# 035: The fidelity audit: every difference from the original, measured and listed (M8)

Milestone: M8 | Branch: task/035-fidelity-audit | Status: MERGED 2026-10-07 (a75099a)

## Goal
D-009: the port as close to 1:1 with the original as possible before any enhancement. This task measures where it is
not, across the whole game, and writes the list that the M8 fix tasks come from. It changes no game-facing code: it
runs, compares, aggregates and reports. Four kinds of evidence: the campaign matrix headless on Metal (every track,
the fastest and slowest class, every mode, every Zone track) with every halt and unimplemented-feature line counted;
new PPSSPP reference scenes beyond the five the suite has; audio over every track; saves and records after races.
The output is `docs/fidelity.md`: a table of differences with evidence and a suspected cause, ordered by what a
player would notice, each row a candidate task.

## Read first
- CLAUDE.md, docs/decisions.md D-009, docs/status.md (M5, M6, M7 rows; Follow-ups: every row marked for M8),
  docs/verification.md (the suite, the HUD check, "Fast, silent test runs"), docs/tracks.md (leagues, classes, the
  cells so far, the switch), docs/metal-backend.md ("Where it differs", the `not emulated` and `not implemented`
  lines and when they print), docs/ge-effects.md, docs/savedata.md, docs/ppsspp.md and tools/ppsspp/ (the PPSSPP
  driver and its deterministic routes; how the five references in `ref/README.md` were captured and matched to the
  port's flips), docs/tasks/006, 013, 014, 018, 032 (Results)
- tools/campaign_sweep.py (`--class`, `--unlock-all`, `--no-damage`, the modes, MODES, the summary), tools/run_boot.py
  (`--shell headless`, `--env`, `--stubs`, `PURE_LIST_STUBS`, `PURE_STRICT_HLE`), tools/frame_regress.sh (adding a
  scene: route, frame, reference, tol, limit, measured), tools/wavstats.py, tools/save_roundtrip.sh, tools/imgdiff.py
- src/profile/pure_profile.cpp (the probes and test switches; read only)

## Deliverable
1. `tools/fidelity_audit.py`: runs a list of cells through `tools/campaign_sweep.py` one at a time (headless,
   `--no-damage`, `--unlock-all` where needed, `PURE_LIST_STUBS=1` and `PURE_TRACE_...` off), collects from each
   cell's log every `[hle-stub]`, `unsupported`, `Runtime stopped`, `[metal] ... not emulated`, `[metal] ... not
   implemented`, `[render]`/`[mpeg]`/`[atrac]`/`[sas]` warning line, the follower's outcome and the backend's exit
   stats, and writes `out/fidelity/matrix.md` (one row per cell) and `out/fidelity/features.md` (one row per distinct
   line: text, cells, count, first track). `--cells FILE` names the list; `--quick` runs three cells (Vineta K Vector
   Single Race, Zone 1, Time Trial Vineta K) for the Verify; `--resume` skips cells already in the matrix.
2. The matrix, run once in full and committed as tables in `docs/fidelity.md`: Single Race on all 12 circuits at
   Vector and at Phantom (24 cells), Time Trial on every circuit at Vector (12), Free Play on one track per league
   (3), Tournament on every league (3), Zone 1 to 4 (4). About 46 cells at 2 to 4 minutes each headless; run them in
   the background in sequence and poll. A cell that stalls for the follower's reasons (Sinucit's fork, Manor Top's
   bend, a marginal track) is recorded as such, not retried more than once; a cell that halts the game is the
   finding.
3. PPSSPP references beyond the five: capture with the PPSSPP driver and add to the suite (a `SCENES` row each, with
   a measured value from three runs) at least: the first full-HUD frame of Modesto Heights, Chenghou Project and Blue
   Ridge (Single Race, Vector, as `race_hud` is for Vineta K), the results screen after a Vineta K race, the TEAM
   screen, Zone 1's first frame and its zone-change frame, Time Trial's HUD on Vineta K, the game's pause menu in a
   race, the Options and Controls screens. These need no unlock. For the Beta and Classic circuits, which PPSSPP
   cannot reach without unlocks: find whether PPSSPP's CWCheat can set the profile's unlock byte (`[[0x08B17794] +
   0x381] = 1`, a pointer write) or its GPI; if it can, capture the first-HUD frame of every other circuit too; if
   not, say so and leave them. Every new reference is listed in `ref/README.md` with its hash and route; the
   captures stay git-ignored.
4. Audio over every circuit: a headless Vineta K-style race per circuit with `PURE_AUDIO_WAV` (the sweep cells of
   item 2 can carry it), `tools/wavstats.py` per cell (active fraction from the race start, clipping), and the sceSas
   and sceAtrac stub or warning lines; one table in docs/fidelity.md. Also the frontend's music loop over a 5-minute
   idle on the main menu.
5. Saves and records: after a Single Race and after a Tournament, the TRACK screen's records and the medal counts
   (shots before and after), the autosave's files under the scratch memory stick, and a restart that LOADs the
   profile and shows the same records; two profiles created in a row and what the LOAD screen then offers (the
   framework's save list picks the first slot: record what the PSP's own dialog would show, from PPSSPP).
6. The two-vblank stretches (task 033): in every race, at about the same track positions on both paths, the game
   runs 0.4 to 1.3 s at a two-vblank cadence (the frame object's locked path: `+0x116c` 0 or the countdown at
   `+0x117c`, docs/timing.md step 5; the main thread calls `sceDisplayWaitVblankStart` twice a frame there).
   Find what sets the lock during a race (`PURE_TRACE_CALLS` on the writers of those fields, or a memory watch;
   docs/timing.md names the limiter), and whether PPSSPP shows the same cadence at the same positions (its
   frame counter against the race clock through the driver). If the game sets it from a timing it measures (a
   frame-time estimate from the system clock, as FUN_08804390 computes), the HLE's answers are the suspect;
   if it is the game's own rule (a weapon, a camera cut, a section of track), it is faithful and the list says
   so. Report either way; fix nothing here.
7. `docs/fidelity.md`: the four evidence sections, the stretches' finding, then the **differences list**: for each, what a player sees or
   would see, where (track, mode, frame), the evidence (log line, shot pair, fraction), the suspected cause (backend
   feature, HLE stub, follower, unknown), and a size guess. Ordered by visibility. Also a short "what matches" section
   so the list is read in proportion. README.md: the tool and the doc. docs/verification.md: the new scenes.

## Acceptance criteria
- [ ] `tools/fidelity_audit.py --quick` runs its three cells and writes the two tables.
- [ ] docs/fidelity.md holds the full matrix (every planned cell with an outcome), the feature table, the audio
      table, the saves section, the two-vblank finding and the differences list.
- [ ] At least eight new reference scenes pass in the suite with measured values, and `tools/frame_regress.sh`
      (headless Metal) still passes every scene.
- [ ] No game-facing code changed (src/, vendor/, patches/ untouched).

## Verify
`tools/build.sh profile && python3 tools/fidelity_audit.py --quick && test -s out/fidelity/matrix.md && tools/frame_regress.sh`

## May touch
- tools/fidelity_audit.py (new), tools/frame_regress.sh (new SCENES rows only), tools/ppsspp/routes/ (new routes),
  ref/README.md, docs/fidelity.md (new), docs/verification.md, README.md

## Must not touch
- src/, vendor/, patches/, config/ (routes and lines are the sweep's; use them), tools/campaign_sweep.py,
  tools/run_boot.py, tools/pp_lines.py, tools/gerec/, CMakeLists.txt

## Estimated turns
90 (most of the wall time is the matrix running in the background)

## Escalate when
PPSSPP cannot be driven (report what the driver returns and capture nothing new), a cell halts the game in a way
that stops every later cell (report it and continue with `--resume` after a restart), or the matrix would take more
than six hours (report the per-cell times and stop at the 30th cell with the rest listed as not run).

## Result
Status: DONE

The work ran over two sessions. The first wrote the audit tool, the PPSSPP routes and captures, the twelve suite
scenes and the analysis in docs/fidelity.md, and started the 46-cell matrix. It was cut off at 21:51 on 2026-10-06,
and the matrix loop finished on its own at 23:06. The second session, in a new worktree:
- read the cells again with the current collectors (`--rescan`, which adds the hitches) and folded the finished
  matrix into docs/fidelity.md: every cell with its outcome, a per-mode summary, the line table, the ignored-GE table
  (65 commands in 14 features), the audio table, the stretches per cell and the differences list;
- made the twelve suite references again, because the first worktree's git-ignored captures were lost with it. All
  12 PNGs and 9 GE dumps came out byte-identical to the hashes in ref/README.md;
- added the brief's missing Zone 1 zone-change frame (`zone_change`: port flip 5679 against PPSSPP vblank 7528,
  captured twice byte-identical; Metal scored 0.0649 in three runs, Vulkan 0.0818 in one windowed run, limit 0.10);
- corrected the burst labels. A burst asking for every vblank of a 30-fps scene falls behind, so `tt_hud.png` and
  `fp_hud.png` are vblank 7340, not 7302, and `zone_hud.png` is 6694, not 6668. The same check showed that a capture
  on a menu before the load does not move the race;
- ran two hitch cells again. The hitches came back at other places, so difference 7 is now "to check" and no longer
  put down to the busy machine;
- made `--resume`, `--report` and `--list` end with a completeness line.

Changed (on the branch, since c105a66): tools/fidelity_audit.py (new), tools/frame_regress.sh (13 new SCENES rows),
tools/ppsspp/routes/ (16 new routes), ref/README.md, docs/fidelity.md (new), docs/verification.md, README.md. src/,
vendor/, patches/ and config/ are untouched.

Verify output (last 20 lines; `tools/verify_task.sh 035` at c9ce1e2, 2026-10-07 00:11, which is b898098 since the
branch was rebased onto batch/m2's docs-only 16fbef2; the three `--quick` cells were PASS, PASS, PASS; the commits
after it change docs only):
```
title        1750    0.0002   0.05   24    0.0002 +0.0000  PASS
profile      2100    0.0000   0.07   24    0.0000 +0.0000  PASS
main_menu    4700    0.0106   0.05   24    0.0106 +0.0000  PASS
race_hud     6016    0.0374   0.10   32    0.0379 -0.0005  PASS
single_player   4765    0.0000   0.05   24    0.0000 +0.0000  PASS
class_select   4990    0.0000   0.07   24    0.0000 +0.0000  PASS
league_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
track_select   5390    0.0000   0.06   24    0.0000 +0.0000  PASS
team_select   5600    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
tt_hud       5890    0.0617   0.12   32    0.0617 +0.0000  PASS
fp_track_select   5375    0.0000   0.06   24    0.0000 +0.0000  PASS
fp_hud       5890    0.0620   0.11   32    0.0620 +0.0000  PASS
tournament_select   5185    0.0000   0.08   24    0.0000 +0.0000  PASS
zone_track_select   4975    0.0000   0.05   24    0.0000 +0.0000  PASS
zone_hud     5260    0.0348   0.09   32    0.0348 +0.0000  PASS
zone_change   5679    0.0649   0.10   32    0.0649 +0.0000  PASS

frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 24s)
verify 035: PASS
```

Counts:
- Cells: 46 of 46 run. 36 PASS, 10 STALL (all the follower's, at four places: Sinucit's fork, Manor Top, Karbonis at
  Phantom, a wedge on Chenghou Project), 0 HALT. `tools/fidelity_audit.py --resume` prints `46 of 46 cells have a
  result (36 PASS, 10 STALL); complete`.
- Features listed: 3 distinct log lines (all audio-capture underruns: no `[hle-stub]`, `unsupported`, `Runtime
  stopped` or `[metal] not emulated/implemented` line in any cell), 65 GE commands the framework ignores (in 14
  features), and 26 imports with no implementation, none of them called.
- Scenes added: 13 to the suite (now 18 scenes), out of 31 new PPSSPP references. The other 18 (OPTIONS, CONTROLS,
  the 11 other circuits' first race frames, the pause menu, the results panel, the save dialog twice, Zone's end
  panel) have no port route in `config/pad_scripts/`.
- Differences found: 11, ordered by visibility in docs/fidelity.md:
  1. environment mapping;
  2. mipmaps;
  3. Sebenco Climb's and Sinucit's surfaces too bright;
  4. a second profile overwrites the first, with no save dialog;
  5. unencrypted saves;
  6. shorter loads;
  7. race hitches (to check);
  8. music gaps at track changes and at Free Play's finish (to check);
  9. clipping in the attract demo (to check);
  10. the colour test;
  11. dithering and depth clamp.

The two-vblank stretches of item 6 are the game's own: FxScreen's full-screen flash sets the lock countdown, and
PPSSPP has the same stretches, of the same lengths.

Open questions:
- Captures: the new PPSSPP captures are git-ignored and exist only in this worktree's `ref/`. The main checkout's
  `ref/` has the five originals. Copy `ref/*.png ref/*.ppdmp` there before running the suite in the main checkout,
  or it exits 2 with "ref/single_player.png missing".
- Lost with the first worktree: the 18 references outside the suite, the Beta and Classic GE dumps and the dump
  readers. Their hashes and commands are still in ref/README.md and docs/fidelity.md.
- Matrix results: in this worktree's `out/fidelity/` (657 MB). The Verify's own runs of the three quick cells are in
  `out/fidelity-verify-quick/`.
- Difference 7 (hitches of 102 to 295 ms in 12 cells, at no fixed place): the port, the sweep's pty reader or the
  machine. Check on an idle machine in a run like a player's, with `PURE_METAL_TRACE`.
- Differences 8 and 9 need PPSSPP's audio dump (`DumpAudio`), which was not taken.
- Difference 3's cause lies upstream of both backends and is not found yet.
- Which event makes the 38-to-39-flip flash is not known, and PPSSPP's race never showed the 31-flip put-back flash.
- Three render pipelines of the 30-fps result and standings screens are missing from `config/metal_pipelines.txt`.
- Medal counting is untested: no cell won a medal.

## Review
Verify rerun: PASS from the main checkout on the merged build, 2026-10-07 (`tools/verify_task.sh 035`): the three
quick cells PASS (Vineta K Single Race, Zone 1, Time Trial Vineta K; `3 of 3 cells have a result; complete`), the
headless suite 18/18 in 24 s (the thirteen new scenes at their measured values, zone_change 0.0649). The new PPSSPP
references and GE dumps were copied into the main checkout's `ref/` first (18 PNGs); the matrix results are kept in
`out/035-wip/fidelity/` (658 MB).
Spot-read: `tools/fidelity_audit.py` (the cell list, `--resume`, `--rescan`, the collectors, the completeness line),
the thirteen SCENES rows and their routes, ref/README.md (hashes and capture commands), docs/fidelity.md (the
matrix, the feature table: 65 GE commands in 14 features ignored by the framework, 26 imports never called; the
references; audio; saves; the two-vblank finding; the differences list).
Merged: a75099a into batch/m2 (clean).
Notes: the work ran over two workers (the first cut by the usage limit with the matrix loop still running; the loop
finished on its own; the second rebuilt the lost references byte-identical to the recorded hashes and folded the
matrix in). The differences list became tasks 036 to 041 (docs/tasks/); differences 5 (save encryption: Sony's
hash keys) and 6 (UMD read timing) wait for Erik's call. The 18 references outside the suite need port routes
before they can join it (a follow-up). The hitches of difference 7 came back at other places on a rerun, so they are
"to check", not the machine's.
