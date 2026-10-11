# 074: The upscaled art as a texture pack (E7, the Vulkan renderer)

Milestone: E7 (Erik, 2026-10-11; D-018 point 4) | Branch: task/074-sprite-pack | Status: OPEN

## Goal
Task 073 upscales the menus' and HUD's bitmap art in the Metal backend. The Vulkan renderer (Windows, and the
Vulkan window on the Mac) draws the originals; it has no scaler, but it loads PPSSPP-format HD texture packs
(`host/gpu/texture_pack.cpp`: `textures.ini` and PNGs keyed by a content hash, installed at `textures/<disc id>/`
in the data directory or used in place from `video.texture_pack_folder`, managed by the menu's texture pack
screen). After this task the Metal backend's dump switch writes such a pack, keyed as the loader keys the same
textures, a tool builds it from the routes that visit every menu and HUD, and the Vulkan renderer draws the same
upscaled art from it. The pack holds the game's art: it is built locally under out/ and never committed. It is
also the base an AI pass can replace atlas by atlas later.

## Read first
- CLAUDE.md, docs/decisions.md (D-018), docs/tasks/073-sprite-upscale.md (the Result: the dump switch, the keys,
  the counts per route), docs/metal-backend.md ("Sprite upscale")
- vendor/portablekit/host/gpu/texture_pack.hpp and texture_pack.cpp (`TexturePackOptions`, `compute_texture_pack_key`,
  `format_texture_pack_key`, `TexturePack::open`, the ini sections it reads: `[options]` with `hash`,
  `ignoreAddress`, `reduceHash`; `[hashes]`; `[games]`), host/gpu/replacement_textures.hpp (how the renderer
  draws a replacement: its own size, the filter), host/gpu/vulkan_renderer.cpp (`TEXTURE_DUMP`: the framework's own
  dumper of originals, `texture_pack_folder()`, where the installed pack lives), host/gpu/texture_pack_import.cpp
  (what a pack folder must hold), host/ui/texture_pack_screen.cpp (the menu's view of a pack), host/settings
  (`video.texture_pack`, `video.texture_pack_folder`), README.md of the framework if it documents packs
- src/gpu/metal_textures.mm (`dump_sprite`, `decoded_texture`: where the upscaled texels and the `TextureState` are
  at hand), src/gpu/sprite_upscale.hpp (`write_png`)
- tools/sprite_check.sh and tools/frame_regress.sh (`--shell vulkan --backend vulkan`: the Vulkan renderer in a window
  on the Mac, paced from the scene; its scene limits), tools/purelib/port.py (the pins; `clean_env`, the data
  directory), docs/windows.md (the rig checklist section, which gains the pack's steps), docs/release.md

## Deliverable
- **The pack dump** (src/gpu/metal_textures.mm, the dump switch of task 073 extended): with `PURE_SPRITE_DUMP=DIR`,
  each upscaled texture is also written as a pack entry: the file `DIR/pack/<key>.png` where `<key>` is
  `format_texture_pack_key` of `compute_texture_pack_key(memory, state, 0, options, ...)` with options `hash`
  xxh64 and `ignoreAddress` true (the port's guest addresses differ from PPSSPP's and may differ between runs; the
  data hash and the palette hash are what identify the art), the other options default; and a line
  `<key> = <key>.png` appended to `DIR/pack/textures.ini` under `[hashes]`, after an `[options]` section saying
  `hash = xxh64` and `ignoreAddress = true` and a `[games]` section naming `UCUS98612`, written once when the
  folder is made. A key already written is skipped. The `<key>.src.png` and Metal-key dumps of task 073 stay as they
  are, beside. If `compute_texture_pack_key` refuses a texture (it returns false), log it once and skip it. Keep
  the dump off the frame's path as task 073 did (it is a debugging switch).
- **`tools/sprite_pack.sh [--out DIR] [--check]`**: builds the pack. Runs, headless on Metal with
  `PURE_SPRITE_UPSCALE=1` and `PURE_SPRITE_DUMP=DIR/dump`, the routes that visit every menu and HUD: the frame
  regression suite's 18 scenes' routes (reuse `tools/frame_regress.sh --out` with the two variables in its
  environment, since its runs pass the environment on, and the sprite dump collects across runs into one folder)
  plus the race routes to their results screens if a scene's route ends before (say which routes the pack came
  from). The pack is `DIR/pack` (textures.ini and the PNGs); print the number of keys and the folder's size. Then
  **`--check`**: the pack opened by the framework (`TexturePack::open` through a small mode of the port, or by
  running the Vulkan renderer with the pack and reading its log: `PURE_TRACE_TEXTURE_PACK` logs every lookup and
  decode; choose the lighter), and the `main_menu` and `race_hud` scenes captured in the Vulkan window
  (`--shell vulkan --backend vulkan`, as frame_regress does, paced from the scene) twice: with `video.texture_pack`
  off (or no pack) and with the pack installed in that run's data directory at `textures/UCUS98612` (copy it there;
  run_boot's data directory is the scratch one). PASS when: the pack holds at least 40 keys; the run with the pack
  logs replacements being drawn (at least 10 distinct keys); the captures with the pack differ from the ones
  without in at least 1% of pixels at tol 24; each capture with the pack, reduced to 480x272 by the centre pixel of
  each block (the Vulkan window's capture size is the window's; say what it is and reduce accordingly, or compare
  at the capture's size against the no-pack capture reduced the same way), is within the scene's frame_regress
  Vulkan limit of the reference; and the HUD is found in the race capture. Print the table; `sprite_pack: PASS` or
  `FAIL` last; exit 0 only on PASS. On Windows the same script builds nothing (no Metal) and only checks an existing
  pack folder given with `--pack DIR`: the rig gets the pack as a folder copied from the Mac.
- **Docs**: docs/metal-backend.md ("Sprite upscale": the pack dump and its keys), docs/windows.md (the rig
  checklist: build the pack on the Mac with `tools/sprite_pack.sh`, copy `out/sprite_pack/pack` to the rig's data
  directory as `textures/UCUS98612`, or install it through the Esc menu's texture pack screen; then
  `tools/sprite_pack.sh --check --pack DIR`), docs/release.md (the pack is not in the zip: how a player makes and
  installs it; the texture pack screen), README.md (the tools table; `PURE_SPRITE_DUMP` now also writes the pack),
  docs/verification.md ("Which path" gains the check). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/sprite_pack.sh --check` PASS on the Mac: the pack built from the routes, opened by the framework,
      drawn by the Vulkan renderer in the two scenes, the captures changed by at least 1% and within the scenes'
      limits after reduction, the HUD found
- [ ] the keys the Metal dump writes equal the keys the Vulkan renderer's own `PURE_TEXTURE_DUMP` writes for the
      same textures (run the main menu route under the Vulkan renderer with `PURE_TEXTURE_DUMP` and the same
      options, and show that the font atlases' and the art atlases' file names match; name the three keys in the
      Result)
- [ ] `tools/sprite_check.sh`, `tools/frame_regress.sh`, `tools/menu_check.sh` both shells unchanged (the pins on)
- [ ] no game art under git: `git status` shows no PNG from the dump; the pack lives under out/
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/sprite_pack.sh --check && tools/sprite_check.sh && tools/frame_regress.sh && python3 tools/docs_check.py`

## May touch
- src/gpu/metal_textures.mm, src/gpu/metal_backend.hpp, src/gpu/sprite_upscale.{cpp,hpp}
- tools/sprite_pack.sh (new), tools/purelib/port.py (only if a helper is needed)
- docs/metal-backend.md, docs/windows.md, docs/release.md, docs/verification.md, README.md,
  docs/tasks/074-sprite-pack.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, vendor/, patches/, src/gpu/shaders/, src/gpu/metal_draw.mm, src/host/,
  src/profile/, tools/sprite_check.sh, tools/frame_regress.sh, tools/hud_check.*, ref/, docs/decisions.md,
  docs/status.md, anything not listed above

## Estimated turns
50

## Escalate when
- the loader's key for a texture cannot be reproduced from the Metal backend's `TextureState` (the acceptance's
  key comparison fails): report the two keys and the options, do not fork the hashing
- the Vulkan renderer draws a replacement at the wrong place or size (the reduced capture fails its limit while
  the no-pack one passes): report the scene and stop
- a vendor change would be needed; a build takes over 5 minutes
