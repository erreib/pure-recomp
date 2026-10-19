// The Metal backend's targets and guest memory (docs/metal-backend.md, "Targets" and "Guest memory"): the target
// cache keyed by (colour address, stride, format); a texture bind that lies in a target found in it (patch 0003),
// and the copy a draw samples when it reads the target it draws into; block transfers, read-backs and the frame and
// depth write-backs, which store a target's pixels or depth in guest memory; a CPU picture copied into a target.
#include "metal_backend.hpp"
#include "metal_device.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <iostream>
#include <memory>
#include <utility>
#include <vector>

namespace pure::gpu::metal_backend {

Target &MetalGeBackend::target_for(const TargetKey &key) {
    const auto found = targets_.find(key);
    if (found != targets_.end()) return *found->second;
    auto target = std::make_unique<Target>();
    target->key = key;
    // D-015: a screen-wide target (the display buffers, stride 512) at the internal scale; a narrower one (the
    // billboards' 128, the bloom's 256) at 480x272, so the bloom's blur keeps the PSP's radius on the screen. Under
    // Fill (task 086) the screen-wide ones take the drawable's shape at 272S rows; the narrower ones stay 480x272.
    target->scale = key.stride >= kWidth ? scale_ : 1u;
    target->columns = key.stride >= kWidth ? columns_ : kWidth;
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:target->width()
                                                          height:target->height()
                                                       mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    target->color = [device_ newTextureWithDescriptor:descriptor];
    descriptor.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    descriptor.usage = MTLTextureUsageRenderTarget;
    target->depth = [device_ newTextureWithDescriptor:descriptor];
    if (target->color == nil || target->depth == nil)
        std::cout << "[metal] target 0x" << std::hex << key.address << std::dec << " at " << target->width() << "x"
                  << target->height() << " could not be made\n";
    if (switches_.log_draws)
        std::cout << "[metal] frame " << frames_ + 1u << " new target 0x" << std::hex << key.address << std::dec
                  << " stride " << key.stride << " format " << key.format << "\n";
    return *targets_.emplace(key, std::move(target)).first->second;
}

// A change of the internal scale (task 067), between two frames (apply_scale()): the screen-wide targets go to
// retired_, so the next frame makes them anew at 480S x 272S as it draws into them (the narrower ones, at 1x
// whatever the scale, stay with what they hold), and the three shared buffers are made for the new size. Nothing is
// read back: the frame write-back pending since the last flip keeps its target and its buffer, and a flip that finds
// no target of the new scale at the display address shows the retired one, until the game draws it again. The
// start line's clause is printed again, `[metal] internal scale now S: ...`. Under Fill (task 086) a change of the
// drawable's shape is a change of the targets' width, and goes the same way.
void MetalGeBackend::change_scale(const Extent &extent) {
    end_encoder();
    for (auto it = targets_.begin(); it != targets_.end();) {
        if (it->first.stride < kWidth) {
            ++it;
            continue;
        }
        if (last_drawn_ == it->second.get()) last_drawn_ = nullptr;
        retired_.push_back(std::move(it->second));
        it = targets_.erase(it);
    }
    scale_ = extent.scale;
    columns_ = extent.columns;
    pure::metal::set_view_size(columns_, kHeight * scale_);
    const std::size_t largest = static_cast<std::size_t>(columns_) * kHeight * scale_ * 4u;
    readback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
    frame_writeback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
    guest_readback_ = [device_ newBufferWithLength:largest options:MTLResourceStorageModeShared];
    std::cout << "[metal] " << scale_report(true) << "\n" << std::flush;
}

// The retired target at `address` drawn into last (change_scale()).
Target *MetalGeBackend::latest_retired_at(std::uint32_t address) {
    Target *best = nullptr;
    for (const std::unique_ptr<Target> &target : retired_)
        if (target->key.address == address && target->color_defined &&
            (best == nullptr || target->draw_serial > best->draw_serial))
            best = target.get();
    return best;
}

bool MetalGeBackend::retired(const Target *target) const {
    return target != nullptr && std::any_of(retired_.begin(), retired_.end(), [target](const auto &old) {
               return old.get() == target;
           });
}

// The target at `address` drawn into last, of any stride and format.
Target *MetalGeBackend::latest_target_at(std::uint32_t address) {
    Target *best = nullptr;
    for (auto &[key, target] : targets_)
        if (key.address == address && target->color_defined &&
            (best == nullptr || target->draw_serial > best->draw_serial))
            best = target.get();
    return best;
}

void MetalGeBackend::snapshot_guest_words(const GuestMemory &memory, Target &target) {
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
Target *MetalGeBackend::find_framebuffer_texture(const GuestMemory &memory, const TextureState &texture,
                                                 std::uint32_t &x, std::uint32_t &y) {
    if (switches_.no_framebuffer_textures || texture.swizzled || static_cast<std::uint32_t>(texture.format) > 3u ||
        texture.width == 0u || texture.height == 0u)
        return nullptr;
    const std::uint32_t texture_address = GuestMemory::canonical(texture.address);
    Target *best = nullptr;
    bool best_exact = false;
    for (auto &[key, target] : targets_) {
        if (!target->color_defined || target->guest_words.empty()) continue;
        const std::uint32_t bytes_per_pixel = target->bytes_per_pixel();
        if (texture_bits(texture.format) != bytes_per_pixel * 8u) continue;
        if (!target->contains(texture_address)) continue;
        if (texture.buffer_width != key.stride || (texture_address - key.address) % bytes_per_pixel != 0u) continue;
        const bool exact = texture_address == key.address;
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
id<MTLTexture> MetalGeBackend::sample_target(Target &source, const Target &drawn) {
    if (&source != &drawn) return source.color;
    if (source.copy == nil) {
        MTLTextureDescriptor *descriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:source.width()
                                                              height:source.height()
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

// Before the HLE copies a block transfer's rows: when the source lies in a target this backend drew, the
// target's rows the copy reads are stored in guest memory first, in the target's format.
void MetalGeBackend::block_transfer(const pk::BlockTransfer &transfer, GuestMemory &memory) {
    ++stats_.transfers.calls;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    if (!ready_ || switches_.no_framebuffer_textures || transfer.width == 0u || transfer.height == 0u ||
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
// buffer; this waits for that copy and stores them.
void MetalGeBackend::write_back_frame(GuestMemory &memory) {
    ++stats_.frames.calls;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    if (!ready_ || pending_frame_.target == nullptr) return;
    PendingFrame pending = pending_frame_;
    pending_frame_ = PendingFrame{};
    @autoreleasepool {
        if (pending.commands != nil && pending.commands.status < MTLCommandBufferStatusCompleted) {
            const auto start = std::chrono::steady_clock::now();
            [pending.commands waitUntilCompleted];
            const double ms =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            stats_.wait_ms += ms;
            stats_.frames.wait_ms += ms;
            trace_.times.wait_frame += ms;
            ++stats_.waits;
        }
        const auto *pixels = static_cast<const std::uint8_t *>(pending.buffer.contents);
        if (store_pixels(memory, *pending.target, guest_pixels(*pending.target, pixels), 0u, kHeight))
            ++stats_.frames.written;
    }
}

// The target at `address` into guest VRAM, whole (the Vulkan backend's rule: a target in VRAM that the GE
// drew, at least as wide as the screen).
void MetalGeBackend::read_back_framebuffer(std::uint32_t address, GuestMemory &memory) {
    ++stats_.read_backs.calls;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    if (!ready_ || switches_.no_framebuffer_textures) return;
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
bool MetalGeBackend::write_back_depth(std::uint32_t color_address, std::uint32_t depth_address,
                                      std::uint32_t depth_stride, GuestMemory &memory, const char *why) {
    ++stats_.depths.calls;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    if (!ready_) return false;
    @autoreleasepool {
        return store_depth(color_address, depth_address, depth_stride, memory, why);
    }
}

// The target whose memory holds byte `address` and which the GE drew into (an upload's target holds a
// picture the CPU wrote, which is in guest memory already), in VRAM: the one starting at `start` first
// (patch 0003's rule), else the one drawn last.
Target *MetalGeBackend::drawn_target_containing(std::uint32_t start, std::uint64_t address) {
    Target *best = nullptr;
    bool best_exact = false;
    for (auto &[key, target] : targets_) {
        if (!target->color_defined || target->guest_words.empty()) continue;
        if ((key.address & 0x1F000000u) != 0x04000000u) continue;
        if (!target->contains(address)) continue;
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
bool MetalGeBackend::frame_written_back(const Target &target) {
    return target.color_defined && !target.guest_words.empty() &&
           (target.key.address & 0x1F000000u) == 0x04000000u && target.key.stride >= kWidth;
}

// Rows `first_row` to `first_row + rows - 1` of the target into guest memory, read back now (a blit into a
// shared buffer and a wait), counted in `writes`.
void MetalGeBackend::store_target(GuestMemory &memory, Target &target, std::uint32_t first_row, std::uint32_t rows,
                                  GuestWrites &writes) {
    copy_to_buffer(target.color, guest_readback_, MTLBlitOptionNone);
    commit(true);
    writes.wait_ms += last_wait_ms_;
    trace_.times.wait_guest += last_wait_ms_;
    if (store_pixels(memory, target,
                     guest_pixels(target, static_cast<const std::uint8_t *>(guest_readback_.contents)), first_row,
                     rows))
        ++writes.written;
}

namespace {

// The pixel of a target `size` pixels across that holds the centre of guest pixel `index` of `guest` (480 or 272):
// (index + 0.5) x size / guest, rounded down, in whole numbers. At internal scale S that is index S + S/2 (D-015),
// the centre pixel of its S x S block; under Fill (task 086) a fraction of the way across the target's width.
std::uint32_t centre_of(std::uint32_t index, std::uint32_t guest, std::uint32_t size) {
    return static_cast<std::uint32_t>((static_cast<std::uint64_t>(2u * index + 1u) * size) / (2u * guest));
}

} // namespace

// The guest's 480x272 picture of `target` from `pixels`, its colour read back at its own size (rows of width() RGBA
// pixels): `pixels` itself at internal scale 1; at S, the centre pixel of each S x S block, (x S + S/2, y S + S/2),
// gathered into guest_picture_ (D-015: the game sees a 480x272 picture as before); under Fill (task 086) the pixel
// at the centre of each guest pixel's place, (x + 0.5) x width/480 across (centre_of()).
const std::uint8_t *MetalGeBackend::guest_pixels(const Target &target, const std::uint8_t *pixels) {
    if (target.width() == kWidth && target.height() == kHeight) return pixels;
    guest_picture_.resize(kPictureBytes);
    const std::size_t row_pixels = target.width();
    std::array<std::uint32_t, kWidth> columns{};
    for (std::uint32_t x = 0; x < kWidth; ++x) columns[x] = centre_of(x, kWidth, target.width());
    for (std::uint32_t y = 0; y < kHeight; ++y) {
        const std::uint8_t *row =
            pixels + static_cast<std::size_t>(centre_of(y, kHeight, target.height())) * row_pixels * 4u;
        std::uint8_t *out = guest_picture_.data() + static_cast<std::size_t>(y) * kWidth * 4u;
        for (std::uint32_t x = 0; x < kWidth; ++x)
            std::memcpy(out + static_cast<std::size_t>(x) * 4u, row + static_cast<std::size_t>(columns[x]) * 4u, 4u);
    }
    return guest_picture_.data();
}

// 480x272 RGBA pixels (red in the low byte) of `target` into its guest memory, rows `first_row` onward, in
// its format and stride (min(stride, 480) pixels a row): 8888 as they are, 5650, 5551 and 4444 packed with
// red in the low bits, as texture_decode reads them and the Vulkan backend's store_frame writes them. The
// target's guest-word snapshot is taken again, since memory now holds what it shows.
bool MetalGeBackend::store_pixels(GuestMemory &memory, Target &target, const std::uint8_t *pixels,
                                  std::uint32_t first_row, std::uint32_t rows) {
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
bool MetalGeBackend::store_depth(std::uint32_t color_address, std::uint32_t depth_address, std::uint32_t depth_stride,
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
    copy_to_buffer(target->depth, guest_readback_, MTLBlitOptionDepthFromDepthStencil);
    commit(true);
    stats_.depths.wait_ms += last_wait_ms_;
    trace_.times.wait_depth += last_wait_ms_;
    const auto *depths = static_cast<const float *>(guest_readback_.contents);
    // At internal scale S each guest pixel's depth is the centre of its S x S block (D-015); under Fill the pixel at
    // the centre of its place across the target's width (task 086), as guest_pixels() takes the colour.
    const std::size_t row_pixels = target->width();
    std::array<std::uint32_t, kWidth> columns{};
    for (std::uint32_t x = 0; x < kWidth; ++x) columns[x] = centre_of(x, kWidth, target->width());
    std::uint32_t lowest = 0xFFFFu, highest = 0u;
    std::array<std::uint16_t, kWidth> row{};
    for (std::uint32_t y = 0; y < kHeight; ++y) {
        const float *line = depths + static_cast<std::size_t>(centre_of(y, kHeight, target->height())) * row_pixels;
        for (std::uint32_t x = 0; x < kWidth; ++x) {
            const float depth = line[columns[x]];
            const auto z = static_cast<std::uint32_t>(std::clamp(depth, 0.0f, 1.0f) * 65535.0f + 0.5f);
            lowest = std::min(lowest, z);
            highest = std::max(highest, z);
            row[x] = static_cast<std::uint16_t>(z);
        }
        std::memcpy(out + static_cast<std::size_t>(y) * depth_stride * 2u, row.data(), sizeof(row));
    }
    ++stats_.depths.written;
    if (!std::exchange(trace_.depth_announced, true))
        std::cout << "[metal] depth written back to guest memory at 0x" << std::hex << depth_address << std::dec
                  << " for " << why << " (PURE_NO_DEPTH_READBACK turns it off)\n";
    if (trace_.depth) {
        const double total =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        std::cout << "[metal] frame " << frames_ + 1u << " " << why << ": depth of 0x" << std::hex
                  << target->key.address << " written back to 0x" << depth_address << std::dec << " stride "
                  << depth_stride << ", z " << lowest << "-" << highest << ", " << total << " ms (GPU wait "
                  << last_wait_ms_ << " ms)\n";
    }
    return true;
}

void MetalGeBackend::upload_frame(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                                  std::uint32_t height, std::uint32_t stride) {
    if (!ready_ || pixels == nullptr || width == 0u || height == 0u || stride < width) return;
    const TraceClock clock(trace_.file != nullptr, trace_.times.memory);
    @autoreleasepool {
        upload(display_address, pixels, width, height, stride);
    }
}

void MetalGeBackend::upload(std::uint32_t display_address, const std::uint8_t *pixels, std::uint32_t width,
                            std::uint32_t height, std::uint32_t stride) {
    const std::uint32_t address = GuestMemory::canonical(display_address);
    Target *target = latest_target_at(address);
    if (target == nullptr) target = &target_for({address, stride, 3u});
    const std::uint32_t copied_width = std::min(width, kWidth);
    const std::uint32_t copied_height = std::min(height, kHeight);
    if (copied_width != kWidth || copied_height != kHeight)
        not_emulated("CPU picture not 480x272 (copied to the top left, unscaled), width", width);
    // A target never drawn starts cleared where the picture does not cover it.
    if (!target->color_defined) begin_pass(*target);
    if (target->reshaped()) {
        upload_fitted(*target, pixels, copied_width, copied_height, stride);
        return;
    }
    // At the target's internal scale S each pixel of the picture is an S x S block (D-015).
    const std::uint32_t scale = target->scale;
    const std::uint32_t scaled_width = copied_width * scale;
    const std::uint32_t scaled_height = copied_height * scale;
    const std::size_t row_bytes = static_cast<std::size_t>(scaled_width) * 4u;
    const std::size_t bytes = row_bytes * scaled_height;
    const auto [buffer, offset] = allocate(bytes);
    auto *staging = static_cast<std::uint8_t *>(buffer.contents) + offset;
    for (std::uint32_t row = 0; row < copied_height; ++row) {
        const std::uint8_t *source = pixels + static_cast<std::size_t>(row) * stride * 4u;
        std::uint8_t *line = staging + static_cast<std::size_t>(row) * scale * row_bytes;
        if (scale == 1u) {
            std::memcpy(line, source, row_bytes);
            continue;
        }
        for (std::uint32_t x = 0; x < copied_width; ++x)
            for (std::uint32_t copy = 0; copy < scale; ++copy)
                std::memcpy(line + (static_cast<std::size_t>(x) * scale + copy) * 4u, source + x * 4u, 4u);
        for (std::uint32_t copy = 1; copy < scale; ++copy) std::memcpy(line + copy * row_bytes, line, row_bytes);
    }
    end_encoder();
    id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
    [blit copyFromBuffer:buffer
               sourceOffset:offset
          sourceBytesPerRow:scaled_width * 4u
        sourceBytesPerImage:bytes
                 sourceSize:MTLSizeMake(scaled_width, scaled_height, 1)
                  toTexture:target->color
           destinationSlice:0
           destinationLevel:0
          destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    uploaded(*target);
}

// What an upload leaves: the target drawn, by a picture from guest memory, which texturing reads correctly anyway.
void MetalGeBackend::uploaded(Target &target) {
    target.color_defined = true;
    frame_drawn_ = true;
    target.draw_serial = ++draw_counter_;
    target.guest_words.clear();
    last_drawn_ = &target;
    ++stats_.uploads;
}

// A CPU picture into a target of another shape than the PSP's (Fill, task 086). The picture has the PSP's shape (a movie
// frame, a loading picture) and keeps it, as the Vulkan renderer keeps a movie's under Fill: it fills the target's
// height, centred, with black beside it (or, in a target narrower than the PSP's shape, its width, with black above and
// below), each target pixel the picture's pixel under its centre; at 272S rows in a wider target that is an S x S block
// a pixel, as at Original.
void MetalGeBackend::upload_fitted(Target &target, const std::uint8_t *pixels, std::uint32_t width,
                                   std::uint32_t height, std::uint32_t stride) {
    const std::uint32_t columns = target.width();
    const std::uint32_t rows = target.height();
    const std::uint32_t shown_width = std::min<std::uint32_t>(
        columns, static_cast<std::uint32_t>(std::lround(static_cast<double>(rows) * kWidth / kHeight)));
    const std::uint32_t shown_height = std::min<std::uint32_t>(
        rows, static_cast<std::uint32_t>(std::lround(static_cast<double>(columns) * kHeight / kWidth)));
    const std::uint32_t left = (columns - shown_width) / 2u;
    const std::uint32_t top = (rows - shown_height) / 2u;
    const std::size_t row_bytes = static_cast<std::size_t>(columns) * 4u;
    const std::size_t bytes = row_bytes * rows;
    const auto [buffer, offset] = allocate(bytes);
    auto *staging = static_cast<std::uint8_t *>(buffer.contents) + offset;
    constexpr std::uint32_t kOpaqueBlack = 0xFF000000u;
    // The picture's column for each target column (kWidth, beyond what the picture has, for black).
    std::vector<std::uint32_t> sources(columns, kWidth);
    for (std::uint32_t x = 0; x < shown_width; ++x) {
        const std::uint32_t source = static_cast<std::uint32_t>((static_cast<std::uint64_t>(2u * x + 1u) * kWidth) /
                                                                (2u * shown_width));
        if (source < width) sources[left + x] = source;
    }
    for (std::uint32_t y = 0; y < rows; ++y) {
        auto *line = reinterpret_cast<std::uint32_t *>(staging + static_cast<std::size_t>(y) * row_bytes);
        const std::uint32_t source_y =
            y >= top && y < top + shown_height
                ? static_cast<std::uint32_t>((static_cast<std::uint64_t>(2u * (y - top) + 1u) * kHeight) /
                                             (2u * shown_height))
                : kHeight;
        if (source_y >= height) {
            std::fill(line, line + columns, kOpaqueBlack);
            continue;
        }
        const std::uint8_t *source = pixels + static_cast<std::size_t>(source_y) * stride * 4u;
        for (std::uint32_t x = 0; x < columns; ++x) {
            if (sources[x] >= width) line[x] = kOpaqueBlack;
            else std::memcpy(line + x, source + static_cast<std::size_t>(sources[x]) * 4u, 4u);
        }
    }
    end_encoder();
    id<MTLBlitCommandEncoder> blit = [commands_ blitCommandEncoder];
    [blit copyFromBuffer:buffer
               sourceOffset:offset
          sourceBytesPerRow:row_bytes
        sourceBytesPerImage:bytes
                 sourceSize:MTLSizeMake(columns, rows, 1)
                  toTexture:target.color
           destinationSlice:0
           destinationLevel:0
          destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    uploaded(target);
}

} // namespace pure::gpu::metal_backend
