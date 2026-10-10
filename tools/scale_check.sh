#!/bin/bash
# The Metal backend at an internal scale against scale 1 (task 066; D-015's bar for E3): the frame regression suite's
# scenes captured headless at PURE_INTERNAL_SCALE=1 and at PURE_INTERNAL_SCALE=S, and each pair compared.
#   tools/scale_check.sh [S] [--out DIR] [--wait SECONDS]
#   S          the internal scale to check, 2 to 6 (default 4).
#   --out      default out/scale: DIR/1 and DIR/S hold each suite's captures and logs (tools/frame_regress.sh --out),
#              DIR/S/reduced the S captures reduced to 480x272, DIR/<scene>.diff.png the differing pixels of a failing
#              scene, DIR/summary.txt the table.
#   --wait     how long to wait for other games to end when the suite's one-game guard refuses to start (default 600;
#              0 gives up at once), as tools/refactor_check.sh waits.
# For each scene: the S capture must be 480S x 272S (the backend's display target at the scale, capture_frame); it is
# reduced to 480x272 by the centre pixel of each S x S block, (x S + S/2, y S + S/2), the rule by which the backend
# feeds guest memory (D-015), and compared with the 1x capture by tools/imgdiff.py at tol 24: PASS when at most 5% of
# the pixels differ. The table also gives, for the record, the fraction with tools/imgdiff.py's own nearest neighbour
# on the full capture ("top-left"), which takes the block's top-left pixel (S x, S y): that pixel's centre lies
# (S - 1) / 2S of a pixel up and left of the 1x pixel's (3/8 at S = 4), which moves every filtered edge, so it is not
# the pass condition (docs/metal-backend.md, "Internal scale").
# For the race scenes on Vineta K's grid (race_hud, tt_hud, fp_hud) the bloom's region, BLOOM below, is measured too:
# its mean luminance (0.299 R + 0.587 G + 0.114 B) in the S capture at its own size against the 1x capture's, PASS
# within 10% of the 1x mean. The region is where the bloom adds the most on that grid: the light strips under the
# stand's roof at the top right and their glows (race frame 6016 of out/gerec/race_1x.gerec replayed into Metal up to
# the bloom's composite draw and past it: the composite adds 41 to 79 to the mean luminance of 16x16 cells there and
# at most 19 elsewhere).
# Whether the scenes pass against PPSSPP does not matter here (tools/frame_regress.sh says that); only that the scaled
# picture is the 1x one drawn finer. Exit 0 PASS, 1 FAIL, 2 cannot run (a suite refused for longer than --wait, no
# capture at all).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

SCALE=4
DIR=out/scale
WAIT=600
# x,y,w,h in the PSP's 480x272 screen.
BLOOM=296,0,184,56
BLOOM_SCENES="race_hud tt_hud fp_hud"
usage() {
  echo "usage: tools/scale_check.sh [S] [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    [2-6]) SCALE=$1; shift ;;
    *) echo "scale_check: unknown argument $1 (S is 2 to 6)"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "scale_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
START=$SECONDS

# capture S: the suite's scenes, headless on Metal at internal scale S, into DIR/S, retried while the one-game guard
# refuses, for up to --wait seconds.
capture() {
  local scale=$1 where="$DIR/$1" waited=0 rc
  rm -rf "$where"
  mkdir -p "$where"
  while :; do
    tools/frame_regress.sh --out "$where" --shell headless --backend metal --env "PURE_INTERNAL_SCALE=$scale" \
      > "$DIR/frame_regress.$scale.stdout" 2>&1
    rc=$?
    grep -q '^frame_regress: another PureNative is running' "$DIR/frame_regress.$scale.stdout" || break
    if [ $waited -ge "$WAIT" ]; then
      cat "$DIR/frame_regress.$scale.stdout"
      echo "scale_check: another game kept running for $WAIT s; try again later"
      exit 2
    fi
    [ $waited -eq 0 ] && sed -n '2,$p' "$DIR/frame_regress.$scale.stdout" | sed 's/^/  waiting for: /'
    sleep 20
    waited=$((waited + 20))
  done
  [ $waited -gt 0 ] && echo "  (waited $waited s for another game to end)"
  if [ $rc -eq 2 ]; then
    cat "$DIR/frame_regress.$scale.stdout"
    echo "scale_check: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep -E '^frame regression:' "$DIR/frame_regress.$scale.stdout" | sed "s/^/  scale $scale: /"
  grep -h '^\[metal\] drawing with' "$where"/*.log 2>/dev/null | sed 's/; shaders compiled.*//' | sort -u |
    sed "s/^/  scale $scale: /"
}

rm -f "$DIR"/*.diff.png "$DIR/summary.txt"
echo "scale check $(date '+%Y-%m-%d %H:%M'): internal scale $SCALE against 1, headless on Metal, into $DIR"
capture 1
capture "$SCALE"

python3 - "$DIR" "$SCALE" "$BLOOM" "$BLOOM_SCENES" "$((SECONDS - START))" <<'EOF'
import os, sys
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, scale, bloom, bloom_scenes, seconds = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4].split(), sys.argv[5]
region = tuple(int(v) for v in bloom.split(","))
TOL, MAX_FRAC, MAX_BLOOM = 24, 0.05, 0.10
lines = []


def note(text=""):
    print(text)
    lines.append(text)


def centres(path, reduced):
    """The S capture at `path` reduced to 480x272 by each block's centre pixel, written to `reduced`."""
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


def compare(a, b, diff=None):
    opts = type("Opts", (), dict(a=a, b=b, tol=TOL, max_frac=MAX_FRAC, mask=None, region=None, out=diff))
    return imgdiff.compare(opts)


def luminance(path):
    w, h, rgb = imgdiff.load_rgb(path)
    x0, y0, x1, y1 = imgdiff.scale_region(region, w, h)
    total = 0.0
    for y in range(y0, y1):
        row = rgb[(y * w + x0) * 3:(y * w + x1) * 3]
        total += 0.299 * sum(row[0::3]) + 0.587 * sum(row[1::3]) + 0.114 * sum(row[2::3])
    return total / ((x1 - x0) * (y1 - y0))


shots1 = os.path.join(out, "1", "shots")
shots = os.path.join(out, str(scale), "shots")
scenes = sorted(f[:-4] for f in os.listdir(shots1) if f.endswith(".png")) if os.path.isdir(shots1) else []
if not scenes:
    print(f"scale_check: no captures at scale 1 in {shots1}")
    sys.exit(2)
reduced_dir = os.path.join(out, str(scale), "reduced")
os.makedirs(reduced_dir, exist_ok=True)
note("")
note(f"each {480 * scale}x{272 * scale} capture by its blocks' centre pixels against the 1x capture, tol {TOL} "
     f"(top-left: tools/imgdiff.py's nearest neighbour, for the record):")
note(f"{'scene':<18} {'size':>10} {'differing':>13} {'fraction':>8} {'limit':>6} {'top-left':>8}  result")
passed = 0
for scene in scenes:
    a, b = os.path.join(shots, scene + ".png"), os.path.join(shots1, scene + ".png")
    if not os.path.isfile(a):
        note(f"{scene:<18} {'-':>10} {'-':>13} {'-':>8} {MAX_FRAC:>6} {'-':>8}  FAIL (no capture at scale {scale})")
        continue
    w, h, _ = imgdiff.load_rgb(a)
    size = f"{w}x{h}"
    if (w, h) != (480 * scale, 272 * scale):
        note(f"{scene:<18} {size:>10} {'-':>13} {'-':>8} {MAX_FRAC:>6} {'-':>8}  "
             f"FAIL (not {480 * scale}x{272 * scale})")
        continue
    reduced = os.path.join(reduced_dir, scene + ".png")
    centres(a, reduced)
    diff = os.path.join(out, scene + ".diff.png")
    r = compare(reduced, b, diff)
    top_left = compare(a, b)["fraction"]
    ok = r["result"] == "PASS"
    if ok:
        os.remove(diff)
        passed += 1
    note(f"{scene:<18} {size:>10} {r['differing']:>6}/{r['total']:<6} {r['fraction']:>8.4f} {MAX_FRAC:>6} "
         f"{top_left:>8.4f}  " + ("PASS" if ok else f"FAIL (diff {diff})"))

note("")
note(f"bloom region {bloom} (x,y,w,h of the 480x272 screen), mean luminance at each capture's own size:")
note(f"{'scene':<18} {'1x':>8} {str(scale) + 'x':>8} {'change':>8} {'limit':>6}  result")
bloom_passed = bloom_total = 0
for scene in bloom_scenes:
    a, b = os.path.join(shots, scene + ".png"), os.path.join(shots1, scene + ".png")
    bloom_total += 1
    if not (os.path.isfile(a) and os.path.isfile(b)):
        note(f"{scene:<18} {'-':>8} {'-':>8} {'-':>8} {'10%':>6}  FAIL (no capture)")
        continue
    one, scaled = luminance(b), luminance(a)
    change = (scaled - one) / one if one > 0 else float("inf")
    ok = abs(change) <= MAX_BLOOM
    bloom_passed += ok
    note(f"{scene:<18} {one:>8.2f} {scaled:>8.2f} {change * 100:>+7.2f}% {'10%':>6}  {'PASS' if ok else 'FAIL'}")

verdict = "PASS" if passed == len(scenes) and bloom_passed == bloom_total else "FAIL"
note("")
note(f"scale check: {verdict}, scale {scale}: {passed}/{len(scenes)} scenes within {MAX_FRAC:.0%} at tol {TOL}, "
     f"{bloom_passed}/{bloom_total} bloom regions within {MAX_BLOOM:.0%} ({int(seconds) // 60}m {int(seconds) % 60}s)")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
