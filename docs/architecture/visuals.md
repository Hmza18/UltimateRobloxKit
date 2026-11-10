# UltimateVisualsKit architecture

UltimateVisualsKit (UVK) is the visual layer of the kit: motion, VFX, UI animation, pets, eggs, reward reveals, camera, object animation and gameplay feedback. It lives in `library/src/Visuals/` and is reached through one module:

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

Visuals:Play("CoinBurst", position)
Visuals.UI:Animate(button, "BouncyPress")
Visuals.Pets:Play("HappyReaction", petModel)
Visuals.Rewards:Reveal("Legendary", rewardData)
Visuals.Camera:Shake("SoftImpact")
Visuals.Sequence():Play("SparkleBurst", position):Wait(0.2):Play("RewardGlow", position):Start()
```

Sub-modules are tables of camelCase functions (`Visuals.UI.animate`). The facade also accepts the method spelling above (`Visuals.UI:Animate`), so both work. Sub-modules load on first use.

Visuals are cosmetic and client-side. No module here decides a gameplay result; games call UVK after the server has decided.

## How it fits the rest of the kit

| Existing piece | Relationship |
|---|---|
| `UI/` (UrkUI, `UI/Game` components, `UI/Style` tokens) | UVK extends it. New components go in `UI/Game/`; UVK never builds a second UI framework. Scale effects share UrkUI's `UrkScale` UIScale |
| `UI/Core/Easing`, `MotionPresets`, `UI/Runtime/Motion` | Kept as is. `Visuals/Core/Curves` wraps Easing; UVK's engine adds springs, priorities and restoration on top |
| `Systems/VFX` (5 presets, 3 tiers) | Kept as is. `Visuals/VFX` registers those presets too and maps the tiers with `Quality.fromLegacy` |
| `Icons/` and `tools/icons/import_pack.py` | The paid-pack pipeline builds on them; originals are never modified |
| `design/tokens/styles.json` | The ten UVK themes are styles there, so every component follows the theme |
| `Systems/Pets`, `Systems/Rebirth` and other systems | Unchanged. They own rules; UVK owns presentation |

## Layout

```
library/src/Visuals/
  Visuals.luau        facade
  Core/               pure Luau, Lune-tested: Clock, Engine, Springs, Curves, Sequence, Registry,
                      Quality, Effects, Pool
  Runtime/            Host (frame loop, settings), Props (Roblox property adapter), Motion (public API)
  VFX/                effect schema, presets, emitter/beam/trail/light builders, player
  UI/                 UI animation presets and player, text effects, popups, fly-to-counter
  Camera/             shake, zoom, focus, orbit, cinematics, restoration
  Objects/            3D object animation presets
  Pets/               pet animator, follow formation, previews, selection screen
  Eggs/               hatch cinematic
  Rewards/            rarity profiles and reward reveals
  Feedback/           event -> feedback mapping
  Audio/              sound cue registry (no bundled sounds)
  Themes/             the ten visual themes
  Icons/              registry for imported icon packs
  Screens/            screen templates
  Presets/            one view over every registry (for tools and AI agents)
  Debug/              stats overlay and profiler
```

## Rules for every module

1. `library-conventions.md` applies: `--!strict`, relative string requires, tabs, 120 columns, StyLua clean, Selene clean.
2. **Split pure from Roblox.** Anything that can be decided without an Instance - preset data, timing plans, layout maths, state machines, budgets - goes in a pure module (`<Name>Logic.luau` or a data module) with a spec in `library/tests/visuals_<area>.spec.luau`. Runtime modules stay thin.
3. **Time comes from `Host.clock`.** Never connect to RenderStepped or Heartbeat, and never use `task.delay`/`task.wait` for effect lifetimes: use `Host.clock:add(job)`, `Host.clock:after(seconds, fn)` or the engine. That is what makes cancellation and cleanup testable and keeps one frame loop for the whole kit.
4. **Animate through the engine** (`Runtime/Motion`): `Motion.tween`, `Motion.spring`, `Motion.punch`, `Motion.native`. It resolves conflicts by priority, never jumps on interruption, drops destroyed targets and can restore original values.
5. **World effects go through `Host.effects:spawn`**, which applies budgets, distance, offscreen and throttle rules and guarantees cleanup.
6. **Every handle** returned to callers has `stop()` and the alias `cancel()`; add `finish()` when "jump to the end state" makes sense. Stopping twice is harmless. Nothing may keep running after its target is destroyed.
7. **Presets are registered** in a `Core/Registry` instance exposed as `<Module>.registry`, with id (PascalCase), name, category, description, params, quality, usage. Games override with `{ override = true }`.
8. **Read settings from Host**: `Host.profile()` (quality profile), `Host.settings()` (reducedMotion, reducedFlashing, intensity), `Host.juice(kind)`. Reduced motion: no loops, no camera shake, jumps instead of travel. Reduced flashing: no full-screen flashes.
9. **Only real Roblox APIs.** If unsure a property or method exists, check the type definitions (see Verification). No shaders, no unsupported post-processing.
10. **No third-party assets, textures or sounds.** Effects must look right with Roblox's built-in particle textures (`rbxasset://textures/particles/sparkles_main.dds`, `smoke_main.dds`, `fire_main.dds`) and accept optional texture ids through `VFX.configure({ textures = ... })`.
11. **Animation principles** are part of the definition of done: anticipation before big moments, follow-through (springs, not hard stops), secondary motion, squash and stretch for cartoon objects, a clear timing hierarchy, readable rarity hierarchy, immediate response to input, and nothing that hides gameplay-critical information.
12. Each folder has a `README.md`: purpose, API table, preset table, example, performance notes, and a "Not verified in Studio" section. Never write that something works in Studio.

## Core API (already implemented)

| Module | Use |
|---|---|
| `Core/Clock` | `clock:add(job) -> remove`, `clock:after(seconds, fn) -> cancel`, `clock:step(dt)`, `clock:now()` |
| `Core/Engine` | `engine:animate(target, spec) -> Handle`, `stop`, `restore`, `isAnimating`, `cancelAll`; adapter-driven, number arrays |
| `Core/Springs` | Presets Gentle, Soft, Snappy, Bouncy, Elastic, Overshoot, Heavy, Playful, Premium, Cinematic; `Springs.step`, `Springs.get`, `Springs.register` |
| `Core/Curves` | All `UI/Core/Easing` curves plus sine/quart/quint/expo/circ/back/elastic/bounce variants, `anticipate`, `anticipateOvershoot`, `swiftOut`, `Curves.bezier`, `steps`, `yoyo`, `blend`, `register` |
| `Core/Sequence` | `Sequence.new(runner)` with `Play`, `Sound`, `Wait`, `At`, `Call`, `Animate`, `Marker`, `Parallel`, `Stagger`, `Cleanup`, `OnDone`, `OnMarker`, `Speed`, `Start`, `Skip`, `Cancel`, `Pause`, `Resume` |
| `Core/Registry` | `Registry.new(kind)`, `register`, `get`, `find`, `list`, `ids`, `search`, `params`, `describe`, `reset` |
| `Core/Quality` | Levels Low/Medium/High/Ultra, `Quality.profile(level)`, `choose(device)`, `scaleCount`, `distanceScale`, `juice`, adaptive controller |
| `Core/Effects` | `effects:spawn(request) -> handle?, reason?`, `stopOwner`, `stopId`, `stopAll`, `stats` |
| `Core/Pool` | `Pool.new({ create, reset, destroy, max })`, `acquire`, `release` |
| `Runtime/Host` | `Host.clock`, `Host.engine`, `Host.effects`, `Host.profile()`, `Host.settings()`, `Host.juice(kind)`, `Host.configure`, `Host.Changed` |
| `Runtime/Motion` | `tween(target, goals, options)`, `spring(target, goals, spring, options)`, `animate`, `punch`, `native`, `stop`, `restore`, `sequence`, `stagger`, `delay` |
| `Runtime/Props` | Virtual properties: `Scale` (GuiObject UIScale), `GroupFade`, `Pivot`, `PivotCFrame`, `ModelScale` |

Read the header comment of each file for details.

## Module contracts

Functions other modules and the facade rely on. Owners may add more.

### VFX (`VFX/VFX.luau`)

```lua
VFX.play(id, at, params?) -> Handle?      -- at: Vector3 | CFrame | BasePart | Attachment | Model
VFX.attach(id, target, params?) -> Handle? -- looping effects; target: BasePart | Attachment | Model
VFX.stop(handle)
VFX.configure({ textures = { [key] = "rbxassetid://..." } })
VFX.registry                               -- Core/Registry, kind "vfx"
```

Common params on every preset: `color` (hex or Color3), `scale`, `intensity`, `owner`, `priority`, `parent`. A nil return means the effect was skipped (budget, distance, throttle), which is normal.

Required preset ids (other modules reference these by name):

| Category | Ids |
|---|---|
| rewards | CoinBurst, GemBurst, StarBurst, CashExplosion, SparkleBurst, RewardGlow, TreasureOpen, ChestGlow, RarityBurst (param `rarity`), RarityBeam, Confetti, Fireworks, GoldenShine |
| pets | PetSpawn, PetDespawn, PetEquip, PetUnequip, PetHappy, PetSelect, PetUpgrade, PetEvolve, PetFusion, PetTeleport, RarityAura (param `rarity`), PetCollect, PetSummon, PetIdleSparkle |
| eggs | EggShakeDust, EggCrack, EggFlash, HatchBurst (param `rarity`), EggEnergy |
| combat | ImpactFlash, EnergyBurst, Shockwave, HitConfirm, AbilityActivate, AbilityCharge, ElementBurst (param `element`: fire, ice, lightning, water, earth, wind, light, dark), Aura, DashTrail, Transformation, CooldownReady |
| movement | SpeedTrail, JumpBurst, LandingDust, DoubleJump, SprintStreaks, TeleportTrail, MovementAura |
| environment | Fireflies, Dust, Snow, Rain, Wind, FallingLeaves, Bubbles, WaterSplash, MagicParticles, Portal, Checkpoint, AreaUnlock, AmbientGlow |
| progression | LevelUp, QuestComplete, Achievement, RankUp, Prestige, Rebirth, SkillUnlock, DailyReward, StreakReward, NewArea |
| feeding | FoodTrail, FoodSplat, HeartBurst, CrumbBurst, TapPop |

### UI (`UI/UIAnimations.luau`)

```lua
UI.animate(gui, presetId, options?) -> Handle
UI.stop(gui, restore?)
UI.bind(button, style?, options?) -> cleanup     -- hover / press / release / selected / disabled states
UI.show(gui, presetId?, options?) / UI.hide(gui, presetId?, options?)
UI.stagger(guis, presetId, options?) -> Handle
UI.countTo(label, to, options?) -> Handle        -- number counter
UI.typewriter(label, text, options?) -> Handle
UI.popup(text, at, options?) -> Handle?          -- floating number; at: Vector3 | Vector2 | GuiObject
UI.flyTo(from, toGui, options?) -> Handle        -- currency flies to a counter
UI.shine(gui, options?) -> Handle
UI.flash(color?, options?) -> Handle?            -- honours reducedFlashing
UI.registry                                      -- kind "ui"
```

### Camera (`Camera/Camera.luau`)

```lua
Camera.shake(presetOrOptions, options?) -> Handle   -- SoftImpact, Impact, HeavyImpact, Rumble, Tap, Hatch, Landing, Explosion
Camera.fov(target, options?) -> Handle
Camera.zoom(factor, options?) -> Handle
Camera.focus(target, options?) -> Handle            -- target: Vector3 | CFrame | Instance
Camera.orbit(target, options?) -> Handle
Camera.pan(fromCFrame, toCFrame, options?) -> Handle
Camera.cinematic(name, target, options?) -> Handle  -- PetReveal, RewardReveal, AreaUnlock, Teleport
Camera.restore(options?)
Camera.registry                                     -- kind "camera"
```

The camera is never left overridden: every handle restores what it changed (CameraType, CFrame, FieldOfView) when it stops, finishes, is replaced by a higher priority move, or the character respawns. Shakes are additive offsets applied after the game's own camera update, so they work with any camera controller.

### Objects (`Objects/Objects.luau`)

```lua
Objects.animate(target, presetId, options?) -> Handle  -- Model | BasePart | Attachment | GuiObject
Objects.stop(target, restore?)
Objects.registry                                       -- kind "object"
```

Presets: Float, Hover, Bounce, Spin, Pulse, Sway, Orbit, ScaleIn, ScaleOut, Reveal, Dissolve, Appear, Disappear, Collect, Teleport, Shake, SquashStretch, Interact.

### Pets (`Pets/Pets.luau`)

```lua
Pets.animator(model, options?) -> PetAnimator   -- idle float / breathe / rotate; :react(id), :destroy()
Pets.play(reactionId, model, options?) -> Handle
Pets.follow(owner, pets, options?) -> Follower  -- formation, smoothing, ground alignment, orbit
Pets.preview(viewportFrame, model, options?) -> Preview
Pets.selection(props) -> SelectionScreen        -- flagship pet selection screen
Pets.registry                                   -- kind "pet"
```

Reactions: HappyReaction, CuriousReaction, SelectBounce, HoverReaction, Spawn, Despawn, Equip, Unequip, Evolve, Upgrade.

### Eggs (`Eggs/Eggs.luau`)

```lua
Eggs.hatch(config) -> Hatch     -- config.eggs = { { rarity, pet, egg?, name? }, ... }; 1, 3 or many
Eggs.idle(eggModel, options?) -> Handle
-- Hatch: skip(), cancel(), isRunning(), Completed (Signal), Revealed (Signal)
```

### Rewards (`Rewards/Rewards.luau`)

```lua
Rewards.reveal(rarity, reward, options?) -> Handle  -- reward: { name, amount?, icon?, image?, model?, subtitle? }
Rewards.batch(rewards, options?) -> Handle
Rewards.registerRarity(id, profile)
Rewards.rarity(id) -> profile
Rewards.rarities() -> { string }                    -- Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret + custom
```

### Feedback (`Feedback/Feedback.luau`)

```lua
Feedback.define(event, recipe)     -- recipe: list of steps (vfx, ui, popup, camera, sound, object, call)
Feedback.fire(event, context?)     -- context: { position, target, gui, amount, rarity, ... }
Feedback.use(pack)                 -- replace many recipes at once
Feedback.events() -> { string }
```

### Audio (`Audio/Audio.luau`)

```lua
Audio.register(cue, idOrOptions)   -- no sounds are bundled; unregistered cues are silent
Audio.play(cue, options?) -> Handle?
Audio.cues() -> { string }         -- the cue names the kit plays
```

### Themes (`Themes/Themes.luau`)

```lua
Themes.set(id) / Themes.get(id?) / Themes.names() / Themes.Changed
```

Ids: VibrantSimulator, PremiumCartoon, Fantasy, Anime, SciFi, Cozy, ModernMinimal, Arcade, Luxury, Adventure. Each maps to a style of the same intent in `design/tokens/styles.json`.

## Verification

Luau tools are pinned in `library/rokit.toml` and `.github/workflows/ci.yml`. From `library/`:

```bash
lune run tests/run tests visuals_
```

```bash
stylua --check src tests examples
```

```bash
selene src tests examples
```

CI also runs strict `luau-analyze` on pure modules and a report-only `luau-lsp analyze` with Roblox type definitions over the whole library.

What Lune proves: everything in `Core/` and every `*Logic` / data module (timing, cancellation, restoration, budgets, cleanup accounting, preset validity). What it cannot prove: how effects look, and any code that creates Instances. Those are `NEEDS MANUAL REVIEW` until run in Studio.

## Status and deviations

State of the implementation at version 0.5.0 (2026-11-10). The contract above is unchanged; where it and the source differ, the source and each module's README are right. Function reference: [visuals-api.md](../references/visuals-api.md). Preset tables: [visuals-presets.md](../references/visuals-presets.md). Module overview: [library/src/Visuals/README.md](../../library/src/Visuals/README.md). The research the design draws on is in [docs/research/visuals](../research/visuals/README.md).

### What exists

| Module | State |
|---|---|
| Core, Runtime | Implemented. Core is pure and spec-tested |
| VFX | 78 presets in the 8 contract categories, every required id present, plus 5 `Legacy*` presets bridged from `Systems/VFX` (83 registry entries) |
| UI | 70 presets and every contract function |
| Camera | 8 shakes, 4 cinematics, 6 move entries |
| Objects | The 18 contract presets |
| Pets | 4 reactions, 6 timelines, animator, follower, preview, selection screen, demo pet |
| Eggs | Hatch for single, triple, multi and auto modes; idle |
| Rewards | 7 rarity profiles, reveal, batch, custom rarities |
| Feedback | 24 events in the Simulator, Minimal and Combat packs |
| Audio | 29 cue names; no sounds bundled |
| Themes | The 10 contract themes |
| Icons | Registry, containers, picker and UrkUI bridge for imported packs; no pack bundled |
| Presets, Debug | One view over the registries; stats overlay and profiler |
| `UI/Game` | 17 animated components added beside the existing 19 |

### Deviations from the contract

- **`UI.bind` returns a Binding object**, not a bare cleanup function. The binding has `setSelected`, `setDisabled`, `status` and `destroy`, and calling it like a function also cleans up, so contract-style code still works.
- **`VFX.stop(handle, immediate?)`** takes a second argument: looping effects fade by default and `immediate = true` destroys at once.
- **Camera handles use `stop(blend?)`** instead of `stop(restore?)`. A camera move always restores, so the argument chooses between blending back and cutting back. `Camera.punchFov` is an addition.
- **RunService use (rule 3).** `Camera.luau` binds two render steps (`Camera - 1` to remove the shake offset, `Camera + 1` to apply it) while a shake or move is active, because only render-step priorities can order it around the game's camera scripts. This is the one module that takes frame time outside `Host.clock`. For completeness: `Runtime/Host` itself owns the single frame connection that steps the clock, keeps a small frame-time sampler connected while adaptive quality is on, and `Debug` connects to RenderStepped only while its overlay or profiler is open.
- **Additions beyond the contract**, all documented in the module READMEs: `UI.ripple`, `backdrop`, `rest`, `isAnimating`, `stats` and three extra presets (HoverReset, Spinner, Highlight); `VFX.stopAll`, `textures`, `stats`, `preload`; `Objects.isAnimating`, `count`, `stopAll`; `Pets.find`, `demoPet`, `stats`; `Eggs.demoEgg`, `demoPet`, hatch `finish`, `stop` and `BatchCompleted`; `Rewards.plan`; `Feedback.clear`, `reset`, `recipe`, `packs`, `connect` and the step kinds `flyTo`, `pet`, `reward`, `hatch`; `Audio.registerMany`, `stop`, `stopAll`, `setVolume`, `mute`, `isMuted`, `registered`, `isRegistered`; `Themes.current`, `has`, `register`, `derive`, `token`, `color`, `particleColors`, `style`, `urkThemes`, `validate`.
- **Accessibility settings are passed in, not detected.** `reducedMotion` and `reducedFlashing` come from `Visuals:Configure`; UVK does not read the device preference itself.
- **README coverage (rule 12).** `Core/`, `Runtime/`, `Presets/` and `Debug/` are documented in their file headers, in the top-level Visuals README and in the API reference rather than in a README of their own.

### Discoverability

`catalog/visuals.json` lists every preset, rarity profile, feedback event, audio cue, theme and game component with id, name, category, description, params, cost and a usage line. It is generated from the pure modules by `library/tools/export_visuals.luau`; CI fails when it is stale. `scripts/automation/build_visuals_refs.py` generates the preset tables in the skills and in `docs/references/visuals-presets.md` from it. The `uvk-*` skills tell agents to search it before writing any effect.

### Verification status

Proven with Lune and strict `luau-analyze`: everything in `Core/` and every `*Logic`, `*Presets` and `*Data` module. Checked with StyLua, Selene and `luau-lsp` against Roblox type definitions only: every module that creates or changes Instances. **Nothing has been run in Roblox Studio.** How effects, animations, screens, the hatch and reveals look and feel, input on touch and gamepad, safe areas, camera restoration in a live game and performance on devices are all `NEEDS MANUAL REVIEW`. Current numbers are in [PROGRESS.md](../../PROGRESS.md).
