# 090: The performance overlay on the Metal shell

Milestone: menu refinements | Branch: task/090-metal-perf-overlay | Status: MERGED

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

**Status: DONE.** The Metal shell draws the framework's performance overlay. The Esc menu's Performance row and F3
work on the Metal shell, and `tools/menu_check.sh` lists both on both shells. Verify passes. No vendor change.

**How it is drawn** (src/host/metal_shell.mm):
- `supports_perf_overlay()` is true, and `set_perf_overlay(bool)` keeps the flag. The flag starts from
  `perf::options().overlay` in `initialize`, since the menu calls `set_perf_overlay` only when the row changes, as
  the Vulkan renderer does at creation.
- F3 is handled in `pump_events` after the interface's event hook, as in the Vulkan renderer's pump.
- In `draw()`, on a game present (`present()`, not `present_ui`), when the flag is set and a picture is drawn:
  - `perf::draw_overlay` fills a CPU buffer.
  - The buffer goes by `replaceRegion` into a 196x72 `MTLPixelFormatRGBA8Unorm` texture in shared storage.
  - The picture's own pipeline draws it with `nearest_` into a viewport at the drawable's top-left corner: inset
    4 x scale, 196 x scale by 72 x scale, scale = `perf::overlay_scale(drawable height)`. That is 3 in a 1920x1088
    drawable, so the rectangle is 588x216 at 12,12.
  - It is opaque, drawn after the picture and before ImGui, and timed with `perf::add_overlay_time`.
- The window capture copies the drawable, so a `shot` shows the overlay. With the flag off nothing is drawn or
  allocated.

**Escalation conditions:**
- The numbers are there. `end_frame` and the time split come from hle_media.cpp, and the shell already called
  `set_display_info`, so no renderer hook was missing.
- No second pipeline was needed.
- The texture is double-buffered, as the brief allows. With one texture, the CPU's `replaceRegion` could rewrite
  pixels that a present still queued on a GPU running behind is sampling. Metal does not order CPU writes to shared
  memory against GPU reads. So the shell has two textures, used in turn (`kOverlaySlots`). Before a slot is
  rewritten, the shell waits for the command buffer that last sampled it, which in practice has finished long before.

**By hand.** What the captures showed, read from each capture's top-left rectangle. The race_hud route in the Metal
window ran with `video.performance=overlay`, paced from 5716, on a fresh stick, with the shot well into the race:
- Display rate at Display (`PURE_DISPLAY_RATE=1`, `[pure] display rate: 120 Hz (8333 us a vblank)`), flip 7900:
  `FPS 120.0 GAME 120.1 SPD 100%`, `FRAME 8.3 MAX 10.4 MS`, `GUEST 1.3 RENDER 3.9 WAIT 3.1`, `FIFO 120HZ 1920X1088`.
- At Original (`PURE_DISPLAY_RATE=0`), flip 6900: `FPS 59.9 GAME 59.9 SPD 100%`, `FRAME 16.7 MAX 18.3 MS`.
- F3: with `video.performance=off`, `key F3` at 5990 showed the overlay at 6016, and `key F3` at 6020 hid it again
  at 6046 (the CURRENT label and lap clock visible again).
- The menu row: `key Escape`, eight Downs and a Right set the Video tab's Performance row to Overlay (the menu's
  shot shows the row and its description). settings.ini then held `video.performance=overlay`, and the race after
  Esc showed the overlay.

### Changed
- src/host/metal_shell.mm: the overlay (`draw_overlay`, two shared textures, the flag, F3, `supports_perf_overlay`
  true); the header comment's `overlay` and `captures` lines and the menu-capability comment.
- tools/overlay_check.sh (new): the check, described in its header.
- tools/menu_check.sh: Metal's Video rows gain "Performance" after "Fast loading" and its Controls rows gain "F3"
  after "Esc", as the Vulkan lists have them; header comments updated.
- docs/controls.md: the F3 sentence, the Controls tab's order, and "Rows the menu leaves out".
- docs/metal-backend.md: "The Metal shell" gets a Performance overlay row; the Captures row says the overlay is
  included; "What it leaves out" and the capability sentence are updated; "What is not done yet" loses the
  performance overlay, and also the stale "the Fill aspect" (done since task 086) in the same line.
- docs/status.md: the folder-buttons bullet becomes a "Menu refinements" bullet holding patch 0029-windows-file-url
  and this task.
- docs/verification.md: the check's row, the menu check's row, and the Metal shell row of "Which path for which
  change".
- README.md: the Esc menu's Video line (Performance; F3 shows or hides it).
- docs/developing.md: the tool's row.
- docs/tasks/090-metal-perf-overlay.md: this Result.

Also run, outside Verify:
- `tools/menu_check.sh --shell vulkan` PASS (Video 21, Controls 37).
- `tools/frame_regress.sh --shell metal --backend metal` 7/7: title 0.0002, main_menu 0.0106, race_hud 0.0149,
  tt_hud 0.0089, fp_hud 0.0115, zone_hud 0.0122, zone_change 0.0369. tt_hud came back at 0.0112 on a rerun of the
  same build (race_hud 0.0148), so the 0.0089 is the window's run-to-run wobble, not this change.
- `tools/hud_check.sh` 61 of 61.
- `python3 tools/controls_check.py` OK.

overlay_check's figures in the Verify run: the rectangle is 0.9637 changed at tol 24; 29664 of its pixels (0.2336)
are not black; the rest of the capture is 0.0000 apart at tol 32. The HUD: off lane CURRENT 2000 and LAP 688 yellow;
overlay lane CURRENT 0 (88% of its region is under the rectangle) and LAP 688. The overlay reads
`FPS 60.0 GAME 59.9 SPD 100% | FRAME 16.7 MAX 19.4 MS | GUEST 2.1 RENDER 3.4 WAIT 11.1 | FIFO 120HZ 1920X1088`, and all
of its 3x3 blocks are one colour. 20 s in all.

### Verify output (last 20 lines)
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
docs_check: 35 files, 0 findings: PASS
```

### Open questions
- **The brief's "the HUD found in both" cannot hold as written.** The overlay covers the HUD's CURRENT label: 88% of
  `tools/hud_check.py`'s CURRENT region lies under the rectangle, and the label reads 0 yellow there. The Vulkan
  renderer's 196x72 at 4,4 in its 960x544 window covers it the same way. So the check requires both labels in the
  lane without the overlay, and in the overlay lane only the labels outside the rectangle (LAP), printing CURRENT's
  count and how much of it is covered. The masked comparison (c) shows the rest of the HUD unchanged.
- **The overlay is drawn on game presents only, not on `present_ui`.** This is the Vulkan renderer's rule
  (`submit_and_present`'s `game_frame`): behind the paused menu the overlay is gone and comes back when the menu
  closes. The brief's "when a picture is drawn" could also be read to include the paused menu's held picture. Say if
  the Metal shell should draw it there too (one argument).
- The Metal shell times no GPU work, so the second line is `FRAME x MAX y MS` with no `GPU` figure, the framework's
  form when `gpu_valid` is false.
- The by-hand runs set the rate with `PURE_DISPLAY_RATE`, which the row then shows as "Set by PURE_DISPLAY_RATE",
  instead of driving the Display rate row itself. The overlay setting was driven through the menu row in a separate
  run.


## Review
Merged 9b97eb9 into batch/m2 (2026-10-14). Verify rerun on the merge from the main checkout (out/090_gate.log):
overlay_check PASS, menu_check PASS, the headless suite 18/18, docs_check PASS; then the Metal window suite 7/7
and hud_check 61 of 61. Spot-read: src/host/metal_shell.mm (the two shared textures used in turn with the wait
before a rewrite, the viewport at the inset, F3 in the pump), tools/overlay_check.sh. The worker's reading of the
brief's "HUD found in both" is right: the overlay covers the CURRENT label on Vulkan too, so the check asks for the
labels outside the rectangle. The overlay on game presents only, as the Vulkan renderer does, stands. Open: no GPU
figure on Metal (the shell times no GPU work).
