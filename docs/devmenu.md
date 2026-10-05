# Developer menu and TTY (spike S7)

## What the disc says
`USRDIR/DevMenu.cfg` (839 bytes) is a flat key/value list: Language, Load Frontend, Track (a `Z:\Data\...` path),
Team, Class, NPC Team, AI Network Client, Camera Mode, Mode, Number of NPC, Cut-down graphics, Test new
track-slope-camera-pitch, Single lap override, Emulate PSP polygon clipping, Replay Camera Mode, Progression,
Sound, Analog Stick, Control Focus, Use new arcade mode balancing, New mode speed, Arcade mode handicap, AI Speed,
Stop AI moving, Show AI race speeds, Ship scale, AI FPS, Draw Collision Data, Draw Simulation, AI Weapons, Pickups,
Autopilot, per-weapon toggles, Disruptor Setting, FPS TTY, File TTY, Network TTY, Music.

## What the retail BOOT.BIN says (string survey, 2026-10-05, `out/strings-survey.txt`)
- No `DevMenu`, `.cfg`, `Load Frontend`, `Cut-down`, `Emulate PSP` string exists in the binary. The dev menu
  parser is almost certainly compiled out of the retail build; the file is a leftover. Do not plan on it for
  track selection or Autopilot; scripted pad routes do that instead (M3-T3). The `Autopilot` strings present are
  the pickup name and the "Autopilot Slow/Fast" cheat effects.
- Debug output paths survive: `host0:memory%s%d.txt`, `host0:tree%s%d.txt`, `host0:inputblock%s%d.txt`,
  `Log.txt` opened `a+t`, and `host0:DVD\USRDIR\FEData.wad` as the dev-kit fallback for `umd:FEData.wad`
  (string at BOOT.BIN offset 0x2408e0, near `BackendRoot.cpp`). The retail path is `umd:` with a bare file name,
  so the IO layer must resolve `umd:FEData.wad` to `disc/PSP_GAME/USRDIR/FEData.wad`.
- Format strings are plentiful (`%s\TrackStartup.xml`, `Block:0x%08X Size:%d ...`), so a printf-style sink
  exists. Which import it reaches (sceIoWrite on fd 1/2, `Kprintf`, or a `host0:` file) is for Ghidra (S7).
- Source paths: `C:/Work/Wipeout/Code/...` (291 of them) and one `Z:\Art_Resources\...`.

## TTY sink (S7 result, from `out/tty.txt`)
The game uses the PSP libc stdio. `FUN_08a22cfc` is `fwrite` (maps the FILE to a descriptor through `FUN_08a232b4`
and calls `sceIoWrite(fd, buf, size*count)`), `FUN_08a22da8` is `fputc`, and `FUN_0880b790` is the read hook that
turns descriptors 0/1/2 into `sceKernelStdin/Stdout/Stderr()`. Its sibling `FUN_0880b834` does the same for writes.
So the sink is **`sceIoWrite` on the descriptor returned by `sceKernelStdout()` or `sceKernelStderr()`**. The HLE
returns fixed descriptors (1 and 2) from those two calls and routes `sceIoWrite` on them to stdout as `[tty]` lines,
which is what task M1-T3 implements. Whether retail code still calls printf/fwrite is settled by running it (M1 exit).
`Log.txt` is opened with mode `a+t` by `FUN_08a38ffc` (references at 0x08A39030); treat as a file in `out/` if it
is ever opened.

## Open
- Whether any dev-menu loader survives under another name (no string evidence; closed unless M1 shows a read of
  `DevMenu.cfg` in `PURE_IO_TRACE`).
