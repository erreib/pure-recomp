#!/usr/bin/env python3
"""A placeholder sky for the models backend's skies (task 106, D-026): two layers written as glTF.

    python3 tools/model_sky_placeholder.py OUT_DIR

Writes OUT_DIR/dome.gltf and OUT_DIR/horizon_city.gltf (one mesh each, POSITION and COLOR_0 in data: URIs) in the
sky's space (models/README.md, "Skies"): the unit cube centred on the origin, y up, the eye at (0.02, 0.38, -0.02),
the horizon at y 0.38. Import each with `tools/model_import.py IN OUT.pmdl --as-is --no-light`.
  - dome: the cube's five faces (four sides and the top, no bottom), 9 x 9 vertices a face like the game's sky
    faces, at distance 1.0 (the faces' own: D-026's depth rule). A vertical gradient: a grey-blue haze below the
    horizon, white from y 0.3 to 0.5, light blue at the sides' top edge, deep blue at the top's centre.
  - horizon_city: a ring of 12 boxes of varied height along the -z face's horizon band, their bases at y 0.30 (just
    under the horizon, so the ground meets them), their tops 0.45 to 0.75, two shades (the faces toward the eye a
    slate blue, the sides and tops a lighter one). Their backs lie on the -z face and their fronts 0.04 inward of it
    (z -0.96): a layer drawn after the dome with the faces' depth test (GREATER) has to be nearer than the dome to
    show, and the prompt's relief allowance (docs/prompts/sky-vineta-k.md: up to 0.05 inward) keeps the sky's depth
    where the sun block reads it.
The colours are given in sRGB and written linear (glTF's COLOR_0 is linear; the importer turns them back). Standard
library only; the sky is ours, no game data.
"""
import base64
import json
import os
import struct
import sys

HAZE_LOW = (168, 184, 204)   # sRGB: the bottom of the sides, under the ground
WHITE = (250, 250, 246)      # the horizon band, y 0.3 to 0.5
EDGE_BLUE = (150, 190, 236)  # the sides' top edge (y 1)
TOP_BLUE = (52, 104, 196)    # the top's centre
CITY_FRONT = (74, 90, 120)   # the boxes' faces toward the eye
CITY_SIDE = (138, 154, 184)  # their sides and tops
RELIEF = 0.04                # the boxes' fronts this far inward of the -z face


def linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def colour(srgb):
    return tuple(linear(x) for x in srgb) + (1.0,)


def mix(a, b, f):
    f = max(0.0, min(1.0, f))
    return tuple(x + (y - x) * f for x, y in zip(a, b))


def gradient(h):
    """The dome's colour for h: a side's y (-1 to 1), or 1 + the top's nearness to its centre (1 to 2)."""
    if h < 0.3:
        return colour(mix(HAZE_LOW, WHITE, (h + 1.0) / 1.3))
    if h <= 0.5:
        return colour(WHITE)
    if h <= 1.0:
        return colour(mix(WHITE, EDGE_BLUE, (h - 0.5) / 0.5))
    return colour(mix(EDGE_BLUE, TOP_BLUE, h - 1.0))


def dome():
    positions, colours, indices = [], [], []
    n = 9
    # Each face: its centre and the two axes spanning it (-1 to 1 on each).
    faces = [((0, 0, 1), (1, 0, 0), (0, 1, 0)),    # +z
             ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),   # -x
             ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),  # -z
             ((1, 0, 0), (0, 0, -1), (0, 1, 0)),   # +x
             ((0, 1, 0), (1, 0, 0), (0, 0, 1))]    # +y, the top
    for centre, a, b in faces:
        first = len(positions)
        top = centre[1] == 1
        for j in range(n):
            for i in range(n):
                s, t = -1.0 + 2.0 * i / (n - 1), -1.0 + 2.0 * j / (n - 1)
                p = tuple(centre[k] + a[k] * s + b[k] * t for k in range(3))
                positions.append(p)
                colours.append(gradient(2.0 - max(abs(p[0]), abs(p[2])) if top else p[1]))
        for j in range(n - 1):
            for i in range(n - 1):
                v = first + j * n + i
                indices += [v, v + 1, v + n, v + 1, v + n + 1, v + n]
    return positions, colours, indices


def city():
    positions, colours, indices = [], [], []
    base, back, front = 0.30, -1.0, -1.0 + RELIEF
    tops = [0.52, 0.66, 0.47, 0.75, 0.58, 0.49, 0.70, 0.55, 0.62, 0.45, 0.68, 0.53]
    pitch = 1.7 / len(tops)  # x from -0.85 to 0.85
    for k, height in enumerate(tops):
        x0 = -0.85 + k * pitch + 0.15 * pitch
        x1 = x0 + pitch * (0.55 + 0.125 * ((k * 7) % 3))

        def corner(ix, iy, iz):
            return (x1 if ix else x0, height if iy else base, front if iz else back)

        # The box's faces as quads: the front (toward +z, the eye), the two sides and the top.
        quads = [((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1), CITY_FRONT),
                 ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0), CITY_SIDE),
                 ((1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1), CITY_SIDE),
                 ((0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0), CITY_SIDE)]
        for *corners, shade in quads:
            first = len(positions)
            for c in corners:
                positions.append(corner(*c))
                colours.append(colour(shade))
            indices += [first, first + 1, first + 2, first, first + 2, first + 3]
    return positions, colours, indices


def check(name, positions):
    """D-026's depth rule with the prompt's relief: on or just inside the cube's surface, within its corners."""
    for p in positions:
        surface = max(abs(p[0]), abs(p[2]), p[1])
        distance = sum(x * x for x in p) ** 0.5
        if surface < 1.0 - RELIEF - 1e-6 or distance > 3 ** 0.5 + 1e-6:
            sys.exit(f"model_sky_placeholder: {name}: vertex {p} breaks the depth rule")


def write(path, positions, colours, indices):
    pos = b"".join(struct.pack("<3f", *p) for p in positions)
    col = b"".join(struct.pack("<4f", *c) for c in colours)
    idx = b"".join(struct.pack("<H", i) for i in indices)
    blob = pos + col + idx + b"\0" * (-len(idx) % 4)
    lo = [min(p[k] for p in positions) for k in range(3)]
    hi = [max(p[k] for p in positions) for k in range(3)]
    doc = {
        "asset": {"version": "2.0", "generator": "pure-recomp tools/model_sky_placeholder.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": os.path.basename(path)[:-5]}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}, "indices": 2, "mode": 4}]}],
        "buffers": [{"byteLength": len(blob),
                     "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode()}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(pos)},
                        {"buffer": 0, "byteOffset": len(pos), "byteLength": len(col)},
                        {"buffer": 0, "byteOffset": len(pos) + len(col), "byteLength": len(idx)}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(positions), "type": "VEC3",
                       "min": lo, "max": hi},
                      {"bufferView": 1, "componentType": 5126, "count": len(colours), "type": "VEC4"},
                      {"bufferView": 2, "componentType": 5123, "count": len(indices), "type": "SCALAR"}],
    }
    with open(path, "w") as f:
        json.dump(doc, f)
    print(f"model_sky_placeholder: {path}: {len(positions)} vertices, {len(indices) // 3} triangles; bounds "
          f"x {lo[0]:.2f}..{hi[0]:.2f} y {lo[1]:.2f}..{hi[1]:.2f} z {lo[2]:.2f}..{hi[2]:.2f}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: model_sky_placeholder.py OUT_DIR")
    os.makedirs(sys.argv[1], exist_ok=True)
    for name, build in (("dome", dome), ("horizon_city", city)):
        positions, colours, indices = build()
        check(name, positions)
        write(os.path.join(sys.argv[1], name + ".gltf"), positions, colours, indices)


if __name__ == "__main__":
    main()
