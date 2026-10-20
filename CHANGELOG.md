# Changelog

## 0.2.0 (2026-10-20)

The races at your display's refresh rate, and the sound that keeps up with it.

- **Display rate**, a new row at the end of the Video tab's game section, on by default: when the display runs
  above 60 Hz, Single Race and Tournament draw at its rate (120 frames a second on a 120 Hz display, 100 on a 100 Hz
  one), and Time Trial, Free Play and Zone too with the 30 fps modes row at 60 fps. The game's speed is unchanged;
  the race runs half a percent under the display's rate so that a missed refresh is won back without a hitch in the
  sound. The menus keep the PSP's pace. Original keeps the PSP's 60 everywhere, as before.
- **Performance** (the frame rate and frame times in the top-left corner, F3) now works on the Mac too, so you can
  see 120 against 60.
- **Sound at high refresh rates.** A sound channel that falls a few milliseconds behind keeps its content and
  regains its lead over the next seconds instead of skipping; the early-race skips heard on a 100 Hz display are
  gone. `PURE_AUDIO_SNAP=1` restores the previous behaviour for comparison.
- **Windows:** the Esc menu's folder buttons (the data folder, the download packs) open Explorer; before, Windows
  refused the address.
- The README is written for players; the developer reference moved to docs/.
- Not in this release, as in 0.1.0: ad hoc multiplayer and the in-game browser (shown as unavailable); download
  packs from the EU and JP editions; notarized or signed builds.

## 0.1.0 (2026-10-13, the first public release)

The whole single-player game on Apple Silicon Macs (Metal) and 64-bit Windows (Vulkan), from the player's own US
Greatest Hits disc image (UCUS-98612 v2.00).

- Every mode, class, league and circuit; profiles and saves in the PSP's own format, with import, export and
  backups; the movies, the music and the sound, including the SAS reverb.
- The US download packs installed from the Esc menu and loaded by the game itself (Gamma, Delta and Classic packs,
  the four bonus ships).
- Enhancements, each a menu row with the original behaviour one choice away: the picture at the display's
  resolution; the view at the window's shape (21:9 and wider, Aspect ratio: Fill); Time Trial, Free Play and Zone at
  60 fps; the full-screen flashes smoothed; texture detail at the internal resolution with anisotropic sampling;
  the menu art upscaled (off by default).
- Controls: keyboard (two layouts), PlayStation and Xbox gamepads as themselves, rebinding in the menu.
- Fidelity against the PSP: frame checks against PPSSPP captures on both renderers; the fourteen behaviour
  differences found by the audit fixed or explained (docs/fidelity.md).
- Not in this release: ad hoc multiplayer and the in-game browser (shown as unavailable); download packs from the
  EU and JP editions; notarized or signed builds.
