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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
