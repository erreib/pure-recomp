# 018: The other campaign modes in the sweep (Time Trial, Free Play, Zone, Tournament)

Milestone: M5 | Branch: task/018-campaign-modes | Status: OPEN (after task 017)

## Goal
The sweep runs Single Race only. The campaign milestone covers every single-player mode. Add menu routes and cell
definitions for Time Trial, Free Play, Zone and Tournament (Alpha league), run each on Vineta K (Zone on its first
Zone track) to its results screen with the test-only no-damage switch where needed, and record what each mode's
results screen looks like and how the sweep detects it. Tournament chains races and needs the ENTER TAG prompt
answered between them.

## Read first
- CLAUDE.md, docs/tasks/016-sweep-reliability.md and 017-sweep-no-damage.md (Results), docs/tracks.md,
  tools/campaign_sweep.py (MODES, results detection, the follower), config/pad_scripts/single_race.txt,
  docs/research.md (modes: Single Race, Tournament, Time Trial, Free Play, Zone; Time Trial/Zone/Free Play are
  30 fps locked, Single Race/Tournament target 60: the sweep's flip-to-time assumptions change)

## Deliverable
1. Routes from MAIN MENU for each mode (DOWN presses on the Single Player menu, then the mode's own screens; Zone has
   no class/ship choice the same way; Time Trial may ask for a ghost), with a `<cell>-menu` shot to prove the
   track list, and the mode's frame budget in MODES.
2. Results detection per mode: Time Trial and Free Play results, Zone's "ZONE n" end screen (Zone ends when the
   ship is destroyed by design, so no-damage must be OFF for Zone and the sweep must accept SHIP DESTROYED as the
   normal end there), Tournament's standings screen between races and the ENTER TAG answer (Cross on the default
   tag) to continue to the next race; a Tournament cell PASSes when the final standings appear.
3. Run: time_trial/vineta_k, free_play/vineta_k, zone/<first zone track>, tournament/alpha (all four races). Record
   lap/zone counts and any halt.

## Acceptance criteria
- [ ] Each mode has a summary row with PASS or a recorded stop reason; Zone's row records the zone reached.
- [ ] The Tournament cell reaches the final standings or records which race stopped it.

## Verify
`python3 tools/campaign_sweep.py time_trial vineta_k && python3 tools/campaign_sweep.py zone zone_1 && grep -c PASS out/sweep/summary.txt`

## May touch
- tools/campaign_sweep.py, config/pad_scripts/ (new route files), docs/tracks.md, README.md (the sweep row)

## Must not touch
- src/, vendor/, patches/, tools/run_boot.py

## Estimated turns
60

## Escalate when
A mode halts the game (stub, unsupported instruction, runtime stop other than the frame exit): record it and move
on; stop entirely only if the main menu route breaks.

## Result
Status: DONE. All four modes run from MAIN MENU to their end screens, and every cell PASSes:
- Time Trial and Free Play on Vineta K;
- Zone on PRO TOZO (`zone_1`, the only Zone track on a new profile), which ends at TOTAL ZONES CLEAR 6;
- the Alpha Tournament, all four races, which ends on the final TOURNAMENT STANDING.

`<cell>-menu` shots prove each route. No cell halted. The Verify line exits 0, and its `grep -c PASS` prints 4.
The WIP's four routes reached their races at the flips their files give. The sweep needed six fixes (below). One of
them replaced the Tournament's end rule: the first Tournament run passed on the wrong screen.

### Cells (2026-10-06)
| Cell | Switch | Outcome | Laps (s) or zones | Contacts (a lap) | Shield taken | Flip (exit at) | Real s |
|---|---|---|---|---|---|---|---|
| time_trial/vineta_k | no damage | PASS | 81.8, 67.5, 73.6 | 68 (26, 20, 22) | 65 | 12830 (13900) | 428 |
| time_trial/vineta_k (Verify; the summary's row) | off | PASS | 68.1, 62.0, 68.2 | 60 (19, 17, 24) | 57 (42.9 left) | 12090 (14900) | 404 |
| free_play/vineta_k | no damage | PASS | 73.6, 68.5, 75.9 | 68 (23, 23, 22) | 65 | 12810 (14900) | 428 |
| zone/zone_1 | off | PASS: TOTAL ZONES CLEAR 6, ship destroyed at 59.2 s | 0 laps | 1 | 75 (all) | 7390 (14250) | 248 |
| zone/zone_1 (Verify; the summary's row) | off | PASS: TOTAL ZONES CLEAR 6, destroyed at 59.2 s | 0 laps | 1 | 75 (all) | 7390 (14250) | 247 |
| tournament/alpha, run 1 | no damage | all four races reached their results panels; the WIP's end rule then passed on the SINGLE PLAYER menu after the tournament (rule replaced, cell run again) | 63.9, 58.5, 57.2; 93.1, 91.6, 94.8; 76.7, 88.5, 84.2; 80.1, 91.4, 94.3 | 47, 78, 69, 62 | 92, 141, 134, 135 | 70620 (85850) | 1298 |
| tournament/alpha, run 2 (the summary's row) | no damage | PASS: TOURNAMENT STANDING after race 4 at flip 70790 (after races 1 to 3 at 17730, 35930, 52900) | 58.5, 63.5, 54.6; 94.1, 88.8, 94.2; 80.8, 86.8, 93.4; 94.4, 93.6, 86.7 | 42, 80, 69, 70 | 72, 166, 162, 137 | 70800 (85850) | 1297 |

Lap counts:
- Every Time Trial, Free Play and Tournament race ran its 3 laps (the Tournament 12 in all).
- Zone ran 0 laps. The ship hit the first corner's barrier at 227 m, 3.5 s in, and stayed against it at 279 m.
  Its shield (75 at the start) ran out there at 59.2 s.

### Routes (MAIN MENU, then DOWN presses on SINGLE PLAYER) and the menu shots
| Mode | DOWN | Screens | `<cell>-menu` shot | Cross held from | Race flips a second | Budget (flips) |
|---|---|---|---|---|---|---|
| Tournament | 1 | CLASS, TOURNAMENT SELECTION, TEAM (no track screen) | TOURNAMENT SELECTION: ALPHA alone, its panel listing the four tracks | 5850 | 60 | 80000 for the four races |
| Time Trial | 2 | CLASS, LEAGUE, TRACK, TEAM (no ghost question on a new profile) | TRACK SELECTION: the four Alpha tracks, RACE and LAP RECORD, gold, silver and bronze 2:04.00, 2:07.00, 2:10.00 | 5900 | 30 | 9000 Vineta K, 11000 the others |
| Zone | 3 | TRACK SELECTION only | PRO TOZO alone, BEST ZONE, BEST SCORE, targets 25, 20, 15 | 5250 | 30 | 9000 |
| Free Play | 4 | CLASS, LEAGUE, TRACK, TEAM | TRACK SELECTION: the four tracks, the records, LENGTH 4446 M, HEIGHT 222 M | 5900 | 30 | 9000 Vineta K, 11000 the others |

### End screens and how the sweep detects them
- **Time Trial.** TIME TRIAL COMPLETED: LAP 1 to 3 (the best in yellow, LR and RR marks), TOTAL and ENTER TAG,
  over the track, 3.5 s after the line. Detected by Single Race's TOTAL label rule (`RESULTS_TOTAL` drawn and
  unchanged in two shots in a row).
- **Free Play.** There is no last lap: the HUD's LAP counter goes on (LAP 4).
  - After three laps the sweep presses Start, DOWN, DOWN (the menu: CONTINUE, RESTART, END SESSION, PRESS X TO
    CONFIRM) and Cross.
  - FREE PLAY SESSION RESULTS comes up 4 s later: the laps best first, TOTAL LAPS 3, ENTER TAG.
  - Its TOTAL LAPS label sits where TOTAL is, so the same rule finds it. Shots taken before END SESSION's Cross are
    skipped.
- **Zone.** The ship's destruction is the normal end: the stall rule is off and `--no-damage` is ignored.
  - The probe's shield at 0 marks the end.
  - The SHIP DESTROYED panel comes up 7 s later: TOTAL ZONES CLEAR, TOTAL LAPS CLEAR, PERFECT ZONES, PERFECT LAPS,
    TOP SPEED, SCORE, ENTER TAG.
  - The title (`DESTROYED_TITLE`) in two shots in a row is PASS. TOTAL ZONES CLEAR is read from the panel
    (`ZONES_VALUE`, `read_digits`) into the summary: 6, as drawn (TOP SPEED 405.14, SCORE 4293).
- **Tournament.** Each race's results panel ("BAD LUCK... 6TH", laps, TOTAL, ENTER TAG) is found by the TOTAL
  label rule. The sweep then presses Cross every 120 flips through these screens:
  1. ENTER TAG, one letter a press (three presses for AAA);
  2. PRESS X TO CONTINUE;
  3. RACE n OF 4 (team, time, points);
  4. TOURNAMENT STANDING (team, points);
  5. PROFILE AUTOSAVED;
  6. NEXT RACE / QUIT TOURNAMENT.

  A new player object appears about 1010 flips after the panel. The next race starts when it stands on its grid
  (lap 0, clock 0), about 1280 flips after the panel. The sweep then holds Cross again and steers with that track's
  table.

  After race 4 the screens are RACE 4 OF 4, TOURNAMENT STANDING (the final standings), END TOURNAMENT ("8TH -
  COMMISERATIONS. HAVE ANOTHER GO!"), PROFILE AUTOSAVED, then MAIN MENU. The TOURNAMENT STANDING title
  (`STANDING_TITLE`) after race 4 is PASS. The detail also records the standings after each race.

### Fixes to the WIP
1. **The Tournament end rule.** The WIP waited for a still screen: two shots in a row equal over the whole screen.
   Every screen between races is drawn over a moving fly-by, so the first still screen was the SINGLE PLAYER menu
   after the tournament (run 1). It is now the TOURNAMENT STANDING title. Shots of that screen differ from
   `STANDING_TITLE` by 0 to 3 columns; the results panel's title differs by 104.
2. **Between races.**
   - The replay's ship lines no longer feed the finished race, where they could have added laps.
   - The next race now starts at the first grid line after a new player object. Before, only the object's very
     first line could start it.
3. **STUCK.** The cell stops when no next grid and no final standings come within 4800 flips of a race's results.
4. **Shot timing after the finish.** The shots are now timed by the frame log as well as the probe. The probe
   prints only while the record changes, and Free Play's pause menu and Zone's destroyed ship stop it.
5. **The slow shots** go 3 flips late. A second shot in the same flip is lost: Time Trial's `ref` shot went
   missing in its first run.
6. **Budgets.**
   - Time Trial and Free Play: 9000 for Vineta K and 11000 for the others. The first Time Trial run used 6800 of
     the WIP's 8000.
   - Tournament: 80000 (13000 + 3 * 18000, plus the screens between races). Run 2 used 64950.

### Changed
- `tools/campaign_sweep.py`:
  - MODES rows for `time_trial`, `free_play`, `zone` and `tournament`: route, Cross-hold flip, flips a second,
    end rule, budgets and the Tournament's race order;
  - each mode's end detection (from the WIP) with the fixes above;
  - `STANDING_TITLE` and `STANDING_REGION`, `ADVANCE_LIMIT` and the STUCK outcome;
  - the docstring.
- `config/pad_scripts/time_trial.txt`, `free_play.txt`, `zone.txt` and `tournament.txt` (new): the routes.
- `config/pad_scripts/drive/zone_1.txt` (new): no steering, with notes.
- `docs/tracks.md`: a section on the other modes (routes, menu shots, 30 fps, end screens and their detection, Zone
  without steering, the runs) and the note on task 017's budgets.
- `README.md`: the sweep row.

### Verify output (last 20 lines)
```
[sweep] zone-zone_1: shot f7243: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7258: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7273: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7288: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7303: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7318: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7333: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7348: SHIP DESTROYED title False (0 in a row)
[sweep] zone-zone_1: shot f7363: SHIP DESTROYED title True (1 in a row)
[sweep] zone-zone_1: shot f7378: SHIP DESTROYED title True (2 in a row)
[sweep] zone-zone_1: PASS at flip 7390, 0 laps, race time 67.1 s, 247 s: zone end panel at flip 7380: TOTAL ZONES CLEAR 6; destroyed at flip 7153 (59.2 s of race clock, 279 m), 0 laps; 1 contacts (1 a lap); shield -0.1 at the end, 75 taken
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| time_trial | vineta_k | PASS | 12090 | 3 | 202.8 | 404 | 2026-10-06 03:11 | results screen at flip 12080 (3 laps: 68.1, 62.0, 68.2 s; 202.5 s at the shot); 60 contacts (19, 17, 24 a lap); shield 42.9 at the end, 57 taken |
| free_play | vineta_k | PASS (no damage) | 12810 | 3 | 222.8 | 428 | 2026-10-06 02:14 | results screen at flip 12800 (3 laps: 73.6, 68.5, 75.9 s; 222.5 s at the shot); 68 contacts (23, 23, 22 a lap); 65 shield taken and refilled (no damage) |
| zone | zone_1 | PASS | 7390 | 0 | 67.1 | 247 | 2026-10-06 03:15 | zone end panel at flip 7380: TOTAL ZONES CLEAR 6; destroyed at flip 7153 (59.2 s of race clock, 279 m), 0 laps; 1 contacts (1 a lap); shield -0.1 at the end, 75 taken |
| tournament | alpha | PASS (no damage) | 70800 | 12 | 1011.8 | 1297 | 2026-10-06 02:59 | final standings (TOURNAMENT STANDING after race 4) at flip 70790; race 1 vineta_k: 3 laps: 58.5, 63.5, 54.6 s, 42 contacts (16, 12, 14 a lap); 72 shield taken and refilled (no damage), TOURNAMENT STANDING at flip 17730; race 2 modesto_heights: 3 laps: 94.1, 88.8, 94.2 s, 80 contacts (28, 25, 27 a lap); 166 shield taken and refilled (no damage), TOURNAMENT STANDING at flip 35930; race 3 chenghou_project: 3 laps: 80.8, 86.8, 93.4 s, 69 contacts (20, 22, 27 a lap); 162 shield taken and refilled (no damage), TOURNAMENT STANDING at flip 52900; race 4 blue_ridge: 3 laps: 94.4, 93.6, 86.7 s, 70 contacts (26, 22, 22 a lap); 137 shield taken and refilled (no damage), TOURNAMENT STANDING at flip 70790 |
4
```
The command exited 0. The summary holds this worktree's four cells, all PASS: Time Trial's and Zone's rows are the
Verify runs, without the switch; Free Play's and Tournament's are runs with it.

Every log has the same clean ending: no `[hle-stub]` and no `unsupported` line. The only runtime stop is the sweep's
own quit ("window closed").

### Open questions
1. **Zone stops at zone 6.** The ship stands against the first corner's barrier from about 8 s until its shield
   runs out. Zone has no AI ships to record a line from. A recorded lap of PRO TOZO would let the follower drive
   it: for example a lap driven by hand in PPSSPP, logged with `tools/pp_lines.py`'s probe. Is that worth a task?
2. **The follower in the 30-fps modes.** The live file is read every 10 flips, which is a third of a second at 30
   flips a second. On Vineta K the follower took 60 to 68 contacts in these modes, against 37 to 47 in Single
   Race. Vineta K still passes without the switch (42.9 shield left), but the other tracks would need
   `--no-damage`. A per-flip live read is still a vendor change.
3. **Untested pieces.**
   - Only Vineta K was run in Time Trial and Free Play. The other tracks' 11000 budgets are estimates from their
     Single Race laps.
   - Free Play's no-lap END SESSION ending (the RETURN TO MAIN MENU banner, `MENU_BANNER`) comes from the cut-off
     worker's run. Its captures are gone, and these runs never reached that ending.

## Review
(Fable fills)
