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
Status: BLOCKED on the brief's second escalation condition. The race does not hold 60 fps in the Metal window at the default scale with the crowd on, even at near 80 and far 200 with a quarter density beyond far. It runs at 39 to 56 fps for about 12 seconds while the stands are in view (numbers below). Everything else is done and committed, and Verify passes.

Changed:
- models/crowd/01_graphite_tee.pmdl to 08_race_fan.pmdl (new): Astra's eight figures. Each was imported from out/crowd-starter/*.glb with `tools/model_import.py`. They have 297 to 315 vertices and 337 to 349 triangles, are version 1, and are 6790 to 7126 bytes. Each file came out byte-identical to the starter's .pmdl.
- models/models.ini:
  - the set syntax in the header;
  - the nine `crowd.zim` lines, each with its track and its line in the pack's ini: 01 Vineta K 2739, 02 Modesto Heights 2932, Blue Ridge 3224, 05 Sinucit 3342, 06 Citta Nuova 3506, Sol 2 3696, 22 Ubermall 4630, Staten Park 4738, Sebenco Peak 4814;
  - each line reads `set=crowd spacing=0.85 near=80 far=200`;
  - `[set crowd]` lists the eight files.
- models/README.md: the set syntax, and the crowd starter paragraph updated.
- src/gpu/models_backend.cpp:
  - **Reader.** It reads in two passes: first the `[figures]` lines and the `[set NAME]` sections, then it resolves them. A line takes `set=`, `spacing=`, `near=`, `far=` and `tint=0|1` (default 1). The reader reports a set with no files, a file that does not read (the rest of the set still serves), a key naming a missing or empty set, and a line with neither `figures=` nor `spacing=` (left out; before, such a line defaulted to figures=1).
  - **Figures.** A set quad stands `max(1, round(width / spacing))` figures, at most 256. Figure f's hash is `h = splitmix64(splitmix64(quantise(base)) + f)`. The model is `h % 8`, the yaw jitter ±12° comes from bits 16 to 31 and the height jitter ±6% from bits 32 to 47.
  - **Density.** The eye's distance d to the base decides: every figure under near, then `f % 2 == pick`, then `f % 4 == pick`, where pick is the place hash's low two bits mod every.
  - **Batching.** A game draw's figures (a set's or the marshal's) are appended into triangle lists with offset u16 indices, flushed before 65535 vertices. `primitive_count` is set per batch.
  - **Trace.** The line is now `[models] frame F: N draws replaced (C by a set) by M model draws, K quads, P figures, V vertices`. It then has the clip part, then `; replaced in N us, M of them the inner backend's`.
  - **Front.** The coordinator's change: the front is now the winding normal of the quad's first triangle, `cross(B - A, C - A)` of corners 0, 1, 2. It is made square to up, with no sign taken from the eye. `sides_` and its clearing are gone, and `quantise` is kept for the hashes. To give "as the GE orders them", `quads_of` stores a strip quad that starts on an odd triangle as (n+1, n, n+2, n+3).
  - **Upright set figures.** A set's figures stand on world +y with the v edge's rise as their height. The marshal keeps the old up rule.
- tools/models_check.sh:
  - run 0 also takes race_hud;
  - the line regex and printout carry the new fields;
  - both frames want 10 replaced, 4 by a set;
  - tt_hud's 150-pixel rule is counted in `MARSHAL_BOX = (108, 120, 56, 32)`, because the Time Trial frame has crowd quads too (4 draws, 1582 figures);
  - new row: race_hud 1 against 0 must differ by at least 2000 pixels at tol 24, and the HUD's two labels must be found with `tools/hud_check.py`'s `yellow()`;
  - race_hud's reference rule is now limit + 0.10 (`CROWD_SLACK`). It measures 0.0613 against a limit of 0.10, so it would pass even the old +0.02.
- Docs:
  - docs/ge-backend.md section 9: sets, density, batching and its cost, the winding rule and why the earlier rules failed, upright set figures, the trace and the check;
  - docs/developing.md: the check's row, `PURE_CROWD_MODELS` and `PURE_TRACE_MODELS`;
  - docs/controls.md: the row's help;
  - README.md: the bullet and the Esc-menu text.

What the 4x capture shows (out/104/cost/w80_x4/shots/race_hud.png, final code, looked at whole and in crops):
- **Stands.** Both stands are full of small, varied figures on every tier:
  - the right stand is dense under the canopy;
  - the left stand has rows between the arches above the "Danger" boards.
- **Facing.** Both stands face the road: faces and folded arms show from the front on both.
- **Placement.** Nothing floats or is sunk, and all figures are upright.
- **Quads that stood wrong before the upright fix.** My first capture (out/104/cost/n80_x4) had giant figures lying across the right stand's lower tiers and leaning near its top. They came from parallelogram quads, whose v edge slants 3.6 to 7.1 units along the tier with up.y between 0.31 and 0.65, for a rise of 2.3 to 2.4. These are the set draws (in frame order) and quad indices within each draw, at frame 6014:
  - draw 0: quads 5, 6, 26, 28, 37, 40, 50, 55;
  - draw 1: quads 4, 7, 17;
  - draw 2: quads 3, 33, 34, 35, 36, 62;
  - draw 3: quad 15.
  Under the upright rule they stand on their tier.
- **Marshals.** In race_hud they are too small to read. In models_check run 2's 4x tt_hud shot (out/104/check/2/shots/wave_a.png, crop out/104/marsh.png), all three marshals on the left booth face the camera (+x toward the race). Their visors show, the right arm is raised and their feet are behind the railing on the deck. So the winding rule faces the marshals and both stands the right way, and no flip was needed.

Cost (race_hud, frame 6016, headless Metal, `PURE_PERF=log`; the race's perf lines are quoted):

| run | scale | figures | vertices | frame | render |
| --- | --- | --- | --- | --- | --- |
| Original | 1x | - | - | race not reached in the perf lines; 0.3 to 1.6 ms elsewhere | - |
| Original | 4x | - | - | 3.8 ms (262 fps uncapped) | 2.9 ms |
| Models, near 120 / far 300 | 1x | 1574 | 498148 | 22.2 to 23.5 ms (42 to 45 fps) | 21 to 22 ms |
| Models, near 120 / far 300 | 4x | 1574 | 498148 | 24.8 to 28.6 ms | 23 to 27 ms |
| Models, near 80 / far 200 (chosen) | 1x | 1359 | 431905 | 19.6 to 23.2 ms | 18.2 to 21.8 ms |
| Models, near 80 / far 200 (chosen) | 4x | 1359 | 431905 | 19.8 to 21.5 ms | 17.9 to 20.0 ms |

- The cost is CPU, the same at 1x and 4x. The trace splits it: replace() takes about 12.4 ms, of which about 9.7 ms is the Metal backend's submit. That backend expands each figure's ~1035 indices into 48-byte GpuVertex entries and uploads them, about 66 MB a frame at 1359 figures. Our placement is about 2.7 ms.
- The headless race already missed 60 at 120/300, so I lowered the thresholds to the brief's 80/200 before the window run. Thinning removes only about 14%, because most of the stands are within 80 units of the start line.

The Metal window run (once; Apple M4 Pro, default internal scale 4 = 1920x1088, FIFO 120 Hz; route main_menu+single_race to frame 7500; out/104/window):

| crowd (near 80 / far 200) | frames | fps | render | figures | vertices | replace (Metal's share) |
| --- | --- | --- | --- | --- | --- | --- |
| on | 5760 to 6480 (grid, countdown, first seconds down the straight; about 12 perf lines) | 38.7 to 55.7 | 14.9 to 22.7 ms | 1359 to 1961 | 431905 to 617939 | 12.3 to 17.8 ms (9.7 to 14.6) |
| on | 6540 onward (one stand left in view, 258 figures, 3 ms replace) | 60 | 6.6 to 7.3 ms | 258 | - | 3 ms |
| off | the whole race | 60 | 4.0 to 5.6 ms | - | - | - |

- **The miss:** up to 35% under 60 fps for about 12 seconds of the start.
- **Why:** the Metal backend's de-indexing and upload of about 1.4 to 2 million vertices a frame. The triangles are not the cost.
- **What would fit:** about 900 figures or fewer on the straight. That needs halving again, by thresholds below the brief's (for example near 40, far 100), a wider spacing (for example 1.2), or an indexed upload in metal_draw.mm (Must not touch). A level-of-detail model is excluded by the brief. I did not go further than the brief's rule.

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
verify 104: PASS
```
The models check in the same run:
```
tt_hud      1 frame 5890: 10 replaced (4 by a set), 15 model draws, 196 quads, 1582 figures, 500750 vertices  0.0121    0.14   32 PASS
race_hud    1 frame 6016: 10 replaced (4 by a set), 15 model draws, 196 quads, 1359 figures, 431905 vertices  0.0613    0.20   32 PASS
tt_hud 1 against 0: 171 pixels differ at tol 24 in the marshals' box (108, 120, 56, 32) (at least 150): PASS
race_hud 1 against 0: 7157 pixels differ at tol 24 (at least 2000), the HUD's labels current 125, lap 43 yellow pixels (each at least 1): PASS
tt_hud wave (Wave_On t=2.15 and Wave_On t=3.15): 312 pixels differ in the marshals' box (112, 124, 48, 22) (at least 40), 0 in the deck (112, 146, 48, 6) (at most 0): PASS
models_check: PASS
```
- `docs_check: 39 files, 0 findings: PASS`.
- `tools/release_check.sh`: binaries PASS (12 files: the known three and the nine models/*.pmdl, which the pattern covers). Only `home` FAILs, on the same six patches/ findings as tasks 102 and 103.

Open questions:
1. The 60 fps miss above is the escalation. To decide: lower thresholds, a wider spacing, or a Metal-side indexed upload (a task that may touch metal_draw.mm).
2. Window checks this change needs, not run:
   - the crowd through the Vulkan renderer (batched lists of up to 65535 vertices with `vertex_address` 0);
   - the Vulkan shell's frame interpolation with batches whose vertex counts change with the density.
3. `quads_of` swaps the first two corners of a strip quad that starts on an odd triangle (the GE's winding). If your measurement took corners 0, 1, 2 without that swap, the two agree only where no quad starts on an odd triangle. The capture shows both stands and all marshals facing correctly under the code as committed.
4. Four tracks are named without a number in models.ini (Blue Ridge, Sol 2, Staten Park, Sebenco Peak), because I found no numbering for them in the repo.
5. A `[figures]` line with neither `figures=` nor `spacing=` is now reported and left out. Before, it silently meant figures=1. All committed lines have one.
6. race_hud at Models now scores 0.0613 against the reference (Original 0.0148). frame_regress's race_hud row is unchanged because the suite runs at Original.

## Review
Verify rerun (the planning session, 2026-10-20, after the merge): `tools/models_check.sh` PASS (race_hud 10 draws
replaced, 4 by a set, 1359 figures, 431905 vertices, 7157 pixels differ from Original, the HUD found; the marshal
rows as before), and the owed window run of race_hud with the crowd through the Vulkan renderer: PASS at 0.0860
(the stands in the picture), and the Vulkan shell holds 60 fps with it at 960x544 (`[perf]` render 6.9 to 7.2 ms,
frame 16.7 ms; the replace step 5.0 ms of which the inner's submit 2.2 ms). The worker's 4x Metal capture looked
at: both grandstands full of small varied spectators on every tier, facing the road, nothing floating; the
marshals facing the race in the Time Trial crop.
Spot-read: the set reader's two passes, the hash-driven pick and jitter, the density bands with the pick bit, the
u16-bounded batching and the winding-normal front are as asked; the upright rule for set figures (world +y, the
v edge's rise as the height) was the right answer to the parallelogram quads it found. The BLOCKED status is the
brief's own escalation, taken correctly: the Metal backend de-indexes and uploads every draw's vertices each
frame (about 66 MB a frame at 1359 figures), so the race start runs at 39 to 56 fps in the Metal window at the
default scale for about 12 seconds; the triangles are not the cost, and the Vulkan renderer, which keeps indices,
holds 60. The fix is the Metal backend's and the batches' statics, task 105.
Merged: f8b403e into batch/m2, the row's default left at Original.
Notes: the quad-corner order note (open question 3) is consistent with my measurement on the extracted frames
(both gave +x for the marshals and toward the road for the stands). The Vulkan shell's frame interpolation with
changing batches is still unverified. Four tracks' numbers in models.ini are unknown to the repo; fine.
