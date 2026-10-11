# 068: The Vulkan renderer draws the effects buffers at 1x (E3, step 4, for Windows)

Milestone: E3 (D-015) | Branch: task/068-vulkan-effects-at-1x | Status: MERGED (867cad6, 2026-10-10)

## Goal
The Vulkan renderer draws every target at its internal scale, the bloom buffers included, so above 1x the bloom's
11-tap blur covers a smaller share of the screen and the glow tightens (PPSSPP keeps this game's effects at low
resolution for that reason; D-015 gives the Metal backend the same rule: a target narrower than 480 stays 480x272).
After this task the Vulkan renderer does the same, so the Windows build at 2x or Auto shows the PSP's glow.

## Read first
- CLAUDE.md, docs/decisions.md (D-015), docs/tasks/066-metal-internal-scale.md (the rule and how the Metal backend
  places a 1x target sampled by a scaled draw and the reverse), docs/metal-backend.md ("Internal scale", "The
  bloom chain"), docs/ge-effects.md ("The bloom chain": the 256-stride buffers, the downsample and composite draws)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp (`Target`, `create_target`, `target_extent`, the render pass's
  `renderArea` and viewport, `framebuffer_descriptor`, the framebuffer-texture placement of task 063's patch,
  `write_back_depth`, `read_back_framebuffer`, `record_game_blit`), shaders/ge.vert and ge.frag
- patches/README.md, docs/upstream.md; tools/gerec/metal_check.sh (step 4b: race_warm at 2x against Metal at 1x)

## Deliverable
1. **Patch `0018-vulkan-effects-at-1x`**: a `Target` has its own extent: `target_extent` for a key whose stride is at
   least 480, 480x272 for a narrower one. Every place that assumed one extent takes the target's: the pass's render
   area and viewport, the scissor's scale, the copy for a framebuffer texture (its sub-rectangle divides by the
   source target's own size, as task 063's placement does on Metal), the depth write-back and read-backs (from a
   scaled target: the centre pixel of each block, as the Metal backend does; a 1x target as today), the display
   blit. The through-mode tile clamp task 063 noted lost above 1x is not this task's.
2. **Measured**: race_1x.gerec frame 6016 replayed into Vulkan at 2x (`PURE_INTERNAL_SCALE=2`, the Vulkan lane at
   the setting) before and after: the bloom region of `tools/scale_check.sh` (x 296-479, y 0-55) against the 1x
   replay's mean luminance, before (the tightened glow: say the figure) and after (within 10%); the glow crops.
   Metal at 2x against Vulkan at 2x on that frame: within tol 24 on 98% of pixels (the metal_check bar).
3. docs/metal-backend.md "Where it differs from the Vulkan backend on purpose" loses the effects-at-1x line if it
   has one; docs/windows.md gets one sentence (the Windows build's default scale draws the bloom at 1x).

## Acceptance criteria
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` 18/18 (test runs at 1x: the Vulkan column unchanged;
      say the deltas); `tools/gerec/metal_check.sh` PASS, step 4b's figure reported before and after.
- [ ] The 2x measurements above.
- [ ] `tools/patches.sh check` ok with 18 patches.

## Verify
`tools/build.sh profile && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/gerec/metal_check.sh`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, shaders/ge.vert, ge.frag: through `tools/patches.sh export
  0018-vulkan-effects-at-1x`, patches/README.md, docs/upstream.md
- docs/metal-backend.md (one line), docs/windows.md (one sentence), docs/verification.md if a column moves

## Must not touch
- src/, include/psprecomp/, tools/, config/, ref/, the Metal backend

## Estimated turns
45

## Escalate when
The renderer's framebuffer-texture copy cannot take a source of another size without the GENERAL-layout question
task 060 left open (report); the Windows suite cannot be run here (expected: say so; the Mac's Vulkan window suite
is the gate).

## Result
Status: DONE

Branch task/068-vulkan-effects-at-1x from batch/m2 (790e628). Commit b04fa2e is patch 0018 and the docs; the next
commit is this Result.

What the patch does (vendor/portablekit/host/gpu/vulkan_renderer.cpp only; ge.vert and ge.frag needed no change,
because the placement and the wrap clamp in the shaders are already relative to the target's size):
- `Target::extent` is set when a target is made, from the stride of the draw that makes it (`extent_for`):
  `target_extent` for a stride of 480 or more, 480x272 for a narrower one. A target made without a draw
  (`upload_frame`'s, the interpolation pictures) is screen-sized. `resize_targets` makes each target again at the
  size its stride gives at the new resolution.
- These now take the target's own size: the pass's render area, the viewport, the scissor's scale, the 16-bit pixel
  scale for the dither, the auto mip rule's 16 x log2(scale) (`drawn_extent`), the stencil copy's quad, the
  framebuffer-texture copy (`framebuffer_descriptor`; `uv_remap` is relative, so the composite (1x into 2x) and the
  downsample (2x into 1x) use the same placement), `hold_frame`, `upload_frame`'s blit, the display blit
  (`record_game_blit` and `submit_and_present` take the source's size), `capture_frame`, `display_image`, the
  interpolation copy and replay, and the depth write-back.
- Read-backs from a scaled target give the centre pixel of each block, as the Metal backend does (`centre_texel`, which
  the depth write-back now shares). The frame write-back and `read_back_framebuffer` copy the target's centre row of
  each PSP row whole: 272 copy regions, or one at 1x. `take_writeback` then picks the centre column. Before, a linear
  blit into a 480x272 image averaged each block's four middle pixels at 2x. That image is gone. Each slot's buffer is
  made on first use and again when a wider target needs more.

Measurements, race_1x.gerec frame 6016 (out/068/, scripts in the session scratchpad):
| Picture | Bloom region mean luminance (x 296-479, y 0-55, at its own size) | vs Vulkan 1x | Glow alone in the region (cut 832 minus cut 831) |
|---|---|---|---|
| Vulkan 1x | 81.13 | | +16.06 |
| Vulkan 2x before | 81.57 | +0.54% | +16.71 (+4.0%) |
| Vulkan 2x after | 81.46 | +0.41% (within 10%) | +16.57 (+3.2%) |
| Metal 2x (`PURE_INTERNAL_SCALE=2`) | 81.46 | +0.41% | |
- Vulkan 1x before and after: 0 pixels differ at tol 0.
- Metal 2x against Vulkan 2x on frame 6016: before, 33/522240 px over tol 24 (0.000063); after, 14/522240 (0.000027).
  Both PASS the metal_check bar. At tol 0 the pictures differ in 178985 px before and 679 after, so Vulkan at 2x now
  draws Metal's picture.
- The glow crops (out/068/crop_before.png and crop_after.png: 1x, Vulkan 2x, Metal 2x) look the same apart from the
  2x glow's finer detail before the patch. The "tightened glow" in the before figure is small (Open questions 1).
- race_warm.gerec at 2x into both backends (`PURE_INTERNAL_SCALE=2`): 18/522240 px over tol 24 (task 066 had 21).
- metal_check step 4b (race_warm, Vulkan 2x against Metal 1x): before 0.080415 (10499 px), after 0.080362 (10492 px).
  Steps 2, 3 and 4a are unchanged: TEAM 0 px, race 2 px, first difference at draw 508.
- `tools/patches.sh check`: ok, 18 patches reproduce vendor/portablekit at 8b0c3fe. The patch applies on 0002 to 0004
  plus 0010 to 0015 (checked on a clean pin), not on 0002 to 0004 alone.
- Vulkan validation layer (VK_LAYER_KHRONOS_validation), on two runs: the 2x replay of frames 6008-6016, and a
  windowed race (main_menu + single_race) where the Esc menu's Resolution row went from Auto (2x) to x1 and back.
  The log shows `[render] internal resolution 480x272`, then `960x544`, and the picture after is right. The only
  message is the existing VUID-VkImageViewCreateInfo-imageViewFormatSwizzle-04465, for the opaque view of a 5650
  copy (patch 0003's code).

The Vulkan window suite (it draws at 2x: Auto in the 960x544 window). "Before" is the main checkout's run of 790e628
earlier today (out/068/regress_before_790e628.txt). "After" is the Verify run.
| Scene | Before | After | | Scene | Before | After |
|---|---|---|---|---|---|---|
| race_hud | 0.0428 | 0.0465 | | zone_hud | 0.0451 | 0.0452 |
| tt_hud | 0.0469 | 0.0467 | | zone_change | 0.0544 | 0.0203 |
| fp_hud | 0.0475 | 0.0456 | | the 13 frontend and menu scenes | | the same to 4 decimals |
Deltas against the script's Vulkan column: race_hud -0.0065, tt_hud -0.0013, fp_hud -0.0104, zone_hud -0.0028,
zone_change -0.0277, the menus +0.0000 to +0.0004. No scene moved more than 0.03, so the column (in
tools/frame_regress.sh, which this brief may not touch) and docs/verification.md stay as they are.

Changed: patches/0018-vulkan-effects-at-1x.patch (new: host/gpu/vulkan_renderer.cpp), patches/README.md (the row and
"0018-vulkan-effects-at-1x"), docs/upstream.md (the dependency row and the section: a candidate behind a profile
switch), docs/metal-backend.md ("Where it differs from the Vulkan backend on purpose" no longer lists the effects at
1x), docs/windows.md (one sentence in step 3), docs/tasks/068-vulkan-effects-at-1x.md (this Result).

Verify output (last 20 lines):
```
[replay]   57 draws: diff 0.000429 (tol 24, 56/130560 px at 480x272) FAIL (133.8 ms)
[replay]   29 draws: diff 0.000000 (tol 24, 0/130560 px at 480x272) PASS (131.5 ms)
[replay]   43 draws: diff 0.000429 (tol 24, 56/130560 px at 480x272) FAIL (127.8 ms)
[replay]   36 draws: diff 0.000000 (tol 24, 0/130560 px at 480x272) PASS (132.2 ms)
[replay]   40 draws: diff 0.000084 (tol 24, 11/130560 px at 480x272) FAIL (140.2 ms)
[replay]   38 draws: diff 0.000000 (tol 24, 0/130560 px at 480x272) PASS (124.8 ms)
[replay]   39 draws: diff 0.000000 (tol 24, 0/130560 px at 480x272) PASS (134.9 ms)
[replay] first difference in frame 6016: draw 40 of 906 (record 10506 in gerec_dump.py's listing)
  primitive triangle_strip, 7 vertices, 0 indices, transformed, vertex type 0x0000013F
  target 0x04088000 8888 stride 512, depth 0x04110000 stride 512
  texture 0x041F41C0 clut4 64x64 buffer 64 swizzled, clut 0x041F4180 format 3 shift 0 mask 0xFF offset 0, function 0 with texture alpha, filter 7/1, wrap 0/0
  blend off: source 2 destination 3 equation 0, fixed 0x000000/0x000000
  alpha test on: function 6 reference 0x7F mask 0xFF
  stencil on: function 1 reference 0x04 mask 0xFF, ops fail 0 depth fail 0 pass 2
  clear mode off
  depth test on function 6, write on, write masks colour 0x000000 alpha 0x00

metal_check: PASS (5 s)
verify 068: PASS
verify exit 0
```
(The same run's suite: `frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (19m 53s)`.)

Open questions:
1. **The "before" figure is small.** The blur's taps are through-mode positions, and those scale with the target. So
   at 2x the Vulkan renderer already blurred with the PSP's radius. The only difference was that the downsample kept
   the 2x detail. Before the patch the region's mean was +0.54% over 1x and the glow alone +4.0%; after, +0.41% and
   +3.2%, the same as Metal's. What the patch changes visibly is the glow's resolution: 34% of the 2x pixels change by
   a level or two, and Vulkan's 2x picture now matches Metal's.
2. **Replaying race_1x at 2x needs a relabelled copy.** ge_replay opens the Vulkan lane at the recording's own scale,
   read from its FrameEnd sizes. `PURE_INTERNAL_SCALE=2` does not move it: "replayed into vulkan at 1x", checked. The
   brief's "the Vulkan lane at the setting" does not hold. The 2x figures come from out/gerec/race_1x_as2x.gerec, a
   copy with each FrameEnd's width and height set to 960x544. Its draws are race_1x's, and those fields are read only
   for the scale and `--compare`. A `--scale` option in src/tools/ge_replay.cpp would make this one command; src/ was
   outside this brief.
3. **The write-back follows the brief, at a cost.** Each flip copies 272 rows of the target's width into host memory:
   2 MB at 4x and 4.2 MB at 8x, against 0.5 MB before, in 272 copy regions. That is still smaller than the depth
   write-back, which copies 8.4 MB at 4x on every race frame. Not measured on Windows. No suite scene shows the change:
   the menus are identical to 4 decimals.
4. A target keeps the size it was made at if its address is later drawn with a stride on the other side of 480. The
   next scale change makes it again at the right size. No recording has such an address: each keeps one stride.
5. No `<prefix>_` switch restores the old sizes. The vendor's AGENTS.md asks for one, but README.md's switch table was
   outside "May touch". An A/B needs a build without the patch.
6. **The first Verify attempt did not count.** It lost the frontend route: "Runtime stopped: window closed" 15 s in,
   during the intro movie (run_boot exit 4), so lang, title and profile had no capture. Every other route passed. The
   frontend scenes alone then passed (0.0544, 0.0302, 0.0543), and the full Verify above was run again from the
   start. zone_change scored 0.0522 in the first attempt and 0.0203 in the second, on the same build (0.0544 before
   the patch). That looks like run-to-run spread at the zone-change frame, but I did not check the captures.
7. The Windows suite was not run (no Windows machine here). The Mac's Vulkan window suite above is the gate.
8. Two old zsh wait loops from an earlier session (PIDs 21205 and 21547) poll `pgrep -f "frame_regress.sh --shell
   metal"`. Their own command lines contain that string, so they will never exit, and any check that looks for a
   running frame_regress with `pgrep -f` sees them.

## Review
Verify rerun: from the main checkout after the merge and patch 0018 applied to the vendor tree (18 patches
reproduce the pin), 2026-10-10: PASS (`--shell vulkan --backend vulkan` 18/18 at its 2x; `tools/gerec/metal_check.sh`
PASS). The gate: `--shell metal --backend metal` 18/18; headless 18/18; `tools/hud_check.sh` 61/61;
`tools/menu_check.sh --shell vulkan` PASS; `tools/refactor_check.sh` PASS at scale 1.
Spot-read: `Target::extent` by the stride rule, `extent_for` at creation and `resize_targets`; the read-backs' centre
texel shared with the depth write-back; the frame write-back's 272 row copies replacing the averaging blit. The
measurements are the right ones: Vulkan 1x unchanged at tol 0, Vulkan 2x against Metal 2x 679 px at tol 0 (from
178985), the race scenes closer to the PPSSPP column.
Merged: `git merge --no-ff` into batch/m2, 867cad6. E3 is complete on both backends.
Notes: the brief's premise was half wrong (the blur radius already scaled; the glow's resolution did not), which the
worker measured and said. Follow-ups recorded in docs/status.md: `ge_replay --scale` (the Vulkan lane replays at
the recording's size; a relabelled copy was needed for the 2x figures); the frame write-back's copy grows with the
scale (2 MB at 4x; the depth write-back's 8.4 MB is larger); no `PURE_NO_...` switch for the sizes; the Windows
suite not run here. The first Verify attempt lost the frontend route to my bundle check's Finder launch ("window
closed"); the second was clean.
