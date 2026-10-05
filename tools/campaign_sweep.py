#!/usr/bin/env python3
"""Campaign sweep: each (mode, track) cell from a cold boot to the race's results screen under scripted driving.

  tools/campaign_sweep.py [MODE [TRACK ...]] [--frames N] [--stall S] [--drive FILE] [--shots-every N] [--list]

MODE is a row of MODES (default single_race); TRACK names a track of the mode (default: all of them, in menu
order). Each cell is one run of tools/run_boot.py, strict (PURE_STRICT_HLE=1) with PSPRECOMP_NO_INTERPRETER=1 and
PURE_WATCH_SHIP=1, windowed (the input script drives the renderer's virtual pad). Its input script is
  config/pad_scripts/main_menu.txt   cold boot to MAIN MENU (shot steps dropped)
  the mode's race route              MAIN MENU to the race, the track picked by N DOWN presses (docs/tracks.md),
                                     Cross held from the countdown for the whole budget
  config/pad_scripts/drive/<track>.txt   the steering table: `frame:axis leftx V` steps (frames of the same run)
Every cell starts from an empty memory stick: the run's game directory is out/sweep/game (EBOOT.ELF and disc.iso
linked to game/, ms0/ emptied before each cell), since the menu route creates a profile and answers its prompts.

--frames N is the race budget: the run stops at flip THROTTLE + N, THROTTLE being the race route's Cross-hold step
(6100), since the menu route alone takes that long (a three-lap race at Vector is 150 s, 9000 flips, more).

While the run goes the tool reads the log and the `[pure] ship` lines (race clock, distance along the track, lap):
  - finished: the lap counter passes the mode's lap count (the player crossed the line on the last lap), then the
    tool asks for a screenshot every 60 flips through PURE_INPUT_LIVE and waits for the results screen: the race
    HUD gone (the top-left time label is no longer drawn: tools/imgdiff.py region variance of the HUD time region
    against the race's own) and the screen stable (two shots in a row equal within imgdiff tolerance). That is PASS;
    the tool then closes the window (`quit`).
  - stalled: no progress along the track (distance up by 5 m, or a new lap) for --stall seconds of race clock (a
    wall stop shows as speed 0 with the distance constant): FAIL, the window is closed.
  - halted: a `[hle-stub]`, `unsupported` or `Runtime stopped` line other than the frame exit and our own quit.
  - no race: no race clock 1800 flips after the Cross-hold step means the menu route broke; the sweep stops there.
Outputs: out/sweep/<mode>-<track>.log (run_boot's log), out/sweep/<mode>-<track>.png (the results screen, or the
last frame captured), out/sweep/<mode>-<track>/ (the live shots, BMP and PNG), and out/sweep/summary.txt, a table
with one row per cell ever run (the latest outcome replaces the cell's earlier row). Exit 0 when every cell of
this invocation passed, 1 otherwise, 2 on bad arguments.
--drive FILE uses FILE as the steering table (one track only; for tuning). --shots-every N also takes a live shot
every N flips from the race start (named t<frame>), for tuning.
"""
import argparse, datetime, os, re, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

MENU_ROUTE = "config/pad_scripts/main_menu.txt"
DRIVE_DIR = "config/pad_scripts/drive"
OUT = "out/sweep"

# The modes and their race routes. `throttle` is the frame of the route's Cross-hold step (the budget counts from
# it); `downs_at` is where the DOWN presses that pick the track go, `downs_gap` apart; `tracks` lists the track menu
# in order (the index is the number of DOWN presses; docs/tracks.md).
ALPHA = ["vineta_k", "modesto_heights", "chenghou_project", "blue_ridge"]
MODES = {
    "single_race": {"route": "config/pad_scripts/single_race.txt", "laps": 3, "throttle": 6100,
                    "downs_at": 5380, "downs_gap": 30, "tracks": ALPHA},
}

SHIP_RE = re.compile(r"\[pure\] ship frame (\d+) t=\d+ clock=(\S+) pos=(\S+),(\S+),(\S+) vel=\S+ kmh=(\S+) "
                     r"dist=(\S+) lap=(\d+)")
SCRIPT_RE = re.compile(r"\[script\] frame (\d+): shot (\S+)")
HALT_RE = re.compile(r"\[hle-stub\]|unsupported|Runtime stopped")
FRAME_EXIT = "[pure] exit at frame"

HUD_TIME = (4, 2, 110, 28)      # the race HUD's time readout, top left, in 480x272 PSP pixels ("CURRENT" + digits)
SHOT_EVERY = 60                 # flips between the live shots once the race is finished
PROGRESS_M = 5.0                # metres along the track that count as progress for the stall rule
NO_RACE_FLIPS = 1800            # flips after the Cross-hold step with no race clock: the route broke


def read_steps(path, drop_shots=True):
    """The `frame:action` lines of a pad script (comments and blank lines dropped)."""
    steps = []
    with open(os.path.join(ROOT, path)) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line or ":" not in line:
                continue
            frame, action = line.split(":", 1)
            if drop_shots and action.strip().startswith("shot"):
                continue
            steps.append((int(frame), action.strip()))
    return steps


def build_script(mode, track, drive, budget):
    m = MODES[mode]
    steps = read_steps(MENU_ROUTE) + read_steps(m["route"])
    downs = m["tracks"].index(track)
    steps += [(m["downs_at"] + k * m["downs_gap"], "pad dpdown") for k in range(downs)]
    steps.append((m["downs_at"] + max(downs, 1) * m["downs_gap"], f"shot {mode}-{track}-menu"))
    # The race route's throttle step holds Cross for the whole budget.
    steps = [(f, f"pad a {budget}") if f == m["throttle"] and a.startswith("pad a") else (f, a) for f, a in steps]
    steps += read_steps(drive, drop_shots=False)
    steps.sort(key=lambda s: s[0])
    return steps


class Race:
    """What the `[pure] ship` lines say so far."""

    def __init__(self, laps):
        self.laps = laps
        self.started = False
        self.frame = 0
        self.clock = 0.0
        self.lap = 0
        self.max_lap = 0
        self.dist = 0.0
        self.line = ""
        self.best = (0, 0.0)          # (lap, distance) of the last progress
        self.best_clock = 0.0         # race clock at the last progress
        self.finished_frame = None    # first flip with the lap counter past the last lap

    def feed(self, m, line):
        self.frame = int(m[1])
        clock, dist, lap = float(m[2]), float(m[7]), int(m[8])
        self.line = line
        if clock > 0.0 and not self.started:
            self.started = True
            self.best, self.best_clock = (lap, dist), clock
        self.clock, self.dist, self.lap = clock, dist, lap
        self.max_lap = max(self.max_lap, lap)
        # The distance is a track coordinate that wraps to 0 once a lap (docs/tracks.md): a big drop is progress.
        if self.started and (lap > self.best[0] or (lap == self.best[0] and (dist > self.best[1] + PROGRESS_M
                                                                            or dist < self.best[1] - 1000.0))):
            self.best, self.best_clock = (lap, dist), clock
        if self.finished_frame is None and self.started and lap > self.laps:
            self.finished_frame = self.frame

    def stalled_for(self):
        return self.clock - self.best_clock if self.started else 0.0


def hud_variance(path):
    """Largest per-channel variance of the HUD time region (tools/imgdiff.py --region --min-variance)."""
    opts = argparse.Namespace(a=path, region=HUD_TIME, min_variance=0.0)
    return imgdiff.variance(opts)["max_variance"]


def same_screen(a, b):
    """True when two shots are equal within the imgdiff tolerance (a stable screen)."""
    opts = argparse.Namespace(a=a, b=b, tol=24, max_frac=0.02, mask=None, region=None, out=None)
    return imgdiff.compare(opts)["result"] == "PASS"


def prepare_game_dir():
    """out/sweep/game: EBOOT.ELF and disc.iso linked to game/, an empty memory stick."""
    game = os.path.join(ROOT, OUT, "game")
    os.makedirs(game, exist_ok=True)
    for name in ("EBOOT.ELF", "disc.iso"):
        target = os.path.join(ROOT, "game", name)
        if not os.path.exists(target):
            sys.exit(f"campaign_sweep: {target} is missing (tools/setup_game.sh)")
        link = os.path.join(game, name)
        if os.path.islink(link) or os.path.exists(link):
            os.remove(link)
        os.symlink(target, link)
    ms0 = os.path.join(game, "ms0")
    shutil.rmtree(ms0, ignore_errors=True)
    os.makedirs(os.path.join(ms0, "PSP", "SAVEDATA"))
    return game


def run_cell(mode, track, opts):
    m = MODES[mode]
    cell = f"{mode}-{track}"
    out = os.path.join(ROOT, OUT)
    drive = opts.drive or os.path.join(DRIVE_DIR, f"{track}.txt")
    if not os.path.exists(os.path.join(ROOT, drive)):
        sys.exit(f"campaign_sweep: no steering table {drive}")
    script = os.path.join(out, f"{cell}.script.txt")
    log = os.path.join(out, f"{cell}.log")
    live = os.path.join(out, f"{cell}.live")
    shots = os.path.join(out, cell)
    shutil.rmtree(shots, ignore_errors=True)
    os.makedirs(shots)
    steps = build_script(mode, track, drive, opts.frames)
    with open(script, "w") as f:
        f.write("".join(f"{fr}:{a}\n" for fr, a in steps))
    open(live, "w").close()
    exit_frame = m["throttle"] + opts.frames
    game = prepare_game_dir()
    cmd = [sys.executable, os.path.join(ROOT, "tools", "run_boot.py"), "--script", script, "--shots", shots,
           "--frames", str(exit_frame), "--strict", "--max-lines", "400000",
           "--env", "PURE_WATCH_SHIP=1", "--env", "PSPRECOMP_NO_INTERPRETER=1",
           "--env", f"PURE_INPUT_LIVE={live}", "--env", f"PURE_GAME_DIR={game}", log]
    print(f"[sweep] {cell}: drive {drive}, {len(steps)} steps, exit at flip {exit_frame}", flush=True)
    start = time.time()
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    race = Race(m["laps"])
    outcome, detail = None, ""
    quit_sent = False
    halt_line = None
    shots_seen = {}                   # name -> frame
    analysed = set()
    hud_ref = None                    # HUD variance of a shot taken in the race
    prev_shot = None
    results_shot = None
    next_live_shot = None
    last_shot_path = None
    offset = 0
    pending = b""

    def send(line):
        with open(live, "a") as f:
            f.write(line + "\n")

    def stop(why_outcome, why):
        nonlocal outcome, detail, quit_sent
        if outcome is None:
            outcome, detail = why_outcome, why
        if not quit_sent:
            send("0:quit")
            quit_sent = True

    while True:
        running = proc.poll() is None
        try:
            with open(log, "rb") as f:
                f.seek(offset)
                chunk = f.read()
        except FileNotFoundError:
            chunk = b""
        offset += len(chunk)
        data = pending + chunk
        *lines, pending = data.split(b"\n")
        for raw in lines:
            line = raw.decode("utf-8", "replace")
            s = SHIP_RE.search(line)
            if s:
                race.feed(s, line)
                continue
            sh = SCRIPT_RE.search(line)
            if sh:
                shots_seen[sh[2]] = int(sh[1])
                continue
            if HALT_RE.search(line) and halt_line is None:
                if quit_sent and "Runtime stopped" in line:
                    continue
                if "Runtime stopped" in line and "PURE_EXIT_AT_FRAME" in line:
                    continue
                halt_line = line.strip()
        if halt_line and outcome is None:
            outcome, detail = "HALT", halt_line
        if outcome is None and race.started:
            if race.stalled_for() >= opts.stall:
                stop("STALL", f"no progress for {race.stalled_for():.1f} s of race clock")
            if opts.shots_every and next_live_shot is None:
                next_live_shot = 0
            if hud_ref is None and race.clock > 8.0 and "hudref" not in shots_seen and not quit_sent:
                send("0:shot hudref")
                shots_seen["hudref"] = -1
        # Live shots once the race is finished (and for tuning, every --shots-every flips).
        if outcome is None and race.finished_frame is not None and not quit_sent:
            due = race.frame - (shots_seen.get("_last_req", -10**9))
            if due >= SHOT_EVERY:
                name = f"f{race.frame}"
                send(f"0:shot {name}")
                shots_seen["_last_req"] = race.frame
        elif outcome is None and opts.shots_every and race.started and not quit_sent:
            due = race.frame - (shots_seen.get("_last_req", -10**9))
            if due >= opts.shots_every:
                send(f"0:shot t{race.frame}")
                shots_seen["_last_req"] = race.frame
        # Analyse the shots that are written.
        for name in sorted(n for n in shots_seen if not n.startswith("_")):
            path = os.path.join(shots, name + ".bmp")
            if name in analysed or not os.path.exists(path):
                continue
            try:
                var = hud_variance(path)
            except (OSError, ValueError):
                continue            # still being written
            analysed.add(name)
            last_shot_path = path
            if name == "hudref":
                hud_ref = var
                continue
            if race.finished_frame is None or hud_ref is None:
                continue
            hud_gone = var < 0.25 * hud_ref
            if hud_gone and prev_shot is not None and same_screen(path, prev_shot[0]) and prev_shot[1]:
                results_shot = path
                stop("PASS", f"results screen at flip {shots_seen[name]} (lap counter {race.max_lap})")
            prev_shot = (path, hud_gone)
        if not running:
            break
        time.sleep(0.5)

    proc.wait()
    elapsed = time.time() - start
    if halt_line and outcome not in ("PASS",):
        outcome, detail = "HALT", halt_line
    if outcome is None:
        if not race.started:
            outcome, detail = "NO RACE", "no race clock in the probe: the menu route did not reach the race"
        else:
            outcome, detail = "TIMEOUT", f"flip budget {opts.frames} used up"
    # The cell's picture: the results screen, else the last shot taken.
    png_path = os.path.join(out, f"{cell}.png")
    pick = results_shot or last_shot_path
    if pick:
        w, h, c, data = png.read_bmp(pick)
        png.write_png(png_path, w, h, c, data)
    row = {"mode": mode, "track": track, "outcome": outcome, "frame": race.frame, "laps": race.max_lap,
           "clock": race.clock, "detail": detail if outcome == "PASS" else f"{detail}; last: {race.line.strip()}",
           "seconds": elapsed}
    print(f"[sweep] {cell}: {outcome} at flip {race.frame}, lap {race.max_lap}, clock {race.clock:.1f} s, "
          f"{elapsed:.0f} s: {row['detail']}", flush=True)
    return row


def write_summary(rows):
    path = os.path.join(ROOT, OUT, "summary.txt")
    header = ("| mode | track | outcome | flip | laps | race clock | real s | run | detail |\n"
              "|---|---|---|---|---|---|---|---|---|\n")
    kept = {}
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                cols = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cols) >= 9 and cols[0] in MODES:
                    kept[(cols[0], cols[1])] = line.rstrip("\n")
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    for r in rows:
        kept[(r["mode"], r["track"])] = (f"| {r['mode']} | {r['track']} | {r['outcome']} | {r['frame']} | "
                                         f"{r['laps']} | {r['clock']:.1f} | {r['seconds']:.0f} | {stamp} | "
                                         f"{r['detail']} |")
    order = [(m, t) for m in MODES for t in MODES[m]["tracks"]]
    with open(path, "w") as f:
        f.write("# Campaign sweep (tools/campaign_sweep.py): the latest outcome of every cell run\n\n")
        f.write(header)
        for key in order:
            if key in kept:
                f.write(kept[key] + "\n")
    return path


def parse(argv):
    p = argparse.ArgumentParser(prog="campaign_sweep.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("mode", nargs="?", default="single_race")
    p.add_argument("tracks", nargs="*")
    p.add_argument("--frames", type=int, default=12000)
    p.add_argument("--stall", type=float, default=20.0)
    p.add_argument("--drive")
    p.add_argument("--shots-every", type=int, default=0)
    p.add_argument("--list", action="store_true")
    opts = p.parse_args(argv)
    if opts.mode not in MODES:
        p.error(f"unknown mode {opts.mode!r} (modes: {', '.join(MODES)})")
    known = MODES[opts.mode]["tracks"]
    opts.tracks = opts.tracks or list(known)
    for t in opts.tracks:
        if t not in known:
            p.error(f"unknown track {t!r} for {opts.mode} (tracks: {', '.join(known)})")
    if opts.drive and len(opts.tracks) != 1:
        p.error("--drive takes one track")
    return opts


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    if opts.list:
        for t in opts.tracks:
            print(f"{opts.mode} {t} ({MODES[opts.mode]['tracks'].index(t)} DOWN)")
        return 0
    os.makedirs(os.path.join(ROOT, OUT), exist_ok=True)
    rows = []
    for track in opts.tracks:
        row = run_cell(opts.mode, track, opts)
        rows.append(row)
        write_summary(rows)
        if row["outcome"] == "NO RACE":
            print("[sweep] the menu route did not reach a race; stopping the sweep", flush=True)
            break
    path = write_summary(rows)
    with open(path) as f:
        print(f.read(), end="")
    return 0 if rows and all(r["outcome"] == "PASS" for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
