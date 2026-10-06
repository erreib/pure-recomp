# 027: The Metal shell: a window with a CAMetalLayer, the shared SDL pad, ImGui on Metal

Milestone: M6 | Branch: task/027-metal-shell | Status: MERGED 2026-10-06 (f5c330f)

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
Status: DONE

Changed:
- `src/host/metal_shell.mm` (new): `MetalShell : portablekit::host::Shell`, registered as `metal`. SDL window
  (`SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE`, size and full screen from the settings, the Vulkan shell's title),
  `SDL_Metal_CreateView`, its `CAMetalLayer` on `MTLCreateSystemDefaultDevice` (BGRA8, sRGB-tagged as MoltenVK tags
  its swapchain, `framebufferOnly` off), a queue of its own. Events and input as the Vulkan renderer's pump, the pad
  from a held `host::SdlPad` (gamepad attach, scripted keys, scripted mouse, pointer capture); no touch controls.
  `present`: the `Metal` texture (or an uploaded `Cpu` picture, or black) drawn letterboxed into the next drawable, the
  interface in the same pass, `presentDrawable`, commit; fast-forward thinning as the Vulkan shell; vsync by
  `displaySyncEnabled`; no interpolation, no Fill. `capture_window` reads the composited drawable back as a BMP.
  Interface: `ImGui_ImplSDL3_InitForMetal` + `ImGui_ImplMetal_Init`, `ImGui_ImplMetal_NewFrame` with a pass descriptor
  of the drawable's attachments (a 1x1 BGRA8 stand-in, since the drawable is taken at the present), `present_ui`.
- `third_party/imgui_metal/imgui_impl_metal.h`, `imgui_impl_metal.mm` (new): Dear ImGui's Metal backend from the
  v1.92.9b tag, verbatim (the vendored `imgui.h` and `backends/imgui_impl_sdl3.cpp` are byte-identical to that tag's).
- `patches/0012-ui-platform-init-in-shell.patch` and its row in `patches/README.md`: vendor `host/ui/layer.cpp`
  (`Layer::attach` loads the fonts, calls only `shell.initialize_ui`, then sets the gamepad mode),
  `host/shell/shell.hpp` (the contract's comment), `host/shell/vulkan_shell.cpp` (`ImGui_ImplSDL3_InitForVulkan` before
  the renderer's ImGui backend; `shutdown_ui` shuts both down).
- `src/gpu/metal_backend.mm` (item 6): `to_shell_` already required `BackendConfig::vulkan_shell`; the comments say so
  and the start-up line under another shell now ends "pictures shown by the shell, not read back" (was "no window").
- `CMakeLists.txt`: the shell and ImGui's `.mm` beside the backend's (Objective-C++, ARC), `third_party/imgui_metal` on
  the include path, and `-framework CoreGraphics` (the sRGB colour space; see Open questions).
- `tools/frame_regress.sh`: `--shell vulkan|metal|headless` sets `PURE_SHELL` and is recorded in the summary.
- `docs/metal-backend.md` ("The Metal shell": parts, what it leaves out, the scaling filter, numbers; the quick start,
  switches, files and "The window" brought up to date), `docs/ge-backend.md` 8.5 (one line), `README.md`.

Acceptance:
- Verify route: frame 2200 reached, `Profile_part1.PMF` opened after `pad start` at 1800, `grep -ci "vulkan\|moltenvk"
  out/027/metal.log` prints 0; the backend made 1 GPU wait in the run (shutdown), against 2128 with the hand-over.
- `tools/frame_regress.sh --shell metal --backend metal --only lang,title,profile`: 0.0002, 0.0002, 0.0000 (Verify run
  and one more; a third run caught the blinking cursor after LOAD on profile, 0.0002, 22 pixels: pacing, as task 023
  saw on lang and title). The captures are pixel-identical at 960x544 to the Vulkan shell's hand-over captures.
- `tools/frame_regress.sh` (Vulkan shell and backend): PASS 5/5, 0.0544 0.0302 0.0543 0.0331 0.0672, 7m 7s; the lang
  capture is identical to the main checkout's run of 04:54. `--backend metal` under the Vulkan shell: 0.0002, 0.0002,
  0.0000 (the hand-over still works). `--shell headless --backend metal`: the same three, in 2 s.
- Menu: Esc over the language page opens the paused menu over the game and Esc closes it (`[menu] closed after
  1.4 s`): `out/027/menu_shots/menu_open.png` (open) and `out/027/menu_shots/menu_closed.png` (closed). Also checked:
  Window size x3 from the menu resizes to a 1440x816 drawable (`out/027/resize_shots/`, run on a scratch
  `PURE_DATA_DIR`), and `PURE_GE_BACKEND=null` in this shell shows its black Cpu picture.

Verify output (last 20 lines):
```
  0xda x1 first=0x0
  0xe2 x2 first=0x0
  0xe3 x2 first=0x0
  0xe4 x2 first=0x0
  0xe5 x2 first=0x0
  0xe6 x1 first=0x0
  0xf0 x1 first=0x0
  0xf1 x1 first=0x0
  0xf2 x1 first=0x0
  0xf3 x1 first=0x0
  0xf4 x1 first=0x0
  0xf5 x1 first=0x0
  0xf6 x1 first=0x0
  0xf7 x1 first=0x0
  0xf8 x1 first=0x0
  0xf9 x1 first=0x0
[metal] 2200 frames, 20623 draws, 2196 passes, 347 textures decoded, 0 framebuffer textures, 0 target copies, 0 uploads, 2 targets, 1 GPU waits (0.371792 ms) in 73.831 s
[run_boot] shots: 4 new BMP(s) converted to PNG in out/027/shots (lang, notice, profile, title)
[run_boot] exit 0 after 74.4s, 361 lines
verify 027: PASS
```
(Above them in `out/027/verify.txt`: `ok: 12 patch(es) reproduce vendor/portablekit at 8b0c3fe`, and the suite's table
lang 0.0002, title 0.0002, profile 0.0000, `frame regression: PASS, 3/3 scenes pass (1m 11s)`.)

Open questions:
1. The scaling filter departs from "nearest or linear by the sharp-screen setting": the shell samples nearest whenever
   the picture covers a whole multiple of 480x272 (the default 2x window), and Smooth is bilinear only at other sizes.
   Plain bilinear at 2x blends every pixel with its neighbour by a quarter and scores 0.0521, 0.0388, 0.0473 (inside
   the limits, not task 023's fractions the acceptance asks for), and looks softer than the Vulkan shell, which copies
   its 2x target 1:1 at the same settings. Keep, or make Smooth literal and accept those fractions?
2. `-framework CoreGraphics` is linked (the brief expected the frameworks to be there already) for
   `CGColorSpaceCreateWithName(kCGColorSpaceSRGB)`, so the layer is colour-matched like MoltenVK's sRGB swapchain.
   Without it the window would show the same bytes untagged (more saturated on a P3 display); captures are unaffected.
3. `third_party/imgui_metal/` holds only the two files, as the brief says. Their headers carry no copyright line; the
   MIT notice is in the vendored `third_party/imgui/LICENSE.txt`, which is not committed in our repo. Add a copy of it
   beside the two files?
4. The shell samples the backend's targets on its own command queue. It relies on Metal's tracking of tracked
   resources across the queues of one device and on the backend committing the frame before `present`; captures are
   identical to the read-back path and nothing tore, but Apple documents the ordering plainly only within one queue. An
   `MTLSharedEvent` the backend signals would make it explicit, which is a backend change beyond item 6.
5. Framework text outside May touch: the menu's System tab reads "Graphics: Vulkan on <device>" under this shell
   (`ui/menu.cpp`), and its Frame rate row offers rates this shell ignores. `src/gpu/metal_shell.hpp` still says the
   hand-over lasts "until the shell has a Metal presenter (task 026)"; it now serves the Vulkan shell only.
6. A `Cpu` picture is uploaded into one texture after waiting for the previous present; fine for the null backend,
   a real CPU backend would want two.

## Review
Verify rerun: PASS from the main checkout on the merged build, 2026-10-06 (`tools/verify_task.sh 027`): twelve
patches reproduce vendor at 8b0c3fe; `--shell metal --backend metal` lang 0.0002, title 0.0002, profile 0.0002 (the
blinking cursor, as task 023 saw), 1m 13s; the Metal-shell frontend route reaches frame 2200 with `Profile_part1`
opened and no Vulkan or MoltenVK line, 1 GPU wait in 2200 frames; then `tools/frame_regress.sh` (Vulkan) 5/5 at
0.0544, 0.0302, 0.0543, 0.0331, 0.0672, +0.000 each (7m 7s).
Spot-read: patch 0012 (the platform init moved into each shell's `initialize_ui`, both shutdowns paired),
`metal_shell.mm` (window and layer setup, the event pump and `SdlPad`, `draw`: next drawable, letterboxed picture, the
interface in the same pass, present, the pending window capture read back), the CMake and `frame_regress.sh --shell`
changes, the two ImGui files (verbatim 1.92.9b).
Merged: f5c330f into batch/m2; 57608da adds Dear ImGui's MIT licence beside its two files (open question 3).
Notes: open question 1 (nearest sampling at whole multiples of 480x272, bilinear only at other sizes): keep; it is
what the Vulkan shell does at 2x and it keeps the suite's fractions. CoreGraphics for the sRGB colour space: fine.
Open question 4 (the shell samples the backend's targets from its own queue, relying on Metal's resource tracking
across queues of one device): record as a backend follow-up (an `MTLSharedEvent` the backend signals at the flip),
to be done in 025 or after. Open question 5: the menu's "Graphics: Vulkan on" text and the frame-rate rows under this
shell are cosmetic; the stale `metal_shell.hpp` comment is fixed here. The read-back hand-over of task 023 now serves
the Vulkan shell only.
