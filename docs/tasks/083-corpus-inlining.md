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
One vendor patch, `patches/0025-corpus-inlining.patch` (through `tools/patches.sh export`), its rows in
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
- vendor/portablekit/cmake/PortableKit.cmake: only through `tools/patches.sh export 0025-corpus-inlining`; commit
  patches/, never vendor/
- patches/0025-corpus-inlining.patch (new), patches/README.md
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
Both `/Ob0` sites in vendor/portablekit/cmake/PortableKit.cmake became `/Ob2` (patches/0025-corpus-inlining.patch,
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
