#!/usr/bin/env python3
"""The accuracy scorecard (task 044): how close the port is to the original, in numbers that can be re-run.

  tools/scorecard.py [--quick | --full] [--only CATEGORY[,CATEGORY...]] [--out DIR] [--tracks TRACK[,...]]
  tools/scorecard.py --refresh-references [CATEGORY] [--tracks TRACK[,...]]
  tools/scorecard.py --selftest

Six categories, each measured on the port headless and compared with PPSSPP (the oracle) or with the game's own
facts, each row graded `faithful`, `close` or `differs` by the threshold the row names (docs/scorecard.md's header
lists them all); a category's grade is its worst graded row. Rows that cannot be graded say why instead: `no
reference` (the PPSSPP side has not been taken: --refresh-references), `not measured` (no instrument exists) and
`accepted (D-011)` (a difference Erik decided to keep); they do not count towards the category's grade.

  pictures      tools/frame_regress.sh (its 18 scenes, from its summary.txt) and the three extra first-race frames
                of docs/fidelity.md item 3 (Blue Ridge, Sinucit, Sebenco Climb) against ref/*.png
  trajectories  per circuit (the 12, Vector, PURE_TEST_UNLOCK_ALL=1), the player's ship with Cross held from the
                countdown and no steering: the port's PURE_WATCH_GRID records against PPSSPP's race records, sampled
                as tools/pp_lines.py samples them, clock-aligned over the first 20 s; the AI ships only if two PPSSPP
                runs of Vineta K agree
  timing        flips per race-clock second per mode; the two-vblank stretches of a follower-driven Vineta K race
                against PPSSPP's (tools/fidelity_audit.py --ppsspp-race); the race load's length (D-011)
  audio         the main menu's music over 60 s and one Single Race per league (Vineta K, Sinucit, Sagarmatha):
                the port's PURE_AUDIO_WAV against PPSSPP's audio dump (tools/audio_compare.py as a library)
  saves         the profile tools/save_roundtrip.sh's first run makes (main_menu.txt on an empty stick, made here
                headless) against PPSSPP's save of the same profile (NAME0000)
  coverage      the campaign matrix's cell results (tools/fidelity_audit.py; reused from out/035-wip/fidelity, never
                run here), the 278 imports by state, the GE commands the framework still ignores

--quick (the default; a few minutes) runs pictures, timing, saves and coverage, timing from the matrix's cached cells.
--full adds trajectories and audio (15 headless port runs) and runs one sweep cell per mode for timing (Single
Race, Time Trial and Free Play on Vineta K, Zone 1; Tournament stays the matrix's): about 25 minutes. --only runs
the named categories (with --full's sources, or --quick's beside --quick). Results go to DIR (default
out/scorecard): scorecard.json,
scorecard.md and every run's route, log and capture; a --full run of every category also writes docs/scorecard.md.
--tracks limits the trajectory and audio circuits (a check, not a scorecard).

--refresh-references [CATEGORY] takes the PPSSPP side through tools/ppsspp/ppsspp_ctl.py (as a library, and its
`run` command) and tools/fidelity_audit.py --ppsspp-race, one PPSSPP at a time, and stores it under ref/scorecard/
(git-ignored), each file's SHA-256 in ref/scorecard/manifest.json and in ref/README.md's table: trajectories (13
runs, about 35 minutes; the three audio circuits' runs dump their sound too), audio (the main menu and the three
races, about 12 minutes), saves (about 2 minutes; the save is moved off PPSSPP's memory stick), timing (about 6
minutes). Pictures use the ref/*.png of tasks 006 and 035; coverage has no PPSSPP side.

--selftest checks every grader and the report on synthetic inputs (no game, no PPSSPP): PASS (exit 0) or FAIL.
Every port run is headless and silent (tools/run_boot.py --shell headless --backend metal, or the tools' own
headless defaults), on an empty memory stick of its own, one game at a time. Exit 0 when the scorecard was written
(whatever the grades), 1 when a run could not start, 2 on bad arguments.
"""
import argparse, bisect, hashlib, json, math, os, re, shutil, struct, subprocess, sys, tempfile, time, wave
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "ppsspp"))
import campaign_sweep as cs      # noqa: E402  (routes and picks of the sweep; used as it is)
import fidelity_audit as fa      # noqa: E402  (scan_log, ppsspp_stretches, the regexes; used as it is)
import audio_compare as ac       # noqa: E402  (Track, locate; used as it is)
import pp_lines as pl            # noqa: E402  (the race-record layout and its parser; used as it is)
import ppsspp_ctl as pc          # noqa: E402  (the PPSSPP driver; used as it is)
import png                       # noqa: E402

CATEGORIES = ["pictures", "trajectories", "timing", "audio", "saves", "coverage"]
QUICK = ["pictures", "timing", "saves", "coverage"]
REF = ROOT / "ref" / "scorecard"
MANIFEST = REF / "manifest.json"
README = ROOT / "ref" / "README.md"
README_BEGIN = "<!-- scorecard references: begin (written by tools/scorecard.py --refresh-references) -->"
README_END = "<!-- scorecard references: end -->"
DATA_DIR = "out/data/scorecard"
PP_ROUTES = ROOT / "tools" / "ppsspp" / "routes"
RTC = 1767225600                       # the driver's RTC base, 2026-01-01 00:00 UTC (docs/ppsspp.md)

FAITHFUL, CLOSE, DIFFERS = "faithful", "close", "differs"
NO_REF, NOT_MEASURED, ACCEPTED = "no reference", "not measured", "accepted (D-011)"
RANK = {FAITHFUL: 0, CLOSE: 1, DIFFERS: 2}

TRACKS = cs.ALPHA + cs.BETA + cs.CLASSIC
TRACK_NAMES = {"vineta_k": "Vineta K", "modesto_heights": "Modesto Heights", "chenghou_project": "Chenghou Project",
               "blue_ridge": "Blue Ridge", "sinucit": "Sinucit", "citta_nuova": "Citta Nuova",
               "sebenco_climb": "Sebenco Climb", "sol_2": "Sol 2", "karbonis": "Karbonis", "sagarmatha": "Sagarmatha",
               "manor_top": "Manor Top", "mandrashee": "Mandrashee"}
AUDIO_TRACKS = ["vineta_k", "sinucit", "sagarmatha"]   # one Single Race per league (the brief)
PLAYER = 7                             # the player's race record on a Single Race grid (docs/tracks.md)

# ---------------------------------------------------------------------------------------------------- thresholds
PICTURE_FAITHFUL = 0.005               # within this of the measured column (lower is better: closer to PPSSPP)
TRAJ_HORIZON = 20.0                    # s of race clock compared
TRAJ_GAP = 1.0                         # m: "first differ by more than 1 m"
TRAJ_FAITHFUL, TRAJ_CLOSE = 1.5, 5.0   # m, the largest distance over the horizon
RATE_FAITHFUL, RATE_CLOSE = 0.02, 0.05  # flips per race-clock second, relative to 60 or 30
STRETCH_FAITHFUL, STRETCH_CLOSE = 1, 3  # two-vblank stretches, the difference in count
CORR_FAITHFUL, CORR_CLOSE = 0.6, 0.3   # --locate correlation (the brief)
RMS_FAITHFUL, RMS_CLOSE = (0.95, 1.05), (0.9, 1.1)
ACTIVE_FAITHFUL, ACTIVE_CLOSE = 0.98, 0.9   # share of seconds where both or neither are active
CLIP_FAITHFUL, CLIP_CLOSE = 0.0001, 0.001   # the port's clipped fraction above PPSSPP's

# The extra first-race frames of docs/fidelity.md item 3: the sweep's picks after main_menu.txt + single_race.txt,
# the frame of the first full HUD, the PPSSPP reference, tol, limit and the measured value (task 044's three
# headless runs on the Metal backend, 2026-10-07; the limit by docs/verification.md's re-baselining rule: the
# largest run plus 0.015 to 0.02, rounded up to a hundredth). Sinucit and Sebenco Climb compare two weather-mist
# states (difference 3, task 038), so their fractions are high whatever the renderer does.
EXTRA_SCENES = [
    # scene              track            frame  reference                   tol  limit  measured  unlock
    ("blue_ridge_hud",    "blue_ridge",    6016, "ref/blue_ridge_hud.png",    32, 0.05,  0.0247,  False),
    ("sinucit_hud",       "sinucit",       6016, "ref/sinucit_hud.png",       32, 0.14,  0.1163,  True),
    ("sebenco_climb_hud", "sebenco_climb", 6018, "ref/sebenco_climb_hud.png", 32, 0.34,  0.3207,  True),
]

# PPSSPP's routes to each circuit's grid (tools/ppsspp/routes, task 035) and the vblank of the first full-HUD frame
# (ref/README.md, runs J and K). Cross is held from the first READY frame, 58 vblanks after it (7213 on Vineta K,
# vineta_k_hold_cross.txt), to the end: "Cross held from the start".
PP_HUD = {"vineta_k": 7155, "modesto_heights": 7158, "chenghou_project": 7158, "blue_ridge": 7158,
          "sinucit": 7662, "citta_nuova": 7664, "sebenco_climb": 7670, "sol_2": 7652,
          "karbonis": 7636, "sagarmatha": 7638, "manor_top": 7640, "mandrashee": 7640}
READY_AFTER_HUD = 58
PP_TEAM_PRESS = 6700                   # vineta_k_start.txt's TEAM SELECTION Cross (the race load starts)
PORT_TEAM_PRESS = 5700                 # single_race.txt's
PORT_THROTTLE = 6100                   # single_race.txt's Cross hold
FADE_FLIPS = 57                        # the race-start fade: 57 flips at two vblanks on both (docs/fidelity.md)
PORT_RACE_FRAMES = 7800                # to about 25 s of race clock (GO at about flip 6253)
PORT_AUDIO_FRAMES = 10200              # to about 65 s
PP_RACE_SECONDS, PP_AUDIO_SECONDS = 25.0, 65.0
PP_HOLD_VBLANKS = 9000                 # Cross held this long from READY (the runs stop at their race clock first)
AUDIO_WINDOW = 60                      # s compared

# The GE commands docs/fidelity.md found no draw of the game using (written once at start-up or with their reset
# value; the scissor stands in for the region; TEXENVCOLOR only matters to the blend texture function, which no
# race draw uses; anti-aliasing does nothing on a PSP; TEXSYNC and TEXFLUSH order texture writes).
GE_UNUSED = {0x15, 0x16, 0x25, 0x26, 0x28, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x36, 0x37, 0x38,
             0x50, 0xCA, 0xCB, 0xCC, 0xE6} | set(range(0xF0, 0xFA))
# The profile's own answers that are constants rather than models (src/profile/pure_profile.cpp, with the reason
# beside each): GPI reads 0 as on retail, the ready-queue rotation is a yield hint the scheduler covers, the
# thread-id list reports no ids.
PROFILE_CONSTANTS = ["sceKernelGetGPI", "sceKernelRotateThreadReadyQueue", "sceKernelGetThreadmanIdList"]

SFO_FIELDS = ["TITLE", "SAVEDATA_TITLE", "SAVEDATA_DETAIL", "CATEGORY", "PARENTAL_LEVEL", "SAVEDATA_FILE_LIST"]
SAVE_FOLDER = "UCUS98612P0000"
DATA_FILE = "PROFILE.BIN"

SHIP_RE = fa.SHIP_T_RE
PLAYER_RE = fa.PLAYER_RE
CALL_FLIP_RE = re.compile(r"^\[call\] sceDisplay:0x289D82FE .* t=(\d+)$")
GE_COUNT_RE = re.compile(r"^GE commands ignored: (\d+) distinct")
UNVERIFIED_RE = re.compile(r"^\[\w+\] (\w+) \(UNVERIFIED")


# ------------------------------------------------------------------------------------------------------ helpers

def row(measure, port, reference, difference, grade, rule, note="", data=None):
    return {"measure": measure, "port": str(port), "reference": str(reference), "difference": str(difference),
            "grade": grade, "rule": rule, "note": note, "data": data or {}}


def worst(grades):
    """A category's grade: the worst of its graded rows; with none, `no reference` or `not measured`."""
    graded = [g for g in grades if g in RANK]
    if graded:
        return max(graded, key=RANK.get)
    return NO_REF if NO_REF in grades else (ACCEPTED if ACCEPTED in grades else NOT_MEASURED)


def grade_low(value, faithful, close):
    """Lower is better: faithful below `faithful`, close below `close`."""
    return FAITHFUL if value < faithful else CLOSE if value < close else DIFFERS


def grade_at_least(value, faithful, close):
    return FAITHFUL if value >= faithful else CLOSE if value >= close else DIFFERS


def grade_band(value, faithful, close):
    return (FAITHFUL if faithful[0] <= value <= faithful[1] else
            CLOSE if close[0] <= value <= close[1] else DIFFERS)


def grade_picture(fraction, measured, limit):
    if fraction is None:
        return DIFFERS
    return FAITHFUL if fraction <= measured + PICTURE_FAITHFUL else CLOSE if fraction <= limit else DIFFERS


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def rel(p):
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        s = str(p)
        home = str(Path.home())
        return "~" + s[len(home):] if s.startswith(home + "/") else s


def clean_env(extra=None):
    """The environment for a port run: no PURE_* or PSPRECOMP_* switch inherited from the shell."""
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("PURE_") or k.startswith("PSPRECOMP_")) or k in ("PURE_ROOT", "PURE_MAIN_CHECKOUT")}
    env.update(extra or {})
    return env


def main_checkout():
    if os.environ.get("PURE_MAIN_CHECKOUT"):
        return Path(os.environ["PURE_MAIN_CHECKOUT"])
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "worktree", "list", "--porcelain"], capture_output=True,
                             text=True).stdout
        first = next(ln[len("worktree "):] for ln in out.splitlines() if ln.startswith("worktree "))
        return Path(first)
    except (OSError, StopIteration):
        return ROOT


def commit_label():
    try:
        c = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True,
                           text=True).stdout.strip() or "unknown"
        dirty = subprocess.run(["git", "-C", str(ROOT), "diff", "--quiet", "HEAD"]).returncode != 0
        return c + ("+changes" if dirty else "")
    except OSError:
        return "unknown"


def say(msg):
    print(f"[scorecard] {msg}", flush=True)


def fmt(v, digits=4):
    return "-" if v is None else f"{v:.{digits}f}"


def other_game():
    sys.path.insert(0, str(ROOT / "tools"))
    import run_boot
    return run_boot.other_games()


WAITED = 0.0                           # seconds spent waiting for someone else's game or PPSSPP


def wait_until(busy, what, limit=3600.0):
    """Waits while busy() names something (another game, another PPSSPP, a profile on PPSSPP's stick): one game at a
    time, and a process this tool did not start is never touched. False after `limit` seconds."""
    global WAITED
    t0, said = time.time(), False
    while True:
        b = busy()
        if not b:
            if said:
                say(f"{what}: free after {time.time() - t0:.0f} s")
                WAITED += time.time() - t0
            return True
        if not said:
            say(f"waiting: {what} ({b})")
            said = True
        if time.time() - t0 > limit:
            say(f"gave up waiting after {limit:.0f} s: {what} ({b})")
            return False
        time.sleep(10)


def wait_game():
    return wait_until(other_game, "another PureNative is running")


def ppsspp_profiles():
    d = pc.MEMSTICK / "PSP" / "SAVEDATA"
    return sorted(p.name for p in d.glob("UCUS98612P*")) if d.exists() else []


def wait_ppsspp():
    """PPSSPP is one instance (its debugger port, its ini, its memory stick): wait for it to be free and for its stick
    to hold no profile (the routes make a new one)."""
    return (wait_until(pc.ppsspp_pids, "PPSSPPSDL is running") and
            wait_until(ppsspp_profiles, "PPSSPP's memory stick holds a profile save") and
            wait_until(pc.ppsspp_pids, "PPSSPPSDL is running"))


# ------------------------------------------------------------------------------------------------- port runs

class Ctx:
    def __init__(self, out, categories, full, tracks):
        self.out = Path(out)
        self.categories = categories
        self.full = full
        self.tracks = tracks
        self.logs = {}            # name -> log path of this invocation's runs
        self.race_runs = {}       # track -> (log, wav or None)
        self.stick = self.out / "game"

    def make_stick(self):
        g = self.stick
        g.mkdir(parents=True, exist_ok=True)
        for name, target in (("EBOOT.ELF", ROOT / "game" / "EBOOT.ELF"),
                             ("disc.iso", Path(os.path.realpath(ROOT / "game" / "disc.iso")))):
            link = g / name
            if not link.is_symlink():
                link.symlink_to(target)
        shutil.rmtree(g / "ms0", ignore_errors=True)
        (g / "ms0" / "PSP" / "SAVEDATA").mkdir(parents=True)
        return g


def write_route(path, steps):
    """`FRAME:ACTION` lines, by frame; at a shared frame a shot goes first (the input script sorts stably)."""
    ordered = sorted(steps, key=lambda s: (s[0], 0 if s[1].startswith("shot") else 1))
    Path(path).write_text("\n".join(f"{f}:{a}" for f, a in ordered) + "\n")


def port_run(ctx, name, steps, frames, env=None, shots=False):
    """One headless, silent run on an empty memory stick: (log, run_boot's exit code, the last frame reached)."""
    runs = ctx.out / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    route = runs / f"{name}.route.txt"
    write_route(route, steps)
    log = runs / f"{name}.log"
    game = ctx.make_stick()
    wait_game()
    cmd = [sys.executable, str(ROOT / "tools" / "run_boot.py"), "--shell", "headless", "--backend", "metal",
           "--script", str(route), "--frames", str(frames), "--seconds", str(max(120, frames // 20)),
           "--max-lines", "600000", "--data-dir", DATA_DIR, "--env", f"PURE_GAME_DIR={game}"]
    if shots:
        cmd += ["--shots", str(runs / f"{name}.shots")]
    for k, v in (env or {}).items():
        cmd += ["--env", f"{k}={v}"]
    cmd.append(str(log))
    t0 = time.time()
    with open(runs / f"{name}.stdout", "w") as f:
        rc = subprocess.run(cmd, cwd=ROOT, env=clean_env(), stdout=f, stderr=subprocess.STDOUT).returncode
    reached = log.exists() and f"[pure] exit at frame {frames}" in log.read_text(errors="replace")
    say(f"run {name}: exit {rc}, frame {frames} {'reached' if reached else 'NOT reached'}, {time.time() - t0:.0f} s")
    ctx.logs[name] = log
    return log, rc, reached


def race_steps(track, hold_flips):
    """The sweep's Single Race route to a circuit (main_menu.txt, single_race.txt, the picks), Cross held from 6100
    for hold_flips."""
    steps = cs.parse_drive(cs.MENU_ROUTE)[0] + cs.parse_drive(cs.MODES["single_race"]["route"])[0]
    m = cs.MODES["single_race"]
    for at, n in cs.picks("single_race", track):
        steps += [(at + k * m["downs_gap"], "pad dpdown") for k in range(n)]
    return [(f, f"pad a {hold_flips}") if f == PORT_THROTTLE and a.startswith("pad a") else (f, a) for f, a in steps]


def port_race(ctx, track, audio):
    """The port's straight-on race on a circuit (Cross from the countdown, no steering, every circuit with the unlock
    switch), with the grid, ship and flip probes, and PURE_AUDIO_WAV when audio is wanted. Cached per invocation."""
    if track in ctx.race_runs and (not audio or ctx.race_runs[track][1]):
        return ctx.race_runs[track]
    frames = PORT_AUDIO_FRAMES if audio else PORT_RACE_FRAMES
    wav = ctx.out / "runs" / f"race-{track}.wav" if audio else None
    env = {"PURE_TEST_UNLOCK_ALL": "1", "PURE_WATCH_GRID": "1", "PURE_WATCH_SHIP": "1",
           "PURE_TRACE_CALLS": "sceDisplay:0x289D82FE"}
    if wav:
        env["PURE_AUDIO_WAV"] = str(wav)
    log, rc, reached = port_run(ctx, f"race-{track}", race_steps(track, frames - PORT_THROTTLE + 100), frames, env)
    ctx.race_runs[track] = (log, wav if reached or (wav and wav.exists()) else None)
    return ctx.race_runs[track]


# -------------------------------------------------------------------------------------------- reference files

def manifest():
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {}


def ref_note(path):
    """`ref/scorecard/...` with the first 12 hex digits of its SHA-256 as the manifest records it."""
    m = manifest().get(rel(path))
    return f"{rel(path)} ({m['sha256'][:12]})" if m else rel(path)


def missing(category):
    return f"missing: tools/scorecard.py --refresh-references {category}"


# ------------------------------------------------------------------------------------------------------ pictures

def parse_regress_summary(text):
    """tools/frame_regress.sh's summary.txt: {scene: {frame, fraction, limit, tol, measured, result}}."""
    out = {}
    for line in text.splitlines():
        w = line.split()
        if len(w) >= 8 and w[1].isdigit() and re.fullmatch(r"[\d.]+", w[3] or ""):
            try:
                frac = float(w[2]) if w[2] != "-" else None
                out[w[0]] = {"frame": int(w[1]), "fraction": frac, "limit": float(w[3]), "tol": int(w[4]),
                             "measured": float(w[5]), "result": " ".join(w[7:])}
            except ValueError:
                continue
    return out


def imgdiff_fraction(cap, ref, tol):
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "imgdiff.py"), str(cap), str(ref), "--tol", str(tol),
                        "--max-frac", "1", "--json"], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)["fraction"]
    except (ValueError, KeyError):
        return None


def cat_pictures(ctx):
    rows = []
    regress = ctx.out / "regress"
    wait_game()
    t0 = time.time()
    with open(ctx.out / "regress.stdout", "w") as f:
        rc = subprocess.run([str(ROOT / "tools" / "frame_regress.sh"), "--out", str(regress)], cwd=ROOT,
                            env=clean_env(), stdout=f, stderr=subprocess.STDOUT).returncode
    say(f"frame_regress.sh: exit {rc}, {time.time() - t0:.0f} s")
    for name in ("main_menu+single_race", "main_menu+time_trial", "main_menu+zone"):
        if (regress / f"{name}.log").exists():
            ctx.logs[f"regress-{name}"] = regress / f"{name}.log"
    summary = regress / "summary.txt"
    scenes = parse_regress_summary(summary.read_text()) if summary.exists() else {}
    if not scenes:
        rows.append(row("the frame regression suite", "no summary", "-", "-", DIFFERS, "",
                        f"tools/frame_regress.sh exit {rc}; see {rel(ctx.out / 'regress.stdout')}"))
    rule = f"faithful within {PICTURE_FAITHFUL} of the measured column, close up to the limit, differs above it"
    for scene, s in scenes.items():
        frac = s["fraction"]
        rows.append(row(f"{scene} (frame {s['frame']}, tol {s['tol']})", fmt(frac),
                        f"measured {s['measured']:.4f}, limit {s['limit']:.2f}",
                        "-" if frac is None else f"{frac - s['measured']:+.4f}",
                        grade_picture(frac, s["measured"], s["limit"]), rule,
                        "" if frac is not None else s["result"],
                        {"scene": scene, "fraction": frac, "measured": s["measured"], "limit": s["limit"]}))
    for scene, track, frame, ref, tol, limit, measured, unlock in EXTRA_SCENES:
        refp = ROOT / ref
        steps = race_steps(track, 3000) + [(frame, f"shot {scene}")]
        log, rc, reached = port_run(ctx, f"picture-{scene}", steps, frame + 30,
                                    {"PURE_TEST_UNLOCK_ALL": "1"} if unlock else {}, shots=True)
        cap = ctx.out / "runs" / f"picture-{scene}.shots" / f"{scene}.png"
        measure = f"{scene} (frame {frame}, tol {tol}; docs/fidelity.md item 3)"
        if not refp.exists():
            rows.append(row(measure, "-", f"{ref} missing (copy the main checkout's ref/)", "-", NO_REF, rule))
            continue
        frac = imgdiff_fraction(cap, refp, tol) if cap.exists() else None
        note = "the weather mist's phase differs (difference 3, task 038)" if track != "blue_ridge" else ""
        rows.append(row(measure, fmt(frac), f"measured {measured:.4f}, limit {limit:.2f}",
                        "-" if frac is None else f"{frac - measured:+.4f}", grade_picture(frac, measured, limit),
                        rule, note if frac is not None else f"no capture (run exit {rc})",
                        {"scene": scene, "fraction": frac, "measured": measured, "limit": limit}))
    return rows


# -------------------------------------------------------------------------------------------------- trajectories

def first_lap(samples):
    """A ship's samples in time order up to its lap clock's first restart (the clock runs from GO through the first
    crossing of the start line and restarts at the next, docs/tracks.md), with strictly increasing clocks."""
    out = []
    for p in samples:
        if out and p[0] < out[-1][0] - 1.0:
            break
        if not out or p[0] > out[-1][0]:
            out.append(p)
    return out


def read_pp_samples(path):
    """A PPSSPP race-record CSV (tools/pp_lines.py's columns): {ship: [(clock, x, y, z)]}, the first lap clock."""
    ships = {}
    with open(path) as f:
        next(f)
        for line in f:
            w = line.strip().split(",")
            if len(w) < 11:
                continue
            k, c = int(w[1]), float(w[2])
            ships.setdefault(k, []).append((c, float(w[3]), float(w[4]), float(w[5])))
    return {k: first_lap(s) for k, s in ships.items()}


def port_series(rows):
    """pp_lines.port_samples rows (flip order) -> {ship: [(clock, x, y, z)]}, the first lap clock."""
    ships = {}
    for r in rows:
        ships.setdefault(r[1], []).append((r[2], r[3], r[4], r[5]))
    return {k: first_lap(s) for k, s in ships.items()}


def interp(series, clocks, c):
    """The position at clock c by linear interpolation of a (clock, x, y, z) series, or None outside it."""
    i = bisect.bisect_left(clocks, c)
    if i < len(clocks) and clocks[i] == c:
        return series[i][1:]
    if i == 0 or i >= len(clocks):
        return None
    (c0, *p0), (c1, *p1) = series[i - 1], series[i]
    if c1 - c0 > 0.1:                    # a hole of more than a few flips: no position there
        return None
    t = (c - c0) / (c1 - c0)
    return tuple(a + (b - a) * t for a, b in zip(p0, p1))


def compare_series(port, pp, horizon=TRAJ_HORIZON, gap=TRAJ_GAP):
    """Clock-aligned distance between a port series (every flip) and PPSSPP samples (a few a frame apart) over
    (0, horizon]: samples, the first clock over `gap`, the largest distance and its clock, the port's last clock."""
    clocks = [p[0] for p in port]
    n, first, top, top_at = 0, None, 0.0, None
    for c, x, y, z in pp:
        if not 0.0 < c <= horizon:
            continue
        q = interp(port, clocks, c)
        if q is None:
            continue
        d = math.dist((x, y, z), q)
        n += 1
        if d > top:
            top, top_at = d, c
        if first is None and d > gap:
            first = c
    return {"samples": n, "first_over": first, "max": top, "max_at": top_at,
            "port_last": clocks[-1] if clocks else None, "pp_last": max((p[0] for p in pp), default=None)}


def deterministic(run1, run2, ships):
    """Two PPSSPP runs of a track: the samples at the same race clock (to the ms) of each named ship. Returns
    (common samples, the largest distance between them)."""
    n, top = 0, 0.0
    for k in ships:
        a = {round(c, 3): (x, y, z) for c, x, y, z in run1.get(k, [])}
        for c, x, y, z in run2.get(k, []):
            p = a.get(round(c, 3))
            if p is not None and 0.0 < c <= TRAJ_HORIZON:
                n += 1
                top = max(top, math.dist(p, (x, y, z)))
    return n, top


def trajectory_row(name, cmp, ref_desc, ships_desc="the player"):
    if cmp["samples"] == 0:
        return row(f"{name}: {ships_desc}", "no samples", ref_desc, "-", DIFFERS,
                   "", f"the port's clock reached {fmt(cmp['port_last'], 1)} s, PPSSPP's {fmt(cmp['pp_last'], 1)} s")
    first = "never" if cmp["first_over"] is None else f"{cmp['first_over']:.2f} s"
    short = cmp["port_last"] is not None and cmp["port_last"] < TRAJ_HORIZON - 0.5
    return row(f"{name}: {ships_desc}, the first clock more than {TRAJ_GAP:g} m apart; the largest distance over "
               f"{TRAJ_HORIZON:g} s", f"first over {TRAJ_GAP:g} m: {first}", ref_desc,
               f"{cmp['max']:.2f} m at {cmp['max_at']:.2f} s", grade_low(cmp["max"], TRAJ_FAITHFUL, TRAJ_CLOSE),
               f"faithful under {TRAJ_FAITHFUL} m, close under {TRAJ_CLOSE} m",
               f"{cmp['samples']} PPSSPP samples" + (f"; the port's run ended at {cmp['port_last']:.1f} s" if short else ""),
               {k: v for k, v in cmp.items()})


def cat_trajectories(ctx):
    rows = []
    ref_dir = REF / "trajectories"
    run1, run2 = ref_dir / "vineta_k.csv", ref_dir / "vineta_k.run2.csv"
    ai = None
    if run1.exists() and run2.exists():
        a, b = read_pp_samples(run1), read_pp_samples(run2)
        n, top = deterministic(a, b, [k for k in range(8) if k != PLAYER])
        ai = n >= 50 and top < 0.01
        rows.append(row("PPSSPP's AI ships: two runs of Vineta K at the same race clock", f"{n} common samples",
                        "the same positions (under 0.01 m)", f"largest {top:.3f} m",
                        FAITHFUL if ai else NOT_MEASURED, "deterministic when every common sample is under 0.01 m apart",
                        "the AI rows follow" if ai else
                        "PPSSPP's AI is not repeatable with the pinned RTC base, so the AI ships are not compared "
                        "(no seed hunting, the brief)", {"common": n, "max": top}))
    for track in ctx.tracks:
        name = TRACK_NAMES[track]
        log, wav = port_race(ctx, track, track in AUDIO_TRACKS and "audio" in ctx.categories)
        prow, player = pl.port_samples(log) if log.exists() else ([], PLAYER)
        port = port_series(prow)
        ref = ref_dir / f"{track}.csv"
        if not ref.exists():
            rows.append(row(f"{name}: the player", f"{len(port.get(player, []))} port records", missing("trajectories"),
                            "-", NO_REF, ""))
            continue
        pp = read_pp_samples(ref)
        rows.append(trajectory_row(name, compare_series(port.get(player, []), pp.get(PLAYER, [])),
                                   f"PPSSPP, {ref_note(ref)}"))
        if ai:
            per = {k: compare_series(port.get(k, []), pp.get(k, [])) for k in range(8) if k != player}
            k, w = max(per.items(), key=lambda kv: kv[1]["max"])
            firsts = [c["first_over"] for c in per.values() if c["first_over"] is not None]
            merged = dict(w, first_over=min(firsts) if firsts else None,
                          samples=sum(c["samples"] for c in per.values()))
            rows.append(trajectory_row(name, merged, f"PPSSPP, {rel(ref)}", f"the 7 AI ships (worst: ship {k})"))
    return rows


# -------------------------------------------------------------------------------------------------------- timing

def race_rate(path):
    """Flips and race-clock seconds over the race windows of a sweep log (`[pure] ship` lines): every pair of ship
    lines of one race on consecutive flips whose clock moved (a lap restart counts the new clock), up to the finish
    (lap bit 16). A gap in the lines is a pause (the probe prints only what changes; the clock stands still), not
    counted."""
    flips, secs, races = 0, 0.0, 0
    prev = None
    with open(path, errors="replace") as f:
        for line in f:
            if PLAYER_RE.match(line):
                prev = None
                continue
            m = SHIP_RE.match(line)
            if not m:
                continue
            frame, clock, lap = int(m[1]), float(m[3]), int(m[6])
            if clock <= 0.0 or lap & 0x10000:
                prev = None
                continue
            if prev is None:
                races += 1
            else:
                dc = clock - prev[1] if clock >= prev[1] - 1.0 else clock
                if dc > 0.0 and frame == prev[0] + 1:
                    flips += 1
                    secs += dc
            prev = (frame, clock)
    return flips, secs, races


def load_length(flips, press_us):
    """The race load in game time: from the TEAM SELECTION confirm to the first flip of the race-start fade, the
    FADE_FLIPS two-vblank flips before the race's first run of one-vblank flips. Returns (load s, press to race
    start s) or None."""
    after = [u for u in flips if u >= press_us - 20000]
    for i in range(len(after) - 21):
        if all(after[i + j + 1] - after[i + j] < 25000 for j in range(20)):
            if i < FADE_FLIPS:
                return None
            return (after[i - FADE_FLIPS] - press_us) / 1e6, (after[i] - press_us) / 1e6
    return None


def port_flip_times(log):
    out = []
    with open(log, errors="replace") as f:
        for line in f:
            m = CALL_FLIP_RE.match(line.strip())
            if m:
                out.append(int(m[1]))
    return out


def pp_flip_times(log):
    out = []
    with open(log, errors="replace") as f:
        for line in f:
            m = fa.PP_LOG_RE.search(line)
            if m and m[1] == "FLIP":
                out.append(int(m[2]))
    return out


def matrix_dir():
    """The matrix's cell results: out/035-wip/fidelity here or in the main checkout, else out/fidelity."""
    for base in (ROOT, main_checkout()):
        for sub in ("out/035-wip/fidelity", "out/fidelity"):
            d = base / sub
            if (d / "cells").is_dir() and any((d / "cells").glob("*.json")):
                return d
    return None


def matrix_cells(d):
    cells = []
    for p in sorted((d / "cells").glob("*.json")):
        try:
            r = json.loads(p.read_text())
        except ValueError:
            continue
        r["_log"] = d / "sweep" / f"{r['cell']}.log"
        cells.append(r)
    return cells


MODE_FPS = {"single_race": 60, "tournament": 60, "time_trial": 30, "free_play": 30, "zone": 30}
MODE_NAMES = {"single_race": "Single Race", "tournament": "Tournament", "time_trial": "Time Trial",
              "free_play": "Free Play", "zone": "Zone"}
FRESH_CELLS = [("single_race", "vineta_k"), ("time_trial", "vineta_k"), ("free_play", "vineta_k"), ("zone", "zone_1")]


def sweep_cell(ctx, mode, track):
    out = ctx.out / "sweep"
    name = cs.cell_name(mode, track)
    wait_game()
    t0 = time.time()
    with open(ctx.out / f"sweep-{name}.stdout", "w") as f:
        subprocess.run([sys.executable, str(ROOT / "tools" / "campaign_sweep.py"), mode, track, "--no-damage",
                        "--out", str(out)], cwd=ROOT, env=clean_env(), stdout=f, stderr=subprocess.STDOUT)
    outcome = "?"
    for line in (ctx.out / f"sweep-{name}.stdout").read_text(errors="replace").splitlines():
        m = fa.SWEEP_LINE_RE.match(line.strip())
        if m and m[1] == name:
            outcome = m[2]
    say(f"sweep cell {name}: {outcome}, {time.time() - t0:.0f} s")
    log = out / f"{name}.log"
    return (log, outcome) if log.exists() else None


def cat_timing(ctx):
    rows = []
    mdir = matrix_dir()
    cells = matrix_cells(mdir) if mdir else []
    fresh = {}
    if ctx.full:
        for mode, track in FRESH_CELLS:
            got = sweep_cell(ctx, mode, track)
            if got:
                fresh[mode] = got
    rule = f"faithful within {RATE_FAITHFUL:.0%} of the reference, close within {RATE_CLOSE:.0%}"
    for mode in ("single_race", "tournament", "time_trial", "free_play", "zone"):
        ref = MODE_FPS[mode]
        if mode in fresh:
            log, outcome = fresh[mode]
            flips, secs, _ = race_rate(log)
            source = f"this run's sweep cell {cs.cell_name(mode, 'vineta_k' if mode != 'zone' else 'zone_1')} ({outcome})"
        else:
            logs = [c["_log"] for c in cells if c["mode"] == mode and c.get("class", "vector") == "vector"
                    and c["_log"].exists()]
            if not logs:
                rows.append(row(f"{MODE_NAMES[mode]}: flips per race-clock second", "-", ref, "-", NOT_MEASURED, rule,
                                "no matrix cells: `python3 tools/fidelity_audit.py` (about 4 h) makes out/fidelity/cells"))
                continue
            flips = secs = 0
            for lg in logs:
                f_, s_, _ = race_rate(lg)
                flips, secs = flips + f_, secs + s_
            source = f"the matrix's {len(logs)} {MODE_NAMES[mode]} cells at Vector ({rel(mdir)}, run 2026-10-06)"
        if secs <= 0:
            rows.append(row(f"{MODE_NAMES[mode]}: flips per race-clock second", "-", ref, "-", DIFFERS, rule,
                            f"no race clock in {source}"))
            continue
        rate = flips / secs
        rows.append(row(f"{MODE_NAMES[mode]}: flips per race-clock second", f"{rate:.2f}", ref,
                        f"{(rate - ref) / ref:+.2%}", grade_low(abs(rate - ref) / ref, RATE_FAITHFUL, RATE_CLOSE), rule,
                        f"{flips} flips over {secs:.1f} s of race clock, {source}"
                        + ("; the two-vblank stretches (the game's own) lower it by half their share" if ref == 60 else ""),
                        {"flips": flips, "seconds": secs, "rate": rate}))
    # The two-vblank stretches of a follower-driven Vineta K race.
    srule = f"faithful when the counts differ by at most {STRETCH_FAITHFUL}, close by at most {STRETCH_CLOSE}"
    pp_sum = REF / "timing" / "ppsspp" / "vineta_k" / "summary.json"
    port_log, port_src = None, ""
    if "single_race" in fresh:
        port_log, port_src = fresh["single_race"][0], "this run's sweep cell single_race-vineta_k"
    else:
        c = next((c for c in cells if c["cell"] == "single_race-vineta_k"), None)
        if c and c["_log"].exists():
            port_log, port_src = c["_log"], f"the matrix's single_race-vineta_k ({rel(mdir)})"
    port_st = fa.scan_log(port_log, 60)["stretches"] if port_log else None
    port_txt = "-" if port_st is None else f"{len(port_st)} ({', '.join(str(s['flips']) for s in port_st)} flips)"
    if not pp_sum.exists():
        rows.append(row("two-vblank stretches over a follower-driven Vineta K race", port_txt, missing("timing"), "-",
                        NO_REF, srule, port_src))
    elif port_st is None:
        rows.append(row("two-vblank stretches over a follower-driven Vineta K race", "-", "-", "-", NOT_MEASURED, srule,
                        "no port race log (the matrix's cell or --full's sweep cell)"))
    else:
        pps = json.loads(pp_sum.read_text())["stretches"]
        d = len(port_st) - len(pps)
        rows.append(row("two-vblank stretches over a follower-driven Vineta K race", port_txt,
                        f"{len(pps)} ({', '.join(str(s['flips']) for s in pps)} flips), {ref_note(pp_sum)}", f"{d:+d}",
                        grade_low(abs(d), STRETCH_FAITHFUL + 1, STRETCH_CLOSE + 1), srule,
                        f"{port_src}; where they fall follows the weapons, which differ run to run on both",
                        {"port": len(port_st), "ppsspp": len(pps)}))
    # The race load (difference 6, accepted by D-011).
    if "vineta_k" in ctx.race_runs:
        log = ctx.race_runs["vineta_k"][0]
    else:
        env = {"PURE_TRACE_CALLS": "sceDisplay:0x289D82FE"}
        log, _, _ = port_run(ctx, "load-vineta_k", race_steps("vineta_k", 300), 6400, env)
    pf = port_flip_times(log) if log.exists() else []
    port_load = load_length(pf, pf[PORT_TEAM_PRESS - 1]) if len(pf) >= PORT_TEAM_PRESS else None
    pp_log = REF / "timing" / "ppsspp" / "vineta_k" / "ppsspp.log"
    lrule = "difference 6, decided by Erik (D-011): the faster loads stay; reported, not graded"
    measure = "the race load before Vineta K, in game time (TEAM SELECTION confirm to the race-start fade)"
    ptxt = "-" if not port_load else f"{port_load[0]:.2f} s (to the race's first one-vblank flip {port_load[1]:.2f} s)"
    if not pp_log.exists():
        rows.append(row(measure, ptxt, missing("timing"), "-", NO_REF, lrule))
    else:
        pp_load = load_length(pp_flip_times(pp_log), pc.vblank_us(PP_TEAM_PRESS))
        if not port_load or not pp_load:
            rows.append(row(measure, ptxt, "-" if not pp_load else f"{pp_load[0]:.2f} s", "-", NOT_MEASURED, lrule,
                            "the flips did not show the race-start fade"))
        else:
            rows.append(row(measure, ptxt, f"{pp_load[0]:.2f} s (to the race's first one-vblank flip "
                            f"{pp_load[1]:.2f} s), {ref_note(pp_log)}", f"{port_load[0] - pp_load[0]:+.2f} s", ACCEPTED,
                            lrule, f"port flips from {rel(log)}",
                            {"port": port_load[0], "ppsspp": pp_load[0]}))
    return rows


# --------------------------------------------------------------------------------------------------------- audio

def first_active(path, start, floor=100.0, seconds=200.0):
    """The time of the first 10 ms block above the floor at or after `start`."""
    t = ac.Track(str(path), start, seconds, floor, 10.0)
    for i, (rms, _zero) in enumerate(t.blocks):
        if rms > floor:
            return start + i * t.block_ms / 1000.0
    return None


def window_figures(path, start, seconds):
    t = ac.Track(str(path), start, seconds, 100.0, 10.0)
    return t


def locate_best(pp_wav, port_wav, t, length, guess_lo, guess_hi):
    try:
        at, corr = ac.locate(str(pp_wav), str(port_wav), f"{t}:{length}:{max(0.0, guess_lo)}:{guess_hi}")
    except ValueError:
        return None, 0.0
    return at - t, corr


def compare_windows(port_wav, pp_wav, port_start, offset, seconds):
    """Per-second figures of the two mixes over aligned windows: RMS ratio, the share of seconds where both or
    neither are active, clipped samples."""
    a = window_figures(port_wav, port_start, seconds)
    b = window_figures(pp_wav, port_start + offset, seconds)
    n = min(len(a.seconds), len(b.seconds))
    ratios = [a.seconds[i][0] / b.seconds[i][0] for i in range(n) if b.seconds[i][0] > 100.0]
    agree = sum(1 for i in range(n) if (a.seconds[i][0] > 100.0) == (b.seconds[i][0] > 100.0))
    return {"seconds": n, "rms_ratio": sum(ratios) / len(ratios) if ratios else None,
            "rms_ratio_range": (min(ratios), max(ratios)) if ratios else None,
            "share": agree / n if n else None, "port_clip": a.clipped, "port_total": a.total,
            "pp_clip": b.clipped, "pp_total": b.total}


def clip_grade(port_clip, port_total, pp_clip, pp_total):
    pf = port_clip / port_total if port_total else 0.0
    qf = pp_clip / pp_total if pp_total else 0.0
    return grade_low(pf - qf, CLIP_FAITHFUL, CLIP_CLOSE), pf, qf


def main_menu_steps():
    """main_menu.txt, then L every 20 s on MAIN MENU: the attract demo starts after 30 s without a new button
    (FUN_0894d4c8), and L makes no sound there (checked: the sceSas channel stays silent)."""
    steps = cs.parse_drive(cs.MENU_ROUTE)[0]
    return steps + [(f, "pad leftshoulder") for f in (4800, 5400, 6000, 6600)]


def cat_audio(ctx):
    rows = []
    adir = REF / "audio"
    crule = f"faithful at or above {CORR_FAITHFUL}, close at or above {CORR_CLOSE} (--locate, the same content)"
    rrule = f"faithful within {RMS_FAITHFUL[0]} to {RMS_FAITHFUL[1]}, close within {RMS_CLOSE[0]} to {RMS_CLOSE[1]}"
    # The main menu's music, 60 s.
    wav = ctx.out / "runs" / "main_menu.wav"
    log, rc, reached = port_run(ctx, "main_menu", main_menu_steps(), 6900, {"PURE_AUDIO_WAV": str(wav)})
    ref = adir / "main_menu.wav"
    ms = first_active(Path(f"{wav}.ch2.wav"), 100.0) if Path(f"{wav}.ch2.wav").exists() else None
    if not ref.exists():
        rows.append(row("main menu music, 60 s: correlation", "-", missing("audio"), "-", NO_REF, crule))
    elif ms is None:
        rows.append(row("main menu music, 60 s: correlation", "no music in the port's capture", rel(ref), "-",
                        DIFFERS, crule))
    else:
        start = ms + 1.0
        off, corr0 = locate_best(ref, wav, start + 4.0, 2.0, 60.0, 120.0)
        corrs = [corr0]
        offs = [off]
        for dt in (24.0, 44.0):
            o, c = locate_best(ref, wav, start + dt, 2.0, start + dt + off - 0.5, start + dt + off + 0.5)
            corrs.append(c)
            offs.append(o)
        spread = (max(offs) - min(offs)) * 1000 if None not in offs else None
        corr = min(corrs)
        rows.append(row("main menu music, 60 s from its start: --locate correlation (lowest of 3 two-second stretches)",
                        f"{corr:.3f}", f"PPSSPP's dump, {ref_note(ref)}", f"offset {off:+.5f} s (spread "
                        f"{fmt(spread, 1)} ms)", grade_at_least(corr, CORR_FAITHFUL, CORR_CLOSE), crule,
                        f"the port's music from {ms:.2f} s, PPSSPP's at {ms + off:.2f} s; correlations "
                        + ", ".join(f"{c:.3f}" for c in corrs), {"corr": corrs, "offsets": offs}))
        w = compare_windows(wav, ref, start, off, AUDIO_WINDOW)
        r = w["rms_ratio"]
        rows.append(row("main menu music, 60 s: mean per-second RMS ratio (port / PPSSPP)",
                        "-" if r is None else f"{r:.3f}", "1", "-" if r is None else f"{r - 1:+.3f}",
                        DIFFERS if r is None else grade_band(r, RMS_FAITHFUL, RMS_CLOSE), rrule,
                        "" if r is None else f"{w['seconds']} s, per second {w['rms_ratio_range'][0]:.3f} to "
                        f"{w['rms_ratio_range'][1]:.3f}", w))
    # One Single Race per league.
    arule = f"faithful at or above {ACTIVE_FAITHFUL:.0%}, close at or above {ACTIVE_CLOSE:.0%}"
    krule = (f"the port's clipped share at most PPSSPP's + {CLIP_FAITHFUL} faithful, + {CLIP_CLOSE} close")
    for track in [t for t in AUDIO_TRACKS if t in ctx.tracks]:
        name = TRACK_NAMES[track]
        log, pwav = port_race(ctx, track, True)
        ref = adir / f"{track}.wav"
        flips_ref = REF / "trajectories" / f"{track}.flips.txt"
        if not ref.exists() or not flips_ref.exists():
            rows.append(row(f"{name} race: music correlation", "-", missing("audio"), "-", NO_REF, crule))
            continue
        go_port = next((int(m[2]) / 1e6 for m in map(SHIP_RE.match, log.read_text(errors="replace").splitlines())
                        if m and float(m[3]) > 0.0), None) if log.exists() else None
        go_pp = next((u / 1e6 for u, c in read_flips(flips_ref) if c > 0.0), None)
        if pwav is None or go_port is None or go_pp is None:
            rows.append(row(f"{name} race: music correlation", "no race in the port's run", rel(ref), "-", DIFFERS,
                            crule))
            continue
        music = Path(f"{pwav}.ch2.wav")
        guess = go_pp - go_port
        found = []
        for dt in (10.0, 20.0, 30.0, 40.0, 50.0):
            o, c = locate_best(ref, music, go_port + dt, 2.0, go_port + dt + guess - 5.0, go_port + dt + guess + 5.0)
            found.append((c, o, dt))
        found.sort(reverse=True)
        best_c, best_o, _ = found[0]
        agree = [f for f in found if f[1] is not None and abs(f[1] - best_o) < 0.002]
        corr = sorted(c for c, _, _ in found)[len(found) // 2]
        rows.append(row(f"{name} race: the port's music channel in PPSSPP's mix (median of 5 two-second stretches "
                        "from GO + 10 s)", f"{corr:.3f}", f"PPSSPP's dump, {ref_note(ref)}",
                        f"offset {best_o:+.5f} s ({len(agree)} of 5 at it)", grade_at_least(corr, CORR_FAITHFUL, CORR_CLOSE),
                        crule, "the effects are louder than the music in a race, and the AI's differ: "
                        + ", ".join(f"{c:.2f}" for c, _, _ in sorted(found, key=lambda f: f[2])),
                        {"found": found}))
        w = compare_windows(pwav, ref, go_port, best_o, AUDIO_WINDOW)
        rows.append(row(f"{name} race: share of seconds where both mixes or neither are active ({AUDIO_WINDOW} s "
                        "from GO)", f"{w['share']:.2f}", "1", f"{w['share'] - 1:+.2f}",
                        grade_at_least(w["share"], ACTIVE_FAITHFUL, ACTIVE_CLOSE), arule,
                        f"mean RMS ratio {fmt(w['rms_ratio'], 3)} (reported: the AI ships differ)", w))
        g, pf, qf = clip_grade(w["port_clip"], w["port_total"], w["pp_clip"], w["pp_total"])
        rows.append(row(f"{name} race: clipped samples of the mix ({AUDIO_WINDOW} s from GO)",
                        f"{w['port_clip']} ({pf:.6f})", f"{w['pp_clip']} ({qf:.6f})", f"{pf - qf:+.6f}", g, krule))
    return rows


# --------------------------------------------------------------------------------------------------------- saves

def parse_sfo(data):
    """PARAM.SFO: {key: value}; SAVEDATA_FILE_LIST as the list of file names it holds."""
    if data[:4] != b"\0PSF":
        raise ValueError("no PSF header")
    keys, values, count = struct.unpack_from("<III", data, 8)
    out = {}
    for i in range(count):
        koff, fmt_, length, _maxlen, voff = struct.unpack_from("<HHIII", data, 20 + i * 16)
        key = data[keys + koff:data.index(b"\0", keys + koff)].decode()
        raw = data[values + voff:values + voff + length]
        if fmt_ == 0x0404:
            out[key] = struct.unpack("<I", raw[:4])[0]
        elif key == "SAVEDATA_FILE_LIST":
            out[key] = [raw[j:j + 13].split(b"\0")[0].decode("latin-1") for j in range(0, len(raw), 32)
                        if raw[j:j + 1] not in (b"", b"\0")]
        elif key == "SAVEDATA_PARAMS":
            out[key] = raw.hex()
        else:
            out[key] = raw.split(b"\0")[0].decode("utf-8", "replace")
    return out


def build_sfo(entries):
    """A PARAM.SFO for the self-test: entries [(key, value)], ints as 0x0404, bytes as binary, str as UTF-8."""
    keys, vals, index = b"", b"", b""
    for k, v in entries:
        if isinstance(v, int):
            raw, f_ = struct.pack("<I", v), 0x0404
        elif isinstance(v, bytes):
            raw, f_ = v, 0x0004
        else:
            raw, f_ = v.encode() + b"\0", 0x0204
        index += struct.pack("<HHIII", len(keys), f_, len(raw), len(raw), len(vals))
        keys += k.encode() + b"\0"
        vals += raw
    key_start = 20 + len(index)
    keys += b"\0" * (-len(keys) % 4)
    return (b"\0PSF" + struct.pack("<IIII", 0x101, key_start, key_start + len(keys), len(entries)) + index + keys
            + vals)


def compare_saves(port_dir, ref_dir):
    rows = []
    pf = {p.name: p.stat().st_size for p in Path(port_dir).iterdir() if p.is_file()}
    rf = {p.name: p.stat().st_size for p in Path(ref_dir).iterdir() if p.is_file()}
    rows.append(row("the save folder's files", ", ".join(sorted(pf)), ", ".join(sorted(rf)),
                    "the same" if set(pf) == set(rf) else f"port only {sorted(set(pf) - set(rf))}, PPSSPP only "
                    f"{sorted(set(rf) - set(pf))}", FAITHFUL if set(pf) == set(rf) else DIFFERS,
                    "faithful when the same names, differs otherwise"))
    for name in sorted(set(pf) | set(rf)):
        if name == DATA_FILE:
            continue
        a, b = pf.get(name), rf.get(name)
        rows.append(row(f"{name}: size", "-" if a is None else f"{a} bytes", "-" if b is None else f"{b} bytes",
                        "-" if a is None or b is None else f"{a - b:+d}", FAITHFUL if a == b else DIFFERS,
                        "faithful when the same size"))
    a, b = pf.get(DATA_FILE), rf.get(DATA_FILE)
    rows.append(row(f"{DATA_FILE} (the data file): size only", f"{a} bytes (plain)", f"{b} bytes (encrypted)",
                    "-" if a is None or b is None else f"{a - b:+d}", FAITHFUL if a == b else DIFFERS,
                    "faithful when the same size",
                    "difference 5: the PSP's savedata encryption (no-key mode); open, task 045 is on it"))
    try:
        ps = parse_sfo((Path(port_dir) / "PARAM.SFO").read_bytes())
        rs = parse_sfo((Path(ref_dir) / "PARAM.SFO").read_bytes())
    except (OSError, ValueError) as e:
        rows.append(row("PARAM.SFO fields", "-", "-", "-", DIFFERS, "", f"unreadable: {e}"))
        ps = rs = None
    if ps is not None:
        for key in SFO_FIELDS:
            a, b = ps.get(key), rs.get(key)
            same = a == b
            note = ""
            if key == "SAVEDATA_FILE_LIST":
                a = ", ".join(a) if a else "empty"
                b = ", ".join(b) if b else "empty"
                note = "the list of encrypted files: difference 5 (open, task 045)" if not same else ""
            rows.append(row(f"PARAM.SFO {key}", repr(a), repr(b), "the same" if same else "differs",
                            FAITHFUL if same else DIFFERS, "faithful when equal", note))
    a, b = Path(port_dir) / "ICON0.PNG", Path(ref_dir) / "ICON0.PNG"
    if a.exists() and b.exists():
        same = a.read_bytes() == b.read_bytes()
        pix = same or png.read_png(str(a)) == png.read_png(str(b))
        rows.append(row("ICON0.PNG, byte for byte", sha256(a)[:12], sha256(b)[:12],
                        "identical" if same else "same pixels" if pix else "differs",
                        FAITHFUL if same else CLOSE if pix else DIFFERS,
                        "faithful when identical, close when only the encoding differs"))
    return rows


def cat_saves(ctx):
    log, rc, reached = port_run(ctx, "save", cs.parse_drive(cs.MENU_ROUTE)[0], 4800, {"PURE_TRACE_SAVEDATA": "1"})
    port = ctx.out / "runs" / "save-folder"
    shutil.rmtree(port, ignore_errors=True)
    src = ctx.stick / "ms0" / "PSP" / "SAVEDATA" / SAVE_FOLDER
    if not src.is_dir():
        return [row("the profile's save folder", "not written", "-", "-", DIFFERS, "",
                    f"no {SAVE_FOLDER} after main_menu.txt (run exit {rc}, {rel(log)})")]
    shutil.copytree(src, port)
    ref = REF / "saves" / SAVE_FOLDER
    if not ref.is_dir():
        return [row("the profile's save folder", ", ".join(sorted(p.name for p in port.iterdir())), missing("saves"),
                    "-", NO_REF, "")]
    out = compare_saves(port, ref)
    for r in out:
        r["note"] = (r["note"] + "; " if r["note"] else "") + f"PPSSPP: {rel(ref)}" if r is out[0] else r["note"]
    return out


# ------------------------------------------------------------------------------------------------------ coverage

def ge_ignored(log):
    """The framework's exit list in a log: {opcode: count}, or None without one."""
    out, inside = None, False
    with open(log, errors="replace") as f:
        for line in f:
            if GE_COUNT_RE.match(line):
                out, inside = {}, True
                continue
            if inside:
                m = fa.IGNORED_RE.match(line.rstrip("\n"))
                if m:
                    out[int(m[1], 16)] = int(m[2])
                    continue
                inside = False
    return out


def import_states(imports_csv, unimplemented, stub_hits, unverified):
    """The 278 imports by state: implemented, stubbed with a documented value (the profile's constants), with no
    implementation (called or never called)."""
    names = []
    with open(imports_csv) as f:
        next(f)
        for line in f:
            w = line.strip().split(",")
            if len(w) >= 3:
                names.append(w[2])
    none = [n for n in names if n in set(unimplemented)]
    const = [n for n in names if n in PROFILE_CONSTANTS]
    impl = [n for n in names if n not in set(none) | set(const)]
    return {"total": len(names), "implemented": impl, "constants": const, "none": none,
            "none_called": sorted(set(stub_hits) & set(none)), "unverified_called": sorted(set(unverified) & set(impl))}


def cat_coverage(ctx):
    rows = []
    mdir = matrix_dir()
    if not mdir:
        rows.append(row("the campaign matrix (46 cells)", "-", "-", "-", NOT_MEASURED, "",
                        "no cell results: `python3 tools/fidelity_audit.py` (about 4 h) makes out/fidelity/cells; the "
                        "scorecard does not run the matrix itself"))
        cells = []
    else:
        cells = matrix_cells(mdir)
        outcomes = {}
        for c in cells:
            outcomes[c["outcome"]] = outcomes.get(c["outcome"], 0) + 1
        bad = sum(n for o, n in outcomes.items() if o not in ("PASS", "STALL"))
        src = f"{rel(mdir)}/cells (the matrix of 2026-10-06, task 035)"
        rows.append(row("the matrix's cells with a result", f"{len(cells)} ("
                        + ", ".join(f"{n} {o}" for o, n in sorted(outcomes.items())) + ")", "46", f"{len(cells) - 46:+d}",
                        FAITHFUL if len(cells) >= 46 and bad == 0 else DIFFERS,
                        "faithful when all 46 have a result and none is HALT, NO RACE, TIMEOUT or STUCK",
                        f"{src}; the stalls are the follower's (docs/fidelity.md)"))
        kinds = [("halts (`Runtime stopped` other than the sweep's own)", lambda k: "Runtime stopped" in k),
                 ("stubs hit (`[hle-stub]`)", lambda k: "[hle-stub]" in k),
                 ("unsupported instructions", lambda k: "unsupported" in k.lower() and "[hle-stub]" not in k),
                 ("skipped draws (`[metal] ... not emulated` / `not implemented`)",
                  lambda k: k.startswith("[metal]") and ("not emulated" in k or "not implemented" in k))]
        for label, pred in kinds:
            n = sum(v for c in cells for k, v in c.get("features", {}).items() if pred(k))
            where = sorted({c["cell"] for c in cells for k in c.get("features", {}) if pred(k)})
            rows.append(row(f"{label} over the cells", n, 0, f"{n:+d}", FAITHFUL if n == 0 else DIFFERS,
                            "faithful at 0, differs otherwise", ", ".join(where[:6])))
    # Imports.
    unimpl, stub_hits, unverified = [], set(), set()
    for c in cells:
        if c.get("unimplemented_list") and not unimpl:
            unimpl = c["unimplemented_list"]
        for k in c.get("features", {}):
            m = re.search(r"\[hle-stub\] (\S+)", k)
            if m:
                stub_hits.add(m[1])
    logs = [c["_log"] for c in cells if c["_log"].exists()]
    for lg in logs:
        with open(lg, errors="replace") as f:
            for line in f:
                if "UNVERIFIED" in line:
                    m = UNVERIFIED_RE.match(line)
                    if m:
                        unverified.add(m[1])
    if not unimpl:
        # This invocation's logs carry the start-up list too.
        for lg in ctx.logs.values():
            if lg.exists():
                txt = lg.read_text(errors="replace")
                m = re.search(r"^Unimplemented imports: \d+ of \d+\n((?:  .*\n)+)", txt, re.M)
                if m:
                    unimpl = [ln.strip() for ln in m[1].splitlines() if ln.startswith("    ")]
                    break
    st = import_states(ROOT / "config" / "imports.csv", unimpl, stub_hits, unverified)
    src = "config/imports.csv; the start-up list and the `[hle-stub]` and `UNVERIFIED` lines of the matrix's logs"
    rows.append(row("imports implemented (a model of the call)", f"{len(st['implemented'])} of {st['total']}",
                    st["total"], f"{len(st['implemented']) - st['total']:+d}",
                    CLOSE if st["unverified_called"] else FAITHFUL,
                    "faithful when every implemented call the matrix made is checked against a game; close when one "
                    "is answered from documentation only (UNVERIFIED)",
                    (f"called from documentation only: {', '.join(st['unverified_called'])}; " if st["unverified_called"]
                     else "") + src, {"unverified_called": st["unverified_called"]}))
    rows.append(row("imports stubbed with a documented value (the profile's constants)",
                    f"{len(st['constants'])}: {', '.join(st['constants'])}", 0, f"{len(st['constants']):+d}",
                    CLOSE if st["constants"] else FAITHFUL, "faithful at 0; close when a constant stands in for the "
                    "PSP's behaviour", "GPI 0 as on retail; the ready-queue rotation a yield hint the scheduler covers; "
                    "no thread ids (src/profile/pure_profile.cpp)"))
    called = st["none_called"]
    rows.append(row("imports with no implementation: never called / called in the matrix",
                    f"{len(st['none']) - len(called)} never called, {len(called)} called", "0 called",
                    f"{len(called):+d} called", FAITHFUL if not called and cells else DIFFERS if called else NOT_MEASURED,
                    "faithful when none is called (a call prints `[hle-stub]`), differs otherwise",
                    "multiplayer, the download menu's network side, game sharing, the alarm and LoadExec calls"))
    # GE commands still ignored: this invocation's race log (the current build), the matrix's for comparison.
    cur = None
    for name in ("regress-main_menu+single_race", "race-vineta_k", "picture-blue_ridge_hud"):
        if name in ctx.logs and ctx.logs[name].exists():
            cur = ge_ignored(ctx.logs[name]), name
            if cur[0] is not None:
                break
    if not cur or cur[0] is None:
        log, _, _ = port_run(ctx, "coverage-race", race_steps("vineta_k", 300), 6400)
        cur = ge_ignored(log), "coverage-race"
    ops, src_run = cur
    old = max((len(c.get("ignored", {})) for c in cells), default=None)
    if ops is None:
        rows.append(row("GE commands the framework ignores", "-", 0, "-", NOT_MEASURED, "", "no exit list in the log"))
    else:
        used = sorted(op for op in ops if op not in GE_UNUSED)
        names = ", ".join(fa.GE_NAMES.get(op, (f"0x{op:02X}",))[0] for op in sorted(ops))
        rows.append(row("GE commands the framework still ignores (distinct, the exit list)", len(ops), 0,
                        f"{len(ops):+d}", FAITHFUL if not ops else CLOSE if not used else DIFFERS,
                        "faithful at 0; close when every one left is one docs/fidelity.md found no draw of the game "
                        "using; differs otherwise",
                        f"this run's {src_run} (to the first race frame): {names}"
                        + (f"; the matrix's logs (before tasks 036, 037, 040): {old}" if old else "")
                        + (f"; used by draws: {', '.join(f'0x{o:02X}' for o in used)}" if used else ""),
                        {"ops": sorted(ops), "used": used}))
    rows.append(row("functions of config/function_map.csv entered during the matrix", "-", "-", "-", NOT_MEASURED, "",
                    "no cheap entry count exists: PSPRECOMP_PROFILE_DISPATCH counts the outer dispatch loop only "
                    "(chained calls never show) and slows the run, PSPRECOMP_COUNT_PC takes eight addresses; the "
                    "VFPU differential test stays a task of its own (the brief's 045)"))
    return rows


# ------------------------------------------------------------------------------------------------------- report

HEADER = """# The accuracy scorecard

`tools/scorecard.py` (task 044) answers "how close is the port to the original" in numbers that can be re-run after
every change: six categories, each measured on the port headless and compared with PPSSPP (the oracle, its side taken
once and kept under `ref/scorecard/`, hashes in `ref/README.md`) or with the game's own facts. Every row has a grade:
`faithful`, `close` or `differs`, by the threshold in its last column; a category's grade is its worst graded row.
Three marks stand in for a grade where none can be given and do not count towards the category's: `no reference`
(the PPSSPP side is missing: refresh it), `not measured` (no instrument exists) and `accepted (D-011)` (difference 6,
the faster race loads, which Erik decided to keep). Difference 5 (saves are plain where the PSP encrypts them) is
open and graded `differs` until task 045 lands.

| Category | What is compared | Thresholds |
|---|---|---|
| Pictures | `tools/frame_regress.sh`'s 18 scenes (its summary) and the first race frames of Blue Ridge, Sinucit and Sebenco Climb (docs/fidelity.md item 3), the fraction of pixels over the tolerance against the PPSSPP capture | faithful within 0.005 of the scene's measured column, close up to its limit, differs above it |
| Trajectories | per circuit (12, Vector, unlock switch), the player's ship with Cross held from the countdown and no steering: PPSSPP's race records (sampled as `tools/pp_lines.py` does, each read twice and kept when both agree) against the port's `PURE_WATCH_GRID` records, clock-aligned (the port's positions interpolated at PPSSPP's race clocks) | the first clock more than 1 m apart is reported; graded on the largest distance over the first 20 s: faithful under 1.5 m, close under 5 m. The AI ships only if two PPSSPP runs of Vineta K agree at every common clock (under 0.01 m) |
| Timing | flips per race-clock second per mode (60 in Single Race and Tournament, 30 in Time Trial, Free Play and Zone); the two-vblank stretches of a follower-driven Vineta K race against PPSSPP's (`tools/fidelity_audit.py --ppsspp-race`); the race load | flips: faithful within 2% of 60 or 30, close within 5% (the stretches, the game's own, lower the 60-fps modes by half their share of the race clock); stretches: faithful when the counts differ by at most 1, close by at most 3; the load: accepted (D-011) |
| Audio | the main menu's music over 60 s (L pressed every 20 s keeps the attract demo away; it makes no sound); one Single Race per league (Vineta K, Sinucit, Sagarmatha), Cross held, 60 s from GO: the port's `PURE_AUDIO_WAV` against PPSSPP's audio dump | correlation (`audio_compare.py --locate`, the port's music in PPSSPP's mix): faithful at 0.6 or more, close at 0.3; RMS ratio: faithful within 0.95 to 1.05, close within 0.9 to 1.1; seconds where both mixes or neither are active: faithful at 98% or more, close at 90%; clipping: faithful when the port's clipped share is at most PPSSPP's + 0.0001, close at + 0.001 |
| Saves | the profile `tools/save_roundtrip.sh`'s first run makes (`main_menu.txt` on an empty stick; made here headless) against PPSSPP's save of the same profile (NAME0000, `save_yes.txt`) | names, sizes, PARAM.SFO's fields and ICON0.PNG's bytes: faithful when equal (ICON0.PNG close when only the encoding differs), differs otherwise; the data file by size only |
| Coverage | the matrix's 46 cells (`tools/fidelity_audit.py`'s cell results, reused from `out/035-wip/fidelity`, never run here), the 278 imports by state, the GE commands the framework still ignores (this run's exit list), the functions entered | halts, stubs, unsupported instructions, skipped draws: faithful at 0; imports: close while a constant or a documentation-only answer stands in; GE: close while every command left is one no draw of the game uses |

Run it: `python3 tools/scorecard.py --quick` (pictures, timing from the matrix's cells, saves, coverage; a few
minutes) or `--full` (all six, with fresh sweep cells for timing; about 25 minutes; a full run of every category
rewrites this file). `--only CATEGORY[,...]` runs some. Refresh the PPSSPP side: `python3 tools/scorecard.py
--refresh-references [CATEGORY]` (about an hour for all; docs/verification.md, "The accuracy scorecard").
"""


def render_md(result, header=True):
    lines = [HEADER] if header else []
    lines.append(f"## {result['mode']} run of {result['date']}, commit {result['commit']} ({result['wall']})")
    lines.append("")
    lines.append("| Category | Grade | Rows: faithful / close / differs / other | Wall time |")
    lines.append("|---|---|---|---|")
    for name in CATEGORIES:
        c = result["categories"].get(name)
        if not c:
            continue
        counts = [sum(1 for r in c["rows"] if r["grade"] == g) for g in (FAITHFUL, CLOSE, DIFFERS)]
        other = len(c["rows"]) - sum(counts)
        waited = c.get("waited_s", 0)
        lines.append(f"| {name.capitalize()} | {c['grade']} | {counts[0]} / {counts[1]} / {counts[2]} / {other} | "
                     f"{c['wall_s']:.0f} s" + (f" ({waited:.0f} s of it waiting for another task's game)"
                                               if waited >= 1 else "") + " |")
    for name in CATEGORIES:
        c = result["categories"].get(name)
        if not c:
            continue
        lines += ["", f"### {name.capitalize()}: {c['grade']} ({result['date']}, commit {result['commit']})", "",
                  "| Measure | Port | Reference | Difference | Grade | Threshold | Note |",
                  "|---|---|---|---|---|---|---|"]
        for r in c["rows"]:
            cells = [r["measure"], r["port"], r["reference"], r["difference"], f"**{r['grade']}**"
                     if r["grade"] == DIFFERS else r["grade"], r["rule"], r["note"]]
            lines.append("| " + " | ".join(str(x).replace("|", "/").replace("\n", " ") for x in cells) + " |")
    return "\n".join(lines) + "\n"


def run(opts):
    cats = opts.only.split(",") if opts.only else (CATEGORIES if opts.full else QUICK)
    for c in cats:
        if c not in CATEGORIES:
            print(f"scorecard: unknown category {c} ({', '.join(CATEGORIES)})")
            return 2
    tracks = opts.tracks.split(",") if opts.tracks else TRACKS
    for t in tracks:
        if t not in TRACKS:
            print(f"scorecard: unknown track {t}")
            return 2
    if not (ROOT / "build" / "arm64" / "bin" / "PureNative").exists():
        print("scorecard: build/arm64/bin/PureNative missing: tools/build.sh profile")
        return 1
    out = Path(opts.out)
    if not out.is_absolute():
        out = ROOT / out
    out.mkdir(parents=True, exist_ok=True)
    full = opts.full or (bool(opts.only) and not opts.quick)
    ctx = Ctx(out, cats, full, tracks)
    t0 = time.time()
    mode = "--full" if full else "--quick"
    result = {"tool": "tools/scorecard.py", "date": time.strftime("%Y-%m-%d %H:%M"), "commit": commit_label(),
              "mode": mode + (f" --only {opts.only}" if opts.only else "") + (f" --tracks {opts.tracks}" if opts.tracks
                                                                             else ""),
              "categories": {}, "references": manifest()}
    funcs = {"pictures": cat_pictures, "trajectories": cat_trajectories, "timing": cat_timing, "audio": cat_audio,
             "saves": cat_saves, "coverage": cat_coverage}
    order = [c for c in ("trajectories", "audio", "pictures", "timing", "saves", "coverage") if c in cats]
    for name in order:
        c0, w0 = time.time(), WAITED
        say(f"{name} ...")
        try:
            rows = funcs[name](ctx)
        except Exception as e:  # a category that breaks says so in its row; the others still run
            import traceback
            traceback.print_exc()
            rows = [row(f"{name}", "-", "-", "-", NOT_MEASURED, "", f"the scorecard failed here: {type(e).__name__}: {e}")]
        grade = worst([r["grade"] for r in rows])
        result["categories"][name] = {"grade": grade, "rows": rows, "wall_s": round(time.time() - c0, 1),
                                      "waited_s": round(WAITED - w0, 1)}
        say(f"{name}: {grade} ({len(rows)} rows, {time.time() - c0:.0f} s)")
    wall = time.time() - t0
    result["wall_s"] = round(wall, 1)
    result["waited_s"] = round(WAITED, 1)
    result["wall"] = f"{int(wall // 60)}m {int(wall % 60)}s" + (
        f", of it {int(WAITED // 60)}m {int(WAITED % 60)}s waiting for another task's game" if WAITED >= 1 else "")
    result["categories"] = {k: result["categories"][k] for k in CATEGORIES if k in result["categories"]}
    (out / "scorecard.json").write_text(json.dumps(result, indent=1, default=str) + "\n")
    md = render_md(result)
    (out / "scorecard.md").write_text(md)
    if opts.full and not opts.only and opts.tracks is None:
        (ROOT / "docs" / "scorecard.md").write_text(md)
        say("wrote docs/scorecard.md")
    for name, c in result["categories"].items():
        print(f"{name:13} {c['grade']}")
    say(f"wrote {rel(out / 'scorecard.json')} and scorecard.md ({result['wall']})")
    return 0


# ---------------------------------------------------------------------------------------------------- references

def read_flips(path):
    out = []
    with open(path) as f:
        for line in f:
            w = line.split()
            if len(w) == 2:
                out.append((int(w[0]), float(w[1])))
    return out


def pp_routes(track):
    if track in cs.ALPHA:
        n = cs.ALPHA.index(track)
        files = ["frontend.txt", "vineta_k_start.txt"] + ([f"track_down{n}.txt"] if n else [])
    else:
        league = "beta" if track in cs.BETA else "classic"
        n = cs.LEAGUES[league].index(track)
        files = ["frontend.txt", "unlock_all.txt", f"unlock_race_{league}.txt"] + (
            [f"unlock_track_down{n}.txt"] if n else [])
    return files, PP_HUD[track] + READY_AFTER_HUD


def pp_race(track, csv_path, race_seconds, wav=None, wall_limit=900.0):
    """A PPSSPP Single Race on a circuit with Cross held from READY: every race record sampled through memory.read
    while the CPU runs (tools/pp_lines.py's block and parser), each block read twice and kept only when both reads
    agree (a read can land inside the game's update of the records), until the player's clock reaches
    race_seconds; every flip logged with its emulated time and the player's clock (a log-only breakpoint on
    sceDisplaySetFrameBuf, as --ppsspp-race does) to <csv>.flips.txt; with wav, PPSSPP's audio dump of the run."""
    files, hold = pp_routes(track)
    # The release far past the run's end keeps the replay executing: when PPSSPP's replay runs out of items it stops
    # overriding the pad, which would lift Cross at once (vineta_k_hold_cross.txt releases 3000 vblanks later).
    script = ("\n".join((PP_ROUTES / f).read_text() for f in files)
              + f"\n{hold}:CROSS\n{hold + PP_HOLD_VBLANKS}:\n")
    states = pc.parse_pad_script(script)
    csv_path = Path(csv_path)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    raw_log = csv_path.with_suffix(".ppsspp.log")
    tmp = csv_path.with_suffix(".csv.tmp")
    report = {}
    rows = torn = 0
    if not wait_ppsspp():
        return {"error": "PPSSPP did not become free"}
    t0 = time.time()
    before = pc.audio_dumps()
    with pc.IniSession(False, port=pc.DEFAULT_PORT, renderer="hardware", hle_log=False, mute=True,
                       savestate_key=False, dump_audio=bool(wav)):
        proc = pc.launch(pc.DEFAULT_ISO, raw_log)
        dbg = None
        try:
            dbg, _ = pc.connect(pc.DEFAULT_PORT, proc.pid, proc)
            pc.wait_boot(dbg)
            dbg.request("replay.time.set", value=RTC)
            dbg.request("replay.execute", version=1, base64=__import__("base64").b64encode(
                pc.build_replay_blob(states)).decode())
            setfb = dbg.symbol(pc.SETFB_STUB)
            clock_at = pl.RECORD_POS + PLAYER * pl.STRIDE + 0x1C
            dbg.request("cpu.breakpoint.add", address=setfb, enabled=False, log=True,
                        logFormat=f"FLIP {{usec:d}} clock {{[0x{clock_at:08x}]:f}}")
            dbg.resume()
            last = [None] * 8
            b64 = __import__("base64")
            with open(tmp, "w") as f:
                f.write("usec,ship,clock,x,y,z,vx,vy,vz,dist,lap\n")
                while True:
                    if time.time() - t0 > wall_limit:
                        raise RuntimeError(f"wall-clock limit {wall_limit:.0f} s reached")
                    u = dbg.usec()
                    frame = pc.frame_at_us(u)
                    if frame < hold - 30:
                        time.sleep(0.5)
                        continue
                    a = dbg.request("memory.read", address=pl.BLOCK_START, size=pl.BLOCK_SIZE)["base64"]
                    b = dbg.request("memory.read", address=pl.BLOCK_START, size=pl.BLOCK_SIZE)["base64"]
                    if a != b:
                        torn += 1
                        continue
                    for r in pl.records(b64.b64decode(a)):
                        k, clock = r[0], r[1]
                        if clock <= 0.0 or clock == last[k]:
                            continue
                        last[k] = clock
                        f.write(f"{u},{k}," + ",".join(f"{v:.3f}" for v in r[1:9]) + f",{r[9]}\n")
                        rows += 1
                    if last[PLAYER] is not None and last[PLAYER] >= race_seconds:
                        break
                    if frame > hold + 1200 and last[PLAYER] is None:
                        raise RuntimeError(f"no race clock by vblank {frame:.0f}: the route did not reach a race")
                    time.sleep(0.03)
            report["end_vblank"] = round(pc.frame_at_us(dbg.usec()), 1)
        except Exception as e:  # report, then still shut PPSSPP down
            report["error"] = f"{type(e).__name__}: {e}"
            say(f"PPSSPP {track}: {report['error']}")
        finally:
            if dbg:
                dbg.close()
            pc.stop_process(proc.pid, proc)
            if wav:
                pc.take_audio_dump(before, str(wav), report)
    if "error" in report:
        tmp.unlink(missing_ok=True)
        return report
    tmp.replace(csv_path)
    flips = []
    with open(raw_log, errors="replace") as f:
        for line in f:
            m = fa.PP_LOG_RE.search(line)
            if m and m[1] == "FLIP" and int(m[2]) >= pc.vblank_us(5000):
                flips.append(f"{m[2]} {m[3]}")
    csv_path.with_suffix(".flips.txt").write_text("\n".join(flips) + "\n")
    raw_log.unlink(missing_ok=True)
    report.update(rows=rows, torn_reads=torn, wall_s=round(time.time() - t0), routes=files, hold=hold)
    say(f"PPSSPP {track}: {rows} samples ({torn} reads discarded as torn), {report['wall_s']} s")
    return report


def ppsspp_saves():
    return pc.MEMSTICK / "PSP" / "SAVEDATA"


def refresh(opts):
    cats = [opts.refresh_references] if opts.refresh_references not in (None, "all") else \
        ["trajectories", "audio", "saves", "timing"]
    for c in cats:
        if c not in ("trajectories", "audio", "saves", "timing"):
            print(f"scorecard: --refresh-references takes trajectories, audio, saves or timing (pictures use ref/*.png, "
                  f"coverage has no PPSSPP side), not {c}")
            return 2
    tracks = opts.tracks.split(",") if opts.tracks else TRACKS
    REF.mkdir(parents=True, exist_ok=True)
    made = {}
    t0 = time.time()

    def note(path, how):
        made[rel(path)] = {"sha256": sha256(path), "bytes": Path(path).stat().st_size,
                           "made": time.strftime("%Y-%m-%d %H:%M"), "how": how}

    tdir, adir = REF / "trajectories", REF / "audio"
    if "trajectories" in cats or "audio" in cats:
        race_tracks = tracks if "trajectories" in cats else [t for t in AUDIO_TRACKS if t in tracks]
        for track in race_tracks:
            audio = track in AUDIO_TRACKS
            csv_path = tdir / f"{track}.csv"
            wav = adir / f"{track}.wav" if audio else None
            rep = pp_race(track, csv_path, PP_AUDIO_SECONDS if audio else PP_RACE_SECONDS, wav)
            if "error" in rep:
                continue
            how = (f"PPSSPP {' + '.join(rep['routes'])}, Cross from vblank {rep['hold']}, race records to "
                   f"{PP_AUDIO_SECONDS if audio else PP_RACE_SECONDS:g} s of race clock")
            note(csv_path, how)
            note(csv_path.with_suffix(".flips.txt"), how + "; every flip (usec, the player's clock)")
            if wav and Path(wav).exists():
                note(wav, how + "; PPSSPP's audio dump")
        if "trajectories" in cats and "vineta_k" in tracks:
            rep = pp_race("vineta_k", tdir / "vineta_k.run2.csv", PP_RACE_SECONDS)
            if "error" not in rep:
                note(tdir / "vineta_k.run2.csv", "PPSSPP, Vineta K again: the AI ships' determinism check")
                note(tdir / "vineta_k.run2.flips.txt", "the second run's flips")
    if "audio" in cats:
        wav = adir / "main_menu.wav"
        cmd = [sys.executable, str(ROOT / "tools" / "ppsspp" / "ppsspp_ctl.py"), "run",
               "--pad-file", str(PP_ROUTES / "frontend.txt"), "--pad-file", str(PP_ROUTES / "main_menu_music.txt"),
               "--until", "9900", "--renderer", "hardware", "--dump-audio", str(wav)]
        say("PPSSPP main menu music ...")
        wait_ppsspp()
        if subprocess.run(cmd, cwd=ROOT).returncode == 0 and wav.exists():
            note(wav, "PPSSPP frontend.txt + main_menu_music.txt to vblank 9900; its audio dump")
    if "saves" in cats:
        sdir = REF / "saves"
        cmd = [sys.executable, str(ROOT / "tools" / "ppsspp" / "ppsspp_ctl.py"), "run",
               "--pad-file", str(PP_ROUTES / "frontend.txt"), "--pad-file", str(PP_ROUTES / "save_yes.txt"),
               "--until", "6200", "--renderer", "hardware"]
        say("PPSSPP save of NAME0000 ...")
        wait_ppsspp()
        subprocess.run(cmd, cwd=ROOT)
        src = ppsspp_saves() / SAVE_FOLDER
        if src.is_dir():
            shutil.rmtree(sdir / SAVE_FOLDER, ignore_errors=True)
            sdir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(sdir / SAVE_FOLDER))    # off PPSSPP's stick: the routes expect no profile
            for p in sorted((sdir / SAVE_FOLDER).iterdir()):
                note(p, "PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot)")
        else:
            say(f"no {SAVE_FOLDER} appeared in {ppsspp_saves()}")
    if "timing" in cats:
        out = "ref/scorecard/timing"
        shutil.rmtree(ROOT / out / "ppsspp" / "vineta_k", ignore_errors=True)
        say("PPSSPP follower race on Vineta K (fidelity_audit.py --ppsspp-race) ...")
        wait_ppsspp()
        subprocess.run([sys.executable, str(ROOT / "tools" / "fidelity_audit.py"), "--ppsspp-race", "vineta_k",
                        "--out", out], cwd=ROOT)
        d = ROOT / out / "ppsspp" / "vineta_k"
        for extra in ("shots", "race.csv"):
            p = d / extra
            shutil.rmtree(p, ignore_errors=True) if p.is_dir() else p.unlink(missing_ok=True)
        for name in ("summary.json", "ppsspp.log"):
            if (d / name).exists():
                note(d / name, "tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing")
    m = manifest()
    m.update(made)
    m = {k: v for k, v in m.items() if (ROOT / k).exists()}
    MANIFEST.write_text(json.dumps(m, indent=1, sort_keys=True) + "\n")
    write_readme(m)
    say(f"references: {len(made)} files made, {len(m)} listed; {time.time() - t0:.0f} s")
    return 0


def write_readme(m):
    table = ["| File (under ref/) | Bytes | SHA-256 | Made | How |", "|---|---|---|---|---|"]
    for k in sorted(m):
        v = m[k]
        table.append(f"| {k[len('ref/'):]} | {v['bytes']} | {v['sha256']} | {v['made']} | {v['how']} |")
    text = README.read_text()
    block = README_BEGIN + "\n" + "\n".join(table) + "\n" + README_END
    if README_BEGIN in text and README_END in text:
        text = text[:text.index(README_BEGIN)] + block + text[text.index(README_END) + len(README_END):]
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    README.write_text(text)


# ------------------------------------------------------------------------------------------------------ selftest

def selftest():
    fails = []

    def check(cond, what):
        print(f"selftest: {'ok  ' if cond else 'FAIL'} {what}")
        if not cond:
            fails.append(what)

    # Grades.
    check(grade_picture(0.0149, 0.0149, 0.10) == FAITHFUL and grade_picture(0.0190, 0.0149, 0.10) == FAITHFUL
          and grade_picture(0.0200, 0.0149, 0.10) == CLOSE and grade_picture(0.11, 0.0149, 0.10) == DIFFERS
          and grade_picture(None, 0.0, 0.05) == DIFFERS and grade_picture(0.0, 0.0149, 0.10) == FAITHFUL,
          "pictures: within 0.005 of measured, up to the limit, above it, no capture, better than measured")
    check(worst([FAITHFUL, CLOSE, NO_REF]) == CLOSE and worst([FAITHFUL, DIFFERS, CLOSE]) == DIFFERS
          and worst([NO_REF, NOT_MEASURED]) == NO_REF and worst([NOT_MEASURED]) == NOT_MEASURED
          and worst([ACCEPTED, FAITHFUL]) == FAITHFUL, "a category is its worst graded row; marks do not count")
    check(grade_low(1.49, 1.5, 5) == FAITHFUL and grade_low(1.5, 1.5, 5) == CLOSE and grade_low(5.0, 1.5, 5) == DIFFERS,
          "trajectory thresholds: under 1.5 m, under 5 m")
    check(grade_band(1.0, RMS_FAITHFUL, RMS_CLOSE) == FAITHFUL and grade_band(0.92, RMS_FAITHFUL, RMS_CLOSE) == CLOSE
          and grade_band(1.2, RMS_FAITHFUL, RMS_CLOSE) == DIFFERS, "RMS ratio bands")
    check(grade_at_least(0.6, 0.6, 0.3) == FAITHFUL and grade_at_least(0.31, 0.6, 0.3) == CLOSE
          and grade_at_least(0.1, 0.6, 0.3) == DIFFERS, "correlation thresholds")
    summ = ("frame regression 2026-10-07, commit x\n\nscene       frame  fraction  limit  tol  measured   delta  result\n"
            "race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS\n"
            "zone_hud     5260         -   0.09   32    0.0121       -  FAIL (no capture)\n")
    s = parse_regress_summary(summ)
    check(s.get("race_hud", {}).get("fraction") == 0.0148 and s["race_hud"]["measured"] == 0.0149
          and s.get("zone_hud", {}).get("fraction") is None and len(s) == 2, "frame_regress summary parsed")
    # Trajectories: a port series every 1/60 s, PPSSPP samples every 3 flips drifting apart.
    port = [(i / 60.0, i * 1.0, 0.0, 0.0) for i in range(1, 1500)]
    pp = [(i / 60.0, i * 1.0 + (0.1 * i / 60.0), 0.0, 0.0) for i in range(3, 1500, 3)]
    c = compare_series(port, pp)
    check(abs(c["max"] - 2.0) < 0.01 and abs(c["first_over"] - 10.05) < 0.06 and c["samples"] == 400,
          f"trajectory: 0.1 m/s drift -> 2.0 m at 20 s, first over 1 m at {fmt(c['first_over'], 2)} s")
    pp_mid = [(i / 60.0 + 1 / 120.0, (i + 0.5) * 1.0, 0.0, 0.0) for i in range(3, 1199, 3)]
    check(compare_series(port, pp_mid)["max"] < 1e-6, "trajectory: interpolation between flips")
    check(trajectory_row("T", c, "ref")["grade"] == CLOSE and
          trajectory_row("T", compare_series(port, []), "ref")["grade"] == DIFFERS, "trajectory rows graded")
    a = {0: [(1.0, 0, 0, 0), (2.0, 1, 0, 0)], 7: [(1.0, 5, 5, 5)]}
    check(first_lap([(0.5, 0, 0, 0), (1.0, 1, 0, 0), (1.0, 1, 0, 0), (60.0, 2, 0, 0), (0.4, 9, 0, 0), (0.5, 9, 0, 0)])
          == [(0.5, 0, 0, 0), (1.0, 1, 0, 0), (60.0, 2, 0, 0)], "trajectory: the samples end at the lap clock's restart")
    check(deterministic(a, a, [0]) == (2, 0.0) and deterministic(a, {0: [(1.0, 0, 0.5, 0)]}, [0])[1] == 0.5,
          "AI determinism: common clocks compared, the player left out")
    # Timing: a synthetic sweep log.
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        lines = ["[pure] ship frame 5730 player object 0x09a00000 index 7"]
        clock, frame, us = 0.0, 6000, 200_000_000
        for i in range(600):                       # 10 s at one vblank a flip, then a 30-flip stretch, then 5 s
            frame += 1
            clock += 1 / 60.0 if i > 0 else 0.0
            lines.append(f"[pure] ship frame {frame} t={us} clock={clock:.3f} pos=0,0,0 vel=0,0,0 kmh=0.000 "
                         f"dist=1.000 lap=0 shield=100.000")
        for i in range(30):
            frame += 1
            clock += 2 / 60.0
            lines.append(f"[pure] ship frame {frame} t={us} clock={clock:.3f} pos=0,0,0 vel=0,0,0 kmh=0.000 "
                         f"dist=1.000 lap=1 shield=100.000")
        clock = 0.0
        for i in range(300):                       # the lap clock restarts at the line
            frame += 1 if i != 150 else 121        # a pause: no line for 120 flips, the clock standing still
            clock += 1 / 60.0
            lines.append(f"[pure] ship frame {frame} t={us} clock={clock:.3f} pos=0,0,0 vel=0,0,0 kmh=0.000 "
                         f"dist=1.000 lap=1 shield=100.000")
        lines.append(f"[pure] ship frame {frame + 1} t={us} clock={clock:.3f} pos=0,0,0 vel=0,0,0 kmh=0.000 "
                     f"dist=1.000 lap=65537 shield=100.000")
        log = tmp / "sweep.log"
        log.write_text("\n".join(lines) + "\n")
        flips, secs, _ = race_rate(log)
        check(flips == 927 and abs(secs - (598 / 60 + 1.0 + 299 / 60)) < 0.005,
              f"flips per race second: {flips} flips over {secs:.3f} s with a stretch, a lap restart and a pause")
        # The load: flips at two vblanks, a 200 ms gap, 57 fade flips at two vblanks, then one vblank a flip.
        v = 16683.3
        t, fl = 0.0, []
        for _ in range(10):
            fl.append(int(t)); t += 2 * v
        press = t
        t += 0.2e6
        for _ in range(40):
            fl.append(int(t)); t += 2 * v
        fade = t
        for _ in range(FADE_FLIPS):
            fl.append(int(t)); t += 2 * v
        race = t
        for _ in range(100):
            fl.append(int(t)); t += v
        got = load_length(fl, press)
        check(got is not None and abs(got[0] - (fade - press) / 1e6) < 1e-3 and abs(got[1] - (race - press) / 1e6) < 1e-3,
              f"race load: {fmt(got[0] if got else None, 3)} s to the fade, {fmt(got[1] if got else None, 3)} s to the race")
        check(load_length(fl[:60], press) is None, "race load: no race start, no figure")
        # Audio: a 'music' track in both, an effect only in the port's mix, clipping on one side.
        rate = 44100

        def wavfile(path, samples):
            with wave.open(str(path), "wb") as w:
                w.setnchannels(2)
                w.setsampwidth(2)
                w.setframerate(rate)
                buf = array("h")
                for s_ in samples:
                    v_ = max(-32768, min(32767, int(s_)))
                    buf.append(v_)
                    buf.append(v_)
                w.writeframes(buf.tobytes())
        import random
        rnd = random.Random(44)
        music = [3000 * math.sin(i * 0.03) + rnd.uniform(-2000, 2000) for i in range(rate * 14)]
        lead = 3 * rate                         # PPSSPP's dump starts the music 3 s later
        ppm = [0.0] * lead + music
        portm = list(music) + [0.0] * lead
        for i in range(5 * rate, 5 * rate + 50):
            ppm[i] = 40000                      # 50 clipped frames x 2 channels in PPSSPP
        wavfile(tmp / "pp.wav", ppm)
        wavfile(tmp / "port.wav", portm)
        off, corr = locate_best(tmp / "pp.wav", tmp / "port.wav", 4.0, 2.0, 5.0, 9.0)
        check(off is not None and abs(off - 3.0) < 1e-4 and corr > 0.99, f"audio: --locate finds the 3 s offset "
              f"({fmt(off, 5)} s, correlation {corr:.3f})")
        w = compare_windows(tmp / "port.wav", tmp / "pp.wav", 0.0, 3.0, 10)
        check(w["seconds"] == 10 and abs(w["rms_ratio"] - 1.0) < 0.05 and w["share"] == 1.0, f"audio: aligned windows "
              f"(RMS ratio {fmt(w['rms_ratio'], 3)}, share {w['share']})")
        check(w["pp_clip"] == 100 and w["port_clip"] == 0 and clip_grade(0, 100, 100, 100000)[0] == FAITHFUL
              and clip_grade(50, 100000, 0, 100000)[0] == CLOSE and clip_grade(5000, 100000, 0, 100000)[0] == DIFFERS,
              "audio: clipped samples counted and graded")
        check(abs(first_active(tmp / "port.wav", 0.0, seconds=5.0)) < 0.02, "audio: the music's first active block")
        # Saves.
        sfo = build_sfo([("CATEGORY", "MS"), ("PARENTAL_LEVEL", 1), ("SAVEDATA_DETAIL", "User name: NAME0000"),
                         ("SAVEDATA_FILE_LIST", b"PROFILE.BIN".ljust(32, b"\0")), ("TITLE", "WIPEOUT PURE")])
        p = parse_sfo(sfo)
        check(p == {"CATEGORY": "MS", "PARENTAL_LEVEL": 1, "SAVEDATA_DETAIL": "User name: NAME0000",
                    "SAVEDATA_FILE_LIST": ["PROFILE.BIN"], "TITLE": "WIPEOUT PURE"}, "PARAM.SFO parsed")
        for side, listed, size in (("port", b"", 41570), ("pp", b"PROFILE.BIN".ljust(32, b"\0"), 41586)):
            d = tmp / side
            d.mkdir()
            (d / "PARAM.SFO").write_bytes(build_sfo([("CATEGORY", "MS"), ("SAVEDATA_FILE_LIST", listed),
                                                     ("TITLE", "WIPEOUT PURE")]))
            (d / DATA_FILE).write_bytes(b"\0" * size)
            png.write_png(str(d / "ICON0.PNG"), 2, 2, 3, bytes(12))
        rows = compare_saves(tmp / "port", tmp / "pp")
        g = {r["measure"]: r["grade"] for r in rows}
        check(g["the save folder's files"] == FAITHFUL and g[f"{DATA_FILE} (the data file): size only"] == DIFFERS
              and g["PARAM.SFO SAVEDATA_FILE_LIST"] == DIFFERS and g["PARAM.SFO TITLE"] == FAITHFUL
              and g["ICON0.PNG, byte for byte"] == FAITHFUL and g["PARAM.SFO SAVEDATA_DETAIL"] == FAITHFUL,
              "saves: names, the data file's size, the file list, the fields, ICON0.PNG")
        # Coverage: the GE exit list and the import states.
        glog = tmp / "ge.log"
        glog.write_text("x\nGE commands ignored: 3 distinct\n  0x15 x10 first=0x0\n  0xca x2 first=0x0\n"
                        "  0xc8 x5 first=0x0\n[metal] 1 frames\n")
        ops = ge_ignored(glog)
        check(ops == {0x15: 10, 0xCA: 2, 0xC8: 5} and sorted(op for op in ops if op not in GE_UNUSED) == [0xC8],
              "coverage: the GE exit list, and which are not in the unused set")
        imp = tmp / "imports.csv"
        imp.write_text("library,nid,name,stub_rel,stub_abs\nA,1,sceA,0,0\nB,2,sceKernelGetGPI,0,0\nC,3,sceHttpX,0,0\n"
                       "D,4,sceY,0,0\n")
        st = import_states(imp, ["sceHttpX"], set(), {"sceY"})
        check(st["implemented"] == ["sceA", "sceY"] and st["constants"] == ["sceKernelGetGPI"] and st["none"] == ["sceHttpX"]
              and st["none_called"] == [] and st["unverified_called"] == ["sceY"], "coverage: the imports by state")
        # The report: a missing reference is a row, not an error; markdown and JSON written.
        r = {"mode": "--quick", "date": "2026-10-07 12:00", "commit": "abc", "wall": "0m 1s",
             "categories": {"saves": {"grade": NO_REF, "wall_s": 1.0,
                                      "rows": [row("folder", "x", missing("saves"), "-", NO_REF, "")]}}}
        md = render_md(r)
        check("### Saves: no reference" in md and "| folder | x | missing: tools/scorecard.py --refresh-references saves"
              in md and md.startswith("# The accuracy scorecard"), "report: a missing reference renders as a row")
        check(json.loads(json.dumps(r))["categories"]["saves"]["grade"] == NO_REF, "report: JSON round trip")
    print("PASS" if not fails else f"FAIL ({len(fails)}: {'; '.join(fails)})")
    return 0 if not fails else 1


def parse(argv):
    p = argparse.ArgumentParser(prog="scorecard.py", usage=__doc__.split("\n\n")[1].strip())
    g = p.add_mutually_exclusive_group()
    g.add_argument("--quick", action="store_true")
    g.add_argument("--full", action="store_true")
    p.add_argument("--only")
    p.add_argument("--refresh-references", nargs="?", const="all", metavar="CATEGORY")
    p.add_argument("--out", default="out/scorecard")
    p.add_argument("--tracks")
    p.add_argument("--selftest", action="store_true")
    return p.parse_args(argv)


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    if opts.selftest:
        return selftest()
    if opts.refresh_references:
        return refresh(opts)
    return run(opts)


if __name__ == "__main__":
    sys.exit(main())
