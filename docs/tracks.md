# Tracks

The track menus as the port shows them on a new profile (2026-10-05), and how `tools/campaign_sweep.py` reaches
each track. Only the Alpha league (with the Vector and Venom classes, and Zone's PRO TOZO) is open on a new
profile; the test switch `PURE_TEST_UNLOCK_ALL=1` opens the Beta and Classic leagues, three more classes and three
more Zone tracks, and the sweep runs them all (task 032, below).

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

## Single Race, the Beta and Classic leagues (task 032)

With `PURE_TEST_UNLOCK_ALL=1` (below) LEAGUE SELECTION lists ALPHA, BETA and CLASSIC; each league's panel names its
four tracks, and its TRACK SELECTION lists them. The sweep reaches a track with the league's DOWN presses at 5180,
5210 and the track's at 5380, 5410, 5440 (and the class's at 4980 and on, `--class`). Its sweep names, in menu
order:

| League (DOWN) | Track (DOWN) | Sweep name | Length (menu) | Distance wraps at | Grid (player) | Start line | AI winner's fastest pass | Budget (flips) |
|---|---|---|---|---|---|---|---|---|
| Alpha (0) | Vineta K (0) ... Blue Ridge (3) | above | | | | | | 13000, 18000 |
| Beta (1) | Sinucit (0) | `sinucit` | 6117 m | 5942 m | 144 m | about 300 m | 86.0 s | 28500 |
| Beta (1) | Citta Nuova (1) | `citta_nuova` | 5408 m | 5051 m | 248 m | about 399 m | 71.3 s | 25500 |
| Beta (1) | Sebenco Climb (2) | `sebenco_climb` | 4813 m | 4651 m | 10 m | about 155 m | 62.1 s | 23000 |
| Beta (1) | Sol 2 (3) | `sol_2` | 4400 m | 4252 m | 92 m | about 242 m | 59.4 s | 21000 |
| Classic (2) | Karbonis (0) | `karbonis` | 3256 m | 3209 m | 729 m | about 876 m | 42.5 s | 16000 |
| Classic (2) | Sagarmatha (1) | `sagarmatha` | 4544 m | 4508 m | 1017 m | about 1171 m | 52.0 s | 21500 |
| Classic (2) | Manor Top (2) | `manor_top` | 4199 m | 4193 m | 276 m | about 431 m | 50.0 s | 20000 |
| Classic (2) | Mandrashee (3) | `mandrashee` | 3901 m | 3835 m | 1115 m | about 1266 m | 47.3 s | 18500 |

The wrap, grid and start-line columns come from the port's own recordings (`--record-line`, below; 2026-10-06), as
the Alpha ones came from PPSSPP's: the grid is the player's slot (k = 7), the start line where the AI ships' lap
field turns from 0 to 1. The fastest pass is the race winner's quickest run of the track coordinate from one wrap
to the next, the pass its line is built round. Each steering table (`config/pad_scripts/drive/<track>.txt`)
follows its line with Vineta K's settings (`follow ... 0.8 0.8 recover=60 absorb=2`), untuned for the track. The
budgets come from the lengths (`lap_budget` in the sweep: three laps at 40 m/s, 144 km/h, and 15 s for the countdown
and the results panel, rounded up to 500 flips). The first rule, 45 m/s (the follower averaged 52 to 60 m/s on the
long Alpha tracks), left Citta Nuova 1650 flips of slack (laps of 116 to 119 s, 43 m/s), so it was lowered after
the first three cells, which ran with the 45 m/s budgets (25500, 23000, 20500).

Sinucit forks at about 800 m: in its recording the winner took a branch near x 570 to 600 in laps 1 and 3 and one
near x 440 to 470 in lap 2, 130 m apart.

The classes (CLASS SELECTION, `--class NAME`): VECTOR (0 DOWN), VENOM (1), FLASH (2), RAPIER (3), PHANTOM (4); a new
profile has VECTOR and VENOM. A race is longer at the faster classes. Headless recordings of Vineta K at each class
(`--record-line --class NAME`, 2026-10-06, `out/032/rec`) reached their races, and the AI winner restarted its lap
clock before its finish as many times as a race of these laps needs:

| Class | DOWN | New profile | Laps (`CLASS_LAPS`) | The AI winner's laps on Vineta K |
|---|---|---|---|---|
| vector | 0 | open | 3 | 47 to 59 s |
| venom | 1 | open | 3 | 41 to 46 s |
| flash | 2 | switch | 4 | 34 to 40 s |
| rapier | 3 | switch | 4 | 31 to 34 s |
| phantom | 4 | switch | 5 | 27 to 29 s |

A `--class` cell counts its class's laps and scales the track's budget by them (`cell_laps`, `cell_budget`). Every
windowed cell of task 032 ran at Vector; the follower has not driven a faster class.

## Everything unlocked: the test switch (task 032)

A new profile has the Vector and Venom classes, the Alpha league and, in Zone, PRO TOZO. The game has a developer
switch that opens everything: bit 0 of the PSP's GPI register (`sceKernelGetGPI`). Every frontend lock check reads
`unlocked = (GPI & 1) ? 1 : profile->0x381`: FUN_088b43d4 (an item's lock), FUN_0894fa5c (the gallery) and
FUN_089516b8 (the unlock notices). The profile byte at +0x381 is what the main menu's hidden button sequence sets
(FUN_0894d4c8: the game's button codes 2, 3, 2, 8, 9, 8, 3, 2, 3, 9, 8, 9 show "Everything"). The frame limiter
reads other GPI bits (0x20, 0x40, 0x80; docs/timing.md), and FUN_08804390 copies GPI to GPO each frame, which the
framework ignores. Retail reads 0, and so does our HLE.

`PURE_TEST_UNLOCK_ALL=1` makes the profile's `sceKernelGetGPI` return 1 (bit 0 only) and prints `[pure] TEST SWITCH:
unlock all` at start-up. It is a test switch like `PURE_TEST_NO_DAMAGE` (README.md, "Test switches"): the sweep sets
it for the cells a new profile cannot reach, never by default. What it opens, from a new profile (headless runs on
the Metal backend, 2026-10-06, `out/032/h/`):

| Screen | Without the switch | With it |
|---|---|---|
| CLASS SELECTION (Single Race) | VECTOR, VENOM | VECTOR, VENOM, FLASH, RAPIER, PHANTOM |
| LEAGUE SELECTION (Single Race) | ALPHA | ALPHA, BETA, CLASSIC |
| TRACK SELECTION, Alpha | VINETA K, MODESTO HEIGHTS, CHENGHOU PROJECT, BLUE RIDGE | the same |
| TRACK SELECTION, Beta | (no Beta league) | SINUCIT, CITTA NUOVA, SEBENCO CLIMB, SOL 2 |
| TRACK SELECTION, Classic | (no Classic league) | KARBONIS, SAGARMATHA, MANOR TOP, MANDRASHEE |
| TRACK SELECTION (Zone) | PRO TOZO | PRO TOZO, MALLAVOL, CORIDON 12, SYNCOPIA |
| TEAM SELECTION | FEISAR, AURICOM, QIREX, AG SYSTEMS, PIRANHA, ASSEGAI, TRIAKIS, HARIMAU | the eight, then ZONE and MEDIEVIL |

The league panel names each league's tracks and the TRACK SELECTION panel gives each track's length, so the lists
above are the game's own. Nothing else changes: a 2200-flip frontend run (`config/pad_scripts/frontend.txt`, a
capture every 50 flips) gives 48 captures pixel-identical with and without the switch, and the logs differ only in
the switch's own line; the MAIN MENU and SINGLE PLAYER screens of the race route are identical too. The CLASS,
LEAGUE and TEAM screens differ only by their longer lists, and Alpha's TRACK SELECTION not at all, so the Alpha
cells' routes hold with the switch on.

### Routes through the longer menus

`config/pad_scripts/single_race.txt` confirms each screen 200 flips after the one before (CLASS SELECTION up by
about 4950, confirmed at 5100; LEAGUE by 5150, confirmed at 5300; TRACK by 5350, confirmed at 5500). The sweep
writes the picks as DOWN presses 30 flips apart (each held 4 frames): the class from 4980, the league from 5180,
the track from 5380 (MODES `class_at`, `league_at`, `downs_at`). The longest picks, PHANTOM (4 DOWN, the last at
5070), CLASSIC (2) and the fourth track (3, the last at 5440), land before their confirms (shots at 5095, 5290 and
5495). `tools/campaign_sweep.py single_race --list [--class NAME]` prints each cell's presses, budget and whether
it needs the switch. Zone's route is unchanged: the Nth Zone track is N DOWN from 4980.

| Pick | Entries (DOWN presses) | Open on a new profile |
|---|---|---|
| class (`--class`, default vector) | vector 0, venom 1, flash 2, rapier 3, phantom 4 | vector, venom |
| league | alpha 0, beta 1, classic 2 | alpha |
| track | the league's four, 0 to 3 | Alpha's |
| Zone track | zone_1 PRO TOZO 0, zone_2 MALLAVOL 1, zone_3 CORIDON 12 2, zone_4 SYNCOPIA 3 | zone_1 |

A cell whose track or class is not open on a new profile (MODES `fresh`, FRESH_CLASSES) runs with
`PURE_TEST_UNLOCK_ALL=1`, and its summary row is marked `(unlock all)`; `--unlock-all` sets the switch for any cell.
A class other than Vector names the cell `<mode>-<track>-<class>` and its summary row `<track>/<class>`. Only
Single Race takes `--class` so far: Time Trial, Free Play and Tournament have a CLASS screen too, at nearly the same
flips (by 5000), but their class presses are untested.

## Racing lines from the port (task 032)

PPSSPP recorded the Alpha lines (`tools/pp_lines.py TRACK --downs N`), through a route with no class or league
picks. For the other tracks the lines come from the port's own AI ships:

- `PURE_WATCH_GRID=1` (README.md) prints, every flip of a race, one line per race record, k = 0 to 7:
  `[pure] grid frame N k=K clock=C pos=x,y,z vel=vx,vy,vz dist=D lap=L`, the ship probe's race-record fields for
  each ship, each line when it changes (eight lines a flip).
- `tools/campaign_sweep.py single_race TRACK --record-line OUT [--line REF]` runs the cell's route headless
  (`PURE_SHELL=headless`, the Metal backend, unpaced) with Cross held from 6100 and no steering, the grid probe,
  `PURE_TEST_NO_DAMAGE=1` and the unlock switch where the track needs it, to the end of the cell's budget, then calls
  `tools/pp_lines.py --port`. The player meets the first barrier and stays there (its shield refilled); the seven
  AI ships race the whole race by themselves (they did on all nine tracks recorded, and on Vineta K at every class). A
  recording takes 1 to 2 minutes of wall time.
- `tools/pp_lines.py --port LOG [--out CSV] [--samples CSV] [--ships leader|ai] [--near M] [--compare REF]` reads the first
  race of such a log, drops the player's record and every record whose lap field has bit 16 set (that ship has
  finished), and writes the samples in the PPSSPP recording's CSV form (`--samples`, the flip in the usec column).
  The line is made from the AI ship with the most progress: the one furthest along the track (the distance
  unwrapped at each wrap) at the last flip every AI ship still races, which is the race's winner. Of its samples it
  keeps those within `--near` metres (default 15) of its fastest whole pass of the track (from one wrap of the
  distance to the next), over all its laps. Two things decided that: Sinucit forks at about 800 m and the winner took
  branches 130 m apart in different laps, so the mean of all its laps ran between them, through the wall; and one
  pass alone wanders (5.8 m from the PPSSPP line on Vineta K, below). `--ships ai` takes the mean of all the AI
  ships instead, as `--export-line` does with a PPSSPP recording (closest to the PPSSPP line, but it mixes branches
  too). The line is the follower's own AiLine (2 m bins, gaps interpolated, smoothed over +-3 bins), written as the
  `dist,x,z` rows `follow` reads.
  `--compare REF` prints how far it lies from another line: the lateral distance (across REF at the same track
  distance) and the distance between the points of the same track distance, mean and maximum over the lap.

Headless runs keep the game's own timing: the race clock advances 5.0 s every 300 flips there, as in the window
(60 flips a second), because the kernel's clock is virtual; only the wall time is shorter (about 200 flips a
second on the Metal backend). The AI ships differ from run to run in either case (the grid varies, task 018).

A heavy run beside a windowed cell breaks the cell: the first Vineta K cell with the port line ran while the first
recording ran, and its menu route fell behind (the profile screen came up after the route's DOWN at 2100, so Cross
picked LOAD; NO RACE, `out/032/vkport` of 12:11). Recordings and windowed cells go one at a time.

### The check on Vineta K

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
a `follow` line in `config/pad_scripts/drive/TRACK.txt`. Since task 032 the port records its own line, for any
track the sweep reaches (PPSSPP's route knows the Alpha league only): `tools/campaign_sweep.py single_race TRACK
--record-line config/pad_scripts/drive/TRACK.line.csv` (1 to 2 min, headless; "Racing lines from the port" above).

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
- **Controls through the live file.** The game's default controls (its own controls screen, task 030): X accelerate, Square use pickup, Circle absorb
  pickup, L/R airbrakes, Triangle reverse camera. The analog triggers press L and R, but `axis lefttrigger 0`
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
| put back by the game | Sinucit at 896 to 980 m, Manor Top at 2198 to 2305 m (task 032) | the ship left the track and fell (on Sinucit the probe's height drops by 30 m and the speed climbs to 700 km/h in under a second), and the game set it back 200 to 500 m along the track, again and again at the same place. The sweep counts every step back of the distance by more than 30 m and under the wrap (`PUTBACK_M`) and names the places in the detail; the first runs, before the class, called these stalls "stuck on geometry" |
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
flips for Vineta K, 17000 for the other three in these runs (18000 since task 017's review), whose laps take the
follower 75 to 95 s. Since that review `--no-damage` is the normal way to run a coverage cell (except Zone, below).

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

## The other single-player modes (task 018)

SINGLE PLAYER lists SINGLE RACE, TOURNAMENT, TIME TRIAL, ZONE and FREE PLAY. Each mode has its own route after
`config/pad_scripts/main_menu.txt`, measured on a new profile (2026-10-06); the sweep proves each with its
`<cell>-menu` shot (the track or league list) and holds Cross from the route's last step for the cell's budget.

| Mode | Route | DOWN on SINGLE PLAYER | Screens | Pick (N DOWN at) | Cross held from | Race flips a second | Budget (`MODES`) |
|---|---|---|---|---|---|---|---|
| Single Race | `single_race.txt` | 0 | CLASS, LEAGUE, TRACK, TEAM | track, 5380 | 6100 | 60 | 13000 Vineta K, 18000 the others |
| Tournament | `tournament.txt` | 1 | CLASS, TOURNAMENT SELECTION, TEAM (no track screen) | league, 5180 | 5850 | 60 | 80000 for the four races |
| Time Trial | `time_trial.txt` | 2 | CLASS, LEAGUE, TRACK, TEAM (no ghost question on a new profile) | track, 5380 | 5900 | 30 | 9000 Vineta K, 11000 the others |
| Zone | `zone.txt` | 3 | TRACK SELECTION only (no class, league or team) | Zone track, 4980 | 5250 | 30 | 9000 |
| Free Play | `free_play.txt` | 4 | CLASS, LEAGUE, TRACK, TEAM | track, 5380 | 5900 | 30 | 9000 Vineta K, 11000 the others |

The menu shots:
- Time Trial's TRACK SELECTION lists the four Alpha tracks with RACE RECORD and LAP RECORD and the gold, silver and
  bronze times (2:04.00, 2:07.00, 2:10.00 on Vineta K); Free Play's has the records with LENGTH (4446 M) and HEIGHT
  (222 M).
- Zone's TRACK SELECTION has PRO TOZO alone (`zone_1`), with BEST ZONE, BEST SCORE and the targets 25, 20, 15.
- Tournament's TOURNAMENT SELECTION has ALPHA alone, its panel listing Vineta K, Modesto Heights, Chenghou Project
  and Blue Ridge.

In Time Trial and Free Play the player is alone, found at flip 5730 at 1216.9 m on Vineta K (just behind the line
at about 1233 m), and the clock starts at about 6010. The lap clock behaves as in Single Race: it runs through the
first crossing and restarts at each later one, so the sweep counts laps the same way. In Zone the probe finds the
player at 5130 with a shield of 75 and the clock starts at about 5380. Tournament's first race is Single Race's
grid (the player 8th at 1079 m), clock from about 5975 to 6055.

### 30 flips a second

Time Trial, Free Play and Zone run at 30 flips a second (docs/research.md), so their budgets are counted at 30, and
the sweep scales its flip-counted waits (`fps` in `MODES`: the `ref` shot, the live shots after the finish, the
slow shots). The live file is still read every 10 flips, a third of a second here, and the follower does worse:
on Vineta K it took 60 to 68 contacts in Time Trial and in Free Play against 37 to 47 in Single Race, with laps of
62 to 82 s. The shield those contacts took (57 to 65 a run) leaves the ship alive: the Verify run, without the
switch, ended with 42.9.

### End screens and how the sweep finds them

| Mode | End screen | Detection (`tools/campaign_sweep.py`) |
|---|---|---|
| Time Trial | TIME TRIAL COMPLETED: LAP 1 to 3 (the best in yellow, LR and RR marks), TOTAL, ENTER TAG, over the track; about 3.5 s after the line | the TOTAL label rule of Single Race (`RESULTS_TOTAL` drawn and unchanged in two shots in a row) |
| Free Play | no last lap: the HUD's LAP goes on (LAP 4). The sweep pauses after three laps (Start), picks END SESSION (DOWN, DOWN; the menu is CONTINUE, RESTART, END SESSION, PRESS X TO CONFIRM) and presses Cross; FREE PLAY SESSION RESULTS comes up about 4 s later: the laps best first, TOTAL LAPS 3, ENTER TAG | the TOTAL label rule: the TOTAL LAPS label is where TOTAL is. Shots before END SESSION's Cross are skipped. With no lap done the session ends on a fly-by with RETURN TO MAIN MENU (`MENU_BANNER`) |
| Zone | the ship is destroyed when the shield runs out, which is Zone's normal end; about 7 s later a SHIP DESTROYED panel: TOTAL ZONES CLEAR, TOTAL LAPS CLEAR, PERFECT ZONES, PERFECT LAPS, TOP SPEED, SCORE, ENTER TAG | from the probe's shield at 0 or below, shots every 15 flips; the SHIP DESTROYED title (`DESTROYED_TITLE`, the same as Single Race's) in two shots in a row is PASS, and TOTAL ZONES CLEAR is read from the panel (`ZONES_VALUE`, `read_digits`). No stall rule, and `--no-damage` is ignored |
| Tournament | after each race the results panel ("BAD LUCK... 6TH", the laps, TOTAL, ENTER TAG); Cross enters the tag one letter at a time (three presses for AAA), then PRESS X TO CONTINUE: the race's standings (ALPHA, RACE n OF 4: team, time, points), TOURNAMENT STANDING (team, points), PROFILE AUTOSAVED, NEXT RACE / QUIT TOURNAMENT. After race 4: RACE 4 OF 4, TOURNAMENT STANDING (the final standings), END TOURNAMENT ("8TH - COMMISERATIONS. HAVE ANOTHER GO!"), PROFILE AUTOSAVED, MAIN MENU | each race's panel by the TOTAL label rule; then Cross every 120 flips (`ADVANCE_EVERY`) and a shot every 30; the next race starts when a new player object stands on its grid (lap 0, clock 0), and Cross is held again. The TOURNAMENT STANDING title (`STANDING_TITLE`) after the last race is PASS. Every screen between races is drawn over a moving fly-by, so none is ever still: a first rule that waited for a still screen passed on the SINGLE PLAYER menu after the tournament. No grid or final standings 4800 flips after a race's results is STUCK |

### Zone without steering

Zone has no AI ships, so `tools/pp_lines.py` cannot record a racing line, and `config/pad_scripts/drive/zone_1.txt`
does not steer. With Cross held and the stick centred the ship starts at 3796 m, meets the barrier of the first
corner at 227 m (3.5 s in, 191 km/h lost) and stays against it at about 279 m. The shield falls about 1.3 a second
there and runs out at 59.2 s; the HUD read ZONE 6 and SCORE 4281 then, and the panel TOTAL ZONES CLEAR 6, TOP SPEED
405.14, SCORE 4293. A racing line for PRO TOZO would let the cell reach later zones.

### Runs (2026-10-06)

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

## Recording a human lap (Erik's line)

Where the follower cannot drive a track (Sinucit's fork, Manor Top's bend, the long Beta tracks on a bad grid), a
human line replaces the AI's. The follower steers in a closed loop along a line, so what it needs is the positions of
a good lap, not the presses (a replayed pad script diverges, since the AI grid differs every run).

1. `tools/record_lap.sh TRACK`: the game opens in a window with sound and your own bindings (a copy of your settings
   in a scratch data directory), every track and class unlocked by the test switch, and every ship's position logged
   once per flip (`PURE_WATCH_GRID=1`). Drive Single Race > the class > the league > TRACK, race three laps (one
   clean lap is enough; the fastest whole lap is kept), then close the window. The log is `out/laps/TRACK.log`.
2. `tools/record_lap.sh TRACK --line`: your fastest whole lap, as the line `config/pad_scripts/drive/TRACK.line.csv`
   (`tools/pp_lines.py --port --ships player`); the AI line it replaces is kept once as `TRACK.line.ai.csv`.
3. `python3 tools/campaign_sweep.py single_race TRACK --no-damage`: the follower on your line.

The sweep's cells of that track then run on your line until the file is replaced again.
