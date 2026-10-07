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
Status: PARTIAL. The AI's start is found and pinned for the test, the Karbonis scrape has its cause, and the tool and
the docs are done. The acceptance's "every AI row of at least three circuits faithful" is not met: with PPSSPP's
whole race clock in force, one circuit's AI row is faithful (Mandrashee, 0.46 m), Vineta K's is close (4.05 m) and
ten differ, their first metre now 3 to 16 s after GO instead of 0.4 s. What is left is the escalation case "the
cause needs a change to the generated code or the codegen": the VFPU dot product in
`include/psprecomp/allegrex_context.hpp` (must not touch, full corpus rebuild). The instruction and both results are
below. `tools/ai_seed_check.sh` therefore FAILs (Vineta K's AI row is `close`), and so does the Verify line.

### The cause of the AI's start, with its evidence
The race's random numbers are the C library's `rand()` (FUN_088e0568, an LCG whose state is at +0x58 of the
structure the pointer at 0x08AB1A6C names). Three things decide what the AI draws from it, and one decides the rest:
1. **Two seeds, both clock readings taken at the TEAM SELECTION confirm.** The AI team pick (FUN_0880e0d0) calls
   `srand(low word of sceKernelGetSystemTimeWide)`, the microseconds since boot, then picks the order of the seven
   AI teams. The Billboard constructor seeds FUN_0886011c's shuffle with the frontend root's +0x44, the game's own
   frame clock in seconds, and every later `rand()` of the race continues that sequence. On Vineta K the seeds are
   0x0B61BCDE and 0x433A26F3 (186.152 s) in the port against 0x06AF1873 and 0x42D27933 (105.237 s) in PPSSPP.
   Two port runs agree because the virtual clock is deterministic headless; two PPSSPP runs agree because the
   route is frame-exact. Neither is the RTC, so this is case (a) in spirit, but the clock is the time since boot
   and the game's frame clock, not the RTC base.
2. **The team set.** The pick draws only unlocked teams. The scorecard's `PURE_TEST_UNLOCK_ALL` adds ZONE and
   MEDIEVIL on the Alpha circuits, where PPSSPP's reference unlocks nothing.
3. **The frame times.** The frame timer (FUN_08804390) integrates `sceKernelGetSystemTimeWide` differences, capped
   at 0.067 s. The port's clock moves in 1 ms quanta (the kernel's starvation tick), so its frames measure
   15683/16683/17683 us, where PPSSPP's follow the emulated CPU time (15957 to 17201 us). The intro then draws a
   different number of random numbers (FUN_0886d688 draws only for objects in the camera's frustum): 4594 against
   4591 at GO with the seeds equal.

Evidence on Vineta K, with the worst AI ship and the scorecard's measure:

| Pinned | First AI ship over 1 m | Largest | Player |
|---|---|---|---|
| nothing | 0.38 s | 134.36 m | 0.98 m |
| seeds | 0.40 s | 256.97 m | 0.83 m |
| seeds and team set | 2.17 s | 116.83 m | 0.82 m |
| seeds, team set and frame times | 13.45 s | 4.05 m | 0.02 m |

With all three pinned, the rand state at every flip is one PPSSPP had, to the end of its log (1792 flips, 20.7 s,
on Vineta K; 1791 on Karbonis).

**Not (b), the load.** The port's 5-flip race load and PPSSPP's 34-flip one both draw 2566 numbers. Both run 58
flips from the load's end to the 60 fps switch. The frame timer is not called during the load. So the load's
length does not reach the race, and there is no D-011 finding.

**What remains: the VFPU dot product.** With the seeds, the team set and the frame times all pinned, the ships still
differ in the last bits from the first physics step: Vineta K ship 0's height is 34.907314 against PPSSPP's
34.907318, and its vertical speed -10.305353 against -10.305360. The AI's paths amplify this. PPSSPP logged the ship
code's VFPU operands and results over 3 s, and the framework's own helper, built with the corpus's flags, was run on
the same operands:
- `vdot.t S000,C400,C400` at 0x089196B8 in FUN_08919394: 389 of 1488 results differ, each by 1 ulp.
  - Example: operands 0xBF5A4EEF, 0x3AFE5500, 0x3D0B28A3 give 0x3F3A766B in PPSSPP and 0x3F3A766C in the port.
- `vdot.t` at 0x08926E08 in FUN_08926ae4: 76 of 5848 results differ.
- `vsqrt.s` at 0x089196BC: 0 of 1488 differ.

Why they differ:
- The framework writes vdot as one C++ expression, which clang contracts into a fused multiply-add chain.
- The VFPU (as PPSSPP models it) truncates aligned products before rounding.

That is the next task. It means changing `execute_vfpu_vdot*` and the dot product inside vmmul, vtfm and vhdp, then
rebuilding the corpus. The same task should compare the transcendental instructions.

### Trajectories rows before (task 044) and after (`SCORECARD_RACE_CLOCK=ref/race_clock`, commit 8a0d2da)
"First" is when the two runs are first more than 1 m apart. Where only one size is given, the runs never parted
by 1 m.

| Circuit | Player before | Player after | AI before (first, largest) | AI after (first, largest) |
|---|---|---|---|---|
| Vineta K | 0.98 m | 0.02 m | 0.38 s, 134.36 m | 13.45 s, 4.05 m (close) |
| Modesto Heights | 0.46 m | 0.09 m | 0.38 s, 143.47 m | 10.94 s, 135.11 m |
| Chenghou Project | 1.30 m | 0.25 m | 0.40 s, 219.93 m | 12.04 s, 103.47 m |
| Blue Ridge | 0.98 m | 0.41 m | 0.42 s, 142.10 m | 9.49 s, 140.13 m |
| Sinucit | 13.89 m (differs) | 0.00 m | 0.40 s, 188.51 m | 3.60 s, 280.70 m |
| Citta Nuova | 0.42 m | 0.02 m | 0.45 s, 183.73 m | 8.17 s, 83.86 m |
| Sebenco Climb | 0.53 m | 0.03 m | 0.45 s, 109.45 m | 3.05 s, 92.98 m |
| Sol 2 | 3.25 m (close) | 0.08 m | 0.40 s, 489.91 m | 6.91 s, 423.60 m |
| Karbonis | 34.07 m (differs) | 0.00 m | 0.42 s, 377.04 m | 9.56 s, 6.47 m |
| Sagarmatha | 0.57 m | 0.20 m | 0.42 s, 253.66 m | 16.35 s, 6.19 m |
| Manor Top | 0.81 m | 0.04 m | 0.45 s, 140.30 m | 11.20 s, 52.35 m |
| Mandrashee | 6.23 m (differs) | 0.00 m | 0.38 s, 500.26 m | never, 0.46 m (faithful) |

The category went from 9 / 1 / 15 / 0 to 14 / 1 / 10 / 0 (faithful / close / differs / other). All 12 player rows
are now faithful.

### The Karbonis finding
The cause is the time step, not the contact response:
- **Before the first contact.** The ship is already 0.4 to 0.5 m along its path from PPSSPP's.
- **The first contact (4.854 s).** The response is the same: 218.2 against 218.3 km/h afterwards, the same
  velocity vector, shield 98.833.
- **The scrape.** The difference accumulates as the next contacts meet the wall at other points: 178.2 against
  174.9 km/h at 4.955 s, then 121.3 against 108.1 km/h at 5.356 s. The speed along the wall differs first.
- **With PPSSPP's frame times replayed.** The player's path stays within 0.01 m of PPSSPP's for the whole 20 s,
  scrape included. The collision code (FUN_08926ae4) is not at fault.

### Changed
- `src/profile/pure_profile.cpp`:
  - `PURE_TEST_RACE_CLOCK=FILE`: a native `srand()` that pins the two seeds, PPSSPP's frame-timer differences
    replayed through a `sceKernelGetSystemTimeWide` wrapper, and the reference's unlock state for GPI. It is a test
    switch only.
  - probes `PURE_WATCH_RAND=1|2`, `PURE_WATCH_WORDS`, `PURE_TRACE_RAND`.
- `tools/ai_seed_check.sh` (new): takes PPSSPP's race clock into `ref/race_clock/<track>.txt` (git-ignored). It
  checks the player's end position against the reference (0.0004 m on Vineta K), runs the scorecard's trajectory
  measure with the clock, and PASSes when the player and AI rows are faithful.
- `tools/scorecard.py`: the `SCORECARD_RACE_CLOCK` environment pass-through for the trajectory runs (5 lines).
- `docs/fidelity.md`: differences 13 and 14 (rows and sections).
- `docs/timing.md`: the game's clock in a race.
- `docs/scorecard.md`: the Trajectories section from the race-clock run, with a note and task 044's figures.
- `README.md`: rows for the switch, the probes and the tool.
- This Result.

Checks: `tools/frame_regress.sh` 18/18 with values unchanged (race_hud 0.0148), and `python3 tools/scorecard.py
--selftest` PASS. A player's game is unchanged: every addition is behind an environment switch.

Verify output (`tools/verify_task.sh 046`, last 20 lines):
```
verify 046: tools/build.sh profile && tools/ai_seed_check.sh && tools/frame_regress.sh --only race_hud
[0/2] Re-checking globbed directories...
[1/4] Checking the build version
[2/4] Building CXX object CMakeFiles/PureNative.dir/vendor/portablekit/host/ui/menu.cpp.o
[3/4] Linking CXX executable bin/PureNative
[ai_seed_check] vineta_k: race clock ref/race_clock/vineta_k.txt
[scorecard] trajectories: close (3 rows, 17 s)
trajectories  close
[scorecard] wrote out/ai_seed_check/scorecard.json and scorecard.md (0m 17s)
  vineta_k          player faithful  first over 1 m: never; largest 0.02 m at 17.25 s
  vineta_k          AI     close     first over 1 m: 13.45 s; largest 4.05 m at 16.00 s
ai_seed_check: FAIL
verify 046: FAIL (exit 1)
```
(`tools/frame_regress.sh --only race_hud` on its own: PASS, race_hud 0.0148.)

Open questions:
1. **The next task: the VFPU dot product.** Implement the hardware's rounding for vdot, vhdp, vmmul, vtfm and the
   other dot forms in `allegrex_context.hpp`, rebuild the corpus, then run `tools/ai_seed_check.sh --tracks` over
   all 12 circuits. Compare the transcendental instructions too (PPSSPP uses tables of the hardware's results).
2. **The 1 ms frame-time steps.** The kernel's starvation quantum is a difference in kind but invisible in play. A
   finer time answer (for example the dispatches since the last tick) would make the port's frame times follow its
   own CPU work, never PPSSPP's exact ones. Not done; Erik's call.
3. **The race clock files** in `ref/race_clock/` are git-ignored. They need copying for a rerun, or
   `tools/ai_seed_check.sh` retakes Vineta K's in about 2.5 minutes. SHA-256 prefixes:
   - vineta_k ffb8f74a83d0, modesto_heights e26bd16494f8, chenghou_project f9172aaf6dd5, blue_ridge f77fedc55886;
   - sinucit 74eda6988e12, citta_nuova 1bf373f1d57a, sebenco_climb a3c8f15ac753, sol_2 16edad61e4f1;
   - karbonis d19168047c09, sagarmatha c05500392afc, manor_top e4f0fa0a9b27, mandrashee 6883dc10800a.

   Only Vineta K's was taken by the tool itself. The other eleven came from the task's probe with the same
   breakpoints, and their players match the references to 0.00 to 0.41 m. `--retake` remakes them, about 30 minutes
   for all.
4. **The scorecard's AI note** still says "another race, not noise". That is the tool's text, and the only change
   allowed in `scorecard.py` was the pass-through; docs/scorecard.md explains it.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
