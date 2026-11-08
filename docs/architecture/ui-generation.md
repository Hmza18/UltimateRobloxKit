# UI generation architecture (UrkUI game layer)

This is the contract for the game-style layer on top of UrkUI. It covers the cartoon and simulator look, the component kit, the declarative screen specs and the builder that turns specs into real Roblox UI. Every module follows [library-conventions.md](library-conventions.md).

```
design/tokens/styles.json ──build_tokens.py──▶ library/src/UI/Style/StyleTokens.luau (generated)
                                  │
                                  └──────────▶ tools/ui/preview_spec.py (HTML preview, approximate)
library/src/UI/Style/Style.luau       resolve palettes, fonts and outlines for the active style (pure)
library/src/UI/Game/*.luau            Roblox components that draw the style (Panel, CartoonButton, ProductCard ...)
library/src/UI/Core/MotionPresets.luau  animation presets as data (pure, tested)
library/src/UI/Spec/SpecSchema.luau   spec validation and defaults (pure, tested)
library/src/UI/Spec/Builder.luau      spec -> instances with Game components (Roblox)
library/src/UI/Spec/Screens/*.json    ready screen specs (Rojo turns .json into ModuleScripts)
library/examples/playground/          Studio playground that renders the real framework
```

## 1. Style layer (pure)

`Style/Style.luau` (pure, no Roblox globals):

| Function | Returns |
|---|---|
| `Style.get(name: string?): StyleDef` | the resolved style (`"cartoon"` by default). Unknown names error |
| `Style.names(): {string}` | the available style names |
| `Style.palette(style, name): { top: string, bottom: string, text: string }` | hex colours; unknown palette names fall back to `"blue"` |
| `Style.surface(style, name): { top, bottom, text }` | `"window"`, `"inset"` or `"dark"` |
| `Style.button(style, kind): { palette: string?, surface: string?, icon: string? }` | kinds: buy, robux, gift, close, primary, danger, neutral, price |
| `Style.badge(style, kind): { palette, shape, text? }` | sale, bonus, attention, new, best |
| `Style.rarity(style, name): { color: string, rainbow: boolean? }` | common ... secret |
| `Style.outline(style, weight: string?): number` | `"thin"`, `"regular"` (default), `"thick"`, `"heavy"` |
| `Style.darken(hex, amount)` / `Style.lighten(hex, amount)` | hex string |
| `Style.setDefault(name)` / `Style.default()` | the style used when components omit `style` |

## 2. Game components (Roblox, `library/src/UI/Game/`)

All components use this shape:

```lua
local card = ProductCard.new(props)   -- returns an object
card.Instance                         -- the root GuiObject (parent it yourself, or pass props.parent)
card:update(partialProps)             -- change props after creation
card:destroy()                        -- disconnects everything (Trove) and destroys the instance
card.Activated                        -- Signal (Util/Signal) for interactive components
```

Shared props on every component: `style: string?`, `parent: Instance?`, `layoutOrder: number?`, `size: UDim2?`, `position: UDim2?`, `anchor: Vector2?`, `name: string?`, `action: string?` (an UrkUI action spec run on activation, such as `"OpenPanel:Shop"` or `"Fire:Buy,starter"`), `visible: boolean?`.

| Module | Extra props | Notes |
|---|---|---|
| `GameText` | `text`, `size: "display"/"title"/"heading"/"label"/"caption"/"price"`, `color: string?` (hex), `stroke: boolean?` (default true), `align: "left"/"center"/"right"`, `minSize: number?`, `maxSize: number?` | Chunky font with a UIStroke text outline. Fits text between min and max (Core/TextFit) |
| `Panel` | `palette: string?` or `surface: string?`, `radius: string?`, `outline: string?`, `gloss: boolean?`, `pattern: boolean?`, `shadow: boolean?`, `padding: string?` | Rounded gradient frame with outline, optional checker pattern and drop shadow. Base of everything |
| `CartoonButton` | `kind: string?` (Style.button kinds), `palette: string?`, `text: string?`, `icon: string?`, `iconSide: "left"/"right"`, `price: Price?`, `enabled: boolean?`, `shine: boolean?` | Hover, press and disabled states through MotionPresets. Price text is formatted from `price` |
| `IconButton` | `icon`, `palette: string?`, `label: string?` (text under the icon), `badge: Badge?`, `shape: "square"/"circle"` | HUD rail buttons |
| `Badge` | `kind` (Style.badge kinds), `text: string?`, `corner: "topRight"/"topLeft"`, `pulse: boolean?` | Sale, bonus, "!" attention, NEW and BEST badges, anchored to the parent's corner |
| `ProductCard` | `palette`, `title`, `subtitle: string?`, `icon: string?`, `image: string?` (asset id, used instead of icon), `price: Price`, `badge: Badge?`, `gift: boolean?`, `rarity: string?`, `owned: boolean?`, `layout: "tall"/"wide"` | Reference 1 egg cards and reference 2 dice and coin cards |
| `PromoBanner` | `palette`, `title`, `subtitle`, `icon`, `price: Price`, `badge: Badge?`, `timer: number?` (seconds left) | The wide "STARTER PACK" card |
| `GameWindow` | `title`, `headerPalette: string?` (default red), `width: number?`, `height: number?`, `closable: boolean?`, `scroll: boolean?`, `sizeClass: "sm"/"md"/"lg"/"full"` | Header bar with outlined title and a red X. `window.Content` is the scrolling frame children go into. `window:open()` / `window:close()` animate. `window.Closed` is a Signal |
| `Section` | `title: string?`, `divider: boolean?` | Heading plus a thick divider line (reference 1 separators) |
| `Grid` | `columns: { phone: number, tablet: number, desktop: number, console: number? }`, `cellAspect: number?`, `gap: string?` | Responsive UIGridLayout. Reads the breakpoint from Core/Breakpoints |
| `CurrencyCounter` | `icon`, `value: number`, `format: string?`, `palette: string?`, `plus: boolean?` (a "+" button that fires the action) | Animated count-up through `MotionPresets.count` |
| `LevelBar` | `level: number`, `value: number`, `max: number`, `palette: string?` | "Lvl. 0 ... 0/100" bar from reference 1 |
| `ProgressBar` | `value`, `max`, `palette`, `showText: boolean?`, `segments: number?` | Animated fill |
| `Timer` | `seconds: number`, `format: "clock"/"short"`, `icon: string?`, `onDone: (() -> ())?` | Countdown driven by one shared Heartbeat ticker |
| `Toggle` | `value: boolean`, `onChanged: ((boolean) -> ())?` | `Changed` Signal |
| `Slider` | `value`, `min`, `max`, `step`, `onChanged` | Mouse, touch and gamepad (left and right) |
| `Dropdown` | `options: {string}`, `value: string`, `onChanged` | |
| `RarityFrame` | `rarity` | Outline colour by rarity; `secret` cycles a rainbow with Decor |
| `RewardPopup` | `title`, `icon`, `amount: string?`, `palette`, `rays: boolean?` | Reveal animation (`MotionPresets.reveal`), auto-closes |

`Price` is `{ kind: "robux" | "currency" | "free", amount: number?, currency: string? (icon name), productId: number?, gamePassId: number? }`. `Badge` is `{ kind: string, text: string? }`.

**Robux display.** Prices show as `R$ 599`, as in reference 2. The kit ships no Robux logo; to use the official icon, pass `robuxImage` in the style or component props, following Roblox's brand guidelines.

**Purchases.** Components never grant anything. A Robux price fires `UrkUI.Intent("Purchase", { productId or gamePassId })`. `Game/PurchaseBridge.luau` (client) prompts with `MarketplaceService:PromptProductPurchase` or `PromptGamePassPurchase`. Granting happens only on the server, through `Systems/Shop` (`ProcessReceipt` for products, ownership checks for passes). A currency price fires `UrkUI.Intent("Buy", { itemId })`, and the server validates and charges.

**Icons.** Every catalog icon has a monochrome glyph (`coin`) and an illustrated colour version (`coin-color`). Specs normally use the `-color` names. `Icons.apply(label, "coin", { style = "color" })` is the same as using `coin-color`.

## 3. Motion presets (pure data, `Core/MotionPresets.luau`)

`MotionPresets.get(name): Preset`, `MotionPresets.names()` and `MotionPresets.sample(preset, t)`. The last one returns `{ scale, rotation, offsetY, transparency }` at normalized time t, for tests and the previewer.

Presets: `hover`, `unhover`, `press`, `release`, `open`, `close`, `popIn`, `bounce`, `count`, `reveal`, `acquire`, `purchase`, `select`, `tabSwitch`, `toastIn`, `toastOut`, `progress`, `attention`, `wiggle`, `shine`.

Each preset is `{ duration: number, easing: string (an Easing name), keys: { { t: number, scale: number?, rotation: number?, offsetY: number?, transparency: number? } }, loop: boolean? }`. Under reduced motion, `Runtime/Motion.play(instance, presetName, options?)` jumps to the last key, or skips looping presets.

## 4. Screen specs

A spec is a JSON object (also valid as a Luau table) describing one screen. `Spec/SpecSchema.luau` validates it and fills in defaults. `tools/ui/validate_spec.py` applies the same rules in Python, and the two are kept equal by shared fixtures.

```json
{
  "spec": 1,
  "id": "PetShop",
  "kind": "window",
  "style": "cartoon",
  "window": { "title": "SHOP", "headerPalette": "red", "sizeClass": "lg" },
  "body": [
    { "type": "banner", "id": "starter", "palette": "teal", "icon": "star-color", "title": "STARTER PACK",
      "subtitle": "A great offer you can't refuse!", "price": { "kind": "robux", "amount": 29, "productId": 0 } },
    { "type": "divider" },
    { "type": "grid", "columns": { "phone": 2, "tablet": 3, "desktop": 3 }, "items": [
      { "type": "product", "id": "tripleHatch", "palette": "purple", "icon": "egg-color", "title": "TRIPLE HATCH",
        "price": { "kind": "robux", "amount": 29, "gamePassId": 0 } }
    ] }
  ]
}
```

Screen kinds:

| Kind | Root |
|---|---|
| `window` | a GameWindow; `body` goes into its content |
| `hud` | a full-screen HUD; `rails` places elements |
| `popup` | a centred RewardPopup or confirm dialog |

HUD `rails` is `{ left?, right?, top?, bottom?, bottomLeft?, bottomRight?, topLeft?, topRight? }`, each a list of elements. Rails respect safe areas through Core/Layout.

Element types and their required fields:

| type | Required | Optional |
|---|---|---|
| `banner` | title, palette, price | id, subtitle, icon, image, badge, timer |
| `product` | title, palette, price | id, subtitle, icon, image, badge, gift, rarity, owned, layout |
| `grid` | items | columns, cellAspect, gap |
| `row` | items | gap, align |
| `heading` | text | size |
| `divider` | | |
| `text` | text | size, color |
| `button` | text or icon | kind, palette, action, price |
| `iconButton` | icon | label, palette, action, badge, shape |
| `currency` | icon, bind or value | format, palette, plus, action |
| `level` | | bind, level, value, max |
| `progress` | | bind, value, max, palette |
| `timer` | seconds | format, icon |
| `toggle` / `slider` / `dropdown` | id, label | value, min, max, step, options, bind |
| `dayCard` | day, reward | state ("claimed", "today" or "locked"), premium, icon, palette |
| `listRow` | title | subtitle, icon, value, progress, button, rank, palette |

`bind` is an UrkUI Store path, such as `"Stats.Cash"`. The element follows it live. `action` uses the UrkUI action syntax. Every interactive element without an action fires `UrkUI.Intent("Select", { id })`.

Validation errors come back as `{ path: string, message: string }`, for example `{ path = "body[3].items[1].price", message = "robux prices need productId or gamePassId" }`. A spec is valid when the list is empty.

## 5. Builder (Roblox, `Spec/Builder.luau`)

```lua
local Builder = require(path.to.UI.Spec.Builder)
local screen = Builder.build(require(path.to.Screens.PetShop), { parent = playerGui, store = UrkUI.store })
screen:open()           -- animated
screen:find("starter")  -- the component object for an element id
screen.Intent           -- Signal(name, args, elementId)
screen:close() ; screen:destroy()
```

`Builder.build` errors with every validation message if the spec is invalid. It never builds a half-valid screen.

## 6. Ownership (parallel work)

| Owner | Paths |
|---|---|
| components agent | `library/src/UI/Game/**`, `library/src/UI/Core/MotionPresets.luau`, `library/src/UI/Core/TextFit.luau`, `library/src/UI/Runtime/Motion.luau` (add `play`), `library/tests/ui_motionpresets.spec.luau`, `library/tests/ui_textfit.spec.luau` |
| spec agent | `library/src/UI/Spec/**` (except the generated StyleTokens), `library/examples/playground/**`, `library/tests/ui_spec*.spec.luau` |
| integrator | `design/`, `tools/ui/`, `tools/icons/`, `library/src/UI/Style/**`, `library/src/Icons/**`, `assets/icons/**`, skills, docs, CI, `UrkUI.luau` exports |
