# Tracks

The track menus as the port shows them on a new profile (2026-10-05), and how `tools/campaign_sweep.py` reaches
each track. Only the Alpha league is open on a new profile.

## Single Race, Vector class, Alpha league

Route: `config/pad_scripts/main_menu.txt` (cold boot to MAIN MENU) then `config/pad_scripts/single_race.txt`
(SINGLE PLAYER, SINGLE RACE, VECTOR, ALPHA, the track, FEISAR). TRACK SELECTION is up from about flip 5350 and
the track is confirmed at 5500; the sweep picks the Nth track with N DOWN presses at 5380, 5410, 5440 (30 flips
apart; each press is held 4 frames). The list order, top to bottom:

| DOWN presses | Track | Sweep name | Length (menu) | Steering table |
|---|---|---|---|---|
| 0 | Vineta K | `vineta_k` | 4446 m | `config/pad_scripts/drive/vineta_k.txt` |
| 1 | Modesto Heights | `modesto_heights` | | `config/pad_scripts/drive/modesto_heights.txt` |
| 2 | Chenghou Project | `chenghou_project` | | `config/pad_scripts/drive/chenghou_project.txt` |
| 3 | Blue Ridge | `blue_ridge` | | `config/pad_scripts/drive/blue_ridge.txt` |

## The ship probe on a track

`PURE_WATCH_SHIP=1` prints the player's race record each flip (task 007). On the grid the lap counter is 0; it
becomes 1 when the ship first crosses the start line, so a three-lap race is over when it passes 3. The distance
along the track is a track coordinate, not a lap distance: on Vineta K the grid is at 1079 m and the start line at
about 1250 m, and the value wraps to 0 once a lap.
