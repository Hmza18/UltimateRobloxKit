---
name: roblox-shop-builder
description: Builds Roblox shops and purchasing end to end - choosing game pass vs developer product vs in-game currency item, shop spec patterns (featured banner, product grid, coin packs with honest bonus percentages), the client PurchaseBridge that prompts MarketplaceService, the server Systems/Shop with idempotent ProcessReceipt and game pass ownership through UserOwnsGamePassAsync, gifting notes, ethical pricing and testing purchases in Studio. Use when adding a store, gamepass shop, coin or gem packs, starter pack, Robux button or gift button, or when purchases fail or grant twice.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [gamepass shop, robux shop, coin packs, gem packs, starter pack, purchasebridge, buy button, gift button, robux button, store screen]
  depends: [roblox-ui-generator, roblox-inventory-economy, roblox-security-anti-exploit]
---

# Roblox shop builder

## Purpose

A shop screen that looks like the reference stores and a purchase path that cannot be exploited or double-granted. UI: a screen spec. Client: `Game/PurchaseBridge` prompts. Server: `Systems/Shop` grants. The client never grants anything.

## When to use (and not)

- Use: gamepass stores, Robux packs, currency shops, starter packs, limited offers, gift buttons.
- Not for inventory data models and currency balancing: `roblox-inventory-economy`. Not for monetisation strategy and price points: `monetization-economy-design`.

## Pick the product type

| Sells | Use | Why |
|---|---|---|
| Permanent perk (x2 cash, VIP, auto hatch) | Game pass | bought once, ownership checked with `UserOwnsGamePassAsync` |
| Consumable (gems, coins, potions, starter pack) | Developer product | repeatable, granted in `ProcessReceipt` |
| Item bought with in-game currency | Currency item in `Systems/Shop` catalog | server prices it, spends from the wallet |

Starter packs are developer products with a server-side "bought once" flag, not game passes, so the contents are granted through the same receipt path.

## Workflow

1. **List the offers** with type, price, contents and id placeholder (`0`).
2. **Write the spec** from `PremiumStore`, `GamepassStore` or `PetSimShop` (`python3 $URK/urk.py ui new PremiumStore --name Store --project .`):
   - featured `banner` (one per screen, the primary action),
   - `heading` + `grid` of game pass `product`s with `gamePassId` and `gift: true` if you implement gifting,
   - `heading` + `grid` of packs with `productId` and `bonus` badges,
   - currency items with `{ "kind": "currency", "amount": 500, "currency": "coin-color" }`.
3. **Validate and preview**: `python3 $URK/urk.py ui validate Store.json`, `python3 $URK/urk.py ui preview Store.json --open`.
4. **Client**: start the bridge once and forward currency buys to the server.
   ```lua
   PurchaseBridge.start(screen.Intent) -- Purchase intents -> PromptProductPurchase / PromptGamePassPurchase
   screen.Intent:Connect(function(name, args)
   	if name == "Buy" then
   		BuyRemote:InvokeServer(args.itemId) -- never send a price; the server looks it up
   	end
   end)
   ```
5. **Server, developer products**: `ShopServer.new({ ..., products = { [123456] = grantGems500 }, store = ... })` binds `MarketplaceService.ProcessReceipt`. `ShopLogic.processReceipt` returns `PurchaseGranted` only after the PurchaseId is committed with the granted effect, and `NotProcessedYet` when the player's data is not loaded, so Roblox retries. Only one script may set `ProcessReceipt`.
6. **Server, game passes**:
   ```luau
   --!strict
   local MarketplaceService = game:GetService("MarketplaceService")
   local Players = game:GetService("Players")
   local PASSES = { [0] = "DoubleCash" } -- gamePassId -> perk; replace 0 with the real id

   local function applyPasses(player: Player)
   	for passId, perk in PASSES do
   		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
   		if ok and owns then
   			player:SetAttribute("Pass_" .. perk, true) -- the HUD and shop read this to show "OWNED"
   		end
   	end
   end
   Players.PlayerAdded:Connect(applyPasses)
   MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
   	if purchased and PASSES[passId] then
   		player:SetAttribute("Pass_" .. PASSES[passId], true)
   	end
   end)
   ```
   Re-check ownership on join; never trust the client's claim of ownership. Then update the card: `screen:update("cashX2", { owned = true })`.
7. **Currency items**: `ShopServer` exposes `URK_Shop.Purchase(itemId, quantity?)`; it recomputes the price, applies limits, stock and sales, pays atomically and refunds if `grant` fails. Rate limited by default.
8. **Test purchases in Studio** (below), then record results.

## Gifting

`gift: true` only draws a purple gift button that fires an intent. Roblox has no built-in gift purchase: implement it yourself, typically a developer product per giftable pass, where the buyer picks a recipient in the same server and your `ProcessReceipt` grant records the gift for that recipient's data (and handles the recipient leaving). Validate the recipient on the server. If you do not implement this, set `gift` to false.

## Ethical pricing (non-negotiable)

- Bonus badges must be true: a pack labelled `+50%` gives 50% more currency per Robux than the base pack. Compute it; write the base rate in a comment in the spec's `note`.
- No fake discounts: a `-60%` sale badge needs a real previous price that was actually charged. Timers must not silently reset.
- Disclose odds for any random reward bought with Robux or with currency bought with Robux (eggs, crates), in the UI, before purchase, as Roblox policy requires.
- Show the price on the button before the prompt; no surprise prompts on hover or on open.
- Never imply a Roblox endorsement or use the Robux logo outside Roblox brand guidelines.

## Conventions

- Ids live in one config module (`ShopConfig`) shared by the spec author and server; specs ship with `0`.
- One primary offer per screen; passes and packs in separate sections.
- Owned passes show `owned: true` (no price, no buy button), not hidden.
- Sale and limit logic lives on the server (`ShopLogic` sales windows), the UI only displays it.

## Common mistakes

- Granting from `screen.Intent` or a client `PromptProductPurchaseFinished`: exploitable and wrong (that event does not mean the receipt was processed).
- Returning `PurchaseGranted` before saving: a crash loses the item and Roblox never retries.
- Two scripts assigning `ProcessReceipt`: the last one wins and the other system stops granting.
- Price sent from the client to the buy remote.
- Checking game pass ownership only at purchase time: players who bought on another server lose the perk.
- Leaving `productId: 0` in a published place: the prompt fails silently with a warning.

## Testing purchases in Studio

- Studio purchase prompts are test purchases: no Robux is charged, but `ProcessReceipt` and `PromptGamePassPurchaseFinished` fire, so the full grant path runs. Real ids must exist and belong to the experience.
- Test: product granted once; leave and rejoin before the save (simulate with a forced `NotProcessedYet`) and confirm the retry grants once; pass ownership persists after rejoin; currency buy with too little money fails with `insufficient funds`; spam the button and see the 1 s bridge cooldown and server rate limit.
- `UserOwnsGamePassAsync` caches; a fresh purchase in the same session is detected through `PromptGamePassPurchaseFinished`.

## Validation

```bash
python3 $URK/urk.py ui validate Store.json
cd library && lune run tests/run   # sys_shop.spec.luau covers ShopLogic and receipts
```

Checklist: every Robux price has exactly one id; bonus maths written down; odds shown for paid random rewards; owned state on join; one ProcessReceipt; Studio test purchases done and reported (or reported as not done).

## Limitations

- Real-money behaviour (refunds, regional pricing, live receipts) cannot be tested in Studio.
- The kit has no gamepass ownership module; the snippet above is the pattern.
- Gifting is not implemented by the kit.
- Roblox monetisation policy changes; check the current creator documentation for paid random items and age rules before launch.
