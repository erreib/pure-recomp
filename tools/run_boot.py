#!/usr/bin/env python3
"""Bounded run of PureNative with a de-duplicated, length-capped log.

  tools/run_boot.py [--seconds N] [--frames N] [--window] [--strict] [--script FILE] [--shots DIR] [--every N]
                    [--stubs] [--max-lines N] [--env KEY=VAL ...] out/run.log

Defaults: headless (PURE_NO_RENDER=1 PURE_NO_AUDIO=1), 60 s wall-clock deadline, stubs listed at start-up
(PURE_LIST_STUBS=1). --window keeps the renderer and audio on. --strict sets PURE_STRICT_HLE=1.
--frames N sets PURE_EXIT_AT_FRAME=N (the profile stops the runtime at that flip), raises the deadline to
max(seconds, N/15) and exits 0 when the run ended there (`[pure] exit at frame` in the output).
--script FILE joins the file's non-empty lines that do not start with `#` with `;` into PURE_INPUT_SCRIPT and
implies --window (the script drives the renderer's virtual pad). --shots DIR sets PURE_SCREENSHOT_DIR (and implies
--window: headless runs capture nothing); after the run every BMP that is new or rewritten there is converted to a
PNG of the same name with tools/png.py, and the BMP is kept. --every N sets PURE_SCREENSHOT_EVERY (default 0 with
--shots, so only the script's `shot` steps write). --stubs writes <log>.stubs.txt: the start-up "Unimplemented
imports" list and each `[hle-stub]` call with its ra (the framework prints a stub's first call only).
--env KEY=VAL is applied last and overrides all of the above.

The game runs under a pty, so its stdout is line-buffered and nothing is lost when the deadline kills it. The parent
keeps the pty's slave end open until the output is drained: macOS discards unread pty output once the last slave
descriptor closes. Repeated identical lines are folded into "... (xN)" and the log stops at --max-lines (default
20000) while the process keeps running until the deadline. The log always ends with the `[run_boot] exit` line, and
its last 25 lines are echoed to stdout. Exit code is the game's, 0 after a --frames exit, or 124 on the deadline.
"""
import argparse, os, pty, re, select, subprocess, sys, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import png  # noqa: E402  (tools/png.py)

FRAME_EXIT = "[pure] exit at frame"
FRAME_EXIT_GRACE = 15.0     # seconds the runtime gets to shut down after the frame exit before it is killed
STUB_RE = re.compile(r"\[hle-stub\] (\S+)")
RA_RE = re.compile(r"\bra=(0x[0-9A-Fa-f]+)")
LIST_RE = re.compile(r"Unimplemented imports: (\d+) of (\d+)")


def parse(argv):
    p = argparse.ArgumentParser(prog="run_boot.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("log")
    p.add_argument("--seconds", type=float, default=60.0)
    p.add_argument("--frames", type=int)
    p.add_argument("--window", action="store_true")
    p.add_argument("--strict", action="store_true")
    p.add_argument("--script")
    p.add_argument("--shots")
    p.add_argument("--every", type=int)
    p.add_argument("--stubs", action="store_true")
    p.add_argument("--max-lines", type=int, default=20000)
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
    exe = os.path.join(ROOT, "build", "arm64", "bin", "PureNative")
    env = dict(os.environ)
    env.setdefault("PURE_GAME_DIR", os.path.join(ROOT, "game"))
    env.setdefault("PURE_LIST_STUBS", "1")
    window = opts.window or opts.script is not None or opts.shots is not None
    if not window:
        env.setdefault("PURE_NO_RENDER", "1"); env.setdefault("PURE_NO_AUDIO", "1")
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
    env.update(kv.split("=", 1) for kv in opts.env)
    os.makedirs(os.path.dirname(os.path.abspath(log)) or ".", exist_ok=True)
    shots_before = bmp_state(shots) if shots is not None else {}

    # A pty for stdout and stderr: line-buffered stdio in the game, no "\r\n" translation on output.
    master, slave = pty.openpty()
    attrs = termios.tcgetattr(slave)
    attrs[1] &= ~termios.OPOST
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    start = time.time()
    p = subprocess.Popen([exe], cwd=ROOT, env=env, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave)

    stubs = Stubs()
    last, repeat, written, tail = None, 0, 0, []
    timed_out = frame_exit = False
    deadline = start + seconds
    with open(log, "w") as out:
        def emit(line, always=False):
            nonlocal written
            if always:                     # the runner's own closing lines are written past the cap too
                out.write(line + "\n")
            elif written < max(opts.max_lines, 0):
                out.write(line + "\n"); written += 1
                if written == opts.max_lines: out.write(f"... log capped at {opts.max_lines} lines\n")
            tail.append(line); del tail[:-25]

        def flush_repeat():
            nonlocal repeat
            if repeat > 1: emit(f"    ... (x{repeat})")
            repeat = 0

        def take(raw):
            nonlocal last, repeat, frame_exit, deadline
            line = raw.decode("utf-8", "replace").rstrip("\r")
            stubs.feed(line)
            if not frame_exit and line.startswith(FRAME_EXIT):
                frame_exit = True
                deadline = min(deadline, time.time() + FRAME_EXIT_GRACE)
            if line == last: repeat += 1; return
            flush_repeat(); last = line; repeat = 1; emit(line)

        buf = b""
        def drain(timeout):
            """Reads what the pty holds; returns False when nothing arrived within timeout."""
            nonlocal buf
            ready, _, _ = select.select([master], [], [], timeout)
            if not ready:
                return False
            try:
                chunk = os.read(master, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            buf += chunk
            *lines, buf = buf.split(b"\n")
            for raw in lines:
                take(raw)
            return True

        try:
            while p.poll() is None:
                remaining = deadline - time.time()
                if remaining <= 0:
                    timed_out = not frame_exit
                    p.kill()
                    break
                drain(min(remaining, 0.25))
        except BaseException:              # Ctrl-C or an error in here: do not leave the game running
            p.kill()
            raise
        try:
            p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            p.kill(); p.wait()
        # The game has exited; the slave is still open here, so what it wrote last is still in the pty.
        drain_end = time.time() + 5.0
        while drain(0.05) and time.time() < drain_end:
            pass
        os.close(slave); os.close(master)
        if buf:
            take(buf)
        flush_repeat()
        if timed_out:
            emit(f"[run_boot] deadline {seconds:.0f}s reached, killed", True)
        elif frame_exit and p.returncode < 0:
            emit(f"[run_boot] killed {FRAME_EXIT_GRACE:.0f}s after the frame exit (shutdown hung)", True)
        if opts.stubs:
            listed, called = stubs.write(log + ".stubs.txt", log)
            emit(f"[run_boot] stubs: {listed} unimplemented at start-up, {called} called -> {log}.stubs.txt", True)
        if shots is not None:
            converted, errors = convert_shots(shots, shots_before)
            for e in errors:
                emit(f"[run_boot] shots: cannot convert {e}", True)
            names = ", ".join(os.path.splitext(n)[0] for n in converted[:8]) + (", ..." if len(converted) > 8 else "")
            emit(f"[run_boot] shots: {len(converted)} new BMP(s) converted to PNG in {opts.shots}"
                 + (f" ({names})" if converted else ""), True)
        if frame_exit:
            code = 0
        elif timed_out:
            code = 124
        else:
            code = p.returncode if p.returncode >= 0 else 128 - p.returncode
        emit(f"[run_boot] exit {code} after {time.time() - start:.1f}s, {written} lines", True)
    print("\n".join(tail))
    return code


if __name__ == "__main__":
    sys.exit(main())
