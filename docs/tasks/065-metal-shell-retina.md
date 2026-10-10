# 065: The Metal shell draws at the display's pixels (E3, step 1)

Milestone: E3 (D-015) | Branch: task/065-metal-shell-retina | Status: OPEN

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
