# 097: The screen batch for the audit's cleanup (tasks 092 to 095)

Milestone: Cleanup (the audit of 2026-10-19) | Branch: batch/m2 (the planning session runs it; no worker) |
Status: PLANNED, waits for Erik to book the screen

## Goal
Run, in one sitting with Erik's screen booked (docs/approach.md, rule 4), every window check tasks 093, 094 and 095
listed as owed, then the gerec recordings afresh. Nothing is merged on it: the four tasks are in batch/m2 already
(the headless gates passed at each merge). A FAIL here is a finding against batch/m2 and gets its own task.

## Preconditions (Erik)
- The game window in front and uncovered for the whole batch; nothing else full-screen; the display at 120 Hz.
- No other PureNative, no PPSSPP, no build running (the stutter and display-rate checks measure wall time; the gerec
  recordings are paced races). `tools/lib.sh`'s guard waits for a stray game but not for a build.
- About 80 minutes. The order below puts the cheap gates first and the 25 minutes of recording last, so the batch
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
| 7 | `tools/display_rate_check.sh --audio` and `--audio --shell vulkan` | 094, 095 | 5 min | E8's sound at the margin; the vblank period now read from the kernel |
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
`mkdir -p out/097 && tools/frame_regress.sh --shell metal 2>&1 | tee out/097/01-metal.log && tools/frame_regress.sh --shell vulkan --backend vulkan 2>&1 | tee out/097/02-vulkan.log && tools/hud_check.sh 2>&1 | tee out/097/03-hud-metal.log && tools/hud_check.sh --shell vulkan 2>&1 | tee out/097/03-hud-vulkan.log && tools/menu_check.sh 2>&1 | tee out/097/04-menu-metal.log && tools/menu_check.sh --shell vulkan 2>&1 | tee out/097/04-menu-vulkan.log && tools/aspect_check.sh 2>&1 | tee out/097/05-aspect-vulkan.log && tools/aspect_check.sh --shell metal 2>&1 | tee out/097/05-aspect-metal.log && tools/overlay_check.sh 2>&1 | tee out/097/06-overlay.log && tools/display_rate_check.sh --audio 2>&1 | tee out/097/07-audio-metal.log && tools/display_rate_check.sh --audio --shell vulkan 2>&1 | tee out/097/07-audio-vulkan.log && tools/stutter_check.sh 2>&1 | tee out/097/08-stutter-metal.log && tools/stutter_check.sh --shell vulkan 2>&1 | tee out/097/08-stutter-vulkan.log && tools/texture_check.sh --shell vulkan 2>&1 | tee out/097/09-texture-vulkan.log && tools/sprite_pack.sh --check 2>&1 | tee out/097/10-sprite-pack.log && tools/save_roundtrip.sh 2>&1 | tee out/097/11-save-roundtrip.log && tools/run_boot.py --seconds 20 --window --shell vulkan out/097/12-vulkan-alone.log && tools/gerec/replay_check.sh 2>&1 | tee out/097/13-replay.log && tools/gerec/metal_check.sh 2>&1 | tee out/097/14-metal-check.log`

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

## Escalation
A FAIL in rows 1 to 3 stops the batch: it is a regression in batch/m2 against a merged gate and takes a task of
its own before the rest is worth running. A FAIL in rows 7 or 8 is first checked against the guard ("the window
was not on screen"): a covered window measures nothing (rule 4), so rerun the row once with the window in front
before calling it a finding.
