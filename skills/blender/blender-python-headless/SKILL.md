---
name: blender-python-headless
description: Writes and runs repeatable Blender Python (bpy) - headless command-line runs, the kit's JSON-in/JSON-out stage scripts, live control through Blender MCP, version-safe API use for Blender 4.x and 5.x, and recovery when a stage fails or Blender crashes. Use for any bpy scripting, batch Blender job, Blender MCP session, or failed Blender stage.
license: MIT
metadata:
  category: blender
  version: 1.0.0
  triggers: [bpy, blender python, headless blender, blender mcp, blender script, blender crash, background mode]
  depends: []
---

# Blender Python, headless and live

## When to use

Any automation in Blender. For export settings see `blender-roblox-export`; for geometry generation without Blender see `procedural-mesh-generation`.

## Workflow

1. Find Blender: `$BLENDER`, then PATH, then `/Applications/Blender.app/Contents/MacOS/Blender` or `C:\Program Files\Blender Foundation\Blender <ver>\blender.exe` (`scripts/lib/env.py` does this).
2. Run every stage the same way, so failures are real exit codes:
   `blender -b --factory-startup --python-exit-code 1 --python script.py -- <args>`
   `--factory-startup` ignores the user's add-ons and prefs, which makes runs reproducible.
3. Structure a stage as JSON in, JSON out, as `scripts/blender/build_asset.py` and `verify_export.py` do: read a spec, act, measure, write a result file, print one `..._OK` line.
4. Live work: Blender MCP (`ahujasid/mcp-for-blender`, see `$URK/integrations/blender/README.md`). Start with scene info, run small scripts with `execute_blender_code`, look at the viewport, then move anything that worked into a headless script.

## Version-safe bpy

```python
import bpy
# Look nodes up by type, never by localized name.
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
# Operator options change between versions: pass only the ones this build knows.
known = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
bpy.ops.export_scene.gltf(**{k: v for k, v in opts.items() if k in known})
# Engines: read the enum instead of hard-coding.
try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    scene.render.engine = "BLENDER_EEVEE"
```

Build meshes with `mesh.from_pydata`, then `mesh.validate()`; set UVs per loop; use `mesh.set_sharp_from_angle()` (4.1+) instead of the removed auto-smooth flag.

## Error recovery

| Symptom | Fix |
|---|---|
| `keyword ... unrecognized` | API changed: filter options as above |
| Exit 0 but no output file | Missing `--python-exit-code 1`, or the exception was caught |
| Context errors in operators | Select and set the active object first, or use `bpy.context.temp_override` |
| Hangs on render | Lower samples, use EEVEE, and set a subprocess timeout |
| Crash | Re-run once with `--debug-python`; if it repeats, bisect the script; never loop retries |

## Validation

Each stage writes a measurement file; compare it to the spec in Python outside Blender (as `asset_batch.py` does). Look at renders.

## Limitations

Blender MCP sends telemetry unless disabled; the kit's launcher sets `DISABLE_TELEMETRY=1`. Headless EEVEE needs a GPU-capable context on some Linux CI runners; use Cycles CPU there.
