#!/usr/bin/env python3
"""Names each hiccup in a run's sound (task 501).
  tools/audio_hiccups.py LOG [--all]
LOG is a run with PURE_TRACE_AUDIO=1 and PURE_PERF=log: a play session's stdout, or tools/display_rate_check.sh
--audio's run.log. One line per `[audio]` second that carries an event, with the host's second beside it and what the
event was, so a hiccup heard at a wall-clock time can be matched to its cause:
  restart   a channel that sat idle and restarted (a jump over a second of audio, purelib.logs.RESTART_FRAMES):
            nothing that was playing skipped
  snap      a producer jumped forward (`resyncs=`): a click. Named by the jump and the host's seconds around it:
            `a dip ate the lead` when the jump is under DIP_JUMP frames (the producer was at most a few buffers
            behind: the sink's floor, 256 frames since task 503, or PURE_AUDIO_SNAP=1's old rule, which snaps at a
            lead under 512), else `a host stall` when the worst frame of the `[perf]` second before or after is over
            STALL_MS (the machine, or the race load), `the race under speed` when either ran under SLOW_SPEED% (the
            game cannot keep real time), else `unexplained`
  late      the sink's rule (patch 0031-audio-sink-late-writes): writes under the lead (`lates=`), with the
            frames already played dropped (`late=`) and the silence the device played (`silent=`); the 1% rebuild
            follows. With `late=0` and `silent=0` it is the rule arming, nothing audible
  dry       silence (`silent=`) with nothing late: nothing was written for the device to play
  mark      the listener's key (F8, or one stick clicked alone; patch 0032-trace-marks): `[mark] N`, printed in its
            place among the events, so what was heard sits beside what the sink and the host did that second
`--all` prints every `[audio]` second. The host's second is the count of `[perf]` lines before the line (the perf
line counts wall seconds from start-up, the audio line 44100-frame windows: the same clock once the run is paced,
not in the harness's unpaced menus). Lines before `[pure] paced from frame` (a tool's unpaced menus and race load)
are marked `unpaced`; a run without that line (a play session) is paced throughout. Exit 0; the reading is the
user's.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from purelib.logs import PACED, RESTART_FRAMES, perf  # noqa: E402

STALL_MS = 50          # a worst frame over this in a host second beside the event: a stall (five vblanks at 100 Hz)
SLOW_SPEED = 95        # a host second under this speed: the race not keeping real time
DIP_JUMP = 4096        # a snap lands 2048 ahead: a mean jump under this came from a cursor under 2048 behind, a dip's
AUDIO_FIELDS_RE = re.compile(r"^\[audio\] (\d+)s frames=(\d+) .*silent=(\d+) .*resyncs=(\d+) resynced=(\d+) "
                             r"lead=(\d+) lates=(\d+) late=(\d+) ratio=([\d.]+)")
MARK_RE = re.compile(r"^\[mark\] (\d+)")


def name(a, hosts):
    """What an audio second's figures say, given the `[perf]` seconds around it (dicts, may be empty)."""
    second, frames, silent, resyncs, resynced, lead, lates, late, ratio = a
    worst = max((h["frame_max"] for h in hosts), default=0.0)
    slowest = min((h["speed"] for h in hosts), default=100)
    if resyncs and resynced // resyncs > RESTART_FRAMES:
        return f"restart: {resyncs} channel{'s' if resyncs > 1 else ''} restarted ({resynced} frames), no skip"
    if resyncs:
        if resynced // resyncs < DIP_JUMP:
            why = "a dip ate the lead" + (f" ({slowest}% speed)" if slowest < SLOW_SPEED else "")
        elif worst > STALL_MS:
            why = f"a host stall ({worst:.0f} ms worst frame)"
        elif slowest < SLOW_SPEED:
            why = f"the race under speed ({slowest}%)"
        else:
            why = "unexplained"
        return f"snap: {resyncs} click{'s' if resyncs > 1 else ''} ({resynced} frames jumped), {why}"
    if lates:
        if late or silent:
            return (f"late: {lates} writes under the lead, {late} frames dropped, {silent} silent "
                    f"({silent * 1000 // 44100} ms), lead {lead}, ratio {ratio}")
        return f"late: {lates} writes under the lead, nothing dropped (arming), lead {lead}, ratio {ratio}"
    if silent:
        return f"dry: {silent} silent frames ({silent * 1000 // 44100} ms), nothing late, lead {lead}"
    return None


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 2
    show_all = "--all" in argv
    host, host_second = None, 0
    pending = []        # events waiting for the `[perf]` line after them: (kind, fields, host before, second, paced)
    counts = {}

    def flush(after):
        for kind, a, before, second, was_paced in pending:
            if kind == "mark":
                what = f"mark {a}: heard here"
            else:
                what = name(a, [h for h in (before, after) if h])
                if what is None and not show_all:
                    continue
            label = (what or "quiet").split(":")[0].split(" ")[0]
            counts[label] = counts.get(label, 0) + 1
            where = f"audio {a[0]}s" if kind == "audio" else f"[mark] {a}"
            print(f"{where}  host second {second}{'' if was_paced else ' unpaced'}  {what or 'quiet'}")
        pending.clear()

    with open(argv[1], errors="replace") as f:
        lines = [line.rstrip("\n") for line in f]
    # A run with no `[pure] paced from frame` line (a play session) is paced throughout; a tool's run is unpaced
    # before that line.
    paced = not any(line.startswith(PACED) for line in lines)
    for line in lines:
        p = perf(line)
        if p:
            flush(p)
            host, host_second = p, host_second + 1
            continue
        if line.startswith(PACED):
            paced = True
            continue
        m = MARK_RE.match(line)
        if m:
            pending.append(("mark", int(m[1]), host, host_second, paced))
            continue
        m = AUDIO_FIELDS_RE.match(line)
        if m:
            pending.append(("audio", (int(m[1]), int(m[2]), int(m[3]), int(m[4]), int(m[5]), int(m[6]), int(m[7]),
                                      int(m[8]), m[9]), host, host_second, paced))
    flush(None)
    print("hiccups: " + (", ".join(f"{k} {n}" for k, n in sorted(counts.items())) or "none") +
          " (snap: a click; late with frames dropped or silence: the sink's rule at a dip; restart: not audible;"
          " mark: the listener's key)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
