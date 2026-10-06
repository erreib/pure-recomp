// The Metal GE backend's shaders (metal_backend.mm), as MSL source compiled when the backend starts:
// the machine needs no Xcode for it, only the Metal compiler that comes with macOS.
//
// Ported from the framework's GLSL (vendor/portablekit/host/gpu/shaders/ge.vert and ge.frag, MIT):
// through-mode and transformed vertices, the GE's per-vertex lighting (four lights, the material colours
// and the update bits, ambient, diffuse, specular with the material's power, reverse normals) and fog
// (tasks 023 and 024), transformed sprites as rectangles already projected (their lighting and fog taken
// from the second vertex), the five texture functions, the alpha test by the GE's numbering (0 NEVER,
// 1 ALWAYS: patch 0005) and the FIX source factor; the stencil value stored as the target's alpha instead of
// the fragment's, with the fragment's own alpha handed to a source-alpha blend as a second output (dual-source
// blending, ge_fragment_dual) as patches 0004 and 0006 do (task 025). The colour test, logic ops and colour
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
    uint4 texture;        // x: texture function (TFX), y: 1 alpha from the texture (TCC), z: 1 texel alpha is one
    uint4 alpha_test;     // x: GE function, y: reference, z: mask
    float4 fog;           // rgb: the fog colour; w: 1 when the draw is fogged
    uint4 stencil;        // x: 1 when the target's alpha, the PSP's stencil, receives y (0..255) instead of the
                          // fragment's alpha (the zpass REPLACE or ZERO the stencil attachment does too)
};

// What ge_fragment_dual hands the blend: the colour with the stored alpha, and the fragment's own alpha as the
// second source (MTLBlendFactorSource1Alpha), which a source-alpha blend reads instead.
struct DualOutput {
    float4 color [[color(0), index(0)]];
    float4 source [[color(0), index(1)]];
};

// Specialisation: a pipeline without a texture or an alpha test has neither in its fragment function.
constant bool kTextured [[function_constant(0)]];
constant bool kAlphaTest [[function_constant(1)]];

struct Varyings {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float3 specular;      // a separate specular term, added after texturing
    float fog;            // 1 clear, 0 fogged
    float point_size [[point_size]];
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

vertex Varyings ge_vertex(uint vid [[vertex_id]],
                          const device GeVertex *vertices [[buffer(0)]],
                          constant VertexUniforms &u [[buffer(1)]],
                          constant LightingUniforms &l [[buffer(2)]]) {
    const GeVertex v = vertices[vid];
    Varyings out;
    out.uv = fma(v.uv, u.uv_transform.xy, u.uv_transform.zw);
    out.color = unpack_unorm4x8_to_float(v.color);
    out.specular = float3(0.0f);
    out.fog = 1.0f;
    out.point_size = 1.0f;
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
    const float4 clip = u.mode.y != 0u ? v.position : u.transform * float4(v.position.xyz, 1.0f);
    // PSP clip space follows OpenGL with z in [-w, w]; Metal clips z against [0, w]. The GE's z scale and
    // offset are the viewport's znear and zfar (metal_backend.mm).
    out.position = float4(fma(clip.x, u.screen.x, clip.w * u.screen.y),
                          fma(clip.y, u.screen.z, clip.w * u.screen.w),
                          (clip.z + clip.w) * 0.5f, clip.w);
    return out;
}

// The fragment's colour and alpha as the GE computes them: texture function, separate specular, fog, alpha
// test (which discards), FIX source factor. The alpha is the fragment's own; the entry points below decide what
// the target's alpha receives.
float4 shade(Varyings in, constant FragmentUniforms &u, texture2d<float> image, sampler image_sampler) {
    float4 color = in.color;
    if (kTextured) {
        float4 texel = image.sample(image_sampler, in.uv);
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
