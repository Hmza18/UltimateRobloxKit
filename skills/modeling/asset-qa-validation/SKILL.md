---
name: asset-qa-validation
description: Quality gate for 3D assets before delivery - automated checks (closed manifold mesh, outward normals, triangle budget, exact size, bottom-centre origin, identity transforms, no n-gons, UVs in range, one material, FBX/OBJ/GLB re-import, relative texture paths), multi-angle renders and contact sheets, plus honest PASS / FAIL / NEEDS MANUAL REVIEW reporting. Use before calling any model done, when reviewing an asset batch, or when asked for validation results.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [qa, validate asset, quality check, contact sheet, non-manifold, normals, inspect render, asset review]
  depends: [blender-roblox-export]
---

# Asset QA and validation

## Automated checks (`scripts/export/asset_batch.py`, written to `<Asset>/qa.json`)

| Check | Source |
|---|---|
| closed_outward_geometry | Python mesh validation (no Blender) |
| triangle_budget, roblox_mesh_limit | spec `max_tris` (default 400), Roblox 20,000 |
| blender_dims_match_spec | `metrics.json`, tolerance 0.002 stud |
| origin_bottom_centre, identity_transforms | `metrics.json` |
| blender_closed_mesh, no_ngons, uvs_in_range, single_material | bmesh measurements |
| reimport_fbx / obj / glb | `export_check.json`, one object and matching size per format |
| blend_reopens_relative_paths | the `.blend` reopens with `//` texture paths |
| visual_inspection | always NEEDS MANUAL REVIEW |
| roblox_studio_import | always NEEDS MANUAL REVIEW until done in Studio |

For a single existing mesh, `python3 $URK/scripts/validate/check_obj.py model.obj --max-tris 400` checks closedness, triangle count and bounds without Blender.

## Visual inspection (required, by eye)

Open `<out>/contact_sheet.png` and each `<Asset>/views/*.png` (hero, front, back, left, right, top, three-quarter back). Look for: holes, dark inverted faces, z-fighting stripes, floating parts, stretched or clipped text, wrong colours, anything resembling a real brand. Note findings per asset.

## Fix loop

Fix the cause in the generator, spec or shared code, rebuild only that asset (`--only Name`), re-inspect. Three rounds per issue, then flag it to the user.

## Reporting

Report the four layers separately: automated QA, Blender re-import, Roblox Studio (done or unavailable), visual inspection, and the user's approval. Never fold a manual item into PASS.

## Limitations

Automated checks cannot judge style or legibility. OCR of text (used in the source project via macOS Vision) is not shipped in the kit.
