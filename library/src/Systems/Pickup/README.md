# Pickup

World item pickup. Items lie in the world as parts with a ProximityPrompt (or a touch trigger). The server checks distance, an ownership window for dropped items, despawn timers and a per-player cooldown, then moves the items into an inventory through an injected `give(player, itemId, count) -> leftover`. Leftovers stay on the ground.

`PickupLogic` is pure (positions are `{ x, y, z }`, time is passed in). Its functions modify the `State` you pass and return explicit results.

## PickupLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `new(overrides?)` | `State` | overrides any key of the config below; errors on negative or non-finite values |
| `spawn(state, itemId, count, position, now, ownerId?)` | `(uid?, reason?)` | `ownerId` starts the ownership window |
| `get(state, uid)` / `remove(state, uid)` | `WorldItem?` / `boolean` | |
| `canPickup(state, uid, userId, position, now)` | `(boolean, reason?)` | checks without changing anything |
| `pickup(state, uid, userId, position, now, give)` | `PickupResult` | `give(itemId, count) -> leftover` |
| `expire(state, now)` | `{ uid }` | removes despawned items, ascending uids |
| `pruneCooldowns(state, now)` | | forgets finished cooldowns |
| `nearby(state, position, radius)` | `{ WorldItem }` | nearest first |
| `distance(a, b)` | `number` | |

`PickupResult = { ok, reason?, taken, remaining, removed }`. Reasons: `"no such item"`, `"invalid input"`, `"despawned"`, `"owned by another player"`, `"too far"`, `"cooldown"`, `"inventory full"`. A full inventory starts no cooldown. A `give` that returns a negative, NaN or non-number leftover counts as "nothing taken".

## Config

| Key | Default | Meaning |
| --- | --- | --- |
| `maxDistance` | `12` | studs between HumanoidRootPart and the item |
| `cooldown` | `0.2` | seconds between pickups per player |
| `ownershipSeconds` | `10` | only the owner can take a dropped item for this long |
| `despawnSeconds` | `120` | `0` keeps items forever |
| `maxCount` | `1000` | largest pile one world item holds |

Server config: `give` (required), `makeVisual(itemId, count) -> BasePart` (default: anchored 1-stud neon part), `parent` (default Folder `Workspace.URK_Pickups`), `usePrompt = true`, `useTouch = false`, `promptText = "Pick up"`, `holdDuration = 0`, `logic` (overrides above), `expireInterval = 1`.

Server methods: `spawnItem(itemId, count, position, owner?) -> uid?`, `removeItem(uid)`, `requestPickup(player, uid)`, `destroy()`. World parts carry attributes `PickupUid`, `ItemId` and `Count`.

## Events

`PickedUp(player, itemId, taken, uid)` and `Despawned(uid, itemId)`.

## Example

```luau
local pickups = PickupServer.new({
	give = function(player, itemId, count)
		return inventory:give(player, itemId, count) -- InventoryServer returns the leftover
	end,
	logic = { despawnSeconds = 60 },
})
pickups:spawnItem("Apple", 3, Vector3.new(0, 3, 0))

-- Drops from the inventory become pickups owned by the dropper for 10 seconds.
local inventory = InventoryServer.new({
	registry = registry,
	onDrop = function(player, stack)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			pickups:spawnItem(stack.id, stack.count, root.Position + root.CFrame.LookVector * 3, player)
		end
	end,
})
```

## Persistence

None. World items are per server and session.

## Limitations

- Time uses `os.clock()` on the server, so timers are per server and reset on restart.
- Ownership uses `UserId`; teams or parties need a custom check before `requestPickup`.
- The default visual is a plain part. Pass `makeVisual` for models (return the primary part, and parent the model yourself if needed).
- Touch pickups fire often; the cooldown and the server distance check limit them.

## Needs a Studio playtest

ProximityPrompt range and triggering, touch pickups, despawn sweeps and visual cleanup. Lune covers `PickupLogic`.
