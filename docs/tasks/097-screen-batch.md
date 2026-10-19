# 097: The screen batch for the audit's cleanup (tasks 092 to 095)

Milestone: Cleanup (the audit of 2026-10-19) | Branch: batch/m2 (the planning session runs it; no worker) |
Status: DONE on the Mac (2026-10-19); the rig's steps are Erik's

## Goal
Run, in one sitting with Erik's screen booked (docs/approach.md, rule 4), every window check tasks 093, 094 and 095
listed as owed, then the gerec recordings afresh. Nothing is merged on it: the four tasks are in batch/m2 already
(the headless gates passed at each merge). A FAIL here is a finding against batch/m2 and gets its own task.

## Preconditions (Erik)
- The game window in front and uncovered for the whole batch; nothing else full-screen; the display at 120 Hz.
- No other PureNative, no PPSSPP, no build running (the stutter and display-rate checks measure wall time; the gerec
  recordings are paced races). `tools/lib.sh`'s guard waits for a stray game but not for a build.
- About 85 minutes. The order below puts the cheap gates first and the 25 minutes of recording last, so the batch
  can stop early if the screen is needed back: whatever is left stays owed.

## Read first
- docs/verification.md, "Which path for which change" (why both window paths and hud_check).
- docs/tasks/094-tools-shared.md, "Window checks for the planning session's screen batch"; 095's "Window checks
  owed"; 093's Result (menu_check, the two paths, the PURE_SHELL=vulkan start).

## The batch, in order
| # | Command | Owed by | About | Guards |
|---|---|---|---|---|
| 1 | `tools/frame_regress.sh --shell metal` | 093, 095 | 5 min | the Metal path's 18 scenes after 093's src moves and 095's helpers |
| 2 | `tools/frame_regress.sh --shell vulkan --backend vulkan` | 093, 095 | 5 min | the Vulkan path (0004's trimmed interfaces, `write_bmp`, `drain_recording`) |
| 3 | `tools/hud_check.sh` and `tools/hud_check.sh --shell vulkan` | 094 | 3 min | the HUD on both shells |
| 4 | `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` | 093, 094, 095 | 1 min | the rows by capability; `Menu::Tab` as `MenuTab` |
| 5 | `tools/aspect_check.sh` and `tools/aspect_check.sh --shell metal` | 094, 095 | 5 min | Fill on both shells; the shared `PURE_WINDOW_SIZE` parse |
| 6 | `tools/overlay_check.sh` | 094 | 30 s | the overlay after `frame_regress --wait` replaced its refusal loop |
| 7 | `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio` and `--audio --shell vulkan`, then `PURE_TRACE_AUDIO=1 PURE_AUDIO_SNAP=1 tools/display_rate_check.sh --audio` | 094, 095, 098 | 8 min | E8's sound at the margin; the vblank period read from the kernel; the sink's late-write rule (098) against the old snap: compare the `[audio]` lines' `resyncs=`, `lates=`, `late=` and `ratio=` over the race, and the check's verdict under both |
| 8 | `tools/stutter_check.sh` and `tools/stutter_check.sh --shell vulkan` | 094, 095 | 12 min | wall time; 094's window guard on a live run (it must not fire) |
| 9 | `tools/texture_check.sh --shell vulkan` | 094 | 2 to 5 min | the Vulkan lane after imgdiff's `reduce_centres` |
| 10 | `tools/sprite_pack.sh --check` | 094 | 1 to 4 min | the pack check's `guarded` loop on `--wait` |
| 11 | `tools/save_roundtrip.sh` | 094 | 3 min | runs 4 and 5, the save list in the window (1 to 3 run headless first) |
| 12 | `tools/run_boot.py --seconds 20 --window --shell vulkan out/097/vulkan_alone.log` | 093 | 1 min | PURE_SHELL=vulkan with no backend named draws with the vulkan backend (read the `[render]` lines) |
| 13 | `tools/gerec/replay_check.sh` | 094 | 14 min | records race, race_warm, frontend and title afresh (`--current` finds the old ones stale), then the replays |
| 14 | `tools/gerec/metal_check.sh` | 094 | 12 min | records team and race_1x afresh, reuses race_warm; Metal against Vulkan |

Each command's output goes under `out/097/` (`tee out/097/NN-name.log`). Verify is the chain below so that
`tools/verify_task.sh 097` runs the whole batch and stops at the first failure; the batch then resumes by hand from
the next row, and the Result records both.

## Verify
`mkdir -p out/097 && tools/frame_regress.sh --shell metal 2>&1 | tee out/097/01-metal.log && tools/frame_regress.sh --shell vulkan --backend vulkan 2>&1 | tee out/097/02-vulkan.log && tools/hud_check.sh 2>&1 | tee out/097/03-hud-metal.log && tools/hud_check.sh --shell vulkan 2>&1 | tee out/097/03-hud-vulkan.log && tools/menu_check.sh 2>&1 | tee out/097/04-menu-metal.log && tools/menu_check.sh --shell vulkan 2>&1 | tee out/097/04-menu-vulkan.log && tools/aspect_check.sh 2>&1 | tee out/097/05-aspect-vulkan.log && tools/aspect_check.sh --shell metal 2>&1 | tee out/097/05-aspect-metal.log && tools/overlay_check.sh 2>&1 | tee out/097/06-overlay.log && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio 2>&1 | tee out/097/07-audio-metal.log && PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan 2>&1 | tee out/097/07-audio-vulkan.log && PURE_TRACE_AUDIO=1 PURE_AUDIO_SNAP=1 tools/display_rate_check.sh --audio 2>&1 | tee out/097/07-audio-metal-snap.log && tools/stutter_check.sh 2>&1 | tee out/097/08-stutter-metal.log && tools/stutter_check.sh --shell vulkan 2>&1 | tee out/097/08-stutter-vulkan.log && tools/texture_check.sh --shell vulkan 2>&1 | tee out/097/09-texture-vulkan.log && tools/sprite_pack.sh --check 2>&1 | tee out/097/10-sprite-pack.log && tools/save_roundtrip.sh 2>&1 | tee out/097/11-save-roundtrip.log && { tools/run_boot.py --seconds 20 --window --shell vulkan out/097/12-vulkan-alone.log; [ $? -eq 124 ]; } && tools/gerec/replay_check.sh 2>&1 | tee out/097/13-replay.log && tools/gerec/metal_check.sh 2>&1 | tee out/097/14-metal-check.log`

(`set -o pipefail` is not in verify_task.sh's shell, so read each tool's own PASS or FAIL line in its log rather than
the chain's exit alone.)

## After the batch, on the idle machine (no screen needed)
The scorecard rerun from docs/status.md's Next: `tools/scorecard.py --only timing`, then
`SCORECARD_RACE_CLOCK=ref/race_clock tools/scorecard.py --only trajectories` against 2026-10-07's figures. The
baseline of 2026-10-19 (out/scorecard-audit/) showed 4 two-vblank stretches on Vineta K while two builds ran; a run
with nothing else on the machine says whether they were the builds'. A `--full` run rewrites docs/scorecard.md and
drops its hand-written Windows paragraph: restore it from git before committing.

## On the rig (Erik, by hand; docs/windows.md "Bringing the rig up to date")
1. `tools/patches.sh check || tools/vendor_setup.sh` (the series is 29 patches now; the corpus recompiles from
   ccache), then `tools/build.sh profile`.
2. The window suite (`tools/frame_regress.sh --shell vulkan --backend vulkan`), `tools/stutter_check.sh`,
   `tools/menu_check.sh --shell vulkan`.
3. One race with `--env PURE_SYNC_READBACK=1`: the start-up line must say `synchronous` (095's `drain_recording`).
4. Task 098's sink: `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio --shell vulkan` at the Display rate
   (100 Hz), then the same with `PURE_AUDIO_SNAP=1`; the early-race resyncs of 2026-10-15 (3 to 4) should read as
   `lates=` with `ratio=0.990` seconds and no resync, and the race by ear.

## Escalation
A FAIL in rows 1 to 3 stops the batch: it is a regression in batch/m2 against a merged gate and takes a task of
its own before the rest is worth running. A FAIL in rows 7 or 8 is first checked against the guard ("the window
was not on screen"): a covered window measures nothing (rule 4), so rerun the row once with the window in front
before calling it a finding.

## The scorecard rerun (2026-10-19, before the batch; no screen needed)
Run by the planning session on batch/m2 at 3810eac with no game, build or PPSSPP running (load average about 3 from
other programs), into out/scorecard-rerun/ (docs/scorecard.md untouched):
`tools/scorecard.py --only timing` (12m 12s) and `SCORECARD_RACE_CLOCK=ref/race_clock tools/scorecard.py --only
trajectories` (1m 51s).

Timing: **close** (5 faithful, 1 close, 1 accepted). Flips per race-clock second 59.46 (Single Race), 59.36
(Tournament, the matrix's), 29.98, 29.98, 29.97 (the 30-fps modes), all faithful. The two-vblank stretches over the
follower-driven Vineta K race: 3 (45, 25, 24 flips) against PPSSPP's 0, close; the 2026-10-19 baseline taken beside
two builds had 4 (differs) and the 2026-10-07 run 1 (faithful). So the builds were not the whole of it: the count
swings 1 to 4 from run to run, and the row's own note says where they fall follows the weapons and the follower's
put-backs. No new finding; the Follow-ups line (the stretch row rests on one race a side) now says so. The race load
0.30 s against PPSSPP's 1.50 s, accepted (D-011), as before.

Trajectories: **differs** (12 faithful, 2 close, 11 differ), the known state. Every player row is faithful but
Karbonis (first over 1 m at 12.08 s, 23.84 m at 19.95 s, the nearest AI ship 369 m away), which is the divergence
docs/fidelity.md records since patch 0009-vfpu-rounding (task 048's premise: "Karbonis' player, faithful before the
patch, now parts at 12.08 s"), reproduced to the sample. docs/scorecard.md's trajectory rows predate that patch
(2026-10-07 13:43), which is why they show Karbonis faithful. The AI rows differ as task 046 left them (the codegen's
dot products), with the worst distances moved by the AI's own run-to-run differences (Sinucit 280.70 to 12.07 m,
Citta Nuova 83.86 to 7.48 m, Mandrashee 0.46 to 1.60 m); PPSSPP's two Vineta K runs agree to 0.000 m as before.

Not run: pictures, saves, coverage and audio (`--quick` or `--full`); a `--full` run rewrites docs/scorecard.md and
needs its Windows paragraph restored after.

## Result (the Mac, 2026-10-19, batch/m2 at 727a1a1 then f293c78)
Status: DONE on the Mac, every row PASS; the rig's steps (above) stay Erik's. Logs under out/097/ (the sound probes'
run logs under out/display_rate_check/audio-*/).

| # | Check | Verdict |
|---|---|---|
| 1 | frame_regress --shell metal | PASS, 7/7 window scenes (5m 11s) |
| 2 | frame_regress --shell vulkan --backend vulkan | PASS, 7/7 (5m 11s) |
| 3 | hud_check, both shells | 61 of 61 shots have the HUD, both |
| 4 | menu_check, both shells | PASS, both |
| 5 | aspect_check, both shells | PASS (Fill against Original between the HUD's bars 0.0627 Metal, 0.0691 Vulkan, limit 0.1) |
| 6 | overlay_check | PASS (0.9626 of the rectangle's pixels differ, at least 0.2) |
| 7 | display_rate_check --audio, Metal and Vulkan, and Metal with `PURE_AUDIO_SNAP=1` | PASS, all three, after the fix below: 1 resync (the race load's, allowed), 0 seconds under 95%, medians 119.4 presents and 119.4 game flips a second |
| 8 | stutter_check, both shells | PASS: Metal 8 of 195 seconds over 25 ms, Vulkan 0 of 185; readback 0.00 ms; the window guard did not fire |
| 9 | texture_check --shell vulkan | PASS (race_hud 0.0727 reduced, limit 0.1) |
| 10 | sprite_pack --check | PASS |
| 11 | save_roundtrip (runs 4 and 5 in the window) | PASS |
| 12 | PURE_SHELL=vulkan with no backend named | draws with the Vulkan renderer ("Renderer: Vulkan on Apple M4 Pro", a 960x544 swapchain) |
| 13 | replay_check | PASS (480 s): race, race_warm, frontend and title recorded afresh (`--current` found the October 6 ones stale), the replays as documented (race into vulkan cold differs from draw 1 as the table in docs/ge-backend.md says; race_warm, frontend and title exact) |
| 14 | metal_check | PASS (391 s): team and race_1x recorded afresh; the TEAM frames 0 pixels over tol 24, the race's first difference at draw 40 of 906 as before |

Findings:
1. **The sound probe measured nothing on the Mac since task 094** (fixed, f293c78). `display_rate_check --audio` read
   its probe's verdict through a here document inside a process substitution; /bin/bash 3.2 scans `<(...)` for
   quotes, so the apostrophe task 094 put in a comment there ("the window guard's rule") ended it with "no closing
   `)'", and the script fell through to its route mode and printed that mode's PASS (the first row 7 run here did,
   three times, in 20 s each). The rig's Git Bash is bash 5, so the 2026-10-15 rig figures stand. The here document
   now sits in a command substitution, as aspect_check's does; both shapes were tried under bash 3.2 with a
   stand-in, and the three probes then ran 125 s each with real verdicts.
2. **The chain stopped at row 12 by its own design**: run_boot exits 124 at its deadline, which `&&` read as a
   failure. Rows 13 and 14 and the row 7 rerun were run by hand after it; the Verify line now accepts 124 there.
3. **Task 098's sink on the Mac is a no-op, as expected.** Under both rules the `[audio]` lines over the probe's run
   are the same to the frame: 20 resyncs (channel restarts, `resynced=` 85 k to 843 k frames each, far beyond the
   2048-frame late limit), `lates=0`, `late=0`, `ratio=1.000` every second. At 119.4 Hz the Mac never runs a channel
   late, so the dip regime the patch is for exists only on the rig (its step 4 above). The Metal run's log of the new
   rule was overwritten by the snap run's (both write out/display_rate_check/audio-metal/run.log); the Vulkan run's
   log is the new rule's.
4. **A question for a task, not this one: `dropped=`.** Every windowed run with sound, under both rules and in the
   2026-10-14 logs too (out/e8audio/), reports `dropped=` 33 k to 43 k a second on the `[audio]` line beside
   `lead=7424`. `dropped` counts frames the runaway trim retired unplayed (`retire(..., false)`: a write that would
   end past `read_position + kRingFrames`, 8192). A lead of 7424 sits one 768-frame buffer under the ring's size, so
   the trim may fire on most writes and the device may be hearing a different stretch of the ring than the counter
   suggests, or the counter means less than it says. By ear the Mac is fine, so this is a counter to understand
   before it is believed, and the candidate root of the rig's hiccups if it is real: the next audio task.

Window checks still owed: none on the Mac. The rig: steps 1 to 4 above (Erik).
