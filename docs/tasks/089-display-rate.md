# 089: The display rate (E8: the game's vblank at the display's refresh)

Milestone: E8 | Branch: task/089-display-rate | Status: MERGED

## Goal
A "Display rate" row in the Esc menu runs the game's own vblank at the display's refresh rate, so on a 120 Hz
display Single Race, Tournament and the modes E4 freed draw 120 frames a second and the two-vblank screens (the
frontend, the 30 fps modes at Original) 60. The game's speed does not change: its step is measured time
(docs/timing.md, "The game's clock in a race"). A check proves it at 59.94 and 120 per second of the game's own
clock, and finds the per-frame counters that do change with the vblank (the race-start fade's countdown is one).
D-022 holds the audit and the design; read it first.

## Read first
- docs/decisions.md D-022, D-017 (E4: the lock byte and the hook pattern), D-016 (E6: the fade's countdown)
- docs/timing.md ("The game's clock in a race", "E4", "E6"): what counts frames and what integrates dt
- vendor/portablekit/host/kernel/kernel.hpp (`kVBlankPeriodUs` at line 86, `last_vblank_us`, `next_vblank_us_`,
  `vblank_count`) and kernel.cpp (`process_timers`, line 538; `on_vblank`; the hold to real time: `pacing_started_`
  and what it compares emulated to real time with)
- vendor/portablekit/host/hle/hle_media.cpp: `frame_start_us` (line 282, `kStep`), `kVBlankDurationUs` (663),
  `sceDisplayGetCurrentHcount` and `sceDisplayIsVblank` (716 to 728, the `16683` literals), `sceDisplayGetVcount`
  and the vblank waits
- vendor/portablekit/host/gpu/frame_pacing.hpp and .cpp (`kGameFrameUs`, `game_frame_us`, `game_rate`, the rates
  the Frame rate row offers; the Vulkan renderer's governor reads them)
- src/host/metal_shell.mm (`kPspFrameSeconds` at line 87, `present_time` about line 709: a picture is due at its
  vblank's real time plus one PSP frame; `display_hz_`, `display_refresh`)
- src/profile/enhancements.cpp (the `kOptions` table, `sixty_fps` and `smooth_flashes`: how an option is read at
  start and applied at a flip through the sceGeDrawSync wrap; `kFlashCountdown`), src/profile/enhancements.hpp,
  src/profile/pure_profile.cpp (where the options are registered)
- tools/framerate_check.sh (the two-lane route and race variants, the race-clock-second arithmetic, the fade's
  flips: the model for this task's check), tools/flash_check.sh (the fade detector), tools/purelib/port.py
  (`ENHANCEMENTS_OFF`, `SCRATCH_SETTINGS`, `original_pacing`), tools/menu_check.sh (the Video rows), tools/stutter_check.sh
- docs/verification.md "Which path for which change" (an enhancement's gate), docs/controls.md ("the game's own
  rows"), patches/README.md and docs/upstream.md (rows and sections); CLAUDE.md

## Deliverable
1. Vendor patch `0030-vblank-period`: the kernel's period a runtime value, `Kernel::vblank_period_us()` and
   `set_vblank_period_us(std::uint64_t)` (default `kVBlankPeriodUs`; a change applies from the next vblank, and
   `next_vblank_us_` is not moved into the past), used by `process_timers`, `last_vblank_us`, hle_media.cpp's
   `kStep` (no longer `static const`), `kVBlankDurationUs`, the hcount and vblank-flag arithmetic, and
   frame_pacing's `game_frame_us`/`game_rate` (the `kGameFrameUs` constant becomes a function of the period, or
   the pacer reads the kernel). Nothing else moves at the default period: the headless suite and the Vulkan window
   suite prove it.
2. The option: `display_rate` in `kOptions` ("Display rate", choices Original / Display, default Display, tab
   Video, after Texture detail; help text per D-022 point 3, naming what the 30 fps modes row means at the
   display's rate), `PURE_DISPLAY_RATE=0|1` as the other options' switches; `PURE_DISPLAY_HZ=N` (test-only, a
   README row under the test switches) names the rate to use instead of the shell's `display_refresh()`. At start
   and when the option changes: with Display and a rate above 60.5 Hz (the shell's, or the env's), the period is
   `round(1e6 / rate)` clamped to 240 Hz; else the PSP's. A `[pure] display rate: 120 Hz (8333 us a vblank)` line
   when it is not the PSP's, `[pure] display rate: off` otherwise, once at start and at each change.
3. The Metal shell: `present_time` uses the kernel's period instead of `kPspFrameSeconds` (a picture due one
   vblank after its flip's real time at whatever the period is); presents at 120 a second on a 120 Hz display
   with vsync. The Vulkan renderer: the Frame rate row's offered rates follow `game_rate()` (a game at 120 shows
   no interpolation rates below it); say in the Result what the row offers at 120.
4. The per-frame counters: with the vblank at 120 the race-start fade's countdown (`kFlashCountdown`, a frame per
   decrement at two vblanks) would last half as long in game time. In the sceGeDrawSync wrap, when the period is
   not the PSP's and Flashes is Original, scale the countdown so the fade lasts the same game time (the E4 pattern:
   write the field; say exactly what you write and when). Audit the frontend and the save dialog the same way:
   measure (below) and hook only what a one-field write fixes; report the rest.
5. `tools/display_rate_check.sh [--race] [--out DIR]` (headless, Metal backend, the shipped enhancements off but
   `PURE_SIXTY_FPS=1` in both lanes so the race is one vblank): the Time Trial route of framerate_check twice,
   `PURE_DISPLAY_RATE=0` and `PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=120`: PASS when the frontend's flips a
   race-clock second are 30 against 60, the race's 60 against 120 (bounds like framerate_check's), the race-start
   fade lasts the same race-clock time within 10% in both (its two-vblank stretch in flips doubling), the HUD is
   drawn, and the `[pure] display rate` lines are as expected. `--race`: the swept Time Trial at both, the lap time
   within 1% and the standing start within 5% or 10 km/h (framerate_check's bounds), contacts a lap within 50%.
   Print every figure. The route about 20 s, the race about 7 minutes.
6. The window on this Mac (120 Hz): `tools/stutter_check.sh` with `PURE_DISPLAY_RATE=1` (one run, by the task;
   the check's bound is 25 ms a frame, which stands) and `tools/framerate_check.sh --shell metal` unchanged at
   Original. Say what the Metal shell's `[shell]` line reports and what `frame_rate_now` counts at 120.
7. Pins and rows: `ENHANCEMENTS_OFF` gains `PURE_DISPLAY_RATE`, `SCRATCH_SETTINGS` `game.display_rate=0`,
   tools/gerec/metal_check.sh's pin line as the others; tools/menu_check.sh's Video rows end "..., Texture
   detail, Display rate" on both shells.
8. Docs: docs/timing.md an "E8" section (the period, where it is read, the counters found and what was hooked, the
   figures); docs/controls.md the row; docs/status.md the E8 bullet; docs/verification.md the check's row and the
   "Which path" line; README.md's features line ("or at your display's rate") and the Esc menu section's Video
   list; docs/windows.md a rig item (the rig's 100 Hz display: the race at 100, the Frame rate row's offer);
   patches/README.md and docs/upstream.md for 0030.

## Acceptance criteria
- [ ] `tools/display_rate_check.sh` PASS and `--race` PASS, figures in the Result.
- [ ] `tools/frame_regress.sh` 18/18, `tools/frame_regress.sh --shell vulkan --backend vulkan` 7/7,
      `tools/framerate_check.sh` PASS, `tools/flash_check.sh` PASS, `tools/menu_check.sh` PASS on both shells,
      `tools/gerec/metal_check.sh` PASS: nothing moves at the PSP's rate.
- [ ] `tools/stutter_check.sh` with `PURE_DISPLAY_RATE=1` on this Mac: the figures in the Result (PASS expected).
- [ ] `tools/patches.sh check` 30; `python3 tools/docs_check.py` PASS.
- [ ] By eye in the Metal window at Display: a race at 120 (the `[perf]` or `[shell]` line), the menus at 60, the
      race-start fade of the same length, the save dialog and the menus not racing; say what you saw.

## Verify
`tools/display_rate_check.sh && tools/frame_regress.sh && tools/framerate_check.sh && tools/menu_check.sh && tools/patches.sh check && python3 tools/docs_check.py`
(`--race`, the Vulkan suite, flash_check, metal_check and the stutter run are run apart and pasted: they exceed
one command's ten minutes together)

## May touch
- vendor/portablekit/host/kernel/kernel.hpp and kernel.cpp (the period only: no scheduler change),
  host/hle/hle_media.cpp, host/gpu/frame_pacing.hpp and .cpp, host/gpu/vulkan_renderer.cpp only if the governor
  needs the rate, exported as patches/0030-vblank-period.patch (commit patches/, never vendor/)
- src/profile/enhancements.cpp and .hpp, src/profile/pure_profile.cpp, src/host/metal_shell.mm
- tools/display_rate_check.sh (new), tools/purelib/port.py, tools/menu_check.sh, tools/gerec/metal_check.sh
- docs/timing.md, docs/controls.md, docs/status.md, docs/verification.md, docs/windows.md, README.md,
  patches/README.md, docs/upstream.md, docs/tasks/089-display-rate.md

## Must not touch
- vendor/portablekit/include/psprecomp/; the kernel's scheduler, waits and starvation rules (the period alone);
  src/gpu/ (the backend draws whatever it is handed); config/; generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
60

## Escalate when
- The hold to real time or the starvation rules depend on the period in a way a settable period breaks (a route
  at 120 stalls, runs fast or slow by the race clock): stop with the trace.
- A per-frame counter changes the game's behaviour at 120 and no one-field write restores it (the game's physics
  at the finer step moves the lap time beyond 1%, or the AI behaves differently): report the figures; the review
  decides.
- Anything would touch include/psprecomp/, the scheduler or the backend.

## Result

**Status: DONE.** This finishes on the review's changes, after the first run was BLOCKED. The route check, the race
check with its new bounds and the checks at the PSP's rate all pass.

**What the period follows.** The period follows the display only while the race backend lives. The condition is E4's
gate:
- `DAT_08a8c5f4` (0x08A8C5F4, the race backend: stored by `BackendRoot_cpp__0880c068` in the race load, zeroed by its
  destructor) is in user RAM (0x08800000 to 0x0A000000);
- and so is the frame object `*0x08A8E960`.

It is not the lock byte `+0x116c`. That byte is 0 in the 30-fps modes at Original and while the save dialog runs, so
gating on it would leave those races at the PSP's rate.

The check is made in the `sceGeDrawSync` wrap, before E4 and E6. With Display, a rate above 60.5 Hz and a live
backend, the period is the display's. Otherwise it is the PSP's. A change applies from the next vblank.

One `[pure] display rate` line is printed for each change:
- `off` for Original, or no display above 60.5 Hz;
- `120 Hz in a race, the PSP's 59.94 Hz outside one` for Display outside a race (at start, and after a race);
- `120 Hz (8333 us a vblank)` at the race load. On the Time Trial route it comes after flip 5700.

### Changed
- **patches/0030-vblank-period.patch** (vendor; `tools/patches.sh check`: 30). It touches
  host/kernel/kernel.{hpp,cpp}, host/hle/hle_media.cpp and host/gpu/frame_pacing.{hpp,cpp}.
  - The kernel: `Kernel::vblank_period_us()` and `set_vblank_period_us()`, default `kVBlankPeriodUs`.
    - `last_vblank_us()` is kept at the tick.
    - A change applies from the next vblank. `next_vblank_us_` is never moved into the past, and the count stands.
  - The media HLE: `frame_start_us`'s step (its grid restarts on a change), the vblank duration, the hcount and the
    vblank flag read the period, and the period is passed to `gpu::pacing` at each flip.
  - frame_pacing: `game_frame_us()` and `game_rate()` follow the period, exactly 60 at the default. A
    `PresentClock` follows a change at its next flip.
  - vulkan_renderer.cpp and menu.cpp are not touched. The renderer asks for a new rate from `game_rate()` at each
    flip, and the menu row filters by it.
- **src/profile/enhancements.{cpp,hpp}**: the Display rate row and its help text, which now says the menus keep the
  PSP's pace. Also `race_backend()` and `display_rate()`: the period, gated as above, with its line printed at each
  change.
- **src/profile/pure_profile.cpp**: a comment only.
- **src/host/metal_shell.mm**: `present_time` uses the kernel's period, and `kPspFrameSeconds` is removed.
- **tools/display_rate_check.sh** (new).
  - Route: the frontend must read 29 to 31 flips a second in both lanes. The 120 lane must print the line outside a
    race before flip 0, and the race line once, from flip 5700 and before the fade.
  - `--race`: bounded are the cells' PASS, the flips a race-clock second, both game clocks, the start bins up to
    1.5 s (5% or 10 km/h) and the contacts a lap (50%). Printed but not bounded: the 2.0 s bin, the first speed pad
    (its race clock and distance) and the mean lap.
- **tools/stutter_check.sh**: `--frames 26000` (twice the cell's budget) when `PURE_DISPLAY_RATE=1`.
- **tools/purelib/port.py**: `ENHANCEMENTS_OFF` and `SCRATCH_SETTINGS`.
- **tools/run_boot.py**: the docstring's pinned list.
- **tools/gerec/metal_check.sh**: the replay pin.
- **tools/menu_check.sh**: the Video rows end "..., Texture detail, Display rate".
- **Docs:**
  - docs/timing.md "E8": the measurements, the race-only gate and why, and the two open items.
  - docs/controls.md: the row and `game.display_rate`.
  - docs/status.md: the E8 bullet.
  - docs/verification.md: the check's row, the enhancements-off bullet and the "Which path" line.
  - docs/windows.md: the rig's 100 Hz item.
  - README.md: the features line and the Esc menu's Video list.
  - docs/developing.md: the rows for `PURE_DISPLAY_RATE` and `PURE_DISPLAY_HZ` (test-only), and a row for the check.
    The switch tables live there, not in README.md, so this is where the brief's "README row" went.
  - patches/README.md and docs/upstream.md: the 0030 entries.

### Verify output (last 20 lines)
```
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
framerate_check: route, shell headless, backend metal, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a489744a5f7111b1f/out/framerate_check/route-metal-headless
framerate_check: PURE_SIXTY_FPS=0: run_boot exit 0, frame 7000 reached: yes, 7 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a489744a5f7111b1f/out/framerate_check/route-metal-headless/0/run.log
  hud_check: 1 of 1 shots have the HUD
framerate_check: PURE_SIXTY_FPS=1: run_boot exit 0, frame 7000 reached: yes, 6 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a489744a5f7111b1f/out/framerate_check/route-metal-headless/1/run.log
  hud_check: 1 of 1 shots have the HUD
PURE_SIXTY_FPS=0: frontend flips 4000-5000 median 33.37 ms; race flips 6300-6900 median 33.37 ms, 29.97 flips a race-clock second; lines ['[pure] sixty fps: off (after flip 0)']; hud_check: 1 of 1 shots have the HUD; 7 s
PURE_SIXTY_FPS=1: frontend flips 4000-5000 median 33.37 ms; race flips 6300-6900 median 16.68 ms, 59.94 flips a race-clock second; lines ['[pure] sixty fps: on (game.sixty_fps) (after flip 5704)']; hud_check: 1 of 1 shots have the HUD; 6 s
framerate_check: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms and 29.97/59.94 flips a second, off/on; the HUD drawn at 60)
menu_check: shell metal, out out/menu_check/metal
menu_check: run_boot exit 0, 9 s, log out/menu_check/metal/run.log
tabs: ok (4)
Video: ok (15)
Audio: ok (4)
Controls: ok (31)
System: ok (15)
menu_check: PASS
ok: 30 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 35 files, 0 findings: PASS
verify 089: PASS
```
The Verify line's first command: `display_rate_check: PASS (frontend 29.84/29.84 and race 59.96/120.00 flips a
second, PSP/120; fade 1.90 and 1.88 s (-1.0%), 57 and 113 flips (x1.98); the HUD drawn at both)`.

### Figures
**`tools/display_rate_check.sh`: PASS.**

| Lane | Frontend median | Frontend flips a virtual second | Race median | Race flips a race-clock second | Race clock starts | Fade |
|---|---|---|---|---|---|---|
| PSP | 33.37 ms | 29.84 | 16.68 ms | 59.96 | flip 6175 | flips 5708-5764, 57 flips, 1.902 s |
| 120 | 33.37 ms | 29.84 | 8.33 ms | 120.00 | flip 6446 | flips 5710-5822, 113 flips, 1.883 s |

- Lines: the PSP lane printed `off` (flip 0). The 120 lane printed the line outside a race (flip 0), then
  `120 Hz (8333 us a vblank)` after flip 5700.
- The HUD is drawn in both lanes.

**`tools/display_rate_check.sh --race`: PASS.**

| Lane | Cell | Laps | Contacts | Flips a race-clock second | Game clock | Start, km/h at 0.5/1.0/1.5/2.0 s | First speed pad |
|---|---|---|---|---|---|---|---|
| PSP | PASS | 58.40, 63.80, 57.00 (mean 59.73 s) | 43 (14.3 a lap) | 59.95 | 1.0001 | 39.3/77.5/121.1/168.2 | 2.152 s at 1266.83 m |
| 120 | PASS | 58.90, 61.80, 55.40 (mean 58.70 s) | 48 (16.0 a lap) | 119.67 | 0.9962 | 39.2/76.9/120.1/183.9 | 2.067 s at 1262.62 m |

Reported, not bounded:
- The mean lap: -1.73% at 120. In the blocked run's two pairs it was -5.27% and -7.56%.
- The 2.0 s bin: 168.2 against 183.9 km/h.
- The first speed pad: 0.085 s and 4.21 m earlier at 120.

Earlier probes of the pad, for the record (docs/timing.md "E8"):
- With the period everywhere, it fired at 2.057 s and 1262.20 m, the same in both runs.
- At 90 Hz (`PURE_DISPLAY_HZ=90`, one cell) it fired at 2.144 s and 1266.32 m.

**The frontend and the save dialog.** They now keep the PSP's cadence:
- The route's frontend reads 29.84 flips a second in both lanes.
- In the Metal window at Display, the title's `[perf]` line reads `game 30.0`, with the line `120 Hz in a race, the
  PSP's 59.94 Hz outside one`.

The audit that led to the gate (with the period everywhere), in docs/timing.md "E8":
- Time drives the boot cards, the language screen's build-in, the flashing after the profile save, and the typed
  help line.
- Frames drive the screens' build-in and build-out transitions. MAIN MENU's after the profile save is flips 4315 to
  4341: 0.90 s at 59.94 Hz and 0.45 s at 120.

**The fade's countdown needs no hook.** At 120 the fade keeps its time and doubles its flips: 1.883 s in 113 flips,
against 1.902 s in 57.

**`PURE_DISPLAY_RATE=1 tools/stutter_check.sh` (the Metal window, this Mac's 120 Hz display): PASS**, 10 of 195
seconds with a frame over 25 ms, readback 0.00 ms.
- Nine of those ten seconds are the sweep's results-panel shots, taken every 30 flips after the race ends (165 to
  199 ms each).
- One is in the race: flip 15823, 25.9 ms, all render.
- The race's `[perf]` lines: game 120.0, frame avg 8.3 ms. Frame max is 9.5 ms in the median second and 13.2 ms at
  the 90th percentile. Guest 1.4 ms, render 6.9 ms.
- The cell passed at flip 23083 of its doubled budget.
- The Metal shell's `[shell]` line, `metal: Apple M4 Pro, window 960x544 points, 1920x1088 pixels, 2x, vsync`, is
  printed at start and does not change with the rate.
- `frame_rate_now` counts the last second's presents: 120 in the race, 30 in the menus.

**Checks at the PSP's rate**, all run after the gate:

| Check | Result | Figures |
|---|---|---|
| `tools/frame_regress.sh` | PASS | 18/18 |
| `tools/frame_regress.sh --shell vulkan --backend vulkan` | PASS | 7/7 |
| `tools/framerate_check.sh` | PASS | 29.97/59.94, medians 33.37/16.68 ms |
| `tools/flash_check.sh` | PASS | fade 57 flips off, 0 on |
| `tools/menu_check.sh` | PASS | both shells |
| `tools/framerate_check.sh --shell metal` at Original | PASS | 29.97/59.94, medians 33.4/16.7 ms |

**`tools/gerec/metal_check.sh`: FAIL, not this task's.**
- It fails on fresh recordings: team frames 5650-5651 at 0.051654, race frame 6016 at draw 305 (0.022235).
- batch/m2's code gives the same figures to the digit on the same recordings.
- This is status.md's owed recording refresh.

**The Vulkan Frame rate row.**
- In a race at 120 it offers "120" (the game's own) and "Match display 120 Hz" only, with the help "Frames between
  the game's 120 a second". I checked this by cycling the row while the period was at 120.
- Outside a race the period is the PSP's, so the row offers its usual rates.
- On the rig's 100 Hz display the race should get "100" and "Match display 100 Hz" (docs/windows.md item).

**By eye: not done.** I cannot watch the window. In its place I have the window's `[perf]` and `[pure]` lines (the
race at 120, the menus at 30) and the probe's shots. Erik's look is still owed.

### Open questions
- **The first speed pad** fires 0.085 to 0.1 s and 4.2 to 4.6 m early at 120 (not traced). It is reported, not
  bounded, as the review decided.
- **Unmeasured: a save dialog while the race backend lives** runs at the display's period: the Time Trial ghost's
  auto-load (`GhostShip_etc__0891e4cc`). Its two vblanks a frame are then 16.7 ms on a 120 Hz display.
- **Left as they are, noted open in docs/timing.md "E8":** `kIdleVBlankLimit` (2.5 minutes at 120 instead of 5) and
  `sceDisplayGetFramePerSec` (still 59.94).
- **D-022** wants the review's amendment: the period is race-only, and the frontend stays at the PSP's rate.

## Review
Merged 0d5790c into batch/m2 (2026-10-14) after one BLOCKED round, the review's decision being the race-only
period (the Result says which condition), the standing start bounded through 1.5 s with the lap mean and the pad
reported, and the stutter check's budget scaled; D-022 amended in 989bbb9. Verify rerun on the merge from the main
checkout (out/089_gate.log): display_rate_check PASS (frontend 29.84 flips a second in both lanes, the race 59.96
against 120.00, the fade 1.90 against 1.88 s), the headless suite 18/18, framerate_check and menu_check PASS,
patches 30, docs_check PASS; then the Vulkan window suite 7/7, flash_check PASS, `PURE_DISPLAY_RATE=1
tools/stutter_check.sh` PASS (8 of 198 seconds over 25 ms, the results-panel shots as the worker found, readback
0.00) and `--race` PASS (the start 39.2/76.9/120.1 against 39.3/77.5/121.1 km/h, the game clock 0.9962 against
1.0001, mean lap 58.67 against 61.17 s reported, 120.02 flips a race-clock second). Spot-read:
patches/0030-vblank-period.patch (the kernel's setter and tick, the media HLE's grid restart, the pacer's rate),
src/profile/enhancements.cpp (`race_backend`, `display_rate`, the line per change), src/host/metal_shell.mm
(`present_time` on the period), tools/display_rate_check.sh. The worker's audit of what counts frames is the
value of this task beyond the row: docs/timing.md "E8". Open, carried in status: the speed pad's early trigger at
120 (a per-frame test, untraced), a save dialog while the race backend lives (the ghost's auto-load) at the
display's period, `kIdleVBlankLimit` and `sceDisplayGetFramePerSec` untouched, the rig at 100 Hz untried, Erik's
eye on a 120 Hz race. metal_check's failure on fresh recordings is batch/m2's owed recording refresh, not this
task's.
