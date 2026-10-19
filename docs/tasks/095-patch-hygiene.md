# 095: Patch hygiene (a series workflow, our tool out of the vendor, duplicates and stale notes)

Milestone: cleanup (audit 2026-10-19) | Branch: task/095-patch-hygiene | Status: OPEN

## Goal
The vendor patches carry only framework changes, each written once, with comments that say what is true. The audit
(docs/history/audit-2026-10-19.md, "Patches") found our recording tool inside patch 0004-ge-backend-and-shell-seams,
read-back code written three ways across three patches, an unused patch, unused interface methods and stale notes.
Editing a patch in the middle of the series needs a workflow patches.sh lacks (it only appends); build it first, since
the later re-pin onto upstream needs it too. Leave alone what upstream PR #44 is likely to replace: 0029's three
`file_url` copies, and 0002/0003's stencil and 0007's save list beyond the duplicates named here.

## Read first (about 30K tokens)
- docs/history/audit-2026-10-19.md, "Patches" and "Upstream".
- tools/patches.sh (whole; short) and tools/vendor_setup.sh; patches/README.md's rows for 0003, 0004, 0005, 0016,
  0019, 0022, 0023, 0025, 0030.
- The vendor files as you reach them; the audit's locations are in "Deliverable".

## Deliverable
1. **A series workflow in tools/patches.sh** (two new subcommands, names yours): materialise the series as one
   commit per patch on a branch in a scratch worktree of vendor/PIN; after edits (fixup commits squashed without an
   interactive editor, e.g. `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash`), write each commit back to its own
   patches/NNNN-slug.patch and bring vendor/portablekit to the result. `tools/patches.sh check` passes afterwards.
   Document both in the script's header. Every later item edits its patch through this workflow.
2. **Drop 0025-guest-time-split** (nothing uses `PURE_TRACE_GUEST`): remove the patch file (leave the number gap) and
   its hook; patches/README.md's row says removed, and why.
3. **The recording tool leaves the vendor.** host/gpu/record_backend.cpp and host/gpu/ge_record_format.hpp move out
   of 0004 into src/ (their users are ours: src/tools/ge_replay.cpp and `PURE_GE_BACKEND=record` in tools/gerec/),
   registered through `BackendRegistration` as the Metal backend registers itself. It must still build on every
   platform it builds on now (src/gpu/ is Mac-only: put it where CMakeLists.txt builds it everywhere). While moving
   it, forward 0017-internal-scale-by-backend's `supports_internal_scale`, `set_internal_scale` and `target_size`
   (the Resolution row disappears under it today). `PURE_GE_BACKEND=record` and the .gerec format stay as they are.
4. **0004's interfaces trimmed**: the `Shell` methods never called through `Shell*` (`shutdown`, `shutdown_ui`,
   `mouse_captured`, `quit_requested`, `request_quit`: check each again), `GeBackend::name()` if still uncalled, the
   two registries as one template, `encode_bmp`/`write_bmp_file` replaced by the renderer's BMP writer or one shared
   one, fields written and never read (`PresentedImage::address`, `::view`, the Vulkan `image`). Keep any member a
   shell or backend in src/ still needs.
5. **The read-back code once** (0003, 0022, 0023): one drain helper for the `SYNC_READBACK` path
   (vulkan_renderer.cpp about 7343-7374 and 7563-7589), one function that creates a host-cached staging buffer (four
   idioms today: about 4680, 7400, 3629-3640), `invalidate_writeback()` used where 0022 inlines it. Behaviour
   unchanged, including Windows: the rig re-checks it (list what it must run).
6. **Small duplicates**: `MenuTab` and `Menu::Tab` as one type (an alias), the vblank period stored once (0030; drop
   the uncalled `gpu::pacing::vblank_period_us()`), the `WINDOW_SIZE` "WxH" parse exported once from the vendor and
   used by src/host/metal_shell.mm, 0005's `env("NO_RENDER")` read once (static) rather than on every pacing call,
   and the texture helpers the Metal backend copies (`texture_bytes`, `texture_level`, `ge_log16`, `texture_bits`,
   the `indexed` test and mip checks in src/gpu/metal_textures.mm, which match file-local copies in
   vulkan_renderer.cpp and texture_decode.cpp) exported once from texture_decode.hpp and used by both.
7. **Stale notes**: ge_state.hpp's lines saying the Vulkan renderer ignores mips, map modes, the colour test, dither
   and clip; "patch 00NN" mentions in the vendor that name the wrong patch or an old number (make each one
   NNNN-slug, or drop the number where the comment stands without it); the `texture_params.x` bit layout described
   once and right (vulkan_renderer.cpp:136, ge.frag:61, ge.vert:183 disagree); in src/, test_hooks.cpp:316 and
   pure_profile.cpp:62's old patch numbers.
8. **Docs: patches/README.md only** (its rows for the patches you change). List any other doc line owed in the
   Result; the planning session applies them.

## Acceptance criteria
- [ ] `tools/patches.sh check` ok; `tools/vendor_setup.sh` on a clean clone reproduces the tree (or the series
      workflow's own proof).
- [ ] Every picture check unchanged (Verify).
- [ ] The Result: lines removed from patches/ per item, the patches changed, the new subcommands with an example,
      how a machine with the old vendor tree (the rig) brings its tree to the new series, and the window checks owed.
- [ ] Nothing in vendor/portablekit/include/psprecomp/ changes (the corpus must not rebuild); no generated/ change.

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && tools/refactor_check.sh && tools/gerec/replay_check.sh && tools/gerec/metal_check.sh && tools/texture_check.sh`

## Window checks (not run by the worker; listed for the planning session's screen batch)
`tools/frame_regress.sh --shell vulkan --backend vulkan`, `tools/frame_regress.sh --shell metal`,
`tools/stutter_check.sh --shell vulkan`, `tools/menu_check.sh` (both shells), `tools/aspect_check.sh` (both shells),
`tools/display_rate_check.sh --audio` (both shells). The rig: its window suite, `tools/stutter_check.sh`, and
`tools/menu_check.sh --shell vulkan`.

## Running beside other work
Task 094 (tools/) may be running games in its worktree. One game at a time: before each check wait until no
PureNative runs (`pgrep -x PureNative`, a bounded wait of 30 minutes, checking every 30 s); if a check refuses because
another game started, wait and rerun it.

## May touch
- vendor/portablekit/ (outside include/psprecomp/) through the patch workflow, patches/ (the patches named above and
  README.md), tools/patches.sh, src/ (the record backend's new home, metal_textures.mm, metal_shell.mm,
  test_hooks.cpp and pure_profile.cpp's comments), CMakeLists.txt, docs/tasks/095-patch-hygiene.md

## Must not touch
- vendor/portablekit/include/psprecomp/, generated/, tools/ other than patches.sh, docs/ other than this file,
  config/, game/ (above all game/ms0), disc/, ref/; tools/regen.sh, tools/build.sh all; no window run; 0029's
  file_url copies

## Estimated turns
80

## Escalate when
- An item needs include/psprecomp/ or a corpus rebuild.
- A picture check changes and the cause is not this task's mistake.
- The read-back merge would change what the GPU waits for (keep the copies and report).

## Progress
(worker, kept current at each commit; a later session resumes from here)
- Done: 1 (`tools/patches.sh open` / `close`), 2 (0025 dropped), 3 (record backend in src/tools/), 4 (0004 trimmed),
  5 (read-back once: `drain_recording`, `host_read_memory`, `invalidate_writeback(memory, coherent)` in 0003).
  6, texture helpers (texture_decode.hpp exports, used by vulkan_renderer.cpp and metal_textures.mm).
  6's rest (MenuTab alias, vblank period kept by the kernel alone, WINDOW_SIZE parse once, NO_RENDER static).
  7 (ge_state.hpp notes, 0022's "patch 0021", texture_params.x described once, ge.frag's ge_log16 pointer,
  test_hooks.cpp and pure_profile.cpp numbers).
- Left: Verify, Result.
- Workflow: `tools/patches.sh open`, edit in out/patch-series, fixup + `GIT_SEQUENCE_EDITOR=true git rebase -i
  --autosquash <pin>` (or an `edit` stop for a patch the later ones rework), `tools/patches.sh close`, build, commit.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
