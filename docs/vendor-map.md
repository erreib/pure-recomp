# Vendor map: PortableKit 8b0c3fe

Spike S3 report (2026-10-05), produced by an Opus agent from the clones under `~/dev/scratch`. Decision D-001 in `docs/decisions.md`. Paths are relative to the vendor repo; verify line numbers against `vendor/portablekit` before relying on them.


Date: 2026-10-05. Clones under `~/dev/scratch` (shallow):

| Repo | HEAD | Commit date |
|---|---|---|
| TeamGDB/PortableKit | 8b0c3fe "Merge pull request #39 from TeamGDB/extension-keys-lookup" (Vladimir Ivanov) | 2026-09-27 14:48:36 +0300 |
| TeamGDB/Yakumo | 962d38b "Merge pull request #278 from TeamGDB/docs/github-pages-site" | 2026-10-05 03:30:06 +0600 |
| PSPRecomp | f6e7d41 | 2026-08-13 21:51:51 -0300 |

All paths below are relative to the repo named in the row or heading. "Inferred" marks anything not read
directly from code or measured.

## 1. What PortableKit is

**Yes: it is the framework plus the reusable host layer, built as a CMake subproject with a profile hook.**
It is not a prebuilt library: a port adds it with `add_subdirectory()` and calls `portablekit_add_game()`,
which compiles the host layer into the port's own executable.

- Self-description: README.md:3 ("a static recompiler for the game's code, and a full reimplementation of
  the system it ran on"). The framework "moved out of Yakumo with their history" (README.md:49). Yakumo "still
  carries its own copy and has not been switched over yet (#2)" (README.md:30).
- Framework, the same split as Yakumo's root:
  - `src/`: decoder, deflate, elf32, extra_instructions, guest_memory, interpreter, nid_registry, program_analysis,
    runtime, sha256.
  - `include/psprecomp/`: 14 headers, including two Yakumo lacks: `corpus_abi.hpp` and `extra_instructions.hpp`.
  - `tools/`: analyzer_main.cpp, codegen_main.cpp, dump_function.cpp, add_overlay.py, wrap_overlay.py,
    extract_iso.py, embed_nids.cmake, embed_shaders.py.
- Reusable host layer under `host/`, in namespace `portablekit` (not `mhp3rd`):
  - kernel: `kernel/` (kernel, fixed_pool, message_pipe, rtc_time, iso_image, fast_loading).
  - HLE: `hle/` (threadman, sysmem, io, system, media, atrac, mpeg, psmf, psmfplayer, net_offline, adhoc,
    utility, savedata, font, extensions).
  - GPU: `gpu/ge_state.*`, `gpu/texture_decode.*`, `gpu/vulkan_renderer.*`, frame_interpolation, frame_pacing.
  - Everything else: `audio/` (atrac_decoder, audio_sink, sas_core), `movie/` (avc_decoder, psmf_demuxer,
    psmf_header), `save_data/`, `adhoc/`, `install/`, `settings/`, `ui/`, `input/`, `fonts/`, `crypto/`.
- How it is packaged:
  - `psprecomp_core`: an OBJECT library (CMakeLists.txt:152-164).
  - Host sources: the list `PORTABLEKIT_HOST_SOURCES` (cmake/PortableKit.cmake:25-91).
  - Renderer and UI sources: `PORTABLEKIT_RENDERER_SOURCES` (cmake/PortableKit.cmake:93-115).
  - `portablekit_add_game(<target> PROFILE_DIR <dir> SOURCES <files>)` builds the game executable
    (cmake/PortableKit.cmake:249-258). It globs `<PROFILE_DIR>/generated/*.cpp` (:266) and links a stub when
    that directory is empty (:282-284). SDL3, Vulkan and glslang are optional (:294-334).
- The profile hook is `const portablekit::GameProfile &portablekit::game()`. The struct is at
  host/profile.hpp:120 and the declaration at :266.
  - The profile is mostly constants: identity, hashes, decryption tag and key, `load_base`, `guest_ram_bytes`,
    overlay slots, save folders.
  - Hooks: `register_extra_hle(HleRegistrar&)` (:211), `patch_loaded_image(Runtime&, const Elf32Image&)` (:214),
    `camera` (:221), `view_aspect_frame` (:226), `fast_loading_allowed` (:248).
  - Environment variables take the profile's `env_prefix` (:126). With `"PURE"` you get `PURE_NO_RENDER`,
    `PURE_TRACE_GE` and so on.
- HLE extension modules are a second seam that needs no vendor patch:
  - Set them with `PORTABLEKIT_HLE_EXTENSION_DIRS` (CMakeLists.txt:134-147).
  - Each module calls `portablekit_add_hle_extension()` (cmake/PortableKit.cmake:167) and declares its own licence
    (docs/HLE_EXTENSIONS.md).
  - A module can fill in or override any HLE function.
- The profile lives outside the framework tree by design: "It lives in the game's own repository, not here"
  (docs/PROFILE_GUIDE.md:3-18).
- macOS CI: yes. .github/workflows/ci.yml:31-33 runs macos-14 with Apple Clang and Ninja. CI builds the framework
  and the tests only (:50-60): no port, no renderer, no FFmpeg. Yakumo also has macOS CI
  (.github/workflows/tests.yml:27), and it builds with `-DPSPRECOMP_PROFILE=mhp3rd` (:47).
- Building docs:
  - docs/BUILDING.md (77 lines). It has no macOS section.
  - The macOS prerequisites are in README.md:70 (`brew install cmake ninja python`) and README.md:73
    (`brew install sdl3 molten-vk vulkan-loader vulkan-headers glslang`).
  - Related pages: docs/BUILD_SYSTEM.md, docs/PROFILE_GUIDE.md, docs/BRINGING_UP_A_GAME.md,
    docs/HLE_EXTENSIONS.md, docs/INSTRUCTION_COVERAGE.md.
- Builds on this machine: **yes** (M4 Pro, 12 cores, 24 GB, Apple clang 17.0.0, cmake 4.4.4, ninja 1.13.2,
  `-DCMAKE_OSX_ARCHITECTURES=arm64`, ccache off).
  - Framework only (`~/dev/scratch/PortableKit/build-tools`):

    | Step | Result |
    |---|---|
    | Configure | 2 s |
    | Tools (`psp_analyze`, `psp_recomp`, `dump_function`) | 2.9 s wall |
    | All 235 steps | 28 s |
    | `ctest` | 20/20 passed in 14 s |

    The build includes `portablekit_host_check`, which compiles and links the whole backend-independent host
    layer against the stand-in profile `tests/test_profile.cpp` (CMakeLists.txt:432-466). Logs:
    `~/dev/scratch/logs/build_pk.log`.
  - Trivial out-of-tree port (`~/dev/scratch/pk-trivial-port`, a 30-line constants-only profile,
    `-DPORTABLEKIT_FFMPEG=OFF`):
    - Configure took 4 s and printed `TrivialNative: Vulkan renderer enabled`.
    - The build took 19 s, including `vulkan_renderer.cpp` and ImGui, against brew SDL3 3.4.18, MoltenVK 1.4.2,
      vulkan-loader/headers 1.4.363 and glslang 16.6.0.
    - Log: `~/dev/scratch/logs/build_trivial.log`.
  - Extra observation, beyond the brief: a bounded run of that trivial port on a copy of BOOT.BIN.
    - Settings: headless, 45 s, interpreter only, no generated code compiled.
    - It printed `HLE imports: 278 total, 486 implemented, 50 logging stubs`.
    - The boot reached stock-module loading from `USRDIR/PRX`, file probing on disc0: and `sceMpegCreate`.
    - 18 of the 50 stubs are sceAtrac3plus and sceMpeg. They are stubs only because FFmpeg was off
      (host/hle/hle_atrac.cpp:910-916, host/hle/hle_mpeg.cpp:741-750). With FFmpeg there would be 32 (inferred).
    - Log: `~/dev/scratch/logs/interp_run.log`.

## 2. Yakumo API (with PortableKit equivalents)

### Tools (Yakumo CMakeLists.txt:138-147)

| Tool | Source | CLI |
|---|---|---|
| `psp_analyze` | tools/analyzer_main.cpp | `psp_analyze <decrypted ELF/PRX> [report.json] [load_base_hex]` (:81). Writes report.json plus `<stem>_imports.csv`, `<stem>_function_seeds.csv` and `<stem>_functions_auto.csv` next to it. Reads `configs/nids.csv` (compile-time default) or `$PSPRECOMP_NIDS_CSV` |
| `psp_recomp` | tools/codegen_main.cpp | `psp_recomp <ELF> <functions.csv> <generated_manifest.cpp>` (manual) and `psp_recomp <ELF> --auto <generated_dir> [load_base_hex] [unit_span_bytes] [--prefix <symbol_prefix>]` (:2045, :2054). Defaults: load base `kDefaultPspUserLoadBase` = 0x08804000 (:2041, include/psprecomp/elf32.hpp:15), unit span 0x4000 (:2043). `generate_auto` is at :1810. Manual mode hard-codes the default load base (:1497) |
| `dump_function` | tools/dump_function.cpp | debugging aid |

PortableKit has the same three tools (CMakeLists.txt:175-184). Its usage strings are tools/analyzer_main.cpp:77
and tools/codegen_main.cpp:1854/1864. It adds `--code START-END` to `--auto` (tools/codegen_main.cpp:1837-1844)
for code outside the executable sections.

### Runtime hooks (Yakumo include/psprecomp/runtime.hpp)

| Name | Signature | Yakumo line | PortableKit line |
|---|---|---|---|
| `HleFunction` | `std::function<void(Runtime &, AllegrexContext &)>` | 82 | 56 |
| `Runtime::register_hle` | `void register_hle(std::string library, std::uint32_t nid, HleFunction function);` | 93 | 67 |
| `Runtime::register_function` | `void register_function(std::uint32_t address, RecompiledFunction function, std::string name);` | 92 | 66 |
| `Runtime::unregister_functions` | `void unregister_functions(std::uint32_t start, std::uint32_t end);` (removes [start, end)) | 122 | 105 |
| `NativeFastPath` | `void (*)(Runtime &, AllegrexContext &)` | 83 | 57 |
| `Runtime::register_native_fast_path` | `void register_native_fast_path(std::uint32_t address, NativeFastPath function);` | 123 | 106 |
| `Runtime::invoke_native_fast_path` | `void invoke_native_fast_path(std::uint32_t address, AllegrexContext &ctx);` | 124 | 107 |
| `RuntimeMissingFunctionHook` / setter | `bool (*)(Runtime &, AllegrexContext &, std::uint32_t pc)`; `void set_runtime_missing_function_hook(RuntimeMissingFunctionHook hook) noexcept;` | 368-369 | 241-242 |
| `RuntimeUnsupportedHook` / setter | `bool (*)(Runtime &, AllegrexContext &, std::uint32_t pc, std::uint32_t instruction)`; `void set_runtime_unsupported_hook(RuntimeUnsupportedHook hook) noexcept;` | 375-376 | 248-249 |
| heartbeat, starvation, pre/post dispatch, pre/post chained call hooks | `set_runtime_*_hook` | 379, 395, 403-408, 415-420 | 251, 267, 276-279, 288-290 |
| `Runtime::run` | `void run(std::uint32_t entry, std::uint64_t max_dispatches = 10'000'000u);` | 101 | 82 |
| `register_generated_functions` | `void register_generated_functions(Runtime &)` | 359 | `(CorpusRuntime &)` in corpus_abi.hpp:411 |
| `Runtime::register_import_stub` | `bool register_import_stub(std::uint32_t address, std::string library, std::uint32_t nid);` | absent | 74 |

Other differences in PortableKit:

- `Runtime` derives from `CorpusRuntime` (runtime.hpp:52, corpus_abi.hpp:226). Generated units include only
  `corpus_abi.hpp`, which is a versioned ABI (`kCorpusAbiVersion`, :29).
- Every identifier in Yakumo's `include/psprecomp` headers also appears in PortableKit's, except an
  `install_profile` mention in a comment.

### Kernel scheduler

Yakumo: profiles/mhp3rd/host/kernel/kernel.hpp, namespace `mhp3rd`. PortableKit: host/kernel/kernel.hpp,
namespace `portablekit`.

| Entry point | Yakumo | PortableKit |
|---|---|---|
| `class Kernel` | :198 | :235 |
| `void install(Runtime &runtime, std::uint32_t gp, std::uint32_t image_end)` | :200 (cpp :110) | :237 (cpp :87) |
| `start_loader_thread(ctx, entry, stack_top)` | :241 | :276 |
| `create_thread(name, entry, priority, ...)` / `start_thread(ctx, uid, ...)` | :242 / :244 | :277 / :279 |
| `exit_current_thread(ctx, status, delete_thread)` | :246 | :281 |
| `finish(ctx, result)` / `finish64` | :253-254 | :288-289 |
| `block(ctx, const WaitState &, result)` / `wake(Thread &, result)` | :257 / :259 | :292 / :294 |
| `delay_current(ctx, us, result)` / `wait_host(ctx, timeout, poll)` | :260 / :266 | :295 / :301 |
| `call_guest(ctx, function, arguments, ...)` | :274 | :310 |
| `queue_interrupt`, `notify_callback`, `deliver_callbacks` | :304, :307, :310 | :344, :347, :350 |
| `on_vblank()` / `add_vblank_hook(fn)` | :315 / :318 | :355 / :358 |
| `on_starvation(ctx)` (preemption point) | :324 (cpp :662) | :364 (cpp :659) |
| `charge_busy_time()` | absent | :373 |
| private `switch_to`, `schedule`, `advance_clock` | :341, :344, :346 (cpp :335, :425) | :390, :393, :395 (cpp :313, :405) |
| `Kernel &kernel()` | :396 | :447 |

Runtime wiring: `install()` registers `set_runtime_starvation_hook(&native_starvation, interval)` (Yakumo
kernel.cpp:127, PortableKit kernel.cpp:105). The outer loop is `Runtime::run` (Yakumo src/runtime.cpp:538).

### GE display-list parser

Yakumo: profiles/mhp3rd/host/gpu/ge_state.hpp, namespace `mhp3rd::gpu`. PortableKit: host/gpu/ge_state.hpp,
namespace `portablekit::gpu`.

| Type | Yakumo | PortableKit |
|---|---|---|
| `struct DrawCall`: primitive, vertices, indices, through, texture, target, blend, depth, alpha_test, viewport, culling, clear_mode/flags, vertex_type, lighting, fog, world/view/projection/texture matrices, raw vertex and bone pointers | :159-209 | :159 |
| `struct BlockTransfer {source, source_stride, source_x, source_y, destination, destination_stride, destination_x, destination_y, width, height, bytes_per_pixel}` | :227-239 | :222 |
| `class GeState`. Sinks: `DrawSink = std::function<void(const DrawCall &)>`, `SignalSink`, `TransferSink = std::function<void(const BlockTransfer &)>`. Setters `set_draw_sink`, `set_transfer_sink`, `set_view_hook`. Entry: `std::uint32_t execute(const GuestMemory &memory, std::uint32_t pc, std::uint32_t stall, bool &finished)` | :243, :245-257, :269 | :238, :240-247, :259 |
| `decode_vertices(...)` | :351 | :348 |
| Bezier and spline | not tessellated: counted as unhandled (ge_state.cpp:1278-1283) | tessellated (ge_state.cpp:1137-1221) |

The sinks are connected to the renderer in PortableKit host/hle/hle_media.cpp:193 (draw sink to
`renderer.submit`) and :196 (transfer sink to `block_transfer`).

### Vulkan renderer

Yakumo has `mhp3rd::gpu::VulkanRenderer` at profiles/mhp3rd/host/gpu/vulkan_renderer.hpp:97 (the .cpp is 9013
lines):

| Member | Line |
|---|---|
| `bool initialize(const RendererConfig &config, std::string &error)` | :105 |
| `bool pump_events()` | :110 |
| `PadState pad()` | :111 |
| `void begin_frame()` | :139 |
| `void begin_display_list()` | :142 |
| `void submit(const DrawCall &call, const GuestMemory &memory)` | :149 |
| `void write_back_frame(GuestMemory &)` | :155 |
| `void read_back_framebuffer(std::uint32_t source, GuestMemory &)` | :160 |
| `bool present(std::uint32_t display_address, std::optional<time_point> moment)` | :168 |
| `initialize_ui` | :318 |
| `present_ui` | :327 |

PortableKit has `portablekit::gpu::VulkanRenderer` at host/gpu/vulkan_renderer.hpp:81 (the .cpp is 7713 lines),
with `initialize` :89, `submit` :130, `present` :149, `window()` :230 and `initialize_ui` :260. In both repos the
renderer still owns the SDL window, pad input and the ImGui Vulkan backend: `SDL_CreateWindow` and `SDL_PollEvent`
are in PortableKit vulkan_renderer.cpp:2073 and :4647. The split planned in D-002 is not done upstream.

### Profile registration in CMake (Yakumo)

- It is selected with the cache variable `PSPRECOMP_PROFILE` (CMakeLists.txt:49). Empty builds only the
  framework.
- The value is joined to a fixed path: `${CMAKE_CURRENT_SOURCE_DIR}/profiles/${PSPRECOMP_PROFILE}` (:170). That
  directory must hold a CMakeLists.txt (:171-173) and is added with
  `add_subdirectory(... "profiles/${PSPRECOMP_PROFILE}")` (:174).
- Directory layout: `profiles/mhp3rd/{CMakeLists.txt (1060 lines), cmake/FFmpeg.cmake, config/, host/, scripts/,
  tools/, tests/, third_party/, packaging/}`. The Git-ignored directories are `generated/`, `analysis/`, `game/`
  and `overlays/` (docs/BUILDING.md:21). docs/PROFILE_GUIDE.md:44 says the same.
- **A profile outside the repo tree is not supported as written.** The path is always under `profiles/`. Two
  workarounds, both inferred and untested: a symlink `profiles/<name>` pointing at our directory, or a vendor patch
  that accepts an absolute profile directory. PortableKit supports this directly; the trivial port above proves it.

### How MHP3rd's generated code is produced

The script is profiles/mhp3rd/scripts/generate.sh.

1. Input: `profiles/mhp3rd/game/EBOOT.ELF`, the decrypted executable (:13-18).
   - It comes from `Yakumo --install image.iso`, or from an external tool via
     `scripts/prepare_game.sh <iso> <EBOOT.ELF>` (prepare_game.sh:6-8, :35).
   - prepare_game.sh checks SHA-256 `55c05984...` and only warns on a mismatch (:21-29).
2. Builds `psp_analyze` and `psp_recomp` in `out/mhp3rd` (:20).
3. Runs `psp_analyze EBOOT.ELF profiles/mhp3rd/analysis/report.json` (:22) with the default load base.
4. Runs `psp_recomp EBOOT.ELF --auto profiles/mhp3rd/generated` (:26). It rewrites only changed units and removes
   stale ones.

Output and build:

- profiles/mhp3rd/CMakeLists.txt globs `generated/*.cpp` (:9) into the OBJECT library `mhp3rd_generated` in job
  pool `psprecomp_generated` (:270-274). Docs: docs/BUILDING.md:15 ("89 C++ units").
- Overlays: `scripts/build_overlays.sh` runs `tools/add_overlay.py` once per overlay (:57). The libraries go to
  `${CMAKE_BINARY_DIR}/bin/overlays` (CMakeLists.txt:820).
- `config/mhp3rd_npjb40001.toml` is documentation only. No code parses it: the only references are README.md:42
  and host/install/game_identity.hpp:4 (a comment). The constants live in host/mhp3rd_profile.hpp:12-48
  (`kLoadBase = kDefaultPspUserLoadBase`, `kGuestRamBytes = 64 MiB`, `kOverlaySlots`).

### Interpreter fallback

The interpreter is a process-wide switch, not a profile setting. That holds in both repos.

- It is on by default and `PSPRECOMP_NO_INTERPRETER=1` turns it off (Yakumo src/interpreter.cpp:36, PortableKit
  :61).
- API: `set_interpreter_fallback_enabled(bool)` and `interpreter_fallback_enabled()`
  (include/psprecomp/interpreter.hpp:48-49). No Yakumo profile code calls the setter.
- `PSPRECOMP_INTERPRETER_BUDGET` sets the slice size (:50-51).
- Dispatch order (Yakumo src/runtime.cpp:605-613):
  1. Look the address up.
  2. Call the missing-function hook, which the profile installs at profiles/mhp3rd/host/overlays.cpp:357.
  3. `run_interpreter_fallback`.
  4. Stop.
- **Running with no corpus differs between the two:**
  - Yakumo's main refuses: `No generated functions are linked...`, then return 3
    (profiles/mhp3rd/host/main.cpp:473-476).
  - PortableKit binds every import stub with `register_import_stub` (host/system.cpp:131-137) and interprets
    from the entry point (host/main.cpp:409-420).
  - PortableKit also runs an executable whose SHA-256 the profile does not know under the interpreter, with a
    warning (host/main.cpp:368-373).

## 3. Building (Yakumo docs/BUILDING.md)

- macOS section (:38-46): "Tested on Apple Silicon".
  `brew install cmake ninja python ccache pkg-config sdl3 molten-vk vulkan-loader vulkan-headers glslang` (:43).
  It expects **all five** of sdl3, molten-vk, vulkan-loader, vulkan-headers and glslang (the latter for
  `glslangValidator`). "FFmpeg is not needed: the build makes its own" (:46).
  PortableKit lists the same five (README.md:73).
- Steps (:116-147):
  1. `cmake -S . -B out/mhp3rd -G Ninja -DCMAKE_BUILD_TYPE=Release -DPSPRECOMP_PROFILE=mhp3rd`
  2. `cmake --build out/mhp3rd --target Yakumo` (bootstrap, no game code)
  3. `Yakumo --install iso --in-place`
  4. `prepare_game.sh`
  5. `generate.sh`
  6. Reconfigure and rebuild.
  7. `build_overlays.sh`

  Check the configure output for `mhp3rd: Vulkan renderer enabled` (:149).
- FFmpeg (:153-165): `MHP3RD_FFMPEG=bundled` is the default.
  - **It is built from source at CMake configure time.** The first configure downloads
    `ffmpeg-7.1.5.tar.xz` from ffmpeg.org and checks it against SHA-256 `de6685...`.
  - It is configured as LGPL with only the `atrac3`, `atrac3p` and `h264` decoders, built with `make`, and
    installed to `out/mhp3rd/bin/lib` (rpath).
  - Code: profiles/mhp3rd/cmake/FFmpeg.cmake:17-41 holds the version, URL, hash and flags. `_mhp3rd_ffmpeg_run`,
    an `execute_process` wrapper, is at :109-110. Fetch, extract, `configure`, `make -j$PSPRECOMP_GENERATED_JOBS`
    and install are at :243-264.
  - Offline: put the tarball in `out/mhp3rd/_deps/downloads/`.
  - `system` uses pkg-config `libavcodec libavutil` (:134). `OFF` drops music and movies.
  - On Windows it downloads a pinned BtbN prebuilt instead.
  - PortableKit has the same mechanism with the same pin (cmake/FFmpeg.cmake:17-19, `PORTABLEKIT_FFMPEG`).
    Wipeout needs ATRAC3+ and H.264 (sceAtrac3plus 8 imports, sceMpeg 23), and both are in the pinned set.
- Build time claims (:23-34), measured on an Apple M1 with 8 GB:

  | Stage | Claimed time |
  |---|---|
  | 89 generated units | 12-14 min |
  | 355 overlays | about 40 min |
  | Fresh clone, everything | about 1 h 50 min |
  | Steam Deck, everything | 5-6 h |

  Generated compiles run one job per 4 GiB of RAM (:34). PortableKit claims "about 2.5 minutes" to generate a
  2.6 MB executable (153 units) and "hours" to compile it (docs/BUILDING.md:42-48). The two claims disagree.
  Our probe: our largest unit (1.38 MB) compiles at -O2 in 60 s with a 1.0 GB maximum RSS. From that, all 144
  units should take about 15-20 min at 6 jobs on this machine (inferred estimate; see the S4 report).
- docs/MACOS.md is for players: release .dmg, Apple Silicon, macOS 13 or later.
- Local state: every brew dependency is installed except ffmpeg, which bundled mode does not need. Versions:
  sdl3 3.4.18, molten-vk 1.4.2, vulkan-loader and vulkan-headers 1.4.363.0, glslang 16.6.0, ccache 4.14.1,
  pkgconf 3.0.7. Python 3.13.2 and make 3.81 are on PATH. The bundled FFmpeg download and build were not run in
  this spike.

## 4. Recommendation: vendor PortableKit, pinned to 8b0c3fe

Reasons:

1. **It already is the split our research asked for** (docs/research.md:111, "Check PortableKit first: it may
   already be the split").
   - PortableKit's host layer is generic (namespace `portablekit`), and a port is a constants profile plus two
     hooks, kept outside the tree.
   - Yakumo's host layer is in namespace `mhp3rd` and its source list is mixed with game code: `host/camera/*`,
     `host/game/*`, `host/mods/*`, `gpu/game_hud.cpp` (profiles/mhp3rd/CMakeLists.txt:181-261).
   - With Yakumo we would either fork the profile or carry a patch to load an out-of-tree profile.
2. **Its framework is a superset of Yakumo's, and on our ELF it lowers everything.**
   - Both repos' tools analyse BOOT.BIN identically: 10962 functions, 456243 instructions, 144 units.
   - PortableKit emits 0 "not lowered" sites. Yakumo emits 76: 74 `lvl.q`/`lvr.q` and 2 `vbfy1`.
   - PortableKit also adds `register_import_stub`, the corpus ABI, `--code` ranges, and lowering for
     vrnd/vi2uc/vi2s/vt5650/vcrs.t/vbfy1.
3. **Much better HLE coverage of Wipeout's 278 imports.**
   - A name grep of the import list against each host tree finds 246 implemented in PortableKit and 165 in Yakumo
     (inferred: it counts names present in the source).
   - PortableKit's own startup report gives 50 stubs with FFmpeg off and 32 with it on (inferred).
   - PortableKit has `hle_net_offline` (sceHttp, sceNetInet, sceNetApctl, sceSsl, sceNetResolver), `hle_psmf` and
     `hle_psmfplayer`. Yakumo has none of them.
4. **Interpreter-first bring-up works today.** With no corpus, BOOT.BIN booted far enough to load modules and
   open files within 45 s. M1 can start before the 15-20 min corpus compile exists.
5. **GE: bezier and spline are tessellated**, where Yakumo drops them. HLE extension modules let our
   GPL-2.0-or-later HLE live outside `vendor/` with no patch.
6. **macOS works.** CI covers macOS, the build here is green with 20/20 tests, and the renderer compiles and links
   against brew MoltenVK.

Risks and what to do about them:

- **API stability.** "Expect ... breaking changes to its interfaces ... without notice" (README.md:5). Pin
  8b0c3fe and update only by decision.
- **Proven range.** Only Yakumo has been run end to end, recompiled, at full speed. PortableKit's recompiled ports
  are less proven:
  - Purun (LocoRoco 2) plays its first level on macOS (README.md:31).
  - Tenkawa's recompiled build does not draw (README.md:32, PortableKit issue #20).

  Keep Yakumo as a read-only reference for renderer fixes that are newer than the split.
- **Yakumo is ahead on some host code.** Its HEAD is 8 days newer, and its renderer is 9013 lines against 7713
  (part of that is MH-specific UI and camera code). If a GE bug shows up, diff that file before writing a fix.
- **Patches still needed.** The SDL/ImGui split of `VulkanRenderer` (D-002) is needed in both repos.

### Concern -> vendor path -> action (PortableKit paths)

| Our concern | Vendor path | Action |
|---|---|---|
| Codegen tools | tools/analyzer_main.cpp, tools/codegen_main.cpp, tools/dump_function.cpp, src/program_analysis.cpp, src/decoder.cpp, src/extra_instructions.cpp | **lift** (BOOT.BIN works unmodified, see S4) |
| Runtime core | src/runtime.cpp, src/guest_memory.cpp, src/elf32.cpp, src/nid_registry.cpp, include/psprecomp/{runtime,corpus_abi,allegrex_context,guest_memory}.hpp | **lift**; never edit headers (full rebuild) |
| Interpreter | src/interpreter.cpp, include/psprecomp/interpreter.hpp | **lift** |
| Kernel/scheduler | host/kernel/kernel.{hpp,cpp}, fixed_pool, message_pipe, rtc_time | **lift**; patch only if D-004's deterministic clock needs a seam there (inferred) |
| HLE threadman | host/hle/hle_threadman.cpp | **lift**. Fill `sceKernelUSec2SysClock` and 7 NIDs with no name in configs/nids.csv (0x912354A7, 0x94416130, 0xD8B299AE, 0xBC6FEBC5, 0x6652B8CA, 0x7E65B999, 0x18260574) through `register_extra_hle` or an HLE extension |
| HLE sysmem | host/hle/hle_sysmem.cpp | **lift** |
| HLE io (+umd) | host/hle/hle_io.cpp, host/kernel/iso_image.cpp | **lift** (reads disc0: from the ISO in place) |
| HLE system (LoadExec, ModuleMgr, Utils, Rtc, Power, Impose) | host/hle/hle_system.cpp | **lift**; add `sceKernelGetGPI`, ModuleMgr 0xD675EBB8, LoadExec 0xBD2F1094, sceRtc 0x3A807CC8/0x27C4594C through the profile hook |
| HLE utility | host/hle/hle_utility.cpp | **lift**; add the 4 `sceUtilityGameSharing*` stubs through the profile hook |
| HLE savedata | host/hle/hle_savedata.cpp, host/save_data/* | **lift**; the profile supplies `save_game_name` and `save_folders` (D-005) |
| HLE display, ctrl, audio, GE list | host/hle/hle_media.cpp, host/audio/audio_sink.cpp | **lift** |
| HLE sas | host/hle/hle_media.cpp (sceSasCore), host/audio/sas_core.cpp | **lift** |
| HLE atrac | host/hle/hle_atrac.cpp, host/audio/atrac_decoder.cpp | **lift** (needs FFmpeg) |
| HLE mpeg | host/hle/hle_mpeg.cpp, host/movie/{avc_decoder,psmf_demuxer,psmf_header}.cpp | **lift** (needs FFmpeg; skip path without it) |
| HLE net | host/hle/hle_net_offline.cpp, host/hle/hle_adhoc.cpp, host/adhoc/* | **lift** the offline stubs. Stub the 10 nameless sceHttp NIDs, sceParseHttp 0x8077A433, sceParseUri 0x568518C9, sceNetAdhoc 0xC7C1FC57 and `sceNetAdhocMatchingInit/Term` through the profile hook |
| GE parser + texture decode | host/gpu/ge_state.{hpp,cpp}, host/gpu/texture_decode.{hpp,cpp} | **lift**; patch for Wipeout GE gaps as found (inferred) |
| Vulkan renderer | host/gpu/vulkan_renderer.{hpp,cpp}, host/gpu/shaders/ | **patch**: split from SDL and ImGui behind the GE backend seam (D-002, D-003). Metal backend is **replace** (M6) |
| SDL window/input | inside host/gpu/vulkan_renderer.cpp (window, events, pad), host/input/bindings.cpp, host/ui/* | **patch**: move window and input out of the renderer (same patch as above) |
| FFmpeg build | cmake/FFmpeg.cmake (`PORTABLEKIT_FFMPEG=bundled`, 7.1.5) | **lift**; or `system` with brew ffmpeg. Bundled needs network on first configure |
