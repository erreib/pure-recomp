# 060: Vulkan: 16-bit targets and the GE's dither

Milestone: W3 (docs/windows.md step 3) | Branch: task/060-vulkan-16bit-dither | Status: OPEN

## Goal
The last and hardest of the step-3 ports: draws into 5650, 5551 and 4444 targets quantised to the format's bits,
with the dither matrix's offset when DITHERENABLE is on, as the PSP writes such targets and as the Metal backend
has drawn them since task 040 (`ge_fragment_16`: blend in the shader on the target's colour, add the dither
offset, keep the format's bits; the target texture stays RGBA8). Vulkan has no programmable blending, so pick one
of docs/windows.md's two paths and defend the choice in the Result:
- true 16-bit `VkFormat`s for those targets (the hardware quantises; the dither offset needs a pass of its own
  or a subpass with an input attachment), or
- RGBA8 targets with the blend done in the shader through a self-dependent subpass input attachment (the closest
  to what Metal does), or `VK_EXT_fragment_shader_interlock` if the driver's support makes it simpler.

## Read first
- docs/metal-backend.md, "How a draw is drawn" (the 16-bit targets row), "The pipeline key" (`sixteen`), and the
  task-040 rules named there (clears into 16-bit targets not dithered; 8888 never dithered)
- docs/tasks/040-colour-test-dither-clamp.md (the measurement: the billboard target against PPSSPP's dump)
- src/gpu/metal_effects.mm and ge.metal's `ge_fragment_16` (the reference; do not touch)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (render passes, target formats, where a subpass could go)
- tools/gerec/gerec_dump.py (reading a draw's state), the billboard recording from task 059 if it was made
- patches/README.md

## Deliverable
A vendor patch (export as 0014-vulkan-16bit-dither): the three 16-bit formats drawn with the GE's quantisation
and dither, 8888 targets untouched, clears not dithered, and the doubled factors/ABSDIFF rows of the Metal
implementation carried over where the chosen path allows (mark what stays unexercised, as task 040 did).

## Acceptance criteria
- [ ] the billboard target measured as task 040 measured it: the dithered 16-bit pixels against PPSSPP's dump of
      the same draw (the adverts' cycle phase caveat is in task 040's follow-up: compare at a matching point or
      record the limitation)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18; the race scenes' distance to the Metal
      column at its smallest so far — this task closes step 3's exit: every race scene's Vulkan fraction within
      0.005 of the Metal column, or the Result names each scene still outside and why
- [ ] `tools/gerec/replay_check.sh` passes
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/, out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/, config/, tools/

## Estimated turns
50

## Escalate when
Neither path reproduces the GE's write rule on this driver; the subpass restructuring would touch the renderer's
public interface in include/psprecomp/; a vendor host rebuild exceeds 5 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
