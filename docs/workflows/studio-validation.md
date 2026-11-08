# Studio validation (manual procedure)

Automated checks stop at Blender. This procedure turns `roblox_studio_import: NEEDS MANUAL REVIEW` into a recorded result. It was **not run while building the kit**, because Studio was unavailable.

1. Open a **new local place** (File → New). Never use the team's live place.
2. For each asset in `build/<batch>/`, use Home → Import 3D → `<Asset>.fbx` → units Studs → Import. Keep the name `SM_<Asset>`.
3. Generate the checker:
   ```bash
   python3 scripts/export/studio_check.py build/<batch> > StudioCheck.luau
   ```
4. Run it: paste it into the Command Bar, or have Claude run it with Studio MCP `execute_luau`. It is read-only.
5. Copy the `@@URK_STUDIO@@ {...}` line from Output into `build/<batch>/studio_report.json`.
6. Look at each model from the front (the camera looking toward `+Z` sees the asset's front) and from behind. Check texture, orientation and scale against a default avatar (about 5 studs tall).
7. Record the result per asset in your tracker. Report `SIZE_MISMATCH`, `NOT_IMPORTED` or a missing texture as FAIL with a screenshot.

Expected: every asset shows `SIZE_OK` with `texture: true`. If the texture is false, the importer did not link the PNG; set `TextureID`, and note this as a known importer behaviour rather than an asset defect.
