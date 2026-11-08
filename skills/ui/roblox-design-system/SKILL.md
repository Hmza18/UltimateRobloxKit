---
name: roblox-design-system
description: The UrkUI game design system - design/tokens/styles.json as the single source of truth for fonts, text sizes, outlines, radius, spacing, surfaces, palettes, buttons, badges, rarity colours, motion and sizes, regenerated into Style/StyleTokens.luau with urk.py ui tokens, the pure Style.luau API, adding a new style with extends, naming and contrast rules. Use when changing colours, fonts, outlines or spacing, adding a style or theme variant, or when a component or spec hardcodes a colour.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [design tokens, styles.json, style tokens, design system, new style, palette token, ui colours, stroke weight, styletokens, midnight style, pastel style]
  depends: []
---

# Roblox design system (UrkUI game styles)

## Purpose

Keep every colour, size, outline and duration of the cartoon game UI in one file, so a whole game can change look by editing tokens instead of components or specs. Contract: `docs/architecture/ui-generation.md` section 1.

```
design/tokens/styles.json --(urk.py ui tokens)--> library/src/UI/Style/StyleTokens.luau (generated, never edit)
                          \-> tools/ui/preview_spec.py reads the JSON directly (HTML previews)
library/src/UI/Style/Style.luau  pure resolver: palettes, surfaces, buttons, badges, rarity, outlines
```

## When to use (and not)

- Use: recolouring the game UI, adding a seasonal or brand style, changing font or outline weights, choosing palette names for a spec, reviewing a component that hardcodes `Color3.fromRGB`.
- Not for the older UrkUI themes (`dark`, `light`, `highContrast` in `Core/Tokens.luau`, colour roles such as `primary`): see `urk-ui-framework`, section Theming. Those drive tag-built UI; this file drives the Game components and screen specs.
- Not for visual principles (which palette means what, hierarchy): see `roblox-ui-design`.

## Workflow

1. Open `design/tokens/styles.json` in the kit repository. The token build reads and writes kit paths only (`design/` and `library/src/UI/Style/`), so restyle in a kit checkout and reinstall or copy the regenerated `StyleTokens.luau` into the game.
2. Change values or add a style (see below). Colours are `#RRGGBB`, sizes are pixels at 1x (UIScale scales them), durations are seconds.
3. Regenerate the Luau module:
   ```bash
   python3 $URK/urk.py ui tokens          # writes library/src/UI/Style/StyleTokens.luau
   python3 $URK/urk.py ui tokens --check  # CI: exit 1 if the Luau module is stale
   ```
   `tools/ui/build_tokens.py` resolves `extends` (deep merge) here, so the runtime gets complete styles.
4. Preview a screen in the new style: set `"style": "<name>"` in a spec and run `python3 $URK/urk.py ui preview <spec.json> --open`.
5. Validate specs again (`python3 $URK/urk.py ui validate <spec.json>`): palette, badge, rarity and size names are read from the active style, so a removed token surfaces as an error.
6. In Studio, check the playground's Theme preview page (`library/examples/playground`).

## The token groups

| Group | Keys (cartoon) | Used by |
|---|---|---|
| `fonts` | title, body, number, fallback | GameText, prices (number) |
| `text` | display 44, title 32, heading 24, label 18, caption 14, price 20, minimum 12 | GameText sizes; `minimum` is the floor on every device |
| `textStroke` | color, thickness 3, smallThickness 2 | outlined titles |
| `outline` | color, thin 2, regular 3, thick 4, heavy 6 | `Style.outline(style, weight)` for UIStroke |
| `radius` | sm 8, md 14, lg 20, xl 28, pill 999 | UICorner |
| `spacing` | xs 4, sm 8, md 12, lg 16, xl 24, xxl 32 | padding, `gap` in specs |
| `shadow`, `gloss`, `pattern` | offsets, transparency, checker or diamond cells | Panel decoration |
| `surfaces` | window, inset, dark | window bodies, insets, price pills |
| `palette` | red orange yellow green teal blue purple pink gold gray, each `{top, bottom, text}` | gradients of cards, buttons, headers |
| `buttons` | buy robux gift close primary danger neutral price | `Style.button(style, kind)` |
| `badges` | sale bonus attention new best | `Style.badge` (palette + shape) |
| `rarity` | common ... secret (rainbow) | RarityFrame, product `rarity` |
| `motion` | hoverScale, pressScale, popOvershoot, fast, normal, slow, count, reveal | MotionPresets, CartoonButton |
| `sizes` | card, banner, hudButton, icon sm/md/lg/xl | default component sizes |

## Style.luau API (pure, testable in Lune)

```lua
local Style = require(ReplicatedStorage.UltimateRobloxKit.UI.Style.Style)
local s = Style.get("cartoon")              -- errors on unknown names; Style.names() lists them
local card = Style.palette(s, "purple")     -- { top = "#B98CFF", bottom = "#7A4DE8", text = "#FFFFFF" }
local win = Style.surface(s, "window")      -- window | inset | dark
local buy = Style.button(s, "robux")        -- { palette = "green", icon = "robux" }
local sale = Style.badge(s, "sale")         -- { palette = "red", shape = "pill" }
local epic = Style.rarity(s, "epic")        -- { color = "#A855F7" }
local px = Style.outline(s, "thick")        -- 4
local hover = Style.lighten(card.top, 0.1)  -- hex in, hex out; Style.darken too
Style.setDefault("midnight")                -- components that omit `style` use it
```

Unknown palette names fall back to `blue` in `Style.palette`, but the spec validator rejects them, so typos never ship silently.

## Adding a style with `extends`

```json
"winter": {
  "description": "Icy event variant of cartoon.",
  "extends": "cartoon",
  "surfaces": { "window": { "top": "#F4FBFF", "bottom": "#DCEFFF", "text": "#16304A" } },
  "outline": { "color": "#16304A" },
  "palette": { "red": { "top": "#7FD3FF", "bottom": "#2C9BEA", "text": "#FFFFFF" } }
}
```

Only list what changes; everything else is inherited by deep merge. Keep every palette name of the parent (specs reference them by name, so `red` may become icy blue for an event, but must exist). Then run `urk.py ui tokens` and use `"style": "winter"` in specs or `Style.setDefault("winter")`.

## Conventions

- Never hardcode colours, font sizes or outline widths in components or specs. Specs name palettes (`"palette": "teal"`), components ask `Style`. The one exception is `text.color` in a spec for a one-off accent; prefer a palette.
- Palette names describe hue (`teal`), not purpose; purpose lives in `buttons` and `badges` (`buy` -> green). Change the meaning once in `buttons`, not in every spec.
- Token keys are lowerCamel or single words; style names are lowercase single words (`cartoon`, `midnight`).
- `StyleTokens.luau` is generated. Edit the JSON and regenerate; CI runs `--check`.
- The kit ships no Robux logo. Prices render as `R$ 599`; to use the official icon pass `robuxImage` and follow Roblox brand guidelines.

## Design guidelines

- **Contrast.** White text with the dark text stroke (`textStroke`) stays readable on every palette; keep that stroke when you lighten palettes. For text without a stroke (body copy on `window` surfaces) keep 4.5:1 (WCAG AA). `Core/Contrast.luau` has `Contrast.ratio(a, b)` and `Contrast.meets(a, b, level, large)`; put those checks in a Lune spec for any new style.
- **Gradients** go light top to darker bottom, 15-25% apart in lightness. Bigger jumps look striped, smaller ones look flat.
- **Outline colour** is one near-black tinted toward the palette's shadow hue (`#1B1530` is purple-black), never pure `#000000`.
- **Pastel styles** need dark text on light fills (`pastel.green.text` is `#2B2240`). Check every palette's `text`.
- Keep `text.minimum` at 12 or above; phones render small text poorly.

## Common mistakes

- Editing `StyleTokens.luau` by hand: overwritten on the next build, and `--check` fails CI.
- Removing a palette in a child style: impossible with `extends` (merge), but deleting it from `cartoon` breaks every spec using it.
- Using `Color3.fromRGB(255, 90, 90)` in a component "just for this card": the next restyle misses it.
- Adding a style but not running `urk.py ui tokens`: `Style.get("winter")` errors at runtime.
- Choosing colours by eye on a monitor only: check a phone in sunlight-level brightness and the colour-blind pairs (red/green buy vs danger also differ by icon and label).

## Example

Request: "make the shop darker and more premium". Use the shipped `midnight` style (dark surfaces, near-black outline, diamond pattern): set `"style": "midnight"` in the spec, preview, and validate. Only if the user wants different hues, add a `extends: "midnight"` style overriding `palette`.

## Validation

```bash
python3 $URK/urk.py ui tokens --check      # StyleTokens.luau matches styles.json
python3 $URK/urk.py ui validate library/src/UI/Spec/Screens/*.json
python3 -m unittest tests/test_ui_specs.py # Python validator and shared fixtures
cd library && lune run tests/run            # includes ui_gamestyle.spec.luau
```

Then look at the preview and the Studio playground Theme page; tokens can be valid and still ugly.

## Limitations

- The HTML previewer approximates fonts, UIStroke and gradients with CSS; final colour judgement needs Studio.
- Contrast for outlined text on gradients is not measured automatically; the stroke rule is a convention.
- Font names must exist in Roblox's `Enum.Font`/`Font.fromName` set; the build script does not check that.
