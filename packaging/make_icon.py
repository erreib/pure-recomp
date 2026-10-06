#!/usr/bin/env python3
"""Draws the app icon (task 029): a dark rounded square with the letters WP, W in cyan and P in pink.

  python3 packaging/make_icon.py          # packaging/icon.png (256x256) and packaging/macos/Wipeout Pure.icns

A plain generated picture: no game art and no logo of the game's owners. The shapes are signed distance fields in a
256-unit design square, so every size of the .icns is drawn at its own resolution with one pixel of anti-aliasing
(no resampling). Writes PNGs with tools/png.py (zlib only); the .icns comes from macOS's iconutil.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from png import write_png  # noqa: E402

# Design square of 256 units. The body follows macOS's icon grid (824 of 1024, corner 185).
BODY_CENTER, BODY_HALF, BODY_RADIUS = 128.0, 103.0, 46.0
TOP, BOTTOM = (20, 24, 38), (38, 44, 66)         # body gradient
W_COLOUR, P_COLOUR = (46, 200, 245), (255, 80, 156)
STROKE = 8.5                                      # half the letters' stroke width
W_POINTS = [(54, 92), (75, 165), (97, 114), (119, 165), (140, 92)]
P_STEM = ((164, 92), (164, 165))
P_BOWL_CENTER, P_BOWL_RADIUS = (180.0, 115.0), 23.0


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def body_sd(px, py):
    qx = abs(px - BODY_CENTER) - (BODY_HALF - BODY_RADIUS)
    qy = abs(py - BODY_CENTER) - (BODY_HALF - BODY_RADIUS)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - BODY_RADIUS


def w_sd(px, py):
    d = min(seg_dist(px, py, *W_POINTS[i], *W_POINTS[i + 1]) for i in range(len(W_POINTS) - 1))
    return d - STROKE


def p_sd(px, py):
    (sx, top), (_, bottom) = P_STEM
    cx, cy = P_BOWL_CENTER
    r = P_BOWL_RADIUS
    d = seg_dist(px, py, sx, top, sx, bottom)
    # The bowl: two short bars from the stem and the right half of a ring.
    d = min(d, seg_dist(px, py, sx, cy - r, cx, cy - r), seg_dist(px, py, sx, cy + r, cx, cy + r))
    if px >= cx:
        d = min(d, abs(math.hypot(px - cx, py - cy) - r))
    return d - STROKE


def coverage(sd_units, scale):
    return max(0.0, min(1.0, 0.5 - sd_units * scale))


def render(size):
    scale = size / 256.0                          # pixels per design unit
    out = bytearray(size * size * 4)
    for y in range(size):
        py = (y + 0.5) / scale
        t = max(0.0, min(1.0, (py - 25.0) / 206.0))
        bg = [TOP[k] + (BOTTOM[k] - TOP[k]) * t for k in range(3)]
        for x in range(size):
            px = (x + 0.5) / scale
            a = coverage(body_sd(px, py), scale)
            if a <= 0.0:
                continue
            rgb = bg
            for sd, colour in ((w_sd(px, py), W_COLOUR), (p_sd(px, py), P_COLOUR)):
                c = coverage(sd, scale)
                if c > 0.0:
                    rgb = [rgb[k] + (colour[k] - rgb[k]) * c for k in range(3)]
            i = (y * size + x) * 4
            out[i:i + 4] = bytes((round(rgb[0]), round(rgb[1]), round(rgb[2]), round(255 * a)))
    return bytes(out)


def main():
    icon_png = os.path.join(ROOT, "packaging", "icon.png")
    write_png(icon_png, 256, 256, 4, render(256))
    print("wrote", os.path.relpath(icon_png, ROOT))
    icns = os.path.join(ROOT, "packaging", "macos", "Wipeout Pure.icns")
    tmp = tempfile.mkdtemp()
    try:
        iconset = os.path.join(tmp, "icon.iconset")
        os.mkdir(iconset)
        pictures = {}
        for base in (16, 32, 128, 256, 512):
            for factor, suffix in ((1, ""), (2, "@2x")):
                size = base * factor
                if size not in pictures:
                    pictures[size] = render(size)
                write_png(os.path.join(iconset, f"icon_{base}x{base}{suffix}.png"), size, size, 4, pictures[size])
        subprocess.run(["iconutil", "-c", "icns", "-o", icns, iconset], check=True)
    finally:
        shutil.rmtree(tmp)
    print("wrote", os.path.relpath(icns, ROOT))


if __name__ == "__main__":
    main()
