#!/usr/bin/env python3
"""A placeholder figure as a glTF with vertex colours (task 102, D-025).

    python3 tools/model_placeholder.py OUT.gltf [--no-colour]

Writes OUT.gltf and its buffer OUT.bin beside it: one mesh, one triangle primitive with POSITION, NORMAL and COLOR_0
(unsigned short normalised RGBA, linear, as Blender's exporter writes it) and u16 indices. The figure is about 410
triangles and 1 unit tall, in the export convention models/README.md gives: y up, the front toward +z, the feet at
the origin. It is a pit marshal in outline: two legs (dark grey), a capsule body and two arms (orange), a head
(white) with a yellow visor on its front, so a capture shows which way a placed figure faces. It stands in for Erik's
model until that exists: tools/model_import.py turns it into models/pitguy.pmdl. --no-colour leaves COLOR_0 out (the
importer refuses such a file without --colour: the check of that rule). Standard library only; the figure is ours.
"""
import argparse
import json
import math
import os
import struct
import sys

LEG = (0.24, 0.25, 0.27)      # sRGB 0..1
SUIT = (0.93, 0.42, 0.10)
HELMET = (0.90, 0.90, 0.88)
VISOR = (0.98, 0.80, 0.05)


def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Mesh:
    def __init__(self):
        self.positions, self.normals, self.colours, self.indices = [], [], [], []

    def vertex(self, p, n, colour):
        self.positions.append(p)
        self.normals.append(n)
        self.colours.append(colour)
        return len(self.positions) - 1

    def capsule(self, a, b, radius, segments, rings, colour, squash_z=1.0, colour_of=None):
        """A capsule from point a to point b (the centres of its two hemispheres): `segments` around, `rings` per
        hemisphere. The frame: w along a->b, u and v across it; z of every offset scaled by squash_z."""
        w = [b[i] - a[i] for i in range(3)]
        length = math.sqrt(sum(x * x for x in w))
        w = [x / length for x in w]
        helper = (0.0, 0.0, 1.0) if abs(w[2]) < 0.9 else (1.0, 0.0, 0.0)
        u = cross(w, helper)
        u = normalise(u)
        v = cross(w, u)
        # Rows from the bottom pole (at a) to the top pole (at b): the bottom hemisphere's rings, then the top's.
        rows = []
        for k in range(rings + 1):  # bottom hemisphere: angle from -90 to 0 degrees
            rows.append((a, -math.pi / 2 + (math.pi / 2) * k / rings))
        for k in range(rings + 1):  # top hemisphere: 0 to 90
            rows.append((b, (math.pi / 2) * k / rings))
        grid = []
        for centre, phi in rows:
            ring = []
            count = 1 if abs(abs(phi) - math.pi / 2) < 1e-9 else segments
            for s in range(count):
                theta = 2 * math.pi * s / segments
                d = [math.cos(phi) * (math.cos(theta) * u[i] + math.sin(theta) * v[i]) + math.sin(phi) * w[i]
                     for i in range(3)]
                offset = [d[0] * radius, d[1] * radius, d[2] * radius * squash_z]
                p = tuple(centre[i] + offset[i] for i in range(3))
                n = normalise([d[0], d[1], d[2] / squash_z if squash_z else d[2]])
                c = colour_of(p, n) if colour_of else colour
                ring.append(self.vertex(p, tuple(n), c))
            grid.append(ring)
        for r in range(len(grid) - 1):
            lower, upper = grid[r], grid[r + 1]
            if len(lower) == 1 and len(upper) == 1:
                continue
            for s in range(segments):
                s1 = (s + 1) % segments
                if len(lower) == 1:      # the bottom pole's fan
                    self.tri(lower[0], upper[s1], upper[s])
                elif len(upper) == 1:    # the top pole's fan
                    self.tri(lower[s], lower[s1], upper[0])
                else:                    # a band; the one between the equators is the cylinder
                    self.quad(lower[s], lower[s1], upper[s1], upper[s])

    def tri(self, i, j, k):
        # Counter-clockwise seen from outside, glTF's front face: fix the winding by the outward normal.
        p = [self.positions[x] for x in (i, j, k)]
        face = cross([p[1][t] - p[0][t] for t in range(3)], [p[2][t] - p[0][t] for t in range(3)])
        n = [sum(self.normals[x][t] for x in (i, j, k)) for t in range(3)]
        if sum(face[t] * n[t] for t in range(3)) < 0:
            j, k = k, j
        self.indices += [i, j, k]

    def quad(self, i, j, k, m):
        self.tri(i, j, k)
        self.tri(i, k, m)


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def normalise(a):
    length = math.sqrt(sum(x * x for x in a)) or 1.0
    return [x / length for x in a]


def figure():
    m = Mesh()
    # Legs: feet at y 0 (the capsules' bottoms), up to the hips.
    for x in (-0.075, 0.075):
        m.capsule((x, 0.05, 0.0), (x, 0.44, 0.0), 0.05, 6, 2, LEG)
    # Body: hips to shoulders, a little flat front to back.
    m.capsule((0.0, 0.47, 0.0), (0.0, 0.73, 0.0), 0.145, 10, 3, SUIT, squash_z=0.7)
    # Arms: shoulder to hand, hanging a little away from the body.
    for side in (-1, 1):
        m.capsule((side * 0.165, 0.76, 0.0), (side * 0.205, 0.47, 0.01), 0.042, 6, 2, SUIT)

    # Head: a sphere (a capsule of no length would divide by zero; two close centres), the visor on its front.
    def head_colour(p, n):
        return VISOR if n[2] > 0.45 and -0.15 < n[1] < 0.55 else HELMET

    m.capsule((0.0, 0.905, 0.0), (0.0, 0.906, 0.0), 0.094, 10, 3, HELMET, colour_of=head_colour)
    return m


def write(path, mesh, colours):
    base = os.path.splitext(path)[0]
    bin_path = base + ".bin"
    count = len(mesh.positions)
    blob = bytearray()
    views, accessors = [], []

    def add(data, target, accessor):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        accessor["bufferView"] = len(views) - 1
        accessors.append(accessor)
        return len(accessors) - 1

    lo = [min(p[i] for p in mesh.positions) for i in range(3)]
    hi = [max(p[i] for p in mesh.positions) for i in range(3)]
    attributes = {
        "POSITION": add(b"".join(struct.pack("<3f", *p) for p in mesh.positions), 34962,
                        {"componentType": 5126, "count": count, "type": "VEC3", "min": lo, "max": hi}),
        "NORMAL": add(b"".join(struct.pack("<3f", *n) for n in mesh.normals), 34962,
                      {"componentType": 5126, "count": count, "type": "VEC3"}),
    }
    if colours:
        data = b"".join(struct.pack("<4H", *(round(to_linear(c) * 65535) for c in colour), 65535)
                        for colour in mesh.colours)
        attributes["COLOR_0"] = add(data, 34962, {"componentType": 5123, "normalized": True, "count": count,
                                                  "type": "VEC4"})
    indices = add(struct.pack(f"<{len(mesh.indices)}H", *mesh.indices), 34963,
                  {"componentType": 5123, "count": len(mesh.indices), "type": "SCALAR"})
    doc = {
        "asset": {"version": "2.0", "generator": "pure-recomp tools/model_placeholder.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "placeholder_marshal"}],
        "meshes": [{"name": "placeholder_marshal",
                    "primitives": [{"attributes": attributes, "indices": indices, "mode": 4}]}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob), "uri": os.path.basename(bin_path)}],
    }
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(bin_path, "wb") as f:
        f.write(blob)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    print(f"model_placeholder: {path} and {os.path.basename(bin_path)}: {count} vertices, "
          f"{len(mesh.indices) // 3} triangles{'' if colours else ', no COLOR_0'}; "
          f"bounds x {lo[0]:.3f}..{hi[0]:.3f} y {lo[1]:.3f}..{hi[1]:.3f} z {lo[2]:.3f}..{hi[2]:.3f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("out", help="the .gltf to write (its .bin goes beside it)")
    parser.add_argument("--no-colour", action="store_true", help="leave COLOR_0 out")
    opts = parser.parse_args()
    if not opts.out.endswith(".gltf"):
        sys.exit("model_placeholder: OUT must end in .gltf")
    write(opts.out, figure(), not opts.no_colour)


if __name__ == "__main__":
    main()
