// The models backend (models_backend.hpp; task 102, D-025): figures drawn as 3D models where the game draws flat ones.
//
//   <prefix>_GE_BACKEND=models          the default since task 102 (src/host/pure_main.cpp)
//   <prefix>_GE_MODELS_INNER=<name>     the backend that draws (default metal on macOS, vulkan elsewhere; pure_main
//                                       sets vulkan under the Vulkan shell); models itself is refused
//   <prefix>_CROWD_MODELS=0|1           the Video tab's Crowds and people row (game.crowd_models) for the run
//   <prefix>_SKY_MODELS=0|1             the Video tab's Skies row (game.sky_models) for the run (task 106)
//   <prefix>_TRACE_MODELS=1             `[models] frame F: N draws replaced (C by a set) by M model draws, K quads,
//                                       P figures, V vertices, B batches reused` every 60 frames and for each captured frame (the
//                                       line then ends in "(captured)")
//
// Every call goes to the inner backend unchanged while the row is Original (the default). At Models, a draw is
// looked at when it is transformed (not through mode, not a clear), textured, a triangle strip or list of decoded
// vertices, and its texture at most 256 texels on a side: its texture's HD pack key (compute_texture_pack_key with
// the pack's rule: xxh64, the address and the mip levels ignored) is looked up in models/models.ini's [figures], once
// per texture and frame. A draw whose key is there is split into quads (two triangles that share an edge: a strip's
// consecutive pair, degenerate joins skipped, or a list's pair), and each quad is replaced by the model's figures:
//   - the quad's corners in world space (its own world matrix applied); "up" from the corners of its lower v to
//     those of its higher v, or the reverse, whichever points to world +y, its length the quad's height; "right" from
//     its lower u to its higher u, made square to up; the front the winding normal of the quad's first triangle as
//     the GE orders it (cross(B - A, C - A) of its corners 0, 1, 2; a strip's odd triangle has its first two
//     swapped), made square to up, with no turn toward the viewer (task 104, D-025 as amended): measured on the
//     extracted frames it is +x for all six pit marshals (toward the oncoming race) and toward the road for both
//     grandstands, whatever the UVs' direction or the mirrored u of draws 152-154. The rules before it (the UV rule
//     up x right; the viewer's side; the side first seen) gave some marshals their back: the intro camera of a Time
//     Trial sees the booths from the far side first;
//   - a set's figures (below) stand on world +y instead, the rise of the quad's v edge their height: some of the
//     grandstands' quads are parallelograms whose v edges slant along the tier, 3.6 to 7.1 units long for a rise of
//     2.3 to 2.4, and a figure stood along the slant would lie on the tier;
//   - the model (models/README.md: y up, front +z, feet at 0, height 1) is turned so its y is up and its z the front
//     (its x is then up x front), scaled uniformly by the quad's height and stood on the midpoint of the quad's bottom
//     edge; with figures=N, N of them side by side across the quad's width;
//   - drawn as a triangle list with the quad's view, projection, viewport, target, blend, depth, stencil, alpha test,
//     fog and masks, the world matrix the identity (the vertices are in world space), no texture, no lighting, the
//     vertex colours the model's times the quad's tint (its vertex colours' mean, or its material colour), material
//     colour white and culling off (a Blender mesh's winding is not promised; depth sorts the faces).
// The quad itself is not drawn. A draw with no quad (a lone triangle) goes through.
//
// A crowd (task 104) maps its key to a set of models (`set=NAME spacing=UNITS [near=U far=U] [tint=0|1]`, the
// [set NAME] section's files): a quad stands max(1, round(width / spacing)) figures, figure f the set's model
// hash(place, f) % size, turned about up by up to +-12 degrees and scaled by up to +-6% from the same hash. The eye's
// distance d to the quad's base thins them: every figure under near, f % 2 == the place's hash bit from near to far,
// f % 4 == its two bits beyond far (a subset of the half, so a figure kept beyond far is kept nearer too). The
// figures of one game draw, a set's or the marshal's, are concatenated into as few triangle-list draws as u16
// indices allow (kMostVertices each; the Metal backend uploads a draw's vertices with each submit, so a draw per
// figure would cost more than the triangles), in groups of consecutive quads whose figures at full density fit one.
//
// The batches of static figures are kept across frames (task 105): by the game draw's identity (its vertex_address,
// primitive_count, texture and palette address), checked against the input they were built from (the figure, the
// world matrix, the vertices and indices). Each frame recomputes only the quads' bands (one distance each); a group
// whose bands did not change submits its kept batches, the current call's state (view, projection, viewport, target,
// fog, ...) put in, with vertex_address a stable synthetic id (kFirstCachedBatchAddress up, models_backend.hpp) and
// index_address a version bumped when the group is rebuilt. At most kMostCachedBatches batches are kept; a draw not
// seen for kDropAfterFrames frames is dropped. A skinned figure's batches (the marshal's) are built every frame with
// vertex_address 0. The quad's tint is in the vertices' colours, so a change of the quad's colours rebuilds.
//   <prefix>_MODELS_NO_CACHE=1          nothing kept: every batch built each frame with vertex_address 0 (read once)
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
// A sky (task 106, D-026): the faces of the game's sky cube map their keys to `sky=NAME`, a [sky NAME] section's layers
// (`<file>.pmdl [parallax=F] [spin=S]`, in the order they are drawn). With the Skies row at Models, the first face of
// a frame mapped to a sky draws its layers in its place, and the other faces of the frame are dropped:
//   - each layer one triangle list, its vertices the model's at 50 units a unit (the cube's half-size; the model is
//     authored in the unit cube, models/README.md, "Skies"), its world matrix a translation to the cube's centre (the
//     face draw's world translation) plus the parallax offset -F x the eye's world x and z (the face draw's view),
//     each wrapped to the cube's width, 100 units, then turned about y by S degrees a second on the clips' clock;
//   - the face draw's state otherwise (view, projection, viewport, target, depth GREATER with writes, stencil, alpha
//     test, fog off, masks: the sun block reads the sky's depth, docs/ge-effects.md), no texture, no lighting, the
//     model's vertex colours, culling off;
//   - the layers' batches kept as the crowd's (one each, a synthetic id and a version, built once from the model, so
//     the offset and the turn never rebuild them); they count against kMostCachedBatches.
// A frame with no face (the menus) draws no sky. The trace line then gains `; sky NAME L layers (F faces replaced), the
// eye at (X, Y, Z) of the cube` (the eye in the sky's space, where a model's horizon is).
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
constexpr std::size_t kMostVertices = 65535u;    // a batched model draw's vertices: what u16 indices reach
constexpr std::uint32_t kMostFigures = 256u;     // on one quad, for a set's spacing
constexpr std::size_t kMostCachedBatches = 64u;  // kept batches in all (task 105)
constexpr std::uint64_t kDropAfterFrames = 60u;  // a kept draw not seen for this many frames is dropped
constexpr float kYawJitter = 12.0f * 3.14159265f / 180.0f;  // a set's figure turns by up to this either way
constexpr float kHeightJitter = 0.06f;                       // and is up to this much taller or shorter
constexpr float kSkyHalfSize = 50.0f;  // the sky cube's half-size in world units: a sky model's unit (task 106)
constexpr float kSkyWidth = 100.0f;    // its width: what a layer's parallax offset wraps to

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
    std::shared_ptr<const Model> model;               // a file's model (null for a set)
    std::vector<std::shared_ptr<const Model>> set;    // a set's models, in the [set NAME] section's order
    std::string file;                                 // the file, or set=NAME
    std::uint32_t figures{1u};                        // a quad's figures (figures=N), when spacing is 0
    float spacing{};                                  // units a figure takes along the quad (spacing=)
    bool thin{};                                      // the density rule: a set, or near=/far= given
    float near_distance{120.0f}, far_distance{300.0f};
    bool tint{true};                                  // the quad's tint multiplies the colours (tint=1)
    std::size_t clip{0u};  // the clip it plays (models.ini's clip=NAME; the first by default)
    std::shared_ptr<const struct Sky> sky;  // a sky face's sky (sky=NAME, task 106): the rest is unused
};

// A sky's layer (task 106): a static model in the unit cube, its parallax factor and its turn in degrees a second.
struct SkyLayer {
    std::shared_ptr<const Model> model;
    std::string file;
    float parallax{}, spin{};
};
struct Sky {
    std::string name;
    std::vector<SkyLayer> layers;  // in the [sky NAME] section's order, the order they are drawn
};

// splitmix64: a place's (or a figure's) hash.
std::uint64_t mix64(std::uint64_t key) {
    key += 0x9E3779B97F4A7C15ull;
    key = (key ^ (key >> 30)) * 0xBF58476D1CE4E5B9ull;
    key = (key ^ (key >> 27)) * 0x94D049BB133111EBull;
    return key ^ (key >> 31);
}

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

// models.ini's [figures] and [set NAME] sections: key -> figure. Empty, with the reason printed, when there is none.
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
    int problems = 0;
    const auto report = [&](int number, const std::string &why) {
        std::cout << "[models] " << ini.string() << ":" << number << ": " << why << "\n";
        ++problems;
    };
    // A file's model, read once; null (reported once) when it cannot be.
    const auto load = [&](const std::string &file) {
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
        return found->second;
    };
    struct Line {
        int number;
        std::string key, set, clip, sky;
        Figure figure;
    };
    std::vector<Line> lines;
    // A set's name -> the line of its section and its files with their lines.
    std::map<std::string, std::pair<int, std::vector<std::pair<int, std::string>>>> sets;
    std::map<std::string, std::pair<int, std::vector<std::pair<int, std::string>>>> skies;  // [sky NAME], as sets
    std::string line, section;
    int number = 0;
    while (std::getline(in, line)) {
        ++number;
        if (const auto comment = line.find_first_of(";#"); comment != std::string::npos) line.erase(comment);
        line = trim(line);
        if (line.empty()) continue;
        if (line.front() == '[') {
            section = lower(trim(line.substr(1u, line.find(']') - 1u)));
            if (section.rfind("set ", 0) == 0) {
                section = "set " + trim(section.substr(4u));
                sets.emplace(section.substr(4u), std::pair{number, std::vector<std::pair<int, std::string>>{}});
            } else if (section.rfind("sky ", 0) == 0) {
                section = "sky " + trim(section.substr(4u));
                skies.emplace(section.substr(4u), std::pair{number, std::vector<std::pair<int, std::string>>{}});
            }
            continue;
        }
        if (section.rfind("set ", 0) == 0) {
            sets[section.substr(4u)].second.emplace_back(number, line);
            continue;
        }
        if (section.rfind("sky ", 0) == 0) {
            skies[section.substr(4u)].second.emplace_back(number, line);
            continue;
        }
        if (section != "figures") continue;
        const auto equals = line.find('=');
        std::istringstream words(equals == std::string::npos ? std::string{} : line.substr(equals + 1u));
        Line entry{number, lower(trim(line.substr(0u, equals))), {}, {}, {}, {}};
        Figure &figure = entry.figure;
        figure.figures = 0u;
        bool figures_given = false, distances = false, bad = false;
        const auto number_of = [&](const std::string &text) {
            char *end = nullptr;
            const float value = std::strtof(text.c_str(), &end);
            if (end == text.c_str() || *end != '\0' || !std::isfinite(value)) bad = true;
            return value;
        };
        std::string word;
        while (words >> word) {
            const auto at = word.find('=');
            const std::string value = at == std::string::npos ? std::string{} : word.substr(at + 1u);
            if (word.rfind("figures=", 0) == 0) {
                figure.figures = static_cast<std::uint32_t>(std::strtoul(value.c_str(), nullptr, 10));
                figures_given = true;
            } else if (word.rfind("clip=", 0) == 0) {
                entry.clip = value;
            } else if (word.rfind("set=", 0) == 0) {
                entry.set = lower(value);
            } else if (word.rfind("sky=", 0) == 0) {
                entry.sky = lower(value);
            } else if (word.rfind("spacing=", 0) == 0) {
                figure.spacing = number_of(value);
            } else if (word.rfind("near=", 0) == 0) {
                figure.near_distance = number_of(value), distances = true;
            } else if (word.rfind("far=", 0) == 0) {
                figure.far_distance = number_of(value), distances = true;
            } else if (word.rfind("tint=", 0) == 0) {
                figure.tint = value != "0";
            } else if (figure.file.empty() && at == std::string::npos) {
                figure.file = word;
            } else {
                bad = true;
            }
        }
        figure.thin = !entry.set.empty() || distances;
        if (entry.key.size() != 24u || entry.key.find_first_not_of("0123456789abcdef") != std::string::npos || bad ||
            int{!figure.file.empty()} + int{!entry.set.empty()} + int{!entry.sky.empty()} != 1 ||
            (figures_given && (figure.figures == 0u || figure.figures > 64u)) || figure.spacing < 0.0f ||
            figure.near_distance < 0.0f || figure.far_distance < figure.near_distance) {
            report(number, "not `<24 hex digits> = <file>.pmdl figures=1..64 [clip=NAME]` or `<24 hex digits> = "
                           "set=NAME spacing=UNITS [near=UNITS far=UNITS] [tint=0|1]` or `<24 hex digits> = sky=NAME`; "
                           "left out");
            continue;
        }
        if (!entry.sky.empty()) {
            lines.push_back(std::move(entry));
            continue;
        }
        if (!figures_given && !(figure.spacing > 0.0f)) {
            report(number, "neither figures=N nor spacing=UNITS (how many figures a quad stands); left out");
            continue;
        }
        if (!entry.set.empty()) figure.file = "set=" + entry.set;
        lines.push_back(std::move(entry));
    }
    // The sets' models: a set with no files, or a file that does not read, is reported (the rest of the set serves).
    std::map<std::string, std::vector<std::shared_ptr<const Model>>> set_models;
    for (const auto &[name, at] : sets) {
        std::vector<std::shared_ptr<const Model>> &chosen = set_models[name];
        if (at.second.empty()) report(at.first, "[set " + name + "] lists no files");
        for (const auto &[line_number, file] : at.second) {
            if (auto model = load(file)) chosen.push_back(std::move(model));
            else report(line_number, "[set " + name + "]'s " + file + " is left out of the set");
        }
    }
    // The skies' layers: `<file>.pmdl [parallax=F] [spin=S]`; a line that does not read is reported and left out.
    std::map<std::string, std::shared_ptr<const Sky>> sky_of;
    for (const auto &[name, at] : skies) {
        auto sky = std::make_shared<Sky>();
        sky->name = name;
        if (at.second.empty()) report(at.first, "[sky " + name + "] lists no layers");
        for (const auto &[line_number, text] : at.second) {
            std::istringstream words(text);
            SkyLayer layer;
            bool bad = false;
            std::string word;
            while (words >> word) {
                const auto at_equals = word.find('=');
                const std::string value = at_equals == std::string::npos ? std::string{} : word.substr(at_equals + 1u);
                char *end = nullptr;
                const float parsed = std::strtof(value.c_str(), &end);
                const bool numeric = !value.empty() && *end == '\0' && std::isfinite(parsed);
                if (word.rfind("parallax=", 0) == 0 && numeric) layer.parallax = parsed;
                else if (word.rfind("spin=", 0) == 0 && numeric) layer.spin = parsed;
                else if (layer.file.empty() && at_equals == std::string::npos) layer.file = word;
                else bad = true;
            }
            if (bad || layer.file.empty()) {
                report(line_number, "not `<file>.pmdl [parallax=F] [spin=DEGREES]`; left out of [sky " + name + "]");
                continue;
            }
            layer.model = load(layer.file);
            if (!layer.model) {
                report(line_number, "[sky " + name + "]'s " + layer.file + " is left out of the sky");
                continue;
            }
            sky->layers.push_back(std::move(layer));
        }
        sky_of.emplace(name, std::move(sky));
    }
    for (Line &entry : lines) {
        Figure &figure = entry.figure;
        if (!entry.sky.empty()) {
            const auto found = sky_of.find(entry.sky);
            if (found == sky_of.end() || found->second->layers.empty()) {
                report(entry.number, found == sky_of.end() ? "no [sky " + entry.sky + "] section; left out"
                                                           : "[sky " + entry.sky + "] has no layer; left out");
                continue;
            }
            figure.sky = found->second;
            figure.file = "sky=" + entry.sky;
            table[entry.key] = std::move(figure);
            continue;
        }
        if (!entry.set.empty()) {
            const auto found = set_models.find(entry.set);
            if (found == set_models.end() || found->second.empty()) {
                report(entry.number, found == set_models.end() ? "no [set " + entry.set + "] section; left out"
                                                               : "[set " + entry.set + "] has no model; left out");
                continue;
            }
            figure.set = found->second;
            table[entry.key] = std::move(figure);
            continue;
        }
        figure.model = load(figure.file);
        if (!figure.model) continue;
        if (!entry.clip.empty()) {
            const std::vector<Clip> &clips = figure.model->clips;
            const auto named =
                std::find_if(clips.begin(), clips.end(), [&](const Clip &c) { return c.name == entry.clip; });
            if (named != clips.end()) {
                figure.clip = static_cast<std::size_t>(named - clips.begin());
            } else {
                report(entry.number, figure.file + " has no clip " + entry.clip +
                                         (clips.empty() ? " (it has none: it stands still)"
                                                        : "; it plays " + clips.front().name));
            }
        }
        table[entry.key] = std::move(figure);
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
    std::cout << (*separator == ';' ? ")" : "");
    for (const auto &[name, chosen] : set_models)
        std::cout << ", set " << name << " of " << chosen.size() << " model" << (chosen.size() == 1u ? "" : "s");
    for (const auto &[name, sky] : sky_of)
        std::cout << ", sky " << name << " of " << sky->layers.size() << " layer" << (sky->layers.size() == 1u ? "" : "s");
    std::cout << (problems != 0 ? ", with problems above" : "") << "\n";
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
        const char *no_cache = portablekit::env("MODELS_NO_CACHE");
        no_cache_ = no_cache != nullptr && *no_cache != '\0' && std::strcmp(no_cache, "0") != 0;
        if (no_cache_)
            std::cout << "[models] " << portablekit::env_name("MODELS_NO_CACHE")
                      << "=1: every batch built each frame and drawn with vertex_address 0\n";
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
        sky_drawn_ = false;
        ++frame_;
        std::erase_if(kept_, [&](const auto &entry) { return frame_ - entry.second.last_seen > kDropAfterFrames; });
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
        if (figure != nullptr && figure->sky != nullptr) {
            if (sky_on_) draw_sky(call, *figure->sky, memory);  // the face itself is never drawn
            else inner_->submit(call, memory);
            return;
        }
        if (figure == nullptr || !crowd_on_ || !replace(call, *figure, memory)) inner_->submit(call, memory);
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
        sky_drawn_ = false;
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
        std::uint64_t replaced{}, set_replaced{}, model_draws{}, quads{}, figures{}, vertices{};
        std::uint64_t reused{};  // batches submitted as kept (task 105)
        const Clip *clip{};      // the first animated figure's clip and time
        double clip_time{};
        double skin_seconds{};  // the frame's skinning
        double replace_seconds{};  // the frame's replace() calls, the inner backend's submits of their draws included
        double submit_seconds{};   // those submits
        std::uint64_t sky_faces{}, sky_layers{};  // the sky's faces dropped and its layers drawn (task 106)
        std::string sky;                          // the sky drawn
        Vec3 sky_eye{};                           // the eye in the sky's space: (eye - centre) / the half-size
    };

    // A quad's placement, what its figures are built from (place() and the hashes), and the band (every: 1, 2 or 4)
    // its figures were last built at.
    struct Placed {
        Vec3 base{}, up{}, right{}, front{}, x_axis{};
        float height{}, width{};
        std::uint32_t tint{}, count{}, every{1u};
        std::uint64_t place_key{}, place_hash{};
    };
    // Consecutive quads whose figures at full density fit one batch (segments_of): what a band change rebuilds.
    struct Segment {
        std::size_t first{}, last{};
        std::vector<DrawCall> batches;   // the triangle lists, their vertices and indices built
        std::vector<std::uint32_t> ids;  // each batch's synthetic vertex_address, kept across rebuilds
        std::uint64_t figures{}, vertices{};
    };
    // A game draw's kept batches (task 105): the input they were built from, which the next call must match for them
    // to serve it, its placed quads and its segments.
    struct Kept {
        const Figure *figure{};
        gpu::PrimitiveType primitive{};
        bool has_vertex_color{};
        std::uint32_t material_color{};
        std::array<float, 16> world{};
        std::vector<gpu::Vertex> vertices;
        std::vector<std::uint16_t> indices;
        std::vector<Placed> quads;
        std::vector<Segment> segments;
        std::uint64_t last_seen{};
        [[nodiscard]] std::size_t batches() const {
            std::size_t n = 0u;
            for (const Segment &segment : segments) n += segment.batches.size();
            return n;
        }
    };
    // What recognises a game draw from frame to frame: its vertex address, primitive count, texture and palette.
    using Identity = std::tuple<std::uint32_t, std::uint32_t, std::uint32_t, std::uint32_t>;

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
        return static_cast<double>(mix64(key) >> 11) * 0x1.0p-53;
    }

    // The model's positions skinned for this figure (into skinned_), or its rest positions when it is static.
    const std::vector<Vec3> &positions_of(const Model &model, std::size_t clip_number, std::uint64_t place) {
        if (model.joints.empty() || model.clips.empty()) return model.positions;
        const auto start = std::chrono::steady_clock::now();
        const Clip &clip = model.clips[std::min(clip_number, model.clips.size() - 1u)];
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

    // The rows, once a frame (never per draw): the table read whenever one of them turns to Models.
    void read_option(bool at_start) {
        const bool crowd = portablekit::settings::game_option("crowd_models") == 1u;
        const bool sky = portablekit::settings::game_option("sky_models") == 1u;
        if ((crowd && !crowd_on_) || (sky && !sky_on_)) {
            seen_.clear();
            sky_batches_.clear();
            kept_.clear();
            table_ = read_table();
        }
        if (crowd && !crowd_on_) std::cout << "[pure] crowd models: on (game.crowd_models), drawn by " << inner_name_ << "\n";
        else if (at_start && !crowd) std::cout << "[pure] crowd models: off\n";
        if (sky && !sky_on_) std::cout << "[pure] skies: on (game.sky_models), drawn by " << inner_name_ << "\n";
        else if (at_start && !sky) std::cout << "[pure] skies: off\n";
        if (crowd != crowd_on_) kept_.clear();
        if (sky != sky_on_) sky_batches_.clear();
        crowd_on_ = crowd;
        sky_on_ = sky;
        on_ = crowd || sky;
    }

    // A sky face (task 106): the frame's first draws the sky's layers in its place; every face is dropped.
    void draw_sky(const DrawCall &call, const Sky &sky, const GuestMemory &memory) {
        ++counts_.sky_faces;
        if (sky_drawn_) return;
        sky_drawn_ = true;
        const auto started = std::chrono::steady_clock::now();
        const DrawCall model_draw = model_draw_of(call);
        const Vec3 centre{call.world[12], call.world[13], call.world[14]};
        const Vec3 eye = eye_of(call.view);
        const auto wrapped = [](float offset) { return offset - kSkyWidth * std::floor(offset / kSkyWidth + 0.5f); };
        for (const SkyLayer &layer : sky.layers) {
            auto found = sky_batches_.find(&layer);
            if (found == sky_batches_.end()) {
                DrawCall batch = model_draw;
                const Model &model = *layer.model;
                batch.vertices.resize(model.positions.size());
                for (std::size_t i = 0; i < model.positions.size(); ++i) {
                    const Vec3 at = scale(model.positions[i], kSkyHalfSize);
                    gpu::Vertex &out = batch.vertices[i];
                    out.position = {at[0], at[1], at[2], 1.0f};
                    out.normal = {0.0f, 0.0f, 0.0f};
                    out.texcoord = {0.0f, 0.0f};
                    out.color = model.colors[i];
                }
                batch.indices = model.indices;
                batch.primitive_count = static_cast<std::uint32_t>(batch.indices.size() / 3u);
                if (!no_cache_) {
                    batch.vertex_address = next_batch_id();
                    batch.index_address = next_version_;
                    next_version_ = next_version_ == 0xFFFFFFFFu ? 1u : next_version_ + 1u;
                }
                found = sky_batches_.emplace(&layer, std::move(batch)).first;
            } else {
                ++counts_.reused;
            }
            DrawCall &batch = found->second;
            refresh(batch, model_draw);
            // T(centre + offset) x R_y(spin): the layer's vertices are the model's at the half-size, about its origin.
            const float turn = static_cast<float>(std::fmod(clock_seconds_ * layer.spin, 360.0) * 3.14159265358979 / 180.0);
            const float c = std::cos(turn), s = std::sin(turn);
            batch.world = {c, 0.0f, -s, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, s, 0.0f, c, 0.0f,
                           centre[0] + wrapped(-layer.parallax * eye[0]), centre[1],
                           centre[2] + wrapped(-layer.parallax * eye[2]), 1.0f};
            const auto submitted = std::chrono::steady_clock::now();
            inner_->submit(batch, memory);
            counts_.submit_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - submitted).count();
            counts_.vertices += batch.vertices.size();
            ++counts_.sky_layers;
            ++counts_.model_draws;
        }
        counts_.sky = sky.name;
        counts_.sky_eye = scale(sub(eye, centre), 1.0f / kSkyHalfSize);
        counts_.replace_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    }

    void report(const char *what) const {
        std::cout << "[models] frame " << shown_frame_ << ": " << shown_.replaced << " draws replaced ("
                  << shown_.set_replaced << " by a set) by " << shown_.model_draws << " model draws, " << shown_.quads
                  << " quads, " << shown_.figures << " figures, " << shown_.vertices << " vertices, " << shown_.reused
                  << " batches reused" << what;
        if (shown_.clip != nullptr)
            std::cout << "; clip " << shown_.clip->name << " t=" << shown_.clip_time << " (animated), skinned in "
                      << static_cast<long>(shown_.skin_seconds * 1e6) << " us";
        if (shown_.sky_faces != 0u)
            std::cout << "; sky " << shown_.sky << " " << shown_.sky_layers << " layers (" << shown_.sky_faces
                      << " faces replaced), the eye at (" << shown_.sky_eye[0] << ", " << shown_.sky_eye[1] << ", "
                      << shown_.sky_eye[2] << ") of the cube";
        if (shown_.replaced != 0u)
            std::cout << "; replaced in " << static_cast<long>(shown_.replace_seconds * 1e6) << " us, "
                      << static_cast<long>(shown_.submit_seconds * 1e6) << " of them the inner backend's";
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
                    // Corners 0 to 2 are the first triangle as the GE winds it: an odd one of a strip is (n+1, n, n+2).
                    if (n % 2u == 0u) quads.push_back({a, b, c, d});
                    else quads.push_back({b, a, c, d});
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

    static bool animated(const Model &model) { return !model.joints.empty() && !model.clips.empty(); }
    // Whether any of the figure's models is skinned (the marshal's): its batches are built every frame.
    static bool animated(const Figure &figure) {
        if (figure.model != nullptr && animated(*figure.model)) return true;
        return std::any_of(figure.set.begin(), figure.set.end(),
                           [](const std::shared_ptr<const Model> &m) { return m != nullptr && animated(*m); });
    }

    // Everything the quad is drawn with (view, projection, viewport, target, blend, depth, stencil, alpha test, fog,
    // masks); then what a model draw changes.
    static DrawCall model_draw_of(const DrawCall &call) {
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
        draw.material_color = 0xFFFFFFFFu;
        draw.lighting_enabled = false;
        draw.has_vertex_color = true;
        draw.world = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f};
        draw.indices.clear();
        draw.vertices.clear();
        return draw;
    }

    // The viewer: the eye of the view matrix (world to eye, column-major), -R^T t.
    static Vec3 eye_of(const std::array<float, 16> &v) {
        return {-(v[0] * v[12] + v[1] * v[13] + v[2] * v[14]), -(v[4] * v[12] + v[5] * v[13] + v[6] * v[14]),
                -(v[8] * v[12] + v[9] * v[13] + v[10] * v[14])};
    }

    // Which of a quad's figures the distance keeps, as `every`: all under near, every second from near to far, every
    // fourth beyond (f % every == the place's pick; f % 4 == its two bits is a subset of f % 2 == its low bit).
    static std::uint32_t band_of(const Figure &figure, const Placed &quad, const Vec3 &eye) {
        if (!figure.thin) return 1u;
        const float d = length(sub(eye, quad.base));
        return d < figure.near_distance ? 1u : d < figure.far_distance ? 2u : 4u;
    }

    // The draw's quads placed, those place() refuses left out; each one's band left 0 for the first band pass.
    static void place_quads(const DrawCall &call, const Figure &figure,
                            const std::vector<std::array<std::uint32_t, 4>> &quads, std::vector<Placed> &out) {
        const bool is_set = !figure.set.empty();
        for (const auto &quad : quads) {
            std::array<Corner, 4> corners{};
            std::array<std::uint32_t, 4> sum{};
            for (std::size_t i = 0; i < 4u; ++i) {
                const gpu::Vertex &vertex = call.vertices[quad[i]];
                corners[i] = {transform(call.world, vertex.position), vertex.texcoord[0], vertex.texcoord[1]};
                const std::uint32_t color = call.has_vertex_color ? vertex.color : call.material_color;
                for (std::uint32_t c = 0; c < 4u; ++c) sum[c] += (color >> (8u * c)) & 0xFFu;
            }
            Placed placed;
            for (std::uint32_t c = 0; c < 4u; ++c) placed.tint |= ((sum[c] + 2u) / 4u) << (8u * c);
            if (!figure.tint) placed.tint = 0xFFFFFFFFu;
            if (!place(corners, is_set, placed.base, placed.up, placed.right, placed.front, placed.height, placed.width))
                continue;
            placed.place_key = quantise(placed.base);
            // The model's x, y, z in world space: x = up x front (= -right), y = up, z = front.
            placed.x_axis = cross(placed.up, placed.front);
            placed.count = figure.spacing > 0.0f
                               ? std::clamp(static_cast<std::uint32_t>(std::lround(placed.width / figure.spacing)), 1u,
                                            kMostFigures)
                               : figure.figures;
            placed.place_hash = mix64(placed.place_key);
            placed.every = 0u;
            out.push_back(placed);
        }
    }

    // The quads grouped in order, each group's figures at full density within kMostVertices (a quad over it alone is
    // a group of its own): a group's batches depend on its own quads' bands alone.
    static std::vector<Segment> segments_of(const Figure &figure, const std::vector<Placed> &quads) {
        std::size_t most = figure.model != nullptr ? figure.model->positions.size() : 0u;
        for (const auto &model : figure.set)
            if (model != nullptr) most = std::max(most, model->positions.size());
        std::vector<Segment> segments;
        std::size_t worst = 0u;
        for (std::size_t q = 0; q < quads.size(); ++q) {
            const std::size_t wanted = static_cast<std::size_t>(quads[q].count) * most;
            if (!segments.empty() && worst + wanted <= kMostVertices) {
                segments.back().last = q + 1u;
                worst += wanted;
            } else {
                Segment segment;
                segment.first = q;
                segment.last = q + 1u;
                segments.push_back(std::move(segment));
                worst = wanted;
            }
        }
        return segments;
    }

    std::uint32_t next_batch_id() {
        const std::uint32_t id = next_id_;
        next_id_ = next_id_ == 0xFFFFFFFFu ? kFirstCachedBatchAddress : next_id_ + 1u;
        return id;
    }

    // The segment's figures at their quads' bands into triangle lists (the figures' vertices and their indices
    // offset), a list flushed before kMostVertices. `keep`: each list carries its synthetic id and a new version.
    void build(const Figure &figure, const std::vector<Placed> &quads, Segment &segment, const DrawCall &model_draw,
               bool keep) {
        const bool is_set = !figure.set.empty();
        segment.batches.clear();
        segment.figures = 0u;
        segment.vertices = 0u;
        DrawCall draw = model_draw;
        const auto flush = [&] {
            if (draw.indices.empty()) return;
            draw.primitive_count = static_cast<std::uint32_t>(draw.indices.size() / 3u);
            if (keep) {
                const std::size_t n = segment.batches.size();
                if (n == segment.ids.size()) segment.ids.push_back(next_batch_id());
                draw.vertex_address = segment.ids[n];
                draw.index_address = next_version_;
                next_version_ = next_version_ == 0xFFFFFFFFu ? 1u : next_version_ + 1u;
            }
            segment.vertices += draw.vertices.size();
            segment.batches.push_back(std::move(draw));
            draw = model_draw;
        };
        for (std::size_t q = segment.first; q < segment.last; ++q) {
            const Placed &quad = quads[q];
            const std::uint32_t pick = static_cast<std::uint32_t>(quad.place_hash & 3u) % quad.every;
            for (std::uint32_t f = 0; f < quad.count; ++f) {
                if (f % quad.every != pick) continue;
                const float across = (static_cast<float>(f) + 0.5f) / static_cast<float>(quad.count) - 0.5f;
                const Vec3 foot = add(quad.base, scale(quad.right, across * quad.width));
                Vec3 fx = quad.x_axis, fz = quad.front;
                float size = quad.height;
                const Model *model = figure.model.get();
                if (is_set) {
                    // The figure's model, turn and height from the hash of its place and number.
                    const std::uint64_t h = mix64(quad.place_hash + f);
                    model = figure.set[static_cast<std::size_t>(h % figure.set.size())].get();
                    const auto unit = [&](int shift) {
                        return static_cast<float>((h >> shift) & 0xFFFFu) / 65535.0f * 2.0f - 1.0f;
                    };
                    const float yaw = unit(16) * kYawJitter, c = std::cos(yaw), s = std::sin(yaw);
                    fz = add(scale(quad.front, c), scale(quad.x_axis, s));
                    fx = sub(scale(quad.x_axis, c), scale(quad.front, s));
                    size *= 1.0f + unit(32) * kHeightJitter;
                }
                const std::vector<Vec3> &positions = positions_of(*model, figure.clip, quad.place_key * 64u + f);
                if (draw.vertices.size() + positions.size() > kMostVertices) flush();
                const std::size_t first = draw.vertices.size();
                draw.vertices.resize(first + positions.size());
                for (std::size_t i = 0; i < positions.size(); ++i) {
                    const Vec3 &p = positions[i];
                    const Vec3 at = add(foot, add(scale(fx, p[0] * size),
                                                  add(scale(quad.up, p[1] * size), scale(fz, p[2] * size))));
                    gpu::Vertex &out = draw.vertices[first + i];
                    out.position = {at[0], at[1], at[2], 1.0f};
                    out.normal = {0.0f, 0.0f, 0.0f};
                    out.texcoord = {0.0f, 0.0f};
                    out.color = modulate(model->colors[i], quad.tint);
                }
                for (const std::uint16_t index : model->indices)
                    draw.indices.push_back(static_cast<std::uint16_t>(first + index));
                ++segment.figures;
            }
        }
        flush();
    }

    // A kept batch for this frame: the current call's state (view, projection, viewport, target, fog, ...) with its
    // own vertices, indices, id, version and count.
    static void refresh(DrawCall &batch, const DrawCall &model_draw) {
        std::vector<gpu::Vertex> vertices = std::move(batch.vertices);
        std::vector<std::uint16_t> indices = std::move(batch.indices);
        const std::uint32_t id = batch.vertex_address, version = batch.index_address, count = batch.primitive_count;
        batch = model_draw;
        batch.vertices = std::move(vertices);
        batch.indices = std::move(indices);
        batch.vertex_address = id;
        batch.index_address = version;
        batch.primitive_count = count;
    }

    // Whether the call is the one the kept batches were built from: the same figure, world matrix and vertices.
    static bool same_input(const Kept &kept, const DrawCall &call, const Figure &figure) {
        if (kept.figure != &figure || kept.primitive != call.primitive || kept.has_vertex_color != call.has_vertex_color ||
            kept.material_color != call.material_color || kept.world != call.world || kept.indices != call.indices ||
            kept.vertices.size() != call.vertices.size())
            return false;
        for (std::size_t i = 0; i < call.vertices.size(); ++i) {
            const gpu::Vertex &a = kept.vertices[i], &b = call.vertices[i];
            if (a.position != b.position || a.texcoord != b.texcoord || a.color != b.color) return false;
        }
        return true;
    }

    // Room for `wanted` more kept batches (kMostCachedBatches in all), the draws seen longest ago dropped for it (not
    // this frame's); false when there is none.
    bool make_room(std::size_t wanted) {
        if (wanted + sky_batches_.size() > kMostCachedBatches) return false;
        for (;;) {
            std::size_t total = sky_batches_.size();  // the sky's layers' kept batches (task 106) count too
            auto oldest = kept_.end();
            for (auto it = kept_.begin(); it != kept_.end(); ++it) {
                total += it->second.batches();
                if (it->second.last_seen < frame_ &&
                    (oldest == kept_.end() || it->second.last_seen < oldest->second.last_seen))
                    oldest = it;
            }
            if (total + wanted <= kMostCachedBatches) return true;
            if (oldest == kept_.end()) return false;
            kept_.erase(oldest);
        }
    }

    // Draws the figures for each of the draw's quads, batched; false (and nothing drawn) when no quad is placed. A
    // draw of static figures keeps its batches (task 105): the next frame's call with the same identity and input
    // only has its bands recomputed, the segments whose bands changed rebuilt and the others submitted as kept.
    bool replace(const DrawCall &call, const Figure &figure, const GuestMemory &memory) {
        const auto started = std::chrono::steady_clock::now();
        const Identity identity{call.vertex_address, call.primitive_count, call.texture.address,
                                call.texture.clut_address};
        bool keep = !no_cache_ && !animated(figure);
        Kept *kept = nullptr;
        if (keep) {
            if (const auto found = kept_.find(identity); found != kept_.end()) {
                if (same_input(found->second, call, figure)) kept = &found->second;
                else if (found->second.last_seen == frame_) keep = false;  // drawn again this frame with other input
                else kept_.erase(found);
            }
        }
        Kept fresh;
        if (kept == nullptr) {
            const std::vector<std::array<std::uint32_t, 4>> quads = quads_of(call);
            if (quads.empty()) return false;
            place_quads(call, figure, quads, fresh.quads);
            fresh.segments = segments_of(figure, fresh.quads);
            if (keep && !make_room(fresh.segments.size())) keep = false;
        }
        Kept &k = kept != nullptr ? *kept : fresh;
        if (k.quads.empty()) {
            counts_.replace_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
            return false;
        }
        const DrawCall model_draw = model_draw_of(call);
        const Vec3 eye = eye_of(call.view);
        std::uint64_t drawn = 0u;
        for (Segment &segment : k.segments) {
            bool changed = false;
            for (std::size_t q = segment.first; q < segment.last; ++q) {
                const std::uint32_t every = band_of(figure, k.quads[q], eye);
                if (every != k.quads[q].every) k.quads[q].every = every, changed = true;
            }
            if (changed) build(figure, k.quads, segment, model_draw, keep);
            else counts_.reused += segment.batches.size();
            for (DrawCall &batch : segment.batches) {
                if (!changed) refresh(batch, model_draw);
                const auto submitted = std::chrono::steady_clock::now();
                inner_->submit(batch, memory);
                counts_.submit_seconds +=
                    std::chrono::duration<double>(std::chrono::steady_clock::now() - submitted).count();
            }
            drawn += segment.batches.size();
            counts_.figures += segment.figures;
            counts_.vertices += segment.vertices;
        }
        counts_.quads += k.quads.size();
        k.last_seen = frame_;
        if (kept == nullptr && keep) {
            fresh.figure = &figure;
            fresh.primitive = call.primitive;
            fresh.has_vertex_color = call.has_vertex_color;
            fresh.material_color = call.material_color;
            fresh.world = call.world;
            fresh.vertices = call.vertices;
            fresh.indices = call.indices;
            kept_.insert_or_assign(identity, std::move(fresh));
        }
        counts_.replace_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
        ++counts_.replaced;
        if (!figure.set.empty()) ++counts_.set_replaced;
        counts_.model_draws += drawn;
        return true;
    }

    // A quad's place for the hashes: its base to a tenth of a unit on each axis (the booths' quads are a unit apart).
    static std::uint64_t quantise(const Vec3 &p) {
        const auto q = [](float v) { return static_cast<std::uint64_t>(static_cast<std::int64_t>(std::lround(v * 10.0f)) & 0x1FFFFF); };
        return q(p[0]) << 42 | q(p[1]) << 21 | q(p[2]);
    }
    // A quad's placement from its corners (D-025): false when its UVs or shape say nothing. `upright` (a set's):
    // up is world +y and the height the v edge's rise.
    static bool place(const std::array<Corner, 4> &corners, bool upright, Vec3 &base, Vec3 &up, Vec3 &right,
                      Vec3 &front, float &height, float &width) {
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
        height = upright ? along_v[1] : length(along_v);
        if (height <= 1e-6f) return false;
        up = upright ? Vec3{0.0f, 1.0f, 0.0f} : scale(along_v, 1.0f / height);
        Vec3 along_u = sub(u_hi, u_lo);
        along_u = sub(along_u, scale(up, dot(along_u, up)));
        width = length(along_u);
        if (width <= 1e-6f) return false;
        right = scale(along_u, 1.0f / width);
        // The front: the first triangle's winding normal, square to up.
        front = cross(sub(corners[1].world, corners[0].world), sub(corners[2].world, corners[0].world));
        front = sub(front, scale(up, dot(front, up)));
        const float facing = length(front);
        if (facing <= 1e-9f) return false;
        front = scale(front, 1.0f / facing);
        base = bottom;
        return true;
    }

    std::unique_ptr<GeBackend> inner_;
    std::string inner_name_;
    bool initialized_{};
    bool trace_{};
    bool on_{};        // either row at Models: the table is looked in
    bool crowd_on_{};  // the Crowds and people row (game.crowd_models)
    bool sky_on_{};    // the Skies row (game.sky_models, task 106)
    bool sky_drawn_{};  // this frame's sky drawn (its first face seen)
    // The sky layers' kept batches (task 106), by layer: built once from the model, refreshed with each frame's state.
    std::map<const SkyLayer *, DrawCall> sky_batches_;
    std::unordered_map<std::string, Figure> table_;
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
    // The kept batches (task 105) by the game draw's identity, the frames they are aged by, the next synthetic id and
    // version, and MODELS_NO_CACHE.
    std::map<Identity, Kept> kept_;
    std::uint64_t frame_{};
    std::uint32_t next_id_{kFirstCachedBatchAddress};
    std::uint32_t next_version_{1u};
    bool no_cache_{};
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
