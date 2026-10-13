# 086: Fill on the Metal shell (E2, the view at the window's shape on the Mac's default renderer)

Milestone: E2 | Branch: task/086-metal-fill | Status: OPEN

## Goal
The Mac plays on the Metal shell and backend (D-008), which have no Fill: the Aspect ratio row offers Original and
Stretch, and `game_aspect()` always says 480:272, so task 084's hook never widens the view there. This task gives the
Metal path what the Vulkan renderer has: under Fill the screen-wide targets take the window's shape, the game is told
that shape at each flip (the hook then draws the 3D view at it), the 2D interface is pulled in to square pixels about
the centre (through-mode draws and orthographic unlit ones, the rule tasks 073 and 085 state), and the shell shows the
whole target. At Original and Stretch nothing changes: every existing check keeps its figures.

## Read first
- docs/decisions.md D-020 (points 1, 3, 4); docs/tasks/084-ultrawide-view.md and 085-vulkan-orthographic-fit.md (the
  Results, if 085 has one by the time you start; else its brief for the rule)
- docs/metal-backend.md (the whole "Internal scale" story, D-015: screen-wide targets at S, narrower ones at 1x;
  "The Metal shell"; "Texture detail"), docs/ge-backend.md section 8 (the shell seam: `game_aspect`, `set_aspect`,
  `supports_aspect`, `target_size`, `set_internal_scale`)
- src/gpu/metal_backend.hpp and .mm (`scale_`, `scale_for`, `apply_scale`, `change_scale`, the start line and
  `scale_report`), src/gpu/metal_targets.mm (`target->scale` at creation, `change_scale`, the pixel read-back's
  centre sampling about line 302, `store_depth`'s about line 379, the CPU picture upload about line 431),
  src/gpu/metal_draw.mm (the viewport from `target.width()`/`height()` about line 491, the scissor scaled about
  line 518, `sample_target`'s `uv_remap` about line 400, the texture-detail level scaling about lines 440 to 449,
  the 2D rule about lines 418 to 432), src/gpu/metal_types.hpp (`Target`, `VertexUniforms`, `FragmentUniforms`),
  src/gpu/shaders/ge.metal (the vertex function: where through-mode and transformed positions become clip space)
- src/host/metal_shell.mm (`game_aspect`, `set_aspect`, `supports_aspect`, `viewport_for`, `sampler_for`,
  `drawable_size`, the `[shell] metal` line), src/gpu/metal_device.mm/.hpp if the drawable size lives there
- vendor/portablekit/host/gpu/vulkan_renderer.cpp `wanted_target_extent` and `interface_fit` (the shape and fit
  arithmetic to match: lines per step 272, width = lines x shape, the fit = the square scale over each axis's),
  host/camera/camera_driver.hpp (the hook is called with the shell's `game_aspect()`)
- tools/aspect_check.sh (task 084, and 085's bars if merged), tools/menu_check.sh (the Metal shell's rows: the
  Aspect ratio row's choices are asserted there), tools/frame_regress.sh, tools/metal_check.sh, tools/hud_check.sh,
  tools/texture_check.sh (the checks a Metal backend change must keep), docs/verification.md "Which path for which
  change"; CLAUDE.md

## Deliverable
1. The backend: a screen-wide target under Fill is `lines` high (272 x S, S the internal scale as today, Auto from
   the drawable's height) and `round(lines x shape)` wide, `shape` the drawable's width over height clamped as the
   Vulkan renderer clamps it; narrower targets stay 480x272 (D-015). `Target` carries its two scales (the vertical
   one stays the integer S the mip and detail arithmetic uses; the horizontal one a float), and every place that
   took `target.scale` as both takes the right one: the viewport and scissor (round the x extents), `uv_remap`
   (already a ratio of sizes), the texture-detail level bias (keep the vertical S; say so in a comment), the pixel
   read-back and `store_depth` (the centre of each guest pixel's block at x (x + 0.5) S_x, y (y + 0.5) S_y, nearest),
   the CPU picture upload (each picture pixel an S_x x S_y block, or a resample; the movies and loading pictures
   have the PSP's shape and under Fill keep it with bars beside, as the Vulkan renderer does for a movie, so this
   path may draw the picture into the centred 480/272-shaped part of the target). The shape is read at the frame
   boundary as the scale is (`apply_scale`): a change retires the screen-wide targets like a scale change.
   `target_size()` reports the real size. The start line and `scale_report` say the shape (`... at 2.333:1` or the
   target size) when it is not the PSP's.
2. The 2D fit: when the shown target's shape is not 480:272, a through-mode draw into it, and a transformed
   orthographic unlit one, not clear mode and not sampling a rendered picture, narrower than 470/480 of the screen,
   is drawn scaled about the screen's centre by `fit_x`, `fit_y` (the square scale over each axis's). Do it in clip
   space in the vertex function through a uniform (two floats) rather than on the CPU, so both kinds of draw share
   one path; screen-wide draws stay spread (their x extent, measured where the draw's vertices are already on the
   CPU for through mode and through the transform otherwise). Match task 085's Vulkan rule so a capture of each
   path agrees.
3. The shell: `supports_aspect(Fill)` true; `set_aspect` keeps Fill; `game_aspect()` returns the shown target's
   shape under Fill (the backend's, which the hook needs at each flip) and 480/272 otherwise; `viewport_for` shows
   the whole drawable under Fill (the target already has its shape); `sampler_for` as before. The window's size for
   a check: honour `PURE_WINDOW_SIZE=WxH` at the window's creation as patch 0027 does on Vulkan (shell code, ours).
4. `tools/aspect_check.sh --shell metal`: the same lanes and bars on the Metal shell and backend (default stays
   vulkan so the task 084/085 figures hold; `--shell metal` for this task's). The Metal lane's figures in the Result
   beside the Vulkan ones; they should agree within the usual Metal/Vulkan difference of the suite.
5. `tools/menu_check.sh`: the Metal shell's Aspect ratio row now offers Fill; update what the check asserts and
   docs/controls.md's "Rows the menu leaves out" (Fill is no longer left out on Metal).
6. Docs: docs/metal-backend.md (a "Fill" subsection: the shape, the fit, the read-backs, what stays at 480x272),
   docs/status.md's E2 bullet (closing it for the Mac), docs/verification.md (the check's row), README.md (the
   shell's row and `PURE_WINDOW_SIZE` on Metal), docs/controls.md.

## Acceptance criteria
- [ ] `tools/aspect_check.sh --shell metal` PASS with every bar 084 and 085 define; figures in the Result.
- [ ] `tools/frame_regress.sh` 18/18 and `tools/frame_regress.sh --shell metal --backend metal` 7/7, both unchanged
      to the figures in docs/verification.md's table (Original: nothing changes).
- [ ] `tools/hud_check.sh` 61 of 61; `tools/texture_check.sh` PASS; `tools/metal_check.sh` PASS (the pinned
      recordings replay unchanged); `tools/menu_check.sh` PASS with its updated rows.
- [ ] `python3 tools/docs_check.py` PASS. No vendor change (no new patch).
- [ ] By hand (say what you saw): the app's window dragged to 21:9 with Aspect ratio Fill: a race shows more track
      to each side, the HUD and menus keep their proportions, the lens flare sits on the sun, the bloom looks as at
      Original, a movie keeps its shape with bars beside it.

## Verify
`tools/aspect_check.sh --shell metal && tools/frame_regress.sh && tools/hud_check.sh && tools/menu_check.sh && python3 tools/docs_check.py`

## May touch
- src/gpu/metal_backend.hpp, metal_backend.mm, metal_targets.mm, metal_draw.mm, metal_types.hpp, metal_trace.mm,
  metal_effects.mm, shaders/ge.metal, src/host/metal_shell.mm (and metal_device.* if the drawable size lives there)
- tools/aspect_check.sh (the `--shell metal` lane only; 085 owns the bars), tools/menu_check.sh
- docs/metal-backend.md, docs/status.md, docs/verification.md, docs/controls.md, README.md, docs/tasks/086-metal-fill.md

## Must not touch
- vendor/ (no patch in this task), vendor/portablekit/include/psprecomp/, src/profile/ (the hook is 084's), the
  kernel, config/metal_pipelines.txt unless a new pipeline is needed (then say so), generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
60

## Escalate when
- A read-back or effect cannot be mapped to a non-integer horizontal scale without a visible change at Original (a
  check's figure moves).
- The bloom chain or the lens flare's depth read breaks under Fill (black bloom, flare through walls): report which
  target and which mapping.
- The 2D fit needs a per-draw decision this backend cannot make (a draw whose extent is unknown before the GPU).
- Anything would touch vendor/ or include/psprecomp/.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
