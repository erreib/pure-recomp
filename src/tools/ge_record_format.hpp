#pragma once

// The .gerec file: the calls the shell made on a GE backend (the framework's
// gpu/ge_backend.hpp), as the record backend (record_backend.cpp, beside this
// file) saw them, with the guest memory each call read, so that they can be
// fed to any backend outside the game (ge_replay.cpp) and the presented images
// compared. Both users are ours, so the format lives here; task 095 moved it
// out of the framework's patch 0004-ge-backend-and-shell-seams unchanged.
//
// A file is the 8 bytes "PKGEREC\0", a u32 format version (kVersion), then
// records. A record is a u8 kind, a u32 payload size and the payload.
// Everything is little endian. Structures are written field by field in the
// order ge_state.hpp declares them, without padding: bool is one byte, a
// string is a u32 length and its bytes, a vector a u32 count and its
// elements. A reader skips kinds it does not know by their size; kinds and the
// fields of a record only ever grow at the end, so a reader for this version
// reads later ones.
//
//   Begin           u32 first frame, u32 frames asked for, string inner backend, string environment prefix,
//                   u64 frames presented and u64 draws submitted by the inner backend before the first frame
//   Memory          u32 address, u32 size, the bytes: guest memory as the call after it reads it. Written for
//                   each range a call reads (texture texels and palette, a block transfer's source rows) that
//                   differs from what the recording last wrote for that range; the first one is the whole of
//                   VRAM where the recording begins
//   Words           u32 address, u32 step, u32 count, then count u32: one guest word every `step` bytes of a
//                   render target's area, at the first draw into it in each frame (what a backend compares to
//                   tell whether the CPU wrote under a target it samples as a texture)
//   DisplayList     nothing: begin_display_list()
//   Draw            a DrawCall (Writer::put(DrawCall)): submit(). Three parts came after the first recordings
//                   and end it: the texture map state (four u32: map mode, projection source, the two shade
//                   lights; a Draw that ends before it reads as map mode 0), then the texture's mip levels,
//                   fields of TextureState written apart (Writer::put_levels: u32 level count, seven times
//                   u32 address, u32 buffer width, u16 width, u16 height for levels 1 to 7, u32 level mode,
//                   s32 level bias, f32 LOD slope; a Draw that ends before them reads as one level), then the
//                   colour test (u8 enabled, u32 function, u32 reference, u32 mask), dithering (u8 enabled,
//                   four u32 matrix rows) and u8 CLIPENABLE (kPixelBytes; a Draw that ends before them reads
//                   as no colour test, no dithering and CLIPENABLE off)
//   Transfer        a BlockTransfer: block_transfer(), followed by Memory records of the source rows as the
//                   copy reads them, after the backend's read-back. The shell then copies the rows itself
//   ReadBack        u32 address: read_back_framebuffer()
//   WriteBackFrame  nothing: write_back_frame()
//   WriteBackDepth  u32 colour address, u32 depth address, u32 depth stride, u8 whether it wrote, string why
//   Upload          u32 display address, u32 width, u32 height, then width x height RGBA pixels: upload_frame()
//   FrameEnd        u32 frame number (frames_presented() of the inner backend once it was shown), u32 display
//                   address asked for, u64 frames presented, u64 draws submitted (the inner backend's own
//                   counters, cumulative), u32 draws and u32 records in this frame, u8 ImageApi of the presented
//                   image, u32 width, u32 height, u32 size and the bytes of the image as capture_frame() wrote it
//                   (a BMP; size 0 when there was none)
//   End             u32 frames recorded, u64 records in the file before this one
//
// A frame is the records after the FrameEnd before it (or after Begin) up to its own.
#include "gpu/ge_backend.hpp"
#include "gpu/ge_state.hpp"

#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace pure::gerec {

// The GE state's types (DrawCall and its parts, BlockTransfer), by their own names.
using namespace portablekit::gpu;

inline constexpr char kMagic[8] = {'P', 'K', 'G', 'E', 'R', 'E', 'C', '\0'};
inline constexpr std::uint32_t kVersion = 1u;

enum class Kind : std::uint8_t {
    Begin = 1,
    Memory = 2,
    Words = 3,
    DisplayList = 4,
    Draw = 5,
    Transfer = 6,
    ReadBack = 7,
    WriteBackFrame = 8,
    WriteBackDepth = 9,
    Upload = 10,
    FrameEnd = 11,
    End = 12,
};

inline const char *kind_name(Kind kind) {
    switch (kind) {
    case Kind::Begin: return "Begin";
    case Kind::Memory: return "Memory";
    case Kind::Words: return "Words";
    case Kind::DisplayList: return "DisplayList";
    case Kind::Draw: return "Draw";
    case Kind::Transfer: return "Transfer";
    case Kind::ReadBack: return "ReadBack";
    case Kind::WriteBackFrame: return "WriteBackFrame";
    case Kind::WriteBackDepth: return "WriteBackDepth";
    case Kind::Upload: return "Upload";
    case Kind::FrameEnd: return "FrameEnd";
    case Kind::End: return "End";
    }
    return "?";
}

// The number of bone matrix floats a Draw carries when it has them.
inline constexpr std::uint32_t kBoneFloats = 96u;
// The bytes of a Draw's mip level fields (Writer::put_levels).
inline constexpr std::uint32_t kLevelBytes = 4u + 7u * 12u + 12u;
// The bytes of a Draw's last part: the colour test, dithering and CLIPENABLE.
inline constexpr std::uint32_t kPixelBytes = 13u + 17u + 1u;

class Writer {
public:
    std::vector<std::uint8_t> bytes;

    void u8(std::uint8_t value) { bytes.push_back(value); }
    void flag(bool value) { bytes.push_back(value ? 1u : 0u); }
    void u16(std::uint16_t value) { raw(&value, sizeof value); }
    void u32(std::uint32_t value) { raw(&value, sizeof value); }
    void u64(std::uint64_t value) { raw(&value, sizeof value); }
    void f32(float value) { raw(&value, sizeof value); }
    void raw(const void *data, std::size_t size) {
        const auto *first = static_cast<const std::uint8_t *>(data);
        bytes.insert(bytes.end(), first, first + size);
    }
    void string(const std::string &value) {
        u32(static_cast<std::uint32_t>(value.size()));
        raw(value.data(), value.size());
    }
    template <std::size_t N> void floats(const std::array<float, N> &values) {
        for (const float value : values) f32(value);
    }

    void put(const Vertex &v) {
        floats(v.position), floats(v.normal), floats(v.texcoord);
        u32(v.color);
    }
    void put(const TextureState &v) {
        flag(v.enabled), u32(v.address), u32(v.buffer_width), u16(v.width), u16(v.height);
        u8(static_cast<std::uint8_t>(v.format)), flag(v.swizzled);
        u32(v.clut_address), u32(v.clut_format), u32(v.clut_shift), u32(v.clut_mask), u32(v.clut_offset);
        u32(v.clut_format_word), u32(v.clut_load_bytes), u32(v.clut_max_bytes);
        u32(v.function), flag(v.alpha_from_texture), u32(v.min_filter), u32(v.mag_filter), u32(v.wrap_s),
            u32(v.wrap_t);
        f32(v.scale_u), f32(v.scale_v), f32(v.offset_u), f32(v.offset_v);
    }
    void put(const RenderTarget &v) {
        u32(v.color_address), u32(v.color_stride), u32(v.color_format), u32(v.depth_address), u32(v.depth_stride);
    }
    void put(const BlendState &v) {
        flag(v.enabled), u32(v.source_factor), u32(v.destination_factor), u32(v.equation), u32(v.fixed_source),
            u32(v.fixed_destination);
    }
    void put(const DepthState &v) {
        flag(v.test_enabled), flag(v.write_enabled), u32(v.function), u16(v.range_near), u16(v.range_far);
    }
    void put(const AlphaTestState &v) { flag(v.enabled), u32(v.function), u32(v.reference), u32(v.mask); }
    void put(const StencilState &v) {
        flag(v.enabled), u32(v.function), u32(v.reference), u32(v.mask), u32(v.fail_op), u32(v.depth_fail_op),
            u32(v.pass_op);
    }
    void put(const ViewportState &v) {
        f32(v.x_scale), f32(v.y_scale), f32(v.z_scale), f32(v.x_offset), f32(v.y_offset), f32(v.z_offset);
        u32(v.scissor_x1), u32(v.scissor_y1), u32(v.scissor_x2), u32(v.scissor_y2);
        f32(v.offset_x), f32(v.offset_y);
    }
    void put(const LightState &v) {
        flag(v.enabled), u32(v.kind), u32(v.type);
        floats(v.position), floats(v.direction), floats(v.attenuation);
        f32(v.spot_exponent), f32(v.spot_cutoff), u32(v.ambient), u32(v.diffuse), u32(v.specular);
    }
    void put(const LightingState &v) {
        u32(v.material_update), u32(v.material_emissive), u32(v.material_diffuse), u32(v.material_specular);
        f32(v.specular_power), u32(v.ambient_color), u32(v.ambient_alpha), u32(v.mode), flag(v.reverse_normals);
        for (const LightState &light : v.lights) put(light);
    }
    void put(const FogState &v) { flag(v.enabled), f32(v.end), f32(v.scale), u32(v.color); }
    void put(const TextureMapState &v) {
        u32(v.map_mode), u32(v.proj_source), u32(v.shade_light_u), u32(v.shade_light_v);
    }
    // The mip level fields of TextureState, which put(TextureState) leaves out
    // so that a Draw's earlier fields keep their place: kLevelBytes bytes.
    void put_levels(const TextureState &v) {
        u32(v.level_count);
        for (const TextureLevel &level : v.levels)
            u32(level.address), u32(level.buffer_width), u16(level.width), u16(level.height);
        u32(v.level_mode), u32(static_cast<std::uint32_t>(v.level_bias)), f32(v.lod_slope);
    }
    void put(const ColorTestState &v) { flag(v.enabled), u32(v.function), u32(v.reference), u32(v.mask); }
    void put(const DitherState &v) {
        flag(v.enabled);
        for (const std::uint32_t row : v.rows) u32(row);
    }
    // Raw vertices and bone matrices are written as the bytes they point at:
    // u32 byte count and the bytes (raw_count x raw_stride, none when the draw
    // was decoded), then u8 1 and the 96 floats when the draw has bones.
    void put(const DrawCall &v) {
        u8(static_cast<std::uint8_t>(v.primitive));
        u32(static_cast<std::uint32_t>(v.vertices.size()));
        for (const Vertex &vertex : v.vertices) put(vertex);
        u32(static_cast<std::uint32_t>(v.indices.size()));
        for (const std::uint16_t index : v.indices) u16(index);
        flag(v.through);
        put(v.texture), put(v.target), put(v.blend), put(v.depth), put(v.alpha_test), put(v.viewport);
        flag(v.culling_enabled), flag(v.cull_clockwise), flag(v.clear_mode), u32(v.clear_flags);
        u32(v.vertex_type), u32(v.vertex_address), u32(v.index_address), u32(v.primitive_count);
        u32(v.material_color), flag(v.lighting_enabled), flag(v.has_vertex_color);
        put(v.lighting), put(v.fog);
        u64(v.environment_version), u64(v.material_version);
        floats(v.world), floats(v.view), floats(v.projection), floats(v.texture_matrix);
        const std::uint32_t raw_bytes = v.raw_vertices != nullptr ? v.raw_count * v.raw_stride : 0u;
        u32(v.raw_count), u32(v.raw_stride), u32(raw_bytes);
        if (raw_bytes != 0u) raw(v.raw_vertices, raw_bytes);
        flag(v.bone_matrices != nullptr);
        if (v.bone_matrices != nullptr)
            for (std::uint32_t i = 0; i < kBoneFloats; ++i) f32(v.bone_matrices[i]);
        put(v.stencil);
        u32(v.color_write_mask), u32(v.alpha_write_mask);
        put(v.texture_map);
        put_levels(v.texture);
        put(v.color_test), put(v.dither), flag(v.clip_enabled);
    }
    void put(const BlockTransfer &v) {
        u32(v.source), u32(v.source_stride), u32(v.source_x), u32(v.source_y);
        u32(v.destination), u32(v.destination_stride), u32(v.destination_x), u32(v.destination_y);
        u32(v.width), u32(v.height), u32(v.bytes_per_pixel);
    }
};

// A Draw as read back: the call, and the bytes its raw vertex and bone
// pointers point into (valid as long as the RecordedDraw is not moved).
struct RecordedDraw {
    DrawCall call;
    std::vector<std::uint8_t> raw_vertices;
    std::array<float, kBoneFloats> bones{};
};

class Reader {
public:
    Reader(const std::uint8_t *data, std::size_t size) : data_(data), size_(size) {}

    [[nodiscard]] bool ok() const noexcept { return !failed_; }
    [[nodiscard]] std::size_t remaining() const noexcept { return size_ - at_; }
    [[nodiscard]] const std::uint8_t *here() const noexcept { return data_ + at_; }
    void skip(std::size_t size) {
        if (size > remaining()) failed_ = true;
        else at_ += size;
    }

    std::uint8_t u8() { return take<std::uint8_t>(); }
    bool flag() { return take<std::uint8_t>() != 0u; }
    std::uint16_t u16() { return take<std::uint16_t>(); }
    std::uint32_t u32() { return take<std::uint32_t>(); }
    std::uint64_t u64() { return take<std::uint64_t>(); }
    float f32() { return take<float>(); }
    std::string string() {
        const std::uint32_t size = u32();
        if (size > remaining()) {
            failed_ = true;
            return {};
        }
        std::string value(reinterpret_cast<const char *>(here()), size);
        at_ += size;
        return value;
    }
    template <std::size_t N> void floats(std::array<float, N> &values) {
        for (float &value : values) value = f32();
    }

    void get(Vertex &v) {
        floats(v.position), floats(v.normal), floats(v.texcoord);
        v.color = u32();
    }
    void get(TextureState &v) {
        v.enabled = flag(), v.address = u32(), v.buffer_width = u32(), v.width = u16(), v.height = u16();
        v.format = static_cast<TextureFormat>(u8()), v.swizzled = flag();
        v.clut_address = u32(), v.clut_format = u32(), v.clut_shift = u32(), v.clut_mask = u32();
        v.clut_offset = u32(), v.clut_format_word = u32(), v.clut_load_bytes = u32(), v.clut_max_bytes = u32();
        v.function = u32(), v.alpha_from_texture = flag(), v.min_filter = u32(), v.mag_filter = u32();
        v.wrap_s = u32(), v.wrap_t = u32();
        v.scale_u = f32(), v.scale_v = f32(), v.offset_u = f32(), v.offset_v = f32();
    }
    void get(RenderTarget &v) {
        v.color_address = u32(), v.color_stride = u32(), v.color_format = u32(), v.depth_address = u32();
        v.depth_stride = u32();
    }
    void get(BlendState &v) {
        v.enabled = flag(), v.source_factor = u32(), v.destination_factor = u32(), v.equation = u32();
        v.fixed_source = u32(), v.fixed_destination = u32();
    }
    void get(DepthState &v) {
        v.test_enabled = flag(), v.write_enabled = flag(), v.function = u32(), v.range_near = u16();
        v.range_far = u16();
    }
    void get(AlphaTestState &v) { v.enabled = flag(), v.function = u32(), v.reference = u32(), v.mask = u32(); }
    void get(StencilState &v) {
        v.enabled = flag(), v.function = u32(), v.reference = u32(), v.mask = u32(), v.fail_op = u32();
        v.depth_fail_op = u32(), v.pass_op = u32();
    }
    void get(ViewportState &v) {
        v.x_scale = f32(), v.y_scale = f32(), v.z_scale = f32(), v.x_offset = f32(), v.y_offset = f32();
        v.z_offset = f32();
        v.scissor_x1 = u32(), v.scissor_y1 = u32(), v.scissor_x2 = u32(), v.scissor_y2 = u32();
        v.offset_x = f32(), v.offset_y = f32();
    }
    void get(LightState &v) {
        v.enabled = flag(), v.kind = u32(), v.type = u32();
        floats(v.position), floats(v.direction), floats(v.attenuation);
        v.spot_exponent = f32(), v.spot_cutoff = f32(), v.ambient = u32(), v.diffuse = u32(), v.specular = u32();
    }
    void get(LightingState &v) {
        v.material_update = u32(), v.material_emissive = u32(), v.material_diffuse = u32();
        v.material_specular = u32(), v.specular_power = f32(), v.ambient_color = u32(), v.ambient_alpha = u32();
        v.mode = u32(), v.reverse_normals = flag();
        for (LightState &light : v.lights) get(light);
    }
    void get(FogState &v) { v.enabled = flag(), v.end = f32(), v.scale = f32(), v.color = u32(); }
    void get(TextureMapState &v) {
        v.map_mode = u32(), v.proj_source = u32(), v.shade_light_u = u32(), v.shade_light_v = u32();
    }
    void get_levels(TextureState &v) {
        v.level_count = u32();
        for (TextureLevel &level : v.levels)
            level.address = u32(), level.buffer_width = u32(), level.width = u16(), level.height = u16();
        v.level_mode = u32(), v.level_bias = static_cast<std::int32_t>(u32()), v.lod_slope = f32();
    }
    void get(ColorTestState &v) { v.enabled = flag(), v.function = u32(), v.reference = u32(), v.mask = u32(); }
    void get(DitherState &v) {
        v.enabled = flag();
        for (std::uint32_t &row : v.rows) row = u32();
    }
    void get(RecordedDraw &draw) {
        DrawCall &v = draw.call;
        v.primitive = static_cast<PrimitiveType>(u8());
        const std::uint32_t vertices = u32();
        if (static_cast<std::uint64_t>(vertices) * 40u > remaining()) {
            failed_ = true;
            return;
        }
        v.vertices.resize(vertices);
        for (Vertex &vertex : v.vertices) get(vertex);
        const std::uint32_t indices = u32();
        if (static_cast<std::uint64_t>(indices) * 2u > remaining()) {
            failed_ = true;
            return;
        }
        v.indices.resize(indices);
        for (std::uint16_t &index : v.indices) index = u16();
        v.through = flag();
        get(v.texture), get(v.target), get(v.blend), get(v.depth), get(v.alpha_test), get(v.viewport);
        v.culling_enabled = flag(), v.cull_clockwise = flag(), v.clear_mode = flag(), v.clear_flags = u32();
        v.vertex_type = u32(), v.vertex_address = u32(), v.index_address = u32(), v.primitive_count = u32();
        v.material_color = u32(), v.lighting_enabled = flag(), v.has_vertex_color = flag();
        get(v.lighting), get(v.fog);
        v.environment_version = u64(), v.material_version = u64();
        floats(v.world), floats(v.view), floats(v.projection), floats(v.texture_matrix);
        v.raw_count = u32(), v.raw_stride = u32();
        const std::uint32_t raw_bytes = u32();
        if (raw_bytes > remaining()) {
            failed_ = true;
            return;
        }
        draw.raw_vertices.assign(here(), here() + raw_bytes);
        at_ += raw_bytes;
        v.raw_vertices = raw_bytes != 0u ? draw.raw_vertices.data() : nullptr;
        if (flag()) {
            for (float &value : draw.bones) value = f32();
            v.bone_matrices = draw.bones.data();
        } else {
            v.bone_matrices = nullptr;
        }
        get(v.stencil);
        v.color_write_mask = u32(), v.alpha_write_mask = u32();
        // Added after the format's first recordings, which end here: they
        // drew every draw with its UVs.
        v.texture_map = {};
        if (remaining() >= 16u) get(v.texture_map);
        // Added after that (the mip levels): recordings without them drew level 0.
        v.texture.level_count = 1u;
        v.texture.levels = {};
        v.texture.level_mode = 0u, v.texture.level_bias = 0, v.texture.lod_slope = 0.0f;
        if (remaining() >= kLevelBytes) get_levels(v.texture);
        // Added after that (the colour test, dithering and CLIPENABLE):
        // recordings without them kept every fragment, dithered nothing and
        // clipped at both depth planes.
        v.color_test = {};
        v.dither = {};
        v.clip_enabled = false;
        if (remaining() >= kPixelBytes) get(v.color_test), get(v.dither), v.clip_enabled = flag();
    }
    void get(BlockTransfer &v) {
        v.source = u32(), v.source_stride = u32(), v.source_x = u32(), v.source_y = u32();
        v.destination = u32(), v.destination_stride = u32(), v.destination_x = u32(), v.destination_y = u32();
        v.width = u32(), v.height = u32(), v.bytes_per_pixel = u32();
    }

private:
    template <typename T> T take() {
        T value{};
        if (sizeof(T) > remaining()) {
            failed_ = true;
            return value;
        }
        std::memcpy(&value, data_ + at_, sizeof(T));
        at_ += sizeof(T);
        return value;
    }

    const std::uint8_t *data_;
    std::size_t size_;
    std::size_t at_{};
    bool failed_{};
};

} // namespace pure::gerec
