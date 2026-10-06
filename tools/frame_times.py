#!/usr/bin/env python3
"""Summary of a Metal frame trace (PURE_METAL_TRACE=FILE, task 033; docs/metal-backend.md, "Frame times").

  tools/frame_times.py TRACE [--long MS] [--fps N] [--from FLIP] [--to FLIP] [--top N] [--plot OUT.png]
                             [--check-no-pipeline-stalls-after N]

TRACE is the CSV the Metal backend writes, a row per flip: the time since the previous flip (frame_ms) and where it
went. The columns, in milliseconds unless they are counts:
  submit_ms      CPU time in the backend's submit() (a draw each), of which pipeline_ms (making render pipelines and
                 depth-stencil states, or waiting for the pre-warm to) and texture_ms (hashing and decoding textures)
  present_ms     the backend's present_image() at the flip before, memory_ms its calls between guest memory and the
                 GPU (the SIGNAL's depth write-back, the frame write-back, transfers, read-backs, uploads, captures);
                 both include their GPU waits, which wait_ms sums and wait_depth_ms, wait_frame_ms, wait_guest_ms,
                 wait_capture_ms and wait_ring_ms (more than two frames in flight) split
  pipelines, depth_states   made by a draw in the interval; decoded, decoded_kb: textures decoded; stencil_copies,
                 draws, passes, copies
  shell_ms       the Metal shell's present() (empty under another shell), drawable_ms of it waiting in nextDrawable;
                 occluded: how many of the interval's presents found the window occluded (macOS shows none of them,
                 and may hold nextDrawable back for up to a second)
  shown_ms       when this flip's picture reached the screen after the previous picture shown did (the drawable's
                 presentedTime), latency_ms after the shell's present() began; empty when it never reached it
  other_ms       the rest: the game's own code, the HLE, the kernel's pacing sleep (frame_ms minus the parts above)
A long frame's cause is the part that exceeds its median over the rows read by the most: pipeline, texture, draws
(the rest of submit), wait depth/frame/guest/capture/ring, backend (present and memory CPU besides their waits),
shell (its CPU besides the drawable), drawable (`drawable, occluded` when the window was occluded), outside
(other_ms: the game, the HLE, pacing).

Prints the frame count, the mean, median, 99th percentile and longest frame time, the frames over --long (default 20
ms) and over 1.5 frames at --fps (default 60), the on-screen intervals when the trace has them, a histogram, the
longest --top (default 10) frames with their columns and cause, and the long frames counted by cause. --from and
--to keep the rows of those flips only (both included). --plot OUT.png draws frame_ms per flip (tools/png.py): the
long frames coloured by cause, lines at the frame time of --fps and at --long.
--check-no-pipeline-stalls-after N exits 1 when a frame after flip N takes over 25 ms with a render pipeline or a
depth-stencil state made in it (the acceptance rule of task 033); without it the exit is 0 unless the trace cannot
be read (2).
"""
import argparse, csv, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

STALL_MS = 25.0      # --check-no-pipeline-stalls-after: a frame this long with a pipeline made in it fails

# Each cause: its name, the colour it is plotted in, and how it is read from a row (milliseconds).
CAUSES = [
    ("pipeline", (230, 60, 60), lambda r: r["pipeline_ms"]),
    ("texture", (240, 160, 40), lambda r: r["texture_ms"]),
    ("draws", (200, 200, 60), lambda r: r["submit_ms"] - r["pipeline_ms"] - r["texture_ms"]),
    ("wait depth", (60, 140, 230), lambda r: r["wait_depth_ms"]),
    ("wait frame", (90, 90, 230), lambda r: r["wait_frame_ms"]),
    ("wait guest", (140, 90, 230), lambda r: r["wait_guest_ms"]),
    ("wait capture", (180, 90, 200), lambda r: r["wait_capture_ms"]),
    ("wait ring", (60, 200, 230), lambda r: r["wait_ring_ms"]),
    ("backend", (120, 180, 120), lambda r: r["present_ms"] + r["memory_ms"] - r["wait_ms"]),
    ("shell", (60, 180, 60), lambda r: r["shell_ms"] - r["drawable_ms"]),
    ("drawable", (30, 120, 30), lambda r: r["drawable_ms"]),
    ("outside", (150, 150, 150), lambda r: r["other_ms"]),
]
SHOWN = ("pipelines", "depth_states", "decoded", "decoded_kb", "stencil_copies", "draws", "passes", "copies")
SHOWN_LABELS = ("pipes", "depths", "decode", "dec_kb", "stcopy", "draws", "passes", "copies")


def read_trace(path):
    """The trace's rows as dicts of floats (empty cells as 0.0, and `has_shell`/`has_shown` set when the shell's
    columns were filled)."""
    rows = []
    with open(path, newline="") as f:
        for raw in csv.DictReader(f):
            row = {}
            for key, value in raw.items():
                if key is None:
                    continue
                try:
                    row[key] = float(value) if value not in ("", None) else 0.0
                except ValueError:
                    row[key] = 0.0
            row["has_shell"] = raw.get("shell_ms", "") not in ("", None)
            row["has_shown"] = raw.get("shown_ms", "") not in ("", None)
            row["flip"] = int(row.get("flip", 0))
            rows.append(row)
    return rows


def percentile(values, p):
    if not values:
        return 0.0
    ordered = sorted(values)
    k = (len(ordered) - 1) * p / 100.0
    lo = int(k)
    hi = min(lo + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def medians(rows):
    return {name: percentile([get(r) for r in rows], 50) for name, _, get in CAUSES}


def cause_of(row, median):
    """The part of the row that exceeds its median by the most, and that excess (ms)."""
    best, excess = "outside", float("-inf")
    for name, _, get in CAUSES:
        e = get(row) - median[name]
        if e > excess:
            best, excess = name, e
    if best == "drawable" and row.get("occluded", 0.0) > 0:
        best = "drawable, occluded"
    return best, excess


def histogram(values, edges):
    counts = [0] * (len(edges) + 1)
    for v in values:
        i = 0
        while i < len(edges) and v >= edges[i]:
            i += 1
        counts[i] += 1
    return counts


def print_histogram(title, values, edges):
    counts = histogram(values, edges)
    total = max(1, len(values))
    widest = max(counts) if counts else 1
    print(f"\n{title}")
    labels = [f"< {edges[0]:g}"] + [f"{edges[i - 1]:g}-{edges[i]:g}" for i in range(1, len(edges))] + [f">= {edges[-1]:g}"]
    for label, count in zip(labels, counts):
        if count == 0 and label.startswith("<"):
            continue
        bar = "#" * max(1 if count else 0, round(40 * count / widest)) if widest else ""
        print(f"  {label:>9} ms {count:7d} {100.0 * count / total:6.2f}%  {bar}")


def plot(path, rows, median, budget, long_ms):
    import png
    width, height = 1600, 360
    top_ms = max(50.0, min(200.0, max((r["frame_ms"] for r in rows), default=50.0)))
    pixels = bytearray([255] * (width * height * 3))

    def put(x, y, colour):
        if 0 <= x < width and 0 <= y < height:
            i = (y * width + x) * 3
            pixels[i:i + 3] = bytes(colour)

    def y_of(ms):
        return height - 1 - int(min(ms, top_ms) / top_ms * (height - 1))

    n = len(rows)
    colours = {name: colour for name, colour, _ in CAUSES}
    colours["drawable, occluded"] = colours["drawable"]
    for x in range(width):
        lo, hi = x * n // width, max(x * n // width + 1, (x + 1) * n // width)
        chunk = rows[lo:hi]
        if not chunk:
            continue
        worst = max(chunk, key=lambda r: r["frame_ms"])
        colour = (170, 170, 170)
        if worst["frame_ms"] > long_ms:
            colour = colours[cause_of(worst, median)[0]]
        for y in range(y_of(worst["frame_ms"]), height):
            put(x, y, colour)
    for ms, colour in ((budget, (40, 160, 40)), (long_ms, (200, 40, 40))):
        if ms and ms < top_ms:
            for x in range(0, width, 2):
                put(x, y_of(ms), colour)
    png.write_png(path, width, height, 3, bytes(pixels))
    print(f"\nplot: {path} ({width}x{height}, flips {rows[0]['flip']}-{rows[-1]['flip']}, 0-{top_ms:g} ms; long frames "
          f"coloured by cause: " + ", ".join(f"{name} rgb{colour}" for name, colour, _ in CAUSES) + ")")


def main(argv=None):
    p = argparse.ArgumentParser(prog="frame_times.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("trace")
    p.add_argument("--long", type=float, default=20.0)
    p.add_argument("--fps", type=float, default=60.0)
    p.add_argument("--from", dest="first", type=int, default=None)
    p.add_argument("--to", dest="last", type=int, default=None)
    p.add_argument("--top", type=int, default=10)
    p.add_argument("--plot")
    p.add_argument("--check-no-pipeline-stalls-after", dest="check", type=int, default=None)
    opts = p.parse_args(argv)
    try:
        rows = read_trace(opts.trace)
    except (OSError, csv.Error) as error:
        print(f"frame_times: cannot read {opts.trace}: {error}")
        return 2
    every = rows
    if opts.first is not None:
        rows = [r for r in rows if r["flip"] >= opts.first]
    if opts.last is not None:
        rows = [r for r in rows if r["flip"] <= opts.last]
    if not rows:
        print(f"frame_times: {opts.trace}: no rows{' in the flips asked for' if every else ''}")
        return 2
    budget = 1000.0 / opts.fps if opts.fps > 0 else 0.0
    times = [r["frame_ms"] for r in rows]
    median = medians(rows)
    long_rows = [r for r in rows if r["frame_ms"] > opts.long]
    missed = sum(1 for t in times if budget and t > 1.5 * budget)
    span = (rows[-1]["t_ms"] - rows[0]["t_ms"] + rows[0]["frame_ms"]) / 1000.0
    print(f"{opts.trace}: flips {rows[0]['flip']}-{rows[-1]['flip']}, {len(rows)} frames in {span:.1f} s "
          f"({len(rows) / span if span > 0 else 0.0:.1f} a second)")
    print(f"  frame time: mean {sum(times) / len(times):.2f} ms, median {percentile(times, 50):.2f}, "
          f"99th percentile {percentile(times, 99):.2f}, longest {max(times):.2f}")
    print(f"  over {opts.long:g} ms: {len(long_rows)}; over 1.5 frames at {opts.fps:g} fps ({1.5 * budget:.1f} ms): "
          f"{missed}")
    print(f"  per frame: draws {sum(r['draws'] for r in rows) / len(rows):.0f}, submit "
          f"{sum(r['submit_ms'] for r in rows) / len(rows):.2f} ms, GPU waits {sum(r['wait_ms'] for r in rows) / len(rows):.2f} ms"
          + (f", shell {sum(r['shell_ms'] for r in rows) / len(rows):.2f} ms" if any(r["has_shell"] for r in rows) else "")
          + f"; in all {sum(int(r['pipelines']) for r in rows)} pipelines and {sum(int(r['depth_states']) for r in rows)} "
          f"depth-stencil states made by draws, {sum(int(r['decoded']) for r in rows)} textures decoded "
          f"({sum(r['decoded_kb'] for r in rows) / 1024.0:.1f} MiB)")
    shown = [r["shown_ms"] for r in rows if r["has_shown"]]
    if shown:
        latency = [r["latency_ms"] for r in rows if r["has_shown"]]
        never = sum(1 for r in rows if r["has_shell"] and not r["has_shown"])
        occluded = [r["flip"] for r in rows if r.get("occluded", 0.0) > 0]
        if occluded:
            print(f"  window occluded at {len(occluded)} presents, flips {occluded[0]}-{occluded[-1]}: what macOS "
                  f"shows and the drawable waits of those frames are not a player's")
        print(f"  on screen (the drawables' presented times, {len(shown)} pictures): interval mean "
              f"{sum(shown) / len(shown):.2f} ms, 99th percentile {percentile(shown, 99):.2f}, longest {max(shown):.2f}, "
              f"over {opts.long:g} ms {sum(1 for s in shown if s > opts.long)}; latency from the shell's present "
              f"mean {sum(latency) / len(latency):.1f} ms, longest {max(latency):.1f}; pictures never shown {never}")

    edges = [4, 8, 12, 16, 17, 18, 20, 25, 33, 50, 100]
    print_histogram("frame_ms histogram", times, edges)
    if shown:
        print_histogram("shown_ms histogram (on screen)", shown, edges)

    print(f"\nmedians: " + ", ".join(f"{name} {median[name]:.2f}" for name, _, _ in CAUSES))
    top = sorted(rows, key=lambda r: r["frame_ms"], reverse=True)[:opts.top]
    print(f"\nlongest {len(top)} frames:")
    print(f"  {'flip':>6} {'t_s':>8} {'frame':>7}  {'cause':<18} {'excess':>7}  " +
          " ".join(f"{c:>8}" for c in ("submit", "pipeline", "texture", "present", "memory", "wait", "shell", "drawable",
                                       "other")) + "  " + " ".join(f"{c:>6}" for c in SHOWN_LABELS) + "  occl")
    for r in top:
        cause, excess = cause_of(r, median)
        print(f"  {r['flip']:>6} {r['t_ms'] / 1000.0:>8.2f} {r['frame_ms']:>7.2f}  {cause:<18} {excess:>7.2f}  " +
              " ".join(f"{r[c]:>8.2f}" for c in ("submit_ms", "pipeline_ms", "texture_ms", "present_ms", "memory_ms",
                                                 "wait_ms", "shell_ms", "drawable_ms", "other_ms")) + "  " +
              " ".join(f"{r[c]:>6g}" for c in SHOWN) + f"  {r.get('occluded', 0.0):>4g}")

    if long_rows:
        tally = {}
        for r in long_rows:
            cause, excess = cause_of(r, median)
            count, total, flips = tally.get(cause, (0, 0.0, []))
            tally[cause] = (count + 1, total + excess, flips + [r["flip"]])
        print(f"\nframes over {opts.long:g} ms by cause:")
        for cause, (count, total, flips) in sorted(tally.items(), key=lambda kv: -kv[1][0]):
            shown_flips = ", ".join(str(f) for f in flips[:12]) + (", ..." if len(flips) > 12 else "")
            print(f"  {cause:<18} {count:5d}  excess mean {total / count:6.2f} ms  flips {shown_flips}")
        with_pipelines = [r for r in long_rows if r["pipelines"] + r["depth_states"] > 0]
        print(f"  with a pipeline or depth-stencil state made: {len(with_pipelines)}"
              + (f" (flips {', '.join(str(r['flip']) for r in with_pipelines[:12])}"
                 f"{', ...' if len(with_pipelines) > 12 else ''})" if with_pipelines else ""))

    if opts.plot:
        plot(opts.plot, rows, median, budget, opts.long)

    if opts.check is not None:
        stalls = [r for r in every if r["flip"] > opts.check and r["frame_ms"] > STALL_MS
                  and r["pipelines"] + r["depth_states"] > 0]
        if stalls:
            print(f"\ncheck: FAIL: {len(stalls)} frames after flip {opts.check} over {STALL_MS:g} ms with a pipeline "
                  f"made in them: " + ", ".join(f"{r['flip']} ({r['frame_ms']:.1f} ms, {int(r['pipelines'])} "
                                                f"pipelines, {int(r['depth_states'])} depth states)" for r in stalls[:20]))
            return 1
        print(f"\ncheck: PASS: no frame after flip {opts.check} over {STALL_MS:g} ms with a pipeline made in it "
              f"({sum(1 for r in every if r['flip'] > opts.check)} frames checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
