#!/usr/bin/env python3
"""Lists the records of a GE backend recording (.gerec, written by the record backend of patch
0004-ge-backend-and-shell-seams).

  tools/gerec/gerec_dump.py [--summary] [--draws] [--images DIR] FILE.gerec

Prints the Begin record, one line per record of the stream (kind, payload size and what it holds; --summary leaves
them out), and a table of the frames: draws counted in the stream, the draws the FrameEnd record says the frame had,
and the inner backend's own cumulative counter with its change since the frame before (the Begin record holds the
counter before the first frame). The three must agree; the table says so per frame and the exit code is 1 when one
disagrees or the file is cut short. --draws parses every Draw record in full (the layout of
vendor/portablekit/host/gpu/ge_record_format.hpp) and checks that it fills its payload exactly; it is implied unless
--summary is given. --images DIR writes each frame's presented image (a BMP, as capture_frame() wrote it) to
DIR/frame_<n>.bmp.

The format: the 8 bytes "PKGEREC\\0", a u32 version, then records of a u8 kind, a u32 payload size and the payload,
little endian. ge_record_format.hpp is the reference; this reader follows version 1.
"""
import argparse, os, struct, sys

MAGIC = b"PKGEREC\0"
VERSION = 1
KINDS = {1: "Begin", 2: "Memory", 3: "Words", 4: "DisplayList", 5: "Draw", 6: "Transfer", 7: "ReadBack",
         8: "WriteBackFrame", 9: "WriteBackDepth", 10: "Upload", 11: "FrameEnd", 12: "End"}
PRIMITIVES = ["points", "lines", "line_strip", "triangles", "triangle_strip", "triangle_fan", "sprites"]
TEXTURE_FORMATS = ["5650", "5551", "4444", "8888", "clut4", "clut8", "clut16", "clut32", "dxt1", "dxt3", "dxt5"]
TARGET_FORMATS = ["5650", "5551", "4444", "8888"]
IMAGE_APIS = ["none", "cpu", "vulkan", "metal"]
LEVEL_BYTES = 4 + 7 * 12 + 12   # a Draw's mip level fields (Writer::put_levels)
LEVEL_MODES = ["auto", "const", "slope", "mode3"]
PIXEL_BYTES = 13 + 17 + 1       # a Draw's colour test, dithering and CLIPENABLE (task 040)
COLOR_TEST_FUNCTIONS = ["never", "always", "equal", "notequal"]


class Cut(Exception):
    pass


class Cursor:
    def __init__(self, data, at=0, end=None):
        self.data, self.at, self.end = data, at, len(data) if end is None else end

    def take(self, fmt):
        size = struct.calcsize(fmt)
        if self.at + size > self.end:
            raise Cut(f"needs {size} bytes at {self.at}, {self.end - self.at} left")
        values = struct.unpack_from(fmt, self.data, self.at)
        self.at += size
        return values

    def u8(self): return self.take("<B")[0]
    def flag(self): return self.take("<B")[0] != 0
    def u16(self): return self.take("<H")[0]
    def u32(self): return self.take("<I")[0]
    def u64(self): return self.take("<Q")[0]
    def f32(self): return self.take("<f")[0]
    def floats(self, n): return self.take(f"<{n}f")

    def raw(self, size):
        if self.at + size > self.end:
            raise Cut(f"needs {size} bytes at {self.at}, {self.end - self.at} left")
        value = self.data[self.at:self.at + size]
        self.at += size
        return value

    def string(self):
        return self.raw(self.u32()).decode("utf-8", "replace")

    def left(self): return self.end - self.at


def texture_state(c):
    t = {}
    t["enabled"] = c.flag(); t["address"] = c.u32(); t["buffer_width"] = c.u32()
    t["width"] = c.u16(); t["height"] = c.u16(); t["format"] = c.u8(); t["swizzled"] = c.flag()
    (t["clut_address"], t["clut_format"], t["clut_shift"], t["clut_mask"], t["clut_offset"], t["clut_format_word"],
     t["clut_load_bytes"], t["clut_max_bytes"]) = c.take("<8I")
    t["function"] = c.u32(); t["alpha_from_texture"] = c.flag()
    t["min_filter"], t["mag_filter"], t["wrap_s"], t["wrap_t"] = c.take("<4I")
    t["scale_u"], t["scale_v"], t["offset_u"], t["offset_v"] = c.floats(4)
    return t


def draw_call(c):
    """Reads a DrawCall in the order Writer::put(DrawCall) writes it; returns the fields the listing shows."""
    d = {"primitive": c.u8()}
    d["vertices"] = c.u32(); c.raw(40 * d["vertices"])          # position 4f, normal 3f, texcoord 2f, colour u32
    d["indices"] = c.u32(); c.raw(2 * d["indices"])
    d["through"] = c.flag()
    d["texture"] = texture_state(c)
    d["target"] = c.take("<5I")                                  # colour address, stride, format, depth address, stride
    blend_on = c.flag(); d["blend"] = (blend_on,) + c.take("<5I")
    d["depth"] = (c.flag(), c.flag(), c.u32(), c.u16(), c.u16())
    d["alpha_test"] = (c.flag(),) + c.take("<3I")
    c.floats(6); c.take("<4I"); c.floats(2)                      # viewport: scale, offset, scissor, screen offset
    d["culling"], d["cull_clockwise"], d["clear_mode"] = c.flag(), c.flag(), c.flag()
    d["clear_flags"] = c.u32()
    d["vertex_type"], d["vertex_address"], d["index_address"], d["primitive_count"] = c.take("<4I")
    d["material_color"] = c.u32(); d["lighting"] = c.flag(); d["has_vertex_color"] = c.flag()
    c.take("<4I"); c.f32(); c.take("<3I"); c.flag()              # lighting: material, power, ambient, mode, reverse
    for _ in range(4):
        c.flag(); c.take("<2I"); c.floats(9); c.floats(2); c.take("<3I")
    d["fog"] = c.flag(); c.floats(2); c.u32()
    c.take("<2Q")                                                # environment and material versions
    c.floats(64)                                                 # world, view, projection, texture matrices
    d["raw_count"], d["raw_stride"] = c.u32(), c.u32()
    d["raw_bytes"] = c.u32(); c.raw(d["raw_bytes"])
    d["bones"] = c.flag()
    if d["bones"]:
        c.floats(96)
    d["stencil"] = (c.flag(),) + c.take("<6I")
    d["color_write_mask"], d["alpha_write_mask"] = c.u32(), c.u32()
    # The texture map state (task 036): map mode, projection source, the two shade lights. Recordings made before
    # it end here, and their draws are map mode 0.
    d["texture_map"] = c.take("<4I") if c.left() >= 16 else (0, 0, 0, 0)
    # The texture's mip levels (task 037): the level count, levels 1 to 7 (address, buffer width, width, height),
    # the level mode, the bias in 1/16 levels and the LOD slope. Recordings made before end here: one level.
    t = d["texture"]
    t["level_count"], t["levels"], t["level_mode"], t["level_bias"], t["lod_slope"] = 1, [], 0, 0, 0.0
    if c.left() >= LEVEL_BYTES:
        t["level_count"] = c.u32()
        t["levels"] = [c.take("<IIHH") for _ in range(7)]
        t["level_mode"], t["level_bias"], t["lod_slope"] = c.u32(), c.take("<i")[0], c.f32()
    # The colour test (enabled, function, reference, mask), dithering (enabled, the matrix's four rows) and
    # CLIPENABLE (task 040). Recordings made before end here: no colour test, no dithering, CLIPENABLE off.
    d["color_test"], d["dither"], d["clip"] = (False, 0, 0, 0xFFFFFF), (False, (0, 0, 0, 0)), False
    if c.left() >= PIXEL_BYTES:
        d["color_test"] = (c.flag(),) + c.take("<3I")
        d["dither"] = (c.flag(), c.take("<4I"))
        d["clip"] = c.flag()
    return d


def describe_draw(d):
    target = d["target"]
    fmt = TARGET_FORMATS[target[2]] if target[2] < len(TARGET_FORMATS) else str(target[2])
    prim = PRIMITIVES[d["primitive"]] if d["primitive"] < len(PRIMITIVES) else str(d["primitive"])
    text = f"{prim} {d['vertices']} vertices"
    if d["indices"]:
        text += f" {d['indices']} indices"
    if d["raw_bytes"]:
        text += f" raw {d['raw_count']}x{d['raw_stride']}"
    text += f" -> 0x{target[0]:08X} {fmt}/{target[1]}"
    t = d["texture"]
    if t["enabled"]:
        tf = TEXTURE_FORMATS[t["format"]] if t["format"] < len(TEXTURE_FORMATS) else str(t["format"])
        text += f" tex 0x{t['address']:08X} {tf} {t['width']}x{t['height']}/{t['buffer_width']}"
        if t["swizzled"]:
            text += " swz"
        if t["format"] in (4, 5, 6, 7):
            text += f" clut 0x{t['clut_address']:08X}"
        if t["level_count"] > 1:
            text += f" levels {t['level_count']} {LEVEL_MODES[t['level_mode'] & 3]}"
            if t["level_mode"] != 0 or t["level_bias"] != 0:
                text += f" bias {t['level_bias']}"
            if t["level_mode"] == 2:
                text += f" slope {t['lod_slope']:g}"
        mode, source, light_u, light_v = d["texture_map"]
        if not d["through"] and mode == 1:
            text += f" texmatrix {source}"
        elif not d["through"] and mode == 2:
            text += f" envmap {light_u},{light_v}"
    on, function, reference, mask = d["color_test"]
    if on and not d["clear_mode"]:
        name = COLOR_TEST_FUNCTIONS[function & 3]
        text += f" ctest {name} {reference:06X}/{mask:06X}"
    if d["dither"][0]:
        text += " dither " + ",".join(f"{row:04X}" for row in d["dither"][1])
    flags = [name for name, on in (("through", d["through"]), ("clear", d["clear_mode"]), ("blend", d["blend"][0]),
                                   ("ztest", d["depth"][0]), ("stencil", d["stencil"][0]), ("lit", d["lighting"]),
                                   ("fog", d["fog"]), ("noclip", not d["through"] and not d["clip"])) if on]
    if flags:
        text += " " + ",".join(flags)
    return text


def main(argv=None):
    p = argparse.ArgumentParser(prog="gerec_dump.py", usage=__doc__.split("\n\n")[1].strip())
    p.add_argument("file")
    p.add_argument("--summary", action="store_true")
    p.add_argument("--draws", action="store_true")
    p.add_argument("--images")
    opts = p.parse_args(argv)
    parse_draws = opts.draws or not opts.summary
    with open(opts.file, "rb") as f:
        data = f.read()
    if data[:8] != MAGIC:
        print(f"{opts.file}: not a .gerec file (magic {data[:8]!r})")
        return 1
    version = struct.unpack_from("<I", data, 8)[0]
    print(f"{opts.file}: {len(data)} bytes, format version {version}")
    if version > VERSION:
        print(f"  written by a later version than this reader ({VERSION}); unknown fields are skipped")
    if opts.images:
        os.makedirs(opts.images, exist_ok=True)

    at, index, problems = 12, 0, []
    counts, frames = {}, []
    frame = {"records": 0, "draws": 0, "memory": 0, "memory_bytes": 0, "kinds": {}}
    begin_draws = None
    ended = False
    while at < len(data):
        if at + 5 > len(data):
            problems.append(f"record {index}: header cut short at byte {at}")
            break
        kind, size = struct.unpack_from("<BI", data, at)
        at += 5
        if at + size > len(data):
            problems.append(f"record {index}: {KINDS.get(kind, kind)} payload of {size} bytes cut short")
            break
        c = Cursor(data, at, at + size)
        name = KINDS.get(kind, f"kind{kind}")
        counts[name] = counts.get(name, 0) + 1
        frame["records"] += 1
        frame["kinds"][name] = frame["kinds"].get(name, 0) + 1
        line = ""
        try:
            if name == "Begin":
                first, asked = c.u32(), c.u32()
                inner, prefix = c.string(), c.string()
                begin_frames, begin_draws = c.u64(), c.u64()
                line = (f"frames {first}-{first + asked - 1} drawn by {inner} ({prefix}_*), before them "
                        f"{begin_frames} frames and {begin_draws} draws")
                print(f"Begin: {line}")
                frame = {"records": 0, "draws": 0, "memory": 0, "memory_bytes": 0, "kinds": {}}
            elif name == "Memory":
                address, length = c.u32(), c.u32()
                c.raw(length)
                frame["memory"] += 1
                frame["memory_bytes"] += length
                line = f"0x{address:08X} {length} bytes"
            elif name == "Words":
                address, step, count = c.u32(), c.u32(), c.u32()
                c.raw(4 * count)
                line = f"0x{address:08X} {count} words every {step} bytes"
            elif name == "Draw":
                frame["draws"] += 1
                if parse_draws:
                    d = draw_call(c)
                    if c.left() != 0:
                        problems.append(f"record {index}: Draw parsed {size - c.left()} of {size} bytes")
                    line = f"#{frame['draws'] - 1} " + describe_draw(d)
                else:
                    c.at = c.end
            elif name == "Transfer":
                v = c.take("<11I")
                line = (f"0x{v[0]:08X}/{v[1]} ({v[2]},{v[3]}) -> 0x{v[4]:08X}/{v[5]} ({v[6]},{v[7]}) "
                        f"{v[8]}x{v[9]} x{v[10]} bytes")
            elif name == "ReadBack":
                line = f"0x{c.u32():08X}"
            elif name == "WriteBackDepth":
                color, depth, stride, wrote = c.u32(), c.u32(), c.u32(), c.flag()
                line = f"0x{color:08X} -> 0x{depth:08X}/{stride} {'written' if wrote else 'not written'} ({c.string()})"
            elif name == "Upload":
                display, width, height = c.u32(), c.u32(), c.u32()
                c.raw(width * height * 4)
                line = f"0x{display:08X} {width}x{height}"
            elif name == "FrameEnd":
                number, display = c.u32(), c.u32()
                presented, submitted = c.u64(), c.u64()
                said_draws, said_records = c.u32(), c.u32()
                api, width, height = c.u8(), c.u32(), c.u32()
                image = c.raw(c.u32())
                api_name = IMAGE_APIS[api] if api < len(IMAGE_APIS) else str(api)
                line = (f"frame {number} display 0x{display:08X}, {said_draws} draws, {said_records} records, "
                        f"image {api_name} {width}x{height}, capture {len(image)} bytes")
                frames.append({"number": number, "counted": frame["draws"], "said": said_draws,
                               "records": frame["records"], "said_records": said_records,
                               "submitted": submitted, "presented": presented, "memory": frame["memory"],
                               "memory_bytes": frame["memory_bytes"], "image": len(image)})
                if opts.images and image:
                    with open(os.path.join(opts.images, f"frame_{number}.bmp"), "wb") as out:
                        out.write(image)
                frame = {"records": 0, "draws": 0, "memory": 0, "memory_bytes": 0, "kinds": {}}
            elif name == "End":
                recorded, records = c.u32(), c.u64()
                line = f"{recorded} frames, {records} records before it"
                if records != index:
                    problems.append(f"End says {records} records came before it; the file has {index}")
                ended = True
            else:
                c.at = c.end
        except Cut as e:
            problems.append(f"record {index}: {name} payload too short: {e}")
        if not opts.summary and name != "Begin":
            print(f"{index:7d} {name:<14s} {size:9d}  {line}".rstrip())
        at += size
        index += 1

    print()
    print("records by kind: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    print()
    print(f"{'frame':>7s} {'draws':>6s} {'said':>6s} {'submitted':>11s} {'delta':>6s} {'records':>8s} "
          f"{'memory':>7s} {'bytes':>10s} {'image':>8s}  check")
    previous = begin_draws
    for f in frames:
        delta = f["submitted"] - previous if previous is not None else None
        ok = f["counted"] == f["said"] and (delta is None or delta == f["counted"]) and \
            f["records"] == f["said_records"] + 1
        if not ok:
            problems.append(f"frame {f['number']}: {f['counted']} draws in the stream, FrameEnd says {f['said']}, "
                            f"the inner backend's counter moved by {delta}")
        print(f"{f['number']:7d} {f['counted']:6d} {f['said']:6d} {f['submitted']:11d} "
              f"{'?' if delta is None else delta:>6} {f['records']:8d} {f['memory']:7d} {f['memory_bytes']:10d} "
              f"{f['image']:8d}  {'ok' if ok else 'MISMATCH'}")
        previous = f["submitted"]
    if frame["records"] > (1 if ended else 0):
        print(f"after the last frame: {frame['records'] - (1 if ended else 0)} records ({frame['draws']} draws)")
    if not ended:
        problems.append("no End record: the recording was cut short")
    for problem in problems:
        print(f"problem: {problem}")
    print(f"{len(frames)} frames, {index} records, {'ok' if not problems else str(len(problems)) + ' problem(s)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
