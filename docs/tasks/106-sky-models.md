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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
