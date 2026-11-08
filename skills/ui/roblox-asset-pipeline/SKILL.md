---
name: roblox-asset-pipeline
description: Prepares 2D UI assets for Roblox - icon and image sizes (1024 px maximum per uploaded image, 1024 px sprite sheets with 128 px cells), PNG RGBA with transparency, padding and naming, validation with validate_icon.py, converting third-party packs with import_pack.py, uploading through the Studio Asset Manager or Open Cloud only with permission, mapping asset ids into Icons.configure, and licence records in assets/icons/LICENSE.md and CREDITS.md. Use when preparing icons, sprite sheets, UI images or decals for upload, or when UI images are blurry, cropped or missing.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [ui assets, upload icons, sprite sheet upload, image asset id, icons.configure, ui image size, decal upload, asset manager, sprite sheet, upload ui]
  depends: [roblox-icon-design, asset-sourcing-licensing]
---

# Roblox 2D UI asset pipeline

## Purpose

Get UI images from a file on disk to an `rbxassetid://` in the game, at the right size, consistently named, legally sourced and recorded. This is 2D only; 3D models and batches are `batch-asset-production`.

## When to use (and not)

- Use: icon sheets, card art, banner art, backgrounds, logos, custom illustrated icons.
- Not for meshes, textures for 3D models or product batches: `batch-asset-production`. Not for drawing icons: `roblox-icon-design`. Not for game thumbnails and the experience icon: `game-art-presentation`.

## Sizes and format

| Asset | Size | Notes |
|---|---|---|
| Any uploaded image | at most 1024 x 1024 | larger uploads are downscaled by Roblox; you lose control of the result |
| Icon sprite sheet | 1024 x 1024, 8 x 8 cells of 128 px | one upload for 64 icons; `ImageRectOffset` / `ImageRectSize` pick a cell |
| Single icon (docs, gallery) | 256 px | the kit writes these to `assets/icons/urk/png/` |
| Card art / banner art | width at about 2x its largest on-screen size at 1x, power-of-two friendly (512, 1024) | |
| Nine-slice panels | small (64-128 px) with `SliceCenter` | scale to any size with no blur |

- PNG, RGBA, transparent background, sRGB. No baked drop shadow or background unless the design needs it.
- Padding: art fills 62-96% of its cell with at least 2% margin (what `validate_icon.py` checks); importer cells keep padding so neighbours never bleed at small sizes.
- Naming: lowercase kebab-case (`gem-blue.png`, `starter-pack-banner.png`); illustrated icons end in `-color`; variants end in the variant (`egg-legendary`).

## Workflow

1. **Source or create** the art. Original, generated (see `roblox-icon-design`) or downloaded under a licence that allows use in a game. Record the source before you edit anything.
2. **Validate**: `python3 $URK/tools/icons/validate_icon.py art/*.png` (format, transparency, size, centring, outline, saturation, coverage; `--glyph` for single-colour glyphs, `--json` for reports). Fix the art, not the checks.
3. **Pack** many small images into sheets:
   - kit icons: `python3 $URK/tools/icons/build_icons.py` (kit repo) writes `assets/icons/urk/sheet-<n>.png`, `icons.json`, `preview.png` and `library/src/Icons/IconData.luau`;
   - your own or third-party PNGs: `python3 $URK/tools/icons/import_pack.py <dir> --pack <name> --source <url> --license-note "<terms>" --out assets/icons/<name> --luau src/shared/IconPacks/<Name>.luau` (add `--tint white` only for single-colour packs you want to theme; omit it to keep colours).
4. **Look** at the generated `preview.png` at 100% and at small size.
5. **Upload, only with the user's permission.** Options: Studio > Asset Manager > Bulk Import (the user signs in), or Open Cloud Assets API with the user's own key. Never auto-upload, never ask for or handle the user's credentials, never upload third-party art you cannot redistribute to a public group.
6. **Map ids in config, not code**:
   ```lua
   -- src/shared/Config/IconSheets.luau
   return { "rbxassetid://<sheet1>", "rbxassetid://<sheet2>" }
   -- client start-up
   Icons.configure({ sheets = require(Shared.Config.IconSheets) })
   -- an imported pack:
   IconCatalog.register(require(Shared.IconPacks.Bbb))
   Icons.configure({ pack = "bbb", sheets = { "rbxassetid://<bbb-sheet1>" } })
   ```
   Card and banner art ids go into the spec's `image` field (`"image": "rbxassetid://<id>"`).
7. **Record licences**: kit icons are MIT (`assets/icons/LICENSE.md`). Every third-party item goes in the project's `CREDITS.md` (name, source URL, author, licence, date, use); imported packs also keep their `PROVENANCE.md`.
8. **Verify in Studio**: icons show, crisp at their size, no neighbouring cell bleeding.

## Conventions

- One folder per pack under `assets/icons/<pack>/`; never mix packs in one sheet set.
- Asset ids in one config module per kind (sheets, art), committed; source PNGs committed only when the licence allows.
- Re-uploads get a new id; update config and keep the old id until the new one is verified.

## Common mistakes

- Uploading 4096 px art: Roblox downscales, edges blur.
- White glyphs with `--tint white` on a multi-colour pack: everything becomes a white silhouette.
- Baked grey backgrounds from an image generator (fails the `transparent` check).
- Assets uploaded to a personal account for a group game: they may not load for the group place.
- Hardcoding `rbxassetid://` numbers in many scripts.
- Committing third-party packs to a public repository (the importer writes a `.gitignore` to prevent it).

## Example

Ten custom pet icons from an artist: name them `pet-<species>-color.png`, run `validate_icon.py` (two fail `centred`; artist fixes), `import_pack.py art/pets --pack pets --source "commissioned, <artist>" --license-note "work for hire, full rights" --out assets/icons/pets --luau src/shared/IconPacks/Pets.luau`, the user uploads `sheet-1.png` via Asset Manager, id goes into `Config/IconSheets`, credit goes into `CREDITS.md`.

## Validation

```bash
python3 $URK/tools/icons/validate_icon.py assets/art/*.png
python3 $URK/tools/icons/build_icons.py --check     # kit repo: committed outputs match a fresh build
python3 -m unittest tests/test_icons.py             # kit repo: catalog, sheets, importer provenance
```

In Studio: every sheet id resolves (no grey boxes, Output has no `sheet <n> has no asset id` warning).

## Limitations

- Upload, moderation and asset permissions happen on Roblox; the kit cannot check them.
- `import_pack.py` reads PNG only; convert SVG first.
- Licences of downloaded packs must be read by the person who downloads them; the importer records what they state.
