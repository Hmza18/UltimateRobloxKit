# Asset export guide

| Format | Settings | Status |
|---|---|---|
| FBX | selected only, `global_scale=0.01`, Apply Transform, no leaf bones, no animation for props, `path_mode=STRIP` | Studio-verified in the source project; re-imported in Blender by the kit |
| OBJ + MTL | forward `-Z`, up `Y`, triangulated, normals, UVs, materials | Re-imported in Blender; Studio import not verified |
| GLB | `+Y` up, applied modifiers, embedded texture | Re-imported in Blender; Studio import not verified |
| `.blend` | relative texture path `//<Asset>.png` | Reopens with texture |
| PNG | 1024 x 1024 RGBA, sRGB | Size checked |

Conventions before export: 1 unit = 1 stud, front `-Y`, up `+Z`, origin bottom-centre on Z = 0, identity transforms, one mesh named `SM_<Asset>`, one material `M_<Asset>`.

Delivery folder per asset: `<Asset>/<Asset>.fbx|.obj|.mtl|.glb|.png|.blend` plus `<Asset>_Image.png`. `package_batch.py` builds this layout and zips it, and refuses unapproved assets.

Checks without Blender:

```bash
python3 scripts/validate/check_obj.py build/props/Crate/Crate.obj --max-tris 400
```

Import into Studio and record the result with [studio validation](studio-validation.md).
