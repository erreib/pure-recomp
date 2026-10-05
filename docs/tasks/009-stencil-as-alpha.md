# 009: Stencil operations as alpha writes in the Vulkan renderer (the bloom mask)

Milestone: M3 (faithful race frame) | Branch: task/009-stencil-as-alpha | Status: OPEN

## Goal
The PSP has no separate stencil buffer: stencil bits live in the framebuffer's alpha channel. Wipeout Pure writes
its bloom mask that way (docs/ge-effects.md: the opaque world and sky write alpha with stencil REPLACE, ref 4 for
most materials and 0xFF for lights; the bloom then weights the scene by that alpha with blend add(SA, 0)). The
framework's GE state ignores the stencil commands (0x24 STE, 0xDC STST, 0xDD SOP) and the write masks (0xE8 PMSKC,
0xE9 PMSKA), so every pixel ends up with full alpha and the whole scene blooms (`out/race-fb/r6400.png`, sky region
mean brightness 254 against 196 without bloom). Emulate the stencil write path the game uses, as vendor patch 0004.

## Read first
- CLAUDE.md, docs/ge-effects.md (the whole sequence; which stencil func/ops/refs/masks each pass sets),
  docs/status.md (bloom row), patches/0003-* (how a vendor patch is exported, `tools/patches.sh export`)
- vendor/portablekit/host/gpu/ge_state.hpp/.cpp (DrawCall, how blend/alpha-test state is parsed; find where 0x24,
  0xDC, 0xDD, 0xE8, 0xE9 are dropped), host/gpu/vulkan_renderer.cpp (pipeline keys, push constants, the fragment
  shader source under host/gpu/shaders/, framebuffer_descriptor), PPSSPP's GE docs for STST/SOP semantics
  (https://www.ppsspp.org/docs/psp-hardware/gpu/ , read-only) and PPSSPP's own stencil handling for the approach
  (GPU/Common/*, read-only; copy nothing)
- ~/dev/pure-recomp/out/race/route.txt and out/race-fb/ (the fb-on capture at frame 6400), ref/vineta_k_start.png
  + ref/README.md (the reference is the first full-HUD frame before READY; find our port's matching frame with
  `--shots --every 10` around 6200-6400 and the HUD region variance)

## Deliverable
1. ge_state: parse STE (enable), STST (func, ref, mask), SOP (sfail, zfail, zpass) and PMSKC/PMSKA into DrawCall
   fields (keep the existing fields untouched; add new ones).
2. vulkan renderer: when stencil is enabled and the test func is ALWAYS (what the game uses; confirm from the
   sequence), make the fragment's written alpha come from the zpass op: REPLACE -> ref, ZERO -> 0, KEEP -> leave the
   destination alpha (alpha write disabled), INVERT/INCR/DECR -> report as unsupported once and leave alpha. Honour
   PMSKA (alpha write mask: any masked bits mean no alpha write) and PMSKC (colour write mask: when it masks a whole
   channel, disable that channel's write). Do it with a push constant + a shader branch or a colour write mask on
   the pipeline, whichever fits the renderer's pipeline-key design; keep it to the smallest change.
3. A stencil test func other than ALWAYS, if the game uses one in this scene, may stay unimplemented but must be
   logged once with the func value.
4. Export as patches/0004-stencil-as-alpha.patch with a README row; `tools/patches.sh check` must pass.

## Acceptance criteria
- [ ] With the bloom path on (no `PURE_NO_FB_TEXTURES`), our port's first full-HUD frame on Vineta K has a sky
      region (100,20,280,60) mean brightness within 25 of the same frame with `PURE_NO_FB_TEXTURES=1`, and the two
      frames differ in fewer than 35% of pixels at tol 24 (bloom adds a glow, it does not wash the frame).
- [ ] That frame compared with ref/vineta_k_start.png at tol 32 is no worse than the no-bloom frame + 0.05.
- [ ] The frontend screens are unchanged: `out/004-shots/title.png` equivalent from the frontend route still
      matches ref/title.png within 0.05 at tol 24.
- [ ] `tools/patches.sh check` passes with 4 patches.

## Verify
`tools/patches.sh check && python3 tools/imgdiff.py out/009/fb-on.png out/009/fb-off.png --tol 24 --max-frac 0.35 && python3 tools/imgdiff.py out/009/title.png ref/title.png --tol 24 --max-frac 0.05`
(The worker produces out/009/fb-on.png, fb-off.png at the same frame and out/009/title.png from the frontend route; state the frame number in the Result.)

## May touch
- vendor/portablekit/host/gpu/ (only via `tools/patches.sh export 0004-stencil-as-alpha`), patches/, docs/ge-effects.md
  (a short "what the renderer now does" section), README.md (a line in the switch table if a switch is added)

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/, config/, patches/0001-0003

## Estimated turns
60

## Escalate when
The renderer's pipeline-key design cannot take a per-draw alpha source without touching more than the fragment
shader, the push constants and the key (report the structure and stop), or the game's stencil func in this scene
is not ALWAYS (report the sequence and stop).

## Result
(worker fills)

## Review
(Fable fills)
