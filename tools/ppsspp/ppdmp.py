#!/opt/homebrew/bin/python3
"""Reads PPSSPP GE dumps (.ppdmp, format versions 5 and 6) and prints what a frame draws.

Python 3 stdlib plus the `zstd` command line tool (brew) for the two compressed blocks. No PPSSPP code is copied;
the layout was learned by reading PPSSPP's GPU/Debugger/Record.cpp, RecordFormat.h and Playback.cpp:

  header   char magic[8] "PPSSPPGE", u32 version, char gameID[9], u8 pad[3]
  u32 command count, u32 pushbuf size
  u32 size + zstd frame: command count x {u8 type, u32 sz, u32 ptr} (packed, 9 bytes)
  u32 size + zstd frame: the push buffer every command's (ptr, sz) points into

Commands: INIT (the GE state: 17 words, then the context command words), REGISTERS (raw GE command words, applied in
order; a PRIM word closes a draw), VERTICES/INDICES (the data of the next PRIM), TEXTURE0-7 (texture bytes from RAM),
FRAMEBUF0-7 (a texture in VRAM: {u32 addr, s32 bufw, u32 flags, u32 pad} then the VRAM bytes as they were at that
draw; flags 1 = the address was a render target earlier in the dump, 2 = unchanged since last sent, 4 = drawn to),
CLUT/CLUTADDR, TRANSFERSRC (a block transfer's source bytes), MEMSET/MEMCPYDEST/MEMCPYDATA (CPU writes to VRAM),
DISPLAY (sceDisplaySetFrameBuf: {u32 addr, s32 stride, s32 format}), EDRAMTRANS.

Usage:
  ppdmp.py summary DUMP            header and command counts
  ppdmp.py draws DUMP [--all] [--vt]   one line per draw (only render-target changes and VRAM binds unless --all;
                                   --vt adds the decoded vertex type, cull, depth clamp and MINZ-MAXZ)
  ppdmp.py passes DUMP             draws grouped by render target, with every VRAM texture bind and what it aliases
  ppdmp.py verts DUMP N            draw N in full: state words and every vertex
  ppdmp.py gelist LOG [--all] [--vt]   the same draw lines from our port's PURE_TRACE_GE_LIST output (no vertices)
  ppdmp.py tex DUMP N OUT.png      writes the VRAM texture bound at draw N as a PNG (RGBA, linear, unswizzled)
  ppdmp.py cover DUMP [OUT.png] [--highlight A-B,C,...]
                                   which draw is visible where: a coverage-only rasteriser of the frame's 3D draws,
                                   pixels per draw (last opaque writer, last writer), decoded vertex types; OUT.png
                                   colours each pixel by its last opaque writer (only the highlighted draws)
"""
import math, struct, subprocess, sys

TYPES = {0: "INIT", 1: "REGISTERS", 2: "VERTICES", 3: "INDICES", 4: "CLUT", 5: "TRANSFERSRC", 6: "MEMSET",
         7: "MEMCPYDEST", 8: "MEMCPYDATA", 9: "DISPLAY", 10: "CLUTADDR", 11: "EDRAMTRANS"}
for _i in range(8):
    TYPES[0x10 + _i] = f"TEXTURE{_i}"
    TYPES[0x18 + _i] = f"FRAMEBUF{_i}"

# Context command ranges INIT saves after its 17 leading words (GPUState.cpp contextCmdRanges).
CONTEXT_RANGES = [(0x00, 0x02), (0x10, 0x10), (0x12, 0x28), (0x2C, 0x33), (0x36, 0x38), (0x42, 0x4D),
                  (0x50, 0x51), (0x53, 0x58), (0x5B, 0xB5), (0xB8, 0xC3), (0xC5, 0xD0), (0xD2, 0xE9),
                  (0xEB, 0xEC), (0xEE, 0xEE), (0xF0, 0xF6), (0xF8, 0xF9)]

PRIM_NAMES = ["points", "lines", "linestrip", "tris", "tristrip", "trifan", "rects", "prim7"]
FB_FORMATS = ["565", "5551", "4444", "8888"]
TEX_FORMATS = ["565", "5551", "4444", "8888", "CLUT4", "CLUT8", "CLUT16", "CLUT32", "DXT1", "DXT3", "DXT5"]
TEX_BITS = [16, 16, 16, 32, 4, 8, 16, 32, 4, 8, 8]
SRC_FACTORS = ["DST", "1-DST", "SA", "1-SA", "DA", "1-DA", "2SA", "1-2SA", "2DA", "1-2DA", "FIXA"]
DST_FACTORS = ["SRC", "1-SRC", "SA", "1-SA", "DA", "1-DA", "2SA", "1-2SA", "2DA", "1-2DA", "FIXB"]
BLEND_EQ = ["add", "sub", "rsub", "min", "max", "abs"]
TEXFUNC = ["modulate", "decal", "blend", "replace", "add"]
ZFUNC = ["never", "always", "eq", "ne", "lt", "le", "gt", "ge"]
SHOW_VT = False   # main() sets it for --vt


def f24(w):
    """A GE 24-bit float: the top 24 bits of an IEEE single."""
    return struct.unpack("<f", struct.pack("<I", (w & 0xFFFFFF) << 8))[0]


def zstd_decompress(data):
    return subprocess.run(["zstd", "-d", "-c", "-q"], input=data, stdout=subprocess.PIPE, check=True).stdout


def load(path):
    raw = open(path, "rb").read()
    magic, version = raw[:8], struct.unpack_from("<I", raw, 8)[0]
    if magic != b"PPSSPPGE" or not 5 <= version <= 6:
        sys.exit(f"{path}: not a PPSSPP GE dump of version 5 or 6 (magic {magic!r}, version {version})")
    game = raw[12:21].split(b"\0")[0].decode()
    count, bufsz = struct.unpack_from("<II", raw, 24)
    pos = 32
    csz = struct.unpack_from("<I", raw, pos)[0]
    cmds_raw = zstd_decompress(raw[pos + 4:pos + 4 + csz])
    pos += 4 + csz
    psz = struct.unpack_from("<I", raw, pos)[0]
    pushbuf = zstd_decompress(raw[pos + 4:pos + 4 + psz])
    if len(cmds_raw) != count * 9 or len(pushbuf) != bufsz:
        sys.exit(f"{path}: truncated ({len(cmds_raw)} of {count * 9} command bytes, {len(pushbuf)} of {bufsz})")
    cmds = [struct.unpack_from("<BII", cmds_raw, i * 9) for i in range(count)]
    return {"version": version, "game": game, "cmds": cmds, "pushbuf": pushbuf}


class State:
    """The GE registers, one word per opcode, as the dump sets them."""

    def __init__(self):
        self.r = [op << 24 for op in range(256)]
        self.world, self.view, self.proj = [0.0] * 12, [0.0] * 12, [0.0] * 16
        self.mtx_at = {0x3A: 0, 0x3C: 0, 0x3E: 0}

    def init(self, buf, ptr):
        words = struct.unpack_from("<512I", buf, ptr)
        i = 17
        for lo, hi in CONTEXT_RANGES:
            for op in range(lo, hi + 1):
                self.r[op] = words[i]
                i += 1
        # Then the matrices, saved as the commands that load them (bone, world, view, projection, texgen), up to an
        # END (GPUgstate::Save with a saved-context version above 0, which version 6 dumps carry).
        if words[i] >> 24 == 0x2A:
            for w in words[i:]:
                if w >> 24 == 0x0C:
                    break
                self.matrix(w)

    def matrix(self, w):
        """The world (0x3A/0x3B), view (0x3C/0x3D) and projection (0x3E/0x3F) matrix loads."""
        op = w >> 24
        if op in self.mtx_at:
            self.mtx_at[op] = w & 0xF
        elif op - 1 in self.mtx_at:
            m = {0x3B: self.world, 0x3D: self.view, 0x3F: self.proj}[op]
            k = self.mtx_at[op - 1]
            if k < len(m):
                m[k] = f24(w)
            self.mtx_at[op - 1] = k + 1

    def v(self, op):
        return self.r[op] & 0xFFFFFF

    def fb(self):
        return 0x04000000 | (self.v(0x9C) & 0x1FFFF0)

    def fb_stride(self):
        return self.v(0x9D) & 0x7FC

    def fb_fmt(self):
        return self.v(0xD2) & 3

    def z(self):
        return 0x04000000 | (self.v(0x9E) & 0x1FFFF0)

    def z_stride(self):
        return self.v(0x9F) & 0x7FC

    def tex_addr(self, level=0):
        return (self.v(0xA0 + level) & 0xFFFFF0) | ((self.v(0xA8 + level) << 8) & 0x0F000000)

    def tex_bufw(self, level=0):
        return self.v(0xA8 + level) & 0x7FF

    def tex_size(self, level=0):
        s = self.v(0xB8 + level)
        return 1 << (s & 0xF), 1 << ((s >> 8) & 0xF)

    def tex_fmt(self):
        return self.v(0xC3) & 0xF

    def swizzled(self):
        return self.v(0xC2) & 1

    def scissor(self):
        a, b = self.v(0xD4), self.v(0xD5)
        return (a & 0x3FF, (a >> 10) & 0x3FF, b & 0x3FF, (b >> 10) & 0x3FF)

    def on(self, op):
        return self.v(op) & 1


def comp_size(kind):
    return {0: 0, 1: 1, 2: 2, 3: 4}[kind]


def vertex_layout(vt):
    """Offsets of (tc, color, pos) and the vertex size, by the PSP's packing rules."""
    tc, col, nrm, pos = vt & 3, (vt >> 2) & 7, (vt >> 5) & 3, (vt >> 7) & 3
    wt, wcount = (vt >> 9) & 3, ((vt >> 14) & 7) + 1
    off, biggest = 0, 1

    def place(size, count):
        nonlocal off, biggest
        if not size:
            return None
        off = (off + size - 1) // size * size
        at = off
        off += size * count
        biggest = max(biggest, size)
        return at

    place(comp_size(wt), wcount)
    o_tc = place(comp_size(tc), 2)
    o_col = place({4: 2, 5: 2, 6: 2, 7: 4}.get(col, 0), 1)
    place(comp_size(nrm), 3)
    o_pos = place(comp_size(pos), 3)
    size = (off + biggest - 1) // biggest * biggest
    return o_tc, o_col, o_pos, size


def read_comp(buf, at, kind, signed, through):
    if kind == 1:
        return struct.unpack_from("<b" if signed and not through else "<B", buf, at)[0]
    if kind == 2:
        return struct.unpack_from("<h" if signed or not through else "<H", buf, at)[0]
    return struct.unpack_from("<f", buf, at)[0]


def decode_vertices(state, verts, indices, count):
    """Returns [(x, y, u, v, colour)] for the PRIM's vertices (raw values; through mode is screen space)."""
    vt = state.v(0x12)
    through = (vt >> 23) & 1
    tc, col, pos = vt & 3, (vt >> 2) & 7, (vt >> 7) & 3
    o_tc, o_col, o_pos, size = vertex_layout(vt)
    idx_kind = (vt >> 11) & 3
    out = []
    if verts is None or size == 0:
        return out
    for i in range(count):
        n = i
        if idx_kind and indices is not None:
            n = struct.unpack_from({1: "<B", 2: "<H", 3: "<I"}[idx_kind], indices, i * comp_size(idx_kind))[0]
        base = n * size
        if base + size > len(verts):
            break
        x = y = u = v = None
        if o_pos is not None:
            k = comp_size(pos)
            x = read_comp(verts, base + o_pos, pos, True, through)
            y = read_comp(verts, base + o_pos + k, pos, True, through)
        if o_tc is not None:
            k = comp_size(tc)
            u = read_comp(verts, base + o_tc, tc, False, True)
            v = read_comp(verts, base + o_tc + k, tc, False, True)
        c = None
        if o_col is not None:
            c = struct.unpack_from("<I" if col == 7 else "<H", verts, base + o_col)[0]
        out.append((x, y, u, v, c))
    return out


def bounds(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    lo, hi = min(vals), max(vals)
    f = (lambda q: f"{q:g}") if isinstance(lo, float) or isinstance(hi, float) else str
    return f"{f(lo)}..{f(hi)}"


def blend_desc(s):
    if not s.on(0x21):
        return "opaque"
    b = s.v(0xDF)
    sf, df, eq = b & 0xF, (b >> 4) & 0xF, (b >> 8) & 7
    sname = SRC_FACTORS[sf] if sf < len(SRC_FACTORS) else f"s{sf}"
    dname = DST_FACTORS[df] if df < len(DST_FACTORS) else f"d{df}"
    if sf == 10:
        sname = f"FIXA {s.v(0xE0):06x}"
    if df == 10:
        dname = f"FIXB {s.v(0xE1):06x}"
    return f"{BLEND_EQ[eq] if eq < 6 else eq}({sname}, {dname})"


def walk(dump):
    """Replays the dump and yields events: ('draw', dict), ('display', dict), ('transfer', dict), ('mem', dict)."""
    buf, s = dump["pushbuf"], State()
    pending = {"verts": None, "indices": None, "fbtex": {}, "tex": {}}
    memcpy_dest = None
    draw_no = 0
    for ctype, sz, ptr in dump["cmds"]:
        name = TYPES.get(ctype, f"type{ctype}")
        if name == "INIT":
            s.init(buf, ptr)
        elif name == "VERTICES":
            pending["verts"] = buf[ptr:ptr + sz]
        elif name == "INDICES":
            pending["indices"] = buf[ptr:ptr + sz]
        elif name.startswith("FRAMEBUF"):
            lvl = ctype - 0x18
            addr, bufw, flags, _ = struct.unpack_from("<IiII", buf, ptr)
            pending["fbtex"][lvl] = {"addr": addr, "bufw": bufw, "flags": flags, "ptr": ptr + 16, "sz": sz - 16}
        elif name.startswith("TEXTURE"):
            pending["tex"][ctype - 0x10] = {"sz": sz}
        elif name == "DISPLAY":
            addr, stride, fmt = struct.unpack_from("<Iii", buf, ptr)
            yield "display", {"addr": addr, "stride": stride, "fmt": fmt, "after_draw": draw_no}
        elif name == "MEMSET":
            dest, val, n = struct.unpack_from("<IiI", buf, ptr)
            yield "mem", {"kind": "memset", "dest": dest, "value": val, "size": n, "after_draw": draw_no}
        elif name == "MEMCPYDEST":
            memcpy_dest = struct.unpack_from("<I", buf, ptr)[0]
        elif name == "MEMCPYDATA":
            yield "mem", {"kind": "memcpy", "dest": memcpy_dest, "size": sz, "after_draw": draw_no}
        elif name == "REGISTERS":
            for (w,) in struct.iter_unpack("<I", buf[ptr:ptr + sz]):
                op = w >> 24
                if op in (0x04, 0x05, 0x06):
                    count = w & 0xFFFF if op == 0x04 else (w & 0xFF) * ((w >> 8) & 0xFF)
                    yield "draw", make_draw(draw_no, s, w, count, pending, buf)
                    draw_no += 1
                    pending = {"verts": None, "indices": None, "fbtex": {}, "tex": {}}
                elif op == 0xEA:
                    yield "transfer", make_transfer(s, w, draw_no)
                else:
                    s.r[op] = w
                    s.matrix(w)
        # CLUT, CLUTADDR, TRANSFERSRC, EDRAMTRANS carry data only.


def make_transfer(s, w, after):
    src = (s.v(0xB2) & 0xFFFFF0) | ((s.v(0xB3) & 0xFF0000) << 8)
    dst = (s.v(0xB4) & 0xFFFFF0) | ((s.v(0xB5) & 0xFF0000) << 8)
    sp, dp, size = s.v(0xEB), s.v(0xEC), s.v(0xEE)
    return {"src": src, "src_stride": s.v(0xB3) & 0x7F8, "src_xy": (sp & 0x3FF, (sp >> 10) & 0x3FF),
            "dst": dst, "dst_stride": s.v(0xB5) & 0x7F8, "dst_xy": (dp & 0x3FF, (dp >> 10) & 0x3FF),
            "w": (size & 0x3FF) + 1, "h": ((size >> 10) & 0x3FF) + 1, "bpp": 4 if w & 1 else 2, "after_draw": after}


def make_draw(n, s, w, count, pending, buf):
    op = w >> 24
    prim = PRIM_NAMES[(w >> 16) & 7] if op == 0x04 else ("bezier" if op == 0x05 else "spline")
    vt = s.v(0x12)
    clear = s.v(0xD3)
    d = {
        "n": n, "prim": prim, "count": count, "through": (vt >> 23) & 1,
        "fb": s.fb(), "fb_fmt": s.fb_fmt(), "fb_stride": s.fb_stride(), "z": s.z(), "z_stride": s.z_stride(),
        "clear": clear & 1, "clear_bits": (clear >> 8) & 7,
        "tex_on": s.on(0x1E), "tex": None, "blend": blend_desc(s),
        "ztest": (ZFUNC[s.v(0xDE) & 7] if s.on(0x23) else "off"), "zwrite": not (s.v(0xE7) & 1),
        "atest": (f"{ZFUNC[s.v(0xDB) & 7]} ref {(s.v(0xDB) >> 8) & 0xFF:02x}" if s.on(0x22) else "off"),
        "ctest": s.on(0x27), "mask_rgb": s.v(0xE8), "mask_a": s.v(0xE9) & 0xFF,
        "scissor": s.scissor(), "texfunc": TEXFUNC[s.v(0xC9) & 7] if (s.v(0xC9) & 7) < 5 else str(s.v(0xC9) & 7),
        "texfunc_rgba": (s.v(0xC9) >> 8) & 1, "texfunc_double": (s.v(0xC9) >> 16) & 1,
        "filter": s.v(0xC6), "wrap": s.v(0xC7), "vtype": vt,
        "matcolor": None,
    }
    if d["tex_on"] or (vt & 3):
        addr = s.tex_addr(0)
        tw, th = s.tex_size(0)
        fmt = s.tex_fmt()
        t = {"addr": addr, "w": tw, "h": th, "bufw": s.tex_bufw(0), "fmt": fmt, "swizzle": s.swizzled(),
             "vram": 0x04000000 <= (addr & 0x0FFFFFFF) < 0x04200000, "flags": None, "ptr": None, "sz": None,
             "levels": ((s.v(0xC2) >> 16) & 7) + 1}
        fb = pending["fbtex"].get(0)
        if fb is not None:
            t.update(flags=fb["flags"], ptr=fb["ptr"], sz=fb["sz"], bufw=fb["bufw"])
        d["tex"] = t
    verts = decode_vertices(s, pending["verts"], pending["indices"], count)
    d["verts"] = verts
    d["regs"] = list(s.r)
    d["mtx"] = (list(s.world), list(s.view), list(s.proj))
    d["vbytes"], d["ibytes"] = pending["verts"], pending["indices"]
    d["xy"] = (bounds([v[0] for v in verts]), bounds([v[1] for v in verts]))
    d["uv"] = (bounds([v[2] for v in verts]), bounds([v[3] for v in verts]))
    cols = {v[4] for v in verts if v[4] is not None}
    d["colours"] = sorted(cols)[:3] if cols else None
    if not (vt >> 2) & 7:
        d["matcolor"] = (s.v(0x55), s.v(0x58) & 0xFF)  # material ambient colour and alpha stand in for a vertex colour
    return d


def fmt_tex(t, targets):
    if t is None:
        return "-"
    fmt = TEX_FORMATS[t["fmt"]] if t["fmt"] < len(TEX_FORMATS) else str(t["fmt"])
    sw = " swz" if t["swizzle"] else ""
    out = f"tex 0x{t['addr']:08x} {fmt} {t['w']}x{t['h']} bufw {t['bufw']}{sw}"
    if t["levels"] > 1:
        out += f" mips {t['levels']}"
    if t["vram"]:
        out += f" vramflags {t['flags']}"
        al = aliases(t, targets)
        if al:
            out += " ALIASES " + "; ".join(al)
    return out


def tex_bytes(t):
    bits = TEX_BITS[t["fmt"]] if t["fmt"] < len(TEX_BITS) else 32
    bufw = t["bufw"] or t["w"]
    return (bits * (bufw * t["h"] + max(0, t["w"] - bufw))) // 8


def aliases(t, targets):
    """Earlier colour or depth targets whose drawn extent overlaps the texture's bytes."""
    a0 = t["addr"] & 0x041FFFFF
    a1 = a0 + tex_bytes(t)
    out = []
    for key, tg in targets.items():
        if tg["lo"] < a1 and a0 < tg["hi"]:
            kind, addr = key
            out.append(f"{kind} 0x{addr:08x} ({tg['desc']}, draws {tg['first']}-{tg['last']})")
    return out


def note_target(targets, d):
    x2, y2 = d["scissor"][2], d["scissor"][3]
    bpp = 4 if d["fb_fmt"] == 3 else 2
    key = ("colour", d["fb"])
    span = bpp * (d["fb_stride"] * y2 + x2 + 1)
    tg = targets.setdefault(key, {"lo": d["fb"], "hi": d["fb"], "first": d["n"], "last": d["n"],
                                  "desc": f"{FB_FORMATS[d['fb_fmt']]} stride {d['fb_stride']}"})
    tg["hi"] = max(tg["hi"], d["fb"] + span)
    tg["last"] = d["n"]
    depth = (not d["clear"] and d["zwrite"] and d["ztest"] != "off") or (d["clear"] and d["clear_bits"] & 4)
    if depth:
        key = ("depth", d["z"])
        span = 2 * (d["z_stride"] * y2 + x2 + 1)
        tg = targets.setdefault(key, {"lo": d["z"], "hi": d["z"], "first": d["n"], "last": d["n"],
                                      "desc": f"z16 stride {d['z_stride']}"})
        tg["hi"] = max(tg["hi"], d["z"] + span)
        tg["last"] = d["n"]


def draw_line(d, targets):
    sc = d["scissor"]
    rt = f"fb 0x{d['fb']:08x} {FB_FORMATS[d['fb_fmt']]}/{d['fb_stride']} z 0x{d['z']:08x}/{d['z_stride']}"
    what = "CLEAR" + "".join(c for c, b in zip("CAZ", (1, 2, 4)) if d["clear_bits"] & b) if d["clear"] else d["prim"]
    line = (f"#{d['n']:4d} {rt} sc {sc[0]},{sc[1]}-{sc[2]},{sc[3]} | {what} x{d['count']}"
            f"{' thru' if d['through'] else ''} xy {d['xy'][0]} , {d['xy'][1]}")
    if d["tex_on"]:
        line += f" uv {d['uv'][0]} , {d['uv'][1]} | {fmt_tex(d['tex'], targets)} {d['texfunc']}"
        line += "/rgba" if d["texfunc_rgba"] else "/rgb"
        if d["texfunc_double"]:
            line += " x2"
    line += f" | {d['blend']} z {d['ztest']}{'' if d['zwrite'] else ' nowrite'} at {d['atest']}"
    if d["mask_rgb"] or d["mask_a"]:
        line += f" mask {d['mask_rgb']:06x}/{d['mask_a']:02x}"
    if d["colours"]:
        line += " col " + ",".join(f"{c:08x}" for c in d["colours"])
    elif d["matcolor"]:
        line += f" mat {d['matcolor'][0]:06x}/{d['matcolor'][1]:02x}"
    if SHOW_VT:
        r = d["regs"]
        line += (f" | vt 0x{d['vtype']:06x} {vtype_desc(d['vtype'])} cull {r[0x1D] & 1}/{r[0x9B] & 1}"
                 f" clamp {r[0x1C] & 1} zrange {r[0xD6] & 0xFFFF}-{r[0xD7] & 0xFFFF}")
    return line


def cmd_summary(dump):
    counts = {}
    for ctype, sz, ptr in dump["cmds"]:
        name = TYPES.get(ctype, f"type{ctype}")
        c = counts.setdefault(name, [0, 0])
        c[0] += 1
        c[1] += sz
    print(f"version {dump['version']} game {dump['game']} commands {len(dump['cmds'])} "
          f"pushbuf {len(dump['pushbuf'])} bytes")
    for name, (n, b) in sorted(counts.items()):
        print(f"  {name:12s} {n:6d} commands {b:10d} bytes")


def cmd_draws(dump, show_all):
    targets = {}
    last_rt = None
    for kind, e in walk(dump):
        if kind == "draw":
            rt = (e["fb"], e["fb_fmt"], e["fb_stride"], e["z"])
            vram_tex = e["tex_on"] and e["tex"] and e["tex"]["vram"]
            if show_all or rt != last_rt or vram_tex or e["clear"]:
                print(draw_line(e, targets))
            last_rt = rt
            note_target(targets, e)
        elif kind == "display":
            print(f"DISPLAY 0x{e['addr']:08x} stride {e['stride']} fmt {e['fmt']} (after draw {e['after_draw']})")
        elif kind == "transfer":
            print(f"TRANSFER 0x{e['src']:08x}/{e['src_stride']} @{e['src_xy']} -> 0x{e['dst']:08x}/"
                  f"{e['dst_stride']} @{e['dst_xy']} {e['w']}x{e['h']} bpp {e['bpp']} (after draw {e['after_draw']})")
        else:
            print(f"{e['kind'].upper()} 0x{(e['dest'] or 0):08x} size {e['size']} (after draw {e['after_draw']})")


def cmd_passes(dump):
    targets = {}
    group = None
    groups = []
    others = []
    for kind, e in walk(dump):
        if kind != "draw":
            others.append((kind, e))
            if group is not None:
                group["events"].append((kind, e))
            continue
        rt = (e["fb"], e["fb_fmt"], e["fb_stride"], e["z"], e["z_stride"])
        if group is None or group["rt"] != rt:
            group = {"rt": rt, "first": e["n"], "last": e["n"], "draws": [], "events": []}
            groups.append(group)
        group["last"] = e["n"]
        group["draws"].append(e)
        e["tex_desc"] = fmt_tex(e["tex"], targets) if e["tex_on"] else None
        note_target(targets, e)
    for g in groups:
        fb, fmt, stride, z, zs = g["rt"]
        print(f"draws {g['first']}-{g['last']} ({len(g['draws'])}): fb 0x{fb:08x} {FB_FORMATS[fmt]} stride {stride}, "
              f"z 0x{z:08x} stride {zs}")
        for d in g["draws"]:
            if d["clear"] or (d["tex_on"] and d["tex"] and d["tex"]["vram"]):
                print("   " + draw_line(d, {}) + (f"\n        {d['tex_desc']}" if d["tex_desc"] and "ALIASES" in
                                                    d["tex_desc"] else ""))
        for kind, e in g["events"]:
            if kind == "display":
                print(f"   DISPLAY 0x{e['addr']:08x} stride {e['stride']} fmt {e['fmt']}")
            elif kind == "transfer":
                print(f"   TRANSFER 0x{e['src']:08x} -> 0x{e['dst']:08x} {e['w']}x{e['h']} bpp {e['bpp']}")
            else:
                print(f"   {e['kind'].upper()} 0x{(e['dest'] or 0):08x} size {e['size']}")


def cmd_tex(dump, n, out):
    sys.path.insert(0, __file__.rsplit("/", 2)[0])
    from png import write_png
    for kind, e in walk(dump):
        if kind == "draw" and e["n"] == n:
            t = e["tex"]
            if not t or t["ptr"] is None:
                sys.exit(f"draw {n} has no VRAM texture")
            buf = dump["pushbuf"]
            bufw = t["bufw"]
            px = bytearray()
            for y in range(t["h"]):
                for x in range(t["w"]):
                    if t["fmt"] == 3:
                        o = t["ptr"] + 4 * (y * bufw + x)
                        px += buf[o:o + 4] if o + 4 <= t["ptr"] + t["sz"] else b"\0\0\0\0"
                    else:
                        o = t["ptr"] + 2 * (y * bufw + x)
                        c = struct.unpack_from("<H", buf, o)[0] if o + 2 <= t["ptr"] + t["sz"] else 0
                        if t["fmt"] == 0:
                            r, g, b, a = (c & 31) << 3, ((c >> 5) & 63) << 2, ((c >> 11) & 31) << 3, 255
                        elif t["fmt"] == 1:
                            r, g, b, a = (c & 31) << 3, ((c >> 5) & 31) << 3, ((c >> 10) & 31) << 3, 255 * (c >> 15)
                        else:
                            r, g, b, a = (c & 15) * 17, ((c >> 4) & 15) * 17, ((c >> 8) & 15) * 17, (c >> 12) * 17
                        px += bytes((r, g, b, a))
            write_png(out, t["w"], t["h"], 4, bytes(px))
            print(f"wrote {out}: draw {n}, 0x{t['addr']:08x} {t['w']}x{t['h']} bufw {bufw} fmt {t['fmt']}")
            return
    sys.exit(f"no draw {n}")


def cmd_verts(dump, n):
    for kind, e in walk(dump):
        if kind == "draw" and e["n"] == n:
            print(draw_line(e, {}))
            print(f"vertex type 0x{e['vtype']:06x}, texfilter 0x{e['filter']:06x}, texwrap 0x{e['wrap']:06x}, "
                  f"texmode 0x{e['regs'][0xC2] & 0xFFFFFF:06x}, texscale u/v 0x{e['regs'][0x48] & 0xFFFFFF:06x}/"
                  f"0x{e['regs'][0x49] & 0xFFFFFF:06x}, region2 0x{e['regs'][0x16] & 0xFFFFFF:06x}, "
                  f"offset x/y 0x{e['regs'][0x4C] & 0xFFFFFF:x}/0x{e['regs'][0x4D] & 0xFFFFFF:x}")
            for i, (x, y, u, v, c) in enumerate(e["verts"]):
                col = f" col {c:08x}" if c is not None else ""
                print(f"  v{i:4d} xy ({x}, {y}) uv ({u}, {v}){col}")
            return
    sys.exit(f"no draw {n}")


def vtype_desc(vt):
    """The vertex type word in words: texcoord, colour, normal and position formats, weights, index, morph, through."""
    k = ["-", "s8", "s16", "f32"]
    c = ["-", "?1", "?2", "?3", "565", "5551", "4444", "8888"]
    out = f"uv {k[vt & 3]} col {c[(vt >> 2) & 7]} nrm {k[(vt >> 5) & 3]} pos {k[(vt >> 7) & 3]}"
    if (vt >> 9) & 3:
        out += f" weights {k[(vt >> 9) & 3]} x{((vt >> 14) & 7) + 1}"
    if (vt >> 11) & 3:
        out += f" index {['-', 'u8', 'u16', 'u32'][(vt >> 11) & 3]}"
    if (vt >> 18) & 7:
        out += f" morph x{((vt >> 18) & 7) + 1}"
    if (vt >> 23) & 1:
        out += " through"
    return out


def positions(vt, verts, indices, count):
    """(x, y, z) of each vertex of a PRIM: normalised as the GE reads them in transform mode, raw in through mode
    (where a 16-bit z is unsigned)."""
    through, pos, idx = (vt >> 23) & 1, (vt >> 7) & 3, (vt >> 11) & 3
    _, _, o_pos, size = vertex_layout(vt)
    if verts is None or o_pos is None or not size:
        return []
    k = comp_size(pos)
    fmt = {1: "<b", 2: "<h", 3: "<f"}[pos]
    scale = 1.0 if through else {1: 1 / 128, 2: 1 / 32768, 3: 1.0}[pos]
    out = []
    for i in range(count):
        n = i
        if idx and indices is not None:
            n = struct.unpack_from({1: "<B", 2: "<H", 3: "<I"}[idx], indices, i * comp_size(idx))[0]
        at = n * size + o_pos
        if at + 3 * k > len(verts):
            break
        x, y, z = (struct.unpack_from(fmt, verts, at + a * k)[0] * scale for a in range(3))
        if through and pos == 2:
            z = struct.unpack_from("<H", verts, at + 2 * k)[0]
        out.append((x, y, z))
    return out


def to_clip(p, mtx):
    """Model position to clip space: p x world x view x projection, the PSP's row-vector order."""
    world, view, proj = mtx
    x, y, z = p
    for m in (world, view):
        x, y, z = (x * m[0] + y * m[3] + z * m[6] + m[9], x * m[1] + y * m[4] + z * m[7] + m[10],
                   x * m[2] + y * m[5] + z * m[8] + m[11])
    return tuple(x * proj[i] + y * proj[4 + i] + z * proj[8 + i] + proj[12 + i] for i in range(4))


def clip_near(poly):
    """Clips a polygon of clip-space vertices against z = -w, the only plane the GE clips on."""
    out = []
    for i, a in enumerate(poly):
        b = poly[(i + 1) % len(poly)]
        da, db = a[2] + a[3], b[2] + b[3]
        if da >= 0:
            out.append(a)
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            out.append(tuple(a[j] + (b[j] - a[j]) * t for j in range(4)))
    return out


def raster(tri, scissor, plot):
    """Calls plot(x, y, z) for every pixel centre inside the screen-space triangle (either winding)."""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if area == 0:
        return
    s = 1.0 if area > 0 else -1.0
    # Edge functions e = alpha x + beta y + gamma, each the weight of the opposite vertex times the area.
    edges = [(by - cy, cx - bx, bx * cy - by * cx), (cy - ay, ax - cx, cx * ay - cy * ax),
             (ay - by, bx - ax, ax * by - ay * bx)]
    y0 = max(scissor[1], int(math.floor(min(ay, by, cy))))
    y1 = min(scissor[3], int(math.ceil(max(ay, by, cy))))
    for py in range(y0, y1 + 1):
        fy = py + 0.5
        lo, hi = scissor[0] - 0.5, scissor[2] + 0.5
        for alpha, beta, gamma in edges:
            k = (beta * fy + gamma) * s
            a = alpha * s
            if a > 0:
                lo = max(lo, -k / a)
            elif a < 0:
                hi = min(hi, -k / a)
            elif k < 0:
                hi = lo - 1
        px0, px1 = int(math.ceil(lo - 0.5)), int(math.floor(hi - 0.5))
        if px0 > px1:
            continue
        # z is linear in screen space: the vertices' z weighted by the edge functions.
        za = sum(e[0] * z for e, z in zip(edges, (az, bz, cz))) / area
        zb = sum((e[1] * fy + e[2]) * z for e, z in zip(edges, (az, bz, cz))) / area
        for px in range(px0, px1 + 1):
            plot(px, py, za * (px + 0.5) + zb)


def cmd_cover(dump, out, highlight):
    """Which draw's pixels are visible in the frame: a coverage-only software rasteriser over the colour target of
    the first clear (the GE's rules where they decide coverage: clip on z = -w only, a triangle with a vertex outside
    the 4096-pixel drawing space is dropped, depth clamp, depth range MINZ/MAXZ, the draw's depth test and write).
    No texturing, blending or alpha test, and no culling (both faces drawn; the depth test settles the order).
    Prints, for every transform-mode draw on that target, the pixels it is the last opaque writer of and the pixels
    it is the last writer of at all; writes OUT.png with each pixel coloured by its last opaque writer (only the
    draws in `highlight`, others grey, when given)."""
    sys.path.insert(0, __file__.rsplit("/", 2)[0])
    from png import write_png
    W, H = 480, 272
    depth = [0] * (W * H)
    opaque = [-1] * (W * H)
    last = [-1] * (W * H)
    target, info = None, {}
    zcmp = [lambda a, b: False, lambda a, b: True, lambda a, b: a == b, lambda a, b: a != b, lambda a, b: a < b,
            lambda a, b: a <= b, lambda a, b: a > b, lambda a, b: a >= b]
    for kind, d in walk(dump):
        if kind != "draw":
            continue
        r = d["regs"]
        if target is None and d["clear"]:
            target = d["fb"]
        if d["fb"] != target:
            continue
        vt = d["vtype"]
        sc = d["scissor"]
        sc = (max(sc[0], 0), max(sc[1], 0), min(sc[2], W - 1), min(sc[3], H - 1))
        if d["clear"]:
            if d["clear_bits"] & 4:
                pts = positions(vt, d["vbytes"], d["ibytes"], d["count"])
                for a, b in zip(pts[0::2], pts[1::2]):
                    for y in range(max(sc[1], int(min(a[1], b[1]))), min(sc[3] + 1, int(max(a[1], b[1])))):
                        for x in range(max(sc[0], int(min(a[0], b[0]))), min(sc[2] + 1, int(max(a[0], b[0])))):
                            depth[y * W + x] = int(b[2])
            continue
        if d["through"] or d["prim"] not in ("tris", "tristrip", "trifan"):
            continue
        n = d["n"]
        pts = [to_clip(p, d["mtx"]) for p in positions(vt, d["vbytes"], d["ibytes"], d["count"])]
        c = len(pts)
        tris = ([(i, i + 1, i + 2) for i in range(0, c - 2, 3)] if d["prim"] == "tris" else
                [(i, i + 1, i + 2) for i in range(c - 2)] if d["prim"] == "tristrip" else
                [(0, i, i + 1) for i in range(1, c - 1)])
        xs, ys, zs = f24(r[0x42]), f24(r[0x43]), f24(r[0x44])
        xc, yc, zc = f24(r[0x45]), f24(r[0x46]), f24(r[0x47])
        ox, oy = (r[0x4C] & 0xFFFF) / 16, (r[0x4D] & 0xFFFF) / 16
        minz, maxz = r[0xD6] & 0xFFFF, r[0xD7] & 0xFFFF
        clamp = r[0x1C] & 1
        test = zcmp[r[0xDE] & 7] if d["ztest"] != "off" else zcmp[1]
        write = d["zwrite"] and d["ztest"] != "off"
        is_opaque = d["blend"] == "opaque"
        stats = info.setdefault(n, {"d": d, "tris": 0, "dropped": 0})

        def plot(x, y, z):
            z = int(min(max(z, 0.0), 65535.0))
            if z < minz or z > maxz:
                return
            i = y * W + x
            if not test(z, depth[i]):
                return
            if write:
                depth[i] = z
            last[i] = n
            if is_opaque:
                opaque[i] = n

        def screen(v):
            return (v[0] / v[3] * xs + xc, v[1] / v[3] * ys + yc, v[2] / v[3] * zs + zc)

        for t in tris:
            vs = [pts[i] for i in t]
            stats["tris"] += 1
            if all(v[3] < 0 for v in vs):
                stats["dropped"] += 1
                continue
            # A vertex outside the 4096x4096 drawing space drops the whole triangle (with depth clamp on, only a
            # vertex in front of z = -w counts).
            if any((not clamp or v[2] > -v[3]) and v[3] != 0 and not (0 <= screen(v)[0] < 4096 and
                                                                       0 <= screen(v)[1] < 4096) for v in vs):
                stats["dropped"] += 1
                continue
            if not clamp and any(abs(v[2] / v[3]) > 1.0000305 for v in vs if v[3] > 0):
                stats["dropped"] += 1
                continue
            poly = clip_near(vs)
            if len(poly) < 3:
                continue
            sp = [screen(v) for v in poly]
            sp = [(x - ox, y - oy, z) for x, y, z in sp]
            for i in range(1, len(sp) - 1):
                raster((sp[0], sp[i], sp[i + 1]), sc, plot)
    seen_opaque, seen_last, box = {}, {}, {}
    for i in range(W * H):
        seen_opaque[opaque[i]] = seen_opaque.get(opaque[i], 0) + 1
        seen_last[last[i]] = seen_last.get(last[i], 0) + 1
        x, y = i % W, i // W
        b = box.setdefault(opaque[i], [x, y, x, y])
        b[0], b[1], b[2], b[3] = min(b[0], x), min(b[1], y), max(b[2], x), max(b[3], y)
    print(f"target 0x{target:08x}: {W * H} pixels; {seen_opaque.get(-1, 0)} with no opaque 3D writer, "
          f"{seen_last.get(-1, 0)} with no 3D writer at all")
    print("draw   prim      verts tris drop opaque  last  opaque box        vertex type / state")
    for n, st in sorted(info.items()):
        d = st["d"]
        r = d["regs"]
        tex = fmt_tex(d["tex"], {}) if d["tex_on"] else "untextured"
        b = "{},{}-{},{}".format(*box[n]) if n in box else "-"
        print(f"#{n:4d} {d['prim']:9s} {d['count']:5d} {st['tris']:4d} {st['dropped']:4d} {seen_opaque.get(n, 0):6d} "
              f"{seen_last.get(n, 0):6d}  {b:16s} {vtype_desc(d['vtype'])} | cull {r[0x1D] & 1}/{r[0x9B] & 1} "
              f"z {d['ztest']}{'' if d['zwrite'] else ' nowrite'} at {d['atest']} {d['blend']} | {tex}")
    if out:
        px = bytearray()
        for i in range(W * H):
            n = opaque[i]
            if n < 0:
                px += b"\0\0\0"
            elif highlight and not any(a <= n <= b for a, b in highlight):
                px += b"\x50\x50\x50"
            else:
                h = (n * 2654435761) & 0xFFFFFF
                px += bytes((64 + (h & 0xBF), 64 + ((h >> 8) & 0xBF), 64 + ((h >> 16) & 0xBF)))
        write_png(out, W, H, 3, bytes(px))
        print(f"wrote {out}")


def cmd_gelist(path, show_all):
    """Our port's PURE_TRACE_GE_LIST output (`[ge-list] run N from PC`, `[ge-list] PC WORD`) replayed through the
    same register model. `[pure] frame`, `[call]`, `[vram]` and `[fbtex]` lines are kept as markers. There is no
    vertex data: the trace has command words only."""
    s, targets, n, last_rt = State(), {}, 0, None
    empty = {"verts": None, "indices": None, "fbtex": {}, "tex": {}}
    markers = ("[ge-list] run ", "[pure] frame ", "[call] ", "[vram]", "[fbtex]")
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith(markers):
            print(line)
            continue
        if not line.startswith("[ge-list] 0x"):
            continue
        w = int(line.split()[2], 16)
        op = w >> 24
        if op in (0x04, 0x05, 0x06):
            count = w & 0xFFFF if op == 0x04 else (w & 0xFF) * ((w >> 8) & 0xFF)
            d = make_draw(n, s, w, count, empty, b"")
            rt = (d["fb"], d["fb_fmt"], d["fb_stride"], d["z"])
            vram_tex = d["tex_on"] and d["tex"] and d["tex"]["vram"]
            if show_all or rt != last_rt or vram_tex or d["clear"]:
                print(draw_line(d, targets))
            last_rt = rt
            note_target(targets, d)
            n += 1
        elif op == 0xEA:
            t = make_transfer(s, w, n)
            print(f"TRANSFER 0x{t['src']:08x}/{t['src_stride']} -> 0x{t['dst']:08x}/{t['dst_stride']} "
                  f"{t['w']}x{t['h']} bpp {t['bpp']}")
        elif op not in (0x00, 0x01, 0x02, 0x08, 0x0A, 0x0B, 0x0C, 0x0E, 0x0F, 0x10):
            s.r[op] = w


def main(argv):
    global SHOW_VT
    if len(argv) < 3:
        sys.exit(__doc__)
    SHOW_VT = "--vt" in argv
    if argv[1] == "gelist":
        cmd_gelist(argv[2], "--all" in argv)
        return
    dump = load(argv[2])
    if argv[1] == "summary":
        cmd_summary(dump)
    elif argv[1] == "draws":
        cmd_draws(dump, "--all" in argv)
    elif argv[1] == "passes":
        cmd_passes(dump)
    elif argv[1] == "verts":
        cmd_verts(dump, int(argv[3]))
    elif argv[1] == "tex":
        cmd_tex(dump, int(argv[3]), argv[4])
    elif argv[1] == "cover":
        rest = [a for a in argv[3:]]
        highlight = []
        if "--highlight" in rest:
            spec = rest[rest.index("--highlight") + 1]
            rest.remove(spec)
            rest.remove("--highlight")
            for part in spec.split(","):
                a, _, b = part.partition("-")
                highlight.append((int(a), int(b or a)))
        cmd_cover(dump, rest[0] if rest else None, highlight)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
