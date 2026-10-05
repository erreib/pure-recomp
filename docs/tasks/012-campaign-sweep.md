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
