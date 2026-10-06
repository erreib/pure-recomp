#!/usr/bin/env python3
"""The fidelity audit (task 035): the campaign matrix headless, one cell at a time, and what every cell's log says.

  tools/fidelity_audit.py [--quick | --cells FILE] [--resume] [--only CELL[,CELL...]] [--audio | --no-audio]
                          [--keep-wav] [--out DIR] [--report] [--rescan] [--list]
  tools/fidelity_audit.py --ppsspp-race TRACK [--out DIR] [--wall-limit S]

Runs each cell of the list through tools/campaign_sweep.py (headless on the Metal backend, the sweep's default;
`--no-damage`, and `--unlock-all` where the sweep decides a new profile lacks the track or class), one after the
other, never beside another game (the sweep refuses to start then). The sweep itself sets PURE_LIST_STUBS=1 and
PURE_STRICT_HLE=1; this tool removes every PURE_TRACE_* switch from the environment the cells inherit, and gives each
cell PURE_AUDIO_WAV (unless --no-audio) so its audio can be measured. From each cell's log it collects:
  - every `[hle-stub]` line, every line with `unsupported`, every `Runtime stopped` other than the sweep's own quit
    and the frame exit, every `[metal] ... is not emulated` and `[metal] ... not implemented` line, the warning lines
    of `[render]`, `[mpeg]`, `[atrac]`, `[sas]`, `[psmfplayer]`, `[savedata]` and `[audio]` (WARN_RE), the game's
    own `[guest]` lines that say error, fail, assert or warn, the audio capture's underruns, the start-up list of
    unimplemented imports, and the framework's exit list of GE commands it ignores (named by GE_NAMES);
  - the follower's outcome (the sweep's last `[sweep] CELL: OUTCOME ...` line: PASS, STALL, HALT, NO RACE, TIMEOUT,
    STUCK) and its detail;
  - the backend's exit stats (`[metal] N frames, ...`, `[metal] pipelines: ...`, the lowest `[metal] frame N ... fps`
    of the race) and the kernel's (`threads (virtual time ...)`);
  - the tracks the race loads opened (`[io] open .../<track dir>/TrackStartup.xml`), which proves the route picked
    the track it meant to;
  - the two-vblank stretches (task 033): runs of STRETCH_MIN or more race flips in a row whose virtual time step (the
    `t=` of consecutive `[pure] ship` lines) is two vblanks, with the race clock, the track distance and the lap
    where each starts. Only the 60-flip modes (Single Race, Tournament) can show them; the others run at two
    vblanks a flip throughout;
  - the audio (with PURE_AUDIO_WAV): tools/wavstats.py over the mix, the sceSas channel (1) and the music channel
    (2) from the race start (the first ship line with a running clock) to the cell's end, then the WAVs are removed
    (--keep-wav keeps them).
Each cell's findings go to <out>/cells/<cell>.json (the sweep's own outputs, logs and shots to <out>/sweep/), and
after every cell the two tables are written again from the JSON files of the invocation's list:
  <out>/matrix.md     one row per cell (cells of the list not run yet say so)
  <out>/features.md   one row per distinct line: the text, the cells it appeared in, the count, the first cell
The default list is the brief's matrix (FULL, 46 cells): Single Race on all 12 circuits at Vector and at Phantom,
Time Trial on every circuit at Vector, Free Play on one circuit per league, Tournament on every league, Zone 1 to 4.
--quick runs three cells (Single Race Vineta K, Zone 1, Time Trial Vineta K); --cells FILE reads a list, one cell a
line, `MODE TRACK [CLASS]` (`#` starts a comment). --resume skips the cells that already have a JSON file;
--only runs the named cells of the list (names as the sweep makes them: `single_race-vineta_k-phantom`).
--report writes the tables from the JSON files without running anything; --rescan reads the cells' logs again first
(the outcome and the audio kept); --list prints the cells.

The sweep's MODES pick a league only in Single Race: Time Trial and Free Play list the Alpha circuits, Tournament the
Alpha league. For the other circuits and leagues this tool extends MODES in the sweep's own process (extend_modes;
tools/campaign_sweep.py is not changed): Time Trial and Free Play get Single Race's league pick (DOWN presses from
5180 on LEAGUE SELECTION, which these modes show at the same flips) and the Beta and Classic circuits, Tournament the
Beta and Classic leagues (DOWN from 5180 on TOURNAMENT SELECTION) with their four races each. Such cells run through
`tools/fidelity_audit.py --sweep-cell ...` (the sweep's main() after the extension) and their rows say `(extended)`;
the opened TrackStartup.xml shows whether the pick held.

Between cells the tool waits while <out>/hold exists (another game can run then, one at a time) and stops when
<out>/stop exists. Exit 0 when every cell of the invocation ran (whatever its outcome), 2 on bad arguments.
"""
import argparse, json, math, os, re, struct, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import campaign_sweep as cs  # noqa: E402  (tools/campaign_sweep.py, imported for its names; never modified)

OUT = "out/fidelity"
QUICK = [("single_race", "vineta_k", "vector"), ("zone", "zone_1", "vector"), ("time_trial", "vineta_k", "vector")]
ALL_TRACKS = cs.ALPHA + cs.BETA + cs.CLASSIC
FULL = ([("single_race", t, "vector") for t in ALL_TRACKS] + [("single_race", t, "phantom") for t in ALL_TRACKS]
        + [("time_trial", t, "vector") for t in ALL_TRACKS]
        + [("free_play", t, "vector") for t in ("vineta_k", "sol_2", "karbonis")]
        + [("tournament", lg, "vector") for lg in ("alpha", "beta", "classic")]
        + [("zone", z, "vector") for z in cs.ZONES])
STRETCH_MIN = 3                 # flips in a row at two vblanks that make a stretch (task 033's rule)
TWO_VBLANK_US = 25000           # a race flip whose virtual time step exceeds this waited two vblanks (16683 us one)
LEAGUE_AT = 5180                # Single Race's league pick; Time Trial and Free Play show LEAGUE SELECTION then too
EXTENDED_MPS = 30.0             # budget speed for the extended 30-flip cells (the follower is slower there)


def extend_modes():
    """Adds to the sweep's MODES (in this process only) the circuits and leagues its routes reach but its tables do
    not list: Time Trial and Free Play on the Beta and Classic circuits (the league picked as in Single Race),
    Tournament on the Beta and Classic leagues. Returns the (mode, track) pairs added."""
    added = []
    for mode in ("time_trial", "free_play"):
        m = cs.MODES[mode]
        if "leagues" in m:
            continue
        m["leagues"] = cs.LEAGUES
        m["league_at"] = LEAGUE_AT
        m["fresh"] = list(cs.ALPHA)
        m["tracks"] = list(m["tracks"])       # the sweep's list is cs.ALPHA itself
        m["frames"] = dict(m["frames"])
        for t in cs.BETA + cs.CLASSIC:
            m["tracks"].append(t)
            seconds = 3 * cs.LENGTHS[t] / EXTENDED_MPS + 15.0
            m["frames"][t] = int(math.ceil(seconds * 30 / 500.0) * 500)
            added.append((mode, t))
    t = cs.MODES["tournament"]
    t["tracks"], t["races"], t["frames"] = list(t["tracks"]), dict(t["races"]), dict(t["frames"])
    for lg in ("beta", "classic"):
        if lg in t["tracks"]:
            continue
        t["tracks"].append(lg)
        t["races"][lg] = list(cs.LEAGUES[lg])
        t["frames"][lg] = sum(cs.MODES["single_race"]["frames"][r] for r in cs.LEAGUES[lg]) + 4 * 3000
        t.setdefault("fresh", ["alpha"])
        added.append(("tournament", lg))
    if "single_race_save" not in cs.MODES:
        # Item 5 (saves and records): a Single Race that goes on past its results panel. The sweep's Tournament end
        # rule with one race: Cross every ADVANCE_EVERY flips through ENTER TAG and the screens after it, until the
        # rule's limit (ADVANCE_LIMIT flips) ends the cell as STUCK; the memory stick then holds what the game saved.
        sr = cs.MODES["single_race"]
        cs.MODES["single_race_save"] = dict(sr, end="standings", tracks=list(cs.ALPHA), fresh=list(cs.ALPHA),
                                            races={t: [t] for t in cs.ALPHA}, leagues={"alpha": cs.ALPHA},
                                            frames={t: sr["frames"][t] + cs.ADVANCE_LIMIT + 1000 for t in cs.ALPHA})
        added += [("single_race_save", t) for t in cs.ALPHA]
    return added


def is_extended(mode, track):
    return (mode in ("time_trial", "free_play") and track not in cs.ALPHA) or \
        (mode == "tournament" and track != "alpha") or mode == "single_race_save"


# The GE commands the framework's GE state ignores (vendor/portablekit/host/gpu/ge_state.cpp lists them at exit),
# by the GE's names (PPSSPP's GPU/ge_constants.h and the PSP SDK's pspge.h, read for the names only), with what an
# ignored one means for the picture.
GE_NAMES = {
    0x14: ("ORIGIN", "draw origin"), 0x15: ("REGION1", "drawing region (the scissor is used instead)"),
    0x16: ("REGION2", "drawing region (the scissor is used instead)"), 0x17: ("LIGHTINGENABLE", "lighting"),
    0x1C: ("CLIPENABLE", "depth clamp / clipping enable"), 0x20: ("DITHERENABLE", "dithering"),
    0x25: ("ANTIALIASENABLE", "anti-aliasing (no effect on a PSP)"), 0x26: ("PATCHCULLENABLE", "patch culling"),
    0x27: ("COLORTESTENABLE", "the colour test"), 0x28: ("LOGICOPENABLE", "logic ops"),
    0x2C: ("MORPHWEIGHT0", "vertex morphing"), 0x2D: ("MORPHWEIGHT1", "vertex morphing"),
    0x2E: ("MORPHWEIGHT2", "vertex morphing"), 0x2F: ("MORPHWEIGHT3", "vertex morphing"),
    0x30: ("MORPHWEIGHT4", "vertex morphing"), 0x31: ("MORPHWEIGHT5", "vertex morphing"),
    0x32: ("MORPHWEIGHT6", "vertex morphing"), 0x33: ("MORPHWEIGHT7", "vertex morphing"),
    0x36: ("PATCHDIVISION", "Bezier/spline patches"), 0x37: ("PATCHPRIMITIVE", "Bezier/spline patches"),
    0x38: ("PATCHFACING", "Bezier/spline patches"), 0x50: ("SHADEMODE", "flat or Gouraud shading"),
    0x51: ("REVERSENORMAL", "reversed normals"), 0x53: ("MATERIALUPDATE", "material from vertex colour"),
    0xC0: ("TEXMAPMODE", "texture map mode (environment and projection mapping)"),
    0xC1: ("TEXSHADELS", "environment-map light sources"), 0xC8: ("TEXLEVEL", "mipmap level mode"),
    0xCA: ("TEXENVCOLOR", "the blend texture function's colour"), 0xCB: ("TEXFLUSH", "texture cache flush"),
    0xCC: ("TEXSYNC", "texture sync"), 0xD0: ("TEXLODSLOPE", "mipmap LOD slope"),
    0xD6: ("MINZ", "depth range clamp"), 0xD7: ("MAXZ", "depth range clamp"),
    0xD8: ("COLORTEST", "the colour test"), 0xD9: ("COLORREF", "the colour test"),
    0xDA: ("COLORTESTMASK", "the colour test"), 0xE2: ("DITH1", "dithering matrix"),
    0xE3: ("DITH2", "dithering matrix"), 0xE4: ("DITH3", "dithering matrix"), 0xE5: ("DITH4", "dithering matrix"),
    0xE6: ("LOGICOP", "logic ops"),
}
for _n in range(1, 8):
    GE_NAMES[0xA0 + _n] = (f"TEXADDR{_n}", "mipmap level address")
    GE_NAMES[0xA8 + _n] = (f"TEXBUFWIDTH{_n}", "mipmap level address")
    GE_NAMES[0xB8 + _n] = (f"TEXSIZE{_n}", "mipmap level size")
for _n in range(0xF0, 0xFA):
    GE_NAMES[_n] = (f"UNKNOWN{_n:02X}", "undocumented (written by the GE init; no known effect)")

# What counts as a warning in the subsystem tags (case-insensitive).
WARN_RE = re.compile(r"cannot|can't|not (emulated|implemented|supported)|unsupported|fail|error|warn|unknown|"
                     r"ran out|missing|dropped|too (many|large|big)|overflow|invalid|stall|timeout|lost", re.I)
TAG_RE = re.compile(r"^\[(render|mpeg|atrac|sas|psmfplayer|savedata|audio|metal|io)\]")
GUEST_BAD_RE = re.compile(r"error|fail|assert|warn", re.I)
SHIP_T_RE = re.compile(r"^\[pure\] ship frame (\d+) t=(\d+) clock=(\S+) pos=\S+ vel=\S+ kmh=(\S+) dist=(\S+) "
                       r"lap=(\d+)")
PLAYER_RE = re.compile(r"^\[pure\] ship frame (\d+) player object")
TRACK_RE = re.compile(r"\[io\] open disc0:/PSP_GAME/USRDIR/Data/(Environments|ClassicsNS|Zone)/([^/]+)/TrackStartup")
IGNORED_RE = re.compile(r"^  0x([0-9a-f]+) x(\d+) first=0x([0-9a-f]+)$")
METAL_EXIT_RE = re.compile(r"^\[metal\] (\d+) frames, (\d+) draws, (\d+) passes, (\d+) textures decoded, (\d+) "
                           r"framebuffer textures, (\d+) target copies, (\d+) uploads, (\d+) targets, (\d+) GPU waits "
                           r"\(([\d.]+) ms\) in ([\d.]+) s")
METAL_PIPE_RE = re.compile(r"^\[metal\] pipelines: (\d+) render pipelines used, (\d+) made by a draw \((\d+) of them "
                           r"waited for the pre-warm, (\d+) not in the list\).*?; (\d+) depth-stencil states, (\d+) made")
METAL_FPS_RE = re.compile(r"^\[metal\] frame (\d+), \d+ draws \(\d+ in the last \d+ frames, ([\d.]+) fps\)")
THREADS_RE = re.compile(r"^threads \(virtual time (\d+) ms, vblanks (\d+)\)")
UNIMPL_RE = re.compile(r"^Unimplemented imports: (\d+) of (\d+)")
STOPPED_RE = re.compile(r"Runtime stopped: (.*)")
SWEEP_LINE_RE = re.compile(r"^\[sweep\] (\S+): (PASS|STALL|HALT|NO RACE|TIMEOUT|STUCK)((?: \([^)]*\))?) at flip (\d+), "
                           r"(\d+) laps, race time ([\d.]+) s, (\d+) s: (.*)$")
UNDERRUN_RE = re.compile(r"\[pure\] audio capture: channel (\d+) underrun")
SAVEDATA_RE = re.compile(r"^\[savedata\] (\w+) \((\d+)\) game=\"(\w*)\" save=\"(\w*)\" file=\"([\w.]*)\"")


def cell_label(mode, track, cls):
    return cs.cell_name(mode, track, cls)


def read_cells(path):
    cells = []
    with open(path) as f:
        for raw in f:
            words = raw.split("#", 1)[0].split()
            if not words:
                continue
            if len(words) not in (2, 3):
                sys.exit(f"fidelity_audit: {path}: a cell is MODE TRACK [CLASS], not {raw.strip()!r}")
            cells.append((words[0], words[1], words[2] if len(words) == 3 else "vector"))
    return cells


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
    """The findings of one sweep log (see the module doc). With fps 30 (Time Trial, Free Play, Zone: two vblanks a
    flip throughout) no stretches are looked for."""
    found = {"features": {}, "ignored": {}, "stretches": [], "tracks": [], "saves": [], "exit": {}, "min_fps": None,
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
                m = IGNORED_RE.match(line)
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
            m = METAL_EXIT_RE.match(line)
            if m:
                found["exit"].update(frames=int(m[1]), draws=int(m[2]), textures=int(m[4]), waits=int(m[9]),
                                     wait_ms=float(m[10]), seconds=float(m[11]))
                continue
            m = METAL_PIPE_RE.match(line)
            if m:
                found["exit"].update(pipelines=int(m[1]), pipelines_made=int(m[2]), pipelines_unlisted=int(m[4]),
                                     depth_states=int(m[5]), depth_made=int(m[6]))
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


WAVSTATS_RE = re.compile(r"active fraction ([\d.]+) \((\d+)/(\d+)\), clipping fraction ([\d.]+)")
ZERO_RE = re.compile(r"zero runs >= \S+ ms: (\d+)")


def wav_stats(path, start, end):
    """tools/wavstats.py over [start, end] s of a capture: {active, seconds, clip, zero_runs} or None."""
    if not os.path.exists(path) or start is None:
        return None
    cmd = [sys.executable, os.path.join(ROOT, "tools", "wavstats.py"), path, "--from", f"{start:.2f}"]
    if end is not None:
        cmd += ["--to", f"{end:.2f}"]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    m = WAVSTATS_RE.search(out)
    if not m:
        return None
    z = ZERO_RE.search(out)
    zl = next((ln.strip() for ln in out.splitlines() if ln.startswith("zero runs")), "")
    sl = next((ln.strip() for ln in out.splitlines() if ln.startswith("silent seconds")), "")
    return {"active": float(m[1]), "active_s": int(m[2]), "seconds": int(m[3]), "clip": float(m[4]),
            "zero_runs": int(z[1]) if z else 0, "zero_detail": zl, "silent_detail": sl}


def run_cell(mode, track, cls, opts):
    """One cell through the sweep; returns its JSON record."""
    name = cell_label(mode, track, cls)
    out = os.path.join(ROOT, opts.out)
    sweep_out = os.path.join(opts.out, "sweep")
    os.makedirs(os.path.join(out, "cells"), exist_ok=True)
    os.makedirs(os.path.join(out, "audio"), exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("PURE_TRACE_")}
    for k in ("PURE_AUDIO_WAV", "PURE_TEST_NO_DAMAGE", "PURE_TEST_UNLOCK_ALL", "PURE_METAL_TRACE"):
        env.pop(k, None)
    wav = os.path.join(out, "audio", f"{name}.wav")
    if opts.audio:
        for p in [wav] + [f"{wav}.ch{n}.wav" for n in range(1, 5)]:
            if os.path.exists(p):
                os.remove(p)
        env["PURE_AUDIO_WAV"] = wav
    args = [mode, track, "--no-damage", "--out", sweep_out]
    if cls != "vector":
        args += ["--class", cls]
    extended = is_extended(mode, track)
    cmd = ([sys.executable, os.path.abspath(__file__), "--sweep-cell", "--"] if extended else
           [sys.executable, os.path.join(ROOT, "tools", "campaign_sweep.py")]) + args
    stdout = os.path.join(out, "cells", f"{name}.stdout")
    print(f"[audit] {name}: {' '.join(cmd[1:] if not extended else ['fidelity_audit.py --sweep-cell'] + args)}",
          flush=True)
    t0 = time.time()
    with open(stdout, "w") as f:
        code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT).returncode
    elapsed = time.time() - t0
    rec = {"cell": name, "mode": mode, "track": track, "class": cls, "extended": extended, "exit": code,
           "wall_s": round(elapsed), "date": time.strftime("%Y-%m-%d %H:%M"), "audio": opts.audio}
    outcome = None
    with open(stdout, errors="replace") as f:
        for line in f:
            m = SWEEP_LINE_RE.match(line.strip())
            if m and m[1] == name:
                outcome = m
            if line.startswith("campaign_sweep: another PureNative"):
                rec["refused"] = True
    if outcome:
        rec.update(outcome=outcome[2], switches=outcome[3].strip(" ()"), flip=int(outcome[4]),
                   laps=int(outcome[5]), clock=float(outcome[6]), detail=outcome[8])
    else:
        rec.update(outcome="NO RESULT", switches="", flip=0, laps=0, clock=0.0,
                   detail=f"the sweep printed no outcome (exit {code}); see {stdout}")
    log = os.path.join(ROOT, sweep_out, f"{name}.log")
    if os.path.exists(log):
        rec["log"] = os.path.relpath(log, ROOT)
        rec.update(scan_log(log, cs.MODES[mode].get("fps", 60)))
    if opts.audio:
        start, end = rec.get("race_start_s"), rec.get("end_s")
        rec["wav"] = {}
        for label, p in (("mix", wav), ("sas", f"{wav}.ch1.wav"), ("music", f"{wav}.ch2.wav")):
            st = wav_stats(p, start, end)
            if st:
                rec["wav"][label] = st
        if not opts.keep_wav:
            for p in [wav] + [f"{wav}.ch{n}.wav" for n in range(1, 5)]:
                if os.path.exists(p):
                    os.remove(p)
    with open(os.path.join(out, "cells", f"{name}.json"), "w") as f:
        json.dump(rec, f, indent=1, sort_keys=True)
    print(f"[audit] {name}: {rec['outcome']} {rec.get('switches', '')} at flip {rec['flip']}, {rec['laps']} laps, "
          f"{elapsed:.0f} s; {len(rec.get('features', {}))} feature lines, {len(rec.get('stretches', []))} "
          f"two-vblank stretches, tracks {','.join(rec.get('tracks', [])) or '-'}", flush=True)
    return rec


def load(out, name):
    p = os.path.join(ROOT, out, "cells", f"{name}.json")
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def short(text, n=160):
    text = text.replace("|", "/")
    return text if len(text) <= n else text[:n - 3] + "..."


def save_text(saves):
    """The savedata requests of a cell, beyond the two every boot makes (the first-boot AUTOSAVE of DLS001 and the
    NEW profile's LISTSAVE), counted by kind."""
    rest = list(saves)
    for boot in ("AUTOSAVE PPCD00001DLS001/DATA1.BIN", "LISTSAVE UCUS98612/PROFILE.BIN"):
        if boot in rest:
            rest.remove(boot)
    if not rest:
        return "-"
    counts = {}
    for x in rest:
        counts[x] = counts.get(x, 0) + 1
    return ", ".join(f"{k}" + (f" x{n}" if n > 1 else "") for k, n in counts.items())


def write_tables(cells, opts):
    out = os.path.join(ROOT, opts.out)
    recs = [(c, load(opts.out, cell_label(*c))) for c in cells]
    rows = ["# Fidelity audit: the campaign matrix (tools/fidelity_audit.py)", "",
            f"Written {time.strftime('%Y-%m-%d %H:%M')}; {sum(1 for _c, r in recs if r)} of {len(recs)} cells run. "
            "Each cell: tools/campaign_sweep.py headless on the Metal backend, `--no-damage`, the unlock switch where "
            "a new profile lacks the track or class; `(extended)`: the league pick added by this tool. Stretches: "
            "runs of race flips at two vblanks (count, seconds in all). Audio: active fraction of the mix from the "
            "race start, then the music channel's, and clipping.", "",
            "| cell | outcome | flip | laps | race s | wall s | track loaded | halts, stubs, warnings | GE ignored | "
            "stretches | min fps | pipelines not listed | audio mix / music / clip | saves | detail |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for (mode, track, cls), r in recs:
        name = cell_label(mode, track, cls)
        if not r:
            rows.append(f"| {name} | not run | | | | | | | | | | | | | |")
            continue
        feats = r.get("features", {})
        halts = sum(n for k, n in feats.items() if "[hle-stub]" in k or "Runtime stopped" in k or "unsupported" in k.lower())
        warns = sum(feats.values()) - halts
        st = r.get("stretches", [])
        st_text = f"{len(st)} ({sum(s['seconds'] for s in st):.1f} s)" if st else "0"
        fps = r.get("min_fps")
        wav = r.get("wav") or {}
        audio = (f"{wav['mix']['active']:.2f} / {wav.get('music', {}).get('active', float('nan')):.2f} / "
                 f"{wav['mix']['clip']:.4f}" if "mix" in wav else "-")
        outcome = r["outcome"] + (" (extended)" if r.get("extended") else "")
        tracks = ",".join(dict.fromkeys(r.get("tracks", []))) or "-"
        rows.append(f"| {name} | {outcome} | {r['flip']} | {r['laps']} | {r['clock']:.1f} | {r['wall_s']} | "
                    f"{short(tracks, 80)} | {halts}, {warns} | {len(r.get('ignored', {}))} | {st_text} | "
                    f"{f'{fps[1]:.1f}' if fps else '-'} | {r.get('exit', {}).get('pipelines_unlisted', '-')} | "
                    f"{audio} | {save_text(r.get('saves', []))} | {short(r.get('detail', ''), 220)} |")
    with open(os.path.join(out, "matrix.md"), "w") as f:
        f.write("\n".join(rows) + "\n")

    feats, ignored = {}, {}
    order = []
    for (mode, track, cls), r in recs:
        if not r:
            continue
        name = cell_label(mode, track, cls)
        for k, n in r.get("features", {}).items():
            e = feats.setdefault(k, {"cells": [], "count": 0, "first": name})
            e["cells"].append(name)
            e["count"] += n
        for op, v in r.get("ignored", {}).items():
            e = ignored.setdefault(int(op), {"cells": [], "count": 0, "first": name, "values": set()})
            e["cells"].append(name)
            e["count"] += v["count"]
            e["values"].add(v["first"])
        if r.get("unimplemented") and "unimplemented" not in order:
            order.append("unimplemented")
            feats_unimpl = (r["unimplemented"], r.get("unimplemented_list", []), name)
    lines = ["# Fidelity audit: distinct lines (tools/fidelity_audit.py)", "",
             f"Written {time.strftime('%Y-%m-%d %H:%M')} from {sum(1 for _c, r in recs if r)} cells. One row per "
             "distinct line (frame numbers and times taken out), then the GE commands the framework ignores "
             "(its exit list: count over all cells, the first value each cell saw), then the imports with no "
             "implementation.", "", "## Lines", "",
             "| line | cells | count | first cell |", "|---|---|---|---|"]
    for k, e in sorted(feats.items(), key=lambda kv: (-len(kv[1]["cells"]), kv[0])):
        lines.append(f"| `{short(k, 200)}` | {len(e['cells'])} | {e['count']} | {e['first']} |")
    if not feats:
        lines.append("| (none) | | | |")
    lines += ["", "## GE commands ignored", "",
              "| command | name | what it does | cells | count | first values seen | first cell |", "|---|---|---|---|---|---|---|"]
    for op in sorted(ignored):
        e = ignored[op]
        nm, what = GE_NAMES.get(op, (f"0x{op:02X}", "?"))
        vals = ", ".join(f"0x{v:x}" for v in sorted(e["values"]))
        lines.append(f"| 0x{op:02X} | {nm} | {what} | {len(e['cells'])} | {e['count']} | {short(vals, 80)} | {e['first']} |")
    if "unimplemented" in order:
        n, names, first = feats_unimpl
        lines += ["", "## Imports with no implementation (listed at start-up; a call would print `[hle-stub]`)", "",
                  f"{n}, in every cell (first: {first}): " + ", ".join(names)]
    with open(os.path.join(out, "features.md"), "w") as f:
        f.write("\n".join(lines) + "\n")

    # The audio of each cell (item 4) and every two-vblank stretch (item 6), one row each.
    aud = ["# Fidelity audit: audio from the race start (tools/fidelity_audit.py, tools/wavstats.py)", "",
           "Active: whole seconds with RMS over 100 (wavstats' floor), as a fraction of the window. Clip: samples at "
           "full scale. Zero runs: stretches of 50 ms or more of exact zeros inside the window. Underruns: the "
           "capture's own lines (a buffer the game handed sceAudio late), per channel over the whole run (channel 3 "
           "is the movies').", "",
           "| cell | window s | mix active | mix clip | music (ch 2) active | music zero runs | sceSas (ch 1) active | "
           "sceSas clip | underruns |", "|---|---|---|---|---|---|---|---|---|"]
    st_rows = ["# Fidelity audit: the two-vblank stretches of the races (tools/fidelity_audit.py)", "",
               "Runs of three or more race flips in a row whose virtual time step is two vblanks (the end-of-frame "
               "routine's locked path, docs/timing.md), from the `[pure] ship` lines' `t=`; the race, the lap begun "
               "(the lap clock's restarts plus one), the track distance and the speed where each starts.", "",
               "| cell | race | lap | distance m | km/h | flips | seconds |", "|---|---|---|---|---|---|---|"]
    for (mode, track, cls), r in recs:
        if not r:
            continue
        name = cell_label(mode, track, cls)
        wav = r.get("wav") or {}
        under = ", ".join(f"ch {k.split('channel ')[1].split()[0]}: {n}" for k, n in sorted(r.get("features", {}).items())
                          if "underrun" in k) or "0"
        if "mix" in wav:
            mx, mu, sa = wav["mix"], wav.get("music", {}), wav.get("sas", {})
            aud.append(f"| {name} | {mx['seconds']} | {mx['active']:.2f} | {mx['clip']:.6f} | "
                       f"{mu.get('active', float('nan')):.2f} | {mu.get('zero_runs', '-')} | "
                       f"{sa.get('active', float('nan')):.2f} | {sa.get('clip', float('nan')):.6f} | {under} |")
        for s in r.get("stretches", []):
            st_rows.append(f"| {name} | {s['race']} | {s['lap']} | {s['dist']} | {s.get('kmh', '-')} | {s['flips']} | "
                           f"{s['seconds']:.2f} |")
    with open(os.path.join(out, "audio.md"), "w") as f:
        f.write("\n".join(aud) + "\n")
    with open(os.path.join(out, "stretches.md"), "w") as f:
        f.write("\n".join(st_rows) + "\n")
    return os.path.join(out, "matrix.md"), os.path.join(out, "features.md")


# --ppsspp-race (item 6 and the results screen): the player's race record in PPSSPP's memory (docs/tracks.md), the
# end-of-frame routine's locked path (docs/timing.md step 5: reached when +0x116c is 0 or the countdown at +0x117c
# runs) and FxScreen's store of that countdown (FUN_0882da04, docs/fidelity.md).
PP_RECORD = 0x08B72010 + 7 * 0x1C0          # the player's entry on a Single Race grid (k = 7)
PP_LOCKED_PC = 0x08865254                   # FUN_0886511c: `addiu a0,s2,-1`, the first instruction of the locked path
PP_FXLOCK_PC = 0x0882E198                   # FUN_0882da04: `sw a1,0x117c(a0)` with a1 = 2
PP_LOG_RE = re.compile(r"BKP PC=\w+: (FLIP|FXLOCK|LOCKED) (\d+)(?: clock (\S+))?")
PP_HOLD_FROM = 7213                         # the first READY frame on vineta_k_start.txt's timing: Cross held from it


def ppsspp_race(opts):
    """--ppsspp-race TRACK: a Single Race of an Alpha circuit at Vector in PPSSPP (tools/ppsspp/ppsspp_ctl.py as a
    library, the software renderer so the results screen can be captured), its menus from the frame-exact routes
    (frontend.txt, vineta_k_start.txt, track_downN.txt) and the race steered closed loop by the sweep's own follower
    (campaign_sweep's Leg, Tuner and Race with the track's steering table): the player's race record read from memory
    about 30 times a second, the stick and the buttons sent live (`input.analog.send`, `input.buttons.send`). PPSSPP
    logs, through log-only breakpoints, every flip (sceDisplaySetFrameBuf) with its emulated time and the race clock,
    every pass through the end-of-frame routine's locked path, and every store of FxScreen's lock countdown. After
    the third lap the tool captures the screen every 30 vblanks for 15 s (the results panel), quits PPSSPP and writes
    <out>/ppsspp/<track>/: race.csv (the samples), shots/, ppsspp.log, and summary.json with the laps, the contacts
    and the two-vblank stretches (runs of flips 25 ms or more apart in the race, with the race clock and how many
    FxScreen stores and locked passes fell inside each)."""
    import base64
    sys.path.insert(0, os.path.join(ROOT, "tools", "ppsspp"))
    import ppsspp_ctl as pc
    track = opts.ppsspp_race
    if track not in cs.ALPHA:
        print(f"fidelity_audit: --ppsspp-race takes an Alpha circuit ({', '.join(cs.ALPHA)}), the routes PPSSPP has")
        return 2
    downs = cs.ALPHA.index(track)
    out = os.path.join(ROOT, opts.out, "ppsspp", track)
    os.makedirs(os.path.join(out, "shots"), exist_ok=True)
    routes = os.path.join(ROOT, "tools", "ppsspp", "routes")
    names = ["frontend.txt", "vineta_k_start.txt"] + ([f"track_down{downs}.txt"] if downs else [])
    script = "\n".join(open(os.path.join(routes, n)).read() for n in names)
    states = pc.parse_pad_script(script)
    leg = cs.Leg(track, argparse.Namespace(drive=None, line=None, tune=False, set=[], wn=1.0, preview=0.3), True)
    tuner, race = leg.tuner, cs.Race(3)
    log_path = os.path.join(out, "ppsspp.log")
    samples = open(os.path.join(out, "race.csv"), "w")
    samples.write("usec,vblank,clock,x,y,z,vx,vy,vz,kmh,dist,lap,lx\n")
    summary = {"track": track, "routes": names, "follower": leg.how}
    shots = []
    t0 = time.time()
    with pc.IniSession(False, port=pc.DEFAULT_PORT, renderer="software", hle_log=False, mute=True,
                       savestate_key=False):
        proc = pc.launch(pc.DEFAULT_ISO, log_path)
        dbg = None
        try:
            dbg, _ = pc.connect(pc.DEFAULT_PORT, proc.pid, proc)
            pc.wait_boot(dbg)
            dbg.request("replay.time.set", value=1767225600)
            dbg.request("replay.execute", version=1, base64=base64.b64encode(pc.build_replay_blob(states)).decode())
            setfb = dbg.symbol(pc.SETFB_STUB)
            clock_at = PP_RECORD + 0x1C
            dbg.request("cpu.breakpoint.add", address=setfb, enabled=False, log=True,
                        logFormat=f"FLIP {{usec:d}} clock {{[0x{clock_at:08x}]:f}}")
            dbg.request("cpu.breakpoint.add", address=PP_FXLOCK_PC, enabled=False, log=True,
                        logFormat="FXLOCK {usec:d}")
            dbg.request("cpu.breakpoint.add", address=PP_LOCKED_PC, enabled=False, log=True,
                        logFormat="LOCKED {usec:d}")
            dbg.resume()
            lx_sent, cross, square_at, finished_at = 0.0, False, -1e9, None
            while True:
                if time.time() - t0 > opts.wall_limit:
                    raise RuntimeError(f"wall-clock limit {opts.wall_limit:.0f} s reached")
                u = dbg.usec()
                frame = pc.frame_at_us(u)
                if frame < PP_HOLD_FROM - 30:
                    time.sleep(0.5)
                    continue
                if not cross and frame >= PP_HOLD_FROM:
                    dbg.request("input.buttons.send", buttons={"cross": True})
                    cross = True
                data = base64.b64decode(dbg.request("memory.read", address=PP_RECORD - 0x20, size=0x40)["base64"])
                vx, vy, vz = struct.unpack_from("<3f", data, 0)
                x, y, z = struct.unpack_from("<3f", data, 0x20)
                lap = struct.unpack_from("<I", data, 0x30)[0]
                dist, clock = struct.unpack_from("<2f", data, 0x38)
                kmh = 3.6 * math.sqrt(vx * vx + vy * vy + vz * vz)
                line = (f"[pure] ship frame {int(frame)} t={u} clock={clock:.3f} pos={x:.3f},{y:.3f},{z:.3f} "
                        f"vel={vx:.3f},{vy:.3f},{vz:.3f} kmh={kmh:.3f} dist={dist:.3f} lap={lap}")
                race.feed(cs.SHIP_RE.search(line), line)
                lx = 0.0
                if race.started and race.finished_frame is None:
                    lx = round(tuner.stick(tuner.demand(race)), 2)
                    if abs(lx - lx_sent) >= cs.LX_STEP or (lx == 0.0 and lx_sent != 0.0):
                        dbg.request("input.analog.send", stick="left", x=lx, y=0.0)
                        lx_sent = lx
                        tuner.note(race.total, lx)
                    if tuner.absorb > 0.0 and race.total - square_at >= tuner.absorb:
                        dbg.request("input.buttons.send", buttons={"cross": True, "square": True})
                        time.sleep(0.07)
                        dbg.request("input.buttons.send", buttons={"cross": True, "square": False})
                        square_at = race.total
                samples.write(f"{u},{frame:.2f},{clock:.3f},{x:.2f},{y:.2f},{z:.2f},{vx:.2f},{vy:.2f},{vz:.2f},"
                              f"{kmh:.1f},{dist:.2f},{lap},{lx:.2f}\n")
                if race.started and race.finished_frame is None and race.stalled_for() >= 30.0:
                    summary["outcome"] = f"STALL at {race.dist:.0f} m after {race.total:.1f} s"
                    break
                if race.finished_frame is not None and finished_at is None:
                    finished_at = frame
                    dbg.request("input.analog.send", stick="left", x=0.0, y=0.0)
                    pc.log(f"finished at vblank {frame:.0f}: laps {race.lap_times}")
                    # The results panel comes up about 4 s after the line, over a moving replay.
                    for k in range(1, 31):
                        f = int(finished_at) + 30 * k
                        rep = pc.capture(dbg, setfb, pc.vblank_us(f), shot=os.path.join(out, "shots", f"r{f}.png"),
                                         keep_stepping=True)
                        shots.append({"requested": f, "frame": rep.get("frame")})
                    summary["outcome"] = "PASS"
                    break
                time.sleep(0.03)
        except Exception as e:  # report, then still shut PPSSPP down
            summary["error"] = f"{type(e).__name__}: {e}"
            pc.log(f"error: {summary['error']}")
        finally:
            samples.close()
            if dbg:
                dbg.close()
            pc.stop_process(proc.pid, proc)
    summary.update(laps=race.lap_times, contacts=len(race.contacts), wall_s=round(time.time() - t0), shots=shots)
    summary["stretches"], summary["race_flips"] = ppsspp_stretches(log_path)
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1)
    print(json.dumps({k: v for k, v in summary.items() if k != "shots"}, indent=1))
    return 0 if summary.get("outcome") == "PASS" else 1


def ppsspp_stretches(log_path):
    """The race's two-vblank stretches in a --ppsspp-race log: runs of STRETCH_MIN or more flips at 25 ms or more
    with the race clock running, each with the FxScreen stores and the locked passes inside it."""
    flips, fx, locked = [], [], []
    if not os.path.exists(log_path):
        return [], 0
    with open(log_path, errors="replace") as f:
        for line in f:
            m = PP_LOG_RE.search(line)
            if not m:
                continue
            u = int(m[2])
            if m[1] == "FLIP":
                flips.append((u, float(m[3]) if m[3] else 0.0))
            elif m[1] == "FXLOCK":
                fx.append(u)
            else:
                locked.append(u)
    race = [(u, c) for u, c in flips if c > 0.0]
    out, run = [], []

    def close():
        if len(run) >= STRETCH_MIN:
            a, b = run[0][0] - 2 * 16683, run[-1][0]
            out.append({"vblank": round((run[0][0] - 15951.8) / 16683.3 + 1), "flips": len(run),
                        "seconds": round((b - a) / 1e6, 2), "clock": round(run[0][1], 1),
                        "fxscreen_stores": sum(1 for v in fx if a <= v <= b),
                        "locked_passes": sum(1 for v in locked if a <= v <= b)})
    for (u0, _c0), (u1, c1) in zip(race, race[1:]):
        if u1 - u0 > TWO_VBLANK_US:
            run.append((u1, c1))
        else:
            close()
            run = []
    close()
    return out, len(race)


def sweep_cell(argv):
    """--sweep-cell -- ARGS: the sweep's main() with MODES extended (extend_modes)."""
    extend_modes()
    return cs.main(argv)


def parse(argv):
    p = argparse.ArgumentParser(prog="fidelity_audit.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("--quick", action="store_true")
    p.add_argument("--cells")
    p.add_argument("--resume", action="store_true")
    p.add_argument("--only")
    p.add_argument("--audio", dest="audio", action="store_true", default=True)
    p.add_argument("--no-audio", dest="audio", action="store_false")
    p.add_argument("--keep-wav", action="store_true")
    p.add_argument("--out", default=OUT)
    p.add_argument("--report", action="store_true")
    p.add_argument("--rescan", action="store_true")
    p.add_argument("--list", action="store_true")
    p.add_argument("--ppsspp-race", metavar="TRACK")
    p.add_argument("--wall-limit", type=float, default=900.0)
    opts = p.parse_args(argv)
    if opts.quick and opts.cells:
        p.error("--quick and --cells name two lists")
    return opts


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "--sweep-cell":
        return sweep_cell(argv[2:] if len(argv) > 1 and argv[1] == "--" else argv[1:])
    opts = parse(argv)
    if opts.ppsspp_race:
        return ppsspp_race(opts)
    extend_modes()
    cells = QUICK if opts.quick else read_cells(opts.cells) if opts.cells else FULL
    for mode, track, cls in cells:
        if mode not in cs.MODES or track not in cs.MODES[mode]["tracks"] or cls not in cs.CLASSES:
            print(f"fidelity_audit: unknown cell {mode} {track} {cls}")
            return 2
    if opts.list:
        for c in cells:
            r = load(opts.out, cell_label(*c))
            print(f"{cell_label(*c)}{' (extended)' if is_extended(c[0], c[1]) else ''}: "
                  f"{r['outcome'] if r else 'not run'}")
        return 0
    if opts.rescan:
        # The logs read again with this version of the collectors (the outcome and the audio kept).
        for c in cells:
            name = cell_label(*c)
            rec = load(opts.out, name)
            if not rec or not rec.get("log") or not os.path.exists(os.path.join(ROOT, rec["log"])):
                continue
            for k in ("features", "ignored", "stretches", "tracks", "saves", "underruns", "exit", "min_fps", "unimplemented",
                      "unimplemented_list", "stopped", "race_start_s", "end_s", "races"):
                rec.pop(k, None)
            rec.update(scan_log(os.path.join(ROOT, rec["log"]), cs.MODES[c[0]].get("fps", 60)))
            with open(os.path.join(ROOT, opts.out, "cells", f"{name}.json"), "w") as f:
                json.dump(rec, f, indent=1, sort_keys=True)
        opts.report = True
    if opts.report:
        for p in write_tables(cells, opts):
            print(p)
        return 0
    todo = cells
    if opts.only:
        names = set(opts.only.split(","))
        todo = [c for c in cells if cell_label(*c) in names]
    out = os.path.join(ROOT, opts.out)
    os.makedirs(out, exist_ok=True)
    ran = 0
    for c in todo:
        name = cell_label(*c)
        if opts.resume and load(opts.out, name):
            continue
        while os.path.exists(os.path.join(out, "hold")):
            time.sleep(10)
        if os.path.exists(os.path.join(out, "stop")):
            print("[audit] stop file: stopping before " + name, flush=True)
            break
        rec = run_cell(*c, opts)
        if rec.get("refused"):
            print("[audit] the sweep refused to start (another PureNative runs); stopping", flush=True)
            os.remove(os.path.join(out, "cells", f"{name}.json"))
            write_tables(cells, opts)
            return 1
        ran += 1
        write_tables(cells, opts)
    m, f = write_tables(cells, opts)
    print(f"[audit] {ran} cells run; tables: {os.path.relpath(m, ROOT)}, {os.path.relpath(f, ROOT)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
