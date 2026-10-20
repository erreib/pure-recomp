// The Metal backend's texture pack loader (task 100, D-024 point 3; docs/metal-backend.md, "The pack loader"). The
// framework's pack class does the backend-neutral part (gpu/texture_pack.hpp: textures.ini, the keys, the loader
// threads that decode the images, the 256 MB decode window); this is the Metal side of what the Vulkan renderer's
// host/gpu/replacement_textures.cpp does: the pack opened and closed once a frame as the menu asks, a decoded
// texture's replacement looked up once (with the format's 512-tall rule), its image uploaded with a full mip chain the
// first time a draw samples it (at most 32 MB a frame past the first image; the original is drawn until then), the
// images on the GPU kept within a budget, the `[texpack]` trace lines, and the menu's TexturePackHost (patch
// 0034-texture-pack-host), which the Metal shell registers.
#include "metal_backend.hpp"
#include "gpu/texture_pack_import.hpp"
#include "install/user_data.hpp"
#include "profile.hpp"
#include "settings/settings.hpp"

#include <algorithm>
#include <bit>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <system_error>
#include <utility>
#include <vector>

namespace pure::gpu::metal_backend {

namespace {

// The Vulkan renderer's constants (replacement_textures.cpp). Replacements on the GPU at once, at most.
constexpr std::size_t kMaxResident = 4096u;
// Pixels uploaded a frame, at most, past the first image: a scene change can bring in dozens of large images.
constexpr std::uint64_t kUploadBytesPerFrame = 32ull * 1024u * 1024u;
// A replacement drawn within this many frames is never dropped for the budget. An in-flight command buffer keeps an
// image it samples alive (ARC), so a drop needs no fence; the margin keeps a texture the game draws every few frames
// from being uploaded again and again.
constexpr std::uint64_t kKeepFrames = 4u;

// PURE_TEXTURE_PACK_MEMORY: megabytes of GPU memory for replacements (default 1024, at least 64), as the Vulkan
// renderer reads it.
std::uint64_t budget_from_environment() {
    std::uint64_t megabytes = 1024u;
    if (const char *value = portablekit::env("TEXTURE_PACK_MEMORY"); value != nullptr && *value != '\0') {
        char *end = nullptr;
        const unsigned long long parsed = std::strtoull(value, &end, 10);
        if (end != value && parsed >= 64u) megabytes = parsed;
    }
    return megabytes * 1024u * 1024u;
}

// The format's 512-tall rule, as the Vulkan renderer keeps it (vulkan_renderer.cpp, file-local there): a texture 512
// texels tall drawn in through mode is hashed only down to the rows its draws have read. The largest V a draw reads:
// a through-mode draw's own, in texels; the whole texture for any other.
std::uint16_t drawn_max_v(const DrawCall &call) {
    if (!call.through) return 512u;
    float max_v = 0.0f;
    for (const Vertex &vertex : call.vertices) max_v = std::max(max_v, vertex.texcoord[1]);
    return static_cast<std::uint16_t>(std::clamp(max_v, 0.0f, 512.0f));
}

// A texture's rows seen after a draw that read down to `drawn`: the first through-mode draw at least 272, a later
// one deeper than that the whole texture.
std::uint16_t update_max_seen_v(std::uint16_t seen, std::uint16_t drawn, bool through) {
    if (!through) return 512u;
    if (seen == 0u) return drawn > 0u ? std::max<std::uint16_t>(272u, drawn) : 0u;
    return drawn > seen ? 512u : seen;
}

std::filesystem::path textures_root() { return portablekit::install::user_data_directory() / "textures"; }

pk::TexturePackLocation pack_location() {
    return pk::texture_pack_location(textures_root(), portablekit::game().disc_id,
                                     portablekit::settings::current().texture_pack_folder);
}

} // namespace

// video.texture_pack (on by default; PURE_TEXTURE_PACK) as the first frame, or the menu's first call, finds it, and
// the budget.
void MetalGeBackend::start_texture_pack() {
    if (pack_started_) return;
    pack_started_ = true;
    pack_wanted_ = portablekit::settings::current().texture_pack;
    pack_applied_ = !pack_wanted_;  // the first apply_texture_pack() opens the pack, or says Off
    pack_budget_ = budget_from_environment();
}

// Opens or closes the pack when the setting, the import's hold or a reload changed it. The cached textures that hold
// the old pack's replacements are dropped, and so is the cache when a pack opens, so the next draws decode the
// originals again and look them up in it; with no pack before or after, the cache is kept: without one the backend
// draws as it did before task 100. The status strings are the Vulkan renderer's.
void MetalGeBackend::apply_texture_pack() {
    start_texture_pack();
    const bool wanted = pack_wanted_ && !pack_held_;
    if (pack_applied_ == wanted && !pack_reload_) return;
    pack_applied_ = wanted;
    pack_reload_ = false;
    const bool had_pack = pack_ != nullptr;
    resident_.clear();  // a command buffer that samples one keeps it alive
    resident_bytes_ = 0u;
    if (had_pack) textures_.clear();
    pack_.reset();  // stops its loader threads
    pack_status_.clear();
    if (!wanted) {
        pack_status_ = pack_held_ ? "Updating" : "Off";
        return;
    }
    const pk::TexturePackLocation location = pack_location();
    std::string error;
    pack_ = pk::TexturePack::open(location.folder, portablekit::game().disc_id, error);
    if (!pack_) {
        std::error_code ec;
        if (std::filesystem::is_directory(location.folder, ec)) pack_status_ = "Not loaded: " + error;
        else if (location.source == pk::TexturePackLocation::Source::Installed) pack_status_ = "Not installed";
        else pack_status_ = "Folder missing: " + portablekit::install::path_to_utf8(location.folder);
        std::cout << "[texpack] " << error << "\n";
        return;
    }
    textures_.clear();
    pack_status_ = std::to_string(pack_->entry_count()) + " textures";
    std::cout << "[texpack] " << pack_->entry_count() << " textures from " << location.folder.string() << "\n";
}

// Once a frame (begin_frame()): the pack applied, the frame's upload allowance renewed, the budget kept, and with
// PURE_TRACE_TEXTURE_PACK the line every 60 frames.
void MetalGeBackend::texture_pack_frame() {
    apply_texture_pack();
    uploaded_this_frame_ = 0u;
    if (!pack_) return;
    evict_replacements();
    if (pk::texture_pack_trace() && frames_ % 60u == 0u && frames_ != pack_line_frame_) {
        pack_line_frame_ = frames_;
        std::cout << "[texpack] frame " << frames_ << ": " << replaced_draws_ << " draws replaced in 60 frames, "
                  << resident_.size() << " images on the GPU (" << (resident_bytes_ >> 20u) << " MB)\n";
        replaced_draws_ = 0u;
    }
}

// A newly decoded texture's replacement (decoded_texture(), with the pack open): the pack's key over its texels and
// palette, through mode's rows of a 512-tall texture as far as this draw reads them. Null when the pack has none.
void MetalGeBackend::find_replacement(const GuestMemory &memory, const TextureState &state, CachedTexture &cached) {
    cached.max_seen_v = 0u;
    if (state.height == 512u && drawing_ != nullptr)
        cached.max_seen_v = update_max_seen_v(0u, drawn_max_v(*drawing_), drawing_->through);
    cached.replacement = pack_->find(memory, state, cached.max_seen_v);
}

// What a draw of a cached texture samples with the pack open: the replacement's image once it is on the GPU, the
// texture itself until then (and for a texture the pack does not replace). It supersedes the sprite upscale: the
// upscaled texture's cache entry finds the same replacement. A 512-tall texture drawn deeper than before is looked
// up again over the rows now in use.
id<MTLTexture> MetalGeBackend::pack_texture(const GuestMemory &memory, const TextureState &state, CachedTexture &cached) {
    if (state.height == 512u && cached.max_seen_v < 512u && drawing_ != nullptr) {
        const std::uint16_t seen = update_max_seen_v(cached.max_seen_v, drawn_max_v(*drawing_), drawing_->through);
        if (seen != cached.max_seen_v) {
            cached.max_seen_v = seen;
            cached.replacement = pack_->find(memory, state, seen);
        }
    }
    if (!cached.replacement) return cached.texture;
    id<MTLTexture> replaced = replacement_texture(*cached.replacement);
    if (replaced == nil) return cached.texture;
    ++replaced_draws_;
    return replaced;
}

// The replacement's image on the GPU, or nil while the original is drawn: an Unloaded one is queued for the loader
// threads, a Decoded one uploaded unless this frame's allowance or the resident count is spent (a later frame takes
// it), and its pixels handed back to the pack either way it ends (consumed()), so the decode window never fills with
// images nobody takes. One that cannot be uploaded is Failed and never tried again.
id<MTLTexture> MetalGeBackend::replacement_texture(pk::Replacement &replacement) {
    if (const auto found = resident_.find(&replacement); found != resident_.end()) {
        found->second.last_used = frames_;
        return found->second.texture;
    }
    switch (replacement.state.load(std::memory_order_acquire)) {
    case pk::Replacement::State::Unloaded: pack_->request(replacement); return nil;
    case pk::Replacement::State::Decoded: break;
    default: return nil;
    }
    if (uploaded_this_frame_ != 0u && uploaded_this_frame_ + replacement.pixels.size() > kUploadBytesPerFrame)
        return nil;
    if (resident_.size() >= kMaxResident) return nil;
    ResidentImage image;
    if (!upload_replacement(replacement, image)) {
        std::cout << "[texpack] cannot upload " << replacement.name << " (" << replacement.width << "x"
                  << replacement.height << "); the original is drawn\n";
        pack_->consumed(replacement);
        replacement.state.store(pk::Replacement::State::Failed, std::memory_order_release);
        return nil;
    }
    if (pk::texture_pack_trace())
        std::cout << "[texpack] frame " << frames_ << ": uploaded " << replacement.name << " (" << (image.bytes >> 10u)
                  << " KiB with mips)\n";
    uploaded_this_frame_ += replacement.pixels.size();
    image.last_used = frames_;
    resident_bytes_ += image.bytes;
    pack_->consumed(replacement);
    id<MTLTexture> texture = image.texture;
    resident_.emplace(&replacement, std::move(image));
    return texture;
}

// The decoded RGBA8 rows into a private texture with a full mip chain: a staging buffer, the copy into level 0 and
// generateMipmapsForTexture in a blit encoder of a command buffer of its own, committed now on the queue the frame's
// commands are committed on later, so it runs before any draw that samples the image (Metal orders the two by the
// texture's hazard tracking). The pack's images have no levels of their own; the draws' level rule (task 037) and
// Texture detail (task 075) pick among these.
bool MetalGeBackend::upload_replacement(const pk::Replacement &replacement, ResidentImage &image) {
    const std::uint32_t width = replacement.width;
    const std::uint32_t height = replacement.height;
    if (width == 0u || height == 0u || replacement.pixels.size() != static_cast<std::size_t>(width) * height * 4u)
        return false;
    const std::uint32_t levels = static_cast<std::uint32_t>(std::bit_width(std::max(width, height)));
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:levels > 1u];
    descriptor.mipmapLevelCount = levels;
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device_ newTextureWithDescriptor:descriptor];
    if (texture == nil) return false;
    id<MTLBuffer> staging = [device_ newBufferWithBytes:replacement.pixels.data()
                                                 length:replacement.pixels.size()
                                                options:MTLResourceStorageModeShared |
                                                        MTLResourceCPUCacheModeWriteCombined];
    if (staging == nil) return false;
    id<MTLCommandBuffer> commands = [queue_ commandBuffer];
    commands.label = @"texture pack upload";
    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit copyFromBuffer:staging
               sourceOffset:0
          sourceBytesPerRow:static_cast<NSUInteger>(width) * 4u
        sourceBytesPerImage:replacement.pixels.size()
                 sourceSize:MTLSizeMake(width, height, 1)
                  toTexture:texture
           destinationSlice:0
           destinationLevel:0
          destinationOrigin:MTLOriginMake(0, 0, 0)];
    if (levels > 1u) [blit generateMipmapsForTexture:texture];
    [blit endEncoding];
    [commands commit];
    image.texture = texture;
    image.bytes = 0u;
    for (std::uint32_t n = 0u; n < levels; ++n)
        image.bytes += static_cast<std::uint64_t>(std::max(width >> n, 1u)) * std::max(height >> n, 1u) * 4u;
    return true;
}

// Over the budget or the count: the least recently drawn images not drawn in the last kKeepFrames frames are dropped
// down to 7/8 of the budget, their replacements Unloaded again (a later draw loads the file again; the original is
// drawn meanwhile). Said once when the images drawn right now need more than the budget.
void MetalGeBackend::evict_replacements() {
    if (resident_bytes_ <= pack_budget_ && resident_.size() < kMaxResident) return;
    std::vector<std::pair<std::uint64_t, pk::Replacement *>> candidates;
    for (const auto &[owner, image] : resident_)
        if (image.last_used + kKeepFrames < frames_) candidates.emplace_back(image.last_used, owner);
    std::sort(candidates.begin(), candidates.end(),
              [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &[last_used, owner] : candidates) {
        if (resident_bytes_ <= pack_budget_ * 7u / 8u && resident_.size() < kMaxResident) break;
        const auto found = resident_.find(owner);
        resident_bytes_ -= found->second.bytes;
        resident_.erase(found);
        owner->state.store(pk::Replacement::State::Unloaded, std::memory_order_release);
    }
    if (resident_bytes_ > pack_budget_ && !pack_budget_said_) {
        pack_budget_said_ = true;
        std::cerr << "[texpack] the replacements drawn right now need " << (resident_bytes_ >> 20u) << " MB, over the "
                  << (pack_budget_ >> 20u) << " MB budget (" << portablekit::env_name("TEXTURE_PACK_MEMORY") << ")\n";
    }
}

// The menu's TexturePackHost (patch 0034). Each change applies at the next frame, or now between two frames (nothing
// drawn since the flip: the paused menu runs there), as the Resolution row's does, so that an import's hold takes
// effect with the game paused behind the menu.
void MetalGeBackend::set_texture_pack(bool enabled) {
    start_texture_pack();
    pack_wanted_ = enabled;
    if (ready_ && !frame_drawn_) apply_texture_pack();
}

std::string MetalGeBackend::texture_pack_status() const {
    if (pack_held_) return "Updating";
    if (!pack_started_) return "Loading";
    if (pack_wanted_ != pack_applied_ || pack_reload_) return pack_wanted_ ? "Loading" : "Off";
    if (!pack_) return pack_status_;
    return pack_status_ + ", " + std::to_string(resident_.size()) + " on the GPU (" +
           std::to_string(resident_bytes_ >> 20u) + " MB)";
}

void MetalGeBackend::reload_texture_pack() {
    start_texture_pack();
    pack_reload_ = true;
    if (ready_ && !frame_drawn_) apply_texture_pack();
}

void MetalGeBackend::hold_texture_pack(bool hold) {
    start_texture_pack();
    pack_held_ = hold;
    if (ready_ && !frame_drawn_) apply_texture_pack();
}

bool MetalGeBackend::texture_pack_held() const { return pack_held_ && !pack_applied_ && !pack_; }

std::string MetalGeBackend::texture_pack_folder() const {
    return portablekit::install::path_to_utf8(pack_location().folder);
}

} // namespace pure::gpu::metal_backend
