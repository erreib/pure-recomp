# 011: Ship shadows (stencil shadow volumes) and exact REPLACE under source-alpha blends

Milestone: M3 polish | Branch: task/011-shadow-volumes-and-dual-source | Status: OPEN

## Goal
Two leftovers from patch 0004 (docs/tasks/009-stencil-as-alpha.md, Open questions): (a) the ships' shadows are
missing: draws 339-356 of the race frame are depth-fail stencil volumes (ops zfail INCR/DECR, colour masked
0xFFFFFF) followed by draw 357, a full-screen darkening with stencil test GREATER ref 4 and ops REPLACE; the renderer
emulates neither, so the darkening is applied everywhere its geometry covers (or nowhere); (b) REPLACE under a colour
blend that reads source alpha (track strips 93-102 ref 0x80, engine glow 820/828 ref 0xFF with add(SA, FIXB)) is
approximated with constant-alpha blending. Make both exact.

## Read first
- CLAUDE.md, docs/ge-effects.md (the stencil section and the frame's stencil sequence), patches/0004-*.patch,
  vendor/portablekit/host/gpu/vulkan_renderer.cpp (depth/stencil attachment creation, pipeline keys, the push
  constants added by 0004), host/gpu/shaders/ge.frag, ref/vineta_k_start.ppdmp via tools/ppsspp/ppdmp.py (`draws --vt`)
- PPSSPP's approach (read-only, copy nothing): it keeps a real stencil attachment and copies it into alpha when a
  framebuffer is sampled; dual-source blending for alpha replace.

## Deliverable
1. A real Vulkan stencil attachment per render target mirroring the PSP's alpha-stencil: stencil ops INCR/DECR/
   INVERT/KEEP/ZERO/REPLACE on sfail/zfail/zpass, stencil test funcs, the stencil write mask; the target's alpha
   (what patch 0004 writes) stays the source of truth for sampling, so after any draw that changes the stencil in a
   way alpha cannot express, keep both consistent (the simplest consistent rule the design allows; document it).
2. Dual-source blending (`dualSrcBlend` feature; fall back to the 0004 approximation when unavailable) so REPLACE
   under source-alpha blends writes the exact ref.
3. Patch 0006 via `tools/patches.sh export`, README row, `PURE_NO_STENCIL_BUFFER=1` to disable the new attachment.

## Acceptance criteria
- [ ] The race frame 6016 shows a dark shadow under each ship on the grid (region check against
      ref/vineta_k_start.png: the shadow regions' brightness within 20 of the reference's).
- [ ] Frame 6016 vs ref at tol 32 is at most 0.30 (it is 0.303 after patch 0005).
- [ ] Frontend title capture unchanged (0.05 at tol 24); `tools/patches.sh check` passes with 6 patches.

## Verify
`tools/patches.sh check && python3 tools/imgdiff.py out/011/hud.png ref/vineta_k_start.png --tol 32 --max-frac 0.30 && python3 tools/imgdiff.py out/011/title.png ref/title.png --tol 24 --max-frac 0.05`

## May touch
- vendor/portablekit/host/gpu/ via `tools/patches.sh export 0006-<slug>` only, patches/, docs/ge-effects.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/, config/, patches/0001-0005

## Estimated turns
70

## Escalate when
MoltenVK lacks a usable depth+stencil format for the target or `dualSrcBlend`; report the device limits and stop.

## Result
Status: PARTIAL. The coordinator stopped the session partway through the renderer work. Patch 0006 is exported but unfinished. It has not been compiled or run, and there is no out/011/hud.png or out/011/title.png, so Verify was not run.

Changed: patches/0006-shadow-volumes-and-dual-source.patch (vendor host/gpu/vulkan_renderer.cpp, host/gpu/shaders/ge.frag), patches/README.md (row 0006), this file. docs/ge-effects.md and README.md are not updated yet.

What the frame needs (from `ref/vineta_k_start.ppdmp`; the per-draw stencil registers were read with a throwaway script over `tools/ppsspp/ppdmp.py`'s `walk()`): 627 draws use stencil ALWAYS, 243 have the stencil off, and one, 357, uses GREATER. Draws 339-356 are the shadow volumes in pairs. The odd draws use cull face 0 with ops KEEP/INCR/KEEP, the even ones cull face 1 with KEEP/DECR/KEEP. All of them have ref 0, compare mask 0x00, write mask 0 and colour masked 0xFFFFFF, with depth test GT and no depth write. Draw 357 is GREATER ref 0x04, mask 0xFF, ops REPLACE/REPLACE/REPLACE, add(FIXA 606060, FIXB 9f9f9f), depth test off. It is a transform-mode quad from -1 to 1 and sits in the middle of the opaque world, so draws 358 and later are not darkened. The track strips 113-122 put the stencil back to 4 with add(DA, FIXB ffffff) blends, which read the stencil as destination alpha. So the shadowed track pixels are the ones a back-face zfail DECR takes from 4 to 3 (ref 4 > stencil). After 357 every pixel's stencil is 4, and the bloom mask's 0xFF comes from later light draws (370 and on).

Design rule (stencil versus alpha):
- The stencil attachment is always exact. Every stencil write reaches it: the GE's ops on sfail, zfail and zpass, the test function, the compare mask and the write mask (~0xE9), plus clear-mode alpha written as REPLACE of the clear colour's alpha.
- The alpha stays the copy that textures, blends, the display and writeback read. A draw marks the alpha stale when the colour path cannot express its stencil effect. That covers an sfail op other than KEEP under a test that can fail, a zfail op other than KEEP under a depth test that can fail, INVERT/INCR/DECR on pass, a partial write mask, or the non-dual-source fallback for REPLACE (`alpha_follows_stencil`).
- While the alpha is stale, the renderer copies the stencil into it before the next draw that reads destination alpha and when the render pass ends (`end_pass`). Ending the pass also covers sampling, display and writeback.
- The copy (`resolve_stencil_alpha`) runs inside the pass and never reads the stencil in a shader. It draws a full-target quad that writes alpha 0, then 8 quads, one per bit b, with stencil EQUAL, compare mask and reference 1<<b, write mask 0, and alpha blended ONE+ONE with (1<<b)/255. Sums of k/255 stay exact in an 8-bit target.
- On this frame that should mean one copy, at the first destination-alpha read after 357 or at the end of the pass. That is not measured.

What is implemented in 0006:
- The depth format is D32_SFLOAT_S8_UINT, or D24_UNORM_S8_UINT, when the stencil buffer is wanted. If neither format exists it logs and falls back to the old list.
- The render pass loads and stores the stencil. The clear-load variants don't load it when colour and alpha are both cleared.
- PipelineKey has `stencil`/`stencil_values` (keys file version 3, 15 words, prewarm size check fixed). The stencil state is set in create_pipeline using `to_compare_op` and the new `to_stencil_op` (INCR/DECR clamp).
- Dual-source blending: `dualSrcBlend` is enabled when supported and `PURE_NO_DUAL_SOURCE` is unset. ge.frag gets a second output, `out_source_alpha` (location 0, index 1). The pipelines that don't use dual-source take a copy of the SPIR-V whose Index-1 output is moved to location 1 by editing its decorations in place (`without_dual_source`). This keeps the change inside host/gpu instead of adding a second shader build to cmake/PortableKit.cmake.
- `kAlphaDual` maps SA/1-SA to SRC1_ALPHA/ONE_MINUS_SRC1_ALPHA with alpha factors ONE/ZERO. `kAlphaAdd` (ONE/ONE) is used by the copy.
- `stencil_alpha()` now takes `buffer`, so with the attachment present it no longer logs functions and ops it emulates. New helpers: `alpha_follows_stencil`, `blend_reads_destination_alpha`, `resolve_stencil_alpha`. `end_pass` calls the copy. The replay clear includes the stencil aspect.
- Off switches: `PURE_NO_STENCIL_BUFFER=1`, which `PURE_NO_STENCIL_ALPHA=1` also implies, and `PURE_NO_DUAL_SOURCE=1`.

What remains:
1. Wire up `submit()`. Nothing sets `key.stencil` yet, so no draw uses the attachment. Each step is short:
   - Non-clear draws with stencil on and a target that is not 5650: set `key.stencil = stencil_key(function, fail, depth_fail, pass)`. Set `key.stencil_values` to `stored_reference(call)`, the 0xDC mask shifted left 8, and `(~alpha_write_mask & 0xFF)` shifted left 16.
   - Clear-mode draws with clear_flags & 2: ALWAYS with REPLACE on all three ops, ref = `call.vertices.back().color >> 24`, masks 0xFF.
   - When the blend reads SA and `impl.dual_source` is set, use `key.alpha_blend = kAlphaDual` with `stored_alpha = stencil`. Otherwise keep the 0004 path and mark the draw stale when the value is not 0.
   - After `begin_pass`, call `resolve_stencil_alpha()` if `impl.alpha_stale` is set and `blend_reads_destination_alpha(key)` is true. Then set `impl.alpha_stale` if the draw does not follow the stencil.
   - Reset `alpha_stale` in `begin_pass`.
2. Build (`tools/build.sh profile`). The build will check that the device reports D32_SFLOAT_S8_UINT and dualSrcBlend. It should (MoltenVK on Apple GPUs), but this is unverified, and it is the escalation condition. Then check pipeline creation with the edited SPIR-V.
3. Capture out/011/hud.png (route `out/011/route.txt`, which is ~/dev/pure-recomp/out/race/route.txt without shots plus `6016:shot hud`, `--frames 6045`) and out/011/title.png. Measure the brightness of the shadow regions under the ships against ref/vineta_k_start.png (regions not chosen yet). Run Verify, and update docs/ge-effects.md and README.md (switch rows).

Numbers: none for 0006. The baseline capture with 0001-0005 was rerun in this worktree (out/011/base/hud.png, out/011/base.log, exit 0) but was not compared.

Verify output: not run (no captures; 0006 not built). `tools/patches.sh check` passes: "ok: 6 patch(es) reproduce vendor/portablekit at 8b0c3fe".

Open questions:
- Should `cmake/PortableKit.cmake` compile a second fragment shader (`GE_DUAL_SOURCE@ge.frag`) instead of editing the SPIR-V at runtime? That file is outside "May touch".
- Stencil on 5551/4444 targets uses the alpha path's 8-bit expansion of the reference for both the test and the write. INCR/DECR step by 1, not by one format step. This game only uses 8888 for stencil.

## Review
(Fable fills)
