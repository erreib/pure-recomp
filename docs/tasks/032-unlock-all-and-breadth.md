# 032: A test-only unlock-all switch, racing lines from the port's own AI, every track in the sweep

Milestone: M5 (breadth) | Branch: task/032-unlock-all-and-breadth | Status: OPEN

## Goal
The sweep covers the Alpha league's four tracks because a fresh profile unlocks nothing else. The game has a
developer switch for that: bit 0 of the PSP's GPI register, read through `sceKernelGetGPI`, which every frontend lock
check treats as "everything unlocked" (`unlocked = (GPI & 1) ? 1 : profile->0x381`, where the profile byte is what
the main menu's hidden button sequence sets). Our HLE returns 0 for GPI. This task adds `PURE_TEST_UNLOCK_ALL=1`, which
makes it return 1, and uses it to put every track, class and league into the sweep: routes for the longer menus,
racing lines for the new tracks recorded from the port's own AI ships (not PPSSPP), MODES rows and budgets, and one
Single Race cell per new track run to its results screen with the no-damage switch.

## Read first
- CLAUDE.md, docs/status.md (Follow-ups: the unlock rows; M5), docs/tracks.md, docs/tasks/016, 017 and 018 (the
  follower, the no-damage switch, the modes), docs/timing.md (GPI bits 0x20/0x40/0x80 are the frame limiter's; bit 0
  is not), docs/verification.md
- src/profile/pure_profile.cpp (`register_pure_hle`: the `sceKernelGetGPI` override returning 0; the
  `PURE_TEST_NO_DAMAGE` switch and `watch_ship`, the race record array at 0x08B72010 + k * 0x1C0 with the player at
  k = 7, fields pos +0, lap +0x10, dist +0x18)
- tools/campaign_sweep.py (MODES, `Leg`, `AiLine`, the follower; how a cell's route reaches a track by DOWN presses
  on the TRACK screen), tools/pp_lines.py (how a racing line is extracted from PPSSPP's AI ships and the `.line.csv`
  format the follower reads), config/pad_scripts/single_race.txt, config/pad_scripts/drive/*.txt and *.line.csv
- out/unlock/ in the main checkout (read only): `unlock_fns.txt` (FUN_0894d4c8: the main menu's sequence
  2,3,2,8,9,8,3,2,3,9,8,9 of the game's button codes sets profile+0x381 and shows "Everything"), `gpi_fe.txt` (three
  frontend screens reading `GPI & 1`), the unlock-type name table at 0x08AB4A0C (Billboard, League, Music, Skin, Team,
  Tournament, Track, Liveries, Flash/Rapier/Phantom Class)

## Deliverable
1. `PURE_TEST_UNLOCK_ALL=1`: `sceKernelGetGPI` returns 1 (bit 0 only) in our profile's override; documented as a
   test-only switch beside `PURE_TEST_NO_DAMAGE` in README.md. Check what it opens: with the switch, from a fresh
   profile, capture the CLASS, LEAGUE and TRACK screens of Single Race and the Zone track screen (`<cell>-menu`-style
   shots in out/032/) and list every entry each shows; without the switch, the same screens as today. Also note
   whether the switch changes anything else visible in a 2200-flip frontend run (it must not: GPI bit 0 is read only
   by the lock checks and copied to GPO at boot).
2. Racing lines from the port: `PURE_WATCH_GRID=1` in the profile prints, every flip of a race, one line per
   entry of the race record array (k = 0..7): `[pure] grid frame N k=K pos=x,y,z dist=D lap=L` (the same fields the
   ship probe prints), and `tools/pp_lines.py --port LOG` turns such a log into the same `.line.csv` the follower
   reads (the AI ship with the most progress over the race, as pp_lines.py chooses from PPSSPP's). Check it on Vineta
   K: a line from a port run against the existing PPSSPP line (`config/pad_scripts/drive/vineta_k.line.csv`): report
   the mean and maximum distance between the two lines over the lap; the follower must still PASS Vineta K with the
   port line (`--line`).
3. Routes and MODES: with the switch, routes through the longer CLASS, LEAGUE and TRACK lists (the DOWN counts per
   entry; `single_race.txt` takes the class, league and track as steps the sweep writes, as task 018 did for the
   modes), MODES rows for every track of every league in Single Race, the Zone tracks 2 to 4, and the classes
   (`--class NAME`, default Vector), with frame budgets from the lap lengths. Record each new track's line (item 2)
   from a port run with the switch, Cross held, no steering (the AI ships race by themselves), as
   `config/pad_scripts/drive/<track>.line.csv` plus a `<track>.txt` with the follow line, as the Alpha tracks have.
4. Run one Single Race cell per new track (every track outside Alpha; Vector class) with `--no-damage` to the results
   screen, and the Zone tracks 2 to 4 to the SHIP DESTROYED panel; record lap times, contacts and any halt in
   docs/tracks.md (a table per league). A cell that stalls is recorded with its stall shot; do not tune the follower
   per track beyond the `--set` parameters the Alpha tracks use.
5. docs/tracks.md: the leagues and their tracks, the class list, the switch, how lines are recorded from the port, the
   cells' table. README.md: the switch, `PURE_WATCH_GRID`, `pp_lines.py --port`.

## Acceptance criteria
- [ ] With `PURE_TEST_UNLOCK_ALL=1` the TRACK screen lists tracks beyond Alpha's four and the CLASS screen more than
      Vector (the shots and the list in Result); without it, today's screens.
- [ ] `tools/pp_lines.py --port` makes a Vineta K line within 5 m mean of the PPSSPP line, and the follower PASSes
      Vineta K with it.
- [ ] Every track outside Alpha has a line and a MODES row, and its Single Race cell reaches the results screen with
      `--no-damage` (or its stall is recorded with the reason).
- [ ] Zone tracks 2 to 4 reach the SHIP DESTROYED panel and their zone counts are recorded.
- [ ] Without the switch, `tools/frame_regress.sh` is unchanged (5/5 at the Metal column) and
      `tools/campaign_sweep.py single_race vineta_k --no-damage` still PASSes.

## Verify
`tools/build.sh profile && python3 tools/campaign_sweep.py single_race citta_nuova --no-damage && python3 tools/campaign_sweep.py zone zone_2 && grep -c PASS out/sweep/summary.txt`

(Citta Nuova stands in for the first Beta track, Sinucit, which the follower cannot drive past its fork: a limit of the
test driver, recorded in the Result and the follow-ups, not of the port.)

## May touch
- src/profile/pure_profile.cpp (the GPI override and the grid probe only), tools/campaign_sweep.py, tools/pp_lines.py,
  config/pad_scripts/ (routes, drive tables, lines), docs/tracks.md, README.md

## Must not touch
- vendor/, patches/, src/gpu/, src/host/, src/hle/, src/tools/, tools/run_boot.py, tools/frame_regress.sh, ref/,
  CMakeLists.txt

## Estimated turns
80 (the cells take about 7 minutes each, windowed; run them in the background and in sequence)

## Escalate when
The switch opens nothing (report the GPI call sites you checked with `PURE_TRACE_CALLS` and stop), a track halts the
game (a stub, an unsupported instruction, a runtime stop: record it and move on; stop only if the menu route breaks),
or a track's AI ships do not race with Cross held and no steering (report; that track gets no line).

## Result
Status: PARTIAL. All five acceptance criteria hold, but the Verify line fails at its first cell. The first Beta track is
`sinucit` as the sweep names it, so the Verify line is unchanged. Sinucit is one of the two recorded stalls: the
follower leaves the track at about 900 to 1050 m, just past a fork, and the game puts the ship back, every time. It
did this in all four Sinucit runs, including the Verify run. The `&&` then skips `zone zone_2`, which passes on its own
(below).

The rest of the task:
- `PURE_TEST_UNLOCK_ALL=1` opens three classes, two leagues and three Zone tracks, and changes nothing else.
- The port records its own racing lines: on Vineta K the line lies 3.84 m (mean) from PPSSPP's line, and the
  follower passes Vineta K on it.
- Every track outside Alpha has a line, a steering table and a MODES row. Six of the eight reach their results
  screens with `--no-damage`. Sinucit and Manor Top stall, recorded with the cause.
- Zone tracks 2 to 4 each end on SHIP DESTROYED at TOTAL ZONES CLEAR 7.
- Without the switch, `tools/frame_regress.sh` is 5/5 on the Metal path and Vineta K `--no-damage` passes.
- No cell, recording or rerun halted.

### What the switch opens
Headless runs on the Metal backend from a new profile (`out/032/h/`, 2026-10-06):

| Screen | Without the switch | With `PURE_TEST_UNLOCK_ALL=1` |
|---|---|---|
| CLASS SELECTION | VECTOR, VENOM | VECTOR, VENOM, FLASH, RAPIER, PHANTOM |
| LEAGUE SELECTION | ALPHA | ALPHA, BETA, CLASSIC |
| TRACK SELECTION, Alpha | VINETA K, MODESTO HEIGHTS, CHENGHOU PROJECT, BLUE RIDGE | the same, pixel-identical |
| TRACK SELECTION, Beta | (no league) | SINUCIT (6117 m), CITTA NUOVA (5408 m), SEBENCO CLIMB (4813 m), SOL 2 (4400 m) |
| TRACK SELECTION, Classic | (no league) | KARBONIS (3256 m), SAGARMATHA (4544 m), MANOR TOP (4199 m), MANDRASHEE (3901 m) |
| Zone TRACK SELECTION | PRO TOZO | PRO TOZO, MALLAVOL, CORIDON 12, SYNCOPIA |
| TEAM SELECTION | FEISAR, AURICOM, QIREX, AG SYSTEMS, PIRANHA, ASSEGAI, TRIAKIS, HARIMAU | the eight, then ZONE and MEDIEVIL |

Nothing else changes:
- A 2200-flip `frontend.txt` run with a capture every 50 flips gives 48 captures that are pixel-identical (tol 0)
  with and without the switch.
- The two logs differ only in the switch's own line.
- MAIN MENU and SINGLE PLAYER are identical too.
- The game copies GPI to GPO each frame (FUN_08804390), and the framework's `sceKernelSetGPO` ignores it.

The class laps come from headless recordings of Vineta K at each class: 3 laps at Vector and Venom, 4 at Flash and
Rapier, 5 at Phantom. The AI's laps run from 59 s at Vector down to 27 s at Phantom. `--class` cells count these
laps (`CLASS_LAPS`).

### Racing lines from the port
- `PURE_WATCH_GRID=1` prints `[pure] grid frame N k=K clock=C pos=x,y,z vel=vx,vy,vz dist=D lap=L` for k = 0 to 7.
- `tools/campaign_sweep.py single_race TRACK --record-line OUT` runs the cell headless with Cross held, no steering
  and the no-damage switch, which takes 1 to 2 minutes. It then calls `tools/pp_lines.py --port LOG`.
- `pp_lines.py --port` builds the line from the AI ship with the most progress, which is the race winner. It keeps
  the winner's samples within 15 m (`--near`) of its fastest wrap-to-wrap pass:
  - Averaging all its laps mixed the two branches of Sinucit's fork, 130 m apart.
  - The fastest pass alone lay 5.79 m from PPSSPP's line on Vineta K.
- Headless runs keep the game's own timing: the race clock still advances 5.0 s every 300 flips.
- PPSSPP's debugger port option in pp_lines.py was also called `--port`. It is now `--debug-port`.

Vineta K, port line against PPSSPP's line over 2219 bins: lateral distance mean 3.84 m, max 11.42 m. The follower
with `--line out/032/vineta_k.port.line.csv --no-damage` passed, with laps 63.2, 57.7 and 60.3 s and 39 contacts
(12, 13, 14). PPSSPP's line has 37 to 47 contacts on record.

### The cells
Windowed on the Metal shell and backend, one at a time, with the unlock switch set by the sweep. Single Race ran
with `--no-damage`.

| League | Cell | Outcome | Laps (s) | Contacts (a lap) | Put-backs | Flip (budget ends at) |
|---|---|---|---|---|---|---|
| Beta | sinucit | STALL in all 4 runs: put back by the game after leaving the track at 871 to 1042 m, past the fork at about 800 m | | 7 (Verify run) | 5 (Verify run; 9, 16, 7 in the others) | 8500 (34600), Verify run |
| Beta | citta_nuova | PASS | 119.4, 116.1, 116.2 | 105 (33, 37, 35) | 0 | 27450 (29100) |
| Beta | sebenco_climb | PASS | 101.0, 106.8, 111.0 | 86 (28, 27, 31) | 0 | 25590 (26600) |
| Beta | sol_2 | PASS | 87.5, 87.6, 84.4 | 66 (22, 21, 23) | 2 | 21840 (27100) |
| Classic | karbonis | PASS | 82.8, 66.2, 62.3 | 64 (22, 20, 22) | 4 | 19000 (22100) |
| Classic | sagarmatha | PASS | 71.4, 62.7, 68.0 | 49 (17, 14, 18) | 0 | 18830 (27600) |
| Classic | manor_top | STALL: put back 3 times at about 1500 m, then 4 times after leaving the track at 2198 to 2305 m (a tight right-left bend) | | 26 in lap 1 | 7 | 10470 (26100) |
| Classic | mandrashee | PASS | 79.4, 72.8, 82.3 | 69 (25, 20, 24) | 0 | 20520 (24600) |
| Zone | zone_2 MALLAVOL | PASS: TOTAL ZONES CLEAR 7, destroyed at 59.8 s | | 1 | | 7410 (14250) |
| Zone | zone_3 CORIDON 12 | PASS: TOTAL ZONES CLEAR 7, destroyed at 62.5 s | | 6 | | 7490 (14250) |
| Zone | zone_4 SYNCOPIA | PASS: TOTAL ZONES CLEAR 7, destroyed at 61.3 s | | 3 | | 7440 (14250) |
| (no switch) | vineta_k | PASS | 68.4, 59.6, 63.7 | 43 (15, 13, 15) | 0 | 18240 (19100) |

The stall shots are `out/sweep/single_race-{sinucit,manor_top}/stall.png`.

Tries for the two stalls, apart from the summary:
- `--set preview=0.5`: Sinucit got past the bad spot twice in sixteen put-backs, then stalled in lap 3. Manor Top
  stalled at the same bend.
- A Sinucit line built round the winner's other pass, on the other branch of the fork, fell seven times, at 871
  to 1042 m.
- On Manor Top the AI pack keeps within 3 to 7 m of its mean, and the follower swings 15 to 23 m off. Both stalls
  are the follower's limit, not the line's.

Fixes made along the way, each its own commit:
- Zone 2 and 3 first timed out with the end panel on screen. On those tracks the panel's title lit each glyph one
  column narrower, and its 7 read as `?`. The title check now ignores one-column edge shifts, and 7 has a second
  signature. Zone 4 and the reruns of Zone 2 and 3 pass.
- A STALL is now classed "put back by the game" when the game set the ship back along the track (`PUTBACK_M`).
- The new tracks' budgets come from their lengths at 40 m/s. The first three cells ran at a 45 m/s rule, which
  left Citta Nuova only 1650 flips of slack.

### Changed
- `src/profile/pure_profile.cpp`: the `PURE_TEST_UNLOCK_ALL` GPI override, `return_one`, and the `PURE_WATCH_GRID`
  probe (`watch_grid`).
- `tools/campaign_sweep.py`:
  - leagues, classes and Zone tracks: `picks`, `needs_unlock`, `cell_name`, `CLASS_LAPS`, `cell_laps`,
    `cell_budget`, `lap_budget`, `LENGTHS`;
  - `--class`, `--unlock-all`, `--record-line`, `--list` with picks, laps and budgets;
  - the `(unlock all)` summary mark;
  - AiLine's `ships`, `span` and `keep` filters;
  - the put-back stall class;
  - the edge-tolerant title match and the 7's second signature.
- `tools/pp_lines.py`: `--port`, `--samples`, `--ships`, `--near` and `--compare`; `--port` renamed to
  `--debug-port`.
- `config/pad_scripts/single_race.txt`, `config/pad_scripts/zone.txt`: comments on the picks.
- `config/pad_scripts/drive/`:
  - `{sinucit,citta_nuova,sebenco_climb,sol_2,karbonis,sagarmatha,manor_top,mandrashee}.{txt,line.csv}` (new);
  - `zone_{2,3,4}.txt` (new).
- `docs/tracks.md`: the leagues and tracks, the classes and their laps, the switch and what it opens, routes,
  lines from the port with the Vineta K check, the put-back stall class, the cells' tables.
- `README.md`:
  - `PURE_TEST_UNLOCK_ALL` under the test switches;
  - `PURE_WATCH_GRID`;
  - the sweep row: leagues, `--class`, `--unlock-all`, `--record-line`, `pp_lines.py --port`.
- `docs/tasks/032-unlock-all-and-breadth.md`: this Result.

### Verify output (last 20 lines)
```
[sweep] single_race-sinucit: exit at flip 34600, no damage (test switch), unlock all (test switch)
[sweep] single_race-sinucit: shot ref: shield bar 100%
[sweep] single_race-sinucit: STALL (no damage, unlock all) at flip 8500, 0 laps, race time 40.0 s, 243 s: put back by the game 4 times since the last progress (it left the track at 952, 947, 931, 949 m and was set down at about 518 m; crawling at 290 km/h with Cross held; shield bar 100%); no progress for 20.0 s of race clock; 7 contacts (7 a lap); 35 shield taken and refilled (no damage); last 5 s (t/dist/kmh/off/lx): 35.9/597/288/+9/-0.32 36.9/672/280/+14/+0.50 37.9/745/298/-3/+0.67 38.9/827/297/-5/+0.59 39.9/900/305/+15/-0.37; last: [pure] ship frame 8500 t=241170698 clock=40.005 pos=448.487,101.884,-110.315 vel=13.718,-56.717,-69.152 kmh=325.735 dist=911.157 lap=1 shield=100.000
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | vineta_k | PASS (no damage) | 18240 | 3 | 200.5 | 407 | 2026-10-06 13:58 | results screen at flip 18230 (3 laps: 68.4, 59.6, 63.7 s; 200.4 s at the shot); 43 contacts (15, 13, 15 a lap); 100 shield taken and refilled (no damage) |
| single_race | sinucit | STALL (no damage, unlock all) | 8500 | 0 | 40.0 | 243 | 2026-10-06 14:43 | put back by the game 4 times since the last progress (it left the track at 952, 947, 931, 949 m and was set down at about 518 m; crawling at 290 km/h with Cross held; shield bar 100%); no progress for 20.0 s of race clock; 7 contacts (7 a lap); 35 shield taken and refilled (no damage); last 5 s (t/dist/kmh/off/lx): 35.9/597/288/+9/-0.32 36.9/672/280/+14/+0.50 37.9/745/298/-3/+0.67 38.9/827/297/-5/+0.59 39.9/900/305/+15/-0.37; last: [pure] ship frame 8500 t=241170698 clock=40.005 pos=448.487,101.884,-110.315 vel=13.718,-56.717,-69.152 kmh=325.735 dist=911.157 lap=1 shield=100.000 |
| single_race | citta_nuova | PASS (no damage, unlock all) | 27450 | 3 | 355.9 | 562 | 2026-10-06 12:41 | results screen at flip 27440 (3 laps: 119.4, 116.1, 116.2 s; 355.8 s at the shot); 105 contacts (33, 37, 35 a lap); 255 shield taken and refilled (no damage) |
| single_race | sebenco_climb | PASS (no damage, unlock all) | 25590 | 3 | 323.0 | 526 | 2026-10-06 12:50 | results screen at flip 25580 (3 laps: 101.0, 106.8, 111.0 s; 322.8 s at the shot); 86 contacts (28, 27, 31 a lap); 178 shield taken and refilled (no damage) |
| single_race | sol_2 | PASS (no damage, unlock all) | 21840 | 3 | 263.3 | 472 | 2026-10-06 12:58 | results screen at flip 21830 (3 laps: 87.5, 87.6, 84.4 s; 263.2 s at the shot); 66 contacts (22, 21, 23 a lap); 151 shield taken and refilled (no damage) |
| single_race | karbonis | PASS (no damage, unlock all) | 19000 | 3 | 217.0 | 421 | 2026-10-06 13:05 | results screen at flip 18990 (3 laps: 82.8, 66.2, 62.3 s; 216.9 s at the shot); 64 contacts (22, 20, 22 a lap); 150 shield taken and refilled (no damage) |
| single_race | sagarmatha | PASS (no damage, unlock all) | 18830 | 3 | 209.9 | 416 | 2026-10-06 13:12 | results screen at flip 18820 (3 laps: 71.4, 62.7, 68.0 s; 209.7 s at the shot); 49 contacts (17, 14, 18 a lap); 80 shield taken and refilled (no damage) |
| single_race | manor_top | STALL (no damage, unlock all) | 10470 | 0 | 74.3 | 276 | 2026-10-06 13:17 | stuck on geometry (contact at 2209 m, 52.0 s, 20 km/h lost, +10 m off the line; crawling at 152 km/h with Cross held; shield bar 100%); no progress for 20.0 s of race clock; 26 contacts (26 a lap); 91 shield taken and refilled (no damage); last 5 s (t/dist/kmh/off/lx): 70.2/2048/245/-7/+0.55 71.2/2078/66/-7/+0.55 72.2/2106/136/-6/+0.38 73.2/2155/209/-4/+1.00 74.2/2205/174/+6/+0.73; last: [pure] ship frame 10470 t=275686825 clock=74.304 pos=-24.499,16.032,-432.049 vel=17.576,6.471,41.921 kmh=165.294 dist=2214.284 lap=1 shield=100.000 |
| single_race | mandrashee | PASS (no damage, unlock all) | 20520 | 3 | 238.8 | 447 | 2026-10-06 13:24 | results screen at flip 20510 (3 laps: 79.4, 72.8, 82.3 s; 238.7 s at the shot); 69 contacts (25, 20, 24 a lap); 140 shield taken and refilled (no damage) |
| zone | zone_2 | PASS (unlock all) | 7410 | 0 | 67.7 | 247 | 2026-10-06 14:09 | zone end panel at flip 7400: TOTAL ZONES CLEAR 7; destroyed at flip 7171 (59.8 s of race clock, 443 m), 0 laps; 1 contacts (1 a lap); shield -0.1 at the end, 75 taken |
| zone | zone_3 | PASS (unlock all) | 7490 | 0 | 70.4 | 250 | 2026-10-06 14:13 | zone end panel at flip 7480: TOTAL ZONES CLEAR 7; destroyed at flip 7254 (62.5 s of race clock, 1815 m), 0 laps; 6 contacts (6 a lap); shield -0.1 at the end, 75 taken |
| zone | zone_4 | PASS (unlock all) | 7440 | 0 | 68.8 | 253 | 2026-10-06 13:45 | zone end panel at flip 7430: TOTAL ZONES CLEAR 7; destroyed at flip 7216 (61.3 s of race clock, 1603 m), 0 laps; 3 contacts (3 a lap); shield -0.0 at the end, 75 taken |
verify 032: FAIL (exit 1)
```
The command exits 1: `single_race sinucit` stalls, so `zone zone_2` and `grep -c PASS` do not run. The summary above
holds 10 PASS rows. zone_2's PASS row is from a run with the final code (14:09).

### Open questions
1. **The Verify line.** Should Sinucit stay in it? It stalls at the same spot every run. To pass it needs a better
   follower (the per-flip live read is a vendor change) or Erik's recorded lap of Sinucit. Otherwise the line could
   name a Beta track that passes, for example `citta_nuova`.
2. **The line rule.** The default is the winner's samples within 15 m of its fastest pass (3.84 m from PPSSPP on
   Vineta K). The mean of all AI ships comes closest (1.54 m) but mixes a fork's branches. Should `--port` pick a
   branch per fork and then average the pack on it?
3. **Faster classes.** Flash to Phantom are routed, and their laps are counted and budgeted, but no windowed cell
   ran them. The follower's settings and budgets above Vector are untested.
4. **Other modes.** The sweep picks a league and class only in Single Race. Time Trial, Free Play and Tournament
   have CLASS and LEAGUE screens too (Tournament: TOURNAMENT SELECTION). I did not check their lists with the
   switch, so those modes still cover Alpha at Vector.
5. **Windowed cells must run alone.** A headless recording beside a windowed cell delayed the boot and broke its menu
   route (NO RACE). Should the sweep refuse to start when another PureNative is running?

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
