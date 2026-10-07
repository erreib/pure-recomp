# 042: The pre-warm list covers the campaign, and the app bundle carries it

Milestone: M8 | Branch: task/042-prewarm-list-and-bundle | Status: MERGED (823c6c4, 2026-10-07)

## Goal
Two follow-ups of tasks 033, 040 and 041. `config/metal_pipelines.txt` lists only the pipelines of the Vineta K
Single Race cell, and since task 040 it also lacks the 16-bit and colour-test keys: task 041 counted nine render
pipelines every 30-fps run still makes by a draw (six at the race load, two or three in the race), 243 ms on a cold
shader cache, the one hitch a player could meet. And the app bundle does not carry the list at all, so the installed
app makes every pipeline on first use. This task refreshes the list over the campaign, ships it in the bundle, and
rebuilds the bundle from the current tree (the one in out/release-macos predates tasks 036 to 041).

## Read first
- CLAUDE.md, docs/metal-backend.md ("The pre-warm list": the refresh recipe; "Frame times"), docs/tasks/033 (Result),
  docs/tasks/041 (Result: the nine pipelines, the runs that made them), docs/release.md and docs/tasks/029 (the
  packer, `RELEASE_RESOURCES` in packaging/release.env: folders of the build's bin directory shipped into
  `Contents/Resources`), tools/bundle.sh (the `--check` runs), docs/tasks/034 (Result: scratch data directories,
  silent runs; the follow-up that `--check`'s runs are not silenced)
- src/gpu/metal_backend.mm near "metal_pipelines.txt in an app's Resources" (read only: where the backend looks and
  how it parses a list, including the `color_test` and `sixteen` fields task 040 added)

## Deliverable
1. `config/metal_pipelines.txt` refreshed as the union of `PURE_METAL_PIPELINES_OUT` files from headless sweep cells
   that cover the campaign: Single Race on every circuit of one class (`--unlock-all`, `--no-damage`), Time Trial,
   Free Play and Zone on at least one track each, and a Tournament race; keep the file's header comment, updated with
   what the list now covers. Acceptance: a second run of each of Single Race Vineta K, Free Play, Time Trial and Zone
   ends with `0 not in the list` on its `[metal] pipelines:` exit line.
2. The bundle ships the list: `tools/bundle.sh` (or packaging/release.env's `RELEASE_RESOURCES`, whichever the packer
   supports without a vendor change) puts `metal_pipelines.txt` in `Contents/Resources`, where the backend looks
   first, before the app is signed; `tools/bundle.sh --check` gains a check that the packed app's run prints a
   `[metal] pre-warm:` line naming the Resources copy.
3. `tools/bundle.sh --check` runs silent and on a scratch data directory like the other tools (task 034's follow-up),
   if the packed app honours `PURE_DATA_DIR` and the mute setting; otherwise say why not.
4. The bundle rebuilt from this branch: `tools/bundle.sh` (a release build, then the packer) and `tools/bundle.sh
   --check out/042` passing, the app left at `out/release-macos/stage/Wipeout Pure.app`. Do not touch anything under
   /Applications or the player's data directory.
5. docs/metal-backend.md ("The pre-warm list": what the list covers now), docs/release.md (the Resources file), the
   README's row for `PURE_METAL_PIPELINES` if it changes.

## Acceptance criteria
- [ ] The four cells above report `0 not in the list`; `tools/frame_regress.sh --only race_hud` unchanged.
- [ ] `tools/bundle.sh --check out/042` passes, including the new pre-warm check.

## Verify
`tools/bundle.sh && tools/bundle.sh --check out/042 && tools/frame_regress.sh --only race_hud`

## May touch
- config/metal_pipelines.txt, tools/bundle.sh, packaging/, docs/metal-backend.md, docs/release.md, README.md

## Must not touch
- src/, vendor/, patches/, include/psprecomp/, tools/frame_regress.sh, tools/campaign_sweep.py, config/pad_scripts/, ref/

## Estimated turns
30

## Escalate when
The packer cannot ship a file into Contents/Resources without a change under vendor/ (report what it offers; a one-line
vendor patch is not this task's), or a cell's second run still makes pipelines by a draw after the refresh (report the
keys: they may depend on something the sweep does not reach).

## Result
Status: DONE. All five deliverables are in and the Verify line passes (`tools/verify_task.sh 042`, 2m 48s with the
packer). The list now covers the campaign: 37 render pipelines and 30 depth-stencil states, up from 26 and 28. A
second run of each acceptance cell made no pipeline by a draw. The app ships the list in `Contents/Resources`, through
the packer's own `RELEASE_RESOURCES`, so no vendor change was needed. `tools/bundle.sh --check` now runs muted on its
scratch data directory and checks the pre-warm. The app was rebuilt from this branch and is at
`out/release-macos/stage/Wipeout Pure.app` (0.1.0-bd732e0, 88 MB).

Changed (branch `task/042-prewarm-list-and-bundle`, from batch/m2 864abf3, 7 commits):
- `config/metal_pipelines.txt`: the union of the `PURE_METAL_PIPELINES_OUT` files from 16 headless, silent sweep
  cells, run one at a time (07:43 to 09:01):
  - Single Race on all twelve Vector circuits (`--unlock-all --no-damage`)
  - Time Trial and Free Play on Vineta K (`--no-damage`)
  - Zone 1
  - the Alpha Tournament's four races (`--no-damage`)
  The header comment says what the list covers.
- `packaging/release.env`: `RELEASE_RESOURCES="app_resources=."`. The packer copies that folder's contents
  (`build/release/bin/app_resources`) into `Contents/Resources` before it signs the app.
- `tools/bundle.sh`, packing:
  - copies `config/metal_pipelines.txt` into `build/release/bin/app_resources` before running the packer;
  - no longer counts a newer list as a reason to rebuild in Release, since the list is not compiled in.
- `tools/bundle.sh --check`:
  - new `prewarm` check. The Resources copy must be identical to `config/metal_pipelines.txt` (`cmp`). The route
    and finder runs must each print `[metal] pre-warm:` naming that copy (compared with `-ef`) with the copy's own
    counts. Each run's "not in the list" count is reported but does not decide the check.
  - silent: after the setup it appends `audio.mute=1` to `DIR/data/settings.ini`.
  - `finder.log` and `finder.stderr.log` are deleted before `open`. `open --stdout` appends (tested with a stub app),
    so a second check into the same DIR used to read the first check's finder log. This bug dates from task 029. It
    showed up here when the Verify run followed my own check into out/042.
- `docs/metal-backend.md`, "The pre-warm list":
  - the new counts and the app's copy;
  - the refresh recipe as it was run;
  - a table per cell of keys used and keys made by a draw;
  - which keys are new and which are gone;
  - the second runs.
  The env, file, Not changed and task 040 rows now point to these changes.
- `docs/release.md`:
  - the staging step and `RELEASE_RESOURCES`;
  - a `Resources/metal_pipelines.txt` row;
  - the `prewarm` check row;
  - how the check's runs stay silent;
  - logs started afresh;
  - task 029's setup failure marked fixed by 16718e6. It said the check still FAILed, which is no longer true.
- `README.md`: the `PURE_METAL_PIPELINES` and `tools/bundle.sh` rows.

The list's size: before, 26 render pipelines and 28 depth-stencil states (61 lines, 6771 bytes). After, 37 render
pipelines and 30 depth-stencil states (77 lines, 9567 bytes).
- All 28 old depth-stencil states and 24 of the 26 old render keys are still used.
- 2 render keys dropped out. Since task 040, the draws that made them use their colour-test or 16-bit variants.
- 13 render keys are new:
  - task 040's six (four `sixteen=1`, two `color_test=1`), made in the Alpha and Beta races;
  - three drawn only by Time Trial and Free Play. With the six, these are task 041's nine for 30-fps runs;
  - three untextured blends with source factor zero, drawn only on the Tournament's screens between races;
  - one colour-test key without the alpha test, from the Classic circuits and Zone.
- 2 depth-stencil states are new: depth compare 4 with a stencil test, from Modesto Heights, Chenghou Project,
  Citta Nuova, Sebenco Climb, Sol 2 and the Tournament.

First runs, with the old list in force:
- Every cell made 2 to 9 render pipelines by a draw: 6 in the Alpha and Beta races (5 in Sinucit's, which stalled), 9 in Time Trial, Free Play and
  the Tournament, 3 on the Classic circuits, 2 in Zone.
- Six cells also made 1 or 2 depth-stencil states by a draw.
- Thirteen cells PASSed. Sinucit (lap 2, at its fork), Karbonis (lap 3) and Manor Top (lap 1) STALLed where the
  follower leaves the track. Their race loads and laps up to the stall are still covered.

Acceptance cells, second run with the new list (`[metal] pipelines:` exit line):
- Single Race Vineta K (`--unlock-all --no-damage`), PASS, 201 s: `29 render pipelines used, 0 made by a draw (0 of
  them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0 made
  by a draw, 30 pre-warmed`
- Single Race Vineta K (`--no-damage`, task 033's cell), PASS, 197 s: `29 render pipelines used, 0 made by a draw (0
  of them waited for the pre-warm, 0 not in the list), 29 taken from the pre-warm of 37; 30 depth-stencil states, 0
  made by a draw, 30 pre-warmed`
- Time Trial Vineta K (`--no-damage`), PASS, 246 s: `32 render pipelines used, 0 made by a draw (0 of them waited for
  the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30
  pre-warmed`
- Free Play Vineta K (`--no-damage`), PASS, 222 s: `32 render pipelines used, 0 made by a draw (0 of them waited for
  the pre-warm, 0 not in the list), 32 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30
  pre-warmed`
- Zone 1, PASS, 75 s: `23 render pipelines used, 0 made by a draw (0 of them waited for the pre-warm, 0 not in the
  list), 23 taken from the pre-warm of 37; 30 depth-stencil states, 0 made by a draw, 30 pre-warmed`

The shader cache was warm, so the pre-warm took 2.2 to 5.0 ms at start and was done by frame 1.

The bundle check in the Verify run:
- bundle, machine, names, content and setup PASS. The setup copied the 252,968,960-byte image.
- route PASS: frame 2200 from `out/042/data` on the Metal shell, title 0.000237.
- finder PASS: title 0.000237.
- prewarm PASS: `route and finder pre-warmed from Contents/Resources/metal_pipelines.txt (config/metal_pipelines.txt,
  37 render pipelines, 30 depth-stencil states); route: 0 of them waited for the pre-warm, 0 not in the list;
  finder: 0 of them waited for the pre-warm, 0 not in the list`.

The route log reads `[metal] pre-warm: 37 render pipelines (made asynchronously) and 30 depth-stencil states from
.../out/release-macos/stage/Wipeout Pure.app/Contents/Resources/metal_pipelines.txt, 1.2575 ms at start`. The finder
log has the same line at 3.54 ms.

The packed app honours `PURE_DATA_DIR` and the mute setting, so deliverable 3 applies:
- `PURE_DATA_DIR`: the route check confirms that the executable and the disc image came from `DIR/data`.
- Mute: the app rewrote `DIR/data/settings.ini` in full during the runs and kept `audio.mute=1`, so it read the
  setting. `audio_sink.cpp` sets gain 0 from it, and the device opened (`Audio: 44100 Hz stereo playback open`).
- `audio.mute` has no environment variable, so the data directory is the only way to pass it through `open --env`.
- `PURE_NO_AUDIO` was not used: the device stays open, as in a player's app with Mute on.
- The setup run opens no audio device.
- `race_hud` is unchanged at 0.0149 (column 0.0148), the same as task 041's run. The list changes no pixel.

Verify output (`tools/verify_task.sh 042`, last 20 lines):
```
     11661 Wipeout Pure.app/Contents/Resources/licenses/Vulkan-Loader-LICENSE.txt
     18092 Wipeout Pure.app/Contents/Resources/licenses/Wipeout Pure-LICENSE.txt
      1389 Wipeout Pure.app/Contents/Resources/licenses/xxHash-LICENSE.txt
      9567 Wipeout Pure.app/Contents/Resources/metal_pipelines.txt
       194 Wipeout Pure.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json
    110467 Wipeout Pure.app/Contents/Resources/Wipeout Pure.icns
data directory after setup: 245M (disc.iso EBOOT.ELF ms0 settings.ini)

bundle check: PASS
frame regression 2026-10-07 09:28, commit bd732e0+changes, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aa54b45d88c51150e/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 042: PASS
```
The packer ran from a clean bd732e0. The suite's "+changes" is a docs/release.md edit I made while the suite ran,
committed as 4afd765. The release `PureNative` was built at the start of the task (37 s, mostly ccache hits). No file
compiled into it has changed on this branch.

Open questions:
1. Not covered by the sweep:
   - classes other than Vector
   - Zone 2 to 4
   - Time Trial and Free Play on tracks other than Vineta K
   - the attract demos
   - weapons the follower never fired
   - the parts of Sinucit, Karbonis and Manor Top after their stalls

   Any key these add shows in a run's exit line as "not in the list", and the documented recipe adds it.
2. Karbonis stalled this time (lap 3, the follower leaving the track at 2600 to 2760 m). docs/status.md lists only
   Sinucit and Manor Top as stalling. Worth a row there.
3. Nothing was measured on a cold shader cache. That needs task 033's throwaway shader-source build, which is under
   src/ and outside this task. The second runs were all warm. Task 033 measured 46 to 73 ms on a cold cache for 26
   pipelines, done by flip 4.
4. Running `release_macos.sh` directly, not through `tools/bundle.sh`, now fails with "no app_resources in
   build/release/bin". This is documented in docs/release.md and in release.env's comment.
5. Two rows in docs/status.md can now be closed:
   - Follow-ups row 88, the bundle lacking the list and the list lacking task 040's and task 041's keys;
   - the `tools/bundle.sh --check` part of row 85, the check not being silenced.

   docs/status.md is outside "May touch".
6. I did not compare the player's data directory before and after the check. Listing it was refused by this
   session's permissions, so nothing there was read or touched. Every run of the check names
   `PURE_DATA_DIR=out/042/data`, and the route check confirms the installed game came from there.
7. The packer's sources, deps and deps-build were copied from the main checkout's `out/release-macos`, the same pins,
   to skip the download and the SDL3 and loader build. `out/` is ignored.

## Review
Verify rerun: PASS from the main checkout after the merge (2026-10-07): `tools/verify_task.sh 042` repacked the app
from the merged tree (so it carries patch 0018 too), the bundle check passed all eight checks including the new
`prewarm` (37 render pipelines and 30 depth-stencil states from Contents/Resources, 0 not in the list on both runs),
race_hud 0.0148.

Spot-read: tools/bundle.sh (the list staged into the build's `app_resources` before the packer, so it is inside the
signature; the check's mute through the scratch settings.ini; the finder logs started afresh, a task 029 bug),
packaging/release.env (`RELEASE_RESOURCES="app_resources=."`), config/metal_pipelines.txt (77 lines, the header says
what it covers). Files outside May touch: none.

Merged: 823c6c4 into batch/m2.

Notes: not covered by the list yet: classes other than Vector, Zone 2 to 4, the 30-fps modes on tracks other than
Vineta K, the attract demos, weapons the follower never fires; any such key shows as "not in the list" on a run's exit
line and the documented recipe adds it. Nothing was measured on a cold shader cache (task 033's method, under src/).
Karbonis stalled on lap 3 this time (the follower leaving the track), a third track for the stall list. Status rows
88 and 85 closed.
