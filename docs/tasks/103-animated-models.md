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
Status: DONE

Changed:
- tools/model_import.py: when the mesh's node has a skin, the importer writes version 2. It keeps the joints in `skins[0].joints` order and takes parents from the node tree; a root's non-joint parents' world matrix is folded into the root. Each vertex gets four joints and weights: every JOINTS_n/WEIGHTS_n set is merged, the four largest kept and normalised, an unweighted vertex binds to joint 0, and the counts are reported. Every animation becomes a clip, sampled at the union of its key times (STEP held, LINEAR lerped, rotations slerped, CUBICSPLINE's values taken linearly). The rest-pose normalisation N = T(o) S(s) is applied consistently. Every joint translation is scaled by s, a root's also gets o. The inverse bind becomes S(s) IBM M^-1 S(1/s) T(-o), where M is the mesh node's world matrix (it is baked into the rest positions and glTF's skinning ignores it). `--static` writes version 1. The importer prints the joint, clip and key counts, then skins each clip's first and last key and prints the bind error and the loop seam.
- src/gpu/models_backend.cpp:
  - `read_model` reads version 2 (and version 1 as before), with bounds checks on every field and a parents-first evaluation order. `Model` gains joints, order, per-vertex joints and weights, and clips; `Figure` gains `clip`.
  - models.ini takes `clip=NAME`. A name the file lacks is reported and the first clip plays. The table line also lists joints, clips and keys.
  - Clock: steady_clock at each `begin_frame`, each frame's step capped at 100 ms. `PURE_MODELS_CLOCK=frames` uses `shown_frame_ / 60` instead, and `PURE_MODELS_SYNC=1` sets every phase to 0. Each figure's phase is a splitmix64 hash of `quantise(base) * 64 + f`.
  - Skinning (`positions_of`) feeds the existing placement loop unchanged. A static model takes the old path.
  - The trace line gains `; clip NAME t=SECONDS (animated), skinned in N us`, appended after `(captured)` so models_check's regex still matches.
- models/pitguy.pmdl: rebuilt as version 2 from the rigged GLB, 172419 bytes. models/models.ini: `clip=Wave_On` on the six lines, and the header explains `clip`.
- tools/models_check.sh:
  - Run 2 is new. It runs tt_hud's route through tools/run_boot.py with shots at 5890 and 5950, Models on, 4x, `PURE_MODELS_CLOCK=frames`, `PURE_MODELS_SYNC=1`. It PASSes when at least 40 pixels at tol 24 differ in `WAVE_BOX = (112, 124, 48, 22)` (the left booth's three marshals) and at most 0 in `DECK_BOX = (112, 146, 48, 6)` (the deck under their feet). Both boxes are constants with their origin in a comment.
  - Runs 0 and 1 now also set the frames clock and sync, so their pose is reproducible. Their criteria are unchanged.
- models/README.md: version 2's layout, the animation section (what is kept, `clip=`, time, the switches, Blender notes), the rigged section updated, and the stale "static only" paragraph replaced. docs/developing.md: `PURE_MODELS_CLOCK` and `PURE_MODELS_SYNC` rows, the trace row, and the models_check and model_import rows. docs/ge-backend.md section 9: the skinning, the time rule, the trace and the check. docs/controls.md: "waving (task 103; ...)".

Python check (an independent reader of out/103/pitguy.pmdl, not the importer's code; it skins with the backend's interpolation):
```
version 2, 2232 vertices, 20 joints, clip Wave_On 4.000 s 97 keys, 172419 bytes, read to the end
t=0 against the rest positions: max 8.99e-07 (PASS at 1e-4)
t=4 against t=0: max 0.00e+00 (PASS at 1e-4)
t=0.9: largest move 0.450 (height 1), the feet (y<0.05, 96 vertices) 8.99e-07, top y 1.000
t=1.4: largest move 0.565 (height 1), the feet (y<0.05, 96 vertices) 8.99e-07, top y 1.001
```
- `--static` output is byte-identical to the previous models/pitguy.pmdl (`cmp`, 47644 bytes).
- Skinning cost from the trace: 33 to 39 us a frame for the six marshals, far under 1 ms.

The 4x capture (out/103/x4/shots/wave_a.png, frame 5890, trace `clip Wave_On t=2.15`; the side-by-side crop with frame 5950 is out/103/x4/crop.png): I looked at it with the Read tool. All three marshals on the left booth have their right forearm raised, hand up beside the head, and stand on the deck behind the railing. At 5950 (t=3.15) the same three hold the arm out and lowered. The booth, railing and deck are unchanged; only the HUD and sky overlays differ.

Verify output (last 20 lines):
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
verify 103: PASS
```
Also in that run: `tt_hud 1 against 0: 182 pixels differ at tol 24 (at least 150): PASS`, `tt_hud wave (Wave_On t=2.15 and Wave_On t=3.15): 339 pixels differ in the marshals' box (112, 124, 48, 22) (at least 40), 0 in the deck (112, 146, 48, 6) (at most 0): PASS`, `models_check: PASS`; `docs_check: 39 files, 0 findings: PASS`. `tools/release_check.sh`: 6 of 7 checks PASS (binaries: 4, the known three and models/*.pmdl). `home` FAILs on the same 6 findings as task 102 (patches/0029-windows-file-url.patch:10,33,56 and patches/README.md:78,613,614), which this task does not touch.

Open questions:
1. Escalation clause, 1x: at 1x only 20 pixels differ in the marshals' box (2 of them are the scene's own change), under 40. Run 2 therefore captures at `PURE_INTERNAL_SCALE=4`: 339 pixels with Models on, 11 with Models off on the same two frames, 0 in the deck either way.
2. On the frames clock the capture frame is not the clip's t=0. 5890 / 60 mod 4 is t=2.15 (the shown frame at `begin_frame` is 5889), so the brief's "the rest pose at t=0 is the static picture" does not hold literally. Task 102's rows pass anyway with the arm raised (182 pixels against 150). I put runs 0 and 1 on the frames clock for reproducibility; on wall time they gave 179 to 180. Say if you would rather they stayed on wall time.
3. The marshal's version 2 file is 172 KB, not about 130 KB: the per-vertex joints and weights add 2232 x 20 = 44.6 KB, which the brief's estimate left out.
4. The backend interpolates linearly between two keys of the dense table, so a STEP channel's jump is spread over one key interval (1/24 s here). The marshal's STEP channels are its constant ones, so nothing shows. A file with a real STEP jump between sparse keys would show a short blend.
5. tools/model_pitguy_rig.py's docstring has no "static only" note, so I left it alone. The stale text is in strings it writes (line 299, the Blender text block; line 309, rig-info.json's `runtime_support`), which a docstring-only edit may not change. out/pitguy-rigged/README.md and rig-info.json (read only) say the same.
6. Window checks this change needs (none were run): tt_hud with Models in the Metal window and in the Vulkan window (`tools/frame_regress.sh --shell metal --backend metal --only tt_hud --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env PURE_CROWD_MODELS=1`, and the Vulkan equivalent with `PURE_GE_MODELS_INNER=vulkan`). Also the marshals waving at real pace with the frame interpolation on, since the model draws' vertices now change every frame.

## Review
Verify rerun (the planning session, 2026-10-20, after the merge): `tools/models_check.sh` PASS (the wave row: 339
pixels differ in the marshals' box between t=2.15 and t=3.15, 0 in the deck; task 102's rows as before), and the
owed window runs, tt_hud with Models through the models backend in the Vulkan window (0.0512, PASS; the trace:
`clip Wave_On t=0.92 (animated), skinned in 69 us`) and the Metal window (0.0500, PASS; `t=0.70`, 129 us). The
worker's 4x side-by-side crop looked at: three marshals on the left booth, right forearm raised beside the head at
t=2.15, the arm out and lowered at t=3.15, feet on the deck behind the railing both times.
Spot-read: the importer's handling of the mesh node's transform and the rest-pose normalisation is the right
algebra (its own t=0 check against the rest mesh at 9e-7 says so); the dense key table makes the backend a lerp;
the clock rule is as briefed; the trace extension keeps the check's regex. Open question 2 is fine: the frames
clock puts frame 5890 at t=2.15, not 0, and the static rows still pass; runs 0 and 1 stay on the frames clock for
reproducibility. Open question 4 (a STEP jump blended over one key interval) is a known shape of the dense table,
harmless for this rig. The stale "static only" strings in tools/model_pitguy_rig.py's outputs are Astra's to
refresh at the next build of the asset.
Merged: 6f79a62 into batch/m2.
Notes: Erik's eye owed on the wave at real pace (the dev build, the row at Models, a Time Trial on Vineta K) and
with the Vulkan shell's frame interpolation on, since the model draws' vertices now change every frame. Astra's
eight crowd figures (tools/model_crowd.py, out/crowd-starter) are the crowd task's input.
