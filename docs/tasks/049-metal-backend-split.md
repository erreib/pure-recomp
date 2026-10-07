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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
