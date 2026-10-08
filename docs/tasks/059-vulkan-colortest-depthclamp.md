# 059: Vulkan: the colour test and the depth clamp

Milestone: W3 (docs/windows.md step 3) | Branch: task/059-vulkan-colortest-depthclamp | Status: OPEN

## Goal
Two of task 040's Metal features into the Vulkan renderer: the GE's colour test (a fragment discard after fog,
exactly as the renderer already does the alpha test) and CLIPENABLE's depth clamp (MINZ/MAXZ; today every
transformed draw is clipped at both ends of the depth range, the registers unread).

## Read first
- docs/metal-backend.md, "How a draw is drawn" (the colour test row, the 16-bit targets row for what is NOT this
  task), and task 040's rules named there (fog before the colour test; the offset before the single clamp)
- docs/tasks/040-colour-test-dither-clamp.md (how each was measured)
- src/gpu/shaders/ge.metal (`kColorTest`, the clamp in `ge_vertex`/`ge_fragment` — the reference; do not touch)
- vendor/portablekit/host/gpu/shaders/ge.frag (the alpha test's discard — the colour test goes beside it),
  vulkan_renderer.cpp (pipeline state; whether `VK_EXT_depth_clip_enable` or `depthClampEnable` fits, or the
  per-vertex clamp Metal does — docs/windows.md leaves the choice; take the one that matches the GE rule on this
  driver and say why in the Result)
- patches/README.md

## Deliverable
A vendor patch (export as 0013-vulkan-colortest-depthclamp): COLORTESTMASK/COLORREF with NEVER, ALWAYS, EQUAL,
NOTEQUAL discarding in the fragment shader (no colour, depth or stencil written), compiled out or branch-free
when the test is off or ALWAYS; and the depth clamp as the GE rule reads (MINZ/MAXZ honoured for draws with
CLIPENABLE off), with draws that never used the registers unchanged.

## Acceptance criteria
- [ ] a colour-tested draw from a recording of the billboard/advert screen on this machine (record it as
      replay_check records its scenes), cut and compared: the discarded pixels match the rule
- [ ] a depth-clamped draw: MINZ/MAXZ honoured where before the whole range clipped (the race scenes carry them;
      name the draw used)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18; no scene moved away from its reference by
      more than 0.003, race scenes moved toward the Metal column or held
- [ ] `tools/gerec/replay_check.sh` passes
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/, out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/, config/, tools/

## Estimated turns
35

## Escalate when
The GE state does not carry COLORTESTMASK/COLORREF or MINZ/MAXZ to the renderer (report, as docs/vendor-map.md
says); neither clamp approach reproduces the GE rule on this driver; a vendor host rebuild exceeds 5 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
