// The models backend (models_backend.hpp; task 102, D-025): figures drawn as 3D models where the game draws flat ones.
//
//   <prefix>_GE_BACKEND=models          the default since task 102 (src/host/pure_main.cpp)
//   <prefix>_GE_MODELS_INNER=<name>     the backend that draws (default metal on macOS, vulkan elsewhere; pure_main
//                                       sets vulkan under the Vulkan shell); models itself is refused
//   <prefix>_CROWD_MODELS=0|1           the Video tab's Crowds and people row (game.crowd_models) for the run
//   <prefix>_TRACE_MODELS=1             `[models] frame F: N draws replaced by M model draws, K quads` every 60
//                                       frames and for each captured frame (the line ends in "(captured)")
//
// Every call goes to the inner backend unchanged while the row is Original (the default). At Models, a draw is
// looked at when it is transformed (not through mode, not a clear), textured, a triangle strip or list of decoded
// vertices, and its texture at most 256 texels on a side: its texture's HD pack key (compute_texture_pack_key with
// the pack's rule: xxh64, the address and the mip levels ignored) is looked up in models/models.ini's [figures], once
// per texture and frame. A draw whose key is there is split into quads (two triangles that share an edge: a strip's
// consecutive pair, degenerate joins skipped, or a list's pair), and each quad is replaced by the model's figures:
//   - the quad's corners in world space (its own world matrix applied); "up" from the corners of its lower v to
//     those of its higher v, or the reverse, whichever points to world +y, its length the quad's height; "right" from
//     its lower u to its higher u, made square to up; front = up x right (D-025's rule), turned round when it points
//     away from the viewer (the eye of the draw's view matrix). Task 102 checked the rule on the pit marshal: it
//     gives +x for draws 149-151, but the game draws 152-154 with u reversed (the same sprite mirrored, which a cut-out
//     drawn without culling shows as a front view from either side), so for them it gives -x and the model would
//     show its back to the race; the viewer's side is what the PSP shows, a front, and +x for all six from the race;
//   - the model (models/README.md: y up, front +z, feet at 0, height 1) is turned so its y is up and its z the front
//     (its x is then up x front), scaled uniformly by the quad's height and stood on the midpoint of the quad's bottom
//     edge; with figures=N, N of them side by side across the quad's width;
//   - drawn as a triangle list with the quad's view, projection, viewport, target, blend, depth, stencil, alpha test,
//     fog and masks, the world matrix the identity (the vertices are in world space), no texture, no lighting, the
//     vertex colours the model's times the quad's tint (its vertex colours' mean, or its material colour), material
//     colour white and culling off (a Blender mesh's winding is not promised; depth sorts the faces).
// The quad itself is not drawn. A draw with no quad (a lone triangle) goes through.
//
// A version 2 model (task 103: joints, weights, clips) is skinned on the CPU for each figure before the placement:
// its clip (the first in the file, or models.ini's clip=NAME) sampled at the figure's time, every joint's local
// transform interpolated between the clip's two keys around it (translation and scale linearly, the rotation
// normalised-linearly), its global the parent's times its own, a vertex the weighted sum of its joints' global x
// inverse bind applied to its rest position. The clip runs on wall time: std::chrono::steady_clock read at each
// begin_frame, the clock advanced by the difference capped at 100 ms (a pause, a stall or the Esc menu does not skip
// it ahead). Each figure's phase is offset by a hash of its quad's place, so the marshals do not wave in unison.
//   <prefix>_MODELS_CLOCK=frames        the clip time is the shown frame / 60 seconds instead (a capture of frame N
//                                       shows the same pose every run)
//   <prefix>_MODELS_SYNC=1              every figure's phase offset 0
// The trace line then ends in `; clip NAME t=SECONDS (animated), skinned in N us` (the first animated figure of the
// frame, the frame's skinning time).
//
// The table is read at start when the row is at Models and again each time the row is set to Models, so a model
// imported again shows at the next switch. models/ is found in the app's Resources (Contents/Resources/models),
// beside the executable (the Windows folder), three levels above it (build/<preset>/bin in a checkout) or under the
// working directory.
#include "models_backend.hpp"

#include "app_paths.hpp"
#include "gpu/texture_pack.hpp"
#include "profile.hpp"
#include "settings/settings.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

namespace pure::models {
namespace {

namespace gpu = portablekit::gpu;
using gpu::DrawCall;
using gpu::GeBackend;
using gpu::GuestMemory;
using Vec3 = std::array<float, 3>;

#if defined(__APPLE__)
constexpr const char *kPlatformInner = "metal";
#else
constexpr const char *kPlatformInner = "vulkan";
#endif
constexpr std::uint32_t kLargestFigureTexture = 256u;  // texels a side: larger textures are not looked up
constexpr std::uint64_t kTraceEvery = 60u;
constexpr double kLargestStep = 0.1;  // seconds: the most the clips' wall clock moves in one frame
// The model draws' vertex type: float positions, 8888 colours, u16 indices, nothing else (no weights to skin).
constexpr std::uint32_t kModelVertexType = (3u << 7) | (7u << 2) | (2u << 11);

Vec3 add(const Vec3 &a, const Vec3 &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }
Vec3 sub(const Vec3 &a, const Vec3 &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
Vec3 scale(const Vec3 &a, float s) { return {a[0] * s, a[1] * s, a[2] * s}; }
float dot(const Vec3 &a, const Vec3 &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
float length(const Vec3 &a) { return std::sqrt(dot(a, a)); }
Vec3 cross(const Vec3 &a, const Vec3 &b) {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}

// M * (p, 1) for a column-major 4x4 (ge_state.hpp's matrices).
Vec3 transform(const std::array<float, 16> &m, const std::array<float, 4> &p) {
    return {m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
            m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]};
}

using Mat4 = std::array<float, 16>;  // column-major

// A joint's local transform: translation, rotation (x, y, z, w), scale.
struct Trs {
    Vec3 t;
    std::array<float, 4> r;
    Vec3 s;
};

struct Joint {
    std::uint16_t parent;  // 0xFFFF for a root
    Trs rest;
    Mat4 inverse_bind;
};

struct Clip {
    std::string name;
    float duration{};
    std::vector<float> times;  // sorted, the first 0
    std::vector<Trs> keys;     // joint j's key k at j * times.size() + k
};

// One .pmdl (models/README.md): positions in the model's frame, ABGR colours, triangles; version 2 adds the skin.
struct Model {
    std::vector<Vec3> positions;
    std::vector<std::uint32_t> colors;
    std::vector<std::uint16_t> indices;
    std::vector<Joint> joints;                           // empty for a static model
    std::vector<std::uint16_t> order;                    // the joints, parents first
    std::vector<std::array<std::uint8_t, 4>> joint_of;  // per vertex
    std::vector<std::array<float, 4>> weights;          // per vertex, summing to 1
    std::vector<Clip> clips;
};

struct Figure {
    std::shared_ptr<const Model> model;
    std::string file;
    std::uint32_t figures{1u};
    std::size_t clip{0u};  // the clip it plays (models.ini's clip=NAME; the first by default)
};

Mat4 multiply(const Mat4 &a, const Mat4 &b) {
    Mat4 out{};
    for (std::size_t c = 0; c < 4u; ++c)
        for (std::size_t r = 0; r < 4u; ++r)
            out[c * 4u + r] = a[r] * b[c * 4u] + a[4u + r] * b[c * 4u + 1u] + a[8u + r] * b[c * 4u + 2u] +
                              a[12u + r] * b[c * 4u + 3u];
    return out;
}

// translation x rotation x scale (glTF's order).
Mat4 matrix_of(const Trs &p) {
    const auto [x, y, z, w] = p.r;
    const float r[9] = {1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
                        2 * (x * y - z * w),     1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
                        2 * (x * z + y * w),     2 * (y * z - x * w),     1 - 2 * (x * x + y * y)};
    return {r[0] * p.s[0], r[1] * p.s[0], r[2] * p.s[0], 0.0f, r[3] * p.s[1], r[4] * p.s[1], r[5] * p.s[1], 0.0f,
            r[6] * p.s[2], r[7] * p.s[2], r[8] * p.s[2], 0.0f, p.t[0],        p.t[1],        p.t[2],        1.0f};
}

// Between two keys: translation and scale linearly, the rotation normalised-linearly on the short way round.
Trs mix(const Trs &a, const Trs &b, float f) {
    Trs out{};
    float d = 0.0f;
    for (std::size_t i = 0; i < 4u; ++i) d += a.r[i] * b.r[i];
    const float sign = d < 0.0f ? -1.0f : 1.0f;
    float norm = 0.0f;
    for (std::size_t i = 0; i < 4u; ++i) {
        out.r[i] = a.r[i] + (sign * b.r[i] - a.r[i]) * f;
        norm += out.r[i] * out.r[i];
    }
    norm = norm > 0.0f ? 1.0f / std::sqrt(norm) : 0.0f;
    for (float &x : out.r) x *= norm;
    for (std::size_t i = 0; i < 3u; ++i) {
        out.t[i] = a.t[i] + (b.t[i] - a.t[i]) * f;
        out.s[i] = a.s[i] + (b.s[i] - a.s[i]) * f;
    }
    return out;
}

// The skin matrices (global x inverse bind, one per joint) of the clip at `t` seconds into it.
void pose(const Model &model, const Clip &clip, float t, std::vector<Mat4> &world, std::vector<Mat4> &skin) {
    const std::size_t joints = model.joints.size(), keys = clip.times.size();
    std::size_t k = 0u;
    float f = 0.0f;
    if (keys > 1u) {
        t = std::clamp(t, 0.0f, clip.times.back());
        k = static_cast<std::size_t>(std::upper_bound(clip.times.begin(), clip.times.end(), t) - clip.times.begin());
        k = std::min(k == 0u ? 0u : k - 1u, keys - 2u);
        const float span = clip.times[k + 1u] - clip.times[k];
        f = span > 0.0f ? std::clamp((t - clip.times[k]) / span, 0.0f, 1.0f) : 0.0f;
    }
    world.resize(joints);
    skin.resize(joints);
    for (const std::uint16_t j : model.order) {
        const Trs &a = clip.keys[j * keys + k];
        const Mat4 local = matrix_of(keys > 1u ? mix(a, clip.keys[j * keys + k + 1u], f) : a);
        const std::uint16_t parent = model.joints[j].parent;
        world[j] = parent == 0xFFFFu ? local : multiply(world[parent], local);
        skin[j] = multiply(world[j], model.joints[j].inverse_bind);
    }
}

bool read_model(const std::filesystem::path &path, Model &model, std::string &error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "cannot read it";
        return false;
    }
    const std::vector<char> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    std::uint32_t header[3]{};
    if (bytes.size() < 16u || std::memcmp(bytes.data(), "PMDL", 4) != 0) {
        error = "not a .pmdl (no PMDL magic)";
        return false;
    }
    std::memcpy(header, bytes.data() + 4, sizeof header);
    const auto [version, vertices, indices] = std::tuple(header[0], header[1], header[2]);
    const std::size_t want = 16u + static_cast<std::size_t>(vertices) * 16u + static_cast<std::size_t>(indices) * 2u;
    if ((version != 1u && version != 2u) || vertices == 0u || vertices > 65535u || indices == 0u || indices % 3u != 0u ||
        bytes.size() < want) {
        error = "version " + std::to_string(version) + ", " + std::to_string(vertices) + " vertices, " +
                std::to_string(indices) + " indices in " + std::to_string(bytes.size()) + " bytes: not a model";
        return false;
    }
    model.positions.resize(vertices);
    model.colors.resize(vertices);
    model.indices.resize(indices);
    const char *at = bytes.data() + 16;
    std::memcpy(model.positions.data(), at, vertices * 12u);
    at += vertices * 12u;
    std::memcpy(model.colors.data(), at, vertices * 4u);
    at += vertices * 4u;
    std::memcpy(model.indices.data(), at, indices * 2u);
    for (const std::uint16_t index : model.indices)
        if (index >= vertices) {
            error = "an index past the vertices";
            return false;
        }
    if (version == 1u) return true;
    // Version 2: the joints, each vertex's weights, the clips (models/README.md).
    std::size_t offset = want;
    const auto take = [&](void *out, std::size_t size) {
        if (offset + size > bytes.size()) return false;
        std::memcpy(out, bytes.data() + offset, size);
        offset += size;
        return true;
    };
    const auto bad = [&](const std::string &what) {
        error = "version 2: " + what;
        model.joints.clear();
        return false;
    };
    std::uint32_t joints = 0u, clips = 0u;
    if (!take(&joints, 4u)) return bad("no joint count");
    if (joints == 0u) return true;  // static: as version 1
    if (joints > 255u) return bad(std::to_string(joints) + " joints, over 255");
    model.joints.resize(joints);
    for (Joint &joint : model.joints) {
        if (!take(&joint.parent, 2u) || !take(joint.rest.t.data(), 12u) || !take(joint.rest.r.data(), 16u) ||
            !take(joint.rest.s.data(), 12u) || !take(joint.inverse_bind.data(), 64u))
            return bad("cut short in the joints");
        if (joint.parent != 0xFFFFu && joint.parent >= joints) return bad("a joint's parent past the joints");
    }
    model.joint_of.resize(vertices);
    model.weights.resize(vertices);
    for (std::uint32_t i = 0; i < vertices; ++i) {
        if (!take(model.joint_of[i].data(), 4u) || !take(model.weights[i].data(), 16u))
            return bad("cut short in the weights");
        for (std::size_t c = 0; c < 4u; ++c)
            if (model.weights[i][c] != 0.0f && model.joint_of[i][c] >= joints) return bad("a weight's joint past the joints");
    }
    if (!take(&clips, 4u) || clips > 1024u) return bad("no clip count");
    model.clips.resize(clips);
    for (Clip &clip : model.clips) {
        std::uint32_t name = 0u, keys = 0u;
        if (!take(&name, 4u) || name > 1024u) return bad("cut short in a clip's name");
        clip.name.resize(name);
        if (!take(clip.name.data(), name) || !take(&clip.duration, 4u) || !take(&keys, 4u) || keys == 0u ||
            keys > 1000000u)
            return bad("cut short in clip " + clip.name);
        clip.times.resize(keys);
        clip.keys.resize(static_cast<std::size_t>(joints) * keys);
        if (!take(clip.times.data(), keys * 4u)) return bad("cut short in clip " + clip.name + "'s times");
        for (Trs &key : clip.keys)
            if (!take(key.t.data(), 12u) || !take(key.r.data(), 16u) || !take(key.s.data(), 12u))
                return bad("cut short in clip " + clip.name + "'s keys");
        if (clip.times.front() != 0.0f || !std::is_sorted(clip.times.begin(), clip.times.end()) ||
            !(clip.duration > 0.0f))
            return bad("clip " + clip.name + "'s times are not sorted from 0 or its duration is not above 0");
    }
    // The order the globals are computed in: parents first.
    std::vector<bool> done(joints);
    while (model.order.size() < joints) {
        const std::size_t before = model.order.size();
        for (std::uint16_t j = 0; j < joints; ++j) {
            const std::uint16_t parent = model.joints[j].parent;
            if (!done[j] && (parent == 0xFFFFu || done[parent])) model.order.push_back(j), done[j] = true;
        }
        if (model.order.size() == before) return bad("the joints' parents form a loop");
    }
    return true;
}

// models/: the app's Resources, beside the executable, three levels above it, the working directory's.
std::filesystem::path find_models_directory() {
    std::vector<std::filesystem::path> candidates;
    const std::filesystem::path exe = portablekit::executable_directory();
    if (!exe.empty()) {
        candidates.push_back(exe / ".." / "Resources" / "models");
        candidates.push_back(exe / "models");
        candidates.push_back(exe / ".." / ".." / ".." / "models");
    }
    candidates.emplace_back("models");
    for (const std::filesystem::path &candidate : candidates) {
        std::error_code ignored;
        if (std::filesystem::is_regular_file(candidate / "models.ini", ignored)) return candidate.lexically_normal();
    }
    return {};
}

std::string trim(std::string text) {
    const auto first = text.find_first_not_of(" \t\r");
    if (first == std::string::npos) return {};
    const auto last = text.find_last_not_of(" \t\r");
    return text.substr(first, last - first + 1u);
}

std::string lower(std::string text) {
    for (char &c : text) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return text;
}

// models.ini's [figures]: key -> figure. Empty, with the reason printed, when there is none.
std::unordered_map<std::string, Figure> read_table() {
    std::unordered_map<std::string, Figure> table;
    const std::filesystem::path directory = find_models_directory();
    if (directory.empty()) {
        std::cout << "[models] no models/models.ini (in the app's Resources, beside the executable or in the "
                     "checkout): the figures stay flat\n";
        return table;
    }
    const std::filesystem::path ini = directory / "models.ini";
    std::ifstream in(ini);
    std::map<std::string, std::shared_ptr<const Model>> models;
    std::string line, section;
    int number = 0, problems = 0;
    while (std::getline(in, line)) {
        ++number;
        if (const auto comment = line.find_first_of(";#"); comment != std::string::npos) line.erase(comment);
        line = trim(line);
        if (line.empty()) continue;
        if (line.front() == '[') {
            section = lower(trim(line.substr(1u, line.find(']') - 1u)));
            continue;
        }
        if (section != "figures") continue;
        const auto equals = line.find('=');
        std::istringstream words(equals == std::string::npos ? std::string{} : line.substr(equals + 1u));
        const std::string key = lower(trim(line.substr(0u, equals)));
        std::string file, word;
        words >> file;
        std::uint32_t figures = 1u;
        std::string clip;
        while (words >> word)
            if (word.rfind("figures=", 0) == 0) figures = static_cast<std::uint32_t>(std::strtoul(word.c_str() + 8, nullptr, 10));
            else if (word.rfind("clip=", 0) == 0) clip = word.substr(5u);
        if (key.size() != 24u || key.find_first_not_of("0123456789abcdef") != std::string::npos || file.empty() ||
            figures == 0u || figures > 64u) {
            std::cout << "[models] " << ini.string() << ":" << number << ": not `<24 hex digits> = <file>.pmdl "
                      << "[figures=1..64] [clip=NAME]`; left out\n";
            ++problems;
            continue;
        }
        auto found = models.find(file);
        if (found == models.end()) {
            auto model = std::make_shared<Model>();
            std::string error;
            if (!read_model(directory / file, *model, error)) {
                std::cout << "[models] " << (directory / file).string() << ": " << error << "; its keys are left out\n";
                model.reset();
                ++problems;
            }
            found = models.emplace(file, std::move(model)).first;
        }
        if (!found->second) continue;
        std::size_t chosen = 0u;
        if (!clip.empty()) {
            const std::vector<Clip> &clips = found->second->clips;
            const auto named = std::find_if(clips.begin(), clips.end(), [&](const Clip &c) { return c.name == clip; });
            if (named != clips.end()) {
                chosen = static_cast<std::size_t>(named - clips.begin());
            } else {
                std::cout << "[models] " << ini.string() << ":" << number << ": " << file << " has no clip " << clip
                          << (clips.empty() ? " (it has none: it stands still)" : "; it plays " + clips.front().name)
                          << "\n";
                ++problems;
            }
        }
        table[key] = Figure{found->second, file, figures, chosen};
    }
    std::cout << "[models] " << ini.string() << ": " << table.size() << " keys, " << models.size() << " model"
              << (models.size() == 1u ? "" : "s");
    const char *separator = " (";
    for (const auto &[file, model] : models) {
        if (!model) continue;
        std::cout << separator << file << ": " << model->positions.size() << " vertices, " << model->indices.size() / 3u
                  << " triangles";
        if (!model->joints.empty()) {
            std::cout << ", " << model->joints.size() << " joints, " << model->clips.size() << " clip"
                      << (model->clips.size() == 1u ? "" : "s");
            for (const Clip &clip : model->clips)
                std::cout << " " << clip.name << " (" << clip.duration << " s, " << clip.times.size() << " keys)";
        }
        separator = "; ";
    }
    std::cout << (*separator == ';' ? ")" : "") << (problems != 0 ? ", with problems above" : "") << "\n";
    return table;
}

// The HD pack's [options] (hash = xxh64, ignoreAddress = true, ignoreMipmap = true): the keys models.ini holds.
const gpu::TexturePackOptions &pack_options() {
    static const gpu::TexturePackOptions options = [] {
        gpu::TexturePackOptions o;
        o.hash = gpu::TexturePackHash::Xxh64;
        o.ignore_address = true;
        o.ignore_mipmap = true;
        return o;
    }();
    return options;
}

struct Corner {
    Vec3 world;
    float u, v;
};

// The per-channel product of two ABGR words.
std::uint32_t modulate(std::uint32_t a, std::uint32_t b) {
    std::uint32_t out = 0u;
    for (std::uint32_t shift = 0u; shift < 32u; shift += 8u) {
        const std::uint32_t x = (a >> shift) & 0xFFu, y = (b >> shift) & 0xFFu;
        out |= ((x * y + 127u) / 255u) << shift;
    }
    return out;
}

class ModelsBackend final : public WrappingBackend {
public:
    ModelsBackend(std::unique_ptr<GeBackend> inner, std::string inner_name)
        : inner_(std::move(inner)), inner_name_(std::move(inner_name)) {}
    ~ModelsBackend() override { shutdown(); }

    GeBackend *inner() const noexcept override { return inner_.get(); }

    bool needs_window() const noexcept override { return inner_->needs_window(); }

    bool initialize(const gpu::BackendConfig &config, std::string &error) override {
        if (!inner_->initialize(config, error)) return false;
        initialized_ = true;
        trace_ = portablekit::env("TRACE_MODELS") != nullptr;
        const char *clock = portablekit::env("MODELS_CLOCK");
        const char *sync = portablekit::env("MODELS_SYNC");
        clock_frames_ = clock != nullptr && std::strcmp(clock, "frames") == 0;
        sync_ = sync != nullptr && *sync != '\0' && std::strcmp(sync, "0") != 0;
        if (clock_frames_)
            std::cout << "[models] " << portablekit::env_name("MODELS_CLOCK")
                      << "=frames: the clips run on the shown frame / 60 s, not wall time\n";
        if (sync_) std::cout << "[models] " << portablekit::env_name("MODELS_SYNC") << "=1: every figure's phase 0\n";
        read_option(true);
        return true;
    }

    void shutdown() override {
        if (!initialized_) return;
        initialized_ = false;
        inner_->shutdown();
    }

    void begin_frame() override {
        read_option(false);
        seen_.clear();
        advance_clock();
        inner_->begin_frame();
    }

    void begin_display_list() override { inner_->begin_display_list(); }
    bool gpu_decode() const override { return inner_->gpu_decode(); }
    bool check_gpu_decode() const override { return inner_->check_gpu_decode(); }

    void submit(const DrawCall &call, const GuestMemory &memory) override {
        if (!on_ || table_.empty() || !candidate(call)) {
            inner_->submit(call, memory);
            return;
        }
        const Figure *figure = lookup(call, memory);
        if (figure == nullptr || !replace(call, *figure, memory)) inner_->submit(call, memory);
    }

    void block_transfer(const gpu::BlockTransfer &transfer, GuestMemory &memory) override {
        inner_->block_transfer(transfer, memory);
    }
    void write_back_frame(GuestMemory &memory) override { inner_->write_back_frame(memory); }
    void read_back_framebuffer(std::uint32_t address, GuestMemory &memory) override {
        inner_->read_back_framebuffer(address, memory);
    }
    bool write_back_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                          GuestMemory &memory, const char *why) override {
        return inner_->write_back_depth(color_address, depth_address, depth_stride, memory, why);
    }
    void upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                      std::uint32_t height, std::uint32_t stride) override {
        inner_->upload_frame(display_address, pixels, width, height, stride);
    }

    // The frame ends here: its counts become the shown frame's.
    gpu::PresentedImage present_image(std::uint32_t display_address) override {
        const gpu::PresentedImage image = inner_->present_image(display_address);
        shown_ = counts_;
        shown_frame_ = inner_->frames_presented();
        counts_ = {};
        if (trace_ && shown_frame_ % kTraceEvery == 0u) report("");
        return image;
    }

    bool capture_frame(const std::string &path) override {
        if (trace_) report(" (captured)");
        return inner_->capture_frame(path);
    }
    std::uint64_t draws_submitted() const noexcept override { return inner_->draws_submitted(); }
    std::uint64_t frames_presented() const noexcept override { return inner_->frames_presented(); }
    bool supports_internal_scale() const noexcept override { return inner_->supports_internal_scale(); }
    void set_internal_scale(std::uint32_t setting) override { inner_->set_internal_scale(setting); }
    std::array<std::uint32_t, 2> target_size() const noexcept override { return inner_->target_size(); }

private:
    struct Counts {
        std::uint64_t replaced{}, model_draws{}, quads{};
        const Clip *clip{};      // the first animated figure's clip and time
        double clip_time{};
        double skin_seconds{};  // the frame's skinning
    };

    // The clips' clock, once a frame: wall time, each step capped at kLargestStep, or the shown frame / 60.
    void advance_clock() {
        if (clock_frames_) {
            clock_seconds_ = static_cast<double>(shown_frame_) / 60.0;
            return;
        }
        const auto now = std::chrono::steady_clock::now();
        if (ticking_)
            clock_seconds_ += std::min(std::chrono::duration<double>(now - last_tick_).count(), kLargestStep);
        last_tick_ = now;
        ticking_ = true;
    }

    // A figure's phase, 0 to 1, from its place (splitmix64 of the key): 0 for all with MODELS_SYNC.
    double phase_of(std::uint64_t key) const {
        if (sync_) return 0.0;
        key += 0x9E3779B97F4A7C15ull;
        key = (key ^ (key >> 30)) * 0xBF58476D1CE4E5B9ull;
        key = (key ^ (key >> 27)) * 0x94D049BB133111EBull;
        key ^= key >> 31;
        return static_cast<double>(key >> 11) * 0x1.0p-53;
    }

    // The model's positions skinned for this figure (into skinned_), or its rest positions when it is static.
    const std::vector<Vec3> &positions_of(const Figure &figure, std::uint64_t place) {
        const Model &model = *figure.model;
        if (model.joints.empty() || model.clips.empty()) return model.positions;
        const auto start = std::chrono::steady_clock::now();
        const Clip &clip = model.clips[std::min(figure.clip, model.clips.size() - 1u)];
        const double duration = static_cast<double>(clip.duration);
        const float t = static_cast<float>(std::fmod(clock_seconds_ + phase_of(place) * duration, duration));
        pose(model, clip, t, world_, skin_);
        skinned_.resize(model.positions.size());
        for (std::size_t i = 0; i < model.positions.size(); ++i) {
            const Vec3 &p = model.positions[i];
            const std::array<float, 4> rest{p[0], p[1], p[2], 1.0f};
            Vec3 sum{};
            for (std::size_t c = 0; c < 4u; ++c) {
                const float w = model.weights[i][c];
                if (w != 0.0f) sum = add(sum, scale(transform(skin_[model.joint_of[i][c]], rest), w));
            }
            skinned_[i] = sum;
        }
        if (counts_.clip == nullptr) counts_.clip = &clip, counts_.clip_time = t;
        counts_.skin_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        return skinned_;
    }

    // The row, once a frame (never per draw): the table read whenever it turns to Models.
    void read_option(bool at_start) {
        const bool on = portablekit::settings::game_option("crowd_models") == 1u;
        if (on != on_) sides_.clear();  // a fresh first sight after a switch; the map is otherwise a few hundred places
        if (on && !on_) {
            table_ = read_table();
            std::cout << "[pure] crowd models: on (game.crowd_models), drawn by " << inner_name_ << "\n";
        } else if (at_start && !on) {
            std::cout << "[pure] crowd models: off\n";
        }
        on_ = on;
    }

    void report(const char *what) const {
        std::cout << "[models] frame " << shown_frame_ << ": " << shown_.replaced << " draws replaced by "
                  << shown_.model_draws << " model draws, " << shown_.quads << " quads" << what;
        if (shown_.clip != nullptr)
            std::cout << "; clip " << shown_.clip->name << " t=" << shown_.clip_time << " (animated), skinned in "
                      << static_cast<long>(shown_.skin_seconds * 1e6) << " us";
        std::cout << "\n";
    }

    static bool candidate(const DrawCall &call) {
        return !call.through && !call.clear_mode && call.texture.enabled && !call.vertices.empty() &&
               (call.primitive == gpu::PrimitiveType::TriangleStrip ||
                call.primitive == gpu::PrimitiveType::Triangles) &&
               call.texture.width <= kLargestFigureTexture && call.texture.height <= kLargestFigureTexture;
    }

    // The figure for the draw's texture, its key computed once per texture and frame.
    const Figure *lookup(const DrawCall &call, const GuestMemory &memory) {
        const gpu::TextureState &t = call.texture;
        const auto key = std::tuple(t.address, t.clut_address, t.clut_format_word,
                                    (static_cast<std::uint32_t>(t.format) << 24) | (t.width << 12) | t.height);
        if (const auto found = seen_.find(key); found != seen_.end()) return found->second;
        const Figure *figure = nullptr;
        gpu::TexturePackKey pack_key;
        std::uint32_t covered_width = 0u, covered_height = 0u;
        // The renderer's max_seen_v for a transformed draw (src/tools/ge_extract.cpp, max_seen_v).
        const std::uint16_t max_v = t.height == 512u ? 512u : 0u;
        if (gpu::compute_texture_pack_key(memory, t, max_v, pack_options(), pack_key, covered_width, covered_height)) {
            const auto found = table_.find(gpu::format_texture_pack_key(pack_key));
            if (found != table_.end()) figure = &found->second;
        }
        seen_.emplace(key, figure);
        return figure;
    }

    // The draw's vertex number `n` (through its indices, when it has them).
    std::uint32_t vertex_at(const DrawCall &call, std::size_t n) const {
        return call.indices.empty() ? static_cast<std::uint32_t>(n) : call.indices[n];
    }

    bool degenerate(const DrawCall &call, std::uint32_t a, std::uint32_t b, std::uint32_t c) const {
        const auto &p = call.vertices;
        if (a >= p.size() || b >= p.size() || c >= p.size()) return true;
        const Vec3 pa{p[a].position[0], p[a].position[1], p[a].position[2]};
        const Vec3 pb{p[b].position[0], p[b].position[1], p[b].position[2]};
        const Vec3 pc{p[c].position[0], p[c].position[1], p[c].position[2]};
        const Vec3 n = cross(sub(pb, pa), sub(pc, pa));
        return dot(n, n) <= 1e-18f;
    }

    // The quads: four vertex numbers each.
    std::vector<std::array<std::uint32_t, 4>> quads_of(const DrawCall &call) const {
        std::vector<std::array<std::uint32_t, 4>> quads;
        const std::size_t count = call.indices.empty() ? call.vertices.size() : call.indices.size();
        if (call.primitive == gpu::PrimitiveType::TriangleStrip) {
            // Triangles n, n+1, n+2. Two non-degenerate ones in a row share an edge: the quad n..n+3.
            std::size_t n = 0u;
            while (n + 3u < count) {
                const std::uint32_t a = vertex_at(call, n), b = vertex_at(call, n + 1u), c = vertex_at(call, n + 2u),
                                    d = vertex_at(call, n + 3u);
                if (!degenerate(call, a, b, c) && !degenerate(call, b, c, d)) {
                    quads.push_back({a, b, c, d});
                    n += 2u;
                } else {
                    n += 1u;
                }
            }
        } else {
            // A list: triangles 2k and 2k+1, when they share two vertices.
            for (std::size_t n = 0u; n + 6u <= count; n += 6u) {
                const std::array<std::uint32_t, 3> s{vertex_at(call, n), vertex_at(call, n + 1u), vertex_at(call, n + 2u)};
                const std::array<std::uint32_t, 3> t{vertex_at(call, n + 3u), vertex_at(call, n + 4u),
                                                     vertex_at(call, n + 5u)};
                std::array<std::uint32_t, 4> quad{s[0], s[1], s[2], 0u};
                int shared = 0;
                bool extra = false;
                for (const std::uint32_t x : t) {
                    if (x == s[0] || x == s[1] || x == s[2]) ++shared;
                    else if (!extra) quad[3] = x, extra = true;
                }
                if (shared == 2 && extra) quads.push_back(quad);
            }
        }
        return quads;
    }

    // Draws the figures for each of the draw's quads; false (and nothing drawn) when it has none.
    bool replace(const DrawCall &call, const Figure &figure, const GuestMemory &memory) {
        const std::vector<std::array<std::uint32_t, 4>> quads = quads_of(call);
        if (quads.empty()) return false;
        const Model &model = *figure.model;
        // Everything the quad is drawn with (view, projection, viewport, target, blend, depth, stencil, alpha test,
        // fog, masks); then what a model draw changes.
        DrawCall draw = call;
        draw.raw_vertices = nullptr;
        draw.raw_count = 0u;
        draw.raw_stride = 0u;
        draw.bone_matrices = nullptr;
        draw.texture.enabled = false;
        draw.primitive = gpu::PrimitiveType::Triangles;
        draw.through = false;
        draw.clear_mode = false;
        draw.culling_enabled = false;
        draw.vertex_type = kModelVertexType;
        draw.vertex_address = 0u;
        draw.index_address = 0u;
        draw.primitive_count = static_cast<std::uint32_t>(model.indices.size() / 3u);
        draw.material_color = 0xFFFFFFFFu;
        draw.lighting_enabled = false;
        draw.has_vertex_color = true;
        draw.world = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f};
        draw.indices = model.indices;
        draw.vertices.clear();
        // The viewer: the eye of the view matrix (world to eye, column-major), -R^T t.
        const std::array<float, 16> &v = call.view;
        const Vec3 eye{-(v[0] * v[12] + v[1] * v[13] + v[2] * v[14]), -(v[4] * v[12] + v[5] * v[13] + v[6] * v[14]),
                       -(v[8] * v[12] + v[9] * v[13] + v[10] * v[14])};
        std::uint64_t drawn = 0u;
        for (const auto &quad : quads) {
            std::array<Corner, 4> corners{};
            std::array<std::uint32_t, 4> sum{};
            for (std::size_t i = 0; i < 4u; ++i) {
                const gpu::Vertex &vertex = call.vertices[quad[i]];
                corners[i] = {transform(call.world, vertex.position), vertex.texcoord[0], vertex.texcoord[1]};
                const std::uint32_t color = call.has_vertex_color ? vertex.color : call.material_color;
                for (std::uint32_t c = 0; c < 4u; ++c) sum[c] += (color >> (8u * c)) & 0xFFu;
            }
            std::uint32_t tint = 0u;
            for (std::uint32_t c = 0; c < 4u; ++c) tint |= ((sum[c] + 2u) / 4u) << (8u * c);
            Vec3 base, up_axis, right_axis, front;
            float height = 0.0f, width = 0.0f;
            if (!place(corners, base, up_axis, right_axis, front, height, width)) continue;
            // The side a quad shows is the one the camera saw it from first, remembered by the quad's place (the
            // review of task 102, D-025 as amended): the PSP draws a cut-out from both sides and the game mirrors u
            // on half of the marshals, so neither the UV rule alone nor the viewer's side each frame gives a figure
            // that both faces the race and stands still; a figure that turned round as the ship passed its plane
            // would be seen doing it. The first sight is from the race's side for everything by the track.
            const std::uint64_t place_key = quantise(base);
            auto side = sides_.find(place_key);
            if (side == sides_.end()) side = sides_.emplace(place_key, dot(front, sub(eye, base)) < 0.0f).first;
            if (side->second) front = scale(front, -1.0f);
            // The model's x, y, z in world space: x = up x front (= -right), y = up, z = front.
            const Vec3 x_axis = cross(up_axis, front);
            for (std::uint32_t f = 0; f < figure.figures; ++f) {
                const float across = (static_cast<float>(f) + 0.5f) / static_cast<float>(figure.figures) - 0.5f;
                const Vec3 foot = add(base, scale(right_axis, across * width));
                const std::vector<Vec3> &positions = positions_of(figure, place_key * 64u + f);
                draw.vertices.resize(positions.size());
                for (std::size_t i = 0; i < positions.size(); ++i) {
                    const Vec3 &p = positions[i];
                    const Vec3 at = add(foot, add(scale(x_axis, p[0] * height),
                                                  add(scale(up_axis, p[1] * height), scale(front, p[2] * height))));
                    gpu::Vertex &out = draw.vertices[i];
                    out.position = {at[0], at[1], at[2], 1.0f};
                    out.normal = {0.0f, 0.0f, 0.0f};
                    out.texcoord = {0.0f, 0.0f};
                    out.color = modulate(model.colors[i], tint);
                }
                inner_->submit(draw, memory);
                ++drawn;
            }
            ++counts_.quads;
        }
        if (drawn == 0u) return false;
        ++counts_.replaced;
        counts_.model_draws += drawn;
        return true;
    }

    // A quad's placement from its corners (D-025): false when its UVs or shape say nothing.
    // A quad's place as a map key: its base to a tenth of a unit on each axis (the booths' quads are a unit apart).
    static std::uint64_t quantise(const Vec3 &p) {
        const auto q = [](float v) { return static_cast<std::uint64_t>(static_cast<std::int64_t>(std::lround(v * 10.0f)) & 0x1FFFFF); };
        return q(p[0]) << 42 | q(p[1]) << 21 | q(p[2]);
    }
    static bool place(const std::array<Corner, 4> &corners, Vec3 &base, Vec3 &up, Vec3 &right, Vec3 &front,
                      float &height, float &width) {
        float u_low = corners[0].u, u_high = u_low, v_low = corners[0].v, v_high = v_low;
        for (const Corner &c : corners) {
            u_low = std::min(u_low, c.u), u_high = std::max(u_high, c.u);
            v_low = std::min(v_low, c.v), v_high = std::max(v_high, c.v);
        }
        const float u_mid = 0.5f * (u_low + u_high), v_mid = 0.5f * (v_low + v_high);
        Vec3 u_lo{}, u_hi{}, v_lo{}, v_hi{};
        int n_ul = 0, n_uh = 0, n_vl = 0, n_vh = 0;
        for (const Corner &c : corners) {
            if (c.u > u_mid) u_hi = add(u_hi, c.world), ++n_uh;
            else u_lo = add(u_lo, c.world), ++n_ul;
            if (c.v > v_mid) v_hi = add(v_hi, c.world), ++n_vh;
            else v_lo = add(v_lo, c.world), ++n_vl;
        }
        if (n_ul == 0 || n_uh == 0 || n_vl == 0 || n_vh == 0) return false;
        u_lo = scale(u_lo, 1.0f / static_cast<float>(n_ul)), u_hi = scale(u_hi, 1.0f / static_cast<float>(n_uh));
        v_lo = scale(v_lo, 1.0f / static_cast<float>(n_vl)), v_hi = scale(v_hi, 1.0f / static_cast<float>(n_vh));
        // Up along v, toward world +y; the bottom edge is the v side it starts from.
        Vec3 along_v = sub(v_hi, v_lo);
        Vec3 bottom = v_lo;
        if (along_v[1] < 0.0f) along_v = scale(along_v, -1.0f), bottom = v_hi;
        height = length(along_v);
        if (height <= 1e-6f) return false;
        up = scale(along_v, 1.0f / height);
        Vec3 along_u = sub(u_hi, u_lo);
        along_u = sub(along_u, scale(up, dot(along_u, up)));
        width = length(along_u);
        if (width <= 1e-6f) return false;
        right = scale(along_u, 1.0f / width);
        front = cross(up, right);
        base = bottom;
        return true;
    }

    std::unique_ptr<GeBackend> inner_;
    std::string inner_name_;
    bool initialized_{};
    bool trace_{};
    bool on_{};
    std::unordered_map<std::string, Figure> table_;
    std::unordered_map<std::uint64_t, bool> sides_;  // a quad's place -> its front turned round (first sight)
    // This frame's lookups: (address, palette address, palette word, format and size) -> figure or null.
    std::map<std::tuple<std::uint32_t, std::uint32_t, std::uint32_t, std::uint32_t>, const Figure *> seen_;
    Counts counts_{};
    Counts shown_{};
    std::uint64_t shown_frame_{};
    // The clips' clock (advance_clock) and the skinning's scratch.
    bool clock_frames_{};
    bool sync_{};
    bool ticking_{};
    double clock_seconds_{};
    std::chrono::steady_clock::time_point last_tick_{};
    std::vector<Mat4> world_, skin_;
    std::vector<Vec3> skinned_;
};

std::unique_ptr<GeBackend> make_models_backend() {
    const char *named = portablekit::env("GE_MODELS_INNER");
    std::string inner_name = named != nullptr && *named != '\0' ? named : kPlatformInner;
    if (inner_name == "models") {
        std::cerr << "[models] " << portablekit::env_name("GE_MODELS_INNER") << "=models: the models backend cannot "
                  << "wrap itself; drawing with " << kPlatformInner << "\n";
        inner_name = kPlatformInner;
    }
    std::unique_ptr<GeBackend> inner = gpu::make_backend(inner_name);
    if (!inner) {
        std::cerr << "[models] " << portablekit::env_name("GE_MODELS_INNER") << "=" << inner_name
                  << ": there is no such backend\n";
        return nullptr;
    }
    return std::unique_ptr<GeBackend>(new ModelsBackend(std::move(inner), inner_name));
}

const gpu::BackendRegistration registration("models",
                                            "draws figures as 3D models over another backend (the Crowds and people row)",
                                            make_models_backend);

} // namespace
} // namespace pure::models
