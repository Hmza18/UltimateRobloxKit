---
name: game-icons
description: Icons for Roblox UI - the kit's 92 original MIT icons (currency, rewards, actions, status, interface, items, stats) as tintable sprite sheets, the Icons API and UrkIcon tag, searching the catalog, uploading sheets, theming with ImageColor3, importing third-party packs you downloaded under their own licence, and drawing new matching icons. Use when a UI needs icons, an icon is missing, or someone wants to add an icon pack.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [icon, icons, icon pack, sprite sheet, imagelabel icon, coin icon, ui icons, import icons]
  depends: []
---

# Game icons

## Use the kit's icons

1. Find names: `python3 $URK/urk.py icons search <word>`, `python3 $URK/urk.py icons list [category]`, or the Icons tab of the dashboard (`python3 $URK/urk.py dashboard --open`), which also previews tint and theme.
2. Add the module to the game: `python3 $URK/urk.py add Icons --project .` (UrkUI includes it).
3. Upload the sprite sheets once: `assets/icons/urk/sheet-1.png` and `sheet-2.png` (1024 px). Use Studio's Asset Manager or Open Cloud, but only with the user's permission. Keep the ids in config, not in code.
4. Configure once on the client:
   ```lua
   local Icons = require(ReplicatedStorage.Shared.Urk.Icons.Icons)
   Icons.configure({ sheets = { "rbxassetid://<sheet1>", "rbxassetid://<sheet2>" } })
   Icons.apply(imageLabel, "coin", { color = Color3.fromRGB(255, 200, 40), size = 32 })
   local settingsIcon = Icons.create("settings", { size = 24 })
   ```
5. No code at all: tag an ImageLabel or ImageButton with `UrkIcon` and set its `Icon` attribute (UrkUI applies it and re-tints it on theme change).

Glyphs are white on transparency, so `ImageColor3` (or the theme's text or accent token) colours them for light, dark and high-contrast themes. Names accept `arrow_left`, `Arrow Left` and `arrowLeft`. `Icons.configure({ aliases = { money = "coins" } })` adds game-specific names.

## Import a pack you downloaded

Some free packs, such as the BuiltByBit "Free Icon Pack", can be used in a game but not republished. The kit cannot ship those. The user downloads the pack under its licence, then:

```bash
python3 $URK/tools/icons/import_pack.py ~/Downloads/pack --pack bbb --prefix bbb- --tint white \
  --source "<url>" --license-note "<terms the user accepted>" \
  --out assets/icons/bbb --luau src/shared/IconPacks/Bbb.luau
```

Then call `IconCatalog.register(require(...Bbb))` and `Icons.configure({ pack = "bbb", sheets = {...} })`. The importer writes `PROVENANCE.md` and a `.gitignore`, so the files are not committed to public repositories by accident. Only `--tint white` single-colour packs can be themed. Never commit third-party icons unless their licence allows redistribution: Kenney (CC0), Tabler and Phosphor (MIT) and Lucide (ISC) do, while game-icons.net (CC BY 3.0) does with credit.

## Draw new icons in the same style

Add a function to `tools/icons/urk_icons.py` with `@icon(name, category, tags)` on its 100-unit grid. Use chunky shapes, strokes of 9-12 units, and `pen.cut()` for holes. Then run `python3 tools/icons/build_icons.py` (needs Pillow), look at `assets/icons/urk/preview.png` in both bands, and run `python3 -m unittest tests/test_icons.py`.

## Validation

`tests/test_icons.py` checks unique kebab-case names, categories, tags, 1024 sheets, 256 px singles, non-overlapping cells, that the Luau data matches the catalog, that the build is reproducible, and that the importer writes provenance and protects existing packs. `library/tests/icons_catalog.spec.luau` covers lookup, normalization, search ranking, aliases and pack registration.

## Limitations

Sheets must be uploaded before icons render in Roblox, and the kit never uploads them on its own. The BuiltByBit pack's licence could not be read automatically (bot protection), so its terms must be checked by the person downloading it. SVG packs need converting to PNG first.
