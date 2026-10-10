# 063: A target sampled as a texture takes the GE's wrap mode (the billboard screens)

Milestone: M8 fidelity (difference 15) | Branch: task/063-fb-texture-wrap | Status: OPEN

## Goal
The track-side advert screens show a flat colour with vertical bars where PPSSPP (and a video of the game) show the
advert's picture: docs/fidelity.md difference 15. Each advert is drawn into a 128x128 16-bit target (four rounds a
frame, docs/ge-effects.md item 2) and the screen is then drawn with that target as its texture, with the texture
scale v = -1, offset 0 and the wrap mode REPEAT (`tools/gerec/gerec_dump.py` on out/gerec/race_1x.gerec, draws
#26, #43, #63, #76 of frame 6016: u and v in [0, 0.992], scale (1, -1), offset (0, 0), wrap (0, 0)). The GE's REPEAT
takes the coordinate modulo 1, so -v becomes 1 - v: the advert, upside down. Both backends instead clamp a target
texture's coordinate at the target's edge (Metal: the sampler for a target texture is clamp on both axes,
src/gpu/metal_draw.mm "sampler = ... | 4u | 8u"; Vulkan: `push.texture_params[0] = 1.0f` drops the wrap flags for a
framebuffer texture and `frag_uv_rect` clamps, vendor/portablekit/host/gpu/vulkan_renderer.cpp around line 6700 and
shaders/ge.frag), so -v clamps to 0 and the screen shows the advert's first row stretched into bars. After this task
both backends apply the GE's wrap in the texture's own coordinate space before placing the texture in the target
image, and the screens show the adverts.

Evidence to read first, in the main checkout (read-only): /Users/erreib/dev/pure-recomp/out/billboard/:
ppsspp/f07600.png (PPSSPP, race time 0:03.4, the orange advert with its sunburst and text at about x 182-208,
y 118-138), shots2/g6490.png (the port, 0:03.9, the same screen as flat bands at about x 176-212, y 106-135),
crop_pp_big.png and crop_port_big.png (both enlarged), and ppsspp2/q*.png (PPSSPP every 20 frames from 7580, the
port's flips 6430 to 6710 are shots2/g*.png; the adverts differ between the two, the cycle is seeded from the clock).

## Read first
- CLAUDE.md, docs/fidelity.md (difference 15), docs/ge-effects.md (item 2), docs/metal-backend.md ("Targets",
  "Textures", "Texture mapping modes": `uv_remap` already places a texture inside the image for modes 1 and 2),
  docs/ge-backend.md section 6 (the Draw record's TextureState: scale, offset, wrap_s, wrap_t)
- src/gpu/metal_draw.mm (draw(): the `find_framebuffer_texture` branch and `uv_transform`), src/gpu/shaders/ge.metal
  (ge_vertex's `out.uv`, `sample_texture`), src/gpu/metal_pipelines.mm (the sampler table's address modes)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (the framebuffer-texture branch after `framebuffer_source`,
  `wrap_flags`, `uv_transform`), vendor/portablekit/host/gpu/shaders/ge.vert (`frag_uv_rect`) and ge.frag (the wrap
  block in main()), patches/README.md (how a vendor change becomes a patch)
- tools/gerec/metal_check.sh, tools/frame_regress.sh, tools/png.py (read_png)

## Deliverable
1. **Metal.** For a draw whose texture is a target (`source != nullptr`): the vertex shader hands on the texture's
   own coordinate (st * scale + offset, nothing else), and the fragment shader applies the GE's wrap per axis in
   that space (REPEAT: fract; CLAMP: clamp to [0, 1], then to the half-texel inside the edge as the Vulkan shader
   does), then places it in the image (`uv_remap`-style: * texture size / 480x272 + the texel origin). The sampler
   stays clamp on both axes (the image is the whole target). Ordinary textures are untouched (the sampler wraps
   them as today). A new fragment-uniform flag or the existing `uv_remap` path, as you judge; a pipeline key
   change is acceptable only if unavoidable (it changes config/metal_pipelines.txt: say so).
2. **Vulkan**, as a vendor patch `0015-vulkan-fb-texture-wrap`: for a framebuffer texture keep the wrap flags, pass
   the texture's own scale and offset, and in ge.frag apply fract or the clamp per axis before the placement into
   the copy's sub-rectangle (replacing the `frag_uv_rect` clamp for this case; the clamp stays for ordinary
   textures). `tools/patches.sh export 0015-vulkan-fb-texture-wrap`; a row in patches/README.md.
3. **tools/billboard_check.sh** (new): runs the race route headless on Metal to flip 6490 (as tools/frame_regress.sh
   runs main_menu.txt+single_race.txt: an empty memory stick, PURE_GAME_DIR, the scratch data directory) with a
   shot at 6490, takes a rectangle strictly inside the orange screen's surface (choose it from the capture; about
   x 182-208, y 112-130), and prints two numbers over it: the mean absolute luminance difference between vertically
   adjacent pixels and between horizontally adjacent ones (tools/png.py). Before the fix the vertical number is
   near the screen's shading alone (measure it: it is the "before"); after, the advert's picture gives a vertical
   number of the same order as the horizontal one. PASS when the vertical number is at least a threshold you set
   from the measurements with a margin (state the before, after and PPSSPP-side numbers in the Result; measure
   PPSSPP's on ppsspp/f07600.png's screen for the order of magnitude). `--backend vulkan --shell vulkan` runs the
   same in the Vulkan window. Exit 0 on PASS.
4. docs/fidelity.md difference 15: state "fixed (task 063)" with the mechanism in one sentence; docs/metal-backend.md
   "Textures": one paragraph on the wrap for a target texture; docs/ge-effects.md item 2: "(flipped)" was right, say
   the GE's REPEAT does it.

Order: Metal first (commit), the check (commit), then Vulkan (commit), docs (commit).

## Acceptance criteria
- [ ] `tools/billboard_check.sh` PASS on Metal headless and with `--backend vulkan --shell vulkan`; the Result shows
      the before and after crops (paths) and the numbers.
- [ ] `tools/frame_regress.sh` 18/18 headless; the race scenes may move by the billboards' pixels only (say by how
      much; race_hud's limit is 0.10); `tools/gerec/metal_check.sh` PASS (Metal and Vulkan agree after both fixes).
- [ ] race_1x.gerec frame 6016 replayed and cut after draw #26, before and after, on both backends: the billboard's
      footprint changed from bars to a picture, the rest of the frame identical (ge_replay --cut, --out; state the
      pixel counts).
- [ ] No ordinary texture changes: a capture of the frontend (`lang`, `title`, `main_menu`) is pixel-identical before
      and after on Metal headless (`tools/refactor_check.sh --before` on the starting commit, then after: the three
      frontend scenes 0 differing pixels; the race scenes are expected to differ).

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/billboard_check.sh`

## May touch
- src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp, src/gpu/metal_types.hpp, src/gpu/shaders/ge.metal,
  src/gpu/metal_pipelines.mm (only if the sampler table must change), config/metal_pipelines.txt (only if the key
  changes)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/shaders/ge.vert, ge.frag: through
  `tools/patches.sh export 0015-vulkan-fb-texture-wrap` (commit patches/, never vendor/), patches/README.md
- tools/billboard_check.sh (new), docs/fidelity.md (row 15), docs/metal-backend.md ("Textures"), docs/ge-effects.md
  (item 2), docs/verification.md (one row for the new check)

## Must not touch
- vendor/portablekit/include/psprecomp/, the GE state (ge_state.*), src/host/, src/profile/, tools/frame_regress.sh,
  tools/gerec/, ref/, the texture decode, the dither and 16-bit paths (task 040), anything not listed above

## Estimated turns
50

## Escalate when
The wrap cannot be applied without changing what ordinary textures sample (the frontend scenes move); the Vulkan
copy's sub-rectangle is not where the shader can wrap into it (report what `framebuffer_descriptor` hands over);
the screen after the fix shows the advert but mirrored or offset by a row against PPSSPP's (a half-texel or flip
polarity question: report both pictures and stop, do not tune by eye); a pipeline key change that invalidates the
pre-warm list beyond adding keys.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
