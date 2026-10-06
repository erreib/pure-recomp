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
| M5 | saves and the whole campaign | `tools/campaign_sweep.py` cells PASS; `tools/save_roundtrip.sh` passes | **every single-player mode reaches its end screen** (task 018, 2026-10-06): Single Race on all four Alpha tracks (task 017, `--no-damage` test switch; Vineta K also without it), Time Trial and Free Play on Vineta K, Zone on PRO TOZO (SHIP DESTROYED panel, zone 6: no racing line, the ship runs out of shield against the first barrier), the Alpha Tournament through all four races to the final TOURNAMENT STANDING; save round trip passes (task 014). Open: higher classes and leagues, the other tracks in the 30-fps modes (untested budgets), a Zone line, multiple profiles need a save-list dialog, finished-race autosave leg, the AI grid varies per run (RNG) | 2026-10-06 |
| M6 | native Metal backend | `tools/frame_regress.sh --shell metal --backend metal` passes 5/5; `tools/gerec/metal_check.sh` passes (Metal against Vulkan on the team and race recordings) | **done** 2026-10-06: GE seam (021, patch 0009), ge_replay (022), Metal backend (023 frontend, 024 lighting/fog/sprites/culling, 025 stencil as alpha, bloom chain, read-backs, write-backs), shell seam (026, patch 0010), headless pace (patch 0011), Metal shell (027, patch 0012). Metal-only suite: lang 0.0002, title 0.0002, profile 0.0002, main_menu 0.0106, race_hud 0.0364 (Vulkan path: 0.054, 0.030, 0.054, 0.033, 0.067); race frame 6016 within 2 px of Vulkan at scale 1; 60 fps in the race under the Metal shell | 2026-10-06 |
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
| Higher classes and leagues need unlocks a fresh profile lacks | M5 | **mapped 2026-10-06**: every frontend lock check reads `unlocked = (sceKernelGetGPI() & 1) ? 1 : profile->0x381` (FUN_088b43d4, FUN_0894fa5c, FUN_089516b8; the profile byte is set by the main menu's hidden sequence 2,3,2,8,9,8,3,2,3,9,8,9 of the game's button codes in FUN_0894d4c8, which shows "Everything"); GPI bit 0 is a dev-kit switch (the frame limiter uses bits 0x20/0x40/0x80). Task 032: `PURE_TEST_UNLOCK_ALL=1` returns 1 from our GPI override, racing lines from the port's own AI, every track in the sweep |
| Multiple profiles need a save-list dialog; the finished-race autosave leg | task 014 | M5 breadth |
| E1 starting points from task 030: the framework's confirm-button row and labels are its first game's (Wipeout confirms with Cross, goes back with Triangle; `PURE_AUTO_CONFIRM` presses Circle); Triangle has only Mouse Left in the default keyboard layout, so with `input.mouse=0` the keyboard cannot go back; the camera and mouse rows act on a second stick this game lacks; gamepad buttons are not rebindable in the menu; one radial dead zone, no outer zone or curve | task 030 | enhancement E1 (controls): a profile field for the confirm button and the menu's labels, a keyboard key for Triangle by default, gamepad rebinding, dead-zone options |
| The app's Info.plist says "MIT License" (the framework's template), and the first-run setup screen says the image is what "the PlayStation 3 release carries" (`ui/setup_screens.cpp`, written for another game) | task 029 | two small vendor patches, or an Info.plist field in release.env upstream; cosmetic |
| The bundle is marked for macOS 13.0 after the packer's import check, but the Metal shell and backend have only run on macOS 15 | task 029 | try on an older Mac if one is ever at hand |
| Distributing the app beyond this Mac needs a public URL for the source (GPL v2 section 3); the notices point at the repository and the commit in the app's version | task 029 | only if Erik publishes |
| Frame-rate dips in play (Erik, first race, 2026-10-06; the scripted race holds 59.7 to 60.1 fps) | playtest | a frame-time trace under the Metal shell with the cause of each long frame: first-use pipeline compiles (new blend/texture states: weapons, effects), CPU texture decodes on first bind, the SIGNAL depth read's GPU wait, stencil copies; then pre-warm pipelines and cache decodes. Brief after 032 |
| Erik's recorded lap (`tools/pad_record.py`) to replace the AI-line follower where it struggles | session 2 | the command and keys are in the Resume notes |

## Resume (session 4, 2026-10-06)
- `main` = 5594b0e (Erik's fourth fast-forward, 2026-10-06, at M6's close): tasks 003, 016 to 027 merged, patches
  0001 to 0012, D-003, D-007, D-008, briefs 028 to 030. `batch/m2` continues from there.
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
  Pure.app` is built from the merged tree with the HUD fix and passes its checks.** Running: 032 (the test-only
  unlock-all switch, racing lines from the port's own AI, every track in the sweep). Next: Erik's playtest; then the enhancements (E1 controls, E2 widescreen, E3 internal resolution, E4 60 fps in the
  30-fps modes, E5 filtering) and the M5 breadth items in Follow-ups (the v2.00 unlock routine first).
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
