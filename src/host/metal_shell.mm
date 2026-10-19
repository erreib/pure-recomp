// The Metal shell: PURE_SHELL=metal (docs/metal-backend.md, "The Metal shell").
//
// A host::Shell (vendor/portablekit/host/shell/shell.hpp, docs/ge-backend.md section 8) in our own sources, so its
// registration below is linked into the program directly, as the Metal GE backend's is. With PURE_GE_BACKEND=metal
// the game runs with no Vulkan or MoltenVK at all:
//
//   window     an SDL window (SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY) with SDL's
//              Metal view, whose CAMetalLayer draws with the program's one Metal device and command queue
//              (src/gpu/metal_device.hpp), the ones the Metal backend draws with: its textures are ours to sample,
//              and our presents are ordered after its frames. The window's size is in points (480x272 times the
//              window-size setting); the layer's drawable is that size in the display's pixels (task 065), kept so
//              on every pixel-size change, so a Retina display shows the picture unblurred by the system.
//   input      the window's events as the Vulkan renderer's pump handles them (close, gamepads coming and going,
//              the captured mouse, the interface's event hook); the pad from host::SdlPad, which the Vulkan
//              shell shares, so the keyboard, the gamepad, the input script's keys and its virtual gamepad reach
//              the game the same way in both. No touch controls.
//   present    the GE backend's image into the layer's next drawable, letterboxed to 480:272 (or stretched),
//              nearest or linear (the sharp-screen setting; nearest whenever the picture is an exact multiple of
//              480x272, see sampler_for()); a Metal image is sampled where the backend left it, a Cpu image is
//              uploaded first, no image clears to black. The interface over it, then presentDrawable and commit.
//              Vsync is the layer's displaySyncEnabled. No frame interpolation: present_due and present_until do
//              nothing. Under the Fill aspect (task 086, for a game that widens its view) the Metal backend draws
//              its screen-wide targets at the drawable's shape (metal_device.hpp's set_fill), the picture covers the
//              whole drawable, and game_aspect() hands the game the targets' shape for its next frame.
//   pacing     while the game is held to real time, each picture is presented at the real time of the vblank after
//              the one its frame began from (presentDrawable:atTime:), as the PSP shows a flip at the next vblank: a
//              flip a millisecond late or early then no longer shows one picture for three refreshes of a 120 Hz
//              display and the next for one (task 033). The vblank is the kernel's: the PSP's 59.94 Hz, or the
//              display's refresh under the Display rate row (E8, task 089), when a picture is due every refresh.
//   overlay    the performance overlay (task 090; the Performance row, `video.performance`, and F3): the framework's
//              perf::draw_overlay image, 196x72, drawn by the picture's pipeline over the drawable's top-left corner at
//              perf::overlay_scale(drawable height), opaque, on game presents only, before the interface, as the
//              Vulkan renderer draws it over its window.
//   captures   capture_window: the next presented drawable, interface and overlay included, read back as a BMP.
//   trace      with PURE_METAL_TRACE (task 033), each present of a game picture tells the backend's frame trace its
//              CPU time, the wait in nextDrawable, and (from the drawable's presented handler) when the picture
//              reached the screen, through the hook in metal_device.hpp.
//   interface  ImGui's SDL3 platform backend (InitForMetal) and its Metal renderer backend (third_party/imgui_metal,
//              Dear ImGui 1.92.9b), drawn into the drawable after the game's picture.
//
// The backend commits each frame's command buffer at present_image(), before present() is called, on the queue this
// shell commits its presents to: Metal runs one queue's command buffers in commit order, and its targets are tracked
// resources, so the shell's sampling comes after every draw of the frame, and the next frame's draws after the
// sampling. (On a queue of the shell's own nothing ordered them, and the window dropped the race HUD: task 031.)
#include "../gpu/metal_device.hpp"
#include "../helpers.hpp"
#include "shell/sdl_pad.hpp"
#include "shell/shell.hpp"

#include "gpu/ge_backend.hpp"
#include "gpu/vulkan_renderer.hpp"  // its window title, fast-forward interval and Aspect rule, which this shell shares
#include "kernel/kernel.hpp"
#include "perf/frame_stats.hpp"
#include "perf/perf_overlay.hpp"
#include "profile.hpp"
#include "settings/settings.hpp"

#include "backends/imgui_impl_sdl3.h"
#include "imgui.h"
#include "imgui_impl_metal.h"

#include <SDL3/SDL.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CABase.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace pure::host {
namespace {

namespace pk = portablekit;
namespace ph = portablekit::host;
using Clock = std::chrono::steady_clock;

constexpr std::uint32_t kPspWidth = pk::gpu::kScreenWidth;
constexpr std::uint32_t kPspHeight = pk::gpu::kScreenHeight;
// Behind the setup screens, as in the Vulkan shell: the dark brown of the project's logo.
constexpr double kBackground[3] = {0.075, 0.055, 0.045};
// The performance overlay's textures, written by the CPU and sampled by the GPU: one is rewritten while the GPU may
// still sample the other, so a present never changes the pixels of one in flight (task 090).
constexpr std::size_t kOverlaySlots = 2u;

// One triangle over the viewport, sampling the game's picture. The viewport is the letterboxed rectangle.
constexpr const char *kShaderSource = R"(
#include <metal_stdlib>
using namespace metal;

struct Shown {
    float4 position [[position]];
    float2 uv;
};

vertex Shown shell_vertex(uint id [[vertex_id]]) {
    const float2 corner = float2(float((id << 1) & 2u), float(id & 2u));
    Shown out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(corner.x, 1.0 - corner.y);
    return out;
}

fragment float4 shell_fragment(Shown in [[stage_in]], texture2d<float> picture [[texture(0)]],
                               sampler filter [[sampler(0)]]) {
    return float4(picture.sample(filter, in.uv).rgb, 1.0);
}
)";

class MetalShell final : public ph::Shell {
public:
    ~MetalShell() override { shutdown(); }

    const char *name() const noexcept override { return "metal"; }

    bool initialize(const ph::ShellConfig &config, std::string &error) override {
        @autoreleasepool {
            const pk::settings::Settings &player = pk::settings::current();
            present_mode_ = player.present_mode;
            set_aspect(player.aspect);
            sharp_ = player.sharp_screen;

            if (!SDL_Init(SDL_INIT_VIDEO)) {
                error = std::string("SDL_Init failed: ") + SDL_GetError();
                return false;
            }
            // A missing gamepad subsystem is not fatal; the keyboard still drives the pad.
            if (!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) std::cout << "[pad] no gamepad support: " << SDL_GetError() << "\n";
            else input_.scan_gamepads();
            // The drawable in the display's pixels, not in points the system then upscales (task 065).
            SDL_WindowFlags flags = SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
            if (player.fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
            const std::uint32_t scale = std::clamp<std::uint32_t>(player.window_scale, 1u, pk::settings::kMaxWindowScale);
            const std::string title = config.title.empty() ? pk::gpu::default_window_title() : config.title;
            int window_width = static_cast<int>(kPspWidth * scale);
            int window_height = static_cast<int>(kPspHeight * scale);
            // PURE_WINDOW_SIZE=WxH for a check of another shape (task 086), parsed as the Vulkan window parses it.
            int switch_width = 0, switch_height = 0;
            const bool sized = ph::window_size_switch(switch_width, switch_height);
            if (sized) {
                window_width = switch_width;
                window_height = switch_height;
            }
            window_ = SDL_CreateWindow(title.c_str(), window_width, window_height, flags);
            if (window_ == nullptr) {
                error = std::string("SDL_CreateWindow failed: ") + SDL_GetError();
                return false;
            }
            // PURE_WINDOW_SIZE counts the drawable's pixels, which the window captures and the backend's Fill shape
            // are in: at a pixel density d the window is W/d x H/d points, so a check's captures are W x H on any
            // display, as the Vulkan window's are (it draws at a pixel a point).
            if (const float density = SDL_GetWindowPixelDensity(window_); sized && density > 1.0f) {
                SDL_SetWindowSize(window_, static_cast<int>(std::lround(switch_width / density)),
                                  static_cast<int>(std::lround(switch_height / density)));
                SDL_SyncWindow(window_);
            }
            if (sized)
                std::cout << "[shell] metal: window " << switch_width << "x" << switch_height << " pixels (WINDOW_SIZE)"
                          << std::endl;
            view_ = SDL_Metal_CreateView(window_);
            if (view_ == nullptr) {
                error = std::string("SDL_Metal_CreateView failed: ") + SDL_GetError();
                return false;
            }
            layer_ = (__bridge CAMetalLayer *)SDL_Metal_GetLayer(view_);
            device_ = pure::metal::device();
            if (layer_ == nil || device_ == nil) {
                error = layer_ == nil ? "SDL's Metal view has no CAMetalLayer" : "there is no Metal device";
                return false;
            }
            // The Metal backend's queue (metal_device.hpp): a present is committed after the frame it shows.
            queue_ = pure::metal::queue();
            layer_.device = device_;
            layer_.pixelFormat = MTLPixelFormatBGRA8Unorm;
            // The window captures read the drawable back.
            layer_.framebufferOnly = NO;
            layer_.opaque = YES;
            // The colours as the Vulkan shell shows them (MoltenVK tags its sRGB swapchain so).
            CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            layer_.colorspace = srgb;
            CGColorSpaceRelease(srgb);
            layer_.displaySyncEnabled = present_mode_ != pk::settings::PresentMode::Immediate;
            update_drawable_size();

            NSError *failure = nil;
            id<MTLLibrary> library = [device_ newLibraryWithSource:@(kShaderSource) options:nil error:&failure];
            if (library == nil) {
                error = std::string("the shell's shaders do not compile: ") +
                        (failure != nil ? failure.localizedDescription.UTF8String : "no message");
                return false;
            }
            MTLRenderPipelineDescriptor *pipeline = [MTLRenderPipelineDescriptor new];
            pipeline.vertexFunction = [library newFunctionWithName:@"shell_vertex"];
            pipeline.fragmentFunction = [library newFunctionWithName:@"shell_fragment"];
            pipeline.colorAttachments[0].pixelFormat = layer_.pixelFormat;
            picture_pipeline_ = [device_ newRenderPipelineStateWithDescriptor:pipeline error:&failure];
            if (picture_pipeline_ == nil) {
                error = std::string("the shell's pipeline cannot be made: ") +
                        (failure != nil ? failure.localizedDescription.UTF8String : "no message");
                return false;
            }
            MTLSamplerDescriptor *sampler = [MTLSamplerDescriptor new];
            sampler.sAddressMode = MTLSamplerAddressModeClampToEdge;
            sampler.tAddressMode = MTLSamplerAddressModeClampToEdge;
            sampler.minFilter = MTLSamplerMinMagFilterNearest;
            sampler.magFilter = MTLSamplerMinMagFilterNearest;
            nearest_ = [device_ newSamplerStateWithDescriptor:sampler];
            sampler.minFilter = MTLSamplerMinMagFilterLinear;
            sampler.magFilter = MTLSamplerMinMagFilterLinear;
            linear_ = [device_ newSamplerStateWithDescriptor:sampler];

            // ImGui's Metal backend builds its pipeline for the attachments a render pass descriptor names
            // (ImGui_ImplMetal_NewFrame), which must be those of the drawable's pass it is later drawn in: one
            // colour attachment in the layer's format, no depth or stencil. A 1x1 texture of that format stands
            // in for the drawable, which is only taken at the present.
            MTLTextureDescriptor *probe = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:layer_.pixelFormat
                                                                                             width:1
                                                                                            height:1
                                                                                         mipmapped:NO];
            probe.usage = MTLTextureUsageRenderTarget;
            probe.storageMode = MTLStorageModePrivate;
            ui_pass_ = [MTLRenderPassDescriptor renderPassDescriptor];
            ui_pass_.colorAttachments[0].texture = [device_ newTextureWithDescriptor:probe];

            update_display_info();
            // The Performance row's overlay at start-up; the menu and F3 change it afterwards.
            overlay_visible_ = pk::perf::options().overlay;
            ready_ = true;
            std::cout << "[shell] metal: " << device_.name.UTF8String << ", window " << window_size() << ", "
                      << (layer_.displaySyncEnabled ? "vsync" : "no vsync") << std::endl;
            return true;
        }
    }

    // The destructor's (host::Shell has no shutdown: nothing calls one through it).
    void shutdown() {
        @autoreleasepool {
            wait_idle();
            if (ui_ready_ && ImGui::GetCurrentContext() != nullptr) shutdown_ui();
            ui_ready_ = false;
            if (input_.gamepad != nullptr) {
                SDL_CloseGamepad(input_.gamepad);
                input_.gamepad = nullptr;
            }
            ready_ = false;
            last_game_ = nil;
            held_ = nil;
            upload_ = nil;
            capture_buffer_ = nil;
            for (std::size_t slot = 0; slot < kOverlaySlots; ++slot) {
                overlay_textures_[slot] = nil;
                overlay_users_[slot] = nil;
            }
            ui_pass_ = nil;
            picture_pipeline_ = nil;
            nearest_ = nil;
            linear_ = nil;
            last_commands_ = nil;
            queue_ = nil;
            layer_ = nil;
            device_ = nil;
            if (view_ != nullptr) {
                SDL_Metal_DestroyView(view_);
                view_ = nullptr;
            }
            if (window_ != nullptr) {
                SDL_DestroyWindow(window_);
                window_ = nullptr;
            }
        }
    }

    bool available() const noexcept override { return ready_; }
    bool has_window() const noexcept override { return window_ != nullptr; }

    // ---------------------------------------------------------------------------------------------------------------
    // Events and input

    bool pump_events() override {
        if (window_ == nullptr) return false;
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            // Closing the window is the only way out; Esc is the interface's (the in-game menu).
            if (event.type == SDL_EVENT_QUIT || event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) quit_ = true;
            if (event.type == SDL_EVENT_GAMEPAD_ADDED) input_.open_gamepad(event.gdevice.which);
            if (event.type == SDL_EVENT_GAMEPAD_REMOVED) input_.close_gamepad(event.gdevice.which);
            // A resize, full screen and back, a move to a display of another density: the drawable follows.
            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED || event.type == SDL_EVENT_WINDOW_DISPLAY_CHANGED) {
                update_drawable_size();
                update_display_info();
            }
            // The mouse, while captured for the game; releases always count. With scripted input on, only the
            // script's mouse reaches the game. Touches arrive as mouse events too and never reach it.
            if (event.type == SDL_EVENT_MOUSE_MOTION && mouse_captured_ && event.motion.which != SDL_TOUCH_MOUSEID &&
                (!scripted_input_ || event.motion.which == ph::kScriptedMouse)) {
                mouse_motion_.x += event.motion.xrel;
                mouse_motion_.y += event.motion.yrel;
            }
            if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN && mouse_captured_ && event.button.button < 32u &&
                event.button.which != SDL_TOUCH_MOUSEID &&
                (!scripted_input_ || event.button.which == ph::kScriptedMouse))
                mouse_buttons_ |= 1u << event.button.button;
            if (event.type == SDL_EVENT_MOUSE_BUTTON_UP && event.button.button < 32u)
                mouse_buttons_ &= ~(1u << event.button.button);
            if (event_hook_ && event_hook_(event)) continue;
            // F3 shows or hides the performance overlay, as in the Vulkan renderer's pump; no pad combination.
            if (event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_F3 && !event.key.repeat)
                overlay_visible_ = !overlay_visible_;
        }
        // Only sampled while the window has focus: a key still down when focus is lost stays down in SDL's
        // snapshot, which the guest would see as held for ever.
        const bool focused = (SDL_GetWindowFlags(window_) & SDL_WINDOW_INPUT_FOCUS) != 0u;
        update_pointer(focused);
        sample(focused);
        return !quit_;
    }

    void sample_pad() override {
        if (window_ == nullptr) return;
        // New input from the devices without handling window events, which wait for the next pump_events().
        SDL_PumpEvents();
        sample((SDL_GetWindowFlags(window_) & SDL_WINDOW_INPUT_FOCUS) != 0u);
    }

    ph::PadState pad() const noexcept override { return input_.pad; }
    ph::MouseMotion take_mouse_motion() noexcept override { return std::exchange(mouse_motion_, ph::MouseMotion{}); }
    ph::MouseMotion take_touch_motion() noexcept override { return {}; }
    bool take_touch_menu() noexcept override { return false; }
    bool touch_controls_visible() const noexcept override { return false; }
    const pk::input::touch::Controls &touch_controls() const override {
        static const pk::input::touch::Controls none;
        return none;
    }
    void set_game_input(bool enabled) override {
        // Buttons held when the game gets its input back stay hidden from it until released.
        if (enabled && !input_.game_input) input_.suppress_held = true;
        input_.game_input = enabled;
    }
    void set_pointer_free(bool free) override { pointer_free_ = free; }
    void set_scripted_key(int position, bool down) override {
        if (position > 0 && position < static_cast<int>(pk::input::kKeyPositions))
            input_.scripted_keys[static_cast<std::size_t>(position)] = down;
    }
    void set_scripted_input(bool scripted) override { scripted_input_ = scripted; }
    void set_event_hook(std::function<bool(const SDL_Event &)> hook) override { event_hook_ = std::move(hook); }
    SDL_Gamepad *gamepad() const noexcept override { return input_.gamepad; }
    SDL_Window *window() const noexcept override { return window_; }

    // ---------------------------------------------------------------------------------------------------------------
    // Presenting

    bool present(const pk::gpu::PresentedImage &image, std::uint32_t,
                 std::optional<Clock::time_point> moment) override {
        if (!ready_) return false;
        @autoreleasepool {
            // The frame trace (task 033): this present's part of the flip the backend just handed over.
            Trace trace{};
            trace.on = pure::metal::trace_on();
            if (trace.on) {
                trace.flip = pure::metal::trace_current_flip();
                trace.entered = Clock::now();
                trace.entered_media = CACurrentMediaTime();
            }
            id<MTLTexture> game = nil;
            if (image.api == pk::gpu::ImageApi::Metal && image.image != 0u)
                game = (__bridge id<MTLTexture>)reinterpret_cast<void *>(image.image);
            else if (image.api == pk::gpu::ImageApi::Cpu && image.pixels != nullptr)
                game = upload(image.pixels, image.width, image.height);
            last_game_ = game;
            ++flips_;
            const Clock::time_point now = Clock::now();
            // A load running faster than real time shows a flip only when the window has not had one for this long,
            // about 30 times a second, so vsync never holds the load back.
            if (fast_forward_ && capture_path_.empty()) {
                if (now - fast_forward_shown_ < pk::gpu::kFastForwardPresentInterval) {
                    ui_draw_data_ = nullptr;
                    report(trace, false);
                    return false;
                }
                fast_forward_shown_ = now;
            }
            // The frame's moment is known only while the game is held to real time; then its pictures are paced.
            const bool shown =
                draw(holding_ ? held_ : game, kBlack, true, trace.on ? &trace : nullptr, present_time(moment));
            report(trace, shown);
            if (shown) {
                presents_.push_back(now);
                while (!presents_.empty() && now - presents_.front() > std::chrono::seconds(1)) presents_.pop_front();
            }
            return shown;
        }
    }

    // No frame interpolation in this shell: every flip is presented as it comes.
    void present_due() override {}
    void present_until(Clock::time_point) override {}
    void pause_interpolation() override {}

    void set_fast_forward(bool on) override {
        if (fast_forward_ == on) return;
        fast_forward_ = on;
        // The first flip of a fast stretch is shown.
        fast_forward_shown_ = {};
    }

    void hold_frame(bool hold) override {
        if (!ready_ || hold == holding_) return;
        if (!hold) {
            holding_ = false;
            held_ = nil;
            return;
        }
        if (last_game_ == nil) return;
        @autoreleasepool {
            // A copy of the picture on screen, which the game may draw over while the hold lasts.
            MTLTextureDescriptor *descriptor =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:last_game_.pixelFormat
                                                                   width:last_game_.width
                                                                  height:last_game_.height
                                                               mipmapped:NO];
            descriptor.usage = MTLTextureUsageShaderRead;
            descriptor.storageMode = MTLStorageModePrivate;
            held_ = [device_ newTextureWithDescriptor:descriptor];
            id<MTLCommandBuffer> commands = [queue_ commandBuffer];
            id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
            [blit copyFromTexture:last_game_ toTexture:held_];
            [blit endEncoding];
            [commands commit];
            last_commands_ = commands;
            holding_ = true;
        }
    }

    void capture_window(const std::string &path) override {
        if (ready_) capture_path_ = path;
    }

    // The shape the game's 3D view should have: 480/272, or under Fill the shape of the screen-wide targets the
    // backend draws the next frame into (task 086; metal_device.hpp's view_size, which the Metal backend sets at each
    // flip before this is asked, and the hook of task 084 reads at each flip).
    float game_aspect() const noexcept override {
        if (aspect_ == pk::settings::Aspect::Fill) {
            std::uint32_t width = 0u, height = 0u;
            pure::metal::view_size(width, height);
            if (width != 0u && height != 0u) return static_cast<float>(width) / static_cast<float>(height);
        }
        return static_cast<float>(kPspWidth) / static_cast<float>(kPspHeight);
    }
    float display_refresh() const noexcept override { return display_hz_; }
    double frame_rate_now() const noexcept override { return static_cast<double>(presents_.size()); }
    // The game's own rate: there is no interpolation to add presents.
    void set_frame_rate(pk::settings::FrameRate) override {}
    void set_frame_rate_auto(bool) override {}

    void set_window_scale(std::uint32_t scale) override {
        if (window_ == nullptr || (SDL_GetWindowFlags(window_) & SDL_WINDOW_FULLSCREEN) != 0u) return;
        scale = std::clamp<std::uint32_t>(scale, 1u, pk::settings::kMaxWindowScale);
        SDL_SetWindowSize(window_, static_cast<int>(kPspWidth * scale), static_cast<int>(kPspHeight * scale));
    }
    void set_fullscreen(bool fullscreen) override {
        if (window_ != nullptr) SDL_SetWindowFullscreen(window_, fullscreen);
    }
    void set_present_mode(pk::settings::PresentMode mode) override {
        present_mode_ = mode;
        if (layer_ != nil) layer_.displaySyncEnabled = mode != pk::settings::PresentMode::Immediate;
        update_display_info();
    }
    // A CAMetalLayer waits for the display or does not; there is no mailbox.
    bool supports_present_mode(pk::settings::PresentMode mode) const override {
        return mode != pk::settings::PresentMode::Mailbox;
    }
    // Original, Stretch or Fill (task 086): under Fill the Metal backend draws at the drawable's shape from its next
    // frame (metal_device.hpp's set_fill) and the game is told that shape; for a game that cannot widen its view, Fill
    // is drawn as Original (GameProfile::view_aspect_frame, the Vulkan renderer's rule).
    void set_aspect(pk::settings::Aspect aspect) override {
        aspect_ = pk::gpu::VulkanRenderer::usable_aspect(aspect);
        pure::metal::set_fill(aspect_ == pk::settings::Aspect::Fill);
    }
    void set_sharp_screen(bool sharp) override { sharp_ = sharp; }
    void set_perf_overlay(bool visible) override { overlay_visible_ = visible; }
    std::string device_name() const override { return device_ != nil ? std::string(device_.name.UTF8String) : std::string{}; }
    // What the menu offers of this shell (patch 0016-menu-rows-by-capability): it leaves out the Frame rate and Lower
    // when behind rows (no interpolation) and the Touch screen rows (no touch controls), and says "Metal on <device>".
    // Every aspect: Fill since task 086 (the menu offers it only to a game that widens its view). The Performance row
    // and the F3 line since task 090 (the overlay, draw_overlay()).
    bool supports_frame_interpolation() const noexcept override { return false; }
    bool supports_perf_overlay() const noexcept override { return true; }
    bool supports_aspect(pk::settings::Aspect) const noexcept override { return true; }
    bool supports_touch() const noexcept override { return false; }
    std::string api_name() const override { return "Metal"; }

    // ---------------------------------------------------------------------------------------------------------------
    // Interface

    bool initialize_ui(std::string &error) override {
        if (!ready_) {
            error = "the Metal shell has no window";
            return false;
        }
        if (ui_ready_) return true;
        if (!ImGui_ImplSDL3_InitForMetal(window_)) {
            error = "ImGui_ImplSDL3_InitForMetal failed";
            return false;
        }
        if (!ImGui_ImplMetal_Init(device_)) {
            ImGui_ImplSDL3_Shutdown();
            error = "ImGui_ImplMetal_Init failed";
            return false;
        }
        ui_ready_ = true;
        return true;
    }

    // shutdown()'s, for the interface's two ImGui backends.
    void shutdown_ui() {
        if (!ui_ready_) return;
        wait_idle();
        ImGui_ImplMetal_Shutdown();
        ImGui_ImplSDL3_Shutdown();
        ui_draw_data_ = nullptr;
        ui_ready_ = false;
    }

    void begin_ui_frame() override {
        if (!ui_ready_) return;
        @autoreleasepool {
            ImGui_ImplMetal_NewFrame(ui_pass_);
        }
    }

    void set_ui_draw_data(ImDrawData *draw_data) override { ui_draw_data_ = draw_data; }

    void present_ui(bool show_game) override {
        if (!ready_) return;
        @autoreleasepool {
            id<MTLTexture> game = show_game ? (holding_ ? held_ : last_game_) : nil;
            draw(game, game != nil ? kBlack : kBackground, false);
        }
    }

private:
    static constexpr double kBlack[3] = {0.0, 0.0, 0.0};

    // A present's part in the frame trace (PURE_METAL_TRACE): the flip it shows, when present() began (both clocks),
    // and the time draw() waited for a drawable.
    struct Trace {
        bool on{};
        std::uint64_t flip{};
        Clock::time_point entered{};
        double entered_media{};
        double drawable_ms{};
    };

    // Hands the trace this present's CPU time, and, for a flip not shown (a skipped fast-forward flip, no drawable),
    // that its picture never reached the screen.
    void report(const Trace &trace, bool shown) const {
        if (!trace.on) return;
        pure::metal::trace_shell_present(std::chrono::duration<double, std::milli>(Clock::now() - trace.entered).count(),
                                         trace.drawable_ms, (SDL_GetWindowFlags(window_) & SDL_WINDOW_OCCLUDED) != 0u);
        if (!shown) pure::metal::trace_presented(trace.flip, 0.0, 0.0);
    }

    void sample(bool focused) {
        input_.sample(focused, mouse_captured_, mouse_buttons_, nullptr, flips_);
    }

    // Captures the pointer for the game when everything allows it and frees it otherwise, as the Vulkan renderer
    // does. Whatever the mouse did or held across a change is dropped.
    void update_pointer(bool focused) {
        const bool minimized = (SDL_GetWindowFlags(window_) & SDL_WINDOW_MINIMIZED) != 0u;
        const bool wanted = pk::settings::current().mouse && input_.game_input && !pointer_free_ && !minimized &&
                            (focused || scripted_input_);
        if (wanted == mouse_captured_) return;
        mouse_captured_ = wanted;
        // A scripted run never takes the real pointer from the person at the machine.
        if (!scripted_input_) SDL_SetWindowRelativeMouseMode(window_, wanted);
        if (ph::pad_tuning().trace) std::cout << "[pad] pointer " << (wanted ? "captured" : "free") << std::endl;
        mouse_buttons_ = 0u;
        mouse_motion_ = {};
        if (wanted) input_.suppress_held = true;
    }

    // The layer's drawable as the window's size in pixels, and its contents scale as the window's pixel density, so
    // that the drawable maps 1:1 onto the display's pixels (task 065). A new size after start-up is logged once.
    void update_drawable_size() {
        if (window_ == nullptr || layer_ == nil) return;
        int width = 0;
        int height = 0;
        if (!SDL_GetWindowSizeInPixels(window_, &width, &height) || width <= 0 || height <= 0) return;
        if (const float density = SDL_GetWindowPixelDensity(window_); density > 0.0f) layer_.contentsScale = density;
        const CGSize size = CGSizeMake(width, height);
        if (!CGSizeEqualToSize(layer_.drawableSize, size)) layer_.drawableSize = size;
        // The Metal backend, made after the shell, reads it for its Auto internal scale (task 066).
        pure::metal::set_drawable_size(static_cast<std::uint32_t>(width), static_cast<std::uint32_t>(height));
        if (ready_ && !CGSizeEqualToSize(logged_size_, size))
            std::cout << "[shell] metal: window " << window_size() << std::endl;
        logged_size_ = size;
    }

    // "960x544 points, 1920x1088 pixels, 2x": the window's size, its drawable's, and the pixel density.
    std::string window_size() const {
        int width = 0;
        int height = 0;
        SDL_GetWindowSize(window_, &width, &height);
        const CGSize pixels = layer_.drawableSize;
        std::ostringstream text;
        text << width << "x" << height << " points, " << static_cast<int>(pixels.width) << "x"
             << static_cast<int>(pixels.height) << " pixels, " << SDL_GetWindowPixelDensity(window_) << "x";
        return text.str();
    }

    void update_display_info() {
        float refresh = 0.0f;
        if (window_ != nullptr) {
            if (const SDL_DisplayID display = SDL_GetDisplayForWindow(window_); display != 0u) {
                if (const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode(display); mode != nullptr)
                    refresh = mode->refresh_rate;
            }
        }
        display_hz_ = refresh;
        const CGSize size = layer_ != nil ? layer_.drawableSize : CGSizeZero;
        pk::perf::set_display_info(present_mode_ == pk::settings::PresentMode::Immediate ? "IMMEDIATE" : "FIFO",
                                   static_cast<std::uint32_t>(size.width), static_cast<std::uint32_t>(size.height),
                                   refresh);
    }

    // A CPU picture (rows of `width` RGBA pixels) as a texture the next draw samples.
    id<MTLTexture> upload(const std::uint8_t *pixels, std::uint32_t width, std::uint32_t height) {
        if (width == 0u || height == 0u) return nil;
        if (upload_ == nil || upload_.width != width || upload_.height != height) {
            MTLTextureDescriptor *descriptor =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                   width:width
                                                                  height:height
                                                               mipmapped:NO];
            descriptor.usage = MTLTextureUsageShaderRead;
            descriptor.storageMode = MTLStorageModeManaged;
            upload_ = [device_ newTextureWithDescriptor:descriptor];
        } else {
            // The frame before may still be sampling it. Only a backend that draws on the CPU comes here.
            wait_idle();
        }
        [upload_ replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:pixels
                   bytesPerRow:static_cast<NSUInteger>(width) * 4u];
        return upload_;
    }

    // Where the picture goes in a drawable of `width` x `height` pixels: the PSP's shape, as large as fits and
    // centred (Original), or the whole drawable (Stretch, and Fill, whose target has the drawable's shape already:
    // task 086). The Vulkan renderer's record_game_blit, to the pixel.
    MTLViewport viewport_for(std::int32_t width, std::int32_t height) const {
        std::int32_t shown_width = width;
        std::int32_t shown_height = height;
        if (aspect_ == pk::settings::Aspect::Original) {
            const double scale = std::min(static_cast<double>(width) / kPspWidth, static_cast<double>(height) / kPspHeight);
            shown_width = std::clamp(static_cast<std::int32_t>(std::lround(kPspWidth * scale)), 1, width);
            shown_height = std::clamp(static_cast<std::int32_t>(std::lround(kPspHeight * scale)), 1, height);
        }
        MTLViewport viewport{};
        viewport.originX = static_cast<double>((width - shown_width) / 2);
        viewport.originY = static_cast<double>((height - shown_height) / 2);
        viewport.width = static_cast<double>(shown_width);
        viewport.height = static_cast<double>(shown_height);
        viewport.znear = 0.0;
        viewport.zfar = 1.0;
        return viewport;
    }

    // Nearest when the sharp-screen setting asks for it, and whenever the picture is shown at a whole multiple of
    // its own size, where each of its pixels covers whole pixels of the window: linear filtering would only blend
    // neighbours there. That is how the Vulkan shell shows a frame at its default settings (its 2x target copied
    // 1:1 into the 2x window), and it gives the frame regression suite the backend's pixels back exactly. The
    // viewport is in the drawable's pixels: the default 960x544-point window on a 2x display is 1920x1088, a whole
    // 4x of a 480x272 picture.
    id<MTLSamplerState> sampler_for(id<MTLTexture> picture, const MTLViewport &viewport) const {
        if (sharp_) return nearest_;
        const auto width = static_cast<std::uint64_t>(viewport.width);
        const auto height = static_cast<std::uint64_t>(viewport.height);
        const bool whole = picture.width != 0u && picture.height != 0u && width % picture.width == 0u &&
                           height % picture.height == 0u && width / picture.width == height / picture.height;
        return whole ? nearest_ : linear_;
    }

    // When a game picture is to reach the screen, in CACurrentMediaTime's seconds, or 0 for as soon as it can.
    //
    // The game flips at its vblank's rate (the PSP's 59.94 Hz, or the display's refresh under the Display rate row:
    // the kernel's period, task 089), held to real time by the kernel's sleeps, which wake a millisecond or two
    // early or late. Shown at the first refresh after its flip, on a 120 Hz display a picture whose flip's phase lies
    // near a refresh boundary alternately catches and misses it: one stays three refreshes (25 ms), the next one
    // (8.3 ms). The trace of a race counted that for 9% of its pictures (task 033, docs/metal-backend.md "Frame
    // times"). The PSP shows a frame at the vblank after the one the frame began from (sceDisplaySetFrameBuf's next
    // frame), so each picture is asked for at that vblank's real time: the frame's moment (the real time of the vblank
    // it began from, which the HLE passes while emulated time is held to real time) plus one vblank of the kernel's
    // period (emulated time is real time while it is held). Those times carry no host jitter. Without a moment (a load running fast, an unpaced run), without vsync, or when the time
    // has passed, the picture is shown at once.
    double present_time(const std::optional<Clock::time_point> &moment) const {
        if (!moment || fast_forward_ || !pace_pictures_ || layer_ == nil || !layer_.displaySyncEnabled) return 0.0;
        const auto vblank = std::chrono::microseconds(pk::kernel().vblank_period_us());
        const Clock::time_point due = *moment + vblank;
        const double ahead = std::chrono::duration<double>(due - Clock::now()).count();
        // Late, or further ahead than a frame and a half: shown at once.
        if (ahead <= 0.0 || ahead > 1.5 * std::chrono::duration<double>(vblank).count()) return 0.0;
        return CACurrentMediaTime() + ahead;
    }

    // One present: `picture` letterboxed over `clear` (or `clear` alone without one), on a `game_frame` (a flip's
    // present, not the interface's present_ui) the performance overlay when it is shown, the interface over them, a
    // window capture when one is pending, then presentDrawable and commit. False when there was no drawable. With `at`
    // above 0 the drawable is shown at that time (CACurrentMediaTime's seconds), else as soon as it can be. With
    // `trace`, the wait for the drawable is timed and the drawable's presented handler reports when it reached the
    // screen.
    bool draw(id<MTLTexture> picture, const double (&clear)[3], bool game_frame, Trace *trace = nullptr,
              double at = 0.0) {
        ImDrawData *ui = ui_ready_ ? ui_draw_data_ : nullptr;
        ui_draw_data_ = nullptr;
        const Clock::time_point asked = trace != nullptr ? Clock::now() : Clock::time_point{};
        id<CAMetalDrawable> drawable = [layer_ nextDrawable];
        if (trace != nullptr) {
            trace->drawable_ms = std::chrono::duration<double, std::milli>(Clock::now() - asked).count();
            if (drawable != nil) {
                const std::uint64_t flip = trace->flip;
                const double entered = trace->entered_media;
                [drawable addPresentedHandler:^(id<MTLDrawable> shown) {
                    const double when = shown.presentedTime;
                    pure::metal::trace_presented(flip, when, when > 0.0 ? (when - entered) * 1000.0 : 0.0);
                }];
            }
        }
        if (drawable == nil) return false;
        id<MTLTexture> target = drawable.texture;
        id<MTLCommandBuffer> commands = [queue_ commandBuffer];
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(clear[0], clear[1], clear[2], 1.0);
        id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
        if (picture != nil) {
            const MTLViewport viewport =
                viewport_for(static_cast<std::int32_t>(target.width), static_cast<std::int32_t>(target.height));
            [encoder setViewport:viewport];
            [encoder setRenderPipelineState:picture_pipeline_];
            [encoder setFragmentTexture:picture atIndex:0];
            [encoder setFragmentSamplerState:sampler_for(picture, viewport) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            if (game_frame && overlay_visible_) {
                const Clock::time_point overlay_start = Clock::now();
                draw_overlay(encoder, commands, static_cast<std::uint32_t>(target.width),
                             static_cast<std::uint32_t>(target.height));
                pk::perf::add_overlay_time(Clock::now() - overlay_start);
            }
        }
        if (ui != nullptr && ui->CmdListsCount > 0) {
            // ImGui sets its own viewport (the whole window) and scissors.
            ImGui_ImplMetal_RenderDrawData(ui, commands, encoder);
        }
        [encoder endEncoding];
        std::string capture;
        if (!capture_path_.empty()) {
            capture = std::exchange(capture_path_, std::string{});
            const NSUInteger bytes = target.width * target.height * 4u;
            if (capture_buffer_ == nil || capture_buffer_.length < bytes)
                capture_buffer_ = [device_ newBufferWithLength:bytes options:MTLResourceStorageModeShared];
            id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
            [blit copyFromTexture:target
                             sourceSlice:0
                             sourceLevel:0
                            sourceOrigin:MTLOriginMake(0, 0, 0)
                              sourceSize:MTLSizeMake(target.width, target.height, 1)
                                toBuffer:capture_buffer_
                       destinationOffset:0
                  destinationBytesPerRow:target.width * 4u
                destinationBytesPerImage:bytes];
            [blit endEncoding];
        }
        if (at > 0.0) [commands presentDrawable:drawable atTime:at];
        else [commands presentDrawable:drawable];
        [commands commit];
        last_commands_ = commands;
        if (!capture.empty()) write_capture(commands, capture, static_cast<std::uint32_t>(target.width),
                                            static_cast<std::uint32_t>(target.height));
        return true;
    }

    // The performance overlay (task 090), as the Vulkan renderer's record_overlay draws it over its window: the
    // framework's 196x72 image of the last second's numbers and the recent frame times (perf::draw_overlay, red in the
    // low byte, so an RGBA8Unorm texture reads it as is), scaled by perf::overlay_scale of the drawable's height into
    // the drawable's top-left corner, inset 4 x scale, with the picture's pipeline and the nearest sampler: opaque,
    // each of its pixels scale x scale of the drawable's. Not drawn when the drawable is too small to hold it. The
    // texture written is the slot after the last one drawn, and the present that last sampled it has finished first
    // (kOverlaySlots).
    void draw_overlay(id<MTLRenderCommandEncoder> encoder, id<MTLCommandBuffer> commands, std::uint32_t width,
                      std::uint32_t height) {
        const std::uint32_t scale = pk::perf::overlay_scale(height);
        const std::uint32_t inset = 4u * scale;
        const std::uint32_t shown_width = pk::perf::kOverlayWidth * scale;
        const std::uint32_t shown_height = pk::perf::kOverlayHeight * scale;
        if (inset + shown_width > width || inset + shown_height > height) return;
        overlay_slot_ = (overlay_slot_ + 1u) % kOverlaySlots;
        if (overlay_textures_[overlay_slot_] == nil) {
            MTLTextureDescriptor *descriptor =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                   width:pk::perf::kOverlayWidth
                                                                  height:pk::perf::kOverlayHeight
                                                               mipmapped:NO];
            descriptor.usage = MTLTextureUsageShaderRead;
            descriptor.storageMode = MTLStorageModeShared;
            overlay_textures_[overlay_slot_] = [device_ newTextureWithDescriptor:descriptor];
            if (overlay_textures_[overlay_slot_] == nil) return;
        }
        id<MTLTexture> texture = overlay_textures_[overlay_slot_];
        if (overlay_users_[overlay_slot_] != nil) [overlay_users_[overlay_slot_] waitUntilCompleted];
        overlay_pixels_.resize(static_cast<std::size_t>(pk::perf::kOverlayWidth) * pk::perf::kOverlayHeight);
        pk::perf::draw_overlay(overlay_pixels_.data());
        [texture replaceRegion:MTLRegionMake2D(0, 0, pk::perf::kOverlayWidth, pk::perf::kOverlayHeight)
                   mipmapLevel:0
                     withBytes:overlay_pixels_.data()
                   bytesPerRow:static_cast<NSUInteger>(pk::perf::kOverlayWidth) * 4u];
        overlay_users_[overlay_slot_] = commands;
        MTLViewport viewport{};
        viewport.originX = static_cast<double>(inset);
        viewport.originY = static_cast<double>(inset);
        viewport.width = static_cast<double>(shown_width);
        viewport.height = static_cast<double>(shown_height);
        viewport.znear = 0.0;
        viewport.zfar = 1.0;
        [encoder setViewport:viewport];
        [encoder setFragmentTexture:texture atIndex:0];
        [encoder setFragmentSamplerState:nearest_ atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }

    // The drawable read back by draw(): BGRA, as the layer holds it, written as the RGBA BMP every capture is.
    void write_capture(id<MTLCommandBuffer> commands, const std::string &path, std::uint32_t width,
                       std::uint32_t height) {
        [commands waitUntilCompleted];
        if (commands.status == MTLCommandBufferStatusError) {
            std::cout << "[render] cannot capture the window to " << path << " (the frame failed on the GPU)" << std::endl;
            return;
        }
        const auto *bgra = static_cast<const std::uint8_t *>(capture_buffer_.contents);
        std::vector<std::uint8_t> rgba(static_cast<std::size_t>(width) * height * 4u);
        for (std::size_t i = 0; i < rgba.size(); i += 4u) {
            rgba[i] = bgra[i + 2u];
            rgba[i + 1u] = bgra[i + 1u];
            rgba[i + 2u] = bgra[i];
            rgba[i + 3u] = 255u;
        }
        if (pk::gpu::write_bmp(path, rgba.data(), width, height))
            std::cout << "[render] window " << width << "x" << height << " -> " << path << std::endl;
        else
            std::cout << "[render] cannot write " << path << std::endl;
    }

    // Waits for the last command buffer committed; Metal runs one queue's buffers in order.
    void wait_idle() {
        if (last_commands_ != nil) [last_commands_ waitUntilCompleted];
    }

    bool ready_{};
    bool quit_{};
    SDL_Window *window_{};
    SDL_MetalView view_{};
    CAMetalLayer *layer_{};
    id<MTLDevice> device_{};
    id<MTLCommandQueue> queue_{};
    id<MTLRenderPipelineState> picture_pipeline_{};
    id<MTLSamplerState> nearest_{};
    id<MTLSamplerState> linear_{};
    id<MTLCommandBuffer> last_commands_{};

    // The pad, the gamepad and the input script's keys, shared with the Vulkan shell.
    ph::SdlPad input_;
    std::function<bool(const SDL_Event &)> event_hook_;
    bool mouse_captured_{};
    bool pointer_free_{};
    bool scripted_input_{};
    std::uint32_t mouse_buttons_{};
    ph::MouseMotion mouse_motion_{};

    // The last game picture presented (shown again behind a paused menu), the copy a hold keeps, and the texture
    // a Cpu picture is uploaded to.
    id<MTLTexture> last_game_{};
    id<MTLTexture> held_{};
    bool holding_{};
    id<MTLTexture> upload_{};
    std::uint64_t flips_{};
    bool fast_forward_{};
    Clock::time_point fast_forward_shown_{};
    std::deque<Clock::time_point> presents_;  // the last second's, for frame_rate_now()

    CGSize logged_size_{};  // the drawable's size the log last named
    pk::settings::PresentMode present_mode_{pk::settings::PresentMode::Fifo};
    pk::settings::Aspect aspect_{pk::settings::Aspect::Original};
    bool sharp_{};
    float display_hz_{};
    // PURE_METAL_PACE=0 shows every picture as soon as it can be, as before task 033.
    bool pace_pictures_{env_on("METAL_PACE", true)};

    std::string capture_path_;
    id<MTLBuffer> capture_buffer_{};

    // The performance overlay (draw_overlay): shown or not (the Performance row, F3), the CPU image, and its textures
    // with the present that last sampled each.
    bool overlay_visible_{};
    std::vector<std::uint32_t> overlay_pixels_;
    std::size_t overlay_slot_{};
    id<MTLTexture> overlay_textures_[kOverlaySlots]{};
    id<MTLCommandBuffer> overlay_users_[kOverlaySlots]{};

    bool ui_ready_{};
    MTLRenderPassDescriptor *ui_pass_{};
    ImDrawData *ui_draw_data_{};
};

const ph::ShellRegistration registration("metal", "an SDL window drawn with Metal; the Metal backend's picture shown directly",
                                         [] { return std::unique_ptr<ph::Shell>(new MetalShell()); });

} // namespace
} // namespace pure::host
