# 091: The display rate's margin (E8: no audio skips at the display's rate)

Milestone: E8 | Branch: task/091-display-rate-margin | Status: MERGED

## Goal
At the Display rate the game runs a small margin under the display's refresh instead of exactly at it, so a race at
the display's rate keeps real time and its audio plays without skips, on both renderers. Erik heard audio stutter
on Vulkan at Display (2026-10-14); the diagnosis is below. A new check proves the result by counting the audio
sink's skips over a race with sound in the window, and the margin is chosen by that measurement.

## The diagnosis (2026-10-14, the planning session; out/e8audio/ in the main checkout)
At a game rate equal to the display's refresh, vsync becomes the clock that paces the game: a frame that misses
its refresh is real time lost for good, since the game can never present faster than the display to make it up.
The audio is produced on the game's clock (the sink's stalled-producer jump of patch 0024-audio-resync-counter, the
law of task 081), so it falls behind and the sink skips. At the PSP's rate on a 120 Hz display the game has room
to catch up (the display takes up to 120 a second). The plain race route with sound, `PURE_TRACE_AUDIO=1`,
`PURE_PERF=log`, `PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=11`, about 75 s of racing in the window on this Mac's
120 Hz display, each lane on its own fresh stick:

| Lane | Audio skips (`resyncs`) | Seconds under 99% speed | Submits blocked over 8 ms |
|---|---|---|---|
| Vulkan, Display, 120 Hz | 13 | 8 | 21 |
| Metal, Display, 120 Hz | 33 | 17 | 0 |
| Vulkan, `PURE_DISPLAY_HZ=119.4` | 1 | 0 | 0 |
| Metal, `PURE_DISPLAY_HZ=119.4` | 1 | 0 | 0 |
| Vulkan, Original (59.94) | 1 | 0 | 1 |

The single skip of the clean lanes is at the race load, at every rate. Vulkan's misses are costlier (its swapchain
has 2 images under FIFO, and MoltenVK blocks `vkQueueSubmit` 11 to 35 ms for a drawable), which is the visible
hitch beside the click; Metal's are shorter and more frequent. The lanes' script and logs are in
/Users/erreib/dev/pure-recomp/out/e8audio/ (run.sh, run3.sh, route.txt, *.log): read them, and copy the method,
not the files.

## Read first
- docs/decisions.md D-022 (as amended) and docs/timing.md "E8"; docs/tasks/089-display-rate.md (its Result and
  Review)
- src/profile/enhancements.cpp: `display_hz()`, `race_backend()`, `display_rate()` (the period and its line), the
  `display_rate` row's description in `kOptions`
- tools/display_rate_check.sh (the route and `--race` variants; how they set `PURE_DISPLAY_HZ`)
- tools/purelib/port.py: `fresh_stick` (an empty memory stick in a scratch game directory: every run of this task
  passes `PURE_GAME_DIR` to one; `run_boot.py --data-dir` alone still saves into the repository's game/ms0, which
  must not happen), `headless_run` (its `game=` argument), `ENHANCEMENTS_OFF`, `SCRATCH_SETTINGS`
- tools/run_boot.py (`--shell`, `--backend`, `--script`, `--frames`, `--sound`, `--env`, `--data-dir`)
- vendor/portablekit/host/audio/audio_sink.cpp with patch 0024's `[audio]` line (`resyncs=`, `lead=`)
- docs/verification.md (the E8 rows, "Which path for which change"), docs/developing.md (the switch and tool rows),
  docs/controls.md (the Display rate row); CLAUDE.md

## Deliverable
1. The margin: `display_rate()` sets the race's period from the display's refresh times (1 + margin) in time, that
   is `llround(1e6 / (hz * (1 - margin)))`, the margin a constant you choose by measurement (item 3), with a
   test-only `PURE_DISPLAY_MARGIN=<fraction>` that overrides it (0 restores the exact display rate, for the
   comparison). `PURE_DISPLAY_HZ` keeps naming the display's refresh, the margin applying to it as to the shell's.
   The `[pure] display rate` line says both: `120 Hz display, the game at 119.4 Hz (8375 us a vblank)` or similar,
   once a change as now. The row's help text says the game runs just under the display's rate to keep the sound
   continuous.
2. `tools/display_rate_check.sh --audio [--shell metal|vulkan] [--margin F]`: the main_menu + single_race route
   with Cross held for the race (the route of out/e8audio/route.txt: single_race.txt's last hold lengthened) in the
   window (default the platform's shell: metal on macOS, vulkan under MINGW), Display on, the display's own
   refresh (no `PURE_DISPLAY_HZ`; refuse with exit 2 and a line when the shell reports 60.5 Hz or less, since there
   is nothing to measure), sound on, `PURE_TRACE_AUDIO=1 PURE_PERF=log`, a fresh stick, paced from 5900, about 75 s
   of race; `--margin` sets `PURE_DISPLAY_MARGIN` for the run. From the race load's `[pure] display rate` line to
   the run's end: PASS when the race's `[audio]` lines count at most 1 resync (the race load's, as at the PSP's
   rate) and no `[perf]` second is under 99% speed after the first 3 s of the race; print the resyncs, the seconds
   under 99%, the presents and the game's rate a second (medians), and the margin and period in force. About
   2.5 minutes.
3. Choose the margin: run `--audio` on both shells at margins 0.005, 0.0025 and 0.001 (and 0, which must fail as the
   diagnosis says), two runs each where time allows, and take the smallest margin at which every run of both
   shells passes. Put the table in the Result and in docs/timing.md "E8". If none of them passes on both shells,
   say so and stop (escalation).
4. The route check: with the margin the race's flips a race-clock second at `PURE_DISPLAY_HZ=120` become 120 x (1 -
   margin); adjust its race bound so it is centred there, and print the margin. `--race` likewise.
5. Docs: docs/timing.md "E8" (the diagnosis above with the table, the margin's measurement, why the exact rate
   cannot hold real time under vsync); docs/developing.md (`PURE_DISPLAY_MARGIN`, the `--audio` variant);
   docs/verification.md (the E8 row gains `--audio`, and the "Which path" line for a change to the display rate or
   the presents names it on both shells); docs/controls.md (the row's text); docs/windows.md (a rig item: `--audio
   --shell vulkan` at its 100 Hz display); docs/status.md (the E8 bullet: the stutter and its fix, the figures).

## Acceptance criteria
- [ ] `tools/display_rate_check.sh --audio` PASS on Metal and `--audio --shell vulkan` PASS on this Mac at the
      chosen margin; `--audio --margin 0` FAILs on at least one shell (the comparison stands); figures in the Result.
- [ ] `tools/display_rate_check.sh` (the route) PASS with its adjusted bound; `--race` PASS.
- [ ] At the PSP's rate nothing moves: `tools/frame_regress.sh` 18/18, `tools/framerate_check.sh` PASS,
      `tools/menu_check.sh` PASS.
- [ ] `python3 tools/docs_check.py` PASS. No vendor change. game/ms0 untouched (`git status` and a listing of
      game/ms0/PSP/SAVEDATA before and after: the same).

## Verify
`tools/display_rate_check.sh && tools/display_rate_check.sh --audio && tools/display_rate_check.sh --audio --shell vulkan && tools/frame_regress.sh && tools/framerate_check.sh && tools/menu_check.sh && python3 tools/docs_check.py`

## May touch
- src/profile/enhancements.cpp and .hpp
- tools/display_rate_check.sh, tools/purelib/port.py (a helper only if needed)
- docs/timing.md, docs/developing.md, docs/verification.md, docs/controls.md, docs/windows.md, docs/status.md,
  docs/tasks/091-display-rate-margin.md

## Must not touch
- vendor/ (the swapchain's image count and the presents are a separate question, recorded as open), src/gpu/,
  src/host/, vendor/portablekit/include/psprecomp/, config/, generated/, game/ (above all game/ms0), disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
40

## Escalate when
- No margin up to 0.005 passes `--audio` on both shells (then the presents themselves must stop holding the game
  thread, a renderer change: report the figures).
- The skips persist at a margin while no second is under 99% speed (then the sink loses audio for another reason:
  report the `[audio]` lines).
- Anything would touch vendor/, src/gpu/ or src/host/, or write to game/ms0.

## Progress (paused)
Paused 2026-10-15 at the coordinator's word: Erik needed his screen back. No margin is chosen yet.
(Kept as the record of the first session; the Result below supersedes it.)

**What is built** (on task/091-display-rate-margin, uncommitted to batch/m2):
- **The margin** (src/profile/enhancements.{cpp,hpp}):
  - The period is `llround(1e6 / (hz * (1 - margin)))`.
  - `kDisplayMargin = 0.0025` is a placeholder, not yet measured.
  - `PURE_DISPLAY_MARGIN=F` overrides it (0 to below 0.5).
  - The lines read `120 Hz display, the game at 119.70 Hz in a race (margin 0.0025), the PSP's 59.94 Hz outside one`
    and `120 Hz display, the game at 119.70 Hz (margin 0.0025, 8354 us a vblank)`.
  - The row's help says the race runs a fraction under the display's rate so the sound stays continuous.
- **tools/display_rate_check.sh**:
  - `--margin F` works with every variant. The route and `--race` read the margin and period from the lines, check the
    period, and centre the race bound on 120 x (1 - margin), plus or minus 3.
  - `--audio [--shell]` is the brief's run: Auto internal scale and the shipped Video defaults, a fresh stick and a
    scratch data directory under `<out>`, run under `caffeinate -d -u`.
  - The window guard: a run FAILs as "the window was not on screen" when its unpaced race load presents more than 1.5
    times the display's refresh.
  - The probe refusal (exit 2 when the unpaced boot shows the same): the first try ran the probe paced, so it could not
    see this. It now sets `PURE_PACED_FROM` and is **untested**.
- **tools/winwatch.m**: the window-list watcher, which says what covers the game window.

**Valid window runs** (window on screen at the race load), all on Metal at Auto (scale 4, 1920x1088):

| Run | Margin | Resyncs | Seconds under 99% | Presents / game, medians | Note |
|---|---|---|---|---|---|
| out/e8m/metal-m0.005-1 | 0.005 | 1 (the load's) | 4 (98, 98, 98, 96%) | 119.5 / 119.4 | the sound held; FAIL on the speed bound |
| out/e8m/metal-default-1 | 0.0025 | 50 in 40 s | 23 (two of them 20% and 41%: 1 s stalls) | 116.05 / 119.7 | 2026-10-14; Erik stopped it at race second 43; disturbed |

**Void runs.** Each had the window off screen: unpaced menus at about 1800 to 1960 presents a second, and the race
load at 470 to 830 or too fast to log.

| Lane | Runs | Their (meaningless) result |
|---|---|---|
| Metal, 0.005 | runs 2 to 5, and probe-test | 1 resync each; 0 slow seconds, except run 2 with one at 98% |
| Vulkan, 0.005 | runs 1 to 3 | 1 resync each, 0 slow seconds |
| Metal, 0 | metal-m0-1 | see below |

- **The cause.** The watcher (runs 4 and 5 on Metal, run 3 on Vulkan) shows the game window on screen at 276,188,
  960x572 points, with a Google Chrome window covering 100% of it from 2 s to the end. macOS 15 does not bring the new
  window to the front. An activation request on the game's process (`winwatch ... activate`) was ignored, and hiding
  Chrome was refused by the permission classifier, so it was not done.
- **metal-m0-1** (margin 0) was off screen at the load (473 presents a second) but vsync-bound in the race:
  - 105 resyncs and 61 seconds under 99%, two of them 1 s stalls (34% and 20%), medians 117.5 / 120.0.
  - It reproduces the failure at the exact rate, but the guard voids it.
- **The diagnosis was off screen too.** In out/e8audio, the 119.4 lanes on both shells and Vulkan at Original had
  their menus at 1300 to 2900 presents a second. Their clean result (1 resync, 0 slow seconds) is therefore unproven.
  Only the two 120 lanes had the window on screen (menus at 120). Those ran Metal at internal scale 1, run_boot's
  default; this check runs Auto.

**Headless, done at the placeholder 0.0025:**
- The route: PASS. The race made 119.72 flips a race-clock second against the bound of 116.70 to 122.70. The lines
  and the period 8354 were checked. With `--margin 0` it also PASSes: 120.00, period 8333.
- `--race`: PASS.
  - Flips: 59.96 and 119.39 a race-clock second; the game clock 1.0001 and 0.9983.
  - The start: 39.3/77.5/121.1 against 38.7/76.9/120.5 km/h.
  - Contacts: 15.0 and 15.3 a lap.
  - Mean lap: 61.83 and 60.73 s; the first speed pad 0.064 s and 3.23 m early.
- `tools/frame_regress.sh` 18/18, `tools/framerate_check.sh` PASS, `tools/menu_check.sh` PASS.

game/ms0/PSP/SAVEDATA is unchanged in both places: the worktree's is empty before and after, and the main checkout's
has the same 13 entries with the same sizes and times.

**Left to do:**
1. With the game window uncovered (Chrome moved or minimized, the window on the current Space), test the probe's
   refusal once.
2. Run the sweep: margin 0 on both shells, then 0.005, 0.0025 and 0.001 on both, two runs each. Run a third when two
   disagree or a run fails on one lone event, and decide by two of three.
3. Decide whether the "no second under 99%" bound fits Metal at Auto. Metal's one valid run at 0.005 kept the sound
   (1 resync) but had 4 seconds at 96 to 98%. If every margin fails only on that bound, it is the brief's escalation
   (the presents holding the game thread) or a review call on the bound.
4. Set kDisplayMargin from the sweep, then rerun the route and `--race` if it changes.
5. Write the docs: timing.md "E8", developing.md, verification.md, controls.md, windows.md, status.md.
6. Run the full Verify, and fold the WIP commits into logical ones.

## Result

**Status: DONE.** The margin is **0.005**: the race at a 120 Hz display runs at 119.40 Hz, 8375 us a vblank. It is the
smallest of the brief's margins at which every run on both shells passes `--audio` under the review's bound (at most 1
resync, no second under 95% speed; the seconds under 99% reported). At 0.0025 Vulkan fails twice and Metal passes
twice; at margin 0 Vulkan fails with 9 resyncs. Verify PASS. game/ms0 is untouched: this worktree's
game/ms0/PSP/SAVEDATA is empty before and after, and the main checkout's has the same 13 entries with the same sizes
and times. The branch starts from batch/m2, with nothing in vendor/, src/gpu/ or src/host/.

### Changed
- **src/profile/enhancements.cpp and .hpp**
  - The period is `llround(1e6 / (hz * (1 - margin)))`, with `kDisplayMargin = 0.005`.
  - `PURE_DISPLAY_MARGIN=F` (test-only, 0 to below 0.5) overrides it; 0 is the exact display rate.
  - The lines: `[pure] display rate: 120 Hz display, the game at 119.40 Hz in a race (margin 0.005), the PSP's
    59.94 Hz outside one` and `[pure] display rate: 120 Hz display, the game at 119.40 Hz (margin 0.005, 8375 us a
    vblank)`, once a change.
  - The Display rate row's help adds "a fraction under the display's rate so the sound stays continuous".
- **tools/display_rate_check.sh**
  - `--margin F` sets `PURE_DISPLAY_MARGIN` for the run at the display's rate in every variant.
  - The route and `--race` read the margin and period from the lines, check the period against
    round(1e6 / (120 x (1 - margin))) and centre the race bound on 120 x (1 - margin), plus or minus 3. They print
    both.
  - New `--audio [--shell metal|vulkan]`, the brief's run:
    - Setup: a fresh stick (`port.fresh_stick`) and a scratch data directory under `<out>`, the shipped Video
      defaults at internal scale Auto, `PURE_DISPLAY_RATE=1` at the display's own refresh, `PURE_TRACE_AUDIO=1
      PURE_PERF=log`, paced from 5900 to about 75 s of race, under `caffeinate -d -u` on macOS.
    - The pass rule (the review's call): at most 1 resync from the race load's line to the end, and no `[perf]`
      second under 95% after the first 3. The seconds under 99% are counted and printed.
    - A window guard, which the brief did not ask for: a covered window presents without vsync and measures nothing.
      A probe of 600 unpaced boot flips refuses with exit 2 when the window presents over 1.5 times the refresh, or
      when the display is not above 60.5 Hz. The run FAILs as "not on screen" when its unpaced race load does the
      same.
    - It refuses `--shell` without `--audio`, and unsets `PURE_DISPLAY_HZ` and `PURE_DISPLAY_MARGIN` from its own
      environment.
- **tools/winwatch.m** (new): a read-only window-list watcher, outside the brief's "May touch", added at the
  coordinator's request. It prints PureNative's window and what covers it. Built by hand; it never moves or raises a
  window.
- **Docs:**
  - docs/timing.md "E8": the period's formula and the new lines, and a new section, "The margin (task 091)", with
    why, the diagnosis's table, the off-screen finding, the sweep, and what the margin moves elsewhere.
  - docs/developing.md: the check's row, the `PURE_DISPLAY_RATE` and `PURE_DISPLAY_HZ` rows, and new rows for
    `PURE_DISPLAY_MARGIN` and tools/winwatch.m.
  - docs/verification.md: the E8 row gains `--audio`. A new "Which path" row covers the display rate's period or
    margin, the presents and the pacer's hold: `--audio` on both shells. The enhancement row names it.
  - docs/controls.md: the row's text.
  - docs/windows.md: the rig item for `--audio --shell vulkan` at 100 Hz (99.50 Hz, 10050 us), and the 089 item
    pointed at the new lines.
  - docs/status.md: the E8 bullet.
  - This file.

### The margin table
All runs: `tools/display_rate_check.sh --audio [--shell vulkan] --margin F` on this Mac's 120 Hz display, about 75 s of
race each. tools/winwatch.m ran beside every run after the pause; the window was on screen at the race load in all of
them, judged by its unpaced presents.

| Margin | Shell | Run (out/) | Resyncs | Under 95% | Under 99% | Presents / game (medians) | Result |
|---|---|---|---|---|---|---|---|
| 0 | Vulkan | e8s/vulkan-0-a | 9 | 0 | 6 | 120.0 / 120.0 | FAIL |
| 0.0025 | Vulkan | e8s/vulkan-0.0025-a | 4 | 0 | 5 | 120.0 / 119.7 | FAIL |
| 0.0025 | Vulkan | e8s/vulkan-0.0025-b | 5 | 0 | 5 | 120.0 / 119.7 | FAIL |
| 0.0025 | Metal | e8s/metal-0.0025-a | 1 | 0 | 1 | 119.8 / 119.7 | PASS |
| 0.0025 | Metal | e8s/metal-0.0025-b | 1 | 0 | 0 | 119.7 / 119.7 | PASS |
| 0.005 | Vulkan | e8s/vulkan-0.005-a | 1 | 0 | 2 | 119.9 / 119.4 | PASS |
| 0.005 | Vulkan | e8s/vulkan-0.005-b | 1 | 0 | 3 | 119.5 / 119.4 | PASS |
| 0.005 | Vulkan | Verify (the default) | 1 | 0 | 2 | 119.6 / 119.4 | PASS |
| 0.005 | Metal | e8m/metal-m0.005-1 (before the pause, no watcher) | 1 | 0 | 4 | 119.5 / 119.4 | PASS |
| 0.005 | Metal | e8s/metal-0.005-b | 1 | 0 | 2 | 119.4 / 119.4 | PASS |
| 0.005 | Metal | Verify (the default) | 1 | 0 | 2 | 119.4 / 119.4 | PASS |

- **0.001** was not run: a smaller margin cannot pass where 0.0025 failed on Vulkan.
- **No cell needed a third run.** The runs in each cell agree, and no failure was a lone event: Vulkan's at 0.0025 had
  3 and 4 extra resyncs.
- **0.005's seconds under 99%** (2 to 4 a run) are no worse than 0.0025's on Vulkan, so the review's preference for a
  larger margin does not arise.
- **The cost of the margin:** one repeated refresh every 1.7 s (the same picture shown twice).
- **Void runs.** Metal at margin 0 was measured once, before the pause (e8m/metal-m0-1): 105 resyncs, 61 seconds under
  99%, two of them 1 s stalls. Its window was off screen at the race load, so the guard voids it. The Progress section
  above lists that run and the void runs at 0.005 with their cause: a Chrome window covering the game's 100%.
- **The covered sample.** The watcher saw one covered sample in all the resumed runs: metal-0.005-b's new window at 6 s,
  behind Terminal (96%) for one 2 s sample in the unpaced menus, before it came to the front. I took it as the launch
  order: the race load was vsync-held (116 presents a second), and no later sample in any run was covered.

**Other figures at 0.005:**
- The route: PASS.
  - Frontend: 29.84 / 29.84 flips a second.
  - Race: 59.96 / 119.41 flips a race-clock second, bound 116.40 to 122.40.
  - Fade: 1.90 and 1.89 s, in 57 and 113 flips.
- `--race`: PASS.
  - Flips: 59.95 and 119.41 a race-clock second; the game clock 1.0001 and 1.0011 s a second.
  - The start: 39.3/77.5/121.1 against 38.9/77.2/120.6 km/h.
  - Contacts: 15.3 and 13.0 a lap.
  - Reported, not bounded: the mean lap 58.60 and 58.27 s (-0.57%), the 2.0 s bin 168.2 and 176.5 km/h, and the first
    speed pad 0.050 s and 2.53 m early.
- The route at `--margin 0` still passes (120.00, 8333 us).
- In Verify, the probe's pass path read 120.0 and 119.0 unpaced presents a second.

### Verify output (last 20 lines)
```

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
framerate_check: route, shell headless, backend metal, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a0c5b2fc55d688270/out/framerate_check/route-metal-headless
framerate_check: PURE_SIXTY_FPS=0: run_boot exit 0, frame 7000 reached: yes, 7 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a0c5b2fc55d688270/out/framerate_check/route-metal-headless/0/run.log
  hud_check: 1 of 1 shots have the HUD
framerate_check: PURE_SIXTY_FPS=1: run_boot exit 0, frame 7000 reached: yes, 6 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a0c5b2fc55d688270/out/framerate_check/route-metal-headless/1/run.log
  hud_check: 1 of 1 shots have the HUD
PURE_SIXTY_FPS=0: frontend flips 4000-5000 median 33.37 ms; race flips 6300-6900 median 33.37 ms, 29.97 flips a race-clock second; lines ['[pure] sixty fps: off (after flip 0)']; hud_check: 1 of 1 shots have the HUD; 7 s
PURE_SIXTY_FPS=1: frontend flips 4000-5000 median 33.37 ms; race flips 6300-6900 median 16.68 ms, 59.94 flips a race-clock second; lines ['[pure] sixty fps: on (game.sixty_fps) (after flip 5704)']; hud_check: 1 of 1 shots have the HUD; 6 s
framerate_check: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms and 29.97/59.94 flips a second, off/on; the HUD drawn at 60)
menu_check: shell metal, out out/menu_check/metal
menu_check: run_boot exit 0, 24 s, log out/menu_check/metal/run.log
tabs: ok (4)
Video: ok (16)
Audio: ok (4)
Controls: ok (32)
System: ok (15)
menu_check: PASS
docs_check: 35 files, 0 findings: PASS
verify 091: PASS
```
Earlier in the same Verify:
- The route: `display_rate_check: PASS (frontend 29.84/29.84 and race 59.96/119.41 flips a second, PSP/120; the
  margin 0.005 at 120 (116.40 to 122.40); fade 1.90 and 1.89 s (-0.5%), 57 and 113 flips (x1.98); the HUD drawn at
  both)`.
- Metal: `display_rate_check: PASS (audio, metal, margin 0.005, 8375 us a vblank: 1 resync, 0 seconds under 95% and 2
  under 99% (reported), medians 119.4 presents and 119.4 game flips a second)`.
- Vulkan: `display_rate_check: PASS (audio, vulkan, margin 0.005, 8375 us a vblank: 1 resync, 0 seconds under 95% and 2
  under 99% (reported), medians 119.6 presents and 119.4 game flips a second)`.

### Open questions
- **The diagnosis's clean lanes were off screen.** Its 119.4 lanes on both shells and Original on Vulkan had their
  menus at 1300 to 2900 presents a second. Their clean result measured nothing; the table above replaces them.
  docs/timing.md says so.
- **This check runs internal scale Auto** (4 on Metal, 2 on Vulkan), a player's default, where the diagnosis ran Metal
  at scale 1 (run_boot's default).
- **Not measured:**
  - Metal at margin 0 with the window on screen throughout (only the voided run).
  - Original on screen.
  - The rig's 100 Hz display (docs/windows.md item).
- **Why Vulkan fails at 0.0025 and Metal does not** is a guess, not traced: Vulkan's misses block its submits longer
  (2 swapchain images under FIFO). The swapchain and the presents holding the game thread remain the renderer question
  the brief set aside.
- **The probe's refusal path** (a covered window) is untested by design (the coordinator's call). Its pass path ran in
  every visible run.
- **The Vulkan Frame rate row's offer** at a game rate of 119.4 is unchecked. `game_rate()` reads 119.52 there;
  interpolation needs the governor above the game's rate plus 0.5, so Display at 120 adds nothing.
- **Erik's eye:** the repeated refresh every 1.7 s, and the sound in a race at Display.
- **D-022** may want a line on the margin (docs/decisions.md was outside "May touch").
- **The watcher is a hand-built diagnostic.** Making the check run it itself, or refuse while the window is covered
  mid-run, would be a follow-up.

## Review
Merged 173991c into batch/m2 as 04362b8 (2026-10-15). Verify rerun on the merge from the main checkout
(out/091_gate.log): the route PASS (race 119.41 flips a race-clock second, margin 0.005), `--audio` PASS on Metal
(1 resync, 0 seconds under 95%, 2 under 99%) and on Vulkan (the same; presents 119.7), the probe's pass path at
120.0 unpaced presents a second on both, the headless suite 18/18, framerate_check, menu_check and docs_check PASS;
game/ms0 unchanged. Spot-read: src/profile/enhancements.cpp (`display_margin()` read once, the period and the lines
from the same `display_period`, the applied state keyed on it), tools/display_rate_check.sh (fresh stick and
PURE_GAME_DIR for the audio run, the window guard), tools/winwatch.m (reads the window list only). The pass bound
(at most 1 resync, no second under 95%; the seconds under 99% reported) was the review's call during the sweep: the
goal is the sound, and the 96 to 98% seconds are slips the sink's lead absorbs. The diagnosis's clean lanes were
off screen (the worker's finding), so the sweep's table replaces them. D-022 amended (2026-10-15). Open: the sink's
tolerance of a late producer (task 081's fork, the next candidate), Vulkan's swapchain, the rig's 100 Hz run
(docs/windows.md), Erik's eye on the repeated refresh.
