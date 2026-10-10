# 065: The Metal shell draws at the display's pixels (E3, step 1)

Milestone: E3 (D-015) | Branch: task/065-metal-shell-retina | Status: MERGED (3c674e4, 2026-10-10)

## Goal
On a Retina Mac the Metal shell's layer is 960x544 for a 960x544-point window and the system upscales it, so the game
is shown blurred at twice its size however sharp the backend's picture is (`[shell] metal: ... window 960x544` on a
3024x1964 panel). After this task the drawable is the window's size in pixels, the picture is scaled to it by the
shell's own filter (sharp or smooth), fullscreen uses every pixel of the panel, and the window-size setting still
means points.

## Read first
- CLAUDE.md, docs/decisions.md (D-015), docs/metal-backend.md ("The Metal shell": Present, Scaling filter, Captures,
  The window), docs/verification.md ("Which path for which change")
- src/host/metal_shell.mm (initialize: the SDL window flags and the layer; `viewport_for`; `present`; the capture
  path `capture_window`; `set_window_scale`, `set_fullscreen`; `update_display_info`)
- SDL3's high-pixel-density window flag and `SDL_GetWindowSizeInPixels` / `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`
  (the SDL headers under build/ or the framework's SDL3 checkout; no copying)
- tools/frame_regress.sh (the `--shell metal` column is a window capture resized to 480x272), tools/hud_check.sh

## Deliverable
1. `SDL_WINDOW_HIGH_PIXEL_DENSITY` on the window; the layer's `drawableSize` set from `SDL_GetWindowSizeInPixels` at
   creation and on every pixel-size change (resize, fullscreen, a move between displays); `layer_.contentsScale` as
   the window's pixel density. The present's viewport (`viewport_for`) in drawable pixels, as it is, so the
   letterbox and the Stretch aspect are unchanged in proportion.
2. The scaling filter's rule ("nearest whenever the picture covers a whole multiple of 480x272") judged in drawable
   pixels: on this Mac the default window is 1920x1088 pixels, a whole 4x of a 480x272 picture, so it stays
   nearest; a 2x-scale backend picture (later, task 066) at 1920x1088 is a whole 2x.
3. The `[shell] metal:` start line names both: `window 960x544 points, 1920x1088 pixels, 2x`.
4. `capture_window` writes the drawable's size (the suite resizes to 480x272 with nearest neighbour; the `--shell
   metal` column's measured values may move by the resize and are re-baselined if they do, within the limits).
5. docs/metal-backend.md "The Metal shell": the drawable rule, one paragraph; docs/verification.md if a measured
   value moves.

## Acceptance criteria
- [ ] A windowed run on this Mac logs `1920x1088 pixels` for the default window and the full panel's pixels in
      fullscreen (`PURE_FULLSCREEN=1` or the setting; say what it logged).
- [ ] `tools/frame_regress.sh --shell metal --backend metal` 18/18 (re-baseline any moved value with three runs and
      say by how much); `tools/hud_check.sh` 61/61; the headless suite unchanged (the shell is not in it).
- [ ] A capture's pixels: the window capture of the title scene at 1920x1088, downsampled by 2 (every other pixel), is
      pixel-identical to the backend's own 480x272 capture upsampled by 2 nearest (the shell adds nothing but the
      interface, which the title has none of). State the count.
- [ ] No change to the Vulkan shell, the backend, or the settings' keys.

## Verify
`tools/build.sh profile && tools/frame_regress.sh && tools/frame_regress.sh --shell metal --backend metal`

## May touch
- src/host/metal_shell.mm, src/gpu/metal_shell.hpp, docs/metal-backend.md ("The Metal shell"), docs/verification.md
  (a measured value), README.md (if a switch is added, none expected)

## Must not touch
- vendor/, patches/, src/gpu/metal_*.mm, src/profile/, tools/, config/, ref/, the settings' keys and defaults

## Estimated turns
30

## Escalate when
SDL3 as built here cannot make a high-density Metal window (report the version and what `SDL_GetWindowSizeInPixels`
returns); the interface (ImGui) draws at the wrong scale after the change and the fix needs the framework's layer
code (host/ui/layer.cpp): report, do not patch vendor.

## Result
Status: DONE

Changed (branch task/065-metal-shell-retina from batch/m2 7f4afce, two commits, then this Result):
- 029e408 src/host/metal_shell.mm:
  - `SDL_WINDOW_HIGH_PIXEL_DENSITY` on the window.
  - `update_drawable_size()` sets the layer's `drawableSize` from `SDL_GetWindowSizeInPixels` and its
    `contentsScale` from `SDL_GetWindowPixelDensity`. It runs at creation, and on `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`
    and `SDL_EVENT_WINDOW_DISPLAY_CHANGED` (each followed by `update_display_info`). A new drawable size after
    start-up is logged once, as `[shell] metal: window ...`.
  - The start line is now `[shell] metal: Apple M4 Pro, window 960x544 points, 1920x1088 pixels, 2x, vsync`.
  - `viewport_for`, `sampler_for` and the capture keep their code: they already worked in the drawable's pixels.
    `sampler_for`'s comment now says so.
- 422ffe4 docs/metal-backend.md, "The Metal shell":
  - a new subsection, "The drawable" (one paragraph);
  - the Window, Scaling filter and Captures rows and "The scaling filter" paragraph now give sizes in drawable pixels.
- src/gpu/metal_shell.hpp, docs/verification.md and README.md are untouched (see Open questions).

Acceptance:
- The default window logs `[shell] metal: Apple M4 Pro, window 960x544 points, 1920x1088 pixels, 2x, vsync`.
- Full screen (there is no `PURE_FULLSCREEN` variable; I used `video.fullscreen=1` in a scratch data directory's
  settings.ini):
  - At creation, mid-transition, it logs `window 1512x872 points, 3024x1744 pixels, 2x`. Then it logs
    `[shell] metal: window 1512x945 points, 3024x1890 pixels, 2x`, and that run's shots are 3024x1890.
  - That is the panel's 3024x1964 less 74 pixels (37 points): macOS places a full-screen window below the camera
    housing.
  - The picture, letterboxed at Original, is 3024x1714 either way and does not reach that strip. The full-screen menu
    shot showed the menu at its point size over the letterboxed picture.
- `tools/frame_regress.sh` headless: 18/18. Every value is as before; zone_change is 0.0369, as in every run since
  task 049.
- `--shell metal --backend metal`: 18/18, with 1920x1088 window captures. zone_change moved by -0.0329 (0.0024
  against 0.0353), and the suite flagged it. The resize did not cause this move:
  - Three window runs of zone_change scored 0.0024, 0.0148 and 0.0423 (median 0.0148, -0.0205). The last window run
    before this change (main checkout, commit b92537a, today 14:19) scored 0.0416.
  - The window's race frames differ from the headless ones in content, not at edges: the camera and the ship have
    moved. In half-size pixels: zone_change 213872, race_hud 87716, tt_hud 49468, zone_hud 9392. Every
    difference covers whole 4x4 blocks.
  - That is the paced race wobble the scene's comment already describes.
  - Not re-baselined. The metal column is the deterministic headless value, the SCENES table lives in tools/ (Must
    not touch), and no value moved by the resize.
- Capture pixels: the title window capture (1920x1088), downsampled by 2, against the backend's own 480x272 capture
  upsampled by 2: 0 of 522240 pixels differ. Every window pixel against the texel it covers (4x): 0 of 2088960.
  The same zero holds for 14 scenes: the 13 non-race scenes and fp_hud.
- `tools/hud_check.sh`: 61 of 61 shots have the HUD.
- The interface: `tools/menu_check.sh` PASS. The 1920x1088 menu shot shows the panel at the same share of the window
  (about 7% to 93% of its width) as the main checkout's 960x544 shot, with its glyphs rasterised at 2x. ImGui's SDL3
  backend gives the size in points and the density as the framebuffer scale, so host/ui/layer.cpp was not needed.
- The diff is only src/host/metal_shell.mm and docs/metal-backend.md: no change to the Vulkan shell, the backend or
  the settings' keys.

Verify output (last 20 lines; the Verify line ran on the final code, before the docs edits):
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0152   0.10   32    0.0149 +0.0003  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0089   0.12   32    0.0112 -0.0023  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0024   0.10   32    0.0353 -0.0329  PASS

moved more than 0.03 from the metal measured value: zone_change (something changed; docs/verification.md)
frame regression: PASS, 18/18 scenes pass, shell metal, backend metal (19m 51s)
```

Open questions:
- Some text still says 960x544 for the Metal window, in files this task could not edit:
  - README.md's `PURE_SHELL` row: "`shot` captures (the window, 960x544 at the default 2x)" and "Prints
    `[shell] metal: DEVICE, window WxH, vsync`";
  - docs/verification.md: "a window's 960x544 capture is reduced by nearest neighbour";
  - tools/frame_regress.sh's header ("960x544 in a window"), tools/hud_check.py's docstring, and tools/bundle.sh's
    finder check ("the window's picture, 960x544").

  The brief lets this task edit README.md only for a new switch and verification.md only for a measured value, and
  tools/ is under Must not touch, so they are left as they were. The suite's reduction and hud_check.py's region
  scaling work at any size.
- zone_change in the window ranged from 0.0024 to 0.0423 over three runs (0.0416 before this change). The ">0.03
  moved" line will fire on Metal window runs at random. Should the table say that this scene's window score
  wobbles?
- In full screen the camera-housing strip stays black, by macOS's placement. Covering it (full screen without
  Spaces, or ignoring the safe area) would help only Stretch (74 more rows) and would put the menu's top beside the
  camera, so it is not done.
- Not tested on a 1x display (there is no external display here). The code takes the density SDL reports, so the
  drawable there is the window's points.

## Review
Verify rerun: from the main checkout after the merge, 2026-10-10: PASS (headless 18/18; `--shell metal --backend
metal` 18/18 with 1920x1088 captures, zone_change's window wobble flagged as the worker measured);
`tools/hud_check.sh` 61/61; `tools/menu_check.sh` PASS, the interface at its point size over the 2x drawable.
Spot-read: the density flag, `update_drawable_size` (pixel size and contents scale, at creation and on the
pixel-size and display-changed events), the start line; `viewport_for`, the samplers and the capture untouched,
as they already worked in drawable pixels. The 0-of-2088960 capture proof is the right one.
Merged: `git merge --no-ff` into batch/m2, 3c674e4; the stale 960x544 texts in README.md, docs/verification.md and
three tool headers updated at the merge (2e1e4ad), with a note on the race scenes' window wobble.
Notes: full screen lands below the camera housing (3024x1890 of 3024x1964), by macOS's placement, and the picture
never reaches that strip: left as is. Not tested on a 1x display (none here); the code takes SDL's density.
