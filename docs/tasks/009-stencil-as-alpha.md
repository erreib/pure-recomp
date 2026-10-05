# 009: Stencil operations as alpha writes in the Vulkan renderer (the bloom mask)

Milestone: M3 (faithful race frame) | Branch: task/009-stencil-as-alpha | Status: MERGED

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
Status: DONE

Changed:
- `patches/0004-stencil-as-alpha.patch` (new; exported with `tools/patches.sh export`): `host/gpu/ge_state.hpp/.cpp`,
  `host/gpu/vulkan_renderer.cpp`, `host/gpu/shaders/ge.frag`
- `patches/README.md` (row 0004), `README.md` (switch row `PURE_NO_STENCIL_ALPHA`), `docs/ge-effects.md` (new
  section "Stencil as alpha: what the renderer does since patch 0004", with the frame's stencil sequence)

The stencil func, confirmed from `ref/vineta_k_start.ppdmp` before designing (all 871 draws): every draw that writes
the bloom mask uses STENCILTEST ALWAYS with ops KEEP/KEEP/REPLACE (ref 0x04 world and sky, 0xFF lights, 0x80 on the
track strips 93-102, 0x00 on parts of the translucent world, 0x78/0x3A on two draws). The one other function is draw
357, GREATER ref 0x04 with all three ops REPLACE: the full-screen shadow darkening after the depth-fail shadow volumes
339-356 (ALWAYS, zfail INCR/DECR, colour masked 0xFFFFFF). Deliverable 3 covers that case (logged once, drawn as
ALWAYS); because all of 357's ops are REPLACE its alpha result is exact anyway, so I did not treat it as the
escalation condition. Run log: `[render] stencil depth fail op 0x4 / 0x5 is not emulated`, `[render] stencil test
function 0x6 is not emulated`, once each. The frontend runs log none.

What the patch does:
1. ge_state parses STE 0x24, STST 0xDC (func, ref, mask), SOP 0xDD (sfail, zfail, zpass), PMSKC 0xE8 and PMSKA 0xE9
   into new `DrawCall::stencil` (`StencilState`), `color_write_mask`, `alpha_write_mask`. Existing fields are unchanged.
2. Renderer, outside clear mode: the target's alpha is written only by the stencil zpass op. REPLACE stores the ref
   (top bit on 5551, top nibble on 4444), ZERO stores 0. KEEP, INVERT/INCR/DECR (logged once), stencil test off, any
   PMSKA bit set, or a 5650 target leave the alpha alone (no A in the colour write mask). A PMSKC channel with all 8
   bits set is not written; partial masks are logged once. Stencil test off now also keeps alpha. That is the
   hardware's and PPSSPP's behaviour (the GE never stores fragment alpha), and the game needs it because its
   translucent world (603-831) draws with the stencil off.
3. How the value is stored: when the colour blend does not read the source alpha, the fragment shader writes it
   (push constant `viewport.w` bit 2, value in bits 3..10; ge.frag `stored()`, after the alpha test). When the blend
   reads source alpha (SA/1-SA with RGB written), a new `PipelineKey::alpha_blend` picks the alpha blend factors.
   ZERO uses (ZERO, ZERO), which is exact. REPLACE uses (CONSTANT_ALPHA, ONE_MINUS_SRC_ALPHA) with the blend
   constant's alpha set to the ref: exact for opaque fragments and for the z-equal decal passes, an approximation
   elsewhere. Pipeline-key file version 1 -> 2 (13 words).
4. `PURE_NO_STENCIL_ALPHA=1` restores the old path. Checked: at the same frame with FB textures on it gives sky 254.5
   and 94.0% differing from fb-off, the old washed frame.

Numbers. Frame **6016** is our port's first full-HUD frame: the HUD fades in over 6010-6016 in both runs (HUD-region
mean and deviation stable from 6016), and READY follows at about 6080. Route `~/dev/pure-recomp/out/race/route.txt`
(presses only) plus `6016:shot`, `--frames 6045`.

| Frame 6016 | Sky (100,20,280,60) mean brightness | vs fb-off, tol 24 | vs ref/vineta_k_start.png, tol 32 |
|---|---|---|---|
| fb-on (`out/009/fb-on.png`) | 210.3 | 6.34% differ (limit 35%) | 0.628 |
| fb-off, `PURE_NO_FB_TEXTURES=1` (`out/009/fb-off.png`) | 195.1 | | 0.663 |
| fb-on, `PURE_NO_STENCIL_ALPHA=1` (old behaviour) | 254.5 | 94.0% differ | |

- Sky difference: 15.2, within 25.
- Reference compare: fb-on 0.628 is better than fb-off 0.663, so it is within the 0.05 allowance.
- Title (`out/009/title.png`, `config/pad_scripts/frontend.txt` shot `title` at 1750, `--frames 1760`): 0.0302 at
  tol 24. `out/004-shots/title.png` scores the same 0.0302. The title, profile and main-menu dumps use no stencil.
- `tools/patches.sh check` passes with 4 patches.
- Visually, the bloom now lights the ceiling strips, the screens and the engines instead of the whole frame. The blue
  shadow-volume boxes under the ships are gone from both the fb-on and fb-off frames, because PMSKC 0xFFFFFF is now
  honoured.

Verify output:
```
ok: 4 patch(es) reproduce vendor/portablekit at 8b0c3fe
PASS fraction 0.063394 (33107/522240 pixels differ by more than 24, limit 0.35) at 960x544
PASS fraction 0.030201 (3943/130560 pixels differ by more than 24, limit 0.05) at 480x272 (resized from 960x544 and 480x272)
```
(`ref/title.png` copied from the main checkout into this worktree's git-ignored `ref/`. `tools/verify_task.sh` does
not exist on this branch, so I ran the Verify line directly.)

Open questions:
- Stencil test off now keeps the destination alpha, which goes beyond the brief's list. It is PSP behaviour, and
  without it the translucent world's draws (stencil off) would write their texture alpha into the mask. Fable to
  confirm this is wanted in 0004 rather than as a separate patch.
- Draw 357 (GREATER) and the shadow volumes' zfail INCR/DECR are not emulated. 357 still applies its colour wherever
  its geometry covers, as it did before this patch, instead of only on pixels with stencil < 4. So ship shadows are
  missing (the volumes now draw nothing, where before they drew blue boxes). Emulating them needs a real stencil
  attachment or a destination read; that is a candidate follow-up task.
- REPLACE under a colour blend that reads source alpha is approximate: draws 93-102 (ref 0x80, alpha 0xB2) and the
  engine-glow sprites 820/828 (ref 0xFF, add(SA, FIXB)). The exact route is dual-source blending, which needs the
  `dualSrcBlend` device feature and a second shader output. That is outside the brief's shader + push constant + key
  limit, so I did not do it.
- `pipeline_keys.bin` lives in the shared user-data directory (`~/Library/Application Support/pure-recomp/PureNative`).
  A build without 0004 (version 1) and one with it (version 2) will discard each other's key list. Only the background
  prewarm is affected.
- The remaining gap to the reference (the haze over the scene, the pale track, the lens-flare rings) is present with
  FB textures off too, so it is not the bloom. docs/ge-effects.md points at the lens-flare depth read for part of it.

## Review
Verify rerun by Fable after the merge on batch/m2: series check ok (4 patches), race frame 6016 with the bloom path
on scores 0.631 against ref/vineta_k_start.png (the worker measured 0.628; the no-bloom frame 0.663). Spot-read:
patch 0004's ge_state parsing and the alpha-source push constant. Decisions: keeping destination alpha when the
stencil test is off stays in 0004 (it is the hardware's behaviour and the translucent world needs it). Follow-ups
recorded: shadow volumes (zfail INCR/DECR + GREATER test) and dual-source blending for exact REPLACE under
source-alpha blends. Merged into batch/m2. Notes: pipeline key file version bumped to 2.
