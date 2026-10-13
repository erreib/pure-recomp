# 084: The 3D view at the window's shape (E2, the game-side hook and the check)

Milestone: E2 | Branch: task/084-ultrawide-view | Status: MERGED

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

**Status: DONE.** Verify passes (out/verify_084.txt):
- aspect_check: PASS.
- The headless suite: 18/18. Every figure equals the build without the hook.
- `tools/patches.sh check`: 27 patches reproduce the pin.
- docs_check: PASS.

The work departs from the brief in two places, both explained below:
- The hook finds the generated body without `lookup_function`, which is private.
- The override goes in at the first flip under a shape other than the PSP's, not at the first flip.

**Changed:**
- New: src/profile/aspect.cpp, src/profile/aspect.hpp, tools/aspect_check.sh, patches/0027-window-size-switch.patch.
- Edited: src/profile/pure_profile.cpp (the include and `.view_aspect_frame`), CMakeLists.txt (the profile's source list), patches/README.md (row and section), docs/upstream.md (row and section), README.md (the tool row, `PURE_WINDOW_SIZE`, `PURE_TRACE_ASPECT`), docs/status.md (the E2 bullet), docs/verification.md (the check's row and the "Which path" line), and this file.
- Not changed: docs/controls.md. It has no Aspect ratio row to annotate.

### What the code does
- **Install.** `view_aspect_frame` waits until a flip reports a shape other than 480/272, or until the first flip when `PURE_TRACE_ASPECT=1` is set. It then installs once:
  - It finds the generated FUN_08a31148 and registers `pure::perspective` at 0x08a31148.
  - It prints `[aspect] FUN_08a31148 overridden: ...`.
  - If the function is not found, it prints one `not found` line instead and does nothing from then on.
- **`perspective`.** When f13 is within 1e-4 of 480/272 and the last view aspect is not, it sets f13 to the view aspect. It then runs the generated body with ctx.pc at the entry.
  - It counts the calls from the race camera (ra 0x088402c0, the return address of the call at 0x088402b8) apart from the others, and counts the calls it widened.
- **At each flip after the install:**
  - Under another shape, it sets 0x08b1fb14 to the float at 0x08b1fb18 times the aspect (only when that value is finite and positive) and remembers that it did.
  - Back at 480/272 after a change, it writes 0x08b1fb18 x 480/272 once.
- **`PURE_TRACE_ASPECT=1`** prints `[aspect] calls: race camera R (W widened), other O (V widened); view aspect A` once a wall-clock second.

### Departure 1: `lookup_function` is private
- **The problem.** `Runtime::lookup_function` is declared under `private:` in vendor/portablekit/include/psprecomp/runtime.hpp (line 166; `private:` is at line 149). `rt.lookup_function(0x08a31148)` does not compile from the profile, and include/psprecomp is out of bounds.
- **The public route.** The hook defines a `CorpusRuntime` subclass, `Registrations` in aspect.cpp. It uses the corpus ABI's protected constructor with a host table that holds only `register_function` and `register_unit`.
  - It replays `psprecomp::register_generated_functions` and keeps what the corpus registers at 0x08a31148: `recomp_unit_0139`.
  - That is the same pointer the live runtime holds: the game has one statically linked corpus, no editions and no overlays.
  - It runs once, guarded by `rt.has_function(0x08a31148)`. An unknown executable runs under the interpreter and gets the not-found line.
- **The registration then behaves as D-020 says.** Unit 139 is poisoned for direct chaining, and every caller arrives through the function table. The trace counts the race camera's calls at about 60 a second.
- **The alternative.** If the review prefers a public accessor, it is a one-line move in runtime.hpp, at the cost of a corpus rebuild.

### Departure 2: the override goes in at the first flip under another shape
- **Registered at the first flip, as briefed,** the headless suite stayed 18/18, but three race scenes moved:

  | Scene | Without the hook | Registered at the first flip |
  |---|---|---|
  | tt_hud | 0.0112 | 0.0095 |
  | fp_hud | 0.0116 | 0.0262 |
  | zone_change | 0.0369 | 0.0018 |

  - The build without the hook reproduces the old figures.
  - The cause: the registration sends FUN_08a31148's calls through the outer dispatch. That moves where the scheduler's dispatch counts fall (as `PURE_TRACE_RAND`'s README row notes).
- **The change.** The brief asks for the suite unchanged and for nothing registered that changes a picture. So at the PSP's shape the hook now registers and writes nothing, and it installs at the first flip whose shape differs.
- **Results:**
  - The headless suite: 18/18, equal to the hook-less build to the fourth decimal.
  - The Vulkan window suite: 7/7, with no `[aspect]` line in its logs. Its figures match the 2026-10-13 gate log (out/pull22_gate.log) within the window runs' usual swing: fp_hud 0.0488 against 0.0508, zone_change 0.0242 against 0.0240, the rest within 0.0001.
- **`PURE_TRACE_ASPECT=1` installs at the first flip whatever the shape.** Both lanes of the check set it, so they run the same dispatches.
  - Without it, the Original lane raced a moment apart: an AI ship moved, (a) read 0.0770, and the transformed draws were 895 against 858.
  - With it, the Vulkan window suite is also 7/7, with the override running and f13 left alone everywhere: race_hud 0.0441, tt_hud 0.0475, fp_hud 0.0486, zone_hud 0.0453, zone_change 0.0228. On the race route the race camera made 300 calls and none was widened.

### aspect_check (three runs, the same figures to the fourth decimal each time)
- **(a) The central strips.** The 953-pixel strips (x 153 to 1106), reduced to 480x272 by the area mean, differ in 0.0691 at tol 32 between the HUD's bars (rows 40 to 212 of 272). The limit is 0.10.
  - Over the whole strip the figure is 0.0826. The HUD, spread under Fill, raises it, so the bar is the band between the HUD's bars, as the brief allows.
  - A stretched picture (the Original strip spread to 1260 pixels, its centre cut) scores 0.4647.
  - The differences are edges and the crowd's texture, from resampling: Fill draws at 1260x540 natively, while Original draws at 960x544 and is blitted to 953x540.
  - Nearest neighbour gave 0.095 over the whole strip, so the check uses the area mean.
- **(b) The outer strips.** The left and right 153-pixel strips, over the band:

  | Strip | Variance (at least 200) | Apart from the adjacent central 153 pixels, tol 32 (at least 0.30) |
  |---|---|---|
  | Left | 3884.5 | 0.6356 |
  | Right | 6222.6 | 0.5239 |

- **(c) The draws.** Printed, not bound.

  | Lane | `[render] frame 6016 (D draws)` | Transformed draws in the captured frame |
  |---|---|---|
  | Original | 342712 | 857 |
  | Fill | 343264 | 858 |

  - The `[render]` count is cumulative over the run: the renderer never resets it.
  - The transformed draws come from `PURE_TRACE_3D`, the `[3d]` line before the capture.
- **(d) The override's counts.**
  - Original: race camera 297 calls, 0 widened; other 12630, 0 widened.
  - Fill: race camera 296 calls, 296 widened; other 12630, 11736 widened. The square view's aspect of 1.0 is left alone.
  - Both logs have the overridden line, and neither has a not-found line.
- **Time.** 1m 51s with warm pipeline caches. The first run took 3m 40s, because each lane ran again once while its fresh pipeline cache was made.

### Verify output (last 20 lines)
```
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
ok: 27 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 34 files, 0 findings: PASS
```

### Open questions
- **Culling may not follow the wider view.**
  - At flip 6016 the wider view adds one transformed draw (857 to 858).
  - Ghidra lists no reader of 0x08b1fb14 (out/aspect/callers4.txt shows writes only), so the flip's tangent write may reach nothing.
  - The race_hud frame shows no missing scenery at the edges. Objects appearing late at the edges are for Erik's eye in a 21:9 race; D-020's remedy is a second override at the culling function.
- **Departures 1 and 2 above** are design calls for the review.
- **Cost not measured.** The per-PC dispatch of unit 139 while Fill is in use is not measured: stutter_check is not in this Verify. At the PSP's shape there is no cost now.
- **The switch's label.** README.md lists `PURE_WINDOW_SIZE` as run-control, "for the checks", because it shapes the window (the README's definition). The brief called it test-only.

## Review
Merged 89e82bf into batch/m2 (2026-10-13). Verify rerun on the merge from the main checkout (out/084_gate.log,
out/aspect_check/summary.txt): aspect_check PASS in 4m 53s with cold pipeline caches ((a) 0.0793 between the
HUD's bars, 0.0892 over the whole strip, a stretched picture 0.4652; (b) left 3884.5 / 0.6331, right 6222.5 /
0.5239; (c) 865 transformed draws Original, 861 Fill; (d) race camera 289 calls 0 widened against 255 calls 255
widened), the headless suite 18/18 to the digit, patches 27, docs_check PASS; then the Vulkan window suite 7/7
(fp_hud 0.0488, zone_change 0.0522, within the window swing) and `tools/hud_check.sh --shell vulkan` 61 of 61.
Spot-read: src/profile/aspect.cpp (the override, the `Registrations` replay of the corpus registration, the
flip-time tangent write and its restore), patches/0027-window-size-switch.patch, tools/aspect_check.sh.
Both departures accepted: `lookup_function` is private and include/psprecomp is closed, so the replay is the
public route (a comment says why; if upstream opens the lookup it collapses to one line); installing the override
only once a shape other than 480:272 is seen is what the brief's "nothing changes at Original" demands, now that
the registration is known to move the dispatch counts. The 21:9 capture by eye: the vertical field of view kept,
the track and stands continue to both sides, the HUD stretched as expected before task 085. Open: the culling
question stands (the transformed draw counts moved by a few either way between runs, so they say nothing);
Erik's eye in a 21:9 race decides, with D-020's second override as the remedy. The window-size switch is
run-control in README.md's sense, as the worker labelled it.
