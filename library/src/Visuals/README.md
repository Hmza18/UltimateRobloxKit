# UltimateVisualsKit (UVK)

The visual layer of UltimateRobloxKit: motion, world VFX, UI animation, object animation, camera moves, pets, egg hatching, reward reveals, gameplay feedback, sound cues, themes and imported icon packs, behind one module.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

Visuals:Play("CoinBurst", position)
Visuals.UI:Animate(button, "BouncyPress")
Visuals.Pets:Play("HappyReaction", petModel)
Visuals.Rewards:Reveal("Legendary", rewardData)
Visuals.Camera:Shake("SoftImpact")
Visuals.Sequence():Play("SparkleBurst", position):Wait(0.2):Play("RewardGlow", position):Start()
```

UVK is cosmetic and client-side. No module decides a gameplay result: the server validates and decides, then the client calls UVK to present it.

**Status.** The pure half (timing, cancellation, restoration, budgets, preset data) is covered by Lune specs and strict type checks. No module that creates Instances has been run in Roblox Studio, so how anything looks, feels or performs on a device is `NEEDS MANUAL REVIEW`. See [Verification](#verification).

## Install

```bash
python3 urk.py add --list
```

```bash
python3 urk.py add Visuals --project ~/games/MyGame
```

The module is `Visuals`. `urk.py add` copies it and the library modules it requires to `src/shared/Urk/`, so the require path in a project is `ReplicatedStorage.Shared.Urk.Visuals.Visuals`. With the `.rbxm` model (`rojo build library -o UltimateRobloxKit.rbxm`) it is `ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals`, as in the examples here.

Sub-modules load on first use, so a game that only animates UI never loads the pet or egg code. Each sub-module is a table of camelCase functions (`Visuals.UI.animate`); the facade also accepts the method spelling (`Visuals.UI:Animate`).

## Quick start

Each line is the whole integration for that feature. Longer walk-through: [docs/workflows/visuals-quickstart.md](../../../docs/workflows/visuals-quickstart.md).

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

-- An animated button: hover, press, release, selected and disabled states
local binding = Visuals.UI.bind(buyButton, "Premium", { onActivated = requestPurchase })

-- Currency collection: burst, coins fly to the counter, the counter rolls, the coin cue plays
Visuals.Feedback:Fire("CollectCoin", { position = coinPosition, amount = 25, total = 1250, counter = coinLabel })

-- Pet selection screen (mouse, touch, keyboard, gamepad)
local screen = Visuals.Pets.selection({
	parent = playerGui,
	title = "Choose your starter",
	pets = {
		{ id = "ember", name = "Ember", rarity = "Rare", color = "#FF8A3D" },
		{ id = "moss", name = "Moss", color = "#58C26A" },
		{ id = "drift", name = "Drift", color = "#5AB0FF" },
	},
	onConfirm = function(id) chooseStarter:FireServer(id) end,
})

-- Egg hatch, after the server has rolled the result
local hatch = Visuals.Eggs:Hatch({ eggs = { { rarity = "Legendary", name = "Dragon", pet = dragonModel, isNew = true } } })

-- Reward reveal scaled by rarity
local reveal = Visuals.Rewards:Reveal("Epic", { name = "Crystal Sword", icon = "sword", subtitle = "From the Frost Chest" })

-- Map a gameplay event to feedback once, fire it anywhere
Visuals.Feedback:Define("OpenChest", {
	{ kind = "vfx", id = "TreasureOpen", at = "$position" },
	{ kind = "popup", text = "+$amount", at = "$position" },
	{ kind = "camera", shake = "SoftImpact", when = { field = "rarity", atLeast = "Epic" } },
	{ kind = "sound", cue = "success", delay = 0.1 },
})
Visuals.Feedback:Fire("OpenChest", { position = chest.Position, amount = 500, rarity = "Epic" })

-- Object animation
local float = Visuals.Objects.animate(coinModel, "Float")
Visuals.Objects.animate(chestModel, "SquashStretch")

-- Icons from an imported pack (falls back to the kit's own icons)
Visuals.Icons.apply(imageLabel, "mypack:sword")

-- Themes
Visuals:Configure({ theme = "Luxury" })

-- Cancel and clean up: every call returns a handle
float.stop()             -- loops restore their target
hatch.cancel()           -- removes the stage and restores the camera
reveal.cancel()
binding.destroy()
screen:destroy()
Visuals:StopAll(petModel) -- every effect started with owner = petModel
Visuals:StopAll()         -- every effect
```

`Visuals:Play` and `Visuals:Attach` return nil when an effect is skipped by the budget, distance, offscreen or throttle rules. That is normal; do not retry.

## Modules

| Reach it as | Folder | What it does | Presets |
|---|---|---|---|
| `Visuals:Play`, `Visuals:Attach`, `Visuals.VFX` | [VFX](VFX/README.md) | Data-driven world effects: particles, beams, trails, rings, lights, flashes | 78 in 8 categories, plus 5 bridged from `Systems/VFX` |
| `Visuals.UI` | [UI](UI/README.md) | UI animation presets, button bindings, show and hide, stagger, counters, typewriter, shine, ripple, flash, popups, fly-to-counter | 70 |
| `Visuals.Objects` | [Objects](Objects/README.md) | Float, spin, bounce, collect, squash and stretch for Models, parts, attachments and GuiObjects | 18 |
| `Visuals.Camera` | [Camera](Camera/README.md) | Additive shake, FOV, zoom, focus, orbit, pan, cinematics; always restores the camera | 8 shakes, 4 cinematics |
| `Visuals.Pets` | [Pets](Pets/README.md) | Rig-agnostic pet animator, reactions, followers, viewport previews, the selection screen | 4 reactions, 6 timelines |
| `Visuals.Eggs` | [Eggs](Eggs/README.md) | The hatch cinematic for 1, 3 or many eggs, auto-hatch, idle eggs | 11 beats, scaled by rarity |
| `Visuals.Rewards` | [Rewards](Rewards/README.md) | Rarity profiles and reward reveals, single and batch | 7 rarities |
| `Visuals.Feedback` | [Feedback](Feedback/README.md) | Event to recipe mapping with throttling and coalescing | 24 events in 3 packs |
| `Visuals.Audio` | [Audio](Audio/README.md) | Sound cues by name. No sounds are bundled | 29 cue names |
| `Visuals.Themes` | [Themes](Themes/README.md) | Ten visual themes: colours, type, layout, motion feel, effect tokens | 10 |
| `Visuals.Icons` | [Icons](Icons/README.md) | Registry and helpers for imported icon packs, themed and animated containers, picker | none bundled |
| `Visuals.Screens` | `Screens/` | Ready screen templates built from the game components (see the module's own files and README when present) | 12 |
| `Visuals.Presets` | `Presets/` | One view over every registry: `search`, `list`, `describe`, `usage`, `register`, `reset`, `export` | |
| `Visuals.Debug` | `Debug/` | Stats overlay, effect profiler, `dump()` of every preset id | |
| `Visuals.Motion`, `Visuals.Sequence()` | `Runtime/`, `Core/` | Tweens, springs, punches and skippable timelines on one clock | 10 springs |
| `Visuals.Quality`, `Visuals.Springs`, `Visuals.Curves` | `Core/` | Quality profiles, spring presets, easing curves (pure Luau) | |

The animated game components (PremiumButton, TabBar, Modal, XPBar, PetCard, RewardPanel and others) live in [UI/Game](../UI/Game/README.md) and take their motion from `Visuals.UI`.

Every preset, with its params, cost and a usage line, is listed in the generated catalog `catalog/visuals.json` at the repository root, and as tables in [docs/references/visuals-presets.md](../../../docs/references/visuals-presets.md). The full function reference is [docs/references/visuals-api.md](../../../docs/references/visuals-api.md). The contract the modules were built to is [docs/architecture/visuals.md](../../../docs/architecture/visuals.md).

## Facade

| Function | Does |
|---|---|
| `Visuals:Play(id, at, params?) -> Handle?` | One-shot VFX preset at a Vector3, CFrame, BasePart, Attachment or Model |
| `Visuals:Attach(id, target, params?) -> Handle?` | Looping VFX preset on a part, attachment or model |
| `Visuals:StopAll(owner?)` | Stops every effect tagged with `owner`, or every effect |
| `Visuals.Sequence() -> Sequence` | A timeline whose `Play` steps run VFX presets and `Sound` steps run audio cues |
| `Visuals:Configure(config)` | Applies settings; later calls change only the fields given |
| `Visuals:Settings()` | `{ level, adaptive, reducedMotion, reducedFlashing, intensity }` |
| `Visuals:Stats()` | `level`, `tracks`, `jobs`, `effects`, `particles`, `lights`, `spawned`, `evicted`, `rejected`, `frameTime`, `running` |
| `Visuals.Changed` | Signal: settings changed (quality stepped, reduced motion toggled) |

camelCase aliases exist for each (`Visuals.play`, `Visuals.configure`, ...).

## Settings

```lua
Visuals:Configure({
	quality = "Medium",        -- "Low" | "Medium" | "High" | "Ultra"; default: chosen from the device
	adaptive = true,           -- step quality down under load and back up (default true)
	reducedMotion = false,     -- no loops, no camera shake, jumps instead of travel
	reducedFlashing = false,   -- screen flashes become soft fades
	intensity = 1,             -- 0..1.5 multiplier on shake, scale punches and particle counts
	theme = "VibrantSimulator",
	textures = { coin = "rbxassetid://<your id>" },   -- optional, see VFX/README.md
	sounds = { coin = 1234567890 },                    -- your own sound ids, see Audio/README.md
})
```

UVK does not read the player's device accessibility preferences by itself. A game that wants to follow Roblox's reduce-motion setting passes it in, for example `Visuals:Configure({ reducedMotion = GuiService.ReducedMotionEnabled })`, and should offer its own settings for flashing and intensity.

## Extension points

Extend through the registries so that search, the catalog and other agents can find what you add.

| Extend | How |
|---|---|
| A preset of any kind | `Visuals.Presets.register(kind, preset)`; `{ override = true }` replaces a built-in and `Visuals.Presets.reset(kind, id)` restores it. Kinds: `vfx`, `ui`, `object`, `camera`, `pet` |
| A VFX preset from layers | `Recipe.preset({...})` from `VFX/RecipeLogic`, then `Visuals.VFX.registry:register(preset)`; validate with `Visuals.VFX.EffectLogic.validate` |
| A UI animation | `Visuals.UI.registry:register({ id, name, category, description, data = { steps = {...} } })`; validate with `Visuals.UI.Logic.validate` |
| A rarity | `Visuals.Rewards.registerRarity("Divine", { extends = "Mythic", rank = 6.5, color = "#7DF9FF" })` |
| Feedback | `Visuals.Feedback.define(event, recipe)` for one event; `Visuals.Feedback.use(pack)` for a built-in pack name or a table of recipes |
| A theme | `Visuals.Themes.register(id, Visuals.Themes.derive("VibrantSimulator", overrides))` |
| Sounds | `Visuals.Audio.register(cue, idOrOptions)` |
| Textures | `Visuals:Configure({ textures = { [key] = id } })`; the kit's generated textures are in `assets/vfx/` ([workflow](../../../docs/workflows/visual-assets.md)) |
| Icons | `Visuals.Icons.register(pack, data)` with a module built by `tools/icons/vault.py` ([workflow](../../../docs/workflows/icon-pack-import.md)) |
| Springs and curves | `Visuals.Springs.register`, `Visuals.Curves.register` |

## Performance

Every world effect goes through one manager that applies the quality profile's budgets, distance, offscreen and throttle rules, and guarantees cleanup. The profiles (`Core/Quality.luau`):

| Level | Live particles | Effects | Lights | Max distance | Fade from | Particle scale | Rate scale | Shake scale | Pet idle updates | Popups |
|---|---|---|---|---|---|---|---|---|---|---|
| Low | 250 | 10 | 0 | 90 studs | 50 | 0.3 | 0.3 | 0.6 | 20 Hz | 8 |
| Medium | 700 | 24 | 2 | 160 | 90 | 0.6 | 0.6 | 0.85 | 30 Hz | 16 |
| High | 1600 | 48 | 6 | 260 | 150 | 1 | 1 | 1 | every frame | 28 |
| Ultra | 3200 | 80 | 12 | 400 | 240 | 1.35 | 1.25 | 1 | every frame | 40 |

| Switch | Low | Medium | High | Ultra |
|---|---|---|---|---|
| Optional layers dropped | yes | no | no | no |
| Trails | off | on | on | on |
| Beams | on | on | on | on |
| Lights, highlights | off | on | on | on |
| Post-processing pulses | off | off | on | on |
| Looping UI shine | off | on | on | on |

- The level is chosen from the device on first use and, with `adaptive` on, stepped down under load and back up to the configured ceiling.
- One clock drives everything and is connected to the frame signal only while something is running. Adaptive quality keeps one small frame-time sampler connected while it is enabled. `Camera` binds two render steps while a shake or move is active, and `Debug` connects only while its overlay or profiler is open.
- Presets made for rapid input carry a `minInterval`; feedback recipes throttle and coalesce per step.
- The particle numbers are estimates computed from preset data, used for budgeting. They are not engine measurements, and no frame time has been measured on a device.

## Verification

Numbers at the time of writing (2026-11-10); rerun the commands for current ones.

| What | How it was checked | Result |
|---|---|---|
| `Core/` (Clock, Engine, Springs, Curves, Sequence, Registry, Quality, Effects, Pool) | Lune specs; `luau-analyze --mode=strict` | passing |
| Every `*Logic`, `*Presets` and `*Data` module | Lune specs; `luau-analyze --mode=strict` (37 Visuals modules) | passing |
| All Visuals specs | `lune run tests/run tests visuals_` from `library/` | 348 passed, 0 failed, 20 spec files |
| Runtime modules that create Instances (`VFX`, `Builders`, `UIAnimations`, `Camera`, `Objects`, `PetAnimator`, `PetFollow`, `PetPreview`, `PetSelection`, `Eggs`, `Rewards`, `RewardView`, `Feedback`, `Audio`, `Themes`, `IconVault`, `Debug`, `Host`, `Motion`, `Props`) | StyLua, Selene, `luau-lsp analyze` with Roblox type definitions | lint, format and types only. **NOT run in Studio** |
| How effects, animations, screens and reveals look and feel | not checked | `NEEDS MANUAL REVIEW` |
| Input on touch and gamepad, safe areas, device performance | not checked | `NEEDS MANUAL REVIEW` |
| Preset catalog | `lune run tools/export_visuals --check` | current |

Each sub-module's README ends with its own "Not verified in Studio" list. Run the specs from `library/`:

```bash
lune run tests/run tests visuals_
```

```bash
lune run tools/export_visuals --check
```

## Rules for contributors

The full list is in [docs/architecture/visuals.md](../../../docs/architecture/visuals.md). In short: split pure logic from Roblox code and spec the pure half; take time from `Host.clock`, never from `task.wait` or your own frame connection; animate through `Runtime/Motion`; spawn world effects through `Host.effects`; return a handle with `stop()` and `cancel()` from everything; register presets with full metadata; no third-party assets, names or copied effects; never write that something works in Studio unless it was run there. After adding or changing a preset, regenerate the catalog (`lune run tools/export_visuals` from `library/`, then `python3 scripts/automation/build_visuals_refs.py` from the repository root).
