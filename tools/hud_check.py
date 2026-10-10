#!/usr/bin/env python3
"""The race HUD in shots (task 031, from task 028's probe): counts the shots that show the HUD.

  tools/hud_check.py DIR [--expect N]

Reads every `h<FLIP>.bmp` in DIR (tools/hud_check.sh writes them: window shots at the window's pixel size (960x544, or the Metal shell's drawable since task 065), or the backend's own
480x272 captures headless) and looks for the HUD's two yellow labels in their regions below, given in PSP pixels
(480x272) and scaled to the shot's size:

  CURRENT   x 2, y 2, 52 x 10     the lap clock's label, top left
  LAP       x 2, y 232, 26 x 10   the lap counter's label, bottom left

A pixel is yellow when red > 180, green > 130 and blue < 90 (task 028's thresholds). A shot has the HUD when both
regions hold at least one yellow pixel. Prints one line per shot (`FLIP current lap` yellow counts and H, h for one
label only, or - for none), then `hud_check: N of M shots have the HUD`. Exit 0 when N equals M (and M equals
--expect when given), 1 otherwise, 2 when DIR has no shots.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png  # noqa: E402  (tools/png.py)

# The labels' regions in PSP pixels: (x, y, width, height).
REGIONS = {"current": (2, 2, 52, 10), "lap": (2, 232, 26, 10)}
# Yellow: the labels' colour, and nothing the track shows behind them in the probe's 61 shots on any path.
RED_MIN, GREEN_MIN, BLUE_MAX = 180, 130, 90


def yellow(shot, region):
    """Yellow pixels of `region` (PSP pixels) in the decoded BMP `shot`."""
    w, h, c, data = shot
    sx, sy = w / 480, h / 272
    x, y, rw, rh = region
    n = 0
    for py in range(int(y * sy), int((y + rh) * sy)):
        for px in range(int(x * sx), int((x + rw) * sx)):
            i = (py * w + px) * c
            if data[i] > RED_MIN and data[i + 1] > GREEN_MIN and data[i + 2] < BLUE_MAX:
                n += 1
    return n


def main():
    p = argparse.ArgumentParser(prog="hud_check.py")
    p.add_argument("dir")
    p.add_argument("--expect", type=int, help="the number of shots the route takes")
    opts = p.parse_args()
    names = [n for n in os.listdir(opts.dir) if n.startswith("h") and n.endswith(".bmp") and n[1:-4].isdigit()]
    names.sort(key=lambda n: int(n[1:-4]))
    if not names:
        print(f"hud_check: no shots in {opts.dir}")
        return 2
    with_hud = 0
    for name in names:
        shot = png.read_bmp(os.path.join(opts.dir, name))
        current, lap = yellow(shot, REGIONS["current"]), yellow(shot, REGIONS["lap"])
        mark = "H" if current and lap else ("h" if current or lap else "-")
        with_hud += mark == "H"
        print(f"{name[1:-4]:>6} {current:5d} {lap:5d}  {mark}")
    print(f"hud_check: {with_hud} of {len(names)} shots have the HUD")
    if opts.expect is not None and len(names) != opts.expect:
        print(f"hud_check: {len(names)} shots, the route takes {opts.expect}")
        return 1
    return 0 if with_hud == len(names) else 1


if __name__ == "__main__":
    sys.exit(main())
