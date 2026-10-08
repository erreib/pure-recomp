#!/bin/bash
# The frame regression suite (task 020): boots the game through the known routes, captures five scenes, compares each
# with its PPSSPP reference in ref/ (tools/imgdiff.py) and prints a PASS/FAIL table, also written to <out>/summary.txt.
# Exit 0 only when every scene passes. Every renderer change runs this before merging, on both paths (D-008). Three
# bounded runs, one per route, each on an empty memory stick of its own (<out>/game, EBOOT.ELF and disc.iso linked
# to game/), because main_menu.txt creates and saves a profile. By default (task 034) they run headless on the Metal
# backend: no window, unpaced, the scenes the backend's own 480x272 pictures, under a minute in all; in a window
# (--shell metal or vulkan) each run is paced to real time and the suite takes about 7 minutes.
#   tools/frame_regress.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR]
#                          [--only SCENE[,SCENE...]] [--env KEY=VAL ...] [--allow-parallel]
#   --backend  sets PURE_GE_BACKEND for the runs, records it in the summary and picks the table's measured column
#              (default metal, the macOS default since D-008; vulkan is the bootstrap path through MoltenVK).
#   --shell    sets PURE_SHELL for the runs and records it in the summary beside the backend (default headless): the
#              shots are the GE backend's own 480x272 captures, the Metal shell's window (task 027) or the Vulkan
#              shell's. The window paths, the gates for shell changes (docs/verification.md), are --shell metal
#              --backend metal and --shell vulkan --backend vulkan.
#   --out      captures (<out>/shots/<scene>.png), run logs, diff images of failing scenes (<out>/<scene>.diff.png:
#              the capture dimmed, differing pixels red) and summary.txt; default out/regress. The suite's files
#              from an earlier run there are removed first.
#   --only     these scenes only, and only the runs they need (in a window --only race_hud takes about 3.5 minutes).
#   --env      extra environment for every run (tools/run_boot.py --env), e.g. a deliberate regression:
#              tools/frame_regress.sh --shell vulkan --backend vulkan --only race_hud --env PURE_NO_STENCIL_BUFFER=1
#              (race_hud FAILs)
#   --allow-parallel  start even while another PureNative runs. Without it the suite refuses to start then, naming
#              the process (task 034: one game at a time; a second game beside a windowed run has broken that
#              run's menu route).
# The runs are silent and use the data directory out/data/frame_regress (settings.ini, pipeline caches), not the
# player's, unless the environment sets PURE_NO_AUDIO or PURE_DATA_DIR (tools/run_boot.py; task 034).
# A scene's fraction is the share of pixels that differ by more than `tol` in any channel, with the capture (480x272
# headless, 960x544 in a window) and the 480x272 reference both at 480x272 (nearest neighbour). It passes at or below
# `limit`. The measured columns hold what the scene scored on each backend when its limit or the backend last
# changed; the table prints the difference from the running backend's column, and a move of more than 0.03 means
# something changed even when the scene still passes. Re-baselining: docs/verification.md, "Frame regression suite".
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD

# The scenes. Route: input scripts in config/pad_scripts/, joined in order with their own `shot` steps dropped; the
# suite adds `FRAME:shot SCENE` for each scene of the route and runs to the route's last shot + EXTRA_FLIPS. Scenes on
# the same route share one run. The measured values per backend (and where they come from) stay beside the limits.
# The metal column serves the Metal window and the headless shell alike: the headless captures equal the window's,
# reduced to 480x272, pixel for pixel in all five scenes, and three headless runs scored within 0.001 of it (task 034).
#  scene      route                          frame  reference               tol  limit  vulkan  metal
SCENES='
   lang       frontend.txt                   690    ref/frontend.png        24   0.07   0.054   0.0002  # vulkan task 006: one-pixel edges of lines and glyphs from the 2x-to-1x downscale; metal task 023: 22 px, the blinking cursor after ENGLISH
   title      frontend.txt                   1750   ref/title.png           24   0.05   0.030   0.0002  # vulkan tasks 006, 009, 010, 011: 0.0302 each time; metal task 023: 31 px, the blinking cursor after PRESS START BUTTON
   profile    frontend.txt                   2100   ref/profile.png         24   0.07   0.054   0.0000  # vulkan task 006: downscale edges, as lang; metal task 023: 0 px
   main_menu  main_menu.txt                  4700   ref/main_menu.png       24   0.05   0.033   0.0106  # vulkan task 006: help text caught mid-typing; metal task 023
   race_hud   main_menu.txt+single_race.txt  6016   ref/vineta_k_start.png  32   0.10   0.067   0.0149  # vulkan task 011 review: first full-HUD frame, bloom and shadows on, runs 0.063-0.086 (the AI grid varies); metal task 025
   single_player      main_menu.txt+single_race.txt  4765  ref/single_player.png      24  0.05   0.025   0.0000  # task 035: SINGLE PLAYER (SINGLE RACE highlighted); PPSSPP frame 5850 of frontend.txt+vineta_k_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   class_select       main_menu.txt+single_race.txt  4990  ref/class_select.png       24  0.07   0.045   0.0000  # task 035: CLASS SELECTION (VECTOR); PPSSPP 6050; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   league_select      main_menu.txt+single_race.txt  5185  ref/league_select.png      24  0.08   0.062   0.0000  # task 035: LEAGUE SELECTION (ALPHA); PPSSPP 6250; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   track_select       main_menu.txt+single_race.txt  5390  ref/track_select.png       24  0.06   0.041   0.0000  # task 035: TRACK SELECTION (VINETA K, length and records); PPSSPP 6450; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   team_select        main_menu.txt+single_race.txt  5600  ref/team_select.png        24  0.06   0.042   0.0000  # task 035: TEAM SELECTION (FEISAR, the wireframe ship); PPSSPP 6690; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   tt_track_select    main_menu.txt+time_trial.txt   5375  ref/tt_track_select.png    24  0.06   0.040   0.0000  # task 035 (metal re-baselined after task 036): the Time Trial TRACK SELECTION (records, bronze/silver/gold); PPSSPP 6650 of time_trial_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   tt_hud             main_menu.txt+time_trial.txt   5890  ref/tt_hud.png             32  0.12   0.096   0.0112  # task 035: the Time Trial first full-HUD frame on Vineta K (CURRENT, BEST, BRONZE TIME); PPSSPP vblank 7340 (the file f07302 of burst C); metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   fp_track_select    main_menu.txt+free_play.txt    5375  ref/fp_track_select.png    24  0.06   0.041   0.0000  # task 035: the Free Play TRACK SELECTION (records, length, height); PPSSPP 6650 of free_play_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   fp_hud             main_menu.txt+free_play.txt    5890  ref/fp_hud.png             32  0.11   0.095   0.0116  # task 035: the Free Play first full-HUD frame on Vineta K; PPSSPP vblank 7340 (the file f07302 of burst E); metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   tournament_select  main_menu.txt+tournament.txt   5185  ref/tournament_select.png  24  0.08   0.063   0.0000  # task 035: TOURNAMENT SELECTION (ALPHA, its four tracks); PPSSPP 6450 of tournament_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   zone_track_select  main_menu.txt+zone.txt         4975  ref/zone_track_select.png  24  0.05   0.033   0.0000  # task 035: the Zone TRACK SELECTION (PRO TOZO, targets); PPSSPP 6250 of zone_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   zone_hud           main_menu.txt+zone.txt         5260  ref/zone_hud.png           32  0.09   0.065   0.0121  # task 035: the Zone 1 first frame with the HUD (SCORE, ZONE 0); PPSSPP vblank 6694 (the file f06668 of burst H); metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
   zone_change        main_menu.txt+zone.txt         5679  ref/zone_change.png        32  0.10   0.082   0.0353  # task 035: the first zone change of Zone 1, the first frame with ZONE 2 and SCORE 800 (the ship stopped at the first barrier, Cross held); PPSSPP vblank 7528 of zone_start.txt; metal: three headless runs, the same each time; vulkan: one windowed run (task 035)
'
EXTRA_FLIPS=30

OUT=out/regress
BACKEND=metal
SHELL_NAME=headless
ONLY=
ENVS=()
PARALLEL=no
# Windows (task 055): the Vulkan backend draws only in the Vulkan shell's window, so the suite defaults to it there.
case "$(uname -s)" in MINGW*|MSYS*) BACKEND=vulkan; SHELL_NAME=vulkan ;; esac
usage() {
  echo "usage: tools/frame_regress.sh [--backend metal|vulkan] [--shell headless|metal|vulkan] [--out DIR] [--only SCENE[,SCENE...]] [--env KEY=VAL ...] [--allow-parallel]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --only) [ $# -ge 2 ] || usage; ONLY=$2; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; case $2 in *=*) ;; *) usage ;; esac; ENVS+=(--env "$2"); shift 2 ;;
    --allow-parallel) PARALLEL=yes; shift ;;
    -h|--help) usage ;;
    *) echo "frame_regress: unknown argument $1"; usage ;;
  esac
done
case $BACKEND in vulkan|metal) ;; *) echo "frame_regress: --backend is vulkan or metal, not $BACKEND"; exit 2 ;; esac
case $SHELL_NAME in vulkan|metal|headless) ;; *) echo "frame_regress: --shell is vulkan, metal or headless, not $SHELL_NAME"; exit 2 ;; esac

# The build directory is the preset's: arm64 on macOS, win-x64 on Windows (task 054; purelib.port knows).
EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
[ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

# One game at a time (task 034): a second PureNative beside a windowed run has delayed its boot and broken its menu
# route, and one beside this suite's runs would load the machine they are measured on.
if [ $PARALLEL = no ]; then
  others=$(python3 -c 'import sys; sys.path.insert(0, "tools"); import run_boot
print("\n".join(f"  pid {p}: {c}" for p, c in run_boot.other_games()))')
  if [ -n "$others" ]; then
    echo "frame_regress: another PureNative is running; one game at a time (--allow-parallel starts anyway):"
    echo "$others"
    exit 2
  fi
fi
DATA=out/data/frame_regress

# The table without comments and blank lines, filtered by --only.
TABLE=$(printf '%s\n' "$SCENES" | sed 's/#.*//' | awk 'NF >= 8')
if [ -n "$ONLY" ]; then
  for s in $(echo "$ONLY" | tr ',' ' '); do
    printf '%s\n' "$TABLE" | awk -v s="$s" '$1 == s { found = 1 } END { exit !found }' ||
      { echo "frame_regress: no scene $s (scenes: $(printf '%s\n' "$TABLE" | awk '{ printf "%s ", $1 }'))"; exit 2; }
  done
  TABLE=$(printf '%s\n' "$TABLE" | awk -v only=",$ONLY," 'index(only, "," $1 ",") > 0')
fi
while read -r scene route frame ref tol limit measured_vulkan measured_metal; do
  [ -f "$ref" ] || { echo "$ref missing (PPSSPP captures are git-ignored: copy them from the main checkout's ref/)"; exit 2; }
done <<< "$TABLE"

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/shots" "$OUT/game"
rm -f "$OUT"/*.log "$OUT"/*.stdout "$OUT"/*.route.txt "$OUT"/*.diff.png "$OUT/summary.txt"
mkdir -p "$OUT/shots" "$OUT/game"
# Hard links on Windows: Git Bash's `ln -s` copies (253 MB of disc.iso per run) without Developer Mode (task 054).
case "$(uname -s)" in MINGW*|MSYS*) LNS="ln" ;; *) LNS="ln -s" ;; esac
$LNS "$ROOT/game/EBOOT.ELF" "$OUT/game/EBOOT.ELF"
$LNS "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$OUT/game/disc.iso"

START=$SECONDS
SUMMARY=()
note() { echo "$*"; SUMMARY+=("$*"); }
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
git diff --quiet HEAD 2>/dev/null || commit="$commit+changes"
note "frame regression $(date '+%Y-%m-%d %H:%M'), commit $commit, shell $SHELL_NAME (PURE_SHELL), backend $BACKEND (PURE_GE_BACKEND), measured column $BACKEND"
extra=$(printf '%s ' ${ENVS[@]+"${ENVS[@]}"} | sed 's/--env //g; s/ *$//')
note "extra environment: ${extra:-none}"
note "data directory: ${PURE_DATA_DIR:-$DATA}"

# One run per route, in table order, on an empty memory stick.
ROUTES=$(printf '%s\n' "$TABLE" | awk '!seen[$2]++ { print $2 }')
for route in $ROUTES; do
  name=$(echo "$route" | sed 's/\.txt//g')
  script="$OUT/$name.route.txt"
  last=$(printf '%s\n' "$TABLE" | awk -v r="$route" '$2 == r { print $3 }' | sort -n | tail -1)
  frames=$((last + EXTRA_FLIPS))
  # The shots go first, so at a frame shared with a press (the input script sorts stably) they capture before it.
  printf '%s\n' "$TABLE" | awk -v r="$route" '$2 == r { print $3 ":shot " $1 }' > "$script"
  for part in $(echo "$route" | tr '+' ' '); do
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)' "config/pad_scripts/$part" >> "$script"
  done
  rm -rf "$OUT/game/ms0"
  mkdir -p "$OUT/game/ms0/PSP/SAVEDATA"
  echo "run $name: $frames flips ..."
  t0=$SECONDS
  python3 tools/run_boot.py --script "$script" --shots "$OUT/shots" --frames "$frames" --data-dir "$DATA" \
    --env PURE_GAME_DIR="$OUT/game" --env PURE_GE_BACKEND="$BACKEND" --env PURE_SHELL="$SHELL_NAME" ${ENVS[@]+"${ENVS[@]}"} \
    "$OUT/$name.log" > "$OUT/$name.stdout" 2>&1
  rc=$?
  reached=no
  grep -q "^\[pure\] exit at frame $frames" "$OUT/$name.log" && reached=yes
  note "run $name: run_boot exit $rc, frame $frames reached: $reached, $((SECONDS - t0)) s, log $OUT/$name.log"
done

# Compare each capture with its reference.
row() { printf '%-10s %6s %9s %6s %4s %9s %7s  %s' "$@"; }
note ""
note "$(row scene frame fraction limit tol measured delta result)"
PASSED=0
TOTAL=0
DRIFT=
while read -r scene route frame ref tol limit measured_vulkan measured_metal; do
  TOTAL=$((TOTAL + 1))
  measured=$measured_vulkan
  [ "$BACKEND" = metal ] && measured=$measured_metal
  cap="$OUT/shots/$scene.png"
  diff="$OUT/$scene.diff.png"
  fraction=-
  delta=-
  if [ ! -f "$cap" ]; then
    result="FAIL (no capture)"
  else
    line=$(python3 tools/imgdiff.py "$cap" "$ref" --tol "$tol" --max-frac "$limit" --out "$diff" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
      result=PASS; PASSED=$((PASSED + 1)); rm -f "$diff"
    elif [ $rc -eq 1 ]; then
      result="FAIL (diff $diff)"
    else
      result="ERROR ($line)"; rm -f "$diff"
    fi
    if [ $rc -le 1 ]; then
      fraction=$(echo "$line" | awk '$2 == "fraction" { printf "%.4f", $3 }')
      delta=$(awk -v f="$fraction" -v m="$measured" 'BEGIN { printf "%+.4f", f - m }')
      awk -v d="$delta" 'BEGIN { exit !(d > 0.03 || d < -0.03) }' && DRIFT="$DRIFT $scene"
    fi
  fi
  note "$(row "$scene" "$frame" "$fraction" "$limit" "$tol" "$measured" "$delta" "$result")"
done <<< "$TABLE"
note ""
[ -n "$DRIFT" ] && note "moved more than 0.03 from the $BACKEND measured value:$DRIFT (something changed; docs/verification.md)"
verdict=FAIL
[ $PASSED -eq $TOTAL ] && verdict=PASS
note "frame regression: $verdict, $PASSED/$TOTAL scenes pass, shell $SHELL_NAME, backend $BACKEND ($(( (SECONDS - START) / 60 ))m $(( (SECONDS - START) % 60 ))s)"
printf '%s\n' "${SUMMARY[@]}" > "$OUT/summary.txt"
[ "$verdict" = PASS ]
