// The Metal GE backend's shaders (metal_backend.mm), as MSL source compiled when the backend starts:
// the machine needs no Xcode for it, only the Metal compiler that comes with macOS.
//
// Ported from the framework's GLSL (vendor/portablekit/host/gpu/shaders/ge.vert and ge.frag, MIT) for
// what task 023 draws: through-mode and transformed vertices, the five texture functions, the alpha
// test by the GE's numbering (0 NEVER, 1 ALWAYS: patch 0005) and the FIX source factor. Lighting, fog,
// the stencil kept as alpha and the colour test are not here yet (tasks 024 and 025).
//
// The structs below are laid out exactly as their C++ twins in metal_backend.mm (static_asserts there).
#pragma once

namespace pure::metal {

inline const char *const kShaderSource = R"metal(
#include <metal_stdlib>
using namespace metal;

// One vertex as the backend writes it: GpuVertex in metal_backend.mm.
struct GeVertex {
    float4 position;   // through mode: screen pixels and z 0..65535; transformed: object space
    float2 uv;         // through mode: texels; transformed: as the vertex holds it
    uint color;        // 0xAABBGGRR
    uint unused;
};

// VertexUniforms in metal_backend.mm.
struct VertexUniforms {
    float4x4 transform;   // projection * view * world, column major as the GE's matrices
    // The GE viewport folded into clip space for a 480x272 target (transformed draws):
    //   X = clip.x * screen.x + clip.w * screen.y,  Y = clip.y * screen.z + clip.w * screen.w
    float4 screen;
    float4 uv_transform;  // uv * xy + zw
    uint4 mode;           // x: 1 for through mode
};

// FragmentUniforms in metal_backend.mm.
struct FragmentUniforms {
    float4 fix;           // rgb: the FIX source factor the colour is multiplied by; w: 1 when it is
    uint4 texture;        // x: texture function (TFX), y: 1 alpha from the texture (TCC), z: 1 texel alpha is one
    uint4 alpha_test;     // x: GE function, y: reference, z: mask
};

// Specialisation: a pipeline without a texture or an alpha test has neither in its fragment function.
constant bool kTextured [[function_constant(0)]];
constant bool kAlphaTest [[function_constant(1)]];

struct Varyings {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float point_size [[point_size]];
};

vertex Varyings ge_vertex(uint vid [[vertex_id]],
                          const device GeVertex *vertices [[buffer(0)]],
                          constant VertexUniforms &u [[buffer(1)]]) {
    const GeVertex v = vertices[vid];
    Varyings out;
    if (u.mode.x != 0u) {
        // Screen pixels to clip space; a pixel's centre is at +0.5, as the PSP samples it.
        out.position = float4(v.position.x * (2.0f / 480.0f) - 1.0f,
                              1.0f - v.position.y * (2.0f / 272.0f),
                              clamp(v.position.z / 65535.0f, 0.0f, 1.0f), 1.0f);
    } else {
        const float4 clip = u.transform * float4(v.position.xyz, 1.0f);
        // PSP clip space follows OpenGL with z in [-w, w]; Metal clips z against [0, w]. The GE's
        // z scale and offset are the viewport's znear and zfar (metal_backend.mm).
        out.position = float4(fma(clip.x, u.screen.x, clip.w * u.screen.y),
                              fma(clip.y, u.screen.z, clip.w * u.screen.w),
                              (clip.z + clip.w) * 0.5f, clip.w);
    }
    out.uv = fma(v.uv, u.uv_transform.xy, u.uv_transform.zw);
    out.color = unpack_unorm4x8_to_float(v.color);
    out.point_size = 1.0f;
    return out;
}

fragment float4 ge_fragment(Varyings in [[stage_in]],
                            constant FragmentUniforms &u [[buffer(0)]],
                            texture2d<float> image [[texture(0)]],
                            sampler image_sampler [[sampler(0)]]) {
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
)metal";

} // namespace pure::metal
