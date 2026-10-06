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
Status: DONE. The shield is the float at `be::Ship` +0xF8 (100.000 full on the Feisar). The probe prints it as
`shield=`. `PURE_TEST_NO_DAMAGE=1` refills it every flip. With `--no-damage`, Modesto Heights, Chenghou Project
and Blue Ridge each PASS to the results screen. The Verify line exits 0 and its `grep -c PASS` prints 3. No cell
halted.

### The shield field: `be::Ship` +0xF8 (float)
How it was found (Ghidra, read-only from the main checkout; `out/017/dec*.txt`):
- The string `energycritical` leads to FUN_08928274(amount, ship, kind), the damage function. It reads the shield
  through FUN_0892478c, which returns `*(float *)(ship + 0xF8)` in the modes below 9. It writes the shield through
  FUN_089247dc, which clamps it to the ship type's maximum `*(*(ship + 0xC8) + 0x74) + 0x84` and stores it at
  +0xF8. It plays `energycritical` when the shield falls through 20, and at 0 or below it puts the ship in state 4
  (destroyed).
- The collision path is in the ship update FUN_08926ae4: a wall or ship contact calls
  FUN_08928274(impact * 0.05 * 0.7, ship, kind).
- The HUD side:
  - FUN_0892195c (Player.cpp) copies the getter's value and the maximum into the player's HUD data each frame.
  - FUN_0881ebd8 (HUD.cpp, the `Shield3D` element that FUN_08821838 looks up) eases the bar towards
    shield / maximum. Under 20 it turns red and blinks.
  - The setter also drives the HUD's `~CRAFTCRITICAL` warning (FUN_0881e944).

How it was confirmed:
1. With `PURE_WATCH_SHIP=1` it reads full at GO and falls on wall contact. Vineta K, follower, out/017/probe: the
   first-corner barrier, then the barrier at 2430 m after the speed pad:
   ```
   [pure] ship frame 6253 t=201180547 clock=0.018 pos=177.198,37.171,-116.810 vel=-0.972,0.002,0.019 kmh=3.500 dist=1079.340 lap=0 shield=100.000
   [pure] ship frame 6668 t=208103992 clock=6.941 pos=-243.738,44.598,-147.260 vel=-86.609,6.138,-37.779 kmh=340.880 dist=1503.788 lap=1 shield=100.000
   [pure] ship frame 6669 t=208120675 clock=6.958 pos=-245.188,44.701,-147.892 vel=-79.589,5.769,-41.023 kmh=323.011 dist=1505.376 lap=1 shield=99.728
   [pure] ship frame 7508 t=222117712 clock=20.954 pos=-816.107,-149.552,137.862 vel=-11.962,1.016,110.780 kmh=401.143 dist=2429.873 lap=1 shield=94.706
   [pure] ship frame 7509 t=222134395 clock=20.971 pos=-816.332,-149.536,139.823 vel=-29.507,0.519,26.590 kmh=143.003 dist=2431.725 lap=1 shield=91.694
   ```
   - Over the first 11 contacts it fell from 100 to 77.4, and it never rose.
   - In a run without the switch (Modesto Heights, below) it reached -0.421, and the game showed "SHIP DESTROYED".
2. Writing the field changes the game. A local, uncommitted build wrote 1.0 there instead of the maximum
   (out/017/destroyed). The ship was destroyed at its first wall, at 6.22 s (`shield=-0.918`), and the
   "SHIP DESTROYED" panel came up 5 s later. That rules out a copy of the shield.

### Summary rows
The Verify run (out/sweep/summary.txt; the switch on, the committed steering tables, budget 17000):

| Cell | Outcome | Laps (s) | Contacts (a lap) | Shield taken (refilled) | Flip (budget ends at) | Real s |
|---|---|---|---|---|---|---|
| modesto_heights | PASS (no damage) | 94.3, 83.8, 86.5 | 73 (25, 21, 27) | 135 | 22380 (23100) | 472 |
| chenghou_project | PASS (no damage) | 89.1, 87.2, 83.2 | 72 (24, 25, 23) | 150 | 22020 (23100) | 465 |
| blue_ridge | PASS (no damage) | 86.4, 89.8, 88.0 | 61 (19, 20, 22) | 126 | 22360 (23100) | 470 |

Two more runs, run after the Verify run, check the tool without the switch:

| Cell | Outcome | Detail |
|---|---|---|
| vineta_k (out/sweep, default budget 13000) | PASS | flip 17830; laps 63.4, 59.6, 63.8 s; 42 contacts (15, 11, 16); shield 13.3 at the end, 87 taken |
| modesto_heights (`--out out/017/damage`) | STALL | `eliminated by damage ("SHIP DESTROYED" title, probe shield -0.4; shield bar 0%; at rest with Cross held)`; destroyed 86.5 s into lap 2 (lap 1 93.4 s), after 60 contacts (27, 33); 37.6 shield lost in lap 1 |

After those runs the summary holds four PASS rows: Vineta K without the switch, and the three cells with it.

### Changed
- `src/profile/pure_profile.cpp`:
  - `shield=` on the probe line, read from `be::Ship` +0xF8;
  - `PURE_TEST_NO_DAMAGE=1` writes the ship type's maximum back into +0xF8 before every flip and prints
    `[pure] TEST SWITCH: no damage ...` once at start-up;
  - the player-ship lookup is now shared by the probe and the switch;
  - comments for the field and its functions.
- `tools/campaign_sweep.py`:
  - a per-track budget in `MODES` (`frames`: 13000 for Vineta K, 17000 for the other three), used when `--frames`
    is not given;
  - `--no-damage`: sets the switch, and marks the summary row's outcome `(no damage)`;
  - the "SHIP DESTROYED" title check (`TITLE_REGION`, `DESTROYED_TITLE`: the title row's lit columns, which allow
    8 columns of difference). The damage class now needs the title or the probe's shield at 0 or below; the shield
    bar alone no longer decides it;
  - the probe's shield in the trace, the stall CSV and the detail (shield at the end and shield taken; with the
    switch, the shield taken and refilled).
- `README.md`:
  - the probe row now lists `shield`;
  - the sweep row lists the budgets and `--no-damage`;
  - a new "Test switches (never for play)" heading with the `PURE_TEST_NO_DAMAGE` row.
- `docs/tracks.md`: the probe's `shield`, how a stall is classed, a section on the shield (the functions), and
  the no-damage runs with their table.
- `docs/tasks/017-sweep-no-damage.md`: this Result.

### Verify output (last 20 lines)
```
[sweep] single_race-blue_ridge: shot f22041: TOTAL label variance 521, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22071: TOTAL label variance 235, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22101: TOTAL label variance 52, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22131: TOTAL label variance 313, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22161: TOTAL label variance 304, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22191: TOTAL label variance 3, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22221: TOTAL label variance 3011, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22251: TOTAL label variance 3142, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22281: TOTAL label variance 3219, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22311: TOTAL label variance 3527, steady False (0 in a row)
[sweep] single_race-blue_ridge: shot f22341: TOTAL label variance 3691, steady True (1 in a row)
[sweep] single_race-blue_ridge: PASS (no damage) at flip 22360, 3 laps, race time 269.5 s, 470 s: results screen at flip 22350 (3 laps: 86.4, 89.8, 88.0 s; 269.3 s at the shot); 61 contacts (19, 20, 22 a lap); 126 shield taken and refilled (no damage)
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | modesto_heights | PASS (no damage) | 22380 | 3 | 270.4 | 472 | 2026-10-05 23:43 | results screen at flip 22370 (3 laps: 94.3, 83.8, 86.5 s; 270.3 s at the shot); 73 contacts (25, 21, 27 a lap); 135 shield taken and refilled (no damage) |
| single_race | chenghou_project | PASS (no damage) | 22020 | 3 | 264.3 | 465 | 2026-10-05 23:50 | results screen at flip 22010 (3 laps: 89.1, 87.2, 83.2 s; 264.1 s at the shot); 72 contacts (24, 25, 23 a lap); 150 shield taken and refilled (no damage) |
| single_race | blue_ridge | PASS (no damage) | 22360 | 3 | 269.5 | 470 | 2026-10-05 23:58 | results screen at flip 22350 (3 laps: 86.4, 89.8, 88.0 s; 269.3 s at the shot); 61 contacts (19, 20, 22 a lap); 126 shield taken and refilled (no damage) |
3
```
The command exited 0. Each cell's log has `[pure] TEST SWITCH: no damage`. None has an `[hle-stub]` or
`unsupported` line, and the only runtime stop is the sweep's own quit ("window closed").

### Open questions
1. **Budget margin.** At 17000, the three runs finished 720 to 1080 flips (12 to 18 s) before the budget ran out.
   A slower race would TIMEOUT. Raise the three to 18000 (above the brief's 16000 to 17000)?
2. **Vineta K is close to the line.** Its pass without the switch ended with 13.3 shield left after 42 contacts.
   Task 016's 3/3 had 37 to 47 contacts, so one or two bad laps would destroy the ship. Should the sweep run
   Vineta K with `--no-damage` too, and count damage-free passes separately?
3. **Absorbing does nothing.** Square every 2 s (`absorb 2`) never raised the shield in either run without the
   switch (0 rises in 11568 and 11939 probe lines). The game's add path is FUN_08923b9c, and the follower
   probably never holds a pickup to absorb. Worth a check only if real races matter.
4. **The game put the ship back.** On Chenghou Project it did this twice (46.5 s, 3965 m to 3755 m; 154.2 s,
   128 m to 4663 m). Each time the ship was going backwards along the track, and in the two frames before the
   put-back the shield fell by 8 and then 13. The run still passed, but these
   are follower failures (wrong-way recovery) that cost time.
5. **The title signature** comes from one render size (960x544, scaled through `imgdiff.scale_region`). Another
   window size has not been tried.

## Review
(Fable fills)
