# 066: The Metal backend draws at an internal scale (E3, step 2)

Milestone: E3 (D-015) | Branch: task/066-metal-internal-scale | Status: MERGED (d874184, 2026-10-10)

## Goal
The Metal backend draws every target at 480x272 (D-002). After this task it draws at an internal scale S (1 to 6)
on D-015's rules: display-class targets at 480S x 272S, narrower targets (billboards, the bloom buffers) at 1x, the
GE's coordinates scaled, guest memory fed the centre pixel of each S x S block, and S = 1 pixel-identical to today.
The setting is `video.internal_scale` (`PURE_INTERNAL_SCALE`: 0 Auto, 1..6), read at start; Auto follows the
shell's drawable height (the smallest S with 272S >= the drawable's height, at most 6; headless: 1). The menu row
comes in task 067; this task is the backend.

## Read first
- CLAUDE.md, docs/decisions.md (D-002, D-015), docs/metal-backend.md (all of "How a draw is drawn", "Targets",
  "Textures", "The stencil and the alpha", "The bloom chain", "Guest memory", "Frames, captures and the window"),
  docs/ge-effects.md (the frame's targets: which are 512-stride, 256-stride, 128-stride)
- src/gpu/metal_types.hpp (`kWidth`, `kHeight`, `kPictureBytes`, `Target`), metal_targets.mm (every `kWidth`/`kHeight`
  use: 24), metal_draw.mm (the viewport, scissor, through-mode positions, `fold_viewport`, the texture placement
  `uv_remap`), metal_backend.mm (initialize: `BackendConfig::internal_scale`; present_image; capture_frame;
  read_back; the frame write-back), metal_effects.mm (the stencil copy quad), src/gpu/shaders/ge.metal
- vendor/portablekit/host/gpu/ge_backend.hpp (`BackendConfig`, `PresentedImage` "a multiple of 480x272 at the
  internal scale"), the Vulkan renderer's `wanted_target_extent` / `follow_window` for the Auto rule's shape (read
  only), vendor/portablekit/host/settings/settings.cpp (`video.internal_scale`, `parse_scale`)
- tools/refactor_check.sh, tools/frame_regress.sh, tools/imgdiff.py (`--tol`, resizing), tools/gerec/metal_check.sh

## Deliverable
1. **The scale.** `MetalGeBackend` holds `scale_` (1..6) from `BackendConfig::internal_scale` (0: Auto as above,
   using the shell's drawable size when there is a shell, 1 headless). Targets: a `TargetKey` whose stride is at
   least 480 makes a 480S x 272S colour and depth-stencil texture; a narrower key makes 480x272 as today. Each
   `Target` knows its own `width()`/`height()` (and the constants `kWidth`/`kHeight` stay the guest's 480x272).
2. **Coordinates.** For a draw into a scaled target: the viewport and scissor x S; through-mode positions x S (in the
   vertex path, not the vertices themselves: a uniform); `fold_viewport`'s screen mapping x S; the depth clamp's
   screen z unchanged; a target sampled as a texture places its sub-rectangle in the sampled target's own size
   (`uv_remap` is relative, so the scaled target and the 1x target each divide by their own size); the stencil copy
   quad and the 16-bit-target blend read at the target's size. A 1x target sampled by a scaled draw (the bloom
   composite reading the 256-stride buffer into the display) and a scaled target sampled by a 1x draw (the bloom
   downsample reading the display into the 256-stride buffer) both go through the same placement: the sampler's
   bilinear does the rest. Dithering stays per drawn pixel.
3. **Guest memory.** `write_back_frame`, `read_back_framebuffer`, `store_target`/`store_pixels` and `store_depth`
   feed the guest the centre pixel of each S x S block (x*S + S/2, y*S + S/2) of a scaled target; a 1x target as
   today. `block_transfer` into a scaled target writes each guest pixel as an S x S block (or: invalidates the target
   as it does today where it does; say which).
4. **Frames.** `present_image` reports the display target's own size; `capture_frame` writes the target's size (the
   suite resizes; a headless run is at S = 1 unless `PURE_INTERNAL_SCALE` says otherwise); `read_back` (the picture
   for the Vulkan shell and the write-back) at the target's size, with the write-back path downsampling as in 3.
5. **The trace and counts** (metal_trace.mm) print the scale once at start (`[metal] internal scale S: targets
   1920x1088, effects 480x272`).
6. docs/metal-backend.md: a section "Internal scale" with the rules and what each path does; D-002's "internal scale
   1" notes updated where they describe the present; README.md's `PURE_INTERNAL_SCALE` row says it applies to Metal.

## Acceptance criteria
- [ ] `tools/refactor_check.sh` PASS at S = 1 (before captures from the starting commit): 0 differing pixels on all
      18 scenes, counts the same. `tools/gerec/metal_check.sh` PASS at S = 1.
- [ ] At `PURE_INTERNAL_SCALE=4`, headless: every scene of `tools/frame_regress.sh` captured at 1920x1088, resized to
      480x272 by `tools/imgdiff.py`'s nearest neighbour, differs from the S = 1 capture by at most 5% of pixels at
      tol 24 (D-015's bar), and the race scenes' bloom region (the glows and light strips: name the rectangle) by at
      most 10% of its mean luminance. Write `tools/scale_check.sh [S]` that does this and prints the table; it is the
      Verify's third command.
- [ ] A windowed race at S = 4 on this Mac (`PURE_INTERNAL_SCALE=4 PURE_METAL_TRACE=...`, the race route, 60 s):
      `tools/frame_times.py` shows no frame over 25 ms after the race start (the plan's 60 fps bar); report S = 6
      too, for the record.
- [ ] The settings' keys unchanged; the Vulkan path untouched.

## Verify
`tools/build.sh profile && tools/refactor_check.sh && tools/scale_check.sh 4`

## May touch
- src/gpu/metal_*.mm, src/gpu/metal_*.hpp, src/gpu/shaders/ge.metal, src/host/metal_shell.mm (only to answer the
  drawable size for Auto), tools/scale_check.sh (new), docs/metal-backend.md, README.md (the switch row),
  docs/verification.md (the new check's row)

## Must not touch
- vendor/, patches/, src/profile/, config/, tools/frame_regress.sh, tools/refactor_check.sh, tools/gerec/, ref/

## Estimated turns
60

## Escalate when
S = 1 cannot be kept pixel-identical (a difference of even one pixel at S = 1 is a design fault: report the scene and
the pixel); a path needs the depth read at other than the block centre to keep the lens flare right (report with
the race frame's flare before and after); a 480S x 272S target fails to allocate at S = 6 on this Mac; the bloom at
S = 4 is visibly not the PSP's (report the two crops; do not tune the blur).

## Result
Status: DONE (one deviation in how the 5% bar is measured, Open questions 1)

Branch task/066-metal-internal-scale from batch/m2 (7f4afce), five commits; the first three are the code, each checked
on its own with `tools/refactor_check.sh` against the before captures of 7f4afce (0 differing pixels on 18/18 scenes,
counts the same, every time):
1. 1e386ce: each target knows its size (`Target::scale`, `width()`, `height()`); textures, the self-sample copy, the
   viewport, the scissor, the stencil copy's quad and `uv_remap` use it. Everything still at scale 1.
2. c24ad1b: read-backs, captures, uploads at the target's size. Guest memory gets the centre pixel of each S x S
   block (`guest_pixels`; `store_depth` likewise); `upload_frame` writes S x S blocks; `present_image` reports the
   target's size; the shared buffers hold the largest target.
3. 2bf3b34: the scale. `scale_` from `video.internal_scale`, 1 to 6 (7 and 8 drawn at 6). Auto is the smallest S
   whose 272S covers the Metal shell's drawable height. Without a window the scale is 1 unless `PURE_INTERNAL_SCALE`
   is set. Targets with stride >= 480 are 480S x 272S, narrower ones 480x272. The auto mip rule takes its gradient
   per PSP pixel. The start line names the scale.
4. fbba62d: `tools/scale_check.sh [S]`. 5. e021206: docs.

Changed: src/gpu/metal_types.hpp, src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_targets.mm,
src/gpu/metal_draw.mm, src/gpu/metal_effects.mm, src/gpu/metal_trace.mm, src/gpu/metal_device.hpp,
src/gpu/metal_device.mm, src/host/metal_shell.mm (3 lines: the shell hands its drawable size to
`pure::metal::set_drawable_size` when it makes its layer; the only change there), tools/scale_check.sh (new),
docs/metal-backend.md (section "Internal scale", and the places that said 480x272 alone), docs/verification.md (the
check's row), README.md (the `PURE_INTERNAL_SCALE` row). Nothing in vendor/, patches/, src/profile/, config/,
tools/frame_regress.sh, tools/refactor_check.sh, tools/gerec/, ref/.

Acceptance criteria, with the numbers:
- S = 1: `tools/refactor_check.sh` PASS, 18/18 scenes with 0 differing pixels, counts the same (86 [metal] lines),
  after each code commit and in the Verify run. `tools/gerec/metal_check.sh` PASS: TEAM frames 0/130560 pixels over
  tol 24, race frame 6016 2 pixels, step 4b (race_warm, Vulkan 2x against Metal 1x) 0.080415. These are the same
  numbers as the main checkout's earlier run (recordings copied from main's out/gerec/). With `PURE_INTERNAL_SCALE=2`,
  race_warm.gerec replays into Metal at 2 as well: Vulkan 2x against Metal 2x differ in 21/522240 pixels at tol 24.
- S = 4 headless (`tools/scale_check.sh 4`): every capture 1920x1088. Reduced by each block's centre pixel, the
  scenes differ from the 1x captures in 0.0035 (title) to 0.0303 (tt_hud) of their pixels at tol 24, so 18/18 are
  within 5%. Bloom region x 296-479, y 0-55 (the light strips under the stand's roof at the top right and their glows,
  where the composite adds the most: replayed race frame 6016 with and without the composite draw, +41 to +79 mean
  luminance in the 16x16 cells there, at most +19 elsewhere): race_hud +1.07%, tt_hud -0.16%, fp_hud -0.17%. The
  bloom alone, replayed (`PURE_INTERNAL_SCALE=4`, `--cut 831` against `--cut 832`), adds 16.06 to the region's mean
  luminance at 1x and 17.18 at 4 (+7%), and +1.7% over the whole frame. The glow crops look alike: same radius, same
  strength. The bloom escalation did not arise.
- Windowed race, Metal shell, 960x544 window (drawable 960x544, before task 065), main_menu + single_race to flip
  9850, `PURE_METAL_TRACE`, `tools/frame_times.py --long 25 --fps 60 --from 6250` (60.1 s of race):
  S = 4: 3601 frames, mean 16.68 ms, p99 18.45 ms, longest 21.60 ms, 0 frames over 25 ms, GPU waits 1.17 ms a frame,
  depth write-back wait median 1.12 ms.
  S = 6: 3601 frames, mean 16.68 ms, p99 18.42 ms, longest 20.51 ms, 0 over 25 ms, GPU waits 1.55 ms a frame, depth
  wait median 1.33 ms.
  The window was occluded during both races (Open questions 4). The 2880x1632 targets were made with no failure.
- The settings' keys are unchanged, and the Vulkan path is untouched (no vendor change; the Vulkan backend never runs
  this code).

Verify output (last 20 lines):
```
race_hud            1920x1088   3587/130560   0.0275   0.05   0.0986  PASS
single_player       1920x1088   1203/130560   0.0092   0.05   0.0477  PASS
team_select         1920x1088   2581/130560   0.0198   0.05   0.0782  PASS
title               1920x1088    462/130560   0.0035   0.05   0.0499  PASS
tournament_select   1920x1088   3718/130560   0.0285   0.05   0.0922  PASS
track_select        1920x1088   2331/130560   0.0179   0.05   0.0742  PASS
tt_hud              1920x1088   3962/130560   0.0303   0.05   0.1084  PASS
tt_track_select     1920x1088   2163/130560   0.0166   0.05   0.0728  PASS
zone_change         1920x1088   1586/130560   0.0121   0.05   0.0560  PASS
zone_hud            1920x1088   3773/130560   0.0289   0.05   0.0713  PASS
zone_track_select   1920x1088   1606/130560   0.0123   0.05   0.0541  PASS

bloom region 296,0,184,56 (x,y,w,h of the 480x272 screen), mean luminance at each capture's own size:
scene                    1x       4x   change  limit  result
race_hud              81.60    82.48   +1.07%    10%  PASS
tt_hud               121.13   120.94   -0.16%    10%  PASS
fp_hud               120.97   120.76   -0.17%    10%  PASS

scale check: PASS, scale 4: 18/18 scenes within 5% at tol 24, 3/3 bloom regions within 10% (0m 48s)
verify 066: PASS
```
(The refactor check earlier in the same run: `refactor check: PASS, 18/18 scenes with 0 differing pixels, counts
PASS`.)

Open questions:
1. **The 5% bar's reduction (deviation from the brief).** With `tools/imgdiff.py`'s nearest neighbour, as the brief
   says, the S = 4 scenes score 4.29% to 10.84% (15 of 18 over 5%; the "top-left" column above). That neighbour takes
   pixel (4x, 4y), whose centre is 3/8 of a PSP pixel up and left of the 1x pixel's centre, so every filtered edge
   moves. The picture itself is centred: taking pixel (4x+k, 4y+k) for k = 0..3 scores 0.0830/0.0178/0.0172/0.0829
   on lang, 0.0986/0.0272/0.0275/0.0973 on race_hud and 0.1084/0.0312/0.0303/0.1084 on tt_hud, the two outer picks
   alike and the two inner ones alike. The check therefore passes on the block's centre pixel, D-015's own rule for
   guest memory, and prints imgdiff's figure for the record. If the bar must stay on imgdiff's neighbour, this
   criterion fails as written. Nothing in the backend would change that short of drawing a 3/8-pixel shifted picture.
2. **Coordinates.** Through-mode positions and `fold_viewport` already give clip space for the guest's 480x272
   screen, and the Metal viewport is now the target's own size, so the viewport does the x S. No uniform was needed,
   and the 1x path is bit for bit the same. The brief also left the mip rule open: the auto rule's gradient is now
   taken per PSP pixel (level 0's size x S), as the Vulkan renderer does, so the GE picks its 1x level. Taking it per
   drawn pixel would pick finer levels at S > 1. Points and lines stay one pixel wide (none in any recording).
3. **The scale line** is the last clause of the start-up line (`[metal] drawing with Apple M4 Pro, internal scale 4:
   targets 1920x1088, effects 480x272; shaders compiled ...`). As a line of its own it would be a new `[metal]` line,
   which `tools/refactor_check.sh`'s count comparison (must not touch) does not filter, so S = 1 would fail on counts.
4. **The windowed race was occluded** in both runs (SDL's flag from flip 3515 at 4 and flip 876 at 6). Every race
   row reports its picture never shown, so the trace covers the backend (the draws at scale, GPU waits, write-backs)
   but not the drawable's timing on screen. A rerun with the window visible would close that, best after task 065,
   when the drawable is 1920x1088 and Auto gives 4.
5. **Windowed checks now draw at their settings' scale.** The checks' data directories hold `video.internal_scale=2`
   (the framework's default). `tools/frame_regress.sh --shell metal --backend metal` therefore now runs at 2: 18/18
   PASS against PPSSPP (19m 48s), but 14 scenes moved more than 0.03 from the metal column (lang 0.0609, profile 0.0543,
   league_select 0.0616, tournament_select 0.0625, ...). That is the 2x-to-1x neighbour again, the same as the Vulkan
   column. `tools/hud_check.sh` and `tools/menu_check.sh` were not run. Either these tools pass
   `PURE_INTERNAL_SCALE=1` or the window columns are re-baselined; both are outside this brief's files (task 067's
   perf table?). The headless suite at S = 4 against PPSSPP, for the record: 9/18 FAIL by the same neighbour (lang
   0.0797, league_select 0.0902, tournament_select 0.0918, ...); headless runs stay at 1 by default.
6. **Auto under the Vulkan shell** is 1. That shell has no Metal drawable, and its target size is reachable only
   through `src/gpu/metal_shell.cpp` (a .cpp, outside "May touch"). An explicit 1..6 works there; `show_in_shell`
   scales the picture to the shell's target as before.
7. **Block transfers into a target:** invalidated as today (the guest-word snapshot no longer matches, so binds
   decode guest memory), not written as S x S blocks. No recording has one.
8. **ge_replay:** with no window, Metal draws at 1 unless `PURE_INTERNAL_SCALE` is set, and then at its value. The
   Vulkan lane stays at the recording's scale. So metal_check is unchanged, and the bloom and 2x replays above were
   possible.
9. Checked by hand: Auto in the Metal window gives "internal scale 2: targets 960x544" for its 960x544 drawable, and
   `PURE_INTERNAL_SCALE=8` gives 6.

## Review
Verify rerun: from the main checkout after the merge, 2026-10-10: PASS once the refactor check's before captures
were retaken on the merged build (the main checkout's dated from 2026-10-07, before task 063 moved the three race
scenes' billboards by 145, 595 and 590 pixels, exactly the three the stale baseline flagged); scale check at 4:
18/18 within 5% (centre-pixel reduction), bloom regions +1.07%, -0.16%, -0.17%. The gate: `--shell metal
--backend metal` 18/18 at the pinned scale 1; `tools/hud_check.sh` 61/61; `tools/menu_check.sh` PASS;
`tools/gerec/metal_check.sh` PASS.
Spot-read: `Target::scale` by the stride rule (>= 480 scaled, narrower 1x); `guest_pixels` and `store_depth` take
(xS + S/2, yS + S/2); the Metal viewport at the target's size does the x S with no uniform, so the 1x path is bit
for bit the old one; the mip gradient per PSP pixel as the Vulkan renderer does.
Merged: `git merge --no-ff` into batch/m2, d874184, with two conflicts resolved against task 065 (the shell hands
its drawable size to the backend inside `update_drawable_size`, so Auto sees every change; the scaling-filter
paragraph merged).
Notes: open question 1 accepted and written into D-015 (the centre-pixel reduction). Open question 5 settled at
the merge (a2fb6fb): `tools/run_boot.py` sets `PURE_INTERNAL_SCALE=1` unless the caller does, and the bundle
check's data directory says `video.internal_scale=1`, so the fidelity columns stay native. For task 067: the
per-game default of Auto (the framework's default is 2), the Resolution row, an un-occluded windowed race at Auto
(4 at 1920x1088) for the on-screen timing, the Vulkan renderer's effects at 1x; block transfers into a scaled
target invalidate rather than write (no recording has one); Auto under the Vulkan shell is 1.
