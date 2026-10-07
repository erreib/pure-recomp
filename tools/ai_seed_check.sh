#!/bin/bash
# tools/ai_seed_check.sh [--tracks T[,T...]] [--retake] [--out DIR]   (task 046)
#
# The scorecard's trajectory measure with the race clock pinned (docs/fidelity.md difference 13): the AI ships of a
# Single Race start from two srand() seeds the game takes from clock readings at the TEAM SELECTION confirm, and the
# race then runs on the frame times the game measures each frame, so the port's AI only races PPSSPP's when it reads
# PPSSPP's clock. For each circuit (default: vineta_k) this
#   1. takes PPSSPP's race clock into ref/race_clock/<track>.txt when it is not there (or with --retake): the
#      scorecard's reference route for the circuit in PPSSPP through the driver, with log-only breakpoints on srand()
#      (FUN_088E0558: the seed and the caller) and on sceKernelGetSystemTimeWide (the frame timer's calls), until the
#      player's race clock passes 20.6 s; the player's race record at the end is checked against the reference
#      ref/scorecard/trajectories/<track>.csv (task 044's), so the clock is the reference race's (PPSSPP repeats a
#      race exactly); about 2.5 minutes of PPSSPP a circuit, which must be free (the tool waits as the scorecard does);
#   2. runs `tools/scorecard.py --only trajectories --tracks ...` with SCORECARD_RACE_CLOCK=ref/race_clock, which
#      gives each port run PURE_TEST_RACE_CLOCK (src/profile/pure_profile.cpp);
#   3. PASSes when every circuit's player row and AI row are faithful (under 1.5 m over 20 s).
# The references themselves (ref/scorecard/) are read, never retaken. Output in out/ai_seed_check/ by default.
set -u
cd "$(dirname "$0")/.." || exit 2
. tools/env.sh
TRACKS=vineta_k
RETAKE=0
OUT=out/ai_seed_check
while [ $# -gt 0 ]; do
  case "$1" in
    --tracks) TRACKS="$2"; shift 2 ;;
    --retake) RETAKE=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ai_seed_check: unknown argument $1"; exit 2 ;;
  esac
done
mkdir -p ref/race_clock "$OUT"

python3 - "$TRACKS" "$RETAKE" <<'PY' || exit 1
"""Takes PPSSPP's race clock for each circuit that lacks one (tools/ai_seed_check.sh, step 1)."""
import base64, math, re, struct, sys, time
from pathlib import Path
ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "ppsspp"))
import ppsspp_ctl as pc
import scorecard as sc
import pp_lines as pl

SRAND = 0x088E0558
FROM_TEAM_PICK, FROM_BILLBOARDS, FRAME_TIMER = 0x0880E160, 0x08860150, 0x08804428
UNTIL = 20.6


def take(track, path):
    files, hold = sc.pp_routes(track)
    script = ("\n".join((sc.PP_ROUTES / f).read_text() for f in files)
              + f"\n{hold}:CROSS\n{hold + sc.PP_HOLD_VBLANKS}:\n")
    states = pc.parse_pad_script(script)
    if not sc.wait_ppsspp():
        raise RuntimeError("PPSSPP did not become free")
    log = path.with_suffix(".ppsspp.log")
    rec = pl.RECORD_POS + sc.PLAYER * pl.STRIDE
    end, clock = None, 0.0
    t0 = time.time()
    with pc.IniSession(False, port=pc.DEFAULT_PORT, renderer="hardware", hle_log=False, mute=True,
                       savestate_key=False):
        proc = pc.launch(pc.DEFAULT_ISO, str(log))
        dbg = None
        try:
            dbg, _ = pc.connect(pc.DEFAULT_PORT, proc.pid, proc)
            pc.wait_boot(dbg)
            dbg.request("replay.time.set", value=sc.RTC)
            dbg.request("replay.execute", version=1, base64=base64.b64encode(pc.build_replay_blob(states)).decode())
            dbg.request("cpu.breakpoint.add", address=SRAND, enabled=False, log=True,
                        logFormat="SRAND {usec:d} a0 {a0:x} ra {ra:x}")
            dbg.request("cpu.breakpoint.add", address=dbg.symbol("zz_sceKernelGetSystemTimeWide"), enabled=False,
                        log=True, logFormat="GSTW {usec:d} ra {ra:x}")
            dbg.resume()
            while True:
                if time.time() - t0 > 1200:
                    raise RuntimeError("wall-clock limit reached")
                frame = pc.frame_at_us(dbg.usec())
                if frame < hold - 30:
                    time.sleep(0.5)
                    continue
                a = dbg.request("memory.read", address=rec, size=0x20)["base64"]
                b = dbg.request("memory.read", address=rec, size=0x20)["base64"]
                if a == b:
                    x, y, z = struct.unpack_from("<3f", base64.b64decode(a), 0)
                    clock = struct.unpack_from("<f", base64.b64decode(a), 0x1C)[0]
                    if clock >= UNTIL:
                        end = (clock, x, y, z)
                        break
                if frame > hold + 1500 and end is None and clock <= 0.0:
                    raise RuntimeError("no race clock: the route did not reach a race")
                time.sleep(0.1)
        finally:
            if dbg:
                dbg.close()
            pc.stop_process(proc.pid, proc)
    team = race = last_before = None
    frames = []
    for line in open(log, errors="replace"):
        m = re.search(r"SRAND (\d+) a0 ([0-9a-f]+) ra ([0-9a-f]+)", line)
        if m:
            ra = int(m[3], 16)
            if ra == FROM_TEAM_PICK:
                team = int(m[2], 16)
            elif ra == FROM_BILLBOARDS:
                race = int(m[2], 16)
                frames = [last_before]
            continue
        m = re.search(r"GSTW (\d+) ra ([0-9a-f]+)", line)
        if m and int(m[2], 16) == FRAME_TIMER:
            if race is None:
                last_before = int(m[1])
            else:
                frames.append(int(m[1]))
    if team is None or race is None or last_before is None or len(frames) < 100:
        raise RuntimeError(f"the log lacks the seeds or the frame times (team {team}, race {race}, {len(frames)} frames)")
    # The same race as the reference? The player's position at the end against the reference at that clock.
    ref = sc.read_pp_samples(sc.REF / "trajectories" / f"{track}.csv").get(sc.PLAYER, [])
    clocks = [p[0] for p in ref]
    q = sc.interp(ref, clocks, end[0])
    off = math.dist(end[1:], q) if q else None
    if off is None or off > 0.05:
        raise RuntimeError(f"the player at {end[0]:.3f} s is {off} m from the reference: not the reference's race")
    unlocked = 0 if track in sc.cs.ALPHA else 1
    with open(path, "w") as f:
        f.write(f"# PPSSPP's race clock for {track} (tools/ai_seed_check.sh, {time.strftime('%Y-%m-%d %H:%M')}): the\n"
                f"# reference route {', '.join(files)}, Cross from vblank {hold}; the player at {end[0]:.3f} s is "
                f"{off:.4f} m from ref/scorecard/trajectories/{track}.csv\n")
        f.write(f"team 0x{team:08X}\nrace 0x{race:08X}\nunlocked {unlocked}\n")
        f.writelines(f"frame {u}\n" for u in frames)
    log.unlink(missing_ok=True)
    print(f"[ai_seed_check] {track}: race clock taken in {time.time() - t0:.0f} s: team seed 0x{team:08X}, race seed "
          f"0x{race:08X}, {len(frames) - 1} frame times; the player at {end[0]:.2f} s is {off:.4f} m from the "
          f"reference", flush=True)


for track in sys.argv[1].split(","):
    if track not in sc.TRACKS:
        sys.exit(f"ai_seed_check: unknown track {track}")
    path = ROOT / "ref" / "race_clock" / f"{track}.txt"
    if path.exists() and sys.argv[2] != "1":
        print(f"[ai_seed_check] {track}: race clock {path.relative_to(ROOT)}", flush=True)
        continue
    take(track, path)
PY

SCORECARD_RACE_CLOCK=ref/race_clock python3 tools/scorecard.py --only trajectories --tracks "$TRACKS" --out "$OUT" \
  > "$OUT/scorecard.stdout" 2>&1
rc=$?
tail -3 "$OUT/scorecard.stdout"
[ $rc -eq 0 ] || { echo "ai_seed_check: FAIL (the scorecard exited $rc)"; exit 1; }

python3 - "$OUT/scorecard.json" "$TRACKS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
rows = d["categories"]["trajectories"]["rows"]
ok = True
for track in sys.argv[2].split(","):
    mine = [r for r in rows if r["measure"].split(":")[0].lower().replace(" ", "_") == track]
    if len(mine) != 2:
        print(f"ai_seed_check: {track}: expected a player row and an AI row, found {len(mine)}")
        ok = False
        continue
    for r in mine:
        who = "AI    " if "AI ships" in r["measure"] else "player"
        print(f"  {track:17} {who} {r['grade']:9} {r['port']}; largest {r['difference']}")
        ok &= r["grade"] == "faithful"
print("ai_seed_check: PASS" if ok else "ai_seed_check: FAIL")
sys.exit(0 if ok else 1)
PY
