# Status

Last updated: 2026-10-05

## Milestones

| Milestone | Goal | Exit command | Status | Last pass |
|---|---|---|---|---|
| P0 | environment, spikes S1 to S10 | `tools/check_env.sh` and the ten deliverables | in progress: S1 S2 S5 done, S7 S8 analysed, S3 S4 S6 running, S9 S10 open | 2026-10-05 |
| M1 | scaffold, codegen, link, game runs on the corpus | corpus run with `PSPRECOMP_NO_INTERPRETER=1` flips 60 s without an unlowered instruction | **done** (tooling tasks 001 still open) | 2026-10-05 |
| M2 | frontend on screen (Vulkan via MoltenVK) | frame 900 of the frontend route matches `ref/frontend.png` | **drawing**: SCEA splash at frame 120, Language Selection from frame ~600 (`out/milestones/02-language-selection.png`); route + compare pending | 2026-10-05 |
| M3 | race start on Vineta K, faithful 3D | countdown frame matches `ref/vineta_k_start.png`; 7200-frame strict Autopilot run exits 0 | open | |
| M4 | audio and video | `wavstats.py` active 90% after countdown; sceMpeg trace matches `ref/boot-hle.log` | open | |
| M5 | saves and the whole campaign | `tools/campaign_sweep.sh` and `tools/save_roundtrip.sh` pass | open | |
| M6 | native Metal backend | `ge_replay --backend metal` passes on all recordings | open | |
| M7 | v1.0 polish | `tools/bundle.sh` app runs from Finder | open | |

## Works

| Area | State |
|---|---|
| Environment | `tools/check_env.sh` passes (arm64 cmake/ninja, sdl3, MoltenVK, Vulkan 1.4, glslang, Ghidra 12.1.4 + allegrex, openjdk 21, PPSSPPSDL) |
| Disc | `tools/iso_extract.py` verifies CRC 4502C588 and extracts 38 files to `disc/` with a manifest |
| Imports | `config/imports.csv`: 278 imports, 33 libraries, all NIDs named, stub addresses |
| Ghidra | `tools/ghidra_headless.sh import` (1 min) then `export`: 8,966 functions in `config/function_map.csv`, stubs named |
| Labels | `tools/label_functions.py`: 8,851 string refs from relocations, 543 functions labelled by source file (`config/function_labels.csv`), `out/import-callers.csv` |
| Vendor | `tools/vendor_setup.sh`: PortableKit pinned at 8b0c3fe in `vendor/portablekit`, patch 0001 applied; `tools/build.sh` (CMake preset arm64, bundled FFmpeg 7.1.5 built at configure); `tools/regen.sh` (analyzer + codegen, 85 s, 144 units) |
| Profile | `src/profile/pure_profile.cpp` defines `portablekit::game()`: identity, hashes, 32 MiB, save folders, 5 extra HLE calls; `config/nids.csv` names the 26 NIDs the framework lacks |
| Corpus | `tools/regen.sh` + `tools/build.sh profile`: 144 units compiled in 7.5 min (12:33-12:41, 6 jobs, ccache cold); `PureNative` is 68 MB; with `PSPRECOMP_NO_INTERPRETER=1` the game runs 60 s and flips without reaching one unlowered instruction |
| Window | `tools/run_boot.py --window --env PURE_SCREENSHOT_DIR=... --env PURE_SCREENSHOT_EVERY=60`: Vulkan on MoltenVK, 960x544 swapchain, 170 to 516 draws a frame, frame 1260 in 45 s; BMP captures (convert with `sips -s format png`) |
| Interpreter boot | `tools/run_boot.py --seconds 120 out/x.log`: boots, loads the stock PRX modules, creates its threads (Main thread, Load screen, soundThread, readThread, snd_tick_timer_thread), parses XML from the WADs; 26 logging stubs, none hit in 120 s; about 1.6 M guest instructions per second, so the frontend load needs the corpus |
| Frame compare | `tools/imgdiff.py` + `tools/png.py` (task 002, merged on batch/m2): pure Python, BMP/PNG, tolerance, mask, region variance, `--selftest` |
| Input | `PURE_INPUT_SCRIPT` (framework): `pad a` = Cross confirms Language Selection, Cross clears the Memory Stick notice (shown ~frame 1500), title "PRESS START" ~frame 2050, Start opens the frontend |
| Decompile | `tools/ghidra_headless.sh script Decompile <out> <addr>...` prints disassembly + C for any function |

## Blockers

| Blocker | State |
|---|---|
| Headless intro movie | With `PURE_NO_RENDER`/`PURE_NO_AUDIO` the game spins on `sceMpegRingbufferAvailableSize` (returns 0x1A8 forever) at the intro movie; the windowed run passes it. Headless verification needs either the movie path to work without a renderer or a skip switch (M4-T4, R8) |
| `sceKernelSetVTimerHandler` | was a no-op in the first runs; now mirrors the framework's Wide form (profile) |
