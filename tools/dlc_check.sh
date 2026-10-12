#!/bin/bash
# The download packs check (task 077, docs/dlc.md): the twelve US packs installed with tools/dlc_install.sh on a fresh
# memory stick of the check's own, then the game run with them, headless on the Metal backend (on Windows in the
# Vulkan window, purelib.port.DRAWING, since nothing draws headless there).
#   tools/dlc_check.sh --packs PACKS [--out DIR] [--wait SECONDS]
#   --packs  the packs, as tools/dlc_install.sh takes them (a folder holding the twelve UCUS98612D<PACK> folders, or
#            its SAVEDATA or PSP/SAVEDATA). Read only: the check copies from it and never writes there.
#   --out    default out/dlc_check: the game directory and its stick (game/), a scratch data directory (data/), each
#            run's log, route and output, the shots, and summary.txt (what is printed); an earlier check's are removed
#            first, nothing else there.
#   --wait   how long to wait for another game to end before a run (default 600; 0 gives up at once): one game at a
#            time.
# Every run starts on a fresh stick (purelib.port.fresh_stick) with the packs installed by tools/dlc_install.sh, so
# main_menu.txt makes and saves a new profile each time; the data directory is a fresh scratch one (port.SCRATCH_SETTINGS).
#   1. The selection run: config/pad_scripts/main_menu.txt + single_race.txt with shots at 5185 (league_select) and
#      5600 (team_select), PURE_TRACE_IO=1. PASS when the log has a successful open of PI.WAD in each of the twelve
#      folders (`[io] open ms0:/PSP/SAVEDATA/<folder>/PI.WAD ... -> <fd>`), league_select differs from
#      ref/league_select.png in at least 1% of its pixels at tol 24 (CLASSIC 2, DELTA and GAMMA under ALPHA) and
#      team_select from ref/team_select.png in at least 0.3% (ICARAS under HARIMAU).
#   2. The races: main_menu.txt + gamma_race.txt, delta_race.txt and classic2_race.txt (the pack leagues' first tracks,
#      Cross held from 6100), each to flip 7630 with shots every 100 flips from 7100 to 7600. PASS when
#      tools/hud_check.py finds the race HUD in at least 4 of the 6 shots and the log has `[guest] Track Allocated`;
#      and the league's TRACK SELECTION, shot at 5390 as the suite shoots Alpha's, differs from ref/track_select.png
#      in at least 5% of its pixels at tol 24, so the race is the pack league's (not Vineta K's, which a route whose
#      DOWN presses met no pack league would race).
#   3. No `[hle-stub]` line in any run with the packs for a call a pack's loading could make: the file calls (sceIo*,
#      IoFileMgr*), the save-data utility (sceUtilitySavedata*), the console identity the binding check reads
#      (sceOpenPSID*, sceWlan*), the save cipher and the kernel's hashes (sceChnnlsv*, sceKernelUtils*). Every
#      `[hle-stub]` line is listed whatever its call, and every run must reach its last flip (no halt).
#   4. The cost: a boot to MAIN MENU (main_menu.txt, 4700 flips, headless and without a picture, purelib.port.BLIND)
#      without and with the packs, twice each, alternating; run_boot's wall time printed (no bar on it; each run must
#      reach its last flip).
# Prints a table, then `dlc_check: PASS` or `FAIL` last. Exit 0 only on PASS, 1 on FAIL, 2 when the packs folder is
# missing, the build, the game or a reference is missing, or a run could not start (another game ran longer than
# --wait).
set -u
PACKS=
OUT=out/dlc_check
WAIT=600
usage() {
  echo "usage: tools/dlc_check.sh --packs PACKS [--out DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --packs) [ $# -ge 2 ] || usage; PACKS=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "dlc_check: unknown argument $1"; usage ;;
  esac
done
[ -n "$PACKS" ] || usage
case $WAIT in ''|*[!0-9]*) echo "dlc_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
[ -d "$PACKS" ] || { echo "dlc_check: the packs folder $PACKS is missing"; exit 2; }
PACKS=$(cd "$PACKS" && pwd)          # the caller's path, before the checkout becomes the working directory
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
# A path as Python and the game take it: Git Bash's /c/... as C:/... on Windows.
native() { case "$(uname -s)" in MINGW*|MSYS*) cygpath -m "$1" ;; *) echo "$1" ;; esac; }

python3 - "$(native "$PACKS")" "$OUT" "$WAIT" <<'EOF'
import os, re, shutil, subprocess, sys, time
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)
from purelib import dlc, port  # noqa: E402  (tools/purelib)

packs, out, wait = sys.argv[1], os.path.abspath(sys.argv[2]), int(sys.argv[3])
GAME, DATA = os.path.join(out, "game"), os.path.join(out, "data")
ROUTES = "config/pad_scripts"
SELECT = [(5185, "league_select", "ref/league_select.png", 0.01), (5600, "team_select", "ref/team_select.png", 0.003)]
TOL = 24
RACES = [("gamma", "Gamma"), ("delta", "Delta"), ("classic2", "Classic 2")]
RACE_SHOTS = list(range(7100, 7601, 100))
# The pack league's TRACK SELECTION, at the frame the suite captures Alpha's (track_select): proof that the race is the
# pack league's and not Alpha's (a route whose DOWN presses found no pack league would race Vineta K with the HUD).
TRACK_SHOT, TRACK_REF, TRACK_LEAST = 5390, "ref/track_select.png", 0.05
RACE_FRAMES, MIN_HUD = 7630, 4
SELECT_FRAMES = 5630
COST_FRAMES = 4700
PACE_MARGIN = 300               # a window run is held to real time from this many flips before its first shot
PACK_CALLS = re.compile(r"::(sceIo|sceUtilitySavedata|sceOpenPSID|sceWlan|sceChnnlsv|sceKernelUtils)|^IoFileMgr")
OPEN_RE = re.compile(r"^\[io\] open ms0:/?PSP/SAVEDATA/(UCUS98612D\w+)/PI\.WAD .*-> 0x([0-9A-Fa-f]+)", re.I)
STUB_RE = re.compile(r"^\[hle-stub\] (\S+)")
EXIT_RE = re.compile(r"^\[run_boot\] exit (-?\d+) after ([\d.]+)s")
lines = []


def say(text=""):
    print(text, flush=True)
    lines.append(text)


def give_up(text):
    say(f"dlc_check: {text}")
    say("dlc_check: FAIL (could not run)")
    write_summary()
    sys.exit(2)


def write_summary():
    with open(os.path.join(out, "summary.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


# --- preconditions ---------------------------------------------------------------------------------------------
if not port.EXE.exists():
    print(f"dlc_check: {port.EXE} missing: tools/build.sh profile")
    sys.exit(2)
for name in ("EBOOT.ELF", "disc.iso"):
    if not os.path.exists(port.GAME / name):
        print(f"dlc_check: game/{name} missing or dangling (tools/setup_game.sh); do not look for the image elsewhere")
        sys.exit(2)
for ref in [r for _, _, r, _ in SELECT] + [TRACK_REF]:
    if not os.path.isfile(ref):
        print(f"dlc_check: {ref} missing (the PPSSPP references are git-ignored: the main checkout's ref/)")
        sys.exit(2)
found = dlc.find(packs)
if not found:
    print(f"dlc_check: no pack folder in {packs}")
    sys.exit(2)
# What an earlier check left in --out, and only that (--out may name a folder holding other things).
os.makedirs(out, exist_ok=True)
for name in ["game", "data", "select"] + [race for race, _ in RACES]:
    shutil.rmtree(os.path.join(out, name), ignore_errors=True)
for name in os.listdir(out):
    if name == "summary.txt" or name.endswith((".log", ".stdout", ".route.txt", ".hud.txt")):
        os.remove(os.path.join(out, name))
port.scratch_data_dir({}, DATA)
shell, backend = port.DRAWING
commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
say(f"dlc_check {time.strftime('%Y-%m-%d %H:%M')}, commit {commit or 'unknown'}, packs {packs}, shell {shell}, "
    f"backend {backend}, out {out}")


def stick(with_packs, log):
    """A fresh stick in GAME, the packs installed on it by tools/dlc_install.sh when with_packs; its summary line."""
    port.fresh_stick(GAME)
    if not with_packs:
        return "no packs"
    code = port.run_tool(["tools/dlc_install.sh", "--data-dir", GAME, packs], log)
    with open(log) as f:
        text = f.read()
    summary = (re.findall(r"^dlc_install: \d+ installed.*$", text, re.M) or ["dlc_install: no summary line"])[-1]
    return f"{summary} (exit {code})"


def run(name, script_parts, frames, shots=(), with_packs=True, env=None, drawing=True):
    """One run on a fresh stick: the route (script_parts joined, their own shots dropped, `FRAME:shot NAME` first),
    to `frames`; returns (Run, its log, the stick line). Waits its turn (one game at a time) for up to --wait s."""
    script = os.path.join(out, f"{name}.route.txt")
    with open(script, "w") as f:
        for frame, shot in shots:
            f.write(f"{frame}:shot {shot}\n")
        for part in script_parts:
            with open(os.path.join(ROUTES, part)) as src:
                for line in src:
                    if line.strip() and not line.lstrip().startswith("#") and \
                            not re.match(r"^\s*\d+:\s*shot(\s|$)", line):
                        f.write(line if line.endswith("\n") else line + "\n")
    if not port.wait_until(port.other_games, port.REFUSED, lambda m: print(f"dlc_check: {m}", flush=True),
                           limit=wait):
        give_up(f"another game kept running for {wait} s; try again later")
    installed = stick(with_packs, os.path.join(out, f"{name}.install.log"))
    sh, be = port.DRAWING if drawing else port.BLIND
    paced = None
    if sh != "headless" and shots:
        paced = max(0, min(f for f, _ in shots) - PACE_MARGIN)
    log = os.path.join(out, f"{name}.log")
    r = port.headless_run(log, script, frames, shell=sh, backend=be, paced_from=paced, env=env,
                          shots=os.path.join(out, name) if shots else None, game=GAME, data_dir=DATA,
                          max_lines=200000, stdout=os.path.join(out, f"{name}.stdout"))
    return r, log, installed


def read(log):
    with open(log, errors="replace") as f:
        return f.read().splitlines()


def wall(log):
    """run_boot's wall time of the run, from its exit line."""
    for line in reversed(read(log)):
        m = EXIT_RE.match(line)
        if m:
            return float(m[2])
    return None


def compare(a, b):
    opts = type("Opts", (), dict(a=a, b=b, tol=TOL, max_frac=1.0, mask=None, region=None, out=None))
    return imgdiff.compare(opts)["fraction"]


rows, failures, stubs, pack_logs = [], [], [], []


def row(check, measured, needs, ok):
    rows.append((check, measured, needs, "-" if ok is None else "PASS" if ok else "FAIL"))
    if ok is False:
        failures.append(check)


# --- 1. the selection run ---------------------------------------------------------------------------------------
say("the selection run: main_menu.txt + single_race.txt, PURE_TRACE_IO=1 ...")
r, log, installed = run("select", ["main_menu.txt", "single_race.txt"], SELECT_FRAMES,
                        [(f, s) for f, s, _, _ in SELECT], env={"PURE_TRACE_IO": "1"})
say(f"  {installed}")
say(f"  run_boot exit {r.code}, flip {r.frame} of {SELECT_FRAMES}, log {log}")
pack_logs.append(log)
row("select run reaches its last flip", f"flip {r.frame}", f"{SELECT_FRAMES}", r.reached)
opened, opens = set(), 0
for line in read(log):
    m = OPEN_RE.match(line)
    if m:
        opens += 1
        if int(m[2], 16) < 0x80000000:
            opened.add(m[1].upper())
missing = [n for n in dlc.PACKS if n not in opened]
row("PI.WAD opened (twelve folders)", f"{len(opened & set(dlc.PACKS))} of 12 folders, {opens} opens"
    + (f"; not: {', '.join(missing[:3])}{', ...' if len(missing) > 3 else ''}" if missing else ""), "12", not missing)
for frame, shot, ref, least in SELECT:
    cap = os.path.join(out, "select", shot + ".png")
    if not os.path.isfile(cap):
        row(f"{shot} against {ref}", "no capture", f">= {least:.3f}", False)
        continue
    fraction = compare(cap, ref)
    row(f"{shot} against {ref}", f"{fraction:.4f} of pixels at tol {TOL}", f">= {least:.3f}", fraction >= least)

# --- 2. the races -----------------------------------------------------------------------------------------------
for race, league in RACES:
    say(f"the race: main_menu.txt + {race}_race.txt ({league}) ...")
    r, log, installed = run(race, ["main_menu.txt", f"{race}_race.txt"], RACE_FRAMES,
                            [(TRACK_SHOT, "track_select")] + [(f, f"h{f}") for f in RACE_SHOTS])
    say(f"  {installed}")
    say(f"  run_boot exit {r.code}, flip {r.frame} of {RACE_FRAMES}, log {log}")
    pack_logs.append(log)
    text = read(log)
    allocated = next((ln.strip() for ln in text if ln.startswith("[guest] Track Allocated")), None)
    hud = subprocess.run([sys.executable, "tools/hud_check.py", os.path.join(out, race)], capture_output=True,
                         text=True).stdout
    with open(os.path.join(out, f"{race}.hud.txt"), "w") as f:
        f.write(hud)
    m = re.search(r"hud_check: (\d+) of (\d+) shots", hud)
    with_hud, shots = (int(m[1]), int(m[2])) if m else (0, 0)
    row(f"race {league}: HUD, Track Allocated",
        f"HUD in {with_hud} of {shots}, {allocated or 'no Track Allocated line'}, flip {r.frame}",
        f">= {MIN_HUD} of {len(RACE_SHOTS)}, the line, {RACE_FRAMES}",
        with_hud >= MIN_HUD and shots == len(RACE_SHOTS) and allocated is not None and r.reached)
    cap = os.path.join(out, race, "track_select.png")
    fraction = compare(cap, TRACK_REF) if os.path.isfile(cap) else None
    row(f"race {league}: track_select against {TRACK_REF}",
        "no capture" if fraction is None else f"{fraction:.4f} of pixels at tol {TOL}", f">= {TRACK_LEAST:.3f}",
        fraction is not None and fraction >= TRACK_LEAST)

# --- 3. the cost ------------------------------------------------------------------------------------------------
times = {False: [], True: []}
for i, with_packs in enumerate((False, True, False, True)):
    name = f"boot{i + 1}_{'packs' if with_packs else 'none'}"
    say(f"the cost: main_menu.txt to flip {COST_FRAMES}, {'with' if with_packs else 'without'} the packs ...")
    r, log, installed = run(name, ["main_menu.txt"], COST_FRAMES, with_packs=with_packs, drawing=False)
    if with_packs:
        pack_logs.append(log)
    t = wall(log)
    say(f"  {installed}; run_boot exit {r.code}, flip {r.frame}, {t if t is not None else '?'} s")
    times[with_packs].append(t if r.reached else None)
fmt = lambda ts: ", ".join("?" if t is None else f"{t:.1f} s" for t in ts)
# No bar on the times; a run that did not reach MAIN MENU's flip (a halt) fails the row.
row(f"boot to MAIN MENU ({COST_FRAMES} flips)", f"with the packs {fmt(times[True])}; without {fmt(times[False])}",
    f"(printed); each run to {COST_FRAMES}", all(t is not None for ts in times.values() for t in ts))

# --- the stubs --------------------------------------------------------------------------------------------------
for log in pack_logs:
    for line in read(log):
        m = STUB_RE.match(line)
        if m:
            stubs.append((os.path.basename(log), line.strip(), bool(PACK_CALLS.search(m[1]))))
pack_stubs = [s for s in stubs if s[2]]
row("[hle-stub] for a pack-related call", f"{len(pack_stubs)} ({len(stubs)} [hle-stub] lines in all)", "0",
    not pack_stubs)

say("")
w0 = max(len(r[0]) for r in rows)
w1 = max(len(r[1]) for r in rows)
w2 = max(len(r[2]) for r in rows)
say(f"{'check':<{w0}}  {'measured':<{w1}}  {'needs':<{w2}}  result")
for check, measured, needs, result in rows:
    say(f"{check:<{w0}}  {measured:<{w1}}  {needs:<{w2}}  {result}")
for log, line, related in stubs:
    say(f"  {log}: {line}{'  (pack-related)' if related else ''}")
say("")
say(f"dlc_check: {'PASS' if not failures else 'FAIL'}")
write_summary()
sys.exit(0 if not failures else 1)
EOF
