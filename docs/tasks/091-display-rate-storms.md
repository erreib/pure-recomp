# 091: The effect storms against the 10 ms budget

Milestone: Windows fidelity / E8 follow-up (Erik, 2026-10-14: played at Display rate on the rig — "mostly ok but a
few stutters around effects heavy moments that don't seem to stutter in the original capped fps mode") |
Branch: task/091-display-rate-storms | Status: OPEN

## Goal
At the Display rate (task 089; the rig's 100 Hz, a 10 ms frame) the races stutter in effect storms where the capped
60 fps mode does not. The arithmetic says why: task 082 measured the storms swelling the recompiled code's `game`
bucket by about 2.4 ms over its roughly 3 ms baseline, render and the GPU go on top, and a peak that hides inside a
16.7 ms budget pokes above 10 ms. This task names the overrun exactly — which bucket grows in the storms at 100 Hz,
by how much, and whether anything but the game's own cost (a wait, a stall, a fence, the depth store) is in it —
and then either lands a small fix if one single cause within May touch accounts for it, or documents the finding:
the Display rate needs CPU and GPU headroom the PSP's budget never asked for, with the figures that say how much.
This is a characterization task in the mold of 082: the measurement is the deliverable, a fix is a bonus.

## Read first
- CLAUDE.md, docs/status.md (the 2026-10-13 and -14 rows: the inlining fix, E8 on the rig, Erik's observation),
  docs/tasks/089-display-rate.md (what the Display rate changes: the vblank period, the race-only rule),
  docs/tasks/082-guest-frame-profile.md (the guest split, the storm swell figures at 60, how the probes were read)
- docs/timing.md (the vblank period and the pacer), docs/verification.md (stutter_check's bounds)
- tools/stutter_check.sh (the swept race: it carries weapon pickups and effect storms; `--out` keeps the logs),
  the `[guest-split]` and `[perf]` line formats (docs/developing.md), patches/0025-guest-time-split.patch (what is
  and is not inside each bucket; `store` and render subtraction)

## Deliverable
The storm profile at both rates, committed as the Result's tables, and the conclusion.
- **The probes:** `PURE_TRACE_GUEST=1 PURE_DISPLAY_RATE=1 tools/stutter_check.sh --out out/091-100hz` and the same
  with `PURE_DISPLAY_RATE=0` (`out/091-60hz`), back to back on the rig, nothing else running. If a first run of a
  fresh binary stalls in `display`, rerun it and keep both (docs/status.md 2026-10-13: the scanner reads a first
  run; believe the second).
- **The analysis, against the 10 ms budget, not stutter_check's 25 ms bound:** for the 100 Hz run, the count and
  per-bucket attribution of game frames over 10 ms (and over 16.7 for comparison); the same frames' buckets in the
  60 Hz run; the storms located (the sweep's weapon events or the `game` bucket's swell) and their worst seconds
  shown as `[guest-split]` rows. Name what the overrun is made of: the recompiled code's own swell, an HLE bucket,
  `store`, or time the split does not see (render, GPU wait, the pacer) — the gap between the game total and the
  frame time names the last class.
- **The verdict, one of:**
  - a single cause within May touch, fixed (export as patch 0031-NNNN through tools/patches.sh if vendor; the full
    gates then apply: suite 18/18, flash, framerate, menu, both stutter_check rates), or
  - the characterization alone: the figures, and docs/windows.md's E8 paragraph gains the honest line — what the
    storms cost at 100 Hz, that Original is the smooth setting on this CPU/GPU when it matters, and what headroom
    a machine needs for a clean Display rate.
- docs/tasks/091-display-rate-storms.md gains the Result; `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] both probes committed with the over-10ms frame counts and per-bucket tables
- [ ] the storms' worst seconds shown and attributed at both rates
- [ ] the verdict written: the named cause and fix with gates, or the characterization and the windows.md line
- [ ] `python3 tools/docs_check.py` passes; nothing committed under vendor/ or out/

## Verify
`PURE_DISPLAY_RATE=1 tools/stutter_check.sh && python3 tools/docs_check.py`

## May touch
- docs/tasks/091-display-rate-storms.md (the Result), docs/windows.md (the E8 paragraph's line, if the verdict is
  the characterization)
- vendor/ only through `tools/patches.sh export 0031-<slug>` and only for a single named cause the probes prove;
  patches/README.md then gains its rows

## Must not touch
- include/psprecomp/, generated/, config/, src/, tools/, CMakeLists.txt, CMakePresets.json, docs/status.md,
  docs/decisions.md, the kernel's scheduler or pacer logic (a pacer change is a design call: escalate), anything
  not listed above

## Estimated turns
60

## Escalate when
- the overrun is the pacer's or the kernel's (report the figures; the fix is a design call for the planning session)
- the overrun is GPU-side (render or fence waits grow at 100 Hz): report the split; a renderer change needs its own
  brief
- a fix would touch more than one vendor file or anything under Must not touch

## Result

**Status: DONE.** The verdict is a characterization. No single cause accounts for the overrun, and there is no fix.
At 100 Hz the race misses the 10 ms budget on most frames, not only in the storms. A race frame costs about
11.7 ms of host work at either rate. The storms add about 0.7 ms of `game` on top. Nothing grows at 100 Hz: per
frame, the GPU, the fence wait and the depth store are flat or smaller than at 60.

### The runs (the rig, 2026-10-14, the Vulkan window, nothing else running)
| run | what | display | race seconds | speed | frame avg | stutter_check (25 ms) |
|---|---|---|---|---|---|---|
| out/091-100hz-norender | first try, worktree binary without the renderer (Open questions) | none | (no race) | | | NO RACE |
| out/091-100hz-off | `PURE_DISPLAY_RATE=1`, first window run of the rebuilt binary | **60 Hz** (`display rate: off`) | 192 | 100% | 16.7 | PASS 4/192 |
| out/091-60hz | `PURE_DISPLAY_RATE=0` | 100 Hz | 188 | 100.2% | 16.67 | PASS 2/188 |
| **out/091-100hz** | `PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=100` | 100 Hz (`display rate: 100 Hz (10000 us a vblank)`) | 235 | **85.1%** | **11.89** | PASS 8/235 |
| out/091-frames-100 | the same race through campaign_sweep with `PURE_TRACE_STALLS_MS=10` (a `[slow-frame]` line for every frame over 10 ms) | 100 Hz | 235 | 82.9% | 12.12 | (not judged) |
| out/091-frames-60 | the same with `PURE_DISPLAY_RATE=0` | 100 Hz | 202 | 100.1% | 16.67 | (not judged) |

All runs had `PURE_TRACE_GUEST=1`. The stutter_check probes are 091-60hz and 091-100hz. The per-frame runs exist
because stutter_check prints `[slow-frame]` only above 25 ms, so it cannot count frames over 10 ms. Those runs
copy stutter_check's environment and change only the threshold. **Their logging has a cost:** each printed line
lands in the `display` bucket. That bucket is 3.1 to 3.2 ms there against 1.9 to 2.1 ms in the probes, so about
+1.2 ms a frame at both rates. Their counts are therefore given at 10 ms and also at 11.2 ms, the line's cost
taken off.

The 60 Hz display in 091-100hz-off was the monitor's state when that run started. The 091-60hz run and the later
runs saw 100 Hz (the `[perf]` line's `FIFO 960x544 100Hz`). `PURE_DISPLAY_HZ=100` therefore only matches what the
shell reported for the rest of the session. It pins the rate so that a refresh change cannot turn the probe off
again.

### Over-10 ms frames: counts (non-poll flips, the frame's pacing sleep taken off; live-file flips apart)
| | 100 Hz (frames-100) | 60 Hz (frames-60) |
|---|---|---|
| presented frames in the race | ~19,470 | ~12,130 |
| over 10 ms | 14,884 (76%) | 10,575 (87%) |
| over 11.2 ms (the 1.2 ms of logging taken off) | 7,512 (39%) | 6,582 (54%) |
| over 12 / 13 ms | 3,302 / 1,003 | 3,595 / 1,344 |
| over 16.7 ms | 66 | 77 |
| over 25 ms | 1 | 2 |
| seconds with a frame over 10 ms | 235 of 235 | 202 of 202 |

The frames are the same at both rates. At 60 Hz just as many frames do more than 10 ms of work. The 16.7 ms frame
absorbs that work in its pacing sleep (4.0 ms a frame), and at 100 Hz there is no sleep left. Frames over 16.7 ms
are as rare at 100 Hz as at 60 (66 against 77).

The over-10 ms frames at 100 Hz average 11.65 ms: guest 7.07 + render 3.66 + wait 0.92 (fence 0.61, pacing 0.18),
with the GPU at 3.33. By band: 10 to 12 ms is 11,582 frames (guest 6.74, render 3.56); 12 to 14 ms is 2,901
(guest 8.00, render 3.89); 14 to 16.7 ms is 335 (guest 9.73, render 4.50). The guest and render grow together
through the bands, and the GPU and the fence stay flat.

### Per-bucket attribution, ms per game frame (the stutter_check probes, no per-frame logging)
| seconds | n | speed | frame avg | guest | render | wait | gpu | game | display | other HLE | hle | calls | store (in render) | fence | pacing |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 Hz all race | 231 | 85.1% | 11.89 | 5.61 | 4.31 | 1.97 | 3.18 | 3.25 | 2.06 | 0.30 | 2.36 | 643 | 0.49 | 1.65 | 0.16 |
| 100 Hz low game quartile | 57 | 86.9% | 11.84 | 5.51 | 4.13 | 2.20 | 3.08 | 2.90 | 2.34 | 0.28 | 2.62 | 489 | 0.49 | | |
| 100 Hz high game quartile (storms) | 57 | 83.1% | 12.15 | 5.98 | 4.21 | 1.95 | 3.13 | **3.63** | 2.04 | 0.31 | 2.36 | 726 | 0.49 | | |
| 60 Hz all race | 188 | 100.2% | 16.67 | 5.77 | 4.58 | 6.31 | 4.02 | 3.45 | 1.89 | 0.43 | 2.32 | 800 | 0.49 | 2.39 | 3.77 |
| 60 Hz low game quartile | 47 | 100.8% | 16.60 | 5.34 | 4.38 | 6.86 | 3.69 | 3.08 | 1.88 | 0.39 | 2.27 | 592 | 0.49 | | |
| 60 Hz high game quartile (storms) | 47 | 100.0% | 16.69 | 6.18 | 4.59 | 5.91 | 4.02 | **3.84** | 1.90 | 0.45 | 2.35 | 958 | 0.48 | | |

`wait` is the GPU fence plus pacing (the `[stalls]` means, weighted by frames). `other HLE` is kernel, io, sas,
audio, ge and other together.

### The storms' worst seconds (the highest `game` bucket: raw `[guest-split]` with its `[perf]`)
100 Hz (out/091-100hz):
```
#128 game 4.05 | kernel 0.06 io 0.00 sas 0.07 audio 0.07 ge 0.05 display 1.67 other 0.05 | store 0.48 | guest 6.02 hle 1.98 calls 667 || fps 84.0 speed 84% | frame avg 11.9 max 24.2 | guest 6.0 render 3.7 wait 2.2
#54  game 3.95 | kernel 0.07 io 0.00 sas 0.09 audio 0.06 ge 0.06 display 2.00 other 0.05 | store 0.48 | guest 6.28 hle 2.33 calls 880 || fps 75.7 speed 76% | frame avg 13.2 max 26.0 | guest 6.3 render 4.5 wait 2.5
#46  game 3.92 | kernel 0.07 io 0.00 sas 0.09 audio 0.07 ge 0.05 display 1.76 other 0.05 | store 0.48 | guest 6.02 hle 2.10 calls 862 || fps 80.1 speed 80% | frame avg 12.5 max 21.1 | guest 6.0 render 4.3 wait 2.2
```
60 Hz (out/091-60hz):
```
#102 game 4.42 | kernel 0.11 io 0.00 sas 0.18 audio 0.12 ge 0.06 display 1.72 other 0.04 | store 0.48 | guest 6.66 hle 2.23 calls 1441 || fps 60.0 speed 100% | frame avg 16.7 max 40.8 | guest 6.7 render 5.5 wait 4.5
#105 game 4.27 | kernel 0.09 io 0.00 sas 0.19 audio 0.12 ge 0.05 display 1.78 other 0.05 | store 0.48 | guest 6.56 hle 2.29 calls 1141 || fps 60.0 speed 100% | frame avg 16.7 max 28.4 | guest 6.6 render 4.5 wait 5.6
#101 game 4.15 | kernel 0.12 io 0.00 sas 0.14 audio 0.12 ge 0.05 display 1.90 other 0.05 | store 0.48 | guest 6.53 hle 2.38 calls 1522 || fps 60.0 speed 100% | frame avg 16.7 max 31.3 | guest 6.5 render 4.6 wait 5.6
```
At 60 Hz the storms take `game` to 4.2 to 4.4 ms and the frame still sleeps 4.5 to 5.6 ms. At 100 Hz the same swell
takes `game` to 3.9 to 4.1 ms, and the frame is already over budget, so the race drops to 76 to 84% speed and
75 to 84 fps. The seconds cannot be paired one to one, because at 85% speed the 100 Hz race reaches each place
later. The storms are matched by their swell: the `game` bucket and the HLE call count rise together (726 against
489 calls a frame at 100 Hz).

One episode is excluded and kept apart: seconds #179 to #184 of out/091-100hz (lap 3) had 30 to 250 ms frames
inside the **`display`** bucket (7.8 to 21.3 ms a frame, speed 38 to 50%), with `game` 4 to 8 ms. That is
stutter_check's "worst second #180" (flip 21386, 250 ms). It did not recur in out/091-frames-100 on the same race,
which had one frame over 25 ms. It is a host stall inside sceDisplay's host work (the shell's event pump), the same
bucket as the first-run stall docs/status.md records but here in the binary's third run. It is not storm cost.

### What the overrun is made of
1. **Not a storm-only effect.** The calm quartile is already 11.8 ms against a 10 ms frame. The storms add +0.73 ms
   of `game` at 100 Hz (2.90 to 3.63) and +0.76 ms at 60 (3.08 to 3.84), the same swell task 082 named. It is
   smaller in absolute terms since the inlining fix (082's +2.4 ms over 8 ms).
2. **The recompiled code's own cost: 3.3 ms.** Rate-independent per frame (3.25 at 100, 3.45 at 60).
3. **An HLE bucket: `display`, 2.1 ms a frame.** This is sceDisplay's host work outside render (the shell's event
   pump, the input script, the overlay revalidation; task 082). It is the largest HLE item and is the same at both
   rates (2.06 / 1.89).
4. **`store`: 0.49 ms, flat and inside render.** Not a cause.
5. **Time outside the split:** render 4.3 ms (CPU-side GE decode and draw recording), plus the GPU fence wait of
   1.65 ms at 100 Hz (2.39 at 60). The GPU itself is 3.2 ms a frame at 100 (4.0 at 60). The fence wait **shrinks**
   at 100 Hz, so this is not a GPU-side growth. Pacing is 0.16 ms at 100 Hz: the pacer never sleeps, so the
   overrun is not its cost.

Sum at 100 Hz: game 3.25 + HLE 2.36 + render 4.31 + fence 1.65 + pacing 0.16 + present/acquire/submit/copy ~0.2 =
11.9 ms against 10.0. The whole frame is over budget, and on a per-frame basis no part of it grows with the rate.
The escalation conditions do not hold: the overrun is not the pacer's or the kernel's, render and the fence do not
grow at 100 Hz, and no single fix in May touch covers it. The 1.9 ms over budget has no one owner. The two largest
movable items are render (4.3) and `display` (2.1), and each would be its own brief (the renderer; the shell's
per-flip work).

### The verdict
The characterization. docs/windows.md's E8 entry gains the figures in a short paragraph rather than the brief's
single line: this rig's race needs about 11.7 ms a frame, so the 100 Hz race holds 85 fps at 85% speed and dips to
76 to 80% in the storms. Original (60) is the smooth setting on this machine. A clean Display rate at 100 Hz wants
about 2.5 ms (25%) more headroom a frame, and more at 120 Hz (an 8.3 ms frame). The stutters Erik saw in the
effect-heavy moments are the storms' extra 0.7 ms deepening an overrun that is present all race. At 100 fps with
FIFO, each 11 to 13 ms frame misses a refresh, and the deeper dips are the ones a player notices.

### Changed
- docs/windows.md (E8 entry under step 4: the measured figures and the headroom statement)
- docs/tasks/091-display-rate-storms.md (this Result)
- Nothing under vendor/, src/, tools/ or out/ committed. No patch.

### Verify output
Per the coordinator's instruction ("do not redo any runs"), the Verify line's stutter_check was not run again
after the probes. Its 100 Hz equivalent is the out/091-100hz probe, which is the Verify command plus
`PURE_TRACE_GUEST=1 PURE_DISPLAY_HZ=100 --out out/091-100hz`. `python3 tools/docs_check.py` was run after the
edits.
```
stutter_check: shell vulkan, backend vulkan, out .../out/091-100hz
stutter_check: campaign_sweep exit 0, 301 s, log .../out/091-100hz/race/single_race-vineta_k.log
race: PASS, paced from flip 6100; 235 seconds, 19888 frames
(a) seconds with a frame over 25 ms: 8 of 235 (3.4%); apart, the live-file flips (a multiple of 10) over it: 350, worst 177.0 ms
(b) readback: 0.00 ms a frame
worst second: #180 after the paced flip, frame avg 29.5 max 250.3 ms, flip 21386 250.3 ms
stutter_check: PASS (8 of 235 seconds over 25 ms, readback 0.00 ms a frame)
docs_check: 35 files, 0 findings: PASS
```

### Open questions
- **The status row's "PASS at the 100 Hz budget" (2026-10-14, the rig on the pull) never ran at 100 Hz.** Its log
  (the main checkout's out/stutter_check/vulkan-vulkan) says `[pure] display rate: off`, `MAILBOX 960x544 60Hz`,
  and has 11391 frames in 189 s, so 60 fps. My first run of the day did the same (`FIFO ... 60Hz`), while
  EnumDisplaySettings and SDL3 itself, queried directly a few minutes later, reported 3440x1440 at 100 Hz. Later
  runs saw 100 Hz. The shell's refresh follows the monitor's state at the time (a remote session or a mode change).
  The rig's E8 gate should pin `PURE_DISPLAY_HZ=100` or check the `display rate:` line before it is believed. That
  is a tools change outside this brief.
- **The 100 Hz race runs slow, not just uneven.** At 85% speed the game's virtual clock falls behind real time
  (235 real seconds of race against 188 at 60). Whether an overrun at the Display rate should drop vblanks (hold
  real time) or slow down (today) is a pacer/kernel design call for the planning session. One option is an
  automatic fallback to the PSP's rate when the speed stays under ~95%.
- **Worktree builds on the rig have no renderer.** CMakePresets.json's `SDL3_ROOT=${sourceDir}/../deps/...` points
  under `.claude/worktrees/` in a worktree, so SDL3 is not found and the Vulkan shell is not compiled
  (`Renderer: not built`; the sweep then times out with NO RACE). I worked around it in the build dir only
  (`cmake -B build/win-x64 -DSDL3_ROOT=H:/errei/Documents/dev-stuff/deps/SDL3-3.4.18 -DSDL3_DIR=.../cmake`, then a
  10 s rebuild from ccache). tools/worktree_init.sh or the preset should handle it.
- The `display` bucket's 2.1 ms a frame (shell pump, input script, overlay) is the cheapest-looking 2 ms to win
  back, but only after measuring how much of it a player's build (no input script) pays.
- The one-off display stall of seconds #179 to #184 (250 ms frames inside sceDisplay's host work, mid-race, not a
  first run) did not recur. If it recurs in play, it is its own problem, separate from the storms.

## Review (Fable, 2026-10-14)

Merged c2c66b9 into batch/m2. The verdict stands: the characterization, no patch. The attribution holds — the
per-bucket sum (game 3.25 + HLE 2.36 + render 4.31 + fence 1.65 + pacing 0.16 + present ~0.2) reproduces the
11.9 ms measured frame, nothing grows per frame at 100 Hz, and the fence wait shrinks there, so the brief's
escalation conditions (pacer, kernel, GPU-side growth) do not hold. The 250 ms display-bucket episode of seconds
#179 to #184 is rightly kept apart from the storm story: same bucket as the first-run scanner stall, did not recur.
The extra probes (norender, the display-rate-off first run) were earned, not scope creep — the off run exposed
that the shell's refresh follows the monitor's state at launch, which invalidates the 2026-10-14 status row's
"PASS at the 100 Hz budget" (that gate ran at 60; the status row is corrected today).

Three Open questions are now the planning session's:
1. The E8 gate must pin `PURE_DISPLAY_HZ=100` (or assert the `display rate:` log line) before its PASS is believed
   — a tools/stutter_check.sh change, to be folded into the next tools task.
2. The 100 Hz race runs slow (85% speed), not just unevenly — whether the Display rate should drop vblanks or
   slow down, and whether to auto-fall-back to Original under ~95% speed, is a design call for docs/decisions.md
   before any pacer work is briefed.
3. Worktree builds on the rig lose the renderer (`SDL3_ROOT=${sourceDir}/../deps/...` resolves wrong under
   .claude/worktrees/) — tools/worktree_init.sh or the preset should pass the absolute path; until then every
   rig worker needs the cmake -D workaround this Result records.
