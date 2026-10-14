#!/bin/bash
# The display-rate check (task 089, D-022, the enhancement E8): the game's vblank at the PSP's 59.94 Hz
# (game.display_rate 0, PURE_DISPLAY_RATE=0, what every other tool runs with: tools/purelib/port.py's original_pacing)
# and at a 120 Hz display's (PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=120: headless there is no display, so the test switch
# names the rate), side by side, headless on the Metal backend. The display's rate holds only while the race backend
# lives (src/profile/enhancements.cpp, E4's gate): the frontend keeps the PSP's 59.94 Hz in both lanes, since its
# screens' transitions count frames (docs/timing.md, "E8"). Both lanes run the 30 fps modes at 60 fps
# (PURE_SIXTY_FPS=1), so the race waits one vblank a frame and the frontend two; Flashes stays at Original
# (PURE_SMOOTH_FLASHES=0, the pin), so the race-start fade waits two vblanks a frame in both.
#   tools/display_rate_check.sh [--race] [--out DIR]
#   --race     the swept Time Trial instead of the route (below).
#   --out      default out/display_rate_check/<route|race>; removed first.
# The route (default): tools/framerate_check.sh's, two runs of config/pad_scripts/main_menu.txt + time_trial.txt
# (Vineta K, Cross held from flip 5900), their own shot steps dropped, each on an empty memory stick
# (<out>/<0|1>/game), with PURE_TRACE_CALLS=sceDisplay:0x289D82FE (a `[call]` line per flip, its virtual time t=) and
# PURE_WATCH_SHIP=1, on the data directory out/data/display_rate_check (about 10 s each). The pad script counts
# flips, and the frontend runs at the PSP's rate in both lanes, so both take the same route. The race at 120 takes
# twice the flips for the same race clock, so each lane has its own end and HUD shot (END0/SHOT0 and END1/SHOT1). For each run: the frontend's flips FRONT_FROM to FRONT_TO (MAIN MENU and
# SINGLE PLAYER's screens), their median interval and their flips a second of virtual time (the system clock the
# game's frame timer reads; the frontend has no race clock); the race's flips while its clock (the `[pure] ship
# frame` lines' clock=) runs from RACE_CLOCK_FROM to RACE_CLOCK_TO s, their median interval and their flips a
# race-clock second; the race-start fade: the longest run of flips more than one and a half of the lane's vblank
# periods after the previous one (two vblanks) between the race's first one-vblank flip after FADE_FROM (the race
# load after TEAM SELECTION) and the race clock's start, its flips and its seconds (from the flip before it to its
# last, virtual time). PASS when both runs have a frontend of 29 to 31 flips a second (median FRONT_MS), the run at
# the PSP's rate a race of 58 to 61 (median RACE0_MS) and the run at 120 one of 116 to 122 (median RACE1_MS), the fade
# lasts the same seconds within FADE_PCT in both and takes FADE_FLIPS times the flips at 120, the HUD is drawn at each
# run's shot (tools/hud_check.py), and the run at the PSP's rate prints `[pure] display rate: off` and nothing else of
# the kind, the run at 120 `[pure] display rate: 120 Hz in a race, the PSP's 59.94 Hz outside one` before its first
# flip and `[pure] display rate: 120 Hz (8333 us a vblank)` once, after the `[call]` line of flip RACE_LOAD (the TEAM
# SELECTION confirm: the backend is made in the load that follows) and before the fade. Printed for both: every
# figure, the lines and the wall time.
# --race: two Time Trial cells of Vineta K through tools/campaign_sweep.py time_trial vineta_k (the sweep's defaults:
# headless, paced from the Cross hold, the follower), one at each rate, both with PURE_SIXTY_FPS=1 and
# PURE_WATCH_WORDS=08a8c3dc (the game clock, a float at DAT_08a8c3dc, with the virtual time t= once a flip), with
# --frames RACE_FRAMES0 and RACE_FRAMES1 (the budget counts flips: 60 and 120 a second), each in <out>/<0|1>/ (about
# 4 and 6 minutes). From each cell, as tools/framerate_check.sh --race reads them: the flips a race-clock second over
# the race, the game clock's advance per virtual second, the standing start (the mean km/h in the half seconds of race
# clock about 0.5, 1.0, 1.5 and 2.0 s), the first speed pad (the first trace row whose speed rises faster than
# PAD_KMH_S km/h a second: its race clock and distance), the laps and the contacts. PASS when both cells PASS in the
# sweep's terms (3 laps, the results screen), the run at the PSP's rate has 58 to 61 flips a second and the run at 120
# 116 to 122, both game clocks advance 0.99 to 1.01 s a second, the start bins up to 1.5 s at 120 are within START_PCT
# or START_KMH of the PSP rate's, and the contacts a lap within CONTACT_PCT. Printed, not bounded (task 089's review):
# the 2.0 s bin, which the first speed pad reaches 0.1 s and 4.6 m early at 120, the pad itself, and the mean lap,
# which the follower moves (it reads its steering every 10 flips, twice as often at 120, and its laps differ by 9%
# from run to run at one rate). The run at 120 prints the race line and the line outside a race, nothing else.
# Waits up to 600 s while another PureNative runs (one game at a time). Prints `display_rate_check: PASS ...` or
# `display_rate_check: FAIL ...` last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD

HZ=120             # the display rate of the run with 1
FRONT_FROM=4000    # the frontend's counted flips: MAIN MENU and SINGLE PLAYER's screens
FRONT_TO=5000
RACE_LOAD=5700     # the route's TEAM SELECTION confirm: the race load, and the backend, from the next flips
FADE_FROM=5600     # the fade is looked for from here (TEAM SELECTION's last flips, the race load) to the race clock
RACE_CLOCK_FROM=1.0   # the race's counted flips: those whose race clock is in this range (s)
RACE_CLOCK_TO=6.0
END0=7000          # the run at the PSP's rate ends here, its HUD shot at SHOT0 (framerate_check's)
SHOT0=6900
END1=8000          # the run at 120 ends here, its HUD shot at SHOT1
SHOT1=7900
FRONT_MS=31:36     # a median of two vblanks at 59.94 (33.4 ms), in both lanes
RACE0_MS=15:18     # one (16.7 ms)
RACE1_MS=7.5:9     # one at 120 (8.3 ms)
FPS30=29:31
FPS60=58:61
FPS120=116:122
FADE_PCT=0.10
FADE_FLIPS=1.8:2.2
CLOCK_RATE=0.99:1.01
START_PCT=0.05
START_KMH=10
START_TO=1.5       # the start bins bounded: those up to this race clock (s)
PAD_KMH_S=300      # a speed pad: the speed rising faster than this (km/h a second)
CONTACT_PCT=0.5
RACE_FRAMES0=18000 # the sweep's budget at 60 flips a second (framerate_check's)
RACE_FRAMES1=36000 # and at 120

RACE=no
OUT=
usage() {
  echo "usage: tools/display_rate_check.sh [--race] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --race) RACE=yes; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "display_rate_check: unknown argument $1"; usage ;;
  esac
done
MODE=route
[ "$RACE" = yes ] && MODE=race
OUT=${OUT:-out/display_rate_check/$MODE}

EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
[ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

# One game at a time (task 034).
wait_game() {
  python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("display_rate_check: " + m, flush=True),
                              limit=600) else 2)'
}

# The lane's switches: 0 the PSP's rate, 1 the display's (named).
lane_env() {
  if [ "$1" = 0 ]; then echo "PURE_DISPLAY_RATE=0"; else echo "PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=$HZ"; fi
}

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "display_rate_check: $MODE, headless, backend metal, $HZ Hz against the PSP's, out $OUT"

if [ "$MODE" = race ]; then
  for v in 0 1; do
    frames=$RACE_FRAMES0
    [ "$v" = 1 ] && frames=$RACE_FRAMES1
    wait_game || exit 2
    t0=$SECONDS
    env $(lane_env $v) PURE_SIXTY_FPS=1 PURE_WATCH_WORDS=08a8c3dc python3 tools/campaign_sweep.py time_trial vineta_k \
      --out "$OUT/$v" --shell headless --backend metal --frames "$frames" > "$OUT/$v.stdout" 2>&1
    rc=$?
    echo "$((SECONDS - t0))" > "$OUT/$v.seconds"
    echo "display_rate_check: $(lane_env $v): campaign_sweep exit $rc, $((SECONDS - t0)) s, log $OUT/$v/time_trial-vineta_k.log"
  done
  python3 - "$OUT" "$FPS60" "$FPS120" "$CLOCK_RATE" "$START_TO" "$START_PCT" "$START_KMH" "$CONTACT_PCT" \
    "$PAD_KMH_S" "$HZ" <<'EOF' | tee "$OUT/summary.txt"
import csv, os, re, struct, sys
sys.path.insert(0, "tools")
from fidelity_audit import SWEEP_LINE_RE  # the sweep's result line, as the audit reads it

out = sys.argv[1]
fps0, fps1, rate = ([float(x) for x in a.split(":")] for a in sys.argv[2:5])
start_to, start_pct, start_kmh, contact_pct, pad_kmh_s = (float(x) for x in sys.argv[5:10])
hz = sys.argv[10]
CELL = "time_trial-vineta_k"
LAPS_RE = re.compile(r"(\d+) laps: ([\d.]+(?:, [\d.]+)*) s")
CONTACTS_RE = re.compile(r"(\d+) contacts")
WORDS_RE = re.compile(r"\[pure\] words frame (\d+) t=(\d+): 0x([0-9A-Fa-f]{8})")
RATE_RE = re.compile(r"\[pure\] display rate: .*")
CENTRES = (0.5, 1.0, 1.5, 2.0)


def read(v):
    """The cell's outcome, laps (count, times), contacts, flips a race-clock second, game clock rate, start bins and
    its display-rate lines."""
    outcome, laps, times, contacts = None, 0, [], None
    with open(os.path.join(out, f"{v}.stdout"), errors="replace") as f:
        for line in f:
            m = SWEEP_LINE_RE.match(line.strip())
            if m and m[1] == CELL:
                outcome, laps = m[2], int(m[5])
                lm = LAPS_RE.search(m[8])
                times = [float(x) for x in lm[2].split(", ")] if lm else []
                cm = CONTACTS_RE.search(m[8])
                contacts = int(cm[1]) if cm else None
    rows = []
    trace = os.path.join(out, v, f"{CELL}.trace.csv")
    if os.path.exists(trace):
        with open(trace) as f:
            rows = [r for r in csv.DictReader(f) if r["race"] == "1" and r["clock"] not in ("", "nan")]
    pts = [(int(r["frame"]), float(r["clock"])) for r in rows if float(r["clock"]) > 1.0]
    fps = (pts[-1][0] - pts[0][0]) / (pts[-1][1] - pts[0][1]) if len(pts) > 1 else None
    pad = None
    speeds = [(float(r["clock"]), float(r["kmh"]), float(r["dist"])) for r in rows
              if r["kmh"] not in ("", "nan") and r["dist"] not in ("", "nan")]
    for (c0, k0, d0), (c1, k1, d1) in zip(speeds, speeds[1:]):
        if c0 > 0.0 and c1 > c0 and (k1 - k0) / (c1 - c0) > pad_kmh_s:
            pad = (c0, d0)
            break
    bins = []
    for c in CENTRES:
        kmh = [float(r["kmh"]) for r in rows
               if c - 0.25 <= float(r["clock"]) < c + 0.25 and r["kmh"] not in ("", "nan")]
        bins.append(sum(kmh) / len(kmh) if kmh else None)
    words, said = [], []
    log = os.path.join(out, v, f"{CELL}.log")
    if os.path.exists(log):
        with open(log, errors="replace") as f:
            for line in f:
                if RATE_RE.match(line):
                    said.append(line.strip())
                    continue
                m = WORDS_RE.match(line)
                if m and pts and pts[0][0] <= int(m[1]) <= pts[-1][0]:
                    value = struct.unpack("<f", bytes.fromhex(m[3])[::-1])[0]
                    if value > 1000.0:
                        words.append((int(m[2]) / 1e6, value))
    clock = (words[-1][1] - words[0][1]) / (words[-1][0] - words[0][0]) if len(words) > 1 else None
    return dict(outcome=outcome, laps=laps, times=times, contacts=contacts, fps=fps, clock=clock, bins=bins,
                flips=(pts[0][0], pts[-1][0]) if pts else None, said=said, pad=pad)


def fmt(x, spec):
    return format(x, spec) if x is not None else "-"


def mean(xs):
    return sum(xs) / len(xs) if xs else None


runs = {v: read(v) for v in ("0", "1")}
fails = []
for v, (lo, hi), name in (("0", fps0, "PSP"), ("1", fps1, "120 Hz")):
    r = runs[v]
    seconds = open(os.path.join(out, f"{v}.seconds")).read().strip()
    per_lap = r["contacts"] / r["laps"] if r["contacts"] is not None and r["laps"] else None
    print(f"{name}: {r['outcome'] or 'no outcome'}, {r['laps']} laps "
          f"({', '.join(f'{x:.2f}' for x in r['times']) or '-'} s, mean {fmt(mean(r['times']), '.2f')}), "
          f"{fmt(r['contacts'], 'd')} contacts ({fmt(per_lap, '.1f')} a lap); {fmt(r['fps'], '.2f')} flips a "
          f"race-clock second (flips {r['flips'][0] if r['flips'] else '-'} to {r['flips'][1] if r['flips'] else '-'}); "
          f"the game clock {fmt(r['clock'], '.4f')} s a second; the start "
          f"{'/'.join(fmt(b, '.1f') for b in r['bins'])} km/h at {'/'.join(str(c) for c in CENTRES)} s; the first "
          f"speed pad from {fmt(r['pad'][0] if r['pad'] else None, '.3f')} s at {fmt(r['pad'][1] if r['pad'] else None, '.2f')} m; "
          f"lines {r['said']}; {seconds} s")
    if r["outcome"] != "PASS" or r["laps"] != 3:
        fails.append(f"{name}: the cell {r['outcome'] or 'gave no outcome'} with {r['laps']} laps")
    if r["fps"] is None or not lo <= r["fps"] <= hi:
        fails.append(f"{name}: {fmt(r['fps'], '.2f')} flips a second (not {lo:g} to {hi:g})")
    if r["clock"] is None or not rate[0] <= r["clock"] <= rate[1]:
        fails.append(f"{name}: the game clock {fmt(r['clock'], '.4f')} s a second (not {rate[0]:g} to {rate[1]:g})")
OFF = "[pure] display rate: off"
OUTSIDE = f"[pure] display rate: {hz} Hz in a race, the PSP's 59.94 Hz outside one"
RACE = f"[pure] display rate: {hz} Hz (8333 us a vblank)"
if runs["0"]["said"] != [OFF]:
    fails.append(f"0: display rate lines {runs['0']['said']} (not [{OFF!r}])")
said1 = runs["1"]["said"]
if not said1 or said1[0] != OUTSIDE or RACE not in said1 or any(t not in (OUTSIDE, RACE) for t in said1):
    fails.append(f"1: display rate lines {said1} (the line outside a race first, then the race's)")
r0, r1 = runs["0"], runs["1"]
for c, b0, b1 in zip(CENTRES, r0["bins"], r1["bins"]):
    if c > start_to:
        continue
    if b0 is None or b1 is None:
        fails.append(f"no start bin at {c} s")
    elif abs(b1 - b0) > start_kmh and abs(b1 - b0) > start_pct * b0:
        fails.append(f"the start at {c} s: {b1:.1f} km/h at 120 against {b0:.1f} (over {start_pct:.0%} and "
                     f"{start_kmh:g} km/h)")
m0, m1 = mean(r0["times"]), mean(r1["times"])
lap = m1 / m0 - 1.0 if m0 and m1 else None
if lap is None:
    fails.append("no lap times")
p0, p1 = r0["pad"], r1["pad"]
pad = (f"the first speed pad {p1[0] - p0[0]:+.3f} s and {p1[1] - p0[1]:+.2f} m at 120 (reported)" if p0 and p1
       else "the first speed pad not found in both")
c0 = r0["contacts"] / r0["laps"] if r0["contacts"] is not None and r0["laps"] else None
c1 = r1["contacts"] / r1["laps"] if r1["contacts"] is not None and r1["laps"] else None
contacts = None
if c0 is not None and c1 is not None:
    contacts = (c1 - c0) / c0 if c0 else (0.0 if c1 == 0 else float("inf"))
    if abs(contacts) > contact_pct:
        fails.append(f"contacts a lap {c1:.1f} at 120 against {c0:.1f} ({contacts:+.0%}, over {contact_pct:.0%})")
else:
    fails.append("no contact counts")
print(f"display_rate_check: {'FAIL' if fails else 'PASS'} (race: {fmt(r0['fps'], '.2f')} and {fmt(r1['fps'], '.2f')} "
      f"flips a race-clock second; game clock {fmt(r0['clock'], '.4f')} and {fmt(r1['clock'], '.4f')}; the start to "
      f"{start_to:g} s within {start_pct:.0%} or {start_kmh:g} km/h; contacts a lap {fmt(c0, '.1f')} and "
      f"{fmt(c1, '.1f')}; reported: mean lap {fmt(m0, '.2f')} and {fmt(m1, '.2f')} s "
      f"({fmt(lap * 100 if lap is not None else None, '+.2f')}%), the 2.0 s bin {fmt(r0['bins'][-1], '.1f')} and "
      f"{fmt(r1['bins'][-1], '.1f')} km/h, {pad}{'; ' + '; '.join(fails) if fails else ''})")
EOF
  grep -q '^display_rate_check: PASS' "$OUT/summary.txt"
  exit $?
fi

for v in 0 1; do
  d=$OUT/$v
  end=$END0 shot=$SHOT0
  [ "$v" = 1 ] && end=$END1 shot=$SHOT1
  mkdir -p "$d/game/ms0/PSP/SAVEDATA" "$d/shots"
  ln -s "$ROOT/game/EBOOT.ELF" "$d/game/EBOOT.ELF"
  ln -s "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$d/game/disc.iso"
  {
    echo "$shot:shot h$shot"
    cat config/pad_scripts/main_menu.txt config/pad_scripts/time_trial.txt |
      grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)'
  } > "$d/route.txt"
  ENVS=()
  for kv in $(lane_env $v); do ENVS+=(--env "$kv"); done
  wait_game || exit 2
  t0=$SECONDS
  python3 tools/run_boot.py --script "$d/route.txt" --shots "$d/shots" --frames $end --shell headless \
    --backend metal --data-dir out/data/display_rate_check --max-lines 80000 --env PURE_GAME_DIR="$d/game" \
    --env PURE_SIXTY_FPS=1 --env PURE_TRACE_CALLS=sceDisplay:0x289D82FE --env PURE_WATCH_SHIP=1 "${ENVS[@]}" \
    "$d/run.log" > "$d/run.stdout" 2>&1
  rc=$?
  echo "$((SECONDS - t0))" > "$d/seconds"
  reached=no
  grep -q "^\[pure\] exit at frame $end" "$d/run.log" && reached=yes
  echo "display_rate_check: $(lane_env $v): run_boot exit $rc, frame $end reached: $reached, $((SECONDS - t0)) s, log $d/run.log"
  python3 tools/hud_check.py "$d/shots" --expect 1 > "$d/hud.txt" 2>&1
  echo "  $(tail -1 "$d/hud.txt")"
done

python3 - "$OUT" $FRONT_FROM $FRONT_TO $FADE_FROM $RACE_CLOCK_FROM $RACE_CLOCK_TO $END0 $END1 "$FRONT_MS" \
  "$RACE0_MS" "$RACE1_MS" "$FPS30" "$FPS60" "$FPS120" $FADE_PCT "$FADE_FLIPS" $RACE_LOAD $HZ <<'EOF' | tee "$OUT/summary.txt"
import os, re, statistics, sys
sys.path.insert(0, "tools")
from purelib.logs import SHIP_T_RE

out = sys.argv[1]
front_from, front_to, fade_from = (int(v) for v in sys.argv[2:5])
clock_from, clock_to = float(sys.argv[5]), float(sys.argv[6])
ends = {"0": int(sys.argv[7]), "1": int(sys.argv[8])}
front_ms, race0_ms, race1_ms, fps30, fps60, fps120 = ([float(x) for x in a.split(":")] for a in sys.argv[9:15])
fade_pct = float(sys.argv[15])
fade_flips = [float(x) for x in sys.argv[16].split(":")]
race_load, hz = int(sys.argv[17]), sys.argv[18]
CALL = "[call] sceDisplay:0x289D82FE "
RATE_RE = re.compile(r"\[pure\] display rate: (?:off|(\d+) Hz \((\d+) us a vblank\))$")
PSP_US = 16683


def read(v):
    """The run's flip times (index n - 1 for flip n), its ship lines' (flip, clock), the display-rate lines (text,
    the flips before each) and the vblank period they name."""
    ts, clocks, said, period = [], [], [], PSP_US
    with open(os.path.join(out, v, "run.log"), errors="replace") as f:
        for line in f:
            if line.startswith(CALL):
                ts.append(int(re.search(r" t=(\d+)", line)[1]))
            elif line.startswith("[pure] display rate:"):
                said.append((line.strip(), len(ts)))
                m = RATE_RE.match(line.strip())
                if m and m[2]:
                    period = int(m[2])
            else:
                m = SHIP_T_RE.match(line)
                if m:
                    clocks.append((int(m[1]), float(m[3])))
    return ts, clocks, said, period


def median_ms(ts, a, b):
    steps = [ts[n - 1] - ts[n - 2] for n in range(max(a, 2), min(b, len(ts)) + 1)]
    return statistics.median(steps) / 1000.0 if steps else None


def per_second(ts, a, b):
    """Flips a second of virtual time over flips a..b."""
    b = min(b, len(ts))
    return (b - a) / ((ts[b - 1] - ts[a - 1]) / 1e6) if b > a and ts[b - 1] > ts[a - 1] else None


def within(x, rng):
    return x is not None and rng[0] <= x <= rng[1]


def fmt(x, spec):
    return format(x, spec) if x is not None else "-"


def fade_of(ts, period, start):
    """The race-start fade: the longest run of two-vblank flips (more than 1.5 periods after the previous flip) from
    the race's first one-vblank flip after fade_from to the race clock's start. (first, last, seconds) or None."""
    slow = lambda n: 2 <= n <= len(ts) and ts[n - 1] - ts[n - 2] > 1.5 * period
    stop = min(start or len(ts), len(ts))
    race = next((n for n in range(fade_from, stop) if not slow(n)), None)
    if race is None:
        return None
    best, run = None, None
    for n in range(race + 1, stop + 1):
        if slow(n):
            run = (run[0], n) if run and run[1] == n - 1 else (n, n)
            if best is None or run[1] - run[0] > best[1] - best[0]:
                best = run
    if best is None:
        return None
    return best[0], best[1], (ts[best[1] - 1] - ts[best[0] - 2]) / 1e6


fails = []
figures = {}
for v, name in (("0", "PSP"), ("1", "120 Hz")):
    ts, clocks, said, period = read(v)
    end = ends[v]
    if len(ts) < end:
        fails.append(f"{name}: {len(ts)} flips traced, not {end}")
    front, front_fps = median_ms(ts, front_from, front_to), per_second(ts, front_from, front_to)
    pts = [(n, c) for n, c in clocks if clock_from <= c <= clock_to]
    race_fps = (pts[-1][0] - pts[0][0]) / (pts[-1][1] - pts[0][1]) if len(pts) > 1 and pts[-1][1] > pts[0][1] else None
    race = median_ms(ts, pts[0][0], pts[-1][0]) if pts else None
    start = next((n for n, c in clocks if c > 0.0), None)
    fade = fade_of(ts, period, start)
    with open(os.path.join(out, v, "seconds")) as f:
        seconds = f.read().strip()
    with open(os.path.join(out, v, "hud.txt")) as f:
        hud = f.read().strip().splitlines()
    hud = hud[-1] if hud else "no hud_check output"
    figures[v] = (front_fps, race_fps, fade, said)
    print(f"{name} ({period} us a vblank): frontend flips {front_from}-{front_to} median {fmt(front, '.2f')} ms, "
          f"{fmt(front_fps, '.2f')} flips a second; race flips {pts[0][0] if pts else '-'}-{pts[-1][0] if pts else '-'} "
          f"(race clock {clock_from:g} to {clock_to:g} s) median {fmt(race, '.2f')} ms, {fmt(race_fps, '.2f')} flips a "
          f"race-clock second; the race clock starts at flip {fmt(start, 'd')}; the fade "
          f"{f'flips {fade[0]}-{fade[1]}, {fade[1] - fade[0] + 1} flips, {fade[2]:.3f} s' if fade else 'not found'}; "
          f"lines {[f'{t} (after flip {n})' for t, n in said]}; {hud}; {seconds} s")
    want_front_ms, want_front_fps, want_race_ms, want_race_fps = (
        (front_ms, fps30, race0_ms, fps60) if v == "0" else (front_ms, fps30, race1_ms, fps120))
    if not within(front, want_front_ms):
        fails.append(f"{name}: frontend median {fmt(front, '.2f')} ms (not {want_front_ms[0]:g} to {want_front_ms[1]:g})")
    if not within(front_fps, want_front_fps):
        fails.append(f"{name}: frontend {fmt(front_fps, '.2f')} flips a second (not {want_front_fps[0]:g} to "
                     f"{want_front_fps[1]:g})")
    if not within(race, want_race_ms):
        fails.append(f"{name}: race median {fmt(race, '.2f')} ms (not {want_race_ms[0]:g} to {want_race_ms[1]:g})")
    if not within(race_fps, want_race_fps):
        fails.append(f"{name}: race {fmt(race_fps, '.2f')} flips a race-clock second (not {want_race_fps[0]:g} to "
                     f"{want_race_fps[1]:g})")
    if fade is None:
        fails.append(f"{name}: no race-start fade")
    texts = [t for t, _ in said]
    if v == "0" and texts != ["[pure] display rate: off"]:
        fails.append(f"{name}: display rate lines {texts}")
    outside = f"[pure] display rate: {hz} Hz in a race, the PSP's 59.94 Hz outside one"
    race_line = f"[pure] display rate: {hz} Hz (8333 us a vblank)"
    if v == "1" and (texts != [outside, race_line] or said[0][1] != 0 or not race_load <= said[1][1] < (
            fade[0] if fade else race_load)):
        fails.append(f"{name}: display rate lines {said} (the line outside a race before the first flip, the race's "
                     f"once from the race load at flip {race_load} on, before the fade)")
    if not hud.startswith("hud_check: 1 of 1 "):
        fails.append(f"{name}: no HUD ({hud})")
(f0, r0, fade0, _), (f1, r1, fade1, _) = figures["0"], figures["1"]
fade_text = "no fade"
if fade0 and fade1:
    ratio_s = fade1[2] / fade0[2]
    ratio_n = (fade1[1] - fade1[0] + 1) / (fade0[1] - fade0[0] + 1)
    fade_text = (f"fade {fade0[2]:.2f} and {fade1[2]:.2f} s ({ratio_s - 1.0:+.1%}), {fade0[1] - fade0[0] + 1} and "
                 f"{fade1[1] - fade1[0] + 1} flips (x{ratio_n:.2f})")
    if abs(ratio_s - 1.0) > fade_pct:
        fails.append(f"the fade at 120 lasts {ratio_s - 1.0:+.1%} of the PSP rate's (over {fade_pct:.0%})")
    if not fade_flips[0] <= ratio_n <= fade_flips[1]:
        fails.append(f"the fade's flips at 120 x{ratio_n:.2f} (not {fade_flips[0]:g} to {fade_flips[1]:g})")
print(f"display_rate_check: {'FAIL' if fails else 'PASS'} (frontend {fmt(f0, '.2f')}/{fmt(f1, '.2f')} and race "
      f"{fmt(r0, '.2f')}/{fmt(r1, '.2f')} flips a second, PSP/120; {fade_text}"
      f"{'; ' + '; '.join(fails) if fails else '; the HUD drawn at both'})")
EOF
grep -q '^display_rate_check: PASS' "$OUT/summary.txt"
