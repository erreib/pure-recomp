#!/bin/bash
# The frame-rate check (task 072, D-017, the enhancement E4): Time Trial at the PSP's two vblanks a frame
# (game.sixty_fps 0, PURE_SIXTY_FPS=0, what every other tool runs with: tools/purelib/port.py's original_pacing) and
# free-running (1, the player's default), side by side. Flashes stays at Original (PURE_SMOOTH_FLASHES=0, the same pin)
# in both, so the race-start fade waits two vblanks either way.
#   tools/framerate_check.sh [--race] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--out DIR]
#   --race     the swept Time Trial instead of the route (below).
#   --shell    the shell (default headless; a window shell is paced from flip PACED_FROM in the route runs, and the
#              sweep's own rules in --race), --backend the GE backend (default metal; vulkan under --shell vulkan).
#   --out      default out/framerate_check/<route|race>-<backend>-<shell>; removed first.
# The route (default): two runs of config/pad_scripts/main_menu.txt + time_trial.txt (Vineta K, Cross held from flip
# 5900), their own shot steps dropped, each on an empty memory stick (<out>/<0|1>/game), with
# PURE_TRACE_CALLS=sceDisplay:0x289D82FE (a `[call]` line per flip, its virtual time t=), PURE_WATCH_SHIP=1, a shot at
# flip RACE_TO (h6900) and the run ending at flip END, one with --env PURE_SIXTY_FPS=0 and one with 1, on the data
# directory out/data/framerate_check (about 7 s each headless). For each run: the median flip interval over the
# frontend's flips FRONT_FROM to FRONT_TO (the menus, two vblanks in both runs: the option leaves the frontend alone)
# and over the race's flips RACE_FROM to RACE_TO (the race-start fade, flips 5708 to 5764 at two vblanks in both
# runs, is over; the race clock runs from about flip 6010 with 0 and 6175 with 1), and the flips a race-clock second
# over the `[pure] ship frame` lines' clock= of those flips. PASS when both frontend medians are within FRONT_MS; the
# run with 0 has a race median within FRONT_MS and 29 to 31 flips a clock second; the run with 1 a race median within
# RACE_MS and 58 to 61 flips a clock second; the run with 0 prints `[pure] sixty fps: off` and no `on`; the run with 1
# prints `[pure] sixty fps: on` once, after the `[call]` line of flip RACE_LOAD or a later one (the TEAM SELECTION
# confirm: the race backend is made in the load that follows it, and the line came after flip 5704 in task 072's
# runs; the frontend before it never has the backend, so its byte is never written); and the shot at RACE_TO of the
# run with 1 shows the HUD (tools/hud_check.py). Printed for both: the medians, the flips a second, the lines and the
# wall time.
# --race: two Time Trial cells of Vineta K through tools/campaign_sweep.py time_trial vineta_k (the sweep's defaults:
# headless, paced from the Cross hold, the follower; about 4 minutes each), one with PURE_SIXTY_FPS=0 in the
# environment and one with 1 (and --frames 18000, twice the cell's budget: the budget counts flips), both with
# PURE_WATCH_WORDS=08a8c3dc (the game clock, a float at DAT_08a8c3dc, with the virtual time t= once a flip), each in
# <out>/<0|1>/. From each cell's trace.csv (the rows of race 1): the flips a race-clock second over the race (from its
# first row with a clock above 1 s to its last), and the mean km/h in four half-second bins of race clock centred at
# 0.5, 1.0, 1.5 and 2.0 s (0.25 to 2.25 s: the standing start, Cross held, before the first speed pad at about 2.2
# s); from its log the game clock's advance per virtual second over the same flips (the clock is set to 1000 once
# early on, so from its values above 1000: the last less the first over their t). PASS when the run with 0 has 29 to
# 31 flips a second and the run with 1 58 to 61, both game clocks advance 0.99 to 1.01 s a second, every start bin of
# the run with 1 is within START_PCT or START_KMH of the run with 0's, and both cells PASS in the sweep's terms
# (3 laps, the results screen). Prints both cells' lap times and contact counts as information: the follower reads
# its steering every 10 flips, twice as often at 60, so its laps differ (not judged).
# Waits up to 600 s while another PureNative runs (one game at a time). Prints `framerate_check: PASS ...` or
# `framerate_check: FAIL ...` last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

FRONT_FROM=4000   # the frontend's counted flips: MAIN MENU and SINGLE PLAYER's screens
FRONT_TO=5000
RACE_LOAD=5700    # the route's TEAM SELECTION confirm: the race load, and the backend, from the next flips
RACE_FROM=6300    # the race's counted flips: the fade is over and the race clock runs in both runs
RACE_TO=6900      # and the HUD shot
END=7000          # the run's end
PACED_FROM=3900   # a window shell's pace (a margin before the frontend's counted flips)
FRONT_MS=31:36    # a median of two vblanks (33.4 ms)
RACE_MS=15:18     # a median of one vblank (16.7 ms)
SLOW_FPS=29:31    # flips a race-clock second at two vblanks
FAST_FPS=58:61    # and at one
CLOCK_RATE=0.99:1.01
START_PCT=0.05
START_KMH=10
RACE_FRAMES=18000 # the run with 1's sweep budget (the cell's 9000 at 30 flips a second)

RACE=no
SHELL_NAME=headless
BACKEND=
OUT=
usage() {
  echo "usage: tools/framerate_check.sh [--race] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --race) RACE=yes; shift ;;
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "framerate_check: unknown argument $1"; usage ;;
  esac
done
pick_backend framerate_check "headless metal vulkan"
MODE=route
[ "$RACE" = yes ] && MODE=race
OUT=${OUT:-out/framerate_check/$MODE-$BACKEND-$SHELL_NAME}
need_game

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "framerate_check: $MODE, shell $SHELL_NAME, backend $BACKEND, out $OUT"

if [ "$MODE" = race ]; then
  for v in 0 1; do
    FRAMES=()
    [ "$v" = 1 ] && FRAMES=(--frames $RACE_FRAMES)
    wait_game framerate_check || exit 2
    t0=$SECONDS
    PURE_SIXTY_FPS=$v PURE_WATCH_WORDS=08a8c3dc python3 tools/campaign_sweep.py time_trial vineta_k --out "$OUT/$v" \
      --shell "$SHELL_NAME" --backend "$BACKEND" ${FRAMES[@]+"${FRAMES[@]}"} > "$OUT/$v.stdout" 2>&1
    rc=$?
    echo "$((SECONDS - t0))" > "$OUT/$v.seconds"
    echo "framerate_check: PURE_SIXTY_FPS=$v: campaign_sweep exit $rc, $((SECONDS - t0)) s, log $OUT/$v/time_trial-vineta_k.log"
  done
  python3 - "$OUT" "$SLOW_FPS" "$FAST_FPS" "$CLOCK_RATE" "$START_PCT" "$START_KMH" <<'EOF' | tee "$OUT/summary.txt"
import os, sys
sys.path.insert(0, "tools")
from purelib.logs import START_CENTRES as CENTRES, race_cell  # the sweep's result line and the cell's trace and clock

out = sys.argv[1]
slow, fast, rate = ([float(x) for x in a.split(":")] for a in sys.argv[2:5])
start_pct, start_kmh = float(sys.argv[5]), float(sys.argv[6])
CELL = "time_trial-vineta_k"


def read(v):
    """The cell's outcome, laps (count, times), contacts, flips a race-clock second, game clock rate, start bins."""
    return race_cell(os.path.join(out, f"{v}.stdout"), os.path.join(out, v), CELL)


def fmt(x, spec):
    return format(x, spec) if x is not None else "-"


runs = {v: read(v) for v in ("0", "1")}
fails = []
for v, (lo, hi) in (("0", slow), ("1", fast)):
    r = runs[v]
    seconds = open(os.path.join(out, f"{v}.seconds")).read().strip()
    print(f"PURE_SIXTY_FPS={v}: {r['outcome'] or 'no outcome'}, {r['laps']} laps "
          f"({', '.join(f'{x:.1f}' for x in r['times']) or '-'} s), {fmt(r['contacts'], 'd')} contacts; "
          f"{fmt(r['fps'], '.2f')} flips a race-clock second (flips {r['flips'][0] if r['flips'] else '-'} to "
          f"{r['flips'][1] if r['flips'] else '-'}); the game clock {fmt(r['clock'], '.4f')} s a second; the start "
          f"{'/'.join(fmt(b, '.1f') for b in r['bins'])} km/h at {'/'.join(str(c) for c in CENTRES)} s; {seconds} s")
    if r["outcome"] != "PASS" or r["laps"] != 3:
        fails.append(f"{v}: the cell {r['outcome'] or 'gave no outcome'} with {r['laps']} laps")
    if r["fps"] is None or not lo <= r["fps"] <= hi:
        fails.append(f"{v}: {fmt(r['fps'], '.2f')} flips a second (not {lo:g} to {hi:g})")
    if r["clock"] is None or not rate[0] <= r["clock"] <= rate[1]:
        fails.append(f"{v}: the game clock {fmt(r['clock'], '.4f')} s a second (not {rate[0]:g} to {rate[1]:g})")
for c, b0, b1 in zip(CENTRES, runs["0"]["bins"], runs["1"]["bins"]):
    if b0 is None or b1 is None:
        fails.append(f"no start bin at {c} s")
    elif abs(b1 - b0) > start_kmh and abs(b1 - b0) > start_pct * b0:
        fails.append(f"the start at {c} s: {b1:.1f} km/h with 1 against {b0:.1f} (over {start_pct:.0%} and "
                     f"{start_kmh:g} km/h: the game's speed moved?)")
r0, r1 = runs["0"], runs["1"]
ok = f"; the start within {start_pct:.0%} or {start_kmh:g} km/h"
print(f"framerate_check: {'FAIL' if fails else 'PASS'} (race: {fmt(r0['fps'], '.2f')} flips a second off, "
      f"{fmt(r1['fps'], '.2f')} on; game clock {fmt(r0['clock'], '.4f')} and {fmt(r1['clock'], '.4f')}"
      f"{'; ' + '; '.join(fails) if fails else ok})")
EOF
  grep -q '^framerate_check: PASS' "$OUT/summary.txt"
  exit $?
fi

for v in 0 1; do
  d=$OUT/$v
  fresh_stick "$d/game"
  mkdir -p "$d/shots"
  {
    echo "$RACE_TO:shot h$RACE_TO"
    cat config/pad_scripts/main_menu.txt config/pad_scripts/time_trial.txt |
      grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)'
  } > "$d/route.txt"
  PACE=()
  [ "$SHELL_NAME" = headless ] || PACE=(--env PURE_PACED_FROM=$PACED_FROM)
  wait_game framerate_check || exit 2
  t0=$SECONDS
  python3 tools/run_boot.py --script "$d/route.txt" --shots "$d/shots" --frames $END --shell "$SHELL_NAME" \
    --backend "$BACKEND" --data-dir out/data/framerate_check --max-lines 60000 --env PURE_GAME_DIR="$d/game" \
    --env PURE_SIXTY_FPS=$v --env PURE_TRACE_CALLS=sceDisplay:0x289D82FE --env PURE_WATCH_SHIP=1 \
    ${PACE[@]+"${PACE[@]}"} "$d/run.log" > "$d/run.stdout" 2>&1
  rc=$?
  echo "$((SECONDS - t0))" > "$d/seconds"
  reached=no
  grep -q "^\[pure\] exit at frame $END" "$d/run.log" && reached=yes
  echo "framerate_check: PURE_SIXTY_FPS=$v: run_boot exit $rc, frame $END reached: $reached, $((SECONDS - t0)) s, log $d/run.log"
  python3 tools/hud_check.py "$d/shots" --expect 1 > "$d/hud.txt" 2>&1
  echo "  $(tail -1 "$d/hud.txt")"
done

python3 - "$OUT" $FRONT_FROM $FRONT_TO $RACE_LOAD $RACE_FROM $RACE_TO $END "$FRONT_MS" "$RACE_MS" "$SLOW_FPS" \
  "$FAST_FPS" <<'EOF' | tee "$OUT/summary.txt"
import os, sys
sys.path.insert(0, "tools")
from purelib.logs import flip_log, flip_median_ms as median_ms  # the flip times and the ship lines

out = sys.argv[1]
front_from, front_to, race_load, race_from, race_to, end = (int(v) for v in sys.argv[2:8])
front_ms, race_ms, slow, fast = ([float(x) for x in a.split(":")] for a in sys.argv[8:12])


def read(v):
    """The run's flip times (index n - 1 for flip n), its ship lines' (flip, clock) and the sixty-fps lines (text,
    the flips before each)."""
    ts, ships, said = flip_log(os.path.join(out, v, "run.log"), "[pure] sixty fps:")
    return ts, [(n, c) for n, _, c in ships], said


def within(x, rng):
    return x is not None and rng[0] <= x <= rng[1]


def fmt(x, spec):
    return format(x, spec) if x is not None else "-"


fails = []
figures = {}
for v in ("0", "1"):
    ts, clocks, said = read(v)
    if len(ts) < end:
        fails.append(f"{v}: {len(ts)} flips traced, not {end}")
    front, race = median_ms(ts, front_from, front_to), median_ms(ts, race_from, race_to)
    pts = [(n, c) for n, c in clocks if race_from <= n <= race_to and c > 0.0]
    fps = (pts[-1][0] - pts[0][0]) / (pts[-1][1] - pts[0][1]) if len(pts) > 1 and pts[-1][1] > pts[0][1] else None
    with open(os.path.join(out, v, "seconds")) as f:
        seconds = f.read().strip()
    with open(os.path.join(out, v, "hud.txt")) as f:
        hud = f.read().strip().splitlines()
    hud = hud[-1] if hud else "no hud_check output"
    figures[v] = (front, race, fps)
    print(f"PURE_SIXTY_FPS={v}: frontend flips {front_from}-{front_to} median {fmt(front, '.2f')} ms; race flips "
          f"{race_from}-{race_to} median {fmt(race, '.2f')} ms, {fmt(fps, '.2f')} flips a race-clock second; "
          f"lines {[f'{t} (after flip {n})' for t, n in said]}; {hud}; {seconds} s")
    if not within(front, front_ms):
        fails.append(f"{v}: frontend median {fmt(front, '.2f')} ms (not {front_ms[0]:g} to {front_ms[1]:g})")
    want_ms, want_fps = (front_ms, slow) if v == "0" else (race_ms, fast)
    if not within(race, want_ms):
        fails.append(f"{v}: race median {fmt(race, '.2f')} ms (not {want_ms[0]:g} to {want_ms[1]:g})")
    if not within(fps, want_fps):
        fails.append(f"{v}: {fmt(fps, '.2f')} flips a race-clock second (not {want_fps[0]:g} to {want_fps[1]:g})")
    texts = [t for t, _ in said]
    if v == "0" and texts != ["[pure] sixty fps: off"]:
        fails.append(f"0: sixty fps lines {texts}")
    if v == "1" and (texts != ["[pure] sixty fps: on (game.sixty_fps)"] or said[0][1] < race_load):
        fails.append(f"1: sixty fps lines {said} (one `on`, after flip {race_load})")
    if v == "1" and not hud.startswith("hud_check: 1 of 1 "):
        fails.append(f"1: no HUD at {race_to} ({hud})")
(f0, r0, s0), (f1, r1, s1) = figures["0"], figures["1"]
print(f"framerate_check: {'FAIL' if fails else 'PASS'} (frontend {fmt(f0, '.1f')}/{fmt(f1, '.1f')} ms, race "
      f"{fmt(r0, '.1f')}/{fmt(r1, '.1f')} ms and {fmt(s0, '.2f')}/{fmt(s1, '.2f')} flips a second, off/on"
      f"{'; ' + '; '.join(fails) if fails else '; the HUD drawn at 60'})")
EOF
grep -q '^framerate_check: PASS' "$OUT/summary.txt"
