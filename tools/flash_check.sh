#!/bin/bash
# The flash check (task 070, D-016, the enhancement E6): the race with the full-screen flashes at the PSP's two vblanks
# a frame (game.smooth_flashes 0, PURE_SMOOTH_FLASHES=0, what every other tool runs with: tools/purelib/port.py's
# original_pacing) and at the race's free-running rate (1, the player's default), side by side.
#   tools/flash_check.sh [--race] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--out DIR]
#   --race     the swept race instead of the race-start fade (below).
#   --shell    the shell (default headless; a window shell is paced from flip 5500 in the fade runs, and the sweep's own
#              rules in --race), --backend the GE backend (default metal; vulkan under --shell vulkan).
#   --out      default out/flash_check/<fade|race>-<backend>-<shell>; removed first.
# The fade (default): two runs of tools/frame_regress.sh's race route (config/pad_scripts/main_menu.txt +
# single_race.txt: Vineta K, Cross held from flip 6100), their own shot steps dropped, each on an empty memory stick
# (<out>/<0|1>/game), with PURE_TRACE_CALLS=sceDisplay:0x289D82FE (a `[call]` line per flip, its virtual time t=),
# PURE_WATCH_SHIP=1, a shot at flip 6100 (h6100) and the run ending at flip END, one with --env PURE_SMOOTH_FLASHES=0
# and one with 1, on the data directory out/data/flash_check (about 7 s each headless). For each run, over flips
# 5600 to 6100: the flips whose t is more than tools/fidelity_audit.py's TWO_VBLANK_US after the previous flip's
# (two vblanks or more), their count and their longest run. TEAM SELECTION and the race load before the race's first
# one-vblank flip (5707) wait two vblanks in both runs: the frontend's lock (+0x116c 0), which the option leaves alone.
# The fade is the first run of such flips after that (flips 5708 to 5764 in the run with 0, 1.90 s), and its seconds
# run from the flip before it to its last. PASS when the run with 0 has a fade of at least MIN_FADE flips, the run with
# 1 has at most MAX_ON two-vblank flips in all from the fade's first flip to 6100, both runs have a `[pure] ship frame`
# line with clock= above 0 by flip END (the race runs; its clock starts at about 6250 with 0 and 6310 with 1, after
# 6100), the HUD is drawn at 6100 in both (tools/hud_check.py), the run with 0 prints `[pure] smooth flashes: off` and
# no `on`, and the run with 1 prints `on` once, during the race (the frontend's +0x116c is 0). Printed for both: the
# counts, the longest runs, the fade (flips and seconds; for the run with 1, the flips the fade's seconds span from
# the same first flip, the fade itself not being visible in its flip times) and the race's start (the first clock
# above 0: flips and seconds from the fade's first flip): with the option on the same seconds take more flips.
# --race: two Single Race cells of Vineta K through tools/campaign_sweep.py single_race vineta_k --no-damage (the
# sweep's defaults: headless, paced from the Cross hold, the follower; about 4 minutes each), one with
# PURE_SMOOTH_FLASHES=0 in the environment and one with 1, each in <out>/<0|1>/, their logs read with
# tools/fidelity_audit.py's scan_log (its two-vblank stretch rule: STRETCH_MIN flips in a row over TWO_VBLANK_US).
# PASS when both cells PASS, the run with 1 has no stretch and its mean lap time is within LAP_TOLERANCE of the run
# with 0's (the race's speed unchanged: the follower drives the same table). Prints both runs' stretches and laps.
# Waits up to 600 s while another PureNative runs (one game at a time). Prints `flash_check: PASS ...` or
# `flash_check: FAIL ...` last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD

FROM=5600         # the counted flips: TEAM SELECTION's last 100, the load, the race-start fade, the countdown
SHOT=6100         # the HUD shot and the end of the counted flips
END=6400          # the run's end: the race clock starts at about 6250 (0) and 6310 (1)
PACED_FROM=5500   # a window shell's pace (frame_regress.sh's margin before the scene)
MIN_FADE=50       # the fade's flips at two vblanks with the option off (57: flips 5708 to 5764)
MAX_ON=2          # two-vblank flips from the fade's first to 6100 with the option on
LAP_TOLERANCE=0.05

RACE=no
SHELL_NAME=headless
BACKEND=
OUT=
usage() {
  echo "usage: tools/flash_check.sh [--race] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --race) RACE=yes; shift ;;
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "flash_check: unknown argument $1"; usage ;;
  esac
done
case $SHELL_NAME in
  headless|metal) BACKEND=${BACKEND:-metal} ;;
  vulkan) BACKEND=${BACKEND:-vulkan} ;;
  *) echo "flash_check: --shell is headless, metal or vulkan, not $SHELL_NAME"; exit 2 ;;
esac
case $BACKEND in metal|vulkan) ;; *) echo "flash_check: --backend is metal or vulkan, not $BACKEND"; exit 2 ;; esac
MODE=fade
[ "$RACE" = yes ] && MODE=race
OUT=${OUT:-out/flash_check/$MODE-$BACKEND-$SHELL_NAME}

EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
[ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

# One game at a time (task 034).
wait_game() {
  python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("flash_check: " + m, flush=True),
                              limit=600) else 2)'
}

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "flash_check: $MODE, shell $SHELL_NAME, backend $BACKEND, out $OUT"

if [ "$MODE" = race ]; then
  for v in 0 1; do
    wait_game || exit 2
    t0=$SECONDS
    PURE_SMOOTH_FLASHES=$v python3 tools/campaign_sweep.py single_race vineta_k --no-damage --out "$OUT/$v" \
      --shell "$SHELL_NAME" --backend "$BACKEND" > "$OUT/$v.stdout" 2>&1
    echo "flash_check: PURE_SMOOTH_FLASHES=$v: campaign_sweep exit $?, $((SECONDS - t0)) s, log $OUT/$v/single_race-vineta_k.log"
  done
  python3 - "$OUT" "$LAP_TOLERANCE" <<'EOF' | tee "$OUT/summary.txt"
import os, re, sys
sys.path.insert(0, "tools")
from fidelity_audit import SWEEP_LINE_RE, STRETCH_MIN, TWO_VBLANK_US, scan_log  # the audit's rule, not a copy

out, tolerance = sys.argv[1], float(sys.argv[2])
LAPS_RE = re.compile(r"(\d+) laps: ([\d.]+(?:, [\d.]+)*) s")
runs = {}
for v in ("0", "1"):
    log = os.path.join(out, v, "single_race-vineta_k.log")
    outcome, laps = None, []
    with open(os.path.join(out, f"{v}.stdout"), errors="replace") as f:
        for line in f:
            m = SWEEP_LINE_RE.match(line.strip())
            if m and m[1] == "single_race-vineta_k":
                outcome = m[2]
                lm = LAPS_RE.search(m[8])
                laps = [float(x) for x in lm[2].split(", ")] if lm else []
    found = scan_log(log) if os.path.exists(log) else {"stretches": []}
    runs[v] = (outcome, laps, found["stretches"])
    mean = sum(laps) / len(laps) if laps else None
    print(f"PURE_SMOOTH_FLASHES={v}: {outcome or 'no outcome'}, laps "
          f"{', '.join(f'{x:.1f}' for x in laps) or '-'} s (mean {f'{mean:.2f}' if mean else '-'} s), "
          f"{len(found['stretches'])} two-vblank stretch(es) ({STRETCH_MIN}+ flips over {TWO_VBLANK_US} us)")
    for s in found["stretches"]:
        print(f"  flip {s['flip']}: {s['flips']} flips, {s['seconds']} s, lap {s['lap']}, {s['dist']} m, {s['kmh']} km/h")
(o0, l0, s0), (o1, l1, s1) = runs["0"], runs["1"]
fails = []
if o0 != "PASS" or o1 != "PASS":
    fails.append(f"outcomes {o0} and {o1}")
if s1:
    fails.append(f"{len(s1)} stretch(es) with the option on")
ratio = None
if l0 and l1:
    ratio = (sum(l1) / len(l1)) / (sum(l0) / len(l0))
    if abs(ratio - 1.0) > tolerance:
        fails.append(f"mean lap with the option on {ratio - 1.0:+.1%} of the run with it off (game speed moved?)")
else:
    fails.append("no lap times")
lap = f"mean lap {ratio - 1.0:+.1%}" if ratio is not None else "no laps"
print(f"flash_check: {'FAIL' if fails else 'PASS'} (race: stretches {len(s0)} off, {len(s1)} on; {lap} on against "
      f"off{'; ' + '; '.join(fails) if fails else ''})")
EOF
  grep -q '^flash_check: PASS' "$OUT/summary.txt"
  exit $?
fi

for v in 0 1; do
  d=$OUT/$v
  mkdir -p "$d/game/ms0/PSP/SAVEDATA" "$d/shots"
  ln -s "$ROOT/game/EBOOT.ELF" "$d/game/EBOOT.ELF"
  ln -s "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$d/game/disc.iso"
  {
    echo "$SHOT:shot h$SHOT"
    cat config/pad_scripts/main_menu.txt config/pad_scripts/single_race.txt |
      grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)'
  } > "$d/route.txt"
  PACE=()
  [ "$SHELL_NAME" = headless ] || PACE=(--env PURE_PACED_FROM=$PACED_FROM)
  wait_game || exit 2
  t0=$SECONDS
  python3 tools/run_boot.py --script "$d/route.txt" --shots "$d/shots" --frames $END --shell "$SHELL_NAME" \
    --backend "$BACKEND" --data-dir out/data/flash_check --max-lines 60000 --env PURE_GAME_DIR="$d/game" \
    --env PURE_SMOOTH_FLASHES=$v --env PURE_TRACE_CALLS=sceDisplay:0x289D82FE --env PURE_WATCH_SHIP=1 \
    ${PACE[@]+"${PACE[@]}"} "$d/run.log" > "$d/run.stdout" 2>&1
  rc=$?
  reached=no
  grep -q "^\[pure\] exit at frame $END" "$d/run.log" && reached=yes
  echo "flash_check: PURE_SMOOTH_FLASHES=$v: run_boot exit $rc, frame $END reached: $reached, $((SECONDS - t0)) s, log $d/run.log"
  python3 tools/hud_check.py "$d/shots" --expect 1 > "$d/hud.txt" 2>&1
  echo "  $(tail -1 "$d/hud.txt")"
done

python3 - "$OUT" $FROM $SHOT $END $MIN_FADE $MAX_ON <<'EOF' | tee "$OUT/summary.txt"
import os, re, sys
sys.path.insert(0, "tools")
from fidelity_audit import TWO_VBLANK_US  # the audit's two-vblank rule
from purelib.logs import SHIP_T_RE

out = sys.argv[1]
first, shot, end, min_fade, max_on = (int(v) for v in sys.argv[2:7])
CALL = "[call] sceDisplay:0x289D82FE "


def read(v):
    """The run's flip times (index n - 1 for flip n), its race start (flip, t) and the smooth-flashes lines (text,
    the flips before each)."""
    ts, start, said = [], None, []
    with open(os.path.join(out, v, "run.log"), errors="replace") as f:
        for line in f:
            if line.startswith(CALL):
                ts.append(int(re.search(r" t=(\d+)", line)[1]))
            elif line.startswith("[pure] smooth flashes:"):
                said.append((line.strip(), len(ts)))
            else:
                m = SHIP_T_RE.match(line)
                if m and start is None and float(m[3]) > 0.0:
                    start = (int(m[1]), int(m[2]))
    return ts, start, said


def slow(ts, n):
    return 2 <= n <= len(ts) and ts[n - 1] - ts[n - 2] > TWO_VBLANK_US


def runs_in(ts, a, b):
    """The runs of two-vblank flips among flips a..b: [(first, last)]."""
    found = []
    for n in range(a, min(b, len(ts)) + 1):
        if not slow(ts, n):
            continue
        if found and found[-1][1] == n - 1:
            found[-1] = (found[-1][0], n)
        else:
            found.append((n, n))
    return found


runs = {v: read(v) for v in ("0", "1")}
fails = []
ts0 = runs["0"][0]
race0 = next((n for n in range(first, min(shot, len(ts0)) + 1) if not slow(ts0, n)), None)
# The longest run, not the first: the race's first flips jitter (a one-vblank flip amid the two-vblank settle,
# a cold cache's compile stall), and a 2-flip fragment before the real fade fooled the first-run rule three times
# on the Windows rig (tasks 077 and 078). The 57-flip expectation below is unchanged.
fade = max(runs_in(ts0, race0 + 1, shot), key=lambda r: r[1] - r[0], default=None) if race0 else None
if fade is None:
    fails.append("no fade in the run with 0")
fade_s = (ts0[fade[1] - 1] - ts0[fade[0] - 2]) / 1e6 if fade else 0.0
for v in ("0", "1"):
    ts, start, said = runs[v]
    if len(ts) < end:
        fails.append(f"{v}: {len(ts)} flips traced, not {end}")
        continue
    rs = runs_in(ts, first, shot)
    count, longest = sum(b - a + 1 for a, b in rs), max((b - a + 1 for a, b in rs), default=0)
    race = next((n for n in range(first, shot + 1) if not slow(ts, n)), None)
    front = sum(b - a + 1 for a, b in runs_in(ts, first, race - 1)) if race else count
    line = (f"PURE_SMOOTH_FLASHES={v}: flips {first}-{shot}: {count} at two vblanks, longest run {longest}; "
            f"{front} before the race's first one-vblank flip ({race})")
    if fade:
        on = runs_in(ts, fade[0], shot)
        in_fade = sum(b - a + 1 for a, b in on)
        if v == "0":
            line += f"; the fade: flips {fade[0]}-{fade[1]}, {fade[1] - fade[0] + 1} flips, {fade_s:.2f} s"
        else:
            spanned = sum(1 for n in range(fade[0], len(ts) + 1) if ts[n - 1] - ts[fade[0] - 2] <= fade_s * 1e6 + 1000)
            line += (f"; from the fade's first flip ({fade[0]}) to {shot}: {in_fade} at two vblanks"
                     f"{' (' + ', '.join(f'{a}-{b}' for a, b in on) + ')' if on else ''}; the fade's {fade_s:.2f} s "
                     f"span flips {fade[0]}-{fade[0] + spanned - 1}, {spanned} flips")
            if in_fade > max_on:
                fails.append(f"{in_fade} two-vblank flips with the option on (at most {max_on})")
        if start:
            line += (f"; the race clock starts at flip {start[0]}, {start[0] - fade[0] + 1} flips and "
                     f"{(start[1] - ts[fade[0] - 2]) / 1e6:.2f} s from the fade's first")
    if start is None or start[0] > end:
        fails.append(f"{v}: no race clock above 0 by flip {end}")
    texts = [t for t, _ in said]
    if v == "0" and (texts != ["[pure] smooth flashes: off"]):
        fails.append(f"0: smooth flashes lines {texts}")
    if v == "1":
        ons = [(t, n) for t, n in said if t.startswith("[pure] smooth flashes: on")]
        if len(said) != 1 or len(ons) != 1 or ons[0][1] < first:
            fails.append(f"1: smooth flashes lines {said}")
        else:
            line += f"; '{ons[0][0]}' after flip {ons[0][1]}"
    with open(os.path.join(out, v, "hud.txt")) as f:
        hud = f.read().strip().splitlines()
    if not hud or not hud[-1].startswith("hud_check: 1 of 1 "):
        fails.append(f"{v}: no HUD at {shot} ({hud[-1] if hud else 'no hud_check output'})")
    print(line)
if fade and fade[1] - fade[0] + 1 < min_fade:
    fails.append(f"the fade with the option off is {fade[1] - fade[0] + 1} flips (at least {min_fade})")
fade_text = f"fade {fade[1] - fade[0] + 1} flips off" if fade else "no fade"
on_text = (f", {sum(b - a + 1 for a, b in runs_in(runs['1'][0], fade[0], shot))} on" if fade else "")
print(f"flash_check: {'FAIL' if fails else 'PASS'} ({fade_text}{on_text}"
      f"{'; ' + '; '.join(fails) if fails else '; the race and its HUD in both'})")
EOF
grep -q '^flash_check: PASS' "$OUT/summary.txt"
