# 044: The accuracy scorecard

Milestone: M8 | Branch: task/044-accuracy-scorecard | Status: OPEN (dispatch after 042)

## Goal
One command that says how close the port is to the original, in numbers that can be re-run after every change:
pictures, trajectories, timing, audio, saves and coverage, each against PPSSPP or against the game's own facts, each
graded by a stated threshold. The PPSSPP side is taken once and cached (git-ignored, hashes in ref/README.md); the
port side is re-run headless each time. The output is docs/scorecard.md (a dated table per category with the commit
it measured) and out/scorecard/scorecard.json. Erik asked for this as the standing answer to "how accurate is the
port" before any enhancement (docs/decisions.md D-009).

## Read first
- CLAUDE.md, docs/fidelity.md (what matches; the matrix; items 3 to 6; the differences list, in particular 5 and 6,
  which stay open and must be reported as they are), docs/verification.md (the suite, re-baselining, audio_compare,
  the WAV capture), docs/tasks/007 (Result: the ship's position in PPSSPP through the driver's `memory.read` and in
  the port through `PURE_WATCH_GRID`, clock-aligned; 1.13 m over 25 s on Vineta K with Cross held), docs/tasks/035
  (Result: the matrix, `tools/fidelity_audit.py`'s cell JSONs and `ppsspp_stretches`), docs/tasks/041 (Result: the
  audio dump and `--locate`), docs/ppsspp.md, docs/tracks.md
- tools/frame_regress.sh (its summary.txt), tools/fidelity_audit.py, tools/pp_lines.py (`--pad`, the race records'
  sampling), tools/audio_compare.py, tools/save_roundtrip.sh, tools/ppsspp/ppsspp_ctl.py: all to be used as they are
  (as libraries or by their outputs), not changed
- ref/README.md (how references are listed with their hashes)

## Deliverable
1. `tools/scorecard.py [--quick | --full] [--only CATEGORY[,..]] [--refresh-references [CATEGORY]] [--out DIR]
   [--selftest]`. `--quick` (minutes) runs pictures, saves and the coverage rows that come from cached cell results;
   `--full` adds the trajectories (12 headless port runs) and the audio (port WAVs). `--refresh-references` takes
   the PPSSPP side through the driver and stores it under ref/scorecard/ (git-ignored) with each file's SHA256 added
   to ref/README.md; a run without a reference says so in the row instead of failing. `--selftest` checks every
   grader on synthetic inputs. Every row: measure, port value, reference value, the difference, and a grade
   `faithful`, `close` or `differs` by a threshold the doc states; a category's grade is its worst row.
2. The categories and their rows:
   - Pictures: the suite's 18 scenes at their tolerances (run `tools/frame_regress.sh` and read its summary) and the
     extra references of docs/fidelity.md item 3 (Blue Ridge, Sebenco Climb, Sinucit HUDs): fraction, limit, measured;
     faithful within 0.005 of the measured column, close within the limit, differs above it.
   - Trajectories: per circuit (the 12 of docs/tracks.md, Vector class, `--unlock-all`), the player's ship driven
     straight on with Cross held from the start and no steering, in PPSSPP (pp_lines.py's sampling with `--pad`) and
     in the port (`PURE_WATCH_GRID=1`): the race clock at which the player's positions first differ by more than 1 m
     and the largest distance over the first 20 s; faithful when the largest distance over 20 s is under 1.5 m, close
     under 5 m. AI ships are not compared unless they prove deterministic: check once whether two PPSSPP runs of one
     track give the same AI samples (the RTC base is pinned in the driver); if they do, add the AI rows the same way,
     and if they do not, say so in the doc and leave them out (no seed hunting in this task).
   - Timing: per mode, flips per race-clock second over the race window (60 in Single Race and Tournament, 30 in
     Time Trial, Free Play and Zone) and the count of two-vblank stretches over the Vineta K race against PPSSPP's
     (fidelity item 6's method, `ppsspp_stretches`); the race load's length in game time against PPSSPP's (difference
     6: reported as `differs` until decided, with the numbers).
   - Audio: the main menu's music over its first 60 s (deterministic): `--locate` correlation and the mean per-second
     RMS ratio; one Single Race per league (Vineta K, Sinucit, Sagarmatha): the race music's correlation, the share
     of seconds where both or neither are active, and the clipped samples on both sides. Faithful: correlation at
     or above 0.6 where the content is the same and the RMS ratio within 0.95 to 1.05; close: 0.3 and 0.9 to 1.1.
   - Saves: after `tools/save_roundtrip.sh`'s profile and PPSSPP's save of the same profile name (one reference run):
     the save directory's file names and sizes, PARAM.SFO's fields (TITLE, SAVEDATA_TITLE, SAVEDATA_DETAIL,
     CATEGORY, PARENTAL_LEVEL, SAVEDATA_FILE_LIST entries), ICON0.PNG byte for byte; the data file by size only
     (difference 5: encrypted on the PSP and in PPSSPP; reported as `differs` until decided).
   - Coverage: the matrix's 46 cells (halts, stubs hit, unsupported instructions, skipped draws: from the cell JSONs of
     a `tools/fidelity_audit.py` run; reuse `out/035-wip/fidelity` when present, else name the command to make them;
     the scorecard does not run the 3-hour matrix itself); the 278 imports by state (implemented, stubbed with a
     documented value, never called; from config/hle_coverage.csv and the matrix logs' stub lines); the GE commands
     still ignored (the distinct count from the exit lines); functions of config/function_map.csv entered during the
     matrix, if the profile or framework already offers a cheap entry count (if none exists, the row says "not
     measured" and the VFPU differential test stays task 045).
3. docs/scorecard.md written by a `--full` run on this branch (with the references refreshed), committed; its header
   explains each category's thresholds and how to refresh. docs/verification.md gains a section; README.md the tool's
   row; ref/README.md the references.

## Acceptance criteria
- [ ] `python3 tools/scorecard.py --selftest` passes; `--quick` completes in under 10 minutes on this machine and
      `--full` (references cached) in under 40; a missing reference degrades to a "no reference" row, not an error.
- [ ] docs/scorecard.md shows every row with a grade and the two open decisions (5, 6) marked as such.

## Verify
`python3 tools/scorecard.py --selftest && python3 tools/scorecard.py --quick --out out/044 && test -s out/044/scorecard.json`

## May touch
- tools/scorecard.py (new), tools/ppsspp/routes/ (routes the references need), docs/scorecard.md (new),
  docs/verification.md, README.md, ref/README.md (the references' hashes; the files themselves are git-ignored)

## Must not touch
- vendor/, patches/, src/, config/, tools/frame_regress.sh, tools/campaign_sweep.py, tools/fidelity_audit.py,
  tools/pp_lines.py, tools/audio_compare.py, tools/ppsspp/ppsspp_ctl.py, tools/save_roundtrip.sh (use them; if one
  lacks something the scorecard needs, work around it in scorecard.py and list it under Open questions)

## Estimated turns
60

## Escalate when
A measure needs a change under src/ or vendor/ (report which and why), or the straight-on run cannot be clock-aligned
on a track (report the track and what the records show).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
