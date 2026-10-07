# PPSSPP driver (tools/ppsspp/ppsspp_ctl.py)

## What it does (task 006, 2026-10-05; later tasks added routes and the audio dump)

Works:
- Reference captures exist: `ref/` holds frontend (Language Selection), title, profile, main_menu and
  vineta_k_start, each as a PNG and a `.ppdmp` of the same frame, plus `ref/boot-hle.log`; frames and hashes are in
  `ref/README.md`. The routes are `routes/frontend.txt` (cold boot to MAIN MENU, profile NAME0000 / AAA, SAVE
  PROFILE answered NO) and `routes/vineta_k_start.txt` (MAIN MENU to the Vineta K race start, chained after the
  frontend with a second `--pad-file`). Three runs gave byte-identical PNGs, and two runs byte-identical `.ppdmp`s.
  Task 035 added the routes of every mode and the unlock code (`tools/ppsspp/routes/`) and thirteen more scenes,
  task 044 the scorecard's references under `ref/scorecard/`; `ref/README.md` lists them all.
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
  `.orig` content after every run.

- Captures can be one flip apart: a screenshot-only capture leaves the CPU stepping, so the next capture arms its
  breakpoint before the game runs on. Before task 006 every capture resumed and paused again, which let about 16
  frames pass at real-time speed; `--shots-every 15` then drifted 3 frames per capture and named files after the
  requested frame. A capture that still starts late (after a GE dump, which has to resume) is flagged `late_frames`
  in the report and in the log.

Does not work yet / blocked:
- Screenshots need PPSSPP's software renderer. The debugger's `gpu.buffer.screenshot` (and every `gpu.buffer.*`)
  fails in 1.20.4 while the CPU is stepping ("Could not download output": the request is only serviced in GE
  stepping, which the WebSocket API cannot enter) and returns the window backbuffer anyway. The driver reads the
  displayed framebuffer from VRAM with `memory.read` instead, which is only valid with `SoftwareRenderer = True`
  (with Vulkan, VRAM framebuffers stay zero). GE dumps work with either renderer.
- Save states (`--savestate`) are blocked: the debugger has no save-state event, and the fallback (posting the
  F2 Save State hotkey with CoreGraphics) needs the Accessibility / post-event permission, which this terminal does
  not have (`CGPreflightPostEventAccess` = false). Granting it to the terminal app makes `--savestate` work.
- (Done in task 035: `routes/zone_start.txt` reaches Zone.)

The exact commands that made `ref/` are in `ref/README.md` ("Regenerate"); each run takes about 2 minutes (the
emulator runs at real-time speed) and quits PPSSPP and restores the ini at the end. Verified 2026-10-05: the
capture run took 122 s wall, the logged run to the main menu 96 s.
Trial screenshots every N frames (how the routes were found): add `--until F --shots-every N [--shots-from F]
--shots-dir DIR`. Scene timeline (software renderer): SCEA logo ~120, LANGUAGE SELECTION from ~480 (CROSS at 700),
Studio Liverpool ~1200, memory-stick notice ~1560 (CROSS at 1700), FX300 intro then movie ~1800 (START at 2400 skips
it), title "PRESS START BUTTON" stable from ~2520 (blinking cursor), PROFILE (LOAD/NEW/DELETE) stable from ~2850
after START at 2700; the rest of the frontend is annotated in `routes/frontend.txt`. Race route (presses at
5700-6700): LOADING at 6753, camera fly-by from ~6810, HUD fades in 7151-7155, READY from 7213, blue ring from ~7220,
GO! at about 7391-7411.

Memstick state matters: the game wrote `PSP/SAVEDATA/PPCD00001DLS001` ("Online system info") the first time it
passed the title (trial 6); all later runs, including every task 006 run, ran with it present and left it unchanged
(mtime still 12:45). A profile save `UCUS98612P0000` created by an accidental YES in trial 10 was moved to
`~/dev/pure-recomp/out/ppsspp/savedata-moved/`; the routes assume no profile save exists, and answering NO on SAVE
PROFILE keeps it that way (no task 006 run wrote one).

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
| General, Sound (`--dump-audio WAV`) | DumpAudio, SaveLoadResetsAVdumping; Enable | True, False; True | PPSSPP's audio dump (task 041): moved to WAV at the end |

Note the key is `SoftwareRenderer`, not `SoftwareRendering`.

## Audio dumps (task 041, 2026-10-07)

`run --dump-audio WAV` turns on PPSSPP's own audio dump for the session (`[General] DumpAudio = True`,
`SaveLoadResetsAVdumping = False`, and `[Sound] Enable = True`, which the dump needs) and, after PPSSPP quits, moves
the WAV it wrote to `WAV`. PPSSPP writes `<memstick>/PSP/AUDIO/UCUS98612_<date>_<time>.wav`: every audio update's mix
of the sceAudio channels, clamped to 16 bits, 44.1 kHz stereo, from the first update after boot, on emulated time, and
before its host volume and resampling, so the driver's default `GameVolume = 0` does not silence it (checked: the
frontend route to frame 5257 gave 87.7 s of audio for 87.70 s of emulated time, with sound in it). It is the mix only,
with no channel apart; PPSSPP closes the file when it shuts down, and the driver repairs the RIFF sizes if it did not
(a killed run). `--keep-running` is refused with it. The report JSON gets `audio_dump` (path, PPSSPP's file, seconds).
An emulated-time dump is the same however fast the host runs PPSSPP, so `--renderer hardware` is fine for it.
docs/history/fidelity.md ("Differences 7 to 9") has the runs that compare it with the port's `PURE_AUDIO_WAV`;
`routes/free_play_idle_end.txt` leaves the ship on the grid in Free Play past the race music's first track change
and ends the session from the pause menu.

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

## Reaching the reference scenes

- frontend (`routes/frontend.txt`, frames in the file): language CROSS, memory-stick notice CROSS, START (movie),
  START (title), PROFILE: DOWN to NEW, CROSS; SET NAME: CROSS x4 (N,A,M,E), then DOWN+CROSS x4 (four '0'), CROSS on
  the blank 9th slot ends the name, CROSS to SET TAG; SET TAG: CROSS x4 (the tag reads AAA, its cursor goes away),
  then one more CROSS: SET TAG does not advance by itself, and this missing press was the draft route's SAVE
  PROFILE "mistiming"; SAVE PROFILE: DOWN to NO, CROSS; WARNING (autosave disabled): CROSS; MAIN MENU (SINGLE
  PLAYER / MULTIPLAYER / PROFILE / DOWNLOAD). Answering NO keeps the memstick free of profile saves.
- vineta_k_start (`routes/vineta_k_start.txt`): from MAIN MENU, CROSS on SINGLE PLAYER, SINGLE RACE, VECTOR, ALPHA
  league, VINETA K, FEISAR (each the first entry, so CROSS only); the race loads, flies the camera, fades the HUD
  in, shows READY with a spinning blue ring, then GO!. There are no countdown digits; `ref/vineta_k_start.png` is
  the first frame with the HUD fully in (CURRENT 0.00.0, ship on the grid).
- zone: SINGLE PLAYER menu, DOWN x3 to ZONE, CROSS; not explored yet.
