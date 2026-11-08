# Inventory

Slot inventory with an item registry, stacking, a capacity, a hotbar, filtering and sorting. `InventoryLogic` is pure and immutable: every call returns a new inventory, so a caller (Crafting, Shop, Pickup) can try an operation and commit only when the whole transaction succeeds. `InventoryServer` owns one inventory per player, validates and rate-limits client intents and replicates a compact view to the owner. `InventoryClient` reads that view and sends intents.

## Files

| File | Runs on | Role |
| --- | --- | --- |
| `InventoryLogic.luau` | anywhere | registry, slots, stacking, hotbar, list/sort, serialize |
| `InventoryServer.luau` | server | per-player state, remotes, signals, store hooks |
| `InventoryClient.luau` | client | latest view, intents |

## InventoryLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newRegistry(defs)` | `Registry` | defs: `{ id, maxStack? = 1, category? = "misc", tags? }`. Errors on duplicates or bad values. |
| `getDef(registry, id)` / `hasTag(registry, id, tag)` | `ItemDef?` / `boolean` | |
| `new(capacity, hotbarSize?)` | `Inventory` | capacity 1..1000; hotbar starts mapped to slots 1..hotbarSize |
| `count(inv, id)`, `usedSlots(inv)`, `freeSlots(inv)`, `slot(inv, i)` | numbers / `Stack?` | |
| `spaceFor(inv, registry, id)`, `canAdd(inv, registry, id, n)` | `number`, `boolean` | unknown items never fit |
| `add(inv, registry, id, n)` | `(Inventory, leftover)` | tops up stacks in slot order, then fills empty slots. Errors if `n` is not a positive integer. |
| `remove(inv, id, n)` | `(Inventory?, reason?)` | all or nothing, highest slots first |
| `removeAt(inv, index, n?)` | `(Inventory?, Stack?, reason?)` | used by Drop |
| `move(inv, registry, from, to, n?)` | `(Inventory?, reason?)` | empty target: move or split; same item: merge to maxStack; other item: swap whole stacks |
| `hotbarSize`, `hotbarStack(inv, pos)`, `selectedStack(inv)` | | |
| `selectHotbar(inv, pos?)` | `(Inventory?, reason?)` | `nil` clears the selection |
| `assignHotbar(inv, pos, index)` | `(Inventory?, reason?)` | keeps each slot on at most one hotbar position |
| `swapHotbar(inv, a, b)` | `(Inventory?, reason?)` | the selection follows the moved position |
| `list(inv, registry, filter?)` | `{ Entry }` | filter: `{ category?, tag?, id? }` |
| `sort(inv, registry, by?)` | `Inventory` | `"category"` (default), `"id"`, `"count"`; merges partial stacks |
| `serialize(inv)` / `view(inv)` | `Saved` | `{ v, slots = { { i, id, n } }, hotbar, sel }` |
| `deserialize(raw, registry, capacity, hotbarSize?)` | `Inventory` | drops unknown items and malformed entries, clamps to maxStack |

Reasons: `"invalid slot"`, `"empty slot"`, `"same slot"`, `"invalid amount"`, `"not enough items"`, `"stack full"`, `"cannot split onto another item"`, `"invalid hotbar position"`.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `registry` | required | from `newRegistry` |
| `capacity` | `30` | slots per player |
| `hotbarSize` | `9` | hotbar positions |
| `store` | `nil` | `{ load(userId) -> any?, save(userId, data) -> boolean }` |
| `remoteFolderName` | `"URK_Inventory"` | folder in ReplicatedStorage |
| `allowDrop` | `true` | accept Drop intents |
| `onDrop` | `nil` | `(player, stack)`, for example spawn a Pickup item |
| `rateLimit` | `{ capacity = 10, refillPerSecond = 5 }` | per player, shared by all intents |
| `autoLoad` | `true` | load on join, save on leave and on BindToClose |

Server methods: `get(player)`, `set(player, inv)`, `update(player, fn)`, `give(player, id, n) -> leftover`, `take(player, id, n) -> boolean`, `loadPlayer`, `savePlayer`, `unloadPlayer`, `destroy`.

Remotes (client to server): `MoveSlot(from, to, amount?)`, `SelectHotbar(position?)`, `AssignHotbar(position, slot)`, `Drop(slot, amount?)`, `RequestSync()`. Server to owner: `Sync(view)`. Every argument is checked with `Util/Validate`; invalid or rate-limited calls are ignored.

## Events

`Changed(player, inventory)`, `Loaded(player, inventory)`, `Dropped(player, stack)` (Util/Signal).

## Example

```luau
-- ServerScriptService/Inventory.server.luau
local Kit = game:GetService("ReplicatedStorage").UltimateRobloxKit
local InventoryLogic = require(Kit.Systems.Inventory.InventoryLogic)
local InventoryServer = require(Kit.Systems.Inventory.InventoryServer)

local registry = InventoryLogic.newRegistry({
	{ id = "Apple", maxStack = 20, category = "food", tags = { "edible" } },
	{ id = "Sword", category = "weapon", tags = { "tool" } },
})

local inventory = InventoryServer.new({ registry = registry, capacity = 24, hotbarSize = 6 })
inventory.Changed:Connect(function(player, inv)
	print(player.Name, "has", InventoryLogic.count(inv, "Apple"), "apples")
end)
-- Later: inventory:give(player, "Apple", 5) returns how many did not fit.
```

```luau
-- StarterPlayerScripts/Inventory.client.luau
local InventoryClient = require(Kit.Systems.Inventory.InventoryClient)
local client = InventoryClient.start()
client.Changed:Connect(function(view) --[[ redraw UI from view.slots and view.hotbar ]] end)
client:selectHotbar(1)
```

## Persistence shape

```luau
{ v = 1, slots = { { i = 1, id = "Apple", n = 12 } }, hotbar = { 1, 2, 3 }, sel = 1 }
```

With SaveData, store `InventoryLogic.serialize(inv)` inside the player record and call `deserialize` on load instead of passing `store`.

## Limitations

- One registry per server; changing `maxStack` later clamps saved stacks on load.
- No per-item metadata (durability, enchantments). Store it in a parallel table keyed by slot if needed.
- Sorting keeps hotbar slot indices, so a sort can change what the hotbar shows.
- Replication sends the whole view on each change. Fine for tens of slots; use diffs for hundreds.

## Needs a Studio playtest

Remote wiring, `Sync` arrival on join, Drop with `onDrop`, the BindToClose flush and save timing with a real store. Lune covers `InventoryLogic` only.
