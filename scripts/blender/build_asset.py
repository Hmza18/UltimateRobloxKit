"""Blender stage: layout.json -> .blend, FBX, OBJ, GLB, preview renders and metrics.json.

Usage (headless):
  blender -b --factory-startup --python-exit-code 1 --python scripts/blender/build_asset.py -- <asset_dir> [--no-renders]
<asset_dir> holds layout.json and the texture written by tools/rbxasset/layout.py.

Conventions (recovered from the supermarket pipeline, FBX path verified in Roblox Studio there):
- 1 Blender unit = 1 stud. Front -Y, up +Z, origin bottom-centre on Z = 0, identity transforms.
- FBX: selected mesh only, global_scale 0.01, Apply Transform (bake_space_transform) on, no leaf bones.
  Blender's metre -> FBX centimetre conversion times 0.01 lands at 1 stud per unit in Studio.
- OBJ: forward -Z, up Y, triangulated, materials, path_mode STRIP (texture sits beside the file).
- GLB: +Y up, embedded texture. Studio import of OBJ and GLB is NOT verified by this kit.
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("usage: ... -- <asset_dir> [--no-renders]")
    return Path(argv[0]).resolve(), "--no-renders" in argv


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def build_object(layout: dict, texture_path: Path):
    name = layout["object_name"]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in layout["verts"]], [], [tuple(f["v"]) for f in layout["faces"]])
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly, f in zip(mesh.polygons, layout["faces"]):
        poly.use_smooth = bool(f["smooth"])
        for loop_index, uv in zip(poly.loop_indices, f["uv"]):
            uv_layer.data[loop_index].uv = uv
    mesh.validate(verbose=False)
    mesh.update()
    mesh.set_sharp_from_angle(angle=math.radians(25))
    obj = bpy.data.objects.new(name, mesh)
    collection = bpy.data.collections.new("Asset")
    bpy.context.scene.collection.children.link(collection)
    collection.objects.link(obj)
    image = bpy.data.images.load(str(texture_path))
    image.colorspace_settings.name = "sRGB"
    mat = bpy.data.materials.new(f"M_{layout['name']}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    principled = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], principled.inputs["Base Color"])
    principled.inputs["Roughness"].default_value = 0.6
    mesh.materials.append(mat)
    bpy.context.view_layer.update()
    return obj


def count_shells(bm) -> int:
    bm.verts.index_update()
    seen, count = set(), 0
    for start in bm.verts:
        if start.index in seen:
            continue
        count += 1
        stack = [start]
        seen.add(start.index)
        while stack:
            for edge in stack.pop().link_edges:
                for nv in edge.verts:
                    if nv.index not in seen:
                        seen.add(nv.index)
                        stack.append(nv)
    return count


def measure(obj) -> dict:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.normal_update()
    result = {
        "tris": sum(len(f.verts) - 2 for f in bm.faces),
        "open_edges": sum(1 for e in bm.edges if e.is_boundary),
        "non_manifold_edges": sum(1 for e in bm.edges if not e.is_manifold),
        "signed_volume": round(bm.calc_volume(signed=True), 6),
        "shells": count_shells(bm),
    }
    bm.free()
    corners = [Vector(c) for c in obj.bound_box]
    low = [min(c[i] for c in corners) for i in range(3)]
    high = [max(c[i] for c in corners) for i in range(3)]
    uvs = mesh.uv_layers.active.data if mesh.uv_layers else []
    result.update({
        "dims": [round(high[i] - low[i], 5) for i in range(3)],
        "low": [round(x, 5) for x in low],
        "location": [round(x, 6) for x in obj.location],
        "rotation": [round(x, 6) for x in obj.rotation_euler],
        "scale": [round(x, 6) for x in obj.scale],
        "ngons": sum(1 for p in mesh.polygons if len(p.vertices) > 4),
        "uv_layers": len(mesh.uv_layers),
        "uv_in_range": all(0 <= d.uv[0] <= 1 and 0 <= d.uv[1] <= 1 for d in uvs),
        "materials": [m.name for m in mesh.materials if m],
    })
    return result


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def export_fbx(obj, path: Path):
    select_only(obj)
    bpy.ops.export_scene.fbx(filepath=str(path), use_selection=True, object_types={"MESH"}, global_scale=0.01,
                             bake_space_transform=True, mesh_smooth_type="FACE", use_mesh_modifiers=True,
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


def export_obj(obj, path: Path):
    select_only(obj)
    bpy.ops.wm.obj_export(filepath=str(path), export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          global_scale=1.0, apply_modifiers=True, export_uv=True, export_normals=True,
                          export_materials=True, path_mode="STRIP", export_triangulated_mesh=True)


def export_glb(obj, path: Path):
    select_only(obj)
    # glTF option names change between Blender versions, so pass only the ones this build knows.
    wanted = dict(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                  export_texcoord=True, export_normals=True, export_materials="EXPORT")
    known = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in known})


def setup_render(scene, size=512, samples=32):
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 0.7
    scene.world = world


def add_lights(scene, size):
    center = Vector((0, 0, size * 0.5))
    for name, offset, watts in (("Key", (-1.5, -2.4, 2.3), 42), ("Fill", (2.2, -1.6, 1.1), 12), ("Rim", (1.2, 2.4, 2.4), 30)):
        light = bpy.data.lights.new(name, "AREA")
        light.size = 2.5 * size
        light.energy = watts * size * size
        obj = bpy.data.objects.new(name, light)
        obj.location = center + Vector(offset) * size
        obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)


def frame_camera(scene, obj, yaw, pitch, lens=70.0, fill=0.88):
    if not scene.camera:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam = scene.camera
    cam.data.lens, cam.data.sensor_width = lens, 36.0
    cam.data.clip_start, cam.data.clip_end = 0.01, 1000
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    center = sum(corners, Vector()) / len(corners)
    radius = max((c - center).length for c in corners)
    y, p = math.radians(yaw), math.radians(pitch)
    direction = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    distance = radius * 6
    tan_half = 18.0 / lens
    for _ in range(5):
        cam.location = center + direction * distance
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()
        inv = cam.matrix_world.inverted()
        pts = [inv @ c for c in corners]
        px = [q.x / -q.z for q in pts]
        py = [q.y / -q.z for q in pts]
        distance *= max(max(px) - min(px), max(py) - min(py)) / 2 / (fill * tan_half)
        cam.data.shift_x = (max(px) + min(px)) / 2 / (2 * tan_half)
        cam.data.shift_y = (max(py) + min(py)) / 2 / (2 * tan_half)
    bpy.context.view_layer.update()


def render(scene, path: Path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    asset_dir, no_renders = args()
    layout = json.loads((asset_dir / "layout.json").read_text())
    scene = clean_scene()
    obj = build_object(layout, asset_dir / layout["texture"])
    metrics = measure(obj)
    outputs = {}
    name = layout["name"]
    if "fbx" in layout["exports"]:
        export_fbx(obj, asset_dir / f"{name}.fbx")
        outputs["fbx"] = f"{name}.fbx"
    if "obj" in layout["exports"]:
        export_obj(obj, asset_dir / f"{name}.obj")
        outputs["obj"] = f"{name}.obj"
    if "glb" in layout["exports"]:
        export_glb(obj, asset_dir / f"{name}.glb")
        outputs["glb"] = f"{name}.glb"
    for image in bpy.data.images:
        if image.filepath:
            image.filepath = f"//{Path(bpy.path.abspath(image.filepath)).name}"
    bpy.ops.wm.save_as_mainfile(filepath=str(asset_dir / f"{name}.blend"), compress=True, relative_remap=False)
    outputs["blend"] = f"{name}.blend"
    if layout.get("renders", True) and not no_renders:
        setup_render(scene)
        add_lights(scene, max(metrics["dims"]))
        views = asset_dir / "views"
        views.mkdir(exist_ok=True)
        # Product-image camera from the supermarket guide: front-left, yaw 32, pitch 17.
        for label, (yaw, pitch) in {"hero": (32, 17), "front": (0, 0), "back": (180, 0), "left": (-90, 0),
                                    "right": (90, 0), "top": (0, 89), "three_quarter_back": (145, 24)}.items():
            frame_camera(scene, obj, yaw, pitch)
            render(scene, views / f"{label}.png")
        outputs["views"] = sorted(p.name for p in views.glob("*.png"))
    metrics["outputs"] = outputs
    (asset_dir / "metrics.json").write_text(json.dumps(metrics, indent=1))
    print("URK_BUILD_OK", json.dumps({k: metrics[k] for k in ("dims", "tris", "open_edges", "shells")}))


main()
