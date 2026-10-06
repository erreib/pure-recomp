// The Metal shell: PURE_SHELL=metal (docs/metal-backend.md, "The Metal shell").
//
// A host::Shell (vendor/portablekit/host/shell/shell.hpp, docs/ge-backend.md section 8) in our own sources, so its
// registration below is linked into the program directly, as the Metal GE backend's is. With PURE_GE_BACKEND=metal
// the game runs with no Vulkan or MoltenVK at all:
//
//   window     an SDL window (SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE) with SDL's Metal view, whose CAMetalLayer
//              draws with the program's one Metal device and command queue (src/gpu/metal_device.hpp), the ones
//              the Metal backend draws with: its textures are ours to sample, and our presents are ordered after
//              its frames.
//   input      the window's events as the Vulkan renderer's pump handles them (close, gamepads coming and going,
//              the captured mouse, the interface's event hook); the pad from host::SdlPad, which the Vulkan
//              shell shares, so the keyboard, the gamepad, the input script's keys and its virtual gamepad reach
//              the game the same way in both. No touch controls.
//   present    the GE backend's image into the layer's next drawable, letterboxed to 480:272 (or stretched),
//              nearest or linear (the sharp-screen setting; nearest whenever the picture is an exact multiple of
//              480x272, see sampler_for()); a Metal image is sampled where the backend left it, a Cpu image is
//              uploaded first, no image clears to black. The interface over it, then presentDrawable and commit.
//              Vsync is the layer's displaySyncEnabled. No frame interpolation: present_due and present_until do
//              nothing.
//   captures   capture_window: the next presented drawable, interface included, read back as a BMP.
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
#include "shell/sdl_pad.hpp"
#include "shell/shell.hpp"

#include "gpu/ge_backend.hpp"
#include "perf/frame_stats.hpp"
#include "portablekit_build_label.hpp"
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
#include <cstring>
#include <deque>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
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
// A load running faster than real time shows a flip only when the window has not had one for this long, about 30
// times a second (the Vulkan renderer's kFastForwardPresentInterval), so vsync never holds the load back.
constexpr auto kFastForwardInterval = std::chrono::milliseconds(33);
// Behind the setup screens, as in the Vulkan shell: the dark brown of the project's logo.
constexpr double kBackground[3] = {0.075, 0.055, 0.045};

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

// The window's title when ShellConfig has none: the program's name and the build label, as the Vulkan shell's
// gpu::default_window_title() makes it.
std::string default_title() {
    std::string title = pk::game().app_name;
    if (*pk::kBuildLabel != '\0') title += std::string(" (") + pk::kBuildLabel + ")";
    return title;
}

class MetalShell final : public ph::Shell {
public:
    ~MetalShell() override { shutdown(); }

    const char *name() const noexcept override { return "metal"; }

    bool initialize(const ph::ShellConfig &config, std::string &error) override {
        @autoreleasepool {
            const pk::settings::Settings &player = pk::settings::current();
            present_mode_ = player.present_mode;
            aspect_ = player.aspect == pk::settings::Aspect::Stretch ? pk::settings::Aspect::Stretch
                                                                     : pk::settings::Aspect::Original;
            sharp_ = player.sharp_screen;

            if (!SDL_Init(SDL_INIT_VIDEO)) {
                error = std::string("SDL_Init failed: ") + SDL_GetError();
                return false;
            }
            // A missing gamepad subsystem is not fatal; the keyboard still drives the pad.
            if (!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) std::cout << "[pad] no gamepad support: " << SDL_GetError() << "\n";
            else input_.scan_gamepads();
            SDL_WindowFlags flags = SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE;
            if (player.fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
            const std::uint32_t scale = std::clamp<std::uint32_t>(player.window_scale, 1u, pk::settings::kMaxWindowScale);
            const std::string title = config.title.empty() ? default_title() : config.title;
            window_ = SDL_CreateWindow(title.c_str(), static_cast<int>(kPspWidth * scale),
                                       static_cast<int>(kPspHeight * scale), flags);
            if (window_ == nullptr) {
                error = std::string("SDL_CreateWindow failed: ") + SDL_GetError();
                return false;
            }
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
            ready_ = true;
            const CGSize size = layer_.drawableSize;
            std::cout << "[shell] metal: " << device_.name.UTF8String << ", window "
                      << static_cast<int>(size.width) << "x" << static_cast<int>(size.height) << ", "
                      << (layer_.displaySyncEnabled ? "vsync" : "no vsync") << std::endl;
            return true;
        }
    }

    void shutdown() override {
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
            if (event.type == SDL_EVENT_WINDOW_DISPLAY_CHANGED) update_display_info();
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
    bool mouse_captured() const noexcept override { return mouse_captured_; }
    bool quit_requested() const noexcept override { return quit_; }
    void request_quit() noexcept override { quit_ = true; }
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
                 std::optional<Clock::time_point>) override {
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
            if (fast_forward_ && capture_path_.empty()) {
                if (now - fast_forward_shown_ < kFastForwardInterval) {
                    ui_draw_data_ = nullptr;
                    report(trace, false);
                    return false;
                }
                fast_forward_shown_ = now;
            }
            const bool shown = draw(holding_ ? held_ : game, kBlack, trace.on ? &trace : nullptr);
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

    float game_aspect() const noexcept override {
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
    // Original or Stretch. Fill needs the game to draw a view of the window's shape; this shell keeps the PSP's.
    void set_aspect(pk::settings::Aspect aspect) override {
        aspect_ = aspect == pk::settings::Aspect::Stretch ? pk::settings::Aspect::Stretch : pk::settings::Aspect::Original;
    }
    void set_sharp_screen(bool sharp) override { sharp_ = sharp; }
    void set_perf_overlay(bool) override {}
    std::string device_name() const override { return device_ != nil ? std::string(device_.name.UTF8String) : std::string{}; }

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

    void shutdown_ui() override {
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
            draw(game, game != nil ? kBlack : kBackground);
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
    // centred (Original), or the whole drawable (Stretch). The Vulkan renderer's record_game_blit, to the pixel.
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
    // 1:1 into the 2x window), and it gives the frame regression suite the backend's pixels back exactly.
    id<MTLSamplerState> sampler_for(id<MTLTexture> picture, const MTLViewport &viewport) const {
        if (sharp_) return nearest_;
        const auto width = static_cast<std::uint64_t>(viewport.width);
        const auto height = static_cast<std::uint64_t>(viewport.height);
        const bool whole = picture.width != 0u && picture.height != 0u && width % picture.width == 0u &&
                           height % picture.height == 0u && width / picture.width == height / picture.height;
        return whole ? nearest_ : linear_;
    }

    // One present: `picture` letterboxed over `clear` (or `clear` alone without one), the interface over it, a
    // window capture when one is pending, then presentDrawable and commit. False when there was no drawable.
    // With `trace`, the wait for the drawable is timed and the drawable's presented handler reports when it reached
    // the screen.
    bool draw(id<MTLTexture> picture, const double (&clear)[3], Trace *trace = nullptr) {
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
                    const double at = shown.presentedTime;
                    pure::metal::trace_presented(flip, at, at > 0.0 ? (at - entered) * 1000.0 : 0.0);
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
        [commands presentDrawable:drawable];
        [commands commit];
        last_commands_ = commands;
        if (!capture.empty()) write_capture(commands, capture, static_cast<std::uint32_t>(target.width),
                                            static_cast<std::uint32_t>(target.height));
        return true;
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
        if (pk::gpu::write_bmp_file(path, rgba.data(), width, height))
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

    pk::settings::PresentMode present_mode_{pk::settings::PresentMode::Fifo};
    pk::settings::Aspect aspect_{pk::settings::Aspect::Original};
    bool sharp_{};
    float display_hz_{};

    std::string capture_path_;
    id<MTLBuffer> capture_buffer_{};

    bool ui_ready_{};
    MTLRenderPassDescriptor *ui_pass_{};
    ImDrawData *ui_draw_data_{};
};

const ph::ShellRegistration registration("metal", "an SDL window drawn with Metal; the Metal backend's picture shown directly",
                                         [] { return std::unique_ptr<ph::Shell>(new MetalShell()); });

} // namespace
} // namespace pure::host
