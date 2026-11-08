---
name: roblox-inventory-economy
description: Inventory, equipment and economy systems for Roblox - item definitions vs item instances, stackable and unique items with ids, server-side transactions, shops with server price lookup, MarketplaceService ProcessReceipt done idempotently, developer products vs game passes, currencies and sinks/sources balance. Use when building an inventory, shop, currency, trading or any Robux purchase flow, or when items duplicate or purchases go missing.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [inventory, equipment, shop, currency, processreceipt, developer product, game pass, marketplaceservice, item duplication, economy sink]
  depends: [roblox-data-persistence, roblox-networking, roblox-security-anti-exploit]
---

# Roblox inventory and economy

## When to use

- Designing what an "item" is, how many a player can hold, and how it is equipped.
- Building a coin shop or a Robux shop (developer products, game passes).
- Players report duplicated items, lost purchases or negative balances.
- Balancing how currency enters (sources) and leaves (sinks) the economy.

When not to use: saving mechanics and session locks (use `roblox-data-persistence`), shop UI (use `roblox-ui-systems`), tycoon/simulator loops (use `roblox-simulator-tycoon`).

## Inputs

- The item catalog: id, kind (stackable, unique, equippable), max stack, slot, price, rarity.
- A working data service (template in `roblox-data-persistence`) with `purchaseHistory` in the profile.
- Developer product ids and game pass ids from the Creator Dashboard (Monetization).

## Workflow

1. **Separate definitions from instances.**
   - Definition: static, shared, frozen config in `ReplicatedStorage.Shared.Config.Items` (name, icon, price, stats). Clients may read it; the server is still authoritative.
   - Instance: what a player owns, in saved data. Stackables are a count by item id; unique items get a generated id and per-copy fields (level, durability).
2. **Store only ids and numbers.** Never save display names, prices or stats in profiles; look them up from definitions so a rebalance applies everywhere.
3. **Write every change as a server transaction**: validate, check, apply all parts, or apply nothing. One function per transaction (`buy`, `sell`, `equip`, `craft`, `trade`).
4. **Clients send intent through validated remotes** (see `roblox-networking`): item id and quantity only. The server looks up the price.
5. **Robux purchases** go through exactly one `MarketplaceService.ProcessReceipt` handler that is idempotent. Copy [references/ProcessReceipt.luau](references/ProcessReceipt.luau).
6. **Game passes** are permanent ownership: check `MarketplaceService:UserOwnsGamePassAsync(userId, passId)` on join (cache the result) and grant immediately on `PromptGamePassPurchaseFinished` when `wasPurchased` is true.
7. **Track sources and sinks** with analytics events so you can see inflation (see `roblox-publishing-liveops`).

### Data model and transactions

```luau
--!strict
-- src/server/Services/InventoryService.luau
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type ItemDef = {
	id: string,
	kind: "stack" | "unique",
	maxStack: number,
	price: number?,        -- nil = not sold in the coin shop
	slot: ("Weapon" | "Hat")?,
}

export type UniqueItem = { uid: string, id: string, level: number }

export type InventoryData = {
	coins: number,
	stacks: { [string]: number },          -- itemId -> count
	uniques: { [string]: UniqueItem },     -- uid -> item
	equipped: { [string]: string },        -- slot -> uid
}

local Items = require(ReplicatedStorage.Shared.Config.Items) :: { [string]: ItemDef }

local InventoryService = {}

local MAX_UNIQUES = 200

function InventoryService.give(inv: InventoryData, itemId: string, qty: number): boolean
	local def = Items[itemId]
	if not def or qty < 1 or qty % 1 ~= 0 then
		return false
	end
	if def.kind == "stack" then
		local current = inv.stacks[itemId] or 0
		if current + qty > def.maxStack then
			return false
		end
		inv.stacks[itemId] = current + qty
		return true
	end
	local count = 0
	for _ in inv.uniques do
		count += 1
	end
	if count + qty > MAX_UNIQUES then
		return false
	end
	for _ = 1, qty do
		local uid = HttpService:GenerateGUID(false)
		inv.uniques[uid] = { uid = uid, id = itemId, level = 1 }
	end
	return true
end

-- All-or-nothing purchase with coins. Checks first, mutates last.
function InventoryService.buy(inv: InventoryData, itemId: string, qty: number): (boolean, string?)
	local def = Items[itemId]
	if not def or def.price == nil then
		return false, "not for sale"
	end
	if qty < 1 or qty > 99 or qty % 1 ~= 0 then
		return false, "bad quantity"
	end
	local cost = def.price * qty
	if inv.coins < cost then
		return false, "not enough coins"
	end
	if not InventoryService.give(inv, itemId, qty) then
		return false, "inventory full"
	end
	inv.coins -= cost      -- only reached when the give succeeded
	return true, nil
end

function InventoryService.equip(inv: InventoryData, uid: string): boolean
	local item = inv.uniques[uid]
	if not item then
		return false            -- client named an item it does not own
	end
	local slot = Items[item.id].slot
	if not slot then
		return false
	end
	inv.equipped[slot] = uid
	return true
end

return InventoryService
```

Because the profile is session-locked and mutated in one server thread without yields between check and apply, these transactions cannot interleave. Do not put a yield (`task.wait`, DataStore call, `InvokeClient`) between the check and the mutation.

### Developer products vs game passes

| | Developer product | Game pass |
| --- | --- | --- |
| Bought | Many times | Once, owned forever |
| Use for | Currency packs, revives, boosts | VIP, 2x coins, extra slots |
| Prompt | `PromptProductPurchase(player, id)` | `PromptGamePassPurchase(player, id)` |
| Grant | `ProcessReceipt` (idempotent, saved) | `UserOwnsGamePassAsync` + `PromptGamePassPurchaseFinished` |
| Needs saving | Yes, the reward and the PurchaseId | No, Roblox tracks ownership |

Read prices for display with `MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)` (or `Enum.InfoType.GamePass`); cache it, it is rate limited.

### ProcessReceipt rules

- Only one script may set `ProcessReceipt`; a second assignment silently replaces the first.
- Return `PurchaseGranted` only after the reward and the PurchaseId are saved together; return `NotProcessedYet` on any failure so Roblox retries.
- If the PurchaseId is already in history, return `PurchaseGranted` without granting again.
- `PromptProductPurchaseFinished` is not proof of payment; never grant from it.

### Sources and sinks

- List every source (quests, drops, idle income, purchases) and sink (shop, upgrades, rebirth resets, consumables, fees on trades).
- Price upgrades on a curve (`base * growth^level`) so sinks scale with income.
- Log `coins earned` and `coins spent` per session; if earned keeps outgrowing spent, prices or sinks need tuning.

## Outputs

- Item definitions module, `InventoryService`, `ReceiptService` (from the reference), shop remotes with validators.

## Validation

1. Studio test purchases: Studio shows a test prompt and does not charge Robux. Buy a developer product, check the reward and that `purchaseHistory` gained the PurchaseId.
2. Force a failure (error in the grant function) and confirm the receipt is retried on rejoin and granted once.
3. Fire the shop remote with a negative quantity, a huge quantity, an unknown id and a uid owned by someone else; nothing changes.
4. Spam buy requests faster than the rate limit; coins never go negative.

## Pitfalls

- **Granting before saving**, then the server crashes: player paid and got nothing, or got it twice after retry. Save reward and PurchaseId together.
- **Two ProcessReceipt handlers** in different scripts: one is silently lost.
- **Client-sent prices or rewards**: always look up on the server.
- **Number item ids as dictionary keys** turn into strings when saved; use string ids everywhere.
- **Unbounded inventories** grow profiles toward the DataStore value size limit; cap counts.
- **Trading without both parties locked**: perform both sides in one server function with checks first, and refuse if either player is mid-transaction.

## Limitations

- Real Robux purchases cannot be tested in Studio; final checks need a live server and real (or team-test) purchases.
- The receipt reference depends on ProfileStore save signals whose exact names should be verified for your installed version.
- Economy balance advice is a starting point; it needs live analytics to tune.
