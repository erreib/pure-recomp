#!/bin/bash
# The aspect check (task 084, D-020's check for E2): the game's 3D view drawn at the window's shape under the Vulkan
# renderer's Fill aspect. The race_hud route of tools/frame_regress.sh in the Vulkan window (--shell vulkan --backend
# vulkan, unpaced until flip 5716 and paced from there, as the suite runs it) at PURE_WINDOW_SIZE=1260x540 (21:9,
# patch 0027-window-size-switch), twice, each lane with its own data directory out/data/aspect_check/<lane> (made
# with tools/purelib/port.py's SCRATCH_SETTINGS, the shipped enhancements off as every tool run has them) whose
# settings.ini says video.aspect=original or video.aspect=fill. Each run has PURE_TRACE_ASPECT=1 (the override's
# counts, src/profile/aspect.cpp), PURE_TRACE_3D=1 (each frame's transformed draws) and PURE_SCREENSHOT_EVERY=6016
# (the `[render] frame 6016 (D draws)` line: the draws over the run). Then (task 085) the main_menu route the same way
# in each lane (unpaced until flip 4400, paced from there, PURE_TRACE_ASPECT=1 only). A lane whose run made Vulkan
# pipelines (a cold pipeline cache stalls the paced race) is run again, up to three times in all, and the last compared.
#   tools/aspect_check.sh [--out DIR] [--wait SECONDS]
#   --out   default out/aspect_check: DIR/original and DIR/fill hold each lane's frame_regress output (shots/race_hud.png
#           the window capture at flip 6016, the run's log), DIR/main_menu.<lane> the main_menu runs' (shots/
#           main_menu.png at flip 4700), DIR/strip.<lane>.png and DIR/menu.strip.<lane>.png the central strips at
#           480x272, DIR/strip.diff.png, DIR/strip.hud.diff.png and DIR/menu.strip.diff.png their differing pixels,
#           DIR/summary.txt the figures.
#   --wait  how long to wait for another PureNative to end before each lane (default 600; 0 gives up at once).
# The captures are the window's pixels, 1260x540. Under Original the PSP's picture is shown at its own shape in the
# centre, 953x540 from x 153 (black either side); under Fill the target has the window's shape, the game draws its
# 3D view at it, and the renderer fits the 2D interface to square pixels about the centre (patch
# 0028-vulkan-orthographic-fit, task 085). PASS when:
#   (a) the central strip of the Fill capture (the width of the PSP's shape at the window's height, 953 pixels about
#       the centre) and the same strip of the Original capture, each reduced to 480x272 by the mean of the pixels each
#       target pixel covers, differ in at most MAX_STRIP of their pixels at tol 32, between the HUD's top bars and its
#       bottom ones (rows BAND of 272): the same view, resampled. The full strip's figure and the figure a stretched
#       picture would score (the Original strip spread to the window's width, its centre cut: what Fill shows without
#       the override) are printed beside it;
#   (b) the Fill capture's outer strips (the 153 pixels left of the central strip and the 153 right of it, over the
#       same rows) hold the scene: per-channel variance of at least MIN_VARIANCE in each, and each differs from the
#       central strip's adjacent 153 pixels in at least MIN_APART of its pixels at tol 32 (not black, not an edge
#       stretched outwards);
#   (c) printed, not bound: each lane's `[render] frame 6016 (D draws)` (draws over the run) and the transformed
#       draws of the frame captured (its `[3d]` line, the one before);
#   (d) the Fill lane's last `[aspect]` counts before the capture show race camera calls, widened, and the Original
#       lane's race camera calls with none widened (the override ran, leaving the PSP's aspect alone); both logs carry
#       the `[aspect] FUN_08a31148 overridden` line and no `not found` line. PURE_TRACE_ASPECT puts the override in at
#       the first flip in both lanes (without it, only at the first flip of another shape), so both run the same
#       dispatches: a lane without it raced a moment apart (an AI ship moved, the central strips 0.077);
#   (e) the HUD fitted (task 085): the central strips of (a) differ in at most MAX_HUD of their pixels at tol 32 over
#       the HUD's bands (rows HUD_BANDS of 272, the rows BAND leaves out), the resampling floor; the whole strip's
#       figure and a stretched picture's over the bands are printed beside it;
#   (f) the main menu, a 2D screen (task 085): the central strips of the two main_menu captures, reduced as in (a),
#       differ in at most MAX_MENU of their pixels at tol MENU_TOL (the suite's for the scene), and each outer strip
#       of the Fill capture (153 and 154 pixels) has at least MIN_LIT of its pixels not black (a channel above 32):
#       the backdrop stays spread. Its mean colour is printed.
# Prints the figures, then `aspect_check: PASS` or `FAIL` last. Exit 0 PASS, 1 FAIL, 2 cannot run. About 4 minutes
# (two paced race routes and two menu routes in a window), up to 6 the first time (the pipeline caches warmed).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

DIR=out/aspect_check
WAIT=600
SIZE=1260x540
usage() {
  echo "usage: tools/aspect_check.sh [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "aspect_check: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "aspect_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
rm -f "$DIR"/strip.*.png "$DIR"/menu.strip.*.png "$DIR/summary.txt"
START=$SECONDS
echo "aspect check $(date '+%Y-%m-%d %H:%M'): race_hud in the Vulkan window at $SIZE, video.aspect original and fill," \
  "into $DIR"

# lane NAME SCENE: the SCENE route (race_hud or main_menu) with video.aspect=NAME in the lane's data directory, into
# DIR/NAME (race_hud) or DIR/main_menu.NAME; again while the run made pipelines, up to three runs.
lane() {
  local name=$1 scene=$2 data rounds=0 rc dest=$DIR/$1 out=$DIR/frame_regress.$1.stdout extra=()
  if [ "$scene" = race_hud ]; then
    extra=(--env PURE_TRACE_3D=1 --env PURE_SCREENSHOT_EVERY=6016)
  else
    dest=$DIR/$scene.$name out=$DIR/frame_regress.$scene.$name.stdout
  fi
  data=$(python3 - "$name" <<'EOF'
import sys
sys.path.insert(0, "tools")
from purelib import port
env = {}
path = port.scratch_data_dir(env, f"out/data/aspect_check/{sys.argv[1]}")
settings = f"{path}/settings.ini"
with open(settings) as f:
    lines = [ln for ln in f.read().splitlines() if not ln.startswith("video.aspect=")]
with open(settings, "w") as f:
    f.write("\n".join(lines + [f"video.aspect={sys.argv[1]}"]) + "\n")
print(path)
EOF
)
  while :; do
    python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("aspect_check: " + m, flush=True),
                              limit=float(sys.argv[1])) else 2)' "$WAIT" || exit 2
    tools/frame_regress.sh --out "$dest" --shell vulkan --backend vulkan --only "$scene" \
      --env "PURE_DATA_DIR=$data" --env "PURE_WINDOW_SIZE=$SIZE" --env PURE_TRACE_ASPECT=1 \
      ${extra[@]+"${extra[@]}"} > "$out" 2>&1
    rc=$?
    rounds=$((rounds + 1))
    if grep -q '^frame_regress: another PureNative is running' "$out"; then
      [ $rounds -lt 3 ] && continue
      cat "$out"
      echo "aspect_check: another game kept starting; try again later"
      exit 2
    fi
    # The suite's verdict (the capture against the PSP reference) does not matter here; a run that could not start
    # does.
    if [ $rc -eq 2 ]; then
      cat "$out"
      echo "aspect_check: tools/frame_regress.sh could not run"
      exit 2
    fi
    [ $rounds -lt 3 ] && grep -q '^\[render\] [0-9]* new pipeline' "$dest"/*.log 2>/dev/null || break
    echo "  lane $name ($scene): the run made pipelines, which moves a paced run: again, with the pipeline cache warmer"
  done
  echo "  lane $name ($scene): $(grep -h '^run [a-z_+]*: run_boot exit' "$out" |
    sed 's/^run [a-z_+]*: //; s/, log .*//')"
}

lane original race_hud
lane fill race_hud
lane original main_menu
lane fill main_menu

python3 - "$DIR" "$((SECONDS - START))" <<'EOF'
import os, re, sys
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, seconds = sys.argv[1], int(sys.argv[2])
TOL = 32
MAX_STRIP = 0.10          # (a) the central strips between the HUD's bars, at TOL (measured: see the task's Result)
BAND = (40, 212)          # rows of 272 between the HUD's top bars and its bottom ones
MIN_VARIANCE = 200.0      # (b) each outer strip's largest per-channel variance over the band (black is 0)
MIN_APART = 0.30          # (b) each outer strip against the central strip's adjacent pixels, at TOL
SIDE = 153                # (b) the outer strips' width
MAX_HUD = 0.05            # (e) the central strips over the HUD's bands, at TOL (measured: see task 085's Result)
HUD_BANDS = ((0, 40), (212, 272))   # rows of 272: the HUD's top bars and its bottom ones, the rows BAND leaves out
MENU_TOL = 24             # (f) the suite's tol for main_menu
MAX_MENU = 0.05           # (f) the menu's central strips, at MENU_TOL
MIN_LIT = 0.90            # (f) each outer strip of the Fill menu: the share of its pixels not black (a channel > 32)
FRAME = 6016
lines = []


def note(text=""):
    print(text)
    lines.append(text)


def crop(img, x0, x1, y0=0, y1=None):
    w, h, rgb = img
    y1 = h if y1 is None else y1
    return x1 - x0, y1 - y0, b"".join(rgb[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, y1))


def reduce(img, dw, dh):
    """img reduced to dw x dh, each target pixel the mean of the source pixels it covers (whole pixels)."""
    w, h, rgb = img
    cols = [(x * w // dw, max(x * w // dw + 1, (x + 1) * w // dw)) for x in range(dw)]
    out = bytearray(dw * dh * 3)
    for y in range(dh):
        y0, y1 = y * h // dh, max(y * h // dh + 1, (y + 1) * h // dh)
        sums = [[0] * (w + 1) for _ in range(3)]   # per channel, the prefix sums of the rows' column totals
        for k in range(3):
            acc, s = 0, sums[k]
            totals = [0] * w
            for yy in range(y0, y1):
                row = rgb[yy * w * 3 + k:(yy + 1) * w * 3:3]
                totals = [a + b for a, b in zip(totals, row)]
            for x in range(w):
                acc += totals[x]
                s[x + 1] = acc
        for x, (x0, x1) in enumerate(cols):
            n = (x1 - x0) * (y1 - y0)
            for k in range(3):
                out[(y * dw + x) * 3 + k] = ((sums[k][x1] - sums[k][x0]) + n // 2) // n
    return dw, dh, bytes(out)


def stretch(img, dw):
    """img spread to dw columns, nearest neighbour (the PSP's picture spread over the window's width)."""
    w, h, rgb = img
    return dw, h, imgdiff.resize_nn(w, h, rgb, dw, h)


def write(path, img):
    png.write_png(path, img[0], img[1], 3, img[2])


def fraction(a, b, region=None, diff=None, mask=None, tol=TOL):
    pa, pb = a if isinstance(a, str) else None, b if isinstance(b, str) else None
    if pa is None:
        pa = os.path.join(out, ".a.png"); write(pa, a)
    if pb is None:
        pb = os.path.join(out, ".b.png"); write(pb, b)
    opts = type("Opts", (), dict(a=pa, b=pb, tol=tol, max_frac=1.0, mask=mask, region=region, out=diff))
    r = imgdiff.compare(opts)["fraction"]
    for p in (os.path.join(out, ".a.png"), os.path.join(out, ".b.png")):
        if os.path.exists(p):
            os.remove(p)
    return r


def variance(img):
    w, h, rgb = img
    n = w * h
    best = 0.0
    for k in range(3):
        ch = rgb[k::3]
        s, sq = sum(ch), sum(v * v for v in ch)
        best = max(best, (n * sq - s * s) / (n * n))
    return best


def lit(img):
    """The share of img's pixels with a channel above 32 (not black), and its mean colour."""
    w, h, rgb = img
    n = w * h
    on = sum(1 for i in range(n) if max(rgb[i * 3:i * 3 + 3]) > 32)
    return on / n, tuple(round(sum(rgb[k::3]) / n) for k in range(3))


def log_figures(lane):
    """(draws over the run at FRAME, transformed draws of the frame captured, the last [aspect] counts before the
    capture, overridden, not found) from the lane's log."""
    path = os.path.join(out, lane, "main_menu+single_race.log")
    draws = transformed = counts = None
    overridden = not_found = False
    last_3d = None
    if not os.path.isfile(path):
        return draws, transformed, counts, overridden, not_found
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith("[aspect] FUN_08a31148 overridden"):
                overridden = True
            elif line.startswith("[aspect] FUN_08a31148 not found"):
                not_found = True
            elif line.startswith("[aspect] calls:") and draws is None:
                m = re.match(r"\[aspect\] calls: race camera (\d+) \((\d+) widened\), other (\d+) \((\d+) widened\)", line)
                if m:
                    counts = tuple(int(v) for v in m.groups())
            elif line.startswith("[3d] frame "):
                m = re.match(r"\[3d\] frame \d+ through=(\d+) transformed=(\d+)", line)
                if m:
                    last_3d = int(m[2])
            elif line.startswith(f"[render] frame {FRAME} ("):
                m = re.match(rf"\[render\] frame {FRAME} \((\d+) draws\)", line)
                if m and draws is None:
                    draws, transformed = int(m[1]), last_3d
    return draws, transformed, counts, overridden, not_found


why = []
hud = None
caps = {lane: os.path.join(out, lane, "shots", "race_hud.png") for lane in ("original", "fill")}
missing = [lane for lane, p in caps.items() if not os.path.isfile(p)]
if missing:
    why.append(f"no capture in {', '.join(missing)}")
else:
    orig, fill = (imgdiff.load_rgb(caps[lane]) for lane in ("original", "fill"))
    w, h = fill[0], fill[1]
    if (orig[0], orig[1]) != (w, h):
        why.append(f"the captures differ in size: {orig[0]}x{orig[1]} and {w}x{h}")
    else:
        strip = round(h * 480 / 272)
        x0 = (w - strip) // 2
        y0, y1 = BAND[0] * h // 272, BAND[1] * h // 272
        note("")
        note(f"captures {w}x{h}; the central strip x {x0}..{x0 + strip} ({strip} pixels, the PSP's shape at the "
             f"window's height); the HUD-free band rows {BAND[0]}..{BAND[1]} of 272 ({y0}..{y1} here)")
        # (a)
        so, sf = reduce(crop(orig, x0, x0 + strip), 480, 272), reduce(crop(fill, x0, x0 + strip), 480, 272)
        po, pf = os.path.join(out, "strip.original.png"), os.path.join(out, "strip.fill.png")
        write(po, so)
        write(pf, sf)
        band = (0, BAND[0], 480, BAND[1] - BAND[0])
        a_band = fraction(pf, po, band, os.path.join(out, "strip.diff.png"))
        a_full = fraction(pf, po)
        wide = stretch(crop(orig, x0, x0 + strip), w)
        control = fraction(reduce(crop(wide, x0, x0 + strip), 480, 272), po, band)
        ok = a_band <= MAX_STRIP
        note(f"(a) the central strips at 480x272, Fill against Original at tol {TOL}: {a_band:.4f} between the HUD's "
             f"bars (limit {MAX_STRIP}), {a_full:.4f} over the whole strip; a stretched picture would score "
             f"{control:.4f}: {'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append(f"(a) the central strips differ in {a_band:.4f} (diff {os.path.join(out, 'strip.diff.png')})")
        # (e), printed after (d): the same strips over the HUD's bands, a mask white in them.
        mask = os.path.join(out, ".hud_mask.png")
        rows = bytearray(480 * 272 * 3)
        for top, bottom in HUD_BANDS:
            rows[top * 480 * 3:bottom * 480 * 3] = b"\xff" * ((bottom - top) * 480 * 3)
        write(mask, (480, 272, bytes(rows)))
        hud = (fraction(pf, po, None, os.path.join(out, "strip.hud.diff.png"), mask),
               fraction(reduce(crop(wide, x0, x0 + strip), 480, 272), po, None, None, mask), a_full)
        os.remove(mask)
        # (b)
        right = x0 + strip
        sides = {"left": (crop(fill, x0 - SIDE, x0, y0, y1), crop(fill, x0, x0 + SIDE, y0, y1)),
                 "right": (crop(fill, right, right + SIDE, y0, y1), crop(fill, right - SIDE, right, y0, y1))}
        for side, (outer, inner) in sides.items():
            var, apart = variance(outer), fraction(outer, inner)
            ok = var >= MIN_VARIANCE and apart >= MIN_APART
            note(f"(b) the {side} strip ({SIDE} pixels, the band): variance {var:.1f} (at least {MIN_VARIANCE:g}), "
                 f"against the adjacent {SIDE} of the central strip {apart:.4f} (at least {MIN_APART}): "
                 f"{'PASS' if ok else 'FAIL'}")
            if not ok:
                why.append(f"(b) the {side} strip does not hold the scene")

figures = {lane: log_figures(lane) for lane in ("original", "fill")}
note(f"(c) draws at frame {FRAME}: " + "; ".join(
    f"{lane} {d if d is not None else '-'} over the run, {t if t is not None else '-'} transformed in the frame"
    for lane, (d, t, _, _, _) in figures.items()))
for lane, (_, _, counts, overridden, not_found) in figures.items():
    if counts is None:
        note(f"(d) {lane}: no [aspect] counts before the capture{', a not found line' if not_found else ''}: FAIL")
        why.append(f"(d) {lane}: no [aspect] counts")
        continue
    race, race_widened, other, other_widened = counts
    ok = overridden and not not_found and race > 0 and (
        race_widened > 0 if lane == "fill" else race_widened == 0 and other_widened == 0)
    note(f"(d) {lane}: race camera {race} calls ({race_widened} widened), other {other} ({other_widened} widened)"
         f"{'' if overridden else ', no overridden line'}{', a not found line' if not_found else ''}: "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        why.append(f"(d) {lane}: the override's counts")

if hud is not None:
    bands = ", ".join(f"{top}..{bottom}" for top, bottom in HUD_BANDS)
    ok = hud[0] <= MAX_HUD
    note(f"(e) the HUD: the central strips over rows {bands} of 272 at tol {TOL}: {hud[0]:.4f} (limit {MAX_HUD}); "
         f"the whole strip {hud[2]:.4f}; a stretched picture would score {hud[1]:.4f} there: "
         f"{'PASS' if ok else 'FAIL'}")
    if not ok:
        why.append(f"(e) the HUD's bands differ in {hud[0]:.4f} (diff {os.path.join(out, 'strip.hud.diff.png')})")

# (f) The main menu, a 2D screen: the central strips match; the Fill capture's outer strips are not black.
menu = {lane: os.path.join(out, f"main_menu.{lane}", "shots", "main_menu.png") for lane in ("original", "fill")}
missing = [lane for lane, p in menu.items() if not os.path.isfile(p)]
if missing:
    note(f"(f) the main menu: no capture in {', '.join(missing)}: FAIL")
    why.append(f"(f) no main_menu capture in {', '.join(missing)}")
else:
    orig, fill = (imgdiff.load_rgb(menu[lane]) for lane in ("original", "fill"))
    w, h = fill[0], fill[1]
    if (orig[0], orig[1]) != (w, h):
        note(f"(f) the main menu captures differ in size: {orig[0]}x{orig[1]} and {w}x{h}: FAIL")
        why.append("(f) the main menu captures differ in size")
    else:
        strip = round(h * 480 / 272)
        x0 = (w - strip) // 2
        po, pf = os.path.join(out, "menu.strip.original.png"), os.path.join(out, "menu.strip.fill.png")
        write(po, reduce(crop(orig, x0, x0 + strip), 480, 272))
        write(pf, reduce(crop(fill, x0, x0 + strip), 480, 272))
        f_strip = fraction(pf, po, None, os.path.join(out, "menu.strip.diff.png"), None, MENU_TOL)
        ok = f_strip <= MAX_MENU
        note(f"(f) the main menu (frame 4700): the central strips at 480x272 at tol {MENU_TOL}: {f_strip:.4f} "
             f"(limit {MAX_MENU}): {'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append(f"(f) the menu's central strips differ in {f_strip:.4f} "
                       f"(diff {os.path.join(out, 'menu.strip.diff.png')})")
        for side, (s0, s1) in {"left": (0, x0), "right": (x0 + strip, w)}.items():
            share, mean = lit(crop(fill, s0, s1))
            ok = share >= MIN_LIT
            note(f"(f) the main menu's {side} strip ({s1 - s0} pixels): {share:.4f} of its pixels not black (at least "
                 f"{MIN_LIT}), mean colour {mean}: {'PASS' if ok else 'FAIL'}")
            if not ok:
                why.append(f"(f) the menu's {side} strip is black")

verdict = "FAIL" if why else "PASS"
note("")
note(f"aspect check: {verdict} ({seconds // 60}m {seconds % 60}s)" + ("" if not why else ": " + "; ".join(why)))
note(f"aspect_check: {verdict}")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
