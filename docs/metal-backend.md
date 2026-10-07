# The Metal GE backend (tasks 023 to 025, 2026-10-06)

`PURE_GE_BACKEND=metal` draws the game with Metal, natively, behind the GE backend seam of D-003
(`docs/ge-backend.md`). It is `src/gpu/metal_backend.mm`, in our sources, and registers itself as `metal`. Task
023 built its skeleton (device, targets, textures, the draws of the 2D frontend, clears, blending, the alpha test,
captures) and proved it on the frame regression suite's three frontend scenes, which it draws within a few pixels
of PPSSPP: the language page, the title screen and the profile screen. Task 024 added the 3D draws: the GE's
per-vertex lighting and fog, transformed sprites expanded on the screen, and culling confirmed on the race. Task 025
added the effects of patches 0003 to 0008: the stencil test and operations with the target's alpha kept as the
PSP's stencil (the shadow volumes, the bloom's mask), the bloom chain's passes over aliased VRAM, block transfers
and read-backs from targets into guest memory, the frame write-back and the depth write-back the lens flare reads
at a GE SIGNAL. The race frame 6016 is now drawn as the Vulkan backend draws it, 2 pixels of 130560 over tol 24 at
the same scale ("The race check" below), and the frame regression suite passes 5/5 with `--backend metal`, race_hud
at 0.0379 against PPSSPP (Vulkan's 0.067). The Metal shell (task 027, "The Metal shell" below) shows its
pictures in a window of its own, with no Vulkan involved. Task 036 added the GE's texture mapping modes, the
texture matrix and the environment map (patch 0013 carries them in the draw state): the ships' hulls and canopies,
glass and shiny roofs show their reflections ("Texture mapping modes" below), which the Vulkan backend does not draw.
Task 037 added the mip levels (patch 0014 carries them): a texture the GE names levels for is a mipmapped texture,
sampled at the level the GE's rule picks, so distant textures no longer shimmer ("Mipmaps" below). Task 040 added
the colour test, the writes into 16-bit targets (the format's bits kept, dithered as the GE says) and CLIPENABLE's
depth clamp (patch 0017 carries the three; "The colour test, 16-bit writes and the depth clamp" below).

## Quick start

```sh
tools/build.sh profile
tools/frame_regress.sh --backend metal                                     # the five scenes against PPSSPP (about 5 min)
tools/frame_regress.sh --backend metal --only lang,title,profile          # the three frontend scenes (about 75 s)
tools/gerec/metal_check.sh                                                 # Metal against Vulkan through ge_replay (below)
build/arm64/bin/PureNative --replay out/gerec/race_1x.gerec --a vulkan --b metal --frames 6016 --cut 393 \
  --tol 24 --out out/cut                                                   # both pictures after draw 393 of frame 6016
PURE_GE_BACKEND=metal tools/run_boot.py --frames 300 out/x.log             # headless: no window, Metal still draws
PURE_GE_BACKEND=metal tools/run_boot.py --frames 700 --env PURE_METAL_LOG=1 out/x.log   # a line per draw
PURE_SHELL=metal PURE_GE_BACKEND=metal tools/run_boot.py --window --frames 700 out/x.log # the Metal shell: no Vulkan
tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile          # the same scenes, Metal shell
```

| Switch | Effect |
|---|---|
| `PURE_GE_BACKEND=metal` | draw with this backend; with the window open (no `PURE_NO_RENDER`) or without one |
| `PURE_METAL_LOG=1` | a line per draw and per new target (below). Every 600 frames and at exit the backend prints its counts either way |
| `PURE_METAL_SHELL=0` | under the Vulkan shell, do not hand the pictures to its window: the window stays black and the input script's `shot` steps capture nothing (see "The window"). Under any other shell there is no hand-over to turn off |
| `PURE_SHELL=metal` | show the pictures in the Metal shell's window instead of the Vulkan shell's (see "The Metal shell") |
| `PURE_NO_FB_TEXTURES=1` | every texture decoded from guest memory, none read from a target (the framework's switch, as for Vulkan) |
| `PURE_NO_DEPTH_READBACK=1` | the framework's switch (patch 0008): the HLE does not ask for the depth write-back at a SIGNAL, so the lens flare is never occluded. ge_replay replays a recording's WriteBackDepth records regardless |
| `PURE_TRACE_STENCIL_COPY=1`, `PURE_TRACE_DEPTH_READBACK=1` | the framework's traces, as the Vulkan backend prints them: `[metal] stencil copied into the alpha of 0x... in frame N (reason)` for each copy of the stencil into the alpha, and `[metal] frame N signal 0x200: depth of 0x... written back to 0x4110000 stride 512, z MIN-MAX, T ms (GPU wait W ms)` for each depth write-back |
| `PURE_METAL_TRACE=FILE` | (task 033) a CSV row per flip with where the time between two flips went: submit, pipeline creation, texture decodes, each kind of GPU wait, the Metal shell's present and when the picture reached the screen ("Frame times"); `tools/frame_times.py FILE` summarises it |
| `PURE_METAL_PIPELINES=FILE` or `0` | (task 033) the pipeline list made at start instead of `config/metal_pipelines.txt` (in the app, its copy in `Contents/Resources`, task 042); `0` turns the pre-warm off ("Frame times", "The pre-warm list") |
| `PURE_METAL_PIPELINES_OUT=FILE` | (task 033) at exit, every render pipeline and depth-stencil key the run's draws used, in the list's form |
| `PURE_METAL_PACE=0` | (task 033) the Metal shell shows each picture as soon as it can, instead of at the real time of the PSP vblank after its frame began |
| `PURE_NO_TEXMAP=1` | (task 036) every draw takes its UVs through the texture scale and offset (texture map mode 0), as before task 036: the texture matrix and environment map modes are not drawn ("Texture mapping modes") |
| `PURE_NO_MIPMAPS=1` | (task 037) every texture is uploaded and sampled at level 0 alone, as before task 037, whatever levels the GE names ("Mipmaps"); its pictures are those of the build before the task |
| `PURE_NO_COLOR_TEST=1`, `PURE_NO_DITHER=1`, `PURE_NO_DEPTH_CLAMP=1` | (task 040) each restores what the backend drew before task 040: every fragment kept; 5650, 5551 and 4444 targets blended by the pipeline at 8 bits a channel, never dithered; every transformed draw clipped at both ends of the depth range, MINZ/MAXZ unread. With all three the pictures are those of the build before the task ("The colour test, 16-bit writes and the depth clamp") |
| `PURE_METAL_SHOW_TARGET=ADDR` | (task 040) each flip presents the target drawn last at ADDR instead of the display: a target the game never shows, such as the race's 565 billboard target (`0x04154000`), in a capture or a `ge_replay --cut ... --out` picture |
| `PURE_NO_LIGHTING`, `PURE_NO_FOG`, `PURE_NO_CULL` | the framework's switches for bisecting 3D draws, read as the Vulkan backend reads them: lit draws drawn with their vertex colour (white without one) and no fog; no fog; nothing culled. ge_replay hands the environment to both backends, so to turn one off in Metal alone replay each backend on its own with `--out` and compare the pictures |

When Metal cannot start (no device, or the shaders do not compile), `initialize` fails with the reason and the HLE
prints `[render] GE backend metal cannot run (...)`. At start the backend prints the device and the shader compile
time (`[metal] drawing with Apple M4 Pro at 480x272, shaders compiled in 0.5 ms; pictures shown in the window`;
about 0.7 s the first time, before macOS has cached the compiled library, and 0.5 to 30 ms after).

## Files

| File | What |
|---|---|
| `src/gpu/metal_backend.mm` | `MetalGeBackend : portablekit::gpu::GeBackend` and its `BackendRegistration("metal", ...)`. Objective-C++ with ARC |
| `src/gpu/metal_shaders.h` | the shaders as one MSL string (`pure::metal::kShaderSource`), ported from the framework's `ge.vert` and `ge.frag` (MIT); the texture mapping modes (`map_texture`, task 036), the mip level (task 037), and the colour test, the 16-bit writes (`ge_fragment_16`) and the depth clamp (task 040) are ours, from PPSSPP's hardware notes |
| `src/gpu/metal_shell.hpp`, `.cpp` | `show_in_shell`: a presented picture into the Vulkan window shell (plain C++, so the shell's headers never meet Objective-C) |
| `tools/gerec/metal_check.sh` | the 3D and race checks (tasks 024 and 025): Metal against Vulkan through ge_replay on the TEAM screen and the race ("The 3D check", "The race check") |
| `src/host/metal_shell.mm` | the Metal shell (task 027): `MetalShell : portablekit::host::Shell` and its `ShellRegistration("metal", ...)`. Objective-C++ with ARC |
| `src/gpu/metal_device.hpp`, `.mm` | the program's one Metal device and command queue, `pure::metal::device()` and `pure::metal::queue()`, which the backend and the shell both use (task 031, "One command queue" below), and the frame trace's hook through which the shell reports its presents (task 033, "Frame times"). Objective-C++ with ARC |
| `config/metal_pipelines.txt` | the render pipelines and depth-stencil states made at start (task 033, "The pre-warm list"); since task 042 it covers the campaign and the app carries a copy in `Contents/Resources` |
| `tools/frame_times.py` | the frame trace's summary (task 033, "Frame times") |
| `third_party/imgui_metal/` | Dear ImGui's Metal renderer backend, `imgui_impl_metal.h` and `imgui_impl_metal.mm` from the 1.92.9b release (the vendored ImGui's), verbatim, MIT |
| `CMakeLists.txt` | the sources in `portablekit_add_game(... SOURCES ...)`, the four `.mm` compiled with `LANGUAGE CXX` and `-x objective-c++ -fobjc-arc`, `third_party/imgui_metal` on the include path, and `-framework Metal`, `Foundation`, `QuartzCore` and (for the shell's sRGB colour space) `CoreGraphics` linked |

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
| Texture coordinates | texels divided by the texture's size in through mode; transformed, by the GE's texture map mode (task 036): the UVs through the GE's scale and offset (mode 0), the texture matrix applied to the position, UV or normal with s and t divided by q per pixel (mode 1), or the environment map from the normal and two lights (mode 2), "Texture mapping modes" |
| Texture function | modulate, decal, blend, replace and add, with TCC (alpha from the texture or not). The blend function's environment colour is not in the draw state; the texel stands in for it, as in `ge.frag` |
| Filtering and wrap | the GE's own filter bits (nearest or linear for magnification and minification; with mip levels, nearest or linear between them: task 037, "Mipmaps") and wrap bits (clamp or repeat) choose one of 48 samplers; `sharp_textures` forces nearest within a level |
| Alpha test | in the fragment shader, by the GE's numbering (0 NEVER, 1 ALWAYS, then EQUAL ... GEQUAL: patch 0005), on the 8-bit alpha and reference under the test's mask, with `discard_fragment`. Draws without a test, or with ALWAYS, use a fragment function compiled without it |
| Colour test | (task 040) in the fragment shader after fog, as the alpha test: the 8-bit colour under COLORTESTMASK against COLORREF under it, NEVER, ALWAYS, EQUAL or NOTEQUAL, with `discard_fragment` (no colour, depth or stencil written); compiled out without a test or with ALWAYS |
| 16-bit targets | (task 040) a draw into a 5650, 5551 or 4444 target blends in the shader on the target's colour (`ge_fragment_16`), adds the dither matrix's offset when DITHERENABLE is on, and keeps the format's bits, as the PSP writes such a target; the target texture stays RGBA8 and holds what those bits expand to |
| Blend | Metal's blend units for the GE factors and the equations ADD, SUBTRACT, REVERSE SUBTRACT, MIN and MAX (MIN and MAX take no factors). A FIX source factor is applied in the shader (the colour arrives multiplied, the blend takes it ONE), so any pair of FIX colours is exact, unless the destination factor reads the source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour. The doubled factors (2xSA and so on) are drawn single and ABSDIFF as ADD, each logged once (`[metal] ... is not emulated`). A draw that stores a stencil value under a blend that reads the source alpha blends with the fragment's own alpha from a second output (dual-source blending, below). The alpha channel's own blend stores the fragment's alpha (ONE, ZERO): the stencil value or a clear's alpha |
| Write masks | whole colour channels the mask (0xE8) keeps are not written; a partial channel mask is written whole and logged once. The alpha, the PSP's stencil, is written only as "The stencil and the alpha" says; the alpha mask (0xE9) is the stencil attachment's write mask (~0xE9) |
| Stencil | the GE's test (0x24, 0xDC: function, reference, compare mask) and operations (0xDD: sfail, zfail, zpass as KEEP, ZERO, REPLACE, INVERT, INCR and DECR, both clamping) on the target's `Depth32Float_Stencil8` attachment, for draws into 5551, 4444 and 8888 targets; the GE compares reference OP stencil under the mask, as Metal does, with the alpha test's function numbers. The reference is the one the target's alpha holds (the top bit of a 5551 target, the top nibble of a 4444 one), set on the encoder (`setStencilReferenceValue`) |
| Depth | the GE function as the depth compare; written only where the GE tests it (`test_enabled && write_enabled`), through mode included. With CLIPENABLE on (every transformed draw of the game), as the GE: clipped at the near plane only, each vertex's screen z clamped to 0..65535, and MINZ/MAXZ tested per pixel (task 040) |
| Clears | CLEARMODE draws have no blend, texture or tests; bits 8..10 choose the colour, the alpha and the depth, and the depth compare is ALWAYS. A clear of the alpha on a 5551, 4444 or 8888 target writes the stencil with it: ALWAYS, REPLACE with the clear colour's alpha (patch 0006) |
| Culling | transformed triangles with culling on, back faces culled, the GE's clockwise front as Metal's `MTLWindingClockwise`: Metal counts the winding in window coordinates (y down), as the GE and Vulkan's flipping viewport do. Confirmed on the race (task 024): race frame 6016 culls 593 of its 906 draws, 353 of them among the first 393 (344 with the counter-clockwise front, 266 of those into the display target; 9 with the clockwise one, the shadow volumes, which write only the stencil), and it matches Vulkan's up to its draw 394, while a build with the winding reversed differs from draw 41 on, 49% of the picture by draw 393 ("The 3D check"). The clockwise case, the shadow volumes, reaches the picture through the stencil since task 025 |
| Scissor | the GE scissor, both ends included, clamped to 480x272; an empty one draws nothing |

### The pipeline key

`PipelineKey` is everything a draw's pipeline is made from, in two parts with a cache each:

| Part | Fields | Makes |
|---|---|---|
| `RenderKey` | blend on/off, Metal source and destination factors, blend operation, colour write mask (alpha included when the draw stores a stencil value), the alpha's destination factor (ZERO, or ONE for the copy of the stencil into the alpha), dual source, textured, alpha test, and since task 040 colour test and `sixteen` (a 5650, 5551 or 4444 target) | `MTLRenderPipelineState` (vertex function `ge_vertex`, fragment function `ge_fragment`, `ge_fragment_dual` with dual source, or `ge_fragment_16` for a 16-bit target, whose pipeline does not blend; specialised by the function constants `kTextured`, `kAlphaTest` and `kColorTest`: the eight specialisations without the colour test and the 16-bit function are made at start, the others on first use). With dual source the colour factors SA and 1-SA become `Source1Alpha` and `OneMinusSource1Alpha`. A line of the pre-warm list without the two later fields reads them as 0 |
| `DepthStencilKey` | depth compare, depth write; the stencil test as the GE gives it: enabled (on a 5551, 4444 or 8888 target), function, fail, depth-fail and pass operations, compare mask, write mask (~0xE9) | `MTLDepthStencilState`, with the same `MTLStencilDescriptor` for both faces. The reference is the encoder's, not the state's |

The keys of `config/metal_pipelines.txt` are made at start, the render pipelines asynchronously, and any other key on
first use (task 033, "Frame times").

Per draw, the vertex uniforms (matrix, folded viewport, uv transform, the row of view x world that gives view-space
z, the mode: through, sprite corners in clip space, fog, lighting, and since task 036 the texture map mode with
the texture matrix, the viewer's direction and the texture's place in the image sampled, and since task 040 the GE's
z scale and offset and MINZ/MAXZ for the depth clamp; 256 bytes), the fragment
uniforms (FIX colour, texture function, TCC, opaque texel alpha, whether the coordinates are divided by q, alpha
test function, reference and mask, fog colour, the stencil value the
alpha stores, since task 037 the mip level rule, and since task 040 the colour test and, for a 16-bit target, the
GE's blend factors, equation and FIX colours, the dither matrix and the target's format: 208 bytes), the blend
colour, the stencil reference, the viewport's depth range, the depth clip mode, the scissor and the cull mode
are set on the encoder when they changed, and the lighting
block (world matrix, global ambient, material colours, update mask and flags, the four lights, fog end and scale)
when a lit, fogged or environment-mapped draw changed it, or the pass is new. Lighting and fog are uniform branches in the one vertex
function, not pipeline variants.

## Targets

As section 2 of `docs/ge-backend.md`: a target is keyed by (colour address, stride, format), the address taken
modulo the cached/uncached mirrors. Each is a 480x272 `RGBA8Unorm` colour texture (5650, 5551 and 4444 targets too:
since task 040 their draws write only the values the format's bits expand to) and a `Depth32Float_Stencil8` texture,
both private to the GPU: internal scale 1, as D-002 asks first.

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
  race's billboards and bloom do ("The bloom chain").
- **From guest memory.** Anything else is decoded with the framework's `decode_texture` (every PSP format to
  RGBA8888; no decoder of our own) and cached by its contents: the key hashes the address, size, format, buffer
  width and swizzle, every byte of the texels the decoder reads, and for the palette formats the CLUT address,
  format, shift, mask and offset and every palette entry the format's indices can reach. A changed texture or
  palette is a new key and is uploaded again; an unchanged one is found. Within a display list a bind's key is
  hashed once. Up to 1024 textures are kept, the least recently used dropped first (a command buffer that still
  uses one keeps it alive). A texture that cannot be decoded is drawn white and logged once. A texture with mip
  levels (task 037) is one mipmapped texture, its key covering every level's address, size, row length and texels
  ("Mipmaps").

In the frontend route 57 textures are decoded by frame 600 and 347 by frame 2130, over 19853 draws: unchanged
textures are found again rather than decoded. (The language page draws the paused intro movie's picture as a
512x512 8888 texture from main memory in 150 sprites; it is decoded again only when the picture changes.)

## The stencil and the alpha (task 025)

The PSP keeps the stencil in the alpha channel of a 5551, 4444 or 8888 target, and never stores a fragment's own
alpha there. The backend follows patches 0004 and 0006 (`docs/ge-effects.md`, "The stencil attachment and the copy
rule"; `docs/ge-backend.md` section 2): the `Depth32Float_Stencil8` attachment is exact, and the colour target's
alpha, which is what sampling, blending, the display and the write-backs read, is kept as its copy.

| Case | What the draw does to the alpha |
|---|---|
| no stencil test, a 5650 target, or alpha bits masked (0xE9 not 0) | nothing: the alpha is not in the write mask |
| zpass REPLACE | the stored reference (`stencil_alpha`): the fragment function writes it as alpha (`FragmentUniforms::stencil`), so only fragments that pass every test write it, as the attachment's zpass does |
| zpass ZERO | 0, the same way |
| zpass KEEP, INVERT, INCR, DECR | nothing from the fragment; INVERT, INCR and DECR are done by the attachment |
| REPLACE or ZERO under a blend that reads the source alpha (SA or 1-SA) | dual-source blending: `ge_fragment_dual` returns the colour with the stencil value as alpha at `[[color(0), index(0)]]` and the fragment's own alpha at `[[color(0), index(1)]]`, and the colour blend reads `Source1Alpha`. Metal has it on every Apple GPU, so the constant-alpha fallback of patch 0004 (exact only for opaque fragments) is not needed |
| clear mode with the alpha flag | the clear colour's alpha, and the stencil REPLACEd with it |

A draw leaves the alpha behind the stencil when the colour path cannot express its effect (patch 0006's
`alpha_follows_stencil`): an sfail operation other than KEEP under a test that can fail, a zfail operation other
than KEEP under a depth test that can fail, INVERT, INCR or DECR on pass, or an alpha write mask that keeps some
bits. The pass is then marked stale, and the stencil is copied into the alpha (`resolve_stencil_alpha`) before the
next draw in the pass whose blend reads the destination alpha (DA or 1-DA), and when the pass ends: every end of a
pass goes through `end_encoder`, so a texture bind, a copy, a read-back, a write-back and the flip all see the copy.
The copy never reads the stencil in a shader: inside the pass, a quad over the target writes alpha 0 (alpha written
alone), then for each of the 8 bits a quad passes the stencil test EQUAL under a compare mask of that bit (reference
the bit, write mask 0) and adds the bit's value to the alpha (alpha blend ONE + ONE); sums of k/255 are exact in an
8-bit target. Nine draws, from a 6-vertex quad in the frame's vertex space; the encoder's state is set again by the
next draw.

On the race the shadow volumes (zfail INCR and DECR, colour masked) leave the alpha stale and the full-screen
darkening quad (stencil test GREATER ref 4, REPLACE) darkens only where the volumes left the stencil below 4. The
stencil is copied into the alpha once a race frame, at the end of the back buffer's pass: 339 copies for the
route's 339 race frames (5707-6045), as patch 0006 measured for Vulkan (338 for frames 5707-6044). None in the
frontend. With `PURE_TRACE_STENCIL_COPY=1` the replay of `race_1x.gerec` shows one copy a frame, at the end of a
pass, never before a destination-alpha read, alternating between 0x04000000 and 0x04088000.

## The bloom chain (task 025)

The six draws of `docs/ge-effects.md` ("The bloom chain"), as this backend resolves them with section 2's target
model and patch 0003's lookup, which task 023 already had:

| Draw (gerec_dump, frame 6016) | Target | Texture bind and what it samples |
|---|---|---|
| downsample | 0x04110000 8888/256: the depth buffer's bytes as a colour target of its own | 0x04088000 8888 512x512 bufw 512: the back buffer, sampled directly, its alpha the stencil mask (copied at the end of its pass, which this draw's pass ends). Blend add(SA, FIXB 0): the scene times the mask |
| black sprite | 0x04132000 8888/256, which lies inside 0x04110000's memory: a target of its own | none |
| horizontal blur | 0x04132000 | 0x04110000 bufw 256: the exact target at the address (0x04110000) |
| black sprite | 0x04110000 | none |
| vertical blur | 0x04110000 | 0x04132000 bufw 256: two targets contain the address, 0x04110000 (row 136) and 0x04132000 (row 0); the one starting there wins (patch 0003), as on the PSP |
| composite | 0x04088000 8888/512 | 0x04110000: the blurred bloom, added at FIX 0xAFAFAF with the alpha masked |

The aliasing cases behave as the Vulkan backend's, and no better: a texture bind inside a target of another stride
or pixel size is decoded from guest memory; a target made over memory another target covers is a texture of its
own, so the vertical blur's overshoot into rows 136 to 141 of 0x04110000 does not reach 0x04132000's rows 0 to 5
as it does on the PSP (the next frame's black sprite clears them there anyway). Guest memory under the bloom targets
changes at each SIGNAL (the depth write-back, below), before their first draw of the frame takes their guest-word
snapshot, so the binds still find the targets. The four billboard rounds (565 target 0x04154000, stride 128) are
sampled the same way, as opaque 5650 textures.

## Guest memory: transfers, read-backs and write-backs (task 025)

All four go through the same steps: a blit of the target's colour (or its depth) into a shared buffer, a commit and
a wait, then the CPU stores the pixels in guest memory in the target's own format and stride (8888 as it is; 5650,
5551 and 4444 packed with red in the low bits, as `texture_decode` reads them and the Vulkan backend's `store_frame`
writes them), and takes the target's guest-word snapshot again, since memory now holds what it shows. Each is
counted with the time it waited for the GPU; the exit line `[metal] stencil: ... guest memory written/asked: ...`
prints them.

| Call | Target | What is written |
|---|---|---|
| `block_transfer` (before the HLE copies the rows) | the target the GE drew, in VRAM, that holds the first byte the copy reads: the one starting at the source buffer first, else the one drawn last | the target's rows the copy's bytes fall in, `min(stride, 480)` pixels each. Nothing when the source lies in no target (the race's 584 transfers over the route are texture uploads from main memory) |
| `read_back_framebuffer(address)` | the same choice for `address`, at least 480 pixels wide (the Vulkan backend's rule) | the whole 480x272 |
| `write_back_frame` (each flip, before the image is asked for) | the target the previous flip showed, if the GE drew it, in VRAM and at least 480 wide (Vulkan's `record_writeback` rule) | the whole 480x272, as it was shown: the Vulkan backend likewise stores at each flip the picture recorded at the flip before. Under the Vulkan shell the picture read back for the window is reused, so this costs no GPU wait; under any other shell `present_image` records the copy into a shared buffer with the frame's commands, and the next flip waits for that command buffer, which has almost always finished by then |
| `write_back_depth(color, depth, stride)` | the target at `color` drawn last | its depth (`MTLBlitOptionDepthFromDepthStencil`) as z = round(depth x 65535) in 16 bits, 480x272 in rows of `stride` from `depth` (VRAM, `0x04000000 | (depth & 0x1FFFF0)`), screen-wide buffers only (stride 480 or more), patch 0008's rule; returns whether it wrote. The vertex function and the viewport's depth range map the GE's z onto depth z / 65535, so this is the GE's own z |

`PURE_NO_FB_TEXTURES` turns the first two off, as it does for the Vulkan backend's `read_back_framebuffer`.

## Frames, captures and the window

- One command buffer a frame, committed at the flip (`present_image`), on the program's one queue, which the Metal
  shell presents on too ("One command queue" below). Without the window no frame waits for the GPU unless two are
  already in flight.
- `present_image` returns `ImageApi::Metal` with the target's `id<MTLTexture>` as `image`, valid until the next call.
  When the frame write-back will store the shown target at the next flip, the picture is kept for it: the read-back
  the Vulkan shell gets anyway, or else a blit into a shared buffer recorded with the frame's commands.
- `capture_frame` reads that texture back synchronously (a blit into a shared buffer, `waitUntilCompleted`) and
  writes the 480x272 BMP of `gpu::write_bmp_file` (`PURE_SCREENSHOT_EVERY` captures go through it).
- `upload_frame` (a CPU-drawn picture: a movie frame shown from main memory, or one decoded into VRAM) copies the
  pixels into the target at that address (made with the given stride and 8888 when there is none) through a staging
  buffer and a blit. A picture of another size than 480x272 is copied to the top left, unscaled, and logged once
  (the Vulkan backend stretches it); the frontend's are 480x272.
- `shutdown` waits for the GPU, prints the counts, and frees every target, texture and pipeline before the queue and
  the device.

### The window

Under the Vulkan shell (the default, `PURE_SHELL` unset), the window belongs to `VulkanRenderer`, which presents its
own target at the display address, and the input script's `shot` steps, which the frame regression suite captures with, read that window
(`VulkanRenderer::capture_window`, from `ui/input_script.cpp`), not `GeBackend::capture_frame`. With nothing in the
shell's targets the window is black and a `shot` writes no file at all (checked: `--only lang --env
PURE_METAL_SHELL=0` ends `FAIL (no capture)`). So, when there is a window, `present_image` reads the picture back
and hands it to the shell (`show_in_shell` in `metal_shell.cpp`: `VulkanRenderer::upload_frame` at the display
address), scaled by nearest neighbour to the shell's target size (960x544 at the default 2x) so that the shell's blit
copies it 1:1. The window then shows what Metal drew, and a `shot`, reduced to 480x272 by nearest neighbour as the
suite does, gives Metal's pixels back exactly: the suite's `lang` shot and the backend's own `capture_frame` of the
same frame are identical at 480x272. This costs one GPU wait and a 2 MB upload a frame. `PURE_METAL_SHELL=0` turns it
off. Under any other shell `BackendConfig::vulkan_shell` is null and there is no hand-over and no read-back:
`present_image` commits the frame and names the target's texture, which the Metal shell samples itself (below) and the
headless shell never looks at (its `shot` steps are `capture_frame`). The start-up line then ends "pictures shown by
the shell, not read back".

## The Metal shell (task 027, 2026-10-06)

`PURE_SHELL=metal` puts the game in a window shell of our own, `src/host/metal_shell.mm` (`MetalShell :
portablekit::host::Shell`, registered as `metal` with a `ShellRegistration`, docs/ge-backend.md section 8), instead of
the Vulkan one. With `PURE_GE_BACKEND=metal` the game then runs with no Vulkan and no MoltenVK: the frontend route's
log has no line naming either. Under another GE backend it shows that backend's `Cpu` picture (the null backend's
black); the Vulkan backend needs the Vulkan shell and draws nothing here, as in the headless shell.

| Part | What it does |
|---|---|
| Window | an SDL window (`SDL_WINDOW_METAL \| SDL_WINDOW_RESIZABLE`, 480x272 times the window-size setting, full screen by the setting), titled as the Vulkan shell's (`PURE_WINDOW_TITLE`, else the program's name and build label); `SDL_Metal_CreateView` and its `CAMetalLayer`: BGRA8, tagged sRGB (as MoltenVK tags its swapchain, so the colours look the same), `framebufferOnly` off for the captures, the program's one device and command queue (`src/gpu/metal_device.hpp`, the backend's; "One command queue" below). Prints `[shell] metal: Apple M4 Pro, window 960x544, vsync` |
| Events and input | `pump_events` handles the window's events as the Vulkan renderer's pump does: close, gamepads arriving and leaving, a display change, the mouse while it is captured for the game (only the script's mouse under scripted input), then the interface's event hook. The pad is a `host::SdlPad` the shell holds, the code the Vulkan shell uses: the keyboard through the player's bindings, the first gamepad or the input script's virtual one, the script's keys (`set_scripted_key`), the neutral pad while an interface screen is up (`set_game_input`). The pointer is captured by the Vulkan renderer's rule. `sample_pad` pumps SDL and samples without handling events |
| Present | the backend's `Metal` image (its target's `id<MTLTexture>`) is drawn into the layer's next drawable by one triangle over the letterboxed rectangle, placed as the Vulkan renderer's `record_game_blit` places it (Original), or over the whole drawable (Stretch); a `Cpu` image is uploaded to a texture first; no image clears to black. The interface is drawn in the same pass, then `presentDrawable` and commit; while the game is held to real time the drawable is presented at the real time of the PSP vblank after the one its frame began from (`presentDrawable:atTime:`, task 033, "Frame times"; `PURE_METAL_PACE=0` presents at once). A fast-forwarding load presents a flip only when none was shown for 33 ms, as the Vulkan shell does. Vsync is the layer's `displaySyncEnabled`, off for Immediate; there is no Mailbox (`supports_present_mode`) |
| Scaling filter | nearest when the sharp-screen setting is on, and whenever the picture covers a whole multiple of 480x272 (the default 2x window); linear otherwise (below) |
| Captures | `capture_window` (the input script's `shot`): the next present also copies the drawable, interface included, into a shared buffer, waits for it and writes the BMP (`[render] window 960x544 -> PATH`), as the Vulkan shell's window captures are written. `ShellConfig::capture_frame` is not used |
| Interface | `initialize_ui`: `ImGui_ImplSDL3_InitForMetal` and `ImGui_ImplMetal_Init` (patch 0012 moved the SDL3 platform init from `Layer::attach` into the shells); `begin_ui_frame`: `ImGui_ImplMetal_NewFrame` with a render pass descriptor that has the drawable's attachments (one BGRA8 colour attachment, no depth: a 1x1 stand-in texture, since the drawable itself is taken at the present); `set_ui_draw_data` keeps the draw data, drawn by the next `present` or `present_ui` over the picture; `present_ui(show_game)` presents the last game picture (behind the paused menu) or the setup screens' brown, with the interface; `shutdown_ui` waits for the GPU and shuts both ImGui backends down |
| Other | `hold_frame` keeps a copy of the picture on screen while the hold lasts; `frame_rate_now` counts the presents of the last second; `display_refresh` is the refresh rate SDL gives for the window's display; `game_aspect` is 480/272; `device_name` the Metal device's name |

What it leaves out: frame interpolation (`present_due`, `present_until` and `pause_interpolation` do nothing and
`set_frame_rate` is ignored: every flip is presented as it comes, so the menu's frame rate row changes nothing here),
the Fill aspect (taken as Original: the shell keeps the PSP's shape, as `usable_aspect` does for a game that cannot
draw another), the touch controls (`touch_controls_visible` is false), the performance overlay (`set_perf_overlay` does
nothing; `PURE_PERF=log` still prints), and the menu's resolution, texture filter and texture-pack rows, which need the
Vulkan renderer (`active_renderer()` is null under this shell, and the menu leaves them out). The System tab's
graphics line still reads "Vulkan on" the device's name: that text is the framework's (`ui/menu.cpp`).

### One command queue (task 031, 2026-10-06)

The backend and the shell draw with the program's one device and command queue, `pure::metal::device()` and
`pure::metal::queue()` (`src/gpu/metal_device.hpp`, `.mm`: made once, on first use, with
`MTLCreateSystemDefaultDevice`; the framework's `BackendConfig` and `ShellConfig` carry neither). The ordering rule:

- Metal runs the command buffers of one queue in the order they are committed, and tracks the hazards of tracked
  resources across them: a command buffer that reads a texture runs after an earlier one of the queue that writes it,
  and the other way round. Every target here is tracked (made by the device with the default hazard tracking).
- The HLE calls the backend's `present_image` before the shell's `present`, on the same thread. `present_image`
  commits the frame's last command buffer, and the shell's `draw` then commits the present that samples the target.
  On one queue the present is therefore ordered after every draw of the frame, the race HUD included, and the
  backend's next frame, which may draw into the same target, after the present.
- Nothing waits on the CPU for it. The backend still waits only where it did: at the SIGNAL's depth write-back, for a
  frame write-back, a read-back or a capture, and when more than `kFramesInFlight` frames are in flight (`in_flight_`
  holds its own command buffers; the shell's between them change nothing). The shell waits only for its own last
  command buffer (`wait_idle`, before it uploads a `Cpu` picture again, and at shutdown) and for a window capture,
  and on one queue those cover the backend's earlier frames too.

Until task 031 the shell had a queue of its own. Metal orders the command buffers of two queues only through an event
(`MTLSharedEvent`) or a wait, and the backend commits its frame without waiting, so the shell's present could sample
the target before the end of the frame had run on the GPU. In a race the window then showed the 3D picture without
the HUD drawn after it, and players saw the HUD flicker or vanish. `tools/hud_check.sh` (docs/verification.md, "The
race HUD check": 61 shots from flip 6200 to 7700 of the race route) counted 11 of 61 shots with the HUD on two queues
(task 028's probe: 12), and 61 of 61 on one queue, as on the Vulkan shell and in the backend's own headless captures.
The SIGNAL's mid-frame commit and wait was not the cause: task 028's probe with `PURE_NO_DEPTH_READBACK=1`, which
leaves the race one command buffer a frame, had the HUD in 3 of 61 shots.

A shared event was not needed. The backend could signal an `MTLSharedEvent` at its commit and the shell encode a wait
for it before sampling, which orders two queues the same way; but on one queue such a pair orders nothing the queue
does not order already, and it would need the event and its value handed from the backend to the shell, for which
the framework's `PresentedImage` has no field. One queue needs no new interface and no new wait.

The race under the Metal shell still runs at 60 fps: with `PURE_PERF=log`, the 24 one-second lines of the race in the
check's route read 59.7 to 60.1 fps, render 3.1 ms a frame on average, and the backend waited for the GPU 2009 times in
7710 flips (2003 of them at the SIGNAL), as many as on two queues.

### The scaling filter

The backend draws at 480x272 and the default window is 960x544. At an exact 2x, linear sampling mixes every window
pixel with its neighbour by a quarter: with plain bilinear the suite scores lang 0.0521, title 0.0388 and profile
0.0473 (inside the limits, far from the backend's own 0.0002, 0.0002 and 0.0000), and the picture is visibly softer
than the Vulkan shell's, which at the same settings copies its 2x target 1:1. So the shell samples nearest whenever the
picture covers a whole multiple of its size, where each game pixel covers whole window pixels and filtering could only
blur. Sharp (the sharp-screen setting) is nearest at any size; Smooth is bilinear at the sizes that are not whole
multiples (a resized window, full screen).

### Numbers

`tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile` (2026-10-06, M4 Pro): lang 0.0002,
title 0.0002, profile 0.0000, task 023's values, in 72 s. The three 960x544 captures are pixel-identical
(`imgdiff.py --tol 0`) to the Vulkan shell's with the hand-over (`--backend metal`) of the same day. Over the frontend
route the backend waited for the GPU twice (0.9 ms) against 2128 times (1009 ms) with the hand-over; the route takes
the same 71 s either way, paced to real time. One of the runs caught the blinking cursor after LOAD at frame 2100
(profile 0.0002, 22 pixels, 19893 draws instead of 19853): its phase follows the real-time pacing, as on lang and
title. For comparison, `--shell headless --backend metal` gives the same three fractions from the backend's own 480x272
captures in 2 s (no window, unpaced: patch 0011), and `tools/frame_regress.sh` with the Vulkan shell and backend still
passes 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and 0.0672.

A window resized through the menu (Window size x3) gets a 1440x816 drawable, and its capture reduced to 480x272 is
identical to the 2x one: nearest at 3x as at 2x.

The menu opens over the game with Esc (the interface's key) and closes with Esc again: `out/027/menu_shots/menu_open.png`
of task 027's check shows it over the paused language page.

## Frame times (task 033, 2026-10-06)

Erik's first race on the app dipped "here and there", while the scripted race's one-second `[perf]` lines held 59.7 to
60.1 fps: a second's average hides single long frames. Task 033 gave the backend a trace with a row per flip, measured
the Vineta K race cell with it, and removed what the backend and the shell could remove without changing a pixel: the
render pipelines compiled on first use (pre-warmed now) and the Metal shell's uneven presents on a 120 Hz display
(timed to the PSP's vblank now). Most of what remains is the game's own: stretches of frames that wait two vblanks.

### The trace

`PURE_METAL_TRACE=FILE` writes a CSV row per flip, from the backend's `present_image()`, for the interval since the
previous flip: everything the backend and the shell did between two flips is in the row of the second. The Metal shell
presents each picture right after `present_image()` and hands its own part to the trace through a small hook in
`src/gpu/metal_device.hpp` (`trace_shell_present`, `trace_presented`; the brief's hook rather than a second file),
including when each drawable reached the screen, from its presented handler's `presentedTime`. A row is therefore
written a few flips late (at most 30), and the last ones at exit. Off, the trace costs one test of a pointer per call;
the counts it reports are the backend's own.

| Column | What |
|---|---|
| `flip`, `t_ms`, `frame_ms` | the flip's number (as `[render] frame N` numbers them), its time since the backend started, the time since the previous flip |
| `submit_ms` | CPU time in `submit()`, the draws |
| `pipeline_ms`, `texture_ms` | of `submit_ms`: making render pipelines and depth-stencil states (or waiting for the pre-warm to); hashing and decoding textures from guest memory |
| `present_ms` | `present_image()` at the previous flip, its waits included |
| `memory_ms` | `write_back_depth`, `write_back_frame`, `block_transfer`, `read_back_framebuffer`, `upload_frame` and `capture_frame`, their waits included |
| `wait_ms`; `wait_depth_ms`, `wait_frame_ms`, `wait_guest_ms`, `wait_capture_ms`, `wait_ring_ms` | GPU waits in all (within `present_ms` and `memory_ms`), and by where: the SIGNAL's depth write-back, the frame write-back, transfers and read-backs from a target, captures and the Vulkan shell's hand-over, more than two frames in flight |
| `pipelines`, `depth_states` | made by a draw in the interval; a draw that waited for the pre-warm counts |
| `decoded`, `decoded_kb` | textures decoded from guest memory, and their size as uploaded (RGBA8) |
| `stencil_copies`, `draws`, `passes`, `copies` | copies of the stencil into the alpha, draws, render passes, copies of a target a draw samples while drawing into it |
| `shell_ms`, `drawable_ms`, `occluded` | the Metal shell's `present()` in the interval, of it the wait in `nextDrawable`, and how many of its presents found the window occluded (SDL's flag, which lags the window by a few flips); empty under another shell |
| `shown_ms`, `latency_ms` | when this flip's picture reached the screen after the previous picture shown did, and after the shell's `present()` began; `shown_ms` 0 when the shell reported that it never reached the screen, both empty when nothing was reported |
| `other_ms` | `frame_ms` less `submit_ms`, `present_ms`, `memory_ms` and `shell_ms`: the game's own code, the HLE, the kernel's pacing sleep |

`tools/frame_times.py TRACE [--long MS] [--fps N] [--from FLIP] [--to FLIP] [--top N] [--plot OUT.png]
[--check-no-pipeline-stalls-after N]` prints the frame count, the mean, median, 99th percentile and longest frame time,
the frames over `--long` (default 20 ms) and over 1.5 frames at `--fps` (default 60), the on-screen intervals when the
trace has them, histograms, the longest `--top` frames with their columns, and the long frames counted by cause. A
long frame's cause is the part of it that exceeds its own median over the rows read by the most: `pipeline`,
`texture`, `draws` (the rest of submit), `wait depth`, `wait frame`, `wait guest`, `wait capture`, `wait ring`,
`backend` (present and memory besides their waits), `shell` (besides the drawable), `drawable` (`drawable, occluded`
with the window occluded) or `outside` (`other_ms`). The medians take the pacing sleep out of `outside`: a long frame
whose excess is there spent its time in the game, the HLE or the kernel. `--plot` draws `frame_ms` per flip with the
long frames coloured by cause (`tools/png.py`). `--check-no-pipeline-stalls-after N` exits 1 when a frame after flip N
takes over 25 ms with a render pipeline made in it, or 5 ms of pipeline work; a depth-stencil state alone does not
count (Metal makes one in microseconds, and one made in a frame that was long for another reason is not its cause).

### Method

The Vineta K Single Race cell (the menus, a three-lap race in which the follower presses Square, use pickup, every 120
flips, the results screen), under the Metal shell in a window, since the dips are what a player sees:

```sh
PURE_METAL_TRACE=out/033/race.csv python3 tools/campaign_sweep.py single_race vineta_k --no-damage --shell metal
python3 tools/frame_times.py out/033/race.csv --long 20 --fps 60 --from 6250 --to RESULTS-300
```

The sweep takes no `--env` (task 034's argument list): the environment reaches the game. The race is read from flip
6250, where the race clock starts, to 300 flips before the results screen. M4 Pro with its built-in display at 120 Hz;
the machine was in use during the runs (a browser at full load on one core, a VM, video), which shows as scattered
frames whose `draws` or `outside` grow with no more work in them. The window was not always visible: in three runs (A, C and D
below) the pictures stopped reaching the screen part of the way through or never did (the `shown_ms` and `occluded`
columns), and while it is occluded macOS holds `nextDrawable` back for up to a second. A cold shader cache, as on a machine's first start of the
app (Erik's first race), was made with a throwaway build, not committed: the shader source got an unused varying holding
a number from the environment, new for each run, so Metal's cache missed every library and pipeline.

### The runs

| Run | Shell | Window | Shader cache | Pre-warm | Pictures | Race window (flips) | Frames | Over 20 ms | Over 25 ms | 99th pct |
|---|---|---|---|---|---|---|---|---|---|---|
| A | Metal | shown until flip 7184, then occluded | warm | off | at once | 6250-17070 | 10821 | 236 | 227 | 33.4 ms |
| B | headless | none | warm | off | | 6250-17110 | 10861 | 244 | 188 | 33.3 ms |
| C | Metal | never shown | cold | off | at once | 6250-17610 | 11361 | 124 | 119 | 31.0 ms |
| D | Metal | occluded from flip 7769 | cold | on | at once | 6250-17990 | 11741 | 113 | 106 | 19.6 ms |
| E | Metal | shown | warm | on | at once | 6250-16890 | 10641 | 61 | 52 | 18.6 ms |
| F | Metal | shown | warm | on | at the PSP's vblank | 6250-17310 | 11061 | 73 | 72 | 18.9 ms |

The race's frames over 20 ms by cause (the tool's rule; a two-vblank stretch is three or more frames in a row over 25
ms whose cause is `outside`):

| Cause | A | B | C | D | E | F | What it is |
|---|---|---|---|---|---|---|---|
| two-vblank stretches (outside) | 211 in 11 | 116 in 8 | 108 in 6 | 94 in 3 | 48 in 2 | 71 in 3 | mostly runs of 13 to 39 frames of 31 to 35 ms, `other_ms` 28 to 32 ms and nothing else above its median: the game's own 30 fps (below) |
| outside, single frames | 11 | 80 | 6 | 8 | 8 | 1 | host contention: `other_ms` alone grows to 40 to 75 ms |
| draws, texture, backend | 3 | 45 | 4 | 5 | 1 | 1 | host contention: `submit_ms` 10 to 110 ms over the usual draws, `texture_ms` up to 34 ms with nothing decoded (the thread descheduled while hashing) |
| wait depth | 7 | 3 | 6 | 4 | 4 | 0 | the SIGNAL's depth write-back waiting 13 to 40 ms for the GPU (median 0.6 ms) |
| drawable, shell | 4 | 0 | 0 | 2 | 0 | 0 | the window occluded: `nextDrawable` held for 104 to 973 ms |
| pipeline | 0 | 0 | 0 | 0 | 0 | 0 | no render pipeline was made in any race; on a cold cache they all came before it (below) |

Before the race the cold cache mattered: in C the race's load (flip 5708) took 134.7 ms making 18 pipelines (122.9 ms
of it), flip 5745 27.6 ms making 3 (21.5 ms), and flips 3 and 5 at boot 26.9 and 26.4 ms; with the pre-warm (D) flips
5708 and 5745 took 15.0 and 7.2 ms, flip 5 10.1 ms, flip 3 waited 11 ms for the pre-warm's first pipeline (27.9 ms),
and no draw made a pipeline after it. On a warm cache a pipeline takes 0.2 to 2 ms on first use, and A and B made all 26
before the race, none in a frame over 25 ms. `--check-no-pipeline-stalls-after 600` fails on C (flips 5708 and 5745)
and passes on every other run.

On screen, run E (the window shown throughout, pictures shown at once) had what the flip times do not show: of 10641
pictures, 476 stayed 25 ms and 470 only 8.3 ms, in pairs, in most five-second stretches of the race (up to 28 pairs in
five seconds). The flips come every 16.68 ms with a standard deviation of 1.4 ms (the kernel's sleeps), and at 120 Hz a
picture is shown at the first refresh after its flip: while the flips' phase lies near a refresh boundary they
alternately catch and miss it. That stutter is the other "dip here and there" a player sees besides the game's own 30
fps stretches; F removes it (After).

### The two-vblank stretches (outside the backend and the shell)

In every run most of the race's long frames come in runs of frames at two vblanks each (about 33 ms; most runs 13 to 39
frames long), with no time above its median in any backend or shell column, 2 to 11 runs a race (E: 7082-7105 and
12280-12303; A: eleven). The emulated clock does not advance while guest code runs (it
jumps to the next event when every thread waits, `Kernel::schedule`), so a frame of two vblanks is the guest waiting
across two vblanks, which `[perf]` confirms ("game" 35 to 49 fps at speed 100% in those seconds). docs/timing.md
describes the game's end-of-frame routine: in a locked mode, or while a countdown at the frame object's `+0x117c` runs,
it waits two vblanks a frame (30 fps). What starts these stretches in the race, and whether the PSP has them in the same
places, is a question for the HLE and the game, outside this task (the brief's escalation): see the pacing trace below
and the Result of docs/tasks/033-frame-time-dips.md.

A headless run of the cell with the framework's pacing trace beside the frame trace (`PURE_TRACE_PACING=900000
PURE_METAL_TRACE=FILE python3 tools/campaign_sweep.py single_race vineta_k --no-damage --max-lines 1500000`; the n-th
`sceDisplaySetFrameBuf` line is flip n) shows the switch. In the race's ordinary frames the main thread calls no vblank wait: it reads the pad
(`sceCtrlReadBufferPositive`, which blocks until the next vblank's sample) and flips 250 us after each vblank, a frame
a vblank. In its stretch at flips 9261-9276 it calls `sceDisplayWaitVblankStart` twice a frame and flips on every
second vblank, the end-of-frame routine's locked path of docs/timing.md (step 5: `n = 2 - (vcount - lastVcount)` waits
when `+0x116c` is 0 or the countdown at `+0x117c` runs), then returns to the free-running path at flip 9277. The
stretches come back at about the same flips in different runs (7082-7105 in D and E; 16252-16290 in D, 16259-16283 in
F), so something in the race sets the lock. Finding what (a watch on `+0x116c` and `+0x117c` of the frame object, and
PPSSPP's frame rate at the same place on the track) is the follow-up the task reports.

### What changed

| Change | Where | What it does |
|---|---|---|
| Pipeline pre-warm | `metal_backend.mm` `start_prewarm`, `config/metal_pipelines.txt` | at `initialize`, the depth-stencil states of the list are made at once and its render pipelines are asked of Metal asynchronously (`newRenderPipelineStateWithDescriptor:completionHandler:`); a draw takes its pipeline from them on first use, waiting only for one not made yet; a key not in the list is still made on first use |
| Pictures at the PSP's vblank | `metal_shell.mm` `present_time` | while emulated time is held to real time (the HLE passes the frame's moment, the real time of the vblank it began from), each game picture is presented at that moment plus one PSP frame (`presentDrawable:atTime:`), when the PSP shows a flip; otherwise, or when that time has passed, at once. `PURE_METAL_PACE=0` turns it off |
| The trace, the tool, the occlusion column | `metal_backend.mm`, `metal_device.hpp`, `metal_shell.mm`, `tools/frame_times.py` | above |

Neither changes a pixel: the pipelines are the ones the draws made before, and the pictures are the same, shown at other
moments. `tools/frame_regress.sh` (both window paths and headless) and `tools/hud_check.sh` pass as before (the Result
of the task file has the runs).

### After

The long frames left in the race with both changes (F, the window shown): 71 in three two-vblank stretches (14720-14752,
15226-15238, 16259-16283) and two of host contention, none with a pipeline made in it, before or after the race's
first 10 seconds. The stretches are the game's; the two others, frames whose `outside` and `draws` grew with no more
work in them, the machine's.

On screen (the drawables' presented times, the window shown):

| Run | Pictures | Shown 16.7 ms | 25 ms | 8.3 ms | 33 ms (the game's two-vblank frames) | Latency, present to screen |
|---|---|---|---|---|---|---|
| E, pictures shown at once | 10641 | 90.6% | 476 | 470 | 51 | 21.5 ms mean, 37.3 longest |
| a minimum duration of two refreshes (`presentDrawable:afterMinimumDuration:`, tried, not kept) | 11091 | 99.4% | 19 | 0 | 49 | 34.0 ms mean, 67.6 longest; `nextDrawable` held the game 4 to 22 ms in 1217 frames |
| F, pictures at the PSP's vblank | 11059 | 98.6% | 47 | 28 | 72 | 27.0 ms mean, 46.9 longest; `nextDrawable` never waited |

The minimum duration evens the pictures out further, but each late flip moves the whole schedule a refresh later and
only the game's slightly slower rate (59.94 against 60) brings it back, so the queue of drawables filled and held the
game back: two to three frames of latency. Times from the game's own vblank grid carry no host jitter and keep the
queue empty, for 5.5 ms more latency than showing each picture at once.

### The pre-warm list

`config/metal_pipelines.txt` holds 37 render pipelines and 30 depth-stencil states (task 042; 26 and 28 from the Vineta
K cell alone before it), a key a line (`render blend=1 source=4 destination=5 ...`, `depth compare=4 write=1 stencil=1
...`: the fields of `RenderKey` and `DepthStencilKey`, Metal's values for the blend factors, operations, write masks and
depth compare, the GE's for the stencil function and operations). The backend looks for it at `PURE_METAL_PIPELINES`
(`0` turns the pre-warm off), then as `metal_pipelines.txt` in an app's `Contents/Resources`, then as
`config/metal_pipelines.txt` three directories above the executable (`build/<preset>/bin` in a checkout or a worktree),
then under the working directory. The app carries a copy in `Contents/Resources` (task 042: `tools/bundle.sh` stages it
for the packer, which seals it with the app; docs/release.md), so the installed app pre-warms from it. At start it
prints `[metal] pre-warm: 37 render pipelines (made asynchronously) and 30 depth-stencil states from PATH, T ms at
start`, then `[metal] pre-warm done: ...`, and at exit `[metal] pipelines: N render pipelines used, M made by a draw (W
of them waited for the pre-warm, X not in the list), ...`.

To refresh it, run what should be covered with `PURE_METAL_PIPELINES_OUT=FILE`, which writes every key the run's draws
used at exit, and merge the files into the list (the lines are canonical, so the union of the files is the new list):

```sh
for t in vineta_k modesto_heights chenghou_project blue_ridge sinucit citta_nuova sebenco_climb sol_2 karbonis \
         sagarmatha manor_top mandrashee; do
  PURE_METAL_PIPELINES_OUT=out/keys/single_race-$t.txt python3 tools/campaign_sweep.py single_race $t --unlock-all --no-damage
done
PURE_METAL_PIPELINES_OUT=out/keys/time_trial.txt python3 tools/campaign_sweep.py time_trial vineta_k --no-damage
PURE_METAL_PIPELINES_OUT=out/keys/free_play.txt python3 tools/campaign_sweep.py free_play vineta_k --no-damage
PURE_METAL_PIPELINES_OUT=out/keys/zone.txt python3 tools/campaign_sweep.py zone zone_1
PURE_METAL_PIPELINES_OUT=out/keys/tournament.txt python3 tools/campaign_sweep.py tournament alpha --no-damage
( grep '^#' config/metal_pipelines.txt; cat out/keys/*.txt | grep -v '^#' | sort -u ) > out/list.txt
mv out/list.txt config/metal_pipelines.txt
```

(`sort -u` puts the `depth` lines before the `render` lines; the order does not matter.) The cells run headless and
silent, one at a time (the sweep's defaults and its one-game guard); a cell takes 75 s (Zone) to 6 minutes (Citta
Nuova), the Tournament 19 minutes, the whole set about 80 minutes. The new list is the union of the files alone, so a
key no draw makes any more (task 040 split two of the first list's keys into colour-test and 16-bit ones) drops out;
to keep the old keys, add `config/metal_pipelines.txt` to the `cat`. A run's exit line counts the keys "not in the
list"; each was made on first use, about 1 ms on a warm shader cache and 10 to 95 ms on a cold one. Then
`tools/bundle.sh` packs the new list into the app.

What the list covers since task 042 (2026-10-07), each cell headless with the list of task 033 (26 render pipelines,
28 depth-stencil states) in force:

| Cell | Outcome | Render keys used | Depth-stencil keys | Made by a draw (not in task 033's list) |
|---|---|---|---|---|
| Single Race Vineta K | PASS, 3 laps, 197 s | 29 | 26 | 6 render pipelines |
| Single Race Modesto Heights | PASS, 3 laps, 292 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Chenghou Project | PASS, 3 laps, 269 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Blue Ridge | PASS, 3 laps, 280 s | 29 | 24 | 6 |
| Single Race Sinucit | STALL in lap 2 (left the track at Sinucit's fork, 880 to 1010 m), 164 s | 25 | 24 | 5 |
| Single Race Citta Nuova | PASS, 3 laps, 359 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Sebenco Climb | PASS, 3 laps, 331 s | 26 | 27 | 6, and 2 depth-stencil states |
| Single Race Sol 2 | PASS, 3 laps, 264 s | 26 | 25 | 6, and 1 depth-stencil state |
| Single Race Karbonis | STALL in lap 3 (the follower left the track at 2600 to 2760 m), 180 s | 24 | 23 | 3 |
| Single Race Sagarmatha | PASS, 3 laps, 224 s | 24 | 23 | 3 |
| Single Race Manor Top | STALL in lap 1 (left the track at 2250 to 2490 m), 95 s | 24 | 23 | 3 |
| Single Race Mandrashee | PASS, 3 laps, 247 s | 24 | 24 | 3 |
| Time Trial Vineta K | PASS, 3 laps, 235 s | 32 | 25 | 9 |
| Free Play Vineta K | PASS, 3 laps, 216 s | 32 | 25 | 9 |
| Zone 1 | PASS, 6 zones, 75 s | 23 | 23 | 2 |
| Tournament, Alpha league | PASS, 4 races, 1121 s | 32 | 30 | 9, and 2 depth-stencil states |

37 render keys and 30 depth-stencil keys in all. Of task 033's list, 24 render keys and all 28 depth-stencil keys are
still used; two render keys are gone, because the draws that made them make their colour-test or 16-bit variants
since task 040. The 13 new render keys:

- the six of task 040 (four `sixteen=1`, two `color_test=1`) that the Vineta K race makes, and the other Alpha and Beta
  circuits too;
- three that only Time Trial and Free Play drew: with the six, the nine every 30-fps run made by a draw (task 041);
- three untextured blends with source factor zero, drawn only by the Tournament's screens between races;
- one colour-test key without the alpha test (`source=4 destination=1 ... alpha_test=0 color_test=1`). The Classic
  circuits and Zone draw it, and they make no 16-bit draw.

The two new depth-stencil states (depth compare 4 with a stencil test, functions 1 and 6) come from Modesto Heights,
Chenghou Project, Citta Nuova, Sebenco Climb, Sol 2 and the Tournament. The stalled cells still cover their race
loads and laps; the results screens are the same on every circuit.

A second run of each acceptance cell with the new list, the exit lines:

| Cell (second run) | Outcome | `[metal] pipelines:` exit line |
|---|---|---|
| Single Race Vineta K (`--unlock-all --no-damage`) | PASS, 201 s | 29 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Single Race Vineta K (`--no-damage`, task 033's cell) | PASS, 197 s | 29 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Time Trial Vineta K (`--no-damage`) | PASS, 246 s | 32 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Free Play Vineta K (`--no-damage`) | PASS, 222 s | 32 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |
| Zone 1 | PASS, 75 s | 23 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the list), 23 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed |

No draw of these runs made a pipeline or a depth-stencil state, and none waited for the pre-warm: on this machine's
warm shader cache the 37 pipelines were made on Metal's threads in 2.2 to 5.1 ms (`[metal] pre-warm done: ... (frame
1)`), and the pre-warm took 2.2 to 5.0 ms on the calling thread at start. On a cold cache the pipelines take longer to
make: task 033 measured 46 to 73 ms for its 26, all made by flip 4, thousands of flips before the first race load.

### Not changed

- The two-vblank stretches: the game's, outside the backend and the shell (above).
- The SIGNAL's depth write-back waits for the GPU each race frame (0.6 ms median; 13 to 40 ms a few times a race, with
  nothing in the frame's own columns to explain it: the GPU busy with other work). Reading the depth a frame late would remove the wait and move the lens flare's occlusion
  a frame: a change to the picture, left alone.
- Hashing the textures a display list binds costs about 0.5 ms a frame (`texture_ms`). Caching by address alone would
  miss a texture rewritten in place, a change to the picture; it is no long frame's cause.
- (Done in task 042.) The app (`tools/bundle.sh`) did not carry `config/metal_pipelines.txt`, so it made its
  pipelines on first use, which cost its first race after an install (the shader cache is warm afterwards). Since task
  042 the bundle ships the list in `Contents/Resources`, where the backend looks first ("The pre-warm list").
- With the window occluded macOS shows nothing and may hold `nextDrawable` back for up to a second; not a player's case.

### The Vulkan path, for comparison

`PURE_PERF=log PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=20 python3 tools/campaign_sweep.py single_race vineta_k
--no-damage --shell vulkan` (the Vulkan shell and backend, which have no trace: the framework's `[slow-frame]` line for
each frame over 20 ms, its guest, render and wait split and its stalls): 61 of the race's frames (6250-17540) were over
20 ms. 41 of them are two two-vblank stretches (12510-12527 and 14494-14516; the `[perf]` seconds over them read "game"
43 to 51 fps at speed 100%), the game's own as on Metal; the other 20 are 20 to 31 ms, a pacing sleep that woke late
beside the frame's read-backs (1 to 37 ms through MoltenVK) or a submit that waited (3 to 13 ms). The game's stretches
are the same on both paths; Metal's frames have no read-back of the picture to wait for.

## Texture mapping modes (task 036, 2026-10-07)

The GE takes a transformed draw's texture coordinates from one of three sources, chosen by TEXMAPMODE (0xC0). The
framework's GE state ignored it and TEXSHADELS (0xC1) until patch 0013, which carries both in `DrawCall::texture_map`
(`map_mode`, `proj_source`, `shade_light_u`, `shade_light_v`). `ge_vertex` computes the coordinates by the mode, so
the reflections the game draws with them (the ships' hulls and canopies, glass buildings, shiny roofs: difference 1
of docs/fidelity.md) are drawn. The Vulkan backend still draws every draw with its UVs.

The registers: 0xC0 holds the mode in bits 0..1 and the texture matrix's source (TEXPROJMAP) in bits 8..9; 0xC1 the
light s comes from in bits 0..1 and the light t comes from in bits 8..9, as the PSP SDK's `sceGuTexMapMode(mode, a1,
a2)` and `sceGuTexProjMapMode(mode)` document them. The game's own values agree: in PPSSPP's dump of the Vineta K
race frame (`ref/vineta_k_start.ppdmp`) 96 draws have 0xC0 = 2 with 0xC1 = 0x100 (lights 0 and 1) and 40 have
0xC0 = 1 (the texture matrix, from the position); the Zone dump (`ref/zone_change.ppdmp`) has 6 with 0xC0 = 2 and
0xC1 = 0x100.

The rules are PPSSPP's hardware notes' (<https://www.ppsspp.org/docs/psp-hardware/gpu/ge-vertex-pipeline/>, the UV
modes, and <https://www.ppsspp.org/docs/psp-hardware/gpu/lighting/>, "Shade mapping"), read as documentation; no
PPSSPP code was read for them:

| Mode | The GE | In `ge_vertex` (`map_texture` in `metal_shaders.h`) |
|---|---|---|
| 0, the UVs | u' = u x scale + offset (8- and 16-bit UVs divided by 128 and 32768 first) | as before: `uv_transform` |
| 1, the texture matrix | (s, t, q) = the source times the 4x3 texture matrix (three rows and the translation row, each component a row sum); the source is the position, the UV, the normalized normal or the normal, as TEXPROJMAP says (0 to 3); per pixel s/q and t/q | `texture_matrix * float4(source, 1)`, the source the vertex's object-space position, (u, v, 0), the normal normalized (a zero normal stays zero) or the normal as decoded; s, t and q interpolated, and the fragment function divides s and t by q (`FragmentUniforms::texture.w`) |
| 2, the environment (shade) map | s = (N.L' + 1) / 2 for the light in 0xC1 bits 0..1, t the same for the light in bits 8..9, in world space. N is the normal through the world matrix (not its inverse transpose), never normalized itself: the dot product is divided by its length. L' is the light's position for a directional light, else its position minus the vertex's world position, normalized (a zero vector stays zero); for a light of the diffuse-and-specular kind, normalize(L' + V), V the view matrix's third column normalized (the viewer at infinity along view-space +z, in world space). Lighting on or off, the light's enable, colours, attenuation, spot exponent and cone play no part | the same, from the light table of the lighting block (filled now for an environment-mapped draw, lit or not) and V in the vertex uniforms (`viewer`) |

Neither mode 1 nor mode 2 takes the texture scale and offset: the notes say shade mapping does not depend on them, and
name mode 0 as the scale-and-offset mode. (The task's brief expected them to apply after, as for mode 0. The game's
draws do not tell the two apart: in the port's race frame the environment-mapped draws that reach the screen carry
scale 1 and offset 0, while the 12 into the billboard target 0x04154000 and the 40 texture-matrix draws carry a v
scale of -1, by all appearances left from earlier draws; a throwaway build that applied the scale and offset in mode
2 drew the suite's 18 scenes pixel-identical to this one.) A target sampled as a texture keeps its place in the
image applied (`uv_remap`, what `uv_transform` folds in for mode 0). Reversed normals (0x51) flip N as they do for
lighting: the notes do not say, and no draw of the game's sets them. A transformed sprite keeps its UVs (its corners
are made on the CPU in clip space; none of the game's is mapped), and mode 3 is drawn as mode 0, each logged once
(`[metal] ... is not emulated`). Through-mode draws take no mapping.

How the game uses them, in the port's race frame 6016 (the recording below): 100 environment-mapped and 40
texture-matrix draws of 906. Every environment-mapped draw is unlit and blended add(FIX ffffff, FIX 000000), an
opaque base layer that the next draws, the same meshes, add their livery or lighting to; its lights are 0 and 1,
directional (in PPSSPP's Vineta K dump 24 of the 96 are of the diffuse-and-specular kind, which the viewer's
direction enters). The texture-matrix draws, four passes of ten meshes, project 128x64 and 64x64 textures onto a
horizontal plane (every vertex at one height) from the position, with an affine matrix (q is 1); in frame 6016
every one of their triangles is clipped or culled (the picture replayed to just before them and to just after them
is the same), as in PPSSPP's dump, so no capture of the suite checks mode 1.

The player's ship in frame 6016 (gerec_dump numbering): #357 to #359 are its hull and canopy, environment-mapped
(texture 0x04193300, CLUT8 64x64, the reflection); #360 to #362 the same three meshes again, lit, with the livery
(CLUT4 128x128) blended over; then the side pods (#363 to #374, six environment-mapped, then six with the livery).
#359 is the canopy: 178 pixels within PSP (225,177)-(254,232).

### The draw-level check

```sh
# frame 6016 of the race route, recorded headless through Metal (about 10 s; GAME an empty memory stick with
# EBOOT.ELF and disc.iso linked, ROUTE config/pad_scripts/main_menu.txt + single_race.txt without their shot steps)
python3 tools/run_boot.py --script ROUTE --frames 6030 --shell headless --env PURE_GAME_DIR=GAME \
  --env PURE_GE_BACKEND=record --env PURE_GE_RECORD_INNER=metal --env PURE_GE_RECORD=out/race6016.gerec \
  --env PURE_GE_RECORD_AT=6016 --env PURE_GE_RECORD_FRAMES=1 out/record.log
# the frame cut after the canopy's environment-mapped draw (#359, the 360th), with the modes and without
build/arm64/bin/PureNative --replay out/race6016.gerec --backend metal --cut 360 --out out/cut_after
PURE_NO_TEXMAP=1 build/arm64/bin/PureNative --replay out/race6016.gerec --backend metal --cut 360 --out out/cut_before
```

The recording is 8.8 MB, 1632 records; `gerec_dump.py` lists its 100 draws `envmap 0,1` and 40 `texmatrix 0`, and
the table checks (906 draws, as the backend's counter says).

The pictures cut after draw #359 (the 360th: the ship's three environment-mapped meshes drawn, the livery not yet)
show the difference plainly (the commands above make them; pictures of the game are not committed). Without
the modes the hull is the environment texture's darkest texels stretched by the meshes' UVs: nearly black, with
bright streaks along the side pods. With them it is a smooth grey shading, light where the hull faces the shade
lights and with a highlight on the canopy, the base the livery is then added to. In numbers, the two cut pictures:

| Compared | Pixels over tol 0 | Over tol 32 | Mean difference |
|---|---|---|---|
| the canopy region (225,177) 30x56, without the modes against with them | 1312 of 1680 | 1073 | 51.7 levels |
| the whole frame, the same (every mapped draw up to #359: the scenery's and the ship's) | 5644 (0.0432) | 2724 (0.0209) | |
| what #357 to #359 change in the ship's area (180,172) 120x100, with the modes (cut 357 against cut 360) | 4643 over tol 8 | | 17.9 levels |

The whole frame replayed from the recording is pixel-identical to the suite's `race_hud` capture (0 pixels over
tol 0), and against PPSSPP's reference its canopy region differs on 452 of 1680 pixels over tol 32 without the modes
and 21 with them, as the suite's captures below.

### Against PPSSPP

`tools/frame_regress.sh` (headless Metal, 2026-10-07, M4 Pro), each scene at tol 32 against its PPSSPP reference,
before (the same build with `PURE_NO_TEXMAP=1`, whose 18 captures are pixel-identical to the build before the task)
and after; the canopy region with `tools/imgdiff.py --region`:

| Scene | Whole frame before | After | Canopy region | Region before | After |
|---|---|---|---|---|---|
| `race_hud` (ref/vineta_k_start.png) | 0.0374 | 0.0262 | (225,177) 30x56 | 0.2690 (452 of 1680) | 0.0125 (21): 98.8% within tol 32 |
| `tt_hud` | 0.0617 | 0.0229 | (225,177) 30x56 | 0.2988 (502) | 0.0333 (56): 96.7% |
| `fp_hud` | 0.0620 | 0.0232 | (225,177) 30x56 | 0.2994 (503) | 0.0333 (56): 96.7% |
| `zone_hud` | 0.0348 | 0.0122 | (212,183) 66x45 | 0.3566 (1059 of 2970) | 0.0141 (42): 98.6% |
| `zone_change` | 0.0649 | 0.0353 | | | |

Each region is a rectangle around the ship's canopy: in race_hud, tt_hud and fp_hud (the same chase camera and ship,
FEISAR) the footprint of draw #359 above, PSP (225,177) 30x56; in zone_hud the Zone ship's dome, (212,183) 66x45.
The 13 frontend scenes have no mapped draws and are unchanged pixel for pixel. What stays over the tolerance in the
race scenes: the AI ships (the grid differs from PPSSPP's), the crowds' alpha-tested texels and one-pixel edges; in
the ship, a few edge pixels. In zone_hud the Zone ship's purple intake at the bottom of the screen differs as it did
before the task (not a mapped draw).

### Metal against Vulkan

Recordings made before patch 0013 hold no texture map state: their draws read as mode 0, and `metal_check.sh`'s race
comparison passes as before (the main checkout's `race_1x.gerec` of 2026-10-06, frame 6016, `--a vulkan --b metal`:
2 pixels over tol 24, PASS). A recording made since carries the modes, which Metal draws and Vulkan does not:

| `PureNative --replay out/race6016.gerec --a vulkan --b metal --frames 6016 --tol 24` | Pixels over tol 24 |
|---|---|
| as built | 2387 (0.0183): the mapped draws |
| with `PURE_NO_TEXMAP=1` | 0 |

(The recording above, made headless through Metal at 480x272, so both replay at 1x; one frame from a cold start, which
two backends start equally.) 0.0183 is under the 0.02 that `metal_check.sh`'s step 3 allows, but by little, and
what it measures there is now this task's difference, not a backend error.

So on a recording made since patch 0013 the Metal-against-Vulkan comparison is like with like only with
`PURE_NO_TEXMAP=1` (ge_replay hands the environment to both backends; the Vulkan backend has no such switch and draws
mode 0 regardless).

## Mipmaps (task 037, 2026-10-07)

The GE samples a texture from up to eight levels, each half the size of the one before, picking the level per pixel
by a rule the draw chooses. The framework's GE state ignored the levels until patch 0014, so every backend sampled
level 0 and distant textures (Blue Ridge's grandstand crowds, the track's far surface, windows) were sharper than on
the PSP and shimmered as the camera moved: difference 2 of docs/fidelity.md. Patch 0014 carries the levels in
`TextureState`; this backend uploads them and picks the level as the GE does. The Vulkan backend still samples level
0.

### The registers and the rule

The register layout is the PSP SDK's (`sceGuTexImage(level, ...)`, `sceGuTexMode`, `sceGuTexLevelMode`,
`sceGuTexSlope`, `sceGuTexFilter`); the rule is PPSSPP's hardware notes'
(<https://www.ppsspp.org/docs/psp-hardware/gpu/raster-pipeline/>, "Mip level selection", and
<https://www.ppsspp.org/docs/psp-hardware/gpu/arithmetic/>, "A float-bits logarithm"), read as documentation; no
PPSSPP code was read for it.

| Register | What | In `TextureState` |
|---|---|---|
| TEXADDRn, TEXBUFWIDTHn, TEXSIZEn (0xA0 + n, 0xA8 + n, 0xB8 + n) | level n's address (TEXBUFWIDTHn bits 16..23 its top byte), row length, log2 width and height, as level 0's | `levels[n - 1]` (`TextureLevel`: `address`, `buffer_width`, `width`, `height`) for levels 1 to 7 |
| TEXMODE (0xC2) bits 16..18 | the highest level the GE may sample | `level_count` (that plus one) |
| TEXLEVEL (0xC8) | bits 0..1 the mode (0 auto, 1 constant, 2 slope), bits 16..23 a signed bias in 1/16 levels | `level_mode`, `level_bias` |
| TEXLODSLOPE (0xD0) | a float | `lod_slope` |
| TEXFILTER (0xC6) bits 0..2 | the minification filter: bit 2 on (4 to 7) samples the levels, bit 1 linear between two levels (6, 7) or the nearest (4, 5), bit 0 nearest or linear within a level | `min_filter`, as before |

The level D, in 1/16 levels:

| Mode | D |
|---|---|
| 0, auto | log16(g) - log16(q): g the largest of the s and t planes' four screen gradients, in texels of level 0 a pixel; q the pixel's q (1/w, times the texture matrix's q) |
| 1, constant | bias |
| 2, slope | 16 + log16(slope) - log16(q) + bias |

log16(x) is the GE's logarithm, `((bits >> 19) & 0xFFF) - 127 x 16` of the float's bits: its exponent and the
top four bits of its mantissa, a piecewise linear 16 x log2 floored to 1/16. D is clamped to 0..16 x (levels - 1);
the linear mip filter blends level D >> 4 with the next by D & 15, the nearest takes level (D + 8) >> 4.

### How the game uses them

In PPSSPP's dumps of the race frames every draw with levels uses the minification filter 7 (linear within and
between levels) but three a frame (filter 1), and every level halves the one before. Blue Ridge's first full-HUD
frame (`blue_ridge_hud.ppdmp`): 830 of its 949 textured draws have levels (17 two, 18 three, 763 four, 32 five), 224
in auto mode with bias 0 and 606 in slope mode with a bias the game sets per draw (-90 to 89 in that frame, -101 to
110 over the five race dumps), the slope always 1/256 (so D = bias - 112 + 16 x log2 w). No draw uses the constant
mode, the separate CLUT per level (TEXMODE bit 8) or a through-mode draw with levels. The other race dumps
(Vineta K, Sebenco Climb, Sinucit, the zone change) are the same in kind.

### Upload

`mip_levels` gives a draw's level count: the GE's `level_count` when `min_filter` bit 2 is on, else 1 (a texture
whose draws take no levels is drawn as before). Each level after the first must be half the one before (Metal's
mipmap sizes), lie in guest memory and overlap no render target; a texture with a level that does not is drawn at
level 0 alone and named once (`[metal] texture 0x... level N ... drawn at level 0 alone`). None did in the suite's
runs or the Blue Ridge runs. `decoded_texture` makes a `MTLTexture` with that many levels and decodes each with the
framework's `decode_texture` from a `TextureState` holding the level's address, row length and size (level 0's
format, swizzle and palette), so no decoder of our own and no per-level entry point in the framework. The content
key hashes, for every level, its address, size, row length and every byte of its texels, then the palette entries
the format reaches, as before; the memo of a display list's keys (`TextureIdentity`) holds the level count and a
hash of the levels' places. A texture read from a render target has no levels.

The exit line counts the textures decoded as before, plus the draws that sampled levels and the levels decoded
after the first: `... N textures decoded, ..., M mipmapped draws (L mip levels decoded after the first), ...`. The
number of textures decoded does not change; each texture with levels adds its levels.

### The level in the shader

The sampler's mip filter (bits 4 and 5 of the sampler index) follows `min_filter` bit 1. `set_level_rule` puts the
mode, the part of D that is the same for the whole draw (0 for auto, the bias for constant, 16 + log16(slope) + bias
for slope) and level 0's size in `FragmentUniforms::level`, and 16 x (levels - 1) in `level_range`. In
`sample_texture` (`metal_shaders.h`) q is `position.w` (Metal hands the fragment 1/w there) times the texture
matrix's q, s and t are the coordinates times that q, so their `dfdx`/`dfdy` are the GE's plane gradients, and D is
the table's with the same float-bits log16; the texel is `sample(..., level(clamp(D, 0, range) / 16))`. A draw
without levels samples as before, with Metal's own derivatives on a texture of one level.

Not done, as the game does not need them: the GE takes q once per 4-pixel span rather than per pixel; the auto mode's
bias (the notes' formula has none, and the game's auto draws all have bias 0); the separate CLUT per level; and a
minification filter without bit 2 (0 to 3) on a texture with levels samples level 0, as the SDK's names for it
(nearest, linear) say, which the notes do not cover (three draws a race frame).

### The check

Headless Metal, 2026-10-07, M4 Pro. "Before" is `PURE_NO_MIPMAPS=1`, whose 18 suite captures and Blue Ridge frame are
pixel-identical to the build before the task (the suite's captures by that build, run from a tree holding its
binary, against this build's with the switch: 0 pixels differ in each).

**Blue Ridge's first race frame** against PPSSPP's (`ref/blue_ridge_hud.png` of the audit's run J, made again for
this task with the command in `ref/README.md`: the PNG and the GE dump came out byte-identical to the hashes there).
Blue Ridge has no route in `config/pad_scripts/`, so the port's frame is the audit's: main_menu.txt + single_race.txt
without their shot steps, plus DOWN at 5380, 5410 and 5440 on TRACK SELECTION, flip 6016, on an empty memory stick.

| Compared with PPSSPP | Before | After |
|---|---|---|
| the whole frame, tol 32 | 0.0392 | 0.0247 |
| the whole frame, tol 16 | 0.0912 | 0.0487 |
| the right grandstand, (300,60) 180x90, tol 32 | 0.1418 | 0.0920 |

(The audit's 0.0534 was before task 036's environment maps.) The crowds, the stands' roofs and the far track are
soft as in PPSSPP's frame; what still differs is the AI grid (other ships than PPSSPP's) and the BLUERIDGE banner,
brighter and wider in PPSSPP's frame.

**The slope rule against the reference.** The same frame with D moved by a constant in slope mode (a throwaway
switch, not kept), against PPSSPP:

| D offset (1/16 levels) | -48 | -32 | -16 | -8 | 0 | +8 | +16 | +32 | +48 |
|---|---|---|---|---|---|---|---|---|---|
| tol 32 | 0.0388 | 0.0374 | 0.0323 | 0.0298 | 0.0247 | 0.0237 | 0.0256 | 0.0352 | 0.0526 |
| tol 16 | 0.0900 | 0.0859 | 0.0675 | 0.0560 | **0.0487** | 0.0549 | 0.0664 | 0.0943 | 0.1268 |

The documented rule (offset 0) is the best at tol 16 and within half a level of the best at tol 32, so it is kept
as the notes give it. Moving the auto mode's D by -32 to +32 changes the frame by at most 0.0007 (its draws cover
little of it).

**The shimmer.** 60 consecutive flips of Blue Ridge's start straight between the grandstands (6340 to 6399, the
ship accelerating from about 110 to 200 km/h with Cross held), each against the next at tol 32:

| Region | Before: mean (min to max) | After |
|---|---|---|
| the whole frame | 0.0845 (0.0650 to 0.1149) | 0.0603 (0.0426 to 0.0926) |
| the right grandstand, (300,60) 180x90 | 0.1902 (0.1625 to 0.2466) | 0.1124 (0.0793 to 0.1887) |
| the left grandstand, (0,60) 180x90 | 0.1248 (0.0975 to 0.1546) | 0.0586 (0.0321 to 0.0862) |
| the track, (0,130) 480x80 | 0.0745 (0.0559 to 0.1007) | 0.0596 (0.0424 to 0.0874) |

The mean absolute change between consecutive frames falls from 7.30 to 5.88 levels over the whole frame (15.24 to
11.11 on the right grandstand).

**The suite** (`tools/frame_regress.sh`, tol 32): race_hud 0.0262 to 0.0149, tt_hud 0.0229 to 0.0112, fp_hud
0.0232 to 0.0116, zone_hud 0.0122 to 0.0121, zone_change 0.0353 to 0.0353 (120 pixels change); the 13 frontend
scenes are unchanged pixel for pixel (none of their textures has levels).

**Decodes.** The race route of the suite (to flip 6046) decodes 646 textures before and after, and after it 596
levels besides (192857 draws sampled levels); Blue Ridge to flip 6020, 612 textures before and after, plus 525
levels. The Time Trial route: 566 textures both, plus 361 levels; Zone: 433 both, plus 52 levels.

### Recordings

Until patch 0017, `record_backend.cpp` recorded the bytes level 0's texels lie in, not the other levels'. A
recording made with patches 0014 to 0016 replays with the levels after the first decoded from whatever ge_replay's
guest memory holds there (zero unless an earlier record wrote it), so a replay of a mipmapped draw is not the game's
picture; replay such recordings with `PURE_NO_MIPMAPS=1`. Since patch 0017 the record backend writes every level a
draw samples, and a recording replays exactly ("The colour test, 16-bit writes and the depth clamp", "Recordings"). Blue Ridge's
frame 6016 recorded through Metal replays 0.0913 off its recorded picture at tol 32 (336 of the frame's mipmapped
draws in PPSSPP's dump have their texture in main memory); recorded and replayed with `PURE_NO_MIPMAPS=1` it is
exact, and `gerec_dump.py --draws` parses the recording (831 draws with levels, listed `levels N auto|slope bias B
slope S`). Older recordings read as one level and replay as before (the main checkout's `race_1x.gerec` parses as
it did).

## The colour test, 16-bit writes and the depth clamp (task 040, 2026-10-07)

Three GE states the framework's GE state ignored until patch 0017, which carries them in `DrawCall::color_test`
(`ColorTestState`), `DrawCall::dither` (`DitherState`) and `DrawCall::clip_enabled`: differences 10 and 11 of
docs/fidelity.md. The Vulkan backend draws none of them.

### The registers and how the game uses them

| Register | What | In the draw state |
|---|---|---|
| COLORTESTENABLE (0x27), COLORTEST (0xD8), COLORREF (0xD9), COLORTESTMASK (0xDA) | the switch; the function in bits 0..1 (0 NEVER, 1 ALWAYS, 2 EQUAL, 3 NOTEQUAL); the reference and the mask, colours as 0x00BBGGRR | `ColorTestState`: `enabled`, `function`, `reference`, `mask` |
| DITHERENABLE (0x20), DITH0 to DITH3 (0xE2 to 0xE5) | the switch; the 4x4 matrix, DITHn the row for the pixels whose y & 3 is n, four signed 4-bit offsets, the one for x & 3 in bits 4 (x & 3) to 4 (x & 3) + 3 | `DitherState`: `enabled`, `rows`, `offset(x, y)` |
| CLIPENABLE (0x1C) | on: transformed primitives clipped at the near plane, each vertex's screen z clamped to 0..65535 | `clip_enabled` |

The command numbers are those of the framework's list of ignored commands (docs/fidelity.md, the feature table) and
the PSP SDK's `sceGuColorFunc` and `sceGuSetDither`; the numbers in the task's brief (0xE1, 0x23, 0xE2 for the colour
test, 0x25 and 0xD0 to 0xD3 for dithering, 0x1D for CLIPENABLE) are other registers (FIXB, the depth test switch,
anti-aliasing, TEXLODSLOPE, culling). The ten commands left the list: 30 distinct remain, from 40.

The matrix's orientation and the dither rule are the ones PPSSPP's software renderer (documented as exact for
dithering and 16-bit conversion, "Per-pixel operations" of the raster pipeline notes) shows. PPSSPP's dump of the
Vineta K frame (`ref/vineta_k_start.ppdmp`) holds the 565 billboard target as its fourth round left it (the
FRAMEBUF record at draw 82): one flat colour, the round's first draw (vertex colour 0xE5E5E5 over the whole target)
dithered by the matrix D71B 5F93 D71B 5F93. Taking the 8-bit value 229 plus the offset at (x & 3, y & 3) with DITHn
as row y & 3, clamped to 0..255 and cut to its top 5, 6 and 5 bits, gives PPSSPP's pixel at all 16384 pixels (its five
colours); with the matrix read the other way round (DITHn as column x & 3), 6144 at best.

In PPSSPP's dumps of the race frames:

- **The colour test**: 3 to 14 draws a frame, always NOTEQUAL to black under the full mask, all textured, blended
  add(SA, FIXB FFFFFF) with the depth write off and the alpha test GREATER 0: light glows. Some write the stencil
  255 that is the bloom's mask (STENCILTEST ALWAYS, zpass REPLACE), and one or two draw into the billboard target.
  Under an additive blend a black fragment adds nothing to the colour, so what the test changes is the stencil (the
  bloom mask) where a glow's texels are black.
- **Dithering**: on every draw into the 565 billboard target (8 to 60 a frame), never on a draw into an 8888 target.
  The game changes the matrix: Blue Ridge's frame has one (CE02 468A), Vineta K's a different one for each of its four
  rounds (the rows' nibbles rotated), the menus and Zone set one but never enable dithering. Of
  Vineta K's 60 draws into the 565 target 17 are opaque, 9 add(FIXA FFFFFF, FIXB 000000), 23 add(SA, 1-SA), 9
  add(FIXA FFFFFF, FIXB FFFFFF) and 2 add(SA, FIXB FFFFFF): 43 blend with what is there.
- **CLIPENABLE**: on for every transformed draw of all 18 dumps. MINZ and MAXZ are the viewport's own z range, one
  step inside it at the far end (1001 and 64946 for z scale -31973 and offset 32973, which map z/w = 1 and -1 to 1000
  and 64946; 0 and 946 for the sky's draws; 65001 and 65481 for a few draws given a thin slice at the front of the
  depth range).

### The colour test

`shade()` in `metal_shaders.h` tests after fog, where the alpha test is done: the fragment's colour in 8-bit steps
under the mask, against the reference under the mask, and `discard_fragment` when the function says so, which writes
no colour, depth or stencil. The function constant `kColorTest` (a field of `RenderKey`) compiles it into the draws
that have it; ALWAYS is compiled out, as for the alpha test. The documentation does not give the order of fog and the
colour test (it matters for fogged draws: fog moves a black fragment off black); the test follows the alpha test's
place, after fog.

### 16-bit targets: where the bits are kept, and the dither

**Where the 16-bit quantisation happened before this task: nowhere a picture reads.** Every target is an RGBA8
texture, 5650, 5551 and 4444 ones too, and the backend cut a 16-bit target's colour to its format only when it stored
the target in guest memory (`store_pixels`: block transfers, read-backs and the frame write-back, 5650 as r >> 3,
g >> 2, b >> 3). The race's 565 billboard target is drawn by four rounds a frame and sampled on the GPU straight from
its RGBA8 texture by the billboard draws, so it kept 8 bits a channel, and a dither offset applied at the store would
change nothing on the screen. Applying the offset to the fragment's colour before Metal's blend would not be the GE's
rule either: the PSP blends, then adds the offset, then keeps the format's bits, and 43 of the 60 draws into the
target blend.

So a draw into a 5650, 5551 or 4444 target now writes what the PSP writes. It goes through `ge_fragment_16`
(`RenderKey::sixteen`), which reads the target's colour (`[[color(0)]]`, the programmable blending of Apple GPUs; the
pipeline does not blend), blends with the GE's own factors and equation (the FIX colours exact, the doubled factors
and ABSDIFF too, which the pipeline's blend draws approximately: `ge_factor`, `ge_blend`), adds the dither matrix's
offset for the pixel when DITHERENABLE is on, clamps once to 0..255, keeps the format's top bits (5, 6 and 5; 5, 5
and 5; 4, 4 and 4) and writes the 8-bit value they expand to by repeating their bits, which `store_pixels` packs back
to the same bits. The alpha, the PSP's stencil, is written as before. A clear into a 16-bit target keeps the bits but
is not dithered: the documentation does not say whether the GE dithers a clear, and the game's clears of the billboard
target are black and covered by every round. The order of the offset and the clamp (one clamp after the offset) is
not stated by the documentation either; it shows only for blends that overflow. 8888 targets are drawn as before.

**The check.** Race frame 6016 recorded through Metal (the command in "Texture mapping modes", with the build of this
task) and replayed with `--cut` at the end of each billboard round, the target shown with
`PURE_METAL_SHOW_TARGET=0x04154000`, before (`PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1 PURE_NO_DEPTH_CLAMP=1`) and after,
against the target as PPSSPP's dump holds it after each of its rounds (draws 26, 45, 69 and 82, `ppdmp.py tex`):

| Picture | Pixels that are 565 values | Flat 4x4 blocks ordered as the round's matrix | The rule applied to the before picture |
|---|---|---|---|
| PPSSPP, rounds 1 to 4 | 1.0000 in each | 0.9943 (874 blocks), 1.0 (921), 0.1171 (222: a vertical gradient), 1.0 (1024) | |
| port before, rounds 1 to 4 (cut 42, 72, 84, 98) | 0.5560, 0.0721, 0.0000, 0.9963 | no block with any dither | |
| port after, rounds 1 to 4 | 1.0000 in each | 1.0 (710 blocks), 1.0 (831), 1.0 (936), 1.0 (1009) | 1.0000, 1.0000, 1.0000, 0.9998 of the pixels |

"Flat 4x4 blocks" are the matrix-aligned blocks whose 5-, 6- and 5-bit values span at most two steps (four in green)
and are not all equal, where a flat colour shows its dither; "ordered as the matrix" means that in every channel no
pixel with a larger offset has a smaller value, which an ordered dither by that matrix always gives (PPSSPP's third
round is a gradient across the blocks, which the measure does not allow for). The last column applies the PSP's rule
(the offset, the clamp, the top bits) to the before picture's 8-bit pixels and compares with the after picture: exact
wherever the last write to a pixel did not blend with an earlier one. The two runs show different adverts at that
moment (the billboards cycle through them: PPSSPP's first round is the red PIRANHA advert, the port's an orange one),
so their pixels are not compared one to one.

### The depth clamp

The hardware notes (<https://www.ppsspp.org/docs/psp-hardware/gpu/ge-vertex-pipeline/>, "Z Clipper", "Clipping
enabled", "MinZ and MaxZ", "Z Clamp") give the rule with CLIPENABLE **on**: transformed triangles and lines are
clipped at the near plane (z = -w) and nowhere else; each vertex's screen z is clamped to 0..65535 before it is
interpolated; the part of a primitive beyond the far plane is drawn at its interpolated depth, and only the per-pixel
MINZ/MAXZ test removes it. With CLIPENABLE off the GE does not clip at the near plane at all and drops a primitive with
a vertex outside 0..65535 in screen z or behind the eye. (The task's brief expected the clamp with CLIPENABLE off; the
notes put it with the switch on, which is how the game draws every transformed draw.) The MINZ/MAXZ test is not done in
through mode: the bloom's through-mode sprites lie at z 0 under MINZ 1001 and are drawn on the PSP.

With CLIPENABLE on the backend now draws a transformed draw that way. `ge_vertex` computes the GE's screen z times w
(z times the z scale plus w times the z offset), clamps it to 0..65535 w for a vertex in front of the near plane, and
hands z / 65535 to a viewport of 0..1; the near plane and MINZ and MAXZ are three clip distances on that z (which,
like the depth, is linear across the screen, so cutting at MINZ is the per-pixel test); the encoder's depth clip mode
is `MTLDepthClipModeClamp`, so Metal no longer clips at the far plane. A vertex behind the near plane keeps its z
unclamped, so the clipper's new vertex on the near plane gets the z the GE gives it. CLIPENABLE off is drawn as before
(clipped at both planes) and named once (`[metal] CLIPENABLE off on a transformed draw ... is not emulated`); no draw
of the game's has it off, and a recording made before patch 0017 reads as off, so it replays as it did.

For this game the clamp changes nothing on the screen, which is what the documentation predicts for its draws: in
PPSSPP's 18 dumps no vertex in front of the near plane lies beyond the far plane (z/w at most 0.9999, on Blue Ridge),
every such vertex's screen z lies within MINZ..MAXZ, and MINZ/MAXZ are the viewport's own range, so the near plane,
the far plane and the test cut where Metal's clipping cut. The suite's 18 captures with the clamp alone
(`PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1`) are pixel-identical to the build before the task, and the race recording
replays to the same picture with and without it. The reference cannot show the rule either way, so the brief's
escalation (the rule against the reference) did not arise.

### What changed on the screen

Headless Metal, 2026-10-07, M4 Pro, against PPSSPP at tol 32 (`tools/frame_regress.sh`, "before" the same build with
the three switches, whose 18 captures are pixel-identical to the build before the task):

| Scene | Before | After | Pixels changed (tol 0) | By |
|---|---|---|---|---|
| race_hud | 0.014874 (1942) | 0.014828 (1936) | 723 | the colour test 640 (a lamp's glow, (307,107) 26x34), the billboard 83 |
| tt_hud | 0.011221 (1465) | 0.011213 (1464) | 377 | the billboards |
| fp_hud | 0.011566 (1510) | 0.011336 (1480) | 413 | the billboards |
| the other 15 scenes | | unchanged | 0 | |

| Region against PPSSPP | tol 32 before | after | tol 16 before | after |
|---|---|---|---|---|
| race_hud, the lamp's glow (307,107) 26x34 | 0.0328 (29 of 884) | 0.0260 (23) | 0.2285 (202) | 0.1765 (156) |
| race_hud, the billboard screen (201,126) 16x8 (draw #42's footprint, 127 pixels) | 0.8828 (113 of 128) | 0.8828 (113) | 0.9063 | 0.9063 |
| tt_hud, the billboard screen (195,114) 29x29 | 0.4245 (357 of 841) | 0.4221 (355) | 0.4828 | 0.4828 |
| fp_hud, the billboard screen (195,114) 29x29 | 0.4269 (359 of 841) | 0.3912 (329) | 0.4816 | 0.4828 |

The billboard screens show other adverts than PPSSPP's frames do (a different moment of the adverts' cycle), which is
nearly all of their difference; what the task changes there is the dither and the 16-bit steps of the content. The
colour test's effect is the bloom: the glows' black texels no longer write the bloom mask's stencil 255, so the bloom
no longer spreads the scene under them.

### Recordings

Patch 0017 also makes `RecordBackend::submit` record the texels of every mip level a draw samples (levels 1 to
`level_count` - 1 when the minification filter's bit 2 is on), each from its own address at its own size. Race frame
6016 recorded through Metal now replays into Metal exactly without `PURE_NO_MIPMAPS` (0 pixels over tol 0; the
recording is 8.9 MB, 611 Memory records against 283), where a recording of the same frame made with patch 0014's
record backend replays 0.0119 off at tol 0. Blue Ridge's first race frame (the audit's route, flip 6016), the
frame task 037 found 0.0913 off at tol 32, recorded the same way replays exactly too (0 pixels over tol 0, 974 draws);
against PPSSPP it scores 0.024732 at tol 32 both before and after this task (27 pixels change, none by more than 8:
its billboards).

A Draw record ends with the colour test, dithering and CLIPENABLE (`kPixelBytes`, 31 bytes); a Draw that ends before
them reads as no colour test, no dithering and CLIPENABLE off, so the older recordings replay as before. `gerec_dump.py`
lists `ctest FUNCTION REFERENCE/MASK`, `dither ROWS` and `noclip`.

On a recording made since patch 0017, Metal against Vulkan (`PureNative --replay ... --a vulkan --b metal --frames
6016 --tol 24`, race frame 6016): 5149 pixels over tol 24 as built (the texture map modes and mip levels, which the
Vulkan backend does not draw either), 3 with `PURE_NO_TEXMAP=1 PURE_NO_MIPMAPS=1` (with `PURE_NO_COLOR_TEST=1
PURE_NO_DITHER=1` as well, still 3), 2 with `PURE_NO_DEPTH_CLAMP=1` too, task 025's figure. The one pixel the depth
clamp moves in that configuration, (146,124), is a depth tie between two draws that the clamp's depth arithmetic
(z times the z scale plus w times the offset, over 65535) rounds the other way from the viewport's; as built, no pixel
of the frame or of the suite's 18 scenes moves with the clamp.

The pre-warm list (`config/metal_pipelines.txt`) had none of the new keys: a race run made 6 render pipelines on
first use (four `sixteen=1`, two `color_test=1`), 1.2 ms at its first race frame and 0.24 ms later on this machine
(`PURE_METAL_TRACE`). Task 042 refreshed the list with them ("The pre-warm list").

## What is not done yet

| Task | What |
|---|---|
| 027 (landed) | what the Metal shell leaves out ("The Metal shell"): frame interpolation, the Fill aspect, the touch controls, the performance overlay, and the menu's resolution, texture filter and texture-pack rows |
| enhancements | drawing above 480x272 (an internal scale above 1, which D-002 leaves for after the native picture) and texture packs, both the Vulkan renderer's today |

The race exercises neither `read_back_framebuffer` nor a block transfer from a target (its transfers come from
main memory), and the frontend calls only `write_back_frame`: the 16-bit store formats and the transfer's row range
are written to the rules above and the Vulkan backend's, and checked by no recording yet.

Not in the draw state (`DrawCall`), so neither backend draws them, and they wait for the framework's GE state to
carry them: logic ops, the texture environment colour (the blend texture function's) and colour doubling. The texture
map modes are carried since patch 0013 and drawn by this backend since task 036, the mip levels since patch 0014 and
task 037, the colour test, dithering and CLIPENABLE since patch 0017 and task 040 (which also reads MINZ/MAXZ, carried
in `DepthState` all along). CLIPENABLE off on a transformed draw (no near-plane clipping; a primitive with a vertex
outside 0..65535 or behind the eye dropped) is not emulated: such a draw is clipped at both depth planes as before
and named once; the game never draws one.

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
- The texture map modes are drawn (task 036): the texture matrix (mode 1) and the environment map (mode 2). The
  Vulkan backend draws every draw with its UVs, so on a recording made since patch 0013 the race differs between the
  two by every mapped draw ("Texture mapping modes", the A/B).
- Mip levels are uploaded and sampled at the level the GE's rule picks (task 037, "Mipmaps"); the Vulkan backend
  samples every texture at level 0.
- The colour test drops fragments, 16-bit targets keep the format's bits with the GE's dithering, and CLIPENABLE's
  depth clamp and MINZ/MAXZ are applied (task 040); the Vulkan backend keeps every fragment, draws 16-bit targets at
  8 bits a channel and clips at both depth planes. On a recording made since patch 0017 the race differs between the
  two by the colour test and the billboard target's bits (`PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1` makes the Metal
  side draw as before).
- Transformed draws are clipped only at the target's edges and the scissor, as the GE clips them: the GE viewport is
  folded into clip space and the Metal viewport is the whole target. The Vulkan backend makes the GE viewport its
  `VkViewport`, which clips at the viewport's edges: the race's HUD is drawn with a viewport shifted one pixel right
  and down (x offset 2048 - 1807), so there the Vulkan backend leaves column 0 and row 0 undrawn ("The race check").
- A block transfer from a target writes back only the target's rows the copy reads, from targets of any width; the
  Vulkan backend writes back the whole target, only for screen-wide ones.
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
3. (task 025) `--replay out/gerec/race_1x.gerec --a vulkan --b metal --frames 6016 --tol 24 --max-frac 0.02` must
   pass; on a failure the first differing draw is printed and both pictures after it are kept ("The race check");
4. for the record, race frame 6016 into both, bisected with `--first-diff --tol 24`: (a) `race_1x.gerec`, (b)
   `race_warm.gerec`. (Task 024 had these as step 3, before the race could pass.)

### Choosing the frame

The brief asked for a TEAM SELECTION frame with the ship model lit and no bloom or stencil draw in the list. There is
none: no frontend frame has a lit draw at all. The route run on Metal with `PURE_METAL_LOG=1` to frame 5760 (151590
draws, a line each, `lit`, `fog` and `cull` among the tags) gives:

| Frames | Screen | Draws a frame | Lit | Fogged | Stencil | Bloom targets | Depth-tested |
|---|---|---|---|---|---|---|---|
| 1-5707 | boot, language, title, profile, menus, CLASS, LEAGUE, TRACK, TEAM, loading | up to 81 | 0 | 0 | 0 | 0 | 2 a frame at 5-123 (boot), 13 at 5702-5706 (loading) |
| 5503-5701 | TEAM SELECTION (within the line above) | 59-81 while it comes in, 65-69 from 5531 | 0 | 0 | 0 | 0 | 0 |
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
| race frame 6016 against PPSSPP (`tools/frame_regress.sh --backend metal --only race_hud`) | 0.2978 at tol 32, limit 0.10 (task 023: 0.2977; Vulkan 0.0672): FAIL, not yet a pass condition. The red is the track, the ships and the stands under the stencil-gated darkening quad, which without the stencil dims the whole screen, and the missing bloom: both 025's, and large enough to hide what lighting changed |

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
scale 1/1230 towards the colour register 0xCCA38E (0xBBGGRR) or black, end 1270 and scale 1/770 towards 0xEDFCFF,
end 5001 and scale 1 towards grey). No point or spot light, no specular, no powered diffuse, no reversed normals, no separate specular: those
are ported from `ge.vert` as they are and checked by nothing but the port.

In the replays Metal takes 4 to 6 ms a race frame and Vulkan 5 to 10 (each including its capture).

## The race check (task 025)

`tools/gerec/metal_check.sh` step 3 replays `out/gerec/race_1x.gerec` (frames 6008-6016 at internal scale 1, both
backends at 480x272) into vulkan and metal and requires frame 6016 within `--tol 24 --max-frac 0.02`; when it
fails it bisects with `--first-diff`, prints the first differing draw's state and keeps both pictures after that
draw (`--cut`, in `out/gerec/metal_race_cut/a` and `b`). Step 4 bisects the frame for the record at tol 24 with no
fraction allowed, at 1x and at 2x (`race_warm.gerec`). The recording used here was made on 2026-10-06 by the main
checkout's metal_check run (frame 6016: 864 draws; task 024's had 906: the AI field differs from run to run).

### Numbers (2026-10-06, M4 Pro)

| Comparison | Result |
|---|---|
| `race_1x.gerec` frames 6008-6016, vulkan against metal | each within 2 pixels over tol 24 (0 to 0.000015): PASS |
| frame 6016, pixels over tol 0, 1, 4, 8, 16, 24 | 553, 77, 24, 18, 3, 2 (of 130560) |
| frame 6016 after draw 393 (`--cut 393`), task 024's first stencil draw | 0 pixels over tol 24 |
| frame 6016 with task 024's backend | 0.3246 at tol 24 (42380 pixels): no shadows, the darkening over the whole screen, no bloom |
| `--first-diff --tol 24` (no fraction) | draw 508 of 864, one pixel: an alpha-tested crowd strip (below) |
| `race_warm.gerec` (2x) frames 6014, 6015, 6016 | 0.0777, 0.0788, 0.0804 at tol 24 (task 024: 0.3768 for 6016): edges and the crowds' texture detail moved by the 2x-to-1x reduction, accumulating from the first alpha-tested draws (`--first-diff --max-frac 0.02` passes 2% at draw 261 of 906, an opaque strip) |
| race frame 6016 against PPSSPP (`tools/frame_regress.sh --backend metal --only race_hud`) | 0.0379 at tol 32 (4954 pixels), limit 0.10: PASS, twice (the verify run and an earlier one). Task 024: 0.2978; the Vulkan backend 0.0672 (runs 0.063 to 0.086, the AI grid varies) |

Metal draws the race with the effects in: shadows under the ships, the bloom on the light strips and the screens, the
lens flare. Against PPSSPP, what stays over tol 32 in race_hud is the AI ships (the grid differs from run to run),
the crowds' alpha-tested texels, parts of the player's ship and one-pixel edges (`imgdiff.py --out`). The pictures of
frame 6016 after the whole frame differ in three places, all small, which item 5 of the brief asked to classify:

| Pixels | Levels | First draw (ge_replay numbering) | What it is | Whose |
|---|---|---|---|---|
| column 0, rows 244-263 (20) | 5-11 | 837 (gerec_dump #836): the HUD's LAP panel, a transformed sprite from x -2 to 12, blended add(SA, 1-SA) | the HUD is drawn with a GE viewport whose offsets are 2048 - 1807 and 2048 - 1911, one pixel right and down of the world's (1808, 1912), so on the screen it covers x -1 to 13. The Vulkan backend makes the GE viewport its `VkViewport`, which then starts at x 1, and clips everything left of it: column 0 keeps the scene, 9 to 11 levels brighter. The GE clips x and y only at the scissor (0,0)-(479,271) (it clips on z = -w and drops triangles outside its 4096-pixel space: the coverage rules of `tools/ppsspp/ppdmp.py cover`, docs/ge-effects.md task 010) and draws column 0, as Metal does. PPSSPP's dump of frame 7155 draws the same sprite (its #843 and #844, x -2 to 12) | a Vulkan difference against the GE's rule; not matched. Both pictures after the draw: `--frames 6016 --cut 837 --out DIR` (in the task's run, rows 244-263 of column 0 are 149-162 in Vulkan's, the scene unchanged, and 142-158 in Metal's, the panel over it) |
| (342,131), (464,115), (439,125) | 20-36 | 508, and later crowd strips | crowd strips alpha-tested GREATER 0x7F on bilinear-filtered CLUT4 texels: a texel alpha at the threshold falls on either side in the two backends (their texture coordinates and filtering are computed by different instruction sequences), so one pixel passes in one and not the other | neither: rounding at a test's threshold |
| 24 pixels over tol 4 in all, the two rows above included | 5 or less elsewhere | from draw 299 on | interpolation and blending rounding | neither |

Nothing else differs by more than 4 levels, so nothing in the race is drawn by another rule in Metal than in Vulkan
except the viewport clipping above. The 2x recording adds no other finding: its differences are the reduction's.

### The lens flare

The depth write-back is asked for at every race frame's SIGNAL 0x200 (339 in the route, frames 5707-6045) and
writes the back buffer's z into 0x04110000. The race route holds Cross from frame 6100, so the player's ship runs
along the first straight's left wall, and at frame 6690 the sun is behind the left pillar (docs/ge-effects.md, the
depth write-back). Two windowed runs of the route to frame 6700 with `PURE_TRACE_DEPTH_READBACK=1`, one per backend,
put the ship in the same place and give:

| Frame | Metal: z written, mean luma around the sun | Vulkan: the same | Task 019 (Vulkan) |
|---|---|---|---|
| 6016, open sky: the flare drawn | 23-13433, 225.8 | 23-13443, 225.9 | 225.7 |
| 6690, sun behind the pillar: no flare | 22-13415, 111.2 | 22-13431, 111.6 | 105.2 with the write-back, 176.5 without |

(Mean luma 0.299 R + 0.587 G + 0.114 B over PSP (100,40) 90x100, the region task 019 measured.) So the game's
4x4 depth test sees the pillar in Metal's depth as in Vulkan's, and drops the flare.

### Cost

Over the race route to frame 6046 (339 race frames), counted by the backend's exit line:

| Run | GPU waits (ms) | Frame write-backs: stored/asked, waited | Depth write-backs: stored/asked, waited | Stencil copies |
|---|---|---|---|---|
| Vulkan shell (`frame_regress.sh --backend metal --only race_hud`) | 6383 (3134) | 6043/6046, 0 ms (the hand-over's read-back reused) | 339/339, 236 ms (0.70 ms each) | 339 |
| Vulkan shell, `MTL_DEBUG_LAYER=1` (the acceptance run) | 6383 (3325) | 6043/6046, 0 ms | 339/339, 283 ms (0.83 ms) | 339 |
| Metal shell (`PURE_SHELL=metal`, `PURE_PERF=log`) | 353 (254) | 6043/6046, 46 ms in 14 waits, the rest already drawn | 339/339, 209 ms (0.62 ms) | 339 |

So a race frame waits for the GPU once, at its SIGNAL, for about 0.6 to 0.8 ms (the flare's depth; in the drive runs
above, Metal's write-back took 0.8 to 0.9 ms at frames 6016, 6400 and 6600 and the Vulkan backend's 1.0 to 1.4 ms),
plus, under the Vulkan shell, the hand-over's read-back at the flip (0.48 ms on average). Under the Metal shell the
race runs at 59.9 to 60.0 fps, frame 16.7 ms (guest 2.1 to 2.6, render 3.2 to 3.4, pacing wait 10.7 to 11.3 ms). None
of the runs printed a `[metal] ... not implemented` line, and the one with Metal's API validation (`Metal API
Validation Enabled`) reached frame 6046 with no validation error. The race's 570 to 606 block transfers (the number
varies from run to run) come from main memory, so none is written back.

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

### Task 024

`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal --only
lang,title,profile` (2026-10-06, M4 Pro): metal_check PASS (6 s with its recordings made; team frames 0.000000 at
tol 24, the race bisected to draw 394 at 1x and to draw 40 at 2x), and the three frontend scenes at their task 023
fractions: `lang` 0.0002, `title` 0.0002, `profile` 0.0000. `tools/frame_regress.sh` (Vulkan): 5/5 at the fractions it
had (0.0544, 0.0302, 0.0543, 0.0331, 0.0672), its five captures pixel-identical to the main checkout's run of
2026-10-06 07:30-07:36.

### Task 025

`tools/build.sh profile && tools/gerec/metal_check.sh && tools/frame_regress.sh --backend metal` (2026-10-06, M4
Pro): metal_check PASS in 5 s with its recordings present (team frames 0.000000 at tol 24; race_1x frame 6016
0.000015 at tol 24, 2 pixels, PASS; bisected for the record to draw 508 at 1x and draw 40 at 2x), and the suite 5/5:
`lang` 0.0002, `title` 0.0002, `profile` 0.0000, `main_menu` 0.0106 (tasks 023 and 024's fractions) and `race_hud`
0.0379 (limit 0.10), in 7m 12s. In those runs the backend stored the frame in guest memory at 2127 of 2130 flips
(frontend), 4727 of 4730 (main menu) and 6043 of 6046 (race) with no wait of its own, and waited for the GPU 2128,
4728 and 6383 times (1024, 2195 and 3149 ms), as many times as before task 025 plus the race's 339 depth write-backs
(250 ms). `tools/frame_regress.sh` (Vulkan): 5/5 at 0.0544, 0.0302, 0.0543, 0.0331 and
0.0673 (race_hud's AI grid varies; 0.0672 before), in 7m 8s, its four frontend captures pixel-identical to the main
checkout's run of 2026-10-06 07:54. The race route on Metal ran to frame 6046 with `MTL_DEBUG_LAYER=1` (Metal API
validation on) without a validation error or a `[metal] ... not implemented` line ("Cost" above). Beyond the Verify
line, `tools/frame_regress.sh --shell metal --backend metal` (no Vulkan at all, M6's exit check) passes 5/5 with the
same five fractions (0.0002, 0.0002, 0.0000, 0.0106, 0.0379) in 7m 10s.

### Task 036

`tools/verify_task.sh 036` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh && python3
tools/imgdiff.py out/regress/shots/race_hud.png ref/vineta_k_start.png --max-frac 0.032 --tol 32`, 2026-10-07, M4
Pro): 13 patches reproduce the vendor tree; the suite passes 18/18 headless in 24 s, the 13 frontend scenes at their
fractions and the race scenes at race_hud 0.0262, tt_hud 0.0229, fp_hud 0.0232, zone_hud 0.0122 and zone_change
0.0353 (the table's metal column, from before the task: 0.0379, 0.0617, 0.0620, 0.0348 and 0.0649; the suite flags
tt_hud and fp_hud as moved by more than 0.03); race_hud 0.026180 at tol 32 against the Verify's 0.032: PASS. Beyond
the Verify line: `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its
vulkan column (19m 49s); `tools/hud_check.sh` (the Metal shell) 61 of 61 shots with the HUD; `PURE_NO_TEXMAP=1`
gives the 18 captures of the build before the task pixel for pixel; the framework's list of ignored GE commands is
63 long in every run (0xC0 and 0xC1 left it); the main checkout's `race_1x.gerec` of 2026-10-06 replays Vulkan
against Metal as before (frame 6016, 2 pixels over tol 24). "Texture mapping modes" has the draw-level check and the
canopy regions.

### Task 037

`tools/verify_task.sh 037` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh &&
tools/hud_check.sh --shell headless`, 2026-10-07, M4 Pro): 14 patches reproduce the vendor tree; the suite passes
18/18 headless in 25 s, the 13 frontend scenes at their fractions and pixel for pixel as before, the race scenes at
race_hud 0.0149, tt_hud 0.0112, fp_hud 0.0116, zone_hud 0.0121 and zone_change 0.0353 (the metal column: 0.0262,
0.0229, 0.0232, 0.0122, 0.0353); hud_check 61 of 61 shots with the HUD. Beyond the Verify line:
`tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its vulkan column
(19m 48s); `tools/hud_check.sh` (the Metal shell, windowed) 61 of 61; `PURE_NO_MIPMAPS=1` gives the 18 captures of the build before the task pixel for pixel; the framework's
list of ignored GE commands is 40 long in every run (63 before: TEXADDR1 to 7, TEXBUFWIDTH1 to 7, TEXSIZE1 to 7,
TEXLEVEL and TEXLODSLOPE left it); no run refused a level or printed a new `not emulated` line. "Mipmaps" has the
Blue Ridge frame, the shimmer sequence and the decode counts.

### Task 040

`tools/verify_task.sh 040` (`tools/patches.sh check && tools/build.sh profile && tools/frame_regress.sh`, 2026-10-07,
M4 Pro): 16 patches reproduce the vendor tree (0001 to 0015 and 0017; 0016 is reserved); the suite passes 18/18
headless in 24 s, the 15 other scenes pixel for pixel as before (Zone's colour-tested draws change none of their pixels),
race_hud 0.0148 (0.0149 before), tt_hud 0.0112 (0.0112), fp_hud 0.0113 (0.0116). Beyond the Verify line:
`tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18, every scene within 0.0005 of its vulkan column
(19m 47s); `tools/hud_check.sh --shell headless` 61 of 61 shots with the HUD; `PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1
PURE_NO_DEPTH_CLAMP=1` gives the 18 captures of the build before the task pixel for pixel, and each feature alone
moves only the pixels "What changed on the screen" names (the depth clamp none); the framework's list of ignored GE
commands is 30 long in every run (40 before: 0x1C, 0x20, 0x27, 0xD8 to 0xDA and 0xE2 to 0xE5 left it); no run printed
a `not emulated` line. "The colour test, 16-bit writes and the depth clamp" has the dither check and the regions.
