# Controls

What a player presses, taken from the code (task 030, 2026-10-06). The framework turns three sources into the one
PSP pad the game reads: the keyboard and the mouse's buttons through the player's bindings, the first SDL gamepad,
and (not under the Metal shell) the on-screen touch controls. `host/shell/sdl_pad.cpp` (`SdlPad::sample`) does it for
both windowed shells, Vulkan and Metal, so everything here holds for `PURE_SHELL=vulkan` and `PURE_SHELL=metal`
alike. The headless shell has no keyboard or gamepad: its pad comes from the input script only (last section).

The sources add up: the buttons are ORed, the stick offsets from the keys, the gamepad and the touch stick are summed
and clamped to the PSP's 0 to 255. The keyboard counts only while the window has focus (the input script's keys
count without it), the mouse's buttons only while the window holds the pointer (below), and nothing reaches the game
while the menu is open; a button still held when the menu closes stays hidden from the game until it is released.
`PURE_TRACE_PAD=1` prints `[pad] buttons 0x... analog X,Y right X,Y` whenever the pad changes.

Sources: `vendor/portablekit/host/input/bindings.hpp` and `.cpp` (the actions, both layouts, the key names, the
settings.ini format), `host/shell/gamepad.cpp` (`read_gamepad`, `pad_tuning()`), `host/shell/sdl_pad.cpp`,
`host/ui/menu.cpp` (`Menu::controls`), `host/ui/layer.cpp` (the binding capture), `host/settings/settings.cpp` and
`settings.hpp` (the keys and defaults), `host/install/user_data.cpp` (where settings.ini lives), and
`host/shell/script_steps.cpp` with `host/ui/input_script.cpp` (the input script). `tools/controls_check.py` checks the
three tables marked below against those sources (exit 1 on a difference).

## What the game expects

Wipeout Pure's own controls screen (MAIN MENU > PROFILE > OPTIONS > CONTROLS, captured in a run on 2026-10-06:
`out/030/shots/gc_controls.png`, route `out/030/game_controls.txt`) shows the defaults as Dual Airbrake, Airbrake
Left L, Airbrake Right R, Accelerate Cross, Use pickup Square, Reverse camera Triangle, Absorb pickup Circle; the
analog stick steers (the sweep steers with `axis leftx`), and the frontend's prompts are Cross to confirm and
Triangle to go back. The game remaps those six actions on that screen itself and keeps the choice in its own save,
apart from everything below.

## The keyboard: the two layouts

The default layout is the framework's (W A S D on the stick, the mouse in the other hand); the classic layout is the
keyboard-only one of its earlier versions, chosen with "Use the classic keyboard layout" at the end of the menu's
Controls tab. A key is a position on the keyboard (its USB HID usage, SDL's scancode), named as on a US keyboard
whatever the layout prints, and each action takes up to two keys or mouse buttons. The names are the ones the menu
and settings.ini use; "None" is how the menu shows an action with nothing bound. The "Menu label" column is the
framework's, written for its first game: in Wipeout Pure Cross confirms and Triangle goes back (the E1 list below).
In "PSP effect", a button is its SceCtrl bit and a stick action is the byte it sets, as `PURE_TRACE_PAD` prints it
(`analog` is the PSP's stick, `right` the second stick of the framework's HD release, which the PSP does not have;
with `input.right_stick=dpad` the camera keys press the D-pad instead and with `off` nothing).

<!-- controls_check: keyboard -->
| PSP input | `settings.ini` key | Menu label | PSP effect | Default layout | Classic layout | Wipeout Pure |
|---|---|---|---|---|---|---|
| Stick up | `input.bind.stick_up` | Move forward | analog Y 1 | W | I | |
| Stick left | `input.bind.stick_left` | Move left | analog X 1 | A | J | steer left |
| Stick down | `input.bind.stick_down` | Move back | analog Y 255 | S | K | |
| Stick right | `input.bind.stick_right` | Move right | analog X 255 | D | L | steer right |
| Triangle | `input.bind.triangle` | △ | 0x1000 | Mouse Left | S | reverse camera; back in the frontend |
| Circle | `input.bind.circle` | ○ (confirm) | 0x2000 | Mouse Right / F | X | absorb pickup |
| Cross | `input.bind.cross` | × (back) | 0x4000 | Space | Z | accelerate; confirm in the frontend |
| Square | `input.bind.square` | □ | 0x8000 | E | A | use pickup |
| L | `input.bind.l` | L | 0x0100 | Q | Q | airbrake left |
| R | `input.bind.r` | R | 0x0200 | Left Shift | W | airbrake right |
| Start | `input.bind.start` | START | 0x0008 | Enter / Tab | Enter | PRESS START on the title; skips the intro movie |
| Select | `input.bind.select` | SELECT | 0x0001 | Backspace | Right Shift / Backspace | |
| D-pad up | `input.bind.dpad_up` | D-pad up | 0x0010 | Up | Up | menu cursor |
| D-pad left | `input.bind.dpad_left` | D-pad left | 0x0080 | Left | Left | |
| D-pad down | `input.bind.dpad_down` | D-pad down | 0x0040 | Down | Down | menu cursor |
| D-pad right | `input.bind.dpad_right` | D-pad right | 0x0020 | Right | Right | |
| Second stick up | `input.bind.camera_up` | Camera up | right Y 1 | I | None | (no second stick on the PSP) |
| Second stick left | `input.bind.camera_left` | Camera left | right X 1 | J | None | |
| Second stick down | `input.bind.camera_down` | Camera down | right Y 255 | K | None | |
| Second stick right | `input.bind.camera_right` | Camera right | right X 255 | L | None | |

The Wipeout Pure column holds only what a run showed: the game's controls screen, the frontend's prompts, and the
routes in `config/pad_scripts/` (Start at the title and over the intro movie, `dpdown` and `dpup` in the menus, the
sweep's steering). A key the stick actions press pushes the stick fully (127 from the centre); two opposite keys
cancel out. Outside the bindings, Esc opens the menu and F3 toggles the performance overlay (in both shells, the
Metal shell's since task 090); neither can be bound. In a traced run (`PURE_TRACE_AUDIO=1` or `PURE_PERF=log`) F8,
or one stick clicked alone, prints a `[mark] N` line into the log in step with the trace lines (patch
0032-trace-marks, task 502: a listener marks a hiccup as it is heard; `tools/audio_hiccups.py` shows the marks beside
the sound's events); an untraced run prints nothing, and F8 still reaches the game if it is bound.

## The mouse

The mouse's buttons are bindable like keys (Mouse Left, Mouse Middle, Mouse Right, Mouse 4, Mouse 5); by default
Mouse Left is Triangle and Mouse Right is Circle. They reach the game only while the window holds the pointer:
`input.mouse=1` (on by default on the desktop; settings.ini only since task 064, the menu's Mouse row is hidden), the
window focused, and no menu or setup screen open. Esc opens the menu and frees the pointer; closing it captures the
pointer again. So with the mouse off, or the pointer free, the default layout has no Triangle at all.

Mouse motion does nothing in Wipeout Pure. The framework turns it into a camera turn only through a game's camera
driver (`GameProfile::camera`), and our profile has none; the sensitivity and invert rows are for such games, and
the menu leaves them out here ("Rows the menu leaves out" below).

## The gamepad

The first gamepad SDL recognises drives the pad (a second one is ignored; when the first is unplugged the next one
still connected takes over; a joystick without an entry in SDL's mapping database is reported as `[pad] NAME has no
gamepad mapping, ignored`). The input script's virtual gamepad ("PortableKit input script") takes over from a real
one, so a controller within reach does not disturb a scripted run. The mapping is positional: the face buttons go by
where they sit, so on a PlayStation pad each button is itself and on an Xbox pad A is Cross. Gamepad buttons cannot
be rebound in the menu (a gamepad button cancels a binding capture); the game's own controls screen remaps them.

<!-- controls_check: gamepad -->
| SDL button (`pad NAME`) | Xbox / PlayStation | PSP, `input.confirm=east` (the default) | PSP, `input.confirm=south` |
|---|---|---|---|
| `a` | A / Cross | Cross 0x4000 | Circle 0x2000 |
| `b` | B / Circle | Circle 0x2000 | Cross 0x4000 |
| `x` | X / Square | Square 0x8000 | Square 0x8000 |
| `y` | Y / Triangle | Triangle 0x1000 | Triangle 0x1000 |
| `back` | View / Create (Select, Share) | Select 0x0001 | Select 0x0001 |
| `start` | Menu / Options (Start) | Start 0x0008 | Start 0x0008 |
| `leftshoulder` | LB / L1 | L 0x0100 | L 0x0100 |
| `rightshoulder` | RB / R1 | R 0x0200 | R 0x0200 |
| `dpup` | D-pad up | D-pad up 0x0010 | D-pad up 0x0010 |
| `dpdown` | D-pad down | D-pad down 0x0040 | D-pad down 0x0040 |
| `dpleft` | D-pad left | D-pad left 0x0080 | D-pad left 0x0080 |
| `dpright` | D-pad right | D-pad right 0x0020 | D-pad right 0x0020 |

`input.confirm=south` (the menu's Confirm button set to "Bottom (Western)") swaps South and East so that a game that
confirms with Circle confirms with the bottom button. Wipeout Pure confirms with Cross, so the default `east` (shown in
the menu as "Right, ○ (Japanese)") is the one that puts its confirm on the bottom button. `guide`, `leftstick`,
`rightstick`, the paddles, `touchpad` and the `misc` buttons press nothing; `leftstick` and `rightstick` together
(L3+R3) open the menu, as Esc does.

| SDL axis (`axis NAME VALUE`) | Xbox / PlayStation | PSP |
|---|---|---|
| `leftx`, `lefty` | left stick | the analog stick (`analog X,Y`), through the dead zone below |
| `lefttrigger` | LT / L2 | L (0x0100) once past the trigger point, ORed with the left shoulder |
| `righttrigger` | RT / R2 | R (0x0200) once past the trigger point, ORed with the right shoulder |
| `rightx`, `righty` | right stick | by `input.right_stick`: `camera` (default) the second stick bytes (`right X,Y`, the same dead zone; bytes 10 and 11 of each SceCtrlData, reserved on a PSP), `dpad` the D-pad bits once past `input.right_stick_zone`, `off` nothing |

The dead zone is radial and the live range is rescaled, so leaving it does not jump: with `x`, `y` the stick's
position (-1 to 1 each), `length = sqrt(x*x + y*y)`; at or below `input.dead_zone` the stick is centred (0x80),
above it each axis is `clamp(0x80 + int(v * s * 127), 0, 255)` with `s = min((length - dead_zone) / (1 - dead_zone),
1) / length`. The triggers are a threshold, since the PSP's L and R are digital: a trigger past `input.trigger` (0 to
1 of its travel) presses the bit. Trigger profiles (other buttons on the triggers) exist only for a game that defines
them; ours defines none, so `input.trigger_profile` stays `standard`. Measured under the Metal shell with the
default tuning (task 030): left stick x 0.1 stays 128 (inside the dead zone), 0.2 gives 135, 0.5 gives 180, 1 gives
255 and -1 gives 1; x and y both 0.7 give 216,216.

<!-- controls_check: tuning -->
| `settings.ini` key | Default | Range | Menu row (Controls tab) | Environment override |
|---|---|---|---|---|
| `input.dead_zone` | 0.15 | 0 to 0.9 (the menu's slider: 0 to 50%) | Stick dead zone | `PURE_PAD_DEADZONE=0.2` |
| `input.trigger` | 0.25 | 0.05 to 1 | Trigger point | `PURE_PAD_TRIGGER=0.5` |
| `input.right_stick` | camera | camera, dpad, off | Right stick | `PURE_PAD_RSTICK_DPAD=1` (any value but 0, no, off, false: dpad) |
| `input.right_stick_zone` | 0.50 | 0.1 to 1 | Right stick D-pad point | `PURE_PAD_RSTICK_ZONE=0.6` |
| `input.confirm` | east | east, south | Confirm button | `PURE_PAD_FACE=south` (`south` or `xbox`: south, anything else east) |
| `input.mouse` | 1 | 0, 1 | none here (Mouse, for a game with a mouse camera: "Rows the menu leaves out") | `PURE_MOUSE=0` |

`pad_tuning()` reads these from the settings on every poll, so a change in the menu applies at once. An environment
override wins for the run only: it is not written back, and the menu shows the row it decides disabled, with "Set by
PURE_..." beside it.

## Rebinding

### In the menu

1. Esc (or L3+R3 on a gamepad) opens the menu over the game. The game pauses while it is open (`ui.menu_pause=1`,
   the System tab's "Pause the game when the menu opens").
2. Q and W (L1 and R1) switch sections: Video, Audio, Controls, System (no Network since task 064). W twice from
   Video is Controls.
3. Up and Down move between rows, Enter selects, Left and Right change a value, Esc goes back and, with nothing being
   edited, closes the menu. The Controls tab holds, in order: the Gamepad section (Connected, Confirm button, Stick
   dead zone, Trigger point, Right stick with D-pad and Off, Right stick D-pad point), the Pilot name section (when
   the game asks for a name, the name), Keyboard and mouse (one row per action in the order of the table above, the
   Esc line and the F3 line), "Restore control defaults", under the Vulkan shell the Touch
   screen section, and "Use the classic keyboard layout". Disabled rows still take the focus: from Confirm button,
   the first row focused, it is 7 Downs to Move forward and 13 to × (back).
4. Enter on an action's row: its value reads "Press a key or a mouse button". The next key or mouse button pressed
   is added to the action; if the action has it already, it is removed instead. An action holds two; a third
   replaces the second. A key another action had is taken from it. Esc cancels, and so does any gamepad button.
5. The change is saved to settings.ini at once and applies to the game when the menu closes. "Restore control
   defaults" puts every binding and every row of the tab back (rows an environment variable decides excepted).

The Video tab ends with a Game section (since task 070, patch 0019-game-option-rows: the options our profile lists in
`GameProfile::options`, `src/profile/enhancements.cpp`). It holds five rows. 30 fps modes (since task 072): 60 fps (the
default) runs Time Trial, Free Play and Zone at the display's rate, as Single Race and Tournament already run;
Original keeps them at 30 fps, as the PSP does (E4, D-017; docs/timing.md, "E4"). The menus run at 30 fps either way.
(The row is not called Frame rate: under the Vulkan shell that is the renderer's frame-rate cap, higher up.) Flashes:
Smooth (the default) keeps the race's frame rate through the full-screen flashes (the race-start fade, a weapon going
off near the ship, the ship put back on the track), Original halves it while they play, as the PSP does (E6, D-016;
docs/timing.md, "E6"). Text and sprites (since task 073): Upscaled has the Metal backend redraw the
menus' text and art and the race HUD, small bitmaps on the PSP, four times finer with smooth edges; Original draws the
PSP's texels and is the default since 2026-10-12 (E7, D-018 as amended; docs/metal-backend.md, "Sprite upscale"). Under the Vulkan renderer the row is shown and does
nothing until a texture pack exists, as its help says. Texture detail (since task 075): Enhanced (the default) has
the renderer draw the mipmapped textures, the track ahead, the walls, the scenery and the ships, at the level of
detail for the pixels drawn rather than the PSP's 480x272, and angled surfaces anisotropically; the difference shows
above Resolution x1. Original picks the level as the PSP does (E5, D-019; docs/metal-backend.md, "Texture detail"). Both
renderers draw it, the Metal backend since task 075 and the Vulkan renderer since task 076 (patch
0020-vulkan-texture-detail), as its help says. Display rate (since task 089): Display (the default) runs the race's
vblank at the display's refresh when that is above 60 Hz, so on a 120 Hz display Single Race and Tournament draw 120
frames a second, and Time Trial, Free Play and Zone 120 with the 30 fps modes row at 60 fps or 60 at Original. The
race runs a fraction under the display's rate (0.5%: 119.4 on a 120 Hz display, since task 091) so that a frame
that misses the display's refresh can be won back and the sound stays continuous; the help says so. The menus keep
the PSP's pace, and on a 60 Hz display nothing changes. Original keeps the PSP's 59.94 Hz everywhere (E8,
D-022; docs/timing.md, "E8"). "Restore video defaults" puts all five back to their defaults; `PURE_SIXTY_FPS`,
`PURE_SMOOTH_FLASHES`, `PURE_SPRITE_UPSCALE`, `PURE_TEXTURE_DETAIL` and `PURE_DISPLAY_RATE` lock them for a run ("Set
by PURE_SIXTY_FPS"), as every tool run does.

The System tab holds, in order: the Game section (Resume, Pause the game when the menu opens, Open the data folder,
Set up game data again…, Quit game), Saves (Import save…, Export save…, Back up saves…, Open the saves folder, Open the
backups folder), Download packs (since task 078, patch 0021-content-packs: the section our profile names for its content
packs; docs/dlc.md, "In the menu (task 078)") and About. Download packs has a "Download packs" row, "N of 12
installed" (a pack counts when its folder on the memory stick holds a PARAM.SFO), a row for each of the twelve US
packs with its title and "Installed" or "Not installed", and "Install download packs…", which opens Import save…'s
file browser: open a pack's folder, or a folder holding the packs (or its SAVEDATA or PSP/SAVEDATA) and "Import from
this folder", then "Import these saves". The rows take the focus, so from Resume it is 23 Downs to Install download
packs…. Export save… and Back up saves… leave the packs out.

Checked under the Metal shell on 2026-10-06 (task 030): Cross rebound to Space / X from the menu, X then confirmed
the game's language screen (`[pad] buttons 0x4000`), and settings.ini held `input.bind.cross=Space / X` until the
second edit removed X again.

### Rows the menu leaves out

Since task 064 (D-014, patch 0016-menu-rows-by-capability) the menu draws a row only when its feature exists, as the
game's profile (`GameProfile::features`) and the shell (`Shell::supports_*`) say. Our profile has no right-stick
camera, so the Right stick row offers D-pad and Off only (the default `input.right_stick=camera` shows as Off: it
sends the stick to the two bytes after the PSP's own, which the game never reads) and the two camera invert rows are
gone; no mouse camera, so Mouse, Mouse sensitivity and the two mouse invert rows are gone (the pointer is still
captured by `input.mouse`, and the mouse's buttons bind as before); no ad hoc play, so the Network tab and the System
tab's "Pause during multiplayer" are gone and opening the menu turns `network.adhoc` off. The Metal shell has no
touch controls, so the Touch screen section is gone there (the Vulkan shell keeps it). Since task 100 the Metal
backend draws texture packs, so the Texture pack row, Import texture pack… and Open the textures folder are in both
shells (patch 0034-texture-pack-host); the Texture filter row, the Vulkan renderer's sampler, is still the Vulkan
shell's alone. Since task 090 the Metal shell
draws the performance overlay, so the Video tab's Performance row and the Controls tab's F3 line are in both shells
(before, the Metal shell left them out). The Video tab's Aspect ratio row offers Original, Stretch and Fill in both shells: Fill needs a game
that widens its own view, which this one does since task 084 (D-020), and the Metal shell draws it since task 086
(before, it left Fill out). A hidden row keeps its settings.ini key and value; "Restore control defaults" still puts the hidden
rows' settings back too. `tools/menu_check.sh` checks the lists (docs/verification.md).

### In settings.ini

The file is `~/Library/Application Support/pure-recomp/PureNative/settings.ini` on macOS (SDL's preference folder for
the organisation `pure-recomp` and the application `PureNative`, from our profile); `PURE_DATA_DIR=DIR` puts it in
`DIR` instead (the tests use a scratch folder that way). It is `key=value` lines, `#` starts a comment, and the game
writes the whole file back, sorted, whenever a menu row changes, keeping keys it does not know. Edit it while the game
is not running.

A binding is `input.bind.<action>=NAME` or `input.bind.<action>=NAME / NAME`, the action keys as in the table above
(`input.bind.cross=Space / X`). An empty value means none. Names ignore case; besides the menu's names, SDL's
`Return` and `Escape` are read as Enter and Esc, and `Key N` is the key at HID position N for a key with no name. A
line with a name that is not known, or with more than two, is ignored with `[settings] ignoring KEY=VALUE` and the
default stays. The names:

- Letters `A` to `Z`, digits `0` to `9`, `Enter`, `Esc`, `Backspace`, `Tab`, `Space`, `CapsLock`
- `-` `=` `[` `]` `\` `#` `;` `'` `` ` `` `,` `.` `/` (a lone `/` is the slash key; the separator is ` / ` with spaces)
- `F1` to `F12`, `PrintScreen`, `ScrollLock`, `Pause`, `Insert`, `Home`, `PageUp`, `Delete`, `End`, `PageDown`
- `Right`, `Left`, `Down`, `Up` (the arrow keys)
- `Numlock`, `Keypad Divide`, `Keypad Multiply`, `Keypad Minus`, `Keypad Plus`, `Keypad Enter`, `Keypad 0` to
  `Keypad 9`, `Keypad Period`, `NonUSBackslash`
- `Left Ctrl`, `Left Shift`, `Left Alt`, `Left GUI`, `Right Ctrl`, `Right Shift`, `Right Alt`, `Right GUI` (GUI is
  Command on a Mac)
- `Mouse Left`, `Mouse Middle`, `Mouse Right`, `Mouse 4`, `Mouse 5`

The other input keys are those of the tuning table, `input.trigger_profile` (`standard`), the mouse's
`input.mouse_sensitivity`, `input.invert_mouse_x`, `input.invert_mouse_y`, the camera's `input.invert_camera_x`,
`input.invert_camera_y`, `input.analog_camera`, `input.camera_speed`, `input.aim_speed` (no effect without a camera
driver), the name's `input.name_entry` and `input.name`, and the touch controls' `input.touch_*`.

The game's own options are `game.<key>=<index>`, the index of the row's choice: `game.sixty_fps=1` (30 fps modes:
60 fps, the default) or `0` (Original), `game.smooth_flashes=1` (Flashes: Smooth, the default) or `0` (Original),
`game.sprite_upscale=1` (Text and sprites: Upscaled) or `0` (Original, the default since 2026-10-12), and
`game.texture_detail=1` (Texture detail: Enhanced, the default) or `0` (Original), and `game.display_rate=1`
(Display rate: Display, the default) or `0` (Original).
An index out of range is ignored with `[settings] ignoring KEY=VALUE` and reads as the default, and a `game.` key
this port has no option for is dropped when the file is next written.

## The input script's names (for tests)

`PURE_INPUT_SCRIPT="FRAME:ACTION ARGUMENT;..."` (or `tools/run_boot.py --script FILE`, one step a line) and the live
file `PURE_INPUT_LIVE=FILE` (lines appended while the game runs; their frames count from when they are read, every
10 frames). One script frame per game flip while the game runs; while the paused menu is open the game's flips stop
and the script counts the menu's frames instead (at most 120 a second: 310 in 2.9 s in task 030's run), so steps
after a menu visit land later in game frames than their numbers say.

| Step | Names | Notes |
|---|---|---|
| `pad NAME[+NAME...] [N]` | SDL's: `a` `b` `x` `y` `back` `guide` `start` `leftstick` `rightstick` `leftshoulder` `rightshoulder` `dpup` `dpdown` `dpleft` `dpright` `misc1` `paddle1` to `paddle4` `touchpad` `misc2` to `misc6` | the virtual gamepad, held N frames (4 by default); the PSP buttons as in the gamepad table: `pad a` is Cross, `pad back` is Select (`pad select` is `[script] unknown button select`) |
| `axis NAME VALUE` | `leftx` `lefty` `rightx` `righty` `lefttrigger` `righttrigger` | held at VALUE (-1 to 1) until the next step on that axis. A trigger reads 0 until set, then SDL maps the full range onto its travel: `axis lefttrigger 0` is half pressed (L held, past 0.25), release it with `axis lefttrigger -1` |
| `key NAME [N]` | SDL's key names: `Escape`, `Return`, `Space`, `Tab`, `Backspace`, `Up`, `Down`, `Left`, `Right`, `Left Shift`, letters (`X`, `Q`, `W`) | held N frames (4 by default); reaches the menu as a key event and the game through the bindings, also with the window in the background. Note `Escape` and `Return`, where the menu and settings.ini say Esc and Enter |
| `click BUTTON [N]`, `mouse DX DY` | `left` `middle` `right` `x1` `x2`; counts | a script with mouse steps counts the pointer as captured without taking the real one |
| `text STRING`, `drop PATH`, `shot NAME`, `quit` | | `shot` writes `PURE_SCREENSHOT_DIR/NAME.bmp` (the window, menu included, under the windowed shells) |

`key`, `mouse`, `click`, `text` and `drop` need a window (`PURE_SHELL=vulkan` or `metal`); the headless shell runs
`pad`, `axis`, `shot` and `quit` and reports the others once. A script without a `pad` or `axis` step, and without
a live file, attaches no virtual gamepad, so a real one stays in charge.

## Starting points for E1 (rebinding and dead zones)

Found while writing this (task 030); none is fixed here, and each one but the last is a framework change (vendor
patch) or a profile field.

- The menu's labels "○ (confirm)" and "× (back)", the Confirm button row ("Right, ○ (Japanese)" for the default),
  its description ("The game's prompts show ○ to confirm and × to go back") and the `[pad] ... connected; confirm on
  circle` line describe the framework's first game. Wipeout Pure confirms with Cross and goes back with Triangle. A
  per-game label set in `GameProfile` would fix all four. `PURE_AUTO_CONFIRM` presses Circle for the same reason,
  which is not Wipeout's confirm.
- Triangle (back in the frontend, reverse camera in a race) has only Mouse Left in the default layout, so it needs
  the mouse captured; with `input.mouse=0` the keyboard cannot go back. A Pure default layout (a profile field the
  framework does not have yet) could put Triangle, and the whole race set, on keys.
- The camera rows (Right stick camera mode, both invert rows, the camera keys I J K L) act on a second stick the PSP
  does not have, and the mouse rows on a camera driver our profile does not set. Task 064 hid the rows ("Rows the
  menu leaves out"); the camera keys' bindings remain, and press the D-pad with `input.right_stick=dpad`.
- Gamepad buttons are fixed (positional); the game's own controls screen covers remapping the PSP buttons.
- The dead zone is radial on both sticks with one value; there is no outer dead zone, response curve or per-axis
  dead zone, and the triggers are a single threshold. The sweep's steering through `axis leftx` passes through this
  dead zone too.
- `docs/tracks.md` ("Controls through the live file") lists "O use pickup, SQ absorb pickup" from FE.wad's XML; the
  game's screen shows Use pickup on Square and Absorb pickup on Circle, which is also why pressing Square there showed
  no shield gain.
