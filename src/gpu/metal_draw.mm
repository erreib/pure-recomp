// The Metal backend's draws (docs/metal-backend.md, "How a draw is drawn"): a DrawCall from the GE's state to the
// encoder. The primitives expanded on the CPU (transformed sprites on the screen), the blend, the lighting block,
// the texture and its mapping mode, the pipeline key, the viewport, scissor and depth clamp, and the state set on
// the encoder when it changed; PURE_METAL_LOG's line per draw.
#include "metal_backend.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <iostream>
#include <iterator>

namespace pure::gpu::metal_backend {
namespace {

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

// A column-major matrix times (x, y, z, 1).
std::array<float, 4> transform_point(const std::array<float, 16> &m, const std::array<float, 4> &p) {
    std::array<float, 4> result{};
    for (std::uint32_t row = 0; row < 4u; ++row)
        result[row] = m[row] * p[0] + m[4u + row] * p[1] + m[8u + row] * p[2] + m[12u + row];
    return result;
}

} // namespace

// A GE colour register (0x00BBGGRR) as 0..1 floats, with an explicit fourth value.
std::array<float, 4> unpack_color(std::uint32_t color, float fourth) {
    return {static_cast<float>(color & 0xFFu) / 255.0f, static_cast<float>((color >> 8u) & 0xFFu) / 255.0f,
            static_cast<float>((color >> 16u) & 0xFFu) / 255.0f, fourth};
}

// The draw's vertices into vertices_ as a list of the Metal primitive it is drawn as, the first `drawn`
// of them drawn (a transformed sprite draw's sources follow); false for none. `transform` (projection x
// view x world) is what a transformed sprite is projected with.
bool MetalGeBackend::expand(const DrawCall &call, const std::array<float, 16> &transform, MTLPrimitiveType &type,
                            std::size_t &drawn) {
    vertices_.clear();
    sprite_corners_ = 0u;
    // A vertex without a colour is drawn with the material colour when the draw is unlit; a lit one
    // takes it from the material registers in the shader (Vulkan's rule).
    const bool use_material_color = !call.has_vertex_color && !call.lighting_enabled;
    const std::size_t total = call.vertices.size();
    const std::size_t count = call.indices.empty() ? total : call.indices.size();
    const auto at = [&](std::size_t i) -> const Vertex & {
        const std::size_t index = call.indices.empty() ? i : call.indices[i];
        return call.vertices[std::min(index, total - 1u)];
    };
    const auto convert = [&](const Vertex &vertex) {
        GpuVertex out;
        out.x = vertex.position[0];
        out.y = vertex.position[1];
        out.z = vertex.position[2];
        out.u = vertex.texcoord[0];
        out.v = vertex.texcoord[1];
        out.color = use_material_color ? call.material_color : vertex.color;
        out.nx = vertex.normal[0];
        out.ny = vertex.normal[1];
        out.nz = vertex.normal[2];
        return out;
    };
    const auto push = [&](const Vertex &vertex) { vertices_.push_back(convert(vertex)); };
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
        if (!call.through) {
            expand_transformed_sprites(call, transform, count, at, convert);
            break;
        }
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
    drawn = sprite_corners_ != 0u ? sprite_corners_ : vertices_.size();
    return drawn != 0u;
}

// Transformed sprites, by the GE's rule: both vertices are projected, and the rectangle between them is
// axis-aligned on the screen, at the second vertex's depth, with its colour, lighting and fog. The
// corners go to the shader in the PSP's clip space (VertexUniforms kClipPositions), all with the second
// vertex's w, so that nothing is interpolated in perspective; each names the second vertex, appended
// after the corners in object space, as the vertex it is lit and fogged as. A sprite with a vertex
// behind the eye (w <= 0) is dropped.
template <typename At, typename Convert>
void MetalGeBackend::expand_transformed_sprites(const DrawCall &call, const std::array<float, 16> &transform,
                                                std::size_t count, const At &at, const Convert &convert) {
    sprite_sources_.clear();
    for (std::size_t i = 0; i + 1u < count; i += 2u) {
        const Vertex &a = at(i);
        const Vertex &b = at(i + 1u);
        const std::array<float, 4> clip_a = transform_point(transform, a.position);
        const std::array<float, 4> clip_b = transform_point(transform, b.position);
        if (!(clip_a[3] > 0.0f) || !(clip_b[3] > 0.0f)) continue;
        const float w = clip_b[3];
        const float x0 = clip_a[0] / clip_a[3] * w;
        const float y0 = clip_a[1] / clip_a[3] * w;
        const auto source = static_cast<std::uint32_t>(sprite_sources_.size());
        const GpuVertex second = convert(b);
        sprite_sources_.push_back(second);
        const auto corner = [&](float x, float y, float u, float v) {
            GpuVertex out = second;
            out.x = x;
            out.y = y;
            out.z = clip_b[2];
            out.w = w;
            out.u = u;
            out.v = v;
            out.source = source;
            return out;
        };
        const GpuVertex top_left = corner(x0, y0, a.texcoord[0], a.texcoord[1]);
        const GpuVertex top_right = corner(clip_b[0], y0, b.texcoord[0], a.texcoord[1]);
        const GpuVertex bottom_right = corner(clip_b[0], clip_b[1], b.texcoord[0], b.texcoord[1]);
        const GpuVertex bottom_left = corner(x0, clip_b[1], a.texcoord[0], b.texcoord[1]);
        vertices_.push_back(top_left);
        vertices_.push_back(top_right);
        vertices_.push_back(bottom_right);
        vertices_.push_back(top_left);
        vertices_.push_back(bottom_right);
        vertices_.push_back(bottom_left);
    }
    sprite_corners_ = vertices_.size();
    if (sprite_corners_ == 0u) return;
    for (GpuVertex &vertex : vertices_) vertex.source += static_cast<std::uint32_t>(sprite_corners_);
    vertices_.insert(vertices_.end(), sprite_sources_.begin(), sprite_sources_.end());
}

// The blend: Metal's blend units for the GE's factors and equations. A FIX source factor is applied
// in the fragment shader (exact for any pair of FIX colours) unless the destination factor reads the
// source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour.
void MetalGeBackend::translate_blend(const BlendState &blend, RenderKey &key, FragmentUniforms &fragment,
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

// The lights, the material and the fog of a lit or fogged draw into lighting_ (ge.vert's Environment
// and Object blocks, filled as vulkan_renderer.cpp fills them). An environment-mapped draw (`shade_mapped`)
// reads the world matrix, the lights and the reversed normals whether it is lit or not.
void MetalGeBackend::fill_lighting(const DrawCall &call, bool lit, bool fogged, bool shade_mapped) {
    LightingUniforms block{};
    const pk::LightingState &state = call.lighting;
    if (fogged) block.fog = {call.fog.end, call.fog.scale, 0.0f, 0.0f};
    if (lit || shade_mapped) {
        block.world = call.world;
        block.ambient = unpack_color(state.ambient_color, static_cast<float>(state.ambient_alpha & 0xFFu) / 255.0f);
        block.emissive = unpack_color(state.material_emissive, state.specular_power);
        block.material_ambient =
            unpack_color(call.material_color, static_cast<float>(call.material_color >> 24u) / 255.0f);
        block.material_diffuse = unpack_color(state.material_diffuse);
        block.material_specular = unpack_color(state.material_specular);
        block.flags = {state.material_update & 7u, call.has_vertex_color ? 1u : 0u, (state.mode & 1u) != 0u ? 1u : 0u,
                       state.reverse_normals ? 1u : 0u};
        for (std::size_t i = 0; i < state.lights.size(); ++i) {
            const pk::LightState &light = state.lights[i];
            Light &out = block.lights[i];
            out.position = {light.position[0], light.position[1], light.position[2], 0.0f};
            out.direction = {light.direction[0], light.direction[1], light.direction[2], 0.0f};
            out.attenuation = {light.attenuation[0], light.attenuation[1], light.attenuation[2], 0.0f};
            out.spot = {light.spot_exponent, light.spot_cutoff, 0.0f, 0.0f};
            out.ambient = unpack_color(light.ambient);
            out.diffuse = unpack_color(light.diffuse);
            out.specular = unpack_color(light.specular);
            out.mode = {light.enabled ? 1u : 0u, light.type, light.kind, 0u};
        }
    }
    if (std::memcmp(&block, &lighting_, sizeof(block)) != 0) {
        lighting_ = block;
        lighting_changed_ = true;
    }
}

// The texture mapping mode of a textured, transformed draw (task 036): the texture matrix (1) or the
// environment map (2) computed in ge_vertex, or the UVs (0) as before. A target sampled as the texture is placed in
// its image by the fragment function (FragmentUniforms::uv_remap), whatever the mode.
void MetalGeBackend::set_texture_map(const DrawCall &call, VertexUniforms &vertex, FragmentUniforms &fragment) {
    const pk::TextureMapState &map = call.texture_map;
    if (call.through || switches_.no_texture_map || map.map_mode == 0u) return;
    if (map.map_mode == 3u) {
        not_emulated("texture map mode 3 (drawn with its UVs)", map.map_mode);
        return;
    }
    if (sprite_corners_ != 0u) {
        // The corners of a transformed sprite are made in clip space on the CPU; none of the game's is mapped.
        not_emulated("texture map mode on a transformed sprite (drawn with its UVs)", map.map_mode);
        return;
    }
    vertex.texture_map = {map.map_mode, map.proj_source, map.shade_light_u, map.shade_light_v};
    if (map.map_mode == 1u) {
        vertex.texture_matrix = call.texture_matrix;
        fragment.texture[3] = 1u;  // s and t divided by q per pixel
    } else {
        // The viewer at infinity along view-space +z, in world space: the view matrix's third column (the
        // GE's matrices are rows of a row-vector transform, stored here as columns).
        std::array<float, 3> viewer{call.view[2], call.view[6], call.view[10]};
        const float length = std::sqrt(viewer[0] * viewer[0] + viewer[1] * viewer[1] + viewer[2] * viewer[2]);
        if (length > 0.0f)
            for (float &value : viewer) value /= length;
        vertex.viewer = {viewer[0], viewer[1], viewer[2], 0.0f};
    }
    ++stats_.texture_mapped;
}

void MetalGeBackend::draw(const DrawCall &call, const GuestMemory &memory) {
    // Transformed draws reach the backend decoded (gpu_decode() is false).
    if (call.vertices.empty()) return;
    const std::array<float, 16> view_world = multiply(call.view, call.world);
    const std::array<float, 16> transform = multiply(call.projection, view_world);
    MTLPrimitiveType type{};
    std::size_t drawn = 0u;
    if (!expand(call, transform, type, drawn)) return;

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
    // A 5650, 5551 or 4444 target keeps the format's bits of every write, dithered when the GE says (task 040):
    // ge_fragment_16 blends and quantises; clears keep the bits undithered.
    const bool sixteen = !switches_.no_dither && call.target.color_format < 3u;
    if (sixteen) {
        key.render.sixteen = true;
        const bool dithered = call.dither.enabled && !call.clear_mode;
        fragment.target = {call.target.color_format, dithered ? 1u : 0u, 0u, 0u};
        fragment.dither = call.dither.rows;
        ++stats_.sixteen_bit;
        if (dithered) ++stats_.dithered;
    }
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
        const bool linear_mag = !switches_.sharp && (state.mag_filter & 1u) != 0u;
        const bool linear_min = !switches_.sharp && (state.min_filter & 1u) != 0u;
        source = find_framebuffer_texture(memory, state, source_x, source_y);
        if (source != nullptr) {
            // The texture's first texel is pixel (x, y) of the target's 480x272 guest screen. The coordinates stay
            // the texture's own; the fragment function wraps them by the GE's wrap mode and places them in the
            // target (task 063), whose sampler clamps at its edges. The place is relative: the texture's size and
            // first texel at the sampled target's internal scale over that target's own size (D-015), so a target
            // at 1x and one at 480S x 272S place the same rectangle, whatever the scale of the target drawn into.
            texture = sample_target(*source, target);
            sampler = (linear_mag ? 1u : 0u) | (linear_min ? 2u : 0u) | 4u | 8u;
            const float scale = static_cast<float>(source->scale);
            const float source_width = static_cast<float>(source->width());
            const float source_height = static_cast<float>(source->height());
            const float width = static_cast<float>(state.width) * scale;
            const float height = static_cast<float>(state.height) * scale;
            fragment.uv_remap = {width / source_width, height / source_height,
                                 static_cast<float>(source_x) * scale / source_width,
                                 static_cast<float>(source_y) * scale / source_height};
            fragment.wrap = {1u, state.wrap_s != 0u ? 1u : 0u, state.wrap_t != 0u ? 1u : 0u, 0u};
            ++stats_.framebuffer_textures;
        } else {
            const std::uint32_t levels = mip_levels(memory, state);
            texture = decoded_texture(memory, state, levels);
            sampler = (linear_mag ? 1u : 0u) | (linear_min ? 2u : 0u) | (state.wrap_s != 0u ? 4u : 0u) |
                      (state.wrap_t != 0u ? 8u : 0u);
            if (levels > 1u && texture != white_) {
                // min_filter bit 1: linear between the two levels around D, else the nearest one.
                sampler |= (state.min_filter & 2u) != 0u ? kMipLinear : kMipNearest;
                set_level_rule(state, levels, fragment);
                ++stats_.mipmapped_draws;
            }
        }
        fragment.texture = {state.function, state.alpha_from_texture ? 1u : 0u,
                            source != nullptr && state.format == TextureFormat::Rgba5650 ? 1u : 0u, 0u};
        set_texture_map(call, vertex, fragment);
    }

    // Pipeline state. The target's alpha is the PSP's stencil (patches 0004 and 0006): the stencil
    // attachment does the GE's test and operations, and the alpha is kept equal to it, written by the
    // fragment where the zpass operation is REPLACE or ZERO and copied from the attachment where the draw
    // leaves it behind (`follows`).
    key.render.textured = textured;
    std::uint32_t stencil_reference = 0u;
    bool follows = true;
    set_pipeline_key(call, sixteen, key, fragment, blend_color, stencil_reference, follows);
    id<MTLRenderPipelineState> pipeline = render_pipeline(key.render);
    if (pipeline == nil) return;
    id<MTLDepthStencilState> depth = depth_state(key.depth);

    // Lighting and fog, as ge.vert and ge.frag: transformed draws only, never a clear.
    const bool lit = call.lighting_enabled && !switches_.no_lighting && !call.through && !call.clear_mode;
    const bool fogged = call.fog.enabled && !switches_.no_fog && !call.through && !call.clear_mode;
    const bool shade_mapped = vertex.texture_map[0] == 2u;
    if (lit || fogged || shade_mapped) fill_lighting(call, lit, fogged, shade_mapped);
    if (fogged) {
        fragment.fog = unpack_color(call.fog.color, 1.0f);
        vertex.view_z = {view_world[2], view_world[6], view_world[10], view_world[14]};
    }

    // Positions: screen pixels in through mode; the GE viewport folded into clip space otherwise. Both are in the
    // guest's 480x272 screen; the Metal viewport is the target's own pixels, so at internal scale S it maps the
    // screen onto 480S x 272S and every position is scaled by S there (D-015), the depth untouched.
    MTLViewport viewport{0.0, 0.0, static_cast<double>(target.width()), static_cast<double>(target.height()), 0.0,
                         1.0};
    // CLIPENABLE's depth clamp (task 040) for transformed draws; without it, Metal clips at both planes.
    const bool clamp_depth = !call.through && call.clip_enabled && !switches_.no_depth_clamp;
    vertex.mode = {call.through ? 1u : 0u, sprite_corners_ != 0u ? kClipPositions : 0u,
                   (fogged ? kFog : 0u) | (lit ? kLighting : 0u), 0u};
    if (!call.through) fold_viewport(call, transform, clamp_depth, vertex, viewport);
    const bool cull = call.culling_enabled && !switches_.no_cull && !call.through && type == MTLPrimitiveTypeTriangle &&
                      call.primitive != PrimitiveType::Sprites && !call.clear_mode;

    // Into the target's pass (after the texture, whose copy may have ended it).
    begin_pass(target);
    // A blend that reads the destination's alpha reads the PSP's stencil.
    const bool reads_destination_alpha = sixteen ? shader_blend_reads_destination_alpha(fragment, key.render.write_mask)
                                                 : blend_reads_destination_alpha(key.render);
    if (alpha_stale_ && reads_destination_alpha) resolve_stencil_alpha("destination alpha read");
    if (!follows) alpha_stale_ = true;
    if (key.depth.stencil) ++stats_.stencil_draws;
    if (target.guest_words.empty() || target.last_drawn_frame != frames_) snapshot_guest_words(memory, target);
    target.last_drawn_frame = frames_;
    target.draw_serial = ++draw_counter_;

    const std::size_t bytes = vertices_.size() * sizeof(GpuVertex);
    const auto [buffer, offset] = allocate(bytes);
    std::memcpy(static_cast<std::uint8_t *>(buffer.contents) + offset, vertices_.data(), bytes);

    // The scissor in the target's pixels: each guest pixel an S x S block.
    const std::uint32_t scale = target.scale;
    const ViewportScissor scaled_scissor{scissor.x * scale, scissor.y * scale, scissor.width * scale,
                                         scissor.height * scale};
    bind_state(call, key, pipeline, depth, stencil_reference, viewport, clamp_depth, scaled_scissor, cull,
               blend_color);
    bind_inputs(buffer, offset, vertex, lit || fogged || shade_mapped, fragment, texture, sampler);
    [encoder_ drawPrimitives:type vertexStart:0 vertexCount:drawn];

    if (switches_.log_draws) log_draw(call, target, source, source_x, source_y, scissor);
    ++stats_.draws;
    ++frame_draws_;
}

// The pipeline key's blend, write masks, alpha and colour tests, depth test and stencil, with the fragment uniforms,
// the blend colour and the stencil reference they go with: a clear's (CLEARMODE) or a draw's. `follows` is set false
// when the draw leaves the target's alpha different from its stencil.
void MetalGeBackend::set_pipeline_key(const DrawCall &call, bool sixteen, PipelineKey &key, FragmentUniforms &fragment,
                                      std::uint32_t &blend_color, std::uint32_t &stencil_reference, bool &follows) {
    if (call.clear_mode) {
        // CLEARMODE: no blend, texture or tests; bits 8..10 say what it writes. A clear of the alpha writes
        // the stencil too: ALWAYS, REPLACE with the clear colour's alpha.
        std::uint8_t mask = MTLColorWriteMaskNone;
        if ((call.clear_flags & 1u) != 0u) mask |= MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue;
        if ((call.clear_flags & 2u) != 0u) mask |= MTLColorWriteMaskAlpha;
        key.render.write_mask = mask;
        key.depth.compare = MTLCompareFunctionAlways;
        key.depth.write = (call.clear_flags & 4u) != 0u;
        if ((call.clear_flags & 2u) != 0u && call.target.color_format != 0u) {
            const std::uint32_t color =
                !call.has_vertex_color && !call.lighting_enabled ? call.material_color : call.vertices.back().color;
            key.depth.stencil = true;
            key.depth.stencil_function = 1u;  // ALWAYS
            key.depth.fail = key.depth.depth_fail = key.depth.pass = 2u;  // REPLACE
            key.depth.compare_mask = 0xFFu;
            key.depth.write_mask = 0xFFu;
            stencil_reference = color >> 24u;
        }
    } else {
        // A 16-bit target blends in the shader (task 040); any other through the pipeline's blend.
        if (sixteen) shader_blend(call.blend, fragment);
        else translate_blend(call.blend, key.render, fragment, blend_color);
        // Whole colour channels the write mask keeps are not written; the alpha, the PSP's stencil, only
        // by the stencil operations.
        std::uint8_t mask = MTLColorWriteMaskNone;
        static constexpr MTLColorWriteMask kChannels[] = {MTLColorWriteMaskRed, MTLColorWriteMaskGreen,
                                                          MTLColorWriteMaskBlue};
        for (std::uint32_t channel = 0; channel < 3u; ++channel) {
            const std::uint32_t bits = (call.color_write_mask >> (8u * channel)) & 0xFFu;
            if (bits != 0xFFu) mask |= kChannels[channel];
            if (bits != 0u && bits != 0xFFu) not_emulated("partial colour write mask", call.color_write_mask);
        }
        const int stored = stencil_alpha(call);
        if (stored >= 0) {
            mask |= MTLColorWriteMaskAlpha;
            fragment.stencil = {1u, static_cast<std::uint32_t>(stored), 0u, 0u};
            // A colour blend that reads the source alpha reads the fragment's own from the second output (the
            // shader's own blend reads it directly).
            key.render.dual_source = !sixteen && blend_reads_source_alpha(key.render, mask);
        }
        key.render.write_mask = mask;
        key.render.alpha_test = call.alpha_test.enabled && call.alpha_test.function != 1u;
        fragment.alpha_test = {call.alpha_test.function, call.alpha_test.reference & 0xFFu,
                               call.alpha_test.mask & 0xFFu, 0u};
        // The colour test (task 040), ALWAYS compiled out as the alpha test's.
        key.render.color_test =
            !switches_.no_color_test && call.color_test.enabled && (call.color_test.function & 3u) != 1u;
        fragment.color_test = {call.color_test.function & 3u, call.color_test.reference & 0x00FFFFFFu,
                               call.color_test.mask & 0x00FFFFFFu, 0u};
        if (key.render.color_test) ++stats_.color_tested;
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
            key.depth.compare_mask = static_cast<std::uint8_t>(call.stencil.mask);
            key.depth.write_mask = static_cast<std::uint8_t>(~call.alpha_write_mask);
            stencil_reference = stored_reference(call);
            follows = alpha_follows_stencil(call, key.depth.compare != MTLCompareFunctionAlways);
        }
    }
}

// A transformed draw's positions: the GE viewport folded into clip space, and its depth clamped as CLIPENABLE
// clamps it (`clamp_depth`) or mapped by the viewport's depth range.
void MetalGeBackend::fold_viewport(const DrawCall &call, const std::array<float, 16> &transform, bool clamp_depth,
                                   VertexUniforms &vertex, MTLViewport &viewport) {
    vertex.transform = transform;
    const pk::ViewportState &vp = call.viewport;
    if (vp.x_scale != 0.0f && vp.y_scale != 0.0f) {
        // screen = ndc * scale + offset - region offset, then to Metal's y-up device space: the guest's 480x272
        // screen, which the viewport maps onto the target's pixels (x S at internal scale S, D-015).
        vertex.screen = {2.0f * vp.x_scale / static_cast<float>(kWidth),
                         2.0f * (vp.x_offset - vp.offset_x) / static_cast<float>(kWidth) - 1.0f,
                         -2.0f * vp.y_scale / static_cast<float>(kHeight),
                         1.0f - 2.0f * (vp.y_offset - vp.offset_y) / static_cast<float>(kHeight)};
    } else {
        vertex.screen = {1.0f, 0.0f, -1.0f, 0.0f};
    }
    if (clamp_depth) {
        // CLIPENABLE on (task 040): the shader computes the GE's screen z, clamps it per vertex and hands
        // it over as depth z / 65535 in a viewport of 0..1; the near plane and MINZ/MAXZ are clip
        // distances, and Metal does not clip at the depth range's ends (depthClipMode clamp).
        vertex.mode[3] = 1u;
        vertex.depth = {vp.z_scale, vp.z_offset, static_cast<float>(call.depth.range_near),
                        static_cast<float>(call.depth.range_far)};
        ++stats_.depth_clamped;
    } else {
        if (!call.clip_enabled && !switches_.no_depth_clamp)
            not_emulated("CLIPENABLE off on a transformed draw (drawn clipped at both depth planes)", 0u);
        if (vp.z_scale != 0.0f) {
            // The shader hands over z in [0, w] for the PSP's [-w, w]; this applies the GE's z scale
            // and offset, reversed when the game set a reversed range.
            viewport.znear = std::clamp((vp.z_offset - vp.z_scale) / 65535.0, 0.0, 1.0);
            viewport.zfar = std::clamp((vp.z_offset + vp.z_scale) / 65535.0, 0.0, 1.0);
        }
    }
}

// The encoder's state for a draw, each part set only when it differs from what the pass has bound (bound_): the
// pipeline, the depth-stencil state, the stencil reference, the viewport, the depth clip mode, the scissor, cull and
// winding, the blend colour.
void MetalGeBackend::bind_state(const DrawCall &call, const PipelineKey &key, id<MTLRenderPipelineState> pipeline,
                                id<MTLDepthStencilState> depth, std::uint32_t stencil_reference,
                                const MTLViewport &viewport, bool clamp_depth, const ViewportScissor &scissor,
                                bool cull, std::uint32_t blend_color) {
    if (bound_.pipeline != pipeline) {
        [encoder_ setRenderPipelineState:pipeline];
        bound_.pipeline = pipeline;
    }
    if (bound_.depth != depth) {
        [encoder_ setDepthStencilState:depth];
        bound_.depth = depth;
    }
    if (key.depth.stencil && (!bound_.stencil_reference_set || bound_.stencil_reference != stencil_reference)) {
        [encoder_ setStencilReferenceValue:stencil_reference];
        bound_.stencil_reference = stencil_reference;
        bound_.stencil_reference_set = true;
    }
    if (!bound_.viewport_set || bound_.viewport.znear != viewport.znear || bound_.viewport.zfar != viewport.zfar) {
        [encoder_ setViewport:viewport];
        bound_.viewport = viewport;
        bound_.viewport_set = true;
    }
    const MTLDepthClipMode depth_clip = clamp_depth ? MTLDepthClipModeClamp : MTLDepthClipModeClip;
    if (!bound_.depth_clip_set || bound_.depth_clip != depth_clip) {
        [encoder_ setDepthClipMode:depth_clip];
        bound_.depth_clip = depth_clip;
        bound_.depth_clip_set = true;
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
        // backend's flipping viewport count it too: confirmed on the race (task 024), whose first
        // 393 draws of frame 6016 match Vulkan's while the reversed winding differs from draw 41 on.
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
}

// What the shaders read, after bind_state(): the vertices at `offset` in `buffer`, the vertex uniforms, the lighting
// block (`lighting_read`: the draw is lit, fogged or environment-mapped), the fragment uniforms, the texture and its
// sampler.
void MetalGeBackend::bind_inputs(id<MTLBuffer> buffer, NSUInteger offset, const VertexUniforms &vertex,
                                 bool lighting_read, const FragmentUniforms &fragment, id<MTLTexture> texture,
                                 std::uint32_t sampler) {
    if (bound_.buffer != buffer) {
        [encoder_ setVertexBuffer:buffer offset:offset atIndex:0];
        bound_.buffer = buffer;
    } else {
        [encoder_ setVertexBufferOffset:offset atIndex:0];
    }
    [encoder_ setVertexBytes:&vertex length:sizeof(vertex) atIndex:1];
    // The lighting block: a lit, fogged or environment-mapped draw's whenever it changed, and something
    // always, since the vertex function names it.
    if (!lighting_bound_ || (lighting_read && lighting_changed_)) {
        [encoder_ setVertexBytes:&lighting_ length:sizeof(lighting_) atIndex:2];
        lighting_bound_ = true;
        lighting_changed_ = false;
    }
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
}

MetalGeBackend::ViewportScissor MetalGeBackend::scissor_of(const DrawCall &call) {
    const std::uint32_t x1 = call.viewport.scissor_x1;
    const std::uint32_t y1 = call.viewport.scissor_y1;
    const std::uint32_t x2 = std::min(call.viewport.scissor_x2, kWidth - 1u);
    const std::uint32_t y2 = std::min(call.viewport.scissor_y2, kHeight - 1u);
    if (x1 > x2 || y1 > y2) return {};
    return {x1, y1, x2 - x1 + 1u, y2 - y1 + 1u};
}

void MetalGeBackend::log_draw(const DrawCall &call, const Target &target, const Target *source, std::uint32_t x,
                              std::uint32_t y, const ViewportScissor &scissor) {
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
            if (call.texture.level_count > 1u)
                std::cout << " levels " << call.texture.level_count << " mode " << call.texture.level_mode
                          << " bias " << call.texture.level_bias;
            if (!call.through && call.texture_map.map_mode == 1u)
                std::cout << " texmatrix " << call.texture_map.proj_source;
            else if (!call.through && call.texture_map.map_mode == 2u)
                std::cout << " envmap " << call.texture_map.shade_light_u << "," << call.texture_map.shade_light_v;
        }
        if (call.blend.enabled)
            std::cout << " blend " << call.blend.source_factor << "/" << call.blend.destination_factor << " eq "
                      << call.blend.equation << " fix " << std::hex << call.blend.fixed_source << "/"
                      << call.blend.fixed_destination << std::dec;
        else
            std::cout << " opaque";
        if (call.alpha_test.enabled)
            std::cout << " at " << call.alpha_test.function << " ref " << call.alpha_test.reference;
        if (call.color_test.enabled)
            std::cout << " ctest " << call.color_test.function << " ref " << std::hex << call.color_test.reference
                      << " mask " << call.color_test.mask << std::dec;
        if (call.dither.enabled && call.target.color_format < 3u) std::cout << " dither";
        if (!call.through && !call.clip_enabled) std::cout << " noclip";
        if (call.depth.test_enabled) std::cout << " z " << call.depth.function << (call.depth.write_enabled ? " w" : "");
        if (call.stencil.enabled) std::cout << " stencil " << call.stencil.function;
        if (call.color_write_mask != 0u) std::cout << " cmask " << std::hex << call.color_write_mask << std::dec;
        if (!call.through && call.lighting_enabled) std::cout << " lit";
        if (!call.through && call.fog.enabled) std::cout << " fog";
        if (!call.through && call.culling_enabled && call.primitive != PrimitiveType::Sprites)
            std::cout << (call.cull_clockwise ? " cull cw" : " cull ccw");
    }
    std::cout << " scissor " << scissor.x << "," << scissor.y << "+" << scissor.width << "x" << scissor.height
              << "\n";
}

} // namespace pure::gpu::metal_backend
