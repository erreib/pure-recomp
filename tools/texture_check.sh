#!/bin/bash
# The texture detail check (task 075, D-019's check for E5): the one check run with the Texture detail option on.
# The four race HUD scenes of the frame regression suite, captured headless on Metal at PURE_INTERNAL_SCALE=4 twice,
# with PURE_TEXTURE_DETAIL=0 (the PSP's levels, what every other tool runs with: tools/purelib/port.py's
# original_pacing) and with 1 (the player's default: D lowered by 16 x log2(S), the mipmapped draws sampled
# anisotropically), and race_hud once more at PURE_INTERNAL_SCALE=1 with 1 (the shift is 0 there; only the anisotropy
# acts).
#   tools/texture_check.sh [--out DIR] [--wait SECONDS]
#   --out      default out/texture_check: DIR/0, DIR/1 and DIR/s1 hold each run's captures and logs
#              (tools/frame_regress.sh --out), DIR/1/reduced the 1 captures reduced to 480x272, DIR/hud/<scene>/
#              h<frame>.bmp the race scenes' 1 captures for tools/hud_check.py, DIR/<scene>.diff.png the differing
#              pixels of a scene whose reduction fails (DIR/race_hud.s1.diff.png for the scale 1 run), DIR/summary.txt
#              the table.
#   --wait     how long to wait for other games to end when the suite's one-game guard refuses to start (default 600;
#              0 gives up at once), as tools/sprite_check.sh waits.
# PASS when, for every scene:
#   - the 1 capture is 1920x1088 (the display target at internal scale 4);
#   - reduced to 480x272 by the centre pixel of each 4 x 4 block (tools/scale_check.sh's rule and code, copied: the
#     rule by which the backend feeds guest memory, D-015), it is within the scene's own limit of its PPSSPP reference
#     at the scene's tol, both read from tools/frame_regress.sh's scene table (the picture is the same picture);
#   - the full 1 capture differs from the full 0 capture in at least 1% of its pixels at tol 24 (the detail is there);
#   - the full 1 capture holds more high-frequency energy than the full 0 one: the mean absolute difference, per
#     channel, between each pixel and its right and its lower neighbour over the whole picture, the ratio of 1's to
#     0's above 1.0;
#   - for race_hud, tt_hud and fp_hud, the 1 capture passes tools/hud_check.py (the HUD found; not zone_hud, whose HUD
#     has no CURRENT or LAP label: its reference fails tools/hud_check.py too, as tools/sprite_check.sh notes);
# and the race_hud run with 1: its exit line (`[metal] ... M mipmapped draws (E enhanced, ...)`, the counts over the
# run) counts at least 10000 enhanced draws; its scale 1 capture is 480x272 and within the scene's limit of the
# reference at its tol, compared directly. Prints the table and `texture_check: PASS` or `FAIL` last. Exit 0 PASS,
# 1 FAIL, 2 cannot run (a suite refused for longer than --wait, no capture at all).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

DIR=out/texture_check
WAIT=600
SCALE=4
SCENES="race_hud tt_hud fp_hud zone_hud"
HUD_SCENES="race_hud tt_hud fp_hud"
usage() {
  echo "usage: tools/texture_check.sh [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "texture_check: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "texture_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
START=$SECONDS

# capture NAME SCALE V SCENES: the scenes headless on Metal at internal scale SCALE with PURE_TEXTURE_DETAIL=V, into
# DIR/NAME, retried while the one-game guard refuses, for up to --wait seconds. The suite's own verdict (each capture
# against its reference at its own size, by nearest neighbour) does not matter here.
capture() {
  local name=$1 scale=$2 v=$3 scenes=$4 where="$DIR/$1" waited=0 rc
  rm -rf "$where"
  mkdir -p "$where"
  while :; do
    tools/frame_regress.sh --out "$where" --shell headless --backend metal --only "$(echo $scenes | tr ' ' ',')" \
      --env "PURE_INTERNAL_SCALE=$scale" --env "PURE_TEXTURE_DETAIL=$v" > "$DIR/frame_regress.$name.stdout" 2>&1
    rc=$?
    grep -q '^frame_regress: another PureNative is running' "$DIR/frame_regress.$name.stdout" || break
    if [ $waited -ge "$WAIT" ]; then
      cat "$DIR/frame_regress.$name.stdout"
      echo "texture_check: another game kept running for $WAIT s; try again later"
      exit 2
    fi
    [ $waited -eq 0 ] && sed -n '2,$p' "$DIR/frame_regress.$name.stdout" | sed 's/^/  waiting for: /'
    sleep 20
    waited=$((waited + 20))
  done
  [ $waited -gt 0 ] && echo "  (waited $waited s for another game to end)"
  if [ $rc -eq 2 ]; then
    cat "$DIR/frame_regress.$name.stdout"
    echo "texture_check: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep -h '^\[pure\] texture detail' "$where"/*.log 2>/dev/null | sort | uniq -c |
    sed "s/^ */  scale $scale, PURE_TEXTURE_DETAIL=$v: /"
}

rm -rf "$DIR"/*.diff.png "$DIR/summary.txt" "$DIR/hud"
echo "texture check $(date '+%Y-%m-%d %H:%M'): $SCENES at internal scale $SCALE, PURE_TEXTURE_DETAIL 0 and 1, and" \
  "race_hud at scale 1 with 1, headless on Metal, into $DIR"
capture 0 "$SCALE" 0 "$SCENES"
capture 1 "$SCALE" 1 "$SCENES"
capture s1 1 1 race_hud

python3 - "$DIR" "$SCALE" "$SCENES" "$HUD_SCENES" "$((SECONDS - START))" <<'EOF'
import os, re, subprocess, sys
from operator import sub
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, scale, scenes, hud_scenes, seconds = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(), sys.argv[4].split(), \
    sys.argv[5]
DIFF_TOL, MIN_DIFF = 24, 0.01           # the full captures: at least 1% of pixels over tol 24
MIN_RATIO = 1.0                         # the high-frequency energy of 1 over 0's: above this
MIN_ENHANCED = 10000                    # enhanced draws over the race_hud run with 1
lines = []


def note(text=""):
    print(text)
    lines.append(text)


def scene_table():
    """{scene: (route, frame, reference, tol, limit)} from tools/frame_regress.sh's SCENES table."""
    with open("tools/frame_regress.sh") as f:
        text = f.read()
    block = text.split("SCENES='", 1)[1].split("'", 1)[0]
    table = {}
    for line in block.splitlines():
        fields = line.split("#", 1)[0].split()
        if len(fields) >= 8:
            table[fields[0]] = (fields[1], int(fields[2]), fields[3], int(fields[4]), float(fields[5]))
    return table


def centres(path, reduced):
    """The S capture at `path` reduced to 480x272 by each block's centre pixel, written to `reduced`. Copied from
    tools/scale_check.sh (task 066): (x S + S/2, y S + S/2), the backend's rule for guest memory."""
    w, h, rgb = imgdiff.load_rgb(path)
    half = scale // 2
    rows = []
    for y in range(272):
        start = ((y * scale + half) * w + half) * 3
        line = rgb[start:start + (w - half) * 3]
        row = bytearray(480 * 3)
        for k in range(3):
            row[k::3] = line[k::scale * 3][:480]
        rows.append(bytes(row))
    png.write_png(reduced, 480, 272, 3, b"".join(rows))


def energy(path):
    """The picture's high-frequency energy: the mean absolute difference, per channel, between each pixel and its
    right neighbour and between each pixel and its lower neighbour, over the whole picture (0 to 255)."""
    w, h, rgb = imgdiff.load_rgb(path)
    stride = w * 3
    total = sum(map(abs, map(sub, rgb[:-stride], rgb[stride:])))       # lower neighbours: (h - 1) rows
    for y in range(h):                                                  # right neighbours: w - 1 a row
        row = rgb[y * stride:(y + 1) * stride]
        total += sum(map(abs, map(sub, row[:-3], row[3:])))
    return total / ((h - 1) * stride + h * (stride - 3))


def compare(a, b, tol, max_frac, diff=None):
    opts = type("Opts", (), dict(a=a, b=b, tol=tol, max_frac=max_frac, mask=None, region=None, out=diff))
    return imgdiff.compare(opts)


def hud(scene, capture, frame):
    """tools/hud_check.py on the capture, written as DIR/hud/<scene>/h<frame>.bmp: (passed, its last line)."""
    where = os.path.join(out, "hud", scene)
    os.makedirs(where, exist_ok=True)
    w, h, rgb = imgdiff.load_rgb(capture)
    imgdiff._write_bmp(os.path.join(where, f"h{frame}.bmp"), w, h, rgb, 3, 24)
    r = subprocess.run([sys.executable, "tools/hud_check.py", where, "--expect", "1"], capture_output=True, text=True)
    last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
    return r.returncode == 0, last


table = scene_table()
size = (480 * scale, 272 * scale)
reduced_dir = os.path.join(out, "1", "reduced")
os.makedirs(reduced_dir, exist_ok=True)
note("")
note(f"each PURE_TEXTURE_DETAIL=1 capture at scale {scale}: its size, by its blocks' centre pixels against the scene's "
     f"reference at the scene's tol and limit (tools/frame_regress.sh), the full capture against the "
     f"PURE_TEXTURE_DETAIL=0 one at tol {DIFF_TOL} (at least {MIN_DIFF:.0%}), the high-frequency energy of the 0 and 1 "
     f"captures and their ratio (above {MIN_RATIO}), and the race HUD (tools/hud_check.py):")
note(f"{'scene':<10} {'size':>10} {'reduced':>8} {'limit':>6} {'tol':>4} {'vs 0':>8} {'energy 0':>9} {'energy 1':>9} "
     f"{'ratio':>7} {'HUD':>4}  result")
passed = 0
for scene in scenes:
    route, frame, ref, tol, limit = table[scene]
    a, b = os.path.join(out, "1", "shots", scene + ".png"), os.path.join(out, "0", "shots", scene + ".png")
    if not (os.path.isfile(a) and os.path.isfile(b)):
        note(f"{scene:<10} {'-':>10} {'-':>8} {limit:>6} {tol:>4} {'-':>8} {'-':>9} {'-':>9} {'-':>7} {'-':>4}  FAIL "
             f"(no capture with {'1' if not os.path.isfile(a) else '0'})")
        continue
    w, h, _ = imgdiff.load_rgb(a)
    why = []
    reduced_text = vs0_text = e0_text = e1_text = ratio_text = "-"
    if (w, h) != size:
        why.append(f"not {size[0]}x{size[1]}")
    else:
        reduced = os.path.join(reduced_dir, scene + ".png")
        centres(a, reduced)
        diff = os.path.join(out, scene + ".diff.png")
        r = compare(reduced, ref, tol, limit, diff)
        reduced_text = f"{r['fraction']:.4f}"
        if r["result"] == "PASS":
            os.remove(diff)
        else:
            why.append(f"reduced over the limit, diff {diff}")
        full = compare(a, b, DIFF_TOL, 1.0)
        vs0_text = f"{full['fraction']:.4f}"
        if full["fraction"] < MIN_DIFF:
            why.append(f"differs from the 0 capture in under {MIN_DIFF:.0%}")
        e0, e1 = energy(b), energy(a)
        ratio = e1 / e0 if e0 > 0 else float("inf")
        e0_text, e1_text, ratio_text = f"{e0:.4f}", f"{e1:.4f}", f"{ratio:.4f}"
        if not ratio > MIN_RATIO:
            why.append(f"energy ratio not above {MIN_RATIO}")
    hud_text = "-"
    if scene in hud_scenes:
        ok, last = hud(scene, a, frame)
        hud_text = "yes" if ok else "no"
        if not ok:
            why.append(f"no HUD ({last})")
    passed += not why
    note(f"{scene:<10} {f'{w}x{h}':>10} {reduced_text:>8} {limit:>6} {tol:>4} {vs0_text:>8} {e0_text:>9} {e1_text:>9} "
         f"{ratio_text:>7} {hud_text:>4}  " + ("PASS" if not why else "FAIL (" + "; ".join(why) + ")"))

note("")
route = table["race_hud"][0].replace(".txt", "")
log = os.path.join(out, "1", route + ".log")
found = None
if os.path.isfile(log):
    with open(log, errors="replace") as f:
        for line in f:
            m = re.search(r"^\[metal\] \d+ frames, .* (\d+) mipmapped draws \((\d+) enhanced, ", line)
            if m:
                found = (int(m[1]), int(m[2]))
if found is None:
    stats_ok = False
    note(f"race_hud run: no exit line with the enhanced count in {log}: FAIL")
else:
    stats_ok = found[1] >= MIN_ENHANCED
    note(f"race_hud run with 1 (exit line, over the run): {found[0]} mipmapped draws, {found[1]} enhanced (at least "
         f"{MIN_ENHANCED}): {'PASS' if stats_ok else 'FAIL'}")

_, frame, ref, tol, limit = table["race_hud"]
s1 = os.path.join(out, "s1", "shots", "race_hud.png")
if not os.path.isfile(s1):
    s1_ok = False
    note("race_hud at scale 1 with 1: no capture: FAIL")
else:
    w, h, _ = imgdiff.load_rgb(s1)
    if (w, h) != (480, 272):
        s1_ok = False
        note(f"race_hud at scale 1 with 1: {w}x{h}, not 480x272: FAIL")
    else:
        diff = os.path.join(out, "race_hud.s1.diff.png")
        r = compare(s1, ref, tol, limit, diff)
        s1_ok = r["result"] == "PASS"
        if s1_ok:
            os.remove(diff)
        note(f"race_hud at scale 1 with 1, against the reference: {r['fraction']:.4f} (limit {limit}, tol {tol}): "
             + ("PASS" if s1_ok else f"FAIL, diff {diff}"))

verdict = "PASS" if passed == len(scenes) and stats_ok and s1_ok else "FAIL"
note("")
note(f"texture check: {passed}/{len(scenes)} scenes pass, the enhanced draws {'PASS' if stats_ok else 'FAIL'}, "
     f"race_hud at scale 1 {'PASS' if s1_ok else 'FAIL'} ({int(seconds) // 60}m {int(seconds) % 60}s)")
note(f"texture_check: {verdict}")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
