---
name: batch-asset-production
description: Runs asset production at scale - batch spec files, the asset_batch.py pipeline (layout, Blender build, exports, re-import, QA, contact sheet), batches of about five, approval gates with status tracking, versioned rebuilds, delivery folders and zip handoff. Use when asked to make many models ("20 products", "a prop pack"), to continue or rebuild a batch, or to package assets for handoff.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [batch, asset pack, many models, 20 products, prop pack, handoff, approval, rebuild asset]
  depends: [procedural-mesh-generation, asset-qa-validation, kit-conventions]
---

# Batch asset production

## Spec

```json
{"batch": "kitchen-props", "assets": [
  {"name": "Crate", "generator": "crate", "size": [2, 2, 2],
   "colors": {"wood": "#D08A3E", "wood_end": "#A9692B"}, "max_tris": 400,
   "exports": ["fbx", "obj", "glb"]}
]}
```
Full example: `$URK/examples/asset-batch/props.json`. Template project: `$URK/templates/asset-pipeline/`.

## Workflow

1. Plan batches of about five assets with similar shapes. Write the spec.
2. Run: `python3 $URK/scripts/export/asset_batch.py spec.json --out build/<batch>`
   (`--skip-blender` for geometry and texture only, `--only Name` to rebuild one, `--no-renders` for speed).
3. Read the console summary and `status.json`. Fix FAILs at the cause.
4. Look at `contact_sheet.png` (needs Pillow: `pip install pillow`) and each `views/` folder.
5. Show the user the images and the QA summary. **Stop.** Do not start the next batch until they approve this one in chat.
6. Record approval: `python3 $URK/scripts/export/asset_batch.py --approve <Asset> build/<batch>` for each approved asset.
7. Package: `python3 $URK/scripts/export/package_batch.py build/<batch> --zip dist/<batch>.zip` copies approved assets only, with FBX, OBJ, MTL, GLB, PNG, `.blend` and preview.
8. Before rebuilding an approved asset, move its folder to `build/<batch>/_versions/<timestamp>/` (the packager refuses to overwrite).

## Validation

`status.json` shows every asset `approved` before packaging; `package_batch.py` exits non-zero otherwise.

## Pitfalls

- Never test the gate by running a later batch; it marks things failed.
- Keep one spec per batch under version control; outputs are rebuildable and belong in `.gitignore`.

## Limitations

Approval is recorded by the agent on the user's word; the script cannot verify who approved.
