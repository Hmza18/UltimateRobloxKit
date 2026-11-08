---
name: roblox-ui-generator
description: Turns a natural-language UI request into a validated UrkUI screen spec JSON and real Roblox UI through Spec/Builder - pick a ready template with urk.py ui list, map phrases to elements, choose palettes and -color icons from the catalog, write the spec, validate, preview in the browser, install it into a project with urk.py ui new and wire purchase and select intents. Includes worked shop, HUD and daily-rewards specs. Use when someone asks to create, generate or mock up a shop, store, HUD, daily rewards, inventory, quest or popup screen.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [screen spec, generate ui, create a shop ui, ui spec, make a hud, daily rewards ui, spec builder, ui from description, urk.py ui, mock up a screen]
  depends: [roblox-ui-design, roblox-design-system, urk-ui-framework]
---

# Roblox UI generator (request -> spec -> Builder)

## Purpose

Produce game UI without hand-placing instances: a JSON screen spec (contract: `docs/architecture/ui-generation.md` section 4) that `Spec/Builder.luau` turns into Game components. Specs are small, diffable and validated before anything is built.

## When to use (and not)

- Use: new shops, stores, HUDs, reward calendars, quest lists, upgrade lists, confirm and reward popups.
- Not for screens the element table cannot express (custom minigames, maps): build those with UrkUI tags (`urk-ui-framework`) and Game components directly.
- Purchase server logic: `roblox-shop-builder`. Device behaviour: `roblox-responsive-layout`.

## Workflow

1. **Pick a template.** `python3 $URK/urk.py ui list` prints the 16 ready screens (PetSimShop, PremiumStore, GamepassStore, MainHud, DailyRewards, Inventory, PetHatch, Upgrades, Quests, Achievements, Settings, Leaderboard, Profile, Trading, RewardPopup, ConfirmPurchase). Start from the closest one; keep its structure.
2. **Map the request to elements** with the table below. Every sellable thing is a `product` (or `banner` when featured), every stat a `currency`, `level`, `progress` or `listRow`.
3. **Choose palettes and icons.** Palettes by role (`roblox-ui-design`). Icons: `python3 $URK/urk.py icons search egg` and use the `-color` name (`egg-color`). Unknown icon names are validation errors.
4. **Write the spec** (start from a copy, see step 7, or write JSON next to it). Give an `id` to everything code will read or update. Robux prices need `productId` (consumables) or `gamePassId` (passes); `0` is the placeholder until the real id exists.
5. **Validate**: `python3 $URK/urk.py ui validate MyShop.json`. Fix every `{path, message}`; never build a half-valid spec (Builder refuses).
6. **Preview**: `python3 $URK/urk.py ui preview MyShop.json --open` (self-contained HTML, approximate). Narrow the window to phone width; show the user.
7. **Install into the game**: `python3 $URK/urk.py ui new PetSimShop --name MyShop --project .` copies the template to `src/shared/UrkScreens/MyShop.json` and writes `src/client/Screens/MyShop.client.luau` (never overwrites). Replace the copied JSON with your spec.
8. **Wire intents** in the generated LocalScript:
   ```lua
   local PurchaseBridge = require(Urk.UI:WaitForChild("Game"):WaitForChild("PurchaseBridge"))
   PurchaseBridge.start(screen.Intent)            -- prompts Robux purchases (1 s cooldown); the server grants
   screen.Intent:Connect(function(name, args, elementId)
   	if name == "Buy" then BuyRemote:FireServer(args.itemId) -- server validates and charges
   	elseif name == "Select" then print("selected", elementId) end
   end)
   ```
9. **Playtest** in Studio (playground or your place) and record what was and was not checked.

## Phrase -> element mapping

| Request says | Element |
|---|---|
| "featured", "starter pack", "limited offer", "bundle" | `banner` (+ `badge` sale, `timer`) |
| "products", "items", "gamepasses", "cards" | `product` inside a `grid` |
| "coin / gem packs", "+50%" | `product` with `badge {kind:"bonus", text:"+50%"}` |
| "best value", "most popular" | `badge {kind:"best"}` and `gold` palette |
| "can gift" | `product.gift: true` |
| "section", "category title" | `heading` (with divider) |
| "currency counter", "cash", "gems" | `currency` with `bind` (`Stats.Cash`) and `plus` |
| "level", "XP bar" | `level` |
| "progress", "storage", "quest bar" | `progress` or `listRow.progress` |
| "countdown", "ends in" | `timer` |
| "menu buttons", "side buttons" | `iconButton` in a HUD rail or `grid` |
| "buttons in a row", "x1 x3 auto" | `row` of `button` |
| "daily rewards", "day 1..7" | `dayCard` in a `grid` |
| "upgrades", "quests", "leaderboard rows" | `listRow` |
| "settings", "volume", "on/off" | `slider`, `toggle`, `dropdown` |
| "reward popup", "you got" | `kind: "popup"`, `popup.variant: "reward"` |
| "are you sure", "confirm purchase" | `popup.variant: "confirm"` with `price` |

## Example 1: pet sim shop, six products and a featured starter pack

```json
{ "spec": 1, "id": "PetShop", "kind": "window", "style": "cartoon",
  "window": { "title": "SHOP", "headerPalette": "red", "sizeClass": "lg" },
  "body": [
    { "type": "banner", "id": "starterPack", "palette": "teal", "icon": "star-color", "title": "STARTER PACK",
      "subtitle": "3 rare pets and 5,000 coins", "price": { "kind": "robux", "amount": 99, "productId": 0 },
      "badge": { "kind": "sale", "text": "-60%" }, "timer": 86400 },
    { "type": "heading", "text": "GAMEPASSES" },
    { "type": "grid", "columns": { "phone": 2, "tablet": 3, "desktop": 3 }, "cellAspect": 1.3, "items": [
      { "type": "product", "id": "tripleHatch", "palette": "purple", "icon": "egg-color", "title": "TRIPLE HATCH",
        "price": { "kind": "robux", "amount": 249, "gamePassId": 0 }, "gift": true },
      { "type": "product", "id": "luckyPaw", "palette": "pink", "icon": "paw-color", "title": "LUCKY PAW",
        "price": { "kind": "robux", "amount": 199, "gamePassId": 0 }, "gift": true },
      { "type": "product", "id": "cashX2", "palette": "green", "icon": "cash-color", "title": "x2 CASH",
        "price": { "kind": "robux", "amount": 299, "gamePassId": 0 }, "gift": true } ] },
    { "type": "heading", "text": "GEMS" },
    { "type": "grid", "columns": { "phone": 2, "tablet": 3, "desktop": 3 }, "cellAspect": 1.3, "items": [
      { "type": "product", "id": "gems500", "palette": "blue", "icon": "gem-color", "title": "500 GEMS",
        "price": { "kind": "robux", "amount": 49, "productId": 0 } },
      { "type": "product", "id": "gems3000", "palette": "orange", "icon": "gem-stack-color", "title": "3,000 GEMS",
        "price": { "kind": "robux", "amount": 249, "productId": 0 }, "badge": { "kind": "bonus", "text": "+20%" } },
      { "type": "product", "id": "gems15000", "palette": "gold", "icon": "chest-color", "title": "15,000 GEMS",
        "price": { "kind": "robux", "amount": 999, "productId": 0 }, "badge": { "kind": "best" } } ] } ] }
```

The bonus percentages must be true against the 500-gem base rate (see `roblox-shop-builder`).

## Example 2: HUD with currencies, level progress and menu buttons

```json
{ "spec": 1, "id": "GameHud", "kind": "hud", "style": "cartoon",
  "rails": {
    "topLeft": [
      { "type": "currency", "id": "cash", "icon": "cash-color", "bind": "Stats.Cash", "palette": "green", "plus": true, "action": "OpenPanel:Shop" },
      { "type": "currency", "id": "gems", "icon": "gem-color", "bind": "Stats.Gems", "palette": "purple", "plus": true, "action": "OpenPanel:Shop" } ],
    "bottom": [ { "type": "level", "id": "level", "bind": "Stats.Level", "max": 100 } ],
    "left": [
      { "type": "iconButton", "id": "inventory", "icon": "backpack-color", "label": "Items", "palette": "blue", "action": "OpenPanel:Inventory" },
      { "type": "iconButton", "id": "teleport", "icon": "teleport-color", "label": "Teleport", "palette": "teal", "action": "OpenPanel:Teleport" },
      { "type": "iconButton", "id": "settings", "icon": "settings-color", "label": "Settings", "palette": "gray", "action": "OpenPanel:Settings" } ] } }
```

`bind` paths follow the Store (`UrkUI.Store.fromAttributes(player, "Stats")` mirrors player attributes). The server sets the attributes; the HUD only displays them.

## Example 3: 7-day daily rewards with a premium day and claim animation

```json
{ "spec": 1, "id": "Daily", "kind": "window", "style": "cartoon",
  "window": { "title": "DAILY REWARDS", "headerPalette": "orange", "sizeClass": "md" },
  "body": [
    { "type": "text", "text": "Come back every day. Day 7 is huge!", "size": "label" },
    { "type": "grid", "columns": { "phone": 3, "tablet": 4, "desktop": 4 }, "cellAspect": 1.2, "gap": "sm", "items": [
      { "type": "dayCard", "id": "day1", "day": 1, "reward": "100 Coins", "icon": "coin-color", "state": "claimed" },
      { "type": "dayCard", "id": "day2", "day": 2, "reward": "Small Egg", "icon": "egg-color", "state": "today", "palette": "green" },
      { "type": "dayCard", "id": "day3", "day": 3, "reward": "250 Coins", "icon": "coins-color" },
      { "type": "dayCard", "id": "day4", "day": 4, "reward": "5 Gems", "icon": "gem-color" },
      { "type": "dayCard", "id": "day5", "day": 5, "reward": "Lucky Potion", "icon": "potion-color" },
      { "type": "dayCard", "id": "day6", "day": 6, "reward": "1,000 Coins", "icon": "money-bag-color" },
      { "type": "dayCard", "id": "day7", "day": 7, "reward": "Mythic Chest", "icon": "chest-color", "premium": true, "palette": "gold" } ] },
    { "type": "button", "id": "claim", "text": "CLAIM", "kind": "buy", "action": "Fire:ClaimDaily" } ] }
```

Claim flow: the button fires `Intent("ClaimDaily")`; the server (`Systems/DailyRewards`) decides and grants; on success the client calls `screen:update("day2", { state = "claimed" })` and shows the reward popup (`RewardPopup.json` or a `RewardPopup` component), whose `reveal` preset animates the icon. Under reduced motion `Runtime/Motion.play` jumps to the final frame, so the claim still reads.

## Conventions

- One spec per screen; file name = `id`. Ids: letters, digits, `_`, `-`; unique across the screen.
- Titles in capitals, under 20 characters ideally (limit 60); subtitles at most 90.
- Never invent element types or fields: unknown fields are errors by design.
- Robux ids stay `0` in templates; replace before publishing and keep them in config.

## Common mistakes

- Using glyph names (`coin`) on cards: allowed, but cards should use `coin-color`.
- Robux price with both `productId` and `gamePassId`, or neither.
- Granting anything from `screen.Intent` on the client.
- Copying a template and forgetting to change `id` (two ScreenGuis with the same name).
- Too many elements: over 200 or nesting deeper than 5 fails validation; split into tabs or screens.

## Validation

```bash
python3 $URK/urk.py ui validate src/shared/UrkScreens/*.json
python3 $URK/urk.py ui preview src/shared/UrkScreens/MyShop.json --open
```

Then a Studio playtest: window size per breakpoint, binds update live, every intent arrives once. Report preview checks and Studio checks separately.

## Limitations

- The preview is an approximation; the Builder output is only proven by a Studio playtest.
- Builder and Game components are Roblox code without automated runtime tests here.
- Layout options are limited to the element table; bespoke layouts need code.
