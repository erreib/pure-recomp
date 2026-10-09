# 061: Windows packaging: the zip, the checks

Milestone: W4 (docs/windows.md step 4) | Branch: task/061-windows-packaging | Status: OPEN

## Goal
The Windows release as a player gets it: unpack a zip, double-click the program, choose the disc image the first
time, play. The zip holds the program, the DLLs it loads, the licences and a read-me, and nothing of the game.
This is docs/windows.md's step 4, the last step of the Windows bring-up. The framework has no Windows packer for a
game (`scripts/package_desktop_windows.ps1` packs the desktop app and its toolchain, not a port), so the packer is
ours: `tools/bundle_windows.sh`, shaped after `tools/bundle.sh` and after the framework's own checks (no game
data, no path of this machine, the packed program runs).

## Read first
- docs/release.md (the macOS app: the release build, what the packer checks, the first-run setup, `--install`)
- tools/bundle.sh (the shape to mirror: pack-if-stale, then the named checks; which are macOS-only)
- packaging/release.env (RELEASE_NAME, RELEASE_SLUG, RELEASE_GAME_NAMES — the same values drive the zip)
- vendor/portablekit/docs/RELEASING.md and scripts/package_desktop_windows.ps1 (read for the checks it does and
  the dist shape: zip, SHA256SUMS, BUILDINFO.txt; do not run it, it packs the wrong thing)
- CMakePresets.json (win-x64; arm64-release is the pattern for the release preset)
- tools/build.sh (the `release` mode is macOS-shaped today)
- docs/windows.md step 4, docs/setup.md's Windows section (the toolchain the release build uses)

## Deliverable
1. A `win-x64-release` configure preset: inherits win-x64, `CMAKE_BUILD_TYPE=Release`,
   `PORTABLEKIT_RELEASE=ON`, its own build directory `build/release-win`. `tools/build.sh release` uses it on
   MINGW* (the macOS branch is untouched). **The corpus compiles again in Release: expect 15 to 25 minutes once,
   ccache after. This long build is allowed for this task and does not count as the blocked full rebuild; run it
   through `tools/build.sh release` and go on when it ends.**
2. `tools/bundle_windows.sh [--zip] | --check DIR` (Git Bash, like the other tools):
   - Pack: stage `out/release-windows/stage/Wipeout Pure/` from `build/release-win/bin` — the executable, the
     DLLs beside it (SDL3, avcodec, avutil, swresample), `FFmpeg-LICENSE.txt`/`FFmpeg-SOURCE.txt` into
     `licenses/`, our `LICENSE` as `LICENSE.txt`, PortableKit's licence and `packaging/THIRD_PARTY_NOTICES.md`
     in `licenses/`, and a new `packaging/windows/README.txt` (what it is, that the player's own disc image is
     required, how the first run asks for it, where the data lands). Rebuild first when the executable is missing
     or older than the sources, as bundle.sh does. Version `0.1.0-<commit>[-dirty]` from CMakeLists.txt and
     `git describe`, recorded in a `BUILDINFO.txt`.
   - `--zip`: `out/release-windows/dist/pure-recomp-<version>-windows-x64.zip` (made with `tar.exe -a`) plus
     `SHA256SUMS`.
   - `--check DIR` (packs first when the stage is missing), each printed PASS or FAIL, exit 0 only when all pass:
     - **files** — the stage holds exactly the expected names (listed in `DIR/bundle_files.txt` with sizes)
     - **dlls** — every DLL the executable imports is a system DLL or beside it in the folder (llvm-objdump -p);
       same for each bundled DLL
     - **machine** — no path of this machine (`H:/errei`, `C:/Users/<user>`, the user name) in any file
     - **names** — no file named like game data (bundle.sh's globs plus RELEASE_GAME_NAMES)
     - **content** — the byte checks bundle.sh does: no disc image (CD001 at 32769), no MIPS ELF/~PSP, no PBP, no
       PARAM.SFO; UCUS98612, .iso, .wad, EBOOT, BOOT.BIN and the disc SHA-256 prefix in no file but the
       executable's own text, never the SHA-256 itself
     - **setup** — the staged executable with `PURE_DATA_DIR=DIR/data` and `--install <the disc image disc.iso
       resolves to>`, no other PURE_ variable: exit 0, `DIR/data` holds EBOOT.ELF, settings.ini and the copied
       disc.iso
     - **route** — the staged executable with only PURE_DATA_DIR and the route variables (frontend pad script,
       PURE_SCREENSHOT_DIR, PURE_SCREENSHOT_EVERY=0, PURE_EXIT_AT_FRAME=2200), default shell and backend
       (Vulkan, windowed): reaches frame 2200 and `DIR/shots/title.png` is within tol 24, max-frac 0.05 of
       ref/title.png (the suite's limit; the re-baselined column has title at 0.030)
     - The macOS-only checks (codesign bundle, finder/LaunchServices, Metal prewarm) do not exist here; the
       script's header says so. There is no Windows pre-warm list: config/metal_pipelines.txt is Metal's.
3. The release executable must not open a console window when a player starts it from Explorer. Preferred:
   link the release preset alone with `/SUBSYSTEM:WINDOWS` (keep `main` via `/ENTRY:mainCRTStartup`); the
   developer build keeps the console subsystem so every tool's log reading is untouched. Verify the route check
   still captures and that `--install` from a console still prints (if stdout from a console is lost under the
   windows subsystem, say so in the Result; do not redesign logging).
4. packaging/THIRD_PARTY_NOTICES.md gains the Windows components as shipped: SDL3 3.4.18 (prebuilt DLL), FFmpeg
   7.1.5 BtbN LGPL shared build (named exactly as cmake/FFmpeg.cmake pins it, with FFmpeg-SOURCE.txt as the
   source pointer in licenses/).
5. Docs: a Windows section in docs/release.md (build, pack, check, what differs from the Mac and why);
   docs/windows.md step 4 gets its exit recorded; docs/status.md Running updated. `python tools/docs_check.py`
   passes.
6. Optional, only if the core is done and turns remain: an .ico from packaging/icon.png (packaging/make_icon.py
   may help) compiled in with llvm-rc for the release build. If skipped, note it as a follow-up.

## Acceptance criteria
- [ ] `tools/build.sh release` produces `build/release-win/bin/PureNative.exe` (Release, PORTABLEKIT_RELEASE=ON)
- [ ] `tools/bundle_windows.sh --zip` produces the stage, the zip and SHA256SUMS; the stage's executable is named
      `Wipeout Pure.exe` (RELEASE_NAME) — if the rename breaks anything, keep PureNative.exe and record why
- [ ] `tools/bundle_windows.sh --check out/061` passes every check, including setup and route against the real
      disc image
- [ ] No console window from Explorer for the staged executable (double-click it once; say what you saw)
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/bundle_windows.sh --check out/061`

## May touch
- tools/ (bundle_windows.sh new, build.sh, env.sh if needed), CMakePresets.json, CMakeLists.txt,
  packaging/ (windows/ new, THIRD_PARTY_NOTICES.md), docs/, out/

## Must not touch
- vendor/ (this task should need no vendor patch; BLOCKED if it does), include/psprecomp/, src/, config/,
  patches/, tools/purelib/ beyond reading

## Estimated turns
40 — commit after each proven stage (the preset + release build; the pack; each check as it first passes; the
docs), so a turn-limit stall never loses work. On resume, finish from the artifacts that exist; do not redo the
release build or passing checks.

## Escalate when
The release build fails in generated/ code or needs a flag change under include/psprecomp/; the subsystem switch
cannot be done with link flags alone (would need src/ changes); `--install` or the route behaves differently in
Release than the dev build in a way that needs src/ or vendor/ changes; a single build exceeds 30 minutes.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
