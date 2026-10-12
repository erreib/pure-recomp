# 075: Texture detail at the internal scale (E5, the Metal backend)

Milestone: E5 (Erik, 2026-10-12; D-019) | Branch: task/075-texture-detail | Status: OPEN

## Goal
At internal scale S the Metal backend picks each mipmapped draw's level as the GE does for the PSP's own 480x272
pixels (task 037; D-015: the auto rule's gradient per PSP pixel, the slope rule by depth alone), so a track surface a
few ship lengths ahead is drawn from a level log2(S) coarser than the pixels could show, and isotropically, so a wall
at a grazing angle blurs along its length. After this task an Esc-menu row "Texture detail", on by default, has the
backend shift the GE's D down by 16 x log2(S) and sample the mipmapped draws anisotropically at that level, and the
checks run with it off so every measured scene stays where it was. D-019 has the figures: in a race frame 74% of the
textured draws sample 2 to 5 levels, all trilinear; the ships by the auto rule, the track by the slope rule with a
per-draw bias; none by the constant rule.

## Read first
- CLAUDE.md, docs/decisions.md (D-015, D-018 as amended, D-019: the decision this task carries out), docs/metal-backend.md
  ("Internal scale" and its table's "Mip levels" row, "Mipmaps" with "The registers and the rule" and "The level in
  the shader", "Sprite upscale" for how task 073 added a row the backend reads itself), docs/ge-backend.md (section
  2: what a `DrawCall` and its `TextureState` carry: `level_mode`, `level_bias`, `lod_slope`, the filters)
- src/gpu/shaders/ge.metal (`ge_log16`, `sample_texture`: the level computed in the shader and the `level()` sample;
  `FragmentUniforms` there and in src/gpu/metal_types.hpp: `level`, `level_range`), src/gpu/metal_textures.mm
  (`set_level_rule`, `read_sprite_upscale`: how a game option is read once a frame; `decoded_texture`: the levels
  uploaded), src/gpu/metal_draw.mm (lines 385 to 445: the sampler bits, the `levels > 1` block that calls
  `set_level_rule` and scales `fragment.level[2..3]` by the target's scale), src/gpu/metal_backend.mm (the sampler
  table in `initialize()`: 48 samplers by index bits; `begin_frame` where the sprite option is re-read),
  src/gpu/metal_backend.hpp (`samplers_`, `sprite_upscale_`, `stats_`), src/gpu/metal_trace.mm (the end-of-run
  stats line)
- src/profile/enhancements.cpp (the option table: the three rows, the Text and sprites row as the model),
  tools/purelib/port.py (`ENHANCEMENTS_OFF`, `SCRATCH_SETTINGS`, `original_pacing`), tools/menu_check.sh (the
  expected Video rows), tools/gerec/metal_check.sh (the pin line of task 073), tools/sprite_check.sh (the model for
  the new check: two captures of the scenes at scale 4 through `tools/frame_regress.sh --out`, the centre-pixel
  reduction, the comparisons, the table), tools/frame_regress.sh (the scene table: race_hud, tt_hud, fp_hud,
  zone_hud and their limits; `--only`, `--env`), tools/hud_check.py, tools/imgdiff.py, tools/png.py (reading a PNG
  for the energy measure), docs/verification.md (the pin paragraph; "Which path for which change"),
  docs/controls.md (the game rows), docs/release.md (settings.ini), README.md (the switches and tools tables)
- Apple's Metal Shading Language specification, section "Sampling": `gradient2d(dPdx, dPdy)` supplies the
  derivatives the LOD and the anisotropic filter are computed from; `MTLSamplerDescriptor.maxAnisotropy` (1 to 16).

## Deliverable
One or two commits on the branch.
- **The option**: in `src/profile/enhancements.cpp`'s table, after the Text and sprites row: key `texture_detail`,
  label `Texture detail`, choices `Original`, `Enhanced`, default `Enhanced` (index 1), tab Video, description along
  the lines of "The PSP picks each texture's level of detail for its own 480x272 pixels, so above 1x the track ahead
  and angled walls stay as soft as on the PSP. Enhanced picks the level for the pixels drawn and samples angled
  surfaces anisotropically. Shows above 1x. Metal only for now: the Vulkan renderer draws the PSP's levels." The
  backend reads `settings::game_option("texture_detail")` at start and once a frame in `begin_frame`, as the sprite
  option is read (share the reading if that stays small), never per draw; `[pure] texture detail: off` at start when
  off, `[pure] texture detail: on (game.texture_detail)` once at the first enhanced draw.
- **The level shift** (D-019 point 2): with the option on, for a draw that samples a texture with levels from guest
  memory (the `levels > 1u` block in metal_draw.mm), D is lowered by `16 * log2(target.scale)` whatever the rule.
  Carry it as a term the shader subtracts (a float in `FragmentUniforms`, for instance `level_range.y`; the
  structure's layout must match between metal_types.hpp and ge.metal, so change both and keep the 16-byte alignment),
  or fold it into `level.y` and leave `level[2..3]` unscaled for the auto rule: either way the result must be the
  same D, which the auto rule makes exact since `ge_log16` of a value divided by a power of two is the value's
  `ge_log16` minus 16 times the power. The clamp to `0 .. level_range.x` stays. At scale 1 the shift is 0.
- **Anisotropic sampling** (D-019 point 3): the sampler table gains a bit (bit 6, 64) for `maxAnisotropy` 16 (or
  the device's limit if lower: say which in the Result; `MTLDevice` has no query, 16 is Metal's maximum, so 16),
  the array growing to 128; the bit is set for an enhanced draw with levels (never for a one-level texture, a 2D
  draw, a target sampled as a texture or an upscaled sprite). In `sample_texture`, an enhanced draw samples with
  `gradient2d` instead of `level()`: `dx = dfdx(uv)`, `dy = dfdy(uv)` (the normalised coordinates after the
  divide by q, before any target placement, which does not apply to a texture with levels), `rho = max(length(dx
  * size), length(dy * size))` in texels of level 0, `k = exp2(D' / 16 - log2(max(rho, 1e-8)))`, and
  `image.sample(s, uv, gradient2d(dx * k, dy * k))`: the GPU's isotropic LOD is then D'/16, and with the
  anisotropic sampler it takes its taps along the long axis at the finer level the short axis allows. Select the
  path by a uniform (the shift term being present, or a flag), not a new pipeline: the pre-warm list
  config/metal_pipelines.txt stays as it is. Original keeps the `level()` path to the pixel: the headless suite,
  `tools/scale_check.sh` and `tools/gerec/metal_check.sh` must not move.
- **The stats**: a count of the enhanced draws printed in the end-of-run line and the `PURE_METAL_LOG` run line
  beside the mipmapped count (`M mipmapped draws (E enhanced)` or similar).
- **The pin**: `tools/purelib/port.py`'s `ENHANCEMENTS_OFF` gains `PURE_TEXTURE_DETAIL`, `SCRATCH_SETTINGS` gains
  `game.texture_detail=0`; `--env PURE_TEXTURE_DETAIL=1` wins as the others do; `tools/gerec/metal_check.sh`'s pin
  line gains `PURE_TEXTURE_DETAIL=0`; `tools/menu_check.sh`'s Video rows gain `Texture detail` after `Text and
  sprites` on both shells.
- **`tools/texture_check.sh [--out DIR] [--wait SECONDS]`**, in the shape of tools/sprite_check.sh: the scenes
  `race_hud`, `tt_hud`, `fp_hud`, `zone_hud` captured headless on Metal at `PURE_INTERNAL_SCALE=4` twice through
  `tools/frame_regress.sh --out --only`, with `PURE_TEXTURE_DETAIL=0` and with `1`. PASS when, for every scene: the
  `1` capture is 1920x1088; its centre-pixel reduction to 480x272 is within the scene's own frame_regress limit of
  `ref/<scene>.png` at the scene's tol (the picture is the same picture); the full `1` capture differs from the full
  `0` capture in at least 1% of pixels at tol 24 (print the fraction); the `1` capture holds more high-frequency
  energy than the `0` one (the mean absolute difference between each pixel and its right and lower neighbours over
  the whole picture, in pure Python through tools/png.py or NumPy if the tools already use it: print both figures
  and their ratio; the bar is a ratio above 1.0, and say in the Result what the four scenes measured); the four `1`
  captures pass `tools/hud_check.py`; and the `race_hud` run's stats line counts at least 300 enhanced draws in its
  last frame or at least 10000 over the run (whichever the line gives: say which). Also one run of `race_hud` at
  `PURE_INTERNAL_SCALE=1` with the option on, compared directly with the reference within the scene's limit (the
  shift is 0 there; only the anisotropy acts). Print a table; `texture_check: PASS` or `FAIL` last; exit 0 only on
  PASS; captures and reductions under `--out` (default out/texture_check). (Replan 2026-10-12, after the first run:
  the 1% and energy bars apply to race_hud, tt_hud and fp_hud only, since the Zone's mipmapped textures hold no
  detail between their levels where zone_hud's frame draws them (level 0 everywhere moves 0.0002 of its pixels at
  tol 24, as Enhanced does), so zone_hud keeps the reduction and the stats; and the HUD bar is on those three
  scenes, as in tools/sprite_check.sh, zone_hud's HUD having no CURRENT or LAP label.)
- **Docs**: docs/metal-backend.md (a section "Texture detail (task 075)" after "Sprite upscale": the shift, the
  gradients, the sampler bit, the stats, the log lines, the cost; the "Internal scale" table's "Mip levels" row and
  "The level in the shader" updated), docs/controls.md (the row and `game.texture_detail`), docs/verification.md
  (the pin paragraph; the "Which path" table gains the check and the shader row names it), docs/release.md
  (settings.ini: `game.texture_detail`, default 1), README.md (the switches table: `PURE_TEXTURE_DETAIL=0|1`; the
  tools table: `tools/texture_check.sh`). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/texture_check.sh` PASS: four scenes reduced within their limits, each differing at full size, each with
      more high-frequency energy, the HUD found in all four, the enhanced draws counted; race_hud at scale 1 within
      its limit
- [ ] `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` PASS with the new row
- [ ] `tools/frame_regress.sh` PASS 18/18, `tools/scale_check.sh` PASS and `tools/sprite_check.sh` PASS (the pin on:
      unchanged), `tools/gerec/metal_check.sh` PASS (its pin line extended)
- [ ] `tools/hud_check.sh` 61 of 61 (the pin on)
- [ ] a race at internal scale 4 with the option on holds 60 fps in the Metal window (the scale check's perf figures
      or `tools/run_boot.py --window` with the fps line, as task 073 measured; the figure in the Result), and the
      Original path costs nothing new (the same measure with the option off, within noise)
- [ ] with `maxAnisotropy` 1 in place of 16 (a temporary edit, not committed) the `race_hud` `1` capture differs
      from the committed one: proof that Metal applies the anisotropy through `gradient2d` (the fraction in the
      Result)
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/texture_check.sh && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && tools/scale_check.sh && tools/sprite_check.sh && python3 tools/docs_check.py`

## May touch
- src/gpu/shaders/ge.metal, src/gpu/metal_types.hpp, src/gpu/metal_textures.mm, src/gpu/metal_draw.mm,
  src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_trace.mm
- src/profile/enhancements.cpp, src/profile/enhancements.hpp
- tools/texture_check.sh (new), tools/menu_check.sh, tools/purelib/port.py, tools/run_boot.py (docstring),
  tools/gerec/metal_check.sh (the pin line only)
- docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/release.md, README.md,
  docs/tasks/075-texture-detail.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/ (config/metal_pipelines.txt included: no new pipeline), vendor/, patches/,
  src/host/, src/gpu/sprite_upscale.*, src/profile/test_hooks.*, tools/frame_regress.sh, tools/scale_check.sh,
  tools/sprite_check.sh, tools/hud_check.*, tools/imgdiff.py, tools/png.py, ref/, docs/decisions.md, docs/status.md,
  anything not listed above

## Estimated turns
60

## Escalate when
- the Original path moves: any headless suite scene, scale_check, sprite_check or metal_check figure changes with
  the pin on (report which and by how much, and stop)
- the reduced `1` capture of a scene fails its limit (report the scene, the fraction, and which draws moved if you
  can tell), or the energy ratio is at or below 1.0 for a scene
- the `maxAnisotropy` 1 against 16 comparison shows no difference at all (Metal not applying the anisotropy on the
  `gradient2d` path): report and stop, with the Original path intact
- a race at scale 4 drops under 60 fps with the option on
- a new pipeline, a vendor change, a change under include/psprecomp/ or to config/ would be needed; a build takes
  over 5 minutes

## Result

**Status: DONE.** The task was replanned once, after a BLOCKED first run. Verify passes: texture_check, menu_check on both shells, frame_regress 18/18, scale_check, sprite_check and docs_check. The Original path is the old one to the pixel. Metal applies the anisotropy through `gradient2d`, and a race at internal scale 4 holds 60 fps in the window with the option on. hud_check passes 61 of 61.

### The replan (coordinator, 2026-10-12)
The first run stopped because zone_hud cannot reach the brief's 1% bar. Its frame's mipmapped textures hold no detail between their levels: level 0 everywhere (`PURE_NO_MIPMAPS=1`) moves 0.0002 of its pixels at tol 24, the same as Enhanced. zone_change does no better (0.0000). The coordinator settled it two ways, and the brief's texture_check paragraph now says both:
1. The 1% and energy bars apply to race_hud, tt_hud and fp_hud only (`DETAIL_SCENES` in texture_check.sh). zone_hud keeps the reduction and the stats; the table prints "-" in its detail columns and gives its figures on a line below, for the record.
2. The HUD bar applies to the same three scenes, as in sprite_check: zone_hud's HUD has no CURRENT or LAP label.

### texture_check (the Verify run)
| Scene | Reduced, on (limit) | Reduced, off | On against off | Energy off | Energy on | Ratio | HUD |
|---|---|---|---|---|---|---|---|
| race_hud | 0.0467 (0.10) | 0.0363 | 0.0218 | 3.5752 | 4.0681 | 1.1378 | found |
| tt_hud | 0.0473 (0.12) | 0.0342 | 0.0244 | 3.5424 | 4.3499 | 1.2279 | found |
| fp_hud | 0.0472 (0.11) | 0.0340 | 0.0244 | 3.5210 | 4.3300 | 1.2298 | found |
| zone_hud | 0.0346 (0.09) | 0.0345 | (0.0002) | (2.2434) | (2.2444) | (1.0004) | - |

- The energy is the mean absolute difference, per channel, between each pixel and its right and its lower neighbour, over the whole 1920x1088 capture. The bar is a ratio above 1.0, on the three Vineta K scenes.
- Reduction against the reference moves the Vineta K scenes about +0.011 toward their limits. The reference is the PSP's coarser level, so the finer texels are not the PSP's.
- race_hud at scale 1 with the option on scores 0.0162 against its reference (limit 0.10; 0.0148 with it off).

### The other figures the brief asks for
- **Enhanced draws.** The exit line gives the count over the run, so the 10000 bar applies. The race_hud route with the option on had 192857 mipmapped draws, 192778 of them enhanced; the other 79 are 2D draws with levels, which D-019 leaves alone. The 600-frame line at flip 6000 read 162803 (162770 enhanced). The window race run had 1519618 (1518711 enhanced).
- **Frame rate at scale 4 in the Metal window.** Measured as task 073 did: `main_menu.txt` + `single_race.txt` without their shots, a fresh stick each run, `PURE_PACED_FROM=6000`, to flip 9850, `PURE_METAL_TRACE`, then `tools/frame_times.py --long 25 --fps 60 --from 6250`.

  | Option | Frames | Mean | 99th pct | Longest | Over 25 ms | On screen: longest, over 25 ms | GPU waits a frame | Submit a frame |
  |---|---|---|---|---|---|---|---|---|
  | off | 3601 in 60.1 s | 16.68 ms | 18.64 ms | 23.15 ms | 0 | 33.33 ms, 1 | 0.86 ms | 2.07 ms |
  | on, flips 7023-9850 | 2828 in 47.2 s | 16.68 ms | 18.52 ms | 21.32 ms | 0 | 25.00 ms, 0 | 0.86 ms | 2.03 ms |
  | on, flips 6250-6967 | 718 in 12.0 s | 16.68 ms | 18.49 ms | 22.06 ms | 0 | 37.50 ms, 1 | 0.94 ms | 2.45 ms |

  - The on run is split where the window was covered (flips 6968 to 7022). There macOS held a drawable back for 0.97 s, the minute's one frame over 25 ms; not a player's case.
  - A second on run, the window off the screen throughout: 3601 frames in 60.1 s, mean 16.68 ms, longest 20.42 ms, none over 25 ms.
  - The race holds 60 fps with the option on.
  - Original costs nothing new: it is the same code (below), and its 0.86 ms of GPU waits a frame is task 067's 0.94 ms within noise.
- **maxAnisotropy.** 16, Metal's maximum (`MTLDevice` has no query for a lower limit). I put 1 in its place temporarily, then reverted it; the rebuilt capture equals the committed one to the pixel. Against the committed build, race_hud's capture with the option on differs in:

  | | tol 0 | tol 2 | tol 24 |
  |---|---|---|---|
  | race_hud | 264862 of 2088960 (0.1268) | 0.0065 | 0.0004 (847 pixels) |
  | tt_hud | 0.1305 | 0.0135 | 0.0005 |

  The differences lie on the track at grazing angles, the crowds and the far scenery.

### The Original path
- **Pixels.** `tools/refactor_check.sh` compared captures from the base commit (eb4f5f6) with this build, the pin on, three ways: at scale 1, at `PURE_INTERNAL_SCALE=4`, and at 4 with `PURE_SPRITE_UPSCALE=1`. Each time all 18 scenes had 0 differing pixels.
- **Counts.** The same on all 7 routes once the new `E enhanced` fields are taken out.
- **The suites.** frame_regress gives the base build's figures. scale_check matches task 066's table to the digit, sprite_check task 073's.
- **hud_check** (the Metal window, the pin on, `[pure] texture detail: off` in its log): `hud_check: 61 of 61 shots have the HUD`.

### What the commits hold
- **fbc1047, the code.**
  - The Texture detail row: Original or Enhanced, default Enhanced, `game.texture_detail`, `PURE_TEXTURE_DETAIL`. The backend reads it at start and in `begin_frame` (`read_game_options`, shared with Text and sprites), and prints `[pure] texture detail: off` at start when off or `[pure] texture detail: on (game.texture_detail)` at the first enhanced draw.
  - The shift: `level_range.y` holds 16 log2(S), which the shader subtracts from D after the rule, before the clamp.
  - The gradient path: `level_range.z` 1 selects it, `gradient2d` with k scaled to D'/16. The struct keeps its 240 bytes, and there is no new pipeline.
  - The sampler table: 128 samplers; bit 6 sets `maxAnisotropy` 16.
  - The counts: `M mipmapped draws (E enhanced, L mip levels decoded after the first)` in the exit line, which `logs.METAL_EXIT_RE` still parses, and `..., M mipmapped draws (E enhanced)` on the 600-frame line.
  - The pin: in port.py, run_boot's docstring and metal_check's replay line; the new row in menu_check's Video lists on both shells.
- **1caf51f, the check and the docs.**
  - texture_check's per-scene bars.
  - The brief's replan note.
  - docs/metal-backend.md: the "Texture detail (task 075)" section (the shift, the gradients, the sampler bit, the counts, the log lines, the checks, the cost), plus the switch row, the Files rows, the "Mip levels" row, "The level in the shader" and the Vulkan-differences note.
  - docs/controls.md: the fourth Game row and `game.texture_detail`.
  - docs/verification.md: the checks table, the Esc menu row, both pin paragraphs, and "Which path" (the shader row names the check, plus a texture detail row).
  - docs/release.md: `game.texture_detail`, default 1.
  - README.md: `PURE_TEXTURE_DETAIL=0|1` and `tools/texture_check.sh`.

### Changed
src/gpu/shaders/ge.metal, src/gpu/metal_types.hpp, src/gpu/metal_textures.mm, src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_trace.mm, src/profile/enhancements.cpp, src/profile/enhancements.hpp, tools/texture_check.sh (new), tools/menu_check.sh, tools/purelib/port.py, tools/run_boot.py (docstring), tools/gerec/metal_check.sh (the pin line), docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/release.md, README.md, docs/tasks/075-texture-detail.md (the replan note and this Result).

### Verify output (last 20 lines)
```
sprite check 2026-10-12 09:07: title main_menu class_select team_select race_hud tt_hud fp_hud at internal scale 4, PURE_SPRITE_UPSCALE 0 and 1, headless on Metal, into /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a102bf65cc19f758b/out/sprite_check
  PURE_SPRITE_UPSCALE=0: 5 [pure] sprite upscale: off
  PURE_SPRITE_UPSCALE=1: 5 [pure] sprite upscale: on (game.sprite_upscale)

each PURE_SPRITE_UPSCALE=1 capture: its size, by its blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), the full capture against the PURE_SPRITE_UPSCALE=0 one at tol 24 (at least 1%), and the race HUD (tools/hud_check.py):
scene                size  reduced  limit  tol     vs 0  HUD  result
title           1920x1088   0.0198   0.05   24   0.0213    -  PASS
main_menu       1920x1088   0.0411   0.05   24   0.0359    -  PASS
class_select    1920x1088   0.0621   0.07   24   0.0583    -  PASS
team_select     1920x1088   0.0585   0.06   24   0.0689    -  PASS
race_hud        1920x1088   0.0414    0.1   32   0.0156  yes  PASS
tt_hud          1920x1088   0.0411   0.12   32   0.0213  yes  PASS
fp_hud          1920x1088   0.0413   0.11   32   0.0203  yes  PASS

main_menu run: 25 textures upscaled in 67.0 ms (at least 2, under 2000 ms): PASS

sprite check: 7/7 scenes pass, the main menu's upscales PASS (0m 38s)
sprite_check: PASS
docs_check: 33 files, 0 findings: PASS
verify 075: PASS
```

### Open questions
1. **metal_check is skipped, as instructed;** its replay line carries the pin. The main checkout's out/gerec recordings date from 2026-10-06, before task 037, so they hold one level each. A replay of them never reaches the levels or this option. Recordings made since task 040 would.
2. **refactor_check's count comparison** has printed "counts FAIL" on every run since task 073. Its strip of the GPU-wait clause expects that clause at the end of the exit line, and task 073 appended `; N textures upscaled (T ms)` after it, so the run-dependent wait counts stay in. The pixel comparison is unaffected. A one-line fix in that tool, which was outside this task's list.
3. **The Vulkan renderer's Texture detail** is its own task (D-019): the same rule in `ge.frag`, a sampler with anisotropy, the device feature. Until then the row is shown there and draws the PSP's levels, as its help says.
