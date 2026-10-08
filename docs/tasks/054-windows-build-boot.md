# 054: Windows build and boot

Milestone: W1 (docs/windows.md step 1) | Branch: task/054-windows-build-boot | Status: OPEN

Run by the planning session itself on Erik's Windows machine (Erik, 2026-10-08): the step needs the corpus
regenerated (`tools/regen.sh` is forbidden to workers) and builds past the 5-minute escalation line.

## Goal
The game builds and runs on Windows x64: the frontend route reaches the main menu and a Vineta K race on the
framework's Vulkan renderer, headless and in a window. What docs/windows.md step 1 names: a Windows CMake preset
(clang-cl preferred, MSVC fallback), toolchain notes in docs/setup.md, FFmpeg as the framework's scripts fetch it
(the BtbN LGPL shared zip on Windows), the data directory under the user's profile, the disc image path, and a way
to build without the Mac-only `tools/build.sh` assumptions.

## Read first
- docs/windows.md
- docs/approach.md, docs/status.md
- vendor/portablekit/docs/BUILDING.md, README.md (prerequisites table), cmake/PortableKit.cmake (renderer deps),
  cmake/FFmpeg.cmake (Windows branch)
- CMakeLists.txt, CMakePresets.json, tools/build.sh, tools/vendor_setup.sh, tools/worktree_init.sh

## Deliverable
- `CMakePresets.json`: a `win-x64` configure/build preset (Ninja, clang-cl or MSVC, RelWithDebInfo, ccache when
  present) that excludes the Metal backend and shell (macOS only; our CMakeLists gates them on `APPLE`).
- The corpus regenerated on this machine into `generated/` (never committed).
- `tools/build.sh` (or a sibling) building on Windows under Git Bash.
- docs/setup.md: a Windows section (toolchain, Vulkan SDK, SDL3, FFmpeg, traps).
- The frontend route to the main menu and a Vineta K race, headless and in a window, on the Vulkan path.

## Acceptance criteria
- [ ] `tools/build.sh profile` (Git Bash) configures and builds `build/win-x64/bin/PureNative.exe`
- [ ] headless frontend route runs to its end frame without a halt or unlowered instruction
- [ ] a windowed run shows the frontend; a race on Vineta K starts and runs
- [ ] `tools/frame_regress.sh --shell vulkan --backend vulkan` against the Vulkan column, references retaken or
      tolerances noted where the Mac's Vulkan values do not transfer (docs/windows.md: references are per machine)
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/frame_regress.sh --shell vulkan --backend vulkan`

## May touch
- CMakeLists.txt, CMakePresets.json, tools/ (build/runner scripts), docs/setup.md, docs/windows.md, docs/status.md,
  README.md, patches/ (via tools/patches.sh export) if the framework needs a Windows fix

## Must not touch
- vendor/ directly, include/psprecomp/, src/gpu/ (Metal code stays as it is), config/

## Estimated turns
long (one session)

## Escalate when
The framework's Windows build is broken in a way a patch under 100 lines does not fix; or the Vulkan renderer
cannot reach the menu on this GPU.

## Result
Status: PARTIAL (everything proven except the Verify, which waits on `ref/` from the Mac)

Changed: CMakeLists.txt (Metal gated on APPLE), CMakePresets.json (win-x64: clang-cl, lld-link, llvm-rc, llvm-mt),
tools/env.sh, tools/build.sh, tools/regen.sh (platform branches), tools/setup_game.sh, tools/purelib/port.py
(hard links, tasklist, a pipe runner in place of the pty), tools/frame_regress.sh (hard-linked game dir),
tools/docs_check.py (forward-slash paths on Windows), src/tools/ge_replay.cpp (process.h for getpid),
docs/setup.md (the Windows section), this brief.

Toolchain installed (winget): LLVM 23.1.3, Vulkan SDK 1.4.363.0 (the Mac's version), ccache 4.14.1; SDL3 3.4.18
VC devel unpacked to deps/; VS 2022 Build Tools (MSVC 14.39, cmake 3.28, ninja) were present. FFmpeg 7.1.5 came
prebuilt through cmake/FFmpeg.cmake's Windows branch. The disc image in Downloads matched CRC32 4502C588; no
Developer Mode means no symlinks, so disc.iso and the game dirs use hard links (Downloads and the repo share H:).

Measured: corpus regenerated on this machine (145 units, 149 MB; codegen seconds, the cold compile 14.5 min at 6
jobs; one compile failure, the unistd.h include above). Frontend route headless to frame 2200 in 3.9 s, exit 0;
the same with PSPRECOMP_NO_INTERPRETER=1 (no unlowered instruction). The menu+race route headless with
PSPRECOMP_NO_INTERPRETER=1 to frame 6400: exit 0, 686,967 draws, 573 block transfers, no halts. Windowed on the
Vulkan shell and backend (RTX 3080, Vulkan 1.4.312): swapchain 960x544 FIFO, frontend route exit 0 with
lang/notice/profile/title shots, menu+race route exit 0 with menu and race shots; race_hud.png shows the full
Vineta K first-lap frame (HUD, ship, AI pack, bloom, crowds). python tools/docs_check.py: 33 files, 0 findings.

Verify output (last 20 lines): not run. `tools/frame_regress.sh --shell vulkan --backend vulkan` exits 2 at its
reference check: the 14 ref/*.png are git-ignored PPSSPP captures that live on the Mac (ref/README.md documents
them; docs/windows.md says the software-renderer PNGs transfer). Waiting on Erik copying the Mac's ref/.

Open questions: whether the Mac's Vulkan measured column transfers to an RTX 3080 (MoltenVK vs native driver;
re-measure and re-baseline if a scene moves); the winget ccache path in tools/env.sh is version-pinned
(ccache-4.14.1) and needs a touch on upgrade; Git Bash pipe runs lose line-grain timing (block-buffered stdout),
fine for run_boot, to re-examine for campaign_sweep's live steering in step 2.
