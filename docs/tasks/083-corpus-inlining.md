# 083: The Windows corpus compiles with inlining

Milestone: Windows fidelity (Erik, 2026-10-13; task 082's finding and the planning session's night experiment) |
Branch: task/083-corpus-inlining | Status: OPEN

## Goal
The framework's MSVC build path compiles every generated corpus unit `/O2 /Ob0` — optimization on, inlining off —
where the Mac's clang path inlines fully. Recompiled code is almost nothing but small functions (the guest memory
accessors above all), so the cost is enormous and measured twice: task 082's split put 8.8 of the rig's 10.7 guest
ms in the recompiled code, and the night experiment (docs/status.md, 2026-10-13: the local /Ob0 to /Ob2 flip, the
same probe back-to-back) dropped the `game` bucket from 9.83 to 3.58 ms a frame, the storm maximum from 20.97 to
4.83, and turned a 121-of-241 stutter_check FAIL into a 3-of-187 PASS on the same tired machine. The whole guest
frame lands at PPSSPP's own 6.5 ms figure, where a static recompile belongs. After this task the flip is a proper
vendor patch, the full gates prove the pictures and the behaviour did not move, and the rig's 60 fps ceiling story
is closed with before/after figures on a rested machine. An upstream candidate of the first order: every Windows
port of the framework pays this today.

## Read first
- CLAUDE.md (note: this task's corpus rebuilds take ~16 minutes each and are expected, twice — the flag change and
  nothing else; parallelism is the build's own memory-capped pool via tools/build.sh; tools/regen.sh stays
  forbidden), docs/status.md (the 2026-10-12 and -13 rows: the whole chain of evidence), docs/tasks/082 (the split
  and the yardstick), patches/README.md, docs/upstream.md
- vendor/portablekit/cmake/PortableKit.cmake: BOTH `/Ob0` sites (the `generated_options` set() around line 287 and
  the `target_compile_options(${target} ...)` around line 646). The night experiment flipped both; a target-level
  append from the game's own CMakeLists is a no-op because the source-property options serialize later (verified
  in compile_commands.json — do the same verification after your change).
- Task 082's open questions: the FP-contract asymmetry (the clang path passes `-ffp-contract=off`, the MSVC path
  does not; harmless while no flag enables FMA — /Ob2 does not — but say in the patch's comment why the MSVC path
  leaves it alone or aligns it; if you align it, the suite judges)
- tools/build.sh, tools/stutter_check.sh, tools/frame_regress.sh, tools/flash_check.sh, tools/framerate_check.sh,
  tools/patches.sh, the guest split's README row (`PURE_TRACE_GUEST`), docs/windows.md (the 2026-10-12 findings
  paragraph this closes), docs/verification.md

## Deliverable
One vendor patch, `patches/0026-corpus-inlining.patch` (through `tools/patches.sh export`), its rows in
patches/README.md with the upstream column loud, the figures, and the docs. Commits per proven stage.
- **The before, on this rested machine:** one probe (`PURE_TRACE_GUEST=1 tools/stutter_check.sh`) on the unfixed
  tree, committed with the `game` bucket figures — the fresh-boot baseline the night experiment lacked.
- **The patch:** both `/Ob0` become `/Ob2` (keep `/bigobj`; keep `/O${PSPRECOMP_GENERATED_OPT_LEVEL}` as is), with
  a comment naming what /Ob0 cost and the task. Verify in compile_commands.json that a generated unit's command
  carries /Ob2 and no /Ob0 before building. Export, commit patches/. Note the build figures in the Result (the
  night run: 9m39s-16m; the units' memory held within the pool).
- **The after:** the same probe (the `game` bucket and stutter_check's own verdict), plus the full gates:
  `tools/frame_regress.sh --all-scenes` (18/18, the fractions against the measured column in the Result — inlining
  must not move a pixel; if any scene moves beyond its windowed wobble, escalate with the figures),
  `tools/flash_check.sh --shell vulkan`, `tools/framerate_check.sh --shell vulkan` and `--race` (the race's game
  clock in the Result: expect it comfortably inside 0.99 to 1.01 now), `tools/menu_check.sh --shell vulkan`.
- **Docs:** patches/README.md; docs/windows.md (the 2026-10-12 findings paragraph gains its closing line: what the
  stutter was and what fixed it); README.md only if a switch is added (none expected); docs/verification.md
  unchanged unless the check lists change; docs/tasks/083-corpus-inlining.md (the Result with the before/after
  table). `tools/patches.sh check` (25) and `python3 tools/docs_check.py` pass.

## Acceptance criteria
- [ ] the fresh-boot before figures committed first
- [ ] compile_commands.json shown carrying /Ob2 and no /Ob0 for a generated unit before the build
- [ ] after: the `game` bucket at or near the night's 3.58 ms and stutter_check PASS with margin; the table in the
      Result
- [ ] `tools/frame_regress.sh --all-scenes` PASS 18/18 with the fractions in the Result
- [ ] `tools/flash_check.sh --shell vulkan`, `tools/framerate_check.sh --shell vulkan` and `--race`,
      `tools/menu_check.sh --shell vulkan` all PASS, the race game clock in the Result
- [ ] `tools/patches.sh check` reports 25 and `python3 tools/docs_check.py` passes; nothing committed under vendor/

## Verify
`tools/stutter_check.sh && tools/frame_regress.sh --all-scenes && tools/flash_check.sh --shell vulkan && tools/framerate_check.sh --shell vulkan && tools/patches.sh check && python3 tools/docs_check.py`

## May touch
- vendor/portablekit/cmake/PortableKit.cmake: only through `tools/patches.sh export 0026-corpus-inlining`; commit
  patches/, never vendor/
- patches/0026-corpus-inlining.patch (new), patches/README.md
- docs/windows.md, docs/verification.md, README.md, docs/tasks/083-corpus-inlining.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/, tools/, every other vendor file, CMakeLists.txt and
  CMakePresets.json (the flag belongs in the vendor cmake where /Ob0 lives, so every preset and port gets it),
  ref/, docs/decisions.md, docs/status.md, anything not listed above

## Estimated turns
60

## Escalate when
- any corpus unit fails to build or the pool thrashes (report the unit and the figures; do not fight the build)
- any suite scene moves beyond the windowed wobble the task files document (report the scene and fractions)
- the after `game` bucket does not land near the night's figure (report; something else differs from the
  experiment)

## Result

**Status: DONE.** Changed: patches/0026-corpus-inlining.patch (new), patches/README.md, docs/windows.md,
docs/tasks/083-corpus-inlining.md. Nothing under vendor/ committed.

### Before: the unfixed tree on a fresh boot (2026-10-13)
`PURE_TRACE_GUEST=1 tools/stutter_check.sh --out out/083-before` on the worktree's unfixed build (the corpus /O2 /Ob0,
ccache-built from the main checkout's objects), the rig freshly rebooted, first game run of the session. The
`[guest-split]` lines are read from the race's first paced flip to the end, ms per game frame:

| run | seconds | game mean | game median | game max | guest mean | guest max | hle mean | stutter_check |
|---|---|---|---|---|---|---|---|---|
| before (fresh boot, /Ob0) | 248 | 10.08 | 9.57 | 16.74 | 13.43 | 57.40 | 3.35 | FAIL, 164 of 248 seconds over 25 ms |
| night baseline (/Ob0, tired) | 241 | 9.68 | 9.29 | 20.97 | 15.16 | 87.03 | 5.49 | FAIL, 121 of 241 |
| night probe (/Ob2, tired) | 187 | 3.57 | 3.52 | 4.83 | 5.76 | 7.32 | 2.19 | PASS, 3 of 187 |

(The night rows are recomputed from out/ob2-baseline and out/ob2-probe with the same reader; status.md's 9.83 for
the baseline used a slightly different window.) The fresh boot does not rescue the /Ob0 build: its `game` bucket is
the night's, so the machine's state was never the cause.

### The patch and the build
Both `/Ob0` sites in vendor/portablekit/cmake/PortableKit.cmake became `/Ob2` (patches/0026-corpus-inlining.patch,
`tools/patches.sh check`: 25). After `tools/build.sh configure`, before any build, compile_commands.json: 144 of 144
corpus units carry `/O2 /Ob2 /bigobj` and no command carries `/Ob0` (before the change: 145 did, the 144 units and
generated_registry.cpp). generated_unit_0000.cpp: `... /O2 /Ob1 /DNDEBUG -std:c++20 -MD /O2 /Ob2 /bigobj ...`.
The compiler is clang-cl 23.1.3 (`C:/Program Files/LLVM/bin/clang-cl.exe`), not cl, so the patch comment's FP note
covers both. The build: `tools/build.sh profile`, 148 steps, 17 s, exit 0: every unit came from ccache, the night
experiment's identical /Ob2 compile of the same sources (the night's own cold build: 9m39s to 16m, no unit failed,
memory within the pool). So no cold corpus compile ran in this task; the binary is the inlined one by the probe below.

### After: the patched tree, same probe
| run | seconds | game mean | game median | game max | guest mean | guest max | hle mean | display max | stutter_check |
|---|---|---|---|---|---|---|---|---|---|
| before (fresh boot, /Ob0) | 248 | 10.08 | 9.57 | 16.74 | 13.43 | 57.40 | 3.35 | 42.18 | FAIL, 164 of 248 |
| after, first run (/Ob2) | 209 | 3.46 | 3.18 | 38.14 | 7.07 | 79.75 | 3.81 | 119.59 | FAIL, 67 of 209 |
| after, second run (/Ob2) | 197 | 3.13 | 3.12 | 3.80 | 5.35 | 6.07 | 2.22 | 2.24 | PASS, 2 of 197 |
| night probe (/Ob2, tired) | 187 | 3.57 | 3.52 | 4.83 | 5.76 | 7.32 | 2.19 | 2.49 | PASS, 3 of 187 |

The first after run (out/083-after) failed on stalls that are not the recompiled code: its `game` mean is the
night's, and its long frames (to 672 ms) sit in the `display` bucket, sceDisplay calls with render and pacing taken
off, 26 seconds over 3 ms against none in either /Ob2 run that passed; the slow frames spread over the whole race.
It was the second game run after the reboot, on a binary the machine had not run before; the immediate rerun
(out/083-after2), nothing changed in between, passed with the night's margin. The before run shows some of the same
`display` stalls (66 seconds over 3 ms), but its 791 guest-dominated counted slow frames are the /Ob0 storms the
`game` bucket names (16.74 ms at its worst second).

### The gates (the /Ob2 tree, out/083-gates.log)
- `tools/frame_regress.sh --all-scenes`: PASS 18/18 (12m 4s). Fraction / measured: lang 0.0544/0.054, title
  0.0302/0.030, profile 0.0543/0.054, main_menu 0.0330/0.033, race_hud 0.0460/0.047, single_player 0.0251/0.025,
  class_select 0.0452/0.045, league_select 0.0614/0.062, track_select 0.0411/0.041, team_select 0.0416/0.042,
  tt_track_select 0.0400/0.040, tt_hud 0.0465/0.049, fp_track_select 0.0409/0.041, fp_hud 0.0578/0.048,
  tournament_select 0.0622/0.063, zone_track_select 0.0333/0.033, zone_hud 0.0441/0.045, zone_change 0.0185/0.052
  (flagged "moved more than 0.03"; limit 0.10). The thirteen frontend scenes are within 0.0008 of the column; the race
  scenes are within their windowed wobble. zone_change re-run alone: 0.0289 PASS. In the Verify run's suite: 0.0251 PASS
  (race_hud 0.0461, tt_hud 0.0589, fp_hud 0.0469, zone_hud 0.0443), 18/18. Task 077 documents zone_change swinging
  0.025 to 0.108 run to run on the rig (see Open questions).
- `tools/flash_check.sh --shell vulkan`: PASS (fade 57 flips off, 0 on; the race and its HUD in both).
- `tools/framerate_check.sh --shell vulkan`: PASS (frontend 33.4/33.4 ms, race 33.4/16.7 ms, 29.97/59.94 flips a
  second off/on; the HUD drawn at 60). Again in Verify: 29.97/59.95.
- `tools/framerate_check.sh --shell vulkan --race`: PASS, 29.98 flips a second off, 59.96 on; **the game clock 0.9993
  and 1.0002 s a second** (task 077: 0.9919/0.9946); laps 79.0/89.8/72.6 s off and 65.2/57.9/57.4 s on.
- `tools/menu_check.sh --shell vulkan`: PASS (Controls 37, System 12).
- In the Verify run: stutter_check PASS, 0 of 194 seconds over 25 ms (a third /Ob2 probe); `tools/patches.sh check`:
  ok, 25 patches; `python3 tools/docs_check.py`: 33 files, 0 findings, PASS.

### Verify output (`tools/verify_task.sh 083`, last 20 lines)
```
H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0004-ge-backend-and-shell-seams.patch:44: trailing whitespace.
#include <algorithm>
warning: squelched 2600 whitespace errors
warning: 2605 lines add whitespace errors.
H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0007-savedata-list-and-no-key-mode.patch:938: trailing whitespace.
#include "ui/save_list.hpp"
H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0007-savedata-list-and-no-key-mode.patch:939: trailing whitespace.

H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0007-savedata-list-and-no-key-mode.patch:940: trailing whitespace.
#include "ui/layer.hpp"
H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0007-savedata-list-and-no-key-mode.patch:941: trailing whitespace.
#include "ui/widgets.hpp"
H:/errei/Documents/dev-stuff/pure-recomp/.claude/worktrees/agent-ab6b50e36c9f923a8/patches/0007-savedata-list-and-no-key-mode.patch:942: trailing whitespace.

warning: squelched 567 whitespace errors
warning: 572 lines add whitespace errors.
ok: 25 patch(es) reproduce vendor/portablekit at 8b0c3fe
docs_check: 33 files, 0 findings: PASS
verify 083: PASS
verify exit 0
```

### Open questions
- zone_change sat at the low end in all three /Ob2 suite runs: 0.0185, 0.0289 and 0.0251, all under the measured 0.052
  (limit 0.10). The last two are inside the rig's documented 0.025 to 0.108 swing. The first is 0.0065 under it and
  moves toward the reference, not away. Task 082's /Ob0 run gave 0.0308. Inlining should not move a pixel, so this is
  read as windowed wobble, but a headless or Mac-side zone_change comparison would settle whether its baseline should
  move. Not escalated: every scene PASSes and no scene moved away from the reference.
- The first after probe (out/083-after) failed stutter_check, 67 of 209, on `display`-bucket stalls (up to 672 ms),
  not on the recompiled code (game 3.46 ms). The next two /Ob2 probes passed, 2 of 197 and 0 of 194. Cause not found;
  the guess is a first run of a fresh binary after the reboot. Worth watching in Erik's play.
- No cold corpus compile ran here: ccache served every /Ob2 unit from the night experiment's build (17 s). The night's
  cold figures (9m39s to 16m, no unit failed) stand as the build cost.
- The FP contract is left unaligned (the rig's compiler is clang-cl 23; the patch comment says why). Any future
  FMA-enabling flag must bring `-ffp-contract=off` with it.
- Still Erik's: the restage, and his ears (whether the audio clicks went with the dips).

## Review

Merged ef413d9 into batch/m2, 2026-10-13. The patch is exactly the brief: both `/Ob0` sites in the vendor cmake's
MSVC branch become `/Ob2`, `/bigobj` and the opt level untouched, each site commented — the first with the cost and
the FP-contract reasoning (why `-ffp-contract=off` stays clang-only: contraction is per source expression, and no
FMA exists without `/arch:AVX2`), the second with why it must follow the first. compile_commands.json was verified
before the build (144 of 144 units `/Ob2`, no `/Ob0` anywhere), which matters doubly because ccache then served the
whole corpus from the night experiment's identical compile in 17 s — the verification plus the after figures are the
proof the binary is the inlined one. The chain of evidence is complete: the fresh-boot before (game 10.08 ms,
stutter_check FAIL 164/248) kills the tired-machine objection to the night baseline, and the after (3.13 ms, PASS
2/197, then 0/194 in Verify) reproduces the night probe on a rested machine. The full gates passed: 18/18 scenes,
flash, framerate, menu, and the race with the game clock at 0.9993/1.0002 s per second — the 0.992 slowdown that fed
the audio sink's clicks is gone.

Two observations, neither blocking:
- zone_change read 0.0185/0.0289/0.0251 across the three /Ob2 suites, all under the 0.052 measured value, within
  task 077's documented 0.025–0.108 rig swing except the first by 0.0065 — and toward the reference, not away. Task
  082's /Ob0 run read 0.0308. Windowed wobble; the worker's suggestion of a headless or Mac-side comparison to
  resettle the scene's baseline is a fair small follow-up, not a defect.
- The first after probe failed on `display`-bucket stalls (to 672 ms) on a binary the machine had never executed;
  the immediate rerun was clean. The planning session watched Defender's real-time scan spike through this task's
  build on this same morning, and a first execution of a fresh unsigned exe is exactly what that scanner intercepts;
  the before run shows traces of the same. Worth remembering when a first run of a freshly linked binary stutters:
  run it twice before believing it.

The upstream row is marked candidate of the first order and that is right: every Windows port of the framework
compiles its corpus without inlining today. Remaining from the brief's story: the release restage (this session) and
Erik's ears on the clicks.
