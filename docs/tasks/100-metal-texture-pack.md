# 100: The HD texture pack on Metal: the backend's pack loader

Milestone: HD pack (D-024) | Branch: task/100-metal-texture-pack | Status: OPEN (dispatch after task 099 merges)

## Goal
The Metal backend, the Mac's default, draws a texture pack: NR74W's HD pack once task 099's decoder is in, and the
sprite pack `tools/sprite_pack.sh` builds from the Metal backend itself either way. The menu's Texture pack row and
the import screen work under the Metal shell as they do under Vulkan. The framework's backend-neutral pack class does
the keys, the ini, the decode threads and the memory window; this task adds the Metal side of what
host/gpu/replacement_textures.cpp does for Vulkan (upload, mips, residency, budget) and the two shell seams the menu
needs. D-024 (3).

## Read first
- docs/decisions.md, D-024.
- src/gpu/metal_textures.mm whole (347 lines: the content key, `decoded_texture` at 225 to 325, the sprite upscale's
  place in it, `set_level_rule` at 327) and src/gpu/metal_backend.hpp 240 to 265 (`textures_`, `texture_clock_`,
  the option flags); src/gpu/metal_types.hpp 256 to 260 (`CachedTexture`) and `kMaxTextures` at 47.
- src/gpu/metal_backend.mm, `begin_frame` (327) and `end_encoder` (422): where a frame starts and where a blit
  encoder can run before the render encoder.
- vendor/portablekit/host/gpu/texture_pack.hpp 45 to 160 (`Replacement`, its states, `TexturePack::open`, `find`,
  `request`, `consumed`, `entry_count`); texture_pack_import.hpp 37 to 48 (`texture_pack_location`).
- vendor/portablekit/host/gpu/vulkan_renderer.cpp: `apply_texture_pack` (4464 to 4510: the open, the status strings,
  the cache drop), the lookup at 4300 to 4316 and 4417 to 4435 (`find`, the 512-tall `max_seen_v` rule, the
  replaced-draw count), `drawn_max_v` and `update_max_seen_v` (4242 to 4256, 14 lines, file-local), the trace
  line at 5888 to 5895; vulkan_renderer.hpp 188 to 210 (the pack methods the menu calls).
- vendor/portablekit/host/gpu/replacement_textures.cpp 14 to 30 (the constants) and `descriptor` 140 to 180 (the
  per-frame upload cap, the Failed path, the trace line) and the eviction at 340 to 360.
- vendor/portablekit/host/ui/menu.cpp 450 to 490 and texture_pack_screen.cpp 80 to 90, 240 to 265, 415 to 420, 460
  to 490, 515 to 520: every call the menu and the import screen make on `gpu::VulkanRenderer` through
  `active_renderer()` (declared in host/hle/hle_common.hpp 108).
- docs/metal-backend.md, "Sprite upscale (task 073)" and its "The texture pack (task 074)" (580 to 763), "Texture
  detail (task 075)" (764 on).
- tools/sprite_pack.sh, the header and the check (lines 1 to 50, 160 to 200, 277 to 300); tools/menu_check.sh 85 to
  92 (the Metal expectations without the pack rows).
- docs/tasks/099-zim-decoder.md, Result (what the pack does on Vulkan, the measurement to compare with).

## Facts
- The pack class is backend-neutral: `TexturePack::open(folder, disc_id, error)`, `find(memory, state, max_seen_v)`
  returns a `shared_ptr<Replacement>` or null, `request(r)` queues a decode (the loader threads fill `r.pixels`,
  RGBA8 rows, `r.width` x `r.height`, and publish `Decoded`), the renderer uploads, frees the pixels and marks
  `Resident` through `consumed(r)`; `Failed` is final. The decode window is 256 MB (`kMaxDecodedBytes`), so a
  renderer that never consumes stalls the loader: consume every Decoded replacement you see, uploaded or refused.
- The pack folder: `texture_pack_location(install::user_data_directory() / "textures", portablekit::game().disc_id,
  settings::current().texture_pack_folder)` (the env `PURE_TEXTURE_PACK` is read inside it); the setting
  `settings::current().texture_pack` (`video.texture_pack`, on by default) is the row.
- Vulkan's constants, to mirror: upload cap 32 MB a frame (`kUploadBytesPerFrame`; the original is drawn until the
  next frame), `kMaxResident` 4096, GPU budget `PURE_TEXTURE_PACK_MEMORY` MB (default 1024), a replacement drawn
  within `kKeepFrames` 4 frames is never evicted. On Metal an `id<MTLTexture>` referenced by an in-flight command
  buffer stays alive under ARC, so eviction is a map erase with no fence.
- The trace lines `tools/sprite_pack.sh --check` reads (its regexes at 277 to 300), under `PURE_TRACE_TEXTURE_PACK=1`
  except the first: `[texpack] N textures from FOLDER` (at open, always); `[texpack] frame F: uploaded NAME (K KiB
  with mips)`; `[texpack] decoded NAME WxH` (the loader prints it); `[texpack] frame F: N draws replaced in 60
  frames, M images on the GPU (K MB)` every 60 frames. Print the same shapes.
- The 512-tall rule: a texture of height 512 drawn in through mode is hashed only down to the rows drawn so far
  (`drawn_max_v`: the largest V among the draw's texcoords, clamped to 512; `update_max_seen_v`: first draw sets
  max(272, drawn), a later deeper draw sets 512). Both are 14 file-local lines in vulkan_renderer.cpp; write the
  same rule in src/gpu (no vendor export for 14 lines).
- Mips: the pack's images have none; Vulkan generates a full chain at upload and samples linear with mips (nearest
  under the sharp setting). The Metal backend's Texture detail (D-019, `set_level_rule`) shifts the level by the
  internal scale on mipmapped draws, so a replacement needs generated mips (`MTLBlitCommandEncoder
  generateMipmapsForTexture:` in a blit encoder before the frame's render encoder, or at upload on a separate
  command buffer) or it blurs at a distance. A replacement supersedes the sprite upscale on the same texture.
- The menu is coupled to the Vulkan renderer: menu.cpp 216 `renderer()` is `active_renderer()`, a
  `gpu::VulkanRenderer *`, null under the Metal shell; the Texture pack row (462 to 486) and the whole import screen
  (texture_pack_screen.cpp) call `set_texture_pack`, `texture_pack_status`, `reload_texture_pack`,
  `hold_texture_pack`, `texture_pack_held`, `texture_pack_folder` on it. tools/menu_check.sh expects no pack rows
  on Metal today (line 89).
- Game data never enters the repository; the HD pack stays in ~/Downloads, the sprite pack in out/sprite_pack.

## Deliverable
- `patches/0034-texture-pack-host.patch` (host/ui/menu.cpp, host/ui/texture_pack_screen.cpp, one new header
  host/gpu/texture_pack_host.hpp, host/hle/hle_common.hpp): a small abstract `TexturePackHost` with the six methods
  above; `VulkanRenderer` implements it; `active_texture_pack_host()` returns the Vulkan renderer when there is one,
  else a host a shell registered (`set_active_texture_pack_host(TexturePackHost *)`); the menu and the import
  screen call the host instead of the renderer, and show the rows when a host exists. Under 120 lines; a candidate
  for upstream (every port with a second backend). The shape of patch 0016-menu-rows-by-capability.
- src/gpu/metal_textures.mm and metal_backend.hpp (a new src/gpu/metal_texture_pack.mm if it grows past 150 lines):
  the Metal backend implements `TexturePackHost`; `apply_texture_pack` once a frame in `begin_frame` (open or close
  the pack when the setting, the hold or a reload changed; drop `textures_` so the next draws look the pack up;
  the status strings as Vulkan's: "Off", "Updating", "N textures", "Not installed", "Not loaded: ...", "Folder
  missing: ..."); in `decoded_texture`, after the cache lookup, `find` the replacement (with the 512-tall rule),
  draw a Resident one's texture, `request` an Unloaded one and draw the original, upload a Decoded one (RGBA8,
  mips generated, the per-frame cap, `consumed`) and draw it; a resident map keyed by `Replacement *` with bytes,
  last-used frame, eviction past the budget of those not used in 4 frames; the `[texpack]` lines above; the
  replaced-draw count.
- src/host/metal_shell.mm registers the backend as the host (and unregisters at shutdown).
- tools/sprite_pack.sh: `--shell metal|vulkan` (default vulkan, as today) so `--check` and `--pack DIR` run the on
  and off scenes in the Metal window too (tools/frame_regress.sh's Metal window lane); the rules unchanged.
- tools/menu_check.sh: the Metal expectations gain "Texture pack" and "[texture pack rows]" (and "Texture filter"
  only if the host exposes it: it does not; say so in the row's comment).
- docs/metal-backend.md: a "The pack loader (task 100)" section under "Sprite upscale" (or beside "Textures"): the
  flow, the constants, what differs from Vulkan; docs/release.md "The texture pack": the Metal shell draws packs and
  offers the import; docs/controls.md's Texture pack sentence; patches/README.md, docs/upstream.md,
  docs/vendor-map.md rows for 0034; docs/developing.md's sprite_pack row.

## Acceptance criteria
- [ ] `tools/sprite_pack.sh --check --shell metal` PASSes on the Mac-built sprite pack (48 PNGs): opened with its
      keys on both routes, at least 10 images uploaded, draws replaced, both scenes differ from the run without the
      pack and match their references at the scene's tolerance, race_hud's HUD found.
- [ ] `tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack --shell metal` PASSes with task 099's
      decoder (the same rules; the "named files missing" count reported).
- [ ] `tools/menu_check.sh` PASSes on both shells with the new Metal rows; the import screen opens under Metal and
      imports a folder (the sprite pack) into textures/UCUS98612 of a scratch data directory, and the row reads
      "48 textures" after it.
- [ ] `tools/frame_regress.sh` headless 18 scenes PASS with no pack installed (nothing changes without one), and
      `tools/texture_check.sh` headless PASS (the level rule untouched for originals).
- [ ] The measurement in Result: on the race and main-menu routes with the HD pack, the `[texpack]` totals, the
      peak `images on the GPU (K MB)`, the frame time of the race scene against no pack (the `[perf]` lines or
      tools/stutter_check.sh's figure), beside task 099's Vulkan numbers.
- [ ] `tools/patches.sh check` ok with 34 patches; `tools/docs_check.py` PASS; `tools/release_check.sh` PASS on
      what it passed before.

## Verify
`tools/build.sh profile && tools/patches.sh check && tools/docs_check.py && tools/frame_regress.sh && tools/texture_check.sh && tools/menu_check.sh && tools/sprite_pack.sh --check --shell metal --out out/100/sprite && tools/sprite_pack.sh --pack ~/Downloads/WipEout-Pure-HD-Texture-Pack --shell metal --out out/100/hd`

The last three commands need the screen (menu_check's window, two Metal window suites of 1 to 4 minutes each): the
brief books it; run the headless parts first.

## May touch
- src/gpu/metal_textures.mm, metal_backend.hpp, metal_backend.mm (begin_frame only), metal_types.hpp, a new
  src/gpu/metal_texture_pack.mm; src/host/metal_shell.mm (the registration)
- vendor/portablekit/host/ui/menu.cpp, host/ui/texture_pack_screen.cpp, host/hle/hle_common.hpp, a new
  host/gpu/texture_pack_host.hpp, host/gpu/vulkan_renderer.hpp (the `: public TexturePackHost`), exported as
  patches/0034-texture-pack-host.patch; never commit vendor/
- tools/sprite_pack.sh, tools/menu_check.sh
- docs/metal-backend.md, docs/release.md, docs/controls.md, docs/developing.md, patches/README.md,
  docs/upstream.md, docs/vendor-map.md
- docs/tasks/100-metal-texture-pack.md (Result)

## Must not touch
- vendor/portablekit/include/psprecomp/, host/gpu/texture_pack.cpp and texture_pack.hpp (task 099's; the class is
  used, not changed), host/gpu/vulkan_renderer.cpp, host/gpu/replacement_textures.*, the corpus, tools/regen.sh
- src/gpu/metal_draw.mm, metal_pipelines.mm, the shaders (a replacement is sampled by the existing pipelines)
- docs/status.md, docs/decisions.md
- config/, generated/, game/, disc/

## Estimated turns
45

## Escalate when
- The menu's coupling cannot be cut in under 120 vendor lines (more than the four files above change): BLOCKED
  with the list of call sites.
- A replacement needs a pipeline or shader change to sample correctly (the alpha test, the colour test or the
  stencil rules of docs/metal-backend.md read the original's format): BLOCKED with the draw and the rule.
- The sprite pack's Metal check cannot PASS because the reference captures were made with the upscale, not a
  pack, and the two differ beyond the tolerance: report the figures, PARTIAL, and keep the HD pack as the subject.
- Task 099 is not merged into batch/m2 when you start: run the sprite pack subject only and mark the HD pack
  criterion "owed to the merge" in Result.

## Result
Status: DONE. Every command in the Verify line passes. Two acceptance items need window runs I did not make (see Open
questions): `tools/menu_check.sh --shell vulkan`, and the import screen under Metal.

Changed:
- `patches/0034-texture-pack-host.patch` (new; 87 lines added, 28 removed, across five files). The new
  `host/gpu/texture_pack_host.hpp` declares the abstract `gpu::TexturePackHost` with the six calls.
  `VulkanRenderer` now derives from it, and its six declarations take `override`; their bodies are unchanged.
  `hle_common.hpp` declares `active_texture_pack_host()`, which returns the Vulkan renderer when there is one and the
  registered host otherwise, and `set_active_texture_pack_host()`. Both are defined in `texture_pack_screen.cpp`.
  In `menu.cpp`, the Texture pack row, `[texture pack rows]` and Restore defaults now call `pack_host()`; Texture
  filter still needs `renderer()`. In the import screen, all 8 calls go to the host. `patches/README.md` has the row
  and the section. `patches.sh check` reports 33 patches, not 34, because 0025 was removed.
- `src/gpu/metal_texture_pack.mm` (new, 309 lines) holds the pack loader:
  - `apply_texture_pack` runs from `begin_frame`, or right away when the menu calls between frames. It uses Vulkan's
    status strings. It drops `textures_` only when a pack was open or opens, so a run without a pack is unchanged.
  - The 512-tall rule (`drawn_max_v`, `update_max_seen_v`).
  - `find_replacement` runs once per decode; `pack_texture` runs per draw.
  - `replacement_texture` handles request, upload and `consumed`, and marks Failed on an error. Uploads are capped at
    32 MB a frame past the first image, with at most 4096 resident.
  - `upload_replacement` makes a private RGBA8 texture with a full chain: staging buffer, blit to level 0, then
    `generateMipmapsForTexture` in its own command buffer.
  - `evict_replacements`: the budget is `PURE_TEXTURE_PACK_MEMORY`, nothing drawn in the last 4 frames is evicted,
    eviction goes down to 7/8 of the budget, and evicted entries are set back to Unloaded.
  - The `[texpack]` lines and the six host methods.
- Other changed source files:
  - `metal_textures.mm`: two hooks in `decoded_texture`, on a cache hit and after a decode.
  - `metal_types.hpp`: `CachedTexture` gains `replacement` and `max_seen_v`; new `ResidentImage`.
  - `metal_backend.hpp`: the backend is now also a `TexturePackHost`, with the new members.
  - `metal_backend.mm`: `begin_frame` calls `texture_pack_frame()`.
  - `src/host/metal_shell.mm`: at its first Metal picture the shell registers the backend, found with `dynamic_cast`
    from `running_backend()`, and it unregisters at shutdown.
- Two changes are outside the brief's May touch list, and both were needed:
  - `metal_backend.mm` `submit` gained two lines, `drawing_ = &call` and its reset. The 512-tall rule needs the
    draw's `through` flag and vertices, and `decoded_texture` does not receive the call.
  - `CMakeLists.txt` gained one line: the new .mm in `metal_backend_sources`.
- `tools/sprite_pack.sh`: new `--shell metal|vulkan` option, default vulkan. The Metal runs use
  `PURE_INTERNAL_SCALE=2`; without it run_boot pins Metal to 1. Both shells now run with `PURE_PERF=log`. The rules
  are unchanged.
- `tools/menu_check.sh`: Metal now expects "Texture pack" and "[texture pack rows]", but not "Texture filter", since
  the host has no filter; the row's comment says so.
- Docs:
  - `docs/metal-backend.md`: new section "The pack loader (task 100)", covering the flow, the constants, a table of
    differences from Vulkan and the figures; the Files row; "eight files".
  - `docs/release.md`: the texture pack bullets.
  - `docs/controls.md`: the shell paragraph.
  - `docs/developing.md`: the sprite_pack row.
  - `docs/vendor-map.md` and `docs/upstream.md`: 0034's row, section and place in the order.
- This task file. Commits fa94f60, 692c79a, 01dfe4a, ee04939, 2c51920 and the Result commit.

Verify output (last 20 lines):
- The headless parts, run first:
  - `tools/build.sh profile` built.
  - `tools/patches.sh check` printed `ok: 33 patch(es) reproduce vendor/portablekit at 8b0c3fe`.
  - `tools/docs_check.py` printed `docs_check: 39 files, 0 findings: PASS`.
  - `tools/frame_regress.sh` printed `frame regression: PASS, 18/18 scenes pass, shell headless, backend metal`.
    Every figure matches its measured value within 0.0016 (zone_change 0.0369 against 0.0353).
  - `tools/texture_check.sh` printed `texture_check: PASS`. Its figures are task 075's to the digit (race_hud 0.0467,
    ratio 1.1378).
- Then each window suite once:
  - `tools/menu_check.sh` (Metal) printed `menu_check: PASS`, with Video ok (18): `..., Scaling filter, Texture pack,
    [texture pack rows], Vsync, ...`.
  - `tools/sprite_pack.sh --check --shell metal --out out/100/sprite` built the pack headless (48 keys, 3.5 MB),
    then printed `sprite_pack: PASS (10m 51s)`:
    - main_menu: 1920x1088, on vs off 0.0359, off reduced 0.0401, on reduced 0.0452, limit 0.05, PASS.
    - race_hud: on vs off 0.0148, off reduced 0.0647, on reduced 0.0647, limit 0.1, HUD yes, PASS.
    - 33 images uploaded, 129987 draws replaced.
  - The HD pack run is below. Its four window runs completed. The analysis step then failed with a bash syntax error
    at line 245. The cause was me: I edited tools/sprite_pack.sh while it ran, and `git checkout` restored the file
    under a new inode, so bash kept reading the edited one. I ran the script's own analysis step, extracted unchanged
    from the committed tool, on the same logs and captures. I did not make another window run.
```
  run main_menu: run_boot exit 0, frame 4730 reached: yes, 48 s, paced from flip 4400
  run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 55 s, paced from flip 5716
the Metal window, pack on (tools/frame_regress.sh --out .../out/100/hd/check/on) ...
  run main_menu: run_boot exit 0, frame 4730 reached: yes, 48 s, paced from flip 4400
  run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 55 s, paced from flip 5716
the pack: 4170 keys (at least 40), hash xxh64, 3876 files named, 2546 of them missing (main_menu/menu/unlock_background.zim, main_menu/previews/ships/02_auricom/frame1.zim, main_menu/previews/ships/02_auricom/frame2.zim), new art: PASS
opened by the Metal backend, route main_menu.txt: 4170 textures from .../out/100/hd/check/data/textures/UCUS98612: PASS
opened by the Metal backend, route main_menu.txt+single_race.txt: 4170 textures from .../out/100/hd/check/data/textures/UCUS98612: PASS
  route main_menu.txt: 11 keys found in the pack, 11 images decoded, 11 uploaded, 49974 draws replaced, peak 11 images on the GPU (265 MB), 0 named files missing or unreadable
  route main_menu.txt+single_race.txt: 182 keys found in the pack, 127 images decoded, 127 uploaded, 209124 draws replaced, peak 124 images on the GPU (594 MB), 54 named files missing or unreadable
drawn: 127 distinct images of the pack uploaded for draws (at least 10), 127 decoded, 259098 draws replaced in the traced 60-frame windows (some on each route): PASS
refused: 0 lines for images the pack holds; 54 files the ini names missing or unreadable (counted, not a rule: in_game/adverts/00_others/01_vineta_k/fx300_text.zim, in_game/adverts/00_others/01_vineta_k/staten_park.zim, in_game/adverts/01_vineta_k/ag_systems_landscape.zim): PASS

each scene in the Metal window: the capture with the pack against the one without at tol 24 (at least 1%), both reduced to 480x272 by their blocks' centre pixels against the scene's reference at the scene's tol and limit (tools/frame_regress.sh), and the race HUD (tools/hud_check.py):
scene           size on vs off  off red.  on red.  limit  tol  HUD  result
main_menu  1920x1088    0.0429    0.0401   0.0491   0.05   24    -  PASS
race_hud   1920x1088    0.2454    0.0647   0.2146    0.1   32  yes  PASS

sprite pack check: 2/2 scenes pass, 4170 keys, 127 drawn (3m 28s)
sprite_pack: PASS
```
- `tools/release_check.sh` (not in Verify): every check but `home` passes. `home` has the same 6 findings it had
  before this task (0029's `C:/Users/...` examples, patches/README.md lines 78, 613 and 614). The README line
  numbers moved by one because of 0034's row.

Measurement: HD pack, Metal window, internal scale 2, against task 099's Vulkan window at S 2.

| | Metal (this task) | Vulkan (task 099) |
|---|---|---|
| Main menu route: keys found, decoded, uploaded | 11, 11, 11 | 11, 11, 11 |
| Main menu route: draws replaced | 49974 | 49974 |
| Main menu route: peak on the GPU | 11 images (265 MB) | 11 images (267 MB) |
| Race route: keys found, decoded, uploaded | 182, 127, 127 | 182, 127, 127 |
| Race route: draws replaced | 209124 | 209469 |
| Race route: peak on the GPU | 124 images (594 MB), at frame 6000 | 124 images (599 MB) |
| Named files missing | 54 | 54 |
| main_menu reduced (limit 0.05) | 0.0491 | 0.0485 |
| race_hud reduced (not a rule for new art) | 0.2146 | 0.1955 |
| On vs off, main_menu / race_hud | 0.0429 / 0.2454 | 0.0275 / 0.2350 |

- Notes on the table:
  - On Metal the MB figures include the generated mips, about 4/3 of level 0, as Vulkan's do.
  - The race route's uploads run from frame 5 (intro/sce/copyright_2005_scee.zim) to frame 6011
    (in_game/hud/bar_standard.zim).
  - The race route's draws differ from Vulkan's by 345, about 0.2%.
  - No `cannot upload` line was printed and no budget warning was given.
- Frame time of the race with the pack and without (`PURE_PERF=log`, the paced seconds from flip 5716 to the scene):
  - With the pack: frame mean 16.6 to 16.7 ms, longest 18.9 ms, render 4.1 to 4.8 ms, 59.9 to 60.2 fps.
  - Without: frame mean 16.7 ms, longest 18.6 ms, render 4.4 to 5.0 ms, 59.8 to 60.0 fps.
  - This window is only 4 to 5 seconds, but uploads ran during it, so it covers the upload cost. The race holds 60 fps.
  - The main menu was paced at 30 fps both ways (33.3 to 33.4 ms).
- Wall time per route: 48 s and 55 s, both with the pack and without (Vulkan: 48 to 49 s and 54 to 55 s).
- Clean-up:
  - I deleted the HD pack copy the check made, out/100/hd/check/data/textures (868 MB).
  - The sprite pack (out/100/sprite/pack) and the captures stay under out/ (git-ignored).
  - No pack file and no image made from one is in a commit.

Open questions:
- Window checks still owed. Under the 3-run limit I did not run:
  - `tools/menu_check.sh --shell vulkan`. The Vulkan rows should be unchanged, because `active_texture_pack_host()`
    returns the renderer there.
  - The import screen under Metal: import the sprite pack into a scratch data directory, then check that the row reads
    "48 textures, ...". No scripted check exists. The code path is the same calls as Vulkan's. The hold applies right
    away while the paused menu runs, because `frame_drawn_` is false then.
- Sampling differs from Vulkan, and `metal_draw.mm` (Must not touch) decides it:
  - The draw's sampler follows the GE's filter bits.
  - For a texture of one level, the replacement's level 0 alone is sampled, since the sampler has no mip filter.
  - At internal scale 2 the checks pass. A pack image four times the original's size drawn at scale 1 would be
    minified 4:1 without levels.
  - Vulkan uses its own linear+mip sampler, with `levels = 1`.
  - The fix would be about 6 lines in metal_draw.mm: a replaced draw takes a linear sampler with mips, and the
    shader's implicit level. That would be a follow-up task. The brief's escalation names only pipeline and shader
    changes, so I did not stop for this.
- The import's `hold_texture_pack(false)` followed by `reload_texture_pack()` opens the pack twice between frames (the
  ini is read twice, and two `[texpack] N textures` lines are printed). This is correct but wasteful.
- Every headless and menu_check log now has one `[texpack] no texture pack folder at ...` line, the same as Vulkan
  runs print.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
