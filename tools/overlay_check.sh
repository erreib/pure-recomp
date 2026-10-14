#!/bin/bash
# The performance overlay check (task 090): the framework's overlay (perf::draw_overlay, the Esc menu's Performance
# row) drawn by the Metal shell over its window. The race_hud route of tools/frame_regress.sh in the Metal window
# (--shell metal --backend metal --only race_hud: unpaced until flip 5716 and paced from there, as the suite runs it,
# the window capture at flip 6016), twice, each lane with its own data directory out/data/overlay_check/<lane> (made
# with tools/purelib/port.py's SCRATCH_SETTINGS, the shipped enhancements off as every tool run has them) whose
# settings.ini says video.performance=off or video.performance=overlay. PURE_PERF is unset for the runs, so the
# settings decide.
#   tools/overlay_check.sh [--out DIR] [--wait SECONDS]
#   --out   default out/overlay_check: DIR/off and DIR/overlay hold each lane's frame_regress output (shots/race_hud.png
#           the window capture, the run's log), DIR/overlay.png the overlay lane's rectangle as captured,
#           DIR/rect.diff.png and DIR/rest.diff.png the differing pixels inside and outside it, DIR/summary.txt the
#           figures.
#   --wait  how long to wait for another PureNative to end before each lane (default 600; 0 gives up at once).
# The rectangle is where the shell draws the overlay: scale = perf::overlay_scale(capture height) (the height over
# 360, at least 1), inset 4 x scale from the top-left corner, 196 x scale by 72 x scale (3, 12 and 588x216 in the
# default 1920x1088 drawable of a 2x display). PASS when:
#   (a) the rectangle of the overlay lane's capture differs from the same rectangle of the other lane's in at least
#       MIN_CHANGED of its pixels at tol TOL;
#   (b) it holds pixels that are not black (a channel above LIT): the overlay's text and graph;
#   (c) the rest of the capture (the rectangle masked) matches the other lane's within the race_hud scene's limit
#       (REST_LIMIT at tol REST_TOL, tools/frame_regress.sh's table): the overlay changes nothing else;
#   (d) the HUD is found in both (tools/hud_check.py's two labels: CURRENT top left, LAP bottom left): both labels in
#       the lane without the overlay, and in the overlay lane the labels outside the rectangle. The CURRENT label lies
#       under the rectangle in the overlay lane (as the Vulkan renderer's overlay covers it), so there it is printed,
#       not required;
#   (e) the overlay's first line reads "FPS ...": the numbers are there, not "MEASURING". The four lines are read
#       back from the capture with the overlay's own 5x7 font (vendor/portablekit/host/perf/perf_overlay.cpp's kFont,
#       read from the source) and printed, with the share of the rectangle's scale x scale blocks that are one colour
#       (the overlay's pixels drawn whole).
# Prints the figures, then `overlay_check: PASS` or `FAIL` last. Exit 0 PASS, 1 FAIL, 2 cannot run. About 25 s
# (two race routes in the window, 10 s each on this Mac).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
unset PURE_PERF

DIR=
WAIT=600
usage() {
  echo "usage: tools/overlay_check.sh [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "overlay_check: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "overlay_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
DIR=${DIR:-out/overlay_check}
DATA=out/data/overlay_check
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
rm -f "$DIR"/*.png "$DIR"/*.stdout "$DIR/summary.txt"
START=$SECONDS
echo "overlay check $(date '+%Y-%m-%d %H:%M'): race_hud in the Metal window, video.performance off and overlay," \
  "into $DIR"

# lane NAME: the race_hud route with video.performance=NAME in the lane's data directory, into DIR/NAME.
lane() {
  local name=$1 data rc out=$DIR/frame_regress.$1.stdout
  data=$(python3 - "$name" "$DATA" <<'EOF'
import sys
sys.path.insert(0, "tools")
from purelib import port
path = port.scratch_data_dir({}, f"{sys.argv[2]}/{sys.argv[1]}")
settings = f"{path}/settings.ini"
with open(settings) as f:
    lines = [ln for ln in f.read().splitlines() if not ln.startswith("video.performance=")]
with open(settings, "w") as f:
    f.write("\n".join(lines + [f"video.performance={sys.argv[1]}"]) + "\n")
print(path)
EOF
)
  python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("overlay_check: " + m, flush=True),
                              limit=float(sys.argv[1])) else 2)' "$WAIT" || exit 2
  tools/frame_regress.sh --out "$DIR/$name" --shell metal --backend metal --only race_hud \
    --env "PURE_DATA_DIR=$data" > "$out" 2>&1
  rc=$?
  if grep -q '^frame_regress: another PureNative is running' "$out" || [ $rc -eq 2 ]; then
    cat "$out"
    echo "overlay_check: tools/frame_regress.sh could not run"
    exit 2
  fi
  # The suite's verdict (the capture against the PSP reference) does not matter here; the capture does.
  echo "  lane $name: $(grep -h '^run [a-z_+]*: run_boot exit' "$out" | sed 's/^run [a-z_+]*: //; s/, log .*//')"
}

lane off
lane overlay

python3 - "$DIR" "$((SECONDS - START))" <<'EOF'
import os, re, sys
sys.path.insert(0, "tools")
import hud_check  # noqa: E402  (tools/hud_check.py: the HUD's labels)
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, seconds = sys.argv[1], int(sys.argv[2])
TOL = 24                  # (a) the rectangle against the other lane's
MIN_CHANGED = 0.20        # (a) the share of the rectangle that must differ
LIT = 32                  # (b) a pixel is not black when a channel is above this
REST_TOL = 32             # (c) the race_hud scene's tol and limit (tools/frame_regress.sh)
REST_LIMIT = 0.10
OVERLAY_W, OVERLAY_H = 196, 72          # perf::kOverlayWidth, kOverlayHeight
TEXT = (235, 235, 235)                  # perf_overlay.cpp's kText
FONT_SOURCE = "vendor/portablekit/host/perf/perf_overlay.cpp"
lines, why = [], []


def note(text=""):
    print(text)
    lines.append(text)


def mask(w, h, box, inside):
    """A w x h mask, white inside box (x0, y0, x1, y1) when inside, else white outside it."""
    x0, y0, x1, y1 = box
    on, off = (b"\xff\xff\xff", b"\x00\x00\x00") if inside else (b"\x00\x00\x00", b"\xff\xff\xff")
    row_in = off * x0 + on * (x1 - x0) + off * (w - x1)
    row_out = off * w
    return w, h, row_out * y0 + row_in * (y1 - y0) + row_out * (h - y1)


def fraction(a, b, mask_img, tol, diff):
    path = os.path.join(out, ".mask.png")
    png.write_png(path, mask_img[0], mask_img[1], 3, mask_img[2])
    opts = type("Opts", (), dict(a=a, b=b, tol=tol, max_frac=1.0, mask=path, region=None, out=diff))
    try:
        return imgdiff.compare(opts)["fraction"]
    finally:
        os.remove(path)


def crop(img, box):
    w, h, rgb = img
    x0, y0, x1, y1 = box
    return x1 - x0, y1 - y0, b"".join(rgb[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, y1))


def font():
    """The overlay's glyphs, {rows (7 five-bit ints): character}, read from the framework's source."""
    try:
        with open(FONT_SOURCE) as f:
            source = f.read()
    except OSError:
        return {}
    glyphs = {}
    for char, rows in re.findall(r"\{'(.)',\s*\{((?:\s*0b[01]{5},?){7})\}\}", source):
        glyphs[tuple(int(r, 2) for r in re.findall(r"0b([01]{5})", rows))] = char
    return glyphs


def read_lines(small, glyphs):
    """The overlay's four text lines read back from its 196x72 image (perf_overlay.cpp: margin 2, glyphs 6 apart,
    lines 9 apart)."""
    w, h, rgb = small
    text = []
    for line in range(4):
        y = 2 + 9 * line
        chars = []
        for x in range(2, w - 4, 6):
            rows = []
            for row in range(7):
                bits = 0
                for column in range(5):
                    i = ((y + row) * w + x + column) * 3
                    if tuple(rgb[i:i + 3]) == TEXT:
                        bits |= 0x10 >> column
                rows.append(bits)
            rows = tuple(rows)
            chars.append(" " if not any(rows) else glyphs.get(rows, "?"))
        text.append("".join(chars).rstrip())
    return text


caps = {lane: os.path.join(out, lane, "shots", "race_hud.png") for lane in ("off", "overlay")}
missing = [lane for lane, p in caps.items() if not os.path.isfile(p)]
if missing:
    why.append(f"no capture in {', '.join(missing)}")
else:
    off, over = imgdiff.load_rgb(caps["off"]), imgdiff.load_rgb(caps["overlay"])
    w, h = over[0], over[1]
    scale = max(1, h // 360)
    inset = 4 * scale
    box = (inset, inset, inset + OVERLAY_W * scale, inset + OVERLAY_H * scale)
    if (off[0], off[1]) != (w, h):
        why.append(f"the captures differ in size: {off[0]}x{off[1]} and {w}x{h}")
    elif box[2] > w or box[3] > h:
        why.append(f"the overlay does not fit a {w}x{h} capture")
    else:
        note("")
        note(f"captures {w}x{h}; the overlay's rectangle: scale {scale}, x {box[0]}..{box[2]}, y {box[1]}..{box[3]} "
             f"({box[2] - box[0]}x{box[3] - box[1]})")
        # (a)
        changed = fraction(caps["overlay"], caps["off"], mask(w, h, box, True), TOL, os.path.join(out, "rect.diff.png"))
        ok = changed >= MIN_CHANGED
        note(f"(a) the rectangle, overlay against off at tol {TOL}: {changed:.4f} of its pixels differ (at least "
             f"{MIN_CHANGED}): {'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append(f"(a) the rectangle differs in {changed:.4f}")
        # (b)
        rect = crop(over, box)
        png.write_png(os.path.join(out, "overlay.png"), rect[0], rect[1], 3, rect[2])
        n = rect[0] * rect[1]
        lit = sum(1 for i in range(n) if max(rect[2][i * 3:i * 3 + 3]) > LIT)
        rect_off = crop(off, box)
        lit_off = sum(1 for i in range(n) if max(rect_off[2][i * 3:i * 3 + 3]) > LIT)
        ok = lit > 0
        note(f"(b) the rectangle's pixels not black (a channel above {LIT}): overlay {lit} ({lit / n:.4f}), off "
             f"{lit_off} ({lit_off / n:.4f}): {'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append("(b) the overlay's rectangle is black")
        # (c)
        rest = fraction(caps["overlay"], caps["off"], mask(w, h, box, False), REST_TOL,
                        os.path.join(out, "rest.diff.png"))
        ok = rest <= REST_LIMIT
        note(f"(c) the rest of the capture, overlay against off at tol {REST_TOL}: {rest:.4f} (limit {REST_LIMIT}, "
             f"race_hud's): {'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append(f"(c) the rest of the capture differs in {rest:.4f}")
        # (d)
        def covered(region):
            x, y, rw, rh = region
            x0, y0, x1, y1 = int(x * w / 480), int(y * h / 272), int((x + rw) * w / 480), int((y + rh) * h / 272)
            inside = max(0, min(x1, box[2]) - max(x0, box[0])) * max(0, min(y1, box[3]) - max(y0, box[1]))
            return inside / ((x1 - x0) * (y1 - y0))
        counts = {lane: {label: hud_check.yellow((img[0], img[1], 3, img[2]), region)
                         for label, region in hud_check.REGIONS.items()}
                  for lane, img in (("off", off), ("overlay", over))}
        shares = {label: covered(region) for label, region in hud_check.REGIONS.items()}
        needed = {"off": list(hud_check.REGIONS),
                  "overlay": [label for label in hud_check.REGIONS if shares[label] < 0.5]}
        for lane in ("off", "overlay"):
            found = [label for label in needed[lane] if counts[lane][label] > 0]
            ok = bool(needed[lane]) and len(found) == len(needed[lane])
            figures = ", ".join(f"{label} {counts[lane][label]} yellow"
                                + (f" ({shares[label]:.0%} under the rectangle)" if lane == "overlay"
                                   and shares[label] >= 0.5 else "")
                                for label in hud_check.REGIONS)
            note(f"(d) the HUD, {lane}: {figures}; required {', '.join(needed[lane])}: {'PASS' if ok else 'FAIL'}")
            if not ok:
                why.append(f"(d) no HUD in the {lane} lane")
        # (e)
        small = (OVERLAY_W, OVERLAY_H, bytes(b for y in range(OVERLAY_H) for x in range(OVERLAY_W)
                                             for b in rect[2][((y * scale) * rect[0] + x * scale) * 3:
                                                              ((y * scale) * rect[0] + x * scale) * 3 + 3]))
        whole = 0
        for y in range(OVERLAY_H):
            for x in range(OVERLAY_W):
                first = rect[2][((y * scale) * rect[0] + x * scale) * 3:((y * scale) * rect[0] + x * scale) * 3 + 3]
                whole += all(rect[2][((y * scale + dy) * rect[0] + x * scale + dx) * 3:
                                     ((y * scale + dy) * rect[0] + x * scale + dx) * 3 + 3] == first
                             for dy in range(scale) for dx in range(scale))
        glyphs = font()
        text = read_lines(small, glyphs) if glyphs else []
        ok = bool(text) and text[0].startswith("FPS ")
        note(f"(e) the overlay reads: {' | '.join(text) if text else '(the font is not readable from ' + FONT_SOURCE + ')'}"
             f"; {whole / (OVERLAY_W * OVERLAY_H):.4f} of its {scale}x{scale} blocks one colour: "
             f"{'PASS' if ok else 'FAIL'}")
        if not ok:
            why.append("(e) the overlay's first line does not read FPS")

verdict = "FAIL" if why else "PASS"
note("")
note(f"overlay check: {verdict} ({seconds // 60}m {seconds % 60}s)" + ("" if not why else ": " + "; ".join(why)))
note(f"overlay_check: {verdict}")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
