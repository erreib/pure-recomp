#!/usr/bin/env python3
"""The sprite upscale against its prototype (task 073, D-018): the port's 4x upscale of a texture, dumped by
PURE_SPRITE_DUMP, against the prototype's maths run on the same texture.

  tools/sprite_proto_check.py DUMP_DIR [--inputs A.png[,B.png...]] [--tol 2]

DUMP_DIR holds what a run with PURE_SPRITE_DUMP=DUMP_DIR wrote: <key>.src.png (the decoded texture the backend
upscaled) and <key>.png (the scaler's output, src/gpu/sprite_upscale.cpp), each texture once. For each pair this runs
the prototype's resample (the planning session's out/fe_tex/upscale_proto.py, its maths copied below: separable
Catmull-Rom 4x on premultiplied RGBA with the alpha over the texture's peak, the colour unpremultiplied, the
smoothstep of half-width 0.22 for a mask-like texture) on <key>.src.png and compares its output with <key>.png, channel
by channel. With --inputs, only the dumped textures whose decoded pixels equal those PNGs (the prototype's own inputs,
which are the game's textures and stay out of the repository) are checked, and an input no dump matches FAILs.
Prints a line per texture (size, mask-like or soft, peak, the largest difference and the pixel it is at, the channel
values over --tol) and `sprite_proto_check: PASS` when every compared texture is within --tol levels per channel
(default 2, the brief's bar), else FAIL. Exit 0 PASS, 1 FAIL, 2 nothing to compare. Pure Python: about 10 s for a
256x128 texture.
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png  # noqa: E402  (tools/png.py)

K = 4


def cr(t):
    """Catmull-Rom weights for the 4 taps at offsets -1, 0, 1, 2 with fraction t (the prototype's cr)."""
    t2, t3 = t * t, t * t * t
    return (-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2)


def resample_1d(rows, n_in, n_out, ch):
    """rows: flat float lists of n_in * ch values -> n_out * ch (the prototype's resample_1d)."""
    taps = []
    for o in range(n_out):
        x = (o + 0.5) / K - 0.5
        i = int(x // 1)
        t = x - i
        w = cr(t)
        taps.append([(min(max(i + d - 1, 0), n_in - 1), w[d]) for d in range(4)])
    out = []
    for r in rows:
        o = [0.0] * (n_out * ch)
        for oi, tp in enumerate(taps):
            base = oi * ch
            for idx, w in tp:
                src = idx * ch
                for c in range(ch):
                    o[base + c] += r[src + c] * w
        out.append(o)
    return out


def upscale(w, h, px):
    """The prototype's upscale of w x h RGBA bytes: (4w x 4h RGBA bytes, mask-like, peak)."""
    peak = max(px[3::4]) or 255
    opaque = sum(1 for i in range(3, len(px), 4) if px[i] == 0 or px[i] >= peak - 1)
    masklike = opaque >= 0.6 * (w * h)
    rows = []
    for y in range(h):
        r = []
        for x in range(w):
            p = (y * w + x) * 4
            a = px[p + 3] / peak
            r += [px[p] * a, px[p + 1] * a, px[p + 2] * a, a]
        rows.append(r)
    rows = resample_1d(rows, w, w * K, 4)
    cols = [[rows[y][x * 4 + c] for y in range(h) for c in range(4)] for x in range(w * K)]
    cols = resample_1d(cols, h, h * K, 4)
    out = bytearray(w * K * h * K * 4)
    e = 0.22
    for x in range(w * K):
        col = cols[x]
        for y in range(h * K):
            pr, pg, pb, a = col[y * 4:y * 4 + 4]
            a = min(max(a, 0.0), 1.0)
            if a > 0.001:
                r, g, b = (min(max(v / a, 0.0), 255.0) for v in (pr, pg, pb))
            else:
                r = g = b = 0.0
            if masklike:
                t = min(max((a - (0.5 - e)) / (2 * e), 0.0), 1.0)
                a = t * t * (3 - 2 * t)
            o = (y * w * K + x) * 4
            out[o], out[o + 1], out[o + 2], out[o + 3] = int(r + 0.5), int(g + 0.5), int(b + 0.5), int(a * peak + 0.5)
    return bytes(out), masklike, peak


def rgba(path):
    w, h, c, data = png.read_png(path)
    if c != 4:
        raise ValueError(f"{path}: {c} channels, not RGBA")
    return w, h, data


def check(name, src, dst, tol):
    """The prototype on src against the port's dst: (passed, the line)."""
    w, h, px = rgba(src)
    ow, oh, port = rgba(dst)
    if (ow, oh) != (w * K, h * K):
        return False, f"{name}: the port's output is {ow}x{oh}, not {w * K}x{h * K}"
    if max(px[3::4]) == 0:
        return True, f"{name}: {w}x{h}, alpha 0 everywhere: the port keeps the colour (sprite_upscale.hpp), not compared"
    t0 = time.time()
    proto, masklike, peak = upscale(w, h, px)
    worst, at, over = 0, None, 0
    for i, (a, b) in enumerate(zip(proto, port)):
        d = abs(a - b)
        if d > tol:
            over += 1
        if d > worst:
            worst, at = d, i
    where = ""
    if at is not None:
        p = at // 4
        x, y, ch = p % ow, p // ow, "RGBA"[at % 4]
        where = f" at ({x},{y}) {ch}: prototype {proto[at]}, port {port[at]}"
    line = (f"{name}: {w}x{h} {'mask-like' if masklike else 'soft'} peak {peak}: largest difference {worst}{where}; "
            f"{over} channel values over {tol} ({time.time() - t0:.1f} s)")
    return worst <= tol, line


def main():
    p = argparse.ArgumentParser(prog="sprite_proto_check.py")
    p.add_argument("dump_dir")
    p.add_argument("--inputs", help="PNG[,PNG...]: check only the dumped textures equal to these")
    p.add_argument("--tol", type=int, default=2)
    opts = p.parse_args()
    keys = sorted(f[:-len(".src.png")] for f in os.listdir(opts.dump_dir) if f.endswith(".src.png"))
    pairs = [(k, os.path.join(opts.dump_dir, k + ".src.png"), os.path.join(opts.dump_dir, k + ".png")) for k in keys
             if os.path.isfile(os.path.join(opts.dump_dir, k + ".png"))]
    failed = False
    if opts.inputs:
        chosen = []
        sources = {k: rgba(s) for k, s, _ in pairs}
        for path in opts.inputs.split(","):
            want = rgba(path)
            match = next((k for k, s, _ in pairs if sources[k] == want), None)
            if match is None:
                print(f"{path}: {want[0]}x{want[1]}, no dumped texture has its pixels: FAIL")
                failed = True
                continue
            chosen.append((f"{os.path.basename(path)} = {match}", os.path.join(opts.dump_dir, match + ".src.png"),
                           os.path.join(opts.dump_dir, match + ".png")))
        pairs = chosen
    if not pairs and not failed:
        print(f"sprite_proto_check: nothing to compare in {opts.dump_dir}")
        return 2
    for name, src, dst in pairs:
        ok, line = check(name, src, dst, opts.tol)
        print(line + ("" if ok else "  FAIL"), flush=True)
        failed |= not ok
    print("sprite_proto_check: FAIL" if failed
          else f"sprite_proto_check: PASS, {len(pairs)} textures within {opts.tol} levels")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
