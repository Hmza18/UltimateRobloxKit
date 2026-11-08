# Resources

Gatherable resource nodes: health, a weighted yield table rolled with an injected random source, respawn timers, tool tiers and per-player gather cooldowns. `ResourcesLogic` is pure (nodes are immutable values; the cooldown table is modified in place). `ResourcesServer` turns CollectionService-tagged instances into nodes, validates hits on the server and gives drops through an injected `give`.

## ResourcesLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newDefs(defs)` | `Defs` | def: `{ kind, maxHealth, yield, rolls? = 1, respawnSeconds? = 30, minTier? = 0, dropOnHit? = false }` |
| `getDef(defs, kind)` | `NodeDef?` | |
| `newNode(defs, kind)` | `Node` | `{ kind, health, respawnAt? }`; errors on unknown kinds |
| `isAvailable(node, now)` | `boolean` | |
| `refresh(defs, node, now)` | `Node` | full health once `respawnAt` has passed |
| `damageFor(def, tool, tierBonus? = 0.25)` | `number` | 0 below `minTier`; `damage * (1 + (tier - minTier) * tierBonus)` |
| `rollYield(def, rng, rolls?)` | `{ Drop }` | weighted pick, count uniform in `min..max`, merged by id |
| `hit(defs, node, tool, now, rng, options?)` | `HitResult` | options: `{ tierBonus?, rolls? }` |
| `ready(cooldowns, key, now)`, `markCooldown(cooldowns, key, now, seconds)`, `pruneCooldowns(cooldowns, now)` | | |
| `seededRng(seed)` | `() -> number` | deterministic source for tests and simulations |

Yield entry: `{ id, weight > 0, min? = 1, max? = min }`. `rng()` must return a number in `[0, 1)`; out-of-range values are clamped and NaN counts as 0.

`HitResult = { ok, reason?, node, damage, depleted, drops }`. Reasons: `"unknown kind"`, `"invalid time"`, `"depleted"`, `"tool tier too low"` (also for tools with no damage).

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `defs`, `give` | required | `give(player, itemId, count) -> leftover` |
| `getTool(player)` | equipped Tool attributes `Tier` and `Damage`, else hands `{ tier = 0, damage = 1 }` | |
| `tag` | `"ResourceNode"` | instances also need a string attribute `Kind` |
| `maxDistance` | `12` | studs from HumanoidRootPart to the node pivot |
| `gatherCooldown` | `0.5` | seconds between hits per player |
| `tierBonus` | `0.25` | |
| `usePrompt` | `true` | adds a ProximityPrompt (on the PrimaryPart for models) |
| `onDepleted(instance)` / `onRespawned(instance)` | hide / show BaseParts | |
| `remoteFolderName` | `"URK_Resources"` | remote `Gather(nodeInstance)` for tool swings |
| `seed` | random | seed for `Random.new` |

Nodes publish attributes `Health` and `Depleted`. Server methods: `gather(player, instance) -> (ok, reason?)`, `getNode(instance)`, `destroy()`.

## Events

`Gathered(player, instance, drops, damage)`, `Depleted(instance, player)`, `Respawned(instance)`.

## Example

```luau
local defs = ResourcesLogic.newDefs({
	{ kind = "OakTree", maxHealth = 30, respawnSeconds = 45,
		yield = { { id = "Log", weight = 9, min = 2, max = 4 }, { id = "Acorn", weight = 1 } } },
	{ kind = "IronOre", maxHealth = 60, minTier = 2, rolls = 2, yield = { { id = "IronOre", weight = 1 } } },
})
local resources = ResourcesServer.new({
	defs = defs,
	give = function(player, itemId, count)
		return inventory:give(player, itemId, count)
	end,
})
-- In Studio: tag a tree model "ResourceNode" and give it the attribute Kind = "OakTree".
```

## Persistence

None. Node state is per server.

## Limitations

- Leftover drops that do not fit are discarded; spawn them with Pickup in `give` if they should stay in the world.
- Node health is shared by everyone (no per-player nodes).
- Timers use `os.clock()` and reset when the server restarts.

## Needs a Studio playtest

Tagging, prompts on models, hide and show on depletion and respawn, the Gather remote from a Tool. Lune covers `ResourcesLogic`.
