# UrkUI

A tag- and attribute-driven UI framework for Roblox. Build UI in Studio, tag it, set attributes,
and UrkUI wires the behaviour: panels and routing, actions, data binding, theming, localisation,
responsive layout, gamepad navigation, animation, tooltips, toasts, context menus and drag and
drop. Everything is also available as code-created components that use the same tags.

UrkUI is original work. It follows the library rules in
[library-conventions.md](../../../docs/architecture/library-conventions.md): pure logic in `Core/`
(tested with Lune), thin Roblox adapters in `Runtime/` and `Behaviours/`, relative requires,
Trove-owned cleanup, and no hard-coded game ids or paths.

## Contents

- [Quick start](#quick-start)
- [Layout](#layout)
- [Tag and attribute reference](#tag-and-attribute-reference)
- [Actions](#actions)
- [Data binding and the Store](#data-binding-and-the-store)
- [Components](#components)
- [Theming](#theming)
- [Responsive layout](#responsive-layout)
- [Controller and accessibility](#controller-and-accessibility)
- [Localisation](#localisation)
- [Animation](#animation)
- [Icons](#icons)
- [Performance](#performance)
- [Security model](#security-model)
- [Testing and what needs a Studio playtest](#testing-and-what-needs-a-studio-playtest)
- [Limitations](#limitations)

## Quick start

```lua
-- StarterPlayerScripts/UI.client.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UrkUI = require(ReplicatedStorage.UltimateRobloxKit.UI.UrkUI)

UrkUI.registerActions({
	BuySword = function(action)
		ReplicatedStorage.Remotes.Buy:FireServer("Sword") -- the server validates and charges
	end,
})

UrkUI.start({
	store = UrkUI.Store.fromAttributes(Players.LocalPlayer, "Stats"), -- player attributes -> Stats.*
	theme = "dark",
})

UrkUI.toast({ text = "Welcome!", kind = "success" })
```

Then tag a TextButton `UrkButton` with `Action` = `BuySword`, and a TextLabel `UrkBind` with
`Path` = `Stats.Cash` and `Format` = `abbrev`. See [the examples](../../examples/ui/), including a
[tag-only setup](../../examples/ui/TagOnly.md) that needs no UI code at all.

## Layout

| Folder | Contents | Runs in |
|---|---|---|
| `Core/` | Pure logic: Path, Store, Format, Tokens, Theme, Contrast, Breakpoints, Layout, SpatialNav, Localizer, Easing, Decor, ToastQueue, PanelRouter, SettingsSchema, SlotLogic, TagSpec | Anywhere, Lune tests |
| `Runtime/` | Services: Binder, Panels, Actions, ThemeService, Motion, Driver, Focus, Responsive, LocalizeService, TooltipService, ToastService, ContextMenuService, DragService, StoreAdapter, Sounds, IconBridge, Create, Context | Client |
| `Behaviours/` | One module per group of tags; each binds a tag to an instance | Client |
| `Components/` | Code-created Button, Window, Dialog, ProgressBar, Currency, Tabs, InventoryGrid, ShopCard, SettingsPanel, Hud | Client |
| `UrkUI.luau` | Public entry point | Client (Core parts anywhere) |

## Tag and attribute reference

Tags are CollectionService tags. UrkUI discovers tagged instances under PlayerGui (or the
`roots` you pass to `start`) by tag, never by path, including UI added later. Each bound instance
gets its own Trove, cleaned when the instance is destroyed, leaves the roots or loses the tag.
Changing one of a tag's attributes at runtime re-binds it (at most once per frame).
`Core/TagSpec.luau` holds this table as data; a test checks that this README lists every entry.

| Tag | Put it on | Attribute | Type | Default | Meaning |
|---|---|---|---|---|---|
| `UrkPanel` | GuiObject or ScreenGui | `PanelId` | string | required | Router id for OpenPanel / ClosePanel / TogglePanel |
| | | `Group` | string | | Exclusive group: opening one closes the others |
| | | `Exclusive` | boolean | true | false lets panels of the group stack |
| | | `Modal` | boolean | false | Modal layer with a backdrop |
| | | `Dismissible` | boolean | true | false blocks Back and backdrop clicks |
| | | `AdoptPriority` | number | 0 | Duplicates with the same PanelId: highest wins, ties keep the first |
| | | `StartOpen` | boolean | false | Open when bound |
| | | `Transition` | string | `pop` | `none`, `fade` (CanvasGroup), `pop`, `slideUp`, `slideDown`, `slideLeft`, `slideRight` |
| | | `CloseOnBackdrop` | boolean | true | Clicking the modal backdrop closes it |
| `UrkModal` | GuiObject or ScreenGui | same as UrkPanel | | | UrkPanel with `Modal` = true |
| `UrkButton` | TextButton / ImageButton | `Action` | string | | Action spec, see [Actions](#actions) |
| | | `Target` | string | | Argument used when the Action has none (`TogglePanel` + Target `Shop`) |
| | | `Variant` | string | | `primary`, `secondary`, `ghost`, `danger`: themed colours with hover / pressed states |
| | | `Tooltip` | string | | Tooltip text |
| | | `TooltipKey` | string | | Localisation key for the tooltip |
| | | `HoverScale` | number | 1.05 | Scale while hovered or gamepad-selected |
| | | `PressScale` | number | 0.95 | Scale while pressed |
| | | `HoverSound` | string | | Sound asset id on hover |
| | | `ClickSound` | string | | Sound asset id on activation |
| | | `Cooldown` | number | 0 | Seconds between activations |
| `UrkBind` | any GuiObject | `Path` | string | required | Store path, for example `Stats.Cash` |
| | | `Format` | string | | `number`, `abbrev`, `percent`, `time`, `duration`, `upper`, `lower` or a registered formatter, with an optional `:arg` (`abbrev:2`) |
| | | `Property` | string | `Text` | Property to write; non-text properties get the raw value |
| | | `Template` | string | | Text with `{value}`, for example `Cash: {value}` |
| | | `Animate` | boolean | false | Count numbers up or down |
| | | `Fallback` | string | `""` | Shown while the value is nil |
| `UrkProgress` | Frame | `Path` | string | | Store path of the value |
| | | `Value` | number | 0 | Static value without a Path |
| | | `Max` | number | 1 | Maximum |
| | | `MaxPath` | string | | Store path of the maximum |
| | | `Fill` | string | `Fill` | Child frame to scale (created and themed if missing) |
| | | `Segments` | number | 0 | Segment dividers |
| | | `Animate` | boolean | true | Tween the fill |
| | | `Vertical` | boolean | false | Fill bottom to top |
| `UrkTabs` | container | `Selected` | string | first tab | The selected tab; set it to switch tabs |
| `UrkTab` | GuiButton inside UrkTabs | `Tab` | string | required | Shows descendants of the container whose `TabPage` attribute matches |
| `UrkTooltip` | any GuiObject | `Text` | string | | Tooltip text |
| | | `Key` | string | | Localisation key, used instead of Text |
| | | `Delay` | number | 0.35 | Seconds before showing |
| | | `Placement` | string | `below` | `below`, `above`, `left`, `right` (flips near screen edges) |
| `UrkToastHost` | Frame | (none) | | | Toasts go into the most recent host; without one a top-right host is created |
| `UrkDraggable` | GuiObject | `DragId` | string | | Payload id reported with the drop |
| | | `DragGroup` | string | `default` | Only targets of the same group accept it |
| `UrkDropTarget` | GuiObject | `DropId` | string | | Id reported with the drop |
| | | `DragGroup` | string | `default` | Group of draggables accepted |
| `UrkIcon` | ImageLabel / ImageButton | `Icon` | string | required | Icon name from the Icons catalogue |
| | | `IconColor` | Color3 | | Tint |
| | | `IconSize` | number | | Square size in pixels |
| `UrkAnimate` | GuiObject | `Effect` | string | required | `Spin`, `Bob`, `Pulse`, `Shine`, `Rainbow` |
| | | `Speed` | number | per effect | Spin: degrees/s (90); Bob, Pulse: cycles/s; Shine: sweeps/s; Rainbow: hue cycles/s |
| | | `Amplitude` | number | per effect | Bob: pixels (4); Pulse: scale fraction (0.06) |
| | | `Phase` | number | 0 | Offset so neighbours do not move in sync |
| | | `Pause` | number | 1.5 | Shine: rest between sweeps |
| `UrkTheme` | any GuiObject | `Role` | string | | Background colour role, with an optional state: `primary:hover` |
| | | `TextRole` | string | | TextColor3 role |
| | | `StrokeRole` | string | | Colour of a child UIStroke |
| | | `ImageRole` | string | | ImageColor3 role |
| | | `PlaceholderRole` | string | | TextBox placeholder colour |
| | | `TransparencyRole` | string | | BackgroundTransparency from the theme (`overlay`, `surface`, `ghost`) |
| | | `TextSize` | string | | Text token (`caption`, `body`, `label`, `title`, `heading`, `display`); never below the minimum text size |
| | | `Radius` | string | | Radius token for a UICorner (`sm`, `md`, `lg`, `xl`, `pill`) |
| `UrkLocalize` | text object | `Key` | string | required | Localisation key |
| | | `Property` | string | `Text` | Property to write |
| | | `Arg_<name>` | any | | Literal placeholder value |
| | | `ArgPath_<name>` | string | | Placeholder bound to a Store path |
| `UrkContextMenu` | GuiObject | `Items` | string | required | `Label=Action` pairs separated by `;`, `-` for a separator |
| `UrkNav` | container | `Wrap` | boolean | false | Wrap at the edges |
| | | `AutoSelect` | boolean | true | Select the first element when the group appears (gamepad) |
| | | `Remember` | boolean | true | Return to the last selected element |
| `UrkResponsive` | GuiObject | `AutoScale` | boolean | false | Add a UIScale driven by the breakpoint |
| | | `Phone_<Property>` etc. | any | | Per-breakpoint overrides, see [Responsive layout](#responsive-layout) |

Plain attributes that are not tied to a tag:

| Attribute | On | Meaning |
|---|---|---|
| `ClosesPanel` = true | a GuiButton inside a panel | Closes that panel when activated |
| `TabPage` = name | a descendant of UrkTabs | Page shown by the UrkTab with the same `Tab` |
| `UrkDragging`, `UrkCarried`, `UrkDropHover`, `UrkRatio`, `UrkBreakpoint`, `Selected` | set by UrkUI | State you can read or style against |

## Actions

An `Action` is one or more calls separated by `;`, each `Name` or `Name:arg1, arg2`.
`Action` = `OpenPanel:Shop;PlaySound:12345` opens the shop and plays a sound.

| Built-in | Arguments | Does |
|---|---|---|
| `OpenPanel` | id | Opens a panel (builds a lazily defined one first) |
| `ClosePanel` | id (optional) | Closes the panel, or goes back when no id is given |
| `TogglePanel` | id | Opens or closes |
| `Back` | | Closes the top dismissible panel |
| `CloseAll` | group (optional) | Closes every panel, or every panel of a group |
| `ShowToast` | text[, kind] | Shows a toast; the text is looked up in the Localizer first |
| `SetTheme` | name | Switches theme |
| `CycleTheme` | | Next theme in `themeOrder` |
| `SetLocale` | locale | Switches language |
| `PlaySound` | asset id | Plays a UI sound |
| `Fire` | name, args... | Fires `UrkUI.Intent(name, args, source)` for game code |

Game actions are registered without editing kit files:

```lua
UrkUI.registerActions({
	Equip = function(action) -- action = { name, args, raw, source, ui }
		EquipRemote:FireServer(action.args[1])
	end,
})
```

`registerActions` works before or after `start` and returns an unregister function.

## Data binding and the Store

`Core/Store.luau` is an observable state tree addressed by dotted paths. It is pure Luau.

| Method | Description |
|---|---|
| `Store.new(initial?, { scheduler?, onError? })` | New store. `scheduler` (UrkUI uses `task.defer`) coalesces writes per frame |
| `store:get(path?)` | Value at a path, or the whole tree. Values are frozen |
| `store:set(path, value)` | Writes (deep-copied and frozen). Same primitive value is a no-op |
| `store:update(path, fn)` | `set(path, fn(current))` |
| `store:merge(path, table)` | Sets several children in one batch |
| `store:subscribe(path, fn)` | `fn(new, old, path)` when the value at `path` changes; returns unsubscribe |
| `store:observe(path, fn)` | subscribe and call now |
| `store:batch(fn)` | Every subscriber fires at most once, after `fn` |
| `store:flush()` | Delivers pending notifications now |

Writes are copy-on-write, so subscribers fire for the written path, its ancestors and its changed
descendants, never for siblings. Feed the store from replicated state:

| Adapter | Description |
|---|---|
| `UrkUI.Store.fromAttributes(instance, prefix, { store?, nest? })` | Mirrors attributes (for example on the Player) into `prefix.*`; `nest = "_"` turns `Upgrades_Speed` into `Upgrades.Speed`. Returns store, stop |
| `UrkUI.Store.fromFolder(folder, prefix, { store? })` | Mirrors ValueBase children (leaderstats) and nested folders. Returns store, stop |

Formatters: `UrkUI.registerFormatter("coins", function(value, arg) return value .. " c" end)` makes
`Format` = `coins` work on UrkBind and `{cash:coins}` in translations.

## Components

All components need `UrkUI.start()` first and return a handle with `Instance` and `Destroy`.
They are built from tagged instances, so they get the same theming, sounds, tooltips and
navigation as Studio-built UI.

| Component | Constructor | Handle |
|---|---|---|
| Button | `Button.new({ text, variant, size = "sm"/"md"/"lg", icon, action, tooltip, width, onClick, parent })` | `setText`, `setEnabled`, `Activated` |
| Window | `Window.new({ id, title, titleKey, size, closable, modal, dismissible, group, transition, parent, build })`; `Window.define(props)` builds on first open | `Content`, `open`, `close`, `isOpen` |
| Dialog | `Dialog.confirm({ title, message, confirmText, cancelText, danger, onResult })`, `Dialog.alert(...)`, also `UrkUI.confirm` | `Result` signal, `wait()` (yields; returns at once if answered), `close(result)` |
| Toasts | `UrkUI.toast(text, kind)` or `UrkUI.toast({ text, title, kind, duration, key, icon })` | returns an id for `UrkUI.dismissToast(id)` |
| Tooltip | `UrkTooltip` tag, `Tooltip` on UrkButton, or `context.tooltip:attach` | shared, pooled, edge-clamped |
| Context menu | `UrkUI.contextMenu({ { label, action / callback, disabled, separator } }, pointOrObject)` | closes on outside click / Back |
| Tabs | `Tabs.new({ tabs = { { id, label, labelKey } }, selected, onChanged, parent })` | `Pages[id]`, `select`, `selected` |
| ProgressBar | `ProgressBar.new({ value, max, segments, role, label = "{value} / {max}", format, parent })` | `set(value, max?)`, `get` |
| Currency | `Currency.new({ icon, path or value, format = "abbrev", parent })` | `set(value)` (count-up, unbound only) |
| InventoryGrid | `InventoryGrid.new({ slots, columns, cellSize, gap, group, dropOptions, onIntent, onReject, onSelect, tooltip, renderSlot, parent })` | `setSlots`, `select`, `selected`, `move` |
| ShopCard | `ShopCard.new({ name, price, icon, currencyIcon, description, owned, affordable, onBuy, parent })` | `setState({ owned, affordable, price })` |
| SettingsPanel | `SettingsPanel.new({ schema, values, onChanged(key, value, all), parent })` | `getValues`, `setValues` |
| Hud | `Hud.new({ name, insets = "core"/"device"/"none", padding, gap, autoScale })` | `rail(name)`, `add(rail, object, order)` |

Components are reached through `UrkUI.Components.<Name>` and load on first use.

Toast queue rules (`Core/ToastQueue.luau`): at most `maxToasts` (3) visible, the rest queued by
priority (error > warning > success = info) then arrival; a toast with the same kind and text, or
the same `key`, merges into the existing one (counter badge, timer restarts); `duration = 0` is
sticky. Default durations: info 4 s, success 3 s, warning 5 s, error 6 s.

Settings schema (`Core/SettingsSchema.luau`): entries are `{ key, kind, label, labelKey,
description, section, default }` plus `min`, `max`, `step` for sliders and `options` for dropdowns.
Kinds are `toggle`, `slider`, `dropdown` and `keybind` (display only). `validate` lists problems,
`sanitize` repairs saved values, `applyChange` returns new values without mutating.

Inventory intents (`Core/SlotLogic.luau`): `resolveDrop(slots, from, to, { maxStack, allowSwap,
split })` returns `move`, `swap`, `merge` (partial when the stack fills) or `reject` with a reason
(`locked`, `not accepted`, `stack full`, `occupied`, `same slot`, `empty source`, `out of range`).
Slots may declare `accepts = { "Weapon" }` and `locked = true`.

## Theming

Design tokens live in `Core/Tokens.luau`: colours per theme, spacing, radius, stroke, text sizes,
fonts, motion durations, DisplayOrder layers (`hud` 0, `panel` 10, `modal` 50, `toast` 80,
`tooltip` 90, `menu` 95, `drag` 100) and button sizes. Built-in themes: `dark`, `light` and
`highContrast`. Roles: `background`, `surface`, `surfaceAlt`, `border`, `text`, `textMuted`,
`primary`, `onPrimary`, `secondary`, `onSecondary`, `danger`, `onDanger`, `success`, `onSuccess`,
`warning`, `onWarning`, `info`, `onInfo`, `focus`, `overlay`. Any role takes a state suffix
(`:hover`, `:pressed`, `:disabled`).

```lua
UrkUI.start({
	themes = { brand = { name = "brand", extends = "dark", colors = { primary = "#8E24AA" } } },
	theme = "brand",
	themeOrder = { "brand", "light", "highContrast" },
})
UrkUI.setTheme("light") -- every UrkTheme element and component re-skins
```

`Core/Contrast.luau` computes WCAG 2 ratios. `Theme.validate` checks every text pair (text on
background and surfaces, onPrimary on primary, and so on) and non-text pairs (focus ring, border).
The dark and light themes pass AA (4.5:1) and high contrast passes AAA (7:1); this is a unit test.
Custom themes with problems print warnings at start-up.

## Responsive layout

`Core/Breakpoints.luau` classifies the viewport and input mix:

| Breakpoint | Rule (defaults) |
|---|---|
| `console` | `GuiService:IsTenFootInterface()`, or a gamepad as the last input without keyboard or touch |
| `phone` | short side under 500 px |
| `tablet` | touch with short side under 900 px, or a non-touch window narrower than 1000 px |
| `desktop` | everything else |

`UrkUI.getBreakpoint()` and `UrkUI.BreakpointChanged(breakpoint, scale)` expose it. The UIScale
fits a reference resolution per breakpoint (phone 844x390, tablet 1180x820, desktop and console
1920x1080), clamped to 0.6 to 1.5 and multiplied by `UrkUI.setUIScale(multiplier)`.

On an `UrkResponsive` element, attributes named `<Breakpoint>_<Property>` override that property:
`Phone_Size`, `Tablet_Position`, `Console_Visible`, `Desktop_TextSize`. Console falls back to
Desktop overrides. The authored value is restored when no override applies.
Safe areas: `Hud` uses `ScreenGui.ScreenInsets` (`CoreUISafeInsets` by default) and
`Layout.safeRect` / `responsive:insets()` give the same maths for custom layouts.

## Controller and accessibility

- **Focus groups.** `UrkNav` collects the visible, Selectable GuiObjects of a container, builds a
  spatial graph with `Core/SpatialNav.luau` (nearest neighbour per direction, aligned targets
  preferred over diagonal ones) and writes `NextSelectionUp/Down/Left/Right`. Groups re-wire when
  their contents or layout change. When a panel opens with a gamepad in use, focus moves into it,
  and it returns to the previous element when the panel closes.
- **Back.** Gamepad B and Escape close the top dismissible panel (and an open context menu first).
  They are bound only while a panel is open.
- **Reduced motion.** `reducedMotion = "auto"` (default) follows Roblox's reduce-motion setting
  when the engine exposes it; `UrkUI.setReducedMotion(true)` forces it. Every tween, transition,
  count-up, shake and decorative effect honours it.
- **Minimum text size.** `minTextSize` (12) and `UrkUI.setMinTextSize(n)`: themed text never goes
  below it.
- **Contrast.** See [Theming](#theming); `highContrast` meets AAA.

## Localisation

`Core/Localizer.luau` looks up keys through a fallback chain (`pt-br` → `pt` → fallback), fills
`{placeholders}` (`{cash:abbrev}` applies a formatter, `{{` is a literal brace) and picks plural
forms with CLDR categories: `{ one = "{count} coin", other = "{count} coins" }`. Built-in plural
rules cover English-style languages, French, Russian, Ukrainian, Polish and languages without
plurals (Japanese, Chinese, Korean, Thai, Vietnamese, Indonesian); pass `pluralRules` for more.
Missing keys return the key itself.

```lua
UrkUI.start({
	translations = { en = { greet = "Hi {name}" }, fr = { greet = "Salut {name}" } },
	useRobloxTranslator = true, -- prefer the experience's cloud localisation table when it has the key
})
UrkUI.setLocale("fr")
print(UrkUI.t("greet", { name = "Ana" }))
```

## Animation

`Runtime/Motion.luau` wraps TweenService: `Motion.tween`, `show` / `hide` transitions, `pop`,
`bounce` and `shake`. Durations are token names (`fast` 0.12 s, `normal` 0.2 s, `slow` 0.35 s) or
seconds, and become 0 with reduced motion. Pure easing curves (`linear`, `quad*`, `cubic*`,
`sineInOut`, `backOut`, `elasticOut`, `bounceOut`), a frame-rate-independent spring and count-up
maths are in `Core/Easing.luau`; decorative effect values in `Core/Decor.luau`.

## Icons

`UrkIcon` and the components call the kit's icon catalogue at `src/Icons/Icons.luau`
(`Icons.apply(label, name, { color, size })`, `Icons.has(name)`), through
`Runtime/IconBridge.luau`. The catalogue is loaded lazily; if it is missing, icons are skipped
with one warning and everything else keeps working. Toasts use the icon named after their kind
(`info`, `success`, `warning`, `error`) when the catalogue has one.

## Performance

- No per-frame work while idle. One shared frame driver (`Runtime/Driver.luau`) connects to
  RenderStepped only while a count-up, shake or decorative effect runs, and disconnects after.
- Decorative effects skip hidden objects and stop entirely under reduced motion.
- Toast expiry uses one `task.delay` for the earliest deadline; toast frames, the tooltip and
  context menu items are pooled.
- Store notifications are batched per frame; subscribers on unrelated paths are never called.
- `Window.define` / `UrkUI.definePanel` build panels on first open.
- Focus graphs and tab pages re-compute at most once per frame, on change only.

## Security model

UrkUI runs on the client and never decides game outcomes. Actions that matter (`Fire`, custom
actions, `ShopCard.onBuy`, `InventoryGrid.onIntent`, `SettingsPanel.onChanged`) hand the game an
intent to send to the server. The server validates it, for example with `Util/Validate`,
`Util/RateLimiter`, `SlotLogic.resolveDrop` and `SettingsSchema.sanitize` on its own data, and
replicates the result back (attributes or values that the Store mirrors).

## Testing and what needs a Studio playtest

| Part | Verified by |
|---|---|
| `Core/*` (Path, Store, Format, Theme, Contrast, Tokens, Breakpoints, Layout, SpatialNav, Localizer, Easing, Decor, ToastQueue, PanelRouter, SettingsSchema, SlotLogic, TagSpec) | Lune specs `tests/ui_*.spec.luau` (`lune run tests/run`), `luau-analyze --mode=strict` |
| `Runtime/*`, `Behaviours/*`, `Components/*`, `UrkUI.luau` | Selene and StyLua in CI only. **Needs a Studio playtest** |

Roblox-only behaviour to check in a playtest (NEEDS MANUAL REVIEW until done):

- Tag discovery for UI cloned from StarterGui on spawn, re-binding on attribute edits, cleanup on destroy.
- Panel transitions, modal backdrops and DisplayOrder layering across several ScreenGuis.
- Back with gamepad B and Escape (Escape also opens the Roblox menu on some platforms).
- Gamepad focus wiring, auto-select on open and focus return on close.
- Tooltip and context menu placement with and without `IgnoreGuiInset`, on phone and console.
- Drag and drop hit testing with `PlayerGui:GetGuiObjectsAtPosition`, touch drags, gamepad carry.
- Toast stacking, pooling and timers; count-up animations; UIScale per breakpoint.
- The reduce-motion setting (`GuiService.ReducedMotionEnabled`) and `LocalizationService` translator.
- `Font.fromName("BuilderSans", weight)` falling back to `GothamSSm` and then `Gotham`.

## Limitations

- Client only; `UrkUI.start` asserts it runs in a LocalScript. Core modules work anywhere.
- One running instance per client. `UrkUI.stop()` unbinds everything and removes kit ScreenGuis.
- Panels that are plain GuiObjects are layered with ZIndex inside their ScreenGui; modals raise
  that ScreenGui's DisplayOrder while open. Give a modal its own ScreenGui (Window and Dialog do)
  for reliable layering above other ScreenGuis.
- The `fade` transition needs a CanvasGroup; other objects use `pop`.
- Panels are hidden when bound unless `StartOpen` is set, so UI left visible for editing in Studio
  starts closed in play.
- Keybind entries in the settings panel are display only; rebinding is up to the game.
- `UrkResponsive` overrides properties that UrkUI can read and write by name; it cannot override
  properties driven by another script at the same time.
- The Icons catalogue is a separate module; icon names depend on it.
