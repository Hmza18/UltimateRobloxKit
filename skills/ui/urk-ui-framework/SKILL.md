---
name: urk-ui-framework
description: Builds Roblox UI with UrkUI, the kit's tag- and attribute-driven framework - panels and modals, buttons with actions, live data binding to a Store, tabs, tooltips, toasts, context menus, drag-and-drop, progress bars, icons, themes (dark, light, high contrast), responsive phone-to-console layouts, gamepad navigation, localisation and animation, mostly without writing scripts. Use for any HUD, menu, shop, inventory or settings screen in a project that uses the kit library.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [urkui, tag based ui, ui framework, hud, panel, toast, tooltip, data binding, theme, drag and drop ui, settings panel]
  depends: [roblox-ui-systems, roblox-icon-design]
---

# UrkUI framework

Original framework in `library/src/UI/` (MIT). Full tag, attribute, action and component reference: `$URK/library/src/UI/README.md`. Read the sections you need rather than the whole file.

## When to use

Any UI in a project with the kit library. For general Roblox UI principles (scale vs offset, layout objects) see `roblox-ui-systems`. For icons see `roblox-icon-design`; for spec-built game screens see `roblox-ui-generator`. For animation presets, button bindings, counters and popups on top of UrkUI see `uvk-ui-animation`; for the animated game components see `uvk-simulator-screens`.

## Install and start

1. Add it to the game: `python3 $URK/urk.py add UI --project .` (this pulls in Icons and Util). It is then at `ReplicatedStorage.Shared.Urk.UI.UrkUI`; with the `.rbxm` model, it is at `ReplicatedStorage.UltimateRobloxKit.UI.UrkUI`.
2. One LocalScript starts it:
   ```lua
   local UrkUI = require(ReplicatedStorage.Shared.Urk.UI.UrkUI)
   UrkUI.registerActions({ BuySword = function(action) BuyRemote:FireServer("Sword") end })
   UrkUI.start({ store = UrkUI.Store.fromAttributes(Players.LocalPlayer, "Stats"), theme = "dark" })
   ```
3. Everything else can be tags and attributes in Studio.

## Building screens with tags (no code)

| Want | Tag | Key attributes |
|---|---|---|
| A menu that opens and closes | `UrkPanel` (or `UrkModal`) | `PanelId`, optional `Group`, `Modal` |
| A button that does something | `UrkButton` | `Action` = `OpenPanel:Shop`, `TogglePanel:Bag;PlaySound:123`, `Fire:Buy,sword` |
| A label that shows live data | `UrkBind` | `Path` = `Stats.Cash`, `Format` = `abbrev` / `percent` / `time` |
| A bar that fills | `UrkProgress` | `Path`, plus a max value |
| Tabs | `UrkTabs` on the container, `UrkTab` on buttons | `Tab`; pages carry `TabPage` |
| Hover help | `UrkTooltip` | `Text` |
| Right-click or long-press menu | `UrkContextMenu` | `Items` = `Equip=Equip;Drop=Drop;-;Sell=Sell` |
| Drag and drop | `UrkDraggable`, `UrkDropTarget` | `DragId`, `DropId` (the game gets an intent and decides) |
| Icon | `UrkIcon` | `Icon` = `coin` |
| Themed colour | `UrkTheme` | `Role` = `surface`, `primary:hover`, `text` |
| Translated text | `UrkLocalize` | `Key` |
| Gamepad group | `UrkNav` | `Wrap` |
| Auto scale | `UrkResponsive` | `AutoScale` |
| Decoration | `UrkAnimate` | `Effect` = `Spin` / `Bob` / `Pulse` / `Shine` / `Rainbow` |

Built-in actions: OpenPanel, ClosePanel, TogglePanel, Back, CloseAll, ShowToast, SetTheme, CycleTheme, SetLocale, PlaySound and Fire. Game actions are registered with `UrkUI.registerActions`, so kit files are never edited.

## Building screens in code

Components (`UrkUI.Components`): Button, Window, Dialog, ProgressBar, Currency, Tabs, InventoryGrid, ShopCard, SettingsPanel and Hud. Toasts and menus go through `UrkUI.toast({ text, kind })` and `UrkUI.contextMenu`. A SettingsPanel is generated from a schema (toggle, slider, dropdown, keybind) and emits changes for the game to validate and save.

## Rules

- **The UI sends intents and never decides outcomes.** Purchases, inventory moves and rewards go to the server, which validates them. Use the library systems (`Systems/Shop`, `Systems/Inventory`) on the server.
- **Colours come from theme roles, not literals.** Check contrast with `Core/Contrast` (built-in themes meet AA, and high contrast meets AAA).
- Test every screen at phone portrait, tablet, desktop and console with a gamepad only. Reduced motion must still work.
- Keep animations decorative and short; the shared driver runs only while something animates.

## Validation

- Pure logic (Store, Format, Theme, Contrast, Breakpoints, Layout, SpatialNav, Localizer, Easing, ToastQueue, PanelRouter, SettingsSchema, SlotLogic, TagSpec) has 119 Lune cases: `lune run tests/urk/run tests/urk` in a project, or `lune run tests/run` in `library/`.
- Runtime, Behaviours and Components need a Studio playtest. The checklist is in the README's "Testing and what needs a Studio playtest" section.

## Limitations

Adapter code was written without a Studio run; the README lists the API names to check (ReducedMotionEnabled, ScreenInsets, font names, input coordinate spaces). There are no visual stories yet; UI Labs stories are on the roadmap. Not a replacement for React-Lua or Fusion in teams already using them.
