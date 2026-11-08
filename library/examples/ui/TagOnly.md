# Tag-only UrkUI setup (no UI code)

Everything below is done in Studio with the Tag Editor (Properties → Tags) and the Attributes
section of the Properties window. The only script is the three-line
[TagOnlyBootstrap.client.luau](TagOnlyBootstrap.client.luau). Server scripts set the numbers with
`player:SetAttribute("Cash", 120)`, `player:SetAttribute("XP", 40)` and `player:SetAttribute("XPMax", 100)`.

Build this tree under **StarterGui** (names are only for you; UrkUI finds everything by tag):

```
StarterGui
├── Hud (ScreenGui)
│   ├── CashLabel (TextLabel)        tags: UrkBind, UrkTheme
│   ├── CoinIcon (ImageLabel)        tags: UrkIcon, UrkAnimate
│   ├── XpBar (Frame)                tags: UrkProgress, UrkTheme
│   │   └── Fill (Frame)
│   └── ShopButton (TextButton)      tags: UrkButton
└── Menus (ScreenGui)
    ├── Shop (Frame)                 tags: UrkPanel, UrkTheme, UrkNav, UrkResponsive
    │   ├── Close (TextButton)       tags: UrkButton
    │   └── Body (Frame)             tags: UrkTabs
    │       ├── ItemsTab (TextButton)   tags: UrkTab
    │       ├── PetsTab (TextButton)    tags: UrkTab
    │       ├── ItemsPage (Frame)
    │       │   └── Sword (ImageButton) tags: UrkButton, UrkContextMenu
    │       └── PetsPage (Frame)
    └── ConfirmReset (Frame)         tags: UrkModal, UrkTheme
        ├── Yes (TextButton)         tags: UrkButton
        └── No (TextButton)          tags: UrkButton
```

| Instance | Attributes |
|---|---|
| CashLabel | `Path` = `Stats.Cash`, `Format` = `abbrev`, `Animate` = true, `Template` = `{value} coins`, `TextRole` = `text` |
| CoinIcon | `Icon` = `coin`, `Effect` = `Pulse`, `Amplitude` = 0.08 |
| XpBar | `Path` = `Stats.XP`, `MaxPath` = `Stats.XPMax`, `Segments` = 5, `Role` = `surfaceAlt`, `Radius` = `pill` |
| ShopButton | `Action` = `TogglePanel:Shop`, `Variant` = `primary`, `Tooltip` = `Shop`, `ClickSound` = an audio asset id |
| Shop | `PanelId` = `Shop`, `Group` = `main`, `Transition` = `pop`, `Role` = `surface`, `Radius` = `lg`, `Phone_Size` = a smaller UDim2 |
| Close | `ClosesPanel` = true, `Variant` = `ghost` |
| Body | `Selected` = `Items` |
| ItemsTab / PetsTab | `Tab` = `Items` / `Tab` = `Pets` |
| ItemsPage / PetsPage | `TabPage` = `Items` / `TabPage` = `Pets` (a plain attribute, not a tag) |
| Sword | `Tooltip` = `Iron Sword`, `Action` = `Fire:BuyItem,Sword`, `Items` = `Inspect=Fire:Inspect,Sword; -; Buy=Fire:BuyItem,Sword` |
| ConfirmReset | `PanelId` = `ConfirmReset`, `Dismissible` = false, `Role` = `surface` |
| Yes | `Action` = `Fire:ResetConfirmed;ClosePanel:ConfirmReset`, `Variant` = `danger` |
| No | `Action` = `ClosePanel:ConfirmReset`, `Variant` = `secondary` |

What you get with no code:

- The shop opens and closes from the HUD button with a pop transition; opening another panel in
  group `main` closes it; gamepad B or Escape closes it.
- With a gamepad, focus jumps into the shop when it opens, the D-pad moves between the nearest
  buttons, and focus returns to the HUD button when it closes.
- The cash label counts up with abbreviations (1.2K), the XP bar animates in five segments, and
  the coin pulses (not with reduced motion).
- Hover and press scale on every UrkButton, a tooltip on the sword, and a right-click /
  long-press / gamepad X menu on it.
- Themes: everything tagged UrkTheme re-skins when an `Action` = `SetTheme:light` or
  `CycleTheme` button is pressed.

The `Fire:...` actions raise `UrkUI.Intent` on the client. To act on them, a game script connects
to `UrkUI.Intent` and sends a request to the server, which validates it. That is the one place the
game needs code, because the client must never decide outcomes such as purchases.
