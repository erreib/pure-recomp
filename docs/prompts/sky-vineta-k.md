# Prompt for Astra: a 3D sky for Vineta K

Paste everything below the line to Astra. The reference images it names are under out/106/sky/ in the checkout
(derived from the game and the HD pack: look at them, never redistribute them, and do not sample their pixels into
the model). The game-side engine work is task 106 (docs/tasks/106-sky-models.md); the conventions here are its.

---

I need a 3D sky for the first track of a PSP racing game port, Vineta K, built the way you built the pit marshal
and the crowd figures: a Blender Python script that constructs vertex-coloured low-poly geometry from primitives
and a palette, exported as glTF with vertex colours, plus previews. No image textures: the engine draws vertex
colours only.

**What the game does today.** The sky is a cube of five flat faces (four sides and a top, no bottom) that follows
the camera, each face a 256x256 picture (1024x1024 in the HD pack). Reference pictures, upside down as the game
stores them, so flip them vertically when you look:
- `original_skybox_03.png` / `hd_skybox_03.png`: the face toward −Z, the city: a row of glass towers of several
  heights on a quay, palm trees along it, lower blocks and mountains behind, a blue sky with yellow-lit clouds.
- `original_skybox_01.png` / `hd_skybox_01.png`: +Z, the sea with cloud reflections, a dark mountain ridge on the
  left, a white sunlit sky above.
- `original_skybox_02.png` / `hd_skybox_02.png`: −X, the sea meeting the city's edge on the right, the sun's glow
  on the left near the horizon, white sky.
- `original_skybox_04.png` / `hd_skybox_04.png`: +X, open sea under yellow clouds, a white sky.
- `original_skybox_top.png` / `hd_skybox_top.png`: +Y, blue sky with a large yellow-lit cloud mass.
The mood: late afternoon, a low sun toward −X, warm yellow clouds on blue, a white haze at the horizon.

**The space you model in.** A unit cube centred on the origin: the faces at ±1 on X and Z, the top at Y = +1, the
floor at Y = −1 (there is no bottom face; the ground is the game's own geometry below the horizon). The camera
sits at the origin, the cube's centre, in every camera mode (an earlier version of this prompt said 0.38 above it
in a race and 0.11 in Time Trial; that was an error in the engine's reading of the game's sheared view matrix,
found 2026-10-21): the horizon as seen from the camera is at Y = 0 on all four sides. Author the horizon band at
Y = 0, the sky above it and the sea below it. +Y is up. The engine scales the cube to 50 game units and draws it
around the camera every frame.

**Depth rule, important.** The dome layer sits exactly on the cube's five faces (every vertex at |X| = 1 or
|Z| = 1 or Y = 1). Every other layer sits a little inside the dome, between 0.02 and 0.10 nearer the origin than
the face it belongs to (the engine's depth test hides anything level with the dome, and the game reads the sky's
depth for its sun effect, so nothing may come nearer than 0.9 of a face). Nothing beyond the cube's corners
(distance 1.73 from the origin). Practically: a shell, with the clouds, the mountains and the city as thin relief
just inside it.

**Layers.** Deliver separate meshes, each its own glTF, drawn back to front by the engine:
1. `dome`: the sky itself, a shell of the cube's five faces (9 x 9 vertices a face, rows placed at the gradient's
   stops) with a vertical colour gradient: a pale haze at the horizon band (Y 0.3 to 0.5) that stays a mid tone
   toward −X where the sun is, warm to blue upward, the top blue. About 600 triangles. The engine draws it first.
2. `clouds_high`: the top's cloud mass and a few scattered clouds as flat or slightly puffed shapes lying on the
   shell just inside the dome's surface (relief toward the origin by up to 0.05), yellow-lit on their sun side
   (−X), lilac shadows. 400 to 800 triangles.
3. `horizon_far`: the mountains (behind the city on −Z and the ridge on +Z's left), as silhouettes with two or
   three shades, standing on the horizon band of the shell. About 600 triangles.
4. `horizon_city`: the city on −Z: eight to fifteen towers of varied height and width, boxy, with a lit face toward
   −X and a shaded face, a quay line, palm trees as simple fans; the towers' bases at the horizon (Y 0), the
   tallest up to Y 0.40. 1500 to 2500 triangles. Keep the −X face's upper half and the top's −X quarter free of
   geometry: the sun sits on the −X face and the game draws its glow and flare there, additively, so the sky
   behind it must stay a mid tone (a warm orange to blue, not white haze: the glow adds 16 to 72 per channel and
   vanishes against anything paler than about 215).
5. `sea` (optional): a flat band just below the horizon on +Z, −X and +X with a blue-to-silver gradient toward
   the sun. About 100 triangles.
Total about 5000 triangles. The engine moves layers 3 and 4 slightly against layer 1 as the ship travels
(parallax), so model them as separate meshes and do not merge them into the dome.

**Conventions, as for the figures.** A Blender Python (bpy) script named `model_sky_vineta_k.py`, to live in the
repository's tools folder beside `model_pitguy.py` and `model_crowd.py`, run headless:
`Blender --background --python-exit-code 1 --python <the script> -- out/sky-vineta-k`. It writes
the editable .blend, one GLB per layer (`dome.glb`, `clouds_high.glb`, `horizon_far.glb`, `horizon_city.glb`,
`sea.glb`), a manifest JSON with triangle counts and bounds, and three preview renders from the camera's point,
the origin, looking −Z, +Z and up. Blender axes: build with Blender's Z up and −Y as the game's +Z (the
glTF exporter's Y-up conversion then gives the game Y up and +Z as described). Vertex colours in a Color
Attribute, no materials with textures. Validate in the script: every vertex satisfies the depth rule above, each
layer's triangle count is within its budget, and the exported GLB reimports with the same bounds.

Keep the style readable from the inside at the size it is drawn (the sky fills the view; a tower is about 50
pixels tall on screen): bold shapes, few colours, no fine detail. Report what you built, the counts, and anything
you had to decide.

## Revision for a sky already built (2026-10-21)

Your `tools/model_sky_vineta_k.py` delivery imported cleanly and draws in the game, with the five faces replaced
and the depth rule holding. One correction, and it is ours: your `preview_sky_in_level.py` was right that the
recorded camera sits at the sky cube's centre. The game's view matrix is a shear, not a rotation, and the engine
read it as a rotation; that is what produced the "0.38 in a race, 0.11 in Time Trial" eye in the first prompt. The
engine is fixed, and the rule is now simply: **the eye is the origin and the horizon is at Y = 0** in every camera
mode.

Please revise the script so the horizon sits at Y = 0: the sea's top edge, the quay, the towers' bases and the
foot of the ridges all at 0 (the towers up to about Y 0.40, the ridges to about 0.55, the clouds between 0.45 and
the top), the haze band of the dome centred on 0, and the previews rendered from the origin. Keep everything else
as it is: the layers, their names, the draw order, the depth placement (your dome at 1.045 with the relief layers
between 1.001 and 1.032 drew correctly), the palette, the free −X upper half. Rebuild to the same folder; the
import lines are unchanged.
