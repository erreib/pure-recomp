"""The readers of a port run's log (task 050): the line formats the tools match, in one place.

The profile's probes (src/profile/pure_profile.cpp) print `[pure] ship` lines (PURE_WATCH_SHIP: the player's race
record each flip, and `player object ... index K` when a race's ship appears), `[pure] grid` lines (PURE_WATCH_GRID:
every race record when it changes) and `[pure] exit at frame N` (PURE_EXIT_AT_FRAME). The framework prints the
start-up list of unimplemented imports (PURE_LIST_STUBS), a stub's first call as `[hle-stub] NAME ... ra=0x...`, and
at exit the Metal backend's counts and the GE commands it ignored. PURE_AUDIO_WAV=FILE writes the mix to FILE and
each sceAudio channel N to FILE.chN.wav (src/hle/audio_capture.cpp).

Since task 094 the checks' own readers are here too, each defined once: tools/campaign_sweep.py's result line
(sweep_result) and a Time Trial cell's trace and game clock (race_cell); the flip times of a run with
PURE_TRACE_CALLS=sceDisplay:0x289D82FE (flip_log, flip_median_ms, flips_per_second); the `[pure] display rate` lines
of E8 (DISPLAY_*, display_margin); the framework's `[perf]` (PURE_PERF=log), `[stalls]` and `[slow-frame]`
(PURE_TRACE_STALLS) and `[audio]` (PURE_TRACE_AUDIO) lines; the window guard (window_guard, window_shown: a window
run measures nothing unless vsync held it on screen); and the fidelity audit's scan of a sweep log (scan_log, its
two-vblank stretch rule STRETCH_MIN and TWO_VBLANK_US), which tools/fidelity_audit.py imports back, so the gates do
not import the audit. `python3 tools/purelib/logs.py --selftest` runs the readers on synthetic lines.
"""
import csv, os, re, statistics, struct, sys

FRAME_EXIT = "[pure] exit at frame"     # the profile's line when PURE_EXIT_AT_FRAME stops the runtime
FRAME_EXIT_RE = re.compile(r"\[pure\] exit at frame (\d+)")
FRAME_RE = re.compile(r"\[pure\] frame (\d+)")                       # PURE_FRAME_LOG's flip counter

# A ship line, every field: frame, clock, x, y, z, vx, vy, vz, kmh, dist, lap, shield (tools/campaign_sweep.py's).
SHIP_RE = re.compile(r"\[pure\] ship frame (\d+) t=\d+ clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"kmh=(\S+) dist=(\S+) lap=(\d+)(?: shield=(\S+))?")
# A ship line with its virtual time: frame, t (us), clock, kmh, dist, lap (tools/fidelity_audit.py's; match()).
SHIP_T_RE = re.compile(r"^\[pure\] ship frame (\d+) t=(\d+) clock=(\S+) pos=\S+ vel=\S+ kmh=(\S+) dist=(\S+) "
                       r"lap=(\d+)")
# A race's ship appears: frame, object, the player's index in the race records.
PLAYER_RE = re.compile(r"\[pure\] ship frame (\d+) player object (\S+) index (\d+)")
# A race record: frame, k, clock, x, y, z, vx, vy, vz, dist, lap.
GRID_RE = re.compile(r"\[pure\] grid frame (\d+) k=(\d+) clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"dist=(\S+) lap=(\d+)")
RACE_OVER = 0x10000     # lap field bit 16: that ship has finished (docs/tracks.md)

STUB_RE = re.compile(r"\[hle-stub\] (\S+)")                          # a stub's first call: its label
RA_RE = re.compile(r"\bra=(0x[0-9A-Fa-f]+)")
UNIMPL_RE = re.compile(r"Unimplemented imports: (\d+) of (\d+)")     # the start-up list's header (PURE_LIST_STUBS)
HALT_RE = re.compile(r"\[hle-stub\]|unsupported|Runtime stopped")    # a line that may end a run early

# The Metal backend's exit line. Tasks 036 and 037 inserted "texture-mapped draws" and "mipmapped draws (... mip
# levels decoded after the first)" after the framebuffer textures; both are optional so older logs still parse.
METAL_EXIT_RE = re.compile(r"^\[metal\] (\d+) frames, (\d+) draws, (\d+) passes, (\d+) textures decoded, (\d+) "
                           r"framebuffer textures, (?:\d+ texture-mapped draws, )?(?:\d+ mipmapped draws \([^)]*\), )?"
                           r"(\d+) target copies, (\d+) uploads, (\d+) targets, (\d+) GPU waits "
                           r"\(([\d.]+) ms\) in ([\d.]+) s")
METAL_PIPE_RE = re.compile(r"^\[metal\] pipelines: (\d+) render pipelines used, (\d+) made by a draw \((\d+) of them "
                           r"waited for the pre-warm, (\d+) not in the list\).*?; (\d+) depth-stencil states, "
                           r"(\d+) made")
METAL_FPS_RE = re.compile(r"^\[metal\] frame (\d+), \d+ draws \(\d+ in the last \d+ frames, ([\d.]+) fps\)")
GE_COUNT_RE = re.compile(r"^GE commands ignored: (\d+) distinct")    # the framework's exit list, then one line each:
GE_IGNORED_RE = re.compile(r"^  0x([0-9a-f]+) x(\d+) first=0x([0-9a-f]+)$")
UNDERRUN_RE = re.compile(r"\[pure\] audio capture: channel (\d+) underrun")


def exit_frame(path):
    """The N of the log's `[pure] exit at frame N` line (the run stopped at its PURE_EXIT_AT_FRAME), or None."""
    try:
        with open(path, errors="replace") as f:
            m = FRAME_EXIT_RE.search(f.read())
    except OSError:
        return None
    return int(m[1]) if m else None


def grid_samples(path):
    """The first race's grid records of a PURE_WATCH_GRID log: ([(frame, k, clock, x, y, z, vx, vy, vz, dist, lap)],
    the player's index), before GO and ships whose race is over left out."""
    rows, player, races = [], 7, 0
    with open(path, errors="replace") as f:
        for line in f:
            m = PLAYER_RE.search(line)
            if m:
                races += 1
                if races > 1:
                    break
                player = int(m[3])
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


def metal_exit(line):
    """The Metal backend's exit counts in a line ({frames, draws, textures, waits, wait_ms, seconds}), or None."""
    m = METAL_EXIT_RE.match(line)
    return m and dict(frames=int(m[1]), draws=int(m[2]), textures=int(m[4]), waits=int(m[9]), wait_ms=float(m[10]),
                      seconds=float(m[11]))


def metal_pipelines(line):
    """The Metal backend's exit line on pipelines ({pipelines, pipelines_made, pipelines_unlisted, depth_states,
    depth_made}), or None."""
    m = METAL_PIPE_RE.match(line)
    return m and dict(pipelines=int(m[1]), pipelines_made=int(m[2]), pipelines_unlisted=int(m[4]),
                      depth_states=int(m[5]), depth_made=int(m[6]))


def ge_ignored(path):
    """The framework's exit list of the GE commands it ignored, {opcode: count}, or None when the log has none."""
    out, inside = None, False
    with open(path, errors="replace") as f:
        for line in f:
            if GE_COUNT_RE.match(line):
                out, inside = {}, True
                continue
            if inside:
                m = GE_IGNORED_RE.match(line.rstrip("\n"))
                if m:
                    out[int(m[1], 16)] = int(m[2])
                    continue
                inside = False
    return out


def unimplemented(text):
    """The names in the start-up list of unimplemented imports (PURE_LIST_STUBS) in a log's text, [] without one."""
    m = re.search(r"^Unimplemented imports: \d+ of \d+\n((?:  .*\n)+)", text, re.M)
    return [ln.strip() for ln in m[1].splitlines() if ln.startswith("    ")] if m else []


def wav_channel(wav, n):
    """The file PURE_AUDIO_WAV=wav writes sceAudio channel n to (1 the sceSas mix, 2 the music, 3 movie audio)."""
    return f"{wav}.ch{n}.wav"


def wav_files(wav):
    """Every file a PURE_AUDIO_WAV=wav capture may write: the mix, then channels 1 to 4."""
    return [str(wav)] + [wav_channel(wav, n) for n in range(1, 5)]


# ------------------------------------------------------------------------------- the sweep's results (task 094)

# tools/campaign_sweep.py's result line for a cell: the cell, the outcome, its detail, the flip, the laps, the race
# time, the wall seconds and the rest (`3 laps: 71.2, 69.8, 70.1 s, 12 contacts, ...`). Moved from
# tools/fidelity_audit.py, which imports it back.
SWEEP_LINE_RE = re.compile(r"^\[sweep\] (\S+): (PASS|STALL|HALT|NO RACE|TIMEOUT|STUCK)((?: \([^)]*\))?) at flip (\d+), "
                           r"(\d+) laps, race time ([\d.]+) s, (\d+) s: (.*)$")
LAPS_RE = re.compile(r"(\d+) laps: ([\d.]+(?:, [\d.]+)*) s")      # in the rest: the lap times
CONTACTS_RE = re.compile(r"(\d+) contacts")                       # in the rest: the follower's contacts
# PURE_WATCH_WORDS=ADDR (the profile): the word at ADDR once a flip, with the virtual time: frame, t (us), the word.
WORDS_RE = re.compile(r"\[pure\] words frame (\d+) t=(\d+): 0x([0-9A-Fa-f]{8})")
START_CENTRES = (0.5, 1.0, 1.5, 2.0)   # the standing start: the race clock (s) of the half-second speed bins


def sweep_result(path, cell):
    """The last result line of `cell` in the sweep's output at path: {outcome, laps, times, contacts}; outcome None,
    laps 0, times [] and contacts None when there is none."""
    result = dict(outcome=None, laps=0, times=[], contacts=None)
    with open(path, errors="replace") as f:
        for line in f:
            m = SWEEP_LINE_RE.match(line.strip())
            if m and m[1] == cell:
                lm, cm = LAPS_RE.search(m[8]), CONTACTS_RE.search(m[8])
                result = dict(outcome=m[2], laps=int(m[5]), times=[float(x) for x in lm[2].split(", ")] if lm else [],
                              contacts=int(cm[1]) if cm else None)
    return result


def race_cell(stdout, cell_dir, cell, pad_kmh_s=None, said=None):
    """A Time Trial cell of tools/campaign_sweep.py run with PURE_WATCH_WORDS=08a8c3dc (the game clock, a float, once
    a flip; tools/framerate_check.sh and tools/display_rate_check.sh --race): sweep_result() of the sweep's output
    `stdout`; from <cell_dir>/<cell>.trace.csv the race's flips a race-clock second after its first second (fps, over
    the flips `flips`), the mean km/h in the half second about each START_CENTRES clock (bins) and, with pad_kmh_s,
    the first speed pad (pad: the race clock and distance of the first row whose speed rises faster than pad_kmh_s
    km/h a second); from <cell_dir>/<cell>.log the game clock's advance a virtual second over those flips (clock)
    and, with said, the log's lines that start with it (said, stripped)."""
    result = sweep_result(stdout, cell)
    rows = []
    trace = os.path.join(cell_dir, f"{cell}.trace.csv")
    if os.path.exists(trace):
        with open(trace) as f:
            rows = [r for r in csv.DictReader(f) if r["race"] == "1" and r["clock"] not in ("", "nan")]
    pts = [(int(r["frame"]), float(r["clock"])) for r in rows if float(r["clock"]) > 1.0]
    fps = (pts[-1][0] - pts[0][0]) / (pts[-1][1] - pts[0][1]) if len(pts) > 1 else None
    pad = None
    if pad_kmh_s is not None:
        speeds = [(float(r["clock"]), float(r["kmh"]), float(r["dist"])) for r in rows
                  if r["kmh"] not in ("", "nan") and r["dist"] not in ("", "nan")]
        for (c0, k0, d0), (c1, k1, d1) in zip(speeds, speeds[1:]):
            if c0 > 0.0 and c1 > c0 and (k1 - k0) / (c1 - c0) > pad_kmh_s:
                pad = (c0, d0)
                break
    bins = []
    for c in START_CENTRES:
        kmh = [float(r["kmh"]) for r in rows
               if c - 0.25 <= float(r["clock"]) < c + 0.25 and r["kmh"] not in ("", "nan")]
        bins.append(sum(kmh) / len(kmh) if kmh else None)
    words, lines = [], []
    log = os.path.join(cell_dir, f"{cell}.log")
    if os.path.exists(log) and (pts or said):
        with open(log, errors="replace") as f:
            for line in f:
                if said and line.startswith(said):
                    lines.append(line.strip())
                    continue
                m = WORDS_RE.match(line)
                if m and pts and pts[0][0] <= int(m[1]) <= pts[-1][0]:
                    value = struct.unpack("<f", bytes.fromhex(m[3])[::-1])[0]
                    if value > 1000.0:
                        words.append((int(m[2]) / 1e6, value))
    clock = (words[-1][1] - words[0][1]) / (words[-1][0] - words[0][0]) if len(words) > 1 else None
    result.update(fps=fps, clock=clock, bins=bins, flips=(pts[0][0], pts[-1][0]) if pts else None, pad=pad,
                  said=lines)
    return result


# ----------------------------------------------------------------------------------- the flips' times (task 094)

# PURE_TRACE_CALLS=sceDisplay:0x289D82FE: a `[call]` line per flip (sceDisplaySetFrameBuf) with its virtual time t=.
FLIP_CALL = "[call] sceDisplay:0x289D82FE "
FLIP_T_RE = re.compile(r" t=(\d+)")


def flip_log(path, said=None):
    """A route run's flips and race (PURE_TRACE_CALLS=sceDisplay:0x289D82FE, PURE_WATCH_SHIP=1): the flip times
    (virtual us, index n - 1 for flip n), the ship lines' (flip, t, clock), and the lines that start with said
    (stripped) with the flips before each."""
    ts, ships, lines = [], [], []
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith(FLIP_CALL):
                ts.append(int(FLIP_T_RE.search(line)[1]))
            elif said and line.startswith(said):
                lines.append((line.strip(), len(ts)))
            else:
                m = SHIP_T_RE.match(line)
                if m:
                    ships.append((int(m[1]), int(m[2]), float(m[3])))
    return ts, ships, lines


def flip_median_ms(ts, a, b):
    """The median interval (ms) of flips a..b, None without one."""
    steps = [ts[n - 1] - ts[n - 2] for n in range(max(a, 2), min(b, len(ts)) + 1)]
    return statistics.median(steps) / 1000.0 if steps else None


def flips_per_second(ts, a, b):
    """Flips a second of virtual time over flips a..b, None without a span."""
    b = min(b, len(ts))
    return (b - a) / ((ts[b - 1] - ts[a - 1]) / 1e6) if b > a and ts[b - 1] > ts[a - 1] else None


# ------------------------------------------------------------------------------- E8's display rate (task 094)

# The profile's line when the vblank period changes (src/profile/enhancements.cpp, display_rate): `off`, the line
# outside a race (the display's Hz, the game's rate in a race, the margin) and the race's (the display's Hz, the
# game's rate, the margin, the period in us). tools/display_rate_check.sh defined the last two twice.
DISPLAY_RATE = "[pure] display rate: "
DISPLAY_OFF = "[pure] display rate: off"
DISPLAY_OUTSIDE_RE = re.compile(r"^\[pure\] display rate: (\d+) Hz display, the game at ([\d.]+) Hz in a race "
                                r"\(margin ([^)]+)\), the PSP's 59\.94 Hz outside one$")
DISPLAY_RACE_RE = re.compile(r"^\[pure\] display rate: (\d+) Hz display, the game at ([\d.]+) Hz \(margin ([^,]+), "
                             r"(\d+) us a vblank\)$")
DISPLAY_HZ_RE = re.compile(r"(\d+) Hz display, the game at ([\d.]+) Hz")    # either line: the display, the game's rate
PSP_VBLANK_US = 16683          # the PSP's vblank period


def display_margin(texts, hz, margin_arg=""):
    """The margin and the period a run at the display's rate names (texts: its display-rate lines, the one outside a
    race first, then the race's, which may alternate) and what is wrong with them: the display hz in both, one margin
    (margin_arg's when given), the period round(1e6 / (hz x (1 - margin))) and the game's rate 1e6 / period."""
    outside = DISPLAY_OUTSIDE_RE.match(texts[0]) if texts else None
    races = [t for t in texts if t != texts[0]]
    race = DISPLAY_RACE_RE.match(races[0]) if races else None
    if not outside or not race or any(t != races[0] for t in races):
        return None, None, [f"display rate lines {texts} (the line outside a race first, then the race's)"]
    margin, period, problems = float(race[3]), int(race[4]), []
    want = int(1e6 / (hz * (1.0 - margin)) + 0.5)
    if int(outside[1]) != hz or int(race[1]) != hz:
        problems.append(f"the lines name a {outside[1]} and a {race[1]} Hz display, not {hz}")
    if float(outside[3]) != margin:
        problems.append(f"the lines name the margins {outside[3]} and {race[3]}")
    if margin_arg and margin != float(margin_arg):
        problems.append(f"the margin {race[3]}, not --margin's {margin_arg}")
    if period != want:
        problems.append(f"the period {period} us, not round(1e6 / ({hz} x (1 - {race[3]}))) = {want}")
    if not outside[2] == race[2] == f"{1e6 / period:.2f}":
        problems.append(f"the game's rate {outside[2]} and {race[2]} Hz, not 1e6 / {period} = {1e6 / period:.2f}")
    return margin, period, problems


# ------------------------------------------------- the framework's per-second and per-frame lines (task 094)

# PURE_PERF=log, a line a second (vendor host/perf/frame_stats.cpp): `fps` the presents, `game` the game's flips,
# `speed` its virtual time against real time, the second's mean and worst frame, and after the present mode and the
# drawable's size the display's refresh (` 120Hz`) when the shell knows it.
PERF_RE = re.compile(r"^\[perf\] fps ([\d.]+) game ([\d.]+) speed (\d+)% \| frame avg ([\d.]+) max ([\d.]+) ms")
PERF_HZ_RE = re.compile(r" (\d+)Hz(?: \||$)")
# PURE_TRACE_STALLS=1: a `[stalls]` line a second (ms a frame over the line's frames; `readback R max M` the GPU's
# drains for a write-back) and, with PURE_TRACE_STALLS_MS=N, a `[slow-frame] FLIP MS ms` line for each frame over N
# ms, ` pacing P xK` the part of it the pacer slept (the game ahead of real time).
STALLS_RE = re.compile(r"^\[stalls\] ms per frame over (\d+) frames:")
READBACK_RE = re.compile(r" readback ([\d.]+) max")
SLOW_FRAME_RE = re.compile(r"^\[slow-frame\] (\d+) ([\d.]+) ms")
PACING_RE = re.compile(r" pacing ([\d.]+) x\d")
# PURE_TRACE_AUDIO=1: the audio sink's line a second; `resyncs=` counts the stalled producer's jumps (patch
# 0024-audio-resync-counter), each a skip in the sound.
AUDIO_RE = re.compile(r"^\[audio\] (\d+)s .* resyncs=(\d+) ")
PACED = "[pure] paced from frame"                  # PURE_PACED_FROM=N: the first paced flip
PACED_RE = re.compile(r"^\[pure\] paced from frame (\d+)")


def perf(line):
    """A `[perf]` line's figures ({fps, game, speed, frame_avg, frame_max, hz}; hz 0 when the line names no
    refresh), or None."""
    m = PERF_RE.match(line)
    if not m:
        return None
    h = PERF_HZ_RE.search(line)
    return dict(fps=float(m[1]), game=float(m[2]), speed=int(m[3]), frame_avg=float(m[4]), frame_max=float(m[5]),
                hz=int(h[1]) if h else 0)


def stalls(line):
    """A `[stalls]` line's (frames, readback ms a frame; 0.0 without a readback), or None."""
    m = STALLS_RE.match(line)
    if not m:
        return None
    r = READBACK_RE.search(line)
    return int(m[1]), float(r[1]) if r else 0.0


def slow_frame(line):
    """A `[slow-frame]` line's (flip, ms with the frame's own pacing sleep taken off), or None."""
    m = SLOW_FRAME_RE.match(line)
    if not m:
        return None
    p = PACING_RE.search(line)
    return int(m[1]), float(m[2]) - (float(p[1]) if p else 0.0)


def audio_resyncs(line):
    """An `[audio]` line's (second, resyncs), or None."""
    m = AUDIO_RE.match(line)
    return (int(m[1]), int(m[2])) if m else None


# ----------------------------------------------------------------------------------- the window guard (task 094)

# Unpaced, a window on screen presents at most the display's refresh a second (vsync holds it); one that is covered,
# on another Space or on a display asleep presents without it, hundreds a second, and a run in it measures nothing
# (task 091 found a browser window covering the game in most of its runs; tools/winwatch.m says what covers it).
SCREEN_HELD = 1.5          # unpaced presents a second over this times the display's refresh: not on screen
NOT_SHOWN = "the window was not on screen"


def window_shown(presents, hz, held_by=SCREEN_HELD):
    """Whether vsync held a window on screen: there are unpaced presents a second to judge, the display's refresh hz
    is known, and none of them is over held_by x hz."""
    return bool(presents) and hz > 0 and all(p <= held_by * hz for p in presents)


def window_guard(path, held_by=SCREEN_HELD):
    """The window guard of a window run's log (PURE_PERF=log; tools/display_rate_check.sh --audio and
    tools/stutter_check.sh): its unpaced seconds (the `[perf]` lines before `[pure] paced from frame`), split at the
    race's `[pure] display rate` line when there is one (E8 on) into the menus (their first two seconds, the game's
    start, left out) and the race load. The load's seconds are judged, else the menus' last three, against the
    display's refresh (the race line's, else the `[perf]` lines'). A dict: race ((hz, rate, margin, period) or None),
    menus, load, judged, hz, shown, and problem (None, or why the run measured nothing)."""
    race, menus, load, paced, hz = None, [], [], False, 0
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith(PACED):
                paced = True
            if paced:
                continue
            if race is None:
                m = DISPLAY_RACE_RE.match(line.rstrip("\n"))
                if m:
                    race = (int(m[1]), float(m[2]), m[3], int(m[4]))
                    continue
            p = perf(line)
            if p:
                (menus if race is None else load).append(p["fps"])
                hz = p["hz"] or hz
    menus = menus[2:]
    if race is not None:
        hz = race[0]
    judged = load or menus[-3:]
    shown = window_shown(judged, hz, held_by)
    problem = None
    if not shown:
        where = "at the race load" if race is not None else "in its unpaced menus"
        over = f"over {held_by:g} x {hz}" if hz else "and no display refresh named"
        problem = (f"{NOT_SHOWN} {where} (unpaced presents {judged or '-'} a second, {over}): vsync did not hold the "
                   f"run, so it measured nothing; run it again with the window shown")
    return dict(race=race, menus=menus, load=load, judged=judged, hz=hz, shown=shown, problem=problem)


# ------------------------------------------------------- the fidelity audit's scan of a sweep log (task 094)
# Moved from tools/fidelity_audit.py (which imports them back; its module doc describes the findings), so the gates
# read a sweep log with the audit's rule without importing the audit and, with it, tools/campaign_sweep.py.

STRETCH_MIN = 3                 # flips in a row at two vblanks that make a stretch (task 033's rule)
TWO_VBLANK_US = 25000           # a race flip whose virtual time step exceeds this waited two vblanks (16683 us one)
HITCH_US = 45000                # one that exceeds this waited three or more: a hitch
# What counts as a warning in the subsystem tags (case-insensitive).
WARN_RE = re.compile(r"cannot|can't|not (emulated|implemented|supported)|unsupported|fail|error|warn|unknown|"
                     r"ran out|missing|dropped|too (many|large|big)|overflow|invalid|stall|timeout|lost", re.I)
TAG_RE = re.compile(r"^\[(render|mpeg|atrac|sas|psmfplayer|savedata|audio|metal|io)\]")
GUEST_BAD_RE = re.compile(r"error|fail|assert|warn", re.I)
TRACK_RE = re.compile(r"\[io\] open disc0:/PSP_GAME/USRDIR/Data/(Environments|ClassicsNS|Zone)/([^/]+)/TrackStartup")
THREADS_RE = re.compile(r"^threads \(virtual time (\d+) ms, vblanks (\d+)\)")
STOPPED_RE = re.compile(r"Runtime stopped: (.*)")
SAVEDATA_RE = re.compile(r"^\[savedata\] (\w+) \((\d+)\) game=\"(\w*)\" save=\"(\w*)\" file=\"([\w.]*)\"")


def normalise(text):
    """A line as a feature: numbers that change from run to run (frames, times, counts) taken out."""
    text = text.strip()
    m = UNDERRUN_RE.search(text)
    if m:
        return f"[pure] audio capture: channel {m[1]} underrun (the game handed sceAudio a buffer late)"
    text = re.sub(r"\bframe \d+\b", "frame N", text)
    text = re.sub(r"\bt=\d+\b", "t=T", text)
    text = re.sub(r"\bra=0x[0-9A-Fa-f]+", "ra=...", text)
    return text


def scan_log(path, fps=60):
    """The findings of one sweep log (tools/fidelity_audit.py's module doc lists them). With fps 30 (Time Trial, Free Play, Zone: two vblanks a
    flip throughout) no stretches are looked for."""
    found = {"features": {}, "ignored": {}, "stretches": [], "hitches": [], "tracks": [], "saves": [], "exit": {},
             "min_fps": None,
             "unimplemented": None, "stopped": None, "race_start_s": None, "end_s": None, "races": 0}
    feats = found["features"]

    def add(text):
        key = normalise(text)
        feats[key] = feats.get(key, 0) + 1

    prev = None            # (frame, t) of the previous ship line of the race
    lapn, last_clock = 0, 0.0   # laps begun in the current race (the lap clock restarts at each line crossing)
    run = []               # the current run of two-vblank flips: (frame, t_us, clock, dist, lap)
    in_ignored = False
    unimpl = []
    in_unimpl = False
    race_on = False
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if in_unimpl:
                if line.startswith("    "):
                    unimpl.append(line.strip())
                    continue
                if line.startswith("  "):
                    continue
                in_unimpl = False
            if in_ignored:
                m = GE_IGNORED_RE.match(line)
                if m:
                    op, count, first = int(m[1], 16), int(m[2]), int(m[3], 16)
                    found["ignored"][op] = {"count": count, "first": first}
                    continue
                in_ignored = False
            s = SHIP_T_RE.match(line)
            if s:
                frame, t, clock, dist, lap = int(s[1]), int(s[2]), float(s[3]), float(s[5]), int(s[6])
                if race_on and clock < last_clock - 1.0:
                    lapn += 1
                last_clock = clock
                if clock > 0.0 and not race_on:
                    race_on = True
                    lapn = 1
                    found["races"] += 1
                    if found["race_start_s"] is None:
                        found["race_start_s"] = t / 1e6
                if race_on:
                    found["end_s"] = t / 1e6
                if (race_on and prev is not None and frame == prev[0] + 1 and clock > 0.0 and lap < 0x10000
                        and t - prev[1] > HITCH_US):
                    # A flip three vblanks or more after the one before: the game held up, or the host (paced, the
                    # kernel's clock then catches up with real time at once, and the audio channels underrun).
                    found["hitches"].append((frame, round((t - prev[1]) / 1000), round(t / 1e6, 1), round(dist)))
                if (fps == 60 and race_on and prev is not None and frame == prev[0] + 1 and clock > 0.0
                        and lap < 0x10000):
                    if t - prev[1] > TWO_VBLANK_US:
                        run.append((frame, t, clock, dist, lapn, float(s[4])))
                    else:
                        if len(run) >= STRETCH_MIN:
                            found["stretches"].append(stretch_of(run, found["races"]))
                        run = []
                prev = (frame, t)
                continue
            if PLAYER_RE.match(line):
                if len(run) >= STRETCH_MIN:
                    found["stretches"].append(stretch_of(run, found["races"]))
                run, prev, race_on = [], None, False
                continue
            if line.startswith("[pure] frame ") or line.startswith("[script]") or line.startswith("    ..."):
                continue
            m = TRACK_RE.search(line)
            if m:
                found["tracks"].append(m[2])
                continue
            m = SAVEDATA_RE.match(line)
            if m:
                found["saves"].append(f"{m[1]} {m[3]}{m[4]}/{m[5]}")
                continue
            if line.startswith("GE commands ignored:"):
                in_ignored = True
                continue
            m = UNIMPL_RE.match(line)
            if m:
                in_unimpl = True
                found["unimplemented"] = f"{m[1]} of {m[2]}"
                continue
            m = METAL_FPS_RE.match(line)
            if m:
                fr, rate = int(m[1]), float(m[2])
                if found["race_start_s"] is not None and (found["min_fps"] is None or rate < found["min_fps"][1]):
                    found["min_fps"] = (fr, rate)
                continue
            e = metal_exit(line) or metal_pipelines(line)
            if e:
                found["exit"].update(e)
                continue
            m = THREADS_RE.match(line)
            if m:
                found["exit"].update(virtual_ms=int(m[1]), vblanks=int(m[2]))
                continue
            m = STOPPED_RE.search(line)
            if m:
                found["stopped"] = m[1].strip()
                if "quit from the input script" not in m[1] and "PURE_EXIT_AT_FRAME" not in m[1]:
                    add(line)
                continue
            if "[hle-stub]" in line or "unsupported" in line.lower():
                add(line)
                continue
            if UNDERRUN_RE.search(line):
                add(line)
                m = re.search(r"channel (\d+) underrun of \d+ frames \((\d+) ms\) at t=(\d+)", line)
                if m:
                    found.setdefault("underruns", []).append((int(m[1]), int(m[2]), round(int(m[3]) / 1e6, 2)))
                continue
            tag = TAG_RE.match(line)
            if tag:
                if tag[1] == "metal" and ("not emulated" in line or "not implemented" in line):
                    add(line)
                elif tag[1] in ("metal", "io"):
                    continue
                elif WARN_RE.search(line):
                    add(line)
                continue
            if line.startswith("[guest]") and GUEST_BAD_RE.search(line):
                add(line)
    if len(run) >= STRETCH_MIN:
        found["stretches"].append(stretch_of(run, found["races"]))
    if unimpl:
        found["unimplemented_list"] = unimpl
    return found


def stretch_of(run, race):
    first, last = run[0], run[-1]
    return {"race": race, "flip": first[0], "flips": len(run), "seconds": round((last[1] - first[1]) / 1e6 + 0.0334, 2),
            "clock": round(first[2], 1), "dist": round(first[3]), "lap": first[4], "kmh": round(first[5])}


# ------------------------------------------------------------------------------------------------ --selftest

def selftest():
    """The readers on synthetic lines, written to a temporary directory: True when every check holds."""
    import tempfile
    failed = []

    def check(name, got, want):
        ok = got == want
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}" + ("" if ok else f": {got!r}, not {want!r}"))
        if not ok:
            failed.append(name)

    def perf_line(fps, hz=120, speed=100):
        return (f"[perf] fps {fps:.1f} game 60.0 speed {speed}% | frame avg 8.3 max 9.0 ms | guest 1.0 render 2.0 "
                f"wait 5.0 ms | lists 120/s draws 900/900 | FIFO 1920x1088" + (f" {hz}Hz" if hz else "")
                + " | gpu n/a")

    with tempfile.TemporaryDirectory() as tmp:
        def write(name, lines):
            path = os.path.join(tmp, name)
            with open(path, "w") as f:
                f.write("\n".join(lines) + "\n")
            return path

        # The sweep's result line: the cell's last one counts, another cell's is ignored.
        out = write("sweep.stdout", [
            "[sweep] time_trial-vineta_k: STALL at flip 9000, 1 laps, race time 70.0 s, 30 s: 1 laps: 70.0 s",
            "[sweep] zone-zone_1: PASS at flip 9000, 0 laps, race time 10.0 s, 20 s: zone 2",
            "[sweep] time_trial-vineta_k: PASS (results) at flip 17000, 3 laps, race time 212.4 s, 240 s: "
            "3 laps: 71.20, 70.60, 70.60 s, 12 contacts, the end"])
        check("sweep_result", sweep_result(out, "time_trial-vineta_k"),
              dict(outcome="PASS", laps=3, times=[71.2, 70.6, 70.6], contacts=12))
        check("sweep_result without the cell", sweep_result(out, "single_race-vineta_k")["outcome"], None)

        # A Time Trial cell: 60 flips a race-clock second, the start bins, a speed pad, the game clock.
        cell = os.path.join(tmp, "cell")
        os.makedirs(cell)
        rows = ["frame,race,clock,kmh,dist"]
        for n in range(361):            # race clock 0 to 6 s at 60 flips a second; a pad at 3 s (+60 km/h at once)
            c = n / 60.0
            rows.append(f"{6000 + n},1,{c:.4f},{100.0 * c + (60.0 if c >= 3.0 else 0.0):.2f},{10.0 * n:.1f}")
        with open(os.path.join(cell, "time_trial-vineta_k.trace.csv"), "w") as f:
            f.write("\n".join(rows) + "\n")
        words = [DISPLAY_OFF]
        for n in range(361):            # the game clock (a float above 1000) advancing 1 s a virtual second
            t = 100_000_000 + n * 16683
            words.append(f"[pure] words frame {6000 + n} t={t}: 0x{struct.pack('>f', 2000.0 + t / 1e6).hex()}")
        write(os.path.join("cell", "time_trial-vineta_k.log"), words)
        r = race_cell(out, cell, "time_trial-vineta_k", pad_kmh_s=300, said=DISPLAY_RATE)
        check("race_cell fps", round(r["fps"], 3), 60.0)
        check("race_cell flips", r["flips"], (6061, 6360))
        check("race_cell bins", [round(b, 1) for b in r["bins"]], [49.2, 99.2, 149.2, 199.2])
        check("race_cell pad", (round(r["pad"][0], 3), r["pad"][1]), (2.983, 1790.0))
        check("race_cell clock", round(r["clock"], 4), 1.0)
        check("race_cell said", r["said"], [DISPLAY_OFF])

        # The flips: two vblanks a flip, then one; a said line after flip 3; ship lines with clock and t.
        ts = [16683 * 2 * n for n in range(1, 11)] + [16683 * 20 + 16683 * n for n in range(1, 11)]
        lines = []
        for n, t in enumerate(ts, 1):
            lines.append(f"{FLIP_CALL}a0=0x0 t={t}")
            if n == 3:
                lines.append("[pure] sixty fps: on (game.sixty_fps)")
            if n > 10:
                lines.append(f"[pure] ship frame {n} t={t} clock={(n - 10) / 60:.3f} pos=0,0,0 vel=0,0,0 kmh=100 "
                             f"dist=5 lap=1")
        got_ts, ships, said = flip_log(write("flips.log", lines), "[pure] sixty fps:")
        check("flip_log flips", len(got_ts), 20)
        check("flip_log said", said, [("[pure] sixty fps: on (game.sixty_fps)", 3)])
        check("flip_log ships", (len(ships), ships[0][:2]), (10, (11, ts[10])))
        check("flip_median_ms 2..10", round(flip_median_ms(got_ts, 2, 10), 3), 33.366)
        check("flip_median_ms 12..20", round(flip_median_ms(got_ts, 12, 20), 3), 16.683)
        check("flips_per_second 11..20", round(flips_per_second(got_ts, 11, 20), 2), 59.94)

        # E8's lines: a consistent pair, then a period the margin does not give.
        outside = ("[pure] display rate: 120 Hz display, the game at 119.40 Hz in a race (margin 0.005), the PSP's "
                   "59.94 Hz outside one")
        race = "[pure] display rate: 120 Hz display, the game at 119.40 Hz (margin 0.005, 8375 us a vblank)"
        check("display_margin", display_margin([outside, race, outside, race], 120, "0.005"), (0.005, 8375, []))
        bad = race.replace("8375", "8333")
        check("display_margin wrong period", len(display_margin([outside, bad], 120)[2]), 2)
        check("display_margin no race line", display_margin([outside], 120)[0], None)

        # The framework's lines.
        check("perf", perf(perf_line(119.9)),
              dict(fps=119.9, game=60.0, speed=100, frame_avg=8.3, frame_max=9.0, hz=120))
        check("perf without a refresh", perf(perf_line(60.0, hz=0))["hz"], 0)
        check("stalls", stalls("[stalls] ms per frame over 120 frames: readback 0.42 max 3.10 x7 present 0.10 x120"),
              (120, 0.42))
        check("stalls without a readback", stalls("[stalls] ms per frame over 60 frames: present 0.10 x60"),
              (60, 0.0))
        check("slow_frame less its pacing", slow_frame("[slow-frame] 6421 31.5 ms: render 4.0 pacing 10.0 x1"),
              (6421, 21.5))
        check("audio_resyncs", audio_resyncs("[audio] 193s queued 4800 frames resyncs=1 underruns=0"), (193, 1))
        check("other lines", (perf("[perf] GPU timestamps: 64 bits"), stalls("[stalls] x"), slow_frame("x"),
                              audio_resyncs("[audio] 3s resyncs=x")), (None, None, None, None))

        # The window guard: E8 on (the race line splits menus and load) and off (the [perf] lines name the refresh).
        start = [perf_line(400.0), perf_line(300.0)]                 # the game's first two seconds: not judged
        paced = ["[pure] paced from frame 5900", perf_line(5000.0)]   # paced seconds are not unpaced ones
        g = window_guard(write("on.log", start + [perf_line(120.0)] * 40 + [race, perf_line(116.1)] + paced))
        check("window_guard on screen (E8)", (g["shown"], g["judged"], g["hz"], g["problem"]), (True, [116.1], 120, None))
        g = window_guard(write("covered.log", start + [perf_line(1771.4)] * 3 + [race, perf_line(404.5)] + paced))
        check("window_guard covered (E8)", (g["shown"], g["problem"].startswith(NOT_SHOWN + " at the race load")),
              (False, True))
        g = window_guard(write("off.log", start + [perf_line(119.0), perf_line(120.0), perf_line(118.0)] + paced))
        check("window_guard on screen (E8 off)", (g["shown"], g["judged"], g["race"]), (True, [119.0, 120.0, 118.0],
                                                                                        None))
        g = window_guard(write("off_covered.log", start + [perf_line(1552.7), perf_line(2203.9)] + paced))
        check("window_guard covered (E8 off)", (g["shown"], g["problem"].startswith(NOT_SHOWN + " in its unpaced")),
              (False, True))
        g = window_guard(write("short.log", start + paced))
        check("window_guard nothing unpaced to judge", g["shown"], False)
        g = window_guard(write("nohz.log", [perf_line(400.0, hz=0)] * 2 + [perf_line(60.0, hz=0)] * 3 + paced))
        check("window_guard no refresh named", (g["shown"], g["hz"]), (False, 0))
        check("window_shown at 1.5 x", (window_shown([180.0], 120), window_shown([180.1], 120)), (True, False))

        # The audit's scan: a race (the clock starts), four flips at two vblanks in a row (a stretch), one step of
        # three vblanks (a hitch), a stub line as a feature.
        lines = ["[pure] ship frame 99 player object 0x1 index 7"]
        t, frame = 0, 100
        for step in [16683] * 5 + [33366] * 4 + [16683] * 3 + [50050] + [16683] * 3:
            t += step
            frame += 1
            lines.append(f"[pure] ship frame {frame} t={t} clock={(frame - 100) / 60:.3f} pos=0,0,0 vel=0,0,0 "
                         f"kmh=200 dist={frame} lap=1")
        lines.append("[hle-stub] sceFoo ra=0x08800000")
        found = scan_log(write("sweep.log", lines))
        check("scan_log stretches", [(s["flip"], s["flips"]) for s in found["stretches"]], [(106, 4)])
        check("scan_log hitches", [h[0] for h in found["hitches"]], [113])
        check("scan_log features", found["features"], {"[hle-stub] sceFoo ra=...": 1})
        check("scan_log at 30 fps", scan_log(os.path.join(tmp, "sweep.log"), 30)["stretches"], [])
    print(f"logs selftest: {'FAIL (' + ', '.join(failed) + ')' if failed else 'PASS'}")
    return not failed


if __name__ == "__main__":
    if sys.argv[1:] != ["--selftest"]:
        sys.exit("usage: python3 tools/purelib/logs.py --selftest")
    sys.exit(0 if selftest() else 1)
