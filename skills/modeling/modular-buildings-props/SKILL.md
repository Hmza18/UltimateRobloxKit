---
name: modular-buildings-props
description: Modular building kits, furniture, interiors, street furniture, vehicles and decorative props for Roblox - stud-grid modules, pivots that snap, wall/floor/trim pieces with real openings, prop families sharing one atlas, and assembling kits in Studio with consistent scale. Use when building a set of structures or props, a shop interior, a street, or any kit meant to snap together.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [modular, building kit, furniture, interior, wall panel, street props, vehicle model, decorative props, snap grid]
  depends: [procedural-mesh-generation, mesh-optimization-lod, map-world-building]
---

# Modular buildings and props

## Grid and pivots

- Pick one module size and never break it: 4 studs for small props and furniture spacing, 8 studs for walls and floors, 12 or 16 studs for storey height.
- Pivot at bottom-centre for props (drops onto floors), at a bottom corner or edge centre for walls if your placement tool snaps edges. Be consistent per kit and write it down.
- Wall thickness 1 stud; doors at least 4 wide x 8 tall for a Roblox avatar; ceilings at least 12 high so the camera does not clip.

## Workflow

1. Kit list: floor tile, wall, wall with window, wall with door, corner, trim, roof piece, plus props.
2. Generate with the kit: `wall_panel` (`window=true` makes a real opening), `floor_tile`, `shelf_unit`, `table`, `bench`, `lamp_post`, `traffic_cone`, `crate`, `barrel`, `stylized_tree`, `rock`. Sizes are studs in the spec.
3. One palette per kit and one shared texture where practical, so copies batch well.
4. Build all pieces with `scripts/export/asset_batch.py`, check the contact sheet for matching style.
5. In Studio: import once, convert to Packages or keep in `ReplicatedStorage/Kit`, place with Studio's grid snap set to the module size; anchor everything static.
6. Vehicles: separate body, wheels and seats as separate meshes so constraints can drive them; keep wheel pivots at the axle centre.

## Validation

Assemble a test room from the kit and look for gaps, z-fighting where pieces meet (inset trims slightly) and mismatched texel density.

## Limitations

Placement and snapping happen in Studio; the kit does not generate whole buildings automatically. Vehicles need a driving rig (`roblox-physics-interactions`).
