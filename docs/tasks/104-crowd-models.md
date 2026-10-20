# 104: The crowd as models: a figure set along each stand quad, batched, with a distance rule

Milestone: Crowd (D-025) | Branch: task/104-crowd-models | Status: OPEN

## Goal
With the "Crowds and people" row at Models, the grandstands of Vineta K (and every track whose crowd key the HD pack
lists) are filled with 3D spectators from Astra's figure set in place of the flat crowd rows: several figures along
each quad's width, chosen by a hash of the place so the same people stand in the same spots every frame, batched
into few draws, thinned with distance so a race frame stays within budget. The marshals keep working. The check
counts the replaced draws on the race route and the cost is measured.

## Read first
- docs/decisions.md, D-025; docs/research.md "The crowd, surveyed (task 101)" (the four strip draws, about 205 quads,
  2.2 to 2.5 units tall, 5.3 to 12.9 wide, each quad one row of the 64x64 sheet: a u span of 0.5 or 1 running past 1
  with the wrap, so a quad shows about 8 to 16 figures; the stands' GE state; the `crowd_background` behind).
- src/gpu/models_backend.cpp: the table reader (343 to 410: `figures=`, `clip=`), `Model` and the cache (97 to
  140, 170 to 230), `replace` and the figure loop (700 to 775: one draw per figure today), the trace (325 to 370).
- models/README.md (the crowd starter section, the format) and models/models.ini.
- docs/tasks/102-marshal-model.md and 103-animated-models.md, Result and Review (what exists; the check's rows).
- tools/models_check.sh whole (the rows; how a route is run and captured; the boxes).
- out/crowd-starter/manifest.json (the eight figures: names, poses, 337 to 349 triangles, 297 to 315 vertices
  each, static, version 1 .pmdl files already made by the importer).

## Facts
- The crowd keys in the HD pack's textures.ini: nine lines map to `in_game/tracks/00_shared/crowd.zim` (lines
  2739, 2932, 3224, 3342, 3506, 3696, 4630, 4738, 4814; `grep -n crowd.zim ~/Downloads/WipEout-Pure-HD-Texture-Pack/
  textures.ini`); Vineta K's is `00000000062cb021471694d4`. The ini's comments or neighbouring lines name the track
  of each; write the track in the models.ini comment as the marshal lines do.
- The crowd draws: triangle strips of 113 to 381 vertices, about 205 quads in all per frame, two stands 146 units
  long either side of the start straight, 4 draws a frame on the race route (471, 472, 615, 616 in the race frame);
  the quad's vertex colour is a per-stand tint (white, or 0xFFB7B0A8); alpha test GREATER 0x7F, fog on, depth
  written, stencil 0x04, in the opaque pass. The backend already splits strips into quads and copies the state.
- Cost: a figure is about 340 triangles and 310 vertices; 205 quads x 10 figures x 340 = 700 k triangles, against
  about 60 k in a race frame today (task 101's extraction: 61692 faces). A u16 index buffer takes 65535 vertices,
  so about 200 figures fit one draw. The Metal backend uploads a draw's vertices each submit; 2000 separate draws a
  frame would cost more than the triangles: batch.
- The backend knows each draw's view matrix, so the eye's distance to a quad is known (task 102 computes the eye
  for the first-sight rule).
- The stands' far rows are small on screen: at 1x a figure 2.3 units tall 300 units away is a few pixels.
- Astra's figures: y up, front +z, feet at the origin, height 1 after import; varied colours and poses, no rig.
  Game data never enters the repository; the figures are ours (built from primitives and a palette). Their
  .pmdl files (about 8 x 7 KB) go under models/crowd/.

## Deliverable
- models.ini grows a set syntax: `<key> = set=crowd spacing=0.85 [near=120 far=300] [tint=1]`, with
  `[set crowd]` sections listing files (`crowd/01_graphite_tee.pmdl` ...), one per line. `spacing` (units) gives
  the figures per quad as `max(1, round(width / spacing))` in place of `figures=N` (which stays for the marshal);
  `near` and `far` (units from the eye to the quad's base) give the density rule below. The reader reports a set
  with no files, a missing file, or a line with neither `figures` nor `spacing`.
- The backend: for a set, figure f of a quad takes model `hash(place, f) % set size`, a yaw jitter of ±12 degrees
  and a height jitter of ±6% from the same hash (deterministic per place), standing on the quad's base at its
  across position as today. Density by distance d from the eye to the quad's base: every figure under `near`,
  every second one between `near` and `far`, every fourth beyond `far` (the chosen ones by `f % 2 == hash bit`, so
  the same figures stay when the camera moves across a boundary), and a stand tint applied as for the marshal.
  Batching: the figures of one original draw are appended into as few `DrawCall`s as the u16 index space allows
  (vertices and indices concatenated with offsets; one draw per 65535 vertices), each with the quad's state; the
  `[models]` line reports draws replaced, model draws, quads and figures, and `vertices` submitted. The marshal's
  path (figures=1, a clip) is unchanged and may share the batching.
- models/crowd/*.pmdl: the eight figures imported from out/crowd-starter/*.glb with the committed importer (do not
  copy the starter's .pmdl files: run `tools/model_import.py` on each GLB so the files are the importer's current
  output), and models/models.ini's nine crowd lines and the `[set crowd]` section; models/README.md's set syntax.
- tools/models_check.sh: the race route's `race_hud` row at Models gains the crowd: `[models]` reports 4 crowd
  draws replaced (plus the marshals), the figure count printed, the capture differs from Original by at least 2000
  pixels at tol 24 (the stands fill), the HUD found by tools/hud_check.py; the reference rule for this row becomes
  "within the scene's limit plus 0.10" (new art fills a fifth of the picture: print the figure, decide on the
  differ and HUD rules). The tt_hud rows unchanged (no crowd in that frame? if the Time Trial frame has crowd
  quads, say so and keep the marshal rules on the marshals' box).
- A cost measurement in Result: the race route headless at 1x and 4x with the row at Original and at Models, the
  frame time from `PURE_PERF=log` (or the run's wall time if headless prints no perf line: say which), the
  `[models]` figure and vertex counts at the race_hud frame, and the same in one Metal window run of the race
  route (`PURE_PERF=log`, the screen is booked for this one run) comparing render ms with the crowd on and off.
  If the window race drops under 60 fps at the default internal scale with the crowd on, raise the density
  thresholds (near 80, far 200) and measure again; say what was chosen.
- Docs: docs/ge-backend.md's models section (sets, density, batching), docs/developing.md (the check's row,
  models.ini's syntax if it is mentioned), docs/controls.md's row help (the crowd now), README.md's bullet.

## Acceptance criteria
- [ ] `tools/models_check.sh` PASSes with the crowd row: 4 crowd draws replaced on race_hud, figures printed, the
      stands differ from Original by at least 2000 pixels, the HUD found; the marshal rows as before.
- [ ] A 4x headless capture of race_hud with Models is looked at: the stands either side of the straight filled
      with varied small figures standing on the tiers, the marshals on the booths, nothing floating or sunk (the
      worker says what it sees, and names any quad whose figures stand wrong with its index).
- [ ] The cost measurement is in Result with the chosen density thresholds; the race holds 60 fps in the Metal
      window at the default scale with the crowd on, or the Result says by how much it misses and why.
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS (Original unchanged).
- [ ] `tools/docs_check.py` PASS; `tools/release_check.sh` as before (the new .pmdl files match the known
      pattern).

## Verify
`tools/build.sh profile && tools/docs_check.py && tools/models_check.sh --out out/104/check && tools/frame_regress.sh`

Headless; the one Metal window run of the race route for the cost measurement is booked, once.

## May touch
- src/gpu/models_backend.cpp, models_backend.hpp
- models/models.ini, models/README.md, models/crowd/ (new)
- tools/models_check.sh
- docs/ge-backend.md, docs/developing.md, docs/controls.md, README.md
- docs/tasks/104-crowd-models.md (Result)

## Must not touch
- vendor/, include/psprecomp/, tools/regen.sh, the corpus
- src/gpu/metal_*.mm, the shaders, src/host/, src/profile/ (the row exists)
- tools/model_import.py, tools/model_crowd.py (the assets are taken as built; a figure's fault is reported, not
  fixed here)
- docs/status.md, docs/decisions.md

## Estimated turns
45

## Escalate when
- The batched draw is drawn wrong by either backend (a backend reads `primitive_count` or `vertex_address` in a
  way the concatenation breaks): name the line, PARTIAL with one draw per figure and the cost it has.
- The race cannot hold 60 fps in the Metal window at the default scale even at near 80, far 200 and a quarter
  density beyond: report the numbers; do not add a level-of-detail model (a later task with Astra).
- The crowd quads' facing under the first-sight rule gives a stand its back (the figures face away from the
  track): report which stand and the sign, and apply the opposite sign for sets only if that fixes both stands.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
