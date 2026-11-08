# Pets

Eggs, hatching, pets and fusing for simulator games. `PetsLogic` is pure (the random source is injected) and immutable. `PetsServer` validates intents, charges egg costs through `CurrencyServer:spendMany`, rolls with a server `Random` and syncs the pet list.

## Config

```luau
local config = PetsLogic.validateConfig({
	rarities = { { name = "Common", rank = 1 }, { name = "Rare", rank = 2 }, { name = "Legendary", rank = 3 } },
	pets = {
		Dog = { rarity = "Common", multiplier = 1 },
		Cat = { rarity = "Rare", multiplier = 3 },
		Dragon = { rarity = "Legendary", multiplier = 10, tradeable = false },
	},
	eggs = {
		Basic = {
			cost = { Coins = 100 },
			entries = { { pet = "Dog", weight = 90 }, { pet = "Cat", weight = 9 }, { pet = "Dragon", weight = 1 } },
			pity = { rarity = "Legendary", after = 200 }, -- guaranteed Legendary on the 200th miss
		},
	},
	capacity = 100, -- default 100
	equipSlots = 3, -- default 3
	-- tiers default: Normal x1, Golden x2.5 (fuse 5), Rainbow x6 (fuse 5)
})
```

## PetsLogic API

| Function | Notes |
| --- | --- |
| `hatch(config, state, egg, amount, rng, luck?)` | 1..10 at once; pity and luck applied; does not charge |
| `odds(config, egg, luck?)` | `{ pet, chance, rarity }` for the egg preview; chances sum to 1 |
| `weights(config, egg, luck?)` | luck multiplies every entry above the egg's most common rarity |
| `give(config, state, kind, tier?)` | rewards, codes |
| `equip`, `unequip`, `equipBest`, `isEquipped` | slots from `equipSlots` |
| `setLocked`, `delete(state, ids)` | locked pets cannot be deleted, fused or traded |
| `fuse(config, state, ids)` | N matching pets (kind and tier) become one of the next tier |
| `multiplierOf`, `totalMultiplier` | `1 + sum(equipped base x tier)` |
| `isTradeable`, `exchange(config, state, give, receive)` | used by Trading; received pets get fresh ids |
| `serialize`, `deserialize(config, raw)` | drops unknown kinds, duplicate ids and bad tiers; clamps counters |

Results: `{ ok, reason?, state }` (and `pets` for hatch, give, fuse, exchange). On failure `state` is the input.

## Server

`PetsServer.new({ pets, store?, currency?, getLuck?, canUseEgg?, remoteFolderName? = "URK_Pets", rateLimit?, random? })`

Remotes in `ReplicatedStorage.URK_Pets`: `Hatch(egg, amount)`, `Equip(id)`, `Unequip(id)`, `EquipBest()`, `Lock(id, locked)`, `Delete(ids)`, `Fuse(ids)`; server to client `Sync(saved)` and `Hatched(egg, pets)`. Methods: `getState`, `setState`, `multiplier(player)`, `hatch(player, egg, amount)`, `destroy`. Signals: `Hatched`, `Changed`.

The hatch order is roll, then charge, then commit, so a failed charge changes nothing. Publish your odds in game: Roblox requires that paid random items show their odds.
