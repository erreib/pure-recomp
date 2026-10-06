# 016: Sweep reliability and the Alpha league

Milestone: M5 | Branch: task/016-sweep-reliability | Status: OPEN

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
(worker fills)

## Review
(Fable fills)
