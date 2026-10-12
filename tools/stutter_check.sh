#!/bin/bash
# The stutter check (task 077): does a race on the window's renderer hold its frame budget with the shipped defaults?
#   tools/stutter_check.sh [--shell metal|vulkan] [--backend metal|vulkan] [--out DIR]
#   --shell    the window shell (default vulkan under MINGW/MSYS, the rig; metal elsewhere), --backend the GE backend
#              (default: the shell's own).
#   --out      default out/stutter_check/<backend>-<shell>; removed first.
# One Single Race cell of Vineta K through tools/campaign_sweep.py single_race vineta_k --no-damage in the window (the
# sweep's own pacing: unpaced menus, the race paced from the Cross hold), with sound (PURE_NO_AUDIO=0: the sweep then
# keeps its pacing, as --sound would not), PURE_PERF=log (a `[perf]` line a second: `frame avg A max M ms`, M the
# second's worst frame) and PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=25 (a `[stalls]` line a second: `readback R ...`,
# R ms a frame over the line's frames; a `[slow-frame]` line for each frame over 25 ms), and the shipped defaults of
# the enhancements named here, since every tool run has them off unless its caller names them (tools/purelib/port.py's
# ENHANCEMENTS_OFF): PURE_SIXTY_FPS=1, PURE_SMOOTH_FLASHES=1, PURE_TEXTURE_DETAIL=1 (the player's defaults) and
# PURE_SPRITE_UPSCALE=0 (Original, the default since D-018 as amended). That is the planning session's probe of task
# 077. About 6 minutes. The log is read from the race's first paced flip (`[pure] paced from frame N`) to its end:
# PASS when (a) at most 1 in 10 of those seconds has a frame over SLOW_MS (its `[slow-frame]` lines between the
# second's `[perf]` lines) after the frame's own pacing sleeps are taken off (the pacer sleeps only when the game is
# ahead of real time, so that part of a long frame is the schedule holding, not a stutter), the flips that are a
# multiple of 10 left out: the window's input script reads the sweep's
# live file (PURE_INPUT_LIVE, the follower's steering) on those, which costs the rig 15 to 25 ms of render time
# whatever the renderer does (946 of the 951 race frames with render over 12 ms in task 077's run), and a player has
# no live file; they are counted and printed apart. And (b) the readback stall
# (`[stalls]` readback, the GPU drains for a framebuffer or depth written back to guest memory) averages at most
# MAX_READBACK_MS a frame over them, weighted by each line's frames. Prints both figures and the worst second either
# way. The cell itself must PASS (the race reached its results screen). Waits up to 600 s while another PureNative
# runs (one game at a time). Prints `stutter_check: PASS ...` or `stutter_check: FAIL ...` last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

SLOW_MS=25              # a frame over this misses the race's 60 fps budget by more than half a frame
MAX_SLOW_FRACTION=0.1   # (a): seconds with such a frame, at most 1 in 10
MAX_READBACK_MS=2.0     # (b): the readback stall, ms a frame

case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) SHELL_NAME=vulkan ;;
  *) SHELL_NAME=metal ;;
esac
BACKEND=
OUT=
usage() {
  echo "usage: tools/stutter_check.sh [--shell metal|vulkan] [--backend metal|vulkan] [--out DIR]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "stutter_check: unknown argument $1"; usage ;;
  esac
done
case $SHELL_NAME in
  metal) BACKEND=${BACKEND:-metal} ;;
  vulkan) BACKEND=${BACKEND:-vulkan} ;;
  *) echo "stutter_check: --shell is metal or vulkan (a window: the check measures wall time), not $SHELL_NAME"; exit 2 ;;
esac
case $BACKEND in metal|vulkan) ;; *) echo "stutter_check: --backend is metal or vulkan, not $BACKEND"; exit 2 ;; esac
OUT=${OUT:-out/stutter_check/$BACKEND-$SHELL_NAME}

EXE=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port; print(port.EXE)')
[ -x "$EXE" ] || { echo "$EXE missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "stutter_check: shell $SHELL_NAME, backend $BACKEND, out $OUT"

# One game at a time (task 034).
python3 -c 'import sys; sys.path.insert(0, "tools"); from purelib import port
sys.exit(0 if port.wait_until(port.other_games, port.REFUSED, lambda m: print("stutter_check: " + m, flush=True),
                              limit=600) else 2)' || exit 2
t0=$SECONDS
PURE_PERF=log PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=$SLOW_MS PURE_NO_AUDIO=0 PURE_SIXTY_FPS=1 \
  PURE_SMOOTH_FLASHES=1 PURE_TEXTURE_DETAIL=1 PURE_SPRITE_UPSCALE=0 \
  python3 tools/campaign_sweep.py single_race vineta_k --no-damage --out "$OUT/race" --shell "$SHELL_NAME" \
  --backend "$BACKEND" > "$OUT/race.stdout" 2>&1
echo "stutter_check: campaign_sweep exit $?, $((SECONDS - t0)) s, log $OUT/race/single_race-vineta_k.log"

python3 - "$OUT" $SLOW_MS $MAX_SLOW_FRACTION $MAX_READBACK_MS <<'EOF' | tee "$OUT/summary.txt"
import os, re, sys
sys.path.insert(0, "tools")
from fidelity_audit import SWEEP_LINE_RE  # the sweep's summary line

out = sys.argv[1]
slow_ms, max_fraction, max_readback = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
PACED_RE = re.compile(r"^\[pure\] paced from frame (\d+)")
PERF_RE = re.compile(r"^\[perf\] .*\| frame avg ([\d.]+) max ([\d.]+) ms")
SLOW_RE = re.compile(r"^\[slow-frame\] (\d+) ([\d.]+) ms")
# The frame's own pacing sleeps: the pacer sleeps only when the game is AHEAD
# of real time, so that part of a long frame is the schedule holding, not a
# stutter a player feels. (a) judges the frame without it (the review of task
# 077: the realign frame after each live-file read was half the FAILs).
PACING_RE = re.compile(r" pacing ([\d.]+) x\d")
POLL = 10  # the input script reads PURE_INPUT_LIVE on flips that are a multiple of this (host/ui/input_script.cpp)
STALLS_RE = re.compile(r"^\[stalls\] ms per frame over (\d+) frames:")
READBACK_RE = re.compile(r" readback ([\d.]+) max")

outcome = None
with open(os.path.join(out, "race.stdout"), errors="replace") as f:
    for line in f:
        m = SWEEP_LINE_RE.match(line.strip())
        if m and m[1] == "single_race-vineta_k":
            outcome = m[2]
log = os.path.join(out, "race", "single_race-vineta_k.log")
paced, seconds, frames, readback, pending, polls = None, [], 0, 0.0, [], []
if os.path.exists(log):
    with open(log, errors="replace") as f:
        for line in f:
            if paced is None:
                m = PACED_RE.match(line)
                if m:
                    paced = int(m[1])
                continue
            m = SLOW_RE.match(line)
            if m:
                flip, ms = int(m[1]), float(m[2])
                p = PACING_RE.search(line)
                if p:
                    ms -= float(p[1])
                if flip % POLL == 0:
                    polls.append(ms)
                else:
                    pending.append((ms, flip))
                continue
            m = PERF_RE.match(line)
            if m:
                worst_slow = max(pending, default=None)
                seconds.append((len(seconds) + 1, float(m[1]), float(m[2]), worst_slow))
                pending = []
                continue
            m = STALLS_RE.match(line)
            if m:
                n = int(m[1])
                r = READBACK_RE.search(line)
                frames += n
                readback += (float(r[1]) if r else 0.0) * n
fails = []
if outcome != "PASS":
    fails.append(f"the race cell {outcome or 'has no outcome'}")
if paced is None:
    fails.append("no `[pure] paced from frame` line")
slow = [s for s in seconds if s[3] is not None and s[3][0] > slow_ms]
fraction = len(slow) / len(seconds) if seconds else 1.0
mean = readback / frames if frames else 0.0
worst = max(slow, key=lambda s: s[3][0]) if slow else None
if not seconds:
    fails.append("no `[perf]` lines after the paced flip")
elif fraction > max_fraction:
    fails.append(f"{len(slow)} of {len(seconds)} seconds have a frame over {slow_ms:g} ms (at most {max_fraction:.0%})")
if not frames:
    fails.append("no `[stalls]` lines after the paced flip")
elif mean > max_readback:
    fails.append(f"readback {mean:.2f} ms a frame (at most {max_readback:g})")
print(f"race: {outcome or 'no outcome'}, paced from flip {paced}; {len(seconds)} seconds, {frames} frames")
print(f"(a) seconds with a frame over {slow_ms:g} ms: {len(slow)} of {len(seconds)} ({fraction:.1%}); apart, the "
      f"live-file flips (a multiple of {POLL}) over it: {len(polls)}, worst {max(polls, default=0.0):.1f} ms")
print(f"(b) readback: {mean:.2f} ms a frame")
if worst:
    print(f"worst second: #{worst[0]} after the paced flip, frame avg {worst[1]:.1f} max {worst[2]:.1f} ms, "
          f"flip {worst[3][1]} {worst[3][0]:.1f} ms")
else:
    print(f"worst second: none has a frame over {slow_ms:g} ms but the live-file flips")
print(f"stutter_check: {'FAIL' if fails else 'PASS'} ({len(slow)} of {len(seconds)} seconds over {slow_ms:g} ms, "
      f"readback {mean:.2f} ms a frame{'; ' + '; '.join(fails) if fails else ''})")
EOF
grep -q '^stutter_check: PASS' "$OUT/summary.txt"
