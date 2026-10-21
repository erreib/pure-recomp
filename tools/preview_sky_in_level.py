"""Compose a recorded level extraction with original and authored skies in Blender.

Blender --background --python-exit-code 1 --python tools/preview_sky_in_level.py -- out/sky-level-preview --hd-pack PATH

All extracted data, packed Blender files and renders must stay in ignored out/.
This is a composition study, not a reproduction of the GE's multipass renderer.
"""
import argparse
import collections
import json
import math
from pathlib import Path
import re
import struct
import sys

import bpy
import numpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gerec.gerec_dump import Cursor, texture_state
import zim_to_png


AXES = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
SKY_KEYS = {"00000000a985ea5ff033d0a2", "00000000c668ec30da8ad8ed", "00000000b35b2a93387e25cf",
            "00000000fd24dbbbc5d5ea0d", "00000000d5927b5de3617a78"}


def matrix(values):
    return Matrix([[values[column * 4 + row] for column in range(4)] for row in range(4)])


def rgba(word):
    channels = [(word >> shift & 255) / 255 for shift in (0, 8, 16, 24)]
    return tuple(value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
                 for value in channels[:3]) + (channels[3],)


def recorded_attributes(path, draws):
    wanted = {draw["record"]: draw for draw in draws}
    result = {}
    with path.open("rb") as stream:
        assert stream.read(12) == b"PKGEREC\0\x01\0\0\0", "Unsupported recording format"
        record = 0
        while header := stream.read(5):
            kind, size = struct.unpack("<BI", header)
            if record not in wanted:
                stream.seek(size, 1)
                record += 1
                continue
            assert kind == 5, (record, "not a Draw")
            cursor = Cursor(stream.read(size))
            primitive = cursor.u8()
            count = cursor.u32()
            colours = [vertex[-1] for vertex in struct.iter_unpack("<9fI", cursor.raw(count * 40))]
            indices = [entry[0] for entry in struct.iter_unpack("<H", cursor.raw(cursor.u32() * 2))]
            cursor.flag()
            texture_state(cursor)
            cursor.take("<5I")
            cursor.flag(); cursor.take("<5I")
            cursor.take("<BBIHH")
            cursor.flag(); cursor.take("<3I")
            cursor.floats(6); cursor.take("<4I"); cursor.floats(2)
            cursor.raw(3); cursor.u32(); cursor.take("<4I")
            cursor.u32(); cursor.raw(2)
            cursor.take("<4I"); cursor.f32(); cursor.take("<3I"); cursor.flag()
            for light in range(4):
                cursor.flag(); cursor.take("<2I"); cursor.floats(9); cursor.floats(2); cursor.take("<3I")
            fog = (cursor.flag(), cursor.f32(), cursor.f32(), cursor.u32())
            draw = wanted[record]
            assert count == draw["vertices"], (record, "vertex count mismatch")
            assert not colours or colours[0] == int(draw["first_color"], 16), (record, "colour mismatch")
            if primitive == 6:
                order = indices or list(range(count))
                colours = [colours[index] for start in range(0, len(order) - 1, 2)
                           for index in (order[start], order[start + 1], order[start + 1], order[start])]
            result[draw["index"]] = {"colours": colours, "fog": fog}
            record += 1
    assert len(result) == len(wanted), "Recording does not contain every selected draw"
    return result


def obj_parts(path):
    part = None
    global_vertices = 0
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "o":
            if part:
                yield part
            part = {"name": fields[1], "index": int(fields[1].split("_")[1]),
                    "vertices": [], "uv": [], "faces": [], "base": global_vertices + 1}
        elif fields[0] == "v":
            part["vertices"].append(tuple(map(float, fields[1:4])))
            global_vertices += 1
        elif fields[0] == "vt":
            part["uv"].append(tuple(map(float, fields[1:3])))
        elif fields[0] == "f":
            indices = []
            for field in fields[1:]:
                position, texcoord = field.split("/")[:2]
                assert position == texcoord, "Expected extractor's one UV per vertex"
                indices.append(int(position) - part["base"])
            part["faces"].append(indices)
    if part:
        yield part


def texture_paths(arguments, draws):
    paths = {draw["key"]: arguments.frame_dir / "textures" / f"{draw['key']}.png" for draw in draws}
    converted = []
    if arguments.hd_pack:
        cache = arguments.output / "hd-textures"
        cache.mkdir(exist_ok=True)
        for line in (arguments.hd_pack / "textures.ini").read_text().splitlines():
            match = re.match(r"^([0-9a-fA-F]{24})\s*=\s*([^#]+)", line)
            if not match or match[1].lower() not in paths:
                continue
            key = match[1].lower()
            source = arguments.hd_pack / match[2].strip()
            if not source.is_file():
                continue
            if source.suffix.lower() == ".zim":
                target = cache / f"{key}.png"
                if not target.exists():
                    assert zim_to_png.main(["zim_to_png", str(source), str(target)]) == 0, source
                paths[key] = target
            elif source.suffix.lower() == ".png":
                paths[key] = source
            else:
                continue
            converted.append(key)
    return paths, sorted(set(converted))


def make_material(draw, attributes, paths, cache):
    texture = draw.get("texture", {})
    signature = (draw["key"], draw["alpha_test"], draw["blend"], str(texture), attributes["fog"])
    if signature in cache:
        return cache[signature]
    material = bpy.data.materials.new(f"GE_{draw['key']}_{draw['index']}")
    material.use_nodes = True
    material.use_backface_culling = False
    material.surface_render_method = "DITHERED"
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    vertex = nodes.new("ShaderNodeVertexColor")
    vertex.layer_name = "Recorded_Color"
    colour = vertex.outputs["Color"]
    alpha = vertex.outputs["Alpha"]
    path = paths.get(draw["key"])
    if path and path.is_file() and texture:
        image = nodes.new("ShaderNodeTexImage")
        image.image = bpy.data.images.load(str(path), check_existing=True)
        image.interpolation = "Linear"
        image.extension = "REPEAT" if texture.get("wrap", [0, 0]) == [0, 0] else "EXTEND"
        multiply = nodes.new("ShaderNodeMixRGB")
        multiply.blend_type = "MULTIPLY"
        multiply.inputs[0].default_value = 1
        links.new(colour, multiply.inputs[1])
        links.new(image.outputs["Color"], multiply.inputs[2])
        colour = image.outputs["Color"] if texture.get("function") == "replace" else multiply.outputs[0]
        if texture.get("alpha", False):
            multiply_alpha = nodes.new("ShaderNodeMath")
            multiply_alpha.operation = "MULTIPLY"
            links.new(alpha, multiply_alpha.inputs[0])
            links.new(image.outputs["Alpha"], multiply_alpha.inputs[1])
            alpha = multiply_alpha.outputs[0]
    fog_enabled, fog_end, fog_scale, fog_word = attributes["fog"]
    if fog_enabled and fog_scale > 0:
        camera = nodes.new("ShaderNodeCameraData")
        distance = nodes.new("ShaderNodeMath")
        distance.operation = "SUBTRACT"
        distance.inputs[0].default_value = fog_end
        links.new(camera.outputs["View Z Depth"], distance.inputs[1])
        factor = nodes.new("ShaderNodeMath")
        factor.operation = "MULTIPLY"
        factor.use_clamp = True
        factor.inputs[1].default_value = fog_scale
        links.new(distance.outputs[0], factor.inputs[0])
        fog = nodes.new("ShaderNodeMixRGB")
        fog.inputs[1].default_value = (*rgba(fog_word)[:3], 1)
        links.new(factor.outputs[0], fog.inputs[0])
        links.new(colour, fog.inputs[2])
        colour = fog.outputs[0]
    links.new(colour, emission.inputs["Color"])
    threshold = re.match(r"GREATER 0x([0-9A-Fa-f]+)", draw["alpha_test"])
    if threshold or draw["blend"] == "add(SA,1-SA)":
        if threshold:
            test = nodes.new("ShaderNodeMath")
            test.operation = "GREATER_THAN"
            test.inputs[1].default_value = int(threshold[1], 16) / 255
            links.new(alpha, test.inputs[0])
            alpha = test.outputs[0]
        transparent = nodes.new("ShaderNodeBsdfTransparent")
        mix_shader = nodes.new("ShaderNodeMixShader")
        links.new(alpha, mix_shader.inputs[0])
        links.new(transparent.outputs[0], mix_shader.inputs[1])
        links.new(emission.outputs[0], mix_shader.inputs[2])
        links.new(mix_shader.outputs[0], output.inputs["Surface"])
    else:
        links.new(emission.outputs[0], output.inputs["Surface"])
    cache[signature] = material
    return material


def mesh_object(part, draw, attributes, collection, root, material):
    mesh = bpy.data.meshes.new(part["name"])
    mesh.from_pydata([tuple(AXES @ Vector(point)) for point in part["vertices"]], [], part["faces"])
    mesh.update()
    mesh.uv_layers.new(name="Recorded_UV")
    mesh.color_attributes.new(name="Recorded_Color", type="FLOAT_COLOR", domain="CORNER")
    uv = mesh.uv_layers["Recorded_UV"]
    colours = mesh.color_attributes["Recorded_Color"]
    words = attributes["colours"]
    assert len(words) == len(part["vertices"]), (part["name"], "expanded colours do not match OBJ")
    for loop in mesh.loops:
        uv.data[loop.index].uv = part["uv"][loop.vertex_index]
        word = words[loop.vertex_index] if draw["vertex_color"] else int(draw["material_color"], 16)
        colours.data[loop.index].color = rgba(word)
    for loop in mesh.loops:
        expected_uv = part["uv"][loop.vertex_index]
        assert max(abs(uv.data[loop.index].uv[axis] - expected_uv[axis]) for axis in range(2)) < 1e-4
        word = words[loop.vertex_index] if draw["vertex_color"] else int(draw["material_color"], 16)
        assert max(abs(colours.data[loop.index].color[axis] - rgba(word)[axis]) for axis in range(4)) < 1e-6
    obj = bpy.data.objects.new(part["name"], mesh)
    collection.objects.link(obj)
    obj.parent = root
    obj.data.materials.append(material)
    obj["draw_index"] = draw["index"]
    obj["texture_key"] = draw["key"]
    obj["recorded_blend"] = draw["blend"]
    return obj


def configure_scene(scene, width):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.cycles.transparent_max_bounces = 16
    scene.render.resolution_x = width
    scene.render.resolution_y = round(width * 272 / 480)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.world = bpy.data.worlds.new(f"{scene.name}_World")
    scene.world.color = (0, 0, 0)


def composite(scene, level_collection, sky_collection, common):
    for collection in (level_collection, sky_collection, common):
        if collection.name not in scene.collection.children:
            scene.collection.children.link(collection)
    level = scene.view_layers[0]
    level.name = "Track_Foreground"
    sky = scene.view_layers.new("Sky_Background")
    level.layer_collection.children[sky_collection.name].exclude = True
    sky.layer_collection.children[level_collection.name].exclude = True
    tree = bpy.data.node_groups.new(f"{scene.name}_Composite", "CompositorNodeTree")
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    scene.compositing_node_group = tree
    foreground = tree.nodes.new("CompositorNodeRLayers")
    foreground.scene = scene
    foreground.layer = level.name
    background = tree.nodes.new("CompositorNodeRLayers")
    background.scene = scene
    background.layer = sky.name
    over = tree.nodes.new("CompositorNodeAlphaOver")
    image_inputs = [socket for socket in over.inputs if socket.type == "RGBA"]
    assert len(image_inputs) == 2, [(socket.name, socket.type) for socket in over.inputs]
    for socket in over.inputs:
        if socket.type == "VALUE" and socket.name in {"Factor", "Fac"}:
            socket.default_value = 1
    tree.links.new(background.outputs["Image"], image_inputs[0])
    tree.links.new(foreground.outputs["Image"], image_inputs[1])
    output = tree.nodes.new("NodeGroupOutput")
    tree.links.new(over.outputs[0], output.inputs["Image"])
    foreground.location = (-350, -150)
    background.location = (-350, 150)
    over.location = (0, 100)
    output.location = (240, 100)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frame-dir", type=Path, default=Path("out/101/race"))
    parser.add_argument("--recording", type=Path, default=Path("out/gerec/race.gerec"))
    parser.add_argument("--sky", type=Path, default=Path("out/sky-vineta-k/sky-vineta-k.blend"))
    parser.add_argument("--hd-pack", type=Path)
    parser.add_argument("--width", type=int, default=1440)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    arguments.output = arguments.output.resolve()
    repository = Path(__file__).resolve().parents[1]
    assert arguments.output.is_relative_to(repository / "out"), "Derived game assets must stay under out/"
    arguments.output.mkdir(parents=True, exist_ok=True)
    frame = json.loads((arguments.frame_dir / "frame.json").read_text())
    draws = [draw for draw in frame["draws"] if draw.get("view") == frame["main_view"] and not draw["through"]]
    main_target = collections.Counter(draw["target"] for draw in draws).most_common(1)[0][0]
    draws = [draw for draw in draws if draw["target"] == main_target and not draw["clear"]]
    supported_blends = {"off", "add(SA,1-SA)", "add(FIX,FIX) fix 0xFFFFFF/0x000000",
                        "add(FIX,SA) fix 0xFFFFFF/0xFFFFFF"}
    skipped = [draw["index"] for draw in draws if draw["blend"] not in supported_blends or
               draw["key"] == "untextured" or draw.get("texture", {}).get("map_mode") == 2]
    draws = [draw for draw in draws if draw["index"] not in skipped]
    attributes = recorded_attributes(arguments.recording, draws)
    paths, hd_keys = texture_paths(arguments, draws)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    common = bpy.data.collections.new("00_Cameras_and_Recorded_View")
    level = bpy.data.collections.new("01_Extracted_Level")
    original = bpy.data.collections.new("02_Original_Sky_Local_Reference")
    draft = bpy.data.collections.new("03_Procedural_Sky_Draft")
    aligned = bpy.data.collections.new("04_Draft_Authored_Eye_Alignment_Experiment")
    scene = bpy.context.scene
    scene.name = "02_Draft_Sky_In_Level"
    configure_scene(scene, arguments.width)
    scene.collection.children.link(common)
    view = matrix(frame["main_view_matrix"])
    camera_world = view.inverted()
    pose = Matrix.Translation(camera_world.translation) @ camera_world.to_quaternion().to_matrix().to_4x4()
    correction = AXES @ pose @ view @ AXES.inverted()
    left_rotation, scale, right_rotation = numpy.linalg.svd(numpy.array(correction.to_3x3()))
    if numpy.linalg.det(left_rotation) < 0:
        left_rotation[:, -1] *= -1
        scale[-1] *= -1
    if numpy.linalg.det(right_rotation) < 0:
        right_rotation[-1, :] *= -1
        scale[-1] *= -1
    outer = bpy.data.objects.new("Recorded_View_Scale", None)
    outer.matrix_world = Matrix.Translation(correction.translation) @ Matrix(left_rotation.tolist()).to_4x4() @ Matrix.Diagonal((*scale, 1))
    common.objects.link(outer)
    root = bpy.data.objects.new("Recorded_View_Correction", None)
    root.parent = outer
    root.matrix_basis = Matrix(right_rotation.tolist()).to_4x4()
    root["purpose"] = "Preserves the recorded non-orthogonal camera matrix; child mesh coordinates remain world-space."
    common.objects.link(root)
    camera = bpy.data.objects.new("Race_Camera_Frame_6016", bpy.data.cameras.new("Recorded_Projection"))
    common.objects.link(camera)
    camera.matrix_world = AXES @ pose
    camera.data.type = "PERSP"
    camera.data.sensor_fit = "HORIZONTAL"
    camera.data.lens = camera.data.sensor_width * frame["main_projection"][0] / 2
    camera.data.clip_start = .5
    camera.data.clip_end = 10000
    scene.render.pixel_aspect_y = (frame["main_projection"][5] / frame["main_projection"][0]) / (scene.render.resolution_x / scene.render.resolution_y)
    scene.camera = camera
    materials = {}
    selected = {draw["index"]: draw for draw in draws}
    object_counts = collections.Counter()
    for part in obj_parts(arguments.frame_dir / "frame.obj"):
        if part["index"] not in selected:
            continue
        draw = selected[part["index"]]
        collection = original if draw["key"] in SKY_KEYS else level
        mesh_object(part, draw, attributes[draw["index"]], collection, root,
                    make_material(draw, attributes[draw["index"]], paths, materials))
        object_counts[collection.name] += 1
    assert len(original.objects) == 5, "Expected all five original sky faces"
    sky_draw = next(draw for draw in draws if draw["key"] in SKY_KEYS)
    centre = Vector(sky_draw["world"][12:15])
    brief_eye = Vector((.02, .38, -.02))
    alignment_offset = camera_world.translation - centre - 50 * brief_eye
    with bpy.data.libraries.load(str(arguments.sky.resolve()), link=False) as (source, destination):
        destination.objects = [name for name in source.objects if name in {"dome", "clouds_high", "horizon_far", "horizon_city", "sea"}]
    assert len(destination.objects) == 5
    for obj in destination.objects:
        draft.objects.link(obj)
        obj.parent = root
        obj.location = AXES @ centre
        obj.scale = (50, 50, 50)
        experiment = obj.copy()
        experiment.name = f"{obj.name}_alignment_experiment"
        aligned.objects.link(experiment)
        experiment.location = AXES @ (centre + alignment_offset)
    original_scene = bpy.data.scenes.new("01_Original_Sky_In_Level")
    configure_scene(original_scene, arguments.width)
    original_scene.render.pixel_aspect_y = scene.render.pixel_aspect_y
    original_scene.camera = camera
    composite(original_scene, level, original, common)
    composite(scene, level, draft, common)
    aligned_scene = bpy.data.scenes.new("03_Draft_Aligned_Experiment")
    configure_scene(aligned_scene, arguments.width)
    aligned_scene.render.pixel_aspect_y = scene.render.pixel_aspect_y
    aligned_scene.camera = camera
    composite(aligned_scene, level, aligned, common)
    bpy.context.view_layer.update()
    actual_view = camera.matrix_world.inverted() @ root.matrix_world @ AXES
    matrix_error = max(abs(actual_view[row][column] - view[row][column]) for row in range(4) for column in range(4))
    assert matrix_error < 1e-4, matrix_error
    outputs = []
    for render_scene, name in ((original_scene, "race-original-sky"), (scene, "race-draft-sky"),
                               (aligned_scene, "race-draft-alignment-experiment")):
        render_scene.render.filepath = str(arguments.output / f"{name}.png")
        bpy.ops.render.render(scene=render_scene.name, write_still=True)
        outputs.append(f"{name}.png")
    bpy.context.window.scene = scene
    bpy.ops.file.pack_all()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
                area.spaces.active.shading.type = "MATERIAL"
                area.spaces.active.clip_end = 10000
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(arguments.output / "vineta-k-sky-context.blend"))
    report = {"frame": frame["frame"], "source_extraction": str(arguments.frame_dir),
              "recording": str(arguments.recording), "objects": dict(object_counts),
              "level_triangles": sum(len(obj.data.polygons) for obj in level.objects),
              "sky_centre_game": list(centre), "camera_game": list(camera_world.translation),
              "recorded_eye_in_sky_cube": list((camera_world.translation - centre) / 50),
              "brief_eye_in_sky_cube": list(brief_eye), "alignment_experiment_offset_game": list(alignment_offset),
              "camera_matrix_error": matrix_error, "hd_texture_keys": hd_keys,
              "skipped_effect_draws": skipped, "previews": outputs,
              "limitations": ["A frame extraction, not the entire level; unsubmitted geometry is absent.",
                              "Unlit textures plus recorded vertex colours, alpha cutouts and approximate fog.",
                              "GE additive/multipass effects, HUD, sun/flare and depth tricks are not reproduced.",
                              "Environment-mapped reflection passes and stencil-only volumes excluded; ship base passes approximated as opaque.",
                              "Recorded inverse-view eye is at cube centre, unlike the brief's eye offset; third scene is an alignment experiment only.",
                              "Sky is composited behind the track rather than allowed to occlude distant geometry.",
                              "Static sky placement: scale 50, no parallax or cloud spin.",
                              "Local-only game/HD-derived data: never commit or redistribute this output."]}
    (arguments.output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    readme = """# Vineta K sky composition study — LOCAL ONLY

Open `vineta-k-sky-context.blend`. The scene selector switches between
`01_Original_Sky_In_Level`, `02_Draft_Sky_In_Level`, and `03_Draft_Aligned_Experiment`.
F12 renders the composited result.
`race-original-sky.png` and `race-draft-sky.png` have identical recorded-camera framing.

The level is editable, textured geometry from race frame 6016, not the whole track.
The mesh objects retain per-draw names, world-space geometry, UVs and recovered vertex colours.
Textures are packed into the blend. No original sky images are embedded in the authored sky asset.
The two `Recorded_View_*` parents preserve the recording's camera shear exactly.

The Track_Foreground view layer excludes the sky; Sky_Background excludes the track.
The compositor puts the sky behind all track geometry, matching the intent of the game's
special sky-depth handling. In the viewport, inspect the track or sky separately;
F12 is the combined view. This avoids a 50-unit sky cube cutting off distant track objects.

This is an art-direction preview, NOT a faithful game capture: additive effects, HUD,
sun/flare, render-to-texture passes, GE depth behavior and precise fog blending are absent.
Reflection mapping and stencil-only volumes are excluded; ship base passes are opaque approximations.
Only geometry submitted in this frame exists; moving the camera can expose holes.
The game's installed models and settings are unchanged.

## Horizon mismatch discovered

The inverse of this recording's full view matrix puts the eye almost exactly at the sky
cube centre, rather than at the prompt's (0.02, 0.38, -0.02) offset. The view's upper 3x3
is not orthogonal: using its transpose as its inverse produces a materially different eye.
The unchanged draft consequently puts its sea/horizon too high in this composition.
The third scene moves ONLY the preview sky to match its authored eye offset (about 19
game units down), leaving the camera and track unchanged. It is an art-direction experiment,
not a depth-safe runtime fix. The original .blend/GLBs, prompt and engine are untouched.
See manifest.json for both eye positions, the experimental translation and matrix check.

Rebuild from the repository root using Blender's background Python runner:
`--python tools/preview_sky_in_level.py -- out/sky-level-preview --hd-pack /path/to/texture-pack`

All files here contain or derive from local game/HD-pack data. Keep them under ignored out/;
do not commit or redistribute. The reusable tools script contains no game assets.
"""
    (arguments.output / "README.md").write_text(readme)
    print(f"CONTEXT COMPLETE: {report['level_triangles']} track triangles, {len(hd_keys)} HD textures; {arguments.output}", flush=True)


if __name__ == "__main__":
    main()
