# 093: The src leftovers (scaffolding, a probe, duplicate helpers)

Milestone: cleanup (audit 2026-10-19) | Branch: task/093-src-leftovers | Status: OPEN

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
