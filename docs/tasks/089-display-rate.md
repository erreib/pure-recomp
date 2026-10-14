# 089: The display rate (E8: the game's vblank at the display's refresh)

Milestone: E8 | Branch: task/089-display-rate | Status: OPEN

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

**Status: BLOCKED.** The brief's escalation condition came up in `tools/display_rate_check.sh --race`. The route
check passes, and nothing moves at the PSP's rate. The swept Time Trial at 120 is not the same race as at 60:

1. **The first speed pad fires early at 120.** The boost starts about 0.1 s and 4.6 m earlier along the track. The
   ship holds the same lateral line (z -96.8). Both runs of each lane gave the same figures to the digit:

   | Rate | Boost starts (race clock) | Distance |
   |---|---|---|
   | 60 | 2.152 to 2.168 s | 1266.83 m |
   | 90 (one probe cell, `PURE_DISPLAY_HZ=90`) | 2.144 to 2.155 s | 1266.32 m |
   | 120 | 2.057 to 2.066 s | 1262.20 m |

   The standing start matches up to 1.5 s. In the 2.0 s bin it does not:

   | Bin | 0.5 s | 1.0 s | 1.5 s | 2.0 s |
   |---|---|---|---|---|
   | 60 | 39.3 | 77.5 | 121.1 | 168.2 km/h |
   | 120 | 38.9 | 77.0 | 120.8 | 189.0 km/h |

   The 2.0 bin is 12% over, outside the brief's 5% or 10 km/h.

   The early boost does not fit a fixed frame-count delay: such a delay would put 90 at about 2.10 s. I did not find
   the mechanism or a one-field write that would undo it.
2. **The mean lap is beyond 1%.** Two runs of each lane:

   | Run | 60 | 120 | Change |
   |---|---|---|---|
   | 1 | 60.50, 61.30, 64.10 (mean 61.97 s), 40 contacts | 60.50, 57.40, 58.20 (mean 58.70 s), 41 contacts | -5.27% |
   | 2 | 65.90, 61.20, 58.00 (mean 61.70 s), 48 contacts | 58.80, 56.90, 55.40 (mean 57.03 s), 44 contacts | -7.56% |

   Contacts a lap are within the 50% bound (13.3 and 13.7, then 16.0 and 14.7). The two causes are mixed together:
   - The follower reads its steering every 10 flips (vendor `headless_shell.cpp`, outside May touch), so it reads
     twice as often at 120. E4 saw the same effect at 30 against 60.
   - The lane at 60 alone moves a lap by 9% between runs (lap 1: 60.5 s, then 65.9 s).

   So a 1% bound on this follower's mean lap is tighter than its own repeatability. The review decides.

Everything else holds:
- Flips at 120: 120.02 and 120.01 a race-clock second, against 59.95 and 59.96 at 60.
- The game clock (`DAT_08a8c3dc`) runs 0.9962 s a virtual second at 120 against 1.0001 at 60, inside 0.99 to 1.01.
  My guess, not checked: a float sum at about 1000 s cannot hold an 8.3 ms step exactly.
- The `[pure] display rate` lines are as expected in both lanes.

Since the run is blocked, these docs are not written: docs/timing.md "E8", docs/controls.md, docs/status.md,
docs/verification.md, docs/windows.md and README.md. They wait for the review's decision. The patch's own rows are
written: patches/README.md and docs/upstream.md.

### Changed
- **patches/0030-vblank-period.patch** (vendor, exported; `tools/patches.sh check`: 30). It touches
  host/kernel/kernel.{hpp,cpp}, host/hle/hle_media.cpp and host/gpu/frame_pacing.{hpp,cpp}.
  - The kernel: `Kernel::vblank_period_us()` and `set_vblank_period_us()`, default `kVBlankPeriodUs`; 0 restores
    the PSP's period.
    - `last_vblank_us_` is kept at the tick, so a change leaves `last_vblank_us()` exact.
    - A change applies from the next vblank. `next_vblank_us_` is never moved, and the vblank count stands.
  - The media HLE:
    - `frame_start_us`'s step comes from the period, and its grid restarts when the step changes.
    - `vblank_duration_us()`, the hcount and the vblank flag read the period (the two `16683` literals are gone).
    - At each flip it passes the period to `gpu::pacing::set_vblank_period_us()`, under `PORTABLEKIT_HAS_RENDERER`.
      The kernel cannot do this itself: frame_pacing.cpp is a renderer source, and the interpolation tests link it
      alone.
  - frame_pacing:
    - `game_frame_us()` is the period times the game's frame in vblanks.
    - `game_rate()` is 60 × 16683 / period / that count, exactly 60 at the default.
    - A `PresentClock` takes a changed frame and restarts its grid at its next flip.
  - `kGameFrameUs` is kept, because the vendor's interpolation tests use it.
  - vulkan_renderer.cpp and menu.cpp are not touched. The renderer asks for a new rate at each flip from
    `game_rate()`, and the menu row filters by it.
- **src/profile/enhancements.{cpp,hpp}**: the row `display_rate` ("Display rate", Original / Display, default
  Display, Video tab, after Texture detail), with the help text of D-022 point 3.
  - `display_rate()` runs at install and in the `sceGeDrawSync` wrap before E4 and E6.
  - With Display, it reads `PURE_DISPLAY_HZ` or the window shell's `display_refresh()` (through `ui::Layer`). Above
    60.5 Hz it sets the period to `round(1e6 / rate)`, with the rate clamped to 240; otherwise it keeps the PSP's.
  - It prints `[pure] display rate: 120 Hz (8333 us a vblank)` or `[pure] display rate: off` once at start and at
    each change.
  - `PURE_DISPLAY_RATE` comes from patch 0019. `PURE_DISPLAY_HZ` is the test switch. Its README row is not written
    (above).
- **src/profile/pure_profile.cpp**: a comment only.
- **src/host/metal_shell.mm**: `present_time` uses `pk::kernel().vblank_period_us()` in place of
  `kPspFrameSeconds`, which is removed. The picture is still due one vblank after its frame's vblank. At the default
  that moves the due time by 0.33 µs (16683 against 16683.3).
- **tools/display_rate_check.sh** (new), route and `--race`, as briefed.
  - The route runs the same flips in both lanes. Each lane has its own end and HUD shot (7000/6900 and 8000/7900).
  - The frontend is measured in flips a virtual second (it has no race clock). The race is measured in flips a
    race-clock second over clock 1 to 6 s.
  - The fade is the longest run of flips over 1.5 vblank periods, between flip 5600 and the race clock's start.
- **tools/purelib/port.py**: `ENHANCEMENTS_OFF` gains `PURE_DISPLAY_RATE`; `SCRATCH_SETTINGS` gains
  `game.display_rate=0`.
- **tools/gerec/metal_check.sh**: `PURE_DISPLAY_RATE=0` on its replay line.
- **tools/menu_check.sh**: the Video rows end "..., Texture detail, Display rate".
- **patches/README.md**: the row and the section for 0030.
- **docs/upstream.md**: the 0030 section.

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
menu_check: run_boot exit 0, 25 s, log out/menu_check/metal/run.log
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
The Verify line's first command: `display_rate_check: PASS (frontend 29.84/58.28 and race 59.96/120.02 flips a
second, PSP/120; fade 1.90 and 1.90 s (-0.1%), 57 and 114 flips (x2.00); the HUD drawn at both)`.

### Figures of the checks the brief names
**`tools/display_rate_check.sh`: PASS.**

| Lane | Frontend median | Frontend flips a virtual second | Race median | Race flips a race-clock second | Fade |
|---|---|---|---|---|---|
| PSP | 33.37 ms | 29.84 | 16.68 ms | 59.96 | flips 5708-5764, 57 flips, 1.902 s |
| 120 | 16.67 ms | 58.28 | 8.33 ms | 120.02 | flips 5709-5822, 114 flips, 1.900 s |

- The race clock starts at flip 6175 at the PSP's rate and 6447 at 120.
- The `[pure] display rate` lines are as expected, the 120 one before flip 0.
- The HUD is drawn in both lanes.

**`tools/display_rate_check.sh --race`: FAIL**, twice (figures above).

**The fade's countdown: no hook written.** At 120 the race-start fade lasts the same game time without one:
1.900 s in 114 flips, against 1.902 s in 57. Its two-vblank stretch doubles in flips, so the countdown does not
halve the fade. FxScreen re-arms it on every frame of a fade that dt times.

**The frontend and the save dialog, measured.** I took shots at the same flips and at the same virtual times in both
lanes (out/e8probe/). Nothing is hooked, because no one-field write fixes these:
- **These follow time (they match at the same virtual time):**
  - the boot cards (SCEA, Studio Liverpool);
  - the language screen's build-in;
  - the flashing after the save confirm (roughly);
  - the menus' typed help line.
- **These count frames (identical at the same flip number):** the screens' build-in and build-out transitions.
  - Example: MAIN MENU's build-in after the profile save, flips 4315 to 4341. That is 27 flips: 0.90 s at the PSP's
    vblank and 0.45 s at 120.
  - So with Display on a 120 Hz display, the frontend's transitions run at twice the speed.
- **The frame counter is not the cause.** `DAT_08a8c3d8` has two references in the corpus, the frame timer's load
  and store, and is not passed on as the update's a1.
- **The route still works.** The pad script's presses land on the same screens at both rates.
- **240 Hz probe:** the menu route did not reach the race. The flip-indexed presses come at a quarter of the time,
  and the time-based intro is not over by then. The fault is in the route, not a player's game.

**Other checks at the PSP's rate:**

| Check | Result | Figures |
|---|---|---|
| `tools/frame_regress.sh` | PASS | 18/18 |
| `tools/frame_regress.sh --shell vulkan --backend vulkan` | PASS | 7/7 |
| `tools/framerate_check.sh` | PASS | 29.97/59.94, medians 33.37/16.68 ms, as in task 072 |
| `tools/flash_check.sh` | PASS | fade 57 flips 1.90 s off, 0 on; race clock at 6253/6309, as in task 070 |
| `tools/menu_check.sh` | PASS | both shells |
| `tools/patches.sh check` | ok | 30 |
| `python3 tools/docs_check.py` | PASS | |

**`tools/gerec/metal_check.sh`: FAIL, and it fails the same way before my change.**
- Team frames 5650-5651: diff 0.051654 (6744 px).
- Race_1x frame 6016: the first difference at draw 305 of 852 (0.022235).
- I reverted my sources and the patch, rebuilt, and replayed the same fresh recordings with batch/m2's code. The
  figures were identical to the digit: team 0.051654, race draw 305 0.022235.
- So the A/B fails on batch/m2 as well. status.md lists "fresh recordings for metal_check" as owed.

**`PURE_DISPLAY_RATE=1 tools/stutter_check.sh` (the Metal window, this Mac's 120 Hz display): FAIL**, on the cell
only.
- Frames: 0 of 107 seconds have a frame over 25 ms, and readback is 0.00 ms a frame.
- The cell timed out. Its flip budget is set for 60 flips a second, and the race used it up at flip 12913.
  `stutter_check.sh` has no `--frames` and is outside May touch.
- The `[perf]` lines: `fps 120.0 game 120.0 speed 100% | frame avg 8.3 max 9.6 ms | guest 1.4 render 3.7 wait 3.3
  ms`; the worst max in the race was 12.3 ms.
- The Metal shell's `[shell]` line, `metal: Apple M4 Pro, window 960x544 points, 1920x1088 pixels, 2x, vsync`, is
  printed at start and says nothing of the rate.
- `frame_rate_now` counts the presents of the last second: 120 at Display, which is the `[perf]` fps.

**`tools/framerate_check.sh --shell metal` at Original: PASS** (29.97/59.94, medians 33.37/16.68 ms).

**The Vulkan Frame rate row at 120.**
- The window run on this Mac's 120 Hz display printed `[pure] display rate: 120 Hz (8333 us a vblank)`, read from
  the shell's `display_refresh()`.
- At the title the `[perf]` line read fps 60.4, game 61.0.
- The row offers only "120" (the game's own) and "Match display 120 Hz". 45, 60, 90 and 120 are not offered. The
  help reads "Frames between the game's 120 a second".
- I checked this by cycling the row (out/e8probe/vkmenu/rates.png).

**By eye: not done.** I cannot watch the window. What I have in its place are the window's figures above and the
probe's shots.

### Open questions
- **The escalation.** Is the speed pad's early boost at 120 acceptable, given its distance (1262.2 m against
  1266.8 m) and its time (0.1 s)? Does the mean-lap bound need a follower that reads its steering by time rather
  than every 10 flips? With today's follower the bound is below its run-to-run spread. And the frontend's
  frame-counted transitions run at twice the speed. Should the period follow the display only while the race backend
  lives? That is not a one-field write, and D-022 point 3 says the frontend at 60 comes with the option.
- **Left as they are:**
  - `kIdleVBlankLimit` still counts vblanks, so the deadlock report comes after 2.5 minutes at 120 instead of 5.
    It is scheduler code, which this task may not touch.
  - `sceDisplayGetFramePerSec` still answers 59.94. Wipeout Pure does not import it.
- **Outside May touch:**
  - `tools/run_boot.py`'s docstring lists the pinned enhancements without `PURE_DISPLAY_RATE`.
  - `stutter_check.sh` needs its budget doubled to pass at 120.
- **The game clock at 120** reads 0.9962 s a second. It is inside the bound; it might be worth a word in E8's notes.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
