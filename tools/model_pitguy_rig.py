"""Rig the current pit marshal and author a four-second wave-on loop.

Blender --background --python-exit-code 1 --python tools/model_pitguy_rig.py -- \
    out/pitguy-v2/pitguy.blend out/pitguy-rigged
Add --render to render a 12-fps preview sequence as well as the key poses.
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree


FPS = 24
END_FRAME = 97


def smoothstep(value, lower, upper):
    fraction = min(1, max(0, (value - lower) / (upper - lower)))
    return fraction * fraction * (3 - 2 * fraction)


def make_armature():
    data = bpy.data.armatures.new("Pit marshal skeleton")
    rig = bpy.data.objects.new("Pit marshal rig", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    definitions = [
        ("root", (0, 0, 0), (0, 0, .2), None),
        ("pelvis", (0, .01, 1.08), (0, .005, 1.19), "root"),
        ("spine", (0, .005, 1.19), (0, .005, 1.40), "pelvis"),
        ("chest", (0, .005, 1.40), (0, .012, 1.65), "spine"),
        ("neck", (0, .012, 1.65), (0, .007, 1.745), "chest"),
        ("head", (0, .007, 1.745), (0, .012, 1.96), "neck"),
    ]
    for side, sign in (("L", 1), ("R", -1)):
        definitions += [
            (f"clavicle.{side}", (sign * .06, .012, 1.61), (sign * .267, .012, 1.59), "chest"),
            (f"upper_arm.{side}", (sign * .267, .012, 1.59), (sign * .34, .022, 1.285), f"clavicle.{side}"),
            (f"forearm.{side}", (sign * .34, .022, 1.285), (sign * .341, -.028, 1.055), f"upper_arm.{side}"),
            (f"hand.{side}", (sign * .341, -.028, 1.055), (sign * .346, -.035, .925), f"forearm.{side}"),
            (f"thigh.{side}", (sign * .11, .018, 1.08), (sign * .125, -.002, .61), "pelvis"),
            (f"shin.{side}", (sign * .125, -.002, .61), (sign * .125, .014, .15), f"thigh.{side}"),
            (f"foot.{side}", (sign * .125, .014, .15), (sign * .125, -.14, .065), f"shin.{side}"),
        ]
    for name, head, tail, parent in definitions:
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        bone.align_roll(Vector((0, -1, 0)))
        if parent:
            bone.parent = data.edit_bones[parent]
        bone.use_deform = name != "root"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.show_in_front = True
    data.display_type = "OCTAHEDRAL"
    rig["instructions"] = "Space: play Wave_On. Pose Mode: edit bones. Feet/root stay planted. Front is -Y."
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    return rig


def body_weights(height):
    chest = smoothstep(height, 1.24, 1.53)
    pelvis = 1 - smoothstep(height, 1.13, 1.25)
    return {"pelvis": pelvis, "spine": (1 - pelvis) * (1 - chest), "chest": (1 - pelvis) * chest}


def weights_for(name, point):
    horizontal, _, height = point
    if name.startswith(("Helmet", "Visor", "Face", "Mask")):
        return {"head": 1}
    if name.startswith("Collar"):
        return {"neck": 1}
    side = "R" if name.startswith("Left ") else "L"
    if "sleeve" in name:
        shoulder = smoothstep(height, 1.56, 1.675)
        forearm = 1 - smoothstep(height, 1.22, 1.36)
        return {f"clavicle.{side}": shoulder,
                f"upper_arm.{side}": (1 - shoulder) * (1 - forearm),
                f"forearm.{side}": (1 - shoulder) * forearm}
    if "forearm" in name:
        return {f"forearm.{side}": 1}
    if "glove" in name:
        hand = 1 - smoothstep(height, .995, 1.055)
        return {f"hand.{side}": hand, f"forearm.{side}": 1 - hand}
    if "boot" in name:
        foot = 1 - smoothstep(height, .16, .23)
        return {f"foot.{side}": foot, f"shin.{side}": 1 - foot}
    if "knee" in name:
        thigh = smoothstep(height, .565, .66)
        return {f"thigh.{side}": thigh, f"shin.{side}": 1 - thigh}
    if "trouser" in name:
        side = "L" if horizontal > 0 else "R"
        pelvis = smoothstep(height, .96, 1.145)
        shin = 1 - smoothstep(height, .60, .70)
        return {"pelvis": pelvis, f"thigh.{side}": (1 - pelvis) * (1 - shin),
                f"shin.{side}": (1 - pelvis) * shin}
    return body_weights(height)


def bind_mesh(parts, rig):
    for obj in parts:
        groups = {bone.name: obj.vertex_groups.new(name=bone.name) for bone in rig.data.bones if bone.use_deform}
        for vertex in obj.data.vertices:
            weights = weights_for(obj.name, vertex.co)
            assert abs(sum(weights.values()) - 1) < 1e-6
            for name, weight in weights.items():
                if weight > 1e-6:
                    groups[name].add([vertex.index], weight, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = "Pit marshal - skinned mesh"
    mesh.parent = rig
    modifier = mesh.modifiers.new("Pit marshal skin", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = False
    mesh.data.calc_loop_triangles()
    assert len(mesh.data.loop_triangles) == 1986
    for vertex in mesh.data.vertices:
        assert 1 <= len(vertex.groups) <= 4
        assert abs(sum(group.weight for group in vertex.groups) - 1) < 1e-5
    return mesh


def point_bone(rig, name, direction):
    bone = rig.pose.bones[name]
    rest = bone.bone
    rest_direction = (rest.tail_local - rest.head_local).normalized()
    rotation = rest_direction.rotation_difference(Vector(direction).normalized()) @ rest.matrix_local.to_quaternion()
    head = bone.head.copy()
    bone.matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bone.location = (0, 0, 0)
    bone.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def make_wave(rig):
    rest_upper = tuple(rig.data.bones["upper_arm.R"].tail_local - rig.data.bones["upper_arm.R"].head_local)
    rest_forearm = tuple(rig.data.bones["forearm.R"].tail_local - rig.data.bones["forearm.R"].head_local)
    poses = [
        (1, rest_upper, rest_forearm, 0, 0),
        (9, rest_upper, rest_forearm, 0, 0),
        (22, (-.78, -.26, -.12), (.08, -.92, .39), -8, 1),
        (34, (-.78, -.17, .04), (.12, .12, .98), 12, 1),
        (46, (-.78, -.26, -.12), (.08, -.92, .39), -8, 1),
        (58, (-.78, -.17, .04), (.12, .12, .98), 12, 1),
        (70, (-.76, -.20, -.12), (.08, -.85, .52), -5, .85),
        (88, rest_upper, rest_forearm, 0, 0),
        (97, rest_upper, rest_forearm, 0, 0),
    ]
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, 96
    for frame in range(1, END_FRAME + 1):
        scene.frame_set(frame)
        lower, upper = next((lower, upper) for lower, upper in zip(poses, poses[1:]) if lower[0] <= frame <= upper[0])
        amount = smoothstep(frame, lower[0], upper[0])
        upper_direction = Vector(lower[1]).normalized().lerp(Vector(upper[1]).normalized(), amount)
        forearm_direction = Vector(lower[2]).normalized().lerp(Vector(upper[2]).normalized(), amount)
        wrist = lower[3] + (upper[3] - lower[3]) * amount
        intensity = lower[4] + (upper[4] - lower[4]) * amount
        for bone in rig.pose.bones:
            bone.rotation_quaternion = Quaternion()
            bone.location = (0, 0, 0)
        rig.pose.bones["chest"].rotation_quaternion = Quaternion((0, 1, 0), math.radians(-3 * intensity))
        rig.pose.bones["neck"].rotation_quaternion = Quaternion((0, 1, 0), math.radians(5 * intensity))
        bpy.context.view_layer.update()
        point_bone(rig, "upper_arm.R", upper_direction)
        point_bone(rig, "forearm.R", forearm_direction)
        rig.pose.bones["hand.R"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(wrist))
        for name in ("chest", "neck", "upper_arm.R", "forearm.R", "hand.R"):
            rig.pose.bones[name].keyframe_insert(data_path="rotation_quaternion", frame=frame, group=name)
    action = rig.animation_data.action
    action.name = "Wave_On"
    action.use_fake_user = True
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "LINEAR"
    for label, frame in (("Rest / loop start", 1), ("Reach toward traffic", 22), ("Sweep onward", 34),
                         ("Reach again", 46), ("Second sweep", 58), ("Return to rest", 88)):
        scene.timeline_markers.new(label, frame=frame)
    scene.frame_set(34)


def validate_motion(mesh):
    scene = bpy.context.scene
    graph = bpy.context.evaluated_depsgraph_get()
    samples = {}
    foot_indices = [vertex.index for vertex in mesh.data.vertices if vertex.co.z < .14]
    for frame in (1, 22, 34, 46, 58, 70, 88, 97):
        scene.frame_set(frame)
        evaluated = mesh.evaluated_get(graph)
        evaluated_mesh = evaluated.to_mesh()
        positions = [vertex.co.copy() for vertex in evaluated_mesh.vertices]
        assert all(math.isfinite(value) for point in positions for value in point)
        for index in foot_indices:
            assert (positions[index] - mesh.data.vertices[index].co).length < 1e-5
        samples[frame] = positions
        evaluated.to_mesh_clear()
    seam = max((first - last).length for first, last in zip(samples[1], samples[97]))
    movement = max((first - peak).length for first, peak in zip(samples[1], samples[34]))
    assert seam < 1e-5
    assert movement > .5
    scene.frame_set(34)
    return {"loop_seam_metres": seam, "maximum_vertex_motion_metres": movement, "feet_planted": True}, samples


def validate_roundtrip(path, reference):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in scene.objects if obj.type == "MESH" and
              any(modifier.type == "ARMATURE" for modifier in obj.modifiers)]
    rigs = [obj for obj in scene.objects if obj.type == "ARMATURE"]
    assert len(meshes) == 1 and len(rigs) == 1, [(obj.name, obj.type) for obj in scene.objects]
    assert rigs[0].animation_data.action is not None
    worst = 0
    for frame, positions in reference.items():
        scene.frame_set(frame - 1)
        graph = bpy.context.evaluated_depsgraph_get()
        tree = KDTree(len(positions))
        for index, point in enumerate(positions):
            tree.insert(point, index)
        tree.balance()
        evaluated = meshes[0].evaluated_get(graph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            _, _, distance = tree.find(evaluated.matrix_world @ vertex.co)
            worst = max(worst, distance)
        evaluated.to_mesh_clear()
    assert worst < 1e-4, f"GLB round-trip deformation differs by {worst} metres"
    return worst


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = os.path.abspath(args.output)
    os.makedirs(output, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.source))
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    rig = make_armature()
    mesh = bind_mesh(parts, rig)
    make_wave(rig)
    report, reference = validate_motion(mesh)
    scene = bpy.context.scene
    camera = scene.camera
    camera.location = (-3, -6, 2.35)
    camera.rotation_euler = (Vector((-.1, 0, 1.04)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 2.45
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
                area.spaces.active.region_3d.view_location = (-.1, 0, 1.04)
                area.spaces.active.region_3d.view_distance = 3.6
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=os.path.join(output, "pitguy-wave.glb"), use_selection=True,
                              export_format="GLB", export_yup=True, export_all_vertex_colors=True,
                              export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_range=False, export_frame_step=1,
                              export_anim_slide_to_zero=True)
    scene.frame_set(34)
    mesh.select_set(False)
    rig.select_set(False)
    scene.render.resolution_x, scene.render.resolution_y = 640, 800
    scene.cycles.samples = 32
    instructions = bpy.data.texts.new("START HERE - pit marshal")
    instructions.write("Pit marshal / Wave_On\n\n"
                       "Press Space in the viewport or Timeline to play. Playback frames 1-96, 24 fps.\n"
                       "The action has an identical end key on frame 97 for a seamless four-second loop.\n"
                       "Frames 22 and 46 reach toward traffic; frames 34 and 58 sweep onward.\n"
                       "Select Pit marshal rig and enter Pose Mode to edit the 20-bone skeleton.\n"
                       "Use the Dope Sheet's Action Editor to inspect Wave_On.\n"
                       "The right arm waves; the feet and root remain planted.\n"
                       "Skinning uses at most three influences per vertex and linear blend skinning.\n\n"
                       "pitguy-wave.glb contains the mesh, vertex colors, skin and baked Wave_On clip.\n"
                       "The recomp's current PMDL v1 importer/runtime only supports static geometry.\n"
                       "Do not expect converting this GLB with model_import.py to preserve animation.\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, "pitguy-rigged.blend"))
    for name, frame in (("rest", 1), ("reach", 22), ("wave", 34)):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(output, name + ".png")
        bpy.ops.render.render(write_still=True)
    report.update({"bones": len(rig.data.bones), "triangles": len(mesh.data.loop_triangles),
                   "clip": "Wave_On", "duration_seconds": 4, "fps": FPS, "frames": [1, 97],
                   "playback_frames": [1, 96], "root_motion": False,
                   "runtime_support": "PMDL v1 is static; animated GLB requires an animation-capable importer/runtime."})
    if args.render:
        frames = os.path.join(output, "preview-frames")
        os.makedirs(frames, exist_ok=True)
        scene.render.resolution_x, scene.render.resolution_y = 480, 600
        scene.cycles.samples = 16
        for index, frame in enumerate(range(1, 97, 2)):
            scene.frame_set(frame)
            scene.render.filepath = os.path.join(frames, f"{index:03d}.png")
            bpy.ops.render.render(write_still=True)
    report["glb_roundtrip_max_error_metres"] = validate_roundtrip(os.path.join(output, "pitguy-wave.glb"), reference)
    with open(os.path.join(output, "rig-info.json"), "w") as stream:
        json.dump(report, stream, indent=2)
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
