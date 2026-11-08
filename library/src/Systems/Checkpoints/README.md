# Checkpoints

Stage progression for obbies, races and level-based games. Progress only goes up, and touching a checkpoint more than `maxSkip` stages ahead is refused, so a teleport exploit or a gap in the course cannot skip stages. Characters respawn at the right checkpoint, hazards kill or damage, and progress saves through an injected store.

| File | Runs on | Role |
| --- | --- | --- |
| `CheckpointsLogic.luau` | anywhere (pure) | touch rules, skips, respawn resolution, cooldowns, persistence |
| `CheckpointsServer.luau` | server | CollectionService tags, respawning, hazards, leaderstats, store |

## Setting up the place

- Tag each checkpoint part `UrkCheckpoint` and give it a whole-number `Stage` attribute (1 is the start).
- Tag kill parts `UrkHazard`. Add a number `Damage` attribute to deal damage instead of killing.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `CheckpointsLogic.resolveConfig(overrides?)` | `Config` | `startStage`, `maxStage`, `maxSkip`, `respawnAtLastTouched` |
| `CheckpointsLogic.new(config)` | `{ stage, highest }` | |
| `CheckpointsLogic.touch(state, stage, config)` | result | `"advanced"`, `"moved"` (respawn point changed), `"same"`, `"behind"`, `"skipped"`, `"invalid"` |
| `grantSkip(state, config)` | ok | one stage forward, for a purchased skip |
| `reset`, `isComplete`, `percent` | | |
| `resolveSpawn(stage, partsByStage)` | `stage?, part?` | nearest checkpoint at or below the stage |
| `cooldownReady(lastAt?, now, cooldown)` | boolean | touch debounce |
| `serialize(state)` / `deserialize(data, config)` | | invalid data falls back to the start; values are capped |
| `CheckpointsServer.new(options?)` | `Service` | `getState`, `grantSkip`, `reset`, `respawn`, `reached`, `destroy` |

## Config

| Key | Default | Meaning |
| --- | --- | --- |
| `config.startStage` | 1 | first stage |
| `config.maxStage` | highest tagged stage | last stage |
| `config.maxSkip` | 1 | how far ahead a touch may be |
| `config.respawnAtLastTouched` | false | touching an earlier checkpoint moves the respawn point back |
| `store` | nil | `{ load(player) -> data?, save(player, data) }` |
| `checkpointTag` / `hazardTag` | `"UrkCheckpoint"` / `"UrkHazard"` | tags |
| `spawnOffset` | `Vector3.new(0, 4, 0)` | added to the checkpoint position |
| `touchCooldown` | 0.5 | seconds per player and part |
| `leaderstats` | true | create `leaderstats.Stage` |

## Example

```lua
local checkpoints = CheckpointsServer.new({
	store = {
		load = function(player) return profiles[player].Data.obby end,
		save = function(player, data) profiles[player].Data.obby = data end,
	},
})
checkpoints.reached:Connect(function(player, stage, result)
	if result == "advanced" then Sounds.play(player, "Checkpoint") end
end)
-- after a skip-stage developer product purchase is confirmed:
checkpoints:grantSkip(player)
```

## Events

`service.reached(player, stage, result)` on every accepted touch (after the cooldown), including `"skipped"` and `"behind"` so you can show hints. Player attributes `Stage` (highest) and `RespawnStage`.

## Persistence shape

`{ stage = number, highest = number }`.

## Limitations

- Touched events come from the physics owner; a client can fake touches of nearby parts, which is why skip protection exists. It cannot stop a player teleporting to the very next checkpoint.
- Saving happens on leave and on `destroy`; save more often through your store if you need it.
- Respawn waits up to 5 seconds for `HumanoidRootPart`.

## Needs a Studio playtest

Tagging, Touched handling, respawn placement, hazards and leaderstats are unverified outside Studio. Lune tests cover `CheckpointsLogic`.
