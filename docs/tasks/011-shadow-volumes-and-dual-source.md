# 011: Ship shadows (stencil shadow volumes) and exact REPLACE under source-alpha blends

Milestone: M3 polish | Branch: task/011-shadow-volumes-and-dual-source | Status: MERGED

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

## Result (continued)
Status: DONE. Patch 0006 is finished, built and run. Verify passes. Frame 6016 is 0.069 against the reference at tol 32 (0.304 with the patch switched off). The ship shadows draw where the PPSSPP frame has them, and the title capture is unchanged.

Changed:
- patches/0006-shadow-volumes-and-dual-source.patch: re-exported over 0001-0005. It touches vendor host/gpu/vulkan_renderer.cpp and host/gpu/shaders/ge.frag.
- patches/README.md: row 0006 rewritten for the finished change.
- docs/ge-effects.md: new section "The stencil attachment and the copy rule", plus task 011 commands under "Reproducing".
- README.md: new rows for `PURE_NO_STENCIL_BUFFER`, `PURE_NO_DUAL_SOURCE` and `PURE_TRACE_STENCIL_COPY`. The `PURE_NO_STENCIL_ALPHA` row now says it implies the first.
- This file.

What this session added to 0006:
- `submit()` wiring, as the first Result planned:
  - Non-clear draws with the stencil on and a target that is not 5650 put `stencil_key(function, fail, zfail, pass)` in the key. `stencil_values` holds `stored_reference`, the 0xDC mask and `~0xE9`.
  - Clear-mode draws that clear the alpha use ALWAYS/REPLACE with the clear colour's alpha.
  - A non-zero REPLACE under a colour blend that reads SA uses `kAlphaDual` with `stored_alpha` set to the value. ZERO keeps `kAlphaZero`. The constant-alpha fallback (no `dualSrcBlend`) marks the alpha stale.
  - After the pass is set up, a stale alpha is copied before a blend that reads DA. A draw that fails `alpha_follows_stencil` then marks the alpha stale, and `begin_pass` resets the flag.
- A bug in the unbuilt design: `resolve_stencil_alpha` wrote its quad at `vertex_offset`. During `submit()`, the current draw's vertices are already in the buffer at that offset, because `vertex_offset` only moves once the draw is recorded. Both `end_pass` and the DA-read copy run at that point, so the copy would have overwritten the draw being submitted. The quad now has a fixed 256-byte slot at the end of each frame's vertex region (`kResolveQuadBytes`), and `vertex_limit` stops short of it.
- `create_pipeline` refuses stencil keys when the attachment is off. Such keys come from the prewarm list of an earlier run.
- A clear decoded on the GPU (raw vertices, so its alpha is unknown) logs once and leaves the stencil as it was. It does not mark the alpha stale. The game never hits this path.
- `PURE_TRACE_STENCIL_COPY=1` logs each copy.

Device (the escalation check): Apple M4 Pro under MoltenVK. The renderer logs "depth format 130 (D32_SFLOAT_S8_UINT), stencil buffer on, dual-source blending on". Pipelines built from the edited SPIR-V, and the dual-source ones, create without errors (99 new pipelines in the final race run). No escalation.

Numbers. Frame 6016 of the race route with bloom on: the 960x544 capture is downscaled to 480x272, and brightness is mean luma (0.299 R + 0.587 G + 0.114 B). "0004 path" means `PURE_NO_STENCIL_BUFFER=1 PURE_NO_DUAL_SOURCE=1`.
- Frame 6016 against ref/vineta_k_start.png at tol 32:
  - out/011/hud.png: 0.0688.
  - 0004 path: 0.3041 (the brief had 0.303).
  - Three earlier runs of the same code: 0.075, 0.086 and 0.063.
- out/011/title.png against ref/title.png at tol 24: 0.0302, the same as tasks 006 and 010.
- How the shadow regions were chosen: a throwaway rasteriser simulated the dump's shadow volumes. It applied the `ppdmp.py cover` rules, back-face culling and the zfail INCR/DECR counts. In the reference frame, 1046 pixels end below 4: under the player's ship, the left-row ship, the middle ship and one far ship. The two regions lie inside that mask.

| Region (480x272 px) | ref | out/011/hud.png | 0004 path |
|---|---|---|---|
| Player ship's shadow (222,250, 16x22) | 30.0 | 32.0 | 32.0 |
| Left-row ship's shadow (53,197, 26x3) | 38.1 | 40.7 | 39.6 |
| Middle ship's shadow (231,171, 15x2), extra | 85.5 | 94.1 | 89.5 |
| Unshadowed track for contrast (160,205, 40x8) | 173.3 | 181.2 | 120.0 |

  Both chosen regions are within 20 of the reference. The shadow regions alone cannot tell the new path from the 0004 path, because the 0004 path darkens the whole track: plain track is 120 there against 173 in the reference.
- Our own shadows: a throwaway build drew 357 without blending, which makes the pixels that pass its stencil test black. 308 pixels in rows 140-271 came out below luma 10, all inside the reference's mask (the player's shadow). There was also a ship-shaped dark patch under the left-row ship.
- Copies: one per race frame, 338 copies for frames 5707-6044. Each comes at the end of the back buffer's pass, alternating between 0x04000000 and 0x04088000. None came before a destination-alpha read, and none in the frontend.

Verify output (`tools/patches.sh check && python3 tools/imgdiff.py out/011/hud.png ref/vineta_k_start.png --tol 32 --max-frac 0.30 && python3 tools/imgdiff.py out/011/title.png ref/title.png --tol 24 --max-frac 0.05`; exit 0):
```
ok: 6 patch(es) reproduce vendor/portablekit at 8b0c3fe
PASS fraction 0.068819 (8985/130560 pixels differ by more than 32, limit 0.3) at 480x272 (resized from 960x544 and 480x272)
PASS fraction 0.030201 (3943/130560 pixels differ by more than 24, limit 0.05) at 480x272 (resized from 960x544 and 480x272)
```

Open questions:
- The AI ships on the grid change from run to run, so the left and middle shadow regions vary too. The four captures show different ships in those slots. Our frame 5977 (from `PURE_TRACE_GE_LIST`) has volume pairs of 312, 108, 252, 168, 240, 156, 144, 540 and 432 vertices; the dump has 420, 456, 180, 252, 312, 156, 108, 240 and 168. The middle region measured 107.6, 98.2, 94.2 and 94.1 across the four runs, so one run was more than 20 from the reference's 85.5. The player's shadow stays at 32-34. Is the AI field seeded from something the port supplies differently, such as the RTC or the save? That would be a separate task.
- Two of the six race runs hung at shutdown after the frame exit; run_boot killed them and still exited 0. The first of them also printed "malloc: Heap corruption detected ... Incorrect guard value: 16" (the other one's log had hit its line cap). The other runs shut down cleanly. This predates 0006: the same message is in the main checkout's out/full.log and in task 014's out/014/probe2.log.
- Some writes reach a target's colour image without touching its stencil: the movie upload blit, the blit from a replaced target, and frame-interpolation replays, which draw with the stencil pipelines but make no copies. A later copy in the same pass would then write the old stencil over that alpha. Wipeout Pure never does this, as far as these runs show.
- Carried over from the first Result: should cmake compile a second fragment shader instead of editing the SPIR-V at runtime? On 5551/4444 targets, the stencil uses the 8-bit expansion of the reference.

## Review
Verify rerun by Fable after the merge on batch/m2: six-patch series ok; race frame 6016 with everything on scores
0.067 against ref/vineta_k_start.png (worker: 0.069; 0.304 before 0006); the device reports D32_SFLOAT_S8_UINT,
stencil buffer on, dual-source on. Spot-read: the resolve-quad slot fix and the stale-alpha rule. Merged into
batch/m2. Follow-ups filed: heap corruption at shutdown (task 015, predates 0006); AI grid varies run to run (RNG
seed, probably RTC; harmless for now); the SPIR-V edit vs a second shader build is a vendor-upstreaming question.
