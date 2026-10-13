# 082: Where the rig's guest frame goes

Milestone: Windows fidelity (Erik, 2026-10-12: "I'd consider my cpu quite far above what should be required to run
a recomp like this" — he is right, and nobody has measured where the 9 to 11 ms go) | Branch:
task/082-guest-frame-profile | Status: MERGED (cb1194d, 2026-10-12)

## Goal
The rig's i5-8600K spends 9 to 11 ms of guest time a frame in Erik's play (out/play-trace*.log), swelling by ~2.5 ms
in effect storms — against a 16.7 ms budget at 60 fps, and against ~5.5 million PSP cycles a frame that a static
recompile should dispatch far faster (PPSSPP, a JIT, holds this game at 60 on weaker CPUs). The number is
anomalous and unattributed. After this task the guest's frame is split into named buckets the way task 078's render
split named the renderer's ([render-split]), three questions have numbers, and no behaviour changes:
1. **Where the 9 to 11 ms go:** recompiled game code vs the HLE buckets (kernel and sync, IO, SAS and audio, GE
   calls, the depth store's share) — per second, cheap enough for a play session.
2. **Which bucket swells in the storms** (+2.5 ms): the explosions' SAS voices are the suspect, now provable.
3. **What better codegen buys:** the corpus currently compiles for baseline x86-64 (no /arch anywhere); one
   measured run with the corpus built /arch:AVX2 says what the rig's own AVX2/BMI are worth. And a PPSSPP yardstick
   on the same rig says what this CPU does to this game under a JIT.

## Read first
- CLAUDE.md (the corpus rules: a corpus RECOMPILE with new flags is a 8 to 20 minute build and allowed once here —
  cap parallelism as vendor/portablekit/AGENTS.md says; tools/regen.sh stays forbidden), docs/status.md (the
  2026-10-12 rows: the day's findings this task stands on), docs/tasks/078 through 081 (the Results: the split
  method, the probes, the play logs' figures), patches/README.md
- vendor/portablekit/host/perf/frame_stats.hpp and .cpp: the render Split (`[render-split]`, `add_split`,
  `split_ticks` — the model to twin for the guest; TRACE_RENDER's "cheap enough to leave the timing nearly as it
  was" bar applies)
- The HLE dispatch: where an import call enters the host (grep the hle/ directory for the dispatch table or the
  import thunk; vendor/portablekit/host/hle/), and where a guest frame boundary is visible to the guest thread (the
  vblank or the display flip the pacer uses, kernel.cpp around line 480 — read, do not change the kernel)
- vendor/portablekit/host/audio/sas_core.cpp (the SAS mix the storms suspect), hle_media.cpp (audio output's
  blocking)
- CMakePresets.json (win-x64, win-x64-release: no /arch), CMakeLists.txt (where the corpus units' flags come from:
  the generated/ objects' target), tools/build.sh
- The PPSSPP driver from task 055: grep tools/ and docs/windows.md for how the references were taken with PPSSPP
  1.20.4 on this rig (where it is installed, how it is driven); docs/verification.md
- tools/stutter_check.sh, tools/campaign_sweep.py, tools/purelib/port.py, tools/patches.sh

## Deliverable
One vendor patch for the instrument, measurements committed as they land, and NO committed behaviour or flag
change. Commits per proven stage.
- **The instrument**, `patches/0025-guest-time-split.patch`: a guest-thread split behind `PURE_TRACE_GUEST=1` — a
  `[guest-split] ms per game frame: game X | kernel Y io Z sas W audio V ge U store T` line once a second, ticks
  taken at the HLE dispatch boundary (everything outside an HLE call is `game`, the recompiled code), the buckets
  by module family, the depth store's share where patch 0021 stores (its own bucket or inside `ge`: say which).
  Off, a scope costs one flag test, exactly as the render split's comment promises; `tools/frame_regress.sh --shell
  vulkan --backend vulkan` 7/7 with the trace off proves nothing moved.
- **The attribution run:** the stutter_check probe environment plus `PURE_TRACE_GUEST=1`, at the shipped defaults
  (60 fps) and the race read from the paced flip: the mean split, and the split of the dip seconds against the calm
  ones (question 2's answer). Committed with the figures in the task file.
- **The codegen run:** the corpus rebuilt once with /arch:AVX2 (a LOCAL, uncommitted flag edit; say exactly where
  the flag went; expect the 8 to 20 minute build, parallelism capped), the same probe, the guest `game` bucket
  before and after, then the edit reverted and the tree shown clean. The number goes in the Result; the decision
  on shipping a flag is Erik's and the Mac session's, not this task's.
- **The yardstick:** if task 055's PPSSPP is still on the rig, one bounded run of the same scene (its own speed
  figure or frame time, however its logs put it) for the Result's comparison table; if it is absent or unscripted,
  say so and move on — it is a reference, not a gate.
- **Docs:** patches/README.md (the instrument's row; upstream candidate — every port wants this split), README.md
  (the PURE_TRACE_GUEST row), docs/verification.md if the check lists change,
  docs/tasks/082-guest-frame-profile.md (the Result with the full table: the splits, the AVX2 delta, the yardstick).

## Acceptance criteria
- [ ] the split line exists behind PURE_TRACE_GUEST, costs one flag test when off, and the windowed suite is 7/7
      unchanged with it off
- [ ] the attribution table in the Result: mean race split, dip seconds vs calm seconds, the storm bucket named
- [ ] the AVX2 delta measured and the tree clean afterwards (`git status`, `tools/patches.sh check` at 24)
- [ ] the PPSSPP yardstick figure, or the stated reason there is none
- [ ] `tools/stutter_check.sh` PASS with the trace on (the instrument must not become the harness cost 078 found)
- [ ] `python3 tools/docs_check.py` passes; nothing committed under vendor/; no committed flag change

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan && tools/stutter_check.sh && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/host/perf/frame_stats.cpp, frame_stats.hpp, and the HLE dispatch site the instrument needs
  (name it in the Result), vendor/portablekit/host/audio/sas_core.cpp only if a bucket needs a scope inside it:
  all only through `tools/patches.sh export 0025-guest-time-split`; commit patches/, never vendor/
- patches/0025-guest-time-split.patch (new), patches/README.md
- README.md, docs/verification.md, docs/tasks/082-guest-frame-profile.md (the Result)
- LOCAL only, reverted before finishing: the corpus /arch flag edit (CMakeLists.txt or the preset)

## Must not touch
- include/psprecomp/ (the instrument lives in host/, not the corpus's headers), generated/, config/, src/, tools/,
  vendor/portablekit/host/kernel/ (read it; change nothing), ref/, docs/decisions.md, docs/status.md, anything not
  listed above; tools/regen.sh is never run

## Estimated turns
60

## Escalate when
- the instrument cannot sit at the HLE dispatch without touching include/psprecomp/ or the kernel (report the
  boundary you found)
- the trace's own cost moves the probe (report on vs off)
- the AVX2 rebuild fails to build or exceeds the vendor guide's expectations badly (report; do not fight the build)

## Result

### The attribution run (stage 2)
`PURE_TRACE_GUEST=1 tools/stutter_check.sh --out out/082-on` (the stutter_check probe: Vineta K Single Race in the
Vulkan window with sound, the shipped defaults, 60 fps; read from the paced flip 6100): stutter_check PASS (21 of
221 seconds over 25 ms, readback 0.00). 221 race seconds, ms per game frame (out/082_split.py):

| seconds | n | speed | render | game | kernel | io | sas | audio | ge | display | other | guest | hle | calls/frame | store (in render) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all (mean) | 221 | 89.3% | 5.44 | **8.76** | 0.07 | 0.00 | 0.13 | 0.11 | 0.05 | 1.56 | 0.04 | 10.72 | 1.96 | 772 | 0.48 |
| calm (speed >= 97%) | 46 | 98.9% | 4.27 | 8.12 | 0.06 | 0.00 | 0.12 | 0.10 | 0.04 | 1.52 | 0.04 | 10.01 | 1.89 | 639 | 0.48 |
| dip (speed < 97%) | 175 | 86.7% | 5.75 | 8.93 | 0.07 | 0.00 | 0.13 | 0.11 | 0.05 | 1.56 | 0.04 | 10.91 | 1.98 | 807 | 0.49 |
| low guest quartile | 55 | 95.5% | 5.06 | 7.69 | 0.06 | 0.00 | 0.12 | 0.11 | 0.04 | 1.63 | 0.04 | 9.68 | 1.99 | 584 | 0.48 |
| high guest quartile (the storms) | 55 | 81.8% | 5.79 | **10.06** | 0.08 | 0.00 | 0.14 | 0.11 | 0.05 | 1.55 | 0.04 | 12.03 | 1.97 | 894 | 0.49 |
| worst second | 1 | 74% | | 11.96 | 0.10 | 0.00 | 0.13 | 0.12 | 0.08 | 1.44 | 0.04 | 13.87 | 1.92 | 1239 | 0.51 |

1. Where the ~11 ms go: **82% is `game`, the recompiled code** (8.8 of 10.7 ms). All HLE together is 2.0 ms, and
   1.6 ms of that is sceDisplay outside render (the flip's host work: the shell's event pump, the input script, the
   overlay revalidation). Kernel and sync, IO, SAS, audio and GE calls are under 0.15 ms each.
2. The storm bucket is **`game`**: the high-guest quartile carries +2.35 ms of guest over the low one, and +2.37 ms
   of it is `game`. SAS moves +0.02 ms (0.12 to 0.14): the SAS-voice suspicion is refuted. HLE calls per frame rise
   (584 to 894) while their time stays flat. The depth store is inside render (0.48 ms, flat), not guest time.

### The codegen run (stage 3)
The LOCAL edit, one line after `portablekit_add_game(PureNative ...)` in CMakeLists.txt:
`target_compile_options(PureNative_generated PRIVATE /arch:AVX2 /clang:-ffp-contract=off)` — the corpus object
target alone (host unchanged); `-ffp-contract=off` because clang-cl would otherwise fuse multiply-adds once FMA is
available, which D-013's rounding forbids. 145 compile lines carried the flag; `tools/build.sh profile` (the
memory-capped job pool) rebuilt it in 9 min 39 s with no warning or error (out/082-avx2-build.log). Same probe,
`PURE_TRACE_GUEST=1 tools/stutter_check.sh --out out/082-avx2`:

| seconds | baseline game | AVX2 game | baseline guest | AVX2 guest | baseline speed | AVX2 speed |
|---|---|---|---|---|---|---|
| all | 8.76 | 8.51 | 10.72 | 10.51 | 89.3% | 91.9% |
| calm (>= 97%) | 8.12 | 8.03 | 10.01 | 10.00 | 98.9% | 99.0% |
| low guest quartile | 7.69 | 7.60 | 9.68 | 9.66 | 95.5% | 96.7% |
| high guest quartile | 10.06 | 9.55 | 12.03 | 11.55 | 81.8% | 86.5% |

AVX2 is worth 1 to 3% of the `game` bucket (0.1 ms in calm seconds, 0.25 ms on the mean, 0.5 ms at the top
quartile), within the run-to-run spread of the swept race (the follower's race differs run to run: 772 against 664
HLE calls a frame). stutter_check with AVX2: FAIL by one second (25 of 232 over 25 ms, 10.8%, against 21 of 221 with
the baseline): the same noise band. Reverted: `git checkout CMakeLists.txt`, rebuilt from ccache in 10 s (no
`arch:AVX2` left in build.ninja), `git status` clean, `tools/patches.sh check` ok at 24.

### The yardstick (stage 4)
Task 055's PPSSPP 1.20.4 (`H:/errei/Documents/dev-stuff/deps/ppsspp-1.20.4/PPSSPPWindows64.exe`, x64 JIT, Vulkan),
driven by `tools/ppsspp/ppsspp_ctl.py` through a scratch script (out/082_ppsspp.py, not committed): the scorecard's
Vineta K Single Race route (`scorecard.pp_routes`) with Cross held from READY, then 60 s of wall time from five
seconds after READY, each PPSSPP thread's CPU time (GetThreadTimes) against the emulated time (out/082-ppsspp-yardstick.log):
speed 100.0% (3600 vblanks in 60.1 s), process 260 ms of CPU per emulated second, the emulation thread **194 ms per
emulated second = 3.2 ms a vblank = 6.5 ms per game frame** (the game's own 30 fps), and that thread does the JIT'd
game code, the HLE and the GE command and vertex decode together.

### The comparison table
| | per emulated second | per game frame | notes |
|---|---|---|---|
| port, guest thread (game + HLE), 60 fps (E4) | ~640 ms | 10.7 ms (game 8.8, HLE 2.0) | + render 5.4 ms a frame on the same thread |
| port, `game` alone, calm seconds | ~490 ms | 8.1 ms | baseline x86-64; AVX2 8.0 |
| port, `game`, storm quartile | ~600 ms | 10.1 ms | AVX2 9.6 |
| PPSSPP 1.20.4 emu thread, 30 fps (the game's own) | 194 ms | 6.5 ms | everything: JIT code, HLE, GE decode |

Per game update, the port's recompiled code alone (8 to 10 ms) costs more than PPSSPP's whole emulation thread
(6.5 ms) on the same CPU, and E4's 60 fps asks for it twice as often. Better codegen flags are not the gap (AVX2:
1 to 3%).

### The trace's cost and the probe's spread
| run | build | PURE_TRACE_GUEST | race seconds | speed | guest | render | stutter_check |
|---|---|---|---|---|---|---|---|
| out/082-on | baseline | 1 | 221 | 89.3% | 10.72 | 5.44 | PASS 21/221 |
| out/082-avx2 | AVX2 corpus | 1 | 232 | 91.9% | 10.51 | 5.09 | FAIL 25/232 |
| out/stutter_check (Verify) | baseline | off | 214 | 92.1% | 10.59 | 5.07 | FAIL 48/214 |
| out/082-off2 | baseline | off | 221 | 89.9% | 10.63 | 5.40 | FAIL 39/221 |
| out/082-on2 | baseline | 1 | 234 | 84.5% | 12.07 | 5.58 | FAIL 119/234 |

On against off: the mean guest moves 0.1 ms (10.72 against 10.59 and 10.63), inside the off runs' own spread; the
wrapper adds ~770 timed calls a frame. The later runs degraded on both settings (on2 is the worst of all, its calm
seconds still game 8.29 against 8.12): the rig's state over the session, not the trace — at the end `tasklist` showed
Memory Compression at 6 GB resident. The check's 10% bound sits inside this spread, so its verdict on this rig is
the ceiling grazed or not, run by run.

### Status
PARTIAL. Every deliverable is in (the instrument, the attribution, the AVX2 delta with the tree clean, the PPSSPP
yardstick, the docs), but the Verify line fails on `tools/stutter_check.sh` with the trace off (48 of 214 seconds,
then 39 of 221 on a rerun). That is outside this task: with the trace off the patch binds the same functions as
before, and the suite and the trace-on run passed earlier in the session. The acceptance item "stutter_check PASS with
the trace on" held once (out/082-on, 21/221) and failed once later (out/082-on2, 119/234, the rig degraded).

### Changed
- patches/0025-guest-time-split.patch (new): vendor/portablekit/host/perf/frame_stats.hpp and .cpp (the `GuestPart`
  split, `guest_split_enabled`, `guest_excluded_time`, `add_guest_split`, the `[guest-split]` line beside
  `[render-split]`); the HLE dispatch site is **host/hle/hle_common.cpp `HleRegistrar::bind`**, which wraps each
  import in a timer only when `PURE_TRACE_GUEST` is set. Untouched: include/psprecomp/, src/runtime.cpp (the
  runtime's `invoke_import_cached`), the kernel. The depth store is in its own `store` column, inside render, outside
  the guest total.
- patches/README.md (the 0024 row and section), README.md (the `PURE_TRACE_GUEST` row), this file.
- docs/verification.md unchanged: the check list did not change.
- No committed flag change: the AVX2 edit was local and is reverted.

### Verify output (last 20 lines, out/082-verify.log)
```
track_select   5390    0.0411   0.06   24     0.041 +0.0001  PASS
team_select   5600    0.0416   0.06   24     0.042 -0.0004  PASS
tt_track_select   5375    0.0400   0.06   24     0.040 +0.0000  PASS
tt_hud       5890    0.0609   0.12   32     0.049 +0.0119  PASS
fp_track_select   5375    0.0409   0.06   24     0.041 -0.0001  PASS
fp_hud       5890    0.0728   0.11   32     0.048 +0.0248  PASS
tournament_select   5185    0.0622   0.08   24     0.063 -0.0008  PASS
zone_track_select   4975    0.0333   0.05   24     0.033 +0.0003  PASS
zone_hud     5260    0.0461   0.09   32     0.045 +0.0011  PASS
zone_change   5679    0.0308   0.10   32     0.052 -0.0212  PASS

frame regression: PASS, 18/18 scenes pass, shell vulkan, backend vulkan (12m 9s)
stutter_check: shell vulkan, backend vulkan, out .../out/stutter_check/vulkan-vulkan
stutter_check: campaign_sweep exit 0, 322 s, log .../out/stutter_check/vulkan-vulkan/race/single_race-vineta_k.log
race: PASS, paced from flip 6100; 214 seconds, 11934 frames
(a) seconds with a frame over 25 ms: 48 of 214 (22.4%); apart, the live-file flips (a multiple of 10) over it: 1049, worst 68.4 ms
(b) readback: 0.00 ms a frame
worst second: #209 after the paced flip, frame avg 18.7 max 91.1 ms, flip 17703 91.1 ms
stutter_check: FAIL (48 of 214 seconds over 25 ms, readback 0.00 ms a frame; 48 of 214 seconds have a frame over 25 ms (at most 10%))
VERIFY EXIT 1
```
Afterwards, run separately: `tools/patches.sh check` reports `ok: 24 patch(es) reproduce vendor/portablekit at 8b0c3fe`,
and `python3 tools/docs_check.py` reports `33 files, 0 findings: PASS`. The first run found one finding in this task's
own patches/README.md text ("patch 0021" by number alone), and it is fixed. The windowed suite is 18 scenes now, not
the brief's 7: 18/18 twice with the trace off (out/082-regress-off.log, out/082-verify.log).

### Open questions
- **The corpus is compiled `/O2 /Ob0` on Windows** (vendor/portablekit/cmake/PortableKit.cmake: MSVC-style
  generated options): inlining is turned off for all the recompiled code. The clang path (Mac) gets `-O2` with
  inlining. That would explain the rig's `game` bucket better than the instruction set does, and it is the next
  measurement to make: one local `/Ob1` or `/Ob2` corpus run on this same probe. Also unmeasured: whether clang-cl
  contracts FP on the Windows corpus today. Without FMA in baseline x86-64 nothing fuses, but the clang path passes
  `-ffp-contract=off` and the MSVC path does not.
- 1.6 ms a frame is sceDisplay outside render (the flip's host work: shell pump, input script, overlay revalidation),
  the largest HLE item; the tools' input script is part of it, and a player's build may pay less.
- The SAS suspicion is refuted (0.13 ms, flat in storms). The storms are game code: more of the game's own work per
  frame, matched by the rising HLE call count (584 to 894).
- Whether to ship a flag is for Erik and the Mac session. On these numbers AVX2 is not worth it.

## Review

Merged cb1194d (2026-10-12). Every deliverable landed and the day's question is answered with numbers: Erik's CPU
is plenty (PPSSPP, a JIT, does the whole game in 6.5 ms a frame on it), the port's Windows guest cost is anomalous
(8.8 ms in the recompiled code alone, the storms swelling exactly that bucket), AVX2 is noise, SAS is cleared, and
the prime suspect is vendor cmake's MSVC branch compiling the corpus /O2 /Ob0 — no inlining at all where the Mac's
clang path inlines. The follow-on experiment (one local corpus build with /Ob2, the same probe) is the next
session's first act, on a freshly rebooted rig: the Verify's stutter_check FAIL tracks the machine degrading over
the day (6 GB of memory compression after ~40 game runs and five worktree builds), measured to be independent of
the new trace (0.1 ms on against off), and the probe bounds should be read against a rested machine. If /Ob2
restores the game bucket toward PPSSPP's figure, the fix is a one-line vendor cmake patch with upstream value for
every Windows port, and the 60 fps ceiling story dissolves. The sink's grace (081's fork) then handles what little
grazing remains.
