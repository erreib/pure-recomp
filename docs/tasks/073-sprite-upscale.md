# 073: The menus' and HUD's bitmap art upscaled (E7)

Milestone: E7 (Erik, 2026-10-11; D-018) | Branch: task/073-sprite-upscale | Status: OPEN

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
  texture from guest memory) asks for it when the draw is through mode, the texture is not a target's, the format is
  a palette one (CLUT4, CLUT8, CLUT16, CLUT32) or 16-bit (5650, 5551, 4444), the draw samples one level, and the
  option is on; never for 8888 (the movie and TV pictures), never for a mipmapped texture, never for a transformed
  draw. The cache key includes the choice (the same texture may be cached plainly for a transformed draw and
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
  `main_menu`, `class_select`, `team_select`, `race_hud`, `tt_hud`, `zone_hud` captured headless on Metal at
  `PURE_INTERNAL_SCALE=4` twice through `tools/frame_regress.sh --out` (its scene selection if it has one, else the
  whole suite), with `PURE_SPRITE_UPSCALE=0` and with `1`. PASS when, for every scene: the `1` capture is 1920x1088;
  its centre-pixel reduction to 480x272 (scale_check's rule and code, shared or copied with a note) is within the
  scene's own frame_regress limit of `ref/<scene>.png` at the scene's tol (the picture is the same picture); the
  full `1` capture differs from the full `0` capture in at least 1% of pixels at tol 24 (the detail is there; print
  the fraction); the three race scenes' `1` captures pass `tools/hud_check.py`; and the `main_menu` run's stats line
  says at least 2 textures were upscaled with a total scaler time under 2000 ms. Print a table; `sprite_check: PASS`
  or `FAIL` last; exit 0 only on PASS; the captures and reductions under `--out` (default out/sprite_check).
- **`tools/menu_check.sh`**: the expected Video rows gain `Text and sprites` after `Flashes` on both shells.
- **Docs**: docs/metal-backend.md (a section "Sprite upscale (task 073)": the rule for which textures, the method,
  the key, the sampler, the stats, the dump switch, the cost figures), docs/controls.md (the row and
  `game.sprite_upscale`), docs/verification.md (the pin paragraph; the "Which path" table gains the check),
  docs/release.md (settings.ini: `game.sprite_upscale`, default 1), README.md (the switches table:
  `PURE_SPRITE_UPSCALE=0|1`, `PURE_SPRITE_DUMP=DIR`; the tools table: `tools/sprite_check.sh`,
  `tools/sprite_proto_check.py` if written). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/sprite_check.sh` PASS: seven scenes, each reduced within its limit, each differing at full size, the
      HUD found in the three race scenes, the main menu's upscales under 2 s in all
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
  tools/purelib/port.py, tools/run_boot.py (docstring)
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

Status: BLOCKED

The brief's premise does not hold: the menus' text and art and the race HUD are not drawn in through mode. They are
transformed draws under an orthographic projection, both in the port and in PPSSPP's dumps. Under the brief's rule
("never for a transformed draw") nothing in the seven scenes is upscaled, so `tools/sprite_check.sh` fails on every
scene. Widening the rule would get around the Verify line, which this task may not do, so the rule is left for the
planning session.

Evidence:
- The port's draw log of the `main_menu` scene (`PURE_METAL_LOG=1`, route `main_menu.txt`, frame 4700, 32 draws): the
  clear (#0) is the only through-mode draw. The text is transformed sprites from CLUT4 256x128 (`0x8cde860`, #3-5 and
  #29-31) and CLUT4 256x256 (`0x8ce3c10`, #24-28). The art is transformed tristrips from the CLUT8 256x128 VRAM atlases
  (`0x417be80` to `0x41be500`, #14-23), CLUT8 256x32 (`0x4179a40`, #2) and CLUT8 8x1 (#19). PPSSPP's dump agrees
  (`tools/ppsspp/ppdmp.py draws ref/main_menu.ppdmp --all --vt`): draw 0 is the only `thru` draw.
- The race HUD (`ref/vineta_k_start.ppdmp`, draws 839-866: CLUT4 512x256 `0x08cc84d0` and CLUT4 256x128 `0x08cd9290`) is
  transformed too. The frame's 11 through-mode draws are the bloom chain, the billboard target and one CLUT4 256x32
  (`0x08e5d8a0`).
- The whole frontend route to flip 4702 has these through-mode textured draws: 8888 512x512 movie pictures, plus three
  CLUT4 textures (512x64 and 256x32 in flips 5-123, 64x64 in flips 1090-4305). None of them is in a checked scene. The
  same route has 30001 transformed draws from the CLUT4 256x256 font, 11331 from CLUT4 256x128 and 4400 from CLUT8
  256x128. With the briefed rule each route upscales 3 to 6 textures (main_menu 3 in 3.6 ms; the race routes 6 in 12
  to 15 ms), and the `1` captures equal the `0` captures (the "vs 0" column below).
- A second problem, separate from the upscale: `zone_hud` fails `tools/hud_check.py` with the option off as well as on.
  The Zone HUD has no CURRENT or LAP label, so both regions hold 0 yellow pixels. `race_hud` and `tt_hud` pass.

A measured alternative, not committed: a temporary build that also upscaled transformed draws with an orthographic
projection (the w row `projection[3] == projection[7] == projection[11] == 0`), with the same check:

| Scene | Reduced against the reference (limit) | Full capture against the 0 capture | HUD |
|---|---|---|---|
| title | 0.0198 (0.05) | 0.0213 | - |
| main_menu | 0.0411 (0.05) | 0.0359 | - |
| class_select | 0.0621 (0.07) | 0.0583 | - |
| team_select | 0.0585 (0.06) | 0.0689 | - |
| race_hud | 0.0414 (0.10) | 0.0156 | yes |
| tt_hud | 0.0411 (0.12) | 0.0213 | yes |
| zone_hud | 0.0337 (0.09) | 0.0120 | no |

Six of seven scenes pass; zone_hud fails only because of the hud_check problem above. Textures upscaled per route:
frontend 12 (23 ms), main_menu 25 (68 ms), Single Race 49 (125 ms), Time Trial 49 (122 ms), Zone 39 (99 ms). team_select
comes close to its limit. The TEAM screen's rotating ship is also drawn under an orthographic projection
(docs/metal-backend.md, "The 3D check"), so this rule upscales it too. Not measured under that rule: which race
textures it takes beyond the HUD, and the race's frame rate at scale 4.

The scaler against the prototype passes. That build's dump (`PURE_SPRITE_DUMP`) holds the prototype's three inputs
with identical decoded pixels: font2 = `d231aa0c90948bec`, vram_a2 = `13971c915eaa2601`, strip2 = `7ea636709ae8ed8f`.
`tools/sprite_proto_check.py out/sprites_ortho --inputs .../font2.png,.../vram_a2.png,.../strip2.png` reports a largest
difference of 0 on all three (PASS). The prototype file itself, run on copies of its inputs in a scratch folder, matches
the port's three outputs exactly (0 channel values differ). One thing to know: the main checkout's
`out/fe_tex/vram_a_4x.png` and `strip_4x.png` predate the last edit of `upscale_proto.py` (17:56 against 17:57) and
differ from the current prototype by up to 33 levels. `font_4x.png` is up to date.

Scaler cost on this Mac (M4 Pro), `upscale_sprite` at -O2, best of 10 runs: 64x64 0.24 ms, 128x128 1.05 ms,
256x256 4.45 ms (mean 5.07 ms), 512x512 18.2 ms.

What the branch holds (commit ba11b95), all to the brief except the draw rule's premise:
- The scaler: the prototype's method in double precision, its operations in its order, fused multiply-add off. One
  departure, documented in the header: a texture whose alpha is 0 everywhere keeps its colour instead of turning
  black.
- The backend: `decoded_texture(..., upscale)`. The key is apart from the plain one, the texture is 4W x 4H and samples
  linear with the GE's wrap. The stats count the upscaled textures and their scaler time, `PURE_SPRITE_DUMP=DIR` writes
  `<key>.src.png` and `<key>.png`, and the option is read at start and at each frame. The `[pure] sprite upscale: on
  (game.sprite_upscale)` and `... off` lines are printed.
- The option row "Text and sprites" (default Upscaled).
- The pin: `ENHANCEMENTS_OFF` (was `ORIGINAL_PACING`) plus `game.sprite_upscale=0` in `SCRATCH_SETTINGS`.
- The menu_check row, and `tools/sprite_check.sh` and `tools/sprite_proto_check.py`.
- Not written: the docs (metal-backend.md section, controls.md, verification.md, release.md, README rows), because
  they would describe a draw rule the replan will change. Also not run: the 2200-flip run and the race at 60 fps with
  the option on.

Changed: src/gpu/sprite_upscale.cpp, src/gpu/sprite_upscale.hpp (new), src/gpu/metal_textures.mm,
src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_trace.mm,
src/gpu/metal_types.hpp, CMakeLists.txt (source list), src/profile/enhancements.cpp, src/profile/enhancements.hpp,
tools/purelib/port.py, tools/run_boot.py (docstring), tools/menu_check.sh, tools/sprite_check.sh (new),
tools/sprite_proto_check.py (new), docs/tasks/073-sprite-upscale.md (this Result).

Verify output (`tools/verify_task.sh 073`; it stops at the first command):
```
each PURE_SPRITE_UPSCALE=1 capture: its size, by its blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), the full capture against the PURE_SPRITE_UPSCALE=0 one at tol 24 (at least 1%), and the race HUD (tools/hud_check.py):
scene                size  reduced  limit  tol     vs 0  HUD  result
title           1920x1088   0.0061   0.05   24   0.0000    -  FAIL (differs from the 0 capture in under 1%)
main_menu       1920x1088   0.0207   0.05   24   0.0000    -  FAIL (differs from the 0 capture in under 1%)
class_select    1920x1088   0.0193   0.07   24   0.0000    -  FAIL (differs from the 0 capture in under 1%)
team_select     1920x1088   0.0240   0.06   24   0.0000    -  FAIL (differs from the 0 capture in under 1%)
race_hud        1920x1088   0.0363    0.1   32   0.0000  yes  FAIL (differs from the 0 capture in under 1%)
tt_hud          1920x1088   0.0342   0.12   32   0.0000  yes  FAIL (differs from the 0 capture in under 1%)
zone_hud        1920x1088   0.0345   0.09   32   0.0000   no  FAIL (differs from the 0 capture in under 1%; no HUD (hud_check: 0 of 1 shots have the HUD))

main_menu run: 3 textures upscaled in 3.6 ms (at least 2, under 2000 ms): PASS

sprite check: 0/7 scenes pass, the main menu's upscales PASS (0m 34s)
sprite_check: FAIL
verify 073: FAIL (exit 1)
```
The rest of the Verify line, run separately on the same build: `tools/menu_check.sh` PASS (Video 13 rows, Text and
sprites last), `tools/menu_check.sh --shell vulkan` PASS (Video 19 rows), `tools/frame_regress.sh` PASS 18/18 (21 s),
`tools/scale_check.sh` PASS (18/18 within 5%, 3/3 bloom regions), `python3 tools/docs_check.py` PASS (33 files, 0
findings).

Open questions:
1. Which draws should be upscaled? Through mode alone reaches almost nothing. A suggestion: also transformed draws
   with an orthographic projection (measured above). Keep in mind that the TEAM screen's ship is orthographic too, and
   that the race textures beyond the HUD were not checked under that rule. A narrower test such as sprite primitives
   plus orthographic would leave out the art's tristrips.
2. The race scenes for the HUD check: zone_hud has no CURRENT or LAP labels. Use fp_hud in its place, or give
   hud_check a Zone region (SCORE).
3. The exit line carries the count at its end (`... in S s; N textures upscaled (T ms)`), not beside "textures
   decoded", because `tools/purelib/logs.py`'s `METAL_EXIT_RE` (outside May touch) expects ", N framebuffer textures"
   right after "textures decoded". The 600-frame line has it beside `decoded`.
4. `tools/gerec/metal_check.sh` runs `PureNative --replay` without going through port.py's pin. Its Metal lane
   therefore follows the settings' `game.sprite_upscale` (default Upscaled). Under the briefed rule this touches
   little, but a wider rule would move its Metal-against-Vulkan comparison unless the replay pins the option.
