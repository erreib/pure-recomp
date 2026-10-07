// The GE drawn with Metal: PURE_GE_BACKEND=metal (docs/metal-backend.md).
//
// A GeBackend (vendor/portablekit/host/gpu/ge_backend.hpp, docs/ge-backend.md) in our own sources, so its
// registration below is linked into the program directly. Task 023 built what the 2D frontend needs, task
// 024 the 3D draws, task 025 the effects:
//
//   targets    keyed by (colour address, stride, format), each a 480x272 RGBA8 colour texture (5650, 5551
//              and 4444 targets too, for now) and a Depth32Float_Stencil8 texture (internal scale 1,
//              D-002). A pass draws into one target; switching targets ends it.
//   stencil    the GE's stencil test and operations on the attachment; the colour target's alpha kept as
//              the PSP's stencil by patch 0006's rule: written by the zpass REPLACE/ZERO where the colour
//              path can (dual-source blending under a source-alpha blend), copied from the attachment where
//              it cannot, before a destination-alpha read and at the end of the pass.
//   textures   a bind that lies in a target samples that target, the one starting at the address first
//              (patch 0003), while guest memory under it is what it was when the target was first drawn
//              in the frame; anything else is decoded from guest memory with the framework's
//              decode_texture() and cached by its contents (texels and the palette entries it can reach).
//   draws      every primitive, through mode or transformed, through one pipeline whose key holds the
//              blend, the write masks, the alpha test, the depth test and the stencil; clears; scissor;
//              the GE viewport folded into clip space; back-face culling.
//              Transformed draws get the GE's per-vertex lighting and fog (ge.vert's, in the shaders), and
//              transformed sprites are expanded on the screen after projection, as the GE draws them.
//   frames     one command buffer a frame, committed at the flip. present_image() names the display
//              target's texture; capture_frame() reads it back synchronously. The device and the command
//              queue are the program's one pair (metal_device.hpp), which the Metal shell presents on too.
//   guest      block transfers from a target, read_back_framebuffer() and the frame write-back store a
//   memory     target's pixels in guest VRAM in its own format; write_back_depth() stores the depth as the
//              GE's 16-bit z at a SIGNAL (the lens flare reads it). Each waits for the GPU; counted, with
//              the time waited.
//
// Under the Vulkan shell (BackendConfig::vulkan_shell), whose present shows its own targets and whose
// window the input script's `shot` steps read, every presented picture is also read back and handed to it
// (metal_shell.hpp); PURE_METAL_SHELL=0 leaves that window black. Under any other shell nothing is handed
// over and nothing is read back: the Metal shell (src/host/metal_shell.mm) samples the presented texture
// itself, and the headless one captures through capture_frame(). PURE_METAL_LOG=1 prints a line per draw.
//
// Frame times (task 033, docs/metal-backend.md "Frame times"): PURE_METAL_TRACE=FILE writes a CSV row per flip with
// where the time between two flips went (submit, pipeline creation, texture decodes, each kind of GPU wait, the
// Metal shell's present through the hook in metal_device.hpp); tools/frame_times.py summarises it. The render
// pipelines and depth-stencil states of config/metal_pipelines.txt are made at start, the pipelines asynchronously
// (pre-warming), so no draw compiles one on first use; PURE_METAL_PIPELINES_OUT=FILE writes the keys a run used.
#include "metal_device.hpp"
#include "metal_shaders.h"
#include "metal_shell.hpp"

#include "gpu/ge_backend.hpp"
#include "gpu/ge_state.hpp"
#include "gpu/texture_decode.hpp"
#include "profile.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace pure::gpu {
namespace {

namespace pk = portablekit::gpu;
using pk::BlendState;
using pk::DrawCall;
using pk::GuestMemory;
using pk::PrimitiveType;
using pk::TextureFormat;
using pk::TextureState;
using pk::Vertex;

constexpr std::uint32_t kWidth = pk::kScreenWidth;    // internal scale 1 (D-002)
constexpr std::uint32_t kHeight = pk::kScreenHeight;
constexpr std::size_t kPictureBytes = static_cast<std::size_t>(kWidth) * kHeight * 4u;
// Vertex and upload space comes in chunks of this size, reused once the GPU has finished with them.
constexpr std::size_t kChunkBytes = 4u << 20u;
constexpr std::size_t kMaxTextures = 1024u;
// Frames the GPU may still be drawing while the next one is recorded.
constexpr std::size_t kFramesInFlight = 2u;
constexpr std::uint64_t kReportEvery = 600u;

// The vertex as the shaders read it (GeVertex in metal_shaders.h).
struct GpuVertex {
    float x{}, y{}, z{}, w{1.0f};
    float u{}, v{};
    std::uint32_t color{};
    std::uint32_t source{};  // a transformed sprite's corner: the vertex it is lit and fogged as
    float nx{}, ny{}, nz{}, nw{};
};
static_assert(sizeof(GpuVertex) == 48u, "GpuVertex must match GeVertex in metal_shaders.h");

// VertexUniforms::mode, y and z.
constexpr std::uint32_t kClipPositions = 1u;  // y: positions in the PSP's clip space (transformed sprite corners)
constexpr std::uint32_t kFog = 1u;            // z bits
constexpr std::uint32_t kLighting = 2u;

struct VertexUniforms {
    std::array<float, 16> transform{};
    std::array<float, 4> screen{};
    std::array<float, 4> uv_transform{1.0f, 1.0f, 0.0f, 0.0f};
    std::array<std::uint32_t, 4> mode{};
    std::array<float, 4> view_z{};
    std::array<std::uint32_t, 4> texture_map{};  // mode, projection source, the two shade lights (task 036)
    std::array<float, 16> texture_matrix{};
    std::array<float, 4> viewer{};
    std::array<float, 4> uv_remap{1.0f, 1.0f, 0.0f, 0.0f};
};
static_assert(sizeof(VertexUniforms) == 240u, "VertexUniforms must match metal_shaders.h");

struct Light {
    std::array<float, 4> position{};
    std::array<float, 4> direction{};
    std::array<float, 4> attenuation{};
    std::array<float, 4> spot{};
    std::array<float, 4> ambient{};
    std::array<float, 4> diffuse{};
    std::array<float, 4> specular{};
    std::array<std::uint32_t, 4> mode{};  // enabled, type, kind
};
static_assert(sizeof(Light) == 128u, "Light must match metal_shaders.h");

// What a lit or fogged draw reads besides its vertices (ge.vert's Environment and Object blocks in one).
struct LightingUniforms {
    std::array<float, 16> world{};
    std::array<float, 4> ambient{};
    std::array<float, 4> emissive{};  // w: the specular power
    std::array<float, 4> material_ambient{};
    std::array<float, 4> material_diffuse{};
    std::array<float, 4> material_specular{};
    std::array<float, 4> fog{};       // end, scale
    std::array<std::uint32_t, 4> flags{};  // update mask, vertex colour, separate specular, reversed normals
    std::array<Light, 4> lights{};
};
static_assert(sizeof(LightingUniforms) == 688u, "LightingUniforms must match metal_shaders.h");

struct FragmentUniforms {
    std::array<float, 4> fix{};
    std::array<std::uint32_t, 4> texture{};
    std::array<std::uint32_t, 4> alpha_test{};
    std::array<float, 4> fog{};               // rgb: the fog colour; w: 1 when fogged
    std::array<std::uint32_t, 4> stencil{};  // x: 1 when the alpha stored is y (the PSP's stencil), not the fragment's
};
static_assert(sizeof(FragmentUniforms) == 80u, "FragmentUniforms must match metal_shaders.h");

// A GE colour register (0x00BBGGRR) as 0..1 floats, with an explicit fourth value.
std::array<float, 4> unpack_color(std::uint32_t color, float fourth = 1.0f) {
    return {static_cast<float>(color & 0xFFu) / 255.0f, static_cast<float>((color >> 8u) & 0xFFu) / 255.0f,
            static_cast<float>((color >> 16u) & 0xFFu) / 255.0f, fourth};
}

// Says once per value which GE state is drawn approximately.
void not_emulated(const char *what, std::uint32_t value) {
    static std::set<std::pair<std::string, std::uint32_t>> seen;
    if (!seen.emplace(what, value).second) return;
    std::cout << "[metal] " << what << " 0x" << std::hex << value << std::dec << " is not emulated\n" << std::flush;
}

std::array<float, 16> multiply(const std::array<float, 16> &a, const std::array<float, 16> &b) {
    std::array<float, 16> result{};
    for (std::uint32_t column = 0; column < 4u; ++column) {
        for (std::uint32_t row = 0; row < 4u; ++row) {
            float sum = 0.0f;
            for (std::uint32_t k = 0; k < 4u; ++k) sum += a[k * 4u + row] * b[column * 4u + k];
            result[column * 4u + row] = sum;
        }
    }
    return result;
}

// A column-major matrix times (x, y, z, 1).
std::array<float, 4> transform_point(const std::array<float, 16> &m, const std::array<float, 4> &p) {
    std::array<float, 4> result{};
    for (std::uint32_t row = 0; row < 4u; ++row)
        result[row] = m[row] * p[0] + m[4u + row] * p[1] + m[8u + row] * p[2] + m[12u + row];
    return result;
}

// The GE's compare functions (depth test, alpha test, stencil test): 0 NEVER, 1 ALWAYS, then EQUAL,
// NOTEQUAL, LESS, LEQUAL, GREATER, GEQUAL.
MTLCompareFunction to_compare(std::uint32_t function) {
    switch (function & 7u) {
    case 0u: return MTLCompareFunctionNever;
    case 1u: return MTLCompareFunctionAlways;
    case 2u: return MTLCompareFunctionEqual;
    case 3u: return MTLCompareFunctionNotEqual;
    case 4u: return MTLCompareFunctionLess;
    case 5u: return MTLCompareFunctionLessEqual;
    case 6u: return MTLCompareFunctionGreater;
    default: return MTLCompareFunctionGreaterEqual;
    }
}

// The GE's stencil operations: 0 KEEP, 1 ZERO, 2 REPLACE, 3 INVERT, 4 INCR, 5 DECR (both clamping).
MTLStencilOperation to_stencil_operation(std::uint32_t op) {
    switch (op & 7u) {
    case 1u: return MTLStencilOperationZero;
    case 2u: return MTLStencilOperationReplace;
    case 3u: return MTLStencilOperationInvert;
    case 4u: return MTLStencilOperationIncrementClamp;
    case 5u: return MTLStencilOperationDecrementClamp;
    default: return MTLStencilOperationKeep;
    }
}

// The stencil reference as the target's alpha holds it: the top bit of a 5551 target, the top nibble of a
// 4444 one, all of 8888 (patch 0006's stored_reference).
std::uint32_t stored_reference(const DrawCall &call) {
    const std::uint32_t reference = call.stencil.reference & 0xFFu;
    if (call.target.color_format == 1u) return (reference & 0x80u) != 0u ? 0xFFu : 0u;
    if (call.target.color_format == 2u) return (reference >> 4u) * 17u;
    return reference;
}

// The value a draw leaves in its target's alpha, which on the PSP is the stencil (patches 0004 and 0006's
// stencil_alpha): -1 keeps the destination's alpha (no stencil test, a 5650 target, which has none, alpha bits
// masked, a zpass KEEP, or INVERT, INCR and DECR, which read the destination and are done by the attachment).
// Only fragments that pass every test write it, as the attachment's zpass operation does.
int stencil_alpha(const DrawCall &call) {
    const pk::StencilState &stencil = call.stencil;
    if (!stencil.enabled || call.target.color_format == 0u || call.alpha_write_mask != 0u) return -1;
    switch (stencil.pass_op) {
    case 1u: return 0;                                               // zero
    case 2u: return static_cast<int>(stored_reference(call));       // replace
    default: return -1;                                              // keep, invert, increment, decrement
    }
}

// Whether the draw leaves its target's alpha equal to the stencil (patch 0006's alpha_follows_stencil). The
// alpha is written only by fragments that pass every test, with stencil_alpha()'s value, so it cannot follow an
// sfail operation where the stencil test can fail, a zfail operation where the depth test can fail, INVERT,
// INCR or DECR on pass, or a write mask that keeps some bits.
bool alpha_follows_stencil(const DrawCall &call, bool depth_can_fail) {
    const pk::StencilState &stencil = call.stencil;
    if (!stencil.enabled || call.target.color_format == 0u || call.alpha_write_mask == 0xFFu) return true;
    const auto writes = [](std::uint32_t op) { return op >= 1u && op <= 5u; };
    const bool fail = stencil.function != 1u && writes(stencil.fail_op);
    const bool depth_fail = depth_can_fail && writes(stencil.depth_fail_op);
    const bool pass = stencil.pass_op >= 3u && stencil.pass_op <= 5u;
    const bool partial = call.alpha_write_mask != 0u &&
                         (writes(stencil.fail_op) || writes(stencil.depth_fail_op) || writes(stencil.pass_op));
    return !fail && !depth_fail && !pass && !partial;
}

const char *format_name(TextureFormat format) {
    static const char *const kNames[] = {"5650", "5551", "4444", "8888", "CLUT4", "CLUT8",
                                         "CLUT16", "CLUT32", "DXT1", "DXT3", "DXT5"};
    const auto index = static_cast<std::size_t>(format);
    return index < std::size(kNames) ? kNames[index] : "?";
}

std::uint32_t texture_bits(TextureFormat format) {
    switch (format) {
    case TextureFormat::Clut4: return 4u;
    case TextureFormat::Clut8: return 8u;
    case TextureFormat::Rgba5650:
    case TextureFormat::Rgba5551:
    case TextureFormat::Rgba4444:
    case TextureFormat::Clut16: return 16u;
    case TextureFormat::Rgba8888:
    case TextureFormat::Clut32: return 32u;
    default: return 0u;
    }
}

bool indexed(TextureFormat format) {
    return format == TextureFormat::Clut4 || format == TextureFormat::Clut8 || format == TextureFormat::Clut16 ||
           format == TextureFormat::Clut32;
}

// A 64-bit hash of bytes, eight at a time.
std::uint64_t hash_bytes(std::uint64_t hash, const std::uint8_t *data, std::size_t size) {
    std::size_t at = 0u;
    for (; at + 8u <= size; at += 8u) {
        std::uint64_t word{};
        std::memcpy(&word, data + at, sizeof(word));
        hash = (hash ^ word) * 0x9E3779B97F4A7C15ull;
        hash ^= hash >> 31u;
    }
    for (; at < size; ++at) hash = (hash ^ data[at]) * 0x100000001B3ull;
    return hash;
}

std::uint64_t hash_value(std::uint64_t hash, std::uint64_t value) {
    hash = (hash ^ value) * 0x9E3779B97F4A7C15ull;
    return hash ^ (hash >> 31u);
}

// `size` bytes of guest memory from `address` into the hash: one run of host memory when they are one,
// word by word otherwise.
std::uint64_t hash_guest(std::uint64_t hash, const GuestMemory &memory, std::uint32_t address, std::size_t size) {
    if (size == 0u) return hash;
    if (const std::uint8_t *data = memory.raw_pointer(address, size)) return hash_bytes(hash, data, size);
    if (!memory.contains(address, size)) return hash_value(hash, 0xDEADu);
    for (std::size_t at = 0u; at < size; ++at) hash = (hash ^ memory.load8(address + static_cast<std::uint32_t>(at))) * 0x100000001B3ull;
    return hash;
}

// A render target: (colour address, stride, pixel format), docs/ge-backend.md section 2.
struct TargetKey {
    std::uint32_t address{};
    std::uint32_t stride{};
    std::uint32_t format{};  // 0 5650, 1 5551, 2 4444, 3 8888
    auto operator<=>(const TargetKey &) const = default;
};

struct Target {
    TargetKey key;
    id<MTLTexture> color;
    id<MTLTexture> depth;  // depth and the stencil, whose copy the colour's alpha is
    id<MTLTexture> copy;   // what a draw samples when it reads the target it draws into
    bool color_defined{};  // drawn or uploaded: a pass loads it rather than clearing it
    bool depth_defined{};
    std::uint64_t draw_serial{};
    std::uint64_t copy_serial{~0ull};
    std::uint64_t last_drawn_frame{~0ull};
    // One word every 256 bytes of the guest memory under the target, taken at its first draw of a
    // frame: a texture bind reads the target only while guest memory still holds these (patch 0003).
    std::vector<std::uint32_t> guest_words;

    [[nodiscard]] std::uint32_t bytes_per_pixel() const { return key.format == 3u ? 4u : 2u; }
};

// The render pipeline state's part of a draw's state.
struct RenderKey {
    bool blend{};
    std::uint8_t source{MTLBlendFactorOne};         // MTLBlendFactor
    std::uint8_t destination{MTLBlendFactorZero};
    std::uint8_t operation{MTLBlendOperationAdd};   // MTLBlendOperation
    std::uint8_t write_mask{MTLColorWriteMaskAll};  // MTLColorWriteMask
    // The alpha's destination factor: ZERO stores the fragment's alpha (the stencil value, or a clear's
    // alpha); ONE adds it (the copy of the stencil into the alpha, resolve_stencil_alpha()).
    std::uint8_t alpha_destination{MTLBlendFactorZero};
    // The colour blend reads the fragment's own alpha from ge_fragment_dual's second output (Source1).
    bool dual_source{};
    bool textured{};
    bool alpha_test{};
    auto operator<=>(const RenderKey &) const = default;
};

// The depth-stencil state's part. The stencil test and operations are the GE's (DrawCall::stencil) on a
// 5551, 4444 or 8888 target, with the bits the alpha write mask leaves writable; the reference is the
// encoder's (setStencilReferenceValue), not the state's.
struct DepthStencilKey {
    std::uint8_t compare{MTLCompareFunctionAlways};  // MTLCompareFunction
    bool write{};
    bool stencil{};
    std::uint8_t stencil_function{};  // the GE's numbering, as the alpha test's
    std::uint8_t fail{};              // the GE's operations: KEEP, ZERO, REPLACE, INVERT, INCR, DECR
    std::uint8_t depth_fail{};
    std::uint8_t pass{};
    std::uint8_t compare_mask{};
    std::uint8_t write_mask{};
    auto operator<=>(const DepthStencilKey &) const = default;
};

// Everything a draw's pipeline is made from.
struct PipelineKey {
    RenderKey render;
    DepthStencilKey depth;
};

// The pre-warm list's text (config/metal_pipelines.txt, PURE_METAL_PIPELINES_OUT): a line per key, `render` or
// `depth` and the key's fields as name=value, the numbers the key holds (Metal's values for the blend factors and
// operations, the write masks and the depth compare; the GE's for the stencil function and operations).
std::string to_text(const RenderKey &key) {
    std::ostringstream out;
    out << "render blend=" << unsigned{key.blend} << " source=" << unsigned{key.source}
        << " destination=" << unsigned{key.destination} << " operation=" << unsigned{key.operation}
        << " write_mask=" << unsigned{key.write_mask} << " alpha_destination=" << unsigned{key.alpha_destination}
        << " dual_source=" << unsigned{key.dual_source} << " textured=" << unsigned{key.textured}
        << " alpha_test=" << unsigned{key.alpha_test};
    return out.str();
}

std::string to_text(const DepthStencilKey &key) {
    std::ostringstream out;
    out << "depth compare=" << unsigned{key.compare} << " write=" << unsigned{key.write}
        << " stencil=" << unsigned{key.stencil} << " function=" << unsigned{key.stencil_function}
        << " fail=" << unsigned{key.fail} << " depth_fail=" << unsigned{key.depth_fail} << " pass=" << unsigned{key.pass}
        << " compare_mask=" << unsigned{key.compare_mask} << " write_mask=" << unsigned{key.write_mask};
    return out.str();
}

// A line of the list as its kind and fields; false for a blank line or a comment (`#`).
bool parse_key_line(const std::string &line, std::string &kind, std::map<std::string, unsigned> &fields) {
    std::istringstream in(line);
    if (!(in >> kind) || kind.front() == '#') return false;
    fields.clear();
    for (std::string field; in >> field;) {
        const std::size_t equals = field.find('=');
        if (equals == std::string::npos) return false;
        fields[field.substr(0, equals)] = static_cast<unsigned>(std::strtoul(field.c_str() + equals + 1, nullptr, 10));
    }
    return true;
}

// The field `name` into `out` when present and it fits; false otherwise.
template <typename T>
bool take_field(const std::map<std::string, unsigned> &fields, const char *name, T &out, unsigned largest = 255u) {
    const auto found = fields.find(name);
    if (found == fields.end() || found->second > largest) return false;
    out = static_cast<T>(found->second);
    return true;
}

bool from_fields(const std::map<std::string, unsigned> &fields, RenderKey &key) {
    return take_field(fields, "blend", key.blend, 1u) && take_field(fields, "source", key.source) &&
           take_field(fields, "destination", key.destination) && take_field(fields, "operation", key.operation) &&
           take_field(fields, "write_mask", key.write_mask) &&
           take_field(fields, "alpha_destination", key.alpha_destination) &&
           take_field(fields, "dual_source", key.dual_source, 1u) && take_field(fields, "textured", key.textured, 1u) &&
           take_field(fields, "alpha_test", key.alpha_test, 1u);
}

bool from_fields(const std::map<std::string, unsigned> &fields, DepthStencilKey &key) {
    return take_field(fields, "compare", key.compare, 7u) && take_field(fields, "write", key.write, 1u) &&
           take_field(fields, "stencil", key.stencil, 1u) && take_field(fields, "function", key.stencil_function, 7u) &&
           take_field(fields, "fail", key.fail, 7u) && take_field(fields, "depth_fail", key.depth_fail, 7u) &&
           take_field(fields, "pass", key.pass, 7u) && take_field(fields, "compare_mask", key.compare_mask) &&
           take_field(fields, "write_mask", key.write_mask);
}

// What a texture bind looks up while its display list runs, before its contents are hashed.
struct TextureIdentity {
    std::uint32_t address{};
    std::uint32_t buffer_width{};
    std::uint32_t size{};
    std::uint32_t format{};
    std::uint32_t clut_address{};
    std::uint32_t clut{};
    bool swizzled{};
    auto operator<=>(const TextureIdentity &) const = default;
};

struct CachedTexture {
    id<MTLTexture> texture;
    std::uint64_t last_used{};
};

// Vertex and upload space handed back by command buffers the GPU has finished with.
struct ChunkPool {
    std::mutex lock;
    std::vector<id<MTLBuffer>> free;
};

// A kind of write into guest memory: how many, how many of them stored something, and the time spent
// waiting for the GPU for them.
struct GuestWrites {
    std::uint64_t calls{};
    std::uint64_t written{};
    double wait_ms{};
};

struct Stats {
    std::uint64_t draws{};
    std::uint64_t passes{};
    std::uint64_t decoded{};
    std::uint64_t framebuffer_textures{};
    std::uint64_t texture_mapped{};  // draws whose texture coordinates came from the texture matrix or the normals
    std::uint64_t copies{};
    std::uint64_t uploads{};
    std::uint64_t waits{};
    double wait_ms{};
    std::uint64_t stencil_draws{};   // draws with the stencil test (a clear of the alpha included)
    std::uint64_t stencil_copies{};  // copies of the stencil into the alpha (resolve_stencil_alpha)
    GuestWrites transfers;           // block_transfer() from a target
    GuestWrites read_backs;          // read_back_framebuffer()
    GuestWrites frames;              // write_back_frame()
    GuestWrites depths;              // write_back_depth()
    std::uint64_t decoded_bytes{};   // of the decoded textures, as uploaded (RGBA8)
    std::uint64_t pipelines_made{};  // render pipelines a draw made, or waited for while pre-warming made them
    std::uint64_t depth_states_made{};
};

// PURE_METAL_TRACE (task 033): what the time between two flips went to, accumulated from one flip's
// present_image() to the next one's. Times in milliseconds.
struct FrameTimes {
    double submit{};        // CPU time in submit()
    double pipeline{};      // of submit: making render pipelines and depth-stencil states (or waiting for the pre-warm)
    double texture{};       // of submit: finding (hashing) and decoding textures from guest memory
    double present{};       // CPU time in present_image(), its waits included
    double memory{};        // CPU time in the calls between guest memory and the GPU, their waits included:
                            // write_back_depth, write_back_frame, block_transfer, read_back_framebuffer,
                            // upload_frame, capture_frame
    double wait_depth{};    // GPU waits: the SIGNAL's depth write-back
    double wait_frame{};    // the frame write-back
    double wait_guest{};    // block transfers and read-backs from a target
    double wait_capture{};  // captures and the Vulkan shell's hand-over
    double wait_ring{};     // more than kFramesInFlight frames in flight
};

// Adds the time from its making to its end to `total` (milliseconds) when `on`; costs nothing more than the test
// when off.
class TraceClock {
public:
    TraceClock(bool on, double &total) : total_(on ? &total : nullptr) {
        if (on) start_ = std::chrono::steady_clock::now();
    }
    ~TraceClock() {
        if (total_ != nullptr)
            *total_ += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start_).count();
    }
    TraceClock(const TraceClock &) = delete;
    TraceClock &operator=(const TraceClock &) = delete;

private:
    double *total_;
    std::chrono::steady_clock::time_point start_{};
};

// A row of the trace, kept until the Metal shell has said when its picture reached the screen.
struct TraceRow {
    std::uint64_t flip{};
    double t_ms{};
    double frame_ms{};
    FrameTimes times;
    Stats counts;  // this interval's (a difference of two snapshots)
    double shell_ms{};
    double drawable_ms{};
    std::uint32_t shell_presents{};
    std::uint32_t occluded{};  // of those presents, made while the window was occluded
};

// The pre-warm (task 033): render pipelines made asynchronously at start from config/metal_pipelines.txt. The
// completion handlers run on Metal's threads and fill `ready`; a draw that needs a key still `pending` waits for it.
struct Prewarm {
    std::mutex lock;
    std::condition_variable changed;
    std::map<RenderKey, id<MTLRenderPipelineState>> ready;
    std::set<RenderKey> pending;
    std::uint32_t asked{};
    std::uint32_t failed{};
    std::chrono::steady_clock::time_point started{};
    double done_ms{};  // from the start to the last completion
};

class MetalGeBackend final : public pk::GeBackend {
public:
    ~MetalGeBackend() override { shutdown(); }

    const char *name() const noexcept override { return "metal"; }
    bool needs_window() const noexcept override { return false; }

    bool initialize(const pk::BackendConfig &config, std::string &error) override {
        @autoreleasepool {
            const auto start = std::chrono::steady_clock::now();
            // The program's one device and queue, which the Metal shell presents on too (metal_device.hpp): its
            // sampling of the frame's target is then ordered after every draw this backend committed before it.
            device_ = pure::metal::device();
            if (device_ == nil) {
                error = "there is no Metal device";
                return false;
            }
            queue_ = pure::metal::queue();
            MTLCompileOptions *options = [MTLCompileOptions new];
            if (@available(macOS 15.0, *)) {
                options.mathMode = MTLMathModeSafe;
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                options.fastMathEnabled = NO;
#pragma clang diagnostic pop
            }
            NSError *failure = nil;
            library_ = [device_ newLibraryWithSource:@(pure::metal::kShaderSource) options:options error:&failure];
            if (library_ == nil) {
                error = std::string("the shaders do not compile: ") +
                        (failure != nil ? failure.localizedDescription.UTF8String : "no message");
                return false;
            }
            vertex_function_ = [library_ newFunctionWithName:@"ge_vertex"];
            // By kTextured | kAlphaTest << 1, then the same with the second output for dual-source blending.
            for (std::uint32_t variant = 0; variant < fragment_functions_.size(); ++variant) {
                MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
                const bool textured = (variant & 1u) != 0u;
                const bool alpha_test = (variant & 2u) != 0u;
                [values setConstantValue:&textured type:MTLDataTypeBool atIndex:0];
                [values setConstantValue:&alpha_test type:MTLDataTypeBool atIndex:1];
                fragment_functions_[variant] =
                    [library_ newFunctionWithName:(variant & 4u) != 0u ? @"ge_fragment_dual" : @"ge_fragment"
                                   constantValues:values
                                            error:&failure];
                if (fragment_functions_[variant] == nil) {
                    error = std::string("the fragment function does not specialise: ") +
                            (failure != nil ? failure.localizedDescription.UTF8String : "no message");
                    return false;
                }
            }
            if (vertex_function_ == nil) {
                error = "the shaders have no ge_vertex";
                return false;
            }
            // Samplers by index: bit 0 linear magnification, bit 1 linear minification, bit 2 clamp u,
            // bit 3 clamp v.
            for (std::uint32_t index = 0; index < samplers_.size(); ++index) {
                MTLSamplerDescriptor *sampler = [MTLSamplerDescriptor new];
                sampler.magFilter = (index & 1u) != 0u ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
                sampler.minFilter = (index & 2u) != 0u ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
                sampler.sAddressMode = (index & 4u) != 0u ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
                sampler.tAddressMode = (index & 8u) != 0u ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
                samplers_[index] = [device_ newSamplerStateWithDescriptor:sampler];
            }
            MTLTextureDescriptor *white = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                            width:1
                                                                                           height:1
                                                                                        mipmapped:NO];
            white.storageMode = MTLStorageModeShared;
            white.usage = MTLTextureUsageShaderRead;
            white_ = [device_ newTextureWithDescriptor:white];
            const std::uint32_t opaque_white = 0xFFFFFFFFu;
            [white_ replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&opaque_white bytesPerRow:4];
            readback_ = [device_ newBufferWithLength:kPictureBytes options:MTLResourceStorageModeShared];
            frame_writeback_ = [device_ newBufferWithLength:kPictureBytes options:MTLResourceStorageModeShared];
            guest_readback_ = [device_ newBufferWithLength:kPictureBytes options:MTLResourceStorageModeShared];
            pool_ = std::make_shared<ChunkPool>();

            // The hand-over (a read-back a frame) only for the Vulkan shell; any other shell has
            // vulkan_shell null and shows the texture present_image() names, or no window at all.
            shell_ = config.vulkan_shell;
            sharp_ = config.sharp_textures;
            const char *shell_switch = portablekit::env("METAL_SHELL");
            to_shell_ = shell_ != nullptr && !(shell_switch != nullptr && std::strcmp(shell_switch, "0") == 0);
            const char *log = portablekit::env("METAL_LOG");
            log_draws_ = log != nullptr && *log != '\0' && std::strcmp(log, "0") != 0;
            no_framebuffer_textures_ = portablekit::env("NO_FB_TEXTURES") != nullptr;
            // The framework's switches for bisecting 3D draws, as the Vulkan backend reads them: NO_LIGHTING
            // draws lit geometry with its vertex colour (white without one) and turns fog off too, NO_FOG turns
            // fog off alone, NO_CULL culls nothing.
            no_lighting_ = portablekit::env("NO_LIGHTING") != nullptr;
            no_fog_ = no_lighting_ || portablekit::env("NO_FOG") != nullptr;
            no_cull_ = portablekit::env("NO_CULL") != nullptr;
            // Ours (task 036): every draw takes its UVs (texture map mode 0), as before the mapping modes.
            no_texture_map_ = portablekit::env("NO_TEXMAP") != nullptr;
            // The framework's traces, as the Vulkan backend reads them: a line per copy of the stencil into the
            // alpha, and per depth write-back.
            trace_stencil_copy_ = portablekit::env("TRACE_STENCIL_COPY") != nullptr;
            trace_depth_ = portablekit::env("TRACE_DEPTH_READBACK") != nullptr;
            started_ = std::chrono::steady_clock::now();
            report_start_ = started_;
            ready_ = true;
            const double ms = std::chrono::duration<double, std::milli>(started_ - start).count();
            std::cout << "[metal] drawing with " << device_.name.UTF8String << " at 480x272, shaders compiled in "
                      << ms << " ms; "
                      << (to_shell_ ? "pictures shown in the window"
                                    : (shell_ != nullptr ? "window left black (PURE_METAL_SHELL=0)"
                                                         : "pictures shown by the shell, not read back"))
                      << "\n";
            // Task 033: the frame trace, the list of keys a run used, and the pre-warm.
            if (pure::metal::trace_on()) open_trace(portablekit::env("METAL_TRACE"));
            if (const char *out = portablekit::env("METAL_PIPELINES_OUT"); out != nullptr && *out != '\0')
                pipelines_out_ = out;
            start_prewarm();
            return true;
        }
    }

    void shutdown() override {
        if (!ready_) return;
        ready_ = false;
        @autoreleasepool {
            commit(true);
            for (id<MTLCommandBuffer> commands : in_flight_) [commands waitUntilCompleted];
            in_flight_.clear();
            const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started_).count();
            std::cout << "[metal] " << frames_ << " frames, " << stats_.draws << " draws, " << stats_.passes
                      << " passes, " << stats_.decoded << " textures decoded, " << stats_.framebuffer_textures
                      << " framebuffer textures, " << stats_.texture_mapped << " texture-mapped draws, "
                      << stats_.copies << " target copies, " << stats_.uploads
                      << " uploads, " << targets_.size() << " targets, " << stats_.waits << " GPU waits ("
                      << stats_.wait_ms << " ms) in " << seconds << " s\n";
            report_guest_writes();
            report_pipelines();
            close_trace();
            write_pipeline_list();
            std::cout << std::flush;
            // Every target's resources before the device they came from (the contract's order).
            presented_ = nullptr;
            last_drawn_ = nullptr;
            current_target_ = nullptr;
            targets_.clear();
            textures_.clear();
            list_keys_.clear();
            render_pipelines_.clear();
            depth_states_.clear();
            if (prewarm_) {
                // Pipelines still compiling finish into the shared state their handlers hold, not into this.
                std::lock_guard<std::mutex> guard(prewarm_->lock);
                prewarm_->ready.clear();
            }
            prewarm_.reset();
            samplers_.fill(nil);
            if (pool_) {
                std::lock_guard<std::mutex> guard(pool_->lock);
                pool_->free.clear();
            }
            chunk_ = nil;
            white_ = nil;
            readback_ = nil;
            frame_writeback_ = nil;
            guest_readback_ = nil;
            pending_frame_ = PendingFrame{};
            fragment_functions_.fill(nil);
            vertex_function_ = nil;
            library_ = nil;
            queue_ = nil;
            device_ = nil;
        }
    }

    void begin_frame() override {}

    void begin_display_list() override { list_keys_.clear(); }

    void submit(const DrawCall &call, const GuestMemory &memory) override {
        if (!ready_) return;
        const TraceClock clock(trace_file_ != nullptr, times_.submit);
        @autoreleasepool {
            draw(call, memory);
        }
    }

    // Before the HLE copies a block transfer's rows: when the source lies in a target this backend drew, the
    // target's rows the copy reads are stored in guest memory first, in the target's format.
    void block_transfer(const pk::BlockTransfer &transfer, GuestMemory &memory) override {
        ++stats_.transfers.calls;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        if (!ready_ || no_framebuffer_textures_ || transfer.width == 0u || transfer.height == 0u ||
            transfer.bytes_per_pixel == 0u)
            return;
        @autoreleasepool {
            const std::uint64_t base = GuestMemory::canonical(transfer.source);
            const std::uint64_t pitch = static_cast<std::uint64_t>(transfer.source_stride) * transfer.bytes_per_pixel;
            const std::uint64_t first =
                base + transfer.source_y * pitch + static_cast<std::uint64_t>(transfer.source_x) * transfer.bytes_per_pixel;
            const std::uint64_t end = first + (transfer.height - 1u) * pitch +
                                      static_cast<std::uint64_t>(transfer.width) * transfer.bytes_per_pixel;
            Target *target = drawn_target_containing(static_cast<std::uint32_t>(base), first);
            if (target == nullptr) return;
            // The target's rows the copy's bytes fall in.
            const std::uint64_t row_bytes = static_cast<std::uint64_t>(target->key.stride) * target->bytes_per_pixel();
            const std::uint64_t from = std::max<std::uint64_t>(first, target->key.address);
            const auto first_row = static_cast<std::uint32_t>((from - target->key.address) / row_bytes);
            const auto last_row = static_cast<std::uint32_t>(
                std::min<std::uint64_t>((end - 1u - target->key.address) / row_bytes, kHeight - 1u));
            if (first_row > last_row) return;
            store_target(memory, *target, first_row, last_row - first_row + 1u, stats_.transfers);
        }
    }

    // The frame shown at the last flip into guest VRAM, in its format (the Vulkan backend's write-back, which
    // stores at each flip the target the flip before showed). present_image() copied its pixels into a shared
    // buffer, or read them back for the Vulkan shell; this waits for that copy and stores them.
    void write_back_frame(GuestMemory &memory) override {
        ++stats_.frames.calls;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        if (!ready_ || pending_frame_.target == nullptr) return;
        PendingFrame pending = pending_frame_;
        pending_frame_ = PendingFrame{};
        @autoreleasepool {
            const std::uint8_t *pixels = picture_.data();
            if (!pending.from_picture) {
                if (pending.commands != nil && pending.commands.status < MTLCommandBufferStatusCompleted) {
                    const auto start = std::chrono::steady_clock::now();
                    [pending.commands waitUntilCompleted];
                    const double ms =
                        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
                    stats_.wait_ms += ms;
                    stats_.frames.wait_ms += ms;
                    times_.wait_frame += ms;
                    ++stats_.waits;
                }
                pixels = static_cast<const std::uint8_t *>(frame_writeback_.contents);
            } else if (picture_.size() != kPictureBytes) {
                return;
            }
            if (store_pixels(memory, *pending.target, pixels, 0u, kHeight)) ++stats_.frames.written;
        }
    }

    // The target at `address` into guest VRAM, whole (the Vulkan backend's rule: a target in VRAM that the GE
    // drew, at least as wide as the screen).
    void read_back_framebuffer(std::uint32_t address, GuestMemory &memory) override {
        ++stats_.read_backs.calls;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        if (!ready_ || no_framebuffer_textures_) return;
        @autoreleasepool {
            const std::uint32_t wanted = GuestMemory::canonical(address);
            Target *target = drawn_target_containing(wanted, wanted);
            if (target == nullptr || target->key.stride < kWidth) return;
            store_target(memory, *target, 0u, kHeight, stats_.read_backs);
        }
    }

    // The depth of the target at `color_address` as the GE keeps it, z = round(depth x 65535) in 16 bits, in
    // rows of `depth_stride` pixels from `depth_address` (patch 0008): the lens flare's SIGNAL handler reads a
    // 4x4 block of it around the sun. Screen-wide depth buffers only, as the Vulkan backend writes them.
    bool write_back_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                          GuestMemory &memory, const char *why) override {
        ++stats_.depths.calls;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        if (!ready_) return false;
        @autoreleasepool {
            return store_depth(color_address, depth_address, depth_stride, memory, why);
        }
    }

    void upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                      std::uint32_t height, std::uint32_t stride) override {
        if (!ready_ || pixels == nullptr || width == 0u || height == 0u || stride < width) return;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        @autoreleasepool {
            upload(display_address, pixels, width, height, stride);
        }
    }

    pk::PresentedImage present_image(std::uint32_t display_address) override {
        pk::PresentedImage image;
        if (!ready_) return image;
        // The trace's row of the interval this flip ends, before this call's own time, which starts the next one.
        if (trace_file_ != nullptr) end_trace_interval();
        const TraceClock clock(trace_file_ != nullptr, times_.present);
        @autoreleasepool {
            ++frames_;
            if (trace_file_ != nullptr) pure::metal::trace_flip(frames_);
            frame_draws_ = 0u;
            Target *shown = latest_target_at(GuestMemory::canonical(display_address));
            if (shown == nullptr) shown = last_drawn_;
            presented_ = shown;
            // The next write_back_frame() stores this picture (as the Vulkan backend stores at each flip the
            // target the flip before showed): read back for the Vulkan shell anyway, else copied into a shared
            // buffer by this frame's commands.
            const bool written_back = shown != nullptr && frame_written_back(*shown);
            pending_frame_ = PendingFrame{};
            if (shown != nullptr && to_shell_) {
                read_back(*shown);
                show_in_shell(shell_, display_address, picture_.data(), kWidth, kHeight, shell_scratch_);
                if (written_back) pending_frame_ = PendingFrame{shown, nil, true};
            } else {
                if (written_back) copy_to_buffer(*shown, frame_writeback_);
                id<MTLCommandBuffer> committed = commit(false);
                if (written_back) pending_frame_ = PendingFrame{shown, committed, false};
            }
            if (frames_ % kReportEvery == 0u) report();
            if (prewarm_ && !prewarm_reported_) report_prewarm_done();
            if (shown != nullptr) {
                image.api = pk::ImageApi::Metal;
                image.address = shown->key.address;
                image.width = kWidth;
                image.height = kHeight;
                image.image = reinterpret_cast<std::uint64_t>((__bridge void *)shown->color);
            }
        }
        return image;
    }

    bool capture_frame(const std::string &path) override {
        if (!ready_ || presented_ == nullptr) return false;
        const TraceClock clock(trace_file_ != nullptr, times_.memory);
        @autoreleasepool {
            if (picture_frame_ != frames_) read_back(*presented_);
            return pk::write_bmp_file(path, picture_.data(), kWidth, kHeight);
        }
    }

    std::uint64_t draws_submitted() const noexcept override { return stats_.draws; }
    std::uint64_t frames_presented() const noexcept override { return frames_; }

private:
    // -----------------------------------------------------------------------------------------------
    // Command buffers, passes and space

    void ensure_commands() {
        if (commands_ != nil) return;
        commands_ = [queue_ commandBuffer];
        frame_buffers_ = [NSMutableArray new];
    }

    // Ends the pass. Whatever reads the target next (a texture, the display, guest memory) reads its alpha,
    // so a stencil the draws left different from it is copied into it first.
    void end_encoder() {
        if (encoder_ != nil) {
            if (alpha_stale_) resolve_stencil_alpha("end of pass");
            [encoder_ endEncoding];
            encoder_ = nil;
        }
        alpha_stale_ = false;
        current_target_ = nullptr;
    }

    // Hands the frame's commands to the GPU; with `wait`, returns once it has drawn them. Returns the command
    // buffer committed (nil when there was nothing to commit).
    id<MTLCommandBuffer> commit(bool wait) {
        end_encoder();
        if (commands_ == nil) return nil;
        const std::shared_ptr<ChunkPool> pool = pool_;
        NSArray<id<MTLBuffer>> *used = frame_buffers_;
        [commands_ addCompletedHandler:^(id<MTLCommandBuffer>) {
            std::lock_guard<std::mutex> guard(pool->lock);
            for (id<MTLBuffer> buffer in used)
                if (buffer.length == kChunkBytes) pool->free.push_back(buffer);
        }];
        [commands_ commit];
        id<MTLCommandBuffer> committed = commands_;
        commands_ = nil;
        frame_buffers_ = nil;
        chunk_ = nil;
        if (wait) {
            const auto start = std::chrono::steady_clock::now();
            [committed waitUntilCompleted];
            last_wait_ms_ = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            stats_.wait_ms += last_wait_ms_;
            ++stats_.waits;
            check(committed);
            return committed;
        }
        in_flight_.push_back(committed);
        while (!in_flight_.empty() && in_flight_.front().status >= MTLCommandBufferStatusCompleted) {
            check(in_flight_.front());
            in_flight_.pop_front();
        }
        while (in_flight_.size() > kFramesInFlight) {
            const auto start = std::chrono::steady_clock::now();
            [in_flight_.front() waitUntilCompleted];
            const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            stats_.wait_ms += ms;
            times_.wait_ring += ms;
            ++stats_.waits;
            check(in_flight_.front());
            in_flight_.pop_front();
        }
        return committed;
    }

    void check(id<MTLCommandBuffer> commands) {
        if (commands.status != MTLCommandBufferStatusError) return;
        static std::uint32_t reported = 0u;
        if (reported++ < 8u)
            std::cout << "[metal] the GPU failed a frame's commands: "
                      << (commands.error != nil ? commands.error.localizedDescription.UTF8String : "no message")
                      << "\n" << std::flush;
    }

    // `bytes` of shared memory for the frame being recorded, at a 256-byte boundary.
    std::pair<id<MTLBuffer>, NSUInteger> allocate(std::size_t bytes) {
        ensure_commands();
        bytes = (bytes + 255u) & ~std::size_t{255u};
        if (bytes > kChunkBytes) {
            id<MTLBuffer> buffer = [device_ newBufferWithLength:bytes options:MTLResourceStorageModeShared];
            [frame_buffers_ addObject:buffer];
            return {buffer, 0u};
        }
        if (chunk_ == nil || chunk_used_ + bytes > kChunkBytes) {
            {
                std::lock_guard<std::mutex> guard(pool_->lock);
                if (!pool_->free.empty()) {
                    chunk_ = pool_->free.back();
                    pool_->free.pop_back();
                } else {
                    chunk_ = nil;
                }
            }
            if (chunk_ == nil) chunk_ = [device_ newBufferWithLength:kChunkBytes options:MTLResourceStorageModeShared];
            chunk_used_ = 0u;
            [frame_buffers_ addObject:chunk_];
        }
        const NSUInteger offset = chunk_used_;
        chunk_used_ += bytes;
        return {chunk_, offset};
    }

    void begin_pass(Target &target) {
        if (encoder_ != nil && current_target_ == &target) return;
        end_encoder();
        ensure_commands();
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target.color;
        pass.colorAttachments[0].loadAction = target.color_defined ? MTLLoadActionLoad : MTLLoadActionClear;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.depthAttachment.texture = target.depth;
        pass.depthAttachment.loadAction = target.depth_defined ? MTLLoadActionLoad : MTLLoadActionClear;
        pass.depthAttachment.clearDepth = 0.0;
        pass.depthAttachment.storeAction = MTLStoreActionStore;
        pass.stencilAttachment.texture = target.depth;
        pass.stencilAttachment.loadAction = target.depth_defined ? MTLLoadActionLoad : MTLLoadActionClear;
        pass.stencilAttachment.clearStencil = 0u;
        pass.stencilAttachment.storeAction = MTLStoreActionStore;
        encoder_ = [commands_ renderCommandEncoderWithDescriptor:pass];
        target.color_defined = true;
        target.depth_defined = true;
        current_target_ = &target;
        last_drawn_ = &target;
        bound_ = Bound{};
        lighting_bound_ = false;
        ++stats_.passes;
    }

    // The target's pixels into picture_, waiting for the GPU.
    void read_back(Target &target) {
        ensure_commands();
        end_encoder();
        id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
        [blit copyFromTexture:target.color
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(kWidth, kHeight, 1)
                            toBuffer:readback_
                   destinationOffset:0
              destinationBytesPerRow:kWidth * 4u
            destinationBytesPerImage:kPictureBytes];
        [blit endEncoding];
        commit(true);
        times_.wait_capture += last_wait_ms_;
        picture_.assign(static_cast<const std::uint8_t *>(readback_.contents),
                        static_cast<const std::uint8_t *>(readback_.contents) + kPictureBytes);
        picture_frame_ = frames_;
    }

    // A blit of the target's colour into `buffer` (480x272 RGBA), recorded in the frame's commands.
    void copy_to_buffer(Target &target, id<MTLBuffer> buffer) {
        ensure_commands();
        end_encoder();
        id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
        [blit copyFromTexture:target.color
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(kWidth, kHeight, 1)
                            toBuffer:buffer
                   destinationOffset:0
              destinationBytesPerRow:kWidth * 4u
            destinationBytesPerImage:kPictureBytes];
        [blit endEncoding];
    }

    // -----------------------------------------------------------------------------------------------
    // Guest memory: block transfers, read-backs and write-backs

    // The target whose memory holds byte `address` and which the GE drew into (an upload's target holds a
    // picture the CPU wrote, which is in guest memory already), in VRAM: the one starting at `start` first
    // (patch 0003's rule), else the one drawn last.
    Target *drawn_target_containing(std::uint32_t start, std::uint64_t address) {
        Target *best = nullptr;
        bool best_exact = false;
        for (auto &[key, target] : targets_) {
            if (!target->color_defined || target->guest_words.empty()) continue;
            if ((key.address & 0x1F000000u) != 0x04000000u) continue;
            const std::uint64_t bytes = static_cast<std::uint64_t>(key.stride) * kHeight * target->bytes_per_pixel();
            if (address < key.address || address - key.address >= bytes) continue;
            const bool exact = key.address == start;
            if (best == nullptr || (exact && !best_exact) ||
                (exact == best_exact && target->draw_serial > best->draw_serial)) {
                best = target.get();
                best_exact = exact;
            }
        }
        return best;
    }

    // Whether the frame write-back stores this displayed target: one the GE drew, in VRAM, at least as wide as
    // the screen (the Vulkan backend's record_writeback rule).
    static bool frame_written_back(const Target &target) {
        return target.color_defined && !target.guest_words.empty() &&
               (target.key.address & 0x1F000000u) == 0x04000000u && target.key.stride >= kWidth;
    }

    // Rows `first_row` to `first_row + rows - 1` of the target into guest memory, read back now (a blit into a
    // shared buffer and a wait), counted in `writes`.
    void store_target(GuestMemory &memory, Target &target, std::uint32_t first_row, std::uint32_t rows,
                      GuestWrites &writes) {
        copy_to_buffer(target, guest_readback_);
        commit(true);
        writes.wait_ms += last_wait_ms_;
        times_.wait_guest += last_wait_ms_;
        if (store_pixels(memory, target, static_cast<const std::uint8_t *>(guest_readback_.contents), first_row, rows))
            ++writes.written;
    }

    // 480x272 RGBA pixels (red in the low byte) of `target` into its guest memory, rows `first_row` onward, in
    // its format and stride (min(stride, 480) pixels a row): 8888 as they are, 5650, 5551 and 4444 packed with
    // red in the low bits, as texture_decode reads them and the Vulkan backend's store_frame writes them. The
    // target's guest-word snapshot is taken again, since memory now holds what it shows.
    bool store_pixels(GuestMemory &memory, Target &target, const std::uint8_t *pixels, std::uint32_t first_row,
                      std::uint32_t rows) {
        const std::uint32_t bytes_per_pixel = target.bytes_per_pixel();
        const std::uint32_t width = std::min(target.key.stride, kWidth);
        rows = std::min(rows, kHeight - std::min(first_row, kHeight));
        if (rows == 0u || width == 0u) return false;
        const std::size_t pitch = static_cast<std::size_t>(target.key.stride) * bytes_per_pixel;
        const std::uint32_t start = target.key.address + static_cast<std::uint32_t>(first_row * pitch);
        std::uint8_t *out =
            memory.raw_pointer(start, (rows - 1u) * pitch + static_cast<std::size_t>(width) * bytes_per_pixel);
        if (out == nullptr) return false;
        static_assert(std::endian::native == std::endian::little, "guest memory is little-endian, as the host");
        std::array<std::uint16_t, kWidth> packed{};
        for (std::uint32_t y = 0; y < rows; ++y) {
            const std::uint8_t *row = pixels + static_cast<std::size_t>(first_row + y) * kWidth * 4u;
            std::uint8_t *line = out + y * pitch;
            if (target.key.format == 3u) {
                std::memcpy(line, row, static_cast<std::size_t>(width) * 4u);
                continue;
            }
            for (std::uint32_t x = 0; x < width; ++x) {
                const std::uint32_t r = row[x * 4u], g = row[x * 4u + 1u], b = row[x * 4u + 2u], a = row[x * 4u + 3u];
                if (target.key.format == 0u)
                    packed[x] = static_cast<std::uint16_t>((r >> 3u) | (g >> 2u) << 5u | (b >> 3u) << 11u);
                else if (target.key.format == 1u)
                    packed[x] =
                        static_cast<std::uint16_t>((r >> 3u) | (g >> 3u) << 5u | (b >> 3u) << 10u | (a >> 7u) << 15u);
                else
                    packed[x] =
                        static_cast<std::uint16_t>((r >> 4u) | (g >> 4u) << 4u | (b >> 4u) << 8u | (a >> 4u) << 12u);
            }
            std::memcpy(line, packed.data(), static_cast<std::size_t>(width) * 2u);
        }
        snapshot_guest_words(memory, target);
        return true;
    }

    // write_back_depth(): the depth aspect of the target's Depth32Float_Stencil8 texture into a shared buffer
    // (a blit and a wait), then z = round(depth x 65535) per pixel. The vertex function and the viewport's depth
    // range map the GE's z onto depth z / 65535, so this is the GE's own z.
    bool store_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                     GuestMemory &memory, const char *why) {
        Target *target = latest_target_at(GuestMemory::canonical(color_address));
        if (target == nullptr || !target->depth_defined) return false;
        // The GE's depth buffer always lies in VRAM. A narrower one, a render-to-texture target's, has no
        // height the GE states, and 272 rows of it could run over what the game keeps after it.
        depth_address = 0x04000000u | (depth_address & 0x001FFFF0u);
        if (depth_stride < kWidth) return false;
        std::uint8_t *out = memory.raw_pointer(depth_address, static_cast<std::size_t>(depth_stride) * kHeight * 2u);
        if (out == nullptr) return false;
        const auto start = std::chrono::steady_clock::now();
        ensure_commands();
        end_encoder();
        id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
        [blit copyFromTexture:target->depth
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(kWidth, kHeight, 1)
                            toBuffer:guest_readback_
                   destinationOffset:0
              destinationBytesPerRow:kWidth * 4u
            destinationBytesPerImage:kPictureBytes
                             options:MTLBlitOptionDepthFromDepthStencil];
        [blit endEncoding];
        commit(true);
        stats_.depths.wait_ms += last_wait_ms_;
        times_.wait_depth += last_wait_ms_;
        const auto *depths = static_cast<const float *>(guest_readback_.contents);
        std::uint32_t lowest = 0xFFFFu, highest = 0u;
        std::array<std::uint16_t, kWidth> row{};
        for (std::uint32_t y = 0; y < kHeight; ++y) {
            for (std::uint32_t x = 0; x < kWidth; ++x) {
                const float depth = depths[static_cast<std::size_t>(y) * kWidth + x];
                const auto z = static_cast<std::uint32_t>(std::clamp(depth, 0.0f, 1.0f) * 65535.0f + 0.5f);
                lowest = std::min(lowest, z);
                highest = std::max(highest, z);
                row[x] = static_cast<std::uint16_t>(z);
            }
            std::memcpy(out + static_cast<std::size_t>(y) * depth_stride * 2u, row.data(), sizeof(row));
        }
        ++stats_.depths.written;
        if (!std::exchange(depth_announced_, true))
            std::cout << "[metal] depth written back to guest memory at 0x" << std::hex << depth_address << std::dec
                      << " for " << why << " (PURE_NO_DEPTH_READBACK turns it off)\n";
        if (trace_depth_) {
            const double total =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            std::cout << "[metal] frame " << frames_ + 1u << " " << why << ": depth of 0x" << std::hex
                      << target->key.address << " written back to 0x" << depth_address << std::dec << " stride "
                      << depth_stride << ", z " << lowest << "-" << highest << ", " << total << " ms (GPU wait "
                      << last_wait_ms_ << " ms)\n";
        }
        return true;
    }

    void report_guest_writes() {
        const auto line = [](const char *what, const GuestWrites &writes) {
            std::cout << " " << what << " " << writes.written << "/" << writes.calls << " (" << writes.wait_ms
                      << " ms waited)";
        };
        std::cout << "[metal] stencil: " << stats_.stencil_draws << " draws, " << stats_.stencil_copies
                  << " copies into the alpha; guest memory written/asked:";
        line("transfers", stats_.transfers);
        line("read-backs", stats_.read_backs);
        line("frames", stats_.frames);
        line("depths", stats_.depths);
        std::cout << "\n";
    }

    void report() {
        const auto now = std::chrono::steady_clock::now();
        const double seconds = std::chrono::duration<double>(now - report_start_).count();
        const std::uint64_t frames = frames_ - report_frames_;
        std::cout << "[metal] frame " << frames_ << ", " << stats_.draws << " draws ("
                  << (stats_.draws - report_draws_) << " in the last " << frames << " frames, "
                  << (seconds > 0.0 ? static_cast<double>(frames) / seconds : 0.0) << " fps), " << targets_.size()
                  << " targets, " << textures_.size() << " textures cached, " << stats_.decoded << " decoded\n";
        report_start_ = now;
        report_frames_ = frames_;
        report_draws_ = stats_.draws;
    }

    // -----------------------------------------------------------------------------------------------
    // The frame trace (PURE_METAL_TRACE, task 033)

    static constexpr const char *kTraceHeader =
        "flip,t_ms,frame_ms,submit_ms,pipeline_ms,texture_ms,present_ms,memory_ms,wait_ms,wait_depth_ms,"
        "wait_frame_ms,wait_guest_ms,wait_capture_ms,wait_ring_ms,pipelines,depth_states,decoded,decoded_kb,"
        "stencil_copies,draws,passes,copies,shell_ms,drawable_ms,occluded,shown_ms,latency_ms,other_ms";
    // How many flips a row waits for the shell to say when its picture reached the screen.
    static constexpr std::uint64_t kTraceDelay = 30u;

    void open_trace(const char *path) {
        std::error_code ignored;
        const std::filesystem::path file(path);
        if (file.has_parent_path()) std::filesystem::create_directories(file.parent_path(), ignored);
        trace_file_ = std::fopen(path, "w");
        if (trace_file_ == nullptr) {
            std::cout << "[metal] cannot write the frame trace to " << path << "\n";
            return;
        }
        trace_path_ = path;
        std::fprintf(trace_file_, "%s\n", kTraceHeader);
        trace_stats_ = stats_;
        times_ = FrameTimes{};
        std::cout << "[metal] frame trace: a row per flip -> " << path << "\n";
    }

    // At a flip: the row of the interval since the previous flip, and the rows whose pictures the shell has
    // reported on written out.
    void end_trace_interval() {
        const auto now = std::chrono::steady_clock::now();
        TraceRow row;
        row.flip = frames_ + 1u;
        row.t_ms = std::chrono::duration<double, std::milli>(now - started_).count();
        row.frame_ms = std::chrono::duration<double, std::milli>(now - (trace_has_flip_ ? trace_last_flip_ : started_)).count();
        trace_last_flip_ = now;
        trace_has_flip_ = true;
        row.times = std::exchange(times_, FrameTimes{});
        row.counts = since(trace_stats_);
        trace_stats_ = stats_;
        const pure::metal::ShellPresents shell = pure::metal::take_shell_presents();
        row.shell_ms = shell.cpu_ms;
        row.drawable_ms = shell.drawable_ms;
        row.shell_presents = shell.count;
        row.occluded = shell.occluded;
        if (shell.count != 0u) shell_seen_ = true;
        pending_rows_.push_back(row);
        flush_trace(false);
    }

    // The counts of stats_ since `before`.
    Stats since(const Stats &before) const {
        Stats d;
        d.draws = stats_.draws - before.draws;
        d.passes = stats_.passes - before.passes;
        d.decoded = stats_.decoded - before.decoded;
        d.decoded_bytes = stats_.decoded_bytes - before.decoded_bytes;
        d.copies = stats_.copies - before.copies;
        d.stencil_copies = stats_.stencil_copies - before.stencil_copies;
        d.pipelines_made = stats_.pipelines_made - before.pipelines_made;
        d.depth_states_made = stats_.depth_states_made - before.depth_states_made;
        return d;
    }

    // Writes the rows in order, each once the shell has reported when its picture reached the screen (under the
    // Metal shell; at once under any other), or kTraceDelay flips later, or with `all` at the end.
    void flush_trace(bool all) {
        while (!pending_rows_.empty()) {
            const TraceRow &row = pending_rows_.front();
            double presented_s = 0.0, latency_ms = 0.0;
            const bool known = pure::metal::take_presented(row.flip, presented_s, latency_ms);
            if (!known && shell_seen_ && !all && frames_ + 1u - row.flip < kTraceDelay) break;
            write_trace_row(row, known, presented_s, latency_ms);
            pending_rows_.pop_front();
        }
    }

    // `known`: the shell reported on the flip's picture; it reached the screen at presented_s, or never (0).
    void write_trace_row(const TraceRow &row, bool known, double presented_s, double latency_ms) {
        const FrameTimes &t = row.times;
        const Stats &c = row.counts;
        const double waits = t.wait_depth + t.wait_frame + t.wait_guest + t.wait_capture + t.wait_ring;
        const double other = row.frame_ms - t.submit - t.present - t.memory - row.shell_ms;
        std::fprintf(trace_file_,
                     "%llu,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%llu,%llu,%llu,%.1f,%llu,"
                     "%llu,%llu,%llu,",
                     static_cast<unsigned long long>(row.flip), row.t_ms, row.frame_ms, t.submit, t.pipeline, t.texture,
                     t.present, t.memory, waits, t.wait_depth, t.wait_frame, t.wait_guest, t.wait_capture, t.wait_ring,
                     static_cast<unsigned long long>(c.pipelines_made), static_cast<unsigned long long>(c.depth_states_made),
                     static_cast<unsigned long long>(c.decoded), static_cast<double>(c.decoded_bytes) / 1024.0,
                     static_cast<unsigned long long>(c.stencil_copies), static_cast<unsigned long long>(c.draws),
                     static_cast<unsigned long long>(c.passes), static_cast<unsigned long long>(c.copies));
        // The shell's columns are empty where no Metal shell presents.
        if (shell_seen_) std::fprintf(trace_file_, "%.3f,%.3f,%u,", row.shell_ms, row.drawable_ms, row.occluded);
        else std::fprintf(trace_file_, ",,,");
        // shown_ms: since the last picture that reached the screen, 0 for one that never did, empty when unknown.
        const bool presented = known && presented_s > 0.0;
        if (presented && last_presented_s_ > 0.0)
            std::fprintf(trace_file_, "%.3f,", (presented_s - last_presented_s_) * 1000.0);
        else if (known && !presented)
            std::fprintf(trace_file_, "0,");
        else std::fprintf(trace_file_, ",");
        if (presented) {
            std::fprintf(trace_file_, "%.3f,", latency_ms);
            last_presented_s_ = presented_s;
            ++trace_shown_;
        } else {
            std::fprintf(trace_file_, ",");
            if (known) ++trace_not_shown_;
        }
        std::fprintf(trace_file_, "%.3f\n", other);
        if (++trace_rows_ % 60u == 0u) std::fflush(trace_file_);
    }

    void close_trace() {
        if (trace_file_ == nullptr) return;
        flush_trace(true);
        std::fclose(trace_file_);
        trace_file_ = nullptr;
        std::cout << "[metal] frame trace: " << trace_rows_ << " rows -> " << trace_path_;
        if (shell_seen_)
            std::cout << "; the shell's pictures: " << trace_shown_ << " reached the screen, " << trace_not_shown_
                      << " never did, " << trace_rows_ - trace_shown_ - trace_not_shown_ << " not reported";
        std::cout << "\n";
    }

    // -----------------------------------------------------------------------------------------------
    // Pipelines: the pre-warm and the list of keys a run used (task 033)

    // The pre-warm list: PURE_METAL_PIPELINES names it (0 or empty turns the pre-warm off); otherwise
    // metal_pipelines.txt in an app's Resources, config/metal_pipelines.txt three levels above the executable
    // (build/<preset>/bin in a checkout), or config/metal_pipelines.txt under the working directory.
    static std::string find_pipeline_list() {
        if (const char *named = portablekit::env("METAL_PIPELINES"); named != nullptr)
            return *named == '\0' || std::strcmp(named, "0") == 0 ? std::string{} : std::string(named);
        std::vector<std::filesystem::path> candidates;
        if (NSString *resources = NSBundle.mainBundle.resourcePath; resources != nil)
            candidates.emplace_back(std::filesystem::path(resources.UTF8String) / "metal_pipelines.txt");
        if (NSString *executable = NSBundle.mainBundle.executablePath; executable != nil)
            candidates.emplace_back(std::filesystem::path(executable.UTF8String).parent_path() / "../../../config" /
                                    "metal_pipelines.txt");
        candidates.emplace_back(std::filesystem::path("config") / "metal_pipelines.txt");
        for (const std::filesystem::path &candidate : candidates) {
            std::error_code ignored;
            if (std::filesystem::is_regular_file(candidate, ignored)) return candidate.lexically_normal().string();
        }
        return {};
    }

    // The depth-stencil states of the list made now (each a few microseconds), and its render pipelines asked of
    // Metal asynchronously: they compile on Metal's threads while the game boots, and a draw takes each from
    // prewarm_ on first use (render_pipeline()), waiting only for one not done yet.
    void start_prewarm() {
        const std::string path = find_pipeline_list();
        if (path.empty()) return;
        std::ifstream in(path);
        if (!in) {
            std::cout << "[metal] cannot read the pipeline list " << path << "; pipelines are made on first use\n";
            return;
        }
        const auto start = std::chrono::steady_clock::now();
        std::vector<RenderKey> renders;
        std::vector<DepthStencilKey> depths;
        std::uint32_t unread = 0u;
        std::string kind;
        std::map<std::string, unsigned> fields;
        for (std::string line; std::getline(in, line);) {
            if (!parse_key_line(line, kind, fields)) continue;
            RenderKey render;
            DepthStencilKey depth;
            if (kind == "render" && from_fields(fields, render)) renders.push_back(render);
            else if (kind == "depth" && from_fields(fields, depth)) depths.push_back(depth);
            else ++unread;
        }
        for (const DepthStencilKey &key : depths)
            if (depth_states_.find(key) == depth_states_.end()) depth_states_.emplace(key, make_depth_state(key));
        prewarm_ = std::make_shared<Prewarm>();
        prewarm_->started = start;
        {
            std::lock_guard<std::mutex> guard(prewarm_->lock);
            prewarm_->pending.insert(renders.begin(), renders.end());
            prewarm_->asked = static_cast<std::uint32_t>(prewarm_->pending.size());
        }
        for (const RenderKey &key : std::set<RenderKey>(renders.begin(), renders.end())) {
            const std::shared_ptr<Prewarm> shared = prewarm_;
            const RenderKey made = key;
            [device_ newRenderPipelineStateWithDescriptor:pipeline_descriptor(key)
                                        completionHandler:^(id<MTLRenderPipelineState> state, NSError *) {
                                            std::lock_guard<std::mutex> guard(shared->lock);
                                            if (state != nil) shared->ready[made] = state;
                                            else ++shared->failed;
                                            shared->pending.erase(made);
                                            if (shared->pending.empty())
                                                shared->done_ms = std::chrono::duration<double, std::milli>(
                                                                      std::chrono::steady_clock::now() - shared->started)
                                                                      .count();
                                            shared->changed.notify_all();
                                        }];
        }
        prewarm_path_ = path;
        prewarm_depth_states_ = depths.size();
        prewarm_start_ms_ = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        std::cout << "[metal] pre-warm: " << prewarm_->asked << " render pipelines (made asynchronously) and "
                  << depths.size() << " depth-stencil states from " << path << ", " << prewarm_start_ms_
                  << " ms at start" << (unread != 0u ? " (" + std::to_string(unread) + " lines not read)" : "")
                  << "\n";
    }

    // Once every pipeline the pre-warm asked for is made: how long that took.
    void report_prewarm_done() {
        std::lock_guard<std::mutex> guard(prewarm_->lock);
        if (!prewarm_->pending.empty()) return;
        prewarm_reported_ = true;
        std::cout << "[metal] pre-warm done: " << prewarm_->asked - prewarm_->failed << " render pipelines made in "
                  << prewarm_->done_ms << " ms" << (prewarm_->failed != 0u ? ", " + std::to_string(prewarm_->failed) + " failed" : "")
                  << " (frame " << frames_ << ")\n";
    }

    void report_pipelines() {
        std::cout << "[metal] pipelines: " << render_pipelines_.size() << " render pipelines used, "
                  << stats_.pipelines_made << " made by a draw";
        if (prewarm_) {
            std::cout << " (" << prewarm_waits_ << " of them waited for the pre-warm, " << prewarm_missed_
                      << " not in the list), " << prewarm_used_ << " taken from the pre-warm of " << prewarm_->asked;
        }
        std::cout << "; " << depth_states_.size() << " depth-stencil states, " << stats_.depth_states_made
                  << " made by a draw" << (prewarm_ ? ", " + std::to_string(prewarm_depth_states_) + " pre-warmed" : "")
                  << "\n";
    }

    // PURE_METAL_PIPELINES_OUT: every key the run's draws used, as config/metal_pipelines.txt holds them.
    void write_pipeline_list() {
        if (pipelines_out_.empty()) return;
        std::error_code ignored;
        const std::filesystem::path file(pipelines_out_);
        if (file.has_parent_path()) std::filesystem::create_directories(file.parent_path(), ignored);
        std::ofstream out(pipelines_out_);
        if (!out) {
            std::cout << "[metal] cannot write the pipeline list to " << pipelines_out_ << "\n";
            return;
        }
        out << "# The Metal backend's render pipelines and depth-stencil states made at start (task 033,\n"
               "# docs/metal-backend.md \"Frame times\"): written by PURE_METAL_PIPELINES_OUT=FILE, every key a run's\n"
               "# draws used. A key not listed is still made on first use.\n";
        for (const RenderKey &key : render_seen_) out << to_text(key) << "\n";
        for (const DepthStencilKey &key : depth_seen_) out << to_text(key) << "\n";
        std::cout << "[metal] " << render_seen_.size() << " render pipeline keys and " << depth_seen_.size()
                  << " depth-stencil keys -> " << pipelines_out_ << "\n";
    }

    // -----------------------------------------------------------------------------------------------
    // Targets

    Target &target_for(const TargetKey &key) {
        const auto found = targets_.find(key);
        if (found != targets_.end()) return *found->second;
        auto target = std::make_unique<Target>();
        target->key = key;
        MTLTextureDescriptor *descriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:kWidth
                                                              height:kHeight
                                                           mipmapped:NO];
        descriptor.storageMode = MTLStorageModePrivate;
        descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        target->color = [device_ newTextureWithDescriptor:descriptor];
        descriptor.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        descriptor.usage = MTLTextureUsageRenderTarget;
        target->depth = [device_ newTextureWithDescriptor:descriptor];
        if (log_draws_)
            std::cout << "[metal] frame " << frames_ + 1u << " new target 0x" << std::hex << key.address << std::dec
                      << " stride " << key.stride << " format " << key.format << "\n";
        return *targets_.emplace(key, std::move(target)).first->second;
    }

    // The target at `address` drawn into last, of any stride and format.
    Target *latest_target_at(std::uint32_t address) {
        Target *best = nullptr;
        for (auto &[key, target] : targets_)
            if (key.address == address && target->color_defined &&
                (best == nullptr || target->draw_serial > best->draw_serial))
                best = target.get();
        return best;
    }

    void snapshot_guest_words(const GuestMemory &memory, Target &target) {
        const std::uint32_t bytes = target.key.stride * kHeight * target.bytes_per_pixel();
        target.guest_words.clear();
        if (!memory.contains(target.key.address, bytes)) return;
        target.guest_words.reserve(bytes / 256u + 1u);
        for (std::uint32_t offset = 0; offset + 4u <= bytes; offset += 256u)
            target.guest_words.push_back(memory.load32(target.key.address + offset));
    }

    // The target a texture lies in, if it reads it the way it was drawn: the same row length, a direct
    // colour format of the same pixel size, and guest memory under the texture unchanged since the
    // target's first draw of the frame. A target that starts at the texture's address wins over one
    // that only contains it (patch 0003). (x, y) is the texture's first texel in the target.
    Target *find_framebuffer_texture(const GuestMemory &memory, const TextureState &texture, std::uint32_t &x,
                                     std::uint32_t &y) {
        if (no_framebuffer_textures_ || texture.swizzled || static_cast<std::uint32_t>(texture.format) > 3u ||
            texture.width == 0u || texture.height == 0u)
            return nullptr;
        const std::uint32_t texture_address = GuestMemory::canonical(texture.address);
        Target *best = nullptr;
        bool best_exact = false;
        for (auto &[key, target] : targets_) {
            if (!target->color_defined || target->guest_words.empty()) continue;
            const std::uint32_t bytes_per_pixel = target->bytes_per_pixel();
            if (texture_bits(texture.format) != bytes_per_pixel * 8u) continue;
            const std::uint32_t base = key.address;
            const std::uint32_t bytes = key.stride * kHeight * bytes_per_pixel;
            if (texture_address < base || texture_address - base >= bytes) continue;
            if (texture.buffer_width != key.stride || (texture_address - base) % bytes_per_pixel != 0u) continue;
            const bool exact = texture_address == base;
            if (best == nullptr || (exact && !best_exact) ||
                (exact == best_exact && target->draw_serial > best->draw_serial)) {
                best = target.get();
                best_exact = exact;
            }
        }
        if (best == nullptr) return nullptr;
        const std::uint32_t bytes_per_pixel = best->bytes_per_pixel();
        const std::uint64_t texture_end = static_cast<std::uint64_t>(texture_address) +
                                          static_cast<std::uint64_t>(texture.buffer_width) * texture.height *
                                              bytes_per_pixel;
        for (std::size_t i = 0; i < best->guest_words.size(); ++i) {
            const std::uint32_t word_address = best->key.address + static_cast<std::uint32_t>(i) * 256u;
            if (word_address < texture_address || word_address >= texture_end) continue;
            if (!memory.contains(word_address, 4u) || memory.load32(word_address) != best->guest_words[i])
                return nullptr;
        }
        const std::uint32_t pixel = (texture_address - best->key.address) / bytes_per_pixel;
        x = pixel % best->key.stride;
        y = pixel / best->key.stride;
        if (x >= kWidth || y >= kHeight) return nullptr;
        return best;
    }

    // What a draw into `drawn` samples of `source`: the target itself, or, when the draw reads the
    // target it draws into, a copy of it made now (which ends the pass).
    id<MTLTexture> sample_target(Target &source, const Target &drawn) {
        if (&source != &drawn) return source.color;
        if (source.copy == nil) {
            MTLTextureDescriptor *descriptor =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                   width:kWidth
                                                                  height:kHeight
                                                               mipmapped:NO];
            descriptor.storageMode = MTLStorageModePrivate;
            descriptor.usage = MTLTextureUsageShaderRead;
            source.copy = [device_ newTextureWithDescriptor:descriptor];
        }
        if (source.copy_serial != source.draw_serial) {
            ensure_commands();
            end_encoder();
            id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
            [blit copyFromTexture:source.color toTexture:source.copy];
            [blit endEncoding];
            source.copy_serial = source.draw_serial;
            ++stats_.copies;
        }
        return source.copy;
    }

    // -----------------------------------------------------------------------------------------------
    // Textures from guest memory

    // Address, layout, the bytes the texels lie in and the palette entries they can reach.
    static std::uint64_t content_key(const GuestMemory &memory, const TextureState &state) {
        std::uint64_t key = 0xCBF29CE484222325ull;
        key = hash_value(key, state.address);
        key = hash_value(key, static_cast<std::uint64_t>(state.width) << 16u | state.height);
        key = hash_value(key, static_cast<std::uint64_t>(state.format) << 32u | state.buffer_width);
        key = hash_value(key, state.swizzled ? 1u : 0u);
        const std::uint32_t bits = texture_bits(state.format);
        std::size_t bytes = 0u;
        if (bits != 0u) {
            const std::uint32_t stride = state.buffer_width != 0u ? state.buffer_width : state.width;
            bytes = static_cast<std::size_t>(stride) * bits / 8u * state.height;
        } else {
            const std::size_t blocks = static_cast<std::size_t>((state.width + 3u) / 4u) * ((state.height + 3u) / 4u);
            bytes = blocks * (state.format == TextureFormat::Dxt1 ? 8u : 16u);
        }
        key = hash_guest(key, memory, state.address, bytes);
        if (indexed(state.format)) {
            key = hash_value(key, state.clut_address);
            key = hash_value(key, static_cast<std::uint64_t>(state.clut_format) << 48u |
                                      static_cast<std::uint64_t>(state.clut_shift) << 32u |
                                      static_cast<std::uint64_t>(state.clut_mask) << 16u | state.clut_offset);
            // Entry ((index >> shift) & mask) | offset << 4 for the indices the format holds: from
            // offset << 4 to at most that plus the mask (or the largest shifted index).
            const std::uint64_t largest_index = bits >= 32u ? 0xFFFFFFFFull : (1ull << bits) - 1u;
            const std::uint64_t reach = std::min<std::uint64_t>(state.clut_mask, largest_index >> state.clut_shift);
            const std::uint64_t first = static_cast<std::uint64_t>(state.clut_offset) << 4u;
            const std::uint32_t entry_bytes = state.clut_format == 3u ? 4u : 2u;
            key = hash_guest(key, memory, state.clut_address + static_cast<std::uint32_t>(first * entry_bytes),
                             static_cast<std::size_t>((reach + 1u) * entry_bytes));
        }
        return key;
    }

    id<MTLTexture> decoded_texture(const GuestMemory &memory, const TextureState &state) {
        const TraceClock clock(trace_file_ != nullptr, times_.texture);
        const TextureIdentity identity{state.address,
                                       state.buffer_width,
                                       static_cast<std::uint32_t>(state.width) << 16u | state.height,
                                       static_cast<std::uint32_t>(state.format),
                                       state.clut_address,
                                       state.clut_format | state.clut_shift << 4u | state.clut_mask << 12u |
                                           state.clut_offset << 20u,
                                       state.swizzled};
        std::uint64_t key{};
        if (const auto memo = list_keys_.find(identity); memo != list_keys_.end()) {
            key = memo->second;
        } else {
            key = content_key(memory, state);
            list_keys_.emplace(identity, key);
        }
        if (const auto found = textures_.find(key); found != textures_.end()) {
            found->second.last_used = ++texture_clock_;
            return found->second.texture;
        }
        if (!pk::decode_texture(memory, state, pixels_) || pixels_.empty()) {
            not_emulated("texture that cannot be decoded (drawn white), format", static_cast<std::uint32_t>(state.format));
            return white_;
        }
        if (textures_.size() >= kMaxTextures) {
            auto oldest = textures_.begin();
            for (auto it = textures_.begin(); it != textures_.end(); ++it)
                if (it->second.last_used < oldest->second.last_used) oldest = it;
            textures_.erase(oldest);  // a command buffer that uses it keeps it alive
        }
        MTLTextureDescriptor *descriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:state.width
                                                              height:state.height
                                                           mipmapped:NO];
        descriptor.storageMode = MTLStorageModeShared;
        descriptor.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> texture = [device_ newTextureWithDescriptor:descriptor];
        [texture replaceRegion:MTLRegionMake2D(0, 0, state.width, state.height)
                   mipmapLevel:0
                     withBytes:pixels_.data()
                   bytesPerRow:static_cast<NSUInteger>(state.width) * 4u];
        textures_.emplace(key, CachedTexture{texture, ++texture_clock_});
        ++stats_.decoded;
        stats_.decoded_bytes += static_cast<std::uint64_t>(state.width) * state.height * 4u;
        return texture;
    }

    // -----------------------------------------------------------------------------------------------
    // Draws

    // The draw's vertices into vertices_ as a list of the Metal primitive it is drawn as, the first `drawn`
    // of them drawn (a transformed sprite draw's sources follow); false for none. `transform` (projection x
    // view x world) is what a transformed sprite is projected with.
    bool expand(const DrawCall &call, const std::array<float, 16> &transform, MTLPrimitiveType &type,
                std::size_t &drawn) {
        vertices_.clear();
        sprite_corners_ = 0u;
        // A vertex without a colour is drawn with the material colour when the draw is unlit; a lit one
        // takes it from the material registers in the shader (Vulkan's rule).
        const bool use_material_color = !call.has_vertex_color && !call.lighting_enabled;
        const std::size_t total = call.vertices.size();
        const std::size_t count = call.indices.empty() ? total : call.indices.size();
        const auto at = [&](std::size_t i) -> const Vertex & {
            const std::size_t index = call.indices.empty() ? i : call.indices[i];
            return call.vertices[std::min(index, total - 1u)];
        };
        const auto convert = [&](const Vertex &vertex) {
            GpuVertex out;
            out.x = vertex.position[0];
            out.y = vertex.position[1];
            out.z = vertex.position[2];
            out.u = vertex.texcoord[0];
            out.v = vertex.texcoord[1];
            out.color = use_material_color ? call.material_color : vertex.color;
            out.nx = vertex.normal[0];
            out.ny = vertex.normal[1];
            out.nz = vertex.normal[2];
            return out;
        };
        const auto push = [&](const Vertex &vertex) { vertices_.push_back(convert(vertex)); };
        switch (call.primitive) {
        case PrimitiveType::Points:
            type = MTLPrimitiveTypePoint;
            for (std::size_t i = 0; i < count; ++i) push(at(i));
            break;
        case PrimitiveType::Lines:
            type = MTLPrimitiveTypeLine;
            for (std::size_t i = 0; i + 1u < count; i += 2u) {
                push(at(i));
                push(at(i + 1u));
            }
            break;
        case PrimitiveType::LineStrip:
            type = MTLPrimitiveTypeLineStrip;
            if (count < 2u) return false;
            for (std::size_t i = 0; i < count; ++i) push(at(i));
            break;
        case PrimitiveType::Triangles:
            type = MTLPrimitiveTypeTriangle;
            for (std::size_t i = 0; i + 2u < count; i += 3u) {
                push(at(i));
                push(at(i + 1u));
                push(at(i + 2u));
            }
            break;
        case PrimitiveType::TriangleStrip:
            // Every other triangle turned round, so that all keep the strip's winding.
            type = MTLPrimitiveTypeTriangle;
            for (std::size_t i = 0; i + 2u < count; ++i) {
                const bool odd = (i & 1u) != 0u;
                push(at(i));
                push(at(odd ? i + 2u : i + 1u));
                push(at(odd ? i + 1u : i + 2u));
            }
            break;
        case PrimitiveType::TriangleFan:
            type = MTLPrimitiveTypeTriangle;
            for (std::size_t i = 1u; i + 1u < count; ++i) {
                push(at(0));
                push(at(i));
                push(at(i + 1u));
            }
            break;
        case PrimitiveType::Sprites:
            // Pairs of opposite corners. The GE takes the second vertex's depth and colour for the whole
            // rectangle (sceGuClear relies on it: its first vertex has z 0), and each corner the u of the
            // vertex it shares x with and the v of the one it shares y with.
            type = MTLPrimitiveTypeTriangle;
            if (!call.through) {
                expand_transformed_sprites(call, transform, count, at, convert);
                break;
            }
            for (std::size_t i = 0; i + 1u < count; i += 2u) {
                Vertex a = at(i);
                const Vertex &b = at(i + 1u);
                a.position[2] = b.position[2];
                a.color = b.color;
                Vertex top_right = b;
                top_right.position[1] = a.position[1];
                top_right.texcoord[1] = a.texcoord[1];
                Vertex bottom_left = a;
                bottom_left.position[1] = b.position[1];
                bottom_left.texcoord[1] = b.texcoord[1];
                push(a);
                push(top_right);
                push(b);
                push(a);
                push(b);
                push(bottom_left);
            }
            break;
        default:
            return false;
        }
        drawn = sprite_corners_ != 0u ? sprite_corners_ : vertices_.size();
        return drawn != 0u;
    }

    // Transformed sprites, by the GE's rule: both vertices are projected, and the rectangle between them is
    // axis-aligned on the screen, at the second vertex's depth, with its colour, lighting and fog. The
    // corners go to the shader in the PSP's clip space (VertexUniforms kClipPositions), all with the second
    // vertex's w, so that nothing is interpolated in perspective; each names the second vertex, appended
    // after the corners in object space, as the vertex it is lit and fogged as. A sprite with a vertex
    // behind the eye (w <= 0) is dropped.
    template <typename At, typename Convert>
    void expand_transformed_sprites(const DrawCall &call, const std::array<float, 16> &transform, std::size_t count,
                                    const At &at, const Convert &convert) {
        sprite_sources_.clear();
        for (std::size_t i = 0; i + 1u < count; i += 2u) {
            const Vertex &a = at(i);
            const Vertex &b = at(i + 1u);
            const std::array<float, 4> clip_a = transform_point(transform, a.position);
            const std::array<float, 4> clip_b = transform_point(transform, b.position);
            if (!(clip_a[3] > 0.0f) || !(clip_b[3] > 0.0f)) continue;
            const float w = clip_b[3];
            const float x0 = clip_a[0] / clip_a[3] * w;
            const float y0 = clip_a[1] / clip_a[3] * w;
            const auto source = static_cast<std::uint32_t>(sprite_sources_.size());
            const GpuVertex second = convert(b);
            sprite_sources_.push_back(second);
            const auto corner = [&](float x, float y, float u, float v) {
                GpuVertex out = second;
                out.x = x;
                out.y = y;
                out.z = clip_b[2];
                out.w = w;
                out.u = u;
                out.v = v;
                out.source = source;
                return out;
            };
            const GpuVertex top_left = corner(x0, y0, a.texcoord[0], a.texcoord[1]);
            const GpuVertex top_right = corner(clip_b[0], y0, b.texcoord[0], a.texcoord[1]);
            const GpuVertex bottom_right = corner(clip_b[0], clip_b[1], b.texcoord[0], b.texcoord[1]);
            const GpuVertex bottom_left = corner(x0, clip_b[1], a.texcoord[0], b.texcoord[1]);
            vertices_.push_back(top_left);
            vertices_.push_back(top_right);
            vertices_.push_back(bottom_right);
            vertices_.push_back(top_left);
            vertices_.push_back(bottom_right);
            vertices_.push_back(bottom_left);
        }
        sprite_corners_ = vertices_.size();
        if (sprite_corners_ == 0u) return;
        for (GpuVertex &vertex : vertices_) vertex.source += static_cast<std::uint32_t>(sprite_corners_);
        vertices_.insert(vertices_.end(), sprite_sources_.begin(), sprite_sources_.end());
    }

    // The blend: Metal's blend units for the GE's factors and equations. A FIX source factor is applied
    // in the fragment shader (exact for any pair of FIX colours) unless the destination factor reads the
    // source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour.
    void translate_blend(const BlendState &blend, RenderKey &key, FragmentUniforms &fragment,
                         std::uint32_t &blend_color) {
        key.blend = blend.enabled;
        if (!blend.enabled) return;
        std::uint32_t equation = blend.equation;
        if (equation > 4u) {
            not_emulated("blend equation (drawn as ADD)", equation);
            equation = 0u;
        }
        static constexpr MTLBlendOperation kOperations[] = {MTLBlendOperationAdd, MTLBlendOperationSubtract,
                                                            MTLBlendOperationReverseSubtract, MTLBlendOperationMin,
                                                            MTLBlendOperationMax};
        key.operation = static_cast<std::uint8_t>(kOperations[equation]);
        if (equation == 3u || equation == 4u) {  // MIN and MAX take no factors
            key.source = MTLBlendFactorOne;
            key.destination = MTLBlendFactorOne;
            return;
        }
        std::uint32_t source = blend.source_factor;
        std::uint32_t destination = blend.destination_factor;
        if (source >= 6u && source <= 9u) {
            not_emulated("doubled blend source factor (drawn single)", source);
            source -= 4u;
        }
        if (destination >= 6u && destination <= 9u) {
            not_emulated("doubled blend destination factor (drawn single)", destination);
            destination -= 4u;
        }
        const std::uint32_t fix_source = blend.fixed_source & 0x00FFFFFFu;
        const std::uint32_t fix_destination = blend.fixed_destination & 0x00FFFFFFu;
        MTLBlendFactor out_destination = MTLBlendFactorZero;
        switch (destination) {
        case 0u: out_destination = MTLBlendFactorSourceColor; break;  // the other pixel's colour
        case 1u: out_destination = MTLBlendFactorOneMinusSourceColor; break;
        case 2u: out_destination = MTLBlendFactorSourceAlpha; break;
        case 3u: out_destination = MTLBlendFactorOneMinusSourceAlpha; break;
        case 4u: out_destination = MTLBlendFactorDestinationAlpha; break;
        case 5u: out_destination = MTLBlendFactorOneMinusDestinationAlpha; break;
        case 10u:
            if (fix_destination == 0x00FFFFFFu) {
                out_destination = MTLBlendFactorOne;
            } else if (fix_destination == 0u) {
                out_destination = MTLBlendFactorZero;
            } else {
                out_destination = MTLBlendFactorBlendColor;
                blend_color = fix_destination;
            }
            break;
        default: break;
        }
        MTLBlendFactor out_source = MTLBlendFactorOne;
        switch (source) {
        case 0u: out_source = MTLBlendFactorDestinationColor; break;
        case 1u: out_source = MTLBlendFactorOneMinusDestinationColor; break;
        case 2u: out_source = MTLBlendFactorSourceAlpha; break;
        case 3u: out_source = MTLBlendFactorOneMinusSourceAlpha; break;
        case 4u: out_source = MTLBlendFactorDestinationAlpha; break;
        case 5u: out_source = MTLBlendFactorOneMinusDestinationAlpha; break;
        case 10u:
            if (fix_source == 0x00FFFFFFu) {
                out_source = MTLBlendFactorOne;
            } else if (fix_source == 0u) {
                out_source = MTLBlendFactorZero;
            } else if (destination <= 1u) {
                out_source = MTLBlendFactorBlendColor;
                blend_color = fix_source;
            } else {
                fragment.fix = {static_cast<float>(fix_source & 0xFFu) / 255.0f,
                                static_cast<float>((fix_source >> 8u) & 0xFFu) / 255.0f,
                                static_cast<float>((fix_source >> 16u) & 0xFFu) / 255.0f, 1.0f};
                out_source = MTLBlendFactorOne;
            }
            break;
        default: break;
        }
        key.source = static_cast<std::uint8_t>(out_source);
        key.destination = static_cast<std::uint8_t>(out_destination);
    }

    // Whether a blend reads the fragment's alpha (SA or 1-SA on either side, the doubled forms drawn single),
    // so the fragment cannot hand over the stencil value as its alpha without dual-source blending.
    static bool blend_reads_source_alpha(const RenderKey &key, std::uint8_t write_mask) {
        const auto reads = [](std::uint8_t factor) {
            return factor == MTLBlendFactorSourceAlpha || factor == MTLBlendFactorOneMinusSourceAlpha;
        };
        return key.blend && key.operation != MTLBlendOperationMin && key.operation != MTLBlendOperationMax &&
               (write_mask & (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue)) != 0u &&
               (reads(key.source) || reads(key.destination));
    }

    // Whether a blend reads the destination's alpha (DA or 1-DA), which is the PSP's stencil.
    static bool blend_reads_destination_alpha(const RenderKey &key) {
        const auto reads = [](std::uint8_t factor) {
            return factor == MTLBlendFactorDestinationAlpha || factor == MTLBlendFactorOneMinusDestinationAlpha;
        };
        return key.blend && key.operation != MTLBlendOperationMin && key.operation != MTLBlendOperationMax &&
               (key.write_mask & (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue)) != 0u &&
               (reads(key.source) || reads(key.destination));
    }

    // Copies the stencil into the open pass's target alpha, which draws since the last copy left different
    // from it (patch 0006's resolve_stencil_alpha), inside the pass and without reading the stencil in a
    // shader: a quad over the whole target writes alpha 0, then one quad per stencil bit passes the stencil
    // test (EQUAL under a compare mask of that bit) where the bit is set and adds the bit's value to the alpha
    // (ONE + ONE, alpha written alone, stencil write mask 0). Sums of multiples of 1/255 are exact in an 8-bit
    // target.
    void resolve_stencil_alpha(const char *reason) {
        alpha_stale_ = false;
        if (encoder_ == nil || current_target_ == nullptr) return;
        ++stats_.stencil_copies;
        if (trace_stencil_copy_)
            std::cout << "[metal] stencil copied into the alpha of 0x" << std::hex << current_target_->key.address
                      << std::dec << " in frame " << frames_ + 1u << " (" << reason << ")\n";
        std::array<GpuVertex, 6> quad{};
        const float w = static_cast<float>(kWidth);
        const float h = static_cast<float>(kHeight);
        const std::array<std::array<float, 2>, 6> corners{{{0.0f, 0.0f}, {w, 0.0f}, {0.0f, h}, {0.0f, h}, {w, 0.0f}, {w, h}}};
        for (std::size_t i = 0; i < quad.size(); ++i) {
            quad[i].x = corners[i][0];
            quad[i].y = corners[i][1];
            quad[i].color = 0xFFFFFFFFu;
        }
        const auto [buffer, offset] = allocate(sizeof(quad));
        std::memcpy(static_cast<std::uint8_t *>(buffer.contents) + offset, quad.data(), sizeof(quad));
        VertexUniforms vertex{};
        vertex.mode = {1u, 0u, 0u, 0u};  // through mode
        FragmentUniforms fragment{};
        fragment.alpha_test = {1u, 0u, 0xFFu, 0u};
        [encoder_ setVertexBuffer:buffer offset:offset atIndex:0];
        [encoder_ setVertexBytes:&vertex length:sizeof(vertex) atIndex:1];
        if (!lighting_bound_) {
            [encoder_ setVertexBytes:&lighting_ length:sizeof(lighting_) atIndex:2];
            lighting_bound_ = true;
            lighting_changed_ = false;
        }
        [encoder_ setViewport:MTLViewport{0.0, 0.0, static_cast<double>(kWidth), static_cast<double>(kHeight), 0.0, 1.0}];
        [encoder_ setScissorRect:MTLScissorRect{0u, 0u, kWidth, kHeight}];
        [encoder_ setCullMode:MTLCullModeNone];
        RenderKey render;
        render.write_mask = MTLColorWriteMaskAlpha;
        DepthStencilKey depth;
        for (std::uint32_t step = 0; step <= 8u; ++step) {
            const std::uint32_t bit = step == 0u ? 0u : 1u << (step - 1u);
            if (step != 0u) {
                render.blend = true;
                render.alpha_destination = MTLBlendFactorOne;  // add
                depth.stencil = true;
                depth.stencil_function = 2u;  // EQUAL, every operation KEEP
                depth.compare_mask = static_cast<std::uint8_t>(bit);
                depth.write_mask = 0u;
            }
            id<MTLRenderPipelineState> pipeline = render_pipeline(render);
            if (pipeline == nil) break;
            [encoder_ setRenderPipelineState:pipeline];
            [encoder_ setDepthStencilState:depth_state(depth)];
            if (step != 0u) [encoder_ setStencilReferenceValue:bit];
            fragment.stencil = {1u, bit, 0u, 0u};
            [encoder_ setFragmentBytes:&fragment length:sizeof(fragment) atIndex:0];
            [encoder_ drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:quad.size()];
        }
        // The next draw sets its own state again.
        bound_ = Bound{};
    }

    // The lights, the material and the fog of a lit or fogged draw into lighting_ (ge.vert's Environment
    // and Object blocks, filled as vulkan_renderer.cpp fills them). An environment-mapped draw (`shade_mapped`)
    // reads the world matrix, the lights and the reversed normals whether it is lit or not.
    void fill_lighting(const DrawCall &call, bool lit, bool fogged, bool shade_mapped) {
        LightingUniforms block{};
        const pk::LightingState &state = call.lighting;
        if (fogged) block.fog = {call.fog.end, call.fog.scale, 0.0f, 0.0f};
        if (lit || shade_mapped) {
            block.world = call.world;
            block.ambient = unpack_color(state.ambient_color, static_cast<float>(state.ambient_alpha & 0xFFu) / 255.0f);
            block.emissive = unpack_color(state.material_emissive, state.specular_power);
            block.material_ambient =
                unpack_color(call.material_color, static_cast<float>(call.material_color >> 24u) / 255.0f);
            block.material_diffuse = unpack_color(state.material_diffuse);
            block.material_specular = unpack_color(state.material_specular);
            block.flags = {state.material_update & 7u, call.has_vertex_color ? 1u : 0u, (state.mode & 1u) != 0u ? 1u : 0u,
                           state.reverse_normals ? 1u : 0u};
            for (std::size_t i = 0; i < state.lights.size(); ++i) {
                const pk::LightState &light = state.lights[i];
                Light &out = block.lights[i];
                out.position = {light.position[0], light.position[1], light.position[2], 0.0f};
                out.direction = {light.direction[0], light.direction[1], light.direction[2], 0.0f};
                out.attenuation = {light.attenuation[0], light.attenuation[1], light.attenuation[2], 0.0f};
                out.spot = {light.spot_exponent, light.spot_cutoff, 0.0f, 0.0f};
                out.ambient = unpack_color(light.ambient);
                out.diffuse = unpack_color(light.diffuse);
                out.specular = unpack_color(light.specular);
                out.mode = {light.enabled ? 1u : 0u, light.type, light.kind, 0u};
            }
        }
        if (std::memcmp(&block, &lighting_, sizeof(block)) != 0) {
            lighting_ = block;
            lighting_changed_ = true;
        }
    }

    // The descriptor of a render pipeline: what render_pipeline() makes on first use and the pre-warm ahead of it.
    MTLRenderPipelineDescriptor *pipeline_descriptor(const RenderKey &key) {
        MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = vertex_function_;
        descriptor.fragmentFunction = fragment_functions_[(key.textured ? 1u : 0u) | (key.alpha_test ? 2u : 0u) |
                                                          (key.dual_source ? 4u : 0u)];
        // With dual-source blending the colour blend's source alpha is the fragment's own, from the second
        // output, while the first output's alpha is the stencil value the target stores.
        const auto colour_factor = [&](std::uint8_t factor) {
            const auto metal = static_cast<MTLBlendFactor>(factor);
            if (!key.dual_source) return metal;
            if (metal == MTLBlendFactorSourceAlpha) return MTLBlendFactorSource1Alpha;
            if (metal == MTLBlendFactorOneMinusSourceAlpha) return MTLBlendFactorOneMinusSource1Alpha;
            return metal;
        };
        MTLRenderPipelineColorAttachmentDescriptor *colour = descriptor.colorAttachments[0];
        colour.pixelFormat = MTLPixelFormatRGBA8Unorm;
        colour.writeMask = key.write_mask;
        colour.blendingEnabled = key.blend;
        colour.rgbBlendOperation = static_cast<MTLBlendOperation>(key.operation);
        colour.sourceRGBBlendFactor = colour_factor(key.source);
        colour.destinationRGBBlendFactor = colour_factor(key.destination);
        // The alpha is the PSP's stencil: the fragment's value (the stencil value or a clear's alpha) is stored
        // as it is, or added for the copy of the stencil into the alpha.
        colour.alphaBlendOperation = MTLBlendOperationAdd;
        colour.sourceAlphaBlendFactor = MTLBlendFactorOne;
        colour.destinationAlphaBlendFactor = static_cast<MTLBlendFactor>(key.alpha_destination);
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        descriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        return descriptor;
    }

    id<MTLRenderPipelineState> render_pipeline(const RenderKey &key) {
        if (const auto found = render_pipelines_.find(key); found != render_pipelines_.end()) return found->second;
        const TraceClock clock(trace_file_ != nullptr, times_.pipeline);
        render_seen_.insert(key);
        bool waited = false;
        if (prewarm_) {
            // Made at start, or still being made: then this draw waits for it, which is still quicker than
            // compiling it a second time.
            std::unique_lock<std::mutex> lock(prewarm_->lock);
            if (prewarm_->pending.count(key) != 0u) {
                waited = true;
                ++prewarm_waits_;
                prewarm_->changed.wait(lock, [&] { return prewarm_->pending.count(key) == 0u; });
            }
            if (const auto ready = prewarm_->ready.find(key); ready != prewarm_->ready.end()) {
                id<MTLRenderPipelineState> state = ready->second;
                prewarm_->ready.erase(ready);
                lock.unlock();
                // A draw that had to wait for the pre-warm counts as one that made its pipeline.
                if (waited) ++stats_.pipelines_made;
                ++prewarm_used_;
                render_pipelines_.emplace(key, state);
                return state;
            }
        }
        NSError *failure = nil;
        id<MTLRenderPipelineState> state = [device_ newRenderPipelineStateWithDescriptor:pipeline_descriptor(key)
                                                                                    error:&failure];
        if (state == nil)
            std::cout << "[metal] cannot make a pipeline: "
                      << (failure != nil ? failure.localizedDescription.UTF8String : "no message") << "\n";
        ++stats_.pipelines_made;
        if (prewarm_) ++prewarm_missed_;
        if (log_draws_) std::cout << "[metal] frame " << frames_ + 1u << " new pipeline " << to_text(key) << "\n";
        render_pipelines_.emplace(key, state);
        return state;
    }

    // A depth-stencil state, made on first use unless the pre-warm made it at start.
    id<MTLDepthStencilState> depth_state(const DepthStencilKey &key) {
        if (const auto found = depth_states_.find(key); found != depth_states_.end()) {
            if (!pipelines_out_.empty()) depth_seen_.insert(key);
            return found->second;
        }
        const TraceClock clock(trace_file_ != nullptr, times_.pipeline);
        depth_seen_.insert(key);
        ++stats_.depth_states_made;
        if (log_draws_) std::cout << "[metal] frame " << frames_ + 1u << " new depth state " << to_text(key) << "\n";
        id<MTLDepthStencilState> state = make_depth_state(key);
        depth_states_.emplace(key, state);
        return state;
    }

    id<MTLDepthStencilState> make_depth_state(const DepthStencilKey &key) {
        MTLDepthStencilDescriptor *descriptor = [MTLDepthStencilDescriptor new];
        descriptor.depthCompareFunction = static_cast<MTLCompareFunction>(key.compare);
        descriptor.depthWriteEnabled = key.write;
        if (key.stencil) {
            // The GE compares the reference with the stored stencil (reference OP stencil, both under the
            // compare mask) as Metal does, with the alpha test's function numbers; both faces alike.
            MTLStencilDescriptor *stencil = [MTLStencilDescriptor new];
            stencil.stencilCompareFunction = to_compare(key.stencil_function);
            stencil.stencilFailureOperation = to_stencil_operation(key.fail);
            stencil.depthFailureOperation = to_stencil_operation(key.depth_fail);
            stencil.depthStencilPassOperation = to_stencil_operation(key.pass);
            stencil.readMask = key.compare_mask;
            stencil.writeMask = key.write_mask;
            descriptor.frontFaceStencil = stencil;
            descriptor.backFaceStencil = stencil;
        }
        return [device_ newDepthStencilStateWithDescriptor:descriptor];
    }

    // The texture mapping mode of a textured, transformed draw (task 036): the texture matrix (1) or the
    // environment map (2) computed in ge_vertex, or the UVs (0) as before. `source` is the target sampled as the
    // texture, if any: the mapped coordinates are placed in it as uv_transform places the UVs.
    void set_texture_map(const DrawCall &call, const Target *source, std::uint32_t source_x, std::uint32_t source_y,
                         VertexUniforms &vertex, FragmentUniforms &fragment) {
        const pk::TextureMapState &map = call.texture_map;
        if (call.through || no_texture_map_ || map.map_mode == 0u) return;
        if (map.map_mode == 3u) {
            not_emulated("texture map mode 3 (drawn with its UVs)", map.map_mode);
            return;
        }
        if (sprite_corners_ != 0u) {
            // The corners of a transformed sprite are made in clip space on the CPU; none of the game's is mapped.
            not_emulated("texture map mode on a transformed sprite (drawn with its UVs)", map.map_mode);
            return;
        }
        vertex.texture_map = {map.map_mode, map.proj_source, map.shade_light_u, map.shade_light_v};
        if (map.map_mode == 1u) {
            vertex.texture_matrix = call.texture_matrix;
            fragment.texture[3] = 1u;  // s and t divided by q per pixel
        } else {
            // The viewer at infinity along view-space +z, in world space: the view matrix's third column (the
            // GE's matrices are rows of a row-vector transform, stored here as columns).
            std::array<float, 3> viewer{call.view[2], call.view[6], call.view[10]};
            const float length = std::sqrt(viewer[0] * viewer[0] + viewer[1] * viewer[1] + viewer[2] * viewer[2]);
            if (length > 0.0f)
                for (float &value : viewer) value /= length;
            vertex.viewer = {viewer[0], viewer[1], viewer[2], 0.0f};
        }
        if (source != nullptr) {
            const float width = static_cast<float>(call.texture.width);
            const float height = static_cast<float>(call.texture.height);
            vertex.uv_remap = {width / static_cast<float>(kWidth), height / static_cast<float>(kHeight),
                               static_cast<float>(source_x) / static_cast<float>(kWidth),
                               static_cast<float>(source_y) / static_cast<float>(kHeight)};
        }
        ++stats_.texture_mapped;
    }

    void draw(const DrawCall &call, const GuestMemory &memory) {
        // Transformed draws reach the backend decoded (gpu_decode() is false).
        if (call.vertices.empty()) return;
        const std::array<float, 16> view_world = multiply(call.view, call.world);
        const std::array<float, 16> transform = multiply(call.projection, view_world);
        MTLPrimitiveType type{};
        std::size_t drawn = 0u;
        if (!expand(call, transform, type, drawn)) return;

        // The scissor, both ends included; an empty one draws nothing.
        const ViewportScissor scissor = scissor_of(call);
        if (scissor.width == 0u || scissor.height == 0u) return;

        Target &target = target_for(
            {GuestMemory::canonical(call.target.color_address), call.target.color_stride, call.target.color_format});

        PipelineKey key;
        FragmentUniforms fragment{};
        VertexUniforms vertex{};
        std::uint32_t blend_color = 0u;
        const bool textured = call.texture.enabled && !call.clear_mode;
        id<MTLTexture> texture = white_;
        std::uint32_t sampler = 0u;
        Target *source = nullptr;
        std::uint32_t source_x = 0u, source_y = 0u;
        const TextureState &state = call.texture;

        // Texture coordinates: texels in through mode, the GE's scale and offset otherwise.
        vertex.uv_transform = call.through && state.width != 0u && state.height != 0u
                                  ? std::array<float, 4>{1.0f / static_cast<float>(state.width),
                                                         1.0f / static_cast<float>(state.height), 0.0f, 0.0f}
                                  : std::array<float, 4>{state.scale_u, state.scale_v, state.offset_u, state.offset_v};
        if (textured) {
            const bool linear_mag = !sharp_ && (state.mag_filter & 1u) != 0u;
            const bool linear_min = !sharp_ && (state.min_filter & 1u) != 0u;
            source = find_framebuffer_texture(memory, state, source_x, source_y);
            if (source != nullptr) {
                // The texture's first texel is pixel (x, y) of a 480x272 target; the sampler clamps at
                // the target's edges.
                texture = sample_target(*source, target);
                sampler = (linear_mag ? 1u : 0u) | (linear_min ? 2u : 0u) | 4u | 8u;
                const float width = static_cast<float>(state.width);
                const float height = static_cast<float>(state.height);
                const std::array<float, 4> uv = vertex.uv_transform;
                vertex.uv_transform = {uv[0] * width / static_cast<float>(kWidth),
                                       uv[1] * height / static_cast<float>(kHeight),
                                       (uv[2] * width + static_cast<float>(source_x)) / static_cast<float>(kWidth),
                                       (uv[3] * height + static_cast<float>(source_y)) / static_cast<float>(kHeight)};
                ++stats_.framebuffer_textures;
            } else {
                texture = decoded_texture(memory, state);
                sampler = (linear_mag ? 1u : 0u) | (linear_min ? 2u : 0u) | (state.wrap_s != 0u ? 4u : 0u) |
                          (state.wrap_t != 0u ? 8u : 0u);
            }
            fragment.texture = {state.function, state.alpha_from_texture ? 1u : 0u,
                                source != nullptr && state.format == TextureFormat::Rgba5650 ? 1u : 0u, 0u};
            set_texture_map(call, source, source_x, source_y, vertex, fragment);
        }

        // Pipeline state. The target's alpha is the PSP's stencil (patches 0004 and 0006): the stencil
        // attachment does the GE's test and operations, and the alpha is kept equal to it, written by the
        // fragment where the zpass operation is REPLACE or ZERO and copied from the attachment where the draw
        // leaves it behind (`follows`).
        key.render.textured = textured;
        std::uint32_t stencil_reference = 0u;
        bool follows = true;
        if (call.clear_mode) {
            // CLEARMODE: no blend, texture or tests; bits 8..10 say what it writes. A clear of the alpha writes
            // the stencil too: ALWAYS, REPLACE with the clear colour's alpha.
            std::uint8_t mask = MTLColorWriteMaskNone;
            if ((call.clear_flags & 1u) != 0u) mask |= MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue;
            if ((call.clear_flags & 2u) != 0u) mask |= MTLColorWriteMaskAlpha;
            key.render.write_mask = mask;
            key.depth.compare = MTLCompareFunctionAlways;
            key.depth.write = (call.clear_flags & 4u) != 0u;
            if ((call.clear_flags & 2u) != 0u && call.target.color_format != 0u) {
                const std::uint32_t color =
                    !call.has_vertex_color && !call.lighting_enabled ? call.material_color : call.vertices.back().color;
                key.depth.stencil = true;
                key.depth.stencil_function = 1u;  // ALWAYS
                key.depth.fail = key.depth.depth_fail = key.depth.pass = 2u;  // REPLACE
                key.depth.compare_mask = 0xFFu;
                key.depth.write_mask = 0xFFu;
                stencil_reference = color >> 24u;
            }
        } else {
            translate_blend(call.blend, key.render, fragment, blend_color);
            // Whole colour channels the write mask keeps are not written; the alpha, the PSP's stencil, only
            // by the stencil operations.
            std::uint8_t mask = MTLColorWriteMaskNone;
            static constexpr MTLColorWriteMask kChannels[] = {MTLColorWriteMaskRed, MTLColorWriteMaskGreen,
                                                              MTLColorWriteMaskBlue};
            for (std::uint32_t channel = 0; channel < 3u; ++channel) {
                const std::uint32_t bits = (call.color_write_mask >> (8u * channel)) & 0xFFu;
                if (bits != 0xFFu) mask |= kChannels[channel];
                if (bits != 0u && bits != 0xFFu) not_emulated("partial colour write mask", call.color_write_mask);
            }
            const int stored = stencil_alpha(call);
            if (stored >= 0) {
                mask |= MTLColorWriteMaskAlpha;
                fragment.stencil = {1u, static_cast<std::uint32_t>(stored), 0u, 0u};
                // A colour blend that reads the source alpha reads the fragment's own from the second output.
                key.render.dual_source = blend_reads_source_alpha(key.render, mask);
            }
            key.render.write_mask = mask;
            key.render.alpha_test = call.alpha_test.enabled && call.alpha_test.function != 1u;
            fragment.alpha_test = {call.alpha_test.function, call.alpha_test.reference & 0xFFu,
                                   call.alpha_test.mask & 0xFFu, 0u};
            // The GE writes depth only where it tests it.
            key.depth.compare = static_cast<std::uint8_t>(call.depth.test_enabled ? to_compare(call.depth.function)
                                                                                  : MTLCompareFunctionAlways);
            key.depth.write = call.depth.test_enabled && call.depth.write_enabled;
            key.depth.stencil = call.stencil.enabled && call.target.color_format != 0u;
            if (key.depth.stencil) {
                key.depth.stencil_function = static_cast<std::uint8_t>(call.stencil.function & 7u);
                key.depth.fail = static_cast<std::uint8_t>(call.stencil.fail_op & 7u);
                key.depth.depth_fail = static_cast<std::uint8_t>(call.stencil.depth_fail_op & 7u);
                key.depth.pass = static_cast<std::uint8_t>(call.stencil.pass_op & 7u);
                key.depth.compare_mask = static_cast<std::uint8_t>(call.stencil.mask);
                key.depth.write_mask = static_cast<std::uint8_t>(~call.alpha_write_mask);
                stencil_reference = stored_reference(call);
                follows = alpha_follows_stencil(call, key.depth.compare != MTLCompareFunctionAlways);
            }
        }
        id<MTLRenderPipelineState> pipeline = render_pipeline(key.render);
        if (pipeline == nil) return;
        id<MTLDepthStencilState> depth = depth_state(key.depth);

        // Lighting and fog, as ge.vert and ge.frag: transformed draws only, never a clear.
        const bool lit = call.lighting_enabled && !no_lighting_ && !call.through && !call.clear_mode;
        const bool fogged = call.fog.enabled && !no_fog_ && !call.through && !call.clear_mode;
        const bool shade_mapped = vertex.texture_map[0] == 2u;
        if (lit || fogged || shade_mapped) fill_lighting(call, lit, fogged, shade_mapped);
        if (fogged) {
            fragment.fog = unpack_color(call.fog.color, 1.0f);
            vertex.view_z = {view_world[2], view_world[6], view_world[10], view_world[14]};
        }

        // Positions: screen pixels in through mode; the GE viewport folded into clip space otherwise.
        MTLViewport viewport{0.0, 0.0, static_cast<double>(kWidth), static_cast<double>(kHeight), 0.0, 1.0};
        vertex.mode = {call.through ? 1u : 0u, sprite_corners_ != 0u ? kClipPositions : 0u,
                       (fogged ? kFog : 0u) | (lit ? kLighting : 0u), 0u};
        if (!call.through) {
            vertex.transform = transform;
            const pk::ViewportState &vp = call.viewport;
            if (vp.x_scale != 0.0f && vp.y_scale != 0.0f) {
                // screen = ndc * scale + offset - region offset, then to Metal's y-up device space.
                vertex.screen = {2.0f * vp.x_scale / static_cast<float>(kWidth),
                                 2.0f * (vp.x_offset - vp.offset_x) / static_cast<float>(kWidth) - 1.0f,
                                 -2.0f * vp.y_scale / static_cast<float>(kHeight),
                                 1.0f - 2.0f * (vp.y_offset - vp.offset_y) / static_cast<float>(kHeight)};
            } else {
                vertex.screen = {1.0f, 0.0f, -1.0f, 0.0f};
            }
            if (vp.z_scale != 0.0f) {
                // The shader hands over z in [0, w] for the PSP's [-w, w]; this applies the GE's z scale
                // and offset, reversed when the game set a reversed range.
                viewport.znear = std::clamp((vp.z_offset - vp.z_scale) / 65535.0, 0.0, 1.0);
                viewport.zfar = std::clamp((vp.z_offset + vp.z_scale) / 65535.0, 0.0, 1.0);
            }
        }
        const bool cull = call.culling_enabled && !no_cull_ && !call.through && type == MTLPrimitiveTypeTriangle &&
                          call.primitive != PrimitiveType::Sprites && !call.clear_mode;

        // Into the target's pass (after the texture, whose copy may have ended it).
        begin_pass(target);
        // A blend that reads the destination's alpha reads the PSP's stencil.
        if (alpha_stale_ && blend_reads_destination_alpha(key.render)) resolve_stencil_alpha("destination alpha read");
        if (!follows) alpha_stale_ = true;
        if (key.depth.stencil) ++stats_.stencil_draws;
        if (target.guest_words.empty() || target.last_drawn_frame != frames_) snapshot_guest_words(memory, target);
        target.last_drawn_frame = frames_;
        target.draw_serial = ++draw_counter_;

        const std::size_t bytes = vertices_.size() * sizeof(GpuVertex);
        const auto [buffer, offset] = allocate(bytes);
        std::memcpy(static_cast<std::uint8_t *>(buffer.contents) + offset, vertices_.data(), bytes);

        if (bound_.pipeline != pipeline) {
            [encoder_ setRenderPipelineState:pipeline];
            bound_.pipeline = pipeline;
        }
        if (bound_.depth != depth) {
            [encoder_ setDepthStencilState:depth];
            bound_.depth = depth;
        }
        if (key.depth.stencil && (!bound_.stencil_reference_set || bound_.stencil_reference != stencil_reference)) {
            [encoder_ setStencilReferenceValue:stencil_reference];
            bound_.stencil_reference = stencil_reference;
            bound_.stencil_reference_set = true;
        }
        if (!bound_.viewport_set || bound_.viewport.znear != viewport.znear || bound_.viewport.zfar != viewport.zfar) {
            [encoder_ setViewport:viewport];
            bound_.viewport = viewport;
            bound_.viewport_set = true;
        }
        const MTLScissorRect rect{scissor.x, scissor.y, scissor.width, scissor.height};
        if (!bound_.scissor_set || bound_.scissor.x != rect.x || bound_.scissor.y != rect.y ||
            bound_.scissor.width != rect.width || bound_.scissor.height != rect.height) {
            [encoder_ setScissorRect:rect];
            bound_.scissor = rect;
            bound_.scissor_set = true;
        }
        const MTLCullMode cull_mode = cull ? MTLCullModeBack : MTLCullModeNone;
        if (!bound_.cull_set || bound_.cull != cull_mode || bound_.clockwise != call.cull_clockwise) {
            [encoder_ setCullMode:cull_mode];
            // Metal counts the winding in window coordinates (y down), where the GE and the Vulkan
            // backend's flipping viewport count it too: confirmed on the race (task 024), whose first
            // 393 draws of frame 6016 match Vulkan's while the reversed winding differs from draw 41 on.
            [encoder_ setFrontFacingWinding:call.cull_clockwise ? MTLWindingClockwise : MTLWindingCounterClockwise];
            bound_.cull = cull_mode;
            bound_.clockwise = call.cull_clockwise;
            bound_.cull_set = true;
        }
        if (key.render.blend && (!bound_.blend_color_set || bound_.blend_color != blend_color)) {
            [encoder_ setBlendColorRed:static_cast<float>(blend_color & 0xFFu) / 255.0f
                                 green:static_cast<float>((blend_color >> 8u) & 0xFFu) / 255.0f
                                  blue:static_cast<float>((blend_color >> 16u) & 0xFFu) / 255.0f
                                 alpha:1.0f];
            bound_.blend_color = blend_color;
            bound_.blend_color_set = true;
        }
        if (bound_.buffer != buffer) {
            [encoder_ setVertexBuffer:buffer offset:offset atIndex:0];
            bound_.buffer = buffer;
        } else {
            [encoder_ setVertexBufferOffset:offset atIndex:0];
        }
        [encoder_ setVertexBytes:&vertex length:sizeof(vertex) atIndex:1];
        // The lighting block: a lit, fogged or environment-mapped draw's whenever it changed, and something
        // always, since the vertex function names it.
        if (!lighting_bound_ || ((lit || fogged || shade_mapped) && lighting_changed_)) {
            [encoder_ setVertexBytes:&lighting_ length:sizeof(lighting_) atIndex:2];
            lighting_bound_ = true;
            lighting_changed_ = false;
        }
        [encoder_ setFragmentBytes:&fragment length:sizeof(fragment) atIndex:0];
        if (bound_.texture != texture) {
            [encoder_ setFragmentTexture:texture atIndex:0];
            bound_.texture = texture;
        }
        if (!bound_.sampler_set || bound_.sampler != sampler) {
            [encoder_ setFragmentSamplerState:samplers_[sampler] atIndex:0];
            bound_.sampler = sampler;
            bound_.sampler_set = true;
        }
        [encoder_ drawPrimitives:type vertexStart:0 vertexCount:drawn];

        if (log_draws_) log_draw(call, target, source, source_x, source_y, scissor);
        ++stats_.draws;
        ++frame_draws_;
    }

    struct ViewportScissor {
        NSUInteger x{}, y{}, width{}, height{};
    };

    static ViewportScissor scissor_of(const DrawCall &call) {
        const std::uint32_t x1 = call.viewport.scissor_x1;
        const std::uint32_t y1 = call.viewport.scissor_y1;
        const std::uint32_t x2 = std::min(call.viewport.scissor_x2, kWidth - 1u);
        const std::uint32_t y2 = std::min(call.viewport.scissor_y2, kHeight - 1u);
        if (x1 > x2 || y1 > y2) return {};
        return {x1, y1, x2 - x1 + 1u, y2 - y1 + 1u};
    }

    void log_draw(const DrawCall &call, const Target &target, const Target *source, std::uint32_t x, std::uint32_t y,
                  const ViewportScissor &scissor) {
        static const char *const kPrimitives[] = {"points", "lines", "linestrip", "triangles",
                                                  "tristrip", "trifan", "sprites"};
        const auto primitive = static_cast<std::size_t>(call.primitive);
        // Numbered as the [render] frame lines number frames: the frame these draws are presented as.
        std::cout << "[metal] frame " << frames_ + 1u << " draw " << frame_draws_ << " "
                  << (primitive < std::size(kPrimitives) ? kPrimitives[primitive] : "?") << " x"
                  << call.vertices.size() << (call.indices.empty() ? "" : " indexed")
                  << (call.through ? " through" : " transformed") << " target 0x" << std::hex << target.key.address
                  << std::dec << "/" << target.key.stride << "/" << target.key.format;
        if (call.clear_mode) {
            std::cout << " clear " << call.clear_flags;
        } else {
            if (call.texture.enabled) {
                std::cout << " tex 0x" << std::hex << call.texture.address << std::dec << " "
                          << format_name(call.texture.format) << " " << call.texture.width << "x"
                          << call.texture.height << " tfx " << call.texture.function
                          << (call.texture.alpha_from_texture ? "/rgba" : "/rgb");
                if (source != nullptr)
                    std::cout << " from target 0x" << std::hex << source->key.address << std::dec << " at " << x
                              << "," << y;
                if (!call.through && call.texture_map.map_mode == 1u)
                    std::cout << " texmatrix " << call.texture_map.proj_source;
                else if (!call.through && call.texture_map.map_mode == 2u)
                    std::cout << " envmap " << call.texture_map.shade_light_u << "," << call.texture_map.shade_light_v;
            }
            if (call.blend.enabled)
                std::cout << " blend " << call.blend.source_factor << "/" << call.blend.destination_factor << " eq "
                          << call.blend.equation << " fix " << std::hex << call.blend.fixed_source << "/"
                          << call.blend.fixed_destination << std::dec;
            else
                std::cout << " opaque";
            if (call.alpha_test.enabled)
                std::cout << " at " << call.alpha_test.function << " ref " << call.alpha_test.reference;
            if (call.depth.test_enabled) std::cout << " z " << call.depth.function << (call.depth.write_enabled ? " w" : "");
            if (call.stencil.enabled) std::cout << " stencil " << call.stencil.function;
            if (call.color_write_mask != 0u) std::cout << " cmask " << std::hex << call.color_write_mask << std::dec;
            if (!call.through && call.lighting_enabled) std::cout << " lit";
            if (!call.through && call.fog.enabled) std::cout << " fog";
            if (!call.through && call.culling_enabled && call.primitive != PrimitiveType::Sprites)
                std::cout << (call.cull_clockwise ? " cull cw" : " cull ccw");
        }
        std::cout << " scissor " << scissor.x << "," << scissor.y << "+" << scissor.width << "x" << scissor.height
                  << "\n";
    }

    // -----------------------------------------------------------------------------------------------
    // CPU pictures

    void upload(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height,
                std::uint32_t stride) {
        const std::uint32_t address = GuestMemory::canonical(display_address);
        Target *target = latest_target_at(address);
        if (target == nullptr) target = &target_for({address, stride, 3u});
        const std::uint32_t copied_width = std::min(width, kWidth);
        const std::uint32_t copied_height = std::min(height, kHeight);
        if (copied_width != kWidth || copied_height != kHeight)
            not_emulated("CPU picture not 480x272 (copied to the top left, unscaled), width", width);
        // A target never drawn starts cleared where the picture does not cover it.
        if (!target->color_defined) begin_pass(*target);
        const std::size_t bytes = static_cast<std::size_t>(copied_width) * copied_height * 4u;
        const auto [buffer, offset] = allocate(bytes);
        auto *staging = static_cast<std::uint8_t *>(buffer.contents) + offset;
        for (std::uint32_t row = 0; row < copied_height; ++row)
            std::memcpy(staging + static_cast<std::size_t>(row) * copied_width * 4u,
                        pixels + static_cast<std::size_t>(row) * stride * 4u,
                        static_cast<std::size_t>(copied_width) * 4u);
        end_encoder();
        id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
        [blit copyFromBuffer:buffer
                   sourceOffset:offset
              sourceBytesPerRow:copied_width * 4u
            sourceBytesPerImage:bytes
                     sourceSize:MTLSizeMake(copied_width, copied_height, 1)
                      toTexture:target->color
               destinationSlice:0
               destinationLevel:0
              destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
        target->color_defined = true;
        // The picture came from guest memory, which texturing reads correctly anyway.
        target->draw_serial = ++draw_counter_;
        target->guest_words.clear();
        last_drawn_ = target;
        ++stats_.uploads;
    }

    // What the open encoder has bound, so that unchanged state is not set again.
    struct Bound {
        id<MTLRenderPipelineState> pipeline;
        id<MTLDepthStencilState> depth;
        id<MTLTexture> texture;
        id<MTLBuffer> buffer;
        std::uint32_t sampler{};
        bool sampler_set{};
        MTLViewport viewport{};
        bool viewport_set{};
        MTLScissorRect scissor{};
        bool scissor_set{};
        MTLCullMode cull{MTLCullModeNone};
        bool clockwise{};
        bool cull_set{};
        std::uint32_t blend_color{};
        bool blend_color_set{};
        std::uint32_t stencil_reference{};
        bool stencil_reference_set{};
    };

    bool ready_{};
    id<MTLDevice> device_;
    id<MTLCommandQueue> queue_;
    id<MTLLibrary> library_;
    id<MTLFunction> vertex_function_;
    std::array<id<MTLFunction>, 8> fragment_functions_{};  // by kTextured | kAlphaTest << 1 | dual source << 2
    std::array<id<MTLSamplerState>, 16> samplers_{};
    id<MTLTexture> white_;
    id<MTLBuffer> readback_;          // the presented picture, read back (picture_)
    id<MTLBuffer> frame_writeback_;   // the presented picture, copied at the flip for write_back_frame()
    id<MTLBuffer> guest_readback_;    // a target's colour or depth for guest memory
    std::map<RenderKey, id<MTLRenderPipelineState>> render_pipelines_;
    std::map<DepthStencilKey, id<MTLDepthStencilState>> depth_states_;

    id<MTLCommandBuffer> commands_;
    NSMutableArray<id<MTLBuffer>> *frame_buffers_;
    id<MTLRenderCommandEncoder> encoder_;
    std::deque<id<MTLCommandBuffer>> in_flight_;
    std::shared_ptr<ChunkPool> pool_;
    id<MTLBuffer> chunk_;
    std::size_t chunk_used_{};
    Bound bound_;

    std::map<TargetKey, std::unique_ptr<Target>> targets_;
    Target *current_target_{};  // of the open encoder
    Target *last_drawn_{};
    Target *presented_{};
    std::uint64_t draw_counter_{};
    // A draw in the open pass left the target's alpha different from its stencil: resolve_stencil_alpha()
    // copies the stencil over it before a draw reads the destination's alpha and before the pass ends.
    bool alpha_stale_{};

    std::unordered_map<std::uint64_t, CachedTexture> textures_;
    std::map<TextureIdentity, std::uint64_t> list_keys_;  // this display list's binds, hashed once
    std::uint64_t texture_clock_{};
    std::vector<std::uint32_t> pixels_;
    std::vector<GpuVertex> vertices_;
    std::vector<GpuVertex> sprite_sources_;
    std::size_t sprite_corners_{};  // of a transformed sprite draw: vertices_ holds its sources after them
    LightingUniforms lighting_{};   // the last lit or fogged draw's, bound at buffer 2
    bool lighting_changed_{};       // since it was last bound
    bool lighting_bound_{};         // in the open encoder

    std::vector<std::uint8_t> picture_;  // the last picture read back
    std::uint64_t picture_frame_{~0ull};
    // The picture the next write_back_frame() stores: the target shown at the last flip, with its pixels in
    // picture_ (read back for the Vulkan shell) or in frame_writeback_ once `commands` has run.
    struct PendingFrame {
        Target *target{};
        id<MTLCommandBuffer> commands;
        bool from_picture{};
    };
    PendingFrame pending_frame_;
    double last_wait_ms_{};  // of the last commit(true)
    portablekit::gpu::VulkanRenderer *shell_{};
    std::vector<std::uint8_t> shell_scratch_;
    bool to_shell_{};
    bool sharp_{};
    bool log_draws_{};
    bool no_framebuffer_textures_{};
    bool no_lighting_{};
    bool no_fog_{};
    bool no_cull_{};
    bool no_texture_map_{};
    bool trace_stencil_copy_{};
    bool trace_depth_{};
    bool depth_announced_{};

    // PURE_METAL_TRACE (task 033): the interval's times, the counts at the last flip, the rows not written yet.
    FrameTimes times_;
    Stats trace_stats_;
    std::FILE *trace_file_{};
    std::string trace_path_;
    std::deque<TraceRow> pending_rows_;
    std::uint64_t trace_rows_{};
    std::uint64_t trace_shown_{};      // rows whose picture reached the screen
    std::uint64_t trace_not_shown_{};  // rows whose picture the shell says never did
    std::chrono::steady_clock::time_point trace_last_flip_{};
    bool trace_has_flip_{};
    bool shell_seen_{};           // a Metal shell reports its presents
    double last_presented_s_{};   // when the last picture shown reached the screen
    // The keys the draws used (PURE_METAL_PIPELINES_OUT) and the pre-warm.
    std::string pipelines_out_;
    std::set<RenderKey> render_seen_;
    std::set<DepthStencilKey> depth_seen_;
    std::shared_ptr<Prewarm> prewarm_;
    std::string prewarm_path_;
    std::size_t prewarm_depth_states_{};
    double prewarm_start_ms_{};
    bool prewarm_reported_{};
    std::uint64_t prewarm_used_{};
    std::uint64_t prewarm_waits_{};
    std::uint64_t prewarm_missed_{};

    std::uint64_t frames_{};
    std::uint64_t frame_draws_{};
    Stats stats_;
    std::chrono::steady_clock::time_point started_{};
    std::chrono::steady_clock::time_point report_start_{};
    std::uint64_t report_frames_{};
    std::uint64_t report_draws_{};
};

const pk::BackendRegistration registration("metal",
                                           "native Metal (tasks 023-025: targets, textures, 2D and 3D draws, the "
                                           "stencil, read-backs and write-backs)",
                                           [] { return std::unique_ptr<pk::GeBackend>(new MetalGeBackend()); });

} // namespace
} // namespace pure::gpu
