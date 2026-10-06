# pure-recomp

A native macOS (arm64) build of **Wipeout Pure** (PSP, Studio Liverpool, 2005) by static recompilation. The game's
MIPS Allegrex code is translated to C++ ahead of time and runs against a rewritten PSP OS layer; the PSP graphics
engine is replaced by a Vulkan backend (through MoltenVK) first and a native Metal backend later. You need your own
dump of the US Greatest Hits disc (UCUS-98612, v2.00, ISO CRC32 4502C588). Nothing from the game is in this repo.

Framework: the MIT [PSPRecomp](https://github.com/jessicanataliagta/PSPRecomp) lineage as carried by
[TeamGDB/Yakumo](https://github.com/TeamGDB/Yakumo), vendored at a pinned commit under `vendor/` and modified
through the numbered series in `patches/`. Our game profile lives in `src/` and is synced into the vendor tree.

## Status
See [docs/status.md](docs/status.md). Decisions: [docs/decisions.md](docs/decisions.md). Research:
[docs/research.md](docs/research.md).

## Layout
| Path | What |
|---|---|
| `config/` | function map, labels, imports, HLE coverage, codegen config, pad scripts. Addresses and names only |
| `src/` | our profile: `profile/` glue, `hle/` overrides and stubs, `gpu/` backend seam and backends, `host/` SDL window, input, dumps |
| `patches/` | changes to the vendored framework, applied in numeric order (`tools/patches.sh`) |
| `tools/` | extraction, build, run, measurement, Ghidra and PPSSPP drivers |
| `tools/patches.sh` | `check`: the vendor tree is `vendor/PIN` plus `patches/` exactly; `export NNNN-slug`: the vendor change beyond the series as a new patch |
| `tools/worktree_init.sh` | first thing in a git worktree: vendor tree, links to the main checkout's `disc/`, `generated/`, `disc.iso`, its own `game/`, build from the shared ccache (about 35 s) |
| `tools/save_roundtrip.sh` | M5 save round trip on its own stick (`out/014/game/ms0`): profile NEW (`main_menu.txt`), LOAD (`profile_load.txt`), LOAD beside an empty DLC folder; exit 0 when all three hold (about 7 min, windowed; `docs/savedata.md`) |
| `tools/frame_regress.sh` | frame regression suite: boots the frontend, main-menu and race routes on an empty stick, captures `lang`, `title`, `profile`, `main_menu` and `race_hud` (race frame 6016), compares each with its `ref/` capture at the limits in the script's table, prints PASS/FAIL per scene to `out/regress/summary.txt`; exit 0 when all pass. Run before merging a renderer change (about 7 min, windowed; `docs/verification.md`) |
| `docs/` | setup, vendor map, decisions, status, spike results, task briefs under `docs/tasks/` |
| `ref/` | PPSSPP reference captures (ignored except the README) |
| `disc/`, `disc.iso`, `gen/`, `vendor/`, `build/`, `out/`, `ghidra_project/` | ignored: game data, generated code, third party, build output |

## First-time setup
```
brew install cmake ninja ccache pkgconf sdl3 molten-vk vulkan-loader vulkan-headers glslang vulkan-validationlayers ghidra
brew install --cask ppsspp-emulator
ln -s "/path/to/Wipeout Pure (USA) (En,Fr,Es) (v2.00).iso" disc.iso
python3 tools/iso_extract.py disc.iso verify && python3 tools/iso_extract.py disc.iso extract disc
tools/check_env.sh
```
Details and machine traps: [docs/setup.md](docs/setup.md). Ghidra: `tools/ghidra_headless.sh import` then `export`.

## Running
`tools/setup_game.sh` lays out `game/` (EBOOT.ELF = the disc's plain BOOT.BIN, `disc.iso`, `ms0/`). `tools/regen.sh`
generates the corpus into `generated/` (85 s) and `tools/build.sh profile` compiles it (8 min cold, seconds after).
`build/arm64/bin/PureNative` runs the game; `tools/run_boot.py` wraps it with a deadline and a folded log. The game
runs under a pty, so a deadline kill loses no output, and the log always ends with the `[run_boot] exit` line.

| `tools/run_boot.py` flag | Meaning |
|---|---|
| `--seconds N` | wall-clock deadline, default 60; exit code 124 when it kills the game |
| `--window` | renderer and audio on (headless otherwise) |
| `--strict` | `PURE_STRICT_HLE=1` |
| `--frames N` | `PURE_EXIT_AT_FRAME=N`, deadline at least N/15 s, exit code 0 when the run ends at that frame |
| `--script FILE` | `PURE_INPUT_SCRIPT` from the file's non-empty, non-`#` lines joined with `;`; implies `--window` |
| `--shots DIR` | `PURE_SCREENSHOT_DIR`; implies `--window`; after the run each new BMP there gets a PNG beside it (`tools/png.py`) |
| `--every N` | `PURE_SCREENSHOT_EVERY` (default 0 with `--shots`: only the script's `shot` steps write) |
| `--stubs` | `<log>.stubs.txt`: the start-up "Unimplemented imports" list and each `[hle-stub]` call with its `ra` |
| `--max-lines N`, `--env K=V` | log cap (default 20000); any extra environment variable, applied last |

| Switch | Meaning |
|---|---|
| `PURE_NO_RENDER=1 PURE_NO_AUDIO=1` | headless (what `tools/run_boot.py` sets unless `--window`) |
| `PSPRECOMP_NO_INTERPRETER=1` | stop at the first address with no recompiled code instead of interpreting it |
| `PURE_EXIT_AT_FRAME=N`, `PURE_FRAME_LOG=N` | stop at the Nth flip; log every Nth flip (`[pure] frame N`) |
| `PURE_SCREENSHOT_DIR=dir PURE_SCREENSHOT_EVERY=N` | windowed only: BMP of every Nth frame (`tools/run_boot.py --shots` converts them to PNG) |
| `PURE_INPUT_SCRIPT="700:pad a;1350:pad start;1500:shot name"` | scripted input, frame-indexed; actions `pad a/b/x/y/start/select/dpup/...` (a = Cross), `key NAME`, `shot NAME`, `quit` |
| `PURE_LIST_STUBS=1`, `PURE_STRICT_HLE=1` | list unimplemented imports at start; stop at the first one called |
| `PURE_TRACE_{KERNEL,IO,GE,MPEG,ATRAC,SAS,AUDIO,SAVEDATA,PAD,PACING,SYNC}=1` | framework traces, one subsystem each |
| `PURE_MALLOC_DEBUG=1` (in `tools/env.sh`) | macOS malloc checks for a single run (task 015): `( export PURE_MALLOC_DEBUG=1; . tools/env.sh; python3 tools/run_boot.py ... )` |
| `PURE_NO_STENCIL_ALPHA=1` | (patch 0004) the renderer stores each draw's fragment alpha and ignores the stencil ops and write masks, as before task 009 (the whole race scene blooms); implies `PURE_NO_STENCIL_BUFFER=1` |
| `PURE_NO_STENCIL_BUFFER=1` | (patch 0006) no Vulkan stencil attachment, as with patch 0004 alone: every stencil test is drawn as ALWAYS and only the zpass REPLACE/ZERO reach the alpha, so the ship shadows (stencil volumes) are missing |
| `PURE_NO_DUAL_SOURCE=1` | (patch 0006) no dual-source blending: a stencil REPLACE under a colour blend that reads the source alpha is stored through the blend constant (exact only where the fragment is opaque); with the stencil attachment on, the alpha is then copied from the stencil before anything reads it |
| `PURE_TRACE_STENCIL_COPY=1` | (patch 0006) a `[render] stencil copied into the alpha of 0x... in frame N (reason)` line for each copy of the stencil into a target's alpha (one per race frame, at the end of the back buffer's pass) |
| `PURE_NO_DEPTH_READBACK=1` | (patch 0008) no depth write-back: guest VRAM under the depth buffer stays as it was (zeros on Vineta K), so the lens flare's CPU depth test always sees open sky and the flare is never occluded, as before task 019. The write-back is on by default for every game on the framework (it has no per-game hook for it), and costs one GPU wait per GE SIGNAL interrupt with a screen-wide depth buffer: one per race frame in Wipeout Pure, none in its frontend |
| `PURE_TRACE_DEPTH_READBACK=1` | (patch 0008) a `[render] frame N signal 0x200: depth of 0x... written back to 0x04110000 stride 512, z MIN-MAX, T ms (GPU wait W ms)` line for each depth write-back |
| `PURE_WATCH_MOVIE=1` | once per flip, while they change: the game's movie object (`DAT_08ab45bc`) and its fields `active`, `ended`, `paused`, reader state, picture-queue capacity, `queued`, `shown` (pictures handed to the renderer), slots (`[pure] movie frame N ...`) |
| `PURE_AUDIO_WAV=<file>` | (task 013) WAV capture of what the game hands to sceAudio (`sceAudioOutputPannedBlocking`, `sceAudioOutputBlocking`, `sceAudioOutputPanned`): each buffer as stereo 16-bit 44.1 kHz with the call's volumes applied, to `<file>.ch<N>.wav` per channel and the clipped sum to `<file>`. Every file is on the virtual clock (sample 0 at time 0; a late or idle channel gets zeros). Read with `tools/wavstats.py` (docs/verification.md, "Audio") |
| `PURE_WATCH_SHIP=1` | (task 007) once per flip during a race, while it changes: the player's race record (`.bss` array of 0x1C0-byte entries, position of entry k at `0x08B72010 + k*0x1C0`): race clock, position, velocity, km/h, track distance, lap, and (task 017) the shield from the ship object (`be::Ship` +0xF8, float, 100 full on the Feisar) (`[pure] ship frame N t=... clock=... pos=... vel=... kmh=... dist=... lap=... shield=...`). PPSSPP reads the same race-record addresses |
| `tools/campaign_sweep.py [MODE [TRACK ...]] [--frames N] [--set KEY=VALUE] [--out DIR]`, `... MODE TRACK --tune` | (tasks 012, 016, 018) each (mode, track) cell from a cold boot to the mode's end screen: menu route + the mode's route (`config/pad_scripts/{single_race,time_trial,free_play,zone,tournament}.txt`, N DOWN presses per `docs/tracks.md`) + the steering table `config/pad_scripts/drive/<track>.txt`, whose `follow` line steers closed loop along the AI racing line `<track>.line.csv` through `PURE_INPUT_LIVE` (dead-zone mapping, recovery off a wall, Square to absorb pickups; options in class `Tuner`, `--set` overrides them for one run), strict, no interpreter, ship probe on; `--frames` counts from the route's Cross hold (6100 in Single Race; default: the track's budget in `MODES`: Single Race 13000 for Vineta K, 18000 for the other Alpha tracks; Time Trial and Free Play, at 30 flips a second, 9000 for Vineta K and 11000 for the others; Zone 9000; Tournament 80000 for its four races); `--no-damage` sets the test switch `PURE_TEST_NO_DAMAGE=1` (below) and marks the summary row `(no damage)` (the normal way to run a coverage cell, except in Zone, which ends when the ship is destroyed and ignores it). End screens (`docs/tracks.md`): the results panel's TOTAL label (Single Race, TIME TRIAL COMPLETED, each Tournament race; Cross every 2 s through ENTER TAG, the race standings, TOURNAMENT STANDING and NEXT RACE between Tournament races, PASS on the TOURNAMENT STANDING title after the last race), FREE PLAY SESSION RESULTS' TOTAL LAPS label (Free Play, paused and ended with END SESSION after three laps), the SHIP DESTROYED panel with TOTAL ZONES CLEAR read into the summary (Zone). Outputs `out/sweep/<mode>-<track>.{log,png,trace.csv,contacts.csv}` and `out/sweep/summary.txt` (outcome, laps, contacts a lap; a STALL row classifies the stop from the probe's shield, a `stall` shot's "SHIP DESTROYED" title and shield bar, and lists the last 5 s of the trace). `tools/pp_lines.py TRACK [--downs N]` records the AI line in PPSSPP (`out/lines/TRACK.csv`); `--export-line` turns it into the committed `.line.csv` |

### Test switches (never for play)
Instruments for the tools. Each one changes the game's rules, prints a `[pure] TEST SWITCH: ...` line at start-up,
and is off unless set.

| Switch | Meaning |
|---|---|
| `PURE_TEST_NO_DAMAGE=1` | (task 017) before every flip the player's shield (`be::Ship` +0xF8) is set back to its full value (the ship type's maximum, `*(*(ship + 0xC8) + 0x74) + 0x84`), so contacts never destroy the ship. For `tools/campaign_sweep.py --no-damage`, which only has to reach every results screen to look for halts |

Routes that reach known screens, as input scripts in `config/pad_scripts/` (frames from a cold start at the default
pacing): `frontend.txt` confirms the language at 700, skips the loading page at 1600, clears the memory-stick notice
at 1650 and skips the intro movie with Start at 1800; the title is up from 1810 (shots `lang`, `notice`, `title`).

## Working with Claude
This repo is worked on by a Fable session that plans, maps the hard parts and reviews, and by Opus subagents that
carry out briefed tasks (`.claude/agents/`). The rules every session follows are in `CLAUDE.md`; each task is a
file under `docs/tasks/` with one verification command.

## Licence
Our code: GPL-2.0-or-later. Vendored framework: MIT. FFmpeg: LGPL, linked dynamically. See `docs/decisions.md` D-006.
