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
`PORTABLEKIT_FFMPEG=bundled` (FFmpeg 7.1.5, LGPL only, built once per build directory into `build/release/bin/lib`).
The corpus compiles again in Release: 8 minutes on the M4 Pro the first time (2026-10-06), seconds after a change in
`src/` only. The developer build in `build/arm64` is not touched.

`tools/bundle.sh` then copies `config/metal_pipelines.txt` into `build/release/bin/app_resources` (task 042: the
packer ships the contents of that folder in `Contents/Resources`, because `packaging/release.env` sets
`RELEASE_RESOURCES="app_resources=."`; the packer refuses to run without the folder, so run it through
`tools/bundle.sh`) and runs `release_macos.sh --game . --no-dmg build/release` with the version
`0.1.0-<commit>[-dirty]` (CMakeLists.txt's project version and `git describe`). A newer pipeline list does not make the
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
| `Resources/licenses/` | `Wipeout Pure-LICENSE.txt` (GPL v2; ours is GPL-2.0-or-later, D-006), PortableKit's, SDL3's, FFmpeg's, the loader's, MoltenVK's, Dear ImGui's, tiny-AES-c's, xxHash's, the font's, and `THIRD_PARTY_NOTICES.md` |
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
| `settings.ini` | `disc_image=` and every setting of the Esc menu (docs/controls.md) |
| `ms0/` | the memory stick: saves in `ms0/PSP/SAVEDATA/` |
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

## Limits

- The app is signed ad hoc and not notarized: on another Mac Gatekeeper asks the player to allow it once (Privacy &
  Security, "Open Anyway", or `xattr -dr com.apple.quarantine`), as `Read Me.txt` says.
- The packer marks the binaries for macOS 13 after checking only the C, C++ and CoreFoundation symbols they import;
  the Metal shell and backend have only been run on macOS 15 (this Mac).
- `Info.plist`'s copyright line comes from the framework's template and says "MIT License"; the licences in the bundle
  and `THIRD_PARTY_NOTICES.md` give the actual terms (GPL-2.0-or-later for the combination).
- The setup's welcome screen says the disc image "the PlayStation 3 release carries it", a sentence the framework
  wrote for another game (`host/ui/setup_screens.cpp`); a vendor patch would make it a profile field.
