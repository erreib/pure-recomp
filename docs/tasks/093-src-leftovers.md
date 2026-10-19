# 093: The src leftovers (scaffolding, a probe, duplicate helpers)

Milestone: cleanup (audit 2026-10-19) | Branch: task/093-src-leftovers | Status: MERGED

## Goal
Our own code carries only what is used. The audit (docs/history/audit-2026-10-19.md, "src/ and config/") found
scaffolding nothing uses, one finished probe, helpers written twice and a few dead lines. Remove or merge them with no
change to any picture, timing or log line a check reads. The sprite upscaler (E7) stays, by Erik's call.

## Read first (about 20K tokens)
- docs/history/audit-2026-10-19.md, "src/ and config/" (the list below repeats it with locations).
- src/host/pure_main.cpp (24 lines); src/gpu/metal_shell.{hpp,cpp}; src/gpu/metal_backend.mm lines 200-270 and
  370-400; src/gpu/metal_targets.mm 210-240; src/profile/test_hooks.cpp 1-60 and 100-135.
- vendor/portablekit/host/gpu/vulkan_renderer.hpp: `default_window_title`, `kFastForwardPresentInterval`,
  `usable_aspect` (read-only: the vendor is not changed here).

## Deliverable
1. **The Metal backend's hand-over to the Vulkan shell goes**: src/gpu/metal_shell.{hpp,cpp}, `Switches::to_shell`,
   `shell_`, `shell_scratch_`, `PendingFrame::from_picture`, the `PURE_METAL_SHELL` read and the branches using them
   (metal_backend.mm about 214-219, 261-263, 386-390; metal_targets.mm about 220-235); the CMake source list follows.
   Then pure_main.cpp: when PURE_SHELL is vulkan and PURE_GE_BACKEND is unset, the backend defaults to vulkan (so
   `PURE_SHELL=vulkan` alone still shows a picture). Under the Metal shell and headless nothing changes.
2. **PURE_WATCH_MOVIE goes** (test_hooks.cpp about 103-131). PURE_WATCH_RAND and PURE_TRACE_RAND stay, with
   `kReentPtr` and `kRandState`.
3. **The Metal shell calls the vendor's exports** instead of its copies: `gpu::default_window_title()`,
   `gpu::kFastForwardPresentInterval`, `VulkanRenderer::usable_aspect()` (metal_shell.mm about 95, 129-133, 147-151),
   if it links on this Mac (it builds the Vulkan renderer); if a link needs a vendor change, keep the copy and say so.
4. **One copy of each helper in src/**: the texture-format and primitive name tables (metal_textures.mm `format_name`,
   metal_draw.mm `kPrimitives`, ge_replay.cpp `texture_format_name` and `primitive_name`) in one small header under
   src/gpu/; one `env_on`-style flag reader used by test_hooks.cpp, aspect.cpp, metal_backend.mm and metal_shell.mm
   where they spell it out (keep each switch's exact semantics: a switch that is on when merely set stays so, matching
   the vendor's reading of the same name); one `load_float` and one hex formatter; `sixty_fps` uses `race_backend()`.
5. **PURE_METAL_SHOW_TARGET is replaced by the vendor's name, PURE_SHOW_TARGET**, read by the Metal backend with the
   same meaning (the target drawn last at that address presented instead of the display).
6. **Dead lines go**: `kLevelNone` (metal_types.hpp), `TraceRow::shell_presents`, `take_later_field`
   (metal_pipelines.mm; every line of config/metal_pipelines.txt carries the later fields: check before removing).
7. **config/pad_scripts/beta_sinucit.txt and beta_sebenco_climb.txt go** if `grep -rn` over tools/ and the non-task
   docs still finds no reader.
8. **Docs: none in this task.** Another task is restructuring docs/ now. List in the Result each doc row or mention
   that must change (PURE_METAL_SHELL, PURE_WATCH_MOVIE, PURE_METAL_SHOW_TARGET in developing.md, metal-backend.md,
   ge-backend.md) and the planning session applies them after both merges.

## Acceptance criteria
- [ ] Every picture check unchanged: the headless suite 18/18, refactor_check PASS (its pixel compare), gerec
      metal_check PASS, texture_check and sprite_check PASS.
- [ ] `PURE_SHELL=vulkan` with no PURE_GE_BACKEND defaults to the vulkan backend (shown by the `[pure]`/`[shell]`
      startup lines of a short headless-free check: read the code path and state it; no window run).
- [ ] The Result gives lines removed per item and the doc changes owed.
- [ ] No vendor/, include/psprecomp/, tools/ or docs/ change other than this task file.

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/refactor_check.sh && tools/gerec/metal_check.sh && tools/texture_check.sh && tools/sprite_check.sh`

## Window checks (not run by the worker; listed for the planning session's screen batch)
`tools/menu_check.sh`, `tools/menu_check.sh --shell vulkan`, `tools/frame_regress.sh --shell metal`,
`tools/frame_regress.sh --shell vulkan --backend vulkan`.

## Running beside other work
The accuracy scorecard (headless, about 20 minutes) may be running when you start, and another worker may run games
later. One game at a time: before each check, wait until no PureNative runs (`pgrep -x PureNative`, a bounded wait
of 30 minutes, checking every 30 s); if a check still refuses because another game started, wait and rerun it.

## May touch
- src/ (the files named above, the new header), CMakeLists.txt (the source list only), config/pad_scripts/ (the
  two files), docs/tasks/093-src-leftovers.md

## Must not touch
- vendor/, vendor/portablekit/include/psprecomp/, patches/, tools/, docs/ (other than this file), generated/,
  game/ (above all game/ms0), disc/, ref/; tools/regen.sh, tools/build.sh all; no window run

## Estimated turns
45

## Escalate when
- Any picture check changes, and the cause is not a mistake of this task.
- An item turns out to have a user this audit missed (a tool, a doc's recipe a check depends on, a game path): keep
  it and report.

## Result
Status: DONE. Every item is in. Every picture check is unchanged against the build before (b63590f, the branch point).
The literal Verify chain still stops at two checks, for causes outside this task: refactor_check's counts filter, and
metal_check under Erik's settings.ini. Both are explained under Verify, with the reruns that prove it.

Changed (10 commits on task/093-src-leftovers, one per item; item 1 has a one-line comment follow-up):
- src/host/pure_main.cpp; src/gpu/metal_backend.{hpp,mm}, metal_targets.mm, metal_types.hpp, metal_draw.mm,
  metal_textures.mm, metal_pipelines.mm, metal_trace.mm; src/gpu/metal_shell.{hpp,cpp} (deleted); src/host/metal_shell.mm;
  src/tools/ge_replay.cpp; src/profile/test_hooks.{hpp,cpp}, aspect.cpp, enhancements.cpp; CMakeLists.txt (source list);
  config/pad_scripts/beta_sinucit.txt and beta_sebenco_climb.txt (deleted); this file.
- New: src/gpu/ge_names.hpp (the name tables, plain C++ so that ge_replay can include it) and src/helpers.hpp (env_on,
  hex, load_float). The second header goes beyond "the new header" in May touch. Its users are in src/profile,
  src/gpu, src/host and src/tools, so it sits at src/.
- Total: 22 files, +171 -329 (net -158).

Lines per item (added/removed, net):
1. Hand-over to the Vulkan shell: +31 -128, net -97. metal_shell.{hpp,cpp} -75, `Switches::to_shell`, `shell_`,
   `shell_scratch_`, `PendingFrame::from_picture`, the PURE_METAL_SHELL read and the branches in present_image and
   write_back_frame are gone.
   pure_main.cpp: the backend defaults to vulkan when the shell is the Vulkan one, meaning PURE_SHELL is vulkan or empty
   (the framework reads empty as vulkan) and PURE_NO_RENDER is unset. Under the Metal shell and headless (PURE_NO_RENDER
   set, whatever PURE_SHELL says) it stays metal.
   Code path for `PURE_SHELL=vulkan` with no PURE_GE_BACKEND: main() sets PURE_GE_BACKEND=vulkan, so
   ensure_shell_and_backend() makes vulkan/vulkan. The startup log then shows no `[shell] ...` line (printed only when
   the shell is not vulkan), no `[render] GE backend ...` line (printed only when the backend is not vulkan) and no
   `[metal] drawing with` line. Before this task the same run printed `[render] GE backend metal (...), in the window`
   and `[metal] ...; pictures shown in the window`. Not run: it opens a window.
   The `[metal] drawing with ...` startup line now ends at "shaders compiled in N ms". Under the Vulkan shell, with
   metal named explicitly, it adds "; the Vulkan shell shows none of its pictures". No check reads that tail: scale_check
   cuts it, refactor_check drops the line.
2. PURE_WATCH_MOVIE: +4 -35, net -31. PURE_WATCH_RAND, PURE_TRACE_RAND, kReentPtr and kRandState stay.
3. The Metal shell on gpu::default_window_title(), gpu::kFastForwardPresentInterval and
   VulkanRenderer::usable_aspect(): +7 -25, net -18. It links on this Mac with no vendor change.
4. One copy of each helper:
   - Name tables: +36 -33, net +3. The Metal log's spelling stays (CLUT8, tristrip). ge_replay's differing-draw
     description now uses it too (it used clut8, triangle_strip). metal_check prints those lines and parses none.
   - env_on, hex, load_float: +71 -56, net +15. env_on is the profile's reading: on when set to a value not starting
     with 0, and the default when unset or empty. PURE_METAL_PACE passes the default `true`. The documented values read
     as before. Two undocumented values now read differently: PURE_METAL_LOG and PURE_METAL_PACE set to something like
     `00` or `0x` (they compared against "0" exactly). The switches that are on when merely set (NO_LIGHTING, NO_FOG,
     NO_CULL, NO_FB_TEXTURES, NO_TEXMAP, NO_MIPMAPS, NO_COLOR_TEST, NO_DITHER, NO_DEPTH_CLAMP,
     TRACE_STENCIL_COPY, TRACE_DEPTH_READBACK) keep that meaning through the vendor's portablekit::env_set.
   - sixty_fps through race_backend(): +11 -13, net -2. It keeps its own check that the lock byte lies in user RAM.
5. PURE_SHOW_TARGET read by the Metal backend, same meaning, same strtoul reading: +5 -4, net +1.
6. Dead lines (kLevelNone, TraceRow::shell_presents, take_later_field): +6 -19, net -13. All 37 render lines of
   config/metal_pipelines.txt carry color_test and sixteen, and the list's writer always writes both.
7. The two pad scripts: -16. grep over tools/ and the docs outside tasks/ and history/ found no reader. The scorecard
   builds its Beta HUD runs itself (race_steps).

Verify output:
The literal chain stopped at refactor_check. Each check was then run alone on this build:
- `tools/build.sh profile`: no warnings.
- frame_regress: `frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)`.
- refactor_check: `refactor check: FAIL, 18/18 scenes with 0 differing pixels, counts FAIL`.
  The pixel compare passes. In counts.diff only the "N GPU waits" figure moves; every count beside it is equal. The
  tool means to drop the GPU waits ("depend on when the GPU finishes"). Its pattern `, N GPU waits (X ms) in Y s$` is
  anchored at the line's end, and the exit line now ends "; N textures upscaled (X ms)", so it no longer matches.
  With the waits taken out anywhere in the line, before and after are the same on all 7 routes, in two after runs.
  The waits vary on one binary: two after runs of this build gave frontend 190 / 176, main_menu 356 / 195, zone
  305 / 200 (before: 160, 244, 196).
- metal_check under the shared settings: `metal_check: FAIL (623 s): team.gerec ... race_1x.gerec frame 6016 ...`.
  The before build (b63590f) fails the same way on the same recordings: team 0.153370 and race 0.196423, the same
  numbers. The cause is ge_replay's Vulkan lane reading the user settings.ini
  (~/Library/Application Support/pure-recomp/PureNative/settings.ini, changed 08:01 today). It has
  video.performance=overlay (the overlay is in the Vulkan capture: 14k pixels after a single clear draw),
  video.texture_pack=1 and video.aspect=fill.
- metal_check with `PURE_DATA_DIR=<an empty dir under out/>`: `metal_check: PASS (5 s)`. team 0/130560 px, race_1x
  frame 6016 13/130560 px; step 4b (reported, not a pass condition) 0.067884. The before build gives exactly the same
  three numbers on the same recordings.
- texture_check: `texture check, shell headless: 4/4 scenes pass, the enhanced draws PASS, race_hud at scale 1 PASS` /
  `texture_check: PASS`.
- sprite_check: `sprite check: 7/7 scenes pass, the main menu's upscales PASS (0m 38s)` / `sprite_check: PASS`.

Last lines of that run (refactor_check, metal_check, texture_check, sprite_check in sequence):
```
refactor check: FAIL, 18/18 scenes with 0 differing pixels, counts FAIL (0m 23s)
== refactor_check exit 1
metal_check: FAIL (623 s): team.gerec: vulkan against metal exit 1 (log out/gerec/metal_team.log); race_1x.gerec frame 6016: vulkan against metal exit 1 (log out/gerec/metal_race.log);
== metal_check exit 1
race_hud    1920x1088   0.0467    0.1   32   0.0218    3.5752    4.0681  1.1378  yes  PASS
tt_hud      1920x1088   0.0473   0.12   32   0.0244    3.5424    4.3499  1.2279  yes  PASS
fp_hud      1920x1088   0.0472   0.11   32   0.0244    3.5210    4.3300  1.2298  yes  PASS
texture check, shell headless: 4/4 scenes pass, the enhanced draws PASS, race_hud at scale 1 PASS (0m 39s)
texture_check: PASS
title           1920x1088   0.0198   0.05   24   0.0213    -  PASS
main_menu       1920x1088   0.0411   0.05   24   0.0359    -  PASS
class_select    1920x1088   0.0621   0.07   24   0.0583    -  PASS
team_select     1920x1088   0.0585   0.06   24   0.0689    -  PASS
race_hud        1920x1088   0.0414    0.1   32   0.0156  yes  PASS
tt_hud          1920x1088   0.0411   0.12   32   0.0213  yes  PASS
fp_hud          1920x1088   0.0413   0.11   32   0.0203  yes  PASS
main_menu run: 25 textures upscaled in 69.7 ms (at least 2, under 2000 ms): PASS
sprite check: 7/7 scenes pass, the main menu's upscales PASS (0m 38s)
sprite_check: PASS
--- metal_check, PURE_DATA_DIR an empty dir (this build; the before build prints the same figures):
[replay] frame 5650: 66 draws, 212 records, 57.2 + 4.7 ms (vulkan + metal), diff 0.000000 (tol 24, 0/130560 px at 480x272) PASS
[replay] frame 6016: 907 draws, 1296 records, 8.2 + 3.2 ms (vulkan + metal), diff 0.000100 (tol 24, 13/130560 px at 480x272) PASS
metal_check: PASS (5 s)
```

Window checks owed (not run): `tools/menu_check.sh`, `tools/menu_check.sh --shell vulkan`,
`tools/frame_regress.sh --shell metal`, `tools/frame_regress.sh --shell vulkan --backend vulkan`. Also, if wanted, one
short `tools/run_boot.py --shell vulkan` with no --backend, to see PURE_SHELL=vulkan alone draw with the vulkan backend.

Docs owed (none changed here):
- docs/developing.md
  - Line 14 (`src/gpu/` row): drop `metal_shell.cpp` ("hands each picture to the Vulkan window shell ...") and add
    `ge_names.hpp`. Add `src/helpers.hpp` (env_on, hex, load_float) to the src rows.
  - Line 16 (pure_main.cpp row): PURE_GE_BACKEND defaults to vulkan when the shell is the Vulkan one.
  - Line 151 (PURE_GE_BACKEND row): "with the window it hands each picture to the window ... (`PURE_METAL_SHELL`)"
    becomes: under the Vulkan shell its pictures reach no window. The default is metal, or vulkan under the Vulkan
    shell.
  - Line 158 (PURE_SHOW_TARGET row): both backends now, and "(Metal's `PURE_METAL_SHOW_TARGET`)" goes.
  - Line 161 (PURE_METAL_SHOW_TARGET row): delete, keeping its example (0x04154000, `ge_replay --cut ... --out`) in the
    PURE_SHOW_TARGET row.
  - Line 162 (PURE_METAL_SHELL row): delete.
  - Line 178 (PURE_SHELL row): "The Vulkan path is `PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan`" becomes
    `PURE_SHELL=vulkan` alone.
  - Line 180 (PURE_WATCH_MOVIE row): delete.
- docs/metal-backend.md
  - Line 45 (PURE_METAL_SHELL row): delete.
  - Line 57: PURE_METAL_SHOW_TARGET becomes PURE_SHOW_TARGET.
  - Lines 66-68: the quoted startup line loses "; pictures shown in the window".
  - Line 93 (Files row `src/gpu/metal_shell.hpp`, `.cpp`): delete, and add `src/gpu/ge_names.hpp`.
  - "The window", lines 312-328: rewrite. There is no hand-over; the Vulkan shell shows only the Vulkan backend's
    pictures; PURE_SHELL=vulkan alone picks it.
  - Line 361 (Frames row): drop "the read-back for the Vulkan shell's hand-over is at that size too".
  - Line 1061 (wait_capture_ms): "captures and the Vulkan shell's hand-over" becomes "captures".
- docs/ge-backend.md, line 97: the metal row's Vulkan-shell cell ("read back and shown in the Vulkan window
  (`PURE_METAL_SHELL=0` ...)") becomes: the window stays black, and PURE_SHELL=vulkan alone picks the vulkan backend.
- docs/verification.md, line 377: drop `PURE_WATCH_MOVIE` from the test switches.
- docs/status.md, line 47 (Metal backend row): drop the `metal_shell.cpp` hand-over mention.

Open questions:
1. tools/refactor_check.sh's counts filter should drop the GPU waits wherever they stand in the line (drop the `$`
   anchor). Until then every refactor_check fails on counts, this task's and any other. This is a tools/ change, for
   task 094 or the planning session.
2. tools/gerec/metal_check.sh replays against the user's settings.ini. It should give the replay its own data dir
   (PURE_DATA_DIR under out/), as run_boot does for the recordings. Otherwise Erik's video.performance, texture_pack and
   aspect settings fail it.
3. `PURE_SHELL=vulkan PURE_GE_BACKEND=metal`, named explicitly, now shows a black window (the startup line says so).
   Nothing uses that pairing.

## Review
Merged 1bb0a44 into batch/m2 as 6d51c6a (2026-10-19). Gate (docs/approach.md rule 3): batch/m2 gained only docs
(task 092) since the branch point, so the merged code is the worker's; the profile build on the merge is clean, and the
worker's runs stand: the suite 18/18, refactor_check 18/18 pixels (its counts filter is broken, see below), metal_check
PASS with an empty data directory and with the same figures as the build before, texture_check and sprite_check PASS.
Spot-read: src/host/pure_main.cpp (the Vulkan shell's default backend), src/helpers.hpp (`env_on` keeps the profile's
reading; the framework's on-when-set switches still go through `env_set`), the hand-over's removal in
metal_backend.mm. The docs owed are applied (developing.md, metal-backend.md "The window" rewritten, ge-backend.md,
verification.md). The two tool defects it found (refactor_check's counts filter anchored at the line's end;
metal_check and replay_check reading the user's settings.ini) went to task 094. Window checks owed to the screen batch:
menu_check on both shells, the window suites on both shells, one `PURE_SHELL=vulkan` start with no backend named.
