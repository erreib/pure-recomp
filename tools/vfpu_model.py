#!/opt/homebrew/bin/python3
"""The VFPU's rounding, modelled against PPSSPP's results (task 047).

  vfpu_model.py --selftest            the arithmetic helpers, task 046's example and pspautotests' vector.expected
  vfpu_model.py --check [DIR]         the chosen dot model over every dot sample in DIR (ref/vfpu): exit 0 when it
                                      reproduces all of them, else the failing rows; the transcendental report
  vfpu_model.py --report [DIR]        every candidate model over every sample, per instruction and lane count
  vfpu_model.py --search [DIR]        the parameter grid of the aligned-truncation family (model c)

The samples are tools/vfpu_probe.py's: sites.json and one <ADDR>.csv a site with PPSSPP's source lanes and result
lanes as bit patterns, and <ADDR>.port.csv with the port's results for the same rows (the corpus's own code, run by
`vfpu_probe.py port`). Every model works on integers: a float is (sign, biased exponent, 24-bit significand), a
product of two is exact (48 bits), and each model says where it rounds or truncates. Inputs with a zero exponent
field are zero (the VFPU flushes subnormals, vfpu-docs' introduction), and so are results below the smallest normal.

The dot-product models (n lanes; a vtfm or vmmul result lane is the same n-lane dot of a matrix row and a vector):
  a      each product rounded to float, then summed in lane order with a rounding after each addition
  b      the port: clang's contraction of the framework's C++ (the _ct vdot `s0*t0 + s1*t1 + s2*t2 + s3*t3` is
         fma(s3,t3, fma(s2,t2, fma(s0,t0, s1*t1))); the vtfm and vmmul loops `sum += m*t` are an fma chain from 0)
  exact  the exact sum rounded to nearest once (what the port gives when the fma chain happens not to round)
  c      exact products aligned to the largest product exponent, kept with 23+N fraction bits there, the bits below
         dropped (toward zero on each product's magnitude, or toward minus infinity on the signed value), summed
         exactly, then rounded once (to nearest even, toward zero, or to nearest away); parameters N, the alignment
         reference (the raw exponent sum of the operands, or the product's own normalised exponent), truncation, final
  d1     products rounded to float, summed exactly, rounded once
  d2     products truncated to float, summed exactly, rounded once
  d3     products rounded to float, summed as a tree ((p0+p1)+(p2+p3)) with a rounding after each addition
"""
import argparse, csv, json, math, random, re, struct, sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DIR = ROOT / "ref" / "vfpu"
AUTOTESTS = Path.home() / "dev" / "scratch" / "pspautotests" / "tests" / "cpu" / "vfpu"

DOT_KINDS = ("vdot", "vhdp", "vtfm", "vmmul")
TRANS_KINDS = ("vsin", "vcos", "vrcp", "vrsq", "vsqrt", "vexp2", "vlog2", "vasin", "vnrcp", "vnsin", "vrexp2")

# The rule this task settles on (see docs/fidelity.md, difference 13): model c with these parameters.
CHOSEN = ("c", {"n": 2, "align": "raw", "trunc": "mag", "final": "rne"})


# ------------------------------------------------------------------------------------------- float32 bits

def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def b2f(b):
    return struct.unpack("<f", struct.pack("<I", b & 0xFFFFFFFF))[0]


def unpack(b):
    """(sign, biased exponent, significand with the hidden bit); subnormals are zero (exponent 0, significand 0)."""
    s, e, m = b >> 31, (b >> 23) & 0xFF, b & 0x7FFFFF
    if e == 0:
        return s, 0, 0
    if e == 255:
        return s, 255, m
    return s, e, m | 0x800000


def is_special(b):
    return (b >> 23) & 0xFF == 255


def round_pack(sign, mag, exp2, mode="rne"):
    """Bits of the float nearest (by `mode`) to (-1)^sign * mag * 2^exp2, mag an integer >= 0; results below the
    smallest normal flush to a signed zero, results beyond the largest finite go to infinity."""
    if mag == 0:
        return sign << 31
    shift = mag.bit_length() - 24
    if shift > 0:
        q, r = mag >> shift, mag & ((1 << shift) - 1)
        half = 1 << (shift - 1)
        if mode == "rne":
            if r > half or (r == half and q & 1):
                q += 1
        elif mode == "rna":
            if r >= half:
                q += 1
        elif mode != "rtz":
            raise ValueError(mode)
        if q == 1 << 24:
            q >>= 1
            shift += 1
    else:
        q = mag << -shift
    e = exp2 + shift + 23 + 127
    if e <= 0:
        return sign << 31
    if e >= 255:
        return (sign << 31) | 0x7F800000
    return (sign << 31) | (e << 23) | (q & 0x7FFFFF)


def to_exact(b):
    """(signed integer, exponent) with value integer * 2^exponent, or None for inf/nan."""
    s, e, m = unpack(b)
    if e == 255:
        return None
    if e == 0:
        return 0, 0
    return (-m if s else m), e - 150


def add_exact(terms):
    """Exact sum of (signed int, exp) terms as (signed int, exp)."""
    terms = [t for t in terms if t[0]]
    if not terms:
        return 0, 0
    lo = min(t[1] for t in terms)
    return sum(v << (x - lo) for v, x in terms), lo


def round_exact(v, x, mode="rne", zero_sign=0):
    if v == 0:
        return zero_sign << 31
    return round_pack(1 if v < 0 else 0, abs(v), x, mode)


def fmul(a, b, mode="rne"):
    pa, pb = to_exact(a), to_exact(b)
    if pa is None or pb is None:
        return f2b(b2f(a) * b2f(b))
    return round_exact(pa[0] * pb[0], pa[1] + pb[1], mode, ((a ^ b) >> 31) & 1)


def fadd(a, b, mode="rne"):
    pa, pb = to_exact(a), to_exact(b)
    if pa is None or pb is None:
        return f2b(b2f(a) + b2f(b))
    v, x = add_exact([pa, pb])
    zs = 1 if (a >> 31) and (b >> 31) else 0          # -0 + -0 = -0, every other exact zero is +0
    return round_exact(v, x, mode, zs)


def ffma(a, b, c):
    """round(a * b + c), one rounding (what an arm64 fmadd computes)."""
    pa, pb, pc = to_exact(a), to_exact(b), to_exact(c)
    if pa is None or pb is None or pc is None:
        return f2b(b2f(a) * b2f(b) + b2f(c))
    v, x = add_exact([(pa[0] * pb[0], pa[1] + pb[1]), pc])
    zs = 1 if ((a ^ b) >> 31) and (c >> 31) else 0
    return round_exact(v, x, "rne", zs)


def ulps(a, b):
    """Distance in units in the last place between two finite floats' bit patterns (signed-magnitude order)."""
    def key(x):
        return -(x & 0x7FFFFFFF) if x >> 31 else (x & 0x7FFFFFFF)
    return abs(key(a) - key(b))


# ------------------------------------------------------------------------------------------- dot models

def special_dot(s, t):
    """Inf or NaN among the operands: IEEE products and sums (pspautotests' expectations follow this)."""
    acc = 0.0
    for x, y in zip(s, t):
        acc += b2f(x) * b2f(y)
    if math.isnan(acc):
        return 0x7FC00000
    return f2b(acc) if abs(acc) < float("inf") else (0xFF800000 if acc < 0 else 0x7F800000)


def dot_a(s, t):
    acc = fmul(s[0], t[0])
    for x, y in zip(s[1:], t[1:]):
        acc = fadd(acc, fmul(x, y))
    return acc


def dot_tree(s, t):
    p = [fmul(x, y) for x, y in zip(s, t)] + [0] * (4 - len(s))
    return fadd(fadd(p[0], p[1]), fadd(p[2], p[3]))


def dot_port_ct(s, t):
    """The _ct vdot's contraction: fma(s3,t3, fma(s2,t2, fma(s0,t0, s1*t1))) over the four-lane view."""
    s, t = list(s) + [0] * (4 - len(s)), list(t) + [0] * (4 - len(t))
    acc = fmul(s[1], t[1])
    acc = ffma(s[0], t[0], acc)
    acc = ffma(s[2], t[2], acc)
    return ffma(s[3], t[3], acc)


def dot_port_loop(s, t):
    """`float sum = 0; sum += m[c] * t[c]` contracted: an fma chain from +0 (vtfm, vmmul)."""
    acc = 0
    for x, y in zip(s, t):
        acc = ffma(x, y, acc)
    return acc


def dot_exact(s, t, mode="rne"):
    terms = []
    for x, y in zip(s, t):
        px, py = to_exact(x), to_exact(y)
        terms.append((px[0] * py[0], px[1] + py[1]))
    v, e = add_exact(terms)
    return round_exact(v, e, mode)


def dot_round_products(s, t, prod_mode):
    terms = [to_exact(fmul(x, y, prod_mode)) for x, y in zip(s, t)]
    v, e = add_exact(terms)
    return round_exact(v, e, "rne")


def dot_c(s, t, n=2, align="raw", trunc="mag", final="rne"):
    """Model c. Each product: sign, exponent E (raw: ea + eb - 127; norm: one more when the significand product
    reaches 2), significand product P (48 bits, value P * 2^(E - 127 - 46)). All are aligned to the largest E and
    kept to 23 + n fraction bits there, the rest dropped; the sum is rounded once."""
    prods = []
    for x, y in zip(s, t):
        sx, ex, mx = unpack(x)
        sy, ey, my = unpack(y)
        if ex == 0 or ey == 0:
            continue
        p = mx * my
        e = ex + ey - 127
        prods.append((sx ^ sy, e, p, e + (1 if (align == "norm" and p >> 47) else 0)))
    if not prods:
        return 0
    top = max(q[3] for q in prods)
    total = 0
    for sign, e, p, en in prods:
        # P is in units of 2^(e - 127 - 46); the kept grid is 2^(top - 127 - 23 - n): drop sh bits.
        sh = top - e + 23 - n
        if sh <= 0:
            v = p << -sh
            v = -v if sign else v
        elif trunc == "mag":
            v = p >> sh
            v = -v if sign else v
        else:                             # floor of the signed value (two's complement shift)
            v = (-p if sign else p) >> sh
        total += v
    return round_exact(total, top - 150 - n, final)


MODELS = {
    "a": dot_a,
    "exact": dot_exact,
    "d1": lambda s, t: dot_round_products(s, t, "rne"),
    "d2": lambda s, t: dot_round_products(s, t, "rtz"),
    "d3": dot_tree,
}


def model_fn(name, params=None):
    if name == "c":
        p = params or {}
        return lambda s, t: dot_c(s, t, **p)
    return MODELS[name]


def model_label(name, params=None):
    if name != "c" or not params:
        return name
    return f"c(N={params['n']},{params['align']},{params['trunc']},{params['final']})"


# ------------------------------------------------------------------------------------------- samples

def apply_prefix(v, prefix):
    """A source prefix over a four-lane view (lanes past the encoded length are 0), as the framework applies it."""
    consts = [0.0, 1.0, 2.0, 0.5, 3.0, 1.0 / 3.0, 0.25, 1.0 / 6.0]
    n = len(v)
    src = list(v) + [0] * (4 - n)
    out = []
    for i in range(4):
        lane = (prefix >> (2 * i)) & 3
        ab = (prefix >> (8 + i)) & 1
        cst = (prefix >> (12 + i)) & 1
        neg = (prefix >> (16 + i)) & 1
        if cst:
            x = f2b(consts[lane + (4 if ab else 0)])
        else:
            x = src[lane] if lane < 4 else 0
            if ab:
                x &= 0x7FFFFFFF
        if neg:
            x ^= 0x80000000
        out.append(x)
    return out


def dot_problems(site, row):
    """The n-lane dot products of one sample row: a list of (lane, s vector, t vector, PPSSPP's result bits)."""
    kind = site["kind"]
    ns, nt = len(site["s"]), len(site["t"])
    s, t, d = row[:ns], row[ns:ns + nt], row[ns + nt:]
    pf = {k: int(v, 16) for k, v in site.get("prefixes", {}).items()}
    if kind == "vdot":
        sv, tv = s, t
        if "s" in pf or "t" in pf:
            sv = apply_prefix(sv, pf.get("s", 0xE4))
            tv = apply_prefix(tv, pf.get("t", 0xE4))
        return [(0, sv, tv, d[0])]
    if kind == "vhdp":
        sv = list(s[:-1]) + [f2b(1.0)]
        return [(0, sv, t, d[0])]
    if kind == "vtfm":
        side = site["side"]
        tv = list(t) + [0] * (side - len(t))
        if len(t) < side:
            tv[side - 1] = f2b(1.0)
        out = []
        for r in range(side):
            mrow = s[r * side:(r + 1) * side]
            v = tv
            if r == side - 1 and "t" in pf:          # the framework applies T's prefix to the last row only
                v = apply_prefix(tv, pf["t"])[:side]
            out.append((r, mrow, v, d[r]))
        return out
    if kind == "vmmul":
        side = site["length"]
        out = []
        for a in range(side):
            for b in range(side):
                out.append((a * side + b, s[b * side:(b + 1) * side], t[a * side:(a + 1) * side], d[a * side + b]))
        return out
    return []


def load(dirpath):
    d = Path(dirpath)
    meta = json.loads((d / "sites.json").read_text())
    sites = []
    for site in meta["sites"]:
        addr = int(site["addr"], 16)
        f = d / f"{addr:08X}.csv"
        if not f.exists():
            continue
        rows = [[int(x, 16) for x in r[1:]] for r in csv.reader(open(f)) if r and r[0] != "usec"]
        pf = d / f"{addr:08X}.port.csv"
        port = None
        if pf.exists():
            port = [[int(x, 16) for x in r] for r in csv.reader(open(pf)) if r and not r[0].startswith("d")]
        sites.append((site, rows, port))
    return meta, sites


def group_name(site):
    if site["kind"] in ("vtfm", "vmmul"):
        return f"{site['mnemonic']} (each lane a {site.get('side', site['length'])}-lane dot)"
    return site["mnemonic"]


def dot_rows(sites):
    """Every dot product of every sample, with its port result: (site, row index, lane, s, t, ppsspp, port)."""
    for site, rows, port in sites:
        if site["kind"] not in DOT_KINDS:
            continue
        for i, row in enumerate(rows):
            for lane, s, t, want in dot_problems(site, row):
                pr = port[i][lane] if port is not None and i < len(port) else None
                yield site, i, lane, s, t, want, pr


def evaluate(model, problems):
    """(matches, total, failures) of a model over (s, t, want) problems; special operands use IEEE."""
    ok, bad = 0, []
    for p in problems:
        s, t, want = p[3], p[4], p[5]
        if any(is_special(x) for x in list(s) + list(t)):
            got = special_dot(s, t)
        else:
            got = model(s, t)
        if got == want:
            ok += 1
        else:
            bad.append((p, got))
    return ok, len(problems), bad


def candidates():
    out = [("a", None), ("exact", None), ("d1", None), ("d2", None), ("d3", None)]
    for n in (0, 1, 2, 3, 4):
        out.append(("c", {"n": n, "align": "raw", "trunc": "mag", "final": "rne"}))
    out.append(("c", {"n": 2, "align": "norm", "trunc": "mag", "final": "rne"}))
    out.append(("c", {"n": 2, "align": "raw", "trunc": "floor", "final": "rne"}))
    out.append(("c", {"n": 2, "align": "raw", "trunc": "mag", "final": "rtz"}))
    return out


def by_group(sites):
    groups = {}
    for p in dot_rows(sites):
        groups.setdefault(group_name(p[0]), []).append(p)
    return groups


def port_model(site):
    return dot_port_ct if site["kind"] in ("vdot", "vhdp") else dot_port_loop


def fmt_row(p, got=None):
    site, i, lane, s, t, want, pr = p
    sv = " ".join(f"{x:08X}" for x in s)
    tv = " ".join(f"{x:08X}" for x in t)
    g = f" model {got:08X}" if got is not None else ""
    return (f"{site['addr']} {site['mnemonic']} row {i} lane {lane}: s {sv} t {tv} -> PPSSPP {want:08X}{g}"
            f"{'' if pr is None else f' port {pr:08X}'}")


# ------------------------------------------------------------------------------------------- transcendentals

def libm():
    import ctypes
    lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    fns = {}
    for name in ("sinf", "cosf", "sqrtf", "exp2f", "log2f", "asinf"):
        f = getattr(lib, name)
        f.restype, f.argtypes = ctypes.c_float, [ctypes.c_float]
        fns[name] = f
    return fns


def trans_true(kind, x):
    """The function in double precision (the reference for 'how far from the true value')."""
    v = b2f(x)
    try:
        if kind == "vsin":
            return math.sin(v * math.pi / 2)
        if kind == "vcos":
            return math.cos(v * math.pi / 2)
        if kind == "vrcp":
            return 1.0 / v
        if kind == "vrsq":
            return 1.0 / math.sqrt(v)
        if kind == "vsqrt":
            return abs(math.sqrt(v))
        if kind == "vexp2":
            return 2.0 ** v
        if kind == "vlog2":
            return math.log2(v)
        if kind == "vasin":
            return math.asin(v) * 2 / math.pi
    except (ValueError, ZeroDivisionError, OverflowError):
        return None
    return None


def trans_closed_forms(kind, m):
    """Closed forms one could put in the codegen, each as a function of the input bits."""
    half_pi = b2f(f2b(1.57079632679489661923))
    f = {}
    if kind in ("vsin", "vcos"):
        fn = m["sinf"] if kind == "vsin" else m["cosf"]
        f["port: libm %sf(x * (float)pi/2)" % kind[1:]] = lambda x: f2b(fn(b2f(f2b(b2f(x) * half_pi))))
        f["double %s(x * pi/2) rounded" % kind[1:]] = lambda x: f2b(trans_true(kind, x))
    elif kind == "vrcp":
        f["port: 1.0f / x"] = lambda x: f2b(1.0 / b2f(x)) if b2f(x) else (x & 0x80000000) | 0x7F800000
    elif kind == "vrsq":
        f["port: 1.0f / sqrtf(x)"] = lambda x: f2b(1.0 / b2f(f2b(math.sqrt(b2f(x))))) if b2f(x) > 0 else None
        f["1 / sqrt(x) rounded once"] = lambda x: f2b(1.0 / math.sqrt(b2f(x))) if b2f(x) > 0 else None
    elif kind == "vsqrt":
        f["port: fabsf(sqrtf(x))"] = lambda x: f2b(abs(math.sqrt(b2f(x)))) if b2f(x) >= 0 else None
    return f


def trans_report(sites, out=print):
    m = libm()
    lines = []
    for site, rows, port in sites:
        kind = site["kind"]
        if kind not in TRANS_KINDS:
            continue
        n = len(site["s"])
        lanes = []
        for i, row in enumerate(rows):
            for k in range(n):
                lanes.append((row[k], row[n + k], port[i][k] if port is not None and i < len(port) else None))
        if not lanes:
            continue
        diff = [abs_ulps for abs_ulps in (ulps(p, w) for x, w, p in lanes if p is not None)]
        ndiff = sum(1 for u in diff if u)
        true_err = []
        for x, w, p in lanes:
            tv = trans_true(kind, x)
            if tv is None or not math.isfinite(tv) or is_special(w):
                continue
            true_err.append(ulps(f2b(tv), w))
        forms = trans_closed_forms(kind, m)
        form_hits = {}
        for name, fn in forms.items():
            hit = tot = 0
            for x, w, p in lanes:
                try:
                    g = fn(x)
                except (ValueError, OverflowError, ZeroDivisionError):
                    g = None
                if g is None:
                    continue
                tot += 1
                hit += g == w
            form_hits[name] = (hit, tot)
        hist = {}
        for u in diff:
            hist[u] = hist.get(u, 0) + 1
        lines.append({"site": site["addr"], "mnemonic": site["mnemonic"], "function": site.get("function"),
                      "lanes": len(lanes), "port_differs": ndiff, "port_max_ulps": max(diff) if diff else None,
                      "port_ulps_histogram": dict(sorted(hist.items())),
                      "ppsspp_vs_true_max_ulps": max(true_err) if true_err else None,
                      "ppsspp_vs_true_differs": sum(1 for u in true_err if u),
                      "closed_forms": {k: f"{h}/{t}" for k, (h, t) in form_hits.items()}})
    for L in lines:
        out(f"  {L['site']} {L['mnemonic']:8} {str(L['function']):22} {L['lanes']:6} results; the port's helper "
            f"differs on {L['port_differs']} (max {L['port_max_ulps']} ulp, histogram {L['port_ulps_histogram']}); "
            f"PPSSPP against the true value: {L['ppsspp_vs_true_differs']} differ, max {L['ppsspp_vs_true_max_ulps']}"
            f" ulp; closed forms reproducing PPSSPP: "
            + "; ".join(f"{k} {v}" for k, v in L["closed_forms"].items()))
    return lines


# ------------------------------------------------------------------------------------------- commands

def cmd_report(d):
    meta, sites = load(d)
    groups = by_group(sites)
    cands = candidates()
    print(f"dot-product samples in {d}: " + ", ".join(f"{g} {len(v)}" for g, v in groups.items()))
    print(f"{'model':34}" + "".join(f"{g[:22]:>24}" for g in groups))
    for name, params in [("port", None)] + cands:
        cells = []
        for g, probs in groups.items():
            if name == "port":
                ok = sum(1 for p in probs if (p[6] if p[6] is not None else port_model(p[0])(p[3], p[4])) == p[5])
                tot = len(probs)
            else:
                ok, tot, _ = evaluate(model_fn(name, params), probs)
            cells.append(f"{ok}/{tot} {100.0 * ok / max(tot, 1):.3f}%")
        print(f"{model_label(name, params):34}" + "".join(f"{c:>24}" for c in cells))
    # the port's results against model b (is the emulation of the port right?)
    for g, probs in groups.items():
        have = [p for p in probs if p[6] is not None]
        if have:
            ok = sum(1 for p in have if port_model(p[0])(p[3], p[4]) == p[6])
            print(f"model b against the port's own results, {g}: {ok}/{len(have)}")
    print("transcendentals:")
    trans_report(sites)


def cmd_search(d, limit):
    meta, sites = load(d)
    groups = by_group(sites)
    probs = [p for g in groups.values() for p in g[:limit]]
    res = []
    for n in range(0, 9):
        for align in ("raw", "norm"):
            for trunc in ("mag", "floor"):
                for final in ("rne", "rtz", "rna"):
                    params = {"n": n, "align": align, "trunc": trunc, "final": final}
                    ok, tot, _ = evaluate(model_fn("c", params), probs)
                    res.append((ok, model_label("c", params)))
    res.sort(reverse=True)
    for ok, lab in res[:20]:
        print(f"{lab:34} {ok}/{len(probs)} {100.0 * ok / len(probs):.3f}%")


def cmd_check(d):
    meta, sites = load(d)
    groups = by_group(sites)
    if not groups:
        print(f"vfpu_model: no dot-product samples in {d}")
        return 1
    name, params = CHOSEN
    fn = model_fn(name, params)
    print(f"chosen model: {model_label(name, params)}")
    fails = 0
    for g, probs in groups.items():
        ok, tot, bad = evaluate(fn, probs)
        port_ok = sum(1 for p in probs if p[6] is not None and p[6] == p[5])
        have_port = sum(1 for p in probs if p[6] is not None)
        print(f"  {g:44} {ok}/{tot} reproduced ({100.0 * ok / tot:.3f}%); the port today {port_ok}/{have_port}")
        for p, got in bad[:20]:
            print("    FAIL " + fmt_row(p, got))
        fails += len(bad)
    print("transcendentals (the port's helper against PPSSPP):")
    trans_report(sites)
    print(f"vfpu_model --check: {'PASS' if not fails else f'FAIL ({fails} rows)'}")
    return 0 if not fails else 1


def autotest_cases():
    """pspautotests vector.c's SVV dot products (vdot/vhdp .p .t .q over the first five test vectors) with the
    hardware's printed results (vector.expected)."""
    vecs = [(1.0, 2.0, 3.0, 4.0), (5.0, 6.0, -7.0, -8.0), (-1.0, -2.0, -3.0, -4.0), (-4.0, -5.0, 6.0, 7.0),
            (-0.1, 1000.0, float("inf"), 0.0)]
    exp = AUTOTESTS / "vector.expected"
    if not exp.exists():
        return None
    lines = {}
    for line in exp.read_text().splitlines():
        m = re.match(r"(vdot|vhdp)_([ptq]): (\S+?),", line)
        if m:
            lines.setdefault((m[1], m[2]), []).append(m[3])
    cases = []
    for (op, sz), vals in lines.items():
        n = {"p": 2, "t": 3, "q": 4}[sz]
        k = 0
        for i in range(5):
            for j in range(5):
                s = [f2b(v) for v in vecs[i][:n]]
                t = [f2b(v) for v in vecs[j][:n]]
                if op == "vhdp":
                    s = s[:-1] + [f2b(1.0)]
                cases.append((f"{op}.{sz} v{i}.v{j}", s, t, vals[k]))
                k += 1
    return cases


def selftest():
    fails = []
    rnd = random.Random(47)
    # 1. round_pack against the platform's double-to-float conversion (round to nearest even), normal range only.
    for _ in range(20000):
        x = rnd.uniform(-1, 1) * 2.0 ** rnd.randint(-100, 100)
        fr = Fraction(x)
        want = f2b(x)
        if (want >> 23) & 0xFF in (0, 255):
            continue
        got = round_exact(fr.numerator * (1 << 60) // fr.denominator, -60) if fr.denominator > 1 << 60 else None
        mant, ex = math.frexp(x)
        mi = int(mant * (1 << 53))
        got = round_exact(mi, ex - 53)
        if got != want:
            fails.append(f"round_pack {x!r}: {got:08X} != {want:08X}")
            break
    # 2. fmul/fadd against IEEE single arithmetic through doubles (exact products/sums of floats fit doubles mostly).
    for _ in range(20000):
        a = f2b(rnd.uniform(-4, 4) * 2.0 ** rnd.randint(-20, 20))
        b = f2b(rnd.uniform(-4, 4) * 2.0 ** rnd.randint(-20, 20))
        if fmul(a, b) != f2b(b2f(a) * b2f(b)):
            fails.append(f"fmul {a:08X} {b:08X}")
            break
        if abs(((a >> 23) & 0xFF) - ((b >> 23) & 0xFF)) < 25 and fadd(a, b) != f2b(b2f(a) + b2f(b)):
            fails.append(f"fadd {a:08X} {b:08X}")
            break
    # 3. ffma against math.fma (double) rounded to float, where the double fma is exact in the float sense.
    for _ in range(5000):
        a, b, c = (f2b(rnd.uniform(-2, 2) * 2.0 ** rnd.randint(-8, 8)) for _ in range(3))
        exact = Fraction(b2f(a)) * Fraction(b2f(b)) + Fraction(b2f(c))
        want = f2b(float(exact)) if exact else 0
        # float(Fraction) rounds to nearest double; a double holds a*b+c exactly here (48+ bits apart at most 64)
        if exact and Fraction(float(exact)) == exact and ffma(a, b, c) != want:
            fails.append(f"ffma {a:08X} {b:08X} {c:08X}")
            break
    # 4. task 046's example: the squared length of (-0.852767, 0.00194, 0.033974).
    v = [0xBF5A4EEF, 0x3AFE5500, 0x3D0B28A3]
    port, chosen = dot_port_ct(v, v), model_fn(*CHOSEN)(v, v)
    if port != 0x3F3A766C:
        fails.append(f"task 046 example: the port model gives {port:08X}, the port gave 3F3A766C")
    if chosen != 0x3F3A766B:
        fails.append(f"task 046 example: the chosen model gives {chosen:08X}, PPSSPP gave 3F3A766B")
    # 5. pspautotests' hardware results for vdot and vhdp (integer and near-integer operands, infinities).
    cases = autotest_cases()
    if cases is None:
        print(f"selftest: {AUTOTESTS / 'vector.expected'} not found; skipped the hardware cases")
    else:
        for name, params in [CHOSEN, ("a", None), ("exact", None)]:
            fn = model_fn(name, params)
            bad = 0
            for label, s, t, want in cases:
                got = special_dot(s, t) if any(is_special(x) for x in s + t) else fn(s, t)
                if f"{b2f(got):f}" != want:
                    bad += 1
                    if name == CHOSEN[0]:
                        fails.append(f"vector.expected {label}: {model_label(name, params)} prints {b2f(got):f}, "
                                     f"the PSP {want}")
            print(f"selftest: vector.expected {len(cases) - bad}/{len(cases)} with {model_label(name, params)}")
    for f in fails:
        print("selftest FAIL: " + f)
    print("vfpu_model --selftest: " + ("PASS" if not fails else "FAIL"))
    return 0 if not fails else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check", nargs="?", const=str(DEFAULT_DIR), metavar="DIR")
    ap.add_argument("--report", nargs="?", const=str(DEFAULT_DIR), metavar="DIR")
    ap.add_argument("--search", nargs="?", const=str(DEFAULT_DIR), metavar="DIR")
    ap.add_argument("--limit", type=int, default=3000, help="--search: rows per group")
    a = ap.parse_args()
    rc = 0
    if a.selftest:
        rc |= selftest()
    if a.report:
        cmd_report(a.report)
    if a.search:
        cmd_search(a.search, a.limit)
    if a.check:
        rc |= cmd_check(a.check)
    if not (a.selftest or a.report or a.search or a.check):
        ap.print_help()
    sys.exit(rc)


if __name__ == "__main__":
    main()
