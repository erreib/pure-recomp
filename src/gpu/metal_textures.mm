// The Metal backend's textures from guest memory (docs/metal-backend.md, "Textures", "Mipmaps" and "Sprite
// upscale"): the mip levels a draw samples, the content key (address, layout, every texel and the palette entries
// they reach), hashed once per display list, the decode with the framework's decode_texture() into a cache of
// kMaxTextures, the sprite upscale of a 2D draw's texture (task 073, sprite_upscale.cpp), and the GE's
// level rule. Textures that lie in a target are metal_targets.mm's.
#include "metal_backend.hpp"
#include "gpu/texture_decode.hpp"
#include "settings/settings.hpp"
#include "sprite_upscale.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <iterator>
#include <system_error>

namespace pure::gpu::metal_backend {
namespace {

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

// Hashed into the content key of an upscaled texture (task 073): the same texels cached plainly for a 3D draw and
// upscaled for a 2D one are two textures.
constexpr std::uint64_t kUpscaledKey = 0x5350524954453478ull;  // "SPRITE4x"

// `size` bytes of guest memory from `address` into the hash: one run of host memory when they are one,
// word by word otherwise.
std::uint64_t hash_guest(std::uint64_t hash, const GuestMemory &memory, std::uint32_t address, std::size_t size) {
    if (size == 0u) return hash;
    if (const std::uint8_t *data = memory.raw_pointer(address, size)) return hash_bytes(hash, data, size);
    if (!memory.contains(address, size)) return hash_value(hash, 0xDEADu);
    for (std::size_t at = 0u; at < size; ++at) hash = (hash ^ memory.load8(address + static_cast<std::uint32_t>(at))) * 0x100000001B3ull;
    return hash;
}

// The bytes decode_texture() reads for a texture: rows of its buffer width (its width when that is 0), or the
// blocks of a DXT texture.
std::size_t texture_bytes(const TextureState &state) {
    const std::uint32_t bits = texture_bits(state.format);
    if (bits != 0u) {
        const std::uint32_t stride = state.buffer_width != 0u ? state.buffer_width : state.width;
        return static_cast<std::size_t>(stride) * bits / 8u * state.height;
    }
    const std::size_t blocks = static_cast<std::size_t>((state.width + 3u) / 4u) * ((state.height + 3u) / 4u);
    return blocks * (state.format == TextureFormat::Dxt1 ? 8u : 16u);
}

// Mip level n of a texture as a texture of its own: level 0's format, swizzle and palette, the level's address,
// row length and size. What decode_texture() decodes the level from.
TextureState texture_level(const TextureState &state, std::uint32_t n) {
    TextureState level = state;
    if (n == 0u || n > state.levels.size()) return level;
    const pk::TextureLevel &registers = state.levels[n - 1u];
    level.address = registers.address;
    level.buffer_width = registers.buffer_width;
    level.width = registers.width;
    level.height = registers.height;
    return level;
}

// The GE's logarithm for the mip level, in 1/16 levels: a float's exponent and the top four bits of its mantissa,
// a piecewise linear log2 floored to 1/16 (PPSSPP's hardware notes, "GE arithmetic"). shaders/ge.metal has the same.
std::int32_t ge_log16(float value) {
    std::uint32_t bits{};
    std::memcpy(&bits, &value, sizeof(bits));
    return static_cast<std::int32_t>((bits >> 19u) & 0xFFFu) - 127 * 16;
}

} // namespace

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

// The mip levels a draw samples its texture with (task 037): the GE's level count when the minification
// filter takes levels (min_filter bit 2) and every level after the first halves the one before, lies in
// guest memory and outside every render target; 1 otherwise. A texture with a level that fails is drawn at
// level 0 alone, said once per texture.
std::uint32_t MetalGeBackend::mip_levels(const GuestMemory &memory, const TextureState &state) {
    if (switches_.no_mipmaps || state.level_count <= 1u || (state.min_filter & 4u) == 0u) return 1u;
    const std::uint32_t count =
        std::min<std::uint32_t>(state.level_count, 1u + static_cast<std::uint32_t>(state.levels.size()));
    for (std::uint32_t n = 1u; n < count; ++n) {
        const TextureState level = texture_level(state, n);
        const char *why = nullptr;
        if (level.width != std::max(1u, static_cast<std::uint32_t>(state.width) >> n) ||
            level.height != std::max(1u, static_cast<std::uint32_t>(state.height) >> n))
            why = "is not half the level before it";
        else if (!memory.contains(level.address, texture_bytes(level)))
            why = "lies outside guest memory";
        else if (target_holding(level.address, texture_bytes(level)) != nullptr)
            why = "lies in a render target";
        if (why == nullptr) continue;
        if (bad_levels_.insert(state.address).second)
            std::cout << "[metal] texture 0x" << std::hex << state.address << std::dec << " "
                      << format_name(state.format) << " " << state.width << "x" << state.height << ": level " << n
                      << " (0x" << std::hex << level.address << std::dec << " " << level.width << "x"
                      << level.height << ") " << why << "; drawn at level 0 alone\n"
                      << std::flush;
        return 1u;
    }
    return count;
}

// A render target whose memory overlaps [address, address + bytes), or none.
const Target *MetalGeBackend::target_holding(std::uint32_t address, std::size_t bytes) const {
    const std::uint64_t first = GuestMemory::canonical(address);
    const std::uint64_t end = first + bytes;
    for (const auto &[key, target] : targets_) {
        if (!target->color_defined) continue;
        if (first < key.address + target->bytes() && key.address < end) return target.get();
    }
    return nullptr;
}

// Address, layout, the bytes the texels of each of its first `levels` levels lie in and the palette entries
// they can reach.
std::uint64_t MetalGeBackend::content_key(const GuestMemory &memory, const TextureState &state, std::uint32_t levels) {
    std::uint64_t key = 0xCBF29CE484222325ull;
    key = hash_value(key, static_cast<std::uint64_t>(state.format) << 32u | levels);
    key = hash_value(key, state.swizzled ? 1u : 0u);
    for (std::uint32_t n = 0u; n < levels; ++n) {
        const TextureState level = texture_level(state, n);
        key = hash_value(key, level.address);
        key = hash_value(key, static_cast<std::uint64_t>(level.width) << 16u | level.height);
        key = hash_value(key, level.buffer_width);
        key = hash_guest(key, memory, level.address, texture_bytes(level));
    }
    if (indexed(state.format)) {
        const std::uint32_t bits = texture_bits(state.format);
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

// The formats whose textures a 2D draw has upscaled (task 073, D-018): the palette ones and the 16-bit
// ones, the menus' fonts, icons and art. Not 8888 (the movie and TV pictures), not DXT.
bool MetalGeBackend::upscalable(TextureFormat format) {
    return indexed(format) || format == TextureFormat::Rgba5650 || format == TextureFormat::Rgba5551 ||
           format == TextureFormat::Rgba4444;
}

// The menu's Text and sprites row (game.sprite_upscale, PURE_SPRITE_UPSCALE): 1, Upscaled, the default. Read at start
// and at each frame (begin_frame()), never per draw; at start, `[pure] sprite upscale: off` when it is off.
void MetalGeBackend::read_sprite_upscale(bool at_start) {
    sprite_upscale_ = portablekit::settings::game_option("sprite_upscale") == 1u;
    if (at_start && !sprite_upscale_) std::cout << "[pure] sprite upscale: off\n";
}

// PURE_SPRITE_DUMP=DIR: an upscaled texture's decoded input as DIR/<key>.src.png and its output (upscaled_) as
// DIR/<key>.png, the cache key in 16 hex digits, once per key. pixels_ holds the input.
void MetalGeBackend::dump_sprite(std::uint64_t key, const TextureState &state) {
    if (!sprites_dumped_.insert(key).second) return;
    char name[24];
    std::snprintf(name, sizeof(name), "%016llx", static_cast<unsigned long long>(key));
    const std::filesystem::path base = std::filesystem::path(switches_.sprite_dump) / name;
    const bool written =
        pure::gpu::write_png(base.string() + ".src.png", reinterpret_cast<const std::uint8_t *>(pixels_.data()),
                             state.width, state.height) &&
        pure::gpu::write_png(base.string() + ".png", upscaled_.data(), state.width * kSpriteScale,
                             state.height * kSpriteScale);
    if (!written) std::cout << "[metal] sprite dump: cannot write " << base.string() << ".png\n";
}

// The texture with its first `levels` levels (mip_levels()), each decoded from its own address with the
// framework's decoder; with more than one it is a mipmapped texture. With `upscale` (a 2D draw's texture of one
// level in a palette or 16-bit format, the option on: metal_draw.mm decides) level 0 is upscaled 4x by
// upscale_sprite() and cached under a key of its own: a texture of 4W x 4H texels that the draw's normalised
// coordinates sample in place.
id<MTLTexture> MetalGeBackend::decoded_texture(const GuestMemory &memory, const TextureState &state,
                                               std::uint32_t levels, bool upscale) {
    const TraceClock clock(trace_.file != nullptr, trace_.times.texture);
    std::uint64_t places = 0u;
    for (std::uint32_t n = 1u; n < levels; ++n) {
        const pk::TextureLevel &level = state.levels[n - 1u];
        places = hash_value(places, static_cast<std::uint64_t>(level.address) << 32u | level.buffer_width);
        places = hash_value(places, static_cast<std::uint64_t>(level.width) << 16u | level.height);
    }
    const TextureIdentity identity{state.address,
                                   state.buffer_width,
                                   static_cast<std::uint32_t>(state.width) << 16u | state.height,
                                   static_cast<std::uint32_t>(state.format),
                                   state.clut_address,
                                   state.clut_format | state.clut_shift << 4u | state.clut_mask << 12u |
                                       state.clut_offset << 20u,
                                   state.swizzled,
                                   levels,
                                   places};
    std::uint64_t key{};
    if (const auto memo = list_keys_.find(identity); memo != list_keys_.end()) {
        key = memo->second;
    } else {
        key = content_key(memory, state, levels);
        list_keys_.emplace(identity, key);
    }
    if (upscale) key = hash_value(key, kUpscaledKey);
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
    // The upscale (task 073): level 0's texels, 4x along each axis. A texture of more than one level is never upscaled.
    upscale = upscale && levels == 1u && pixels_.size() == static_cast<std::size_t>(state.width) * state.height;
    if (upscale) {
        const auto start = std::chrono::steady_clock::now();
        upscale_sprite(reinterpret_cast<const std::uint8_t *>(pixels_.data()), state.width, state.height, upscaled_);
        stats_.upscale_ms +=
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        ++stats_.upscaled;
        if (!sprite_upscale_said_) {
            sprite_upscale_said_ = true;
            std::cout << "[pure] sprite upscale: on (game.sprite_upscale)\n";
        }
        if (!switches_.sprite_dump.empty()) dump_sprite(key, state);
    }
    const std::uint32_t width = upscale ? state.width * kSpriteScale : state.width;
    const std::uint32_t height = upscale ? state.height * kSpriteScale : state.height;
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:levels > 1u];
    descriptor.mipmapLevelCount = levels;
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device_ newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:upscale ? static_cast<const void *>(upscaled_.data())
                                   : static_cast<const void *>(pixels_.data())
               bytesPerRow:static_cast<NSUInteger>(width) * 4u];
    std::uint64_t bytes = static_cast<std::uint64_t>(width) * height * 4u;
    for (std::uint32_t n = 1u; n < levels; ++n) {
        // mip_levels() checked the level's size and memory, and a level is no larger than level 0, which
        // decoded: the decoder does not refuse it.
        const TextureState level = texture_level(state, n);
        if (!pk::decode_texture(memory, level, pixels_) ||
            pixels_.size() != static_cast<std::size_t>(level.width) * level.height) {
            not_emulated("texture level that cannot be decoded (its texels undefined), format",
                         static_cast<std::uint32_t>(state.format));
            continue;
        }
        [texture replaceRegion:MTLRegionMake2D(0, 0, level.width, level.height)
                   mipmapLevel:n
                     withBytes:pixels_.data()
                   bytesPerRow:static_cast<NSUInteger>(level.width) * 4u];
        bytes += static_cast<std::uint64_t>(level.width) * level.height * 4u;
        ++stats_.decoded_levels;
    }
    textures_.emplace(key, CachedTexture{texture, ++texture_clock_});
    ++stats_.decoded;
    stats_.decoded_bytes += bytes;
    return texture;
}

// The GE's level rule (task 037; PPSSPP's hardware notes, "Mip level selection"), D in 1/16 levels:
//   auto (TEXLEVEL mode 0)   D = log16(g) - log16(q)
//   constant (mode 1)        D = bias
//   slope (mode 2)           D = 16 + log16(slope) - log16(q) + bias
// clamped to 0..16 x (levels - 1); log16 is ge_log16(). g (the largest of the texture coordinates' four
// screen gradients, in texels a pixel) and q (1/w, times the texture matrix's q) change across the draw, so
// the shader adds their terms; this sets the rest.
void MetalGeBackend::set_level_rule(const TextureState &state, std::uint32_t levels, FragmentUniforms &fragment) {
    float rule = kLevelAuto;
    std::int32_t constant = 0;
    switch (state.level_mode) {
    case 0u: break;
    case 1u:
        rule = kLevelConstant;
        constant = state.level_bias;
        break;
    case 2u:
        rule = kLevelSlope;
        constant = 16 + ge_log16(state.lod_slope) + state.level_bias;
        break;
    default: not_emulated("texture level mode (drawn as auto)", state.level_mode); break;
    }
    fragment.level = {rule, static_cast<float>(constant), static_cast<float>(state.width),
                      static_cast<float>(state.height)};
    fragment.level_range = {16.0f * static_cast<float>(levels - 1u), 0.0f, 0.0f, 0.0f};
}

} // namespace pure::gpu::metal_backend
