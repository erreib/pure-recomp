# 060: Vulkan: 16-bit targets and the GE's dither

Milestone: W3 (docs/windows.md step 3) | Branch: task/060-vulkan-16bit-dither | Status: OPEN

## Goal
The last and hardest of the step-3 ports: draws into 5650, 5551 and 4444 targets quantised to the format's bits,
with the dither matrix's offset when DITHERENABLE is on, as the PSP writes such targets and as the Metal backend
has drawn them since task 040 (`ge_fragment_16`: blend in the shader on the target's colour, add the dither
offset, keep the format's bits; the target texture stays RGBA8). Vulkan has no programmable blending, so pick one
of docs/windows.md's two paths and defend the choice in the Result:
- true 16-bit `VkFormat`s for those targets (the hardware quantises; the dither offset needs a pass of its own
  or a subpass with an input attachment), or
- RGBA8 targets with the blend done in the shader through a self-dependent subpass input attachment (the closest
  to what Metal does), or `VK_EXT_fragment_shader_interlock` if the driver's support makes it simpler.

## Read first
- docs/metal-backend.md, "How a draw is drawn" (the 16-bit targets row), "The pipeline key" (`sixteen`), and the
  task-040 rules named there (clears into 16-bit targets not dithered; 8888 never dithered)
- docs/tasks/040-colour-test-dither-clamp.md (the measurement: the billboard target against PPSSPP's dump)
- src/gpu/metal_effects.mm and ge.metal's `ge_fragment_16` (the reference; do not touch)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (render passes, target formats, where a subpass could go)
- tools/gerec/gerec_dump.py (reading a draw's state), the billboard recording from task 059 if it was made
- patches/README.md

## Deliverable
A vendor patch (export as 0014-vulkan-16bit-dither): the three 16-bit formats drawn with the GE's quantisation
and dither, 8888 targets untouched, clears not dithered, and the doubled factors/ABSDIFF rows of the Metal
implementation carried over where the chosen path allows (mark what stays unexercised, as task 040 did).

## Acceptance criteria
- [ ] the billboard target measured as task 040 measured it: the dithered 16-bit pixels against PPSSPP's dump of
      the same draw (the adverts' cycle phase caveat is in task 040's follow-up: compare at a matching point or
      record the limitation)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18; the race scenes' distance to the Metal
      column at its smallest so far — this task closes step 3's exit: every race scene's Vulkan fraction within
      0.005 of the Metal column, or the Result names each scene still outside and why
- [ ] `tools/gerec/replay_check.sh` passes
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/, out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/, config/, tools/

## Estimated turns
50

## Escalate when
Neither path reproduces the GE's write rule on this driver; the subpass restructuring would touch the renderer's
public interface in include/psprecomp/; a vendor host rebuild exceeds 5 minutes.

## Working notes
Design (decided before the code): RGBA8 targets, with the blend done in ge.frag on the colour read through the
render pass's own colour attachment as a self-dependent subpass input (the colour attachment is also input attachment
0, GENERAL layout inside the pass, a BY_REGION self-dependency, and a by-region barrier before each draw into a 16-bit
target, which also stops such draws from merging). This is Metal's `ge_fragment_16` on Vulkan. It is one render pass
for every target, so every pipeline, framebuffer and descriptor set stays compatible and ge.frag can declare the input
legally for all pipelines (a second shader module would need cmake/PortableKit.cmake, outside May touch). Rejected:
true 16-bit `VkFormat`s (the hardware rounds where the GE truncates after the blend, the dither offset sits after the
blend, and every reader of a target expects RGBA8); `VK_EXT_fragment_shader_interlock` (supported on this RTX 3080, but
it needs storage-image writes, which bypass the depth/stencil test unless the tests run early, and early tests break
discard-with-depth-write). The subpass path leaves overlapping fragments of one draw unordered (no
`VK_EXT_rasterization_order_attachment_access` on this driver); measured on race_warm frames 6008, 6012 and 6016 with
culling applied, the blended draws into 0x04154000 have 0 such pixels.

## Result
Status: DONE (the step-3 exit's 0.005 bar is not met; every scene outside it is named below with the reason)

Changed:
- patches/0014-vulkan-16bit-dither.patch (new; vendor host/gpu/vulkan_renderer.cpp and shaders/ge.frag), with its row and
  section in patches/README.md. Host rebuild about 10 s. No include/psprecomp/ or cmake change. `tools/patches.sh
  check`: 14 patches reproduce the pin.
  - The render pass's colour attachment is also input attachment 0 (GENERAL inside the pass, a BY_REGION
    self-dependency, explicit external dependencies for the layout changes). One pass for every target.
  - Every target gets an input-attachment set (set 2 of `pipeline_layout`, its own pool of 128), bound when a pass
    begins and in frame interpolation's replay. Target images gain `INPUT_ATTACHMENT` usage.
  - `PipelineKey` gains `sixteen` (1 + format), `dither`, `dither_rows`, `fix_source`/`fix_destination` and
    `pixel_scale`, which become ge.frag's specialisation constants 5 to 16. For a 16-bit draw the shader:
    - blends with the GE's raw factors and equation on `subpassLoad` (FIX exact, the doubled factors and ABSDIFF as
      ge.metal's `ge_factor`/`ge_blend`);
    - adds DITHn's offset for the PSP pixel (row y & 3; the pixel is gl_FragCoord over the internal scale);
    - clamps once, keeps 5/6/5, 5/5/5 or 4/4/4 bits and writes their bit-repeated 8-bit value.
  - The pipeline does not blend, and the shader's alpha is the stencil value, so no dual source or constant-alpha trick
    is needed. Clears into 16-bit targets keep the bits but are not dithered. 8888 targets are unchanged.
  - Before each 16-bit draw the merge group is flushed and a by-region barrier is recorded (`sixteen_barrier`).
  - The pipeline key list goes from version 4 to 5 (25 words).
  - `PURE_NO_DITHER=1` (`portablekit::env("NO_DITHER")`, the Metal name) restores the old drawing.
  - `PURE_SHOW_TARGET=ADDR` presents that render target instead of the display (Metal's `PURE_METAL_SHOW_TARGET`). It
    is what makes the billboard target measurable in a Vulkan replay (task 059's open question 4).
- docs/metal-backend.md (three statements that only Metal dithers), docs/fidelity.md (difference 11), docs/status.md
  (resolved row), and this file's Working notes.

**The design and why.** The measured driver is an RTX 3080 with Vulkan 1.4.312. It offers
`VK_EXT_fragment_shader_interlock` (pixel interlock), `VK_EXT_attachment_feedback_loop_layout` and
`VK_KHR_dynamic_rendering_local_read`. It does not offer `VK_EXT_rasterization_order_attachment_access`.
- **Chosen: RGBA8 targets, blended in the shader on a self-dependent subpass input.**
  - It is the closest thing to Metal's `[[color(0)]]`.
  - It keeps the depth/stencil tests, discards and the stencil-in-alpha logic in the fixed pipeline, unchanged.
  - The renderer has one subpass per target pass, so the change is the pass description, a descriptor set and a
    barrier.
  - It is one pass for all targets. ge.frag is one embedded module (a second needs cmake/PortableKit.cmake, outside May
    touch), and with one pass it declares the input legally for every pipeline. Every pipeline, framebuffer and the
    discard and replay passes also stay compatible.
- **Rejected: true 16-bit `VkFormat`s.** The hardware rounds where the GE truncates. The dither offset comes after the
  blend, where the fixed-function blend cannot take it. Every reader of a target (framebuffer textures, store_frame,
  interpolation) expects RGBA8.
- **Rejected: fragment-shader interlock.** It needs storage-image writes, which ignore the late depth/stencil test
  unless the tests run early. Early tests write depth for fragments that the alpha or colour test then discards. The
  race's 16-bit draws use ztest and the alpha test.
- **The known limit of the chosen path.** Overlapping fragments of one draw are not ordered against each other's
  reads. A coverage rasteriser over race_warm frames 6008, 6012 and 6016 (culling applied) finds 0 such pixels in the
  blended draws into 0x04154000. Merging is off for those draws, so separate draws are always ordered.

Evidence, per acceptance criterion:
- **The off switch.**
  - Race_warm (task 059's recording, all 9 frames) replays to byte-identical BMPs with this build under
    `PURE_NO_DITHER=1` and with the 0013 build (out/base). That covers the render-pass change too.
  - Validation layer on frames 6014-6016: no VUID from the new code, after adding the usage bit it asked for. It gives
    the same 11 pre-existing ShaderOutputNotConsumed warnings as the 0013 build.
- **The billboard target (criterion 1).**
  - Draw numbers, re-derived on race_warm frame 6016 with gerec_dump and a coverage script: the rounds into 0x04154000
    are #1-22, #27-53, #58-77 and #82-91. Every draw in them is dithered, with the matrices 1B5F/93D7, 71B5/F93D,
    5F93/D71B and B5F9/3D71.
  - The colour-tested draws are #60 and #61; task 059's "#34" was another count.
  - The method: replays with `--cut` and `PURE_SHOW_TARGET=0x04154000`, dither on and off, with the 128x128 target read
    at one sample per PSP pixel.

  | Cut (after draw) | 565 values, on | 565 values, off | PSP rule on the off pixels = on | Blocks dithered by the round's matrix, on / off |
  |---|---|---|---|---|
  | 23 (round 1) | 1.0000 | 0.0026 | 0.9675 | 702 / 0 |
  | 54 (round 2) | 1.0000 | 0.9615 | 1.0000 | 953 / 0 |
  | 78 (round 3) | 1.0000 | 0.0413 | 0.8430 | 4 / 0 |
  | 85 (#84: one unblended draw over the whole target) | 1.0000 | 0.9999 | **1.0000 (16384/16384)** | 1023 / 0 |
  | 92 (round 4) | 1.0000 | 0.9973 | 0.9996 | 1016 / 0 |

  - Rounds 1 and 3 blend repeatedly. Applying the rule once to the 8-bit result cannot equal quantising after every
    blend, hence 0.97 and 0.84.
  - PPSSPP's dump (`ref/vineta_k_start.ppdmp`, FRAMEBUF records at draws 26, 45, 69 and 82, DITH rows from its
    registers) has 565 values everywhere.
  - Blocks dithered by the round's matrix: PPSSPP 740, 921, 3 and 1024; this build 702, 953, 4 and 1016.
  - The same round against PPSSPP, pixel by pixel (fraction of pixels differing, dithered / before):

    | Round | tol 0 | tol 8 | tol 16 |
    |---|---|---|---|
    | 1 | 0.53 / 1.00 | 0.28 / 0.40 | 0.16 / 0.05 |
    | 2 | 0.46 / 0.46 | 0.28 / 0.28 | 0.28 / 0.28 |
    | 3 | 0.65 / 0.98 | 0.37 / 0.54 | 0.19 / 0.31 |

    Round 4 cannot be compared: PPSSPP's is a flat 229 grey and ours shows other content.
  - The limitation is the one task 040 recorded. PPSSPP's matrices and adverts are at another point of the cycle (its
    round 1 uses 3D71/B5F9, ours 1B5F/93D7), so exact equality is not expected. Round 1's rise at tol 16 is that content
    offset; the dither alone moves no pixel by more than 8 (below).
- **The suite (criterion 2).** 18/18 PASS (20m 13s).
  - On the fixed recording the dither changes frame 6016 by 489 px at tol 0 and by 0 px at tol 8, 16 and 32. It cannot
    move a suite fraction (tol 32), so the race-scene changes since task 059 are run wobble:

    | Scene | Task 059's run | This run |
    |---|---|---|
    | race_hud | 0.0505 | 0.0531 |
    | tt_hud | 0.0489 | 0.0480 |
    | fp_hud | 0.0453 | 0.0556 |
    | zone_hud | 0.0480 | 0.0460 |
    | zone_change | 0.0479 | 0.0850 |

  - zone_change came out at 0.0850 here. Two further `--only` runs gave 0.0292 with the dither on and 0.0706 with
    `PURE_NO_DITHER=1`. Zone never enables dithering, so that spread is the live run.
  - Moved-flags: tt_hud and fp_hud, both downward. The column is not re-baselined.
  - Step 3's exit (Vulkan within 0.005 of Metal on every race scene) is not met:

    | Scene | Vulkan | Metal |
    |---|---|---|
    | race_hud | 0.053 | 0.0149 |
    | tt_hud | 0.048 | 0.0112 |
    | fp_hud | 0.056 | 0.0116 |
    | zone_hud | 0.046 | 0.0121 |
    | zone_change | 0.029-0.085 | 0.0353 |

  - Why the gap is not a renderer feature: the two columns are not measured alike.
    - The menu scenes, which have no 3D, no dither and no step-3 feature, show the same gap: lang 0.054 against 0.0002,
      title 0.030 against 0.0002, team_select 0.042 against 0.0000.
    - The Vulkan column is a windowed, paced run captured at 960x544 (2x internal scale) and sampled to 480x272. The
      Metal column is the headless backend's own 480x272 pictures.
    - So a floor of about 0.03 to 0.05 comes from the capture path and scale, and the race scenes sit on that floor
      plus run wobble.
    - The like-for-like comparison is `tools/gerec/metal_check.sh`'s A/B, which needs a Mac.
- **replay_check (criterion 3).** PASS (502 s).
  - The four recordings were made again with this build, because the old ones hold undithered pictures. out/gerec_0013
    keeps task 059's.
  - Step 2, frames 6014-6016: 0 px at tol 4. Frontend and title: 0 px at tol 0.
- **docs_check (criterion 4).** PASS (33 files, 0 findings).

Verify output (last 20 lines), `tools/verify_task.sh 060`:
```
profile      2100    0.0543   0.07   24     0.054 +0.0003  PASS
main_menu    4700    0.0330   0.05   24     0.033 +0.0000  PASS
race_hud     6016    0.0531   0.10   32     0.067 -0.0139  PASS
single_player   4765    0.0251   0.05   24     0.025 +0.0001  PASS
class_select   4990    0.0452   0.07   24     0.045 +0.0002  PASS
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0480   0.12   32     0.096 -0.0480  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0556   0.11   32     0.095 -0.0394  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0460   0.09   32     0.065 -0.0190  PASS
zone_change   5679    0.0850   0.10   32     0.082 +0.0030  PASS

moved more than 0.03 from the vulkan measured value: tt_hud fp_hud (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (20m 13s)
verify 060: PASS
```

Open questions:
1. **README.md is outside May touch.** Its `PURE_NO_DITHER` row says the Vulkan backend draws 16-bit targets the same
   either way; it now dithers too. `PURE_SHOW_TARGET` needs a row. For the reviewer, as at 058 and 059.
2. **Step 3's exit criterion compares two columns measured differently** (see criterion 2). It needs either a
   re-baseline of both on one capture path or `metal_check.sh` run on a Mac. That belongs to step 3's exit task, not
   this one.
3. **Not exercised by the game, as on Metal:** 5551 and 4444 targets, the doubled factors, ABSDIFF, and a 16-bit
   *displayed* target under frame interpolation. Interpolation's replay binds the input set but records no barrier
   between such draws.
4. **Every render pass now uses GENERAL for its colour attachment, plus explicit external dependencies.** On NVIDIA
   this cost nothing measurable: the suite took 20m 13s, as in task 059. On tiled or AMD GPUs a GENERAL colour
   attachment may lose compression; `VK_EXT_attachment_feedback_loop_layout` would be the refinement.
5. **A trap for the next vendor edit: the vendor tree's files are CRLF in this checkout.**
   - A `sed -i` in Git Bash rewrote ge.frag as LF.
   - `patches.sh check` then failed, although the diff was right.
   - The file was restored to CRLF before the export.
6. **Throwaway scripts are not committed:** the coverage-overlap script, the billboard measurement, and a zstd shim for
   ppdmp.py (this machine has no `zstd`). Their outputs are in out/ab/ (measure.txt, cut_on_*/cut_off_*, pp/).

## Review
Verify rerun: from the main checkout after the merge (14 patches reproduce the pin), 2026-10-08: PASS, 18/18;
race_hud 0.0535, tt_hud 0.0471, fp_hud 0.0565, zone_change 0.0453 — the wobble bands as the Result reads them.
Spot-read: patch 0014 (547 lines); the subpass-input design is argued against the driver's real features and the
rejected paths' real defects; the unblended draw's 16384/16384 against the PSP's rule and the per-round block
counts against PPSSPP's dump are the right evidence; the single-draw-overlap limit is measured at 0 pixels, not
assumed.
Merged: into batch/m2 after 4765079's branch.
Notes: the capture-path finding is accepted as a wrong premise in the brief, reported exactly as the protocol
asks: the step-3 exit's 0.005 bar compares columns measured differently (the no-3D menu scenes carry the same
0.03-0.05 gap), so the bar is judged by tools/gerec/metal_check.sh's A/B on a Mac — docs/windows.md amended, the
Vulkan column re-baselined from three post-060 runs instead. README and setup follow-ups done at the merge.
GENERAL-layout cost on tiled/AMD GPUs (open question 4) recorded as an upstream-facing follow-up.
