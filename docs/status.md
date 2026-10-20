# Status

Last updated: 2026-10-20 (the Mac's sound probe on both shells after tasks 501 to 503 merged: PASS, unchanged). M1 to M9 done, the Windows bring-up done, the enhancements E2 to E8 and the US
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
| E7 | the frontend's resolution (D-018) | done 2026-10-11 (tasks 073, 074); Original by default since 2026-10-12 |
| E8 | the display rate (D-022) | done 2026-10-15 (tasks 089, 091-display-rate-margin); the rig's 100 Hz sound probe PASSes since 2026-10-19 (task 500), the sink's early-race shape fixed the same day (task 501); Erik's ear on a played race owed |
| DLC | the US download packs (D-005) | done 2026-10-12 (tasks 077-download-packs, 078-download-packs-menu) |
| R1 | the first public release | done 2026-10-13: v0.1.0 at f31c1be (task 087); 0.2.0 released 2026-10-20: v0.2.0 at 13ac398 (E8, the sink's late rule, patch 0029-windows-file-url; both archives and the sums on the page) |
| VR | the stereo spike (D-021) | briefed, undispatched (task 088) |
| HD pack | NR74W's HD texture pack | on the roadmap, not scheduled (Next) |
| Crowd | 3D crowd and people models in place of the track-side sprites | on the roadmap, not scheduled (Next); nothing looked at yet |
| Cleanup | the audit of 2026-10-19 | tasks 092 to 095 merged 2026-10-19, their doc lines applied (docs/history/audit-2026-10-19.md); the screen batch (task 097) ran on the Mac 2026-10-19, every row PASS; the rig's batch (task 500) the same day, every row PASS |

## Works

What runs today. The Mac is an M4 Pro with a 120 Hz display; the rig is Erik's Windows machine (i5-8600K, RTX 3080,
a 100 Hz display).

| Area | State |
|---|---|
| Toolchain | Mac: `tools/check_env.sh` (arm64 cmake and ninja, SDL3, MoltenVK, Ghidra 12.1.4, PPSSPP); the rig: clang-cl on the `win-x64` preset, Git Bash (docs/setup.md) |
| Disc and game | `tools/iso_extract.py` verifies CRC 4502C588 and extracts `disc/`; `tools/setup_game.sh` lays out `game/` |
| Vendor | PortableKit at 8b0c3fe with 31 patches by topic (`tools/patches.sh check`; patches/README.md, docs/upstream.md, docs/vendor-map.md) |
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
- The HD texture pack (Erik, 2026-10-14; not scheduled): two tasks when picked, a ZIM decoder (or a conversion to PNG
  at import) for the Vulkan renderer's loader with the pack as the test subject, then a pack loader for the Metal
  backend; each with a check counting replacements on the race and menu routes. The pack is derived art: never in this
  repository or an archive ([the roadmap entry](history/sessions.md#the-arcs-2026-10-08-to-2026-10-15)).
- 3D crowd and people models (Erik, 2026-10-20; not scheduled): the track-side spectators and figures the game
  draws as flat sprites, drawn as models instead. Nothing looked at yet. The first task is a survey, not a change:
  how the game draws them (which draws, textures and lists on the race routes; `PURE_TRACE_GE` and a .gerec), what a
  substitution hook in the two renderers would key on (the texture or the draw's signature), and where the models
  would come from (made for this port, never the game's or another game's bytes). Then one renderer, then the other,
  each with a check counting substituted draws on the race route, and an Esc-menu row with Original one choice away,
  like every enhancement.
- E1, the controls; the VR spike (task 088, on the rig); the candidates named after E7: the frontend at 60 fps and the
  menu-XML spike (new in-game options).
