# The macOS app (task 029)

`Wipeout Pure.app` is the game as a player gets it: double-click it, choose the disc image the first time, play. It
holds the program, the libraries it loads, the licences and an icon, and nothing of the game: the first-run setup makes
what the game needs from the player's own image, in the player's data directory. The framework packs it
(`vendor/portablekit/scripts/release_macos.sh`, `vendor/portablekit/docs/RELEASING.md`); this repository brings what is
its own (`packaging/`, `LICENSE`) and wraps the steps in `tools/bundle.sh`.

## Build and bundle

```
tools/build.sh release            # build/release/bin/PureNative: the arm64-release preset (10 to 20 min cold)
tools/bundle.sh                   # the release build if it is missing or older than the sources, then the packer
tools/bundle.sh --zip             # also the zip archive (out/release-macos/dist)
tools/bundle.sh --dist            # the disk image and the zip archive
tools/bundle.sh --check out/029   # the checks below, with a scratch data directory in out/029/data
```

The release build is its own build directory, `build/release`, configured by the `arm64-release` preset in
`CMakePresets.json`: the developer preset (`/usr/bin/clang`, ccache, arm64) with `CMAKE_BUILD_TYPE=Release`,
`PORTABLEKIT_RELEASE=ON` (the executable names no path of the checkout and has no fallback to its `game/`) and
`PORTABLEKIT_FFMPEG=bundled` (FFmpeg 7.1.5, LGPL only, built once per build directory into `build/release/bin/lib`)
and `CMAKE_OSX_DEPLOYMENT_TARGET=13.0`, the packer's `MACOS_DEPLOYMENT_TARGET`: the executable and FFmpeg are compiled
for the oldest macOS the app claims, so an `@available(macOS 15.0, *)` is a check at run time and the compiler warns
about a newer API used without one. Without it (through 0.2.0) clang compiled for this Mac's macOS 15, decided every
such check at compile time and dropped its fallback, and the packer only marked the binaries down to 13 afterwards:
both releases aborted at launch on macOS 13 and 14 (a tester's macOS 14.6, 2026-10-22: `-[MTLCompileOptions
setMathMode:]`, macOS 15 only, in the Metal backend's `initialize`). `tools/bundle.sh` refuses to pack a build whose
executable or FFmpeg is compiled for a newer macOS than the packer's, and `tools/build.sh release` configures the build
directory afresh when `CMakePresets.json` is newer than its cache. The corpus compiles again in Release: 8 minutes on
the M4 Pro the first time (2026-10-06), seconds after a change in `src/` only. The developer build in `build/arm64` is
not touched: it compiles for this Mac's macOS, so its `@available` checks are decided at compile time.

`tools/bundle.sh` then copies `config/metal_pipelines.txt` into `build/release/bin/app_resources` (task 042: the
packer ships the contents of that folder in `Contents/Resources`, because `packaging/release.env` sets
`RELEASE_RESOURCES="app_resources=."`; the packer refuses to run without the folder, so run it through
`tools/bundle.sh`) and runs `release_macos.sh --game . --no-dmg build/release` with the version
`0.1.0-<commit>[-dirty]` (CMakeLists.txt's project version and the abbreviated commit), or the project version alone,
`0.1.0`, when HEAD is exactly at the tag `v0.1.0` with no uncommitted change (task 087, [Publishing](#publishing)). A newer pipeline list does not make the
release build stale: it is not compiled in. The packer:

1. checks that `packaging/THIRD_PARTY_NOTICES.md` names every pinned component (SDL3, FFmpeg and its configure line,
   MoltenVK, the Vulkan loader), that the executable is a release build and that `bin/lib` holds the bundled FFmpeg;
2. fetches the pinned sources into `out/release-macos/sources`, each checked by SHA-256 (it needs the network the
   first time), and builds SDL3 3.4.16 and the Vulkan loader 1.4.357 for macOS 13 into `out/release-macos/deps`
   (about a minute, once; they are rebuilt only when a pin changes);
3. assembles `out/release-macos/stage/Wipeout Pure.app` (with the `RELEASE_RESOURCES` folder's files in
   `Contents/Resources`), points every library at `@rpath` (the bundle's
   `Contents/Frameworks`), strips local symbols, checks the system symbols the binaries import against the macOS 13
   SDK (`/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk` on this Mac) and marks them for macOS 13;
4. signs every library and the app ad hoc (no Developer ID, not notarized) and checks the app: the signature, no
   library outside the bundle, no path of this machine, no game data by name or by content.

With `--zip` or `--dist` the archives land in `out/release-macos/dist` with the FFmpeg source archive, which the LGPL
asks to be offered beside the binaries, `SHA256SUMS` and `BUILDINFO.txt`. Without them, `dist/` holds only those.

## What the app holds

| Path in `Wipeout Pure.app/Contents` | What |
|---|---|
| `MacOS/Wipeout Pure` | the program (PureNative, Release): our profile, the Metal backend and shell, PortableKit, Dear ImGui, the recompiled code |
| `Frameworks/libavcodec.61.dylib`, `libavutil.59.dylib` | FFmpeg 7.1.5 (music, movies), LGPL, dynamically linked |
| `Frameworks/libSDL3.0.dylib` | SDL3 3.4.16 (window, input, audio) |
| `Frameworks/libvulkan.1.dylib` | the Vulkan loader; the program links it, the Metal path loads no Vulkan driver |
| `Frameworks/libMoltenVK.dylib`, `Resources/vulkan/icd.d/MoltenVK_icd.json` | MoltenVK 1.4.2 and its manifest, for the Vulkan path only |
| `Resources/Wipeout Pure.icns` | the icon (`packaging/make_icon.py`: a rounded square with W and P, no game art) |
| `Resources/fonts/NotoSansCJKjp-Regular.otf` | the framework's fallback font for Japanese text in the menu |
| `Resources/metal_pipelines.txt` | (task 042) the Metal backend's pre-warm list, a copy of `config/metal_pipelines.txt` made at packing: the render pipelines and depth-stencil states made at start, the pipelines asynchronously, so no draw compiles one on first use, not even on a machine's first start with a cold shader cache (docs/metal-backend.md, "The pre-warm list"). The backend looks for it here first, and the app's signature seals it. `PURE_METAL_PIPELINES=FILE` or `0` still overrides it |
| `Resources/models/` | (task 102) the models backend's figures, only in an app built with `PURE_MODELS` ON: the release preset has it OFF (D-027), so a release has no models folder, no Crowds and people or Skies row, and runs on the Metal backend alone. With it ON: `models/models.ini` and every `.pmdl` under `models/` with its folder, copied at packing (not `models/README.md`), which the backend looks for there first |
| `Resources/licenses/` | `Wipeout Pure-LICENSE.txt` (GPL v2; ours is GPL-2.0-or-later, D-006), PortableKit's, SDL3's, FFmpeg's, the loader's, MoltenVK's, Dear ImGui's, tiny-AES-c's, xxHash's, Zstandard's, the font's, and `THIRD_PARTY_NOTICES.md` |
| `Info.plist`, `PkgInfo`, `_CodeSignature/` | id `com.erikreiblein.pure-recomp`, name, version, `LSMinimumSystemVersion` 13.0, category racing games; the ad hoc seal |

The app is 88 MB: the executable 66 MB, the font 16 MB, the five libraries 9.5 MB. `out/release-macos/stage/Read
Me.txt` (from `packaging/macos/README.txt`) goes beside the app in the archives: what
the app is, the disc it needs, the first start, where the data is, the keyboard, the licence. The file list with
sizes of a packed app is in task 029's Result and in `<DIR>/bundle_files.txt` after `tools/bundle.sh --check DIR`.

## First run: the setup

The program finds the game in this order (`locate_game` in the framework's `host/main.cpp`): a game directory on the
command line or in `PURE_GAME_DIR` (a developer's switch, never set for the app), the installation in the data
directory, and in a developer build the checkout's `game/` (a release build has none). With no installation it runs
the setup in its window (the Metal shell): choose the disc image, the setup checks its disc id (UCUS-98612) and the
executable's SHA-256, then copies the image into the data directory (the default) or uses it where it is, prepares
`EBOOT.ELF` from it, and the game starts. From a terminal:

```
"Wipeout Pure.app/Contents/MacOS/Wipeout Pure" --install                      # the setup screens again
"Wipeout Pure.app/Contents/MacOS/Wipeout Pure" --install IMAGE [--in-place]   # no screens: set up and exit
```

The profile names the plain executable the disc carries beside the encrypted `EBOOT.BIN`
(`executable_path_on_disc = "PSP_GAME/SYSDIR/BOOT.BIN"` in `src/profile/pure_profile.cpp`), whose SHA-256 it knows, so
the installer takes it as it is, with no key (16718e6, task 029's review). What the setup did before that:
[the record](history/release.md#the-setup-before-16718e6-task-029-2026-10-06).

## The data directory

`~/Library/Application Support/pure-recomp/PureNative/` (SDL's preference folder for the profile's organisation and
application names), or `PURE_DATA_DIR` when it is set:

| File | What |
|---|---|
| `EBOOT.ELF` | the executable prepared from the image (3.6 MB) |
| `disc.iso` | the copy of the image (241 MiB); absent when it is used in place, `settings.ini` then names where it is |
| `settings.ini` | `disc_image=` and every setting of the Esc menu (docs/controls.md). `video.internal_scale` (the Video tab's Resolution) starts at `auto` for this game since task 067 (the framework's default is 2): the app draws at the display's resolution out of the box, 1920x1088 in the default window on a 2x display. A file that already holds a value keeps it, since the setting is the player's: a data directory an earlier build wrote holds `video.internal_scale=2` (every save writes every key) and stays at 2 until Resolution is set to Auto in the menu. `game.smooth_flashes` (the Video tab's Flashes, task 070, E6) is 1, Smooth, unless the player picks Original (0), `game.sixty_fps` (the Video tab's Frame rate, task 072, E4) is 1, 60 fps, unless the player picks Original (0), `game.sprite_upscale` (the Video tab's Text and sprites, task 073, E7) is 0, Original, since 2026-10-12 (D-018 as amended; builds through 0.1.0-56673a2 had 1, Upscaled) unless the player picks Upscaled (1), and `game.texture_detail` (the Video tab's Texture detail, task 075, E5) is 1, Enhanced, unless the player picks Original (0): a file without a key, an earlier build's included, reads as the default and gets the key at its next save |
| `ms0/` | the memory stick: saves in `ms0/PSP/SAVEDATA/`, and the download packs the player installs beside them (`ms0/PSP/SAVEDATA/UCUS98612D<PACK>`; [Download packs](#download-packs-task-077)) |
| `pipeline_cache.bin`, `pipeline_keys.bin` | the Vulkan path's pipeline cache, when it has run |

After a copying setup the directory holds about 245 MiB: the image, 252,968,960 bytes (241 MiB), the 3.6 MB executable
and `settings.ini`. With `--in-place` it holds only the executable and `settings.ini`. The developer build reads the
same directory first, so an installation there is also what `build/arm64/bin/PureNative` plays unless `PURE_GAME_DIR`
names another game directory, as `tools/run_boot.py` does.

`tools/bundle.sh --check` plays an installation the same way (below); how task 029 first played a hand-made one, on
both paths: [the record](history/release.md#a-hand-made-installation-task-029-2026-10-06).

## The Vulkan path from the app

The app runs the Metal shell and backend (D-008: our `main()` sets `PURE_SHELL=metal` and `PURE_GE_BACKEND=metal`
when they are unset). The Vulkan path needs both variables, and runs on the bundled loader and MoltenVK (the loader
finds the manifest in `Contents/Resources/vulkan/icd.d`):

```
PURE_SHELL=vulkan PURE_GE_BACKEND=vulkan "Wipeout Pure.app/Contents/MacOS/Wipeout Pure"
open --env PURE_SHELL=vulkan --env PURE_GE_BACKEND=vulkan "Wipeout Pure.app"
```

## The check

`tools/bundle.sh --check DIR` (task 029's Verify line with `DIR` = `out/029`; task 042's with `out/042`) prints PASS
or FAIL per check:

| Check | Passes when |
|---|---|
| bundle | `codesign --verify --deep --strict` holds, the signature is ad hoc, every Mach-O loads only `/usr/lib`, `/System/Library` and `@rpath` libraries that are in `Contents/Frameworks` (`otool -L` shows no `/opt/homebrew`), and its rpaths are relative |
| machine | no file names the home directory or `/<user>/` |
| names | no file is named like game data: the packer's names (`eboot*`, `*.iso`, `*.prx`, `*.bin`, `param.sfo`, `ms0`, ...) and `RELEASE_GAME_NAMES` |
| content | no file is a disc image, a PSP executable, a PBP or a PARAM.SFO by its header; `UCUS98612`, `.iso`, `.wad`, `EBOOT`, `BOOT.BIN` are in no file but the executable, and there only in its own text strings, which are listed (the disc id the setup checks an image against, the names of the files it writes and reads, its messages); the SHA-256 prefix of the disc image is in no file |
| setup | the bundled executable with `PURE_DATA_DIR=DIR/data` (empty) and `--install "$(readlink disc.iso)"`, with no other `PURE_` variable, exits 0 with `EBOOT.ELF`, `settings.ini` and the copied `disc.iso` there |
| route | the bundled executable again, with only `PURE_DATA_DIR` and the route's variables: the log names `DIR/data/EBOOT.ELF` and `DIR/data/disc.iso`, the Metal shell, the frontend route (`config/pad_scripts/frontend.txt`) reaches frame 2200, and `DIR/shots/title.png` is within tol 24, max-frac 0.05 of `ref/title.png` |
| finder | `open "Wipeout Pure.app"` (LaunchServices, as Finder does; `--env` gives it the same data directory and route): the Metal window opens and its title shot, `DIR/finder_shots/title.png`, is within the same limit |
| prewarm | (task 042) `Contents/Resources/metal_pipelines.txt` is `config/metal_pipelines.txt` (`cmp`), and the route and finder runs each print `[metal] pre-warm: R render pipelines (made asynchronously) and D depth-stencil states from` that copy, with R and D the copy's own counts. Each run's exit line, `(W of them waited for the pre-warm, X not in the list)`, is reported, not checked: it measures how much of the route the list covers, not the bundle |

It exits 0 when all pass. route, finder and prewarm play the installation, so when setup fails they are reported
FAIL without running (with no game the app shows its setup screens and waits). It writes only under `DIR`;
`DIR/data` holds the copy of the image, so `DIR` must stay under the ignored `out/`. Each run's log is started
afresh; `open` appends to its `--stdout` file, so before task 042 a second check into the same `DIR` read the first
one's `finder.log` too.

The runs are silent and use no data directory but `DIR/data` (task 034's follow-up, task 042), as the other tools run
on their scratch directories. Every run names `PURE_DATA_DIR=DIR/data`, which the packed app honours (the route check
reads `Executable:` and `Disc image:` from there), and after the setup the check appends `audio.mute=1` to
`DIR/data/settings.ini`: the in-game menu's Mute, which the app reads from its data directory at start (the audio
sink sets the device's gain to 0). The setting has no environment variable, so the data directory is the one way to
reach the app through `open` as well. The check does not use `PURE_NO_AUDIO`, which would leave the audio device
closed; with Mute the app opens it as a player's app does. The setup run opens no audio device.

## The texture pack (task 074)

The Metal backend upscales the menus' and the HUD's bitmap art at decode (E7, docs/metal-backend.md "Sprite upscale");
the Vulkan renderer, the Windows release's and the Vulkan path's from the app, draws the same art from a texture pack in
PPSSPP's format instead. The pack holds the game's art, so it is in neither the app nor the zip: the player makes it
from their own disc, on a Mac, since the scaler is the Metal backend's.

- **Making it** (macOS, a checkout of this repository with the game set up by `tools/setup_game.sh`):
  `tools/sprite_pack.sh` (about 8 minutes, headless; docs/metal-backend.md "The texture pack") writes
  `out/sprite_pack/pack`, `textures.ini` and 48 PNGs, 3.5 MB; `tools/sprite_pack.sh --check` also checks it in the
  Vulkan window. The app reads the same switch the tool uses, `PURE_SPRITE_DUMP=DIR` with Text and sprites at
  Upscaled (`DIR/pack` collects the art of every screen played), but that was not tried with the app.
- **Installing it**: the folder goes into the data directory as `textures/UCUS98612`
  (`~/Library/Application Support/pure-recomp/PureNative/textures/UCUS98612/`, on Windows
  `%APPDATA%\pure-recomp\PureNative\textures\UCUS98612\`), or in the game under either shell (the Metal shell since
  task 100): Esc, Video, Import texture pack…, and the folder chosen; the screen finds the pack in it, checks it and copies it there, keeping a pack
  it replaces in `textures/.backup/`. Open the textures folder (the same tab) shows where packs go.
- **Using it**: the Video tab's Texture pack row (`video.texture_pack`, on by default) turns it on and off and notes
  what is loaded (`48 textures, ...`). The Text and sprites row does nothing under the Vulkan renderer (its help says
  so); the Texture pack row is the switch there. Since task 100 the Metal backend draws packs too (its own loader:
  docs/metal-backend.md "The pack loader"), and the Metal shell offers the Texture pack row and the import as the
  Vulkan shell does; a pack's image supersedes the upscale of the same texture.
- **Other packs** (task 099, D-024): the loader reads PPSSPP's ZIM images as well as PNG (raw, zlib or zstd, the
  last through Zstandard's decoder, which the build downloads and compiles in: `cmake/Zstd.cmake`), so a pack made
  for PPSSPP installs the same way. NR74W's HD texture pack (<https://github.com/0xf0xx0/WipEout-Pure-HD-Texture-Pack>,
  1331 ZIM images for 4172 keys, every edition) is the one checked (`tools/sprite_pack.sh --pack DIR`). It is
  derived art, imported by the player: never in the app, the zip, the Windows folder or this repository. The Vulkan
  renderer and, since task 100, the Metal backend draw it (`tools/sprite_pack.sh --pack DIR --shell metal`).

## Download packs (task 077)

The game's download packs (docs/dlc.md: the twelve US packs, 62 MB) are the game's data, like the disc image: neither
the app, the zip, the Windows folder nor this repository carries them, and the bundle checks' name and content
rules would find a `PARAM.SFO` or a `.wad` in an archive. A player who has them installs them on the data directory's
memory stick, beside the saves, where the game finds them at its next start:

- in the game (since task 078): Esc, System, and in the Download packs section "Install download packs…". The file
  browser opens at the home folder: open a pack's folder, or go to the folder holding the packs (a PSP stick's root or
  its `PSP/SAVEDATA` will do) and pick "Import from this folder"; the next screen names each pack it found ("Gamma
  Pack 1 (UCUS98612DGAMMAPACK1)"); "Import these saves" copies them, and "Restart now" starts the game again with
  them. The section counts the packs on the stick ("12 of 12 installed") and lists each, Installed or Not installed.
  All twelve US packs import (docs/dlc.md, "In the menu (task 078)");
- with `tools/dlc_install.sh PACKS` from a checkout (the app's data directory by default, `--data-dir DIR` for
  another; it checks each folder's name, PI.WAD and PARAM.SFO first, and skips a pack already there unless
  `--replace`);
- or by hand: the folders copied into `~/Library/Application Support/pure-recomp/PureNative/ms0/PSP/SAVEDATA/` on
  macOS, `%APPDATA%\pure-recomp\PureNative\ms0\PSP\SAVEDATA\` on Windows (or under `PURE_DATA_DIR`), one
  `UCUS98612D<PACK>` folder each.

Export save… and Back up saves… leave the packs out: they are the game's data, not the player's saves.

With the packs, LEAGUE SELECTION lists CLASSIC 2, DELTA and GAMMA under ALPHA and TEAM SELECTION adds ICARAS; the boot
to MAIN MENU takes 0.2 to 0.4 s longer headless (the game opens every pack at start-up). `tools/dlc_check.sh --packs
PACKS` checks a set on a scratch stick (docs/developing.md).

## Limits

- The app is signed ad hoc and not notarized: on another Mac Gatekeeper asks the player to allow it once (Privacy &
  Security, "Open Anyway", or `xattr -dr com.apple.quarantine`), as `Read Me.txt` says.
- The packer marks the binaries it did not build for macOS 13 after checking only the C, C++ and CoreFoundation symbols
  they import, so an Objective-C message newer than macOS 13 is caught only by the compiler's availability warnings in
  the release build (compiled for 13 since 2026-10-22). The Metal shell and backend have only been run on macOS 15
  (this Mac): a launch on macOS 13 or 14 is owed (a tester, or a virtual machine of that macOS on this Mac).
- `Info.plist`'s copyright line comes from the framework's template and says "MIT License"; the licences in the bundle
  and `THIRD_PARTY_NOTICES.md` give the actual terms (GPL-2.0-or-later for the combination).
- The setup's welcome screen says the disc image "the PlayStation 3 release carries it", a sentence the framework
  wrote for another game (`host/ui/setup_screens.cpp`); a vendor patch would make it a profile field.

## Windows

The Windows release (task 061, docs/windows.md step 4) is a zip holding a folder, `Wipeout Pure`, that a player
unpacks anywhere and starts with a double click; the first start runs the same setup as the app (choose the disc image,
the check of its disc id and executable, the copy into the data directory). The framework's Windows packer
(`vendor/portablekit/scripts/package_desktop_windows.ps1`) packs its desktop app and toolchain, not a game, so the
packer is ours, `tools/bundle_windows.sh`, run from the Bash of Git for Windows, shaped after `tools/bundle.sh` and
that script's checks.

```
tools/build.sh release                     # build/release-win/bin/PureNative.exe: the win-x64-release preset
tools/bundle_windows.sh                    # the release build if missing or stale, then the folder in out/release-windows/stage
tools/bundle_windows.sh --zip              # also out/release-windows/dist: the zip, SHA256SUMS, BUILDINFO.txt
tools/bundle_windows.sh --check out/061    # the checks below, with a scratch data directory in out/061/data
```

The `win-x64-release` preset inherits `win-x64` (clang-cl, lld-link, ccache) with `CMAKE_BUILD_TYPE=Release`,
`PORTABLEKIT_RELEASE=ON` (no path of the checkout, no fallback to its `game/`), `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`
(the static C and C++ runtime: a player's Windows need not have the Visual C++ redistributable, which the developer
build's `VCRUNTIME140.dll` and `MSVCP140.dll` imports need) and its own directory, `build/release-win`. CMakeLists.txt
links that build alone with the windows subsystem (`WIN32_EXECUTABLE`, entry `mainCRTStartup`, so `main` stays the
entry): started from Explorer it opens no console window. The developer build keeps the console subsystem every tool
reads. Both Windows builds compile `packaging/windows/pure.rc` (task 071) with llvm-rc (`CMAKE_RC_COMPILER`) into the
executable: the icon, `packaging/windows/pure.ico` (drawn by `packaging/make_icon.py` at 16, 24, 32, 48, 64, 128 and
256, each size at its own resolution like the .icns, PNG entries), so Explorer, a shortcut and the unpacked zip show
it; and a VERSIONINFO (FileVersion and ProductVersion the project version with a fourth field 0,
ProductName and FileDescription `Wipeout Pure`, LegalCopyright naming GPL-2.0-or-later; no commit, which is in
`BUILDINFO.txt`), which Explorer's Properties sheet shows. The running window's (and its taskbar button's) icon is the SDL
shell's business at run time, not this resource's; it was not looked at in task 071. The corpus compiled again in Release in 10.5 minutes cold on the 6-thread machine (2026-10-09). FFmpeg is
BtbN's prebuilt LGPL shared build that the framework's `cmake/FFmpeg.cmake` pins; `tools/build.sh release` copies the
developer build's downloaded zip into the release directory first.

| Path in the folder | What |
|---|---|
| `Wipeout Pure.exe` | the program (PureNative, Release, 80 MB): our profile, PortableKit with its Vulkan renderer and shell, Dear ImGui, the recompiled code; the icon and version resource of `packaging/windows/pure.rc` |
| `SDL3.dll` | SDL3 3.4.18, libsdl-org's prebuilt DLL (the developer build's `SDL3_ROOT`) |
| `avcodec-61.dll`, `avutil-59.dll`, `swresample-5.dll` | FFmpeg 7.1.5, BtbN's LGPL shared build, dynamically linked |
| `LICENSE.txt`, `README.txt` | ours (GPL-2.0-or-later) and `packaging/windows/README.txt` |
| `BUILDINFO.txt` | the version (`0.1.0-<commit>[-dirty]`, or `0.1.0` at the tag `v0.1.0`: [Publishing](#publishing)), the full commit, PortableKit's pin and patches, the toolchain, the shipped DLLs |
| `licenses/` | FFmpeg's licence and source note (the build's), PortableKit's, SDL3's, Dear ImGui's, tiny-AES-c's, xxHash's and Zstandard's licences, and `THIRD_PARTY_NOTICES.md` |
| `models/` | (task 102) `models.ini` and the `.pmdl` files of `models/`, the models backend's figures, which it looks for beside the executable |

The folder is 146 MB, the zip 49 MB. `vulkan-1.dll` is not shipped: the graphics driver installs it in System32.
The data directory is `%APPDATA%\pure-recomp\PureNative\` (SDL's preference folder), or `PURE_DATA_DIR`, with the
files of [The data directory](#the-data-directory).

`tools/bundle_windows.sh --check DIR` prints PASS or FAIL per check and exits 0 when all pass:

| Check | Passes when |
|---|---|
| files | the folder holds exactly the names above (with their sizes in `DIR/bundle_files.txt`) |
| dlls | every DLL the program and each bundled DLL imports (`llvm-objdump -p`) is in the folder, an API set (`api-ms-win-*`, `ext-ms-*`) or in System32 and not a C/C++ runtime redistributable (`vcruntime*`, `msvcp*`, ...) |
| machine | no file holds `H:/errei`, `H:\errei`, `C:/Users/<user>` (either slash), the user name or `dev-stuff`, in any case; `README.txt` and the notices are read without the source address (`https://github.com/erreib/pure-recomp`, task 087), whose GitHub account is the user's name |
| names | no file is named like game data (bundle.sh's names and `RELEASE_GAME_NAMES`) |
| content | bundle.sh's byte checks; `UCUS98612`, `.iso`, `.wad`, `EBOOT`, `BOOT.BIN` only in the executable's own strings, in the two texts this repository writes for the player (`README.txt` and `THIRD_PARTY_NOTICES.md`, which name the disc image and the data directory's files), or in a bundled DLL only inside longer words (BtbN's `avcodec-61.dll` holds libvmaf's `RESIDUEBOOTSTRAP_LIBSVMNUSVR`); each such hit is listed; the disc image's SHA-256 prefix in no file |
| icon | `llvm-readobj --coff-resources` lists ICON (the seven images of `pure.ico`), GROUP_ICON and VERSIONINFO in the executable; the version's ProductName is `RELEASE_NAME` and its ProductVersion the project version with a fourth field 0 (read from the resource's UTF-16 strings); the subsystem (`llvm-readobj --file-headers`) is still the windows one (task 071) |
| setup | the staged program with `PURE_DATA_DIR=DIR/data` and `--install` of the image `disc.iso` is (a hard link on Windows), no other `PURE_` variable: exit 0, `EBOOT.ELF`, `settings.ini` and the copied `disc.iso` there |
| route | the staged program with only `PURE_DATA_DIR` and the route's variables, the default shell and backend (Vulkan, windowed): the log names `DIR/data`'s game and the Vulkan renderer, the frontend route reaches frame 2200 (exit status 4: the runtime stopped by `PURE_EXIT_AT_FRAME`), and `DIR/shots/title.png` is within tol 24, max-frac 0.05 of `ref/title.png` (0.030 on 2026-10-09) |

What differs from the Mac, and why:

- No bundle, finder or prewarm check: there is no signature (the zip is not signed; SmartScreen asks once, as
  `README.txt` says), no LaunchServices, and the pre-warm list is the Metal backend's (`config/metal_pipelines.txt`);
  the Vulkan path keeps its pipeline cache in the data directory instead.
- No font: Windows supplies the Japanese fallback (MS Gothic or Meiryo).
- The read-me is inside the folder, so the content check lists its hits instead of finding none.
- Under the windows subsystem the program has no console of its own: redirected output (a file or a pipe, as the
  check's `setup.log` and `route.log`) is written, but an interactive command prompt shows none of `--install`'s
  messages; its exit status still tells. The developer build is unchanged.
- Started from Explorer (2026-10-09): its parent is `explorer.exe`, no `conhost.exe` child, one window titled
  PureNative; it closed on a plain `taskkill /PID` (WM_CLOSE).

## Publishing

How a release goes public (task 087): the repository on GitHub, `https://github.com/erreib/pure-recomp`, and the two
archives as a GitHub release of it. A session never pushes and never tags `main`; the tag, the push and the release
page are Erik's steps.

1. **The version.** Bump `project(PureRecomp VERSION x.y.z)` in CMakeLists.txt (it names the archives, the app's
   version and the Windows version resource) and write the release's section of CHANGELOG.md (the planning session
   writes it); commit both on `main`.
2. **The tag.** `git tag -a v<version> -m "pure-recomp <version>"` on that commit (a lightweight tag works too).
3. **The check.** `tools/release_check.sh --history` at the tag: PASS before the history goes public (below). A
   finding in a past commit is a decision, a history rewrite or a fresh history, not a fix.
4. **The archives**, from the tag with a clean tree on both machines: here `tools/bundle.sh --zip` (then
   `tools/bundle.sh --check out/<dir>`), which leaves `pure-recomp-<version>-macos-arm64.zip`,
   `ffmpeg-7.1.5.tar.xz`, `SHA256SUMS` and `BUILDINFO.txt` in `out/release-macos/dist`; on the rig, the same tag
   checked out, `tools/bundle_windows.sh --zip` (then `--check out/<dir>`), which leaves
   `pure-recomp-<version>-windows-x64.zip`, `SHA256SUMS` and `BUILDINFO.txt` in `out/release-windows/dist`.
5. **The archives checked.** `tools/release_check.sh --archive out/release-macos/dist/pure-recomp-*.zip ZIP` with
   ZIP the rig's zip copied here (its BUILDINFO.txt is inside it; the macOS one is beside the zip), where the tag
   exists: a zip named for a release needs the tag on the commit its BUILDINFO.txt names.
6. **SHA256SUMS.** One file for the page: the two `SHA256SUMS` joined (`cat`), the macOS zip, the FFmpeg source and
   the Windows zip; `shasum -a 256 -c SHA256SUMS` checks them.
7. **The release page** (Erik, by hand): push `main` and the tag, draft a release at `v<version>` titled
   `pure-recomp <version>`, the CHANGELOG section as its body, and as its assets the two zips, `ffmpeg-7.1.5.tar.xz`
   (the LGPL source the notices promise beside the build), the joined `SHA256SUMS` and the macOS `BUILDINFO.txt`
   renamed `BUILDINFO-macos.txt` (the Windows one is in its zip).

**The version from the tag.** `tools/bundle.sh` and `tools/bundle_windows.sh` name the archives after the project
version alone when HEAD is exactly at the tag `v<project version>` (`git tag --points-at HEAD`) and no tracked file
has uncommitted changes; otherwise after `<version>-<commit>[-dirty]` as before (the abbreviated commit, with
`git describe --exclude='*'` so that a tag never enters it). A `v` tag at HEAD that is not `v<project version>` stops
the pack before the build: `release version: FAIL: HEAD is tagged v0.2.0 but CMakeLists.txt's version is 0.1.0`. At
the tag with uncommitted changes the pack goes on, named `<version>-<commit>-dirty`, and says why. BUILDINFO.txt's
`Built from:` line carries the full commit either way: the framework's packer writes `git rev-parse HEAD` there, and
`tools/bundle_windows.sh` too. The packer takes the name through its own `--version`; no vendor change.

**The check.** `tools/release_check.sh [--history] [--archive ZIP ...]` (the script's header lists every rule) reads
the files of HEAD, what a push publishes, and prints each finding as `FILE:LINE: what`, the notes, a table and
`release_check: PASS` or `FAIL` (exit 0 only on PASS); about 1 s:

| Check | Passes when |
|---|---|
| paths | no file under the git-ignored game, vendor, build and scratch paths (`disc/`, `game/`, `generated/`, `vendor/`, `build/`, `out/`, `ref/` but `ref/README.md`, `ghidra_project/` and the rest of `.gitignore`) |
| names | no path part with a game-data extension (`.iso`, `.cso`, `.bin`, `.wad`, `.at3`, `.pmf`, `.prx`, `.elf`, `.ovl`, `.pbp`, `.sfo`, `.ppst`, `.ppdmp`, `.gerec`) or named like the game's files (`RELEASE_GAME_NAMES` and the packer's: `eboot*`, `PARAM.SFO`, `PI.WAD`, `ICON0.PNG`, `DATA.BIN`, `ms0`, `savedata`, ...), in any case; no file is game data by its header |
| size | no file over 1 MiB, 1048576 bytes (the largest is `config/function_map.csv`, 318026 bytes) |
| binaries | every file is text but the three icons: `packaging/icon.png`, the macOS `.icns` in `packaging/macos/` and `packaging/windows/pure.ico` |
| keys | no run of 32 or more hex digits (16 bytes is a download pack's XTEA key, docs/dlc.md) and no 16-byte array literal, unless the allow list of hashes takes it: 64 digits named SHA-256 on its line, the two before it or its Markdown table's header (the references, the pinned sources, the executable's hashes in the profile); 40 digits named a commit, tree or PIN there, or a commit of this repository; a hash column of `config/*.csv`; `vendor/PIN`. A run of one repeated digit is padding |
| tokens | no GitHub (`ghp_` and its kin), GitLab (`glpat-`) or AWS (`AKIA`) token and no PEM block |
| home | no home directory (`/Users/NAME`, `/home/NAME`, `C:\Users\NAME` in either slash) and no path in the rig's user folder outside the record (`docs/tasks/`, `docs/history/`, `docs/research.md`, where a task's machine paths are history) and the machine checks' own patterns (`tools/release_check.sh`, `tools/bundle_windows.sh`, this file), which are notes |
| history | (`--history`) the paths and names rules on every path ever added (`git log --all --no-renames --diff-filter=A -m`), the keys and tokens rules on every file version ever committed (`git rev-list --objects --all`), no binary but the three and no game header; the stash, never pushed, is left out |
| archive | (`--archive ZIP`) no entry named like game data or game data by its header; BUILDINFO.txt (in the zip, else beside it) is for the zip's version, names a commit of this repository, not `-dirty`, and a release version has its tag on that commit; in the macOS zip no game data path in the app's `Contents/Resources` and no game string (`UCUS98612`, `PSP_GAME`, `EBOOT`, `BOOT.BIN`, `.iso`, `.wad`) or home path in its text files |

2026-10-13 (task 087) on `batch/m2` plus the task: every rule PASS but home, with six findings, all the rig's user
folder in files the planning session owns: the `win-x64` preset's `SDL3_ROOT` (CMakePresets.json), the Windows
`CCACHE_DIR` default (tools/env.sh), PPSSPP's path (tools/ppsspp/ppsspp_ctl.py) and three lines of docs/setup.md. The
history PASSES (at e91d443): 823 commits, 393 paths ever added and 1656 file versions (46.0 MB) in 3.6 s, with no
game path, name or header, no binary but the three, and no key or token; its 1443 SHA-256 and 15 git object ids are
the allow list's (the references' table, the notices' pins, the profile's hashes, task 052's tree ids). `--archive`
PASSES on the fresh `pure-recomp-0.1.0-e91d443-macos-arm64.zip` (87 entries, 14 text files of the app's Resources
read), and at a scratch tag `v0.1.0` (deleted after) the pack was `pure-recomp-0.1.0-macos-arm64.zip`, Info.plist
0.1.0, BUILDINFO.txt naming e91d443, its `--archive` PASS while the tag stood and FAIL ("the tag v0.1.0 is not on
commit e91d443") once it was gone.

**What the GPL asks of a distributed build.** The program is a combination under GPL-2.0-or-later (D-006); whoever
distributes it owes the source of that version (section 3). The release page does it: the tag's source archives are
on the same page, and the repository says where everything else comes from (PortableKit at the pin in
`tools/vendor_setup.sh` with `patches/` applied; SDL3, FFmpeg, the Vulkan loader and MoltenVK by URL and SHA-256 in
the notices; FFmpeg's own source archive as an asset, as its LGPL asks). The texts in the archives say where the
source lives, as plain text: `packaging/macos/README.txt` (the zip's `Read Me.txt`, beside the app) and
`packaging/windows/README.txt` name `https://github.com/erreib/pure-recomp` and the version or commit to take;
`packaging/THIRD_PARTY_NOTICES.md` names the repository, the tag or commit, and the read-me for its address. The
address is not in the notices because they ship inside the app, and the GitHub account in it is this Mac's user
name: the framework's packer refuses an app holding `/<user>/` (its check for paths of this machine, a fixed
`grep -e "/$(id -un)/"` in `release_macos.sh`), and so does `tools/bundle.sh --check`'s machine row. On Windows the
read-me is inside the folder, so `tools/bundle_windows.sh --check`'s machine row reads the two texts without the
address. A `@SOURCE_URL@` marker is not possible without a vendor change either: the macOS packer substitutes
`@MINIMUM_SYSTEM_VERSION@` in `README.txt` alone (one fixed `sed -e` in `release_macos.sh`) and copies the notices
as they are, and `tools/bundle_windows.sh` copies both as they are. If the repository moves, the two read-mes and
`SOURCE_URL` in `tools/bundle_windows.sh` change with it.

## History

[docs/history/release.md](history/release.md): the setup before 16718e6 and the hand-made
installation task 029 played.
