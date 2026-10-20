# Patches against the vendored framework

Applied in numeric order by `tools/vendor_setup.sh` (`git apply` inside `vendor/portablekit`, at the commit in
`vendor/PIN`). `tools/patches.sh check` applies the series to a clean checkout of the pinned commit and compares it
with the vendor tree; `tools/patches.sh export NNNN-slug` writes a new patch from the vendor tree's uncommitted
changes, numbered above the last one. To change a patch inside the series, `tools/patches.sh open` makes it a branch
of one commit a patch in out/patch-series and `tools/patches.sh close` writes the commits back and brings the vendor
tree to them (task 095; the script's header has the steps). The series has one patch per framework topic (task 052); which patches could
go upstream, what a pull request would carry and what it needs first: `docs/upstream.md`.

## Old numbers
Task 052 (2026-10-07) regrouped the twenty patches of tasks 001 to 048 into nine, one per topic (the series has grown since; the table above is current), without
changing a byte of the vendor tree. The task files (the record), a few strings the tools print, two config comments
and comments inside the vendor tree itself cite the old numbers: since task 095 only the two "patch 0021" of
`include/psprecomp/allegrex_context.hpp` (now 0009-vfpu-rounding), left because a change there recompiles the corpus
(the record format's "patch 0014" and "patch 0017" moved to `src/tools/` with it and name their fields instead);
since task 053 the docs name the new patch with the task that made the change, and the history files under
`docs/history/` mark an old number "old". This is where each went. A patch split by file
went to more than one new patch. 0016 was never used.

| Old patch | New patch |
|---|---|
| 0001-embed-nids-verbatim | 0001 |
| 0002-ring-not-empty-while-aus-pending | 0006 |
| 0003-framebuffer-texture-prefers-exact-target | 0003 |
| 0004-stencil-as-alpha | 0002 (ge_state.{hpp,cpp}), 0003 (ge.frag, vulkan_renderer.cpp) |
| 0005-alpha-test-never-always | 0003 |
| 0006-shadow-volumes-and-dual-source | 0003 |
| 0007-free-target-descriptors-before-pool | 0003 |
| 0008-depth-write-back-at-signal | 0003 |
| 0009-ge-backend-seam | 0004 |
| 0010-shell-seam | 0004 |
| 0011-host-wait-real-time | 0005 |
| 0012-ui-platform-init-in-shell | 0004 |
| 0013-texture-mapping-modes | 0002 (ge_state), 0003 (a renderer comment), 0004 (ge_record_format.hpp) |
| 0014-texture-mip-levels | 0002 (ge_state), 0003 (a renderer comment), 0004 (ge_record_format.hpp) |
| 0015-savedata-list | 0007 |
| 0017-colour-test-dither-clip | 0002 (ge_state), 0003 (a renderer comment), 0004 (ge_record_format.hpp, record_backend.cpp) |
| 0018-sas-reverb | 0008 |
| 0019-savedata-no-key-mode | 0007 |
| 0020-vfpu-dot-rounding | 0009 |
| 0021-vfpu-cross-horizontal | 0009 |

## The series
Kinds: Layout constant, Bug, Missing feature, Tooling, Speed, Behaviour, Fidelity. The dependencies are in
`docs/upstream.md`; every patch applies after the ones before it.

| Patch | Old | Kind | Upstream | What |
|---|---|---|---|---|
| 0001-cmake-embed-nids-verbatim | 0001 | Bug | candidate | `VERBATIM` on the NID table's embedding command, so a profile's `config/nids.csv` survives the shell |
| 0002-ge-state-commands | 0004, 0013, 0014, 0017 (ge_state) | Missing feature | candidate | GeState parses the stencil, the write masks, the texture map modes, the mip levels, the colour test, dithering and CLIPENABLE into `DrawCall` |
| 0003-vulkan-renderer-fixes | 0003, 0004 (renderer), 0005 to 0008, 0013/0014/0017 (comments) | Bug, missing feature | candidate | The Vulkan renderer: framebuffer textures, stencil as alpha, the alpha test's numbering, shadow volumes and dual source, the descriptor pool at shutdown, depth written back at SIGNAL |
| 0004-ge-backend-and-shell-seams | 0009, 0010, 0012, 0013/0014/0017 (record format) | Missing feature | candidate | `gpu::GeBackend` and `host::Shell` behind the HLE (D-003, D-007): the vulkan and null backends, the vulkan and headless shells (the record backend and its .gerec format live in `src/tools/` since task 095) |
| 0005-kernel-host-waits-and-pacing | 0011 | Behaviour (headless pace) | candidate | Only network waits hold the unpaced clock to real time; the shell decides whether the clock is paced |
| 0006-mpeg-ring-not-empty-while-aus-pending | 0002 | Bug | candidate | `sceMpegRingbufferAvailableSize` reports the ring one packet short of empty while access units are queued |
| 0007-savedata-list-and-no-key-mode | 0015, 0019 | Missing feature | candidate | List requests answered with a choice (script, PSP-style list, or a safe default); saves without a game key written and checked in mode 1 |
| 0008-sas-reverb | 0018 | Missing feature | candidate | The SAS reverb (the SPU's reverberator, nine presets) and the voices' effect sends |
| 0009-vfpu-rounding | 0020, 0021 | Fidelity (D-013) | the rules; the test mode is ours | VFPU dot products, cross products and horizontal sums round as a PSP does; generated units built with `-ffp-contract=off` |
| 0010-vulkan-viewport-into-clip-space | (task 056) | Bug | candidate | The GE viewport's x and y folded into the draw's transform and the `VkViewport` the whole target, so an offset GE viewport keeps column 0 and row 0 (the race HUD) |
| 0011-vulkan-texture-mapping | (task 057) | Missing feature | candidate | Texture map modes 1 (the texture matrix, s and t divided by q per pixel) and 2 (the environment map from the normal and two lights) drawn by the Vulkan renderer, as the Metal backend draws them; `<prefix>_NO_TEXMAP` draws every draw with its UVs |
| 0012-vulkan-mipmaps | (task 058) | Missing feature | candidate | The mip levels a draw names uploaded by the Vulkan renderer and sampled at the level the GE's rule picks (auto, constant, slope), the mip filter from the minification filter's bits, as the Metal backend does; `<prefix>_NO_MIPMAPS` samples level 0 alone |
| 0013-vulkan-colortest-depthclamp | (task 059) | Missing feature | candidate | The GE's colour test (NEVER, ALWAYS, EQUAL, NOTEQUAL under COLORTESTMASK against COLORREF, a discard after fog) and CLIPENABLE's depth clamp (near plane only, screen z clamped per vertex, MINZ/MAXZ as clip distances, `depthClampEnable`) drawn by the Vulkan renderer, as the Metal backend draws them; `<prefix>_NO_COLOR_TEST` and `<prefix>_NO_DEPTH_CLAMP` restore the old paths |
| 0014-vulkan-16bit-dither | (task 060) | Fidelity | candidate | Draws into 5650, 5551 and 4444 targets blended in `ge.frag` on the colour read as the render pass's own input attachment, then dithered by the GE's matrix and cut to the format's bits, as the Metal backend's `ge_fragment_16`; `<prefix>_NO_DITHER` draws them at 8 bits a channel as before; `<prefix>_SHOW_TARGET` presents an offscreen target |
| 0015-vulkan-fb-texture-wrap | (task 063) | Fidelity | candidate | A render target sampled as a texture takes the GE's wrap mode: the texture's own coordinates wrapped per axis (REPEAT modulo 1, CLAMP between the centres of the edge texels) in `ge.frag`, then placed in the target's copy, as the Metal backend does; the billboards' adverts show instead of their first row stretched into bars |
| 0016-menu-rows-by-capability | (task 064) | Behaviour, tooling | candidate | The Esc menu draws a row only when its feature exists: `GameProfile::features` (`MenuFeatures`: ad hoc play, the right-stick camera, the mouse camera) and five `Shell` answers (frame interpolation, the performance overlay, each aspect, touch controls, the API's name), every default today's; `<prefix>_MENU_DUMP` prints each tab's rows when the menu opens |
| 0017-internal-scale-by-backend | (task 067) | Behaviour | candidate | The menu's Resolution row asks the GE backend, not the Vulkan renderer: `GeBackend::supports_internal_scale()`, `set_internal_scale()` and `target_size()` (defaults: no, nothing, 480x272), the Vulkan backend forwarding to its renderer as the menu did; `gpu::running_backend()` for the menu; `GameProfile::default_internal_scale`, the scale a new player starts with (unset: the framework's 2) |
| 0018-vulkan-effects-at-1x | (task 068) | Fidelity | candidate, behind a profile switch | Each Vulkan target the size its stride gives (D-015, as the Metal backend draws): the internal resolution for a buffer at least 480 pixels wide, 480x272 for a narrower one (the bloom's buffers, the billboards'), so the bloom's blur and glow stay the PSP's at any scale; every pass, viewport, scissor, copy, blit and read-back takes the target's own size, and guest memory gets the centre pixel of each block |
| 0019-game-option-rows | (task 070) | Missing feature | candidate | A game's own settings as menu rows: `GameProfile::options` (`GameOption`: key, label, choices, help, default, tab), each kept as an index in settings.ini (`game.<key>`), `<prefix>_<KEY>` deciding it for a run, `settings::game_option(key)` for the port, and a Game section at the end of the tab it names; no option, no section |
| 0020-vulkan-texture-detail | (task 076) | Fidelity, enhancement | candidate, behind a profile field | Texture detail at the internal scale in the Vulkan renderer, as the Metal backend draws it: with the game option `GameProfile::texture_detail_option` names at 1, a draw that samples a texture with mip levels and is not a 2D draw has the GE's D lowered by 16 x log2 of its target's scale whatever the rule, and `ge.frag` samples that level through the coordinates' own gradients (`textureGrad`, `texture_params.x` bit 21) with an anisotropic sampler (`samplerAnisotropy`, at most 16 taps); no option named, or the option at 0, draws as before |
| 0021-content-packs | (task 078-download-packs-menu, the Mac line) | Missing feature | candidate | Content packs among a game's save folders: `SaveFolder::content_pack` marks a folder the game loads as content (a download pack) and `GameProfile::content_packs_label` names the System tab's section for them, after Saves: how many the memory stick holds, each pack Installed or Not installed, and "Install <label>…", which opens Import's folder browser (`ui::open_import()`); Export and Back up saves leave content packs out; Import skips a content pack's SAVEDATA_FILE_LIST entry that is not a printable name; nothing marked and no label, nothing changes |
| 0022-vulkan-async-readback | (task 077-vulkan-readback-stutter) | Performance | candidate (any discrete GPU) | The depth write-back at a GE SIGNAL (`write_back_depth`, the lens flare's CPU depth test) records its copy into the frame and stores the copy the frame before recorded, instead of submitting the half-recorded frame and fence-waiting the queue every race frame; the guest reads depth one frame old. `<prefix>_SYNC_READBACK=1` restores the synchronous drain |
| 0023-vulkan-cached-window-capture | (task 078-vulkan-effect-slowdowns) | Performance, tooling | candidate (any discrete GPU) | A window capture (the input script's `shot`) reads its buffer from a HOST_CACHED memory type when the device has one, instead of the first HOST_COHERENT type (uncached on NVIDIA): `write_bmp` reads it byte by byte, which took 110 to 160 ms a capture on an RTX 3080 and now about 4 ms, wait included; the picture is the same |
| 0024-audio-resync-counter | (task 079) | Tooling | candidate | The sink's stalled-producer jump (a producer's cursor under the device's read position plus 512 frames, snapped to plus 2048: an audible skip with the ring never dry) is counted: `resyncs=` and `resynced=` (frames skipped) on the `[audio]` trace line and its shutdown total, with `lead=` (frames written ahead of the device). The counter only; the rate-matching the slug names is not in it (task 079 stopped at the characterization) |
| 0025-guest-time-split | (task 082; removed by task 095) | Removed | none | Removed (task 095): `<prefix>_TRACE_GUEST`, the [perf] line's guest time split at the HLE boundary, served task 082's one measurement and nothing in `tools/` or `src/` set it afterwards; the number stays unused |
| 0026-corpus-inlining | (task 083) | Performance | **candidate of the first order (every Windows port pays this today)** | The MSVC-style branch of `portablekit_add_game` compiled every generated unit, and the overlay targets, `/O2 /Ob0`: optimization on, inlining off, where the clang path inlines. Both sites now pass `/Ob2`. The recompiled code is almost all small functions, so the cost was the whole Windows guest anomaly: the rig's `game` bucket fell from about 10 to about 3.6 ms a game frame. `/bigobj` and the opt level are unchanged; no FP contraction flag (see the section) |
| 0027-window-size-switch | (task 084) | Tooling | candidate | `<prefix>_WINDOW_SIZE=WxH` opens the Vulkan renderer's window at W x H instead of 480x272 times `video.window_scale`, so a check can run a window of another shape (21:9 for `tools/aspect_check.sh`, the Fill aspect of D-020); unset or malformed, the window is as before |
| 0028-vulkan-orthographic-fit | (task 085) | Behaviour | candidate | Under the Fill aspect the Vulkan renderer's interface fit (2D draws into the shown framebuffer pulled in about the screen's centre to square pixels) takes transformed draws under an orthographic projection with lighting off too, not only through mode: their clip x and y scaled after `viewport_into_clip`, in the draw's transform and in its frame-interpolation summary alike; a draw at least 470 of the 480 PSP pixels wide through its transform stays spread unless it is textured and lies within the screen (2 PSP pixels of margin each side: a layer of interface art); `<prefix>_NO_ORTHOGRAPHIC_FIT` fits through-mode draws alone, as before; Original and Stretch draw as before |
| 0029-windows-file-url | (the planning session, 2026-10-13, after Erik's Windows play) | Bug fix | **candidate of the first order (every Windows port's folder buttons)** | The menu's folder buttons (Open the data folder, the saves, backups, textures and fonts folders) build a `file://` URL for `SDL_OpenURL` by percent-encoding the whole path, so a Windows path came out `file://C%3A%5CUsers%5C...`, which Explorer refuses: nothing opened. The three copies of `file_url` (menu.cpp, font_menu.cpp, save_screen.cpp) now put three slashes before an absolute path, keep the drive's colon and turn backslashes into slashes: `file:///C:/Users/...`; macOS and Linux paths come out as before (`file:///Users/...`) |
| 0030-vblank-period | (task 089) | Behaviour | candidate | The kernel's vblank period a runtime value: `Kernel::vblank_period_us()` and `set_vblank_period_us()` (default `kVBlankPeriodUs`, the PSP's 16683 us; a new period applies from the next vblank, which stays where it was due, and the count of vblanks stands), read by the tick (`process_timers`), `last_vblank_us()` (now the vblank's own time, kept at the tick), the media HLE's frame grid (`frame_start_us`'s step), vblank duration, hcount and vblank flag, and frame interpolation's game frame (read from the kernel through `pacing::set_vblank_period_source`; `game_frame_us()` and `game_rate()` follow it, 60 at the PSP's period as before, 120 for a game at 60 whose vblank runs at 120 Hz, and a present clock follows a change at its next flip). Nothing moves at the default period |
| 0031-audio-sink-late-writes | (task 098, the planning session, 2026-10-19) | Behaviour | candidate (with 0024) | The sink's stalled-producer jump fired on any cursor under the device's read position plus 512 frames and snapped it 2048 ahead: 46 ms of silence in that channel, the click heard after every dip. Now only a cursor more than `kLateLimit` (2048 frames) behind is a stall and snaps as before (`resyncs=`); a cursor less behind drops just the frames already played (`late=`), writes the rest where it belongs, and any write under the sink's 2048-frame lead (`lates=` events; task 501 widened this from 512 frames, with a device present only) arms a lead rebuild: the SDL stream's frequency ratio goes to 0.99 (`SDL_SetAudioStreamFrequencyRatio`, about 17 cents) until the device has read `kRecoveryFrames` (2048 / 0.01, about 4.6 s), by when every channel keeping real time has 2048 frames of lead again (`ratio=` on the trace line). The stream call is made outside the sink's lock, because the device callback holds the stream's lock while it takes the sink's. `<PREFIX>_AUDIO_SNAP=1` restores the old rule for A/B. A producer below real time for longer than the limit still snaps: the deficit must surface somewhere (task 081's analysis). |

## What each patch does
The paragraphs are the rows the old patches had, edited only where they named each other.

### 0001-cmake-embed-nids-verbatim
Old 0001. `portablekit_add_game` passes `-DINPUT=a.csv|b.csv` to the shell unquoted when a profile ships
`config/nids.csv`; the `|` becomes a pipe. Adds `VERBATIM`.

### 0002-ge-state-commands
The ge_state.{hpp,cpp} sections of old 0004, 0013, 0014 and 0017, in that order. No backend draws with any of it
here; 0003 and the Metal backend in `src/` read it, and our record format (`src/tools/ge_record_format.hpp`) writes it.
- Stencil and write masks (old 0004): the GE state ignored the stencil (0x24, 0xDC, 0xDD) and the write masks (0xE8,
  0xE9). Parses them into `DrawCall::stencil` (`StencilState`), `color_write_mask` and `alpha_write_mask`.
- Texture mapping modes (old 0013): the GE state ignored TEXMAPMODE (0xC0: the map mode in bits 0..1, the texture
  matrix's source TEXPROJMAP in bits 8..9) and TEXSHADELS (0xC1: the two lights of an environment map in bits 0..1 and
  8..9), so no backend could draw Wipeout Pure's environment-mapped draws (the ships' hulls and canopies, glass and
  shiny roofs: 46 to 125 draws a race frame) or its texture-matrix draws (40 on Vineta K) other than with their UVs.
  Parses both into `DrawCall::texture_map` (`TextureMapState`: `map_mode`, `proj_source`, `shade_light_u`,
  `shade_light_v`), so they leave the ignored-command list.
- Mip levels (old 0014): the GE state ignored a texture's mip levels: TEXADDR1 to 7 (0xA1 to 0xA7), TEXBUFWIDTH1 to 7
  (0xA9 to 0xAF), TEXSIZE1 to 7 (0xB9 to 0xBF), the level count in TEXMODE (0xC2 bits 16..18), TEXLEVEL (0xC8: the
  level mode in bits 0..1, a signed bias in 1/16 levels in bits 16..23) and TEXLODSLOPE (0xD0), so no backend could
  sample the smaller levels Wipeout Pure gives 70 to 87% of its textured race draws, and distant textures shimmered.
  `TextureState` carries them (`level_count`, `levels[7]` of `TextureLevel`: address, buffer width, width, height;
  `level_mode`, `level_bias`, `lod_slope`), so 23 commands leave the ignored-command list.
- Colour test, dithering, CLIPENABLE (old 0017): the GE state ignored the colour test (COLORTESTENABLE 0x27;
  COLORTEST 0xD8: the function in bits 0..1, 0 NEVER, 1 ALWAYS, 2 EQUAL, 3 NOTEQUAL; COLORREF 0xD9 and COLORTESTMASK
  0xDA, 0x00BBGGRR), dithering (DITHERENABLE 0x20 and the matrix DITH0 to DITH3, 0xE2 to 0xE5: DITHn is the row for
  y & 3 == n, four signed 4-bit offsets, column x & 3 at bits 4 x (x & 3)) and CLIPENABLE (0x1C), so no backend could
  drop the pure black pixels Wipeout Pure's glow sprites and billboard content test away (3 to 14 draws a race frame,
  fidelity difference 10), dither its 565 billboard target (difference 11) or clamp depth as the GE does with
  CLIPENABLE on (every 3D draw). Parses them into `DrawCall::color_test` (`ColorTestState`), `dither`
  (`DitherState`, with `offset(x, y)`) and `clip_enabled`, so 10 commands leave the ignored-command list (30 distinct
  remain, from 40).
- Task 095 took out `ge_state.hpp`'s notes that the Vulkan renderer samples level 0, draws every draw with its UVs
  and draws none of the colour test, dithering and CLIPENABLE: 0011 to 0014 draw them, and the GE state says what the
  GE does, not what a backend draws.

### 0003-vulkan-renderer-fixes
Old 0003, the renderer and shader sections of old 0004, old 0005 to 0008, then the renderer sections of old 0013,
0014 and 0017 (comments only: the renderer draws every draw with its UVs, samples level 0, and draws neither the
colour test, nor dithering, nor CLIPENABLE's depth clamp). Needs 0002's stencil fields.
- Framebuffer texture lookup (old 0003): `find_framebuffer_texture` picked the most recently drawn target containing a
  texture's address; Wipeout Pure's bloom blurs 0x04132000, which lies inside the 0x04110000 target, so the blur
  sampled never-drawn rows (magenta). Prefer a target starting at the address.
- Stencil as alpha (old 0004, renderer part): every draw stored its fragment alpha, so Wipeout Pure's bloom mask
  (stencil REPLACE into the 8888 alpha) was full everywhere and the whole race scene bloomed. The target's alpha is
  now written only by the stencil zpass op (REPLACE ref, ZERO; KEEP, no stencil test or masked bits leave it),
  through the fragment shader or, when the colour blend reads source alpha, the alpha blend factors (exact for ZERO,
  opaque fragments only for REPLACE); whole masked colour channels are not written. Other stencil functions and
  INCR/DECR/INVERT are logged once. `PURE_NO_STENCIL_ALPHA=1` restores the old path.
- The alpha test's numbering (old 0005): the fragment shader read the GE alpha-test function 1 as NEVER and 0 as "no
  test", but the GE numbers them like the depth test, 0 NEVER and 1 ALWAYS, so every draw that enables the alpha test
  with ALWAYS was discarded: on Vineta K that is 268 of 871 draws and 87% of the frame (track, barriers, arches,
  pillars, sky cube). Tests by the GE numbering, pushes ALWAYS for draws without the test and for clears, and compiles
  the discard out for ALWAYS instead of NEVER.
- Shadow volumes and dual source (old 0006): Wipeout Pure's ship shadows are depth-fail stencil volumes (zfail
  INCR/DECR, colour masked) and a full-screen darkening tested GREATER ref 4, which the stencil-as-alpha path alone
  drew as ALWAYS over the whole opaque world. Each target's depth image gets a stencil aspect (D32_SFLOAT_S8_UINT, else
  D24_UNORM_S8_UINT), loaded and stored by the render pass; every draw with the stencil on a 5551/4444/8888 target
  puts its test, ops, reference, compare mask and write mask (~0xE9) in the pipeline key (`stencil`,
  `stencil_values`; keys file version 3), and a clear of the alpha REPLACEs the stencil with the clear alpha. The
  stencil is exact and the alpha (what textures, blends, the display and write-back read) is its copy: after a draw
  the colour path cannot match (`alpha_follows_stencil`), the stencil is copied into the alpha before the next
  destination-alpha blend and at the end of the pass (`resolve_stencil_alpha`, 9 quads inside the pass from a fixed
  vertex slot). REPLACE under a colour blend that reads source alpha uses dual-source blending (`kAlphaDual`,
  SRC1_ALPHA) when the device has `dualSrcBlend`; the other pipelines use a SPIR-V copy with the second output moved
  off. `PURE_NO_STENCIL_BUFFER=1` (implied by `PURE_NO_STENCIL_ALPHA=1`) and `PURE_NO_DUAL_SOURCE=1` turn the parts
  off; `PURE_TRACE_STENCIL_COPY=1` logs each copy.
- Descriptors before the pool (old 0007): `VulkanRenderer::shutdown()` destroyed `descriptor_pool` and only then the
  render targets, whose `destroy_target` frees each target's two copy descriptor sets (made when the game samples a
  framebuffer, as Wipeout Pure's bloom does) back to that pool. Under MoltenVK the pool and its sets are heap objects,
  so `vkFreeDescriptorSets` wrote into freed memory: the "Heap corruption detected, free list is damaged ... Incorrect
  guard value" abort (or a hang while the crash report was written) after a race's frame exit (task 015). Destroys the
  targets, the held picture and the interpolation targets before the pool.
- Depth written back at SIGNAL (old 0008): the renderer kept depth in per-target Vulkan images and never stored it in
  guest VRAM, so Wipeout Pure's lens flare, whose GE SIGNAL 0x0200 handler reads a 4x4 block of the depth buffer
  around the sun with the CPU (through the 0x04600000 mirror), always read zeros (open sky) and was never occluded.
  Before a SIGNAL interrupt with a signal function is queued, `write_back_depth` copies the depth aspect of the GE's
  current colour target into a mapped buffer, runs the frame recorded so far and waits (as `read_back_framebuffer`
  does), and stores z = depth x 65535 as 16-bit pixels in rows of the depth stride at the depth address (480x272;
  screen-wide buffers, stride 480 or more, only). Depth images get TRANSFER_SRC usage. About 1 ms a race frame on the
  M4 Pro, 0.9 of it the GPU wait. `PURE_NO_DEPTH_READBACK=1` turns it off; `PURE_TRACE_DEPTH_READBACK=1` logs each
  write-back. The HLE side (`hle_media.cpp`) goes through the GE backend once 0004 applies. Since task 095 the
  read-back pieces are written once, here: `drain_recording` (submit, wait, go on recording; the framework's
  `read_back_framebuffer` and the depth write-back both call it, the waits as before), `host_read_memory` (the
  memory type of a buffer the CPU reads: cached and coherent, then cached, then coherent; the frame write-back, the
  depth write-back and 0023's capture pick with it, each as before) and `invalidate_writeback(memory, coherent)`.

### 0004-ge-backend-and-shell-seams
Old 0009, 0010 and 0012. It carried the record backend and the .gerec format too (with the record-format sections of
old 0013, 0014 and 0017) until task 095 moved both to `src/tools/` (`record_backend.cpp`, `ge_record_format.hpp`):
their users are ours (`--replay`, `tools/gerec/`), and the backend registers with `BackendRegistration` as the Metal
backend does. Needs 0003 (it builds on the renderer's depth write-back and its HLE call).
- The GE backend seam (old 0009; D-003, docs/ge-backend.md): `gpu::GeBackend` (`host/gpu/ge_backend.hpp`) with a
  registry (`register_backend`, `make_backend`, `BackendRegistration`) and `<prefix>_GE_BACKEND` (vulkan when unset).
  The HLE (`hle_media.cpp`) hands draws, block transfers, read-backs, the frame and depth write-backs, CPU pictures,
  captures and the draw/frame counters to the backend. `vulkan` forwards each call to the renderer method that did
  the work before (`vulkan_ge_backend.cpp`, no change in output; the renderer gains `display_image()`, which names the
  target `present()` shows). `null` draws nothing, presents black and counts draws, and needs no window: with
  `<prefix>_NO_RENDER` set it is the only backend that runs, without a window or GPU. Adds the three sources to
  `cmake/PortableKit.cmake`. Task 095 trimmed the interface to what is called through it: no `GeBackend::name()`;
  `PresentedImage` keeps `api`, the size, `pixels` (Cpu) and `image` (Metal's texture), the Vulkan backend naming
  its target by display address alone; one BMP writer, `gpu::write_bmp` (moved out of the renderer, so the null
  backend writes the same file without it); and both registries one template, `Registry<T>` (`host/registry.hpp`).
- The shell seam (old 0010; D-007, docs/ge-backend.md section 8): `host::Shell` (`host/shell/shell.hpp`: lifecycle,
  events and input, presenting, interface) with a registry (`register_shell`, `make_shell`, `ShellRegistration`) and
  `<prefix>_SHELL` (vulkan when unset; `<prefix>_NO_RENDER` means headless). The HLE (`hle_media.cpp`) owns a shell
  and a GE backend and talks to nothing else: `ensure_shell_and_backend()` makes the shell, then the backend (the
  Vulkan backend only in the Vulkan shell), `present_frame` shows the backend's image through `Shell::present`, and
  sceCtrl samples the shell's pad. `vulkan` (`vulkan_shell.cpp`) owns the `VulkanRenderer` and forwards each call to
  it unchanged (a Cpu image from another backend is uploaded into the display target first); `active_renderer()`
  gives the renderer only under it, for what needs Vulkan itself. `headless` (`headless_shell.cpp`, no SDL or GPU)
  reads the input script and the live file at pad level, one script frame per flip: `pad` and `axis` set the pad as
  the SDL shells map their gamepad, `shot` writes the GE backend's `capture_frame`, `quit` ends the run,
  key/mouse/text steps are reported once. Shared pieces moved out of the renderer and the interface: the SDL pad
  sampler (`sdl_pad.cpp`, the renderer's `Impl` derives from it), the gamepad-to-PSP mapping with SDL's button and
  axis names (`gamepad.cpp`), the input script's grammar (`script_steps.cpp`). The interface layer attaches to a
  `Shell` with a window (`Layer::attach(host::Shell &)`); the menu's resolution, texture filter and texture pack rows
  use the Vulkan renderer through `active_renderer()`. Adds the six sources to `cmake/PortableKit.cmake`. No change in
  what the Vulkan path shows (the frame regression captures are pixel-identical). Since task 095 `Shell` has no
  `shutdown`, `shutdown_ui`, `mouse_captured`, `quit_requested` or `request_quit`: nothing called them through it, and
  a shell's destructor frees what it made.
- The UI platform init in the shell (old 0012): `Layer::attach` started ImGui's SDL3 platform backend with
  `ImGui_ImplSDL3_InitForVulkan` for every shell, which is wrong for a shell that draws with another API (the Metal
  shell, task 027, needs `ImGui_ImplSDL3_InitForMetal`). The platform init moves into `Shell::initialize_ui`: the
  Vulkan shell calls `ImGui_ImplSDL3_InitForVulkan` for its renderer's window before the renderer's ImGui Vulkan
  backend (and leaves neither running on failure), and `Layer::attach` loads the fonts, calls
  only `shell.initialize_ui`, then sets the gamepad mode. The Vulkan path is unchanged.

### 0005-kernel-host-waits-and-pacing
Old 0011. Needs 0004 (the HLE sets the pacing where it makes the shell). `Kernel::advance_clock` slept up to 1 ms of
real time per clock step while any thread was in a `WaitType::Host` wait, so a network wait would see real time pass;
`user_main`'s `sceKernelWaitThreadEnd` is such a wait for the whole run, which held every unpaced (headless) run to
about 19 frames a second. `wait_host` takes `real_time` (only the adhoc network waits pass it) and the sleep applies
to those alone; `Kernel::set_paced(bool)` lets the HLE pace the clock by the shell (a shell with a window is paced,
the headless one is not), with `<prefix>_NO_RENDER` deciding until the shell exists. Headless frontend route: 2200
frames in 1.1 s instead of 115 s, same draws, same events. Windowed runs unchanged. `<prefix>_NO_RENDER` is read
once (a static, as before the patch), not at every pacing call.

### 0006-mpeg-ring-not-empty-while-aus-pending
Old 0002. `sceMpegRingbufferAvailableSize` reported the ring empty while the demuxer still held access units (the
audio fetch runs ahead and takes the last packs), so a game that ends a movie on an empty ring (Wipeout Pure) dropped
its last 16 pictures and never tore the movie down. Reports one packet short of empty while units are queued.

### 0007-savedata-list-and-no-key-mode
Old 0015, then old 0019. Needs 0004 (the `save` script step lives in the shells' script readers).
- The save list (old 0015): `hle_savedata.cpp` answered LISTSAVE with the first listed name and LISTLOAD with the
  first save that exists, so Wipeout Pure's second profile overwrote its first and LOAD offered no choice (fidelity
  difference 4, task 039). A list request (LISTLOAD, LISTSAVE, LISTDELETE, and mode 7 without a save name, which
  Wipeout Pure's PROFILE > DELETE sends and a PSP answers with a list of the game's saves) now takes, in order: the
  input script's new `save ANSWER` step (a save name, a 0-based position, `newest`, `free` or `cancel`; queued by both
  script readers in `shell/script_steps.cpp`, so headless runs answer it too); the save list (`ui/save_list.cpp`,
  new; hooked into `draw_over_game` and kept from the menu like the on-screen keyboard), when there is a choice and an
  interface: drawn over the running game in the PSP dialog's layout (banner, a column of `ICON0.PNG` icons with the
  game's newData icon for free slots, stb_image into ImGui user textures, the save's title, date, time, size and
  detail, NEW DATA), the request staying VISIBLE while the game polls, with the PSP's overwrite and delete questions
  (No first), "Save completed." and the result written when it closes (cancel: 1); Enter and Back follow the
  request's buttonSwap through the pad mapping; otherwise the newest save to load, the first free slot to save to,
  only the named save to delete, and a cancel rather than writing over or deleting anything. A list request while
  another's list is open closes it as cancelled. Adds `host/ui/save_list.cpp` to `cmake/PortableKit.cmake`.
- The no-key mode (old 0019): `hle_savedata.cpp` wrote a save plain whenever the request carried no game key, but a
  PSP (and PPSSPP) writes such a save in the save-data utility's no-key mode, mode 1: Wipeout Pure's 0x5DC-byte block
  (the firmware 1.x layout, no key field) got a plain `PROFILE.BIN` that no PSP would load, and PSP and PPSSPP saves,
  which are mode 1, met a hash check that refused them (fidelity difference 5, task 045). A request without a key (the
  short block, or a zero key) now sets `SaveFiles::no_key_mode` when the console's keys are available
  (`savedata_keys_available()`), and `write_save` then enciphers the data file in mode 1 with the console's keys
  alone, stores it at the data's own length plus the 16-byte header (41586 bytes for the 41570 of a profile, as
  PPSSPP's), lists its hash in `SAVEDATA_FILE_LIST` and signs `SAVEDATA_PARAMS` (flag 0x01, the mode-1 hash of
  PARAM.SFO; `write_flags()` says which). `data_file_hash` hashes a file whose length is not a multiple of 16 as if
  padded with zeros, which is what the PSP's hash covers (the framework only ever wrote padded files, so its own saves
  hash as before; PPSSPP's 41586-byte file failed without it). `load_save` checks PARAM.SFO's own hashes before the
  data file's for every encrypted save, as the import check does, and reports the flag and whether the file's listed
  hash was checked; `do_load` logs `PROFILE.BIN: mode 1 (no game key), PARAM.SFO's hash verified, the file's hash in
  SAVEDATA_FILE_LIST verified, decrypted` on a line of its own and a failed hash as `broken save in ...` with result
  0x80110306, and `do_save` logs the mode-1 write likewise (the `saved`/`loaded` lines keep their form). A plain save
  (flag 0, every save the port wrote before) still loads as it is; without the keys the behaviour is the old one. No
  key material: every key comes from `crypto_keys()` by slot.

### 0008-sas-reverb
Old 0018. The software SAS accepted `__sceSasRevType`, `__sceSasRevParam`, `__sceSasRevEVOL` and `__sceSasRevVON` and
dropped them, and `__sceSasSetVolume`'s effect sends (its fifth and sixth arguments) with them, so a game's reverb
never sounded: Wipeout Pure asks for HALL from the race load on, and its effects stopped dead at a pause where
PPSSPP's ring on for half a second (fidelity difference 12, task 043). `SasCore` gains a reverb unit, `SasReverb`: the
PlayStation SPU's reverberator from its public documentation (psx-spx, "SPU Reverb Formula" and "SPU Reverb
Examples": the same-side and different-side reflections, four combs, two all-pass filters in a ring of 16-bit
samples, every intermediate saturated), the nine presets by `__sceSasRevType` (1 ROOM to 9 PIPE; anything else OFF, a
new type starting from a silent ring), RevParam's delay and feedback shaping ECHO and DELAY (inferred from those two
tables, which differ only there), the voices' effect sends summed as the dry mix is, the unit's output added at the
wet volumes when the wet switch is on and the dry mix kept or dropped by the dry one. Two departures from the SPU,
both measured against PPSSPP's output of the game: the formula steps once a sample at the SAS's 44100 Hz, not at
22050 Hz between the SPU's resampling filters (at 22050 Hz the tail lasts three times as long), and the sends enter
at half their volume (the wet level is half the unity reading's at every 100 ms step of a decay). Type 0, the wet
switch off, or `<prefix>_NO_REVERB=1` leaves the output exactly as before; `<prefix>_SAS_REVERB_SPU_RATE=1` runs the
SPU's rate and filters. About 4 us of host time a 256-frame grain (5.8 ms) on the M4 Pro; `<prefix>_TRACE_AUDIO`'s
per-second line adds `reverb=TYPE reverb_us=N`, and `<prefix>_TRACE_SAS` prints each change of a voice's sends and
of the four reverb calls.

### 0009-vfpu-rounding
Old 0020, then old 0021. Changes `include/psprecomp/`, so applying it to a built tree recompiles the whole corpus.
- The dot products (old 0020): the framework computed every VFPU dot product as one C++ expression (`vdot`, `vhdp`,
  the dot lanes of `vcrsp` and `vqmul` in `allegrex_context.hpp`; the rows of `vtfm` and the elements of `vmmul` as
  loops the codegen emits inline), which clang contracts into fused multiply-adds, so the port rounded differently
  from the PSP and from PPSSPP (task 047: 20 percent of one site's `vdot.t` results off by 1 ulp, and the AI's race
  parting from PPSSPP's over seconds). `AllegrexContext::vfpu_dot` now rounds as a real PSP does (pspautotests' rule:
  exact products with a raw exponent sum, zeros and subnormals skipped, aligned to the largest exponent with two
  extra bits, truncated toward zero, summed exactly, cut to 24 bits toward zero, flushed below the smallest normal;
  infinities and NaNs on the unfused IEEE path), the `_ct` and runtime `vdot`, `vhdp`, `vcrsp` and `vqmul` use it,
  `codegen_main.cpp`'s Vtfm and Vmmul emitters call it instead of their loops, and the generated units are compiled
  with `-ffp-contract=off` so every translated instruction rounds on its own. `vfpu_dot_mode()` 1 (test only: our
  profile sets it under `PURE_TEST_RACE_CLOCK` or `PURE_VFPU_DOT=ppsspp`) gives PPSSPP's JIT rounding instead (a
  fused chain in lane order for vectors, unfused from +0 for matrix elements) for the scorecard's comparisons.
- The cross product and horizontal sums (old 0021): the cross product's lanes (`vcrsp.t`, `execute_vfpu_cross_quat`)
  and the horizontal sums (`vfad`, `vavg`, `execute_vfpu_horizontal`) rounded like the dot products before old 0020:
  `vfpu_cross_dot` gives, under the test mode, PPSSPP's JIT rule measured by task 048 (both products rounded, then
  their difference, on every one of 1592532 sampled lanes; the port's chain from lane 0 differed on 20 to 24 percent
  and was what parted Karbonis' player at 6.974 s) and, by default, the PSP's rule; Z is the two forced lanes only,
  so an infinite s.z or t.z no longer makes it NaN (pspautotests' nine cases); `vfad`/`vavg` sum in lane order
  unfused under the test mode (every sampled result) and by the PSP's rule by default (pspautotests' 15 and 15).
  `vqmul.q`, `vcrs.t`, `vmscl` and `vrot` are unchanged (not in the game's code, one product, or unmeasured).

### 0010-vulkan-viewport-into-clip-space
Task 056. The renderer made the GE viewport (`screen = ndc * scale + offset - region offset`) its `VkViewport`, and
Vulkan clips x and y at the viewport, while the GE clips them only at the scissor. A viewport that does not start at
the target's corner lost its first column and row: the race HUD's (offset 1807/1911 against the world's 1808/1912)
lost column 0 (task 025, found against the Metal backend). `interpolation::viewport_into_clip` turns the viewport's x
and y into a matrix applied after the projection, `submit` puts it in the push constants' transform, and the
`VkViewport` covers the whole target, as the Metal backend draws (docs/metal-backend.md, "How a draw is drawn"); the
z scale and offset stay in the viewport's depth range. A frame summary's projection carries the same matrix, so frame
interpolation's blended transforms keep it. Window coordinates, and with them the cull winding, are unchanged. On the
race recording the fix changes only PSP column 0 (123 pixels at 960x544 in frame 6016).

### 0011-vulkan-texture-mapping
Task 057. The renderer drew every transformed draw with its UVs through the texture scale and offset (texture map
mode 0); TEXMAPMODE and TEXSHADELS, carried in `DrawCall::texture_map` since patch 0002-ge-state-commands, went unread here. The
object block (set 1, binding 1) grows by the mode, the texture matrix, the viewer's direction (w: reversed normals) and
the texture's place in a sampled target (144 to 256 bytes), written for lit and texture-mapped draws;
`texture_params.x` gains bit 3 (mapped) and bit 4 (divide by q). `map_texture` in `ge.vert` is the Metal backend's
(`src/gpu/shaders/ge.metal`, task 036), and `ge.frag` divides s and t by q (a new varying at location 5) before the
clamps. Mode 3 and transformed sprites keep their UVs, as on Metal. Frame interpolation keeps a mapped draw's object
block, so its blended world matrix moves the reflection. `<prefix>_NO_TEXMAP` restores the old path.

### 0012-vulkan-mipmaps
Task 058. The renderer uploaded and sampled level 0 of every texture; the levels and the level rule, carried in
`TextureState` since patch 0002-ge-state-commands, went unread here. `mip_levels` takes the GE's level count when the
minification filter's bit 2 is on and every level halves the one before, lies in guest memory and outside every render
target (else level 0 alone, said once); the image then has that many mip levels, each decoded with `decode_texture`
from its own address (in the background as level 0 is), and the cache key covers every level. Such a texture is
sampled through a sampler of its own (`mip_sampler`, linear between levels). `texture_params.x` gains bits 5 and 6
(the rule: auto, constant, slope), bit 7 (linear between levels, from the minification filter's bit 1) and, from bit
8, the part of D that is the same across the draw; `mip_lod` in `ge.frag` adds the rest with the GE's float-bits
logarithm and samples with `textureLod`, as `sample_texture` in `src/gpu/shaders/ge.metal` (task 037). At an internal
scale above 1 the auto rule's gradient is taken per PSP pixel. A texture of one level is drawn as before;
`<prefix>_NO_MIPMAPS` (the name the Metal backend reads) restores the old path. Since task 095 the layout helpers
both backends need are `texture_decode.hpp`'s, written once: `bits_per_texel` (the decoder's, no longer file-local),
`indexed`, `texture_bytes`, `texture_level`, `sampled_level_count`, `mip_level_problem` (the halving and guest memory
checks; each backend adds its own render targets) and `ge_log16`; the decoder's two palette tests call `indexed`.

### 0013-vulkan-colortest-depthclamp
Task 059. The renderer kept every fragment and clipped every transformed draw at both ends of the depth range; the
colour test and CLIPENABLE with MINZ/MAXZ, carried in `DrawCall::color_test`, `clip_enabled` and `depth` since patch
0002-ge-state-commands, went unread here. The colour test is in the pipeline: `PipelineKey` gains the function,
reference and mask, which become `ge.frag`'s specialisation constants `kColorTest`, `kColorFunction`,
`kColorReference` and `kColorMask`; after fog, where the alpha test is, the fragment's 8-bit colour under the mask
is compared with the reference under it and a failing fragment is discarded (no colour, depth or stencil). Without the
test or with ALWAYS the discard is compiled out. The depth clamp follows the GE's rule with CLIPENABLE on, as
`ge_vertex` in `src/gpu/shaders/ge.metal` (task 040): `ge.vert` (`kDepthClamp`) computes the screen z times w,
clamps it to 0..65535 w for a vertex in front of the near plane, hands z / 65535 to a viewport of 0..1, and makes the
near plane, MINZ and MAXZ three `gl_ClipDistance`s; the pipeline has `depthClampEnable`, so nothing is clipped at the
depth range's ends. The z scale, offset, MINZ and MAXZ go in the environment block (496 to 512 bytes), written again
when a clamped draw needs other values. It needs the depthClamp and shaderClipDistance features (said once when the
device lacks them). The pipeline key list's version goes from 3 to 4 (18 words), so an older list is not prewarmed
once. `<prefix>_NO_COLOR_TEST` and `<prefix>_NO_DEPTH_CLAMP` (the Metal backend's names) restore the old paths.

### 0014-vulkan-16bit-dither
Task 060. The renderer drew 5650, 5551 and 4444 targets at 8 bits a channel, blended by the pipeline, and never
dithered (`DrawCall::dither` went unread). Every target stays an RGBA8 image; what changes is how a draw into a 16-bit
one writes it. The render pass's colour attachment is also its input attachment 0 (GENERAL inside the pass, a
by-region self-dependency, explicit external dependencies for the layout changes), with one pass for every target so
pipelines, framebuffers and descriptor sets stay compatible; each target has an input-attachment set (set 2 of the
pipeline layout, its own pool), bound when a pass begins (and in frame interpolation's replay). `PipelineKey` gains
`sixteen` (1 + the format), the dither switch and rows, the FIX colours and the pixel scale, which become `ge.frag`'s
specialisation constants: the shader blends with the GE's raw factors and equation on `subpassLoad` (FIX exact, the
doubled factors and ABSDIFF as `ge.metal`'s `ge_factor`/`ge_blend`), adds the matrix's offset for the PSP pixel
(DITHn the row for y & 3) when DITHERENABLE is on and the draw is not a clear, clamps once, keeps the top 5/6/5,
5/5/5 or 4/4/4 bits and writes what they expand to; the pipeline does not blend, and the shader's alpha is the
stencil value the target stores. Before each such draw the open merge group is drawn and a by-region barrier
recorded, so a draw reads what the ones before it wrote; fragments of one draw that overlap are not ordered (no
`VK_EXT_rasterization_order_attachment_access` on the measured driver). The pipeline key list goes from version 4 to 5
(25 words). `<prefix>_NO_DITHER` (the Metal backend's name) restores the old drawing; `<prefix>_SHOW_TARGET=ADDR`
presents that render target in place of the display (the Metal backend's `<prefix>_METAL_SHOW_TARGET`).

### 0015-vulkan-fb-texture-wrap
Task 063. A draw that samples a render target (the billboards' 128x128 565 target, the bloom chain) had its
coordinates folded into the target's 480x272 copy (`uv_transform`) and its wrap flags dropped, so the copy's sampler
clamped them at the target's edge: the billboards, drawn with v scale -1 and REPEAT, clamped -v to 0 and showed the
advert's first row as vertical bars. Now `uv_transform` stays the texture's own scale and offset, the wrap flags stay,
and `texture_params.x` gains `kPushPlaced` (2^20; a target has no mip levels, so the mip bits stay clear). Such a draw
writes an object block whose `uv_remap` is the texture's place in the copy (mapped or not); `ge.vert` hands it on in
`frag_uv_rect` in place of the through-mode tile clamp, and no longer applies it to modes 1 and 2 itself; `ge.frag`
takes the coordinate (divided by q in mode 1) modulo 1 on a repeating axis or clamps it between the centres of the
texture's edge texels (half a texel of the texture's own size, its share of the target's PSP pixels) on a clamping
one, then places it. Ordinary textures are drawn as before. At an internal scale above 1 a through-mode draw that
samples a target (the bloom's tiles) loses the tile clamp of `clamp_through_quad`, which only acts there.

### 0016-menu-rows-by-capability
Task 064 (D-014). The Esc menu (`host/ui/menu.cpp`) drew the framework's first game's rows for every game and every
shell. Two sets of gates now decide which rows are drawn; a hidden row keeps its settings key and value.
- The game's: `GameProfile::features` (`MenuFeatures` in `host/profile.hpp`): `adhoc` (the Network tab and the System
  tab's "Pause during multiplayer"; without it the menu turns `network.adhoc` off when it opens, so the game sees the
  wireless switch off), `right_stick_camera` (the Right stick row's Camera choice and the two camera inversion rows;
  a Camera setting is shown as Off, which it is for a game that never reads the second stick's bytes) and
  `mouse_camera` (Mouse, Mouse sensitivity and the two mouse inversion rows; the bindings stay).
- The shell's: `Shell::supports_frame_interpolation()` (Frame rate, Lower when behind), `supports_perf_overlay()`
  (Performance, the F3 row), `supports_aspect(Aspect)` (the Aspect ratio row's choices; an aspect not offered shows as
  Original), `supports_touch()` (the Touch screen section) and `api_name()` (the System tab's "<api> on <device>").
Every default is today's behaviour (all true; `api_name()` is the shell's registered name with a capital, "Vulkan"),
so a game that sets nothing and the Vulkan shell draw every row they drew before. Restore video defaults restores the
rows shown only. `<prefix>_MENU_DUMP` (tests): when the menu opens, its first frames draw each tab once and print
`[menu] tabs: ...` and one `[menu] <Tab>: <rows>` line a tab, the labels in draw order, the offered choices of Aspect
ratio and Right stick and the Graphics line in parentheses, and the rows another screen's code draws as one entry
(`[font rows]`, `[texture pack rows]`, `[save rows]`).

### 0017-internal-scale-by-backend
Task 067 (D-015, E3 step 3). The Video tab's Resolution row, its value text and "Restore video defaults"'s line for it
were the Vulkan renderer's (`active_renderer()`), so a GE backend that draws at an internal scale of its own (our
Metal backend, task 066) had no row. Now they ask the backend the HLE draws with, `gpu::running_backend()` (declared
in `host/gpu/ge_backend.hpp`, defined in `hle_media.cpp` over its `active_backend()`): the row is drawn when
`GeBackend::supports_internal_scale()` answers true, its value is `target_size()`, and a change calls
`set_internal_scale(setting)`, the setting as `BackendConfig::internal_scale` takes it (0 Auto). The defaults are no,
nothing and 480x272, so the null backend has no row (our record backend in `src/tools/` answers as the backend it
wraps, since task 095); the Vulkan backend (`vulkan_ge_backend.cpp`) answers
true and forwards both to its renderer, which is what the menu called before, so the Vulkan shell's menu is unchanged
(the texture filter and texture pack rows keep their renderer gate). `GameProfile::default_internal_scale`
(`std::optional`, unset by default) is the scale a new player starts with: `settings::defaults_for` applies it, so it
is also what "Restore video defaults" restores; a value in settings.ini or `<prefix>_INTERNAL_SCALE` still decides.
Our profile sets 0 (Auto).

### 0018-vulkan-effects-at-1x
Task 068 (D-015, E3 step 4, for the Windows build). Every target was `target_extent`, the internal resolution, so above
1x the bloom's buffers (8888, stride 256) and the billboards' target (565, stride 128) were drawn at the scale too,
where the Metal backend draws them at 1x since task 066 (PPSSPP's "lower resolution for effects" for this game). The
blur's taps are through-mode positions, which scale with the target, so its radius was the PSP's already; what moved
was the detail the downsample kept and every pixel of the glow by a level or two (race_1x.gerec frame 6016 at 2x: the
glow region's mean luminance +0.54% from 1x before, +0.41% after, as Metal's at 2x; Vulkan against Metal at 2x, 33
pixels over tol 24 before, 14 after). Now each `Target` has an `extent`, set when it is made
from the stride of the draw that makes it (`extent_for`: `target_extent` at 480 or more, 480x272 below; a target made
without a draw, `upload_frame`'s, is a screen). The pass's render area, the viewport, the scissor's scale, a 16-bit
target's pixel scale for the dither, the auto mip rule's 16 x log2 of the scale (`drawn_extent`), the stencil copy's
quad, the copy a draw samples of a target (`framebuffer_descriptor`: the copy has the target's size, and the placement
is relative to it, so a 1x buffer sampled into a scaled screen, the composite, and the reverse, the downsample, go
through the same `uv_remap`), `hold_frame`, `upload_frame`'s blit, the display blit (`record_game_blit` and
`submit_and_present` take the source's size), `capture_frame`, `display_image`, the frame interpolation's picture copy
and replay, and the depth write-back take the target's own size; `resize_targets` makes each target again at the size
its stride gives at the new resolution. The frame write-back and `read_back_framebuffer` give the guest the centre
pixel of each S x S block, (x S + S/2, y S + S/2), as the depth write-back already did and the Metal backend does
(`centre_texel`, shared with the depth): the target's row at the centre of each PSP row is copied whole into the
slot's buffer (272 copy regions, one at 1x) and `take_writeback` picks the column at the centre of each PSP pixel.
Before, a linear blit scaled the target into a 480x272 image, which at an even scale averages each block's four middle
pixels; that image is gone, and each slot's buffer is made when the slot first writes a frame back and again when a
wider target needs more (272 rows of the target's width: 2.1 MB at 4x, where the depth write-back copies 8.4 MB).
At internal scale 1 every target is 480x272 as before and the pictures are the same (race_1x.gerec frame 6016: 0
pixels differ). A target keeps the size it was made at when a later draw gives its address a stride on the other side
of 480 (no recording has one: each address keeps one stride) until the next change of scale makes it again. The tile
clamp that 0015 notes as lost above 1x is left as it is.

### 0019-game-option-rows
Task 070 (D-016, the enhancement E6, and E4 and E5 after it). A port could add HLE hooks but had no player setting of
its own: the menu's rows and settings.ini's keys are the framework's table. Now a game lists its options in
`GameProfile::options` (`host/profile.hpp`): a `GameOption` has a `key` (settings.ini's name without `game.`, lower
snake case), a `label` (the row's text), `choices` (the texts the row cycles through), a `description` (the help
text), a `default_choice` (an index into the choices) and a `tab` (`MenuTab`: Video, Audio, Controls, Network,
System). `host/settings/`: `Settings::game_options` keeps each value as an index, in the options' order; `all_fields()`
adds a field per option after the bindings', `game.<key>=<index>`, so loading, saving and the environment work as for
the framework's own keys: an index out of range is ignored (`[settings] ignoring ...`, the default stays), the
variable `<prefix>_<KEY>` (the key upper-cased) decides the value for the run and `overridden_by("game.<key>")` names
it, and `save()` drops a `game.` key that no option has. `defaults_for()` gives each option its default, and
`settings::game_option(key)` returns the current index (a lookup by key in the profile's small table, cheap enough
for every frame; 0 for a key no option has). `host/ui/menu.cpp`: `game_rows(tab)` draws a `section("Game")` and a
`choice_row` per option at the end of each tab that has options (`options_for("game.<key>", description)`, so the
row is locked with "Set by <variable>" when the environment decides it), saving on change; the `<prefix>_MENU_DUMP`
lines list the rows as the others; each tab's Restore button puts that tab's options back to their defaults (not one
the environment decides). A game that lists no option gets no section and no key: every tab and settings.ini are as
before. Our profile lists one, Flashes (`game.smooth_flashes`, `src/profile/enhancements.cpp`). The menu's own tab
type (0016's `Menu::Tab`) is `MenuTab` itself, an alias since task 095.

### 0020-vulkan-texture-detail
Task 076 (D-019, E5; the Metal backend's half was task 075). The renderer picked a mipmapped draw's level as the GE does
for the PSP's 480x272 pixels (patch 0012-vulkan-mipmaps: the auto rule's gradient per PSP pixel, the slope rule by depth
alone), so at internal scale S a surface was drawn from a level log2(S) coarser than the pixels could show, and
isotropically. `GameProfile::texture_detail_option` (`host/profile.hpp`, null by default) names the game option (one of
`options`, patch 0019-game-option-rows) whose choice 1 asks for texture detail; the renderer reads
`settings::game_option(key) == 1u` at start (`[render] texture detail: off` when it is 0) and once a frame in
`begin_frame`, never per draw. A draw is enhanced when the option is on, its texture has levels (from guest memory: not
a target's, not a texture pack's replacement) and it is not a 2D draw (through mode, or unlit under an orthographic
projection: `projection[3]`, `[7]` and `[11]` all 0, the Metal backend's rule). Then the level rule block's constant
loses 16 x log2 of the drawn target's width over 480 (`shift`, the term the auto rule adds, so the auto rule's addition
cancels and its gradient is per drawn pixel; the slope and constant rules lose it too; the clamp to -2048..2047 and the
packing are as before), and `texture_params.x` gains `kPushDetail`, 2^21, above `kPushPlaced` (both exact in a float;
`mip_lod` now masks the constant's twelve bits). In `ge.frag` such a draw takes `dFdx`/`dFdy` of the normalised
coordinates after the divide by q and before the wraps, scales them by k = 2^(lod - log2 rho) (rho the longer in texels
of level 0) and samples with `textureGrad`, so the GPU's isotropic level is the GE's shifted one and the anisotropic
sampler takes its taps along the footprint's long axis; the clamp wrap's `half_texel` keeps using that level. The
sampler: `samplerAnisotropy` is enabled where the device has it (a line when it does not and the game names the option),
and `mip_detail_sampler` (`mip_sampler` with `maxAnisotropy` min(16, the device's limit); 16 under MoltenVK on the M4
Pro) is what `texture_sampler(levels, true)` returns, except with the Sharp texture filter, which keeps the nearest mip
sampler. The sampler is part of each texture's descriptor set, and one texture can be drawn in a frame both by an
enhanced draw and by a 2D one, so `Texture` gains `detail_descriptor`, made at the texture's first enhanced draw,
rewritten with the other on a Texture filter change and freed with it; the descriptor pool is sized for twice as many
texture sets when the game names the option. `[render] texture detail: on` at the first enhanced draw. Without the
option, or with it at 0, the draws, the samplers and the pictures are as before (the Vulkan window suite's seven scenes
to the pixel). Our profile names `texture_detail` (the Texture detail row, `src/profile/enhancements.cpp`). The
bits of `texture_params.x` are described once, above `PushConstants` in `vulkan_renderer.cpp`; `ge.vert` and `ge.frag`
point there (task 095: the three descriptions disagreed).

### 0021-content-packs
Task 078 (078-download-packs-menu, the Mac line's 078; D-005; docs/dlc.md, "In the menu (task 078)"). A game's download packs are save folders the game loads as
content, and the framework had them only as save folders: listed among the saves, copied by Back up saves, and checked
on Import as saves, where seven of Wipeout Pure's twelve US packs were refused ("NAME is missing.": the first entry of
their PARAM.SFO's SAVEDATA_FILE_LIST is four bytes of a PSP address, 0x08xxxxxx, then zeros, and TEST.BIN, the file
they hold, is the second). `host/profile.hpp`: `SaveFolder::content_pack` (false by default) marks such a folder, and
`GameProfile::content_packs_label` (null by default) names the section that shows them. `host/save_data/`:
`names_of_save_folders`, which the export's names and `saves_to_back_up` (the backup, its conflicts and the backup
screen's text) read, skips content packs, so Export and Back up saves leave them out whatever `exported` says;
`is_game_save_name` and `save_label` still take them, so Import does; `check_save_folder` skips, for a content pack
only, a file list entry whose name up to its first NUL holds a byte outside printable ASCII (an empty name was already
skipped for every folder), and checks the rest as before; `content_packs(memory_stick)` lists the profile's content
packs in its order, each installed when its folder holds a PARAM.SFO (as `saves_to_back_up` counts a save; none while
the memory stick is unknown). `host/ui/menu.cpp`: when the label is set, `Menu::system` draws after the Saves section
`section(label)`, an `info_row(label, "N of M installed")` (the dump adds the count in parentheses), a
`[content pack rows]` dump entry and one widgets `info_row` a pack (its description, "Installed" or "Not installed"),
and a `button_row("Install " + the label in lower case + "…")` whose help says what to pick and which calls
`ui::open_import()` (`host/ui/save_screen.{hpp,cpp}`: Import save…'s `open_browser(Stage::ChooseImport)`, on Android its
picker), disabled while the memory stick is unknown. A game that marks nothing and names no label gets no section, the
same exports, backups and import checks. Our profile marks the twelve US packs and names "Download packs".

### 0022-vulkan-async-readback
Task 077 (077-vulkan-readback-stutter). On a discrete GPU (the rig's RTX 3080) a race lost 9 to 16 ms a frame to `perf::Stall::Readback`: not the
block-transfer readback the stall's name suggests (`read_back_framebuffer` never runs in Wipeout Pure's race; its block
transfers are all main RAM to VRAM), but `write_back_depth`, which at every GE SIGNAL with a screen-wide depth buffer
(once per race frame: the lens flare's CPU depth test, patch 0003-vulkan-renderer-fixes) submitted the half-recorded frame and waited for its
fence. Now each `FrameSlot` has its own depth buffer (`depth`, `depth_in_flight`, `depth_frame`, `depth_recorded`): the
SIGNAL records the copy into the frame without submitting, and stores in guest memory the newest copy an earlier frame
recorded (`begun_frames` tells this frame's from those), waiting for that frame's fence (`Stall::Fence`, long signalled
in practice); older ones are dropped. The first SIGNAL stores nothing (guest memory keeps its bytes). A second SIGNAL in
one frame that needs a bigger buffer than the first's drains as before. The conversion to the GE's 16 bits is
`store_depth`, the copy `record_depth_copy`, both shared with the synchronous path, which `<prefix>_SYNC_READBACK=1`
restores exactly (its drain and both invalidates are 0003's `drain_recording` and `invalidate_writeback`). The start-up line says which (`a frame late` or `synchronous`). Upstream: a candidate; the one-frame
lag is what a game's CPU depth test sees, so a framework would want it per game or documented.

### 0023-vulkan-cached-window-capture
Task 078 (078-vulkan-effect-slowdowns). The input script's `shot` (a window capture, `write_capture`) copied the swapchain image into a buffer from
`find_memory_type(HOST_VISIBLE | HOST_COHERENT)`, the first such type, which on NVIDIA is uncached, and `write_bmp`
then read it a byte at a time: 110 to 160 ms a capture on the rig, a long frame at every scripted shot (the "first-use
present hitches" task 078 was opened for). The buffer now comes from a HOST_VISIBLE | HOST_COHERENT | HOST_CACHED type
when the device has one (type 4 on the RTX 3080), else as before; no invalidate is needed since the type is coherent
(0003's `host_read_memory` with `invalidates` false picks it).
Measured: fence wait 1.5 to 3.3 ms, read, convert and write 1.6 to 2.5 ms. The BMP is the same bytes. Upstream: a
candidate; any discrete GPU's captures.

### 0024-audio-resync-counter
Task 079, the characterization stage alone. `AudioSink::mix` snaps a producer's cursor that has fallen within 512
frames of the device's read position (`kPrebufferFrames / 4`) forward to read position plus 2048. Each jump skips
frames that the channel never wrote, so you hear a click, but the ring never runs dry, so `silent=` stays 0 and no
counter recorded the jump. The patch counts it: `resyncs=` (events) and `resynced=` (frames skipped) on the
per-second `[audio]` line under `<prefix>_TRACE_AUDIO` and in its shutdown total. `lead=` is `write_end -
read_position` at the line. No behaviour changes. The swept race on the rig showed 5.2 resyncs a second, about 1960
frames each, while emulation ran at 88% of real time. The menus, at 100% real time, showed none from drift. The
skips track the producer's lost time, not a fast device clock, so the slug's rate-matching was not built (task 079's
Result). Upstream: a candidate, since any port with a slow or bursty producer skips here without knowing it.

### 0025-guest-time-split
Removed by task 095 (the audit of 2026-10-19). Task 082 added `<prefix>_TRACE_GUEST=1`, a `[guest-split]` line a
second that split the [perf] line's guest time by module family with a timer around each import in
`HleRegistrar::bind`, to measure where the rig's guest milliseconds went (docs/tasks/082-guest-frame-profile.md keeps
the figures). Nothing in `tools/` or `src/` set the switch after that measurement, so the patch and its timer went;
the number is left unused rather than renumbering the patches after it.

### 0026-corpus-inlining
Task 083. `cmake/PortableKit.cmake` passed `/Ob0` (no inlining) beside `/O${PSPRECOMP_GENERATED_OPT_LEVEL}` in its
MSVC branch twice: the generated units' source property `COMPILE_OPTIONS` and the overlay target's compile options.
Both are `/Ob2` now. A target-level `/Ob2` appended from a port's own CMakeLists is a no-op, since the source
property serializes after it on the command line (compile_commands.json shows `/O2 /Ob1 ... /O2 /Ob0 /bigobj`), so
the fix belongs in the framework. Recompiled code is almost nothing but small functions (the guest memory accessors
above all); without inlining every one stays a call, and on the rig (i5-8600K, clang-cl 23) the recompiled code ran
2.7x slow: the `game` bucket of `PURE_TRACE_GUEST` was 10.08 ms a game frame on a fresh boot and the race's
stutter_check failed in two of three seconds. The figures after: docs/tasks/083-corpus-inlining.md. The FP contract
is left as it was: the clang path passes `-ffp-contract=off`, this branch does not; contraction is decided per
source expression, so inlining fuses nothing new, and without `/arch:AVX2` an x64 target has no FMA instruction. A
flag that enables FMA here must bring `-ffp-contract=off` (clang-cl) with it. The corpus rebuild with the flag is
the only cost (~16 minutes on the rig). Upstream: a candidate of the first order; every Windows port of the framework
pays this today.

### 0027-window-size-switch
Task 084. The Vulkan renderer opens its window at 480x272 times `video.window_scale` (1 to the framework's maximum),
so every window it opens has the PSP's shape until the player resizes it. A check of the Fill aspect (D-020: the game
draws its 3D view at the window's shape) needs a window of another shape from the first frame, the same in every run.
`<prefix>_WINDOW_SIZE=WxH`, read once beside `SDL_CreateWindow`, opens the window at W x H (1 to 16384 each) and
prints `[render] window WxH (WINDOW_SIZE)`; unset, or anything but two positive numbers joined by an `x`, and the
window is as before. Nothing else reads it: the menu's Window size row and a later resize work as they did. The parse
is `host::window_size_switch()` (`shell/shell.hpp`, task 095), which our Metal shell calls too. Applies to the pin
alone. Upstream: a candidate, tooling any port's window checks can use.

### 0028-vulkan-orthographic-fit
Task 085 (D-020, point 3). Under Fill the target has the window's shape, so each of the game's 480x272 pixels is wider
than square, and the renderer pulls the 2D interface in about the screen's centre to square pixels again
(`interface_fit`). It did so for through-mode draws only, by moving their vertices. Wipeout Pure draws its menus and
HUD as transformed draws under an orthographic projection (the w row, `projection[3]`, `[7]` and `[11]`, all 0) with
lighting off (task 073's finding; the rule E7 and E5 use), so they stretched: at 21:9 the HUD was a third wider than it
should be. Such a draw into the shown framebuffer, not in clear mode and not sampling a rendered picture, now has its
clip x and y scaled by `fit_x` and `fit_y` after `viewport_into_clip`: clip (0, 0) is the screen's centre, so the
scale is the same fit about the centre. The fit goes into `push.transform` and, through the `viewport_into_clip`
overload and `summarize(call, fit_x, fit_y)`, into the draw's interpolation summary, from which the replay rebuilds a
blended draw's transform, so the two paths agree; at a fit of 1 both are bit for bit as before. A draw whose vertices
span less than 470 of the 480 PSP pixels through its transform is fitted. A wider one is fitted only when it is
textured and lies within the screen, 2 PSP pixels of margin each side (`kScreenEdgeMargin`, so a quad from exactly 0
to 480 counts): a layer of interface art drawn as one quad, such as Wipeout Pure's profile screens' panel (a 512x512
CLUT8 texture in VRAM) and its title's logo layer (512x128), which must line up with the fitted text over them. An
untextured screen-wide draw (a backdrop, a fade) and any screen-wide draw that reaches past the screen's edges (the
race's fly-in glow, x -142 to 1571) stay spread with the 3D view. A raw draw (`<prefix>_GPU_DECODE`) has no vertices
on the CPU to measure and stays spread. Through-mode draws keep the vertex fit and its width rule unchanged. The
fitted draw's scissor is fitted with it, as a through-mode draw's is. `<prefix>_NO_ORTHOGRAPHIC_FIT` fits
through-mode draws alone, as before. Nothing changes at Original or Stretch (no fit) or for a game without
`view_aspect_frame` (no Fill). The texture detail test of 0020 now reads the same `orthographic` flag. Needs 0010
(`viewport_into_clip`) and 0020 (the flag it moves).

### 0029-windows-file-url
The planning session (2026-10-13), after Erik found the Esc menu's "Open the data folder" and its siblings doing
nothing on Windows. `SDL_OpenURL` takes a URL, and the menus make one from a path by percent-encoding every byte
that is not a letter, digit, slash, dash, underscore, dot or tilde: fine for `/Users/...` (one leading slash from
the path, `file://` giving the other two), wrong for `C:\Users\...`, whose colon and backslashes came out `%3A` and
`%5C` with only two slashes before them. The fix adds the third slash when the path does not start with one, keeps
`:` and maps `\` to `/`, in the three identical helpers (a shared one would be the upstream shape). Tested by a
compile of the helper on three paths (macOS unchanged, two Windows drives) and by the rig by hand. Upstream: a
candidate of the first order, every Windows port of the framework has dead folder buttons today.

### 0030-vblank-period
Task 089 (D-022, the enhancement E8): the game's vblank at a display's refresh. The kernel ticked the vblank at the
PSP's 59.94 Hz, one constant, `kVBlankPeriodUs`, read by the tick, `last_vblank_us()` (the next vblank less the
constant), the media HLE (the frame grid's step in `frame_start_us`, the vertical blank's 14 of 286 lines, the
hcount and the vblank flag, whose two `16683` literals were the same constant) and, as `kGameFrameUs`, frame
interpolation's game frame. The period is now the kernel's `vblank_period_us()`, set by `set_vblank_period_us()`
(0 restores the PSP's); `last_vblank_us()` is kept at the tick, so a change of period leaves it the vblank's own
time; a change applies from the next vblank, which stays where it was due (never moved into the past), and the count
of vblanks so far stands. The period is kept by the kernel alone: frame_pacing.cpp, which is built without the
kernel (the renderer's sources, the framework's interpolation tests), reads it through the function the media HLE
hands `gpu::pacing::set_vblank_period_source()` when it makes the shell (task 095; until then a copy passed on at
each flip, and an uncalled `pacing::vblank_period_us()`): `game_frame_us()` is the period
times the game's frame in vblanks and `game_rate()` 60 x 16683 / period / that count, exactly 30 or 60 at the PSP's
period as before, so the menu's Frame rate row, which offers only rates above `game_rate()`, offers the game's own
rate and Match display when a game at 60 runs its vblank at 120 Hz. A present clock whose frame no longer matches
`game_frame_us()` takes the new frame and starts its grid over at the next flip. The kernel's scheduler, waits,
starvation quantum and hold to real time are untouched (the hold compares emulated with real time, not vblanks);
`kIdleVBlankLimit` still counts vblanks, so the deadlock report comes after 2.5 minutes of a 120 Hz vblank with no
thread to run instead of 5, and `sceDisplayGetFramePerSec` still answers 59.94. Our profile sets the period from the
Esc menu's Display rate row (`src/profile/enhancements.cpp`). At the default period nothing moves: the headless
suite 18/18, the Vulkan window suite 7/7, framerate_check, flash_check and menu_check on both shells as before.
Upstream: a candidate; any port that wants a game's frame rate at a display's refresh (or VR's 72 or 90 Hz) needs it.

### 0031-audio-sink-late-writes
Task 098 (2026-10-19; D-023, task 081's fork b+). Patch 0024-audio-resync-counter counted the sink's stalled-producer jump and task 081
showed what it was: not a stalled producer but a continuous channel whose lead a dip had eaten, its cursor at the
device's read position (0 to 15 frames ahead), snapped 2048 frames forward, 46 ms of silence in that channel each
time, the click in Erik's ear after every dip; and that dropping the played frames without rebuilding a lead turns
the click into a near-mute when the producer runs below real time for long (the harness's 85% race). The rule is
now in two parts. A cursor more than `kLateLimit` (2048 frames) behind the device is a stall or a restart and takes
the old snap, counted as before. A cursor less behind drops only the frames the device has already played
(`read_position - cursor`, counted as `late=` frames) and writes the rest at its own slots; and any write under the
`kPrebufferFrames` lead the sink is designed to hold (`lates=` events; task 501 widened this from 512 frames after
task 500 saw the rig's race load land a cursor 777 to 2595 frames ahead and the lead then drain to zero before
anything armed, whereupon a producer at real time, which cannot close a deficit by itself, played it as silence on
every write for 2 s) arms a recovery, with a device present only (the no-device ring drains itself to exactly that
lead): the stream's frequency ratio is set to
`kRecoveryRatio` 0.99 until the device has read `kRecoveryFrames` more (2048 / 0.01 = 204800, about 4.6 s; each
late write extends it), so a channel that keeps real time regains 2048 frames of lead with no gap and a pitch
17 cents low for those seconds. The ratio is decided under the sink's lock and applied after it is released, because
`feed_device` runs with the stream locked and then takes the sink's lock. The trace line gains `lates=`, `late=`
and `ratio=` after `lead=` (its readers match `resyncs=` by name), the shutdown total `lates=` and `late=`.
`<PREFIX>_AUDIO_SNAP=1` keeps the old rule for an A/B run. Headless (no device) and in a paced boot with the device
both rules give the same figures (the menus never run late); the race under dips, where they differ, is the window
probe `PURE_TRACE_AUDIO=1 tools/display_rate_check.sh --audio` (task 097, row 7) and the rig's 100 Hz run.
Upstream: a candidate with 0024, which it completes; any port whose producer dips below real time clicks the same way.
