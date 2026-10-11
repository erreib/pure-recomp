#!/bin/bash
# The sprite upscale check (task 073, D-018's check for E7): the one check run with the Text and sprites option on.
# Seven scenes of the frame regression suite, captured headless on Metal at PURE_INTERNAL_SCALE=4 twice, with
# PURE_SPRITE_UPSCALE=0 (the PSP's texels, what every other tool runs with: tools/purelib/port.py's original_pacing)
# and with 1 (the player's default, the menus' and the HUD's bitmaps upscaled 4x at decode).
#   tools/sprite_check.sh [--out DIR] [--wait SECONDS]
#   --out      default out/sprite_check: DIR/0 and DIR/1 hold each run's captures and logs (tools/frame_regress.sh
#              --out), DIR/1/reduced the 1 captures reduced to 480x272, DIR/hud/<scene>/h<frame>.bmp the race scenes'
#              1 captures for tools/hud_check.py, DIR/<scene>.diff.png the differing pixels of a scene whose reduction
#              fails, DIR/summary.txt the table.
#   --wait     how long to wait for other games to end when the suite's one-game guard refuses to start (default 600;
#              0 gives up at once), as tools/scale_check.sh waits.
# PASS when, for every scene:
#   - the 1 capture is 1920x1088 (the display target at internal scale 4);
#   - reduced to 480x272 by the centre pixel of each 4 x 4 block (tools/scale_check.sh's rule and code, copied: the
#     rule by which the backend feeds guest memory, D-015), it is within the scene's own limit of its PPSSPP reference
#     at the scene's tol, both read from tools/frame_regress.sh's scene table (the picture is the same picture);
#   - the full 1 capture differs from the full 0 capture in at least 1% of its pixels at tol 24 (the detail is there);
#   - for the race scenes (race_hud, tt_hud, zone_hud), the 1 capture passes tools/hud_check.py (the HUD found);
# and the main_menu run's exit line (`[metal] ...; N textures upscaled (T ms)`) says at least 2 textures were
# upscaled, in under 2000 ms in all. Prints the table and `sprite_check: PASS` or `FAIL` last. Exit 0 PASS, 1 FAIL,
# 2 cannot run (a suite refused for longer than --wait, no capture at all).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

DIR=out/sprite_check
WAIT=600
SCALE=4
SCENES="title main_menu class_select team_select race_hud tt_hud zone_hud"
HUD_SCENES="race_hud tt_hud zone_hud"
usage() {
  echo "usage: tools/sprite_check.sh [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "sprite_check: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "sprite_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
START=$SECONDS

# capture V: the scenes headless on Metal at internal scale 4 with PURE_SPRITE_UPSCALE=V, into DIR/V, retried while
# the one-game guard refuses, for up to --wait seconds. The suite's own verdict (each capture against its reference at
# its own size, by nearest neighbour) does not matter here.
capture() {
  local v=$1 where="$DIR/$1" waited=0 rc
  rm -rf "$where"
  mkdir -p "$where"
  while :; do
    tools/frame_regress.sh --out "$where" --shell headless --backend metal --only "$(echo $SCENES | tr ' ' ',')" \
      --env "PURE_INTERNAL_SCALE=$SCALE" --env "PURE_SPRITE_UPSCALE=$v" > "$DIR/frame_regress.$v.stdout" 2>&1
    rc=$?
    grep -q '^frame_regress: another PureNative is running' "$DIR/frame_regress.$v.stdout" || break
    if [ $waited -ge "$WAIT" ]; then
      cat "$DIR/frame_regress.$v.stdout"
      echo "sprite_check: another game kept running for $WAIT s; try again later"
      exit 2
    fi
    [ $waited -eq 0 ] && sed -n '2,$p' "$DIR/frame_regress.$v.stdout" | sed 's/^/  waiting for: /'
    sleep 20
    waited=$((waited + 20))
  done
  [ $waited -gt 0 ] && echo "  (waited $waited s for another game to end)"
  if [ $rc -eq 2 ]; then
    cat "$DIR/frame_regress.$v.stdout"
    echo "sprite_check: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep -h '^\[pure\] sprite upscale' "$where"/*.log 2>/dev/null | sort | uniq -c | sed "s/^ */  PURE_SPRITE_UPSCALE=$v: /"
}

rm -rf "$DIR"/*.diff.png "$DIR/summary.txt" "$DIR/hud"
echo "sprite check $(date '+%Y-%m-%d %H:%M'): $SCENES at internal scale $SCALE, PURE_SPRITE_UPSCALE 0 and 1," \
  "headless on Metal, into $DIR"
capture 0
capture 1

python3 - "$DIR" "$SCALE" "$SCENES" "$HUD_SCENES" "$((SECONDS - START))" <<'EOF'
import os, re, subprocess, sys
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

out, scale, scenes, hud_scenes, seconds = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(), sys.argv[4].split(), \
    sys.argv[5]
DIFF_TOL, MIN_DIFF = 24, 0.01           # the full captures: at least 1% of pixels over tol 24
MIN_UPSCALED, MAX_UPSCALE_MS = 2, 2000.0
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
note(f"each PURE_SPRITE_UPSCALE=1 capture: its size, by its blocks' centre pixels against the scene's reference at the "
     f"scene's tol and limit (tools/frame_regress.sh), the full capture against the PURE_SPRITE_UPSCALE=0 one at tol "
     f"{DIFF_TOL} (at least {MIN_DIFF:.0%}), and the race HUD (tools/hud_check.py):")
note(f"{'scene':<14} {'size':>10} {'reduced':>8} {'limit':>6} {'tol':>4} {'vs 0':>8} {'HUD':>4}  result")
passed = 0
for scene in scenes:
    route, frame, ref, tol, limit = table[scene]
    a, b = os.path.join(out, "1", "shots", scene + ".png"), os.path.join(out, "0", "shots", scene + ".png")
    if not (os.path.isfile(a) and os.path.isfile(b)):
        note(f"{scene:<14} {'-':>10} {'-':>8} {limit:>6} {tol:>4} {'-':>8} {'-':>4}  FAIL (no capture with "
             f"{'1' if not os.path.isfile(a) else '0'})")
        continue
    w, h, _ = imgdiff.load_rgb(a)
    why = []
    if (w, h) != size:
        why.append(f"not {size[0]}x{size[1]}")
        reduced_text, vs0_text = "-", "-"
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
    hud_text = "-"
    if scene in hud_scenes:
        ok, last = hud(scene, a, frame)
        hud_text = "yes" if ok else "no"
        if not ok:
            why.append(f"no HUD ({last})")
    passed += not why
    note(f"{scene:<14} {f'{w}x{h}':>10} {reduced_text:>8} {limit:>6} {tol:>4} {vs0_text:>8} {hud_text:>4}  "
         + ("PASS" if not why else "FAIL (" + "; ".join(why) + ")"))

note("")
stats_ok = False
log = os.path.join(out, "1", "main_menu.log")
found = None
if os.path.isfile(log):
    with open(log, errors="replace") as f:
        for line in f:
            m = re.search(r"^\[metal\] \d+ frames, .*; (\d+) textures upscaled \(([\d.e+-]+) ms\)", line)
            if m:
                found = (int(m[1]), float(m[2]))
if found is None:
    note(f"main_menu run: no exit line with the upscale counts in {log}: FAIL")
else:
    stats_ok = found[0] >= MIN_UPSCALED and found[1] < MAX_UPSCALE_MS
    note(f"main_menu run: {found[0]} textures upscaled in {found[1]:.1f} ms (at least {MIN_UPSCALED}, under "
         f"{MAX_UPSCALE_MS:.0f} ms): {'PASS' if stats_ok else 'FAIL'}")

verdict = "PASS" if passed == len(scenes) and stats_ok else "FAIL"
note("")
note(f"sprite check: {passed}/{len(scenes)} scenes pass, the main menu's upscales {'PASS' if stats_ok else 'FAIL'} "
     f"({int(seconds) // 60}m {int(seconds) % 60}s)")
note(f"sprite_check: {verdict}")
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
