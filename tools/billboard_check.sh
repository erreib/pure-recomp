#!/bin/bash
# The billboard check (task 063; docs/fidelity.md, difference 15): whether the track-side advert screen on Vineta K's
# first pillar shows the advert's picture or the flat colour with vertical bars it showed while a target sampled as
# a texture clamped its coordinate at the target's edge instead of taking the GE's wrap mode.
#   tools/billboard_check.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR] [--env KEY=VAL ...]
#   --backend  the GE backend (default metal; vulkan under --shell vulkan).
#   --shell    the shell whose picture is read (default headless: the backend's own 480x272 capture, unpaced, about
#              10 s); metal or vulkan read the window's (paced to real time, about 4 minutes). The window's picture
#              is read at the PSP's pixel centres, so the numbers are in PSP pixels at any size.
#   --out      default out/billboard_check/<backend>-<shell>: the route (route.txt), the run's log (run.log), the shot
#              (shots/b6490.bmp and .png), the rectangle enlarged 8 times (crop.png) and the numbers (summary.txt).
#              Removed first.
#   --env      extra environment for the run (tools/run_boot.py --env).
# The route is tools/frame_regress.sh's race route: config/pad_scripts/main_menu.txt + single_race.txt (Vineta K, Cross
# held from flip 6100), their own shot steps dropped, on an empty memory stick (<out>/game, tools/lib.sh's
# fresh_stick), with one shot at flip 6490 (race time 0:03.9: the orange advert screen ahead on the left, at
# x 167-198 y 117-133, a strut across its right half) and the run ending at flip 6500. The run is silent and uses the
# data directory out/data/billboard_check.
# The numbers, over the rectangle RECT (PSP pixels x0 y0 x1 y1, ends excluded: x 169-180 y 119-131, left of the
# strut), strictly inside the screen's surface: the mean absolute difference of the luminance (0.299 R + 0.587 G +
# 0.114 B, 0..255) between vertically adjacent pixels, and between horizontally adjacent ones. The bars of the clamped
# texture are vertical: they change across the screen and not down it, so the vertical number is the screen's shading
# alone. The advert's picture changes both ways. PASS (exit 0) when the run reached its last flip and the vertical
# number is at least THRESHOLD.
# Measured (task 063): before the fix vertical 2.0 and horizontal 20.3 on Metal headless, 1.7 and 24.6 in the Vulkan
# window; after the Metal fix 18.7 and 12.5 on Metal headless (the sunburst advert). PPSSPP's, for the order of
# magnitude: 25.6 and 26.7 on the same screen at race time 0:03.4 (out/billboard/ppsspp/f07600.png in the main
# checkout, x 181-187 y 121-127, left of its strut). The threshold sits well above the bars and below the picture.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

SHOT=6490
END=6500
RECT="169 119 181 132"
THRESHOLD=8

BACKEND=
SHELL_NAME=headless
OUT=
ENVS=()
usage() {
  echo "usage: tools/billboard_check.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR] [--env KEY=VAL ...]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; case $2 in *=*) ;; *) usage ;; esac; ENVS+=(--env "$2"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "billboard_check: unknown argument $1"; usage ;;
  esac
done
pick_backend billboard_check "headless metal vulkan"
OUT=${OUT:-out/billboard_check/$BACKEND-$SHELL_NAME}

need_game

rm -rf "$OUT"
mkdir -p "$OUT/shots"
OUT=$(cd "$OUT" && pwd)
fresh_stick "$OUT/game"
{
  echo "$SHOT:shot b$SHOT"
  cat config/pad_scripts/main_menu.txt config/pad_scripts/single_race.txt |
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)'
} > "$OUT/route.txt"

echo "billboard_check: backend $BACKEND, shell $SHELL_NAME, shot at flip $SHOT, out $OUT"
t0=$SECONDS
python3 tools/run_boot.py --script "$OUT/route.txt" --shots "$OUT/shots" --frames $END --shell "$SHELL_NAME" \
  --backend "$BACKEND" --data-dir out/data/billboard_check --env PURE_GAME_DIR="$OUT/game" \
  ${ENVS[@]+"${ENVS[@]}"} "$OUT/run.log" > "$OUT/run.stdout" 2>&1
rc=$?
reached=no
grep -q "^\[pure\] exit at frame $END" "$OUT/run.log" && reached=yes
echo "billboard_check: run_boot exit $rc, frame $END reached: $reached, $((SECONDS - t0)) s, log $OUT/run.log"
[ -f "$OUT/shots/b$SHOT.png" ] || { echo "billboard_check: FAIL (no shot $OUT/shots/b$SHOT.png)"; exit 1; }

python3 - "$OUT/shots/b$SHOT.png" "$OUT/crop.png" "$THRESHOLD" $RECT <<'EOF' | tee "$OUT/summary.txt"
import sys
sys.path.insert(0, "tools")
import png
path, crop, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])
x0, y0, x1, y1 = (int(v) for v in sys.argv[4:8])
width, height, channels, data = png.read_png(path)
def rgb(x, y):
    # PSP pixel (x, y): the shot's pixel at its centre.
    sx, sy = int((x + 0.5) * width / 480), int((y + 0.5) * height / 272)
    at = (sy * width + sx) * channels
    return data[at:at + 3]
def luma(x, y):
    r, g, b = rgb(x, y)
    return 0.299 * r + 0.587 * g + 0.114 * b
down = [abs(luma(x, y + 1) - luma(x, y)) for y in range(y0, y1 - 1) for x in range(x0, x1)]
across = [abs(luma(x + 1, y) - luma(x, y)) for y in range(y0, y1) for x in range(x0, x1 - 1)]
vertical, horizontal = sum(down) / len(down), sum(across) / len(across)
scale = 8
out = bytearray()
for y in range((y1 - y0) * scale):
    for x in range((x1 - x0) * scale):
        out += rgb(x0 + x // scale, y0 + y // scale)
png.write_png(crop, (x1 - x0) * scale, (y1 - y0) * scale, 3, bytes(out))
verdict = "PASS" if vertical >= threshold else "FAIL"
print(f"rectangle x {x0}-{x1 - 1} y {y0}-{y1 - 1} of {path} ({width}x{height}), crop {crop}")
print(f"vertical {vertical:.2f} horizontal {horizontal:.2f} (mean absolute luminance difference of adjacent pixels)")
print(f"billboard_check: {verdict}, vertical {vertical:.2f} against the threshold {threshold:g}")
EOF
[ "$reached" = yes ] && grep -q '^billboard_check: PASS' "$OUT/summary.txt"
