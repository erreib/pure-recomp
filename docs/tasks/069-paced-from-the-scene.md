# 069: The window checks run unpaced to the scene (tools)

Milestone: tools (Erik, 2026-10-10) | Branch: task/069-paced-from-the-scene | Status: OPEN

## Goal
A windowed run is held to real time from boot, so each route of `tools/frame_regress.sh --shell metal|vulkan` takes
100 to 180 s through menus the window adds nothing to, and the two window suites plus `tools/hud_check.sh` cost
about 45 minutes per gate. Headless the same routes take 15 s. After this task the window checks run unpaced until
shortly before the first thing they capture and paced from there (`PURE_PACED_FROM=N`, as `tools/menu_check.sh`
already does), and the window suite captures only the scenes the shell can change: a window run of a menu scene is
pixel-identical to the backend's (task 065 proved 0 of 2088960 pixels on 14 scenes), so those stay headless.

## Read first
- CLAUDE.md, docs/verification.md ("The frame regression suite", "Which path for which change", the window
  wobble note), docs/tasks/065-metal-shell-retina.md (the capture proof), docs/tasks/034-*.md if present
  (`PURE_PACED_FROM`'s origin), README.md (`PURE_PACED_FROM`), docs/fidelity.md (the AI seed from the clock, task
  046: an unpaced frontend changes the race's random numbers)
- tools/frame_regress.sh (the SCENES table, the route loop, EXTRA_FLIPS, the `moved more than 0.03` line),
  tools/hud_check.sh, tools/menu_check.sh (the pattern), tools/purelib/port.py, tools/run_boot.py

## Deliverable
1. **frame_regress.sh**: for a window shell, each route runs with `PURE_PACED_FROM` = the route's first captured
   scene's flip minus 300 (a margin for the shell's first presents and the pre-warm), unless the caller passes
   `--paced-from N` or `--paced` (from boot, today's behaviour). Headless runs are unpaced already and unchanged.
   A new `--window-scenes` default for the window shells: the five race scenes (race_hud, tt_hud, fp_hud, zone_hud,
   zone_change) and one menu scene per route as a smoke test (main_menu and title), unless `--all-scenes`. The
   printed table says which scenes ran and the pacing used.
2. **hud_check.sh**: unpaced until 300 flips before its first shot (6200), paced from there.
3. **The columns re-measured once.** The race scenes' window values move with the race's seed (an unpaced frontend
   gives the clock another reading at TEAM SELECTION). Take three window runs per shell, record the median as the
   new measured value in the SCENES table with the run range in the comment, and update docs/verification.md's
   table and its wobble note. The headless (Metal) column is untouched: nothing headless changes.
4. **The timing**: before and after, for `--shell metal --backend metal`, `--shell vulkan --backend vulkan` and
   `tools/hud_check.sh`, in docs/verification.md.
5. `tools/bundle.sh`'s route and finder checks are not changed (they test the app as a player starts it).

## Acceptance criteria
- [ ] `tools/frame_regress.sh --shell metal --backend metal` and `--shell vulkan --backend vulkan` PASS with the new
      default scene set in under 5 minutes each; `--all-scenes` still PASSes in both shells (the full table, now
      paced from the scene); `tools/hud_check.sh` PASS 61/61 in under 2 minutes.
- [ ] The headless suite is byte-for-byte unchanged: `tools/frame_regress.sh` 18/18 with every value identical to
      before, and `tools/refactor_check.sh` PASS against before captures from the starting commit.
- [ ] Every window value that moved is re-measured (three runs, the median) and within its limit; the `moved more
      than 0.03` line fires on none of the three runs after the re-measure.
- [ ] docs/verification.md's tables and timings updated; `python3 tools/docs_check.py` 0 findings.

## Verify
`tools/frame_regress.sh && tools/frame_regress.sh --shell metal --backend metal && tools/hud_check.sh`

## May touch
- tools/frame_regress.sh, tools/hud_check.sh, tools/purelib/port.py (only if the paced-from plumbing belongs there),
  docs/verification.md, README.md (the tools' rows)

## Must not touch
- src/, vendor/, patches/, config/, ref/, tools/run_boot.py, tools/refactor_check.sh, tools/scale_check.sh,
  tools/menu_check.sh, tools/bundle.sh, tools/gerec/

## Estimated turns
35

## Escalate when
A window scene captured paced-from-the-scene fails its limit on all three runs where it passed paced-from-boot
(report the scene and the three values: the pacing changed the picture, not only the seed); the shell's first
presents after the switch to paced show a hitch that reaches a captured scene (report the trace).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
