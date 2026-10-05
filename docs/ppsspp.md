# PPSSPP driver (tools/ppsspp/ppsspp_ctl.py)

## Status at pause (2026-10-05)

Works:
- `tools/ppsspp/ppsspp_ctl.py` (Python 3 stdlib only, no venv) launches `/Applications/PPSSPPSDL.app` 1.20.4 on
  `disc.iso` in a window at 1x with the WebSocket debugger on, connects to it, plays a frame-indexed pad script,
  saves PNG screenshots and GE dumps (`.ppdmp`) at given frames, and quits PPSSPP cleanly (SIGTERM). `status`,
  `shot`, `gedump`, `press`, `quit`, `launch` and `ini apply|restore|show` work on a running instance.
- Input is exact in emulated time: the script goes through PPSSPP's replay engine (`replay.execute`), stamped half a
  frame before the target vblank. Runs are deterministic: two runs of the same script gave byte-identical
  screenshots for all 118 shared capture frames (trials 7 and 8, frames 30 to 3540).
- Screenshots and GE dumps are taken at a well-defined frame (see "Capture point" below); the vblank model was
  measured against the game and has no drift.
- The ini is edited per run and put back afterwards; PPSSPP's own first ini is kept as
  `~/.config/ppsspp/PSP/SYSTEM/ppsspp.ini.orig` (and `controls.ini.orig`). The live ini is currently restored to the
  `.orig` content and no PPSSPP instance is running.

Does not work yet / blocked:
- No reference captures exist yet in `ref/` (frontend.png, frontend.ppdmp, boot-hle.log, vineta_k_start.*). The
  scripted frontend route is unfinished: it reaches the PROFILE screen and the name/tag entry deterministically, but
  the SAVE PROFILE answer is mistimed in `routes/frontend_draft.txt` (DOWN lost, CROSS picks YES, Save dialog opens).
  By hand (`press` on a running game) I did reach MAIN MENU and then Single Race > Vector > Alpha > Vineta K >
  Feisar, up to READY / countdown / GO; only the frame numbers of a scripted run are missing.
- Screenshots need PPSSPP's software renderer. The debugger's `gpu.buffer.screenshot` (and every `gpu.buffer.*`)
  fails in 1.20.4 while the CPU is stepping ("Could not download output": the request is only serviced in GE
  stepping, which the WebSocket API cannot enter) and returns the window backbuffer anyway. The driver reads the
  displayed framebuffer from VRAM with `memory.read` instead, which is only valid with `SoftwareRenderer = True`
  (with Vulkan, VRAM framebuffers stay zero). GE dumps work with either renderer.
- Save states (`--savestate`) are blocked: the debugger has no save-state event, and the fallback (posting the
  F2 Save State hotkey with CoreGraphics) needs the Accessibility / post-event permission, which this terminal does
  not have (`CGPreflightPostEventAccess` = false). Granting it to the terminal app makes `--savestate` work.
- `ref/boot-hle.log` not captured yet: the verified run below wrote a boot-to-title HLE log to `out/ppsspp/`; rerun
  with `--log ref/boot-hle.log` on the finished frontend route.

Exact command to reproduce a capture (title screen at frame 2650, screenshot and GE dump of the same frame):
```
cd ~/dev/pure-recomp
/opt/homebrew/bin/python3 tools/ppsspp/ppsspp_ctl.py run \
  --pad "700:CROSS,708:,1700:CROSS,1708:,2400:START,2408:" \
  --shot 2650:out/ppsspp/title.png --gedump 2650:out/ppsspp/title.ppdmp \
  --log out/ppsspp/boot-hle.log --report out/ppsspp/title.json
```
Verified 2026-10-05 13:08: 46 s wall, captured frame 2653 (title screen, framebuffer 0x04000000), 26388-byte
`.ppdmp` (PPSSPP's own copy `~/.config/ppsspp/PSP/SYSTEM/DUMP/UCUS98612_0002.ppdmp`), 1.16 MB HLE log, PPSSPP quit
cleanly, ini restored. These are title-screen captures in `out/`, not the `ref/` frontend scene.
Trial screenshots every N frames (how the route was found): add `--until F --shots-every N [--shots-from F]
--shots-dir DIR`. Scene timeline on a fresh memstick (software renderer): SCEA logo ~120, LANGUAGE SELECTION from
~480 (CROSS at 700), Studio Liverpool ~1200, memory-stick notice ~1560 (CROSS at 1700), FX300 intro then movie
~1800 (START at 2400 skips it), title "PRESS START BUTTON" stable from ~2520 (blinking cursor), PROFILE
(LOAD/NEW/DELETE) stable from ~2880 after START at 2700.

Memstick state matters: the game wrote `PSP/SAVEDATA/PPCD00001DLS001` ("Online system info") the first time it
passed the title (trial 6); all later trials ran with it present. A profile save `UCUS98612P0000` created by an
accidental YES in trial 10 was moved to `out/ppsspp/savedata-moved/`; routes assume no profile save exists.

## How it works

1. `ini`: before each `run`, the current `ppsspp.ini`/`controls.ini` are copied to `*.pre-ctl`, the driver keys are
   set, and after PPSSPP exits the copies are put back (`--keep-ini` leaves the driver keys). `ppsspp.ini.orig` is
   written once, never overwritten; `ini restore` copies it back. Config location on this build: `$HOME/.config/
   ppsspp/PSP/SYSTEM/` (macOS memstick default = `$HOME/.config/ppsspp`; `~/Library/Application Support` unused).
2. `launch`: `PPSSPPSDL --windowed --pause-menu-exit [--log=FILE] <iso>`; stdout goes to `out/ppsspp/ppsspp-stdout.log`.
   The debugger port is the configured `RemoteISOPort`; if it was busy PPSSPP picks a random one and the driver
   finds it with `lsof`.
3. With `AutoRun = False` PPSSPP boots into a CPU break at emulated time 0. The driver connects to
   `ws://127.0.0.1:PORT/debugger` (subprotocol `debugger.ppsspp.org`), disables log/input broadcasts, sets the RTC
   base (`replay.time.set`, default 2026-01-01 00:00 UTC), sends the pad script as a replay blob, and resumes.
4. Frames: vblank N starts at V(N) = 15951.8 us + (N-1) x 16683.3 us of emulated time (`cpu.evaluate usec`).
   Measured: the game's return from `sceDisplayWaitVblankStartCB` lands 5 us after V(N) at N = 296..2996.
5. Capture point for frame N: a conditional breakpoint `usec >= V(N)` on the import stub
   `zz_sceDisplaySetFrameBuf` stops at flip k (first flip at or after V(N)); `gpu.record.dump` is armed there; the
   breakpoint is re-added unconditionally and the next flip k+1 is caught; its `a0..a3` (address, stride, format,
   sync) locate the finished frame k+1 in VRAM, which is read and written as a 480x272 RGB PNG. The GE recorder
   starts at flip k and ends at flip k+1, so the `.ppdmp` and the PNG are the same frame. Wipeout Pure flips with
   `sceDisplaySetFrameBuf(0x04000000 | 0x04088000, 512, 3 (8888), 0 (immediate))` at 30 fps, so the captured frame
   is usually N+2. The report JSON records `flip_k_frame` and `frame` (vblank position of flip k+1).
6. Quit: SIGTERM; SDL turns it into SDL_QUIT and PPSSPP saves its config and exits (SIGKILL after 15 s).

## ini keys the driver sets

| Section | Key | Value | Why |
|---|---|---|---|
| General | AutoRun | False | boot into a CPU break so input/time start at 0 |
| General | RemoteDebuggerOnStartup | True | start the web server with the debugger |
| General | RemoteISOPort | 45333 (`--port`) | fixed debugger port |
| General | FirstRun, CheckForNewVersion | False | no popups |
| General | PauseOnLostFocus, PauseWhenMinimized | False | keep running in the background |
| General | Enable Logging | True | needed for `--log` |
| General | RewindSnapshotInterval, AutoLoadSaveState, EnableCheats | 0, 0, False | determinism |
| General | WindowWidth, WindowHeight | 960, 544 | window size only |
| Graphics | GraphicsBackend | 3 (VULKAN) | presentation backend |
| Graphics | SoftwareRenderer | True (`--renderer software`, default) / False | VRAM holds real pixels |
| Graphics | InternalResolution, FrameSkip, AutoFrameSkip, FullScreen | 1, 0, False, False | 1x, every frame |
| SystemParam | GameLanguage, ButtonPreference | 1, 1 | English, CROSS confirms |
| Sound | GameVolume | 0 (unless `--sound`) | silence |
| Log (`--log`) | SCEUTIL, SCEDISP, MPEG, SCEIO = 5; SCEKERNEL, ME, ATRAC, HLE, SCEMODULE, LOADER, BOOT, SYSTEM, SCEGE, SCEAUDIO, SCESAS, SCECTRL, SCERTC = 4 | Debug / Info | HLE trace; SCEKERNEL at Debug writes ~20k lines/s (context switches) and slows the run |
| controls.ini (`--savestate`) | Save State | 1-132 (F2) | hotkey for the blocked save-state path |

Note the key is `SoftwareRenderer`, not `SoftwareRendering`.

## Debugger events used (request -> response, as observed on 1.20.4)

| Event | Request | Response / notes |
|---|---|---|
| `version` | `{name, version}` | `{name: "PPSSPP", version: "v1.20.4"}` |
| `broadcast.config.set` | `{disallowed: {logger: true, input: true}}` | refused ("Unsupported key") until the server's first poll; retry |
| `game.status` | `{}` | `{game: {id: "UCUS98612", version: "2.00", title: "Wipeout Pure"} or null, paused}` |
| `cpu.status` | `{}` | `{stepping, paused, pc, ticks}` |
| `cpu.evaluate` | `{expression: "usec"}` or a symbol (`zz_sceDisplaySetFrameBuf`) | `{uintValue, floatValue}`; numbers in expressions default to hex, write `0x...` |
| `cpu.stepping` | `{}` | no reply; a `cpu.stepping` broadcast `{pc, ticks, reason}` follows. Ignored by PPSSPP unless the core is in RUNNING_CPU (between frames it is NEXTFRAME), so the driver repeats it |
| `cpu.resume` | `{}` | no reply; `cpu.resume` broadcast |
| `cpu.nextHLE` | `{}` | breaks after the next HLE call; Wipeout makes one every few us, too slow for pacing (not used) |
| `cpu.breakpoint.add` / `remove` | `{address, condition?}` | `{}`; condition `usec >= 0x...` |
| `cpu.getReg` | `{name: "a0"}` | `{uintValue, ...}` |
| `memory.read` | `{address, size}` | `{base64}` |
| `replay.time.set` | `{value: unix_seconds}` | `{}` |
| `replay.execute` | `{version: 1, base64}` | `{}`; blob = packed items `u8 action, u64 time_us, 8-byte payload` (0 buttons u32, 1 analog u8[2][2]); the driver centres the sticks first because replay analog starts at (0,0) |
| `replay.status` | `{}` | `{executing, saving}` |
| `gpu.record.dump` | `{}` | no reply; later `{event: "gpu.record.dump", ticket, uri: "data:application/octet-stream;base64,..."}` (same ticket). PPSSPP also writes `~/.config/ppsspp/PSP/SYSTEM/DUMP/UCUS98612_NNNN.ppdmp` |
| `gpu.stats.get` | `{}` | after next flip: `{fps, vblanksPerSecond, info}` |
| `hle.thread.list` | `{}` | `{threads: [...]}` |
| `input.buttons.send` | `{buttons: {cross: true}}` | `{}`; used only by `press` (not frame-exact) |
| `gpu.buffer.screenshot` | `{type: "uri"}` | fails while CPU-stepping on 1.20.4 (see above); not used |

## Limitations

- Emulated time `usec` is 32-bit: runs longer than 71 minutes wrap.
- Capture frames are "first frame drawn after the first flip at or after V(N)", not the display at vblank N.
- The web server binds all interfaces and PPSSPP registers the LAN address with report.ppsspp.org while the debugger
  is on (PPSSPP behaviour); the driver turns it off again when it restores the ini.
- The game's menus drop presses that land during transitions; routes need wide spacing (90+ frames inside the name
  entry worked; screen changes take 100-300 frames).

## Reaching the reference scenes (by hand, frames still to be pinned)

- frontend: language CROSS, memory-stick notice CROSS, START (movie), START (title), PROFILE: DOWN to NEW, CROSS;
  SET NAME: CROSS x4 (N,A,M,E), then DOWN+CROSS x4 (four '0'), CROSS on the blank 9th slot ends the name, CROSS to
  SET TAG; CROSS x3 (AAA), CROSS; SAVE PROFILE: DOWN to NO, CROSS; WARNING (autosave disabled): CROSS; MAIN MENU
  (SINGLE PLAYER / MULTIPLAYER / PROFILE / DOWNLOAD). Answering NO keeps the memstick free of profile saves.
- vineta_k_start: from MAIN MENU, CROSS on SINGLE PLAYER, SINGLE RACE, VECTOR, ALPHA league, VINETA K, FEISAR (each
  the first entry, so CROSS only); the race loads, flies the camera, shows READY, then the blue countdown rings
  (about 60-90 frames after READY) and GO.
- zone: SINGLE PLAYER menu, DOWN x3 to ZONE, CROSS; not explored yet.
