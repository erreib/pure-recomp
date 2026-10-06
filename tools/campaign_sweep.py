#!/usr/bin/env python3
"""Campaign sweep: each (mode, track) cell from a cold boot to the race's results screen under scripted driving.

  tools/campaign_sweep.py [MODE [TRACK ...]] [--frames N] [--stall S] [--drive FILE] [--shots-every N] [--list]
                          [--set KEY=VALUE ...] [--out DIR] [--no-damage]
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
Every cell starts from an empty memory stick: the run's game directory is out/sweep/game/<cell> (EBOOT.ELF and
disc.iso linked to game/, ms0/ emptied before each run), since the menu route creates a profile and answers its
prompts. Cells of different tracks can run side by side (the summary is merged under a lock).

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
  follow LINE [WN [PREVIEW]] [KEY=VALUE ...]   the options of class Tuner: koff, kpsi (feedback gains), airbrake
                 (hold the inside airbrake while the demanded |lx| passes it), lift and ahead (release Cross before
                 a corner that needs more yaw rate than lift rad/s at the current speed). --set KEY=VALUE overrides
                 them, and wn and preview, for one run (tuning).
Every run also writes out/sweep/<mode>-<track>.trace.csv: per ship line the flip, race clock, lap, distance,
position, speed, the lx in force, the signed offset from the AI line (m, + = right) and the heading error from it
(rad) when a line file exists, Cross (1 held) and the airbrake (-1 L, 1 R), and <mode>-<track>.contacts.csv: the
contacts (the speed down by CONTACT_KMH within CONTACT_WINDOW s: walls, other ships, weapon hits) with the race
time, lap and distance. The summary's detail counts them a lap. A `ref` shot 600 flips into the race reads the
HUD's shield bar (SHIELD_BAR, full) to check the reading.

--frames N is the race budget: the run stops at flip THROTTLE + N, THROTTLE being the race route's Cross-hold step
(6100), since the menu route alone takes that long (a three-lap race at Vector is 150 s, 9000 flips, more). Without
--frames each track gets its budget from MODES (`frames`): the follower's laps take about 60 s on Vineta K and 75 to
95 s on the other Alpha tracks.

--no-damage sets PURE_TEST_NO_DAMAGE=1, the port's test switch that refills the player's shield every flip, so
contacts cannot destroy the ship: the sweep's job is to reach every results screen and find halts, not to race
well. The summary marks such a row's outcome `(no damage)`. Never a default.

While the run goes the tool reads the `[pure] ship` lines (race clock, distance along the track, lap):
  - finished: the lap clock has restarted `laps` times (the player crossed the line at the end of the last lap; see
    Race for why the lap field cannot say so). The tool then stops steering (the game's autopilot takes the ship),
    asks for a screenshot every 30 flips through PURE_INPUT_LIVE and waits for the results panel, which comes up
    about 4 s after the line over a moving replay: its TOTAL label (RESULTS_TOTAL) drawn (tools/imgdiff.py region
    variance) and unchanged in two shots in a row (region compare, tol 32, 2%). That is PASS; the tool then
    closes the window (`quit`).
  - stalled: no progress along the track (distance up by 5 m, or a new lap) for --stall seconds of race clock (a
    wall stop shows as speed 0 with the distance constant): STALL. The tool takes a `stall` shot, then closes the
    window. The detail classifies the stop from the shot ("SHIP DESTROYED" title, shield bar), the probe's
    shield and the trace (classify_stall: eliminated by damage, off the line, stuck on geometry, or stopped)
    and lists the last 5 s of the trace one row a second;
    out/sweep/<mode>-<track>.stall.csv holds those 5 s in full.
  - halted: a `[hle-stub]`, `unsupported` or `Runtime stopped` line other than the frame exit and our own quit.
  - no race: no race clock 1800 flips after the Cross-hold step means the menu route broke; the sweep stops there.
Outputs: out/sweep/<mode>-<track>.log (the game's output, repeated lines folded), out/sweep/<mode>-<track>.png (the
results screen, the stall shot, or the last frame captured), out/sweep/<mode>-<track>/ (the live shots), and
out/sweep/summary.txt, a table with one row per cell ever run (the latest outcome replaces the cell's earlier row;
--tune runs are not entered). Exit 0 when every cell of this invocation passed, 1 otherwise, 2 on bad arguments.
--drive FILE uses FILE as the steering table (one track only; for tuning). --shots-every N also takes a live shot
every N flips from the race start (named t<frame>), for tuning. --out DIR writes everything (the game directory and
the summary too) under DIR instead of out/sweep, so two tuning runs can go side by side.
"""
import argparse, datetime, fcntl, math, os, pty, re, select, shutil, subprocess, sys, termios, time

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
# `frames` is each track's race budget (flips from the Cross hold): three laps at the follower's pace, the results
# panel and some slack (task 016: laps of 57 to 70 s on Vineta K, 75 to 95 s on the other three; the race clock runs
# at about 58 flips a second).
# The other keys (task 018; docs/tracks.md has each mode's screens):
#   fps     flips a second in the race: Time Trial, Free Play and Zone are locked at 30 (docs/research.md), so their
#           budgets are flips at 30 a second, and the flip-counted waits (the `ref` shot, the live shots after the
#           finish) are scaled to keep their times
#   end     how a cell ends: `results` (the results panel's TOTAL label, as in Single Race), `session` (Free Play has
#           no last lap: after `laps` laps the sweep pauses and picks END SESSION, and the "RETURN TO MAIN MENU" banner
#           is the end), `destroyed` (Zone ends when the shield runs out: the "SHIP DESTROYED" panel with TOTAL ZONES
#           CLEAR is the end, the zones are read from it, and the stall rule and --no-damage do not apply),
#           `standings` (Tournament: the races of `races` in a row; after each results panel the sweep presses Cross
#           every ADVANCE_EVERY flips through ENTER TAG and the standings until the next race's player object
#           appears; after the last race the standings screen is the end)
#   races   Tournament: the tracks of each league in race order (each race steers with its track's table)
ALPHA = ["vineta_k", "modesto_heights", "chenghou_project", "blue_ridge"]
DEFAULT_FRAMES = 13000
MODES = {
    "single_race": {"route": "config/pad_scripts/single_race.txt", "laps": 3, "throttle": 6100,
                    "downs_at": 5380, "downs_gap": 30, "tracks": ALPHA,
                    "frames": {"vineta_k": 13000, "modesto_heights": 18000, "chenghou_project": 18000,
                               "blue_ridge": 18000}},
    # Three laps alone against the clock; 60 to 95 s laps are 1800 to 2900 flips at 30 a second.
    "time_trial": {"route": "config/pad_scripts/time_trial.txt", "laps": 3, "throttle": 5900, "fps": 30,
                   "downs_at": 5380, "downs_gap": 30, "tracks": ALPHA,
                   "frames": {"vineta_k": 8000, "modesto_heights": 10000, "chenghou_project": 10000,
                              "blue_ridge": 10000}},
    "free_play": {"route": "config/pad_scripts/free_play.txt", "laps": 3, "throttle": 5900, "fps": 30,
                  "end": "session", "downs_at": 5380, "downs_gap": 30, "tracks": ALPHA,
                  "frames": {"vineta_k": 8000, "modesto_heights": 10000, "chenghou_project": 10000,
                             "blue_ridge": 10000}},
    # Zone tracks: zone_1 is PRO TOZO, the only one open on a new profile.
    "zone": {"route": "config/pad_scripts/zone.txt", "laps": 0, "throttle": 5250, "fps": 30, "end": "destroyed",
             "downs_at": 4980, "downs_gap": 30, "tracks": ["zone_1"], "frames": {"zone_1": 9000}},
    # Leagues: ALPHA only on a new profile. The budget covers all four races (Single Race's budgets, with the
    # screens between them).
    "tournament": {"route": "config/pad_scripts/tournament.txt", "laps": 3, "throttle": 5850, "end": "standings",
                   "downs_at": 5180, "downs_gap": 30, "tracks": ["alpha"], "races": {"alpha": ALPHA},
                   "frames": {"alpha": 75000}},
}

SHIP_RE = re.compile(r"\[pure\] ship frame (\d+) t=\d+ clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"kmh=(\S+) dist=(\S+) lap=(\d+)(?: shield=(\S+))?")
PLAYER_RE = re.compile(r"\[pure\] ship frame (\d+) player object (\S+) index (\d+)")   # a new race's ship
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
# Contacts (walls, other ships, weapon hits): the speed falling by CONTACT_KMH within CONTACT_WINDOW s of race clock
# from at least CONTACT_MIN_KMH; a drop within CONTACT_GAP s of the last one is the same contact.
CONTACT_KMH = 20.0
CONTACT_WINDOW = 0.25
CONTACT_GAP = 1.0
CONTACT_MIN_KMH = 80.0
TAIL_S = 5.0                    # seconds of trace a STALL reports
# The HUD's shield (energy) bar, bottom right under the speed bar, in 480x272 PSP pixels (out/m3/s7200.png: full,
# 2026-10-05). It fills from the left, cyan to white; a column counts as filled when a pixel of it is.
SHIELD_BAR = (310, 254, 143, 11)
REF_SHOT_FLIPS = 600            # the `ref` shot (a full shield bar) this many flips after the race clock starts
# The "SHIP DESTROYED" panel the game puts up about 5 s after the shield runs out (task 017, out/017/destroyed: a
# Vineta K race on a local build that held the shield at 1, destroyed at the first wall at 6.2 s), checked in a
# shot's title row, in 480x272 PSP pixels; the results panel has its place there ("BAD LUCK... 8TH"). A column is
# lit when a pixel of it is white (every channel 0xC0 or more). DESTROYED_TITLE is the title's columns from the
# left, as runs: positive lit, negative dark. Shots of the panel differ from it by 0 or 1 column, the panel fading
# in by 14, "BAD LUCK... 8TH" by 40, a bright race view by 35 or more.
TITLE_REGION = (16, 22, 170, 14)
DESTROYED_TITLE = (-4, 11, -1, 11, -1, 2, -1, 11, -7, 12, -1, 11, -1, 11, -2, 10, -1, 11, -1, 11, -1, 11, -2, 11, -1,
                   12, -11)
TITLE_MAX_MISMATCH = 8          # columns
# Zone (task 018, out/018/e-zone2): the same "SHIP DESTROYED" title heads Zone's end panel, about 6 s after the
# shield runs out, with TOTAL ZONES CLEAR, TOTAL LAPS CLEAR, PERFECT ZONES, PERFECT LAPS, TOP SPEED, SCORE and ENTER
# TAG. ZONES_VALUE is where TOTAL ZONES CLEAR's number is drawn (left-aligned at x 240, 8 pixels high; room for
# three digits), read by read_digits.
ZONES_VALUE = (236, 52, 40, 14)
# Free Play (task 018, out/018/e-fp3): END SESSION in the pause menu (CONTINUE, RESTART, END SESSION) leads to a
# fly-by with a "RETURN TO MAIN MENU" banner and PRESS X TO CONFIRM; MENU_BANNER is the banner's lit columns in
# BANNER_REGION, as DESTROYED_TITLE is the title's (shots of the banner differ from it by 0 to 2 columns).
BANNER_REGION = (52, 80, 220, 20)
MENU_BANNER = (-5, 11, -1, 11, -1, 11, -1, 11, -1, 11, -1, 11, -7, 11, -1, 11, -7, 13, -2, 11, -1, 2, -1, 11, -7, 13,
               -2, 11, -1, 11, -1, 11, -9)
PAUSE_GAP = 40                  # flips between the steps of the pause-menu answer (Start, DOWN, DOWN, Cross)
ADVANCE_EVERY = 120             # Tournament: flips between the Cross presses that answer the screens between races


def parse_drive(path, drop_shots=True):
    """The steps of a pad script or steering table: ([(frame, action)], [(dist, action)], follow), follow being
    the `follow LINE [WN [PREVIEW]] [KEY=VALUE ...]` line's (path, wn, preview, {KEY: VALUE}) or None."""
    steps, dist_steps, follow = [], [], None
    with open(os.path.join(ROOT, path)) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line.startswith("follow "):
                words = [w for w in line.split()[1:] if "=" not in w]
                params = dict(w.split("=", 1) for w in line.split()[1:] if "=" in w)
                follow = (words[0], float(words[1]) if len(words) > 1 else 1.0,
                          float(words[2]) if len(words) > 2 else 0.3, params)
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

    def __init__(self, laps, refilled=False):
        self.laps = laps
        self.refilled = refilled      # PURE_TEST_NO_DAMAGE: the port refills the shield after every probe line
        self.started = False
        self.frame = self.start_frame = 0
        self.clock = 0.0
        self.base = 0.0               # the lap times completed so far
        self.total = 0.0
        self.lap = 0
        self.laps_done = 0            # lap clock resets seen
        self.lap_times = []
        self.dist = 0.0
        self.prev_dist = None         # the distance of the previous ship line of the race (None on its first)
        self.x = self.z = self.vx = self.vz = self.kmh = 0.0
        self.shield = None            # the ship object's shield (+0xF8; 100 full), from builds whose probe prints it
        self.full = 0.0               # the highest shield seen
        self.damage = 0.0             # shield lost in the race (with the switch: what the refills put back)
        self.line = ""
        self.best = (0, 0.0)          # (laps done, distance) of the last progress
        self.best_total = 0.0         # race time at the last progress
        self.finished_frame = None    # first flip after the last lap was completed
        self.hist = []                # (race time, km/h) of the last CONTACT_WINDOW s
        self.contacts = []            # (race time, laps done, distance, km/h lost)

    def feed(self, m, line):
        self.frame = int(m[1])
        clock, dist, lap = float(m[2]), float(m[10]), int(m[11])
        self.x, self.z, self.vx, self.vz, self.kmh = float(m[3]), float(m[5]), float(m[6]), float(m[8]), float(m[9])
        shield = float(m[12]) if m[12] is not None else None
        if shield is not None and self.started and self.finished_frame is None:
            # The probe prints the shield before the switch refills it, so with the switch each line shows what
            # that frame took; without it, the shield only falls.
            lost = self.full - shield if self.refilled else (self.shield - shield if self.shield is not None else 0.0)
            self.damage += max(0.0, lost)
        if shield is not None:
            self.full = max(self.full, shield)
        self.shield = shield
        self.line = line
        self.prev_dist = self.dist if self.started else None
        if clock > 0.0 and not self.started:
            self.started = True
            self.start_frame = self.frame
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
        if self.finished_frame is None and self.started and self.laps and self.laps_done >= self.laps:
            self.finished_frame = self.frame      # (laps 0: Zone, which ends when the ship is destroyed)
        if self.started and self.finished_frame is None:
            self.hist.append((self.total, self.kmh))
            while self.hist[0][0] < self.total - CONTACT_WINDOW:
                self.hist.pop(0)
            peak = max(k for _t, k in self.hist)
            last = self.contacts[-1][0] if self.contacts else -1e9
            if peak >= CONTACT_MIN_KMH and peak - self.kmh >= CONTACT_KMH and self.total - last >= CONTACT_GAP:
                self.contacts.append([self.total, self.laps_done, dist, peak - self.kmh, float("nan")])

    def contact_text(self):
        """`N contacts (a, b, c a lap)` over the laps begun."""
        laps = max(1, min(self.laps, self.laps_done + 1))
        per = [0] * laps
        for _t, lp, _d, _k, _o in self.contacts:
            per[min(lp, laps - 1)] += 1
        return f"{len(self.contacts)} contacts ({', '.join(map(str, per))} a lap)"

    def damage_text(self):
        """`; shield S at the end, D taken` (with the switch: `; D shield taken and refilled (no damage)`); empty
        when the probe does not print the shield."""
        if self.shield is None:
            return ""
        if self.refilled:
            return f"; {self.damage:.0f} shield taken and refilled (no damage)"
        return f"; shield {self.shield:.1f} at the end, {self.damage:.0f} taken"

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
    task 012). The heading answers 0.2 to 0.5 s after the stick. The stick has a dead zone: binned over a
    three-lap run (task 016, 2026-10-05) the velocity heading turns at about 0 rad/s for |lx| up to 0.3, then about
    1.15 * (|lx| - 0.3) rad/s, about 0.8 rad/s at full lock (the host's 15% dead zone, rescaled, plus the game's).
    The loop asks for a yaw rate u * yaw, and stick() maps u through the dead zone (lx = deadzone + (1 - deadzone)
    * |u|). With heading error psi and offset e, u = v*kappa(d + v*preview)/yaw + 2*ZETA*wn/yaw * psi
    - wn^2/(yaw*v) * e places the closed loop's poles at wn rad/s with damping ZETA. (Pure pursuit over 20 to 60 m,
    the first try, was ten times too stiff for that lag and swung from lock to lock. Without the dead-zone mapping
    the offset term stays inside the dead zone below about 20 m, and the ship ran 10 to 13 m off the line for
    seconds at a time: 43 contacts in a three-lap run.)

    The `follow` line's KEY=VALUE options (PARAMS) scale the feedback and use the controls full lock lacks:
      yaw, deadzone  the stick model above (rad/s at full lock; lx where the turning starts)
      koff, kpsi   multiply the offset and heading terms (1 = the poles above)
      airbrake A   hold the airbrake on the inside of the turn (L for -lx, R for +lx, through the analog triggers)
                   while the demanded |lx| is above A, until it falls below 0.8 A (0: never)
      lift L       release Cross while the line's sharpest curvature from PREVIEW to AHEAD s ahead needs more than
                   L rad/s at the current speed, and hold it again below 0.9 L (0: never)
      ahead S      that look-ahead (s)
      lag T        predict the ship T s ahead before steering (a Smith predictor): the heading turned by the lx
                   steps sent in the last T s (the model above) and the position moved on along it; the loop then
                   steers the predicted ship (0: steer the ship as last seen)
      vmax V       above V km/h (a speed pad gives about 450; the AI ships race at 270 to 340) release Cross and
                   hold both airbrakes until the speed is 10 km/h under V (0: never). Speed lost while braking is
                   not counted as a contact. Blue Ridge needs speed at about 2360 m: capped at 250 km/h the ship
                   fell there and the game put it back at about 1960 m, three times in a row (task 016)
      absorb S     press Square (`pad x`, "Absorb pickup" in the game's default controls: X accelerate, O use
                   pickup, SQ absorb, L1/R1 airbrakes) for `hold` frames every S s of race, meant to turn a weapon
                   picked up from a pad into shield (0: never). A ship whose shield runs out is destroyed ("SHIP
                   DESTROYED"). No shield gain was seen in task 016's shots, held 4 or 40 frames
      use S        press Circle (`pad b`, "Use pickup") every S s of race: fires a weapon, or raises a shield
                   or engages the autopilot when the pickup is one of those (0: never)
      recover K    below K km/h after the first 5 s (the ship against a wall, its velocity no guide to where its nose
                   points) steer full lock towards the line, Cross held, until the speed is back (0: never)"""
    ZETA = 0.7
    PARAMS = {"yaw": 0.8, "deadzone": 0.3, "koff": 1.0, "kpsi": 1.0, "airbrake": 0.0, "lift": 0.0, "ahead": 1.5,
              "lag": 0.0, "recover": 0.0, "vmax": 0.0, "absorb": 0.0, "hold": 4.0, "use": 0.0}

    def __init__(self, line, wn, preview, **params):
        self.line, self.wn, self.preview = line, wn, preview
        self.heading = None
        self.psi = self.offset = 0.0
        self.sent = [(0.0, 0.0)]      # (race time, lx) of the steps sent, for the predictor
        self.recovering = 0
        for k, v in self.PARAMS.items():
            setattr(self, k, float(params.get(k, v)))

    def describe(self):
        return f"wn {self.wn}, preview {self.preview} s" + "".join(
            f", {k} {getattr(self, k):g}" for k, v in self.PARAMS.items() if getattr(self, k) != v)

    def line_heading(self, d):
        ax, az = self.line.at(d - 10.0)
        bx, bz = self.line.at(d + 10.0)
        return math.atan2(bz - az, bx - ax)

    def curvature(self, d):
        return wrap_angle(self.line_heading(d + 20.0) - self.line_heading(d - 20.0)) / 40.0

    def demand(self, race):
        """The lx the loop asks for, before clipping to full lock."""
        speed = math.hypot(race.vx, race.vz)
        if speed > 3.0:
            self.heading = math.atan2(race.vz, race.vx)
        if self.heading is None:
            return 0.0
        v = max(speed, 30.0)
        heading, x, z, d = self.heading, race.x, race.z, race.dist
        if self.lag > 0.0:
            turn = self.pending(race.total)
            mid = heading + turn / 2.0
            x, z = x + speed * self.lag * math.cos(mid), z + speed * self.lag * math.sin(mid)
            heading, d = heading + turn, d + speed * self.lag
        ff = speed * self.curvature(d + speed * self.preview) / self.yaw
        self.psi = psi = wrap_angle(self.line_heading(d) - heading)
        self.offset = e = self.line.offset(x, z, d)
        if self.recover > 0.0:
            if race.total > 5.0 and race.kmh < self.recover:
                if abs(e) >= 3.0 or not self.recovering:
                    self.recovering = -1 if e > 0.0 else 1
                return float(self.recovering)
            self.recovering = 0
        return (ff + self.kpsi * 2.0 * self.ZETA * self.wn / self.yaw * psi
                - self.koff * self.wn ** 2 / (self.yaw * v) * e)

    def note(self, t, lx):
        """An lx step sent at race time t."""
        self.sent.append((t, lx))
        while len(self.sent) > 2 and self.sent[1][0] < t - 3.0:
            self.sent.pop(0)

    def response(self, lx):
        """The yaw rate (rad/s) lx gives: none in the dead zone, linear past it."""
        return math.copysign(max(0.0, abs(lx) - self.deadzone) / (1.0 - self.deadzone), lx) * self.yaw

    def pending(self, t):
        """The heading change still to come from the steps sent in the last `lag` s."""
        t0, total = t - self.lag, 0.0
        for i, (ts, lx) in enumerate(self.sent):
            te = self.sent[i + 1][0] if i + 1 < len(self.sent) else t
            a, b = max(ts, t0), min(te, t)
            if b > a:
                total += self.response(lx) * (b - a)
        return total

    def stick(self, u):
        """The lx that gives the yaw rate u * yaw: past the dead zone the response is about linear in lx."""
        if abs(u) < 0.02:
            return 0.0
        return math.copysign(self.deadzone + (1.0 - self.deadzone) * min(abs(u), 1.0), u)

    def steer(self, race):
        return self.stick(self.demand(race))

    def corner_need(self, race):
        """The yaw rate (rad/s) the sharpest curvature from PREVIEW to AHEAD s ahead needs at the current speed."""
        speed = math.hypot(race.vx, race.vz)
        d0, d1 = race.dist + speed * self.preview, race.dist + speed * max(self.ahead, self.preview)
        kmax = max(abs(self.curvature(d0 + k * 5.0)) for k in range(int((d1 - d0) // 5.0) + 1))
        return speed * kmax / self.yaw


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


def shield_fraction(path):
    """How full the HUD's shield bar is in a shot: the run of filled columns from the bar's left end over its full
    width (SHIELD_BAR), 0 to 1; None when the shot cannot be read."""
    try:
        w, h, c, data = png.read_bmp(path)
    except (OSError, ValueError):
        return None
    x0, y0, x1, y1 = imgdiff.scale_region(SHIELD_BAR, w, h)
    run = 0
    for x in range(x0, x1):
        if not any(data[(y * w + x) * c + 2] >= 0xf0 and data[(y * w + x) * c + 1] >= 0xd0
                   and data[(y * w + x) * c] >= 0x9c for y in range(y0, y1)):
            break
        run += 1
    return run / (x1 - x0)


def shield_text(path):
    f = shield_fraction(path)
    return "unreadable" if f is None else f"{f:.0%}"


def title_columns(path, region=TITLE_REGION):
    """The lit columns of a shot's title row (TITLE_REGION, or region) as a string of '#' and '.', one per PSP
    pixel column; None when the shot cannot be read."""
    try:
        w, h, c, data = png.read_bmp(path)
    except (OSError, ValueError):
        return None
    _x0, y0, _x1, y1 = imgdiff.scale_region(region, w, h)
    sx = w / 480.0
    cols = []
    for px in range(region[0], region[0] + region[2]):
        lit = any(all(data[(y * w + x) * c + k] >= 0xc0 for k in range(3))
                  for x in range(int(px * sx), max(int(px * sx) + 1, int((px + 1) * sx))) for y in range(y0, y1))
        cols.append("#" if lit else ".")
    return "".join(cols)


def title_match(path, region, runs):
    """True when a shot's lit columns in region are within TITLE_MAX_MISMATCH of runs (positive lit, negative
    dark), None when the shot cannot be read."""
    cols = title_columns(path, region)
    if cols is None:
        return None
    want = "".join(("#" if n > 0 else ".") * abs(n) for n in runs)
    return sum(a != b for a, b in zip(cols, want)) <= TITLE_MAX_MISMATCH


def destroyed_title(path):
    """True when a shot shows the "SHIP DESTROYED" title (within TITLE_MAX_MISMATCH columns of DESTROYED_TITLE),
    None when the shot cannot be read."""
    return title_match(path, TITLE_REGION, DESTROYED_TITLE)


# The end panels' digits are drawn like a seven-segment display: the segments each digit lights (a top, b top
# right, c bottom right, d bottom, e bottom left, f top left, g middle, h a centre stroke in the upper half). This
# font's middle bar sits below the centre, its 6 has no top bar, its 9 no bottom bar, and its 1 is a centre stroke
# with a flag at the top left, a foot and a tick at the right.
DIGIT_SEGMENTS = {"0": "abcdef", "1": "acdgh", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "cdefg",
                  "7": "abc", "8": "abcdefg", "9": "abcfg"}
SEGMENT_BOXES = {"a": (0.35, 0.65, 0.0, 0.1), "b": (0.62, 1.0, 0.2, 0.4), "c": (0.75, 1.0, 0.72, 0.85),
                 "d": (0.35, 0.65, 0.9, 1.0), "e": (0.0, 0.25, 0.72, 0.85), "f": (0.0, 0.38, 0.2, 0.4),
                 "g": (0.35, 0.65, 0.45, 0.62), "h": (0.4, 0.6, 0.2, 0.4)}


def read_digits(path, region):
    """The number drawn in region of a shot (light digits on a darker panel), '?' for a glyph that matches no digit
    within one segment; None when the shot cannot be read or the region holds no glyph."""
    try:
        w, h, c, data = png.read_bmp(path)
    except (OSError, ValueError):
        return None
    x0, y0, x1, y1 = imgdiff.scale_region(region, w, h)

    def lit(x, y):
        i = (y * w + x) * c
        return min(data[i], data[i + 1], data[i + 2]) >= 0x98

    cols = [x for x in range(x0, x1) if any(lit(x, y) for y in range(y0, y1))]
    glyphs, run = [], []
    for x in cols:
        if run and x != run[-1] + 1:
            glyphs.append(run)
            run = []
        run.append(x)
    if run:
        glyphs.append(run)
    boxes = []
    for g in glyphs:
        ys = [y for y in range(y0, y1) if any(lit(x, y) for x in g)]
        boxes.append((g[0], g[-1], ys[0], ys[-1]))
    if not boxes:
        return None
    tall = max(b[3] - b[2] for b in boxes)
    out = ""
    for gx0, gx1, gy0, gy1 in boxes:
        if gy1 - gy0 < 0.6 * tall:
            continue                  # a decimal point
        gw, gh = gx1 - gx0 + 1, gy1 - gy0 + 1
        segs = ""
        for s, (u0, u1, v0, v1) in SEGMENT_BOXES.items():
            xs = range(gx0 + int(u0 * gw), gx0 + max(int(u0 * gw) + 1, int(u1 * gw)))
            ys = range(gy0 + int(v0 * gh), gy0 + max(int(v0 * gh) + 1, int(v1 * gh)))
            if any(lit(x, y) for x in xs for y in ys):
                segs += s
        dist = {d: len(set(segs) ^ set(want)) for d, want in DIGIT_SEGMENTS.items()}
        best = min(dist, key=dist.get)
        out += best if dist[best] <= 1 and list(dist.values()).count(dist[best]) == 1 else "?"
    return out or None


def classify_stall(race, tail, shield, destroyed=None):
    """Why the ship stopped, from the stall shot (its title and shield bar), the probe's shield, the contacts and
    the last TAIL_S s of the trace:
      eliminated by damage  the shot shows the "SHIP DESTROYED" title, or the probe's shield is 0 or less (the
                            shield bar alone does not decide: it reads 0% whenever the HUD is hidden)
      stuck on geometry     a contact from 3 s before the last progress on (the stall began there)
      off the line          more than 25 m from the AI line, or moving more than 90 degrees off it
      stopped               none of these (the speed ran down without a contact)
    with the mean speed of the last TAIL_S s (at rest, or crawling)."""
    last = tail[-1] if tail else None
    since = race.best_total - 3.0
    hits = [c for c in race.contacts if c[0] >= since]
    sh = "no stall shot" if shield is None else f"shield bar {shield:.0%}"
    kmh = sum(r[4] for r in tail) / len(tail) if tail else 0.0
    moving = (f"{'at rest' if kmh < 2.0 else f'crawling at {kmh:.0f} km/h'} with Cross "
              f"{'held' if last and last[8] else 'up'}")
    probe = race.shield is not None and race.shield <= 0.0
    if destroyed or probe:
        why = (['"SHIP DESTROYED" title'] if destroyed else []) + (
            [f"probe shield {race.shield:.1f}"] if race.shield is not None else [])
        return f"eliminated by damage ({', '.join(why)}; {sh}; {moving})"
    if hits:
        t, _lp, d, lost, off = hits[0]
        return (f"stuck on geometry (contact at {d:.0f} m, {t:.1f} s, {lost:.0f} km/h lost, {off:+.0f} m off the "
                f"line; {moving}; {sh})")
    if last and (abs(last[6]) > 25.0 or (not math.isnan(last[7]) and abs(last[7]) > math.pi / 2)):
        return (f"off the line ({last[6]:+.0f} m from the line, heading {math.degrees(last[7]):+.0f} deg off; "
                f"{moving}; {sh})")
    return f"stopped (no contact since the last progress; {moving}; {sh})"


def tail_text(tail):
    """The last TAIL_S s of the trace, one row a second: `race time/distance/km/h/offset/lx`."""
    rows, nxt = [], None
    for r in reversed(tail):
        if nxt is None or r[1] <= nxt:
            rows.append(r)
            nxt = r[1] - 1.0
    return "last 5 s (t/dist/kmh/off/lx): " + " ".join(
        f"{r[1]:.1f}/{r[3]:.0f}/{r[4]:.0f}/{r[6]:+.0f}/{r[5]:+.2f}" for r in reversed(rows))


def prepare_game_dir(cell):
    """out/sweep/game/<cell>: EBOOT.ELF and disc.iso linked to game/, an empty memory stick (one per cell, so cells
    of different tracks can run side by side)."""
    game = os.path.join(ROOT, OUT, "game", cell)
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


class Leg:
    """What steers one race on a track: the steering table's frame steps, its DistTable or Tuner, the AI line."""

    def __init__(self, track, opts, single):
        self.track = track
        drive = (opts.drive if single else None) or os.path.join(DRIVE_DIR, f"{track}.txt")
        if not os.path.exists(os.path.join(ROOT, drive)):
            sys.exit(f"campaign_sweep: no steering table {drive}")
        drive_steps, dist_steps, follow = parse_drive(drive, drop_shots=False)
        line_path = (opts.line if single else None) or (follow[0] if follow else
                                                          os.path.join(LINES_DIR, f"{track}.csv"))
        self.line_path = line_path
        self.ai_line = (AiLine(os.path.join(ROOT, line_path)) if os.path.exists(os.path.join(ROOT, line_path))
                        else None)
        self.tuner = None
        if opts.tune or follow:
            if self.ai_line is None:
                sys.exit(f"campaign_sweep: no racing line {line_path} (tools/pp_lines.py {track})")
            wn, preview, params = (opts.wn, opts.preview, {}) if opts.tune or not follow else follow[1:]
            params = dict(params, **dict(kv.split("=", 1) for kv in opts.set))
            wn, preview = float(params.pop("wn", wn)), float(params.pop("preview", preview))
            unknown = set(params) - set(Tuner.PARAMS)
            if unknown:
                sys.exit(f"campaign_sweep: unknown follow option {', '.join(sorted(unknown))} "
                         f"({', '.join(Tuner.PARAMS)})")
            self.tuner = Tuner(self.ai_line, wn, preview, **params)
            drive_steps, dist_steps = [s for s in drive_steps if not s[1].startswith("axis")], []
        self.drive_steps = drive_steps
        self.table = DistTable(dist_steps) if dist_steps else None
        self.how = (f"{'tune' if opts.tune else 'follow'} {line_path} (coverage {self.ai_line.covered:.0%}, "
                    f"{self.ai_line.length:.0f} m, {self.tuner.describe()})" if self.tuner else
                    f"drive {drive} ({len(drive_steps)} frame steps, {len(dist_steps)} distance steps)")


def run_cell(mode, track, opts):
    m = MODES[mode]
    cell = f"{mode}-{track}"
    out = os.path.join(ROOT, OUT)
    end = m.get("end", "results")
    fps = m.get("fps", 60)
    no_damage = opts.no_damage and end != "destroyed"     # Zone ends by the ship's destruction
    names = m.get("races", {}).get(track, [track])
    legs = [Leg(t, opts, len(names) == 1) for t in names]
    script = os.path.join(out, f"{cell}.script.txt")
    log = os.path.join(out, f"{cell}.log")
    live = os.path.join(out, f"{cell}.live")
    shots = os.path.join(out, cell)
    shutil.rmtree(shots, ignore_errors=True)
    os.makedirs(shots)
    frames = opts.frames or m["frames"].get(track, DEFAULT_FRAMES)
    steps = build_script(mode, track, legs[0].drive_steps, frames)
    with open(script, "w") as f:
        f.write("".join(f"{fr}:{a}\n" for fr, a in steps))
    open(live, "w").close()
    exit_frame = m["throttle"] + frames
    game = prepare_game_dir(cell)
    env = dict(os.environ)
    env.update({"PURE_GAME_DIR": game, "PURE_LIST_STUBS": "1", "PURE_STRICT_HLE": "1",
                "PURE_EXIT_AT_FRAME": str(exit_frame), "PURE_INPUT_SCRIPT": ";".join(f"{fr}:{a}" for fr, a in steps),
                "PURE_SCREENSHOT_DIR": shots, "PURE_SCREENSHOT_EVERY": "0", "PURE_WATCH_SHIP": "1",
                "PSPRECOMP_NO_INTERPRETER": "1", "PURE_INPUT_LIVE": live, "PURE_FRAME_LOG": "60"})
    env.pop("PURE_TEST_NO_DAMAGE", None)
    if no_damage:
        env["PURE_TEST_NO_DAMAGE"] = "1"      # a test switch: the player's shield refilled every flip
    if opts.no_damage and not no_damage:
        print(f"[sweep] {cell}: --no-damage ignored: {mode} ends when the ship is destroyed", flush=True)
    for k, leg in enumerate(legs):
        print(f"[sweep] {cell}: {f'race {k + 1} {leg.track}: ' if len(legs) > 1 else ''}{leg.how}", flush=True)
    print(f"[sweep] {cell}: exit at flip {exit_frame}{', no damage (test switch)' if no_damage else ''}", flush=True)
    port = Port(env, log, max(60.0, exit_frame / 15.0), opts.max_lines)
    trace = open(os.path.join(out, f"{cell}.trace.csv"), "w", buffering=1)
    trace.write("frame,clock,lap,dist,x,z,kmh,lx,offset,psi,thrust,airbrake,shield,race\n")
    # Flip-counted waits keep their times in the 30-flip modes.
    shot_every = max(15, SHOT_EVERY * fps // 60)
    ref_flips = REF_SHOT_FLIPS * fps // 60
    slow_gap = 600 * fps // 60

    leg = 0
    tuner, table, ai_line = legs[0].tuner, legs[0].table, legs[0].ai_line
    race = Race(m["laps"], refilled=no_damage)
    done = []                         # Tournament: (track, Race) of each race whose results panel came up
    state = {"outcome": None, "detail": "", "quit": False, "quit_at": None, "halt": None, "lx": 0.0,
             "steering": True, "thrust": 1, "airbrake": 0, "frame": 0, "steady": 0, "prev_shot": None,
             "results": None, "last_shot": None, "ref": False, "slow_shots": 0, "slow_at": -10**9,
             "advance": None, "paused": 0, "zones": None, "destroyed": 0.0}
    shots_seen = {}                   # name -> frame
    analysed = set()
    sent = []                         # --tune: (lap, dist, lx) of every lx step sent
    tail = []                         # the trace rows of the last TAIL_S s of race time
    contacts = []                     # (race number, contact) of the races before this one
    stall_shot = os.path.join(shots, "stall.bmp")
    triggers = {-1: ["lefttrigger"], 1: ["righttrigger"], 2: ["lefttrigger", "righttrigger"]}
    geo = tuner or (Tuner(ai_line, 1.0, 0.0) if ai_line else None)     # the line's heading for the trace

    def send(text):
        with open(live, "a") as f:
            f.write(text + "\n")

    def stop(why_outcome, why):
        if state["outcome"] is None:
            state["outcome"], state["detail"] = why_outcome, why
        if state["quit"] or state["quit_at"]:
            return
        if why_outcome == "STALL":
            # A picture of what stopped the ship first; the loop quits once it is written (or 4 s on).
            send("0:shot stall")
            state["quit_at"] = time.time() + 4.0
            return
        send("0:quit")
        state["quit"] = True

    def set_controls(airbrake, thrust):
        if airbrake != state["airbrake"]:
            for axis in triggers.get(state["airbrake"], []):
                # -1, not 0: a trigger axis set to 0 stays pressed (task 016: L and R held after a release with 0
                # braked the ship to a 10 km/h crawl with Cross held, in three runs).
                send(f"0:axis {axis} -1")
            for axis in triggers.get(airbrake, []):
                send(f"0:axis {axis} 1")
            state["airbrake"] = airbrake
        if thrust != state["thrust"]:
            # Cross is held by the route's `pad a BUDGET`; a 1-frame press releases it early, a long one holds it.
            # The hold goes 2 frames after the line is read: the port reads the live file every 10 flips, and a
            # release and a hold read together would otherwise run in the same frame, the release of the 1-frame
            # press then lifting Cross for good (task 016: a ship left coasting to a stop at 266 m).
            send("0:pad a 1" if not thrust else f"2:pad a {frames + 1000}")
            state["thrust"] = thrust

    def race_text(r):
        return (f"{r.laps_done} laps: " + ", ".join(f"{t:.1f}" for t in r.lap_times) + " s")

    def on_results(path, name):
        """The results panel of the race is up (two steady shots of its TOTAL label)."""
        state["results"] = path
        if end != "standings":
            stop("PASS", f"results screen at flip {shots_seen[name]} ({race_text(race)}; {race.total:.1f} s at "
                         f"the shot)")
            return
        # Tournament: answer ENTER TAG and the standings with Cross until the next race (or, after the last, the
        # final standings) is up.
        done.append((legs[leg].track, race, race.total))
        print(f"[sweep] {cell}: race {leg + 1} ({legs[leg].track}) results at flip {shots_seen[name]} "
              f"({race_text(race)}; {race.contact_text()}{race.damage_text()})", flush=True)
        set_controls(0, 0)
        state["advance"] = {"last": race.frame, "shot": race.frame, "presses": 0, "final": leg == len(legs) - 1,
                            "steady": 0, "prev": None, "prev_name": None, "pressed": set(), "candidate": False}

    def next_race(frame):
        """A new player object after a race's results: the next race of the tournament is loading."""
        nonlocal leg, tuner, table, ai_line, geo, race
        contacts.extend((leg + 1, c) for c in race.contacts)
        leg += 1
        tuner, table, ai_line = legs[leg].tuner, legs[leg].table, legs[leg].ai_line
        geo = tuner or (Tuner(ai_line, 1.0, 0.0) if ai_line else None)
        race = Race(m["laps"], refilled=no_damage)
        tail.clear()
        state.update({"advance": None, "steering": True, "lx": 0.0, "ref": False, "slow_shots": 0,
                      "slow_at": -10**9, "steady": 0, "prev_shot": None, "results": None})
        for k in ("_last_req", "ref"):
            shots_seen.pop(k, None)
        analysed.discard("ref")
        state.pop("absorbed", None)   # the absorb and use timers count race time, which starts again
        state.pop("used", None)
        send("0:axis leftx 0")
        set_controls(0, 1)            # Cross held through the countdown and the race
        print(f"[sweep] {cell}: race {leg + 1} ({legs[leg].track}) player object at flip {frame}", flush=True)

    def on_ship(s, text):
        adv = state["advance"]
        if adv and adv["candidate"]:
            # The first line of a new player object: the next race when the ship is on its grid (lap 0, clock 0);
            # the replay behind the results panel runs with lap 65537.
            adv["candidate"] = False
            if int(s[11]) == 0 and float(s[2]) == 0.0:
                next_race(int(s[1]))
        race.feed(s, text)
        state["frame"] = race.frame
        if not race.started or state["quit"] or state["advance"]:
            return
        if (end == "destroyed" and race.finished_frame is None and race.shield is not None
                and race.shield <= 0.0):
            race.finished_frame = race.frame          # Zone: the shield has run out, the end panel follows
            state["destroyed"] = race.total
        if race.finished_frame is not None:
            if state["steering"]:
                send("0:axis leftx 0")
                set_controls(0, 1)
                state["steering"], state["lx"] = False, 0.0
            if end == "session" and not state["paused"]:
                # Free Play has no last lap: pause, END SESSION (two DOWN), Cross.
                set_controls(0, 0)
                send("0:pad start")
                send(f"{PAUSE_GAP}:pad dpdown")
                send(f"{2 * PAUSE_GAP}:pad dpdown")
                send(f"{3 * PAUSE_GAP}:pad a")
                state["paused"] = race.frame
        elif tuner is not None:
            raw = tuner.demand(race)
            lx = round(tuner.stick(raw), 2)
            if abs(lx - state["lx"]) >= LX_STEP or (lx == 0.0 and state["lx"] != 0.0):
                send(f"0:axis leftx {lx:.2f}")
                state["lx"] = lx
                sent.append((race.laps_done, race.dist, lx))
                tuner.note(race.total, lx)
            airbrake, thrust = 0, 1
            if tuner.airbrake > 0.0 and not tuner.recovering:
                side = 1 if raw > 0 else -1
                hold = tuner.airbrake * (0.8 if state["airbrake"] == side else 1.0)
                airbrake = side if abs(raw) > hold else 0
            if tuner.lift > 0.0 and not tuner.recovering:
                need = tuner.corner_need(race)
                thrust = 0 if need > tuner.lift * (0.9 if not state["thrust"] else 1.0) else 1
            if tuner.vmax > 0.0 and not tuner.recovering:
                over = state["airbrake"] == 2
                if race.kmh > tuner.vmax - (10.0 if over else 0.0):
                    airbrake, thrust = 2, 0
            set_controls(airbrake, thrust)
        elif table is not None:
            acts = table.start(race.dist) if race.prev_dist is None else table.crossed(race.prev_dist, race.dist)
            for a in acts:
                send(f"0:{a}")
                if a.startswith("axis leftx"):
                    state["lx"] = float(a.split()[2])
        if (tuner is not None and tuner.absorb > 0.0 and race.finished_frame is None
                and race.total - state.get("absorbed", 0.0) >= tuner.absorb):
            send(f"0:pad x {int(tuner.hold)}")   # Square: "Absorb pickup" in the default controls
            state["absorbed"] = race.total
        if (tuner is not None and tuner.use > 0.0 and race.finished_frame is None
                and race.total - state.get("used", 0.0) >= tuner.use):
            send("0:pad b 4")                     # Circle: "Use pickup" in the default controls
            state["used"] = race.total
        if not state["ref"] and race.frame - race.start_frame >= ref_flips:
            send("0:shot ref")
            state["ref"] = True
        off = ai_line.offset(race.x, race.z, race.dist) if ai_line else float("nan")
        if race.contacts and math.isnan(race.contacts[-1][4]):
            if state["airbrake"] == 2:
                race.contacts.pop()               # the vmax brake, not a contact
            else:
                race.contacts[-1][4] = off
        if (race.finished_frame is None and race.total > 5.0 and race.kmh < 30.0 and state["slow_shots"] < 3
                and race.frame - state["slow_at"] >= slow_gap):
            send(f"0:shot slow{race.frame}")         # what slowed the ship down (for the stall diagnosis)
            state["slow_shots"] += 1
            state["slow_at"] = race.frame
        psi = (wrap_angle(geo.line_heading(race.dist) - math.atan2(race.vz, race.vx))
               if geo and race.kmh > 10.0 else float("nan"))
        shield = race.shield if race.shield is not None else float("nan")
        row = (race.frame, race.total, race.laps_done, race.dist, race.kmh, state["lx"], off, psi, state["thrust"],
               state["airbrake"], shield)
        tail.append(row)
        while tail[0][1] < race.total - TAIL_S:
            tail.pop(0)
        trace.write(f"{race.frame},{race.total:.3f},{race.laps_done},{race.dist:.2f},{race.x:.2f},{race.z:.2f},"
                    f"{race.kmh:.1f},{state['lx']:.2f},{off:.2f},{psi:.3f},{state['thrust']},{state['airbrake']},"
                    f"{shield:.1f},{leg + 1}\n")

    def handle(text):
        s = SHIP_RE.search(text)
        if s:
            on_ship(s, text)
            return
        p = PLAYER_RE.search(text)
        if p:
            if state["advance"] and not state["advance"]["final"] and state["outcome"] is None:
                state["advance"]["candidate"] = True
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

    def analyse(name, path):
        """A live shot taken after the finish (`f...`) or between races (`a...`)."""
        if name.startswith("a") and state["advance"]:
            adv = state["advance"]
            if not adv["final"]:
                return
            # After the last race: the final standings are the first screen that stays still (two shots in a row
            # with no Cross between them equal over the whole screen) once ENTER TAG is answered (three presses);
            # the results panel never is (it is drawn over a moving replay).
            steady = (adv["prev"] is not None and adv["prev_name"] not in adv["pressed"]
                      and same_region(path, adv["prev"], (0, 0, 480, 272)))
            adv["steady"] = adv["steady"] + 1 if steady and adv["presses"] >= 3 else 0
            adv["prev"], adv["prev_name"] = path, name
            print(f"[sweep] {cell}: shot {name}: still {steady} ({adv['steady']} in a row, {adv['presses']} "
                  f"presses)", flush=True)
            if adv["steady"] >= 1 and state["outcome"] is None:
                state["results"] = path
                stop("PASS", f"final standings at flip {shots_seen[name]}")
            return
        if race.finished_frame is None or not name.startswith("f"):
            return
        if end == "destroyed":
            title = destroyed_title(path)
            state["steady"] = state["steady"] + 1 if title else 0
            print(f"[sweep] {cell}: shot {name}: SHIP DESTROYED title {title} ({state['steady']} in a row)",
                  flush=True)
            if state["steady"] >= 2 and state["outcome"] is None:
                state["results"] = path
                state["zones"] = read_digits(path, ZONES_VALUE)
                stop("PASS", f"zone end panel at flip {shots_seen[name]}: TOTAL ZONES CLEAR {state['zones']}; "
                             f"destroyed at flip {race.finished_frame} ({state['destroyed']:.1f} s of race clock, "
                             f"{race.dist:.0f} m), {race.laps_done} laps")
            return
        if end == "session":
            # Only shots from after END SESSION's Cross count (the pause menu is still, and the TOTAL label rule
            # must not take it for a panel). With laps done the session ends on FREE PLAY SESSION RESULTS (the laps
            # newest first, TOTAL LAPS, ENTER TAG): the TOTAL label rule below. With none it goes straight to the
            # RETURN TO MAIN MENU banner.
            if shots_seen[name] < state["paused"] + 3 * PAUSE_GAP + 10:
                return
            if title_match(path, BANNER_REGION, MENU_BANNER):
                print(f"[sweep] {cell}: shot {name}: RETURN TO MAIN MENU banner", flush=True)
                if state["outcome"] is None:
                    state["results"] = path
                    stop("PASS", f"END SESSION's RETURN TO MAIN MENU banner at flip {shots_seen[name]} "
                                 f"({race_text(race)}; {race.total:.1f} s of race clock)")
                return
        var = region_variance(path, RESULTS_TOTAL)
        prev = state["prev_shot"]
        steady = prev is not None and same_region(path, prev, RESULTS_TOTAL)
        state["prev_shot"] = path
        state["steady"] = state["steady"] + 1 if steady and var >= RESULTS_MIN_VARIANCE else 0
        print(f"[sweep] {cell}: shot {name}: TOTAL label variance {var:.0f}, steady {steady} "
              f"({state['steady']} in a row)", flush=True)
        if state["steady"] >= 1 and state["outcome"] is None and not state["advance"]:
            on_results(path, name)

    while True:
        for text in port.read(0.05):
            handle(text)
        outcome = state["outcome"]
        if state["halt"] and outcome is None:
            stop("HALT", state["halt"])
        if state["outcome"] is None and not race.started and not state["advance"] and not done \
                and state["frame"] > m["throttle"] + NO_RACE_FLIPS:
            stop("NO RACE", f"no race clock by flip {state['frame']}: the menu route did not reach the race")
        if state["outcome"] is None and race.started and end != "destroyed":
            if race.finished_frame is None and race.stalled_for() >= opts.stall:
                stop("STALL", f"no progress for {race.stalled_for():.1f} s of race clock")
        if state["quit_at"] and not state["quit"]:
            if os.path.exists(stall_shot):
                state["quit_at"] = min(state["quit_at"], time.time() + 0.5)   # let the writer finish
            if time.time() >= state["quit_at"]:
                send("0:quit")
                state["quit"] = True
        # Between races: a shot every shot_every flips, Cross every ADVANCE_EVERY (10 flips after a shot).
        adv = state["advance"]
        if adv and state["outcome"] is None and not state["quit"]:
            if state["frame"] - adv["shot"] >= shot_every:
                adv["shot"] = state["frame"]
                name = f"a{leg + 1}-{state['frame']}"
                send(f"0:shot {name}")
                if state["frame"] - adv["last"] >= ADVANCE_EVERY:
                    adv["last"] = state["frame"]
                    send("10:pad a")
                    adv["presses"] += 1
                    adv["pressed"].add(name)
        # Live shots once the race is finished (and for tuning, every --shots-every flips).
        if state["outcome"] is None and not state["quit"] and race.started and not adv:
            every = shot_every if race.finished_frame is not None else opts.shots_every
            prefix = "f" if race.finished_frame is not None else "t"
            if every and race.frame - shots_seen.get("_last_req", -10**9) >= every:
                send(f"0:shot {prefix}{race.frame}")
                shots_seen["_last_req"] = race.frame
        # Analyse the shots that are written.
        for name in sorted((n for n in shots_seen if not n.startswith("_")), key=lambda n: shots_seen[n]):
            path = os.path.join(shots, name + ".bmp")
            if name in analysed or not os.path.exists(path):
                continue
            try:
                imgdiff.load_rgb(path)
            except (OSError, ValueError):
                continue            # still being written
            analysed.add(name)
            state["last_shot"] = path
            if name == "ref":
                print(f"[sweep] {cell}: shot ref: shield bar {shield_text(path)}", flush=True)
                continue
            try:
                analyse(name, path)
            except (OSError, ValueError):
                pass
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
        if not race.started and not done:
            outcome, detail = "NO RACE", "no race clock in the probe: the menu route did not reach the race"
        elif port.timed_out:
            outcome, detail = "TIMEOUT", f"wall-clock deadline reached (exit {code})"
        else:
            outcome, detail = "TIMEOUT", f"flip budget {frames} used up"
    # Convert the live shots, and keep the cell's picture: the results screen, else the last shot taken.
    for name in sorted(os.listdir(shots)):
        if name.endswith(".bmp"):
            try:
                w, h, c, data = png.read_bmp(os.path.join(shots, name))
                png.write_png(os.path.join(shots, name[:-4] + ".png"), w, h, c, data)
            except (OSError, ValueError):
                pass
    pick = state["results"] or (stall_shot if os.path.exists(stall_shot) else None) or state["last_shot"]
    if pick:
        w, h, c, data = png.read_bmp(pick)
        png.write_png(os.path.join(out, f"{cell}.png"), w, h, c, data)
    if opts.tune:
        tuned = os.path.join(out, f"{cell}.tuned.txt")
        lap, n = write_tuned(tuned, cell, sent, race.laps_done, opts)
        print(f"[sweep] {cell}: {n} steps of lap {lap + 1} -> {tuned}", flush=True)
    current = not done or done[-1][1] is not race      # the race the cell stopped in has no results panel
    if len(legs) > 1:
        # Tournament: each race's laps and contacts, and where the cell stopped.
        races = [f"race {k + 1} {t}: {race_text(r)}, {r.contact_text()}{r.damage_text()}"
                 for k, (t, r, _total) in enumerate(done)]
        if current:
            races.append(f"race {leg + 1} {legs[leg].track} (stopped here): {race_text(race)}, "
                         f"{race.contact_text()}{race.damage_text()}" if race.started else
                         f"race {leg + 1} {legs[leg].track} (stopped here): not started")
        detail += "; " + "; ".join(races)
    elif race.started:
        detail += f"; {race.contact_text()}{race.damage_text()}"
    if outcome == "STALL":
        shield = shield_fraction(stall_shot) if os.path.exists(stall_shot) else None
        destroyed = destroyed_title(stall_shot) if os.path.exists(stall_shot) else None
        detail = f"{classify_stall(race, tail, shield, destroyed)}; {detail}; {tail_text(tail)}"
        with open(os.path.join(out, f"{cell}.stall.csv"), "w") as f:
            f.write("frame,clock,lap,dist,kmh,lx,offset,psi,thrust,airbrake,shield\n")
            for r in tail:
                f.write(",".join(f"{v:.3f}" if isinstance(v, float) else str(v) for v in r) + "\n")
    contacts.extend((leg + 1, c) for c in race.contacts)
    with open(os.path.join(out, f"{cell}.contacts.csv"), "w") as f:
        f.write("clock,lap,dist,kmh_lost,offset,race\n")
        for k, (t, lp, d, kmh, o) in contacts:
            f.write(f"{t:.2f},{lp},{d:.1f},{kmh:.0f},{o:.1f},{k}\n")
    laps = sum(r.laps_done for _t, r, _total in done) + (race.laps_done if current else 0)
    clock = sum(total for _t, _r, total in done) + (race.total if current else 0.0)
    row = {"mode": mode, "track": track, "outcome": outcome, "frame": state["frame"], "laps": laps,
           "clock": clock, "detail": detail if outcome == "PASS" else f"{detail}; last: {race.line.strip()}",
           "seconds": elapsed, "tune": opts.tune, "no_damage": no_damage}
    print(f"[sweep] {cell}: {outcome}{' (no damage)' if no_damage else ''} at flip {state['frame']}, "
          f"{laps} laps, race time {clock:.1f} s, {elapsed:.0f} s: {row['detail']}", flush=True)
    return row


def write_summary(rows):
    """Merges this invocation's rows into the summary, under a lock (sweeps of other cells may run alongside)."""
    with open(os.path.join(ROOT, OUT, "summary.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _write_summary(rows)


def _write_summary(rows):
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
        outcome = r["outcome"] + (" (no damage)" if r.get("no_damage") else "")
        kept[(r["mode"], r["track"])] = (f"| {r['mode']} | {r['track']} | {outcome} | {r['frame']} | "
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
    p.add_argument("--frames", type=int, default=None)
    p.add_argument("--stall", type=float, default=20.0)
    p.add_argument("--drive")
    p.add_argument("--shots-every", type=int, default=0)
    p.add_argument("--max-lines", type=int, default=400000)
    p.add_argument("--tune", action="store_true")
    p.add_argument("--line")
    p.add_argument("--wn", type=float, default=1.0)
    p.add_argument("--preview", type=float, default=0.3)
    p.add_argument("--export-line", metavar="OUT")
    p.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    p.add_argument("--out", default=OUT)
    p.add_argument("--list", action="store_true")
    p.add_argument("--no-damage", action="store_true")
    opts = p.parse_args(argv)
    bad = [kv for kv in opts.set if "=" not in kv]
    if bad:
        p.error(f"--set takes KEY=VALUE, not {bad[0]!r}")
    if opts.mode not in MODES:
        p.error(f"unknown mode {opts.mode!r} (modes: {', '.join(MODES)})")
    known = MODES[opts.mode]["tracks"]
    opts.tracks = opts.tracks or list(known)
    for t in opts.tracks:
        if t not in known:
            p.error(f"unknown track {t!r} for {opts.mode} (tracks: {', '.join(known)})")
    if (opts.drive or opts.tune or opts.line or opts.export_line) and len(opts.tracks) != 1:
        p.error("--drive, --tune, --line and --export-line take one track")
    if (opts.drive or opts.tune or opts.line) and MODES[opts.mode].get("races"):
        p.error(f"--drive, --tune and --line take a one-race cell, not {opts.mode}")
    return opts


def main(argv=None):
    global OUT
    opts = parse(sys.argv[1:] if argv is None else argv)
    OUT = opts.out
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
