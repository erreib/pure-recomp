#!/opt/homebrew/bin/python3
"""Record the AI racing lines of a Single Race in PPSSPP: the steering source for tracks nobody has driven.

  tools/pp_lines.py TRACK_NAME [--downs N] [--race-seconds S] [--out CSV]

Boots disc.iso in PPSSPPSDL through tools/ppsspp/ppsspp_ctl.py (used as a library; hardware renderer, sound off,
the ini put back afterwards), plays tools/ppsspp/routes/frontend.txt and vineta_k_start.txt with N DOWN presses
on TRACK SELECTION (docs/tracks.md; 0 is Vineta K), lets the player's ship idle on the grid while the seven AI
ships race, and samples the race records (task 007: entry k's position at 0x08B72010 + k*0x1C0, velocity -0x20,
lap +0x10, distance along the track +0x18, race clock +0x1C) through `memory.read` while the CPU runs, about 20
times a second of wall time, until S seconds of race clock have passed. Each record carries its own race clock, so
the samples need no frame alignment. Writes CSV rows `usec,ship,clock,x,y,z,vx,vy,vz,dist,lap` (one row per ship
whenever its clock moved) to out/lines/TRACK_NAME.csv. tools/campaign_sweep.py --tune reads it.
"""
import argparse, base64, struct, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "ppsspp"))
import ppsspp_ctl as pc  # noqa: E402

RECORD_POS = 0x08B72010
STRIDE = 0x1C0
BLOCK_START = RECORD_POS - 0x20
BLOCK_SIZE = 7 * STRIDE + 0x40
ROUTES = ROOT / "tools" / "ppsspp" / "routes"
DOWN_AT = 6400          # TRACK SELECTION is up from about 6350; the track is confirmed with CROSS at 6500
DOWN_GAP = 30


def records(data):
    out = []
    for k in range(8):
        o = k * STRIDE + 0x20
        vx, vy, vz = struct.unpack_from("<3f", data, o - 0x20)
        x, y, z = struct.unpack_from("<3f", data, o)
        lap, _idx = struct.unpack_from("<2I", data, o + 0x10)
        dist, clock = struct.unpack_from("<2f", data, o + 0x18)
        out.append((k, clock, x, y, z, vx, vy, vz, dist, lap))
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("track")
    p.add_argument("--downs", type=int, default=0)
    p.add_argument("--race-seconds", type=float, default=80.0)
    p.add_argument("--out")
    p.add_argument("--port", type=int, default=pc.DEFAULT_PORT)
    p.add_argument("--wall-limit", type=float, default=600.0, help="give up after this many seconds of wall time")
    a = p.parse_args()
    out = Path(a.out or ROOT / "out" / "lines" / f"{a.track}.csv")
    out.parent.mkdir(parents=True, exist_ok=True)
    script = (ROUTES / "frontend.txt").read_text() + "\n" + (ROUTES / "vineta_k_start.txt").read_text()
    script += "\n" + "\n".join(f"{DOWN_AT + i * DOWN_GAP}:DOWN, {DOWN_AT + i * DOWN_GAP + 8}:"
                               for i in range(a.downs))
    states = pc.parse_pad_script(script)
    rows = 0
    t0 = time.time()
    with pc.IniSession(False, port=a.port, renderer="hardware", hle_log=False, mute=True, savestate_key=False):
        proc = pc.launch(pc.DEFAULT_ISO)
        dbg = None
        try:
            dbg, _ = pc.connect(a.port, proc.pid, proc)
            pc.wait_boot(dbg)
            dbg.request("replay.time.set", value=1767225600)
            blob = pc.build_replay_blob(states)
            dbg.request("replay.execute", version=1, base64=base64.b64encode(blob).decode())
            dbg.resume()
            last_clock = [None] * 8
            race_start = None
            with open(out, "w") as f:
                f.write("usec,ship,clock,x,y,z,vx,vy,vz,dist,lap\n")
                while True:
                    if time.time() - t0 > a.wall_limit:
                        raise RuntimeError(f"wall-clock limit {a.wall_limit:.0f}s reached")
                    u = dbg.usec()
                    frame = pc.frame_at_us(u)
                    if frame < 6900:
                        time.sleep(1.0)
                        continue
                    data = base64.b64decode(dbg.request("memory.read", address=BLOCK_START,
                                                        size=BLOCK_SIZE)["base64"])
                    for r in records(data):
                        k, clock = r[0], r[1]
                        if clock <= 0.0 or clock == last_clock[k]:
                            continue
                        last_clock[k] = clock
                        f.write(f"{u},{k}," + ",".join(f"{v:.3f}" for v in r[1:9]) + f",{r[9]}\n")
                        rows += 1
                    clocks = [c for c in last_clock if c is not None]
                    if clocks and race_start is None:
                        race_start = frame
                        pc.log(f"race clock running from frame {frame:.0f}; wall {time.time() - t0:.0f}s")
                    if clocks and max(clocks) >= a.race_seconds:
                        break
                    if frame > 7600 and race_start is None:
                        raise RuntimeError(f"no race clock by frame {frame:.0f}: the route did not reach a race")
                    time.sleep(0.05)
            pc.log(f"{rows} rows -> {out}; wall {time.time() - t0:.0f}s")
        finally:
            if dbg:
                dbg.close()
            clean = pc.stop_process(proc.pid, proc)
            pc.log("PPSSPP quit cleanly" if clean else "PPSSPP had to be killed")


if __name__ == "__main__":
    main()
