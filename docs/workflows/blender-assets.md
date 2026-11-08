# Workflow: Blender assets

The pipeline recovered from the supermarket project, generalised.

```
spec.json ─▶ tools/rbxasset (mesh + UV atlas + texture, no Blender) ─▶ layout.json + PNG
          ─▶ scripts/blender/build_asset.py ─▶ .blend, .fbx, .obj/.mtl, .glb, views/*.png, metrics.json
          ─▶ scripts/blender/verify_export.py ─▶ export_check.json (every format re-imported)
          ─▶ QA in asset_batch.py ─▶ qa.json, status.json, contact_sheet.png
          ─▶ user approval ─▶ package_batch.py ─▶ dist/
```

## Run it

```bash
python3 scripts/export/asset_batch.py examples/asset-batch/props.json --out build/props
```

The example builds five assets in about 20 seconds on an Apple-silicon laptop. Add `--skip-blender` for geometry and textures only, or `--no-renders` to skip previews.

## Write a spec

```json
{"batch": "market", "assets": [
  {"name": "MilkJug", "generator": "jug_household", "size": [0.6, 0.45, 1.0], "layout": "guide",
   "colors": {"body": "#F5F7FA", "cap": "#2E86DE"}, "max_tris": 400}
]}
```

Fields: `name` (letters, digits, `_`), `generator` (see `procedural-mesh-generation`), `size` in studs `[X width, Y depth, Z height]`, optional `params`, `colors` (panel → hex), `texture` (your own 1024 PNG), `layout` (`pack` or `guide`), `max_tris`, `exports`, `renders`.

## Custom models

For a hand-made `.blend`, skip the generator: select the object and use the same export calls as `build_asset.py` (`export_fbx`, `export_obj`, `export_glb`). Then validate with `scripts/validate/check_obj.py` and import into Studio. See [asset export](asset-export.md).

## Live Blender

To inspect or tweak a scene interactively, use Blender MCP ([MCP integration](mcp-integration.md)). Move anything that works into a script so it can be repeated.
