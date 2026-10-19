# 094: The checks' shared code, and three harness defects

Milestone: cleanup (audit 2026-10-19) | Branch: task/094-tools-shared | Status: OPEN

## Goal
Each log format is parsed in one place, each piece of setup is written once, and three defects in the harness are
fixed. The audit (docs/history/audit-2026-10-19.md, "Defects" 1 to 3 and "Tools") measured about 600 lines copied
across the checks. Every check keeps its command line, its options and its verdict line; only its insides change,
and every verdict a check gives today it gives after.

## Read first (about 30K tokens)
- docs/history/audit-2026-10-19.md, "Defects" and "Tools".
- tools/purelib/port.py: `fresh_stick`, `wait_until`, `other_games`, `ENHANCEMENTS_OFF`.
- tools/fidelity_audit.py: `SWEEP_LINE_RE`, `STRETCH_MIN`, `TWO_VBLANK_US`, `scan_log`, and what they import.
- tools/display_rate_check.sh: the probe and the window guard (`held_by`, "not on screen"), and the `--race` reader.
- tools/framerate_check.sh and tools/stutter_check.sh (their Python heredocs); the other copies by grep.

## Deliverable
Defects:
1. **stutter_check's window guard.** It runs in a window and judges wall time, but a covered window runs without
   vsync and measures nothing (task 091-display-rate-margin). Give it display_rate_check's rule, shared: the run
   FAILs as "the window was not on screen" when its unpaced phase (the sweep's unpaced menus) presents more than 1.5
   times the display's refresh a second. One shared function serves both checks.
2. **The memory stick through `port.fresh_stick`** in hud_check, flash_check, framerate_check, billboard_check,
   sas_reverb_check and display_rate_check (and any other `ln -s` of EBOOT.ELF or disc.iso into a stick): under Git
   Bash `ln -s` copies the 253 MB image, where fresh_stick hard-links it.
3. **No stale recordings.** replay_check.sh and gerec/metal_check.sh reuse out/gerec/*.gerec, recorded Oct 6, before
   texture mapping, mips, the colour test, dither and CLIPENABLE entered the format, so the Metal-against-Vulkan
   replays never exercise those. A recording older than the current format (its version or its fields; read
   src/tools/ge_replay.cpp and vendor host/gpu/ge_record_format.hpp, read-only) is recorded again, not reused.
   Record afresh in this task and state what the replays now cover.

Added by the planning session during the task (2026-10-19; both found by task 093):
- **refactor_check's counts filter.** It drops the "N GPU waits (X ms) in Y s" figure only at the end of the line
  (`$`), but the Metal exit line now ends "; N textures upscaled (X ms)", so every refactor_check FAILs on counts
  while 18/18 pixels match. Drop the GPU waits wherever they stand in the line.
- **The gerec replays read the player's settings.ini.** metal_check.sh (and replay_check.sh) replay without
  PURE_DATA_DIR, so Erik's video.performance=overlay puts the overlay in the Vulkan capture and metal_check FAILs.
  Give each replay its own empty data directory under out/, as run_boot does.

Shared code (each with one definition, the copies replaced):
4. **tools/purelib/logs.py**: the sweep cell line, `STRETCH_MIN`, `TWO_VBLANK_US`, `scan_log` (moved from
   fidelity_audit, which imports them back, so the gates no longer import fidelity_audit and campaign_sweep), and
   readers for the `[pure] display rate`, `[perf]`, `[stalls]`, `[slow-frame]`, `[audio]` and flip-time lines, with
   the race-clock regexes display_rate_check defines twice and LAPS/CONTACTS/WORDS defined three times. A
   `--selftest` on synthetic lines, the window guard included.
5. **The centre-pixel reduce and `compare()`** (scale, texture, sprite, sprite_pack, aspect) as one function in
   tools/imgdiff.py or purelib.
6. **tools/lib.sh**, sourced: the build/game guard (EXE, EBOOT.ELF, disc.iso; 15 copies), the one-game wait (three
   styles today: make it one, a bounded wait), the shell/backend argument block (11 copies).
7. **`tools/frame_regress.sh --wait`**: waits for the other game instead of refusing; the five retry loops around a
   refused frame_regress go.
8. **save_roundtrip.sh headless**: its windows were for input scripts needing the renderer's pad, untrue since task
   026 (save_interchange runs the same routes headless). Fix its header too (it says three windowed runs; it does
   five).
9. **gerec/metal_check.sh uses replay_check.sh's record and replay** instead of its own copy.
10. Script headers stay each check's specification (docs/approach.md rule 8): update them where behaviour or setup
    moved. **No docs/ edits**: another task is restructuring docs/ now; list in the Result each doc line that must
    change, and the planning session applies them.

## Acceptance criteria
- [ ] Before and after: each check in Verify run on batch/m2's tools first and on yours after, the verdict lines and
      summary figures compared; any figure that moves is explained (timing noise named as such) in a Result table.
- [ ] `python3 tools/purelib/logs.py --selftest` PASS (in Verify).
- [ ] The gerec replays record afresh and pass; the Result says which GE features they now exercise.
- [ ] Lines removed and added, per item, in the Result.
- [ ] No change outside tools/ and this task file; game/ms0 untouched.

## Verify
`python3 tools/purelib/logs.py --selftest && tools/frame_regress.sh && tools/framerate_check.sh && tools/display_rate_check.sh && tools/display_rate_check.sh --race && tools/flash_check.sh && tools/billboard_check.sh && tools/texture_check.sh && tools/sprite_check.sh && tools/scale_check.sh && tools/refactor_check.sh && tools/save_roundtrip.sh && tools/gerec/replay_check.sh && tools/gerec/metal_check.sh`

If one of these opens a game window by default (it should not), take it out of your run, say so, and list it below.

## Window checks (not run by the worker; listed for the planning session's screen batch)
`tools/stutter_check.sh`, `tools/stutter_check.sh --shell vulkan`, `tools/display_rate_check.sh --audio` (both
shells), `tools/hud_check.sh`, `tools/menu_check.sh` (both shells), `tools/aspect_check.sh` (both shells),
`tools/overlay_check.sh`, and any other check whose setup you changed and that runs a window.

## Running beside other work
Another worker (task 093) builds and runs headless checks in its own worktree, and the scorecard may still be
running. One game at a time: before each check wait until no PureNative runs (`pgrep -x PureNative`, a bounded wait
of 30 minutes, checking every 30 s); if a check refuses because another game started, wait and rerun it.

## May touch
- tools/ (except tools/docs_check.py), docs/tasks/094-tools-shared.md

## Must not touch
- src/, vendor/, patches/, config/, docs/ (other than this file), CMakeLists.txt, generated/, game/ (above all
  game/ms0), disc/, ref/; tools/regen.sh, tools/build.sh all; no window run

## Estimated turns
70

## Escalate when
- A check's verdict or a figure it bounds changes and the cause is not this task's mistake.
- A copy turns out to differ in a way a check depends on (keep both, say how they differ).

## Result
Status: DONE. Every item and both added defects are in. What needs a window was not run (listed below): the gerec
recordings and replays, stutter_check's guard on a live run, and save_roundtrip's runs 4 and 5. Item 8 went only
part way, and the reason is under Open questions.

Changed (tools/ and this file only; 14 commits on task/094-tools-shared, d9d7032..HEAD):
- tools/purelib/logs.py: the checks' readers, each defined once: `SWEEP_LINE_RE`, `LAPS_RE`, `CONTACTS_RE`,
  `WORDS_RE`, `sweep_result`, `race_cell`, `flip_log`, `flip_median_ms`, `flips_per_second`, `DISPLAY_*` and
  `display_margin` (display_rate_check had two copies of these), `perf`, `stalls`, `slow_frame`, `audio_resyncs`, and
  the window guard (`window_guard`, `window_shown`, `SCREEN_HELD`). `scan_log` moved here from fidelity_audit with
  `STRETCH_MIN`, `TWO_VBLANK_US` and the regexes it uses, and fidelity_audit imports them back, so the scorecard's
  `fa.*` still works. Also `--selftest`. purelib/__init__.py now describes it.
- tools/lib.sh (new, sourced): `need_game`, `wait_game TOOL [S]`, `window_shell`, `pick_backend`, `fresh_stick`.
- framerate_check, display_rate_check, flash_check and stutter_check read their logs through purelib.logs and take
  their setup from lib.sh. None of them imports fidelity_audit any more.
- stutter_check (defect 1): it now FAILs as "the window was not on screen" when the sweep's unpaced menus present more
  than 1.5 x the display's refresh. The refresh comes from the `[perf]` lines' `NHz`, or from E8's race line when
  PURE_DISPLAY_RATE=1. The rule is the same function display_rate_check --audio uses, for both its probe and its run.
- Memory sticks (defect 2): every stick is built by `fresh_stick` (hard links on Windows). Converted: framerate,
  flash, display_rate, hud, billboard, sas_reverb, save_interchange, frame_regress, save_roundtrip, replay_check and
  metal_check. No `ln -s` into a stick is left.
- gerec (defect 3): `gerec_dump.py --current` reports a recording's first frame and scale, or why it is stale (format
  version, or Draws that end before the texture map, the mip levels or the colour test, dithering and CLIPENABLE).
  replay_check's `record NAME ROUTE AT FRAMES [SCALE]` keeps a recording only if it is current and holds those frames
  and scale; otherwise it records it again. replay_check.sh can now be sourced, and metal_check.sh sources it for its
  setup, `record()`, `replay()` and `verdict()` (item 9).
- imgdiff.py: `reduce_centres` and `compare_files` (with selftest cases) replace the copies in scale_check,
  texture_check, sprite_check, sprite_pack and aspect_check.
- frame_regress.sh `--wait [SECONDS]` (item 7). The retry loops in texture, sprite, scale, refactor and aspect_check,
  overlay_check's refusal handling and sprite_pack's `guarded` loop now pass `--wait`. sas_reverb_check waits
  (bounded) where it used to refuse. menu_check takes its guard, shell check and wait from lib.sh.
- save_roundtrip.sh: runs 1 to 3 are headless (port's DRAWING), runs 4 and 5 stay in the window, `--headless` runs
  1 to 3 only, and the header is fixed (five runs).
- Added defect 1, refactor_check: the counts filter now drops the GPU waits wherever they sit in the line, together
  with the upscale's time.
- Added defect 2, the gerec replays: each `replay()` gets an empty `out/gerec/data/<log name>` as PURE_DATA_DIR
  unless the environment names one.
- run_boot.py no longer re-exports `other_games`, which nothing used any more.

Before and after (batch/m2's tools in a scratch worktree at d9d7032, then this branch, same build, headless, one game
at a time). Before running them, I also ran every changed summary heredoc, old and new code, on the same outputs:
batch/m2's runs plus the main checkout's older framerate --race, flash --race, display_rate race (a FAIL) and audio
runs. Every pair printed identical text.

| Check | Before | After | What moved |
|---|---|---|---|
| frame_regress | PASS 18/18 | PASS 18/18 | nothing |
| framerate_check | PASS 33.4/33.4, 33.4/16.7 ms, 29.97/59.94 | same | nothing |
| display_rate_check | PASS 29.84/29.84, 59.96/119.41, fade 1.90/1.89 s x1.98 | same | nothing |
| display_rate_check --race | PASS 59.95/119.42, clock 1.0002/1.0011, contacts a lap 15.0/14.3, mean lap 59.47/58.50 | PASS 59.95/119.42, clock 1.0002/1.0011, contacts 13.3/15.0, mean lap 60.87/58.23 | Laps and contacts only (PSP first lap 61.7 then 67.6 s). This is run-to-run noise from the follower, which steers closed loop in a paced race (the header says its laps vary 9% between runs). The bounded figures, the start bins and the pad are unchanged, and both summaries print the same text on the same outputs. |
| flash_check | PASS fade 57 off, 0 on | same | nothing |
| billboard_check | PASS vertical 18.70 | same | nothing |
| texture_check | PASS | PASS | nothing |
| sprite_check | PASS | PASS | main_menu upscale time 71.3 vs 90.2 ms (wall-time noise) |
| scale_check | PASS (2m 10s) | PASS (0m 51s) | Wall time only: before, it waited 80 s for task 093's game. |
| refactor_check | FAIL: 18/18 pixels, counts FAIL | PASS: 18/18, counts PASS | The added refactor_check defect: the GPU-wait counts differed on all 7 routes. After = this branch's capture against batch/m2's before-captures. |
| save_roundtrip | not run (windowed) | `--headless` PASS runs 1-3, 8 s | Runs 4-5 need the window (see Open questions). |
| sas_reverb_check (extra) | PASS | PASS | nothing |
| hud_check --shell headless (extra) | 61/61 | 61/61 | nothing |
| save_interchange --port-only (extra) | not run | port side passes (exit 3 by design) | |

stutter_check on the main checkout's old runs, rescored through the new summary. Oct 14 metal-metal: its unpaced
menus presented [1771.4, 404.5] a second against a 120 Hz display, so it was PASS and is now FAIL "the window was not
on screen in its unpaced menus". It had been a PASS that measured nothing. Oct 13 vulkan-vulkan presented [109.1,
117.0, 111.1] and stays PASS.

What the gerec replays now exercise: they were not run, because recording and the Vulkan replays need a window.
- All six Oct 6 recordings report via `--current` that "its Draw records end before the texture map state (task
  036), and the parts after it", so the first run of either check records them again.
- A headless probe recorded the same routes and frames with Metal inside the record backend
  (out/094/gerec-probe, not out/gerec). The draw streams match the Oct 6 files draw for draw (8039, 132, 22, 56).
- In race frames 6008-6016 (race_warm, which covers race and race_1x), the new records carry 1260 texture-mapped
  draws (environment map or texture matrix), 5881 mipmapped, 28 colour-tested and 835 dithered, plus CLIPENABLE on
  all 7940 transformed draws. The Oct 6 race_warm had none of these.
- team (5650-5651), frontend (690-691) and title (1750-1751) contain none of the first four. Their new content is
  CLIPENABLE on every transformed draw (130, 18 and 54).
- The sourced `record()` (keeping a current file) and `replay()` (into null, with its own empty data directory) were
  exercised headless.

Lines added and removed, per item. Total across 27 files in tools/: +1178/-1088. Of the additions, 171 are scan_log
moved out of fidelity_audit (-168 there) and 157 are the two new selftests.
| Item | Added / removed |
|---|---|
| 1 stutter guard | stutter_check +39/-54; window_guard and window_shown are 52 of logs.py's lines |
| 2 fresh_stick | billboard +7/-17, hud +5/-10, sas_reverb +6/-14, save_interchange +5/-7, menu_check +4/-12 (with guard and wait); the other sticks are in the rows below |
| 3 stale recordings | gerec_dump +59/-1, replay_check +59/-32 |
| 4 purelib/logs.py | logs.py +586/-1 (readers 208, guard 52, moved scan_log 171, selftest 142); fidelity_audit +5/-168; display_rate_check +58/-221, framerate_check +14/-85, flash_check +23/-57 (these three include their lib.sh and stick changes); purelib/__init__ +4/-1 |
| 5 reduce and compare | imgdiff +49; scale_check +8/-29, sprite_check +7/-28, texture_check +8/-30, sprite_pack +9/-25, aspect_check +1/-2 |
| 6 tools/lib.sh | +59, used by 14 scripts |
| 7 frame_regress --wait | frame_regress +23/-29 (header rewrap +7/-7 on top); texture +10/-21, sprite +11/-21, scale +9/-20, refactor +10/-20, aspect +3/-11, overlay +4/-6, sprite_pack +14/-24 |
| 8 save_roundtrip | +47/-22 |
| 9 metal_check | +14/-111 |
| added: refactor_check counts | +5/-2 |
| added: replay data dir | replay_check +13/-5 |
| run_boot re-export | +1/-3 |

Window checks for the planning session's screen batch (not run here):
- `tools/gerec/replay_check.sh` and `tools/gerec/metal_check.sh`. They are in the Verify line, but they record in the
  Vulkan shell and replay into Vulkan windows, so I took them out of my run. Their first run records afresh, about 15
  minutes.
- `tools/save_roundtrip.sh`: by default its runs 4 and 5 run in the window. My Verify ran `--headless` instead.
- `tools/stutter_check.sh` and `--shell vulkan`: the guard on a live run.
- `tools/display_rate_check.sh --audio` on both shells.
- `tools/hud_check.sh`, `tools/menu_check.sh` on both shells, `tools/aspect_check.sh` on both shells, and
  `tools/overlay_check.sh`.
- `tools/texture_check.sh --shell vulkan` and `tools/sprite_pack.sh --check` (frame_regress --wait in a window).

Verify output: the brief's line with the window checks taken out, logs selftest first and `save_roundtrip.sh
--headless` in place of `save_roundtrip.sh`. Each check was run alone after waiting for no PureNative:
```
10:15:20 end python3 tools/purelib/logs.py --selftest rc=0 0 s: logs selftest: PASS
10:15:43 end tools/frame_regress.sh rc=0 23 s: frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 22s)
10:15:56 end tools/framerate_check.sh rc=0 13 s: framerate_check: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms and 29.97/59.94 flips a second, off/on; the HUD drawn at 60)
10:16:14 end tools/display_rate_check.sh rc=0 18 s: display_rate_check: PASS (frontend 29.84/29.84 and race 59.96/119.41 flips a second, PSP/120; the margin 0.005 at 120 (116.40 to 122.40); fade 1.90 and 1.89 s (-0.5%), 57 and 113 flips (x1.98); the HUD drawn at both)
10:22:36 end tools/display_rate_check.sh --race rc=0 382 s: display_rate_check: PASS (race: 59.95 and 119.42 flips a race-clock second, the margin 0.005 at 120 Hz (8375 us a vblank, 116.40 to 122.40); game clock 1.0002 and 1.0011; ...)
10:22:49 end tools/flash_check.sh rc=0 13 s: flash_check: PASS (fade 57 flips off, 0 on; the race and its HUD in both)
10:22:56 end tools/billboard_check.sh rc=0 7 s: billboard_check: PASS, vertical 18.70 against the threshold 8
10:23:39 end tools/texture_check.sh rc=0 43 s: texture_check: PASS
10:24:20 end tools/sprite_check.sh rc=0 41 s: sprite_check: PASS
10:25:12 end tools/scale_check.sh rc=0 52 s: scale check: PASS, scale 4: 18/18 scenes within 5% at tol 24, 3/3 bloom regions within 10% (0m 51s)
10:25:36 end tools/refactor_check.sh rc=0 24 s: refactor check: PASS, 18/18 scenes with 0 differing pixels, counts PASS (0m 24s)
10:25:44 end tools/save_roundtrip.sh --headless rc=0 8 s: save round trip: PASS (runs 1 to 3, --headless)
python3 tools/imgdiff.py --selftest: PASS selftest (0.21 s)
```

Open questions:
- Item 8's premise holds only for runs 1 to 3. Runs 4 and 5 (task 039) choose in the save list, which is the host's
  interface and opens only in a window. Headless, the framework answers LISTSAVE and LISTLOAD itself (the first free
  slot, the newest save), so their list checks cannot hold; tried headless, they gave 4 FAILs. I kept them in the
  window rather than drop the check's coverage. The default run is about 3 minutes instead of 13, and `--headless`
  covers runs 1 to 3 in 8 s. Should Verify lines use `--headless`, and should runs 4 and 5 move to the window batch
  for good?
- refactor_check had been FAILing on every run since the exit line gained "; N textures upscaled", the same finding
  as task 093's. Its verdict moves from FAIL to PASS because of that fix only; the pixels were 18/18 identical in
  both.
- hud_check keeps its own shell block, because its `--backend` takes any backend name. aspect_check (its lanes) and
  texture_check (`--shell headless|vulkan`) keep theirs too.
- record() checks the frames, the scale and the format, but not the inner backend. A recording made with Metal inside
  (like the headless probe) placed in out/gerec would be reused.
- Doc lines that must change (no docs/ edits made):
  - docs/developing.md:50 (frame_regress): add `--wait`.
  - docs/developing.md:54 and verification.md:13 (stutter): add the window guard.
  - docs/developing.md:58-60 and the scale, refactor, aspect and overlay rows (`--wait`): it is now passed to
    `frame_regress.sh --wait`.
  - docs/developing.md:72 and verification.md:488, 503 (sas_reverb): it waits up to 600 s instead of refusing.
  - save_roundtrip lines (developing.md:73, savedata.md:232, setup.md:121, verification.md:278, 613-614): runs 1-3
    headless, runs 4-5 in the window, `--headless`, about 3 minutes.
  - developing.md tool list: add tools/lib.sh and `purelib/logs.py --selftest`.
  - verification.md:100, 205-206, 311-314: frame_regress `--wait`; run_boot.py no longer has `other_games`.
  - verification.md:756 (purelib.logs row): the new readers, the guard, scan_log, its users and the selftest.
  - ge-backend.md:290-293 and metal-backend.md:1485-1488: recordings are also redone when stale (`--current`);
    metal_check sources replay_check; each replay gets its own empty data directory and the enhancements pinned off.
  - metal-backend.md:95, 409, 737, 821, 886: the centre-pixel reduce is imgdiff's `reduce_centres`.
  - The refactor_check counts passage in verification.md: the GPU waits are dropped wherever they stand.

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
