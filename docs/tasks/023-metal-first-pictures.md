# 023: The Metal GE backend, first pictures (the 2D frontend)

Milestone: M6 | Branch: task/023-metal-first-pictures | Status: OPEN

## Goal
A native Metal implementation of `portablekit::gpu::GeBackend` (docs/ge-backend.md, task 021) in our own sources,
selected by `PURE_GE_BACKEND=metal`, that draws the game's 2D frontend correctly: the language page (over the paused
intro movie), the title screen and the profile screen. 3D, the stencil-as-alpha rules, the bloom chain and the depth
write-back are later tasks (024, 025); this one builds the backend's skeleton (device, targets, textures, through-mode
draws, clears, blending, alpha test, captures) and proves it on the frame regression suite's three frontend scenes.

## Read first
- CLAUDE.md, docs/ge-backend.md (all sections; 2 is the render-target model, 3 how Metal meets it, 6 what landed),
  docs/decisions.md D-002 and D-003, docs/ge-effects.md (what the race asks for later; not this task's scope)
- vendor/portablekit/host/gpu/ge_backend.hpp (the interface), ge_state.hpp (`DrawCall`, `Vertex`, `TextureState`,
  `RenderTarget`, `BlendState`, `DepthState`, `AlphaTestState`, `StencilState`, `ViewportState`; the colour and
  alpha write masks), texture_decode.hpp (`decode_texture`, `snapshot_texture`, `decode_snapshot`: CPU decode of
  every PSP texture format to RGBA8888; use it, do not write a decoder), null_backend.cpp (the smallest backend;
  its capture and registration), vulkan_ge_backend.cpp
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: how it draws (search `submit(`, through mode, clear mode,
  the blend factor and alpha-test translation, the target lookup `find_framebuffer_texture`), and
  host/gpu/shaders/ge.vert, ge.frag (the GLSL the MSL is ported from; the vendor is MIT, porting is allowed)
- patches/0003 to 0006 and 0008 (behaviour the Vulkan path has that a backend must share; 0005's alpha-test
  numbering applies here: GE function 0 is NEVER, 1 ALWAYS)
- ~/dev/bouncer-recomp/src/gs/metal_backend.mm, metal_shaders.h and docs/metal-backend.md there (read only: the
  shape of a Metal backend written without Xcode: shaders as a header string compiled at run time, `.mm` compiled
  with `-x objective-c++`, lazy GPU buffers, synchronous read-back for captures)
- tools/frame_regress.sh (`--backend metal` sets `PURE_GE_BACKEND`; the scenes, thresholds and references),
  docs/verification.md

## Deliverable
1. `src/gpu/metal_backend.mm` (+ `metal_shaders.h` with the MSL as a string, and any `.hpp` it needs): class
   `MetalGeBackend : GeBackend`, registered as `metal` with a `BackendRegistration` (our sources are compiled into
   the executable directly, so the registration is not dropped). `needs_window()` false. `initialize` makes the
   default device, a command queue, and compiles the shaders from source (`newLibraryWithSource`), reporting the
   compiler's message in `error` when it fails.
2. CMakeLists.txt: the `.mm` in `SOURCES`, compiled as Objective-C++ with ARC (`set_source_files_properties(...
   PROPERTIES LANGUAGE CXX COMPILE_OPTIONS "-x;objective-c++;-fobjc-arc")`), and `target_link_libraries(PureNative
   PRIVATE "-framework Metal" "-framework Foundation" "-framework QuartzCore")`. The build must stay a
   `tools/build.sh profile` build.
3. Render targets as section 2 of docs/ge-backend.md: keyed by (colour address, stride, format), each a colour
   texture (RGBA8 for 8888; 565/5551/4444 targets may be RGBA8 internally for now) and a `Depth32Float_Stencil8`
   texture, 480x272 (internal scale 1: D-002 says native resolution first). A texture bind whose address lies in a
   target samples that target's colour texture, the target starting at the address first (patch 0003); otherwise the
   texture is decoded from guest memory with `decode_texture` and cached by content (address, format, size and a hash
   of the bytes it covers, including the palette), so a changed texture is re-uploaded and an unchanged one is not.
4. `submit` for this task's scope: through-mode draws (`DrawCall::through`: positions in screen pixels, z 0..65535)
   of points, lines, triangles, strips, fans and sprites (sprites expand to two triangles with the PSP's texture
   coordinate rule), textured or not, with vertex colour or `material_color`; `clear_mode` draws (colour, alpha and
   depth cleared by `clear_flags`); the scissor and viewport from `ViewportState`; `BlendState` (the GE factors
   including the FIX colours, the equations the frontend uses, the common ones through Metal's blend units); the
   alpha test by GE numbering (`AlphaTestState`, patch 0005), done in the fragment shader with a discard; the colour
   and alpha write masks; depth test and write as `DepthState`. Transformed (3D) draws: also sent to the GPU through
   the same pipeline with the world, view and projection matrices and the PSP's clip-z remap, with no lighting or fog
   (vertex colour only), so that nothing is silently skipped; they are task 024's to make right. Stencil ops may be
   ignored here (task 025), but `StencilState` must be carried to the pipeline key so 025 adds them without a
   rewrite.
5. `upload_frame`: the CPU-drawn picture (the movie frames the language and profile pages show) into the display
   target's colour texture. `write_back_frame`, `read_back_framebuffer`, `block_transfer`, `write_back_depth`: count
   and log once (`[metal] ... not implemented`), return false where a result is asked; task 025 fills them.
6. `present_image`: `ImageApi::Metal`, the display target's colour texture (or the last drawn target, as Vulkan's
   `display_image`). `capture_frame`: a synchronous read-back of that texture (blit to a shared buffer,
   `waitUntilCompleted`) written as the BMP the suite reads (`gpu::write_bmp_file`). `draws_submitted`,
   `frames_presented` as the other backends count them. `shutdown` frees every target before the device, as the
   contract says.
7. `PURE_METAL_LOG=1`: one line per draw (frame, index, primitive, vertex count, target, texture, blend, alpha test)
   for debugging; off by default.
8. `docs/metal-backend.md` (new, in the shape of the Bouncer's): what is implemented, the pipeline key, the target
   and texture caches, what is deferred to 024 and 025, and the Verify numbers. `README.md`: the `metal` backend in
   the `PURE_GE_BACKEND` row, `PURE_METAL_LOG`, a Layout row for `src/gpu/`.

How to run it: `PURE_GE_BACKEND=metal` with the window shell open (do not set `PURE_NO_RENDER`): the Vulkan shell's
window shows black while Metal draws off screen, the input scripts work, and `PURE_SCREENSHOT_DIR` captures come from
`MetalGeBackend::capture_frame`. `tools/frame_regress.sh --backend metal --only lang,title,profile` runs the three
scenes that way and compares them with the PPSSPP references at the suite's thresholds.

## Acceptance criteria
- [ ] `tools/build.sh profile` builds; `PURE_GE_BACKEND=metal tools/run_boot.py --frames 300 out/023/boot.log`
      prints the `[render] GE backend metal ...` line and no `[metal] ... not implemented` line for anything in
      items 4 to 6.
- [ ] `tools/frame_regress.sh --backend metal --only lang,title,profile` passes all three scenes at the suite's
      thresholds (lang 0.07, title 0.05, profile 0.07 at tolerance 24).
- [ ] `tools/frame_regress.sh` (Vulkan, no option) still passes 5/5 with the same fractions as before this task
      (the Metal sources must not touch the Vulkan path).

## Verify
`tools/build.sh profile && tools/frame_regress.sh --backend metal --only lang,title,profile`

## May touch
- CMakeLists.txt (the `.mm` source, its compile options, the frameworks), src/gpu/ (new), docs/metal-backend.md
  (new), README.md

## Must not touch
- vendor/, patches/, src/profile/, src/hle/, src/host/, tools/, config/, ref/

## Estimated turns
70

## Escalate when
A frontend scene stays above its threshold because of a GE feature outside items 4 to 6 (a 3D draw that needs
lighting, the stencil-as-alpha rule, a block transfer or read-back the scene depends on, a render-to-texture pass):
record which draws (`PURE_METAL_LOG`) and which feature, leave the scene failing, and stop with PARTIAL rather than
widening the scope. Also stop if the interface in `ge_backend.hpp` lacks something Metal needs (say what), or if a
`.mm` cannot be built through `tools/build.sh profile`.

## Result
Status: DONE

All eight deliverables are in. `PURE_GE_BACKEND=metal` passes the three frontend scenes at 0.0002 (lang), 0.0002
(title) and 0.0000 (profile), against limits of 0.07, 0.05 and 0.07. The pixels over tolerance are the blinking
cursors (22 and 31). The Vulkan suite passes 5/5 with the same fractions as before, and its five captures are
pixel-identical to the main checkout's run of 2026-10-06 03:35. The 300-frame headless boot prints `[render] GE
backend metal (...), without a window`. Its only `[metal] ... not implemented` line is `write_back_frame`, one of
item 5's deferred calls (below). The design, numbers and deferred items are in `docs/metal-backend.md`.

One thing in the brief did not hold, and I worked around it inside "May touch". The brief says suite captures
come from `MetalGeBackend::capture_frame`. They do not. The suite's `shot` steps call
`VulkanRenderer::capture_window` (`ui/input_script.cpp`), which reads the Vulkan window, and the HLE calls
`capture_frame` only for `PURE_SCREENSHOT_EVERY`, which the suite sets to 0. With nothing in the shell's targets,
a `shot` writes no file: `--only lang --env PURE_METAL_SHELL=0` ends `FAIL (no capture)`. So when a window
exists, the backend reads each presented picture back and hands it to the shell. It scales the picture by nearest
neighbour to the shell's target size and calls the public `VulkanRenderer::upload_frame`, in
`src/gpu/metal_shell.cpp`. The window then shows Metal's picture instead of black, and a `shot` reduced to 480x272
gives Metal's pixels back exactly. The backend's own `capture_frame` of `lang` is identical to the suite's shot.
The cost is one GPU wait a frame, 0.42 ms on average (892 ms over 2128 frames). `PURE_METAL_SHELL=0` turns the
hand-over off. Task 026's presenter replaces it.

Measured beyond the Verify line (not acceptance items): `main_menu` with Metal scores 0.0106 (limit 0.05). `race_hud`
scores 0.2977 (limit 0.10), with no lighting, shadows or bloom yet, and the race route runs to frame 6046 without
errors. Metal's front-face winding was checked with a standalone test triangle: Metal counts winding in window
coordinates (y down), as Vulkan does in framebuffer space, so the GE's clockwise maps to `MTLWindingClockwise`.

Changed:
- `src/gpu/metal_backend.mm` (new): `MetalGeBackend`, registered as `metal`
- `src/gpu/metal_shaders.h` (new): the MSL, compiled at run time
- `src/gpu/metal_shell.hpp`, `src/gpu/metal_shell.cpp` (new): the hand-over to the window shell
- `CMakeLists.txt`: the sources, Objective-C++ with ARC for the `.mm`, and the Metal, Foundation and QuartzCore
  frameworks
- `docs/metal-backend.md` (new)
- `README.md`: `metal` in the `PURE_GE_BACKEND` row, `PURE_METAL_LOG`, `PURE_METAL_SHELL`, and a Layout row for
  `src/gpu/`

Verify output (last 20 lines):
```
verify 023: tools/build.sh profile && tools/frame_regress.sh --backend metal --only lang,title,profile
[0/2] Re-checking globbed directories...
[1/4] Checking the build version
frame regression 2026-10-06 04:20, commit cb9c2c0+changes, backend metal (PURE_GE_BACKEND: recorded, not enforced)
extra environment: none
run frontend: 2130 flips ...
run frontend: run_boot exit 0, frame 2130 reached: yes, 72 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a4bffb82572406c2f/out/regress/frontend.log

scene       frame  fraction  limit  tol  measured   delta  result
lang          690    0.0002   0.07   24     0.054  -0.054  PASS
title        1750    0.0002   0.05   24     0.030  -0.030  PASS
profile      2100    0.0000   0.07   24     0.054  -0.054  PASS

moved more than 0.03 from the measured value: lang profile (something changed; docs/verification.md)
frame regression: PASS, 3/3 scenes pass (1m 12s)
verify 023: PASS
```
`tools/frame_regress.sh` (Vulkan, final build): `frame regression: PASS, 5/5 scenes pass (7m 7s)`, at lang 0.0544,
title 0.0302, profile 0.0543, main_menu 0.0331 and race_hud 0.0672, each with delta +0.000.

Open questions:
1. The hand-over to the window costs one synchronous read-back a frame. Should it stay until task 026? The
   alternative is a vendor change in which `shot` steps call the backend's `capture_frame` when the backend is not
   `vulkan`. That needs a patch, so I did not make it here.
2. Acceptance 1 says "no `[metal] ... not implemented` line for anything in items 4 to 6", but item 5 asks the four
   deferred calls to log exactly that. I read the criterion as covering what items 4 to 6 ask to implement. The
   boot prints one such line, for `write_back_frame`, which the HLE calls every flip, and none for anything
   implemented.
3. The suite's `measured` column is the Vulkan backend's, so a Metal run reports "moved more than 0.03" for lang and
   profile because it improved. Per-backend measured values would need a change in `tools/`, which was outside this
   task.
4. The backend differs from Vulkan on purpose in a few places (`docs/metal-backend.md`, "Where it differs"). It
   draws at native 480x272 instead of 2x. It honours the GE's filter bits instead of always sampling bilinear. It
   depth-tests through-mode draws when the GE enables the test, and draws points and lines. In the frontend scenes
   only the resolution and the filter bits come into play, so task 024 should confirm the rest against PPSSPP on
   the race.
5. Transformed sprites are expanded in object space, as the Vulkan backend does. That is right for the frontend's
   orthographic projection, but task 024 should check it on 3D sprites.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
