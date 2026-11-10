---
name: uvk-visuals-kit
description: Entry point for UltimateVisualsKit (UVK), the kit's visual layer in library/src/Visuals - one facade for VFX presets, UI animation, object animation, camera moves, pets, egg hatching, reward reveals, feedback events, sound cues, themes and icons, with a searchable preset catalog. Use first for any visual polish, juice, game feel, effects or animation task, to pick existing presets and components instead of writing effects from scratch.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [visuals kit, uvk, ultimatevisualskit, visual polish, juice, game feel, preset catalog, visuals.json, which preset, make it feel good]
  depends: []
---

# UltimateVisualsKit: start here

UVK is cosmetic and client-side. The server decides results; UVK presents them. This skill maps a visual task to the module, preset and narrower skill that already cover it.

## When to use

- Any request for effects, animation, polish, "juice", feedback, reveals, pets or eggs on screen.
- You are about to write a tween, a ParticleEmitter or a camera script by hand. Look here first.

When not to use: gameplay rules (odds, rewards, damage, inventory) belong to the `Systems/` modules and `roblox-simulator-systems`; static screen layout belongs to `roblox-ui-generator` and `urk-ui-framework`.

## Inputs

- The moment to polish (what happened, who sees it, how often per second it can fire).
- The game's theme and target devices (phones lower every budget).
- Whether the library is installed in the project (step 1).

## Workflow

1. **Install once.** The module is `Visuals`; `urk.py add` also copies the library modules it requires.

   ```bash
   python3 $URK/urk.py add Visuals --project .
   ```

2. **Search before writing anything.** The catalog lists every preset with id, description, params, cost and a usage line. This is the rule for every UVK skill: grep `catalog/visuals.json` (in a project: `.claude/ultimate-roblox-kit/catalog/visuals.json`) before authoring an effect.

   ```bash
   grep -n -i '"id": ".*coin' $URK/catalog/visuals.json
   ```

   ```bash
   python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [print(k, i['id'], '-', i['usage']) for k,v in d['kinds'].items() for i in v if sys.argv[2] in (i['id']+i['description']).lower()]" $URK/catalog/visuals.json coin
   ```

   At run time the same search is `Visuals.Presets.search("coin")`, and `Visuals.Presets.describe("vfx", "CoinBurst")` returns the metadata. The id lists by kind are in [references/preset-index.md](references/preset-index.md).

3. **Call the facade.** Sub-modules load on first use. Both spellings work: `Visuals.UI.animate(...)` and `Visuals.UI:Animate(...)`.

   ```lua
   --!strict
   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   -- urk.py add puts the library in src/shared/Urk; with the .rbxm model the path is
   -- ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals
   local Visuals = require(ReplicatedStorage.Shared.Urk.Visuals.Visuals)

   Visuals:Configure({ theme = "VibrantSimulator" }) -- optional: quality, reducedMotion, reducedFlashing, intensity
   Visuals:Play("CoinBurst", position)
   Visuals.UI:Animate(button, "BouncyPress")
   Visuals.Feedback:Fire("CollectCoin", { position = position, amount = 25, total = 1250, counter = coinLabel })
   Visuals.Sequence():Play("SparkleBurst", position):Wait(0.2):Play("RewardGlow", position):Start()
   ```

4. **Pick the module, then open only that skill.**

   | Task | Module | Skill |
   |---|---|---|
   | One call per gameplay event (tap, collect, level up, hit) | `Visuals.Feedback` | `uvk-gameplay-feedback` |
   | World particles, beams, auras, ambience | `Visuals.VFX`, `Visuals:Play` / `:Attach` | `uvk-vfx-presets` |
   | Buttons, panels, counters, popups, fly-to-counter | `Visuals.UI` | `uvk-ui-animation` |
   | Timing, springs, sequences, the animation principles | `Visuals.Motion`, `Visuals.Sequence` | `uvk-motion-design` |
   | Pet idle, reactions, followers, selection screen | `Visuals.Pets` | `uvk-pet-visuals` |
   | Egg hatch cinematic | `Visuals.Eggs` | `uvk-egg-hatching` |
   | Rarity reveals, reward batches | `Visuals.Rewards` | `uvk-reward-reveals` |
   | Shake, FOV, focus, orbit, cinematics | `Visuals.Camera` | `uvk-camera-effects` |
   | Hits, abilities, elements, dashes | Combat feedback pack | `uvk-combat-visuals` |
   | Simulator HUD, shop and reward screens | `UI/Game` components | `uvk-simulator-screens` |
   | Floating, spinning, collecting world objects | `Visuals.Objects` | `uvk-motion-design` |
   | Budgets, quality levels, profiling | `Visuals.Debug`, `Core/Quality` | `uvk-visual-performance`, `uvk-visual-debugging` |
   | A purchased icon pack | `Visuals.Icons`, `tools/icons/vault.py` | `uvk-icon-pack` |
   | Proving it works | Lune specs, Studio checklist | `uvk-visual-testing` |

5. **Only when nothing fits, extend through the registries**, never beside them: `Visuals.Presets.register(kind, preset)` adds a preset, `{ override = true }` replaces a built-in (`Visuals.Presets.reset(kind, id)` restores it), `Visuals.Rewards.registerRarity`, `Visuals.Feedback.define` / `use`, `Visuals.Themes.register`. A registered preset shows up in search for the next agent.

6. **Keep every handle.** Each call returns a handle with `stop()` and `cancel()`. Stop loops and attached effects when their owner goes away: `Visuals:StopAll(owner)` ends everything started with `params.owner == owner`.

7. **Review against the checklist** in [references/quality-checklist.md](references/quality-checklist.md) before calling the work done.

## Outputs

- Client code that calls presets by id; no hand-built emitters, tweens or camera scripts where a preset exists.
- New presets, rarities or feedback recipes registered in the UVK registries, not in private tables.

## Validation

```bash
python3 $URK/urk.py check .
```

```bash
lune run tests/urk/run tests/urk
```

Inside the kit repository the specs are `cd library && lune run tests/run tests visuals_`. Looks, feel and device performance are `NEEDS MANUAL REVIEW` in Studio; see `uvk-visual-testing`.

## Pitfalls

- **Reinventing a preset.** A hand-written coin burst ignores budgets, reduced motion and cleanup. Search first.
- **Playing visuals before the server answers.** A reveal for a reward the server then refuses is a bug. Fire feedback from the server's confirmation.
- **`Visuals:Play` returned nil.** That is normal: the effect was skipped by budget, distance, offscreen or throttle rules. Do not retry in a loop.
- **Running UVK on the server.** It is client presentation; the server only sends the event.
- **Ids from memory.** Ids are PascalCase and exact; an unknown id errors or is skipped. Copy them from the catalog.

## Limitations

- UVK passes its Lune specs for pure logic and its lint, format and type checks. No module that creates Instances has been run in Studio, so how effects look and feel is unverified.
- No textures or sounds are bundled. Effects fall back to Roblox's built-in particle textures, and sound cues are silent until the game registers its own sounds.
- The catalog is a snapshot generated from the library; if a project overrides presets at run time, `Visuals.Presets` is the truth there.
