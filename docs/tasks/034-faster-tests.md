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
6. Silent runs: every scripted run the tools start is silent by default (`PURE_NO_AUDIO=1` unless the environment
   sets `PURE_NO_AUDIO` or `PURE_AUDIO_WAV`, which task 013's audio checks use: confirm the WAV capture still
   works, since it wraps the sceAudio calls in our HLE rather than the device; if `NO_AUDIO` disables those
   calls, use `audio.mute=1` in the scratch data directory's settings.ini instead). `run_boot.py --sound` and the
   sweep's `--sound` turn the sound on for watching a cell. Erik muted the shared settings by hand on 2026-10-06
   (`audio.mute=1` in `~/Library/Application Support/pure-recomp/PureNative/settings.ini`) to silence the running
   worker's windows: once the tools no longer read that file (item 4), set that line back to `audio.mute=0` so
   the app plays sound again, and say so in Result.
7. One game at a time: task 032 found that a second PureNative running beside a windowed cell (a headless
   recording) delayed the cell's boot and broke its menu route (NO RACE). The sweep and the suite refuse to start
   while another PureNative process runs (`pgrep -f build/.*/bin/PureNative`), with a message naming it, unless
   `--allow-parallel` is given; a headless run is not affected by timing and may skip the check when it is told
   so (say which runs do).
8. `tools/hud_check.sh` keeps its windowed default (it tests the window); `tools/verify_task.sh` unchanged.
   docs/verification.md: the new defaults, the wall times before and after, which path to run for which change.

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (new default) passes 5/5 within 0.001 of its column and takes under 2 minutes.
- [ ] `tools/campaign_sweep.py single_race vineta_k --no-damage` PASSes on the new default, reads the shield bar in
      its `ref` shot, and takes under 5 minutes (report the time; the race itself is about 3.5 minutes paced).
- [ ] `tools/frame_regress.sh --shell metal --backend metal` and `--shell vulkan --backend vulkan` still pass 5/5
      at their columns; `tools/hud_check.sh` 61 of 61.
- [ ] No tool reads or writes the player's data directory (`ls -l` its mtimes before and after a suite and a sweep
      cell: unchanged), and no scripted run makes a sound unless `--sound` is given.

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
Status: DONE. All eight deliverables are in. The Verify line passes (`tools/verify_task.sh 034`, exit 0, 212 s with
the build).
- The suite runs headless on Metal by default in 9 to 10 s, down from 7m 9s.
- The Vineta K sweep cell runs headless, with only the race paced, in 197 to 199 s, down from 402 s.
- The tools no longer touch the player's data directory, and they run silent unless `--sound` is given.
- I set `audio.mute=1` in `~/Library/Application Support/pure-recomp/PureNative/settings.ini` back to
  `audio.mute=0`, so the app plays sound again. I did this after the last run, and nothing else in that file changed.

Base: the worktree started on `main` (b5cb152). That base has neither task 032 nor this brief's item 7. Before
committing anything, I moved `task/034-faster-tests` onto `batch/m2` (8364dc0). Where the "before" numbers come from:
- The suite's: measured on b5cb152. Its script, `run_boot.py` and its routes are the same on both bases.
- The sweep's: measured on 8364dc0.

Changed:
- `src/profile/pure_profile.cpp`: `PURE_PACED_FROM=N`.
  - The kernel runs unpaced from start-up until flip N, then paced from flip N on, in any shell. It calls
    `kernel().set_paced(...)` at registration and again on every flip in `wrap_flip_counter`, so the shell's own
    `set_paced(has_window)` cannot undo it.
  - `0` paces from the start. Unset or empty leaves the choice to the shell, as before.
  - It prints `[pure] PURE_PACED_FROM=N: ...` at start-up and `[pure] paced from frame N t=...` when pacing starts.
- `tools/run_boot.py`:
  - Silent by default. It sets `PURE_NO_AUDIO=1` unless `--sound` is given or the environment (or `--env`) sets
    `PURE_NO_AUDIO`. It also leaves the sound on when `PURE_AUDIO_WAV` is set for a run with a window. Headless runs
    stay silent with `PURE_AUDIO_WAV`, as they were.
  - `--data-dir DIR` (default `out/data/run_boot`) sets `PURE_DATA_DIR` unless one is already named. The directory is
    made on first use with a `settings.ini` holding `ui.menu_hint_seen=1`, and kept between runs.
  - New helpers: `scratch_data_dir`, `silence`, and `other_games` (the PureNative processes now running, by
    `pgrep -f build/.*/bin/PureNative`, kept only when the process itself is PureNative).
- `tools/frame_regress.sh`:
  - Default is now `--shell headless --backend metal`. The Metal column serves both shells; a comment says why.
  - Data directory `out/data/frame_regress`, named in the summary.
  - `--allow-parallel`. Without it, the suite exits 2 and names the process when another PureNative is running.
  - Header comments updated.
- `tools/campaign_sweep.py`:
  - Default is now headless on the Metal backend, with `PURE_PACED_FROM` set to the mode's Cross-hold flip (the
    `throttle` step, in every mode).
  - `--shell headless|metal|vulkan` and `--backend NAME`. `PURE_SHELL`, `PURE_GE_BACKEND` and `PURE_PACED_FROM` from
    the environment are kept.
  - `--sound` turns the sound on and paces the whole run (`PURE_PACED_FROM=0`).
  - Data directory `out/data/campaign_sweep`, also for `--record-line`.
  - `--allow-parallel` guard.
  - The start line now names the shell, backend, paced-from flip and data directory. Docstring updated.
- `tools/hud_check.sh`: data directory `out/data/hud_check`, silent. It keeps its window default.
- `tools/save_roundtrip.sh`: data directory `out/data/save_roundtrip`, silent.
- `README.md`:
  - `PURE_PACED_FROM` row, with the window caveat.
  - run_boot's `--sound` and `--data-dir`, and the `--window` and headless rows.
  - The suite, HUD check, save round trip and sweep rows.
- `docs/verification.md`:
  - The suite section: new default, the shared Metal column, data directory, guard.
  - The HUD check's data directory.
  - A new section, "Fast, silent test runs": per-tool defaults, `PURE_PACED_FROM`, sound, data directory, one game
    at a time, the before and after wall times, the NEW-profile leg, and "Which path for which change".
- `config/pad_scripts/`: unchanged. Item 5 says a LOAD route is not worth it.
- Commits: ca91ee0, 5d22cd7, 08efc85, 26b8c6c, 4428c89, a6ac4b8, and the Result commit.

Acceptance:
1. New suite default:
   - Three runs took 9, 9 and 10 s, all 5/5.
   - Fractions: lang 0.0002, title 0.0002, profile 0.0000, main_menu 0.0106 (all exactly at the Metal column),
     race_hud 0.0374, 0.0374 and 0.0371 (-0.0005, -0.0005, -0.0008).
   - Each headless capture matches the Metal window's capture of the same scene pixel for pixel (`imgdiff --tol 0`,
     after the window's capture is reduced to 480x272). So no `headless` column is needed, and the escalation
     (more than 0.01 apart) does not apply.
   - The Verify run: 0m 10s, 5/5.
2. Sweep cell `single_race vineta_k --no-damage` on the new default:
   - PASS in 197 s (laps 61.2, 61.9 and 60.3 s; 39 contacts). The `ref` shot reads the shield bar as 100%.
   - The Verify run: PASS in 199 s (laps 61.6, 58.8 and 64.0 s).
   - Before, in the Metal window on 8364dc0: 402 s (laps 64.0, 61.0 and 63.2 s; 50 contacts).
   - The race was held to real time headless: 188.6 s of race clock in 197 s of wall time, and the log shows
     `[pure] paced from frame 6100`.
   - The follower's timing holds as in a window:
     - the headless shell reads the live file every 10 flips;
     - the race clock started at flip 6253 and the `ref` shot came at flip 6860, the same flips as in the window
       run;
     - the shots after the finish came every 30 flips, as in the window run;
     - the results panel's TOTAL label was found steady 300 flips after the first finish shot (570 in the window
       run; the panel sits over a moving replay).
   - Further headless cells, all PASS:
     - `time_trial vineta_k --no-damage` (30 flips a second): 228 s, against 404 s for a windowed run of the day in
       the main checkout's summary. The `ref` bar read 100%.
     - `zone zone_1`: 75 s, against 247 s. SHIP DESTROYED was read in two shots and TOTAL ZONES CLEAR as 6, as before.
   - Offline check of the shot readers. I took the main checkout's window shots, cut them to 480x272, and ran
     `title_match`, `read_digits`, `shield_fraction` and the TOTAL label test on them. They give the same answers as
     on the full-size shots. That covers the Metal-window Zone shots and, with task 032's edge-tolerant title match,
     the older Vulkan ones. No region scaling needed fixing.
3. Window paths, each 5/5:
   - `--shell metal --backend metal`: 7m 9s. race_hud 0.0380 (+0.0001); the other scenes at the column.
   - `--shell vulkan --backend vulkan`: 7m 10s. Fractions 0.0544, 0.0302, 0.0543, 0.0331 and 0.0684 (+0.0014; the AI
     grid spread is 0.063 to 0.086).
   - `tools/hud_check.sh` (Metal window): 61 of 61, 229 s. With `--shell headless`: 61 of 61, 13 s.
   - `tools/save_roundtrip.sh`: PASS, all three runs, 426 s.
4. Player's data directory and sound:
   - I listed the directory's mtimes before and after every run: the 3 headless suites, the sweep cell, both window
     suites, both HUD checks, the Zone and Time Trial cells, the save round trip and the Verify run. Every pair was
     unchanged. The whole listing at 16:09 also matched the 15:16 baseline (sorted).
   - Every run log says `Audio: disabled by PURE_NO_AUDIO`, the window runs' too: all 27 game logs of these runs
     (`out/034`, `out/014`, `out/sweep`, `out/regress`).
   - `run_boot.py --sound` opens the device: `Audio: 44100 Hz stereo playback open`.
   - The WAV capture works without the device. A headless `main_menu.txt` run with `PURE_NO_AUDIO=1` and
     `PURE_AUDIO_WAV` wrote all three channels, with the music from t=145.48 s (as in task 013).
     `wavstats.py --from 146` gives active 12/12 and no clipping.
5. One game at a time: with a sweep cell running, both `tools/frame_regress.sh` and `tools/campaign_sweep.py` refused
   to start (exit 2) and named its pid and command.

Wall times, before and after:

| Run | Before | After |
|---|---|---|
| suite, default | 7m 9s (Metal window; routes 72, 159 and 197 s) | 9 to 10 s (headless; routes 2, 2 and 4 s) |
| suite, `--shell metal --backend metal` | 7m 9s | 7m 9s |
| suite, `--shell vulkan --backend vulkan` | 7m 10s to 7m 16s (tasks 028, 031) | 7m 10s |
| sweep cell, Vineta K, `--no-damage` | 402 s | 197 s; 199 s in the Verify run |

NEW-profile leg (item 5), timed with `main_menu.txt` headless and unpaced on Metal, three runs. In the shots, the
profile screen is up at flip 2000 to 2100, and MAIN MENU is drawn from about flip 4380.
- From boot to MAIN MENU (flip 4380): 1.8 to 2.05 s.
- From the profile screen (flip 2100) to MAIN MENU, covering name, tag and the save question: 0.65 s each time.
  Paced, the same 2280 flips take about 76 s.
- That is far under 5 s, so I did not add a cached profile or a LOAD route, and the routes are unchanged.

Item 7, which runs skip the check:
- None of the tools pass `--allow-parallel` on their own. The suite and the sweep check once, when they start.
- The headless suite does not depend on timing (unpaced, frame-indexed), so it is the one run that can safely take
  `--allow-parallel`.
- A sweep cell should not, since its race is paced and steered closed loop. Nor should the window paths.
- `run_boot.py`, `hud_check.sh` and `save_roundtrip.sh` do not check (the brief names only the suite and the sweep).

Verify output (last 20 lines; `tools/verify_task.sh 034`, exit 0):
```
[sweep] single_race-vineta_k: shot f17255: TOTAL label variance 1171, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17285: TOTAL label variance 1541, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17315: TOTAL label variance 29, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17345: TOTAL label variance 2187, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17375: TOTAL label variance 184, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17405: TOTAL label variance 3398, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17435: TOTAL label variance 4486, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17465: TOTAL label variance 4312, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17495: TOTAL label variance 2579, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17525: TOTAL label variance 3702, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17555: TOTAL label variance 4286, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17585: TOTAL label variance 4105, steady True (1 in a row)
[sweep] single_race-vineta_k: PASS (no damage) at flip 17600, 3 laps, race time 190.6 s, 199 s: results screen at flip 17590 (3 laps: 61.6, 58.8, 64.0 s; 190.5 s at the shot); 44 contacts (14, 15, 15 a lap); 101 shield taken and refilled (no damage)
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | vineta_k | PASS (no damage) | 17600 | 3 | 190.6 | 199 | 2026-10-06 16:14 | results screen at flip 17590 (3 laps: 61.6, 58.8, 64.0 s; 190.5 s at the shot); 44 contacts (14, 15, 15 a lap); 101 shield taken and refilled (no damage) |
1
verify 034: PASS
```
Above them in `out/034/verify.txt`:
- `frame regression: PASS, 5/5 scenes pass, shell headless, backend metal (0m 10s)`, with race_hud 0.0374 (-0.0005)
  and the other four scenes at the column.
- `[sweep] single_race-vineta_k: shot ref: shield bar 100%`.

Open questions:
1. `tools/pad_record.py`'s recording command (`run_boot.py --window ...`) is now silent, and it now runs on
   `out/data/run_boot` with default key bindings. For Erik recording a lap, it wants `--sound`, and his bindings need
   `--data-dir` (or `PURE_DATA_DIR`) pointing at a copy of his settings. The script is outside "May touch".
2. `tools/gerec/*.sh` record through run_boot, so those runs are covered. Their `PureNative --replay` calls run the
   game directly with no `PURE_DATA_DIR`. With the Vulkan backend, a replay may still use the player's pipeline cache
   (task 022 raised this). `tools/gerec/` is under "Must not touch".
3. `tools/bundle.sh --check` sets its own `PURE_DATA_DIR`. Its route runs, including the `open` of the app, are not
   silenced. That file is outside "May touch".
4. When a window run sets `PURE_AUDIO_WAV`, the sound stays on, as the brief asks. The capture works without the
   device, so this exception could go if every scripted run should be silent.
5. My additions to the brief:
   - The sweep's `--sound` also paces the whole run, since sound with unpaced menus would be garbled.
   - New scratch data directories start with `ui.menu_hint_seen=1`, so the menu hint does not cover a window's first
     12 s. The player's file had the same setting.
6. In docs/status.md, the follow-up row "The app and the developer build share one data directory" can now be closed.
   status.md is outside "May touch".

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
