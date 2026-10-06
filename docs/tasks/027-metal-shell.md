# 027: The Metal shell: a window with a CAMetalLayer, the shared SDL pad, ImGui on Metal

Milestone: M6 | Branch: task/027-metal-shell | Status: OPEN

## Goal
With the shell seam (task 026, patch 0010) and the Metal GE backend (task 023), the port still shows Metal's
pictures through the Vulkan window by a read-back a frame. This task adds `MetalShell`, in our sources, selected by
`PURE_SHELL=metal`: an SDL window with a `CAMetalLayer`, the shared SDL pad sampling and scripted input, the backend's
`Metal` image presented directly (letterboxed), and the framework's ImGui interface on ImGui's Metal renderer backend.
After it, `PURE_SHELL=metal PURE_GE_BACKEND=metal` runs the game with no Vulkan or MoltenVK involved, and the read-back
hand-over of task 023 is turned off under this shell.

## Read first
- CLAUDE.md, docs/ge-backend.md sections 8 and 8.5 (the `Shell` interface as landed, the headless and Vulkan shells,
  what `Layer::attach` still assumes), docs/decisions.md D-002, D-003, D-007, docs/metal-backend.md ("The window":
  the hand-over this task replaces; `present_image` returns `ImageApi::Metal` with the target's `id<MTLTexture>`)
- vendor/portablekit/host/shell/shell.hpp (every method you implement), vulkan_shell.cpp (the forwarding shell:
  which calls the HLE and the UI make), headless_shell.cpp (the smallest shell), sdl_pad.hpp and .cpp (`SdlPad`:
  sample, gamepad attach, scripted keys; derive from it or hold one), script_steps.hpp
- vendor/portablekit/host/ui/layer.cpp (`Layer::attach`: `ImGui_ImplSDL3_InitForVulkan(window)` then
  `shell.initialize_ui`; `begin_ui_frame`, `set_ui_draw_data`, `present_ui`), ui/input_script.cpp (pushes SDL events
  at `shell().window()` and attaches the virtual gamepad: works with any SDL window)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `pump_events` (the SDL event loop: window close, the event hook,
  `SdlPad`), `present` (letterboxing by `game_aspect()`, the UI composited over the game), `capture_window`
- vendor/portablekit/third_party/imgui/imgui.h (`IMGUI_VERSION`, 1.92.9b), backends/imgui_impl_sdl3.h
- src/gpu/metal_backend.mm (`present_image`, `to_shell_` and `PURE_METAL_SHELL`), src/gpu/metal_shell.cpp (the
  hand-over), CMakeLists.txt (how the `.mm` is compiled and the frameworks linked)
- SDL3: `SDL_Metal_CreateView`, `SDL_Metal_GetLayer`, `SDL_WINDOW_METAL`

## Deliverable
1. `src/host/metal_shell.mm` (+ `.hpp` if needed): `MetalShell : portablekit::host::Shell`, registered as `metal`
   with a `ShellRegistration`. `initialize`: an SDL window (`SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE`, the title from
   `ShellConfig` or the framework's default), `SDL_Metal_CreateView`, the `CAMetalLayer` with the default device (the
   same device the backend uses: `MTLCreateSystemDefaultDevice`), a command queue. `has_window()` true,
   `window()` the SDL window, `available()` after initialize.
2. Events and input through `SdlPad` (shared with the Vulkan shell): `pump_events` runs the SDL event loop as the
   Vulkan renderer's does (close, the UI's event hook, scripted keys), `sample_pad`/`pad` from `SdlPad::sample`,
   the gamepad attach (`gamepad()`), `set_scripted_key`, `set_scripted_input`, `set_game_input`, `set_pointer_free`,
   mouse motion; touch controls absent (`touch_controls_visible` false; `touch_controls()` may return a static
   empty object); `request_quit`/`quit_requested`.
3. `present(image, display_address, moment)`: a `Metal` image is drawn into the layer's next drawable, letterboxed
   to the game's aspect (480:272) with nearest or linear sampling by the sharp-screen setting, a `Cpu` image is
   uploaded to a texture first, no image clears to black; then the UI draw data (item 5) over it, then
   `presentDrawable` and commit. Vsync by `set_present_mode` (`displaySyncEnabled`). `present_due`/`present_until`
   do nothing (no frame interpolation); `pause_interpolation`, `set_fast_forward`, `hold_frame`, `set_frame_rate*`,
   `display_refresh` (the display's refresh rate), `frame_rate_now` (frames presented a second), `game_aspect`
   (480/272), `set_window_scale`, `set_fullscreen`, `set_aspect` (letterbox only; Fill unsupported as
   `usable_aspect` says), `set_sharp_screen`, `set_perf_overlay` (may do nothing), `device_name` (the Metal
   device's name).
4. `capture_window(path)`: the next presented drawable, composited, read back and written as a BMP (the input
   script's `shot`); `ShellConfig::capture_frame` is not needed under this shell.
5. The interface. `Layer::attach` calls `ImGui_ImplSDL3_InitForVulkan(window)`, which is wrong for this shell: a
   small vendor patch (0012; the series has 0011 by then) moves the platform init into `Shell::initialize_ui` (the
   Vulkan shell calls `ImGui_ImplSDL3_InitForVulkan` itself, this shell `ImGui_ImplSDL3_InitForMetal`), and
   `Layer::attach` calls only `shell.initialize_ui`. `MetalShell::initialize_ui` also calls `ImGui_ImplMetal_Init`,
   `begin_ui_frame` `ImGui_ImplMetal_NewFrame` with the drawable's render pass descriptor, `set_ui_draw_data` keeps
   the draw data, `present_ui(show_game)` renders it over the game's image in `present` (or alone when the game is
   hidden), `shutdown_ui` the shutdowns. ImGui's Metal backend (`imgui_impl_metal.h`, `imgui_impl_metal.mm`, MIT,
   the files from Dear ImGui 1.92.9b exactly, licence header kept) goes under `third_party/imgui_metal/` in our repo
   and into the build beside the `.mm`.
6. `src/gpu/metal_backend.mm`: the hand-over to the window (`to_shell_`) is off when the shell is not the Vulkan one
   (`BackendConfig::vulkan_shell == nullptr`), so no read-back happens under this shell; `PURE_METAL_SHELL` keeps its
   meaning under the Vulkan shell.
7. CMakeLists.txt: the new `.mm` sources (Objective-C++ with ARC, as the backend) and ImGui's Metal backend; the
   frameworks are already linked. `tools/frame_regress.sh`: a `--shell vulkan|metal|headless` option that sets
   `PURE_SHELL` for the runs and records it in the summary beside the backend (default vulkan; the suite is
   otherwise unchanged).
8. docs/metal-backend.md: a section "The Metal shell" (what it does, what it leaves out: interpolation, Fill, touch,
   texture-pack rows), docs/ge-backend.md 8.5: a line that the `metal` shell exists and where. README.md: `metal` in
   the `PURE_SHELL` row, `--shell` in the suite's row.

## Acceptance criteria
- [ ] `PURE_SHELL=metal PURE_GE_BACKEND=metal tools/run_boot.py --script config/pad_scripts/frontend.txt --frames 2200
      out/027/metal.log` reaches frame 2200 with the route's presses taking effect (`Profile_part1` opened) and no
      Vulkan or MoltenVK line in the log (`grep -ci "vulkan\|moltenvk" out/027/metal.log` prints 0).
- [ ] `tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile` passes with task 023's
      fractions (0.0002, 0.0002, 0.0000), the captures coming from this shell's `capture_window`.
- [ ] `tools/frame_regress.sh` (Vulkan shell and backend) passes 5/5 unchanged, and `PURE_GE_BACKEND=metal` under the
      Vulkan shell still passes the three frontend scenes (the hand-over still works there).
- [ ] The menu opens over the game under the Metal shell (the framework's key for the interface), and closes.
      Record a screenshot (`capture_window`) with it open in out/027/ and name the file in Result.

## Verify
`tools/build.sh profile && tools/patches.sh check && tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile && PURE_SHELL=metal PURE_GE_BACKEND=metal python3 tools/run_boot.py --script config/pad_scripts/frontend.txt --shots out/027/shots --frames 2200 --seconds 300 out/027/metal.log && grep -q 'Profile_part1' out/027/metal.log && test "$(grep -ci 'vulkan\|moltenvk' out/027/metal.log)" = 0`

## May touch
- src/host/ (new `.mm`/`.hpp`), third_party/imgui_metal/ (new, the two ImGui files verbatim), src/gpu/metal_backend.mm
  (item 6 only), CMakeLists.txt, tools/frame_regress.sh (the `--shell` option only), docs/metal-backend.md,
  docs/ge-backend.md (8.5, one line), README.md, and vendor/portablekit/host/ui/layer.cpp, host/shell/shell.hpp,
  host/shell/vulkan_shell.cpp for item 5 only, via `tools/patches.sh export 0012-ui-platform-init-in-shell`

## Must not touch
- vendor/portablekit/ apart from item 5's three files; patches/0001-0011; src/gpu/metal_shaders.h; src/tools/;
  src/profile/; src/hle/; tools/ apart from frame_regress.sh's option; config/; ref/

## Estimated turns
80

## Escalate when
SDL3's Metal view cannot be made on this machine (report the error), `SdlPad` cannot be used from our sources
(report what it needs from the renderer), ImGui's Metal backend of 1.92.9b does not build against the vendored
ImGui (report the error; do not patch ImGui), or the platform-init change needs more of `ui/` than `Layer::attach`.
Do not change the GE backend beyond item 6, and do not add frame interpolation or Fill.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
