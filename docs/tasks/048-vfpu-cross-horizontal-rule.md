# 048: PPSSPP's rounding for the cross, quaternion and horizontal products (the test mode's missing kinds)

Milestone: M8 | Branch: task/048-vfpu-cross-horizontal-rule | Status: OPEN (the samples and the rule; the codegen change is Fable's)

## Goal
Patch 0020 (D-013) made the port's dot products round as PPSSPP's JIT does under the test mode, and the samples
confirm it on 1.17 million dot products, but `tools/ai_seed_check.sh` still shows the AI parting from PPSSPP's on ten
circuits, and Karbonis' player, faithful before the patch, now parts at 12.08 s (docs/fidelity.md, "The codegen's
rule"). The kinds the race runs that were never sampled, and that the patch or the corpus's new `-ffp-contract=off`
changed, are the suspects: the cross and quaternion products (`AllegrexContext::execute_vfpu_cross_quat`: `vcrs`,
`vcrsp`, `vqmul`, 108 call sites in the corpus), the horizontal sums (`execute_vfpu_horizontal`: `vfad`, `vavg`, 61
sites), `vrot` (24 sites) and `vmscl` (4). This task samples them in PPSSPP the way task 047 did, finds the rounding
PPSSPP's JIT applies to each, states it as C++ for the header, and shows which of them explains Karbonis.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 13: the measured dot rule and "The codegen's rule": the table before and
  after patch 0020), docs/verification.md ("The VFPU dot-product check" and "The two rounding modes"),
  docs/tasks/047 (Result: the probe's modes, `port`, how PPSSPP's registers are read, the models), docs/tasks/046
  (the race clock, `tools/ai_seed_check.sh`, the race records)
- tools/vfpu_probe.py and tools/vfpu_model.py (yours to extend), tools/ppsspp/ppsspp_ctl.py (library)
- vendor/portablekit/include/psprecomp/allegrex_context.hpp: `vfpu_dot*` (patch 0020), `execute_vfpu_cross_quat`,
  `execute_vfpu_horizontal`, `execute_vfpu_vrot`, `execute_vfpu_vmscl`; and the Vtfm/Vmmul emitters in
  vendor/portablekit/tools/codegen_main.cpp. Read only for the repo: in your worktree you may edit the header for the
  probe's harness experiments (it compiles the header), but never export a patch from it and never commit vendor/;
  the final code goes in your Result and Fable applies it.
- ~/dev/scratch/vfpu-docs (the instruction reference; `vcrs`, `vcrsp`, `vqmul`, `vfad`, `vavg`, `vrot` semantics),
  ~/dev/scratch/pspautotests/tests/cpu/vfpu (real-hardware outputs: `vector.expected` for vcrs/vqmul/vfad/vavg with
  integer operands, which any model must still reproduce)
- PPSSPP's source may not be read or copied; its results through the debugger are the oracle.

## Deliverable
1. `tools/vfpu_probe.py scan` and `sample` extended to `vcrs`, `vcrsp`, `vqmul`, `vfad`, `vavg`, `vrot` and `vmscl`
   (their encodings and lanes), and `port` to compute the port's results for them through the harness under
   `PURE_VFPU_DOT=ppsspp` and `psp`. Samples under ref/vfpu/jit (git-ignored, hashes in ref/README.md): the Vineta K
   reference race as task 047 did, and the Karbonis race with its race clock (`ref/race_clock/karbonis.txt` through
   the same mechanism `tools/ai_seed_check.sh` uses, so the PPSSPP run is the reference race), both from READY to at
   least 13 s of race clock; every site of those kinds with 50 or more hits.
2. `tools/vfpu_model.py` extended with models for each kind (cross and quaternion: which product is rounded and the
   fma order, as clang contracts `a*b - c*d` and the four-term forms, and the chain from lane 0 that patch 0020 uses;
   horizontal: sequential sums, weighted sums, `(s0+s1+..)*(1/n)` against `/n`; vrot: the sin and cos products;
   vmscl: a single product) and `--check ref/vfpu` covering them: the named model that reproduces 100 percent of
   PPSSPP's results per kind, or the failing rows.
3. Karbonis: from the race records (the scorecard's port run under the race clock against
   ref/scorecard/trajectories/karbonis.csv), the first sample where the player's state differs after patch 0020 and
   which sampled site, executed just before it, has a port result that differs from PPSSPP's under the test mode. If
   the differing sites are among the kinds above, say which rule fixes them (demonstrated through the harness: with
   the header edited in your worktree, `port` under the test mode reproduces PPSSPP on every row).
4. The exact C++ for each kind, stated as the header should have it under the test mode (and what the default, PSP
   mode should do: `vfpu_dot`'s rule where a sum of products is involved, a plain IEEE product otherwise), in the
   Result; docs/fidelity.md (difference 13's section extended), docs/verification.md (the check), README.md if a
   switch is added.

## Acceptance criteria
- [ ] `python3 tools/vfpu_model.py --check ref/vfpu` passes with the new kinds included, or lists the failing rows.
- [ ] The Karbonis divergence is attributed to a sampled site, or shown not to be any of these kinds (then say what
      else ran between the last agreeing sample and the first differing one).
- [ ] `tools/frame_regress.sh --only race_hud` unchanged (nothing of the port's committed code changes in this task).

## Verify
`python3 tools/vfpu_model.py --selftest && python3 tools/vfpu_model.py --check ref/vfpu && tools/frame_regress.sh --only race_hud`

## May touch
- tools/vfpu_probe.py, tools/vfpu_model.py, tools/ppsspp/routes/, ref/README.md, docs/fidelity.md,
  docs/verification.md, README.md; the header in your worktree only for harness experiments (never exported)

## Must not touch
- patches/, src/, config/, tools/frame_regress.sh, tools/scorecard.py, tools/ai_seed_check.sh, ref/race_clock/ and
  ref/scorecard/ (read only), earlier patches; never commit anything under vendor/

## Estimated turns
50

## Escalate when
The debugger cannot read what a kind needs (report), or no model reproduces more than 99 percent of a kind after the
candidates above and two of your own (report the failing rows), or Karbonis' first difference follows no sampled site
(report what ran).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
