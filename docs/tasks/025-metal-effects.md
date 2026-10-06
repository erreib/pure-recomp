# 025: The Metal GE backend, effects: stencil as alpha, the bloom chain, read-backs and write-backs

Milestone: M6 | Branch: task/025-metal-effects | Status: OPEN (after task 024)

## Goal
After tasks 023 and 024 the Metal backend draws the race's geometry lit and fogged but without the effects the
Vulkan path gained in patches 0003 to 0008: the stencil kept as alpha (the bloom's mask and the shadow volumes),
the bloom chain's render-to-texture passes over aliased VRAM, the block transfers and read-backs into guest memory,
the frame write-back and the depth write-back the lens flare reads at a GE SIGNAL. This task adds them, so that the
race frame matches the Vulkan backend through ge_replay and PPSSPP through the frame regression suite, which then
passes 5/5 with `--backend metal`.

## Read first
- CLAUDE.md, docs/metal-backend.md (all; "What is not done yet" lists this task's items and how the stencil fields are
  already carried in the pipeline key), docs/ge-effects.md (the bloom chain's addresses and passes, the lens flare's
  4x4 depth read, the shadow volumes), docs/ge-backend.md sections 1, 2 (the render-target model and the alpha copy
  rule), 7 (ge_replay)
- patches/0003 (framebuffer-as-texture lookup), 0004 (stencil ops as alpha writes), 0006 (real stencil attachment,
  dual-source blending for REPLACE under source-alpha blends, the alpha copy rule), 0008 (depth write-back at SIGNAL):
  the behaviour the Vulkan backend has and this backend must share, and the README rows that say why
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `submit` (the stencil state translation, the alpha copy, the
  dual-source path), `read_back_framebuffer`, `write_back_frame`, `write_back_depth`, `find_framebuffer_texture`
- vendor/portablekit/host/hle/hle_media.cpp: `block_transfer` (the backend's part before the HLE copies rows),
  `write_back_depth_for_signal`
- src/gpu/metal_backend.mm, metal_shaders.h as task 024 left them; tools/gerec/metal_check.sh (task 024)
- tools/frame_regress.sh (`--backend metal`), docs/verification.md, ref/README.md (the PPSSPP race reference)

## Deliverable
1. Stencil: the `Depth32Float_Stencil8` attachment's test and operations from `StencilState` (the fields the
   pipeline key already carries), with the reference and masks; the alpha channel of the colour target kept as the
   PSP's stencil copy by the rule of patch 0006 (alpha is what sampling, blending, display and write-back read; it is
   written from the stencil ops where alpha can express them and resolved from the attachment where it cannot, before
   a destination-alpha read and at the end of the pass). REPLACE under a source-alpha blend through dual-source
   blending (Metal: a second colour output with `[[color(0), index(1)]]` and the `Source1` blend factors) as patch
   0006 does. Shadow volumes (zfail INCR/DECR, test GREATER) draw.
2. The bloom chain (docs/ge-effects.md): the depth bytes at 0x04110000 as a 256-stride colour target, the scene
   target sampled as a texture into it, 0x04132000 inside it as the blur target, the add back. Everything needed is
   the render-target model of section 2 and the framebuffer-as-texture rule already in the backend; make the aliasing
   cases work (a texture bind inside a target of another stride or format, a target made over memory another target
   covers) as the Vulkan backend does, and no better.
3. `block_transfer`: when the source lies in a target the backend drew, write that target's pixels (the rows the
   copy will read) into guest memory first, in the target's guest format, as `read_back_framebuffer` does for one
   target; `read_back_framebuffer(address)`: the target at the address into guest VRAM. `write_back_frame`: the
   displayed target into guest VRAM once a flip, in the guest's format. All three synchronous (a blit to a shared
   buffer and a wait), counted, with the wait time in the stats.
4. `write_back_depth(color, depth, stride, memory, why)`: the depth of the target at `color` as 16-bit PSP z
   (`round(z x 65535)`) into guest memory at `depth` in rows of `stride`, synchronous, returning whether it wrote;
   the lens flare then occludes as in Vulkan (patch 0008; `PURE_NO_DEPTH_READBACK` is the framework's switch).
5. Whatever `--first-diff` against Vulkan on `race_warm.gerec` frames 6014-6016 still turns up after items 1 to 4,
   fixed if it is this backend's, recorded if it is a Vulkan difference against the GE's documented rule (do not
   match a Vulkan bug; report both pictures).
6. `tools/gerec/metal_check.sh`: its race check (task 024 records `race_1x.gerec`, the race at internal scale 1, and
   bisects frame 6016 against Vulkan) becomes a pass condition: `--a vulkan --b metal --frames 6016 --tol 24
   --max-frac 0.02` on `race_1x.gerec` (both backends at 480x272, so no resize edges), with the first differing draw
   printed when it fails. Task 024's bisection tools (cutting a recording after draw N and diffing both pictures)
   were scratch files; add `--cut N` to ge_replay (`src/tools/ge_replay.cpp`: replay the frame's records up to and
   including its Nth Draw, then present and capture, with `--out`) so the same is done in-tree.
7. docs/metal-backend.md: the stencil and alpha rule, the bloom chain, the read-backs and write-backs, the numbers
   (race frames against Vulkan and PPSSPP, the wait time a frame), "What is not done yet" reduced to the Metal shell
   (027) and the enhancements. README.md if a switch is added.

## Acceptance criteria
- [ ] `tools/frame_regress.sh --backend metal` passes 5/5: race_hud at or under the suite's limit (0.10 at tol 32)
      with bloom, shadows and the lens flare's occlusion in; the four frontend scenes keep tasks 023/024's fractions.
- [ ] `race_1x.gerec` frame 6016 replayed into vulkan and metal passes at tol 24, max-frac 0.02 (both at 480x272).
- [ ] `tools/frame_regress.sh` (Vulkan) still passes 5/5 unchanged.
- [ ] A race route runs to its end on Metal (`PURE_GE_BACKEND=metal` with `main_menu.txt` + `single_race.txt` to
      frame 6046, as task 023 did) with no Metal validation error and no `[metal] ... not implemented` line.

## Verify
`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal`

## May touch
- src/gpu/, tools/gerec/metal_check.sh, src/tools/ge_replay.cpp (the `--cut` option only), docs/metal-backend.md
  (and docs/ge-backend.md section 7 for `--cut`), README.md

## Must not touch
- vendor/, patches/, src/profile/, src/hle/, src/host/, src/tools/ apart from `--cut`, tools/frame_regress.sh,
  tools/gerec/replay_check.sh, config/, ref/, CMakeLists.txt

## Estimated turns
80

## Escalate when
A GE behaviour the race needs cannot be expressed with Metal's stencil, blending or framebuffer fetch (say which draw
and state), the lens-flare depth read needs a hook outside the backend (it should not: `write_back_depth` is called
by the HLE at the SIGNAL), or ge_replay or the recording lacks something beyond `--cut` (report it). If
race_hud stays above 0.10 after items 1 to 5 for a reason outside this backend (an AI-grid difference between the
capture and the reference, as docs/verification.md notes for Vulkan's 0.063 to 0.086), report the number and the
cause and stop with PARTIAL.

## Result
**Status: DONE.** All seven deliverables are in and the four acceptance criteria hold:
- `tools/frame_regress.sh --backend metal` passes 5/5: lang 0.0002, title 0.0002, profile 0.0000, main_menu 0.0106
  (tasks 023/024's fractions) and race_hud 0.0379 at tol 32 (limit 0.10; task 024 0.2978, Vulkan 0.067), with
  shadows, bloom and the flare's occlusion in.
- `race_1x.gerec` frame 6016, vulkan against metal at 480x272: 0.000015 at tol 24 (2 of 130560 pixels), PASS at
  max-frac 0.02. Frames 6008-6016 are all within 2 pixels.
- `tools/frame_regress.sh` (Vulkan) passes 5/5 at 0.0544, 0.0302, 0.0543, 0.0331, 0.0673. The four frontend
  captures are pixel-identical to the main checkout's run of 07:54.
- The race route (`main_menu.txt` + `single_race.txt`, empty stick) runs to frame 6046 on Metal with
  `MTL_DEBUG_LAYER=1`. The log shows "Metal API Validation Enabled", no validation error and no
  `[metal] ... not implemented` line.

**What was built** (src/gpu/metal_backend.mm, metal_shaders.h):
1. Stencil. The `Depth32Float_Stencil8` attachment now does the GE's test and operations: function, sfail, zfail
   and zpass (INCR/DECR clamp), compare mask and write mask (~0xE9). The reference is set per draw with
   `setStencilReferenceValue`, as the target's alpha holds it. A clear of the alpha REPLACEs the stencil.
   - The alpha follows patch 0006's rule: zpass REPLACE/ZERO is written by the fragment, and dual-source blending
     (`ge_fragment_dual`, `[[color(0), index(1)]]`, `Source1Alpha`) covers source-alpha blends.
   - The stencil is copied into the alpha (`resolve_stencil_alpha`: 9 quads inside the pass, stencil EQUAL per bit)
     before a destination-alpha read and at every end of a pass. That is one copy per race frame (339 over the
     route), as Vulkan does.
   - The shadow volumes and the GREATER-4 darkening quad now darken only the shadows.
2. Bloom chain. It needed no new mechanism: section 2's targets and patch 0003's exact-address rule resolve all
   six binds. The downsample reads the back buffer's alpha, which is now the stencil mask. The doc has a table of
   the binds.
3. and 4. Guest memory. `block_transfer` stores the source target's rows that the copy reads. `read_back_framebuffer`
   stores a whole screen-wide target. `write_back_frame` stores the picture shown at the previous flip, as the
   Vulkan backend does: it reuses the Vulkan shell's read-back, or else waits for a copy recorded at the flip.
   `write_back_depth` stores round(z x 65535). Each one is a blit, a wait and a store in the target's format, and
   re-takes the target's guest-word snapshot. All are counted with their wait time (exit line
   `[metal] stencil: ...`). The depth write-back costs 0.6 to 0.8 ms per race frame. On the drive to frame 6690 (sun
   behind the pillar), the area around the sun reads 111.2 in Metal and 111.6 in Vulkan (no flare; task 019 measured
   105.2 with the write-back and 176.5 without).
5. Remaining differences on race_1x 6016 (frame 6016's first diff at tol 24 is draw 508). There are three:
   - Column 0, rows 244-263, 5-11 levels. This is a Vulkan difference against the GE's rule. The HUD is drawn with a
     GE viewport shifted one pixel (offset 2048-1807). The Vulkan backend makes that its `VkViewport` and clips
     column 0 away, but the GE clips x/y only at the scissor. Metal draws column 0 and I did not match Vulkan here.
     `--cut 837 --out DIR` gives both pictures.
   - Three crowd pixels, 20-36 levels. These are alpha-test (GREATER 0x7F) threshold rounding on bilinear texels,
     so neither backend is wrong.
   - The rest is within 4 levels.
   - race_warm at 2x against 1x: 0.0777-0.0804 at tol 24. These are all reduction edges (first diff at draw 40, an
     alpha-test edge).
6. `ge_replay --cut N` replays the last frame up to and including its Nth draw, then flips, captures and compares
   it. `--first-diff` on a cut frame bisects within N. `metal_check.sh` step 3 is now the race pass condition at
   tol 24 / max-frac 0.02. When it fails, it prints the first differing draw and keeps both pictures via `--cut`.
   Step 4 is task 024's bisections, kept for the record.
7. docs/metal-backend.md covers the stencil and alpha, the bloom chain, guest memory, the race check, the flare,
   costs and verify numbers. "What is not done yet" is reduced to 027's leftovers and enhancements. Also updated:
   docs/ge-backend.md section 7 (`--cut`) and README.md.

Beyond the brief: `tools/frame_regress.sh --shell metal --backend metal` (no Vulkan at all, M6's exit check)
passes 5/5 with the same five fractions in 7m 10s. Under the Metal shell the race runs at 60 fps and waits for the
GPU only at its SIGNAL (353 waits in 6046 frames).

Changed:
- `src/gpu/metal_backend.mm`: the stencil state, the alpha rule with dual source and the copy, block transfers,
  read-backs, frame and depth write-backs, stats
- `src/gpu/metal_shaders.h`: `FragmentUniforms::stencil`, `shade()`, `ge_fragment` storing the stencil value,
  `ge_fragment_dual`
- `src/tools/ge_replay.cpp`: `--cut N` only
- `tools/gerec/metal_check.sh`: step 3 (race pass condition, `--first-diff` plus `--cut` on failure); step 4 for
  the record
- `docs/metal-backend.md`, `docs/ge-backend.md` (section 7: `--cut`), `README.md` (src/gpu row, ge_replay row,
  metal_check row, `PURE_TRACE_STENCIL_COPY`/`PURE_TRACE_DEPTH_READBACK` rows, `PURE_GE_BACKEND` row)
- `docs/tasks/025-metal-effects.md`: this Result

Verify output (last 20 lines):
```
metal_check: PASS (5 s)
frame regression 2026-10-06 08:19, commit 6aeb14e, backend metal (PURE_GE_BACKEND: recorded, not enforced), shell vulkan (PURE_SHELL)
extra environment: none
run frontend: 2130 flips ...
run frontend: run_boot exit 0, frame 2130 reached: yes, 73 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aef6c74b9de737ac2/out/regress/frontend.log
run main_menu: 4730 flips ...
run main_menu: run_boot exit 0, frame 4730 reached: yes, 159 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aef6c74b9de737ac2/out/regress/main_menu.log
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 199 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aef6c74b9de737ac2/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
lang          690    0.0002   0.07   24     0.054  -0.054  PASS
title        1750    0.0002   0.05   24     0.030  -0.030  PASS
profile      2100    0.0000   0.07   24     0.054  -0.054  PASS
main_menu    4700    0.0106   0.05   24     0.033  -0.022  PASS
race_hud     6016    0.0379   0.10   32     0.067  -0.029  PASS

moved more than 0.03 from the measured value: lang profile (something changed; docs/verification.md)
frame regression: PASS, 5/5 scenes pass (7m 12s)
verify 025: PASS
```

Open questions:
1. The Vulkan backend loses column 0 and row 0 of transformed draws whose GE viewport does not start at the
   target's corner. Here that is the race HUD (offset 1807/1911, against the world's 1808/1912). Fixing it is a
   vendor change: put the viewport into clip space and give the `VkViewport` the whole target, as Metal does.
   Should that be a follow-up patch? It would move Vulkan's race_hud slightly.
2. No recording exercises a block transfer or `read_back_framebuffer` from a target. The race's 570-606 transfers per
   route come from main memory, and the frontend only writes back the frame. So the 16-bit store formats and the
   transfer row range follow the rules and Vulkan's code but are unchecked. A scene that copies a rendered target,
   if the game has one, would need a recording.
3. The main checkout's `race_1x.gerec` (recorded 2026-10-06 07:53, 864 draws in frame 6016) differs from the one in
   task 024's numbers (906 draws: the AI field varies). Draw numbers in docs/metal-backend.md for task 024 refer to
   the old file. Task 025's refer to the new one.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
