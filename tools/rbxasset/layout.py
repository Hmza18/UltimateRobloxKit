"""Spec -> mesh -> atlas -> texture -> layout.json, the hand-off to scripts/blender/build_asset.py.

A spec is one asset:
  {"name": "Crate", "generator": "crate", "size": [2, 2, 2], "params": {},
   "colors": {"wood": "#C8873A", "wood_end": "#A86A2A"}, "texture": null,
   "layout": "pack" | "guide", "max_tris": 400}
Sizes are studs; 1 Blender unit = 1 stud. Front is -Y, up is +Z, origin bottom-centre.
"""
from __future__ import annotations

import json
import os

from .atlas import pack, pack_guide, to_texture_uv
from .generators import build
from .meshkit import validate
from .texture import paint_panels, read_png_size, write_png

TEX = 1024


def make_layout(spec: dict, out_dir: str) -> dict:
    name = spec["name"]
    if not name.replace("_", "").isalnum():
        raise ValueError(f"Asset name must be alphanumeric or underscores: {name!r}")
    mesh = build(spec)
    check = validate(mesh)
    if not (check["closed"] and check["outward"]):
        raise ValueError(f"{name}: generator produced open or inverted geometry: {check}")
    tex = int(spec.get("texture_px", TEX))
    rects = (pack_guide if spec.get("layout") == "guide" else pack)(mesh.panels, tex, 6 if spec.get("layout") == "guide" else 12)
    os.makedirs(out_dir, exist_ok=True)
    texture_path = os.path.join(out_dir, f"{name}.png")
    if spec.get("texture"):
        w, h = read_png_size(spec["texture"])
        if (w, h) != (tex, tex):
            raise ValueError(f"{name}: supplied texture is {w}x{h}, expected {tex}x{tex}")
        with open(spec["texture"], "rb") as src, open(texture_path, "wb") as dst:
            dst.write(src.read())
    else:
        write_png(texture_path, tex, tex, paint_panels(rects, spec.get("colors", {}), tex))
    layout = {
        "name": name,
        "object_name": spec.get("object_name", f"SM_{name}"),
        "size": spec["size"],
        "max_tris": spec.get("max_tris", 400),
        "verts": mesh.verts,
        "faces": [{"v": f["v"], "smooth": f["smooth"], "panel": f["panel"],
                   "uv": [to_texture_uv(uv, rects[f["panel"]], tex) for uv in f["uv"]]} for f in mesh.faces],
        "rects": rects,
        "texture": os.path.basename(texture_path),
        "geometry_check": check,
        "stretched": getattr(mesh, "stretched", False),
        "exports": spec.get("exports", ["fbx", "obj", "glb"]),
        "renders": spec.get("renders", True),
    }
    with open(os.path.join(out_dir, "layout.json"), "w") as fh:
        json.dump(layout, fh)
    return layout
