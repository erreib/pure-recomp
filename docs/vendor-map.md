# Vendor map: the framework seams this port uses

PortableKit (TeamGDB, MIT) is vendored at `vendor/PIN` (8b0c3fe) with `patches/` applied in order
(`tools/vendor_setup.sh`; `tools/patches.sh check`). Each patch in full: patches/README.md; upstream: docs/upstream.md.
The spike report behind D-001 (the API at 8b0c3fe, Yakumo):
[docs/history/vendor-map-2026-10-05.md](history/vendor-map-2026-10-05.md).

## Used as it is
The codegen (`psp_analyze`, `psp_recomp`), the runtime and `include/psprecomp/` (never edited: the corpus would
recompile), the interpreter, the kernel, the HLE, the GE parser and texture decoder, ATRAC and the movies (FFmpeg
7.1.5, built at configure), the saves, settings, input bindings, installer and the macOS packer.

## Patched
- 0001-cmake-embed-nids-verbatim: `config/nids.csv` survives the shell
- 0002-ge-state-commands: stencil, masks, texture maps, mips, colour test, dither, CLIPENABLE parsed
- 0003-vulkan-renderer-fixes: framebuffer textures, stencil as alpha, alpha test, shadow volumes, depth write-back
- 0004-ge-backend-and-shell-seams: `gpu::GeBackend`, `host::Shell` (D-003, D-007), one `Registry<T>` (`host/registry.hpp`), `gpu::write_bmp`;
  the null backend (the record backend is ours: `src/tools/record_backend.cpp`)
- 0005-kernel-host-waits-and-pacing: the shell sets the pace (`Kernel::set_paced`); frame pacing reads the vblank period
  through `pacing::set_vblank_period_source()`
- 0006-mpeg-ring-not-empty-while-aus-pending: movies end
- 0007-savedata-list-and-no-key-mode: the save list; saves in mode 1
- 0008-sas-reverb: the SPU reverberator
- 0009-vfpu-rounding: the PSP's VFPU rounding (D-013), `-ffp-contract=off`
- 0010-vulkan-viewport-into-clip-space to 0015-vulkan-fb-texture-wrap: the Vulkan renderer draws what Metal does;
  0012's `texture_decode.hpp` exports `bits_per_texel`, `indexed`, `texture_bytes`, `texture_level`,
  `sampled_level_count`, `mip_level_problem` and `ge_log16`, which the Metal backend uses too
- 0016-menu-rows-by-capability: `GameProfile::features` (D-014)
- 0017-internal-scale-by-backend: the Resolution row asks the backend
- 0018-vulkan-effects-at-1x: the effect buffers at 1x (D-015)
- 0019-game-option-rows: `GameProfile::options`, `game.<key>`, `PURE_<KEY>`
- 0020-vulkan-texture-detail: `GameProfile::texture_detail_option`
- 0021-content-packs: `SaveFolder::content_pack`, the Download packs section
- 0022-vulkan-async-readback: the depth write-back a frame late
- 0023-vulkan-cached-window-capture: captures from host-cached memory
- 0024-audio-resync-counter: `resyncs=` on the `[audio]` line
- 0025: removed by task 095 (the guest-time split; its number stays unused)
- 0026-corpus-inlining: MSVC's `/Ob2`
- 0027-window-size-switch: `PURE_WINDOW_SIZE` (`host::window_size_switch()`, parsed once for the Vulkan renderer and
  the Metal shell)
- 0028-vulkan-orthographic-fit: the 2D fit under Fill
- 0029-windows-file-url: the folder buttons on Windows
- 0030-vblank-period: `Kernel::set_vblank_period_us` (E8)
- 0031-audio-sink-late-writes: the sink keeps a late producer's content, `kRecoveryRatio` (D-023)
- 0033-zim-textures: texture packs of ZIM images (`decode_zim` in host/gpu/texture_pack.cpp, D-024); zstd's decoder
  is ours, `cmake/Zstd.cmake` (`pure_zstd_decoder`, linked into PureNative after `portablekit_add_game`)
- 0034-texture-pack-host: `gpu::TexturePackHost` (host/gpu/texture_pack_host.hpp, the six calls of the menu's Texture
  pack row and the import screen), `VulkanRenderer` implements it; `active_texture_pack_host()` and
  `set_active_texture_pack_host()` (hle_common.hpp, defined in texture_pack_screen.cpp); our Metal shell registers the
  Metal backend (task 100)

## Replaced
- The GE backend: `src/gpu/` registers `metal` (`BackendRegistration`), the macOS default (D-008;
  docs/metal-backend.md).
- The shell: `src/host/metal_shell.mm` registers `metal` (`ShellRegistration`): the window, pad, ImGui on Metal.
- `main()`: `src/host/pure_main.cpp` (`--replay` runs ge_replay, else the framework's main as `portablekit_main`).

## The profile hooks
`portablekit_add_game(PureNative ...)` in `CMakeLists.txt` builds the game; `src/profile/pure_profile.cpp` defines
`portablekit::game()`: identity and hashes, `load_base`, 32 MiB, `env_prefix` "PURE", the save folders and packs,
`register_extra_hle` (five HLE calls, the flip counter, `src/profile/enhancements.cpp`'s wrap, the test hooks, the
audio capture), `view_aspect_frame` (`src/profile/aspect.cpp`), `default_internal_scale` (Auto), `frame_vblanks`,
`features`, `options` and `texture_detail_option`. Native overrides use `Runtime::register_function`.
