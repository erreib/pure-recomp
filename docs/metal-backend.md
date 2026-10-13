# The Metal GE backend

`PURE_GE_BACKEND=metal` draws the game with Metal, natively at the PSP's 480x272 or at an internal scale of it (task
066, "Internal scale"), behind the GE backend seam of D-003 (`docs/ge-backend.md`); with the Metal shell
(`PURE_SHELL=metal`, "The Metal shell") it is the default on macOS (D-008), and the game runs with no Vulkan or MoltenVK in the process. It is `src/gpu/metal_backend.mm` and the files
beside it ("Files"), registered as `metal`. It draws everything the framework's GE state carries (`DrawCall`, with
patch 0002-ge-state-commands): through-mode and transformed draws with the GE's lighting and fog, transformed sprites
expanded on the screen, culling, the alpha and colour tests, blending with exact FIX colours, the stencil test and
operations with the target's alpha kept as the PSP's stencil (the shadow volumes, the bloom's mask), the bloom chain
over aliased VRAM, the texture mapping modes (the reflections), mip levels at the level the GE's rule picks (or,
with the Texture detail row, the level for the pixels drawn, anisotropically: task 075), 16-bit
targets with the GE's dither, CLIPENABLE's depth clamp, block transfers and read-backs into guest memory, and the
frame and depth write-backs (the lens flare). The frame regression suite's 18 scenes pass on it against PPSSPP
(docs/verification.md, "Frame regression suite"); where it draws differently from the Vulkan backend, and why: "Where
it differs from the Vulkan backend on purpose".

The backend was built by tasks 023 (the 2D frontend), 024 (3D: lighting, fog, sprites, culling), 025 (the effects),
027 (the Metal shell), 031 (one command queue), 033 (frame times, the pre-warm), 036 (texture mapping), 037 (mipmaps),
040 (the colour test, 16-bit writes, the depth clamp), 042 (the pre-warm list over the campaign), 049 (the split
into files by concern), 066 (the internal scale), 073 (the sprite upscale) and 075 (texture detail). What each measured: [docs/history/metal-backend.md](history/metal-backend.md).

## Quick start

```sh
tools/build.sh profile
tools/frame_regress.sh                                    # the 18 scenes against PPSSPP, headless on Metal (about 25 s)
tools/frame_regress.sh --only lang,title,profile          # the three frontend scenes (seconds)
tools/frame_regress.sh --shell metal --backend metal      # the same in the Metal shell's window (paced: minutes)
tools/hud_check.sh                                        # the race HUD in the Metal window, 61 shots (about 4 min)
tools/gerec/metal_check.sh                                # Metal against Vulkan through ge_replay (below)
build/arm64/bin/PureNative --replay out/gerec/race_1x.gerec --a vulkan --b metal --frames 6016 --cut 393 \
  --tol 24 --out out/cut                                  # both pictures after draw 393 of frame 6016
tools/run_boot.py --frames 300 out/x.log                  # headless: no window, Metal still draws
tools/run_boot.py --frames 700 --env PURE_METAL_LOG=1 out/x.log   # a line per draw
tools/run_boot.py --window --frames 700 out/x.log         # the Metal shell and backend (the defaults): no Vulkan
tools/refactor_check.sh --before                          # captures before a change that only moves code ("Files")
tools/refactor_check.sh                                   # after it: 0 differing pixels on every scene, or FAIL
```

| Switch | Effect |
|---|---|
| `PURE_GE_BACKEND=metal` | draw with this backend; with the window open (no `PURE_NO_RENDER`) or without one |
| `PURE_METAL_LOG=1` | a line per draw and per new target (below). Every 600 frames and at exit the backend prints its counts either way |
| `PURE_METAL_SHELL=0` | under the Vulkan shell, do not hand the pictures to its window: the window stays black and the input script's `shot` steps capture nothing (see "The window"). Under any other shell there is no hand-over to turn off |
| `PURE_SHELL=metal` | show the pictures in the Metal shell's window instead of the Vulkan shell's (see "The Metal shell") |
| `PURE_NO_FB_TEXTURES=1` | every texture decoded from guest memory, none read from a target (the framework's switch, as for Vulkan) |
| `PURE_NO_DEPTH_READBACK=1` | the framework's switch (patch 0003-vulkan-renderer-fixes, task 019): the HLE does not ask for the depth write-back at a SIGNAL, so the lens flare is never occluded. ge_replay replays a recording's WriteBackDepth records regardless |
| `PURE_TRACE_STENCIL_COPY=1`, `PURE_TRACE_DEPTH_READBACK=1` | the framework's traces, as the Vulkan backend prints them: `[metal] stencil copied into the alpha of 0x... in frame N (reason)` for each copy of the stencil into the alpha, and `[metal] frame N signal 0x200: depth of 0x... written back to 0x4110000 stride 512, z MIN-MAX, T ms (GPU wait W ms)` for each depth write-back |
| `PURE_METAL_TRACE=FILE` | (task 033) a CSV row per flip with where the time between two flips went: submit, pipeline creation, texture decodes, each kind of GPU wait, the Metal shell's present and when the picture reached the screen ("Frame times"); `tools/frame_times.py FILE` summarises it |
| `PURE_METAL_PIPELINES=FILE` or `0` | (task 033) the pipeline list made at start instead of `config/metal_pipelines.txt` (in the app, its copy in `Contents/Resources`, task 042); `0` turns the pre-warm off ("Frame times", "The pre-warm list") |
| `PURE_METAL_PIPELINES_OUT=FILE` | (task 033) at exit, every render pipeline and depth-stencil key the run's draws used, in the list's form |
| `PURE_METAL_PACE=0` | (task 033) the Metal shell shows each picture as soon as it can, instead of at the real time of the PSP vblank after its frame began |
| `PURE_NO_TEXMAP=1` | (task 036) every draw takes its UVs through the texture scale and offset (texture map mode 0), as before task 036: the texture matrix and environment map modes are not drawn ("Texture mapping modes") |
| `PURE_NO_MIPMAPS=1` | (task 037) every texture is uploaded and sampled at level 0 alone, as before task 037, whatever levels the GE names ("Mipmaps"); its pictures are those of the build before the task |
| `PURE_NO_COLOR_TEST=1`, `PURE_NO_DITHER=1`, `PURE_NO_DEPTH_CLAMP=1` | (task 040) each restores what the backend drew before task 040: every fragment kept; 5650, 5551 and 4444 targets blended by the pipeline at 8 bits a channel, never dithered; every transformed draw clipped at both ends of the depth range, MINZ/MAXZ unread. With all three the pictures are those of the build before the task ("The colour test, 16-bit writes and the depth clamp") |
| `PURE_METAL_SHOW_TARGET=ADDR` | (task 040) each flip presents the target drawn last at ADDR instead of the display: a target the game never shows, such as the race's 565 billboard target (`0x04154000`), in a capture or a `ge_replay --cut ... --out` picture |
| `PURE_INTERNAL_SCALE=N` | (task 066) the framework's `video.internal_scale` for the run: the backend draws its screen-wide targets at N (1 to 6; 0 Auto), read at start ("Internal scale"). Without a window the backend draws at 1 unless this is set |
| `PURE_SPRITE_UPSCALE=0\|1` | (task 073) the menu's Text and sprites row, `game.sprite_upscale`, for the run: `1` upscales the 2D draws' textures 4x at decode, `0` (the default since 2026-10-12) draws the PSP's texels; every tool run has `0` unless it names it ("Sprite upscale") |
| `PURE_SPRITE_DUMP=DIR` | (task 073) each upscaled texture written once as `DIR/<key>.src.png` (the decoded input) and `DIR/<key>.png` (the output), for `tools/sprite_proto_check.py`; the textures are the game's, so DIR belongs under `out/` ("Sprite upscale") |
| `PURE_TEXTURE_DETAIL=0\|1` | (task 075) the menu's Texture detail row, `game.texture_detail`, for the run: `1` (the default) draws the mipmapped textures at the level for the pixels drawn, 16 x log2(S) sixteenths finer than the GE's at internal scale S, and anisotropically; `0` at the GE's level for the PSP's 480x272 pixels, as before; every tool run has `0` unless it names it ("Texture detail") |
| `PURE_NO_LIGHTING`, `PURE_NO_FOG`, `PURE_NO_CULL` | the framework's switches for bisecting 3D draws, read as the Vulkan backend reads them: lit draws drawn with their vertex colour (white without one) and no fog; no fog; nothing culled. ge_replay hands the environment to both backends, so to turn one off in Metal alone replay each backend on its own with `--out` and compare the pictures |

When Metal cannot start (no device, or the shaders do not compile), `initialize` fails with the reason and the HLE
prints `[render] GE backend metal cannot run (...)`. At start the backend prints the device and the shader compile
time (`[metal] drawing with Apple M4 Pro, internal scale 1: targets 480x272, effects 480x272; shaders compiled in 0.5
ms; pictures shown in the window`; about 0.7 s the first time, before macOS has cached the compiled library, and 0.5
to 30 ms after). Before task 066 the line read `drawing with Apple M4 Pro at 480x272, shaders compiled ...`.

## Files

The backend is split by concern (task 049, 2026-10-07): one class, `MetalGeBackend : portablekit::gpu::GeBackend`,
declared in a header and defined in seven Objective-C++ files (ARC), each opening with a comment that says what it
owns. Before task 049 it was all `metal_backend.mm` (2975 lines) with the shaders as a string in `metal_shaders.h`;
the split moved code without changing it (`tools/refactor_check.sh` below). Task 062 (2026-10-09) then simplified
it the same way, checked by the same script: one blit into a buffer, one byte span per target, `draw()` in parts,
and the switches, the trace and the pre-warm each in a struct of their own.

| File | What |
|---|---|
| `src/gpu/metal_backend.mm` | the backend proper: `initialize` (device, shaders, samplers, the switches into `switches_`) and `shutdown`, `submit`, the flip (`present_image`) and `capture_frame`, the frame's command buffers, render passes and vertex space (`commit`, `end_encoder`, `begin_pass`, `allocate`, and `copy_to_buffer`, the one blit of a target's colour or depth into a shared buffer, which `read_back`, the frame write-back, `store_target` and `store_depth` use), `not_emulated`, and the `BackendRegistration("metal", ...)`. Its opening comment is the backend's overview |
| `src/gpu/metal_backend.hpp` | the class: its members grouped under a heading per concern that names the file defining them, its data members (50, among them one struct each for the switches, the trace and the pre-warm: `switches_`, `trace_`, `prewarm_`), and the eight helpers more than one file uses (`unpack_color`, `not_emulated`, `to_compare`, `stored_reference`, `stencil_alpha`, `alpha_follows_stencil`, `format_name`, `texture_bits`), each with the file that defines it |
| `src/gpu/metal_types.hpp` | the shared types: the sizes (`kWidth`, the guest's 480x272, `kMaxScale`, `kChunkBytes`, `kMaxTextures`, `kFramesInFlight`), `GpuVertex` and the uniform blocks (`VertexUniforms`, `Light`, `LightingUniforms`, `FragmentUniforms`) with their `static_assert`s against `shaders/ge.metal`, `TargetKey` and `Target` (with `bytes()` and `contains(address)`, the guest memory a target covers, which every scan of the targets uses, and since task 066 its internal `scale`, `width()` and `height()`), `RenderKey`, `DepthStencilKey` and `PipelineKey`, `TextureIdentity` and `CachedTexture`, `ChunkPool`, `GuestWrites` and `Stats`, `FrameTimes`, `TraceClock` and `TraceRow`, `Prewarm`; and the three structs the class holds once each (task 062): `Switches` (`switches_`, filled by `initialize`), `TraceState` (`trace_`, metal_trace.mm's) and `PrewarmState` (`prewarm_`, metal_pipelines.mm's) |
| `src/gpu/metal_targets.mm` | "Targets" and "Guest memory": the target cache (`target_for`, `latest_target_at`, the guest-word snapshot), a texture bind found in a target (`find_framebuffer_texture`, the rule of task 009) and the copy a draw samples of the target it draws into; `block_transfer`, `read_back_framebuffer`, `write_back_frame`, `write_back_depth` and the stores into guest memory; `upload_frame` |
| `src/gpu/metal_textures.mm` | "Textures" and "Mipmaps", from guest memory: the levels a draw samples (`mip_levels`), the content key and its hashes, `decoded_texture` and the cache, the GE's level rule; the sprite upscale's dump and its texture pack (`dump_sprite`, "Sprite upscale"); the game options the backend reads itself, at start and once a frame (`read_game_options`: Text and sprites, Texture detail) |
| `src/gpu/metal_pipelines.mm` | "The pipeline key" and "The pre-warm list": the fragment-function variants, `render_pipeline` and `depth_state` (made on first use or taken from the pre-warm), the GE-to-Metal compare and stencil tables, the list's text form and parser, `start_prewarm`, the pipelines' exit line and `PURE_METAL_PIPELINES_OUT`; the pre-warm's state and the keys the draws used are `prewarm_` (`PrewarmState`) |
| `src/gpu/metal_effects.mm` | "The stencil and the alpha": what a draw leaves in its target's alpha, `resolve_stencil_alpha`, the blend checks for dual-source blending and for that copy; the blend of a 16-bit target in the shader (task 040). The bloom chain has no code of its own: targets drawn into and sampled ("The bloom chain") |
| `src/gpu/metal_draw.mm` | "How a draw is drawn": `draw`, from the `DrawCall` to the encoder, with the primitives expanded on the CPU (`expand`, transformed sprites), the blend factors (`translate_blend`), the lighting block, the texture mapping mode, and its parts in the order it calls them: the pipeline key with the fragment uniforms of the tests and the blend (`set_pipeline_key`), the GE viewport folded into clip space (`fold_viewport`), then the encoder's state set when it changed (`bind_state`) and what the shaders read (`bind_inputs`); and `PURE_METAL_LOG`'s line |
| `src/gpu/metal_trace.mm` | "Frame times": `PURE_METAL_TRACE`'s rows, the line every 600 frames, the exit lines of the stencil, guest memory, the colour test, 16-bit targets and the depth clamp; their state is `trace_` (`TraceState`), which also holds the framework's stencil-copy and depth traces' switches |
| `src/gpu/shaders/ge.metal` | the shaders, plain MSL: `ge_vertex`, `ge_fragment`, `ge_fragment_dual`, `ge_fragment_16`; ported from the framework's `ge.vert` and `ge.frag` (MIT); the texture mapping modes (`map_texture`, task 036), the mip level (task 037), and the colour test, the 16-bit writes and the depth clamp (task 040) are ours, from PPSSPP's hardware notes; the texture detail path in `sample_texture` (task 075, "Texture detail") too |
| `src/gpu/shaders/embed.cmake` | the build step that turns `ge.metal` into `build/<preset>/generated_metal/ge_metal.hpp`: the file's text byte for byte as a raw string, `pure::metal::kShaderSource`, which `initialize` compiles. Rerun by the build whenever `ge.metal` changes |
| `src/gpu/sprite_upscale.hpp`, `.cpp` | (task 073) `upscale_sprite`, the 4x resample of a W x H RGBA8 texture ("Sprite upscale"), and `write_png` for `PURE_SPRITE_DUMP` (the framework's vendored stb_image_write); plain C++, no Metal |
| `src/gpu/metal_shell.hpp`, `.cpp` | `show_in_shell`: a presented picture into the Vulkan window shell (plain C++, so the shell's headers never meet Objective-C) |
| `tools/gerec/metal_check.sh` | the 3D and race checks (tasks 024 and 025): Metal against Vulkan through ge_replay on the TEAM screen and the race ("The 3D check", "The race check") |
| `tools/scale_check.sh` | (task 066) the backend at internal scale S against 1: the suite's 18 scenes headless at both, compared after reducing the S captures to 480x272 by their blocks' centre pixels, plus the race scenes' bloom region ("Internal scale") |
| `tools/refactor_check.sh` | (task 049) the proof that a change moved code and changed no picture: the frame regression suite's 18 scenes captured before the change (`--before`, on the starting commit) and after, compared at `--tol 0`, plus the backend's exit counts per route; PASS only at 0 differing pixels everywhere |
| `src/host/metal_shell.mm` | the Metal shell (task 027): `MetalShell : portablekit::host::Shell` and its `ShellRegistration("metal", ...)`. Objective-C++ with ARC |
| `src/gpu/metal_device.hpp`, `.mm` | the program's one Metal device and command queue, `pure::metal::device()` and `pure::metal::queue()`, which the backend and the shell both use (task 031, "One command queue" below), the frame trace's hook through which the shell reports its presents (task 033, "Frame times"), and the Metal shell's drawable size, which the backend's Auto internal scale reads (task 066, "Internal scale"). Objective-C++ with ARC |
| `config/metal_pipelines.txt` | the render pipelines and depth-stencil states made at start (task 033, "The pre-warm list"); since task 042 it covers the campaign and the app carries a copy in `Contents/Resources` |
| `tools/frame_times.py` | the frame trace's summary (task 033, "Frame times") |
| `third_party/imgui_metal/` | Dear ImGui's Metal renderer backend, `imgui_impl_metal.h` and `imgui_impl_metal.mm` from the 1.92.9b release (the vendored ImGui's), verbatim, MIT |
| `CMakeLists.txt` | the backend's seven files in `metal_backend_sources` (and `src/gpu/sprite_upscale.cpp` beside them in `platform_sources`), the sources in `portablekit_add_game(... SOURCES ...)`, every `.mm` compiled with `LANGUAGE CXX` and `-x objective-c++ -fobjc-arc`, the shader embedding step and its directory on the include path, `third_party/imgui_metal` on the include path, and `-framework Metal`, `Foundation`, `QuartzCore` and (for the shell's sRGB colour space) `CoreGraphics` linked |

Built without Xcode, in the shape of the Bouncer's backend (`~/dev/bouncer-recomp/docs/metal-backend.md`): the
`.mm` files go through the same `/usr/bin/clang++` and ccache as every other source of `tools/build.sh profile`, and
the shaders are compiled when the backend starts (`newLibraryWithSource`, `MTLMathModeSafe`) from the text the build
embedded, so the machine needs only the Metal compiler that comes with macOS and no build reads a shader file at run
time. A compile error is the message `initialize` returns.

New code goes in the file of its concern, with its declaration in `metal_backend.hpp` under that file's heading; a
type or helper more than one file uses goes in `metal_types.hpp` or the header's helper list. The code lives in
`pure::gpu::metal_backend` (a named namespace, since the class is shared between files); file-local helpers stay in
each file's anonymous namespace.

## How a draw is drawn

| What | How |
|---|---|
| Primitives | Expanded on the CPU into lists, as the Vulkan backend does: points (1 pixel), lines, line strips, triangles; strips and fans unrolled with every triangle keeping the strip's winding; sprites as two triangles by the GE's rule (the second vertex's depth and colour for the whole rectangle, each corner the u of the vertex it shares x with and the v of the one it shares y with; transformed sprites below). Indices are resolved while expanding. 48 bytes a vertex (`GpuVertex`: position, uv, colour, the vertex a sprite corner is lit as, normal) into 4 MB shared buffers that are reused once the GPU has finished with them |
| Colour | the vertex colour, or the material colour (`DrawCall::material_color`) when the vertex type has none and the draw is unlit, Vulkan's rule. A lit draw's colour is the lighting's |
| Lighting | per vertex in `ge_vertex`, ported from `ge.vert` for transformed draws with `lighting_enabled` (never through mode or clears), in world space: emissive, plus the global ambient light times the material ambient, plus for each of the four lights that is on its ambient, diffuse and specular terms, scaled by distance attenuation (point and spot) and the spot cone. Directional, point and spot lights; diffuse, diffuse and specular, and powered diffuse kinds; the specular power; the viewer looking down z for the half vector; the normal transformed by the world matrix and normalised (`reverse_normals` flips it). The material update bits make the vertex colour stand in for the ambient, diffuse and specular material colours when the vertex has a colour; alpha is the global ambient alpha times the material ambient's. The result is clamped to 0..1; with the specular kept apart (`LightingState::mode`) the specular is added after texturing. The lights, material and fog go to the vertex function as one 688-byte block (`LightingUniforms`, buffer 2), bound again only when a lit or fogged draw changes it. The race lights with ambient, emissive and up to two directional diffuse lights; point and spot lights, specular, powered diffuse and reversed normals are ported but no recording exercises them |
| Fog | `ge.vert`/`ge.frag`'s: per vertex, (view-space z + end) x scale (`FogState`), so 1 is clear and 0 fogged, for transformed draws with fog on; in the fragment shader after texturing and the separate specular, the colour mixed towards the fog colour by that factor clamped to 0..1, alpha untouched |
| Transformed sprites | by the GE's rule, on the screen after projection: both vertices are projected, and the rectangle between them is axis-aligned in window coordinates, at the second vertex's depth, lit, coloured and fogged as the second vertex, texture coordinates interpolated without perspective. The corners go to the vertex function already in the PSP's clip space, all with the second vertex's w (`VertexUniforms::mode.y`), each naming the second vertex (appended to the buffer after the corners) as the one it is lit and fogged as. A sprite with a vertex behind the eye (w <= 0) is dropped. The Vulkan backend expands them in object space; the two agree whenever the transform keeps the rectangle axis-aligned on the screen, as it does for every transformed sprite in the recordings (26 in the TEAM frame, 28 in race frame 6016: 0.0000 px between the corners either way) |
| Through mode | positions in screen pixels go straight to clip space for the guest's 480x272 screen, which the viewport maps onto the target's pixels (x S at an internal scale S, "Internal scale"); z is `z / 65535` |
| Transformed | `projection x view x world`; the GE viewport (`screen = ndc x scale + offset - region offset`) folded into clip x and y, so the Metal viewport stays the whole target; clip z remapped from the PSP's [-w, w] to Metal's [0, w], and the GE's z scale and offset become the viewport's `znear` and `zfar` (reversed when the game reverses the range), as the Vulkan backend folds them into `minDepth`/`maxDepth` |
| Texture coordinates | texels divided by the texture's size in through mode; transformed, by the GE's texture map mode (task 036): the UVs through the GE's scale and offset (mode 0), the texture matrix applied to the position, UV or normal with s and t divided by q per pixel (mode 1), or the environment map from the normal and two lights (mode 2), "Texture mapping modes" |
| Texture function | modulate, decal, blend, replace and add, with TCC (alpha from the texture or not). The blend function's environment colour is not in the draw state; the texel stands in for it, as in `ge.frag` |
| Filtering and wrap | the GE's own filter bits (nearest or linear for magnification and minification; with mip levels, nearest or linear between them: task 037, "Mipmaps") and wrap bits (clamp or repeat) choose one of 48 samplers; `sharp_textures` forces nearest within a level |
| Alpha test | in the fragment shader, by the GE's numbering (0 NEVER, 1 ALWAYS, then EQUAL ... GEQUAL: task 010), on the 8-bit alpha and reference under the test's mask, with `discard_fragment`. Draws without a test, or with ALWAYS, use a fragment function compiled without it |
| Colour test | (task 040) in the fragment shader after fog, as the alpha test: the 8-bit colour under COLORTESTMASK against COLORREF under it, NEVER, ALWAYS, EQUAL or NOTEQUAL, with `discard_fragment` (no colour, depth or stencil written); compiled out without a test or with ALWAYS |
| 16-bit targets | (task 040) a draw into a 5650, 5551 or 4444 target blends in the shader on the target's colour (`ge_fragment_16`), adds the dither matrix's offset when DITHERENABLE is on, and keeps the format's bits, as the PSP writes such a target; the target texture stays RGBA8 and holds what those bits expand to |
| Blend | Metal's blend units for the GE factors and the equations ADD, SUBTRACT, REVERSE SUBTRACT, MIN and MAX (MIN and MAX take no factors). A FIX source factor is applied in the shader (the colour arrives multiplied, the blend takes it ONE), so any pair of FIX colours is exact, unless the destination factor reads the source colour, when it is the blend colour; a FIX destination is ONE, ZERO or the blend colour. The doubled factors (2xSA and so on) are drawn single and ABSDIFF as ADD, each logged once (`[metal] ... is not emulated`). A draw that stores a stencil value under a blend that reads the source alpha blends with the fragment's own alpha from a second output (dual-source blending, below). The alpha channel's own blend stores the fragment's alpha (ONE, ZERO): the stencil value or a clear's alpha |
| Write masks | whole colour channels the mask (0xE8) keeps are not written; a partial channel mask is written whole and logged once. The alpha, the PSP's stencil, is written only as "The stencil and the alpha" says; the alpha mask (0xE9) is the stencil attachment's write mask (~0xE9) |
| Stencil | the GE's test (0x24, 0xDC: function, reference, compare mask) and operations (0xDD: sfail, zfail, zpass as KEEP, ZERO, REPLACE, INVERT, INCR and DECR, both clamping) on the target's `Depth32Float_Stencil8` attachment, for draws into 5551, 4444 and 8888 targets; the GE compares reference OP stencil under the mask, as Metal does, with the alpha test's function numbers. The reference is the one the target's alpha holds (the top bit of a 5551 target, the top nibble of a 4444 one), set on the encoder (`setStencilReferenceValue`) |
| Depth | the GE function as the depth compare; written only where the GE tests it (`test_enabled && write_enabled`), through mode included. With CLIPENABLE on (every transformed draw of the game), as the GE: clipped at the near plane only, each vertex's screen z clamped to 0..65535, and MINZ/MAXZ tested per pixel (task 040) |
| Clears | CLEARMODE draws have no blend, texture or tests; bits 8..10 choose the colour, the alpha and the depth, and the depth compare is ALWAYS. A clear of the alpha on a 5551, 4444 or 8888 target writes the stencil with it: ALWAYS, REPLACE with the clear colour's alpha (task 011) |
| Culling | transformed triangles with culling on, back faces culled, the GE's clockwise front as Metal's `MTLWindingClockwise`: Metal counts the winding in window coordinates (y down), as the GE and Vulkan's flipping viewport do. Confirmed on the race (task 024): race frame 6016 culls 593 of its 906 draws, 353 of them among the first 393 (344 with the counter-clockwise front, 266 of those into the display target; 9 with the clockwise one, the shadow volumes, which write only the stencil), and it matches Vulkan's up to its draw 394, while a build with the winding reversed differs from draw 41 on, 49% of the picture by draw 393 ("The 3D check"). The clockwise case, the shadow volumes, reaches the picture through the stencil since task 025 |
| Scissor | the GE scissor, both ends included, clamped to 480x272, times the target's internal scale; an empty one draws nothing |

### The pipeline key

`PipelineKey` is everything a draw's pipeline is made from, in two parts with a cache each:

| Part | Fields | Makes |
|---|---|---|
| `RenderKey` | blend on/off, Metal source and destination factors, blend operation, colour write mask (alpha included when the draw stores a stencil value), the alpha's destination factor (ZERO, or ONE for the copy of the stencil into the alpha), dual source, textured, alpha test, and since task 040 colour test and `sixteen` (a 5650, 5551 or 4444 target) | `MTLRenderPipelineState` (vertex function `ge_vertex`, fragment function `ge_fragment`, `ge_fragment_dual` with dual source, or `ge_fragment_16` for a 16-bit target, whose pipeline does not blend; specialised by the function constants `kTextured`, `kAlphaTest` and `kColorTest`: the eight specialisations without the colour test and the 16-bit function are made at start, the others on first use). With dual source the colour factors SA and 1-SA become `Source1Alpha` and `OneMinusSource1Alpha`. A line of the pre-warm list without the two later fields reads them as 0 |
| `DepthStencilKey` | depth compare, depth write; the stencil test as the GE gives it: enabled (on a 5551, 4444 or 8888 target), function, fail, depth-fail and pass operations, compare mask, write mask (~0xE9) | `MTLDepthStencilState`, with the same `MTLStencilDescriptor` for both faces. The reference is the encoder's, not the state's |

The keys of `config/metal_pipelines.txt` are made at start, the render pipelines asynchronously, and any other key on
first use (task 033, "Frame times").

Per draw, the vertex uniforms (matrix, folded viewport, uv transform, the row of view x world that gives view-space z,
the mode: through, sprite corners in clip space, fog, lighting, and since task 036 the texture map mode with the texture
matrix, the viewer's direction and the texture's place in the image sampled, and since task 040 the GE's z scale and
offset and MINZ/MAXZ for the depth clamp; 256 bytes), the fragment uniforms (FIX colour, texture function, TCC, opaque
texel alpha, whether the coordinates are divided by q, alpha test function, reference and mask, fog colour, the stencil
value the alpha stores, since task 037 the mip level rule, and since task 040 the colour test and, for a 16-bit target,
the GE's blend factors, equation and FIX colours, the dither matrix and the target's format: 208 bytes), the blend
colour, the stencil reference, the viewport's depth range, the depth clip mode, the scissor and the cull mode are set on
the encoder when they changed, and the lighting block (world matrix, global ambient, material colours, update mask and
flags, the four lights, fog end and scale) when a lit, fogged or environment-mapped draw changed it, or the pass is new.
Lighting and fog are uniform branches in the one vertex function, not pipeline variants.

## Targets

As section 2 of `docs/ge-backend.md`: a target is keyed by (colour address, stride, format), the address taken
modulo the cached/uncached mirrors. Each is an `RGBA8Unorm` colour texture (5650, 5551 and 4444 targets too: since
task 040 their draws write only the values the format's bits expand to) and a `Depth32Float_Stencil8` texture, both
private to the GPU, at 480x272, or at 480S x 272S for a key at least 480 pixels wide when the backend draws at an
internal scale S above 1 (task 066, "Internal scale"; until then internal scale 1 alone, as D-002 asked first).

- A pass draws into one target. A draw into another target ends the pass; the next one loads the target, or clears
  it to zero the first time.
- At a target's first draw of a frame, one guest word every 256 bytes of the memory under it is kept, as the Vulkan
  backend does (the framebuffer-texture lookup compares them: task 009).
- The display target of `present_image(address)` is the target at that address drawn last (of any stride or
  format), or, when there is none, the target drawn last: Vulkan's `display_image` rule.

## Textures

- **From a target.** A bind of a direct-colour, unswizzled texture whose address lies in a target with the same row
  length and pixel size, while guest memory under the texture still holds the target's guest words, samples that
  target: the target that starts at the address first, else the one drawn last (task 009). The texture's first
  texel is pixel (x, y) of the target, the sampler clamps at the target's edges, and a 5650 texture reads alpha 1. A
  draw that samples the target it draws into reads a copy made by a blit when the target has changed (which ends
  the pass); any other target is sampled directly, Metal ordering the passes. The frontend reads no target; the
  race's billboards and bloom do ("The bloom chain"). The GE's wrap mode applies to such a texture as to any other
  (below).
- **From guest memory.** Anything else is decoded with the framework's `decode_texture` (every PSP format to
  RGBA8888; no decoder of our own) and cached by its contents: the key hashes the address, size, format, buffer
  width and swizzle, every byte of the texels the decoder reads, and for the palette formats the CLUT address,
  format, shift, mask and offset and every palette entry the format's indices can reach. A changed texture or
  palette is a new key and is uploaded again; an unchanged one is found. Within a display list a bind's key is
  hashed once. Up to 1024 textures are kept, the least recently used dropped first (a command buffer that still
  uses one keeps it alive). A texture that cannot be decoded is drawn white and logged once. A texture with mip
  levels (task 037) is one mipmapped texture, its key covering every level's address, size, row length and texels
  ("Mipmaps"). Since task 073 a 2D draw's palette or 16-bit texture is upscaled 4x at decode and cached under a key
  of its own ("Sprite upscale").

The wrap of a target sampled as a texture (task 063). A texture of its own is wrapped by its sampler (REPEAT or clamp
to edge, per axis, from the GE's wrap register). A target's texture covers part of a 480x272 image, so its sampler
clamps at the image's edges and the wrap is done in `ge.metal`: the vertex function hands on the texture's own
coordinate (the UV times the scale plus the offset, or the mapped s and t of modes 1 and 2), and the fragment function
(`place_in_target`) takes it modulo 1 on a REPEAT axis or holds it between the centres of the texture's edge texels on
a CLAMP axis, then places it in the image (`FragmentUniforms::uv_remap`: the texture's size and its first texel over
480x272; `wrap` says it is a target and which axes clamp). The billboards need it: each screen samples its 128x128
advert with v scale -1 and REPEAT, so the GE reads -v modulo 1, that is 1 - v: the strip's v runs against the target's
rows, and the advert comes out upright, as in PPSSPP. Clamped at the image's edge, -v gave row 0 for every pixel and
the screens showed the advert's first row stretched into vertical bars (docs/fidelity.md, difference 15). The bloom
chain's draws clamp with coordinates inside the texture, which the change leaves alone. The Vulkan renderer does the
same since task 063 (patch 0015-vulkan-fb-texture-wrap).

In the frontend route 57 textures are decoded by frame 600 and 347 by frame 2130, over 19853 draws: unchanged
textures are found again rather than decoded. (The language page draws the paused intro movie's picture as a
512x512 8888 texture from main memory in 150 sprites; it is decoded again only when the picture changes.)

## The stencil and the alpha

The PSP keeps the stencil in the alpha channel of a 5551, 4444 or 8888 target, and never stores a fragment's own alpha
there. The backend follows the Vulkan renderer's rules of tasks 009 and 011 (`docs/ge-effects.md`, "The stencil
attachment and the copy rule"; `docs/ge-backend.md` section 2): the `Depth32Float_Stencil8` attachment is exact, and the
colour target's alpha, which is what sampling, blending, the display and the write-backs read, is kept as its copy.

| Case | What the draw does to the alpha |
|---|---|
| no stencil test, a 5650 target, or alpha bits masked (0xE9 not 0) | nothing: the alpha is not in the write mask |
| zpass REPLACE | the stored reference (`stencil_alpha`): the fragment function writes it as alpha (`FragmentUniforms::stencil`), so only fragments that pass every test write it, as the attachment's zpass does |
| zpass ZERO | 0, the same way |
| zpass KEEP, INVERT, INCR, DECR | nothing from the fragment; INVERT, INCR and DECR are done by the attachment |
| REPLACE or ZERO under a blend that reads the source alpha (SA or 1-SA) | dual-source blending: `ge_fragment_dual` returns the colour with the stencil value as alpha at `[[color(0), index(0)]]` and the fragment's own alpha at `[[color(0), index(1)]]`, and the colour blend reads `Source1Alpha`. Metal has it on every Apple GPU, so the Vulkan renderer's constant-alpha fallback (exact only for opaque fragments) is not needed |
| clear mode with the alpha flag | the clear colour's alpha, and the stencil REPLACEd with it |

A draw leaves the alpha behind the stencil when the colour path cannot express its effect (task 011's
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
route's 339 race frames (5707-6045), as task 011 measured for Vulkan (338 for frames 5707-6044). None in the
frontend. With `PURE_TRACE_STENCIL_COPY=1` the replay of `race_1x.gerec` shows one copy a frame, at the end of a
pass, never before a destination-alpha read, alternating between 0x04000000 and 0x04088000.

## The bloom chain

The six draws of `docs/ge-effects.md` ("The bloom chain"), as this backend resolves them with section 2's target
model and the framebuffer-texture lookup of task 009, which task 023 already had:

| Draw (gerec_dump, frame 6016) | Target | Texture bind and what it samples |
|---|---|---|
| downsample | 0x04110000 8888/256: the depth buffer's bytes as a colour target of its own | 0x04088000 8888 512x512 bufw 512: the back buffer, sampled directly, its alpha the stencil mask (copied at the end of its pass, which this draw's pass ends). Blend add(SA, FIXB 0): the scene times the mask |
| black sprite | 0x04132000 8888/256, which lies inside 0x04110000's memory: a target of its own | none |
| horizontal blur | 0x04132000 | 0x04110000 bufw 256: the exact target at the address (0x04110000) |
| black sprite | 0x04110000 | none |
| vertical blur | 0x04110000 | 0x04132000 bufw 256: two targets contain the address, 0x04110000 (row 136) and 0x04132000 (row 0); the one starting there wins (task 009), as on the PSP |
| composite | 0x04088000 8888/512 | 0x04110000: the blurred bloom, added at FIX 0xAFAFAF with the alpha masked |

The aliasing cases behave as the Vulkan backend's, and no better: a texture bind inside a target of another stride
or pixel size is decoded from guest memory; a target made over memory another target covers is a texture of its
own, so the vertical blur's overshoot into rows 136 to 141 of 0x04110000 does not reach 0x04132000's rows 0 to 5
as it does on the PSP (the next frame's black sprite clears them there anyway). Guest memory under the bloom targets
changes at each SIGNAL (the depth write-back, below), before their first draw of the frame takes their guest-word
snapshot, so the binds still find the targets. The four billboard rounds (565 target 0x04154000, stride 128) are
sampled the same way, as opaque 5650 textures.

## Guest memory: transfers, read-backs and write-backs

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
| `write_back_depth(color, depth, stride)` | the target at `color` drawn last | its depth (`MTLBlitOptionDepthFromDepthStencil`) as z = round(depth x 65535) in 16 bits, 480x272 in rows of `stride` from `depth` (VRAM, `0x04000000 | (depth & 0x1FFFF0)`), screen-wide buffers only (stride 480 or more), task 019's rule; returns whether it wrote. The vertex function and the viewport's depth range map the GE's z onto depth z / 65535, so this is the GE's own z |

`PURE_NO_FB_TEXTURES` turns the first two off, as it does for the Vulkan backend's `read_back_framebuffer`.

## Frames, captures and the window

- One command buffer a frame, committed at the flip (`present_image`), on the program's one queue, which the Metal
  shell presents on too ("One command queue" below). Without the window no frame waits for the GPU unless two are
  already in flight.
- `present_image` returns `ImageApi::Metal` with the target's `id<MTLTexture>` as `image`, valid until the next call.
  When the frame write-back will store the shown target at the next flip, the picture is kept for it: the read-back
  the Vulkan shell gets anyway, or else a blit into a shared buffer recorded with the frame's commands.
- `capture_frame` reads that texture back synchronously (a blit into a shared buffer, `waitUntilCompleted`) and
  writes the BMP of `gpu::write_bmp_file` at the texture's size: 480x272, or 480S x 272S at an internal scale S
  ("Internal scale"; `PURE_SCREENSHOT_EVERY` captures go through it).
- `upload_frame` (a CPU-drawn picture: a movie frame shown from main memory, or one decoded into VRAM) copies the
  pixels into the target at that address (made with the given stride and 8888 when there is none) through a staging
  buffer and a blit, each pixel an S x S block at an internal scale S. A picture of another size than 480x272 is
  copied to the top left, unscaled, and logged once (the Vulkan backend stretches it); the frontend's are 480x272.
- `shutdown` waits for the GPU, prints the counts, and frees every target, texture and pipeline before the queue and
  the device.

### The window

Under the Vulkan shell (the default, `PURE_SHELL` unset), the window belongs to `VulkanRenderer`, which presents its own
target at the display address, and the input script's `shot` steps, which the frame regression suite captures with, read
that window (`VulkanRenderer::capture_window`, from `ui/input_script.cpp`), not `GeBackend::capture_frame`. With nothing
in the shell's targets the window is black and a `shot` writes no file at all (checked: `--only lang --env
PURE_METAL_SHELL=0` ends `FAIL (no capture)`). So, when there is a window, `present_image` reads the picture back and
hands it to the shell (`show_in_shell` in `metal_shell.cpp`: `VulkanRenderer::upload_frame` at the display address),
scaled by nearest neighbour to the shell's target size (960x544 at the default 2x) so that the shell's blit copies it
1:1. The window then shows what Metal drew, and a `shot`, reduced to 480x272 by nearest neighbour as the suite does,
gives Metal's pixels back exactly: the suite's `lang` shot and the backend's own `capture_frame` of the same frame are
identical at 480x272. This costs one GPU wait and a 2 MB upload a frame. `PURE_METAL_SHELL=0` turns it off. Under any
other shell `BackendConfig::vulkan_shell` is null and there is no hand-over and no read-back: `present_image` commits
the frame and names the target's texture, which the Metal shell samples itself (below) and the headless shell never
looks at (its `shot` steps are `capture_frame`). The start-up line then ends "pictures shown by the shell, not read
back". At an internal scale S above 1 the picture read back is 480S x 272S, which `show_in_shell` scales to the shell's
target the same way ("Internal scale").

## Internal scale

Task 066 (E3, D-015, 2026-10-10): the backend draws at an internal scale S of 1 to 6, the framework's
`video.internal_scale` (`PURE_INTERNAL_SCALE`), read at start; since task 067 the menu's Resolution row changes it
while the game runs ("A change while the game runs" below), and this game's default is Auto (our profile's
`default_internal_scale`, patch 0017-internal-scale-by-backend; the framework's default is 2), so the packed app draws
at the display's resolution out of the box. Until task 066 it drew at 1 alone (D-002). The start-up line names it:
`[metal] drawing with Apple M4 Pro, internal scale 4: targets 1920x1088, effects 480x272; ...` (`scale_report` in
metal_trace.mm), the screen-wide targets' size and the narrower ones'.

| Setting | S |
|---|---|
| 1 to 6 | that; 7 and 8, which the settings allow (the Vulkan renderer's limit), are drawn at 6 (`kMaxScale`) |
| 0, Auto | the smallest S whose 272 S covers the Metal shell's drawable height, at most 6: 2 for the drawable of a 960x544-point window at 1 pixel a point, 4 at 2 (a Retina panel, task 065), 6 in full screen here (3024x1890); the shell hands its drawable's size to `pure::metal::set_drawable_size` (`metal_device.hpp`) when it makes its layer, before the backend starts, and again at every change of it, and Auto follows it from the flip after a change that crosses a multiple of 272 lines (task 067). 1 under the Vulkan shell, which has no such drawable |
| any, with no window (the headless shell, ge_replay) | 1, unless `PURE_INTERNAL_SCALE` decides the setting (`settings::overridden_by`): the suite, the refactor check, the sweeps and every headless tool stay at 1 whatever their settings.ini holds (the framework's default is 2), and ge_replay replays Metal at 1 as before. With the switch set, a headless run and ge_replay's Metal lane draw at its value (ge_replay's Vulkan lane stays at the recording's scale) |

What each path does at S (D-015's rules; at S = 1 every one of them is what the backend did before, which the refactor
check proves: 0 differing pixels on the 18 scenes and the same counts after each of the task's three code steps):

| Path | At internal scale S |
|---|---|
| Targets | a key whose stride is at least 480 (the display buffers, stride 512) is a 480S x 272S colour and depth-stencil texture (`Target::scale`, `width()`, `height()`, `target_for`); a narrower key (the billboard target, stride 128; the bloom buffers, 256) stays 480x272, so the bloom's 11-tap blur keeps the PSP's radius on the screen (PPSSPP's "lower resolution for effects" for this game) and the adverts stay the PSP's. `kWidth` and `kHeight` stay the guest's 480x272: the GE's coordinates, guest memory and the guest-word snapshot are in them. A texture that fails to allocate is named (`[metal] target 0x... at WxH could not be made`); none did at 6 |
| Positions | through-mode positions (`ge_vertex`) and the folded GE viewport (`fold_viewport`) give clip space for the guest's 480x272 screen, and the Metal viewport is the target's own pixels, so the viewport transform scales every position by S: no uniform and no vertex changes for it. The depth (z / 65535 through the viewport's range, or the clamp's screen z) is untouched |
| Scissor | the GE scissor's pixels times S, both ends included as before |
| A target sampled as a texture | the texture's place in the target (`FragmentUniforms::uv_remap`) is relative: its size and first texel at the sampled target's scale over that target's own size. A 1x target sampled by a scaled draw (the bloom's composite reading the 256-stride buffer into the display) and a scaled target sampled by a 1x draw (the downsample reading the display into the 256-stride buffer) go through the same placement, and the sampler's bilinear does the rest. The GE's wrap is applied in the texture's own coordinates, as before (task 063) |
| Mip levels | the auto rule's gradient is taken per PSP pixel: level 0's size in `FragmentUniforms::level` times S, so the GE picks the level it picks at 1x, as the Vulkan renderer does at its scale ("Mipmaps"). The slope and constant rules do not depend on the scale. That is the Texture detail row at Original, as every tool run has it; at Enhanced, the default since task 075, D is then lowered by 16 x log2(S) whatever the rule, the level for the pixels drawn, and sampled anisotropically ("Texture detail") |
| The stencil copy | its quad over the guest's screen (`resolve_stencil_alpha`), the viewport and scissor at the target's size |
| 16-bit targets | blended in the shader on the drawn pixel's own colour and dithered per drawn pixel (the matrix by the window's x & 3 and y & 3). Every 16-bit target of this game is the billboards', at 1x |
| Points and lines | one pixel wide at any scale (Metal draws no wider line); none of the recordings (the frontend, the TEAM screen, the race at 1x and 2x) has a point or a line |
| Guest memory | the frame write-back, `read_back_framebuffer`, a block transfer's source rows (`store_target`) and the depth write-back (`store_depth`) blit the target whole at its size and give the guest the centre pixel of each S x S block, (x S + S/2, y S + S/2) (`guest_pixels`): the game sees a 480x272 picture and depth as before, and the lens flare's 4x4 depth test reads the depth at those centres. A block transfer into a target's memory draws nothing into the target, at any scale, as before: the target's guest-word snapshot then no longer matches, so later binds of that memory decode it from guest memory |
| CPU pictures | `upload_frame` writes each pixel of the picture as an S x S block |
| Frames | `present_image` reports the display target's own size (480S x 272S, as `PresentedImage` asks); `capture_frame` writes the BMP at that size; the read-back for the Vulkan shell's hand-over is at that size too |
| Buffers | the three shared buffers (`readback_`, `frame_writeback_`, `guest_readback_`) hold the largest target: 8.4 MB each at 4, 18.8 MB at 6 |

### A change while the game runs

Task 067 (patch 0017-internal-scale-by-backend): the Video tab's Resolution row (Auto, x1 to x6), which was the Vulkan
renderer's alone, asks the GE backend now (`GeBackend::supports_internal_scale()`, `set_internal_scale(setting)`,
`target_size()` for its value, "Auto   1920×1088"), and the backend answers yes. A change takes effect at the next
frame, with nothing read back mid-frame:

- When. `set_internal_scale` keeps the setting. With nothing drawn since the last flip (`frame_drawn_`, set by a pass
  and an upload, cleared at the flip), which is where the paused menu runs, the scale changes there and then;
  otherwise (the menu over the running game draws before the flip) at `begin_frame()`, right after the flip. So no
  frame is drawn at two scales. `begin_frame()` also lets Auto follow the drawable: when its height crosses a multiple
  of 272 lines (a resize, full screen and back), S changes at that flip.
- What changes (`change_scale` in metal_targets.mm). The screen-wide targets (stride at least 480) leave the target
  map for `retired_`, and the next frame makes each anew at 480S x 272S when it draws into it; the narrower ones, at
  1x whatever the scale, stay with what they hold (the billboards' adverts, the bloom buffers). The three shared
  buffers are made for 480S x 272S. The start line's clause is printed again, once per change: `[metal] internal
  scale now 1: targets 480x272, effects 480x272`. A setting that gives the same S (Auto at 4 and x4 here) changes
  nothing and prints nothing.
- What survives it. The frame write-back pending since the flip keeps its target and the buffer its copy went into
  (`PendingFrame::buffer`), so the next flip stores that picture in guest memory by its own scale's block centres. The
  picture the shell holds (the paused menu's background) is the shell's own reference to the old texture. Until the game
  draws its display again, a flip that finds no target of the new scale at the display address shows the retired one;
  the retired targets go at the first flip that shows a target of the new scale. A copy into a shared buffer from a
  target larger than the buffer (a retired one, at a capture) makes the buffer anew at the target's size first.
- What does not. A retired target's contents: a frame that draws over the previous frame's picture rather than
  clearing it would start from black once after a change, and a texture bind of a retired target's memory decodes
  guest memory (the frame write-back's picture) until the target is drawn again. Neither showed in the runs below.

Checked in the Metal window (task 067), on a fresh data directory, so at the new default, Auto, with the row unlocked
(`tools/run_boot.py` sets `PURE_INTERNAL_SCALE=1` and so locks it; the runs went without that default) and input
scripts on frontend.txt's steps to the title, each window shot reduced to 480x272 by its blocks' centre pixels and
compared at tol 24, limit 5% (scale_check's rule):
- The row. Esc, Right on Resolution (Auto to x1), Esc; then Esc, Left (x1 to Auto), Esc. The log has `[metal] internal
  scale now 1: ...` and `... now 4: ...` at the presses, and the menu shows "×1   480×272" and "Auto   1920×1088". The
  title 80 frames after the change to x1 differs from a run at `PURE_INTERNAL_SCALE=1` in 0 pixels, the title after
  the change back from the title at Auto before both in 0 pixels (and Auto from 1x in 0.35%, as scale_check's title).
- Auto following the window. Window size x2 to x3 (2880x1632 pixels) and back: `now 6`, then `now 4`, each at the
  first flip after the menu closed; the title at 6 differs from the 1x one in 0.03%, the title back at 4 from the one
  before in 0 pixels.
- A data directory whose settings.ini holds `video.internal_scale=2` (an earlier build's) draws at 2 and keeps the
  value.

### The checks

`tools/scale_check.sh [S]` (default 4) captures the suite's 18 scenes headless at `PURE_INTERNAL_SCALE=1` and at S,
checks that each S capture is 480S x 272S, reduces it to 480x272 by its blocks' centre pixels (the guest's rule above)
and compares it with the 1x capture at tol 24: each must differ in at most 5% of its pixels (D-015's bar). On the three
race scenes of Vineta K's grid (race_hud, tt_hud, fp_hud) the bloom's region, x 296-479, y 0-55 (the light strips
under the stand's roof at the top right and their glows), must keep its mean luminance within 10%. The region is where
the bloom adds the most: race frame 6016 of `out/gerec/race_1x.gerec` replayed into Metal up to the composite draw and
past it (`--cut 831` and `--cut 832`) differs by 41 to 79 in the mean luminance of the 16x16 cells there and by at
most 19 elsewhere.

At S = 4 (2026-10-10, the task's build): every capture 1920x1088; by the centre pixels 0.35% (title) to 3.03% (tt_hud)
of the pixels differ at tol 24, all 18 within 5%; the bloom region's mean luminance moves +1.07% on race_hud, -0.16%
on tt_hud and -0.17% on fp_hud. The bloom alone, replayed (race_1x.gerec, frame 6016, `PURE_INTERNAL_SCALE=4` before
and after the composite draw): it adds 16.06 to the region's mean luminance at 1x and 17.18 at 4 (+7%), 4.38 and 4.46
over the whole frame (+1.7%); the glows keep their radius on the screen and look the same.

`tools/gerec/metal_check.sh` replays Metal at 1 as before and passes as before (the TEAM frames 0 pixels over tol 24,
race frame 6016 2 pixels; step 4b, `race_warm.gerec` at Vulkan's 2x against Metal's 1x, 0.0804). With
`PURE_INTERNAL_SCALE=2` the same 2x recording replays into Metal at 2 too, and race frame 6016 then differs from
Vulkan's by 21 of 522240 pixels over tol 24 at 960x544 (`--a vulkan --b metal --frames 6016 --tol 24`): the two
backends at the same scale draw the same picture.

| Scene | Centre pixels | Top-left (imgdiff) | Scene | Centre pixels | Top-left (imgdiff) |
|---|---|---|---|---|---|
| lang | 0.0172 | 0.0830 | team_select | 0.0198 | 0.0782 |
| title | 0.0035 | 0.0499 | tt_track_select | 0.0166 | 0.0728 |
| profile | 0.0131 | 0.0652 | tt_hud | 0.0303 | 0.1084 |
| main_menu | 0.0077 | 0.0429 | fp_track_select | 0.0177 | 0.0740 |
| race_hud | 0.0275 | 0.0986 | fp_hud | 0.0290 | 0.1077 |
| single_player | 0.0092 | 0.0477 | tournament_select | 0.0285 | 0.0922 |
| class_select | 0.0153 | 0.0679 | zone_track_select | 0.0123 | 0.0541 |
| league_select | 0.0282 | 0.0907 | zone_hud | 0.0289 | 0.0713 |
| track_select | 0.0179 | 0.0742 | zone_change | 0.0121 | 0.0560 |

The reduction is the check's own, not `tools/imgdiff.py`'s nearest neighbour, which takes the block's top-left pixel
(S x, S y): that pixel's centre lies (S - 1) / 2S of a PSP pixel up and left of the 1x pixel's centre (3/8 at S = 4),
which moves every filtered edge by that much. The table gives that fraction too ("top-left"), for the record; at S = 4
it is 4.3% to 10.8%, all of it on edges. The picture is centred where the 1x one is: taking the pixel at (4x + k, 4y +
k) of each block, k = 0, 1, 2, 3 scores 0.0830, 0.0178, 0.0172, 0.0829 on lang, 0.0986, 0.0272, 0.0275, 0.0973 on
race_hud and 0.1084, 0.0312, 0.0303, 0.1084 on tt_hud: the two outer picks alike, the two inner ones alike. An
example, the frontend's: the paused movie's picture is drawn with bilinear filtering and its texel centres on the
pixel centres, so at 1x every pixel reads one texel, while at 4 the outer pixels of a block blend with the
neighbouring texel, at the screen's edges the wrapped one. Across the left column's block the white background reads
159, 222, 254, 254 (254 at 1x), across the right column's the mirror: the top-left pick is 95 levels off on the left
edge, the centre pick 32 off on the right one.

### The cost

A windowed race at 4 and at 6 on this Mac (M4 Pro), the Metal shell's 960x544 window (the drawable at a pixel a point,
before task 065), `main_menu.txt` + `single_race.txt` (shots dropped) to flip 9850, `PURE_METAL_TRACE` on, read from
flip 6250, where the race clock starts, for 60 s (`tools/frame_times.py TRACE --long 25 --fps 60 --from 6250`):

| S | Targets | Frames | Mean | 99th pct | Longest | Over 25 ms | GPU waits a frame | Depth write-back wait (median) |
|---|---|---|---|---|---|---|---|---|
| 4 | 1920x1088 | 3601 | 16.68 ms | 18.45 ms | 21.60 ms | 0 | 1.17 ms | 1.12 ms |
| 6 | 2880x1632 | 3601 | 16.68 ms | 18.42 ms | 20.51 ms | 0 | 1.55 ms | 1.33 ms |

No frame over 25 ms in either: the plan's 60 fps bar holds at 4 and at 6. The longest frames' cause is `outside` (the
game, the HLE, the kernel's pacing) or `wait depth` (the SIGNAL's depth write-back, 12.5 ms once at 4), as at 1x (task
033: a 0.6 ms median wait there). Neither run met a two-vblank stretch of the game's own within its 60 s. The
window was occluded for both races (SDL's flag from flip 3515 at 4 and 876 at 6; the trace's `occluded` column), so no
picture reached the screen and the rows say nothing of the drawable's timing; the backend's side, the draws at the
scale, the GPU waits and the write-backs, is all in them. The three shared buffers and the targets at 6 were made
without a failure.

On the screen (task 067, 2026-10-10): the same race with the window visible, after task 065, so the drawable is
1920x1088 and Auto is 4. The route as above (on an empty memory stick of its own, as the suite gives each route,
`PURE_PACED_FROM=6000` to cross the menus unpaced), `PURE_INTERNAL_SCALE=0`, `6` and `1`, the same reading of the
trace. "Shown" is the share of the race's rows whose drawable reached the screen (the trace's `shown_ms`), with no row
occluded in any of the three; "on screen" is the interval between two pictures shown (`shown_ms`):

| S | Targets | Frames | Mean | 99th pct | Longest | Over 25 ms | Shown | On screen: mean, 99th pct, longest | GPU waits a frame | Depth write-back wait (median) |
|---|---|---|---|---|---|---|---|---|---|---|
| Auto (4) | 1920x1088 | 3601 | 16.68 ms | 18.35 ms | 19.39 ms | 0 | 3600 of 3601 | 16.68, 16.67, 25.00 ms | 0.94 ms | 0.96 ms |
| 6 | 2880x1632 | 3601 | 16.68 ms | 18.43 ms | 21.23 ms | 0 | 3601 of 3601 | 16.68, 16.67, 25.00 ms | 1.24 ms | 1.03 ms |
| 1 | 480x272 | 3601 | 16.68 ms | 18.55 ms | 20.59 ms | 0 | 3601 of 3601 | 16.68, 16.67, 25.00 ms | 0.77 ms | 0.86 ms |

The race holds 60 fps on the screen at every scale, Auto included: no frame and no on-screen interval over 25 ms. The
longest frames are `outside` (the game, the HLE, the kernel's pacing) at all three. The on-screen intervals are two
refreshes of the 120 Hz panel each, but for a picture held three refreshes (25 ms) followed by a short one, 13 to 16
times in the minute at every scale alike, so not the scale's (the shell presents at the vblank after the frame's,
"Frame times"; the game's two-vblank stretches did not occur). What the scale costs is the GPU's: the waits a frame go
from 0.77 ms at 1 to 0.94 ms at 4 and 1.24 ms at 6. Runs with the window off the screen (on a desktop behind another
app's full-screen Space, or the screen locked: two at Auto, one each at 6 and 1) are not in the table; their backend
figures were alike (means 16.68 to 17.22 ms), and their only frames over 25 ms waited for a drawable macOS held back
while the window was hidden (up to 1.1 s), not a player's case.

## Sprite upscale (task 073)

Task 073 (E7, D-018, 2026-10-11): the menus' text and art and the race HUD are bitmap atlases drawn at about one texel
a pixel of the 480x272 picture: the fonts CLUT4 256x128 and 256x256 in main memory (glyphs about 15 texels tall,
antialiased in 16 alpha levels), the art atlases CLUT8 256x128 in VRAM (logos, the katakana "wipeout" strip, the
menus' bars, the ship pictures of TEAM SELECTION), the HUD's CLUT4 512x256 and 256x128. An internal scale above 1
("Internal scale") magnifies their texels and adds no detail. With the menu's Text and sprites row at Upscaled
(`game.sprite_upscale=1`; `PURE_SPRITE_UPSCALE`; Original, 0, is the default since 2026-10-12: D-018, amended), the backend redraws each such texture four times finer
at decode, whatever the internal scale. The Vulkan renderer draws the originals; the row says so in its help. It draws
the same upscaled art from a texture pack the dump switch writes (task 074, "The texture pack" below).

### Which textures

A texture from guest memory (not a target's: "Textures") is upscaled when all of these hold (`draw` in metal_draw.mm
decides, `decoded_texture` does it):

| Condition | Why |
|---|---|
| the draw is a 2D draw: through mode, or transformed under an orthographic projection (the projection matrix's w row, `projection[3]`, `[7]` and `[11]`, all 0) with lighting off | the game draws its 2D layers as transformed draws under an orthographic projection, not in through mode. In the main menu's frame (flip 4700, 32 draws) the clear is the only through-mode draw; the text is transformed sprites and the art transformed strips, as in PPSSPP's dump (`ref/main_menu.ppdmp`), and the race HUD likewise (`ref/vineta_k_start.ppdmp`, draws 839-866). Through mode alone reaches three small textures in the whole frontend route, none in a checked scene (task 073's first run). The 3D scenes are perspective; the lighting test keeps a lit orthographic model plain (no frontend draw is lit, so it leaves out nothing today) |
| the format is a palette one (CLUT4, CLUT8, CLUT16, CLUT32) or 16-bit (5650, 5551, 4444) | 8888 is the movie and TV pictures, full-colour already; DXT is not used by these layers |
| the draw samples one level (`mip_levels` is 1) | a texture with levels is a 3D one |
| the option is on | `game_option("sprite_upscale")`, read at start and at each frame (`begin_frame`), never per draw: a change in the menu applies from the next frame |

What it takes: 14 textures by flip 2200 of the frontend route, 25 in the main menu route (the two fonts, the art
atlases, the TEAM SELECTION ship picture, the icons), 49 in each race route (the menus' and the HUD's). In the race
only the HUD changes: race_hud's capture with the option on differs from the one with it off in 1.6% of its pixels,
every one of them in the HUD.

### The method

`upscale_sprite` (src/gpu/sprite_upscale.cpp), the planning session's prototype (`out/fe_tex/upscale_proto.py` on the
Mac) in C++, from a W x H RGBA8 texture to 4W x 4H:

1. Each texel's colour premultiplied by its coverage, the alpha over the texture's peak alpha (the largest in it).
2. Separable Catmull-Rom at 4x, rows first: four taps with the weights (-t^3 + 2t^2 - t)/2, (3t^3 - 5t^2 + 2)/2,
   (-3t^3 + 4t^2 + t)/2 and (t^3 - t^2)/2 at the fraction t of the sample centre (o + 0.5)/4 - 0.5, clamped at the
   edges.
3. The coverage clamped to 0..1 and the colour divided by it (0 where it is at most 0.001), clamped to 0..255: flat
   colours stay flat up to an edge.
4. A mask-like texture (at least 60% of its texels at alpha 0 or within 1 of the peak; every texture the menus draw
   is) takes its coverage through a smoothstep of half-width 0.22 about 0.5, `t = clamp((a - 0.28) / 0.44, 0, 1)`,
   `a = t*t*(3 - 2t)`: crisp antialiased outlines. Any other texture keeps the resampled coverage.
5. The alpha is the coverage times the peak; each channel rounded to the nearest level.

It runs in double precision with the prototype's operations in its order and fused multiply-add off (`#pragma clang
fp contract(off)`), so its output is the prototype's to the level: `tools/sprite_proto_check.py` on the 25 textures
the main menu route dumps finds a largest difference of 0, the prototype's three inputs (font2, vram_a2 and strip2 of
out/fe_tex/, the same pixels as three of the dumped inputs) included, and the prototype file itself run on those
inputs gives the same bytes. One departure, for a case the menus do not draw: a texture whose alpha is 0 everywhere
keeps its colour (resampled as if every texel covered) and alpha 0, where the prototype would turn it black. Hairline
strokes thin out, as the prototype showed; the glyphs and logos come out crisp and smooth where nearest neighbour
gives blocks.

### In the backend

- **The key.** `decoded_texture(memory, state, levels, upscale)` hashes a constant into the content key of an
  upscaled texture, so the same texels drawn by a 3D draw are cached plainly beside it.
- **The texture.** 4W x 4H RGBA8, one level, counted in the decoded bytes at that size: 2 MB for a 256x128 atlas,
  16 MB for the one 512x512 CLUT8 picture the menus upscale. A draw's coordinates are normalised by the GE's size
  (through mode: `uv_transform` divides by W and H) or by its texture scale (transformed), so the larger texture
  samples in place and no uniform changes; `FragmentUniforms::level` is not set (one level). The shader is unchanged.
- **The sampler.** Linear for magnification and minification whatever the GE's filter bits say (they were for one
  texel a pixel), with the GE's wrap. At internal scale 4 a texel drawn one to a pixel covers 4 x 4 drawn pixels, each
  sampling an output texel at its centre; at scale 1 a pixel samples between two output texels and the filter's blend
  comes close to the original texel.
- **The counts.** The line every 600 frames gains `..., D decoded, U upscaled (T ms)`; the exit line ends with
  `...; U textures upscaled (T ms)` (after `in S s`, since `tools/purelib/logs.py` reads the line's counts up to
  there): the textures upscaled and the time the scaler took for them. `PURE_METAL_TRACE`'s `texture_ms` includes the
  scaler's time.
- **The log.** `[pure] sprite upscale: off` at start when the option is off; `[pure] sprite upscale: on
  (game.sprite_upscale)` at the first upscale.
- **The dump.** `PURE_SPRITE_DUMP=DIR` writes each upscaled texture once, `DIR/<key>.src.png` (the decoded input) and
  `DIR/<key>.png` (the output), the cache key in 16 hex digits, with the stb_image_write the framework vendors; and,
  since task 074, the output as an entry of the texture pack `DIR/pack` ("The texture pack" below). The pictures are
  the game's: the folder stays under `out/` and is never committed.

### The texture pack (task 074)

D-018's point 4: the Vulkan renderer (Windows, and the Vulkan window on the Mac) has no scaler, but it loads HD texture
packs in PPSSPP's format (the framework's `host/gpu/texture_pack.cpp`: a `textures.ini` and PNGs keyed by a hash of the
texture's contents, installed at `textures/<disc id>/` in the data directory or used where it is, managed by the Esc
menu's Video tab). The dump switch writes the upscaled art as such a pack, so the Vulkan renderer draws what the Metal
backend draws. The pack is the base an AI pass can replace atlas by atlas later.

- **The entries.** `dump_sprite` (metal_textures.mm), for each upscaled texture once: the key from the framework's own
  `compute_texture_pack_key(memory, state, 0, options, ...)` and `format_texture_pack_key`, with the options `hash`
  xxh64 and `ignoreAddress` true and the rest the format's defaults; the 4x output as `DIR/pack/<key>.png`; and the line
  `<key> = <key>.png` appended under textures.ini's `[hashes]`. The key is 24 hex digits: 16 of cache key (the
  address left out, so zero in its top half; the dimension word, log2 height << 8 | log2 width, XORed with the
  palette's hash: the CLUT bytes the last load read and the CLUT format word) and 8 of the texels' hash, the low 32 bits
  of xxh64. The port's guest addresses differ from PPSSPP's and may differ between runs, so the address is left out:
  the texels and the palette identify the art. The same picture at another address (the menus keep up to twelve copies
  of an art atlas in VRAM over a route) is one key.
- **textures.ini.** Written when `DIR/pack` is first used and has none: a comment, `[options]` (`version = 1`,
  `hash = xxh64`, `ignoreAddress = true`), `[games]` naming `UCUS98612`, and `[hashes]`, to which each entry's line is
  appended. A key already in the folder (this run's, or a PNG an earlier run into the same `DIR` wrote) is skipped, so
  runs collect into one pack. A texture the key function refuses (it returns false: a format without a hash size, or
  memory it cannot read) is said once, `[metal] sprite pack: no pack key for texture ...`, and left out; none was in
  the routes below.
- **The keys are the loader's.** The Vulkan renderer's own dump (`PURE_TEXTURE_DUMP=DIR`, every texture it decodes,
  the originals, keyed with the same options) on the main menu route wrote the same names for all 11 pictures the
  Metal backend upscales there, the two fonts (CLUT4 256x128 `0000000038d957c250811edd`, CLUT4 256x256
  `0000000032e401a19c4925fa`) and the art atlas (CLUT8 256x128 `00000000d2df1e257fb392ca`) among them, and its
  pictures equal the Metal backend's decoded inputs pixel for pixel.
- **One difference from the loader.** A texture 512 texels tall that a through-mode draw samples is hashed by the
  Vulkan renderer only down to the lowest row its draws read (the format's rule); the dump hashes the whole texture.
  The menus' and the HUD's 2D draws are orthographic transformed draws, which the loader also hashes whole (the one
  512x512 picture the menus upscale included, whose key matched); through mode reaches only the three small textures
  task 073 found in the frontend route.
- **How the Vulkan renderer draws it.** The loader decodes a PNG on a thread of its own and the renderer uploads it
  with mips the first time a draw samples the texture; until then the original is drawn. A replacement is sampled with
  the draw's normalised coordinates, so the 4x picture lands where the original was, linear (nearest with the Video
  tab's Texture filter at Sharp).

`tools/sprite_pack.sh` builds the pack and checks it. The build runs, headless on Metal with `PURE_SPRITE_UPSCALE=1` and
`PURE_SPRITE_DUMP=DIR/dump`, the frame regression suite's 18 scenes' routes (`tools/frame_regress.sh --out`: 44 keys)
and the Single Race and the Time Trial on Vineta K on to their results screens (`tools/campaign_sweep.py --no-damage`,
the race paced, about 3.5 minutes each: 2 keys each), then moves `DIR/dump/pack` to `DIR/pack` (default
`out/sprite_pack/pack`). On 2026-10-11: 48 keys, 3.5 MB, the build 7m 43s; with `--check`, 8m 17s to 11m. A Zone run to its end panel added no key
and is not run. Twelve of the keys are one CLUT4 32x16 picture (texels hash `cd0aa2c1`) under palettes the game
animates: which of them a run meets varies from run to run; the other 36 were the same in three builds.

`--check` installs the pack in a scratch data directory of its own (`DIR/check/data/textures/UCUS98612`) and captures
main_menu and race_hud in the Vulkan window (`tools/frame_regress.sh --shell vulkan --backend vulkan`, paced from the
scene) with `PURE_TEXTURE_PACK=0` and with it on and `PURE_TRACE_TEXTURE_PACK=1`. The window's captures are its pixels,
960x544, reduced to 480x272 by the centre pixel of each 2 x 2 block for the comparison with the reference. On
2026-10-11:

| Scene | With the pack against without (at least 1%) | Without, reduced (limit) | With, reduced (limit) | HUD |
|---|---|---|---|---|
| main_menu | 0.0232 | 0.0401 (0.05) | 0.0446 (0.05) | - |
| race_hud | 0.0116 | 0.0647 (0.10) | 0.0638 (0.10) | found |

The renderer opened the pack (`[texpack] 48 textures from ...`) in both runs and uploaded 33 of its pictures for the
draws that sampled them. The reduced figures without the pack are above the suite's Vulkan column (0.033, 0.047)
because the suite reduces by the top-left pixel of each block (`tools/imgdiff.py`'s nearest neighbour) and this check
by the centre one, as `tools/sprite_check.sh` does. On Windows the script builds nothing; `--check --pack DIR` checks a
pack copied from the Mac (docs/windows.md).

### The checks

Every tool run has the option off (`PURE_SPRITE_UPSCALE=0`, `tools/purelib/port.py`'s `original_pacing`, and
`game.sprite_upscale=0` in a new scratch settings.ini), so the suite, the scale check and the HUD check measure the
PSP's texels; `tools/gerec/metal_check.sh` sets it for its replays too, which run outside port.py (with the option on,
its TEAM frames would differ from Vulkan's in 5.9% of pixels, over its 2% bar). `tools/sprite_check.sh` is the check
with it on: title, main_menu, class_select, team_select, race_hud, tt_hud and fp_hud headless at internal scale 4 with
the option off and on (`tools/frame_regress.sh --only`). Each capture with it on must be 1920x1088; reduced to 480x272
by its blocks' centre pixels (scale_check's rule), within the scene's own limit of its reference at the scene's tol
(the picture is the same picture); different from the capture with it off in at least 1% of its pixels at tol 24 (the
detail is there); for the three race scenes, with the HUD found by `tools/hud_check.py` (not zone_hud, whose HUD has no
CURRENT or LAP label); and the main menu run's exit line must count at least 2 upscaled textures in under 2000 ms.
On 2026-10-11 (the task's build):

| Scene | Reduced against the reference (limit) | Against the capture with it off |
|---|---|---|
| title | 0.0198 (0.05) | 0.0213 |
| main_menu | 0.0411 (0.05) | 0.0359 |
| class_select | 0.0621 (0.07) | 0.0583 |
| team_select | 0.0585 (0.06) | 0.0689 |
| race_hud | 0.0414 (0.10) | 0.0156 |
| tt_hud | 0.0411 (0.12) | 0.0213 |
| fp_hud | 0.0413 (0.11) | 0.0203 |

The HUD was found in the three race scenes, and the main menu route upscaled 25 textures in 70 ms. The reduced
pictures move towards their limits because the upscaled glyph is not the PSP's texel: a smooth edge where the
reference has a stepped one. team_select is the closest (0.0585 of 0.06); with its ship picture at its plain value it
would be about 0.054 (the ship's rectangle holds 1221 of its 7643 differing pixels with the option on, 574 with it
off). At internal scale 1 with the option on the suite still passes 18/18 (main_menu 0.0392, class_select 0.0596,
team_select 0.0544, the five race scenes within 0.011 of their measured values), though nine menu scenes move more than
0.03 from theirs.

### The cost

The scaler at -O2 (the profile's build) on this Mac (M4 Pro), best of ten: 64x64 0.24 ms, 128x128 1.05 ms, 256x256
4.45 ms, 512x512 18.2 ms. A route's total (headless): the frontend to flip 2200 14 textures in 46 to 53 ms, the main
menu route 25 in 70 ms, a race route 49 in 123 to 129 ms. Each texture is upscaled once, when it is first decoded,
and found in the cache after.

A windowed race at internal scale 4 with the option on (`main_menu.txt` + `single_race.txt` without their shots on an
empty memory stick, `PURE_PACED_FROM=6000`, to flip 9850, `PURE_METAL_TRACE`, read from flip 6250 for 60 s as in "The
cost" above): 3601 frames in 60.1 s, mean 16.68 ms, 99th percentile 18.57 ms, longest 20.88 ms, none over 25 ms; on
the screen 3601 pictures, interval mean 16.68 ms, longest 25.00 ms, none over. The race holds 60 fps; 51 textures
were upscaled over the run, in 219 ms in all.

## Texture detail (task 075)

Task 075 (E5, D-019, 2026-10-12): the backend picks a mipmapped draw's level as the GE does for the PSP's 480x272
pixels ("Mipmaps"; at internal scale S the auto rule's gradient is taken per PSP pixel, "Internal scale"), so at S a
surface is drawn from a level log2(S) coarser than the pixels could show, two levels at 4, and isotropically, so a
wall at a grazing angle blurs along its length. In a race frame three of four textured draws have levels (D-019:
the ships by the auto rule, the track and the scenery by the slope rule with a per-draw bias). With the menu's Texture
detail row at Enhanced (`game.texture_detail=1`, `PURE_TEXTURE_DETAIL`; the default), the backend draws them at the
level the GE would pick with S times the pixels each way and samples them anisotropically. Original (0) is the path
as it was, to the pixel. The Vulkan renderer does the same since task 076 (patch 0020-vulkan-texture-detail; "The
Vulkan renderer" below).

### What it does

| Part | Enhanced |
|---|---|
| The level | D, in 1/16 levels by the GE's rule ("The registers and the rule"), lowered by 16 x log2(S) whatever the rule, then clamped to 0..16 x (levels - 1) as before. The game's per-draw intent (the slope rule's slope and bias) is kept relative; a surface close by still draws level 0. For the auto rule the gradient stays scaled by S (level 0's size times S) and the shift removes it again: at S = 2 and 4 that is exactly the gradient per drawn pixel (`ge_log16` of a value times 2^n is the value's plus 16n), at 3, 5 and 6 within the logarithm's piecewise-linear step. At S = 1 the shift is 0 |
| The sample | through `gradient2d` instead of `level()`: `dx = dfdx(uv)` and `dy = dfdy(uv)` of the normalised coordinates (after the divide by q), rho = max(|dx x size|, |dy x size|) in texels of level 0, k = 2^(D'/16 - log2 rho), and `sample(s, uv, gradient2d(dx k, dy k))`. The GPU's isotropic level is then D'/16, and the anisotropic sampler takes its taps along the footprint's long axis at the finer level its short axis allows |
| The sampler | bit 6 of the sampler index (`kAnisotropic`, 64; the table in `initialize()` grew from 48 to 128 samplers) sets `maxAnisotropy` to 16 (`kMaxAnisotropy`), Metal's maximum: `MTLDevice` has no query for a lower limit |
| Which draws | a texture with levels from guest memory (the `levels > 1` block of `draw` in metal_draw.mm), not a 2D draw (through mode, or orthographic and unlit). Never a texture of one level, a target sampled as a texture or an upscaled sprite, which have no levels. On the race_hud route 79 of 192857 mipmapped draws are 2D and are left alone |

### In the backend

- **The option.** `read_game_options` (metal_textures.mm) reads `game_option("texture_detail")` with the Text and
  sprites row, at start and at every `begin_frame`, never per draw: a change in the menu applies from the next frame.
- **The uniforms.** `FragmentUniforms::level_range.y` holds the shift, 16 x log2(S), and `level_range.z` 1 selects the
  gradient path in `sample_texture`; both were unused, so the block keeps its 240 bytes. At Original both are 0 and the
  shader takes the `level()` sample as before. The path is chosen by the uniform, not a pipeline:
  `config/metal_pipelines.txt` is unchanged.
- **The counts.** The exit line's mipmapped count gains the enhanced draws, `M mipmapped draws (E enhanced, L mip
  levels decoded after the first)` (inside the parentheses, so `tools/purelib/logs.py` reads the line as before), and
  the line every 600 frames ends `..., M mipmapped draws (E enhanced)`. The race_hud route with the option on: 192857
  mipmapped draws, 192778 enhanced; the Zone route 41389 of 41389.
- **The log.** `[pure] texture detail: off` at start when the option is off; `[pure] texture detail: on
  (game.texture_detail)` at the first enhanced draw.

### The checks

Every tool run has the option off (`PURE_TEXTURE_DETAIL=0`, `tools/purelib/port.py`'s `original_pacing`, and
`game.texture_detail=0` in a new scratch settings.ini; `tools/gerec/metal_check.sh` sets it for its replays), so the
suite, the scale check, the sprite check and the HUD check measure the PSP's levels. The Original path is the old one
to the pixel: `tools/refactor_check.sh` from the commit before the task, at internal scale 1, at 4 and at 4 with
`PURE_SPRITE_UPSCALE=1`, found 0 differing pixels on all 18 scenes each time, and the same counts once the new
`E enhanced` fields are taken out.

`tools/texture_check.sh` is the check with it on: race_hud, tt_hud, fp_hud and zone_hud headless at internal scale 4
with the option off and on (`tools/frame_regress.sh --only`). Each capture with it on must be 1920x1088 and, reduced
to 480x272 by its blocks' centre pixels, within the scene's own limit of its reference at the scene's tol (the picture
is the same picture). For race_hud, tt_hud and fp_hud it must also differ from the capture with it off in at least 1%
of its pixels at tol 24 (the detail is there), hold more high-frequency energy (the mean absolute difference, per
channel, between each pixel and its right and its lower neighbour over the whole picture: the ratio above 1.0), and
show the HUD (`tools/hud_check.py`). The race_hud run's exit line must count at least 10000 enhanced draws, and a
race_hud run at internal scale 1 with the option on (the shift 0, the anisotropy alone) must be within its limit of
the reference. On 2026-10-12 (the task's build), about 40 s:

| Scene | Reduced, on (limit) | Reduced, off | On against off | Energy off | Energy on | Ratio | HUD |
|---|---|---|---|---|---|---|---|
| race_hud | 0.0467 (0.10) | 0.0363 | 0.0218 | 3.5752 | 4.0681 | 1.1378 | found |
| tt_hud | 0.0473 (0.12) | 0.0342 | 0.0244 | 3.5424 | 4.3499 | 1.2279 | found |
| fp_hud | 0.0472 (0.11) | 0.0340 | 0.0244 | 3.5210 | 4.3300 | 1.2298 | found |
| zone_hud | 0.0346 (0.09) | 0.0345 | (0.0002) | (2.2434) | (2.2444) | (1.0004) | - |

race_hud at scale 1 with the option on scores 0.0162 against the reference (limit 0.10; 0.0148 off). The reduced
pictures move towards their limits, by about 0.011 on the Vineta K scenes, because the reference is the PSP's coarser
level: the finer texels are not the PSP's. zone_hud is held to the reduction alone (the replan of 2026-10-12): the
Zone's mipmapped textures hold no detail between their levels where its frame draws them. Its frame has 243 draws with
levels, all enhanced, but its track and walls come out the same to the pixel; level 0 everywhere (`PURE_NO_MIPMAPS=1`,
the finest any level choice can sample) moves 0.0002 of its pixels at tol 24 from the Original capture, as Enhanced
does, where it moves race_hud's 0.0224. zone_change, the route's other scene, moves 0.0000. zone_hud's HUD has no
CURRENT or LAP label for `tools/hud_check.py`, as in the sprite check.

Metal applies the anisotropy on the `gradient2d` path: with `maxAnisotropy` 1 in place of 16 (a build not committed),
race_hud's capture with the option on differs from the committed one in 12.68% of its pixels at tol 0, 0.65% at tol 2
and 0.04% at tol 24 (tt_hud 13.05%, 1.35%, 0.05%), on the track at grazing angles, the crowds and the far scenery.

### The cost

The race at internal scale 4 in the Metal window, as in "The cost" above (`main_menu.txt` + `single_race.txt` without
their shots on an empty memory stick, `PURE_PACED_FROM=6000`, to flip 9850, `PURE_METAL_TRACE`, read from flip 6250),
with the option off and on:

| Option | Frames | Mean | 99th pct | Longest | Over 25 ms | On screen: longest, over 25 ms | GPU waits a frame | Submit a frame |
|---|---|---|---|---|---|---|---|---|
| off | 3601 in 60.1 s | 16.68 ms | 18.64 ms | 23.15 ms | 0 | 33.33 ms, 1 | 0.86 ms | 2.07 ms |
| on, flips 7023-9850 | 2828 in 47.2 s | 16.68 ms | 18.52 ms | 21.32 ms | 0 | 25.00 ms, 0 | 0.86 ms | 2.03 ms |
| on, flips 6250-6967 | 718 in 12.0 s | 16.68 ms | 18.49 ms | 22.06 ms | 0 | 37.50 ms, 1 | 0.94 ms | 2.45 ms |

The run with the option on was split where the window was covered (flips 6968 to 7022: macOS held a drawable back
for 0.97 s, the one frame over 25 ms of the minute, not a player's case). A second run with it on, the window off the
screen throughout, gave 3601 frames in 60.1 s, mean 16.68 ms, longest 20.42 ms, none over 25 ms, 0.94 ms of GPU waits
a frame. The race holds 60 fps; the anisotropic taps cost the GPU little at this scale (the waits a frame 0.86 to 0.94
ms against 0.86 off, task 067's 0.94 at Auto), and Original costs nothing new, being the same code.

### The Vulkan renderer (task 076)

Patch 0020-vulkan-texture-detail gives the Vulkan renderer, the Windows build's, the same rule. The framework does not
know the row's key: our profile names it (`GameProfile::texture_detail_option = "texture_detail"`,
`src/profile/pure_profile.cpp`), and the renderer reads `settings::game_option` of it at start and once a frame in
`begin_frame`, never per draw. Which draws are enhanced is the rule above (a texture with levels from guest memory, not
a 2D draw: through mode, or orthographic and unlit, from the draw's projection and lighting); the picture is the
same rule, reached by other means:

| Part | In the Vulkan renderer |
|---|---|
| The level | the shift, 16 x log2(S) with S the drawn target's width over 480, comes off the level rule's constant (`texture_params.x` bits 8 and up, packed in `submit`), where the auto rule already adds the same term for its per-PSP-pixel gradient (patch 0012-vulkan-mipmaps), so for the auto rule the two cancel and the gradient is per drawn pixel; the slope and constant rules lose it. Auto follows the window, so S is 2 in the default 960x544 window |
| The sample | `ge.frag`: bit 21 of `texture_params.x` (`kPushDetail`, beside `kPushPlaced` at 2^20; both exact in a float) selects `textureGrad` with the derivatives of the coordinates after the divide by q, scaled by the same k as `gradient2d` here; without it the `textureLod` path is as it was (`mip_lod` now masks the constant's twelve bits) |
| The sampler | `mip_detail_sampler`: `mip_sampler` with `maxAnisotropy` min(16, the device's `maxSamplerAnisotropy`), 16 under MoltenVK on the M4 Pro, with the `samplerAnisotropy` feature enabled where the device has it (`[render] texture detail samples isotropically: ...` where it does not). With the renderer's Sharp texture filter the nearest mip sampler stays |
| The descriptor | the sampler is part of each cached texture's descriptor set, and a texture can be drawn in one frame by an enhanced draw and by a 2D one, so a texture with levels gets a second set, `detail_descriptor`, at its first enhanced draw (made, rewritten on a Texture filter change and freed with the texture); the descriptor pool has room for it when the game names the option. Nothing is made with the option off |
| The log | `[render] texture detail: off` at start when the option is off; `[render] texture detail: on` at the first enhanced draw. The renderer has no count of its draws |

`tools/texture_check.sh --shell vulkan` is its check: race_hud, tt_hud, fp_hud and zone_hud captured in the Vulkan
window (`tools/frame_regress.sh --shell vulkan --backend vulkan`, paced from 300 flips before the scene) with the
option off and on, each capture reduced by the centre pixel of its S x S blocks (S its width over 480), the same bars
as the Metal lane, and the `on` and `off` lines in place of the count. On 2026-10-12 (the task's build, the default
960x544 window, S = 2), about 2 minutes (up to 5 when the off runs are made again, below):

| Scene | Reduced, on (limit) | Reduced, off | On against off | Energy off | Energy on | Ratio | HUD |
|---|---|---|---|---|---|---|---|
| race_hud | 0.0727 (0.10) | 0.0647 | 0.0194 | 6.3364 | 6.8594 | 1.0825 | found |
| tt_hud | 0.0800 (0.12) | 0.0699 | 0.0188 | 6.3131 | 7.1880 | 1.1386 | found |
| fp_hud | 0.0797 (0.11) | 0.0696 | 0.0188 | 6.2722 | 7.1494 | 1.1399 | found |
| zone_hud | 0.0557 (0.09) | 0.0556 | (0.0002) | (4.0860) | (4.0869) | (1.0002) | - |

The reductions take each 2 x 2 block's lower right pixel, the centre pick, where the suite's nearest-neighbour
reduction takes the upper left, hence 0.0647 off where the suite scores race_hud 0.0465. The shift is one level at
S = 2 against Metal's two at 4, and the energy ratios are lower with it (1.08 to 1.14). A first run in a fresh data
directory, or after a change to the shaders, makes the pipelines while paced, and that stall can move the race
(tt_hud's capture with the option off, after 26 new pipelines: 27% of its pixels off the suite's at tol 0); the check
makes its off runs again while they make pipelines, three rounds at most, so the race is the suite's (from a fresh data
directory the off captures of the last round equal the suite's to the pixel).

MoltenVK applies the anisotropy through `textureGrad`: with `maxAnisotropy` 1 in place of the limit (a build not
committed), race_hud's capture with the option on differs from the committed one in 15.49% of its pixels at tol 0,
2.15% at tol 2 and 0.20% at tol 24 (tt_hud 22.33%, 5.22%, 0.25%), on the crowds, the buildings and the track's edges
at grazing angles and the ships far ahead.

With the option off the renderer draws as before: the Vulkan window suite's seven scenes equal the base build's
(batch/m2 9a2e72d, patches to 0019) to the pixel, and score the base figures.

The cost, the race in the Vulkan window (960x544, FIFO at 120 Hz; `main_menu.txt` + `single_race.txt` without their
shots on an empty memory stick, `PURE_PACED_FROM=6000`, to flip 9850, `PURE_PERF=log`: the 63 one-second lines from
the race's start, a warm pipeline cache):

| Option | Scale | fps, mean (lowest) | Seconds under 59.5 | Frame, mean | Longest frame | GPU a frame, mean (largest) |
|---|---|---|---|---|---|---|
| off | Auto (2) | 59.70 (52.2) | 2 | 16.77 ms | 34.6 ms | 1.66 ms (9.3 ms) |
| on | Auto (2) | 59.71 (48.4) | 2 | 16.78 ms | 34.3 ms | 1.66 ms (9.0 ms) |
| off | 4 | 59.94 (59.8) | 0 | 16.70 ms | 21.4 ms | 2.05 ms (15.1 ms) |
| on | 4 | 59.94 (59.8) | 0 | 16.70 ms | 19.3 ms | 2.37 ms (10.4 ms) |

The two seconds under 59.5 at Auto are the last two of both runs, with the option off as on. The race holds 60 fps
with the option on as it does off; at internal scale 4 (`PURE_INTERNAL_SCALE=4`, a 1920x1088 target) the anisotropic
taps add about 0.3 ms of GPU time a frame.

## The interface fit under Fill (task 085, the Vulkan renderer)

Under the Fill aspect (D-020) the Vulkan renderer's target has the window's shape and the game draws its 3D view at
it, so the 2D interface is pulled in about the screen's centre to square pixels (`interface_fit`: `fit_x`, `fit_y`
the smaller of the two scales over each). Patch 0028-vulkan-orthographic-fit gives the fit the same 2D rule as the
sprite upscale and texture detail above: a draw is 2D when it is in through mode, or transformed under an
orthographic projection with lighting off. A through-mode draw's vertices are moved, as before; a transformed one has
its clip x and y scaled by `fit_x`, `fit_y` after `viewport_into_clip` (clip (0, 0) is the screen's centre), in its
transform and in its interpolation summary, and its scissor fitted with it. A draw into another framebuffer, a clear
and a draw that samples a rendered picture (the bloom chain) stay spread with the 3D view. So does a transformed draw
at least 470 PSP pixels wide through its transform, unless it is textured and lies within the screen (2 PSP pixels of
margin each side). The textured ones within the screen are layers of interface art: the profile screens (PROFILE, SET
NAME, SET TAG, flips 1800 to 4300 of the main_menu route) draw their panel (the rules, the A-G RACING box, the logo,
the memory stick) as one quad, 0 to 480, of a 512x512 CLUT8 texture in VRAM at 0x04179a40, and the title screen its
logo as a 512x128 one at the same address; fitted, they line up with the text over them. The untextured ones (the
menus' white backdrop, the fades) and the ones past the screen's edges (the race's fly-in glow, x -142 to 1571) are
what should cover the window. Through-mode draws keep their vertex fit and its 470-pixel rule. At 1260x540 the race
HUD and the menus keep their proportions (`tools/aspect_check.sh` (e) and (f)). The Metal shell has no Fill yet (task
086).

## The Metal shell

`PURE_SHELL=metal` puts the game in a window shell of our own, `src/host/metal_shell.mm` (`MetalShell :
portablekit::host::Shell`, registered as `metal` with a `ShellRegistration`, docs/ge-backend.md section 8), instead of
the Vulkan one. With `PURE_GE_BACKEND=metal` the game then runs with no Vulkan and no MoltenVK: the frontend route's
log has no line naming either. Under another GE backend it shows that backend's `Cpu` picture (the null backend's
black); the Vulkan backend needs the Vulkan shell and draws nothing here, as in the headless shell.

| Part | What it does |
|---|---|
| Window | an SDL window (`SDL_WINDOW_METAL \| SDL_WINDOW_RESIZABLE \| SDL_WINDOW_HIGH_PIXEL_DENSITY`, 480x272 points times the window-size setting, full screen by the setting), titled as the Vulkan shell's (`PURE_WINDOW_TITLE`, else the program's name and build label); `SDL_Metal_CreateView` and its `CAMetalLayer`: BGRA8, tagged sRGB (as MoltenVK tags its swapchain, so the colours look the same), `framebufferOnly` off for the captures, the drawable the window's size in pixels ("The drawable" below), the program's one device and command queue (`src/gpu/metal_device.hpp`, the backend's; "One command queue" below). Prints `[shell] metal: Apple M4 Pro, window 960x544 points, 1920x1088 pixels, 2x, vsync`, and `[shell] metal: window ...` again when the drawable's size changes |
| Events and input | `pump_events` handles the window's events as the Vulkan renderer's pump does: close, gamepads arriving and leaving, a display change, the mouse while it is captured for the game (only the script's mouse under scripted input), then the interface's event hook. The pad is a `host::SdlPad` the shell holds, the code the Vulkan shell uses: the keyboard through the player's bindings, the first gamepad or the input script's virtual one, the script's keys (`set_scripted_key`), the neutral pad while an interface screen is up (`set_game_input`). The pointer is captured by the Vulkan renderer's rule. `sample_pad` pumps SDL and samples without handling events |
| Present | the backend's `Metal` image (its target's `id<MTLTexture>`) is drawn into the layer's next drawable by one triangle over the letterboxed rectangle, placed as the Vulkan renderer's `record_game_blit` places it (Original), or over the whole drawable (Stretch); a `Cpu` image is uploaded to a texture first; no image clears to black. The interface is drawn in the same pass, then `presentDrawable` and commit; while the game is held to real time the drawable is presented at the real time of the PSP vblank after the one its frame began from (`presentDrawable:atTime:`, task 033, "Frame times"; `PURE_METAL_PACE=0` presents at once). A fast-forwarding load presents a flip only when none was shown for 33 ms, as the Vulkan shell does. Vsync is the layer's `displaySyncEnabled`, off for Immediate; there is no Mailbox (`supports_present_mode`) |
| Scaling filter | nearest when the sharp-screen setting is on, and whenever the picture covers a whole multiple of its size in the drawable's pixels (the default window on a 2x display, 1920x1088: 4x a 480x272 picture); linear otherwise (below) |
| Captures | `capture_window` (the input script's `shot`): the next present also copies the drawable, interface included, into a shared buffer, waits for it and writes the BMP at the drawable's size (`[render] window 1920x1088 -> PATH` on a 2x display), as the Vulkan shell's window captures are written. `ShellConfig::capture_frame` is not used |
| Interface | `initialize_ui`: `ImGui_ImplSDL3_InitForMetal` and `ImGui_ImplMetal_Init` (task 027 moved the SDL3 platform init from `Layer::attach` into the shells); `begin_ui_frame`: `ImGui_ImplMetal_NewFrame` with a render pass descriptor that has the drawable's attachments (one BGRA8 colour attachment, no depth: a 1x1 stand-in texture, since the drawable itself is taken at the present); `set_ui_draw_data` keeps the draw data, drawn by the next `present` or `present_ui` over the picture; `present_ui(show_game)` presents the last game picture (behind the paused menu) or the setup screens' brown, with the interface; `shutdown_ui` waits for the GPU and shuts both ImGui backends down |
| Other | `hold_frame` keeps a copy of the picture on screen while the hold lasts; `frame_rate_now` counts the presents of the last second; `display_refresh` is the refresh rate SDL gives for the window's display; `game_aspect` is 480/272; `device_name` the Metal device's name |

What it leaves out: frame interpolation (`present_due`, `present_until` and `pause_interpolation` do nothing and
`set_frame_rate` is ignored: every flip is presented as it comes), the Fill aspect (taken as Original: the shell keeps
the PSP's shape, as `usable_aspect` does for a game that cannot draw another), the touch controls
(`touch_controls_visible` is false), the performance overlay (`set_perf_overlay` does nothing; `PURE_PERF=log` still
prints), and the menu's texture filter and texture-pack rows, which need the Vulkan renderer (`active_renderer()` is
null under this shell, and the menu leaves them out). The Resolution row is the GE backend's since task 067 (patch
0017-internal-scale-by-backend), and the Metal backend answers it ("Internal scale"). Since task 064 (patch
0016-menu-rows-by-capability) the shell says so to the menu, which hides the rows: `supports_frame_interpolation()`,
`supports_perf_overlay()` and `supports_touch()` answer false and `supports_aspect` false for Fill, so the Video tab
has no Frame rate, Lower when behind or Performance row and Aspect ratio no Fill, and the Controls tab no F3 line and
no Touch screen section. `api_name()` is "Metal", so the System tab's graphics line reads "Metal on Apple M4 Pro".
`tools/menu_check.sh` checks the rows (docs/controls.md, "Rows the menu leaves out").

### The drawable

The window is made with `SDL_WINDOW_HIGH_PIXEL_DENSITY`, and the layer's `drawableSize` is the window's size in pixels
(`SDL_GetWindowSizeInPixels`), its `contentsScale` the window's pixel density (`SDL_GetWindowPixelDensity`), set at
creation and again on every `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` (a resize, full screen and back, a move to a display of
another density) and display change (task 065). Until then the drawable was the window's size in points, 960x544 on this
Mac's 2x panel, and macOS upscaled it, blurring every pixel whatever the scaling filter said. The window-size setting
still counts points (480x272 times the setting), so the default window here is 960x544 points and 1920x1088 pixels, and
the present's viewport (`viewport_for`), the scaling filter's rule and the window captures are in drawable pixels: the
letterbox and Stretch keep their proportions, 1920x1088 is a whole 4x of a 480x272 picture (nearest), and a `shot` is
1920x1088, each 4x4 block one pixel of the backend's picture (the title shot reduced by 2 against the backend's own
capture enlarged by 2: 0 of 522240 pixels differ; the suite's reduction to 480x272 is unchanged). The interface keeps
its size in points: ImGui's SDL3 backend gives it the window's size in points and the density as its framebuffer scale,
so the menu covers the same share of the window as before, its glyphs rasterised at 2x. In full screen macOS keeps the
window below the camera housing: on this Mac the shell logs `[shell] metal: window 1512x945 points, 3024x1890 pixels,
2x`, the panel's 3024x1964 less the 74-pixel strip beside the camera, which the letterboxed picture (3024x1714 at
Original) would not reach anyway.

### One command queue

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

Until task 031 the shell had a queue of its own, which Metal does not order against the backend's without an event
or a wait, and the window dropped the race HUD in most frames; why one queue and not a shared event:
[One command queue](history/metal-backend.md#one-command-queue-why-task-031-2026-10-06).

### The scaling filter

The backend draws at the internal scale ("Internal scale": 1x headless, the settings' scale in a window, Auto the
drawable's size) and the default window is 960x544 points: as many pixels on a 1x display, 1920x1088 on a 2x one
("The drawable" above). At an exact 2x, linear sampling mixes every window pixel with its neighbour by a quarter:
with plain bilinear the suite scores lang 0.0521, title 0.0388 and profile 0.0473 (inside the limits, far from the
backend's own 0.0002, 0.0002 and 0.0000), and the picture is visibly softer than the Vulkan shell's, which at the same
settings copies its 2x target 1:1. So the shell samples nearest whenever the picture covers a whole multiple of its
size in the drawable's pixels, where each game pixel covers whole window pixels and filtering could only blur (a 1x
picture in the default window on a 2x display is a whole 4x; a picture at Auto covers it 1:1). Sharp (the
sharp-screen setting) is nearest at any size; Smooth is bilinear at the sizes that are not whole multiples (a resized
window, full screen).

## Frame times

The backend writes a trace with a row per flip (`PURE_METAL_TRACE`), and two of task 033's changes keep the race's
frames even without changing a pixel: the render pipelines are made at start from a list ("The pre-warm list") rather
than on first use, and the Metal shell presents each picture at the real time of the PSP's vblank after its frame began
(`PURE_METAL_PACE=0` presents at once), which keeps a 120 Hz display from showing one picture 25 ms and the next 8.3 ms.
What remains in a race is the game's own: stretches of frames that wait two vblanks (docs/fidelity.md, "The two-vblank
stretches"). The runs that found all this: [Frame times](history/metal-backend.md#frame-times-task-033-2026-10-06).

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

The list covers the cells of task 042 (2026-10-07): Single Race on all 12 circuits, Time Trial and Free Play on Vineta
K, Zone 1 and the Alpha tournament; second runs of five of them with the new list made no pipeline by a draw. Not
covered yet: classes other than Vector, Zone 2 to 4, the 30-fps modes off Vineta K and the attract demos. The cells,
their keys and the second runs: [the pre-warm list's
coverage](history/metal-backend.md#the-pre-warm-lists-coverage-task-042-2026-10-07).

### Left as it is

- The two-vblank stretches: the game's, outside the backend and the shell (docs/fidelity.md).
- The SIGNAL's depth write-back waits for the GPU each race frame (0.6 ms median; 13 to 40 ms a few times a race, with
  nothing in the frame's own columns to explain it: the GPU busy with other work). Reading the depth a frame late
  would remove the wait and move the lens flare's occlusion a frame: a change to the picture, left alone.
- Hashing the textures a display list binds costs about 0.5 ms a frame (`texture_ms`). Caching by address alone would
  miss a texture rewritten in place, a change to the picture; it is no long frame's cause.
- With the window occluded macOS shows nothing and may hold `nextDrawable` back for up to a second; not a player's case.

## Texture mapping modes

The GE takes a transformed draw's texture coordinates from one of three sources, chosen by TEXMAPMODE (0xC0). The
framework's GE state ignored it and TEXSHADELS (0xC1) until task 036 (patch 0002-ge-state-commands), which carries both
in `DrawCall::texture_map` (`map_mode`, `proj_source`, `shade_light_u`, `shade_light_v`). `ge_vertex` computes the
coordinates by the mode, so the reflections the game draws with them (the ships' hulls and canopies, glass buildings,
shiny roofs: difference 1 of docs/fidelity.md) are drawn. The Vulkan renderer draws modes 1 and 2 by the same rules
since task 057 (patch 0011-vulkan-texture-mapping: `map_texture` in `ge.vert`, from the object block).

The registers: 0xC0 holds the mode in bits 0..1 and the texture matrix's source (TEXPROJMAP) in bits 8..9; 0xC1 the
light s comes from in bits 0..1 and the light t comes from in bits 8..9, as the PSP SDK's `sceGuTexMapMode(mode, a1,
a2)` and `sceGuTexProjMapMode(mode)` document them. The game's own values agree: in PPSSPP's dump of the Vineta K
race frame (`ref/vineta_k_start.ppdmp`) 96 draws have 0xC0 = 2 with 0xC1 = 0x100 (lights 0 and 1) and 40 have
0xC0 = 1 (the texture matrix, from the position); the Zone dump (`ref/zone_change.ppdmp`) has 6 with 0xC0 = 2 and
0xC1 = 0x100.

The rules are PPSSPP's hardware notes' (<https://www.ppsspp.org/docs/psp-hardware/gpu/ge-vertex-pipeline/>, the UV
modes, and <https://www.ppsspp.org/docs/psp-hardware/gpu/lighting/>, "Shade mapping"), read as documentation; no
PPSSPP code was read for them:

| Mode | The GE | In `ge_vertex` (`map_texture` in `shaders/ge.metal`) |
|---|---|---|
| 0, the UVs | u' = u x scale + offset (8- and 16-bit UVs divided by 128 and 32768 first) | as before: `uv_transform` |
| 1, the texture matrix | (s, t, q) = the source times the 4x3 texture matrix (three rows and the translation row, each component a row sum); the source is the position, the UV, the normalized normal or the normal, as TEXPROJMAP says (0 to 3); per pixel s/q and t/q | `texture_matrix * float4(source, 1)`, the source the vertex's object-space position, (u, v, 0), the normal normalized (a zero normal stays zero) or the normal as decoded; s, t and q interpolated, and the fragment function divides s and t by q (`FragmentUniforms::texture.w`) |
| 2, the environment (shade) map | s = (N.L' + 1) / 2 for the light in 0xC1 bits 0..1, t the same for the light in bits 8..9, in world space. N is the normal through the world matrix (not its inverse transpose), never normalized itself: the dot product is divided by its length. L' is the light's position for a directional light, else its position minus the vertex's world position, normalized (a zero vector stays zero); for a light of the diffuse-and-specular kind, normalize(L' + V), V the view matrix's third column normalized (the viewer at infinity along view-space +z, in world space). Lighting on or off, the light's enable, colours, attenuation, spot exponent and cone play no part | the same, from the light table of the lighting block (filled now for an environment-mapped draw, lit or not) and V in the vertex uniforms (`viewer`) |

Neither mode 1 nor mode 2 takes the texture scale and offset: the notes say shade mapping does not depend on them, and
name mode 0 as the scale-and-offset mode. (The task's brief expected them to apply after, as for mode 0. The game's
draws do not tell the two apart: in the port's race frame the environment-mapped draws that reach the screen carry
scale 1 and offset 0, while the 12 into the billboard target 0x04154000 and the 40 texture-matrix draws carry a v
scale of -1, by all appearances left from earlier draws; a throwaway build that applied the scale and offset in mode
2 drew the suite's 18 scenes pixel-identical to this one.) A target sampled as a texture is placed in the
image by the fragment function after the GE's wrap, in every mode (`FragmentUniforms::uv_remap`, task 063; "Textures"). Reversed normals (0x51) flip N as they do for
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

### Checking a draw

A recording made headless through Metal, replayed with `--cut` to just after the draw in question, with and without
the switch that turns the feature off, shows what one draw changes (the pictures of the game are not committed):

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

### Metal against Vulkan

A recording made before task 036 holds no texture map state and replays as mode 0 on both backends. One made since
carries the modes, which Metal draws, and since task 057 the Vulkan backend too; `PURE_NO_TEXMAP=1` turns them off in
both (ge_replay hands the environment to both backends), which is what `tools/gerec/metal_check.sh` sets for the race. The canopy before and after, the suite
against PPSSPP and the A/B: [Texture mapping modes](history/metal-backend.md#texture-mapping-modes-task-036-2026-10-07).

## Mipmaps

The GE samples a texture from up to eight levels, each half the size of the one before, picking the level per pixel by a
rule the draw chooses. The framework's GE state ignored the levels until task 037, so every backend sampled level 0 and
distant textures (Blue Ridge's grandstand crowds, the track's far surface, windows) were sharper than on the PSP and
shimmered as the camera moved: difference 2 of docs/fidelity.md. Patch 0002-ge-state-commands (task 037) carries the
levels in `TextureState`; this backend uploads them and picks the level as the GE does. The Vulkan renderer does the
same since task 058 (patch 0012-vulkan-mipmaps: the levels in one image's mip levels, the rule in `mip_lod` in
`ge.frag`), with the auto rule's gradient taken per PSP pixel at its internal scale.

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
`sample_texture` (`shaders/ge.metal`) q is `position.w` (Metal hands the fragment 1/w there) times the texture
matrix's q, s and t are the coordinates times that q, so their `dfdx`/`dfdy` are the GE's plane gradients, and D is
the table's with the same float-bits log16; the texel is `sample(..., level(clamp(D, 0, range) / 16))`. A draw
without levels samples as before, with Metal's own derivatives on a texture of one level.

With the Texture detail row at Enhanced (task 075, the default) a draw's `level_range.z` is 1 and the same D is
lowered by `level_range.y`, 16 x log2(S), then sampled through `gradient2d` with an anisotropic sampler instead of
`level()` ("Texture detail"). At Original both are 0 and the texel is the `level()` sample above, to the pixel.

Not done, as the game does not need them: the GE takes q once per 4-pixel span rather than per pixel; the auto mode's
bias (the notes' formula has none, and the game's auto draws all have bias 0); the separate CLUT per level; and a
minification filter without bit 2 (0 to 3) on a texture with levels samples level 0, as the SDK's names for it
(nearest, linear) say, which the notes do not cover (three draws a race frame).

### Recordings

Since task 040 the record backend writes the texels of every mip level a draw samples (docs/ge-backend.md, section 6),
so a recording replays its mipmapped draws exactly. One made between tasks 037 and 040 holds level 0's texels alone:
replay it with `PURE_NO_MIPMAPS=1`. Older recordings read as one level and replay as before. Until task 058 the Vulkan
backend sampled level 0, so on a recording made since task 037 Metal against Vulkan was like with like only with
`PURE_NO_MIPMAPS=1` beside `PURE_NO_TEXMAP=1` (task 040's note for `tools/gerec/metal_check.sh`). Since tasks 057 and
058 both backends draw the modes and the levels, so the two switches are no longer needed for that A/B; each still
turns its feature off in both (ge_replay hands the environment to both backends). The
Blue Ridge frame, the slope rule against the reference, the shimmer and the decode counts:
[Mipmaps](history/metal-backend.md#mipmaps-task-037-2026-10-07).

## The colour test, 16-bit writes and the depth clamp

Three GE states the framework's GE state ignored until task 040 (patch 0002-ge-state-commands), which carries them in
`DrawCall::color_test` (`ColorTestState`), `DrawCall::dither` (`DitherState`) and `DrawCall::clip_enabled`: differences
10 and 11 of docs/fidelity.md. The Vulkan backend draws the colour test and the depth clamp too since task 059 (patch
0013-vulkan-colortest-depthclamp: the same rules, the test as specialisation constants, the clamp with
`depthClampEnable` and three `gl_ClipDistance`s), and the 16-bit writes with the dither since task 060 (patch
0014-vulkan-16bit-dither: the same blend, offset and bits in `ge.frag`, the target's colour read as the render pass's
own input attachment, which is the nearest Vulkan has to `[[color(0)]]`; fragments of one draw that overlap are not
ordered against each other there, which no 16-bit draw of the race does).

### The registers and how the game uses them

| Register | What | In the draw state |
|---|---|---|
| COLORTESTENABLE (0x27), COLORTEST (0xD8), COLORREF (0xD9), COLORTESTMASK (0xDA) | the switch; the function in bits 0..1 (0 NEVER, 1 ALWAYS, 2 EQUAL, 3 NOTEQUAL); the reference and the mask, colours as 0x00BBGGRR | `ColorTestState`: `enabled`, `function`, `reference`, `mask` |
| DITHERENABLE (0x20), DITH0 to DITH3 (0xE2 to 0xE5) | the switch; the 4x4 matrix, DITHn the row for the pixels whose y & 3 is n, four signed 4-bit offsets, the one for x & 3 in bits 4 (x & 3) to 4 (x & 3) + 3 | `DitherState`: `enabled`, `rows`, `offset(x, y)` |
| CLIPENABLE (0x1C) | on: transformed primitives clipped at the near plane, each vertex's screen z clamped to 0..65535 | `clip_enabled` |

The command numbers are those of the framework's list of ignored commands (docs/history/fidelity.md, the feature table) and
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

`shade()` in `shaders/ge.metal` tests after fog, where the alpha test is done: the fragment's colour in 8-bit steps
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
of the game's has it off, and a recording made before task 040 reads as off, so it replays as it did.

For this game the clamp changes nothing on the screen, which is what the documentation predicts for its draws: in
PPSSPP's 18 dumps no vertex in front of the near plane lies beyond the far plane (z/w at most 0.9999, on Blue Ridge),
every such vertex's screen z lies within MINZ..MAXZ, and MINZ/MAXZ are the viewport's own range, so the near plane,
the far plane and the test cut where Metal's clipping cut. The suite's 18 captures with the clamp alone
(`PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1`) are pixel-identical to the build before the task, and the race recording
replays to the same picture with and without it. The reference cannot show the rule either way, so the brief's
escalation (the rule against the reference) did not arise.

### Recordings

A Draw record ends with the colour test, dithering and CLIPENABLE (`kPixelBytes`, 31 bytes); a Draw that ends before
them reads as no colour test, no dithering and CLIPENABLE off, so older recordings replay as before. `gerec_dump.py`
lists `ctest FUNCTION REFERENCE/MASK`, `dither ROWS` and `noclip`. On a recording made since task 040, Metal against
Vulkan no longer differs by the billboard target's bits (since tasks 057 to 060 the Vulkan backend draws the texture
map modes, the mip levels, the colour test, the depth clamp and the 16-bit writes as well);
`PURE_NO_TEXMAP=1 PURE_NO_MIPMAPS=1 PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1 PURE_NO_DEPTH_CLAMP=1` makes the Metal side
draw as before the three tasks, and race frame 6016 then differs from Vulkan's by 2 pixels over tol 24, task 025's
figure. The dither check against PPSSPP's billboard target, the scenes and regions before and after, and the recordings'
numbers: [The colour test, 16-bit writes and the depth
clamp](history/metal-backend.md#the-colour-test-16-bit-writes-and-the-depth-clamp-task-040-2026-10-07).

## What is not done yet

- What the Metal shell leaves out ("The Metal shell"): frame interpolation, the Fill aspect, the touch controls, the
  performance overlay, and the menu's texture filter and texture-pack rows.
- Texture packs, the Vulkan renderer's today: an enhancement, after fidelity (D-009); the next step of D-018 (task
  074) writes the sprite upscale's output as one. Drawing above 480x272 came
  with task 066 ("Internal scale"), the menu's Resolution row for it and the Auto default with task 067.

The race exercises neither `read_back_framebuffer` nor a block transfer from a target (its transfers come from
main memory), and the frontend calls only `write_back_frame`: the 16-bit store formats and the transfer's row range
are written to the rules above and the Vulkan backend's, and checked by no recording yet.

Not in the draw state (`DrawCall`), so neither backend draws them, and they wait for the framework's GE state to carry
them: logic ops, the texture environment colour (the blend texture function's) and colour doubling. The texture map
modes are carried and drawn by this backend since task 036, the mip levels since task 037, the colour test, dithering
and CLIPENABLE since task 040, which also reads MINZ/MAXZ, carried in `DepthState` all along (patch
0002-ge-state-commands carries the three). CLIPENABLE off on a transformed draw (no near-plane clipping; a primitive
with a vertex outside 0..65535 or behind the eye dropped) is not emulated: such a draw is clipped at both depth planes
as before and named once; the game never draws one.

## Where it differs from the Vulkan backend on purpose

- Native 480x272 (D-002) headless and in every check, at the settings' internal scale in a window (task 066); the
  Vulkan backend's checks draw the screens at 2x (its settings' scale in the suite's 960x544 window), which is where
  its 0.054 on `lang` and `profile` comes from (one-pixel edges moved by the 2x-to-1x reduction).
- The GE's texture filter bits are honoured (the Vulkan backend samples everything bilinear).
- Through-mode draws are depth-tested when the GE enables the test (the Vulkan backend never tests them).
- TCC and the ADD texture function are honoured; the alpha test reads its mask.
- FIX source factors are exact for any pair of colours (the Vulkan backend has one blend constant for both).
- Points and lines are drawn (the Vulkan backend drops them).
- Only a draw that reads the target it draws into goes through a copy.
- An empty scissor draws nothing (the Vulkan backend draws one row or column).
- Mip levels: both backends upload them and pick the level by the GE's rule (task 037 here, task 058 and patch
  0012-vulkan-mipmaps there). Drawing at 2x, the Vulkan backend adds 16 x log2 of its internal scale to the auto
  rule's D, so that g, the screen gradient, stays per PSP pixel; Metal takes g per PSP pixel the same way at its
  internal scale (task 066: level 0's size times S). With the Texture detail row at Enhanced (task 075, the default)
  Metal then lowers D by 16 x log2(S) and samples anisotropically, and so does the Vulkan renderer since task 076
  (patch 0020-vulkan-texture-detail: the shift taken off its level rule's constant, `textureGrad`, a second
  descriptor set per texture for the anisotropic sampler; "Texture detail", "The Vulkan renderer").
- 16-bit targets keep the format's bits with the GE's dithering, the colour test and CLIPENABLE's depth clamp with
  MINZ/MAXZ are in both (task 040 here; tasks 059 and 060, patches 0013-vulkan-colortest-depthclamp and
  0014-vulkan-16bit-dither there). The Vulkan backend reads a 16-bit target's colour as an input attachment with a
  barrier between draws, so overlapping fragments of one draw are not ordered as Metal's programmable blending orders
  them (`PURE_NO_DITHER=1` draws as before on either side).
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

## The 3D check

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

The TEAM screen is the frontend frame with the most transformed draws (its rotating ship is ten textured quads under an
orthographic projection), though none of them is lit, fogged, depth-tested or stencilled: no frontend frame has a lit
draw, so lighting and fog are checked on the race. Why that frame: [Choosing the
frame](history/metal-backend.md#choosing-the-frame).

### Why at internal scale 1

Recorded at the settings' 2x, the TEAM frames are 0.0519 over tol 24 (6773 pixels), all on glyph and outline edges.
The text is drawn minified (8x15-texel glyphs into about 5x10 pixels, at fractional positions) and filtered, and
reducing Vulkan's 960x544 picture to 480x272 by nearest neighbour keeps the sub-pixel whose centre is a quarter pixel
up and left of Metal's pixel centre: 0.4 texel on a glyph edge, 25 to 64 levels. A replay draws at the scale of its
recording, so a recording made with `PURE_INTERNAL_SCALE=1` has Vulkan draw at 1x like Metal, and then the two draw
the TEAM frames identically: 0 of 130560 pixels differ, at tol 0. The race at 1x is likewise exact up to its first
stencil draw, where at 2x the first pixel over tol 24 comes at draw 40 (11 pixels, the edge of an alpha test).

## The race check

`tools/gerec/metal_check.sh` step 3 replays `out/gerec/race_1x.gerec` (frames 6008-6016 at internal scale 1, both
backends at 480x272) into vulkan and metal and requires frame 6016 within `--tol 24 --max-frac 0.02`; when it
fails it bisects with `--first-diff`, prints the first differing draw's state and keeps both pictures after that
draw (`--cut`, in `out/gerec/metal_race_cut/a` and `b`). Step 4 bisects the frame for the record at tol 24 with no
fraction allowed, at 1x and at 2x (`race_warm.gerec`). The recording used here was made on 2026-10-06 by the main
checkout's metal_check run (frame 6016: 864 draws; task 024's had 906: the AI field differs from run to run).

The only place where Metal and Vulkan draw the race by different rules is the viewport's clipping ("Where it differs
from the Vulkan backend on purpose"); every other pixel over tol 4 is rounding at a test's threshold or in
interpolation and blending. The classification, the lens flare on both backends and the cost of the write-backs:
[The race check](history/metal-backend.md#the-race-check-task-025).

## History

[docs/history/metal-backend.md](history/metal-backend.md): what tasks 023 to 042 measured, in the order the doc had
it: the backend's story, the Metal shell's numbers and why one command queue, the frame-time runs, the pre-warm list's
coverage, the texture mapping modes', mipmaps' and colour test's checks, the 3D and race checks' numbers, and each
task's Verify numbers.
