# models/

The 3D figures the models backend draws in place of the game's flat ones when the Video tab's "Crowds and people" row
is at Models (task 102, D-025; docs/ge-backend.md, "The models backend"). Everything here is ours: no byte of the
game. The app ships the folder in its resources (tools/bundle.sh, tools/bundle_windows.sh); a checkout's build finds
it three levels above the executable.

- `models.ini` maps a texture's HD pack key to a model (`[figures]`, `<key> = <name>.pmdl figures=N`; the file says
  how). The six pitguy keys are the pit marshal's texture on six tracks.
- A crowd maps a key to a set (task 104): `<key> = set=crowd spacing=0.85 [near=120 far=300] [tint=0|1]`, with a
  `[set crowd]` section listing its files, one a line (`crowd/01_graphite_tee.pmdl` ...). A quad then stands
  `max(1, round(width / spacing))` figures across its width, figure f of a quad the set's file `hash(place, f) % size`
  with a yaw jitter of up to 12 degrees and a height jitter of up to 6% from the same hash (the same people in the
  same spots every frame), thinned with the eye's distance d to the quad's base: all of them under `near`, every
  second one from `near` to `far`, every fourth beyond `far` (the ones kept chosen by the hash, so a figure does not
  swap when the camera crosses a boundary). `tint=1`, the default, multiplies their colours by the quad's tint as for
  the marshal. The reader reports a set with no files, a missing file and a line with neither `figures=` nor
  `spacing=`. The nine crowd keys are the grandstands' sheet (`crowd.zim`) on nine tracks.
- `crowd/` holds the set: Astra's eight spectators (below), each imported by `tools/model_import.py` from its GLB.
- `pitguy.pmdl` is the pit marshal: the rigged draft below, version 2, waving (task 103). Task 102 first shipped the **placeholder** figure `tools/model_placeholder.py` builds (a
  432-triangle outline: grey legs, an orange body and arms, a white head with a yellow visor on its front), made by
  `python3 tools/model_placeholder.py out/102/placeholder.gltf` and
  `python3 tools/model_import.py out/102/placeholder.gltf models/pitguy.pmdl`; a model replaces another by its file name.

## Skies

A sky (task 106, D-026) replaces a track's five sky faces when the Video tab's **Skies** row is at Models. The five
face keys map to it in `[figures]` (`<key> = sky=vineta_k`); its `[sky vineta_k]` section lists the layers, one a
line, drawn in that order: `sky/vineta_k/dome.pmdl parallax=0`, `sky/vineta_k/clouds_high.pmdl parallax=0.001
spin=0.2`, ... (`spin=S` turns a layer about y at S degrees a second). A track without `sky=` keys keeps its faces.

- **The space.** A unit cube centred on the origin, y up: the sides at ±1 on x and z, the top at y = +1, no bottom
  (the game's ground is below the horizon). The game's eye is the cube's centre, the origin, so the horizon seen
  from the eye is at y = 0 on the sides (not 0.38: that figure, in the first prompt and D-026, came from reading the
  game's sheared view matrix as a rotation; corrected 2026-10-21). The backend draws a layer at 50 units a unit
  (the cube's half-size) about the sky cube's centre, which follows the camera.
- **The depth rule.** The game reads the sky's depth around the sun (docs/ge-effects.md, the sun block): keep every
  vertex on the cube's surface or just inside it (D-026: nothing nearer than the faces, 1.0; the prompt's relief: a
  layer over the dome comes up to 0.05 inward, since the faces' depth test, GREATER, hides what is level with the
  dome) and nothing beyond the corners (1.73).
- **The layers.** Each a static `.pmdl` (version 1), under 65535 vertices, vertex colours only (no texture), imported
  with both of the sky switches: `python3 tools/model_import.py dome.gltf models/sky/vineta_k/dome.pmdl --as-is
  --no-light` (`--as-is` keeps the file's coordinates, no normalisation or recentring; `--no-light` writes the
  author's colours with no key light baked). The dome first, then what stands in front of it.
- **The parallax.** The sky cube follows the camera, so a layer cannot stand in the world; a layer with
  `parallax=F` is moved by −F x the eye's world x and z instead, wrapped to the cube's width (100 units): a far
  layer (F 0.002, the city) slides against the dome (F 0) as the ship moves. The backend applies it as the layer's
  world translation, so its kept batch is never rebuilt for it.
- `sky/vineta_k/` holds **Astra's Vineta K sky** (`tools/model_sky_vineta_k.py out/sky-vineta-k`, 2026-10-21; five
  layers, 4101 triangles: the dome at 1.045, the high clouds, the far ridges, the city on −z, the sea), imported
  as above. Its first version has the horizon at y = 0.38, where the prompt then put the eye, so in the game it
  sits 19 units above the horizon; the prompt's revision asks for it at y = 0. The placeholder it replaced is
  `tools/model_sky_placeholder.py OUT_DIR` (a gradient dome and 12 slate boxes on −z).

## Making a model (Blender)

The convention the importer expects:

- **y up, the front toward +z, the feet at the origin.** Blender's glTF exporter turns its z up into glTF's y up
  ("+Y Up", the default), so in Blender: z up, the figure facing Blender's -y (the front view, numpad 1, looks at
  its front).
- **A colour attribute** on the mesh (Object Data, Color Attributes), painted or filled per face, and the export's
  Data > Mesh > "Vertex Colors" (Active) on, so the file carries COLOR_0. The importer refuses a mesh without one
  (exit 2) unless `--colour RRGGBB` gives it one flat colour. Textures and materials are not read.
- **Any size**: the importer scales the model to a height of 1 (its feet at 0) and centres it on its feet; the
  backend scales it to the height of the quad it replaces (the marshal's is 2.03 units).
- **No lighting to set up**: a fixed key light is baked into the colours at import (`--light X,Y,Z`, toward the
  light, default above and in front); the game draws the figures unlit, with its fog.
- **A budget**: up to 2000 triangles for the marshal; a crowd figure about 300 (D-025).
- Export as glTF 2.0 (`.glb`, or `.gltf` with its `.bin`), then:

```
python3 tools/model_import.py ~/Desktop/pitguy.glb models/pitguy.pmdl
```

The importer prints the counts and the bounds. Then run the game with the row at Models (or
`PURE_CROWD_MODELS=1`), or `tools/models_check.sh`.

## Rigged pit marshal draft

`tools/model_pitguy.py` builds the editable static draft. `tools/model_pitguy_rig.py` rigs that Blender file and
exports one skinned, vertex-coloured GLB with a 20-bone skeleton and a four-second `Wave_On` action. The right arm
signals approaching vehicles through with two forearm sweeps, then returns to rest. The root and feet stay fixed.

```
Blender --background --python-exit-code 1 --python tools/model_pitguy.py -- out/pitguy-v2
Blender --background --python-exit-code 1 --python tools/model_pitguy_rig.py -- out/pitguy-v2/pitguy.blend out/pitguy-rigged --render
```

Open `out/pitguy-rigged/pitguy-rigged.blend` and press Space to play frames 1–96 at 24 fps. The exported
`pitguy-wave.glb` includes the identical closing pose at frame 97, with clip times 0–4 seconds. The builder checks
weights, fixed feet and loop continuity, then reimports the GLB to compare deformed positions at eight times.
`--render` also writes a 12-fps PNG sequence under `preview-frames/` for encoding a preview video.

`models/pitguy.pmdl` is this GLB imported as version 2 (task 103): the importer keeps the skin and the clip, and the
backend plays it, each marshal at its own phase:

```
python3 tools/model_import.py out/pitguy-rigged/pitguy-wave.glb models/pitguy.pmdl
```

It prints `20 joints`, `1 clip`, `Wave_On: 97 keys, 4.000 s`, and checks the file: the clip's first key skinned is
within about 1e-6 of the rest positions (the bind pose is the rest pose) and its last key equals its first (the
loop). `--static` writes the rest pose as version 1 (byte for byte the static marshal of before). The importer
normalises by the rest pose only and applies the same scale and offset to the joints and the inverse bind matrices,
so no pose resizes the figure or slides its feet.

## Animation (version 2)

- **What is kept.** One skin (`skins[0]` of the mesh's node, its joints in that order, at most 255), up to four
  weights a vertex (more are reported and the four largest kept; weights not summing to 1 are reported and
  normalised; a vertex without weights binds to joint 0), every animation as a clip: translation, rotation and scale
  channels of the joints (morph weights are not read), sampled at the union of the clip's key times (STEP held,
  LINEAR interpolated, rotations slerped, CUBICSPLINE's values taken linearly), a joint without a channel at its
  rest transform. The light stays baked on the rest pose's normals: the colours do not change with the pose.
- **Which clip.** The first in the file, or `clip=NAME` on the figure's line of models.ini
  (`<key> = pitguy.pmdl figures=1 clip=Wave_On`). A name the file lacks is reported and the first clip plays.
- **Time.** The clips loop on wall time (steady_clock, each frame's step capped at 100 ms: a pause or the Esc menu
  does not skip a clip ahead), each figure offset by a hash of its place. `PURE_MODELS_CLOCK=frames` runs them on the
  shown frame / 60 s and `PURE_MODELS_SYNC=1` puts every figure at phase 0, for a reproducible capture
  (`tools/models_check.sh` uses both; docs/developing.md).
- **Blender.** An Armature modifier, named vertex groups, actions on the armature; export with Animation on and the
  skinning's "Include All Bone Influences" off (four at most). Keep the root and the feet still unless the figure
  should walk: the backend stands every figure where its quad was.

## Crowd starter assets

`tools/model_crowd.py` builds eight casual spectators inspired by the crowd atlas, using the pit marshal's
two-unit authoring height, feet at the origin and front toward Blender -Y. They have varied outfits, skin/hair
colors and static poses (relaxed, folded arms, hands on hips, clapping and cheering), at 337–349 triangles each.

```
Blender --background --python-exit-code 1 --python tools/model_crowd.py -- out/crowd-starter
```

`out/crowd-starter/crowd-starter.blend` is the editable lineup. Each figure also has an individual GLB and PMDL,
an individual preview, and a manifest entry. The GLBs are exported at the origin before the review lineup is
arranged. They have vertex colors and named anatomical part groups, but no armatures or animation clips yet.
The script checks geometry and converts every GLB with the existing importer. A scale-comparison render uses
`out/pitguy-v2/pitguy.blend` if present (`--scale-reference` overrides that source).

Task 104 imported the eight GLBs into `crowd/` (`python3 tools/model_import.py out/crowd-starter/01_graphite_tee.glb
models/crowd/01_graphite_tee.pmdl`, and so on: 297 to 315 vertices, 337 to 349 triangles, version 1, about 7 KB
each) and maps the crowd's nine keys to them as the set `crowd` (above). A figure's fault is fixed in
`tools/model_crowd.py` and imported again under the same name.

## The .pmdl format

Little-endian: the magic `PMDL`, u32 version (1 or 2), u32 vertex count, u32 index count, then the float3 positions
(the model's frame above, height 1), the u32 colours as the GE's ABGR words (red in the low byte, the light baked in)
and the u16 indices, three a triangle. The backend draws the triangles without culling, so the winding does not
matter. That is all of version 1.

Version 2 (task 103) goes on after the indices, everything in the same normalised frame:

- u32 joint count J (0: a static model, nothing follows, read as version 1);
- per joint, 106 bytes: u16 parent (an earlier or later joint's number, 0xFFFF for a root), float3 rest translation,
  float4 rest rotation (x, y, z, w), float3 rest scale, 16 floats inverse bind matrix (column-major);
- per vertex, 20 bytes: 4 x u8 joint numbers, 4 x float weights (summing to 1, unused ones 0);
- u32 clip count, then per clip: u32 name length and the UTF-8 name, float duration (seconds), u32 key count K,
  K float times (sorted, the first 0), then per joint, per key, 40 bytes: float3 translation, float4 rotation,
  float3 scale (the joint's local transform at that key).

A joint's local matrix is translation x rotation x scale, its global its parent's global times its local (a root's
is its local), and a vertex at time t is the weighted sum of (global x inverse bind) applied to its rest position.
The marshal: 2232 vertices, 20 joints, one clip of 97 keys, 172419 bytes.
