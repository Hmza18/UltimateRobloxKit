---
name: roblox-simulator-tycoon
description: Simulator and tycoon systems in Roblox - collect, sell, upgrade, rebirth loops with formulas, pets and eggs with disclosed odds and PolicyService checks, tycoon plot claiming, droppers, conveyors and collectors, purchase buttons with ownership validation, saving tycoon progress and capped idle earnings. Use when building a simulator, tycoon, idle or clicker experience, egg hatching, rebirths or plot ownership.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [simulator, tycoon, rebirth, dropper, conveyor, egg hatch, hatching, eggs, pets, rarities, world unlock, pet system, plot claim, idle earnings, clicker]
  depends: [roblox-inventory-economy, roblox-data-persistence, roblox-security-anti-exploit, monetization-economy-design]
---

# Roblox simulators and tycoons

## When to use

- Simulator loops: click or collect, fill a backpack, sell, buy upgrades, rebirth for a multiplier.
- Pet and egg systems, including paid ones.
- Tycoons: claimable plots, droppers, conveyors, collectors, buy buttons that unlock the next stage.
- Offline (idle) earnings.

When not to use: generic inventory, currency and Developer Product receipts are `roblox-inventory-economy`; pricing and fairness decisions are `monetization-economy-design`; save layer is `roblox-data-persistence`.

## Inputs

- Currencies (soft only, or soft plus Robux products), the upgrade list with base costs, and target session pacing.
- Plot count per server (match to max players), plot models in `ServerStorage`.
- Egg tables (pet, weight) and whether any egg is bought with Robux, directly or indirectly.

## Workflow

1. **Server owns every number.** Clients send intents (`Collect`, `Sell`, `Buy("Dropper2")`, `Hatch("ForestEgg")`); the server validates and changes values. Client UI only displays replicated values (attributes or a state remote).
2. **Core loop formulas** (one `Formulas` module, unit-tested):
   - Upgrade cost: `cost(n) = floor(base * growth^n)`, `growth` 1.12-1.25.
   - Rebirth requirement: `req(r) = floor(baseReq * 2.5^r)`; rebirth multiplier `1 + 0.5 * r` (additive feels fairer than multiplicative stacking).
   - Income per collect: `perCollect * upgradeMultiplier * (1 + 0.5 * rebirths)`.
   - Use `math.floor` and store counts as integers; for very large values store mantissa/exponent or log10 rather than float drift past 2^53.
3. **Eggs with disclosed odds.** Odds live in data and are shown in the hatch UI as exact percentages computed from the same table the server rolls. Roll on the server with a per-server `Random.new()`.
4. **Paid random items.** If an egg costs Robux (or a currency bought with Robux), Roblox policy requires showing odds before purchase, and some regions restrict paid random items. Check `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` and hide or disable the paid option for those players. No pity-timer hiding, no fake near-misses, no "limited time" pressure loops.
5. **Tycoon plots.** On join or on touching a claim pad, give the first free plot: set `plot:SetAttribute("OwnerUserId", userId)`. Release on `PlayerRemoving` and reset the plot. Every purchase checks the attribute against the caller.
6. **Droppers and collectors.** The server spawns drops at a fixed interval per owned dropper, stores the value as an attribute, and the collector's `Touched` adds value only for drops whose `OwnerUserId` matches the plot owner. Cap live drops per plot (for example 40) and destroy old ones, or skip physical drops entirely and credit income on a timer with a visual-only client drop.
7. **Buy buttons** show only when prerequisites are owned; on press the server checks owner, prerequisite, price, then deducts and unlocks, then saves the purchased id list.
8. **Saving tycoons.** Save the list of purchased item ids and currency, not part positions. Rebuild the plot on load by replaying purchases in order.
9. **Idle earnings.** On load: `elapsed = math.clamp(os.time() - lastSeen, 0, CAP_SECONDS)`; `offline = floor(elapsed * incomePerSecond * OFFLINE_RATE)` with a cap (for example 8 hours, 50 percent rate). Show the amount earned; never sell removing the cap as a pressure tactic.

### Egg hatch and tycoon purchase (server)

```lua
--!strict
-- ServerScriptService/Sim/SimService.luau (ModuleScript)
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Eggs = require(ReplicatedStorage.Shared.EggTables) -- { [eggId]: { price: number, paidWithRobux: boolean, pets: { { id: string, weight: number } } } }
local Items = require(ReplicatedStorage.Shared.TycoonItems) -- { [itemId]: { price: number, requires: string? } }

export type Profile = { coins: number, pets: { string }, purchased: { [string]: boolean } }

local SimService = {}
local rng = Random.new()
local lastAction: { [Player]: number } = {}

local function rateLimited(player: Player, interval: number): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < interval then
		return true
	end
	lastAction[player] = now
	return false
end

function SimService.oddsFor(eggId: string): { { id: string, percent: number } }
	local egg = Eggs[eggId]
	local total = 0
	for _, entry in egg.pets do
		total += entry.weight
	end
	local out = {}
	for _, entry in egg.pets do
		table.insert(out, { id = entry.id, percent = entry.weight / total * 100 }) -- shown in UI as-is
	end
	return out
end

function SimService.roll(eggId: string, random: Random): string
	local egg = Eggs[eggId]
	local total = 0
	for _, entry in egg.pets do
		total += entry.weight
	end
	local pick = random:NextNumber(0, total)
	for _, entry in egg.pets do
		pick -= entry.weight
		if pick <= 0 then
			return entry.id
		end
	end
	return egg.pets[#egg.pets].id
end

function SimService.hatch(player: Player, profile: Profile, eggId: unknown): string?
	if typeof(eggId) ~= "string" or Eggs[eggId] == nil or rateLimited(player, 0.5) then
		return nil
	end
	local egg = Eggs[eggId]
	if egg.paidWithRobux then
		return nil -- Robux eggs are granted from ProcessReceipt, never from this remote
	end
	if profile.coins < egg.price then
		return nil
	end
	profile.coins -= egg.price
	local pet = SimService.roll(eggId, rng)
	table.insert(profile.pets, pet)
	return pet
end

function SimService.buyItem(player: Player, profile: Profile, plot: Model, itemId: unknown): boolean
	if typeof(itemId) ~= "string" or rateLimited(player, 0.2) then
		return false
	end
	local item = Items[itemId]
	if item == nil or profile.purchased[itemId] then
		return false
	end
	if plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return false -- not your plot
	end
	if item.requires and not profile.purchased[item.requires] then
		return false
	end
	if profile.coins < item.price then
		return false
	end
	profile.coins -= item.price
	profile.purchased[itemId] = true
	return true -- caller unlocks the model and marks the profile dirty
end

-- Call before showing or prompting any Robux egg. Fails closed when the policy is unknown.
function SimService.canOfferPaidRandom(player: Player): boolean
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	return ok and not policy.ArePaidRandomItemsRestricted
end

function SimService.cleanup(player: Player)
	lastAction[player] = nil
end

return SimService
```

Plot claiming, dropper loop with a drop cap, and offline earnings code: [references/tycoon-systems.md](references/tycoon-systems.md).

## Outputs

- `Formulas`, `SimService`, `PlotService` modules; `EggTables` and `TycoonItems` data; hatch UI that renders `oddsFor` output.

## Validation

1. Lune tests: `roll` over 1,000,000 seeded trials lands within 0.2 percentage points of `oddsFor`; cost formulas are monotonic; idle earnings respect the cap with a `lastSeen` in the future (clock skew) giving 0.
2. Studio **Clients and Servers** with 2 players: player B cannot buy on player A's plot (fire the remote manually from B's command bar).
3. Rejoin: plot rebuilds from saved purchases in the same order.
4. Check PolicyService behavior on a published test place; Studio returns default policy values.

## Pitfalls

- **Odds in UI differ from server table**: compute display from the same module the server rolls.
- **Touched-based collection with no owner check**: other players steal drops. Check `OwnerUserId` on both the drop and the plot.
- **Unbounded drops**: thousands of parts per plot. Cap and recycle, or go timer-based.
- **Float overflow** in late-game numbers: formatting shows `inf` or `1e+308`. Plan big-number storage early.
- **Saving every coin change**: DataStore throttling. Save on interval and on leave.
- **Plot not released** on leave: server fills up with dead plots.
- **Rebirth resets that also wipe Robux purchases**: never reset paid items.

## Limitations

- Balance numbers are starting points; real pacing needs playtest data and analytics.
- Paid random item rules are platform policy and can change; verify current Roblox policy and PolicyService fields in creator docs before shipping.
- Physics-based droppers behave differently under heavy server load; the timer-based alternative is more predictable.
