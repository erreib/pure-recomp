# 026: The shell seam: `host::Shell`, the Vulkan shell adapter, a headless shell (patch 0010)

Milestone: M6 | Branch: task/026-shell-seam | Status: OPEN

## Goal
Task 021 put the GE behind `gpu::GeBackend` and left the window shell fused in `VulkanRenderer`. This task puts the
shell behind `host::Shell` (docs/ge-backend.md section 8, D-007) the same way: a mechanical vendor patch with no
behaviour change for the Vulkan path (the regression suite is the gate), plus a `HeadlessShell` that reads the input
script at pad level so that every route can run without a window. The Metal shell (task 027) is written against the
interface this task lands.

## Read first
- CLAUDE.md, docs/ge-backend.md (sections 6 and 8), docs/decisions.md D-003 and D-007
- vendor/portablekit/host/gpu/vulkan_renderer.hpp (the public surface: which methods are the shell's),
  vulkan_renderer.cpp: `initialize` (where the window, the gamepad and the virtual gamepad are made), `pump_events`,
  `sample_pad`, `pad`, `set_scripted_key`, `set_scripted_input`, `set_event_hook`, `present`, `present_due`,
  `present_until`, `pause_interpolation`, `set_fast_forward`, `hold_frame`, `capture_window`, `initialize_ui`,
  `begin_ui_frame`, `set_ui_draw_data`, `present_ui`
- vendor/portablekit/host/hle/hle_media.cpp: every use of `media().renderer`, `active_renderer()`,
  `ensure_renderer()`, `ensure_backend()` (the shell's call sites), and the sceCtrl HLE (`sample_pad`/`pad`)
- vendor/portablekit/host/ui/layer.cpp (`Layer::attach`, `handle_event`, `renderer()`), ui/input_script.cpp (the
  script format and the names it accepts; how it pushes SDL events at the window and drives the virtual gamepad; the
  live file), ui/*.cpp users of `renderer()` (setup_screens, menu, file_browser, text_input, widgets,
  texture_pack_screen), host/camera_probe.cpp, host/input/bindings.hpp
- vendor/portablekit/host/kernel/kernel.cpp `pace_to_real_time` (reads `<prefix>_NO_RENDER`; do not change it)
- patches/0009-ge-backend-seam.patch (the shape of a mechanical seam patch), patches/README.md
- docs/tasks/021-ge-backend-seam.md (Result and Review)

## Deliverable
1. `host/shell/shell.hpp`: `portablekit::host::Shell` with the three groups of section 8.1 (lifecycle, events and
   input, presenting, interface), `ShellConfig` (today's `RendererConfig`), and `PadState`, `MouseMotion`,
   `CameraReading`, `kScriptedMouse` moved here (the renderer header includes it and keeps the names visible in
   `portablekit::gpu` through aliases, so nothing else has to change). A registry as `ge_backend.hpp` has
   (`register_shell`, `make_shell`, `shell_names`, `selected_shell()` from `<prefix>_SHELL`, default `vulkan`).
2. `host/shell/vulkan_shell.cpp` (renderer sources): `VulkanShell`, an adapter that owns the `VulkanRenderer` and
   forwards every method to it, at the same point and with the same arguments as the HLE and UI called them before.
   `present(image, address, time)`: for the Vulkan GE backend's image (`ImageApi::Vulkan`), `renderer.present(address,
   time)` as today; for a `Cpu` image, `renderer.upload_frame` of its pixels into the display address first, then the
   same present (how a non-Vulkan backend's picture reaches the window before task 027). A `renderer()` accessor for
   the UI screens that need Vulkan itself.
3. `host/shell/headless_shell.cpp` (system-layer sources, no SDL or Vulkan): `HeadlessShell`, `has_window()` false,
   `window()` null, `gamepad()` null. `pad()` is built from the input script (`<prefix>_INPUT_SCRIPT`) and the live
   file (`<prefix>_INPUT_LIVE`) read at pad level, frame by frame as the shell's `present()` counts frames: the same
   file format and action names as `ui/input_script.cpp` (`pad NAME [FRAMES]`, `axis NAME VALUE`, `shot NAME`,
   `quit`); `shot` asks the active GE backend to `capture_frame` into `<prefix>_SCREENSHOT_DIR/NAME.bmp` and prints
   the same `[script] frame N: shot NAME` line; `quit` makes `pump_events()` return false; mouse, key and text actions
   are reported once and ignored. Reuse `ui/input_script.cpp`'s parser if it can be shared without SDL; otherwise a
   small parser of the same grammar here, and say so. `present()` counts frames; the UI methods are no-ops;
   `initialize_ui` returns false with a message.
4. `host/shell/sdl_pad.cpp` (renderer sources for now): the SDL pad sampling extracted from
   `VulkanRenderer::sample_pad` and the scripted-key state, as a struct the renderer uses unchanged (the Metal shell
   of task 027 will use it too). Keep the renderer's behaviour exactly; this is a move, not a rewrite.
5. `hle_media.cpp`: `media().renderer` becomes `std::unique_ptr<host::Shell> shell` (declared before the backend, so
   the backend is destroyed first as today); `ensure_backend()` becomes `ensure_shell_and_backend()`: the shell named
   by `<prefix>_SHELL` is made first (with `<prefix>_NO_RENDER` set: the headless shell), then the backend with
   `BackendConfig::vulkan_shell` set when the shell is the Vulkan one, with the section 6 selection table unchanged
   (`NO_RENDER` + `vulkan` backend: no rendering at all, as today; `NO_RENDER` + `null`: headless, every draw
   reaches the backend). `present_frame` calls `shell->present(image, address, time)` and the rest through the
   interface. `active_renderer()` returns the `VulkanRenderer` only when the shell is the Vulkan one, for
   `ui/` callers that need Vulkan itself; every other caller goes through `Shell`. The sceCtrl HLE samples the shell's
   pad.
6. `ui/layer.cpp` and the other `ui/` users: attach to a `Shell` (`Layer::attach(host::Shell &)`); ImGui's SDL3
   platform init only when `has_window()`; `renderer()` for the Vulkan-only screens via `active_renderer()`.
   `ui/input_script.cpp` keeps its SDL path for shells with a window.
7. `cmake/PortableKit.cmake`: the new sources. Patch 0010 via `tools/patches.sh export 0010-shell-seam`, a row in
   `patches/README.md`, README rows for `PURE_SHELL` (and the headless shell's script support), docs/ge-backend.md
   section 8.5 "What landed" (the interface as landed, differences from 8.1, selection table, numbers).

## Acceptance criteria
- [ ] `tools/frame_regress.sh` passes 5/5 with the same fractions as before (+/- 0.000 expected: the Vulkan path is
      unchanged), and the five captures are pixel-identical to the previous run's (`tools/imgdiff.py --tol 0`).
- [ ] `PURE_SHELL=headless PURE_GE_BACKEND=null PURE_TRACE_MPEG=1 tools/run_boot.py --script
      config/pad_scripts/frontend.txt --frames 2200 --env PURE_NO_RENDER= out/026/headless.log` reaches frame 2200,
      and the log shows the frontend route's presses took effect: the title's Start opens the profile movie
      (`Profile_part1` appears in the `[mpeg]` lines, which it never does when the pad is neutral, since a run without
      input sits on Language Selection).
- [ ] The same headless run with `PURE_SCREENSHOT_DIR` set writes the route's `shot` captures (black, from null) and
      prints the `[script] frame N: shot NAME` lines at the script's frames.
- [ ] `tools/patches.sh check` passes with ten patches.

## Verify
`tools/patches.sh check && tools/frame_regress.sh && PURE_SHELL=headless PURE_GE_BACKEND=null PURE_TRACE_MPEG=1 python3 tools/run_boot.py --script config/pad_scripts/frontend.txt --frames 2200 --seconds 300 --env PURE_NO_RENDER= out/026/headless.log && grep -q 'Profile_part1' out/026/headless.log`

## May touch
- vendor/portablekit/host/shell/ (new), host/gpu/vulkan_renderer.hpp and .cpp (moves only), host/hle/hle_media.cpp,
  host/ui/*.cpp and .hpp, host/camera_probe.cpp, cmake/PortableKit.cmake, all via `tools/patches.sh export
  0010-shell-seam`; patches/README.md; docs/ge-backend.md (a new section 8.5 only); README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/kernel/, host/gpu/ge_backend.*, null_backend.cpp,
  record_backend.cpp, ge_record_format.hpp, vulkan_ge_backend.cpp (the GE seam is fixed), patches/0001-0009, src/,
  tools/, config/

## Estimated turns
80

## Escalate when
The Vulkan path cannot keep pixel-identical output without changing the renderer's frame loop (report what
`present` assumes about the shell), a `ui/` screen needs more from the renderer than `active_renderer()` can give
without a window (report which), or the input script's grammar cannot be read at pad level for the frontend route
(report which actions the route needs that have no pad meaning). Do not touch the kernel's pacing or host-wait sleep;
a headless run at about 19 frames a second is expected (section 8.4).

## Result
Status: DONE. All seven deliverables are in patch 0010. The Verify line passes, and so do all four acceptance
criteria. Nothing in the brief's "Escalate when" came up: the Vulkan path keeps pixel-identical output without any
change to the renderer's frame loop, no `ui/` screen needs more than `active_renderer()` gives, and every action the
frontend route uses (`pad`, `shot`) has a pad-level meaning.

Changed:
- `patches/0010-shell-seam.patch` (new, 3030 lines: 1576 added, 608 removed). Files under `vendor/portablekit/`:
  - `host/shell/shell.hpp`, `shell.cpp` (new, system layer). `host::Shell` with the four groups of 8.1, plus
    `ShellConfig`, `PadState`, `MouseMotion`, `CameraReading` and `kScriptedMouse`. The registry is
    `register_shell`, `make_shell`, `shell_names`, `shell_description`, `ShellRegistration` and `selected_shell()`
    (`<prefix>_SHELL`, vulkan by default).
  - `host/shell/vulkan_shell.hpp`, `vulkan_shell.cpp` (new, renderer). `VulkanShell` owns the `VulkanRenderer` and
    forwards every call to it. Its `present()` uploads a `Cpu` image with `upload_frame` first, then calls
    `renderer.present(address, time)` as before. `host::vulkan_renderer(Shell *)` is the renderer accessor.
  - `host/shell/headless_shell.cpp` (new, system layer, no SDL). `HeadlessShell`; see "The headless shell" in
    docs/ge-backend.md 8.5.
  - `host/shell/sdl_pad.hpp`, `sdl_pad.cpp` (new, renderer). `host::SdlPad` holds the pad sampling, the gamepad
    open/scan/close and the scripted keys, moved out of `VulkanRenderer::Impl`. `Impl` now derives from it, so the
    renderer's code that uses those members did not change.
  - `host/shell/gamepad.hpp`, `gamepad.cpp` (new, system layer). `read_gamepad`, `PadTuning` and `pad_tuning()`,
    moved out of the renderer. They use SDL-free button and axis numbers with SDL's names, which `static_assert`s in
    `sdl_pad.cpp` check against SDL.
  - `host/shell/script_steps.hpp`, `script_steps.cpp` (new, system layer). The input script's grammar, moved out of
    `ui/input_script.cpp` and shared by both readers. The brief asked to say whether the parser was shared: it was
    shared, not rewritten.
  - `host/gpu/vulkan_renderer.hpp`, `.cpp`: moves only. The four types are now aliases, and the pad code, about 260
    lines, is removed. What remains new is the base class and one call in `Impl::sample_pad`.
  - `host/hle/hle_media.cpp`: `media().shell` replaces the renderer, declared before the backend. Also
    `active_shell()` and `ensure_shell_and_backend()`. `present_frame` calls `shell->present(image, address, time)`
    and does the rest through the interface. sceCtrl samples the shell's pad. `active_renderer()` returns the
    renderer only under the Vulkan shell.
  - `host/ui/layer.hpp`, `layer.cpp`, `ui.hpp`, `menu.cpp`, `input_script.cpp`, `input_script.hpp`, `text_input.cpp`,
    `file_browser.cpp`, `widgets.cpp`, `texture_pack_screen.cpp`, `setup_screens.cpp`:
    - The interface uses `Layer::attach(host::Shell &)` and `Layer::shell()`. `attach` refuses a shell without a
      window.
    - The menu's resolution, texture filter and texture pack rows, and the texture pack screen, reach the renderer
      through `active_renderer()`. Under another shell those rows are left out.
    - The setup screens test `Layer::get().attached()`.
  - `cmake/PortableKit.cmake`: the six new sources.
  - `host/camera_probe.cpp`: unchanged. The `gpu::CameraReading` alias and `active_renderer()` still serve it.
- `patches/README.md`: the 0010 row.
- `README.md`: a `PURE_SHELL` row, and the headless shell's script support in the `PURE_INPUT_SCRIPT`,
  `PURE_SCREENSHOT_DIR` and `--script` rows.
- `docs/ge-backend.md`: section 8.5, "What landed". It covers the files, the interface as landed and how it differs
  from 8.1, the selection table, the headless shell and the numbers.
- Commits: 8d34aa5 (the seam) and the Result commit.

Differences from 8.1 (details in 8.5):
- `ShellConfig` is `{title, capture_frame}`, with an empty title meaning the shell's default.
  - `default_window_title()` needs the build-label header, which `portablekit_host_check` does not see. It therefore
    stays in the renderer, and so does `RendererConfig`.
  - `capture_frame` is how a shell without a window takes a picture for `capture_window()`: the HLE passes in the
    backend's `capture_frame`.
- `present()` takes `moment` without a default argument.
- The kernel's idle and poll hooks are set only for a shell with a window.

Numbers:
- `tools/frame_regress.sh`, three runs: before on c394d8b, after on the patched tree, and the Verify run on 8d34aa5.
  They took 7m 8s, 7m 8s and 7m 7s.

  | Scene | Before | After | Verify | Captures vs before, `imgdiff.py --tol 0` |
  |---|---|---|---|---|
  | lang | 0.0544 | 0.0544 | 0.0544 | identical in both (0 of 522240 px) |
  | title | 0.0302 | 0.0302 | 0.0302 | identical in both |
  | profile | 0.0543 | 0.0543 | 0.0543 | identical in both |
  | main_menu | 0.0331 | 0.0331 | 0.0331 | identical in both |
  | race_hud | 0.0672 | 0.0672 | 0.0672 | identical in both |

- Headless frontend route (acceptance 2):
  - 2200 frames in 115.1 s (Verify run), with 20643 draws submitted. That is 19 frames a second, the pace 8.4
    expects.
  - Every script step ran at its frame: `[script] frame 690: shot lang`, 700, 1600, 1640, 1650, 1750 and 1800
    `pad start`, then 2100 `shot profile`.
  - With `PURE_TRACE_PAD=1` the presses show up as `[pad] buttons 0x4000` (Cross) and `0x8` (Start).
  - After Start, the game opens `Movies/Profile_part1.PMF`. The events come in the same order as in the windowed
    suite run's `frontend.log`.
- Acceptance 3: the same run with `--shots out/026/headless_shots` printed the four `[script] frame N: shot NAME`
  lines. It wrote `lang`, `notice`, `title` and `profile`, each a black 480x272 BMP plus PNG.
- Acceptance 4: `tools/patches.sh check` printed "ok: 10 patch(es) reproduce vendor/portablekit at 8b0c3fe".
- Other paths, checked with short runs:

  | Setting | Result |
  |---|---|
  | null backend in the Vulkan window | the uploaded image is shown, and a `shot` of it is uniform black |
  | `PURE_SHELL=bogus` | falls back to vulkan and prints the registered names |
  | `PURE_SHELL=headless` with the Vulkan backend | prints that nothing is drawn |
  | `PURE_NO_RENDER=1` with the Vulkan backend | prints "Renderer: disabled", as before |
  | headless with `PURE_INPUT_LIVE` | lines appended mid-run were read at frame 290; `pad start` pressed Start; `key` was reported once as ignored; `quit` stopped the run ("quit from the input script") |

- Without a renderer: the system-layer sources (`shell.cpp`, `gamepad.cpp`, `script_steps.cpp`,
  `headless_shell.cpp`, `hle_media.cpp`) pass a syntax check with `PORTABLEKIT_HAS_RENDERER` undefined and with no
  SDL or generated-version include paths. My files give no warnings under `-Wall -Wextra`.

Verify output (`tools/verify_task.sh 026`, exit 0; the suite's table is quoted above, and the tail is the null
run's log as run_boot echoes it):
```
  0xd9 x1 first=0x0
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
[render] null backend: 2200 frames, 20643 draws submitted, 0 block transfers, 0 uploads in 115.122 s
[run_boot] exit 0 after 115.5s, 2538 lines
verify 026: PASS
```

Open questions:
1. A headless run is paced to real time when `PURE_NO_RENDER` is left unset.
   - `Kernel::pace_to_real_time` decides on `NO_RENDER` alone, and I did not touch it.
   - So `PURE_SHELL=headless PURE_GE_BACKEND=null` without `NO_RENDER` ran 1200 frames in 39.6 s, about 30 frames a
     second. The Verify's `NO_RENDER=` run does 19.
   - Until patch 0011, a headless route is about 1.6 times faster without `NO_RENDER`.
   - Should a headless route drop `NO_RENDER`, or should the pacing check ask the shell?
2. `shot` without `PURE_SCREENSHOT_DIR` writes to `./NAME.bmp`, the same as in a window.
   - The Verify line sets no `PURE_SCREENSHOT_DIR`, so each Verify run leaves `lang.bmp`, `notice.bmp`, `title.bmp`
     and `profile.bmp` in the repo root. They are not git-ignored. I deleted mine.
   - Two possible fixes: add `--shots out/026/headless_shots` to the Verify line, or add `*.bmp` to `.gitignore`.
3. `tools/run_boot.py --script` implies `--window`, so it leaves audio on. A headless-shell run through it plays
   sound. A `--shell headless` flag in run_boot could set `PURE_SHELL`, `PURE_GE_BACKEND=null`,
   `PURE_NO_RENDER=` and `PURE_NO_AUDIO=1` together. `tools/` was outside this brief.
4. `Profile_part1` appears in an `[io] open ... Profile_part1.PMF` line, not in a `[mpeg]` line: the MPEG trace
   prints no file names. The Verify's `grep` reads the whole log, so it passes either way. The same line appears in
   the windowed log.
5. For task 027 (the Metal shell):
   - `Layer::attach` still uses `ImGui_ImplSDL3_InitForVulkan`.
   - `gpu::default_window_title()` lives in `vulkan_renderer.cpp`.
   - The menu leaves out the resolution, texture filter and texture pack rows under any non-Vulkan shell.
   - `SdlPad` is ready to share. A MetalShell can derive from it or hold one, and call `sample()` with its own
     pointer and touch state.
6. The headless shell copies one quirk of SDL's virtual gamepad so that both shells agree: a trigger set with
   `axis lefttrigger 0` reads as half pressed (0.5 > 0.25), so L is held. No route uses trigger axes.
7. `hle_common.hpp` still says "The renderer owns the window" above `active_renderer()`. That file was outside "May
   touch", so the stale comment stays.
8. `vulkan_renderer(Shell *)` uses a `dynamic_cast`, the first in the framework. RTTI is on in the build.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
