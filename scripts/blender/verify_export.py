"""Re-import every export into an empty scene and measure what an engine would receive.

Usage: blender -b --factory-startup --python-exit-code 1 --python scripts/blender/verify_export.py -- <asset_dir>
Writes <asset_dir>/export_check.json. FBX at 0.01 re-imports into Blender at 0.01 x the size in
metres (Blender reads centimetres back), so FBX dims are compared after multiplying by 100.
"""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def bounds(objs):
    corners = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    low = [min(c[i] for c in corners) for i in range(3)]
    high = [max(c[i] for c in corners) for i in range(3)]
    return low, high


def reimport(kind, path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if kind == "fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif kind == "obj":
        bpy.ops.wm.obj_import(filepath=str(path), forward_axis="NEGATIVE_Z", up_axis="Y")
    elif kind == "glb":
        bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return {"objects": 0}
    low, high = bounds(meshes)
    scale = 100.0 if kind == "fbx" else 1.0
    images = [n.image for o in meshes for m in o.data.materials if m and m.use_nodes
              for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
    return {
        "objects": len(meshes),
        "names": [o.name for o in meshes],
        "dims": [round((high[i] - low[i]) * scale, 4) for i in range(3)],
        "low": [round(low[i] * scale, 4) for i in range(3)],
        "tris": sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons),
        "uv_layers": max(len(o.data.uv_layers) for o in meshes),
        "materials": sorted({m.name for o in meshes for m in o.data.materials if m}),
        "texture_found": any(i.size[0] > 0 for i in images),
    }


def main():
    asset_dir = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    layout = json.loads((asset_dir / "layout.json").read_text())
    result = {}
    for kind in layout["exports"]:
        path = asset_dir / f"{layout['name']}.{kind}"
        result[kind] = reimport(kind, path) if path.exists() else {"missing": True}
    bpy.ops.wm.open_mainfile(filepath=str(asset_dir / f"{layout['name']}.blend"))
    result["blend"] = {"reopens": layout["object_name"] in bpy.data.objects,
                       "texture_paths_relative": all(i.filepath.startswith("//") for i in bpy.data.images if i.filepath)}
    (asset_dir / "export_check.json").write_text(json.dumps(result, indent=1))
    print("URK_VERIFY_OK", json.dumps({k: v.get("dims") for k, v in result.items() if isinstance(v, dict)}))


main()
