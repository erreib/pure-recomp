# Reference captures

PPSSPP reference material for frame comparison. Everything here except this file is git-ignored.

Made 2026-10-05 (task 006) with `tools/ppsspp/ppsspp_ctl.py` (docs/ppsspp.md): PPSSPP SDL 1.20.4 (brew cask
`ppsspp-emulator`), software renderer, rendering resolution 1x (480x272), frameskip off, game language English,
CROSS confirms, RTC base 2026-01-01 00:00 UTC, default compatibility settings. Memstick: `PSP/SAVEDATA/PPCD00001DLS001`
present, no profile save. The PNG is the displayed framebuffer read from VRAM (480x272 RGB); the `.ppdmp` is the GE
recording of the same frame (PPSSPP GE dump format, replayable in PPSSPP's GE debugger).

## Files and frames

Frames are vblank counts since boot. "Requested" is the `--shot`/`--gedump` frame; "captured" is the vblank position
of the flip that handed over the captured frame (`frame` in `ppsspp_run.json`). Three runs (two plain, one with HLE
logging) gave byte-identical PNGs, and the two plain runs byte-identical `.ppdmp` files.

| Scene | Files | Requested | Captured | Route state |
|---|---|---|---|---|
| Language Selection | frontend.{png,ppdmp} | 600 | 602 | ENGLISH highlighted; before CROSS at 700 |
| Title | title.{png,ppdmp} | 2650 | 2653 | "PRESS START BUTTON" (cursor shown); after START at 2400, before START at 2700 |
| Profile | profile.{png,ppdmp} | 2880 | 2882 | PROFILE, LOAD highlighted; before DOWN at 2900 |
| Main Menu | main_menu.{png,ppdmp} | 5640 | 5643 | MAIN MENU, SINGLE PLAYER highlighted, help text fully typed; after WARNING CROSS at 5250 |
| Vineta K start | vineta_k_start.{png,ppdmp} | 7154 | 7155.3 | first frame with the HUD (CURRENT 0.00.0, POS 8/8, LAP 1/3) fully faded in, ship on the grid; before READY |
| Boot log | boot-hle.log | | | boot to frame 5659 (Main Menu) on routes/frontend.txt with `--log` (HLE categories in docs/ppsspp.md) |
| Run report | ppsspp_run.json | | | the driver's JSON report of the capture run (flip times, framebuffer addresses, dump sizes) |

The Vineta K countdown has no digits: READY slides in from 7213, a blue ring fades in behind it from about 7220, and
the ring keeps spinning until GO! (green ring), when the timer starts. GO! was seen between 7241 and 7261 in a run
whose race presses were 150 frames earlier, which shifted every race event by exactly 150 frames, so it is at about
7391-7411 on these routes (not captured). With no "3" to pin, the reference is the brief's fallback: the first frame
with the HUD at CURRENT 0.00.0 and the grid. The HUD fades in over 7151-7155; 7155 is the first fully opaque frame.

## Regenerate

```
cd ~/dev/pure-recomp     # or a worktree with disc.iso linked
P=/opt/homebrew/bin/python3; R=tools/ppsspp/routes
$P tools/ppsspp/ppsspp_ctl.py run --pad-file $R/frontend.txt --pad-file $R/vineta_k_start.txt --until 7160 \
  --shot 600:ref/frontend.png --gedump 600:ref/frontend.ppdmp \
  --shot 2650:ref/title.png --gedump 2650:ref/title.ppdmp \
  --shot 2880:ref/profile.png --gedump 2880:ref/profile.ppdmp \
  --shot 5640:ref/main_menu.png --gedump 5640:ref/main_menu.ppdmp \
  --shot 7154:ref/vineta_k_start.png --gedump 7154:ref/vineta_k_start.ppdmp --report ref/ppsspp_run.json
$P tools/ppsspp/ppsspp_ctl.py run --pad-file $R/frontend.txt --until 5650 --log ref/boot-hle.log
```
About 2 minutes per run (real-time emulation). Check `ls ~/.config/ppsspp/PSP/SAVEDATA` first: only
`PPCD00001DLS001` may be there.

## SHA-256 of the 2026-10-05 captures

| File | SHA-256 |
|---|---|
| frontend.png | f1d2374d33a5b60d660e59a44953610b6687c1f21285140268308296b516fb2a |
| title.png | 725ae1c2a3317deb5755f77addbd2899e69f28cba9c92c9a88ca84df12bba878 |
| profile.png | f5c9bb2dec38af9bc45e53da838443c85b0ae2fe9c791223e9880ea133796e1f |
| main_menu.png | f1545c70b7b786dd9f4f176831d6b75a5cd56789ff9b781747d3a8d382c5c132 |
| vineta_k_start.png | 20f36ae28d57503e98027ea607314a68949ecc5d255ee04ce6d015ab849cb259 |
| frontend.ppdmp | ca978c97039380360e4b6f6c9d81f7da4d71a391e0beb9f9ef4f784672dab790 |
| title.ppdmp | 0e30e7ee835543382024ed7cc0742ec44a5c14832e9c11700f7355dd588ceba3 |
| profile.ppdmp | 5d28af107b969963dec0a8e53c9a6ed03d102996c6b30b7c92aec015ea6817f6 |
| main_menu.ppdmp | 39ff394b3f134f1ad1abd6c1952248a5213a3b39ee635b2bb13c62246d1f86ea |
| vineta_k_start.ppdmp | 1981e89408cfb554546d3d3196b6ab6a303f02719eaaac90313b8df775541e30 |

Not captured yet: `zone` (SINGLE PLAYER, DOWN x3 to ZONE, CROSS) and save states (`--savestate` needs the
Accessibility permission, docs/ppsspp.md).
