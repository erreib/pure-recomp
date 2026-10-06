#!/usr/bin/env python3
"""Turn a run log into a replayable input script.

Record:  python3 tools/run_boot.py --window --seconds 1200 --max-lines 400000 \
             --env PURE_TRACE_PAD=1 --env PURE_FRAME_LOG=1 out/lap.log
Convert: python3 tools/pad_record.py out/lap.log config/pad_scripts/lap.txt [--from FRAME] [--to FRAME]

The log must carry a `[pure] frame N` line per flip (PURE_FRAME_LOG=1) and the framework's `[pad] buttons 0x.. analog
X,Y right X,Y` lines, which it prints when the pad state changes. Each change is attributed to the last flip seen.
Buttons become `F:pad NAME HOLD` steps (SDL names), the left stick `F:axis leftx V` / `axis lefty V` steps.
"""
import re, sys

BUTTONS = {0x0001: "back", 0x0008: "start", 0x0010: "dpup", 0x0020: "dpright", 0x0040: "dpdown", 0x0080: "dpleft",
           0x0100: "leftshoulder", 0x0200: "rightshoulder", 0x1000: "y", 0x2000: "b", 0x4000: "a", 0x8000: "x"}

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = sys.argv[1:]
    lo = int(opts[opts.index("--from") + 1]) if "--from" in opts else 0
    hi = int(opts[opts.index("--to") + 1]) if "--to" in opts else 10**9
    log, out = args[0], args[1]
    frame, events = 0, []   # (frame, buttons, lx, ly)
    for line in open(log, errors="replace"):
        m = re.match(r"\[pure\] frame (\d+)", line)
        if m: frame = int(m.group(1)); continue
        m = re.match(r"\[pad\] buttons 0x([0-9A-Fa-f]+) analog (\d+),(\d+)", line)
        if m and lo <= frame <= hi:
            events.append((frame, int(m.group(1), 16), int(m.group(2)), int(m.group(3))))
    steps, down, last_axis = [], {}, (None, None)
    for f, buttons, x, y in events:
        for bit, name in BUTTONS.items():
            held = bool(buttons & bit)
            if held and bit not in down:
                down[bit] = f
            elif not held and bit in down:
                start = down.pop(bit)
                steps.append((start, f"pad {name} {max(1, f - start)}"))
        ax = (round((x - 128) / 127.0, 2), round((y - 128) / 127.0, 2))
        if ax[0] != last_axis[0]: steps.append((f, f"axis leftx {ax[0]}"))
        if ax[1] != last_axis[1]: steps.append((f, f"axis lefty {ax[1]}"))
        last_axis = ax
    end = events[-1][0] if events else frame
    for bit, start in down.items(): steps.append((start, f"pad {BUTTONS[bit]} {max(1, end - start)}"))
    steps = [s for s in steps if s[1]]
    steps.sort()
    with open(out, "w") as w:
        w.write(f"# converted from {log}: {len(events)} pad changes, frames {lo}..{min(hi, end)}\n")
        for f, s in steps: w.write(f"{f}:{s}\n")
    print(f"{len(steps)} steps -> {out} (frames {events[0][0] if events else 0}..{end})")

if __name__ == "__main__":
    main()
