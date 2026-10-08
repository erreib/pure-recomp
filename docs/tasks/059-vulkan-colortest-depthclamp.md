# 059: Vulkan: the colour test and the depth clamp

Milestone: W3 (docs/windows.md step 3) | Branch: task/059-vulkan-colortest-depthclamp | Status: OPEN

## Goal
Two of task 040's Metal features into the Vulkan renderer: the GE's colour test (a fragment discard after fog,
exactly as the renderer already does the alpha test) and CLIPENABLE's depth clamp (MINZ/MAXZ; today every
transformed draw is clipped at both ends of the depth range, the registers unread).

## Read first
- docs/metal-backend.md, "How a draw is drawn" (the colour test row, the 16-bit targets row for what is NOT this
  task), and task 040's rules named there (fog before the colour test; the offset before the single clamp)
- docs/tasks/040-colour-test-dither-clamp.md (how each was measured)
- src/gpu/shaders/ge.metal (`kColorTest`, the clamp in `ge_vertex`/`ge_fragment` — the reference; do not touch)
- vendor/portablekit/host/gpu/shaders/ge.frag (the alpha test's discard — the colour test goes beside it),
  vulkan_renderer.cpp (pipeline state; whether `VK_EXT_depth_clip_enable` or `depthClampEnable` fits, or the
  per-vertex clamp Metal does — docs/windows.md leaves the choice; take the one that matches the GE rule on this
  driver and say why in the Result)
- patches/README.md

## Deliverable
A vendor patch (export as 0013-vulkan-colortest-depthclamp): COLORTESTMASK/COLORREF with NEVER, ALWAYS, EQUAL,
NOTEQUAL discarding in the fragment shader (no colour, depth or stencil written), compiled out or branch-free
when the test is off or ALWAYS; and the depth clamp as the GE rule reads (MINZ/MAXZ honoured for draws with
CLIPENABLE off), with draws that never used the registers unchanged.

## Acceptance criteria
- [ ] a colour-tested draw from a recording of the billboard/advert screen on this machine (record it as
      replay_check records its scenes), cut and compared: the discarded pixels match the rule
- [ ] a depth-clamped draw: MINZ/MAXZ honoured where before the whole range clipped (the race scenes carry them;
      name the draw used)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18; no scene moved away from its reference by
      more than 0.003, race scenes moved toward the Metal column or held
- [ ] `tools/gerec/replay_check.sh` passes
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/, out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/, config/, tools/

## Estimated turns
35

## Escalate when
The GE state does not carry COLORTESTMASK/COLORREF or MINZ/MAXZ to the renderer (report, as docs/vendor-map.md
says); neither clamp approach reproduces the GE rule on this driver; a vendor host rebuild exceeds 5 minutes.

## Result
Status: DONE

Changed:
- patches/0013-vulkan-colortest-depthclamp.patch (new; vendor host/gpu/vulkan_renderer.cpp, shaders/ge.vert,
  shaders/ge.frag), plus its row and section in patches/README.md.
  - **The colour test.** `PipelineKey` gains `color_test` (1 | function << 1; 0 for none or ALWAYS),
    `color_reference` and `color_test_mask`. They become `ge.frag`'s specialisation constants `kColorTest`,
    `kColorFunction`, `kColorReference` and `kColorMask`. After fog, where the alpha test is, the shader takes the
    8-bit colour (`roundEven`, as Metal's `rint`) under the mask and compares it with the reference under the mask.
    NEVER, EQUAL and NOTEQUAL discard, so a failing fragment writes no colour, depth or stencil. Without the test, or
    with ALWAYS, `kColorTest` is false and the discard is compiled out. The push constants are full, and the values
    are constant for this game (NOTEQUAL 000000/FFFFFF), so they are put in the pipeline rather than a uniform.
  - **The depth clamp, with CLIPENABLE on** (the rule task 040 established from the hardware notes, with `ge_vertex`
    as the reference):
    - `ge.vert` (`kDepthClamp`, vertex constant 0) computes zw = z x zscale + w x zoffset. For a vertex in front of
      the near plane it clamps zw to 0..65535 w, and it outputs z = zw / 65535.
    - `gl_ClipDistance[0..2]` are the near plane, MINZ and MAXZ.
    - The pipeline has `depthClampEnable`, and the `VkViewport` is 0..1 for these draws.
    - Every other draw writes clip distances of 1. CLIPENABLE off and through mode are drawn as before; CLIPENABLE off
      is named once.
    - The z scale, z offset, MINZ and MAXZ go in a new `vec4 depth` at the end of the environment block (496 to 512
      bytes). The block is written again when a clamped draw needs other values, or when nothing has been written this
      frame.
  - Device features `depthClamp` and `shaderClipDistance` are enabled when present. Without them the clamp is off,
    and the renderer says so once.
  - The pipeline key list (`pipeline_keys.bin`) goes from version 3 to version 4 (18 words). An older list is skipped
    once rather than misread.
  - `PURE_NO_COLOR_TEST=1` and `PURE_NO_DEPTH_CLAMP=1` (via `portablekit::env`, the names Metal reads) restore the
    old paths.
  - The comment saying the renderer draws neither feature is corrected.
  - Host rebuild: about 10 s. No include/psprecomp/ change. `tools/patches.sh check`: 13 patches reproduce the pin.
- docs/metal-backend.md: three statements said the Vulkan backend has no colour test and no clamp. This patch makes
  them false, so they are corrected: the section intro, the Recordings note, and the "differs on purpose" bullet.
  Dithering stays Metal-only.
- docs/fidelity.md: differences 10 and 11 name the Vulkan renderer.
- docs/status.md: a resolved row.

**Why depthClampEnable with clip distances.**
- vulkaninfo on this RTX 3080 (driver 581.80, Vulkan 1.4.312) reports `depthClamp`, `shaderClipDistance` and
  `VK_EXT_depth_clip_enable` (`depthClipEnable`), so all three options were available.
- The GE rule needs three things:
  - clipping at the near plane only;
  - a per-vertex clamp of screen z before interpolation;
  - a per-pixel MINZ/MAXZ test.
- `depthClampEnable` alone turns off clipping at both planes. It then clamps each fragment's depth to the viewport,
  which is not the GE's per-vertex clamp to 0..65535 followed by MINZ/MAXZ.
- `VK_EXT_depth_clip_enable` only separates clipping from clamping. Neither of its settings clips at the near plane
  alone.
- So the per-vertex clamp has to be in the shader, with the near plane and MINZ/MAXZ as clip distances. That is
  Metal's design.
- In that design `depthClampEnable` plays the part of `MTLDepthClipModeClamp`: nothing is clipped at either end of
  the 0..1 range. Both features are core Vulkan 1.0, so no extension is needed.
- A cost: the vertex module now declares `gl_ClipDistance`. A device without `shaderClipDistance` would get a module
  with that capability. This is open question 3.

Evidence, per acceptance criterion:
- **Off path byte-identical.** I kept a copy of the 0012 build (out/base/). It and this build with
  `PURE_NO_COLOR_TEST=1 PURE_NO_DEPTH_CLAMP=1` replay all 9 frames of race_warm to identical BMPs (cmp). That
  recording was made by task 058's build; it is kept in out/gerec_0012/.
- **The two features on that recording, frame 6016 against the 0012 build.**

  | Build | Pixels that differ at tol 0 (of 522240) | At tol 32 |
  |---|---|---|
  | Both on | 2705 | 0 |
  | Colour test alone | 2704 | 0 |
  | Clamp alone | 1 (a depth tie, as Metal's task 040 saw) | 0 |

- **Colour-tested draws, cut and compared (criterion 1).**
  - The race recording carries the billboard round. Frame 6016's colour-tested draws are:
    - #34, into the 565 billboard target 0x04154000;
    - #803 and #811, lit glows that write the stencil;
    - #804 and #805, fogged.
    All are NOTEQUAL 000000/FFFFFF. I used the race_warm recording that replay_check records, not a separate one.
  - The method. A throwaway build (since reverted; the tree matches the patch, `patches.sh export` finds nothing)
    drew colour-tested draws unblended. I replayed with `--cut N` and `--cut N+1`, with the test on and with
    `PURE_NO_COLOR_TEST=1`.
  - The rule predicts that a fragment is discarded exactly where its 8-bit colour is black.

  | Draw | Footprint (px) | Black, discarded | Not black, kept | Against the rule |
  |---|---|---|---|---|
  | 6016 #811 | 135 | 19 | 115 | 1 |
  | 6015 #811 | 131 | 19 | 111 | 1 |
  | 6015 #812 | 130 | 19 | 110 | 1 |

  - #804/#805, 6008's #802/#803 and 6015's #804/#805 (1189 and 194 px) are fogged, so no fragment is black: all
    were kept, 0 against the rule. 6016 #803 and 6008 #800 draw nothing on screen.
  - The one pixel against the rule in each glow draw. A second throwaway build wrote the tested 8-bit value as the
    colour. At 6016 (642,288) the shader's value is (0,0,1): not black, so kept by the rule. The target's own
    float-to-unorm conversion stores that fragment as black. The rule held on the value tested in all three draws;
    the mismatch is the target's rounding at a .5 boundary.
- **A depth-clamped draw (criterion 2).**
  - CLIPENABLE is on for every transformed draw. MINZ/MAXZ are the viewport's own ranges: 1001..64946 for the world,
    0..946 for the sky, 65001..65481 or 65007..65487 for the front slice. A throwaway trace over every transformed
    draw of the replay found no vertex in front of the near plane beyond the far plane or outside MINZ..MAXZ. So, as
    on Metal (task 040), the game's own registers cannot show the clamp.
  - The draws used: frame 6016 #164 and #165 (texture 0x0417A700, unblended, 177 and 274 vertices, screen z
    1454..1745 and 1744..44497). The throwaway build drew them as their screen z (red the high byte, green the low)
    without the depth test. It moved MINZ, then MAXZ, to 3000, and compared with `PURE_NO_DEPTH_CLAMP=1`, the old path
    that clipped the whole range and ignored the registers.
  - Their 96901 visible px have z 1471..7256.

  | Moved register | Pixels cut | Pixels kept | Against the rule |
  |---|---|---|---|
  | MINZ 3000 | all 9919 with z < 3000 | all 86982 with z >= 3000 | 0 |
  | MAXZ 3000 | all 86982 with z > 3000 | all 9919 with z <= 3000 | 0 |

  - With the draws' own MINZ, the clamped path drops no pixel against the old path. 175 px differ in z by 1 unit:
    the arithmetic of zw / 65535 against the viewport's minDepth..maxDepth.
- **replay_check (criterion 4).** Before this build, race and race_warm were set aside in out/gerec_0012/ because
  they hold no-colour-test pictures. replay_check then recorded them again (199 s and 200 s) and passed in 411 s.
  - Step 2, race_warm frames 6014-6016: 0 px at tol 4.
  - Frontend and title: 0 px at tol 0.
- **The suite (criterion 3).** 18/18. Compared with task 058's run:

  | Scene | Task 058's run | This run |
  |---|---|---|
  | race_hud | 0.0480 | 0.0505 |
  | tt_hud | 0.0622 | 0.0489 |
  | fp_hud | 0.0623 | 0.0453 |
  | zone_hud | 0.0461 | 0.0480 |
  | zone_change | 0.0501 | 0.0479 |

  - The 13 non-race scenes give 058's fractions to the 4th decimal.
  - No scene moved by more than 0.003 from task 058's run, except tt_hud and fp_hud, which moved down.
  - race_hud (+0.0025) and zone_hud (+0.0019) are slightly up; see open question 1.
- `python tools/docs_check.py`: PASS (33 files, 0 findings).

Verify output (last 20 lines), `tools/verify_task.sh 059`:
```
lang          690    0.0544   0.07   24     0.054 +0.0004  PASS
title        1750    0.0302   0.05   24     0.030 +0.0002  PASS
profile      2100    0.0543   0.07   24     0.054 +0.0003  PASS
main_menu    4700    0.0330   0.05   24     0.033 +0.0000  PASS
race_hud     6016    0.0505   0.10   32     0.067 -0.0165  PASS
single_player   4765    0.0251   0.05   24     0.025 +0.0001  PASS
class_select   4990    0.0452   0.07   24     0.045 +0.0002  PASS
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0489   0.12   32     0.096 -0.0471  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0453   0.11   32     0.095 -0.0497  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0480   0.09   32     0.065 -0.0170  PASS
zone_change   5679    0.0479   0.10   32     0.082 -0.0341  PASS

moved more than 0.03 from the vulkan measured value: tt_hud fp_hud zone_change (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (20m 13s)
verify 059: PASS
```

Open questions:
1. **race_hud came out at 0.0505, against 0.0480 in task 058's run (+0.0025, within 0.003).** zone_hud is +0.0019.
   - I do not attribute this to the patch. On a single recording, the patch moves 0 px of frame 6016 at tol 32,
     against the 0012 build. The suite compares at tol 32, and its frames come from a live run, which wobbles
     between runs.
   - Even so, "race scenes moved toward the Metal column or held" holds only within that noise for race_hud and
     zone_hud. A second suite run, which I did not make, would settle it.
2. tt_hud, fp_hud and zone_change are flagged as having moved more than 0.03. All three moves are downward, toward the
   reference. The column is not re-baselined; per task 056's review, that happens at step 3's exit.
3. **Devices without `shaderClipDistance`.**
   - The vertex module declares `gl_ClipDistance` for every pipeline. On a device without the feature the clamp is
     off, but the module still carries the capability.
   - A fix needs a second embedded module without it, built through `cmake/PortableKit.cmake`, which is outside this
     brief's May touch. The RTX 3080 and MoltenVK have the feature.
4. **The billboard target's colour-tested draw (#34, into 0x04154000) is not cut-checked.** The replay can only present
   the display. That draw is fogged, as are #804/#805, and the 565 target also lacks the dither (task 060).
5. README.md's `PURE_NO_COLOR_TEST` and `PURE_NO_DEPTH_CLAMP` rows still say Metal only ("The Vulkan backend has no
   colour test"). README.md is outside May touch; this is noted in the status.md row.
6. The throwaway debug builds and their scripts are not committed. Their outputs are in out/ab/ (cuts, dz_*) and
   out/dbg*/.

## Review
Verify rerun: from the main checkout after the merge (13 patches reproduce the pin), 2026-10-08: PASS, 18/18 in
20m 15s; the moved flags downward. race_hud's +0.0025 in the worker's run is run wobble, as the Result argues
(the patch moves 0 px of the fixed recording at tol 32) — the gate run bears that reading out.
Spot-read: patch 0013 (343 lines); the colour test as specialisation constants is the right call for a game
whose values never change; the depth-clamp design argument (Metal's design, core 1.0 features) is sound; the
per-pixel rule checks and the .5-boundary forensics are the series' standard.
Merged: into batch/m2 after ceb7e56's branch.
Notes: README's switch rows fixed at the merge (dither stays Metal-only until task 060). Open question 3
(a module without gl_ClipDistance for devices lacking shaderClipDistance) is recorded as an upstream-facing
follow-up — both targets this project ships to have the feature. The billboard target's colour-tested draw
cut-check waits on task 060's dither work, which owns that target.
