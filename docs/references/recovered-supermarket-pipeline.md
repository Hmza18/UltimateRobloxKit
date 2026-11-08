# Recovered from the supermarket modeling project

The kit started from a real production: 51 stylized supermarket products for a Roblox game, built in 11 batches of about five, all approved by the owner and delivered as `License1` to `License11` zip handoffs. Studio import was never run there because Studio was not installed. This page records what was carried over, what changed, and what could not be recovered. The source project itself was only read, never modified.

## Carried over

| Source project | Kit | Change |
|---|---|---|
| `pipeline/meshkit.py` (MeshData, loft, wrap_loft, planar_loft, cap, extrude, validate) | `tools/rbxasset/meshkit.py` | Unchanged |
| `pipeline/atlas.py` (MaxRects packer, guide 0.75/0.25 layout) | `tools/rbxasset/atlas.py` | Unchanged |
| `pipeline/safe_area.py` (printable areas from geometry) | `tools/rbxasset/safe_area.py` | Unchanged |
| `pipeline/grid.py` (display grid) | `tools/rbxasset/grid.py` | Unchanged |
| `pipeline/generators/` packaging, vessels, cartons, round, electronics, soft goods (38 generators) | `tools/rbxasset/generators/` | Unchanged. Added a fallback in `build()` for proportions a generator was not tuned for |
| None | `tools/rbxasset/generators/props.py` | New: 12 environment prop generators written for the kit |
| `pipeline/stage_blender.py` (build object, materials, render camera, measure, OBJ and FBX export) | `scripts/blender/build_asset.py` | Generalised to any asset. Added GLB export. Renders use EEVEE for speed |
| `pipeline/stage_verify_export.py` (OBJ and FBX re-import) | `scripts/blender/verify_export.py` | Adds GLB. Compares all formats |
| `pipeline/stage_qa.py` (28 product checks plus OCR) | `scripts/export/asset_batch.py` QA (14 automated and 2 manual checks) | Product-specific checks (brand text OCR, shelf fit, guide UV regions) were not carried over. The geometry, transform, UV and export checks were |
| `pipeline/run_product.py` batch gate and `--approve` | `asset_batch.py --status/--approve`, `package_batch.py` | Same rule: nothing is packaged until approved |
| `tools/make_handoff.py` (License zips) | `scripts/export/package_batch.py` | Generic destination; keeps the `_versions` archive rule |
| `tools/contact_sheet.py` | `contact_sheet()` in `asset_batch.py` | Same idea, needs Pillow |
| `tools/studio_manifest.py` and `tools/roblox/StudioAssetTest.luau` | `scripts/export/studio_check.py` | Rewritten as a read-only generated checker |
| `tools/start_blender_mcp.sh`, `tools/blender_mcp_server.sh`, `tests/test_blender_mcp.py` | `integrations/blender/` | Paths made project-relative; pinned pip install replaces the local clone |
| `tools/build_skills.py` (23 custom skills) | `skills/modeling/*`, `skills/blender/*`, `skills/toolchain/roblox-studio-mcp` | Consolidated into 12 skills; supermarket-only rules kept in `product-packaging-assets` |
| `docs/LESSONS.md` | Pitfalls sections of the modeling skills | Kept the lessons that apply beyond packaging |
| `docs/INSTALL_STATUS.md` (third-party review) | `third_party/manifest.json`, `SOURCES.md` | Same pinned commits |
| `.claude/skills/` third-party skills (19) | Optional fetch with `scripts/install/third_party.py` | Not vendored. Fetched at the same pinned commits with their license |

### The 23 custom skills and where they went

| Original skill | Kit skill |
|---|---|
| production-orchestrator, production-progress-tracker, roblox-export-pipeline | batch-asset-production |
| geometry-template-library, procedural-packaging-modeler, bottle-and-can-generator, organic-shape-modeler | procedural-mesh-generation |
| automatic-uv-mapping, professional-packaging-designer (generic parts) | uv-texture-atlas |
| final-quality-gate, mesh-integrity-checker, visual-quality-inspector, texture-quality-control, automated-product-rendering | asset-qa-validation |
| blender-python-automation, blender-mcp-controller, blender-error-recovery | blender-python-headless |
| roblox-studio-asset-tester, roblox-import-validation | roblox-studio-mcp |
| supermarket-modeling-standards, supermarket-product-catalog, display-grid-calculator, original-brand-generator | product-packaging-assets |
| (style direction from LESSONS.md) | stylized-asset-design |

### Third-party skills installed there (19)

EL4CTEO/blender-skills (13), WojciechJelen/roblox-dev-kit (blender-to-roblox, roblox-doctor, find-resources), SyphoDev-yt/roblox-ai-skills (roblox-3d-model), gogolumo rbsmithy, JuliusBrussee caveman. The kit can fetch all of these except roblox-3d-model and caveman (license or scope) with `scripts/install/third_party.py`.

## Lessons kept

- FBX at `global_scale=0.01` with Apply Transform is the Studio-verified format; OBJ and MTL were delivered on request.
- Front -Y, up +Z, origin bottom-centre, transforms applied, one closed mesh, one texture.
- Look at renders from every side; several real defects passed every automated check.
- Fix causes in shared generators, three rounds per issue, then flag.
- Stylized beats realistic for this owner: saturated colour, chunky outlined type, chunky proportions.
- Never test a batch gate by running a later batch.

## Not recovered

- **Chat history** from the earlier sessions is not accessible. Everything here comes from files.
- **The 30 brand-specific packaging templates** (`pipeline/packaging/*.py`, about 6,000 lines) and the brand JSON files. They encode that game's fictional brands; reusing them would copy one game's art into every game.
- **OCR legibility checks** (`tools/ocr.swift`, macOS Vision). They are macOS-only and tied to label templates.
- **The guide document** (`references/original/Supermarket_Modeler_Guide_CLAUDE.md`). It is the client's document, so the kit restates only general rules.
- **The delivered models and textures.** Those are the game's assets, not tooling.
- **Studio validation results.** None exist: Studio was never available to that project.
