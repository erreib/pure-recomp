# 076: Texture detail at the internal scale (E5, the Vulkan renderer)

Milestone: E5 (Erik, 2026-10-12; D-019) | Branch: task/076-vulkan-texture-detail | Status: OPEN

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
