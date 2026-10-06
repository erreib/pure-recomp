# 016: Sweep reliability and the Alpha league

Milestone: M5 | Branch: task/016-sweep-reliability | Status: MERGED (partial)

## Goal
Task 012's follower finishes Vineta K once in two tries. Make the Vineta K cell pass three times in a row, then add
Modesto Heights, Chenghou Project and Blue Ridge with their own AI lines. Keep the stall diagnosis in the tool.

## Read first
- CLAUDE.md, docs/tasks/012-campaign-sweep.md (both Results and the Review decisions), docs/tracks.md,
  tools/campaign_sweep.py, tools/pp_lines.py, config/pad_scripts/drive/vineta_k.txt and vineta_k.line.csv

## Deliverable
1. STALL diagnosis: a `shot stall` before the quit, and the last 5 s of the trace in the summary detail; classify
   the stall (eliminated by damage: shield energy; stuck on geometry; off the line) from the shot and the ship
   record (find the shield/energy field near the race record if it exists: the HUD's energy bar).
2. Fewer contacts on Vineta K: tune preview/offset gains, use the airbrakes (`pad leftshoulder`/`rightshoulder`
   through the live file) where the line needs more than full lock, lift the throttle before the tightest corners;
   target under 10 contacts a lap. Measure the pass rate: three consecutive `--frames 13000` runs must PASS.
3. Modesto Heights, Chenghou Project, Blue Ridge: record the AI line (`tools/pp_lines.py <track> --downs N`), export,
   `follow` line, one PASS each (more if time allows); record lengths and start lines in docs/tracks.md.

## Acceptance criteria
- [ ] Vineta K: 3/3 PASS at `--frames 13000` (list the three run times and contact counts).
- [ ] At least two more Alpha tracks PASS once each; every attempted cell is in the summary with its outcome.

## Verify
`for i in 1 2 3; do python3 tools/campaign_sweep.py single_race vineta_k --frames 13000 || exit 1; done; grep -c PASS out/sweep/summary.txt`

## May touch
- tools/campaign_sweep.py, tools/pp_lines.py, config/pad_scripts/drive/, docs/tracks.md, README.md (the sweep row)

## Must not touch
- src/, vendor/, patches/, tools/run_boot.py, tools/imgdiff.py

## Estimated turns
60

## Escalate when
A track halts the game (stub, unsupported instruction, runtime stop other than the frame exit): record the cell and
move on; stop entirely only if Vineta K cannot reach 2/3 after ten tuning runs (report the contact pattern).

## Result
Status: PARTIAL. Vineta K passes three times in a row at `--frames 13000` (the Verify line exits 0), with 37, 47
and 39 contacts. The stall diagnosis is in the tool and has classified every stop since. The other three Alpha
tracks have recorded AI lines and steering tables, but none has passed: on them the ship takes about 20 contacts
a lap, its shield runs out, and the game shows "SHIP DESTROYED" in lap 2 or 3. Contacts on Vineta K stay at 11 to
18 a lap, above the brief's target of 10.

### Vineta K: the three Verify runs
Steering: `follow config/pad_scripts/drive/vineta_k.line.csv 0.8 0.8 recover=60 absorb=2` (wn 0.8, preview
0.8 s, dead-zone mapping, recovery below 60 km/h, Square every 2 s), strict, no interpreter.

| Run | Outcome | Race time | Laps (s) | Contacts (a lap) | Real time |
|---|---|---|---|---|---|
| 1 (22:42) | PASS at flip 17070 | 182.4 s | 60.4, 59.1, 57.7 | 37 (12, 12, 13) | 385 s |
| 2 (22:48) | PASS at flip 17910 | 195.3 s | 65.8, 60.4, 57.2 | 47 (18, 15, 14) | 398 s |
| 3 (22:55) | PASS at flip 17750 | 192.9 s | 69.4, 61.3, 58.4 | 39 (13, 15, 11) | 394 s |

A contact is the sweep's rule: the speed falls by 20 km/h or more within 0.25 s of race clock, from at least
80 km/h, with 1 s between contacts. It catches walls, other ships and weapon hits. Task 012 counted its 30 contacts
another way, so the numbers do not compare.

### Every cell run (2026-10-05)
Vineta K tuning runs (`--frames 13000`, `--out out/sweep/<run>`). Runs stopped by hand were stopped once their
first lap showed the setting was no better.

| Run | Settings (follow options) | Outcome | Contacts |
|---|---|---|---|
| A | task 012's (wn 1.0, preview 0.3, no dead-zone mapping) | PASS 192.6 s (65.1, 56.5, 63.8) | 43 (14, 13, 16) |
| B | A + preview 0.5, airbrake 1.1, lift 1.0 | STALL at 58.8 s, lap 1, 2690 m: a 10 km/h crawl (both triggers left pressed by `axis ... 0`) | 7 |
| C | dead-zone mapping (yaw 0.8, deadzone 0.3), wn 1.0, preview 0.3 | PASS 189.3 s (65.7, 60.4, 56.9) | 50 (15, 20, 15) |
| D | C with wn 1.3, preview 0.5 | lock to lock from the start; stopped by hand at 25 s | |
| E | predictor lag 0.8, wn 0.8, recover 60 | stopped by hand before the race (the offline model rated it poorly) | |
| F | wn 0.8, preview 0.8, recover 60 | PASS 195.8 s (66.1, 59.1, 61.7) | 40 (11, 15, 14) |
| G | predictor lag 0.9, yaw 1.2, wn 0.9, recover 60 | mean offset 12.6 m in the first lap; stopped by hand at 64 s | 10 in lap 1 |
| H | yaw 1.0, preview 0.5, wn 0.8, recover 60, vmax 360 | STALL at 38.1 s, 2420 m: 10 km/h crawl (triggers as in B) | 5 |
| I | F + vmax 360 | STALL at 29.6 s, 1664 m: the same | 2 |
| J | I with the trigger release fixed | 18 contacts in the first lap; stopped by hand at 65 s | 18 in lap 1 |
| K | H with the trigger release fixed | STALL at 68.1 s, lap 1 (past the wrap), 266 m: Cross lifted for good (a release and a hold read in one batch), the ship coasted to rest | 13 |
| L | yaw 1.0, preview 0.5, wn 0.8 | 12 contacts in lap 1; stopped by hand at 78 s | 12, 5 |
| M | F without recover | STALL at 33.8 s, 1914 m: nosed square into the outer barrier, at rest, Cross held, lx 0 | 1 |
| Verify 1-3 | F + absorb 2 (the committed table) | PASS, PASS, PASS (above) | 37, 47, 39 |

The other Alpha tracks (`out/sweep/`; the summary keeps the latest row of each cell):

| Cell | Settings | Budget | Outcome |
|---|---|---|---|
| modesto_heights | F | 13000 | TIMEOUT at flip 19100: 2 laps in 190 s, 53 contacts (28, 24), at rest at 1010 m at the end |
| modesto_heights | F + absorb 1.5 hold 40 | 20000 | stopped by hand at about 70 s (shield bar 71% by then) |
| modesto_heights | F + vmax 250 | 24000 | STALL, lap 3: eliminated by damage (shield bar 0%), 103 counted contacts (braking counted then) |
| modesto_heights | F + absorb 2 (committed table; the summary's row) | 20000 | STALL, lap 2 at 4052 m: eliminated by damage, 50 contacts (27, 23) |
| chenghou_project | F | 20000 | STALL, lap 3 at 4638 m: eliminated by damage ("SHIP DESTROYED", laps 86.8, 74.2 s), 53 contacts (22, 16, 15) |
| chenghou_project | F + absorb 2 | 20000 | STALL, lap 3 at 764 m: eliminated by damage, 62 contacts (21, 19, 22); the shield fell steadily from 100% to 0% in shots every 15 s |
| chenghou_project | F + vmax 250, absorb 1.5 hold 40 | 24000 | STALL, lap 2: classed eliminated by damage (shield bar 0%) while moving backwards at 110 to 175 km/h; the shot was overwritten by the next run, so not checked |
| chenghou_project | F + absorb 2 (committed table) | 20000 | STALL, lap 3 at 855 m: eliminated by damage, 67 contacts (21, 23, 23) |
| chenghou_project | F + use 2 (Circle every 2 s; `--out out/sweep/U`) | 20000 | STALL, lap 3 at 4627 m: eliminated by damage, 56 contacts (19, 20, 17); the shield fell as without it |
| chenghou_project | committed table (`--out out/sweep/X`) | 20000 | STALL, lap 2 at 329 m: eliminated by damage, 48 contacts (23, 25) |
| chenghou_project | committed table (the summary's row) | 20000 | STALL, lap 3 at 2374 m: eliminated by damage, 48 contacts (19, 23, 6) |
| blue_ridge | F | 20000 | STALL, lap 2 at 4201 m: eliminated by damage, 40 contacts (20, 20) |
| blue_ridge | F + absorb 1.5 hold 40 | 20000 | stopped by hand at about 70 s (shield bar 74% by then) |
| blue_ridge | F + vmax 250 | 24000 | STALL at 67.1 s, lap 1: at 2360 m the capped ship fell and the game put it back at about 1960 m, three times |
| blue_ridge | F + absorb 2 (committed table) | 20000 | STALL, lap 3 at 1667 m: eliminated by damage ("SHIP DESTROYED", laps 1:22.65, 1:30.04), 48 contacts (18, 22, 8) |
| blue_ridge | committed table (the summary's row) | 20000 | STALL, lap 3 at 4106 m: eliminated by damage, 58 contacts (20, 23, 15) |

No cell halted: no `[hle-stub]`, unsupported instruction or runtime stop on any of the four tracks.

### Findings
1. **Stall diagnosis.** On STALL the sweep takes a `stall` shot, then quits. It reads the HUD's shield bar from
   the shot (the cyan bar under the speed bar, `SHIELD_BAR`; a `ref` shot 600 flips in reads 100% in every run)
   and classifies the stop from the shot, the contacts and the trace. The summary detail carries the class, the
   contacts a lap and the last 5 s of the trace, one row a second; `<cell>.stall.csv` holds those 5 s in full.
   Classes seen:
   - eliminated by damage: "SHIP DESTROYED" with the lap times and ENTER TAG, the HUD gone. Seen on Chenghou
     Project, Blue Ridge and Modesto Heights. Task 012's lap-3 stop (speed run down over 6 s with no impact, then
     at rest with Cross held) fits this.
   - stuck on geometry: the ship nosed into a barrier, Cross held, engine lit, shield mostly full.
   No shield field was found in the race records. `tools/pp_lines.py --dump` recorded +-0x1C0 around every entry
   in two races: a Vineta K race with the player driving into a barrier, and a Modesto Heights race. No field
   starts equal for all ships and only falls, apart from +0x48, which reads as the first lap time in 1/100 s. The
   shield probably lives in `be::Ship`, and the probe that would print it is under `src/`.
2. **The stick's dead zone** was the main cause of task 012's contacts. Under |lx| 0.3 the ship does not turn;
   past it the yaw rate is about 1.15 * (|lx| - 0.3) rad/s. The loop's offset correction stayed inside the dead
   zone below about 20 m, so the ship ran 10 to 13 m off the line for seconds at a time (71% of run A more than
   10 m off). `Tuner.stick()` maps through the dead zone.
3. **The lag limits the follower.** A fit to run C gives about 0.3 s from writing a step to the heading moving,
   then a 0.5 s lag. With the mapping, wn 1.0 swings 15 to 20 m either way and wn 1.3 goes lock to lock. wn 0.8
   with preview 0.8 is the calmest setting found (mean offset 8.7 m). A Smith predictor (`lag`) looked good in an
   offline model but was worse in the game.
4. **Live-file control pitfalls.**
   - `axis lefttrigger 0` leaves L pressed; release with -1.
   - A `pad a 1` (lift) and a `pad a N` (hold) read in the same 10-flip batch run in the same frame. The 1-frame
     release then lifts Cross for good.
   Both bugs looked like "a 10 km/h crawl with Cross held" and cost runs B, H, I and K. Both are fixed: release
   with -1, and send the hold as `2:pad a N`.
5. **Damage decides the other tracks.** The shield fell about 1.7% a contact (Chenghou Project: 100% to 0% over
   about 60 contacts). Vineta K's 37 to 47 contacts leave the ship alive. On the other tracks the follower makes
   about 20 contacts a lap, and laps take 75 to 95 s, so the ship is destroyed in lap 2 or 3.
   - Pressing Square, the game's "Absorb pickup" (default controls read from FE.wad: X accelerate, O use pickup,
     SQ absorb, L1/R1 airbrakes, triangle reverse camera), every 1.5 to 2 s, held 4 or 40 frames, gave no shield
     gain in any shot.
   - Pressing Circle ("Use pickup") every 2 s did not slow the drain either.
   - Capping the speed at 250 km/h did not lower the drain, and it broke Blue Ridge at a jump.
6. **Speed pads.** The ship reaches 400 to 460 km/h on pads (the AI ships race at 270 to 340). Most Vineta K
   runs met the left barrier at 2410 to 2450 m after the pad at about 2100 m, losing 190 to 380 km/h. A speed
   cap at 360 km/h (vmax: lift and both airbrakes) did not reduce the contacts.
7. **Recovery.** A ship that hits a barrier nose first can end at rest against it with Cross held: the stick
   alone does not turn it while it pushes (runs M and K). `recover 60` steers full lock towards the line below
   60 km/h. In run F and Verify run 3, every episode under 60 km/h (at 1884 to 1927 m and 2432 to 2493 m) was
   over within 2.1 s.

### Changed
- `tools/campaign_sweep.py`:
  - stall shot, shield-bar reading, `classify_stall`, the last 5 s in the detail, `<cell>.stall.csv`;
  - contacts a lap in the detail, `<cell>.contacts.csv`, `ref` and `slow` shots;
  - `Tuner`: dead-zone mapping (`yaw`, `deadzone`), the `follow` line's KEY=VALUE options (`koff`, `kpsi`,
    `airbrake`, `lift`, `ahead`, `lag`, `recover`, `vmax`, `absorb`, `hold`, `use`) and `--set` to override
    them;
  - trace columns (heading error, Cross, airbrake), line-buffered;
  - `--out DIR`, per-cell game directories and a locked summary, so runs can go side by side;
  - the `--frames` default is now 13000.
- `tools/pp_lines.py`: `--pad` (extra pad items) and `--dump` (raw race-record blocks).
- `config/pad_scripts/drive/vineta_k.txt`: the committed settings and why.
- `config/pad_scripts/drive/{modesto_heights,chenghou_project,blue_ridge}.txt` and `.line.csv` (new): AI lines
  recorded in PPSSPP on 2026-10-05 (`--downs 1, 2, 3`; 98% of the 2 m bins sampled) with the same follow
  settings.
- `docs/tracks.md`:
  - lengths, wrap points, grids and start lines of all four tracks;
  - what the follower works with: the dead zone, the lag, speed pads, the control pitfalls;
  - the stall classes and the shield bar.
- `README.md`: the sweep row.

PPSSPP was quit after each of its four recordings (the Vineta K shield search and the three AI lines), and
`ppsspp.ini` and `controls.ini` match their `.orig` copies.

### Verify output (last 20 lines)
```
[sweep] single_race-vineta_k: follow config/pad_scripts/drive/vineta_k.line.csv (coverage 100%, 4438 m, wn 0.8, preview 0.8 s, recover 60, absorb 2), exit at flip 19100
[sweep] single_race-vineta_k: shot ref: shield bar 100%
[sweep] single_race-vineta_k: shot f17520: TOTAL label variance 940, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17550: TOTAL label variance 591, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17580: TOTAL label variance 2349, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17610: TOTAL label variance 3317, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17640: TOTAL label variance 1517, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17670: TOTAL label variance 134, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17700: TOTAL label variance 3663, steady False (0 in a row)
[sweep] single_race-vineta_k: shot f17730: TOTAL label variance 3293, steady True (1 in a row)
[sweep] single_race-vineta_k: PASS at flip 17750, 3 laps, race time 192.9 s, 394 s: results screen at flip 17740 (3 laps: 69.4, 61.3, 58.4 s; 192.8 s at the shot); 39 contacts (13, 15, 11 a lap)
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | vineta_k | PASS | 17750 | 3 | 192.9 | 394 | 2026-10-05 22:55 | results screen at flip 17740 (3 laps: 69.4, 61.3, 58.4 s; 192.8 s at the shot); 39 contacts (13, 15, 11 a lap) |
| single_race | modesto_heights | STALL | 20690 | 2 | 242.9 | 444 | 2026-10-05 22:51 | eliminated by damage (shield bar 0%; at rest with Cross held); no progress for 20.0 s of race clock; 103 contacts (45, 45, 13 a lap); last 5 s (t/dist/kmh/off/lx): 238.7/1926/0/+6/-1.00 239.7/1926/0/+6/-1.00 240.7/1926/1/+6/-1.00 241.7/1926/1/+6/-1.00 242.7/1926/1/+6/-1.00; last: [pure] ship frame 20690 t=444051661 clock=43.208 pos=-199.247,6.872,147.619 vel=0.013,0.029,0.057 kmh=0.234 dist=1925.867 lap=1 |
| single_race | chenghou_project | STALL | 19510 | 1 | 225.6 | 429 | 2026-10-05 22:49 | eliminated by damage (shield bar 0%; crawling at 132 km/h with Cross held); no progress for 20.0 s of race clock; 105 contacts (58, 47 a lap); last 5 s (t/dist/kmh/off/lx): 221.4/4456/112/+25/-1.00 222.4/4421/107/+21/+1.00 223.4/4374/175/+19/+1.00 224.4/4322/150/+9/+1.00 225.4/4287/126/-10/+1.00; last: [pure] ship frame 19510 t=427368661 clock=110.410 pos=593.759,-39.150,-526.869 vel=26.748,-2.179,-21.052 kmh=122.790 dist=4283.728 lap=1 |
| single_race | blue_ridge | STALL | 10100 | 0 | 67.1 | 268 | 2026-10-05 22:49 | stuck on geometry (contact at 2363 m, 46.3 s, 34 km/h lost, +9 m off the line; crawling at 219 km/h with Cross held; shield bar 74%); no progress for 20.0 s of race clock; 35 contacts (35 a lap); last 5 s (t/dist/kmh/off/lx): 62.9/2169/268/+7/-0.42 63.9/2214/130/+1/+0.45 64.9/2267/262/-2/+0.37 65.9/2325/220/-1/+0.00 67.0/1978/228/+2/+0.39; last: [pure] ship frame 10100 t=268296006 clock=67.097 pos=-208.143,57.676,291.364 vel=-50.469,10.630,-39.453 kmh=233.768 dist=1985.963 lap=1 |
1
```
The Verify line exits 0 (each run exits 0, or the loop would have stopped). Its `grep -c PASS` prints 1: the
summary keeps one row per cell, and only the Vineta K row is a PASS. The other rows in that output are earlier
runs of those cells; the summary now holds the later rows listed above. The tail shows run 3; runs 1 and 2 printed
their PASS lines above it (in the table at the top).

### Open questions
1. **Contacts under 10 a lap.** The follower is limited by the lag, and the live file adds 0 to 10 flips of it.
   Two directions:
   - a lateral bias learned from contact positions: the left wall is hit twice as often as the right (143 against
     73 over six runs), and at 3900 m it is 7 to 11 m from the line;
   - a live file read every flip, which is a vendor change.
2. **The shield.** Can a probe field for the shield (in `be::Ship`, under `src/`) be added? Then the sweep could
   watch damage per contact, not just from shots. Is absorbing disabled in Single Race, or does Square not reach
   it?
3. **Budget for the other tracks.** Their laps take 75 to 95 s with this follower, so three laps need about
   16000 to 17000 flips. Those runs used 20000 to 24000. Should their cells carry their own budget in `MODES`?
4. **The shield bar as the damage test.** It reads 0% whenever the HUD is hidden. The vmax Chenghou stop was
   classed as damage while the ship was moving backwards at speed. A check for the "SHIP DESTROYED" title would
   be firmer.

## Review
Merged (Fable). Vineta K 3/3 is the acceptance that matters; not rerun by Fable (three seven-minute races) since the
worker's three runs and their traces are recorded. The other tracks fail by shield depletion, which is the game's
own rule; a test-only no-damage switch for the sweep (task 017) and the user's recorded laps for faithful driving
are the two ways forward. Decisions: per-track budgets in MODES, yes; a "SHIP DESTROYED" title check, yes; a per-flip
live-file read is a vendor change and waits.
