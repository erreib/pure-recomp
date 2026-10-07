# Status

Last updated: 2026-10-06, M6 complete (session 4; see "Resume" below)

## Milestones

| Milestone | Goal | Exit command | Status | Last pass |
|---|---|---|---|---|
| P0 | environment, spikes S1 to S10 | `tools/check_env.sh` and the ten deliverables | in progress: S1 S2 S5 done, S7 S8 analysed, S3 S4 S6 running, S9 S10 open | 2026-10-05 |
| M1 | scaffold, codegen, link, game runs on the corpus | corpus run with `PSPRECOMP_NO_INTERPRETER=1` flips 60 s without an unlowered instruction | **done** (tooling tasks 001 still open) | 2026-10-05 |
| M2 | frontend on screen (Vulkan via MoltenVK) | frame 900 of the frontend route matches `ref/frontend.png` | **main menu reached** by script (`config/pad_scripts/main_menu.txt`: language, notice, title, profile NEW, 9-slot name, tag, save question, warning, MAIN MENU at ~frame 4450; `out/milestones/04-main-menu.png`); PPSSPP compare pending | 2026-10-05 |
| M3 | race start on Vineta K, faithful 3D | first full-HUD frame vs `ref/vineta_k_start.png` ≤ 0.30 at tol 32 (2x capture downscaled); 13,200-frame strict run (interpreter off, strict HLE, throttle held; retail has no Autopilot) exits 0 | **race reached**: Single Player > Single Race > Vector > Alpha > Vineta K > Feisar loads, countdown passes, HUD and music run (`out/milestones/05-race-vineta-k-magenta.png`); **done**: track, barriers, arches, sky, bloom, ship shadows and lens-flare occlusion (patches 0003-0006, 0008); frame 6016 vs PPSSPP **0.068** at tol 32; strict 13,200-frame run exits 0; clean shutdown (0007) | 2026-10-06 |
| M4 | audio and video | `wavstats.py` active ≥ 0.9 from the first music (main menu) and over the race window; movies play (patch 0002) | **done** (task 013): music loops seamlessly, effects over music in the race, no clipping; `PURE_AUDIO_WAV` + `tools/wavstats.py` | 2026-10-05 |
| M5 | saves and the whole campaign | `tools/campaign_sweep.py` cells PASS; `tools/save_roundtrip.sh` passes | **every mode and every track reached** (tasks 016 to 018, 032): all 12 circuits start a race and 10 finish three laps to the results screen (Sinucit and Manor Top stall where the test driver leaves the road), all 4 Zone tracks run to SHIP DESTROYED; Time Trial, Free Play and the Alpha Tournament to their end screens; the test-only unlock switch opens every class and league; racing lines recorded from the port's own AI; save round trip passes. Open for M8: classes above Vector, the other modes' higher leagues, the two follower stalls, multiple profiles' save list | 2026-10-06 |
| M6 | native Metal backend | `tools/frame_regress.sh --shell metal --backend metal` passes 5/5; `tools/gerec/metal_check.sh` passes (Metal against Vulkan on the team and race recordings) | **done** 2026-10-06: GE seam (021, patch 0009), ge_replay (022), Metal backend (023 frontend, 024 lighting/fog/sprites/culling, 025 stencil as alpha, bloom chain, read-backs, write-backs), shell seam (026, patch 0010), headless pace (patch 0011), Metal shell (027, patch 0012). Metal-only suite: lang 0.0002, title 0.0002, profile 0.0002, main_menu 0.0106, race_hud 0.0364 (Vulkan path: 0.054, 0.030, 0.054, 0.033, 0.067); race frame 6016 within 2 px of Vulkan at scale 1; 60 fps in the race under the Metal shell | 2026-10-06 |
| M8 | fidelity: as close to 1:1 with the original as possible (D-009) | the whole sweep without halts or unimplemented features; PPSSPP comparisons on every track and mode within the suite's limits | **audited and fixed** 2026-10-07: tasks 036 to 041 merged (patches 0013 to 0015 and 0017: environment and projection mapping, mipmaps, the save list, the colour test, dithering and the depth clamp); race scenes vs PPSSPP 0.011 to 0.035; differences 3, 7, 8 and 9 are the game's own or the harness's; open: 5 (save encryption) and 6 (UMD timing) await Erik, 12 (the SAS reverb the framework drops), the pre-warm list. Audit (task 035, docs/fidelity.md): 46 cells, no halt, no stub, no unsupported instruction, no skipped draw; 18 suite scenes vs PPSSPP pass; the two-vblank stretches are the game's own (PPSSPP too); 11 differences listed and briefed as tasks 036 to 041 (environment mapping, mipmaps, the save list, colour test/dither/clamp, the hitch and audio checks; difference 3, the brightness, closed by task 038 as the weather mist's phase, not the port's); 5 (save encryption) and 6 (UMD timing) await Erik's call | 2026-10-07 |
| M7 | v1.0 polish | `tools/bundle.sh && tools/bundle.sh --check out/029` passes; `tools/hud_check.sh` 61/61; controls documented | **playable from Finder** 2026-10-06: 028 (Metal by default), 030 (controls doc + checker), 029 (`Wipeout Pure.app` through the framework's packer, 88 MB, signed ad hoc, no game data; first-run setup takes the ISO), 031 (the Metal window's race HUD fixed). Open: the follow-ups (menu text, Info.plist copyright, a mid-race suite scene), then the enhancements | 2026-10-06 |

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
| Regression | `tools/frame_regress.sh` (task 020): five scenes vs the PPSSPP references in 7 min, PASS at the measured values; the merge gate for renderer changes |
| Sweep modes | `tools/campaign_sweep.py MODE TRACK` for single_race, time_trial, free_play, zone, tournament (task 018): routes in `config/pad_scripts/`, each mode's end screen detected (results TOTAL label, Free Play's END SESSION leg, Zone's SHIP DESTROYED title with the zone count read from the panel, Tournament's TOURNAMENT STANDING title); docs/tracks.md |
| GE seam | patch 0009 (task 021): every GE call the HLE makes goes through `gpu::GeBackend` (`PURE_GE_BACKEND=vulkan|null|record`); `null` runs headless with `PURE_NO_RENDER=`, `record` writes `.gerec` streams (`PURE_GE_RECORD*`); docs/ge-backend.md section 6 |
| ge_replay | `build/arm64/bin/PureNative --replay FILE.gerec [--backend N | --a N --b N [--first-diff]] [--compare --tol T --max-frac F] [--out DIR]` (task 022): replays a recording into any backend outside the game, compares pictures per frame as imgdiff.py does, bisects the first differing draw; Vulkan 5-13 ms a frame, null 1 ms. A backend against its own recording is exact only after warm-up frames (the bloom targets carry history); backend against backend starts equal. `tools/gerec/replay_check.sh` makes the recordings (race, race_warm, frontend, title) and runs the checks (5 min) |
| Metal backend | `PURE_GE_BACKEND=metal` (task 023, `src/gpu/metal_backend.mm`, docs/metal-backend.md): targets by (address, stride, format) at 480x272, textures via the vendor decoder cached by content, through-mode and transformed draws, clears, blends incl. exact FIX colours, GE alpha-test numbering, write masks, depth; shaders are MSL compiled at run time (no Xcode). Pictures reach the Vulkan window by a read-back hand-over until the Metal shell (027) |
| Shell seam | patch 0010 (task 026): `host::Shell` behind the HLE and the UI; `PURE_SHELL=vulkan|headless`; the headless shell reads the input script at pad level, so routes run without a window (`PURE_SHELL=headless PURE_GE_BACKEND=null --env PURE_NO_RENDER=`); pixel-identical Vulkan captures; docs/ge-backend.md 8.5 |
| Headless runs | `PURE_SHELL=headless PURE_GE_BACKEND=null tools/run_boot.py --script ROUTE --shots DIR --frames N` runs a route with no window at thousands of frames a second (patches 0010 and 0011): the frontend route to frame 2200 in 1.1 s. With `PURE_GE_BACKEND=metal` the shots are real pictures |
| Metal shell | `PURE_SHELL=metal` (task 027, `src/host/metal_shell.mm`): an SDL window with a CAMetalLayer, the shared SDL pad and input script, the Metal backend's texture shown directly (letterboxed; nearest at whole multiples of 480x272), ImGui on its Metal backend (`third_party/imgui_metal`, Dear ImGui 1.92.9b, MIT); `tools/frame_regress.sh --shell metal --backend metal`; patch 0012 moves the ImGui platform init into each shell |
| Controls | docs/controls.md (task 030): keyboard layouts, mouse, gamepad mapping and dead zones, rebinding in the menu and settings.ini (`~/Library/Application Support/pure-recomp/PureNative/settings.ini`), the input script's names; `tools/controls_check.py` keeps the tables equal to the code. The game: Cross accelerate, Square use pickup, Circle absorb, L/R airbrakes, Triangle reverse camera |
| App bundle | `tools/bundle.sh` (task 029): a Release build (`tools/build.sh release`, preset `arm64-release`) packed by `vendor/portablekit/scripts/release_macos.sh` into `out/release-macos/stage/Wipeout Pure.app` (SDL3, Vulkan loader, MoltenVK, FFmpeg inside; licences; no game data); first run: the framework's setup asks for the disc image and copies it under `~/Library/Application Support/pure-recomp/PureNative/`; `tools/bundle.sh --check DIR` runs the seven checks; docs/release.md |
| Decompile | `tools/ghidra_headless.sh script Decompile <out> <addr>...` prints disassembly + C for any function |

## Blockers

| Blocker | State |
|---|---|
| (resolved 2026-10-05) heap corruption at shutdown | Patch 0007 (task 015): `VulkanRenderer::shutdown()` destroyed the descriptor pool before the render targets, and `destroy_target` then freed each target's copy descriptor sets into the destroyed pool, so MoltenVK wrote into its freed pool object. The abort ("free list is damaged ... Incorrect guard value") came later in exit, and the crash report it wrote is what looked like a shutdown hang. Found with `MallocScribble=1` (now `PURE_MALLOC_DEBUG=1` in `tools/env.sh`): the free then fails on the spot, `pointer being freed was not allocated` (0x5555555555555555) in `vkFreeDescriptorSets` from `destroy_target` |
| (resolved 2026-10-05) environment meshes | Patch 0005 (task 010): the vendored renderer had the GE alpha-test function numbering backwards (1 = ALWAYS, not NEVER), so 87% of the race frame's pixels were discarded. Race frame 6016 vs PPSSPP now 0.303 (`out/milestones/08-race-vineta-k-full.png`) |
| (resolved 2026-10-05) bloom chain | Patch 0003 (framebuffer-texture lookup) + patch 0004 (stencil ops as alpha writes, task 009): the bloom lights strips, screens and engines; race frame 6016 vs PPSSPP 0.631 (no bloom 0.663). Open follow-ups: shadow volumes (stencil zfail INCR/DECR, test GREATER) so ship shadows are missing; exact REPLACE under source-alpha blends needs dual-source blending |
| (resolved 2026-10-05) movies never ended, profile screen blank | Patch 0002: `sceMpegRingbufferAvailableSize` reported the ring empty while 16 pictures were still queued in the demuxer (the audio fetch runs ahead). The game ends a movie on an empty ring, so it dropped the end of every clip and never tore the instance down. With the patch all three movies (SCEA clip, `WoFMVNew_US.PMF`, `Profile_part1.PMF`) play and delete, the game autosaves `PPCD00001DLS001`, and the Profile screen (Load/New/Delete) appears (`out/milestones/03-profile-screen.png`). The 52-picture stop before the language confirm is by design (task 005) |
| (resolved 2026-10-06) Headless input | Patch 0010 (task 026): the headless shell reads the input script at pad level, so every `pad`/`axis`/`shot`/`quit` route runs without a window (`PURE_SHELL=headless PURE_GE_BACKEND=null`); mouse, key and text steps still need a window |
| (resolved 2026-10-06) Metal window dropped the race HUD | Task 031: the backend and the shell shared no ordering (two command queues); both now use one device and one queue (`src/gpu/metal_device`), and the window shows the HUD in 61 of 61 probe shots (11 before) at 60 fps with no added wait. `tools/hud_check.sh [--shell ...]` guards it; the campaign sweep runs the default path again |
| (resolved 2026-10-06) Headless pace | Patch 0011: the kernel's host-wait sleep applies only to waits bound to real time (the adhoc network waits), and pacing follows the shell (`Kernel::set_paced`). Headless runs: the null backend to frame 2000 in 0.5 s (was 106 s), the headless frontend route to frame 2200 in 1.1 s (was 115 s), same draws and events |
| Ghidra in worktrees | Ghidra refuses a project path containing `.claude`, so `tools/ghidra_headless.sh import` fails inside `.claude/worktrees/`; workers import into a scratch directory |
| `sceKernelSetVTimerHandler` | was a no-op in the first runs; now mirrors the framework's Wide form (profile) |

## Follow-ups (collected 2026-10-06; none blocks a milestone)

| Item | Where it came from | Note |
|---|---|---|
| Vulkan backend loses column 0 / row 0 of transformed draws whose GE viewport is offset (the race HUD) | task 025 | a vendor patch: viewport into clip space, `VkViewport` the whole target, as Metal does; moves Vulkan's race_hud slightly; upstream candidate |
| Cross-queue ordering between the Metal backend and the Metal shell relies on Metal's resource tracking | task 027 | an `MTLSharedEvent` the backend signals at the flip would make it explicit |
| Block transfers and `read_back_framebuffer` from a rendered target are unexercised by any recording | task 025 | the race copies from main memory only; a scene that copies a rendered target (other tracks, Zone) needs a recording |
| Point and spot lights, specular, reversed normals ported but unexercised | task 024 | a recording of a night or tunnel track |
| Suite "measured" column is Vulkan's; a Metal run reports every scene as moved | tasks 023, 024 | task 028 |
| `run_boot.py --script` implies a window and leaves audio on; a `--shell headless` flag | task 026 | task 028 |
| Menu text "Graphics: Vulkan on ..." and frame-rate rows under the Metal shell | task 027 | cosmetic, `ui/menu.cpp` (vendor) |
| Format version 2: seed targets from a Begin record so a cold replay matches its recording exactly | task 022 | only if a Metal-against-PPSSPP cold start is ever needed |
| Zone has no racing line (the ship runs out of shield at the first barrier, zone 6) | task 018 | a PPSSPP lap of PRO TOZO logged with `tools/pp_lines.py`, or Erik's recorded lap |
| Time Trial and Free Play on the other Alpha tracks (budgets 11000 untested; the 30-fps modes read the live file every 10 flips) | task 018 | run with `--no-damage` |
| (resolved 2026-10-06) Higher classes and leagues need unlocks a fresh profile lacks | task 032: `PURE_TEST_UNLOCK_ALL=1` (GPI bit 0) opens Flash, Rapier, Phantom, the Beta and Classic leagues and Zone tracks 2 to 4; every track has a port-recorded racing line and a sweep row; six of eight new tracks pass, Sinucit and Manor Top stall (above) | |
| Multiple profiles need a save-list dialog; the finished-race autosave leg | task 014 | M5 breadth |
| E1 starting points from task 030: the framework's confirm-button row and labels are its first game's (Wipeout confirms with Cross, goes back with Triangle; `PURE_AUTO_CONFIRM` presses Circle); Triangle has only Mouse Left in the default keyboard layout, so with `input.mouse=0` the keyboard cannot go back; the camera and mouse rows act on a second stick this game lacks; gamepad buttons are not rebindable in the menu; one radial dead zone, no outer zone or curve | task 030 | enhancement E1 (controls): a profile field for the confirm button and the menu's labels, a keyboard key for Triangle by default, gamepad rebinding, dead-zone options |
| The app's Info.plist says "MIT License" (the framework's template), and the first-run setup screen says the image is what "the PlayStation 3 release carries" (`ui/setup_screens.cpp`, written for another game) | task 029 | two small vendor patches, or an Info.plist field in release.env upstream; cosmetic |
| The bundle is marked for macOS 13.0 after the packer's import check, but the Metal shell and backend have only run on macOS 15 | task 029 | try on an older Mac if one is ever at hand |
| Distributing the app beyond this Mac needs a public URL for the source (GPL v2 section 3); the notices point at the repository and the commit in the app's version | task 029 | only if Erik publishes |
| (measured 2026-10-06) Frame-rate dips in play | task 033: pipeline creation never happens inside a race now (pre-warmed from `config/metal_pipelines.txt`), the 120 Hz judder is gone (presents at the PSP's vblank), and the rest is the game's own two-vblank stretches, 2 to 11 a race of 0.4 to 1.3 s at fixed track positions on both paths: the M8 audit (task 035, item 6) finds what sets the lock and whether PPSSPP does the same. Task 041 (2026-10-07): the 0.1 to 0.3 s hitches of the matrix are the headless test runs' (priority-31 threads under host load, once a cold-cache pipeline compile of 243 ms), not a player's: 16 minutes of windowed race, with or without probes and the WAV capture, had no frame of 100 ms (longest 63 ms, the lens-flare depth wait) | |
| (resolved 2026-10-06) The app and the developer build shared one data directory | task 034: every tool runs on its own scratch `PURE_DATA_DIR` under out/ (run_boot, frame_regress, campaign_sweep, hud_check, save_roundtrip) and silent unless `--sound`; the app's settings are untouched by tests. Still reading the player's directory: `tools/pad_record.py`'s recording command (wants `--sound` and `--data-dir` with a copy of Erik's bindings), `PureNative --replay` (no data dir: the Vulkan pipeline cache), `tools/bundle.sh --check`'s runs (silenced and on `DIR/data` since task 042) | |
| Sinucit and Manor Top stall in the sweep, and Citta Nuova is marginal (passed once with 33 to 37 contacts a lap, stalled on geometry at 2580 m in the Verify rerun): the follower leaves the road at Sinucit's fork (about 900 to 1050 m) and Manor Top's tight right-left bend (2200 to 2300 m) and the game puts the ship back each time; the AI pack stays within 3 to 7 m of its line where the follower swings 15 to 23 m | task 032 | a limit of the test driver, not the port (the put-back is the game's own rule). Options: Erik's recorded lap of those tracks (`tools/pad_record.py`), a per-flip live read for the follower (a vendor change), or a fork-aware line (`pp_lines.py --port` picks the winner's fastest pass; the pack's mean is closer but mixes a fork's branches) |
| Flash, Rapier and Phantom are routed and budgeted in the sweep (4, 4 and 5 laps) but no cell has run above Vector; Time Trial, Free Play and Tournament still pick Alpha at Vector | task 032 | the M8 fidelity audit runs them with the unlock switch |
| (resolved 2026-10-07, task 042: the list is the union of 16 campaign cells, 37 render pipelines and 30 depth-stencil states, and the app ships it in Contents/Resources; not covered yet: classes other than Vector, Zone 2 to 4, the 30-fps modes off Vineta K, the attract demos) The app bundle did not carry `config/metal_pipelines.txt`, so the installed app made its render pipelines on first use (about 135 ms at the first race load on a cold shader cache; nothing inside a race). Since task 040 the list also lacks the six keys of the 16-bit and colour-test pipelines (four `sixteen=1`, two `color_test=1`: 1.2 ms at the first race frame; `PURE_METAL_PIPELINES_OUT` writes them). Task 041 counts nine pipelines every 30-fps run still makes by a draw, six at the race load and two or three in the race, 243 ms on a cold shader cache: the one hitch a player could meet | tasks 033, 040, 041 | `tools/bundle.sh`: copy it into `Contents/Resources` where the backend looks; regenerate the list with the new keys; with the next bundle rebuild |
| The vblank-timed present (task 033) ends the 8/25 ms pairing on a 120 Hz display but adds about 5.5 ms of latency on average; `PURE_METAL_PACE=0` presents at once | task 033 | Erik to judge by playing |
| Weather tracks (Sebenco Climb, Sinucit, any FxWeather track) cannot be compared frame to frame against PPSSPP: the mist's phase differs by the run's menu timing (task 038) | task 038 | for the scorecard: compare with the two mist draws left out on both sides, or a mist-substituted replay; the bisection readers (a full DrawCall parser on gerec_dump.py, a register reader on ppdmp.py, a .gerec draw patcher) were scratch scripts worth a tool |
| Texture mapping follow-ups (task 036): no picture check of mode 1 yet (Vineta K's projected plane is off screen in the suite's frame); reversed normals in mode 2 not settled by the notes; the lighting's specular half-vector uses world +z where the notes give the view matrix's third column (the race uses no specular); docs/ge-backend.md section 6's Draw record description predates patches 0013, 0014 and 0017 (the header in `ge_record_format.hpp` is current) | tasks 036, 037, 040 | small; a frame with the projected plane on screen; the specular viewer when a lit specular draw is found |
| Karbonis stalls under the test driver too (task 042: lap 3, the follower leaving the track at 2600 to 2760 m), beside Sinucit and Manor Top; Erik's recorded laps (`tools/record_lap.sh`) would replace the follower on the three | task 042 | when Erik records them |
| The SAS reverb (task 043, D-010): two constants fitted to PPSSPP's output, not documented; the parts no game here exercises are inferred (RevParam for ECHO and DELAY, PIPE as "Half Echo", type -1 as OFF); the menus' ring tail at the race start not measured; the attract demo's clipping not re-measured with the reverb | task 043 | a PSP capture of the pause would settle the constants; otherwise leave |
| Code organisation and simplification pass (Erik, 2026-10-07: "later on"): split src/gpu/metal_backend.mm by concern (targets, textures, pipelines, stencil-as-alpha and bloom, the 16-bit path) with the shaders out of the header string; one shared headless-runner module for the sweep, the audit, the scorecard and the replay checks; the test-only switches out of the profile into one test-hooks file; squash patches that touch the same files and send upstream candidates; move task history out of the reference docs into the task files. Measured by the suite and the scorecard before and after | Erik | after the scorecard (044), before enhancements |
| The port's frame times move in 1 ms quanta (task 046: `sceKernelGetSystemTimeWide` advances by the kernel's starvation tick, so the game's frame timer measures 15683/16683/17683 us where PPSSPP's follow the emulated CPU time); invisible in play, a difference in kind; a finer time answer (the dispatches since the last tick) would make the port's frames follow its own work | task 046 | Erik's call; a kernel patch |
| Scorecard follow-ups (task 044): coverage's halts/stubs rows read the 2026-10-06 matrix (a new matrix is about 4 h); functions entered is not measured (the VFPU differential test is still unbriefed); the stretch row rests on one race per side and swings by 1 to 3; `tools/save_roundtrip.sh` has no headless or single-run option (13 min windowed); `pp_lines.py --pad` holds end when the items run out (add a release); PPSSPP's debugger stopped answering `memory.read` twice in 20 runs (the tool retries once) | task 044 | with the next matrix refresh |
| Task 045 follow-ups: Export of a plain save from before patch 0019 stays plain until the game's next save rewrites it in mode 1 (teaching Export mode 1 needs a remembered "this game saves without a key"); mode 5 still pads data files to 16 bytes with no oracle to check; the profile's 69 stored heap pointers are 0x200 higher in the port than in PPSSPP (a start-up or allocator layout difference, harmless for saves) | task 045 | small; the heap offset when something else points at start-up layout |
| Task 040 follow-ups: `tools/gerec/metal_check.sh` must add `PURE_NO_MIPMAPS=1` beside `PURE_NO_TEXMAP=1` when it re-records (recordings now carry the mip levels, which Metal draws and Vulkan does not: race frame 6016 is 0.0219 at tol 24 with one switch, 3 pixels with both); the dithered billboard screen cannot be compared with PPSSPP at the suite's frames (the adverts are at another point of their cycle), so a reference at the same point of the cycle is wanted; rules the notes leave open are chosen and named in docs/metal-backend.md (fog before the colour test, clears into 16-bit targets not dithered, the offset before the single clamp, 8888 never dithered); 5551/4444 targets, the doubled factors, ABSDIFF and CLIPENABLE off are drawn but not exercised by the game | task 040 | small; with the next recording refresh |
| Save list follow-ups (task 039): PROFILE > SAVE opens the list on the first free slot (a PSP would sit on the current slot and ask to overwrite); a remembered current slot from the last LISTLOAD/LISTSAVE would fix the focus; LISTSAVE with a full stick and no scripted answer is cancelled headless; the list's look differs from the PSP's dialog (the interface's font and button symbols, no fade; after Delete completed the list closes where a PSP returns to it); the mouse was not exercised; the layout was not checked against `ref/save_dialog.png` | task 039 | small; for the scorecard's dialog comparison |
| Erik's recorded lap (`tools/pad_record.py`) to replace the AI-line follower where it struggles | session 2 | the command and keys are in the Resume notes |

## Resume (session 4, 2026-10-06)
- `main` = (Erik's ninth fast-forward, 2026-10-07, the commit below): tasks 003, 016 to 045 merged, patches 0001 to 0015
  and 0017 to 0019, D-003, D-007 to D-012, the M8 audit, its fix round, the reverb, PSP-format saves and the scorecard. `batch/m2` continues from there. Remote: `origin` =
  https://dev.eriksmedia.com/erreib/pure-recomp.git (private GitLab, created 2026-10-06 by Erik's push of `main`);
  Erik pushes, nobody else (the session's permissions deny pushes; CLAUDE.md forbids them for workers).
- Merge gate: `tools/frame_regress.sh` (5 scenes, 7 min) after any renderer change; `tools/verify_task.sh NNN` reruns a
  brief's Verify from this checkout.
- Merged 2026-10-06: 022 (ge_replay, in the game executable behind `--replay`; our own `main()` through
  `HOST_MAIN_NAME`), 023 (Metal backend: the 2D frontend scenes within 0.0002 of PPSSPP), 026 (the shell seam, patch
  0010: `host::Shell`, Vulkan shell adapter, headless shell with pad from the input script; D-007), and Fable's patch
  0011 (headless runs unpaced: thousands of frames a second), 027 (the Metal shell, patch 0012), 024 (Metal 3D:
  lighting, fog, screen-space sprites, culling; the race frame at internal scale 1 matches Vulkan to its first
  stencil draw), 025 (Metal effects: stencil as alpha, bloom chain, read-backs and write-backs, ge_replay `--cut`).
  **M6 complete.** D-008: Metal by default on macOS. Merged: 028 (the default in our entry point, per-backend
  measured columns in the suite, `run_boot.py --shell/--backend`; Verify rerun PASS on both paths), 030
  (controls doc + checker), 031 (the Metal window's race HUD: one command queue, `tools/hud_check.sh`), 029 (the app
  bundle; the profile names the plain BOOT.BIN so the installer works). **The app at `out/release-macos/stage/Wipeout
  Pure.app` is built from the merged tree with the HUD fix and passes its checks.** Merged: 032 (the test-only
  unlock-all switch, racing lines from the port's own AI, every track in the sweep). Merged: 034 (faster tests: the suite headless on Metal in 10 s, a sweep cell in 199 s with only the race paced,
  tools on scratch data directories, silent runs; Verify rerun PASS). Merged: 033 (frame-time trace, pipeline pre-warming, vblank-timed presents; the remaining dips are the
  game's own two-vblank stretches, routed to 035 item 6; Verify rerun PASS). **D-009 (Erik, 2026-10-06): fidelity before enhancements; the
  pause-menu redesign is dropped.** Merged: 035, the M8 fidelity audit (two workers; the matrix loop finished on its own; Verify rerun PASS,
  18/18 scenes). Merged: 036 (environment and projection mapping, patch 0013: the race scenes vs PPSSPP 0.012 to 0.035 now; the
  suite's Metal column re-baselined), 038 (the brightness is the weather mist's phase; not a difference). Merged: 039 (the save list, patch 0015; Verify rerun PASS), 037 (mipmaps, patch 0014: race scenes vs PPSSPP
  0.011 to 0.015 now, Blue Ridge 0.025; Verify rerun PASS). Merged 2026-10-07: 040 (colour test, dithering of the 565
  billboard target, depth clamp with CLIPENABLE on, patch 0017; the record backend records mip levels; race scenes
  unchanged or lower; Verify rerun PASS, 18/18, HUD 61/61). Merged 2026-10-07: 041 (the hitches are the headless test runs' own:
  priority-31 threads under host load and a cold-cache pipeline compile, 16 minutes of windowed race without a frame of
  100 ms; the music's 2 s stop is the track's own fade and silence and PPSSPP plays the same samples; PPSSPP's attract
  demos clip as much; `tools/audio_compare.py`, the driver's `--dump-audio`; Verify rerun PASS). **The M8 fix round is
  complete.** Open: differences 5 (save encryption, Sony's keys) and 6 (UMD timing) await Erik's call; 12 (the SAS
  reverb: the game sends type 5, both sends on, volume 0x666, the framework drops all of it; a vendor patch, PPSSPP's
  race dump through audio_compare.py as the check) is the next fidelity task if Erik agrees; the pre-warm list's nine
  missing pipelines are the one hitch a player could meet. Then the accuracy scorecard Erik asked about. Erik (2026-10-07): proceed with the three steps.
  Merged 2026-10-07: 042 (the pre-warm list over 16 cells, the app ships it, the bundle check silent and checking
  the pre-warm; Verify rerun PASS) and 043 (the SAS reverb, patch 0018, 17 patches; two constants fitted to PPSSPP,
  D-010; Verify rerun PASS). The app at out/release-macos/stage is repacked from the merged tree with both. Running:
  044 (the accuracy scorecard). Erik 2026-10-07: 6 → D-011, the faster loads stay. Merged 2026-10-07: 045 (saves in the PSP's own format: patch 0019 writes mode 1 without a game key and verifies saves on the way in; `tools/save_interchange.sh` passes both directions against PPSSPP; 18 patches; Verify rerun PASS). D-012: the expanded version's own save format, later. Merged 2026-10-07: 044 (the accuracy
  scorecard: `tools/scorecard.py --quick` in 49 s, `--full` in 18 min, references cached under ref/scorecard; first
  run in docs/scorecard.md: pictures faithful, timing faithful, audio faithful, saves close (69 heap pointers), coverage
  close, trajectories differs: the port's AI ships run a different race from PPSSPP's from 0.4 s after GO on every
  circuit while each side repeats itself, and three player paths move where an AI ship comes near or a wall scrape
  amplifies a 1 to 3 km/h contact difference). Merged 2026-10-07: 046 (the AI's start is `rand()` seeded from the time since boot and the game's frame clock at
  TEAM SELECTION, plus the unlocked team set and the port's 1 ms frame-time quanta; pinned by the test switch
  `PURE_TEST_RACE_CLOCK`, all 12 player trajectories are faithful, Karbonis included; the load is not involved; the AI
  still parts over a 1-ulp VFPU dot product in the codegen). Running: 047 (a worker: the VFPU probe through PPSSPP's debugger, thousands of
  samples per site, the rounding model that reproduces them, the transcendentals' error); then Fable puts the rule
  into the codegen header (patch 0020, corpus rebuild) and runs `tools/ai_seed_check.sh --tracks`; then the
  organisation pass, then enhancements.
  Open for Erik: a finer virtual-time answer than the kernel's 1 ms starvation tick. Erik, 2026-10-06: finish this round first; then consider an accuracy scorecard (pictures,
  trajectory divergence per track with the AI seed pinned, timing, audio correlation, save files byte for byte,
  coverage, a VFPU differential test) before any enhancement. The game's own unlock code on MAIN MENU: LEFT, RIGHT,
  LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R (sets the profile byte the test switch stands in for).
- M5 breadth still open: higher classes/leagues, the other tracks in Time Trial/Free Play (budgets 11000 untested),
  a Zone racing line (a PPSSPP lap of PRO TOZO logged with `tools/pp_lines.py`), Erik's recorded lap
  (`tools/pad_record.py`), the save-list dialog for multiple profiles.

## Resume (updated at the end of session 2, 2026-10-05)
- `main` = 2971eff (Erik's second fast-forward). `batch/m2` is two commits past it (resume notes, `tools/pad_record.py`).
- `task/011-shadow-volumes-and-dual-source` (29ec191): PARTIAL, patch 0006 exported but never built; the Result section
  holds the stencil-versus-alpha design rule and the exact remaining steps (wire `submit()`, build, capture, Verify).
  Finish it from that branch; do not merge the unbuilt patch. `task/012-campaign-sweep`: PARTIAL; the sweep tool, the single_race route, `docs/tracks.md` and a Vineta K
  notes file exist, no steering tuned (the first corner is a right-hander; a race needs ~18,000 flips). Decisions for
  the follow-up (Fable): `--frames` counts from the Cross hold, as the tool does; distance-keyed steering tables are
  acceptable; prefer Erik's recorded lap (`tools/pad_record.py`) over the closed-loop tuner, and keep the tuner's
  PPSSPP AI-line idea as the fallback for tracks nobody drives. Merge per the checklist;
  re-export 0006 over the series if `tools/patches.sh check` complains.
- Next steps in order: merge 011/012; Erik's recorded lap (`tools/pad_record.py` turns a run log with
  `PURE_TRACE_PAD=1 PURE_FRAME_LOG=1` into a script; the command and keys are in the chat recap and README) to replace
  hand-tuned steering; M4 audio checks (wavstats); M5 save round trip; then the Metal backend (M6) on top of the five
  vendor patches, which are all upstream candidates.
- Session 3 (2026-10-05, Erik: "Proceed"): workers dispatched for 011 (continued), 012 (continued), 013 (audio
  checks), 014 (save round trip); merge whichever finished, from their branches.
- Earlier resume notes (session 1) follow.

## Resume (written 2026-10-05 at the first pause)
- Branches: `main` fast-forwarded to ad219ee on 2026-10-05 (Erik's third "fast-forward main"): patches 0001-0007,
  tasks 001-015 (012 partial, 016 running). `batch/m2` continues from there. Both other workers committed PARTIAL results on their branches (worktrees under `.claude/worktrees/`):
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
