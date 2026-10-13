# 084: The 3D view at the window's shape (E2, the game-side hook and the check)

Milestone: E2 | Branch: task/084-ultrawide-view | Status: OPEN

## Goal
Under the framework's Fill aspect the game draws its 3D view at the window's shape instead of a stretched 480:272:
on a 21:9 window a race shows more track to each side at the same height. The framework's Vulkan renderer already
spreads the game's screen over the window and tells the profile the picture's aspect once a frame
(`GameProfile::view_aspect_frame`); this task gives Wipeout Pure that hook, and a check that proves the view widened.
The 2D interface still stretches after this task (task 085 fits it) and the Metal shell still has no Fill (task 086).
D-020 holds the audit and the design; read it first.

## Read first
- docs/decisions.md, D-020 (the whole section: addresses, registers, the mechanism)
- vendor/portablekit/host/profile.hpp, the `view_aspect_frame` member and its comment; host/camera/camera_driver.hpp
  (`view_aspect_frame` is called at each flip with the renderer's `game_aspect()`)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `wanted_target_extent`, `interface_fit`, `game_aspect`,
  `supports_fill`, `usable_aspect`, the window creation (`SDL_CreateWindow`, `player.window_scale`); the
  `Fill` comments around lines 2062, 5535, 6623 and 7060
- vendor/portablekit/include/psprecomp/runtime.hpp: `register_function`, `lookup_function`,
  `RecompiledFunction`; vendor/portablekit/src/runtime.cpp `Runtime::register_function` (lines 430 to 480: a
  registration whose name is not `recomp_unit_*` disables chaining for its unit, so cross-unit callers reach it
  through the function table) and `invoke_chained_unit`
- vendor/portablekit/include/psprecomp/allegrex_context.hpp (`fpr`, `pc`, `gpr`)
- src/profile/pure_profile.cpp (the `GameProfile` literal; `register_pure_hle`) and src/profile/enhancements.cpp
  (how E4 and E6 wrap imports and read guest memory through `rt.memory()`; the style of a profile hook here)
- src/profile/test_hooks.cpp (a second example of profile code that writes guest memory)
- tools/texture_check.sh and tools/purelib/port.py (`scratch_data_dir`, `SCRATCH_SETTINGS`, `ENHANCEMENTS_OFF`): a
  two-lane windowed check with its own data directory and settings; tools/run_boot.py (`--shell vulkan --backend
  vulkan`, `--shots`, `PURE_PACED_FROM`); tools/frame_regress.sh (how it runs the race_hud route in a window and
  which frame it captures: `main_menu.txt` + `single_race.txt`, frame 6016, paced from 5716)
- tools/imgdiff.py and tools/png.py (`--region`, `--min-variance`, resize, `--json`)
- docs/verification.md "Which path for which change" and the tools table; docs/upstream.md and patches/README.md
  (what a new patch's rows and section look like); CLAUDE.md
- The audit's decompiles are in the main checkout, not in the worktree: /Users/erreib/dev/pure-recomp/out/aspect/
  (decomp1.txt the Camera constructor, decomp3.txt the camera apply FUN_0883ff34 with the call at 088402b8,
  decomp4.txt FUN_08a31148 and the FOV writers, decomp5.txt the frontend callers, callers4.txt the FOV readers
  and writers). Read, do not copy game bytes anywhere.

## Deliverable
1. `src/profile/aspect.cpp` and `aspect.hpp` (names are yours): the hook `view_aspect_frame(psprecomp::Runtime &,
   float aspect)`, set on the `GameProfile` literal in pure_profile.cpp.
   - On its first call: `original = rt.lookup_function(0x08a31148)`; if null, print one `[aspect]` line saying so
     and do nothing ever after; else `rt.register_function(0x08a31148, &perspective, "pure::perspective")`.
   - `perspective(Runtime &rt, AllegrexContext &ctx)`: the game's FUN_08a31148(fovy, aspect, near, far, y scale,
     frame) takes the aspect in `f13` (ctx.fpr[13]; the race camera loads it from f30 = 1.7647059f, the frontend
     views pass 0x3fe1e1e2, FUN_08869290 passes 1.0). When |f13 - 480/272| < 1e-4 and the frame's view aspect is
     not 480/272, set f13 to the view aspect. Then run `original(rt, ctx)` (ctx.pc is the function's entry; the
     generated unit dispatches on it). Count the calls (a `PURE_TRACE_ASPECT=1` line a second, or at exit, with
     the calls and the aspect in force).
   - At each flip, with `aspect` differing from 480/272 by more than 1e-4: write the float at 0x08b1fb14 as the
     float at 0x08b1fb18 times `aspect` (the game's horizontal half-FOV tangent, which every camera writer sets as
     the vertical one times 480/272). Remember that you changed it. When `aspect` is back at 480/272 and you had
     changed it, write 0x08b1fb18 times 480/272 once and forget. At exactly 480/272 with nothing changed, write
     nothing (the Original path must leave guest memory untouched: the headless suite proves it).
   - The view aspect the override reads is the last one the flip hook received (a plain static). 480/272 means
     "leave the argument alone".
2. The window's size for a check: the Vulkan renderer creates its window at 480 x 272 times `video.window_scale`.
   Add a test-only `<prefix>_WINDOW_SIZE=WxH` read at that creation (vendor, host/gpu/vulkan_renderer.cpp, a few
   lines next to `SDL_CreateWindow`): when set and well formed, the window opens at W x H instead; otherwise as
   before. Export it as `tools/patches.sh export 0027-window-size-switch`; a row and a section in
   patches/README.md, a row in docs/upstream.md (tooling; a candidate), the env row in README.md.
3. `tools/aspect_check.sh [--out DIR]`: the race_hud route in the Vulkan window (`--shell vulkan --backend vulkan`,
   `PURE_WINDOW_SIZE=1260x540`, paced from 5716 as the suite does, the shipped enhancements off as every tool run
   has them, its own scratch data directory) twice: lane `original` with `video.aspect=original` and lane `fill`
   with `video.aspect=fill` written into the lane's settings.ini (the key's values are the names `original`,
   `stretch`, `fill`; see vendor/portablekit/host/settings/settings.cpp `kAspects`). Capture the window at frame
   6016 in each lane (`shot`). Then:
   - (a) The Fill capture's central strip, of width 1260 x (480/272)/(1260/540) = 953 pixels about the centre, scaled
     to 480x272, against the Original capture scaled to 480x272: within a limit you measure and set with a margin
     (expect the 3D within about 0.10 at tol 32: the view is the same, resampled; the HUD differs since it is
     stretched in the Fill lane and not in the other, which this task accepts; print the fraction). If the HUD's
     share pushes it past what the 3D alone would give, compare the region below the HUD's top bars and above its
     bottom ones instead, and say so in the Result.
   - (b) The Fill capture's outer strips (the 153 pixels on each side outside the central strip) hold the scene:
     `--min-variance` well above black, and each strip differs from the adjacent 153 pixels of the central strip
     (not a stretched edge). Print the figures.
   - (c) The `[render] frame 6016 (D draws)` draw count of each lane, printed side by side (culling that follows the
     aspect draws more under Fill). A figure, not a bound, unless your runs show it stable enough to bound.
   - (d) The `[aspect]` trace: the override ran in the race (calls > 0) in the Fill lane and the start-up has no
     `[aspect]` "not found" line.
   Prints `aspect_check: PASS` or `FAIL` last, exit 0 only on PASS; summary and captures under
   `out/aspect_check/`. About 2.5 minutes (two paced race routes in a window). Waits for another PureNative like
   the other window checks (`tools/purelib/port.py`'s helper if there is one; else as stutter_check does).
4. Docs: docs/status.md gets an E2 bullet under the enhancements (what shipped here, what 085 and 086 still owe, the
   figures); docs/verification.md a row for the check and the "Which path" line for a change to the hook;
   README.md the tool row and the env rows (`PURE_WINDOW_SIZE`, `PURE_TRACE_ASPECT`); docs/controls.md's note on
   the Aspect ratio row if it names what Fill does for this game (one sentence).

## Acceptance criteria
- [ ] `tools/aspect_check.sh` PASS on this Mac: (a) within its limit, (b) the strips hold the scene, (d) the
      override ran; (c) printed for both lanes.
- [ ] `tools/frame_regress.sh` (headless, Metal) 18/18 unchanged: the Original path writes nothing to guest memory
      and registers nothing that changes a picture.
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 7/7 (the window scenes at the PSP's shape: the
      override runs with f13 left alone).
- [ ] `tools/patches.sh check` reports 27; `python3 tools/docs_check.py` PASS.
- [ ] No game bytes, no decompile text, no address table beyond the handful of addresses the code and D-020 name.

## Verify
`tools/aspect_check.sh && tools/frame_regress.sh && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- src/profile/aspect.cpp, src/profile/aspect.hpp (new), src/profile/pure_profile.cpp (the literal and an include),
  src/profile/CMakeLists.txt or wherever profile sources are listed
- vendor/portablekit/host/gpu/vulkan_renderer.cpp only for the window-size switch, exported as
  patches/0027-window-size-switch.patch (commit patches/, never vendor/)
- tools/aspect_check.sh (new), tools/purelib/port.py (a small helper only if two tools need it)
- patches/README.md, docs/upstream.md, docs/status.md, docs/verification.md, docs/controls.md, README.md,
  docs/tasks/084-ultrawide-view.md

## Must not touch
- vendor/ beyond the one switch above; vendor/portablekit/include/psprecomp/; src/gpu/ (the 2D fit is task 085);
  the Metal shell (task 086); config/ (no addresses there for this); generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
50

## Escalate when
- `lookup_function(0x08a31148)` returns null, or the override's call count stays 0 through a race (the calls are
  reaching the generated body some other way): stop, report what `register_function` did to the unit.
- The Fill lane's 3D view does not widen (the central-strip compare fails while the HUD alone cannot explain it),
  or the game crashes or hangs after the registration: stop with the trace.
- The check needs more from the vendor than the window-size switch.
- Anything would touch include/psprecomp/, the kernel, or codegen.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
