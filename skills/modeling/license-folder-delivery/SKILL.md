---
name: license-folder-delivery
description: The License folder structure used to deliver approved Roblox 3D objects - handoff/License<N>/<Asset>/ with <Asset>_FBX.fbx, <Asset>_OBJ.obj, .mtl, .png, _Image.png and .blend, plus a verified License<N>.zip - together with the 51 owner-approved supermarket objects as size and shape references and Roblox reference sizes for walls, fixtures and products. Use when packaging or handing off 3D assets, naming delivery folders, or when sizing or choosing a shape for a new Roblox object by referencing earlier approved work.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [license folder, license1, handoff, deliver assets, delivery zip, reference object, approved models, reference size, _fbx]
  depends: [batch-asset-production, procedural-mesh-generation]
---

# License folder delivery and 3D references

The delivery format and references from the user's supermarket project, where 51 products went out as `License1` to `License11`. Use the same structure for every new batch of Roblox 3D objects unless the user asks for another.

## When to use

- Handing off approved assets, building a delivery zip, naming delivery folders.
- Starting any new Roblox object: look up a similar approved reference and the standard sizes first.
- Not for building or QA itself; that is `batch-asset-production` and `asset-qa-validation`.

## The structure

```
handoff/
├── License1/
│   ├── TamsCereal/
│   │   ├── TamsCereal_FBX.fbx      FBX, scale 0.01, Apply Transform (the Studio import file)
│   │   ├── TamsCereal_OBJ.obj      OBJ, -Z forward, Y up
│   │   ├── TamsCereal.mtl          material for the OBJ (keeps the plain name the OBJ references)
│   │   ├── TamsCereal.png          1024 texture
│   │   ├── TamsCereal_Image.png    512 transparent product image (yaw 32, pitch 17)
│   │   ├── TamsCereal.blend        editable source, relative texture path
│   │   └── TamsCereal_GLB.glb      only when GLB was exported (kit addition)
│   └── <four more assets>/
├── License1.zip                    entries start with License1/, verified byte for byte
├── License2/ ...
└── _previous/<timestamp>/          earlier deliveries, moved here, never overwritten
```

Rules:

1. **`License<N>` is the delivery batch number** (batch 1 → `License1`), whichever in-game product line the items belong to. The product line ("guide license": 1 Starter, 2 Pantry, 3 Fresh, 4 Pet, 5 Candy, 6 Drinks, 7 Frozen, 8 Cleaning, 9 Electronics, 10 Clothing and fashion) is a separate fact; keep it in your catalog.
2. One folder per asset, named with the PascalCase asset name, no apostrophes (`Tam's Cereal` → `TamsCereal`).
3. FBX and OBJ get `_FBX` and `_OBJ` suffixes so a client can tell them apart. The other files keep the plain name.
4. Only approved assets are delivered. An earlier delivery of the same number moves to `_previous/<timestamp>/`.
5. Every copied file and every zip entry is compared with its source.

## Workflow

1. Build and QA the batch: `python3 $URK/scripts/export/asset_batch.py specs/batch-01.json --out build/batch-01` (renders must be on, because `_Image.png` comes from `views/hero.png`).
2. Show the user the renders and wait for approval in chat. Record it: `python3 $URK/scripts/export/asset_batch.py --approve <Asset> build/batch-01`.
3. Deliver: `python3 $URK/scripts/export/package_batch.py build/batch-01 --license 1 --dest handoff`.
   It refuses if any asset is not approved, prints `License1.zip: 5 assets, N files`, and leaves earlier deliveries in `_previous/`.

## Referencing earlier objects

- [references/approved-products.md](references/approved-products.md): all 51 approved objects with handoff folder, product line, generator, exact size, display grid, triangle count and approved shape. Find the nearest shape and reuse its generator and proportions.
- Rebuild any of them as a shape reference (flat colour, no label art):
  `python3 $URK/scripts/export/asset_batch.py $URK/examples/supermarket-reference/products.json --license-group 6 --out build/ref6`
- [references/roblox-reference-sizes.md](references/roblox-reference-sizes.md): walls, doors, shelves, fridges, freezers, counters, delivery boxes and product limits in studs.

## Validation

- `package_batch.py` exit 0 and the printed file count (6 or 7 files per asset).
- `unzip -l handoff/License<N>.zip` lists `License<N>/<Asset>/...` paths only.
- `tests/test_license_delivery.py` covers the layout, naming, refusal of unapproved assets and the `_previous` archive.

## Pitfalls

- Renaming the OBJ does not rename its `mtllib` line; that is why the `.mtl` keeps the plain name.
- Do not test the delivery step on an unapproved batch to "see what happens"; it only reports and exits, but never fake approval to get past it.
- Products from the reference list carry the supermarket game's fictional brands; new games need new brands.

## Limitations

The reference set gives geometry and sizes only. The original label art, brand files and the full modeling guide stay in the private supermarket project. Studio import of these deliveries was never verified there (Studio was unavailable).
