#!/bin/bash
# The models check (task 102, D-025's check for the Crowds and people row): headless on the Metal backend through the
# models backend (PURE_GE_BACKEND=models, PURE_GE_MODELS_INNER=metal, PURE_INTERNAL_SCALE=1, PURE_TRACE_MODELS=1; no
# window), the frame regression suite's scenes (tools/frame_regress.sh --only) run twice:
#   0  tt_hud and race_hud with PURE_CROWD_MODELS=0 (Original: every draw goes through);
#   1  tt_hud and race_hud with PURE_CROWD_MODELS=1 (Models: the pit marshals' six quads drawn as models/pitguy.pmdl,
#      and since task 104 the grandstands' four crowd draws as the figure set crowd, in both frames);
#   2  (task 103) tt_hud's route on its own (tools/run_boot.py --script --shots) with two shots a second apart, frames
#      5890 and 5950, Models on at PURE_INTERNAL_SCALE=4, PURE_MODELS_CLOCK=frames and PURE_MODELS_SYNC=1 (the
#      clip at 2.15 s and 3.15 s: the arm raised, then lowered).
#   tools/models_check.sh [--out DIR] [--wait SECONDS]
#   --out   default out/models_check: DIR/0 and DIR/1 hold each run's captures and logs (tools/frame_regress.sh --out),
#           DIR/2 run 2's (shots/wave_a.png and wave_b.png, tt_hud.log),
#           DIR/<scene>.diff.png the differing pixels of a scene over its allowance, DIR/summary.txt the table
#   --wait  how long the runs wait for another game to end before they start (tools/frame_regress.sh --wait; default
#           600, 0 gives up at once)
# PASS when:
#   - tt_hud's 1 capture differs from its 0 capture in at least MIN_PIXELS (150) pixels at tol DIFF_TOL (24) inside
#     MARSHAL_BOX: the marshals are there (at 1x a marshal is about 18 pixels tall; the placeholder's three on screen
#     moved 213, all in x 115-155, y 127-145, the booths at the left of the straight; the box keeps the crowd's
#     figures, which the Time Trial frame shows too, out of the count);
#   - race_hud's 1 capture differs from its 0 capture in at least MIN_CROWD (2000) pixels at tol 24 (the stands
#     fill) and shows the HUD (tools/hud_check.py's two yellow labels);
#   - the 0 runs' `[models] frame F: ... (captured)` lines say 0 draws replaced, and the 1 run's say WANT (10) for
#     each scene, WANT_SETS (4) of them by a set (the six booths' quads and the four crowd draws are in both frames);
#     the line's figures and vertices are printed;
#   - each 1 capture is within its scene's limit plus its slack of its PPSSPP reference at the scene's tol, both read
#     from tools/frame_regress.sh's table: SLACK (0.02) for tt_hud, CROWD_SLACK (0.10) for race_hud, whose stands
#     are new art over a fifth of the picture that the reference does not have;
#   - run 2's two shots differ in at least MIN_WAVE (40) pixels at tol 24 inside WAVE_BOX (the left booth's marshals)
#     and in at most MAX_DECK (0) inside DECK_BOX (the deck under their feet): the arms move, the feet stay planted.
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
rm -rf "$OUT/0" "$OUT/1" "$OUT/2"
rm -f "$OUT"/*.diff.png "$OUT/summary.txt" "$OUT"/frame_regress.*.stdout
START=$SECONDS

# capture NAME V SCENES: the scenes headless through the models backend over Metal with PURE_CROWD_MODELS=V.
capture() {
  local name=$1 v=$2 scenes=$3
  echo "models_check: run $name (PURE_CROWD_MODELS=$v): $scenes ..."
  tools/frame_regress.sh --wait "$WAIT" --out "$OUT/$name" --only "$scenes" \
    --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env PURE_INTERNAL_SCALE=1 \
    --env PURE_TRACE_MODELS=1 --env PURE_MODELS_CLOCK=frames --env PURE_MODELS_SYNC=1 --env "PURE_CROWD_MODELS=$v" \
    > "$OUT/frame_regress.$name.stdout" 2>&1
  if ! grep -q '^frame regression: ' "$OUT/frame_regress.$name.stdout"; then
    cat "$OUT/frame_regress.$name.stdout"
    echo "models_check: tools/frame_regress.sh could not run"
    echo "models_check: FAIL"
    exit 1
  fi
}
capture 0 0 tt_hud,race_hud
capture 1 1 tt_hud,race_hud

# Run 2 (task 103): tt_hud's route (frame_regress.sh's table: main_menu.txt+time_trial.txt, its shot steps dropped)
# with two shots a second apart, wave_a at the scene's frame and wave_b WAVE_GAP flips later, Models on, the clips on
# the frame count with every phase 0 (PURE_MODELS_CLOCK=frames, PURE_MODELS_SYNC=1): the same two poses every run.
WAVE_A=5890 WAVE_GAP=60 WAVE_SCALE=4   # at 1x the arms move 20 pixels in the box (the marshals are 18 tall)
capture_wave() {
  local dir="$OUT/2"
  local script="$dir/route.txt"
  mkdir -p "$dir"
  echo "models_check: run 2 (PURE_CROWD_MODELS=1, the frames clock): tt_hud at $WAVE_A and $((WAVE_A + WAVE_GAP)) ..."
  wait_game models_check "$WAIT" || exit 2
  printf '%s:shot wave_a\n%s:shot wave_b\n' "$WAVE_A" "$((WAVE_A + WAVE_GAP))" > "$script"
  for part in main_menu.txt time_trial.txt; do
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)' "config/pad_scripts/$part" >> "$script"
  done
  fresh_stick "$dir/game"
  python3 tools/run_boot.py --shell headless --script "$script" --shots "$dir/shots" \
    --frames $((WAVE_A + WAVE_GAP + 30)) --data-dir out/data/frame_regress --env PURE_GAME_DIR="$dir/game" \
    --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env "PURE_INTERNAL_SCALE=$WAVE_SCALE" \
    --env PURE_TRACE_MODELS=1 --env PURE_CROWD_MODELS=1 --env PURE_MODELS_CLOCK=frames --env PURE_MODELS_SYNC=1 \
    "$dir/tt_hud.log" > "$dir/run_boot.stdout" 2>&1
}
capture_wave

python3 - "$OUT" "$((SECONDS - START))" <<'EOF'
import glob, os, re, sys
sys.path.insert(0, "tools")
import hud_check  # noqa: E402  (tools/hud_check.py: the HUD's labels)
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, seconds = sys.argv[1], sys.argv[2]
DIFF_TOL, MIN_PIXELS = 24, 150       # the 1 capture against the 0 one: the figures' pixels (213 with the placeholder)
MARSHAL_BOX = (108, 120, 56, 32)     # x 108-163, y 120-151: the left booth's marshals at 1x, where MIN_PIXELS counts
MIN_CROWD = 2000                     # race_hud 1 against 0: the stands' figures (task 104)
SLACK = 0.02                         # over the scene's own limit: the figures are not in the PPSSPP reference
CROWD_SLACK = {"race_hud": 0.10}     # the stands fill a fifth of race_hud's picture (task 104)
WANT, WANT_SETS = 10, 4              # the six marshals' quads and the four crowd draws, in both frames (task 101)
# Run 2's boxes, (x, y, w, h) on the 480x272 screen: the left booth's marshals and the deck under their feet, found
# once from a 4x headless capture of tt_hud (task 103, out/103/x4; Models off, the same two frames differ in 11 and 0
# pixels there, the scene's own change): MIN_WAVE pixels at least must differ in the first, at the capture's 4x pixels,
# MAX_DECK at most in the second (the feet stay planted, the camera still).
WAVE_BOX = (112, 124, 48, 22)     # x 112-159, y 124-145: the three marshals of the left booth, arms to feet
DECK_BOX = (112, 146, 48, 6)      # y 146-151: the booth's deck under their feet
MIN_WAVE, MAX_DECK = 40, 0
LINE = re.compile(r"^\[models\] frame (\d+): (\d+) draws replaced \((\d+) by a set\) by (\d+) model draws, "
                  r"(\d+) quads, (\d+) figures, (\d+) vertices \(captured\)")
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
    """The run's `[models] ... (captured)` lines for the route: (frame, replaced, by a set, model draws, quads,
    figures, vertices) each."""
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
note(f"models check: tt_hud and race_hud headless on Metal through the models backend, PURE_CROWD_MODELS 0 and 1, "
     f"the crowd, and the wave at 4x ({seconds} s)")
note(f"{'scene':<9} {'run':>3} {'models line':<84} {'vs ref':>7} {'allowed':>7} {'tol':>4} result")
for run, scenes in (("0", ["tt_hud", "race_hud"]), ("1", ["tt_hud", "race_hud"])):
    for scene in scenes:
        route, frame, ref, tol, limit = table[scene]
        cap = os.path.join(out, run, "shots", scene + ".png")
        why = []
        got = captured(run, route)
        want, want_sets = (0, 0) if run == "0" else (WANT, WANT_SETS)
        if not got:
            text = "none"
            why.append("no `[models] ... (captured)` line")
        else:
            f, n, sets, m, k, figures, vertices = got[0]
            text = f"frame {f}: {n} replaced ({sets} by a set), {m} model draws, {k} quads, {figures} figures, {vertices} vertices"
            if n != want or sets != want_sets:
                why.append(f"{n} draws replaced, {sets} by a set, not {want} and {want_sets}")
        fraction = "-"
        allowed = limit + CROWD_SLACK.get(scene, SLACK)
        if not os.path.isfile(cap):
            why.append("no capture")
        elif run == "1":
            diff = os.path.join(out, scene + ".diff.png")
            r = imgdiff.compare_files(cap, ref, tol, allowed, diff)
            fraction = f"{r['fraction']:.4f}"
            if r["result"] != "PASS":
                why.append(f"over the limit {limit} + {allowed - limit:.2f}, diff {diff}")
            else:
                os.remove(diff)
        else:
            fraction = f"{imgdiff.compare_files(cap, ref, tol, 1.0)['fraction']:.4f}"
        result = "PASS" if not why else "FAIL (" + "; ".join(why) + ")"
        if why:
            failed.append(f"{scene} {run}")
        note(f"{scene:<9} {run:>3} {text:<84} {fraction:>7} {f'{allowed:.2f}' if run == '1' else '-':>7} {tol:>4} {result}")

# The figures are there: the 1 capture of tt_hud against the 0 one in the marshals' box.
a, b = os.path.join(out, "1", "shots", "tt_hud.png"), os.path.join(out, "0", "shots", "tt_hud.png")
if os.path.isfile(a) and os.path.isfile(b):
    r = imgdiff.compare_files(a, b, DIFF_TOL, 1.0, region=MARSHAL_BOX)
    ok = r["differing"] >= MIN_PIXELS
    note(f"tt_hud 1 against 0: {r['differing']} pixels differ at tol {DIFF_TOL} in the marshals' box {MARSHAL_BOX} "
         f"(at least {MIN_PIXELS}): {'PASS' if ok else 'FAIL'}")
    if not ok:
        failed.append("tt_hud 1 against 0")
else:
    note("tt_hud 1 against 0: a capture is missing: FAIL")
    failed.append("tt_hud 1 against 0")
# The stands fill (task 104): race_hud 1 against 0 over the whole picture, and the HUD still drawn over them.
a, b = os.path.join(out, "1", "shots", "race_hud.png"), os.path.join(out, "0", "shots", "race_hud.png")
bmp = os.path.join(out, "1", "shots", "race_hud.bmp")
if os.path.isfile(a) and os.path.isfile(b) and os.path.isfile(bmp):
    r = imgdiff.compare_files(a, b, DIFF_TOL, 1.0)
    shot = png.read_bmp(bmp)
    labels = {name: hud_check.yellow(shot, region) for name, region in hud_check.REGIONS.items()}
    ok = r["differing"] >= MIN_CROWD and all(labels.values())
    note(f"race_hud 1 against 0: {r['differing']} pixels differ at tol {DIFF_TOL} (at least {MIN_CROWD}), the HUD's "
         f"labels {', '.join(f'{k} {v}' for k, v in labels.items())} yellow pixels (each at least 1): "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        failed.append("race_hud 1 against 0")
else:
    note("race_hud 1 against 0: a capture is missing: FAIL")
    failed.append("race_hud 1 against 0")
# The wave (run 2): the arm moves between the two frames inside the marshals' box, the deck below their feet does not.
wa, wb = os.path.join(out, "2", "shots", "wave_a.png"), os.path.join(out, "2", "shots", "wave_b.png")
times = []
try:
    with open(os.path.join(out, "2", "tt_hud.log"), encoding="utf-8", errors="replace") as f:
        times = [m.group(1) for m in map(re.compile(r"^\[models\] .*\(captured\); clip (\S+ t=\S+)").match, f) if m]
except OSError:
    pass
if os.path.isfile(wa) and os.path.isfile(wb):
    arm = imgdiff.compare_files(wa, wb, DIFF_TOL, 1.0, region=WAVE_BOX)["differing"]
    deck = imgdiff.compare_files(wa, wb, DIFF_TOL, 1.0, region=DECK_BOX)["differing"]
    ok = arm >= MIN_WAVE and deck <= MAX_DECK
    note(f"tt_hud wave ({' and '.join(times) or 'no clip in the trace'}): {arm} pixels differ in the marshals' box "
         f"{WAVE_BOX} (at least {MIN_WAVE}), {deck} in the deck {DECK_BOX} (at most {MAX_DECK}): "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        failed.append("tt_hud wave")
else:
    note("tt_hud wave: a capture is missing (run 2): FAIL")
    failed.append("tt_hud wave")
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
