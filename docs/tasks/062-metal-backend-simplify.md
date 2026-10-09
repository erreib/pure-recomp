# 062: Simplify the Metal backend (the simplification task from 049's list)

Milestone: M9 organisation (follow-up) | Branch: task/062-metal-backend-simplify | Status: OPEN

## Goal
Task 049 split the Metal backend into files by concern and noted four simplifications it saw and did not do,
because they change code rather than move it. This task does those four, one commit each, and proves after
each that nothing on the screen or in the backend's counts changed. When it is done the backend reads as one
design rather than as the layers of tasks 023 to 040, and the enhancements (E3's internal resolution, E5's
filtering) start from the simpler shape.

## Read first
- CLAUDE.md, docs/metal-backend.md ("Files" and the sections the items below name), docs/tasks/049-metal-backend-split.md
  (the Result's "Simplifications seen" and how the refactor check was used commit by commit)
- src/gpu/metal_backend.hpp (the class), src/gpu/metal_types.hpp, src/gpu/metal_backend.mm, metal_targets.mm,
  metal_textures.mm, metal_draw.mm, metal_trace.mm, metal_pipelines.mm
- tools/refactor_check.sh (its header: --before first, on the untouched starting commit, built in this worktree)

## Deliverable
Before any edit: `tools/build.sh profile && tools/refactor_check.sh --before` in this worktree on the starting
commit (the one `git switch -c` branched from). Then four changes, in this order, each its own commit, each
followed by `tools/build.sh profile && tools/refactor_check.sh` (PASS: 0 differing pixels on every scene, the
`[metal]` counts the same) before the next starts, so that any difference bisects to one change:

1. **One blit.** `read_back` (metal_backend.mm), `copy_to_buffer` (metal_backend.mm) and `store_depth`
   (metal_targets.mm) each write out the same `copyFromTexture:...toBuffer:` blit (ensure_commands, end_encoder,
   a blit encoder, the 480x272 copy at kWidth * 4 bytes a row, endEncoding). One private helper does the blit,
   taking the source texture, the destination buffer and the `MTLBlitOption` (none, or
   `MTLBlitOptionDepthFromDepthStencil` for the depth); the three callers keep their own commit, wait and
   accounting lines as they are. Afterwards `copyFromTexture:` occurs once under src/gpu/.
2. **One target span.** `latest_target_at`, `drawn_target_containing` (metal_targets.mm), `target_holding`
   (metal_textures.mm) and `find_framebuffer_texture` (metal_targets.mm) each scan `targets_` and each compute a
   target's byte extent (`stride * kHeight * bytes_per_pixel()`) and its containment of an address in their own
   words. Give `Target` (or a free function beside it in metal_types.hpp) one `bytes()` and one
   `contains(address)` (or `span()` returning first and end), and write the four scans against them. Keep each
   scan's selection rule exactly as its comment states it (newest draw_serial; exact start over containing;
   VRAM only; first overlap), and keep the four functions: the rules differ, the arithmetic should not.
   `find_framebuffer_texture`'s extra conditions (row length, format, unchanged guest words) stay as they are.
3. **draw() in parts.** `MetalGeBackend::draw` (metal_draw.mm, about 300 lines) does, in order: the decode and
   scissor, the texture and its source target, the pipeline key and the fragment uniforms, lighting and fog, the
   positions and the viewport, then the encoder-state block (the pass, the pipeline, the depth-stencil state, the
   stencil reference, the blend colour, the sampler, the textures, the uniform buffers, cull and winding, the
   lighting block) and the draw call itself. Move the encoder-state block into its own member function (one or
   two: binding the state that `Bound` tracks is the natural cut) called from `draw()` at the same point, with the
   same conditions, in the same order of Metal calls. `draw()` ends under 160 lines. No Metal call changes order,
   no condition changes, no `Bound` comparison is added or dropped.
4. **The members by owner.** `MetalGeBackend` holds about 90 data members. Gather into three structs, each owned
   by the file that reads it, the members that belong to one concern:
   - the trace's (metal_trace.mm): `times_`, `trace_stats_`, `trace_file_`, `pending_rows_`, `trace_rows_`,
     `trace_shown_`, `trace_not_shown_`, `trace_last_flip_`, `last_presented_s_`, `trace_stencil_copy_`,
     `trace_depth_` and the report counters (`report_start_`, `report_frames_`, `report_draws_`) if they are read
     only by the trace;
   - the pre-warm's and pipeline recording's (metal_pipelines.mm): `render_seen_`, `depth_seen_`, `prewarm_`,
     `prewarm_start_ms_`, `prewarm_used_`, `prewarm_waits_`, `prewarm_missed_`;
   - the switches' (read once in the constructor, metal_backend.mm): `no_framebuffer_textures_`, `no_lighting_`,
     `no_fog_`, `no_cull_`, `no_texture_map_`, `no_mipmaps_`, `no_color_test_`, `no_dither_`, `no_depth_clamp_`,
     `show_target_` and any other `PURE_*`-set flag the constructor fills.
   Each struct is declared in metal_types.hpp (or metal_backend.hpp beside `Bound`), the class holds one member
   of each (`trace_`, `prewarm_`, `switches_`), and every reader is rewritten to go through it. Initial values,
   the point each is read and the point each is written stay the same. The class ends with at most 50 direct
   data members (count the lines of metal_backend.hpp that declare one). A member that two concerns share
   (`stats_`, `frames_`, `frame_draws_`, `last_wait_ms_`) stays where it is: say in the Result which you left
   and why.

docs/metal-backend.md: "Files" names the new helper functions and the three structs where it describes what
each file owns; nothing else in the doc changes, because nothing else in the backend changes.

## Acceptance criteria
- [ ] `tools/refactor_check.sh` PASS after each of the four commits and at the end: 0 differing pixels on all 18
      scenes against the before captures, the `[metal]` counts the same in every route.
- [ ] `tools/frame_regress.sh` 18/18 at the same measured values as before; `tools/hud_check.sh --shell headless`
      61 of 61; `tools/gerec/metal_check.sh` PASS (it needs the screen; run it once at the end).
- [ ] `grep -c 'copyFromTexture:' src/gpu/*.mm` totals 1; the four scans compute no byte extent of their own;
      `draw()` under 160 lines; `MetalGeBackend` with at most 50 direct data members.
- [ ] No constant, no default, no order of Metal calls, no `PURE_*` switch's meaning changed: the diff is
      structure.

## Verify
`tools/build.sh profile && tools/refactor_check.sh && tools/frame_regress.sh && tools/hud_check.sh --shell headless`

## May touch
- src/gpu/metal_backend.hpp, src/gpu/metal_types.hpp, src/gpu/metal_backend.mm, metal_targets.mm,
  metal_textures.mm, metal_draw.mm, metal_trace.mm, metal_pipelines.mm, metal_effects.mm
- docs/metal-backend.md ("Files" only)

## Must not touch
- vendor/, patches/, src/gpu/shaders/, src/gpu/metal_shell.*, src/gpu/metal_device.*, src/host/, src/profile/,
  tools/, config/, ref/, CMakeLists.txt, and the behaviour of anything (this task changes structure; it changes no
  logic, no constant, no order of GPU commands)

## Estimated turns
50

## Escalate when
A capture or a count differs after one of the four changes and the cause is not a slip in that change (a
difference that survives a careful re-read is a hidden dependency on order or on a member's lifetime: report the
change, the scene and the pixel or count, revert that change, keep the others, and stop with PARTIAL); `draw()`
cannot get under 160 lines without reordering a Metal call (report the size reached); a member in the struct
lists above turns out to be read by a file other than its owner's in a way that a struct would have to expose
through the class anyway (leave it direct and say so, that is not an escalation).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
