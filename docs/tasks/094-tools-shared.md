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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
