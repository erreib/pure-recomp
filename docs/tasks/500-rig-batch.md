# 500: The rig's batch for the cleanup and the audio sink (tasks 095, 097, 098)

Milestone: Cleanup (the audit of 2026-10-19) and E8 | Branch: main at 76350b5 or later, pulled on the rig | Status:
OPEN (the rig's planning session or Erik by hand; docs/windows.md "Bringing the rig up to date")

## Goal
The rig's vendor tree is brought to the 30-patch series and the Windows build is checked for what tasks 093 to
095 changed, then the audio sink of task 098 is measured where its problem lives: the race at the Display rate on
the rig's 100 Hz display, where the run of 2026-10-15 FAILed on 3 to 4 early-race resyncs. The Mac's batch (task
097) passed every row and found the sink a no-op there (nothing runs late at 119.4 Hz); this is its proof or its
refutation.

## Read first
- docs/windows.md, "Bringing the rig up to date" (the steps and the cautions: one game at a time, the window in
  front and uncovered, warm the pipeline cache first, a coarse bound that FAILs alone gets a second run).
- docs/tasks/097-screen-batch.md, "On the rig" and Result findings 3 and 4 (what the Mac saw on the trace line).
- docs/tasks/098-audio-sink-late-writes.md (the rule, the switch `PURE_AUDIO_SNAP=1`, the trace fields).
- docs/timing.md, "On the rig's 100 Hz display" (the 2026-10-15 figures to compare with).

## Preconditions
- Git Bash in the checkout, `git pull` done, no PureNative, PPSSPP or build running.
- The game window in front and uncovered for every step from 4 on; the display at 100 Hz.
- About 60 minutes: the vendor resync's corpus rebuild comes from ccache (minutes), the suite about 5, the stutter
  check 6, the two probes 2.5 each plus their boots, the race with the synchronous read-back 4.

## The steps, in order
1. `tools/patches.sh check || tools/vendor_setup.sh`, then `tools/patches.sh check` must say 30. vendor_setup
   rewrites include/psprecomp/allegrex_context.hpp with the same bytes, so the corpus recompiles from ccache.
2. `tools/build.sh profile`. CMakeLists.txt gained src/tools/record_backend.cpp; the reconfigure is automatic. If the
   worktree build loses the renderer, set `SDL3_ROOT` (docs/windows.md; status Follow-ups, E8 on the rig).
3. One warm-up run: `tools/run_boot.py --seconds 30 --window --shell vulkan out/500/warm.log` (a cold pipeline cache
   stalls the race start and would spoil step 5).
4. `tools/frame_regress.sh --shell vulkan --backend vulkan 2>&1 | tee out/500/04-suite.log` (18 scenes in the window
   here). Guards 095's `host_read_memory` and `gpu::write_bmp` captures and 093's src moves on Windows.
5. `tools/stutter_check.sh 2>&1 | tee out/500/05-stutter.log` (0022's frame-late read-back path; 094's window guard
   must not fire). The bound is coarse: a FAIL alone gets a second run.
6. `tools/menu_check.sh --shell vulkan 2>&1 | tee out/500/06-menu.log` (Menu::Tab as MenuTab, the rows by capability).
7. `PURE_SYNC_READBACK=1 python3 tools/campaign_sweep.py single_race vineta_k --no-damage --out out/500/07-sync --shell vulkan --backend vulkan`
   (the cell stutter_check runs, with the environment passed through as the checks pass `PURE_TRACE_AUDIO`): the
   start-up line must say `synchronous`, the cell must PASS to its results screen, and nothing halts. Guards 095's
   `drain_recording`. Its wall time is not a gate (the synchronous path is the slower one by design).
8. The sound at 100 Hz, both sink rules, new first:
   `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan 2>&1 | tee out/500/08-audio-new.log`, then
   `PURE_TRACE_AUDIO=1 PURE_AUDIO_SNAP=1 tools/display_rate_check.sh --audio --shell vulkan 2>&1 | tee out/500/08-audio-snap.log`.
   Copy each run's `out/display_rate_check/audio-vulkan/run.log` aside before the next run (the second overwrites it).
   Compare over the race (from the `[pure] paced from` line): `resyncs=` and `resynced=`, `lates=` and `late=`, the
   seconds at `ratio=0.990`, `silent=`, and the check's verdict. On 2026-10-15 the old rule gave 3 to 4 resyncs at
   the race load and 4 and 9 s into the race, speed held.
9. Erik's ear: one race at Display with the new rule, one with `PURE_AUDIO_SNAP=1`, same circuit. Fewer or no clicks
   at the race start with the new rule is the result this task is for; a 1% pitch sag for a few seconds after a dip
   is the rule working, a sag that never ends is a bug.

## Verify
`tools/patches.sh check && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/stutter_check.sh && tools/menu_check.sh --shell vulkan && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan`

## Report (the Result section of this file, committed on the rig; Erik pushes)
- Each step's verdict line, and for step 8 a small table: rule, resyncs (and where), lates, late frames, seconds at
  ratio 0.990, the check's verdict. Note `dropped=`'s order of magnitude in both (task 097, finding 4).
- Step 9 in a sentence.
- Anything that halted, any coarse-bound FAIL and its second run.

## Escalate when
Step 1 cannot reach 30 patches (stop: the series or the pin differs from the Mac's); the suite FAILs a scene that
passed on 2026-10-15 (a Windows-only regression from 093 to 095: a task of its own, not a fix here); step 8's new
rule shows `lates=` growing every second with `ratio=0.990` never ending (the recovery does not converge at 100 Hz:
report the figures, do not retune the constants here).

## Result (the rig, 2026-10-19, batch/m2 at e9654b2; branch task/500-rig-batch)
Status: DONE for steps 1 to 8 (every row but the sound probe PASS; the probe FAILs under both rules on its resync
count, the figures below); step 9 not run (it needs Erik's ear; this session has none). Logs under out/500/
(`01-vendor_setup.log`, `02-build.log`, `warm.log`, `04-suite.log`, `05-stutter.log`, `06-menu.log`, `07-sync/`,
`08-audio-new.log` and `08-audio-new-run.log`, `08-audio-snap.log` and `08-audio-snap-run.log`, `verify.log` and
`08-audio-new-run2.log` for the Verify chain's second new-rule probe). No step ran with the window covered; the
guard said "the window on screen: yes" in every probe.

| # | Step | Verdict |
|---|---|---|
| 1 | patches check, vendor_setup, check | first check FAILed (`differs: vendor/portablekit/cmake/PortableKit.cmake`); vendor_setup exit 0, then `ok: 30 patch(es) reproduce vendor/portablekit at 8b0c3fe` |
| 2 | build.sh profile | linked bin/PureNative.exe in 47 s (236 steps, the reconfigure automatic, one -Wdeprecated-volatile warning in vulkan_renderer.cpp); the renderer present (`Renderer: Vulkan on NVIDIA GeForce RTX 3080, target 960x544`), SDL3_ROOT not needed |
| 3 | warm-up, 30 s in the window | ran to its deadline (exit 124 by design), the Vulkan renderer |
| 4 | frame_regress --shell vulkan --backend vulkan | PASS, 18/18 scenes (8m 56s), twice (the Verify chain repeated it: 18/18, 8m 56s); no scene FAILed |
| 5 | stutter_check | PASS, 0 of 195 seconds over 25 ms, readback 0.00 ms; the guard did not fire (presents judged [114.5, 108.0, 101.8]); the Verify rerun PASS too, 1 of 189 seconds (worst 27.6 ms) |
| 6 | menu_check --shell vulkan | PASS (tabs 4, Video 21, Audio 4, Controls 37, System 15) |
| 7 | PURE_SYNC_READBACK=1 campaign_sweep single_race vineta_k | the start-up line says `synchronous, PURE_SYNC_READBACK set`; PASS (no damage) at flip 17830, 3 laps (62.4, 65.9, 60.0 s), results screen at flip 17820, 213 s wall; nothing halted |
| 8 | display_rate_check --audio --shell vulkan, new rule then PURE_AUDIO_SNAP=1 | FAIL under both: 2 resyncs (new) and 3 (snap) against at most 1; speed held in all three runs (medians 99.5 presents and 99.5 game flips a second, race second 5 at 96 to 98%, none under 95%); the table below |
| 9 | Erik's ear | not run |

Step 8, over the race (from the `[pure] paced from frame 5900` line; audio second 188 is the race load):

| Rule | Resyncs (audio second, `resynced=`) | `lates=` | `late=` frames | `silent=` in the race | Seconds at `ratio=0.990` | Verdict |
|---|---|---|---|---|---|---|
| new, run 1 | 2: 188s (4455, the load's), 196s (388473) | 94 (30, 54, 10 at 192 to 194s) | 19961 (13919, 6042, 0) | 19961 at 192 to 193s (0.45 s), after the load's 2407 | 192 to 198s (7 s) | FAIL, 2 resyncs |
| old (`PURE_AUDIO_SNAP=1`) | 3: 188s (4455), 192s (2064), 196s (390455) | 0 | 0 | 16 at 192s, after the load's 2407 | none | FAIL, 3 resyncs |
| new, run 2 (the Verify chain) | 2: 188s (4455), 196s (388785) | 10 (all at 188s) | 0 | 0 after the load's 2407 | 188 to 192s (5 s) | FAIL, 2 resyncs |

The lead (`lead=`) at the race start: run 1 2273, 1949, 1625, 0 at 189 to 192s, then 1103, 1115, 1895, 5054 (the
196s restart), 6625 at 199s and 5500 to 7700 for the rest of the race; the old rule 1931, 1607, 2051, 2255 (after
its 2064-frame jump), 2699, 3143, 2819, 5887; run 2 777 at 188s, 1556, 1568, 2348, 1592, 2632, 2308, 2752, 5446.
After audio second 199 every run reads `lates=0 late=0 ratio=1.000` to the end: the recovery converges, no escalation.

`dropped=`: 30.5 k to 31.3 k frames a second in the menus under both rules (`lead=` 7424 to 7751, the Mac's order of
magnitude, task 097 finding 4), and 0 through the race (a stray 12 to 51 in the seconds the lead touched 7564 to 7599).

Readings:
1. **The 4 s resync of 2026-10-15 is a dip the new rule handles, in two shapes.** In run 1 the lead drained to 0
   over the race's first 4 seconds (about 700 frames a second) and the producer then wrote behind the device for
   about 1.5 s: each late write dropped the frames the device had passed (`late=`), the device played silence for
   exactly those frames (`silent=` 19961 = `late=` 19961, the ring past `write_end`), in 84 pieces (464 frames a
   write at 192s, 112 at 193s) until the 1% slowdown closed the deficit at about 441 frames a second. The old rule
   took the same dip as one 2064-frame jump (47 ms of content skipped, 16 silent frames). By the counters run 1's
   new rule cost ten times the silence of the old rule's jump, spread over 2 s. In run 2 the ten late writes at the
   race load (task 098's open question 1: writes under the 512-frame arming threshold but not behind the device,
   `late=0`) armed the 0.990 ratio from 188s, the lead never reached 0 and the race played with no silence past the
   load's: the brief's expected outcome. So on the rig that arming is the part of the rule that works, not a harmless
   side-effect; dropping the threshold to "strictly behind" would leave run 1's shape only. Which shape a run gets
   depends on the lead left after the race load (2273 against 777 at 189s) and the drain's pace, both unsteered.
   Not retuned here, per the brief; the figures say the recovery rate (441 frames a second) is slower than the
   rig's early-race drain, so a producer already at a deficit keeps underrunning until it closes.
2. **The 196s resync (about 388 k to 390 k frames, 8.8 s) is a channel restart, not a dip**, in every rig run
   including 2026-10-15's "9 s into the race": a cursor far beyond `kLateLimit`, snapped under both rules, with the
   lead jumping about 3000 frames. The probe's `MAX_RESYNCS=1` (the race load's) counts it, so on the rig the audio
   probe cannot PASS even in run 2, where the dips cost nothing. The probe wants to tell a restart from a jump
   (`resynced=` far over 2048) or allow it; task 097 finding 3 saw 20 such restarts on the Mac outside the probe's
   window.
3. Nothing halted, no coarse bound FAILed (both stutter runs PASS), no scene regressed against 2026-10-15's
   suite, and the Windows build of 093 to 095 is clean (the captures, the src moves, `drain_recording` under the
   synchronous read-back).

Verify output (the chain's last 20 lines, out/500/verify.log; its exit is 1 on the probe's resync count):
```
race: PASS, paced from flip 6100; 189 seconds, 11427 frames
the window on screen: yes (unpaced presents a second judged: [111.4, 107.2, 99.4], the display 100 Hz)
(a) seconds with a frame over 25 ms: 1 of 189 (0.5%); apart, the live-file flips (a multiple of 10) over it: 644, worst 34.5 ms
(b) readback: 0.00 ms a frame
worst second: #79 after the paced flip, frame avg 16.7 max 27.6 ms, flip 10813 25.0 ms
stutter_check: PASS (1 of 189 seconds over 25 ms, readback 0.00 ms a frame)
menu_check: shell vulkan, out out/menu_check/vulkan
menu_check: run_boot exit 0, 30 s, log out/menu_check/vulkan/run.log
tabs: ok (4)
Video: ok (21)
Audio: ok (4)
Controls: ok (37)
System: ok (15)
menu_check: PASS
display_rate_check: audio, shell vulkan, backend vulkan, the display's own refresh, margin the default, out /h/errei/Documents/dev-stuff/pure-recomp/out/display_rate_check/audio-vulkan
display_rate_check: probe: [pure] display rate: 100 Hz display, the game at 99.49 Hz in a race (margin 0.005), the PSP's 59.94 Hz outside one; the unpaced boot presents 100.0 a second; the run ends at flip 13362
display_rate_check: run_boot exit 0, 137 s, log /h/errei/Documents/dev-stuff/pure-recomp/out/display_rate_check/audio-vulkan/run.log
vulkan: 100 Hz display, margin 0.005, the game at 99.49 Hz (10051 us a vblank); the window on screen: yes (unpaced presents a second: the menus' median 100.0, the race load's [67.6, 100.1]); race seconds 77 (74 after the first 3); resyncs 2 (audio seconds: 188s, 196s); seconds under 99% speed 1 (race second 5 98%), under 95% 0; medians 99.5 presents and 99.5 game flips a second; flip 13362 reached: yes; 137 s
display_rate_check: FAIL (audio, vulkan, margin 0.005, 10051 us a vblank: 2 resyncs, 0 seconds under 95% and 1 under 99% (reported), medians 99.5 presents and 99.5 game flips a second; 2 resyncs (at most 1))
verify exit: 1
```

Changed: docs/tasks/500-rig-batch.md (this section). No code, no vendor, no patches.

Open questions:
- Step 9, Erik's ear: one race at Display under each rule on the same circuit. Run 1's shape would sound like a
  2 s buzz of small gaps at the race's 4th second; run 2's like nothing. The old rule's like one click.
- Whether the 512-frame arming threshold should stay (it is what made run 2 clean) and whether 1% for 4.6 s is the
  pair for the rig, where the early-race drain outpaces the recovery (task 098's open question 2).
- The probe's resync rule against the 196s channel restart (reading 2): allow it or classify by size, else
  `--audio --shell vulkan` never PASSes on the rig.

## Follow-up: the probe tells a channel restart from a skip (the rig, 2026-10-19, branch task/500-probe-restarts)
Reading 2 above, made directly (docs/approach.md rule 1: two tools files, two doc lines). `purelib.logs` reads
`resynced=` beside `resyncs=` (`AUDIO_RE`) and `audio_restart(line)` says whether a line's jumps average over
`RESTART_FRAMES` (44100, one second of audio): a cursor that sat idle and restarted at the write target, not a skip
in a playing channel (the race load's jump is about 4500 frames, a dip's about 2100, a restart's 388 k to 394 k).
`tools/display_rate_check.sh --audio` counts those apart as `channel restarts N (audio seconds: ...)` and leaves them
out of `MAX_RESYNCS`; the header, docs/verification.md's row and docs/timing.md's measurement paragraph say so.
`python3 tools/purelib/logs.py --selftest` PASS (a skip, a restart, no resync, a line without `resynced=`);
`python3 tools/docs_check.py` PASS.

Replayed over the three logs above with the new reader: new rule run 1 and run 2 read 1 resync (the load's) and 1
restart, so both would PASS on the count; the old rule reads 2 (the load's and the 192s jump) and 1 restart, FAIL.

Two live runs after the change, out/500/10-audio-new-restarts*.log and 11-audio-new-restarts2*.log, both with the
window on screen and both under other load (Chrome and VS Code at about 39% of the CPU between them, measured
between the runs; the three runs above were not checked for this):
- Run 4: FAIL on 3 seconds under 95% speed (race seconds 5, 10 and 19 at 89, 70 and 93%) and 5 resyncs
  (189s; 198s x2 after a `lead=0`; 207s x2 at a 247 ms frame), 1 restart (197s, 394459, printed apart). The new
  rule's late branch under that load: `lates=` 40, 59, 58, 57 at 193 to 196s with `late=` 87343 frames in all,
  the lead at 0 to 212 through them (run 1's shape, four seconds long). Not a figure for the rule: a disturbed run.
- Run 5 (the second run): FAIL on 3 resyncs: the load's (188s, 4667), then 2 at 206s (`resynced=` 13851 for the
  pair, `silent=` 3874) under a 247 ms host frame at race second 19 (`[perf]` max 247.3 ms, speed 98%); 1 restart
  (196s, 389266) apart; no second under 95%. The early race was run 2's shape: `lates=2 late=1536` at the load
  armed the ratio to 192s, the lead 2595 to 4167, no silence after the load's 4155.

So the classification holds in every run (the restart at race second 8 to 9 is one line each time, the rest are
jumps a playing channel made), and the probe on the rig now FAILs only on what the ear would hear: a dip the lead
did not cover. A stall of a quarter second is beyond any sink rule's reach (the deficit passes `kLateLimit` and
snaps under both); its cause today is the machine's other load, to be ruled out before the next measurement by
closing Chrome and the editor, which the brief's preconditions did not name.

Changed: tools/purelib/logs.py, tools/display_rate_check.sh, docs/verification.md, docs/timing.md, this file.
