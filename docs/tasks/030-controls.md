# 030: Controls: the keyboard and gamepad mapping documented and checked under the Metal shell

Milestone: M7 | Branch: task/030-controls | Status: OPEN

## Goal
The framework maps the keyboard (two layouts, rebindable in its menu, saved in settings.ini) and SDL gamepads to the
PSP pad; the shell seam (task 026) moved that code into `host/shell/sdl_pad.cpp` and `gamepad.cpp`, and the Metal
shell (task 027) uses it. Nothing documents what a player presses, and nobody has checked the menu's binding editor
under the Metal shell. This task writes `docs/controls.md` from the code, checks the editor and the gamepad path with
a scripted virtual gamepad, and leaves a place for the enhancement E1 (rebinding and dead zones) to start from.

## Read first
- CLAUDE.md, docs/status.md (the enhancements table in ~/.claude/plans is summarised there under M7/E1), README.md
  (the input rows), docs/ge-backend.md 8.5 ("The headless shell": the script's pad names)
- vendor/portablekit/host/input/bindings.hpp and .cpp (`Action`, `default_bindings()`, `classic_bindings()`, the
  settings.ini format `parse`/`assign`), host/shell/gamepad.cpp (`read_gamepad`, `PadTuning`: dead zones, triggers
  as L/R, the stick), host/shell/sdl_pad.cpp (keys and mouse to actions; the virtual gamepad the input script
  attaches), host/ui/input_script.cpp and host/shell/script_steps.cpp (`pad NAME`, `axis NAME VALUE`, `key`, `mouse`),
  host/ui/menu.cpp (the Controls tab: what it edits), host/settings/settings.cpp (where settings.ini lives)
- src/host/metal_shell.mm (`SdlPad` use, the event hook)

## Deliverable
1. `docs/controls.md`: a table of the PSP pad against the default keyboard layout and the classic layout, taken from
   `default_bindings()` and `classic_bindings()` (key positions named as the menu names them); the mouse's part; the
   gamepad mapping (`read_gamepad`: which SDL buttons and axes become which PSP inputs, the dead zone and trigger
   thresholds from `PadTuning`); how to rebind in the menu and in settings.ini (the exact file path on macOS and the
   key names); the input script's names for tests. One line on what the game itself expects (Wipeout Pure's
   defaults: Cross accelerate, Square/Circle airbrakes, L/R..., from the game's own controls screen, checked in a
   run, not from memory).
2. A check that the table is the code: `tools/controls_check.py` prints the two layouts from a small parser of
   `bindings.cpp`'s tables (or a `--dump-bindings` switch is out of scope: parse the source) and compares them with
   the tables in docs/controls.md; exit 1 on a difference.
3. The menu's Controls tab under the Metal shell: open the menu over the game (`PURE_SHELL=metal`), go to the
   Controls tab with the input script's `key` steps, rebind one action to another key, close the menu, and show the
   new key drives the game (`PURE_TRACE_PAD` prints the button) and settings.ini holds it; put the menu screenshot in
   out/030/ and name it in Result. Restore the setting afterwards (run on a scratch `PURE_DATA_DIR`).
4. The gamepad path with the script's virtual gamepad under the Metal shell: `pad a`, `pad start`, `axis leftx -1`,
   `axis lefttrigger 1` produce the expected `[pad] buttons`/stick values in a `PURE_TRACE_PAD=1` run (a table in
   Result), and the dead zone from `PadTuning` is what the doc says.
5. README.md: the input rows point to docs/controls.md.

## Acceptance criteria
- [ ] `python3 tools/controls_check.py` exits 0 and the two tables in docs/controls.md match the code.
- [ ] Item 3's rebinding works under the Metal shell (the screenshot and the trace lines in Result).
- [ ] Item 4's table matches `gamepad.cpp`.

## Verify
`python3 tools/controls_check.py && PURE_SHELL=metal PURE_GE_BACKEND=metal PURE_TRACE_PAD=1 python3 tools/run_boot.py --script config/pad_scripts/frontend.txt --frames 800 --seconds 120 out/030/pad.log && grep -q 'buttons 0x4000' out/030/pad.log`

## May touch
- docs/controls.md (new), tools/controls_check.py (new), README.md

## Must not touch
- vendor/, patches/, src/, config/, tools/ apart from the new script, ref/

## Estimated turns
30

## Escalate when
The menu's Controls tab does not open or does not save under the Metal shell (report what happens: that is a 027
follow-up, not yours to fix), or the gamepad path needs a code change (report it for E1).

## Result
Status: DONE

Changed:
- `docs/controls.md` (new): what the game expects (from its own controls screen, seen in a run), the keyboard table
  (PSP input, settings.ini key, menu label, PSP effect, default and classic layouts, the use in Wipeout Pure), the
  mouse's part, the gamepad (buttons for both `input.confirm` values, axes, the dead-zone formula with measured
  values, the tuning defaults with their ranges, menu rows and environment overrides), rebinding in the menu (keys,
  row order, capture rules) and in settings.ini (the macOS path, the format, every key name), the input script's
  names, and a list of starting points for E1. Three tables carry `<!-- controls_check: ... -->` markers.
- `tools/controls_check.py` (new): parses `bindings.hpp`/`.cpp` (Action enum, `hid` positions, `kKeyNames`,
  `kMouseNames`, `kInfo`, `kButtonBits`, `make_default`, `make_classic`), `gamepad.hpp`/`.cpp` (`kButtonNames`,
  `read_gamepad`'s `held(...)` lines) and `settings.hpp` (pad defaults); prints the two layouts as the menu formats
  them and compares the keyboard, gamepad and tuning tables of docs/controls.md; exit 0 match, 1 difference, 2 parse
  error. Mutation check: 11 edits of a copy of the doc (a layout cell in each layout, a label, a bit, a stick value, a
  removed row, a gamepad bit, a wrong button name, an extra gamepad row, the dead zone, a removed marker) each fail
  (exit 1, the marker exit 2) with the one difference named.
- `README.md`: the `PURE_INPUT_SCRIPT` and `PURE_TRACE_*` rows point to docs/controls.md, a line under Running, a
  `tools/controls_check.py` row. The `PURE_INPUT_SCRIPT` row listed `pad select`, which is not a name (a run prints
  `[script] unknown button select`); it now says `back` (Select).

Item 1, the game's own controls screen (headless Metal route, 4.3 s: `out/030/game_controls.txt`, MAIN MENU >
PROFILE > OPTIONS > CONTROLS, capture `out/030/shots/gc_controls.png`): Dual Airbrake, Airbrake Left L, Airbrake
Right R, Accelerate Cross, Use pickup Square, Reverse camera Triangle, Absorb pickup Circle; the frontend prompts are
Cross CONFIRM and Triangle BACK (`gc_options.png`).

Item 3, the menu's Controls tab under the Metal shell (`PURE_SHELL=metal PURE_GE_BACKEND=metal PURE_TRACE_PAD=1`,
scratch `PURE_DATA_DIR=out/030/rebind_data` and `PURE_GAME_DIR=out/030/game`, script `out/030/rebind.txt`, log
`out/030/rebind.log`): Esc opens the menu (paused), W W reaches Controls, 19 Downs reach "× (back)" (Cross), Return
starts the capture (`r2_capturing.png`: "Press a key or a mouse button"), `key X` adds X, Esc closes; then X in the
game; then the same path again and X removes X. **Menu screenshot: `out/030/shots/r3_bound.png`** (× (back) = Space /
X). Trace lines:

```
[script] frame 700: key X                      <- X before the rebind: no [pad] line, language screen stays (r4_closed.png)
[script] frame 800: key Escape
[menu] opened; the game is paused
[script] frame 1075: key X                     <- in the capture
[script] frame 1110: key Escape
[menu] closed after 2.9 s
[script] frame 1170: key X
[pad] buttons 0x4000 analog 128,128 right 128,128
[pad] buttons 0x0 analog 128,128 right 128,128   <- the game leaves Language Selection (r5_after_x.png: SCEA presents)
[script] frame 1575: key X                     <- second capture: X removed (r6_restored.png: Space)
[script] frame 1650: key X                     <- no [pad] line
```

settings.ini in the scratch folder, polled every 50 ms during the run (`out/030/settings_watch.txt`):
`09:23:41 input.bind.cross=Space`, `09:23:44 input.bind.cross=Space / X`, `09:23:53 input.bind.cross=Space`; the file
ends as the defaults. Erik's `~/Library/Application Support/pure-recomp/PureNative/settings.ini` is untouched (mtime
2026-10-05 16:23).

Item 4, the virtual gamepad under the Metal shell (`out/030/gamepad.txt`, `out/030/gamepad.log`; default tuning:
dead zone 0.15, trigger 0.25, confirm east, right stick camera). Expected values computed from `read_gamepad`:

| Step | `gamepad.cpp` | `[pad]` trace |
|---|---|---|
| `pad a` | South: Cross 0x4000 (`confirm_south` false) | `buttons 0x4000` |
| `pad b` / `pad x` / `pad y` | East Circle 0x2000 / West Square 0x8000 / North Triangle 0x1000 | `0x2000` / `0x8000` / `0x1000` |
| `pad start` | Start 0x0008 | `buttons 0x8` |
| `pad back` | Select 0x0001 | `buttons 0x1` |
| `pad leftshoulder` / `rightshoulder` | L 0x0100 / R 0x0200 | `0x100` / `0x200` |
| `pad dpup` / `dpdown` / `dpleft` / `dpright` | 0x0010 / 0x0040 / 0x0080 / 0x0020 | `0x10` / `0x40` / `0x80` / `0x20` |
| `pad guide` | not mapped | no line |
| `axis leftx -1` | `0x80 + int(-1 * 1 * 127)` = 1 | `analog 1,128` |
| `axis leftx 1` / `axis lefty -1` | 255 / y 1 | `analog 255,128` / `analog 128,1` |
| `axis leftx 0.1` | length 0.1 <= 0.15: centred | no line (stays 128) |
| `axis leftx 0.2` | `(0.2 - 0.15) / 0.85 * 127` = 7: 135 | `analog 135,128` |
| `axis leftx 0.5` | `0.35 / 0.85 * 127` = 52: 180 | `analog 180,128` |
| `axis leftx 0.7` + `axis lefty 0.7` (same frame) | radial: length 0.99, 88 each: 216,216 | `analog 216,216` |
| `axis lefttrigger 1` | 1 > 0.25: L 0x0100 | `buttons 0x100` |
| `axis lefttrigger 0` | SDL maps 0 to half travel, 0.5 > 0.25: still L | no line (still 0x100) |
| `axis lefttrigger -1` | 0: released | `buttons 0x0` |
| `axis righttrigger 1` / `-1` | R 0x0200 / released | `0x200` / `0x0` |
| `axis rightx 1` | camera mode: second stick 255 | `right 255,128` |
| `pad a+leftshoulder` | 0x4000 + 0x0100 | `buttons 0x4100` |
| `PURE_PAD_DEADZONE=0.3`: `axis leftx 0.2`, `0.5` | 0.2 inside; `0.2 / 0.7 * 127` = 36: 164 | no line; `analog 164,128` (`out/030/deadzone.log`) |

The dead zone is `input.dead_zone` (0.15) read by `pad_tuning()` on every poll, as docs/controls.md says, and an
environment override is not written back (the scratch settings.ini kept 0.15). No code change was needed.

Verify output (last 20 lines; `tools/verify_task.sh 030`, line 25 of the output is `controls_check: OK,
docs/controls.md matches the code (20 actions in two layouts, 12 gamepad buttons, 6 tuning defaults)` and
`out/030/pad.log` has `[script] frame 700: pad a` then `[pad] buttons 0x4000 analog 128,128 right 128,128` under
`[shell] metal`):
```
  0xda x1 first=0x0
  0xe2 x2 first=0x0
  0xe3 x2 first=0x0
  0xe4 x2 first=0x0
  0xe5 x2 first=0x0
  0xe6 x1 first=0x0
  0xf0 x1 first=0x0
  0xf1 x1 first=0x0
  0xf2 x1 first=0x0
  0xf3 x1 first=0x0
  0xf4 x1 first=0x0
  0xf5 x1 first=0x0
  0xf6 x1 first=0x0
  0xf7 x1 first=0x0
  0xf8 x1 first=0x0
  0xf9 x1 first=0x0
[metal] 800 frames, 6290 draws, 796 passes, 149 textures decoded, 0 framebuffer textures, 0 target copies, 0 uploads, 2 targets, 7 GPU waits (3.31288 ms) in 26.2928 s
[metal] stencil: 796 draws, 0 copies into the alpha; guest memory written/asked: transfers 0/0 (0 ms waited) read-backs 0/0 (0 ms waited) frames 797/800 (3.31288 ms waited) depths 0/0 (0 ms waited)
[run_boot] exit 0 after 26.9s, 345 lines
verify 030: PASS
```

Open questions:
- For E1 (all in docs/controls.md, "Starting points for E1"; each needs a vendor patch or a new profile field): the
  menu labels "○ (confirm)" / "× (back)", the Confirm button row ("Right, ○ (Japanese)" is the default that puts
  Wipeout's confirm, Cross, on the bottom button), its description and the `[pad] ... connected; confirm on circle`
  line are the framework's first game's, not Wipeout Pure's (Cross confirms, Triangle goes back);
  `PURE_AUTO_CONFIRM` presses Circle. The default layout gives Triangle (frontend back, reverse camera) only Mouse
  Left, so with `input.mouse=0` the keyboard cannot go back. The camera and mouse rows act on a second stick and a
  camera driver this game does not have. Gamepad buttons cannot be rebound in the menu (the game's own screen remaps
  them). One radial dead zone, no outer zone or curve.
- `docs/tracks.md` (Controls through the live file) says "O use pickup, SQ absorb pickup" from FE.wad's XML; the
  game's screen shows Use pickup on Square and Absorb pickup on Circle, which fits "Pressing Square showed no shield
  gain". Outside this task's May touch: Fable to correct.
- The 19 Downs from Confirm button to × (back) depend on the framework's row order; a menu change (E1) shifts the
  count in `out/030/rebind.txt`.
- The input script's frames count menu frames while the paused menu is open (310 in 2.9 s here), so script frames and
  game flips part after a menu visit; docs/controls.md says so. `--frames` (game flips) then cannot end such a run at a
  known script step; `out/030/rebind.txt` ends with `quit` ("Runtime stopped: window closed", run_boot exit 4).

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
