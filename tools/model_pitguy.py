"""Build the vertex-coloured pit marshal with Blender's Python runtime.

Run: Blender --background --python-exit-code 1 --python tools/model_pitguy.py -- out/pitguy-v2
Writes editable Blender source, a single-mesh GLB, and front, back and three-quarter previews.
The figure faces Blender -Y, stands on Z=0, and stays within the game's 2,000-triangle budget.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector


SUIT = (.205, .222, .225)
PANEL = (.285, .315, .325)
RUBBER = (.065, .078, .082)
EDGE = (.115, .135, .14)
HELMET = (.105, .12, .125)
MASK = (.32, .34, .34)
AMBER = (.94, .59, .105)
parts = []
materials = {}
TORSO = [(1.145, 0, .004, .19, .115), (1.17, 0, 0, .198, .119),
         (1.37, 0, 0, .213, .129), (1.42, 0, 0, .234, .139),
         (1.60, 0, .006, .252, .137), (1.655, 0, .008, .225, .12),
         (1.705, 0, .012, .105, .085)]


def tinted(colour, factor):
    return tuple(min(1, channel * factor) for channel in colour)


def mesh_object(name, vertices, faces, colour, smooth=False, face_colours=None, surface="cloth"):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    attribute = mesh.color_attributes.new(name="Color", type="BYTE_COLOR", domain="CORNER")
    mesh.color_attributes.active_color = attribute
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth and len(polygon.vertices) == 4
        shade = face_colours[polygon.index] if face_colours else colour
        for loop_index in polygon.loop_indices:
            attribute.data[loop_index].color_srgb = (*shade, 1)
    key = (colour, surface)
    if key not in materials:
        material = bpy.data.materials.new(name)
        material.diffuse_color = (*colour, 1)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        vertex_colour = material.node_tree.nodes.new("ShaderNodeVertexColor")
        vertex_colour.layer_name = "Color"
        material.node_tree.links.new(vertex_colour.outputs["Color"], shader.inputs["Base Color"])
        shader.inputs["Roughness"].default_value = {"cloth": .83, "shell": .55, "visor": .25}[surface]
        materials[key] = material
    mesh.materials.append(materials[key])
    parts.append(obj)
    return obj


def loft(name, rings, colour, segments=8, power=1, band_colours=None, surface="cloth", cap_top=True):
    vertices = []
    for height, centre_x, centre_y, radius_x, radius_y in rings:
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            cosine, sine = math.cos(angle), math.sin(angle)
            vertices.append((centre_x + radius_x * math.copysign(abs(cosine) ** power, cosine),
                             centre_y + radius_y * math.copysign(abs(sine) ** power, sine), height))
    faces = [tuple(reversed(range(segments)))]
    shades = [colour]
    for row in range(len(rings) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((row * segments + index, row * segments + next_index,
                          (row + 1) * segments + next_index, (row + 1) * segments + index))
            shades.append(band_colours[row] if band_colours else colour)
    if cap_top:
        faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
        shades.append(colour)
    return mesh_object(name, vertices, faces, colour, smooth=True, face_colours=shades, surface=surface)


def patch(name, corners, colour, depth=.004, surface="cloth", conform=None):
    centre = sum((Vector(corner) for corner in corners), Vector()) / 4
    normal = (Vector(corners[1]) - Vector(corners[0])).cross(Vector(corners[3]) - Vector(corners[0])).normalized()
    inner = [tuple(centre + (Vector(corner) - centre) * .84 + normal * depth) for corner in corners]
    if conform:
        inner = [tuple(Vector(conform(point)) + normal * depth) for point in inner]
        inner.append(tuple(Vector(conform(centre)) + normal * depth))
    faces = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    faces += [(4, 5, 8), (5, 6, 8), (6, 7, 8), (7, 4, 8)] if conform else [(4, 5, 6, 7)]
    obj = mesh_object(name, list(corners) + inner, faces, colour,
                      face_colours=[tinted(colour, .78)] * 4 + [colour] * (len(faces) - 4), surface=surface)
    for polygon in obj.data.polygons:
        polygon.use_smooth = polygon.index >= 4
    return obj


def sheet(name, rows, colour, surface="cloth"):
    columns = len(rows[0])
    vertices = [point for row in rows for point in row]
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            start = row * columns + column
            faces.append((start, start + 1, start + columns + 1, start + columns))
    return mesh_object(name, vertices, faces, colour, smooth=True, surface=surface)


def profile_point(rings, horizontal, height, back=False, offset=.003, power=1):
    for lower, upper in zip(rings, rings[1:]):
        if lower[0] <= height <= upper[0]:
            fraction = (height - lower[0]) / (upper[0] - lower[0])
            profile = [bottom + fraction * (top - bottom) for bottom, top in zip(lower, upper)]
            width, depth = profile[3:]
            distance = depth * max(0, 1 - abs((horizontal - profile[1]) / width) ** (2 / power)) ** (power / 2) + offset
            return (horizontal, profile[2] + (distance if back else -distance), height)
    raise ValueError(f"Height outside profile: {height}")


def torso_point(horizontal, height, back=False, offset=.003):
    return profile_point(TORSO, horizontal, height, back, offset, power=.8)


def torso_strip(name, left, right, heights, colour, back=False, offset=.009):
    rows = [[torso_point(horizontal, height, back, offset) for horizontal in (left, right)] for height in heights]
    if back:
        rows = [list(reversed(row)) for row in rows]
    return sheet(name, rows, colour)


def make_torso():
    loft("Suit - fitted torso", TORSO, EDGE, segments=12, power=.8)
    loft("Collar - padded seal", [(1.665, 0, .005, .09, .082), (1.745, 0, .005, .084, .078)], RUBBER)
    for side, sign in (("Left", -1), ("Right", 1)):
        for row, (bottom, top) in enumerate(((1.435, 1.49), (1.498, 1.555), (1.563, 1.625))):
            for column in range(3):
                inside, outside = .016 + column * .059, .016 + column * .059 + .052
                left, right = sorted((sign * inside, sign * outside))
                corners = [torso_point(left, bottom), torso_point(right, bottom),
                           torso_point(right, top), torso_point(left, top)]
                patch(f"{side} vest - quilt {row + 1}.{column + 1}", corners,
                      tinted(PANEL, 1 - column * .06 + row * .025),
                      conform=lambda point: torso_point(point[0], point[2]))
        for row, (bottom, top) in enumerate(((1.19, 1.25), (1.26, 1.315), (1.325, 1.375))):
            for column in range(2):
                left, right = sorted((sign * (.02 + column * .082), sign * (.092 + column * .082)))
                corners = [torso_point(left, bottom), torso_point(right, bottom),
                           torso_point(right, top), torso_point(left, top)]
                patch(f"{side} abdomen - quilt {row + 1}.{column + 1}", corners, tinted(PANEL, .81),
                      conform=lambda point: torso_point(point[0], point[2]))
        left, right = sorted((sign * .194, sign * .214))
        torso_strip(side + " harness - webbing", left, right, (1.18, 1.37, 1.42, 1.60, 1.645), RUBBER)
        for row, (bottom, top) in enumerate(((1.24, 1.38), (1.445, 1.53), (1.54, 1.625))):
            left, right = sorted((sign * .023, sign * .173))
            patch(f"{side} back - pad {row + 1}",
                  [torso_point(right, bottom, True, .012), torso_point(left, bottom, True, .012),
                   torso_point(left, top, True, .012), torso_point(right, top, True, .012)], tinted(PANEL, .78),
                  conform=lambda point: torso_point(point[0], point[2], True, .012))
    torso_strip("Vest - centre zip", -.008, .008, (1.18, 1.37, 1.42, 1.60, 1.65), RUBBER)
    for back in (False, True):
        rows = [[torso_point(horizontal, height, back, .012)
                 for horizontal in (-.215, -.15, -.075, 0, .075, .15, .215)]
                for height in (1.386, 1.422)]
        sheet("Harness - " + ("rear" if back else "front") + " chest band",
              [list(reversed(row)) for row in rows] if back else rows, RUBBER)
    loft("Belt - waist webbing", [(1.135, 0, .004, .194, .12), (1.176, 0, .004, .201, .126)], RUBBER,
         segments=12, power=.75)
    patch("Belt - clasp", [(-.026, -.126, 1.137), (.026, -.126, 1.137),
                           (.026, -.126, 1.172), (-.026, -.126, 1.172)], PANEL, .004, "shell")


def make_head():
    loft("Helmet - rounded shell", [(1.712, 0, .007, .077, .077), (1.76, 0, .007, .112, .105),
                                    (1.86, 0, .009, .132, .12), (1.935, 0, .012, .119, .109),
                                    (1.983, 0, .014, .075, .074), (2.00, 0, .014, .025, .031)],
         HELMET, segments=12, surface="shell")
    columns = (-1, -.67, -.33, 0, .33, .67, 1)
    def face_row(width, height, depth, curve=0):
        return [(width * portion, -.126 + .052 * abs(width * portion / .115) ** 1.8 + depth,
                 height + curve * abs(portion)) for portion in columns]
    sheet("Helmet - recessed face opening", [face_row(.102, 1.75, .015, .012),
                                             face_row(.12, 1.902, .015, -.014)], RUBBER, "shell")
    sheet("Visor - curved amber lens", [face_row(.102, 1.865, -.011, -.008),
                                        face_row(.109, 1.895, -.011, -.012)], AMBER, "visor")
    sheet("Visor - top glint", [face_row(.105, 1.888, -.012, -.012),
                               face_row(.105, 1.894, -.012, -.012)], (.99, .75, .27), "visor")
    sheet("Helmet - brow rim", [face_row(.116, 1.9, -.013, -.012),
                                face_row(.12, 1.915, -.008, -.014)], RUBBER, "shell")
    sheet("Face - shaped protective mask", [face_row(.065, 1.719, .022, .012),
                                            face_row(.087, 1.774, -.005, .008),
                                            face_row(.10, 1.825, -.003, -.008),
                                            face_row(.058, 1.852, -.005, -.018)], MASK, "cloth")


def make_trousers():
    vertices, faces, shades, top_rings = [], [], [], []
    profiles = {}
    for side, sign in (("Left", -1), ("Right", 1)):
        centre = sign * .125
        rings = [(.635, centre, -.002, .077, .08), (.70, centre, -.002, .089, .09),
                 (.84, sign * .116, .012, .106, .112), (.99, sign * .11, .018, .103, .115),
                 (1.075, sign * .11, .018, .103, .11)]
        profiles[side] = rings
        leg = loft(side + " trouser", rings, SUIT, band_colours=[EDGE, SUIT, SUIT, SUIT], cap_top=False)
        start = len(vertices)
        vertices.extend(tuple(vertex.co) for vertex in leg.data.vertices)
        faces.extend(tuple(start + index for index in polygon.vertices) for polygon in leg.data.polygons)
        shades.extend([SUIT] + [EDGE] * 8 + [SUIT] * 24)
        top_rings.append([start + 32 + index for index in range(8)])
        parts.remove(leg)
        bpy.data.objects.remove(leg, do_unlink=True)
    left, right = top_rings
    border = [right[index] for index in (0, 1, 2, 3)] + [left[index] for index in (1, 2, 3, 4, 5, 6, 7)]
    border += [right[index] for index in (5, 6, 7)]
    waist = len(vertices)
    for index in border:
        position = vertices[index]
        angle = math.atan2((position[1] - .018) / .12, position[0] / .20)
        vertices.append((.192 * math.cos(angle), .006 + .117 * math.sin(angle), 1.155))
    for index, bottom in enumerate(border):
        next_index = (index + 1) % len(border)
        faces.append((bottom, border[next_index], waist + next_index, waist + index))
        shades.append(SUIT)
    faces.extend([(right[3], right[4], left[0], left[1]), (right[4], right[5], left[7], left[0])])
    shades.extend([SUIT, SUIT])
    mesh_object("Suit - continuous trousers and seat", vertices, faces, SUIT, smooth=True, face_colours=shades)
    return profiles


def make_limbs():
    trousers = make_trousers()
    for side, sign in (("Left", -1), ("Right", 1)):
        centre = sign * .125
        loft(side + " knee - padded cuff", [(.565, centre, -.002, .08, .087),
                                            (.59, centre, -.005, .087, .092),
                                            (.638, centre, -.004, .087, .094),
                                            (.66, centre, -.002, .08, .087)], EDGE,
             band_colours=[RUBBER, EDGE, RUBBER])
        shaft = [(.145, centre, .014, .062, .068), (.20, centre, .014, .068, .075),
                 (.42, centre, .008, .08, .085), (.565, centre, 0, .072, .079)]
        loft(side + " boot - fitted tall shaft", shaft, PANEL,
             band_colours=[EDGE, PANEL, PANEL], surface="shell")
        loft(side + " boot - shaped foot", [(0, centre, -.045, .081, .139),
                                            (.036, centre, -.045, .084, .141),
                                            (.094, centre, -.049, .079, .13),
                                            (.17, centre, .009, .074, .085)], RUBBER, power=.65,
             band_colours=[RUBBER, EDGE, RUBBER], surface="shell")
        rows = [[profile_point(shaft, centre + horizontal, height, offset=.002)
                 for horizontal in (-.009, 0, .009)] for height in (.185, .33, .54)]
        sheet(side + " boot - front seam", rows, EDGE, "shell")
        for row, height in enumerate((.755, .85)):
            span = .072 if row == 0 else .084
            rows = [[profile_point(trousers[side], centre + horizontal, height + rise + shift, offset=.009)
                     for horizontal, rise in ((-span, .004), (-span / 2, .01), (0, .014),
                                              (span / 2, .007), (span, 0))] for shift in (0, .006)]
            sheet(f"{side} trouser - fold {row + 1}", rows, tinted(SUIT, .76))
        sleeve = [(1.055, sign * .341, -.028, .046, .052),
                                              (1.10, sign * .343, -.012, .055, .062),
                                              (1.25, sign * .342, .018, .071, .073),
                                              (1.31, sign * .338, .024, .069, .075),
                                              (1.43, sign * .324, .018, .082, .09),
                                              (1.565, sign * .29, .012, .093, .103),
                  (1.637, sign * .267, .012, .072, .082), (1.67, sign * .247, .012, .026, .035)]
        loft(side + " sleeve - relaxed arm", sleeve, SUIT,
             band_colours=[EDGE, SUIT, RUBBER, SUIT, SUIT, EDGE, EDGE])
        loft(side + " glove - cuff and fingers", [(.895, sign * .346, -.033, .034, .04),
                                                  (.925, sign * .348, -.04, .047, .051),
                                                  (.99, sign * .344, -.032, .052, .054),
                                                  (1.055, sign * .341, -.028, .046, .052)], RUBBER,
             band_colours=[RUBBER, EDGE, RUBBER])
        loft(side + " glove - thumb", [(.931, sign * .298, -.058, .018, .021),
                                         (.982, sign * .30, -.052, .026, .025)], RUBBER, segments=6)
        corners = [profile_point(sleeve, sign * .341 + horizontal, height)
                   for horizontal, height in ((-.028, 1.075), (.028, 1.075), (.038, 1.225), (-.038, 1.225))]
        patch(side + " forearm - inset guard", corners, EDGE,
              conform=lambda point: profile_point(sleeve, point[0], point[2]))
        for height in (1.405, 1.475, 1.545):
            centre_x = sign * (.324 - (height - 1.43) * .25)
            rows = [[profile_point(sleeve, centre_x + horizontal, height + rise + shift, offset=.003)
                     for horizontal, rise in ((-.055, 0), (0, .004), (.055, 0))] for shift in (0, .005)]
            sheet(f"{side} sleeve - stitch {height}", rows, EDGE)


def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_studio():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.render.resolution_x = 800
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.world.color = (.13, .13, .13)
    scene.view_settings.view_transform = "AgX"
    studio = bpy.data.collections.new("Studio - excluded from GLB")
    scene.collection.children.link(studio)
    for name, position, energy, size in (("Key", (-3, -4, 5), 420, 4),
                                         ("Fill", (3, -2, 3), 180, 3),
                                         ("Rim", (1, 3, 4), 500, 3)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size = energy, "DISK", size
        light = bpy.data.objects.new(name, data)
        studio.objects.link(light)
        light.location = position
        aim(light, (0, 0, 1))
    camera = bpy.data.objects.new("Preview camera", bpy.data.cameras.new("Preview camera"))
    studio.objects.link(camera)
    camera.location = (3, -6, 2.25)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.28
    scene.camera = camera
    aim(camera, (0, 0, 1.01))
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.color_type = "MATERIAL"
                area.spaces.active.region_3d.view_distance = 3.4
                area.spaces.active.region_3d.view_location = (0, 0, 1)
                area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
    return camera


def main():
    output = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
    os.makedirs(output, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    make_torso()
    make_head()
    make_limbs()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.duplicate()
    bpy.ops.object.join()
    export_mesh = bpy.context.object
    export_mesh.name = "Pit marshal"
    export_mesh.data.calc_loop_triangles()
    triangles = len(export_mesh.data.loop_triangles)
    counts = {}
    for obj in parts:
        obj.data.calc_loop_triangles()
        counts[obj.name] = len(obj.data.loop_triangles)
    print(json.dumps({"triangles": triangles, "parts": counts}, indent=2), flush=True)
    if triangles > 2000:
        raise RuntimeError(f"Triangle budget exceeded: {triangles}")
    bpy.ops.export_scene.gltf(filepath=os.path.join(output, "pitguy.glb"), use_selection=True,
                              export_format="GLB", export_yup=True, export_all_vertex_colors=True)
    bpy.data.objects.remove(export_mesh, do_unlink=True)
    camera = setup_studio()
    for obj in parts:
        obj.select_set(False)
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, "pitguy.blend"))
    for name, position in (("front", (0, -6, 1.01)), ("three-quarter", (3, -6, 2.25)),
                           ("back", (3, 6, 2.1))):
        camera.location = position
        aim(camera, (0, 0, 1.01))
        bpy.context.scene.render.filepath = os.path.join(output, name + ".png")
        bpy.ops.render.render(write_still=True)
    with open(os.path.join(output, "model-info.json"), "w") as report:
        json.dump({"triangles": triangles, "vertex_colours": True, "height_metres": 2,
                   "front": "Blender -Y / glTF +Z", "rigged": False}, report, indent=2)
    print(f"Pit marshal: {triangles} triangles; {output}", flush=True)


if __name__ == "__main__":
    main()
