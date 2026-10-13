# 085: The 2D interface at square pixels under Fill (E2, the Vulkan fit for orthographic draws)

Milestone: E2 | Branch: task/085-vulkan-orthographic-fit | Status: OPEN

## Goal
Under the framework's Fill aspect (task 084 made this game's 3D view take the window's shape) the HUD and the menus
keep their proportions. The Vulkan renderer already pulls the 2D interface in about the screen's centre to square
pixels, but only through-mode draws (`interface_fit`, the `call.through` condition in the draw path). Wipeout Pure
draws its menus and HUD as transformed draws under an orthographic projection with lighting off (task 073's finding,
the rule E7 and E5 use), so under Fill they stretch today: at 21:9 the HUD is a third wider than it should be. This
task extends the fit to those draws, as a vendor patch, and extends the aspect check to prove it.

## Read first
- docs/decisions.md D-020 (point 3) and docs/tasks/084-ultrawide-view.md (the Result: what the check measures and
  the figures it got; its Open questions)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `interface_fit` (about line 5560) and its use in the draw path
  (about line 6623: the through-mode fit of `impl.scratch` vertices, `kScreenWideDraw`, the exclusions: clear mode,
  a draw that samples a rendered picture, a draw not into the shown framebuffer); the push constants (about line
  6899: `push.transform = viewport_into_clip(call) * projection * view_world`); the renderer's own `orthographic`
  test (about line 6941, E5's); the frame interpolation replay (about lines 8136 to 8230: the transform is rebuilt
  there from the draw summaries)
- vendor/portablekit/host/gpu/frame_interpolation.cpp and .hpp: `viewport_into_clip` (the GE viewport folded into
  the target's clip space: clip (0, 0) is the screen's centre), `is_orthographic`, the draw summary's `projection`
  (line 31: `viewport_into_clip(call) * call.projection`)
- src/gpu/metal_draw.mm lines 418 to 432 (the 2D rule as this port states it: through, or orthographic with the w
  row zero and lighting off; the TEAM screen's ship is orthographic but lit, a model)
- tools/aspect_check.sh (task 084), tools/imgdiff.py, tools/frame_regress.sh (the `title` and `main_menu` scenes:
  route `frontend.txt` frame 1750 and `main_menu.txt` frame 4700)
- patches/README.md, docs/upstream.md, docs/metal-backend.md "The Vulkan renderer" (where the Vulkan patches are
  described in this port's docs), docs/verification.md; CLAUDE.md

## Deliverable
1. Vendor patch `0028-vulkan-orthographic-fit` (host/gpu/vulkan_renderer.cpp, and frame_interpolation.cpp if the
   summary is the right place): under Fill (`interface_fit` true) a transformed draw that is orthographic
   (`projection[3]`, `[7]`, `[11]` all 0) with lighting off, into the shown framebuffer, not clear mode and not
   sampling a rendered picture, is drawn pulled in about the screen's centre by `fit_x`, `fit_y`: a scale of clip x
   and y applied after `viewport_into_clip` (clip space is centred on the screen, so a scale about its origin is
   the fit about the centre), in the same place for the main draw path and for the interpolation replay (fold it
   into the summary's projection, or apply it where the replay rebuilds the transform; both paths must agree or an
   interpolated frame jumps). Screen-wide draws stay spread, as the through rule says: a draw whose x extent in
   clip space, from its vertices through the transform, covers at least 470/480 of the width (fades, backdrops,
   the bloom chain's quads); draws that sample a rendered picture are excluded already. Through-mode draws keep
   the existing vertex fit unchanged. Nothing changes at Original or Stretch (interface_fit false), and nothing
   changes for a game without `view_aspect_frame` (Fill is not offered).
2. `tools/aspect_check.sh` gains two bars, in the same two lanes at 1260x540:
   - (e) The HUD: the Fill capture's central strip scaled to 480x272 against the Original capture over the HUD
     bands (rows 0 to 40 and 212 to 272, the bands (a) leaves out) within a limit you measure and set with a
     margin, and the whole-frame fraction printed beside (a)'s. Task 084 saw 0.0826 over the whole strip with the
     HUD stretched and 0.0691 between the bars; with the fit the bands should come down to the resampling floor.
   - (f) The main menu: the `main_menu.txt` route to frame 4700 in both lanes (the suite's scene; paced from 4400
     as the suite does), the Fill capture's central strip scaled to 480x272 against the Original capture within
     0.05 (a 2D screen: it should match as the suite's own captures match their reference), and the outer strips
     of the Fill capture not black (the backdrop stays spread) unless the game draws nothing there, in which case
     say what they hold.
   Keep (a) to (d). The check's time grows by two frontend routes (about 50 s each in the window).
3. Docs: patches/README.md row and section; docs/upstream.md row (a candidate: any game whose 2D is orthographic);
   docs/metal-backend.md's Vulkan section or docs/ge-backend.md, one paragraph on the fit rule; docs/status.md's E2
   bullet (what 085 closes, the figures); docs/verification.md's row for the check updated; README.md's tool row
   if its one line changes.

## Acceptance criteria
- [ ] `tools/aspect_check.sh` PASS with (a) to (f); (e) and (f) within their limits; the figures in the Result.
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 7/7 (Original: nothing changes).
- [ ] `tools/frame_regress.sh` (headless, Metal) 18/18 unchanged.
- [ ] `tools/patches.sh check` reports 28; `python3 tools/docs_check.py` PASS.
- [ ] By hand (say in the Result what you saw): a window at 1260x540 under Fill, the title screen, the main menu
      and a race start: menus and HUD at their proportions, the fades and backdrops covering the whole window.

## Verify
`tools/aspect_check.sh && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/frame_interpolation.cpp and .hpp,
  exported as patches/0028-vulkan-orthographic-fit.patch (commit patches/, never vendor/)
- tools/aspect_check.sh, tools/purelib/port.py (a helper only if needed)
- patches/README.md, docs/upstream.md, docs/metal-backend.md or docs/ge-backend.md, docs/status.md,
  docs/verification.md, README.md, docs/tasks/085-vulkan-orthographic-fit.md

## Must not touch
- vendor/portablekit/include/psprecomp/; the kernel; src/gpu/ and src/host/ (the Metal side is task 086);
  src/profile/ (the hook is task 084's); config/; generated/, game/, disc/, ref/
- tools/regen.sh, tools/build.sh all

## Estimated turns
45

## Escalate when
- The fit cannot be expressed as a clip-space scale (a draw path that bypasses `push.transform`, or the GE
  viewport not centred on the screen for these draws, so the fit would need an offset the renderer cannot know).
- A screen-wide orthographic draw cannot be told from a wide HUD element by its extent (say which draw).
- (f) fails because the frontend draws its 2D some third way (neither through nor orthographic unlit): report the
  draw's projection and lighting state.
- Anything would touch include/psprecomp/ or the Metal backend.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
