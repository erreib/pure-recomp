#!/bin/bash
# The ge_replay check (task 022): replays GE backend recordings (.gerec) outside the game and checks what they present.
#   tools/gerec/replay_check.sh
# Recordings are made only when missing, each by one windowed run of a route of tools/frame_regress.sh (pad scripts
# joined, `shot` steps dropped) on an empty memory stick of its own, drawn by Vulkan through the record backend in the
# Vulkan shell (PURE_SHELL=vulkan PURE_GE_RECORD_INNER=vulkan, set explicitly: the macOS default is the Metal path,
# D-008, which has no Vulkan renderer to record), and must pass tools/gerec/gerec_dump.py --summary:
#   out/gerec/race.gerec       main_menu.txt + single_race.txt, frames 6014-6016 (AT=6014 FRAMES=3), about 3.5 minutes
#   out/gerec/race_warm.gerec  the same route, frames 6008-6016 (AT=6008 FRAMES=9): six frames that fill the render
#                              targets before the three that are compared, about 3.5 minutes
#   out/gerec/frontend.gerec   frontend.txt, frames 690-691 (task 023), about 25 s
#   out/gerec/title.gerec      frontend.txt, frames 1750-1751 (task 023), about 1 minute
# The steps:
# 1. race.gerec into vulkan with --compare at tol 0. Reported, not a pass condition: a replay starts with no render
#    targets, and the first frames of a race recording depend on target pixels drawn before it began (the bottom rows
#    of the bloom target; docs/ge-backend.md, section 7), so frame 6014 cannot match from a cold start.
# 2. race_warm.gerec into vulkan with --compare --frames 6014-6016 --tol 4 --max-frac 0.001: must pass.
# 3. race.gerec into null with --out out/gerec/null: three black 480x272 frames, frame_6014.bmp to frame_6016.bmp, exit 0.
# 4. race.gerec into vulkan and null at once with --first-diff on frame 6014: the frame must fail (null draws nothing)
#    and the bisection must name the first draw that makes a difference, with its state.
# 5. frontend.gerec and title.gerec into vulkan with --compare at tol 0: must pass (2D screens hold no state across
#    frames that a recording lacks).
# Exit 0 when every step passes. Logs and replay outputs are in out/gerec/. Needs the screen (Vulkan opens a window).
set -u
cd "$(dirname "$0")/../.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD
# The build directory is the preset's: arm64 on macOS, win-x64 on Windows (task 054; purelib.port knows).
BIN=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
# Hard links on Windows: Git Bash's `ln -s` copies (253 MB of disc.iso per run) without Developer Mode (task 054).
case "$(uname -s)" in MINGW*|MSYS*) LNS="ln" ;; *) LNS="ln -s" ;; esac
OUT=out/gerec

[ -x "$BIN" ] || { echo "$BIN missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }
mkdir -p "$OUT"

FAILED=
START=$SECONDS
step() { echo; echo "== $*"; }
fail() { echo "replay_check: FAIL: $*"; FAILED="$FAILED|$*"; }

# record NAME ROUTE AT FRAMES: frames AT to AT+FRAMES-1 of ROUTE to out/gerec/NAME.gerec, unless that file exists.
record() {
  local name=$1 route=$2 at=$3 frames=$4
  local file="$OUT/$name.gerec" game="$OUT/$name.game" script="$OUT/$name.route.txt"
  local last=$((at + frames + 10))
  if [ -s "$file" ]; then
    echo "$file exists ($(wc -c < "$file" | tr -d ' ') bytes): not recorded again"
    return 0
  fi
  rm -rf "$game" "$file.capture.bmp"
  mkdir -p "$game/ms0/PSP/SAVEDATA"
  $LNS "$ROOT/game/EBOOT.ELF" "$game/EBOOT.ELF"
  $LNS "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$game/disc.iso"
  : > "$script"
  for part in $(echo "$route" | tr '+' ' '); do
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)' "config/pad_scripts/$part" >> "$script"
  done
  echo "recording $name: $route, frames $at-$((at + frames - 1)), run to frame $last ..."
  local t0=$SECONDS
  # The Vulkan shell and an explicit Vulkan inner backend: the Metal default (D-008) has no Vulkan renderer to record.
  python3 tools/run_boot.py --script "$script" --frames "$last" --shell vulkan \
    --env PURE_GAME_DIR="$ROOT/$game" --env PURE_GE_BACKEND=record --env PURE_GE_RECORD_INNER=vulkan \
    --env PURE_GE_RECORD="$ROOT/$file" \
    --env PURE_GE_RECORD_AT="$at" --env PURE_GE_RECORD_FRAMES="$frames" \
    "$OUT/$name.record.log" > "$OUT/$name.record.stdout" 2>&1
  local rc=$?
  echo "recording $name: run_boot exit $rc, $((SECONDS - t0)) s, log $OUT/$name.record.log"
  grep -E '^\[gerec\] saved' "$OUT/$name.record.log"
  if [ ! -s "$file" ]; then
    fail "recording $name: no $file"
    return 1
  fi
  if ! python3 tools/gerec/gerec_dump.py --summary "$file" > "$OUT/$name.dump.txt" 2>&1; then
    tail -8 "$OUT/$name.dump.txt"
    fail "recording $name: gerec_dump rejects $file"
    rm -f "$file"
    return 1
  fi
  sed -n '/^  frame/,$p' "$OUT/$name.dump.txt"
}

# replay LOG ARGS...: one replay, its [replay] lines (and a bisected draw's state) shown; sets rc.
replay() {
  local log=$1
  shift
  "$BIN" --replay "$@" > "$log" 2>&1
  rc=$?
  grep -E '^\[replay\]|^  [a-z]' "$log"
}

step "recordings"
record race main_menu.txt+single_race.txt 6014 3
record race_warm main_menu.txt+single_race.txt 6008 9
record frontend frontend.txt 690 2
record title frontend.txt 1750 2

if [ -s "$OUT/race.gerec" ]; then
  step "1. race.gerec into vulkan, against the recorded images from a cold start (reported, not a pass condition)"
  replay "$OUT/replay_vulkan_cold.log" "$OUT/race.gerec" --backend vulkan --compare --out "$OUT/vulkan_cold"
  [ $rc -le 1 ] || fail "vulkan replay of race.gerec exit $rc (log $OUT/replay_vulkan_cold.log)"
fi

if [ -s "$OUT/race_warm.gerec" ]; then
  step "2. race_warm.gerec into vulkan, frames 6014-6016 against the recorded images after six frames of warm-up"
  replay "$OUT/replay_vulkan.log" "$OUT/race_warm.gerec" --backend vulkan --compare --frames 6014-6016 \
    --tol 4 --max-frac 0.001 --out "$OUT/vulkan"
  [ $rc -eq 0 ] || fail "vulkan replay of race_warm.gerec exit $rc (log $OUT/replay_vulkan.log)"
  [ "$(grep -c '^\[replay\] frame 601[456]: .* PASS$' "$OUT/replay_vulkan.log")" -eq 3 ] ||
    fail "vulkan replay of race_warm.gerec: frames 6014-6016 did not all pass"
fi

if [ -s "$OUT/race.gerec" ]; then
  step "3. race.gerec into null"
  rm -rf "$OUT/null"
  replay "$OUT/replay_null.log" "$OUT/race.gerec" --backend null --out "$OUT/null"
  [ $rc -eq 0 ] || fail "null replay exit $rc (log $OUT/replay_null.log)"
  for frame in 6014 6015 6016; do
    bmp="$OUT/null/frame_$frame.bmp"
    if [ ! -f "$bmp" ]; then
      fail "null replay wrote no $bmp"
    elif python3 -c 'import sys; sys.path.insert(0, "tools"); import png
w, h, c, data = png.read_bmp(sys.argv[1]); sys.exit(0 if (w, h) == (480, 272) and not any(data) else 1)' "$bmp"; then
      echo "$bmp: black, 480x272"
    else
      fail "$bmp is not a black 480x272 frame"
    fi
  done

  step "4. race.gerec into vulkan and null, frame 6014 bisected to its first differing draw"
  replay "$OUT/replay_first_diff.log" "$OUT/race.gerec" --a vulkan --b null --first-diff --frames 6014
  [ $rc -eq 1 ] || fail "vulkan against null exit $rc, expected 1 (log $OUT/replay_first_diff.log)"
  grep -q '^\[replay\] frame 6014: .* FAIL$' "$OUT/replay_first_diff.log" ||
    fail "vulkan against null: frame 6014 did not fail"
  grep -q '^\[replay\] first difference in frame 6014: draw [0-9]' "$OUT/replay_first_diff.log" ||
    fail "vulkan against null: no first differing draw named"
fi

for name in frontend title; do
  [ -s "$OUT/$name.gerec" ] || continue
  step "5. $name.gerec into vulkan, against the recorded images"
  replay "$OUT/replay_$name.log" "$OUT/$name.gerec" --backend vulkan --compare --out "$OUT/vulkan_$name"
  [ $rc -eq 0 ] || fail "vulkan replay of $name.gerec exit $rc (log $OUT/replay_$name.log)"
done

echo
if [ -n "$FAILED" ]; then
  echo "replay_check: FAIL ($((SECONDS - START)) s):$(echo "$FAILED" | tr '|' '\n' | sed '/^$/d; s/^/ /' | tr '\n' ';')"
  exit 1
fi
echo "replay_check: PASS ($((SECONDS - START)) s)"
