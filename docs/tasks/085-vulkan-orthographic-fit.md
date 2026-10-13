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

**Status: BLOCKED**, on the brief's second escalation condition: a screen-wide orthographic draw that holds interface
art cannot be told from a backdrop by its extent (the draw is below). Everything else the brief asks for is done and
passes: the patch, the check's (e) and (f), the docs, Verify (aspect_check PASS, the Vulkan window suite 7/7, 28
patches, docs_check PASS), and the headless suite 18/18 with the same figures as task 084's. The review decides
whether the remaining case blocks the merge. Nothing was widened to work around it.

**Changed:**
- New: patches/0028-vulkan-orthographic-fit.patch (host/gpu/vulkan_renderer.cpp, host/gpu/frame_interpolation.hpp
  and .cpp).
- Edited: tools/aspect_check.sh ((e), (f); the lane function takes the scene), patches/README.md (row and section),
  docs/upstream.md (row and section), docs/metal-backend.md (a new section, "The interface fit under Fill"),
  docs/status.md (the E2 bullet), docs/verification.md (the check's row and the "Which path" line), README.md (the
  tool row and `PURE_NO_ORTHOGRAPHIC_FIT`), this file.

### What the patch does
- In `submit`, a transformed draw that is orthographic (`projection[3]`, `[7]`, `[11]` all 0) with lighting off,
  into the shown framebuffer, not clear mode, not sampling a rendered picture, under Fill (`interface_fit` true), is
  measured: its vertices through `viewport_into_clip(call) * projection * view * world`, divided by w. Below 470 of
  the 480 PSP pixels wide, it is fitted: `clip_fit = {fit_x, fit_y}`.
- `push.transform` takes `viewport_into_clip(call, fit_x, fit_y)`, a new overload that scales the clip x and y rows.
  Clip (0, 0) is the screen's centre, so that is the fit about the centre. The draw's scissor is fitted with it, as a
  through-mode draw's is.
- The interpolation summary takes the same fit: `record_draw_for_replay(..., clip_fit)` and `summarize(call, fit_x,
  fit_y)`, which folds it into the summary's projection. So the replay, which rebuilds a blended draw's transform from
  the summaries, agrees with the main path.
- At a fit of 1 both are bit for bit as before (a multiply by 1.0f). Through-mode draws keep the vertex fit unchanged.
  The `orthographic` flag is computed once and reused by the texture detail test of patch 0020.
- A raw draw (GPU decode, `PURE_GPU_DECODE=1`, off by default) has no vertices on the CPU to measure and stays
  spread.
- One addition the brief did not ask for: `PURE_NO_ORTHOGRAPHIC_FIT` fits through-mode draws alone, as before (the
  framework's "give new behaviour an off switch"). README.md has its row.

### The draw that blocks
- **Which.** The profile screens (PROFILE, SET NAME, SET TAG: the main_menu route's flips about 1800 to 4300) draw
  their panel art as one quad. The panel art is the rules across the screen, the CONFIRM row's line, the A-G RACING
  box, the logo and the memory stick's outline.
  - The quad samples a CLUT8 texture, 512x512, in VRAM at 0x04179a40. On the title screen the same address is a
    512x128 texture, whose spread I could not see in the capture.
  - It is orthographic, unlit and blended, and spans x 0 to 480 through its transform.
  - The renderer finds no render target there (`framebuffer_source` is null), so the texels are written by the guest,
    not rendered.
- **What the rule does with it.** At 480 wide it stays spread, like the white backdrop drawn just before it (an
  untextured quad, 0 to 480).
  - The text and buttons drawn over it are fitted: PROFILE, LOAD, NEW, DELETE, the cursor, CONFIRM, BACK, the NAME00
    box.
  - Under Fill at 1260x540 the panel's top rule runs from x 58 to 1228, its boxes are a third too wide, and none of it
    lines up with the fitted text any more.
  - Captures in this worktree: out/085_byhand/shots/f2100.png, out/085_byhand/shots2/g3000.png and g3900.png.
- **How it was found.** A temporary trace (removed before the export) listed every textured 2D draw at least 470
  pixels wide on the main_menu + single_race route.
  - Besides the layer there was only one: a 64x64 CLUT8 texture at 0x0968a4b0 during the race's fly-in (flips about
    5950), x -101 to 1176. It is wider than the screen, an effect, and spread under any rule.
- **Options for the review** (none taken):
  1. Merge as is and accept the profile screens stretched under Fill (a player sees them when making or loading a
     profile).
  2. Fit a textured screen-wide 2D draw and keep only untextured ones spread. The white backdrop is untextured (seen
     in the trace); the fades were not checked. The race's 64x64 effect would be pulled in a third too.
  3. A profile field naming the texture addresses that are interface layers (game knowledge, a `GameProfile` field).
  4. Leave it to Erik's eye.

### aspect_check (two runs, every fraction the same to the fourth decimal; the second run's counts)
- **(a)** 0.0691 between the HUD's bars (limit 0.10), as in task 084. Over the whole strip it is now 0.0512 (task 084:
  0.0826 with the HUD spread). A stretched picture scores 0.4647.
- **(b)** Left strip: variance 3884.5, 0.6356 apart from the central strip. Right strip: 6222.6 and 0.5239.
- **(c)** Transformed draws at the frame: 857 under Original, 858 under Fill.
- **(d)** Original: race camera 300 calls, 0 widened. Fill: 294 calls, 294 widened.
- **(e)** 0.0205 over the HUD's bands (rows 0 to 40 and 212 to 272) at tol 32.
  - The limit is 0.05, measured with a margin of about 2.4.
  - A stretched picture scores 0.4419 over the same bands.
  - strip.hud.diff.png shows the edges of the 3D view and of the HUD's glyphs: resampling.
- **(f)** The main menu's central strips differ in 0.0205 at tol 24.
  - The limit is 0.05; the tol and limit are the suite's for the scene.
  - The differences are glyph edges and the one-pixel rule under MAIN MENU: resampling.
  - The outer strips are 1.0000 not black, mean colour (255, 255, 255): the white backdrop stays spread.
- **Time.** 5m 18s the first run (both race lanes made pipelines and ran again). 3m 57s the second, which included
  two waits for task 086's game.

### By hand
I read the captures of a window at 1260x540 under Fill. The route was main_menu + single_race without
`PURE_TRACE_3D`, so the direct vertex path ran; the check's race lanes take the expanded path, and its menu lanes
both.
- **Title (1750):** the logo, PRESS START BUTTON and the bottom bar at their proportions, white across the window.
- **The fade after START (1805):** white over the whole window.
- **Profile screens (2100, 3000, 3900):** the blocking case above.
- **Main menu (4460, 4700), SINGLE PLAYER (4712, 4740), TEAM SELECTION (5600):** text, art, rules and the bottom panel
  fitted; the white backdrop over the whole window.
- **Race start (6016) and racing (6400):** the HUD at its proportions (CURRENT, POS, LAP, the speed and shield bars,
  the track's name), the track to both sides.
- **Not exercised: the interpolation replay of a fitted draw.** This game's profile does not blend orthographic draws
  (`CutThresholds::orthographic` false), so a fitted draw is replayed from its recorded state, which has the fit. The
  summary carries the fit for a game that blends them.

### Verify output (last 20 lines)
Verify's four commands were run one at a time, each after waiting for task 086's game to end: out/verify_085_*.txt.
The headless suite: 18/18, every figure as in task 084's Verify (zone_change 0.0369).
```
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 11 s, paced from flip 5716, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-acce1db8807af49eb/out/regress/main_menu+single_race.log
run main_menu+time_trial: 5920 flips, paced from flip 5590 ...
run main_menu+time_trial: run_boot exit 0, frame 5920 reached: yes, 15 s, paced from flip 5590, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-acce1db8807af49eb/out/regress/main_menu+time_trial.log
run main_menu+free_play: 5920 flips, paced from flip 5590 ...
run main_menu+free_play: run_boot exit 0, frame 5920 reached: yes, 15 s, paced from flip 5590, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-acce1db8807af49eb/out/regress/main_menu+free_play.log
run main_menu+zone: 5709 flips, paced from flip 4960 ...
run main_menu+zone: run_boot exit 0, frame 5709 reached: yes, 28 s, paced from flip 4960, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-acce1db8807af49eb/out/regress/main_menu+zone.log

scene       frame  fraction  limit  tol  measured   delta  result
title        1750    0.0302   0.05   24     0.030 +0.0002  PASS
main_menu    4700    0.0331   0.05   24     0.033 +0.0001  PASS
race_hud     6016    0.0465   0.10   32     0.047 -0.0005  PASS
tt_hud       5890    0.0505   0.12   32     0.049 +0.0015  PASS
fp_hud       5890    0.0488   0.11   32     0.048 +0.0008  PASS
zone_hud     5260    0.0452   0.09   32     0.045 +0.0002  PASS
zone_change   5679    0.0522   0.10   32     0.052 +0.0002  PASS

frame regression: PASS, 7/7 scenes pass, the window scenes, shell vulkan, backend vulkan (1m 36s)
ok: 28 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 34 files, 0 findings: PASS
```

### Open questions
- **The profile screens' panel layer, above:** which option, if any.
- **Raw draws are not fitted** (GPU decode, opt-in): measuring them would need their positions decoded on the CPU.
- **The docs describe the rule as it stands.** They name the profile screens as not covered (docs/metal-backend.md,
  docs/status.md, patches/README.md, docs/upstream.md), so a different decision means editing those lines.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
