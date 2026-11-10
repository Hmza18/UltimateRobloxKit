# Design system reference

The visual design system of the kit: which file owns which decision, the token vocabulary, and the ten themes. For the API see [Visuals/Themes](../../library/src/Visuals/Themes/README.md); for the architecture see [visuals.md](../architecture/visuals.md).

## How the pieces relate

```
design/tokens/styles.json          the look of game components (source of truth, hand-written)
  └─ tools/ui/build_tokens.py ─▶ library/src/UI/Style/StyleTokens.luau   (generated, do not edit)
       ├─ UI/Style/Style.luau      lookups with fallbacks; one default style
       │    └─ UI/Game/*           buttons, cards, windows, badges read the style when built
       └─ Visuals/Themes/ThemeData.luau   one theme per style: reads the style, adds motion,
            │                             colour roles, type roles, layout and effects
            └─ Visuals/Themes/Themes.luau  current theme; Themes.set also sets the default style
                 └─ every Visuals module   reads motion and effect tokens from the current theme
```

| Decision | Owner | Change it by |
|---|---|---|
| Palette swatches, surfaces, outlines, radii, fonts, text sizes, rarity colours of components | `design/tokens/styles.json` | Editing the JSON, then `python3 urk.py ui tokens` |
| Colour roles, type weights, layout scales, motion, effect presets | `library/src/Visuals/Themes/ThemeData.luau` | Editing the theme's spec, or `Themes.derive` at runtime |
| Which theme is active | The game | `Themes.set(id)` or `Visuals.Configure({ theme = id })` |
| Base UrkUI role colours (`primary`, `onPrimary`, `focus`, ...) | `UI/Core/Tokens` or `Themes.urkThemes()` | `UrkUI.start({ themes = Themes.urkThemes() })` |

A theme never repeats a value its style owns. `ThemeData` reads surface, text and border colours, rarity colours, font families, text sizes, text stroke, spacing, radius and shadow from the generated style, so components and effects cannot disagree.

## The ten themes

| Theme | Id | Style key | Surfaces | Outline | Radius (md) | Title font | Motion |
|---|---|---|---|---|---|---|---|
| Vibrant Simulator | `VibrantSimulator` | `vibrant` | Light, sky blue | Indigo, 4 px | 18 | LuckiestGuy | Bouncy, pops, intensity 1.15 |
| Premium Cartoon | `PremiumCartoon` | `premium` | Light, warm cream | Navy, 3 px | 16 | DenkOne | Premium, soft overshoot, 1.0 |
| Fantasy | `Fantasy` | `fantasy` | Light, parchment | Dark oak, 3 px | 6 | GrenzeGotisch | Heavy, rising, cinematic, 0.9 |
| Anime | `Anime` | `anime` | Light, white | Ink, 3 px | 5 | Bangers | Overshoot, very fast, 1.3 |
| Sci-Fi | `SciFi` | `scifi` | Dark, navy glass | Glowing cyan, 2 px | 4 | Michroma | Snappy, wipes, 0.85 |
| Cozy | `Cozy` | `cozy` | Light, cream paper | Cocoa, 2 px | 20 | PatrickHand | Soft and Gentle, slow, 0.7 |
| Modern Minimal | `ModernMinimal` | `minimal` | Light, flat white | Slate hairline, 1 px | 8 | BuilderSansBold | Snappy, fades, 0.5 |
| Arcade | `Arcade` | `arcade` | Dark, cabinet violet | Near black, 4 px | 2 | Arcade | Snappy and Elastic, shortest, 1.4 |
| Luxury | `Luxury` | `luxury` | Dark, black lacquer | Gold, 2 px | 6 | Bodoni | Premium and Cinematic, slowest, 0.6 |
| Adventure | `Adventure` | `adventure` | Dark, forest canvas | Dark green, 3 px | 10 | Oswald | Heavy slides, Bouncy rewards, 1.0 |

The last column ends with the theme's motion intensity. The earlier styles `cartoon`, `midnight` and `pastel` are unchanged and have no theme.

## Colour

Colours are `#RRGGBB` strings in data and become `Color3` at the edge (`Themes.color`).

| Role | Meaning | Rule |
|---|---|---|
| `background` | Behind panels: screen backdrops, page fill | |
| `surface` | Panels and windows (the style's window colour) | |
| `text` | Body text on `background` and `surface` | At least 4.5:1 on both |
| `textMuted` | Secondary text, captions, hints | At least 4.5:1 on both |
| `primary` | The main action and the dominant brand colour | At least 3:1 on `background` |
| `secondary` | The second action colour | |
| `accent` | Highlights, selection, focus | At least 3:1 on `background` |
| `success`, `warning`, `error` | Outcomes | At least 3:1 on `surface` (checked by the spec) |
| `border` | Outlines (the style's outline colour) | |
| `glow` | Glows, shines and highlight fills | Decorative, no contrast rule |

Rarity colours are `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic` and `Secret`, taken from the style. `Secret` is also flagged `rainbow` in the style, so components may cycle its hue.

In `styles.json`, palette swatches (`red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `gold`, `gray`) are gradients with a `top`, a `bottom` and a `text` colour. Two rules keep text on them readable, both enforced by tests:

- With a text stroke of 2 px or more, the stroke carries the contrast: stroke against the swatch is at least 3:1, and stroke against the text at least 4.5:1.
- With a thinner stroke (`scifi`, `minimal`, `luxury`), the text colour itself reaches 4.5:1 on both ends of the gradient. That is why those styles use dark text on their yellow, gold and gray swatches.

Surface text (`window`, `inset`, `dark`) reaches 4.5:1 on both ends of the surface gradient in every style.

## Typography

| Role | Family from | Use |
|---|---|---|
| `display`, `title`, `heading` | Style `fonts.title` | Screen titles, window headers, section headings |
| `body`, `label`, `caption` | Style `fonts.body` | Paragraphs, buttons, small print |
| `number` | Style `fonts.number` | Prices, counters, damage numbers |

Every family is an `Enum.Font` name that Roblox ships; `UI/Game/Kit.font` resolves it and falls back to the style's `fallback`. Each role also has a weight (an `Enum.FontWeight` name) and a size in pixels at 1x. `typography.scale` gives a text scale per breakpoint (`phone`, `tablet`, `desktop`, `console`, the names in `UI/Core/Breakpoints`); phones scale down slightly and consoles up, for ten-foot viewing.

Stroke presets (`title`, `body`, `number`) and shadow presets (`soft`, `hard`) come from the style's text stroke and shadow. `typography.numbers` says how numbers read: `abbreviated` (1.2K), `grouped` (1,234) or `padded` (001234, Arcade), with `decimals`, `separator`, `suffixCase` and `tabular`.

Whether a given weight exists for a family in Roblox, and how each font renders, is `NEEDS MANUAL REVIEW`.

## Layout

| Token | Values |
|---|---|
| `spacing` | `xs`, `sm`, `md`, `lg`, `xl`, `xxl` (from the style) |
| `radius` | `sm`, `md`, `lg`, `xl`, `pill` (from the style) |
| `padding` | `screen`, `panel`, `card`, `button`, `chip` |
| `margin` | `screen`, `section`, `item` |
| `safeArea` | HUD and modals stay inside the device safe area (`inset`); full-screen backdrops go under it (`bleed`); `minInset` is the smallest gap to a screen edge |
| `breakpoints` | Per `phone`, `tablet`, `desktop`, `console`: grid `columns`, `gutter`, `hudScale`, `density` |
| `layers` | `hud` 0, `panel` 10, `modal` 50, `toast` 80, `reveal` 120, `debug` 1000 |

Layers are DisplayOrder bands. The first four match UrkUI's own bands, so kit screens and UrkUI screens stack together; reward reveals sit above toasts and the debug overlay above everything.

## Motion

| Token | Meaning |
|---|---|
| `duration.instant`, `fast`, `normal`, `slow`, `cinematic` | Seconds. Never decreasing. `fast` and `normal` equal the style's own values |
| `easing` | Default curve for tweens, a `Visuals/Core/Curves` name |
| `spring.press`, `hover`, `panel`, `popup`, `card`, `reward`, `camera` | `Visuals/Core/Springs` preset per role |
| `intensity` | Multiplier for travel, scale and shake amounts (0.5 Modern Minimal to 1.4 Arcade) |
| `scale.hover`, `press`, `pop` | Scale amounts, equal to the style's `hoverScale`, `pressScale`, `popOvershoot` |
| `transition.panel`, `popup`, `toast`, `card`, `reward`, `screen` | `pop`, `slide`, `fade`, `scale`, `rise`, `wipe`, `blink` or `none` |
| `stagger` | Seconds between list items |
| `reduced` | Substitutes under reduced motion: a non-overshooting spring, `durationScale`, and `fade` for every transition |

| Theme | Normal | Press | Popup | Reward | Camera | Panel transition |
|---|---|---|---|---|---|---|
| Vibrant Simulator | 0.16 s | Bouncy | Bouncy | Bouncy | Soft | pop |
| Premium Cartoon | 0.20 s | Snappy | Overshoot | Bouncy | Gentle | scale |
| Fantasy | 0.22 s | Soft | Soft | Premium | Cinematic | rise |
| Anime | 0.13 s | Overshoot | Overshoot | Elastic | Snappy | slide |
| Sci-Fi | 0.16 s | Snappy | Snappy | Overshoot | Gentle | wipe |
| Cozy | 0.26 s | Soft | Soft | Soft | Gentle | rise |
| Modern Minimal | 0.15 s | Snappy | Snappy | Soft | Gentle | fade |
| Arcade | 0.10 s | Snappy | Elastic | Elastic | Snappy | pop |
| Luxury | 0.30 s | Premium | Premium | Cinematic | Cinematic | fade |
| Adventure | 0.20 s | Snappy | Overshoot | Bouncy | Heavy | slide |

Modules read these instead of hard-coding a feel: `Themes.token("motion.spring.popup")`, `Themes.token("motion.duration.fast")`. The user's settings are meant to win over the theme: when `Host.settings().reducedMotion` is on a module should use `motion.reduced`, and `Host.settings().intensity` should multiply the theme's intensity. The theme only supplies the tokens; applying them is each module's job.

## Effects

| Token | Presets | Fields |
|---|---|---|
| `shadow` | `sm`, `md`, `lg` | `color`, `offsetX`, `offsetY`, `transparency`, `spread` |
| `glow` | `soft`, `strong`, `reward` | `color`, `size`, `transparency` |
| `gradient` | `primary`, `accent`, `surface`, `reward` | `rotation`, `stops` (`at` 0..1, `color`) for a UIGradient |
| `outline` | `thin`, `regular`, `bold` | `color`, `thickness`, `transparency` for a UIStroke |
| `highlight` | `select`, `hover`, `reward` | `fill`, `outline`, `fillTransparency`, `outlineTransparency` for a Highlight |
| `shine` | `subtle`, `sweep`, `reward` | `color`, `angle`, `width`, `speed`, `transparency` |
| `particles` | 3 to 5 colours | What VFX tints with when a preset has no colour of its own |
| `sparkle` | One texture key | The theme's default particle shape (`star`, `spark`, `glow`, `flare`, `ring`, `heart`, `circle`, `confetti`, `leaf`) |

Roblox has no blurred drop shadow for UI: `shadow` presets describe an offset copy behind the element, and `spread` is how many pixels larger that copy is.

Texture keys refer to the kit's generated textures. See [visual assets](../workflows/visual-assets.md).

## Adding a theme

1. Add a complete style to `design/tokens/styles.json` with the same sections as `vibrant` (no `extends`), then run `python3 urk.py ui tokens`.
2. Add a spec to `ThemeData.luau` and its id to `ThemeData.IDS`.
3. Run the checks below. They fail on unreadable text, an unknown spring or curve, durations out of order, or a theme that duplicates another's primary colour, fonts or spring set.

```bash
python3 urk.py ui tokens --check
```

```bash
cd tests && python3 -m unittest test_ui_specs test_visuals_tools -v
```

```bash
cd library && lune run tests/run tests visuals_themes
```

For a variation of an existing theme inside one game, do not edit the kit: use `Themes.derive` and `Themes.register`.

## What is and is not verified

| Verified by tests | Not verified |
|---|---|
| Every style and theme has every token; hex colours are well formed | How any theme looks in Roblox: fonts, strokes, gradients, shadows |
| Contrast ratios above, computed with the WCAG 2 formula | Legibility at real sizes on real devices |
| Spring and curve names exist; durations are ordered | How the motion feels |
| Font families are `Enum.Font` names | That each family supports the chosen weight |
| The generated `StyleTokens.luau` is current | `Themes.luau` running in Studio |

Visual results are `NEEDS MANUAL REVIEW` in Studio. The HTML spec preview (`tools/ui/preview_spec.py`) approximates styles in a browser, and some of its text colours are fixed for light panels, so dark styles (`scifi`, `arcade`, `luxury`, `adventure`) may preview with dark text on dark panels there even though the tokens are correct.
