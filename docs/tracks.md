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
| 1 | Modesto Heights | `modesto_heights` | | about 4465 m | 652 m | about 803 m | `config/pad_scripts/drive/modesto_heights.txt` |
| 2 | Chenghou Project | `chenghou_project` | | | | | `config/pad_scripts/drive/chenghou_project.txt` |
| 3 | Blue Ridge | `blue_ridge` | | | | | `config/pad_scripts/drive/blue_ridge.txt` |

The wrap and start-line columns come from the AI ships' race records in PPSSPP (`out/lines/<track>.csv`).

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

A race of N laps is therefore over at the Nth restart of the lap clock, which is what the sweep counts.

## After the finish

The game takes the ship over (autopilot, about 360 km/h, close to the AI line) and the race clock goes on. About
4 s after the line a results panel comes up over a moving replay of the race: the place ("BAD LUCK... 8TH"), the
three lap times, TOTAL, and ENTER TAG (a new profile sets the lap and race records, LR and RR). The screen is
never still, so the sweep watches the panel's TOTAL label (480x272 pixels 18,138 to 58,150): drawn and unchanged
in two shots in a row, 30 flips apart. The shots start at the finish line; the race HUD is gone within 2 s.

## Steering tables

`config/pad_scripts/drive/<track>.txt` can hold `FRAME:ACTION` input-script steps, `@DIST:ACTION` steps that the
sweep sends through `PURE_INPUT_LIVE` as the ship passes DIST on every lap, and `follow LINE WN PREVIEW`, which
makes the sweep steer closed loop along a racing line (`config/pad_scripts/drive/<track>.line.csv`, `dist,x,z`).

Open-loop tables do not hold a race:
- Frame-keyed: GO moves by about 6 flips between runs (task 007), and every wall contact shifts the rest of the
  race.
- Distance-keyed: `tools/campaign_sweep.py MODE TRACK --tune` steers closed loop along an AI racing line from
  `tools/pp_lines.py TRACK [--downs N]` and writes the second lap's steps to `out/sweep/<mode>-<track>.tuned.txt`.
  On Vineta K that lap (53.5 s, 1825 steps) replayed open loop drifted 15 to 25 m off the line within 20 s, spun
  the ship round at about 2440 m and was still on lap 1 after 101 s. Wall contacts and the other ships make each
  run's path different, and nothing pulls an open-loop ship back.

So the committed tables are `follow` lines. They do not make a race certain yet. Two sweep runs of Vineta K on
2026-10-05: one PASS (laps 64.2, 59.4, 58.0 s, 30 wall contacts), one STALL on lap 3. There, after 28
contacts, the speed ran down from 290 km/h at 4260 m to 0 at 4437 m over 6 s without an impact, and the ship sat
there with Cross held; a ship destroyed by wall damage is the suspect (no shot was taken). Fewer contacts need a
better tracker: most happen 12 to 20 m off the line after a corner was run wide, where the line needs only 0.3 to
0.5 rad/s, and the rest where it needs about 1 rad/s, the most full lock gives (airbrakes are not used).

Making a table for a new track: `tools/pp_lines.py TRACK --downs N`
(3.5 min), `tools/campaign_sweep.py single_race TRACK --export-line config/pad_scripts/drive/TRACK.line.csv`, and
a `follow` line in `config/pad_scripts/drive/TRACK.txt`.

Measured on Vineta K (2026-10-05): lx held at full lock turns the velocity heading at about 1 rad/s from
150 km/h up, and the heading answers 0.2 to 0.5 s after the stick. A step sent through the live file lands 0 to
10 flips after it is written (the port reads the file every 10 flips). Pure pursuit over 20 to 60 m was far too
stiff for that lag and swung from lock to lock into the walls; the curvature feed-forward with heading and
offset feedback at 1 rad/s (class `Tuner`) finishes three laps with about eight wall contacts a lap.
