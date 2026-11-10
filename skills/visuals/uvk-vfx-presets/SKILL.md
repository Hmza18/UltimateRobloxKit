---
name: uvk-vfx-presets
description: World visual effects from UltimateVisualsKit's preset library - 78 data-driven presets in eight categories (rewards, pets, eggs, combat, movement, environment, progression, feeding) played with Visuals:Play and Visuals:Attach, with colour, scale, intensity, rarity and element params, quality budgets and guaranteed cleanup, plus the layer schema for registering or overriding a preset. Use when adding coin bursts, sparkles, auras, trails, confetti, weather, level-up or collection effects, or when authoring a new particle effect for the kit.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [vfx preset, coin burst, collection effect, coin collection, sparkle, confetti, aura effect, level up effect, particle preset, ambient particles, weather effect, original effects, effect library, satisfying effects]
  depends: [uvk-visuals-kit]
---

# UVK VFX presets

## When to use

- Any particle, beam, trail, ring, light or flash effect in the world: pick a preset by id.
- Looping effects on a part or model (auras, trails, ambience).
- A new effect the library lacks: author it as preset data and register it.

When not to use: raw ParticleEmitter authoring outside the kit (`roblox-vfx`); a whole gameplay event with popup, sound and shake (`uvk-gameplay-feedback`); reveals by rarity (`uvk-reward-reveals`).

## Inputs

- Where it plays: a Vector3, CFrame, BasePart, Attachment or Model.
- How often it can fire, and the lowest device the game targets.
- Optional uploaded texture ids. None are needed: effects fall back to Roblox's built-in particle textures.

## Workflow

1. **Choose the preset.** The table by category, with cost and extra params, is [references/vfx-presets.md](references/vfx-presets.md). Or:

   ```bash
   grep -n -i -B2 -A2 'burst' $URK/catalog/visuals.json | grep '"id"'
   ```

2. **Play one-shots, attach loops.**

   ```lua
   Visuals:Play("CoinBurst", position)
   Visuals:Play("RarityBurst", petModel, { rarity = "Legendary" })
   Visuals:Play("ElementBurst", hitPosition, { element = "ice", scale = 1.5 })

   local aura = Visuals:Attach("RarityAura", petModel, { rarity = "Epic", owner = petModel })
   aura.stop()        -- loops fade out
   aura.stop(true)    -- or disappear at once
   Visuals:StopAll(petModel)   -- everything started with owner = petModel
   ```

   Common params: `color` (hex or Color3; retints every layer), `scale` (0.25-4), `intensity` (0-2), `owner`, `priority`, `parent`. `rarity`: Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret. `element`: fire, ice, lightning, water, earth, wind, light, dark. Ambient presets take `size` (4-200 studs).

3. **Treat nil as normal.** `Visuals:Play` returns nil when the effect was skipped by budget, distance, offscreen, throttle or quality. Never loop until it succeeds.

4. **Reserve the eight high-cost presets** (`RarityBurst`, `HatchBurst`, `PetEvolve`, `Transformation`, `Prestige`, `Rebirth`, `AreaUnlock`, `EggFlash`) for rare moments. Presets made for rapid input (`TapPop`, `ImpactFlash`, `HitConfirm`, `CoinBurst`) carry a `minInterval`, so spam cannot stack them.

5. **Optional textures.** Sharper shapes come from the kit's generated textures, uploaded by the owner:

   ```bash
   python3 $URK/urk.py visuals textures --check
   ```

   ```lua
   Visuals:Configure({ textures = { coin = "rbxassetid://<your id>", heart = "rbxassetid://<your id>" } })
   ```

   The upload and id mapping are in `docs/workflows/visual-assets.md`. Uploading is manual and needs the owner's account.

6. **Author or override a preset as data.** Layers: `particles`, `beam`, `trail`, `light`, `highlight`, `ring`, `flash`, `billboard`, `shake`, `sound`, `postfx`.

   ```lua
   local VFX = Visuals.VFX
   local Recipe = require(ReplicatedStorage.Shared.Urk.Visuals.VFX.RecipeLogic)

   local preset = Recipe.preset({
   	id = "SlimePop", name = "Slime pop", category = "combat",
   	description = "Green blobs burst outward and a ring spreads on the ground.",
   	color = "#7CFF6B", tags = { "slime", "pop" },
   	data = {
   		duration = 0.6,
   		layers = Recipe.join(
   			Recipe.particles({ texture = "drop", colors = { "#D6FFC2", "#7CFF6B" }, burst = 14, gravity = -40 }),
   			Recipe.ring("#7CFF6B", { radius = { 0.4, 4 } })
   		),
   	},
   })
   assert(#VFX.EffectLogic.validate(preset.data) == 0)
   VFX.registry:register(preset)                             -- new id
   VFX.registry:register(myCoinBurst, { override = true })   -- replace a built-in; registry:reset(id) restores
   ```

   Check its cost before shipping: `VFX.EffectLogic.cost(preset.data)` estimates live particles and lights. Budgets are in `uvk-visual-performance`.

## Outputs

- Preset calls by id; looping handles stored and stopped with their owner.
- New presets registered through `Recipe.preset`, validated, with a description and tags so search finds them.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_vfx`. The spec checks every preset against the schema and the budgets at each quality level. How an effect looks is `NEEDS MANUAL REVIEW` in Studio: play it at Low and High, on a phone profile, and near a wall.

## Pitfalls

- **Writing an emitter by hand** because the id was not found: search by what it shows ("sparkle", "ring", "trail"), not by the game noun.
- **Looping preset played with `Play`.** Use `Attach` for loops and trails; trails need a part target.
- **Auras in ViewportFrames.** ViewportFrames do not render particles, beams or trails.
- **Whole-map weather.** Attach `Rain` or `Snow` to the character's root part with the default `size`; a huge box gets sparser, not better.
- **Stacking flashes.** One flash per moment; reduced flashing softens them, but three presets with flash layers at once is still too much.
- **Copying another game's effect names or look.** Presets are original; keep new ones original and descriptive.

## Limitations

- `EffectLogic`, `RecipeLogic` and the preset data are covered by Lune specs and strict type checks. `Builders.luau` and `VFX.luau` were not run in Studio; all tuning was done from numbers, not by eye.
- With fallback textures a "coin" is a gold sparkle and a "heart" a pink one; literal shapes need uploaded textures.
- Emitters, beams and lights are created per effect and destroyed with it; only the holder parts are pooled.
