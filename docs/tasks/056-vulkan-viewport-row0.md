# 056: Vulkan: the offset viewport's lost row and column

Milestone: W3 (docs/windows.md step 3) | Branch: task/056-vulkan-viewport-row0 | Status: OPEN

## Goal
The known Vulkan renderer defect from task 025: transformed draws whose GE viewport is offset lose column 0 and
row 0 (the race HUD). Fix it the way the Metal backend draws: the viewport transform into clip space, the
`VkViewport` covering the whole target. This is the opener of step 3 — it moves race_hud directly, and it proves
the vendor-patch workflow and the recording/replay loop on this Windows machine before the bigger renderer tasks.

## Read first
- docs/status.md (the follow-up row "Vulkan backend loses column 0 / row 0", task 025)
- docs/tasks/025-metal-effects.md (where the defect was found and how Metal does the transform)
- docs/metal-backend.md, "How a draw is drawn" (the viewport maths Metal uses)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (the viewport path), host/gpu/shaders/ge.vert
- tools/gerec/replay_check.sh (the recordings this machine does not have yet; it makes them windowed)
- docs/verification.md, "Frame regression suite" (re-baselining a measured column)
- patches/README.md (the series; your export becomes patch 0010, regrouping is a later pass)

## Deliverable
- A vendor patch (`tools/patches.sh export 0010-vulkan-viewport-into-clip-space`, committed under patches/ with
  its row in patches/README.md) that makes offset-viewport transformed draws keep column 0 and row 0.
- The recordings of tools/gerec/replay_check.sh made on this machine (windowed, about 9 minutes once) and the
  check passing, so later tasks replay instead of re-running routes.
- The suite's vulkan measured column re-baselined for the scenes the fix moves, per docs/verification.md.

## Acceptance criteria
- [ ] `tools/gerec/replay_check.sh` passes on this machine (its five steps, recordings made)
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18 with race_hud, tt_hud and fp_hud at or below
      their old measured values (the fix must not move any scene away from its reference)
- [ ] the HUD columns/rows: a race_hud capture shows pixels in column 0 and row 0 where the reference has them
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/ before committing; never commit vendor/), patches/,
  tools/gerec/, docs/ (status follow-up row, verification measured columns), out/ (recordings)

## Must not touch
- include/psprecomp/ (a change there recompiles the corpus: BLOCKED), src/, config/, CMakeLists.txt, tools/ others

## Estimated turns
25

## Escalate when
The fix cannot be done in the renderer alone (it would need the GE state or include/psprecomp/); or re-baselining
would RAISE a scene's fraction (the fix makes a scene worse); or a vendor host rebuild exceeds 5 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
