# 068: The Vulkan renderer draws the effects buffers at 1x (E3, step 4, for Windows)

Milestone: E3 (D-015) | Branch: task/068-vulkan-effects-at-1x | Status: OPEN (after task 067)

## Goal
The Vulkan renderer draws every target at its internal scale, the bloom buffers included, so above 1x the bloom's
11-tap blur covers a smaller share of the screen and the glow tightens (PPSSPP keeps this game's effects at low
resolution for that reason; D-015 gives the Metal backend the same rule: a target narrower than 480 stays 480x272).
After this task the Vulkan renderer does the same, so the Windows build at 2x or Auto shows the PSP's glow.

## Read first
- CLAUDE.md, docs/decisions.md (D-015), docs/tasks/066-metal-internal-scale.md (the rule and how the Metal backend
  places a 1x target sampled by a scaled draw and the reverse), docs/metal-backend.md ("Internal scale", "The
  bloom chain"), docs/ge-effects.md ("The bloom chain": the 256-stride buffers, the downsample and composite draws)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (`Target`, `create_target`, `target_extent`, the render pass's
  `renderArea` and viewport, `framebuffer_descriptor`, the framebuffer-texture placement of task 063's patch,
  `write_back_depth`, `read_back_framebuffer`, `record_game_blit`), shaders/ge.vert and ge.frag
- patches/README.md, docs/upstream.md; tools/gerec/metal_check.sh (step 4b: race_warm at 2x against Metal at 1x)

## Deliverable
1. **Patch `0018-vulkan-effects-at-1x`**: a `Target` has its own extent: `target_extent` for a key whose stride is at
   least 480, 480x272 for a narrower one. Every place that assumed one extent takes the target's: the pass's render
   area and viewport, the scissor's scale, the copy for a framebuffer texture (its sub-rectangle divides by the
   source target's own size, as task 063's placement does on Metal), the depth write-back and read-backs (from a
   scaled target: the centre pixel of each block, as the Metal backend does; a 1x target as today), the display
   blit. The through-mode tile clamp task 063 noted lost above 1x is not this task's.
2. **Measured**: race_1x.gerec frame 6016 replayed into Vulkan at 2x (`PURE_INTERNAL_SCALE=2`, the Vulkan lane at
   the setting) before and after: the bloom region of `tools/scale_check.sh` (x 296-479, y 0-55) against the 1x
   replay's mean luminance, before (the tightened glow: say the figure) and after (within 10%); the glow crops.
   Metal at 2x against Vulkan at 2x on that frame: within tol 24 on 98% of pixels (the metal_check bar).
3. docs/metal-backend.md "Where it differs from the Vulkan backend on purpose" loses the effects-at-1x line if it
   has one; docs/windows.md gets one sentence (the Windows build's default scale draws the bloom at 1x).

## Acceptance criteria
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18 (test runs at 1x: the Vulkan column unchanged;
      say the deltas); `tools/gerec/metal_check.sh` PASS, step 4b's figure reported before and after.
- [ ] The 2x measurements above.
- [ ] `tools/patches.sh check` ok with 18 patches.

## Verify
`tools/build.sh profile && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/gerec/metal_check.sh`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, shaders/ge.vert, ge.frag: through `tools/patches.sh export
  0018-vulkan-effects-at-1x`, patches/README.md, docs/upstream.md
- docs/metal-backend.md (one line), docs/windows.md (one sentence), docs/verification.md if a column moves

## Must not touch
- src/, include/psprecomp/, tools/, config/, ref/, the Metal backend

## Estimated turns
45

## Escalate when
The renderer's framebuffer-texture copy cannot take a source of another size without the GENERAL-layout question
task 060 left open (report); the Windows suite cannot be run here (expected: say so; the Mac's Vulkan window suite
is the gate).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
