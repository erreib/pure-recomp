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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
