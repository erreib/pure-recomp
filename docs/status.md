# Status

Last updated: 2026-10-07 evening. M1 to M9 done (M9, the organisation pass, closed with task 053); then a
simplification task, then the enhancements. The session-by-session resume notes are in
[docs/history/sessions.md](history/sessions.md).

## Milestones

| Milestone | Goal | Exit command | State | Last pass |
|---|---|---|---|---|
| P0 | environment, spikes S1 to S10 | `tools/check_env.sh` and the ten deliverables | done, but S9 (the HLE coverage tool and its table under config/ were never made; the scorecard's coverage rows count the imports by state from `config/imports.csv`) | 2026-10-05 |
| M1 | scaffold, codegen, link, game runs on the corpus | corpus run with `PSPRECOMP_NO_INTERPRETER=1` flips 60 s without an unlowered instruction | done (the rest of task 001's tooling was task 004, merged) | 2026-10-05 |
| M2 | frontend on screen | frame 900 of the frontend route matches `ref/frontend.png` | done: every frontend screen in the suite, 0 pixels from PPSSPP's on Metal | 2026-10-06 |
| M3 | race start on Vineta K, faithful 3D | first full-HUD frame vs `ref/vineta_k_start.png` within 0.30 at tol 32; 13,200-frame strict run exits 0 | done: race_hud 0.0149 on Metal (0.067 on Vulkan) | 2026-10-07 |
| M4 | audio and video | `wavstats.py` active from the first music and over the race; movies play | done (task 013); the SAS reverb since task 043 | 2026-10-07 |
| M5 | saves and the whole campaign | `tools/campaign_sweep.py` cells PASS; `tools/save_roundtrip.sh` passes | done: every mode, class and circuit reached (tasks 016 to 018, 032, 035); the save list (039), PSP-format saves (045); the follower stalls on Sinucit, Manor Top and Karbonis (a test-driver limit) | 2026-10-07 |
| M6 | native Metal backend | `tools/frame_regress.sh --shell metal --backend metal`; `tools/gerec/metal_check.sh` | done (tasks 021 to 027); Metal is the default on macOS (D-008) | 2026-10-06 |
| M7 | v1.0 polish | `tools/bundle.sh && tools/bundle.sh --check out/029`; `tools/hud_check.sh` 61/61; controls documented | done: the app plays from Finder (tasks 028 to 031, 033, 042); open follow-ups below | 2026-10-07 |
| M8 | fidelity: as close to 1:1 with the original as possible (D-009) | the sweep without halts or unimplemented features; PPSSPP comparisons within the suite's limits | done (tasks 035 to 048): the 14 differences fixed, explained or accepted (docs/fidelity.md); the scorecard: pictures, timing and audio faithful, saves and coverage close, trajectories differs (the AI rows, difference 13) | 2026-10-07 |
| M9 | organisation: the code and docs simplified before enhancements (Erik) | each task's own proof of no change; `tools/docs_check.py` | **done** 2026-10-07: tasks 049 to 053 merged (the Metal backend by concern, the shared runner, the test hooks, nine patches by topic, the docs pass with `tools/docs_check.py`); the simplification task from 049's list is the first candidate after it | 2026-10-07 |

## Works

| Area | State |
|---|---|
| Area | State |
|---|---|
| Environment | `tools/check_env.sh` passes (arm64 cmake/ninja, sdl3, MoltenVK, Vulkan 1.4, glslang, Ghidra 12.1.4 + allegrex, openjdk 21, PPSSPPSDL) |
| Disc | `tools/iso_extract.py` verifies CRC 4502C588 and extracts 38 files to `disc/` with a manifest |
| Imports | `config/imports.csv`: 278 imports, 33 libraries, all NIDs named, stub addresses |
| Ghidra | `tools/ghidra_headless.sh import` (1 min) then `export`: 8,966 functions in `config/function_map.csv`, stubs named |
| Labels | `tools/label_functions.py`: 8,851 string refs from relocations, 543 functions labelled by source file (`config/function_labels.csv`), `out/import-callers.csv` |
| Vendor | `tools/vendor_setup.sh`: PortableKit pinned at 8b0c3fe in `vendor/portablekit` with the nine patches of `patches/` (one per topic since task 052; `tools/patches.sh check`, docs/upstream.md); `tools/build.sh` (CMake preset arm64, bundled FFmpeg 7.1.5 built at configure); `tools/regen.sh` (analyzer + codegen, 85 s, 144 units) |
| Profile | `src/profile/pure_profile.cpp` defines `portablekit::game()`: identity, hashes, 32 MiB, save folders, 5 extra HLE calls, the run-control switches; the test switches and probes in `src/profile/test_hooks.cpp` behind one `install` and one `flip` (task 051); `config/nids.csv` names the 26 NIDs the framework lacks |
| Corpus | `tools/regen.sh` + `tools/build.sh profile`: 144 units compiled in 7.5 min (12:33-12:41, 6 jobs, ccache cold); `PureNative` is 68 MB; with `PSPRECOMP_NO_INTERPRETER=1` the game runs 60 s and flips without reaching one unlowered instruction |
| Window | `tools/run_boot.py --window --env PURE_SCREENSHOT_DIR=... --env PURE_SCREENSHOT_EVERY=60`: Vulkan on MoltenVK, 960x544 swapchain, 170 to 516 draws a frame, frame 1260 in 45 s; BMP captures (convert with `sips -s format png`) |
| Interpreter boot | `tools/run_boot.py --seconds 120 out/x.log`: boots, loads the stock PRX modules, creates its threads (Main thread, Load screen, soundThread, readThread, snd_tick_timer_thread), parses XML from the WADs; 26 logging stubs, none hit in 120 s; about 1.6 M guest instructions per second, so the frontend load needs the corpus |
| Frame compare | `tools/imgdiff.py` + `tools/png.py` (task 002, merged on batch/m2): pure Python, BMP/PNG, tolerance, mask, region variance, `--selftest` |
| References | `ref/` holds PPSSPP captures + GE dumps (task 006): frontend 602, title 2653, profile 2882, main_menu 5643, vineta_k_start 7155 (first full-HUD frame; the countdown has no digits), `boot-hle.log`. First compares at tol 24: main menu 3.3%, title 3.0% (PASS at 5%), profile and language 5.4% (downscale edges) |
| Runner | `tools/run_boot.py` (task 004): pty, `--script FILE`, `--shots DIR` (PNG via tools/png.py), `--every`, `--frames`, `--stubs`; `config/pad_scripts/frontend.txt` boots to the title and the profile screen (lang 700, notice 1600/1650, title ~1700, Start 1800, profile ~2000) |
| Input | `PURE_INPUT_SCRIPT` (framework): `pad a` = Cross confirms Language Selection, Cross clears the Memory Stick notice (shown ~frame 1500), title "PRESS START" ~frame 2050, Start opens the frontend |
| Ship probe | `PURE_WATCH_SHIP=1` (task 007): per-flip player position, velocity, km/h, distance, lap from the static race record at 0x08B72010 + 7*0x1C0 (PPSSPP reads the same address through the driver) |
| Regression | `tools/frame_regress.sh` (tasks 020, 034, 035): 18 scenes vs the PPSSPP references, headless on Metal in about 25 s, PASS at the measured values; the merge gate for renderer changes, on both paths (docs/verification.md) |
| Sweep modes | `tools/campaign_sweep.py MODE TRACK` for single_race, time_trial, free_play, zone, tournament (task 018): routes in `config/pad_scripts/`, each mode's end screen detected (results TOTAL label, Free Play's END SESSION leg, Zone's SHIP DESTROYED title with the zone count read from the panel, Tournament's TOURNAMENT STANDING title); docs/tracks.md |
| GE seam | patch 0004-ge-backend-and-shell-seams (task 021): every GE call the HLE makes goes through `gpu::GeBackend` (`PURE_GE_BACKEND=vulkan|null|record`); `null` runs headless with `PURE_NO_RENDER=`, `record` writes `.gerec` streams (`PURE_GE_RECORD*`); docs/ge-backend.md sections 1 to 6 |
| ge_replay | `build/arm64/bin/PureNative --replay FILE.gerec [--backend N | --a N --b N [--first-diff]] [--compare --tol T --max-frac F] [--out DIR]` (task 022): replays a recording into any backend outside the game, compares pictures per frame as imgdiff.py does, bisects the first differing draw; Vulkan 5-13 ms a frame, null 1 ms. A backend against its own recording is exact only after warm-up frames (the bloom targets carry history); backend against backend starts equal. `tools/gerec/replay_check.sh` makes the recordings (race, race_warm, frontend, title) and runs the checks (5 min) |
| Metal backend | `PURE_GE_BACKEND=metal` (tasks 023 to 025, 036, 037, 040; `src/gpu/`, in seven files by concern since task 049; docs/metal-backend.md): targets by (address, stride, format) at 480x272, textures via the vendor decoder cached by content, through-mode and transformed draws, clears, blends incl. exact FIX colours, GE alpha-test numbering, write masks, depth; shaders are MSL compiled at run time (no Xcode). Pictures reach the Vulkan window by a read-back hand-over until the Metal shell (027) |
| Shell seam | patch 0004-ge-backend-and-shell-seams (task 026): `host::Shell` behind the HLE and the UI; `PURE_SHELL=vulkan|headless`; the headless shell reads the input script at pad level, so routes run without a window (`PURE_SHELL=headless PURE_GE_BACKEND=null --env PURE_NO_RENDER=`); pixel-identical Vulkan captures; docs/ge-backend.md section 8 |
| Headless runs | `PURE_SHELL=headless PURE_GE_BACKEND=null tools/run_boot.py --script ROUTE --shots DIR --frames N` runs a route with no window at thousands of frames a second (the shell seam and patch 0005-kernel-host-waits-and-pacing): the frontend route to frame 2200 in 1.1 s. With `PURE_GE_BACKEND=metal` the shots are real pictures |
| Metal shell | `PURE_SHELL=metal` (task 027, `src/host/metal_shell.mm`): an SDL window with a CAMetalLayer, the shared SDL pad and input script, the Metal backend's texture shown directly (letterboxed; nearest at whole multiples of 480x272), ImGui on its Metal backend (`third_party/imgui_metal`, Dear ImGui 1.92.9b, MIT); `tools/frame_regress.sh --shell metal --backend metal`; task 027 moved the ImGui platform init into each shell |
| Controls | docs/controls.md (task 030): keyboard layouts, mouse, gamepad mapping and dead zones, rebinding in the menu and settings.ini (`~/Library/Application Support/pure-recomp/PureNative/settings.ini`), the input script's names; `tools/controls_check.py` keeps the tables equal to the code. The game: Cross accelerate, Square use pickup, Circle absorb, L/R airbrakes, Triangle reverse camera |
| App bundle | `tools/bundle.sh` (task 029): a Release build (`tools/build.sh release`, preset `arm64-release`) packed by `vendor/portablekit/scripts/release_macos.sh` into `out/release-macos/stage/Wipeout Pure.app` (SDL3, Vulkan loader, MoltenVK, FFmpeg inside; licences; no game data); first run: the framework's setup asks for the disc image and copies it under `~/Library/Application Support/pure-recomp/PureNative/`; `tools/bundle.sh --check DIR` runs the seven checks; docs/release.md |
| Decompile | `tools/ghidra_headless.sh script Decompile <out> <addr>...` prints disassembly + C for any function |
| Shared runner | `tools/purelib` (task 050): the tools' one copy of running the game headless, the one-game guard, the clean environment and the log readers; every headless run on the steady clock (`PURE_NO_BUSY_CLOCK=1`) |
| Fidelity measures | `tools/scorecard.py` (task 044, docs/scorecard.md), `tools/fidelity_audit.py` (task 035), `tools/ai_seed_check.sh` (046), `tools/sas_reverb_check.sh` (043), `tools/save_interchange.sh` (045), `tools/vfpu_probe.py` and `tools/vfpu_model.py` (047, 048); docs/fidelity.md |
| Docs check | `tools/docs_check.py` (task 053): every path, link, patch and task file the docs name exists (docs/verification.md, "The docs check") |

## Blockers

| Blocker | State |
|---|---|
| Blocker | State |
|---|---|
| (resolved 2026-10-05) heap corruption at shutdown | Task 015 (patch 0003-vulkan-renderer-fixes): `VulkanRenderer::shutdown()` destroyed the descriptor pool before the render targets, and `destroy_target` then freed each target's copy descriptor sets into the destroyed pool, so MoltenVK wrote into its freed pool object. The abort ("free list is damaged ... Incorrect guard value") came later in exit, and the crash report it wrote is what looked like a shutdown hang. Found with `MallocScribble=1` (now `PURE_MALLOC_DEBUG=1` in `tools/env.sh`): the free then fails on the spot, `pointer being freed was not allocated` (0x5555555555555555) in `vkFreeDescriptorSets` from `destroy_target` |
| (resolved 2026-10-05) environment meshes | Task 010 (patch 0003-vulkan-renderer-fixes): the vendored renderer had the GE alpha-test function numbering backwards (1 = ALWAYS, not NEVER), so 87% of the race frame's pixels were discarded. Race frame 6016 vs PPSSPP now 0.303 (`out/milestones/08-race-vineta-k-full.png`) |
| (resolved 2026-10-05) bloom chain | Task 009 (patch 0003-vulkan-renderer-fixes: the framebuffer-texture lookup and stencil ops as alpha writes): the bloom lights strips, screens and engines; race frame 6016 vs PPSSPP 0.631 (no bloom 0.663). The follow-ups, shadow volumes and dual-source blending, were task 011 |
| (resolved 2026-10-05) movies never ended, profile screen blank | Task 005 (patch 0006-mpeg-ring-not-empty-while-aus-pending): `sceMpegRingbufferAvailableSize` reported the ring empty while 16 pictures were still queued in the demuxer (the audio fetch runs ahead). The game ends a movie on an empty ring, so it dropped the end of every clip and never tore the instance down. With the patch all three movies (SCEA clip, `WoFMVNew_US.PMF`, `Profile_part1.PMF`) play and delete, the game autosaves `PPCD00001DLS001`, and the Profile screen (Load/New/Delete) appears (`out/milestones/03-profile-screen.png`). The 52-picture stop before the language confirm is by design (task 005) |
| (resolved 2026-10-06) Headless input | Task 026 (patch 0004-ge-backend-and-shell-seams): the headless shell reads the input script at pad level, so every `pad`/`axis`/`shot`/`quit` route runs without a window (`PURE_SHELL=headless PURE_GE_BACKEND=null`); mouse, key and text steps still need a window |
| (resolved 2026-10-06) Metal window dropped the race HUD | Task 031: the backend and the shell shared no ordering (two command queues); both now use one device and one queue (`src/gpu/metal_device`), and the window shows the HUD in 61 of 61 probe shots (11 before) at 60 fps with no added wait. `tools/hud_check.sh [--shell ...]` guards it; the campaign sweep runs the default path again |
| (resolved 2026-10-06) Headless pace | Patch 0005-kernel-host-waits-and-pacing (Fable, after task 026): the kernel's host-wait sleep applies only to waits bound to real time (the adhoc network waits), and pacing follows the shell (`Kernel::set_paced`). Headless runs: the null backend to frame 2000 in 0.5 s (was 106 s), the headless frontend route to frame 2200 in 1.1 s (was 115 s), same draws and events |
| Ghidra in worktrees | Ghidra refuses a project path containing `.claude`, so `tools/ghidra_headless.sh import` fails inside `.claude/worktrees/`; workers import into a scratch directory |
| `sceKernelSetVTimerHandler` | was a no-op in the first runs; now mirrors the framework's Wide form (profile) |
| (resolved 2026-10-08) Vulkan viewport column 0 / row 0 | Patch 0010-vulkan-viewport-into-clip-space (task 056, from task 025): the GE viewport's x and y are in the draw's transform and the `VkViewport` is the whole target, as Metal draws; offset viewports (the race HUD) keep column 0 and row 0. The suite's scenes move by under 0.001, the Vulkan column is unchanged |
| (resolved 2026-10-08) Vulkan texture mapping modes | Patch 0011-vulkan-texture-mapping (task 057): the Vulkan renderer draws texture map modes 1 (the texture matrix, s and t divided by q per pixel) and 2 (the environment map) as the Metal backend does (task 036); `PURE_NO_TEXMAP=1` turns them off in both. On Windows the race scenes moved toward the reference: race_hud 0.059 (column 0.067), tt_hud 0.071, fp_hud 0.072, zone_hud 0.048, zone_change 0.052; the 13 non-race scenes unchanged. The Vulkan column is unchanged until step 3's re-measure |
| (resolved 2026-10-08) Vulkan mip levels | Patch 0012-vulkan-mipmaps (task 058): the Vulkan renderer uploads the mip levels a draw names and samples at the level the GE's rule picks (auto, constant, slope; the mip filter from the minification filter's bits), as the Metal backend does (task 037); `PURE_NO_MIPMAPS=1` turns it off in both and is byte-identical to the build before. Race frame 6016 replayed: the grandstand draw's 20133 pixels all at the level the rule gives. On Windows: race_hud 0.048 (task 057's run 0.059), tt_hud 0.062, fp_hud 0.062, zone_hud 0.046, zone_change 0.050; the 13 non-race scenes unchanged. The Vulkan column is unchanged until step 3's re-measure |
| (resolved 2026-10-08) Vulkan 16-bit targets and dither | Patch 0014-vulkan-16bit-dither (task 060): draws into 5650, 5551 and 4444 targets blend in `ge.frag` on the colour read as the render pass's own input attachment, get the GE's dither offset and keep the format's bits, as Metal's `ge_fragment_16`; `PURE_NO_DITHER=1` is byte-identical to the build before; `PURE_SHOW_TARGET=ADDR` presents an offscreen target. The 565 billboard target of race_warm frame 6016: every pixel a 565 value in every round (8-bit before), the flat round reproduces the rule on all 16384 pixels. On the fixed recording the dither moves 0 px of the frame at tol 8; the suite's race-scene moves are run wobble (zone_change 0.085, 0.029, 0.071 in three runs). README.md's `PURE_NO_DITHER` row still says Metal only and `PURE_SHOW_TARGET` has no row (outside task 060's files). Step 3's 0.005 exit is not met by any scene, menus included: see task 060's Result |
| (resolved 2026-10-08) Vulkan colour test and depth clamp | Patch 0013-vulkan-colortest-depthclamp (task 059): the Vulkan renderer draws the GE's colour test (a discard after fog, by specialisation constants) and CLIPENABLE's depth clamp (near plane only, screen z clamped per vertex, MINZ/MAXZ as clip distances, `depthClampEnable`) as the Metal backend does (task 040); `PURE_NO_COLOR_TEST=1` and `PURE_NO_DEPTH_CLAMP=1` turn them off in both and are byte-identical to the build before. Race frame 6016 replayed: the glow draws' discarded pixels are their black fragments; MINZ or MAXZ moved into a track draw's depth range cuts it pixel-exactly. As on Metal the clamp moves no pixel of the game's frames (1 px, a depth tie). On Windows: race_hud 0.0505 (task 058's run 0.0480), tt_hud 0.049, fp_hud 0.045, zone_hud 0.048, zone_change 0.048; the 13 non-race scenes unchanged. README.md's `PURE_NO_COLOR_TEST` and `PURE_NO_DEPTH_CLAMP` rows still say Metal only (outside task 059's files). The Vulkan column is unchanged until step 3's re-measure |

## Follow-ups (none blocks a milestone)

| Item | Where it came from | Note |
|---|---|---|
| Block transfers and `read_back_framebuffer` from a rendered target are unexercised by any recording | task 025 | the race copies from main memory only; a scene that copies a rendered target (other tracks, Zone) needs a recording |
| Point and spot lights, specular, reversed normals ported but unexercised | task 024 | a recording of a night or tunnel track |
| Menu text "Graphics: Vulkan on ..." and frame-rate rows under the Metal shell | task 027 | cosmetic, `ui/menu.cpp` (vendor) |
| Format version 2: seed targets from a Begin record so a cold replay matches its recording exactly | task 022 | only if a Metal-against-PPSSPP cold start is ever needed |
| Zone has no racing line (the ship runs out of shield at the first barrier, zone 6) | task 018 | a PPSSPP lap of PRO TOZO logged with `tools/pp_lines.py`, or Erik's recorded lap |
| E1 starting points from task 030: the framework's confirm-button row and labels are its first game's (Wipeout confirms with Cross, goes back with Triangle; `PURE_AUTO_CONFIRM` presses Circle); Triangle has only Mouse Left in the default keyboard layout, so with `input.mouse=0` the keyboard cannot go back; the camera and mouse rows act on a second stick this game lacks; gamepad buttons are not rebindable in the menu; one radial dead zone, no outer zone or curve | task 030 | enhancement E1 (controls): a profile field for the confirm button and the menu's labels, a keyboard key for Triangle by default, gamepad rebinding, dead-zone options |
| The app's Info.plist says "MIT License" (the framework's template), and the first-run setup screen says the image is what "the PlayStation 3 release carries" (`ui/setup_screens.cpp`, written for another game) | task 029 | two small vendor patches, or an Info.plist field in release.env upstream; cosmetic |
| The bundle is marked for macOS 13.0 after the packer's import check, but the Metal shell and backend have only run on macOS 15 | task 029 | try on an older Mac if one is ever at hand |
| Distributing the app beyond this Mac needs a public URL for the source (GPL v2 section 3); the notices point at the repository and the commit in the app's version | task 029 | only if Erik publishes |
| Sinucit and Manor Top stall in the sweep, and Citta Nuova is marginal (passed once with 33 to 37 contacts a lap, stalled on geometry at 2580 m in the Verify rerun): the follower leaves the road at Sinucit's fork (about 900 to 1050 m) and Manor Top's tight right-left bend (2200 to 2300 m) and the game puts the ship back each time; the AI pack stays within 3 to 7 m of its line where the follower swings 15 to 23 m | task 032 | a limit of the test driver, not the port (the put-back is the game's own rule). Options: Erik's recorded lap of those tracks (`tools/pad_record.py`), a per-flip live read for the follower (a vendor change), or a fork-aware line (`pp_lines.py --port` picks the winner's fastest pass; the pack's mean is closer but mixes a fork's branches) |
| The vblank-timed present (task 033) ends the 8/25 ms pairing on a 120 Hz display but adds about 5.5 ms of latency on average; `PURE_METAL_PACE=0` presents at once | task 033 | Erik to judge by playing |
| Weather tracks (Sebenco Climb, Sinucit, any FxWeather track) cannot be compared frame to frame against PPSSPP: the mist's phase differs by the run's menu timing (task 038) | task 038 | for the scorecard: compare with the two mist draws left out on both sides, or a mist-substituted replay; the bisection readers (a full DrawCall parser on gerec_dump.py, a register reader on ppdmp.py, a .gerec draw patcher) were scratch scripts worth a tool |
| Texture mapping follow-ups (task 036): no picture check of mode 1 yet (Vineta K's projected plane is off screen in the suite's frame); reversed normals in mode 2 not settled by the notes; the lighting's specular half-vector uses world +z where the notes give the view matrix's third column (the race uses no specular); (docs/ge-backend.md section 6's Draw record description, which predated tasks 036, 037 and 040, was brought up to date by task 053) | tasks 036, 037, 040 | small; a frame with the projected plane on screen; the specular viewer when a lit specular draw is found |
| Karbonis stalls under the test driver too (task 042: lap 3, the follower leaving the track at 2600 to 2760 m), beside Sinucit and Manor Top; Erik's recorded laps (`tools/record_lap.sh`) would replace the follower on the three | task 042 | when Erik records them |
| The SAS reverb (task 043, D-010): two constants fitted to PPSSPP's output, not documented; the parts no game here exercises are inferred (RevParam for ECHO and DELAY, PIPE as "Half Echo", type -1 as OFF); the menus' ring tail at the race start not measured; the attract demo's clipping not re-measured with the reverb | task 043 | a PSP capture of the pause would settle the constants; otherwise leave |
| (resolved 2026-10-09) The simplifications from task 049's list, done by task 062 (merged 1589688): one blit helper, one target byte span, draw() in parts (300 to 133 lines), the trace's, the pre-warm's and the switches' members in three structs (90 to 50 direct members); 0 differing pixels and the same counts against the 2026-10-07 captures. Left: snapshot_guest_words computes its own extent; `prewarm_.path` unread; the two PURE_TRACE_* flags sit in `trace_` though their readers are effects and targets | task 062 | small; with the next Metal change |
| Task 063 follow-ups: on Vulkan above internal scale 1 a through-mode draw that samples a target (the bloom's blur tiles) lost `clamp_through_quad`'s tile clamp to the wrap's placement (race_warm at 2x: a seam of up to 11 levels at x 638-639; keeping both needs a second flat varying); bilinear sampling within half a texel of a REPEAT seam blends with the target's neighbouring pixel, not the far edge's texel (a screen about 128 px tall or more); no `PURE_NO_...` switch for the wrap, unlike the Vulkan patches 0011-vulkan-texture-mapping to 0014-vulkan-16bit-dither | task 063 | the first with E3 (internal resolution); the others small |
| `tools/ppsspp/ppdmp.py tex` decodes only direct-colour VRAM textures: a CLUT4/CLUT8 texture comes out as 16-bit noise (the palette and the swizzle ignored). A standalone decoder with the palette (the CLUT record), the shift/mask/base of CLUTFORMAT, the swizzle and RAM textures was written 2026-10-10 while finding Vineta K's crowd texture (out/crowd/ppdmp_tex2.py, git-ignored): fold it into `tex`. Found with it: the crowd on Vineta K's stands is one CLUT4 64x64 texture of four spectator rows (draw 503 of ref/vineta_k_start.ppdmp, 0x041BE080), tiled along the stand by 381-vertex strips; the 216 ribbon draws after the sky (CLUT8 64x64 greyscale noise) cover no pixel of that frame. The other dumps: Blue Ridge and Sinucit each draw their own crowd texture of the same layout (four spectator rows, 64x64, CLUT8: draw 917 of blue_ridge_hud.ppdmp from RAM, draw 117 of sinucit_hud.ppdmp), different people and palettes; Sebenco Climb's start frame draws none. So the crowd is per circuit, one small texture each (out/crowd/sheet_*.png, the contact sheets) | the crowd question (Erik) | small; with the crowd-by-circuit task |
| E3 follow-ups (tasks 066 to 068): `ge_replay` needs a `--scale` option (the Vulkan lane replays at the recording's own size; task 068 relabelled a copy of race_1x.gerec as 960x544 for its 2x figures); the frame write-back copies the target's full width per row (2 MB at 4x, 4.2 MB at 8x; the depth write-back's 8.4 MB at 4x is larger); no `PURE_NO_...` switch restores the Vulkan renderer's old target sizes (an A/B needs a build without 0018-vulkan-effects-at-1x); (resolved 2026-10-11: the Windows suite ran with the nineteen-patch vendor on the RTX 3080 — 18/18 in 12m 17s, task 069's pacing, every scene within 0.012 of the Mac-measured Vulkan column, fp_hud +0.0120 the largest, no scene flagged as moved; out/071-suite.log); settings.hpp's `defaults_for` comment inexact; a scripted check of a live Resolution change needs a pad script and a way past run_boot's pin; block transfers into a scaled target invalidate rather than write | tasks 066-068 | small; the Windows run with the next Windows session |
| (was) Simplifications seen during the Metal split and not done (task 049, each a code change, not a move): `draw()` is 300 lines (the encoder-state block could be its own function); `read_back`, `copy_to_buffer` and `store_depth` repeat one blit; `find_framebuffer_texture`, `drawn_target_containing`, `latest_target_at` and `target_holding` are four scans of `targets_`; the class holds about 90 data members (the trace's, the pre-warm's and the switches' could be three small structs owned by their files) | task 049 | a simplification task after the docs pass, measured by tools/refactor_check.sh |
| The boot's loading screen follows host time (task 049: with `PURE_METAL_LOG=1` two runs of one build draw 368758 and 373243 times, the difference at flips 118 to 124 where some flips lack the logo sprites; without the log every run draws 372713), so log-heavy runs are not reproducible and the busy-time charge (task 051) may be the same thing | task 049 | with the next timing look |
| The PPSSPP session block (open an ini session, launch, connect, wait for the boot, pin the RTC, start the replay) is written four times (scorecard, audit, vfpu_probe, ai_seed_check); a shared `purelib.ppsspp.session` needs a PPSSPP run to prove unchanged | task 050 | small, with the next PPSSPP-side change |
| `tools/patches.sh export` appends above the last number, so the next vendor change becomes 0010 whatever its topic (task 052 regrouped twenty patches into nine by topic): an export mode that regenerates a named patch would keep the series by topic | task 052 | small |
| Code organisation and simplification pass (Erik, 2026-10-07: "later on"): done by tasks 049 (the Metal backend by concern, the shaders as `ge.metal`), 050 (`tools/purelib`), 051 (`src/profile/test_hooks`), 052 (nine patches by topic, docs/upstream.md) and 053 (the docs: reference and history, `tools/docs_check.py`); the simplification task from 049's list done by task 062 (2026-10-09); left: offering the upstream candidates (Erik's call) | Erik | after the scorecard (044), before enhancements |
| The port's frame times move in 1 ms quanta (task 046: `sceKernelGetSystemTimeWide` advances by the kernel's starvation tick, so the game's frame timer measures 15683/16683/17683 us where PPSSPP's follow the emulated CPU time); invisible in play, a difference in kind; a finer time answer (the dispatches since the last tick) would make the port's frames follow its own work | task 046 | Erik's call; a kernel patch |
| Scorecard follow-ups (task 044): coverage's halts/stubs rows read the 2026-10-06 matrix (a new matrix is about 4 h); functions entered is not measured (the VFPU differential test is still unbriefed); the stretch row rests on one race per side and swings by 1 to 3; `tools/save_roundtrip.sh` has no headless or single-run option (13 min windowed); `pp_lines.py --pad` holds end when the items run out (add a release); PPSSPP's debugger stopped answering `memory.read` twice in 20 runs (the tool retries once) | task 044 | with the next matrix refresh |
| Task 045 follow-ups: Export of a plain save from before task 045 stays plain until the game's next save rewrites it in mode 1 (teaching Export mode 1 needs a remembered "this game saves without a key"); mode 5 still pads data files to 16 bytes with no oracle to check; the profile's 69 stored heap pointers are 0x200 higher in the port than in PPSSPP (a start-up or allocator layout difference, harmless for saves) | task 045 | small; the heap offset when something else points at start-up layout |
| Task 040 follow-ups: (resolved 2026-10-08 at the 058 merge: `metal_check.sh` no longer sets `PURE_NO_TEXMAP=1` — since tasks 057 and 058 the Vulkan backend draws the modes and the levels too, so the A/B compares like with like unswitched); the dithered billboard screen cannot be compared with PPSSPP at the suite's frames (the adverts are at another point of their cycle), so a reference at the same point of the cycle is wanted; rules the notes leave open are chosen and named in docs/metal-backend.md (fog before the colour test, clears into 16-bit targets not dithered, the offset before the single clamp, 8888 never dithered); 5551/4444 targets, the doubled factors, ABSDIFF and CLIPENABLE off are drawn but not exercised by the game | task 040 | small; with the next recording refresh |
| Save list follow-ups (task 039): PROFILE > SAVE opens the list on the first free slot (a PSP would sit on the current slot and ask to overwrite); a remembered current slot from the last LISTLOAD/LISTSAVE would fix the focus; LISTSAVE with a full stick and no scripted answer is cancelled headless; the list's look differs from the PSP's dialog (the interface's font and button symbols, no fade; after Delete completed the list closes where a PSP returns to it); the mouse was not exercised; the layout was not checked against `ref/save_dialog.png` | task 039 | small; for the scorecard's dialog comparison |
| Erik's recorded lap (`tools/pad_record.py`) to replace the AI-line follower where it struggles | session 2 | the command and keys are in the Resume notes |

## Resume

- **Branches.** `main` = the commit below (Erik's nineteenth fast-forward, 2026-10-11: tasks up to 072, M1 to M9,
  the Windows bring-up with its icon, the billboard fix, the Esc menu by capability, E3 native resolution, E6 smooth
  flashes and E4 the 30-fps modes free-running done, nineteen patches by topic). `batch/m2` is the integration branch, equal to `main` at this point; every task branches
  from it (`git switch -c task/NNN-slug batch/m2`). Remote: `origin` = Erik's private GitLab
  (https://dev.eriksmedia.com/erreib/pure-recomp.git); Erik alone pushes.
- **The gate.** `tools/verify_task.sh NNN` reruns a brief's Verify from the main checkout; `tools/frame_regress.sh`
  (headless, about 25 s) after any change, both window paths and `tools/hud_check.sh` before merging a renderer or
  shell change (docs/verification.md, "Which path for which change"); `python3 tools/docs_check.py` after a change
  that moves or renames a file, a tool or a patch. Merge: rerun the Verify, spot-read, `git merge --no-ff` into
  `batch/m2`, remove the worktree.
- **Running.** The Windows bring-up (docs/windows.md). Step 2 is task 055, merged 522e3fb (2026-10-08): the
  harness runs on Windows (the PPSSPP 1.20.4 driver, the ConPTY runner, worktree_init for workers, the references
  retaken with the Mac's kept in ref/mac-2026-10-07/); the Windows scorecard grades Pictures close, Coverage
  close, Timing not measured (no matrix yet), Saves differs (the headless gap: a run without a drawing backend
  wrote no profile save and loaded no race — diagnosed and fixed 2026-10-08: not headless but the blind runs'
  metal backend falling back to Vulkan, which headless draws into no window; blind runs use the null backend on
  Windows (purelib.port.BLIND) and Saves grades close. refactor_check.sh alone stays macOS-only, needing headless
  pictures).
  Step 3's code is COMPLETE (2026-10-08, tasks 056 to 060 merged, the patch series 0010-vulkan-viewport-into-clip-space to 0014-vulkan-16bit-dither): the Vulkan renderer
  draws the viewport into clip space, texture map modes 1 and 2, mip levels at the GE's rule, the colour test,
  the depth clamp, and 16-bit targets with the GE's dither — each verified per pixel on replay cuts with a
  byte-identical off path. The suite's Vulkan column is re-baselined on this machine (race scenes 0.067-0.096
  down to 0.048-0.056); the 0.005-to-Metal exit bar is judged by tools/gerec/metal_check.sh's A/B on the Mac
  (task 060 found the suite's two columns are not measured alike: docs/windows.md). That A/B ran on the Mac
  2026-10-09 with the fourteen-patch vendor and PASSED: team frames 5650-5651 diff 0.000000, race_1x frame 6016
  diff 0.000015 (2 px of 130560 at tol 24; the first differing draw is the stencilled, alpha-tested CLUT4 ship
  decal at draw 508 of 864), so the two complete backends agree on one recording and step 3 is DONE. Step 4 (packaging) is task 061, merged 18c5df4 (2026-10-09): the `win-x64-release` preset,
  `tools/bundle_windows.sh` (the folder, `--zip`, `--check`: all seven checks PASS, docs/release.md "Windows");
  task 071 gave the executable its icon and a version resource (`packaging/windows/pure.ico` and `pure.rc`, through
  llvm-rc) and the check an eighth, `icon`: all eight checks PASS (out/071-icon); code signing is declined (Erik,
  2026-10-11: not paying a CA for a private build; the zip stays unsigned, README.txt's SmartScreen note is the
  answer, and a signature would put a verified legal name in the binary). With it the Windows bring-up's four steps
  are done, the Mac A/B included (2026-10-09). Step 1 was task 054 on `task/054-windows-build-boot`,
  run 2026-10-08 on Erik's Windows machine by the planning session itself (the corpus regeneration and the first
  cold build sit outside a worker's limits): the game builds with clang-cl on the win-x64 preset, the corpus
  regenerated there (145 units), and the frontend route, the main menu and a Vineta K race run on the framework's
  Vulkan renderer, headless and in a window on the RTX 3080, with `PSPRECOMP_NO_INTERPRETER=1` clean to frame
  6400. DONE 2026-10-08: with ref/ copied from the Mac, the Verify passes 18/18 on the Vulkan path against the Mac's
  measured Vulkan column unchanged (largest delta +0.0172). Steps 2 to 4 are worker tasks to brief; `tools/worktree_init.sh` needs
  its Windows pass before workers run in parallel here. Task 062 (2026-10-09, merged 1589688) did the simplification task from task
  049's list, proven by `tools/refactor_check.sh`; the organisation work is complete. Next: the enhancements (D-009).
- **The app.** Repacked 2026-10-11 from 012631c (`tools/bundle.sh --zip`, then `tools/bundle.sh --check out/repack-070`:
  8 checks PASS; out/repack-070.log), then from 36464ad (out/repack-072.log) and from 6fbfdfb (`--check
  out/repack-073` PASS; out/repack-073.log): Wipeout Pure 0.1.0-6fbfdfb at out/release-macos/stage, the zip in
  out/release-macos/dist. It has E3 (Auto resolution), the trimmed Esc menu, the billboard fix, E6 (the Flashes
  row, Smooth by default), E4 (the 30 fps modes row, 60 fps by default) and E7's Metal half (the Text and sprites
  row, Upscaled by default; a settings.ini an earlier build wrote lacks the keys and so reads the defaults).
  The Windows zip likewise repacked 2026-10-11 from 6393b67 on Erik's rig (`tools/bundle_windows.sh --zip`, then
  `--check out/repack-071`: all seven checks PASS, before task 071's icon check; out/repack-071.log):
  pure-recomp-0.1.0-6393b67-windows-x64.zip in out/release-windows/dist, with the same features; the route's title
  fraction 0.030170, unchanged from the 18c5df4 pack (a menu scene; E3's Auto changes the 3D, not the menus).
- **The Esc menu** (D-014, task 064, merged b92537a 2026-10-10): rows gated by the game's features and the
  shell's (patch 0016-menu-rows-by-capability); four tabs, no camera, mouse-camera, touch (Metal) or network rows;
  `tools/menu_check.sh` keeps the lists. Follow-ups: the bindings list's framework labels ("Move forward", four
  "Camera" bindings this game never reads); the Vulkan shell's Touch section on a desktop; Restore control defaults
  resets hidden rows. The enhancements are open.
- **E3, native resolution** (D-015, 2026-10-10): task 065 merged 3c674e4 (the Metal shell's drawable at the
  display's pixels: 1920x1088 for the default window on this Mac, the panel below the camera housing in full
  screen); task 066 merged d874184 (the backend at internal scale 1 to 6 or Auto, effects buffers at 1x, scale 1
  pixel-identical, `tools/scale_check.sh`; the Metal backend's test runs pinned to scale 1 by `tools/run_boot.py`,
  the Vulkan backend's at their 2x); task 067 merged 790e628 (the Resolution row for any backend that answers,
  patch 0017-internal-scale-by-backend; Auto as this game's default; a live change at the next frame; the on-screen
  perf table: 16.68 ms mean at Auto (4), 6 and 1, no frame over 25 ms); task 068 merged 867cad6 (patch
  0018-vulkan-effects-at-1x: the Vulkan renderer's narrow targets at 1x, Vulkan 2x now Metal's picture). **E3 is
  complete on both backends.** The app repacked from 056d27f (Auto by default). Task 069 merged 22d3ba5 (2026-10-11):
  the window checks run unpaced to the scene and capture the seven window scenes by default (`--all-scenes` for
  18): the window suites 19m 48s to 5m 10s, the HUD check 227 s to 82 s; `--paced` keeps the old pacing for a
  pacing change. Follow-up: a built-in wait in frame_regress.sh while another game runs.
- **E6, a steady frame rate through the full-screen flashes** (D-016, 2026-10-11; Erik's pick after his playtest:
  the dips at the race start and when a bomb goes off). The dips are the game's own two-vblank lock while a
  full-screen flash plays (docs/fidelity.md "The two-vblank stretches"); the game integrates a measured dt, so the
  lock does not set the race's speed. Task 070 (in flight): the countdown cleared each frame in the 60-fps modes
  from a `sceGeDrawSync` wrap in the profile, behind a Flashes row (Original / Smooth, Smooth by default) drawn by a
  generic game-option patch (0019-game-option-rows: `GameProfile::options`, `game.<key>` in settings.ini,
  `PURE_<KEY>`); every tool run pinned to `PURE_SMOOTH_FLASHES=0` through tools/purelib/port.py so the measured
  scenes stay; `tools/flash_check.sh` (the fade's 57 two-vblank flips to 0; a swept race with 0 stretches and lap
  times within 5%) is the check with it on. **Task 070 merged 68803cd (2026-10-11): E6 complete.** Gate: verify
  PASS, both menu dumps, suite 18/18 to the digit, HUD 61/61 (out/070_gate.log). Follow-ups: the `--race` lap bound
  is coarse (two different races; widen to 10% or compare the race clock's advance), the Flashes row's place after
  the Restore button when more rows come; on Windows `tools/menu_check.sh --shell vulkan` and
  `tools/flash_check.sh --shell vulkan` (and `--race`) have not run yet (docs/windows.md "Updating the rig": the rig's
  2026-10-11 session ran the suite and repacked, those two and the by-hand race are open).
- **E4, Time Trial, Free Play and Zone free-running** (D-017, 2026-10-11; Erik's pick after E6). The audit the plan
  asked for is done (the planning session; out/e4/ on the Mac): the lock is the frame object's byte `+0x116c`, set
  to 0 by the three modes' race managers after the race backend set it to 1, read only by the end-of-frame routine
  and the save-dialog driver; the frame timer's fixed-step bytes are dead (never written, 0 in .data); with the byte
  forced to 1 while the backend lives (`DAT_08a8c5f4`) a paced Time Trial ran at 59.95 flips a race-clock second
  with the same standing start and game-clock rate, the ghost samples by time (0.05 s), Zone's zone timer and shield
  drain follow the race clock. No per-frame logic found; the cheat's double speed is not the port's. **Task 072
  merged 8fb4955 (2026-10-11), the row renamed in 88fc1cf: E4 complete.** The hook in the E6 wrap, a "30 fps modes"
  row (Original / 60 fps, default 60 fps, `game.sixty_fps`, `PURE_SIXTY_FPS`), the pin beside `PURE_SMOOTH_FLASHES`,
  `tools/framerate_check.sh [--race]`. Gate: verify PASS (route 33.4/16.7 ms and 29.97/59.94 flips a second off/on;
  race 29.97/59.95, game clock 0.9994/1.0001, the standing start within 5%), flash_check, both menu dumps, suite
  18/18 to the digit, HUD 61/61 (out/072_gate.log). Follow-ups: Original chosen during a free-running race takes
  effect at the next race; a save dialog in a race runs free with the option on; the frontend at 60 (not audited);
  the check on the rig with `--shell vulkan`.
- **E7, the frontend's resolution** (D-018, 2026-10-11; Erik's pick after E4: the menus look low-resolution). The
  menus are bitmap font atlases and art atlases drawn at one texel a screen pixel in through mode, so E3 only
  magnified their texels (the planning session; out/fe_tex/). A prototype edge-preserving 4x resample on the real
  atlases gave crisp text and logos. **Task 073 merged ddad728 (2026-10-11): the Metal half of E7 complete.** The
  Metal backend upscales the textures of 2D draws (through mode, or orthographic with lighting off: the brief's
  "through mode" was wrong, the worker's BLOCKED run found the menus are orthographic transformed draws) in a
  palette or 16-bit format 4x at decode; a "Text and sprites" row (Original / Upscaled, default Upscaled,
  `game.sprite_upscale`, `PURE_SPRITE_UPSCALE`), the pin beside the other two (`ENHANCEMENTS_OFF` in port.py),
  `tools/sprite_check.sh`, `tools/sprite_proto_check.py`, `PURE_SPRITE_DUMP=DIR`. Gate: verify PASS (sprite_check
  7/7, the scaler the prototype's to the bit, 25 textures in 66 ms on the main menu, a race at scale 4 at 60 fps
  with 0 frames over 25 ms), hud 61/61, metal_check, window suites 7/7 both shells (out/073_gate.log).
  Follow-ups: sprite_check's margin on team_select and class_select; a byte cap on the texture cache; the TEAM
  ship sentence in docs/metal-backend.md. Task 074 (in flight): the dump as a PPSSPP-format texture pack for the
  Vulkan renderer (Windows) and as the base for an AI pass. The frontend at 60 fps comes after.
- **Open calls for Erik.** A finer virtual-time answer than the kernel's 1 ms starvation tick (task 046, a kernel
  patch); the vblank-timed present's 5.5 ms of latency, to judge by playing (`PURE_METAL_PACE=0`); recorded laps of
  Sinucit, Manor Top and Karbonis (`tools/record_lap.sh`) to replace the follower there; offering the upstream
  candidates (docs/upstream.md); a public source URL before distributing the app (GPL v2 section 3); D-012's own save
  format when the expanded version starts.
- The game's own unlock code on MAIN MENU: LEFT, RIGHT, LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R (sets the profile
  byte `PURE_TEST_UNLOCK_ALL` stands in for).

## Resolved

The follow-ups resolved since they were collected, with what resolved them:

- Cross-queue ordering between the Metal backend and the Metal shell relies on Metal's resource tracking (task 027).
  Resolved: task 031 put the backend and the shell on one command queue (docs/metal-backend.md, "One command queue").
- Suite "measured" column is Vulkan's; a Metal run reports every scene as moved (tasks 023, 024). Resolved: task 028: a
  measured column per backend.
- `run_boot.py --script` implies a window and leaves audio on; a `--shell headless` flag (task 026). Resolved: task 028:
  `--shell headless` (README.md).
- Time Trial and Free Play on the other Alpha tracks (budgets 11000 untested; the 30-fps modes read the live file every
  10 flips) (task 018). Resolved: the fidelity audit (task 035) ran Time Trial on all 12 circuits and Free Play on each
  league.
- Higher classes and leagues need unlocks a fresh profile lacks (task 032: `PURE_TEST_UNLOCK_ALL=1` (GPI bit 0) opens
  Flash, Rapier, Phantom, the Beta and Classic leagues and Zone tracks 2 to 4; every track has a port-recorded racing
  line and a sweep row; six of eight new tracks pass, Sinucit and Manor Top stall (above)). Resolved: task 032.
- Multiple profiles need a save-list dialog; the finished-race autosave leg (task 014). Resolved: the save list, task
  039; the finished-race autosave found by the audit, task 035 (docs/savedata.md, "Autosave").
- Frame-rate dips in play (task 033: pipeline creation never happens inside a race now (pre-warmed from
  `config/metal_pipelines.txt`), the 120 Hz judder is gone (presents at the PSP's vblank), and the rest is the game's
  own two-vblank stretches, 2 to 11 a race of 0.4 to 1.3 s at fixed track positions on both paths: the M8 audit (task
  035, item 6) finds what sets the lock and whether PPSSPP does the same. Task 041 (2026-10-07): the 0.1 to 0.3 s
  hitches of the matrix are the headless test runs' (priority-31 threads under host load, once a cold-cache pipeline
  compile of 243 ms), not a player's: 16 minutes of windowed race, with or without probes and the WAV capture, had no
  frame of 100 ms (longest 63 ms, the lens-flare depth wait)). Resolved: tasks 033, 035 and 041: the pre-warm and the
  vblank-timed present; the rest is the game's own two-vblank stretches and, in tests, host contention.
- The app and the developer build shared one data directory (task 034: every tool runs on its own scratch
  `PURE_DATA_DIR` under out/ (run_boot, frame_regress, campaign_sweep, hud_check, save_roundtrip) and silent unless
  `--sound`; the app's settings are untouched by tests. Still reading the player's directory: `tools/pad_record.py`'s
  recording command (wants `--sound` and `--data-dir` with a copy of Erik's bindings), `PureNative --replay` (no data
  dir: the Vulkan pipeline cache), `tools/bundle.sh --check`'s runs (silenced and on `DIR/data` since task 042)).
  Resolved: task 034.
- Flash, Rapier and Phantom are routed and budgeted in the sweep (4, 4 and 5 laps) but no cell has run above Vector;
  Time Trial, Free Play and Tournament still pick Alpha at Vector (task 032). Resolved: the fidelity audit (task 035)
  ran Single Race at Phantom on all 12 circuits.
- The app bundle did not carry `config/metal_pipelines.txt`, so the installed app made its
  render pipelines on first use (about 135 ms at the first race load on a cold shader cache; nothing inside a race).
  Since task 040 the list also lacks the six keys of the 16-bit and colour-test pipelines (four `sixteen=1`, two
  `color_test=1`: 1.2 ms at the first race frame; `PURE_METAL_PIPELINES_OUT` writes them). Task 041 counts nine
  pipelines every 30-fps run still makes by a draw, six at the race load and two or three in the race, 243 ms on a cold
  shader cache: the one hitch a player could meet (tasks 033, 040, 041). Resolved: task 042 (the list is the union of
  16 campaign cells, 37 render pipelines and 30 depth-stencil states, and the app ships it in Contents/Resources; not
  covered yet: classes other than Vector, Zone 2 to 4, the 30-fps modes off Vineta K, the attract demos).
- Headless runs depend on machine load through the kernel's busy-time charge (task 051: a thread over 100 ms of wall
  time without a wait has up to 250 ms added to the virtual clock; two of twelve runs under the other workers' load
  diverged); `PURE_NO_BUSY_CLOCK=1` makes them repeat exactly and the shared runner (task 050) sets it for every
  headless run; a player's game keeps the charge (task 051). Resolved: task 050: the shared runner sets
  `PURE_NO_BUSY_CLOCK=1` for every headless run.

The resume notes of every session, and the milestone table as it stood before task 053:
[docs/history/sessions.md](history/sessions.md).
