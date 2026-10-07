#!/usr/bin/env python3
"""Two 16-bit PCM WAVs side by side: per-second activity, the longest silences, peaks and clipping (task 041).

  tools/audio_compare.py A.wav B.wav [--from S] [--from-b S] [--seconds N] [--floor RMS] [--block-ms MS]
                         [--top N] [--quiet] [--detail S:E]
  tools/audio_compare.py A.wav B.wav --locate T:LEN:FROM:TO
  tools/audio_compare.py --selftest

Made to compare the port's capture (PURE_AUDIO_WAV, the mix or one channel) with PPSSPP's audio dump
(tools/ppsspp/ppsspp_ctl.py run --dump-audio) of the same route. The two start at different moments, so each file
has its own window start: --from S for A, --from-b S for B (default: the same as --from); --seconds N is the window
length (default: as long as the shorter file allows). Times in the table are from the window start; the silences are
listed with both that time and the time in the file.

Prints, for every whole second of the window, each file's RMS, peak and clipped samples (both sides together, int16
scale), `-` after a file's figures when the second is silent (RMS at or under --floor, default 100, about -50 dBFS,
as tools/wavstats.py counts it) and `<>` at the end of a row where one file is active and the other silent. Then a
summary for each file: the active seconds, the peak (and in dBFS), the clipped samples (at -32768 or 32767) and
their fraction, and its --top (default 5) longest silences: runs of --block-ms (default 10 ms) blocks whose RMS is at
or under the floor, with `all zero` when every sample of the run is 0 (a dropout or digital silence, rather than a
quiet passage). --quiet leaves out the per-second rows. --detail S:E adds rows of ten blocks (100 ms by default)
from S to E seconds after the window starts, each file's RMS and `z` when every sample of the row is 0: the
sample-level view of a gap. Exit 0, or 2 on bad input.

--locate T:LEN:FROM:TO finds where B's stretch from T to T+LEN seconds (in B's file) occurs in A between FROM and TO
(in A's file), by normalised cross-correlation of the two files' mono sum (8 times decimated first, then at the full
rate around the best match), and prints the time in A, the offset (A minus B) and the correlation (1 is identical).
It finds a channel inside a mix: the port's music channel (PURE_AUDIO_WAV's ch2) in PPSSPP's dump, where the effects
are louder than the music, matches at 0.3 to 0.7; the same offset at two times shows the two played the same samples
in between. About a second per 4 s searched with LEN 2.

--selftest writes two WAVs with known gaps and clipping to a temporary directory, runs the analysis on them and
checks the figures it prints against the ones the files were made with: PASS (exit 0) or FAIL (exit 1). Pure Python
(array + math.sumprod), about a second per minute of stereo audio and file.
"""
import argparse
import math
import os
import sys
import tempfile
import wave
from array import array


def parse(argv):
    p = argparse.ArgumentParser(prog="audio_compare.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("a", nargs="?")
    p.add_argument("b", nargs="?")
    p.add_argument("--from", dest="start", type=float, default=0.0)
    p.add_argument("--from-b", dest="start_b", type=float)
    p.add_argument("--seconds", type=float)
    p.add_argument("--floor", type=float, default=100.0)
    p.add_argument("--block-ms", type=float, default=10.0)
    p.add_argument("--top", type=int, default=5)
    p.add_argument("--quiet", action="store_true")
    p.add_argument("--detail", metavar="S:E")
    p.add_argument("--locate", metavar="T:LEN:FROM:TO")
    p.add_argument("--selftest", action="store_true")
    opts = p.parse_args(argv)
    if not opts.selftest and (opts.a is None or opts.b is None):
        p.error("give two WAV files, or --selftest")
    return opts


class Track:
    """One file's window: per-second and per-block figures, made in one pass."""

    def __init__(self, path, start, seconds, floor, block_ms):
        self.path = path
        try:
            source = wave.open(path, "rb")
        except (OSError, EOFError, wave.Error) as e:
            raise ValueError(f"cannot read {path}: {e}")
        with source:
            self.rate, self.channels, width, frames = (source.getframerate(), source.getnchannels(),
                                                       source.getsampwidth(), source.getnframes())
            if width != 2:
                raise ValueError(f"{path} is {8 * width}-bit; only 16-bit PCM is read")
            self.length = frames / self.rate
            self.first = min(frames, max(0, int(round(start * self.rate))))
            last = frames if seconds is None else min(frames, self.first + int(round(seconds * self.rate)))
            source.setpos(self.first)
            self.block = max(1, int(round(block_ms * self.rate / 1000)))
            self.seconds = []     # (rms, peak, clipped) per whole second
            self.blocks = []      # (rms, all_zero) per block
            self.peak = self.clipped = self.total = 0
            at = self.first
            while at < last:
                n = min(self.rate, last - at)
                samples = array("h")
                samples.frombytes(source.readframes(n))
                if sys.byteorder != "little":
                    samples.byteswap()
                if not samples:
                    break
                got = len(samples) // self.channels
                clip = samples.count(32767) + samples.count(-32768)
                peak = max(max(samples), -min(samples))
                self.peak = max(self.peak, peak)
                self.clipped += clip
                self.total += len(samples)
                if got == self.rate:
                    self.seconds.append((math.sqrt(math.sumprod(samples, samples) / len(samples)), peak, clip))
                step = self.block * self.channels
                for i in range(0, len(samples) - step + 1, step):
                    part = samples[i:i + step]
                    energy = math.sumprod(part, part)
                    self.blocks.append((math.sqrt(energy / len(part)), energy == 0))
                at += got
            self.end = at
        self.floor = floor
        self.block_ms = self.block * 1000 / self.rate

    def active(self):
        return sum(1 for rms, _, _ in self.seconds if rms > self.floor)

    def silences(self):
        """(first block, blocks, all zero) of each run of blocks at or under the floor, longest first."""
        runs, start, zero = [], None, True
        for i, (rms, all_zero) in enumerate(self.blocks + [(math.inf, False)]):
            if rms <= self.floor:
                if start is None:
                    start, zero = i, True
                zero = zero and all_zero
            elif start is not None:
                runs.append((start, i - start, zero))
                start = None
        return sorted(runs, key=lambda r: (-r[1], r[0]))

    def window_start(self):
        return self.first / self.rate

    def describe_silence(self, run):
        first, count, zero = run
        rel = first * self.block_ms / 1000
        return (f"{count * self.block_ms:.0f} ms at +{rel:.2f} s ({self.window_start() + rel:.2f} s)"
                f"{' all zero' if zero else ''}")


def read_mono(path, start, seconds):
    """(rate, the mono sum (L+R)/2 as floats) of `seconds` from `start`."""
    try:
        with wave.open(path, "rb") as w:
            rate, channels = w.getframerate(), w.getnchannels()
            if w.getsampwidth() != 2:
                raise ValueError(f"{path}: only 16-bit PCM is read")
            w.setpos(min(w.getnframes(), max(0, int(round(start * rate)))))
            data = array("h")
            data.frombytes(w.readframes(int(round(seconds * rate))))
    except (OSError, EOFError, wave.Error) as e:
        raise ValueError(f"cannot read {path}: {e}")
    if sys.byteorder != "little":
        data.byteswap()
    if channels == 1:
        return rate, [float(v) for v in data]
    return rate, [(data[i] + data[i + 1]) / 2 for i in range(0, len(data) - 1, channels)]


def correlate(hay, tpl, offsets):
    """Normalised cross-correlation of tpl against hay at each offset."""
    n = len(tpl)
    norm = math.sqrt(math.sumprod(tpl, tpl)) or 1.0
    out = []
    for o in offsets:
        part = hay[o:o + n]
        energy = math.sumprod(part, part)
        out.append(math.sumprod(part, tpl) / (norm * math.sqrt(energy)) if energy > 0 else 0.0)
    return out


def locate(path_a, path_b, spec):
    """Where B's [T, T+LEN) occurs in A's [FROM, TO): (time in A, correlation)."""
    t, length, frm, to = (float(v) for v in spec.split(":"))
    rate, tpl = read_mono(path_b, t, length)
    rate_a, hay = read_mono(path_a, frm, to - frm + length)
    if rate != rate_a or len(tpl) < 64 or len(hay) < len(tpl):
        raise ValueError("--locate needs two files at one rate, a template and a search range inside the files")
    k = 8
    dec = lambda x: [sum(x[i:i + k]) / k for i in range(0, len(x) - k + 1, k)]
    coarse_tpl, coarse_hay = dec(tpl), dec(hay)
    coarse = correlate(coarse_hay, coarse_tpl, range(len(coarse_hay) - len(coarse_tpl) + 1))
    best = max(range(len(coarse)), key=lambda i: coarse[i]) * k
    near = range(max(0, best - 2 * k), min(len(hay) - len(tpl), best + 2 * k) + 1)
    fine = correlate(hay, tpl, near)
    j = max(range(len(fine)), key=lambda i: fine[i])
    return frm + near[j] / rate, fine[j]


def dbfs(peak):
    return "-inf" if peak == 0 else f"{round(20 * math.log10(peak / 32768), 1) + 0.0:.1f}"


def report(a, b, opts, out=print):
    out(f"A {a.path}: {a.length:.1f} s, {a.rate} Hz, {a.channels} channel(s), window from {a.window_start():.2f} s")
    out(f"B {b.path}: {b.length:.1f} s, {b.rate} Hz, {b.channels} channel(s), window from {b.window_start():.2f} s")
    rows = max(len(a.seconds), len(b.seconds))
    if not opts.quiet:
        out(f"{'t s':>7} | {'A rms':>6} {'peak':>5} {'clip':>5}   | {'B rms':>6} {'peak':>5} {'clip':>5}")
        for k in range(rows):
            cells, states = [], []
            for t in (a, b):
                if k < len(t.seconds):
                    rms, peak, clip = t.seconds[k]
                    loud = rms > t.floor
                    states.append(loud)
                    cells.append(f"{rms:6.0f} {peak:5d} {clip:5d} {' ' if loud else '-'}")
                else:
                    cells.append(f"{'':6} {'':5} {'':5}  ")
            mark = "  <>" if len(states) == 2 and states[0] != states[1] else ""
            out(f"{k:7d} | {cells[0]} | {cells[1]}{mark}")
    for name, t in (("A", a), ("B", b)):
        whole = len(t.seconds)
        active = t.active()
        out(f"{name}: {whole} whole seconds, active {active} ({active / whole if whole else 0:.3f}), "
            f"peak {t.peak} ({dbfs(t.peak)} dBFS), clipped {t.clipped} of {t.total} samples "
            f"({t.clipped / t.total if t.total else 0:.6f})")
        runs = t.silences()[:opts.top]
        listed = "; ".join(t.describe_silence(r) for r in runs) if runs else "none"
        out(f"{name}: longest silences (blocks of {t.block_ms:.0f} ms at rms <= {t.floor:g}): {listed}")
    if getattr(opts, "detail", None):
        start, _, end = opts.detail.partition(":")
        first, last = int(float(start) * 1000 / a.block_ms), int(float(end) * 1000 / a.block_ms)
        out(f"{'+s':>8} | {'A rms':>6}   | {'B rms':>6}   (rows of 10 blocks of {a.block_ms:.0f} ms)")
        for k in range(first, last, 10):
            cells = []
            for t in (a, b):
                part = t.blocks[k:k + 10]
                if not part:
                    cells.append(f"{'':6}  ")
                    continue
                rms = math.sqrt(sum(r * r for r, _ in part) / len(part))
                cells.append(f"{rms:6.0f} {'z' if all(z for _, z in part) else ' '}")
            out(f"{k * a.block_ms / 1000:8.2f} | {cells[0]} | {cells[1]}")
    differ = sum(1 for k in range(min(len(a.seconds), len(b.seconds)))
                 if (a.seconds[k][0] > a.floor) != (b.seconds[k][0] > b.floor))
    out(f"seconds where one is active and the other silent: {differ}")


# ---------------------------------------------------------------- self test

def write_wav(path, rate, channels, frames):
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        data = array("h", frames)
        if sys.byteorder != "little":
            data.byteswap()
        w.writeframes(data.tobytes())


def tone(rate, seconds, gaps, clip_at=None, clip_count=0, amplitude=8000):
    """Stereo frames of a 440 Hz tone, zero inside each (start, length) gap, clip_count samples at 32767 from clip_at."""
    out = []
    for i in range(int(seconds * rate)):
        t = i / rate
        v = 0 if any(s <= t < s + n for s, n in gaps) else int(amplitude * math.sin(2 * math.pi * 440 * t))
        out += [v, v]
    if clip_at is not None:
        at = int(clip_at * rate) * 2
        out[at:at + clip_count] = [32767] * clip_count
    return out


def selftest():
    rate = 44100
    checks = []
    with tempfile.TemporaryDirectory() as tmp:
        pa, pb = os.path.join(tmp, "a.wav"), os.path.join(tmp, "b.wav")
        # A: 6 s, a 1.5 s gap from 2.0 s and a 0.2 s one from 4.5 s, 10 clipped samples at 1.0 s.
        write_wav(pa, rate, 2, tone(rate, 6.0, [(2.0, 1.5), (4.5, 0.2)], clip_at=1.0, clip_count=10))
        # B: the same 6 s one second later in its file (1 s of silence first), one 0.5 s gap from 2.5 s of the tone.
        write_wav(pb, rate, 2, [0, 0] * rate + tone(rate, 6.0, [(2.5, 0.5)]))
        lines = []
        opts = argparse.Namespace(quiet=False, top=5)
        a = Track(pa, 0.0, None, 100.0, 10.0)
        b = Track(pb, 1.0, None, 100.0, 10.0)
        report(a, b, opts, out=lines.append)
        print("\n".join(lines))
        ra, rb = a.silences(), b.silences()
        checks += [
            ("A has 6 whole seconds, B 6 from its window", len(a.seconds) == 6 and len(b.seconds) == 6),
            ("A's longest silence is 1500 ms at 2.00 s, all zero",
             ra and ra[0][1] * a.block_ms == 1500 and abs(ra[0][0] * a.block_ms - 2000) < 1 and ra[0][2]),
            ("A's second silence is 200 ms at 4.50 s", len(ra) > 1 and ra[1][1] * a.block_ms == 200
             and abs(ra[1][0] * a.block_ms - 4500) < 1),
            ("B's longest silence is 500 ms at +2.50 s (3.50 s in the file)",
             rb and rb[0][1] * b.block_ms == 500 and abs(rb[0][0] * b.block_ms - 2500) < 1
             and abs(b.window_start() + rb[0][0] * b.block_ms / 1000 - 3.5) < 0.001),
            ("A has 10 clipped samples, B none", a.clipped == 10 and b.clipped == 0),
            ("A's peak is 32767, B's the tone's (7999)", a.peak == 32767 and b.peak == 7999),
            # Second 2 (2.0-3.0 s) is all gap in A; B is active (its gap is half of it).
            ("second 2 is silent in A and active in B, the only such row",
             [ln.split("|")[0].strip() for ln in lines if "<>" in ln] == ["2"]),
            ("the summary counts that one row", lines[-1].endswith(": 1")),
        ]
        # --locate: B2 holds A2's noise from 1.0 s on, starting at 0.5 s (B2's t is A2's t + 0.5), under louder noise.
        seed = [12345]

        def noise(n, amp):
            out = []
            for _ in range(n):
                seed[0] = (seed[0] * 1103515245 + 12345) & 0x7FFFFFFF
                out.append(int(amp * ((seed[0] >> 8) / (1 << 22) - 1.0)))
            return out
        base = noise(4 * rate, 3000)
        cover = noise(4 * rate, 6000)
        shifted = [0] * (rate // 2) + base[rate:]
        pa2, pb2 = os.path.join(tmp, "a2.wav"), os.path.join(tmp, "b2.wav")
        write_wav(pa2, rate, 1, base)
        write_wav(pb2, rate, 1, [max(-32768, min(32767, shifted[i] + cover[i])) for i in range(len(shifted))])
        at, score = locate(pa2, pb2, "2.0:0.5:0:3.5")
        print(f"locate: B2 2.0 s found in A2 at {at:.5f} s (ncc {score:.3f})")
        checks.append(("--locate finds a stretch under louder noise to the sample (A2 2.5 s)",
                       abs(at - 2.5) < 0.5 / rate and 0.3 < score < 0.6))
        try:
            Track(os.path.join(tmp, "missing.wav"), 0.0, None, 100.0, 10.0)
            checks.append(("a missing file is refused", False))
        except ValueError:
            checks.append(("a missing file is refused", True))
    ok = True
    for name, good in checks:
        print(f"selftest: {'ok  ' if good else 'FAIL'} {name}")
        ok = ok and bool(good)
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None):
    opts = parse(sys.argv[1:] if argv is None else argv)
    if opts.selftest:
        return selftest()
    if opts.locate:
        try:
            at, score = locate(opts.a, opts.b, opts.locate)
        except ValueError as e:
            print(f"audio_compare: {e}")
            return 2
        t = float(opts.locate.split(":")[0])
        print(f"B {opts.b} at {t:.3f} s is A {opts.a} at {at:.5f} s: offset A - B {at - t:+.5f} s, ncc {score:.3f}")
        return 0
    try:
        a = Track(opts.a, opts.start, opts.seconds, opts.floor, opts.block_ms)
        b = Track(opts.b, opts.start if opts.start_b is None else opts.start_b, opts.seconds, opts.floor,
                  opts.block_ms)
    except ValueError as e:
        print(f"audio_compare: {e}")
        return 2
    if not a.total or not b.total:
        print("audio_compare: a window is empty (past the end of its file?)")
        return 2
    report(a, b, opts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
