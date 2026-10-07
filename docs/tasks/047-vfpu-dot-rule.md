# 047: The VFPU's dot-product rounding, measured against PPSSPP (fidelity difference 13, what is left)

Milestone: M8 | Branch: task/047-vfpu-dot-rule | Status: MERGED (8c1f9ba, 2026-10-07); the codegen change is patch 0020 (D-013)

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
Status: DONE. The probe, the samples, the model and the docs are in; `vfpu_model.py --check ref/vfpu` reproduces
100% of every dot-product sample with one named model per instruction and PPSSPP core, and race_hud is unchanged
(0.0149). The finding reverses task 046's reading: PPSSPP does not truncate. Its JIT (the core every reference in
ref/ was taken under) computes `vdot` and `vtfm` in plain IEEE single precision, fused in lane order, and `vmmul`
unfused; the port differs only in which product its fused chain rounds first (vdot), the sign of an exact zero (vtfm)
and fusing (vmmul). The PSP's own rule (pspautotests) is a truncating one that neither PPSSPP core reproduces. Two
parts of the brief cannot be met as written: the game has no `vhdp` in its code (the 371 words that decode as one are
data), and of the transcendentals only `vrcp`, `vrsq` and `vsqrt` run in the race (`vsin`, `vcos`: two sites each, not
run; `vexp2`, `vlog2`, `vasin`: none in the executable).

Changed:
- `tools/vfpu_probe.py` (new): `scan` (the 711 dot and transcendental sites the corpus has code for), `cover` (hits
  per site in PPSSPP's race), `sample` (operands and results through log-only breakpoints armed at boot; `--cpu-core
  0` steps PPSSPP's interpreter), `port` (the corpus's own code for each site, built with the corpus's flags, run on
  PPSSPP's operands: the port side computed, no port run and no profile switch needed).
- `tools/vfpu_model.py` (new): the models (a, a0, chain, b = the port, exact, the aligned-truncation family c, d1-d3),
  `RULES` per PPSSPP core, `--selftest`, `--check`, `--report`, `--search`.
- `docs/fidelity.md`: difference 13's row and the new section "The dot-product rule, measured (task 047)".
- `docs/verification.md`: "The VFPU dot-product check". `README.md`: the two tools' rows. `ref/README.md`: the
  commands and the samples' hashes (`ref/vfpu/`, git-ignored). This Result.
- `src/profile/pure_profile.cpp` untouched (the port side is computed from the samples).

Verify output (`tools/verify_task.sh 047`, last 20 lines):
```
  vtfm4.q (each lane a 4-lane dot)         chain                    59064/59064 (100.000%); the port today 59064/59064 (100.000%)
  vmmul.q (each lane a 4-lane dot)         a0                       384704/384704 (100.000%); the port today 376915/384704 (97.975%)
  vdot.q                                   chain                    7506/7506 (100.000%); the port today 7506/7506 (100.000%)
  transcendentals (the port's helper against PPSSPP):
  vrcp.s     4 sites,   17627 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 0 (max 0 ulp); port: 1.0f / x: 17627/17627
  vrsq.s    22 sites,   83901 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 27315 (max 1 ulp); port: 1.0f / sqrtf(x): 83901/83901; 1 / sqrt(x) rounded once: 56586/83901
  vsqrt.s   29 sites,  112864 results: the port's helper differs on 0 (max 0 ulp); PPSSPP differs from the true value (double precision) on 0 (max 0 ulp); port: fabsf(sqrtf(x)): 112864/112864
  not in these samples: vsin, vcos, vexp2, vlog2, vasin (tools/vfpu_probe.py scan: vsin and vcos have two sites each, which the race did not run; vexp2, vlog2 and vasin occur nowhere in the executable)
vfpu_model --check: PASS
frame regression 2026-10-07 15:32, commit e43658b, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a5ce844b901510b62/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 047: PASS
```

### Which PPSSPP core the references were taken under
The JIT, CPU core 1. `tools/ppsspp/ppsspp_ctl.py` never sets `[CPU] CPUCore`, and PPSSPP's own first ini, kept as
`~/.config/ppsspp/PSP/SYSTEM/ppsspp.ini.orig` since 2026-10-05, has `CPUCore = 1`, as does the live ini. So the
scorecard's references (task 044), task 046's race clocks and its 3 s vdot log, and this task's `ref/vfpu/jit/` all
come from the JIT. `ref/vfpu/interp/` comes from the interpreter (core 0), set for that session only and put back.

### The samples (Vineta K, the scorecard's reference route, READY to 12 s of race clock)
Coverage (JIT, READY to 3.2 s): 205 of 711 sites ran, 1.4 million hits. Sampled: every site with 50 or more hits.
Per site, rows (one row = one execution: source lanes before, destination lanes one instruction later):

JIT (`ref/vfpu/jit/`, 195 sites, 812229 rows; the hot sites log for a shorter span from GO so each gives about 5000;
the two task 046 sites log for the whole run):
- vdot.q: 2 sites, 7506 rows: 08887C04 3753, 088AE970 3753
- vdot.t: 109 sites, 466447 rows: 0882375C 4963, 08823760 4963, 08823764 4963, 08823768 4963, 088237F0 5009, 088237F4 5009, 088237F8 5009, 088237FC 5009, 08823DB8 5215, 08823DBC 5215, 08823E1C 5308, 08823E20 5308, 08824B18 4357, 08827504 4324, 08827508 4324, 08827510 4324, 0882756C 4302, 088275BC 4278, 088275DC 4240, 08827600 4168, 088304F8 905, 08832270 4992, 08832598 4541, 08840E30 4286, 088437D4 4992, 088437F8 4992, 08843C38 541, 0884423C 4992, 088462B0 5348, 0884A24C 4992, 0884A35C 4917, 088697F4 4764, 08869848 4591, 088698A8 4583, 0886A278 4764, 0886A31C 2885, 0886A620 2488, 0886A624 2488, 0886A628 2488, 0886A62C 2488, 0887C238 408, 0887C34C 408, 088879C4 2648, 08887B64 3753, 08887BD4 3753, 08917490 5824, 0891758C 8422, 089177A8 8422, 08917C10 5824, 08917C24 5824, 08917C60 5824, 08917DD8 4358, 08917DF4 4358, 08917E08 4358, 08917E60 4358, 08917E74 4358, 08917EBC 4358, 089196B8 5824, 0891A264 5824, 0891ACD8 5824, 0891AD88 5824, 0891AE44 5824, 0891AE74 5824, 0891B11C 5824, 0891B148 5824, 0891B188 5824, 0891B1E4 5824, 0891B268 5824, 0891B420 5824, 089220C4 906, 089224DC 906, 089227D0 906, 089227E0 906, 08926E08 7248, 08929A30 9576, 08929A74 9548, 08929AB4 10324, 0892A270 906, 0892A480 906, 0892A4F4 906, 0892A998 906, 0892A99C 906, 0892A9A0 906, 0892AD4C 906, 0892AD50 906, 0892AD54 906, 0892C8CC 1424, 0892C8F0 1424, 0892CA68 4992, 0892D588 4992, 0892D8B4 4992, 0892DCF0 4590, 0892E044 4992, 0892E1C4 4992, 0892E418 4992, 08930074 5256, 08930084 5256, 089300B0 5256, 089314FC 4535, 0893150C 4535, 0893156C 6868, 089315E0 6868, 089350D4 4992, 08935100 4992, 089351A0 4992, 0893523C 4992, 08936640 906, 08936694 906, 0893759C 795
- vmmul.q: 5 sites, 24044 rows: 08886ABC 4742, 088936CC 4395, 088C9F88 4980, 088F11A0 4935, 08927230 4992
- vrcp.s: 4 sites, 17627 rows: 08824BB4 4357, 088437E8 4992, 08887C0C 3753, 088883BC 4525
- vrsq.s: 22 sites, 83901 rows: 08827570 4302, 0883259C 4541, 0886A27C 4764, 0887C23C 408, 08917E64 4358, 08917E78 4358, 0891B120 5824, 0891B18C 5824, 089227E4 906, 08929A6C 9548, 0892A6D0 906, 0892A714 906, 0892AA00 906, 0892AD9C 906, 0892C8F4 1424, 0892CCB4 4992, 08934780 4992, 08934790 4992, 089347A0 4992, 089350D8 4992, 08945E78 4530, 08945E8C 4530
- vsqrt.s: 29 sites, 112864 rows: 08824B1C 4357, 088304FC 905, 08832274 4992, 08840E34 4286, 08843C3C 541, 0884A250 4992, 0884A360 4917, 088879D0 2648, 08887B70 3753, 08887BE0 3753, 08887C08 3753, 08917C28 5824, 08917DF8 4358, 089196BC 5824, 0891AE48 5824, 0891B424 5824, 089224E0 906, 089227D4 906, 08929AB8 10324, 0892A9D4 906, 0892AD88 906, 0892C8D0 1424, 08930078 5256, 089300B4 5256, 08931570 6868, 089315E4 6868, 08934820 4992, 08936644 906, 089375A0 795
- vtfm3.t: 18 sites, 85074 rows: 0886A268 4764, 0886A354 1689, 08886A70 5004, 08893674 5010, 088AF05C 4794, 088AF088 3909, 089346F8 4992, 089346FC 4992, 08934700 4992, 0893471C 4992, 08934734 4992, 08934758 4992, 0893475C 4992, 08934760 4992, 08934764 4992, 08934768 4992, 0893476C 4992, 08934774 4992
- vtfm4.q: 6 sites, 14766 rows: 0886A37C 1689, 088AF030 5025, 088F1144 5334, 0892A734 906, 0892A738 906, 0892A73C 906

Interpreter (`ref/vfpu/interp/`, 27 sites chosen across the kinds, 60086 rows, stepped at about 90 stops a second,
22 minutes):
- vdot.q: 2 sites, 2442 rows: 08887C04 1221, 088AE970 1221
- vdot.t: 8 sites, 25538 rows: 0882375C 1580, 08823DB8 1788, 08827504 1718, 089196B8 5800, 0891B11C 2880, 08926E08 7256, 08929A74 2884, 08930074 1632
- vmmul.q: 4 sites, 6140 rows: 088936CC 1695, 088C9F88 1500, 088F11A0 1449, 08927230 1496
- vrcp.s: 2 sites, 3137 rows: 08824BB4 1625, 088437E8 1512
- vrsq.s: 2 sites, 4606 rows: 08827570 1722, 08929A6C 2884
- vsqrt.s: 2 sites, 4512 rows: 089196BC 2880, 08930078 1632
- vtfm3.t: 4 sites, 6268 rows: 08886A70 1764, 08893674 1500, 088AF05C 1500, 08934758 1504
- vtfm4.q: 3 sites, 7443 rows: 0886A37C 1062, 088AF030 1523, 088F1144 4858

None of the sampled sites has a prefix (`vpfx` words, decoded from the code: PPSSPP's debugger does not expose the
prefix registers). `vmmul` and `vtfm` rows hold whole matrices; each result element is one dot product, so the dot
products are: JIT `vdot.t` 466447, `vdot.q` 7506, `vtfm3.t` 255222, `vtfm4.q` 59064, `vmmul.q` 384704 (1.17 million);
interpreter 25538, 2442, 18804, 29772, 98240.

### The model report (percentage of PPSSPP's results each candidate reproduces, `vfpu_model.py --report ref/vfpu`)
JIT (CPU core 1):

| Model | vdot.t (3) | vtfm3.t (3) | vtfm4.q (4) | vmmul.q (4) | vdot.q (4) |
|---|---|---|---|---|---|
| port today (b; reproduces the port's own compiled results 100%) | 79.873 | 97.515 | 100.000 | 97.975 | 100.000 |
| **the JIT's rule: chain for vdot and vtfm, a0 for vmmul** | **100.000** | **100.000** | **100.000** | **100.000** | **100.000** |
| a (unfused from the first product) | 77.873 | 78.624 | 90.419 | 100.000 | 85.891 |
| a0 (unfused from +0) | 77.873 | 76.139 | 90.419 | 100.000 | 85.891 |
| chain (fused in lane order) | 100.000 | 100.000 | 100.000 | 97.975 | 100.000 |
| exact sum, rounded once | 71.917 | 77.919 | 77.982 | 96.128 | 90.741 |
| d1 products rounded, exact sum | 68.907 | 73.116 | 77.783 | 99.088 | 85.891 |
| d2 products truncated, exact sum | 43.938 | 49.919 | 65.448 | 89.526 | 56.182 |
| d3 tree of roundings | 77.873 | 76.139 | 82.922 | 99.371 | 85.891 |
| c(N=2,raw,mag,rtz) = the PSP's (hw) | 40.532 | 51.155 | 63.096 | 88.456 | 50.466 |
| c(N=0..4,raw,mag,rne) | 37.5 to 71.1 | 54.2 to 77.0 | 64.0 to 78.3 | 89.8 to 95.9 | 57.7 to 89.1 |
| c(N=2,norm,mag,rtz) | 37.414 | 50.979 | 63.005 | 88.504 | 44.271 |
| c(N=2,raw,floor,rtz) | 41.285 | 53.901 | 59.673 | 88.903 | 50.560 |

The whole c grid (N 0 to 8, raw or normalised alignment, magnitude or floor truncation, rne/rtz/rna; `--search`,
3000 dot products a group): best 87.9% on the JIT set, 90.9% on the interpreter's.

Interpreter (CPU core 0):

| Model | vdot.t (3) | vtfm4.q (4) | vtfm3.t (3) | vdot.q (4) | vmmul.q (4) |
|---|---|---|---|---|---|
| port today | 84.756 | 100.000 | 93.618 | 100.000 | 97.773 |
| **the interpreter's rule: chain for vdot and vtfm; a0 for vmmul, its last element chain** | **100.000** | **100.000** | **100.000** | **100.000** | **100.000** |
| a | 86.675 | 93.447 | 93.613 | 83.989 | 99.909 |
| a0 | 86.675 | 93.447 | 87.231 | 83.989 | 99.977 |
| chain | 100.000 | 100.000 | 100.000 | 100.000 | 97.706 |
| exact | 79.352 | 76.538 | 88.689 | 87.797 | 95.334 |
| hw | 39.283 | 63.365 | 70.692 | 48.280 | 86.274 |

The interpreter's one difference from the JIT: the last element of a vmmul result, `d[side-1][side-1]`, is fused (23
of the 23 elements where chain and a0 differ there; the JIT: unfused on all 69 such elements).

How far the port is from the JIT: `vdot.t` 93881 of 466447 differ (66766 by 1 ulp, 5679 by 2-3, 7319 by 4-15, 14117
by 16 or more, where large products cancel); at task 046's sites 0x089196B8 1253 of 5824 (21.5%, all 1 ulp) and
0x08926E08 648 of 7248 (8.9%). `vtfm3.t` 6342 of 255222, each an exact zero, PPSSPP -0, the port +0. `vmmul.q` 7789 of
384704 (7026 by 1 ulp). Task 046's example (0xBF5A4EEF, 0x3AFE5500, 0x3D0B28A3) squared: chain 0x3F3A766B = PPSSPP,
the port 0x3F3A766C.

### The rule, for the codegen
To run PPSSPP's reference race (what the scorecard and `tools/ai_seed_check.sh` measure), PPSSPP's JIT rule. s and t
are the n lanes the encoding names (n = 2, 3, 4 for .p, .t, .q), after the source prefixes. No alignment and no extra
bits: every operation is an IEEE single-precision operation rounded to nearest even, the sign is IEEE's.

```cpp
// vdot (and vhdp, unmeasured: the game has none), and each row of vtfm/vhtfm (the matrix row and the vector, the
// vector's last lane 1.0 for vhtfm): lane 0's product rounded, then one fused multiply-add per further lane.
float r = s[0] * t[0];                                  // a statement of its own: clang never contracts across statements
for (std::uint32_t i = 1; i < n; ++i) r = std::fma(s[i], t[i], r);
// vmmul, each element d[a][b] = sum over c of s[b][c] * t[a][c] (the pairing the codegen already uses): nothing fused,
// from +0, in c order.
float r = 0.0f;
for (std::uint32_t c = 0; c < n; ++c) { const float p = s_row[c] * t_row[c]; r = r + p; }
```

- vdot: only the encoded n lanes. The `_ct` vdot today sums a four-lane view and its fourth `fma(0, 0, r)` turns a -0
  into +0; whether a prefix constant in a lane past n takes part is not measured (no sampled site has a prefix).
- vtfm: the chain starts from the first product, not from +0 (the codegen's `float sum = 0.0f; sum += m*t` gives +0
  where PPSSPP gives -0). The last row keeps the T-prefix handling the codegen has.
- vmmul: the codegen's loop `sum += vfpu_s[...] * vfpu_t[...]` is contracted today; it must not be (a separate
  product variable, or `#pragma clang fp contract(off)`).
- These live in two places: `execute_vfpu_vdot_ct`, `execute_vfpu_vdot` and `execute_vfpu_vhdp` in
  `include/psprecomp/allegrex_context.hpp` (its `vcrsp`/`vqmul` dot lanes too, unmeasured), and the Vtfm and Vmmul
  cases of `vendor/portablekit/tools/codegen_main.cpp`, which emit those loops inline.

The PSP's own rule (pspautotests `vector.expected`, a real PSP: only this member of the grid gives all 150 vdot/vhdp
results; chain, a and exact give 144), for the record and a later choice:
1. Operands: a zero exponent field is zero (subnormals flushed); inf/NaN take the IEEE path.
2. For each lane with both operands non-zero: sign = sa ^ sb, E = ea + eb - 127 (the raw biased exponent sum, not
   normalised when the significand product reaches 2), P = (ma | 1<<23) * (mb | 1<<23), exact, 48 bits.
3. top = the largest E. Each P is shifted right by (top - E) + 21: 25 fraction bits kept at 2^(top-127), that is 2
   extra bits beyond a float's 23; the bits shifted out are dropped from the magnitude (toward zero) before the sign is
   applied (v = sign ? -(P >> sh) : (P >> sh); a shift of 64 or more gives 0).
4. The v are summed exactly (int64). The result is sign(sum) * |sum| * 2^(top - 127 - 25), cut to 24 significant bits
   toward zero (no rounding up); below 2^-126 it is a signed zero, from 2^128 infinity; a zero sum gives +0 (unchecked).
On PPSSPP's samples it reproduces 40.5% of `vdot.t`, so it would move the port off PPSSPP's references; which rule the
codegen takes is Fable's and Erik's call (docs/fidelity.md leaves it open).

### The transcendentals (the port's helpers against PPSSPP)
| Instruction | JIT: sites, results, port differs | Interpreter: sites, results, port differs | PPSSPP against the true value |
|---|---|---|---|
| `vrcp.s` | 4, 17627, 0 | 2, 3137, 1363 (max 5 ulp: 1 ulp 298, 2: 405, 3: 395, 4: 264, 5: 1, all at 0x088437E8; 0x08824BB4's operand is always 1.0) | JIT 0 differ; interpreter 1363, max 5 ulp |
| `vrsq.s` | 22, 83901, 0 | 2, 4606, 0 | both `1/sqrtf` with two roundings: JIT 27315 of 83901 are 1 ulp from the correctly rounded value |
| `vsqrt.s` | 29, 112864, 0 | 2, 4512, 0 | 0 differ |
| `vsin`, `vcos` | 2 sites each (FUN_088742b0, FUN_08889408), not run in the sampled race | | |
| `vexp2`, `vlog2`, `vasin` | not in the executable | | |

No table is implied by the JIT: its results are the IEEE operations the port already uses (0 differences). The
interpreter's `vrcp` matches no closed form tried (`1.0f / x` reproduces 1774 of 3137): a table or the hardware's own
algorithm, consistent with vfpu-docs' "lowest 3.5 bits inaccurate" for the PSP's `vrcp`.

Open questions:
1. **Which rule the codegen takes.** PPSSPP's JIT rule above puts the port on the scorecard's references; the PSP's
   truncating rule is the hardware's but disagrees with every PPSSPP sample. The end-to-end test of the JIT rule is
   `tools/ai_seed_check.sh --tracks` over the 12 circuits after the corpus rebuild (Vineta K's AI row should become
   faithful).
2. **The probe moves PPSSPP's AI.** With the probe's breakpoints the player ends within 1 mm of the reference at 12 s,
   the AI ships up to 0.55 m (4 breakpoints in the two task 046 functions, the same whether on the vdot sites or on
   integer instructions beside them) and 8 m (all 330); a breakpoint on code the race never runs and a second
   uninstrumented PPSSPP run stay at the measure's floor (2 to 6 cm). That points at the breakpoints' effect on the
   JIT's blocks rather than the dot product they log, but a breakpoint cannot show the uninstrumented JIT's
   arithmetic: question 1's ai_seed_check run is what settles it.
3. **Unmeasured:** `vhdp` (absent), a prefix constant in a lane past n, subnormal operands, the sign of an exactly
   cancelling sum, `vsin`/`vcos` (sample them in a mode or menu that runs FUN_088742b0 or FUN_08889408: `vfpu_probe.py
   cover` with another route), `vmmul` .p and .t and `vdot.p` (none ran), the dot lanes of `vcrsp` and `vqmul`.
4. **The interpreter run** diverges from the reference race (its AI 1.3 to 62 m away at 12 s), most likely by its
   `vrcp`; it was used only for its rows.

## Review
Verify rerun: PASS from the main checkout at 8c1f9ba (2026-10-07): `vfpu_model --selftest` PASS, `--check ref/vfpu`
PASS (every dot-product sample reproduced by the named rule per instruction and per PPSSPP core), race_hud 0.0148.
The samples (87 MB) copied from the worker's ref/vfpu with the hashes ref/README.md lists.

Spot-read: tools/vfpu_probe.py (log-only breakpoints armed at boot; the port side computed by building each site's
corpus code with the corpus's flags, so no port run was needed; the interpreter core set for one session and put
back), tools/vfpu_model.py (the candidate models and the `c` grid search; the pspautotests cross-check), the
fidelity section (the three rules stated precisely). Files outside May touch: none. The worker was cut off once by a
usage limit after its fourth commit and resumed with its context.

Merged: 8c1f9ba into batch/m2.

Notes: the finding reverses task 046's reading: PPSSPP does not model the hardware's rounding at all; its JIT fuses
vdot and vtfm in lane order (its own compiler's doing on this machine) and leaves vmmul unfused, its interpreter fuses
vmmul's last element, and the real PSP (pspautotests' 150 results, 6 of which discriminate) truncates aligned
products with two extra bits. D-013 decides what the port does. Unmeasured and recorded: vhdp (absent), prefix
constants past n, subnormals, cancelling sums' sign, vsin/vcos (two sites each the race never runs), vcrsp/vqmul's
dot lanes, and the PSP's inaccurate vrcp (the interpreter's differs from 1/x by up to 5 ulp; the JIT's is exact).
