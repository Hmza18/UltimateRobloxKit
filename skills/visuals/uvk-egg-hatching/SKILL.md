---
name: uvk-egg-hatching
description: The egg hatch cinematic from UltimateVisualsKit's Visuals.Eggs - eleven beats (drop in, wobble that builds, energy, crack, flash, pet appears, rarity celebration, result) scaled by rarity from common to secret, for one, three or many eggs, with auto-hatch mode, skip, cancel, camera push-in and full cleanup, plus idle eggs for the shop. Use when creating an egg opening, hatching animation, legendary hatch, multi-hatch or auto-hatch presentation, or when a hatch feels flat.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [egg hatching, hatching animation, egg hatch, egg opening, hatch cinematic, legendary egg, multi hatch, triple hatch, auto hatch, egg animation, open an egg]
  depends: [uvk-visuals-kit]
---

# UVK egg hatching

A hatch is presentation only. The server rolls the eggs first (`Systems/Pets`), then the client plays what was already decided.

## When to use

- Opening one egg, three eggs or a large batch, with the rarity deciding how big the moment is.
- Auto-hatch loops, and idle motion on eggs standing in a shop.

When not to use: odds, pity, luck and inventory (`roblox-simulator-systems`); a reveal that is not an egg (`uvk-reward-reveals`).

## Inputs

- The server's result: for each egg `{ rarity, name?, pet = Model or function, egg = Model?, isNew?, color? }`. Without a pet model a demo pet is built.
- Whether the player may skip (default yes) and whether the camera may move (default yes).

## Workflow

1. **Ask the server, then hatch what it returns.**

   ```lua
   local results = hatchRemote:InvokeServer(eggId, 3)   -- server validates currency, rolls, saves
   if not results then
   	Visuals.Feedback:Fire("Error", { gui = hatchButton })
   	return
   end

   local hatch = Visuals.Eggs:Hatch({
   	eggs = {
   		{ rarity = "Legendary", name = "Dragon", pet = dragonModel, isNew = true },
   		{ rarity = "Common", name = "Kitten", pet = kittenModel },
   		{ rarity = "Rare", name = "Fox" },             -- no model: a demo pet is built
   	},
   })
   hatch.Revealed:Connect(function(index, entry) end)
   hatch.Completed:Connect(function(results, skipped)
   	refreshInventory()
   end)
   ```

2. **Know the beats.** enter, settle, anticipation, wobble (3 shakes for Common up to 9 for Secret), energy, crack, transition (bloom, and a short hit-stop from Epic), appear (`HatchBurst`, pet springs in, `HappyReaction`), rarity (aura, burst or beam, fireworks and confetti from Legendary), result, finish. Time to the result for one egg runs from about 2.2 s (Common) to 5.7 s (Secret), divided by `speed`.

3. **Pick the mode by count.** One egg is `single`, three is `triple` (85 % of the time), more is `multi` (70 %, at most four shakes each, rarest revealed last). Layout is computed from the count and the aspect ratio.

4. **Auto-hatch** runs about a second per batch with no camera and no input until `next()` returns nil:

   ```lua
   local auto = Visuals.Eggs:Hatch({
   	mode = "auto",
   	eggs = firstBatch,
   	next = function() return nextBatchFromServer() end,
   })
   auto.BatchCompleted:Connect(function(results) end)
   auto.stop()
   ```

5. **Config.** `origin` (CFrame of the stage; default 14 studs in front of the camera), `distance`, `speed`, `camera`, `ui`, `skippable`, `autoContinue`, `hold` (2.5 s), `parent`, `guiParent`, `sounds` (cue to asset id), `onReveal(index, entry)`.

6. **Control.** `hatch.skip()` jumps to the result (a second press dismisses), `hatch.finish()`, `hatch.cancel()` removes everything at once and restores the camera, `hatch.isRunning()`.

7. **Hide the HUD** while a hatch runs and restore it on `Completed`, including after cancel.

8. **Shop eggs.** `local idle = Visuals.Eggs:Idle(shopEggModel)` sways with an occasional hop; `idle.stop()` restores it.

9. **Sounds are opt-in.** Register cues such as `egg.land`, `egg.wobble`, `egg.crack`, `egg.reveal` and `rarity.legendary` with `Visuals.Audio`; unregistered cues are silent.

## Outputs

- A client hatch controller that requests a result, plays `Eggs.hatch` and refreshes state on `Completed`.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_eggs` (plan, layout, wobble, skip). In Studio (`NEEDS MANUAL REVIEW`): stage placement and scale at each aspect ratio, custom egg and pet models with unusual pivots, skip at every beat, cancel mid-hatch, reduced motion, Low quality with a 10-egg hatch on a phone profile, and that the camera is restored after respawn.

## Pitfalls

- **Rolling on the client** or starting the hatch before the server answers: the animation would show a pet the server never granted.
- **Unskippable long hatches.** Players open hundreds of eggs. Keep `skippable = true` and offer auto mode.
- **Same spectacle for every rarity.** The built-in scaling is the point: do not pass `speed` or extra effects that flatten it.
- **Stacking a reward reveal on top.** The hatch already celebrates the rarity; do not also call `Rewards.reveal` for the same pet.
- **Leaving the stage behind.** Always let the hatch finish or call `cancel()`; do not destroy its instances yourself.

## Limitations

- `HatchLogic` is covered by a Lune spec. `Eggs.luau` builds the stage, moves the camera and creates GUI, and was not run in Studio; every visual aspect is unverified.
- The demo egg and demo pet are plain placeholders built from Parts.
- Timings are design targets, not measurements.
