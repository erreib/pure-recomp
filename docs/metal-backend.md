# The Metal GE backend (task 023, 2026-10-06)

`PURE_GE_BACKEND=metal` draws the game with Metal, natively, behind the GE backend seam of D-003
(`docs/ge-backend.md`). It is `src/gpu/metal_backend.mm`, in our sources, and registers itself as `metal`. Task
023 built its skeleton (device, targets, textures, the draws of the 2D frontend, clears, blending, the alpha test,
captures) and proved it on the frame regression suite's three frontend scenes, which it draws within a few pixels
of PPSSPP: the language page, the title screen and the profile screen. 3D lighting, the stencil kept as alpha, the
bloom chain and the read-backs into guest memory are tasks 024 and 025. The Metal shell (task 027, "The Metal shell"
below) shows its pictures in a window of its own, with no Vulkan involved.

## Quick start

```sh
tools/build.sh profile
tools/frame_regress.sh --backend metal --only lang,title,profile          # the three frontend scenes (about 75 s)
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
| Primitives | Expanded on the CPU into lists, as the Vulkan backend does: points (1 pixel), lines, line strips, triangles; strips and fans unrolled with every triangle keeping the strip's winding; sprites as two triangles by the GE's rule (the second vertex's depth and colour for the whole rectangle, each corner the u of the vertex it shares x with and the v of the one it shares y with). Indices are resolved while expanding. 32 bytes a vertex (`GpuVertex`: position, uv, colour) into 4 MB shared buffers that are reused once the GPU has finished with them |
| Colour | the vertex colour, or the material colour (`DrawCall::material_color`) when the vertex type has none and the draw is unlit, Vulkan's rule. Lit draws are drawn with their vertex colour (white when they have none): no lighting or fog yet |
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
| Culling | transformed triangles with culling on, back faces culled, the GE's clockwise front as Metal's `MTLWindingClockwise`: Metal counts the winding in window coordinates (y down), as the GE and Vulkan's flipping viewport do. Checked with a test triangle; the frontend culls nothing, so task 024 confirms it on the race |
| Scissor | the GE scissor, both ends included, clamped to 480x272; an empty one draws nothing |

### The pipeline key

`PipelineKey` is everything a draw's pipeline is made from, in two parts with a cache each:

| Part | Fields | Makes |
|---|---|---|
| `RenderKey` | blend on/off, Metal source and destination factors, blend operation, colour write mask, textured, alpha test | `MTLRenderPipelineState` (vertex function `ge_vertex`, fragment function `ge_fragment` specialised by the function constants `kTextured` and `kAlphaTest`; the four specialisations are made at start) |
| `DepthStencilKey` | depth compare, depth write; the stencil test as the GE gives it: enabled (on a 5551, 4444 or 8888 target), function, fail, depth-fail and pass operations, reference, compare mask, write mask (~0xE9) | `MTLDepthStencilState`. The stencil fields are carried for task 025, which sets the state's stencil descriptors from them; today the stencil attachment is left untouched |

Per draw, the vertex uniforms (matrix, folded viewport, uv transform, through flag), the fragment uniforms (FIX
colour, texture function, TCC, opaque texel alpha, alpha test function, reference and mask), the blend colour, the
viewport's depth range, the scissor and the cull mode are set on the encoder when they changed.

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
| 024 | lighting and fog (lit draws use their vertex colour); transformed sprites are expanded in object space, as the Vulkan backend does, which is right only for the frontend's orthographic projection; culling to be confirmed on the race; the colour test, logic ops, the texture environment colour and colour doubling are not in `DrawCall` |
| 025 | the stencil attachment's test and operations, the alpha copy rule (patches 0004 and 0006: today non-clear draws leave the alpha alone), `block_transfer`, `read_back_framebuffer`, `write_back_frame` and `write_back_depth`. These four are counted and say `[metal] <call>: not implemented (task 025); counted, nothing written` once; `write_back_depth` returns false. The frontend calls only `write_back_frame` (once a flip) |

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
