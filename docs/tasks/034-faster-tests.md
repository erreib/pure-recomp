# 034: Faster tests: unpaced menus, the suite headless on Metal, the sweep paced only during the race

Milestone: M7 (tooling) | Branch: task/034-faster-tests | Status: OPEN (after task 032)

## Goal
Every scripted run is held to real time from its first frame, so the 4,450 flips of movies and menus before the
main menu cost about 150 s per run and a sweep cell about 7 minutes, of which only the race needs real time (the
follower steers in a closed loop). Headless runs are unpaced since patch 0011 and draw real pictures with the Metal
backend since task 028. This task makes the regression suite run headless on Metal by default (about a minute instead
of seven), gives the profile a switch that keeps the clock unpaced until a given flip and paced from there, and runs
the sweep headless with the race paced, so a cell's menus take seconds. It also measures what the NEW-profile leg
costs once the menus are unpaced, and adds a cached-profile LOAD route only if it still matters.

## Read first
- CLAUDE.md, docs/status.md (Follow-ups: the shared data directory row; this task also fixes that for the tools),
  docs/verification.md, docs/ge-backend.md 8.4 and 8.5 (pacing by shell, the headless shell's script support),
  docs/tasks/028-metal-by-default.md (Result: headless Metal shots against the references), docs/tasks/031 (Result:
  the HUD check headless)
- src/profile/pure_profile.cpp (`wrap_flip_counter`: the per-flip hook where `PURE_EXIT_AT_FRAME` and the probes
  live; `kernel()` is reachable there), vendor/portablekit/host/kernel/kernel.hpp (`set_paced`, patch 0011),
  kernel/fast_loading.hpp (what the framework already speeds up and when it keeps real time)
- tools/frame_regress.sh (the SCENES table, `--shell`, the measured columns, the per-route runs), tools/run_boot.py
  (`--shell headless`), tools/campaign_sweep.py (`Port`, the environment of a cell's run, `throttle`, the live file
  read every 10 flips, `fps` of the 30-fps modes), tools/hud_check.sh, tools/save_roundtrip.sh, tools/verify_task.sh
- src/host/metal_shell.mm (`draw`: the drawable wait at vsync; why an unpaced clock does not speed a windowed run)

## Deliverable
1. `PURE_PACED_FROM=<flip>` in the profile: from the first flip the kernel is unpaced (`kernel().set_paced(false)`),
   and at flip N it is paced again (`set_paced(true)`). Any shell; the speed-up is real only without a window (a
   windowed shell still presents at the display's rate). Document it in README.md beside the other switches, with
   that caveat. `PURE_PACED_FROM=0` means paced from the start (no change); unset means the shell decides, as today.
2. The suite headless by default: `tools/frame_regress.sh` runs `--shell headless --backend metal` unless told
   otherwise, with the backend's own 480x272 captures as the scene shots. Measure the five scenes' fractions on that
   path three times; if they stay within 0.001 of the Metal column, the column serves both shells; if not, add a
   `headless` measured column. Keep `--shell metal --backend metal` and `--shell vulkan --backend vulkan` working
   with their columns (they are the gates for shell changes; docs/verification.md says which to run when). Record
   the suite's new wall time.
3. The sweep: `tools/campaign_sweep.py` runs `--shell headless --backend metal` by default, with
   `PURE_PACED_FROM=<the mode's throttle flip>` so the menus are unpaced and the race paced (the 30-fps modes too);
   the shots come from the backend. The follower's timing assumptions (the live file read every 10 flips, the
   `ref` shot's flip, the shot cadence after the finish) must hold as before: check the Vineta K cell PASSes with
   `--no-damage` and reads the shield bar, and record the cell's wall time before and after. If headless shots
   confuse any detection (the results TOTAL label, SHIP DESTROYED, TOURNAMENT STANDING are read from 480x272 pictures
   either way), fix the region scaling rather than the shell. `--shell metal` stays available for watching a cell.
4. The tools on a scratch data directory: `run_boot.py`, `frame_regress.sh`, `campaign_sweep.py`, `hud_check.sh`,
   `save_roundtrip.sh` pass `PURE_DATA_DIR` under out/ (one per tool, kept between runs so pipeline caches persist)
   unless the environment sets it, so playing in the app never changes a test run and a test never touches the
   player's `~/Library/Application Support/pure-recomp/PureNative/`. The sweep's and the suite's `PURE_GAME_DIR`
   handling stays as it is.
5. The NEW-profile leg: with the menus unpaced, time the main-menu route (`main_menu.txt`) headless from boot to
   MAIN MENU, and the part spent from the profile screen to MAIN MENU (the name, tag and save question). Report both.
   If that part still costs more than 5 s per run, add a cached profile: a memory stick made once per out/ (the first
   run's `ms0/` after the save), and a `main_menu_load.txt` route (LOAD, first slot) the suite and the sweep use when
   the cache exists; otherwise say it is not worth it and leave the routes alone.
6. `tools/hud_check.sh` keeps its windowed default (it tests the window); `tools/verify_task.sh` unchanged.
   docs/verification.md: the new defaults, the wall times before and after, which path to run for which change.

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (new default) passes 5/5 within 0.001 of its column and takes under 2 minutes.
- [ ] `tools/campaign_sweep.py single_race vineta_k --no-damage` PASSes on the new default, reads the shield bar in
      its `ref` shot, and takes under 5 minutes (report the time; the race itself is about 3.5 minutes paced).
- [ ] `tools/frame_regress.sh --shell metal --backend metal` and `--shell vulkan --backend vulkan` still pass 5/5
      at their columns; `tools/hud_check.sh` 61 of 61.
- [ ] No tool reads or writes the player's data directory (`ls -l` its mtimes before and after a suite and a sweep
      cell: unchanged).

## Verify
`tools/build.sh profile && tools/frame_regress.sh && python3 tools/campaign_sweep.py single_race vineta_k --no-damage && grep -c PASS out/sweep/summary.txt`

## May touch
- src/profile/pure_profile.cpp (the paced-from switch only), tools/frame_regress.sh, tools/run_boot.py,
  tools/campaign_sweep.py, tools/hud_check.sh, tools/save_roundtrip.sh, config/pad_scripts/ (a LOAD route only if
  item 5 says so), docs/verification.md, README.md

## Must not touch
- vendor/, patches/, src/gpu/, src/host/, src/hle/, src/tools/, tools/gerec/, ref/, CMakeLists.txt

## Estimated turns
50

## Escalate when
A headless shot differs from the windowed one by more than 0.01 on a scene (report which draws: the HUD check's
method), the follower cannot keep the race paced headless (report the probe timings), or a tool needs more than
`PURE_DATA_DIR` to leave the player's directory alone.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
