# 053: The docs pass (the organisation pass, 5 of 5)

Milestone: M9 organisation | Branch: task/053-docs-pass | Status: OPEN

## Goal
The reference docs grew a section per task: docs/fidelity.md is 1500 lines, docs/metal-backend.md 1375,
docs/verification.md 670, and each holds history (what a task measured on a date) beside reference (how the thing
works now). Tasks 049 to 052 moved files, tools and patches, so paths and patch numbers in the docs are stale in
places. This task makes every reference doc describe the repository as it is, moves task history into the task
files or an appendix, and adds a check that keeps the docs honest.

## Read first
- CLAUDE.md, docs/ (every .md; the README; patches/README.md's mapping table from old to new patch numbers, task
  052), docs/tasks/049 to 052 (Results: what moved where), docs/tasks/TEMPLATE.md
- tools/ (the tool names and command lines are the contract the docs cite)

## Deliverable
1. Each reference doc split into reference and history: the reference part stays in the doc, rewritten where the
   code moved (docs/metal-backend.md's file names and the shader; docs/verification.md's tools, with tools/purelib;
   docs/ge-backend.md section 6, the Draw record, brought up to patch 0004-ge-backend-and-shell-seams' final form;
   docs/savedata.md; docs/timing.md); the per-task history ("Task NNN measured...", the dated tables) moved to
   docs/history/<topic>.md (one per reference doc that had history, linked from the doc's end) when it is more than
   a paragraph, or left as a dated note when it is less. The task files are not rewritten (they are the record).
2. Old patch numbers switched to the new series everywhere outside docs/tasks/ and vendor/, using patches/README.md's
   mapping table: the docs, README.md, ref/README.md, the comments in tools/ and src/tools/. Where a sentence says
   "patch 0014 added X", it becomes "patch 0002-ge-state-commands (task 037) added X", keeping the task number so the
   history stays reachable.
3. docs/status.md trimmed: the milestone table rows say the current state in one line each (P0 and M1 are long done;
   their rows still say "in progress" and "tasks 001 still open"), the Works and Blockers tables kept, the Follow-ups
   table kept but with resolved rows moved to a "Resolved" list at the end, and the Resume section cut to what a
   new session needs (the branches, the gate, the running task, the open calls), with the session-by-session
   history moved to docs/history/sessions.md.
4. `tools/docs_check.py`: every `tools/<name>` and `src/<path>` a doc or the README names exists; every relative
   link in docs/ resolves; every `patches/NNNN-` name cited exists; every `docs/tasks/NNN` cited exists; exit 0 when
   clean, else the list. Run it; make it clean. Add it to docs/verification.md.
5. README.md: the layout table and the tools table checked against the tree; the switches table checked against the
   code (each `PURE_*` name the README lists is read somewhere under src/ or vendor/, and each name read under src/
   is listed; the vendor's own switches as the README has them).

## Acceptance criteria
- [ ] `python3 tools/docs_check.py` exits 0.
- [ ] No reference doc names a file, tool or patch that does not exist; docs/status.md's milestone rows are current.
- [ ] Nothing of the record is lost: every dated table and finding moved is reachable from the doc it left.

## Verify
`python3 tools/docs_check.py && tools/frame_regress.sh --only race_hud`

## May touch
- docs/ (not docs/tasks/ except this brief's Result), docs/history/ (new), README.md, ref/README.md,
  patches/README.md (wording only), tools/docs_check.py (new), comments in tools/ and src/tools/ that cite old patch
  numbers (comments only)

## Must not touch
- src/ (other than comments in src/tools/), vendor/, patches/*.patch, config/, docs/tasks/ (the record), tools/
  (other than the new check and the comments named), the task briefs' texts

## Estimated turns
45

## Escalate when
A doc's statement cannot be checked against the code (report it as "unverified" in the doc rather than guess), or a
history section has no natural task file or topic to go to (report; leave it in place).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
