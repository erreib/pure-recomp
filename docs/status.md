# Status

Last updated: 2026-10-05 13:05 (session paused at this point; see "Resume" below)

## Milestones

| Milestone | Goal | Exit command | Status | Last pass |
|---|---|---|---|---|
| P0 | environment, spikes S1 to S10 | `tools/check_env.sh` and the ten deliverables | in progress: S1 S2 S5 done, S7 S8 analysed, S3 S4 S6 running, S9 S10 open | 2026-10-05 |
| M1 | scaffold, codegen, link, game runs on the corpus | corpus run with `PSPRECOMP_NO_INTERPRETER=1` flips 60 s without an unlowered instruction | **done** (tooling tasks 001 still open) | 2026-10-05 |
| M2 | frontend on screen (Vulkan via MoltenVK) | frame 900 of the frontend route matches `ref/frontend.png` | **main menu reached** by script (`config/pad_scripts/main_menu.txt`: language, notice, title, profile NEW, 9-slot name, tag, save question, warning, MAIN MENU at ~frame 4450; `out/milestones/04-main-menu.png`); PPSSPP compare pending | 2026-10-05 |
| M3 | race start on Vineta K, faithful 3D | countdown frame matches `ref/vineta_k_start.png`; 7200-frame strict Autopilot run exits 0 | **race reached**: Single Player > Single Race > Vector > Alpha > Vineta K > Feisar loads, countdown passes, HUD and music run (`out/milestones/05-race-vineta-k-magenta.png`); renders correctly with `PURE_NO_FB_TEXTURES=1` (bloom path open, see Blockers) | 2026-10-05 |
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
| References | `ref/` holds PPSSPP captures + GE dumps (task 006): frontend 602, title 2653, profile 2882, main_menu 5643, vineta_k_start 7155 (first full-HUD frame; the countdown has no digits), `boot-hle.log`. First compares at tol 24: main menu 3.3%, title 3.0% (PASS at 5%), profile and language 5.4% (downscale edges) |
| Runner | `tools/run_boot.py` (task 004): pty, `--script FILE`, `--shots DIR` (PNG via tools/png.py), `--every`, `--frames`, `--stubs`; `config/pad_scripts/frontend.txt` boots to the title and the profile screen (lang 700, notice 1600/1650, title ~1700, Start 1800, profile ~2000) |
| Input | `PURE_INPUT_SCRIPT` (framework): `pad a` = Cross confirms Language Selection, Cross clears the Memory Stick notice (shown ~frame 1500), title "PRESS START" ~frame 2050, Start opens the frontend |
| Ship probe | `PURE_WATCH_SHIP=1` (task 007): per-flip player position, velocity, km/h, distance, lap from the static race record at 0x08B72010 + 7*0x1C0 (PPSSPP reads the same address through the driver) |
| Decompile | `tools/ghidra_headless.sh script Decompile <out> <addr>...` prints disassembly + C for any function |

## Blockers

| Blocker | State |
|---|---|
| Environment meshes not drawn | Task 007: with identical input the port's physics match PPSSPP within 1 m for 46 s (same 338 km/h, same wall hit at 6.21 s, same resting place), so the "void" is the renderer: track surface, barriers, stadium arches, pillar bodies and sky are missing while crowds, billboards, skyline, ships and HUD draw (`out/007/side_t05-t20.png`). Separate from the bloom chain. Next: GE-list diff of one race frame against `ref/vineta_k_start.ppdmp` (task 010) |
| Bloom chain (framebuffer and depth memory sampled as textures) | With the framework's framebuffer-texture path on, the race scene is tinted magenta; with `PURE_NO_FB_TEXTURES=1` it renders correctly without bloom (`out/milestones/05-race-vineta-k.png`). The trace shows 512x512 fmt=3 "large or copied" textures at render-target addresses drawn in through mode: the game's bloom reads the frame and the depth area (0x04110000) as colour. Needs VRAM-aliasing-aware targets (R3); planned for the Metal backend design (M6), or a vendor patch if the Vulkan path has a simple fault. Patch 0003 fixed the lookup (magenta gone); now the whole scene blooms because the bloom mask is stencil-written alpha (REPLACE ref 4 / 0xFF) and the GE state ignores stencil (0x24, 0xDC, 0xDD) and the alpha write mask (0xE8/0xE9): task 009. Interim: routes run with `PURE_NO_FB_TEXTURES=1` |
| (resolved 2026-10-05) movies never ended, profile screen blank | Patch 0002: `sceMpegRingbufferAvailableSize` reported the ring empty while 16 pictures were still queued in the demuxer (the audio fetch runs ahead). The game ends a movie on an empty ring, so it dropped the end of every clip and never tore the instance down. With the patch all three movies (SCEA clip, `WoFMVNew_US.PMF`, `Profile_part1.PMF`) play and delete, the game autosaves `PPCD00001DLS001`, and the Profile screen (Load/New/Delete) appears (`out/milestones/03-profile-screen.png`). The 52-picture stop before the language confirm is by design (task 005) |
| Headless input | `PURE_INPUT_SCRIPT` is driven by the renderer's pad, so headless runs have no input at all and sit on Language Selection. Routes run windowed for now; a headless input path (profile-level pad injection into sceCtrl) is a new task |
| Ghidra in worktrees | Ghidra refuses a project path containing `.claude`, so `tools/ghidra_headless.sh import` fails inside `.claude/worktrees/`; workers import into a scratch directory |
| `sceKernelSetVTimerHandler` | was a no-op in the first runs; now mirrors the framework's Wide form (profile) |

## Resume (written 2026-10-05 at the pause)
- Branches: `main` d7467ec (scaffold). `batch/m2` = main + task 002 merged and reviewed; fast-forward main when Erik
  says so. Both other workers committed PARTIAL results on their branches (worktrees under `.claude/worktrees/`):
  - `task/001-tooling-port`: `tools/patches.sh` DONE (check/export tested), `tools/worktree_init.sh` written (a fresh
    worktree builds in 33 s, all 144 corpus units ccache hits, so R5 is resolved); run_boot flags, check_env PIN check,
    README rows NOT done. Merge the two scripts after rerunning `tools/patches.sh check`; re-brief the rest as task 004.
  - `task/003-headless-intro-movie`: diagnosis only (see Blockers). Re-brief as "movie end condition": validate
    against PPSSPP, then patch 0002 or `PURE_SKIP_FMV`.
- Fixes the workers asked for, outside their May-touch: `.gitignore` must use `/disc`, `/generated`, `/game` (the
  trailing-slash forms do not match the symlinks worktrees use); `tools/check_env.sh` still names `vendor/yakumo`;
  `run_boot.py` should give the game a pty (block-buffered stdout loses the tail at the deadline kill); `[hle-stub]`
  prints only on a stub's first call. Merge per the
  checklist in CLAUDE.md / the plan: rerun each brief's Verify from this checkout, spot-read, `git merge --no-ff` into
  `batch/m2`, remove the worktree.
- PPSSPP driver (spike S6, committed): `tools/ppsspp/ppsspp_ctl.py run --pad "700:CROSS,708:,..." --shot F:out.png
  --gedump F:out.ppdmp --log ...` drives PPSSPPSDL through its WebSocket debugger with frame-exact, deterministic input
  (`docs/ppsspp.md`). Screenshots need `SoftwareRenderer = True` (read from VRAM), GE dumps work with any renderer,
  save states are blocked (needs Accessibility for F2). PPSSPP timeline on a fresh memory stick: language ~480,
  notice ~1560, START at 2400 skips the movie, title ~2520, **profile screen Load/New/Delete ~2880** (our port shows a
  blank page there: the movie-end blocker). `ref/` is still empty; `out/ppsspp/title.{png,ppdmp}` and
  `out/ppsspp/boot-hle.log` exist. `tools/ppsspp/routes/{frontend,vineta_k_start}.txt` are deterministic (task 006).
- Next milestone steps: fix the profile-screen stall above; route to the main menu and a race (task 004: route script
  + `route_check` using `tools/imgdiff.py --region --min-variance`); PPSSPP reference compare; then M3 (race).
- The plan with every brief: `~/.claude/plans/in-the-bouncer-recomp-validated-babbage.md`.
