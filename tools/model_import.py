#!/usr/bin/env python3
"""A glTF model to the models backend's .pmdl (task 102, D-025).

    python3 tools/model_import.py IN.gltf|IN.glb OUT.pmdl [--light X,Y,Z] [--height H] [--colour RRGGBB]

Reads the first mesh of IN (a .gltf with its buffers beside it or in data: URIs, or one .glb): every triangle
primitive (mode 4) of it, placed by the first node that uses the mesh (its TRS or matrix and its parents'). Each
primitive needs POSITION and COLOR_0 (float VEC3 or VEC4, or normalised unsigned byte or short: glTF's colours are
linear, so they are turned to sRGB, the display values the GE's vertex colours are); NORMAL is read when present,
else each vertex gets the mean of its faces' normals. Then:
  - a fixed key light is baked into the colours: colour x (0.55 + 0.45 x max(0, n . l)), on the sRGB value, l the
    unit vector toward the light, --light X,Y,Z in the model's frame (default 0.3,0.8,0.5: above, in front, a
    little to the figure's left);
  - the model is normalised: its feet (the lowest y) at 0 and its height --height (default 1), uniformly scaled, x
    and z centred on the bounding box of its feet (the vertices within 5% of the height above the lowest);
  - OUT is written, little-endian: the magic PMDL, u32 version 1, u32 vertex count, u32 index count, then the
    float3 positions, the u32 colours as the GE's ABGR words (red in the low byte, alpha 0xFF) and the u16 indices.
Prints the counts and the bounds. Exit 2 when the mesh has no COLOR_0 (a flat grey is not wanted silently:
--colour RRGGBB gives such a mesh one sRGB colour, lit as above), when it has no triangles, or when it has more than
65535 vertices. The export convention (models/README.md): y up, the front toward +z, the feet at the origin.
Standard library only. The winding is not promised (a Blender mesh may mix it): the backend draws the models
without culling.
"""
import argparse
import base64
import json
import math
import os
import struct
import sys

MAGIC = b"PMDL"
VERSION = 1
FLOOR, SPAN = 0.55, 0.45     # the bake: floor + span x max(0, n . l)
FEET_BAND = 0.05             # the feet: within this share of the height above the lowest vertex

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FORMATS = {5120: ("b", 127.0), 5121: ("B", 255.0), 5122: ("h", 32767.0), 5123: ("H", 65535.0),
           5125: ("I", None), 5126: ("f", None)}


def fail(message, code=2):
    print(f"model_import: {message}", file=sys.stderr)
    sys.exit(code)


def load(path):
    """The glTF's JSON and its buffers' bytes."""
    with open(path, "rb") as f:
        data = f.read()
    glb_bin = None
    if data[:4] == b"glTF":
        _, _, length = struct.unpack_from("<4sII", data, 0)
        at, doc = 12, None
        while at + 8 <= min(length, len(data)):
            size, kind = struct.unpack_from("<II", data, at)
            chunk = data[at + 8:at + 8 + size]
            if kind == 0x4E4F534A:      # JSON
                doc = json.loads(chunk.decode("utf-8"))
            elif kind == 0x004E4942:    # BIN
                glb_bin = chunk
            at += 8 + size
        if doc is None:
            fail(f"{path}: a .glb without a JSON chunk")
    else:
        doc = json.loads(data.decode("utf-8"))
    buffers = []
    for n, buffer in enumerate(doc.get("buffers", [])):
        uri = buffer.get("uri")
        if uri is None:
            if glb_bin is None:
                fail(f"{path}: buffer {n} has no uri and there is no GLB binary chunk")
            buffers.append(glb_bin)
        elif uri.startswith("data:"):
            buffers.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            from urllib.parse import unquote
            with open(os.path.join(os.path.dirname(os.path.abspath(path)), unquote(uri)), "rb") as f:
                buffers.append(f.read())
    return doc, buffers


def read_accessor(doc, buffers, index):
    """An accessor's elements as tuples of floats (normalised integers to 0..1 or -1..1; others as they are)."""
    acc = doc["accessors"][index]
    n = COMPONENTS[acc["type"]]
    fmt, scale = FORMATS[acc["componentType"]]
    count = acc["count"]
    if "bufferView" not in acc:
        return [tuple([0.0] * n)] * count
    view = doc["bufferViews"][acc["bufferView"]]
    data = buffers[view["buffer"]]
    size = struct.calcsize("<" + fmt)
    stride = view.get("byteStride") or size * n
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    normalised = acc.get("normalized", False)
    out = []
    for i in range(count):
        values = struct.unpack_from(f"<{n}{fmt}", data, base + i * stride)
        if normalised and scale is not None:
            values = tuple(max(v / scale, -1.0) for v in values)
        out.append(tuple(float(v) for v in values))
    if "sparse" in acc:
        fail("sparse accessors are not read")
    return out


def matrix_of(node):
    """A node's local matrix, column-major 4x4 as glTF writes it."""
    if "matrix" in node:
        return list(node["matrix"])
    t = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    r = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]
    return [r[0] * s[0], r[1] * s[0], r[2] * s[0], 0.0,
            r[3] * s[1], r[4] * s[1], r[5] * s[1], 0.0,
            r[6] * s[2], r[7] * s[2], r[8] * s[2], 0.0,
            t[0], t[1], t[2], 1.0]


def multiply(a, b):
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


def mesh_matrix(doc, mesh_index):
    """The world matrix of the first node that uses the mesh (identity when none does)."""
    nodes = doc.get("nodes", [])
    parent = {}
    for n, node in enumerate(nodes):
        for child in node.get("children", []):
            parent[child] = n
    for n, node in enumerate(nodes):
        if node.get("mesh") == mesh_index:
            m = matrix_of(node)
            at = n
            while at in parent:
                at = parent[at]
                m = multiply(matrix_of(nodes[at]), m)
            return m
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def normal_matrix(m):
    """The inverse transpose of m's upper 3x3, as rows."""
    a = [[m[c * 4 + r] for c in range(3)] for r in range(3)]
    det = (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
           + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    if abs(det) < 1e-20:
        fail("the mesh's node has a singular transform")
    cof = [[(a[(r + 1) % 3][(c + 1) % 3] * a[(r + 2) % 3][(c + 2) % 3]
             - a[(r + 1) % 3][(c + 2) % 3] * a[(r + 2) % 3][(c + 1) % 3]) / det for c in range(3)] for r in range(3)]
    return cof  # the cofactor matrix over det is the inverse transpose


def normalise(v):
    length = math.sqrt(sum(x * x for x in v))
    return [x / length for x in v] if length > 0 else [0.0, 1.0, 0.0]


def to_srgb(c):
    c = min(max(c, 0.0), 1.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def parse_vector(text):
    try:
        v = [float(x) for x in text.split(",")]
    except ValueError:
        v = []
    if len(v) != 3 or not any(v):
        fail(f"--light wants X,Y,Z, not {text}", 1)
    return normalise(v)


def main():
    parser = argparse.ArgumentParser(description="A glTF model to the models backend's .pmdl (task 102).")
    parser.add_argument("input", help="IN.gltf or IN.glb")
    parser.add_argument("output", help="OUT.pmdl")
    parser.add_argument("--light", default="0.3,0.8,0.5", help="toward the key light, X,Y,Z in the model's frame")
    parser.add_argument("--height", type=float, default=1.0, help="the height to normalise to (default 1)")
    parser.add_argument("--colour", help="RRGGBB (sRGB) for a mesh without COLOR_0")
    opts = parser.parse_args()
    light = parse_vector(opts.light)
    flat = None
    if opts.colour is not None:
        text = opts.colour.lstrip("#")
        if len(text) != 6:
            fail(f"--colour wants RRGGBB, not {opts.colour}", 1)
        flat = tuple(int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    if opts.height <= 0:
        fail("--height must be above 0", 1)

    doc, buffers = load(opts.input)
    meshes = doc.get("meshes", [])
    if not meshes:
        fail(f"{opts.input}: no mesh")
    m = mesh_matrix(doc, 0)
    nm = normal_matrix(m)
    positions, normals, colours, indices = [], [], [], []
    skipped = 0
    for primitive in meshes[0]["primitives"]:
        if primitive.get("mode", 4) != 4:
            skipped += 1
            continue
        attributes = primitive["attributes"]
        if "POSITION" not in attributes:
            fail(f"{opts.input}: a primitive without POSITION")
        first = len(positions)
        pos = read_accessor(doc, buffers, attributes["POSITION"])
        if "COLOR_0" in attributes:
            col = [tuple(to_srgb(c[i]) for i in range(3)) for c in read_accessor(doc, buffers, attributes["COLOR_0"])]
        elif flat is not None:
            col = [flat] * len(pos)
        else:
            fail(f"{opts.input}: the mesh has no vertex colours (COLOR_0): export with a colour attribute and "
                 f"\"Vertex Colors\" on, or give --colour RRGGBB for one flat colour")
        nor = read_accessor(doc, buffers, attributes["NORMAL"]) if "NORMAL" in attributes else None
        for i, p in enumerate(pos):
            positions.append([sum(m[c * 4 + r] * (p[c] if c < 3 else 1.0) for c in range(4)) for r in range(3)])
            colours.append(col[i])
            if nor is not None:
                normals.append(normalise([sum(nm[r][c] * nor[i][c] for c in range(3)) for r in range(3)]))
        if "indices" in primitive:
            idx = [int(v[0]) for v in read_accessor(doc, buffers, primitive["indices"])]
        else:
            idx = list(range(len(pos)))
        indices += [first + i for i in idx[:len(idx) - len(idx) % 3]]
        if nor is None:
            normals += [None] * len(pos)
    if not indices:
        fail(f"{opts.input}: the first mesh has no triangles")
    if len(positions) > 65535:
        fail(f"{opts.input}: {len(positions)} vertices, over the 65535 a u16 index reaches")
    # Normals from the faces where the file has none: the area-weighted mean of the faces around each vertex.
    if any(n is None for n in normals):
        sums = [[0.0, 0.0, 0.0] for _ in positions]
        for t in range(0, len(indices), 3):
            a, b, c = (positions[indices[t + k]] for k in range(3))
            e1 = [b[k] - a[k] for k in range(3)]
            e2 = [c[k] - a[k] for k in range(3)]
            face = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
            for k in range(3):
                for j in range(3):
                    sums[indices[t + k]][j] += face[j]
        normals = [n if n is not None else normalise(sums[i]) for i, n in enumerate(normals)]

    # Normalise: the feet at y 0, the height opts.height, x and z centred on the feet's bounding box.
    low = min(p[1] for p in positions)
    high = max(p[1] for p in positions)
    if high - low <= 0:
        fail(f"{opts.input}: the mesh is flat in y (no height)")
    scale = opts.height / (high - low)
    band = low + FEET_BAND * (high - low)
    feet = [p for p in positions if p[1] <= band]
    cx = (min(p[0] for p in feet) + max(p[0] for p in feet)) / 2
    cz = (min(p[2] for p in feet) + max(p[2] for p in feet)) / 2
    placed = [((p[0] - cx) * scale, (p[1] - low) * scale, (p[2] - cz) * scale) for p in positions]

    words = []
    for colour, n in zip(colours, normals):
        lit = FLOOR + SPAN * max(0.0, sum(n[k] * light[k] for k in range(3)))
        r, g, b = (min(255, max(0, round(c * lit * 255))) for c in colour)
        words.append(0xFF000000 | (b << 16) | (g << 8) | r)

    out = bytearray(MAGIC)
    out += struct.pack("<III", VERSION, len(placed), len(indices))
    for p in placed:
        out += struct.pack("<3f", *p)
    out += struct.pack(f"<{len(words)}I", *words)
    out += struct.pack(f"<{len(indices)}H", *indices)
    os.makedirs(os.path.dirname(os.path.abspath(opts.output)), exist_ok=True)
    with open(opts.output, "wb") as f:
        f.write(out)
    lo = [min(p[k] for p in placed) for k in range(3)]
    hi = [max(p[k] for p in placed) for k in range(3)]
    print(f"model_import: {opts.output}: {len(placed)} vertices, {len(indices)} indices ({len(indices) // 3} "
          f"triangles), {len(out)} bytes; bounds x {lo[0]:.3f}..{hi[0]:.3f} y {lo[1]:.3f}..{hi[1]:.3f} "
          f"z {lo[2]:.3f}..{hi[2]:.3f}; scale {scale:.4g}, light {light[0]:.2f},{light[1]:.2f},{light[2]:.2f}"
          + (f"; {skipped} primitive(s) not triangles, left out" if skipped else "")
          + ("; colour " + opts.colour if flat is not None and "COLOR_0" not in str(meshes[0]) else ""))


if __name__ == "__main__":
    main()
