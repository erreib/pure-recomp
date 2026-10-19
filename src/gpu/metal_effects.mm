// The Metal backend's effects (docs/metal-backend.md, "The stencil and the alpha", "16-bit targets"). The PSP keeps
// the stencil in the target's alpha: the value a draw stores there and whether the alpha still follows the stencil
// afterwards (patches 0004 and 0006), the copy of the stencil into the alpha where it does not
// (resolve_stencil_alpha), and the blend checks for dual-source blending and for that copy. A draw into a 16-bit
// target blends in the shader (task 040). The bloom chain has no code of its own: it is targets drawn into and
// sampled as textures (metal_targets.mm).
#include "metal_backend.hpp"

#include <array>
#include <cstring>
#include <iostream>

namespace pure::gpu::metal_backend {

// The stencil reference as the target's alpha holds it: the top bit of a 5551 target, the top nibble of a
// 4444 one, all of 8888 (patch 0003's stored_reference).
std::uint32_t stored_reference(const DrawCall &call) {
    const std::uint32_t reference = call.stencil.reference & 0xFFu;
    if (call.target.color_format == 1u) return (reference & 0x80u) != 0u ? 0xFFu : 0u;
    if (call.target.color_format == 2u) return (reference >> 4u) * 17u;
    return reference;
}

// The value a draw leaves in its target's alpha, which on the PSP is the stencil (patches 0004 and 0006's
// stencil_alpha): -1 keeps the destination's alpha (no stencil test, a 5650 target, which has none, alpha bits
// masked, a zpass KEEP, or INVERT, INCR and DECR, which read the destination and are done by the attachment).
// Only fragments that pass every test write it, as the attachment's zpass operation does.
int stencil_alpha(const DrawCall &call) {
    const pk::StencilState &stencil = call.stencil;
    if (!stencil.enabled || call.target.color_format == 0u || call.alpha_write_mask != 0u) return -1;
    switch (stencil.pass_op) {
    case 1u: return 0;                                               // zero
    case 2u: return static_cast<int>(stored_reference(call));       // replace
    default: return -1;                                              // keep, invert, increment, decrement
    }
}

// Whether the draw leaves its target's alpha equal to the stencil (patch 0003's alpha_follows_stencil). The
// alpha is written only by fragments that pass every test, with stencil_alpha()'s value, so it cannot follow an
// sfail operation where the stencil test can fail, a zfail operation where the depth test can fail, INVERT,
// INCR or DECR on pass, or a write mask that keeps some bits.
bool alpha_follows_stencil(const DrawCall &call, bool depth_can_fail) {
    const pk::StencilState &stencil = call.stencil;
    if (!stencil.enabled || call.target.color_format == 0u || call.alpha_write_mask == 0xFFu) return true;
    const auto writes = [](std::uint32_t op) { return op >= 1u && op <= 5u; };
    const bool fail = stencil.function != 1u && writes(stencil.fail_op);
    const bool depth_fail = depth_can_fail && writes(stencil.depth_fail_op);
    const bool pass = stencil.pass_op >= 3u && stencil.pass_op <= 5u;
    const bool partial = call.alpha_write_mask != 0u &&
                         (writes(stencil.fail_op) || writes(stencil.depth_fail_op) || writes(stencil.pass_op));
    return !fail && !depth_fail && !pass && !partial;
}

// Copies the stencil into the open pass's target alpha, which draws since the last copy left different
// from it (patch 0003's resolve_stencil_alpha), inside the pass and without reading the stencil in a
// shader: a quad over the whole target writes alpha 0, then one quad per stencil bit passes the stencil
// test (EQUAL under a compare mask of that bit) where the bit is set and adds the bit's value to the alpha
// (ONE + ONE, alpha written alone, stencil write mask 0). Sums of multiples of 1/255 are exact in an 8-bit
// target.
void MetalGeBackend::resolve_stencil_alpha(const char *reason) {
    alpha_stale_ = false;
    if (encoder_ == nil || current_target_ == nullptr) return;
    ++stats_.stencil_copies;
    if (trace_.stencil_copy)
        std::cout << "[metal] stencil copied into the alpha of 0x" << std::hex << current_target_->key.address
                  << std::dec << " in frame " << frames_ + 1u << " (" << reason << ")\n";
    std::array<GpuVertex, 6> quad{};
    const float w = static_cast<float>(kWidth);
    const float h = static_cast<float>(kHeight);
    const std::array<std::array<float, 2>, 6> corners{{{0.0f, 0.0f}, {w, 0.0f}, {0.0f, h}, {0.0f, h}, {w, 0.0f}, {w, h}}};
    for (std::size_t i = 0; i < quad.size(); ++i) {
        quad[i].x = corners[i][0];
        quad[i].y = corners[i][1];
        quad[i].color = 0xFFFFFFFFu;
    }
    const auto [buffer, offset] = allocate(sizeof(quad));
    std::memcpy(static_cast<std::uint8_t *>(buffer.contents) + offset, quad.data(), sizeof(quad));
    VertexUniforms vertex{};
    vertex.mode = {1u, 0u, 0u, 0u};  // through mode
    FragmentUniforms fragment{};
    fragment.alpha_test = {1u, 0u, 0xFFu, 0u};
    [encoder_ setVertexBuffer:buffer offset:offset atIndex:0];
    [encoder_ setVertexBytes:&vertex length:sizeof(vertex) atIndex:1];
    if (!lighting_bound_) {
        [encoder_ setVertexBytes:&lighting_ length:sizeof(lighting_) atIndex:2];
        lighting_bound_ = true;
        lighting_changed_ = false;
    }
    // The quad is in the guest's 480x272 screen, as a through-mode draw; the viewport and scissor are the target's
    // own pixels, at its internal scale.
    const std::uint32_t target_width = current_target_->width();
    const std::uint32_t target_height = current_target_->height();
    [encoder_ setViewport:MTLViewport{0.0, 0.0, static_cast<double>(target_width), static_cast<double>(target_height),
                                      0.0, 1.0}];
    [encoder_ setScissorRect:MTLScissorRect{0u, 0u, target_width, target_height}];
    [encoder_ setCullMode:MTLCullModeNone];
    RenderKey render;
    render.write_mask = MTLColorWriteMaskAlpha;
    DepthStencilKey depth;
    for (std::uint32_t step = 0; step <= 8u; ++step) {
        const std::uint32_t bit = step == 0u ? 0u : 1u << (step - 1u);
        if (step != 0u) {
            render.blend = true;
            render.alpha_destination = MTLBlendFactorOne;  // add
            depth.stencil = true;
            depth.stencil_function = 2u;  // EQUAL, every operation KEEP
            depth.compare_mask = static_cast<std::uint8_t>(bit);
            depth.write_mask = 0u;
        }
        id<MTLRenderPipelineState> pipeline = render_pipeline(render);
        if (pipeline == nil) break;
        [encoder_ setRenderPipelineState:pipeline];
        [encoder_ setDepthStencilState:depth_state(depth)];
        if (step != 0u) [encoder_ setStencilReferenceValue:bit];
        fragment.stencil = {1u, bit, 0u, 0u};
        [encoder_ setFragmentBytes:&fragment length:sizeof(fragment) atIndex:0];
        [encoder_ drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:quad.size()];
    }
    // The next draw sets its own state again.
    bound_ = Bound{};
}

// Whether a blend reads the fragment's alpha (SA or 1-SA on either side, the doubled forms drawn single),
// so the fragment cannot hand over the stencil value as its alpha without dual-source blending.
bool MetalGeBackend::blend_reads_source_alpha(const RenderKey &key, std::uint8_t write_mask) {
    const auto reads = [](std::uint8_t factor) {
        return factor == MTLBlendFactorSourceAlpha || factor == MTLBlendFactorOneMinusSourceAlpha;
    };
    return key.blend && key.operation != MTLBlendOperationMin && key.operation != MTLBlendOperationMax &&
           (write_mask & (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue)) != 0u &&
           (reads(key.source) || reads(key.destination));
}

// Whether a blend reads the destination's alpha (DA or 1-DA), which is the PSP's stencil.
bool MetalGeBackend::blend_reads_destination_alpha(const RenderKey &key) {
    const auto reads = [](std::uint8_t factor) {
        return factor == MTLBlendFactorDestinationAlpha || factor == MTLBlendFactorOneMinusDestinationAlpha;
    };
    return key.blend && key.operation != MTLBlendOperationMin && key.operation != MTLBlendOperationMax &&
           (key.write_mask & (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue)) != 0u &&
           (reads(key.source) || reads(key.destination));
}

// A draw into a 16-bit target (task 040) blends in the shader (ge_fragment_16) with the GE's own factors and
// equation, the FIX colours and doubled factors exact; the pipeline does not blend.
void MetalGeBackend::shader_blend(const BlendState &blend, FragmentUniforms &fragment) {
    if (!blend.enabled) return;
    fragment.blend = {1u, blend.source_factor & 0xFu, blend.destination_factor & 0xFu, blend.equation & 7u};
    fragment.fix_source = unpack_color(blend.fixed_source);
    fragment.fix_destination = unpack_color(blend.fixed_destination);
}

// Whether the shader's blend reads the destination's alpha (DA, 1-DA, 2DA or 1-2DA on either side), which is
// the PSP's stencil.
bool MetalGeBackend::shader_blend_reads_destination_alpha(const FragmentUniforms &fragment, std::uint8_t write_mask) {
    const auto reads = [](std::uint32_t factor) { return factor == 4u || factor == 5u || factor == 8u || factor == 9u; };
    return fragment.blend[0] != 0u && fragment.blend[3] < 3u &&
           (write_mask & (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue)) != 0u &&
           (reads(fragment.blend[1]) || reads(fragment.blend[2]));
}

} // namespace pure::gpu::metal_backend
