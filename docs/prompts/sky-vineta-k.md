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
sits at (0.02, 0.38, −0.02): the horizon as seen from the camera is therefore at Y = 0.38 across the sides, not at
0. +Y is up. The engine scales the cube to 50 game units and draws it around the camera every frame.

**Depth rule, important.** Nothing may come nearer the origin than the faces (distance 1.0 along an axis, that is,
keep every vertex at |X| ≥ 1 or |Z| ≥ 1 or Y ≥ 1, the way the five faces are) and nothing beyond the cube's corners
(distance 1.73 from the origin). The game reads the sky's depth for its sun effect, so the sky must sit where the
faces were. Practically: build everything on or just outside the cube's surface, like a shell, with relief no
deeper than 0.1 inward of the corners.

**Layers.** Deliver separate meshes, each its own glTF, drawn back to front by the engine:
1. `dome`: the sky itself, a shell of the cube's five faces (or a hemisphere clipped to the cube) with a vertical
   colour gradient: white haze at the horizon band (Y 0.3 to 0.5), warm to blue upward, the top blue. About 500
   triangles. The engine draws it first.
2. `clouds_high`: the top's cloud mass and a few scattered clouds as flat or slightly puffed shapes lying on the
   shell just inside the dome's surface (relief toward the origin by up to 0.05), yellow-lit on their sun side
   (−X), lilac shadows. 400 to 800 triangles.
3. `horizon_far`: the mountains (behind the city on −Z and the ridge on +Z's left), as silhouettes with two or
   three shades, standing on the horizon band of the shell. About 600 triangles.
4. `horizon_city`: the city on −Z: eight to fifteen towers of varied height and width, boxy, with a lit face toward
   −X and a shaded face, a quay line, palm trees as simple fans; the towers' bases at the horizon (Y 0.38), the
   tallest up to Y 0.75. 1500 to 2500 triangles. Keep the +X face and the top's −X quarter free of tall geometry:
   the sun and its flare are drawn by the game there.
5. `sea` (optional): a flat band just below the horizon on +Z, −X and +X with a blue-to-silver gradient toward
   the sun. About 100 triangles.
Total about 5000 triangles. The engine moves layers 3 and 4 slightly against layer 1 as the ship travels
(parallax), so model them as separate meshes and do not merge them into the dome.

**Conventions, as for the figures.** A Blender Python (bpy) script named `model_sky_vineta_k.py`, to live in the
repository's tools folder beside `model_pitguy.py` and `model_crowd.py`, run headless:
`Blender --background --python-exit-code 1 --python <the script> -- out/sky-vineta-k`. It writes
the editable .blend, one GLB per layer (`dome.glb`, `clouds_high.glb`, `horizon_far.glb`, `horizon_city.glb`,
`sea.glb`), a manifest JSON with triangle counts and bounds, and three preview renders from the camera's point
(0.02, 0.38, −0.02) looking −Z, +Z and up. Blender axes: build with Blender's Z up and −Y as the game's +Z (the
glTF exporter's Y-up conversion then gives the game Y up and +Z as described). Vertex colours in a Color
Attribute, no materials with textures. Validate in the script: every vertex satisfies the depth rule above, each
layer's triangle count is within its budget, and the exported GLB reimports with the same bounds.

Keep the style readable from the inside at the size it is drawn (the sky fills the view; a tower is about 50
pixels tall on screen): bold shapes, few colours, no fine detail. Report what you built, the counts, and anything
you had to decide.
