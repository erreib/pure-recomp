#!/bin/bash
# The menu check (task 064, D-014): opens the Esc menu at the title in a window with PURE_MENU_DUMP=1 (patch
# 0016-menu-rows-by-capability) and checks each tab's rows against the lists this game and this shell should show.
#   tools/menu_check.sh [--shell metal|vulkan] [--out DIR]
#   --shell  the window shell, with its own GE backend (default metal, the macOS default): the Metal shell answers no
#            to frame interpolation, the performance overlay, Fill and touch controls; the Vulkan shell yes to all.
#   --out    default out/menu_check/<shell>: the run's log (run.log), its shots (shots/title.png, shots/menu.png: the
#            Video tab as the menu shows it after the dump) and the result (summary.txt). Removed first.
# The route: config/pad_scripts/menu_check.txt, frontend.txt's steps to the title, then Escape at flip 2100 (the menu
# opens a few frames later and its first frames dump a tab each) and Escape again 70 script frames later (counted in
# menu frames while the paused menu is open), which closes it; the run ends at flip 2250. Unpaced until flip 2050
# (PURE_PACED_FROM), paced from there; about 25 s. Silent, on the data directory out/data/menu_check.
# The lists (Wipeout Pure's profile: no ad hoc play, no right-stick or mouse camera): four tabs, no Network; no Camera
# choice, camera inversion or mouse rows. Both shells: Resolution first (the GE backend's internal scale, patch
# 0017-internal-scale-by-backend, task 067; locked by the run's PURE_INTERNAL_SCALE=1). Metal: no Texture filter or
# texture pack rows (the Vulkan renderer's), no Frame rate, Lower when behind or Performance, no F3 row, no Touch
# screen rows, "Metal on". Vulkan: all of those, "Vulkan on". Aspect ratio offers Original and Stretch in both: Fill needs a game that widens its view
# (GameProfile::view_aspect_frame), which this one does not. Both: the Video tab ends with the game's own options
# (patch 0019-game-option-rows, task 070) in the option table's order: 30 fps modes (task 072; game.sixty_fps, locked by
# the run's PURE_SIXTY_FPS=0), Flashes (game.smooth_flashes; locked by the run's PURE_SMOOTH_FLASHES=0) and Text and
# sprites (task 073; game.sprite_upscale, locked by the run's PURE_SPRITE_UPSCALE=0; shown under the Vulkan shell too,
# where it does nothing until a texture pack exists), all tools/purelib/port.py's pin (the game's row is not called
# Frame rate: under the Vulkan shell that is the renderer's frame-rate cap). A `*` in a list matches any text (the
# device's name).
# Waits up to 600 s while another PureNative runs (one game at a time). Prints `menu_check: PASS` or each tab's
# differences and `menu_check: FAIL`; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

SHELL_NAME=metal
OUT=
usage() {
  echo "usage: tools/menu_check.sh [--shell metal|vulkan] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "menu_check: unknown argument $1"; usage ;;
  esac
done
case $SHELL_NAME in
  metal|vulkan) ;;
  *) echo "menu_check: --shell is metal or vulkan, not $SHELL_NAME"; exit 2 ;;
esac
OUT=${OUT:-out/menu_check/$SHELL_NAME}

EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
[ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

# One game at a time (task 034): a second game beside a windowed run can delay its boot and break its route.
python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("menu_check: " + m, flush=True),
                              limit=600) else 2)' || exit 2

rm -rf "$OUT"
mkdir -p "$OUT/shots"
echo "menu_check: shell $SHELL_NAME, out $OUT"
t0=$SECONDS
python3 tools/run_boot.py --script config/pad_scripts/menu_check.txt --shots "$OUT/shots" --frames 2250 \
  --shell "$SHELL_NAME" --backend "$SHELL_NAME" --data-dir out/data/menu_check \
  --env PURE_MENU_DUMP=1 --env PURE_PACED_FROM=2050 "$OUT/run.log" > "$OUT/run.stdout" 2>&1
echo "menu_check: run_boot exit $?, $((SECONDS - t0)) s, log $OUT/run.log"

python3 - "$SHELL_NAME" "$OUT/run.log" > "$OUT/summary.txt" <<'EOF'
import re, sys

shell, log = sys.argv[1], sys.argv[2]


def matches(got, want):
    """`want` with `*` matching any text; everything else, brackets too, literally."""
    return re.fullmatch(".*".join(re.escape(part) for part in want.split("*")), got) is not None


metal = shell == "metal"
bindings = ["Move forward", "Move left", "Move back", "Move right", "△", "○  (confirm)", "×  (back)", "□", "L", "R",
            "START", "SELECT", "D-pad up", "D-pad left", "D-pad down", "D-pad right", "Camera up", "Camera left",
            "Camera down", "Camera right"]
expected = {
    "tabs": ["Video", "Audio", "Controls", "System"],
    "Video": ["Resolution", "Display", "Window size", "Aspect ratio (Original / Stretch)", "Scaling filter"]
             + ([] if metal else ["Texture filter", "Texture pack", "[texture pack rows]"]) + ["Vsync"]
             + ([] if metal else ["Frame rate", "Lower when behind"]) + ["Game speed", "Fast loading"]
             + ([] if metal else ["Performance"])
             + ["[font rows]", "Restore video defaults", "30 fps modes", "Flashes", "Text and sprites"],
    "Audio": ["Volume", "Mute", "Device", "Restore audio defaults"],
    "Controls": ["Connected", "Confirm button", "Stick dead zone", "Trigger point", "Right stick (D-pad / Off)",
                 "Right stick D-pad point", "When the game asks for a name", "Pilot name"] + bindings
                + ["Esc"] + ([] if metal else ["F3"]) + ["Restore control defaults"]
                + ([] if metal else ["On-screen controls", "D-pad", "Controls opacity", "Controls size",
                                     "Touch camera speed"])
                + ["Use the classic keyboard layout"],
    "System": ["Resume", "Pause the game when the menu opens", "Open the data folder", "Set up game data again…",
               "Quit game", "[save rows]", "Wipeout Pure Native", "Game", "Data folder", "Saves folder",
               "Graphics (%s on *)" % ("Metal" if metal else "Vulkan"), "Interface"],
}

# The dump: "[menu] tabs: A, B" then "[menu] Tab: row, row (choices), ...". A build with a label adds a Build row.
dumped = {}
with open(log, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line.startswith("[menu] ") or ": " not in line:
            continue
        name, rows = line[len("[menu] "):].split(": ", 1)
        if name in ("tabs", "Video", "Audio", "Controls", "Network", "System") and name not in dumped:
            dumped[name] = [r for r in rows.split(", ") if r != "Build"]

failed = False
for name, want in expected.items():
    got = dumped.get(name)
    if got is None:
        print(f"{name}: no dump line")
        failed = True
        continue
    if len(got) == len(want) and all(matches(g, w) for g, w in zip(got, want)):
        print(f"{name}: ok ({len(got)})")
        continue
    failed = True
    missing = [w for w in want if not any(matches(g, w) for g in got)]
    extra = [g for g in got if not any(matches(g, w) for w in want)]
    print(f"{name}: differs")
    print(f"  expected: {', '.join(want)}")
    print(f"  dumped:   {', '.join(got)}")
    if missing:
        print(f"  missing:  {', '.join(missing)}")
    if extra:
        print(f"  extra:    {', '.join(extra)}")
    if not missing and not extra:
        print("  (the same rows in another order)")
for name in dumped:
    if name not in expected:
        print(f"{name}: a tab this game should not have")
        failed = True
print("menu_check: FAIL" if failed else "menu_check: PASS")
sys.exit(1 if failed else 0)
EOF
check=$?
cat "$OUT/summary.txt"
exit $check
