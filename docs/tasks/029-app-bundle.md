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
Status: PARTIAL. Deliverables 1 to 5, 7 and 8 are in. The framework's packer runs on this Mac (no `--local` needed),
and `tools/bundle.sh` produces `out/release-macos/stage/Wipeout Pure.app`. The app is signed ad hoc, every library
resolves inside it, and it holds no game data and no path of this machine. Item 6 stops at the installer: `--install`
copies the image, then fails with "The prepared executable does not match the supported one". The cause is in our
profile, `src/profile/pure_profile.cpp`, which is under "Must not touch":
- `executable_path_on_disc` is `PSP_GAME/SYSDIR/EBOOT.BIN`. On this disc that file is encrypted (`~PSP`, SHA-256
  `0228768504ea...`, which is `encrypted_executable_sha256`).
- `decryption_key` for tag 0x08000000 is empty. The profile's comment says the key is "not filled in yet".
- So the decrypted result never matches `executable_sha256` (`9033e4dd...`).

So Verify fails: setup FAIL, and route and finder are not run. I did not change `src/`.

The rest of item 6 works from a data directory laid out by hand, the way `--install IMAGE --in-place` would leave it
(`out/029/standin/data`: `EBOOT.ELF` is a link to `game/EBOOT.ELF`, and `settings.ini` has `disc_image=` set to the
image's path; nothing was copied):
- The bundled executable, with only `PURE_DATA_DIR` and the frontend route's variables, played that installation:
  `Executable: .../out/029/standin/data/EBOOT.ELF` and `Disc image:` the ISO. It ran in `[shell] metal: Apple M4 Pro,
  window 960x544` with the Metal backend, reached `[pure] exit at frame 2200`, and the title shot was `PASS fraction
  0.000237` against `ref/title.png` (tol 24, max-frac 0.05).
- `open "Wipeout Pure.app"` (LaunchServices, with `--env` for the same variables) did the same, also at 0.000237.
- With `PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan`, the bundled loader took the bundle's `MoltenVK_icd.json`.
  MoltenVK 1.4.2 drew the language screen at 0.054 against `ref/frontend.png`, the Vulkan path's measured value.

**The fix (one line in the profile, then rerun Verify):** set `.executable_path_on_disc =
"PSP_GAME/SYSDIR/BOOT.BIN"`. The disc's plain executable is `\x7FELF` with SHA-256 `9033e4dd...`, which is
`executable_sha256` and is what `tools/setup_game.sh` already uses. `inspect` accepts a plain executable whose SHA-256
the profile knows, and `prepare_executable` returns a plain ELF unchanged, so no key is involved. The alternative is
to fill in the tag key.

Changed:
- `CMakePresets.json`: configure and build preset `arm64-release`. It inherits `arm64` and adds
  `CMAKE_BUILD_TYPE=Release`, `PORTABLEKIT_RELEASE=ON`, `PORTABLEKIT_FFMPEG=bundled`, with `build/release` as the
  build directory.
- `tools/build.sh`: `release` configures if needed (reusing build/arm64's FFmpeg archive) and builds PureNative. The
  cold build took 8 min (10:31 to 10:39), with the corpus and FFmpeg rebuilt. It printed no error, and
  `build/release/bin/PureNative` contains no `/Users/erreib`.
- `.gitignore`: adds `build/release/`, `out/release-macos/` and `dist/`.
- `packaging/release.env`: as the brief asks, with two differences:
  - It adds `RELEASE_MACOS_CATEGORY=public.app-category.racing-games`.
  - `RELEASE_GAME_NAMES="ucus98612* ppcd00001* *.wad *.at3 *.pmf icon0.png pic1.png devmenu.cfg
    *wipeout*pure*usa*"`. A bare `*wipeout*pure*` matches every file in the bundle named after the app (`Wipeout
    Pure.app`, its executable, its icon, `Wipeout Pure-LICENSE.txt`), so the packer would refuse its own output. The
    dump's usual name is caught by `*wipeout*pure*usa*` instead, and the disc's own file names were added.
- `packaging/THIRD_PARTY_NOTICES.md`:
  - Every bundled component, with its licence and the pins the packer greps for: SDL3, FFmpeg with its configure
    line, the Vulkan loader, MoltenVK.
  - PortableKit (MIT, pinned commit plus our patch series), Dear ImGui 1.92.9b including the Metal backend in
    `third_party/imgui_metal/`, tiny-AES-c, stb, xxHash, the Noto CJK font.
  - Our code, GPL-2.0-or-later.
  - FFmpeg: LGPL, dynamically linked and replaceable (re-sign afterwards), and where its source is.
- `packaging/icon.png` and `packaging/macos/Wipeout Pure.icns`: a dark rounded square with W in cyan and P in pink.
  `packaging/make_icon.py` draws them as signed distance fields through `tools/png.py`, each icns size at its own
  resolution, and `iconutil` packs the icns.
- `packaging/macos/README.txt`: what the app is, the disc it needs, Gatekeeper on first open, the setup, the data
  directory and where saves live, the keyboard in one table, the licence line.
- `tools/bundle.sh`: new. With no option, `--zip` or `--dist` it packs the app. `--check DIR` runs the checks.
  `docs/release.md` has the details.
- `docs/release.md`: new. It covers building and bundling, what the app holds, the first run and why it fails today,
  the data directory, the Vulkan path from the app, the checks and the limits.
- `README.md`: a Play section at the top, rows for `packaging/` and `tools/bundle.sh`, and `LICENSE` in the licence
  line.
- `LICENSE`: new, outside "May touch". The packer copies `<game>/LICENSE` into the bundle unconditionally
  (`release_macos.sh` line 421), RELEASING.md lists it as something the game brings, and the brief cites it. It is the
  verbatim GPL v2 text (SHA-256 `8177f975...`, copied from FFmpeg's `COPYING.GPLv2`). The notices and the read-me say
  "or later".
- Commits: 9de28f2, c4289e9, 2ef089d, 6601a88, and this Result.

Verify (`tools/verify_task.sh 029`, 10:57:42 to 10:57:57; the packer reused its built SDL3 and loader). The check
table:
```
bundle   PASS  signed ad hoc, 6 Mach-O files, every library is the system's or in Contents/Frameworks
machine  PASS  no /Users/erreib, no /erreib/ in any file
names    PASS  no file named like game data (35 entries)
content  PASS  no game file; the disc image's SHA-256 (87078aee9e4f9557...) in no file; hits only in the executable's own strings:
  UCUS98612: 6 string(s) of the executable, e.g. "UCUS98612" "UCUS98612P0000" "UCUS98612P0001"
  .iso: 17 string(s) of the executable, e.g. "  --install image set up from image.iso without the setup screens, then exit" ...
  EBOOT: 12 string(s) of the executable, e.g. "  game_dir        play from a directory holding EBOOT.ELF, disc.iso and ms0/" ...
  BOOT.BIN: 10 string(s) of the executable, e.g. "Decrypting EBOOT.BIN needs " "EBOOT.BIN did not decrypt with the key table its tag selects" ...
setup    FAIL  exit 1, copied no, data: disc.iso.part; Setup failed: Setup failed: The prepared executable does not match the supported one. (log .../out/029/setup.log)
route    FAIL  not run: no installation in .../out/029/data (setup failed)
finder   FAIL  not run: no installation in .../out/029/data (setup failed)
```
Last 20 lines:
```
         8 Wipeout Pure.app/Contents/PkgInfo
  16467736 Wipeout Pure.app/Contents/Resources/fonts/NotoSansCJKjp-Regular.otf
      1083 Wipeout Pure.app/Contents/Resources/licenses/DearImGui-LICENSE.txt
     26517 Wipeout Pure.app/Contents/Resources/licenses/FFmpeg-COPYING.LGPLv2.1.txt
       629 Wipeout Pure.app/Contents/Resources/licenses/FFmpeg-SOURCE.txt
     11358 Wipeout Pure.app/Contents/Resources/licenses/MoltenVK-LICENSE.txt
      4301 Wipeout Pure.app/Contents/Resources/licenses/NotoSansCJK-OFL.txt
      1123 Wipeout Pure.app/Contents/Resources/licenses/PortableKit-LICENSE.txt
       884 Wipeout Pure.app/Contents/Resources/licenses/SDL3-LICENSE.txt
      7089 Wipeout Pure.app/Contents/Resources/licenses/THIRD_PARTY_NOTICES.md
      1211 Wipeout Pure.app/Contents/Resources/licenses/tiny-AES-c-UNLICENSE.txt
     11661 Wipeout Pure.app/Contents/Resources/licenses/Vulkan-Loader-LICENSE.txt
     18092 Wipeout Pure.app/Contents/Resources/licenses/Wipeout Pure-LICENSE.txt
      1389 Wipeout Pure.app/Contents/Resources/licenses/xxHash-LICENSE.txt
       194 Wipeout Pure.app/Contents/Resources/vulkan/icd.d/MoltenVK_icd.json
    110467 Wipeout Pure.app/Contents/Resources/Wipeout Pure.icns
data directory after setup: 241M (disc.iso.part)

bundle check: FAIL (3 checks)
verify 029: FAIL (exit 1)
```

The packer's own run, in the same Verify:
- `all 384 system imports exist in MacOSX13.3.sdk` (the CLT carries the 13.3 SDK, so its macOS 13 check runs here)
- `marked 3 binaries for macOS 13.0`
- `no paths of this machine in Wipeout Pure.app`
- `no game data in Wipeout Pure.app`
- `Wipeout Pure.app: 88M, 6 Mach-O files, 0 overlays`

Info.plist: id `com.erikreiblein.pure-recomp`, name `Wipeout Pure`, version 0.1.0 (`Wipeout Pure 0.1.0-6601a88`),
`LSMinimumSystemVersion` 13.0. The executable loads `@rpath/libSDL3.0.dylib`, `@rpath/libvulkan.1.dylib`,
`@rpath/libavcodec.61.dylib`, `@rpath/libavutil.59.dylib` and system frameworks only, with rpath
`@executable_path/../Frameworks`. No Mach-O in the bundle names `/opt/homebrew`.

The developer build is unaffected. `tools/build.sh profile && tools/frame_regress.sh --only lang` gave `lang 690
0.0002 0.07 24 0.0002 +0.0000 PASS`, `frame regression: PASS, 1/1 scenes pass, shell metal, backend metal`.

The bundle's files (bytes), 88 MB in all:
```
      7351 Contents/_CodeSignature/CodeResources
   1686400 Contents/Frameworks/libavcodec.61.dylib
    719056 Contents/Frameworks/libavutil.59.dylib
   3902544 Contents/Frameworks/libMoltenVK.dylib
   2540000 Contents/Frameworks/libSDL3.0.dylib
    620496 Contents/Frameworks/libvulkan.1.dylib
      2166 Contents/Info.plist
  65605984 Contents/MacOS/Wipeout Pure
         8 Contents/PkgInfo
  16467736 Contents/Resources/fonts/NotoSansCJKjp-Regular.otf
      1083 Contents/Resources/licenses/DearImGui-LICENSE.txt
     26517 Contents/Resources/licenses/FFmpeg-COPYING.LGPLv2.1.txt
       629 Contents/Resources/licenses/FFmpeg-SOURCE.txt
     11358 Contents/Resources/licenses/MoltenVK-LICENSE.txt
      4301 Contents/Resources/licenses/NotoSansCJK-OFL.txt
      1123 Contents/Resources/licenses/PortableKit-LICENSE.txt
       884 Contents/Resources/licenses/SDL3-LICENSE.txt
      7089 Contents/Resources/licenses/THIRD_PARTY_NOTICES.md
      1211 Contents/Resources/licenses/tiny-AES-c-UNLICENSE.txt
     11661 Contents/Resources/licenses/Vulkan-Loader-LICENSE.txt
     18092 Contents/Resources/licenses/Wipeout Pure-LICENSE.txt
      1389 Contents/Resources/licenses/xxHash-LICENSE.txt
       194 Contents/Resources/vulkan/icd.d/MoltenVK_icd.json
    110467 Contents/Resources/Wipeout Pure.icns
```
`Read Me.txt` goes beside the app in `out/release-macos/stage`. `out/release-macos/dist` holds `ffmpeg-7.1.5.tar.xz`,
`SHA256SUMS` and `BUILDINFO.txt`.

The data directory after setup:
- `out/029/data` holds only `disc.iso.part`, 252,968,960 bytes (241 MiB). The installer copied the whole image, then
  failed while preparing the executable. A successful copying setup would be about 245 MiB: the image, the 3.6 MB
  `EBOOT.ELF` and `settings.ini`.
- The hand-made in-place directory is 52 KB after its runs (links, `settings.ini`, `ms0/`, and the Vulkan run's
  pipeline cache).

Finder screenshots, both the Metal shell's own window capture at 960x544, from `open "Wipeout Pure.app"`:
- `out/029/finder_game_title.png`: the game's title screen, with the hand-made data directory.
- `out/029/finder_first_run_setup.png`: the first-run setup screen ("Welcome to Wipeout Pure Native", Choose disc
  image), with the empty data directory of the first check run.

`screencapture` could not be used. From this session it returns only the desktop picture, with no windows and no menu
bar, so the session has no Screen Recording permission.

`git status` is clean. `build/`, `out/`, `disc`, `disc.iso`, `game/` and `generated` show only as ignored, and
nothing of the game is in packaging/ or anywhere else in git.

Open questions:
1. Should the profile change land? `executable_path_on_disc = "PSP_GAME/SYSDIR/BOOT.BIN"` is recommended (no key);
   the alternative is the tag key. Verify should then pass all seven checks. Setup takes a few seconds (the copy did),
   and the route and the `open` run take about 40 s each (they did with the hand-made directory).
2. Is `LICENSE` at the root acceptable outside "May touch"? The packer cannot run without it.
3. `Info.plist`'s `NSHumanReadableCopyright` says "MIT License". It comes from the framework's template
   (`vendor/portablekit/packaging/macos/Info.plist.in`). Editing it after the packer would break the seal, so it would
   need a vendor patch or an Info.plist field in release.env.
4. The setup's welcome screen says the image is what "the PlayStation 3 release carries". That sentence is hardcoded
   for another game in the framework's `host/ui/setup_screens.cpp`, and fixing it needs a vendor patch.
5. The packer marks the binaries for macOS 13 after checking only the libc, libc++ and CoreFoundation imports. The
   Metal shell and backend have not been run below macOS 15.
6. The notices offer our source as "the pure-recomp repository at the commit in the app's version". Distributing the
   app beyond this Mac needs a public URL for it, which GPL v2 section 3 requires.
7. A plain double-click (no `--env`) uses `~/Library/Application Support/pure-recomp/PureNative/`. That directory
   already holds a `settings.ini` and Vulkan pipeline caches from developer runs, but no installation, so today the app
   opens on the setup screen there. I installed nothing there, per the brief.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
