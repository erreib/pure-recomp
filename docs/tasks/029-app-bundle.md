# 029: The macOS app bundle: packaging files, a release build, the installer path, tools/bundle.sh

Milestone: M7 | Branch: task/029-app-bundle | Status: OPEN (after task 028)

## Goal
A `Wipeout Pure.app` that Erik can launch from Finder on this Mac: on first run it asks for the disc image (the
framework's installer), then plays with the Metal shell and backend by default (D-008). The framework packs releases
(`vendor/portablekit/scripts/release_macos.sh`, docs/RELEASING.md there); this task brings what the game must bring
(`packaging/`), makes a Release build, runs the packer, and wraps the whole thing in `tools/bundle.sh`. Nothing of the
game goes into the artifact: the packer checks that, and so does this brief.

## Read first
- CLAUDE.md (hard rules: never commit game bytes; the artifact must hold none either), docs/decisions.md D-006 (our
  licence, GPL-2.0-or-later) and D-008, docs/status.md (M7 row), README.md
- vendor/portablekit/docs/RELEASING.md (all), scripts/release_macos.sh (its header and what it checks: notices,
  game data, machine paths; the deployment target and SDK it needs), packaging/sources.sh (the pins and
  `MACOS_DEPLOYMENT_TARGET`), apps/portablekit/packaging/release.env (the example), docs/BUILDING.md (the
  `PORTABLEKIT_RELEASE` and `PORTABLEKIT_FFMPEG` options), cmake/FFmpeg.cmake
- vendor/portablekit/host/main.cpp (`locate_game`: game_dir, the installed game in the user data directory, the
  checkout's game/, else the installer; `--install [image.iso [--in-place]]`), host/install/installer.cpp (what the
  setup does with the image: copies it, or references it in place), host/install/user_data.cpp (`<prefix>_DATA_DIR`)
- CMakePresets.json (the arm64 preset: `/usr/bin/clang`, ccache, arm64), tools/build.sh, tools/env.sh
- src/host/pure_main.cpp (task 028's defaults), third_party/imgui_metal/ (ships with its licence)

## Deliverable
1. `packaging/release.env`: `RELEASE_NAME="Wipeout Pure"` (the app's name), `RELEASE_SLUG=pure-recomp`,
   `RELEASE_TARGET=PureNative`, `RELEASE_APP_ID=com.erikreiblein.pure-recomp`, a summary, `RELEASE_OVERLAYS=0`,
   `RELEASE_PROFILE_DIR=.`, `RELEASE_GAME_NAMES="ucus98612* *wipeout*pure* *.wad"` (names that must not appear in
   an artifact), no extra executables.
2. `packaging/THIRD_PARTY_NOTICES.md`: every component the bundle carries with its licence and the pinned versions
   the packer greps for (SDL3, FFmpeg and its configure flags, MoltenVK, the Vulkan loader, from
   `packaging/sources.sh` and `cmake/FFmpeg.cmake`), plus PortableKit (MIT), Dear ImGui (MIT, including the Metal
   backend files under `third_party/imgui_metal/`), and our own code (GPL-2.0-or-later, `LICENSE`). FFmpeg is
   LGPL and dynamically linked: say so, and where its source is.
3. `packaging/macos/Wipeout Pure.icns` made from a plain generated picture (`packaging/icon.png`, 256x256: a rounded
   square with the letters WP in two colours, drawn with Python's zlib PNG writer in tools/png.py or `sips`; no game
   art, no logo of the game's owners), and `packaging/macos/README.txt` (what the app is, that it needs the player's
   own disc image, the first-run setup, where saves live, the keyboard controls in one table, the licence line).
4. A Release configure preset `arm64-release` in CMakePresets.json (the arm64 preset plus `CMAKE_BUILD_TYPE=Release`,
   `PORTABLEKIT_RELEASE=ON`, `PORTABLEKIT_FFMPEG=bundled`, build directory `build/release`), and `tools/build.sh
   release` that configures and builds it (the corpus compiles again in Release: run it in the background, it may take
   10 to 20 minutes cold; the shared ccache helps the second time).
5. `tools/bundle.sh`: builds `release` when `build/release/bin/PureNative` is missing or older than the sources, then
   runs `vendor/portablekit/scripts/release_macos.sh --game . --no-dmg build/release` (add `--zip` or the dmg behind
   `--dist`), and prints where the app is (`out/release-macos/stage/Wipeout Pure.app`). If the packer cannot run on
   this machine (it wants the SDK of its deployment target, macOS 13, and this machine has the Command Line Tools
   with a newer SDK; or it fetches sources this machine cannot), say exactly what fails in Result and make
   `tools/bundle.sh --local` instead: the same bundle layout assembled by hand (Info.plist with the app id, name,
   version and `LSMinimumSystemVersion`; the executable; the FFmpeg dylibs from `build/release/lib`; SDL3, the Vulkan
   loader and MoltenVK's ICD copied from Homebrew into `Contents/Frameworks` with `install_name_tool` so every
   library resolves inside the bundle; the licences; the icon), signed ad hoc. The local bundle is for this machine
   only and the doc says so.
6. The installer path, checked: with `PURE_DATA_DIR=out/029/data` (empty) the bundled executable run with
   `--install "<Erik's ISO path>"` sets the game up from the image (copied or in place: say which and how big the data
   directory is), and then runs without `PURE_GAME_DIR` and without `--install`, through the Metal shell and backend
   by default, the frontend route (`PURE_INPUT_SCRIPT` from `config/pad_scripts/frontend.txt`, `PURE_SCREENSHOT_DIR`)
   to frame 2200 with the `title` shot matching `ref/title.png` as the suite does (tol 24, 0.05). Launched from
   Finder (`open "<app>"`) it shows its window and the game (a screenshot of the window in out/029/, taken with
   `screencapture` or the shell's capture, named in Result).
7. No game data in the artifact: besides the packer's own check, `grep -rl` the bundle for `UCUS98612`, `.iso`,
   `.wad`, `EBOOT`, `BOOT.BIN` and the ISO's SHA-256 prefix, and list the bundle's files with sizes in Result.
   Nothing under out/, build/, packaging/ that comes from the game is committed (git status clean of it).
8. docs/setup.md (or a new docs/release.md): how to build and bundle, what the bundle contains, the first-run setup,
   where the data directory is, how to run the Vulkan path from the bundle (`PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan`,
   which needs MoltenVK in the bundle). README.md: a "Play" section at the top pointing to it. docs/status.md: not
   yours.

## Acceptance criteria
- [ ] `tools/bundle.sh` produces `Wipeout Pure.app` (packer or `--local`), every Mach-O in it resolves its libraries
      inside the bundle (`otool -L` shows no `/opt/homebrew` path), and it is signed ad hoc.
- [ ] The bundle holds no game data (item 7) and no path of this machine (the packer's check, or `grep -rl
      /Users/erreib` empty).
- [ ] Item 6: setup from the ISO, then the frontend route to frame 2200 from the installed data directory with the
      title shot within the suite's limit; the Finder launch shows the game.
- [ ] `tools/build.sh profile` and `tools/frame_regress.sh` are unaffected (the developer build and its suite still
      pass 5/5 at the Metal measured values after task 028).

## Verify
`tools/bundle.sh && tools/bundle.sh --check out/029`

(`--check DIR` does items 6 and 7 and exits 0 when they hold: it runs the bundled executable with
`PURE_DATA_DIR=DIR/data`, `--install "$(readlink disc.iso)"`, then the frontend route with shots into `DIR/shots`,
compares `DIR/shots/title.png` with `ref/title.png` through `tools/imgdiff.py --max-frac 0.05 --tol 24`, and greps
the bundle.)

## May touch
- packaging/ (new), tools/bundle.sh (new), tools/build.sh (the `release` case), CMakePresets.json (the new preset),
  docs/setup.md or docs/release.md, README.md, .gitignore (`out/release-macos/`, `build/release/`, `dist/`)

## Must not touch
- vendor/, patches/, src/, config/, ref/, tools/run_boot.py, tools/frame_regress.sh, CMakeLists.txt

## Estimated turns
60

## Escalate when
The Release build fails to compile or link (report the error; do not change src/ or vendor/), the packer needs a
change under vendor/ (report; `--local` is the fallback, not a patch), or the installed game fails to start from the
data directory for a reason in the framework's installer (report the log). Never copy the ISO or any extracted file
into the repo or the bundle; the installer's copy goes under `PURE_DATA_DIR` only.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
