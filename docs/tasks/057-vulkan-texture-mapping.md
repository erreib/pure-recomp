# 057: Vulkan: the texture mapping modes

Milestone: W3 (docs/windows.md step 3) | Branch: task/057-vulkan-texture-mapping | Status: OPEN

## Goal
The framework's Vulkan renderer draws every transformed draw with texture map mode 0 (UVs through the GE's scale
and offset). The Metal backend since task 036 also draws mode 1 (the texture matrix applied to position, UV or
normal, s and t divided by q per pixel) and mode 2 (the environment map from the normal and two lights) — the
reflections on the ships and the canopy. Port that into the Vulkan renderer as a vendor patch: the GE state
already carries the fields; the renderer reads none of them.

## Read first
- docs/metal-backend.md, "Texture mapping modes" (the modes, the maths, draw #359 the canopy, "Checking a draw")
- docs/tasks/036-environment-mapping.md (how the Metal side was built and measured, and its open follow-ups)
- src/gpu/shaders/ge.metal, `map_texture` (the reference implementation — read it, port its logic; the MSL file
  itself stays untouched)
- vendor/portablekit/host/gpu/shaders/ge.vert, ge.frag, vulkan_renderer.cpp (where mode 0 lives today)
- tools/gerec/gerec_dump.py and docs/metal-backend.md "Checking a draw" (cutting a frame at one draw)
- patches/README.md

## Deliverable
A vendor patch (export as 0011-vulkan-texture-mapping) that draws modes 1 and 2 in the Vulkan renderer: the
matrix and per-pixel q divide, the environment map's two light directions, the same rule Metal and the notes use.
The per-draw state must reach the shader the way the renderer already passes its uniforms; mode 0 draws must be
byte-for-byte what they were (the specialisation or branch must not disturb them).

## Acceptance criteria
- [ ] the canopy draw (race frame 6016, draw #359 by the "Checking a draw" method on this machine's race_warm
      recording): the environment-mapped pixels drawn, where before the task they took mode 0's UVs
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan`: 18/18, race_hud, tt_hud and fp_hud moved toward
      the Metal column (race_hud's Metal is 0.0149); no non-race scene moved more than 0.003
- [ ] `tools/gerec/replay_check.sh` still passes (replays are deterministic with the new modes)
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- vendor/portablekit/host/gpu/ (exported to patches/), patches/, docs/ (measured columns, status), out/

## Must not touch
- include/psprecomp/ (BLOCKED if needed), src/ (the Metal backend is the reference, not a work site), config/,
  tools/

## Estimated turns
40

## Escalate when
The GE state turns out not to carry a field the modes need (docs/vendor-map.md rule: report the difference);
a change to include/psprecomp/ or the GE state recorder would be needed; a vendor host rebuild exceeds 5 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
