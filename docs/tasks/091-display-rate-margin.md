# 091: The display rate's margin (E8: no audio skips at the display's rate)

Milestone: E8 | Branch: task/091-display-rate-margin | Status: OPEN

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

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
