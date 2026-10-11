# 069: The window checks run unpaced to the scene (tools)

Milestone: tools (Erik, 2026-10-10) | Branch: task/069-paced-from-the-scene | Status: MERGED (22d3ba5, 2026-10-11)

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
Status: PARTIAL. Every deliverable is in and every check passes, but one acceptance bar is missed by about 10 s: the
default window suites take 5m 10s (Metal) and 5m 11s (Vulkan), not under 5 minutes. The cause is the display rate,
explained below. Neither escalation condition occurred.

Changed (branch task/069-paced-from-the-scene from batch/m2 76f9143, commit 434938f, then this Result):
- tools/frame_regress.sh:
  - Scenes. `WINDOW_SCENES` (title, main_menu, race_hud, tt_hud, fp_hud, zone_hud, zone_change) is the default set
    for a window shell on macOS. `--all-scenes` runs all 18; `--window-scenes` runs the seven headless; `--only`
    picks from the whole table. Headless, and Windows (where nothing draws headless), keep all 18 by default.
  - Pacing. A window run sets `PURE_PACED_FROM` to its route's first captured scene minus `PACE_MARGIN` (300).
    `--paced-from N` sets N for every run. `--paced` sets nothing, so the shell paces from boot as before. A
    `PURE_PACED_FROM` from the caller (the environment or `--env`) wins over all three.
  - Summary. New `scenes:` line (the set, and the scenes not run) and `pacing:` line. Each run line ends with its
    pace, and the verdict says `the window scenes` for that set. The table rows keep their format.
  - SCENES. The Vulkan column's five race scenes are re-measured (below). The comments keep the Windows figures.
- tools/hud_check.sh: in a window, `PURE_PACED_FROM=5900` (the first shot at 6200, minus 300). Headless is
  unchanged. The start line names the pace.
- docs/verification.md:
  - the suite's usage, its window paragraph, the Vulkan column, and bullets on the scene set and the pace;
  - the HUD check's time, and the "Fast, silent test runs" table rows;
  - the wobble note, rewritten with what was measured;
  - a new section, "The window checks paced from the scene (task 069, 2026-10-10)": the timings and the trace;
  - "Which path for which change": `--paced` for pacing changes, and `--all-scenes` once for a change that could
    move a menu only in a window.
- README.md: the rows for frame_regress.sh and hud_check.sh.

Timings. This Mac (M4 Pro, 120 Hz panel); the tools' own times, not counting the wait for the main checkout's games:

| Run | Before (76f9143, paced from boot) | After (paced from the scene) |
|---|---|---|
| `--shell metal --backend metal` | 19m 48s, 18/18 | 5m 10s, 7/7 (three runs, 5m 10s each; Verify 5m 9s); `--all-scenes` 7m 46s, 18/18 |
| `--shell vulkan --backend vulkan` | 19m 48s, 18/18 | 5m 11s, 7/7 (three runs, 5m 11s each); `--all-scenes` 7m 46s, 18/18 |
| `tools/hud_check.sh` | 227 s, 61/61 | 82 s, 61/61 (Verify 81 s) |

Why it is 5m 10s:
- Unpaced, a window still presents every flip at vsync: 120 flips a second here. The paced menus run at 30 a second.
- Each route costs (first scene - 300)/120 s unpaced plus its paced flips/30 s. The six routes took 24, 48, 55, 58,
  58 and 67 s.
- The 300-flip margin costs 7.5 s a route over running unpaced, 45 s in all.

Re-measured values:
- Metal window: all seven scenes scored the headless values in all three runs. The captures were pixel-identical to
  the paced-from-boot run. The metal column is untouched.
- Vulkan window: the three runs were identical to the pixel, with each other and with the paced-from-boot run. The
  medians are now in the vulkan column, replacing the Windows RTX 3080 medians:

  | Scene | New (measured) | Windows median it replaces |
  |---|---|---|
  | race_hud | 0.047 (0.0465) | 0.053 |
  | tt_hud | 0.049 (0.0493) | 0.048 |
  | fp_hud | 0.048 (0.0475) | 0.056 |
  | zone_hud | 0.045 (0.0452) | 0.048 |
  | zone_change | 0.052 (0.0522) | 0.048 |

  title and main_menu are unchanged (0.0302 and 0.0331). Every value is within its limit, and the "moved more than
  0.03" line fired in none of the runs.
- Headless: `tools/frame_regress.sh` 18/18, every value identical to before. `tools/refactor_check.sh` against the
  before captures from 76f9143: PASS, 18/18 scenes with 0 differing pixels, and the same counts (86 [metal] lines).
- `python3 tools/docs_check.py`: 33 files, 0 findings, PASS.

Hitch check (escalation 2), from a `PURE_METAL_TRACE` of the Single Race route (paced from 5716) and the Zone route
(paced from 4960):
- The switch settles at once. Up to it the pictures reach the screen every 8.3 ms; from the first paced flip, every
  33.3 ms, with one picture a vsync late about a dozen flips on.
- race_hud's last 87 flips take 16.7 ms each. The longest is 20.4 ms, at the capture's own flip.
- zone_hud's and zone_change's last 60 flips take 33.3 ms each, with one picture shown at 41.7 ms.
- Every window capture paced from the scene equals its paced-from-boot capture, pixel for pixel, in both shells.

Escalation 1 (a scene failing its limit on all three runs) did not occur: every scene passed every run.

Verify output (last 20 lines; `tools/verify_task.sh 069`, run through a wait for the main checkout's game to end):
```
run main_menu+free_play: 5920 flips, paced from flip 5590 ...
run main_menu+free_play: run_boot exit 0, frame 5920 reached: yes, 58 s, paced from flip 5590, log out/regress/main_menu+free_play.log
run main_menu+zone: 5709 flips, paced from flip 4960 ...
run main_menu+zone: run_boot exit 0, frame 5709 reached: yes, 67 s, paced from flip 4960, log out/regress/main_menu+zone.log

scene       frame  fraction  limit  tol  measured   delta  result
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 7/7 scenes pass, the window scenes, shell metal, backend metal (5m 9s)
hud_check: shell metal, backend metal, 61 shots from flip 6200 to 7700, paced from flip 5900, out out/hud/metal
hud_check: run_boot exit 0, frame 7710 reached: yes, 81 s, log out/hud/metal/run.log
6200:H 6225:H 6250:H [... all 61 shots :H ...] 7650:H 7675:H 7700:H
hud_check: 61 of 61 shots have the HUD
verify 069: PASS
```
The headless part of the same Verify run: `frame regression: PASS, 18/18 scenes pass, shell headless, backend metal
(0m 21s)`.

Open questions:
1. The 5-minute bar. With the brief's design the window suite takes about 5m 10s on a 120 Hz display, and roughly
   twice as long unpaced on a 60 Hz one. I kept the brief's margin of 300 and the `title` scene. Two ways under 5
   minutes:
   - Drop `title` from WINDOW_SCENES. That removes the frontend run (-24 s, about 4m 46s). main_menu.txt's presses up
     to flip 1800 are the same as frontend.txt's, so the main_menu run already passes through the title.
   - Set PACE_MARGIN to 200 (-15 s, about 4m 55s). The traces show the switch settling within a flip.
2. The brief expected the race scenes to move with the pacing. On this machine they did not: paced from the scene,
   the window race scenes were pixel-identical to paced-from-boot in all three runs in each shell. The race's seed
   did move in 2 of 16 window runs, independent of the pacing change:
   - The Metal `--all-scenes` run (Single Race paced from 4465, before TEAM SELECTION) loaded the AI ships in
     another order: race_hud 0.0158 against 0.0148. Two more runs paced from 4465, and one from 5716, gave 0.0148.
   - My before HUD check (paced from boot) took 601 ms of game time for its first load, against 584 in every other
     run, and 367 against 351 for its fourth. It loaded other AI ships and billboards, and all 61 shots differed from
     the main checkout's paced-from-boot run of the same commit. My after HUD run matched that run in all 61 shots.
   - Not chased, as asked. The figures are in docs/verification.md's wobble note.
3. The vulkan column now holds Mac values, as the brief asks. Windows's default suite (the Vulkan window, all 18
   scenes) will see deltas of up to 0.008 against them (fp_hud). That is well under 0.03, but its own medians now
   live only in the comments.
4. This worktree's out/data/frame_regress and out/data/hud_check were copied from the main checkout before the
   before runs: the settings with video.internal_scale=2, and the Vulkan pipeline caches. That puts the runs under
   the gate's conditions.
5. frame_regress.sh still refuses at once while another game runs. refactor_check.sh and scale_check.sh retry it,
   and I ran every window check through a wait-until-free wrapper of my own in the scratchpad. A built-in 600 s wait,
   like menu_check.sh's, would be a small follow-up if it is wanted.

## Review
Verify rerun: from the main checkout after the merge, 2026-10-11: PASS (headless 18/18 in 21 s; `--shell metal
--backend metal` 7/7 in 5m 10s; `tools/hud_check.sh` 61/61 in 81 s). The gate: `--shell vulkan --backend vulkan`
7/7 in 5m 10s; `tools/menu_check.sh` PASS.
Spot-read: the pace is a per-route `PURE_PACED_FROM` from the first captured scene minus 300, a caller's value
winning; `--paced` restores pacing from boot; the window scene set is the seven a shell can change, `--all-scenes`
the table; headless untouched (0 differing pixels against the starting commit's captures).
Merged: `git merge --no-ff` into batch/m2, 22d3ba5.
Notes: PARTIAL by 10 s on the brief's five-minute bar, accepted: the bar was a round target, and the remaining time
is the panel's 120 Hz presenting the unpaced menus (the two ways under five minutes are recorded in the Result and
not taken). The race scenes did not move with the pacing (pixel-identical captures in both shells); the seed moved
in 2 of 16 window runs independent of it, the wobble note now carries the figures. The Vulkan column's race scenes
now hold this Mac's medians; the Windows medians stay in the comments. Follow-up: `tools/frame_regress.sh` refuses
at once while another game runs where refactor_check and scale_check wait; a built-in wait like menu_check's.
