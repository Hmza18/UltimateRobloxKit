---
name: roblox-icon-design
description: Icons for Roblox game UI - the kit's original MIT URK Icons as monochrome glyphs, illustrated -color versions and colour variants in 1024 px sprite sheets, the Icons API (configure, apply with style, create), the UrkIcon tag, the illustrated style rules (thick dark outline, gradient, gloss, shadow, automatic alignment), adding new icons in urk_icons.py with colours and variants, rebuilding and validating, an optional image-generation workflow, and licensing of third-party packs. Use when a UI needs icons, an icon is missing, someone wants a new icon drawn or generated, or wants to import an icon pack.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [icon, icons, icon pack, coin icon, sprite sheet, urkicon, illustrated icon, draw an icon, generate icon, import icons, ui icons]
  depends: []
---

# Roblox icon design

## Purpose

Use, extend and validate the kit's icon set so every icon in a game shares one look: chunky silhouette, thick dark outline, saturated gradient fill, soft top-left gloss. The set is drawn from code (`tools/icons/urk_icons.py`), so it is original, MIT and reproducible.

## When to use (and not)

- Use: picking icons for specs and HUDs, theming them, adding a missing icon, generating illustrated art, importing a pack.
- Not for upload, sizes and id mapping in depth: `roblox-asset-pipeline`. Not for the experience icon and thumbnails: `game-art-presentation`. Not for a purchased or private pack that must stay untouched and out of git: `uvk-icon-pack`.

## Three kinds of icon

| Kind | Name | Looks | Use for |
|---|---|---|---|
| Glyph | `coin` | white silhouette, tinted with `ImageColor3` | small buttons, lists, toggles, themed UI (light, dark, high contrast) |
| Illustrated | `coin-color` | outlined, gradient, gloss, shadow | cards, HUD buttons, rewards, specs (the default there) |
| Variant | `gem-blue`, `egg-legendary`, `medal-bronze` | illustrated in another colour | tiers, rarities, currencies |

Find names: `python3 $URK/urk.py icons search <word>`, `python3 $URK/urk.py icons list [category]`, `assets/icons/urk/icons.json`, or the dashboard Icons tab (`python3 $URK/urk.py dashboard --open`). Galleries: `assets/icons/urk/preview.png` (glyphs) and `preview-color.png` (illustrated).

## Workflow: use icons in a game

1. Install the module: `python3 $URK/urk.py add Icons --project .` (UrkUI includes it).
2. Upload the sheets `assets/icons/urk/sheet-1.png` ... (1024 px each) once, with the user's permission (Studio Asset Manager or Open Cloud). Keep ids in config.
3. Configure on the client and apply:
   ```lua
   local Icons = require(ReplicatedStorage.Shared.Urk.Icons.Icons)
   Icons.configure({ sheets = require(ReplicatedStorage.Shared.Config.IconSheets) })
   Icons.apply(label, "coin", { color = Color3.fromRGB(255, 200, 40), size = 32 }) -- tinted glyph
   Icons.apply(label, "coin", { style = "color" })  -- same as "coin-color"
   Icons.apply(label, "egg-legendary")              -- a variant
   local settingsIcon = Icons.create("settings", { size = 24 })
   ```
   `style = "glyph"` turns a `-color` name back into its glyph. `Icons.variants`, `Icons.styled`, `Icons.list(category, style)` and `Icons.search` help pick names in code.
4. No code: tag an ImageLabel or ImageButton `UrkIcon` with attribute `Icon` (`IconColor`, `IconSize` optional); UrkUI applies and re-tints on theme change.
5. Specs: use `-color` names on `product`, `banner`, `iconButton`, `currency`, `dayCard`; glyph names are accepted.

Names accept `arrow_left`, `Arrow Left` and `arrowLeft`. `Icons.configure({ aliases = { money = "coins" } })` adds game-specific names.

## The illustrated style (applied automatically by `tools/icons/illustrate.py`)

1. Silhouette = the glyph with holes filled.
2. Shadow: silhouette offset down, dark, soft.
3. Outline: silhouette dilated about 4.5% of the size, near-black `#1B1530` (same as the UI outline token).
4. Detail: the glyph's holes filled with a darker shade of the base colour.
5. Body: vertical gradient, light top -> base -> darker bottom.
6. Gloss: soft white ellipse upper-left, clipped to the body.
7. Automatic alignment in `tools/icons/build_icons.py`: every icon is centred and scaled so its largest side fills 84% (glyph) or 90% (illustrated) of the cell, so icons line up in rows whatever their drawn position.

Glyph rules (`urk_icons.py` header): chunky silhouettes, strokes 9-12 units, rounded joins, optical size about 80 units on the 100 grid, holes cut with `pen.cut()`.

## Workflow: add a new icon

1. Draw it in `tools/icons/urk_icons.py`:
   ```python
   @icon("seed", "items", "plant farm grow")
   def _(p):
       p.ellipse(50, 56, 26, 32)          # body
       p.cut().line([(50, 34), (50, 70)], 6)  # centre groove as a hole
       p.ink().poly([(50, 10), (62, 26), (50, 30), (38, 26)])  # sprout
   ```
   Pen: `circle`, `ellipse`, `ring`, `rect(x0, y0, x1, y1, r)`, `poly`, `line(pts, w)`; `cut()` switches to erasing, `ink()` back to drawing.
2. Colour it in `tools/icons/illustrate.py`: add `"seed": "#8BC34A"` to `PALETTE` (otherwise the category colour in `CATEGORY_COLORS` is used). Multi-colour parts go in `REGIONS`, a list of `((x0, y0, x1, y1) in 100-unit space, "#hex")`, for example a brown handle on a sword.
3. Variants: add `"seed": {"gold": "#F7C21B"}` to `VARIANTS` in `tools/icons/build_icons.py` to get `seed-gold`.
4. Rebuild: `python3 $URK/tools/icons/build_icons.py` (needs Pillow). It writes singles, sheets, `icons.json`, previews and `library/src/Icons/IconData.luau`.
5. Look at `preview.png` (dark and light bands) and `preview-color.png`; compare the new icon with neighbours at small size.
6. Test: `python3 -m unittest tests/test_icons.py` and `python3 $URK/tools/icons/build_icons.py --check`.
7. New sheets or moved cells mean re-uploading the changed sheets and updating ids.

## Optional: image-generation workflow

For art the code style cannot draw (a detailed pet, a food item), use an image model the user has access to:

1. Prompt template: "original cartoon game icon of <thing>, thick dark outline, saturated colours, soft top-left highlight, 3/4 view, centred, transparent background, no text, no logos".
2. Export PNG RGBA at 512 or 1024 px; remove any background the model baked in.
3. Validate: `python3 $URK/tools/icons/validate_icon.py out/*.png` (transparent, size 62-96%, centred within 6%, dark outline, saturation, coverage). Fix or regenerate failures; do not loosen checks.
4. Import as a colour pack (no `--tint`, which keeps the colours): `python3 $URK/tools/icons/import_pack.py out --pack gen --source "generated with <model>, <date>" --license-note "<model terms>" --out assets/icons/gen --luau src/shared/IconPacks/Gen.luau`.
5. Record the model and its terms in `CREDITS.md`. Never prompt for a named game's or brand's icons.

## Licensing

- URK Icons: MIT (`assets/icons/LICENSE.md`); free for commercial games.
- Never copy or trace icons from proprietary packs or other games.
- Packs that allow in-game use but not republishing (for example the BuiltByBit "Free Icon Pack") are imported locally only: the user downloads under its terms, `import_pack.py` writes `PROVENANCE.md` and a `.gitignore`. Redistributable: Kenney (CC0), Tabler and Phosphor (MIT), Lucide (ISC); game-icons.net (CC BY 3.0) with credit.
- Only `--tint white` single-colour packs can be themed with `ImageColor3`.

## Conventions

- Lowercase kebab-case names; illustrated end in `-color`; variants end in the variant word.
- One look per screen: do not mix URK illustrated icons with a flat third-party pack on the same cards.
- Icon sizes from tokens (`sizes.icon`: sm 24, md 40, lg 72, xl 110).

## Common mistakes

- Tinting a `-color` icon with `ImageColor3` (muddy colours); tint glyphs only.
- Forgetting `Icons.configure`: Output warns `sheet <n> has no asset id` and icons are blank.
- Drawing thin 3-unit strokes: they vanish at 24 px.
- Hand-placing art off-centre and "fixing" it with offsets; alignment is automatic.
- Committing a downloaded pack to a public repository.

## Validation

```bash
python3 $URK/tools/icons/build_icons.py --check
python3 -m unittest tests/test_icons.py
python3 $URK/tools/icons/validate_icon.py path/to/*.png
cd library && lune run tests/run   # icons_catalog.spec.luau: lookup, styles, aliases, packs
```

## Limitations

- Sheets must be uploaded before icons render in Roblox; the kit never uploads.
- `import_pack.py` reads PNG only; convert SVG first.
- The BuiltByBit licence page could not be read automatically; the downloader checks the terms.
- Image-model output quality and licence terms vary; validation checks style, not originality.
