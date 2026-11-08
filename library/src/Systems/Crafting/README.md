# Crafting

Recipes with inputs, outputs, a duration and an optional station tag; an atomic craft transaction against an inventory value; and a timed job queue driven by an injected clock. `CraftingLogic` is pure and immutable and reaches the inventory through `InventoryOps`, so it works with `InventoryLogic` or with a plain `{ [itemId]: count }` bag. `CraftingServer` wires it to players and remotes.

## CraftingLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newBook(recipes)` | `Book` | recipe: `{ id, inputs, outputs, time? = 0, station? }`; counts are positive integers |
| `getRecipe(book, id)` | `Recipe?` | |
| `bagOps` | `InventoryOps` | for `{ [itemId]: count }` tables, unlimited space |
| `inventoryOps(registry)` | `InventoryOps` | backed by `InventoryLogic` |
| `missing(recipe, inventory, ops, times?)` | `{ ItemCount }` | what is still needed |
| `canCraft(book, id, inventory, ops, context?, times?)` | `(boolean, reason?)` | context: `{ stations? = { [tag]: true } }` |
| `craft(book, id, inventory, ops, context?, times? = 1)` | `CraftResult` | instant; inputs out, outputs in, all or nothing |
| `newQueue(maxJobs? = 10)` | `Queue` | |
| `enqueue(book, queue, id, inventory, ops, context?, now)` | `QueueResult` | takes inputs now; jobs run one after another |
| `collect(book, queue, inventory, ops, now)` | `CollectResult` | delivers finished jobs in order; `blocked` when outputs do not fit |
| `cancel(book, queue, jobId, inventory, ops, now)` | `QueueResult` | refunds inputs, moves later unstarted jobs up |
| `progress(job, now)` | `0..1` | |
| `serializeQueue(queue)` / `deserializeQueue(book, raw, maxJobs?)` | | |

`InventoryOps = { count(inv, id), remove(inv, id, n) -> (inv?, reason?), add(inv, id, n) -> (inv, leftover) }`. Ops must return new values and never modify their input; that is what makes a failed craft leave the inventory untouched.

Reasons: `"unknown recipe"`, `"invalid times"` (not 1..1000), `"station required"`, `"missing items"`, `"no space"`, `"queue full"`, `"invalid time"`, `"no such job"`, `"no space for refund"`.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `book`, `ops` | required | |
| `getInventory(player)` / `setInventory(player, inv)` | required | read and commit the inventory (for example `inventory:get` and `inventory:set`) |
| `getStations(player)` | none | `{ [tag]: true }` for stations in reach, checked on the server |
| `maxJobs` | `10` | |
| `store` | `nil` | persists queues |
| `clock` | `os.time` | wall clock, so queued jobs keep running while the player is offline |
| `collectInterval` | `1` | seconds between automatic deliveries |
| `remoteFolderName` | `"URK_Crafting"` | remotes `Craft(recipeId, times?)`, `Enqueue(recipeId)`, `Cancel(jobId)`; server to owner `Sync(savedQueue)` |
| `rateLimit` | `{ capacity = 6, refillPerSecond = 3 }` | |

Server methods: `craft`, `enqueue`, `cancel`, `collect(player) -> delivered`, `getQueue`, `loadPlayer`, `savePlayer`, `unloadPlayer`, `destroy`.

## Events

`Crafted(player, recipeId, times)`, `JobStarted(player, job)`, `JobCompleted(player, job)`.

## Example

```luau
local book = CraftingLogic.newBook({
	{ id = "Planks", inputs = { { id = "Log", count = 1 } }, outputs = { { id = "Plank", count = 4 } } },
	{ id = "Sword", inputs = { { id = "Plank", count = 2 }, { id = "Iron", count = 3 } },
		outputs = { { id = "Sword", count = 1 } }, time = 30, station = "Anvil" },
})
local crafting = CraftingServer.new({
	book = book,
	ops = CraftingLogic.inventoryOps(registry),
	getInventory = function(player) return inventory:get(player) end,
	setInventory = function(player, inv) inventory:set(player, inv) end,
	getStations = function(player)
		-- Server-side check, for example the nearest part tagged "Anvil" within 10 studs.
		return { Anvil = isNearTag(player, "Anvil", 10) }
	end,
})
```

## Persistence shape

```luau
{ v = 1, n = 7, jobs = { { id = 5, r = "Sword", s = 1767225600, f = 1767225630 } } }
```

## Limitations

- One queue per player, sequential jobs. Parallel stations need one queue per station.
- Station checks are a callback; the module does not find stations in the world.
- Recipes with random outputs are not supported; roll them in your own grant step.
- If outputs do not fit, finished jobs wait in the queue (`blocked`) until there is space.

## Needs a Studio playtest

Remote intents, automatic delivery, queue persistence across sessions and the station callback. Lune covers `CraftingLogic`, including the InventoryLogic integration.
