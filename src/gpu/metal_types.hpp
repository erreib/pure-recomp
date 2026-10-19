// The Metal GE backend's shared types (docs/metal-backend.md, "Files"): the sizes of its targets and buffers, the
// vertex and the uniform blocks the shaders read (laid out as their twins in shaders/ge.metal, whose sizes the
// static_asserts check), the keys of targets, pipelines and textures, a target, the counts, and the frame trace's
// clock and rows. Objective-C++ only: the backend's .mm files include it through metal_backend.hpp.
#pragma once

#include "gpu/ge_backend.hpp"
#include "gpu/ge_state.hpp"

#import <Metal/Metal.h>

#include <array>
#include <chrono>
#include <compare>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace pure::gpu::metal_backend {

namespace pk = portablekit::gpu;
using pk::BlendState;
using pk::DrawCall;
using pk::GuestMemory;
using pk::PrimitiveType;
using pk::TextureFormat;
using pk::TextureState;
using pk::Vertex;

// The guest's screen, 480x272: what the GE's coordinates and guest memory are in. A target is drawn at an internal
// scale of it (Target::scale, D-015).
constexpr std::uint32_t kWidth = pk::kScreenWidth;
constexpr std::uint32_t kHeight = pk::kScreenHeight;
constexpr std::size_t kPictureBytes = static_cast<std::size_t>(kWidth) * kHeight * 4u;
// The highest internal scale (D-015): 2880x1632 targets. The settings allow 8; 7 and 8 are drawn at this.
constexpr std::uint32_t kMaxScale = 6u;
// Vertex and upload space comes in chunks of this size, reused once the GPU has finished with them.
constexpr std::size_t kChunkBytes = 4u << 20u;
constexpr std::size_t kMaxTextures = 1024u;
// Frames the GPU may still be drawing while the next one is recorded.
constexpr std::size_t kFramesInFlight = 2u;
constexpr std::uint64_t kReportEvery = 600u;

// The vertex as the shaders read it (GeVertex in shaders/ge.metal).
struct GpuVertex {
    float x{}, y{}, z{}, w{1.0f};
    float u{}, v{};
    std::uint32_t color{};
    std::uint32_t source{};  // a transformed sprite's corner: the vertex it is lit and fogged as
    float nx{}, ny{}, nz{}, nw{};
};
static_assert(sizeof(GpuVertex) == 48u, "GpuVertex must match GeVertex in shaders/ge.metal");

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
    std::array<float, 4> depth{};  // the depth clamp (task 040): the GE's z scale and offset, MINZ, MAXZ
    // The interface's fit under Fill (task 086): x and y scale the position's clip x and y about the screen's centre
    // when z is 1 (a 2D draw into a target of another shape than the PSP's, metal_draw.mm); z 0 leaves it alone.
    std::array<float, 4> fit{1.0f, 1.0f, 0.0f, 0.0f};
};
static_assert(sizeof(VertexUniforms) == 256u, "VertexUniforms must match shaders/ge.metal");

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
static_assert(sizeof(Light) == 128u, "Light must match shaders/ge.metal");

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
static_assert(sizeof(LightingUniforms) == 688u, "LightingUniforms must match shaders/ge.metal");

struct FragmentUniforms {
    std::array<float, 4> fix{};
    std::array<std::uint32_t, 4> texture{};
    std::array<std::uint32_t, 4> alpha_test{};
    std::array<float, 4> fog{};               // rgb: the fog colour; w: 1 when fogged
    std::array<std::uint32_t, 4> stencil{};  // x: 1 when the alpha stored is y (the PSP's stencil), not the fragment's
    // The mip level the GE samples (task 037): x the rule (kLevelNone, kLevelAuto, kLevelConstant, kLevelSlope),
    // y the part of the level D (in 1/16 levels) that does not change across the draw, z and w level 0's size.
    std::array<float, 4> level{};
    // x: the highest D, 16 x (levels - 1). Texture detail (task 075, D-019), with the option on: y the shift
    // subtracted from D, 16 x log2(S) at internal scale S, and z 1: the level through gradient2d, sampled
    // anisotropically. Both 0 otherwise (Original: the level() sample as before).
    std::array<float, 4> level_range{};
    std::array<std::uint32_t, 4> color_test{};  // the colour test (task 040): function, reference, mask
    // A draw into a 16-bit target (task 040), which blends in the shader: x 1 when blended, y and z the GE's source
    // and destination factors, w its equation; the FIX colours; the dither matrix's rows; x the target's format and
    // y 1 when the draw dithers.
    std::array<std::uint32_t, 4> blend{};
    std::array<float, 4> fix_source{};
    std::array<float, 4> fix_destination{};
    std::array<std::uint32_t, 4> dither{};
    std::array<std::uint32_t, 4> target{};
    // A target sampled as the texture (task 063): the texture's place in the 480x272 image, uv * xy + zw, applied
    // after the GE's wrap in the texture's own coordinates; x of `wrap` 1 when both apply, y and z 1 when s and t
    // clamp (0: they repeat).
    std::array<float, 4> uv_remap{1.0f, 1.0f, 0.0f, 0.0f};
    std::array<std::uint32_t, 4> wrap{};
};
static_assert(sizeof(FragmentUniforms) == 240u, "FragmentUniforms must match shaders/ge.metal");

// FragmentUniforms::level.x: how the level is chosen. None samples level 0 with the derivatives Metal takes (a
// texture without levels); the others are TEXLEVEL's modes 0 to 2 plus one, the level computed in the shader.
constexpr float kLevelNone = 0.0f;
constexpr float kLevelAuto = 1.0f;
constexpr float kLevelConstant = 2.0f;
constexpr float kLevelSlope = 3.0f;
// The sampler index's mip filter bits (the sampler table in initialize()).
constexpr std::uint32_t kMipNearest = 16u;
constexpr std::uint32_t kMipLinear = 32u;
// The sampler index's anisotropy bit (task 075): maxAnisotropy kMaxAnisotropy, for a Texture detail draw.
constexpr std::uint32_t kAnisotropic = 64u;
constexpr NSUInteger kMaxAnisotropy = 16u;  // Metal's maximum; MTLDevice has no query for a lower one

// A render target: (colour address, stride, pixel format), docs/ge-backend.md section 2.
struct TargetKey {
    std::uint32_t address{};
    std::uint32_t stride{};
    std::uint32_t format{};  // 0 5650, 1 5551, 2 4444, 3 8888
    auto operator<=>(const TargetKey &) const = default;
};

struct Target {
    TargetKey key;
    // The internal scale it is drawn at (D-015): 480S x 272S pixels, each S x S block one pixel of the guest's. Under
    // the Fill aspect (task 086) S is the vertical scale alone, the whole number the mip and texture detail arithmetic
    // uses, and `columns` the width: the drawable's shape at 272S rows, so a guest pixel is columns/480 (scale_x())
    // pixels wide and S tall. 480S otherwise, and 480 for a narrower key (1x whatever the scale).
    std::uint32_t scale{1u};
    std::uint32_t columns{kWidth};
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
    // Its textures' size in pixels, and its colour's bytes at 4 a pixel.
    [[nodiscard]] std::uint32_t width() const { return columns; }
    [[nodiscard]] std::uint32_t height() const { return kHeight * scale; }
    // The horizontal scale: S, or under Fill a fraction (task 086).
    [[nodiscard]] float scale_x() const { return static_cast<float>(columns) / static_cast<float>(kWidth); }
    // Of another shape than the PSP's (Fill, task 086).
    [[nodiscard]] bool reshaped() const { return columns != kWidth * scale; }
    [[nodiscard]] std::size_t picture_bytes() const { return static_cast<std::size_t>(width()) * height() * 4u; }
    // The guest memory the target covers from its address: kHeight rows of `stride` pixels.
    [[nodiscard]] std::uint64_t bytes() const {
        return static_cast<std::uint64_t>(key.stride) * kHeight * bytes_per_pixel();
    }
    // Whether byte `address` lies in that memory.
    [[nodiscard]] bool contains(std::uint64_t address) const {
        return address >= key.address && address - key.address < bytes();
    }
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
    bool color_test{};  // task 040: the colour test in the fragment function
    // Task 040: a 5650, 5551 or 4444 target: ge_fragment_16, which blends in the shader (the pipeline does not) and
    // keeps the format's bits, dithered when the draw says.
    bool sixteen{};
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

// What a texture bind looks up while its display list runs, before its contents are hashed.
struct TextureIdentity {
    std::uint32_t address{};
    std::uint32_t buffer_width{};
    std::uint32_t size{};
    std::uint32_t format{};
    std::uint32_t clut_address{};
    std::uint32_t clut{};
    bool swizzled{};
    std::uint32_t levels{};       // the levels uploaded (task 037), 1 without mipmaps
    std::uint64_t level_places{}; // a hash of levels 1 and up's addresses, row lengths and sizes
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
    std::uint64_t decoded_levels{};  // mip levels decoded after the first, in the decoded textures (task 037)
    std::uint64_t mipmapped_draws{}; // draws that sampled a texture with levels
    std::uint64_t enhanced_draws{};  // of those, the ones Texture detail drew (task 075)
    std::uint64_t framebuffer_textures{};
    std::uint64_t texture_mapped{};  // draws whose texture coordinates came from the texture matrix or the normals
    std::uint64_t color_tested{};    // draws with the colour test (task 040)
    std::uint64_t sixteen_bit{};     // draws into 5650, 5551 and 4444 targets, which keep the format's bits
    std::uint64_t dithered{};        // of those, the ones the GE dithers
    std::uint64_t depth_clamped{};   // transformed draws with CLIPENABLE's depth clamp
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
    std::uint64_t upscaled{};        // of the decoded textures, those upscaled 4x for 2D draws (task 073)
    double upscale_ms{};             // the time the scaler took for them (sprite_upscale.cpp)
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

// The switches initialize() reads once from the environment and the backend's config (metal_backend.mm); the file
// that draws each concern reads its own. The class's switches_.
struct Switches {
    bool sharp{};      // the config's sharp textures: nearest filtering
    bool log_draws{};  // PURE_METAL_LOG
    bool no_framebuffer_textures{};
    bool no_lighting{};
    bool no_fog{};
    bool no_cull{};
    bool no_texture_map{};
    bool no_mipmaps{};
    bool no_color_test{};
    bool no_dither{};
    bool no_depth_clamp{};
    std::uint32_t show_target{};  // PURE_METAL_SHOW_TARGET: the target each flip presents instead of the display
    std::string sprite_dump;      // PURE_SPRITE_DUMP (task 073): the folder each upscaled texture is written to once
};

// The frame trace and the counts' lines (metal_trace.mm), and the framework's traces. The class's trace_.
struct TraceState {
    // PURE_TRACE_STENCIL_COPY and PURE_TRACE_DEPTH_READBACK: a line per copy of the stencil into the alpha and per
    // depth write-back; and whether the first write-back's line was said.
    bool stencil_copy{};
    bool depth{};
    bool depth_announced{};
    // PURE_METAL_TRACE (task 033): the interval's times, the counts at the last flip, the rows not written yet.
    FrameTimes times;
    Stats stats;
    std::FILE *file{};
    std::string path;
    std::deque<TraceRow> pending_rows;
    std::uint64_t rows{};
    std::uint64_t shown{};      // rows whose picture reached the screen
    std::uint64_t not_shown{};  // rows whose picture the shell says never did
    std::chrono::steady_clock::time_point last_flip{};
    bool has_flip{};
    bool shell_seen{};          // a Metal shell reports its presents
    double last_presented_s{};  // when the last picture shown reached the screen
    // When the backend started (the rows' times, the exit line's seconds); the line every 600 frames.
    std::chrono::steady_clock::time_point started{};
    std::chrono::steady_clock::time_point report_start{};
    std::uint64_t report_frames{};
    std::uint64_t report_draws{};
};

// The keys the draws used (PURE_METAL_PIPELINES_OUT) and the pre-warm on the backend's side (metal_pipelines.mm).
// The class's prewarm_.
struct PrewarmState {
    std::string pipelines_out;
    std::set<RenderKey> render_seen;
    std::set<DepthStencilKey> depth_seen;
    std::shared_ptr<Prewarm> shared;  // what the completion handlers fill; null without a list
    std::string path;
    std::size_t depth_states{};
    double start_ms{};
    bool reported{};
    std::uint64_t used{};
    std::uint64_t waits{};
    std::uint64_t missed{};
};

} // namespace pure::gpu::metal_backend
