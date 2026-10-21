# 106: The skies as models: the models backend draws a layered sky in place of the sky cube

Milestone: Skies (D-026) | Branch: task/106-sky-models | Status: OPEN

## Goal
With a new "Skies" row at Models, Vineta K's five sky faces are replaced by a layered vertex-coloured sky model
drawn once a frame around the camera, with the faces' depth and stencil state so the sun block and the rest of the
frame are untouched, and a parallax offset per layer so the horizon slides against the dome as the ship moves.
Astra's sky model may not exist when the task starts: the task builds a placeholder sky (a dome gradient and a
ring of boxes) with a script, so the engine side is proven and Astra's layers replace it by name. D-026 records the
design; docs/prompts/sky-vineta-k.md is the prompt Astra builds from.

## Read first
- docs/decisions.md, D-026 (the survey's facts and the rules), docs/prompts/sky-vineta-k.md (the model's space).
- src/gpu/models_backend.cpp: the table reader (sets, `[set NAME]`), `replace` and the batch cache (the kept
  batches of task 105 with a stable `vertex_address` and a version), the frame hooks and the trace.
- models/models.ini and models/README.md (the syntax to extend).
- src/profile/enhancements.cpp (`kOptions`: the row to add, beside `crowd_models`).
- out/106/skycube/frame.obj and frame.json (the five faces extracted: their extent relative to the cube's centre,
  ±50 on x and z, 49.7 on y; the centre is the face draw's world translation), out/101/race/frame.json draw 635
  (the state: depth GREATER write, fog off, stencil ALWAYS 0x04, alpha test ALWAYS, cull off, white colour, view 1,
  `usual_world` false: the world matrix is the scenery's scale with the cube's translation).
- tools/models_check.sh (the rows; the headless capture and the boxes).
- docs/ge-effects.md around "sun block" (what reads the sky's depth).

## Facts
- The faces' keys for Vineta K (the HD pack's ini lines 2605 to 2609): skybox_01 `00000000b35b2a93387e25cf` (+z),
  skybox_02 `00000000d5927b5de3617a78` (−x), skybox_03 `00000000a985ea5ff033d0a2` (−z), skybox_04
  `00000000fd24dbbbc5d5ea0d` (+x), skybox_top `00000000c668ec30da8ad8ed` (+y). Other tracks have their own five
  (`grep skybox ~/Downloads/WipEout-Pure-HD-Texture-Pack/textures.ini`).
- The cube's centre is the face draw's world translation (188.5, 40.1, −116.8 in the race frame; the eye at
  190.6, 59.2, −115.7); the world matrix is uniform 2293.69 with that translation, so object space is the cube
  scaled by 1/2293.69: the model draw should carry its own world matrix (identity) with vertices placed in world
  space, as the figures do, at centre + 50 x the model's unit coordinates.
- The five faces come in one display list, consecutive draws, every frame of a race; the first face seen in a
  frame triggers the sky draw, the other four are dropped; a frame without them (the menus) draws no sky.
- The camera's world position for the parallax is the eye from the face draw's view matrix (task 102 computes
  it); the offset for a layer is −F x (eye.x, eye.z) wrapped to the cube's width (100 units), applied as the
  layer's world translation, so a layer's kept batch never rebuilds for it.
- A `.pmdl` version 1 is a static mesh (the sky's layers are static); the importer normalises height to 1 and
  moves the feet to 0, which is wrong for a sky: `tools/model_import.py --as-is` keeps the file's coordinates
  (no normalisation, no recentring) and still bakes the light unless `--no-light`; a sky layer is imported with
  both (its colours are the author's).
- The batches: a layer is one draw (under 65535 vertices); the kept-batch cache of task 105 applies when the
  draw's input is unchanged, which it is: only the state and the world translation change per frame.
- Game data never enters the repository; the placeholder sky and Astra's are ours.

## Deliverable
- tools/model_import.py: `--as-is` and `--no-light` (the importer's docstring and models/README.md say what a sky
  layer uses).
- tools/model_sky_placeholder.py OUT_DIR: writes `dome.gltf` (a five-face shell of the unit cube, 9 x 9 grids per
  face, a vertical gradient from white at y 0.3 to 0.5 to blue at the top) and `horizon_city.gltf` (a ring of 12
  boxes of varied height on the −z face's horizon band at y 0.38, two shades), both within D-026's depth rule;
  models/sky/vineta_k/dome.pmdl and horizon_city.pmdl made from them with `--as-is --no-light`; models/README.md's
  sky section (the space, the depth rule, the layers, the parallax).
- models/models.ini: `[sky vineta_k]` with `dome.pmdl parallax=0` and `horizon_city.pmdl parallax=0.002`, and the
  five face keys mapped `sky=vineta_k`; the header's syntax.
- src/gpu/models_backend.cpp: the `[sky NAME]` reader (layers in order, `parallax=F`, `spin=S`); the row
  `sky_models` read once a frame; in `submit`, a face draw whose key maps to a sky: on the frame's first, the
  layers submitted in order as D-026 (2) and (3) say (world translation = centre + the parallax offset, the
  state copied from the face draw, `texture.enabled` false, vertex colours as the model's, `has_vertex_color`
  true, lighting off, fog as the face's (off), depth and stencil as the face's, cull off, the kept-batch ids), the
  face draw dropped; the trace line gains `sky NAME L layers`; `[pure] skies: on (game.sky_models)` once.
- src/profile/enhancements.cpp: the `sky_models` row, "Skies", Original or Models, default 0, Video tab, the help
  in the rows' voice ("The sky is five flat pictures on the PSP. Models draws a 3D sky where the port has one:
  Vineta K today. Both renderers."); `PURE_SKY_MODELS` comes with it; tools/purelib/port.py's `ENHANCEMENTS_OFF`
  pins it to 0.
- tools/models_check.sh: a sky row: race_hud and tt_hud with `PURE_SKY_MODELS=1` (and the crowd on as the
  default): the trace reports 5 faces replaced by L layer draws, the capture differs from the one without in the
  sky region (above the horizon: a box the task finds once at 4x, written as a constant), the race HUD found, and
  the captures within the scene's limit plus 0.10; the Metal and Vulkan window runs of race_hud with both rows at
  Models (two window runs, Erik's screen booked) looked at: the sky drawn, the sun flare still there.
- Docs: docs/ge-backend.md's models section (skies, the parallax, the depth rule), docs/controls.md and README.md
  (the row), docs/developing.md (`PURE_SKY_MODELS`, the tools' rows), tools/menu_check.sh (the row on both shells).

## Acceptance criteria
- [ ] `tools/models_check.sh` PASSes with the sky row: 5 faces replaced on both scenes, the sky region differs,
      the HUD found, the references within limit + 0.10.
- [ ] A 4x headless capture of race_hud with the placeholder sky looked at: a gradient sky behind the track, a
      ring of boxes on the −z horizon, the sun flare (the game's) still drawn, no black or missing sky anywhere in
      the picture; the worker says what it sees.
- [ ] The two window runs PASS and are looked at (the sky on both renderers).
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS (the row pinned off by the tools; Original unchanged);
      `tools/menu_check.sh` PASS on both shells (two more window runs, or the same session's).
- [ ] `tools/docs_check.py` PASS; `tools/release_check.sh` as before (the new .pmdl files under models/sky/ match
      the pattern: adjust the pattern to `models/**/*.pmdl` if needed).

## Verify
`tools/build.sh profile && tools/docs_check.py && python3 tools/model_sky_placeholder.py out/106/placeholder && tools/models_check.sh --out out/106/check && tools/frame_regress.sh`

Headless; then the window runs listed above (race_hud on each shell with both rows at Models, and menu_check on
each shell), Erik's screen booked.

## May touch
- src/gpu/models_backend.cpp, models_backend.hpp
- src/profile/enhancements.cpp, tools/purelib/port.py (`ENHANCEMENTS_OFF`), tools/menu_check.sh
- tools/model_import.py (the two switches), tools/model_sky_placeholder.py (new), tools/models_check.sh,
  tools/release_check.sh (the binaries pattern only)
- models/models.ini, models/README.md, models/sky/ (new)
- docs/ge-backend.md, docs/controls.md, docs/developing.md, README.md
- docs/tasks/106-sky-models.md (Result)

## Must not touch
- vendor/, include/psprecomp/, tools/regen.sh, the corpus
- src/gpu/metal_*.mm, the shaders, src/host/
- docs/status.md, docs/decisions.md, docs/prompts/
- out/106/ (read only)

## Estimated turns
45

## Escalate when
- The sun block's picture breaks with the sky model (the flare missing or wrong, or the capture's bloom region
  differs beyond the limit): report the depth values the sky draw writes against the faces' (the trace or a
  depth dump), PARTIAL with the row's default Original.
- The face draws are not consecutive or not all five in a frame on some scene: report the draw indices seen,
  and trigger on the first face anyway.
- The parallax offset makes a layer visibly pop at the wrap: report the frame and the offset; PARTIAL with the
  wrap at the cube's width kept.

## Result
Status: DONE (the engine side is proven. The 4x look has two caveats, under "What the captures showed" and "Open questions": the −z boxes are out of view of both check cameras, and the game's sun glow is drawn but cannot be told apart in the pale placeholder sky.)

Changed:
- tools/model_import.py: `--as-is` (keeps the file's coordinates: no normalisation, no recentring) and `--no-light` (no key light baked); the docstring says a sky layer uses both.
- tools/model_sky_placeholder.py (new). It writes `dome.gltf`: the five faces, each 9 x 9 vertices. Each side's rows sit at the gradient's stops (−1, −0.4, 0, 0.3, 0.38, 0.5, 0.6, 0.8, 1), from a haze below the horizon, through white at y 0.3 to 0.5 and sky blue at 0.6, to deep blue at the top's centre. A uniform grid would have put rows only at 0.25 and 0.5. It also writes `horizon_city.gltf`: 12 boxes of varied height on the −z horizon, bases at y 0.30, tops at 0.45 to 0.75, slate fronts and lighter sides and tops. Every vertex is checked against the depth rule.
- models/sky/vineta_k/dome.pmdl (640 triangles) and horizon_city.pmdl (96 triangles), imported with `--as-is --no-light`.
- models/models.ini: the five face keys `sky=vineta_k`, `[sky vineta_k]` (`sky/vineta_k/dome.pmdl parallax=0`, `sky/vineta_k/horizon_city.pmdl parallax=0.002`), and the header's syntax. models/README.md: a new "Skies" section covering the space, the depth rule, the layers and the parallax.
- src/gpu/models_backend.cpp:
  - The `[sky NAME]` reader reads layers in order with `parallax=F` and `spin=S`; a key's value can now be `sky=NAME`; the summary gains `sky NAME of L layers`.
  - `crowd_models` and `sky_models` are read once a frame. Either one turning to Models re-reads the table, and the kept batches and lookups are cleared with it.
  - `draw_sky`: the first face of a frame submits each layer as one kept batch. The vertices are the model's times 50. The world matrix is a translation to the face's world translation plus the wrapped offset −F x eye.xz, then a turn of S deg/s about y. The state is the face draw's (copied through `model_draw_of`: texture off, vertex colours, no lighting, culling off). All five faces are dropped.
  - The sky's batches count against kMostCachedBatches.
  - The trace gains `; sky NAME L layers (F faces replaced), the eye at (X, Y, Z) of the cube`, and `[pure] skies: on (game.sky_models), drawn by NAME` / `[pure] skies: off` are printed.
- src/profile/enhancements.cpp: the `sky_models` row, "Skies", Original or Models, default 0, Video tab, with the brief's help text. tools/purelib/port.py: `PURE_SKY_MODELS` is in ENHANCEMENTS_OFF.
- tools/models_check.sh: run 4, both scenes with `PURE_SKY_MODELS=1` and the crowd on. It requires `sky vineta_k 2 layers (5 faces replaced)`, at least 2000 pixels changed against run 1 at tol 24 in SKY_BOX (150, 0, 85, 60) (3597 and 4602 measured), race_hud's HUD found, and both captures within their limit plus 0.10. tools/menu_check.sh: the "Skies" row on both shells.
- docs/ge-backend.md (the models section's Skies entry: the draw, the parallax, the depth rule, the glow, the trace), docs/controls.md, README.md, docs/developing.md (`PURE_SKY_MODELS`, the importer's switches, the placeholder tool's row, the check's sky row).
- tools/release_check.sh is unchanged. Its fnmatch pattern `models/*.pmdl` already matches models/sky/vineta_k/*.pmdl (binaries PASS, 14 files).

Verify output (last 20 lines; the full Verify line exited 0; models_check's sky rows were `tt_hud sky (run 4): sky vineta_k 2 layers (5 faces replaced), 4602 pixels differ ... 0.1545 vs ref (allowed 0.22): PASS`, `race_hud sky (run 4): ... 3597 pixels differ ... 0.1194 vs ref (allowed 0.20): PASS`, `models_check: PASS`):
```
lang          690    0.0002   0.07   24    0.0002 +0.0000  PASS
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

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 20s)
```
Other checks: `tools/docs_check.py` PASS (40 files, 0 findings). `tools/menu_check.sh --shell metal` PASS and `--shell vulkan` PASS (window runs). `tools/release_check.sh` is as before: the binaries row passes, and the only failing row is `home`, with six findings in patches/0029-windows-file-url.patch and patches/README.md that this task did not touch.

What the captures showed:
- **4x headless race_hud, sky on (out/106/x4/shots/race_hud.png), against Original (out/106/x4off):**
  - The yellow-lit clouds and lilac tints of the Original's −x face are gone. In their place is the dome's gradient: white haze from the horizon up, and light blue only in the top rows ((201, 218, 247) at the top edge).
  - The race camera faces −x and is pitched down 5.6° with a ±15° vertical view, so it sees the sides only up to y about 0.55, mostly the white band. The game's additive sun glow (draws 640-657, depth GREATER with no writes) adds about 16 to 72 a channel over the sky, so anything paler than about 215 turns white. That is why I moved the blue down to y 0.6.
  - No black or missing sky anywhere; the HUD, the stands and the track are as before.
  - The 12 boxes are on −z and are not in view in race_hud or tt_hud.
  - A one-off diagnostic with `spin=0.8976` (90° at frame 6016 on the frames clock, out/106/spin; models.ini restored afterwards) turned them to −x. They drew in front of the dome with the right depth order, slate fronts and lighter sides, washed to white toward their bases by the sun glow.
  - The glow itself is drawn. A one-off all-red dome showed it on top (red with +16 to +72), strongest at the upper left. In the placeholder's pale sky, though, it reads as part of the white haze rather than as a distinct flare.
- **4x tt_hud:** the same white-to-light-blue sky ((195, 213, 243) at the top). The trace puts Time Trial's eye at (0.07, 0.11, 0.02) of the cube, not 0.38, so its horizon is lower in the sky's space.
- **Window runs, both rows at Models** (`--env PURE_GE_BACKEND=models`; frame_regress's own `--backend` alone bypasses the wrapper):
  - Metal shell race_hud (out/106/win_metal): 5 faces replaced by 2 layers; 0.1628 against the reference. That is within limit + 0.10 (0.20), though frame_regress's plain 0.10 marks it FAIL, as it does for the crowd.
  - Vulkan shell race_hud (out/106/win_vulkan, inner vulkan): 5 faces replaced by 2 layers; 0.1439 (within 0.20).
  - I looked at both: the same pale gradient sky behind the track as headless, the crowd and the HUD drawn, no black or missing sky, and the glow merged into the white as above.

Open questions:
- **The depth rule.** D-026's strict "nothing nearer than 1.0" cannot hold for a layer over a unit-cube dome: depth GREATER hides anything level with the dome, so such a layer would be invisible. The placeholder's boxes stand 0.04 inside the −z face, under the prompt's 0.05 allowance for clouds. The check's captures stay within limits. I did not measure the sun block's depth reads with a layer covering the sun; the −x face where the sun sits has no layer geometry.
- **Box placement.** The brief puts the boxes on −z, but both check cameras look −x, so the second layer is proven only by the trace and the spin diagnostic. If the placeholder should show boxes in the check scenes, a few would have to stand on −x, away from the sun's direction (screen upper left, about z +0.3, y 0.5 to 0.6).
- **The sun flare.** It is still drawn, but it only reads as a flare against a sky darker than about 215 a channel. Astra's sky should keep the −x horizon's sky saturated enough for the glow to show. The prompt says the sun is toward −X, but it also asks to keep +X clear, which looks swapped. In the race frame the sun is on the −x face.
- **The eye's height.** It is 0.38 of the cube in the race and 0.11 in Time Trial. A model whose horizon is authored at 0.38 will sit high in Time Trial. Worth telling Astra, or offsetting a layer's y per mode later.
- **Window frame_regress.** The window frame_regress lines carry no `(captured)` models line. The 60-frame trace lines show the sky, so this is only a capture-trace gap under the window shells.

## Review
Verify rerun (the planning session, 2026-10-20, after the merge): `tools/models_check.sh` PASS with the sky row on
both scenes (5 faces replaced by 2 layers, 3597 and 4602 pixels changed in the sky box, within limit + 0.10); the
worker's 4x race_hud capture looked at: a pale gradient sky behind the track in place of the clouds, the crowd and
the HUD as before, nothing black or missing. The worker's window runs on both shells reported the same.
Spot-read: the `[sky NAME]` reader, the first-face trigger with the five faces dropped, the layers as kept batches
with the state copied from the face draw, the parallax offset and the spin as a world translation and turn, the
row and the pin are as briefed. The open questions are findings that change the prompt: a layer level with the
dome is hidden by the depth test (so the layers sit 0.02 to 0.10 inside; D-026 (2) amended), the sun is on the −x
face (the prompt had +x), the additive glow needs a mid-tone sky behind it, and the eye sits at 0.38 of the cube in
a race and 0.11 in Time Trial (the prompt now says so). docs/prompts/sky-vineta-k.md carries all four.
Merged: 1c964e7 into batch/m2; the row stays Original by default.
Notes: the placeholder's boxes stand on −z, out of both check cameras' view; proven by the trace and a spin
diagnostic. The sun block's depth read with geometry under the sun is unmeasured until a model covers it.
Follow-up (2026-10-21): the eye height was wrong. Astra's preview tool inverted the recorded view matrix outright
and found the eye at the sky cube's centre; the game's view is a shear (its pitch is in row 2 only), so the models
backend's −Rᵀt put it 19 units high in a race and 5 in Time Trial. eye_of now inverts the 3x3; D-026, the prompt
and models/README.md say the horizon is at y = 0. Astra's five layers (built for 0.38) are installed and drew on
both check scenes (5 faces replaced by 5 layers, 3597 and 4475 pixels changed in the sky box); the check counts the
section's layers instead of expecting 2. One of three check runs failed its kept-batches rule with the uncached
capture one level off across the whole screen (42144 pixels at tol 0, max delta 212, invisible); the next two runs
gave 0, so it is a timing flake of the slow uncached run, not the eye. The horizon's re-authoring is Astra's next step.
