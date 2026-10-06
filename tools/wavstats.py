#!/usr/bin/env python3
"""Loudness of a 16-bit PCM WAV per second, to check captured game audio without listening (task 013).

  tools/wavstats.py <wav> [--from S] [--to S] [--floor RMS] [--gap-ms G] [--min-active-frac F] [--max-clip-frac C]
                    [--quiet]

Prints one row per second from --from (default 0) to --to (default the end): RMS and peak over every sample of the
second, both sides together, on the int16 scale. Then the summary: the fraction of whole seconds whose RMS is above
the silence floor (--floor, default 100, about -50 dBFS), the silent seconds by their start time, the longest silent
run, and the clipping fraction (samples at -32768 or 32767 over all samples in the window). A trailing part second
is shown but left out of the active fraction. A dropout too short to make a second silent shows in the zero runs:
stretches of at least --gap-ms (default 50) where every sample is exactly 0, by start time and length, not counting
one that touches either end of the window. They are information only: between sound effects they are normal, inside
music they are dropouts.

--min-active-frac and --max-clip-frac turn the summary into a check: the last line is PASS (exit 0) when the active
fraction is at least F and the clipping fraction at most C, FAIL (exit 1) otherwise; with neither the last line is
INFO (exit 0). Bad input exits 2. --quiet leaves out the per-second rows. Pure Python (array + math.sumprod), about a
second per minute of stereo audio.
"""
import argparse
import math
import sys
import wave
from array import array


def parse(argv):
    p = argparse.ArgumentParser(prog="wavstats.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("wav")
    p.add_argument("--from", dest="start", type=float, default=0.0)
    p.add_argument("--to", dest="stop", type=float)
    p.add_argument("--floor", type=float, default=100.0)
    p.add_argument("--gap-ms", type=float, default=50.0)
    p.add_argument("--min-active-frac", type=float)
    p.add_argument("--max-clip-frac", type=float)
    p.add_argument("--quiet", action="store_true")
    return p.parse_args(argv)


def zero_runs(data, channels, min_frames):
    """(first frame, length) of each run of all-zero frames of at least min_frames inside data, not touching an end."""
    frame = 2 * channels
    block = bytes(frame * min_frames)
    frames = len(data) // frame
    runs, at = [], data.find(block)
    while at != -1:
        if at % frame:
            at = data.find(block, at + frame - at % frame)
            continue
        start = end = at // frame
        while start > 0 and not any(data[(start - 1) * frame:start * frame]):
            start -= 1
        end = at // frame + min_frames
        while end < frames and not any(data[end * frame:(end + 1) * frame]):
            end += 1
        if start > 0 and end < frames:
            runs.append((start, end - start))
        at = data.find(block, end * frame)
    return runs


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    try:
        source = wave.open(opts.wav, "rb")
    except (OSError, EOFError, wave.Error) as e:
        print(f"wavstats: cannot read {opts.wav}: {e}")
        return 2
    rate, channels, width, frames = (source.getframerate(), source.getnchannels(), source.getsampwidth(),
                                     source.getnframes())
    if width != 2:
        print(f"wavstats: {opts.wav} is {8 * width}-bit; only 16-bit PCM is read")
        return 2
    length = frames / rate
    print(f"{opts.wav}: {length:.1f} s, {rate} Hz, {channels} channel(s)")
    first = min(frames, max(0, int(round(opts.start * rate))))
    last = frames if opts.stop is None else min(frames, max(first, int(round(opts.stop * rate))))
    source.setpos(first)

    rows, active, whole, clipped, total, silent = 0, 0, 0, 0, 0, []
    window = bytearray()
    run = longest = 0
    longest_at = run_at = None
    at = first
    while at < last:
        n = min(rate, last - at)
        samples = array("h")
        samples.frombytes(source.readframes(n))
        if sys.byteorder != "little":
            samples.byteswap()
        if not samples:
            break
        window += samples.tobytes()
        t = at / rate
        rms = math.sqrt(math.sumprod(samples, samples) / len(samples))
        peak = max(max(samples), -min(samples))
        clip = samples.count(32767) + samples.count(-32768)
        clipped += clip
        total += len(samples)
        is_whole = n == rate
        loud = rms > opts.floor
        if is_whole:
            whole += 1
            if loud:
                active += 1
                run = 0
            else:
                silent.append(t)
                if run == 0:
                    run_at = t
                run += 1
                if run > longest:
                    longest, longest_at = run, run_at
        if not opts.quiet:
            bar = "#" * min(60, int(rms / 150))
            mark = "" if loud else "  silent"
            part = "" if is_whole else f"  ({n / rate:.2f} s)"
            print(f"{t:8.1f} s  rms {rms:7.0f}  peak {peak:5d}  clip {clip:5d}{mark}{part}  {bar}")
        rows += 1
        at += n

    if total == 0:
        print(f"wavstats: nothing between {opts.start} s and the end ({length:.1f} s)")
        return 2
    active_frac = active / whole if whole else 0.0
    clip_frac = clipped / total
    shown = ", ".join(f"{t:.0f}" for t in silent[:20]) + (", ..." if len(silent) > 20 else "")
    print(f"window {first / rate:.1f} .. {at / rate:.1f} s: {whole} whole seconds, floor rms {opts.floor:g}")
    print(f"silent seconds: {len(silent)}" + (f" (at {shown})" if silent else ""))
    if longest:
        print(f"longest silent run: {longest} s from {longest_at:.0f} s")
    gaps = zero_runs(bytes(window), channels, max(1, int(opts.gap_ms * rate / 1000)))
    if gaps:
        listed = ", ".join(f"{(first + g) / rate:.3f} s {n * 1000 / rate:.0f} ms" for g, n in gaps[:10])
        print(f"zero runs >= {opts.gap_ms:g} ms: {len(gaps)}, longest {max(n for _, n in gaps) * 1000 / rate:.0f} ms "
              f"({listed}{', ...' if len(gaps) > 10 else ''})")
    else:
        print(f"zero runs >= {opts.gap_ms:g} ms: 0")
    print(f"active fraction {active_frac:.4f} ({active}/{whole}), clipping fraction {clip_frac:.6f} "
          f"({clipped}/{total} samples)")
    checks = []
    if opts.min_active_frac is not None:
        checks.append(active_frac >= opts.min_active_frac)
    if opts.max_clip_frac is not None:
        checks.append(clip_frac <= opts.max_clip_frac)
    if not checks:
        print("INFO")
        return 0
    limits = []
    if opts.min_active_frac is not None:
        limits.append(f"active >= {opts.min_active_frac:g}")
    if opts.max_clip_frac is not None:
        limits.append(f"clip <= {opts.max_clip_frac:g}")
    ok = all(checks)
    print(("PASS" if ok else "FAIL") + f" ({', '.join(limits)})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
