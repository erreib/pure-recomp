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
Status: DONE. The probe and the model cover the new kinds, and both circuits are sampled from READY to 13 s.
`vfpu_model.py --check ref/vfpu` passes with every kind the race runs included. PPSSPP's JIT computes `vcrsp.t`
unfused: it rounds both products and then their difference, on all 1592532 sampled result lanes. The port's test mode
rounds the first product and fuses the second, so 20 to 24% of its results differ. `vfad` and `vmscl` already match.

Karbonis' player first parts at 6.974 s. In the frames just before that, only `vcrsp.t` results differ from PPSSPP.
With the header below (in a copy, never in vendor/), the harness reproduces PPSSPP under the test mode on every
sampled row. race_hud is unchanged (0.0149).

Four kinds could not be measured. The game's code has no `vcrs.t`, `vqmul.q` or `vavg`; they decode only in data.
No `vrot` site ran on either circuit before 13 s.

Changed:
- `tools/vfpu_probe.py`:
  - `scan`, `cover` and `sample` decode `vcrs.t`, `vcrsp.t`, `vqmul.q`, `vfad`, `vavg`, `vrot` and `vmscl`.
  - `sample` gets `--cap 0` (every execution), `--window FROM,TO` (every execution between two race clocks, placed by
    the reference race) and `--coverage DIR`.
  - `port` gets `--modes ppsspp,psp`, `--tag`, `--include`, `--fp-contract` and `--kinds`. The harness now uses the
    corpus's `-ffp-contract=off`, and it builds against a header from before patch 0020 too.
  - A function's last block is skipped in the harness.
- `tools/vfpu_model.py`:
  - A model for each kind (`kind_models`), PPSSPP's rule (`RULES_048`) and the PSP's (`HW_048`).
  - `--check` now covers the new kinds and the port's two modes; `--check --tag` checks a header experiment.
  - `--diff` lists where the port differs from PPSSPP, in time order. `--report` covers the new kinds.
  - `--selftest` adds pspautotests' `vcrs`/`vcrsp`/`vqmul`/`vfad`/`vavg` results and the `vrot.expected` report.
  - Sample sets are found anywhere under the directory.
- `docs/fidelity.md`: difference 13's row, and a new section "The cross, quaternion and horizontal products,
  measured".
- `docs/verification.md`: "The other kinds (task 048)".
- `README.md`: the two tools' rows.
- `ref/README.md`: the three new sets, their commands and hashes. The sets are under `ref/vfpu/jit/`: `048_vineta_k`,
  `048_karbonis` and `048_karbonis_dot` (git-ignored).
- This Result.
- Nothing under src/, patches/ or vendor/. The header experiments ran on copies in `out/048/candidate/include` and
  `out/048/pre0020/include`.

Verify output (`tools/verify_task.sh 048`, last 20 lines):
```
  vfad.q (result lanes)                    sequential               184512/184512 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 184512/184512 (100.000%); default mode = hw 158833/184512 (86.083%)
  vfad.p (result lanes)                    sequential               6304/6304 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 6304/6304 (100.000%); default mode = hw 3842/6304 (60.945%)
  vmscl.q (result lanes)                   ieee                     1524032/1524032 (100.000%)
                                           the port since patch 0020: test mode = PPSSPP 1524032/1524032 (100.000%); default mode = hw 1524032/1524032 (100.000%)
  transcendentals (the port's helper against PPSSPP):
  not in these samples: vsin, vcos, vrcp, vrsq, vexp2, vlog2, vasin (tools/vfpu_probe.py scan: vsin and vcos have two sites each, which the race did not run; vexp2, vlog2 and vasin occur nowhere in the executable)
vfpu_model --check: PASS
frame regression 2026-10-07 16:44, commit 4c863f5, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-a49864a3975020b8e/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0144   0.10   32    0.0149 -0.0005  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 048: PASS
```
(The full check prints every set under ref/vfpu, task 047's included: still 100% under the JIT's and the
interpreter's rules.)

### Sample counts per kind and site
What the game's code has (`scan`): 108 `vcrsp.t`, 61 `vfad` (2 `.p`, 42 `.t`, 17 `.q`), 24 `vrot` (12 `.t`, 12 `.q`,
0x088F12A4 to 0x088F1ACC, no function in the map) and 4 `vmscl` (3 `.q`, 1 `.t`). `vcrs.t`, `vqmul.q` and `vavg` decode
only in data.

Coverage on PPSSPP's JIT, READY to 13 s:
- Vineta K: 101 of 197 sites ran, 911882 hits; 65 had 50 or more hits.
- Karbonis: 72 sites ran, 876955 hits; 62 had 50 or more hits.

Every execution of those sites was sampled. No site has a prefix. Rows per site (one row is one execution):

**Vineta K** (`048_vineta_k`). At 13.01 s the player is 0.0009 m from the reference and every ship is within 0.15 m.
- vcrsp.t: 27 sites, 255662 rows (766986 result lanes)
  - 08823B04 5314, 088274F8 44922, 088275B0 20557, 088275B8 20557, 088275E0 19224, 08827650 25244, 08827710 869
  - 08827734 705, 08827758 428, 0885EC70 75, 08917E98 4738, 0891B1B8 6256, 0891B244 6256, 0892A6C0 960
  - 0892A6C4 960, 0892CB8C 7680, 0892E16C 15358, 0892E3DC 7680, 08933510 15358, 08933618 423, 089347A8 15360
  - 089347AC 15360, 089347B0 15360, 089358F0 406, 089359D0 406, 08935A28 406, 08945E94 4800
- vfad.p: 2 sites, 6304 rows: 08874988 1731, 08874E80 4573
- vfad.t: 26 sites, 364118 rows
  - 08823770 74663, 08823804 65681, 08825240 288, 088252D8 288, 08825384 288, 08827660 25244, 0882766C 25244
  - 08827678 25244, 088276D8 869, 088442C0 32211, 088444FC 7688, 08844500 7688, 08929A68 21922, 0892A6CC 960
  - 0892A710 960, 0892A9D0 960, 0892A9FC 960, 0892AD84 960, 0892AD98 960, 0892CCB0 7680, 0893477C 15360
  - 0893478C 15360, 0893479C 15360, 0893481C 7680, 08945E74 4800, 08945E88 4800
- vfad.q: 8 sites, 184512 rows: 08843664, 08843668, 0884366C, 08843670, 088436FC, 08843700, 08843704 and 08843708,
  23064 each
- vmscl.q: 2 sites, 95252 rows (1524032 elements): 08893638 87572, 08927248 7680

**Karbonis** (`048_karbonis`). At 13.08 s the player is 0.019 m from the reference and every ship is within 0.026 m.
- vcrsp.t: 29 sites, 275182 rows (825546 result lanes)
  - 08823B04 4780, 088274F8 49801, 088275B0 26575, 088275B8 26575, 088275E0 23818, 08827650 24067, 08827710 509
  - 08827734 453, 08827758 408, 08859B60 60, 08917E98 4620, 08918A10 86, 08918AB8 86, 0891B1B8 6288, 0891B244 6288
  - 0892A6C0 964, 0892A6C4 964, 0892CB8C 7720, 0892E16C 15321, 0892E3DC 7687, 08933510 15321, 08933618 410
  - 089347A8 15448, 089347AC 15448, 089347B0 15448, 089358F0 407, 089359D0 405, 08935A28 405, 08945E94 4820
- vfad.t: 23 sites, 371982 rows
  - 08823770 79457, 08823804 72208, 08827660 24067, 0882766C 24067, 08827678 24067, 088276D8 509, 088442C0 32262
  - 088444FC 7728, 08844500 7728, 08929A68 22681, 0892A6CC 964, 0892A710 964, 0892A9D0 964, 0892A9FC 964
  - 0892AD84 964, 0892AD98 964, 0892CCB0 7720, 0893477C 15448, 0893478C 15448, 0893479C 15448, 0893481C 7720
  - 08945E74 4820, 08945E88 4820
- vfad.q: 8 sites, 185472 rows: the same eight sites as Vineta K, 23184 each
- vmscl.q: 2 sites, 36780 rows (588480 elements): 08893638 29063, 08927248 7717

**Karbonis, dot products and transcendentals, 6.0 to 7.0 s** (`048_karbonis_dot`): every execution of all 711 dot and
transcendental sites; 213 ran, 259370 rows.
- Dot products: vdot.t 178092, vtfm3.t 43161 lanes, vtfm4.q 78288 lanes, vmmul.q 119760 elements.
- Transcendentals: vrcp 2562, vrsq 11249, vsqrt 26023.
- Its 1422 breakpoints move PPSSPP's AI by up to 31 m and its player by 4 cm at 7.6 s. Each row is still one execution.

### The model report per kind (percentage of PPSSPP's results, `vfpu_model.py --report`)
| `vcrsp.t` model | Vineta K (766986) | Karbonis (825546) |
|---|---|---|
| **unfused: both products rounded, then the difference (the rule)** | **100.000** | **100.000** |
| first product rounded, second fused (vfpu_dot's chain) | 75.893 | 79.985 |
| the port's test mode since patch 0020 (that chain; Z over the four-lane view) | 75.893 | 79.759 |
| second product rounded, first fused (clang's `a*b - c*d`) | 75.245 | 81.541 |
| the port before patch 0020 (harness on the reversed header, `-ffp-contract=on`) | 75.245 | 81.315 |
| exact difference rounded once | 68.757 | 73.473 |
| the PSP's rule (hw; the port's default mode equals it on every lane) | 47.596 | 50.917 |
| the Result's header, test mode / default mode against hw | 100.000 / 100.000 | 100.000 / 100.000 |

How far apart the port's test mode is on Karbonis (167098 differing lanes):
- 1 ulp: 68.5%; 2 ulp: 6.9%; 3 to 15 ulp: 14.3%; 16 or more: 9.2%.
- 1.1% differ only in the sign of a zero (Z's four-lane view adds +0).
- The large ones are where the products cancel. For example, the Y lane of (-48.2926, 1.2539, -103.9333) x
  (48.2926, -78.2539, 103.9333) is 0 in PPSSPP and 0.000148 in the port.

| `vfad` model | .t VK (364118) | .q VK (184512) | .p VK (6304) | .t Kar (371982) | .q Kar (185472) |
|---|---|---|---|---|---|
| **in lane order from s0 (the rule)** | **100** | **100** | **100** | **100** | **100** |
| from +0 (the port's loop) | 100 | 100 | 100 | 100 | 100 |
| tree (s0+s1)+(s2+s3) | 100 | 93.438 | 100 | 100 | 93.244 |
| exact | 76.092 | 92.850 | 100 | 82.399 | 92.914 |
| hw | 49.202 | 86.083 | 60.945 | 51.535 | 86.471 |
| the port: test mode, default mode, before patch 0020 | 100 | 100 | 100 | 100 | 100 |

For `.t`, the tree is the same sum as the rule.

`vmscl.q`: one IEEE product, 100% of 1524032 (Vineta K) and 588480 (Karbonis) elements. The port gives 100% in both
modes and before patch 0020.

Not measured, because there are no samples:
- `vcrs.t` is one product in every model; the IEEE product gives pspautotests' 75/75.
- `vqmul.q`: every model gives the 100/100 integer-operand cases.
- `vavg`: hw(sum) * (1/n) gives 15/15; the others give 14/15 (`.p` of (-0.1, 1000) is 499.949982 on the PSP).
- `vrot`: no form gives `vrot.expected`'s PSP values. For 0.3 the PSP gives sin 0x3EE8716C and cos 0x3F641900; the
  port's sinf/cosf give 0x3EE87173 and 0x3F641901.

The dot products in Karbonis' window: chain/a0, 100% of 419301, and the port's test mode 100%. The transcendentals:
the port differs on none.

### Karbonis
**What was compared.** `tools/ai_seed_check.sh --tracks karbonis` gives the port's race records under the race
clock, after patch 0020. I compared them with ref/scorecard/trajectories/karbonis.csv at the clocks both sides
sampled.

**The first difference.** The player's position and velocity agree to the printed 3 decimals until 6.924 s. The only
exceptions are 11 single flips of the last digit, the first at 0.117 s (vy -0.002 against -0.001). So the player's
state differs in its low bits from the first frames.
- The first sample that really parts is 6.974 s (port frame 6671, PPSSPP usec 138326183). The position is 8 mm off
  and the velocity 9 mm/s, during the scrape along the wall.
- The player is 1 m off at 12.08 s.

**What ran just before it.** These are the three frames from PPSSPP usec 138276120 (6.924 s, the last agreeing
sample) to 138326183.
- `vcrsp.t`: 660 of 2895 results differ from the port's test mode, at 22 of the 26 sites that ran.
- The last differing ones are the once-a-frame cross products in the ship update's path, at usec 138325042 to
  138325051, 1.1 ms before the sample. Each is off by 1 or 2 ulp. The sites:
  - FUN_0892a230 at 0x0892A6C0 (row 597 lane 1) and 0x0892A6C4 (lane 2);
  - FUN_08945e54 at 0x08945E94 (rows 2985 to 2989).
  - Both functions are called from FUN_08926ae4.
- Nothing else differs: none of the 1962 `vfad` and 2032 `vmscl` results. In the window run, none of the 8767
  `vdot`, 2094 `vtfm3`, 3928 `vtfm4` and 5872 `vmmul` results, and none of the `vrcp`/`vrsq`/`vsqrt` results.
- Before 0.117 s (usec 131418908 to 131468973): 293 of 2448 `vcrsp.t` results differ, at 14 sites; vfad and vmscl
  none.
- From READY to 13 s, `vcrsp.t` differs on 167098 of 825546 lanes, at all 29 of its sites, from READY + 0.001 s on.
- `vfpu_model.py --diff ref/vfpu/jit/048_karbonis` lists them.

**The rule that fixes them: unfused.** With the header copy below:
- `vfpu_probe.py port --modes ppsspp,psp --tag candidate --include out/048/candidate/include` reproduces PPSSPP
  under the test mode on every `vcrsp.t`, `vfad` and `vmscl` result of both circuits: 825546 + 371982 + 185472 +
  588480 on Karbonis, and the same on Vineta K.
- Its default mode equals the PSP's rule on every one of them.
- Check it with `vfpu_model.py --check ref/vfpu/jit/048_karbonis --tag candidate`.

**Before patch 0020.** The corpus before patch 0020 was no closer: it was 81.3% right on Karbonis' `vcrsp.t`. In the
three frames it got 588 lanes wrong, 344 of them the same lanes as the test mode. So Karbonis' faithful player before
the patch was a scrape that resolved the same way despite other wrong low bits. It was not a right cross product.

### The C++ per kind, both modes
For `include/psprecomp/allegrex_context.hpp` (Fable applies it; a corpus rebuild).

**1. vcrsp.t.** A new helper beside `vfpu_dot_prefixed`. Test mode: PPSSPP's JIT. Default: the PSP's rule.
```cpp
    // vcrsp.t (task 048). Test mode: PPSSPP's JIT rounds both products of each lane and then their difference,
    // nothing fused (every one of 1592532 sampled result lanes). Default: the PSP's rule, vfpu_dot's.
    static float vfpu_cross_dot(const float *s, const float *t, std::uint32_t n) noexcept {
#if defined(__clang__)
#pragma clang fp contract(off)
#endif
        if (vfpu_dot_mode() != 1u) return vfpu_dot_psp(s, t, n);
        float r = s[0] * t[0];
        for (std::uint32_t i = 1u; i < n; ++i) {
            const float p = s[i] * t[i];
            r = r + p;
        }
        return r;
    }
```
And in `execute_vfpu_cross_quat`, the `length == 3u` branch:
```cpp
        if (length == 3u) { // VCRSP.T
            // X/Y are produced directly from the unprefixed inputs.  The PSP
            // applies rewritten S/T prefixes only to the final dot-product lane.
            {
                const float s0[2]{source[1], source[2]}, t0[2]{target[2], -target[1]};
                const float s1[2]{source[2], source[0]}, t1[2]{target[0], -target[2]};
                result[0] = vfpu_cross_dot(s0, t0, 2u);
                result[1] = vfpu_cross_dot(s1, t1, 2u);
            }

            // Forced T view: [T.y, -T.x, T.w, T.z], while retaining the
            // original constant/absolute controls.
            vfpu_ctrl[1] = (vfpu_ctrl[1] & ~kSwizzleAndNegateMask) | 0x000200B1u;
            apply_vfpu_source_prefix(target, 4u, 1u);
            apply_vfpu_source_prefix(source, 4u, 0u);
            // Z is the first two lanes of the forced views, s.x*t.y + s.y*(-t.x): lanes 2 and 3 (s.z*t.w, 0*t.z)
            // are no part of it on the PSP (pspautotests: an infinite s.z or t.z leaves Z finite).
            result[2] = vfpu_cross_dot(source, target, 2u);
        } else if (length == 4u) { // VQMUL.Q   (unchanged)
```
- The default mode gives the same finite results as today. Zero lanes add nothing to `vfpu_dot_psp`.
- The default mode fixes Z for an infinite s.z or t.z. pspautotests has 9 such `vcrsp` cases, for example v0 x v4,
  where Z should be 1000.199951. Today both modes give NaN, because the four-lane view multiplies the infinity by 0.

**2. vfad and vavg.** In `execute_vfpu_horizontal`, replace the final loop. The test mode keeps today's unfused sum
from +0, which reproduces PPSSPP on every sample. The default mode takes the PSP's rule over the four-lane view (zero
lanes add nothing), which gives pspautotests' 15 `vfad` and 15 `vavg` results.
```cpp
        float result[1]{0.0f};
        if (vfpu_dot_mode() != 1u) {
            result[0] = vfpu_dot_psp(source, weights, 4u);
        } else {
            for (std::uint32_t lane = 0u; lane < 4u; ++lane) {
                const float p = source[lane] * weights[lane];
                result[0] = result[0] + p;
            }
        }
        write_vfpu_vector_with_destination_prefix(result, destination_scalar_register, 1u);
```
- The two statements keep the test mode unfused even outside the corpus's `-ffp-contract=off`, for example in the
  interpreter's build.
- For `vavg.t` the default multiplies each lane by 1/3 inside the PSP's sum. Whether the PSP does that or divides the
  sum is not measured; the game has no `vavg`.

**3. Unchanged in both modes:**
- `vqmul.q` stays on `vfpu_dot`. It is not measured and the game has none; if PPSSPP treats it as it treats `vcrsp`,
  it would take `vfpu_cross_dot(…, 4u)`.
- `vcrs.t` stays as the codegen's inline products. It is one IEEE product a lane in every model, and pspautotests'
  75/75.
- `vmscl`: one IEEE product in both modes, measured.
- `vrot`: not measured. The PSP's own sin and cos are 1 to 7 ulp from libm (`vrot.expected`), and no closed form
  gives them.

Only `vcrsp.t` changes the test mode, and only `vfad` changes the default mode in a way the game uses (the PSP's
truncating sum instead of IEEE).

Open questions:
1. **The end-to-end test.** After the rebuild with the rule, run `tools/ai_seed_check.sh --tracks` over the 12
   circuits. Two things are expected: Karbonis' player returns to faithful, and the AI rows move. Every ship's update
   runs `vcrsp.t` many times a frame:
   - FUN_0892cb58: 8 times;
   - FUN_0892dea8 and FUN_089345e8: 16 times each;
   - FUN_088274e0: about 50 times.
   This task cannot run the test, because it needs a corpus rebuild.
2. **The default mode's `vfad` is a change to a player's game**: the PSP's truncating sum (D-013's direction) instead
   of IEEE. Fable or Erik decide whether it goes in with the cross product.
3. **Unmeasured:**
   - `vrot`: its 24 sites did not run on either circuit before 13 s. Sample a route that runs 0x088F12A4 to
     0x088F1ACC to settle it.
   - `vqmul.q`, `vcrs.t` and `vavg` are not in the game's code.
   - Prefix constants in lanes past n: no sampled site has a prefix.
4. **The probe's breakpoints perturb PPSSPP.**
   - The full-race samples moved PPSSPP's ships by 0.15 m or less.
   - The 711-site window moved its AI by 31 m and its player by 4 cm at 7.6 s.
   - The rows are each one execution, but a breakpoint cannot show the arithmetic of the JIT's uninstrumented blocks.
     This is task 047's caveat, unchanged.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
