# 007: Same-input race comparison, PPSSPP against the port

Milestone: M3 | Branch: task/007-same-input-race-compare | Status: OPEN (after task 006)

## Goal
With Cross held from the countdown on Vineta K (Vector, Feisar), our port's ship races at 0:09 and floats above a
void at 0:39. Decide whether the game does the same on PPSSPP with identical input (a wall scrape and respawn) or
whether our physics diverge, and if they diverge, find the first frame where the ship's position differs.

## Read first
- CLAUDE.md, docs/status.md (Blockers), docs/ppsspp.md, tools/ppsspp/routes/vineta_k_start.txt (task 006),
  config/pad_scripts/main_menu.txt and ~/dev/pure-recomp/out/race2/route.txt (the port's route with `6100:pad a 3000`)
- docs/research.md: the game-state pointer at 0x08B17798 (offsets +0x21C4 onwards, from the suxin.space article)
  and `config/function_labels.csv` entries for `Collision.cpp`, `CollMesh.cpp`, `Ship*`.

## Deliverable
1. In PPSSPP: extend the race route so CROSS is held from the first countdown frame for 3000 frames; capture the
   screen at race clock 0:05, 0:10, 0:20, 0:30, 0:40 (use the HUD time in captures to align, since the countdown
   frame differs between the two) into `out/007/ppsspp/`.
2. In the port: the same with `tools/run_boot.py --script ... --shots out/007/port --env PURE_NO_FB_TEXTURES=1`,
   captures at the same race clocks.
3. A side-by-side table: at each clock, same place on the track or not (describe), and `tools/imgdiff.py` fractions.
4. If they diverge: find the ship's world position in guest memory (the game-state object; `PURE_WATCH_MOVIE`-style
   probe in the profile reading the position each flip, under `PURE_WATCH_SHIP=1`; in PPSSPP read the same address
   through the driver's `memory.read` each capture) and report the first race clock at which positions differ by
   more than a ship length, plus the sceCtrl values each side saw at that time (the port: `PURE_TRACE_PAD=1`).

## Acceptance criteria
- [ ] Captures and the table exist; the Result states diverge / same-with-respawn with evidence.
- [ ] If diverging, the first differing clock and the position values on both sides are in the Result.

## Verify
`test -s out/007/ppsspp/t10.png && test -s out/007/port/t10.png && python3 tools/imgdiff.py out/007/port/t10.png out/007/ppsspp/t10.png --tol 32 --max-frac 0.5 --json`

## May touch
- tools/ppsspp/routes/, src/profile/pure_profile.cpp (a `PURE_WATCH_SHIP` probe only), README.md (switch row),
  out/007/ (ignored)

## Must not touch
- vendor/, patches/, tools/run_boot.py, tools/imgdiff.py, config/

## Estimated turns
45

## Escalate when
The ship position cannot be located in memory within 15 turns of trying: report the comparison table and stop.

## Result
(worker fills)

## Review
(Fable fills)
