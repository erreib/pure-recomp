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

**Status: DONE.** Verify passes (out/verify_086.txt):
- `aspect_check --shell metal`: PASS on task 084's bars (a) to (d).
- The headless suite: 18/18, every figure as in docs/verification.md.
- hud_check: 61 of 61.
- menu_check: PASS with Fill in the Aspect ratio row.
- docs_check: PASS.

Task 085 has no Result yet, so its bars (e) and (f) are not in this branch's script. I computed them by hand from its brief, on the Metal lane's captures (below). No vendor change: `tools/patches.sh check` still reports 27.

**Changed:**
- Backend: src/gpu/metal_types.hpp, metal_backend.hpp, metal_backend.mm, metal_targets.mm, metal_draw.mm, metal_trace.mm, shaders/ge.metal, metal_device.hpp and metal_device.mm.
- Shell: src/host/metal_shell.mm.
- Tools: tools/aspect_check.sh (the `--shell metal` lane only) and tools/menu_check.sh.
- Docs: docs/metal-backend.md (a new "Fill (task 086)" section, plus the rows it touches), docs/status.md, docs/verification.md, docs/controls.md, README.md and this file.
- Not changed: config/metal_pipelines.txt. No new pipeline was needed: the fit is a uniform.

### What the code does
- **The targets.** Under Fill a screen-wide target is 272S rows by round(272S x shape) columns. S is the internal scale as before, with Auto taken from the drawable's height. The shape is the drawable's, clamped to 1:4 .. 8:1 as the Vulkan renderer clamps it (`extent_for`).
  - `Target` keeps `scale` as the vertical S and gains `columns` and `scale_x()`.
  - Narrower targets stay 480x272.
  - A change of shape is applied in `apply_scale` at `begin_frame` and retires the targets like a scale change.
  - `target_size()` and the start line report the real size: `targets 1269x544 at 2.333:1`.
- **The two scales.** Each path that used one scale now takes the right one per axis:
  - The scissor rounds each axis's edges.
  - `uv_remap` uses `scale_x` across and S down.
  - The mip gradient and the texture-detail shift keep the vertical S, with a comment saying why.
  - Read-backs and `store_depth` take the pixel under each guest pixel's centre, worked out in whole numbers (`centre_of`). At the PSP's shape that is exactly the old block-centre pixel.
  - `upload_frame` keeps the picture's shape, centred with black bars. This game never calls it: every route counts 0 uploads.
- **The game's shape.** At each flip `present_image` publishes the size of the next frame's targets through `pure::metal::set_view_size`. The shell's `game_aspect()` returns that shape under Fill, so the hook sees 2.33272 for a 1260x540 drawable.
- **The 2D fit.** It follows the rule of task 085's brief:
  - Which draws: through mode, or orthographic and unlit; not clear mode; not sampling a target; into a reshaped target at one of the last two displayed addresses; and narrower than 470 of 480 guest pixels. The width is measured on the CPU, through the transform and folded viewport for transformed draws.
  - The fit itself is `VertexUniforms::fit`, applied in `ge_vertex` to clip x and y on both branches. The uniform block grows from 240 to 256 bytes.
  - A fitted draw's scissor is fitted with it, as the Vulkan renderer fits its scissor.
  - `PURE_METAL_LOG` lines end in `fitted`.
- **The shell.**
  - `supports_aspect(Fill)` is true.
  - `set_aspect` keeps Fill for a game that has the view hook, and says so to the backend with `set_fill`.
  - `viewport_for` covers the whole drawable under Fill.
  - `PURE_WINDOW_SIZE=WxH` is read when the window is made, as the drawable's size in pixels: the window becomes W/d x H/d points at pixel density d, so the captures are 1260x540, as the Vulkan window's are.

### Original is unchanged
- **Refactor check.** `tools/refactor_check.sh` from batch/m2, headless at internal scale 1 and at 3 (an odd S, to test the centre arithmetic): 0 differing pixels on all 18 scenes.
  - The exit counts are identical except the ring's "GPU waits" count, which moved on 7 routes. It follows the machine's load: the 085 worker was running games at the same time.
- **Window suite.** `--shell metal --backend metal`: 7/7. fp_hud read 0.0091 once and 0.0116 on a rerun, the paced window's usual swing. The other scenes match the table.
- **Other checks.** texture_check PASS with the documented figures. `tools/gerec/metal_check.sh` PASS. `tools/menu_check.sh --shell vulkan` PASS.

### The aspect check, Metal beside Vulkan (this build, 1260x540)

| Bar | Metal (`--shell metal`) | Vulkan (default lane, HUD still spread before 085) |
|---|---|---|
| (a) between the HUD's bars / whole strip (limit 0.10) | 0.0627 / 0.0469 | 0.0691 / 0.0826 |
| (b) left: variance, apart | 3813.7, 0.6330 | 3884.5, 0.6356 |
| (b) right: variance, apart | 6163.3, 0.5179 | 6222.6, 0.5239 |
| (c) draws over the run at 6016, Original / Fill | 342712 / 343264 | 342712 / 343264 (857 / 858 transformed; the Metal backend prints no `[3d]` line) |
| (d) race camera calls widened: Fill / Original | 275 of 275 / 0 of 273 | 287 of 287 / 0 of 303 |
| 085's (e) by hand: HUD bands, rows 0-40 / 212-272 | 0.0166 / 0.0219 | (085's) |
| 085's (f) by hand: main menu central strip / outer strips | 0.0024 (limit 0.05) / white, not black | (085's) |

- (a) and (b) were the same to the fourth decimal in two runs.
- Metal against Vulkan at tol 32, reduced to 480x272:
  - Original: 0.0000.
  - Fill: 0.0173 between the HUD's bars (Metal's 1269x544 resampled to the window against Vulkan's native 1260x540) and 0.0554 over the frame (the HUD is fitted on Metal only).
- The Metal lane takes about 20 s: the pipelines are pre-warmed, so no lane is run again.

### By hand
I could not physically drag a window. I used `PURE_WINDOW_SIZE=1260x540` captures plus input-script runs that drive the Esc menu. What I saw:
- **The race.** It shows more track and stands to each side at the same height. The HUD keeps its proportions and position: the 32 HUD draws of frame 6016 are fitted.
- **The bloom** on the stand lights looks as at Original.
- **The lens flare** is an orthographic, unlit strip of 60 vertices, so the rule could fit it. Its strip measured at least 470 pixels in every frame seen: 765 flare draws to flip 8500, none fitted. So it stays with the 3D view, on the sun.
- **Menus.** The title, main menu and profile screens are fitted, with their white backdrops spread.
- **Switching at run time.** Original to Fill in the Esc menu mid-race prints `internal scale now 2: targets 1269x544 at 2.333:1`, and the override widens from the next flip. Changing Window size under Fill to the PSP's shape prints `now 6: targets 2880x1632`, and the view returns to 480/272.
- **Movies do not keep their shape.** This game draws each movie frame as one through-mode draw of 150 sprites covering the screen, so the rule treats it as a backdrop and stretches it: the boot "Sony ... Presents" movie, and the language page's backdrop (the paused intro movie's last frame), whose fitted text then sits over a stretched panel. The Vulkan rule does the same, so the two paths agree.

### Verify output (last 20 lines)
```
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
hud_check: shell metal, backend metal, 61 shots from flip 6200 to 7700, paced from flip 5900, out /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-af1fbfe20abd8382a/out/hud/metal
hud_check: run_boot exit 0, frame 7710 reached: yes, 36 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-af1fbfe20abd8382a/out/hud/metal/run.log
6200:H 6225:H 6250:H 6275:H 6300:H 6325:H 6350:H 6375:H 6400:H 6425:H 6450:H 6475:H 6500:H 6525:H 6550:H 6575:H 6600:H 6625:H 6650:H 6675:H 6700:H 6725:H 6750:H 6775:H 6800:H 6825:H 6850:H 6875:H 6900:H 6925:H 6950:H 6975:H 7000:H 7025:H 7050:H 7075:H 7100:H 7125:H 7150:H 7175:H 7200:H 7225:H 7250:H 7275:H 7300:H 7325:H 7350:H 7375:H 7400:H 7425:H 7450:H 7475:H 7500:H 7525:H 7550:H 7575:H 7600:H 7625:H 7650:H 7675:H 7700:H
hud_check: 61 of 61 shots have the HUD
menu_check: shell metal, out out/menu_check/metal
menu_check: run_boot exit 0, 9 s, log out/menu_check/metal/run.log
tabs: ok (4)
Video: ok (14)
Audio: ok (4)
Controls: ok (31)
System: ok (15)
menu_check: PASS
docs_check: 34 files, 0 findings: PASS
verify 086: PASS
```

### Open questions
- **Movies stretch under Fill on both renderers.** Keeping their shape would take a rule beyond 085's, for example: a through-mode draw that covers the screen from an 8888 main-memory texture is a movie, and gets fitted. That is a design call for 085 and 086 together; I did not depart from the shared rule.
- **The lens flare is safe only by its measured width.** If another track places it narrower than 470 pixels, the rule would pull it off the sun. The same holds on Vulkan.
- **Merging with 085.** When 085 merges, its (e) and (f) bars run in `--shell metal` as they are. Its (a) line still says "the HUD spread under Fill", which is wrong for Metal and is 085's wording to change. My change to the script is the `--shell` option, the per-shell data and output directories, and `PURE_INTERNAL_SCALE=0` for the Metal lane.
- **menu_check on Vulkan.** On batch/m2 it would have failed since task 084: the Vulkan shell already offered Fill. Its expected list is updated here for both shells.
- **Auto under Fill.** Metal draws 272S rows (1269x544 into a 1260x540 window, scaled linearly), as the brief specifies. Vulkan's Auto draws the window's own 540 lines.
- **No settle delay.** A Fill resize retires the targets at the next frame, with no settle delay like the Vulkan renderer's 12 frames. A live drag could rebuild them often; it was not measured.
- **Stale doc outside my scope.** docs/ge-backend.md 8.2 still says the Metal shell letterboxes by `game_aspect()`. That file is outside "May touch".

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
