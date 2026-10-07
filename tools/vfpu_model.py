#!/opt/homebrew/bin/python3
"""The VFPU's dot-product rounding, modelled against PPSSPP's results (task 047).

  vfpu_model.py --selftest            the arithmetic helpers, task 046's example and pspautotests' vector.expected
  vfpu_model.py --check [DIR]         every sample set under DIR (ref/vfpu: jit/, interp/): the rule for the PPSSPP
                                      core that made it, per instruction; exit 0 when it reproduces every dot-product
                                      sample, else the failing rows; then the transcendental report
  vfpu_model.py --report [DIR]        every candidate model over every sample set, per instruction and lane count
  vfpu_model.py --search [DIR]        the parameter grid of the aligned-truncation family (model c)
  vfpu_model.py --check DIR --tag T   the same, with the port's results under both modes from <ADDR>.port.T.<mode>.csv
  vfpu_model.py --diff [DIR] [--which ppsspp] [--limit N]
                                      every sampled result where the port (<ADDR>.port.<which>.csv) differs from
                                      PPSSPP's, per site and in time order (task 048: where a divergence can start)

Task 048 adds the kinds beside the dot forms, each result lane a problem with its own candidates (kind_models):
vcrs.t (one product), vcrsp.t (a difference of two products: the first rounded and the second fused, the reverse,
unfused, exact, the PSP's), vqmul.q (four products: chains in either lane order, unfused, clang's contraction, exact,
the PSP's), vfad (in lane order from s0 or from +0, a tree, exact, the PSP's), vavg (the framework's weighted sum,
sum / n, sum * (1/n), the PSP's), vrot (sinf/cosf of the float x * pi/2, sin/cos in double) and vmscl (one product).
RULES_048 holds PPSSPP's JIT's measured rule a kind, HW_048 the PSP's (what the header's default mode computes);
--check also reports the port's results under the two modes of patch 0020 (vfpu_probe.py port --modes ppsspp,psp):
the test mode against PPSSPP, the default against the PSP's rule.

The samples are tools/vfpu_probe.py's: a directory with sites.json (which PPSSPP core made them, the sites, their
prefixes) and one <ADDR>.csv a site with PPSSPP's source lanes and result lanes as bit patterns, and <ADDR>.port.csv
with the port's results for the same rows (the corpus's own code, run by `vfpu_probe.py port`). Every model works on
integers: a float is (sign, biased exponent, 24-bit significand), a product of two is exact (48 bits), and each model
says where it rounds. Inputs with a zero exponent field are zero (the VFPU flushes subnormals, vfpu-docs'
introduction), and so are results below the smallest normal.

The dot-product models over the n lanes the encoding names (a vtfm or vmmul result lane is the same n-lane dot of a
matrix row and a vector):
  a      unfused: each product rounded to float, then summed in lane order, rounding after each addition
  a0     the same from +0 (r = +0, then r = r + round(s_i * t_i)): only the sign of an exact zero differs from a
  chain  fused in lane order: r = s0*t0 rounded, then r = fma(s_i, t_i, r) for i = 1 .. n-1 (one rounding each)
  b      the port today: clang's contraction of the framework's C++. The _ct vdot `s0*t0 + s1*t1 + s2*t2 + s3*t3`
         is fma(s3,t3, fma(s2,t2, fma(s0,t0, s1*t1))) over a four-lane view (lane 1's product is the one rounded);
         the vtfm and vmmul loops `float sum = 0; sum += m*t` are an fma chain from +0
  exact  the exact sum rounded to nearest once
  c      exact products aligned to the largest product exponent and kept with 23+N fraction bits there, the bits
         below dropped (toward zero on each product's magnitude, or toward minus infinity on the signed value),
         summed exactly, rounded once (to nearest even, toward zero, or to nearest away); parameters N, the alignment
         reference (the raw exponent sum, or the product's own normalised exponent), truncation and final rounding.
         c(N=2,raw,mag,rtz) is the only one of the grid that reproduces all 150 of pspautotests' vdot/vhdp results
         from a real PSP (vector.expected) and is called `hw` below
  d1     products rounded to float, summed exactly, rounded once
  d2     products truncated to float, summed exactly, rounded once
  d3     products rounded to float, summed as a tree ((p0+p1)+(p2+p3)), rounding after each addition

What the samples showed (docs/fidelity.md, difference 13): PPSSPP's JIT (CPU core 1, the core of every reference in
ref/) computes vdot and vtfm as `chain` and vmmul as `a0`, on 100 percent of the samples; its interpreter (core 0)
the same, except that it fuses (`chain`) the last element of a vmmul's result. The port's vdot differs from them only
by its contraction order (lane 1's product rounded first instead of lane 0's), its vtfm only in the sign of an exact
zero (its chain starts from +0), its vmmul by fusing. Neither core is the PSP's rule (`hw`). RULES holds the measured
rule of each core.
"""
import argparse, csv, json, math, random, re, struct, sys
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DIR = ROOT / "ref" / "vfpu"
AUTOTESTS = Path.home() / "dev" / "scratch" / "pspautotests" / "tests" / "cpu" / "vfpu"

DOT_KINDS = ("vdot", "vhdp", "vtfm", "vmmul")
TRANS_KINDS = ("vsin", "vcos", "vrcp", "vrsq", "vsqrt", "vexp2", "vlog2", "vasin", "vnrcp", "vnsin", "vrexp2")
HW = ("c", {"n": 2, "align": "raw", "trunc": "mag", "final": "rtz"})

# The measured rule of each PPSSPP CPU core, per instruction kind: (model, params); `vmmul_last` is the model of the
# result matrix's last element where it differs. vhdp has no samples (the game has no vhdp in its code): it is given
# vdot's rule.
RULES = {
    1: {"name": "PPSSPP's JIT", "vdot": ("chain", None), "vhdp": ("chain", None), "vtfm": ("chain", None),
        "vmmul": ("a0", None)},
    0: {"name": "PPSSPP's interpreter", "vdot": ("chain", None), "vhdp": ("chain", None), "vtfm": ("chain", None),
        "vmmul": ("a0", None), "vmmul_last": ("chain", None)},
}


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


def dot_chain(s, t):
    """Fused in lane order: s0*t0 rounded, then one fma a lane (PPSSPP's JIT for vdot and vtfm)."""
    acc = fmul(s[0], t[0])
    for x, y in zip(s[1:], t[1:]):
        acc = ffma(x, y, acc)
    return acc


def dot_a0(s, t):
    """Unfused from +0: r = +0, then r = r + round(s_i * t_i) (PPSSPP's vmmul)."""
    acc = 0
    for x, y in zip(s, t):
        acc = fadd(acc, fmul(x, y))
    return acc


MODELS = {
    "a": dot_a,
    "a0": dot_a0,
    "chain": dot_chain,
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
    lab = f"c(N={params['n']},{params['align']},{params['trunc']},{params['final']})"
    return lab + (" = hw" if params == HW[1] else "")


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
        raw = [r for r in csv.reader(open(f)) if r and r[0] != "usec"]
        rows = [[int(x, 16) for x in r[1:]] for r in raw]
        site["_usec"] = [int(r[0]) for r in raw]
        pf = d / f"{addr:08X}.port.csv"
        port = None
        if pf.exists():
            port = [[int(x, 16) for x in r] for r in csv.reader(open(pf)) if r and not r[0].startswith("d")]
        # Task 048: the port's results under each rounding mode (vfpu_probe.py port --modes ppsspp,psp [--tag T]):
        # <ADDR>.port.<mode>.csv and <ADDR>.port.<tag>.<mode>.csv, kept in site["_ports"] by "<mode>"/"<tag>.<mode>".
        site["_ports"] = {}
        for f in sorted(d.glob(f"{addr:08X}.port.*.csv")):
            name = f.name[len(f"{addr:08X}.port."):-len(".csv")]
            site["_ports"][name] = [[int(x, 16) for x in r] for r in csv.reader(open(f))
                                    if r and not r[0].startswith("d")]
        sites.append((site, rows, port))
    return meta, sites


def group_name(site):
    if site["kind"] in ("vtfm", "vmmul"):
        return f"{site['mnemonic']} (each lane a {site.get('side', site['length'])}-lane dot)"
    return site["mnemonic"]


def dot_rows(sites, which="port"):
    """Every dot product of every sample, with its port result: (site, row index, lane, s, t, ppsspp, port); the
    port's from <ADDR>.port.csv, or with `which` (ppsspp, psp) from <ADDR>.port.<which>.csv."""
    for site, rows, port in sites:
        if site["kind"] not in DOT_KINDS:
            continue
        if which != "port":
            port = site.get("_ports", {}).get(which)
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


def rule_model(rule, p):
    """The (model, params) a core's rule gives the dot product p (site, row, lane, ...)."""
    site, lane = p[0], p[2]
    kind = site["kind"]
    if kind == "vmmul" and "vmmul_last" in rule and lane == site["length"] ** 2 - 1:
        return rule["vmmul_last"]
    return rule[kind]


def evaluate_rule(rule, problems):
    """evaluate() with the model the rule gives each problem."""
    ok, bad = 0, []
    for p in problems:
        name, params = rule_model(rule, p)
        got = special_dot(p[3], p[4]) if any(is_special(x) for x in list(p[3]) + list(p[4])) \
            else model_fn(name, params)(p[3], p[4])
        if got == p[5]:
            ok += 1
        else:
            bad.append((p, got))
    return ok, len(problems), bad


def rule_label(rule, kind):
    name, params = rule[kind]
    lab = model_label(name, params)
    if kind == "vmmul" and "vmmul_last" in rule:
        lab += f", last element {model_label(*rule['vmmul_last'])}"
    return lab


def candidates():
    out = [("a", None), ("a0", None), ("chain", None), ("exact", None), ("d1", None), ("d2", None), ("d3", None), HW]
    for n in (0, 1, 2, 3, 4):
        out.append(("c", {"n": n, "align": "raw", "trunc": "mag", "final": "rne"}))
    out.append(("c", {"n": 2, "align": "norm", "trunc": "mag", "final": "rtz"}))
    out.append(("c", {"n": 2, "align": "raw", "trunc": "floor", "final": "rtz"}))
    return out


def by_group(sites, which="port"):
    groups = {}
    for p in dot_rows(sites, which):
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


# ------------------------------------------------------------------------------------------- task 048: other kinds
#
# The products and sums beside the dot forms. Each sample row of these kinds gives one problem a result lane:
#   vcrs.t   lane i: one product, (s1*t2, s2*t0, s0*t1)
#   vcrsp.t  lane i: a difference of two products, (s1*t2 - s2*t1, s2*t0 - s0*t2, s0*t1 - s1*t0)
#   vqmul.q  lane i: four products (vfpu-docs' pcode; the header's order s . (t3, t2, -t1, t0), ...)
#   vfad     lane 0: s0 + s1 (+ s2 (+ s3))
#   vavg     lane 0: the same over n
#   vrot     lane i: sin(x * pi/2), cos(x * pi/2) (negated sine with imm bit 4) or 0, by the immediate
#   vmscl    element i: s_i * t
# The models take (s, t, lane, site) and return the result's bits.

NEW_KINDS = ("vcrs", "vcrsp", "vqmul", "vfad", "vavg", "vrot", "vmscl")
ONE = 0x3F800000


def neg(b):
    return b ^ 0x80000000


CRS_PAIRS = ((1, 2), (2, 0), (0, 1))                 # vcrs.t: lane i = s[a] * t[b]
CRSP_TERMS = (((1, 2), (2, 1)), ((2, 0), (0, 2)), ((0, 1), (1, 0)))   # vcrsp.t: lane i = s[a]t[b] - s[c]t[d]
# vqmul.q, lane i = s . T_i, T_i as the header builds it (the docs' pcode has the same terms, from s[3] down)
QMUL_T = ((3, 2, ~1, 0), (~2, 3, 0, 1), (1, ~0, 3, 2), (~0, ~1, ~2, 3))


def qmul_t(t, lane):
    return [neg(t[~k]) if k < 0 else t[k] for k in QMUL_T[lane]]


def any_special(*vs):
    return any(is_special(x) for v in vs for x in v)


def ieee_terms(s, t):
    """Inf or NaN among the operands: IEEE products summed in order, unfused (the header's fallback)."""
    return special_dot(s, t)


def crsp_ops(s, t, lane):
    (a, b), (c, d) = CRSP_TERMS[lane]
    return [s[a], s[c]], [t[b], neg(t[d])]


def crsp_model(fn):
    def m(s, t, lane, site):
        sv, tv = crsp_ops(s, t, lane)
        return ieee_terms(sv, tv) if any_special(sv, tv) else fn(sv, tv)
    return m


def crsp_second(sv, tv):
    """The second product rounded, the first fused: fma(a, b, -round(c*d)) (clang's contraction of `a*b - c*d`)."""
    return ffma(sv[0], tv[0], fmul(sv[1], tv[1]))


def crsp_port_ppsspp(s, t, lane, site):
    """The header since task 047 under the test mode: vfpu_dot over two lanes for X and Y; for Z the four-lane
    view (s0, s1, s2, 0) . (t1, -t0, 0, t2), whose zero lanes add +0 to the chain."""
    if lane < 2:
        sv, tv = crsp_ops(s, t, lane)
        return ieee_terms(sv, tv) if any_special(sv, tv) else dot_chain(sv, tv)
    sv, tv = [s[0], s[1], s[2], 0], [t[1], neg(t[0]), 0, t[2]]
    return ieee_terms(sv, tv) if any_special(sv, tv) else dot_chain(sv, tv)


def crsp_port_old(s, t, lane, site):
    """The header before task 047 (clang's contraction, -ffp-contract=on): X and Y `a*b - c*d` as
    fma(a, b, -round(c*d)); Z the four-term `s0*t0 + s1*t1 + s2*t2 + s3*t3` of the forced view, as the _ct vdot."""
    if lane < 2:
        sv, tv = crsp_ops(s, t, lane)
        return ieee_terms(sv, tv) if any_special(sv, tv) else crsp_second(sv, tv)
    sv, tv = [s[0], s[1], s[2], 0], [t[1], neg(t[0]), 0, t[2]]
    return ieee_terms(sv, tv) if any_special(sv, tv) else dot_port_ct(sv, tv)


def qmul_model(fn, order=(0, 1, 2, 3)):
    def m(s, t, lane, site):
        tv = qmul_t(t, lane)
        sv, tv = [s[k] for k in order], [tv[k] for k in order]
        return ieee_terms(sv, tv) if any_special(sv, tv) else fn(sv, tv)
    return m


def sum_seq(v, start=None):
    acc = v[0] if start is None else start
    for x in (v[1:] if start is None else v):
        acc = fadd(acc, x)
    return acc


def fad_model(fn):
    def m(s, t, lane, site):
        return f2b(sum(b2f(x) for x in s)) if any_special(s) else fn(list(s))
    return m


def fad_tree(v):
    v = list(v) + [0] * (4 - len(v))
    return fadd(fadd(v[0], v[1]), fadd(v[2], v[3])) if len(v) == 4 else sum_seq(v)


def fad_exact(v):
    terms = [to_exact(x) for x in v]
    val, e = add_exact(terms)
    return round_exact(val, e)


AVG_W = {2: 0x3F000000, 3: f2b(1.0 / 3.0), 4: 0x3E800000}


def avg_port(v):
    """The framework: r = +0, then r = r + s_i * w over a four-lane view (the lanes past n are 0), each rounded."""
    w = AVG_W[len(v)]
    acc = 0
    for x in list(v) + [0] * (4 - len(v)):
        acc = fadd(acc, fmul(x, w))
    return acc


def avg_div(v):
    n = len(v)
    acc = sum_seq(v)
    p = to_exact(acc)
    if p is None or p[0] == 0:
        return f2b(b2f(acc) / n)
    q = Fraction(p[0]) * Fraction(2) ** p[1] / n
    return f2b(float(q)) if abs(q) >= Fraction(2) ** -100 else 0


def avg_mul(v):
    return fmul(sum_seq(v), AVG_W[len(v)])


def avg_hw(v):
    return fmul(dot_c(v, [ONE] * len(v), **HW[1]), AVG_W[len(v)])


HALF_PI_F = f2b(1.57079632679489661923)
_LIBM = None


def libm_f(name):
    global _LIBM
    if _LIBM is None:
        _LIBM = libm()
    return _LIBM[name]


def rot_lane(site, lane):
    """What lane `lane` of a vrot holds: 'cos', 'sin' (negated with imm bit 4) or 'zero'."""
    imm = int(site.get("imm", 0))
    cl, sl = imm & 3, (imm >> 2) & 3
    if lane == cl:
        return "cos"
    if cl == sl or lane == sl:
        return "sin"
    return "zero"


def rot_model(sinf, cosf):
    def m(s, t, lane, site):
        what = rot_lane(site, lane)
        if what == "zero":
            return 0
        r = cosf(s[0]) if what == "cos" else sinf(s[0])
        if what == "sin" and int(site.get("imm", 0)) & 0x10:
            r = neg(r)
        return r
    return m


def _f(x):
    return f2b(x)


ROT_FORMS = {
    # the port: std::sin / std::cos of the float x * (float)(pi/2) (libm's sinf, cosf)
    "port": (lambda x: _f(libm_f("sinf")(b2f(fmul(x, HALF_PI_F)))),
             lambda x: _f(libm_f("cosf")(b2f(fmul(x, HALF_PI_F))))),
    # the true value, sin(x * pi/2) in double precision rounded once
    "double": (lambda x: _f(math.sin(b2f(x) * math.pi / 2)), lambda x: _f(math.cos(b2f(x) * math.pi / 2))),
    # the float product x * (float)(pi/2), then sin and cos in double precision rounded once
    "double(float product)": (lambda x: _f(math.sin(b2f(fmul(x, HALF_PI_F)))),
                              lambda x: _f(math.cos(b2f(fmul(x, HALF_PI_F))))),
}


def kind_models(kind):
    """The candidate models of a task 048 kind: {name: fn(s, t, lane, site) -> bits}."""
    if kind == "vcrs":
        return {"ieee": lambda s, t, lane, site: fmul(s[CRS_PAIRS[lane][0]], t[CRS_PAIRS[lane][1]])}
    if kind == "vcrsp":
        return {"first": crsp_model(dot_chain), "second": crsp_model(crsp_second), "unfused": crsp_model(dot_a),
                "exact": crsp_model(dot_exact), "hw": crsp_model(model_fn(*HW)),
                "port test mode": crsp_port_ppsspp, "port before 0020": crsp_port_old}
    if kind == "vqmul":
        return {"chain": qmul_model(dot_chain), "chain from s3": qmul_model(dot_chain, (3, 2, 1, 0)),
                "unfused": qmul_model(dot_a), "b (before 0020)": qmul_model(dot_port_ct),
                "exact": qmul_model(dot_exact), "hw": qmul_model(model_fn(*HW))}
    if kind == "vfad":
        return {"sequential": fad_model(sum_seq), "from +0": fad_model(lambda v: sum_seq(v + [0] * (4 - len(v)), 0)),
                "tree": fad_model(fad_tree), "exact": fad_model(fad_exact),
                "hw": fad_model(lambda v: dot_c(v, [ONE] * len(v), **HW[1]))}
    if kind == "vavg":
        return {"port (weighted, from +0)": fad_model(avg_port), "sum / n": fad_model(avg_div),
                "sum * (1/n)": fad_model(avg_mul), "hw sum * (1/n)": fad_model(avg_hw)}
    if kind == "vrot":
        return {name: rot_model(*fns) for name, fns in ROT_FORMS.items()}
    if kind == "vmscl":
        return {"ieee": lambda s, t, lane, site: fmul(s[0], t[0])}
    return {}


# The measured rule of each PPSSPP core for these kinds (model names of kind_models), and what the PSP's default
# mode of the header should compute (its `hw` where a sum of products is involved, an IEEE product otherwise).
# Measured on PPSSPP's JIT (task 048, Vineta K and Karbonis, READY to 13 s): vcrsp.t unfused, vfad sequential (from
# s0; from +0 gives the same on every sample), vmscl one IEEE product. Not measured, because the game's code has no
# vcrs.t, vqmul.q or vavg and no vrot ran in either race: vcrs is one product in every model; vqmul's and vavg's
# entries are vcrsp's and vfad's rule carried over and vrot's is the port's helper, so --check applies them only to
# pspautotests' integer cases.
RULES_048 = {
    1: {"vcrs": "ieee", "vcrsp": "unfused", "vqmul": "unfused", "vfad": "sequential", "vavg": "sum / n",
        "vrot": "port", "vmscl": "ieee"},
}
HW_048 = {"vcrs": "ieee", "vcrsp": "hw", "vqmul": "hw", "vfad": "hw", "vavg": "hw sum * (1/n)", "vrot": "port",
          "vmscl": "ieee"}


def other_problems(site, row):
    """The result lanes of one sample row of a task 048 kind: [(lane, s, t, PPSSPP's bits)]."""
    kind, n = site["kind"], site["length"]
    if kind in ("vcrs", "vcrsp", "vqmul"):
        s, t, d = row[:n], row[n:2 * n], row[2 * n:3 * n]
        return [(i, s, t, d[i]) for i in range(n)]
    if kind in ("vfad", "vavg"):
        return [(0, row[:n], [], row[n])]
    if kind == "vrot":
        return [(i, row[:1], [], row[1 + i]) for i in range(n)]
    if kind == "vmscl":
        k = n * n
        s, t, d = row[:k], row[k:k + 1], row[k + 1:k + 1 + k]
        return [(i, [s[i]], t, d[i]) for i in range(k)]
    return []


def other_rows(sites, which="port"):
    """Every result lane of the task 048 kinds: (site, row index, lane, s, t, PPSSPP's bits, the port's bits) with
    the port's from <ADDR>.port.csv, or another port file (`which`: ppsspp, psp: <ADDR>.port.<which>.csv)."""
    for site, rows, port in sites:
        if site["kind"] not in NEW_KINDS:
            continue
        if which != "port":
            port = site.get("_ports", {}).get(which)
        for i, row in enumerate(rows):
            for lane, s, t, want in other_problems(site, row):
                pr = port[i][lane] if port is not None and i < len(port) else None
                yield site, i, lane, s, t, want, pr


def evaluate_other(fn, problems):
    ok, bad = 0, []
    for p in problems:
        got = fn(p[3], p[4], p[2], p[0])
        if got == p[5]:
            ok += 1
        else:
            bad.append((p, got))
    return ok, len(problems), bad


def other_groups(sites, which="port"):
    groups = {}
    for p in other_rows(sites, which):
        groups.setdefault(p[0]["mnemonic"], []).append(p)
    return groups


def other_fmt(p, got=None):
    site, i, lane, s, t, want, pr = p
    extra = f" imm {site.get('imm')} ({rot_lane(site, lane)})" if site["kind"] == "vrot" else ""
    g = f" model {got:08X}" if got is not None else ""
    return (f"{site['addr']} {site['mnemonic']} row {i} lane {lane}{extra}: s {' '.join(f'{x:08X}' for x in s)}"
            f"{' t ' + ' '.join(f'{x:08X}' for x in t) if t else ''} -> PPSSPP {want:08X}{g}"
            f"{'' if pr is None else f' port {pr:08X}'}")


def port_agreement(probs, ref_fn=None):
    """(agreeing, total) of the port's bits (p[6]) against PPSSPP's (ref_fn None) or against a model."""
    have = [p for p in probs if p[6] is not None]
    if ref_fn is None:
        return sum(1 for p in have if p[6] == p[5]), len(have)
    return sum(1 for p in have if p[6] == ref_fn(p)), len(have)


# ------------------------------------------------------------------------------------------- commands

def datasets(d):
    """The sample sets under d: d itself and its subdirectories that hold a sites.json, as (path, meta, sites)."""
    d = Path(d)
    out = []
    for p in sorted({f.parent for f in d.rglob("sites.json")}) if d.exists() else []:
        if (p / "sites.json").exists():
            meta, sites = load(p)
            if sites:
                out.append((p, meta, sites))
    return out


def core_of(meta):
    return meta.get("run", {}).get("cpu_core", 1)


def set_title(path, meta):
    run = meta.get("run", {})
    core = core_of(meta)
    rule = RULES.get(core, {}).get("name", f"core {core}")
    offs = run.get("ships_off_reference_m") or {}
    worst = max(offs.values()) if offs else None
    return (f"{path}: {rule} (CPU core {core}), {run.get('track')} to race clock {run.get('end_clock', 0):.2f} s"
            + (f"; the ships end {worst:.3f} m or less from the reference race" if worst is not None else ""))


def trans_summary(sites, out=print):
    """The transcendental instructions per mnemonic: the port's helper against PPSSPP, PPSSPP against the value."""
    lines = trans_report(sites, out=lambda *_: None)
    agg = {}
    for L in lines:
        a = agg.setdefault(L["mnemonic"], {"sites": 0, "lanes": 0, "port_differs": 0, "port_max": 0,
                                            "true_differs": 0, "true_max": 0, "forms": {}})
        a["sites"] += 1
        a["lanes"] += L["lanes"]
        a["port_differs"] += L["port_differs"]
        a["port_max"] = max(a["port_max"], L["port_max_ulps"] or 0)
        a["true_differs"] += L["ppsspp_vs_true_differs"]
        a["true_max"] = max(a["true_max"], L["ppsspp_vs_true_max_ulps"] or 0)
        for k, v in L["closed_forms"].items():
            h, t = (int(x) for x in v.split("/"))
            f = a["forms"].setdefault(k, [0, 0])
            f[0] += h
            f[1] += t
    for mn, a in sorted(agg.items()):
        out(f"  {mn:8} {a['sites']:3} sites, {a['lanes']:7} results: the port's helper differs on {a['port_differs']} "
            f"(max {a['port_max']} ulp); PPSSPP differs from the true value (double precision) on "
            f"{a['true_differs']} (max {a['true_max']} ulp); "
            + "; ".join(f"{k}: {h}/{t}" for k, (h, t) in a["forms"].items()))
    missing = [k for k in ("vsin", "vcos", "vrcp", "vrsq", "vexp2", "vlog2", "vasin") if k + ".s" not in agg
               and not any(m.startswith(k + ".") for m in agg)]
    if missing:
        out(f"  not in these samples: {', '.join(missing)} (tools/vfpu_probe.py scan: vsin and vcos have two sites "
            f"each, which the race did not run; vexp2, vlog2 and vasin occur nowhere in the executable)")
    return agg


def cmd_report(d):
    for path, meta, sites in datasets(d):
        print(set_title(path, meta))
        groups = by_group(sites)
        cands = candidates() if groups else []
        if groups:
            print("  " + ", ".join(f"{g} {len(v)}" for g, v in groups.items()))
            print(f"  {'model':30}" + "".join(f"{g.split(' ')[0]:>22}" for g in groups))
        rule = RULES.get(core_of(meta))
        for name, params in ([("port", None)] + ([("rule", None)] if rule else []) + cands if groups else []):
            cells = []
            for g, probs in groups.items():
                if name == "port":
                    have = [p for p in probs if p[6] is not None]
                    ok, tot = sum(1 for p in have if p[6] == p[5]), len(have)
                elif name == "rule":
                    ok, tot, _ = evaluate_rule(rule, probs)
                else:
                    ok, tot, _ = evaluate(model_fn(name, params), probs)
                cells.append(f"{100.0 * ok / max(tot, 1):.3f}%")
            lab = f"the rule of {rule['name']}" if name == "rule" else model_label(name, params)
            print(f"  {lab:30}" + "".join(f"{c:>22}" for c in cells))
        for g, probs in groups.items():
            have = [p for p in probs if p[6] is not None]
            if have:
                ok = sum(1 for p in have if port_model(p[0])(p[3], p[4]) == p[6])
                print(f"  model b against the port's own results, {g}: {ok}/{len(have)}")
        report_others(sites, core_of(meta))
        print("  transcendentals, per site:")
        trans_report(sites, out=lambda s: print("  " + s))


def report_others(sites, core):
    """Every candidate model of the task 048 kinds over a set, per mnemonic: the percentage of PPSSPP's results it
    gives, and the port's (today, and under both modes) against PPSSPP."""
    groups = other_groups(sites)
    if not groups:
        return
    rule48 = RULES_048.get(core, {})
    for g, probs in groups.items():
        kind = probs[0][0]["kind"]
        print(f"  {g}: {len(probs)} result lanes over {len({p[0]['addr'] for p in probs})} sites")
        for name, fn in kind_models(kind).items():
            ok, tot, _ = evaluate_other(fn, probs)
            mark = " (the rule)" if rule48.get(kind) == name else (" (hw)" if HW_048.get(kind) == name else "")
            print(f"    {name + mark:34} {ok:8}/{tot} {100.0 * ok / max(tot, 1):8.3f}%")
        names = {"port": "the port (.port.csv)", "ppsspp": "the port, test mode", "psp": "the port, default mode",
                 "pre0020": "the port before the VFPU rounding patch (0009-vfpu-rounding; old 0020)"}
        tags = sorted({k for s_ in sites for k in s_[0].get("_ports", {})})
        for which in ["port"] + tags:
            label = names.get(which, f"the port, {which}")
            gg = other_groups(sites, which).get(g, [])
            ok, n = port_agreement(gg)
            if n:
                print(f"    {label:34} {ok:8}/{n} {100.0 * ok / n:8.3f}% (against PPSSPP)")
        if kind == "vrot":
            lanes = {}
            for p in probs:
                lanes.setdefault(rot_lane(p[0], p[2]), []).append(p)
            for what, ps in sorted(lanes.items()):
                for name, fn in kind_models(kind).items():
                    ok, tot, _ = evaluate_other(fn, ps)
                    print(f"    {what} lanes, {name:28} {ok:8}/{tot}")


def cmd_search(d, limit):
    for path, meta, sites in datasets(d):
        print(set_title(path, meta))
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
        for ok, lab in res[:10]:
            print(f"  {lab:34} {ok}/{len(probs)} {100.0 * ok / len(probs):.3f}%")


def hw_of(p):
    """The PSP's rule (the header's default mode) for problem p: the hardware dot product for the dot kinds, the
    task 048 kinds' HW_048 model otherwise."""
    site = p[0]
    if site["kind"] in DOT_KINDS:
        return special_dot(p[3], p[4]) if any(is_special(x) for x in list(p[3]) + list(p[4])) \
            else model_fn(*HW)(p[3], p[4])
    return kind_models(site["kind"])[HW_048[site["kind"]]](p[3], p[4], p[2], site)


def mode_line(sites, g, tag=None):
    """The port's results under the two rounding modes of task 047 (vfpu_probe.py port --modes ppsspp,psp):
    the test mode against PPSSPP, the default against the PSP's rule. None when the set has no such files."""
    out = []
    pre = f"{tag}." if tag else ""
    for which, ref, label in ((pre + "ppsspp", None, "test mode = PPSSPP"), (pre + "psp", hw_of, "default mode = hw")):
        groups = by_group(sites, which)
        groups.update(other_groups(sites, which))
        probs = [p for p in groups.get(g, []) if p[6] is not None]
        if not probs:
            continue
        ok = sum(1 for p in probs if p[6] == (p[5] if ref is None else ref(p)))
        out.append(f"{label} {ok}/{len(probs)} ({100.0 * ok / len(probs):.3f}%)")
    return "; ".join(out) or None


def cmd_check(d, tag=None):
    sets = datasets(d)
    if not sets:
        print(f"vfpu_model: no samples under {d} (tools/vfpu_probe.py sample)")
        return 1
    fails = 0
    for path, meta, sites in sets:
        core = core_of(meta)
        rule, rule48 = RULES.get(core), RULES_048.get(core)
        print(set_title(path, meta))
        dots, others = by_group(sites), other_groups(sites)
        if (dots and rule is None) or (others and rule48 is None):
            print(f"  no rule for CPU core {core}")
            fails += 1
            continue
        for g, probs in dots.items():
            kind = probs[0][0]["kind"]
            ok, tot, bad = evaluate_rule(rule, probs)
            have = [p for p in probs if p[6] is not None]
            port_ok = sum(1 for p in have if p[6] == p[5])
            print(f"  {g:40} {rule_label(rule, kind):24} {ok}/{tot} ({100.0 * ok / tot:.3f}%)"
                  + (f"; the port (.port.csv) {port_ok}/{len(have)} ({100.0 * port_ok / len(have):.3f}%)"
                     if have else ""))
            ml = mode_line(sites, g, tag)
            if ml:
                print(f"  {'':40} the port{f' ({tag})' if tag else ' since patch 0009-vfpu-rounding (task 047's 0020)'}: {ml}")
            for p, got in bad[:20]:
                print("    FAIL " + fmt_row(p, got))
            fails += len(bad)
        for g, probs in others.items():
            kind = probs[0][0]["kind"]
            name = rule48[kind]
            ok, tot, bad = evaluate_other(kind_models(kind)[name], probs)
            port_ok, port_n = port_agreement(probs)
            print(f"  {g + ' (result lanes)':40} {name:24} {ok}/{tot} ({100.0 * ok / tot:.3f}%)"
                  + (f"; the port (.port.csv) {port_ok}/{port_n} ({100.0 * port_ok / port_n:.3f}%)" if port_n else ""))
            ml = mode_line(sites, g, tag)
            if ml:
                print(f"  {'':40} the port{f' ({tag})' if tag else ' since patch 0009-vfpu-rounding (task 047's 0020)'}: {ml}")
            for p, got in bad[:20]:
                print("    FAIL " + other_fmt(p, got))
            fails += len(bad)
        print("  transcendentals (the port's helper against PPSSPP):")
        trans_summary(sites)
    print(f"vfpu_model --check: {'PASS' if not fails else f'FAIL ({fails} results)'}")
    return 0 if not fails else 1


def cmd_diff(d, which, limit):
    """Every sampled result where the port's (<ADDR>.port.<which>.csv) differs from PPSSPP's, in time order: the
    sites a divergence can start from (task 048: the Karbonis attribution)."""
    for path, meta, sites in datasets(d):
        print(set_title(path, meta))
        rows = []
        groups = by_group(sites, which)
        groups.update(other_groups(sites, which))
        total = 0
        for g, probs in groups.items():
            have = [p for p in probs if p[6] is not None]
            total += len(have)
            for p in have:
                if p[6] != p[5]:
                    rows.append((p[0]["_usec"][p[1]], p))
        rows.sort(key=lambda r: r[0])
        arm = meta.get("run", {}).get("armed_usec")
        print(f"  {len(rows)} of {total} results differ (the port: <ADDR>.port.{which}.csv)")
        per = {}
        for usec, p in rows:
            per.setdefault((p[0]["addr"], p[0]["mnemonic"], p[0].get("function")), []).append(usec)
        for (addr, mn, fn), us in sorted(per.items(), key=lambda kv: kv[1][0]):
            print(f"  {addr} {mn:9} {str(fn):22} {len(us):6} differ, the first at usec {us[0]}"
                  + (f" (READY + {(us[0] - arm) / 1e6:.3f} s)" if arm else ""))
        for usec, p in rows[:limit]:
            fmt = other_fmt if p[0]["kind"] in NEW_KINDS else fmt_row
            print(f"    usec {usec} " + fmt(p))


def autotest_cases():
    """pspautotests vector.c's SVV dot products (vdot/vhdp .p .t .q over its first five test vectors) with the
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
                cases.append((f"{op}.{sz} v{i}.v{j}", s, t, vals[k], 4 not in (i, j)))
                k += 1
    return cases


AUTOTEST_VECTORS = [(1.0, 2.0, 3.0, 4.0), (5.0, 6.0, -7.0, -8.0), (-1.0, -2.0, -3.0, -4.0), (-4.0, -5.0, 6.0, 7.0),
                    (-0.1, 1000.0, float("inf"), 0.0)]


def autotest_cases_048():
    """pspautotests vector.c's vcrs.t, vcrsp.t, vqmul.q (C000 = op(C100, C200) over the first five test vectors
    each way, 25 cases) and vfad, vavg .p .t .q (S000 = op(C100), 5 cases each) with a real PSP's printed results
    (vector.expected): {kind: [(label, s, t, [result lanes as printed], integer operands)]}."""
    exp = AUTOTESTS / "vector.expected"
    if not exp.exists():
        return None
    lines = {}
    for line in exp.read_text().splitlines():
        m = re.match(r"(vcrs|vcrsp|vqmul|vfad|vavg)_([ptq]): (.*)$", line)
        if m:
            lines.setdefault((m[1], m[2]), []).append(m[3].split(","))
    vec = [[f2b(v) for v in x] for x in AUTOTEST_VECTORS]
    out = {}
    for (op, sz), vals in lines.items():
        n = {"p": 2, "t": 3, "q": 4}[sz]
        if op in ("vfad", "vavg"):
            for i in range(5):
                out.setdefault(op, []).append((f"{op}.{sz} v{i}", vec[i][:n], [], vals[i][:1], i != 4))
        else:
            k = 0
            for i in range(5):
                for j in range(5):
                    out.setdefault(op, []).append((f"{op}.{sz} v{i}.v{j}", vec[i][:n], vec[j][:n], vals[k][:n],
                                                   4 not in (i, j)))
                    k += 1
    return out


def rot_autotests():
    """vrot.expected (pspautotests, a real PSP): the sine and cosine of each angle it tests, as bits."""
    exp = AUTOTESTS / "vrot.expected"
    if not exp.exists():
        return None
    out, angle = {}, None
    for line in exp.read_text().splitlines():
        m = re.match(r"== vrot\.p C000, S100, angle (\S+) ==", line)
        if m:
            angle = f2b(float(m[1]))
            continue
        m = re.match(r"imm  0: ([0-9a-f]{8}),([0-9a-f]{8}),", line)   # imm 0: lane 0 the cosine, lane 1 the sine
        if m and angle is not None:
            out[angle] = (int(m[2], 16), int(m[1], 16))
            angle = None
    return out


def selftest():
    fails = []
    rnd = random.Random(47)
    # 1. round_exact against the platform's double-to-float conversion (round to nearest even), normal range.
    for _ in range(20000):
        x = rnd.uniform(-1, 1) * 2.0 ** rnd.randint(-100, 100)
        want = f2b(x)
        if (want >> 23) & 0xFF in (0, 255):
            continue
        mant, ex = math.frexp(x)
        got = round_exact(int(mant * (1 << 53)), ex - 53)
        if got != want:
            fails.append(f"round_exact {x!r}: {got:08X} != {want:08X}")
            break
    # 2. fmul/fadd against single-precision arithmetic through doubles (exact there for these ranges).
    for _ in range(20000):
        a = f2b(rnd.uniform(-4, 4) * 2.0 ** rnd.randint(-20, 20))
        b = f2b(rnd.uniform(-4, 4) * 2.0 ** rnd.randint(-20, 20))
        if fmul(a, b) != f2b(b2f(a) * b2f(b)):
            fails.append(f"fmul {a:08X} {b:08X}")
            break
        if abs(((a >> 23) & 0xFF) - ((b >> 23) & 0xFF)) < 25 and fadd(a, b) != f2b(b2f(a) + b2f(b)):
            fails.append(f"fadd {a:08X} {b:08X}")
            break
    # 3. ffma: one rounding of the exact a*b+c, against Fraction where a double holds the exact value.
    for _ in range(5000):
        a, b, c = (f2b(rnd.uniform(-2, 2) * 2.0 ** rnd.randint(-8, 8)) for _ in range(3))
        exact = Fraction(b2f(a)) * Fraction(b2f(b)) + Fraction(b2f(c))
        if exact and Fraction(float(exact)) == exact and ffma(a, b, c) != f2b(float(exact)):
            fails.append(f"ffma {a:08X} {b:08X} {c:08X}")
            break
    # 4. The port's model b against the corpus's own code: tools/vfpu_probe.py port's harness results are checked in
    #    --report; here task 046's example, the squared length of (-0.852767, 0.00194, 0.033974).
    v = [0xBF5A4EEF, 0x3AFE5500, 0x3D0B28A3]
    if dot_port_ct(v, v) != 0x3F3A766C:
        fails.append(f"task 046 example: model b gives {dot_port_ct(v, v):08X}, the port gave 3F3A766C")
    if dot_chain(v, v) != 0x3F3A766B:
        fails.append(f"task 046 example: chain gives {dot_chain(v, v):08X}, PPSSPP gave 3F3A766B")
    # 5. pspautotests' results from a real PSP for vdot and vhdp. The hardware model must give all 150; every rule
    #    must give the cases whose operands are integers (vectors 0 to 3: exact in every model).
    cases = autotest_cases()
    if cases is None:
        print(f"selftest: {AUTOTESTS / 'vector.expected'} not found; skipped the hardware cases")
    else:
        for name, params in [HW, ("chain", None), ("a", None), ("exact", None)]:
            fn = model_fn(name, params)
            bad, bad_int = [], []
            for label, s, t, want, integer in cases:
                got = special_dot(s, t) if any(is_special(x) for x in s + t) else fn(s, t)
                if f"{b2f(got):f}" != want:
                    bad.append(f"{label} {b2f(got):f} (PSP {want})")
                    if integer:
                        bad_int.append(label)
            print(f"selftest: vector.expected {len(cases) - len(bad)}/{len(cases)} with {model_label(name, params)}"
                  + (f"; differs on {', '.join(bad)}" if bad else ""))
            if (name, params) == HW and bad:
                fails.append(f"vector.expected: the hardware model misses {len(bad)}")
            if bad_int:
                fails.append(f"vector.expected: {model_label(name, params)} misses integer cases {bad_int}")
    # 6. Task 048: pspautotests' vcrs, vcrsp, vqmul, vfad and vavg results from a real PSP. PPSSPP's rule (RULES_048)
    #    and the PSP's rule (HW_048) must give every case whose operands are integers (vectors 0 to 3); the counts
    #    over all the cases are reported for every model.
    cases48 = autotest_cases_048()
    if cases48:
        for kind in ("vcrs", "vcrsp", "vqmul", "vfad", "vavg"):
            models = kind_models(kind)
            required = {RULES_048[1][kind], HW_048[kind]}
            for name, fn in models.items():
                bad, bad_int, total = [], [], 0
                for label, sv, tv, want, integer in cases48.get(kind, []):
                    site = {"kind": kind, "length": len(sv), "mnemonic": label.split()[0]}
                    for lane, w in enumerate(want):
                        total += 1
                        got = fn(sv, tv, lane, site)
                        if f"{b2f(got):f}" != w:
                            bad.append(f"{label} lane {lane} {b2f(got):f} (PSP {w})")
                            if integer:
                                bad_int.append(f"{label} lane {lane}")
                print(f"selftest: vector.expected {kind} {total - len(bad)}/{total} with {name}"
                      + (" (required on integers)" if name in required else "")
                      + (f"; differs on {', '.join(bad[:6])}{' ...' if len(bad) > 6 else ''}" if bad else ""))
                if name in required and bad_int:
                    fails.append(f"vector.expected: {kind} {name} misses integer cases {bad_int[:6]}")
    rot = rot_autotests()
    if rot:
        for name, (sinf_, cosf_) in ROT_FORMS.items():
            hits = sum((sinf_(x) == sn) + (cosf_(x) == cs) for x, (sn, cs) in rot.items())
            print(f"selftest: vrot.expected (a real PSP) {hits}/{2 * len(rot)} sines and cosines with {name}: "
                  + ", ".join(f"{b2f(x):g} -> sin {sinf_(x):08X} cos {cosf_(x):08X} (PSP {sn:08X} {cs:08X})"
                              for x, (sn, cs) in rot.items()))
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
    ap.add_argument("--diff", nargs="?", const=str(DEFAULT_DIR), metavar="DIR",
                    help="the sampled results where the port (--which) differs from PPSSPP, in time order")
    ap.add_argument("--which", default="ppsspp", help="--diff: the port file, <ADDR>.port.<which>.csv")
    ap.add_argument("--tag", help="--check: the port's results under both modes from <ADDR>.port.<tag>.<mode>.csv "
                                  "(vfpu_probe.py port --modes ppsspp,psp --tag T, e.g. a header experiment)")
    ap.add_argument("--limit", type=int, default=3000, help="--search: rows per group; --diff: rows listed")
    a = ap.parse_args()
    rc = 0
    if a.selftest:
        rc |= selftest()
    if a.report:
        cmd_report(a.report)
    if a.search:
        cmd_search(a.search, a.limit)
    if a.check:
        rc |= cmd_check(a.check, a.tag)
    if a.diff:
        cmd_diff(a.diff, a.which, a.limit)
    if not (a.selftest or a.report or a.search or a.check or a.diff):
        ap.print_help()
    sys.exit(rc)


if __name__ == "__main__":
    main()
