#!/usr/bin/env python3
"""Bounded headless run of PureNative with a de-duplicated, length-capped log.

  tools/run_boot.py [--seconds N] [--frames N] [--window] [--strict] [--max-lines N] [--env KEY=VAL ...] out/run.log

Defaults: headless (PURE_NO_RENDER=1 PURE_NO_AUDIO=1), 60 s wall-clock deadline, stubs listed at start-up
(PURE_LIST_STUBS=1). --frames sets PURE_EXIT_AT_FRAME (once the runner supports it) and raises the deadline.
--window keeps the renderer and audio on. --strict sets PURE_STRICT_HLE=1. Repeated identical lines are folded into
"... (xN)" and the log stops at --max-lines (default 20000) while the process keeps running until the deadline.
The last 25 lines are echoed to stdout. Exit code is the game's, or 124 on the deadline.
"""
import os, signal, subprocess, sys, threading, time

def main():
    args = sys.argv[1:]
    seconds, frames, window, strict, max_lines, extra = 60.0, None, False, False, 20000, {}
    log = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--seconds": seconds = float(args[i + 1]); i += 2
        elif a == "--frames": frames = int(args[i + 1]); i += 2
        elif a == "--window": window = True; i += 1
        elif a == "--strict": strict = True; i += 1
        elif a == "--max-lines": max_lines = int(args[i + 1]); i += 2
        elif a == "--env": k, v = args[i + 1].split("=", 1); extra[k] = v; i += 2
        else: log = a; i += 1
    if not log: sys.exit(__doc__)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    exe = os.path.join(root, "build", "arm64", "bin", "PureNative")
    env = dict(os.environ)
    env.setdefault("PURE_GAME_DIR", os.path.join(root, "game"))
    env.setdefault("PURE_LIST_STUBS", "1")
    if not window:
        env.setdefault("PURE_NO_RENDER", "1"); env.setdefault("PURE_NO_AUDIO", "1")
    if strict: env["PURE_STRICT_HLE"] = "1"
    if frames is not None:
        env["PURE_EXIT_AT_FRAME"] = str(frames); seconds = max(seconds, frames / 10.0)
    env.update(extra)
    os.makedirs(os.path.dirname(os.path.abspath(log)) or ".", exist_ok=True)
    start = time.time()
    p = subprocess.Popen([exe], cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         errors="replace", bufsize=1)
    last, repeat, written, tail = None, 0, 0, []
    timed_out = threading.Event()
    def watchdog():
        if not timed_out.wait(0) and p.poll() is None:
            time.sleep(max(0.0, seconds - (time.time() - start)))
            if p.poll() is None:
                timed_out.set(); p.kill()
    threading.Thread(target=watchdog, daemon=True).start()
    with open(log, "w") as out:
        def emit(line):
            nonlocal written
            if written < max_lines:
                out.write(line + "\n"); written += 1
                if written == max_lines: out.write(f"... log capped at {max_lines} lines\n")
            tail.append(line); del tail[:-25]
        def flush_repeat():
            nonlocal repeat
            if repeat > 1: emit(f"    ... (x{repeat})")
            repeat = 0
        for line in p.stdout:
            line = line.rstrip("\n")
            if line == last: repeat += 1; continue
            flush_repeat(); last = line; repeat = 1; emit(line)
        flush_repeat()
        try: p.wait(timeout=10)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
        if timed_out.is_set(): emit(f"[run_boot] deadline {seconds:.0f}s reached, killed")
        code = 124 if timed_out.is_set() else p.returncode
        emit(f"[run_boot] exit {code} after {time.time() - start:.1f}s, {written} lines")
    print("\n".join(tail))
    sys.exit(code)

if __name__ == "__main__":
    main()
