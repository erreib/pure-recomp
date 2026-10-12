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
  PASS; captures and reductions under `--out` (default out/texture_check).
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
