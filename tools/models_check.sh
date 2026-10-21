#!/bin/bash
# The models check (task 102, D-025's check for the Crowds and people row): headless on the Metal backend through the
# models backend (PURE_GE_BACKEND=models, PURE_GE_MODELS_INNER=metal, PURE_INTERNAL_SCALE=1, PURE_TRACE_MODELS=1; no
# window), the frame regression suite's scenes (tools/frame_regress.sh --only) run twice:
#   0  tt_hud and race_hud with PURE_CROWD_MODELS=0 (Original: every draw goes through);
#   1  tt_hud and race_hud with PURE_CROWD_MODELS=1 (Models: the pit marshals' six quads drawn as models/pitguy.pmdl,
#      and since task 104 the grandstands' four crowd draws as the figure set crowd, in both frames);
#   3  (task 105) race_hud with PURE_CROWD_MODELS=1 and PURE_MODELS_NO_CACHE=1 (every batch built and uploaded each
#      frame);
#   4  (task 106) tt_hud and race_hud with PURE_CROWD_MODELS=1 and PURE_SKY_MODELS=1 (the Skies row: Vineta K's
#      five sky faces drawn as the layers of models.ini's [sky vineta_k]);
#   2  (task 103) tt_hud's route on its own (tools/run_boot.py --script --shots) with two shots a second apart, frames
#      5890 and 5950, Models on at PURE_INTERNAL_SCALE=4, PURE_MODELS_CLOCK=frames and PURE_MODELS_SYNC=1 (the
#      clip at 2.15 s and 3.15 s: the arm raised, then lowered).
#   tools/models_check.sh [--out DIR] [--wait SECONDS]
#   --out   default out/models_check: DIR/0, DIR/1, DIR/3 and DIR/4 hold each run's captures and logs (tools/frame_regress.sh --out),
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
#   - (task 105) the kept batches serve: run 1's race_hud captured line has batches reused above 0 (the crowd's
#     batches kept from the frames before at the same camera), run 3's has 0 with the same counts, and run 1's
#     race_hud capture equals run 3's at tol 0 (the cached picture is the uncached one); the share of run 1's race
#     lines with reuse is printed;
#   - run 2's two shots differ in at least MIN_WAVE (40) pixels at tol 24 inside WAVE_BOX (the left booth's marshals)
#     and in at most MAX_DECK (0) inside DECK_BOX (the deck under their feet): the arms move, the feet stay planted;
#   - (task 106) the sky: run 4's captured lines say `sky vineta_k L layers (5 faces replaced)` with L the section's
#     layers (2) for both scenes, each capture differs from run 1's in at least MIN_SKY pixels at tol 24 inside
#     SKY_BOX (the sky above the horizon), race_hud's HUD is found, and both are within the scene's limit plus 0.10
#     of their PPSSPP reference (the sky is new art over the top of the picture).
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
rm -rf "$OUT/0" "$OUT/1" "$OUT/2" "$OUT/3" "$OUT/4"
rm -f "$OUT"/*.diff.png "$OUT/summary.txt" "$OUT"/frame_regress.*.stdout
START=$SECONDS

# capture NAME V SCENES [ARG...]: the scenes headless through the models backend over Metal with PURE_CROWD_MODELS=V,
# the further arguments (--env K=V) to tools/frame_regress.sh.
capture() {
  local name=$1 v=$2 scenes=$3
  shift 3
  echo "models_check: run $name (PURE_CROWD_MODELS=$v): $scenes ..."
  tools/frame_regress.sh --wait "$WAIT" --out "$OUT/$name" --only "$scenes" \
    --env PURE_GE_BACKEND=models --env PURE_GE_MODELS_INNER=metal --env PURE_INTERNAL_SCALE=1 \
    --env PURE_TRACE_MODELS=1 --env PURE_MODELS_CLOCK=frames --env PURE_MODELS_SYNC=1 --env "PURE_CROWD_MODELS=$v" "$@" \
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
capture 3 1 race_hud --env PURE_MODELS_NO_CACHE=1
capture 4 1 tt_hud,race_hud --env PURE_SKY_MODELS=1

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
# The sky (task 106): the region above the horizon both scenes show between their buildings and stands, found once
# from 4x headless captures with the placeholder sky (out/106/x4; at 1x the Original's clouds against the dome's
# gradient), and the layers models.ini's [sky vineta_k] lists.
SKY_BOX = (150, 0, 85, 60)        # x 150-234, y 0-59 on the 480x272 screen
MIN_SKY, SKY_LAYERS, SKY_SLACK = 2000, 2, 0.10  # 3597 (race_hud) and 4602 (tt_hud) measured
SKY = re.compile(r"; sky (\S+) (\d+) layers \((\d+) faces replaced\)")
LINE = re.compile(r"^\[models\] frame (\d+): (\d+) draws replaced \((\d+) by a set\) by (\d+) model draws, "
                  r"(\d+) quads, (\d+) figures, (\d+) vertices, (\d+) batches reused( \(captured\))?")
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


def models_lines(run, route, only_captured=True):
    """The run's `[models]` lines for the route (only the `(captured)` ones by default): (frame, replaced, by a set,
    model draws, quads, figures, vertices, batches reused) each."""
    try:
        with open(log_of(run, route), encoding="utf-8", errors="replace") as f:
            return [tuple(int(x) for x in m.groups()[:8]) for m in map(LINE.match, f)
                    if m and (m.group(9) or not only_captured)]
    except OSError:
        return []


def captured(run, route):
    return models_lines(run, route)


def first_line(run, route, prefix):
    try:
        with open(log_of(run, route), encoding="utf-8", errors="replace") as f:
            return next((ln.rstrip("\n") for ln in f if ln.startswith(prefix)), None)
    except OSError:
        return None


table = scene_table()
failed = []
note(f"models check: tt_hud and race_hud headless on Metal through the models backend, PURE_CROWD_MODELS 0 and 1, "
     f"the crowd, the kept batches, and the wave at 4x ({seconds} s)")
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
            f, n, sets, m, k, figures, vertices, _ = got[0]
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
# The kept batches (task 105): reused in run 1's race_hud frame, none in run 3's, and the two pictures equal at tol 0.
race = table["race_hud"][0]
kept, uncached = captured("1", race), captured("3", race)
a, b = os.path.join(out, "1", "shots", "race_hud.png"), os.path.join(out, "3", "shots", "race_hud.png")
if kept and uncached and os.path.isfile(a) and os.path.isfile(b):
    reused, reused_off = kept[0][7], uncached[0][7]
    same = imgdiff.compare_files(a, b, 0, 1.0)["differing"]
    racing = [ln for ln in models_lines("1", race, False) if ln[1] > 0]
    with_reuse = sum(1 for ln in racing if ln[7] > 0)
    counts = uncached[0][1:7] == kept[0][1:7]
    ok = reused > 0 and reused_off == 0 and same == 0 and counts
    note(f"race_hud kept batches: frame {kept[0][0]} {reused} of {kept[0][3]} batches reused (above 0), "
         f"PURE_MODELS_NO_CACHE=1 {reused_off} of {uncached[0][3]} (0), the same counts {'yes' if counts else 'no'}, "
         f"{same} pixels differ at tol 0 (0); {with_reuse} of {len(racing)} lines with replaced draws reuse: "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        failed.append("race_hud kept batches")
else:
    note("race_hud kept batches: a line or a capture is missing (runs 1 and 3): FAIL")
    failed.append("race_hud kept batches")
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
# The sky (run 4): the faces replaced by the layers, the sky region changed against run 1, the HUD still drawn.
for scene in ("tt_hud", "race_hud"):
    route, frame, ref, tol, limit = table[scene]
    a, b = os.path.join(out, "4", "shots", scene + ".png"), os.path.join(out, "1", "shots", scene + ".png")
    why = []
    sky_line = None
    try:
        with open(log_of("4", route), encoding="utf-8", errors="replace") as f:
            sky_line = next((m for m in (SKY.search(ln) for ln in f if "(captured)" in ln) if m), None)
    except OSError:
        pass
    if sky_line is None:
        why.append("no `sky NAME L layers` in the captured line")
    elif int(sky_line.group(2)) != SKY_LAYERS or int(sky_line.group(3)) != 5:
        why.append(f"{sky_line.group(2)} layers for {sky_line.group(3)} faces, not {SKY_LAYERS} for 5")
    differing, fraction = 0, "-"
    if os.path.isfile(a) and os.path.isfile(b):
        differing = imgdiff.compare_files(a, b, DIFF_TOL, 1.0, region=SKY_BOX)["differing"]
        if differing < MIN_SKY:
            why.append(f"{differing} pixels differ in the sky's box, not {MIN_SKY}")
        diff = os.path.join(out, scene + ".sky.diff.png")
        r = imgdiff.compare_files(a, ref, tol, limit + SKY_SLACK, diff)
        fraction = f"{r['fraction']:.4f}"
        if r["result"] != "PASS":
            why.append(f"over the limit {limit} + {SKY_SLACK:.2f}, diff {diff}")
        else:
            os.remove(diff)
    else:
        why.append("a capture is missing (runs 1 and 4)")
    if scene == "race_hud":
        bmp = os.path.join(out, "4", "shots", "race_hud.bmp")
        if os.path.isfile(bmp):
            shot = png.read_bmp(bmp)
            if not all(hud_check.yellow(shot, region) for region in hud_check.REGIONS.values()):
                why.append("the HUD's labels are not found")
        else:
            why.append("no race_hud.bmp")
    text = sky_line.group(0).lstrip("; ") if sky_line else "no sky line"
    note(f"{scene} sky (run 4): {text}, {differing} pixels differ from run 1 at tol {DIFF_TOL} in {SKY_BOX} (at least "
         f"{MIN_SKY}), {fraction} vs ref (allowed {limit + SKY_SLACK:.2f}): {'PASS' if not why else 'FAIL (' + '; '.join(why) + ')'}")
    if why:
        failed.append(f"{scene} sky")
sky_on = first_line("4", table["tt_hud"][0], "[pure] skies:")
note(f"run 4: {sky_on or 'no [pure] skies line'}")
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
