// The Metal GE backend's shaders (metal_backend.mm), as MSL source compiled when the backend starts:
// the machine needs no Xcode for it, only the Metal compiler that comes with macOS.
//
// Ported from the framework's GLSL (vendor/portablekit/host/gpu/shaders/ge.vert and ge.frag, MIT):
// through-mode and transformed vertices, the GE's per-vertex lighting (four lights, the material colours
// and the update bits, ambient, diffuse, specular with the material's power, reverse normals) and fog
// (tasks 023 and 024), transformed sprites as rectangles already projected (their lighting and fog taken
// from the second vertex), the GE's texture mapping modes (task 036: the texture matrix and the environment map,
// which the framework's shaders do not have), the mip level by the GE's rule (task 037), the five texture
// functions, the alpha test by the GE's numbering (0 NEVER, 1 ALWAYS: patch 0005) and the FIX source factor;
// the stencil value stored as the target's alpha instead of the fragment's, with the fragment's own alpha handed
// to a source-alpha blend as a second output (dual-source blending, ge_fragment_dual) as patches 0004 and 0006 do
// (task 025). Task 040 added the colour test, the writes into 16-bit targets (ge_fragment_16: the blend done in the
// shader on the target's colour, the dither matrix's offset, and the target's own bits kept) and the depth clamp of
// CLIPENABLE (the near plane and MINZ/MAXZ as clip distances, each vertex's screen z clamped). Logic ops and colour
// doubling are not in the draw state.
//
// The structs below are laid out exactly as their C++ twins in metal_backend.mm (static_asserts there).
#pragma once

namespace pure::metal {

inline const char *const kShaderSource = R"metal(
#include <metal_stdlib>
using namespace metal;

// One vertex as the backend writes it: GpuVertex in metal_backend.mm.
struct GeVertex {
    float4 position;   // through mode: screen pixels and z 0..65535; transformed: object space, or the PSP's
                       // clip space for the corners of a transformed sprite (VertexUniforms::mode.y)
    float2 uv;         // through mode: texels; transformed: as the vertex holds it
    uint color;        // 0xAABBGGRR
    uint source;       // a transformed sprite's corner: the vertex (in this buffer) it is lit and fogged as
    float4 normal;     // xyz, object space
};

// VertexUniforms in metal_backend.mm.
struct VertexUniforms {
    float4x4 transform;   // projection * view * world, column major as the GE's matrices
    // The GE viewport folded into clip space for a 480x272 target (transformed draws):
    //   X = clip.x * screen.x + clip.w * screen.y,  Y = clip.y * screen.z + clip.w * screen.w
    float4 screen;
    float4 uv_transform;  // uv * xy + zw
    uint4 mode;           // x: 1 through mode; y: 1 positions in clip space (sprite corners); z: 1 fog, 2 lighting
    float4 view_z;        // the row of view * world that gives view-space z, for fog
    // The texture mapping mode (task 036), for transformed draws: x the mode (0 the UVs through uv_transform,
    // 1 the texture matrix, 2 the environment map), y the texture matrix's source (0 position, 1 UV, 2 normalized
    // normal, 3 normal), z and w the lights s and t come from in mode 2.
    uint4 texture_map;
    float4x4 texture_matrix;  // the GE's 4x3 texture matrix, column major as the others
    float4 viewer;        // xyz: the viewer's direction in world space (the view matrix's third column, normalized)
    float4 uv_remap;      // modes 1 and 2: the texture's coordinates into the image sampled, uv * xy + zw (a target
                          // sampled as a texture covers part of it); identity otherwise
    // The depth clamp (task 040), for transformed draws with mode.w 1 (CLIPENABLE on): x and y the GE viewport's z
    // scale and offset, z and w MINZ and MAXZ.
    float4 depth;
};

// One of the GE's lights: Light in metal_backend.mm. Colours are 0..1.
struct Light {
    float4 position;      // xyz: the direction towards the light for a directional one, else its position
    float4 direction;     // xyz: a spot light's axis
    float4 attenuation;   // xyz: constant, linear, quadratic
    float4 spot;          // x: exponent, y: cosine of the cone's half angle
    float4 ambient;
    float4 diffuse;
    float4 specular;
    uint4 mode;           // x: enabled, y: type (0 directional, 1 point, 2 spot), z: kind (0 diffuse,
                          // 1 diffuse and specular, 2 powered diffuse)
};

// LightingUniforms in metal_backend.mm: the lights, the material and the fog a lit or fogged draw reads.
struct LightingUniforms {
    float4x4 world;
    float4 ambient;            // the global ambient light, rgba
    float4 emissive;           // rgb; w: the specular power
    float4 material_ambient;   // rgba (DrawCall::material_color)
    float4 material_diffuse;
    float4 material_specular;
    float4 fog;                // x: end, y: scale
    uint4 flags;               // x: material update mask, y: 1 the vertex has a colour, z: 1 specular kept apart,
                               // w: 1 reversed normals
    Light lights[4];
};

// FragmentUniforms in metal_backend.mm.
struct FragmentUniforms {
    float4 fix;           // rgb: the FIX source factor the colour is multiplied by; w: 1 when it is
    uint4 texture;        // x: texture function (TFX), y: 1 alpha from the texture (TCC), z: 1 texel alpha is one,
                          // w: 1 the coordinates are projective (s, t, q: the texture matrix), divided by q
    uint4 alpha_test;     // x: GE function, y: reference, z: mask
    float4 fog;           // rgb: the fog colour; w: 1 when the draw is fogged
    uint4 stencil;        // x: 1 when the target's alpha, the PSP's stencil, receives y (0..255) instead of the
                          // fragment's alpha (the zpass REPLACE or ZERO the stencil attachment does too)
    // The mip level (task 037): x the rule (0 none: level 0, Metal's own derivatives; 1 auto, 2 constant, 3 slope:
    // TEXLEVEL's modes), y the part of D (1/16 levels) that is the same across the draw, zw level 0's size.
    float4 level;
    float4 level_range;   // x: the highest D, 16 x (levels - 1)
    uint4 color_test;     // the colour test (task 040): x the GE function (0 NEVER, 2 EQUAL, 3 NOTEQUAL; 1 ALWAYS is
                          // compiled out), y the reference, z the mask, both 0x00BBGGRR
    // A draw into a 16-bit target (ge_fragment_16, task 040), which blends in the shader:
    uint4 blend;          // x: 1 when blended, y: the GE's source factor, z: its destination factor, w: the equation
    float4 fix_source;    // rgb: FIXA
    float4 fix_destination;  // rgb: FIXB
    uint4 dither;         // DITH0 to DITH3: the matrix's rows for y & 3, four signed 4-bit offsets each, x & 3's at
                          // bits 4 x (x & 3)
    uint4 target;         // x: the target's format (0 5650, 1 5551, 2 4444), y: 1 when the draw dithers
};

// What ge_fragment_dual hands the blend: the colour with the stored alpha, and the fragment's own alpha as the
// second source (MTLBlendFactorSource1Alpha), which a source-alpha blend reads instead.
struct DualOutput {
    float4 color [[color(0), index(0)]];
    float4 source [[color(0), index(1)]];
};

// Specialisation: a pipeline without a texture, an alpha test or a colour test has none of them in its fragment
// function.
constant bool kTextured [[function_constant(0)]];
constant bool kAlphaTest [[function_constant(1)]];
constant bool kColorTest [[function_constant(2)]];

struct Varyings {
    float4 position [[position]];
    float3 uv;            // s, t, q; q is 1 but for the texture matrix (FragmentUniforms::texture.w)
    float4 color;
    float3 specular;      // a separate specular term, added after texturing
    float fog;            // 1 clear, 0 fogged
    float point_size [[point_size]];
};

// What ge_vertex hands on: Varyings, and the clip distances of the depth clamp (task 040), which the fragment
// functions do not read: [0] the near plane, [1] MINZ, [2] MAXZ, each kept where it is not negative.
struct VertexOut {
    float4 position [[position]];
    float3 uv;
    float4 color;
    float3 specular;
    float fog;
    float point_size [[point_size]];
    float clip_distance [[clip_distance]] [3];
};

// The GE's per-vertex lighting, as ge.vert evaluates it, in world space: emissive, plus the global ambient
// light times the material ambient, plus for each enabled light its ambient, diffuse and specular terms,
// scaled by distance attenuation and the spot cone. The material update mask makes the vertex colour stand
// in for the ambient (bit 0), diffuse (bit 1) and specular (bit 2) material colours; a vertex without a
// colour keeps the material ones.
float4 light_vertex(const GeVertex v, constant LightingUniforms &l, thread float3 &separate_specular) {
    const float4 vertex_color = unpack_unorm4x8_to_float(v.color);
    const uint mask = l.flags.x;
    const bool has_color = l.flags.y != 0u;
    const float4 ambient_material = (has_color && (mask & 1u) != 0u) ? vertex_color : l.material_ambient;
    const float3 diffuse_material = (has_color && (mask & 2u) != 0u) ? vertex_color.rgb : l.material_diffuse.rgb;
    const float3 specular_material = (has_color && (mask & 4u) != 0u) ? vertex_color.rgb : l.material_specular.rgb;
    const float power = l.emissive.w;

    const float3 world_position = (l.world * float4(v.position.xyz, 1.0f)).xyz;
    // Skinned normals come out of the bone matrices far from unit length, so the GE's normalisation after
    // the transform matters.
    const float3x3 world3 = float3x3(l.world[0].xyz, l.world[1].xyz, l.world[2].xyz);
    float3 normal = world3 * v.normal.xyz;
    const float length_squared = dot(normal, normal);
    normal = length_squared > 0.0f ? normal * rsqrt(length_squared) : float3(0.0f, 0.0f, 1.0f);
    if (l.flags.w != 0u) normal = -normal;

    float3 sum = l.emissive.rgb + l.ambient.rgb * ambient_material.rgb;
    float3 specular = float3(0.0f);
    for (uint i = 0; i < 4u; ++i) {
        const Light light = l.lights[i];
        if (light.mode.x == 0u) continue;
        const uint type = light.mode.y;
        const uint kind = light.mode.z;
        float3 to_light = light.position.xyz;
        float scale = 1.0f;
        if (type != 0u) {
            to_light -= world_position;
            const float distance = length(to_light);
            const float3 k = light.attenuation.xyz;
            scale = clamp(1.0f / max(k.x + k.y * distance + k.z * distance * distance, 1e-20f), 0.0f, 1.0f);
        }
        to_light = dot(to_light, to_light) > 0.0f ? normalize(to_light) : float3(0.0f, 0.0f, 1.0f);
        if (type == 2u) {
            float3 axis = light.direction.xyz;
            axis = dot(axis, axis) > 0.0f ? normalize(axis) : float3(0.0f, 0.0f, 1.0f);
            const float angle = dot(axis, -to_light);
            scale *= angle >= light.spot.y ? pow(max(angle, 0.0f), light.spot.x) : 0.0f;
        }
        const float n_dot_l = dot(normal, to_light);
        float diffuse = max(n_dot_l, 0.0f);
        if (kind == 2u) diffuse = pow(diffuse, power);
        sum += (light.ambient.rgb * ambient_material.rgb + light.diffuse.rgb * diffuse_material * diffuse) * scale;
        if (kind == 1u && n_dot_l >= 0.0f) {
            // The viewer is taken to look down z, as the GE does.
            const float3 half_vector = normalize(to_light + float3(0.0f, 0.0f, 1.0f));
            specular += light.specular.rgb * specular_material * pow(max(dot(normal, half_vector), 0.0f), power) * scale;
        }
    }
    const float alpha = l.ambient.a * ambient_material.a;
    if (l.flags.z != 0u) {
        separate_specular = clamp(specular, 0.0f, 1.0f);
    } else {
        sum += specular;
        separate_specular = float3(0.0f);
    }
    return clamp(float4(sum, alpha), 0.0f, 1.0f);
}

// A unit vector, a zero vector staying zero (the GE's rule for the shade lights).
float3 unit_or_zero(float3 v) {
    const float length_squared = dot(v, v);
    return length_squared > 0.0f ? v * rsqrt(length_squared) : float3(0.0f);
}

// The texture coordinates of the texture matrix (mode 1) and the environment map (mode 2), by the GE's rules as
// PPSSPP's hardware notes give them (docs/metal-backend.md, "Texture mapping modes"). Neither takes the texture
// scale and offset; uv_remap only places the texture in the image sampled.
float3 map_texture(const GeVertex v, constant VertexUniforms &u, constant LightingUniforms &l) {
    if (u.texture_map.x == 1u) {
        // The source, as three components with the matrix's translation added (a fourth component of 1), times
        // the matrix: s, t and q, interpolated and divided per pixel.
        float3 source;
        switch (u.texture_map.y) {
        case 0u: source = v.position.xyz; break;
        case 1u: source = float3(v.uv, 0.0f); break;
        case 2u: source = unit_or_zero(v.normal.xyz); break;
        default: source = v.normal.xyz; break;
        }
        const float3 stq = (u.texture_matrix * float4(source, 1.0f)).xyz;
        return float3(fma(stq.x, u.uv_remap.x, stq.z * u.uv_remap.z), fma(stq.y, u.uv_remap.y, stq.z * u.uv_remap.w),
                      stq.z);
    }
    // The environment map: s and t are (N.L' + 1) / 2 for the two shade lights, in world space, where N is the
    // normal through the world matrix (the dot product divided by its length), and L' the light's position for a
    // directional light, else the direction from the vertex to it, normalized, and for a diffuse-and-specular
    // light normalized again after the viewer's direction is added. Lighting, the lights' enables and colours,
    // attenuation and the spot cone play no part.
    const float3x3 world3 = float3x3(l.world[0].xyz, l.world[1].xyz, l.world[2].xyz);
    float3 normal = world3 * v.normal.xyz;
    if (l.flags.w != 0u) normal = -normal;
    const float length_squared = dot(normal, normal);
    const float inverse_length = length_squared > 0.0f ? rsqrt(length_squared) : 0.0f;
    const float3 world_position = (l.world * float4(v.position.xyz, 1.0f)).xyz;
    float2 st;
    for (uint i = 0; i < 2u; ++i) {
        const Light light = l.lights[i == 0u ? u.texture_map.z : u.texture_map.w];
        float3 to_light = light.position.xyz;
        if (light.mode.y != 0u) to_light -= world_position;
        to_light = unit_or_zero(to_light);
        if (light.mode.z == 1u) to_light = unit_or_zero(to_light + u.viewer.xyz);
        st[i] = (dot(normal, to_light) * inverse_length + 1.0f) * 0.5f;
    }
    return float3(fma(st, u.uv_remap.xy, u.uv_remap.zw), 1.0f);
}

vertex VertexOut ge_vertex(uint vid [[vertex_id]],
                           const device GeVertex *vertices [[buffer(0)]],
                           constant VertexUniforms &u [[buffer(1)]],
                           constant LightingUniforms &l [[buffer(2)]]) {
    const GeVertex v = vertices[vid];
    VertexOut out;
    out.uv = float3(fma(v.uv, u.uv_transform.xy, u.uv_transform.zw), 1.0f);
    out.color = unpack_unorm4x8_to_float(v.color);
    out.specular = float3(0.0f);
    out.fog = 1.0f;
    out.point_size = 1.0f;
    for (uint i = 0; i < 3u; ++i) out.clip_distance[i] = 1.0f;
    if (u.mode.x != 0u) {
        // Screen pixels to clip space; a pixel's centre is at +0.5, as the PSP samples it.
        out.position = float4(v.position.x * (2.0f / 480.0f) - 1.0f,
                              1.0f - v.position.y * (2.0f / 272.0f),
                              clamp(v.position.z / 65535.0f, 0.0f, 1.0f), 1.0f);
        return out;
    }
    // A sprite's corners are lit and fogged as its second vertex, which `source` names.
    const GeVertex lit = u.mode.y != 0u ? vertices[v.source] : v;
    if ((u.mode.z & 2u) != 0u) out.color = light_vertex(lit, l, out.specular);
    // Fog runs linearly from 1 (clear) to 0 (fogged) with view-space z, which is negative in front of the
    // camera: (z + end) * scale.
    if ((u.mode.z & 1u) != 0u) out.fog = (dot(u.view_z, float4(lit.position.xyz, 1.0f)) + l.fog.x) * l.fog.y;
    // Modes 1 and 2 (never set for sprite corners: metal_backend.mm draws those with their UVs).
    if (u.texture_map.x != 0u) out.uv = map_texture(v, u, l);
    const float4 clip = u.mode.y != 0u ? v.position : u.transform * float4(v.position.xyz, 1.0f);
    // PSP clip space follows OpenGL with z in [-w, w]; Metal clips z against [0, w]. The GE's z scale and
    // offset are the viewport's znear and zfar (metal_backend.mm).
    out.position = float4(fma(clip.x, u.screen.x, clip.w * u.screen.y),
                          fma(clip.y, u.screen.z, clip.w * u.screen.w),
                          (clip.z + clip.w) * 0.5f, clip.w);
    if (u.mode.w != 0u) {
        // CLIPENABLE on (task 040; PPSSPP's hardware notes, "Z Clipper", "Clipping enabled", "MinZ and MaxZ", "Z
        // Clamp"): the GE clips at the near plane (z = -w) only, clamps each vertex's screen z to 0..65535 before it
        // is interpolated, and leaves the far side to the per-pixel MINZ/MAXZ test. Metal does not clip z here
        // (MTLDepthClipModeClamp, a viewport of 0..1); the near plane and the MINZ/MAXZ test are clip distances on
        // the screen z, which, like the depth, is linear across the screen. zw is that z times w; a vertex behind
        // the near plane keeps it unclamped, so the near plane's clipper interpolates it as the GE does.
        float zw = fma(clip.z, u.depth.x, clip.w * u.depth.y);
        if (clip.w > 0.0f && clip.z >= -clip.w) zw = clamp(zw, 0.0f, 65535.0f * clip.w);
        out.position.z = zw / 65535.0f;
        out.clip_distance[0] = clip.z + clip.w;
        out.clip_distance[1] = zw - u.depth.z * clip.w;
        out.clip_distance[2] = u.depth.w * clip.w - zw;
    }
    return out;
}

// The GE's logarithm for the mip level, in 1/16 levels: the float's exponent and the top four bits of its mantissa
// (a piecewise linear log2, floored to 1/16), of |x|. ge_log16 in metal_backend.mm.
float ge_log16(float x) {
    return float(int((as_type<uint>(x) >> 19u) & 0xFFFu) - 127 * 16);
}

// The texel, at the mip level the GE picks for a texture with levels (task 037; PPSSPP's hardware notes, "Mip level
// selection"): D = log16(g) - log16(q) (auto), the bias (constant) or 16 + log16(slope) - log16(q) + bias (slope),
// u.level.y holding what does not change across the draw. q is the GE's per-pixel q: 1/w (position.w, which Metal
// gives as 1/w), times the texture matrix's q; s and t are the texture coordinates times q, whose screen
// gradients g takes, in texels. D is clamped to the levels the texture has; the sampler's mip filter takes the
// nearest level or blends the two around it.
float4 sample_texture(Varyings in, constant FragmentUniforms &u, texture2d<float> image, sampler image_sampler) {
    const float2 uv = u.texture.w != 0u ? in.uv.xy / in.uv.z : in.uv.xy;
    if (u.level.x == 0.0f) return image.sample(image_sampler, uv);
    const float q = in.position.w * in.uv.z;
    float d = u.level.y;
    if (u.level.x == 1.0f) {
        const float2 st = in.uv.xy * in.position.w;
        const float2 across = abs(dfdx(st)) * u.level.zw;
        const float2 down = abs(dfdy(st)) * u.level.zw;
        d += ge_log16(max(max(across.x, across.y), max(down.x, down.y)));
    }
    if (u.level.x != 2.0f) d -= ge_log16(q);
    return image.sample(image_sampler, uv, level(clamp(d, 0.0f, u.level_range.x) / 16.0f));
}

// The fragment's colour and alpha as the GE computes them: texture function, separate specular, fog, alpha
// test (which discards), FIX source factor. The alpha is the fragment's own; the entry points below decide what
// the target's alpha receives.
float4 shade(Varyings in, constant FragmentUniforms &u, texture2d<float> image, sampler image_sampler) {
    float4 color = in.color;
    if (kTextured) {
        float4 texel = sample_texture(in, u, image, image_sampler);
        // A 16-bit 5650 framebuffer sampled as a texture has no alpha.
        if (u.texture.z != 0u) texel.a = 1.0f;
        const bool rgba = u.texture.y != 0u;
        switch (u.texture.x) {
        case 0u:  // modulate
            color = float4(color.rgb * texel.rgb, rgba ? color.a * texel.a : color.a);
            break;
        case 1u:  // decal
            color = float4(rgba ? mix(color.rgb, texel.rgb, texel.a) : texel.rgb, color.a);
            break;
        case 2u:  // blend: the environment colour is not in the draw state; the texel stands in, as in ge.frag
            color = float4(mix(color.rgb, texel.rgb, texel.rgb), rgba ? color.a * texel.a : color.a);
            break;
        case 4u:  // add
            color = float4(min(color.rgb + texel.rgb, float3(1.0f)), rgba ? color.a * texel.a : color.a);
            break;
        default:  // replace (3) and the undefined 5..7
            color = float4(texel.rgb, rgba ? texel.a : color.a);
            break;
        }
    }
    // A separate specular term is added after texturing, then fog blends towards its colour; neither
    // touches alpha.
    color.rgb = min(color.rgb + in.specular, float3(1.0f));
    if (u.fog.w != 0.0f) color.rgb = mix(u.fog.rgb, color.rgb, saturate(in.fog));
    if (kColorTest) {
        // The colour test (task 040): the fragment's 8-bit colour under the mask against the reference under the
        // mask, after fog, as the alpha test below; a fragment that fails writes nothing (no colour, depth or
        // stencil).
        const uint3 c = uint3(rint(saturate(color.rgb) * 255.0f));
        const uint value = (c.r | (c.g << 8u) | (c.b << 16u)) & u.color_test.z;
        const uint reference = u.color_test.y & u.color_test.z;
        bool passed = true;
        switch (u.color_test.x) {
        case 0u: passed = false; break;
        case 2u: passed = value == reference; break;
        case 3u: passed = value != reference; break;
        default: break;
        }
        if (!passed) discard_fragment();
    }
    if (kAlphaTest) {
        // The GE's own numbering, as the depth test's: 0 NEVER, 1 ALWAYS, EQUAL, NOTEQUAL, LESS,
        // LEQUAL, GREATER, GEQUAL, on the 8-bit alpha and reference under the mask.
        const uint alpha = uint(rint(saturate(color.a) * 255.0f)) & u.alpha_test.z;
        const uint reference = u.alpha_test.y & u.alpha_test.z;
        bool passed = true;
        switch (u.alpha_test.x) {
        case 0u: passed = false; break;
        case 2u: passed = alpha == reference; break;
        case 3u: passed = alpha != reference; break;
        case 4u: passed = alpha < reference; break;
        case 5u: passed = alpha <= reference; break;
        case 6u: passed = alpha > reference; break;
        case 7u: passed = alpha >= reference; break;
        default: break;
        }
        if (!passed) discard_fragment();
    }
    // A FIX source factor: the colour arrives multiplied, and the blend takes it ONE.
    if (u.fix.w != 0.0f) color.rgb *= u.fix.rgb;
    return color;
}

// The PSP never stores a fragment's own alpha: the target's alpha is the stencil, which a draw writes only
// through its stencil operations (patch 0004). With u.stencil.x the value replaces the alpha; otherwise the
// pipeline does not write alpha at all (or the draw is a clear, which writes its colour's alpha).
float4 stored(float4 color, constant FragmentUniforms &u) {
    if (u.stencil.x != 0u) color.a = float(u.stencil.y) / 255.0f;
    return color;
}

fragment float4 ge_fragment(Varyings in [[stage_in]],
                            constant FragmentUniforms &u [[buffer(0)]],
                            texture2d<float> image [[texture(0)]],
                            sampler image_sampler [[sampler(0)]]) {
    return stored(shade(in, u, image, image_sampler), u);
}

// The GE's blend factors for the shader's own blend (ge_fragment_16): the source side's 0 and 1 are the
// destination colour and one minus it, the destination side's the source colour and one minus it; then SA, 1-SA,
// DA, 1-DA, the doubled 2SA, 1-2SA, 2DA, 1-2DA (not clamped: PPSSPP's hardware notes, "8-bit color products") and
// 10 FIX. Others are ONE on the source side and ZERO on the destination side, as metal_backend.mm's translate_blend.
float3 ge_factor(uint factor, bool source_side, float4 source, float4 destination, float3 fix) {
    switch (factor) {
    case 0u: return source_side ? destination.rgb : source.rgb;
    case 1u: return 1.0f - (source_side ? destination.rgb : source.rgb);
    case 2u: return float3(source.a);
    case 3u: return float3(1.0f - source.a);
    case 4u: return float3(destination.a);
    case 5u: return float3(1.0f - destination.a);
    case 6u: return float3(2.0f * source.a);
    case 7u: return float3(1.0f - 2.0f * source.a);
    case 8u: return float3(2.0f * destination.a);
    case 9u: return float3(1.0f - 2.0f * destination.a);
    case 10u: return fix;
    default: return float3(source_side ? 1.0f : 0.0f);
    }
}

// The GE's blend of the fragment with the target's colour, unclamped: ADD, SUBTRACT (source minus destination),
// REVERSE SUBTRACT, MIN, MAX and ABSDIFF (the last three on the colours without factors); 6 and 7 as ADD.
float3 ge_blend(float4 source, float4 destination, constant FragmentUniforms &u) {
    switch (u.blend.w) {
    case 3u: return min(source.rgb, destination.rgb);
    case 4u: return max(source.rgb, destination.rgb);
    case 5u: return abs(source.rgb - destination.rgb);
    default: break;
    }
    const float3 a = source.rgb * ge_factor(u.blend.y, true, source, destination, u.fix_source.rgb);
    const float3 b = destination.rgb * ge_factor(u.blend.z, false, source, destination, u.fix_destination.rgb);
    switch (u.blend.w) {
    case 1u: return a - b;
    case 2u: return b - a;
    default: return a + b;
    }
}

// What a 16-bit target keeps of a colour (task 040): the colour in 8-bit steps, plus, when the draw dithers, the
// dither matrix's offset for the pixel (row y & 3, column x & 3, a signed 4-bit value), clamped once to 0..255; then
// the top bits of each channel the format has (5650: 5, 6 and 5; 5551: 5; 4444: 4), stored as the 8-bit value they
// expand to by repeating their bits, which the RGBA8 target holds and the 16-bit store packs back exactly.
float3 sixteen_bit(float3 rgb, float2 pixel, constant FragmentUniforms &u) {
    float3 value = rint(rgb * 255.0f);
    if (u.target.y != 0u) {
        const uint2 at = uint2(pixel) & 3u;
        const uint nibble = (u.dither[at.y] >> (4u * at.x)) & 15u;
        value += float(int(nibble ^ 8u) - 8);
    }
    const uint3 c = uint3(clamp(value, 0.0f, 255.0f));
    uint3 kept;
    switch (u.target.x) {
    case 0u: {  // 5650
        const uint3 top = c >> uint3(3u, 2u, 3u);
        kept = uint3((top.r << 3u) | (top.r >> 2u), (top.g << 2u) | (top.g >> 4u), (top.b << 3u) | (top.b >> 2u));
        break;
    }
    case 1u: {  // 5551
        const uint3 top = c >> 3u;
        kept = (top << 3u) | (top >> 2u);
        break;
    }
    default:  // 4444
        kept = (c >> 4u) * 17u;
        break;
    }
    return float3(kept) / 255.0f;
}

// A draw into a 5650, 5551 or 4444 target (task 040). The PSP blends, dithers and keeps the format's bits in that
// order, so the blend is done here on the target's colour ([[color(0)]], Apple GPUs' programmable blending) and the
// pipeline does not blend. The alpha, the PSP's stencil, is what stored() says, as for the other targets.
fragment float4 ge_fragment_16(Varyings in [[stage_in]],
                               constant FragmentUniforms &u [[buffer(0)]],
                               texture2d<float> image [[texture(0)]],
                               sampler image_sampler [[sampler(0)]],
                               float4 destination [[color(0)]]) {
    const float4 color = shade(in, u, image, image_sampler);
    const float3 rgb = u.blend.x != 0u ? ge_blend(color, destination, u) : color.rgb;
    return stored(float4(sixteen_bit(rgb, in.position.xy, u), color.a), u);
}

// A draw that stores a stencil value under a blend that reads the source alpha (patch 0006's kAlphaDual): the
// blend reads the fragment's own alpha from the second output.
fragment DualOutput ge_fragment_dual(Varyings in [[stage_in]],
                                     constant FragmentUniforms &u [[buffer(0)]],
                                     texture2d<float> image [[texture(0)]],
                                     sampler image_sampler [[sampler(0)]]) {
    const float4 color = shade(in, u, image, image_sampler);
    DualOutput out;
    out.color = stored(color, u);
    out.source = float4(color.a);
    return out;
}
)metal";

} // namespace pure::metal
