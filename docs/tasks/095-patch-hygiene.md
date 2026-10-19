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
- Verify passed (below); nothing left.
- Workflow: `tools/patches.sh open`, edit in out/patch-series, fixup + `GIT_SEQUENCE_EDITOR=true git rebase -i
  --autosquash <pin>` (or an `edit` stop for a patch the later ones rework), `tools/patches.sh close`, build, commit.

## Result
Status: DONE

Changed:
- tools/patches.sh: `open [DIR]` and `close [DIR]`, documented in its header (item 1).
- patches/: I removed 0025-guest-time-split.patch and left its number unused (item 2). Patches edited in substance:
  0002, 0003, 0004, 0005, 0012, 0019, 0020, 0022, 0023, 0027, 0030. `close` rewrote these with new hunk offsets and
  index lines only: 0007, 0009 (cmake offsets only; its include/psprecomp/ hunk is byte-identical), 0010, 0011, 0013
  to 0018, 0021, 0026, 0028, 0029. patches/README.md: the intro, "Old numbers", the table rows of 0004, 0025 and 0030,
  and the sections of 0002, 0003, 0004, 0005, 0012, 0017, 0019, 0020, 0022, 0023, 0025, 0027 and 0030.
- src/tools/record_backend.cpp and src/tools/ge_record_format.hpp are new: moved out of 0004 into namespace
  pure::gerec. Also src/tools/ge_replay.cpp and CMakeLists.txt (record_backend.cpp joins the sources every platform
  builds). In src/gpu/: metal_backend.hpp, metal_backend.mm, metal_targets.mm and metal_textures.mm. Then
  src/host/metal_shell.mm, and comments only in src/profile/test_hooks.cpp and pure_profile.cpp.
- docs/tasks/095-patch-hygiene.md (Progress, Result).
- Commits: one per item, with item 6 split in two (the texture helpers, then the four small duplicates), plus one
  progress commit. I rebased the branch onto batch/m2 at cfcc3be. That commit merged task 094, which touched tools/
  and docs/ only, none of this task's files.

Lines. Lines the series adds to the vendor tree went from +8249 -1349 (net 6900, batch/m2) to +7327 -1438 (net
5889). The patch files went from 14643 lines to 13883. Each item's share of the series' net:

| Item | Series net | Elsewhere |
|---|---|---|
| 1 open/close | 0 | tools/patches.sh +123 -15 |
| 2 0025 dropped | -118 | |
| 3 record backend to src/tools | -838 | +841 in src/tools/ (the same code, plus the internal scale forwards) |
| 4 0004's interfaces trimmed | -73 | src: the name() overrides, the Metal shell's overrides |
| 5 read-back once | -21 | |
| 6 texture helpers | +28 | metal_textures.mm +15 -65 |
| 6 four small duplicates | +8 | metal_shell.mm's own parser, -9 |
| 7 stale notes | +3 | |

Items 4 to 6 grow some patch files even though the tree shrinks. Removing an upstream copy adds `-` lines to a patch:
the renderer's write_bmp, read_back_framebuffer's drain, create_writeback's memory pick and the decoder's palette
tests.

What each item did:
1. `tools/patches.sh open` puts the series on branch `patch-series` in a worktree of vendor/PIN (default
   out/patch-series), one commit per patch, each subject the patch's name. It refuses to start unless `check` passes.
   `close` writes each commit back to patches/<subject>.patch and removes the file of any patch whose commit is gone.
   It then brings vendor/portablekit to the branch's tree, writing only files whose bytes or mode differ, runs `check`,
   and removes the worktree and branch. include/psprecomp/ kept its time stamp through every close here. `close`
   refuses a dirty worktree, a rebase in progress, a branch not based on vendor/PIN, merge commits, empty commits, and
   misnamed or out-of-order subjects. A round trip with no edits rewrites nothing except the index lines of 0022 and
   0023, whose postimage hashes named a tree the series never produced (fixed in the 0025 commit). Example:
   ```
   tools/patches.sh open
   cd out/patch-series && <edit> && git commit -a --fixup="$(git log -1 --format=%H --grep=^0004-)"
   GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$(cat ../../vendor/PIN)"
   cd ../.. && tools/patches.sh close
   ```
   To drop a patch: `git rebase --onto C^ C`. Where later patches rework the same lines (0003, 0012 and 0023 here), an
   `edit` stop on the patch plus an amend works better than a fixup made at the tip. Conflicts in later patches
   resolve as in any rebase.
2. 0025 is gone, and with it the timer in `HleRegistrar::bind`. Its README row says it was removed, and why.
3. src/tools/record_backend.cpp registers `record` through `BackendRegistration`, as the Metal backend registers
   itself, and is built on every platform. It forwards `supports_internal_scale`, `set_internal_scale` and
   `target_size` to the backend it wraps. `PURE_GE_BACKEND=record` and the .gerec format are unchanged: replay_check
   made five new recordings through it here (race, race_warm, frontend, title and metal_check's team), and
   gerec_dump.py accepted them.
4. The 0004 interfaces lost these members:
   - `Shell::shutdown`, `shutdown_ui`, `mouse_captured`, `quit_requested` and `request_quit`. None is called through
     `Shell*`. The Metal shell keeps its own `shutdown` and `shutdown_ui`, which its destructor calls.
   - `GeBackend::name()`, which nothing called.
   - The two registries, now one template, `Registry<T>` in host/registry.hpp.
   - `encode_bmp`, `write_bmp_file` and the renderer's `write_bmp`, now one `gpu::write_bmp` in ge_backend.cpp,
     because the null backend has no renderer.
   - `PresentedImage::address` and `::view`. The Vulkan backend also no longer fills `image`; Metal still does.
5. Three helpers in 0003:
   - `Impl::drain_recording`: the submit, wait and resume that read_back_framebuffer and the synchronous depth
     write-back each ran, line for line. The calls are the same and in the same order, so the GPU waits on exactly
     what it waited on before.
   - `Impl::host_read_memory`: the frame write-back, the depth write-back and 0023's capture pick their memory type
     with it, each keeping its old order and fallback.
   - `invalidate_writeback(memory, coherent)`, which 0022's two inlined invalidates now call.
6. The small duplicates, each written once:
   - The menu uses `using Tab = MenuTab`, with no casts and no static_assert.
   - The kernel alone keeps the vblank period. Frame pacing reads it through `pacing::set_vblank_period_source()`,
     set once where the HLE makes the shell, and the uncalled `pacing::vblank_period_us()` is gone.
   - `host::window_size_switch()` parses PURE_WINDOW_SIZE for both the Vulkan renderer and the Metal shell.
   - 0005's NO_RENDER test is a static.
   - texture_decode.hpp exports `bits_per_texel`, `indexed`, `texture_bytes`, `texture_level`, `sampled_level_count`,
     `mip_level_problem` and `ge_log16`. The Vulkan renderer, the decoder and metal_textures.mm use them. The record
     backend keeps its own byte count, renamed `recorded_texture_bytes`, because it takes the wider of buffer width
     and width.
7. The stale notes:
   - ge_state.hpp's notes on what the Vulkan renderer ignores are gone (0002).
   - `texture_params.x` is described once, above `PushConstants` (0020); ge.vert and ge.frag point there.
   - 0022's "patch 0021" and ge.frag's ge_log16 pointer (0012) are fixed.
   - test_hooks.cpp's "patch 0020" now reads 0009-vfpu-rounding, and pure_profile.cpp's "patch 0011" reads
     0005-kernel-host-waits-and-pacing.
   - Every other "patch 00NN" left in the vendor correctly names the patch it sits in.

The rig, whose vendor tree holds the old series: after the pull, `tools/patches.sh check` fails. Step 1 of
docs/windows.md "Bringing the rig up to date" fixes it: `tools/patches.sh check || tools/vendor_setup.sh`, then
`tools/patches.sh check` (29 patches now). vendor_setup re-applies every patch, so
include/psprecomp/allegrex_context.hpp is rewritten with the same bytes and the corpus recompiles, from ccache where
the cache has it. `open` and `close` cannot do this step, because `open` refuses a tree that is not the current series.
Then run `tools/build.sh profile`. CMakeLists.txt gained a source, and the reconfigure is automatic.

Window checks owed (none run here):
- Mac:
  - `tools/frame_regress.sh --shell vulkan --backend vulkan` and `--shell metal`.
  - `tools/stutter_check.sh --shell vulkan`.
  - `tools/menu_check.sh`, both shells (Menu::Tab).
  - `tools/aspect_check.sh`, both shells (the shared PURE_WINDOW_SIZE parse).
  - `tools/display_rate_check.sh --audio`, both shells (the vblank period now read from the kernel).
- The rig (Windows behaviour of item 5):
  - Its window suite (captures through `host_read_memory` and `write_bmp`).
  - `tools/stutter_check.sh` (0022's frame-late path).
  - `tools/menu_check.sh --shell vulkan`.
  - One race run with `--env PURE_SYNC_READBACK=1`: the synchronous depth path now goes through `drain_recording`,
    and its start-up line says `synchronous`.

Verify output (last 20 lines). For one game at a time I ran Verify in two halves, waiting for no PureNative before
each. These are each step's verdict lines and texture_check's tail:
```
ok: 29 patch(es) reproduce vendor/portablekit at 8b0c3fe
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 23s)
counts: the same in every route (86 [metal] lines)
refactor check: PASS, 18/18 scenes with 0 differing pixels, counts PASS (0m 23s)
[replay] frame 1750: 28 draws, 94 records, 29.9 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
[replay] frame 1751: 28 draws, 77 records, 6.5 ms, diff 0.000000 (tol 0, 0/522240 px at 960x544) PASS
replay_check: PASS (483 s)
metal_check: PASS (390 s)
scene            size  reduced  limit  tol     vs 0  energy 0  energy 1   ratio  HUD  result
race_hud    1920x1088   0.0467    0.1   32   0.0218    3.5752    4.0681  1.1378  yes  PASS
tt_hud      1920x1088   0.0473   0.12   32   0.0244    3.5424    4.3499  1.2279  yes  PASS
fp_hud      1920x1088   0.0472   0.11   32   0.0244    3.5210    4.3300  1.2298  yes  PASS
zone_hud    1920x1088   0.0346   0.09   32        -         -         -       -    -  PASS
race_hud run with 1 (exit line, over the run): 192857 mipmapped draws, 192778 enhanced (at least 10000): PASS
race_hud at scale 1 with 1, against the reference: 0.0162 (limit 0.1, tol 32): PASS
texture check, shell headless: 4/4 scenes pass, the enhanced draws PASS, race_hud at scale 1 PASS (0m 40s)
texture_check: PASS
```

Open questions:
- Verify ran on batch/m2 with task 094's fixed tools, because the branch is rebased onto cfcc3be. Neither known defect
  applied: refactor_check's counts passed as they stand, and replay_check and metal_check give each replay a data
  directory of its own. No PURE_DATA_DIR workaround was needed. I captured the refactor_check baseline on batch/m2's
  own build.
- One behaviour moved on purpose with item 6: frame pacing now sees a change of the kernel's vblank period at once
  instead of at the next flip. So while the game is paused behind the menu, the Frame rate row follows a Display rate
  change at once. Nothing moves at the default period.
- Left in place:
  - The two "patch 0021" (old numbering, now 0009) in include/psprecomp/allegrex_context.hpp, which this task must
    not touch.
  - src/ comments with old numbers outside the two the brief named, all now 0003 (0004's stencil part is 0002/0003):
    metal_effects.mm "patch 0006" (3 times), metal_backend.mm:13 "patch 0006", metal_targets.mm:252 "patch 0008",
    src/gpu/shaders/ge.metal:11 "patch 0005", ge.metal:434 "patch 0004" and ge.metal:531 "patch 0006".
  - ge.metal:312's "ge_log16 in metal_textures.mm" (now pk::ge_log16, texture_decode.hpp).
- Doc lines owed (the planning session applies them):
  - docs/developing.md:165: the PURE_TRACE_GUEST row goes. Its tools table: patches.sh gains `open` and `close`.
  - docs/vendor-map.md:33: 0025 is removed. Add entries for host/registry.hpp, texture_decode.hpp's exports,
    `pacing::set_vblank_period_source`, `host::window_size_switch` and `gpu::write_bmp`.
  - docs/status.md:46 and docs/windows.md:81: "30 patches" is now 29.
  - docs/ge-backend.md:67, 112, 115 and 129: the record backend and format are in src/tools/; the registry is a
    template; PresentedImage has no address or view. Line 315: Shell's lifecycle row loses shutdown and the
    interface row loses shutdown_ui.
  - docs/metal-backend.md:301: `gpu::write_bmp`.
  - docs/upstream.md: 0004's row and section (no record backend; its dependency on 0002 was the record format's),
    0025, and 0030's "passed on at each flip".
  - tools/gerec/gerec_dump.py:13 and :25: the format's reference is src/tools/ge_record_format.hpp.
  - CLAUDE.md "Hard rules" could name `tools/patches.sh open` and `close` beside `export` for a change inside the
    series.

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
