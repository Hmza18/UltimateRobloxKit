---
name: uvk-gameplay-feedback
description: Gameplay feedback with UltimateVisualsKit's Visuals.Feedback - one call per game event (Tap, CollectCoin, CollectGem, LevelUp, QuestComplete, Purchase, Error, EquipPet, UnlockArea and more) that runs a recipe of VFX, UI animation, floating popups, fly-to-counter, camera shake and sound cues, with throttling and amount coalescing for rapid input, conditions, and the Simulator, Minimal and Combat packs. Use when adding tapping or clicking feedback, coin and gem collection effects, level-up or purchase celebrations, floating numbers, or when wiring server events to client visuals.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [gameplay feedback, tapping feedback, tap feedback, click feedback, clicker feedback, coin collection, collect coins effect, collection effects, floating numbers, level up celebration, purchase feedback, feedback event, satisfying, juicy]
  depends: [uvk-visuals-kit]
---

# UVK gameplay feedback

Feedback has no gameplay logic and no authority. The server validates and decides; the client presents.

## When to use

- A game event should produce several coordinated responses (burst, popup, counter roll, shake, sound).
- Rapid events (tapping, collecting) need caps so the screen and the frame time stay sane.

When not to use: a single effect with no event (`uvk-vfx-presets`, `uvk-ui-animation`); a long cinematic (`uvk-egg-hatching`, `uvk-reward-reveals`); combat-specific events (`uvk-combat-visuals`, which builds on this skill).

## Inputs

- The server-to-client event and its payload (position, amount, new total).
- The GuiObjects involved: the tapped button (`gui`), the counter label (`counter`), the XP bar (`bar`).

## Workflow

1. **Find the event.** The built-in events, their steps and the context fields they read are in [references/feedback-events.md](references/feedback-events.md). `Visuals.Feedback.events()` lists them at run time; `Visuals.Feedback.recipe("Tap")` returns one.

2. **Fire from the server's confirmation.**

   ```lua
   -- Server
   CollectRemote.OnServerEvent:Connect(function(player, coinId)
   	local coin = validateAndCollect(player, coinId)        -- your rules
   	if coin then
   		CoinCollected:FireClient(player, { position = coin.position, amount = coin.value, total = wallet(player) })
   	end
   end)

   -- Client
   CoinCollected.OnClientEvent:Connect(function(data)
   	Visuals.Feedback:Fire("CollectCoin", {
   		position = data.position,
   		amount = data.amount,
   		total = data.total,
   		counter = coinLabel,
   	})
   end)
   ```

   Or bind the signal once: `Visuals.Feedback.connect(CoinCollected.OnClientEvent, "CollectCoin", function(data) return { position = data.position, total = data.total, counter = coinLabel } end)` returns a disconnect function.

3. **Tapping.** `Tap` presses the button, shows a coalesced `+amount` popup, plays `TapPop`, shakes on every fifth tap and plays `tap`. Local input may fire it at once for responsiveness, as long as the number shown is one the server will confirm:

   ```lua
   tapButton.Activated:Connect(function()
   	-- position is a world position (Vector3, CFrame, part or model); the popup and TapPop play there
   	Visuals.Feedback:Fire("Tap", { gui = tapButton, position = clickTarget.Position, amount = perTap })
   	TapRemote:FireServer()
   end)
   ```

   Without a `position` the popup and the burst are dropped and the button press and sound still play.

4. **Supply the context the recipe reads.** A step whose own field refers to a missing value is dropped and listed in the result's `dropped`; nothing errors. `fire` returns `{ handles, dropped, stop, cancel }`.

5. **Define or change an event** with a recipe: a list of steps of kind `vfx`, `ui`, `popup`, `flyTo`, `camera`, `sound`, `object`, `pet`, `reward`, `hatch` or `call`.

   ```lua
   Visuals.Feedback:Define("OpenChest", {
   	{ kind = "vfx", id = "TreasureOpen", at = "$position" },
   	{ kind = "popup", text = "+$amount", at = "$position", throttle = { max = 8, window = 1, coalesce = "amount" } },
   	{ kind = "camera", shake = "SoftImpact", when = { field = "rarity", atLeast = "Epic" } },
   	{ kind = "sound", cue = "success", delay = 0.1 },
   })
   ```

   Every step takes `delay`, `when`, `throttle` and `optional`. `"$name"` becomes `context.name`; inside text, numbers are formatted (`1,250`, `12.5K`). `when`: `{ field, min?, max?, equals?, exists?, atLeast? }`, `{ every = N }`, or a list. `throttle`: `{ max, window = 1, coalesce? }`; with `coalesce = "amount"` skipped amounts are added to the next shown step, so the total shown equals the total earned.

6. **Choose a pack.** `Simulator` is the default. `Visuals.Feedback.use("Minimal")` swaps in calmer recipes with no camera movement for calm games and low-end devices; `"Combat"` adds combat events. A table of event to recipe replaces only the events it defines. `Visuals.Feedback.reset()` restores the default.

7. **Register sounds** for the cues you want heard (`tap`, `coin`, `gem`, `success`, `error`, `level.up`): `Visuals:Configure({ sounds = { coin = 1234567890 } })` with your own asset ids. Unregistered cues are silent.

## Outputs

- One `Feedback:Fire` (or `connect`) per event in client code; custom recipes defined once at client start.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_feedback` (resolve, conditions, throttle, coalescing, every preset id in the packs exists). In Studio (`NEEDS MANUAL REVIEW`): tap 15 times a second for 10 s and confirm popups stay under the cap and the frame time holds on a phone profile; check `Visuals:Stats()` returns to zero live effects afterwards.

## Pitfalls

- **Rewards shown before the server confirms.** Only input acknowledgement (the press, the tap pop) may be immediate.
- **Hand-rolled throttles.** Use the step's `throttle`; it also coalesces amounts.
- **A popup per coin** when 30 coins are collected at once. Coalesce, and let the counter roll carry the total.
- **Shake on frequent events.** Use `when = { every = N }` or the `Minimal` pack.
- **Sound with no visual.** Every cue in a recipe should have a visual step beside it.
- **Calling VFX, UI and Camera separately** for the same event in several scripts. Put it in one recipe so it can be tuned and throttled in one place.

## Limitations

- `FeedbackLogic` is covered by a Lune spec. `Feedback.luau` only forwards to the other modules and was not run in Studio; whether each forwarded call looks right is unverified.
- A missing module or an unknown preset in a recipe is skipped silently at run time; `Feedback.define` validates the recipe's shape, not that every id exists.
- Throttle caps protect counts, not frame time on a specific phone. Measure on the device.
