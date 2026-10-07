# Tracks: the record (tasks 016 to 018 and 032, 2026-10-05 and 2026-10-06)

The sweep's runs that docs/tracks.md recorded, moved here by task 053 (2026-10-07); the tracks, the routes, the
follower and how the sweep reads each screen stay in [docs/tracks.md](../tracks.md). Every cell has run again since,
in the fidelity audit's matrix (task 035, docs/history/fidelity.md), and the stalls are summed up in docs/tracks.md,
"Stalls".

## Port lines against the PPSSPP line on Vineta K (task 032)


The port's Vineta K recording (`tools/campaign_sweep.py single_race vineta_k --record-line
out/032/vineta_k.port.line.csv --line config/pad_scripts/drive/vineta_k.line.csv`, 60 s of wall time to flip
19100): all seven AI ships ran their three laps; the winner, ship 0, finished at flip 15917, and the faster of its
two whole passes of the track took 56.6 s. Lines made from it, against the PPSSPP line (the mean of PPSSPP's seven
AI ships, `config/pad_scripts/drive/vineta_k.line.csv`), over the 2219 bins of the lap (`--compare`):

| Line from the port's recording | Lateral distance, mean | Lateral distance, max | Same-distance points, mean |
|---|---|---|---|
| the winner's samples within 15 m of its fastest pass (`--port`'s default; `out/032/vineta_k.port.line.csv`) | 3.84 m | 11.42 m (at 1110 m) | 3.93 m |
| the winner's samples within 20 m (`--near 20`) | 3.12 m | 10.66 m | |
| all the winner's laps (the first version, which mixes branches where a track forks) | 2.81 m | 10.66 m | 2.88 m |
| the winner's fastest pass alone | 5.79 m | 16.64 m | 5.91 m |
| the mean of the seven AI ships (`--ships ai`, also mixes branches) | 1.54 m | 6.96 m | 1.58 m |

The follower drove Vineta K on the port lines (`tools/campaign_sweep.py single_race vineta_k --no-damage --line
LINE --out out/032/vkport`; the steering table's own settings):

| Line | Outcome | Laps (s) | Contacts (a lap) | Mean distance from the line | Flip |
|---|---|---|---|---|---|
| `out/032/vineta_k.port.line.csv` (the 15 m line) | PASS | 63.2, 57.7, 60.3 | 39 (12, 13, 14) | 8.1 m, 28% of the race more than 10 m off | 17290 |
| the first version (all the winner's laps) | PASS | 60.5, 59.9, 56.1 | 49 (13, 22, 14) | 8.8 m, 35% | 17060 |
| the PPSSPP line, without the unlock switch (the acceptance run) | PASS | 68.4, 59.6, 63.7 | 43 (15, 13, 15) | | 18240 |

The PPSSPP line's own record is 37 to 47 contacts (task 016), so the port line drives as well. The Alpha tables keep
their PPSSPP lines.

## No-damage runs (task 017, 2026-10-05 and 2026-10-06)

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

## The other single-player modes: runs (task 018, 2026-10-06)


| Cell | Switch | Outcome | Laps (s) or zones | Contacts (a lap) | Shield taken | Flip (budget ends at) | Real s |
|---|---|---|---|---|---|---|---|
| zone/zone_1 | off | PASS: TOTAL ZONES CLEAR 6, destroyed at 59.2 s | 0 laps | 1 | 75 (all) | 7390 (14250) | 248 |
| time_trial/vineta_k | no damage | PASS | 81.8, 67.5, 73.6 | 68 (26, 20, 22) | 65 | 12830 (13900, budget 8000 then) | 428 |
| free_play/vineta_k | no damage | PASS | 73.6, 68.5, 75.9 | 68 (23, 23, 22) | 65 | 12810 (14900) | 428 |
| tournament/alpha, first run | no damage | the four races to their panels; the old still rule then passed on the SINGLE PLAYER menu (replaced) | 63.9, 58.5, 57.2; 93.1, 91.6, 94.8; 76.7, 88.5, 84.2; 80.1, 91.4, 94.3 | 47, 78, 69, 62 | 92, 141, 134, 135 | 70620 (85850) | 1298 |
| tournament/alpha | no damage | PASS: TOURNAMENT STANDING after race 4 at flip 70790 (and after races 1 to 3 at 17730, 35930, 52900) | 58.5, 63.5, 54.6; 94.1, 88.8, 94.2; 80.8, 86.8, 93.4; 94.4, 93.6, 86.7 | 42, 80, 69, 70 | 72, 166, 162, 137 | 70800 (85850) | 1297 |
| time_trial/vineta_k (Verify) | off | PASS | 68.1, 62.0, 68.2 | 60 (19, 17, 24) | 57 (42.9 left) | 12090 (14900) | 404 |
| zone/zone_1 (Verify) | off | PASS: TOTAL ZONES CLEAR 6, destroyed at 59.2 s | 0 laps | 1 | 75 (all) | 7390 (14250) | 247 |

No cell halted: no `[hle-stub]`, unsupported instruction or runtime stop other than the sweep's own quit. Between
Tournament races the next player object appeared about 1010 flips (17 s, eight Cross presses) after the results
panel, and the final TOURNAMENT STANDING about 670 flips after race 4's panel. The Feisar finished the first
run's tournament 8th ("8TH - COMMISERATIONS. HAVE ANOTHER GO!").

## Runs of the other leagues and the Zone tracks (task 032)

Every cell from a new profile, windowed on the default path (the Metal shell and backend), the unlock switch set by
the sweep, Single Race with `--no-damage` (2026-10-06; `out/sweep/summary.txt`). The race clock's laps, the
sweep's contacts, the shield the frames took (the switch put it back), the game's put-backs (the ship off the
track and set back along it), and the flip of the outcome with the flip the budget ended at.

### Beta

| Cell | Outcome | Laps (s) | Contacts (a lap) | Shield taken | Put-backs | Flip (budget ends at) | Real s |
|---|---|---|---|---|---|---|---|
| sinucit | STALL: put back by the game, 9 times in 50 s, each time after it left the track at 896 to 980 m (just past the fork at about 800 m), set down at about 517 m; 0 laps | | 13 (13) | 54 | 9 | 9570 (31600) | 262 |
| citta_nuova | PASS | 119.4, 116.1, 116.2 | 105 (33, 37, 35) | 255 | 0 | 27450 (29100) | 562 |
| sebenco_climb | PASS | 101.0, 106.8, 111.0 | 86 (28, 27, 31) | 178 | 0 | 25590 (26600) | 526 |
| sol_2 | PASS | 87.5, 87.6, 84.4 | 66 (22, 21, 23) | 151 | 2 (at 970 and 1109 m in lap 3) | 21840 (27100) | 472 |

### Classic

| Cell | Outcome | Laps (s) | Contacts (a lap) | Shield taken | Put-backs | Flip (budget ends at) | Real s |
|---|---|---|---|---|---|---|---|
| karbonis | PASS | 82.8, 66.2, 62.3 | 64 (22, 20, 22) | 150 | 4 (at 2605 to 2922 m in lap 1) | 19000 (22100) | 421 |
| sagarmatha | PASS | 71.4, 62.7, 68.0 | 49 (17, 14, 18) | 80 | 0 | 18830 (27600) | 416 |
| manor_top | STALL: put back by the game, 3 times at about 1500 m and then 4 times after it left the track at 2198 to 2305 m, set down at about 2008 m; 0 laps | | 26 (26) | 91 | 7 | 10470 (26100) | 276 |
| mandrashee | PASS | 79.4, 72.8, 82.3 | 69 (25, 20, 24) | 140 | 0 | 20520 (24600) | 447 |

Both stalls ran before the put-back class existed, so their rows first said "stuck on geometry" (an incidental
contact); `classify_stall` on the same logs gives "put back by the game 4 times since the last progress" for both.
The Verify run of Sinucit (14:43, the summary's row now) stalled the same way with the class in place: put back 5
times, after leaving the track at 891 to 952 m, set down at about 518 m, STALL at flip 8500. Manor Top's row is
still the first run's. The stall shots are `out/sweep/single_race-sinucit/stall.png` and
`out/sweep/single_race-manor_top/stall.png`. What happens there:

- **Sinucit.** The track forks at about 800 m, and the AI ships take both branches (in the recording, 81 samples on
  the branch near x 430 to 470 and 78 on the one near x 570 to 610 at 850 m). The line follows the winner's fastest
  pass, on the first. The follower ran 9 to 16 m right of it there, inside the right-hand bend after the fork, where
  the AI pack keeps within about 9 m of its own mean, and fell off: the probe's height dropped from 124 to 95 m in
  1.2 s and the game put the ship back at about 517 m, nine times. Tries with the follower's own options, apart from
  the summary: `--set preview=0.5` (`out/032/p05`) got through twice in sixteen falls and stalled in lap 3 at 942 to
  1012 m; a line round the winner's other pass, on the other branch (`out/032/alt`), fell seven times, at 871 to 1042 m.
- **Manor Top.** No fork: the AI pack keeps within 3 to 7 m of its mean through a tight right-left bend at 2150 to
  2350 m. The follower turned in at full lock and swung 15 to 23 m right of the line, off the track; `--set
  preview=0.5` (`out/032/p05`) stalled at the same bend (2195 to 2462 m).

Both are the follower's limit (its 0.8 s lag, task 016), not a halt: the committed tables keep Vineta K's settings.

No cell halted: no `[hle-stub]`, unsupported instruction or runtime stop other than the sweep's own quit (or a
recording's frame exit) in any of the 30 logs: the cells, the reruns, the tries and the 13 recordings.

### Zone

| Cell | Track | Outcome | Zones (TOTAL ZONES CLEAR) | Destroyed at | Contacts | Flip (budget ends at) | Real s |
|---|---|---|---|---|---|---|---|
| zone_2 | MALLAVOL | PASS | 7 (TOP SPEED 461.63, SCORE 4808) | 59.8 s, at rest at 443 m | 1 | 7410 (14250) | 247 |
| zone_3 | CORIDON 12 | PASS | 7 (TOP SPEED 504.83, SCORE 4991) | 62.5 s, at 1815 m | 6 | 7490 (14250) | 250 |
| zone_4 | SYNCOPIA | PASS | 7 | 61.3 s, at 1603 m | 3 | 7440 (14250) | 253 |

As on PRO TOZO (zone 6), the ship runs with Cross held and no steering into a barrier and drains its shield (75)
against it for about a minute. The first runs of zone_2 and zone_3 timed out with the panel on the screen for seven
minutes: on these tracks the SHIP DESTROYED title lit every glyph one column narrower (13 columns off the signature
against a limit of 8), and the 7 of TOTAL ZONES CLEAR, a top bar with a centre stroke, read as `?`. The title check
now ignores a column an edge moved by one place explains (the panels count 0, race views and the other panels 23 or
more) and the 7 has a second signature; the zone_4 cell and the zone_2 and zone_3 reruns ran with the fix.

### Without the switch

- `tools/campaign_sweep.py single_race vineta_k --no-damage`: PASS at flip 18240 (laps 68.4, 59.6, 63.7 s, 43
  contacts); the log has no `unlock all` line.
- `tools/frame_regress.sh` (the Metal shell and backend, `out/032/regress`): PASS, 5/5 scenes, every fraction equal
  to the measured column but race_hud's 0.0366 (measured 0.0379).
