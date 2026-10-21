"""Build a terrain-first Vineta K background study, not a cube-shell replacement.

Blender --background --python-exit-code 1 --python tools/model_vineta_mountains.py -- out/vineta-mountains

The authored terrain is original geometry with vertex colours. Only the optional
context blend and its renders contain locally extracted game assets.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.noise import ridged_multi_fractal


PROFILE = [(-84, 0), (-72, .12), (-58, .37), (-43, .55), (-30, .72), (-16, 1),
           (-2, .62), (12, .88), (25, .53), (39, .65), (51, .28), (64, 0)]
BANDS = [dict(name="Foothills", radius=1150, depth=1350, height=430, columns=144, rows=48, seed=19),
         dict(name="Main_Massif", radius=1850, depth=1850, height=1370, columns=288, rows=96, seed=37),
         dict(name="Distant_Range", radius=3050, depth=2100, height=1540, columns=144, rows=48, seed=53)]
SUN = Vector((-.65, -.35, .68)).normalized()


def blend(first, second, amount):
    amount = max(0, min(1, amount))
    return tuple(start + (end - start) * amount for start, end in zip(first, second))


def smooth(value):
    value = max(0, min(1, value))
    return value * value * (3 - 2 * value)


def hash_value(horizontal, vertical, seed):
    value = (horizontal * 374761393 + vertical * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((value ^ (value >> 16)) & 0xFFFFFFFF) / 0xFFFFFFFF * 2 - 1


def noise(horizontal, vertical, seed):
    left, bottom = math.floor(horizontal), math.floor(vertical)
    amount_x, amount_y = smooth(horizontal - left), smooth(vertical - bottom)
    lower = hash_value(left, bottom, seed) * (1 - amount_x) + hash_value(left + 1, bottom, seed) * amount_x
    upper = hash_value(left, bottom + 1, seed) * (1 - amount_x) + hash_value(left + 1, bottom + 1, seed) * amount_x
    return lower * (1 - amount_y) + upper * amount_y


def fractal(horizontal, vertical, seed, octaves=5):
    total, amplitude, weight = 0, 1, 0
    for octave in range(octaves):
        total += amplitude * noise(horizontal, vertical, seed + octave * 11)
        weight += amplitude
        horizontal, vertical = horizontal * 2.03 + 13.7, vertical * 2.03 - 7.2
        amplitude *= .52
    return total / weight


def profile(angle):
    for (start, lower), (end, upper) in zip(PROFILE, PROFILE[1:]):
        if angle <= end:
            return lower + (upper - lower) * smooth((angle - start) / (end - start))
    return 0


def terrain_point(column, row, band):
    across = column / band["columns"]
    inward = row / band["rows"]
    degrees = -84 + across * 148
    angle = math.radians(degrees)
    radius = band["radius"] + inward * band["depth"]
    horizontal, vertical = math.sin(angle) * radius, math.cos(angle) * radius
    seed = band["seed"]
    warp = fractal(horizontal / 520, vertical / 700, seed, 3)
    crest = .48 + .09 * math.sin(angle * 6 + seed) + .045 * math.sin(angle * 17) + warp * .08
    ridge = max(0, 1 - abs(inward - crest) / .47)
    ridge = ridge ** 1.20
    peak = profile(degrees + warp * 4)
    rock = fractal(horizontal / 200, vertical / 270, seed + 101)
    channels = abs(fractal(horizontal / 250 + inward * 1.4, vertical / 620, seed + 211, 4))
    crags = ridged_multi_fractal(Vector((horizontal / 340, vertical / 520, seed * .13)),
                                1.0, 2.1, 5, 1.0, 2.0)
    branching = .63 + .26 * channels + .12 * rock + .12 * crags
    height = band["height"] * peak * ridge * branching
    height += band["height"] * .065 * ridge * peak * noise(horizontal / 80, vertical / 100, seed + 13)
    height *= smooth(inward / .12) * smooth((1 - inward) / .13)
    height *= smooth(across / .05) * smooth((1 - across) / .06)
    return Vector((horizontal, vertical, max(0, height)))


def terrain_colour(point, normal, band):
    horizontal, vertical, height = point
    seed = band["seed"]
    slope = 1 - max(0, normal.z)
    rock_amount = smooth((slope - .12) / .40) * .75 + smooth((height - 230) / 500) * .50
    variation = fractal(horizontal / 140, vertical / 180, seed + 400, 3)
    vegetation = blend((.29, .35, .30), (.36, .40, .31), variation + .5)
    stone = blend((.46, .48, .49), (.64, .60, .52), variation * .7 + .4)
    albedo = blend(vegetation, stone, rock_amount)
    light = .46 + .54 * max(0, normal.dot(SUN))
    shade = tuple(channel * light for channel in albedo)
    distance = math.hypot(horizontal, vertical)
    haze = 1 - math.exp(-distance / 6200)
    haze += .08 * (1 - smooth(height / 250))
    return blend(shade, (.66, .73, .79), haze)


def linear(colour):
    return tuple(channel / 12.92 if channel <= .04045 else ((channel + .055) / 1.055) ** 2.4
                 for channel in colour) + (1,)


def vertex_material(name):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Color"
    links.new(attribute.outputs["Color"], output.inputs["Surface"])
    return material


def coloured_mesh(name, vertices, faces, colours, material, collection):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    attribute = data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    data.color_attributes.active_color = attribute
    for loop in data.loops:
        attribute.data[loop.index].color = linear(colours[loop.vertex_index])
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def make_band(band, material, collection):
    columns, rows = band["columns"], band["rows"]
    vertices = [terrain_point(column, row, band) for row in range(rows + 1) for column in range(columns + 1)]
    faces, colours = [], []
    for row in range(rows + 1):
        for column in range(columns + 1):
            point = vertices[row * (columns + 1) + column]
            across = vertices[row * (columns + 1) + min(columns, column + 1)] - vertices[row * (columns + 1) + max(0, column - 1)]
            inward = vertices[min(rows, row + 1) * (columns + 1) + column] - vertices[max(0, row - 1) * (columns + 1) + column]
            normal = across.cross(inward).normalized()
            if normal.z < 0:
                normal.negate()
            colours.append(terrain_colour(point, normal, band))
            if row < rows and column < columns:
                first = row * (columns + 1) + column
                faces.extend([(first, first + 1, first + columns + 1),
                              (first + 1, first + columns + 2, first + columns + 1)])
    obj = coloured_mesh(band["name"], vertices, faces, colours, material, collection)
    obj["role"] = "Full-depth terrain, not a skybox silhouette"
    obj["procedural_seed"] = band["seed"]
    assert all(math.isfinite(value) for point in vertices for value in point)
    assert all(polygon.area > 1e-4 for polygon in obj.data.polygons)
    return obj


def backdrop(material, collection):
    vertices, colours, faces = [], [], []
    rings, sectors, radius = 24, 64, 14000
    for row in range(rings + 1):
        latitude = -.35 + row / rings * 1.90
        elevation = math.sin(latitude)
        colour = blend((.71, .77, .81), (.34, .49, .66), smooth(max(0, elevation) / .75))
        for column in range(sectors):
            angle = column / sectors * math.tau
            vertices.append((radius * math.cos(latitude) * math.sin(angle),
                             radius * math.cos(latitude) * math.cos(angle), radius * elevation))
            warmth = max(0, -math.sin(angle)) * max(0, 1 - abs(elevation - .1) / .35) * .12
            colours.append(blend(colour, (.85, .77, .64), warmth))
    for row in range(rings):
        for column in range(sectors):
            following = (column + 1) % sectors
            faces.append((row * sectors + column, row * sectors + following,
                          (row + 1) * sectors + following, (row + 1) * sectors + column))
    obj = coloured_mesh("Temporary_Atmospheric_Backdrop_No_Clouds", vertices, faces, colours, material, collection)
    sea = coloured_mesh("Temporary_Sea_Plane", [(-12000, -12000, -.5), (12000, -12000, -.5),
                                                (12000, 12000, -.5), (-12000, 12000, -.5)],
                        [(0, 1, 2, 3)], [(.35, .49, .57)] * 4, material, collection)
    return obj, sea


def camera(scene, name, position, target, lens=42):
    obj = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector(target) - Vector(position)).to_track_quat("-Z", "Y").to_euler()
    obj.data.lens = lens
    obj.data.clip_start = .1
    obj.data.clip_end = 40000
    return obj


def render(scene, camera_obj, path):
    scene.camera = camera_obj
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def prepare_view(scene, camera_obj):
    scene.camera = camera_obj
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                space = area.spaces.active
                space.region_3d.view_perspective = "CAMERA"
                space.shading.type = "MATERIAL"
                space.shading.use_scene_world = True
                space.clip_start = .1
                space.clip_end = 40000


def export_terrain(objects, output):
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for original in objects:
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.select_set(True)
        copies.append(obj)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    combined = bpy.context.object
    combined.name = "Vineta_Mountain_Range_Prototype"
    bpy.ops.export_scene.gltf(filepath=str(output / "mountain-range.glb"), export_format="GLB",
                              use_selection=True, export_yup=True, export_texcoords=False,
                              export_animations=False, export_all_vertex_colors=False)
    expected = [[operation(vertex.co[axis] for vertex in combined.data.vertices) for axis in range(3)]
                for operation in (min, max)]
    expected_triangles = len(combined.data.polygons)
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(output / "mountain-range.glb"))
    imported = set(bpy.data.objects) - existing
    points = [obj.matrix_world @ vertex.co for obj in imported if obj.type == "MESH" for vertex in obj.data.vertices]
    actual = [[operation(point[axis] for point in points) for axis in range(3)] for operation in (min, max)]
    error = max(abs(expected[side][axis] - actual[side][axis]) for side in range(2) for axis in range(3))
    assert error < .001, ("GLB bounds changed", error)
    assert sum(len(obj.data.polygons) for obj in imported if obj.type == "MESH") == expected_triangles
    for obj in imported:
        if obj.type == "MESH":
            assert len(obj.data.color_attributes) > 0
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(combined, do_unlink=True)
    return {"reimport_bounds_max_error": error, "triangles": expected_triangles, "vertex_colours": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--context", type=Path, default=Path("out/sky-level-preview/vineta-k-sky-context.blend"))
    parser.add_argument("--frame", type=Path, default=Path("out/101/race/frame.json"))
    parser.add_argument("--width", type=int, default=1600)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = arguments.output.resolve()
    assert output.is_relative_to(Path(__file__).resolve().parents[1] / "out")
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "Mountains_First_Study"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = arguments.width
    scene.render.resolution_y = round(arguments.width * .5625)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.world = bpy.data.worlds.new("Neutral_Atmosphere")
    scene.world.color = (.4, .5, .6)
    terrain = bpy.data.collections.new("01_MOUNTAINS_Three_Deep_Terrain_Bands")
    environment = bpy.data.collections.new("02_TEMPORARY_Sky_And_Sea_No_Clouds")
    scene.collection.children.link(terrain)
    scene.collection.children.link(environment)
    material = vertex_material("Original_Terrain_Vertex_Colour")
    objects = [make_band(band, material, terrain) for band in BANDS]
    backdrop(material, environment)
    hero = camera(scene, "01_MOUNTAIN_PORTRAIT", (150, -600, 120), (0, 2600, 490), 28)
    overview = camera(scene, "02_TERRAIN_DEPTH_OVERVIEW", (-4200, -2000, 2300), (0, 2400, 230), 40)
    render(scene, hero, output / "mountain-range-portrait.png")
    render(scene, overview, output / "mountain-range-depth.png")
    prepare_view(scene, hero)
    validation = export_terrain(objects, output)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "mountain-range.blend"))
    report = {"stage": "Terrain-first art-direction prototype; NOT a drop-in sky-shell asset",
              "authored_asset": "mountain-range.blend", "glb": "mountain-range.glb",
              "triangles": sum(len(obj.data.polygons) for obj in objects),
              "validation": validation,
              "bands": [{"name": obj.name, "triangles": len(obj.data.polygons),
                         "bounds_blender": {"min": [min(vertex.co[axis] for vertex in obj.data.vertices) for axis in range(3)],
                                            "max": [max(vertex.co[axis] for vertex in obj.data.vertices) for axis in range(3)]}}
                        for obj in objects],
              "coordinates": "Blender Z up, +Y toward the main mountains; glTF Y up, -Z toward mountains; origin at sea level",
              "decisions": ["Real kilometre-scale depth and relief, not polygons painted on a unit cube.",
                            "Three terrain bands: foothills, main massif and far ridge; no redesigned city.",
                            "Muted rock/vegetation, baked directional shading and distance haze; vertex colours only.",
                            "Temporary plain gradient sky and sea; clouds deliberately deferred.",
                            "Engine background depth/parallax representation must be revisited after visual approval."],
              "previews": ["mountain-range-portrait.png", "mountain-range-depth.png"]}
    if arguments.context.is_file():
        with bpy.data.libraries.load(str(arguments.context.resolve()), link=False) as (source, destination):
            destination.collections = ["01_Extracted_Level"]
        level = destination.collections[0]
        assert level is not None
        scene.collection.children.link(level)
        frame = json.loads(arguments.frame.read_text())
        draw_info = {draw["index"]: draw for draw in frame["draws"]}
        for obj in level.objects:
            obj.parent = None
            obj.matrix_world = Matrix.Identity(4)
            if draw_info[obj["draw_index"]].get("texture", {}).get("map_mode") == 1:
                obj.hide_render = True
                obj.hide_viewport = True
        level_materials = {material for obj in level.objects for material in obj.data.materials if material}
        for material in level_materials:
            if not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.type != "EMISSION" or not node.inputs["Color"].is_linked:
                    continue
                fog = node.inputs["Color"].links[0].from_node
                if fog.type == "MIX_RGB" and fog.inputs[0].is_linked and fog.inputs[2].is_linked:
                    material.node_tree.links.new(fog.inputs[2].links[0].from_socket, node.inputs["Color"])
        view = Matrix([[frame["main_view_matrix"][column * 4 + row] for column in range(4)] for row in range(4)])
        game_eye = view.inverted().translation
        anchor = Vector((game_eye.x, -game_eye.z, -49.5))
        for obj in list(terrain.objects) + list(environment.objects):
            obj.location += anchor
        hero.location += anchor
        overview.location += anchor
        context_eye = anchor + Vector((-200, -2200, 650))
        context_camera = camera(scene, "00_START_HERE_Mountains_Over_Track", context_eye,
                                anchor + Vector((0, 2500, 350)), 32)
        pose = view.inverted()
        axis = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        race_camera = camera(scene, "03_RACE_DIRECTION_Approximate", axis @ game_eye,
                             axis @ (game_eye + pose.to_3x3() @ Vector((0, 0, -100))), 24)
        render(scene, context_camera, output / "mountains-in-level.png")
        render(scene, race_camera, output / "mountains-race-direction.png")
        prepare_view(scene, context_camera)
        bpy.ops.object.select_all(action="DESELECT")
        objects[1].select_set(True)
        bpy.context.view_layer.objects.active = objects[1]
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=str(output / "vineta-mountains-context.blend"))
        report.update(context="vineta-mountains-context.blend", context_anchor_blender=list(anchor),
                      context_note="LOCAL ONLY: extracted frame, not full track. Elevated mountain-facing camera is a composition study, not the recorded race view; level's camera fog disabled for inspection.")
        report["previews"].extend(["mountains-in-level.png", "mountains-race-direction.png"])
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    (output / "README.md").write_text("""# Mountains-first study

Start with **vineta-mountains-context.blend** or **mountains-in-level.png**.
The saved camera deliberately faces the mountain range from above the grandstand.
Terrain, track, sea and background are in ONE visible scene and ONE view layer.
No compositor toggle is needed. Material Preview shows the authored vertex colours;
Numpad 0 enters the saved camera, F12 renders it. Orbit freely to inspect real depth.
The original race direction faces away from the main massif; its preview is included separately.

**mountain-range.blend** and **mountain-range.glb** are the clean authored asset,
without any game geometry or reference images. Three independently editable terrain bands
are joined into one mesh for the GLB. Colours/shading/haze are vertex-authored, with no textures.
The asset origin is sea level; Blender +Y / glTF -Z points into the main range.
See mountain-range-depth.png for the volume, ridges and valleys rather than a flat silhouette.

This is an ART-DIRECTION PROTOTYPE, not an engine-ready sky replacement. It deliberately
uses real world-scale depth and a higher terrain budget rather than the previous ~600-triangle
cube-shell silhouettes. A depth-safe distant-background pass/representation and parallax
need deciding before integration. No installed sky, engine code, or earlier asset was changed.
The backdrop and sea are temporary; cloud design and city replacement are not part of this pass.

The context blend/renders contain locally extracted game/HD textures, are incomplete outside
the recorded view and must not be committed or redistributed. The context camera is elevated
to expose the mountains; it is not an exact in-game screenshot. Original sky faces are absent.
The extracted level's camera-dependent fog is disabled for this distant inspection view.

Rebuild with Blender's background runner:
`--python tools/model_vineta_mountains.py -- out/vineta-mountains`
""")
    print(f"MOUNTAINS COMPLETE: {report['triangles']} terrain triangles; {output}", flush=True)


if __name__ == "__main__":
    main()
