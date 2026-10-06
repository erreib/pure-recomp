// The GE drawn with Metal: PURE_GE_BACKEND=metal (docs/metal-backend.md).
//
// A GeBackend (vendor/portablekit/host/gpu/ge_backend.hpp, docs/ge-backend.md) in our own sources, so its
// registration below is linked into the program directly. Task 023 built what the 2D frontend needs:
//
//   targets    keyed by (colour address, stride, format), each a 480x272 RGBA8 colour texture (5650, 5551
//              and 4444 targets too, for now) and a Depth32Float_Stencil8 texture (internal scale 1,
//              D-002). A pass draws into one target; switching targets ends it.
//   textures   a bind that lies in a target samples that target, the one starting at the address first
//              (patch 0003), while guest memory under it is what it was when the target was first drawn
//              in the frame; anything else is decoded from guest memory with the framework's
//              decode_texture() and cached by its contents (texels and the palette entries it can reach).
//   draws      every primitive, through mode or transformed, through one pipeline whose key holds the
//              blend, the write masks, the alpha test, the depth test and (carried for task 025) the
//              stencil; clears; scissor; the GE viewport folded into clip space.
//   frames     one command buffer a frame, committed at the flip. present_image() names the display
//              target's texture; capture_frame() reads it back synchronously.
//
// Not yet (tasks 024 and 025): lighting, fog, the stencil and the alpha it keeps, block transfers and
// read-backs into guest memory, the depth write-back. Those calls are counted and logged once.
//
// The Vulkan shell still owns the window. Its present shows its own targets, and the input script's
// `shot` steps read its window, so every presented picture is also handed to it (metal_shell.hpp);
// PURE_METAL_SHELL=0 leaves the window black. PURE_METAL_LOG=1 prints a line per draw.
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
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
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
    std::uint32_t unused{};
};
static_assert(sizeof(GpuVertex) == 32u, "GpuVertex must match GeVertex in metal_shaders.h");

struct VertexUniforms {
    std::array<float, 16> transform{};
    std::array<float, 4> screen{};
    std::array<float, 4> uv_transform{1.0f, 1.0f, 0.0f, 0.0f};
    std::array<std::uint32_t, 4> mode{};
};
static_assert(sizeof(VertexUniforms) == 112u, "VertexUniforms must match metal_shaders.h");

struct FragmentUniforms {
    std::array<float, 4> fix{};
    std::array<std::uint32_t, 4> texture{};
    std::array<std::uint32_t, 4> alpha_test{};
};
static_assert(sizeof(FragmentUniforms) == 48u, "FragmentUniforms must match metal_shaders.h");

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
    id<MTLTexture> depth;  // depth and the stencil (task 025)
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
    bool textured{};
    bool alpha_test{};
    auto operator<=>(const RenderKey &) const = default;
};

// The depth-stencil state's part.
struct DepthStencilKey {
    std::uint8_t compare{MTLCompareFunctionAlways};  // MTLCompareFunction
    bool write{};
    // The stencil test and operations as the GE gives them (DrawCall::stencil) and the bits the alpha
    // write mask leaves writable. Carried here so that task 025 turns them into the state's stencil
    // descriptors; this task draws with the stencil attachment untouched.
    bool stencil{};
    std::uint8_t stencil_function{};
    std::uint8_t fail{};
    std::uint8_t depth_fail{};
    std::uint8_t pass{};
    std::uint8_t reference{};
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

struct Stats {
    std::uint64_t draws{};
    std::uint64_t passes{};
    std::uint64_t decoded{};
    std::uint64_t framebuffer_textures{};
    std::uint64_t copies{};
    std::uint64_t uploads{};
    std::uint64_t waits{};
    double wait_ms{};
};

class MetalGeBackend final : public pk::GeBackend {
public:
    ~MetalGeBackend() override { shutdown(); }

    const char *name() const noexcept override { return "metal"; }
    bool needs_window() const noexcept override { return false; }

    bool initialize(const pk::BackendConfig &config, std::string &error) override {
        @autoreleasepool {
            const auto start = std::chrono::steady_clock::now();
            device_ = MTLCreateSystemDefaultDevice();
            if (device_ == nil) {
                error = "there is no Metal device";
                return false;
            }
            queue_ = [device_ newCommandQueue];
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
            for (std::uint32_t variant = 0; variant < 4u; ++variant) {
                MTLFunctionConstantValues *values = [MTLFunctionConstantValues new];
                const bool textured = (variant & 1u) != 0u;
                const bool alpha_test = (variant & 2u) != 0u;
                [values setConstantValue:&textured type:MTLDataTypeBool atIndex:0];
                [values setConstantValue:&alpha_test type:MTLDataTypeBool atIndex:1];
                fragment_functions_[variant] = [library_ newFunctionWithName:@"ge_fragment"
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
            pool_ = std::make_shared<ChunkPool>();

            shell_ = config.vulkan_shell;
            sharp_ = config.sharp_textures;
            const char *shell_switch = portablekit::env("METAL_SHELL");
            to_shell_ = shell_ != nullptr && !(shell_switch != nullptr && std::strcmp(shell_switch, "0") == 0);
            const char *log = portablekit::env("METAL_LOG");
            log_draws_ = log != nullptr && *log != '\0' && std::strcmp(log, "0") != 0;
            no_framebuffer_textures_ = portablekit::env("NO_FB_TEXTURES") != nullptr;
            started_ = std::chrono::steady_clock::now();
            report_start_ = started_;
            ready_ = true;
            const double ms = std::chrono::duration<double, std::milli>(started_ - start).count();
            std::cout << "[metal] drawing with " << device_.name.UTF8String << " at 480x272, shaders compiled in "
                      << ms << " ms; "
                      << (to_shell_ ? "pictures shown in the window"
                                    : (shell_ != nullptr ? "window left black (PURE_METAL_SHELL=0)" : "no window"))
                      << "\n";
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
                      << " framebuffer textures, " << stats_.copies << " target copies, " << stats_.uploads
                      << " uploads, " << targets_.size() << " targets, " << stats_.waits << " GPU waits ("
                      << stats_.wait_ms << " ms) in " << seconds << " s\n"
                      << std::flush;
            // Every target's resources before the device they came from (the contract's order).
            presented_ = nullptr;
            last_drawn_ = nullptr;
            current_target_ = nullptr;
            targets_.clear();
            textures_.clear();
            list_keys_.clear();
            render_pipelines_.clear();
            depth_states_.clear();
            samplers_.fill(nil);
            if (pool_) {
                std::lock_guard<std::mutex> guard(pool_->lock);
                pool_->free.clear();
            }
            chunk_ = nil;
            white_ = nil;
            readback_ = nil;
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
        @autoreleasepool {
            draw(call, memory);
        }
    }

    // Task 025: a rendered source is written to guest memory before the HLE copies it.
    void block_transfer(const pk::BlockTransfer &, GuestMemory &) override {
        deferred("block_transfer", block_transfers_);
    }
    void write_back_frame(GuestMemory &) override { deferred("write_back_frame", frame_write_backs_); }
    void read_back_framebuffer(std::uint32_t, GuestMemory &) override {
        deferred("read_back_framebuffer", read_backs_);
    }
    bool write_back_depth(std::uint32_t, std::uint32_t, std::uint32_t, GuestMemory &, const char *) override {
        deferred("write_back_depth", depth_write_backs_);
        return false;
    }

    void upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                      std::uint32_t height, std::uint32_t stride) override {
        if (!ready_ || pixels == nullptr || width == 0u || height == 0u || stride < width) return;
        @autoreleasepool {
            upload(display_address, pixels, width, height, stride);
        }
    }

    pk::PresentedImage present_image(std::uint32_t display_address) override {
        pk::PresentedImage image;
        if (!ready_) return image;
        @autoreleasepool {
            ++frames_;
            frame_draws_ = 0u;
            Target *shown = latest_target_at(GuestMemory::canonical(display_address));
            if (shown == nullptr) shown = last_drawn_;
            presented_ = shown;
            if (shown != nullptr && to_shell_) {
                read_back(*shown);
                show_in_shell(shell_, display_address, picture_.data(), kWidth, kHeight, shell_scratch_);
            } else {
                commit(false);
            }
            if (frames_ % kReportEvery == 0u) report();
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

    void end_encoder() {
        if (encoder_ != nil) {
            [encoder_ endEncoding];
            encoder_ = nil;
        }
        current_target_ = nullptr;
    }

    // Hands the frame's commands to the GPU; with `wait`, returns once it has drawn them.
    void commit(bool wait) {
        end_encoder();
        if (commands_ == nil) return;
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
            stats_.wait_ms += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            ++stats_.waits;
            check(committed);
            return;
        }
        in_flight_.push_back(committed);
        while (!in_flight_.empty() && in_flight_.front().status >= MTLCommandBufferStatusCompleted) {
            check(in_flight_.front());
            in_flight_.pop_front();
        }
        while (in_flight_.size() > kFramesInFlight) {
            const auto start = std::chrono::steady_clock::now();
            [in_flight_.front() waitUntilCompleted];
            stats_.wait_ms += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            ++stats_.waits;
            check(in_flight_.front());
            in_flight_.pop_front();
        }
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
        picture_.assign(static_cast<const std::uint8_t *>(readback_.contents),
                        static_cast<const std::uint8_t *>(readback_.contents) + kPictureBytes);
        picture_frame_ = frames_;
    }

    void deferred(const char *what, std::uint64_t &count) {
        if (count++ == 0u)
            std::cout << "[metal] " << what << ": not implemented (task 025); counted, nothing written\n"
                      << std::flush;
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
        return texture;
    }

    // -----------------------------------------------------------------------------------------------
    // Draws

    // The draw's vertices as a list of the Metal primitive it is drawn as; false for none.
    bool expand(const DrawCall &call, MTLPrimitiveType &type) {
        vertices_.clear();
        // A vertex without a colour is drawn with the material colour, unlit (no lighting yet: 024).
        const bool use_material_color = !call.has_vertex_color && !call.lighting_enabled;
        const std::size_t total = call.vertices.size();
        const std::size_t count = call.indices.empty() ? total : call.indices.size();
        const auto at = [&](std::size_t i) -> const Vertex & {
            const std::size_t index = call.indices.empty() ? i : call.indices[i];
            return call.vertices[std::min(index, total - 1u)];
        };
        const auto push = [&](const Vertex &vertex) {
            GpuVertex out;
            out.x = vertex.position[0];
            out.y = vertex.position[1];
            out.z = vertex.position[2];
            out.u = vertex.texcoord[0];
            out.v = vertex.texcoord[1];
            out.color = use_material_color ? call.material_color : vertex.color;
            vertices_.push_back(out);
        };
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
        return !vertices_.empty();
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

    id<MTLRenderPipelineState> render_pipeline(const RenderKey &key) {
        if (const auto found = render_pipelines_.find(key); found != render_pipelines_.end()) return found->second;
        MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = vertex_function_;
        descriptor.fragmentFunction = fragment_functions_[(key.textured ? 1u : 0u) | (key.alpha_test ? 2u : 0u)];
        MTLRenderPipelineColorAttachmentDescriptor *colour = descriptor.colorAttachments[0];
        colour.pixelFormat = MTLPixelFormatRGBA8Unorm;
        colour.writeMask = key.write_mask;
        colour.blendingEnabled = key.blend;
        colour.rgbBlendOperation = static_cast<MTLBlendOperation>(key.operation);
        colour.sourceRGBBlendFactor = static_cast<MTLBlendFactor>(key.source);
        colour.destinationRGBBlendFactor = static_cast<MTLBlendFactor>(key.destination);
        // The alpha is the PSP's stencil, which only clears write here (task 025 adds the rest).
        colour.alphaBlendOperation = MTLBlendOperationAdd;
        colour.sourceAlphaBlendFactor = MTLBlendFactorOne;
        colour.destinationAlphaBlendFactor = MTLBlendFactorZero;
        descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        descriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        NSError *failure = nil;
        id<MTLRenderPipelineState> state = [device_ newRenderPipelineStateWithDescriptor:descriptor error:&failure];
        if (state == nil)
            std::cout << "[metal] cannot make a pipeline: "
                      << (failure != nil ? failure.localizedDescription.UTF8String : "no message") << "\n";
        render_pipelines_.emplace(key, state);
        return state;
    }

    id<MTLDepthStencilState> depth_state(const DepthStencilKey &key) {
        if (const auto found = depth_states_.find(key); found != depth_states_.end()) return found->second;
        MTLDepthStencilDescriptor *descriptor = [MTLDepthStencilDescriptor new];
        descriptor.depthCompareFunction = static_cast<MTLCompareFunction>(key.compare);
        descriptor.depthWriteEnabled = key.write;
        // key.stencil and the fields after it: task 025 sets frontFaceStencil and backFaceStencil here.
        id<MTLDepthStencilState> state = [device_ newDepthStencilStateWithDescriptor:descriptor];
        depth_states_.emplace(key, state);
        return state;
    }

    void draw(const DrawCall &call, const GuestMemory &memory) {
        // Transformed draws reach the backend decoded (gpu_decode() is false).
        if (call.vertices.empty()) return;
        MTLPrimitiveType type{};
        if (!expand(call, type)) return;

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
        }

        // Pipeline state.
        key.render.textured = textured;
        if (call.clear_mode) {
            // CLEARMODE: no blend, texture or tests; bits 8..10 say what it writes.
            std::uint8_t mask = MTLColorWriteMaskNone;
            if ((call.clear_flags & 1u) != 0u) mask |= MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue;
            if ((call.clear_flags & 2u) != 0u) mask |= MTLColorWriteMaskAlpha;
            key.render.write_mask = mask;
            key.depth.compare = MTLCompareFunctionAlways;
            key.depth.write = (call.clear_flags & 4u) != 0u;
        } else {
            translate_blend(call.blend, key.render, fragment, blend_color);
            // Whole colour channels the write mask keeps are not written; the alpha, the PSP's
            // stencil, is left to the stencil operations (task 025).
            std::uint8_t mask = MTLColorWriteMaskNone;
            static constexpr MTLColorWriteMask kChannels[] = {MTLColorWriteMaskRed, MTLColorWriteMaskGreen,
                                                              MTLColorWriteMaskBlue};
            for (std::uint32_t channel = 0; channel < 3u; ++channel) {
                const std::uint32_t bits = (call.color_write_mask >> (8u * channel)) & 0xFFu;
                if (bits != 0xFFu) mask |= kChannels[channel];
                if (bits != 0u && bits != 0xFFu) not_emulated("partial colour write mask", call.color_write_mask);
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
                key.depth.reference = static_cast<std::uint8_t>(call.stencil.reference);
                key.depth.compare_mask = static_cast<std::uint8_t>(call.stencil.mask);
                key.depth.write_mask = static_cast<std::uint8_t>(~call.alpha_write_mask);
            }
        }
        id<MTLRenderPipelineState> pipeline = render_pipeline(key.render);
        if (pipeline == nil) return;
        id<MTLDepthStencilState> depth = depth_state(key.depth);

        // Positions: screen pixels in through mode; the GE viewport folded into clip space otherwise.
        MTLViewport viewport{0.0, 0.0, static_cast<double>(kWidth), static_cast<double>(kHeight), 0.0, 1.0};
        vertex.mode[0] = call.through ? 1u : 0u;
        if (!call.through) {
            vertex.transform = multiply(call.projection, multiply(call.view, call.world));
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
        const bool cull = call.culling_enabled && !call.through && type == MTLPrimitiveTypeTriangle &&
                          call.primitive != PrimitiveType::Sprites && !call.clear_mode;

        // Into the target's pass (after the texture, whose copy may have ended it).
        begin_pass(target);
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
            // backend's flipping viewport count it too (checked with a test triangle, 2026-10-06; the
            // frontend culls nothing, so task 024 confirms it on the race).
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
        [encoder_ drawPrimitives:type vertexStart:0 vertexCount:vertices_.size()];

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
    };

    bool ready_{};
    id<MTLDevice> device_;
    id<MTLCommandQueue> queue_;
    id<MTLLibrary> library_;
    id<MTLFunction> vertex_function_;
    std::array<id<MTLFunction>, 4> fragment_functions_{};  // by kTextured | kAlphaTest << 1
    std::array<id<MTLSamplerState>, 16> samplers_{};
    id<MTLTexture> white_;
    id<MTLBuffer> readback_;
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

    std::unordered_map<std::uint64_t, CachedTexture> textures_;
    std::map<TextureIdentity, std::uint64_t> list_keys_;  // this display list's binds, hashed once
    std::uint64_t texture_clock_{};
    std::vector<std::uint32_t> pixels_;
    std::vector<GpuVertex> vertices_;

    std::vector<std::uint8_t> picture_;  // the last picture read back
    std::uint64_t picture_frame_{~0ull};
    portablekit::gpu::VulkanRenderer *shell_{};
    std::vector<std::uint8_t> shell_scratch_;
    bool to_shell_{};
    bool sharp_{};
    bool log_draws_{};
    bool no_framebuffer_textures_{};

    std::uint64_t frames_{};
    std::uint64_t frame_draws_{};
    Stats stats_;
    std::uint64_t block_transfers_{};
    std::uint64_t frame_write_backs_{};
    std::uint64_t read_backs_{};
    std::uint64_t depth_write_backs_{};
    std::chrono::steady_clock::time_point started_{};
    std::chrono::steady_clock::time_point report_start_{};
    std::uint64_t report_frames_{};
    std::uint64_t report_draws_{};
};

const pk::BackendRegistration registration("metal", "native Metal (task 023: targets, textures, 2D draws)",
                                           [] { return std::unique_ptr<pk::GeBackend>(new MetalGeBackend()); });

} // namespace
} // namespace pure::gpu
