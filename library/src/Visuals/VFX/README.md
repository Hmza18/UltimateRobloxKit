# Visuals/VFX

Data-driven world effects for UltimateVisualsKit. A preset is plain data (a list of layers); the runtime turns each layer into one real Roblox object and plays it through `Host.effects`, so every effect respects the quality budget, distance, offscreen and throttle rules and is always cleaned up.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

Visuals:Play("CoinBurst", position)
Visuals:Play("RarityBurst", petModel, { rarity = "Legendary" })
Visuals:Play("ElementBurst", hitPosition, { element = "ice", scale = 1.5 })

local aura = Visuals:Attach("RarityAura", petModel, { rarity = "Epic", owner = petModel })
aura.stop()        -- looping effects fade out
aura.stop(true)    -- or disappear at once
```

## Files

| File | Kind | What |
|---|---|---|
| `EffectLogic.luau` | pure | Schema, `validate`, `resolve`, `cost`, colour helpers, texture fallbacks |
| `RecipeLogic.luau` | pure | Layer recipes (sparkles, glow, dust, ring, beam ...) and `Recipe.preset` metadata |
| `*Presets.luau` | pure data | One module per category: rewards, pets, eggs, combat, movement, environment, progression, feeding |
| `CatalogData.luau` | pure | All presets in one list, the legacy bridge, `Catalog.registry()` |
| `Builders.luau` | Roblox | Builds Instances from resolved layers |
| `VFX.luau` | Roblox | The public module |

## API (`VFX.luau`)

| Function | Notes |
|---|---|
| `VFX.play(id, at, params?) -> Handle?` | `at`: Vector3, CFrame, BasePart, Attachment or Model (PrimaryPart, else first BasePart). `nil` means skipped (budget, distance, offscreen, throttle, quality) |
| `VFX.attach(id, target, params?) -> Handle?` | Same, but `target` must be an Instance. Use for looping presets and trails |
| `VFX.stop(handle, immediate?)` | Looping effects stop emitting and fade for their particle lifetime; `immediate = true` destroys now. One-shots are always destroyed at once. Safe on `nil` and twice |
| `VFX.stopAll(owner?) -> number` | Immediately stops every VFX effect, or those started with `params.owner == owner` |
| `VFX.configure({ textures = { [key] = id } })` | Texture ids by key. Also reachable as `Visuals:Configure({ textures = ... })` |
| `VFX.textures()` | The configured ids |
| `VFX.stats()` | `live`, `effects`, `particles`, `lights`, `rejected`, `highlights`, `holders` (pool), `presets` |
| `VFX.preload()` | Asks ContentProvider to load configured texture ids; returns at once |
| `VFX.registry` | `Core/Registry`, kind `"vfx"` |
| `VFX.EffectLogic` | The pure module, for validating your own presets |

Handle: `{ id, stop(immediate?), cancel(immediate?), isAlive() }`. `cancel` is `stop`.

Common params on every preset:

| Param | Meaning |
|---|---|
| `color` | Hex string or Color3. The declared default is the preset's own palette and changes nothing; any other colour retints every layer (white cores stay white, layers with `tint = false` such as dust keep their colours) |
| `scale` | 0.25..4. Multiplies sizes, speeds, radii, ranges and offsets |
| `intensity` | 0..2. Multiplies particle counts, light brightness and shake |
| `owner` | Any value; `VFX.stopAll(owner)` and `Visuals:StopAll(owner)` end its effects |
| `priority` | Overrides the preset's priority. Higher priority evicts older, lower-priority effects when the budget is full |
| `parent` | Instance that holds the effect's holder part when playing at a position (default: `Workspace.UvkEffects`) |

## The schema

```lua
{
	duration = 1.2,        -- one-shots; defaults to the end of the longest layer
	looping = false,
	minInterval = 0.05,    -- throttle between starts of this preset
	priority = 0,
	area = { param = "size", base = 40 },             -- ambient effects, see below
	variantParam = "rarity", variants = { Common = def, ... },  -- optional
	layers = { Layer, ... },
}
```

Every layer has `kind`, and may have `name`, `optional` (dropped on Low), `delay`, `tint`, `offset` `{x, y, z}` and `orient` `{x, y, z}` degrees.

| Kind | Roblox object | Main fields |
|---|---|---|
| `particles` | ParticleEmitter | `texture`, `colors` (1-4 hex), `sizes`, `transparency`, `lifetime {min,max}`, `speed {min,max}`, `spread {x,y}`, `burst` or `rate` (+ `emitFor`), `acceleration`, `gravity`, `drag`, `rotation`, `rotSpeed`, `lightEmission`, `lightInfluence`, `brightness`, `squash`, `shape`, `shapeStyle`, `shapeInOut`, `shapeSize`, `emissionDirection`, `orientation`, `zOffset`, `lockedToPart`, `timeScale` |
| `beam` | Beam + 2 Attachments | `colors`, `transparency`, `width {start,end}`, `length`, `direction`, `curve`, `segments`, `texture`, `textureSpeed`, `textureLength`, `faceCamera`, `fadeIn`/`hold`/`fadeOut` (animates width) |
| `trail` | Trail + 2 Attachments | `colors`, `transparency`, `time`, `width {studs}`, `widthScale`, `minLength`, `maxLength`. Only built on a part target |
| `light` | PointLight / SpotLight / SurfaceLight | `light`, `colors {hex}`, `range`, `brightness`, `angle`, `face`, `fadeIn`/`hold`/`fadeOut`, `pulse {period, depth}` (looping) |
| `highlight` | Highlight | `colors {fill}`, `outline`, `fillTransparency`, `outlineTransparency`, `depthMode`, envelope. Needs a part or model target; at most 8 at once |
| `ring` | 2 curved Beams (`style = "line"`) or a Neon cylinder Part (`"disc"`) | `colors {from, to}`, `radius {from,to}`, `thickness`, `transparency {from,to}`, `time`, `easing` |
| `flash` | Neon ball Part (`"orb"`) or PointLight (`"light"`) | `colors`, `sizes {from,to}`, `transparency {from,to}`, `time` |
| `billboard` | BillboardGui | `image` (texture key) or `text`, `colors`, `sizes {from,peak,to}` studs, `time`, `rise`, `alwaysOnTop` |
| `shake` | calls `Camera.shake(preset, { intensity, position, radius })` | `preset`, `amount` |
| `sound` | calls `Audio.play(cue, { volume, at })` | `cue`, `volume` |
| `postfx` | BloomEffect / ColorCorrectionEffect / BlurEffect under the camera | `effect`, `amount`, `colors`, envelope. One pulse per kind at a time |

`EffectLogic.validate(def)` returns every problem (unknown kinds and fields, ranges, stop counts, hex colours). `EffectLogic.resolve(def, profile, params, distanceScale, settings)` applies:

- the quality profile: `particleScale`, `rateScale`, `lifetimeScale`, `dropOptional`, and the `trails`, `beams`, `lights`, `highlights`, `postProcessing` switches. A kept burst layer always emits at least one particle
- `scale`, `intensity`, `color`, the variant param and the area param
- distance (counts fall towards the profile's `maxDistance`) and Host intensity
- reduced flashing: `flash` layers become mostly transparent and slower, lights fade in and dim, `postfx` is dropped
- reduced motion: `shake` layers and light pulsing are dropped, billboards do not rise

`EffectLogic.cost(def, params?)` estimates live particles (burst counts, and rate x average lifetime) and lights for the budget.

Camera and Audio are loaded lazily inside `pcall`, so VFX works without them. No built-in preset has a `sound` layer (Feedback, Rewards and Eggs own audio, and a second cue here would double it); `shake` is used by Shockwave, CashExplosion, PetEvolve, Transformation, Prestige, Rebirth, AreaUnlock, the earth and lightning ElementBurst, and Legendary+ RarityBurst / HatchBurst.

### Ambient effects and `size`

Fireflies, Dust, Snow, Rain, Wind, FallingLeaves, Bubbles, MagicParticles and AmbientGlow emit from a box whose width is the `size` param (4..200 studs). Rates follow the area but are held between 0.25x and 2.5x, so a very large box gets sparser instead of heavier. For weather, attach to the character's root part with the default size rather than covering a whole map. Wind blows along the target's right-hand axis and Portal faces along the target's front: rotate the target or pass a CFrame.

## Textures

Layers name textures by key: `spark`, `glow`, `star`, `ring`, `smoke`, `circle`, `confetti`, `coin`, `gem`, `heart`, `leaf`, `drop`, `shard`, `bubble`, `flare`, `streak`. No textures are bundled.

```lua
Visuals:Configure({ textures = { coin = "rbxassetid://<your id>", heart = "rbxassetid://<your id>" } })
```

A key with no id falls back to a Roblox built-in:

| Fallback | Keys |
|---|---|
| `rbxasset://textures/particles/sparkles_main.dds` | spark, star, confetti, coin, gem, heart, leaf, shard, streak |
| `rbxasset://textures/particles/smoke_main.dds` | glow, ring, smoke, circle, drop, bubble |
| `rbxasset://textures/particles/fire_main.dds` | flare |

Presets are tuned to read with the fallbacks: shape comes from colour ramps, size curves, squash, speed, gravity and drag rather than from the picture. With fallbacks a "coin" is a gold sparkle and a "heart" is a pink one, so supply `coin`, `heart`, `leaf` and `confetti` first if you want literal shapes. A `billboard` layer shows its image only when the key has an id; otherwise it draws its `text`, or a round glow dot. A layer may also give a raw `rbxassetid://` string instead of a key.

## Register or override a preset

```lua
local VFX = Visuals.VFX
local Recipe = require(ReplicatedStorage.UltimateRobloxKit.Visuals.VFX.RecipeLogic)

local preset = Recipe.preset({
	id = "SlimePop",
	name = "Slime pop",
	category = "combat",
	description = "Green blobs burst outward and a ring spreads on the ground.",
	color = "#7CFF6B",
	tags = { "slime", "pop" },
	data = {
		duration = 0.6,
		layers = Recipe.join(
			Recipe.particles({ texture = "drop", colors = { "#D6FFC2", "#7CFF6B" }, burst = 14, gravity = -40 }),
			Recipe.ring("#7CFF6B", { radius = { 0.4, 4 } })
		),
	},
})
assert(#VFX.EffectLogic.validate(preset.data) == 0)
VFX.registry:register(preset)                        -- new id
VFX.registry:register(myCoinBurst, { override = true })  -- replace a built-in; registry:reset(id) restores it
```

`Recipe.preset` adds the `color`, `scale` and `intensity` params, the usage line and the cost label. A hand-written `Core/Registry` preset table works too; its `data` is the definition.

The five `Systems/VFX` presets are registered as `LegacyHatch`, `LegacyLevelUp`, `LegacyCoinPickup`, `LegacyRareAura` and `LegacyPurchase` (category `legacy`). They are converted from `VFXLogic.PRESETS` when the catalog loads, not copied. `Systems/VFX` itself is unchanged. A preset a game adds later with `VFXLogic.register` can be bridged with `Catalog.legacyPreset(name, preset)`.

## Presets

78 presets in 8 categories, plus 5 legacy. "Particles" is the estimated live particle count at High quality (the worst variant for `rarity` / `element` presets); Low shows roughly 30% of it and drops optional layers.

Cost label (computed from the definition, see `Recipe.costLabel`): **low** is up to 40 particles, one light, fewer than 7 layers and no beam; **medium** is up to 120 particles, two lights, fewer than 12 layers and no post-processing; **high** is anything above. The eight **high** presets are the expensive ones: keep them for rare moments.

Every preset also takes `color`, `scale` and `intensity`.

| Id | Category | Type | Cost | Particles | Extra params |
|---|---|---|---|---|---|
| CashExplosion | rewards | one-shot | medium | 56 | - |
| ChestGlow | rewards | loop | low | 17 | - |
| CoinBurst | rewards | one-shot | low | 24 | - |
| Confetti | rewards | one-shot | medium | 45 | - |
| Fireworks | rewards | one-shot | medium | 95 | - |
| GemBurst | rewards | one-shot | low | 24 | - |
| GoldenShine | rewards | one-shot | low | 8 | - |
| RarityBeam | rewards | loop | medium | 44 | `rarity` |
| RarityBurst | rewards | one-shot | high | 170 | `rarity` |
| RewardGlow | rewards | one-shot | low | 17 | - |
| SparkleBurst | rewards | one-shot | low | 25 | - |
| StarBurst | rewards | one-shot | low | 28 | - |
| TreasureOpen | rewards | one-shot | medium | 39 | - |
| PetCollect | pets | one-shot | low | 18 | - |
| PetDespawn | pets | one-shot | low | 24 | - |
| PetEquip | pets | one-shot | low | 16 | - |
| PetEvolve | pets | one-shot | high | 79 | - |
| PetFusion | pets | one-shot | medium | 56 | - |
| PetHappy | pets | one-shot | low | 13 | - |
| PetIdleSparkle | pets | loop | low | 3 | - |
| PetSelect | pets | one-shot | low | 6 | - |
| PetSpawn | pets | one-shot | low | 17 | - |
| PetSummon | pets | one-shot | medium | 37 | - |
| PetTeleport | pets | one-shot | medium | 18 | - |
| PetUnequip | pets | one-shot | low | 12 | - |
| PetUpgrade | pets | one-shot | low | 27 | - |
| RarityAura | pets | loop | medium | 76 | `rarity` |
| EggCrack | eggs | one-shot | low | 16 | - |
| EggEnergy | eggs | loop | low | 15 | - |
| EggFlash | eggs | one-shot | high | 2 | - |
| EggShakeDust | eggs | one-shot | low | 8 | - |
| HatchBurst | eggs | one-shot | high | 188 | `rarity` |
| AbilityActivate | combat | one-shot | low | 16 | - |
| AbilityCharge | combat | loop | low | 17 | - |
| Aura | combat | loop | low | 18 | - |
| CooldownReady | combat | one-shot | low | 6 | - |
| DashTrail | combat | loop | low | 4 | - |
| ElementBurst | combat | one-shot | medium | 41 | `element` |
| EnergyBurst | combat | one-shot | medium | 42 | - |
| HitConfirm | combat | one-shot | low | 12 | - |
| ImpactFlash | combat | one-shot | low | 9 | - |
| Shockwave | combat | one-shot | low | 16 | - |
| Transformation | combat | one-shot | high | 96 | - |
| DoubleJump | movement | one-shot | low | 14 | - |
| JumpBurst | movement | one-shot | low | 12 | - |
| LandingDust | movement | one-shot | low | 17 | - |
| MovementAura | movement | loop | low | 15 | - |
| SpeedTrail | movement | loop | low | 5 | - |
| SprintStreaks | movement | loop | low | 7 | - |
| TeleportTrail | movement | loop | low | 16 | - |
| AmbientGlow | environment | loop | low | 11 | `size` |
| AreaUnlock | environment | one-shot | high | 56 | - |
| Bubbles | environment | loop | low | 32 | `size` |
| Checkpoint | environment | one-shot | medium | 24 | - |
| Dust | environment | loop | medium | 44 | `size` |
| FallingLeaves | environment | loop | low | 30 | `size` |
| Fireflies | environment | loop | low | 20 | `size` |
| MagicParticles | environment | loop | low | 33 | `size` |
| Portal | environment | loop | medium | 61 | - |
| Rain | environment | loop | medium | 79 | `size` |
| Snow | environment | loop | medium | 100 | `size` |
| WaterSplash | environment | one-shot | low | 34 | - |
| Wind | environment | loop | low | 9 | `size` |
| Achievement | progression | one-shot | low | 22 | - |
| DailyReward | progression | one-shot | medium | 34 | - |
| LevelUp | progression | one-shot | low | 35 | - |
| NewArea | progression | one-shot | medium | 30 | - |
| Prestige | progression | one-shot | high | 94 | - |
| QuestComplete | progression | one-shot | low | 30 | - |
| RankUp | progression | one-shot | low | 22 | - |
| Rebirth | progression | one-shot | high | 72 | - |
| SkillUnlock | progression | one-shot | low | 22 | - |
| StreakReward | progression | one-shot | low | 34 | - |
| CrumbBurst | feeding | one-shot | low | 15 | - |
| FoodSplat | feeding | one-shot | low | 16 | - |
| FoodTrail | feeding | loop | low | 9 | - |
| HeartBurst | feeding | one-shot | low | 19 | - |
| TapPop | feeding | one-shot | low | 6 | - |
| LegacyCoinPickup | legacy | one-shot | low | 12 | - |
| LegacyHatch | legacy | one-shot | medium | 65 | - |
| LegacyLevelUp | legacy | one-shot | medium | 48 | - |
| LegacyPurchase | legacy | one-shot | medium | 50 | - |
| LegacyRareAura | legacy | loop | low | 38 | - |

`rarity`: Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret. Count, size, duration and layers grow with rarity: Common is a small pop; Rare adds a ring and a light; Epic adds rays and a second ring; Legendary adds a light pillar, embers and a shake; Mythic adds a flash, a second wave and a white beam core; Secret adds a prismatic wave, a third ring and a bloom pulse.

`element`: fire (rises), ice (brakes, sinks slowly), lightning (fast, brief, bright), water (arcs under gravity), earth (chunky, heavy), wind (wide, fast, drag), light (radiates), dark (implodes, then bursts).

## Performance notes

- Budgets come from `Core/Quality`: Low allows 250 live particles and 10 effects with no lights, trails, highlights or post-processing. Every one-shot preset resolves to at most 62 particles on Low and under 400 on High (checked by the spec).
- Presets meant for rapid input (TapPop, ImpactFlash, HitConfirm, CoinBurst, CrumbBurst, EggShakeDust ...) carry a `minInterval`, so tap spam cannot stack them.
- Effects at a position use pooled holder parts (up to 24 kept). Emitters, beams and lights are created per effect and destroyed with it; they are not pooled.
- A `ring` in `line` style updates two attachments and two beams each frame for its short life; `disc` style resizes one part.
- Lights are skipped when the profile's light budget is used up; the effect still plays.
- Highlights are capped at 8 at once across all effects, and only one post-processing pulse of each kind runs at a time.
- Nothing runs per frame while no effect is animating: timing uses `Host.clock` and `Runtime/Motion` only.
- A looping effect ends by itself when its target part leaves the DataModel.

## Not verified in Studio

Lune tests cover the pure half: schema validation, resolve at every quality level, budgets, rarity and element rules, colour maths, texture fallbacks and the legacy bridge (`library/tests/visuals_vfx.spec.luau`). `Builders.luau` and `VFX.luau` were checked with StyLua, Selene and luau-lsp against the Roblox type definitions and have NOT been run in Studio. NEEDS MANUAL REVIEW:

- How every preset looks. All tuning was done from numbers, not by eye
- `ring` in `line` style: two Beams bent into half circles with `CurveSize`. The attachment orientation and curve signs follow the documented Beam maths but are unconfirmed; if the ring looks wrong, use `style = "disc"`
- Emit volumes: `Shape`, `ShapeStyle` and `ShapeInOut` on a sized invisible part, including the assumption that the Cylinder shape's axis is the part's Y axis (Portal, MovementAura and the column effects rely on it) and that `Inward` particles travel to the centre
- Flat radial dust (`emissionDirection = "Front"` with `spread = { 9, 180 }`)
- `ParticleEmitter:Emit` immediately after parenting a new emitter
- Emit volumes welded to a moving target with `WeldConstraint`
- BillboardGui pops adorned to an Attachment, and the glow-dot fallback
- Bloom, colour-correction and blur pulses parented to the camera, and how they combine with a game's own Lighting effects
- Highlight parented under `Workspace.UvkEffects` with `Adornee` set
- Soft stop timing, and cleanup when a target is destroyed mid-effect
- `Camera.shake` and `Audio.play` calls from `shake` / `sound` layers
- Performance on real phones
