#!/bin/bash
# The models check (task 102, D-025's check for the Crowds and people row): headless on the Metal backend through the
# models backend (PURE_GE_BACKEND=models, PURE_GE_MODELS_INNER=metal, PURE_INTERNAL_SCALE=1, PURE_TRACE_MODELS=1; no
# window), the frame regression suite's scenes (tools/frame_regress.sh --only) run twice:
#   0  tt_hud with PURE_CROWD_MODELS=0 (Original: every draw goes through);
#   1  tt_hud and race_hud with PURE_CROWD_MODELS=1 (Models: the pit marshals' six quads drawn as models/pitguy.pmdl).
#   tools/models_check.sh [--out DIR] [--wait SECONDS]
#   --out   default out/models_check: DIR/0 and DIR/1 hold each run's captures and logs (tools/frame_regress.sh --out),
#           DIR/<scene>.diff.png the differing pixels of a scene over its allowance, DIR/summary.txt the table
#   --wait  how long the runs wait for another game to end before they start (tools/frame_regress.sh --wait; default
#           600, 0 gives up at once)
# PASS when:
#   - tt_hud's 1 capture differs from its 0 capture in at least MIN_PIXELS (150) pixels at tol DIFF_TOL (24): the
#     figures are there (at 1x a marshal is about 18 pixels tall; the placeholder's three on screen move 213, all in
#     x 115-155, y 127-145, the booths at the left of the straight);
#   - the 0 run's `[models] frame F: ... (captured)` line for tt_hud says 0 draws replaced, and the 1 run's says 6
#     for each scene (the six booths' quads are in both frames);
#   - each 1 capture is within its scene's limit plus SLACK (0.02) of its PPSSPP reference at the scene's tol, both
#     read from tools/frame_regress.sh's table.
# The 1 run's `[texpack]` line is quoted: the Metal backend under the wrapper still looks for its texture pack.
# About a minute. Prints PASS or FAIL last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

OUT=out/models_check
WAIT=600
usage() {
  echo "usage: tools/models_check.sh [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "models_check: unknown argument $1"; usage ;;
  esac
done
need_game
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/0" "$OUT/1"
rm -f "$OUT"/*.diff.png "$OUT/summary.txt" "$OUT"/frame_regress.*.stdout
START=$SECONDS

# capture NAME V SCENES: the scenes headless through the models backend over Metal with PURE_CROWD_MODELS=V.
capture() {
  local name=$1 v=$2 scenes=$3
  echo "models_check: run $name (PURE_CROWD_MODELS=$v): $scenes ..."
  tools/frame_regress.sh --wait "$WAIT" --out "$OUT/$name" --only "$scenes" \
    --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env PURE_INTERNAL_SCALE=1 \
    --env PURE_TRACE_MODELS=1 --env "PURE_CROWD_MODELS=$v" > "$OUT/frame_regress.$name.stdout" 2>&1
  if ! grep -q '^frame regression: ' "$OUT/frame_regress.$name.stdout"; then
    cat "$OUT/frame_regress.$name.stdout"
    echo "models_check: tools/frame_regress.sh could not run"
    echo "models_check: FAIL"
    exit 1
  fi
}
capture 0 0 tt_hud
capture 1 1 tt_hud,race_hud

python3 - "$OUT" "$((SECONDS - START))" <<'EOF'
import glob, os, re, sys
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)

out, seconds = sys.argv[1], sys.argv[2]
DIFF_TOL, MIN_PIXELS = 24, 150       # the 1 capture against the 0 one: the figures' pixels (213 with the placeholder)
SLACK = 0.02                         # over the scene's own limit: the figures are not in the PPSSPP reference
WANT = 6                             # the pit marshal's quads in both frames (task 101)
LINE = re.compile(r"^\[models\] frame (\d+): (\d+) draws replaced by (\d+) model draws, (\d+) quads \(captured\)")
lines = []


def note(text=""):
    print(text)
    lines.append(text)


def scene_table():
    """{scene: (route, frame, reference, tol, limit)} from tools/frame_regress.sh's SCENES table."""
    with open("tools/frame_regress.sh") as f:
        block = f.read().split("SCENES='", 1)[1].split("'", 1)[0]
    table = {}
    for line in block.splitlines():
        fields = line.split("#", 1)[0].split()
        if len(fields) >= 8:
            table[fields[0]] = (fields[1], int(fields[2]), fields[3], int(fields[4]), float(fields[5]))
    return table


def log_of(run, route):
    return os.path.join(out, run, route.replace(".txt", "") + ".log")


def captured(run, route):
    """The run's `[models] ... (captured)` lines for the route: (frame, replaced, model draws, quads) each."""
    try:
        with open(log_of(run, route), encoding="utf-8", errors="replace") as f:
            return [tuple(int(x) for x in m.groups()) for m in map(LINE.match, f) if m]
    except OSError:
        return []


def first_line(run, route, prefix):
    try:
        with open(log_of(run, route), encoding="utf-8", errors="replace") as f:
            return next((ln.rstrip("\n") for ln in f if ln.startswith(prefix)), None)
    except OSError:
        return None


table = scene_table()
failed = []
note(f"models check: tt_hud and race_hud headless on Metal through the models backend, PURE_CROWD_MODELS 0 and 1 "
     f"({seconds} s)")
note(f"{'scene':<9} {'run':>3} {'models line':<46} {'vs ref':>7} {'allowed':>7} {'tol':>4} result")
for run, scenes in (("0", ["tt_hud"]), ("1", ["tt_hud", "race_hud"])):
    for scene in scenes:
        route, frame, ref, tol, limit = table[scene]
        cap = os.path.join(out, run, "shots", scene + ".png")
        why = []
        got = captured(run, route)
        want = 0 if run == "0" else WANT
        if not got:
            text = "none"
            why.append("no `[models] ... (captured)` line")
        else:
            f, n, m, k = got[0]
            text = f"frame {f}: {n} replaced, {m} model draws, {k} quads"
            if n != want:
                why.append(f"{n} draws replaced, not {want}")
        fraction = "-"
        allowed = limit + SLACK
        if not os.path.isfile(cap):
            why.append("no capture")
        elif run == "1":
            diff = os.path.join(out, scene + ".diff.png")
            r = imgdiff.compare_files(cap, ref, tol, allowed, diff)
            fraction = f"{r['fraction']:.4f}"
            if r["result"] != "PASS":
                why.append(f"over the limit {limit} + {SLACK}, diff {diff}")
            else:
                os.remove(diff)
        else:
            fraction = f"{imgdiff.compare_files(cap, ref, tol, 1.0)['fraction']:.4f}"
        result = "PASS" if not why else "FAIL (" + "; ".join(why) + ")"
        if why:
            failed.append(f"{scene} {run}")
        note(f"{scene:<9} {run:>3} {text:<46} {fraction:>7} {f'{allowed:.2f}' if run == '1' else '-':>7} {tol:>4} {result}")

# The figures are there: the 1 capture of tt_hud against the 0 one.
a, b = os.path.join(out, "1", "shots", "tt_hud.png"), os.path.join(out, "0", "shots", "tt_hud.png")
if os.path.isfile(a) and os.path.isfile(b):
    r = imgdiff.compare_files(a, b, DIFF_TOL, 1.0)
    ok = r["differing"] >= MIN_PIXELS
    note(f"tt_hud 1 against 0: {r['differing']} pixels differ at tol {DIFF_TOL} (at least {MIN_PIXELS}): "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        failed.append("tt_hud 1 against 0")
else:
    note("tt_hud 1 against 0: a capture is missing: FAIL")
    failed.append("tt_hud 1 against 0")
on = first_line("1", table["tt_hud"][0], "[pure] crowd models:")
off = first_line("0", table["tt_hud"][0], "[pure] crowd models:")
pack = first_line("1", table["tt_hud"][0], "[texpack]")
note(f"run 0: {off or 'no [pure] crowd models line'}")
note(f"run 1: {on or 'no [pure] crowd models line'}")
note(f"run 1: {pack or 'no [texpack] line'}")
note(f"models_check: {'PASS' if not failed else 'FAIL (' + ', '.join(failed) + ')'}")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(1 if failed else 0)
EOF
