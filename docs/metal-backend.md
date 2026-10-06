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
pictures in a window of its own, with no Vulkan involved.

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
| `tools/gerec/metal_check.sh` | the 3D and race checks (tasks 024 and 025): Metal against Vulkan through ge_replay on the TEAM screen and the race ("The 3D check", "The race check") |
| `src/host/metal_shell.mm` | the Metal shell (task 027): `MetalShell : portablekit::host::Shell` and its `ShellRegistration("metal", ...)`. Objective-C++ with ARC |
| `third_party/imgui_metal/` | Dear ImGui's Metal renderer backend, `imgui_impl_metal.h` and `imgui_impl_metal.mm` from the 1.92.9b release (the vendored ImGui's), verbatim, MIT |
| `CMakeLists.txt` | the sources in `portablekit_add_game(... SOURCES ...)`, the three `.mm` compiled with `LANGUAGE CXX` and `-x objective-c++ -fobjc-arc`, `third_party/imgui_metal` on the include path, and `-framework Metal`, `Foundation`, `QuartzCore` and (for the shell's sRGB colour space) `CoreGraphics` linked |

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
| Blend | Metal's blend units for the GE factors and the equations ADD, SUBTRACT, REVERSE SUBTRACT, MIN and MAX (MIN and MAX take no factors). A FIX source factor is applied in the shader (the colour arrives multiplied, the blend takes it ONE), so any pair of FIX colours is exact, unless the destination factor reads the source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour. The doubled factors (2xSA and so on) are drawn single and ABSDIFF as ADD, each logged once (`[metal] ... is not emulated`). A draw that stores a stencil value under a blend that reads the source alpha blends with the fragment's own alpha from a second output (dual-source blending, below). The alpha channel's own blend stores the fragment's alpha (ONE, ZERO): the stencil value or a clear's alpha |
| Write masks | whole colour channels the mask (0xE8) keeps are not written; a partial channel mask is written whole and logged once. The alpha, the PSP's stencil, is written only as "The stencil and the alpha" says; the alpha mask (0xE9) is the stencil attachment's write mask (~0xE9) |
| Stencil | the GE's test (0x24, 0xDC: function, reference, compare mask) and operations (0xDD: sfail, zfail, zpass as KEEP, ZERO, REPLACE, INVERT, INCR and DECR, both clamping) on the target's `Depth32Float_Stencil8` attachment, for draws into 5551, 4444 and 8888 targets; the GE compares reference OP stencil under the mask, as Metal does, with the alpha test's function numbers. The reference is the one the target's alpha holds (the top bit of a 5551 target, the top nibble of a 4444 one), set on the encoder (`setStencilReferenceValue`) |
| Depth | the GE function as the depth compare; written only where the GE tests it (`test_enabled && write_enabled`), through mode included |
| Clears | CLEARMODE draws have no blend, texture or tests; bits 8..10 choose the colour, the alpha and the depth, and the depth compare is ALWAYS. A clear of the alpha on a 5551, 4444 or 8888 target writes the stencil with it: ALWAYS, REPLACE with the clear colour's alpha (patch 0006) |
| Culling | transformed triangles with culling on, back faces culled, the GE's clockwise front as Metal's `MTLWindingClockwise`: Metal counts the winding in window coordinates (y down), as the GE and Vulkan's flipping viewport do. Confirmed on the race (task 024): race frame 6016 culls 593 of its 906 draws, 353 of them among the first 393 (344 with the counter-clockwise front, 266 of those into the display target; 9 with the clockwise one, the shadow volumes, which write only the stencil), and it matches Vulkan's up to its draw 394, while a build with the winding reversed differs from draw 41 on, 49% of the picture by draw 393 ("The 3D check"). The clockwise case, the shadow volumes, reaches the picture through the stencil since task 025 |
| Scissor | the GE scissor, both ends included, clamped to 480x272; an empty one draws nothing |

### The pipeline key

`PipelineKey` is everything a draw's pipeline is made from, in two parts with a cache each:

| Part | Fields | Makes |
|---|---|---|
| `RenderKey` | blend on/off, Metal source and destination factors, blend operation, colour write mask (alpha included when the draw stores a stencil value), the alpha's destination factor (ZERO, or ONE for the copy of the stencil into the alpha), dual source, textured, alpha test | `MTLRenderPipelineState` (vertex function `ge_vertex`, fragment function `ge_fragment`, or `ge_fragment_dual` with dual source, specialised by the function constants `kTextured` and `kAlphaTest`; the eight specialisations are made at start). With dual source the colour factors SA and 1-SA become `Source1Alpha` and `OneMinusSource1Alpha` |
| `DepthStencilKey` | depth compare, depth write; the stencil test as the GE gives it: enabled (on a 5551, 4444 or 8888 target), function, fail, depth-fail and pass operations, compare mask, write mask (~0xE9) | `MTLDepthStencilState`, with the same `MTLStencilDescriptor` for both faces. The reference is the encoder's, not the state's |

Per draw, the vertex uniforms (matrix, folded viewport, uv transform, the row of view x world that gives view-space
z, and the mode: through, sprite corners in clip space, fog, lighting), the fragment uniforms (FIX colour, texture
function, TCC, opaque texel alpha, alpha test function, reference and mask, fog colour, the stencil value the
alpha stores), the blend colour, the stencil reference, the viewport's depth range, the scissor and the cull mode
are set on the encoder when they changed, and the lighting
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
  race's billboards and bloom do ("The bloom chain").
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

- One command buffer a frame, committed at the flip (`present_image`). Without the window no frame waits for the
  GPU unless two are already in flight.
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
| Window | an SDL window (`SDL_WINDOW_METAL \| SDL_WINDOW_RESIZABLE`, 480x272 times the window-size setting, full screen by the setting), titled as the Vulkan shell's (`PURE_WINDOW_TITLE`, else the program's name and build label); `SDL_Metal_CreateView` and its `CAMetalLayer`: BGRA8, tagged sRGB (as MoltenVK tags its swapchain, so the colours look the same), `framebufferOnly` off for the captures, the system default device (`MTLCreateSystemDefaultDevice`, the backend's) and a command queue of the shell's own. Prints `[shell] metal: Apple M4 Pro, window 960x544, vsync` |
| Events and input | `pump_events` handles the window's events as the Vulkan renderer's pump does: close, gamepads arriving and leaving, a display change, the mouse while it is captured for the game (only the script's mouse under scripted input), then the interface's event hook. The pad is a `host::SdlPad` the shell holds, the code the Vulkan shell uses: the keyboard through the player's bindings, the first gamepad or the input script's virtual one, the script's keys (`set_scripted_key`), the neutral pad while an interface screen is up (`set_game_input`). The pointer is captured by the Vulkan renderer's rule. `sample_pad` pumps SDL and samples without handling events |
| Present | the backend's `Metal` image (its target's `id<MTLTexture>`) is drawn into the layer's next drawable by one triangle over the letterboxed rectangle, placed as the Vulkan renderer's `record_game_blit` places it (Original), or over the whole drawable (Stretch); a `Cpu` image is uploaded to a texture first; no image clears to black. The interface is drawn in the same pass, then `presentDrawable` and commit. A fast-forwarding load presents a flip only when none was shown for 33 ms, as the Vulkan shell does. Vsync is the layer's `displaySyncEnabled`, off for Immediate; there is no Mailbox (`supports_present_mode`) |
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

The backend commits each frame's command buffer in `present_image`, before the HLE calls `present`, and its targets
are tracked resources of the same device, so Metal orders the shell's sampling after the frame's draws and the next
frame's draws after the sampling.

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

## What is not done yet

| Task | What |
|---|---|
| 027 (landed) | what the Metal shell leaves out ("The Metal shell"): frame interpolation, the Fill aspect, the touch controls, the performance overlay, and the menu's resolution, texture filter and texture-pack rows |
| enhancements | drawing above 480x272 (an internal scale above 1, which D-002 leaves for after the native picture) and texture packs, both the Vulkan renderer's today |

The race exercises neither `read_back_framebuffer` nor a block transfer from a target (its transfers come from
main memory), and the frontend calls only `write_back_frame`: the 16-bit store formats and the transfer's row range
are written to the rules above and the Vulkan backend's, and checked by no recording yet.

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
validation on) without a validation error or a `[metal] ... not implemented` line ("Cost" above).
