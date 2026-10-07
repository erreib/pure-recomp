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
Status: DONE. Every reference doc now describes the repository as it is, with each task's measurements moved word for
word to `docs/history/` and linked from the doc it left; the docs, README.md, ref/README.md and the comments of
tools/ and src/tools/ name every patch in the new series with the task that made the change (an old number appears
only marked "old": in the history files, docs/upstream.md and patches/README.md's mapping table); docs/status.md is
trimmed; README.md's layout, tools and switches are checked against the tree and the code; and `tools/docs_check.py`
(new, 227 lines) passes on all 31 docs. The Verify line passes.

### Changed
Lines before (batch/m2 at 143f2f5) and after, and where each doc's history went:

| Doc | Before | After | History |
|---|---|---|---|
| docs/fidelity.md | 1502 | 136 | docs/history/fidelity.md (1510): the whole audit report as it stood, tasks 035 to 048; the reference now gives how fidelity is measured, what matches, each difference's state and where its fix lives (the numbering the code cites kept), the two-vblank rule, item 3, the 30 GE commands still ignored, what is open |
| docs/metal-backend.md | 1396 | 837 | docs/history/metal-backend.md (684): the story of tasks 023 to 040, the Metal shell's numbers, why one queue, the frame-time runs, the pre-warm coverage, the texture-mapping, mipmap and colour-test checks, the 3D and race checks' numbers, every task's Verify numbers |
| docs/verification.md | 766 | 717 | docs/history/verification.md (238): the suite's first five scenes and task 035's thirteen with their first runs, the re-baselines, the HUD check before task 031, task 034's wall times, task 051's log diff, the M4 audio checks, the reverb's steps, the VFPU breakpoints and rebuild figures, task 050's equivalence checks. New in the reference: a table of every check, the suite's 18-scene table as the script has it, `tools/purelib`, "The docs check" |
| docs/ge-backend.md | 477 | 407 | docs/history/ge-backend.md (371): the design of 2026-10-06, the order of work, what tasks 021, 022 and 026 landed and measured. The reference gives the interface, the backends, the selection with the Metal shell, the vendor files and the .gerec format with the Draw record field by field in patch 0004-ge-backend-and-shell-seams' final form; sections 2, 7 and 8 keep their subjects (code cites them) |
| docs/ge-effects.md | 543 | 249 | docs/history/ge-effects.md (344): task 008's confirmation and pre-fix diagnosis, the stencil and attachment results (tasks 009, 011), the environment draws (010), the flare with and without the write-back and its cost (019), the reproduction commands |
| docs/tracks.md | 497 | 393 | docs/history/tracks.md (142): the run tables of tasks 017, 018 and 032, the port lines against PPSSPP's |
| docs/release.md | 176 | 163 | docs/history/release.md (32): the setup before 16718e6, the hand-made installation of task 029 |
| docs/status.md | 220 | 177 | docs/history/sessions.md (140): the three Resume sections (sessions 1 to 4) and the milestone table as it stood. Milestone rows one line each (P0, M1 current; M9 added), Works and Blockers kept with the new patch names (three rows added), Follow-ups kept with 11 resolved rows moved to a Resolved list at the end, Resume cut to the branches, the gate, the running task and the open calls |
| docs/timing.md | 72 | 82 | none (a dated note): the stale "patch 0002 or src/hle/display_pure.cpp" replaced by what the framework does; the open lock-field questions answered from the audit; the race clock's file and the busy-time charge added |
| docs/savedata.md | 219 | 220 | none (dated notes): patch names; the autosave after a finished race (found by the audit); the round trip's pilot check fixed in task 045's review |
| README.md | 168 | 206 | none: Layout (directories and key files; `gen/` was `generated/`, `game/`, `third_party/`, the build files added; the Metal shell's `metal_shell.cpp` role) and a new Tools table naming every file under tools/; the framework line (PortableKit, D-001); the Play section (the setup works since 16718e6); `PURE_NO_FB_TEXTURES` row added; patch names |
| docs/decisions.md 191 to 193, docs/scorecard.md 157 (same), ref/README.md 411 to 412, docs/ppsspp.md 164 to 166, patches/README.md 267 to 269 (wording), docs/setup.md 39 to 36, docs/devmenu.md 36 (same) | | | patch names; pointers to moved sections; ppsspp's dated status; a stale self-reference and a switch's name |

Not split, and why: docs/vendor-map.md, docs/codegen-baseline.md, docs/research.md, docs/setup.md and docs/devmenu.md
are spike reports (each a dated record as a whole); docs/scorecard.md is written by `tools/scorecard.py --full`;
docs/controls.md and docs/upstream.md have no per-task history (upstream.md's "old NNNN" are on purpose).

Comments (comments and unprinted docstrings only): tools/gerec/gerec_dump.py, tools/gerec/metal_check.sh,
tools/save_roundtrip.sh, tools/save_interchange.sh, tools/vfpu_model.py, tools/vfpu_probe.py,
src/tools/ge_replay.{cpp,hpp}. `tools/build.sh profile` rebuilt the touched file.

`tools/docs_check.py`: paths (`tools/`, `src/`, `config/`, `docs/`, `packaging/`, `third_party/`, in prose and code
blocks; braces, globs, stems and placeholders such as TRACK), relative links with their `#anchors`, patch names
(`NNNN-slug` must be a file in patches/; a bare "patch NNNN" is reported unless marked "old"), `docs/tasks/NNN`. It
skips the task files, path-checks neither the spike reports about other repositories nor the history files, and lets a
history file cite an old patch by the name patches/README.md's mapping table gives it. Documented in its header and
in docs/verification.md, "The docs check".

How the moves were checked: for each split doc, every non-empty line of the batch/m2 version was looked up in the new
reference plus its history file (whitespace normalised); the lines not found verbatim (26 to 56 a doc) are the ones
this task edited on purpose (patch names, headings without dates, the rewritten openings and status rows), and the old
milestone rows went to docs/history/sessions.md so none of them is lost.

Commits: 59856ba to 9850dfd on task/053-docs-pass (24) and this Result, one doc or one kind of change each.

### Verify output (last 20 lines)
```
verify 053: python3 tools/docs_check.py && tools/frame_regress.sh --only race_hud
docs_check: 31 files, 0 findings: PASS
frame regression 2026-10-07 19:15, commit 9850dfd, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a0377aad2caee7814/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 6s)
verify 053: PASS
```
(`tools/verify_task.sh 053` at 9850dfd, the last commit before this Result; the earlier run at a4c7c7f gave the
same.)

### Open questions
1. **Old numbers left outside May touch.** `tools/scorecard.py` prints "patch 0019" in two strings (lines 1038 and 1225,
   the Saves note and the header it writes into docs/scorecard.md), so the next `--full` run writes the old number back
   into docs/scorecard.md (docs_check would then report it). `tools/vfpu_model.py` prints "since patch 0020" and labels
   `pre0020` "the port before patch 0020"; its and `tools/vfpu_probe.py`'s module docstrings are their `--help` text;
   `vfpu_probe.py` writes "patch 0020" into the harness source it generates. `config/pad_scripts/frontend.txt` and
   `main_menu.txt` say "Measured ... after patch 0002" (config/ is must-not-touch). The three vendor comments task 052
   named stay. A small tools task could switch the printed strings.
2. **CLAUDE.md** says "Tests live in `tests/` and are built by `tools/build.sh profile`"; there is no tests/ directory.
   CLAUDE.md is outside May touch.
3. **`tools/gerec/metal_check.sh`** sets only `PURE_NO_TEXMAP=1` for the race A/B; a recording made now carries mip
   levels and the colour test, which Vulkan does not draw, so a fresh recording would need `PURE_NO_MIPMAPS=1` (and
   `PURE_NO_COLOR_TEST=1 PURE_NO_DITHER=1`) too. The docs say so; the script is the existing follow-up of task 040.
4. **Judgement calls**: docs/tracks.md keeps "What the follower has to work with" (task 016) as reference, since it is
   what anyone tuning the follower needs; docs/ge-backend.md keeps the cold-replay decay table in section 7, since
   `tools/gerec/replay_check.sh` cites that section for why `race.gerec` cannot match cold. Either could move.
5. **docs_check's reach**: it does not check `ref/` paths (the captures are git-ignored, so a fresh clone lacks them),
   `out/` paths, vendor paths, or plain-text section names ("docs/fidelity.md, "Difference 8"") that are not links;
   the code comments that cite the fidelity doc's difference numbers and item 3 still find them in the new reference.

### Statements marked unverified
- docs/verification.md, "Frame regression suite": the Metal window path's time for the 18 scenes (only the five-scene
  time of 7 minutes and the Vulkan path's 19m 47s for 18 were measured).

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
