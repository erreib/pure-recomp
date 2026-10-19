#!/usr/bin/env python3
"""Compare two frames with a tolerance, or check that a region of one frame has something drawn in it.

  tools/imgdiff.py A B [--tol 24] [--max-frac 0.02] [--mask mask.png] [--region x,y,w,h] [--out diff.png] [--json]
  tools/imgdiff.py A [B] --min-variance V [--region x,y,w,h] [--json]
  tools/imgdiff.py --selftest

A and B are PNG (8-bit grey, grey+alpha, RGB, RGBA) or BMP (24/32-bit) files; alpha is dropped and grey becomes
RGB. When the sizes differ, both are resized to 480x272 by nearest neighbour (960x544 captures against 480x272
PPSSPP references); same-size frames are compared as they are. A pixel differs when any channel differs by more
than --tol. PASS (exit 0) when differing / total is at most --max-frac, FAIL (exit 1) otherwise; bad input exits 2.
--mask: pixels that are black in the mask (every channel below 128) are ignored; the mask is resized to the
comparison size. --region x,y,w,h is in PSP screen pixels (480x272) and is scaled to the frame being measured;
without --min-variance it limits the comparison to that rectangle. --min-variance V: no comparison; PASS when the
largest per-channel variance of A inside the region (whole frame without --region) is at least V. --out writes a
diff image: differing pixels in red over A dimmed to a third. --json prints one JSON object instead of the text line.
"""
import argparse, contextlib, io, json, os, random, struct, sys, tempfile, time, zlib
from operator import and_, itemgetter, or_, sub

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png  # noqa: E402  (tools/png.py)

PSP_W, PSP_H = 480, 272
_SQUARES = [v * v for v in range(256)]
_DIM = bytes(v // 3 for v in range(256))
_TO_255 = bytes([0, 255]) + bytes(254)      # flag 1 -> 255
_TO_KEEP = bytes([255, 0]) + bytes(254)     # flag 1 -> 0, flag 0 -> 255
_MASK_ON = bytes(v >= 128 for v in range(256))


def load_rgb(path):
    """(width, height, RGB bytes) from a PNG or BMP file, whatever its channel count."""
    with open(path, "rb") as f:
        magic = f.read(8)
    if magic == png.PNG_SIGNATURE:
        w, h, c, data = png.read_png(path)
    elif magic[:2] == b"BM":
        w, h, c, data = png.read_bmp(path)
    else:
        raise ValueError(f"{path}: neither PNG nor BMP")
    if c == 3:
        return w, h, data
    out = bytearray(w * h * 3)
    if c == 4:
        for k in range(3):
            out[k::3] = data[k::4]
    else:                                   # grey or grey+alpha
        grey = data[0::c]
        for k in range(3):
            out[k::3] = grey
    return w, h, bytes(out)


def resize_nn(w, h, data, dw, dh):
    """Nearest-neighbour resize of RGB bytes from w x h to dw x dh (source pixel floor(x * w / dw))."""
    if (w, h) == (dw, dh):
        return data
    pick = itemgetter(*[(x * w // dw) * 3 + k for x in range(dw) for k in range(3)])
    stride = w * 3
    rows = []
    for y in range(dh):
        sy = y * h // dh
        rows.append(bytes(pick(data[sy * stride:(sy + 1) * stride])))
    return b"".join(rows)


def scale_region(region, w, h):
    """PSP-screen rectangle (x, y, w, h) -> clamped pixel box (x0, y0, x1, y1) in a w x h frame."""
    x, y, rw, rh = region
    x0, y0 = min(w, x * w // PSP_W), min(h, y * h // PSP_H)
    x1, y1 = min(w, (x + rw) * w // PSP_W), min(h, (y + rh) * h // PSP_H)
    if x1 <= x0 or y1 <= y0:
        raise ValueError(f"region {x},{y},{rw},{rh} is empty in a {w}x{h} frame")
    return x0, y0, x1, y1


def _flags_int(flags):
    return int.from_bytes(flags, "big")


def _any_channel(per_byte):
    """Per-byte 0/1 flags of an RGB image -> big int with one 0/1 byte per pixel (1 when any channel is set)."""
    return _flags_int(per_byte[0::3]) | _flags_int(per_byte[1::3]) | _flags_int(per_byte[2::3])


def _diff_table(tol):
    """Indexed by a - b (negative indices wrap): 1 when |a - b| > tol."""
    table = bytearray(512)
    for d in range(256):
        table[d] = d > tol
        table[-d] = d > tol
    return bytes(table)


def compare(opts):
    wa, ha, a = load_rgb(opts.a)
    wb, hb, b = load_rgb(opts.b)
    resized = (wa, ha) != (wb, hb)
    if resized:
        w, h = PSP_W, PSP_H
        a, b = resize_nn(wa, ha, a, w, h), resize_nn(wb, hb, b, w, h)
    else:
        w, h = wa, ha
    n = w * h
    keep = None                              # big int, one 0/1 byte per pixel; None = every pixel
    if opts.mask:
        wm, hm, m = load_rgb(opts.mask)
        keep = _any_channel(resize_nn(wm, hm, m, w, h).translate(_MASK_ON))
    box = None
    if opts.region:
        box = scale_region(opts.region, w, h)
        x0, y0, x1, y1 = box
        row = bytes(x0) + b"\x01" * (x1 - x0) + bytes(w - x1)
        inside = _flags_int(bytes(w * y0) + row * (y1 - y0) + bytes(w * (h - y1)))
        keep = inside if keep is None else keep & inside
    differ = _any_channel(bytes(map(_diff_table(opts.tol).__getitem__, map(sub, a, b))))
    if keep is not None:
        differ &= keep
    total = n if keep is None else keep.bit_count()
    if total == 0:
        raise ValueError("the mask and region leave no pixels to compare")
    differing = differ.bit_count()
    fraction = differing / total
    if opts.out:
        flags = differ.to_bytes(n, "big")
        dim = a.translate(_DIM)
        red, clear = flags.translate(_TO_255), flags.translate(_TO_KEEP)
        out = bytearray(dim)
        out[0::3] = bytes(map(or_, dim[0::3], red))
        out[1::3] = bytes(map(and_, dim[1::3], clear))
        out[2::3] = bytes(map(and_, dim[2::3], clear))
        png.write_png(opts.out, w, h, 3, bytes(out))
    return {"result": "PASS" if fraction <= opts.max_frac else "FAIL", "mode": "compare", "a": opts.a, "b": opts.b,
            "width": w, "height": h, "fraction": fraction, "differing": differing, "total": total, "tol": opts.tol,
            "max_frac": opts.max_frac, "resized": resized, "a_size": [wa, ha], "b_size": [wb, hb],
            "mask": opts.mask, "region": list(opts.region) if opts.region else None,
            "pixel_region": list(box) if box else None, "out": opts.out}



def compare_files(a, b, tol, max_frac, diff=None, mask=None, region=None):
    """compare() on two files without the command line's namespace: the result dict (task 094: the one call the
    checks that compare captures in Python make; diff is --out, region a PSP-screen (x, y, w, h))."""
    return compare(argparse.Namespace(a=a, b=b, tol=tol, max_frac=max_frac, mask=mask, region=region, out=diff))


class NotScaled(ValueError):
    """A capture whose size is not S times 480x272 (reduce_centres without a scale)."""


def reduce_centres(path, reduced, scale=None):
    """The capture at path reduced to 480x272 by the centre pixel of each S x S block, (x S + S/2, y S + S/2): the
    backend's rule for guest memory (task 066), by which tools/scale_check.sh, texture_check.sh, sprite_check.sh and
    sprite_pack.sh compare a capture at internal scale S with the 1x picture (task 094: one copy of the four). Written
    to `reduced` as a PNG. S is scale, or without one the capture's width over 480, which must then be S times
    480x272 (NotScaled otherwise). Returns S."""
    w, h, rgb = load_rgb(path)
    if scale is None:
        scale = w // PSP_W
        if scale < 1 or w != PSP_W * scale or h != PSP_H * scale:
            raise NotScaled(f"{w}x{h} is not a multiple of 480x272")
    half = scale // 2
    rows = []
    for y in range(PSP_H):
        start = ((y * scale + half) * w + half) * 3
        line = rgb[start:start + (w - half) * 3]
        row = bytearray(PSP_W * 3)
        for k in range(3):
            row[k::3] = line[k::scale * 3][:PSP_W]
        rows.append(bytes(row))
    png.write_png(reduced, PSP_W, PSP_H, 3, b"".join(rows))
    return scale

def variance(opts):
    w, h, a = load_rgb(opts.a)
    box = scale_region(opts.region, w, h) if opts.region else (0, 0, w, h)
    x0, y0, x1, y1 = box
    pixels = b"".join(a[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, y1))
    n = (x1 - x0) * (y1 - y0)
    var = []
    for k in range(3):
        ch = pixels[k::3]
        s, sq = sum(ch), sum(map(_SQUARES.__getitem__, ch))
        var.append((n * sq - s * s) / (n * n))
    return {"result": "PASS" if max(var) >= opts.min_variance else "FAIL", "mode": "variance", "a": opts.a,
            "width": w, "height": h, "region": list(opts.region) if opts.region else None,
            "pixel_region": list(box), "variance": var, "max_variance": max(var), "min_variance": opts.min_variance}


def evaluate(opts):
    return variance(opts) if opts.min_variance is not None else compare(opts)


def report(res, as_json):
    if as_json:
        print(json.dumps(res))
        return
    if res["mode"] == "variance":
        where = "frame" if res["region"] is None else "region " + ",".join(map(str, res["region"]))
        v = "/".join(f"{x:.1f}" for x in res["variance"])
        print(f"{res['result']} variance R/G/B {v} (max {res['max_variance']:.1f}, need {res['min_variance']:g}) "
              f"in {where} of {res['a']} ({res['width']}x{res['height']})")
        return
    size = f"{res['width']}x{res['height']}"
    if res["resized"]:
        size += " (resized from {}x{} and {}x{})".format(*res["a_size"], *res["b_size"])
    print(f"{res['result']} fraction {res['fraction']:.6f} ({res['differing']}/{res['total']} pixels differ by more "
          f"than {res['tol']}, limit {res['max_frac']:g}) at {size}")


def _region(text):
    try:
        x, y, w, h = (int(v) for v in text.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError(f"region must be x,y,w,h integers, not {text!r}")
    if x < 0 or y < 0 or w <= 0 or h <= 0:
        raise argparse.ArgumentTypeError(f"region {text!r} needs x, y >= 0 and w, h > 0")
    return x, y, w, h


def parse(argv):
    p = argparse.ArgumentParser(prog="imgdiff.py", description=__doc__.split("\n\n")[0])
    p.add_argument("a", nargs="?", help="frame under test (PNG or BMP)")
    p.add_argument("b", nargs="?", help="reference frame (PNG or BMP)")
    p.add_argument("--tol", type=int, default=24, help="per-channel tolerance, default 24")
    p.add_argument("--max-frac", type=float, default=0.02, help="largest passing fraction, default 0.02")
    p.add_argument("--mask", help="image whose black pixels are ignored")
    p.add_argument("--region", type=_region, help="x,y,w,h in 480x272 PSP screen pixels")
    p.add_argument("--min-variance", type=float, help="PASS when A's region varies at least this much")
    p.add_argument("--out", help="write a diff PNG (red = differing)")
    p.add_argument("--json", action="store_true", help="print one JSON object")
    p.add_argument("--selftest", action="store_true", help="run the built-in self-test")
    opts = p.parse_args(argv)
    if opts.selftest:
        return opts
    if not opts.a:
        p.error("A is required")
    if opts.min_variance is None and not opts.b:
        p.error("B is required unless --min-variance is given")
    if opts.min_variance is not None and (opts.mask or opts.out):
        p.error("--mask and --out apply to comparisons, not to --min-variance")
    return opts


def main(argv=None):
    opts = parse(argv)
    if opts.selftest:
        return selftest()
    try:
        res = evaluate(opts)
    except (OSError, ValueError) as e:
        print(f"imgdiff: error: {e}", file=sys.stderr)
        return 2
    report(res, opts.json)
    return 0 if res["result"] == "PASS" else 1


# ---- self-test ----------------------------------------------------------------------------------------------------

def _write_bmp(path, w, h, pixels, channels, bits, top_down=False, v5=False):
    """Test writer: 24-bit like the framework, 32-bit BI_RGB, or 32-bit V5 BI_BITFIELDS (BGRA)."""
    step, stride = bits // 8, (w * bits + 31) // 32 * 4
    body = bytearray(stride * h)
    for i, y in enumerate(range(h) if top_down else range(h - 1, -1, -1)):
        px = pixels[y * w * channels:(y + 1) * w * channels]
        for k, src in enumerate((2, 1, 0, 3)[:step]):
            body[i * stride + k:i * stride + w * step:step] = px[src::channels] if src < channels else b"\xff" * w
    hsize = 124 if v5 else 40
    info = struct.pack("<IiiHHIIiiII", hsize, w, -h if top_down else h, 1, bits, 3 if v5 else 0, len(body),
                       2835, 2835, 0, 0)
    if v5:
        info += struct.pack("<IIII", 0xFF0000, 0xFF00, 0xFF, 0xFF000000) + bytes(hsize - 56)
    with open(path, "wb") as f:
        f.write(b"BM" + struct.pack("<IHHI", 14 + hsize + len(body), 0, 0, 14 + hsize) + info + body)


def _write_filtered_png(path, w, h, channels, data):
    """Test writer: row y uses PNG filter type y % 5, so read_png has to undo all five."""
    stride, rows, prev = w * channels, [], bytes(w * channels)
    for y in range(h):
        cur, ft = data[y * stride:(y + 1) * stride], y % 5
        row = bytearray([ft])
        for i in range(stride):
            a = cur[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ft == 0: pred = 0
            elif ft == 1: pred = a
            elif ft == 2: pred = b
            elif ft == 3: pred = (a + b) // 2
            else:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
            row.append((cur[i] - pred) & 255)
        rows.append(bytes(row))
        prev = cur
    ihdr = struct.pack(">IIBBBBB", w, h, 8, {1: 0, 2: 4, 3: 2, 4: 6}[channels], 0, 0, 0)
    with open(path, "wb") as f:
        f.write(png.PNG_SIGNATURE + png._chunk(b"IHDR", ihdr) + png._chunk(b"IDAT", zlib.compress(b"".join(rows)))
                + png._chunk(b"IEND", b""))


def selftest():
    start = time.time()
    failures = []

    def check(name, ok, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{': ' + detail if detail else ''}")
        if not ok:
            failures.append(name)

    def run(*argv):
        return evaluate(parse(list(argv)))

    W, H = PSP_W, PSP_H
    rng = random.Random(0x5EED)
    base = rng.randbytes(W * H * 3)
    with tempfile.TemporaryDirectory() as tmp:
        path = lambda name: os.path.join(tmp, name)
        png.write_png(path("a.png"), W, H, 3, base)
        png.write_png(path("a_copy.png"), W, H, 3, base)
        check("png write/read round trip", png.read_png(path("a.png")) == (W, H, 3, base))

        r = run(path("a.png"), path("a_copy.png"))
        check("identical frames", r["fraction"] == 0.0 and r["result"] == "PASS", f"fraction {r['fraction']}")

        qw, qh, shift = W // 2, H // 2, 7          # top-left quadrant moved 7 px right, wrapping inside it
        moved = bytearray(base)
        for y in range(qh):
            row = base[y * W * 3:(y * W + qw) * 3]
            moved[y * W * 3:(y * W + qw) * 3] = row[-shift * 3:] + row[:-shift * 3]
        png.write_png(path("b.png"), W, H, 3, bytes(moved))
        r = run(path("a.png"), path("b.png"), "--out", path("diff.png"))
        check("one quadrant shifted", abs(r["fraction"] - 0.25) <= 0.01 and r["result"] == "FAIL",
              f"fraction {r['fraction']:.4f}")
        dw, dh, _, diff = png.read_png(path("diff.png"))
        reds = sum(1 for i in range(0, len(diff), 3) if diff[i:i + 3] == b"\xff\x00\x00")
        check("diff image marks differing pixels red", (dw, dh) == (W, H) and reds == r["differing"],
              f"{reds} red, {r['differing']} differing")

        mask = bytearray(b"\xff" * (W * H))
        for y in range(qh):
            mask[y * W:y * W + qw] = bytes(qw)
        png.write_png(path("mask.png"), W, H, 1, bytes(mask))
        r = run(path("a.png"), path("b.png"), "--mask", path("mask.png"))
        check("mask hides the shifted quadrant", r["fraction"] == 0.0 and r["total"] == W * H - qw * qh)
        r = run(path("a.png"), path("b.png"), "--region", f"{qw},0,{qw},{qh}")
        check("region on an untouched quadrant", r["fraction"] == 0.0 and r["total"] == qw * qh)

        big = resize_nn(W, H, base, 2 * W, 2 * H)
        _write_bmp(path("big.bmp"), 2 * W, 2 * H, big, 3, 24)
        r = run(path("big.bmp"), path("a.png"))
        check("960x544 BMP against 480x272 PNG", r["resized"] and r["fraction"] == 0.0 and (r["width"], r["height"])
              == (W, H))

        odd_w, odd_h = 37, 5                       # 111-byte rows padded to 112
        odd = rng.randbytes(odd_w * odd_h * 3)
        odd_rgba = rng.randbytes(odd_w * odd_h * 4)
        _write_bmp(path("odd24.bmp"), odd_w, odd_h, odd, 3, 24)
        _write_bmp(path("odd32.bmp"), odd_w, odd_h, odd, 3, 32, top_down=True)
        _write_bmp(path("odd32a.bmp"), odd_w, odd_h, odd_rgba, 4, 32, v5=True)
        check("bmp round trip 24-bit bottom-up, padded rows", png.read_bmp(path("odd24.bmp")) == (odd_w, odd_h, 3, odd))
        check("bmp round trip 32-bit top-down", png.read_bmp(path("odd32.bmp")) == (odd_w, odd_h, 3, odd))
        check("bmp round trip 32-bit bitfields with alpha",
              png.read_bmp(path("odd32a.bmp")) == (odd_w, odd_h, 4, odd_rgba))
        _write_bmp(path("a.bmp"), W, H, base, 3, 24)
        r = run(path("a.bmp"), path("a.png"))
        check("bmp against png of the same pixels", r["fraction"] == 0.0 and not r["resized"])

        ok = True
        for ch in (1, 2, 3, 4):
            px = rng.randbytes(odd_w * 10 * ch)
            _write_filtered_png(path(f"f{ch}.png"), odd_w, 10, ch, px)
            ok = ok and png.read_png(path(f"f{ch}.png")) == (odd_w, 10, ch, px)
        check("png filter types 0-4, 1 to 4 channels", ok)
        with open(path("deep.png"), "wb") as f:
            f.write(png.PNG_SIGNATURE + png._chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 16, 2, 0, 0, 0))
                    + png._chunk(b"IEND", b""))
        try:
            png.read_png(path("deep.png"))
            check("16-bit png rejected", False)
        except ValueError as e:
            check("16-bit png rejected with IHDR fields", "bit_depth=16" in str(e))

        half = bytearray(W * H * 3)                # left half black, right half noise
        for y in range(H):
            half[(y * W + qw) * 3:(y + 1) * W * 3] = base[(y * W + qw) * 3:(y + 1) * W * 3]
        png.write_png(path("half.png"), W, H, 3, bytes(half))
        r = run(path("half.png"), "--region", "20,20,100,100", "--min-variance", "50")
        check("variance on a flat region fails", r["result"] == "FAIL", f"max {r['max_variance']:.1f}")
        r = run(path("half.png"), "--region", "300,20,100,100", "--min-variance", "50")
        check("variance on a drawn region passes", r["result"] == "PASS", f"max {r['max_variance']:.1f}")

        quad = bytearray(4 * W * 4 * H * 3)         # a 4x capture whose block centres (2, 2) hold the 1x picture
        for y in range(H):
            for x in range(W):
                at = ((4 * y + 2) * 4 * W + 4 * x + 2) * 3
                quad[at:at + 3] = base[(y * W + x) * 3:(y * W + x) * 3 + 3]
        png.write_png(path("quad.png"), 4 * W, 4 * H, 3, bytes(quad))
        s = reduce_centres(path("quad.png"), path("quad_r.png"))
        r = compare_files(path("quad_r.png"), path("a.png"), 0, 0.0)
        check("reduce_centres takes each block's centre pixel", s == 4 and r["fraction"] == 0.0 and not r["resized"])
        try:
            reduce_centres(path("odd24.bmp"), path("odd_r.png"))
            check("reduce_centres refuses a size not S x 480x272", False)
        except NotScaled:
            check("reduce_centres refuses a size not S x 480x272", True)

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = main([path("a.png"), path("b.png"), "--json"])
        res = json.loads(buf.getvalue())
        check("cli --json and exit code", rc == 1 and {"width", "height", "fraction", "differing", "total"} <= set(res))

    elapsed = time.time() - start
    check("under 2 s", elapsed < 2.0, f"{elapsed:.2f} s")
    if failures:
        print(f"FAIL selftest: {', '.join(failures)}")
        return 1
    print(f"PASS selftest ({elapsed:.2f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
