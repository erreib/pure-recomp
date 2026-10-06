# Tracks

The track menus as the port shows them on a new profile (2026-10-05), and how `tools/campaign_sweep.py` reaches
each track. Only the Alpha league is open on a new profile.

## Single Race, Vector class, Alpha league

Route: `config/pad_scripts/main_menu.txt` (cold boot to MAIN MENU) then `config/pad_scripts/single_race.txt`
(SINGLE PLAYER, SINGLE RACE, VECTOR, ALPHA, the track, FEISAR). TRACK SELECTION is up from about flip 5350 and
the track is confirmed at 5500; the sweep picks the Nth track with N DOWN presses at 5380, 5410, 5440 (30 flips
apart; each press is held 4 frames). In PPSSPP (`tools/pp_lines.py --downs N`) the presses go at vblank 6400,
6430, 6460 and the track is confirmed at 6500. The list order, top to bottom:

| DOWN presses | Track | Sweep name | Length (menu) | Distance wraps at | Grid (player) | Start line | Steering table |
|---|---|---|---|---|---|---|---|
| 0 | Vineta K | `vineta_k` | 4446 m | about 4437 m | 1079 m | about 1233 m | `config/pad_scripts/drive/vineta_k.txt` |
| 1 | Modesto Heights | `modesto_heights` | 4576 m | about 4465 m | 652 m | about 803 m | `config/pad_scripts/drive/modesto_heights.txt` |
| 2 | Chenghou Project | `chenghou_project` | 4866 m | about 4963 m | 1121 m | about 1272 m | `config/pad_scripts/drive/chenghou_project.txt` |
| 3 | Blue Ridge | `blue_ridge` | 4780 m | about 4666 m | 229 m | about 375 m | `config/pad_scripts/drive/blue_ridge.txt` |

The wrap, grid and start-line columns come from the AI ships' race records in PPSSPP (`out/lines/<track>.csv`,
recorded 2026-10-05 with `tools/pp_lines.py TRACK --downs N`): the grid is the player's (8th) slot, the AI
ships stand about 19.5 m apart ahead of it, and the start line is where their lap field turns from 0 to 1. The
length is the TRACK SELECTION panel's (the sweep's `<cell>-menu` shot).

## The ship probe on a track

`PURE_WATCH_SHIP=1` prints the player's race record each flip (task 007). What its fields mean on a race,
from the PPSSPP recordings of all eight records and the port's three-lap run (2026-10-05):

- `dist` is a track coordinate, not a lap distance. It wraps to 0 once a lap, at a point that is not the start
  line (the table above).
- `clock` is the lap clock. It starts at GO and runs on through the first crossing of the start line (the ship
  starts behind it), then restarts at 0 at every later crossing. The HUD's lap times are these values: the
  port's run read 59.59, 53.54 and 59.16 s on the results panel, and the probe saw the clock drop back from 59.6,
  53.5 and 59.2.
- `lap` is 0 on the grid and 1 from the first crossing, and stays 1: it is not a lap counter. Once the race is
  over, bit 16 is set as well (65537 from the finish line on). PPSSPP reads taken while the CPU runs sometimes
  catch 257 for a frame.
- `shield` (task 017) is not in the race record: it is the ship object's float at `be::Ship` +0xF8, 100.000 on the
  grid for the Feisar (the ship type's maximum, `*(*(ship + 0xC8) + 0x74) + 0x84`). Every wall or ship contact
  lowers it (Vineta K, 2026-10-05: 100 to 77.4 over the first 11 contacts, about 2 a contact); at 0 or below the
  ship is destroyed.

A race of N laps is therefore over at the Nth restart of the lap clock, which is what the sweep counts.

## After the finish

The game takes the ship over (autopilot, about 360 km/h, close to the AI line) and the race clock goes on. About
4 s after the line a results panel comes up over a moving replay of the race: the place ("BAD LUCK... 8TH"), the
three lap times, TOTAL, and ENTER TAG (a new profile sets the lap and race records, LR and RR). The screen is
never still, so the sweep watches the panel's TOTAL label (480x272 pixels 18,138 to 58,150): drawn and unchanged
in two shots in a row, 30 flips apart. The shots start at the finish line; the race HUD is gone within 2 s.

## Steering tables

`config/pad_scripts/drive/<track>.txt` can hold `FRAME:ACTION` input-script steps, `@DIST:ACTION` steps that the
sweep sends through `PURE_INPUT_LIVE` as the ship passes DIST on every lap, and `follow LINE WN PREVIEW
[KEY=VALUE ...]`, which makes the sweep steer closed loop along a racing line
(`config/pad_scripts/drive/<track>.line.csv`, `dist,x,z`; the options are documented in the sweep's class
`Tuner`).

Open-loop tables do not hold a race (task 012):
- Frame-keyed: GO moves by about 6 flips between runs (task 007), and every wall contact shifts the rest of the
  race.
- Distance-keyed: the second lap of a `--tune` run on Vineta K (53.5 s, 1825 steps) replayed open loop drifted
  15 to 25 m off the line within 20 s, spun the ship round at about 2440 m and was still on lap 1 after 101 s.

So the committed tables are `follow` lines. Making one for a new track: `tools/pp_lines.py TRACK --downs N`
(3.5 min), `tools/campaign_sweep.py single_race TRACK --export-line config/pad_scripts/drive/TRACK.line.csv`, and
a `follow` line in `config/pad_scripts/drive/TRACK.txt`.

### What the follower has to work with (Vineta K, task 016, 2026-10-05)

- **The stick's dead zone.** Binned over a three-lap run, the velocity heading turns at about 0 rad/s for |lx| up
  to 0.3, then about 1.15 * (|lx| - 0.3) rad/s, about 0.8 rad/s at full lock: the host's 15% dead zone
  (rescaled) plus the game's own. Task 012's loop sat inside it whenever the offset was under about 20 m, so the
  ship ran 10 to 13 m off the line for seconds at a time (71% of the race more than 10 m off). `Tuner.stick()`
  now maps the loop's demand through it.
- **The lag.** Fitted to a run with the mapping: about 0.3 s from the step being written to the heading starting
  to move (the live file is read every 10 flips) and a 0.5 s first-order lag after it, about 0.8 s in all. With
  the mapping, wn 1.0 / preview 0.3 swung 15 to 20 m either side of the line and wn 1.3 / preview 0.5 went lock
  to lock. wn 0.8 / preview 0.8 is the calmest setting tried: the mean offset is 8.7 m, 38% of the race more
  than 10 m off.
- **Speed pads.** The ship reaches 400 to 460 km/h on the pads (the AI ships race at 270 to 340 km/h), and most
  run met the left barrier at 2410 to 2450 m after the pad at about 2100 m, losing 190 to 380 km/h.
- **Controls through the live file.** The game's default controls (FE.wad): X accelerate, O use pickup, SQ absorb
  pickup, L1/R1 airbrakes, triangle reverse camera. The analog triggers press L and R, but `axis lefttrigger 0`
  leaves the trigger pressed: release with `axis lefttrigger -1`. A `pad a 1` (to lift Cross) and a `pad a N`
  (to hold it again) read in the same 10-flip batch run in the same frame, and the 1-frame release then lifts
  Cross for good: the hold has to go a couple of frames later (`2:pad a N`). Both mistakes looked like a ship
  slowing to a 10 km/h crawl, or a stop, "with Cross held".

Contacts (the sweep's rule: the speed down by 20 km/h within 0.25 s) stayed at 11 to 18 a lap on Vineta K with
every setting tried, and about 20 a lap on the other three tracks; the brief's target of under 10 was not
reached. The shield falls about 1.7% a contact, so Vineta K's 37 to 47 contacts a race leave the ship alive and
the other tracks destroy it in lap 2 or 3. Pressing Square ("Absorb pickup") showed no shield gain. A 250 km/h
cap (`vmax`) did not lower the drain, and on Blue Ridge the capped ship fell at about 2360 m (a jump) and the game
put it back at about 1960 m, three times in a row: the track coordinate jumps back with it, which the stall rule
sees as no progress. The full list of runs is in `docs/tasks/016-sweep-reliability.md`.

## Stalls

The sweep takes a `stall` shot before it closes the window and classifies the stall (`classify_stall`):

| Class | Seen | What it looks like |
|---|---|---|
| eliminated by damage | Chenghou Project, Modesto Heights and Blue Ridge, in lap 2 or 3, after 40 to 67 contacts | "SHIP DESTROYED" panel with the lap times; the HUD and its shield bar are gone (reads 0%); the ship at rest. The sweep decides it from the stall shot's title (`DESTROYED_TITLE`) or the probe's shield at 0 or below |
| stuck on geometry | Vineta K at 1914 m (no `recover`) | the ship nosed into a barrier, Cross held, engine lit, at rest or crawling; the shield bar mostly full |
| off the line | | more than 25 m from the line or moving more than 90 degrees off it |
| stopped | | no contact since the last progress (task 012's lap-3 stop at 4437 m, speed run down over 6 s with no impact, fits a destroyed ship) |

The shield bar reads 0% whenever the HUD is hidden, so it only goes into the detail; the class comes from the
title and the probe. The "SHIP DESTROYED" panel comes up about 5 s after the ship is destroyed, in the place of the
results panel's "BAD LUCK... 8TH", with LAP 1-3 and PRESS X TO CONTINUE: `TITLE_REGION` and `DESTROYED_TITLE` in
the sweep are its title's lit columns, taken from a Vineta K run on a local build that held the shield at 1 (the
first wall, at 6.2 s, destroyed the ship; task 017).

## The shield

The shield (energy) bar is the HUD's cyan bar under the speed bar, bottom right; the sweep reads its fill from a
shot (`SHIELD_BAR`). The value behind it is the ship object's float at `be::Ship` +0xF8 (task 017), not a field of
the race records (task 016 looked there with `tools/pp_lines.py --dump` and found none). In the code:

| Function | What it does with the shield |
|---|---|
| FUN_0892478c | reads +0xF8 (in the modes below 9 of `DAT_08b173e4`; the network modes keep it in a net record) |
| FUN_089247dc | writes +0xF8, clamped to the ship type's maximum `*(*(ship + 0xC8) + 0x74) + 0x84`; for the player it also updates the HUD's `~CRAFTCRITICAL` warning (FUN_0881e944, under 20 and 10) |
| FUN_08928274 | the damage: lowers the shield by the amount (halved in some modes), plays `energycritical` when it falls through 20, and at 0 or below puts the ship in state 4, destroyed (FUN_08928824); for the player it adds the amount to the race stats at `DAT_08b17794` +0x84, +0x88 or +0x8c by kind (the stats that FUN_0895a244 reports as `TotalWeaponDamage`, `TotalWallCollisionDamage`, `TotalShipCollisionDamage`) |
| FUN_08926ae4 | the ship's update: a wall or ship contact calls the damage with `impact * 0.05 * 0.7` |
| FUN_08923b78, FUN_08923b9c | refill to the maximum; add (absorbing a pickup, `TotalEnergyAbsorbed`) |
| FUN_0892195c (Player.cpp) | copies the shield and its maximum into the player's HUD data each frame |
| FUN_0881ebd8 (HUD.cpp) | the bar (`Shield3D`): eases towards shield / maximum; red and blinking under 20 |

`PURE_WATCH_SHIP=1` prints it as `shield=` and `PURE_TEST_NO_DAMAGE=1` (a test switch, `README.md`) refills it
every flip; a local build that wrote 1 instead destroyed the ship at its first wall, which is what showed the
field is the shield and not a copy.

## No-damage runs (task 017)

The follower takes about 20 contacts a lap on Modesto Heights, Chenghou Project and Blue Ridge, which runs the
shield out in lap 2 or 3. The sweep's job there is to reach the results screen and see whether anything halts, so
`tools/campaign_sweep.py ... --no-damage` sets `PURE_TEST_NO_DAMAGE=1` and the summary marks the row
`(no damage)`. Vineta K passes without it (task 016). Each track has its own budget in `MODES` (`frames`): 13000
flips for Vineta K, 17000 for the other three, whose laps take the follower 75 to 95 s.

The runs of 2026-10-05/06 (the committed steering tables; the summary's damage figure is the shield the frames
took, which the switch put back):

| Cell | Switch | Outcome | Laps (s) | Contacts (a lap) | Shield taken | Flips (budget ends at) |
|---|---|---|---|---|---|---|
| modesto_heights | no damage | PASS | 94.3, 83.8, 86.5 | 73 (25, 21, 27) | 135 | 22380 (23100) |
| chenghou_project | no damage | PASS | 89.1, 87.2, 83.2 | 72 (24, 25, 23) | 150 | 22020 (23100) |
| blue_ridge | no damage | PASS | 86.4, 89.8, 88.0 | 61 (19, 20, 22) | 126 | 22360 (23100) |
| vineta_k | off | PASS | 63.4, 59.6, 63.8 | 42 (15, 11, 16) | 87 (13 left) | 17830 (19100) |
| modesto_heights | off (`--out out/017/damage`) | STALL: eliminated by damage ("SHIP DESTROYED" title, probe shield -0.4), destroyed at 179.9 s, 453 m into lap 2 | 93.4, then 86.5 into lap 2 | 60 (27, 33) | 100 (62.4 left after lap 1) | 18200 (23100) |

No cell halted: no `[hle-stub]`, unsupported instruction or runtime stop other than the sweep's own quit. A
contact costs about 2 shield (1.7 to 2.1 a contact over these runs; one frame of a wall contact took at most 4.7),
so a race of more than about 50 contacts ends in "SHIP DESTROYED"; Vineta K's pass leaves only 13. On Chenghou
Project the game put the ship back twice, at 46.5 s (3965 m to 3755 m) and at 154.2 s (128 m to 4663 m), each
time while it was going backwards along the track, and two frames before each took 8 and then 13 at once.
