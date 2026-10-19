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
# 077. The Display rate row (E8, task 089) stays at tools/purelib/port.py's pin (Original) unless the environment names
# PURE_DISPLAY_RATE; with PURE_DISPLAY_RATE=1 the race runs at the display's refresh, so the cell's flip budget (13000,
# counted at 60 flips a second) is doubled with --frames 26000, a ceiling for a display up to 120 Hz: the race still
# ends at its results screen. About 6 minutes. The log is read from the race's first paced flip (`[pure] paced from frame N`) to its end:
# PASS when (a) at most 1 in 10 of those seconds has a frame over SLOW_MS (its `[slow-frame]` lines between the
# second's `[perf]` lines) after the frame's own pacing sleeps are taken off (the pacer sleeps only when the game is
# ahead of real time, so that part of a long frame is the schedule holding, not a stutter), the flips that are a
# multiple of 10 left out: the window's input script reads the sweep's
# live file (PURE_INPUT_LIVE, the follower's steering) on those, which costs the rig 15 to 25 ms of render time
# whatever the renderer does (946 of the 951 race frames with render over 12 ms in task 077's run), and a player has
# no live file; they are counted and printed apart. And (b) the readback stall
# (`[stalls]` readback, the GPU drains for a framebuffer or depth written back to guest memory) averages at most
# MAX_READBACK_MS a frame over them, weighted by each line's frames. Prints both figures and the worst second either
# way. The cell itself must PASS (the race reached its results screen). And the window must have been on screen (task
# 094, tools/purelib/logs.py's window guard, the rule tools/display_rate_check.sh --audio judges its run by): a covered
# window, one on another Space or on a display asleep runs without vsync (task 091), so its race measures nothing. The
# sweep's unpaced menus (the `[perf]` seconds before the paced flip, their first two left out) present at most the
# display's refresh a second when vsync holds the window; the run FAILs as `the window was not on screen` when their
# last three (with PURE_DISPLAY_RATE=1, the race load's) present more than SCREEN_HELD (1.5) times the refresh the
# `[perf]` lines name (with PURE_DISPLAY_RATE=1, the race's `[pure] display rate` line's), or name none. Waits up to
# 600 s while another PureNative runs (one game at a time). Prints `stutter_check: PASS ...` or `stutter_check: FAIL
# ...` last; exit 0 only on PASS.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

SLOW_MS=25              # a frame over this misses the race's 60 fps budget by more than half a frame
MAX_SLOW_FRACTION=0.1   # (a): seconds with such a frame, at most 1 in 10
MAX_READBACK_MS=2.0     # (b): the readback stall, ms a frame

SHELL_NAME=$(window_shell)
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
pick_backend stutter_check "metal vulkan" "a window: the check measures wall time"
OUT=${OUT:-out/stutter_check/$BACKEND-$SHELL_NAME}
need_game

rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
echo "stutter_check: shell $SHELL_NAME, backend $BACKEND, out $OUT"

wait_game stutter_check || exit 2
t0=$SECONDS
FRAMES=()
[ "${PURE_DISPLAY_RATE:-0}" = 1 ] && FRAMES=(--frames 26000)
PURE_PERF=log PURE_TRACE_STALLS=1 PURE_TRACE_STALLS_MS=$SLOW_MS PURE_NO_AUDIO=0 PURE_SIXTY_FPS=1 \
  PURE_SMOOTH_FLASHES=1 PURE_TEXTURE_DETAIL=1 PURE_SPRITE_UPSCALE=0 \
  python3 tools/campaign_sweep.py single_race vineta_k --no-damage --out "$OUT/race" --shell "$SHELL_NAME" \
  --backend "$BACKEND" ${FRAMES[@]+"${FRAMES[@]}"} > "$OUT/race.stdout" 2>&1
echo "stutter_check: campaign_sweep exit $?, $((SECONDS - t0)) s, log $OUT/race/single_race-vineta_k.log"

python3 - "$OUT" $SLOW_MS $MAX_SLOW_FRACTION $MAX_READBACK_MS <<'EOF' | tee "$OUT/summary.txt"
import os, sys
sys.path.insert(0, "tools")
from purelib.logs import PACED_RE, perf, slow_frame, stalls, sweep_result, window_guard  # the readers, the guard

out = sys.argv[1]
slow_ms, max_fraction, max_readback = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
# slow_frame() takes the frame's own pacing sleeps off: the pacer sleeps only when the game is AHEAD of real time,
# so that part of a long frame is the schedule holding, not a stutter a player feels. (a) judges the frame without it
# (the review of task 077: the realign frame after each live-file read was half the FAILs).
POLL = 10  # the input script reads PURE_INPUT_LIVE on flips that are a multiple of this (host/ui/input_script.cpp)

outcome = sweep_result(os.path.join(out, "race.stdout"), "single_race-vineta_k")["outcome"]
log = os.path.join(out, "race", "single_race-vineta_k.log")
paced, seconds, frames, readback, pending, polls, guard = None, [], 0, 0.0, [], [], None
if os.path.exists(log):
    guard = window_guard(log)
    with open(log, errors="replace") as f:
        for line in f:
            if paced is None:
                m = PACED_RE.match(line)
                if m:
                    paced = int(m[1])
                continue
            m = slow_frame(line)
            if m:
                flip, ms = m
                if flip % POLL == 0:
                    polls.append(ms)
                else:
                    pending.append((ms, flip))
                continue
            p = perf(line)
            if p:
                worst_slow = max(pending, default=None)
                seconds.append((len(seconds) + 1, p["frame_avg"], p["frame_max"], worst_slow))
                pending = []
                continue
            st = stalls(line)
            if st:
                frames += st[0]
                readback += st[1] * st[0]
fails = []
if outcome != "PASS":
    fails.append(f"the race cell {outcome or 'has no outcome'}")
if paced is None:
    fails.append("no `[pure] paced from frame` line")
# The window guard (tools/purelib/logs.py, display_rate_check.sh --audio's rule): the sweep's unpaced menus present
# at most SCREEN_HELD times the display's refresh a second when vsync held the window on screen; a covered window
# runs the race without vsync and its frames measure nothing (task 091).
if guard is not None and not guard["shown"]:
    fails.append(guard["problem"])
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
if guard is not None:
    print(f"the window on screen: {'yes' if guard['shown'] else 'no'} (unpaced presents a second judged: "
          f"{guard['judged'] or '-'}, the display {guard['hz'] or '-'} Hz)")
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
