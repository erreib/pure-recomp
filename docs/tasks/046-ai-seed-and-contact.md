# 046: Why the AI runs a different race, and the Karbonis contact response (scorecard: Trajectories)

Milestone: M8 | Branch: task/046-ai-seed-and-contact | Status: OPEN

## Goal
The scorecard's first run (docs/scorecard.md, task 044) grades Trajectories `differs`: with identical input the
player's ship follows PPSSPP's path within a metre on eight circuits, but the seven AI ships run a different race from
PPSSPP's on every circuit from 0.4 s after GO, and each side repeats itself exactly (two PPSSPP runs agree to 0 m, two
port runs agree to 0 m). So the state the AI starts from differs, not noise. Three player rows (Sinucit, Mandrashee,
Sol 2) move only because an AI ship comes near. Karbonis is separate: the player scrapes a wall at about 30 km/h from
7 s, the port runs 1 to 3 km/h faster through the scrape, and the gap grows to 34 m by 20 s. This task finds what the
AI's start depends on, makes the port match PPSSPP where it is the port's (or pins it for the test where it is the
clock's), and finds where the contact response differs.

## Read first
- CLAUDE.md, docs/scorecard.md (Trajectories: the rows, the method, the references under ref/scorecard/trajectories),
  docs/tasks/044 (Result: how the straight-on runs are taken on both sides, the race records' fields, `--pad`'s
  release, torn reads), docs/tasks/007 (Result: the race records at 0x08B72010 + k*0x1C0, the clock alignment),
  docs/tasks/017 (Result: the collision path in the ship update FUN_08926ae4, the shield field), docs/timing.md (the
  frame limiter, the vblank counts, what runs during a load), docs/decisions.md D-011 (the shorter loads: 0.30 s
  against PPSSPP's 1.50 s before the race; if the AI's start depends on the load's length, that is the "new finding"
  D-011 names and must be reported, not silently fixed), docs/ppsspp.md (the driver pins PPSSPP's RTC base; its log
  levels SCEKERNEL and SCERTC; `memory.read`)
- config/imports.csv: the game imports no Mt19937, so its random numbers are its own code; the time it can read:
  sceKernelGetSystemTime/Low/Wide, sceKernelLibcTime, sceKernelLibcGettimeofday, sceKernelLibcClock,
  sceRtcGetCurrentTick, sceRtcGetCurrentClock(LocalTime), sceRtcGetTime_t, sceDisplayGetVcount
- src/profile/pure_profile.cpp (the probes `PURE_WATCH_GRID`, `PURE_WATCH_SHIP`; how the port answers time if it
  overrides anything; the test switches), vendor/portablekit/host/hle/ (how the framework answers those time calls:
  virtual time from boot, and the RTC base), tools/ghidra/ (Callers and Decompile scripts) and config/function_map.csv

## Deliverable
1. The AI's start. Find the game's random-number source and what seeds it (Ghidra: callers of the time imports around
   the race load; a multiply by a linear-congruential constant or a shift-xor generator reachable from the AI or the
   race setup; `PURE_TRACE_CALLS` or the HLE trace on both sides to compare the values the time calls return and how
   many times they are made before GO). Decide between the candidates with evidence: (a) the clock the port answers
   (then the fix is a test-only pin in the profile, `PURE_RTC_BASE=<ISO time>` or the like, matching the driver's
   base, and the scorecard's trajectory runs use it; a player's game keeps the real clock); (b) the number of frames
   or calls before the race under the shorter load (then report it as the D-011 finding, add a test-only switch that
   holds the load to PPSSPP's length so the scorecard can show the AI matching with it, and leave D-011's decision to
   Erik); (c) something the port answers wrongly (a value, an order, a count: fix it, as a vendor patch 0020 if it is
   the framework's). Whichever it is, show the AI rows of Vineta K and two other circuits going faithful under the
   pin or fix, with the scorecard's own trajectory measure.
2. The Karbonis contact. From the race records on both sides (velocity, position per sample), find where the scrape
   diverges: the first contact sample, whether the speed difference appears at once or accumulates, and which quantity
   differs first (speed along the wall, the normal component, the shield). Then narrow the cause: the collision
   response in FUN_08926ae4's path (task 017), a VFPU operation's result (the framework's interpreter fallback can run a
   function range if a switch exists: check `PSPRECOMP_*` in the framework; a differing result between the interpreter
   and the generated code for that function is the finding and names the instruction), or a time-step difference.
   Fix it if it is small and the port's; otherwise report it with the instruction or function named, as the next task.
3. `tools/ai_seed_check.sh`: runs the scorecard's trajectory measure for Vineta K with the pin or fix in force and
   PASSes when the player and the AI rows are faithful (the references under ref/scorecard/trajectories, taken by
   task 044, are the PPSSPP side; do not retake them unless the finding says PPSSPP's run itself was at fault).
4. docs/fidelity.md: a new difference 13 (the AI's start) with the cause and its resolution, and 14 (the contact
   response) with what was found; docs/timing.md if the load's frame count is the cause; README.md for any switch;
   docs/scorecard.md is regenerated by `tools/scorecard.py --only trajectories` with the switch exported, and its
   Trajectories rows reported before and after.

## Acceptance criteria
- [ ] `tools/ai_seed_check.sh` passes; the scorecard's Trajectories category with the switch in force has every AI row
      of at least three circuits faithful, and the cause is named with evidence in docs/fidelity.md.
- [ ] `tools/frame_regress.sh` unchanged (18/18); a player's game is unchanged unless the cause was the port's own.
- [ ] The Karbonis scrape has a named cause or a named next step.

## Verify
`tools/build.sh profile && tools/ai_seed_check.sh && tools/frame_regress.sh --only race_hud`

## May touch
- src/profile/pure_profile.cpp (test-only switches, probes), src/hle/ (a time answer if it is ours), a vendor patch
  0020 via `tools/patches.sh export 0020-<cause>` for host/hle/ or host/kernel/ time answers only; tools/ai_seed_check.sh
  (new); tools/scorecard.py (only an environment pass-through for the trajectory runs, if needed); tools/ppsspp/routes/;
  docs/fidelity.md, docs/timing.md, docs/scorecard.md (regenerated), README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, the codegen, host/gpu/, src/gpu/, config/, tools/frame_regress.sh,
  tools/campaign_sweep.py, tools/pp_lines.py, ref/scorecard/ (read only), earlier patches

## Estimated turns
60

## Escalate when
The cause needs a change to the generated code or the codegen (report the instruction and the function with both
results), the AI's start proves to depend on something PPSSPP itself does not reproduce between its own runs (report
the evidence), or the contact difference needs more than a probe to localise (report what was measured).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
