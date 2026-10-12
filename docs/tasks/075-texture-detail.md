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

## Result

**Status: BLOCKED.** Verify fails at its first command. `tools/texture_check.sh` passes race_hud, tt_hud, fp_hud, the enhanced-draw count and race_hud at scale 1. It fails zone_hud on one bar: the 1 capture must differ from the 0 capture in at least 1% of its pixels at tol 24, and it differs in 0.0002 (energy ratio 1.0004). No level choice can reach that bar on the Zone route (evidence below), so the bar is the problem, not the code. I left the check as the brief specifies it rather than loosen it, and stopped before the docs. Everything else measured passes: the Original path is the same to the pixel, the anisotropy acts, and a race at scale 4 holds 60 fps with the option on.

### Why zone_hud cannot pass
- zone_hud's frame (flip 5260) has 243 draws with levels (179 of them CLUT4 64x64 by the slope rule, biases mostly +20 and +23, like the race's); over the route all 41389 mipmapped draws were enhanced. The Zone's track and walls are bit-identical between 0 and 1; only the ship and a few distant objects change: 47123 pixels differ at tol 0 (2.26%), 4537 at tol 4, 314 at tol 24.
- Level 0 everywhere (`PURE_NO_MIPMAPS=1`, the finest any level choice can sample) differs from Original by the same 314 pixels at tol 24 (0.0002). On race_hud the same comparison gives 0.0224, next to Enhanced's 0.0218. The Zone's mipmapped textures hold no detail between their levels where this frame draws them, which fits the mode's flat white-and-blue look.
- The route's other scene, zone_change (flip 5679), is no better: 0.0000 at tol 24, energy ratio 1.0005, reduced 0.0436 (limit 0.10).
- zone_hud's energy ratio, 1.0004, clears the brief's escalation bar of 1.0 only by noise.

### Decisions needed
1. **zone_hud's bars.** Either keep zone_hud for the "same picture" reduction (0.0346 of its 0.09 here) and drop its 1% and energy bars, or check the three Vineta K scenes only. Either is a one-line change to texture_check.sh (the scene lists, or a per-scene bar).
2. **The HUD bar on zone_hud.** The brief asks that "the four 1 captures pass tools/hud_check.py", but zone_hud's own reference fails `tools/hud_check.py` (0 yellow pixels in both regions: its HUD has no CURRENT or LAP label), as tools/sprite_check.sh already notes. texture_check.sh holds the HUD bar to race_hud, tt_hud and fp_hud, as sprite_check does. Please confirm.

### The figures the brief asks for
- **Energy** (the mean absolute difference, per channel, between each pixel and its right and its lower neighbour over the whole 1920x1088 capture), 0 then 1, and the ratio:

  | Scene | Energy 0 | Energy 1 | Ratio |
  |---|---|---|---|
  | race_hud | 3.5752 | 4.0681 | 1.1378 |
  | tt_hud | 3.5424 | 4.3499 | 1.2279 |
  | fp_hud | 3.5210 | 4.3300 | 1.2298 |
  | zone_hud | 2.2434 | 2.2444 | 1.0004 |

- **Enhanced draws.** The exit line gives the count over the run, so the 10000 bar applies. The race_hud route with 1 had 192857 mipmapped draws, 192778 of them enhanced. The other 79 are 2D draws with levels (orthographic and unlit), which D-019 point 3 leaves alone. The 600-frame line at flip 6000 read 162803 mipmapped (162770 enhanced).
- **Frame rate at scale 4 in the Metal window.** Measured as task 073 did: `main_menu.txt` + `single_race.txt` without their shots, a fresh stick each run, `PURE_PACED_FROM=6000`, to flip 9850, `PURE_METAL_TRACE`, then `tools/frame_times.py --long 25 --fps 60 --from 6250`.
  - **Off:** 3601 frames in 60.1 s, mean 16.68 ms, 99th percentile 18.64 ms, longest 23.15 ms, none over 25 ms. All 3601 pictures reached the screen: interval mean 16.68 ms, longest 33.33 ms (one over 25 ms). A frame averaged 0.86 ms of GPU waits and 2.07 ms of submit.
  - **On, third run.** The window was covered once, at flips 6968 to 7022, where macOS held a drawable back for 0.97 s. Flips 7023 to 9850: 2828 frames, mean 16.68 ms, 99th percentile 18.52 ms, longest 21.32 ms, none over 25 ms; all 2828 pictures on screen, longest interval 25.00 ms. Flips 6250 to 6967: 718 frames, mean 16.68 ms, longest 22.06 ms, none over 25 ms (one on-screen interval of 37.5 ms, 3 pictures not shown). A frame averaged 0.86 to 0.94 ms of GPU waits and 2.03 to 2.45 ms of submit.
  - **On, second run** (the window was never on screen): 3601 frames in 60.1 s, mean 16.68 ms, longest 20.42 ms, none over 25 ms, 0.94 ms of GPU waits a frame.
  - **On, first run** (the window partly hidden): the long frames were 5 drawable waits (33 to 91 ms), 2 occluded drawables near 1 s, one depth write-back wait (a 41.9 ms frame) and one `outside` frame of 25.4 ms. That is a hidden window, not a player's case.
  - **Verdict:** the race holds 60 fps with the option on. The Original path costs nothing new: it is the same code to the pixel (below), and its 0.86 ms of GPU waits a frame matches task 067's 0.94 ms within noise.
- **maxAnisotropy:** 16, Metal's maximum (`MTLDevice` has no query for a lower limit). I put 1 in its place temporarily, then reverted it; the rebuilt capture equals the committed one to the pixel. Against the committed build, race_hud's 1 capture differs in 264862 of 2088960 pixels at tol 0 (0.1268), 0.0065 at tol 2 and 0.0004 at tol 24 (847 pixels); tt_hud in 0.1305, 0.0135 and 0.0005. The differences lie on the track at grazing angles, the crowds and the far scenery, so Metal does apply the anisotropy through `gradient2d`.

### The Original path
- **Pixels.** `tools/refactor_check.sh` compared captures from the base commit (eb4f5f6) with this build, the pin on, three ways: at scale 1, at `PURE_INTERNAL_SCALE=4`, and at 4 with `PURE_SPRITE_UPSCALE=1` (the captures scale_check and sprite_check take). Each time all 18 scenes had 0 differing pixels.
- **Counts.** The same on all 7 routes once the new `E enhanced` fields are taken out. refactor_check itself prints "counts FAIL" for two reasons: those new fields, and GPU-wait counts that its strip stopped removing when task 073 appended `; N textures upscaled` after them.
- **The suites:** frame_regress 18/18 with the base build's figures; scale_check PASS with task 066's table to the digit; sprite_check PASS with task 073's table to the digit; menu_check PASS on both shells (Video 14 and 20 rows, Texture detail last); docs_check PASS.

### What the commit holds (fbc1047)
- **The option.** Key `texture_detail`, "Texture detail", Original and Enhanced, default Enhanced, on the Video tab after Text and sprites, with the brief's help text. The backend reads it at start and in `begin_frame`, together with the sprite option (`read_sprite_upscale` became `read_game_options`). It prints `[pure] texture detail: off` at start when off, and `[pure] texture detail: on (game.texture_detail)` at the first enhanced draw.
- **The shift and the path.** `FragmentUniforms::level_range.y` holds 16 log2(S), which the shader subtracts from D after the rule and before the clamp. `level_range.z` = 1 selects the gradient path: `dfdx`/`dfdy` of the normalised uv, rho in texels of level 0, `k = exp2(D'/16 - log2(max(rho, 1e-8)))`, `gradient2d(dx * k, dy * k)`.
  - The struct keeps its 240 bytes (both fields were unused).
  - The auto rule's `level[2..3]` stay scaled by S, so at S = 2 and 4 the auto D is exactly the per-drawn-pixel gradient's; at 3, 5 and 6 it is within the GE logarithm's piecewise-linear step.
  - No new pipeline; config/metal_pipelines.txt is untouched.
  - An enhanced draw is one whose texture has levels and comes from guest memory, and which is not a 2D draw.
- **The sampler table:** 128 entries; bit 6 (`kAnisotropic`) sets `maxAnisotropy` 16.
- **The counts.** The exit line reads `M mipmapped draws (E enhanced, L mip levels decoded after the first)`. The new field sits inside the parentheses, so `purelib.logs.METAL_EXIT_RE` still parses the line (checked). The 600-frame line ends `..., M mipmapped draws (E enhanced)`, and `METAL_FPS_RE` still matches it.
- **The pin:** `ENHANCEMENTS_OFF` and `SCRATCH_SETTINGS` in port.py, run_boot's docstring, metal_check's replay line, and menu_check's Video rows on both shells.
- **tools/texture_check.sh** as the brief describes, with the HUD bar on three scenes (decision 2 above).

### Not done (stopped at the blocker)
- **The docs:** docs/metal-backend.md's "Texture detail (task 075)" section, its "Internal scale" table's "Mip levels" row and "The level in the shader"; docs/controls.md, docs/verification.md, docs/release.md and README.md. The comment in src/profile/enhancements.cpp already names the metal-backend.md section. docs_check passes as the tree stands.
- **`tools/gerec/metal_check.sh`** (not in Verify) was not run. This worktree has no recordings, and making them takes three Vulkan-window runs (about 10 minutes). Its replay line carries the pin. The main checkout's out/gerec recordings date from 2026-10-06, before task 037, so they hold one level and would not exercise the option anyway.
- **`tools/hud_check.sh`** (61 windowed shots) was not run. Its runs carry the pin through port.py, and the Original path is pixel-identical.

### Changed
src/gpu/shaders/ge.metal, src/gpu/metal_types.hpp, src/gpu/metal_textures.mm, src/gpu/metal_draw.mm, src/gpu/metal_backend.hpp, src/gpu/metal_backend.mm, src/gpu/metal_trace.mm, src/profile/enhancements.cpp, src/profile/enhancements.hpp, tools/texture_check.sh (new), tools/menu_check.sh, tools/purelib/port.py, tools/run_boot.py (docstring), tools/gerec/metal_check.sh (the pin line), docs/tasks/075-texture-detail.md (this Result).

### Verify output (all 19 lines)
```
verify 075: tools/texture_check.sh && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && tools/scale_check.sh && tools/sprite_check.sh && python3 tools/docs_check.py
texture check 2026-10-12 08:53: race_hud tt_hud fp_hud zone_hud at internal scale 4, PURE_TEXTURE_DETAIL 0 and 1, and race_hud at scale 1 with 1, headless on Metal, into /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a102bf65cc19f758b/out/texture_check
  scale 4, PURE_TEXTURE_DETAIL=0: 4 [pure] texture detail: off
  scale 4, PURE_TEXTURE_DETAIL=1: 4 [pure] texture detail: on (game.texture_detail)
  scale 1, PURE_TEXTURE_DETAIL=1: 1 [pure] texture detail: on (game.texture_detail)

each PURE_TEXTURE_DETAIL=1 capture at scale 4: its size, by its blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), the full capture against the PURE_TEXTURE_DETAIL=0 one at tol 24 (at least 1%), the high-frequency energy of the 0 and 1 captures and their ratio (above 1.0), and the race HUD (tools/hud_check.py):
scene            size  reduced  limit  tol     vs 0  energy 0  energy 1   ratio  HUD  result
race_hud    1920x1088   0.0467    0.1   32   0.0218    3.5752    4.0681  1.1378  yes  PASS
tt_hud      1920x1088   0.0473   0.12   32   0.0244    3.5424    4.3499  1.2279  yes  PASS
fp_hud      1920x1088   0.0472   0.11   32   0.0244    3.5210    4.3300  1.2298  yes  PASS
zone_hud    1920x1088   0.0346   0.09   32   0.0002    2.2434    2.2444  1.0004    -  FAIL (differs from the 0 capture in under 1%)

race_hud run with 1 (exit line, over the run): 192857 mipmapped draws, 192778 enhanced (at least 10000): PASS
race_hud at scale 1 with 1, against the reference: 0.0162 (limit 0.1, tol 32): PASS

texture check: 3/4 scenes pass, the enhanced draws PASS, race_hud at scale 1 PASS (0m 41s)
texture_check: FAIL
verify 075: FAIL (exit 1)
```

### Open questions
1. zone_hud's bars in texture_check.sh (decision 1 above): which form, or another scene set.
2. The HUD bar on three scenes instead of four (decision 2 above).
3. Once those are settled, the follow-up is the docs, metal_check (its recordings first) and hud_check.sh, then the Verify line again. The code needs no change for either decision.
