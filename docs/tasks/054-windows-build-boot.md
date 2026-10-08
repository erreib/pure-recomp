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
