# 103: Animated figures: `.pmdl` version 2 with joints and clips, skinned in the models backend

Milestone: Crowd (D-025) | Branch: task/103-animated-models | Status: OPEN

## Goal
The pit marshals wave. The rigged marshal exists (out/pitguy-rigged/pitguy-wave.glb: one skinned mesh of 1986
triangles with vertex colours, a 20-bone skeleton and a four-second `Wave_On` clip, built by tools/model_pitguy.py
and tools/model_pitguy_rig.py), but `.pmdl` version 1 is static and the importer drops the skin. This task gives the
format a version 2 that carries joints, weights and clips, teaches the importer to write it and the models backend to
play it: each figure skinned on the CPU every frame at its own phase, standing where task 102 put it. Version 1
files keep working. Erik's later wish, a figure that turns to follow the player's ship, is not this task.

## Read first
- docs/decisions.md, D-025 (as amended) and docs/tasks/102-marshal-model.md, Result and Review (what the backend
  does today, the facing rule, the check).
- models/README.md whole (the convention, the rigged draft's section, the version 1 layout).
- src/gpu/models_backend.cpp: `Model` and `read_model` (97 to 140), the table and the model cache (170 to 230), the
  frame hooks (290 to 300, 325 to 370: `begin_frame`, `shown_frame_`, the trace), `replace` (430 to 520: the quad
  loop, the placement, the vertex loop that builds the draw).
- tools/model_import.py whole (390 lines: the glTF reader `load`, `read_accessor`, `matrix_of`, `mesh_matrix`,
  the light bake, the normalisation, the writer at 260 to 275).
- out/pitguy-rigged/README.md and rig-info.json (the clip's facts, the builder's own validation).
- The glTF 2.0 skinning and animation facts as the file uses them (read the file, not the spec):
  `skins[0].joints` (20 node indices in joint order), `inverseBindMatrices` (an accessor of 20 MAT4, column-major),
  the mesh node 20 under root 21, `JOINTS_0` as four unsigned bytes and `WEIGHTS_0` as four floats per vertex (at
  most three non-zero), one animation `Wave_On` with 60 channels (translation, rotation, scale for each of the 20
  joints), samplers with LINEAR and STEP interpolation, times in seconds from 0 to 4, rotations as quaternions
  (x, y, z, w). A node's local transform is translation x rotation x scale; a joint's global matrix is its
  parent's global times its local; a skin matrix is the joint's global times its inverse bind matrix; a vertex is
  the weighted sum of its skin matrices applied to its rest position.

## Facts
- Version 1: `PMDL`, u32 1, u32 vertices, u32 indices, float3 positions (height 1, feet at 0, front +z), u32 ABGR
  colours (the light baked), u16 indices. The backend's `read_model` checks the size from the counts.
- The importer normalises by the rest pose: it scales positions so the rest height is 1 and moves the feet to the
  origin. Version 2 must apply the same scale and offset to every joint's translation keys and inverse bind
  matrices' translations (the README's warning: normalising poses separately would make the figure resize or
  slide). The light is baked on the rest pose's normals and stays baked: the colours do not change with the pose,
  which is acceptable for figures this small.
- The backend builds each figure's draw by transforming `model.positions` through the quad's placement (the loop
  at about 495 to 510). Skinning goes before that loop: a skinned position per vertex for this figure's pose, then
  the placement as today. Cost: 2232 vertices x 6 marshals a frame, nothing.
- Time: the backend sees `begin_frame` once a frame and has `shown_frame_` from the inner backend. The game's
  frame rate varies (60, 120, the menus' 30), so the clip runs on wall time: `std::chrono::steady_clock` read at
  each `begin_frame`, the clip time advanced by the difference, capped at 100 ms a frame (a pause, a stall or the
  Esc menu, during which no frames come, does not skip the clip ahead). Each figure's phase is offset by a hash of
  its place (task 102's `quantise(base)`), so six marshals do not wave in unison; `PURE_MODELS_SYNC=1` sets every
  offset to 0 (for a capture that must be reproducible).
- Reproducibility for the check: `PURE_MODELS_CLOCK=frames` makes the clip time `shown_frame_ / 60` seconds
  instead of wall time, so a headless capture of frame N always shows the same pose.
- Game data never enters the repository; the models are ours.

## Deliverable
- `.pmdl` version 2 (models/README.md documents it beside version 1): the version 1 header and arrays, then
  u32 joint count J (0 for a static model, which the backend treats as version 1), per joint: u16 parent (0xFFFF
  for a root), float3 rest translation, float4 rest rotation (x, y, z, w), float3 rest scale, 16 floats inverse
  bind (column-major); per vertex: 4 x u8 joint indices and 4 x float weights (normalised to sum 1 at import; a
  vertex with no weights binds to joint 0 with weight 1); u32 clip count, per clip: a u32-length name, float
  duration, u32 key count K, K float times (sorted, the first 0), then per joint per key: float3 translation,
  float4 rotation, float3 scale (the importer samples every channel at the union of key times, STEP channels held,
  LINEAR interpolated, so the backend only ever interpolates between two keys of a dense table). Size for the
  marshal: about 20 x 97 x 40 bytes = 78 KB plus the mesh.
- tools/model_import.py: with a skin in the file, writes version 2 (the joint order of `skins[0].joints`, parents
  from the node tree, the mesh node's own transform folded into the rest positions and the inverse bind matrices
  as the glTF semantics require, the normalisation applied consistently), every animation as a clip; without a
  skin, version 1 as today. `--static` writes version 1 from a skinned file (the rest pose). Prints the joint,
  clip and key counts. A vertex with more than four weights, or weights not summing to about 1, is reported and
  normalised.
- src/gpu/models_backend.cpp: `read_model` reads version 2 (version 1 as before); `Model` gains the joints, the
  weights and the clips; a `Pose` cache per (model, clip, time quantised to 1/120 s) is optional, a plain
  evaluation per figure is fine at six figures; the clip time per frame as the Facts say; the skinned positions fed
  to the existing placement; `[models]` trace line gains `clip NAME t=SECONDS` for the first figure of the frame
  and `(animated)` when any figure is skinned. Which clip plays: the first in the file, or `clip=NAME` in
  models.ini's figure line (`figures=1 clip=Wave_On`).
- models/pitguy.pmdl rebuilt as version 2 from out/pitguy-rigged/pitguy-wave.glb (committed; about 130 KB).
- tools/models_check.sh: a third row: the tt_hud scene captured at two frames one second apart
  (`PURE_MODELS_CLOCK=frames`, `PURE_MODELS_SYNC=1`, Models on; tools/run_boot.py's `--shots DIR --every N` or two
  `--frames` runs, whichever the script already drives) and compared: at least 40 pixels differ inside the
  marshals' region (the left booth: the box the task finds once from the 4x capture, written as a constant with
  its origin), and the region below the figures' feet (the deck line) is unchanged, so the feet stay planted;
  the existing rows unchanged. PASS or FAIL last.
- docs: models/README.md (version 2, the clip, `clip=` in models.ini, the switches), docs/developing.md
  (`PURE_MODELS_CLOCK`, `PURE_MODELS_SYNC`), docs/ge-backend.md's models section (the skinning, the time rule),
  docs/controls.md if the row's help text should mention the wave (one clause), tools/model_pitguy_rig.py's
  docstring if its "static only" note is now wrong (one line).

## Acceptance criteria
- [ ] `python3 tools/model_import.py out/pitguy-rigged/pitguy-wave.glb out/103/pitguy.pmdl` writes version 2 and
      prints 20 joints, 1 clip, its key count; `--static` writes a version 1 byte-identical to the current
      models/pitguy.pmdl (the rest pose is the same mesh).
- [ ] A Python check in Result: the clip at t=0 and t=4 give the same pose (the loop), and at t=0 the skinned
      positions equal the rest positions within 1e-4 (the bind pose is the rest pose, which the builder's round
      trip promises).
- [ ] `tools/models_check.sh` PASSes with its new row: the arm moves between the two frames, the feet do not.
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS (Original unchanged); task 102's rows of the models check
      PASS as before (the figures' rest pose at t=0 under `PURE_MODELS_CLOCK=frames` is the static picture).
- [ ] A 4x headless capture of tt_hud at a frame where the arm is raised (the trace's `t=` says which; frame
      5890 + 24 x 0.9 for the first reach) is looked at: a marshal with an arm up on the booth.
- [ ] `tools/docs_check.py` PASS; `tools/release_check.sh` as before.

## Verify
`tools/build.sh profile && tools/docs_check.py && python3 tools/model_import.py out/pitguy-rigged/pitguy-wave.glb out/103/pitguy.pmdl && tools/models_check.sh --out out/103/check && tools/frame_regress.sh`

Headless throughout; no window run.

## May touch
- tools/model_import.py, tools/models_check.sh, tools/model_pitguy_rig.py (a docstring line only)
- src/gpu/models_backend.cpp, models_backend.hpp
- models/pitguy.pmdl, models/models.ini, models/README.md
- docs/developing.md, docs/ge-backend.md, docs/controls.md
- docs/tasks/103-animated-models.md (Result)

## Must not touch
- vendor/, include/psprecomp/, tools/regen.sh, the corpus
- src/gpu/metal_*.mm, the shaders, src/host/ (the skinning is the wrapper's; a model draw stays an ordinary draw)
- out/pitguy-rigged/ (read only), docs/status.md, docs/decisions.md

## Estimated turns
40

## Escalate when
- The glTF's skin cannot be reproduced by the rule in Read first (the importer's t=0 pose differs from the rest
  mesh by more than 1e-3 after the mesh node's transform is folded): report the first joint that differs and the
  numbers, BLOCKED.
- The check cannot see the arm move in a headless capture at 1x (the marshals are a few pixels): capture at
  `PURE_INTERNAL_SCALE=4` for that row and say so; if still under 40 pixels, report the figures, PARTIAL.
- A frame's skinning takes more than 1 ms for the six marshals (time it once): say so; do not optimise beyond a
  pose cache.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
