# 050: One shared runner for the tools (the organisation pass, 2 of 5)

Milestone: M9 organisation | Branch: task/050-tools-shared-runner | Status: MERGED (7ed295e, 2026-10-07)

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
Status: DONE. The shared parts are in the package `tools/purelib/` (port, logs, ppsspp), the tools use it, and every
check of deliverable 3 gives the same result as on the unchanged tools (the before runs are in `out/050/before/`).
The Verify line passes (`tools/verify_task.sh 050`, exit 0). Neither escalation applies: no check changed its
result, and the guard and environment rules that differ between tools were moved as they were, each kept and
reported below (none was picked over another). The coordinator's addition is in too: every headless port run the
runner starts gets `PURE_NO_BUSY_CLOCK=1` unless the caller names it, and the checks gave the same results with it.

What the module holds (docs/verification.md, "The shared runner: tools/purelib", has the table):
- `purelib.port`: `ROOT`, `EXE`, `GAME` and `main_checkout()` (the worktree rule); `clean_env` (both environment
  rules, below); `scratch_data_dir`, `silence`, `steady_clock`; `fresh_stick`; `other_games`, `refuse` (the sweep's
  guard and message), `wait_until`, `wait_game`, `waited` (the scorecard's wait and its waiting time); `PtyRun` (the
  pty runner run_boot.py and the sweep each had a copy of); `headless_run` (the scorecard's run_boot.py command line,
  returning exit code, exit frame and log); `run_tool`.
- `purelib.logs`: the ship, player, grid, frame-exit, `[hle-stub]`, start-up list, halt, `[metal]` exit, GE exit list
  and underrun formats, and the readers `exit_frame`, `grid_samples`, `metal_exit`, `metal_pipelines`, `ge_ignored`,
  `unimplemented`, `wav_files`, `wav_channel`.
- `purelib.ppsspp`: `wait_free` (one PPSSPP, no profile on its stick: the scorecard's wait), `stick_snapshot` and
  `stick_restore` (vfpu_probe's), `profiles`, `savedata`.
Every function has a one-line docstring.

Changed (lines before and after, base 28e5e34):

| File | Before | After | What moved out |
|---|---|---|---|
| `tools/run_boot.py` | 342 | 228 | the pty loop (now `PtyRun`), `scratch_data_dir`, `silence`, `other_games` (re-exported under their names: `frame_regress.sh` and `sas_reverb_check.sh` import `run_boot.other_games`), the stub regexes; new: the steady clock for runs without a window and without `--sound` |
| `tools/campaign_sweep.py` | 1687 | 1589 | class `Port` (now `PtyRun`), the memory stick, the refusal, the ship, player, frame and halt regexes (re-exported for the audit); new: the steady clock for headless cells without `--sound` and for `--record-line` |
| `tools/scorecard.py` | 1885 | 1775 | `clean_env`, `main_checkout`, `other_game`, `wait_until`, `wait_game`, `WAITED`, `ppsspp_profiles`, `wait_ppsspp`, `ppsspp_saves`, `Ctx.make_stick`, the run_boot.py command line of `port_run`, `ge_ignored`, the subprocess calls of the suite, the sweep cells, `ppsspp_ctl.py run` and `--ppsspp-race` |
| `tools/fidelity_audit.py` | 873 | 855 | its cells' environment (now `clean_env(drop=CELL_DROP)`), the sweep call, the WAV paths, the ship, player, unimplemented, `[metal]`, GE and underrun regexes and the `[metal]` exit parsing |
| `tools/vfpu_probe.py` | 814 | 793 | `stick_snapshot`, `stick_restore`, the borrowed `sc.wait_ppsspp` |
| `tools/pp_lines.py` | 285 | 260 | `GRID_RE`, `PLAYER_RE`, `RACE_OVER`, `port_samples` (now `logs.grid_samples`, imported under the old name) |
| `tools/ai_seed_check.sh` | 171 | 172 | its Python's `sc.wait_ppsspp` (now `wait_free`); the line-15 comment now names `src/profile/test_hooks.cpp` |
| `tools/hud_check.py` | 70 | 70 | nothing: it reads shots and starts no run; its run is `hud_check.sh`'s (bash) through run_boot.py |
| `tools/purelib/` (new) | 0 | 526 | `__init__.py` 14, `port.py` 331, `logs.py` 128, `ppsspp.py` 53 |
| `docs/verification.md` | | +39 | the section "The shared runner: tools/purelib", with the steady-clock line |

README.md is unchanged: no path changed. Commits: 2cfe95d, 1a0840c, a0a152b, 7e4ea37, e7fdb22, 683646e, 11b4b92,
c0ead31, d1bc474, f34a1eb, f02edac, 6fea8d8, 0c7345d and the Result commit.

The checks, before (unchanged tools, 17:44 to 17:52) and after (the move, 17:59 to 18:09; with the steady clock,
18:14 to 18:19; the Verify run, 18:19 to 18:23), each output kept under `out/050/before/`, `out/050/after/`,
`out/050/after2/`, the diffs in `out/050/compare_refactor.txt` and `out/050/compare_steady_clock.txt` (times masked):

| Check | Before | After the move | With the steady clock | Diff |
|---|---|---|---|---|
| `scorecard.py --selftest` | PASS, 28 checks | PASS | PASS | identical |
| `scorecard.py --quick --out out/050` | pictures faithful, timing close, saves close, coverage close | the same | the same (also the Verify run) | 0 of 53 rows differ in measure, port value, reference, difference, grade or note (race_hud 0.0148, Blue Ridge 0.0247, Sinucit 0.0877, Sebenco Climb 0.2984, stretches 3 against 0, load 0.30 s accepted, 30 GE commands); the only stdout difference is two lines of the after run, `waiting: another PureNative is running (...)` and `free after 30 s`, and the wall line's `of it 0m 30s waiting`: another worker's game ran, and the moved wait waited for it with the same words |
| `campaign_sweep.py single_race vineta_k --no-damage` | PASS, flip 17540, laps 66.6, 59.5, 55.1 s, 48 contacts, 198 s | PASS, flip 17890, laps 63.7, 60.0, 61.1 s, 40 contacts, 203 s | PASS, flip 17850, laps 64.0, 60.3, 62.5 s, 41 contacts, 202 s | the outcome is the same; the laps differ as every paced, closed-loop cell's do from run to run (task 034's two runs: 61.2/61.9/60.3 and 61.6/58.8/64.0 s) |
| `hud_check.sh --shell headless` | 61 of 61 | 61 of 61 | 61 of 61 (also the Verify run) | identical, `summary.txt` too (yellow counts per shot) |
| `vfpu_probe.py port ref/vfpu/jit` | 195 sites | 195 sites | not rerun (no port run in it) | identical; the 2667 port result files have the same SHA-256 |
| `vfpu_model.py --check ref/vfpu` | PASS | PASS | PASS (the Verify run) | identical |
| `ai_seed_check.sh` | Vineta K player faithful (0.00 m), AI close (18.54 s, 2.85 m), so FAIL (exit 1) | the same | the same | identical; these are the two rows of docs/fidelity.md's patch 0021 table |
| `fidelity_audit.py --list --out out/035-wip/fidelity` (no `--selftest`) | 46 of 46 (36 PASS, 10 STALL); complete | the same | the same | identical |

Beyond the brief's checks, against the code before the move:
- `PtyRun` against the old run_boot.py and the sweep's old `Port`, on a stand-in for PureNative in six ways a run ends
  (frame exit with an unterminated last line, deadline, SIGSEGV, exit 3, a slow writer, a 30,000-line flood with
  repeats), each with the default cap and a cap of 12: identical logs (elapsed time masked), stdout, stub summaries,
  lines handed to the caller and exit codes (`out/050/run_boot_cmp.txt`, `out/050/sweep_cmp.txt`).
- `fidelity_audit.py --rescan` of the cached 46-cell matrix by the old and the new audit, each on a copy of the
  cells: identical cell JSON, `matrix.md`, `features.md` and output (`out/050/rescan-old`, `out/050/rescan-new`).
- `pp_lines.py --port` on a real `PURE_WATCH_GRID` log (the ai_seed_check race), old and new: identical samples and
  output (`out/050/pp_lines/`).
- The environment each runner gives the game, checked on the stand-in: `PURE_NO_BUSY_CLOCK=1` without a window, with
  `--shell headless` and through `headless_run` (also when the shell had set it: the scorecard's clean environment
  drops it); unset with `--window`, `--shell metal`, `--script` (a window), and `--sound`; the caller's value kept
  from the environment or `--env`. In the sweep: `1` for a headless cell, unset for `--shell metal`, `--shell vulkan`
  and a headless cell with `--sound`.

Verify output (last 20 lines; `tools/verify_task.sh 050`, exit 0; above them `scorecard: pictures faithful, timing
close, saves close, coverage close` in 50 s and `hud_check: 61 of 61 shots have the HUD` in 13 s):
```
  transcendentals (the port's helper against PPSSPP):
  vrcp.s     2 sites,    2562 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 0 (max 0 ulp); port: 1.0f / x: 2562/2562
  vrsq.s    23 sites,   11249 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 3524 (max 1 ulp); port: 1.0f / sqrtf(x): 11249/11249; 1 / sqrt(x) rounded once: 7725/11249
  vsqrt.s   27 sites,   26023 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 0 (max 0 ulp); port: fabsf(sqrtf(x)): 26023/26023
  not in these samples: vsin, vcos, vexp2, vlog2, vasin (tools/vfpu_probe.py scan: vsin and vcos have two sites each, which the race did not run; vexp2, vlog2 and vasin occur nowhere in the executable)
ref/vfpu/jit/048_vineta_k: PPSSPP's JIT (CPU core 1), vineta_k to race clock 13.01 s; the ships end 0.149 m or less from the reference race
  vfad.t (result lanes)                    sequential               364118/364118 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 364118/364118 (100.000%); default mode = hw 179152/364118 (49.202%)
  vcrsp.t (result lanes)                   unfused                  766986/766986 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 582085/766986 (75.893%); default mode = hw 766986/766986 (100.000%)
  vfad.q (result lanes)                    sequential               184512/184512 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 184512/184512 (100.000%); default mode = hw 158833/184512 (86.083%)
  vfad.p (result lanes)                    sequential               6304/6304 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 6304/6304 (100.000%); default mode = hw 3842/6304 (60.945%)
  vmscl.q (result lanes)                   ieee                     1524032/1524032 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 1524032/1524032 (100.000%); default mode = hw 1524032/1524032 (100.000%)
  transcendentals (the port's helper against PPSSPP):
  not in these samples: vsin, vcos, vrcp, vrsq, vexp2, vlog2, vasin (tools/vfpu_probe.py scan: vsin and vcos have two sites each, which the race did not run; vexp2, vlog2 and vasin occur nowhere in the executable)
vfpu_model --check: PASS
verify 050: PASS
```

Open questions:
1. **The rules that differ between tools, all kept as they were (the brief: report both, pick none).**
   - Environment, three rules. `run_boot.py` and the sweep inherit the whole environment (the sweep keeps
     `PURE_SHELL`, `PURE_GE_BACKEND`, `PURE_PACED_FROM` from it). The audit's cells drop only `PURE_TRACE_*`,
     `PURE_AUDIO_WAV`, `PURE_TEST_NO_DAMAGE`, `PURE_TEST_UNLOCK_ALL` and `PURE_METAL_TRACE`, and pass the rest to the
     sweep. The scorecard's runs drop every `PURE_*` and `PSPRECOMP_*` but `PURE_ROOT` and `PURE_MAIN_CHECKOUT`. So
     the same shell (say `PURE_GE_BACKEND=vulkan` exported) gives audit cells on Vulkan and scorecard runs on Metal.
     `clean_env()` and `clean_env(drop=...)` hold both; which one a new tool should take is Erik's or Fable's call.
   - One game at a time, two behaviours. The sweep refuses (exit 2, `--allow-parallel` to start anyway), and the audit
     stops when its sweep refused; the scorecard waits (10 s polls, an hour a wait, then runs anyway; no
     `--allow-parallel`). `run_boot.py` and `hud_check.sh` do not check. Both are `purelib.port` functions now.
   - Exit codes: a game killed by a signal is 128 plus the signal in run_boot's exit line and status, the negative
     status in the sweep's `[sweep] exit` line (`PtyRun.code(signals=...)` keeps each).
   - PPSSPP: `save_interchange.sh` keeps its own bash wait (PPSSPP only, 30 minutes, no check of the stick for a
     profile); it is bash and outside "May touch".
2. **Small differences the move made, none visible in a check.**
   - The sweep's memory stick now links `disc.iso` to the image itself, as the scorecard's, `frame_regress.sh`'s and
     `hud_check.sh`'s do, instead of to `game/disc.iso` (the same file one link further).
   - The scorecard's "frame reached" reads the number of the `[pure] exit at frame N` line (`logs.exit_frame`) instead
     of looking for the text `[pure] exit at frame <frames>` anywhere in the log.
   - `vfpu_probe.py` and `ai_seed_check.sh` still print their PPSSPP waiting lines with `[scorecard]` (they pass the
     scorecard's `say`, as their output was), so their outputs did not change.
3. **Not moved: the PPSSPP session.** The block that opens an `IniSession`, launches PPSSPP, connects, waits for the
   boot, pins the RTC and starts the replay is written four times (`scorecard.pp_race`, `fidelity_audit.ppsspp_race`,
   `vfpu_probe.ppsspp_race`, `ai_seed_check.sh`'s `take`), each with its own extras (renderer, CPU core, audio dump,
   breakpoints). The brief's list for PPSSPP is the shared-use wait, and no check of deliverable 3 runs PPSSPP, so a
   move there could not have been shown unchanged here. A candidate for a follow-up with a PPSSPP run to compare.
4. **The steady clock.** The framework reads `PURE_NO_BUSY_CLOCK` by its presence, so any value turns the charge off;
   a headless run through the runners cannot keep the charge except with `--sound` (run_boot.py, the sweep) or a
   window. `vfpu_probe.py` (the coordinator's "the probe") starts no port run (PPSSPP and the compiled harness only),
   so it has nothing to set. README.md's switch table has no `PURE_NO_BUSY_CLOCK` row; the table is the part task
   051 rewrote on batch/m2, so the row is better added after this branch is merged.
5. **Base.** The branch starts at 28e5e34 (as the setup said); batch/m2 has since gained tasks 051 and 052. None of
   their files is one this branch changes except docs/verification.md (a different place), so the merge should be
   clean. The comment in `ai_seed_check.sh` names `src/profile/test_hooks.cpp`, which exists from task 051 on.
6. **The brief's `vfpu_probe.py port ref/vfpu/jit` rewrites `ref/vfpu/jit/<ADDR>.port.csv`** under the default
   rounding mode (no `--modes`). Of this worktree's 2667 port files the run rewrites 195, 139 of them with hashes
   that differ from the main checkout's copies (made under another mode or build, I did not find which); the
   rewritten files are the same before and after the move, and `--check` passes on them. Run in the main checkout,
   that check of deliverable 3 overwrites its files too.

## Review
Verify rerun: PASS from the main checkout at 7ed295e (2026-10-07): scorecard selftest and `--quick` (pictures
faithful, timing close, saves close, coverage close), HUD 61 of 61, `vfpu_model --check` PASS.

Spot-read: tools/purelib (port, logs, ppsspp; one-line docstrings; both environment rules and both guard behaviours
kept as functions rather than one picked), the tools' diffs (internals only; command lines and outputs unchanged),
the steady clock set for headless runs and left off for windowed and `--sound` runs, the PtyRun equivalence test on
a stand-in game in six ways a run ends. Files outside May touch: none.

Merged: 7ed295e into batch/m2.

Notes: the differing rules between tools (three environment rules, two guard behaviours, two exit-code forms) are
recorded, not resolved; a new tool should take `clean_env()` and the scorecard's wait. The PPSSPP session block is
still written four times (a follow-up with a PPSSPP run to compare). `vfpu_probe.py port ref/vfpu/jit` without
`--modes` rewrites the set's port files under the default mode; the checks use `--modes`. README gains the
`PURE_NO_BUSY_CLOCK` row here, after the merge.
