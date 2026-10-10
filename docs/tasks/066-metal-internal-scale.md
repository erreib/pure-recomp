# 066: The Metal backend draws at an internal scale (E3, step 2)

Milestone: E3 (D-015) | Branch: task/066-metal-internal-scale | Status: OPEN

## Goal
The Metal backend draws every target at 480x272 (D-002). After this task it draws at an internal scale S (1 to 6)
on D-015's rules: display-class targets at 480S x 272S, narrower targets (billboards, the bloom buffers) at 1x, the
GE's coordinates scaled, guest memory fed the centre pixel of each S x S block, and S = 1 pixel-identical to today.
The setting is `video.internal_scale` (`PURE_INTERNAL_SCALE`: 0 Auto, 1..6), read at start; Auto follows the
shell's drawable height (the smallest S with 272S >= the drawable's height, at most 6; headless: 1). The menu row
comes in task 067; this task is the backend.

## Read first
- CLAUDE.md, docs/decisions.md (D-002, D-015), docs/metal-backend.md (all of "How a draw is drawn", "Targets",
  "Textures", "The stencil and the alpha", "The bloom chain", "Guest memory", "Frames, captures and the window"),
  docs/ge-effects.md (the frame's targets: which are 512-stride, 256-stride, 128-stride)
- src/gpu/metal_types.hpp (`kWidth`, `kHeight`, `kPictureBytes`, `Target`), metal_targets.mm (every `kWidth`/`kHeight`
  use: 24), metal_draw.mm (the viewport, scissor, through-mode positions, `fold_viewport`, the texture placement
  `uv_remap`), metal_backend.mm (initialize: `BackendConfig::internal_scale`; present_image; capture_frame;
  read_back; the frame write-back), metal_effects.mm (the stencil copy quad), src/gpu/shaders/ge.metal
- vendor/portablekit/host/gpu/ge_backend.hpp (`BackendConfig`, `PresentedImage` "a multiple of 480x272 at the
  internal scale"), the Vulkan renderer's `wanted_target_extent` / `follow_window` for the Auto rule's shape (read
  only), vendor/portablekit/host/settings/settings.cpp (`video.internal_scale`, `parse_scale`)
- tools/refactor_check.sh, tools/frame_regress.sh, tools/imgdiff.py (`--tol`, resizing), tools/gerec/metal_check.sh

## Deliverable
1. **The scale.** `MetalGeBackend` holds `scale_` (1..6) from `BackendConfig::internal_scale` (0: Auto as above,
   using the shell's drawable size when there is a shell, 1 headless). Targets: a `TargetKey` whose stride is at
   least 480 makes a 480S x 272S colour and depth-stencil texture; a narrower key makes 480x272 as today. Each
   `Target` knows its own `width()`/`height()` (and the constants `kWidth`/`kHeight` stay the guest's 480x272).
2. **Coordinates.** For a draw into a scaled target: the viewport and scissor x S; through-mode positions x S (in the
   vertex path, not the vertices themselves: a uniform); `fold_viewport`'s screen mapping x S; the depth clamp's
   screen z unchanged; a target sampled as a texture places its sub-rectangle in the sampled target's own size
   (`uv_remap` is relative, so the scaled target and the 1x target each divide by their own size); the stencil copy
   quad and the 16-bit-target blend read at the target's size. A 1x target sampled by a scaled draw (the bloom
   composite reading the 256-stride buffer into the display) and a scaled target sampled by a 1x draw (the bloom
   downsample reading the display into the 256-stride buffer) both go through the same placement: the sampler's
   bilinear does the rest. Dithering stays per drawn pixel.
3. **Guest memory.** `write_back_frame`, `read_back_framebuffer`, `store_target`/`store_pixels` and `store_depth`
   feed the guest the centre pixel of each S x S block (x*S + S/2, y*S + S/2) of a scaled target; a 1x target as
   today. `block_transfer` into a scaled target writes each guest pixel as an S x S block (or: invalidates the target
   as it does today where it does; say which).
4. **Frames.** `present_image` reports the display target's own size; `capture_frame` writes the target's size (the
   suite resizes; a headless run is at S = 1 unless `PURE_INTERNAL_SCALE` says otherwise); `read_back` (the picture
   for the Vulkan shell and the write-back) at the target's size, with the write-back path downsampling as in 3.
5. **The trace and counts** (metal_trace.mm) print the scale once at start (`[metal] internal scale S: targets
   1920x1088, effects 480x272`).
6. docs/metal-backend.md: a section "Internal scale" with the rules and what each path does; D-002's "internal scale
   1" notes updated where they describe the present; README.md's `PURE_INTERNAL_SCALE` row says it applies to Metal.

## Acceptance criteria
- [ ] `tools/refactor_check.sh` PASS at S = 1 (before captures from the starting commit): 0 differing pixels on all
      18 scenes, counts the same. `tools/gerec/metal_check.sh` PASS at S = 1.
- [ ] At `PURE_INTERNAL_SCALE=4`, headless: every scene of `tools/frame_regress.sh` captured at 1920x1088, resized to
      480x272 by `tools/imgdiff.py`'s nearest neighbour, differs from the S = 1 capture by at most 5% of pixels at
      tol 24 (D-015's bar), and the race scenes' bloom region (the glows and light strips: name the rectangle) by at
      most 10% of its mean luminance. Write `tools/scale_check.sh [S]` that does this and prints the table; it is the
      Verify's third command.
- [ ] A windowed race at S = 4 on this Mac (`PURE_INTERNAL_SCALE=4 PURE_METAL_TRACE=...`, the race route, 60 s):
      `tools/frame_times.py` shows no frame over 25 ms after the race start (the plan's 60 fps bar); report S = 6
      too, for the record.
- [ ] The settings' keys unchanged; the Vulkan path untouched.

## Verify
`tools/build.sh profile && tools/refactor_check.sh && tools/scale_check.sh 4`

## May touch
- src/gpu/metal_*.mm, src/gpu/metal_*.hpp, src/gpu/shaders/ge.metal, src/host/metal_shell.mm (only to answer the
  drawable size for Auto), tools/scale_check.sh (new), docs/metal-backend.md, README.md (the switch row),
  docs/verification.md (the new check's row)

## Must not touch
- vendor/, patches/, src/profile/, config/, tools/frame_regress.sh, tools/refactor_check.sh, tools/gerec/, ref/

## Estimated turns
60

## Escalate when
S = 1 cannot be kept pixel-identical (a difference of even one pixel at S = 1 is a design fault: report the scene and
the pixel); a path needs the depth read at other than the block centre to keep the lens flare right (report with
the race frame's flare before and after); a 480S x 272S target fails to allocate at S = 6 on this Mac; the bloom at
S = 4 is visibly not the PSP's (report the two crops; do not tune the blur).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
