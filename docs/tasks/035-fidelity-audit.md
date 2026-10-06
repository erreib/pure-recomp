# 035: The fidelity audit: every difference from the original, measured and listed (M8)

Milestone: M8 | Branch: task/035-fidelity-audit | Status: OPEN (dispatch after task 033; headless, one game at a time)

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
6. `docs/fidelity.md`: the four evidence sections, then the **differences list**: for each, what a player sees or
   would see, where (track, mode, frame), the evidence (log line, shot pair, fraction), the suspected cause (backend
   feature, HLE stub, follower, unknown), and a size guess. Ordered by visibility. Also a short "what matches" section
   so the list is read in proportion. README.md: the tool and the doc. docs/verification.md: the new scenes.

## Acceptance criteria
- [ ] `tools/fidelity_audit.py --quick` runs its three cells and writes the two tables.
- [ ] docs/fidelity.md holds the full matrix (every planned cell with an outcome), the feature table, the audio
      table, the saves section and the differences list.
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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
