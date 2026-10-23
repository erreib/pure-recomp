#!/bin/bash
# The shield check (task 107, GitHub issue 2): the Shield effect (the shell that builds up over a ship when it raises
# its shield, flashes at a contact and fades at the end) at the PSP's 59.94 Hz and at a 120 Hz display's rate, side by
# side. Its update FUN_08946918 eases in whole 60 Hz frames of the frame's dt, none at 119.40 Hz, so without
# src/profile/shield_step.cpp's override the effect never builds up, a contact's flash stays, and the effect never
# fades to its delete test (docs/timing.md, "The shield effect (task 107)").
#   tools/shield_check.sh [--no-step] [--out DIR]
#   --no-step  the run at 120 with PURE_SHIELD_STEP=0 (the generated code at the display's rate): the check then FAILs,
#              which shows the switch and the check are real.
#   --out      default out/shield_check (out/shield_check-no-step with --no-step); removed first.
# Two Single Race cells of Vineta K through tools/campaign_sweep.py single_race vineta_k --no-damage (headless, paced
# from the Cross hold, the follower; seven AI ships, who raise shields, about 8 to 20 effects a race), both with
# PURE_TRACE_SHIELD=1: lane 0 at the PSP's rate (the sweep's PURE_DISPLAY_RATE=0), lane 1 with PURE_DISPLAY_RATE=1
# PURE_DISPLAY_HZ=120 and --frames FRAMES1 (the budget counts flips: 120 a second), each in <out>/<0|1>/ (about 3.5
# minutes each). --no-damage keeps the player's ship from being destroyed, which would end a lane early. From each
# log, every effect's `new` and `end` lines (src/profile/shield_step.cpp): its life (its own clock at its last live
# flip), its rise (the clock when its colour's alpha first reached 90% of the target's, `-` never), its fade (from the
# dying flag to the end) and how it ended (`deleted` by its own delete test, `replaced` by the ship's next shield,
# `killed`, `gone` with the race); an effect with no `end` is live at the run's end, aged by its last line's clock.
# PASS when lane 0 prints no `[pure] shield step` line (Original registers nothing) and has at least MIN_EFFECTS
# effects ended `deleted` (the median's sample), lane 1 prints the override's line once and has at least MIN_EFFECTS
# effects, and in lane 1 every effect built up (a rise) and ended (`deleted`, `replaced` or `killed`; one live at the
# end or `gone` with the race only when younger than lane 0's median life plus LIFE_PCT), each `deleted` one's life
# is within LIFE_PCT of lane 0's median, and lane 1's median rise and fade are within STEP_PCT of STEP_S (15 steps of
# 1/60 s, the decompile's: the alpha from 0 to 90% of 1.0 and from 1.0 to the delete test's 0.1 at 0.15 a step).
# Lane 0's own rise and fade are printed, not bounded: the port's 1 ms clock makes a third of its 59.94 Hz frames
# 15.683 ms, which take no step, so Original eases at about 38 steps a second (0.37 to 0.47 s) where the PSP's
# 16.68 ms frames give 60 (task 107's sighting run). Printed for both: the effects, their medians and ranges, the
# sweep's outcome and the wall time.
# Waits up to 600 s while another PureNative runs (one game at a time). Prints `shield_check: PASS ...` or
# `shield_check: FAIL ...` last; exit 0 only on PASS (2 for a usage error).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

HZ=120            # the display rate of lane 1
FRAMES1=26000     # lane 1's sweep budget in flips (the cell's 13000 at 60 a second)
MIN_EFFECTS=4     # effects a lane needs for its figures to mean anything
LIFE_PCT=0.10     # lane 1's lives about lane 0's median
STEP_S=0.25       # 15 steps of 1/60 s: the rise and the fade at 60 steps a second
STEP_PCT=0.10

STEP=1
OUT=
usage() {
  echo "usage: tools/shield_check.sh [--no-step] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --no-step) STEP=0; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "shield_check: unknown argument $1"; usage ;;
  esac
done
if [ -z "$OUT" ]; then
  OUT=out/shield_check
  [ "$STEP" = 0 ] && OUT=out/shield_check-no-step
fi
need_game
unset PURE_DISPLAY_HZ PURE_DISPLAY_MARGIN PURE_SHIELD_STEP

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "shield_check: lanes 59.94 Hz and $HZ Hz (PURE_SHIELD_STEP=$STEP there), out $OUT"

for v in 0 1; do
  ENV=(PURE_TRACE_SHIELD=1)
  FRAMES=()
  if [ "$v" = 1 ]; then
    ENV+=(PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=$HZ PURE_SHIELD_STEP=$STEP)
    FRAMES=(--frames $FRAMES1)
  fi
  wait_game shield_check || exit 2
  t0=$SECONDS
  env "${ENV[@]}" python3 tools/campaign_sweep.py single_race vineta_k --no-damage --out "$OUT/$v" \
    ${FRAMES[@]+"${FRAMES[@]}"} > "$OUT/$v.stdout" 2>&1
  rc=$?
  echo "$((SECONDS - t0))" > "$OUT/$v.seconds"
  echo "shield_check: lane $v: campaign_sweep exit $rc, $((SECONDS - t0)) s, log $OUT/$v/single_race-vineta_k.log"
done

python3 - "$OUT" "$STEP" "$MIN_EFFECTS" "$LIFE_PCT" "$STEP_S" "$STEP_PCT" <<'EOF' | tee "$OUT/summary.txt"
import os, re, statistics, sys

out, step = sys.argv[1], sys.argv[2] == "1"
min_effects = int(sys.argv[3])
life_pct, step_s, step_pct = (float(x) for x in sys.argv[4:7])
CELL = "single_race-vineta_k"
NEW = re.compile(r"\[pure\] shield frame (\d+) ship (\d+) obj (0x[0-9A-F]+) new t=([\d.]+)")
LIVE = re.compile(r"\[pure\] shield frame (\d+) ship (\d+) obj (0x[0-9A-F]+) t=[\d.]+ clock=([\d.]+)")
END = re.compile(r"\[pure\] shield frame (\d+) ship (\d+) obj (0x[0-9A-F]+) end (\w+) life=([\d.]+) "
                 r"rise=([\d.-]+) fade=([\d.-]+) steps=(\d+)")
OUTCOME = re.compile(r"^\| single_race \| vineta_k \| (\w+) \|")


def num(s):
    return None if s == "-" else float(s)


def read(v):
    """The lane's effects (each a dict: ship, frame, t, how, life, rise, fade, steps; how None while live at the
    end), its `[pure] shield step` lines and the sweep's outcome."""
    effects, open_, steps, outcome = [], {}, [], None
    with open(os.path.join(out, v, CELL + ".log"), errors="replace") as f:
        for line in f:
            if "[pure] shield step" in line:
                steps.append(line.strip())
            m = NEW.search(line)
            if m:
                e = {"ship": int(m[2]), "frame": int(m[1]), "t": float(m[4]), "how": None, "life": 0.0,
                     "rise": None, "fade": None, "steps": 0}
                effects.append(e)
                open_[m[3]] = e
                continue
            m = LIVE.search(line)
            if m and m[3] in open_:
                open_[m[3]]["life"] = float(m[4])
                continue
            m = END.search(line)
            if m and m[3] in open_:
                e = open_.pop(m[3])
                e.update(how=m[4], life=float(m[5]), rise=num(m[6]), fade=num(m[7]), steps=int(m[8]))
    with open(os.path.join(out, f"{v}.stdout"), errors="replace") as f:
        for line in f:
            m = OUTCOME.match(line)
            if m:
                outcome = m[1]
    return effects, steps, outcome


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def rng(xs):
    xs = [x for x in xs if x is not None]
    return f"{min(xs):.3f} to {max(xs):.3f}" if xs else "-"


def fmt(x):
    return f"{x:.3f}" if x is not None else "-"


lanes = {v: read(v) for v in ("0", "1")}
fails = []
for v, name in (("0", "59.94 Hz"), ("1", "120 Hz")):
    effects, steps, outcome = lanes[v]
    seconds = open(os.path.join(out, f"{v}.seconds")).read().strip()
    hows = {}
    for e in effects:
        hows[e["how"] or "live"] = hows.get(e["how"] or "live", 0) + 1
    deleted = [e for e in effects if e["how"] == "deleted"]
    print(f"lane {v} ({name}): the sweep {outcome or 'gave no outcome'}, {seconds} s; {len(effects)} effects "
          f"({', '.join(f'{n} {h}' for h, n in sorted(hows.items())) or 'none'}); life of the deleted: median "
          f"{fmt(med(e['life'] for e in deleted))} s ({rng(e['life'] for e in deleted)}); rise median "
          f"{fmt(med(e['rise'] for e in effects))} ({rng(e['rise'] for e in effects)}); fade median "
          f"{fmt(med(e['fade'] for e in deleted))} ({rng(e['fade'] for e in deleted)})")
    for e in effects:
        print(f"  ship {e['ship']} from flip {e['frame']} (t={e['t']:.3f}): {e['how'] or 'live at the end'}, life "
              f"{e['life']:.3f}, rise {fmt(e['rise'])}, fade {fmt(e['fade'])}, steps {e['steps']}")
    for s in steps:
        print(f"  {s}")

effects0, steps0, _ = lanes["0"]
effects1, steps1, _ = lanes["1"]
if steps0:
    fails.append(f"lane 0 printed {len(steps0)} `[pure] shield step` line(s): Original registered something")
deleted0 = [e["life"] for e in effects0 if e["how"] == "deleted"]
if len(deleted0) < min_effects:
    fails.append(f"lane 0: {len(deleted0)} effects ended deleted (under {min_effects}: no median to compare with)")
want = "overridden" if step else "off (PURE_SHIELD_STEP=0)"
if len(steps1) != 1 or want not in steps1[0]:
    fails.append(f"lane 1: {len(steps1)} `[pure] shield step` line(s), not one saying {want}")
if len(effects1) < min_effects:
    fails.append(f"lane 1: {len(effects1)} effects (under {min_effects})")
life0 = med(deleted0)
for e in effects1:
    what = f"lane 1: ship {e['ship']}'s effect from flip {e['frame']}"
    if e["rise"] is None:
        fails.append(f"{what} never built up")
    if life0 is not None:
        lo, hi = life0 * (1 - life_pct), life0 * (1 + life_pct)
        if e["how"] in (None, "gone"):
            if e["life"] > hi:
                fails.append(f"{what} still showing after {e['life']:.3f} s (lane 0's lives end by {hi:.3f})")
        elif e["how"] == "deleted" and not lo <= e["life"] <= hi:
            fails.append(f"{what} lived {e['life']:.3f} s (not {lo:.3f} to {hi:.3f}, lane 0's median "
                         f"{life0:.3f} +-{life_pct:.0%})")
rise1 = med(e["rise"] for e in effects1)
fade1 = med(e["fade"] for e in effects1 if e["how"] == "deleted")
for what, x in (("rise", rise1), ("fade", fade1)):
    if x is None or abs(x - step_s) > step_pct * step_s:
        fails.append(f"lane 1's median {what} {fmt(x)} s (not {step_s:g} s +-{step_pct:.0%}: 15 steps at 60 a second)")
summary = (f"lanes 0 and 1: {len(effects0)} and {len(effects1)} effects, median life {fmt(life0)} and "
           f"{fmt(med(e['life'] for e in effects1 if e['how'] == 'deleted'))} s, rise {fmt(med(e['rise'] for e in effects0))} "
           f"and {fmt(rise1)} s, fade {fmt(med(e['fade'] for e in effects0 if e['how'] == 'deleted'))} and {fmt(fade1)} s")
if len(fails) > 8:
    fails = fails[:8] + [f"and {len(fails) - 8} more"]
print(f"shield_check: {'FAIL' if fails else 'PASS'} ({summary}{'; ' + '; '.join(fails) if fails else ''})")
EOF
grep -q '^shield_check: PASS' "$OUT/summary.txt"
exit $?
