"""Build Vineta K's original, vertex-coloured five-layer sky.

Blender --background --python-exit-code 1 --python tools/model_sky_vineta_k.py -- out/sky-vineta-k

Coordinates in construction functions are game-space: Y up, city toward -Z.
No reference images are loaded, sampled, or embedded. Palette values are sRGB.
"""
import argparse
import itertools
import json
import math
from pathlib import Path
import random
import struct
import sys

import bpy
from mathutils import Vector


EYE = (.02, .38, -.02)
SHELL = 1.045
CORNER_PLANE = 2.967
MAX_RADIUS = 1.72
BUDGETS = {"dome": (450, 600), "clouds_high": (400, 800),
           "horizon_far": (540, 660), "horizon_city": (1500, 2500), "sea": (90, 120)}
PLANES = list(itertools.product((-1, 1), repeat=3))


def mix(first, second, amount):
    amount = max(0, min(1, amount))
    return tuple(start + (end - start) * amount for start, end in zip(first, second))


def linear(colour):
    return tuple(channel / 12.92 if channel <= .04045 else ((channel + .055) / 1.055) ** 2.4
                 for channel in colour) + (1,)


def blender_point(point):
    return point[0], -point[2], point[1]


def game_point(point):
    return point[0], point[2], -point[1]


def bounds(points):
    return {"min": [min(point[axis] for point in points) for axis in range(3)],
            "max": [max(point[axis] for point in points) for axis in range(3)]}


def clipped(polygon):
    for normal in PLANES:
        result = []
        for start, end in zip(polygon, polygon[1:] + polygon[:1]):
            start_distance = sum(value * axis for value, axis in zip(start, normal)) - CORNER_PLANE
            end_distance = sum(value * axis for value, axis in zip(end, normal)) - CORNER_PLANE
            if start_distance <= 0:
                result.append(start)
            if (start_distance < 0 < end_distance) or (end_distance < 0 < start_distance):
                amount = start_distance / (start_distance - end_distance)
                result.append(tuple(value + (other - value) * amount for value, other in zip(start, end)))
        polygon = result
    return polygon


class Layer:
    def __init__(self, name):
        self.name = name
        self.vertices = []
        self.faces = []
        self.colours = []
        self.groups = {}

    def polygon(self, points, colour, group="surface", clip=False):
        points = clipped(points) if clip else points
        for index in range(1, len(points) - 1):
            triangle = (points[0], points[index], points[index + 1])
            area = (Vector(triangle[1]) - Vector(triangle[0])).cross(Vector(triangle[2]) - Vector(triangle[0])).length
            if area < 1e-10:
                continue
            first = len(self.vertices)
            self.vertices.extend(triangle)
            self.faces.append((first, first + 1, first + 2))
            self.colours.extend(colour(point) if callable(colour) else colour for point in triangle)
            self.groups.setdefault(group, []).extend(range(first, first + 3))

    def box(self, left, right, bottom, top, back, front, colour, group):
        points = [(left, bottom, back), (right, bottom, back), (right, top, back), (left, top, back),
                  (left, bottom, front), (right, bottom, front), (right, top, front), (left, top, front)]
        for indices, shade in [((4, 5, 6, 7), colour), ((0, 4, 7, 3), mix(colour, (1, .94, .73), .28)),
                               ((5, 1, 2, 6), mix(colour, (.24, .31, .43), .38)),
                               ((3, 7, 6, 2), mix(colour, (.96, .90, .73), .35)),
                               ((1, 0, 3, 2), colour), ((0, 1, 5, 4), colour)]:
            self.polygon([points[index] for index in indices], shade, group)

    def validate(self):
        minimum, maximum = BUDGETS[self.name]
        assert minimum <= len(self.faces) <= maximum, (self.name, len(self.faces), BUDGETS[self.name])
        for point in self.vertices:
            assert all(math.isfinite(value) for value in point), (self.name, point)
            assert max(abs(point[0]), point[1], abs(point[2])) >= 1 - 1e-7, (self.name, "inside cube", point)
            assert Vector(point).length <= MAX_RADIUS + 1e-7, (self.name, "radius", point)
        return {"triangles": len(self.faces), "budget": BUDGETS[self.name], "bounds_game": bounds(self.vertices),
                "minimum_face_distance": min(max(abs(point[0]), point[1], abs(point[2])) for point in self.vertices),
                "maximum_radius": max(Vector(point).length for point in self.vertices),
                "parts": {name: len(indices) // 3 for name, indices in self.groups.items()}}

    def object(self, material):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata([blender_point(point) for point in self.vertices], [], self.faces)
        mesh.update()
        colour = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        mesh.color_attributes.active_color = colour
        for loop in mesh.loops:
            colour.data[loop.index].color = linear(self.colours[loop.vertex_index])
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.data.materials.append(material)
        for name, indices in self.groups.items():
            obj.vertex_groups.new(name=name).add(indices, 1, "REPLACE")
        return obj


def sky_colour(point):
    height = point[1]
    stops = [(-1, (.25, .39, .51)), (.15, (.48, .61, .67)), (.30, (.88, .90, .86)),
             (.38, (.97, .96, .89)), (.50, (.95, .94, .84)), (.66, (.72, .77, .79)),
             (.83, (.48, .59, .75)), (SHELL, (.34, .47, .69))]
    for (lower, start), (upper, end) in zip(stops, stops[1:]):
        if height <= upper:
            shade = mix(start, end, (height - lower) / (upper - lower))
            break
    else:
        shade = stops[-1][1]
    if height >= SHELL - 1e-6:
        shade = mix(shade, (.30, .43, .67), (1 - max(abs(point[0]), abs(point[2]))) / 2)
    warmth = max(0, -point[0]) * max(0, 1 - abs(height - .53) / .4) * .13
    return mix(shade, (1, .91, .66), warmth)


def dome():
    layer = Layer("dome")
    across = [-SHELL + 2 * SHELL * index / 7 for index in range(8)]
    heights = [-1, -.4, .15, .30, .38, .50, .66, .83, SHELL]
    for axis, sign in ((0, -1), (0, 1), (2, -1), (2, 1)):
        for left, right in zip(across, across[1:]):
            for bottom, top in zip(heights, heights[1:]):
                points = [(left, bottom, sign * SHELL), (right, bottom, sign * SHELL),
                          (right, top, sign * SHELL), (left, top, sign * SHELL)]
                if axis == 0:
                    points = [(point[2], point[1], point[0]) for point in points]
                layer.polygon(points, sky_colour, f"side_{axis}_{sign}", clip=True)
    for left, right in zip(across, across[1:]):
        for back, front in zip(across, across[1:]):
            layer.polygon([(left, SHELL, back), (right, SHELL, back),
                           (right, SHELL, front), (left, SHELL, front)], sky_colour, "top", clip=True)
    bevel = CORNER_PLANE - 2 * SHELL
    bottom_bevel = CORNER_PLANE - SHELL - 1
    for sign_x, sign_z in itertools.product((-1, 1), repeat=2):
        layer.polygon([(sign_x * SHELL, SHELL, sign_z * bevel), (sign_x * SHELL, bevel, sign_z * SHELL),
                       (sign_x * bevel, SHELL, sign_z * SHELL)], sky_colour, "corner_bevels")
        layer.polygon([(sign_x * SHELL, -1, sign_z * bottom_bevel),
                       (sign_x * bottom_bevel, -1, sign_z * SHELL),
                       (sign_x * SHELL, -bevel, sign_z * SHELL)], sky_colour, "corner_bevels")
    return layer


def cloud_patch(layer, axis, sign, centre, radii, seed, group):
    segments = 36
    randomizer = random.Random(seed)
    phase = randomizer.random() * math.tau
    rings = []
    for scale, depth in ((.57, 1.016), (1, 1.032)):
        ring = []
        for index in range(segments):
            angle = index * math.tau / segments
            lobe = 1 + .14 * math.sin(7 * angle + phase) + .045 * math.sin(11 * angle - phase)
            horizontal = centre[0] + math.cos(angle) * radii[0] * scale * lobe
            vertical = centre[1] + math.sin(angle) * radii[1] * scale * lobe
            if axis == 1:
                point = (horizontal, depth, vertical)
            elif axis == 0:
                point = (sign * depth, vertical, horizontal)
            else:
                point = (horizontal, vertical, sign * depth)
            ring.append(point)
        rings.append(ring)
    if axis == 1:
        centre_point = (centre[0], 1.012, centre[1])
    elif axis == 0:
        centre_point = (sign * 1.012, centre[1], centre[0])
    else:
        centre_point = (centre[0], centre[1], sign * 1.012)

    def shade(point):
        vertical = point[2] if axis == 1 else point[1]
        height = (vertical - centre[1]) / radii[1]
        sunward = (centre[0] - (point[0] if axis != 0 else point[2])) / radii[0]
        horizontal = (point[0] if axis != 0 else point[2]) - centre[0]
        radius = math.hypot(horizontal / radii[0], height)
        billow = math.cos(horizontal / radii[0] * 9 + phase) * .065
        light = .80 + height * .23 + sunward * .14 - radius * .24 + billow
        return mix((.58, .59, .69), (1, .89, .55), light)

    for index in range(segments):
        following = (index + 1) % segments
        layer.polygon([centre_point, rings[0][index], rings[0][following]], shade, group)
        for inner, outer in zip(rings, rings[1:]):
            layer.polygon([inner[index], outer[index], outer[following], inner[following]], shade, group)


def clouds():
    layer = Layer("clouds_high")
    patches = [(1, 1, (.35, .36), (.48, .37)), (1, 1, (.20, -.16), (.28, .29)),
               (1, 1, (.48, -.58), (.29, .17)), (2, -1, (-.25, .91), (.46, .12)),
               (2, 1, (-.18, .82), (.55, .13)), (0, -1, (.16, .88), (.50, .115)),
               (0, 1, (.06, .87), (.66, .115))]
    for index, (axis, sign, centre, radii) in enumerate(patches):
        cloud_patch(layer, axis, sign, centre, radii, 240 + index, f"cloud_{index + 1:02d}")
    return layer


def subdivided_facet(layer, triangle, divisions, colour, name):
    first, second, third = [Vector(point) for point in triangle]

    def point(row, column):
        return tuple(first + (second - first) * (row / divisions) + (third - first) * (column / divisions))

    def shade(vertex):
        return mix((.76, .79, .78), colour, (vertex[1] - .377) / .20)

    for row in range(divisions):
        for column in range(divisions - row):
            layer.polygon([point(row, column), point(row + 1, column), point(row, column + 1)], shade, name)
            if row + column < divisions - 1:
                layer.polygon([point(row + 1, column), point(row + 1, column + 1), point(row, column + 1)], shade, name)


def ridge(layer, profile, divisions, axis, depth, palette, seed, name):
    randomizer = random.Random(seed)
    columns = []
    for index, (position, peak) in enumerate(profile):
        middle = .38 + (peak - .38) * randomizer.uniform(.30, .62)
        heights = (.377, middle, peak)
        offset = randomizer.uniform(-.055, .055) if index not in (0, len(profile) - 1) else 0
        columns.append([(position + (offset if row == 1 else 0), height, depth) if axis == 2
                        else (depth, height, position + (offset if row == 1 else 0)) for row, height in enumerate(heights)])
    for index, (left, right) in enumerate(zip(columns, columns[1:])):
        for row in range(2):
            colour = palette[1 if right[2][1] >= left[2][1] else 2]
            subdivided_facet(layer, [left[row], right[row], left[row + 1]], divisions, colour, name)
            subdivided_facet(layer, [right[row], right[row + 1], left[row + 1]], divisions, palette[0], name)


def mountains():
    layer = Layer("horizon_far")
    ridge(layer, [(-1, .61), (-.83, .74), (-.58, .95), (-.31, .80), (-.05, .88),
                  (.19, .72), (.41, .79), (.73, .65), (1, .54)], 3, 2, -1.028,
          [(.53, .59, .67), (.61, .65, .70), (.46, .53, .63)], 33, "city_distant_range")
    ridge(layer, [(-1, .49), (-.78, .62), (-.51, .68), (-.25, .58), (.04, .73),
                  (.33, .66), (.56, .70), (.82, .55), (1, .47)], 2, 2, -1.020,
          [(.46, .52, .59), (.55, .59, .61), (.39, .46, .55)], 34, "city_foothills")
    ridge(layer, [(.12, .382), (.29, .42), (.43, .52), (.57, .47), (.73, .63), (.88, .54), (1, .49)],
          2, 2, 1.021, [(.43, .50, .59), (.52, .56, .61), (.36, .43, .52)], 35, "sea_left_ridge")
    ridge(layer, [(-1, .58), (-.86, .52), (-.70, .55), (-.46, .46), (-.28, .40), (-.12, .382)],
          2, 0, -1.023, [(.52, .58, .64), (.61, .65, .67), (.46, .53, .60)], 36, "city_edge")
    return layer


def front_quad(layer, left, right, bottom, top, depth, colour, group):
    layer.polygon([(left, bottom, depth), (right, bottom, depth), (right, top, depth), (left, top, depth)], colour, group)


def tower(layer, centre, width, height, floors, index):
    left, right = centre - width / 2, centre + width / 2
    front, back, base = -1.0045, -1.016, .38
    group = f"tower_{index + 1:02d}"
    stone = [(.77, .77, .70), (.68, .72, .72), (.82, .79, .68)][index % 3]
    layer.box(left, right, base, height, back, front, stone, group)
    layer.box(left - .008, right + .008, base, base + .025, back, front + .001, stone, group)
    layer.box(left + width * .10, right - width * .10, height, min(.75, height + .014),
              back + .002, front - .001, mix(stone, (.92, .87, .71), .3), group)
    for floor in range(floors):
        bottom = base + .03 + (height - base - .04) * floor / floors
        top = base + .03 + (height - base - .04) * (floor + 1) / floors - .006
        glass = mix((.29, .43, .53), (.55, .65, .68), floor / floors)
        for column in range(3):
            window_left = left + .006 + (width - .012) * column / 3
            window_right = left + .006 + (width - .012) * (column + 1) / 3 - .004
            front_quad(layer, window_left, window_right, bottom, top, front + .0003,
                       mix(glass, (.74, .76, .70), .20 if column == 0 else 0), group)
        for side, position in ((-1, left - .0002), (1, right + .0002)):
            layer.polygon([(position, bottom, back + .002), (position, bottom, front - .002),
                           (position, top, front - .002), (position, top, back + .002)],
                          mix(glass, (.86, .79, .58) if side == -1 else (.23, .32, .44), .3), group)
        front_quad(layer, left, right, top, top + .003, front + .0006, mix(stone, (1, .94, .79), .2), group)
    for column in range(4):
        position = left + (width - .004) * column / 3
        front_quad(layer, position, position + .003, base + .027, height, front + .0008, stone, group)


def palm(layer, centre, height, lean, index):
    group = f"palm_{index + 1:02d}"
    base, depth = .382, -1.001
    crown = (centre + lean, base + height, depth)
    layer.polygon([(centre - .0028, base, depth), (centre + .0028, base, depth),
                   (crown[0] + .0016, crown[1], depth), (crown[0] - .0016, crown[1], depth)],
                  (.47, .44, .32), group)
    for frond in range(7):
        angle = math.pi * (.06 + .88 * frond / 6)
        span = height * (.47 + .08 * (frond % 2))
        bend = (crown[0] + math.cos(angle) * span * .6, crown[1] + math.sin(angle) * span * .30, depth + .0002)
        tip = (crown[0] + math.cos(angle) * span, crown[1] - span * .16, depth + .0001)
        edge = (bend[0], bend[1] - height * .07, depth + .0003)
        colour = (.40, .47, .27) if frond < 3 else (.27, .38, .29)
        layer.polygon([crown, bend, edge], colour, group)
        layer.polygon([bend, tip, edge], mix(colour, (.72, .68, .39), .30), group)
    layer.polygon([(crown[0] - .003, crown[1], depth), (crown[0], crown[1] + .027, depth),
                   (crown[0] + .004, crown[1] + .006, depth)], (.40, .46, .26), group)


def city():
    layer = Layer("horizon_city")
    towers = [(-.86, .075, .51, 5), (-.72, .09, .61, 7), (-.57, .10, .67, 8),
              (-.43, .11, .72, 8), (-.28, .095, .69, 8), (-.12, .13, .736, 8),
              (.055, .11, .62, 7), (.20, .12, .65, 7), (.36, .105, .58, 6),
              (.51, .085, .53, 5), (.65, .09, .56, 5), (.81, .075, .49, 5)]
    for index, (centre, width, height, floors) in enumerate(towers):
        tower(layer, centre, width, height, floors, index)
    for index in range(14):
        centre = -.94 + index * .143
        top = .413 + (index % 3) * .008
        layer.box(centre - .055, centre + .055, .38, top, -1.013, -1.0028,
                  (.66, .68, .63), f"quayside_block_{index + 1:02d}")
        front_quad(layer, centre - .045, centre + .045, .389, top - .007, -1.0026,
                   (.40, .49, .52), f"quayside_block_{index + 1:02d}")
    layer.box(-1, 1, .365, .38, -1.015, -1.0018, (.57, .59, .54), "quay")
    front_quad(layer, -1, 1, .376, .38, -1.0016, (.85, .81, .66), "quay")
    for index in range(23):
        palm(layer, -.96 + index * .087, .055 + (index * 7 % 5) * .009,
             .005 * ((index % 3) - 1), index)
    return layer


def sea():
    layer = Layer("sea")
    across = [-1.01, -.505, 0, .505, 1.01]
    heights = [-1, -.25, .15, .28, .379]

    def shade(point):
        height = point[1]
        colour = mix((.26, .41, .53), (.64, .73, .75), (height + 1) / 1.38)
        colour = mix(colour, (.89, .90, .83), (height - .20) / .18)
        return mix(colour, (.88, .83, .65), max(0, -point[0]) * max(0, (height + .20) / .58) * .28)

    for axis, sign in ((2, 1), (0, -1), (0, 1)):
        for left, right in zip(across, across[1:]):
            for bottom, top in zip(heights, heights[1:]):
                points = [(left, bottom, sign * 1.008), (right, bottom, sign * 1.008),
                          (right, top, sign * 1.008), (left, top, sign * 1.008)]
                if axis == 0:
                    points = [(point[2], point[1], point[0]) for point in points]
                layer.polygon(points, shade, f"sea_{axis}_{sign}", clip=True)
    return layer


def make_material():
    material = bpy.data.materials.new("Sky_Vertex_Colour_Unlit")
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Color"
    material.node_tree.links.new(attribute.outputs["Color"], output.inputs["Surface"])
    return material


def export_and_check(obj, output, expected):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = output / f"{obj.name}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_yup=True, export_normals=True, export_texcoords=False,
                              export_materials="EXPORT", export_animations=False,
                              export_all_vertex_colors=False)
    payload = path.read_bytes()
    length, chunk_type = struct.unpack_from("<II", payload, 12)
    assert chunk_type == 0x4E4F534A
    document = json.loads(payload[20:20 + length])
    assert not document.get("images") and not document.get("textures"), obj.name
    assert len(document["meshes"]) == 1, obj.name
    for material in document["materials"]:
        assert "KHR_materials_unlit" in material.get("extensions", {}), (obj.name, "unlit material missing")
        assert material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1]) == [1, 1, 1, 1], obj.name
    triangles = 0
    for primitive in document["meshes"][0]["primitives"]:
        assert "COLOR_0" in primitive["attributes"], obj.name
        assert primitive.get("mode", 4) == 4, obj.name
        triangles += document["accessors"][primitive["indices"]]["count"] // 3
        position_bounds = document["accessors"][primitive["attributes"]["POSITION"]]
        for key in ("min", "max"):
            assert max(abs(first - second) for first, second in zip(position_bounds[key], expected["bounds_game"][key])) < 1e-5
    assert triangles == expected["triangles"], (obj.name, triangles)
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = set(bpy.data.objects) - existing
    points = [game_point(imported_obj.matrix_world @ vertex.co) for imported_obj in imported
              if imported_obj.type == "MESH" for vertex in imported_obj.data.vertices]
    actual = bounds(points)
    error = max(abs(actual[key][axis] - expected["bounds_game"][key][axis])
                for key in ("min", "max") for axis in range(3))
    assert error < 1e-5, (obj.name, "roundtrip", error)
    assert all(max(abs(point[0]), point[1], abs(point[2])) >= 1 - 1e-6 and Vector(point).length <= MAX_RADIUS + 1e-6
               for point in points), obj.name
    for imported_obj in imported:
        bpy.data.objects.remove(imported_obj, do_unlink=True)
    expected.update(glb=path.name, export_triangles=triangles, reimport_bounds_game=actual,
                    reimport_max_bounds_error=error, vertex_colour=True, image_textures=False)


def make_camera(scene, name, direction):
    data = bpy.data.cameras.new(name)
    data.type = "PERSP"
    data.lens_unit = "FOV"
    data.angle = math.radians(90)
    data.clip_start = .001
    data.clip_end = 10
    camera = bpy.data.objects.new(name, data)
    scene.collection.objects.link(camera)
    camera.location = blender_point(EYE)
    camera.rotation_euler = Vector(blender_point(direction)).to_track_quat("-Z", "Y").to_euler()
    return camera


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--resolution", type=int, default=1024)
    parser.add_argument("--skip-render", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = arguments.resolution
    scene.render.resolution_y = arguments.resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.world = bpy.data.worlds.new("No_External_Lighting")
    scene.world.color = (0, 0, 0)
    material = make_material()
    objects, reports = [], {}
    for build in (dome, clouds, mountains, city, sea):
        layer = build()
        reports[layer.name] = layer.validate()
        objects.append(layer.object(material))
        print(f"SKY {layer.name}: {len(layer.faces)} triangles", flush=True)
    for obj in objects:
        export_and_check(obj, output, reports[obj.name])
    cameras = [("preview-city-minus-z", (0, 0, -1)), ("preview-sea-plus-z", (0, 0, 1)),
               ("preview-up", (0, 1, 0))]
    camera_objects = []
    for name, direction in cameras:
        camera = make_camera(scene, name, direction)
        camera_objects.append(camera)
        scene.camera = camera
        if not arguments.skip_render:
            scene.render.filepath = str(output / f"{name}.png")
            bpy.ops.render.render(write_still=True)
    scene.camera = camera_objects[0]
    bpy.ops.object.select_all(action="DESELECT")
    objects[3].select_set(True)
    bpy.context.view_layer.objects.active = objects[3]
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
                area.spaces.active.shading.type = "MATERIAL"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "sky-vineta-k.blend"))
    manifest = {"generator": "tools/model_sky_vineta_k.py", "name": "Vineta K — afternoon harbour",
                "coordinates": "Game/glTF: Y up; Blender: Z up, -Y maps to game +Z",
                "camera_game": EYE, "horizon_y": .38, "runtime_scale": 50,
                "draw_order": list(reports), "total_triangles": sum(report["triangles"] for report in reports.values()),
                "layers": reports, "radius_limit": MAX_RADIUS,
                "depth_rule": "Every vertex: abs(X)>=1 OR abs(Z)>=1 OR Y>=1; radius<=1.72",
                "decisions": ["Dome at 1.045, relief layers at 1.001–1.032; stricter prompt depth rule retained.",
                              "Corner bevels meet D-026's tighter 1.72 radius; no bottom face.",
                              "Hand-authored sRGB palette converted to linear vertex colours; unlit materials.",
                              "Twelve towers, twenty-three palms; top -X quarter and +X free of tall geometry.",
                              "No reference pixels, textures, sun disc, placement changes, or engine modifications."],
                "previews": [{"file": f"{name}.png", "eye_game": EYE, "direction_game": direction, "horizontal_fov": 90}
                             for name, direction in cameras],
                "validation": "Geometry budgets, finite nondegenerate triangles, strict depth, GLB COLOR_0/no images, and Blender reimport bounds passed."}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    readme = """# Vineta K: afternoon harbour

Original procedural, vertex-coloured geometry. No game/HD images are embedded or sampled.

Open `sky-vineta-k.blend`; the saved camera looks toward the city. Numpad 0 enters camera view.
The three `preview-*.png` images are exact-eye, 90-degree views toward -Z, +Z, and up.
Five named mesh objects correspond to the five standalone GLBs. Vertex groups identify editable parts.
Material Preview/Rendered shows the unlit Color attribute; Solid mode can use Color Type: Attribute.

Rebuild from the repository root:
```
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/model_sky_vineta_k.py -- out/sky-vineta-k
```

Draw order: dome, clouds_high, horizon_far, horizon_city, sea. Game/glTF Y is up; city is -Z.
The eye is (0.02, 0.38, -0.02), not the cube centre. No bottom and no modelled sun disc.
The dome lies at 1.045; other layers lie closer, but still outside the original unit cube.
This deliberately satisfies the prompt's stricter face-depth rule despite D-026 now permitting 0.9.
Corner bevels keep radius <=1.72. Cloud relief is <=0.033. Tower bases are 0.38, tallest roof 0.75.
The top's -X quarter and the +X face have no towers or mountains; only thin clouds/sky/sea.

For the runtime importer, use BOTH `--as-is --no-light` on each GLB, for example:
```
python3 tools/model_import.py out/sky-vineta-k/dome.glb out/sky-vineta-k/dome.pmdl --as-is --no-light
```
Do not normalize these to figure height. No models.ini entry is installed by this builder.
Manifest records budgets, game-space bounds, depth extrema and GLB reimport errors.
Visual approval, in-game sun/depth checks, and moving/parallax seam checks remain integration work.
"""
    (output / "README.md").write_text(readme)
    print(f"SKY COMPLETE: {manifest['total_triangles']} triangles; {output}", flush=True)


if __name__ == "__main__":
    main()
