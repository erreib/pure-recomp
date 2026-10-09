# 062: Simplify the Metal backend (the simplification task from 049's list)

Milestone: M9 organisation (follow-up) | Branch: task/062-metal-backend-simplify | Status: MERGED (1589688, 2026-10-09)

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
Status: DONE. All four simplifications are in, one commit each, and the backend draws exactly what it drew before.
The before captures were taken with the untouched starting commit (4b0f75f), built in this worktree. After each
commit, `tools/build.sh profile && tools/refactor_check.sh` passed: 18/18 scenes at 0 differing pixels, and the
`[metal]` counts the same in every route (86 lines).

Changed (src/gpu/metal_backend.hpp, metal_types.hpp, metal_backend.mm, metal_targets.mm, metal_textures.mm,
metal_draw.mm, metal_trace.mm, metal_pipelines.mm, metal_effects.mm; docs/metal-backend.md "Files"):
- 448ad72, one blit. `copy_to_buffer(texture, buffer, MTLBlitOption)` in metal_backend.mm is now the only place
  the `copyFromTexture:...toBuffer:` blit is written. read_back, store_depth (with
  `MTLBlitOptionDepthFromDepthStencil`), store_target and present_image's frame write-back all call it, and each
  keeps its own commit, wait and accounting lines. I turned the existing copy_to_buffer into the helper rather than
  wrapping it in a new one.
- b57f5d6, one target span. `Target::bytes()` and `Target::contains(address)` are in metal_types.hpp.
  drawn_target_containing, find_framebuffer_texture and target_holding now use them, each with its selection rule
  and comment unchanged. latest_target_at only ever matched the exact address and computed no extent, so it is
  unchanged. find_framebuffer_texture's extent was 32-bit and is now 64-bit. The GE's stride register is 16 bits,
  and even the largest extent (65535 x 272 x 4 bytes) fits in 32 bits, so the result is the same.
- a42c1fe, draw() in parts. The encoder-state block is now two functions, called at the same point with the Metal
  calls in the same order:
  - `bind_state`: the pipeline, depth-stencil state, stencil reference, viewport, depth clip, scissor, cull and
    winding, and blend colour.
  - `bind_inputs`: the vertex buffer, vertex uniforms, lighting block, fragment uniforms, texture and sampler.

  I did not cut exactly at what `Bound` tracks. Bound tracks the vertex buffer, texture and sampler, but their calls
  sit on either side of the uniform calls, so a Bound-only function would have reordered Metal calls.

  The encoder block alone left draw() at about 230 lines. Two blocks that make no Metal call moved out as well, each
  called from its old place:
  - `set_pipeline_key`: the clear-or-draw branch that fills the key, the fragment uniforms of the tests and blend,
    the blend colour, the stencil reference and `follows`.
  - `fold_viewport`: the GE viewport folded into clip space, plus the depth clamp or the depth range.

  draw() is now 133 lines (was 300). One condition changed form but not meaning: `bind_inputs` takes
  `lit || fogged || shade_mapped` as a single bool, `lighting_read`.
- af515c4, the members by owner. There are three structs in metal_types.hpp, and the class holds one of each:
  - `Switches switches_`: the nine `no_*` flags and `show_target`, plus the other flags initialize() fills once:
    `log_draws` (PURE_METAL_LOG), `to_shell` (PURE_METAL_SHELL with the config) and `sharp` (the config's sharp
    textures).
  - `TraceState trace_`: everything on the brief's list. The report counters went in because only metal_trace.mm
    reads them; `report_start` is still set in initialize. It also holds the trace's own `path`, `has_flip` and
    `shell_seen`, and two members added to get down to 50: `depth_announced` (the depth write-back line's said-once
    flag, beside `depth`) and `started` (the start time that the rows and the exit line's seconds count from).
  - `PrewarmState prewarm_`: `shared` (the old `prewarm_`, which the completion handlers fill), `start_ms`, `used`,
    `waits`, `missed`, `render_seen` and `depth_seen`, plus `path`, `depth_states`, `reported` and `pipelines_out`.

  The class has 50 direct data members (was 90). I left `stats_`, `frames_`, `frame_draws_` and `last_wait_ms_`
  direct because several concerns share them, as the brief says. `trace_.times` and `trace_.file` are read by every
  file through TraceClock. They moved anyway: the brief lists them, and since the struct is a plain aggregate no
  accessor was needed. Initial values, and the points where each member is written and read, are unchanged.
- 25b18f9, docs/metal-backend.md "Files": the table rows name the helpers and the three structs where they describe
  what each file owns, and one sentence after the intro says what task 062 did.

Checks besides Verify:
- `tools/frame_regress.sh`: 18/18, and the table matches the one taken before any change row for row (zone_change
  0.0353 both times). `tools/hud_check.sh --shell headless`: 61 of 61.
- `tools/gerec/metal_check.sh`: PASS. Team: 0/130560 px on both frames. Race: 2/130560 px at tol 24. The bisection
  finds the first differences at draws 508 (race_1x) and 40 (race_warm). The starting commit's build gives exactly
  the same numbers on the same recordings, so the 2 px predate this task. (The 049 review recorded race 0 px.) The
  recordings were copied from the main checkout's out/gerec (made Oct 6), not recorded again.
- Paths the refactor check does not exercise: the race route on the starting build and on af515c4, three ways:
  - (A) PURE_METAL_TRACE, PURE_METAL_PIPELINES_OUT, PURE_TRACE_STENCIL_COPY and PURE_TRACE_DEPTH_READBACK;
  - (B) every NO_* switch, plus PURE_METAL_PIPELINES=0 and PURE_METAL_SHOW_TARGET=0x04000000;
  - (C) PURE_NO_FOG.

  All three gave captures with 0 differing pixels. With times taken out, the `[metal]` lines are the same except
  for the output paths and the GPU wait count, which depends on timing and which refactor_check also drops. That
  includes the 339 stencil-copy lines and the 339 depth write-back lines. The trace's count columns (flip, decoded,
  decoded_kb, stencil_copies, draws, passes, copies) match over 6046 rows, and the key list is the same (29 render,
  22 depth-stencil).

Verify output (last 20 lines), `tools/verify_task.sh 062` at 25b18f9:
```
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

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
hud_check: shell headless, backend metal, 61 shots from flip 6200 to 7700, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a1799f8643cf65947/out/hud/headless
hud_check: run_boot exit 0, frame 7710 reached: yes, 11 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a1799f8643cf65947/out/hud/headless/run.log
6200:H 6225:H 6250:H 6275:H 6300:H 6325:H 6350:H 6375:H 6400:H 6425:H 6450:H 6475:H 6500:H 6525:H 6550:H 6575:H 6600:H 6625:H 6650:H 6675:H 6700:H 6725:H 6750:H 6775:H 6800:H 6825:H 6850:H 6875:H 6900:H 6925:H 6950:H 6975:H 7000:H 7025:H 7050:H 7075:H 7100:H 7125:H 7150:H 7175:H 7200:H 7225:H 7250:H 7275:H 7300:H 7325:H 7350:H 7375:H 7400:H 7425:H 7450:H 7475:H 7500:H 7525:H 7550:H 7575:H 7600:H 7625:H 7650:H 7675:H 7700:H
hud_check: 61 of 61 shots have the HUD
verify 062: PASS
```
In the same run, the refactor check (before 4b0f75f, after 25b18f9) printed "counts: the same in every route (86
[metal] lines)" and "refactor check: PASS, 18/18 scenes with 0 differing pixels, counts PASS (0m 23s)".

Open questions:
1. **`grep -c 'copyFromTexture:' src/gpu/*.mm` totals 2, not 1.** The `toBuffer:` blit now appears once. The
   second match is sample_target's `copyFromTexture:toTexture:` in metal_targets.mm, the copy a draw samples of the
   target it draws into. That is a different blit and was not one of the three.
2. **Two members joined trace_ beyond the brief's lists, to reach 50: `depth_announced_` and `started_`.**
   metal_backend.mm also reads `started_` (the start-up line's compile time and the exit line's seconds), so by the
   brief's rule for shared members it could have stayed direct. That would leave the class at 51. The other
   candidate for the 50th slot was `render_pipelines_` and `depth_states_` in prewarm_: only metal_pipelines.mm
   reads them, and shutdown clears them just as it clears the pre-warm. That would make prewarm_ the whole state
   of the pipelines file, under a name narrower than its contents.
3. **`trace_.stencil_copy` and `trace_.depth` follow the brief, but metal_trace.mm never reads them.** Their readers
   are metal_effects.mm and metal_targets.mm. As PURE_TRACE_* flags that initialize() fills, they would fit in
   switches_ just as well.
4. **snapshot_guest_words still computes a target's extent itself, in 32 bits.** It is not one of the four scans,
   so I left it alone; it could use `Target::bytes()`. Also, `prewarm_.path` is written and never read, as
   `prewarm_path_` was before.

## Review
Verify rerun: from the main checkout after the merge, 2026-10-09: PASS. The refactor check there compared against the
main checkout's before captures, taken 2026-10-07 at d55e70a (task 049's time): 0 differing pixels on 18 scenes and
the same 86 `[metal]` count lines, so the backend's pictures are unchanged across tasks 050 to 062 too. Frame suite
18/18 headless, `--shell metal --backend metal` 18/18 (20 min), `--shell vulkan --backend vulkan` 18/18 (20 min),
`tools/hud_check.sh` 61/61 in the Metal shell and headless.
Spot-read: `copy_to_buffer(texture, buffer, options)` carries the same nine blit arguments the three copies had,
with `MTLBlitOptionNone` where no option was given; `Target::bytes()`/`contains()` reproduce the extent arithmetic
and the three scans keep their selection rules and comments; draw()'s sixteen `[encoder_ set...]` calls are in the
same order before and after the cut (bind_state nine, bind_inputs seven). Lines: the nine files 3204 to 3252 (+48:
the structs and helpers in metal_types.hpp +73, the class -34); draw() 300 to 133; 90 to 50 direct members.
Merged: `git merge --no-ff` into batch/m2, 1589688.
Notes: the `copyFromTexture:` count of 1 in the acceptance line was the brief's slip: the second occurrence is
sample_target's texture-to-texture copy, not one of the three. The race A/B's 2 px predate the task (the same
figure on the starting build and in the Mac A/B of the same morning). Follow-ups, none behavioural:
snapshot_guest_words still computes a target's extent itself (could use `Target::bytes()`); `prewarm_.path` is
written and never read; `trace_.stencil_copy` and `trace_.depth` are read by metal_effects.mm and
metal_targets.mm rather than the trace, so they belong in `switches_`.
