// The Metal GE backend's class (PURE_GE_BACKEND=metal; docs/metal-backend.md), declared here and defined by concern
// in the .mm files beside it (docs/metal-backend.md, "Files"; the heading of each group of members names its
// file), with the helpers more than one of those files uses. Objective-C++ only.
#pragma once

#include "metal_types.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace pure::gpu::metal_backend {

// Helpers more than one of the files uses, each defined in the file named beside it.
std::array<float, 4> unpack_color(std::uint32_t color, float fourth = 1.0f);  // metal_draw.mm
void not_emulated(const char *what, std::uint32_t value);                     // metal_backend.mm
MTLCompareFunction to_compare(std::uint32_t function);                        // metal_pipelines.mm
std::uint32_t stored_reference(const DrawCall &call);                         // metal_effects.mm
int stencil_alpha(const DrawCall &call);                                      // metal_effects.mm
bool alpha_follows_stencil(const DrawCall &call, bool depth_can_fail);        // metal_effects.mm
std::uint32_t texture_bits(TextureFormat format);                             // metal_textures.mm

class MetalGeBackend final : public pk::GeBackend {
public:
    ~MetalGeBackend() override { shutdown(); }

    const char *name() const noexcept override { return "metal"; }
    bool needs_window() const noexcept override { return false; }

    bool initialize(const pk::BackendConfig &config, std::string &error) override;
    void shutdown() override;
    void begin_frame() override;
    void begin_display_list() override { list_keys_.clear(); }
    void submit(const DrawCall &call, const GuestMemory &memory) override;
    void block_transfer(const pk::BlockTransfer &transfer, GuestMemory &memory) override;
    void write_back_frame(GuestMemory &memory) override;
    void read_back_framebuffer(std::uint32_t address, GuestMemory &memory) override;
    bool write_back_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                          GuestMemory &memory, const char *why) override;
    void upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                      std::uint32_t height, std::uint32_t stride) override;
    pk::PresentedImage present_image(std::uint32_t display_address) override;
    bool capture_frame(const std::string &path) override;

    std::uint64_t draws_submitted() const noexcept override { return stats_.draws; }
    std::uint64_t frames_presented() const noexcept override { return frames_; }

    // The menu's Resolution row (patch 0017-internal-scale-by-backend, task 067): the setting (0 Auto) takes effect
    // at the next frame (metal_backend.mm); the screen-wide targets' size now (under Fill, task 086, the drawable's
    // shape at 272S rows).
    bool supports_internal_scale() const noexcept override { return true; }
    void set_internal_scale(std::uint32_t setting) override;
    std::array<std::uint32_t, 2> target_size() const noexcept override { return {columns_, kHeight * scale_}; }

private:
    // The frame flow: start, shutdown, submit, the flip, captures; command buffers, passes, space (metal_backend.mm)
    void ensure_commands();
    void end_encoder();
    id<MTLCommandBuffer> commit(bool wait);
    void check(id<MTLCommandBuffer> commands);
    std::pair<id<MTLBuffer>, NSUInteger> allocate(std::size_t bytes);
    void begin_pass(Target &target);
    void read_back(Target &target);
    void copy_to_buffer(id<MTLTexture> texture, __strong id<MTLBuffer> &buffer, MTLBlitOption options);
    // The screen-wide targets' size a setting gives now: S, and the width, 480S or under Fill the drawable's shape at
    // 272S rows (task 086).
    struct Extent {
        std::uint32_t scale{1u};
        std::uint32_t columns{kWidth};
    };
    static Extent extent_for(std::uint32_t setting);
    void apply_scale();

    // Targets and guest memory: the target cache, transfers, read-backs, write-backs, CPU pictures (metal_targets.mm)
    Target &target_for(const TargetKey &key);
    void change_scale(const Extent &extent);
    Target *latest_target_at(std::uint32_t address);
    Target *latest_retired_at(std::uint32_t address);
    bool retired(const Target *target) const;
    void snapshot_guest_words(const GuestMemory &memory, Target &target);
    Target *find_framebuffer_texture(const GuestMemory &memory, const TextureState &texture, std::uint32_t &x,
                                     std::uint32_t &y);
    id<MTLTexture> sample_target(Target &source, const Target &drawn);
    Target *drawn_target_containing(std::uint32_t start, std::uint64_t address);
    static bool frame_written_back(const Target &target);
    void store_target(GuestMemory &memory, Target &target, std::uint32_t first_row, std::uint32_t rows,
                      GuestWrites &writes);
    const std::uint8_t *guest_pixels(const Target &target, const std::uint8_t *pixels);
    bool store_pixels(GuestMemory &memory, Target &target, const std::uint8_t *pixels, std::uint32_t first_row,
                      std::uint32_t rows);
    bool store_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
                     GuestMemory &memory, const char *why);
    void upload(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height,
                std::uint32_t stride);
    void upload_fitted(Target &target, const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height,
                       std::uint32_t stride);
    void uploaded(Target &target);

    // Textures from guest memory: mip levels, the content key, the decode and cache, the sprite upscale (task 073), the
    // level rule, the game options the backend reads (tasks 073 and 075) (metal_textures.mm)
    std::uint32_t mip_levels(const GuestMemory &memory, const TextureState &state);
    const Target *target_holding(std::uint32_t address, std::size_t bytes) const;
    static std::uint64_t content_key(const GuestMemory &memory, const TextureState &state, std::uint32_t levels);
    static bool upscalable(TextureFormat format);
    void read_game_options(bool at_start);
    id<MTLTexture> decoded_texture(const GuestMemory &memory, const TextureState &state, std::uint32_t levels,
                                   bool upscale);
    void dump_sprite(const GuestMemory &memory, std::uint64_t key, const TextureState &state);
    static void set_level_rule(const TextureState &state, std::uint32_t levels, FragmentUniforms &fragment);

    // Pipelines: fragment-function variants, render and depth-stencil states, the pre-warm list (metal_pipelines.mm)
    id<MTLFunction> fragment_function(std::uint32_t variant, NSError **failure = nullptr);
    MTLRenderPipelineDescriptor *pipeline_descriptor(const RenderKey &key);
    id<MTLRenderPipelineState> render_pipeline(const RenderKey &key);
    id<MTLDepthStencilState> depth_state(const DepthStencilKey &key);
    id<MTLDepthStencilState> make_depth_state(const DepthStencilKey &key);
    static std::string find_pipeline_list();
    void start_prewarm();
    void report_prewarm_done();
    void report_pipelines();
    void write_pipeline_list();

    // Effects: the stencil kept as the alpha, and the blend of a 16-bit target in the shader (metal_effects.mm)
    void resolve_stencil_alpha(const char *reason);
    static bool blend_reads_source_alpha(const RenderKey &key, std::uint8_t write_mask);
    static bool blend_reads_destination_alpha(const RenderKey &key);
    static void shader_blend(const BlendState &blend, FragmentUniforms &fragment);
    static bool shader_blend_reads_destination_alpha(const FragmentUniforms &fragment, std::uint8_t write_mask);

    // The frame trace (PURE_METAL_TRACE) and the counts printed every 600 frames and at exit (metal_trace.mm)
    std::string scale_report(bool changed = false) const;
    void open_trace(const char *path);
    void end_trace_interval();
    Stats since(const Stats &before) const;
    void flush_trace(bool all);
    void write_trace_row(const TraceRow &row, bool known, double presented_s, double latency_ms);
    void close_trace();
    void report();
    void report_guest_writes();

    // Draws: a DrawCall from the GE's state to the encoder (metal_draw.mm)
    struct ViewportScissor {
        NSUInteger x{}, y{}, width{}, height{};
    };
    bool expand(const DrawCall &call, const std::array<float, 16> &transform, MTLPrimitiveType &type,
                std::size_t &drawn);
    template <typename At, typename Convert>
    void expand_transformed_sprites(const DrawCall &call, const std::array<float, 16> &transform, std::size_t count,
                                    const At &at, const Convert &convert);
    void translate_blend(const BlendState &blend, RenderKey &key, FragmentUniforms &fragment,
                         std::uint32_t &blend_color);
    void fill_lighting(const DrawCall &call, bool lit, bool fogged, bool shade_mapped);
    void set_texture_map(const DrawCall &call, VertexUniforms &vertex, FragmentUniforms &fragment);
    void draw(const DrawCall &call, const GuestMemory &memory);
    void set_pipeline_key(const DrawCall &call, bool sixteen, PipelineKey &key, FragmentUniforms &fragment,
                          std::uint32_t &blend_color, std::uint32_t &stencil_reference, bool &follows);
    void fold_viewport(const DrawCall &call, const std::array<float, 16> &transform, bool clamp_depth,
                       VertexUniforms &vertex, MTLViewport &viewport);
    void bind_state(const DrawCall &call, const PipelineKey &key, id<MTLRenderPipelineState> pipeline,
                    id<MTLDepthStencilState> depth, std::uint32_t stencil_reference, const MTLViewport &viewport,
                    bool clamp_depth, const ViewportScissor &scissor, bool cull, std::uint32_t blend_color);
    void bind_inputs(id<MTLBuffer> buffer, NSUInteger offset, const VertexUniforms &vertex, bool lighting_read,
                     const FragmentUniforms &fragment, id<MTLTexture> texture, std::uint32_t sampler);
    static ViewportScissor scissor_of(const DrawCall &call);
    bool interface_fit(const Target &target, float &fit_x, float &fit_y) const;
    bool screen_wide(const DrawCall &call, const VertexUniforms &vertex, const std::array<float, 16> &transform) const;
    void log_draw(const DrawCall &call, const Target &target, const Target *source, std::uint32_t x, std::uint32_t y,
                  const ViewportScissor &scissor, bool fitted);

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
        MTLDepthClipMode depth_clip{MTLDepthClipModeClip};
        bool depth_clip_set{};
    };

    bool ready_{};
    id<MTLDevice> device_;
    id<MTLCommandQueue> queue_;
    id<MTLLibrary> library_;
    id<MTLFunction> vertex_function_;
    // By kTextured | kAlphaTest << 1 | dual source << 2 | kColorTest << 3 | 16-bit target << 4 (fragment_function()).
    std::array<id<MTLFunction>, 32> fragment_functions_{};
    std::array<id<MTLSamplerState>, 128> samplers_{};
    id<MTLTexture> white_;
    // Each holds the largest target, 480S x 272S at 4 bytes a pixel.
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

    // The internal scale of the targets at least 480 pixels wide (D-015, initialize()); the narrower ones are 1x.
    std::uint32_t scale_{1u};
    // Their width: 480S, or under the Metal shell's Fill aspect the drawable's shape at 272S rows (task 086).
    std::uint32_t columns_{kWidth};
    // The last two displayed addresses (present_image()): under Fill a 2D draw into one of them is fitted (task 086).
    std::array<std::uint32_t, 2> display_addresses_{};
    // video.internal_scale as the backend takes it (0 Auto, which follows the drawable): from initialize(), then
    // from the menu (set_internal_scale()). scale_ follows it at the next frame (apply_scale()).
    std::uint32_t setting_{1u};
    // A target was drawn into or uploaded to since the last flip: a scale change waits for the next one.
    bool frame_drawn_{};
    std::map<TargetKey, std::unique_ptr<Target>> targets_;
    // The screen-wide targets of the scale before the last change (change_scale()), out of targets_: kept while the
    // pending frame write-back or the picture shown reads one, until a flip shows a target of the new scale.
    std::vector<std::unique_ptr<Target>> retired_;
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
    // The sprite upscale (task 073): game.sprite_upscale as read at the last frame (read_game_options()), whether its
    // `on` line was said, the last upscaled texture's texels, and the keys PURE_SPRITE_DUMP has written; with it the
    // texture pack of task 074 in its pack/ folder, keyed as the framework's pack loader keys a texture (the folder and
    // its textures.ini made at the first entry).
    bool sprite_upscale_{};
    bool sprite_upscale_said_{};
    // Texture detail (task 075): game.texture_detail as read at the last frame (read_game_options()), and whether its
    // `on` line was said (at the first enhanced draw, metal_draw.mm).
    bool texture_detail_{};
    bool texture_detail_said_{};
    std::vector<std::uint8_t> upscaled_;
    std::set<std::uint64_t> sprites_dumped_;
    std::set<std::string> pack_keys_;
    bool pack_ready_{};
    std::vector<GpuVertex> vertices_;
    std::vector<GpuVertex> sprite_sources_;
    std::size_t sprite_corners_{};  // of a transformed sprite draw: vertices_ holds its sources after them
    LightingUniforms lighting_{};   // the last lit or fogged draw's, bound at buffer 2
    bool lighting_changed_{};       // since it was last bound
    bool lighting_bound_{};         // in the open encoder

    std::vector<std::uint8_t> picture_;  // the last picture read back, at its target's size
    std::uint32_t picture_width_{};
    std::uint32_t picture_height_{};
    std::uint64_t picture_frame_{~0ull};
    // A scaled target's 480x272 picture for guest memory, the centre pixel of each block (guest_pixels()).
    std::vector<std::uint8_t> guest_picture_;
    // The picture the next write_back_frame() stores: the target shown at the last flip, with its pixels in
    // frame_writeback_ once `commands` has run.
    struct PendingFrame {
        Target *target{};
        id<MTLCommandBuffer> commands;
        id<MTLBuffer> buffer;  // the frame_writeback_ the commands copy into (a scale change replaces that member)
    };
    PendingFrame pending_frame_;
    double last_wait_ms_{};  // of the last commit(true)
    std::set<std::uint32_t> bad_levels_;  // textures drawn at level 0 alone for a level mip_levels() refused
    Switches switches_;     // read once by initialize() (metal_backend.mm)
    TraceState trace_;      // PURE_METAL_TRACE, the framework's traces and the counts' lines (metal_trace.mm)
    PrewarmState prewarm_;  // the pre-warm and the keys the draws used (metal_pipelines.mm)

    std::uint64_t frames_{};
    std::uint64_t frame_draws_{};
    Stats stats_;
};

} // namespace pure::gpu::metal_backend
