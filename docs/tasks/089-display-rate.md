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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
