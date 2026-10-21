# Status

Last updated: 2026-10-20 (0.2.0 released; the HD texture pack on both renderers, tasks 099 and 100; the crowd survey, the marshal as a model and its wave, the crowd on the stands, tasks 101 to 104). M1 to M9 done, the Windows bring-up done, the enhancements E2 to E8 and the US
download packs merged, 0.1.0 released for macOS and Windows on 2026-10-13, 0.2.0 (E8, the sound at 100 Hz) released 2026-10-20. Now: the cleanup the audit of 2026-10-19
asked for. How each arc got here, session by session: [docs/history/sessions.md](history/sessions.md) (the state
before this cut: ["The state before the docs diet"](history/sessions.md#the-state-before-the-docs-diet-2026-10-19-task-092)).

## Milestones and enhancements

| Item | Goal | State |
|---|---|---|
| P0 | environment, spikes S1 to S10 | done 2026-10-05, but S9 (the HLE coverage tool) was never made |
| M1 | scaffold, codegen, link, the game on the corpus | done 2026-10-05 |
| M2 | frontend on screen | done 2026-10-06: every frontend scene 0 pixels from PPSSPP's on Metal |
| M3 | race start on Vineta K, faithful 3D | done 2026-10-07 |
| M4 | audio and video | done 2026-10-07 (task 013; the SAS reverb, task 043) |
| M5 | saves and the whole campaign | done 2026-10-07: every mode, class and circuit; the save list (039); PSP-format saves (045) |
| M6 | native Metal backend | done 2026-10-06 (tasks 021 to 027); Metal is the macOS default (D-008) |
| M7 | v1.0 polish: the app | done 2026-10-07 (tasks 028 to 031, 033, 042) |
| M8 | fidelity, 1:1 with the original (D-009) | done 2026-10-07 (tasks 035 to 048; docs/fidelity.md) |
| M9 | organisation | done 2026-10-07 (tasks 049 to 053); the simplification, task 062, 2026-10-09 |
| Windows | bring-up, steps 1 to 4 (docs/windows.md) | done 2026-10-09 (tasks 054 to 061; the icon, task 071) |
| E1 | controls | open, not started: task 030's starting points (Follow-ups) |
| E2 | the 3D view at the window's shape (D-020) | done 2026-10-13, both renderers (tasks 084 to 086) |
| E3 | native resolution (D-015) | done 2026-10-10, both renderers (tasks 065 to 068) |
| E4 | Time Trial, Free Play and Zone at 60 fps (D-017) | done 2026-10-11 (task 072) |
| E5 | texture detail (D-019) | done 2026-10-12, both renderers (tasks 075, 076) |
| E6 | a steady frame rate through the flashes (D-016) | done 2026-10-11 (task 070) |
| E7 | the frontend's resolution (D-018) | done 2026-10-11 (tasks 073, 074); Original by default since 2026-10-12; to be retired once the HD pack's menus draw on both renderers (Erik, 2026-10-20; Next) |
| E8 | the display rate (D-022) | done 2026-10-15 (tasks 089, 091-display-rate-margin); the rig's 100 Hz sound probe PASSes since 2026-10-19 (task 500), the sink's early-race shape fixed the same day (task 501); Erik's ear on a played race owed |
| DLC | the US download packs (D-005) | done 2026-10-12 (tasks 077-download-packs, 078-download-packs-menu) |
| R1 | the first public release | done 2026-10-13: v0.1.0 at f31c1be (task 087); 0.2.0 released 2026-10-20: v0.2.0 at 13ac398 (E8, the sink's late rule, patch 0029-windows-file-url; both archives and the sums on the page) |
| VR | the stereo spike (D-021) | briefed, undispatched (task 088) |
| HD pack | NR74W's HD texture pack (D-024) | tasks 099 and 100 merged 2026-10-20: the pack draws on both renderers (the race route: 127 images, 594 to 599 MB on the GPU; the menus: 11), zstd 1.5.7 a pinned source download, `tools/sprite_pack.sh --pack DIR [--shell metal]` the check; Erik's eye on the import screen under Metal and on the menus against E7's upscale owed |
| Crowd | 3D crowd and people models in place of the track-side sprites (D-025) | tasks 102 to 104 merged 2026-10-20: the `models` GE backend, the "Crowds and people" row (Original by default), the pit marshals as Astra's model waving, the grandstands filled with Astra's eight spectators (about 1360 figures a frame on Vineta K, hashed by place, thinned with distance, batched); the Vulkan shell holds 60 fps with the crowd, the Metal backend does not (its per-frame de-indexed upload: task 105, the static batches cached); the row's default flips to Models after it |
| Photo mode | a paused race seen from a free camera, captured at any resolution | on the roadmap, not scheduled (Next); nothing looked at yet |
| Skies | 3D backgrounds in place of the tracks' 2D sky images | on the roadmap, not scheduled (Next); nothing looked at yet |
| Cleanup | the audit of 2026-10-19 | tasks 092 to 095 merged 2026-10-19, their doc lines applied (docs/history/audit-2026-10-19.md); the screen batch (task 097) ran on the Mac 2026-10-19, every row PASS; the rig's batch (task 500) the same day, every row PASS |

## Works

What runs today. The Mac is an M4 Pro with a 120 Hz display; the rig is Erik's Windows machine (i5-8600K, RTX 3080,
a 100 Hz display).

| Area | State |
|---|---|
| Toolchain | Mac: `tools/check_env.sh` (arm64 cmake and ninja, SDL3, MoltenVK, Ghidra 12.1.4, PPSSPP); the rig: clang-cl on the `win-x64` preset, Git Bash (docs/setup.md) |
| Disc and game | `tools/iso_extract.py` verifies CRC 4502C588 and extracts `disc/`; `tools/setup_game.sh` lays out `game/` |
| Vendor | PortableKit at 8b0c3fe with 33 patches by topic (numbered to 0034; 0025 removed) (`tools/patches.sh check`; patches/README.md, docs/upstream.md, docs/vendor-map.md) |
| Corpus | `tools/regen.sh` (85 s): 144 units on the Mac, 145 on the rig, inlined on both since patch 0026-corpus-inlining; `PSPRECOMP_NO_INTERPRETER=1` runs clean |
| The game | the whole single-player game: every mode, class, league and circuit; the movies, the music and the sound with the SAS reverb; saves in the PSP's format with the save list, import, export and backups; the twelve US download packs |
| Mac, Metal (the default) | the Metal shell and backend (D-008): the drawable at the display's pixels, internal scale Auto, Fill, texture detail, the flashes smoothed, the 30-fps modes at 60, the race at 119.40 Hz on the 120 Hz display (E8), the performance overlay (F3) |
| Mac, Vulkan | the framework's Vulkan shell and renderer on MoltenVK: internal scale, Fill, texture detail and the game's rows as on Metal (the sprite upscale is Metal's; Vulkan takes art as a texture pack); E8's sound holds at the margin on both shells |
| Windows, Vulkan | the rig: the game at 60 fps with E2 to E6 and E8, the corpus inlined (task 083); at the Display rate on its 100 Hz display the sound probe PASSes with task 098's sink armed early (task 501: the race load's landing starts the lead rebuild, the dip at race second 4 passes with no silence); whether a played race keeps real time there with a gamepad is Erik's to measure (docs/windows.md, "Open on the rig") |
| Headless | `PURE_SHELL=headless` with the `metal` backend (real pictures) or `null`, thousands of frames a second; on Windows nothing draws headless, so blind runs take the null backend (`purelib.port.BLIND`) |
| Esc menu | rows by what the game and the shell can do (D-014): Resolution, Aspect ratio, Performance, the game's rows (30 fps modes, Flashes, Text and sprites, Texture detail, Display rate), Download packs in System; `tools/menu_check.sh` on both shells |
| Controls | keyboard (two layouts), mouse, gamepads, rebinding in the menu (docs/controls.md; `tools/controls_check.py`) |
| The app and the zip | `tools/bundle.sh` makes `Wipeout Pure.app`, `tools/bundle_windows.sh` the Windows zip, eight checks each (docs/release.md); 0.1.0 published on GitHub with both archives; last staged 0.1.0-bc0a86a on the Mac and e4f1fb7 on the rig (2026-10-15) |
| The harness | the headless suite (18 scenes, about 25 s), the window suites (7 scenes, about 5 minutes a path), the HUD check, the enhancements' checks, the sweep, the scorecard and the fidelity tools; on the rig under Git Bash (the ConPTY runner, PPSSPP 1.20.4), all but `tools/refactor_check.sh`; docs/verification.md |
| Fidelity | the M8 audit's fourteen differences fixed, explained or accepted (docs/fidelity.md); the window checks of tasks 092 to 095 and 098 PASS on the Mac (task 097, 2026-10-19) and on the rig (task 500, the same day); the scorecard's timing and trajectories lanes rerun 2026-10-19 (task 097, "The scorecard rerun"): timing close, the players faithful on 11 of 12 circuits as docs/fidelity.md says |

## Follow-ups

None blocks a milestone. One line each, the detail in the linked task file or in
[the table as it stood](history/sessions.md#follow-ups-2026-10-19).

The renderers and the GE:
- Block transfers and `read_back_framebuffer` from a rendered target, point and spot lights, specular and reversed
  normals: ported, exercised by no recording ([024](tasks/024-metal-3d.md), [025](tasks/025-metal-effects.md)).
- Texture mapping: no picture check of mode 1, reversed normals in mode 2 unsettled, the specular half-vector on world
  +z ([036](tasks/036-environment-mapping.md)).
- The dithered billboard has no PPSSPP reference at the same point of its cycle; 5551 and 4444 targets, the doubled
  factors, ABSDIFF and CLIPENABLE off are drawn but unexercised ([040](tasks/040-colour-test-dither-clamp.md)).
- Vulkan above internal scale 1: a through-mode draw that samples a target loses the tile clamp (a seam at x 638-639
  of race_warm at 2x); bilinear at a REPEAT seam; no `PURE_NO_...` switch for the wrap
  ([063](tasks/063-fb-texture-wrap.md)).
- E3's leftovers: `ge_replay --scale`; the frame write-back copies whole rows; no switch back to the Vulkan renderer's
  old target sizes; settings.hpp's `defaults_for` comment; no scripted live Resolution change; block transfers into a
  scaled target invalidate ([066](tasks/066-metal-internal-scale.md), [068](tasks/068-vulkan-effects-at-1x.md)).
- Task 062's leftovers: `snapshot_guest_words` computes its own extent, `prewarm_.path` is unread, two trace flags sit
  in `trace_` ([062](tasks/062-metal-backend-simplify.md)).
- The recordings under out/gerec/ predate texture mapping, mips, the colour test, dither and CLIPENABLE, and
  `tools/gerec/metal_check.sh` fails on fresh ones with batch/m2's code too (task 093;
  [089](tasks/089-display-rate.md)).
- The record backend does not forward patch 0017-internal-scale-by-backend's scale calls (task 095).
- A `.gerec` format 2 that seeds the targets, only if a cold replay must match its recording
  ([022](tasks/022-ge-replay.md)).
- The Vulkan swapchain and its presents hold the game thread on a missed refresh
  ([091](tasks/091-display-rate-margin.md)).

The enhancements:
- E1, not started: the confirm row and labels are the framework's first game's; no keyboard Triangle with
  `input.mouse=0`; camera and mouse rows for a second stick; no gamepad rebinding in the menu; one radial dead zone
  ([030](tasks/030-controls.md)).
- The Esc menu: the bindings list's framework labels, the Vulkan shell's Touch section on a desktop, Restore control
  defaults resets hidden rows ([064](tasks/064-menu-rows-by-capability.md)).
- E2: the movies stretch under Fill on both renderers ([086](tasks/086-metal-fill.md)).
- E4: Original chosen in a free-running race applies at the next race; a save dialog in a race runs free; the frontend
  at 60 is not audited ([072](tasks/072-sixty-fps-modes.md)).
- E5: `tools/refactor_check.sh`'s count strip since task 073; texture_check's Vulkan lane reruns on pipeline creation
  and drifts at load boundaries on the rig; no count of enhanced draws on the Vulkan perf line
  ([076](tasks/076-vulkan-texture-detail.md)).
- E6: flash_check `--race`'s lap bound is coarse; the Flashes row's place after Restore
  ([070](tasks/070-smooth-flashes.md)).
- E7: sprite_check's margin on team_select and class_select, no byte cap on the texture cache, the TEAM ship sentence
  in docs/metal-backend.md, the pack's race cells behind an option, the 40-key bar, the scaler's hairlines
  ([073](tasks/073-sprite-upscale.md), [074](tasks/074-sprite-pack.md)).
- E8: the first speed pad fires 0.1 s early at 120 (not traced); `kIdleVBlankLimit` and `sceDisplayGetFramePerSec`;
  the Vulkan Frame rate row at a game rate of 119.4; Erik's eye on the race at 120 and the menus (docs/timing.md,
  "E8").
- E8 on the rig: `--audio --shell vulkan` PASSes since task 500 (098's sink, the probe counting channel restarts
  and, since task 501, the race load's snaps apart) on a quiet machine and FAILs under other load (a quarter-second
  host stall with Chrome and the editor busy: `tools/audio_hiccups.py` names them); the storms route holds 85 to 90%
  where this one holds 100%, the sweep's live-file steering the leading candidate, a played race with `PURE_PERF=log`
  the test (task 501, "The gate"); the E8 gate must pin `PURE_DISPLAY_HZ=100`;
  drop vblanks or slow down under about 95% is a pacer call; worktree builds there lose the renderer (`SDL3_ROOT`)
  (docs/timing.md, "On the rig's 100 Hz display"; [091](tasks/091-display-rate-storms.md),
  [500](tasks/500-rig-batch.md)).
- The audio sink keeps a late producer's content and rebuilds its lead by slowing the device 1% (task 098, patch
  0031-audio-sink-late-writes, D-023); on the Mac a no-op by measurement (nothing runs late at 119.4 Hz); on the rig
  (task 500) it took the early-race dip two ways, clean or 0.45 s of silence in 84 pieces when the lead drained to
  zero, until task 501 armed the recovery from the full 2048-frame lead (five runs clean after the load); Erik's
  first marked race (2026-10-20) then showed a deficit under the 2048-frame stall floor playing 1.4 s of silence
  after a two-second dip at the race start, so task 503 lowered the floor to 256 frames (a dip of milliseconds
  keeps its content, anything larger is one click); what is left is the race load's own snap (one or two, the
  load's stalls, counted apart), the clicks of the seconds a played race runs under speed (7 of 167: the start,
  two effects-heavy stretches, the Esc menu's resume), and Erik's ear on the next race
  ([098](tasks/098-audio-sink-late-writes.md), [500](tasks/500-rig-batch.md) reading 1,
  [501](tasks/501-audio-sink-early-arming.md), [503](tasks/503-audio-sink-late-limit.md)).
- The `[audio]` line's `dropped=` in the tools' windowed runs is their unpaced menus (the producer three times
  ahead of real time, the ring trimming): 0 on every paced line and in a run paced from the start, so not a
  player's condition ([501](tasks/501-audio-sink-early-arming.md), "The gate"; [097](tasks/097-screen-batch.md),
  finding 4).

Fidelity, the game and the saves:
- The follower stalls on Sinucit, Manor Top and Karbonis and is marginal on Citta Nuova; Zone has no racing line
  ([032](tasks/032-unlock-all-and-breadth.md), [042](tasks/042-prewarm-list-and-bundle.md),
  [018](tasks/018-campaign-modes.md)).
- The weather tracks cannot be compared frame to frame with PPSSPP: the mist's phase follows the menu timing
  ([038](tasks/038-surface-brightness.md)).
- The SAS reverb's two constants are fitted to PPSSPP's output ([043](tasks/043-sas-reverb.md); docs/fidelity.md,
  "Open").
- The boot's loading screen follows host time, so log-heavy runs do not repeat
  ([049](tasks/049-metal-backend-split.md)).
- Saves: a plain save from before task 045 exports plain until re-saved; mode 5's padding is unchecked; the profile's
  heap pointers sit 0x200 above PPSSPP's ([045](tasks/045-savedata-no-key-mode.md)).
- The save list: SAVE opens on the first free slot, LISTSAVE on a full stick cancels headless, the look is not the
  PSP's dialog ([039](tasks/039-save-list.md)).
- DLC: a pack-aware profile's load without the packs is untried; PROFILE > DELETE may list the packs; no PPSSPP
  reference with packs; the EU and JP packs later ([077](tasks/077-download-packs.md),
  [078](tasks/078-download-packs-menu.md)).
- The scorecard: coverage reads the 2026-10-06 matrix, functions entered are not measured, the stretch row rests on
  one race a side and swings 1 to 4 stretches (faithful to differs) run to run, idle machine or not (2026-10-19,
  [097](tasks/097-screen-batch.md); [044](tasks/044-accuracy-scorecard.md)).

The tools:
- `tools/ppsspp/ppdmp.py tex` decodes direct-colour VRAM textures only; the CLUT decoder of 2026-10-10 waits to be
  folded in ([the crowd](history/sessions.md#follow-ups-2026-10-19)).
- The PPSSPP session block is written four times ([050](tasks/050-tools-shared-runner.md)); `tools/patches.sh export`
  numbers by order, not topic ([052](tasks/052-patch-series-by-topic.md)).
- `tools/save_roundtrip.sh` has no headless option; `pp_lines.py --pad` holds at the end
  ([044](tasks/044-accuracy-scorecard.md)); `tools/frame_regress.sh` wants a wait while another game runs
  ([069](tasks/069-paced-from-the-scene.md)).
- A windowed suite baseline sturdier than "to the digit": zone_change swings 0.025 to 0.108 a run
  ([077](tasks/077-vulkan-readback-stutter.md)); a host-side asynchronous logger, so a sweep's stdout never stalls the
  game thread (vendor; [078](tasks/078-vulkan-effect-slowdowns.md)).
- The audit's tools findings (the copied readers, the stutter check's window guard, the `ln -s` sticks): task 093.

The app:
- Info.plist says "MIT License" and the setup screen names the PlayStation 3 release; the bundle is marked for macOS
  13.0 but has run on macOS 15 only ([029](tasks/029-app-bundle.md)).

By hand on the rig (Erik; docs/windows.md): the Explorer icon and Properties (task 071), the folder buttons (patch
0029-windows-file-url), the Flashes race with the overlay, Texture detail by eye, a race at the Display rate, the
twelve packs copied for `tools/dlc_check.sh`.

## Branches

`main` = 76350b5 (2026-10-19: the audit's cleanup, the screen batch). `batch/m2` is the integration branch,
`main` plus the rig's sink tasks 500 to 503; every task branches from it (`git switch -c task/NNN-slug batch/m2`).
Remotes: `origin`, Erik's private GitLab, and `github`, the public repository (https://github.com/erreib/pure-recomp;
`v0.1.0` is there). Only Erik pushes.

## The gate

The worker runs the brief's Verify and keeps its logs under out/; the planning session reads them and reruns only what
the merge can change (`tools/verify_task.sh NNN` from the main checkout), then spot-reads and `git merge --no-ff` into
`batch/m2` and removes the worktree (docs/approach.md, rule 3). `tools/frame_regress.sh` (headless, about 25 s) after
any change; both window paths and `tools/hud_check.sh` before merging a renderer or shell change (docs/verification.md,
"Which path for which change"), run in one batch when Erik books the screen (rule 4); `python3 tools/docs_check.py`
after a change that moves or renames a file, a tool or a patch.

## Open calls for Erik

- A finer virtual-time answer than the kernel's 1 ms starvation tick ([046](tasks/046-ai-seed-and-contact.md), a
  kernel patch).
- The vblank-timed present's 5.5 ms of latency, to judge by playing (`PURE_METAL_PACE=0`;
  [033](tasks/033-frame-time-dips.md)).
- Recorded laps of Sinucit, Manor Top and Karbonis (`tools/record_lap.sh`) to replace the follower there.
- Offering the upstream candidates (docs/upstream.md): on hold until more is known (the audit, Erik's call).
- The 100 Hz race at the Display rate: drop vblanks or slow down (a pacer design for docs/decisions.md).
- D-012's own save format when the expanded version starts.

## Next

- The audit's cleanup (docs/history/audit-2026-10-19.md): 092 docs, 093 src, 094 tools and 095 patches (29 now)
  merged 2026-10-19, and the doc lines 094 and 095 owed applied the same day. The screen batch (task 097) ran on the Mac
  2026-10-19: every row PASS, the gerec recordings fresh, one tool defect found and fixed (the sound probe was void
  under bash 3.2 since task 094). The scorecard's timing and trajectories lanes reran the same day: no new finding.
  The rig's batch (task 500) ran the same day: every row PASS, the sound probe PASS at 100 Hz once channel restarts
  are counted apart and the machine is quiet. Task 501 (the same day, merged) armed the sink's recovery from the
  full lead, and the probe now counts the race load's snaps apart; `dropped=` turned out to be the harness's unpaced
  menus. batch/m2 is ready for `main` when Erik says so. Next: Erik's ear on a played race at Display with the trace
  (docs/windows.md, "Open on the rig"; F8 or a stick click marks the log as a hiccup is heard, patch 0032-trace-marks
  of task 502; `tools/audio_hiccups.py` reads it). His first marked race (2026-10-20) answered the speed
  question (a played race keeps real time: 7 of 167 seconds under 95%, so the storms verdict is the harness's)
  and found the late rule's hole, closed by task 503 (the stall floor 2048 to 256 frames). His second race on it:
  "almost perfect", one tiny stutter at the intro camera (the race's one second under 95%: three clicks, 48 ms,
  at 80% speed), nothing else in 160 seconds, two short Esc menus clean. What is left for the sound at 100 Hz is
  the pacer's question (Open calls): the seconds the race cannot keep real time. His third start, traced
  (503, "The intro camera's second, traced"): one 22 ms snap he did not hear; the second is three costs, the
  game's own track streaming in 30 to 47 ms frames (the kernel does not preempt), one 32 ms first-use render
  frame, and GPU fence waits at 3440x1440. Next, in order: task 504 (a lead switch, Erik's ear at 93 ms, then a
  prewarm of the first-use uploads at the load; briefed in 503), a long Esc menu's resume traced on this sink
  (the first race's 2.6 s menu snapped twice on resume). The Mac's probe on both shells at the merge (2026-10-20):
  PASS, unchanged, 0 resyncs and 0 seconds under 95% on each, `lates=0` (098, "The Mac's probe at the merge").
- Menu refinements: Erik's to name.
- The HD texture pack (Erik, 2026-10-14; picked 2026-10-20, D-024): tasks 099 and 100 merged 2026-10-20. The
  build downloads zstd 1.5.7 once (cmake/Zstd.cmake, the SHA-256 pinned) and compiles its decoder; patch
  0033-zim-textures reads ZIM images in the loader's `decode`; patch 0034-texture-pack-host lets the menu's pack
  rows and the import screen ask whatever draws packs, and src/gpu/metal_texture_pack.mm is the Metal backend's
  loader (upload with mips, a 1 GB budget, the Vulkan renderer's trace lines). `tools/sprite_pack.sh --pack DIR`
  PASSes on the HD pack in both windows (the race route: 182 keys found, 127 images uploaded, 594 to 599 MB on
  the GPU at the peak; the menus: 11; 54 files the ini names are not in the reupload); the race holds 60 fps on
  Metal with the pack. The README tells a player how to fetch and import it. Owed: Erik's eye on the import screen
  under Metal (the row should read "4170 textures") and on the deeper menus; the rig's build with the decoder and
  the same check with the pack copied there (Vulkan on Windows). Both bundles ship `licenses/Zstandard-LICENSE.txt`
  (the macOS app repacked and looked at; the Windows copy line is the rig's to prove). Follow-up: the framework's
  SOURCE_PROVENANCE row with the upstream request. The pack is derived art: never in this repository or an
  archive; a player imports it through the menu.
  Then, Erik's call of 2026-10-20: once the pack's menus draw on both renderers and look better than the sprite
  upscale (he expects they do), retire E7's upscale: the Text and sprites row, src/gpu/sprite_upscale.*, the
  upscale path in metal_textures.mm, `PURE_SPRITE_UPSCALE` and `PURE_SPRITE_DUMP`, tools/sprite_check.sh, the pack
  build of tools/sprite_pack.sh (its `--pack DIR` check stays as the texture pack check, renamed), the sections of
  docs/metal-backend.md and the fidelity rows; D-018 superseded. Conditions before the task is briefed: the pack
  covers the menus a player sees (the 2549 files its ini names but lacks leave some at the original art), and a
  player without a pack keeps the original art, as the row's default already gives since 2026-10-12.
- 3D crowd and people models (Erik, 2026-10-20; picked the same day). The survey (task 101, merged 2026-10-20;
  docs/research.md "The crowd, surveyed") found: the crowd is four triangle-strip draws a frame, about 205 vertical
  quads 2.2 to 2.5 units tall (the road is 41 units wide, a ship 10.5 long) standing on two 146-unit grandstands
  either side of the start straight, each quad one row of a 64x64 4-bit sheet of about 56 figures (the HD pack's
  crowd.zim: the same figures as photographs at 256x256); fixed in the world, not billboards; alpha test GREATER
  0x7F, no blending, fog on, depth written, in the opaque pass; a 64x64 `crowd_background` on the tiers behind
  (no HD file in the reupload); a `camera_flash` quad blended additively in the translucent pass. The Time Trial
  figure is the pit marshal: six single quads 2 units tall on the start line's booths, facing the oncoming race,
  32x64 (HD 128x256). The tool: `PureNative --replay FILE.gerec --extract FRAME --out DIR [--keys K,...]` writes
  the frame as an OBJ scene in the track's frame (y up, one world scale) with a material per draw, the textures
  as PNGs named by the pack's keys and a JSON of every draw's state and bounds; `tools/zim_to_png.py` shows a
  pack's image. D-025 (2026-10-20) settles the substitution: a `models` GE backend of ours wrapping the platform's, which
  recognises a draw by its texture's pack key and submits model draws (vertex colours, no texture, the quad's
  fog, depth, stencil and tint) in place of each quad; models are Erik's Blender work exported as glTF with vertex
  colours and converted by the importer task 102 adds to `.pmdl` under models/, shipped in the app's resources; the
  row is "Crowds and people", Original or Models. Task 102 (merged 2026-10-20) built all of it for the pit
  marshal: the wrapper changes nothing at Original (the 18 scenes match at tol 0), at Models the six marshals
  stand on the booths as a placeholder figure, facing the race (the side first seen, remembered by place: the
  review's rule), on both renderers in the window and headless. The marshal model arrived 2026-10-20 from Astra's
  Blender scripts (tools/model_pitguy.py builds the figure, 1986 triangles, a dark quilted suit, helmet and amber
  visor; tools/model_pitguy_rig.py rigs it with 20 bones and a four-second Wave_On clip, out/pitguy-rigged/); its
  rest pose is models/pitguy.pmdl through `tools/model_import.py`, seen on the booths at 4x. Task 103 (merged 2026-10-20): `.pmdl` version 2 carries joints,
  weights and clips, the importer writes it from the rigged GLB, and the models backend skins each figure on the
  CPU (about 70 to 130 us a frame for six) on wall time with a phase per figure (`PURE_MODELS_CLOCK=frames` and
  `PURE_MODELS_SYNC=1` for captures); the marshals wave on both renderers, the check sees the arm move and the
  feet stay. Astra's tools/model_crowd.py built eight casual spectators (337 to 349 triangles each,
  out/crowd-starter). Task 104 (merged 2026-10-20), the crowd: a set syntax in models.ini maps the nine crowd keys to Astra's eight
  spectators (models/crowd/), figures along each quad at a spacing of 0.85 units picked by a hash of the place
  with a yaw and height jitter, every figure within 80 units of the eye, every second to 200, every fourth beyond,
  batched into draws of up to 65535 vertices; a quad's front is its winding normal (the marshals face the race,
  both stands the road, in the captures); the check's crowd row PASSes. On Vineta K's race start that is about
  1360 figures and 430 k vertices a frame: the Vulkan shell holds 60 fps (render 7 ms at 960x544), the Metal
  window drops to 39 to 56 fps for the 12 seconds the stands are in view, because the Metal backend de-indexes and
  uploads every draw's vertices each frame (about 66 MB a frame). Task 105 (briefed, dispatched 2026-10-20): the models backend keeps its
  static batches across frames with a stable id and a version, and the Metal backend caches the expanded vertex
  buffer of such a batch, so a frame with the crowd costs the marshals' skinning and a few bound buffers; then
  the row's default to Models. Owed to the Vulkan shell: its frame interpolation with batches whose counts change.
- Photo mode during races (Erik, 2026-10-20; not scheduled): pause a race (the Esc menu already holds the guest),
  move a free camera around the frozen scene, hide the HUD, and save a capture at a chosen resolution. Nothing
  looked at yet. The shape it would take in this port: the game's frame is a GE display list the backends already
  record and replay (docs/ge-backend.md, the record backend and `ge_replay`), and the PSP keeps the view matrix
  apart from the model and projection matrices in GE state, so the last list can be drawn again with the view
  replaced and the through-mode (2D, HUD) draws left out, at the internal scale of the player's choice, through the
  existing capture path. The first task is a spike on the Metal backend: replay the paused frame's list with a
  substituted view matrix and no HUD, and say what breaks (objects the game culled from the original camera are
  simply absent; the bloom and billboard passes read targets drawn with the old view; the sky). Then the camera's
  controls in the Esc menu's shape, the capture row, and the Vulkan path. A capture is the player's own, never in
  this repository.
- 3D backgrounds in place of the 2D skies (Erik, 2026-10-20; not scheduled): each track's sky is a cube of flat
  images the game draws in the opaque world (docs/ge-effects.md: the sky cube's faces end the opaque pass, just
  before the GE SIGNAL at which the game reads the depth buffer for the sun block, which samples the sky's depth);
  drawn instead as a model or a layered scene (a dome, clouds with parallax, the horizon's buildings in depth) that
  moves with the camera. Nothing looked at yet. The first task is a survey on the race routes: the sky cube's draws
  on each track (the textures, the matrices, what depth they write and what the sun block's read-back needs of it),
  what a substitution hook keys on (the sky
  texture's hash, as the texture pack keys do), how the camera's orientation reaches the backend (the view matrix
  in GE state), and whether the bloom and billboard passes read the sky. Then a scene format of our own for a sky
  (made for this port, never the game's or another game's bytes; the HD pack's sky image is a pack's, drawn by the
  loader, not this), one track on Metal with an Esc-menu row and Original one choice away, then the rest and the
  Vulkan path, each with a check counting substituted sky draws on the race route. Shares the survey and the hook
  with the crowd models above: the two are one substitution mechanism keyed by texture, so the survey task covers
  both.
- E1, the controls; the VR spike (task 088, on the rig); the candidates named after E7: the frontend at 60 fps and the
  menu-XML spike (new in-game options).
