# Equipment

Configurable equipment slots, equip and unequip rules with level and tag requirements, and stat aggregation with flat bonuses and multipliers. `EquipmentLogic` is pure and immutable. `EquipmentServer` keeps a loadout per player, validates intents, checks ownership through a callback and applies results through callbacks (stats as attributes by default, Tools through `EquipmentServer.toolEquipper`).

## EquipmentLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newCatalog(slots, items, stacking?)` | `Catalog` | item: `{ id, slot? or slots?, requirements? = { level?, tags? }, stats? = { add?, mul? } }` |
| `new()` | `Loadout` | `{ equipped = { [slot]: itemId } }` |
| `equippedIn(loadout, slot)`, `isEquipped(loadout, itemId)` | | |
| `meetsRequirements(item, context?)` | `(boolean, reason?)` | context: `{ level?, tags? = { [tag]: true } }` |
| `canEquip(catalog, loadout, itemId, context?, slot?)` | `(boolean, reason?)` | |
| `equip(catalog, loadout, itemId, context?, slot?)` | `(Loadout?, slotOrReason, replacedId?)` | no slot: first free slot of the item, else its first slot |
| `unequip(loadout, slot)` | `(Loadout, removedId?)` | |
| `aggregate(catalog, loadout, base?)` | `{ [stat]: number }` | `(base + sum(add)) * multiplier` |
| `invalidSlots(catalog, loadout, context?)` | `{ slot }` | items the wearer no longer qualifies for |
| `serialize(loadout)` / `deserialize(catalog, raw)` | | drops unknown slots, unknown items, wrong slots, duplicates |

Reasons: `"unknown item"`, `"unknown slot"`, `"wrong slot"`, `"already equipped"` (the same item in another slot), `"level too low"`, `"missing tag <tag>"`.

Stacking: `"product"` (default) multiplies multipliers, so 1.1 and 1.2 give 1.32. `"additive"` sums their bonuses, so 1.1 and 1.2 give 1.3.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `catalog` | required | |
| `getContext(player)` | `{}` | level and tags for requirements |
| `hasItem(player, itemId)` | allow all | ownership, for example `InventoryLogic.count(inv, id) > 0` |
| `baseStats(player)` | `{}` | stats before equipment |
| `onEquip(player, slot, itemId)` / `onUnequip(...)` | `nil` | apply and undo visuals or tools |
| `onStats(player, stats)` | sets `Stat_<name>` attributes | |
| `store` | `nil` | `{ load, save }` |
| `remoteFolderName` | `"URK_Equipment"` | remotes `Equip(itemId, slot?)`, `Unequip(slot)`; server to owner `Sync(equipped, stats)` |
| `rateLimit` | `{ capacity = 6, refillPerSecond = 3 }` | |

Server methods: `get`, `equip(player, itemId, slot?) -> (ok, reason?)`, `unequip(player, slot)`, `stats(player)`, `revalidate(player)`, `loadPlayer`, `savePlayer`, `unloadPlayer`, `destroy`. On load, saved items are re-equipped through `equip`, so ownership and requirements are checked again.

## Events

`Equipped(player, slot, itemId, replacedId)`, `Unequipped(player, slot, itemId)`, `StatsChanged(player, stats)`.

## Example

```luau
local catalog = EquipmentLogic.newCatalog({ "head", "body", "weapon" }, {
	{ id = "IronHelm", slot = "head", stats = { add = { defense = 5 } } },
	{ id = "FireStaff", slot = "weapon", requirements = { level = 5, tags = { "mage" } },
		stats = { add = { magic = 12 }, mul = { magic = 1.25 } } },
})
local tools = EquipmentServer.toolEquipper(game:GetService("ServerStorage").Tools)
local equipment = EquipmentServer.new({
	catalog = catalog,
	getContext = function(player)
		return { level = player:GetAttribute("Level") or 1, tags = { [player:GetAttribute("Class") or ""] = true } }
	end,
	hasItem = function(player, itemId)
		local inv = inventory:get(player)
		return inv ~= nil and InventoryLogic.count(inv, itemId) > 0
	end,
	onEquip = tools.onEquip,
	onUnequip = tools.onUnequip,
})
```

## Persistence shape

```luau
{ v = 1, e = { head = "IronHelm", weapon = "FireStaff" } }
```

## Limitations

- An item fits one slot at a time; two-handed items that block a second slot need a custom rule in `hasItem` or a wrapper.
- Stats are numbers only. Humanoid properties (WalkSpeed, MaxHealth) are applied by your `onStats`.
- `toolEquipper` matches Tools by item id name and only manages Tools it created.

## Needs a Studio playtest

Tool cloning into the Backpack, attribute updates, the Sync remote and re-equip on join. Lune covers `EquipmentLogic`.
