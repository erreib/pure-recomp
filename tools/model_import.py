#!/usr/bin/env python3
"""A glTF model to the models backend's .pmdl (task 102, D-025; skinned and animated: task 103).

    python3 tools/model_import.py IN.gltf|IN.glb OUT.pmdl [--light X,Y,Z] [--height H] [--colour RRGGBB] [--static]

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
A skinned mesh (its node has a skin; task 103) is written as version 2 (models/README.md): the same header and
arrays, then the skin's joints in the order of skins[0].joints (parents from the node tree; a root's parents' world
matrix folded into it), each vertex's four joints and weights (JOINTS_0/WEIGHTS_0 and any further sets: the four
largest kept, normalised to sum 1, an unweighted vertex bound to joint 0) and every animation as a clip, sampled at
the union of its channels' key times (STEP held, LINEAR interpolated, rotations slerped; a joint without a channel
keeps its rest transform). The rest pose is normalised as above, and the same normalisation is applied to the joints
(every translation scaled, the roots' offset) and to the inverse bind matrices (the mesh node's world matrix, which
glTF's skinning ignores, folded in), so a pose never resizes or slides the figure. --static writes version 1 (the
rest pose) from a skinned file. The importer skins each clip's first key and prints its largest distance from the
rest positions (the bind pose is the rest pose when it is about 0) and the clip's seam (first key against last).
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
VERSION = 1                  # static; 2 adds the skin and the clips (task 103)
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
    return trs_matrix(node.get("translation", [0.0, 0.0, 0.0]), node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
                      node.get("scale", [1.0, 1.0, 1.0]))


def trs_matrix(t, q, s):
    """translation x rotation (x, y, z, w) x scale, column-major."""
    x, y, z, w = q
    r = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]
    return [r[0] * s[0], r[1] * s[0], r[2] * s[0], 0.0,
            r[3] * s[1], r[4] * s[1], r[5] * s[1], 0.0,
            r[6] * s[2], r[7] * s[2], r[8] * s[2], 0.0,
            t[0], t[1], t[2], 1.0]


def multiply(a, b):
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


IDENTITY = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def affine(scale=1.0, offset=(0.0, 0.0, 0.0)):
    """T(offset) x S(scale), column-major."""
    return [scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, scale, 0, offset[0], offset[1], offset[2], 1.0]


def inverse(m):
    """The inverse of an affine column-major 4x4."""
    rows = normal_matrix(m)  # the inverse transpose of the 3x3, as rows: its [r][c] is the inverse's [c][r]
    out = [0.0] * 16
    for c in range(3):
        for r in range(3):
            out[c * 4 + r] = rows[c][r]
    for r in range(3):
        out[12 + r] = -sum(out[c * 4 + r] * m[12 + c] for c in range(3))
    out[15] = 1.0
    return out


def apply(m, p):
    return [sum(m[c * 4 + r] * (p[c] if c < 3 else 1.0) for c in range(4)) for r in range(3)]


def decompose(m):
    """A similarity's translation, rotation (x, y, z, w) and scale."""
    t = [m[12], m[13], m[14]]
    s = [math.sqrt(sum(m[c * 4 + r] ** 2 for r in range(3))) for c in range(3)]
    a = [[m[c * 4 + r] / s[c] for c in range(3)] for r in range(3)]   # a[r][c]
    trace = a[0][0] + a[1][1] + a[2][2]
    if trace > 0:
        k = 2 * math.sqrt(1 + trace)
        q = [(a[2][1] - a[1][2]) / k, (a[0][2] - a[2][0]) / k, (a[1][0] - a[0][1]) / k, k / 4]
    elif a[0][0] >= a[1][1] and a[0][0] >= a[2][2]:
        k = 2 * math.sqrt(1 + a[0][0] - a[1][1] - a[2][2])
        q = [k / 4, (a[0][1] + a[1][0]) / k, (a[0][2] + a[2][0]) / k, (a[2][1] - a[1][2]) / k]
    elif a[1][1] >= a[2][2]:
        k = 2 * math.sqrt(1 + a[1][1] - a[0][0] - a[2][2])
        q = [(a[0][1] + a[1][0]) / k, k / 4, (a[1][2] + a[2][1]) / k, (a[0][2] - a[2][0]) / k]
    else:
        k = 2 * math.sqrt(1 + a[2][2] - a[0][0] - a[1][1])
        q = [(a[0][2] + a[2][0]) / k, (a[1][2] + a[2][1]) / k, k / 4, (a[1][0] - a[0][1]) / k]
    return t, normalise_q(q), s


def normalise_q(q):
    length = math.sqrt(sum(x * x for x in q))
    return [x / length for x in q] if length > 0 else [0.0, 0.0, 0.0, 1.0]


def slerp(a, b, f):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0:
        b, d = [-x for x in b], -d
    if d > 0.9995:
        return normalise_q([x + (y - x) * f for x, y in zip(a, b)])
    theta = math.acos(min(1.0, d))
    wa, wb = math.sin((1 - f) * theta) / math.sin(theta), math.sin(f * theta) / math.sin(theta)
    return normalise_q([wa * x + wb * y for x, y in zip(a, b)])


def sample(times, values, interpolation, t, rotation):
    """A channel at time t: held before its first key and after its last."""
    if t <= times[0]:
        return list(values[0])
    if t >= times[-1]:
        return list(values[-1])
    k = max(i for i in range(len(times) - 1) if times[i] <= t)
    if interpolation == "STEP":
        return list(values[k])
    f = (t - times[k]) / (times[k + 1] - times[k])
    if rotation:
        return slerp(values[k], values[k + 1], f)
    return [x + (y - x) * f for x, y in zip(values[k], values[k + 1])]


def skin_positions(rest, influences, joints, pose):
    """The rest positions skinned by a pose (one (t, r, s) per joint): what the backend computes."""
    world = [None] * len(joints)

    def global_of(j):
        if world[j] is None:
            local = trs_matrix(*pose[j])
            parent = joints[j]["parent"]
            world[j] = local if parent is None else multiply(global_of(parent), local)
        return world[j]

    skins = [multiply(global_of(j), joints[j]["ibm"]) for j in range(len(joints))]
    out = []
    for p, influence in zip(rest, influences):
        acc = [0.0, 0.0, 0.0]
        for j, w in influence:
            q = apply(skins[j], p)
            acc = [acc[k] + w * q[k] for k in range(3)]
        out.append(acc)
    return out


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


def skin_block(doc, buffers, skin_node, mesh_world, scale, offset, rest, influences):
    """Version 2's joints, weights and clips (models/README.md) as bytes, and the lines to print."""
    nodes = doc["nodes"]
    skin = doc["skins"][skin_node["skin"]]
    order = skin["joints"]
    if len(order) > 255:
        fail(f"{len(order)} joints, over the 255 a u8 joint index reaches")
    slot = {n: j for j, n in enumerate(order)}
    parent_node = {c: n for n, node in enumerate(nodes) for c in node.get("children", [])}
    ibms = (read_accessor(doc, buffers, skin["inverseBindMatrices"]) if "inverseBindMatrices" in skin
            else [tuple(IDENTITY)] * len(order))
    # The normalisation N = T(offset) S(scale): a joint's global G' = N G S(1/scale), so every local translation is
    # scaled and a root's local gains N's offset (its parents' world A folded in: T(offset) S(scale) A L S(1/scale)),
    # and the inverse bind IBM' = S(scale) IBM M^-1 S(1/scale) T(-offset), M the mesh node's world matrix (the rest
    # positions carry it; glTF's skinning ignores it), so G' IBM' = N G IBM M^-1 N^-1 skins the stored positions.
    inv_m = inverse(mesh_world)
    unoffset = affine(1.0, [-x for x in offset])
    joints = []
    for j, n in enumerate(order):
        p = parent_node.get(n)
        parent = slot.get(p) if p is not None else None
        a = None
        if parent is None:
            a, at = IDENTITY, p
            while at is not None:
                a = multiply(matrix_of(nodes[at]), a)
                at = parent_node.get(at)
            a = multiply(affine(scale, offset), a)
            if all(abs(x - y) < 1e-9 for x, y in zip(a, affine(scale, offset))):
                a = "plain"
        ibm = multiply(multiply(multiply(affine(scale), list(ibms[j])), inv_m), multiply(affine(1.0 / scale), unoffset))
        joints.append({"node": n, "parent": parent, "root": a, "ibm": ibm})

    def placed_trs(j, t, r, s):
        a = joints[j]["root"]
        if a is None:
            return [x * scale for x in t], normalise_q(r), list(s)
        if a == "plain":
            return [o + x * scale for o, x in zip(offset, t)], normalise_q(r), list(s)
        return decompose(multiply(multiply(a, trs_matrix(t, r, s)), affine(1.0 / scale)))

    rest_trs = []
    for joint in joints:
        node = nodes[joint["node"]]
        if "matrix" in node:
            rest_trs.append(decompose(node["matrix"]))
        else:
            rest_trs.append((node.get("translation", [0.0] * 3), node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
                             node.get("scale", [1.0] * 3)))

    # The weights: the four largest, normalised.
    binds, many, off, bare = [], 0, 0, 0
    for influence in influences:
        merged = {}
        for j, w in influence:
            merged[j] = merged.get(j, 0.0) + w
        top = sorted(merged.items(), key=lambda jw: -jw[1])
        many += len(top) > 4
        top = top[:4]
        total = sum(w for _, w in top)
        if total <= 1e-8:
            bare += 1
            top, total = [(0, 1.0)], 1.0
        elif abs(sum(merged.values()) - 1.0) > 1e-3:
            off += 1
        if any(j >= len(order) for j, _ in top):
            fail(f"a vertex names joint {max(j for j, _ in top)} of {len(order)}")
        binds.append([(j, w / total) for j, w in top])

    out = bytearray(struct.pack("<I", len(joints)))
    for j, joint in enumerate(joints):
        t, r, s = placed_trs(j, *rest_trs[j])
        out += struct.pack("<H3f4f3f16f", 0xFFFF if joint["parent"] is None else joint["parent"], *t, *r, *s,
                           *joint["ibm"])
    for bind in binds:
        padded = bind + [(0, 0.0)] * (4 - len(bind))
        out += struct.pack("<4B4f", *(j for j, _ in padded), *(w for _, w in padded))

    animations = doc.get("animations", [])
    out += struct.pack("<I", len(animations))
    lines = [f"model_import: skin: {len(joints)} joints, {len(binds)} vertices bound"
             + (f"; {many} with more than four weights (the four largest kept)" if many else "")
             + (f"; {off} with weights not summing to 1 (normalised)" if off else "")
             + (f"; {bare} without weights (bound to joint 0)" if bare else "")
             + f"; {len(animations)} clip{'' if len(animations) == 1 else 's'}"]
    for number, animation in enumerate(animations):
        name = animation.get("name") or f"clip{number}"
        channels = {}
        times = set()
        for channel in animation["channels"]:
            target = channel["target"]
            if target.get("node") not in slot or target["path"] not in ("translation", "rotation", "scale"):
                continue
            sampler = animation["samplers"][channel["sampler"]]
            keys = [k[0] for k in read_accessor(doc, buffers, sampler["input"])]
            values = read_accessor(doc, buffers, sampler["output"])
            interpolation = sampler.get("interpolation", "LINEAR")
            if interpolation == "CUBICSPLINE":   # in-tangent, value, out-tangent per key: the values, linearly
                values, interpolation = values[1::3], "LINEAR"
            channels[(slot[target["node"]], target["path"])] = (keys, values, interpolation)
            times.update(keys)
        keys = []
        for t in sorted(times):
            if not keys or t - keys[-1] > 1e-6:
                keys.append(t)
        if not keys or keys[0] > 1e-6:
            keys.insert(0, 0.0)
        keys[0] = 0.0
        poses = []
        for t in keys:
            pose = []
            for j in range(len(joints)):
                trs = []
                for which, path in enumerate(("translation", "rotation", "scale")):
                    if (j, path) in channels:
                        k, v, interpolation = channels[(j, path)]
                        trs.append(sample(k, v, interpolation, t, path == "rotation"))
                    else:
                        trs.append(list(rest_trs[j][which]))
                pose.append(placed_trs(j, *trs))
            poses.append(pose)
        encoded = name.encode("utf-8")
        out += struct.pack("<I", len(encoded)) + encoded + struct.pack("<fI", keys[-1], len(keys))
        out += struct.pack(f"<{len(keys)}f", *keys)
        for j in range(len(joints)):
            for pose in poses:
                t, r, s = pose[j]
                out += struct.pack("<3f4f3f", *t, *r, *s)
        first = skin_positions(rest, binds, joints, poses[0])
        last = skin_positions(rest, binds, joints, poses[-1])
        bind_error = max(math.dist(a, b) for a, b in zip(first, rest))
        seam = max(math.dist(a, b) for a, b in zip(first, last))
        lines.append(f"model_import: clip {name}: {len(keys)} keys, {keys[-1]:.3f} s, {len(channels)} channels; its "
                     f"first key skinned is within {bind_error:.2e} of the rest positions, its last within {seam:.2e} "
                     f"of its first")
    return bytes(out), "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="A glTF model to the models backend's .pmdl (task 102).")
    parser.add_argument("input", help="IN.gltf or IN.glb")
    parser.add_argument("output", help="OUT.pmdl")
    parser.add_argument("--light", default="0.3,0.8,0.5", help="toward the key light, X,Y,Z in the model's frame")
    parser.add_argument("--height", type=float, default=1.0, help="the height to normalise to (default 1)")
    parser.add_argument("--colour", help="RRGGBB (sRGB) for a mesh without COLOR_0")
    parser.add_argument("--static", action="store_true", help="version 1 (the rest pose) even from a skinned mesh")
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
    influences = []              # per vertex: (joint, weight) pairs, all the file's sets
    skin_node = next((n for n in doc.get("nodes", []) if n.get("mesh") == 0 and "skin" in n), None)
    skinned = skin_node is not None and not opts.static
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
        if skinned:
            sets = [(read_accessor(doc, buffers, attributes[f"JOINTS_{k}"]),
                     read_accessor(doc, buffers, attributes[f"WEIGHTS_{k}"]))
                    for k in range(8) if f"JOINTS_{k}" in attributes and f"WEIGHTS_{k}" in attributes]
            for i in range(len(pos)):
                influences.append([(int(j[i][c]), w[i][c]) for j, w in sets for c in range(4) if w[i][c] > 0])
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

    extra, notes = (skin_block(doc, buffers, skin_node, m, scale, (-cx * scale, -low * scale, -cz * scale),
                               placed, influences) if skinned else (b"", ""))

    words = []
    for colour, n in zip(colours, normals):
        lit = FLOOR + SPAN * max(0.0, sum(n[k] * light[k] for k in range(3)))
        r, g, b = (min(255, max(0, round(c * lit * 255))) for c in colour)
        words.append(0xFF000000 | (b << 16) | (g << 8) | r)

    out = bytearray(MAGIC)
    out += struct.pack("<III", 2 if skinned else VERSION, len(placed), len(indices))
    for p in placed:
        out += struct.pack("<3f", *p)
    out += struct.pack(f"<{len(words)}I", *words)
    out += struct.pack(f"<{len(indices)}H", *indices)
    out += extra
    os.makedirs(os.path.dirname(os.path.abspath(opts.output)), exist_ok=True)
    with open(opts.output, "wb") as f:
        f.write(out)
    lo = [min(p[k] for p in placed) for k in range(3)]
    hi = [max(p[k] for p in placed) for k in range(3)]
    print(f"model_import: {opts.output}: {len(placed)} vertices, {len(indices)} indices ({len(indices) // 3} "
          f"triangles), {len(out)} bytes; bounds x {lo[0]:.3f}..{hi[0]:.3f} y {lo[1]:.3f}..{hi[1]:.3f} "
          f"z {lo[2]:.3f}..{hi[2]:.3f}; scale {scale:.4g}, light {light[0]:.2f},{light[1]:.2f},{light[2]:.2f}"
          + (f"; {skipped} primitive(s) not triangles, left out" if skipped else "")
          + ("; colour " + opts.colour if flat is not None and "COLOR_0" not in str(meshes[0]) else "")
          + ("; version 2" if skinned else "; version 1" + (" (--static: the skin left out)" if skin_node else "")))
    if notes:
        print(notes)


if __name__ == "__main__":
    main()
