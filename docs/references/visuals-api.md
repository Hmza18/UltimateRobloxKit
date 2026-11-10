# UltimateVisualsKit API reference

Every public function of `library/src/Visuals`, read from the source at version 0.5.0. Signatures use Luau notation; `?` marks an optional argument. Preset ids, params and costs are in the generated [visuals-presets.md](visuals-presets.md) and in `catalog/visuals.json`. Overview and quick start: [library/src/Visuals/README.md](../../library/src/Visuals/README.md) and [visuals-quickstart.md](../workflows/visuals-quickstart.md).

**Verification.** Modules marked *pure* have Lune specs and pass strict `luau-analyze`. Modules marked *runtime* create or change Instances; they pass StyLua, Selene and `luau-lsp` with Roblox type definitions and have NOT been run in Roblox Studio. Behaviour described for runtime modules is what the code is written to do, not what was observed.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
```

Sub-modules are reached as `Visuals.<Name>` and load on first use. Both `Visuals.UI.animate(...)` and `Visuals.UI:Animate(...)` work for every sub-module function.

## Contents

- [Facade](#facade)
- [VFX](#vfx)
- [UI](#ui)
- [Objects](#objects)
- [Camera](#camera)
- [Pets](#pets)
- [Eggs](#eggs)
- [Rewards](#rewards)
- [Feedback](#feedback)
- [Audio](#audio)
- [Themes](#themes)
- [Icons](#icons)
- [Presets](#presets)
- [Debug](#debug)
- [Motion and Sequence](#motion-and-sequence)
- [Core modules](#core-modules)
- [Preset counts](#preset-counts)

## Facade

`Visuals.luau` (runtime).

| Function | Description |
|---|---|
| `Visuals:Play(id: string, at: any, params: table?) -> Handle?` | Plays a one-shot VFX preset at a Vector3, CFrame, BasePart, Attachment or Model. nil when skipped (budget, distance, offscreen, throttle, quality) |
| `Visuals:Attach(id: string, target: Instance, params: table?) -> Handle?` | Attaches a looping VFX preset (aura, trail, ambient) |
| `Visuals:StopAll(owner: any?)` | Stops every effect started with `params.owner == owner`, or every effect when nil |
| `Visuals.Sequence() -> Sequence` | A new sequence whose `Play` steps run VFX presets and `Sound` steps run audio cues |
| `Visuals:Configure(config: Config?)` | Applies settings. Fields: `quality`, `adaptive`, `reducedMotion`, `reducedFlashing`, `intensity` (0..1.5), `theme`, `textures`, `sounds`. Later calls change only the fields given |
| `Visuals:Settings() -> Settings` | `{ level, adaptive, reducedMotion, reducedFlashing, intensity }` |
| `Visuals:Stats() -> table` | `level`, `tracks`, `jobs`, `effects`, `particles`, `lights`, `spawned`, `evicted`, `rejected`, `frameTime`, `running` |
| `Visuals.Changed` | Signal fired when settings change |

Aliases: `play`, `attach`, `stopAll`, `sequence`, `configure`, `settings`, `stats`. Lazy sub-modules: `Motion`, `VFX`, `UI`, `Camera`, `Objects`, `Pets`, `Eggs`, `Rewards`, `Feedback`, `Audio`, `Themes`, `Icons`, `Screens`, `Presets`, `Debug`, `Quality`, `Springs`, `Curves`.

## VFX

`VFX/VFX.luau` (runtime), `VFX/EffectLogic.luau`, `VFX/RecipeLogic.luau`, `VFX/CatalogData.luau` and the `*Presets.luau` files (pure). Details: [VFX README](../../library/src/Visuals/VFX/README.md).

| Function | Description |
|---|---|
| `VFX.play(id: string, at: any, params: table?) -> Handle?` | Same as `Visuals:Play` |
| `VFX.attach(id: string, target: any, params: table?) -> Handle?` | Same as `Visuals:Attach` |
| `VFX.stop(handle: Handle?, immediate: boolean?)` | Loops fade for their particle lifetime; `immediate = true` destroys now. Safe on nil and twice |
| `VFX.stopAll(owner: any?) -> number` | Stops every VFX effect, or those of an owner; returns the count |
| `VFX.configure(config: { textures: { [string]: string }? })` | Texture ids by key |
| `VFX.textures() -> { [string]: string }` | The configured ids |
| `VFX.stats() -> table` | `live`, `effects`, `particles`, `lights`, `rejected`, `highlights`, `holders`, `presets` |
| `VFX.preload()` | Asks ContentProvider to load configured textures; returns at once |
| `VFX.registry` | `Core/Registry` of kind `vfx` |
| `VFX.EffectLogic` | The pure schema module: `validate(def)`, `resolve(def, profile, params, distanceScale, settings)`, `cost(def, params?)` |

Handle: `{ id, stop(immediate?), cancel(immediate?), isAlive() }`. Common params: `color`, `scale` (0.25..4), `intensity` (0..2), `owner`, `priority`, `parent`; `rarity`, `element` and `size` on the presets that declare them.

`RecipeLogic`: `Recipe.preset(spec)` builds a registry preset with standard params, usage line and cost label; `Recipe.join(...)` concatenates layer lists; the layer helpers are `particles`, `sparkles`, `glow`, `dust`, `groundDust`, `inward`, `streaks`, `ring`, `flash`, `light`, `beam`, `trail`, `highlight`, `shake`, `sound`, `postfx` and `multicolor`; `Recipe.costLabel(def)` gives `low`, `medium` or `high`; `Recipe.tier` and `Recipe.byRarity` build rarity variants. `CatalogData`: `Catalog.presets()`, `Catalog.registry()`, `Catalog.legacy()`, `Catalog.legacyPreset(name, preset)`, `Catalog.params(registry, id, overrides?)`.

## UI

`UI/UIAnimations.luau` (runtime), `UI/UILogic.luau`, `UI/UIPresets.luau` (pure). Details: [UI README](../../library/src/Visuals/UI/README.md).

| Function | Description |
|---|---|
| `UI.animate(gui: GuiObject, presetId: string, options: Options?) -> Handle` | Plays a preset. Options: `duration`, `speed`, `intensity`, `delay`, `easing`, `spring`, `mirror`, `priority`, `restore`, `color`, `colors`, `at`, `position`, `size`, `onDone(completed)`, `onMarker(name)` |
| `UI.stop(gui: GuiObject, restore: boolean?)` | Stops every preset on the object; `restore = true` returns it to rest and removes overlays |
| `UI.rest(gui: GuiObject)` | Recaptures the rest state after you change the object yourself |
| `UI.isAnimating(gui: GuiObject) -> boolean` | A preset chain is running |
| `UI.show(gui: GuiObject, presetId: string?, options: Options?) -> Handle` | Sets `Visible = true` and plays an entrance (default `PopIn`) |
| `UI.hide(gui: GuiObject, presetId: string?, options: Options?) -> Handle` | Plays an exit (default `PopOut`), then hides and restores rest. A newer `show` wins |
| `UI.stagger(guis: { GuiObject }, presetId: string, options: StaggerOptions?) -> Handle` | Plays a preset across a list. Extra options: `interval`, `order` (`forward`, `reverse`, `center`, `edges`, `random`), `seed`, `show` |
| `UI.bind(button: GuiObject, style: string?, options: BindOptions?) -> Binding` | Hover, press, release, selected and disabled states. Styles: `BouncyPress`, `Soft`, `Snappy`, `Premium`, `Arcade`, `Minimal`. Options: `target`, `enabled()`, `selected`, `disabled`, `color`, `onActivated`, `onState(status)` |
| `UI.countTo(label: TextLabel \| TextButton, to: number, options: CountOptions?) -> Handle` | Rolls a number. Options: `from`, `duration`, `easing`, `format`, `prefix`, `suffix`, `pop`, `onStep`, `onDone` |
| `UI.typewriter(label: TextLabel \| TextButton \| TextBox, text: string, options: TypeOptions?) -> Handle` | Reveals text. Options: `speed` (characters per second, 40), `onChar`, `onDone` |
| `UI.shine(gui: GuiObject, options: ShineOptions?) -> Handle` | A streak sweeps across. Options: `duration`, `delay`, `angle`, `width`, `alpha`, `color`, `loop`, `interval`, `onDone` |
| `UI.ripple(gui: GuiObject, options: RippleOptions?) -> Handle` | A circle grows from a point. Options: `at`, `color`, `duration`, `alpha`, `onDone` |
| `UI.flash(color: any?, options: FlashOptions?) -> Handle?` | Full-screen flash; honours reduced flashing. Options: `duration`, `alpha`, `onDone`. nil without a PlayerGui |
| `UI.backdrop(parent: Instance, options: BackdropOptions?) -> Handle` | A dim layer; `handle.Instance`; `stop()` fades it out and destroys it |
| `UI.popup(text: string \| number, at: any, options: PopupOptions?) -> Handle?` | Floating text at a world position, viewport pixels, GuiObject, part, attachment or model. Options: `style` (`damage`, `currency`, `crit`, `heal`), `color`, `size`, `duration`, `format`, `font`, `offset`, `onDone` |
| `UI.flyTo(from: any, toGui: GuiObject, options: FlyOptions?) -> Handle` | Items burst out and home onto a counter. Options: `count`, `image`, `color`, `size`, `spread`, `duration`, `stagger`, `seed`, `punch`, `onArrive(index)`, `onDone` |
| `UI.stats() -> { chains: number, popups: number, flyers: number }` | Live counts |
| `UI.registry`, `UI.Logic` | The `ui` registry and `UILogic` (`validate(recipe)`, `buttonEvent(state, event)`, `xpPlan`, ...) |

Handle: `stop(restore?)`, `cancel`, `finish()`, `isDone()`. Binding: `setSelected(bool)`, `setDisabled(bool)`, `status()`, `destroy()`; calling the binding also cleans up.

## Objects

`Objects/Objects.luau` (runtime), `Objects/ObjectsLogic.luau` (pure). Details: [Objects README](../../library/src/Visuals/Objects/README.md).

| Function | Description |
|---|---|
| `Objects.animate(target: Instance, presetId: string, options: Options?) -> Handle` | Plays a preset on a Model, BasePart, Attachment or GuiObject. Options: `amplitude`, `speed`, `duration`, `axis`, `phase`, `intensity`, `target`, `onDone(completed)`, `restore`, `allowUnanchored`, `fresh` |
| `Objects.stop(target: Instance, restore: boolean?)` | Stops it. Default: loops restore, one-shots stay |
| `Objects.isAnimating(target: Instance) -> boolean` | |
| `Objects.stopAll(restore: boolean?)` | Stops every object animation |
| `Objects.count() -> number` | Live animations |
| `Objects.registry` | Kind `object` |

Handle: `stop(restore?)`, `cancel()`, `finish()`, `isActive()`.

## Camera

`Camera/Camera.luau` (runtime), `Camera/CameraLogic.luau` (pure). Details: [Camera README](../../library/src/Visuals/Camera/README.md).

| Function | Description |
|---|---|
| `Camera.shake(presetOrDef: string \| ShakeDef, options: ShakeOptions?) -> Handle` | Additive shake. Options: `intensity`, `duration`, `amplitude`, `rotation`, `frequency`, `seed`, `position`, `radius` |
| `Camera.fov(target: number, options: MoveOptions?) -> Handle` | Eases the field of view and holds it until stopped |
| `Camera.zoom(factor: number, options: MoveOptions?) -> Handle` | Magnifies through FOV; `mode = "distance"` dollies instead |
| `Camera.punchFov(amount: number, options: MoveOptions?) -> Handle` | FOV kick that springs back. Skipped under reduced motion |
| `Camera.focus(target: Vector3 \| CFrame \| Instance, options: FocusOptions?) -> Handle` | Holds the camera at `distance`, `angle`, `elevation`, `height` from a target |
| `Camera.orbit(target, options: OrbitOptions?) -> Handle` | Circles a target at `speed` degrees per second |
| `Camera.pan(from: CFrame, to: CFrame, options: MoveOptions?) -> Handle` | Travels over `travel` seconds, then holds |
| `Camera.cinematic(name: string, target?, options: CinematicOptions?) -> Handle` | Plays a recipe; `onMarker(name)` fires at its beats |
| `Camera.restore(options: { shakes: boolean? }?)` | Force-releases everything; `{ shakes = false }` keeps shakes |
| `Camera.isActive() -> boolean` | A shake or move is live |
| `Camera.stats() -> { shakes: number, moves: number, bound: boolean }` | |
| `Camera.registry` | Kind `camera` |

Move options: `priority`, `blendIn`, `blendOut`, `duration`, `easing`, `fov`, `onDone(completed)`. Handle: `stop(blend?)`, `cancel()`, `finish()`, `isActive()`.

## Pets

`Pets/Pets.luau`, `PetAnimator.luau`, `PetFollow.luau`, `PetPreview.luau`, `PetSelection.luau`, `DemoPet.luau` (runtime); `PetsLogic.luau`, `SelectionLogic.luau` (pure). Details: [Pets README](../../library/src/Visuals/Pets/README.md).

| Function | Description |
|---|---|
| `Pets.animator(model: Model, options: Options?) -> PetAnimator` | Attaches an idle loop. Options: `phase`, `radius`, `idle`, `breathe`, `speed`, `turntable`, `everyFrame`, `animations`, `onReact(name)` |
| `Pets.find(model: Model) -> PetAnimator?` | The animator on a model |
| `Pets.play(id: string, model: Model, options: PlayOptions?) -> Handle` | Plays a reaction or a timeline |
| `Pets.follow(owner, pets: { Model }, options: Options?) -> Follower` | Pets trail an owner (Model, BasePart or function returning a CFrame) in a formation |
| `Pets.preview(viewportFrame: ViewportFrame, model: Model, options: Options?) -> Preview` | A clone in a ViewportFrame with its own camera |
| `Pets.selection(props) -> SelectionScreen` | The pet selection screen |
| `Pets.demoPet(options) -> Model` | The original demo pet (`color`, `variant` 1-3, `size`) |
| `Pets.stats() -> { animators: number, followers: number }` | |
| `Pets.registry`, `Pets.Logic` | Kind `pet`; `PetsLogic` |

PetAnimator: `:react(id, options?)`, `:setHover(bool)`, `:setSelected(bool)`, `:setRarity(rarity?)`, `:destroy(restore?)`. Follower: `:add(pet)`, `:remove(pet)`, `:setMode("rows" | "arc" | "circle" | "orbit")`, `:pets()`, `:destroy()`. Preview: `:react(id)`, `:setHover(bool)`, `:setSelected(bool)`, `:refit()`, `:destroy()`. SelectionScreen: `:select(id)`, `:confirm()`, `:focus(id?)`, `:selected()`, `:layout()`, `:destroy()`.

## Eggs

`Eggs/Eggs.luau` (runtime), `Eggs/HatchLogic.luau` (pure). Details: [Eggs README](../../library/src/Visuals/Eggs/README.md).

| Function | Description |
|---|---|
| `Eggs.hatch(config: Config) -> Hatch` | Runs the hatch cinematic. Config: `eggs`, `mode`, `origin`, `distance`, `speed`, `camera`, `ui`, `skippable`, `autoContinue`, `hold`, `parent`, `guiParent`, `sounds`, `onReveal(index, entry)`, `next` |
| `Eggs.idle(eggModel: Model, options: IdleOptions?) -> IdleHandle` | Sway and occasional hop; restored on stop |
| `Eggs.demoEgg(color?) -> Model`, `Eggs.demoPet(color?) -> Model` | The placeholder models |
| `Eggs.Logic` | `HatchLogic`: `plan`, `layout`, `wobble`, `idle`, `skipSteps`, `total`, `hitStop` |

Hatch: `skip()`, `finish()`, `cancel()`, `stop()`, `isRunning()`, signals `Revealed(index, entry)`, `Completed(results, skipped)`, `BatchCompleted(results)`.

## Rewards

`Rewards/Rewards.luau`, `Rewards/RewardView.luau` (runtime), `Rewards/RewardsLogic.luau` (pure). Details: [Rewards README](../../library/src/Visuals/Rewards/README.md).

| Function | Description |
|---|---|
| `Rewards.reveal(rarity: string, reward: Reward?, options: Options?) -> Handle` | Reveals one reward `{ name, amount?, icon?, image?, model?, subtitle? }` |
| `Rewards.batch(rewards: { { rarity, reward } }, options: Options?) -> Handle` | Rarest last; tiers below `options.threshold` share a grid |
| `Rewards.registerRarity(id: string, profile: table) -> Profile` | Registers a custom rarity; `extends` names a base; built-ins need `override = true` |
| `Rewards.rarity(id: string) -> Profile` | The profile (Common's for an unknown id) |
| `Rewards.rarities() -> { string }` | Ids, lowest rank first |
| `Rewards.plan(rarity: string, reward: Reward?, options: Options?) -> Plan` | The timeline a reveal would run |
| `Rewards.Logic` | `RewardsLogic` |

Options: `parent`, `position`, `speed`, `skipAnticipation`, `compact`, `skippable`, `autoDismiss`, `displayOrder`, `hint`, `fastForward`, `threshold`, `onDismiss`, `reducedMotion`, `reducedFlashing`. Handle: `skip()`, `finish()`, `dismiss()`, `cancel()`, `stop()`, `isRunning()`, signal `Completed(dismissed)`.

## Feedback

`Feedback/Feedback.luau` (runtime), `Feedback/FeedbackLogic.luau` (pure). Details: [Feedback README](../../library/src/Visuals/Feedback/README.md).

| Function | Description |
|---|---|
| `Feedback.fire(event: string, context: Context?) -> Fired` | Runs the event's recipe. Returns `{ handles, dropped, stop, cancel }` |
| `Feedback.define(event: string, recipe: Recipe)` | Defines or replaces one event; errors on an invalid recipe |
| `Feedback.use(pack: string \| { [string]: Recipe })` | A built-in pack name (`Simulator`, `Minimal`, `Combat`) or a table; replaces only the events it defines |
| `Feedback.clear(event: string?)` | Removes one recipe, or all |
| `Feedback.reset()` | Restores the Simulator pack |
| `Feedback.events() -> { string }` | Defined event names |
| `Feedback.recipe(event: string) -> Recipe?` | One recipe |
| `Feedback.packs() -> { string }` | Built-in pack names |
| `Feedback.connect(signal, event: string, mapContext: ((...any) -> Context?)?) -> () -> ()` | Fires the event when the signal fires; returns a disconnect function |
| `Feedback.Logic` | `FeedbackLogic` |

Step kinds: `vfx`, `ui`, `popup`, `flyTo`, `camera`, `sound`, `object`, `pet`, `reward`, `hatch`, `call`. Every step takes `delay`, `when`, `throttle`, `optional`.

## Audio

`Audio/Audio.luau` (runtime), `Audio/AudioLogic.luau` (pure). No sounds are bundled. Details: [Audio README](../../library/src/Visuals/Audio/README.md).

| Function | Description |
|---|---|
| `Audio.register(cue: string, idOrOptions: any)` | An id, or `{ id, volume, pitch, pitchVariance, cooldown, maxConcurrent, group }`; nil removes the cue |
| `Audio.registerMany(map: { [string]: any })` | Cue to id or options |
| `Audio.play(cue: string, options: PlayOptions?) -> Handle?` | nil when unregistered, cooling down, at its limit or muted. Options: `volume`, `pitch`, `pitchVariance`, `force`, `at` |
| `Audio.stop(handle: Handle?)`, `Audio.stopAll()` | |
| `Audio.setVolume(group: string?, volume: number)` | Group volume, or master when group is nil |
| `Audio.mute(value: boolean)`, `Audio.isMuted() -> boolean` | |
| `Audio.cues() -> { string }` | The cue names the kit plays |
| `Audio.registered() -> { string }`, `Audio.isRegistered(cue: string) -> boolean` | |

## Themes

`Themes/Themes.luau` (runtime), `Themes/ThemeData.luau`, `Themes/ThemeLogic.luau` (pure). Details: [Themes README](../../library/src/Visuals/Themes/README.md).

| Function | Description |
|---|---|
| `Themes.set(id: string) -> Theme` | Makes a theme current and switches the UrkUI style; errors on an unknown id |
| `Themes.get(id: string?) -> Theme` | A theme table, or the current one |
| `Themes.current() -> string` | Current theme id |
| `Themes.names() -> { string }` | Registered ids, sorted |
| `Themes.has(id: string) -> boolean` | |
| `Themes.register(id: string, theme: Theme, options: { override: boolean? }?) -> Theme` | Adds a custom theme after validating it |
| `Themes.derive(base: string \| Theme, overrides: table?) -> Theme` | Deep copy with overrides merged in |
| `Themes.token(path: string, id: string?) -> any` | For example `"motion.spring.press"` |
| `Themes.color(name: string, id: string?) -> Color3` | A colour role, a rarity or a hex string |
| `Themes.particleColors(id: string?) -> { Color3 }` | The theme's particle palette |
| `Themes.style(id: string?) -> string` | The `styles.json` key |
| `Themes.urkThemes() -> { [string]: ThemeDef }` | Role themes for `UrkUI.start({ themes = ... })` |
| `Themes.validate(theme: Theme) -> { Problem }` | Empty when valid |
| `Themes.Changed`, `Themes.IDS`, `Themes.DEFAULT` | Signal `(id, theme, previousId)`; built-in ids; `"VibrantSimulator"` |

## Icons

`Icons/IconVault.luau` (runtime), `Icons/IconVaultLogic.luau` (pure). No pack ships with the kit. Details: [Icons README](../../library/src/Visuals/Icons/README.md) and [the import workflow](../workflows/icon-pack-import.md).

| Function | Description |
|---|---|
| `Icons.register(pack: string, data: table, options: table?) -> number` | Registers a generated data module; returns the icon count |
| `Icons.unregister(pack)` | Removes a pack |
| `Icons.configure({ defaultPack?, assetIds?, sheets? })` | Default pack, asset ids and sheet ids per pack |
| `Icons.has(name: string) -> boolean` | A pack icon or a kit icon exists |
| `Icons.apply(label: ImageLabel \| ImageButton, name: string, options: ApplyOptions?) -> boolean` | Sets the image; falls back to the kit `Icons` module |
| `Icons.create(name: string, options: ApplyOptions?) -> ImageLabel` | A new label |
| `Icons.container(name: string, options: ContainerOptions?) -> Container` | A themed tile around the icon |
| `Icons.animated(name: string, presetId: string?, options: ContainerOptions?) -> Container` | A container that plays a `Visuals.UI` preset |
| `Icons.picker(props: PickerProps) -> Picker` | Search box, category tabs, virtualised grid |
| `Icons.bridge() -> () -> ()` | Makes pack icons usable by name in UrkUI components and screen specs; returns an undo function |
| `Icons.refresh()` | Restyles every live container |
| `Icons.get`, `search`, `categories`, `list`, `autocomplete`, `packs`, `info`, `assetId`, `missingAssetIds`, `setAssetIds`, `setSheetIds`, `setDefaultPack`, `defaultPack` | Registry queries from `IconVaultLogic` |

## Presets

`Presets/Presets.luau` (runtime: it requires the runtime modules), `Presets/PresetsLogic.luau` (pure).

| Function | Description |
|---|---|
| `Presets.search(query: string, limit: number?) -> { Entry }` | Best matches across every kind; entries are `{ kind, id, score }` |
| `Presets.list(kind: string?, filter: Filter?) -> { Entry }` | Every preset, or one kind; filter by `category`, `tag`, `theme`, `quality` |
| `Presets.describe(kind: string, id: string) -> table` | `kind`, `id`, `name`, `category`, `description`, `params`, `themes`, `quality`, `dependencies`, `preview`, `usage`, `tags`, `overridden` |
| `Presets.usage(kind: string, id: string) -> string` | One line of example code |
| `Presets.kinds() -> { string }`, `Presets.count() -> number` | |
| `Presets.register(kind: string, preset: Preset, options: { override: boolean? }?) -> Preset` | Adds a preset to the registry of its kind |
| `Presets.reset(kind: string, id: string) -> boolean` | Puts a built-in back after an override |
| `Presets.add(registry: Registry)` | Adds a game's own `Core/Registry` |
| `Presets.export() -> table` | Plain metadata for every preset: `{ kinds, total }` |

Registries collected: `vfx`, `ui`, `object`, `camera`, `pet`, and `screen` when a Screens module is installed.

## Debug

`Debug/Debug.luau` (runtime), `Debug/DebugLogic.luau` (pure).

| Function | Description |
|---|---|
| `Debug.overlay(parent: Instance?) -> () -> ()` | Shows live stats (default under PlayerGui); returns a close function |
| `Debug.profile(seconds: number, start: () -> any, done: (ProfileResult) -> ()) -> () -> ()` | Measures frame time before and with an effect; result has `averageMs`, `p99Ms`, `verdict` (`ok`, `noticeable`, `expensive`), `before`, `after`. Returns a cancel function |
| `Debug.stats() -> table` | `level`, `tracks`, `jobs`, `effects`, `particles`, `lights`, `spawned`, `evicted`, `rejected` |
| `Debug.dump()` | Prints every preset id by kind |

## Motion and Sequence

`Runtime/Motion.luau` (runtime) on `Core/Engine.luau` and `Core/Sequence.luau` (pure).

| Function | Description |
|---|---|
| `Motion.tween(target, goals: table, options: Options?) -> Handle` | Timed animation of ordinary Roblox values. Options: `duration`, `easing`, `delay`, `priority`, `repeatCount`, `reverses`, `restore`, `essential`, `from`, `onDone`, `onStep` |
| `Motion.spring(target, goals: table, spring: string \| Spring?, options: Options?) -> Handle` | Spring animation |
| `Motion.animate(target, options: Options & { props: table }) -> Handle` | The general form |
| `Motion.punch(target, property: string, amount: any, spring?) -> Handle` | Kicks a property and lets it settle back |
| `Motion.native(instance: Instance, goals: table, options?) -> Tween?` | TweenService, off the Luau frame loop |
| `Motion.stop(target, restore: boolean?)`, `Motion.restore(target, properties: { string }?)` | |
| `Motion.isAnimating(target, property: string?) -> boolean`, `Motion.count() -> number` | |
| `Motion.sequence(runner?) -> Sequence` | A sequence on the shared clock |
| `Motion.stagger(items, interval: number, each: (item, index) -> ()) -> () -> ()` | Calls `each` per item, spaced in time; returns cancel |
| `Motion.delay(seconds: number, callback: () -> ()) -> () -> ()` | A cancellable timer on the shared clock |
| `Motion.Springs`, `Motion.Curves` | The core modules |

Engine handle: `cancel(restore?)`, `finish()`, `pause()`, `resume()`, `isDone()`, `completed`, `skipped`. Virtual properties (`Runtime/Props`): `Scale`, `GroupFade`, `Pivot`, `PivotCFrame`, `ModelScale`.

Sequence builder: `Play(name, ...)`, `Sound(cue, options?)`, `Wait(seconds)`, `At(time)`, `Call(fn)`, `Animate(target, spec)`, `Marker(name)`, `Parallel(...)`, `Stagger(...)`, `Cleanup(fn)`, `OnDone(fn)`, `OnMarker(fn)`, `Speed(factor)`; controls: `Start()`, `Skip()`, `Cancel()`, `Pause()`, `Resume()`. Skipping drops cosmetic steps that have not fired and still runs `Call`, `Animate` and `Marker` steps with `ctx.skipped = true`; every `Cleanup` runs exactly once in all endings.

## Core modules

All pure. Reached as `Visuals.Quality`, `Visuals.Springs`, `Visuals.Curves`, or by requiring the file.

| Module | Functions |
|---|---|
| `Core/Clock` | `Clock.new()`; `clock:add(job) -> remove`, `clock:after(seconds, fn) -> cancel`, `clock:step(dt)`, `clock:now()`, `clock:count()` |
| `Core/Engine` | `Engine.new(adapter, clock)`; `engine:animate(target, spec) -> Handle`, `stop`, `restore`, `isAnimating`, `cancelAll`, `count` |
| `Core/Springs` | `Springs.NAMES`, `has(name)`, `get(spring?)`, `register(name, spring)`, `step(position, velocity, target, dt, spring)`, `settled(...)`, `settleTime(spring?, epsilon?)`. Presets: Gentle, Soft, Snappy, Bouncy, Elastic, Overshoot, Heavy, Playful, Premium, Cinematic |
| `Core/Curves` | `get(name?)`, `has(name)`, `names()`, `ease(curve, t)`, `register(name, curve)`, `bezier(x1, y1, x2, y2)`, `steps(count)`, `yoyo(curve)`, `blend(a, b, weight)` |
| `Core/Sequence` | `Sequence.new(runner)` and the builder above |
| `Core/Registry` | `Registry.new(kind)`, `Registry.validate(preset)`; `register`, `unregister`, `get`, `find`, `has`, `original`, `isOverridden`, `reset`, `list`, `ids`, `categories`, `search`, `params`, `describe`, `count` |
| `Core/Quality` | `LEVELS`, `isLevel`, `profile(level)`, `rank`, `atLeast`, `fromLegacy`, `toLegacy`, `choose(device)`, `defaults()`, `merge`, `juice(settings, kind?)`, `scaleCount`, `distanceScale`, `adaptive(level, ceiling?)`, `adapt(state, frameTime, options?)` |
| `Core/Effects` | `Effects.new(host)`; `effects:spawn(request) -> handle?, reason?`, `stopOwner`, `stopId`, `stopAll`, `stats` |
| `Core/Pool` | `Pool.new({ create, reset, destroy, max })`; `acquire`, `release` |
| `Runtime/Host` (runtime) | `Host.clock`, `Host.engine`, `Host.effects`, `Host.Changed`, `settings()`, `profile()`, `juice(kind?)`, `frameTime()`, `configure(partial)`, `detect()`, `isRunning()` |

## Preset counts

From `catalog/visuals.json` at the time of writing; the generated [visuals-presets.md](visuals-presets.md) has the tables and is the current source.

| Kind | Count | Notes |
|---|---|---|
| World VFX | 83 | 78 built-in presets in 8 categories (rewards 13, pets 14, eggs 5, combat 11, movement 7, environment 13, progression 10, feeding 5) plus 5 `Legacy*` presets bridged from `Systems/VFX` |
| UI animations | 70 | buttons 19, panels 22, text 5, cards 9, navigation 11, notifications 4 |
| Object animations | 18 | 7 loops, 11 one-shots |
| Camera | 18 | 8 shakes, 4 cinematics, 6 move entries (metadata for `focus`, `orbit`, `pan`, `zoom`, `fov`, `punchFov`) |
| Pet | 10 | 4 reactions, 6 timelines |
| Rarity profiles | 7 | Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret |
| Feedback events | 24 | 20 in the Simulator pack; Combat adds 4; Minimal and Combat override some |
| Audio cues | 29 | names only; no sounds are bundled |
| Themes | 10 | |
| UI/Game components | 37 | 19 from 0.3.0, 17 animated components added in 0.5.0, and PurchaseBridge |
