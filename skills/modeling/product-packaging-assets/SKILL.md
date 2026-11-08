---
name: product-packaging-assets
description: Shop and supermarket product assets - picking the right container or packaging generator, original fictional brands, label layout inside safe areas, shelf display grids (cells per 3.6 x 1.85 stud spot), product images at a fixed camera, and batch delivery by license folder. Recovered from a 51-product Roblox supermarket project. Use when making store goods, grocery items, packaged products, shelf stock or shop inventory models.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [supermarket, product, packaging, grocery, shelf, store item, cereal box, bottle, display grid]
  depends: [procedural-mesh-generation, uv-texture-atlas, batch-asset-production]
---

# Product and packaging assets

## Workflow

1. Product list: name, display type, size or grid, shape description. Group products into batches of five by similar geometry.
2. Pick a generator by shape: boxes → `carton_box`; bags → `pillow_bag`, `bag_gusset`, `paper_sack`; bottles and jars → `bottle`, `jar`, `ribbed_bottle`; cans → `can`, `food_can`; cups and tubs → `cup_tub`, `noodle_cup`; cartons → `gable_carton`, `egg_carton`; bars → `wrapper_bar`.
3. Size from the shelf grid: `tools/rbxasset/grid.py`. A display spot is 3.6 x 1.85 studs, one layer; cell = 3.6/cols x 1.85/rows; keep a gap of at least 0.05 stud; max product height about 1.55.
4. Brand: invent an original name, palette and mascot; check it does not resemble a real brand. Store it as JSON next to the spec.
5. Texture: `"layout": "guide"` so the front art gets 75 % of the texture. Front panel carries the name in chunky outlined type; back gets short copy (small panels blur long text).
6. Build the batch with `scripts/export/asset_batch.py`; the hero view uses the product-image camera (yaw 32°, pitch 17°, about 92 % fill). For round wrap labels, yaw 12° keeps the name visible.
7. Stop for approval per batch.

## Rules that held up in production

- Every text, logo and barcode inside the mesh-derived safe area, unstretched, clear of edges, folds, seams and corners.
- Front marks unique to the front (a brand name also on the back cannot prove orientation).
- Clear packaging needs RGBA texture and SurfaceAppearance transparency in Roblox; back faces are culled, so interiors will not show.
- Keep text out of the top and bottom 15 % of tapered bags.

## Limitations

The kit ships the generic generators and flat painter. The source project's 30 brand-specific label templates are not included (they were tied to that game's brands); recreate label art per project.
