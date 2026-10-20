// ge_replay's --extract mode (task 101): one recorded frame as an OBJ scene, its textures by HD pack key and a JSON
// of its draws. What it writes is described in ge_extract.hpp; docs/ge-backend.md, section 7, and docs/developing.md
// say how to run it. Everything it writes is derived from the game's data and belongs under out/.
//
// Conventions, as the framework holds them (ge_state.cpp's matrix upload, ge.vert, vulkan_renderer.cpp's multiply):
// the matrices are 4x4 column-major, element (row, column) at [column * 4 + row], applied to column vectors as M * v,
// so a world-space position is world * (x, y, z, 1) with the translation in [12], [13], [14]. A transformed draw's
// texture coordinates are its vertices' UVs times the texture scale plus the offset (the renderer's uv_transform).
// Sprites are expanded as the Vulkan renderer expands them (the Sprites case of its primitive expansion): the two
// vertices are opposite corners, the other two corners take one's x and the other's y, and all four take the second
// vertex's z, in object space. The GE spans a transformed sprite in screen space after the transform, so a sprite
// is always screen-aligned; the object-space expansion matches it only where the draw's rotation is the camera's.
#include "ge_extract.hpp"

#include "../gpu/ge_names.hpp"
#include "../helpers.hpp"

#include "gpu/texture_decode.hpp"
#include "gpu/texture_pack.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <utility>

namespace pure::extract {
namespace {

namespace gpu = portablekit::gpu;
using Matrix = std::array<float, 16>;
using Vec3 = std::array<float, 3>;

// The HD pack's [options] (hash = xxh64, ignoreAddress = true, ignoreMipmap = true), so the names are its keys.
gpu::TexturePackOptions pack_options() {
    gpu::TexturePackOptions options;
    options.hash = gpu::TexturePackHash::Xxh64;
    options.ignore_address = true;
    options.ignore_mipmap = true;
    return options;
}

// The renderer's max_seen_v for a texture it has not seen before (vulkan_renderer.cpp, drawn_max_v and
// update_max_seen_v): only 512-tall textures drawn in through mode hash fewer rows.
std::uint16_t max_seen_v(const gpu::DrawCall &call) {
    if (call.texture.height != 512u) return 0u;
    if (!call.through) return 512u;
    float max_v = 0.0f;
    for (const gpu::Vertex &vertex : call.vertices) max_v = std::max(max_v, vertex.texcoord[1]);
    const auto drawn = static_cast<std::uint16_t>(std::clamp(max_v, 0.0f, 512.0f));
    return drawn > 0u ? std::max<std::uint16_t>(272u, drawn) : 0u;
}

Vec3 transform(const Matrix &m, const std::array<float, 4> &p) {
    return {m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
            m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]};
}

// The upper 3x3 of view * world with each column scaled to length 1, against the identity: 0 when the draw's
// rotation undoes the camera's, which is what a screen-facing quad looks like.
float facing_error(const Matrix &view, const Matrix &world) {
    float worst = 0.0f;
    for (int column = 0; column < 3; ++column) {
        Vec3 c{};
        for (int row = 0; row < 3; ++row)
            for (int k = 0; k < 3; ++k) c[row] += view[k * 4 + row] * world[column * 4 + k];
        const float length = std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
        if (length == 0.0f) return 2.0f;
        for (int row = 0; row < 3; ++row)
            worst = std::max(worst, std::fabs(c[row] / length - (row == column ? 1.0f : 0.0f)));
    }
    return worst;
}

const char *factor_name(std::uint32_t factor, bool source) {
    static constexpr const char *kNames[] = {"", "", "SA", "1-SA", "DA", "1-DA", "2SA", "1-2SA", "2DA", "1-2DA", "FIX"};
    if (factor == 0u) return source ? "DC" : "SC";
    if (factor == 1u) return source ? "1-DC" : "1-SC";
    return factor < std::size(kNames) ? kNames[factor] : "?";
}

const char *equation_name(std::uint32_t equation) {
    static constexpr const char *kNames[] = {"add", "sub", "rsub", "min", "max", "abs"};
    return equation < std::size(kNames) ? kNames[equation] : "?";
}

const char *compare_name(std::uint32_t function) {
    static constexpr const char *kNames[] = {"NEVER", "ALWAYS", "EQUAL", "NOTEQUAL", "LESS", "LEQUAL", "GREATER", "GEQUAL"};
    return function < std::size(kNames) ? kNames[function] : "?";
}

const char *function_name(std::uint32_t function) {
    static constexpr const char *kNames[] = {"modulate", "decal", "blend", "replace", "add"};
    return function < std::size(kNames) ? kNames[function] : "?";
}

std::string number(float value) {
    if (!std::isfinite(value)) return "null";
    char text[32];
    std::snprintf(text, sizeof text, "%.6g", static_cast<double>(value));
    return text;
}

std::string quoted(const std::string &text) { return "\"" + text + "\""; }

std::string matrix_json(const Matrix &m) {
    std::string out = "[";
    for (std::size_t i = 0; i < m.size(); ++i) out += (i != 0u ? "," : "") + number(m[i]);
    return out + "]";
}

std::string vec_json(const Vec3 &v) { return "[" + number(v[0]) + "," + number(v[1]) + "," + number(v[2]) + "]"; }

// A draw as the files need it: its state in short, and for a transformed draw its triangles in world space.
struct Draw {
    std::size_t index{};   // in the frame, from 1
    std::size_t record{};  // gerec_dump.py's record number
    std::string key;       // the texture's pack key, "untextured", or "nokey_<address>" when it cannot be hashed
    gpu::DrawCall call;    // without its vertices and indices
    std::size_t vertex_count{};
    std::size_t index_count{};
    bool raw{};            // vertices left undecoded (GPU vertex decode): no geometry
    std::vector<Vec3> positions;  // world space (screen space for a through draw), as the faces index them
    std::vector<std::array<float, 2>> uvs;
    std::vector<std::array<std::uint32_t, 3>> faces;
    Vec3 low{}, high{};
    bool bounded{};
    std::size_t colors{};  // distinct vertex colours
    std::uint32_t first_color{};
    float facing{};        // the fraction of its triangles whose eye-space normal lies within 5 degrees of the view axis
};

} // namespace

struct FrameExtract::Impl {
    std::filesystem::path out;
    std::uint32_t frame{};
    std::set<std::string> wanted;
    std::vector<Draw> draws;
    std::unique_ptr<gpu::TextureDumper> dumper;
    std::size_t queued{};  // textures handed to the dumper since it was made
    struct Texture {
        gpu::TextureState state;
        std::vector<std::size_t> draws;
        bool decoded{};
    };
    std::map<std::string, Texture> textures;
    std::size_t skipped_lines{}, skipped_points{};

    void geometry(Draw &draw, const gpu::DrawCall &call) {
        const std::size_t total = call.vertices.size();
        const std::size_t count = call.indices.empty() ? total : call.indices.size();
        const auto at = [&](std::size_t i) -> std::uint32_t {
            const std::size_t mapped = call.indices.empty() ? i : call.indices[i];
            return static_cast<std::uint32_t>(std::min(mapped, total - 1u));
        };
        const auto place = [&](const gpu::Vertex &vertex) {
            draw.positions.push_back(call.through ? Vec3{vertex.position[0], vertex.position[1], vertex.position[2]}
                                                  : transform(call.world, vertex.position));
            const float u = vertex.texcoord[0] * call.texture.scale_u + call.texture.offset_u;
            const float v = vertex.texcoord[1] * call.texture.scale_v + call.texture.offset_v;
            draw.uvs.push_back({u, 1.0f - v});
        };
        const auto face = [&](std::uint32_t a, std::uint32_t b, std::uint32_t c) {
            if (a != b && b != c && a != c) draw.faces.push_back({a, b, c});
        };
        switch (call.primitive) {
        case gpu::PrimitiveType::Triangles:
        case gpu::PrimitiveType::TriangleStrip:
        case gpu::PrimitiveType::TriangleFan:
            for (const gpu::Vertex &vertex : call.vertices) place(vertex);
            if (call.primitive == gpu::PrimitiveType::Triangles) {
                for (std::size_t i = 0; i + 2u < count; i += 3u) face(at(i), at(i + 1u), at(i + 2u));
            } else if (call.primitive == gpu::PrimitiveType::TriangleStrip) {
                for (std::size_t i = 0; i + 2u < count; ++i) {
                    const bool odd = (i & 1u) != 0u;
                    face(at(i), at(odd ? i + 2u : i + 1u), at(odd ? i + 1u : i + 2u));
                }
            } else {
                for (std::size_t i = 1u; i + 1u < count; ++i) face(at(0), at(i), at(i + 1u));
            }
            break;
        case gpu::PrimitiveType::Sprites:
            for (std::size_t i = 0; i + 1u < count; i += 2u) {
                gpu::Vertex a = call.vertices[at(i)];
                const gpu::Vertex &b = call.vertices[at(i + 1u)];
                a.position[2] = b.position[2];
                gpu::Vertex top_right = b, bottom_left = a;
                top_right.position[1] = a.position[1];
                top_right.texcoord[1] = a.texcoord[1];
                bottom_left.position[1] = b.position[1];
                bottom_left.texcoord[1] = b.texcoord[1];
                const auto first = static_cast<std::uint32_t>(draw.positions.size());
                place(a);
                place(top_right);
                place(b);
                place(bottom_left);
                face(first, first + 1u, first + 2u);
                face(first, first + 2u, first + 3u);
            }
            break;
        case gpu::PrimitiveType::Points: ++skipped_points; return;
        default: ++skipped_lines; return;
        }
        std::set<std::uint32_t> colors;
        for (const gpu::Vertex &vertex : call.vertices) colors.insert(vertex.color);
        draw.colors = colors.size();
        draw.first_color = call.vertices.front().color;
        // Bounds of the vertices the faces use; of every vertex when no face is left.
        const auto grow = [&](const Vec3 &p) {
            for (int k = 0; k < 3; ++k) {
                draw.low[k] = draw.bounded ? std::min(draw.low[k], p[k]) : p[k];
                draw.high[k] = draw.bounded ? std::max(draw.high[k], p[k]) : p[k];
            }
            draw.bounded = true;
        };
        if (draw.faces.empty()) {
            for (const Vec3 &p : draw.positions) grow(p);
        } else {
            std::size_t facing = 0u;
            for (const auto &f : draw.faces) {
                for (std::uint32_t i : f) grow(draw.positions[i]);
                if (call.through) continue;
                // The triangle's normal in eye space (the view's rotation applied to the world-space normal).
                const Vec3 &p = draw.positions[f[0]], &q = draw.positions[f[1]], &r = draw.positions[f[2]];
                const Vec3 e{q[0] - p[0], q[1] - p[1], q[2] - p[2]}, g{r[0] - p[0], r[1] - p[1], r[2] - p[2]};
                const Vec3 n{e[1] * g[2] - e[2] * g[1], e[2] * g[0] - e[0] * g[2], e[0] * g[1] - e[1] * g[0]};
                const Matrix &m = call.view;
                const Vec3 eye{m[0] * n[0] + m[4] * n[1] + m[8] * n[2], m[1] * n[0] + m[5] * n[1] + m[9] * n[2],
                               m[2] * n[0] + m[6] * n[1] + m[10] * n[2]};
                const float length = std::sqrt(eye[0] * eye[0] + eye[1] * eye[1] + eye[2] * eye[2]);
                if (length > 0.0f && std::fabs(eye[2]) / length > 0.9962f) ++facing;  // cos 5 degrees
            }
            if (!call.through) draw.facing = static_cast<float>(facing) / static_cast<float>(draw.faces.size());
        }
    }

    void texture(Draw &draw, const gpu::DrawCall &call, const psprecomp::GuestMemory &memory) {
        if (!call.texture.enabled || call.clear_mode) {
            draw.key = "untextured";
            return;
        }
        static const gpu::TexturePackOptions options = pack_options();
        const std::uint16_t seen = max_seen_v(call);
        gpu::TexturePackKey key;
        std::uint32_t covered_width = 0u, covered_height = 0u;
        if (!gpu::compute_texture_pack_key(memory, call.texture, seen, options, key, covered_width, covered_height)) {
            draw.key = "nokey_" + hex(call.texture.address).substr(2);
            return;
        }
        draw.key = gpu::format_texture_pack_key(key);
        auto [it, fresh] = textures.try_emplace(draw.key);
        it->second.draws.push_back(draw.index);
        if (!fresh) return;
        it->second.state = call.texture;
        std::vector<std::uint32_t> pixels;
        if (!gpu::decode_texture(memory, call.texture, pixels) ||
            pixels.size() < static_cast<std::size_t>(call.texture.width) * call.texture.height)
            return;
        it->second.decoded = true;
        // The dumper drops what it is handed beyond 256 waiting images; a fresh one every 128 drains the last.
        if (queued == 128u) {
            dumper.reset();
            queued = 0u;
        }
        if (!dumper) dumper = std::make_unique<gpu::TextureDumper>(out / "textures");
        dumper->dump(memory, call.texture, seen, options, pixels.data());
        ++queued;
    }
};

FrameExtract::FrameExtract(std::filesystem::path out, std::uint32_t frame, std::vector<std::string> keys)
    : impl_(std::make_unique<Impl>()) {
    impl_->out = std::move(out);
    impl_->frame = frame;
    impl_->wanted.insert(keys.begin(), keys.end());
}

FrameExtract::~FrameExtract() = default;

bool FrameExtract::open(std::string &error) {
    std::error_code code;
    std::filesystem::create_directories(impl_->out / "textures", code);
    if (code) error = "cannot make " + (impl_->out / "textures").string() + ": " + code.message();
    return !code;
}

void FrameExtract::draw(std::size_t record, const gpu::DrawCall &call, const psprecomp::GuestMemory &memory) {
    Draw draw;
    draw.index = impl_->draws.size() + 1u;
    draw.record = record;
    draw.vertex_count = call.vertices.empty() ? call.raw_count : call.vertices.size();
    draw.index_count = call.indices.size();
    draw.raw = call.vertices.empty() && call.raw_vertices != nullptr;
    impl_->texture(draw, call, memory);
    if (!call.vertices.empty()) impl_->geometry(draw, call);
    draw.call = call;
    draw.call.vertices.clear();
    draw.call.indices.clear();
    draw.call.raw_vertices = nullptr;
    draw.call.bone_matrices = nullptr;
    impl_->draws.push_back(std::move(draw));
}

bool FrameExtract::finish(std::string &summary, std::string &error) {
    Impl &x = *impl_;
    x.dumper.reset();  // waits for every PNG
    const auto png = [&](const std::string &key) {
        std::error_code ignored;
        return std::filesystem::exists(x.out / "textures" / (key + ".png"), ignored);
    };

    // The frame's usual world matrix (the most frequent among transformed draws), and the distinct view matrices.
    std::map<Matrix, std::size_t> worlds;
    std::vector<Matrix> views;
    std::vector<std::vector<std::pair<std::size_t, std::size_t>>> ranges;
    std::vector<std::size_t> view_of(x.draws.size(), 0u);
    const Draw *first = nullptr;
    for (std::size_t i = 0; i < x.draws.size(); ++i) {
        const Draw &draw = x.draws[i];
        if (draw.call.through) continue;
        if (first == nullptr) first = &draw;
        ++worlds[draw.call.world];
        std::size_t v = std::find(views.begin(), views.end(), draw.call.view) - views.begin();
        if (v == views.size()) {
            views.push_back(draw.call.view);
            ranges.emplace_back();
        }
        view_of[i] = v;
        auto &list = ranges[v];
        if (!list.empty() && list.back().second + 1u == draw.index) list.back().second = draw.index;
        else list.emplace_back(draw.index, draw.index);
    }
    // The camera: the view most draws use (the first transformed draw may be a render-to-texture pass's).
    std::vector<std::size_t> view_draws(views.size(), 0u);
    const Draw *main_first = nullptr;
    for (std::size_t i = 0; i < x.draws.size(); ++i)
        if (!x.draws[i].call.through) ++view_draws[view_of[i]];
    const std::size_t main_view =
        views.empty() ? 0u : std::max_element(view_draws.begin(), view_draws.end()) - view_draws.begin();
    for (std::size_t i = 0; i < x.draws.size() && main_first == nullptr; ++i)
        if (!x.draws[i].call.through && view_of[i] == main_view) main_first = &x.draws[i];
    Matrix usual{};
    std::size_t usual_count = 0u;
    for (const auto &[world, count] : worlds)
        if (count > usual_count) usual = world, usual_count = count;

    // frame.obj and frame.mtl.
    std::ofstream obj(x.out / "frame.obj"), mtl(x.out / "frame.mtl");
    if (!obj || !mtl) {
        error = "cannot write " + (x.out / "frame.obj").string();
        return false;
    }
    obj << "# PureNative --replay --extract " << x.frame << " (task 101): the transformed draws of the frame in world\n"
        << "# space (the world matrix applied, the view left out); one object per draw, named draw_<number>_<key>\n"
        << "mtllib frame.mtl\n";
    std::set<std::string> materials;
    std::size_t base = 1u, objects = 0u, faces = 0u;
    for (const Draw &draw : x.draws) {
        if (draw.call.through || draw.faces.empty()) continue;
        if (!x.wanted.empty() && !x.wanted.count(draw.key)) continue;
        char name[16];
        std::snprintf(name, sizeof name, "draw_%04zu_", draw.index);
        obj << "o " << name << draw.key << "\nusemtl " << draw.key << "\n";
        for (const Vec3 &p : draw.positions) obj << "v " << number(p[0]) << " " << number(p[1]) << " " << number(p[2]) << "\n";
        for (const auto &uv : draw.uvs) obj << "vt " << number(uv[0]) << " " << number(uv[1]) << "\n";
        for (const auto &f : draw.faces) {
            obj << "f";
            for (std::uint32_t i : f) obj << " " << base + i << "/" << base + i;
            obj << "\n";
        }
        base += draw.positions.size();
        faces += draw.faces.size();
        ++objects;
        materials.insert(draw.key);
    }
    mtl << "# PureNative --replay --extract " << x.frame << ": one material per texture key\n";
    for (const std::string &key : materials) {
        mtl << "newmtl " << key << "\nKd 1 1 1\n";
        if (png(key)) mtl << "map_Kd textures/" << key << ".png\nmap_d textures/" << key << ".png\n";
        mtl << "\n";
    }

    // frame.json.
    std::ofstream json(x.out / "frame.json");
    if (!json) {
        error = "cannot write " + (x.out / "frame.json").string();
        return false;
    }
    std::size_t through = 0u, raw = 0u;
    for (const Draw &draw : x.draws) through += draw.call.through, raw += draw.raw;
    json << "{\n  \"frame\": " << x.frame << ",\n  \"draws_total\": " << x.draws.size() << ",\n  \"through_draws\": "
         << through << ",\n  \"raw_vertex_draws\": " << raw << ",\n  \"skipped_lines\": " << x.skipped_lines
         << ",\n  \"skipped_points\": " << x.skipped_points << ",\n  \"obj_objects\": " << objects
         << ",\n  \"obj_faces\": " << faces << ",\n  \"keys_filter\": [";
    {
        std::size_t n = 0u;
        for (const std::string &key : x.wanted) json << (n++ != 0u ? "," : "") << quoted(key);
    }
    json << "],\n  \"matrices\": \"4x4 column-major, element (row, column) at [column * 4 + row], applied as M * v\",\n";
    json << "  \"view\": " << (first ? matrix_json(first->call.view) : "null") << ",\n  \"projection\": "
         << (first ? matrix_json(first->call.projection) : "null") << ",\n  \"main_view\": " << main_view
         << ",\n  \"main_view_matrix\": " << (main_first ? matrix_json(main_first->call.view) : "null")
         << ",\n  \"main_projection\": " << (main_first ? matrix_json(main_first->call.projection) : "null")
         << ",\n  \"usual_world\": " << matrix_json(usual)
         << ",\n  \"views\": [\n";
    for (std::size_t v = 0; v < views.size(); ++v) {
        json << "    {\"view\": " << v << ", \"draw_count\": " << view_draws[v] << ", \"matrix\": " << matrix_json(views[v])
             << ", \"draws\": [";
        for (std::size_t r = 0; r < ranges[v].size(); ++r)
            json << (r != 0u ? "," : "") << "[" << ranges[v][r].first << "," << ranges[v][r].second << "]";
        json << "]}" << (v + 1u < views.size() ? "," : "") << "\n";
    }
    json << "  ],\n  \"textures\": [\n";
    {
        std::size_t n = 0u;
        for (const auto &[key, texture] : x.textures) {
            json << "    {\"key\": " << quoted(key) << ", \"format\": " << quoted(pure::gpu::texture_format_name(texture.state.format))
                 << ", \"width\": " << texture.state.width << ", \"height\": " << texture.state.height
                 << ", \"address\": " << quoted(hex(texture.state.address)) << ", \"png\": " << (png(key) ? "true" : "false")
                 << ", \"draws\": [";
            for (std::size_t d = 0; d < texture.draws.size(); ++d) json << (d != 0u ? "," : "") << texture.draws[d];
            json << "]}" << (++n < x.textures.size() ? "," : "") << "\n";
        }
    }
    json << "  ],\n  \"draws\": [\n";
    for (std::size_t i = 0; i < x.draws.size(); ++i) {
        const Draw &draw = x.draws[i];
        const gpu::DrawCall &c = draw.call;
        const gpu::TextureState &t = c.texture;
        const bool ortho = c.projection[11] == 0.0f && c.projection[15] != 0.0f;
        const float error_value = c.through ? 2.0f : facing_error(c.view, c.world);
        const bool billboard = !c.through && c.world != usual && error_value < 0.02f;
        json << "    {\"index\": " << draw.index << ", \"record\": " << draw.record << ", \"key\": " << quoted(draw.key)
             << ", \"primitive\": " << quoted(pure::gpu::primitive_name(c.primitive)) << ", \"vertices\": "
             << draw.vertex_count << ", \"indices\": " << draw.index_count << ", \"faces\": " << draw.faces.size()
             << ", \"through\": " << (c.through ? "true" : "false") << ", \"clear\": " << (c.clear_mode ? "true" : "false")
             << ", \"raw\": " << (draw.raw ? "true" : "false") << ", \"target\": " << quoted(hex(c.target.color_address))
             << ", \"vertex_type\": " << quoted(hex(c.vertex_type)) << ", \"vertex_address\": " << quoted(hex(c.vertex_address));
        if (t.enabled && !c.clear_mode)
            json << ", \"texture\": {\"address\": " << quoted(hex(t.address)) << ", \"format\": "
                 << quoted(pure::gpu::texture_format_name(t.format)) << ", \"width\": " << t.width << ", \"height\": "
                 << t.height << ", \"levels\": " << t.level_count << ", \"function\": " << quoted(function_name(t.function))
                 << ", \"alpha\": " << (t.alpha_from_texture ? "true" : "false") << ", \"filter\": [" << t.min_filter
                 << "," << t.mag_filter << "], \"wrap\": [" << t.wrap_s << "," << t.wrap_t << "], \"uv_scale\": ["
                 << number(t.scale_u) << "," << number(t.scale_v) << "], \"uv_offset\": [" << number(t.offset_u) << ","
                 << number(t.offset_v) << "], \"map_mode\": " << c.texture_map.map_mode << "}";
        if (draw.bounded)
            json << ", \"space\": " << quoted(c.through ? "screen" : "world") << ", \"min\": " << vec_json(draw.low)
                 << ", \"max\": " << vec_json(draw.high);
        json << ", \"blend\": " << quoted(c.blend.enabled ? std::string(equation_name(c.blend.equation)) + "(" +
                                                                factor_name(c.blend.source_factor, true) + "," +
                                                                factor_name(c.blend.destination_factor, false) + ")" +
                                                                (c.blend.source_factor == 10u || c.blend.destination_factor == 10u
                                                                     ? " fix " + hex(c.blend.fixed_source, 6) + "/" +
                                                                           hex(c.blend.fixed_destination, 6)
                                                                     : "")
                                                          : "off")
             << ", \"alpha_test\": "
             << quoted(c.alpha_test.enabled ? std::string(compare_name(c.alpha_test.function)) + " " +
                                                  hex(c.alpha_test.reference, 2) + " mask " + hex(c.alpha_test.mask, 2)
                                            : "off")
             << ", \"depth\": " << quoted(std::string(c.depth.test_enabled ? compare_name(c.depth.function) : "off") +
                                         (c.depth.write_enabled ? " write" : " no write"))
             << ", \"stencil\": " << quoted(c.stencil.enabled ? std::string(compare_name(c.stencil.function)) + " " +
                                                                  hex(c.stencil.reference, 2)
                                                            : "off")
             << ", \"lighting\": " << (c.lighting_enabled ? "true" : "false") << ", \"fog\": "
             << (c.fog.enabled ? "true" : "false") << ", \"cull\": "
             << quoted(c.culling_enabled ? (c.cull_clockwise ? "cw" : "ccw") : "off") << ", \"vertex_color\": "
             << (c.has_vertex_color ? "true" : "false") << ", \"material_color\": " << quoted(hex(c.material_color))
             << ", \"alpha_write_mask\": " << quoted(hex(c.alpha_write_mask, 2));
        if (draw.colors != 0u)
            json << ", \"colors\": " << draw.colors << ", \"first_color\": " << quoted(hex(draw.first_color));
        if (!c.through)
            json << ", \"orthographic\": " << (ortho ? "true" : "false") << ", \"view\": " << view_of[i]
                 << ", \"usual_world\": " << (c.world == usual ? "true" : "false") << ", \"world\": "
                 << matrix_json(c.world) << ", \"facing_error\": " << number(error_value) << ", \"facing_view\": "
                 << number(draw.facing) << ", \"billboard\": " << (billboard ? "true" : "false");
        json << "}" << (i + 1u < x.draws.size() ? "," : "") << "\n";
    }
    json << "  ]\n}\n";
    if (!obj || !mtl || !json) {
        error = "a write to " + x.out.string() + " failed";
        return false;
    }
    std::size_t pngs = 0u;
    for (const auto &[key, texture] : x.textures) pngs += png(key);
    std::ostringstream line;
    line << "[replay] extracted frame " << x.frame << " to " << x.out.string() << ": " << x.draws.size() << " draws ("
         << through << " through, " << raw << " undecoded, " << x.skipped_lines << " lines and " << x.skipped_points
         << " points skipped), " << objects << " objects and " << faces << " faces in frame.obj, " << x.textures.size()
         << " textures, " << pngs << " PNGs";
    summary = line.str();
    return true;
}

} // namespace pure::extract
