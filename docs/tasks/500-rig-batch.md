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

## Result
(the rig fills)
