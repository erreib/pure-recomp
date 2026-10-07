# 050: One shared runner for the tools (the organisation pass, 2 of 5)

Milestone: M9 organisation | Branch: task/050-tools-shared-runner | Status: OPEN

## Goal
The Python tools each grew their own copy of "run the game headless with this route, wait for the one-game guard,
read the log": tools/scorecard.py (12 subprocess sites), tools/fidelity_audit.py (3), tools/campaign_sweep.py,
tools/vfpu_probe.py, tools/hud_check.py, tools/ai_seed_check.sh's Python, and the PPSSPP side through
tools/ppsspp/ppsspp_ctl.py. This task puts the shared parts in one module and makes the tools use it, with every
tool's own check passing unchanged.

## Read first
- CLAUDE.md, docs/verification.md (every tool's section), README.md (the tools table and the switches), docs/tasks/034
  (Result: scratch data directories, silent runs, `PURE_PACED_FROM`), docs/tasks/044 (Result: the scorecard's
  `clean_env`, `port_run`, the one-game wait), docs/tasks/035 (the audit's `run_cell`)
- tools/run_boot.py (the runner every Python tool ends up calling; its flags), tools/scorecard.py, tools/fidelity_audit.py,
  tools/campaign_sweep.py, tools/hud_check.py, tools/vfpu_probe.py, tools/ai_seed_check.sh, tools/pp_lines.py,
  tools/ppsspp/ppsspp_ctl.py (library use)

## Deliverable
1. `tools/purelib/` (a package; or one module `tools/pure_run.py` if that is all it needs) with: the repository root
   and binary location (`build/arm64/bin/PureNative`, the worktree rule), the clean environment for a port run (no
   inherited `PURE_*`/`PSPRECOMP_*`), a scratch data directory per tool, the one-game guard wait with the same message
   and `--allow-parallel` behaviour the tools have today, a headless run (shell, backend, route or input script,
   frames, paced-from, extra environment, log path) returning exit code, the frame reached and the log, the common
   log readers (the `[pure]` grid and ship lines, the `[metal]` exit lines, `[hle-stub]` lines, the WAV capture path),
   and the PPSSPP driver's shared-use wait (one instance, a clean memory stick) as the scorecard does it. Every
   function documented in one line.
2. The tools above using it, their own code shrinking accordingly, and their command lines, outputs and file layouts
   unchanged (other tools and docs depend on them: tools/verify_task.sh, the briefs' Verify lines, docs/scorecard.md).
   Bash tools stay bash; tools/frame_regress.sh is not touched.
3. The checks, each unchanged in its result: `python3 tools/scorecard.py --selftest && python3 tools/scorecard.py
   --quick --out out/050` (the same grades as docs/scorecard.md's quick run), `python3 tools/campaign_sweep.py
   single_race vineta_k --no-damage` (PASS), `tools/hud_check.sh --shell headless` 61 of 61, `python3
   tools/vfpu_probe.py port ref/vfpu/jit` then `python3 tools/vfpu_model.py --check ref/vfpu` PASS,
   `tools/ai_seed_check.sh` (Vineta K: the same two rows as docs/fidelity.md's patch 0021 table), and
   `tools/fidelity_audit.py --selftest` if it has one (else its `--list` on the cached matrix).
4. docs/verification.md: a short section on the module; README.md's tools row if a path changes (it should not).

## Acceptance criteria
- [ ] Every check in deliverable 3 passes with the same result as before the change.
- [ ] The duplicated runner code is gone: no tool keeps its own subprocess call to PureNative or its own guard wait.

## Verify
`python3 tools/scorecard.py --selftest && python3 tools/scorecard.py --quick --out out/050 && tools/hud_check.sh --shell headless && python3 tools/vfpu_model.py --check ref/vfpu`

## May touch
- tools/*.py (the tools named), tools/purelib/ (new), tools/ai_seed_check.sh (its Python part), docs/verification.md,
  README.md

## Must not touch
- src/, vendor/, patches/, config/, tools/frame_regress.sh, tools/run_boot.py's command line (its flags are the
  contract; its internals may move into the module if run_boot.py then calls it), ref/ (read only), the tools'
  command lines and output formats

## Estimated turns
50

## Escalate when
A tool's check changes its result after the move (report which and the diff: that is a behaviour the copies did
not share, a finding), or two tools' guard or environment rules turn out to conflict (report both; do not pick one
silently).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
