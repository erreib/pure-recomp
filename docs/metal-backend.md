# The Metal GE backend (tasks 023 and 024, 2026-10-06)

`PURE_GE_BACKEND=metal` draws the game with Metal, natively, behind the GE backend seam of D-003
(`docs/ge-backend.md`). It is `src/gpu/metal_backend.mm`, in our sources, and registers itself as `metal`. Task
023 built its skeleton (device, targets, textures, the draws of the 2D frontend, clears, blending, the alpha test,
captures) and proved it on the frame regression suite's three frontend scenes, which it draws within a few pixels
of PPSSPP: the language page, the title screen and the profile screen. Task 024 added the 3D draws: the GE's
per-vertex lighting and fog, transformed sprites expanded on the screen, and culling confirmed on the race. Against
the Vulkan backend at the same scale, the race frame 6016 is drawn alike, within one level, up to its first draw
that tests the stencil ("The 3D check" below). The stencil kept as alpha, the bloom chain and the read-backs into
guest memory are task 025; the Metal presenter in the shell is 026.

## Quick start

```sh
tools/build.sh profile
tools/frame_regress.sh --backend metal --only lang,title,profile          # the three frontend scenes (about 75 s)
tools/gerec/metal_check.sh                                                 # Metal against Vulkan through ge_replay (below)
PURE_GE_BACKEND=metal tools/run_boot.py --frames 300 out/x.log             # headless: no window, Metal still draws
PURE_GE_BACKEND=metal tools/run_boot.py --frames 700 --env PURE_METAL_LOG=1 out/x.log   # a line per draw
```

| Switch | Effect |
|---|---|
| `PURE_GE_BACKEND=metal` | draw with this backend; with the window open (no `PURE_NO_RENDER`) or without one |
| `PURE_METAL_LOG=1` | a line per draw and per new target (below). Every 600 frames and at exit the backend prints its counts either way |
| `PURE_METAL_SHELL=0` | do not hand the pictures to the window shell: the window stays black and the input script's `shot` steps capture nothing (see "The window") |
| `PURE_NO_FB_TEXTURES=1` | every texture decoded from guest memory, none read from a target (the framework's switch, as for Vulkan) |
| `PURE_NO_LIGHTING`, `PURE_NO_FOG`, `PURE_NO_CULL` | the framework's switches for bisecting 3D draws, read as the Vulkan backend reads them: lit draws drawn with their vertex colour (white without one) and no fog; no fog; nothing culled. ge_replay hands the environment to both backends, so to turn one off in Metal alone replay each backend on its own with `--out` and compare the pictures |

When Metal cannot start (no device, or the shaders do not compile), `initialize` fails with the reason and the HLE
prints `[render] GE backend metal cannot run (...)`. At start the backend prints the device and the shader compile
time (`[metal] drawing with Apple M4 Pro at 480x272, shaders compiled in 0.5 ms; pictures shown in the window`;
about 0.7 s the first time, before macOS has cached the compiled library, and 0.5 to 30 ms after).

## Files

| File | What |
|---|---|
| `src/gpu/metal_backend.mm` | `MetalGeBackend : portablekit::gpu::GeBackend` and its `BackendRegistration("metal", ...)`. Objective-C++ with ARC |
| `src/gpu/metal_shaders.h` | the shaders as one MSL string (`pure::metal::kShaderSource`), ported from the framework's `ge.vert` and `ge.frag` (MIT) |
| `src/gpu/metal_shell.hpp`, `.cpp` | `show_in_shell`: a presented picture into the Vulkan window shell (plain C++, so the shell's headers never meet Objective-C) |
| `tools/gerec/metal_check.sh` | the 3D check (task 024): Metal against Vulkan through ge_replay on the TEAM screen and the race ("The 3D check") |
| `CMakeLists.txt` | the two sources in `portablekit_add_game(... SOURCES ...)`, the `.mm` compiled with `LANGUAGE CXX` and `-x objective-c++ -fobjc-arc`, and `-framework Metal`, `Foundation`, `QuartzCore` linked |

Built without Xcode, in the shape of the Bouncer's backend (`~/dev/bouncer-recomp/docs/metal-backend.md`): the
`.mm` goes through the same `/usr/bin/clang++` and ccache as every other source of `tools/build.sh profile`, and
the shaders are compiled when the backend starts (`newLibraryWithSource`, `MTLMathModeSafe`), so the machine needs
only the Metal compiler that comes with macOS. A compile error is the message `initialize` returns.

## How a draw is drawn

| What | How |
|---|---|
| Primitives | Expanded on the CPU into lists, as the Vulkan backend does: points (1 pixel), lines, line strips, triangles; strips and fans unrolled with every triangle keeping the strip's winding; sprites as two triangles by the GE's rule (the second vertex's depth and colour for the whole rectangle, each corner the u of the vertex it shares x with and the v of the one it shares y with; transformed sprites below). Indices are resolved while expanding. 48 bytes a vertex (`GpuVertex`: position, uv, colour, the vertex a sprite corner is lit as, normal) into 4 MB shared buffers that are reused once the GPU has finished with them |
| Colour | the vertex colour, or the material colour (`DrawCall::material_color`) when the vertex type has none and the draw is unlit, Vulkan's rule. A lit draw's colour is the lighting's |
| Lighting | per vertex in `ge_vertex`, ported from `ge.vert` for transformed draws with `lighting_enabled` (never through mode or clears), in world space: emissive, plus the global ambient light times the material ambient, plus for each of the four lights that is on its ambient, diffuse and specular terms, scaled by distance attenuation (point and spot) and the spot cone. Directional, point and spot lights; diffuse, diffuse and specular, and powered diffuse kinds; the specular power; the viewer looking down z for the half vector; the normal transformed by the world matrix and normalised (`reverse_normals` flips it). The material update bits make the vertex colour stand in for the ambient, diffuse and specular material colours when the vertex has a colour; alpha is the global ambient alpha times the material ambient's. The result is clamped to 0..1; with the specular kept apart (`LightingState::mode`) the specular is added after texturing. The lights, material and fog go to the vertex function as one 688-byte block (`LightingUniforms`, buffer 2), bound again only when a lit or fogged draw changes it. The race lights with ambient, emissive and up to two directional diffuse lights; point and spot lights, specular, powered diffuse and reversed normals are ported but no recording exercises them |
| Fog | `ge.vert`/`ge.frag`'s: per vertex, (view-space z + end) x scale (`FogState`), so 1 is clear and 0 fogged, for transformed draws with fog on; in the fragment shader after texturing and the separate specular, the colour mixed towards the fog colour by that factor clamped to 0..1, alpha untouched |
| Transformed sprites | by the GE's rule, on the screen after projection: both vertices are projected, and the rectangle between them is axis-aligned in window coordinates, at the second vertex's depth, lit, coloured and fogged as the second vertex, texture coordinates interpolated without perspective. The corners go to the vertex function already in the PSP's clip space, all with the second vertex's w (`VertexUniforms::mode.y`), each naming the second vertex (appended to the buffer after the corners) as the one it is lit and fogged as. A sprite with a vertex behind the eye (w <= 0) is dropped. The Vulkan backend expands them in object space; the two agree whenever the transform keeps the rectangle axis-aligned on the screen, as it does for every transformed sprite in the recordings (26 in the TEAM frame, 28 in race frame 6016: 0.0000 px between the corners either way) |
| Through mode | positions in screen pixels go straight to clip space for a 480x272 target; z is `z / 65535` |
| Transformed | `projection x view x world`; the GE viewport (`screen = ndc x scale + offset - region offset`) folded into clip x and y, so the Metal viewport stays the whole target; clip z remapped from the PSP's [-w, w] to Metal's [0, w], and the GE's z scale and offset become the viewport's `znear` and `zfar` (reversed when the game reverses the range), as the Vulkan backend folds them into `minDepth`/`maxDepth` |
| Texture coordinates | texels divided by the texture's size in through mode, the GE's scale and offset otherwise |
| Texture function | modulate, decal, blend, replace and add, with TCC (alpha from the texture or not). The blend function's environment colour is not in the draw state; the texel stands in for it, as in `ge.frag` |
| Filtering and wrap | the GE's own filter bits (nearest or linear for magnification and minification, the base level only) and wrap bits (clamp or repeat) choose one of 16 samplers; `sharp_textures` forces nearest |
| Alpha test | in the fragment shader, by the GE's numbering (0 NEVER, 1 ALWAYS, then EQUAL ... GEQUAL: patch 0005), on the 8-bit alpha and reference under the test's mask, with `discard_fragment`. Draws without a test, or with ALWAYS, use a fragment function compiled without it |
| Blend | Metal's blend units for the GE factors and the equations ADD, SUBTRACT, REVERSE SUBTRACT, MIN and MAX (MIN and MAX take no factors). A FIX source factor is applied in the shader (the colour arrives multiplied, the blend takes it ONE), so any pair of FIX colours is exact, unless the destination factor reads the source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour. The doubled factors (2xSA and so on) are drawn single and ABSDIFF as ADD, each logged once (`[metal] ... is not emulated`) |
| Write masks | whole colour channels the mask (0xE8) keeps are not written; a partial channel mask is written whole and logged once. The alpha, which is the PSP's stencil, is written only by clears (below); the alpha mask (0xE9) is carried as the stencil write mask for task 025 |
| Depth | the GE function as the depth compare; written only where the GE tests it (`test_enabled && write_enabled`), through mode included |
| Clears | CLEARMODE draws have no blend, texture or tests; bits 8..10 choose the colour, the alpha and the depth, and the depth compare is ALWAYS |
| Culling | transformed triangles with culling on, back faces culled, the GE's clockwise front as Metal's `MTLWindingClockwise`: Metal counts the winding in window coordinates (y down), as the GE and Vulkan's flipping viewport do. Confirmed on the race (task 024): race frame 6016 culls 593 of its 906 draws, 353 of them among the first 393 (344 with the counter-clockwise front, 266 of those into the display target; 9 with the clockwise one, the shadow volumes, which write only the stencil), and it matches Vulkan's up to its draw 394, while a build with the winding reversed differs from draw 41 on, 49% of the picture by draw 393 ("The 3D check"). The clockwise case shows in no picture until the stencil does (025) |
| Scissor | the GE scissor, both ends included, clamped to 480x272; an empty one draws nothing |

### The pipeline key

`PipelineKey` is everything a draw's pipeline is made from, in two parts with a cache each:

| Part | Fields | Makes |
|---|---|---|
| `RenderKey` | blend on/off, Metal source and destination factors, blend operation, colour write mask, textured, alpha test | `MTLRenderPipelineState` (vertex function `ge_vertex`, fragment function `ge_fragment` specialised by the function constants `kTextured` and `kAlphaTest`; the four specialisations are made at start) |
| `DepthStencilKey` | depth compare, depth write; the stencil test as the GE gives it: enabled (on a 5551, 4444 or 8888 target), function, fail, depth-fail and pass operations, reference, compare mask, write mask (~0xE9) | `MTLDepthStencilState`. The stencil fields are carried for task 025, which sets the state's stencil descriptors from them; today the stencil attachment is left untouched |

Per draw, the vertex uniforms (matrix, folded viewport, uv transform, the row of view x world that gives view-space
z, and the mode: through, sprite corners in clip space, fog, lighting), the fragment uniforms (FIX colour, texture
function, TCC, opaque texel alpha, alpha test function, reference and mask, fog colour), the blend colour, the
viewport's depth range, the scissor and the cull mode are set on the encoder when they changed, and the lighting
block (world matrix, global ambient, material colours, update mask and flags, the four lights, fog end and scale)
when a lit or fogged draw changed it, or the pass is new. Lighting and fog are uniform branches in the one vertex
function, not pipeline variants.

## Targets

As section 2 of `docs/ge-backend.md`: a target is keyed by (colour address, stride, format), the address taken
modulo the cached/uncached mirrors. Each is a 480x272 `RGBA8Unorm` colour texture (5650, 5551 and 4444 targets too,
for now) and a `Depth32Float_Stencil8` texture, both private to the GPU: internal scale 1, as D-002 asks first.

- A pass draws into one target. A draw into another target ends the pass; the next one loads the target, or clears
  it to zero the first time.
- At a target's first draw of a frame, one guest word every 256 bytes of the memory under it is kept, as the Vulkan
  backend does (patch 0003's lookup compares them).
- The display target of `present_image(address)` is the target at that address drawn last (of any stride or
  format), or, when there is none, the target drawn last: Vulkan's `display_image` rule.

## Textures

- **From a target.** A bind of a direct-colour, unswizzled texture whose address lies in a target with the same row
  length and pixel size, while guest memory under the texture still holds the target's guest words, samples that
  target: the target that starts at the address first, else the one drawn last (patch 0003). The texture's first
  texel is pixel (x, y) of the target, the sampler clamps at the target's edges, and a 5650 texture reads alpha 1. A
  draw that samples the target it draws into reads a copy made by a blit when the target has changed (which ends
  the pass); any other target is sampled directly, Metal ordering the passes. The frontend reads no target; the
  race's bloom does (task 025).
- **From guest memory.** Anything else is decoded with the framework's `decode_texture` (every PSP format to
  RGBA8888; no decoder of our own) and cached by its contents: the key hashes the address, size, format, buffer
  width and swizzle, every byte of the texels the decoder reads, and for the palette formats the CLUT address,
  format, shift, mask and offset and every palette entry the format's indices can reach. A changed texture or
  palette is a new key and is uploaded again; an unchanged one is found. Within a display list a bind's key is
  hashed once. Up to 1024 textures are kept, the least recently used dropped first (a command buffer that still
  uses one keeps it alive). A texture that cannot be decoded is drawn white and logged once.

In the frontend route 57 textures are decoded by frame 600 and 347 by frame 2130, over 19853 draws: unchanged
textures are found again rather than decoded. (The language page draws the paused intro movie's picture as a
512x512 8888 texture from main memory in 150 sprites; it is decoded again only when the picture changes.)

## Frames, captures and the window

- One command buffer a frame, committed at the flip (`present_image`). Without the window no frame waits for the
  GPU unless two are already in flight.
- `present_image` returns `ImageApi::Metal` with the target's `id<MTLTexture>` as `image`, valid until the next call.
- `capture_frame` reads that texture back synchronously (a blit into a shared buffer, `waitUntilCompleted`) and
  writes the 480x272 BMP of `gpu::write_bmp_file` (`PURE_SCREENSHOT_EVERY` captures go through it).
- `upload_frame` (a CPU-drawn picture: a movie frame shown from main memory, or one decoded into VRAM) copies the
  pixels into the target at that address (made with the given stride and 8888 when there is none) through a staging
  buffer and a blit. A picture of another size than 480x272 is copied to the top left, unscaled, and logged once
  (the Vulkan backend stretches it); the frontend's are 480x272.
- `shutdown` waits for the GPU, prints the counts, and frees every target, texture and pipeline before the queue and
  the device.

### The window

The window still belongs to the Vulkan shell (`VulkanRenderer`), which presents its own target at the display
address, and the input script's `shot` steps, which the frame regression suite captures with, read that window
(`VulkanRenderer::capture_window`, from `ui/input_script.cpp`), not `GeBackend::capture_frame`. With nothing in the
shell's targets the window is black and a `shot` writes no file at all (checked: `--only lang --env
PURE_METAL_SHELL=0` ends `FAIL (no capture)`). So, when there is a window, `present_image` reads the picture back
and hands it to the shell (`show_in_shell` in `metal_shell.cpp`: `VulkanRenderer::upload_frame` at the display
address), scaled by nearest neighbour to the shell's target size (960x544 at the default 2x) so that the shell's blit
copies it 1:1. The window then shows what Metal drew, and a `shot`, reduced to 480x272 by nearest neighbour as the
suite does, gives Metal's pixels back exactly: the suite's `lang` shot and the backend's own `capture_frame` of the
same frame are identical at 480x272. This costs one GPU wait and a 2 MB upload a frame, and goes when the shell gets
its Metal presenter (task 026). `PURE_METAL_SHELL=0` turns it off.

## What is not done yet

| Task | What |
|---|---|
| 025 | the stencil attachment's test and operations, the alpha copy rule (patches 0004 and 0006: today non-clear draws leave the alpha alone), `block_transfer`, `read_back_framebuffer`, `write_back_frame` and `write_back_depth`. These four are counted and say `[metal] <call>: not implemented (task 025); counted, nothing written` once; `write_back_depth` returns false. The frontend calls only `write_back_frame` (once a flip) |
| 026 | the Metal presenter in the shell, which replaces the hand-over to the window and its per-frame wait |

On race frame 6016 the first draw that differs from Vulkan is task 025's: ge_replay's draw 394 (gerec_dump's #393:
ge_replay counts draws from 1, gerec_dump from 0), a full-screen quad blended FIX 0x606060 + FIX 0x9F9F9F (a
darkening) where the stencil test passes, which is how the shadow volumes drawn just before it (stencil only, the
clockwise-culled draws) reach the picture. Without the stencil it darkens the whole screen. Later the bloom chain
(gerec_dump's #868 to #873) reads the stencil mask from the alpha.

Not in the draw state (`DrawCall`), so neither backend draws them, and they wait for the framework's GE state to
carry them: the colour test, logic ops, the texture environment colour (the blend texture function's), colour
doubling, the texture map modes (environment and projection mapping: `texture_matrix` is carried, the map mode is
not), and the depth range clamp (MINZ/MAXZ, which `docs/ge-backend.md` section 2 lets stay ignored).

## Where it differs from the Vulkan backend on purpose

- Native 480x272 (D-002); the Vulkan backend draws at 2x by default, which is where its 0.054 on `lang` and
  `profile` comes from (one-pixel edges moved by the 2x-to-1x reduction).
- The GE's texture filter bits are honoured (the Vulkan backend samples everything bilinear).
- Through-mode draws are depth-tested when the GE enables the test (the Vulkan backend never tests them).
- TCC and the ADD texture function are honoured; the alpha test reads its mask.
- FIX source factors are exact for any pair of colours (the Vulkan backend has one blend constant for both).
- Points and lines are drawn (the Vulkan backend drops them).
- Only a draw that reads the target it draws into goes through a copy.
- An empty scissor draws nothing (the Vulkan backend draws one row or column).
- Transformed sprites are expanded on the screen after projection, the GE's rule; the Vulkan backend expands them
  in object space and projects the corners, which gives the same rectangle only while the transform keeps it
  axis-aligned on the screen (every transformed sprite this game was recorded drawing does), and otherwise a
  rotated or perspective quad.

## The 3D check (task 024)

`tools/gerec/metal_check.sh [TEAM_FRAME]` compares Metal with Vulkan through ge_replay (`docs/ge-backend.md`,
section 7). It records, when missing, `out/gerec/team.gerec` (TEAM_FRAME and the frame after, default 5650) and
`out/gerec/race_1x.gerec` (6008-6016), both at internal scale 1, and `out/gerec/race_warm.gerec` (6008-6016 at the
settings' 2x, replay_check.sh's), each by one windowed run of `main_menu.txt` + `single_race.txt` on an empty memory
stick (about 3, 3.5 and 3.5 minutes). Then:

1. the team frames' draws must hold no stencil and no bloom-target draw (lit and fogged ones are counted);
2. `--replay out/gerec/team.gerec --a vulkan --b metal --tol 24 --max-frac 0.02` must pass;
3. for the record, race frame 6016 into both, bisected with `--first-diff --tol 24`: (a) `race_1x.gerec`, (b)
   `race_warm.gerec`.

### Choosing the frame

The brief asked for a TEAM SELECTION frame with the ship model lit and no bloom or stencil draw in the list. There is
none: no frontend frame has a lit draw at all. The route run on Metal with `PURE_METAL_LOG=1` to frame 5760 (151590
draws, a line each, `lit`, `fog` and `cull` among the tags) gives:

| Frames | Screen | Draws a frame | Lit | Fogged | Stencil | Bloom targets | Depth-tested |
|---|---|---|---|---|---|---|---|
| 1-5707 | boot, language, title, profile, menus, CLASS, LEAGUE, TRACK, TEAM, loading | up to 81 | 0 | 0 | 0 | 0 | 2 a frame at 5-123 (boot), 13 at 5702-5706 (loading) |
| 5503-5701 | TEAM SELECTION (within the line above) | 65-69 | 0 | 0 | 0 | 0 | 0 |
| 5708 on | the race | 682-684 | 220-261 | 434-436 | 519 | 5 | 672-674 |

The TEAM screen's rotating ship is ten textured quads (pre-drawn outline pictures, 256x128 CLUT8 textures in VRAM),
not a lit model. Every TEAM draw but the clear is transformed, under an orthographic projection, with linear
filtering; none is lit, fogged, depth-tested or stencilled. So the TEAM frame checks the transformed path (matrices,
the viewport, the transformed sprites, 26 sprite draws, texture coordinates), and lighting and fog are checked on the
race up to its first stencil draw instead. 5650 is the middle of the TEAM screen (5503-5701 in the survey run), so a
run that drifts by some tens of frames still lands on it; its recording holds 66 draws a frame, 131 of the two
frames' 133 transformed.

### Why at internal scale 1

Recorded at the settings' 2x, the TEAM frames are 0.0519 over tol 24 (6773 pixels), all on glyph and outline edges.
The text is drawn minified (8x15-texel glyphs into about 5x10 pixels, at fractional positions) and filtered, and
reducing Vulkan's 960x544 picture to 480x272 by nearest neighbour keeps the sub-pixel whose centre is a quarter pixel
up and left of Metal's pixel centre: 0.4 texel on a glyph edge, 25 to 64 levels. A replay draws at the scale of its
recording, so a recording made with `PURE_INTERNAL_SCALE=1` has Vulkan draw at 1x like Metal, and then the two draw
the TEAM frames identically: 0 of 130560 pixels differ, at tol 0. The race at 1x is likewise exact up to its first
stencil draw, where at 2x the first pixel over tol 24 comes at draw 40 (11 pixels, the edge of an alpha test).

### Numbers (2026-10-06, M4 Pro)

| Comparison | Result |
|---|---|
| `team.gerec` (1x) frames 5650 and 5651, vulkan against metal | 0.000000 at tol 24 (0 pixels; 0 at tol 0 too): PASS |
| the same frames recorded at 2x | 0.051877 at tol 24 (6773 pixels, glyph edges) |
| `race_1x.gerec` frame 6016, `--first-diff --tol 24` | first difference at draw 394 of 906, the stencil-gated darkening quad (025's), in 10 steps. After draw 393: 0 pixels over tol 1, 36 one level off |
| what draws 1-393 hold | 58 lit draws (45 into the display target), 360 fogged (275 into it), 353 culled (266 counter-clockwise into the display target) |
| race frame 6016 whole, against Vulkan at 1x | 0.3246 at tol 24 (42380 pixels): the shadow darkening over the whole screen, the bloom, and what follows from them |
| `race_warm.gerec` (2x) frame 6016, `--first-diff --tol 24` | first difference at draw 40 (11 pixels): a fogged, alpha-tested (GREATER 0x7F), bilinear-textured strip that writes the stencil, its alpha-test edge moved by the 2x-to-1x reduction. Bisected to the first draw past 5% of the pixels instead: draw 394 |
| race frame 6016 whole, against Vulkan at 2x | 0.3768 at tol 24 |
| race frame 6016 against PPSSPP (`tools/frame_regress.sh --backend metal --only race_hud`) | RACE_HUD_PENDING |

That the race comparison would catch a wrong rule: the 1x recording cut after draw 393 of frame 6016, replayed into
Vulkan, and into Metal alone with a switch (pixels over tol 24 against Vulkan's picture):

| Metal | Over tol 24 | Over tol 8 |
|---|---|---|
| as built | 0 | 0 |
| `PURE_NO_LIGHTING` (vertex colour, no fog) | 1936 (0.0148) | 3352 |
| `PURE_NO_FOG` | 555 (0.0043) | 1049 |
| `PURE_NO_CULL` (most back faces are hidden by the depth test anyway) | 68 (0.0005) | 81 |
| the winding reversed (a throwaway build) | 63574 (0.4869); `--first-diff` stops at draw 41 | 64474 |

What the race lights with (frames 6008-6016): lit draws whose vertex colour stands in for all three material colours
with no light on (emissive plus the global ambient times the vertex colour; 1944 draws over the nine frames), and
lit draws with the material colours and two directional diffuse lights (523); fog with four settings (end 1400 and
scale 1/1230 towards 0xCCA38E or black, end 1270 and scale 1/770 towards 0xEDFCFF, end 5001 and scale 1 towards
grey). No point or spot light, no specular, no powered diffuse, no reversed normals, no separate specular: those
are ported from `ge.vert` as they are and checked by nothing but the port.

In the replays Metal takes 4 to 6 ms a race frame and Vulkan 6 to 9 (each including its capture).

## Verify numbers

`tools/build.sh profile && tools/frame_regress.sh --backend metal --only lang,title,profile` (2026-10-06, M4 Pro),
against the PPSSPP references at the suite's thresholds, beside the Vulkan backend's documented values:

| Scene | Tol | Limit | Metal | Pixels over tol | Vulkan (2x) |
|---|---|---|---|---|---|
| `lang` | 24 | 0.07 | 0.0002 | 22: the blinking cursor after ENGLISH, shown in our frame and not in PPSSPP's | 0.0544 |
| `title` | 24 | 0.05 | 0.0002 | 31: the blinking cursor after PRESS START BUTTON, shown in PPSSPP's frame and not in ours | 0.0302 |
| `profile` | 24 | 0.07 | 0.0000 | 0 | 0.0543 |

Every other pixel is within 24 of PPSSPP's; most of the rest of the difference is 1 or 2 levels (`lang`: 117458
pixels at 1-2, 9474 at 3-8, 3187 at 9-24: the paused movie picture behind the page, a texture from main memory,
is 254 where PPSSPP's is 253; `title`: 124915 pixels equal; `profile`: 123411 equal, its white background 255 in
both). The backend's own `capture_frame` of `lang` (`PURE_SCREENSHOT_EVERY`) is identical to the suite's window
shot reduced to 480x272.

Outside the Verify line, for the record (not acceptance items): `main_menu` (2D as well) scores 0.0106 against its
limit of 0.05 (Vulkan 0.0331), and `race_hud` 0.2977 against 0.10 (Vulkan 0.0672): the capture shows the track,
the stands, the ships and the HUD in place, without lighting, the stencil-volume shadows and the bloom, which are
tasks 024 and 025. The race route runs to its end on Metal (frame 6046).

The frontend route (2130 flips, windowed) takes 72 s with either backend: the frames are paced, not drawn slowly.
The Metal backend drew 19853 draws in 2126 passes, decoded 347 textures, read no target as a texture and made no
copy, and waited for the GPU 2128 times (the hand-over to the window, once a frame) for 892 ms in all, 0.42 ms a
frame. The first shader compile on a machine takes about 0.7 s, later ones 0.5 to 30 ms.

With the Metal sources built in, `tools/frame_regress.sh` (Vulkan) passes 5/5 with the fractions it had before
(0.0544, 0.0302, 0.0543, 0.0331, 0.0672), and its five captures are pixel-identical to the main checkout's run of
2026-10-06 03:35.
