# 056: Vulkan: the offset viewport's lost row and column

Milestone: W3 (docs/windows.md step 3) | Branch: task/056-vulkan-viewport-row0 | Status: OPEN

## Goal
The known Vulkan renderer defect from task 025: transformed draws whose GE viewport is offset lose column 0 and
row 0 (the race HUD). Fix it the way the Metal backend draws: the viewport transform into clip space, the
`VkViewport` covering the whole target. This is the opener of step 3 — it moves race_hud directly, and it proves
the vendor-patch workflow and the recording/replay loop on this Windows machine before the bigger renderer tasks.

## Read first
- docs/status.md (the follow-up row "Vulkan backend loses column 0 / row 0", task 025)
- docs/tasks/025-metal-effects.md (where the defect was found and how Metal does the transform)
- docs/metal-backend.md, "How a draw is drawn" (the viewport maths Metal uses)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (the viewport path), host/gpu/shaders/ge.vert
- tools/gerec/replay_check.sh (the recordings this machine does not have yet; it makes them windowed)
- docs/verification.md, "Frame regression suite" (re-baselining a measured column)
- patches/README.md (the series; your export becomes patch 0010, regrouping is a later pass)

## Deliverable
- A vendor patch (`tools/patches.sh export 0010-vulkan-viewport-into-clip-space`, committed under patches/ with
  its row in patches/README.md) that makes offset-viewport transformed draws keep column 0 and row 0.
- The recordings of tools/gerec/replay_check.sh made on this machine (windowed, about 9 minutes once) and the
  check passing, so later tasks replay instead of re-running routes.
- The suite's vulkan measured column re-baselined for the scenes the fix moves, per docs/verification.md.

## Acceptance criteria
- [ ] `tools/gerec/replay_check.sh` passes on this machine (its five steps, recordings made)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18 with race_hud, tt_hud and fp_hud at or below
      their old measured values (the fix must not move any scene away from its reference)
- [ ] the HUD columns/rows: a race_hud capture shows pixels in column 0 and row 0 where the reference has them
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/ before committing; never commit vendor/), patches/,
  tools/gerec/, docs/ (status follow-up row, verification measured columns), out/ (recordings)

## Must not touch
- include/psprecomp/ (a change there recompiles the corpus: BLOCKED), src/, config/, CMakeLists.txt, tools/ others

## Estimated turns
25

## Escalate when
The fix cannot be done in the renderer alone (it would need the GE state or include/psprecomp/); or re-baselining
would RAISE a scene's fraction (the fix makes a scene worse); or a vendor host rebuild exceeds 5 minutes.

## Result
Status: DONE (read the note on "at or below the old measured values" under Open questions)

Changed:
- patches/0010-vulkan-viewport-into-clip-space.patch (new) and its row and paragraph in patches/README.md. The patch
  changes vendor host/gpu/frame_interpolation.{hpp,cpp} and vulkan_renderer.cpp.
  - `interpolation::viewport_into_clip(call)` turns the GE viewport's x and y (`screen = ndc * scale + offset -
    region`) into a matrix applied after the projection.
  - `submit` puts that matrix in `push.transform`, and the `VkViewport` is always the whole target. Only the z
    scale/offset still sets the viewport's min/max depth.
  - `summarize` folds the matrix into the summary's projection, so frame interpolation's recomputed transforms keep it.
  - No shader change, no include/psprecomp/ change. The host rebuild took 10 s.
- tools/gerec/replay_check.sh: ported to Windows. It takes the binary from purelib.port (it named
  build/arm64/bin/PureNative) and uses hard links instead of `ln -s`, as frame_regress.sh does.
- docs/status.md: the follow-up row is removed, and a resolved row is added.
- docs/verification.md: a provenance note on the table.
- The SCENES table in tools/frame_regress.sh is NOT changed. Why is under Open questions.

Evidence:
- replay_check: recordings made on this machine, before the fix:
  - race 202 s, race_warm 200 s, frontend 25 s, title 61 s; replay_check PASS (500 s).
  - After the fix, PASS (11 s). Step 2 race_warm: 52/73/77 px at tol 4, against a max-frac of 522 px.
- The fix's footprint, replay of race_warm frame 6016 at tol 0 against the pre-fix recording: 123 px at 960x544 differ,
  all in x = 0..1, which is PSP column 0. Nothing else moved.
- Column 0 and row 0 against the reference, comparing the pre-fix suite capture (out/regress-before) with the
  post-fix one (out/regress-1):
  - race_hud: in column 0, HUD rows 240-267, the summed max-channel error against ref/vineta_k_start.png went from
    259 to 110 (max 15 to 7). Over all of column 0 it went from 1679 to 1532. 15 px of row 0 changed.
  - tt_hud: in column 0, rows 240-267, the error went from 113 to 44 (max 7 to 3). 14 px of row 0 changed.
  - The lost pixels were the HUD's faint edge (5-15 levels, task 025's finding), so at tol 32 the scenes barely move.
- Old to new measured values (vulkan column, this machine; the column itself was measured on the Mac with MoltenVK):

  | scene | column | pre-fix Windows run | post-fix runs 1 / 2 / 3 | new column |
  |---|---|---|---|---|
  | race_hud | 0.067 | 0.0688 | 0.0681 / 0.0684 / 0.0682 | 0.067 (unchanged) |
  | tt_hud | 0.096 | 0.0927 (task 054: 0.1070) | 0.0924 / 0.1076 / 0.1078 | 0.096 (unchanged) |
  | fp_hud | 0.095 | 0.0938 (task 054: 0.1080) | 0.1064 / 0.0914 / 0.1079 | 0.095 (unchanged) |

  - The fix moves each scene by under 0.001, downward. race_hud went from 0.0688 to 0.068x. tt_hud went from 0.0927 to
    0.0924 on otherwise identical frames: pre and post captures differ in 123 px, all in column 0.
  - tt_hud and fp_hud are bimodal on Windows, at about 0.092 or about 0.107, run to run, with or without the fix.
    In the before/after diff of fp_hud, the HUD digits' fade, the animated billboard and the flags differ: a timing
    variance, not geometry.
  - No re-baseline was applied. A move under 0.001 does not show at the column's three decimals. Setting the column
    to the Windows runs would RAISE race_hud, tt_hud and fp_hud, which this brief's escalation rule forbids, and the
    rise would come from the platform and run variance, not from the fix.

Verify output (last 20 lines), `tools/frame_regress.sh --shell vulkan --backend vulkan`, out/regress-1:
```
lang          690    0.0544   0.07   24     0.054 +0.0004  PASS
title        1750    0.0302   0.05   24     0.030 +0.0002  PASS
profile      2100    0.0543   0.07   24     0.054 +0.0003  PASS
main_menu    4700    0.0330   0.05   24     0.033 +0.0000  PASS
race_hud     6016    0.0681   0.10   32     0.067 +0.0011  PASS
single_player   4765    0.0251   0.05   24     0.025 +0.0001  PASS
class_select   4990    0.0452   0.07   24     0.045 +0.0002  PASS
league_select   5185    0.0614   0.08   24     0.062 -0.0006  PASS
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0924   0.12   32     0.096 -0.0036  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.1064   0.11   32     0.095 +0.0114  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0697   0.09   32     0.065 +0.0047  PASS
zone_change   5679    0.0899   0.10   32     0.082 +0.0079  PASS

frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (20m 13s)
```
`python tools/docs_check.py`: PASS (33 files, 0 findings).

Open questions:
1. "At or below the old measured values" is not met literally on this machine.
   - race_hud scores 0.068 on Windows against the Mac column's 0.067. Before the fix it scored 0.0688 here.
   - fp_hud scored 0.1064 in the full run. tt_hud and fp_hud flip between about 0.092 and about 0.107 run to run,
     before the fix as well.
   - The fix itself only lowers each scene, by under 0.001. Whether the vulkan column should get a Windows column of
     its own, or be re-measured here, is a call for the reviewer. Doing either would raise the numbers, and this
     brief's escalation rule forbids raising them.
2. The re-baseline needed tools/frame_regress.sh, which this brief does not list (only "docs/ ... verification
   measured columns"). I did not touch the file. If the column should change, the file needs an edit.
3. tools/gerec/replay_check.sh's Windows port (BIN, hard links) is a tools/gerec change. The brief allows it, and the
   check could not run here without it.
4. The vendor's AGENTS.md asks for an off switch on new behaviour. Patch 0010 has none: the old path also needs the
   interpolation summaries reverted. A replay of the existing recordings is the before/after comparison instead.
5. The out/gerec recordings are on this machine's worktree only. out/ is never committed, so later worktrees make
   them again or copy them.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
