#!/bin/bash
# The SAS reverb check (task 043): plays the Free Play pause route headless with PURE_AUDIO_WAV and compares the
# sound's decay after the pause with PPSSPP's audio dump of the same route (ref/audio/free_play_pause.wav).
#   tools/sas_reverb_check.sh [--out DIR] [--env KEY=VAL ...] [--allow-parallel]
#   --out      the route, the run's log and WAVs, and summary.txt (default out/sas_reverb; its files are replaced).
#   --env      extra environment for the run (tools/run_boot.py --env), e.g. --env PURE_NO_REVERB=1 for the port
#              without the reverb (the check FAILs: the sound stops dead) or --env PURE_SAS_REVERB_SPU_RATE=1.
#   --allow-parallel  start even while another PureNative runs (one game at a time otherwise, as frame_regress.sh).
# The route, both sides from an empty memory stick: the port's main_menu.txt and free_play.txt without its Cross hold
# (the ship idles on Vineta K's grid), then START at flip 16700, as task 041 ran it (docs/fidelity.md, "Difference
# 8"); PPSSPP's tools/ppsspp/routes/frontend.txt, free_play_start.txt and free_play_idle_end.txt (START at vblank
# 28800). The reference is taken once (about 8 minutes; ref/README.md has its SHA-256):
#   python3 tools/ppsspp/ppsspp_ctl.py run --pad-file tools/ppsspp/routes/frontend.txt \
#     --pad-file tools/ppsspp/routes/free_play_start.txt --pad-file tools/ppsspp/routes/free_play_idle_end.txt \
#     --until 29700 --renderer hardware --dump-audio ref/audio/free_play_pause.wav
# At the pause the game stops the music, holds the effects on one level for 70 to 110 ms, then keys them off; what
# sounds after that is the reverb's tail. In each mix the tail starts at the first 10 ms block after START whose RMS
# is under 0.6 of the median of the five blocks before it, once those five are all under 0.7 of the median level of
# the 0.5 s before START (the music has stopped, so the drop is the held effects' end). The check compares the RMS
# of five 100 ms steps from there: PASS when each of the port's is non-zero and within a factor of 2 of PPSSPP's.
# START's time: PPSSPP's vblank 28800 at its vblank timing (the driver's report: the first vblank at 15951.83 us,
# 16683.33 us apart); the port's, the virtual time of the first sceSas call logged after the script's START (the run
# traces __sceSasRevEVOL, which the race calls every frame).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD

OUT=out/sas_reverb
ENVS=()
PARALLEL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift 2 ;;
    --env) ENVS+=(--env "$2"); shift 2 ;;
    --allow-parallel) PARALLEL=1; shift ;;
    *) echo "usage: tools/sas_reverb_check.sh [--out DIR] [--env KEY=VAL ...] [--allow-parallel]"; exit 2 ;;
  esac
done

REF=ref/audio/free_play_pause.wav
PRESS_FLIP=16700
FRAMES=16800
[ -f "$REF" ] || { echo "sas_reverb_check: $REF missing (PPSSPP's dump; copy it from the main checkout's ref/audio/ or take it as the header says)"; exit 2; }
[ -x build/arm64/bin/PureNative ] || { echo "sas_reverb_check: build/arm64/bin/PureNative missing (tools/build.sh profile)"; exit 2; }
if [ "$PARALLEL" = 0 ]; then
  others=$(python3 -c 'import sys; sys.path.insert(0, "tools"); import run_boot
print("\n".join(f"  pid {p}: {c}" for p, c in run_boot.other_games()))')
  if [ -n "$others" ]; then
    echo "sas_reverb_check: another PureNative is running; one game at a time (--allow-parallel starts anyway):"
    echo "$others"
    exit 2
  fi
fi

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/game"
rm -f "$OUT"/port.wav* "$OUT/run.log" "$OUT/run.stdout" "$OUT/route.txt" "$OUT/summary.txt"
mkdir -p "$OUT/game/ms0/PSP/SAVEDATA"
ln -s "$ROOT/game/EBOOT.ELF" "$OUT/game/EBOOT.ELF"
ln -s "$ROOT/game/disc.iso" "$OUT/game/disc.iso"

# The route: main_menu.txt without its shot, free_play.txt without the Cross hold at 5900, then the pause menu's END
# SESSION as the sweep picks it (the run ends before DOWN, DOWN, Cross matter).
{
  grep -Ev '^[[:space:]]*(#|$)|:[[:space:]]*shot([[:space:]]|$)' config/pad_scripts/main_menu.txt
  grep -Ev '^[[:space:]]*(#|$)|^5900:' config/pad_scripts/free_play.txt
  printf '%s:pad start\n%s:pad dpdown\n%s:pad dpdown\n%s:pad a\n' "$PRESS_FLIP" $((PRESS_FLIP + 40)) $((PRESS_FLIP + 80)) $((PRESS_FLIP + 120))
} > "$OUT/route.txt"

echo "sas_reverb_check: Free Play pause route, START at flip $PRESS_FLIP, to flip $FRAMES (headless) ..."
t0=$SECONDS
python3 tools/run_boot.py --shell headless --script "$OUT/route.txt" --frames "$FRAMES" --seconds 300 --max-lines 200000 \
  --data-dir out/data/sas_reverb --env PURE_GAME_DIR="$OUT/game" --env PURE_AUDIO_WAV="$OUT/port.wav" \
  --env PURE_TRACE_CALLS=sceSasCore:0xD5A229C9 ${ENVS[@]+"${ENVS[@]}"} "$OUT/run.log" > "$OUT/run.stdout" 2>&1
rc=$?
echo "sas_reverb_check: run_boot exit $rc, $((SECONDS - t0)) s, log $OUT/run.log"
grep -q "^\[pure\] exit at frame $FRAMES" "$OUT/run.log" || { echo "sas_reverb_check: FAIL (the run did not reach flip $FRAMES)"; exit 1; }

python3 - "$OUT/run.log" "$OUT/port.wav" "$REF" "$PRESS_FLIP" "$OUT/summary.txt" <<'EOF'
import math, re, sys, wave
from array import array

log, port_wav, ref_wav, press_flip, summary = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
BLOCK = 0.010      # s
STEP = 0.100       # s
STEPS = 5          # the checked steps: the first 0.5 s
SHOWN = 10         # steps printed: the first second
FACTOR = 2.0
PP_PRESS = (15951.83 + (28800 - 1) * 16683.333333) / 1e6     # PPSSPP's vblank 28800, s

lines = []
def out(text=""):
    print(text)
    lines.append(text)

def port_press():
    seen = False
    with open(log, errors="replace") as f:
        for line in f:
            if not seen:
                seen = line.startswith(f"[script] frame {press_flip}: pad start")
                continue
            m = re.search(r"^\[call\] .* t=(\d+)", line)
            if m:
                return int(m.group(1)) / 1e6
    return None

def blocks(path, start, seconds):
    w = wave.open(path, "rb")
    rate, channels = w.getframerate(), w.getnchannels()
    w.setpos(max(0, int(round(start * rate))))
    data = array("h")
    data.frombytes(w.readframes(int(round(seconds * rate))))
    n = int(round(BLOCK * rate)) * channels
    return [math.sqrt(math.sumprod(data[i:i + n], data[i:i + n]) / n) for i in range(0, len(data) - n + 1, n)]

def rms_of(levels):
    return math.sqrt(sum(v * v for v in levels) / len(levels)) if levels else 0.0

def tail_start(path, press):
    """The first 10 ms block after START under 0.6 of the median of the five before it, when those five are all under
    0.7 of the median level of the 0.5 s before START (the music has stopped: what drops then is the effects' held
    level); returns (time, the blocks from there, the 0.1 s of blocks before it)."""
    lead = 1.0
    b = blocks(path, press - lead, lead + 3.0)
    first = int(round(lead / BLOCK))
    playing = sorted(b[first - 50:first])[25]
    for i in range(first, len(b)):
        if max(b[i - 5:i]) < 0.7 * playing and b[i] < 0.6 * sorted(b[i - 5:i])[2]:
            return press - lead + i * BLOCK, b[i:], b[i - 10:i]
    return None, [], []

port_t = port_press()
if port_t is None:
    out(f"sas_reverb_check: FAIL (no sceSas call logged after the script's START at flip {press_flip})")
    sys.exit(1)
results = {}
for name, path, press in (("port", port_wav, port_t), ("PPSSPP", ref_wav, PP_PRESS)):
    t, tail, lead_in = tail_start(path, press)
    if t is None:
        out(f"sas_reverb_check: FAIL (no end of the effects found in the {name} mix within 3 s of START)")
        sys.exit(1)
    per = int(round(STEP / BLOCK))
    steps = [rms_of(tail[k * per:(k + 1) * per]) for k in range(SHOWN)]
    results[name] = (press, t, steps, lead_in)

out("sas_reverb_check: the sound after the Free Play pause, port against PPSSPP's dump")
for name in ("port", "PPSSPP"):
    press, t, steps, lead_in = results[name]
    out(f"  {name:6s} START at {press:.3f} s, the effects end at {t:.3f} s ({(t - press) * 1000:.0f} ms later); "
        f"the 100 ms before: RMS {rms_of(lead_in):.0f}")
out("")
out("  step (ms)    port   PPSSPP   port/PPSSPP  result")
failed = 0
for k in range(SHOWN):
    a, b = results["port"][2][k], results["PPSSPP"][2][k]
    ratio = a / b if b > 0 else float("inf")
    if k < STEPS:
        ok = a > 0 and b > 0 and 1 / FACTOR <= ratio <= FACTOR
        failed += not ok
        verdict = "ok" if ok else ("FAIL (zero)" if a == 0 else "FAIL")
    else:
        verdict = "(shown only)"
    out(f"  {k * 100:3d}-{k * 100 + 100:<4d} {a:8.0f} {b:8.0f}   {ratio:8.2f}     {verdict}")
out("")
if failed:
    out(f"sas_reverb_check: FAIL ({failed} of the first {STEPS} steps outside a factor of {FACTOR:g} of PPSSPP's, or zero)")
else:
    out(f"sas_reverb_check: PASS (the first {STEPS} steps within a factor of {FACTOR:g} of PPSSPP's, none zero)")
with open(summary, "w") as f:
    f.write("\n".join(lines) + "\n")
sys.exit(1 if failed else 0)
EOF
