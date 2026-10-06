# 024: The Metal GE backend, 3D: lighting, fog, sprites, culling

Milestone: M6 | Branch: task/024-metal-3d | Status: OPEN

## Goal
Task 023's Metal backend draws transformed (3D) geometry with its vertex colour only. This task makes 3D draws right:
the GE's lighting (four lights, material colours, ambient, specular power), fog, transformed sprites expanded in
screen space as the GE does, culling confirmed on the race, and anything else in `DrawCall` that a 3D draw carries
and the backend ignores today. The reference is the Vulkan backend through ge_replay (task 022), backend against
backend on recordings that have no bloom and no stencil work, since those are task 025's. The race frame against
PPSSPP is measured and reported, not yet a pass condition.

## Read first
- CLAUDE.md, docs/metal-backend.md (all of it: how a draw is drawn, the pipeline key, "What is not done yet",
  "Where it differs"), docs/ge-backend.md sections 1, 2, 6 and 7 (ge_replay: `--a/--b`, `--first-diff`,
  `--frames`), docs/ge-effects.md (the race's bloom chain and shadow volumes, which this task leaves alone)
- src/gpu/metal_backend.mm, src/gpu/metal_shaders.h (what exists), src/tools/ge_replay.cpp (the tool's options)
- vendor/portablekit/host/gpu/ge_state.hpp (`LightingState`, `LightState`, `FogState`, `DrawCall::lighting_enabled`,
  `material_color`, `has_vertex_color`, `environment_version`, `material_version`), host/gpu/shaders/ge.vert and
  ge.frag (the lighting and fog the Vulkan backend computes: port them), vulkan_renderer.cpp (`submit`: how sprites
  are expanded for transformed draws, how lit draws without a vertex colour are coloured, the cull decision)
- tools/gerec/replay_check.sh (how recordings are made and replayed), config/pad_scripts/single_race.txt (the route
  through CLASS, LEAGUE, TRACK and TEAM to the race; the TEAM screen shows a lit, rotating ship model)
- https://www.ppsspp.org/docs/psp-hardware/gpu/ (read only: the GE's lighting model, sprite rule and fog) if a
  detail is not in ge.vert

## Deliverable
1. Lighting in `metal_shaders.h` and the uniforms that feed it: the GE model as `ge.vert` computes it (per-vertex;
   light kinds directional, point, spot; diffuse, specular with the material's power, ambient; the material
   update bits choosing between the vertex colour and the material colours; `reverse_normals`), for draws with
   `lighting_enabled`. Unlit draws keep their vertex or material colour as today.
2. Fog as `ge.vert`/`ge.frag` do (`FogState`: end, scale, colour), applied where the GE enables it.
3. Transformed sprites expanded in screen space after projection (the GE's rule: the second vertex's depth and
   colour; the rectangle axis-aligned on screen), with the Vulkan backend's result as the reference.
4. Culling confirmed on the race (the frontend culls nothing): `cull_clockwise` against Metal's winding in window
   coordinates, checked by `--first-diff` against Vulkan; fix if wrong.
5. Whatever else `--first-diff` against Vulkan turns up in a lit, fog-free, stencil-free frame (a texture
   coordinate rule, a depth-range case, a colour clamp): fix it if it is a 3D rule, record it in
   docs/metal-backend.md if it is 025's.
6. `tools/gerec/metal_check.sh TEAM_FRAME`: records `out/gerec/team.gerec` when missing (the `single_race.txt` route
   with the record backend at the TEAM screen frame you choose, 2 frames, Vulkan inner; write the chosen frame into the
   script as its default and say in docs/metal-backend.md how you chose it: a frame where the ship model is lit and
   no bloom or stencil draw is in the list, checked with `PURE_METAL_LOG` or `gerec_dump.py`), then runs
   `PureNative --replay out/gerec/team.gerec --a vulkan --b metal --tol 24 --max-frac 0.02` and, for the record,
   `--replay out/gerec/race_warm.gerec --a vulkan --b metal --frames 6016 --tol 24 --first-diff` (reported, not a
   pass condition: the first differing draw should be one of the bloom chain or a stencil draw, 025's).
7. docs/metal-backend.md: lighting and fog rows in "How a draw is drawn", the sprite rule, the culling check, the
   numbers (team frame fraction, race frame 6016 fraction against Vulkan and against PPSSPP via
   `tools/frame_regress.sh --backend metal --only race_hud`, the first differing draw), and "What is not done yet"
   reduced to 025 and 026. README.md if a switch is added.

## Acceptance criteria
- [ ] `metal_check.sh`: the team recording replayed into vulkan and metal passes at tol 24, max-frac 0.02 (the
      remaining pixels are edges from 2x against 1x).
- [ ] The race frame 6016 bisection's first differing draw against Vulkan is a bloom-chain or stencil draw (task
      025's), not a lit or fogged one; the fraction against Vulkan and against PPSSPP is recorded.
- [ ] `tools/frame_regress.sh --backend metal --only lang,title,profile` still passes with the task 023 fractions
      (0.0002, 0.0002, 0.0000), and the Vulkan suite still passes 5/5 unchanged.

## Verify
`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal --only lang,title,profile`

## May touch
- src/gpu/ (the backend and its shaders), tools/gerec/metal_check.sh (new), docs/metal-backend.md, README.md

## Must not touch
- vendor/, patches/, src/profile/, src/hle/, src/host/, src/tools/ (ge_replay: if it lacks an option you need,
  report it), tools/frame_regress.sh, tools/gerec/replay_check.sh, config/, ref/, CMakeLists.txt

## Estimated turns
70

## Escalate when
No frontend frame with a lit model is free of bloom and stencil draws (report the frames you checked and what they
contain; the acceptance then needs a different reference), or a difference against Vulkan traces to the Vulkan
backend being wrong against the GE's documented rule (report both, do not match a Vulkan bug), or ge_replay needs a
change. Do not start on the stencil, the bloom chain, read-backs or write-backs (025).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
