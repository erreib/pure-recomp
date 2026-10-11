# Windows bring-up: the plan

Written 2026-10-07 on the Mac, for the session that starts on Erik's Windows machine. Read docs/approach.md first,
then docs/status.md; this file says what Windows needs and in what order. Each step is a task brief under docs/tasks/
(054 onward) when it is dispatched; the shapes are here so the Windows session can write them.

## What transfers as it is

- The framework (PortableKit, vendored at 8b0c3fe with our nine patches): it builds on Windows (Yakumo ships there);
  `cmake/PortableKit.cmake` has the MSVC branches (`/O<level> /Ob0 /bigobj`, the 1 MiB default stack the comment
  near line 523 explains).
- Our profile (src/profile/), the HLE overrides (src/hle/), the host entry point (src/host/pure_main.cpp: it sets
  Metal by default only on macOS), the patches, the config, the pad scripts.
- The generated corpus: regenerated from the disc on the new machine (`tools/regen.sh`: codegen about 85 s, the
  compile 15 to 20 minutes), never copied.
- The rounding rules (patch 0009-vfpu-rounding): integer code for the PSP's rule and explicit `std::fma` for the
  test mode, so x64 rounds as arm64 does. `-ffp-contract=off` is clang's flag; MSVC's `/fp:precise` does not contract
  by default (check `cl` and `clang-cl` both).
- The Python tools (tools/*.py, tools/purelib): plain Python 3; the PPSSPP driver works with the Windows build of
  PPSSPP (its debugger is the same).

## What does not

- The Metal backend and shell (src/gpu/metal_*.mm, src/gpu/shaders/ge.metal, src/host/metal_shell.*): macOS only,
  excluded from the Windows build; the Vulkan renderer and shell (the framework's, behind our seams) are the path.
- The macOS bundle (tools/bundle.sh, packaging/release.env's macOS parts): the framework has Windows release
  scripting (Yakumo's RELEASING.md describes zip packaging with `tar.exe` and a game-data check); reuse it.
- The bash tools (tools/*.sh: frame_regress, verify_task, hud_check, save checks, the Metal checks): Git Bash or
  WSL runs them; the Metal-only ones are skipped.
- The scorecard's references under ref/scorecard and the VFPU samples under ref/vfpu: recorded with PPSSPP's Apple
  Silicon JIT, whose rounding is its compiler's (docs/fidelity.md, difference 13). PPSSPP's x64 JIT rounds
  differently. Retake the references on Windows (`tools/scorecard.py --refresh-references`) rather than compare
  against the Mac's; the picture references under ref/*.png are PPSSPP's software renderer and transfer.

## The steps

1. **Build and boot (one task).** A CMake preset for Windows (clang-cl preferred, MSVC as the fallback), the
   toolchain notes in docs/setup.md, FFmpeg as the framework's scripts fetch it, the data directory under the user's
   profile (`%APPDATA%`), the disc image path, `tools/build.sh`'s equivalent (a PowerShell script to be written, or the same script
   under Git Bash). Exit: the frontend route to the main menu and a Vineta K race on the Vulkan path, headless and in a
   window; `tools/frame_regress.sh --shell vulkan --backend vulkan` against the Vulkan column (docs/verification.md).
2. **Tools (one task).** Every Python tool runs; the bash tools run under Git Bash or WSL; the PPSSPP driver drives
   the Windows PPSSPP; the scorecard's references retaken; `tools/docs_check.py` passes with docs/setup.md's Windows
   section. Exit: `tools/scorecard.py --quick` with the same grades as docs/scorecard.md's categories.
3. **Fidelity parity in the Vulkan renderer (about four tasks, the real work).** Everything the M8 round put in the
   Metal backend, into the framework's Vulkan renderer as patches (the GE state already carries the fields; the
   renderer draws none of them):
   - texture mapping modes (environment map and texture matrix; docs/metal-backend.md "Texture mapping modes");
   - mip levels (the level in the shader; "Mipmaps");
   - the colour test and the depth clamp (GLSL discard as the alpha test; `VK_EXT_depth_clip_enable` or the
     per-vertex clamp Metal does);
   - the 16-bit targets and dithering: Vulkan has no programmable blending, so either render 5650/5551/4444 targets
     to true 16-bit formats (the hardware quantises; the dither offset needs a pass of its own or a subpass with an
     input attachment) or keep RGBA8 targets and dither in a second subpass. Measure as task 040 did (the billboard
     target against PPSSPP's dump).
   Exit: `tools/gerec/metal_check.sh`'s A/B compares the two complete backends on one recording, on the Mac.
   (Task 060 found the suite cannot judge this bar: its Vulkan column is a windowed 960x544 capture sampled down,
   its Metal column the headless backend's own 480x272 pictures, and the no-3D menu scenes carry the same 0.03 to
   0.05 gap as the race scenes — the capture path, not the renderer. The Windows measure is the re-baselined
   Vulkan column against the PPSSPP references, which tasks 056 to 060 moved from 0.067-0.096 to 0.045-0.056 on
   the race scenes.)
   Exit met 2026-10-09 on the Mac: `tools/gerec/metal_check.sh` PASS — the TEAM SELECTION frames pixel-identical
   between the backends, race frame 6016 at 0.000015 (2 pixels over tol 24 of 130560).
   Since task 068 (patch 0018-vulkan-effects-at-1x) the Windows build's default scale (Auto, the multiple of 480x272
   that covers the window) draws the screens at that scale and the bloom's and the adverts' buffers at 1x, as the
   Metal backend does (D-015), so the glow is the PSP's at any scale.
4. **Packaging (one task).** The Windows zip through the framework's release script, the game-data check, a
   first-run setup that takes the disc image, the pre-warm list shipped, a bundle check equivalent to the macOS one.
   Exit (task 061, 2026-10-09): `tools/bundle_windows.sh --check out/061` passes files, dlls, machine, names,
   content, setup and route (title 0.030 of 0.05) on the staged `Wipeout Pure.exe`, and since task 071 (2026-10-11)
   an eighth check, icon (the executable's icon and version resource); `--zip` makes
   `pure-recomp-<version>-windows-x64.zip` (49 MB) with `SHA256SUMS`. As built, not as first planned: the packer is
   ours (the framework's Windows script packs its desktop app, not a game), the Release build links the static C
   runtime and the windows subsystem, and no pre-warm list ships (it is the Metal backend's; Vulkan keeps a pipeline
   cache in the data directory). docs/release.md, "Windows".

## What to decide before starting

- Which compiler: clang-cl keeps the flags and warnings the Mac build has; MSVC is what the framework's own Windows
  CI uses. Try clang-cl first.
- x64 only, or arm64 Windows too: x64 first (the players); arm64 if a VM on the Mac is wanted later.
- Whether the Mac stays the primary for fidelity work: yes while the Metal backend is the measured one; a renderer
  fix lands in Metal first and becomes a brief for Vulkan, or the other way round, never both at once.
