# models/

The 3D figures the models backend draws in place of the game's flat ones when the Video tab's "Crowds and people" row
is at Models (task 102, D-025; docs/ge-backend.md, "The models backend"). Everything here is ours: no byte of the
game. The app ships the folder in its resources (tools/bundle.sh, tools/bundle_windows.sh); a checkout's build finds
it three levels above the executable.

- `models.ini` maps a texture's HD pack key to a model (`[figures]`, `<key> = <name>.pmdl figures=N`; the file says
  how). The six pitguy keys are the pit marshal's texture on six tracks.
- `pitguy.pmdl` is the pit marshal. Today it is the **placeholder** figure `tools/model_placeholder.py` builds (a
  432-triangle outline: grey legs, an orange body and arms, a white head with a yellow visor on its front), made by
  `python3 tools/model_placeholder.py out/102/placeholder.gltf` and
  `python3 tools/model_import.py out/102/placeholder.gltf models/pitguy.pmdl`. Erik's model replaces it by name.

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

## The .pmdl format

Little-endian: the magic `PMDL`, u32 version (1), u32 vertex count, u32 index count, then the float3 positions (the
model's frame above, height 1), the u32 colours as the GE's ABGR words (red in the low byte, the light baked in) and
the u16 indices, three a triangle. The backend draws the triangles without culling, so the winding does not matter.
