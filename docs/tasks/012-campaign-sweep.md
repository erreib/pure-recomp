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
(worker fills)

## Review
(Fable fills)
