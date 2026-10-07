# 047: The VFPU's dot-product rounding, measured against PPSSPP (fidelity difference 13, what is left)

Milestone: M8 | Branch: task/047-vfpu-dot-rule | Status: OPEN (the probe and the rule; the codegen change is Fable's)

## Goal
With the AI's start pinned (task 046), the ships still part over the last bit of `vdot`: the framework computes the
dot product as one C++ expression, which clang contracts into fused multiply-adds, while the PSP's VFPU rounds
differently (task 046 measured 389 of 1488 results of `vdot.t` at 0x089196B8 differing by 1 ulp, and 76 of 5848 at
0x08926E08). Task 046's operand logs are gone with its worktree, and the published documentation does not state the
rule (pspautotests' vector tests use integer operands; PPSSPP's hardware pages say nothing about precision). This task
rebuilds the evidence: a reusable probe that logs VFPU operands and results from PPSSPP at chosen instructions, a
large sample over the race, and the rounding model that reproduces every sample, for the dot forms and for the
transcendental instructions. Fable then puts the rule into the codegen header (a corpus rebuild, outside this task).

## Read first
- CLAUDE.md, docs/fidelity.md (difference 13, "What is left: the VFPU's dot product": the instructions, the counts,
  the example operands and both results; the transcendental list), docs/tasks/046 (Result: how PPSSPP's registers
  were read at breakpoints; `PURE_TEST_RACE_CLOCK` and ref/race_clock), docs/ppsspp.md (the debugger: breakpoints
  with conditions, `cpu.getReg`, `cpu.stepping`, register names), tools/ppsspp/ppsspp_ctl.py (as a library)
- vendor/portablekit/include/psprecomp/allegrex_context.hpp, read only: `execute_vfpu_vdot_ct`, `execute_vfpu_vdot`,
  `execute_vfpu_vhdp`, and the dot products inside the matrix and transform forms (lines near 816, 862, 918 to 933)
  and the transcendental helpers; this file must not be edited (a corpus rebuild)
- ~/dev/scratch/vfpu-docs (the hardware-verified instruction reference; its introduction's statements on rounding:
  round to nearest, subnormals flushed) and ~/dev/scratch/pspautotests/tests/cpu/vfpu (real-hardware expected
  outputs; `vector.expected`'s dot products are integer operands, so they settle nothing about ulps but every model
  must still reproduce them)
- PPSSPP's source may not be read or copied. Its results, through the debugger, are the oracle.

## Deliverable
1. `tools/vfpu_probe.py`: through the driver, runs a route in PPSSPP with breakpoints at given instruction addresses,
   and at each hit records the instruction's VFPU source operands (the lanes the encoding names, after prefixes if the
   prefix registers are not identity: record the prefix registers too), steps one instruction, and records the result
   lanes; CSV rows of hex bit patterns. Also a `--port` mode that records the same at the same addresses in the port
   (a profile probe exists for watch points: use `PURE_WATCH_WORDS` or add nothing if the port side can be computed
   instead, see 3). Keep PPSSPP's memory stick as found.
2. The samples, under ref/vfpu/ (git-ignored, hashes in ref/README.md): the race route of task 046 (`vineta_k`, with
   its race clock so both sides run the same race) over at least 10 s, at the two `vdot.t` sites of task 046, at
   least one `vhdp`, one `vmmul` or `vtfm` site the ship code uses (find them with Ghidra or the function map; task
   046's Result names the functions), and the transcendental sites it names (`vsin`, `vcos`, `vrcp`, `vrsq`, `vexp2`,
   `vlog2`, `vasin`: whichever the race's code executes). Thousands of rows per site.
3. The rule: `tools/vfpu_model.py` with candidate models for the dot product (a: products rounded to float and summed
   in order, no fusion; b: fused multiply-add chain as clang contracts it; c: exact products aligned to the largest
   exponent, kept with N extra bits, truncated toward zero, summed, rounded to nearest once; with N and the alignment
   and sign handling as parameters; d: others the data suggests), each run over every sample; the report says which
   model reproduces 100 percent of PPSSPP's results per instruction and lane count, and for the transcendentals the
   maximum error in ulps of the port's helper against PPSSPP and whether a table lookup is implied. If no candidate
   reaches 100 percent, the rows that fail each model are listed with their operands, so the next attempt can be
   made from them.
4. docs/fidelity.md: difference 13's section extended with the rule and its evidence; docs/verification.md: the
   probe and the model as a repeatable check (`tools/vfpu_model.py --check ref/vfpu` exits 0 when the chosen model
   reproduces every sample); README.md the tools' rows.

## Acceptance criteria
- [ ] `python3 tools/vfpu_model.py --check ref/vfpu` passes for the dot forms with one named model, or lists the
      failing rows; the transcendental report has numbers.
- [ ] `tools/frame_regress.sh --only race_hud` unchanged (nothing of the port's code changes in this task).

## Verify
`python3 tools/vfpu_model.py --selftest && python3 tools/vfpu_model.py --check ref/vfpu && tools/frame_regress.sh --only race_hud`

## May touch
- tools/vfpu_probe.py (new), tools/vfpu_model.py (new), tools/ppsspp/routes/, ref/README.md, docs/fidelity.md,
  docs/verification.md, README.md; src/profile/pure_profile.cpp only for a probe switch if the port side cannot be
  computed from the samples

## Must not touch
- vendor/portablekit/include/psprecomp/ (Fable's), the codegen, patches/, src/gpu/, src/host/, config/,
  tools/frame_regress.sh, tools/scorecard.py, tools/ai_seed_check.sh, ref/race_clock/ and ref/scorecard/ (read only)

## Estimated turns
50

## Escalate when
The debugger cannot read the VFPU registers (report what `cpu.getReg` offers and what was tried), or no model
reproduces more than 99 percent of the dot-product samples after the candidates above and two more of your own
(report the failing rows).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
