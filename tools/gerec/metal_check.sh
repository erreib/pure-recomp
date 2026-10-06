#!/bin/bash
# The Metal GE backend against the Vulkan one through ge_replay (task 024; docs/metal-backend.md, "The 3D check").
#   tools/gerec/metal_check.sh [TEAM_FRAME]        TEAM_FRAME defaults to 5650
# Recordings are made only when missing, each by one windowed run of main_menu.txt + single_race.txt (`shot` steps
# dropped) on an empty memory stick of its own, drawn by Vulkan through the record backend, as
# tools/gerec/replay_check.sh makes them, and must pass gerec_dump.py --summary:
#   out/gerec/team.gerec       frames TEAM_FRAME and TEAM_FRAME+1 at internal scale 1 (PURE_INTERNAL_SCALE=1), the
#                              TEAM SELECTION screen (frames 5503-5701 of the route: 5650 is in its middle, so a run
#                              that drifts by a few tens of frames still lands on it). Recorded again when the file
#                              holds other frames or another scale. About 3 minutes
#   out/gerec/race_1x.gerec    frames 6008-6016 at internal scale 1, the race; about 3.5 minutes
#   out/gerec/race_warm.gerec  the same frames at the settings' scale (2x), replay_check.sh's; about 3.5 minutes
# A replay draws at the scale its recording was made at, so the 1x recordings compare Vulkan at 1x with Metal at 1x
# (internal scale 1, D-002): the same pixel centres, no edges moved by a 2x-to-1x reduction. The TEAM screen's text
# is drawn minified and filtered, which at 2x against 1x puts 5% of its pixels over tol 24 by construction.
# The steps:
# 1. The team frames' draws, from gerec_dump.py: none may draw into the bloom targets (0x04110000, 0x04132000) or
#    use the stencil, so that the comparison holds nothing task 025 has still to do. Lit and fogged draws are counted
#    and reported; the frontend has none (docs/metal-backend.md says how that was checked).
# 2. team.gerec into vulkan and metal at once, --tol 24 --max-frac 0.02: must pass.
# 3. For the record, not a pass condition: race frame 6016 into vulkan and metal, bisected with --first-diff at
#    tol 24 (the first draw after which any pixel differs by more than 24): (a) race_1x.gerec, where it names the
#    first draw that differs for a reason other than the scale; (b) race_warm.gerec, at 2x against 1x.
# Exit 0 when steps 1 and 2 pass. Logs are in out/gerec/metal_*.log. Needs the screen (Vulkan opens a window).
set -u
cd "$(dirname "$0")/../.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD
BIN=build/arm64/bin/PureNative
OUT=out/gerec
TEAM_FRAME=${1:-5650}
ROUTE=main_menu.txt+single_race.txt

case "$TEAM_FRAME" in ''|*[!0-9]*) echo "usage: tools/gerec/metal_check.sh [TEAM_FRAME]"; exit 2 ;; esac
[ -x "$BIN" ] || { echo "$BIN missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }
mkdir -p "$OUT"

FAILED=
START=$SECONDS
step() { echo; echo "== $*"; }
fail() { echo "metal_check: FAIL: $*"; FAILED="$FAILED|$*"; }

# held FILE: "FIRST SCALE", the first frame a recording holds (its Begin record) and the scale of its first image
# (width / 480); empty when the file does not parse that far.
held() {
  python3 - "$1" <<'EOF' 2>/dev/null
import struct, sys
data = open(sys.argv[1], "rb").read()
at, first = 12, None
while at + 5 <= len(data):
    kind, size = struct.unpack_from("<BI", data, at)
    if kind == 1:
        first = struct.unpack_from("<I", data, at + 5)[0]
    elif kind == 11:  # FrameEnd: frame, display, 2 x u64, draws, records, api, width
        print(first, struct.unpack_from("<I", data, at + 5 + 33)[0] // 480)
        break
    at += 5 + size
EOF
}

# record NAME AT FRAMES SCALE: frames AT to AT+FRAMES-1 of the route to out/gerec/NAME.gerec at internal scale SCALE
# (empty: the settings'), unless that file holds them at that scale.
record() {
  local name=$1 at=$2 frames=$3 scale=$4
  local file="$OUT/$name.gerec" game="$OUT/$name.game" script="$OUT/$name.route.txt"
  local last=$((at + frames + 10))
  if [ -s "$file" ]; then
    local first_scale
    first_scale=$(held "$file")
    if [ "${first_scale% *}" = "$at" ] && { [ -z "$scale" ] || [ "${first_scale#* }" = "$scale" ]; }; then
      echo "$file exists ($(wc -c < "$file" | tr -d ' ') bytes, from frame $at at ${first_scale#* }x): not recorded again"
      return 0
    fi
    echo "$file holds frames from ${first_scale% *} at ${first_scale#* }x, not $at at ${scale}x: recording it again"
    rm -f "$file"
  fi
  rm -rf "$game"
  mkdir -p "$game/ms0/PSP/SAVEDATA"
  ln -s "$ROOT/game/EBOOT.ELF" "$game/EBOOT.ELF"
  ln -s "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$game/disc.iso"
  : > "$script"
  for part in $(echo "$ROUTE" | tr '+' ' '); do
    grep -Ev '^[[:space:]]*[0-9]+:[[:space:]]*shot([[:space:]]|$)' "config/pad_scripts/$part" >> "$script"
  done
  local scale_env=()
  [ -n "$scale" ] && scale_env=(--env "PURE_INTERNAL_SCALE=$scale")
  echo "recording $name: $ROUTE, frames $at-$((at + frames - 1))${scale:+ at internal scale $scale}, run to frame $last ..."
  local t0=$SECONDS
  python3 tools/run_boot.py --script "$script" --frames "$last" \
    --env PURE_GAME_DIR="$ROOT/$game" --env PURE_GE_BACKEND=record --env PURE_GE_RECORD="$ROOT/$file" \
    --env PURE_GE_RECORD_AT="$at" --env PURE_GE_RECORD_FRAMES="$frames" ${scale_env[@]+"${scale_env[@]}"} \
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
record team "$TEAM_FRAME" 2 1
record race_1x 6008 9 1
record race_warm 6008 9 ""

if [ -s "$OUT/team.gerec" ]; then
  step "1. team.gerec (frames $TEAM_FRAME-$((TEAM_FRAME + 1))): what its draws are"
  python3 tools/gerec/gerec_dump.py "$OUT/team.gerec" > "$OUT/team.draws.txt" 2>&1
  draws=$(grep -c ' Draw ' "$OUT/team.draws.txt")
  transformed=$(grep ' Draw ' "$OUT/team.draws.txt" | grep -vc 'through')
  lit=$(grep ' Draw ' "$OUT/team.draws.txt" | grep -Ec '[ ,]lit(,|$)')
  fogged=$(grep ' Draw ' "$OUT/team.draws.txt" | grep -Ec '[ ,]fog(,|$)')
  stencil=$(grep ' Draw ' "$OUT/team.draws.txt" | grep -Ec '[ ,]stencil(,|$)')
  bloom=$(grep ' Draw ' "$OUT/team.draws.txt" | grep -Ec -- '-> 0x041(10|32)000 ')
  echo "$draws draws: $transformed transformed, $lit lit, $fogged fogged, $stencil with the stencil, $bloom into the bloom targets"
  [ "$draws" -gt 0 ] || fail "team.gerec holds no draw"
  [ "$stencil" -eq 0 ] || fail "team.gerec has $stencil draws with the stencil (task 025's): choose another frame"
  [ "$bloom" -eq 0 ] || fail "team.gerec has $bloom draws into the bloom targets (task 025's): choose another frame"

  step "2. team.gerec into vulkan and metal, tol 24, max-frac 0.02"
  replay "$OUT/metal_team.log" "$OUT/team.gerec" --a vulkan --b metal --tol 24 --max-frac 0.02 --out "$OUT/metal_team"
  [ $rc -eq 0 ] || fail "team.gerec: vulkan against metal exit $rc (log $OUT/metal_team.log)"
fi

for name in race_1x race_warm; do
  [ -s "$OUT/$name.gerec" ] || continue
  [ $name = race_1x ] && label="3a" || label="3b"
  step "$label. $name.gerec frame 6016 into vulkan and metal, bisected at tol 24 (reported, not a pass condition)"
  replay "$OUT/metal_${name}_first_diff.log" "$OUT/$name.gerec" --a vulkan --b metal --frames 6016 --tol 24 --first-diff
  [ $rc -le 1 ] || fail "$name.gerec: vulkan against metal exit $rc (log $OUT/metal_${name}_first_diff.log)"
done

echo
if [ -n "$FAILED" ]; then
  echo "metal_check: FAIL ($((SECONDS - START)) s):$(echo "$FAILED" | tr '|' '\n' | sed '/^$/d; s/^/ /' | tr '\n' ';')"
  exit 1
fi
echo "metal_check: PASS ($((SECONDS - START)) s)"
