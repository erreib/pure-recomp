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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
