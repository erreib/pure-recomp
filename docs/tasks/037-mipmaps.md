# 037: Mipmaps (fidelity difference 2)

Milestone: M8 | Branch: task/037-mipmaps | Status: OPEN (after task 036: both touch ge_state and the Metal texture path)

## Goal
Distant textures shimmer: crowds, the track surface, windows. 70 to 87% of the race's textured draws name mip levels
(TEXADDR1 to 7, TEXSIZE1 to 7) and a level rule (TEXLEVEL mode and bias, TEXLODSLOPE), and the framework's GE state
ignores all of them, so every backend samples level 0. This task carries the levels in the state (a vendor patch),
uploads them in the Metal backend, and selects the level as the GE does.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 2: Blue Ridge's grandstands, the evidence), docs/metal-backend.md (the
  texture cache: content key, `decoded_texture`, the samplers' filter bits; "Where it differs"), docs/tasks/036 (Result:
  how patch 0013 extended `TextureState` and the record format; follow the same shape)
- vendor/portablekit/host/gpu/ge_state.hpp and .cpp (`TextureState`: address, buffer width, size, format, swizzle,
  filters: `min_filter`/`mag_filter` carry the GE's mipmap filter bits already), host/gpu/texture_decode.hpp and .cpp
  (`decode_texture` decodes level 0; what it needs per level: address, buffer width, size)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: texture levels, the LOD rule: TEXLEVEL mode 0 auto from
  the derivatives, 1 constant from the bias, 2 slope with TEXLODSLOPE and the bias; the per-level sizes halve;
  up to 8 levels)
- src/gpu/metal_backend.mm (`decoded_texture`, the content hash, the sampler table), src/gpu/metal_shaders.h
  (`ge_fragment`'s sampling)

## Deliverable
1. Patch 0014 (`tools/patches.sh export 0014-texture-mip-levels`): `TextureState` carries the level count the GE
   gives, each level's address, buffer width, width and height (the GE's per-level registers), and the level rule
   (`level_mode`, `level_bias`, `lod_slope`); `ge_state.cpp` sets them; the record format gains them at the end;
   `gerec_dump.py` parses them. The Vulkan backend stays on level 0 (a comment); its suite is unchanged.
2. The Metal backend: a texture with levels is a mipmapped `MTLTexture`, each level decoded with the framework's
   decoder from its own address (the content hash covers every level's texels and the palette); the sampler's
   mip filter follows the GE's bits (`min_filter` bit 2: nearest or linear between levels); the level rule: mode 0
   lets Metal pick the level from the derivatives (the GE's auto mode is the same idea; the bias applies through
   `lodBias`-equivalent or a shader `bias`), mode 1 a constant level from the bias (`sample` with `level()`), mode
   2 the GE's slope formula from the distance (`bias` per draw computed as the docs give it, applied in the shader).
   Textures the GE names one level for are unchanged.
3. The check: Blue Ridge's first race frame against its PPSSPP reference (`ref/blue_ridge_hud.png` from the audit's
   reference table, with the route the audit used for it, or `race_hud` on Vineta K if Blue Ridge has no port
   route yet: say which) before and after, and the shimmer gone in a 60-flip sequence of Blue Ridge's straight (the
   per-frame fraction between consecutive frames drops; report the numbers).
4. docs/metal-backend.md (mipmaps: upload, the level rule, the cache key), docs/fidelity.md (difference 2's row with
   the result), patches/README.md, README.md if a switch is added (`PURE_NO_MIPMAPS` for A/B).

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (headless Metal) passes with no scene more than 0.003 above its measured value, and
      the race scenes at or below theirs.
- [ ] Blue Ridge's first race frame against PPSSPP improves by at least 0.01 (0.053 at tol 32 in the audit).
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` unchanged; `tools/patches.sh check` 14 patches;
      `tools/hud_check.sh` 61 of 61; the texture cache's count of decodes in a race does not grow by more than the
      levels (report the exit line before and after).

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && tools/hud_check.sh --shell headless`

## May touch
- vendor/portablekit/host/gpu/ge_state.hpp, ge_state.cpp, ge_record_format.hpp, texture_decode.hpp and .cpp (a
  per-level entry point if needed), vulkan_renderer.cpp (a comment), via `tools/patches.sh export 0014-texture-mip-levels`;
  patches/; src/gpu/; tools/gerec/gerec_dump.py; docs/metal-backend.md, docs/fidelity.md (difference 2), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/hle/, host/shell/, src/host/, src/profile/, src/tools/, tools/frame_regress.sh,
  config/, ref/, patches/0001-0013

## Estimated turns
70

## Escalate when
The GE's level rule for mode 2 cannot be matched to the reference within the shimmer check (report the pictures for
the candidate formulas), or a level's address lies outside guest memory or inside a render target (report which
texture; draw level 0 for it).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
