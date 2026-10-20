"""Build a small vertex-coloured crowd library at the pit marshal's authoring scale.

Blender --background --python-exit-code 1 --python tools/model_crowd.py -- out/crowd-starter
Writes a Blender lineup, eight standalone GLBs/PMDLs, a manifest, and preview renders.
The figures are static pose studies. Stand placement and animation are separate work.
"""
import argparse
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector


FIGURES = [
    dict(name="01_graphite_tee", label="Graphite tee", shirt=(.18, .20, .20), pants=(.26, .34, .40),
         skin=(.70, .48, .35), hair=(.15, .10, .075), pose="relaxed", build="regular", sleeves="short"),
    dict(name="02_navy_stripe", label="Navy / orange stripe", shirt=(.16, .25, .36), pants=(.48, .43, .31),
         skin=(.82, .62, .47), hair=(.27, .16, .09), pose="folded", build="broad", sleeves="short", stripe=(.85, .37, .17)),
    dict(name="03_burgundy_sweater", label="Burgundy sweater", shirt=(.48, .16, .18), pants=(.19, .20, .22),
         skin=(.36, .23, .17), hair=(.065, .055, .05), pose="hips", build="regular", sleeves="long"),
    dict(name="04_ivory_tee", label="Ivory tee", shirt=(.82, .82, .73), pants=(.21, .25, .25),
         skin=(.84, .64, .52), hair=(.13, .115, .10), pose="one_hip", build="slender", sleeves="short"),
    dict(name="05_teal_top", label="Teal top", shirt=(.16, .47, .43), pants=(.19, .28, .37),
         skin=(.60, .38, .25), hair=(.10, .075, .055), pose="clapping", build="slender", sleeves="short", hairstyle="ponytail"),
    dict(name="06_sand_jacket", label="Sand jacket", shirt=(.56, .48, .31), pants=(.24, .27, .28),
         skin=(.43, .29, .21), hair=(.07, .065, .06), pose="relaxed", build="broad", sleeves="long", jacket=True),
    dict(name="07_plum_top", label="Plum top", shirt=(.39, .25, .40), pants=(.23, .23, .24),
         skin=(.48, .30, .22), hair=(.10, .07, .06), pose="folded", build="slender", sleeves="short", hairstyle="long"),
    dict(name="08_race_fan", label="Race fan", shirt=(.82, .84, .79), pants=(.24, .34, .40),
         skin=(.82, .62, .46), hair=(.58, .43, .22), pose="cheering", build="regular", sleeves="short", stripe=(.12, .40, .43)),
]


def tint(colour, factor):
    return tuple(min(1, value * factor) for value in colour)


class FigureMesh:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.colours = []
        self.groups = {}

    def add(self, vertices, faces, colours, group):
        start = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(start + index for index in face) for face in faces)
        self.colours.extend(colours)
        self.groups.setdefault(group, []).extend(range(start, len(self.vertices)))
        return start

    def loft(self, rings, colour, group, segments=8, colour_of=None, cap_top=True, cap_bottom=True):
        vertices, faces, colours = [], [], []
        for height, centre_x, centre_y, width, depth in rings:
            for index in range(segments):
                angle = (index + .5) * math.tau / segments
                vertices.append((centre_x + width * math.cos(angle), centre_y + depth * math.sin(angle), height))
        if cap_bottom:
            faces.append(tuple(reversed(range(segments))))
            colours.append(colour)
        for row in range(len(rings) - 1):
            for index in range(segments):
                next_index = (index + 1) % segments
                face = (row * segments + index, row * segments + next_index,
                        (row + 1) * segments + next_index, (row + 1) * segments + index)
                faces.append(face)
                centre = sum((Vector(vertices[vertex]) for vertex in face), Vector()) / 4
                colours.append(colour_of(row, centre) if colour_of else colour)
        if cap_top:
            faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
            colours.append(colour_of(len(rings) - 1, Vector((0, 0, rings[-1][0]))) if colour_of else colour)
        return self.add(vertices, faces, colours, group)

    def tube(self, points, radii, depths, colours, group, segments=4):
        vertices, faces, shades = [], [], []
        previous_tangent, previous_across = None, None
        for row, point in enumerate(points):
            tangent = Vector(points[min(row + 1, len(points) - 1)]) - Vector(points[max(row - 1, 0)])
            tangent.normalize()
            if previous_tangent is None:
                across = Vector((1, 0, 0))
                if abs(across.dot(tangent)) > .9:
                    across = Vector((0, 1, 0))
            else:
                across = previous_tangent.rotation_difference(tangent) @ previous_across
            across = (across - tangent * across.dot(tangent)).normalized()
            outward = tangent.cross(across)
            previous_tangent, previous_across = tangent.copy(), across.copy()
            for index in range(segments):
                angle = (index + .5) * math.tau / segments
                vertices.append(tuple(Vector(point) + across * (math.cos(angle) * radii[row]) +
                                      outward * (math.sin(angle) * depths[row])))
        faces.append(tuple(reversed(range(segments))))
        shades.append(colours[0])
        for row in range(len(points) - 1):
            for index in range(segments):
                next_index = (index + 1) % segments
                faces.append((row * segments + index, row * segments + next_index,
                              (row + 1) * segments + next_index, (row + 1) * segments + index))
                shades.append(colours[row])
        faces.append(tuple((len(points) - 1) * segments + index for index in range(segments)))
        shades.append(colours[-1])
        self.add(vertices, faces, shades, group)

    def finish(self, name, material):
        data = bpy.data.meshes.new(name)
        data.from_pydata(self.vertices, [], self.faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        colours = data.color_attributes.new(name="Color", type="BYTE_COLOR", domain="CORNER")
        data.color_attributes.active_color = colours
        for polygon in data.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4
            for loop in polygon.loop_indices:
                colours.data[loop].color_srgb = (*self.colours[polygon.index], 1)
        data.materials.append(material)
        for name, indices in self.groups.items():
            obj.vertex_groups.new(name=name).add(indices, 1, "REPLACE")
        data.calc_loop_triangles()
        assert len(data.loop_triangles) <= 350, (obj.name, len(data.loop_triangles))
        for triangle in data.loop_triangles:
            points = [data.vertices[index].co for index in triangle.vertices]
            assert (points[1] - points[0]).cross(points[2] - points[0]).length > 1e-8
        assert abs(min(vertex.co.z for vertex in data.vertices)) < 1e-6
        assert abs(max(vertex.co.z for vertex in data.vertices) - 2) < 1e-6
        return obj


def trousers(mesh, config):
    vertices, faces, colours, top_rings = [], [], [], []
    colour = config["pants"]
    hip = .105 if config["build"] != "broad" else .115
    for side, sign in (("R", -1), ("L", 1)):
        start = len(vertices)
        rings = [(.085, sign * .12, .012, .071, .077), (.58, sign * .118, .005, .085, .095),
                 (1.025, sign * hip, .012, .101, .11)]
        for height, centre_x, centre_y, width, depth in rings:
            for index in range(6):
                angle = index * math.tau / 6
                vertices.append((centre_x + width * math.cos(angle), centre_y + depth * math.sin(angle), height))
        faces.append(tuple(reversed([start + index for index in range(6)])))
        colours.append(colour)
        for row in range(2):
            for index in range(6):
                next_index = (index + 1) % 6
                faces.append((start + row * 6 + index, start + row * 6 + next_index,
                              start + (row + 1) * 6 + next_index, start + (row + 1) * 6 + index))
                colours.append(tint(colour, .88 if index in (0, 2) else 1))
        top_rings.append([start + 12 + index for index in range(6)])
    right, left = top_rings
    border = [left[index] for index in (0, 1, 2)] + [right[index] for index in (1, 2, 3, 4, 5)]
    border += [left[index] for index in (4, 5)]
    waist = len(vertices)
    waist_width = .195 if config["build"] == "broad" else .181
    for index in border:
        point = vertices[index]
        angle = math.atan2((point[1] - .012) / .11, point[0] / .20)
        vertices.append((waist_width * math.cos(angle), .005 + .115 * math.sin(angle), 1.14))
    for index, bottom in enumerate(border):
        next_index = (index + 1) % len(border)
        faces.append((bottom, border[next_index], waist + next_index, waist + index))
        colours.append(colour)
    faces.extend([(left[2], left[3], right[0], right[1]), (left[3], left[4], right[5], right[0])])
    colours.extend([colour, colour])
    mesh.add(vertices, faces, colours, "trousers")
    for sign in (-1, 1):
        vertices = [(sign * .12 + horizontal, depth, height)
                    for height, width, front, back in ((0, .073, -.17, .073), (.115, .067, -.11, .065))
                    for horizontal, depth in ((-width, front), (width, front), (width, back), (-width, back))]
        faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        mesh.add(vertices, faces, [(.095, .105, .11)] * 6, "foot.R" if sign < 0 else "foot.L")


def torso(mesh, config):
    shirt = config["shirt"]
    width = {"slender": .205, "regular": .23, "broad": .255}[config["build"]]
    waist = {"slender": .195, "regular": .202, "broad": .221}[config["build"]]
    rings = [(1.12, 0, .005, waist, .132), (1.39, 0, .002, width * .91, .137),
             (1.60, 0, .01, width, .134), (1.715, 0, .012, .078, .074)]
    def colour_of(row, centre):
        if config.get("jacket") and abs(centre.x) < .10 and centre.y < -.07:
            return (.20, .24, .23)
        return tint(shirt, .91 if centre.y > .03 else 1)
    mesh.loft(rings, shirt, "torso", colour_of=colour_of)
    mesh.loft([(1.69, 0, .012, .068, .067), (1.79, 0, .008, .057, .055)], config["skin"], "neck",
              segments=4, cap_top=False, cap_bottom=False)
    if "stripe" in config:
        vertices = []
        for height in (1.48, 1.525):
            amount = (height - 1.39) / (1.60 - 1.39)
            radius = width * (.91 + .09 * amount)
            depth = .137 - .003 * amount
            for fraction in (-.72, -math.sin(math.pi / 8), 0, math.sin(math.pi / 8), .72):
                span = max(0, (abs(fraction) - math.sin(math.pi / 8)) /
                           (math.cos(math.pi / 8) - math.sin(math.pi / 8)))
                front = -depth * ((1 - span) * math.cos(math.pi / 8) + span * math.sin(math.pi / 8))
                vertices.append((radius * fraction, .002 + .008 * amount + front - .007, height))
        faces = [(index, index + 1, index + 6, index + 5) for index in range(4)]
        mesh.add(vertices, faces, [config["stripe"]] * 4, "torso")
    if config.get("jacket"):
        for sign in (-1, 1):
            mesh.add([(sign * .025, -.146, 1.40), (sign * .10, -.131, 1.60), (sign * .06, -.075, 1.69)],
                     [(0, 1, 2)] if sign > 0 else [(2, 1, 0)], [tint(shirt, 1.15)], "torso")
    return width


def head(mesh, config):
    skin, hair = config["skin"], config["hair"]
    def colour_of(row, centre):
        if row >= 2 or (row == 1 and (centre.y > -.03 or abs(centre.x) > .075)):
            return hair
        return skin
    mesh.loft([(1.755, 0, -.002, .063, .067), (1.855, 0, .003, .095, .091),
               (1.948, 0, .008, .092, .089), (2, 0, .012, .048, .051)],
              skin, "head", colour_of=colour_of)
    mesh.add([(-.013, -.083, 1.865), (.013, -.083, 1.865), (0, -.085, 1.91), (0, -.111, 1.871)],
             [(0, 1, 3), (1, 2, 3), (2, 0, 3)], [tint(skin, .92), skin, tint(skin, 1.06)], "head")
    for sign in (-1, 1):
        centre = sign * .035
        mesh.add([(centre - .009, -.083, 1.914), (centre + .009, -.083, 1.914),
                  (centre + .009, -.083, 1.919), (centre - .009, -.083, 1.919)],
                 [(0, 1, 2, 3)], [tint(hair, .65)], "head")
    mesh.add([(-.014, -.078, 1.812), (.014, -.078, 1.812), (.011, -.078, 1.816), (-.011, -.078, 1.816)],
             [(0, 1, 2, 3)], [tint(skin, .64)], "head")
    if config.get("hairstyle") == "ponytail":
        mesh.tube([(0, .084, 1.92), (0, .14, 1.76)], [.043, .025], [.036, .025], [hair], "head")
    elif config.get("hairstyle") == "long":
        mesh.add([(-.086, .015, 1.93), (-.092, .055, 1.73), (0, .11, 1.73), (.092, .055, 1.73),
                  (.086, .015, 1.93), (0, .095, 1.97)],
                 [(0, 1, 2, 5), (5, 2, 3, 4)], [hair, hair], "head")


def arms(mesh, config, width):
    for sign, side in ((-1, "R"), (1, "L")):
        shoulder = Vector((sign * (width + .012), .008, 1.60))
        elbow = Vector((sign * (width + .07), .012, 1.30))
        wrist = Vector((sign * (width + .08), -.025, 1.055))
        end = wrist + Vector((sign * .005, -.012, -.135))
        if config["pose"] in ("hips", "one_hip") and (sign > 0 or config["pose"] == "hips"):
            elbow = Vector((sign * (width + .16), -.012, 1.34))
            wrist = Vector((sign * (width + .008), -.13, 1.18))
            end = wrist + Vector((-sign * .07, -.025, -.075))
        elif config["pose"] == "folded":
            elbow = Vector((sign * (width + .02), -.065, 1.31))
            wrist = Vector((-sign * .025, -.225 + sign * .014, 1.40 + sign * .025))
            end = wrist + Vector((-sign * .105, 0, .025))
        elif config["pose"] == "clapping":
            elbow = Vector((sign * (width + .075), -.03, 1.34))
            wrist = Vector((sign * .075, -.26, 1.46))
            end = Vector((sign * .035, -.29, 1.56))
        elif config["pose"] == "cheering" and sign < 0:
            elbow = Vector((-.48, -.015, 1.64))
            wrist = Vector((-.43, -.045, 1.875))
            end = Vector((-.42, -.055, 1.98))
        sleeve = shoulder.lerp(elbow, .42)
        colours = [config["shirt"], config["shirt"], config["skin"], config["skin"]]
        if config["sleeves"] == "long":
            colours = [config["shirt"]] * 4
        anchor = shoulder + Vector((-sign * .035, 0, .035))
        mesh.tube([anchor, shoulder, sleeve, elbow, wrist], [.035, .086, .077, .061, .044], [.035, .094, .079, .068, .047],
                  colours, "arm." + side)
        mesh.tube([wrist, end], [.05, .037], [.037, .028], [config["skin"]], "hand." + side)


def material():
    result = bpy.data.materials.new("Crowd - vertex colours")
    result.use_nodes = True
    nodes = result.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = "Color"
    result.node_tree.links.new(colour.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = .82
    return result


def studio():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.world.color = (.15, .15, .15)
    scene.view_settings.view_transform = "AgX"
    for name, position, energy, size in (("Key", (-3, -4, 6), 650, 5), ("Fill", (4, -2, 4), 350, 5),
                                         ("Rim", (0, 4, 5), 650, 4)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.size = energy, size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    camera = bpy.data.objects.new("Preview camera", bpy.data.cameras.new("Preview camera"))
    scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    scene.camera = camera
    return camera


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    parser.add_argument("--scale-reference", default="out/pitguy-v2/pitguy.blend")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = os.path.abspath(args.output)
    os.makedirs(output, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    shared_material = material()
    figures, report = [], []
    for config in FIGURES:
        geometry = FigureMesh()
        trousers(geometry, config)
        width = torso(geometry, config)
        head(geometry, config)
        arms(geometry, config, width)
        obj = geometry.finish(config["name"], shared_material)
        obj["pose"] = config["pose"]
        obj["authoring_height"] = 2.0
        obj["placement"] = "Feet at origin; Blender -Y front; glTF +Z front."
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = os.path.join(output, config["name"] + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_yup=True,
                                  export_all_vertex_colors=True, export_animations=False)
        subprocess.run(["python3", os.path.join(os.path.dirname(__file__), "model_import.py"), path,
                        os.path.join(output, config["name"] + ".pmdl")], check=True)
        report.append({"name": config["name"], "label": config["label"], "pose": config["pose"],
                       "triangles": len(obj.data.loop_triangles), "height": 2, "rigged": False,
                       "glb": config["name"] + ".glb", "pmdl": config["name"] + ".pmdl"})
        obj.select_set(False)
        figures.append(obj)
    camera = studio()
    scene = bpy.context.scene
    for index, obj in enumerate(figures):
        obj.location.x = (index - 3.5) * .88
    camera.location = (3.1, -12, 3.0)
    camera.rotation_euler = (Vector((0, 0, 1.02)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 8.25
    scene.render.resolution_x, scene.render.resolution_y = 1920, 680
    scene.render.resolution_percentage = 100
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.color_type = "VERTEX"
                area.spaces.active.region_3d.view_location = (0, 0, 1)
                area.spaces.active.region_3d.view_distance = 9
                area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
    instructions = bpy.data.texts.new("START HERE - crowd starter")
    instructions.write("Eight static crowd figures, 2 units tall like the pit marshal.\n"
                       "Select a figure and use View > Frame Selected to inspect it.\n"
                       "Every figure is one mesh with vertex colours and named anatomical part groups.\n"
                       "The lineup offsets are only for this review scene. Individual GLBs are exported at the origin.\n"
                       "The PMDL files use the existing importer and are normalized to height 1.\n"
                       "These are static pose studies: no armatures, clips or stand-placement logic yet.\n")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, "crowd-starter.blend"))
    scene.render.filepath = os.path.join(output, "lineup.png")
    bpy.ops.render.render(write_still=True)
    camera.location = (0, -12, 1.02)
    camera.rotation_euler = (Vector((0, 0, 1.02)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(output, "front-lineup.png")
    bpy.ops.render.render(write_still=True)
    for obj in figures:
        obj.hide_render = True
    camera.data.ortho_scale = 2.4
    camera.location = (2.5, -6, 2.3)
    camera.rotation_euler = (Vector((0, 0, 1)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = 500, 640
    for obj in figures:
        position = obj.location.copy()
        obj.location = (0, 0, 0)
        obj.hide_render = False
        scene.render.filepath = os.path.join(output, obj.name + ".png")
        bpy.ops.render.render(write_still=True)
        obj.hide_render = True
        obj.location = position
    if os.path.isfile(args.scale_reference):
        with bpy.data.libraries.load(os.path.abspath(args.scale_reference), link=False) as (source, target):
            target.objects = source.objects
        for obj in target.objects:
            if obj.type == "MESH":
                scene.collection.objects.link(obj)
        for index, offset in ((0, -.95), (4, .95)):
            figures[index].hide_render = False
            figures[index].location = (offset, 0, 0)
        camera.location = (2, -9, 2.6)
        camera.rotation_euler = (Vector((0, 0, 1.02)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 3.55
        scene.render.resolution_x, scene.render.resolution_y = 1200, 800
        scene.render.filepath = os.path.join(output, "scale-comparison.png")
        bpy.ops.render.render(write_still=True)
    with open(os.path.join(output, "manifest.json"), "w") as stream:
        json.dump({"authoring_height": 2, "front": "Blender -Y / glTF +Z", "feet": "origin",
                   "stage": "static asset studies; placement deferred", "figures": report}, stream, indent=2)
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
