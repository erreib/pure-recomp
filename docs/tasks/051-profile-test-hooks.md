# 051: The test-only switches out of the profile (the organisation pass, 3 of 5)

Milestone: M9 organisation | Branch: task/051-profile-test-hooks | Status: OPEN

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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
