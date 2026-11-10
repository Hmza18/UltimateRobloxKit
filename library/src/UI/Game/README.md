# UrkUI Game components

A game-style component kit on top of UrkUI: the bright simulator look with chunky outlined type,
thick dark outlines, gradient panels with a checker pattern and gloss, colour-coded product cards,
price pills, attention badges, a red-header shop window and animated counters. Everything is
original work drawn with plain Roblox UI objects; no images are required.

This folder implements sections 2 and 3 of
[ui-generation.md](../../../../docs/architecture/ui-generation.md). Styles come from
`design/tokens/styles.json` through the generated `Style/StyleTokens.luau` and the pure
`Style/Style.luau` resolver. Motion presets are data in `Core/MotionPresets.luau`, played by
`Runtime/Motion.play`. Text sizing uses `Core/TextFit.luau`.

## Contents

- [Quick start](#quick-start)
- [Shared shape and props](#shared-shape-and-props)
- [Visual anatomy](#visual-anatomy)
- [Component reference](#component-reference)
- [Animated components](#animated-components)
- [Prices and purchases](#prices-and-purchases)
- [Motion presets](#motion-presets)
- [Theming](#theming)
- [Interaction, controller and accessibility](#interaction-controller-and-accessibility)
- [Performance](#performance)
- [Testing and Studio checklist](#testing-and-studio-checklist)
- [Limitations](#limitations)

## Quick start

```lua
-- StarterPlayerScripts/Shop.client.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage.UltimateRobloxKit
local UrkUI = require(Kit.UI.UrkUI)
local Game = require(Kit.UI.Game.Game)

UrkUI.start() -- optional, but needed for `action` props and UrkUI.Intent
Game.PurchaseBridge.start(UrkUI.Intent) -- Robux prices open Roblox's purchase prompts

local shop = Game.GameWindow.new({ title = "SHOP", sizeClass = "lg", parent = Players.LocalPlayer.PlayerGui })
Game.PromoBanner.new({
	palette = "teal", icon = "star-color", title = "STARTER PACK", subtitle = "A great offer you can't refuse!",
	price = { kind = "robux", amount = 29, productId = 123456 }, badge = { kind = "best" }, timer = 3600,
	layoutOrder = 1, parent = shop.Content,
})
Game.Section.new({ title = "GAMEPASSES", layoutOrder = 2, parent = shop.Content })
local grid = Game.Grid.new({ columns = { phone = 2, tablet = 3, desktop = 4 }, layoutOrder = 3, parent = shop.Content })
grid:add(Game.ProductCard.new({
	name = "tripleHatch", palette = "purple", icon = "egg-color", title = "TRIPLE HATCH", subtitle = "+50% Bonus",
	price = { kind = "robux", amount = 599, gamePassId = 654321 }, badge = { kind = "attention" }, gift = true,
}))
shop:open()
```

Without `UrkUI.start()` the components still draw and animate; intents go to `Game.Intent`
instead of `UrkUI.Intent`, and `action` props are skipped with a warning.

## Shared shape and props

```lua
local card = ProductCard.new(props)  -- returns an object
card.Instance                        -- root GuiObject (parent it yourself, or pass props.parent)
card:update(partialProps)            -- merge props and redraw (cheap value changes skip the redraw)
card:destroy()                       -- Trove cleanup: connections, tweens, presets, ticker jobs, instances
card.Activated                       -- Signal(name) on interactive components
```

| Prop | Type | Meaning |
|---|---|---|
| `style` | string? | Style name from styles.json; default `Style.default()` (`cartoon`) |
| `parent` | Instance? | Parent for the root. GameWindow and RewardPopup wrap a PlayerGui parent in their own ScreenGui |
| `layoutOrder` | number? | LayoutOrder of the root |
| `size` | UDim2? | Root size (GameText: a string `size` is the text role) |
| `position` | UDim2? | Root position |
| `anchor` | Vector2? | Root AnchorPoint |
| `name` | string? | Instance name; also the `itemId` in purchase intents |
| `action` | string? | UrkUI action spec run on activation, such as `OpenPanel:Shop` or `Fire:Buy,starter` |
| `visible` | boolean? | Root visibility (GameWindow starts hidden unless true) |

`update` keeps whatever you parented into `object.Content` (Panel, GameWindow, Grid). Children the
component made itself are marked with the `UrkInternal` attribute and rebuilt.

## Visual anatomy

```
root (transparent; TextButton for interactive components)
├── Shadow       dark rounded copy, offset down by shadow.offsetY, shadow.transparency   ZIndex 0
└── Body         white frame tinted by a vertical UIGradient (palette top -> bottom)        ZIndex 1
    ├── UICorner   radius token
    ├── UIStroke   outline colour, Border mode, round joins, outline weight
    ├── Pattern    checker overlay (two crossed stripe gradients, or a tiled image)        ZIndex 1
    ├── Gloss      white rounded highlight on the top 45 %, fading to transparent          ZIndex 2
    ├── Shine      optional sweeping streak (CartoonButton shine = true)                  ZIndex 2
    └── Content    the component's icons and text                                          ZIndex 3
```

Text is a TextLabel with the style's title, body or number font, a contextual UIStroke outline
(`textStroke.thickness`, thinner for label and caption) and a UITextSizeConstraint.

**Checker pattern.** The default needs no image: two overlay frames carry hard-edged
UIGradient transparency stripes at +45 and -45 degrees, and where they cross they form the diamond
checker. That is two instances per panel and no per-frame work. A NumberSequence holds at most 20
points, so a panel shows at most 10 stripe segments: the cell is `pattern.cell` (24 px) on cards
and grows on large windows. The stripe count is recomputed only when the panel's 1x size changes.
For an exact cell everywhere, set `pattern.image` (or `patternImage`) in the style or the Panel
props: one ImageLabel then tiles it with `ScaleType.Tile`. A grid of 64 frames per panel was
rejected as too heavy for a shop with dozens of cards.

## Component reference

### GameText

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `text` | string | `""` | The text |
| `size` | `"display"`, `"title"`, `"heading"`, `"label"`, `"caption"`, `"price"` | `"label"` | Text role (font family and maximum size). A UDim2 sets the frame size instead; then use `role` |
| `color` | hex | `#FFFFFF` | Text colour |
| `stroke` | boolean | true | Outline |
| `align` | `"left"`, `"center"`, `"right"` | center | Horizontal alignment |
| `minSize`, `maxSize` | number | floor, role size | Fit bounds; never below the style minimum (or UrkUI's minimum text size) |
| `wrap` | boolean | false | Allow several lines (extra prop) |

`GameText.decorate(label, style, options, trove)` styles any existing TextLabel the same way.

### Panel

| Prop | Default | Meaning |
|---|---|---|
| `palette` / `surface` | blue | Palette name, or `window`, `inset`, `dark` |
| `radius` | `lg` | Radius token (`sm`, `md`, `lg`, `xl`, `pill`) |
| `outline` | `thick` | Outline weight (`thin`, `regular`, `thick`, `heavy`) |
| `gloss` | true for palettes | Top highlight |
| `pattern` | false | Checker overlay |
| `shadow` | true | Drop shadow |
| `padding` | none | Spacing token for `panel.Content` |
| `patternImage` | style | Tiled pattern image (extra prop) |

Fields: `panel.Content`, `panel.Body`.

### CartoonButton

| Prop | Default | Meaning |
|---|---|---|
| `kind` | `primary` | `buy`, `robux`, `gift`, `close`, `primary`, `danger`, `neutral`, `price` (palette, surface and icon from the style) |
| `palette` | from kind | Overrides the kind's colour |
| `text` | | Label |
| `icon` | from kind | Icon name |
| `iconSide` | `left` | `left` or `right` |
| `price` | | Price; the label becomes `R$ 599`, `1.2K` with the currency icon, or `FREE` |
| `enabled` | true | false greys the palette and ignores input |
| `shine` | false | Looping shine sweep |
| `robuxImage` | style | Robux artwork shown before the number (extra prop) |

### IconButton

| Prop | Default | Meaning |
|---|---|---|
| `icon` / `image` | | Icon name or asset id |
| `palette` | blue | Colour |
| `label` | | Outlined caption under the icon |
| `badge` | | `{ kind, text? }` corner badge |
| `shape` | `square` | `square` or `circle` |

Size: `sizes.hudButton.size` (64) unless `size` is given.

### Badge

| Prop | Default | Meaning |
|---|---|---|
| `kind` | `new` | `sale`, `bonus`, `attention` (red circle "!"), `new`, `best` (tilted ribbon) |
| `text` | style text or the kind in capitals | Badge text, such as `+50%` |
| `corner` | `topRight` | `topRight` or `topLeft` of the parent |
| `pulse` | true for attention | Loops the `attention` preset |

### ProductCard

| Prop | Default | Meaning |
|---|---|---|
| `palette` | blue | Card colour (purple, blue, orange, yellow, teal ...) |
| `title`, `subtitle` | | Outlined title; yellow subtitle such as `+50% Bonus` |
| `icon` / `image` | | Big icon name or asset id |
| `price` | | Price tag at the bottom (right on `wide`) |
| `badge` | | `{ kind, text? }` |
| `gift` | false | Purple gift button (fires the `Gift` intent) |
| `rarity` | | Heavy outline in the rarity colour; `secret` cycles a rainbow |
| `owned` | false | Price tag shows `OWNED`; activation fires no purchase |
| `layout` | `tall` | `tall` (sizes.card) or `wide` |

### PromoBanner

| Prop | Default | Meaning |
|---|---|---|
| `palette` | teal | Banner colour |
| `title`, `subtitle` | | Display title and subtitle |
| `icon` / `image` | | Big icon on the left |
| `price` | | Price tag on the right |
| `badge` | | Corner badge |
| `timer` | | Seconds left; shows an `Ends in 1:02:03` countdown |

Full width by default, `sizes.banner.height` (110) tall.

### GameWindow

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Outlined header title |
| `headerPalette` | red | Header colour |
| `sizeClass` | `md` | `sm` 420x320, `md` 560x420, `lg` 760x520, `full` 94 % x 90 % |
| `width`, `height` | | Pixels at 1x, override the size class |
| `closable` | true | Red X button; it closes the window and runs `action` |
| `scroll` | true | Content is a ScrollingFrame (AutomaticCanvasSize Y) |

`window.Content` holds children (vertical UIListLayout by LayoutOrder, padding `lg`).
`window:open()` / `window:close()` play `open` / `close`; `window:isOpen()`; `window.Opened` and
`window.Closed` are Signals. With a gamepad, opening selects the first button inside.

### Section

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Heading text |
| `divider` | true | Thick rounded divider line under it |
| `align`, `color` | left, white | Title alignment and colour |

### Grid

| Prop | Default | Meaning |
|---|---|---|
| `columns` | `{ phone = 2, tablet = 3, desktop = 4 }` | Columns per breakpoint; console falls back to desktop |
| `cellAspect` | 1 | Cell width / height |
| `gap` | `md` | Spacing token |

`grid:add(component or instance)`. `Grid.columnsFor(columns, breakpoint)` is the rule.

### CurrencyCounter

| Prop | Default | Meaning |
|---|---|---|
| `icon` / `image` | | Currency icon overlapping the left end |
| `value` | 0 | Amount; `update({ value })` counts up with the `count` preset |
| `format` | `abbrev` | Core/Format spec |
| `palette` | dark surface | Pill colour |
| `plus` | false | Green `+` button that fires Activated and runs `action` |

### LevelBar

| Prop | Default | Meaning |
|---|---|---|
| `level` | 0 | Shown as `Lvl. 3` |
| `value`, `max` | 0, 1 | Bar fill and `40/100` text |
| `palette` | green | Fill colour |
| `prefix` | `Lvl. ` | Label prefix (extra prop) |

### ProgressBar

| Prop | Default | Meaning |
|---|---|---|
| `value`, `max` | 0, 1 | Fill ratio; `update({ value })` tweens the fill and plays `progress` |
| `palette` | green | Fill colour |
| `showText` | false | `value/max` over the bar |
| `segments` | 0 | Divider lines |

### Timer

| Prop | Default | Meaning |
|---|---|---|
| `seconds` | 0 | Seconds left; `update({ seconds })` restarts |
| `format` | `clock` | `clock` (`1:02:03`) or `short` (`1h 2m`) |
| `icon` | | Clock icon |
| `onDone` | | Called once at zero; `timer.Done` Signal fires too |
| `prefix`, `background` | `""`, true | Text before the time; false draws text only (extra props) |

`timer:remaining()` returns the seconds left.

### Toggle, Slider, Dropdown

| Component | Props | Signals and methods |
|---|---|---|
| `Toggle` | `value`, `onChanged(boolean)`, `onPalette` (green), `enabled` | `Changed`, `set(value, silent?)` |
| `Slider` | `value`, `min` (0), `max` (1), `step` ((max - min) / 100), `onChanged(number)`, `palette`, `enabled` | `Changed`, `set(value, silent?)`; `Slider.snap(value, min, max, step)` |
| `Dropdown` | `options`, `value`, `onChanged(string)`, `palette`, `enabled` | `Changed`, `close()` |

### RarityFrame

| Prop | Default | Meaning |
|---|---|---|
| `rarity` | common | `common` ... `secret`; secret cycles a rainbow |
| `radius`, `outline` | `lg`, `heavy` | Shape of the overlay outline |

`RarityFrame.attach(stroke, style, rarity)` recolours an existing UIStroke and returns a stop
function (ProductCard uses it).

### RewardPopup

| Prop | Default | Meaning |
|---|---|---|
| `title`, `icon` / `image`, `amount` | | Reveal content |
| `palette` | gold | Card colour |
| `rays` | true | Turning light rays behind the card |
| `duration` | 2.5 | Seconds before it closes itself; 0 keeps it open (extra prop) |
| `destroyOnClose` | true | Destroy after closing (extra prop) |

It opens on creation with the `reveal` preset unless `visible = false`; clicking closes it early.
`popup:open()`, `popup:close()`, `popup.Closed`.

## Animated components

These seventeen components follow the same contract as the ones above (`Component.new(props)`,
`.Instance`, `:update(partial)`, `:destroy()`, `Activated` on interactive ones, style tokens,
`enabled`, gamepad selection) and take their motion from `Visuals/UI`
([Visuals/UI/README.md](../../Visuals/UI/README.md)) instead of `Core/MotionPresets`, so they
move with the same presets as `Visuals.UI.animate`. Interactive roots are wired by
`Game/Extra.wire`: the kit's selection outline, hover and click sounds, `Activated`, and a
`Visuals.UI.bind` button style for hover, press, release and selected. Their animation follows
the visuals kit's settings (`Visuals.Configure({ reducedMotion, reducedFlashing, intensity, quality })`),
not `UrkUI.setReducedMotion`.

| Component | Root | Interactive | Motion used |
|---|---|---|---|
| PremiumButton | TextButton | yes | `Premium` style, looping shine, `Glow` |
| TabBar | Frame | tabs are buttons | `IndicatorSlide`, `TextBounce`, `Snappy` style |
| Modal | Frame | buttons, backdrop | `ModalIn` / `ModalOut`, `BackdropIn` / `BackdropOut` |
| Tooltip | CanvasGroup | no | `PopIn`, `FadeOut` |
| XPBar | Frame | no | fill tween, `Highlight`, `UpgradePulse` |
| InventorySlot | TextButton | yes | `Snappy` style, `Selected`, `Error` (locked) |
| PetCard | TextButton | yes | `Soft` style, `Selected` |
| RarityBadge | Frame | no | looping shine, rainbow outline |
| RewardPanel | Frame | claim button | staggered `BadgePop`, `PopIn` |
| QuestCard | Frame | claim button | `Pulse`, `UpgradePulse` |
| AchievementCard | Frame | no | `UpgradePulse`, staggered `BadgePop` |
| Notification | CanvasGroup | click to dismiss | `ToastIn` / `ToastOut`, timer bar tween |
| LeaderboardRow | Frame | no | `countTo` |
| LoadingScreen | CanvasGroup | no | `Pulse`, `FadeOut` / `FadeIn` tips, `FadeOut` |
| SelectionCard | TextButton | yes | `Soft` style, `Selected`, `BadgePop` / `ScaleOut` tick |
| HotbarSlot | TextButton | yes | `Snappy` style, `UpgradePulse` when ready |
| StatChip | Frame | no | `countTo`, `TextBounce`, `BouncyPress` |

ShopCard is covered by ProductCard.

### PremiumButton

| Prop | Default | Meaning |
|---|---|---|
| `text` | | Label |
| `icon` / `image` | | Icon on the left |
| `palette` | `gold` | Colour |
| `enabled` | true | false greys it, stops shine and glow, ignores input |
| `shine` | true | Looping shine sweep |
| `shineInterval` | 2.6 | Seconds between sweeps |
| `glow` | true | Breathing outline glow |
| `radius` | `lg` | Radius token |

```lua
local claim = Game.PremiumButton.new({ text = "CLAIM REWARD", icon = "gift-color", parent = panel })
claim.Activated:Connect(function() Net.fire("Claim") end)
```

Default size 220 x 64.

### TabBar

| Prop | Default | Meaning |
|---|---|---|
| `tabs` | | List of `{ id, text?, icon?, image? }` or plain strings |
| `value` | first tab | Active tab id; `update({ value })` moves the indicator without a rebuild |
| `palette` | `blue` | Indicator colour |
| `enabled` | true | |
| `onChanged` | | `function(id)` |

`tabs.Changed` (Signal, id) and `Activated` fire when the player picks another tab.
`tabs:select(id, silent?)`, `tabs:value()`. Pure helpers: `TabBar.normalize(tabs)`,
`TabBar.indexOf(tabs, id)`.

```lua
local tabs = Game.TabBar.new({ tabs = { { id = "pets", text = "PETS" }, { id = "eggs", text = "EGGS" } }, parent = shop.Content })
tabs.Changed:Connect(function(id) showPage(id) end)
```

Default size full width x 52.

### Modal

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Header title |
| `text` | | Body text (wrapped) |
| `buttons` | | List of `{ id, text?, kind?, icon?, keepOpen? }`; `kind` is a CartoonButton kind |
| `headerPalette` | `blue` | Header colour |
| `width`, `height` | 440, 280 | Window size at 1x |
| `closable` | true | X button, Escape and gamepad B close it |
| `closeOnBackdrop` | true | A click on the dim layer closes it |
| `dim` | 0.45 | Backdrop transparency |

`modal:open()`, `modal:close()`, `modal:isOpen()`; Signals `Opened`, `Closed`; `Activated` fires
with the pressed button's id (the modal then closes unless `keepOpen`). Starts hidden unless
`visible = true`. A PlayerGui parent gets a ScreenGui of its own (DisplayOrder 40). Custom
children go in `modal.Content`. With a gamepad, opening selects the first button.

```lua
local confirm = Game.Modal.new({ title = "REBIRTH?", text = "You keep your pets and lose your coins.",
	buttons = { { id = "yes", text = "REBIRTH", kind = "buy" }, { id = "no", text = "CANCEL", kind = "neutral" } },
	parent = playerGui })
confirm.Activated:Connect(function(id) if id == "yes" then Net.fire("Rebirth") end end)
confirm:open()
```

### Tooltip

| Prop | Default | Meaning |
|---|---|---|
| `text` | | Tooltip text (nothing shows when empty) |
| `target` | | GuiObject it describes |
| `side` | `top` | `top`, `bottom`, `left`, `right` |
| `delay` | 0.4 | Seconds of hover or selection before it shows |
| `maxWidth` | 240 | Pixels at 1x before the text wraps |
| `gap` | 8 | Pixels between target and bubble |
| `parent` | target's ScreenGui | Where the bubble lives |

Shows on MouseEnter and SelectionGained, hides on leave; follows the target every frame while
shown and stays on screen. `tooltip:show()`, `tooltip:hide()`. Pure helpers:
`Tooltip.measure(text, textSize, maxWidth)`, `Tooltip.place(side, targetPosition, targetSize, size, gap)`.

```lua
Game.Tooltip.new({ target = boost.Instance, text = "Doubles coins for 10 minutes", side = "bottom" })
```

### XPBar

| Prop | Default | Meaning |
|---|---|---|
| `level` | 1 | Number in the badge |
| `value`, `max` | 0, 1 | Fill and `40/100` text |
| `palette` | `blue` | Fill colour |
| `badgePalette` | `gold` | Level badge colour |
| `showText` | true | `value/max` over the bar |
| `maxForLevel` | | `function(level) -> number`: bar size per level |

`bar:gain(amount)` plays the gain and handles overflow: fill to the end, badge pulse,
`bar.LevelUp:Fire(level)`, reset, continue, across as many levels as the gain covers
(`UILogic.xpPlan`). `update({ value, max, level })` sets the state directly with a tween.

```lua
local xp = Game.XPBar.new({ level = 3, value = 40, max = 100, parent = hud })
xp:gain(250)
```

Default size 320 x 44.

### InventorySlot

| Prop | Default | Meaning |
|---|---|---|
| `icon` / `image` | | Item icon; none draws an empty slot |
| `count` | | Stack count, shown as `x12` above 1 |
| `rarity` | | Outline in the rarity colour (`secret` cycles a rainbow) |
| `selected` | false | Raised with a glowing outline; `update({ selected })` animates without a rebuild |
| `equipped` | false | Green tick in the corner |
| `locked` | false | Dimmed with a padlock; a press shakes and does not fire Activated |
| `enabled` | true | |

```lua
local slot = Game.InventorySlot.new({ name = "sword_3", icon = "sword-color", count = 12, rarity = "rare" })
slot.Activated:Connect(function(id) select(id) end)
```

Default size 72 x 72. `InventorySlot.countText(count)` is the stack text rule.

### PetCard

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Pet name |
| `rarity` | | Outline colour and a RarityBadge |
| `icon` / `image` | | Portrait; or parent an ImageLabel / ViewportFrame to `card.Content` |
| `stats` | | Up to three `{ icon?, image?, text }` chips |
| `palette` | `blue` | Card colour |
| `selected` | false | Glowing outline, raised; animates without a rebuild |
| `equipped` | false | Green tick |
| `enabled` | true | |

```lua
local card = Game.PetCard.new({ name = "pet_42", title = "Ember Fox", rarity = "epic", image = "rbxassetid://1",
	stats = { { icon = "coin-color", text = "x2.5" } }, equipped = true })
```

Default size 156 x 208.

### RarityBadge

| Prop | Default | Meaning |
|---|---|---|
| `rarity` | `common` | Colour from the style's rarity table |
| `text` | rarity in capitals | Badge text |
| `shimmer` | true for legendary, mythic, secret | Looping shine (every 3.2, 2.4, 1.8 s) |

```lua
Game.RarityBadge.new({ rarity = "legendary", parent = card.Instance })
```

### RewardPanel

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Panel title |
| `rewards` | | List of `{ icon?, image?, amount?, rarity? }` |
| `columns` | up to 4 | Tiles per row |
| `claimText` | `CLAIM` | Button text |
| `claimed` | false | Button reads `CLAIMED` and is disabled |
| `revealed` | true | false hides tiles and button until `panel:reveal()` |
| `palette` | window surface | Panel colour |

`panel:reveal()` pops the tiles in from the centre out, then the claim button. Pressing the
button fires `panel.Claimed` and `Activated` once and sets `claimed`. The panel grants nothing.

```lua
local panel = Game.RewardPanel.new({ title = "DAILY REWARDS", revealed = false, parent = gui,
	rewards = { { icon = "coin-color", amount = "x500" }, { icon = "gift-color", amount = "x1", rarity = "rare" } } })
panel.Claimed:Connect(function() Net.fire("ClaimDaily") end)
panel:reveal()
```

Default size 420 x 300.

### QuestCard

| Prop | Default | Meaning |
|---|---|---|
| `title`, `description` | | Texts |
| `value`, `max` | 0, 1 | Progress bar |
| `rewards` | | Up to three `{ icon?, image?, text }` chips |
| `state` | from value / max | `active`, `claimable`, `claimed` |
| `claimText` | `CLAIM` | Button text |
| `palette` | `green` | Progress colour |

The button is enabled and breathing only when claimable; pressing it fires `quest.Claimed(name)`
and `Activated`. Set `state = "claimed"` after the server confirms. Becoming claimable flashes
the card once.

```lua
local quest = Game.QuestCard.new({ name = "hatch10", title = "EGG COLLECTOR", description = "Hatch 10 eggs",
	value = 4, max = 10, rewards = { { icon = "coin-color", text = "500" } } })
quest:update({ value = 10 })
```

Default size full width x 104.

### AchievementCard

| Prop | Default | Meaning |
|---|---|---|
| `title`, `description` | | Texts |
| `icon` / `image` | | Shown in a round badge |
| `tier`, `maxTier` | 0, 3 | Stars earned and shown (up to 5; 0 hides them) |
| `value`, `max` | | Progress bar (none without `max`) |
| `unlocked` | `tier > 0` | Locked cards are dimmed |
| `palette` | `gold` | Badge colour when unlocked |

Updating to `unlocked = true` or a higher `tier` flashes the card with a shine and pops the new
stars in.

```lua
local card = Game.AchievementCard.new({ title = "COLLECTOR", description = "Own 50 pets", icon = "trophy", value = 20, max = 50 })
card:update({ tier = 1, unlocked = true, value = 50 })
```

Default size full width x 96.

### Notification

| Prop | Default | Meaning |
|---|---|---|
| `kind` | `info` | `info`, `success`, `warning`, `error`: accent colour |
| `title`, `text` | | Texts |
| `icon` / `image` | `!` | Icon in the accent badge |
| `palette` | from kind | Accent override |
| `duration` | 4 | Seconds before it dismisses itself; 0 keeps it |
| `destroyOnClose` | true | Destroy after closing |

Shows on creation unless `visible = false` (`toast:show()`). `toast:dismiss()`; a click dismisses
and fires `Activated`. `toast.Closed(name)` fires after the exit. Stacking is the caller's job
(a UIListLayout, or positions from `Core/ToastQueue`).

```lua
Game.Notification.new({ kind = "success", title = "QUEST COMPLETE", text = "+500 coins", parent = toastStack })
```

Default size 320 x 84 (includes an 8 px margin the CanvasGroup needs for the outline and shadow).

### LeaderboardRow

| Prop | Default | Meaning |
|---|---|---|
| `rank` | | 1-3 get a gold, silver or bronze medal |
| `title` | | Player name |
| `value` | 0 | `update({ value })` rolls the number |
| `format` | `abbrev` | Core/Format spec |
| `avatar` | | Image id or content string; or parent an image to `row.Content` |
| `highlight` | false | The local player's row |

```lua
Game.LeaderboardRow.new({ rank = 1, title = "Builderman", value = 1250000, layoutOrder = 1, parent = list })
```

Default size full width x 52.

### LoadingScreen

| Prop | Default | Meaning |
|---|---|---|
| `title` | | Game title |
| `logo` / `icon` | | Logo image, or parent your own to `loading.Content` |
| `tips` | | Strings shown in turn |
| `tipInterval` | 4 | Seconds per tip |
| `progress` | 0 | 0..1; `loading:setProgress(ratio)` |
| `palette` | `green` | Bar colour |
| `background` | `dark` | Surface used for the backdrop gradient |
| `destroyOnClose` | true | |

`loading:finish()` fills the bar, fades out, fires `loading.Closed` and destroys. A PlayerGui
parent gets a ScreenGui (DisplayOrder 100, IgnoreGuiInset).

```lua
local loading = Game.LoadingScreen.new({ title = "PET WORLD", tips = { "Hatch eggs to find rare pets" }, parent = playerGui })
loading:setProgress(0.5)
loading:finish()
```

### SelectionCard

| Prop | Default | Meaning |
|---|---|---|
| `title`, `description` | | Texts |
| `icon` / `image` | | Preview; or parent your own to `card.Content` |
| `palette` | `blue` | Card colour |
| `selected` | false | Tick, glow and raised pose; animates without a rebuild |
| `enabled` | true | |

The card does not select itself: the screen listens to `Activated` and calls
`update({ selected })`, which makes single and multi select the screen's choice.

```lua
local card = Game.SelectionCard.new({ name = "ranger", title = "RANGER", description = "Fast and fragile", icon = "bolt" })
card.Activated:Connect(function(id) pick(id) end)
```

Default size 220 x 280.

### HotbarSlot

| Prop | Default | Meaning |
|---|---|---|
| `icon` / `image` | | Ability icon |
| `keybind` | | Short label (`Q`, `1`, `RT`) |
| `palette` | dark surface | Slot colour |
| `enabled` | true | |
| `readyPulse` | true | Flash and bounce when the cooldown ends |

`slot:startCooldown(seconds)` counts down on the shared clock; `slot:setCooldown(remaining, duration?)`
shows a time value you drive; `slot:clearCooldown()`; `slot:isReady()`; `slot.Ready(name)` fires
when a cooldown ends. `Activated` fires during a cooldown too. The sweep is vertical; a radial
sweep is not implemented.

```lua
local dash = Game.HotbarSlot.new({ name = "dash", icon = "bolt", keybind = "Q", parent = hotbar })
dash.Activated:Connect(function() if dash:isReady() then Net.fire("Dash") end end)
dash:startCooldown(8)
```

Default size 64 x 64.

### StatChip

| Prop | Default | Meaning |
|---|---|---|
| `icon` / `image` | | Icon on the left |
| `value` | | Number (formatted, rolls on change) or string |
| `format` | `abbrev` | Core/Format spec for numbers |
| `prefix`, `suffix` | | Around the value |
| `palette` | dark surface | Chip colour |

```lua
local luck = Game.StatChip.new({ icon = "star-color", value = 120, suffix = "%" })
luck:update({ value = 135 })
```

Default size 120 x 36.

### Notes for the animated components

- **Not verified in Studio.** These files pass StyLua, Selene and `luau-lsp` only. Layout
  fractions, text fitting and every animation NEED MANUAL REVIEW in Studio.
- Sizes are 1x pixels. Several layouts read the root's offset height at build time, so give
  these components offset-based sizes (the defaults are) rather than scale-based heights.
- Fades need a CanvasGroup. Tooltip, Notification and LoadingScreen are CanvasGroups; Modal's
  window and the cards are frames, so their entrances show scale and travel without a fade.
- Motion inside UIListLayout / UIGridLayout is scale only (layouts own Position).
- The selected glow is an outline frame (`UvkGlow`) around the root; it is white unless a
  colour is passed to the binding.
- Interactive touch targets default to 44 px or more; do not size them below that.

## Prices and purchases

`Price` is `{ kind = "robux" | "currency" | "free", amount?, currency? (icon name), productId?, gamePassId? }`.

| Price | Shows | Activation fires |
|---|---|---|
| robux | green pill `R$ 599` (or `robuxImage` + `599`) | `Intent("Purchase", { productId or gamePassId, itemId })` |
| currency | dark pill with the currency icon and `1.2K` | `Intent("Buy", { itemId, currency, amount })` |
| free | green pill `FREE` | nothing (Activated only) |

The components never grant anything and do not fire `Select`; when an element has no action
and no price, the spec Builder decides what to fire from `Activated`. When `action` is set it runs
instead of the price intent. The gift button fires `Intent("Gift", { itemId, productId, gamePassId })`.

`Game/PurchaseBridge.luau` (client) turns `Purchase` intents into prompts:

```lua
local stop = PurchaseBridge.start(UrkUI.Intent, { cooldown = 1, onPrompt = function(request) end })
```

It accepts `{ productId }`, `{ gamePassId }` or the Fire action's list form
(`Fire:Purchase,123` and `Fire:Purchase,123,pass`), ignores invalid ids (0, the placeholder in the
example specs, only warns), wraps `MarketplaceService:PromptProductPurchase` and
`PromptGamePassPurchase` in pcall and ignores a repeat for the same id within the cooldown.
Granting happens only on the server: `Systems/Shop` (`ProcessReceipt` for products, ownership
checks for passes); currency purchases are validated and charged by the server.

The kit ships no Robux logo. To show the official icon, pass `robuxImage` in the style or the
component props and follow Roblox's brand guidelines.

## Motion presets

`Core/MotionPresets.luau` (pure) holds 20 presets as data:

| Preset | Use | Preset | Use |
|---|---|---|---|
| `hover` / `unhover` | pointer and gamepad selection | `count` | counter pop and count-up timing |
| `press` / `release` | button press | `acquire`, `purchase` | item gained, purchase feedback |
| `select`, `tabSwitch` | selection, tab change | `toastIn`, `toastOut` | toasts |
| `open` / `close` | windows | `progress` | bar pulse |
| `popIn`, `bounce` | appear | `attention` (loop) | "!" badges |
| `reveal` | reward popup | `wiggle` (loop), `shine` (loop) | gift wiggle, shine sweep |

Each preset is `{ duration, easing, keys = { { t, scale?, rotation?, offsetY?, transparency? } }, loop? }`.
A property interpolates between the previous and next key that set it, eased with an
`Core/Easing` curve. `MotionPresets.sample(preset, t)` returns `{ scale, rotation, offsetY,
transparency }`; `from(preset, current)` restarts a preset from the current values;
`validate(preset)` lists problems.

`Runtime/Motion.play(instance, presetName, { onDone?, fromCurrent?, speed?, loop? })` plays one on
the shared frame driver and returns a stop function. On a GuiObject, scale drives its `UrkScale`
UIScale, rotation and offsetY are relative to the resting values, and transparency drives
`GroupTransparency` on a CanvasGroup (ignored on other objects). On a UIGradient, offsetY drives
`Offset.X` (the `shine` sweep from -1 to 1). Starting a preset stops the previous one on the same
instance. `Motion.stop(instance)`, `Motion.isPlaying(instance)` and `Motion.cancel(instance)`
(stop a `Motion.tween`) are the helpers.

## Theming

Styles live in `design/tokens/styles.json`. `tools/ui/build_tokens.py` generates
`Style/StyleTokens.luau`, which the components read through `Style/Style.luau`, so a new look is
a JSON change, never a component change:

- `palette` and `surfaces`: `{ top, bottom, text }` hex per name (gradient top and bottom, text colour).
- `outline`: colour and the `thin` / `regular` / `thick` / `heavy` widths in pixels.
- `fonts`: `title`, `body`, `number` family names and a `fallback`; the components try
  `Enum.Font.<name>`, then `Font.fromName`, then the fallback, then GothamBlack.
- `text`: role sizes and `minimum`; `textStroke`: text outline colour and thickness.
- `radius`, `spacing`, `shadow`, `gloss`, `pattern` (`cell`, `transparency`, optional `image`),
  `sizes` (card, banner, hudButton, icon), `buttons`, `badges`, `rarity`, `motion`.
- Optional `robuxImage` and `patternImage` asset ids.

Pick a style per component with `style = "midnight"` or for everything with
`Style.setDefault("midnight")`. Token sizes are 1x pixels; UrkUI's responsive UIScale (or your own
UIScale) scales them.

## Interaction, controller and accessibility

- Interactive roots are TextButtons with `Selectable = true` and a styled `SelectionImageObject`
  (heavy white rounded outline). Hover and gamepad selection play `hover` / `unhover`; mouse,
  touch and gamepad A play `press` / `release`, blended from the current scale.
- Disabled components (`enabled = false`) use the gray palette and ignore input.
- Hover and click sounds come from `UrkUI.start({ sounds = { hover, click } })` when set.
- Reduced motion (`UrkUI.setReducedMotion` or the Roblox setting): one-shot presets jump to their
  last key, looping presets (attention, wiggle, shine) do not start, count-ups and tweens are
  instant, the rainbow and the reward rays stand still.
- Text never goes below the style's `text.minimum`, raised to UrkUI's `minTextSize` when running.
- Grid columns follow the breakpoint; GameText refits on size changes.

## Performance

- No per-frame work while idle. `Runtime/Driver` runs one RenderStepped connection only while an
  animation, count-up, countdown or rainbow is active. Timers, count-ups and the rainbow share one
  `Game/Ticker` job; countdowns update about four times a second.
- Looping presets skip frames while their object is hidden; the rainbow skips hidden frames.
- Tweens, presets and ticker jobs are stopped on `destroy` (Trove), and a preset job ends by itself
  when its instance leaves the tree.
- TextFit runs only when a label's 1x size changes (not every frame of a hover scale).
- A card is about 25 instances: root, shadow, body, gradient, stroke, two pattern layers, gloss,
  content, icon, two or three labels with strokes and constraints, and the price pill.

## Testing and Studio checklist

| Part | Verified by |
|---|---|
| `Core/MotionPresets.luau`, `Core/TextFit.luau`, `Style/Style.luau` | Lune specs `tests/ui_motionpresets`, `ui_textfit`, `ui_gamestyle`; `luau-analyze --mode=strict` in CI |
| `Game/*`, `Runtime/Motion.play` | Selene and StyLua in CI only. **Needs a Studio playtest** |
| Animated components (PremiumButton ... StatChip), `Game/Extra.luau` | Selene, StyLua and `luau-lsp` only; their pure maths lives in `Visuals/UI/UILogic` (spec `tests/visuals_ui`). **Needs a Studio playtest** |

Check in Studio (NEEDS MANUAL REVIEW until done):

- [ ] Gradients run light top to dark bottom; the body UIStroke is not tinted by the UIGradient.
- [ ] Crossed stripe gradients read as a subtle checker on cards, banners and the window.
- [ ] Gloss, shine sweep and shadow sit inside the rounded corners; badges overlap card corners.
- [ ] `FredokaOne` / `LuckiestGuy` load (Enum.Font path) and the text outline is chunky.
- [ ] TextFit + UITextSizeConstraint: long titles shrink, then truncate at the minimum size.
- [ ] Hover / press / release feel, gamepad selection outline, touch on a phone.
- [ ] Slider drag with mouse and touch; D-pad left and right while selected.
- [ ] Dropdown list above neighbours; clipping inside a scrolling window.
- [ ] GameWindow open / close animation, close button, scroll, gamepad selection on open.
- [ ] CurrencyCounter count-up, Timer countdown and onDone, secret rainbow, reward rays.
- [ ] Reduced motion: loops off, one-shots instant.
- [ ] Grid columns at phone, tablet, desktop and console breakpoints.
- [ ] PurchaseBridge prompts in a Studio test server with real product and pass ids.

## Limitations

- Client only. Components work without `UrkUI.start()`, but actions need it.
- The default checker has at most 10 stripe segments per panel, so cells grow on big windows;
  use `pattern.image` for exact cells.
- `transparency` keys only affect CanvasGroups; windows and cards use scale and offset only.
- `offsetY` keys move `Position`, which UIListLayout and UIGridLayout control: inside layouts only
  scale and rotation presets have a visible effect.
- The Dropdown list is a child of the dropdown, so a clipping ScrollingFrame clips it.
- Metrics in TextFit are approximations; the engine's TextScaled does the exact fit.
- The kit ships no Robux logo and no sounds.
