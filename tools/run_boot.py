#!/usr/bin/env python3
"""Bounded run of PureNative with a de-duplicated, length-capped log.

  tools/run_boot.py [--seconds N] [--frames N] [--window] [--shell vulkan|metal|headless] [--backend NAME]
                    [--strict] [--script FILE] [--shots DIR] [--every N] [--stubs] [--max-lines N] [--sound]
                    [--data-dir DIR] [--env KEY=VAL ...] out/run.log

Defaults: headless (PURE_NO_RENDER=1), silent (PURE_NO_AUDIO=1), a scratch data directory (PURE_DATA_DIR=
out/data/run_boot), 60 s wall-clock deadline, stubs listed at start-up (PURE_LIST_STUBS=1). The shell and the GE
backend are PureNative's own default (on macOS the Metal ones unless the environment names others, D-008;
PURE_NO_RENDER makes the shell headless). --window keeps the renderer on.
--shell NAME sets PURE_SHELL. vulkan and metal are window shells and imply --window. headless (no window, no GPU
unless a backend that draws is named) implies no window: the run is headless as by default, even with --script or
--shots, with the null GE backend (PURE_GE_BACKEND=null unless --backend or the environment names one). Such a run
is unpaced, so --shell headless --script FILE --shots DIR runs a route in seconds, its shots the backend's own
480x272 captures. --backend NAME sets PURE_GE_BACKEND (vulkan, metal, null, record). --strict sets PURE_STRICT_HLE=1.
Sound (task 034): every run is silent, PURE_NO_AUDIO=1 (no audio device; the game's sceAudio calls still run on the
virtual clock, so PURE_AUDIO_WAV captures as before), unless --sound, or the environment (or --env) sets
PURE_NO_AUDIO, or sets PURE_AUDIO_WAV for a run with a window (task 013's audio checks).
The data directory (task 034): PURE_DATA_DIR (settings.ini, pipeline caches, logs, save backups) is --data-dir DIR
(default out/data/run_boot), made on first use and kept between runs, unless the environment (or --env) names one,
so a test run never reads or writes the player's ~/Library/Application Support/pure-recomp/PureNative/ and settings
changed while playing never reach a test. A new one starts with a settings.ini holding ui.menu_hint_seen=1 (the
menu hint would sit over a window's first 12 s). The game itself comes from PURE_GAME_DIR (default game/).
The internal scale (task 066): a run on the Metal backend draws at internal scale 1 unless PURE_INTERNAL_SCALE is
set, so the checks measure its native picture whatever the data directory's settings say; a run on the Vulkan
backend keeps the settings' scale (2), on which its columns were measured.

The clock (task 050): a run without a window and without --sound gets PURE_NO_BUSY_CLOCK=1 (the framework's
busy-time charge off, so the run does not depend on the machine's load), unless the environment (or --env) names
it; a window or --sound keeps the framework's charge, as a player has it.
--frames N sets PURE_EXIT_AT_FRAME=N (the profile stops the runtime at that flip), raises the deadline to
max(seconds, N/15) and exits 0 when the run ended there (`[pure] exit at frame` in the output).
--script FILE joins the file's non-empty lines that do not start with `#` with `;` into PURE_INPUT_SCRIPT and
implies --window unless --shell headless (in a window the script drives the shell's virtual pad; the headless shell
reads it at pad level). --shots DIR sets PURE_SCREENSHOT_DIR (and implies --window unless --shell headless); after
the run every BMP that is new or rewritten there is converted to a PNG of the same name with tools/png.py, and the
BMP is kept. --every N sets PURE_SCREENSHOT_EVERY (default 0 with --shots, so only the script's `shot` steps
write). --stubs writes <log>.stubs.txt: the start-up "Unimplemented imports" list and each `[hle-stub]` call with its
ra (the framework prints a stub's first call only).
--env KEY=VAL is applied last and overrides all of the above.

The game runs under a pty, so its stdout is line-buffered and nothing is lost when the deadline kills it. The parent
keeps the pty's slave end open until the output is drained: macOS discards unread pty output once the last slave
descriptor closes. Repeated identical lines are folded into "... (xN)" and the log stops at --max-lines (default
20000) while the process keeps running until the deadline. The log always ends with the `[run_boot] exit` line, and
its last 25 lines are echoed to stdout. Exit code is the game's, 0 after a --frames exit, or 124 on the deadline.
"""
import argparse, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import png  # noqa: E402  (tools/png.py)
from purelib import port  # noqa: E402  (tools/purelib: the environment, the guard, the pty runner)
from purelib.logs import RA_RE, STUB_RE, UNIMPL_RE as LIST_RE  # noqa: E402
# Kept under their names here for the scripts that import them from run_boot (frame_regress.sh and
# sas_reverb_check.sh call run_boot.other_games()).
from purelib.port import FRAME_EXIT_GRACE, other_games, scratch_data_dir, silence  # noqa: E402,F401


def parse(argv):
    p = argparse.ArgumentParser(prog="run_boot.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("log")
    p.add_argument("--seconds", type=float, default=60.0)
    p.add_argument("--frames", type=int)
    p.add_argument("--window", action="store_true")
    p.add_argument("--shell", choices=("vulkan", "metal", "headless"))
    p.add_argument("--backend", metavar="NAME")
    p.add_argument("--strict", action="store_true")
    p.add_argument("--script")
    p.add_argument("--shots")
    p.add_argument("--every", type=int)
    p.add_argument("--stubs", action="store_true")
    p.add_argument("--max-lines", type=int, default=20000)
    p.add_argument("--sound", action="store_true")
    p.add_argument("--data-dir", default=os.path.join("out", "data", "run_boot"), metavar="DIR")
    p.add_argument("--env", action="append", default=[], metavar="KEY=VAL")
    opts = p.parse_args(argv)
    for kv in opts.env:
        if "=" not in kv:
            p.error(f"--env takes KEY=VAL, not {kv!r}")
    return opts


def read_script(path):
    with open(path) as f:
        steps = [line.strip() for line in f]
    return ";".join(s for s in steps if s and not s.startswith("#"))


class Stubs:
    """Collects the start-up "Unimplemented imports" list and the [hle-stub] calls from the raw output."""

    def __init__(self):
        self.header, self.listed, self.library, self.in_list = None, [], None, False
        self.called = {}                     # label -> [count, first ra]

    def feed(self, line):
        if self.in_list:
            if line.startswith("    ") and self.library:
                self.listed.append(f"{self.library}::{line.strip()}")
                return
            if line.startswith("  ") and not line.startswith("    "):
                self.library = line.strip().split(" (")[0]
                return
            self.in_list = False
        m = LIST_RE.search(line)
        if m:
            self.header, self.in_list, self.library = (int(m[1]), int(m[2])), True, None
            return
        m = STUB_RE.search(line)
        if m:
            ra = RA_RE.search(line)
            entry = self.called.setdefault(m[1], [0, ra[1] if ra else "?"])
            entry[0] += 1

    def write(self, path, log):
        n = len(self.listed)
        with open(path, "w") as f:
            f.write(f"# stub summary of {log}\n")
            if self.header:
                f.write(f"Unimplemented imports at start-up: {self.header[0]} of {self.header[1]}\n")
            else:
                f.write("Unimplemented imports at start-up: not in the output (PURE_LIST_STUBS unset?)\n")
            for name in self.listed:
                f.write(f"  {name}\n")
            f.write(f"Called during the run: {len(self.called)} (the framework prints a stub's first call only)\n")
            for label, (count, ra) in self.called.items():
                f.write(f"  [hle-stub] {label} ra={ra}" + (f" (x{count})" if count > 1 else "") + "\n")
        return n, len(self.called)


def bmp_state(directory):
    try:
        names = os.listdir(directory)
    except FileNotFoundError:
        return {}
    return {n: os.stat(os.path.join(directory, n)).st_mtime_ns for n in names if n.lower().endswith(".bmp")}


def convert_shots(directory, before):
    """Converts the BMPs that are new or rewritten since `before` to PNGs; returns (converted, errors)."""
    converted, errors = [], []
    for name, mtime in sorted(bmp_state(directory).items()):
        if before.get(name) == mtime:
            continue
        src = os.path.join(directory, name)
        try:
            w, h, c, data = png.read_bmp(src)
            png.write_png(os.path.splitext(src)[0] + ".png", w, h, c, data)
            converted.append(name)
        except (OSError, ValueError) as e:
            errors.append(f"{name}: {e}")
    return converted, errors


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    log = opts.log
    seconds = opts.seconds
    env = dict(os.environ)
    env.setdefault("PURE_GAME_DIR", os.path.join(ROOT, "game"))
    env.setdefault("PURE_LIST_STUBS", "1")
    headless = opts.shell == "headless"
    window = opts.window or (opts.shell is not None and not headless) or \
        (not headless and (opts.script is not None or opts.shots is not None))
    if not window:
        env.setdefault("PURE_NO_RENDER", "1")
    if opts.shell is not None:
        env["PURE_SHELL"] = opts.shell
    if opts.backend is not None:
        env["PURE_GE_BACKEND"] = opts.backend
    if headless:
        # No window; the null backend unless one is named (the default one would draw on the GPU).
        if opts.backend is None and not env.get("PURE_GE_BACKEND"):
            env["PURE_GE_BACKEND"] = "null"
    # The checks measure the Metal backend's native picture (task 066): a run on it draws at internal scale 1
    # unless the caller sets PURE_INTERNAL_SCALE (tools/scale_check.sh does), whatever the data directory says.
    # The Vulkan backend's runs keep the settings' scale (2): its columns were measured on its 2x target copied
    # 1:1 into the 960x544 window, and a 1x target there is upscaled bilinear by its shell, which moves them.
    backend = env.get("PURE_GE_BACKEND") or ("metal" if sys.platform == "darwin" else "vulkan")
    if backend == "metal":
        env.setdefault("PURE_INTERNAL_SCALE", "1")
    if opts.strict:
        env["PURE_STRICT_HLE"] = "1"
    if opts.frames is not None:
        env["PURE_EXIT_AT_FRAME"] = str(opts.frames); seconds = max(seconds, opts.frames / 15.0)
    if opts.script is not None:
        env["PURE_INPUT_SCRIPT"] = read_script(opts.script)
    shots = os.path.abspath(opts.shots) if opts.shots is not None else None
    if shots is not None:
        os.makedirs(shots, exist_ok=True)
        env["PURE_SCREENSHOT_DIR"] = shots
        env["PURE_SCREENSHOT_EVERY"] = str(opts.every if opts.every is not None else 0)
    elif opts.every is not None:
        env["PURE_SCREENSHOT_EVERY"] = str(opts.every)
    if opts.stubs:
        env["PURE_LIST_STUBS"] = "1"
    extra = dict(kv.split("=", 1) for kv in opts.env)
    asked = dict(env, **extra)          # --env counts as the environment for the defaults below
    silence(asked, opts.sound, window)
    scratch_data_dir(asked, opts.data_dir)
    if not window and not opts.sound:
        port.steady_clock(asked)
    env.update(asked)
    shots_before = bmp_state(shots) if shots is not None else {}

    run = port.PtyRun(env, log, seconds, opts.max_lines)     # the game under a pty, its log folded as it comes
    stubs = Stubs()
    try:
        while run.alive() and not run.killed:
            for line in run.read(min(max(run.deadline - time.time(), 0.0), 0.25)):
                stubs.feed(line)
    except BaseException:              # Ctrl-C or an error in here: do not leave the game running
        run.kill()
        raise
    for line in run.drain():           # the game has exited; what it wrote last is still in the pty
        stubs.feed(line)
    if run.timed_out:
        run.emit(f"[run_boot] deadline {seconds:.0f}s reached, killed", True)
    elif run.frame_exit and run.returncode < 0:
        run.emit(f"[run_boot] killed {FRAME_EXIT_GRACE:.0f}s after the frame exit (shutdown hung)", True)
    if opts.stubs:
        listed, called = stubs.write(log + ".stubs.txt", log)
        run.emit(f"[run_boot] stubs: {listed} unimplemented at start-up, {called} called -> {log}.stubs.txt", True)
    if shots is not None:
        converted, errors = convert_shots(shots, shots_before)
        for e in errors:
            run.emit(f"[run_boot] shots: cannot convert {e}", True)
        names = ", ".join(os.path.splitext(n)[0] for n in converted[:8]) + (", ..." if len(converted) > 8 else "")
        run.emit(f"[run_boot] shots: {len(converted)} new BMP(s) converted to PNG in {opts.shots}"
                 + (f" ({names})" if converted else ""), True)
    code = run.close("run_boot", signals=True)
    print("\n".join(run.tail))
    return code


if __name__ == "__main__":
    sys.exit(main())
