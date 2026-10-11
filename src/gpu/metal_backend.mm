// The GE drawn with Metal: PURE_GE_BACKEND=metal (docs/metal-backend.md).
//
// A GeBackend (vendor/portablekit/host/gpu/ge_backend.hpp, docs/ge-backend.md) in our own sources, so its
// registration below is linked into the program directly. Task 023 built what the 2D frontend needs, task
// 024 the 3D draws, task 025 the effects:
//
//   targets    keyed by (colour address, stride, format), each an RGBA8 colour texture (5650, 5551 and 4444
//              targets too) and a Depth32Float_Stencil8 texture, at 480x272, or at 480S x 272S for a key at
//              least 480 wide at the internal scale S (task 066, D-015; guest memory gets each block's
//              centre pixel). A pass draws into one target; switching targets ends it.
//   stencil    the GE's stencil test and operations on the attachment; the colour target's alpha kept as
//              the PSP's stencil by patch 0006's rule: written by the zpass REPLACE/ZERO where the colour
//              path can (dual-source blending under a source-alpha blend), copied from the attachment where
//              it cannot, before a destination-alpha read and at the end of the pass.
//   textures   a bind that lies in a target samples that target, the one starting at the address first
//              (patch 0003), while guest memory under it is what it was when the target was first drawn
//              in the frame; anything else is decoded from guest memory with the framework's
//              decode_texture() and cached by its contents (texels and the palette entries it can reach);
//              a texture with mip levels (task 037) is a mipmapped texture, each level decoded from its own
//              address, sampled at the level the GE's rule (TEXLEVEL) picks. A 2D draw's texture (through
//              mode, or orthographic and unlit) in a palette or 16-bit format is upscaled 4x at decode (task
//              073, the menu's Text and sprites row: sprite_upscale.cpp) and sampled linear.
//   draws      every primitive, through mode or transformed, through one pipeline whose key holds the
//              blend, the write masks, the alpha test, the colour test, the depth test and the stencil; clears;
//              scissor; the GE viewport folded into clip space; back-face culling. A draw into a 5650, 5551 or
//              4444 target blends in the shader and keeps the format's bits, dithered when the GE says (task
//              040); with CLIPENABLE on, depth is clamped as the GE clamps it, and MINZ/MAXZ tested.
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
//
// The files: this one is the backend proper, the class's start and shutdown, submit(), the flip (present_image()),
// captures, the frame's command buffers, render passes and vertex space, and the registration; the rest by concern,
// metal_targets.mm (the target cache, guest memory, CPU pictures), metal_textures.mm (textures from guest memory),
// metal_pipelines.mm (pipelines and the pre-warm), metal_effects.mm (the stencil kept as the alpha, the 16-bit
// blend), metal_trace.mm (the frame trace and the counts), metal_draw.mm (a draw, from the GE's state to the
// encoder). The class is declared in metal_backend.hpp, its shared types are in metal_types.hpp, and the shaders are
// shaders/ge.metal (docs/metal-backend.md, "Files").
#include "metal_backend.hpp"
#include "ge_metal.hpp"  // shaders/ge.metal as a string, generated by the build
#include "metal_device.hpp"
#include "profile.hpp"
#include "settings/settings.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <system_error>

namespace pure::gpu::metal_backend {
namespace {

// The internal scale of the screen-wide targets (D-015, task 066): video.internal_scale (PURE_INTERNAL_SCALE), 1 to
// kMaxScale, at start; then the menu's Resolution row's (task 067, set_internal_scale()). The setting at start: the
// config's (the settings'), except with no window at all (the headless shell, ge_replay), where it is 1 unless
// PURE_INTERNAL_SCALE decides the setting, and then that (ge_replay's config holds the recording's scale), so
// headless runs and the checks stay at 1 whatever settings.ini holds.
std::uint32_t setting_at_start(const pk::BackendConfig &config) {
    std::uint32_t drawable_width = 0u, drawable_height = 0u;
    pure::metal::drawable_size(drawable_width, drawable_height);
    const bool window = config.vulkan_shell != nullptr || drawable_height != 0u;
    if (window) return config.internal_scale;
    return portablekit::settings::overridden_by("video.internal_scale").empty()
               ? 1u
               : portablekit::settings::current().internal_scale;
}

// The scale a setting gives now: 1 to kMaxScale as it says (7 and 8 drawn at kMaxScale); Auto (0) the smallest S
// whose 272 S covers the Metal shell's drawable height as it is now, at most kMaxScale, and 1 without a Metal shell.
std::uint32_t scale_for(std::uint32_t setting) {
    std::uint32_t scale = setting;
    if (scale == 0u) {
        std::uint32_t drawable_width = 0u, drawable_height = 0u;
        pure::metal::drawable_size(drawable_width, drawable_height);
        scale = 1u;
        while (scale < kMaxScale && kHeight * scale < drawable_height) ++scale;
    }
    return std::clamp(scale, 1u, kMaxScale);
}

} // namespace

// Says once per value which GE state is drawn approximately.
void not_emulated(const char *what, std::uint32_t value) {
    static std::set<std::pair<std::string, std::uint32_t>> seen;
    if (!seen.emplace(what, value).second) return;
    std::cout << "[metal] " << what << " 0x" << std::hex << value << std::dec << " is not emulated\n" << std::flush;
}

bool MetalGeBackend::initialize(const pk::BackendConfig &config, std::string &error) {
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
        // By kTextured | kAlphaTest << 1, then the same with the second output for dual-source blending: the
        // eight made here; those with the colour test or for a 16-bit target (task 040) on first use.
        for (std::uint32_t variant = 0; variant < 8u; ++variant) {
            if (fragment_function(variant, &failure) == nil) {
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
        // bit 3 clamp v; bits 4 and 5 between mip levels (task 037): 0 level 0 only, 1 the nearest level
        // (kMipNearest), 2 linear between the two nearest (kMipLinear).
        for (std::uint32_t index = 0; index < samplers_.size(); ++index) {
            MTLSamplerDescriptor *sampler = [MTLSamplerDescriptor new];
            sampler.magFilter = (index & 1u) != 0u ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
            sampler.minFilter = (index & 2u) != 0u ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
            sampler.sAddressMode = (index & 4u) != 0u ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
            sampler.tAddressMode = (index & 8u) != 0u ? MTLSamplerAddressModeClampToEdge : MTLSamplerAddressModeRepeat;
            const std::uint32_t mip = index & (kMipNearest | kMipLinear);
            sampler.mipFilter = mip == kMipLinear    ? MTLSamplerMipFilterLinear
                                : mip == kMipNearest ? MTLSamplerMipFilterNearest
                                                     : MTLSamplerMipFilterNotMipmapped;
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
        setting_ = setting_at_start(config);
        scale_ = scale_for(setting_);
        // The largest target's colour (or depth, 4 bytes a pixel too): 480S x 272S.
        const std::size_t largest = kPictureBytes * scale_ * scale_;
        readback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
        frame_writeback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
        guest_readback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
        pool_ = std::make_shared<ChunkPool>();

        // The hand-over (a read-back a frame) only for the Vulkan shell; any other shell has
        // vulkan_shell null and shows the texture present_image() names, or no window at all.
        shell_ = config.vulkan_shell;
        switches_.sharp = config.sharp_textures;
        const char *shell_switch = portablekit::env("METAL_SHELL");
        switches_.to_shell = shell_ != nullptr && !(shell_switch != nullptr && std::strcmp(shell_switch, "0") == 0);
        const char *log = portablekit::env("METAL_LOG");
        switches_.log_draws = log != nullptr && *log != '\0' && std::strcmp(log, "0") != 0;
        switches_.no_framebuffer_textures = portablekit::env("NO_FB_TEXTURES") != nullptr;
        // The framework's switches for bisecting 3D draws, as the Vulkan backend reads them: NO_LIGHTING
        // draws lit geometry with its vertex colour (white without one) and turns fog off too, NO_FOG turns
        // fog off alone, NO_CULL culls nothing.
        switches_.no_lighting = portablekit::env("NO_LIGHTING") != nullptr;
        switches_.no_fog = switches_.no_lighting || portablekit::env("NO_FOG") != nullptr;
        switches_.no_cull = portablekit::env("NO_CULL") != nullptr;
        // Ours (task 036): every draw takes its UVs (texture map mode 0), as before the mapping modes.
        switches_.no_texture_map = portablekit::env("NO_TEXMAP") != nullptr;
        // Ours (task 037): every texture uploaded and sampled at level 0 alone, as before the mip levels.
        switches_.no_mipmaps = portablekit::env("NO_MIPMAPS") != nullptr;
        // Ours (task 040), each restoring what the backend drew before: every fragment kept (no colour test);
        // 5650, 5551 and 4444 targets written at 8 bits a channel by the pipeline's blend, never dithered; every
        // transformed draw clipped at both depth planes, MINZ and MAXZ unread.
        switches_.no_color_test = portablekit::env("NO_COLOR_TEST") != nullptr;
        switches_.no_dither = portablekit::env("NO_DITHER") != nullptr;
        switches_.no_depth_clamp = portablekit::env("NO_DEPTH_CLAMP") != nullptr;
        // Ours (task 040), for looking at a target the game draws but does not show (the 565 billboard target):
        // each flip presents the target drawn last at this address instead of the display.
        if (const char *show = portablekit::env("METAL_SHOW_TARGET"); show != nullptr && *show != '\0')
            switches_.show_target = static_cast<std::uint32_t>(std::strtoul(show, nullptr, 0));
        // The framework's traces, as the Vulkan backend reads them: a line per copy of the stencil into the
        // alpha, and per depth write-back.
        trace_.stencil_copy = portablekit::env("TRACE_STENCIL_COPY") != nullptr;
        trace_.depth = portablekit::env("TRACE_DEPTH_READBACK") != nullptr;
        // Ours (task 073): the menu's Text and sprites row, read again at every frame; and PURE_SPRITE_DUMP=DIR,
        // each upscaled texture written there once (metal_textures.mm).
        read_sprite_upscale(true);
        if (const char *dump = portablekit::env("SPRITE_DUMP"); dump != nullptr && *dump != '\0') {
            std::error_code ignored;
            std::filesystem::create_directories(dump, ignored);
            switches_.sprite_dump = dump;
        }
        trace_.started = std::chrono::steady_clock::now();
        trace_.report_start = trace_.started;
        ready_ = true;
        const double ms = std::chrono::duration<double, std::milli>(trace_.started - start).count();
        std::cout << "[metal] drawing with " << device_.name.UTF8String << ", " << scale_report()
                  << "; shaders compiled in " << ms << " ms; "
                  << (switches_.to_shell ? "pictures shown in the window"
                                : (shell_ != nullptr ? "window left black (PURE_METAL_SHELL=0)"
                                                     : "pictures shown by the shell, not read back"))
                  << "\n";
        // Task 033: the frame trace, the list of keys a run used, and the pre-warm.
        if (pure::metal::trace_on()) open_trace(portablekit::env("METAL_TRACE"));
        if (const char *out = portablekit::env("METAL_PIPELINES_OUT"); out != nullptr && *out != '\0')
            prewarm_.pipelines_out = out;
        start_prewarm();
        return true;
    }
}

void MetalGeBackend::shutdown() {
    if (!ready_) return;
    ready_ = false;
    @autoreleasepool {
        commit(true);
        for (id<MTLCommandBuffer> commands : in_flight_) [commands waitUntilCompleted];
        in_flight_.clear();
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - trace_.started).count();
        std::cout << "[metal] " << frames_ << " frames, " << stats_.draws << " draws, " << stats_.passes
                  << " passes, " << stats_.decoded << " textures decoded, " << stats_.framebuffer_textures
                  << " framebuffer textures, " << stats_.texture_mapped << " texture-mapped draws, "
                  << stats_.mipmapped_draws << " mipmapped draws (" << stats_.decoded_levels
                  << " mip levels decoded after the first), "
                  << stats_.copies << " target copies, " << stats_.uploads
                  << " uploads, " << targets_.size() << " targets, " << stats_.waits << " GPU waits ("
                  << stats_.wait_ms << " ms) in " << seconds << " s; " << stats_.upscaled
                  << " textures upscaled (" << stats_.upscale_ms << " ms)\n";
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
        retired_.clear();
        textures_.clear();
        list_keys_.clear();
        render_pipelines_.clear();
        depth_states_.clear();
        if (prewarm_.shared) {
            // Pipelines still compiling finish into the shared state their handlers hold, not into this.
            std::lock_guard<std::mutex> guard(prewarm_.shared->lock);
            prewarm_.shared->ready.clear();
        }
        prewarm_.shared.reset();
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

// After each flip: a scale the menu changed while the frame was drawn (the menu over the running game), or Auto's
// when the drawable's height crossed a multiple of 272 (a resize, full screen and back), takes effect here.
// The Text and sprites row is read here too (task 073), so a change in the menu applies from the next frame.
void MetalGeBackend::begin_frame() {
    apply_scale();
    if (ready_) read_sprite_upscale(false);
}

// The menu's Resolution row (task 067). Between two frames, with nothing drawn since the flip (the paused menu runs
// there), the scale changes now; otherwise at the next begin_frame(), so that no frame is drawn at two scales.
void MetalGeBackend::set_internal_scale(std::uint32_t setting) {
    setting_ = setting;
    if (!frame_drawn_) apply_scale();
}

void MetalGeBackend::apply_scale() {
    if (!ready_) return;
    const std::uint32_t wanted = scale_for(setting_);
    if (wanted != scale_) change_scale(wanted);
}

void MetalGeBackend::submit(const DrawCall &call, const GuestMemory &memory) {
    if (!ready_) return;
    const TraceClock clock(trace_.file != nullptr, trace_.times.submit);
    @autoreleasepool {
        draw(call, memory);
    }
}

pk::PresentedImage MetalGeBackend::present_image(std::uint32_t display_address) {
    pk::PresentedImage image;
    if (!ready_) return image;
    // The trace's row of the interval this flip ends, before this call's own time, which starts the next one.
    if (trace_.file != nullptr) end_trace_interval();
    const TraceClock clock(trace_.file != nullptr, trace_.times.present);
    @autoreleasepool {
        ++frames_;
        if (trace_.file != nullptr) pure::metal::trace_flip(frames_);
        frame_draws_ = 0u;
        Target *shown = latest_target_at(GuestMemory::canonical(display_address));
        if (switches_.show_target != 0u)
            if (Target *named = latest_target_at(GuestMemory::canonical(switches_.show_target)); named != nullptr)
                shown = named;
        // After a scale change, until the game draws its display again: the picture at the scale before (task 067).
        if (shown == nullptr && !retired_.empty()) shown = latest_retired_at(GuestMemory::canonical(display_address));
        if (shown == nullptr) shown = last_drawn_;
        presented_ = shown;
        // The next write_back_frame() stores this picture (as the Vulkan backend stores at each flip the
        // target the flip before showed): read back for the Vulkan shell anyway, else copied into a shared
        // buffer by this frame's commands.
        const bool written_back = shown != nullptr && frame_written_back(*shown);
        pending_frame_ = PendingFrame{};
        if (shown != nullptr && switches_.to_shell) {
            read_back(*shown);
            show_in_shell(shell_, display_address, picture_.data(), picture_width_, picture_height_, shell_scratch_);
            if (written_back) pending_frame_ = PendingFrame{shown, nil, true};
        } else {
            if (written_back) copy_to_buffer(shown->color, frame_writeback_, MTLBlitOptionNone);
            id<MTLCommandBuffer> committed = commit(false);
            if (written_back) pending_frame_ = PendingFrame{shown, committed, false, frame_writeback_};
        }
        frame_drawn_ = false;
        // The targets of the scale before a change go once nothing reads them: the write-back pending now is this
        // picture's, and it is the new scale's (or nothing at all).
        if (!retired_.empty() && !retired(shown)) retired_.clear();
        if (frames_ % kReportEvery == 0u) report();
        if (prewarm_.shared && !prewarm_.reported) report_prewarm_done();
        if (shown != nullptr) {
            image.api = pk::ImageApi::Metal;
            image.address = shown->key.address;
            // The target's own size: 480S x 272S for a display target at internal scale S (D-015).
            image.width = shown->width();
            image.height = shown->height();
            image.image = reinterpret_cast<std::uint64_t>((__bridge void *)shown->color);
        }
    }
    return image;
}

bool MetalGeBackend::capture_frame(const std::string &path) {
    if (!ready_ || presented_ == nullptr) return false;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    @autoreleasepool {
        // At the target's own size (480S x 272S at internal scale S): the suite's comparisons resize.
        if (picture_frame_ != frames_) read_back(*presented_);
        return pk::write_bmp_file(path, picture_.data(), picture_width_, picture_height_);
    }
}

void MetalGeBackend::ensure_commands() {
    if (commands_ != nil) return;
    commands_ = [queue_ commandBuffer];
    frame_buffers_ = [NSMutableArray new];
}

// Ends the pass. Whatever reads the target next (a texture, the display, guest memory) reads its alpha,
// so a stencil the draws left different from it is copied into it first.
void MetalGeBackend::end_encoder() {
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
id<MTLCommandBuffer> MetalGeBackend::commit(bool wait) {
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
        trace_.times.wait_ring += ms;
        ++stats_.waits;
        check(in_flight_.front());
        in_flight_.pop_front();
    }
    return committed;
}

void MetalGeBackend::check(id<MTLCommandBuffer> commands) {
    if (commands.status != MTLCommandBufferStatusError) return;
    static std::uint32_t reported = 0u;
    if (reported++ < 8u)
        std::cout << "[metal] the GPU failed a frame's commands: "
                  << (commands.error != nil ? commands.error.localizedDescription.UTF8String : "no message")
                  << "\n" << std::flush;
}

// `bytes` of shared memory for the frame being recorded, at a 256-byte boundary.
std::pair<id<MTLBuffer>, NSUInteger> MetalGeBackend::allocate(std::size_t bytes) {
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

void MetalGeBackend::begin_pass(Target &target) {
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
    frame_drawn_ = true;
    target.color_defined = true;
    target.depth_defined = true;
    current_target_ = &target;
    last_drawn_ = &target;
    bound_ = Bound{};
    lighting_bound_ = false;
    ++stats_.passes;
}

// The target's pixels into picture_, at its own size, waiting for the GPU.
void MetalGeBackend::read_back(Target &target) {
    copy_to_buffer(target.color, readback_, MTLBlitOptionNone);
    commit(true);
    trace_.times.wait_capture += last_wait_ms_;
    picture_.assign(static_cast<const std::uint8_t *>(readback_.contents),
                    static_cast<const std::uint8_t *>(readback_.contents) + target.picture_bytes());
    picture_width_ = target.width();
    picture_height_ = target.height();
    picture_frame_ = frames_;
}

// A blit of a target's `texture`, whole (480S x 272S at its internal scale), into `buffer` at 4 bytes a pixel,
// recorded in the frame's commands: its colour (RGBA) with MTLBlitOptionNone, its depth (floats) with
// MTLBlitOptionDepthFromDepthStencil. Each caller commits, waits and counts as it needs. A buffer smaller than the
// texture (a target of the scale before a change, read after the buffers were made for the new one) is made anew.
void MetalGeBackend::copy_to_buffer(id<MTLTexture> texture, __strong id<MTLBuffer> &buffer, MTLBlitOption options) {
    ensure_commands();
    end_encoder();
    const NSUInteger width = texture.width;
    const NSUInteger height = texture.height;
    if (buffer.length < width * height * 4u)
        buffer = [device_ newBufferWithLength:width * height * 4u options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
    [blit copyFromTexture:texture
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(width, height, 1)
                        toBuffer:buffer
               destinationOffset:0
          destinationBytesPerRow:width * 4u
        destinationBytesPerImage:width * height * 4u
                         options:options];
    [blit endEncoding];
}

namespace {

const pk::BackendRegistration registration("metal",
                                           "native Metal (tasks 023-025: targets, textures, 2D and 3D draws, the "
                                           "stencil, read-backs and write-backs)",
                                           [] { return std::unique_ptr<pk::GeBackend>(new MetalGeBackend()); });

} // namespace

} // namespace pure::gpu::metal_backend
