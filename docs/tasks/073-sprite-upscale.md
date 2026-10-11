# 073: The menus' and HUD's bitmap art upscaled (E7)

Milestone: E7 (Erik, 2026-10-11; D-018) | Branch: task/073-sprite-upscale | Status: MERGED (ddad728, 2026-10-11; replanned once after a BLOCKED first run: the draw rule)

## Goal
The frontend's text and art are bitmap atlases drawn at one texel a screen pixel in through mode (D-018: the font
atlases CLUT4 256x128 and 256x256, glyphs about 15 texels tall in 16 alpha levels; the art atlases CLUT8 256x128 in
VRAM), so E3's internal scale only magnifies their texels. After this task the Metal backend upscales such textures
by 4 at decode with an edge-preserving resample, behind an Esc-menu row that is on by default, and the checks run
with it off so every measured scene stays where it was. The race HUD, drawn the same way, gains the same.

## Read first
- CLAUDE.md, docs/decisions.md (D-015, D-016, D-018: the decision this task carries out, with the prototype's
  method and figures), docs/metal-backend.md ("Textures", "Internal scale", "Mipmaps"; the file's shape, since it
  gains a section), docs/ge-backend.md (section 2: what a `DrawCall` carries; `through`)
- src/gpu/metal_textures.mm (`content_key`, `decoded_texture`: the cache, the decode, the upload),
  src/gpu/metal_draw.mm (lines 385 to 430: `uv_transform` in through mode, `find_framebuffer_texture`, the sampler
  bits, the call to `decoded_texture`), src/gpu/metal_backend.hpp (the cache's types, `CachedTexture`, `switches_`,
  `stats_`), src/gpu/metal_trace.mm and the end-of-run stats line in src/gpu/metal_backend.mm (where a count is
  printed), src/gpu/metal_backend.mm's header comment (how the files split by concern)
- src/profile/enhancements.cpp (the option table and how a game option is read: `settings::game_option`), the
  backend's own switches (how `switches_.sharp` is read from the environment, so the backend can read a game option
  or a variable the same way: the option is read once a frame at most, not per draw)
- The prototype: out/fe_tex/upscale_proto.py in the main checkout (read-only for you), and its inputs and outputs
  there (font2.png, vram_a2.png, strip2.png are the game's own textures: never copy them into the repository; the
  `*_4x.png` and `*_cmp.png` show the expected result)
- tools/scale_check.sh (the model for the new check: captures at an internal scale, the centre-pixel reduction,
  the comparison with imgdiff), tools/frame_regress.sh (`--out`, the scene table and each scene's limit; how the
  environment reaches a run), tools/hud_check.py, tools/imgdiff.py, tools/purelib/port.py (`ORIGINAL_PACING`,
  `SCRATCH_SETTINGS`), tools/menu_check.sh (the expected Video rows), docs/verification.md (the pin paragraph;
  "Which path for which change"), docs/controls.md (the game rows), docs/release.md (settings.ini), README.md (the
  switches and tools tables)

## Deliverable
One or two commits on the branch.
- **The scaler**, in a new `src/gpu/sprite_upscale.cpp` with a small header (plain C++, no Metal: a function from an
  RGBA8 image W x H to 4W x 4H), listed in the CMake sources beside the backend's files. The prototype's method,
  exactly: separable Catmull-Rom (the weights `(-t^3 + 2t^2 - t)/2, (3t^3 - 5t^2 + 2)/2, (-3t^3 + 4t^2 + t)/2,
  (t^3 - t^2)/2` for the four taps, sample centres at `(o + 0.5)/4 - 0.5`, edges clamped) over premultiplied RGBA
  with the alpha divided by the texture's peak alpha (the largest alpha in it; a texture with no alpha at all is
  left as it is); then the colour unpremultiplied (flat colours stay flat at the edges) and clamped. A texture is
  "mask-like" when at least 60% of its texels have alpha 0 or within 1 of the peak: its coverage goes through a
  smoothstep of half-width 0.22 about 0.5 (`t = clamp((a - 0.28) / 0.44, 0, 1); a = t*t*(3 - 2t)`), else the
  resampled coverage stands; the alpha is then multiplied back by the peak. Integer or float arithmetic as you
  like, but the output must match the prototype's on the three inputs to within 2 levels per channel (write a
  small `tools/sprite_proto_check.py` that runs the prototype's maths on an RGBA PNG and compares with the port's
  output of the same texture, dumped by a switch described below; or run the prototype's own file). Cost: a
  256x256 texture in well under 50 ms on this Mac; note the figure.
- **The backend**: `decoded_texture` takes whether to upscale. The caller (metal_draw.mm, where it is called for a
  texture from guest memory) asks for it when the draw is a **2D draw**: through mode, or a transformed draw whose
  projection is orthographic (the w row of the projection matrix, `projection[3]`, `[7]` and `[11]`, all 0) with
  lighting off (the TEAM screen's rotating ship is drawn orthographic but lit: it is a model, not art, and stays
  plain); and the texture is not a target's, the format is a palette one (CLUT4, CLUT8, CLUT16, CLUT32) or 16-bit
  (5650, 5551, 4444), the draw samples one level, and the option is on; never for 8888 (the movie and TV pictures),
  never for a mipmapped texture, never for a perspective draw. (Replan 2026-10-11, after the first run: the menus'
  text and art and the race HUD are transformed orthographic draws, not through mode; through mode alone reaches
  three textures in the whole frontend route. The measured orthographic rule passed six of seven scenes, team_select
  at 0.0585 of 0.06 with the ship included; the lighting test is meant to take the ship out of it. Report the
  team_select figure with the ship excluded.) The cache key includes the choice (the same texture may be cached plainly for a transformed draw and
  upscaled for a through-mode one). The `MTLTexture` is 4W x 4H; through-mode `uv_transform` already divides by the
  GE's width and height, so nothing else moves. An upscaled texture samples linear in both directions whatever the
  GE's filters say (the sampler bits), with the GE's wrap. `fragment.level` keeps the GE's size (no mips). The
  stats gain the count of upscaled textures and their total scaler time, printed in the end-of-run line and the
  `PURE_METAL_LOG` run line beside `decoded`. A dump switch for the check and the next task: `PURE_SPRITE_DUMP=DIR`
  writes each upscaled texture once as `DIR/<key as 16 hex digits>.png` (the output) and `DIR/<key>.src.png` (the
  decoded input), through a small PNG writer of your own or the framework's (stb_image_write is in
  vendor/portablekit/third_party; use what the framework links). The dump is for local use only: its folder is
  under out/.
- **The option**: in `src/profile/enhancements.cpp`'s table, after the two rows there: key `sprite_upscale`, label
  `Text and sprites`, choices `Original`, `Upscaled`, default `Upscaled` (index 1), tab Video, description along the
  lines of "The menus' text and art and the race HUD are small bitmaps on the PSP. Upscaled redraws them four times
  finer with smooth edges. Metal only: the Vulkan renderer draws the originals until a texture pack exists." The
  backend reads `settings::game_option("sprite_upscale")` once per display list (or frame), not per draw. Log once
  at the first upscale `[pure] sprite upscale: on (game.sprite_upscale)` and `[pure] sprite upscale: off` at start
  when off (the backend's own log line is fine).
- **The pin**: `tools/purelib/port.py`'s `ORIGINAL_PACING` tuple gains `PURE_SPRITE_UPSCALE` (rename the constant and
  its docstring if the name no longer fits: it now covers the enhancements in general), `SCRATCH_SETTINGS` gains
  `game.sprite_upscale=0`; `--env PURE_SPRITE_UPSCALE=1` wins as the others do.
- **`tools/sprite_check.sh [--out DIR] [--wait SECONDS]`**, in the shape of tools/scale_check.sh: the scenes `title`,
  `main_menu`, `class_select`, `team_select`, `race_hud`, `tt_hud`, `fp_hud` (not zone_hud: the Zone HUD has no
  CURRENT or LAP label for hud_check) captured headless on Metal at
  `PURE_INTERNAL_SCALE=4` twice through `tools/frame_regress.sh --out` (its scene selection if it has one, else the
  whole suite), with `PURE_SPRITE_UPSCALE=0` and with `1`. PASS when, for every scene: the `1` capture is 1920x1088;
  its centre-pixel reduction to 480x272 (scale_check's rule and code, shared or copied with a note) is within the
  scene's own frame_regress limit of `ref/<scene>.png` at the scene's tol (the picture is the same picture); the
  full `1` capture differs from the full `0` capture in at least 1% of pixels at tol 24 (the detail is there; print
  the fraction); the three race scenes' `1` captures pass `tools/hud_check.py`; and the `main_menu` run's stats line
  says at least 2 textures were upscaled with a total scaler time under 2000 ms. Print a table; `sprite_check: PASS`
  or `FAIL` last; exit 0 only on PASS; the captures and reductions under `--out` (default out/sprite_check).
- **`tools/menu_check.sh`**: the expected Video rows gain `Text and sprites` after `Flashes` on both shells.
- **`tools/gerec/metal_check.sh`** (replan): its Metal lane runs `PureNative --replay` outside port.py's pin, so it
  reads the settings' default (Upscaled) and its Metal-against-Vulkan comparison would move; set
  `PURE_SPRITE_UPSCALE=0` in that lane's environment (a one-line change with a comment naming this task), and say in
  the Result whether `tools/gerec/metal_check.sh` still passes.
- **Docs**: docs/metal-backend.md (a section "Sprite upscale (task 073)": the rule for which textures, the method,
  the key, the sampler, the stats, the dump switch, the cost figures), docs/controls.md (the row and
  `game.sprite_upscale`), docs/verification.md (the pin paragraph; the "Which path" table gains the check),
  docs/release.md (settings.ini: `game.sprite_upscale`, default 1), README.md (the switches table:
  `PURE_SPRITE_UPSCALE=0|1`, `PURE_SPRITE_DUMP=DIR`; the tools table: `tools/sprite_check.sh`,
  `tools/sprite_proto_check.py` if written). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/sprite_check.sh` PASS: seven scenes, each reduced within its limit, each differing at full size, the
      HUD found in the three race scenes (race_hud, tt_hud, fp_hud), the main menu's upscales under 2 s in all
- [ ] the port's upscale of the prototype's three inputs matches the prototype within 2 levels per channel (the
      check script or the prototype's own run, figures in the Result)
- [ ] `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` PASS with the new row
- [ ] `tools/frame_regress.sh` PASS 18/18 and `tools/scale_check.sh` PASS (the pin on: unchanged)
- [ ] `tools/hud_check.sh` 61 of 61 (the pin on)
- [ ] a 2200-flip frontend run with `--env PURE_SPRITE_UPSCALE=1` at `PURE_INTERNAL_SCALE=4` prints the `on` line
      and its stats line counts upscaled textures; a run at scale 1 with the option on also upscales (the choice does
      not depend on the scale) and still passes the `main_menu` scene's limit after reduction (there is none: compare
      the 480x272 capture directly within the limit)
- [ ] a race at internal scale 4 with the option on holds 60 fps in the Metal window (the scale check's perf
      figures or `tools/run_boot.py --window` with the fps line; the figure in the Result)
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/sprite_check.sh && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && tools/scale_check.sh && python3 tools/docs_check.py`

## May touch
- src/gpu/sprite_upscale.cpp and .hpp (new), src/gpu/metal_textures.mm, src/gpu/metal_draw.mm,
  src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_trace.mm, src/gpu/metal_types.hpp, CMakeLists.txt
  (the source list only)
- src/profile/enhancements.cpp, src/profile/enhancements.hpp
- tools/sprite_check.sh (new), tools/sprite_proto_check.py (new, optional), tools/menu_check.sh,
  tools/purelib/port.py, tools/run_boot.py (docstring), tools/gerec/metal_check.sh (the pin line only)
- docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/release.md, README.md,
  docs/tasks/073-sprite-upscale.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, vendor/, patches/, src/gpu/shaders/ (the shader needs no change: say so
  if it does and stop), src/host/, src/profile/test_hooks.*, tools/frame_regress.sh, tools/scale_check.sh,
  tools/hud_check.*, tools/imgdiff.py, ref/, docs/decisions.md, docs/status.md, anything not listed above

## Estimated turns
60

## Escalate when
- the through-mode UV path does not sample a larger texture in place (the reduced scene fails its limit with the
  option on): report which draws move and stop
- the scaler's output differs from the prototype's by more than 2 levels on any of the three inputs after a
  careful look at the arithmetic (report the worst pixel and the two values)
- the main menu's upscales take over 2 s, or a race at scale 4 drops under 60 fps with the option on
- a shader change, a vendor change or a change under include/psprecomp/ would be needed; a build takes over
  5 minutes

## Result

Status: DONE

**First run (BLOCKED, 2026-10-11).** The brief's premise did not hold. The menus' text and art and the race HUD are
transformed draws under an orthographic projection, not through-mode draws. In the port's draw log of the main menu
(flip 4700, 32 draws) the clear is the only through-mode draw, and PPSSPP's `ref/main_menu.ppdmp` and
`ref/vineta_k_start.ppdmp` (the HUD, draws 839-866) agree. Through mode alone reaches three small textures in the
whole frontend route, none of them in a checked scene, so with the original rule sprite_check differed from the
plain captures in 0.0000 of the pixels on all seven scenes. The first run also found that zone_hud has no CURRENT or
LAP label for hud_check. An uncommitted build with an orthographic rule passed six of seven scenes. The brief was
replanned (81b03ea): a 2D draw is through mode, or orthographic with lighting off; fp_hud replaces zone_hud;
metal_check's replays are pinned.

**This run.** The branch holds the scaler, the backend's rule as amended, the option row, the pin, sprite_check,
sprite_proto_check, the metal_check pin line and the docs. Commits: ba11b95, 63e89ed, 365c5a0, plus the merge of the
amended brief.

- **The rule** (metal_draw.mm). A texture is upscaled when the draw is through mode, or transformed with
  `projection[3]`, `[7]` and `[11]` all 0 and `lighting_enabled` off. The other conditions are as briefed: the texture
  is not a target's, the format is CLUT4/8/16/32 or 5650/5551/4444, the draw samples one level, and the option is on.
  The race's 3D scenes stay plain: race_hud's capture with the option on differs from the one with it off in 1.6% of
  its pixels, all of them in the HUD.
- **The TEAM ship and the lighting test.** The lighting test leaves out nothing in these scenes. No frontend draw is
  lit (docs/metal-backend.md, "The 3D check", and `team.gerec`'s draws), and the TEAM SELECTION ship is one unlit
  orthographic strip of a CLUT8 256x128 picture (the port's recording, and PPSSPP's draw 41). It is art, and it is
  upscaled. team_select is 0.0585 of its 0.06 limit. With the ship at its plain value it would be about 0.054: the
  ship's rectangle holds 1221 of the 7643 differing pixels with the option on, and 574 with it off.
- **The scaler against the prototype.** The match is exact. `tools/sprite_proto_check.py` on the 25 textures a main
  menu run dumps (`PURE_SPRITE_DUMP`) finds a largest difference of 0 on every one. The prototype's three inputs are
  among them, with identical decoded pixels: font2 = `d231aa0c90948bec`, vram_a2 = `13971c915eaa2601`, strip2 =
  `7ea636709ae8ed8f`. The prototype file itself, run on copies of its inputs in a scratch folder, gives the port's
  bytes. The scaler runs in double precision with the prototype's order of operations and `#pragma clang fp
  contract(off)`. One departure, documented: a texture whose alpha is 0 everywhere keeps its colour.
- **Cost.** `upscale_sprite` at -O2 on the M4 Pro, best of 10: 64x64 0.24 ms, 128x128 1.05 ms, 256x256 4.45 ms (mean
  5.07 ms), 512x512 18.2 ms. Headless route totals: frontend to flip 2200, 14 textures in 46 to 53 ms; main menu, 25 in
  66 to 70 ms; race routes, 49 in 123 to 129 ms.
- **2200-flip frontend runs** with `--env PURE_SPRITE_UPSCALE=1`, headless on Metal:
  - `PURE_INTERNAL_SCALE=4`: the `[pure] sprite upscale: on (game.sprite_upscale)` line; the line at flip 1800 says
    `297 decoded, 12 upscaled (24.2 ms)`; the exit line says `; 14 textures upscaled (53.2 ms)`.
  - Scale 1: the same line, and 14 upscaled (46.3 ms), so the choice does not depend on the scale.
  - The `main_menu` scene at scale 1 with the option on, compared directly at 480x272: 0.0392 within 0.05. The whole
    suite at scale 1 with the option on passes 18/18, though nine menu scenes move more than 0.03 from their measured
    values (class_select 0.0596 of 0.07, team_select 0.0544 of 0.06).
- **A race at internal scale 4 with the option on, in the Metal window.** The setup: `main_menu.txt` +
  `single_race.txt` without shots, an empty stick, `PURE_PACED_FROM=6000`, flip 9850, `PURE_METAL_TRACE`, and
  `tools/frame_times.py --long 25 --fps 60 --from 6250`. Results: 3601 frames in 60.1 s, mean 16.68 ms, 99th
  percentile 18.57 ms, longest 20.88 ms, 0 over 25 ms. On screen: 3601 pictures, interval mean 16.68 ms, longest
  25.00 ms, 0 over. It holds 60 fps; 51 textures were upscaled over the run, 219 ms in all.
- **`tools/gerec/metal_check.sh`** with `PURE_SPRITE_UPSCALE=0` on its replays: PASS, unchanged. The TEAM frames show
  0 pixels over tol 24; race frame 6016 shows 2 pixels (0.000015); step 4b on race_warm shows 0.0804, reported only.
  This used the main checkout's recordings, linked. With the option on, the TEAM replay would be 0.0585, a FAIL
  against its 0.02 bar, so the pin is needed.
- **The pin's checks.** `tools/hud_check.sh` passes 61 of 61. The frame regression suite passes 18/18, unchanged
  from its measured values. `tools/scale_check.sh` passes with the same figures as docs/metal-backend.md's table
  (title 0.0035 up to tt_hud 0.0303; bloom +1.07%, -0.16%, -0.17%). `tools/controls_check.py` is OK.

Changed:
- New: src/gpu/sprite_upscale.cpp, src/gpu/sprite_upscale.hpp, tools/sprite_check.sh, tools/sprite_proto_check.py.
- Backend: src/gpu/metal_draw.mm, src/gpu/metal_textures.mm, src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm,
  src/gpu/metal_trace.mm, src/gpu/metal_types.hpp, CMakeLists.txt (source list).
- Profile: src/profile/enhancements.cpp, src/profile/enhancements.hpp.
- Tools: tools/purelib/port.py, tools/run_boot.py (docstring), tools/menu_check.sh, tools/gerec/metal_check.sh (the
  pin line).
- Docs: docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/release.md, README.md,
  docs/tasks/073-sprite-upscale.md (this Result).

Verify output (`tools/verify_task.sh 073`, last 20 lines):
```
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

scale check: PASS, scale 4: 18/18 scenes within 5% at tol 24, 3/3 bloom regions within 10% (0m 47s)
docs_check: 33 files, 0 findings: PASS
verify 073: PASS
```
The same run's sprite_check and menu_check lines:
```
title           1920x1088   0.0198   0.05   24   0.0213    -  PASS
main_menu       1920x1088   0.0411   0.05   24   0.0359    -  PASS
class_select    1920x1088   0.0621   0.07   24   0.0583    -  PASS
team_select     1920x1088   0.0585   0.06   24   0.0689    -  PASS
race_hud        1920x1088   0.0414    0.1   32   0.0156  yes  PASS
tt_hud          1920x1088   0.0411   0.12   32   0.0213  yes  PASS
fp_hud          1920x1088   0.0413   0.11   32   0.0203  yes  PASS
main_menu run: 25 textures upscaled in 66.4 ms (at least 2, under 2000 ms): PASS
sprite_check: PASS
menu_check: PASS   (metal)
menu_check: PASS   (vulkan)
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
```

Open questions:
1. team_select sits at 0.0585 of its 0.06 limit with the option on, and class_select at 0.0621 of 0.07. The ship
   picture is about 0.005 of it. A run-to-run wobble there would fail sprite_check, although three headless runs (one
   of them before the lighting test) gave the same figures to the pixel. If more headroom is wanted, sprite_check
   could keep the suite's limits and add a margin of its own, or the reduced comparison could be made against the
   plain capture at scale 4 instead of the reference.
2. The exit line carries the count at its end (`... in S s; N textures upscaled (T ms)`), not beside "textures
   decoded". `tools/purelib/logs.py`'s `METAL_EXIT_RE`, outside May touch, reads ", N framebuffer textures" right after
   "textures decoded". The line every 600 frames has the count beside `decoded`.
3. docs/metal-backend.md "The 3D check" says the TEAM screen's "rotating ship is ten textured quads under an
   orthographic projection". In `team.gerec` the ship is one CLUT8 256x128 picture drawn as a single strip, and the
   other strips are untextured. That sentence was left as it was. The lighting test, as briefed, excludes nothing in
   the frontend today.
4. Upscaled textures are 16 times the memory of the plain ones: 2 MB for a 256x128 atlas, 16 MB for the one 512x512
   CLUT8 picture. The cache is capped by count (1024), not by bytes, and the runs here kept 51 upscaled textures.

## Review
Verify rerun: `tools/verify_task.sh 073` from the main checkout after the merge, 2026-10-11 18:40 (out/073_gate.log):
PASS. sprite_check 7/7 (title 0.0198, main_menu 0.0411, class_select 0.0621 of 0.07, team_select 0.0585 of 0.06,
race_hud 0.0414, tt_hud 0.0411, fp_hud 0.0413 reduced against the references; 1.6 to 6.9% of the full captures
changed; the HUD found in the three race scenes; 25 textures upscaled in 66 ms on the main menu), menu_check both
shells, suite 18/18, scale_check 18/18 and 3/3 bloom regions, docs_check. After it: hud_check 61 of 61,
`tools/gerec/metal_check.sh` PASS (25 s), the window suites 7/7 on the Metal shell and 7/7 on the Vulkan shell with
the Vulkan backend (a first Vulkan-shell run without `--backend vulkan` ran the Metal backend under that shell, a
pairing with no measured column, and failed one scene: the gate's invocation, not the change).
Spot-read: the rule in metal_draw.mm (through, or orthographic with lighting off; one level; palette or 16-bit;
not a target) and the forced linear sampler; the cache key hashing the choice; the option read once a frame; the
scaler's header stating the prototype's maths and its one departure (an all-transparent texture keeps its colour);
the dump switch off the frame path; the metal_check pin.
Merged: ddad728 into batch/m2.
Notes: the first run's BLOCKED was right: the brief said through mode and the menus are orthographic transformed
draws; the replan (81b03ea) fixed the rule and the Zone HUD scene. The lighting test excludes nothing today (no
frontend draw is lit; the TEAM ship is an unlit picture and is upscaled, about 0.005 of team_select's figure).
Follow-ups: team_select and class_select sit near their limits in sprite_check (0.0585 of 0.06, 0.0621 of 0.07):
if a run wobbles, compare the reduced capture against the plain scale-4 capture with a margin of the check's own
instead of the reference; the texture cache is capped by count, and an upscaled texture is 16x the bytes (a byte
cap, small); docs/metal-backend.md's "The 3D check" sentence on the TEAM ship ("ten textured quads") predates the
recording's one strip; the pack for the Vulkan renderer is task 074.
