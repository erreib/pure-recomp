# 049: Split the Metal backend by concern (the organisation pass, 1 of 5)

Milestone: M9 organisation | Branch: task/049-metal-backend-split | Status: OPEN

## Goal
src/gpu/metal_backend.mm is 2975 lines in one file with 20 structs and one class, and the MSL shaders live as a
string in src/gpu/metal_shaders.h (516 lines). Erik asked for the code to be organised and simplified before
enhancements. This task splits the backend into files by concern with no change in behaviour: the same bytes on
every capture, the same numbers in the trace.

## Read first
- CLAUDE.md, docs/metal-backend.md ("Files", "How a draw is drawn", "Targets", "Textures", "The stencil and the
  alpha", "The bloom chain", "Guest memory", "Frame times", "The pre-warm list", the task sections), docs/ge-backend.md
  (the seam the backend implements), docs/tasks/023, 024, 025, 031, 033 (Results: how the pieces grew)
- src/gpu/metal_backend.mm (all of it), src/gpu/metal_shaders.h, src/gpu/metal_device.{hpp,mm}, src/host/metal_shell.mm
  (what it needs from the backend), CMakeLists.txt (how the .mm files are compiled: `-x objective-c++ -fobjc-arc`)
- tools/frame_regress.sh, tools/gerec/metal_check.sh, tools/frame_times.py (the checks)

## Deliverable
1. The split, under src/gpu/: a header for the shared types (`metal_types.hpp`: the uniform structs with their
   static_asserts, the keys, `Target`, `CachedTexture`, `Stats`, the trace rows), and implementation files by concern,
   each with a short header comment saying what it owns: targets and guest memory (the target cache, block
   transfers, read-backs, write-backs), textures (identity, decode, the chunk pool, mip levels), pipelines (the
   render and depth-stencil keys, the fragment-function variants, the pre-warm list and its parser), effects (the
   stencil-as-alpha resolve, the bloom chain, the 16-bit path), trace (frame times, the trace clock and rows, the exit
   summary), and the backend proper (`metal_backend.mm`: the class, `submit`, the frame flow, the registry). Pick the
   cut points from the code's own structure; the names above are the shape, not a mandate. No file over about 800
   lines.
2. The shaders out of the header string: src/gpu/shaders/ge.metal as a plain Metal source file, embedded at build time
   (a CMake step that turns it into a generated header with a raw string, or any build-time embedding that keeps the
   app self-contained and the headless build path-independent); the backend compiles it at run time as before.
   Syntax highlighting and diffs then work on the shader.
3. The proof of no change: `tools/refactor_check.sh` (new; reusable by the other organisation tasks): captures the
   suite's 18 scenes with the build before the change into a directory, then after, and compares each pair with
   `tools/imgdiff.py --tol 0`, PASS only when every pair has 0 differing pixels; plus `tools/frame_regress.sh` 18/18
   at the same values, `tools/gerec/metal_check.sh` unchanged, and `tools/hud_check.sh --shell headless` 61 of 61.
   Take the "before" captures from the current batch/m2 build at the start, before touching anything.
4. docs/metal-backend.md's "Files" section rewritten for the new layout; CMakeLists.txt for the new files. README.md
   unchanged unless a path it names moves.

## Acceptance criteria
- [ ] `tools/refactor_check.sh` PASS: 0 differing pixels on all 18 scenes against the pre-change build.
- [ ] `tools/frame_regress.sh` 18/18 at the same measured values; `tools/hud_check.sh --shell headless` 61 of 61;
      `tools/gerec/metal_check.sh` passes as before.
- [ ] No file under src/gpu/ over about 800 lines; the shader is a .metal file.

## Verify
`tools/build.sh profile && tools/refactor_check.sh && tools/frame_regress.sh`

## May touch
- src/gpu/ (new files, the split), CMakeLists.txt (the new sources and the shader embedding), tools/refactor_check.sh
  (new), docs/metal-backend.md ("Files")

## Must not touch
- vendor/, patches/, src/host/, src/profile/, src/tools/, config/, tools/frame_regress.sh, tools/gerec/, the behaviour
  of anything (this task moves code; it changes no logic, no constant, no order of operations)

## Estimated turns
50

## Escalate when
A capture differs by even one pixel after the move and the cause is not a build-order or embedding mistake (report
the scene and the pixel: that is a hidden dependency on order, which is a finding, not something to paper over), or
the shader embedding cannot be made self-contained for the bundle.

## Result
Status: DONE. src/gpu/metal_backend.mm (2975 lines) is now seven Objective-C++ files by concern and two headers, and
the shaders are src/gpu/shaders/ge.metal, embedded at build time. Nothing changed on the screen: the new
`tools/refactor_check.sh` finds 0 differing pixels on all 18 scenes against captures taken with the batch/m2 build
(28e5e34) before anything was touched, and the backend's counts are the same in every route. Each commit of the split
was checked the same way, so a difference could be bisected to one concern; none appeared.

Changed:
- New in src/gpu/ (line counts):
  - `metal_types.hpp` (321): the sizes, `GpuVertex` and the uniform blocks with their static_asserts, the keys,
    `Target`, `CachedTexture`, `ChunkPool`, `Stats`, `FrameTimes`, `TraceClock`, `TraceRow`, `Prewarm`, as they were.
  - `metal_backend.hpp` (279): the class. Its methods sit under a heading per concern that names their file, its data
    members are as they were, and it declares the eight helpers more than one file uses.
  - `metal_targets.mm` (401), `metal_textures.mm` (286), `metal_pipelines.mm` (380), `metal_effects.mm` (157),
    `metal_trace.mm` (172), `metal_draw.mm` (725). Each opens with a comment saying what it owns.
  - `shaders/ge.metal` (510): the MSL, the old string's text with the old header's description in front as comments.
  - `shaders/embed.cmake` (17): the build step that writes `build/<preset>/generated_metal/ge_metal.hpp`, ge.metal
    byte for byte as a raw string under the old name, `pure::metal::kShaderSource`.
- `src/gpu/metal_backend.mm` (483, was 2975): start and shutdown, submit, the flip, captures, the command buffers,
  passes and vertex space, `not_emulated` and the registration. Its opening comment is the overview it always had,
  plus a paragraph naming the files.
- Removed: `src/gpu/metal_shaders.h` (516).
- `tools/refactor_check.sh` (203, new):
  - `--before` captures the suite's scenes with the current build into out/refactor/before. It records the shell,
    the backend and the environment.
  - Without `--before`, it captures again with those settings. It compares each pair with imgdiff `--tol 0
    --max-frac 0`, and each route's `[metal]` exit and 600-frame lines. Times, rates, GPU waits and the pre-warm's
    timing-dependent split are taken out of those lines.
  - `--wait SECONDS` (default 600) waits out the one-game guard.
  - Run twice on the unchanged build, it passed: 18/18 at 0 pixels, counts the same.
- `CMakeLists.txt`: `metal_backend_sources` (the seven files), every `.mm` through one `set_source_files_properties`,
  and the embedding step (`add_custom_command`, `target_sources`, the include directory).
- `docs/metal-backend.md`: "Files" rewritten: the layout, where new code goes, and the refactor check. Outside it,
  three lines named `metal_shaders.h`, which no longer exists; they name `shaders/ge.metal` now. The opening line
  names the files beside metal_backend.mm.
- `README.md`: the `src/gpu/` row, since `metal_shaders.h` moved (deliverable 4).

How the move was made. A script took each member function's text from the class body and removed four columns of
indentation. In each definition it qualified the name (`MetalGeBackend::`) and dropped `static`, `override` and the
one default argument. It rewrapped the eight signatures that then ran past 120 columns. The bodies and comments are the
original lines. The code moved from the anonymous namespace to `pure::gpu::metal_backend`, because a class shared
between files needs a name. The backend builds with clang's default `-ffp-contract=on`, which fuses only within one
expression, so moving a function to another file cannot change a float result. The captures agree.

Checks besides Verify:
- `tools/frame_regress.sh`: 18/18. The table is the same as before the change to the fourth decimal (zone_change
  0.0369 both times).
- `tools/hud_check.sh --shell headless`: 61 of 61. The 61 race shots (flips 6200 to 7700) are byte-identical to the
  before build's.
- `tools/gerec/metal_check.sh`: PASS before and after (team 0/130560 px, race 2/130560 px at tol 24).
  - The replays' diffs and bisection steps are the same, first differences at draws 508 and 40.
  - Metal's pictures of team frames 5650 and 5651 and race frame 6016 are byte-identical.
- The race route headless, four runs: twice on the starting build (its sources rebuilt in place, then restored) and
  twice on the split. Each ran with `PURE_METAL_TRACE`, `PURE_METAL_PIPELINES_OUT`, `PURE_TRACE_STENCIL_COPY` and
  `PURE_TRACE_DEPTH_READBACK`. All four agree on:
  - the trace's count columns over 6046 rows;
  - the 693 `[metal]` lines, among them the 339 stencil copies and the 339 depth write-backs with their z ranges;
  - the key list (29 render, 22 depth-stencil) and the 6 shots.
- The shader: the embedded text is ge.metal byte for byte. With comments stripped, its 366 lines of code are the old
  string's.
- Touching ge.metal re-embeds it and recompiles metal_backend.mm alone. The embed script writes the same header into
  a fresh directory.
- A trial merge with today's batch/m2 (tasks 050 to 052 in it) has no conflicts.

Verify output (last 20 lines), `tools/verify_task.sh 049` at f74fcdf:
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0113   0.12   32    0.0112 +0.0001  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0115   0.11   32    0.0116 -0.0001  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 26s)
verify 049: PASS
```

The refactor check's table from that run (`out/refactor/summary.txt`; before: 28e5e34, after: f74fcdf):
```
scene               differing  result
class_select                0  PASS
fp_hud                      0  PASS
fp_track_select             0  PASS
lang                        0  PASS
league_select               0  PASS
main_menu                   0  PASS
profile                     0  PASS
race_hud                    0  PASS
single_player               0  PASS
team_select                 0  PASS
title                       0  PASS
tournament_select           0  PASS
track_select                0  PASS
tt_hud                      0  PASS
tt_track_select             0  PASS
zone_change                 0  PASS
zone_hud                    0  PASS
zone_track_select           0  PASS

counts: the same in every route (86 [metal] lines)
refactor check: PASS, 18/18 scenes with 0 differing pixels, counts PASS (0m 26s)
```

Open questions:
1. **The shader cache misses once.** The shader's text changed by comments only: the old header's description is in
   front, and the comments name the new C++ files. Metal's shader cache therefore misses once on each machine after
   this lands. That costs one compile at start, about 0.2 to 0.7 s (447 ms in one of the runs here). The pictures are
   the same.
2. **Runs with the per-draw log are not reproducible.** So `PURE_METAL_LOG=1` could not serve as a before/after
   check.
   - On the race route, two runs of the same split build drew 368758 and 373243 times. Without the log, every run
     draws 372713.
   - Two runs of the starting build with the log drew 372713 both times.
   - The difference is in the boot's loading screen, flips 118 to 124, where some flips lack the logo sprites. The
     guest's loading progress against the flips depends on how fast the host runs while the log is written.
   - So something in the boot path follows host time. That matters to any check that compares logs. batch/m2's
     f34a1eb ("Turn the busy-time charge off for headless runs in run_boot") may touch the same thing; not checked.
3. **Retake the before captures at the merge point.** When this merges, run `tools/refactor_check.sh --before` on
   batch/m2 first rather than reuse this worktree's captures. batch/m2 has changed headless runs since 28e5e34
   (f34a1eb), which may move headless pictures.
4. **Stale names outside May touch.**
   - `config/metal_pipelines.txt` line 10 says the keys are in metal_backend.mm. They are in metal_types.hpp now.
   - `tools/bundle.sh` line 239 says the backend looks for the list in metal_backend.mm. That is
     metal_pipelines.mm's `find_pipeline_list` now.
   - docs/metal-backend.md's task 033 table ("What changed") names `metal_backend.mm` `start_prewarm`. It records
     that task, so it was left.
5. **The chunk pool stayed in metal_backend.mm.** The brief listed it under textures. It is the frame's vertex and
   upload space (`allocate`, handed back in `commit`), so it stayed with the command buffers.
6. **Worth simplifying; seen during the move and not done.** Each would change code rather than move it.
   - `draw()` is 300 lines. The block that sets the encoder's state when it changed (`bound_`) could be a function
     of its own.
   - `read_back` repeats `copy_to_buffer`'s blit, and `store_depth` repeats it with the depth option. One helper
     could serve all three.
   - `find_framebuffer_texture` and `drawn_target_containing` share the same scan of `targets_`: the target that
     starts at the address, else the one drawn last. `latest_target_at` and `target_holding` are two more scans.
   - The class holds about 90 data members for every concern. Three groups could each become a small struct owned
     by its file: the trace's (`times_`, `trace_*`), the pre-warm's (`prewarm_*`, `pipelines_out_`, `render_seen_`,
     `depth_seen_`) and the switches (`no_*_`).
   - The suite's metal column says 0.0353 for zone_change. batch/m2 scored 0.0369 before this task and after it.
     That is not this task's; a re-baseline is docs/verification.md's call.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
