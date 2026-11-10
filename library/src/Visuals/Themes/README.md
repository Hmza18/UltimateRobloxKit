# Visuals/Themes

Ten visual themes. A theme is one art direction for the whole game: the UrkUI game style its components use, plus the colour roles, type roles, layout scales, motion feel and effect presets the visuals modules read.

```lua
local Themes = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Themes.Themes)

Themes.set("Luxury")                          -- before building UI
Themes.token("motion.spring.press")           --> "Premium"
Themes.token("motion.duration.fast")          --> 0.16
Themes.color("accent")                        --> Color3
```

`Visuals.Configure({ theme = "Luxury" })` calls `Themes.set` for you.

## The ten themes

| Id | Style key | Look | Fonts (title / body / number) | Motion |
|---|---|---|---|---|
| `VibrantSimulator` | `vibrant` | Candy colours on sky-blue glass, very chunky indigo outlines, big radii | LuckiestGuy / FredokaOne / LuckiestGuy | Bouncy and Playful springs, pops, intensity 1.15 |
| `PremiumCartoon` | `premium` | Warm cream panels, navy outlines, rich gradients, long soft shadows | DenkOne / Nunito / FredokaOne | Premium panels, Overshoot popups, intensity 1.0 |
| `Fantasy` | `fantasy` | Parchment, dark oak outlines, jewel tones, small chiselled corners | GrenzeGotisch / Fondamento / Merriweather | Heavy panels, rising reveals, Cinematic camera |
| `Anime` | `anime` | White panels, ink outlines, hard offset shadows, hot pink and cyan | Bangers / Nunito / Bangers | Overshoot everywhere, 0.13 s normal, intensity 1.3 |
| `SciFi` | `scifi` | Navy glass, thin glowing cyan edges, square corners, grid | Michroma / TitilliumWeb / Sarpanch | Snappy, wipes, small scale amounts |
| `Cozy` | `cozy` | Cream paper, cocoa outlines, very round corners, garden colours | PatrickHand / Nunito / PatrickHand | Soft and Gentle only, slow, intensity 0.7 |
| `ModernMinimal` | `minimal` | Flat white, hairline borders, solid accents, no gloss | BuilderSansBold / BuilderSans / BuilderSansMedium | Snappy, fades instead of pops, scale 1.02 / 0.98, intensity 0.5 |
| `Arcade` | `arcade` | Cabinet-black panels, pixel type, square corners, neon blocks | Arcade / RobotoMono / Arcade | Snappy and Elastic, 0.05 s fast, intensity 1.4 |
| `Luxury` | `luxury` | Black lacquer, fine gold rules, serif titles, jewel fills | Bodoni / JosefinSans / Merriweather | Premium and Cinematic, 0.3 s normal, intensity 0.6 |
| `Adventure` | `adventure` | Forest canvas, leather insets, sturdy outlines, sunset colours | Oswald / Ubuntu / Oswald | Heavy panels that slide, Bouncy rewards |

The default is `VibrantSimulator`. The older styles `cartoon`, `midnight` and `pastel` stay in `styles.json` unchanged; they have no theme of their own.

## Files

| File | What |
|---|---|
| `ThemeData.luau` | Pure data: one complete table per theme. Tokens a style already owns (surface, text and border colours, rarity colours, fonts, text sizes, stroke, spacing, radius, shadow) are read from `UI/Style/StyleTokens`, so a theme cannot drift from its components |
| `ThemeLogic.luau` | Pure rules: `validate`, WCAG `luminance` / `contrast`, `mix`, `readableOn`, `ensureContrast`, `token`, `derive`, `styleKey`, `themeForStyle`, `urkTheme`, `newRegistry` |
| `Themes.luau` | Runtime: current theme, `Changed` signal, `Color3` conversion, and the link to `UI/Style` and UrkUI |

## API (`Themes.luau`)

| Function | Use |
|---|---|
| `Themes.set(id) -> Theme` | Makes a theme current, calls `Style.setDefault(theme.style)`, switches a running UrkUI ThemeService that knows the id, fires `Changed`. Errors on an unknown id |
| `Themes.get(id?) -> Theme` | A theme table, or the current one. Read-only |
| `Themes.current() -> string` | Current theme id |
| `Themes.names() -> { string }` | Registered ids, sorted |
| `Themes.has(id) -> boolean` | Whether an id is registered |
| `Themes.register(id, theme, { override }?) -> Theme` | Adds a custom theme after validating it. The error lists every problem |
| `Themes.derive(base, overrides?) -> Theme` | Deep copy of a theme (id or table) with overrides merged in |
| `Themes.token(path, id?) -> any` | `"motion.spring.press"`, `"effects.glow.soft.size"`, `"effects.particles.1"`. Missing tokens fall back to the default theme, then `nil` |
| `Themes.color(name, id?) -> Color3` | A colour role (`"accent"`), a rarity (`"Legendary"`) or any `"#RRGGBB"` |
| `Themes.particleColors(id?) -> { Color3 }` | The theme's particle palette |
| `Themes.style(id?) -> string` | The `styles.json` key |
| `Themes.urkThemes() -> { [id]: ThemeDef }` | Role themes for `UrkUI.start({ themes = ... })` |
| `Themes.validate(theme) -> { Problem }` | `{ path, kind, message }` per problem; empty when valid |
| `Themes.Changed` | `Util/Signal`, fires `(id, theme, previousId)` |

## Tokens in a theme

| Section | Tokens |
|---|---|
| `colors` | `primary`, `secondary`, `accent`, `success`, `warning`, `error`, `background`, `surface`, `text`, `textMuted`, `border`, `glow` |
| `rarity` | `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic`, `Secret` |
| `typography` | `fonts`, `weights` and `sizes` per role (`display`, `title`, `heading`, `body`, `label`, `caption`, `number`), `fallback`, `stroke` (`title`, `body`, `number`), `shadow` (`soft`, `hard`), `scale` per breakpoint, `numbers` (`style`, `decimals`, `separator`, `suffixCase`, `tabular`) |
| `layout` | `spacing`, `radius`, `padding` (`screen`, `panel`, `card`, `button`, `chip`), `margin` (`screen`, `section`, `item`), `safeArea`, `breakpoints` (`phone`, `tablet`, `desktop`, `console`: `columns`, `gutter`, `hudScale`, `density`), `layers` (`hud` 0, `panel` 10, `modal` 50, `toast` 80, `reveal` 120, `debug` 1000) |
| `motion` | `duration` (`instant`, `fast`, `normal`, `slow`, `cinematic`), `easing` (a `Core/Curves` name), `spring` per role (`press`, `hover`, `panel`, `popup`, `card`, `reward`, `camera`; `Core/Springs` names), `intensity`, `scale` (`hover`, `press`, `pop`), `transition` per role (`panel`, `popup`, `toast`, `card`, `reward`, `screen`), `stagger`, `reduced` |
| `effects` | `shadow` (`sm`, `md`, `lg`), `glow` (`soft`, `strong`, `reward`), `gradient` (`primary`, `accent`, `surface`, `reward`), `outline` (`thin`, `regular`, `bold`), `highlight` (`select`, `hover`, `reward`), `shine` (`subtle`, `sweep`, `reward`), `particles`, `sparkle` |

Transition values are `pop`, `slide`, `fade`, `scale`, `rise`, `wipe`, `blink` or `none`. `motion.reduced` is what modules use when reduced motion is on: a spring that does not overshoot, shorter durations and `fade` for every transition.

## Custom themes

```lua
local candy = Themes.derive("VibrantSimulator", {
	name = "Candy Shop",
	colors = { accent = "#B0125E", glow = "#FFB3E6" },
	motion = { spring = { popup = "Elastic" }, intensity = 1.25 },
})
Themes.register("CandyShop", candy)
Themes.set("CandyShop")
```

`register` rejects a theme with a missing token, a colour that is not `#RRGGBB`, a spring or curve name that does not exist, durations out of order, a reduced-motion transition other than `fade` or `none`, or text that does not reach 4.5:1 on `background` and `surface` (3:1 for `accent` and `primary` on `background`). A custom theme reuses one of the existing style keys; a new component look needs a new style in `design/tokens/styles.json`.

## With UrkUI

Game components (`UI/Game`) take their look from `Style.get()`, which `Themes.set` switches. They read the style when they are built, so set the theme first or rebuild on `Themes.Changed`.

Base UrkUI components use role themes. To give them the same palette, start UrkUI with the themes this module generates; `Themes.set` then switches its ThemeService too, which re-skins those components live:

```lua
UrkUI.start({ themes = Themes.urkThemes(), theme = Themes.current() })
```

## Performance

Themes are plain tables built once at require time. `Themes.token` walks a short path; modules that read a token every frame should cache it and refresh on `Themes.Changed`. `Themes.color` caches each `Color3`.

## Not verified in Studio

`ThemeData` and `ThemeLogic` are pure and covered by `library/tests/visuals_themes.spec.luau` (validity, style mapping, contrast, distinctness, derive, registry, token fallback, UrkUI role themes at AA). `Themes.luau` itself (the `Style.setDefault` call, the ThemeService switch, `Color3` conversion and the signal) was NOT run in Studio, and how each theme looks on screen is `NEEDS MANUAL REVIEW`: fonts, strokes and gradients have only been checked as token values.
