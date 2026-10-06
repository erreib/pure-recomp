# 017: Shield probe and a test-only no-damage switch for the sweep

Milestone: M5 | Branch: task/017-sweep-no-damage | Status: OPEN

## Goal
The follower cannot keep the shield alive on Modesto Heights, Chenghou Project and Blue Ridge (task 016: ~20
contacts a lap, "SHIP DESTROYED" in lap 2 or 3). The sweep's job is to run every track to its results screen to
find halts, not to race well. Add (1) the shield value to the ship probe and (2) a switch, for the sweep only, that
keeps the player's shield full; then run the three tracks to PASS. The switch is a test instrument and is named and
documented as such; it is never on by default.

## Read first
- CLAUDE.md, docs/tasks/016-sweep-reliability.md (Result: the shield bar, the stall classes, the dump of the race
  records), docs/tasks/007-same-input-race-compare.md (be::Ship layout found so far: vtable 0x08AC259C at +0x3c,
  +0x480 index, +0x488 kind, +0xcc AI flag, matrices at +0x40/+0x80), src/profile/pure_profile.cpp (`watch_ship`),
  config/function_labels.csv (functions labelled `Ship.cpp`, `HUD.cpp`, `Collision.cpp`), tools/ghidra_headless.sh
  (`script Decompile`/`Callers` from the main checkout, read-only)

## Deliverable
1. Find the shield (energy) field: the HUD draws the shield bar from it (`HUD.cpp` functions), the collision code
   decrements it. Ghidra: decompile the HUD bar function and the collision damage path; confirm by watching the
   candidate field in `PURE_WATCH_SHIP` output during a wall contact (it must fall on contact and read full at GO).
   Add `shield=` to the probe line.
2. `PURE_TEST_NO_DAMAGE=1`: in the flip wrapper, write the full value back into the player's shield field each flip
   when the switch is set; print a `[pure] TEST SWITCH: no damage` line once at start-up. README row under a
   "Test switches (never for play)" heading.
3. `tools/campaign_sweep.py`: per-track budgets in MODES (16000-17000 flips for the longer tracks), a
   "SHIP DESTROYED" title check for the damage class, and a `--no-damage` flag that sets the switch and marks the
   summary row with `(no damage)`.
4. Run Modesto Heights, Chenghou Project and Blue Ridge with `--no-damage` to PASS; keep Vineta K's result without it.

## Acceptance criteria
- [ ] `PURE_WATCH_SHIP=1` prints a shield value that falls on wall contact and is full at GO (show three lines).
- [ ] Each of the three tracks PASSes with `--no-damage` (summary rows marked); any halt is recorded as the cell's
      outcome.

## Verify
`python3 tools/campaign_sweep.py single_race modesto_heights --no-damage && python3 tools/campaign_sweep.py single_race chenghou_project --no-damage && python3 tools/campaign_sweep.py single_race blue_ridge --no-damage && grep -c 'PASS' out/sweep/summary.txt`

## May touch
- src/profile/pure_profile.cpp (probe field, the switch), tools/campaign_sweep.py, config/pad_scripts/drive/,
  docs/tracks.md, README.md, tools/ghidra/ (new scripts only)

## Must not touch
- vendor/, patches/, tools/run_boot.py, tools/imgdiff.py, config/*.csv

## Estimated turns
50

## Escalate when
The shield field cannot be confirmed within 20 turns (report candidates and stop), or a track halts the game (record
and move on).

## Result
(worker fills)

## Review
(Fable fills)
