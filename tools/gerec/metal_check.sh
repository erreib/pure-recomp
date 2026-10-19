#!/bin/bash
# The Metal GE backend against the Vulkan one through ge_replay (tasks 024 and 025; docs/metal-backend.md, "The 3D
# check" and "The race check").
#   tools/gerec/metal_check.sh [TEAM_FRAME]        TEAM_FRAME defaults to 5650
# The setup, the recordings and the replays are tools/gerec/replay_check.sh's (this sources it; task 094): a recording
# is made when it is missing, holds other frames or another internal scale, or is older than the current format
# (gerec_dump.py --current), by one windowed run of main_menu.txt + single_race.txt (`shot` steps dropped) on an empty
# memory stick of its own, drawn by Vulkan through the record backend in the Vulkan shell (PURE_SHELL=vulkan
# PURE_GE_RECORD_INNER=vulkan, set explicitly: the macOS default is the Metal path, D-008), and must pass
# gerec_dump.py --summary; every replay has the sprite upscale, the texture detail and the display rate off:
#   out/gerec/team.gerec       frames TEAM_FRAME and TEAM_FRAME+1 at internal scale 1 (PURE_INTERNAL_SCALE=1), the
#                              TEAM SELECTION screen (frames 5503-5701 of the route: 5650 is in its middle, so a run
#                              that drifts by a few tens of frames still lands on it). About 3 minutes
#   out/gerec/race_1x.gerec    frames 6008-6016 at internal scale 1, the race; about 3.5 minutes
#   out/gerec/race_warm.gerec  the same frames at the settings' scale (2x), replay_check.sh's; about 3.5 minutes
# A replay draws at the scale its recording was made at, so the 1x recordings compare Vulkan at 1x with Metal at 1x
# (internal scale 1, D-002): the same pixel centres, no edges moved by a 2x-to-1x reduction. The TEAM screen's text
# is drawn minified and filtered, which at 2x against 1x puts 5% of its pixels over tol 24 by construction.
# The steps:
# 1. The team frames' draws, from gerec_dump.py: none may draw into the bloom targets (0x04110000, 0x04132000) or
#    use the stencil, so that they check the transformed path alone (the race checks the rest). Lit and fogged draws
#    are counted and reported; the frontend has none (docs/metal-backend.md says how that was checked).
# 2. team.gerec into vulkan and metal at once, --tol 24 --max-frac 0.02: must pass.
# 3. race_1x.gerec frame 6016 into vulkan and metal, --tol 24 --max-frac 0.02 (task 025: the stencil kept as alpha,
#    the shadow volumes, the bloom chain, the depth and frame write-backs): must pass. When it fails, --first-diff
#    names the first draw after which the pictures differ, and the recording cut after that draw (ge_replay --cut)
#    leaves both pictures in out/gerec/metal_race_cut/a and b.
# 4. For the record, not a pass condition: race frame 6016 bisected with --first-diff at tol 24 and no fraction
#    allowed (the first draw after which any pixel differs by more than 24): (a) race_1x.gerec; (b) race_warm.gerec,
#    at 2x against 1x, where the 2x-to-1x reduction moves edges from the first alpha-tested draws on.
# Exit 0 when steps 1 to 3 pass. Logs are in out/gerec/metal_*.log. Needs the screen (Vulkan opens a window).
set -u
TEAM_FRAME=${1:-5650}
case "$TEAM_FRAME" in ''|*[!0-9]*) echo "usage: tools/gerec/metal_check.sh [TEAM_FRAME]"; exit 2 ;; esac
TOOL=metal_check
. "$(dirname "$0")/replay_check.sh"     # the setup, record(), replay(), step(), fail() and verdict()
ROUTE=main_menu.txt+single_race.txt

step "recordings"
record team "$ROUTE" "$TEAM_FRAME" 2 1
record race_1x "$ROUTE" 6008 9 1
record race_warm "$ROUTE" 6008 9

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

if [ -s "$OUT/race_1x.gerec" ]; then
  step "3. race_1x.gerec frame 6016 into vulkan and metal, tol 24, max-frac 0.02"
  # The Metal backend maps textures from normals and the texture matrix (task 036) and the Vulkan
  # backend does not: the race A/B compares the two with that feature off on both sides.
  replay "$OUT/metal_race.log" "$OUT/race_1x.gerec" --a vulkan --b metal --frames 6016 --tol 24 --max-frac 0.02 \
    --first-diff --out "$OUT/metal_race"
  if [ $rc -ne 0 ]; then
    fail "race_1x.gerec frame 6016: vulkan against metal exit $rc (log $OUT/metal_race.log)"
    cut=$(sed -n 's/^\[replay\] first difference in frame [0-9]*: draw \([0-9]*\) of.*/\1/p' "$OUT/metal_race.log")
    if [ -n "$cut" ]; then
      rm -rf "$OUT/metal_race_cut"
      replay "$OUT/metal_race_cut.log" "$OUT/race_1x.gerec" --a vulkan --b metal --frames 6016 --cut "$cut" \
        --tol 24 --out "$OUT/metal_race_cut"
      echo "both pictures after draw $cut: $OUT/metal_race_cut/a/frame_6016.bmp (vulkan), $OUT/metal_race_cut/b/frame_6016.bmp (metal)"
    fi
  fi
else
  fail "no out/gerec/race_1x.gerec"
fi

for name in race_1x race_warm; do
  [ -s "$OUT/$name.gerec" ] || continue
  [ $name = race_1x ] && label="4a" || label="4b"
  step "$label. $name.gerec frame 6016 into vulkan and metal, bisected at tol 24 (reported, not a pass condition)"
  replay "$OUT/metal_${name}_first_diff.log" "$OUT/$name.gerec" --a vulkan --b metal --frames 6016 --tol 24 --first-diff
  [ $rc -le 1 ] || fail "$name.gerec: vulkan against metal exit $rc (log $OUT/metal_${name}_first_diff.log)"
done

verdict
