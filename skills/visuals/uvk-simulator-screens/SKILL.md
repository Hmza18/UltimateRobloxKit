---
name: uvk-simulator-screens
description: Premium simulator UI built from the kit's animated UI/Game components - PremiumButton, TabBar, Modal, Tooltip, XPBar, InventorySlot, PetCard, RarityBadge, RewardPanel, QuestCard, AchievementCard, Notification, LeaderboardRow, LoadingScreen, SelectionCard, HotbarSlot and StatChip, alongside ProductCard, GameWindow, CurrencyCounter and the ten Visuals themes. Use when a shop, HUD, inventory, quest log, reward or loading screen should look and feel like a polished premium simulator, or when choosing which ready component fits a screen.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [premium simulator, simulator screen, premium shop, premium ui, shop feel, animated component, pet card, xp bar, quest card, inventory slot, hotbar cooldown, loading screen, visual theme, simulator hud]
  depends: [uvk-visuals-kit, uvk-ui-animation]
---

# UVK simulator screens

## When to use

- Assembling a shop, HUD, inventory, quests, achievements, rewards, leaderboard, loading or selection screen from components that already animate.
- Making an existing screen feel premium: swap plain buttons and bars for the animated components and set a theme.

When not to use: generating a whole screen from a JSON spec (`roblox-ui-generator`; the spec format has element types for these components too); the purchase flow and prices (`roblox-shop-builder`); layout rules per device (`roblox-responsive-layout`); custom motion on hand-built UI (`uvk-ui-animation`).

## Inputs

- The screen's content and the server data behind it. Components send intents and read state; they never grant anything.
- A theme: `VibrantSimulator` (default), `PremiumCartoon`, `Fantasy`, `Anime`, `SciFi`, `Cozy`, `ModernMinimal`, `Arcade`, `Luxury`, `Adventure`.

## Workflow

1. **Set the theme before building UI.** Components read the style when they are built.

   ```lua
   local Visuals = require(ReplicatedStorage.Shared.Urk.Visuals.Visuals)
   local Game = require(ReplicatedStorage.Shared.Urk.UI.Game.Game)

   Visuals:Configure({ theme = "PremiumCartoon" })
   ```

2. **Pick components, not frames.** Every component is `Game.<Name>.new(props)` with `.Instance`, `:update(partial)` and `:destroy()`; interactive ones have `Activated`.

   | Need | Component | Motion it brings |
   |---|---|---|
   | Main call to action | `PremiumButton` | Premium press style, looping shine, glow |
   | Shop tabs | `TabBar` | sliding indicator, text bounce |
   | Confirm dialog | `Modal` | modal and backdrop in / out |
   | Hints | `Tooltip` | pop in, fade out |
   | Level progress | `XPBar` | fill, overflow across levels, badge pulse |
   | Inventory grid | `InventorySlot` | select, locked shake |
   | Pet list | `PetCard`, `RarityBadge` | hover lift, selected glow, shimmer |
   | Claim screens | `RewardPanel` | tiles pop in from the centre, then the claim button |
   | Quests, achievements | `QuestCard`, `AchievementCard` | claimable pulse, unlock flash, stars |
   | Toasts | `Notification` | toast in / out, timer bar |
   | Leaderboards | `LeaderboardRow` | rolling value |
   | Loading | `LoadingScreen` | breathing logo, tips, fade out |
   | Class or mode choice | `SelectionCard` | selected tick and glow |
   | Abilities | `HotbarSlot` | cooldown sweep, ready pulse |
   | Stats | `StatChip`, `CurrencyCounter` | rolling numbers |
   | Shop items | `ProductCard`, `PromoBanner`, `GameWindow`, `Grid` | card styling, badges, timers |

3. **A premium shop in outline.**

   ```lua
   local shop = Game.GameWindow.new({ title = "SHOP", sizeClass = "lg", parent = playerGui })
   local tabs = Game.TabBar.new({
   	tabs = { { id = "pets", text = "PETS" }, { id = "eggs", text = "EGGS" } },
   	layoutOrder = 1, parent = shop.Content,
   })
   tabs.Changed:Connect(function(id) showPage(id) end)

   local grid = Game.Grid.new({ columns = { phone = 2, tablet = 3, desktop = 4 }, layoutOrder = 2, parent = shop.Content })
   grid:add(Game.ProductCard.new({
   	name = "tripleHatch", palette = "purple", icon = "egg-color", title = "TRIPLE HATCH",
   	price = { kind = "robux", amount = 599, gamePassId = 654321 }, badge = { kind = "best" },
   }))

   local claim = Game.PremiumButton.new({ text = "CLAIM REWARD", icon = "gift-color", parent = shop.Content })
   claim.Activated:Connect(function() ClaimRemote:FireServer() end)
   shop:open()
   ```

4. **Let state changes animate.** Update props instead of rebuilding: `xp:gain(250)`, `quest:update({ value = 10 })`, `card:update({ selected = true })`, `row:update({ value = score })`, `slot:startCooldown(8)`.

5. **Connect screens to feedback.** A confirmed purchase: `Visuals.Feedback:Fire("Purchase", { gui = card.Instance, position = rootPart.Position })` (`position` is a world position for the confetti; leave it out for UI only). A refused one: `Visuals.Feedback:Fire("Error", { gui = card.Instance })`. A claim: `Visuals.Rewards:Batch(...)`.

6. **Restraint is what reads as premium.** One shining call to action per screen. One attention loop on the HUD. Consistent rarity colours from the theme. Generous spacing. Entrances staggered by 50-80 ms, exits faster than entrances.

7. **Settings.** Component motion follows `Visuals:Configure({ reducedMotion, reducedFlashing, intensity, quality })`. Touch targets default to 44 px or more; do not shrink them.

## Outputs

- Client screen modules built from `Game` components under a ScreenGui, with a theme set at startup and remotes for every action.

## Validation

```bash
python3 $URK/urk.py check .
```

```bash
lune run tests/urk/run tests/urk
```

Then the Studio checklist in the component README (`library/src/UI/Game/README.md`, "Testing and Studio checklist") at phone, tablet, desktop and gamepad-only. Layout, text fitting and every animation of the animated components are `NEEDS MANUAL REVIEW`.

## Pitfalls

- **Scale-based heights.** Several components read their offset height at build time; give them offset sizes (the defaults are).
- **Expecting fades on frames.** Only Tooltip, Notification and LoadingScreen are CanvasGroups; other entrances show scale and travel.
- **Theme set after building.** Set it first, or rebuild on `Visuals.Themes.Changed`.
- **Shine on everything.** Shine on five buttons is noise; it is also off at Low quality.
- **Components that grant.** `RewardPanel` fires `Claimed`; the server grants. `QuestCard` becomes `claimed` only after the server confirms.
- **Stacking toasts by hand** with overlapping positions. Use a UIListLayout or `Core/ToastQueue`.

## Limitations

- The 17 animated components pass StyLua, Selene and `luau-lsp` only. They were not run in Studio; layout fractions, text fitting and motion are unverified.
- `HotbarSlot` has a vertical cooldown sweep; a radial sweep is not implemented.
- A custom theme reuses an existing style key; a new component look needs a new style in the design tokens (`roblox-design-system`).
