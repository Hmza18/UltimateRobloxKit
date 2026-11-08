---
name: procedural-mesh-generation
description: Generates closed, low-poly, UV-mapped meshes from parameters with the kit's Blender-free mesh kit (tools/rbxasset) - lofts, lathes, extrusions, rounded blocks, multi-shell props - and 73 ready generators for props, furniture, nature, containers and packaging. Use when creating any model from code, adding a new generator, or making many variants of a shape.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [procedural mesh, generator, lathe, loft, meshkit, generate model, low poly model, prop generator]
  depends: [uv-texture-atlas]
---

# Procedural mesh generation

Recovered from the supermarket pipeline, where these generators produced all 51 approved products.

## Inputs

Asset name, generator, size `[width X, depth Y, height Z]` in studs, optional `params` and panel `colors`.

## Workflow

1. List generators: `python3 -c "import sys; sys.path.insert(0,'$URK/tools'); from rbxasset.generators import REGISTRY; print(sorted(REGISTRY))"`.
   Props: crate, barrel, shelf_unit, table, bench, lamp_post, traffic_cone, coin_pickup, stylized_tree, rock, wall_panel, floor_tile. Containers: bottle, can, canister, cup_tub, jar, jug_household, food_can, salt_canister, ribbed_bottle, noodle_cup, fish_tub. Packaging: carton_box, bag_gusset, pillow_bag, paper_sack, sliced_loaf_bag, pouch_pillow, wrapper_bar, wrapper_block, tray_lidded, gable_carton, cheese_block, egg_carton. Electronics and soft goods: phone, tv_flat, console_box, game_case, headset, flat_box, bread_loaf, paper_rolls, pet_toy_bone, lollipop, clothing_shirt, clothing_pants, handbag, sunglasses, watch. Plus 23 more from the approved supermarket products (soda_can, shake_bottle, oval_bottle, bleach_jug, standup_pouch, puffy_pouch, crimped_pet_bag, litter_box, wrapped_bar, domed_lollipop, folded_tee, folded_jeans, hobo_bag, diver_watch, gaming_headset and others); the list command shows all. Each one's approved use is in `license-folder-delivery`'s reference table.
2. Use one in a batch spec (see `batch-asset-production`), or build directly:
   ```python
   import sys; sys.path.insert(0, "tools")
   from rbxasset.generators import build
   from rbxasset.meshkit import validate
   mesh = build({"generator": "barrel", "size": [1.6, 1.6, 2.2]})
   print(validate(mesh))   # closed, outward, tris, degenerate faces
   ```
3. New generator: add a function `name(w, d, h, **params) -> MeshData` to `tools/rbxasset/generators/props.py` (or a new module registered in `generators/__init__.py`) and add it to `GENERATORS`.

## Building blocks (`tools/rbxasset/meshkit.py`)

| Call | Makes |
|---|---|
| `mesh.loft(rings, panels, cap_bottom, cap_top)` | skin of equal-size rings, capped, closed |
| `lathe_rings([(radius, z), ...], n)` | rings for turned shapes (vessels, barrels, posts) |
| `rrect(w, d, r, z)` | rounded-rectangle ring with vertices at front and back centre |
| `mesh.wrap_loft(...)` | wrap label split front/back at the sides (round labels) |
| `mesh.planar_loft(...)` | box-projected art on soft bags |
| `mesh.extrude(outline, z0, z1)` | prism from any CCW outline, triangulated caps |
| `block(mesh, cx, cy, z0, w, d, h, panel)` | rounded block shell (in `props.py`) |
| `mesh.fit(w, d, h)` | exact size, origin bottom-centre |

Rings run counter-clockwise seen from above with vertex 0 at the back (+Y), so the front (-Y) is mid-panel and seams hide at the back.

## Validation

`validate()` must report `closed` and `outward` (positive signed volume) with no degenerate faces; `tests/test_rbxasset.py` checks every registered generator.

## Pitfalls (from production)

- Vertical edges collapse in projected mapping and make zero-area UVs: use elliptical rings for pillow shapes.
- Bottom caps need v flipped or their art is mirrored (`cap(flip=True)` does this).
- Two faces in one plane flicker in game: inset touching shells slightly.
- Holes need a real frame, not a slit (see `wall_panel(window=True)`).

## Limitations

Lofts and lathes cover props, containers and buildings well; organic sculpted forms (faces, animals) need hand modelling or `characters-rigging`.
