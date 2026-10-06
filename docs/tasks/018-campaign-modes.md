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
(worker fills)

## Review
(Fable fills)
