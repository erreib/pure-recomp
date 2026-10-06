# Status

Last updated: 2026-10-06 (session 4; see "Resume" below)

## Milestones

| Milestone | Goal | Exit command | Status | Last pass |
|---|---|---|---|---|
| P0 | environment, spikes S1 to S10 | `tools/check_env.sh` and the ten deliverables | in progress: S1 S2 S5 done, S7 S8 analysed, S3 S4 S6 running, S9 S10 open | 2026-10-05 |
| M1 | scaffold, codegen, link, game runs on the corpus | corpus run with `PSPRECOMP_NO_INTERPRETER=1` flips 60 s without an unlowered instruction | **done** (tooling tasks 001 still open) | 2026-10-05 |
| M2 | frontend on screen (Vulkan via MoltenVK) | frame 900 of the frontend route matches `ref/frontend.png` | **main menu reached** by script (`config/pad_scripts/main_menu.txt`: language, notice, title, profile NEW, 9-slot name, tag, save question, warning, MAIN MENU at ~frame 4450; `out/milestones/04-main-menu.png`); PPSSPP compare pending | 2026-10-05 |
| M3 | race start on Vineta K, faithful 3D | first full-HUD frame vs `ref/vineta_k_start.png` ≤ 0.30 at tol 32 (2x capture downscaled); 13,200-frame strict run (interpreter off, strict HLE, throttle held; retail has no Autopilot) exits 0 | **race reached**: Single Player > Single Race > Vector > Alpha > Vineta K > Feisar loads, countdown passes, HUD and music run (`out/milestones/05-race-vineta-k-magenta.png`); **done**: track, barriers, arches, sky, bloom, ship shadows and lens-flare occlusion (patches 0003-0006, 0008); frame 6016 vs PPSSPP **0.068** at tol 32; strict 13,200-frame run exits 0; clean shutdown (0007) | 2026-10-06 |
| M4 | audio and video | `wavstats.py` active ≥ 0.9 from the first music (main menu) and over the race window; movies play (patch 0002) | **done** (task 013): music loops seamlessly, effects over music in the race, no clipping; `PURE_AUDIO_WAV` + `tools/wavstats.py` | 2026-10-05 |
| M5 | saves and the whole campaign | `tools/campaign_sweep.py` cells PASS; `tools/save_roundtrip.sh` passes | **every single-player mode reaches its end screen** (task 018, 2026-10-06): Single Race on all four Alpha tracks (task 017, `--no-damage` test switch; Vineta K also without it), Time Trial and Free Play on Vineta K, Zone on PRO TOZO (SHIP DESTROYED panel, zone 6: no racing line, the ship runs out of shield against the first barrier), the Alpha Tournament through all four races to the final TOURNAMENT STANDING; save round trip passes (task 014). Open: higher classes and leagues, the other tracks in the 30-fps modes (untested budgets), a Zone line, multiple profiles need a save-list dialog, finished-race autosave leg, the AI grid varies per run (RNG) | 2026-10-06 |
| M6 | native Metal backend | `ge_replay --backend metal` passes on all recordings; `tools/frame_regress.sh --backend metal` passes | in progress: the seam landed (task 021, patch 0009: `gpu::GeBackend`, Vulkan adapter with pixel-identical captures, `null` and `record` backends, `tools/gerec/gerec_dump.py`); briefs 022 (ge_replay) and 023 (Metal first pictures) written | 2026-10-06 |
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
| Regression | `tools/frame_regress.sh` (task 020): five scenes vs the PPSSPP references in 7 min, PASS at the measured values; the merge gate for renderer changes |
| Sweep modes | `tools/campaign_sweep.py MODE TRACK` for single_race, time_trial, free_play, zone, tournament (task 018): routes in `config/pad_scripts/`, each mode's end screen detected (results TOTAL label, Free Play's END SESSION leg, Zone's SHIP DESTROYED title with the zone count read from the panel, Tournament's TOURNAMENT STANDING title); docs/tracks.md |
| GE seam | patch 0009 (task 021): every GE call the HLE makes goes through `gpu::GeBackend` (`PURE_GE_BACKEND=vulkan|null|record`); `null` runs headless with `PURE_NO_RENDER=`, `record` writes `.gerec` streams (`PURE_GE_RECORD*`); docs/ge-backend.md section 6 |
| Decompile | `tools/ghidra_headless.sh script Decompile <out> <addr>...` prints disassembly + C for any function |

## Blockers

| Blocker | State |
|---|---|
| (resolved 2026-10-05) heap corruption at shutdown | Patch 0007 (task 015): `VulkanRenderer::shutdown()` destroyed the descriptor pool before the render targets, and `destroy_target` then freed each target's copy descriptor sets into the destroyed pool, so MoltenVK wrote into its freed pool object. The abort ("free list is damaged ... Incorrect guard value") came later in exit, and the crash report it wrote is what looked like a shutdown hang. Found with `MallocScribble=1` (now `PURE_MALLOC_DEBUG=1` in `tools/env.sh`): the free then fails on the spot, `pointer being freed was not allocated` (0x5555555555555555) in `vkFreeDescriptorSets` from `destroy_target` |
| (resolved 2026-10-05) environment meshes | Patch 0005 (task 010): the vendored renderer had the GE alpha-test function numbering backwards (1 = ALWAYS, not NEVER), so 87% of the race frame's pixels were discarded. Race frame 6016 vs PPSSPP now 0.303 (`out/milestones/08-race-vineta-k-full.png`) |
| (resolved 2026-10-05) bloom chain | Patch 0003 (framebuffer-texture lookup) + patch 0004 (stencil ops as alpha writes, task 009): the bloom lights strips, screens and engines; race frame 6016 vs PPSSPP 0.631 (no bloom 0.663). Open follow-ups: shadow volumes (stencil zfail INCR/DECR, test GREATER) so ship shadows are missing; exact REPLACE under source-alpha blends needs dual-source blending |
| (resolved 2026-10-05) movies never ended, profile screen blank | Patch 0002: `sceMpegRingbufferAvailableSize` reported the ring empty while 16 pictures were still queued in the demuxer (the audio fetch runs ahead). The game ends a movie on an empty ring, so it dropped the end of every clip and never tore the instance down. With the patch all three movies (SCEA clip, `WoFMVNew_US.PMF`, `Profile_part1.PMF`) play and delete, the game autosaves `PPCD00001DLS001`, and the Profile screen (Load/New/Delete) appears (`out/milestones/03-profile-screen.png`). The 52-picture stop before the language confirm is by design (task 005) |
| Headless input | `PURE_INPUT_SCRIPT` and the pad belong to the window shell (`VulkanRenderer`), so a run without a window has no input and sits on Language Selection; routes run windowed. A pad source outside the shell is part of the shell split (task 026, the Metal presenter), or a profile-level pad injection into sceCtrl |
| Headless pace | without a window the kernel sleeps up to 1 ms of real time per clock step while any thread is in a host wait, and `user_main`'s `sceKernelWaitThreadEnd` is one for the whole run, so headless runs hold at about 19 frames a second (task 021). A kernel change (do not sleep for waits that depend only on guest state) is a Fable task when headless speed matters (ge_replay does not run the game) |
| Ghidra in worktrees | Ghidra refuses a project path containing `.claude`, so `tools/ghidra_headless.sh import` fails inside `.claude/worktrees/`; workers import into a scratch directory |
| `sceKernelSetVTimerHandler` | was a no-op in the first runs; now mirrors the framework's Wide form (profile) |

## Resume (session 4, 2026-10-06)
- `main` = ad219ee (Erik's third fast-forward, 2026-10-05). `batch/m2` is ahead with tasks 016, 017, 018, 019, 020, 021 and
  003 (diagnosis record) merged, D-003, briefs 022 and 023, `tools/verify_task.sh` (base-10 fix: `018` works).
- Merge gate: `tools/frame_regress.sh` (5 scenes, 7 min) after any renderer change; `tools/verify_task.sh NNN` reruns a
  brief's Verify from this checkout.
- Next: dispatch 022 (ge_replay, in the game executable behind `--replay`; our own `main()` through `HOST_MAIN_NAME`)
  and 023 (Metal backend, 2D frontend scenes) in parallel; both edit CMakeLists.txt, resolve by hand at merge. Then 024
  (Metal 3D), 025 (Metal stencil/bloom/depth write-back), 026 (Metal presenter + UI, the shell split that also gives
  headless input). `out/gerec/race.gerec` (23 MB, frames 6014 to 6016, Vulkan inner) is the first recording.
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
