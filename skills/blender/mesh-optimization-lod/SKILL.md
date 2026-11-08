---
name: mesh-optimization-lod
description: Keeps Roblox meshes cheap - triangle budgets by asset role, decimation and manual reduction, LOD strategy using RenderFidelity and StreamingEnabled, collision meshes via CollisionFidelity or simple proxy parts, texture memory and atlases, draw-call reduction by merging and reuse. Use when an asset is too heavy, before exporting a batch, or when a place lags on mobile.
license: MIT
metadata:
  category: blender
  version: 1.0.0
  triggers: [triangle budget, decimate, lod, collision mesh, collisionfidelity, renderfidelity, poly count, too many triangles]
  depends: [blender-roblox-export]
---

# Mesh optimization and LOD

## Budgets (starting points, tune per game)

| Role | Triangles | Texture |
|---|---|---|
| Small prop or shelf product (many copies) | 100-400 | 1024 atlas shared or 512 |
| Hero prop | 1,000-3,000 | 1024 |
| Building module | 200-1,500 | trim sheet |
| Character | 2,000-6,000 | 1024 |
| Hard limit per mesh on import | 20,000 | |

The supermarket project kept 51 products under about 400 triangles each and they still read as chunky stylized models: spend triangles on silhouette, not flat areas.

## Workflow

1. Measure: `metrics.json` from `build_asset.py`, or in Blender `sum(len(p.vertices) - 2 for p in obj.data.polygons)`.
2. Reduce in this order: remove hidden faces → lower ring counts on cylinders (8-14 segments is enough for props) → merge coplanar faces → Decimate (Collapse, ratio) on organic shapes only, then fix UV seams.
3. LOD in Roblox: there is no manual LOD chain for MeshParts. Use `RenderFidelity = Automatic` (engine LOD) for most props, `Precise` only for hero items, and StreamingEnabled with model `LevelOfDetail = StreamingMesh` for distant models (verify current property names).
4. Collision: `CollisionFidelity = Box` for small props, `Hull` for rounded ones, `PreciseConvexDecomposition` only where players climb. For complex walkable props, weld invisible simple Parts as collision and set the mesh `CanCollide = false`.
5. Draw calls: reuse the same MeshId and TextureID across copies; pack many small props into one texture atlas (`uv-texture-atlas`).

## Validation

Compare before and after triangle counts and renders side by side; in Studio check the MicroProfiler and memory categories (`roblox-performance`).

## Limitations

Engine LOD behaviour is Roblox-controlled and changes; verify in a playtest on a low-end device.
