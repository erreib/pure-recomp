#!/usr/bin/env python3
"""Campaign sweep: each (mode, track) cell from a cold boot to the race's results screen under scripted driving.

  tools/campaign_sweep.py [MODE [TRACK ...]] [--frames N] [--stall S] [--drive FILE] [--shots-every N] [--list]
  tools/campaign_sweep.py MODE TRACK --tune [--line CSV] [--wn W] [--preview S]
  tools/campaign_sweep.py MODE TRACK --export-line OUT [--line CSV]

MODE is a row of MODES (default single_race); TRACK names a track of the mode (default: all of them, in menu
order). Each cell is one run of build/arm64/bin/PureNative, strict (PURE_STRICT_HLE=1) with
PSPRECOMP_NO_INTERPRETER=1 and PURE_WATCH_SHIP=1, windowed (the input script drives the renderer's virtual pad).
The tool runs the game itself under a pty, the way tools/run_boot.py does, and writes the log line by line: it
steers from the `[pure] ship` lines as they come, and run_boot's block-buffered log reaches a reader up to 50
flips late. Its input script is
  config/pad_scripts/main_menu.txt   cold boot to MAIN MENU (shot steps dropped)
  the mode's race route              MAIN MENU to the race, the track picked by N DOWN presses (docs/tracks.md),
                                     Cross held from the countdown for the whole budget
  config/pad_scripts/drive/<track>.txt   the steering table (below)
Every cell starts from an empty memory stick: the run's game directory is out/sweep/game (EBOOT.ELF and disc.iso
linked to game/, ms0/ emptied before each cell), since the menu route creates a profile and answers its prompts.

Steering tables hold three kinds of lines (`#` starts a comment):
  FRAME:ACTION   an input-script step at that flip of the run (`6540:axis leftx 0.4`)
  @DIST:ACTION   sent through PURE_INPUT_LIVE (`0:ACTION`) when the ship's distance along the track (the race
                 record's +0x18, a track coordinate that wraps once a lap) passes DIST, on every lap. Of the `axis`
                 steps passed since the last ship line only the last is sent, and the first ship line of the race
                 sends the step in force there. The port reads the live file every 10 flips, so a step lands 0 to
                 10 flips after the ship passes its distance (0 to 15 m at racing speed), as it did when recorded.
  follow LINE [WN [PREVIEW]]   steer closed loop along LINE, a racing line (`dist,x,z` rows from --export-line),
                 as --tune does, through PURE_INPUT_LIVE; the table's `axis` steps are then ignored.
--tune drives closed-loop and records a table of `@DIST` steps: it tracks an AI racing line recorded in PPSSPP
(tools/pp_lines.py writes out/lines/<track>.csv; --line names another), the AI ships' mean position per 2 m of
track distance, with the line's curvature --preview seconds ahead as a feed-forward and heading and offset
feedback tuned to --wn rad/s (class Tuner). A step is sent when lx moves by 0.04. The steps sent on the second
lap (the first full lap at speed; the first lap when the race ends sooner) become
out/sweep/<mode>-<track>.tuned.txt. Replayed open loop, such a table did not hold a lap on Vineta K
(docs/tracks.md), so the committed tables `follow` an exported line instead. --export-line OUT writes the AI line
of out/lines/<track>.csv (or --line) as `dist,x,z` rows for that.
Every run also writes out/sweep/<mode>-<track>.trace.csv: per ship line the flip, race clock, lap, distance,
position, speed, the lx in force and, when a line file exists, the signed offset from the AI line (m, + = right).

--frames N is the race budget: the run stops at flip THROTTLE + N, THROTTLE being the race route's Cross-hold step
(6100), since the menu route alone takes that long (a three-lap race at Vector is 150 s, 9000 flips, more).

While the run goes the tool reads the `[pure] ship` lines (race clock, distance along the track, lap):
  - finished: the lap clock has restarted `laps` times (the player crossed the line at the end of the last lap; see
    Race for why the lap field cannot say so). The tool then stops steering (the game's autopilot takes the ship),
    asks for a screenshot every 30 flips through PURE_INPUT_LIVE and waits for the results panel, which comes up
    about 4 s after the line over a moving replay: its TOTAL label (RESULTS_TOTAL) drawn (tools/imgdiff.py region
    variance) and unchanged in two shots in a row (region compare, tol 32, 2%). That is PASS; the tool then
    closes the window (`quit`).
  - stalled: no progress along the track (distance up by 5 m, or a new lap) for --stall seconds of race clock (a
    wall stop shows as speed 0 with the distance constant): STALL, the window is closed.
  - halted: a `[hle-stub]`, `unsupported` or `Runtime stopped` line other than the frame exit and our own quit.
  - no race: no race clock 1800 flips after the Cross-hold step means the menu route broke; the sweep stops there.
Outputs: out/sweep/<mode>-<track>.log (the game's output, repeated lines folded), out/sweep/<mode>-<track>.png (the
results screen, or the last frame captured), out/sweep/<mode>-<track>/ (the live shots, BMP and PNG), and
out/sweep/summary.txt, a table with one row per cell ever run (the latest outcome replaces the cell's earlier row;
--tune runs are not entered). Exit 0 when every cell of this invocation passed, 1 otherwise, 2 on bad arguments.
--drive FILE uses FILE as the steering table (one track only; for tuning). --shots-every N also takes a live shot
every N flips from the race start (named t<frame>), for tuning.
"""
import argparse, datetime, math, os, pty, re, select, shutil, subprocess, sys, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import imgdiff  # noqa: E402  (tools/imgdiff.py)
import png  # noqa: E402  (tools/png.py)

EXE = os.path.join(ROOT, "build", "arm64", "bin", "PureNative")
MENU_ROUTE = "config/pad_scripts/main_menu.txt"
DRIVE_DIR = "config/pad_scripts/drive"
LINES_DIR = "out/lines"
OUT = "out/sweep"

# The modes and their race routes. `throttle` is the frame of the route's Cross-hold step (the budget counts from
# it); `downs_at` is where the DOWN presses that pick the track go, `downs_gap` apart; `tracks` lists the track menu
# in order (the index is the number of DOWN presses; docs/tracks.md).
ALPHA = ["vineta_k", "modesto_heights", "chenghou_project", "blue_ridge"]
MODES = {
    "single_race": {"route": "config/pad_scripts/single_race.txt", "laps": 3, "throttle": 6100,
                    "downs_at": 5380, "downs_gap": 30, "tracks": ALPHA},
}

SHIP_RE = re.compile(r"\[pure\] ship frame (\d+) t=\d+ clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"kmh=(\S+) dist=(\S+) lap=(\d+)")
FRAME_RE = re.compile(r"\[pure\] frame (\d+)")
SCRIPT_RE = re.compile(r"\[script\] frame (\d+): shot (\S+)")
HALT_RE = re.compile(r"\[hle-stub\]|unsupported|Runtime stopped")
FRAME_EXIT = "[pure] exit at frame"
FRAME_EXIT_GRACE = 15.0         # seconds the runtime gets to shut down after the frame exit

# The results panel (out/sweep/single_race-vineta_k/f16856.png, 2026-10-05: "BAD LUCK... 8TH", LAP 1-3, TOTAL,
# ENTER TAG) is drawn over a moving replay of the race, so the screen is never still; its TOTAL label is. In
# 480x272 PSP pixels:
RESULTS_TOTAL = (18, 138, 40, 12)
RESULTS_MIN_VARIANCE = 1500.0   # the label is drawn (about 3300 to 4500 on the panel)
SHOT_EVERY = 30                # flips between the live shots once the race is finished
PROGRESS_M = 5.0                # metres along the track that count as progress for the stall rule
NO_RACE_FLIPS = 1800            # flips after the Cross-hold step with no race clock: the route broke
WRAP_M = 1000.0                 # a drop in the distance this big is the once-a-lap wrap, not a step back
LX_STEP = 0.04                  # --tune sends a new lx when it moves this much


def parse_drive(path, drop_shots=True):
    """The steps of a pad script or steering table: ([(frame, action)], [(dist, action)], follow), follow being
    the `follow LINE [WN [PREVIEW]]` line's (path, wn, preview) or None."""
    steps, dist_steps, follow = [], [], None
    with open(os.path.join(ROOT, path)) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line.startswith("follow "):
                words = line.split()
                follow = (words[1], float(words[2]) if len(words) > 2 else 1.0,
                          float(words[3]) if len(words) > 3 else 0.3)
                continue
            if not line or ":" not in line:
                continue
            key, action = line.split(":", 1)
            action = action.strip()
            if key.startswith("@"):
                dist_steps.append((float(key[1:]), action))
            elif not (drop_shots and action.startswith("shot")):
                steps.append((int(key), action))
    return steps, dist_steps, follow


def build_script(mode, track, drive_steps, budget):
    m = MODES[mode]
    steps = parse_drive(MENU_ROUTE)[0] + parse_drive(m["route"])[0]
    downs = m["tracks"].index(track)
    steps += [(m["downs_at"] + k * m["downs_gap"], "pad dpdown") for k in range(downs)]
    steps.append((m["downs_at"] + max(downs, 1) * m["downs_gap"], f"shot {mode}-{track}-menu"))
    # The race route's throttle step holds Cross for the whole budget.
    steps = [(f, f"pad a {budget}") if f == m["throttle"] and a.startswith("pad a") else (f, a) for f, a in steps]
    steps += drive_steps
    steps.sort(key=lambda s: s[0])
    return steps


class Race:
    """What the `[pure] ship` lines say so far.

    The record's clock is the lap clock: it runs from GO, goes on through the first crossing of the start line
    (the lap field turns from 0 to 1 there) and restarts at 0 at every later crossing, while the lap field stays 1
    (PPSSPP, out/lines/vineta_k.csv, 2026-10-05). So a completed lap shows as the clock dropping back, and the race
    is over after `laps` such drops. `total` is the race time, the sum of the lap clocks."""

    def __init__(self, laps):
        self.laps = laps
        self.started = False
        self.frame = 0
        self.clock = 0.0
        self.base = 0.0               # the lap times completed so far
        self.total = 0.0
        self.lap = 0
        self.laps_done = 0            # lap clock resets seen
        self.lap_times = []
        self.dist = 0.0
        self.prev_dist = None         # the distance of the previous ship line of the race (None on its first)
        self.x = self.z = self.vx = self.vz = self.kmh = 0.0
        self.line = ""
        self.best = (0, 0.0)          # (laps done, distance) of the last progress
        self.best_total = 0.0         # race time at the last progress
        self.finished_frame = None    # first flip after the last lap was completed

    def feed(self, m, line):
        self.frame = int(m[1])
        clock, dist, lap = float(m[2]), float(m[10]), int(m[11])
        self.x, self.z, self.vx, self.vz, self.kmh = float(m[3]), float(m[5]), float(m[6]), float(m[8]), float(m[9])
        self.line = line
        self.prev_dist = self.dist if self.started else None
        if clock > 0.0 and not self.started:
            self.started = True
            self.best, self.best_total = (0, dist), clock
        if self.started and clock < self.clock - 1.0:
            self.base += self.clock
            self.laps_done += 1
            self.lap_times.append(self.clock)
        self.clock, self.dist, self.lap = clock, dist, lap
        self.total = self.base + clock
        # The distance is a track coordinate that wraps to 0 once a lap (docs/tracks.md): a big drop is progress.
        if self.started and (self.laps_done > self.best[0] or dist > self.best[1] + PROGRESS_M
                             or dist < self.best[1] - WRAP_M):
            self.best, self.best_total = (self.laps_done, dist), self.total
        if self.finished_frame is None and self.started and self.laps_done >= self.laps:
            self.finished_frame = self.frame

    def stalled_for(self):
        return self.total - self.best_total if self.started else 0.0


class AiLine:
    """An AI racing line: the AI ships' mean x, z per BIN metres of track distance, gaps interpolated, smoothed over
    +-3 bins, closed at the wrap. Read from tools/pp_lines.py's recording, or from a `dist,x,z` line file that
    --export-line wrote from one (the form a steering table's `follow` names)."""
    BIN = 2.0

    @staticmethod
    def samples(path, player):
        with open(path) as f:
            header = next(f).strip()
            for row in f:
                cols = row.strip().split(",")
                if header == "dist,x,z":
                    yield float(cols[0]), float(cols[1]), float(cols[2])
                    continue
                _u, k, _clock, x, _y, z, vx, _vy, vz, dist, _lap = cols
                if int(k) == player or math.hypot(float(vx), float(vz)) < 20.0:
                    continue            # the idle player, and ships on the grid
                yield float(dist), float(x), float(z)

    def __init__(self, path, player=7):
        sums, dmax = {}, 0.0
        with open(path) as f:
            exported = f.readline().strip() == "dist,x,z"
        for d, x, z in self.samples(path, player):
            s = sums.setdefault(int(d // self.BIN), [0.0, 0.0, 0])
            s[0] += x
            s[1] += z
            s[2] += 1
            dmax = max(dmax, d)
        if not sums:
            raise ValueError(f"{path}: no AI samples")
        self.n = int(dmax // self.BIN) + 1
        self.length = self.n * self.BIN
        xs, zs = [None] * self.n, [None] * self.n
        for b, (sx, sz, c) in sums.items():
            xs[b], zs[b] = sx / c, sz / c
        known = sorted(sums)
        for i, a in enumerate(known):
            b = known[(i + 1) % len(known)]
            gap = (b - a) % self.n or self.n
            for j in range(1, gap):
                t = j / gap
                xs[(a + j) % self.n] = xs[a] * (1 - t) + xs[b] * t
                zs[(a + j) % self.n] = zs[a] * (1 - t) + zs[b] * t
        r = 0 if exported else 3       # an exported line is smoothed already
        self.x = [sum(xs[(i + j) % self.n] for j in range(-r, r + 1)) / (2 * r + 1) for i in range(self.n)]
        self.z = [sum(zs[(i + j) % self.n] for j in range(-r, r + 1)) / (2 * r + 1) for i in range(self.n)]
        self.covered = len(known) / self.n

    def export(self, path, step=1):
        """Writes the line as `dist,x,z` rows, one per bin (every `step` bins, plus the last, which fixes the length)."""
        with open(path, "w") as f:
            f.write("dist,x,z\n")
            for i in sorted(set(range(0, self.n, step)) | {self.n - 1}):
                f.write(f"{i * self.BIN:.1f},{self.x[i]:.2f},{self.z[i]:.2f}\n")

    def at(self, d):
        f = (d % self.length) / self.BIN
        i = int(f) % self.n
        j = (i + 1) % self.n
        t = f - int(f)
        return self.x[i] * (1 - t) + self.x[j] * t, self.z[i] * (1 - t) + self.z[j] * t

    def offset(self, x, z, d):
        """Signed distance of (x, z) from the line at track distance d; + is to the right of the line's direction
        (the side +lx steers towards)."""
        ax, az = self.at(d)
        bx, bz = self.at(d + 4.0)
        tx, tz = bx - ax, bz - az
        n = math.hypot(tx, tz) or 1.0
        return (tx * (z - az) - tz * (x - ax)) / n


def wrap_angle(a):
    return (a + math.pi) % (2.0 * math.pi) - math.pi


class Tuner:
    """Tracks an AiLine: lx = the line's curvature ahead as a feed-forward, plus heading and offset feedback.

    Angles are atan2(z, x); positive lx turns the ship towards larger angles (heading -x, -lx turns it towards +z;
    task 012). Measured on Vineta K (2026-10-05): lx held at +-1 gives a velocity-heading rate of about 1 rad/s at
    150 km/h and up, and the heading answers 0.2 to 0.5 s after the step. With yaw rate = YAW * lx, heading error
    psi and offset e, lx = v*kappa(d + v*preview)/YAW + 2*ZETA*wn/YAW * psi - wn^2/(YAW*v) * e places the closed
    loop's poles at wn rad/s with damping ZETA. (Pure pursuit over 20 to 60 m, the first try, was ten times too
    stiff for that lag and swung from lock to lock.)"""
    YAW = 1.0
    ZETA = 0.7

    def __init__(self, line, wn, preview):
        self.line, self.wn, self.preview = line, wn, preview
        self.heading = None

    def line_heading(self, d):
        ax, az = self.line.at(d - 10.0)
        bx, bz = self.line.at(d + 10.0)
        return math.atan2(bz - az, bx - ax)

    def curvature(self, d):
        return wrap_angle(self.line_heading(d + 20.0) - self.line_heading(d - 20.0)) / 40.0

    def steer(self, race):
        speed = math.hypot(race.vx, race.vz)
        if speed > 3.0:
            self.heading = math.atan2(race.vz, race.vx)
        if self.heading is None:
            return 0.0
        v = max(speed, 30.0)
        ff = speed * self.curvature(race.dist + speed * self.preview) / self.YAW
        psi = wrap_angle(self.line_heading(race.dist) - self.heading)
        e = self.line.offset(race.x, race.z, race.dist)
        lx = ff + 2.0 * self.ZETA * self.wn / self.YAW * psi - self.wn ** 2 / (self.YAW * v) * e
        return max(-1.0, min(1.0, lx))


class DistTable:
    """The `@DIST:ACTION` steps of a steering table, sent as the ship passes their distances."""

    def __init__(self, steps):
        self.steps = sorted(steps, key=lambda s: s[0])

    @staticmethod
    def _last_per_axis(actions):
        out, seen = [], set()
        for a in reversed(actions):
            words = a.split()
            key = tuple(words[:2]) if words and words[0] == "axis" else None
            if key is not None:
                if key in seen:
                    continue
                seen.add(key)
            out.append(a)
        return list(reversed(out))

    def start(self, d):
        """The axis steps in force at distance d (the last ones at or before it, wrapping round)."""
        before = [a for k, a in self.steps if k <= d] or [a for _k, a in self.steps]
        after = [a for k, a in self.steps if k > d]
        return [a for a in self._last_per_axis(after + before) if a.startswith("axis")]

    def crossed(self, d0, d1):
        if d1 >= d0:
            acts = [a for k, a in self.steps if d0 < k <= d1]
        elif d0 - d1 > WRAP_M:
            acts = [a for k, a in self.steps if k > d0] + [a for k, a in self.steps if k <= d1]
        else:
            acts = []                 # a step back (a bounce off a wall)
        return self._last_per_axis(acts)


class Port:
    """PureNative under a pty (line-buffered stdout, as tools/run_boot.py runs it), its output folded into the log
    as it arrives."""

    def __init__(self, env, log_path, seconds, max_lines):
        self.master, self.slave = pty.openpty()
        attrs = termios.tcgetattr(self.slave)
        attrs[1] &= ~termios.OPOST
        termios.tcsetattr(self.slave, termios.TCSANOW, attrs)
        self.start = time.time()
        self.deadline = self.start + seconds
        self.p = subprocess.Popen([EXE], cwd=ROOT, env=env, stdin=subprocess.DEVNULL, stdout=self.slave,
                                  stderr=self.slave)
        self.log = open(log_path, "w", buffering=1)
        self.buf = b""
        self.last, self.repeat, self.written, self.max_lines = None, 0, 0, max_lines
        self.frame_exit = self.timed_out = False

    def _emit(self, line):
        if self.written < self.max_lines:
            self.log.write(line + "\n")
            self.written += 1
            if self.written == self.max_lines:
                self.log.write(f"... log capped at {self.max_lines} lines\n")

    def _take(self, raw, out):
        line = raw.decode("utf-8", "replace").rstrip("\r")
        if not self.frame_exit and line.startswith(FRAME_EXIT):
            self.frame_exit = True
            self.deadline = min(self.deadline, time.time() + FRAME_EXIT_GRACE)
        out.append(line)
        if line == self.last:
            self.repeat += 1
            return
        if self.repeat > 1:
            self._emit(f"    ... (x{self.repeat})")
        self.last, self.repeat = line, 1
        self._emit(line)

    def read(self, timeout):
        """The lines that arrive within timeout; kills the game at the deadline."""
        out = []
        if self.p.poll() is None and time.time() > self.deadline:
            self.timed_out = not self.frame_exit
            self.p.kill()
        ready, _, _ = select.select([self.master], [], [], timeout)
        if ready:
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                chunk = b""
            self.buf += chunk
            *lines, self.buf = self.buf.split(b"\n")
            for raw in lines:
                self._take(raw, out)
        return out

    def alive(self):
        return self.p.poll() is None

    def close(self):
        """Waits for the game, drains the pty and closes the log; returns (exit code, the last lines)."""
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
        out = []
        end = time.time() + 5.0
        while time.time() < end:
            got = self.read(0.05)
            if not got:
                break
            out += got
        os.close(self.slave)
        os.close(self.master)
        if self.buf:
            self._take(self.buf, out)
        if self.repeat > 1:
            self._emit(f"    ... (x{self.repeat})")
        code = 0 if self.frame_exit else 124 if self.timed_out else self.p.returncode
        self.log.write(f"[sweep] exit {code} after {time.time() - self.start:.1f}s, {self.written} lines\n")
        self.log.close()
        return code, out


def region_variance(path, region):
    """Largest per-channel variance of a region (tools/imgdiff.py --region --min-variance)."""
    opts = argparse.Namespace(a=path, region=region, min_variance=0.0)
    return imgdiff.variance(opts)["max_variance"]


def same_region(a, b, region):
    """True when a region of two shots is equal within tolerance (tools/imgdiff.py --region, tol 32, 2%)."""
    opts = argparse.Namespace(a=a, b=b, tol=32, max_frac=0.02, mask=None, region=region, out=None)
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


def write_tuned(path, cell, sent, laps_done, opts):
    """The lx steps --tune sent on one lap, as a distance-keyed steering table."""
    lap = 1 if laps_done >= 2 else 0          # laps done when the steps were sent: 1 is the second lap
    rows = {}
    for lp, d, lx in sent:
        if lp == lap:
            rows[round(d, 1)] = lx
    with open(path, "w") as f:
        f.write(f"# {cell}: recorded by tools/campaign_sweep.py --tune (wn {opts.wn}, preview {opts.preview} s, line "
                f"{opts.line}) on lap {lap + 1}, {datetime.date.today().isoformat()}\n")
        for d in sorted(rows):
            f.write(f"@{d:.1f}:axis leftx {rows[d]:.2f}\n")
    return lap, len(rows)


def run_cell(mode, track, opts):
    m = MODES[mode]
    cell = f"{mode}-{track}"
    out = os.path.join(ROOT, OUT)
    drive = opts.drive or os.path.join(DRIVE_DIR, f"{track}.txt")
    if not os.path.exists(os.path.join(ROOT, drive)):
        sys.exit(f"campaign_sweep: no steering table {drive}")
    drive_steps, dist_steps, follow = parse_drive(drive, drop_shots=False)
    line_path = opts.line or (follow[0] if follow else os.path.join(LINES_DIR, f"{track}.csv"))
    ai_line = AiLine(os.path.join(ROOT, line_path)) if os.path.exists(os.path.join(ROOT, line_path)) else None
    tuner = None
    if opts.tune or follow:
        if ai_line is None:
            sys.exit(f"campaign_sweep: no racing line {line_path} (tools/pp_lines.py {track})")
        wn, preview = (opts.wn, opts.preview) if opts.tune or not follow else follow[1:]
        tuner = Tuner(ai_line, wn, preview)
        drive_steps, dist_steps = [s for s in drive_steps if not s[1].startswith("axis")], []
    table = DistTable(dist_steps) if dist_steps else None
    script = os.path.join(out, f"{cell}.script.txt")
    log = os.path.join(out, f"{cell}.log")
    live = os.path.join(out, f"{cell}.live")
    shots = os.path.join(out, cell)
    shutil.rmtree(shots, ignore_errors=True)
    os.makedirs(shots)
    steps = build_script(mode, track, drive_steps, opts.frames)
    with open(script, "w") as f:
        f.write("".join(f"{fr}:{a}\n" for fr, a in steps))
    open(live, "w").close()
    exit_frame = m["throttle"] + opts.frames
    game = prepare_game_dir()
    env = dict(os.environ)
    env.update({"PURE_GAME_DIR": game, "PURE_LIST_STUBS": "1", "PURE_STRICT_HLE": "1",
                "PURE_EXIT_AT_FRAME": str(exit_frame), "PURE_INPUT_SCRIPT": ";".join(f"{fr}:{a}" for fr, a in steps),
                "PURE_SCREENSHOT_DIR": shots, "PURE_SCREENSHOT_EVERY": "0", "PURE_WATCH_SHIP": "1",
                "PSPRECOMP_NO_INTERPRETER": "1", "PURE_INPUT_LIVE": live, "PURE_FRAME_LOG": "60"})
    how = (f"{'tune' if opts.tune else 'follow'} {line_path} (coverage {ai_line.covered:.0%}, "
           f"{ai_line.length:.0f} m, wn {tuner.wn}, preview {tuner.preview} s)" if tuner else
           f"drive {drive} ({len(drive_steps)} frame steps, {len(dist_steps)} distance steps)")
    print(f"[sweep] {cell}: {how}, exit at flip {exit_frame}", flush=True)
    port = Port(env, log, max(60.0, exit_frame / 15.0), opts.max_lines)
    trace = open(os.path.join(out, f"{cell}.trace.csv"), "w")
    trace.write("frame,clock,lap,dist,x,z,kmh,lx,offset\n")

    race = Race(m["laps"])
    state = {"outcome": None, "detail": "", "quit": False, "halt": None, "lx": 0.0, "steering": True,
             "frame": 0, "steady": 0, "prev_shot": None, "results": None, "last_shot": None}
    shots_seen = {}                   # name -> frame
    analysed = set()
    sent = []                         # --tune: (lap, dist, lx) of every lx step sent

    def send(text):
        with open(live, "a") as f:
            f.write(text + "\n")

    def stop(why_outcome, why):
        if state["outcome"] is None:
            state["outcome"], state["detail"] = why_outcome, why
        if not state["quit"]:
            send("0:quit")
            state["quit"] = True

    def on_ship(s, text):
        race.feed(s, text)
        state["frame"] = race.frame
        if not race.started or state["quit"]:
            return
        if race.finished_frame is not None:
            if state["steering"]:
                send("0:axis leftx 0")
                state["steering"], state["lx"] = False, 0.0
        elif tuner is not None:
            lx = round(tuner.steer(race), 2)
            if abs(lx - state["lx"]) >= LX_STEP or (lx == 0.0 and state["lx"] != 0.0):
                send(f"0:axis leftx {lx:.2f}")
                state["lx"] = lx
                sent.append((race.laps_done, race.dist, lx))
        elif table is not None:
            acts = table.start(race.dist) if race.prev_dist is None else table.crossed(race.prev_dist, race.dist)
            for a in acts:
                send(f"0:{a}")
                if a.startswith("axis leftx"):
                    state["lx"] = float(a.split()[2])
        off = f"{ai_line.offset(race.x, race.z, race.dist):.2f}" if ai_line else ""
        trace.write(f"{race.frame},{race.total:.3f},{race.laps_done},{race.dist:.2f},{race.x:.2f},{race.z:.2f},"
                    f"{race.kmh:.1f},{state['lx']:.2f},{off}\n")

    def handle(text):
        s = SHIP_RE.search(text)
        if s:
            on_ship(s, text)
            return
        fr = FRAME_RE.match(text)
        if fr:
            state["frame"] = max(state["frame"], int(fr[1]))
            return
        sh = SCRIPT_RE.search(text)
        if sh:
            shots_seen[sh[2]] = int(sh[1])
            return
        if HALT_RE.search(text) and state["halt"] is None:
            if "Runtime stopped" in text and (state["quit"] or "PURE_EXIT_AT_FRAME" in text):
                return
            state["halt"] = text.strip()

    while True:
        for text in port.read(0.05):
            handle(text)
        outcome = state["outcome"]
        if state["halt"] and outcome is None:
            stop("HALT", state["halt"])
        if state["outcome"] is None and not race.started and state["frame"] > m["throttle"] + NO_RACE_FLIPS:
            stop("NO RACE", f"no race clock by flip {state['frame']}: the menu route did not reach the race")
        if state["outcome"] is None and race.started:
            if race.finished_frame is None and race.stalled_for() >= opts.stall:
                stop("STALL", f"no progress for {race.stalled_for():.1f} s of race clock")
        # Live shots once the race is finished (and for tuning, every --shots-every flips).
        if state["outcome"] is None and not state["quit"] and race.started:
            every = SHOT_EVERY if race.finished_frame is not None else opts.shots_every
            prefix = "f" if race.finished_frame is not None else "t"
            if every and race.frame - shots_seen.get("_last_req", -10**9) >= every:
                send(f"0:shot {prefix}{race.frame}")
                shots_seen["_last_req"] = race.frame
        # Analyse the shots that are written.
        for name in sorted(n for n in shots_seen if not n.startswith("_")):
            path = os.path.join(shots, name + ".bmp")
            if name in analysed or not os.path.exists(path):
                continue
            try:
                var = region_variance(path, RESULTS_TOTAL)
                prev = state["prev_shot"]
                steady = prev is not None and same_region(path, prev, RESULTS_TOTAL)
            except (OSError, ValueError):
                continue            # still being written
            analysed.add(name)
            state["last_shot"] = path
            if race.finished_frame is None or not name.startswith("f"):
                continue
            state["steady"] = state["steady"] + 1 if steady and var >= RESULTS_MIN_VARIANCE else 0
            print(f"[sweep] {cell}: shot {name}: TOTAL label variance {var:.0f}, steady {steady} "
                  f"({state['steady']} in a row)", flush=True)
            if state["steady"] >= 1 and state["outcome"] is None:
                state["results"] = path
                stop("PASS", f"results screen at flip {shots_seen[name]} ({race.laps_done} laps: "
                     + ", ".join(f"{t:.1f}" for t in race.lap_times) + f" s; {race.total:.1f} s at the shot)")
            state["prev_shot"] = path
        if not port.alive():
            break

    code, rest = port.close()
    for text in rest:
        handle(text)
    trace.close()
    elapsed = time.time() - port.start
    outcome, detail = state["outcome"], state["detail"]
    if state["halt"] and outcome != "PASS":
        outcome, detail = "HALT", state["halt"]
    if outcome is None:
        if not race.started:
            outcome, detail = "NO RACE", "no race clock in the probe: the menu route did not reach the race"
        elif port.timed_out:
            outcome, detail = "TIMEOUT", f"wall-clock deadline reached (exit {code})"
        else:
            outcome, detail = "TIMEOUT", f"flip budget {opts.frames} used up"
    # Convert the live shots, and keep the cell's picture: the results screen, else the last shot taken.
    for name in sorted(os.listdir(shots)):
        if name.endswith(".bmp"):
            try:
                w, h, c, data = png.read_bmp(os.path.join(shots, name))
                png.write_png(os.path.join(shots, name[:-4] + ".png"), w, h, c, data)
            except (OSError, ValueError):
                pass
    pick = state["results"] or state["last_shot"]
    if pick:
        w, h, c, data = png.read_bmp(pick)
        png.write_png(os.path.join(out, f"{cell}.png"), w, h, c, data)
    if opts.tune:
        tuned = os.path.join(out, f"{cell}.tuned.txt")
        lap, n = write_tuned(tuned, cell, sent, race.laps_done, opts)
        print(f"[sweep] {cell}: {n} steps of lap {lap + 1} -> {tuned}", flush=True)
    row = {"mode": mode, "track": track, "outcome": outcome, "frame": race.frame, "laps": race.laps_done,
           "clock": race.total, "detail": detail if outcome == "PASS" else f"{detail}; last: {race.line.strip()}",
           "seconds": elapsed, "tune": opts.tune}
    print(f"[sweep] {cell}: {outcome} at flip {race.frame}, {race.laps_done} laps, race time {race.total:.1f} s, "
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
        if r.get("tune"):
            continue
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
    p.add_argument("--max-lines", type=int, default=400000)
    p.add_argument("--tune", action="store_true")
    p.add_argument("--line")
    p.add_argument("--wn", type=float, default=1.0)
    p.add_argument("--preview", type=float, default=0.3)
    p.add_argument("--export-line", metavar="OUT")
    p.add_argument("--list", action="store_true")
    opts = p.parse_args(argv)
    if opts.mode not in MODES:
        p.error(f"unknown mode {opts.mode!r} (modes: {', '.join(MODES)})")
    known = MODES[opts.mode]["tracks"]
    opts.tracks = opts.tracks or list(known)
    for t in opts.tracks:
        if t not in known:
            p.error(f"unknown track {t!r} for {opts.mode} (tracks: {', '.join(known)})")
    if (opts.drive or opts.tune or opts.line or opts.export_line) and len(opts.tracks) != 1:
        p.error("--drive, --tune, --line and --export-line take one track")
    return opts


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    if opts.list:
        for t in opts.tracks:
            print(f"{opts.mode} {t} ({MODES[opts.mode]['tracks'].index(t)} DOWN)")
        return 0
    if opts.export_line:
        src = opts.line or os.path.join(LINES_DIR, f"{opts.tracks[0]}.csv")
        line = AiLine(os.path.join(ROOT, src))
        line.export(opts.export_line)
        print(f"{src}: {line.length:.0f} m, {line.covered:.0%} of the bins sampled -> {opts.export_line}")
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
