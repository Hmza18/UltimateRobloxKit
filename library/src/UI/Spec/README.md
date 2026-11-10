# UI screen specs

A screen spec is a small JSON document (or a Luau table of the same shape) that describes one
screen: a shop window, a HUD or a popup. `SpecSchema.luau` validates it and fills in defaults, and
`Builder.luau` turns it into real Roblox UI made of the Game components in `../Game/`. The format
is the contract in [ui-generation.md](../../../../docs/architecture/ui-generation.md), sections 4
and 5.

| File | Runs in | Purpose |
|---|---|---|
| `SpecSchema.luau` | anywhere (pure Luau, Lune tests) | `validate`, `withDefaults`, the rule tables |
| `Builder.luau` | Roblox client | `Builder.build(spec, options)` returns a screen object |
| `Screens/*.json` | Rojo turns each into a ModuleScript | 16 ready, reference-quality screens |

Ready screens: `PetSimShop`, `PremiumStore`, `GamepassStore`, `MainHud`, `DailyRewards`,
`Inventory`, `PetHatch`, `Upgrades`, `Quests`, `Achievements`, `Settings`, `Leaderboard`,
`Profile`, `Trading`, `RewardPopup` and `ConfirmPurchase`. Every Robux price in them uses id `0`, a
placeholder: replace it with your developer product or game pass id before you publish.

## Contents

- [Spec format](#spec-format)
- [Element types](#element-types)
- [Prices, badges, binds and actions](#prices-badges-binds-and-actions)
- [Validation](#validation)
- [Building a screen](#building-a-screen)
- [Turning a request into a spec (for AI agents)](#turning-a-request-into-a-spec-for-ai-agents)
- [What is verified](#what-is-verified)

## Spec format

```json
{
  "spec": 1,
  "id": "PetShop",
  "kind": "window",
  "style": "cartoon",
  "description": "Optional note for people and tools.",
  "window": { "title": "SHOP", "headerPalette": "red", "sizeClass": "lg" },
  "body": [ { "type": "heading", "text": "GAMEPASSES" } ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `spec` | yes | Format version, always `1` |
| `id` | yes | Identifier (letters, digits, `_`, `-`); also the ScreenGui name |
| `kind` | yes | `window`, `hud` or `popup` |
| `style` | no | A `Style.names()` entry: `cartoon` (default), `midnight`, `pastel`, or one of the ten Visuals styles `vibrant`, `premium`, `fantasy`, `anime`, `scifi`, `cozy`, `minimal`, `arcade`, `luxury`, `adventure` |
| `description` | no | Up to 200 characters |
| `window` | window | `title` (required), `headerPalette` (`red`), `sizeClass` (`sm`/`md`/`lg`/`full`, default `md`), `closable` (true), `scroll` (true), `width`, `height` (pixels, override sizeClass) |
| `body` | window, optional for popup | List of elements, top to bottom |
| `rails` | hud | `{ left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }`, each a list of elements |
| `popup` | popup | `variant` (`reward` or `confirm`), `title`, `message`, `icon`, `amount`, `palette`, `rays`, and for confirm: `confirmText`, `cancelText`, `price` |

Every element has a `type` and may carry `id` (unique across the screen), `visible` (default true),
`note` (ignored, for authors) and `motion` (see [Motion](#motion)). Unknown fields are errors, so
typos surface at once.

Palettes: `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `gold`, `gray`.
Button kinds: `buy`, `robux`, `gift`, `close`, `primary`, `danger`, `neutral`, `price`. Badge kinds:
`sale`, `bonus`, `attention`, `new`, `best`. Rarities: `common`, `uncommon`, `rare`, `epic`,
`legendary`, `mythic`, `secret`. Gaps: `xs`, `sm`, `md`, `lg`, `xl`, `xxl`. Text sizes: `display`,
`title`, `heading`, `label`, `caption`, `price`. All of these come from the active style
(`design/tokens/styles.json`), and validation reads them from there.

Icons are catalogue names. Use the illustrated `-color` names (`coin-color`, `egg-color`); the
monochrome glyph names (`coin`) are also accepted. Unknown names are errors.

Icons of an imported pack are written `pack:name`, lowercase kebab-case on both sides of the colon
(`mypack:iron-sword`). Both validators check only that shape, because a pack is registered in the
game at runtime (`Visuals.Icons.register`, see [Visuals/Icons](../../Visuals/Icons/README.md)); a
pack icon that is not registered shows nothing. Call `Visuals.Icons.bridge()` once so the Game
components resolve pack names too. The HTML preview draws a labelled tile for a pack icon, never
the artwork.

## Element types

Required fields are in bold. Defaults filled by `withDefaults` are in brackets.

| type | Fields | Builds |
|---|---|---|
| `banner` | **title**, **palette**, **price**, subtitle, icon, image, badge, timer (seconds) | PromoBanner |
| `product` | **title**, **palette**, **price**, subtitle, icon, image, badge, gift [false], rarity, owned [false], layout [`tall`] | ProductCard |
| `grid` | **items**, columns [phone 2, tablet 3, desktop 3, console = desktop], cellAspect [1.25], gap [`md`] | Grid |
| `row` | **items**, gap [`md`], align [`center`] | horizontal list |
| `heading` | **text** (60), size [`heading`] | Section with divider |
| `divider` | | Section divider |
| `text` | **text** (200), size [`label`], color (`#RRGGBB`) | GameText |
| `button` | **text** (24) or **icon**, kind [`robux` / `buy` / `primary` from the price], palette, action, price | CartoonButton |
| `iconButton` | **icon**, label (16), palette, action, badge, shape [`square`] | IconButton |
| `currency` | **icon**, **bind** or **value**, format [`abbrev`], palette, plus [false], action | CurrencyCounter |
| `level` | bind, level [0], value [0], max [100] | LevelBar |
| `progress` | bind, value [0], max [100], palette [`green`] | ProgressBar |
| `timer` | **seconds**, format [`clock`] (`clock`/`short`), icon | Timer |
| `toggle` | **id**, **label** (40), value [false], bind | label + Toggle |
| `slider` | **id**, **label**, min [0], max [1], step [0.1], value [min], bind | label + Slider |
| `dropdown` | **id**, **label**, **options**, value [first option], bind | label + Dropdown |
| `dayCard` | **day** (1-31), **reward** (24), state [`locked`] (`claimed`/`today`/`locked`), premium [false], icon, palette | Panel card |
| `listRow` | **title**, subtitle, icon, value, progress `{ value, max, bind, palette }`, button (a button element), rank, palette | Panel row |

### Animated components

These build the seventeen animated components of [UI/Game](../Game/README.md#animated-components),
which take their motion from `Visuals/UI`.

| type | Fields | Builds | Intent |
|---|---|---|---|
| `premiumButton` | **text** (24) or **icon**, image, palette, action, shine, glow | PremiumButton | `Select` |
| `tabBar` | **id**, **tabs** (1-8 of `{ id, text, icon }`, text or icon each), value [first tab id], palette | TabBar | `Tab { id, value }` |
| `modal` | **id**, **title**, text (200), buttons (1-3 of `{ id, text, kind }`), headerPalette, closable [true] | Modal over the whole screen, hidden until `screen:find(id):open()` | `Select { id, button }`, `Close` |
| `tooltip` | **text**, **target** (the id of another element), side [`top`] (`top`/`bottom`/`left`/`right`) | Tooltip on the target | |
| `xpBar` | bind, level [1], value [0], max [100], palette | XPBar | |
| `inventorySlot` | icon, image, count, rarity, selected, equipped, locked, action | InventorySlot | `Select` |
| `petCard` | **title**, icon, image, rarity, stats (1-3 of `{ text, icon, image }`), palette, selected, equipped, action | PetCard | `Select` |
| `rarityBadge` | **rarity**, text (12) | RarityBadge | |
| `rewardPanel` | **rewards** (1-12 of `{ icon, image, amount, rarity }`, icon or image each), title, columns (1-6), claimText, claimed, palette | RewardPanel | `Claim` |
| `questCard` | **title**, description (90), value, max, rewards (1-3 chips), state (`active`/`claimable`/`claimed`), claimText, palette | QuestCard | `Claim` |
| `achievementCard` | **title**, description, icon, image, tier (0-5, at most maxTier), maxTier, value, max, unlocked, palette | AchievementCard | |
| `notification` | **title**, text (90), kind [`info`] (`info`/`success`/`warning`/`error`), icon, image, palette, duration (seconds, 0 keeps it) | Notification in the layout flow | `Select` on click, `Close` |
| `leaderboardRow` | **title**, rank, value, format, avatar (asset id), highlight, bind | LeaderboardRow | |
| `loadingScreen` | title, icon, image, tips (1-20 strings), progress (0-1), palette | LoadingScreen over the whole screen | `Close` |
| `selectionCard` | **title**, description, icon, image, palette, selected, action | SelectionCard | `Select` |
| `hotbarSlot` | **icon**, **image** or **keybind** (4), palette, cooldown (seconds), action | HotbarSlot | `Select { id, ready }` |
| `statChip` | **value** (number or text) or **bind**, icon, image, format, prefix (8), suffix (8), palette | StatChip | |

```json
{ "type": "tabBar", "id": "tabs", "tabs": [ { "id": "pets", "text": "PETS" }, { "id": "eggs", "text": "EGGS" } ] }
{ "type": "petCard", "id": "pet_fox", "title": "Ember Fox", "rarity": "epic", "icon": "paw-color",
  "stats": [ { "icon": "coin-color", "text": "x2.5" } ], "equipped": true, "motion": { "preset": "CardReveal", "delay": 0.1 } }
{ "type": "questCard", "id": "hatch10", "title": "EGG COLLECTOR", "description": "Hatch 10 eggs", "value": 4, "max": 10 }
{ "type": "hotbarSlot", "id": "dash", "icon": "energy-color", "keybind": "Q", "cooldown": 8 }
{ "type": "premiumButton", "id": "claim", "text": "CLAIM REWARD", "icon": "gift-color", "motion": "Pulse" }
{ "type": "tooltip", "text": "Doubles coins for 10 minutes", "target": "claim", "side": "bottom" }
```

Screens raise intents only. A `Claim` or a hotbar `Select` grants nothing: the server decides, and
the game then updates the element (`screen:update("hatch10", { state = "claimed" })`). A hotbar slot
with `cooldown` starts that countdown on each press while it is ready; this is presentation, and
the `ready` flag in the intent is a hint, not proof.

### Motion

`motion` plays a `Visuals.UI` preset on the element each time the screen opens:

```json
{ "type": "banner", "motion": "SlideInDown", "title": "SALE", "palette": "red", "price": { "kind": "free" } }
{ "type": "button", "text": "PLAY", "motion": { "preset": "Pulse", "delay": 0.4 } }
```

The value is a preset id, or `{ preset, delay }` with a delay of 0 to 5 seconds. The id must be
registered in `Visuals/UI/UIPresets` (`PopIn`, `SlideInUp`, `CardReveal`, `Pulse`, `Glow`,
`BadgePop` ... see [Visuals/UI](../../Visuals/UI/README.md)); presets a game registers before
validating are accepted in Luau. The Python validator checks against `MOTION_PRESETS` in
`tools/ui/spec_rules.py`, a copy of the built-in ids that `tests/ui_specparity.spec.luau` compares
with the registry, so a game-registered preset passes in Luau but not in Python.

Builder plays the preset through `Visuals.UI.animate`, which honours reduced motion, and stops it
with its rest state restored when the screen closes or is destroyed. `Visuals/UI/UIAnimations` is
required lazily inside `pcall`: without the Visuals module the screen still builds and `motion` is
ignored (the schema then accepts any PascalCase id). Elements inside a list or grid layout only
show the scale and fade parts of a preset, because the layout owns their position.

Columns are whole numbers from 1 to 6, or one number for every breakpoint. Titles are at most 60
characters and subtitles 90 (readable at phone size). A screen holds at most 200 elements, nested at
most 5 deep. Interactive elements without an id get one from `withDefaults` (`auto_body_3_1`).

Examples of each:

```json
{ "type": "banner", "id": "starterPack", "palette": "teal", "icon": "star-color", "title": "STARTER PACK",
  "subtitle": "3 rare pets and 5,000 coins", "price": { "kind": "robux", "amount": 99, "productId": 0 },
  "badge": { "kind": "sale", "text": "-60%" }, "timer": 86400 }
{ "type": "product", "id": "tripleHatch", "palette": "purple", "icon": "egg-color", "title": "TRIPLE HATCH",
  "subtitle": "Open 3 eggs at once", "price": { "kind": "robux", "amount": 249, "gamePassId": 0 }, "gift": true }
{ "type": "grid", "columns": { "phone": 2, "tablet": 3, "desktop": 3 }, "items": [ ] }
{ "type": "row", "gap": "sm", "align": "left", "items": [ ] }
{ "type": "heading", "text": "GEM PACKS" }
{ "type": "divider" }
{ "type": "text", "text": "Log in every day for bigger rewards.", "size": "caption" }
{ "type": "button", "id": "open3", "text": "OPEN x3", "kind": "primary", "action": "Fire:Hatch,3" }
{ "type": "iconButton", "id": "shop", "icon": "shop-color", "label": "Shop", "palette": "orange",
  "action": "OpenPanel:Shop", "badge": { "kind": "new" } }
{ "type": "currency", "id": "cash", "icon": "cash-color", "bind": "Stats.Cash", "plus": true, "action": "OpenPanel:Shop" }
{ "type": "level", "id": "level", "bind": "Stats.Level", "max": 100 }
{ "type": "progress", "id": "storage", "value": 18, "max": 50, "palette": "blue" }
{ "type": "timer", "id": "eventTimer", "seconds": 1800, "format": "clock", "icon": "clock-color" }
{ "type": "toggle", "id": "showPets", "label": "Show other players' pets", "value": true, "bind": "Settings.ShowPets" }
{ "type": "slider", "id": "music", "label": "Music volume", "min": 0, "max": 1, "step": 0.05, "value": 0.6 }
{ "type": "dropdown", "id": "uiSize", "label": "Interface size", "options": ["Small", "Medium", "Large"], "value": "Medium" }
{ "type": "dayCard", "id": "day7", "day": 7, "reward": "Mythic Chest", "icon": "chest-color", "premium": true }
{ "type": "listRow", "id": "walkSpeed", "icon": "speed-color", "title": "WALK SPEED", "value": "Lv 4/10",
  "progress": { "value": 4, "max": 10 },
  "button": { "text": "UPGRADE", "kind": "buy", "price": { "kind": "currency", "amount": 1200, "currency": "coin-color" } } }
```

## Prices, badges, binds and actions

- **Price** `{ kind, amount, currency, productId, gamePassId }`:
  - `robux`: a whole `amount` of at least 1 and exactly one of `productId` or `gamePassId` (whole
    numbers; `0` is the placeholder). Shown as `R$ 99`. Pressing it fires
    `Intent("Purchase", { id, productId, gamePassId, amount })`. `Game/PurchaseBridge` prompts the
    purchase; the server grants it.
  - `currency`: a whole `amount` of at least 0 and a `currency` icon name. Fires
    `Intent("Buy", { id, itemId, amount, currency })`; the server validates and charges.
  - `free`: no amount or ids. Fires `Select`.
- **Badge** `{ kind, text? }`, text at most 12 characters (`"+50%"`, `"BEST"`).
- **bind** is an UrkUI Store path such as `Stats.Cash` (letters, digits and `_` between dots). The
  element follows it live: currency takes a number, level and progress a number or
  `{ level?, value?, max? }`, controls their value.
- **action** uses the UrkUI action syntax (`OpenPanel:Shop`, `Fire:Buy,starter;PlaySound:123`); the
  component runs it. Interactive elements without an action fire `Intent("Select", { id })`.
  Toggles, sliders and dropdowns fire `Intent("Change", { id, value })`.

## Validation

```lua
local SpecSchema = require(path.to.UI.Spec.SpecSchema)
local issues = SpecSchema.validate(spec)   -- {} when valid
for _, issue in issues do
	print(issue.path, issue.message)       -- body[3].items[1].price   robux prices need productId or gamePassId
end
print(SpecSchema.format(issues))          -- one "path: message" line per issue
local full = SpecSchema.withDefaults(spec) -- new table, input untouched
```

Paths use `body[3].items[1].price`, `rails.left[2].icon`, `window.title`, `popup.variant`, and `""`
for the spec itself. Messages are stable, short and specific, for example `unknown palette
chartreuse`, `duplicate id shop (first used at rails.left[1])`, `title is 61 characters; the limit
is 60`, `columns.phone must be a whole number from 1 to 6`, `invalid bind path Stats..Cash`,
`unknown rail middle`, `unknown element type carousel`.

`SpecSchema.ELEMENT_TYPES` (required, optional, interactive, container per type) and
`SpecSchema.RULES` (kinds, rails, enums, limits) are plain data, so `tools/ui/validate_spec.py` can
mirror them. Helpers: `isIcon`, `isId`, `isAction`, `isBindPath`, `resolveColumns`, `walk`.

## Building a screen

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local URK = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
local UrkUI = require(URK.UI.UrkUI)
local Builder = require(URK.UI.Spec.Builder)

UrkUI.start()
local shop = Builder.build(URK.UI.Spec.Screens.PetSimShop, { -- a ModuleScript or a table
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	store = UrkUI.store,
})
shop.Intent:Connect(function(name, args, elementId)
	if name == "Purchase" then
		-- hand to PurchaseBridge / MarketplaceService; the server grants in ProcessReceipt
	elseif name == "Buy" then
		-- send args.itemId to the server; it validates and charges
	end
end)
shop:open()
shop:update("starterPack", { timer = 3600 })
shop:find("tripleHatch") -- the ProductCard object
shop:close()
shop:destroy()
```

| Option | Default | Meaning |
|---|---|---|
| `parent` | PlayerGui | PlayerGui or a Folder gets a new ScreenGui; a GuiObject embeds the screen in it (previews) |
| `store` | none | UrkUI Store; `bind` elements observe it |
| `forwardTo` | none | A Signal such as `UrkUI.Intent` that also receives every intent |
| `writeBinds` | false | Controls also `store:set` their bind path (local settings) |
| `displayOrder` | hud 0, window 10, popup 50 | ScreenGui DisplayOrder |
| `startOpen` | true for hud | Open right after building |
| `style` | `spec.style` | Build with another style |
| `breakpoint` | detected | Force `phone`, `tablet`, `desktop` or `console` |

The screen object: `Instance`, `Intent` (Signal of `name, args, elementId`), `spec` (with
defaults), `root` (GameWindow or popup component), `open()`, `close()`, `destroy()`, `find(id)`,
`update(id, props)` (returns false for unknown ids) and `ids()`. Window screens also emit
`Intent("Close", { id })` when the window closes; confirm popups emit `Cancel`, and `Confirm` or the
price intent from the confirm button.

Layout rules: window size comes from `sizeClass` and the breakpoint (`Builder.windowSize`, phones
get almost the whole screen); grids pass their columns to the Grid component, which follows the
breakpoint; HUD rails sit in `Layout.safeRect` with 12 px padding inside a ScreenGui that uses
`CoreUISafeInsets`, anchored with `Layout.rail` (`top` and `bottom` map to Layout's `topCenter` and
`bottomCenter`).

## Turning a request into a spec (for AI agents)

1. **Pick the kind.** A menu, shop or list is a `window`; always-on screen furniture is a `hud`; a
   short reveal or a yes/no question is a `popup`.
2. **Start from the closest ready screen** in `Screens/` and keep its structure (banner, heading,
   grid, divider, footer). Copy, do not invent new element types or fields.
3. **List the content.** Every sellable thing becomes a `product` (or a `banner` when featured);
   every count or stat becomes `currency`, `level`, `progress` or a `listRow`.
4. **Choose palettes with meaning.** One palette per card, neighbours different, gold for premium or
   best value, green for buy, red for the window header unless the brand says otherwise.
5. **Choose `-color` icons** that name the thing (`egg-color` for eggs, `coins-color` for coin
   packs). Check names against `Icons.list()` or `assets/icons/urk/icons.json`.
6. **Price everything.** Robux prices get `productId` (consumables) or `gamePassId` (passes), `0`
   until the real id exists; currency prices name their currency icon.
7. **Write short copy.** Titles in capitals, at most 60 characters (aim for under 20); subtitles say
   what the player gets, at most 90.
8. **Give ids** to everything the game will read or update (`starterPack`, `tripleHatch`).
9. **Validate** with `SpecSchema.validate` (or `tools/ui/validate_spec.py`), fix every issue, then
   preview with `tools/ui/preview_spec.py` or the Studio playground.

Worked example. Request: *"Create a pet simulator shop with six products, colorful cards, Robux
buttons, and a featured starter pack."*

- Kind `window`, closest screen `PetSimShop`.
- Featured starter pack: a `banner` with a sale badge and a timer.
- Six products: two rows of three, so one `grid` with three desktop columns (two on phones), each
  card a different palette, all Robux-priced: three game passes and three gem packs.
- Robux buttons come from the robux prices (`R$ 249`).

```json
{
  "spec": 1,
  "id": "PetShopSix",
  "kind": "window",
  "style": "cartoon",
  "window": { "title": "PET SHOP", "headerPalette": "red", "sizeClass": "lg" },
  "body": [
    { "type": "banner", "id": "starterPack", "palette": "teal", "icon": "star-color", "title": "STARTER PACK",
      "subtitle": "3 rare pets, 5,000 coins and a lucky boost!",
      "price": { "kind": "robux", "amount": 99, "productId": 0 },
      "badge": { "kind": "sale", "text": "-60%" }, "timer": 86400 },
    { "type": "heading", "text": "BEST SELLERS" },
    { "type": "grid", "columns": { "phone": 2, "tablet": 3, "desktop": 3 }, "cellAspect": 1.3, "items": [
      { "type": "product", "id": "tripleHatch", "palette": "purple", "icon": "egg-color", "title": "TRIPLE HATCH",
        "subtitle": "Open 3 eggs at once", "price": { "kind": "robux", "amount": 249, "gamePassId": 0 } },
      { "type": "product", "id": "autoHatch", "palette": "blue", "icon": "refresh-color", "title": "AUTO HATCH",
        "subtitle": "Hatch while you relax", "price": { "kind": "robux", "amount": 149, "gamePassId": 0 } },
      { "type": "product", "id": "luckyPaw", "palette": "pink", "icon": "paw-color", "title": "LUCKY PAW",
        "subtitle": "x2 chance of rare pets", "price": { "kind": "robux", "amount": 199, "gamePassId": 0 },
        "badge": { "kind": "best" } },
      { "type": "product", "id": "gemPouch", "palette": "green", "icon": "gem-color", "title": "POUCH OF GEMS",
        "subtitle": "500 Gems", "price": { "kind": "robux", "amount": 49, "productId": 0 } },
      { "type": "product", "id": "gemChest", "palette": "orange", "icon": "chest-color", "title": "CHEST OF GEMS",
        "subtitle": "2,750 Gems", "price": { "kind": "robux", "amount": 249, "productId": 0 },
        "badge": { "kind": "bonus", "text": "+10%" } },
      { "type": "product", "id": "gemVault", "palette": "gold", "icon": "crown-color", "title": "VAULT OF GEMS",
        "subtitle": "12,000 Gems", "price": { "kind": "robux", "amount": 899, "productId": 0 },
        "badge": { "kind": "best", "text": "BEST" } }
    ] }
  ]
}
```

Then `SpecSchema.validate(spec)` returns `{}`, and `Builder.build(spec, { store = UrkUI.store })`
builds it. Hook `screen.Intent` for `Purchase` and replace the `0` ids before publishing.

## What is verified

| Part | Verified by |
|---|---|
| `SpecSchema.luau` | Lune specs `tests/ui_spec.spec.luau` (rules, paths, messages, defaults) and `tests/ui_spec_screens.spec.luau` (every screen validates, -color icons, required screens) |
| `SpecSchema.luau`, animated components, `motion`, pack icons, the ten Visuals styles | `tests/ui_spec_animated.spec.luau` |
| Luau and Python agree | `tests/ui_specparity.spec.luau` (shared fixtures, element tables, motion id list) and `tests/test_ui_specs.py` at the repository root |
| `Builder.luau` | Selene and StyLua in CI only. **Needs a Studio playtest** with the Game components |
| `Screens/*.json` | Validated by the Lune specs; how they look needs the Studio playground |

Builder codes against the component API in the contract (section 2). It has not been run in Studio
here. Things to check in a playtest: window sizes per breakpoint, HUD rails inside the safe area on
phones with a notch, grid cell sizes inside rails and rows, the day card and list row compositions,
store binds updating live, and the confirm popup's backdrop and buttons.

**Not verified in Studio:** the builders for the seventeen animated components, `motion` playback,
tooltips attached after the build, modals and loading screens parented to the screen root, and
pack icons. They pass StyLua, Selene and `luau-lsp` only and NEED MANUAL REVIEW in a playtest.

The HTML preview (`tools/ui/preview_spec.py`) draws a static approximation of every element type
in every style. Text on a surface uses that surface's text colour from the style, so the dark
styles (`midnight`, `scifi`, `arcade`, `luxury`, `adventure`) stay readable. It does not animate:
`motion` shows as a hover title, hidden elements are skipped, and a modal is drawn inline with a
dashed outline.
