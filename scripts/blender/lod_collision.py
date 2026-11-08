"""LODs and a collision hull for an asset built by build_asset.py. Runs inside Blender (4.2 LTS or newer):

  blender -b --factory-startup --python-exit-code 1 --python scripts/blender/lod_collision.py -- <asset_dir> [--ratios 0.5,0.25] [--hull-tris 128]

Reads <asset_dir>/<Name>.blend and writes, next to it:
  <Name>_LOD1.fbx/.obj, <Name>_LOD2.fbx/.obj   Decimate (collapse) copies; same UVs and texture
  <Name>_Collision.fbx/.obj                     convex hull, decimated to at most --hull-tris triangles
  lod.json                                      triangles per level, hull triangles, hull/mesh volume ratio,
                                                and the bounding-box difference of every level (must stay ~0)
Roblox notes: MeshPart.RenderFidelity already does distance LOD for one mesh; these files are for games that
swap meshes themselves (far props, crowds) or want a cheap custom collision mesh (set the hull MeshPart's
Transparency to 1 and CanCollide true, and the visible mesh's CanCollide false, or use CollisionFidelity Hull).
Nothing here imports into Studio; Studio checks stay manual.
"""
import json
import sys
from pathlib import Path

import bmesh
import bpy


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("usage: ... -- <asset_dir> [--ratios 0.5,0.25] [--hull-tris 128]")
    ratios, hull = [0.5, 0.25], 128
    if "--ratios" in argv:
        ratios = [float(x) for x in argv[argv.index("--ratios") + 1].split(",")]
    if "--hull-tris" in argv:
        hull = int(argv[argv.index("--hull-tris") + 1])
    return Path(argv[0]).resolve(), ratios, hull


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def tris(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def volume(obj) -> float:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    v = abs(bm.calc_volume(signed=False))
    bm.free()
    return v


def bbox(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return [min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)]


def duplicate(obj, name):
    copy = obj.copy()
    copy.data = obj.data.copy()
    copy.name = copy.data.name = name
    bpy.context.collection.objects.link(copy)
    return copy


def decimate(obj, ratio):
    select_only(obj)
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def convex_hull(obj, name, max_tris):
    """A closed convex hull built from the vertex positions only (no faces, UVs or materials of the source)."""
    bm = bmesh.new()
    for v in obj.data.vertices:
        bm.verts.new(v.co)
    bm.verts.ensure_lookup_table()
    result = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    leftovers = {g for g in list(result.get("geom_interior", [])) + list(result.get("geom_unused", []))
                 if isinstance(g, bmesh.types.BMVert) and g.is_valid}
    if leftovers:
        bmesh.ops.delete(bm, geom=list(leftovers), context="VERTS")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    hull = bpy.data.objects.new(name, mesh)
    hull.matrix_world = obj.matrix_world.copy()
    bpy.context.collection.objects.link(hull)
    if tris(hull) > max_tris:
        decimate(hull, max_tris / tris(hull))
    return hull


def export(obj, path: Path):
    select_only(obj)
    bpy.ops.export_scene.fbx(filepath=str(path.with_suffix(".fbx")), use_selection=True, object_types={"MESH"},
                             global_scale=0.01, bake_space_transform=True, mesh_smooth_type="FACE",
                             use_mesh_modifiers=True, add_leaf_bones=False, bake_anim=False, path_mode="STRIP")
    bpy.ops.wm.obj_export(filepath=str(path.with_suffix(".obj")), export_selected_objects=True,
                          forward_axis="NEGATIVE_Z", up_axis="Y", global_scale=1.0, apply_modifiers=True,
                          export_uv=True, export_normals=True, export_materials=True, path_mode="STRIP",
                          export_triangulated_mesh=True)


def main():
    asset_dir, ratios, hull_tris = args()
    layout = json.loads((asset_dir / "layout.json").read_text())
    name = layout["name"]
    bpy.ops.wm.open_mainfile(filepath=str(asset_dir / f"{name}.blend"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise SystemExit(f"expected one mesh in {name}.blend, found {len(meshes)}")
    base = meshes[0]
    report = {"name": name, "lod0": {"tris": tris(base), "bbox": bbox(base)}, "levels": [], "hull": None}
    base_box = bbox(base)
    for i, ratio in enumerate(ratios, 1):
        lod = duplicate(base, f"{base.name}_LOD{i}")
        decimate(lod, ratio)
        box = bbox(lod)
        report["levels"].append({"level": i, "ratio": ratio, "tris": tris(lod),
                                 "bboxDelta": round(max(abs(a - b) for a, b in zip(box, base_box)), 5)})
        export(lod, asset_dir / f"{name}_LOD{i}")
    hull = convex_hull(base, f"{base.name}_Collision", hull_tris)
    base_volume = volume(base)
    report["hull"] = {"tris": tris(hull), "volumeRatio": round(volume(hull) / base_volume, 3) if base_volume else None,
                      "bboxDelta": round(max(abs(a - b) for a, b in zip(bbox(hull), base_box)), 5)}
    export(hull, asset_dir / f"{name}_Collision")
    (asset_dir / "lod.json").write_text(json.dumps(report, indent=1))
    print("URK_LOD_OK", json.dumps({"lod0": report["lod0"]["tris"], "levels": [lv["tris"] for lv in report["levels"]],
                                    "hull": report["hull"]["tris"]}))


main()
