# Feedback

One call per gameplay event. An event maps to a recipe: a list of steps that the other visuals modules run (VFX, UI animation, popup, fly-to-counter, camera, sound, object animation, pet reaction, reward reveal, hatch, callback).

Feedback has no gameplay logic and no authority. The server validates and decides; the client only presents:

```lua
-- Server
CollectRemote.OnServerEvent:Connect(function(player, coinId)
	local coin = validateAndCollect(player, coinId) -- your rules
	if coin then
		CoinCollected:FireClient(player, { position = coin.position, amount = coin.value, total = wallet(player) })
	end
end)

-- Client
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

CoinCollected.OnClientEvent:Connect(function(data)
	Visuals.Feedback:Fire("CollectCoin", {
		position = data.position,
		amount = data.amount,
		total = data.total,
		counter = coinLabel,
	})
end)
-- or: Visuals.Feedback.connect(CoinCollected.OnClientEvent, "CollectCoin", function(data) ... return context end)
```

## API

| Function | Use |
|---|---|
| `Feedback.fire(event, context?)` | Runs the recipe. Returns `{ handles, dropped, stop, cancel }`. An unknown event warns once |
| `Feedback.define(event, recipe)` | Defines or replaces one event; errors on an invalid recipe |
| `Feedback.use(pack)` | A built-in pack name or a table of event to recipe; replaces only the events it defines |
| `Feedback.clear(event?)` / `Feedback.reset()` | Remove recipes / restore the Simulator pack |
| `Feedback.events()` / `Feedback.recipe(event)` / `Feedback.packs()` | Inspection |
| `Feedback.connect(signal, event, mapContext?)` | Fires the event when the signal fires; returns a disconnect function |

## Recipes

```lua
Visuals.Feedback:Define("OpenChest", {
	{ kind = "vfx", id = "TreasureOpen", at = "$position" },
	{ kind = "popup", text = "+$amount", at = "$position", throttle = { max = 8, window = 1, coalesce = "amount" } },
	{ kind = "camera", shake = "SoftImpact", when = { field = "rarity", atLeast = "Epic" } },
	{ kind = "sound", cue = "success", delay = 0.1 },
})
```

| Kind | Fields |
|---|---|
| `vfx` | `id`, `at`, `params?`, `attach?` (with `options.duration` to end it) |
| `ui` | `action` = `animate` (default; `preset`, `target`), `countTo` (`target`, `to`), `shine`, `show`, `hide` (`target`), `flash` (`color?`) |
| `popup` | `text`, `at`, `options?` |
| `flyTo` | `from`, `to`, `options?` |
| `camera` | exactly one of `shake`, `cinematic` (+ `target`), `fov`, `zoom`, `focus` |
| `sound` | `cue`, `options?` |
| `object` | `preset`, `target` |
| `pet` | `reaction`, `target` |
| `reward` | `rarity`, `reward` |
| `hatch` | `eggs`, `config?` |
| `call` | `fn(context, step)` |

Every step also takes `delay`, `when`, `throttle` and `optional`.

- **References**: a value of exactly `"$name"` becomes `context.name` with its type kept; inside text, numbers are formatted (`1,250`, `12.5K`, `3M`). Paths work: `"$pet.name"`.
- **Missing context**: a step whose own field refers to a missing value is dropped and listed in `dropped`, unless the field is in `optional`. References inside option tables are simply nil.
- **when**: `{ field, min?, max?, equals?, exists?, atLeast? }` (`atLeast` compares rarities), `{ every = N }` (every Nth fire), or a list that must all hold.
- **throttle**: `{ max, window = 1, coalesce? }`. Over the limit the step is skipped; with `coalesce = "amount"` the amounts are added up and shown by one merged step when the limit allows, so the total shown equals the total earned.

## Packs

`Simulator` (default) defines: Tap, CollectCoin, CollectGem, EquipPet, UnequipPet, HatchEgg, QuestComplete, LevelUp, UnlockArea, UpgradeItem, FeedAnimal, Purchase, Error, RebirthDone, DailyReward, Achievement, RankUp, AbilityUsed, Hit, Dash.

`Minimal` overrides Tap, CollectCoin, CollectGem, LevelUp, RebirthDone, RankUp, AbilityUsed and Hit with fewer steps and no camera movement. `Combat` overrides Hit, AbilityUsed and Dash and adds Critical, ElementHit, AbilityCharge and CooldownReady.

Context fields the Simulator pack reads: `position`, `gui` (the button or panel), `counter` and `total`, `amount`, `pet`, `eggs` (+ `origin`, `speed`, `mode`), `bar`, `text`, `rarity` and `reward`, `character`, and for FeedAnimal `projectile`, `animal`, `travel` (seconds until impact).

UI presets used: BouncyPress, InventorySelect, Pulse, UpgradePulse, Confirm, Error, ToastIn, LevelUpText.

## Performance

Rapid events are throttled per step (Tap: 8 popups, 12 TapPop effects and 15 sounds per second; the shake only every fifth tap). Firing an event with no matching context costs one table walk and creates nothing.

## Not verified in Studio

`FeedbackLogic` is covered by `tests/visuals_feedback.spec.luau` (14 tests), including that every VFX id, shake, cinematic, object preset and pet reaction in the packs is one the contract lists. `Feedback.luau` only forwards to other modules and was NOT run in Studio: whether each forwarded call looks right, and the exact options each module accepts, is `NEEDS MANUAL REVIEW`. A missing module or an unknown preset is skipped silently.
