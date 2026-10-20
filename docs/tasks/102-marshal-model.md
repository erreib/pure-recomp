# 102: The pit marshal as a model: the substituting backend, the model format, the menu row

Milestone: Crowd (D-025) | Branch: task/102-marshal-model | Status: OPEN

## Goal
With the Video tab's new "Crowds and people" row at Models, the six pit marshal quads on the start line's booths are
drawn as a 3D figure each, on both renderers, from a vertex-coloured model under models/ in the repository; at
Original nothing changes. This task builds the machinery of D-025: the `models` GE backend that wraps the platform's,
the `.pmdl` format and its importer from glTF, the key-to-model table, the option row and the headless check. Erik's
own marshal model may not exist when the task starts: the importer is proven on a placeholder figure the task makes
itself (a 1-unit-tall low-poly figure built by a Python script, so the pipeline and the placement are checked), and
Erik's model replaces it by name.

## Read first
- docs/decisions.md, D-025 (the design; what is not done).
- docs/research.md, "The crowd, surveyed (task 101, 2026-10-20)" (the marshal's and the crowd's draws and state).
- src/tools/record_backend.cpp whole (a wrapping backend: how it forwards every GeBackend call, how it is registered
  and how it makes its inner; the shape to copy) and vendor/portablekit/host/gpu/ge_backend.hpp 80 to 175 (the
  interface, `make_backend`, `selected_backend`, `running_backend`, `BackendRegistration`).
- vendor/portablekit/host/gpu/ge_state.hpp: `Vertex` (41 to 46), `TextureState` (59 to 75), `FogState` (188 to
  193), `DrawCall` (230 to 275), `PrimitiveType` (16 to 25).
- vendor/portablekit/host/gpu/texture_pack.hpp 77 to 125 (`compute_texture_pack_key`, `format_texture_pack_key`,
  `TexturePackOptions`).
- src/profile/enhancements.cpp 60 to 130 (`kOptions`: a row's fields) and wherever `game_option("texture_detail")`
  is read once a frame (grep) for the reading pattern; docs/controls.md's paragraph on the game rows.
- src/host/pure_main.cpp 1 to 40 (where `PURE_GE_BACKEND`'s default is set) and src/host/metal_shell.mm 385 to 400
  (the `dynamic_cast` of `running_backend()` to the texture pack host, which the wrapper must not break).
- src/gpu/metal_pipelines.mm 245 to 262 (how a file is found in the app's Resources or three levels above the
  executable: the same lookup for models/).
- tools/frame_regress.sh 1 to 60 (how a headless Metal capture of a scene is made and compared) and
  tools/texture_check.sh 1 to 30 (a check that runs a scene twice with an option off and on).
- docs/tasks/101-crowd-survey.md, Result, "The person figure" and the JSON of out/101/person/frame.json (the six
  draws: index 149 to 154, tristrip of 4 vertices, world uniform 2293.69, vertex colour 0xFFDFD9D3, alpha test
  GREATER 0x7F, depth GREATER write, stencil ALWAYS 0x04, fog on, lighting off, cull off, texture CLUT4 32x64 key
  `00000000d5085be1dbd7e4c3`).

## Facts
- The marshal's six quads: 2.03 units tall, about 1 wide, feet at y 39.41, three at each edge of the start straight
  (z -84.6 to -86.0 and -127.3 to -130.3), facing +x within about 37 degrees. The crowd quads are 2.2 to 2.5 tall.
  The road is 41 units wide; a ship 10.5 long. y is up. The world matrix is a uniform scale with no rotation, so
  object space is the track's frame scaled by 1/2293.69: a model's vertices must be given in object space (divide
  the world-space placement by the scale) or the model draw must carry its own world matrix (identity, with the
  placement done in world space): the second is simpler and both backends take the draw's own `world`.
- The texture key rule: `compute_texture_pack_key(memory, call.texture, max_seen_v, options, key, cw, ch)` with
  options {Xxh64, ignore_address true, ignore_mipmap true}; `max_seen_v` as task 101's extractor computes it
  (src/tools/ge_extract.cpp 49). The key is the HD pack's: `00000000d5085be1dbd7e4c3` for the marshal (one of six
  keys the pack maps to pitguy.zim: the others are other editions or tracks; list them all in models.ini from
  textures.ini line 2752's neighbours, `grep pitguy.zim`). Hash the texture once per (address, frame), not per
  draw: the renderer's memo is per display list.
- A quad in these strips: 4 vertices, two triangles; a crowd strip is many quads joined by degenerate triangles
  (task 101: 368 vertices, 411 non-degenerate of 1001 triangles). The front: with vertices A B C D in strip order,
  the two triangles are ABC and BCD; the quad's up is the edge along which v changes, its right the edge along
  which u increases; front = up x right (right-handed), the side from which the sprite reads unmirrored. Verify
  the sign on the marshal: the figures face +x (the survey); if the computed front points -x, flip the rule and
  say so in Result.
- Vertex colours are the GE's ABGR words (`Vertex::color`, red in the low byte). The quad's tint multiplies the
  model's colour per channel. `has_vertex_color` true and `lighting_enabled` false make both backends use the
  vertex colour as is (metal_draw.mm 601 shows the fallback when neither).
- `PURE_GE_BACKEND` is set in pure_main.cpp only when unset, "metal" on macOS and "vulkan" elsewhere; the record
  backend reads `PURE_GE_RECORD_INNER` the same way. `running_backend()` returns the backend hle_media made (the
  wrapper, once it is the default); the Metal shell casts it to `TexturePackHost`.
- Blender 5.0.1 at /Applications/Blender.app; its glTF exporter writes COLOR_0 when the mesh has a colour
  attribute and the export's "Vertex Colors" is on. A glTF is JSON plus a .bin (or one .glb); accessors give
  positions (float3), colours (float3 or float4, or normalised u8/u16) and indices (u16 or u32). Python's stdlib
  (json, struct) reads it.
- The app's Resources: `RELEASE_RESOURCES="app_resources=."` in packaging/release.env ships the contents of
  build/release/bin/app_resources; tools/bundle.sh copies config/metal_pipelines.txt there (lines 128 to 136). A
  models/ folder goes the same way (the worker adds the copy; the Windows packer's folder too,
  tools/bundle_windows.sh, under May touch).
- Game data never enters the repository; a model Erik makes is ours. The placeholder figure the task builds is ours.

## Deliverable
- `tools/model_import.py IN.gltf|IN.glb OUT.pmdl [--light X,Y,Z] [--height 1]`: reads the mesh (the first mesh's
  primitives, triangles), bakes a fixed key light into the vertex colours (Lambert with a floor: colour x (0.55 +
  0.45 x max(0, n.l)), the normals from the file or from faces), normalises the model so its feet (min y) are at 0
  and its height is 1 (or `--height`), centres x and z on the feet's bounding box, and writes `.pmdl`: magic
  `PMDL`, u32 version 1, u32 vertex count, u32 index count, then float3 positions, u32 ABGR colours, u16 indices;
  prints counts and bounds. Exits 2 on a mesh without colours (a flat grey is not wanted silently: say
  `--colour RRGGBB` to allow one).
- `tools/model_placeholder.py OUT.gltf`: a 1-unit figure of about 400 triangles (a capsule body, a head, two legs,
  two arms, two or three colours) so the pipeline runs before Erik's model exists. models/pitguy.pmdl is built from
  it by the task and replaced by Erik's export later; models/README.md says so and gives the export convention
  (y up, the front toward +z, feet at the origin, a colour attribute, glTF with vertex colours; the importer
  normalises height).
- `models/models.ini`: `[figures]` section, `<key> = <name>.pmdl figures=1` per key (the six pitguy keys), a
  comment per line naming the texture and the track; read by the backend at start and on the row's change.
- `src/gpu/models_backend.cpp` (and .hpp; registered as `models`): wraps the inner backend named by
  `PURE_GE_MODELS_INNER` (default: the platform's, "metal" on macOS, "vulkan" elsewhere; `models` refused as inner);
  every GeBackend call forwarded; `submit`: with the row at Original, or no table, or a draw whose texture is
  disabled, through-mode, clear-mode, not a strip or triangle list, or whose key is not in the table, the call goes
  through; otherwise the strip is split into quads, each quad placed as D-025 says, the model draw submitted
  (`vertices` the model's transformed to world space with the draw's own `world` set to identity and the quad's
  view and projection; `indices` the model's; `through` false; `texture.enabled` false; `has_vertex_color` true;
  `lighting_enabled` false; `material_color` white; `blend`, `depth`, `alpha_test` (keep), `viewport`, `target`,
  `fog`, stencil as the quad's; `culling_enabled` true with the winding matching the model's front faces, or off
  if the importer cannot promise it; `vertex_address` 0 and `primitive_count` the triangle count), and the quad
  itself not submitted. One `[models] frame F: N draws replaced by M model draws, K quads` line every 60 frames
  with `PURE_TRACE_MODELS=1`, and `[pure] crowd models: on (game.crowd_models)` once when the row is Models at
  start or when switched. `inner()` exposed so the Metal shell's texture pack host lookup finds the Metal backend
  through the wrapper (metal_shell.mm: try the running backend, then its inner).
- src/host/pure_main.cpp: `PURE_GE_BACKEND` defaults to `models`; `PURE_GE_MODELS_INNER` defaults as above. The
  record backend's default inner stays vulkan.
- src/profile/enhancements.cpp: the `crowd_models` row, label "Crowds and people", choices "Original" and "Models",
  description in the rows' voice ("The crowd and the figures by the track are flat pictures on the PSP. Models
  draws them as 3D figures where the port has a model for them: the start line's marshals today. Both renderers."),
  default 0, Video tab; the once-a-frame read in the backend; `PURE_CROWD_MODELS` comes with the row.
- `tools/models_check.sh [--out DIR]`: headless on the Metal backend (`PURE_GE_MODELS_INNER=metal`, no window):
  the Time Trial route to the `tt_hud` scene twice, `PURE_CROWD_MODELS=0` and `1`, the captures compared (differ
  by at least a few hundred pixels, the marshals' area), the `[models]` line's N equal to 6 for the frame, and the
  `1` capture against the scene's reference within the suite's limit for that scene plus 0.02 (the figures are
  small); PASS or FAIL printed last. Also the race route's `race_hud` scene with `1`: the `[models]` line reports 6
  (the same booths are in that frame) and the capture passes its reference the same way.
- Docs: docs/controls.md (the new row beside the others), docs/developing.md (`PURE_CROWD_MODELS`,
  `PURE_TRACE_MODELS`, `PURE_GE_MODELS_INNER`, the tools' rows, the `models` backend in the `PURE_GE_BACKEND` row),
  docs/ge-backend.md (a section on the models backend), README.md's enhancement list (one bullet) and Esc menu
  text (the row), tools/menu_check.sh's expected rows (both shells), tools/bundle.sh and tools/bundle_windows.sh
  (models/ into the resources, and the checks' file lists), docs/release.md (the resources row).

## Acceptance criteria
- [ ] `tools/model_import.py` on the placeholder's glTF writes models/pitguy.pmdl (committed; a few KB) and prints
      its counts; on a glTF without colours it exits 2.
- [ ] `tools/models_check.sh` PASSes headless: 6 draws replaced in the tt_hud frame and in the race_hud frame, the
      captures with models differ from those without, both within their references' limits plus 0.02.
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS with the row at Original (the wrapper changes nothing);
      `tools/menu_check.sh` PASS on both shells with the new row (the window: Erik's screen is booked for the two
      menu runs only).
- [ ] The texture pack still works under the wrapper: `tools/sprite_pack.sh --check --shell metal` is not rerun
      (it needs the window and the pack's row only; the shell's host lookup through `inner()` is read in the code
      and a headless run prints `[texpack]`'s "no texture pack folder" line as before, which shows the host is
      found: quote it).
- [ ] The figures stand on the booths facing +x in a headless capture at 4x internal scale of the tt_hud scene
      with models (the worker looks at it and says what it sees: six small figures on the booths at the left of
      the straight, upright, feet on the rails, the placeholder's colours).
- [ ] `tools/docs_check.py` PASS; `tools/release_check.sh` PASS on what it passed before (models/*.pmdl are
      binary: add them to the check's known binaries list by pattern, tools/release_check.sh is under May touch
      for that one rule, and say so in Result).

## Verify
`tools/build.sh profile && tools/docs_check.py && python3 tools/model_placeholder.py out/102/placeholder.gltf && python3 tools/model_import.py out/102/placeholder.gltf out/102/placeholder.pmdl && tools/models_check.sh --out out/102/check && tools/frame_regress.sh`

The menu check on both shells is run once each after the headless parts pass (two window runs; the screen is
booked for them).

## May touch
- src/gpu/models_backend.cpp, models_backend.hpp (new), CMakeLists.txt (their lines and the resources copy),
  src/host/pure_main.cpp, src/host/metal_shell.mm (the host lookup through the wrapper's inner only),
  src/profile/enhancements.cpp
- tools/model_import.py, tools/model_placeholder.py, tools/models_check.sh (new); tools/menu_check.sh,
  tools/bundle.sh, tools/bundle_windows.sh, tools/release_check.sh (the binaries rule's pattern only)
- models/ (new: models.ini, pitguy.pmdl, README.md)
- docs/controls.md, docs/developing.md, docs/ge-backend.md, docs/release.md, README.md
- docs/tasks/102-marshal-model.md (Result)

## Must not touch
- vendor/ (no patch: the wrapper is a registered backend, the key rule and the option mechanism are used as
  exported), include/psprecomp/, tools/regen.sh, the corpus
- src/gpu/metal_*.mm and the shaders (a model draw is an ordinary draw to the backend)
- docs/status.md, docs/decisions.md

## Estimated turns
45

## Escalate when
- A model draw cannot be expressed as a `DrawCall` both backends draw the same way (a field the Vulkan renderer
  reads from guest memory by `vertex_address` rather than from `vertices`): name the field and the line, BLOCKED.
- The wrapper as the default backend breaks a tool's assumption (`--backend` names, the record backend's inner,
  the Metal shell's host lookup) that `inner()` does not mend: list the tool and the line, BLOCKED.
- The headless capture's reference comparison cannot pass with figures in the picture at any sane allowance
  (the figures are a few hundred pixels at 1x): report the figures and the diff image's location, PARTIAL, and
  keep the differ-from-Original rule.

## Result
Status: DONE

Changed:
- src/gpu/models_backend.cpp, src/gpu/models_backend.hpp (new): the `models` backend. It wraps `PURE_GE_MODELS_INNER`'s backend (refuses `models`) and forwards every call. With the row at Models it keys each candidate draw's texture once per texture and frame (the pack's rule), splits strips and lists into quads, and submits one placed model draw per figure, built as the Deliverable lists. Culling is off. It prints `[pure] crowd models: off|on (game.crowd_models), drawn by NAME` and, with `PURE_TRACE_MODELS=1`, the `[models] frame F: ...` line every 60 frames and for each captured frame (ending in `(captured)`). `WrappingBackend::inner()` is in the header.
- CMakeLists.txt: the source line, built on every platform.
- src/host/pure_main.cpp: `PURE_GE_BACKEND` defaults to `models` on every platform. `PURE_GE_MODELS_INNER` defaults to metal, or vulkan under the Vulkan shell, and to vulkan elsewhere (`_putenv_s` on Windows). The record backend's inner default is unchanged.
- src/host/metal_shell.mm: the texture pack host lookup tries the running backend, then `WrappingBackend::inner()`.
- src/profile/enhancements.cpp: the `crowd_models` row, "Crowds and people", Original/Models, default 0, Video tab, worded as the brief asks.
- tools/model_placeholder.py, tools/model_import.py, tools/models_check.sh (new). models/README.md, models/models.ini (the six pitguy keys, one comment each naming the texture, the track and the pack's ini line), models/pitguy.pmdl (6256 bytes, from the placeholder).
- tools/bundle.sh and tools/bundle_windows.sh: models/models.ini and models/*.pmdl go into Contents/Resources/models and into the Windows folder's models/, which is also added to the expected file list. tools/release_check.sh: `KNOWN_BINARY_PATTERNS = ("models/*.pmdl",)`, the binaries rule's pattern only (with its messages). tools/menu_check.sh: the new row in both shells' lists. The check now runs through the models backend over the shell's own (`--backend models --env PURE_GE_MODELS_INNER=<shell>`, and internal scale 1 kept for Metal), so the Metal window run proves the shell's pack host lookup through `inner()`.
- docs/developing.md: the source row; `PURE_CROWD_MODELS`, `PURE_GE_MODELS_INNER` and `PURE_TRACE_MODELS`; the three tools; `models` in the `PURE_GE_BACKEND` and `--backend` rows; the pure_main row.
- docs/ge-backend.md: the models row in sections 3 and 5, and a new section 9, "The models backend".
- docs/controls.md (the row, six rows now, the env lock, `game.crowd_models`), docs/release.md (the `Resources/models/` row and the Windows `models/` row), README.md (one enhancement bullet, and the row in the Esc menu text).

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
verify 102: PASS
```
The models check inside the same Verify run:
```
tt_hud      0 frame 5890: 0 replaced, 0 model draws, 0 quads  0.0112       -   32 PASS
tt_hud      1 frame 5890: 6 replaced, 6 model draws, 6 quads  0.0128    0.14   32 PASS
race_hud    1 frame 6016: 6 replaced, 6 model draws, 6 quads  0.0148    0.12   32 PASS
tt_hud 1 against 0: 218 pixels differ at tol 24 (at least 150): PASS
run 1: [texpack] no texture pack folder at .../out/data/frame_regress/textures/UCUS98612
models_check: PASS
```
- The importer: on the placeholder, `228 vertices, 1296 indices (432 triangles), 6256 bytes; bounds x -0.247..0.247 y 0.000..1.000 z -0.097..0.097`. On the same figure without COLOR_0 (`model_placeholder.py --no-colour`) it exits 2, and with `--colour 808080` it runs. It also reads a real Blender 5.0.1 GLB export: a scaled, translated sphere with a byte colour attribute came out height 1 with the right colours and node transform.
- The wrapper at Original changes nothing: the 18-scene suite run through it (`--env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env PURE_INTERNAL_SCALE=1 --env PURE_CROWD_MODELS=0`) matched the plain metal run's 18 shots at tol 0 with 0 pixels different.
- The texture pack under the wrapper: headless prints `[texpack] no texture pack folder at .../textures/UCUS98612` as before. In the Metal window, menu_check under the wrapper lists the Texture pack row and its rows, so the shell finds the host through `inner()`.
- Window runs, once each: `tools/menu_check.sh`, Video ok (19), all tabs, `menu_check: PASS`. `tools/menu_check.sh --shell vulkan`, Video ok (22), `menu_check: PASS`.
- release_check: paths, names, size, binaries (`4 binary files`, the known three and models/pitguy.pmdl), keys and tokens PASS. `home` FAILs on patches/0029-windows-file-url.patch:10,33,56 and patches/README.md:78,613,614 (`C:/Users/...`, `/Users/...`). This task touches no file under patches/, so the failure was there before.

What the capture showed (4x headless tt_hud, Models, out/102/x4/shots/tt_hud.png, crop out/102/x4/marshals_crop.png): three small figures stand on the booth at the left of the straight. They are upright, their feet on the booth's deck with the legs behind its railing, in the placeholder's colours: grey legs, orange body and arms, a white head. All three show their yellow visor to the camera, so they face +x. The other three quads are replaced too (6 quads) but are off screen in this frame.

The first capture had the middle figure showing the back of its white helmet. The cause: D-025's rule (front = up x right) gives +x for draws 149-151 but -x for 152-154. The game draws those three with u reversed, the same sprite mirrored; a cut-out drawn without culling shows a front from either side. No single sign makes all six face +x, so flipping the rule would only swap which three face away. The backend now keeps the rule for the axis and turns each quad's front toward the viewer, the eye of the draw's view matrix. That is the side the PSP shows, and +x for all six from the race. One more fact on the rule: from +x the camera sees 149-151 with u increasing to its left.

Open questions:
1. The front rule (above) is my choice and needs review. Its cost: a figure turns round when the camera crosses its plane, at the moment it is edge-on, as the ship passes the booths. Two alternatives would keep the figures fixed: remember each quad's first-seen side (keyed by its position), or a static rule such as facing the road. D-025 may want amending either way.
2. The Vulkan renderer drawing the model draws is untested; no window run with the row at Models was booked. Window checks this change needs: tt_hud with Models in the Vulkan window (`tools/frame_regress.sh --shell vulkan --backend vulkan --only tt_hud --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=vulkan --env PURE_CROWD_MODELS=1`) and the same in the Metal window. The model draws carry `vertex_address` 0 as the brief says. The Vulkan renderer's frame interpolation recognises draws across frames by these fields, so the figures with interpolation on are unverified.
3. tools/purelib/port.py's `ENHANCEMENTS_OFF` does not pin `PURE_CROWD_MODELS` (the file is not under May touch). The default is Original, so tool runs are unaffected unless a data directory's settings.ini says otherwise. When the default becomes Models, it belongs there.
4. D-025 counts the option's draws in the perf line's enhanced draws. Not done: the counts are in the `[models]` trace only.
5. menu_check now runs through the models backend, a change of that check's backend: deliberate, see Changed.
6. The Windows side is not built here: pure_main's `_putenv_s` branch and bundle_windows.sh's models/ copy and list need the rig.
7. models_check's differ threshold is 150 pixels at tol 24 (the placeholder moves 218). A model of Erik's that looks much like the cut-out could fall under it.
8. race_hud with Models scores 0.0148 against its measured 0.0149. Its six marshals are replaced but barely change the picture, likely off screen or hidden in that frame. Not inspected.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
