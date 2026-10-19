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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fills at review) Verify rerun: | Spot-read: | Merged: | Notes:
