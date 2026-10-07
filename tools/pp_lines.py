#!/opt/homebrew/bin/python3
"""Record the AI racing lines of a Single Race in PPSSPP, or take them from a port log: the steering source for
tracks nobody has driven.

  tools/pp_lines.py TRACK_NAME [--downs N] [--race-seconds S] [--out CSV] [--pad ITEMS] [--dump BIN] [--debug-port P]
  tools/pp_lines.py --port LOG [--out LINE_CSV] [--samples CSV] [--ships leader|ai|player] [--near M] [--compare LINE_CSV]

Boots disc.iso in PPSSPPSDL through tools/ppsspp/ppsspp_ctl.py (used as a library; hardware renderer, sound off,
the ini put back afterwards), plays tools/ppsspp/routes/frontend.txt and vineta_k_start.txt with N DOWN presses
on TRACK SELECTION (docs/tracks.md; 0 is Vineta K), lets the player's ship idle on the grid while the seven AI
ships race, and samples the race records (task 007: entry k's position at 0x08B72010 + k*0x1C0, velocity -0x20,
lap +0x10, distance along the track +0x18, race clock +0x1C) through `memory.read` while the CPU runs, about 20
times a second of wall time, until S seconds of race clock have passed. Each record carries its own race clock, so
the samples need no frame alignment. Writes CSV rows `usec,ship,clock,x,y,z,vx,vy,vz,dist,lap` (one row per ship
whenever its clock moved) to out/lines/TRACK_NAME.csv. tools/campaign_sweep.py --tune reads it.
--pad ITEMS appends ppsspp_ctl pad items to the route (`6900:CROSS` holds Cross from vblank 6900: the player drives
straight on and meets the walls). --dump BIN also writes each sample's raw race-record block (DUMP_SIZE bytes from
DUMP_START: one stride before entry 0 to the end of entry 7) as a u64 usec and the bytes, for finding fields such
as the shield energy (task 016).

--port LOG (task 032) needs no PPSSPP: LOG is a run of the port with PURE_WATCH_GRID=1, whose `[pure] grid frame N
k=K clock=C pos=x,y,z vel=vx,vy,vz dist=D lap=L` lines give every race record each flip (tools/campaign_sweep.py
--record-line makes such a run and calls this). The samples of the first race (from the first `player object` line
to the next) go to --samples in the PPSSPP recording's CSV form (the flip in the usec column; default LOG with
`.grid.csv`), skipping the player's entry (the index the `player object` line names) and records whose lap field
has bit 16 set (that ship's race is over). The line is made from the AI ship with the most progress over the race
(the furthest along the track, the distance unwrapped at each wrap, at the last flip every AI ship still races):
the mean of its samples, over all its laps, that lie within --near metres (default 15) of its fastest whole pass
of the track coordinate (from one wrap to the next). Not every lap as it is, because a track can fork: on Sinucit
at about 800 m the winner took branches 130 m apart in different laps, and the mean of its laps ran between them,
through the wall; and not the fastest pass alone, because one lap wanders: on Vineta K it lies 5.8 m (mean) from
the PPSSPP line, the mean within 15 m 3.8 m. `--ships ai` takes the mean of all the AI ships over the race instead,
as
tools/campaign_sweep.py --export-line does with a PPSSPP recording): the AiLine of tools/campaign_sweep.py (2 m
bins, gaps interpolated, smoothed over +-3 bins), written to --out as the `dist,x,z` rows a steering table's `follow`
reads (default LOG with `.line.csv`). --compare REF reports how far the new line lies from REF, another `dist,x,z`
line, over the lap: the lateral distance (across REF at the same track distance) and the distance between the two
points of the same track distance, mean and maximum.
"""
import argparse, base64, math, re, struct, sys, time
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
DUMP_START = RECORD_POS - STRIDE
DUMP_SIZE = 9 * STRIDE


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


GRID_RE = re.compile(r"\[pure\] grid frame (\d+) k=(\d+) clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"dist=(\S+) lap=(\d+)")
PLAYER_RE = re.compile(r"\[pure\] ship frame \d+ player object \S+ index (\d+)")
WRAP_M = 1000.0         # a drop in the distance this big is the once-a-lap wrap (tools/campaign_sweep.py)
RACE_OVER = 0x10000     # lap field bit 16: that ship has finished (docs/tracks.md)


def port_samples(log):
    """The first race's grid samples of a port log: ([(frame, k, clock, x, y, z, vx, vy, vz, dist, lap)], player)."""
    rows, player, races = [], 7, 0
    with open(log, errors="replace") as f:
        for line in f:
            m = PLAYER_RE.search(line)
            if m:
                races += 1
                if races > 1:
                    break
                player = int(m[1])
                continue
            m = GRID_RE.search(line)
            if not m or races == 0:
                continue
            frame, k, lap = int(m[1]), int(m[2]), int(m[11])
            vals = [float(v) for v in m.groups()[2:10]]
            if vals[0] <= 0.0 or lap & RACE_OVER:
                continue                # before GO, or that ship's race is over
            rows.append((frame, k, *vals, lap))
    return rows, player


def progress(rows, player):
    """Per AI ship: (how far along the track it is at the last flip every AI ship still races, the flip): the
    distance unwrapped at the track's wrap point (the largest distance seen), counted from the track's 0, so the grid
    order counts. Samples stop at a ship's finish (RACE_OVER), so a later flip would compare finished ships."""
    length = max(r[9] for r in rows)
    state, path = {}, {}
    for r in rows:
        k, frame, d = r[1], r[0], r[9]
        if k == player:
            continue
        w, last = state.get(k, (0, d))
        if d < last - WRAP_M:
            w += 1
        state[k] = (w, d)
        path.setdefault(k, []).append((frame, w * length + d))
    at = min(p[-1][0] for p in path.values())
    return {k: (max(u for f, u in p if f <= at), at) for k, p in path.items()}


def full_passes(rows):
    """One ship's whole passes of the track: (first flip, last flip) of the samples from one wrap of the distance to
    the next, so each covers the track coordinate from 0 to the wrap once."""
    out, start, last = [], None, None
    for r in rows:
        if last is not None and r[9] < last - WRAP_M:
            if start is not None:
                out.append((start, prev))
            start = r[0]
        prev, last = r[0], r[9]
    return out


def port_main(a):
    sys.path.insert(0, str(ROOT / "tools"))
    from campaign_sweep import AiLine   # noqa: E402  (the follower's line, so the two agree)
    log = Path(a.port)
    rows, player = port_samples(log)
    if not rows:
        sys.exit(f"pp_lines: no grid lines of a race in {log} (PURE_WATCH_GRID=1)")
    samples = Path(a.samples) if a.samples else log.with_suffix(".grid.csv")
    with open(samples, "w") as f:
        f.write("usec,ship,clock,x,y,z,vx,vy,vz,dist,lap\n")
        for r in rows:
            f.write(f"{r[0]},{r[1]}," + ",".join(f"{v:.3f}" for v in r[2:10]) + f",{r[10]}\n")
    prog = progress(rows, player)
    for k in sorted(prog):
        print(f"ship {k}: {prog[k][0]:.0f} m along the track at flip {prog[k][1]}")
    span = None
    skip = player                     # AiLine leaves the player's own samples out, unless they are the line
    if a.ships == "player":
        # A human lap (tools/record_lap.sh): the player's samples within --near of the player's fastest whole pass.
        passes = full_passes([r for r in rows if r[1] == player])
        if not passes:
            sys.exit(f"pp_lines: the player (ship {player}) never drove the whole track from one wrap to the next")
        span = min(passes, key=lambda p: p[1] - p[0])
        ships, skip = {player}, -1
        what = (f"ship {player}, the player: its samples within {a.near:g} m of its fastest whole pass of the track "
                f"(flips {span[0]} to {span[1]}, {(span[1] - span[0]) / 60.0:.1f} s; {len(passes)} whole passes)")
    elif a.ships == "leader":
        leader = max(prog, key=lambda k: prog[k][0])
        passes = full_passes([r for r in rows if r[1] == leader])
        if not passes:
            sys.exit(f"pp_lines: ship {leader} never drove the whole track from one wrap to the next")
        span = min(passes, key=lambda p: p[1] - p[0])
        ships = {leader}
        what = (f"ship {leader}, the AI ship with the most progress: its samples within {a.near:g} m of its fastest "
                f"whole pass of the track (flips {span[0]} to {span[1]}, {(span[1] - span[0]) / 60.0:.1f} s; "
                f"{len(passes)} whole passes)")
    else:
        ships, what = set(prog), f"the mean of the AI ships {', '.join(map(str, sorted(prog)))}"
    keep = None
    if span is not None:
        fastest = AiLine(str(samples), player=skip, ships=ships, span=span)

        def keep(d, x, z):
            fx, fz = fastest.at(d)
            return math.hypot(x - fx, z - fz) <= a.near
    line = AiLine(str(samples), player=skip, ships=ships, keep=keep)
    out = Path(a.out) if a.out else log.with_suffix(".line.csv")
    line.export(str(out))
    frames = [r[0] for r in rows]
    print(f"{log}: {len(rows)} samples of flips {min(frames)} to {max(frames)} (player {player}); {what}: "
          f"{line.length:.0f} m, {line.covered:.0%} of the bins sampled -> {out}")
    if a.compare:
        ref = AiLine(str(Path(a.compare)))
        lat, pts = [], []
        for i in range(line.n):
            d = i * line.BIN
            if d >= ref.length:
                break
            x, z = line.x[i], line.z[i]
            rx, rz = ref.at(d)
            lat.append(abs(ref.offset(x, z, d)))
            pts.append(math.hypot(x - rx, z - rz))
        worst = max(range(len(lat)), key=lat.__getitem__)
        print(f"against {a.compare} ({ref.length:.0f} m) over {len(lat)} bins: lateral distance mean "
              f"{sum(lat) / len(lat):.2f} m, max {lat[worst]:.2f} m (at {worst * line.BIN:.0f} m); same-distance "
              f"points mean {sum(pts) / len(pts):.2f} m, max {max(pts):.2f} m")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("track", nargs="?")
    p.add_argument("--port", metavar="LOG", help="make the line from a port log with PURE_WATCH_GRID=1 lines")
    p.add_argument("--samples", help="--port: the samples CSV (default LOG with .grid.csv)")
    p.add_argument("--ships", choices=("leader", "ai", "player"), default="leader")
    p.add_argument("--compare", metavar="LINE_CSV")
    p.add_argument("--near", type=float, default=15.0, help="--port: metres from the leader's fastest pass")
    p.add_argument("--downs", type=int, default=0)
    p.add_argument("--race-seconds", type=float, default=80.0)
    p.add_argument("--out")
    p.add_argument("--debug-port", type=int, default=pc.DEFAULT_PORT, help="PPSSPP's debugger port")
    p.add_argument("--wall-limit", type=float, default=600.0, help="give up after this many seconds of wall time")
    p.add_argument("--pad", default="", help="extra pad items appended to the route")
    p.add_argument("--dump", help="also write the raw race-record block of every sample here")
    a = p.parse_args()
    if a.port:
        return port_main(a)
    if not a.track:
        p.error("TRACK_NAME is needed without --port")
    out = Path(a.out or ROOT / "out" / "lines" / f"{a.track}.csv")
    out.parent.mkdir(parents=True, exist_ok=True)
    script = (ROUTES / "frontend.txt").read_text() + "\n" + (ROUTES / "vineta_k_start.txt").read_text()
    script += "\n" + "\n".join(f"{DOWN_AT + i * DOWN_GAP}:DOWN, {DOWN_AT + i * DOWN_GAP + 8}:"
                               for i in range(a.downs))
    script += "\n" + a.pad
    states = pc.parse_pad_script(script)
    rows = 0
    t0 = time.time()
    with pc.IniSession(False, port=a.debug_port, renderer="hardware", hle_log=False, mute=True, savestate_key=False):
        proc = pc.launch(pc.DEFAULT_ISO)
        dbg = None
        try:
            dbg, _ = pc.connect(a.debug_port, proc.pid, proc)
            pc.wait_boot(dbg)
            dbg.request("replay.time.set", value=1767225600)
            blob = pc.build_replay_blob(states)
            dbg.request("replay.execute", version=1, base64=base64.b64encode(blob).decode())
            dbg.resume()
            last_clock = [None] * 8
            race_start = None
            dump = open(a.dump, "wb") if a.dump else None
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
                    if dump:
                        raw = base64.b64decode(dbg.request("memory.read", address=DUMP_START,
                                                           size=DUMP_SIZE)["base64"])
                        dump.write(struct.pack("<Q", u) + raw)
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
            if dump:
                dump.close()
            pc.log(f"{rows} rows -> {out}; wall {time.time() - t0:.0f}s")
        finally:
            if dbg:
                dbg.close()
            clean = pc.stop_process(proc.pid, proc)
            pc.log("PPSSPP quit cleanly" if clean else "PPSSPP had to be killed")


if __name__ == "__main__":
    main()
