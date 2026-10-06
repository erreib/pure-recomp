# 012: Campaign sweep: every track to the results screen under scripted driving

Milestone: M5 | Branch: task/012-campaign-sweep | Status: OPEN

## Goal
The port reaches a race and drives (task 007: physics match PPSSPP). The campaign milestone needs every track and
mode to run to its results screen without a halt. Retail has no Autopilot, so the driver is a script: hold Cross
and steer with the analog stick by a per-track table of (frame, lx) steps that keeps the ship on the track well
enough to finish laps (it does not need to win). Build the sweep tool and the routes for Single Race on the Alpha
league tracks first (Vector class), then extend.

## Read first
- CLAUDE.md, docs/status.md, config/pad_scripts/main_menu.txt, ~/dev/pure-recomp/out/race/route.txt (menu to race),
  vendor/portablekit/host/ui/input_script.hpp (`axis leftx VALUE` holds the stick; `pad a N` holds Cross N frames)
- docs/tasks/007-same-input-race-compare.md Result (the ship's race record: position, velocity, distance along the
  track at 0x08B72010 + 7*0x1C0 + 0x18, lap counter at +0x10; `PURE_WATCH_SHIP=1` prints them per flip)
- tools/imgdiff.py --help (region variance to detect screens), out/race/*.png and out/m3/*.png (HUD layout)

## Deliverable
1. `tools/campaign_sweep.py`: for each (mode, track) cell in a table, runs the port with the menu route plus the
   race route plus a driving script, bounded by `--frames`, with `PURE_WATCH_SHIP=1` and `PSPRECOMP_NO_INTERPRETER=1`
   `--strict`; detects the results screen by a stable screen with the race HUD gone (imgdiff region variance on the
   HUD time region) or by the lap counter reaching 3 then a screen change; writes `out/sweep/<mode>-<track>.{log,png}`
   and a summary table (`PASS`, or the frame and last `[pure] ship` line where it stopped). One cell takes about
   5 minutes of real time; run cells sequentially.
2. Driving scripts `config/pad_scripts/drive/<track>.txt`: a steering table found by iterating with the ship probe
   (distance along the track must keep increasing; a wall stop shows as speed 0 with distance constant). Vineta K
   first (its first left-hander at 6.2 s needs lx about -0.6 from ~5 s), then the other Alpha league tracks in the
   order the Single Race menu lists them (DOWN presses in the track menu).
3. A route to the track menu for each track: the race route with N DOWN presses on the track list; record the list
   order in `docs/tracks.md`.

## Acceptance criteria
- [ ] `python3 tools/campaign_sweep.py single_race vineta_k --frames 12000` reports PASS (results screen reached) with
      lap 3 seen in the probe, strict, no interpreter.
- [ ] At least four Alpha league tracks PASS; the summary lists every cell attempted with its outcome.

## Verify
`python3 tools/campaign_sweep.py single_race vineta_k --frames 12000 && grep -q PASS out/sweep/summary.txt`

## May touch
- tools/campaign_sweep.py, config/pad_scripts/drive/, config/pad_scripts/*.txt (new route files only), docs/tracks.md,
  README.md (one row)

## Must not touch
- src/, vendor/, patches/, tools/run_boot.py, tools/imgdiff.py

## Estimated turns
60

## Escalate when
A track halts the game (a `[hle-stub]`, `unsupported`, or `Runtime stopped` other than the frame exit) or the ship
cannot be kept on the track by a steering table within 10 iterations: record the cell as the stop reason and move on;
stop entirely only if the menu route itself breaks.

## Result
Status: PARTIAL. The session ended before any steering was tuned. The sweep tool, the race route and the track list
exist. No cell has been run through the tool, and Verify was not run. With no tuned table it would report STALL at
the first corner, about 13 s into the race. One exploratory race run turned up three facts that change the plan:
the brief's frame budget, the direction of the first corner, and what the lap counter means.

### Cells attempted
| Mode | Track | Outcome | How far | Steering table |
|---|---|---|---|---|
| single_race | vineta_k | not run through the sweep. Exploratory run `out/explore/e1` (run_boot, strict, no interpreter, 8450 flips, 240 s) | GO at flip 6252; lap 1, dist 1424.8 m (start line about 1250 m), stopped against the left barrier at 6.1 s race clock | `config/pad_scripts/drive/vineta_k.txt`: notes only, no steps |
| single_race | modesto_heights | not attempted | | none |
| single_race | chenghou_project | not attempted | | none |
| single_race | blue_ridge | not attempted | | none |

### Findings
1. **`--frames 12000` cannot cover a three-lap race.**
   - The menu route alone takes 6252 flips to GO.
   - Vineta K is 4446 m a lap (track menu), so a race is 13.3 km. At the Vector top speed of 338 km/h that is at
     least 142 s, or 8500 flips at 60 flips/s.
   - An absolute bound of 12000 ends the run about 96 s into the race, before lap 3 ends.
   - The tool therefore counts `--frames` from the race route's Cross-hold step at 6100 (the run exits at
     6100 + N). The Verify line keeps its meaning, but a cell then takes about 18000 flips, or 8.5 min at the
     35 flips/s the port runs windowed. The reviewer should confirm this reading or change the Verify line.
2. **The first corner of Vineta K is a right-hander, not a left.**
   - With `6540:axis leftx -0.6` until 6700, the ship (heading -x) turned towards +z, which is left, and hit the
     left barrier at 6.1 s. The shot at 5.7 s (`out/explore/e1/e6600.png`) shows the track bending right.
   - Task 007's "left-hand turn" came from a straight run that scraped the outer barrier. The next try should be
     +lx from about 6540.
   - The stick mapping is correct: negative lx yaws the ship left.
3. **What the probe's fields mean on a race.**
   - The lap counter is 0 on the grid and becomes 1 when the ship first crosses the start line. A three-lap race
     is therefore over when the counter passes 3, not when it reaches 3.
   - `dist` is a track coordinate: 1079.3 m on the grid and about 1250 m at the start line, and it wraps once a
     lap.
   - The tool's stall rule allows for the wrap. All of this is in `docs/tracks.md`.
4. **The route needs a fresh memory stick for every run.** The route creates a profile and answers its prompts,
   and the first run wrote `UCUS98612P0000` into `game/ms0`. The tool therefore runs every cell from
   `out/sweep/game`: EBOOT.ELF and disc.iso are linked, and ms0 is emptied before each cell.

### Changed
- `tools/campaign_sweep.py` (new, untested end to end). It builds the cell's script from the menu route, the
  race route with N DOWN presses at 5380/5410/5440, and `drive/<track>.txt`. It runs `tools/run_boot.py --strict`
  with `PURE_WATCH_SHIP=1`, `PSPRECOMP_NO_INTERPRETER=1`, `PURE_INPUT_LIVE` and its own game directory, and follows
  the log as it runs:
  - STALL: no progress for `--stall` s of race clock. The tool then closes the window through the live file.
  - HALT: a `[hle-stub]`, `unsupported` or `Runtime stopped` line.
  - After the finish (lap counter > 3), it takes a live shot every 60 flips. PASS is the HUD time region's
    variance falling below a quarter of a mid-race reference shot, with two shots in a row equal at tol 24.
  - It writes `out/sweep/<mode>-<track>.{log,png}` and a merged `out/sweep/summary.txt`.
  - Only `--list`, compilation and the script assembly were checked. The results-screen thresholds are guesses:
    no race has finished yet, so no results screen has been seen.
- `config/pad_scripts/single_race.txt` (new): MAIN MENU to the race, Feisar/Vector/Alpha, Cross held from 6100.
- `config/pad_scripts/drive/vineta_k.txt` (new): the notes above, with no steps.
- `docs/tracks.md` (new): the Alpha list order (Vineta K 0, Modesto Heights 1, Chenghou Project 2, Blue Ridge 3
  DOWN presses), the DOWN timing and the probe semantics. The lengths of the last three tracks are still blank.
- `README.md`: one row for the tool.

### Verify output
Not run. The session was stopped, and with no Vineta K steering the cell can only STALL.

### What remains, and the plan I was following
- Open-loop tuning by hand would need 30 or more full runs a track, at 3 min of menu each, so it does not fit.
  The faster path, partly built (scratch scripts kept uncommitted in this worktree's `out/explore/`):
  1. `pp_lines.py`: records all 8 race records from PPSSPP through `memory.read` while the AI races and the
     player idles. That gives an AI racing line, (dist, x, z), per track: about 3.5 min a track.
     - It has to wait for the CPU to report stepping before it resumes (fixed).
     - The Vineta K recording was cut short by the stop (117 samples).
     - PPSSPP's ini was restored.
  2. `tune.py`: a closed-loop run in the port. It does pure pursuit on the velocity heading towards the AI line
     40-70 m ahead and sends `0:axis leftx V` through `PURE_INPUT_LIVE`, which is read every 10 flips. It records
     the applied `[script] frame N: axis leftx V` lines as the (frame, lx) table, then replays that table open
     loop through the sweep.
  3. Watch whether the open-loop replay holds over three laps. GO moves by about 6 flips between runs, and AI
     contact and weapons are not repeatable. If it does not hold, the robust option is a table keyed by
     distance along the track, applied by the sweep through the live file. That departs from the brief's
     (frame, lx) form, so it needs the reviewer's agreement.
- Then do Modesto Heights, Chenghou Project and Blue Ridge in that order. The DOWN-press route is in the tool
  but not yet checked: the tool takes a `<cell>-menu` shot at the track list.

### Open questions
1. Should `--frames` stay relative to the Cross hold (finding 1), or should the Verify line become an absolute
   bound of about 18000?
2. Is a distance-keyed steering table acceptable if frame-keyed tables prove flaky across runs?

## Review
(Fable fills)

## Result (continued)
Status: PARTIAL. Vineta K reached the results panel once through the Verify command (strict, no interpreter, three
laps, 3:01.7). The next run of the same command stalled on lap 3, so the last Verify run is a FAIL and the cell is
not reliable yet. Only Vineta K was attempted, so the second criterion (four Alpha tracks) is open. Modesto
Heights has its AI line recorded but no cell run: the session went past the two-hour box.

### Cells attempted
| Mode | Track | Outcome | How far | Steering |
|---|---|---|---|---|
| single_race | vineta_k | PASS once, STALL once | verify1 (2026-10-05 21:31): PASS at flip 17730, laps 64.2, 59.4, 58.0 s (8th), results panel confirmed at flip 17720, 30 wall contacts. verify2 (21:38): STALL at flip 18040, on lap 3 at 4437 m, after 28 contacts | `follow config/pad_scripts/drive/vineta_k.line.csv 1.0 0.3` |
| single_race | modesto_heights | not run | AI line recorded in PPSSPP (`out/lines/modesto_heights.csv`, not committed): the distance wraps at about 4465 m, grid 652 m, start line about 803 m | none |
| single_race | chenghou_project | not attempted | | none |
| single_race | blue_ridge | not attempted | | none |

The runs that led there, all Vineta K (outputs in `out/sweep/`, ignored):

| Run | Steering | Result |
|---|---|---|
| tune1 | `--tune`, pure pursuit 20 to 60 m ahead, lx = 2.5 x angle | swung from lock to lock (offset +-15 m every 2 s), 150 km/h at best; stopped by hand at 65 s, lap 1, 2486 m |
| tune2 | `--tune`, curvature feed-forward with heading and offset feedback (wn 1.0 rad/s, preview 0.3 s) | three laps, 59.6, 53.5, 59.2 s (2:52.3, 8th), 7 to 9 wall contacts a lap, no stop. Its shots identified the results panel |
| replay1 | tune2's second lap as 1825 `@DIST:axis leftx V` steps, open loop | 15 to 25 m off the line within 20 s, spun round at about 2440 m, still on lap 1 after 101 s; stopped by hand |
| verify1 | `follow` (as committed); panel = three equal shots 60 flips apart | PASS |
| verify2 | the same; panel = two equal shots 30 flips apart (the committed code) | STALL on lap 3 |

### Findings
1. **The lap field is not a lap counter.** The PPSSPP recording of all eight records and the port's three-lap runs
   agree:
   - The field is 0 on the grid, 1 from the first crossing of the start line, and then stays 1.
   - Bit 16 is set once the race is over (65537 from the finish line on).
   - The record's clock is the lap clock. It runs from GO through the first crossing, then restarts at every
     later crossing. The probe's values match the lap times on the results panel.
   - The sweep therefore counts laps as clock restarts and sums them into a race time for the stall rule.
2. **The results panel is drawn over a moving replay.**
   - About 4 s after the line, the panel comes up: "BAD LUCK... 8TH", the lap times, TOTAL, and ENTER TAG (a new
     profile sets the LR and RR records).
   - Neither the brief's "stable screen" nor "HUD gone" holds: the panel title sits where the HUD time was.
   - PASS is now the panel's TOTAL label drawn and unchanged in two shots 30 flips apart, looked for only after
     the third lap.
3. **Open-loop steering does not hold a race.** Frame-keyed tables shift with GO and every contact. The
   distance-keyed replay that the reviewer accepted was tried (replay1) and failed in the first lap. Wall
   contacts and the other ships make each run's path different, and nothing pulls an open-loop ship back. The
   committed table therefore steers closed loop: `follow LINE WN PREVIEW` tracks a racing line through
   `PURE_INPUT_LIVE`. `--tune` still records the open-loop form.
4. **run_boot.py's log is block-buffered.** The file is opened without line buffering, so a reader sees the
   `[pure] ship` lines up to about 50 flips late, which is too late to steer by. The sweep now runs PureNative
   under its own pty, the way run_boot does: the same environment, folded log and frame-exit grace. It writes
   the log line by line. A live step then lands 0 to 16 flips after the ship line it answers (the port reads the
   live file every 10 flips).
5. **Steering dynamics** (Vineta K, from tune1's log):
   - lx held at full lock turns the velocity heading at about 1 rad/s from 150 km/h up.
   - The heading answers 0.2 to 0.5 s after the stick.
   - The line needs up to about 1 rad/s at racing speed.
   - The `Tuner` places the closed loop at 1 rad/s with damping 0.7.
6. **The verify2 stall.** On lap 3, after 28 contacts, the speed ran down from 290 km/h at 4260 m to 0 at
   4437 m over 6 s, with no impact in the trace. The ship then sat there with Cross held.
   - A ship destroyed by accumulated wall damage is the suspect. It is unconfirmed, because the tool takes no
     shot at a STALL.
   - Most contacts happen 12 to 20 m off the line after a corner was run wide, at places where the line needs
     only 0.3 to 0.5 rad/s. The rest happen where it needs about 1 rad/s, which is the limit of full lock;
     airbrakes are not used.
7. **The budget is tight.** `--frames 12000` ends the run at flip 18100.
   - verify1's race finished at about flip 17150, and the panel was confirmed at 17720, 380 flips before the
     end. The 30-flip, two-shot rule of the committed code confirms it about 300 flips sooner.
   - Races took 172 to 182 s, so a run with more contacts can run out of budget.
8. **The memory reads need no pausing.** PPSSPP's `memory.read` works while the CPU runs, so `tools/pp_lines.py`
   needs no breakpoints: each record carries its own clock. Reads sometimes catch a record mid-update (a
   lap value of 257 for one sample). The AI line is the mean of the seven AI ships per 2 m of distance (98% of
   the bins sampled in 80 s of race).
9. **Another worktree ran alongside these runs.** Another agent's PureNative
   (`.claude/worktrees/agent-aa2599ed98787550a`) ran windowed at the same time. No interference was seen, since
   each process has its own virtual pad. PPSSPP was quit after each recording, and its ini and controls.ini
   match the `.orig` copies.

### Changed
- `tools/campaign_sweep.py`:
  - its own pty runner;
  - lap counting from the lap clock, and the race-time stall rule;
  - results-panel detection;
  - steering tables with `FRAME:`, `@DIST:` and `follow` lines;
  - `--tune` (closed-loop `Tuner`, which writes `out/sweep/<cell>.tuned.txt`) and `--export-line`;
  - a per-flip `out/sweep/<cell>.trace.csv` (distance, position, speed, lx, offset from the line);
  - NO RACE detected during the run.
- `tools/pp_lines.py` (new): records the AI ships' race records in PPSSPP during a Single Race (`--downs N` picks
  the track), using `tools/ppsspp/ppsspp_ctl.py` as a library; about 3.5 min a track. It is outside the brief's
  May touch, but the reviewer's resume decision asked for it.
- `config/pad_scripts/drive/vineta_k.txt`: the `follow` line, plus the notes, including why not a replayed table.
- `config/pad_scripts/drive/vineta_k.line.csv` (new): the Vineta K AI line, `dist,x,z`, 2219 rows, exported from
  the PPSSPP recording.
- `docs/tracks.md`: probe semantics (lap clock, lap field, finish bit), the wrap point and start line of Vineta K
  and Modesto Heights, the results panel, steering tables and how to make one, the two Verify runs.
- `README.md`: the sweep row, rewritten (still one row).

### Verify output (last 20 lines)
The run with the committed code (verify2):
```
$ python3 tools/campaign_sweep.py single_race vineta_k --frames 12000 && grep -q PASS out/sweep/summary.txt
[sweep] single_race-vineta_k: follow config/pad_scripts/drive/vineta_k.line.csv (coverage 100%, 4438 m, wn 1.0, preview 0.3 s), exit at flip 18100
[sweep] single_race-vineta_k: STALL at flip 18040, 2 laps, race time 198.3 s, 404 s: no progress for 20.0 s of race clock; last: [pure] ship frame 18040 t=401043887 clock=70.536 pos=664.235,-115.061,424.842 vel=-0.011,0.000,0.010 kmh=0.053 dist=4437.037 lap=1
# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run

| mode | track | outcome | flip | laps | race clock | real s | run | detail |
|---|---|---|---|---|---|---|---|---|
| single_race | vineta_k | STALL | 18040 | 2 | 198.3 | 404 | 2026-10-05 21:38 | no progress for 20.0 s of race clock; last: [pure] ship frame 18040 t=401043887 clock=70.536 pos=664.235,-115.061,424.842 vel=-0.011,0.000,0.010 kmh=0.053 dist=4437.037 lap=1 |
exit 1
```
The run before it (verify1) used the same steering. Its only difference was the panel rule (three equal shots
60 flips apart):
```
[sweep] single_race-vineta_k: shot f17719: TOTAL label variance 4370, steady True (2 in a row)
[sweep] single_race-vineta_k: PASS at flip 17730, 3 laps, race time 191.9 s, 396 s: results screen at flip 17720 (3 laps: 64.2, 59.4, 58.0 s; 191.7 s at the shot)
| single_race | vineta_k | PASS | 17730 | 3 | 191.9 | 396 | 2026-10-05 21:31 | results screen at flip 17720 (3 laps: 64.2, 59.4, 58.0 s; 191.7 s at the shot) |
exit 0
```
`out/sweep/verify1/single_race-vineta_k.png` is the panel (LAP 1 1.04.25, LAP 2 0.59.42, LAP 3 0.58.04, TOTAL
3.01.71).

### Open questions
1. **Committing the AI line.** Is `config/pad_scripts/drive/vineta_k.line.csv` acceptable?
   - It holds measured positions of PPSSPP's AI ships, not bytes of the game: the same kind of numbers as task
     007's Result. But the hard rule limits `config/` to addresses, names, NIDs and hashes (pad scripts aside).
   - If it is not acceptable, `follow` can name `out/lines/<track>.csv`, and `tools/pp_lines.py` regenerates
     that in 3.5 min a track.
2. **`follow` instead of a table.** `follow` replaces both the brief's (frame, lx) table and the distance-keyed
   replay. Both open-loop forms were measured not to hold a race. Is that acceptable?
3. **Reliability, the next steps in order:**
   - a `shot stall` before the quit on STALL, to see what stopped the ship;
   - fewer contacts: a longer preview or a stronger offset gain after corners, airbrakes (L/R) where the line
     needs more than full lock, and lifting off Cross (`pad a 1`, then `pad a N` again);
   - three Verify runs to measure the pass rate.
   Then Modesto Heights: `tools/campaign_sweep.py single_race modesto_heights --export-line
   config/pad_scripts/drive/modesto_heights.line.csv` (after `tools/pp_lines.py modesto_heights --downs 1`, if
   `out/lines/` is gone) and a `follow` line. Then the other two tracks.
4. **The Verify budget.** Should the Verify line take `--frames 13000`? With 12000, a 3-lap race with more
   contacts than verify1 runs out of flips before the panel.
5. **ENTER TAG.** The panel waits for a tag entry. Single Race does not need it, since the sweep quits at the
   panel. A mode with a next race (a tournament) will need the tag answered.
