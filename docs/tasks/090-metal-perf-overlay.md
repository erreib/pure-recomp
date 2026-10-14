# 090: The performance overlay on the Metal shell

Milestone: menu refinements | Branch: task/090-metal-perf-overlay | Status: OPEN

## Goal
The Esc menu's Performance row and its F3 toggle work on the Metal shell: the framework's overlay (fps, the game's
rate, frame times and a graph of recent frames, drawn by `perf::draw_overlay` into a 196x72 image) appears in the
window's top-left corner as it does on the Vulkan path, so a player can see 120 against 60 (E8) rather than guess.
Today the Metal shell answers `supports_perf_overlay()` false and the menu hides the row and the F3 line.

## Read first
- vendor/portablekit/host/perf/perf_overlay.hpp and .cpp (`draw_overlay`, `kOverlayWidth`/`kOverlayHeight`,
  `overlay_scale`), perf/frame_stats.hpp ("cheap enough to collect all the time": the numbers are there without
  `PURE_PERF`)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `set_perf_overlay` (about line 5817), the overlay's staging
  (about lines 2999 to 3036: `draw_overlay` once a frame into `overlay_pixels`, uploaded) and its compositing into
  the presented picture and the window capture (about line 8896: an integer scale from the height, an inset of
  4 x scale, copied opaquely, no blending)
- vendor/portablekit/host/ui/menu.cpp: the Performance row (about line 595: Off / Overlay / Overlay and log / Log
  only, `shell().set_perf_overlay(perf::options().overlay)`), the F3 line (about 1016), the F3 key handling
- src/host/metal_shell.mm: `supports_perf_overlay`, `set_perf_overlay` (about lines 504 to 511), the present pass
  (about lines 752 to 776: the picture drawn by `picture_pipeline_` as one triangle over `viewport_for`'s
  viewport with `sampler_for`, then ImGui), the window capture (`capture_path_`, what a `shot` writes: the
  drawable), `shutdown_ui` and the shell's shutdown order
- tools/menu_check.sh (the rows asserted per shell: Video's "Performance" and Controls' "F3" are Vulkan-only
  today), docs/controls.md "Rows the menu leaves out", docs/metal-backend.md "The Metal shell" (what it leaves
  out), docs/verification.md's tools table; CLAUDE.md

## Deliverable
1. src/host/metal_shell.mm: `supports_perf_overlay()` true; `set_perf_overlay(bool)` keeps the flag. In the
   present pass, when the flag is set and a picture is drawn: `perf::draw_overlay` into a CPU buffer once per
   present, written into a 196x72 RGBA8 `MTLTexture` (shared storage, one texture reused; the overlay's pixel
   order is red in the low byte, so pick the pixel format that reads it as is, `MTLPixelFormatRGBA8Unorm`), and
   drawn with the picture pipeline and the nearest sampler into a viewport at the drawable's top-left: inset
   4 x scale, size 196 x scale by 72 x scale, scale = `perf::overlay_scale(drawable height)`; opaque, over the
   picture, before ImGui (so the menu draws over it). A window capture (`shot`) shows it, since it captures the
   drawable. Nothing is drawn when the flag is off: the suite's window captures stay as they are.
2. tools/menu_check.sh: the Metal shell's Video rows gain "Performance" after "Fast loading" and its Controls rows
   gain "F3" after "Esc", as the Vulkan lists have them (read the dump to place them exactly).
3. A check, `tools/overlay_check.sh`: a Metal window run of the race route (`tools/run_boot.py --shell metal
   --backend metal`, paced from 5716 as the suite does, a scratch data directory) with `video.performance=overlay`
   in its settings.ini and one without, a `shot` at flip 6016 in each: PASS when the overlay's rectangle (the
   top-left 4 x scale + 196 x scale by 72 x scale of the capture) differs from the same rectangle of the other run
   in at least 20% of its pixels at tol 24, holds non-black pixels, and the rest of the frame (the capture with
   the rectangle masked) matches the other run within the race_hud scene's limit; the HUD found in both. Print
   the figures. About 2 minutes. Also `tools/menu_check.sh` PASS on both shells.
4. Docs: docs/controls.md ("Rows the menu leaves out": Performance and F3 no longer left out on Metal; the Esc
   menu's description if it names the overlay), docs/metal-backend.md ("The Metal shell": the overlay drawn,
   how), docs/status.md (a menu-refinements bullet: the folder buttons of patch 0029-windows-file-url and this),
   docs/verification.md (the check's row), README.md (the Esc menu section's Video line: "Performance" shows the
   frame rate and frame times; F3 toggles it) and docs/developing.md's tool row.

## Acceptance criteria
- [ ] `tools/overlay_check.sh` PASS with its figures in the Result.
- [ ] `tools/menu_check.sh` PASS on both shells with the updated rows; `tools/frame_regress.sh` 18/18 and
      `--shell metal --backend metal` 7/7 unchanged (the flag off).
- [ ] `python3 tools/docs_check.py` PASS. No vendor change.
- [ ] By hand (say what you saw in a capture): a race in the Metal window with the Performance row at Overlay and
      Display rate at Display on this Mac shows fps 120 and the game at 120 in the overlay; at Original, 60.

## Verify
`tools/overlay_check.sh && tools/menu_check.sh && tools/frame_regress.sh && python3 tools/docs_check.py`

## May touch
- src/host/metal_shell.mm, tools/overlay_check.sh (new), tools/menu_check.sh, tools/purelib/port.py (a helper only
  if needed)
- docs/controls.md, docs/metal-backend.md, docs/status.md, docs/verification.md, README.md, docs/developing.md,
  docs/tasks/090-metal-perf-overlay.md

## Must not touch
- vendor/ (the overlay's drawing and the menu are the framework's and stay), vendor/portablekit/include/psprecomp/,
  src/gpu/, src/profile/, config/, generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
35

## Escalate when
- The overlay's numbers are empty on Metal (the perf stats need a renderer hook the Metal path lacks): say which
  figures are missing and where the Vulkan renderer feeds them.
- The picture pipeline cannot draw a second texture into a sub-viewport without a new pipeline (then a small
  second pipeline is fine; say so), or the shared texture's writes race the GPU (then double-buffer it; say so).
- Anything would touch vendor/.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
