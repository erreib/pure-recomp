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
Status: DONE. Verify prints FAIL: at t10, 65.2% of pixels differ, and the limit is 50%. That failure is the finding,
not missing work. Both sides put the ship in the same place at every clock. The port just does not draw most of the
scene around it.

**The answer: the runs do not diverge.** With CROSS held, the Feisar does the same thing on PPSSPP and in the port. It
reaches 338 km/h, then hits the outer barrier of the first left-hand turn at race clock 6.21 s. Speed drops to about
150 km/h within 0.05 s, and the ship scrapes along the barrier to a stop at about 13 s. It stays there to the end of
the trace at 46 s. There is no respawn and no reset; it is pinned nose-first against the yellow-and-black barrier.
The clock-aligned positions never differ by more than 1.13 m (at 25.09 s). The brief's threshold is a ship length,
which I took as 5 m. Before the hit they agree within 0.40 m. The port's "floats above a void at 0:39, speed 0" is this same
resting place. The void is the port's renderer: it does not draw the track surface, the barrier, the pillars or the
sky (see the table and Open question 1).

### Where the ship is in memory
The ship's state lives in a per-ship race record, a `.bss` array, so it has the same address in PPSSPP and in the
port. Entry k is 0x1C0 bytes. Offsets are relative to its position vector at `0x08B72010 + k*0x1C0`:

| Offset | Field |
|---|---|
| -0x20 | velocity, m/s (HUD km/h = \|v\| x 3.6; checked: 87.5 m/s = 315 km/h) |
| +0x00 | position x, y, z, 1 (equal to the be::Ship object's matrix row at +0x70) |
| +0x10 | lap counter |
| +0x14 | the entry's ship index |
| +0x18 | distance along the track |
| +0x1C | race clock in seconds (float; the HUD formats it in FUN_0881dd18) |

The player is index 7 on both sides (8th on the grid). How it is found:
- be::Ship objects have vtable 0x08AC259C at +0x3c, set by LinkObj_etc__089261ac, the Ship.cpp constructor.
- +0x480 is the ship index, +0x488 the kind (0 or 1 for a player, 2 or 3 for AI), +0xcc the AI flag.
- +0x40 and +0x80 are 4x4 matrices from the transform base FUN_08893eb4.

The objects are on the heap at different addresses: port 0x09A48060 (0x09A5FBB0 in an earlier run), PPSSPP
0x09A552C0. The record array is static, so both sides read the same thing. The game-state pointer 0x08B17798 from the
suxin.space article only leads to zone and score stats (+0x21C4 zones, +0x21D0 score); it does not lead to the ship.

### Side-by-side
The port's shots were taken at flips 6556/6856/7456/8056/8656. PPSSPP's were taken at frames 7693/7993/8592/9192/9791
(the displayed frame is the next flip). The HUD is in the captures, and positions are clock-aligned from the two
memory traces. imgdiff is `--tol 32` with the port's 960x544 frame scaled to 480x272.

| Clock | HUD port / PPSSPP | km/h port / PPSSPP | Same place? | Port pos | PPSSPP pos | Delta | imgdiff fraction |
|---|---|---|---|---|---|---|---|
| 0:05 | 0.05.0 / 0.05.0 | 314 / 313 | yes: braking zone of the first left-hander, EUR billboard ahead, AI ship ahead left | (-75.49, 37.83, -116.16) | (-75.86, 37.83, -116.18) | 0.37 m | 0.7130 |
| 0:10 | 0.10.0 / 0.10.0 | 12 / 12 | yes: against the outer barrier, pillar ahead left. The port draws the far skyline and tower but no barrier, track or pillar body | (-221.33, 43.02, -137.55) | (-220.51, 42.95, -137.05) | 0.96 m | 0.6521 |
| 0:20 | 0.20.0 / 0.20.0 | 0 / 0 | yes: at rest at the barrier. The port shows only the pillar's middle band and the blue window band, at the same screen positions | (-227.87, 43.20, -142.26) | (-227.02, 43.14, -141.74) | 1.00 m | 0.8074 |
| 0:30 | 0.30.1 / 0.30.0 | 0 / 0 | yes, same view as 0:20 | (-229.56, 43.31, -142.69) | (-228.62, 43.25, -142.16) | 1.08 m | 0.8232 |
| 0:40 | 0.40.1 / 0.40.0 | 0 / 0 | yes, same view | (-229.64, 43.32, -142.73) | (-228.71, 43.25, -142.21) | 1.07 m | 0.8267 |

The wall hit, aligned by clock (from `out/007/compare.py`):

| Clock | Port km/h | PPSSPP km/h | Delta |
|---|---|---|---|
| 6.157 | 337.7 | 337.8 | 0.38 m |
| 6.206 | 338.4 | 171.6 (PPSSPP hits within this flip) | 0.38 m |
| 6.256 | 149.4 | 145.9 | 0.34 m |
| 6.456 | 112.9 | 108.0 | 0.53 m |

The positions grow apart by half a metre in the scrape and then stay about 1 m apart while the ship is at rest.

### Input
The sceCtrl values were the same on both sides. The port's `PURE_TRACE_PAD=1` shows `buttons 0x4000 analog 128,128`
(CROSS, sticks centred) from flip 6100 until flip 9100. The race starts at flip 6253, so CROSS goes down 153 flips
before GO, during the ring countdown. PPSSPP's replay holds CROSS (0x4000), with the sticks centred by the driver, from
vblank 7213 (the first READY frame) to 10213. The clock starts at vblank 7393, so that is 180 frames before GO. The
start offsets differ by 27 frames within the countdown, and that made no measurable difference. Speeds at 1 s are
77.3 and 77.7 km/h.

### Changed
- `src/profile/pure_profile.cpp`: the `PURE_WATCH_SHIP=1` probe. Once per flip, while the line changes, it prints
  the player's race record: `[pure] ship frame N t=... clock=... pos=x,y,z vel=... kmh=... dist=... lap=...`. It
  finds the player's be::Ship object by scanning user RAM for the vtable, every 30 flips until the object is there.
- `README.md`: a switch row for `PURE_WATCH_SHIP`.
- `tools/ppsspp/routes/vineta_k_hold_cross.txt` (new): CROSS from 7213 to 10213, chained after `frontend.txt` and
  `vineta_k_start.txt`.
- `docs/tasks/007-same-input-race-compare.md`: this Result.

### Reproducing (all outputs in `out/007/`, ignored)
- Port:
  `tools/run_boot.py --script out/007/port_route.txt --shots out/007/port --frames 9150 --seconds 900 --max-lines 40000 --env PURE_NO_FB_TEXTURES=1 --env PURE_TRACE_PAD=1 --env PURE_WATCH_SHIP=1 out/007/port.log`
  - The route is out/race2/route.txt with `shot t05..t40` at 6556/6856/7456/8056/8656.
  - Run time 253 s. The log has 3422 ship lines.
- PPSSPP captures (stock driver, 176 s, quit cleanly):
  `ppsspp_ctl.py run --pad-file routes/frontend.txt --pad-file routes/vineta_k_start.txt --pad-file routes/vineta_k_hold_cross.txt --shot 7693:out/007/ppsspp/t05.png --shot 7993:...t10 --shot 8592:...t20 --shot 9192:...t30 --shot 9791:...t40 --until 9800`
  - Its t05 flip time (usec 128366242) is the same as in the traced run, so the run is deterministic.
- PPSSPP memory trace: `out/007/pp_race.py`.
  - It uses `ppsspp_ctl.py` as a library and stops at the first sceDisplaySetFrameBuf at or after each traced
    vblank, which is the same point as the port's probe. There it reads the race-record block 0x08B71E50+0x1200 and
    all be::Ship objects through `memory.read`.
  - Traced every 10 frames over 7150-7360, every frame over 7361-8200, and every 5 frames over 8201-10200, into
    `out/007/pp1/stats.bin`.
- Comparison: `out/007/compare.py out/007/port.log out/007/pp1` writes `out/007/compare.txt`.
- Montages: `out/007/side_t05-t20.png`, `side_t30-t40.png`, and `side_grid.png` (the start grid).

### Verify output (last 20 lines)
```
$ test -s out/007/ppsspp/t10.png && test -s out/007/port/t10.png && python3 tools/imgdiff.py out/007/port/t10.png out/007/ppsspp/t10.png --tol 32 --max-frac 0.5 --json
{"result": "FAIL", "mode": "compare", "a": "out/007/port/t10.png", "b": "out/007/ppsspp/t10.png", "width": 480, "height": 272, "fraction": 0.6521139705882353, "differing": 85140, "total": 130560, "tol": 32, "max_frac": 0.5, "resized": true, "a_size": [960, 544], "b_size": [480, 272], "mask": null, "region": null, "pixel_region": null, "out": null}
exit 1
```
(`tools/verify_task.sh` does not exist in this tree, so I ran the brief's line directly.)

### Open questions
1. **The Blocker "ship off the track" should become a renderer blocker.** With `PURE_NO_FB_TEXTURES=1`, the port
   leaves out most of Vineta K's environment:
   - the track surface, the barriers, the stadium arches (only their cyan light strips are drawn), the pillar bodies
     and the sky are missing;
   - the grid's dark track patches come out as tall dark-blue slabs;
   - the crowds, the billboards, the far skyline, the ships and the HUD are drawn correctly
     (`out/007/side_grid.png`, `side_t05-t20.png`).

   `out/milestones/05-race-vineta-k.png` was taken as "renders correctly" in status.md, but it is not: compare it
   with `ref/vineta_k_start.png`. Task 006 already measured 0.946. This looks separate from the bloom chain (task
   008). The missing draws are the large environment meshes, so their vertex format or primitive type, clipping, or
   fog is the first suspect. The next step would be a GE-list diff of one race frame against
   `ref/vineta_k_start.ppdmp`.
2. **The Verify line assumed that the same place would look alike.** It fails only because of item 1. If it should
   gate this task, it could compare HUD-and-ship regions (`--region`), or the memory traces instead.
3. **The port's frame time jitters.**
   - Virtual time between flips alternates between about 15.7 and 17.7 ms (PPSSPP: 16.2 to 17.5 ms).
   - Four flips took 120 to 251 ms (flips 7502, 7608, 7766, 8736, all after the ship was at rest). The game's clock
     then stepped 67 ms (it caps dt).
   - The game integrates with measured dt, so jitter like this reaches the physics. Here it cost under 0.4 m in 6 s.
     The HUD showing 0.30.1 instead of 0.30.0 at flip 8056 comes from these hitches.
   - Port runs are also not repeatable: heap addresses and the GO flip (about 6251 to 6257 in three runs) move
     between runs.
4. **The PPSSPP driver can lose a resume.** In the long trace, a `cpu.resume` was dropped: a late `cpu.stepping`
   from `Debugger.pause()` stopped the CPU again. `wait_breakpoint` then waited forever, because emulated time does
   not move while the CPU is stepping. I resumed it by hand.
   - `out/007/pp_race.py` works around this: it resends the resume when the clock stands still for 2 s.
   - `tools/ppsspp/` (outside `routes/`) was outside this task's scope, so the fix and a `--watch ADDR:SIZE` capture
     option are not committed. Both would be small driver changes.

## Review
(Fable fills)
