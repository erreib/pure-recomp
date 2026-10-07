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
Status: DONE. `tools/scorecard.py` grades the port in six categories against PPSSPP or the game's own facts.
`--selftest` passes. `--quick` took 49 s (twice, the Verify runs). `--full` took 17 m 38 s with no time spent waiting,
and it wrote docs/scorecard.md (2026-10-07 11:57, commit db10191). The PPSSPP side is in `ref/scorecard/`
(git-ignored), with 38 files listed with their SHA-256 in `ref/scorecard/manifest.json` and in ref/README.md. Neither
escalation condition was met:
- No measure needed src/ or vendor/.
- Every circuit's straight-on run clock-aligns. The player's positions agree within 1 m until at least 5 s on all 12
  circuits; they stay within 1 m for all 20 s on seven, and within 1.5 m on eight.

On the way, batch/m2 was merged twice (D-011, then task 045 with patch 0019), and the build was redone with patch 0019,
following the coordinator's two messages. As a result:
- The race load is graded `accepted (D-011)`.
- The Saves rows compare PSP-format saves on both sides, the data file through its decrypted contents.

**Category grades (the --full run in docs/scorecard.md):**

| Category | Grade | Rows faithful / close / differs / other |
|---|---|---|
| Pictures | faithful | 21 / 0 / 0 / 0 |
| Trajectories | differs | 9 / 1 / 15 / 0 |
| Timing | faithful | 6 / 0 / 0 / 1 (the load: accepted, D-011) |
| Audio | faithful | 11 / 0 / 0 / 0 |
| Saves | close | 14 / 1 / 0 / 0 |
| Coverage | close | 6 / 3 / 0 / 1 (functions entered: not measured) |

The `--quick` run grades Timing `close`. Its stretch count comes from the matrix's Vineta K cell: 3 stretches (16, 23
and 23 flips) against PPSSPP's 0, a difference of +3. The full run's fresh cell had 1 stretch (24 flips) against 0,
which is faithful.

**The rows that are `differs`, all in Trajectories.** "First" is the race clock at which the two runs first differ by
more than 1 m; "largest" is the largest distance over the first 20 s.

| Circuit | Ships | First | Largest |
|---|---|---|---|
| Vineta K | the 7 AI ships | 0.38 s | 134.36 m at 19.99 s |
| Modesto Heights | the 7 AI ships | 0.38 s | 143.47 m at 14.20 s |
| Chenghou Project | the 7 AI ships | 0.40 s | 219.93 m at 15.16 s |
| Blue Ridge | the 7 AI ships | 0.42 s | 142.10 m at 17.95 s |
| Sinucit | the 7 AI ships | 0.40 s | 188.51 m at 8.36 s |
| Sinucit | the player | 5.05 s | 13.89 m at 5.91 s |
| Citta Nuova | the 7 AI ships | 0.45 s | 183.73 m at 19.42 s |
| Sebenco Climb | the 7 AI ships | 0.45 s | 109.45 m at 11.95 s |
| Sol 2 | the 7 AI ships | 0.40 s | 489.91 m at 16.25 s |
| Karbonis | the 7 AI ships | 0.42 s | 377.04 m at 19.95 s |
| Karbonis | the player | 7.86 s | 34.07 m at 19.95 s |
| Sagarmatha | the 7 AI ships | 0.42 s | 253.66 m at 19.99 s |
| Manor Top | the 7 AI ships | 0.45 s | 140.30 m at 14.30 s |
| Mandrashee | the 7 AI ships | 0.38 s | 500.26 m at 19.99 s |
| Mandrashee | the player | 6.79 s | 6.23 m at 7.09 s |

What the records show for the three player rows:
- **Sinucit.** When the runs part, AI ship 6 is 9.1 m from the player in the port and 20.4 m in PPSSPP.
- **Mandrashee.** The same ship is 7.8 m away in the port and 16.7 m in PPSSPP.
- **Karbonis.** The nearest AI ship is more than 200 m away. The player scrapes a wall at about 30 km/h from 7 s, the
  port 1 to 3 km/h faster through the scrape, and the gap grows once the ship is free (12 m by 12 s).

The other rows:
- **Sol 2's player is `close`:** 3.25 m at 6.76 s, with AI ship 6 10.7 m away in the port against 23.4 m in PPSSPP.
- **The other eight players are faithful**, with a largest distance of 0.42 to 1.30 m (Vineta K 0.98 m, as task 007
  found).

**Rows other than `differs` and `faithful`:**
- **Accepted (D-011):** the race load before Vineta K is 0.30 s in the port and 1.50 s in PPSSPP. That is the time
  from the TEAM SELECTION confirm to the first of the race-start fade's 57 two-vblank flips.
- **Saves, `close`:** the decrypted PROFILE.BIN files differ in 71 bytes in 69 words, and all 69 hold user-RAM
  addresses on both sides (task 045's heap pointers). Every other row is equal, including PROFILE.BIN's 41586 bytes,
  `SAVEDATA_FILE_LIST` and ICON0.PNG byte for byte.
- **Coverage, `close`:**
  - 249 of the 278 imports are implemented; sceUtilityGetSystemParamString is answered from documentation only
    (UNVERIFIED) and is called in all 46 cells.
  - 3 imports are the profile's constants (sceKernelGetGPI, sceKernelRotateThreadReadyQueue,
    sceKernelGetThreadmanIdList).
  - 30 GE commands are still ignored, and none of them is one a draw of the game uses.
- **Coverage, beside those:** the 26 imports with no implementation are never called (that row is faithful), and
  functions entered is `not measured`.

**Other figures:**
- Pictures: the 18 suite scenes are at their measured values (race_hud 0.0148). Blue Ridge scores 0.0247, Sinucit
  0.0877 and Sebenco Climb 0.2993; the last two are the weather mist.
- Flips per race-clock second: Single Race 59.82, Tournament 59.36 (the matrix), Time Trial 29.98, Free Play 29.98,
  Zone 29.97.
- Audio, the main menu: correlation 1.000 and RMS ratio 1.000.
- Audio, the races (Vineta K, Sinucit, Sagarmatha):
  - music correlation 0.627, 0.689 and 0.735;
  - both mixes active in 1.00 of the seconds;
  - clipped samples 0 against 6, 0 and 0.

Changed (12 commits on the branch, plus the merges):
- `tools/scorecard.py` (new).
- `tools/ppsspp/routes/main_menu_music.txt` (new): MAIN MENU with L every 20 s. This keeps the attract demo away, and L
  makes no sound there.
- `docs/scorecard.md` (new): from the --full run. Its header was rendered again from the same JSON after two wording
  fixes.
- `docs/verification.md`: a new section, "The accuracy scorecard".
- `README.md`: the tool's row.
- `ref/README.md`: the references' section and their hash table, which the tool rewrites between markers.

Verify output (`tools/verify_task.sh 044` at 91217c1, last 20 lines):
```
[scorecard] pictures ...
[scorecard] frame_regress.sh: exit 0, 25 s
[scorecard] run picture-blue_ridge_hud: exit 0, frame 6046 reached, 5 s
[scorecard] run picture-sinucit_hud: exit 0, frame 6046 reached, 4 s
[scorecard] run picture-sebenco_climb_hud: exit 0, frame 6048 reached, 5 s
[scorecard] pictures: faithful (21 rows, 40 s)
[scorecard] timing ...
[scorecard] run load-vineta_k: exit 0, frame 6400 reached, 7 s
[scorecard] timing: close (7 rows, 7 s)
[scorecard] saves ...
[scorecard] run save: exit 0, frame 4800 reached, 3 s
[scorecard] saves: close (15 rows, 3 s)
[scorecard] coverage ...
[scorecard] coverage: close (10 rows, 0 s)
pictures      faithful
timing        close
saves         close
coverage      close
[scorecard] wrote out/044/scorecard.json and scorecard.md (0m 49s)
verify 044: PASS
```

Wall times:
- `--quick`: 49 s, twice.
- `--full`: 17 m 38 s for the committed run, and 17 m 56 s for an earlier one.
- `--refresh-references`: about an hour of PPSSPP in all. The 13 trajectory runs took about 36 minutes; the main
  menu, the save and the follower race took 3, 2 and 6 minutes; then the two retakes.

Open questions:
1. **The port's AI ships are a different race from PPSSPP's on every circuit, from 0.4 s after GO.** Each side
   repeats itself: two PPSSPP runs of Vineta K agree to 0.000 m, and two headless port runs of Karbonis and Sinucit
   agree to 0 m. So the state the AI starts from differs. Two candidates:
   - the time the port answers, where the driver pins the RTC base;
   - the shorter loads of D-011, which change how many frames run before the race.

   The brief says no seed hunting, so this was not chased. It also moves three player rows (Sinucit, Mandrashee and,
   as close, Sol 2) where an AI ship comes near.
2. **Karbonis' wall scrape amplifies a 1 to 3 km/h difference in the contact response** into 34 m by 20 s. Task 007
   saw the same effect at 0.5 m on Vineta K. It is a candidate for a closer look at the collision path.
3. **Files the brief names that did not serve as they are** (worked around in scorecard.py, as the brief asks):
   - `config/hle_coverage.csv` does not exist. The imports are classified from `config/imports.csv`, the start-up
     list, the matrix logs' `[hle-stub]` and `UNVERIFIED` lines, and the profile's constant answers.
   - `tools/save_roundtrip.sh` has no headless or run-1-only option: it runs five windowed runs in 13 minutes. Its run
     1 (`main_menu.txt` on an empty stick) is reproduced headless.
   - `tools/pp_lines.py`'s PPSSPP route reaches the Alpha league only. The scorecard samples with its block and
     parser in its own loop, through task 035's unlock routes. Each block is read twice and kept when both reads
     agree; 2 to 10 torn reads were dropped per run.
4. **PPSSPP's replay lifts the pad when its items run out.** A `--pad` hold with no later release ends at once, so
   the first Vineta K run sat on the grid. The scorecard adds a release 9000 vblanks on. `pp_lines.py --pad` users
   should do the same.
5. **PPSSPP's debugger stopped answering `memory.read` twice in about 20 runs** (Sagarmatha's first try, and the
   second follower race). The first follower race also stalled in lap 3, while task 045 shared the machine. The tool
   now retries a hung trajectory run once and drops its partial dump. The kept follower race (3 laps, 43 contacts) had
   no stretch, so the stretch row swings with one race per side: +1 in the --full run, +3 in --quick against the
   matrix's cell. Several races per side would make that row steadier.
6. **A profile left on PPSSPP's stick.** Task 045 put a profile on PPSSPP's stick at 10:58 for about 1.5 minutes,
   while Sagarmatha's first run started. That run was the one that hung, and it was redone with the stick clean. The
   tool now waits while PPSSPP runs for someone else or its stick holds a profile save.
7. **Coverage reads the matrix of 2026-10-06** (`~/dev/pure-recomp/out/035-wip/fidelity`), which predates tasks 036
   to 045. Only its GE count is replaced by this run's exit list (30 against the matrix's 65). A new matrix (about
   4 h) would refresh the rest.
8. **Functions entered is `not measured`.** `PSPRECOMP_PROFILE_DISPATCH` sees the outer dispatch loop only, and
   `PSPRECOMP_COUNT_PC` takes eight addresses. The brief puts the VFPU differential test in "task 045", but that number
   went to the save format.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
