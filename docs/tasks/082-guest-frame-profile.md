# 082: Where the rig's guest frame goes

Milestone: Windows fidelity (Erik, 2026-10-12: "I'd consider my cpu quite far above what should be required to run
a recomp like this" — he is right, and nobody has measured where the 9 to 11 ms go) | Branch:
task/082-guest-frame-profile | Status: OPEN

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
- **The instrument**, `patches/0024-guest-time-split.patch`: a guest-thread split behind `PURE_TRACE_GUEST=1` — a
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
  all only through `tools/patches.sh export 0024-guest-time-split`; commit patches/, never vendor/
- patches/0024-guest-time-split.patch (new), patches/README.md
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
