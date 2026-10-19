#!/bin/bash
# The race HUD check (task 031, from task 028's probe): runs the race route and counts the shots that show the HUD.
# The frame regression suite's race_hud (flip 6016) comes before the race clock starts; this check covers the race
# itself, where the Metal shell's window once dropped the HUD in most frames (docs/tasks/031-metal-window-hud.md).
#   tools/hud_check.sh [--shell metal|vulkan|headless] [--backend NAME] [--out DIR] [--env KEY=VAL ...]
#   --shell    the shell whose pictures are checked (default metal, the macOS default): the Metal shell's window,
#              the Vulkan shell's, or, headless, the GE backend's own 480x272 captures (unpaced, about 15 s).
#   --backend  the GE backend (default: metal under the metal and headless shells, vulkan under the vulkan shell).
#   --out      default out/hud/<shell>: the route (route.txt), the run's log (run.log), the shots (shots/h<FLIP>.bmp
#              and .png) and the count (summary.txt). Removed first.
#   --env      extra environment for the run (tools/run_boot.py --env).
# The run is silent and uses the data directory out/data/hud_check (settings.ini, pipeline caches), not the
# player's, unless the environment sets PURE_NO_AUDIO or PURE_DATA_DIR (tools/run_boot.py; task 034).
# The route: config/pad_scripts/main_menu.txt + single_race.txt (Vineta K, Cross held from flip 6100, no steering),
# their own shot steps dropped, on an empty memory stick (<out>/game, tools/lib.sh's fresh_stick), with a
# shot every 25 flips from 6200 to 7700 (61 shots; the race goes at about 6250) and the run ending at flip 7710.
# The shots are read by tools/hud_check.py: the yellow of the CURRENT label (PSP pixels x 2, y 2, 52 x 10) and of
# the LAP label (x 2, y 232, 26 x 10), red > 180, green > 130, blue < 90. Prints `hud_check: N of M shots have the
# HUD` (also in <out>/summary.txt) and exits 0 when every shot of the route was taken and has it. In a window the run
# is unpaced until PACE_MARGIN flips before the first shot (PURE_PACED_FROM=5900, task 069) and paced to real time
# from there, so the race's frames are a player's: about 80 s in all (227 s paced from boot); headless
# it is unpaced throughout. The caller's PURE_PACED_FROM (the environment's, or an --env) wins.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

FIRST=6200
STEP=25
LAST=7700
END=7710
PACE_MARGIN=300

SHELL_NAME=metal
BACKEND=
OUT=
ENVS=()
usage() {
  echo "usage: tools/hud_check.sh [--shell metal|vulkan|headless] [--backend NAME] [--out DIR] [--env KEY=VAL ...]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; case $2 in *=*) ;; *) usage ;; esac; ENVS+=(--env "$2"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "hud_check: unknown argument $1"; usage ;;
  esac
done
case $SHELL_NAME in
  metal|headless) BACKEND=${BACKEND:-metal} ;;
  vulkan) BACKEND=${BACKEND:-vulkan} ;;
  *) echo "hud_check: --shell is metal, vulkan or headless, not $SHELL_NAME"; exit 2 ;;
esac
OUT=${OUT:-out/hud/$SHELL_NAME}

need_game

rm -rf "$OUT"
mkdir -p "$OUT/shots"
OUT=$(cd "$OUT" && pwd)
fresh_stick "$OUT/game"
{
  cat config/pad_scripts/main_menu.txt config/pad_scripts/single_race.txt |
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)'
  for f in $(seq $FIRST $STEP $LAST); do echo "$f:shot h$f"; done
} > "$OUT/route.txt"
shots=$(( (LAST - FIRST) / STEP + 1 ))

# The pace (task 069): in a window, unpaced until PACE_MARGIN flips before the first shot, paced from there.
# The caller's PURE_PACED_FROM (the environment's, or an --env, the last one winning as in tools/run_boot.py) wins.
given=${PURE_PACED_FROM:-}
for e in ${ENVS[@]+"${ENVS[@]}"}; do case $e in PURE_PACED_FROM=*) given=${e#*=} ;; esac; done
pace=()
paced=unpaced
if [ -n "$given" ]; then
  paced="paced from flip $given (the caller's)"
elif [ "$SHELL_NAME" != headless ]; then
  pace=(--env "PURE_PACED_FROM=$((FIRST - PACE_MARGIN))"); paced="paced from flip $((FIRST - PACE_MARGIN))"
fi
echo "hud_check: shell $SHELL_NAME, backend $BACKEND, $shots shots from flip $FIRST to $LAST, $paced, out $OUT"
t0=$SECONDS
python3 tools/run_boot.py --script "$OUT/route.txt" --shots "$OUT/shots" --frames $END --shell "$SHELL_NAME" \
  --data-dir out/data/hud_check \
  --backend "$BACKEND" --env PURE_GAME_DIR="$OUT/game" ${pace[@]+"${pace[@]}"} ${ENVS[@]+"${ENVS[@]}"} \
  "$OUT/run.log" > "$OUT/run.stdout" 2>&1
rc=$?
reached=no
grep -q "^\[pure\] exit at frame $END" "$OUT/run.log" && reached=yes
echo "hud_check: run_boot exit $rc, frame $END reached: $reached, $((SECONDS - t0)) s, log $OUT/run.log"
python3 tools/hud_check.py "$OUT/shots" --expect $shots > "$OUT/summary.txt"
check=$?
grep -v '^hud_check:' "$OUT/summary.txt" | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $1 ":" $4 } END { print "" }'
grep '^hud_check:' "$OUT/summary.txt"
[ "$reached" = yes ] && [ $check -eq 0 ]
