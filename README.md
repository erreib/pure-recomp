# Wipeout Pure: Recompiled

pure-recomp is a native port of **Wipeout Pure** (PSP, Studio Liverpool, 2005) for Apple Silicon Macs and Windows,
made by static recompilation: the game's code is translated ahead of time into a program that runs directly on
your machine, with its graphics drawn by Metal on macOS and Vulkan on Windows. It is not an emulator, and the
download contains none of the game: you play it from your own disc image.

**You need a disc image dumped from your own copy of Wipeout Pure, US Greatest Hits edition (UCUS-98612, version
2.00).** The setup checks it and refuses other editions and regions.

## System requirements

| | macOS | Windows |
|---|---|---|
| Machine | Apple Silicon (M1 or newer) | 64-bit Windows 10 or 11 |
| Graphics | any Apple Silicon GPU (Metal) | a graphics card with a Vulkan driver (any current NVIDIA, AMD or Intel driver) |
| System | macOS 13 or newer (tested on 15) | |
| Input | a keyboard, or a PlayStation or Xbox gamepad | the same |
| Disk | about 300 MB for the program and your copy of the disc | the same |

## How to install

1. Download the archive for your platform from the [releases page](https://github.com/erreib/pure-recomp/releases).
2. **macOS**: unpack and drag `Wipeout Pure` anywhere. The app is signed ad hoc and not notarized, so the first
   launch is refused once; open System Settings, Privacy & Security, and click "Open Anyway" next to the message
   about Wipeout Pure. **Windows**: unpack the zip anywhere and keep the folder together. The build is not signed,
   so SmartScreen asks once: "More info", then "Run anyway".
3. Start it. The setup asks for your disc image, checks it, and copies it into the program's data folder (or uses
   it where it is). The game starts; later starts go straight to it.

Your saves and settings live in the data folder: `~/Library/Application Support/pure-recomp/PureNative/` on macOS,
`%APPDATA%\pure-recomp\PureNative\` on Windows, with the saves under `ms0/PSP/SAVEDATA/` in the PSP's own format.
The read-me inside each archive has the details.

## Features

- **The complete single-player game**: every mode, class, league and circuit, the movies, the music and the sound.
- **Your PSP saves work.** Saves are in the PSP's format; the menu imports a save from a memory stick or PPSSPP,
  exports one back, and keeps backups.
- **The download packs.** If you have the original US DLC packs (the `UCUS98612D...` folders from a PSP memory
  stick), the menu installs them and the game loads them as it always did: the Gamma, Delta and Classic packs with
  their tracks and ships, and the four bonus ships.
- **Enhancements, each one choice away from the original behaviour**, in the menu that Esc opens:
  - the picture at your display's resolution instead of 480x272;
  - the view at your window's shape, ultrawide included (Aspect ratio: Fill);
  - Time Trial, Free Play and Zone at 60 fps instead of the PSP's 30;
  - the full-screen flashes smoothed;
  - sharper textures at distance (mipmap detail at the internal resolution);
  - the menu art upscaled (off by default).
- **Controls**: keyboard with two layouts, PlayStation and Xbox gamepads as themselves, and every key rebindable.
- **Faithful by default.** The reference is the PSP's own output: the port's checks compare its frames with PPSSPP
  captures, and the behaviour differences found along the way are fixed or explained in
  [docs/fidelity.md](docs/fidelity.md).

## Controls

| Wipeout Pure | PSP | Keyboard |
|---|---|---|
| Steer | stick | A and D (W and S: up, down) |
| Accelerate, confirm | Cross | Space |
| Airbrake left, right | L, R | Q, Left Shift |
| Use pickup | Square | E |
| Absorb pickup | Circle | F, or the right mouse button |
| Reverse camera, back | Triangle | the left mouse button |
| Start, skip a movie | Start | Enter or Tab |
| Menu cursor | D-pad | the arrow keys |
| The port's own menu | | Esc (L3+R3 on a gamepad) |

A gamepad is positional: Cross is the bottom button on a PlayStation pad, A on an Xbox pad. Rebinding and a
classic keyboard-only layout are in the Esc menu's Controls tab ([docs/controls.md](docs/controls.md)).

## The Esc menu

Press **Esc** at any time (L3+R3 on a gamepad) for the port's own menu over the game; Esc again, or Resume, goes
back. The game pauses while it is open, unless you tell the System tab otherwise. Everything here is saved to
`settings.ini` in the data folder, and each tab has a row that restores its defaults.

- **Video.** Resolution (Auto follows the window; or a multiple of the PSP's 480x272), Display and Window size,
  Aspect ratio (Original keeps the PSP's shape with bars, Stretch fills the window, Fill draws the view at the
  window's shape: the ultrawide option), Scaling filter, Vsync, Game speed and Fast loading, and on Windows the
  Frame rate row (frame interpolation) and texture filtering and packs. At the end of the tab, the game's own
  enhancements: **30 fps modes** (60 fps, or the PSP's 30), **Flashes** (smoothed, or the original), **Text and
  sprites** (original, or upscaled), **Texture detail** (enhanced, or the original).
- **Audio.** Volume, mute, the output device.
- **Controls.** The connected gamepad, the confirm button (Cross as the bottom button, or the right one), dead
  zones, every binding for the keyboard, mouse and pad, and the classic keyboard-only layout.
- **System.** Resume, pausing, open the data folder, set up the game data again (another disc image), quit; your
  profiles with import, export and backups; the download packs, how many are installed and a button to install
  more; and what build you are running.

## Known issues

- The macOS app is not notarized and the Windows build is not signed (the one-time step above).
- On Windows the first race on each track can stutter for a moment while the graphics driver compiles its shaders;
  they are cached, so it does not come back.
- Under the Fill aspect ratio the movies are stretched to the window, and the HUD keeps to the width of a 16:9
  picture rather than the window's edges.
- No ad hoc multiplayer and no in-game browser: the services are gone, and the game shows them as unavailable.
- The European and Japanese discs are refused, and their download packs are not converted for the US game.

## FAQ

**What is static recompilation?** The game's executable is machine code for the PSP's MIPS processor. A recompiler
reads that code once, ahead of time, and writes an equivalent program in C++, which is compiled for your
machine. The result runs the game's own logic natively, without an emulator interpreting instructions while you
play. The PSP's operating system calls are answered by a rewritten layer, and its graphics chip by a native
renderer.

**Is this a decompilation?** No. Nobody rewrote the game by hand, and there is no readable source of it here. The
translated code is generated on your own machine from your disc by the build, and a release build carries that
translation and none of the game's data.

**Why only the US v2.00 disc?** The port is built against that executable, address by address. The other editions
have different executables, and supporting one would be a port of its own.

**Is it faster than PPSSPP?** Lighter: there is no just-in-time compiler, no emulated operating system and no
emulator around the game, so a race costs a few milliseconds of CPU per frame and a fraction of the memory. The
graphics cost depends on the resolution you pick, as in an emulator.

**Where do my PPSSPP saves go?** Esc, System, Import: pick the `UCUS98612...` folder from PPSSPP's memory stick
(`memstick/PSP/SAVEDATA/`). Export writes one back in the same format.

**Can I run the Vulkan renderer on the Mac?** Yes, through MoltenVK, which the app bundles; see
[docs/release.md](docs/release.md). Metal is the default and the one to use.

## Building

Builds are made on a machine with the disc image, since the game's code is generated from it: macOS with the
Homebrew packages named in [docs/developing.md](docs/developing.md), or Windows as described in
[docs/windows.md](docs/windows.md). There is no automated build for that reason. `tools/bundle.sh` and
`tools/bundle_windows.sh` make the release archives ([docs/release.md](docs/release.md)).

## How it was made

The framework is [TeamGDB/PortableKit](https://github.com/TeamGDB/PortableKit) (MIT), the
[PSPRecomp](https://github.com/jessicanataliagta/PSPRecomp) lineage's framework split out of
[TeamGDB/Yakumo](https://github.com/TeamGDB/Yakumo), vendored at a pinned commit and changed only through the
patches in `patches/`. The game's profile, the Metal backend and the test tooling are this repository's.

The port was planned, mapped and reviewed by a Claude session, with briefed tasks carried out by Claude subagents;
every task is a file under `docs/tasks/` with its verification command, its Result and its Review, the decisions are
in [docs/decisions.md](docs/decisions.md), and [docs/status.md](docs/status.md) says what works and what proves it.
Reverse engineering used Ghidra with [ghidra-allegrex](https://github.com/kotcrab/ghidra-allegrex), PPSSPP as the
behavioural reference (no PPSSPP source is copied here) and [pspautotests](https://github.com/hrydgard/pspautotests)
for the hardware's rules.

## Credits

- [PortableKit](https://github.com/TeamGDB/PortableKit), [Yakumo](https://github.com/TeamGDB/Yakumo) and
  [PSPRecomp](https://github.com/jessicanataliagta/PSPRecomp), the framework and its lineage.
- [PPSSPP](https://www.ppsspp.org/), the reference for what the PSP does, and
  [pspautotests](https://github.com/hrydgard/pspautotests).
- [ghidra-allegrex](https://github.com/kotcrab/ghidra-allegrex) by kotcrab.
- [Thomas Perl](https://thp.io/2021/pure-dlc) and [vscode-wipeout](https://github.com/vscode-wipeout) for the
  WAD, VEXX and DLC format research.
- [SDL3](https://libsdl.org/), [FFmpeg](https://ffmpeg.org/), [MoltenVK](https://github.com/KhronosGroup/MoltenVK)
  and [Dear ImGui](https://github.com/ocornut/imgui), shipped with the builds; the full list is in
  `packaging/THIRD_PARTY_NOTICES.md`.

## Licence

This repository's code is GPL-2.0-or-later (`LICENSE`). The vendored framework is MIT; FFmpeg is LGPL and linked as
separate libraries. Wipeout Pure is a trademark of Sony Interactive Entertainment; this project is not affiliated
with or endorsed by Sony and distributes none of its material.
