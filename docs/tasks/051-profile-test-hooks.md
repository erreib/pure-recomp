# 051: The test-only switches out of the profile (the organisation pass, 3 of 5)

Milestone: M9 organisation | Branch: task/051-profile-test-hooks | Status: MERGED (f7dbc43, 2026-10-07)

## Goal
src/profile/pure_profile.cpp (668 lines) mixes the game's real profile (the executable, memory, the HLE overrides,
the savedata names, the lens-flare depth write-back) with fourteen test-only switches and probes: `PURE_TEST_NO_DAMAGE`,
`PURE_TEST_UNLOCK_ALL`, `PURE_TEST_RACE_CLOCK`, `PURE_WATCH_GRID`, `PURE_WATCH_SHIP`, `PURE_WATCH_MOVIE`,
`PURE_WATCH_RAND`, `PURE_WATCH_WORDS`, `PURE_TRACE_RAND`, `PURE_TRACE_CALLS`, `PURE_VFPU_DOT`, `PURE_PACED_FROM`,
`PURE_EXIT_AT_FRAME`, `PURE_FRAME_LOG`. This task moves the test instruments into their own file behind one seam, so
the profile reads as the game's port and the instruments as what they are, with no change in behaviour.

## Read first
- CLAUDE.md, README.md (the switches table: which are test-only, which a player may use), docs/tasks/017, 032, 046
  (Results: the shield probe, the GPI override, the race clock), docs/timing.md
- src/profile/pure_profile.cpp (all of it), src/host/pure_main.cpp, src/hle/ (what the profile registers), the
  framework's profile interface (vendor/portablekit/include/psprecomp/ or host/, read only: what hooks a profile may
  install and when)

## Deliverable
1. `src/profile/test_hooks.{hpp,cpp}`: every test-only switch and probe, installed through one call the profile makes
   at start (`test_hooks::install(...)`) with the hooks it needs (the per-flip hook, the GPI answer, the time answer
   under the race clock, the rand hooks, the watch probes), each switch in its own function with the README row's
   text as its comment. The profile keeps what a player's game uses (`PURE_PACED_FROM`, `PURE_EXIT_AT_FRAME`,
   `PURE_FRAME_LOG` are run-control, not test instruments: decide from the README whether they stay or move, and say
   why). The switches' names, log lines and effects are unchanged.
2. The proof of no change: a headless run with every switch on, before and after, with identical logs (modulo
   timestamps): `PURE_TEST_UNLOCK_ALL=1 PURE_TEST_NO_DAMAGE=1 PURE_WATCH_GRID=1 PURE_WATCH_SHIP=1 PURE_WATCH_RAND=1
   PURE_TRACE_RAND=1` over the Vineta K single-race route to frame 6500, the two logs diffed; and `tools/ai_seed_check.sh`
   (Vineta K) giving the same two rows as docs/fidelity.md's patch 0021 table; `tools/frame_regress.sh` 18/18 at the
   same values; `python3 tools/campaign_sweep.py single_race vineta_k --no-damage --unlock-all` PASS.
3. docs: README.md's switches table marks each row test-only or run-control (one word in the row, where it is not
   already said); a short "Test hooks" section in docs/verification.md.

## Acceptance criteria
- [ ] The before and after logs of the all-switches run are identical apart from timestamps.
- [ ] `tools/frame_regress.sh` 18/18 unchanged; `tools/ai_seed_check.sh` unchanged; the sweep cell passes.
- [ ] pure_profile.cpp holds no `env("TEST_`/`env("WATCH_`/`env("TRACE_` read; test_hooks.cpp holds them all.

## Verify
`tools/build.sh profile && tools/frame_regress.sh --only race_hud && tools/ai_seed_check.sh`

## May touch
- src/profile/ (the split), CMakeLists.txt (the new file), README.md (the table's words), docs/verification.md

## Must not touch
- vendor/, patches/, src/gpu/, src/host/, src/hle/ (unless a hook seam needs one line, then say so), config/, tools/,
  the switches' names and effects

## Estimated turns
35

## Escalate when
A switch cannot be moved without changing when it takes effect (report which and why: that ordering is a finding),
or the framework offers no hook point for one and it would need a vendor change.

## Result
Status: DONE. All three acceptance criteria hold. The Verify line exits 1, as it did before this change. Its build
and `frame_regress.sh --only race_hud` steps PASS. Its last step, `tools/ai_seed_check.sh`, FAILs by its own rule
(every row faithful): Vineta K's AI row is `close` at 18.54 s, 2.85 m, the row in docs/fidelity.md's patch 0021
table. That row is the same before and after the change.

### What moved and what stayed
- **Moved:** `src/profile/test_hooks.{hpp,cpp}` (new) hold eleven switches: `PURE_TEST_NO_DAMAGE`,
  `PURE_TEST_UNLOCK_ALL`, `PURE_TEST_RACE_CLOCK`, `PURE_VFPU_DOT`, `PURE_WATCH_MOVIE`, `PURE_WATCH_SHIP`,
  `PURE_WATCH_GRID`, `PURE_WATCH_RAND`, `PURE_WATCH_WORDS`, `PURE_TRACE_RAND` and `PURE_TRACE_CALLS`. The ship lookup
  and the memory helpers they share moved with them. Each switch has its own function, commented with its README
  row's text and then the finding that was there before. The code was moved, not rewritten.
- **The seam:**
  - `test_hooks::install(hle)` is the one call at start, from `register_pure_hle`. It prints the switches' start-up
    lines, wraps the frame timer for the race clock and the calls `PURE_TRACE_CALLS` names, and returns
    `Hooks{gpi}`. The profile binds that answer to `sceKernelGetGPI`: 0 as on retail, 1 under the unlock switch or
    a race clock file's `unlocked 1`.
  - `test_hooks::flip(rt, frame)` is the per-flip hook. The profile's flip counter calls it before the game's own
    `sceDisplaySetFrameBuf`.
- **Stayed in the profile:** `PURE_EXIT_AT_FRAME`, `PURE_FRAME_LOG` and `PURE_PACED_FROM`, which are run-control.
  - README lists them in the main switches table, not under "Test switches (never for play)". The rows there change
    the game's rules and print a `TEST SWITCH` line. These three change no rule and watch nothing: they end a run,
    print a frame count, or set the pace.
  - The flip counter that carries them is also where the test hooks hang.
  - The retail GPI answer stays as well, since it belongs to the port.
- **The acceptance grep:** `pure_profile.cpp` (668 lines before, 201 after) reads only `PACED_FROM`,
  `EXIT_AT_FRAME` and `FRAME_LOG`. Every `TEST_`, `WATCH_`, `TRACE_` and `VFPU_DOT` read is in `test_hooks.cpp`.
- **Every effect happens at the same moment as before:**
  - Binding order: the flip counter, then the frame timer, then the call traces, then the audio capture, then GPI.
    So `PURE_TRACE_CALLS` still wraps the flip counter and the replayed timer, and a GPI trace is still replaced.
  - The native `srand()`/`rand()` copies and `PURE_VFPU_DOT` are still set at the first flip. The race clock's
    rounding is still set when its file is read.
  - No switch had to change when it takes effect, so the escalation did not apply.

### The log diff (deliverable 2)
Each run is the Vineta K Single Race route (`main_menu.txt` + `single_race.txt`, no shots) to flip 6500. Every run
was headless on the Metal backend, silent, and on an empty stick of its own (`out/051/switch_runs.sh`). The diff masks
only the framework's wall-clock figures (`out/051/norm.py`): the `[metal]` ms, fps and GPU-wait counts, and the
`[run_boot]` time. Every `[pure]` and `[call]` line, `t=` included, is compared byte for byte. The "before" build is
28e5e34, the "after" build is 477eff7.

| Run | Switches | Lines | before vs before | after vs after | before vs after |
|---|---|---|---|---|---|
| all (the brief's) | `PURE_TEST_UNLOCK_ALL PURE_TEST_NO_DAMAGE PURE_WATCH_GRID PURE_WATCH_SHIP PURE_WATCH_RAND PURE_TRACE_RAND` | 8969 | 0 | 0 | **0: identical** |
| extra | `PURE_WATCH_MOVIE PURE_WATCH_WORDS PURE_TRACE_CALLS (flip, GPI) PURE_VFPU_DOT=ppsspp PURE_WATCH_RAND=2 PURE_TEST_NO_DAMAGE PURE_FRAME_LOG=100 PURE_PACED_FROM=100000` | 20398 | 0 | 0 | 66 lines in another place, 0 as a multiset |
| clock | `PURE_TEST_RACE_CLOCK=ref/race_clock/vineta_k.txt PURE_TEST_UNLOCK_ALL PURE_WATCH_SHIP PURE_WATCH_RAND PURE_TRACE_CALLS (flip, timer)` | 14875 | 0 | 0 | 0: identical |

The table's figures are with `PURE_NO_BUSY_CLOCK=1`, two runs per build. The first runs, made without it, agreed
the same way (all run: 0 lines before against after) except twice, explained below.

What moved in the extra run, and why:
- **Start-up:** one `install` call puts the test lines in one block after the profile's own. The no-damage
  `TEST SWITCH` line now comes after `[pure] PURE_PACED_FROM=100000: ...` instead of before it. With
  `PURE_AUDIO_WAV`, its `audio capture: mix ->` line would now come after the unlock lines.
- **Within a flip:** 65 `[pure] words frame N00` lines now come after `[pure] frame N00`. `PURE_TRACE_RAND`'s
  `rand calls` line moves the same way, beside `[pure] frame N` and `[pure] paced from frame N`. The probes' other
  lines (movie, rand, ship, grid) keep their place after them.

No tool reads these lines by their order (grep of tools/).

**A finding: the busy-time charge.** Two of the twelve runs made without `PURE_NO_BUSY_CLOCK` came out different from
their twins:
- The clock run, after the change, had a 101 ms step at flip 6072 to 6073. Every later `t=` moved, but the game
  state did not, since the race clock replays the frame times.
- The all run, in a second after-run, had a 105 ms step at flip 6428 to 6429. Here the race changed from that flip
  on.
- Their reruns matched the before logs exactly.

The cause is the framework's `Kernel::charge_busy_time`: a thread that runs over 100 ms of wall time without a wait
has that time (up to 250 ms) added to the virtual clock. Other workers' games were loading the machine, so a race
frame sometimes crossed the line. This is the one way a headless run depends on machine load.
`PURE_NO_BUSY_CLOCK=1` turns it off, and with it every run repeated exactly. docs/verification.md "Test hooks" says
so.

### The other checks, before and after
- **`tools/frame_regress.sh`:** 18/18 both times with every fraction equal, for example race_hud 0.0148, zone_change
  0.0369 and tt_hud 0.0113 (`out/051/{before,after}/regress/summary.txt`).
- **`tools/ai_seed_check.sh` (Vineta K):** the same two rows both times, and the same as docs/fidelity.md's patch 0021
  table:
  - player faithful (never over 1 m, largest 0.00 m);
  - AI close (first over 1 m at 18.54 s, largest 2.85 m).

  `scorecard.json` differs only in date, commit and wall time.
- **`python3 tools/campaign_sweep.py single_race vineta_k --no-damage --unlock-all`:** PASS (no damage, unlock all)
  at flip 17390. Laps 61.6, 58.7 and 60.2 s, 38 contacts, 197 s. The log carries both `TEST SWITCH` lines and the
  `PURE_PACED_FROM=6100` line, and its only stop is the script's quit.

### Changed
- `src/profile/test_hooks.hpp`, `src/profile/test_hooks.cpp` (new): the test switches and probes behind
  `install` and `flip`.
- `src/profile/pure_profile.cpp`: the instruments removed. It calls `test_hooks::install` after the flip counter and
  binds the GPI answer it returns. The flip counter calls `test_hooks::flip`.
- `CMakeLists.txt`: `src/profile/test_hooks.cpp` in SOURCES.
- `README.md`:
  - each row of the switches table now starts with `run-control.` or `test-only.`;
  - a sentence above the table says what the two words mean and where the test-only switches live;
  - a new `PURE_TRACE_CALLS` row (it had none).
- `docs/verification.md`: "Test hooks (task 051)" covers what moved and what stayed, the seam and its binding order,
  how the proof was run, the busy-time charge, and the two orders that moved.
- `docs/tasks/051-profile-test-hooks.md`: this Result.

### Verify output (last 20 lines)
```
[2/4] Building CXX object CMakeFiles/PureNative.dir/vendor/portablekit/host/ui/menu.cpp.o
[3/4] Linking CXX executable bin/PureNative
frame regression 2026-10-07 18:03, commit 942d5ca, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 6 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a5b1b14903ea484c6/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 6s)
[ai_seed_check] vineta_k: race clock ref/race_clock/vineta_k.txt
[scorecard] trajectories: close (3 rows, 15 s)
trajectories  close
[scorecard] wrote out/ai_seed_check/scorecard.json and scorecard.md (0m 14s)
  vineta_k          player faithful  first over 1 m: never; largest 0.00 m at 11.71 s
  vineta_k          AI     close     first over 1 m: 18.54 s; largest 2.85 m at 19.99 s
ai_seed_check: FAIL
verify 051: FAIL (exit 1)
```
On 28e5e34, before the change, the same `ai_seed_check` FAIL with the same two rows
(`out/051/before/ai_seed_check.txt`).

### Open questions
1. **Start-up and in-flip line order.** To keep both exactly, `install` would have to be split into three calls
   from the profile: the start-up lines, the wraps, and the unlock lines. The flip hook would have to be split in
   two, around the frame log. I kept the one call the brief asks for. Should the order be exact instead?
2. **The busy-time charge in the tools.** Headless comparisons can move under machine load: the race scenes of
   `frame_regress.sh`, the scorecard's trajectories and `ai_seed_check.sh`. Should the headless tools set
   `PURE_NO_BUSY_CLOCK=1`? That is a tools/ change, so it belongs to the tools pass.
3. **A stale comment.** `tools/ai_seed_check.sh` line 15 still says `PURE_TEST_RACE_CLOCK` lives in
   `src/profile/pure_profile.cpp`. tools/ was must-not-touch here.
4. **The lens-flare depth write-back.** The brief lists it among the profile's contents. On batch/m2 it is patch 0008
   in the vendor tree (`PURE_NO_DEPTH_READBACK`), not in `pure_profile.cpp`, so there was nothing to move.
5. **README classifications to check.**
   - test-only: the framework traces, `PURE_MALLOC_DEBUG`, `PURE_METAL_LOG`, `PURE_METAL_TRACE`,
     `PURE_METAL_SHOW_TARGET` and every A/B switch (`PURE_NO_*`, `PURE_SAS_REVERB_SPU_RATE`).
   - run-control: `PSPRECOMP_NO_INTERPRETER`, `PURE_LIST_STUBS`/`PURE_STRICT_HLE`, `PURE_AUDIO_WAV` and
     `PURE_GE_RECORD` (captures, like screenshots), `PURE_METAL_SHELL=0`, `PURE_METAL_PIPELINES(_OUT)` and
     `PURE_METAL_PACE`.
   - The `tools/campaign_sweep.py` row in the switches table is a tool, not a switch, and is left unmarked. The four
     rows under "Test switches" keep their heading's "never for play".

## Review
Verify rerun: from the main checkout at f7dbc43 (2026-10-07): `tools/build.sh profile`, race_hud 0.0148, and
`tools/ai_seed_check.sh` giving the same two Vineta K rows as before the change (player faithful 0.00 m; AI close at
18.54 s, 2.85 m). The brief's Verify line fails as it did before the task, because `ai_seed_check.sh`'s own PASS rule
(every row faithful) cannot hold on Vineta K's AI row; my brief should have said "the same rows", and the acceptance
criteria, which say that, all hold.

Spot-read: test_hooks.{hpp,cpp} (one `install`, one `flip`, each switch its own function with the README's text;
the binding order kept so `PURE_TRACE_CALLS` still wraps the flip counter and the replayed timer), pure_profile.cpp
(668 to 201 lines, only run-control reads left), the README's run-control/test-only words. Files outside May touch:
none.

Merged: f7dbc43 into batch/m2.

Notes: the run-control three stay in the profile with the reasons given; agreed. The log order moved in two
harmless places (the start-up block, the `words` lines after the frame line), which no tool reads by order; the one
call stays. The finding that matters is the kernel's busy-time charge: headless runs depend on machine load unless
`PURE_NO_BUSY_CLOCK=1`; the shared runner (task 050) now sets it for every headless run, and the stale comment in
tools/ai_seed_check.sh goes with it.
