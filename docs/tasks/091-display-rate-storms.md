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
