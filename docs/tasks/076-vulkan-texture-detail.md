# 076: Texture detail at the internal scale (E5, the Vulkan renderer)

Milestone: E5 (Erik, 2026-10-12; D-019) | Branch: task/076-vulkan-texture-detail | Status: MERGED (the merge commit after bf3ad8b, 2026-10-12)

## Goal
Task 075 gave the Metal backend the "Texture detail" row (D-019): with Enhanced, every mipmapped draw's level D is
lowered by 16 x log2(S) at internal scale S, whatever the GE's rule, and the draw is sampled anisotropically at that
level through gradients scaled to it. The Vulkan renderer, the Windows rig's renderer, still draws the PSP's levels
and the row's help says so. After this task the Vulkan renderer does the same as the Metal backend, as a vendor
patch, the row's help no longer excepts it, and `tools/texture_check.sh --shell vulkan` proves it in the Vulkan
window on this Mac the way the Metal lane does headless.

## Read first
- CLAUDE.md, docs/decisions.md (D-015, D-019), docs/tasks/075-texture-detail.md (the Metal half: its Deliverable,
  its replan note and its Result's figures), docs/metal-backend.md ("Texture detail (task 075)"; "Mipmaps": the
  Vulkan renderer's rule since task 058 and the differences note), patches/README.md (the series, the row format,
  the upstream column; patch 0012-vulkan-mipmaps, 0017-internal-scale-by-backend, 0018-vulkan-effects-at-1x and
  0019-game-option-rows as the models), docs/upstream.md (what a patch's upstream column means), docs/windows.md
  (the rig checklist: the row this task adds)
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: the sampler creation in the initialisation (the six samplers
  after `vkCreatePipelineLayout`; `texture_sampler(levels)`), the device features block (`supported_features`,
  `enabled_features`: how `dualSrcBlend` and `depthClamp` are enabled when the device has them, with a line when
  not), the level rule block before the pass handling (the comment "The mip level rule of a texture with levels":
  `rule`, `constant`, the auto rule's `+ 16 log2(drawn_extent.width / kPspWidth)`, the packing into
  `texture_params[0]`: bits 5..6 the rule, bit 7 linear between levels, bits 8 and up the constant plus 2048,
  `kPushPlaced` at 2^20), `PushConstants` (128 bytes, `texture_params` x's bit layout in its comment), where
  `sharp_textures` is read per frame (the model for reading an option once a frame), `ge_log16`
- vendor/portablekit/host/gpu/shaders/ge.frag (`mip_lod`, the `mipmapped` path, `textureLod`, the clamp wrap's
  `half_texel` from `textureSize(..., ceil(lod))`), ge.vert if the coordinates' derivatives need anything
- vendor/portablekit/host/profile.hpp (`GameProfile`: `features`, `options`; where a game names what the framework
  may use), vendor/portablekit/host/settings/settings.hpp (`game_option(key)`), src/profile/pure_profile.cpp (the
  profile's fields and their comments), src/profile/enhancements.cpp (the Texture detail row's help text)
- src/gpu/shaders/ge.metal (`sample_texture`'s enhanced path: the exact maths to mirror), src/gpu/metal_draw.mm
  (the enhanced-draw rule: a texture with levels from guest memory, not a 2D draw: `flat` = through, or
  orthographic (`projection[3]`, `[7]`, `[11]` all 0) and unlit)
- tools/texture_check.sh (the Metal lane; this task adds `--shell vulkan`), tools/sprite_pack.sh (its Vulkan window
  lane through `tools/frame_regress.sh --out ... --shell vulkan --backend vulkan --only ...` and its `reduce` of a
  window capture by S = its width over 480), tools/frame_regress.sh (`--shell vulkan --backend vulkan`: the window
  scenes, paced from the scene), tools/patches.sh (`export NNNN-slug`, `check`), tools/purelib/port.py (the pin:
  `PURE_TEXTURE_DETAIL=0` reaches the Vulkan runs too), docs/verification.md ("Which path for which change": the
  Vulkan renderer row), README.md (the tools table's `tools/texture_check.sh` row)

## Deliverable
One vendor patch, `patches/0020-vulkan-texture-detail.patch` (through `tools/patches.sh export`), its row in
patches/README.md (both tables: the dependency table and the catalogue with its upstream column), and the small
changes outside vendor/. One or two commits.
- **How the renderer knows the option** (generic, as patch 0019 is: the framework must not know this game's key):
  `GameProfile` gains `const char *texture_detail_option = nullptr;` with a comment: the key of the game option
  (one of `options`) whose choice 1 asks the renderer for the level and anisotropy of D-019; nullptr, the default,
  leaves the renderer as it was. src/profile/pure_profile.cpp sets it to `"texture_detail"` beside `.options`. The
  renderer reads `settings::game_option(key) == 1u` once a frame (where it reads `sharp_textures` or at the frame's
  start), never per draw, and prints `[render] texture detail: on` once at the first enhanced draw and `[render]
  texture detail: off` once at start when the key is set and the option is off (nothing when no key).
- **The level shift**, in the level rule block: with the option on, for a texture with levels from guest memory
  (`texture_levels > 1u`, not placed) on a draw that is not a 2D draw (not through; and not orthographic-and-unlit,
  the rule of metal_draw.mm, from the call's projection and lighting), `constant` loses `16 x log2(S)` where S is
  `drawn_extent.width / kPspWidth` (the auto rule then adds nothing, since its addition is the same term; the
  slope and constant rules lose it): say it in the comment as D-019 point 2 says it. The clamp to -2048..2047 and
  the packing stay.
- **The gradient path**: a new flag bit in `texture_params[0]` above the constant's bits and `kPushPlaced` (2^21,
  a named constant `kPushDetail` beside `kPushPlaced`, with the comment extended; both are exact in a float), set
  for the enhanced draw. In ge.frag's `mipmapped` path with that bit: `lod` as computed (the constant already
  shifted), `dx = dFdx(uv)`, `dy = dFdy(uv)` of the normalised coordinates after the q divide and before the wrap
  adjustments, `rho = max(length(dx * size), length(dy * size))` with `size = textureSize(guest_texture, 0)`,
  `k = exp2(lod - log2(max(rho, 1e-8)))`, and `textureGrad(guest_texture, uv, dx * k, dy * k)` in place of
  `textureLod`. The `half_texel` clamp keeps using `lod`. Without the bit the path is byte-for-byte what it was.
- **The sampler**: enable `samplerAnisotropy` in `enabled_features` when the device supports it (the pattern of
  `dualSrcBlend`; a line when it does not: "[render] texture detail samples isotropically: this device has no
  samplerAnisotropy"); create `mip_detail_sampler` (linear, mipmap linear, `anisotropyEnable` with
  `maxAnisotropy = min(16, limits.maxSamplerAnisotropy)`, repeat, `VK_LOD_CLAMP_NONE`) beside `mip_sampler` and
  destroy it with the others; `texture_sampler(levels, detail)` returns it for an enhanced draw when
  `sharp_textures` is off (with Sharp textures the nearest mip sampler stays: say so in a comment). The descriptor
  for an enhanced draw must use it: follow how `texture_sampler(levels)` reaches the two descriptor sites and give
  them the choice (a descriptor cached per texture may need the sampler in its key: check, and say in the Result
  what you found).
- **The row's help** in src/profile/enhancements.cpp: drop "Metal only for now: the Vulkan renderer draws the PSP's
  levels." and say "Both renderers." or nothing.
- **`tools/texture_check.sh --shell vulkan`**: the three Vineta K scenes (race_hud, tt_hud, fp_hud; zone_hud as in
  the Metal lane if cheap, else left out and said) captured in the Vulkan window through `tools/frame_regress.sh
  --out ... --shell vulkan --backend vulkan --only ...` with `PURE_TEXTURE_DETAIL=0` and with `1`, the window
  capture's S its width over 480 (sprite_pack's reduce), the same bars as the Metal lane: reduced within the
  scene's limit, at least 1% different from the 0 capture at tol 24, the energy ratio above 1.0, the HUD found,
  and the enhanced draws counted if the Vulkan renderer has a count to print (else the `on` line present in the
  log). The Metal lane unchanged. The summary line names the shell.
- **The pin**: already there (port.py reaches every run); confirm `tools/frame_regress.sh --shell vulkan --backend
  vulkan` is unchanged with the pin on, and `tools/gerec/metal_check.sh`'s Vulkan lane too (its replay line carries
  `PURE_TEXTURE_DETAIL=0`).
- **Docs**: patches/README.md (the rows), docs/metal-backend.md (the "Texture detail" section: the Vulkan renderer
  does the same, the differences note), docs/controls.md (the row no longer Metal-only), docs/verification.md (the
  Vulkan renderer row of "Which path" names `tools/texture_check.sh --shell vulkan`), docs/windows.md (the rig
  checklist: an open item to run `tools/texture_check.sh --shell vulkan` there and look at a race with the row on
  and off), README.md (the tools row: `--shell vulkan`). `python3 tools/docs_check.py` and `tools/patches.sh check`
  pass.

## Acceptance criteria
- [ ] `tools/texture_check.sh --shell vulkan` PASS: the three scenes reduced within their limits, each at least 1%
      different at full size, each with an energy ratio above 1.0, the HUD found; the figures in the Result
- [ ] `tools/texture_check.sh` (the Metal lane) PASS, unchanged
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` PASS 7/7 with the base figures (the pin on)
- [ ] `tools/menu_check.sh --shell vulkan` PASS (the row's help changed, the rows not)
- [ ] with `maxAnisotropy` 1 in place of the limit (a temporary edit, not committed) the race_hud `1` capture
      differs from the committed one: MoltenVK applies the anisotropy through `textureGrad` (the fraction in the
      Result)
- [ ] a race in the Vulkan window holds its frame rate with the option on as it does off (`tools/run_boot.py
      --window --shell vulkan` with the fps line, or the suite's timings: the figures in the Result)
- [ ] `tools/patches.sh check` and `python3 tools/docs_check.py` pass; `git status` shows no change under vendor/
      beyond what the patch carries (vendor/ is never committed)

## Verify
`tools/texture_check.sh --shell vulkan && tools/texture_check.sh && tools/frame_regress.sh --shell vulkan --backend vulkan && tools/menu_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/gpu/vulkan_renderer.cpp, vendor/portablekit/host/gpu/vulkan_renderer.hpp,
  vendor/portablekit/host/gpu/shaders/ge.frag (and ge.vert only if needed), vendor/portablekit/host/profile.hpp:
  only through `tools/patches.sh export 0020-vulkan-texture-detail`; commit patches/, never vendor/
- patches/0020-vulkan-texture-detail.patch (new), patches/README.md
- src/profile/pure_profile.cpp, src/profile/enhancements.cpp
- tools/texture_check.sh
- docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/windows.md, README.md,
  docs/tasks/076-vulkan-texture-detail.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/gpu/ (the Metal half is done), src/host/, src/profile/test_hooks.*,
  tools/frame_regress.sh, tools/sprite_pack.sh, tools/purelib/, tools/hud_check.*, tools/imgdiff.py, ref/,
  docs/decisions.md, docs/status.md, any vendor file not listed, anything not listed above

## Estimated turns
60

## Escalate when
- the Vulkan window suite or metal_check's Vulkan lane moves with the pin on (report which scene and by how much)
- the reduced `1` capture of a scene fails its limit in the Vulkan window, or its energy ratio is at or below 1.0
  (the Metal lane's figures are the expectation: 1.14 to 1.23)
- MoltenVK shows no difference between `maxAnisotropy` 1 and the limit (report; keep the level shift, which is the
  larger gain, and say so)
- the push constants cannot hold the flag (they are 128 bytes and full: a float bit above 2^20 in
  `texture_params[0]` is the plan; if that bit is taken, stop and say which bits are free)
- a change under include/psprecomp/, to the GE state or the record format, or to config/ would be needed; a build
  takes over 5 minutes (a vendor host change rebuilds the host layer, minutes, not the corpus)

## Result

**Status: DONE.** Verify passes: both texture_check lanes, the Vulkan window suite 7/7, menu_check under the Vulkan shell, patches.sh check and docs_check.
- **Patch 0020-vulkan-texture-detail** gives the Vulkan renderer the Metal backend's Texture detail: the level shift, `textureGrad` and an anisotropic sampler.
- **Off, nothing changes.** With the option off (the pin), the renderer draws exactly as before. The seven window scenes equal the base build's to the pixel.
- **MoltenVK applies the anisotropy** through `textureGrad`.
- **Frame rate.** A race in the Vulkan window holds 60 fps with the option on, as it does off.

### What the code does
- **The option.** `GameProfile::texture_detail_option` (patch 0020; `host/profile.hpp`, default nullptr). Our profile sets it to `"texture_detail"` beside `.options`.
  - The renderer reads `settings::game_option(key) == 1u` in `initialize` and once a frame in `begin_frame`, never per draw.
  - It prints `[render] texture detail: off` at start when the option is off, and `[render] texture detail: on` once, at the first enhanced draw. Nothing is printed when the game names no key.
- **Which draws.** The rule of metal_draw.mm, from the call's projection and lighting: a texture with levels from guest memory, on a draw that is neither through mode nor orthographic (`projection[3]`, `[7]`, `[11]` all 0) and unlit.
  - A target's texture is never enhanced (it has 1 level), and neither is a texture pack replacement (`texture_descriptor` reports 1 level for it).
- **The shift.** In the level rule block, `shift = lround(16 log2(drawn_extent.width / 480))`. The auto rule adds it as before; an enhanced draw then subtracts it, so for the auto rule nothing is added.
  - The clamp to -2048..2047 and the packing are unchanged. The comment says it in D-019 point 2's terms.
- **The flag.** `kPushDetail` = 2^21, beside `kPushPlaced` (2^20). Both comments are extended.
  - Bit 21 was free. Everything packed into x stays under 2^24, so it is exact in a float.
  - `mip_lod` now masks the constant's 12 bits (`((flags >> 8) & 0xFFF) - 2048`). Without the bit that is the same value.
- **The shader** (ge.frag).
  - With the bit, `dFdx`/`dFdy` of `uv` are taken right after the q divide.
  - `lod` comes from `mip_lod`, with the constant already shifted.
  - `rho = max(length(dx*size), length(dy*size))` and `k = exp2(lod - log2(max(rho, 1e-8)))`, then `textureGrad(guest_texture, uv, dx*k, dy*k)`.
  - The `half_texel` clamp still uses `lod`.
  - Without the bit, the `textureLod`/`texture` path is the old expression.
- **ge.vert** is untouched: it reads only bit 3 and `kPlaced`.

### The descriptor cache and the sampler (what I found)
- **The descriptor cache.** The sampler is baked into each cached `Texture`'s one combined-image-sampler descriptor set. That set is written in `create_texture_image` and rewritten by `set_sharp_textures` (with `vkDeviceWaitIdle`) when the Texture filter changes.
  - So the sampler is effectively part of the cache entry's identity. `texture_sampler(levels)` reaches only those two sites.
  - The per-texture descriptor cannot be switched per draw:
    - the same texture can be drawn in one frame by an enhanced draw and by a 2D draw (79 of the race route's mipmapped draws are 2D on Metal);
    - a set already bound in the frame's command buffer cannot be rewritten.
- **What I did about it.**
  - `Texture` gained `detail_descriptor`: the same view through `texture_sampler(levels, true)`.
  - It is allocated lazily at the texture's first enhanced draw (`detail_descriptor()`; if allocation fails, the draw falls back to the plain set).
  - It is freed in `destroy_texture` and rewritten beside the other set in `set_sharp_textures`.
  - With the option off, no extra set is ever allocated.
  - The descriptor pool gets 4x instead of 2x `kMaxCachedTextures` sets when the game names the option, since retired textures keep their sets for a frame.
  - The texture cache key itself did not need the sampler.
- **`texture_sampler(levels, detail)`** returns `mip_detail_sampler` for an enhanced draw. Under Sharp it returns `mip_sharp_sampler` (said in a comment): the setting asks for the nearest texel.
- **The sampler.** `mip_detail_sampler` is linear, mipmap linear, repeat, `VK_LOD_CLAMP_NONE`, with `anisotropyEnable` and `maxAnisotropy = min(16, limits.maxSamplerAnisotropy)`.
  - `samplerAnisotropy` is enabled when supported, in the pattern of `dualSrcBlend`. When it is not, and the game names the option, the line "[render] texture detail samples isotropically: this device has no samplerAnisotropy" is printed.
  - MoltenVK on this M4 Pro reports `maxSamplerAnisotropy` 16 (read with a temporary print), so the limit is 16.

### texture_check --shell vulkan (the Verify run; default 960x544 window, S = 2)
| Scene | Reduced, on (limit) | Reduced, off | On against off | Energy off | Energy on | Ratio | HUD |
|---|---|---|---|---|---|---|---|
| race_hud | 0.0727 (0.10) | 0.0647 | 0.0194 | 6.3364 | 6.8594 | 1.0825 | found |
| tt_hud | 0.0800 (0.12) | 0.0699 | 0.0188 | 6.3131 | 7.1880 | 1.1386 | found |
| fp_hud | 0.0797 (0.11) | 0.0696 | 0.0188 | 6.2722 | 7.1494 | 1.1399 | found |
| zone_hud | 0.0557 (0.09) | 0.0556 | (0.0002) | (4.0860) | (4.0869) | (1.0002) | - |

- **The count.** The Vulkan renderer has no draw count, so the lane checks instead that the race_hud run logs `on` with 1 and `off` (and no `on`) with 0. PASS.
- **zone_hud is included** (two runs, cheap) and held to the reduction alone, as in the Metal lane.
- **Reduced, off** was computed outside the tool. The centre pick at S = 2 takes each block's lower right pixel, where the suite takes the upper left, so it reads 0.0647 where the suite reads 0.0465.
- **The ratios are lower than Metal's** (1.08 to 1.14, against 1.14 to 1.23): one level of shift at S = 2, against two at S = 4.
- **The Metal lane** is unchanged, to the digit of task 075's figures: race_hud 0.0467 / 0.0218 / 1.1378, tt_hud 1.2279, fp_hud 1.2298, 192778 of 192857 enhanced, scale 1 0.0162.

### maxAnisotropy 1 against the limit
A temporary edit (`maxAnisotropy = 1.0f`, not committed; the file was restored byte for byte, and the rebuilt race_hud capture equals the earlier one to the pixel). The 1 captures against the committed build's:

| | tol 0 | tol 2 | tol 24 |
|---|---|---|---|
| race_hud | 80872 of 522240 (0.1549) | 0.0215 | 0.0020 (1022 px) |
| tt_hud | 0.2233 | 0.0522 | 0.0025 |

The differences are only on surfaces at grazing angles: the crowds, buildings, the far track and the ships ahead. No game state differs (checked on the diff images).

### Frame rate (the Vulkan window)
The setup:
- 960x544, FIFO at 120 Hz.
- `main_menu.txt` + `single_race.txt` without shots, a fresh stick per run, `--data-dir out/076/perf/data` (warmed by one discarded run).
- `PURE_PACED_FROM=6000`, to flip 9850, `PURE_PERF=log`. The figures are the 63 one-second lines from the race start.

| Option | Scale | fps mean (lowest) | Seconds < 59.5 | Frame mean | Longest | GPU a frame (max) |
|---|---|---|---|---|---|---|
| off | Auto (2) | 59.70 (52.2) | 2 | 16.77 ms | 34.6 ms | 1.66 ms (9.3) |
| on | Auto (2) | 59.71 (48.4) | 2 | 16.78 ms | 34.3 ms | 1.66 ms (9.0) |
| off | 4 | 59.94 (59.8) | 0 | 16.70 ms | 21.4 ms | 2.05 ms (15.1) |
| on | 4 | 59.94 (59.8) | 0 | 16.70 ms | 19.3 ms | 2.37 ms (10.4) |

- **The dips at Auto** are the last two seconds of both runs, with the option off as on.
- **The cost:** about 0.3 ms of GPU time a frame at internal scale 4. None is measurable at 2x.

### The pin (the Original path)
- **The Vulkan window suite.** 7/7 with the base figures: title 0.0302, main_menu 0.0331, race_hud 0.0465, tt_hud 0.0493, fp_hud 0.0475, zone_hud 0.0452, zone_change 0.0522.
  - To check pixels, I reversed patch 0020 and the profile line, built the base, and ran the suite with a data directory of its own. All seven captures equal this build's, 0 pixels at tol 0.
- **metal_check.** I copied the main checkout's recordings (team, race_1x and race_warm, from 2026-10-06) into this worktree's out/gerec and ran `tools/gerec/metal_check.sh`: PASS.
  - Every diff figure and first-diff line equals the main checkout's 075 gate logs. Its replay line carries `PURE_TEXTURE_DETAIL=0`.
  - These recordings hold one level, so they never reach the option.

### Changed
patches/0020-vulkan-texture-detail.patch (new; vendor/portablekit/host/gpu/vulkan_renderer.cpp, host/gpu/shaders/ge.frag, host/profile.hpp), patches/README.md, src/profile/pure_profile.cpp, src/profile/enhancements.cpp (the help text and the E5 comment), tools/texture_check.sh, docs/metal-backend.md, docs/controls.md, docs/verification.md, docs/windows.md, README.md, docs/tasks/076-vulkan-texture-detail.md. Two commits.

### Verify output (last 20 lines)
```
title        1750    0.0302   0.05   24     0.030 +0.0002  PASS
main_menu    4700    0.0331   0.05   24     0.033 +0.0001  PASS
race_hud     6016    0.0465   0.10   32     0.047 -0.0005  PASS
tt_hud       5890    0.0493   0.12   32     0.049 +0.0003  PASS
fp_hud       5890    0.0475   0.11   32     0.048 -0.0005  PASS
zone_hud     5260    0.0452   0.09   32     0.045 +0.0002  PASS
zone_change   5679    0.0522   0.10   32     0.052 +0.0002  PASS

frame regression: PASS, 7/7 scenes pass, the window scenes, shell vulkan, backend vulkan (1m 36s)
menu_check: shell vulkan, out out/menu_check/vulkan
menu_check: run_boot exit 0, 9 s, log out/menu_check/vulkan/run.log
tabs: ok (4)
Video: ok (20)
Audio: ok (4)
Controls: ok (37)
System: ok (12)
menu_check: PASS
ok: 20 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 33 files, 0 findings: PASS
verify 076: PASS
```

### Open questions
1. **docs/upstream.md has no row for 0020.** It holds the patch dependency table and the per-patch upstream notes, and it is not in May touch; patches/README.md has the series row and the paragraph. What I found, read from the code (not tried patch by patch):
   - to apply, 0020 needs 0019 (the `options` lines of profile.hpp) and 0012, 0015 and 0018 (the renderer and ge.frag lines it edits);
   - to build, it needs 0012 (the mip rule, `mip_levels`), 0018 (`drawn_extent`) and 0019 (`settings::game_option`).
2. **texture_check --shell vulkan reruns its 0 runs whenever any pipeline was made.** The reason: in a fresh data directory, a run that compiled 26 pipelines while paced moved tt_hud's race (27% of its pixels at tol 0). The 0 runs are now repeated, up to three rounds in all, while any 0 run logs `[render] N new pipeline(s)`. That trigger also fires on a straggler in a warm directory: in the final Verify it cost one extra round, 4m56s for the lane. A threshold on the stall's milliseconds would be quieter.
3. **One Verify run's suite scored zone_change 0.0546.** The Zone run took 68 s instead of the usual 28, cause not found (machine load or the window). An immediate rerun gave 0.0522, equal to the pixel to the base build, and so did the final Verify. The paced window race is sensitive to stalls.
4. **Out-of-scope files still describe the Vulkan renderer's texture detail as missing.** docs/status.md and docs/decisions.md (D-019's consequences) still say it draws the PSP's levels (Must not touch). src/profile/enhancements.hpp's header comment still names only the Metal backend as reading the option (not in May touch).
5. **The Vulkan renderer counts no enhanced draws**, so the `on` line stands in for the count. A count could go on the `[perf]` line if wanted.

## Review
Fable, 2026-10-12. Diff within May touch; the vendor change only through patch 0020 (`tools/patches.sh check`: 20
patches reproduce the pin), the profile hook generic (null by default), the Original path the old expression. Merged
`--no-ff` into batch/m2, vendor reset to the pin plus the series, built, and from the main checkout:
`tools/verify_task.sh 076` PASS (Vulkan lane race_hud 0.0738 of 0.10 reduced, 0.0251 against Original, energy ratio
1.0851; tt_hud 1.1386; fp_hud 1.1399; zone_hud reduced 0.0557 of 0.09; the on and off lines; Metal lane to the digit
of task 075; Vulkan window suite 7/7 with the base figures; menus PASS; docs_check), the headless suite 18/18, the
Metal window suite 7/7, hud_check 61 of 61 under Vulkan, metal_check PASS (out/076_gate.log). The out-of-scope
sentences the Result named (D-019's consequences, docs/status.md, enhancements.hpp's header) and docs/upstream.md's
row and section for 0020 were done at merge. Follow-ups: the rig's run of the Vulkan lane; the lane's rerun of its
0 captures on any new pipeline (a stall threshold); a count of the enhanced draws on the renderer's perf line.

