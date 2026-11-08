---
name: blender-roblox-export
description: Exports Blender assets to Roblox correctly - FBX at 0.01 scale with Apply Transform (the Studio-verified path), OBJ and GLB alternatives, axes, pivots, single-mesh naming, textures beside the file, Roblox import limits, re-import verification, and multi-format delivery folders. Use whenever a model leaves Blender for Roblox, an import comes in the wrong size or orientation, or textures go missing.
license: MIT
metadata:
  category: blender
  version: 1.0.0
  triggers: [fbx, obj export, glb, export to roblox, import 3d, wrong scale, 100x too big, mesh import]
  depends: [blender-python-headless]
---

# Blender to Roblox export

## Rules (recovered, FBX path verified in Studio in the supermarket project)

| Item | Value |
|---|---|
| Units | 1 Blender unit = 1 stud; scene unit scale 1.0 |
| Axes in Blender | front -Y, up +Z |
| Pivot | origin bottom-centre on Z = 0, transforms applied (location 0, rotation 0, scale 1) |
| FBX | selected only, `global_scale=0.01`, `bake_space_transform=True` (Apply Transform), `add_leaf_bones=False`, `bake_anim=False` for props, `path_mode="STRIP"` |
| OBJ | forward `NEGATIVE_Z`, up `Y`, triangulated, materials on, texture beside file (unverified in Studio) |
| GLB | `+Y up`, apply modifiers, embedded texture (unverified in Studio) |
| Limits | 20,000 triangles per mesh on import; images above 1024 px are downscaled (verify current limits in creator docs) |

## Workflow

1. Prepare: one mesh object per asset named `SM_<Asset>`, one material, one UV map, closed geometry, no n-gons.
2. Export: `scripts/blender/build_asset.py` already does FBX, OBJ, GLB with these settings. For a hand-made `.blend`, select the object and use the same parameters (see `export_fbx` in that script).
3. Verify: `scripts/blender/verify_export.py` re-imports every format into an empty scene and writes `export_check.json`. FBX dims come back ×0.01, which the script corrects.
4. Studio: Import 3D with units = Studs, check `Size`, front direction and texture, per `roblox-studio-mcp`.
5. Deliver: `<Asset>/` with `.fbx`, `.obj`, `.mtl`, `.glb`, `.png`, `.blend`, preview image. Keep previous versions under `_versions/<timestamp>/` instead of overwriting.

## Rigs and animation

For skinned meshes and animations: keep armature scale 1, export with `add_leaf_bones=False`, `bake_anim=True`, only deform bones, and follow Roblox's R15 naming when building avatars. See `characters-rigging`.

## Pitfalls

- Model 100× too big: FBX scale left at 1.0.
- Rotated 90°: transforms not applied, or exported with Apply Transform off.
- Pivot at a corner: origin not set to bottom-centre before export.
- Texture missing: importer did not link it; set `TextureID` or a SurfaceAppearance.
- Holes: Roblox culls back faces; fix open or flipped faces, do not enable double-sided.

## Limitations

Only FBX at 0.01 has a recorded Studio verification (from the source project). OBJ and GLB pass Blender re-import here but are unverified in Studio.
