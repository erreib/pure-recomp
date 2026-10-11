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

## Result

Status: DONE

The branch has four commits plus this Result: 12cce3e (the pack dump), c3c4a15 (`tools/sprite_pack.sh`), 1a9818a
and 19b4f13 (the docs; 19b4f13 corrects figures after the Verify run and touches only the docs).

- **The pack dump** (metal_textures.mm). `dump_sprite` now takes the guest memory. It keeps task 073's
  `<key>.src.png` and `<key>.png`, and also writes `DIR/pack/<key>.png` with the line `<key> = <key>.png` under
  `[hashes]`. The key is the framework's `compute_texture_pack_key(memory, state, 0, options, ...)`, formatted by
  `format_texture_pack_key`, with `hash` xxh64 and `ignoreAddress` true. textures.ini is written when the folder is
  first used: a comment, `[options]` (version, hash, ignoreAddress), `[games]` `UCUS98612 = true`, then `[hashes]`. A key
  already present, from this run or an earlier PNG in the same folder, is skipped. A key the function refuses is logged
  once and left out; none were refused on these routes. The dump still runs only when the switch is set.
- **The keys match the Vulkan renderer's** (acceptance 2). The main menu route ran under the Vulkan renderer with
  `PURE_TEXTURE_DUMP` (no pack loaded, so `kDumpOptions`: xxh64, ignoreAddress). That dump wrote 316 originals. All 11
  pack keys the Metal backend writes on the same route are among them:
  - font CLUT4 256x128 (task 073's `font2`): `0000000038d957c250811edd`
  - font CLUT4 256x256: `0000000032e401a19c4925fa`
  - art atlas CLUT8 256x128 (`vram_a2`): `00000000d2df1e257fb392ca`
  - the 512x512 CLUT8 picture and the 256x32 strip (`strip2`) also match.

  The Vulkan dump's PNGs of the three named textures equal the Metal backend's decoded inputs exactly (imgdiff tol 0).
  The 25 textures the Metal backend upscales on the main menu route reduce to 11 pack keys. The menus keep up to twelve
  identical copies of the art atlas at different VRAM addresses, and with ignoreAddress they share one key. The input
  PNGs are identical, so the collapse is correct.
- **`tools/sprite_pack.sh [--out DIR] [--check] [--pack DIR] [--wait SECONDS]`**. The build runs the suite's 18 scenes'
  routes (44 keys), then the Single Race and the Time Trial on Vineta K to their results screens (`campaign_sweep.py
  --no-damage`, about 3.5 minutes each, 2 keys each). The result is 48 keys, 3.5 MB, in `out/sprite_pack/pack`. A Zone
  cell to its end panel added no key, so it is not run. Free Play's session end and the Tournament standings are not
  run. `--check` installs the pack in `DIR/check/data/textures/UCUS98612`, a fresh scratch data directory. It then
  runs `frame_regress.sh --shell vulkan --backend vulkan --only main_menu,race_hud` twice: with `PURE_TEXTURE_PACK=0`,
  and with `=1` plus `PURE_TRACE_TEXTURE_PACK=1`. To confirm the pack opened, the check reads the trace log rather than
  adding a mode to the port (the brief offered both). The Vulkan window captures at 960x544 and the check reduces by
  the centre pixel of each 2x2 block. `--pack DIR` checks without building and is the only mode on Windows.
  The figures (identical in two check runs):

  | scene | with vs without the pack | without, reduced | with, reduced | limit | HUD |
  |---|---|---|---|---|---|
  | main_menu | 0.0232 | 0.0401 | 0.0446 | 0.05 | - |
  | race_hud | 0.0116 | 0.0647 | 0.0638 | 0.10 | found |

  In both runs the renderer logged `48 textures from .../textures/UCUS98612`, uploaded 33 distinct pack pictures for
  draws, and replaced 129795 draws. Every picture sits in the right place at the right size (checked by eye in the two
  captures).
- **Acceptance 3.** `tools/sprite_check.sh` and the headless `tools/frame_regress.sh` give the same figures as task 073
  and the suite's measured column (Verify, below). `tools/menu_check.sh` and `--shell vulkan` both PASS. The plain
  Vulkan window main_menu scored 0.0331 against its measured 0.033.
- **Acceptance 4.** `git status` is clean. Every PNG is under out/ and none is committed.

Changed:
- src/gpu/metal_textures.mm, src/gpu/metal_backend.hpp
- tools/sprite_pack.sh (new)
- docs/metal-backend.md ("The texture pack (task 074)", the Files row, the dump bullet), docs/windows.md (the rig
  checklist's pack bullet), docs/release.md ("The texture pack (task 074)"), docs/verification.md ("Which path" row),
  README.md (the tools row, `PURE_SPRITE_UPSCALE` and `PURE_SPRITE_DUMP` rows), docs/tasks/074-sprite-pack.md (this
  Result)

Verify output (`tools/verify_task.sh 074`, at 1a9818a, log out/074_verify.log, last 20 lines):
```
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0112   0.12   32    0.0112 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0116   0.11   32    0.0116 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0122   0.09   32    0.0121 +0.0001  PASS
zone_change   5679    0.0369   0.10   32    0.0353 +0.0016  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
docs_check: 33 files, 0 findings: PASS
verify 074: PASS
```
The same run's sprite_pack and sprite_check lines:
```
the pack: 48 keys (at least 40), hash xxh64, 0 named files missing: PASS
drawn: 33 distinct images of the pack uploaded for draws (at least 10), 33 decoded, 129795 draws replaced in the traced 60-frame windows: PASS
main_menu    960x544    0.0232    0.0401   0.0446   0.05   24    -  PASS
race_hud     960x544    0.0116    0.0647   0.0638    0.1   32  yes  PASS
sprite_pack: PASS
main_menu run: 25 textures upscaled in 64.3 ms (at least 2, under 2000 ms): PASS
sprite_check: PASS
```

Open questions:
1. Verify took about 10 minutes: sprite_pack 8m 17s, of which the two paced sweep races were about 7 minutes and
   added 4 small keys. That is past the 10-minute limit of a single foreground tool call, so Verify ran in the
   background with nothing else running and was waited on. The earlier pieces each ran in the foreground. The window
   runs took 10 to 15 s each in Verify but 48 to 55 s in an earlier check run, so the tool's time varies. If the race
   cells are not worth 7 minutes, they could move behind an option.
2. race_hud's change with the pack is 0.0116, just over the 1% bar. At 960x544 and internal scale 2 only the HUD
   differs. It matched to four decimals in two runs, but there is little margin.
3. Twelve of the 48 keys are one CLUT4 32x16 picture (texels hash `cd0aa2c1`) under palettes the game animates. Which
   twelve a build catches varies; the other 36 were the same in three builds. The Vulkan run drew 2 of the twelve.
   Without them the pack would hold 36 keys, under the 40 the check asks for.
4. Seen by eye in the Vulkan capture: the main menu's top-right logo loses its thin white inner stripes, and the small
   "V5.0 //2197" text thins. This is the scaler's hairline thinning that task 073 noted, now visible at 2x. It is not
   a pack issue, but Erik may want to look before an AI pass.
5. Not tested: the app's own `PURE_SPRITE_DUMP` (docs/release.md says so), and the script's Windows path handling
   (`cygpath -m` for paths given to Python and the game; frame_regress's `--env` arguments rely on Git Bash's argument
   conversion, as the other tools do).
6. The Text and sprites row's help in src/profile/enhancements.cpp, outside this task's files, still says the Vulkan
   renderer draws the originals "until a texture pack exists". It could now point to the Texture pack row.
7. For a 512-tall texture drawn in through mode, the loader hashes only the rows its draws use, and the dump hashes the
   whole texture. Task 073 found that through mode reaches only three small textures in the frontend route, so this
   should not matter here, but it was not checked texture by texture (docs/metal-backend.md).
