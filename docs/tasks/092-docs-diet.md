# 092: The docs diet (current state in the reference docs, history out)

Milestone: cleanup (audit 2026-10-19) | Branch: task/092-docs-diet | Status: OPEN

## Goal
A fresh session reads little and finds the current state fast. The audit (docs/history/audit-2026-10-19.md, "Docs")
measured a 47K-token start (status.md 22.6K, decisions.md 15.7K, vendor-map.md 6.7K) and found each check described
three times. When this is done: docs/status.md holds the current state only, docs/vendor-map.md is a short seams
reference, developing.md gives each tool one line, verification.md says what each check guards and when it runs,
and the history these held lives in docs/history/, linked. Nothing is lost: text moves, it is not deleted, unless it
is wrong or a duplicate of a fact kept elsewhere.

## Read first (about 25K tokens; skim the rest by grep)
- docs/approach.md, whole (short): "Working rules", rules 5 and 8 above all.
- docs/history/audit-2026-10-19.md, "Docs".
- docs/status.md: its headings (`grep -n '^#' docs/status.md`), then the sections as you move them.
- tools/docs_check.py: what it checks (paths, patches and tasks named must exist).

## Deliverable
1. **docs/status.md, current state only, at most 30 KB.** Keep: the milestone and enhancement table (status per
   row, one line each), a "Works" table brought up to date (what runs today on Mac and Windows, both shells), the open
   follow-ups (one line each, a link for detail), Branches, the gate, open calls, and what is next. Move to
   docs/history/sessions.md (append, under a dated heading): the Resume arcs (E3 to E8, the rig stutter arc, DLC,
   the release), resolved Blockers and the Resolved section, resolved follow-ups, and the repack log. Fix the
   "Last updated" line and the stale items the audit lists.
2. **docs/vendor-map.md**: at most 4 KB, "the framework seams this port uses": which vendor parts we use as they
   are, which we patch (by patch, one line), which we replace (the Metal backend and shell), and the profile hooks.
   The Oct 5 spike report (the Yakumo comparison and the rest) moves to docs/history/vendor-map-2026-10-05.md.
3. **docs/developing.md**: the tools table becomes one line per tracked file under tools/ (path, what it is for,
   time a run takes), the detail left to the script's header. Every tracked tools/ file has a row (it lacks
   billboard_check, bundle_windows, menu_check, release_check, scale_check and purelib/conpty). Mark the fidelity
   layer's tools (scorecard, fidelity_audit, vfpu_probe, vfpu_model, the ppsspp/ tools, audio_compare,
   save_interchange, pp_lines, ai_seed_check, sas_reverb_check) as "reference, not a gate". The switch table keeps
   one row per switch, its provenance cut to a task number.
4. **docs/verification.md**: the checks table says, per check, what it guards, its pass bar and when it runs (the
   "Which path for which change" rows), one fact per column, no task history in cells. The fidelity layer's
   sections (scorecard, VFPU, audio, interchange; about 28 KB) move to docs/fidelity.md (or docs/scorecard.md where
   that fits better); the task-069 wall-time table and other measurements move to docs/history/verification.md.
5. **docs/windows.md**: the dated "Updating the rig" checklist moves to docs/history/ (a windows-rig file); keep the
   rig's current open items and how to bring the rig up to date, in short.
6. **Duplicated measurements**: the E8 margin's write-up stays in docs/timing.md "E8" and the task file; status.md
   and windows.md link to it instead of restating it. Apply the same rule wherever you meet a measurement repeated
   in reference docs.
7. **tools/docs_check.py** gains one rule: every tracked file under tools/ (excluding `__pycache__`) is named in
   docs/developing.md.
8. Do not change: docs/decisions.md (a log, read by entry), docs/tasks/ (the record; never rewritten),
   docs/approach.md, CLAUDE.md, docs/scorecard.md, README.md and CHANGELOG.md (other than a link that must follow a
   move).

## Acceptance criteria
- [ ] `wc -c docs/status.md` at most 30000; docs/vendor-map.md at most 4500.
- [ ] CLAUDE.md + docs/approach.md + docs/status.md together at most 48000 bytes (about 12K tokens).
- [ ] Every tracked tools/ file named in docs/developing.md, enforced by docs_check.
- [ ] No text lost: each moved block is in its new home (spot-checkable by grep), and the Result lists what moved
      where and what was cut as wrong or duplicated, with the reason.
- [ ] `python3 tools/docs_check.py` PASS. No file outside "May touch" changed. No game run, no build.

## Verify
`python3 tools/docs_check.py && test $(wc -c < docs/status.md) -le 30000 && test $(wc -c < docs/vendor-map.md) -le 4500 && test $(cat CLAUDE.md docs/approach.md docs/status.md | wc -c) -le 48000`

## May touch
- docs/status.md, docs/vendor-map.md, docs/developing.md, docs/verification.md, docs/windows.md, docs/timing.md,
  docs/fidelity.md, docs/scorecard.md (only to receive moved sections, not its scorecard table), docs/history/*
  (new files and appends), README.md and CHANGELOG.md (links only), tools/docs_check.py,
  docs/tasks/092-docs-diet.md

## Must not touch
- docs/decisions.md, docs/approach.md, CLAUDE.md, docs/tasks/ other than this file, src/, tools/ other than
  docs_check.py, vendor/, patches/, config/, game/, out/ beyond scratch

## Estimated turns
50

## Escalate when
- A section cannot be classed as current or history without a call on what is true today (say which, with both
  readings).
- The size bounds cannot be met without deleting text that is neither wrong nor duplicated.

## Result
Status: DONE

Changed: docs/status.md, docs/vendor-map.md, docs/developing.md, docs/verification.md, docs/windows.md,
docs/timing.md, docs/fidelity.md, docs/history/sessions.md (insert), docs/history/verification.md (append),
docs/history/vendor-map-2026-10-05.md, docs/history/developing.md and docs/history/windows-rig.md (new),
tools/docs_check.py, this file. Nine commits on task/092-docs-diet (2b3949f to b008abc, then this Result), each
`Task: 092`.

Sizes: status.md 90,364 to 15,816 bytes; vendor-map.md 26,983 to 3,442; CLAUDE.md + approach.md + status.md
26,439; developing.md 83,223 to 52,128 (the Running section and its switch table are most of what is left);
verification.md 83,227 to 48,621; windows.md 22,680 to 9,193.

What moved where (all verbatim, with relative links rewritten for the new directory; checked line by line against the
originals, and each block can be found by grep):
- status.md to docs/history/sessions.md, new section "The state before the docs diet (2026-10-19, task 092)", placed
  first in the file because it is ordered newest first: the milestone table (with exit commands), the old Works
  table, the Blockers table (all resolved but the Ghidra caveat), the whole Follow-ups table, the Resume bullets from
  "Branches" (as it stood) through the Windows bring-up, the repack log ("The app"), the Esc menu, E3, E6, E4, E7,
  E5, E2, E8 with the margin, the rig's stutter arc (077 to 083), DLC, the two lines' merge, Erik's play check, R1,
  the release, the menu refinements, the HD-pack roadmap entry, the rig's 2026-10-14 pull, the storms, the open
  calls and the unlock code, then the Resolved list. status.md now holds the milestone and enhancement table, Works
  for the Mac and the rig, the open follow-ups one line each with a link, Branches, the gate, open calls and Next.
- vendor-map.md (the spike S3 report) to docs/history/vendor-map-2026-10-05.md; vendor-map.md rewritten as the
  seams reference (used as is, patched one line a patch, replaced, the profile hooks). docs_check now path-checks
  vendor-map.md (it names this repository's paths now).
- developing.md's tools table to docs/history/developing.md; the new table has one row per tracked tools/ file
  (path, purpose, a run's time), the six missing tools and the purelib modules (conpty too), the six Ghidra scripts,
  and the 23 PPSSPP routes in one brace-form row; the fidelity layer's tools marked "reference, not a gate".
- verification.md's checks table to docs/history/verification.md ("The checks table as it stood"); the new one has
  Guards, Pass bar and When it runs, no task history. Task 069's wall-time section and its record of the window
  columns' wobble to docs/history/verification.md. The fidelity layer's sections (Audio with PURE_AUDIO_WAV,
  wavstats, audio_compare and the SAS reverb check; the save interchange check; the accuracy scorecard; the VFPU
  dot-product check with its two subsections; 28 KB) to docs/fidelity.md, "The fidelity layer's checks", same
  headings at a deeper level. Not to docs/scorecard.md: `tools/scorecard.py --full` rewrites that file whole.
  verification.md keeps a short section naming the moved headings, so old pointers still find them by grep.
- windows.md's "Updating the rig" checklist to docs/history/windows-rig.md; windows.md keeps "Bringing the rig up
  to date" and "Open on the rig" in short.
- The rig's E8 figures (the storm profile from the windows.md checklist, the 2026-10-15 sound probe from status.md)
  into docs/timing.md, E8, "On the rig's 100 Hz display", so status.md and windows.md link instead of restating.
- The Ghidra worktree caveat (a status Blocker) into `tools/ghidra_headless.sh`'s row in developing.md.

Cut as wrong or duplicated (and why):
- status.md: the doubled table header rows (Works, Blockers); the Resolved list's last line, a link to
  sessions.md that means nothing inside sessions.md; the unlock-code line (duplicate of docs/fidelity.md, "PPSSPP
  references beyond the suite"; its copy is in sessions.md); "Merge: rerun the Verify" (wrong since approach.md
  rule 3); the open call to publish the repository and the follow-up on a public source URL (done, 0.1.0 is public);
  the follow-up on the menu's "Graphics: Vulkan on" text (resolved by task 064, per the audit); "28 patches" (30);
  "Last updated 2026-10-07"; M3's race_hud figure and the rig's guest time (the suite's table and task 083 hold them).
- developing.md: the switch rows' provenance cut to one task number (patch names, D-numbers, "Vulkan since task N"
  are in patches/README.md and docs/decisions.md); the suite's "about 10 s" (about 25 s).
- verification.md: the suite's and the HUD check's wall times (5m 10s, 5m 11s, 19m 48s, 7m 46s, 82 s, 227 s)
  restated task 069's table, now round figures and a link; "four" pinned enhancements (five: E8's
  `PURE_DISPLAY_RATE`); purelib's Used-by column (most bash checks use it now; conpty had no row).
- timing.md: "the rig's 100 Hz display is unmeasured" (measured 2026-10-14 and 2026-10-15).
- fidelity.md: "README.md, the tools table" (README has none) and the moved scorecard text's "the re-baselining
  rule above" (now names docs/verification.md).

docs_check gained its fifth check, `tools`: every tracked file under tools/ (git ls-files, `__pycache__` aside) is
named in docs/developing.md by its path or a brace form; shown to FAIL with a row removed. The check needed neither
the vendor tree nor the disc; no build, no game run, no window check.

Verify output (last 20 lines):
```
docs_check: 39 files, 0 findings: PASS
```
Exit 0: the three size tests pass (status.md 15816 bytes, vendor-map.md 3442, CLAUDE.md + approach.md + status.md
26439).

Open questions:
- The Esc menu's folder buttons on Windows (patch 0029-windows-file-url): status.md's menu-refinements bullet said
  "Verified on the rig by hand", but the later rig bullet of 2026-10-14 and windows.md's checklist list it as open,
  Erik's by hand. status.md and windows.md now carry the later reading (open); if it was verified, drop that item.
- Pointers outside "May touch" that name a section this task moved: ref/README.md (verification.md "The SAS reverb
  check", "The accuracy scorecard", "The VFPU dot-product check"), docs/savedata.md:244 ("The save interchange
  check"), tools/scorecard.py's HEADER (and so docs/scorecard.md's line 25, "The accuracy scorecard"). They still
  resolve by grep through verification.md's "The fidelity layer's checks", but should say docs/fidelity.md.
  docs/dlc.md and docs/release.md send the reader to developing.md for dlc_check's detail, now in its header.
- docs/decisions.md D-001 cites "Spike S3 (docs/vendor-map.md)", and CLAUDE.md's escalation rule says "the vendor
  API differs from docs/vendor-map.md": the API tables at 8b0c3fe are now in docs/history/vendor-map-2026-10-05.md
  (linked from vendor-map.md). Both files were outside this task.
- tools/save_roundtrip.sh's header says three windowed runs (five): tools/, for task 093.
- The routes row names its 23 files in one brace-form row; if one row a file is wanted literally, it is 23 rows.

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
