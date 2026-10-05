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
  ppdmp.py draws DUMP [--all]      one line per draw (only render-target changes and VRAM binds unless --all)
  ppdmp.py passes DUMP             draws grouped by render target, with every VRAM texture bind and what it aliases
  ppdmp.py verts DUMP N            draw N in full: state words and every vertex
  ppdmp.py gelist LOG [--all]      the same draw lines from our port's PURE_TRACE_GE_LIST output (no vertices)
  ppdmp.py tex DUMP N OUT.png      writes the VRAM texture bound at draw N as a PNG (RGBA, linear, unswizzled)
"""
import struct, subprocess, sys

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

    def init(self, buf, ptr):
        words = struct.unpack_from("<512I", buf, ptr)
        i = 17
        for lo, hi in CONTEXT_RANGES:
            for op in range(lo, hi + 1):
                self.r[op] = words[i]
                i += 1

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
    if len(argv) < 3:
        sys.exit(__doc__)
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
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
