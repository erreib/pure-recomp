# Reference captures

PPSSPP reference material for frame comparison. Everything here except this file is git-ignored.

Settings used: PPSSPP (brew cask `ppsspp-emulator`), rendering resolution 1x (480x272), Vulkan backend, default compatibility settings (`SoftwareRasterDepth` is on for Wipeout Pure by compat.ini), no texture filtering changes, frameskip off.

| Scene | Files | How to reach it |
|---|---|---|
| frontend | frontend.{png,ppst,ppdmp} | boot, skip intro, first stable main-menu frame |
| vineta_k_start | vineta_k_start.{png,ppst,ppdmp} | Single Race, Vector class, Feisar, Vineta K, the frame showing countdown "3" |
| zone | zone.{png,ppst,ppdmp} | Zone mode, first Zone track, first frame after the fade-in |
| boot-hle.log | PPSSPP log with HLE logging on, from boot into the frontend | Settings > Tools > Developer tools > logging |

Regenerate by hand; capture frames with Dev menu > GE debugger > Record for the `.ppdmp` files.
