# UltimateVisualsKit demos and playground

Five flagship demos and an interactive playground for the visuals kit (`src/Visuals/`) and the
UrkUI Game components. Everything here is a client-side example: it uses the public entry points
only, builds every prop from Parts in code (no assets, no asset ids) and fakes its "server" with
local functions that are labelled `STAND-IN FOR THE SERVER` and grant nothing.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local UrkUI = require(ReplicatedStorage.UltimateRobloxKit.UI.UrkUI) -- UrkUI.Game = the components
```

## Status: NEEDS MANUAL REVIEW

**None of this was run in Studio.** What was checked in this repository: `rojo build` of the project
succeeds, StyLua and Selene are clean, `luau-lsp analyze` with the project's own sourcemap reports
no errors in these files, `DemoLogic.luau` and `Playground/PlaygroundLogic.luau` pass
`luau-analyze --mode=strict`, and their Lune specs pass (`tests/visuals_demos.spec.luau`,
`tests/visuals_demos_playground.spec.luau`). Layout, motion, effects, camera behaviour and
cleanup need a playtest with the checklists below.

## Build and run

From the repository root, with the pinned tools installed (`rokit install` in `library/`):

```bash
rojo serve library/examples/visuals/visuals.project.json
```

1. Open a new Baseplate place in Studio (not a published game).
2. In the Rojo plugin press **Connect**. Studio gets `ReplicatedStorage.UltimateRobloxKit`,
   `StarterPlayer.StarterPlayerScripts.UvkDemos` (the launcher and the demo modules), a floor and a
   spawn.
3. Press **Play**. The launcher menu is on the left: pick a demo, **STOP DEMO** ends it.

To build a place file instead: `rojo build library/examples/visuals/visuals.project.json -o uvk-demos.rbxl`.

The paths in the project are relative to this folder (`../../src`), like `examples/playground`.

## Files

| File | Purpose |
|---|---|
| `visuals.project.json` | Rojo place: the library in ReplicatedStorage, the demos in StarterPlayerScripts, a floor |
| `Launcher.client.luau` | LocalScript menu; starts one demo at a time; reduced motion / flashing toggles |
| `DemoKit.luau` | Shared demo helpers: cleanup scopes, bootstrap, stage, blocky animals, food, panels |
| `DemoLogic.luau` | Pure, strict: throw arcs, wind-up, coin scatter, tap-rate stream, simulator numbers, sample data |
| `PetSelectionDemo.luau` ... `AnimalFeedingDemo.luau` | The five demos; each returns `{ title, description, start(parent) -> stop }` |
| `Playground/Playground.luau` | The playground (same `start(parent) -> stop` shape) |
| `Playground/PlaygroundLogic.luau` | Pure, strict: categories, generated controls, example code, list window, metrics |

Every demo puts what it creates in one cleanup scope; `stop()` destroys its instances, stops its
handles, disconnects its connections and is safe to call twice.

## Reduced motion bridge

UrkUI and the visuals kit each have a reduced-motion switch (the animated Game components follow
the visuals one). `DemoKit.bootstrap()` links them; in your own game the two directions are:

```lua
Visuals.Changed:Connect(function(s) UrkUI.setReducedMotion(s.reducedMotion) end) -- Visuals -> UrkUI
Visuals.Configure({ reducedMotion = UrkUI.isReducedMotion() })                   -- UrkUI -> Visuals (after UrkUI.start)
```

`UrkUI.start()` reads the player's Reduce Motion setting; the second line copies it into Visuals.
`DemoKit.setReducedMotion(value)` sets both at once (the launcher toggle uses it).

## The demos

### 1. Pet selection (`PetSelectionDemo`)
`Visuals.Pets.selection` with four original demo pets (Pebble, Sprout, Ember, Nimbus) with names,
descriptions, rarities and stats; select and confirm are logged. Confirm spawns the pet next to
the stage with `Visuals.Pets.play("Spawn")`, then `Visuals.Pets.follow` walks it after the
player, and a toast confirms. Also: a HappyReaction button, Release (Despawn).
APIs: `Pets.selection`, `Pets.demoPet`, `Pets.play`, `Pets.follow`, `Visuals.Play`, `UrkUI.toast`.

### 2. Egg hatching (`EggHatchingDemo`)
An egg stand (pedestal, display egg with `Eggs.idle` and a ChestGlow). Buttons: Common, Rare,
Legendary, Mythic single hatch, triple hatch, eight-egg multi hatch, an auto-hatch toggle
(`mode = "auto"` with `next`), and the skip hint. Results and reveals are logged.
APIs: `Eggs.hatch` (`Revealed`, `Completed`, `BatchCompleted`, `stop`, `cancel`), `Eggs.idle`,
`Eggs.demoEgg`, `Visuals.Attach`.

### 3. Reward reveal (`RewardRevealDemo`)
A button per rarity (Common to Secret), a custom rarity registered by the demo ("Stardust",
extends Legendary), a batch of six mixed rewards and a fast-forward toggle. World VFX play on the
stage; the reward is shown as a small demo pet.
APIs: `Rewards.reveal`, `Rewards.batch`, `Rewards.registerRarity`, `Pets.demoPet`.

### 4. Simulator feedback (`SimulatorFeedbackDemo`)
A tap crystal (world, ClickDetector) and a big TAP button fire `Feedback.fire("Tap")`; each tap
drops a coin that is collected with `CollectCoin` (burst, fly to counter, counter roll). Upgrade
button (`UpgradeItem`, `Error` when too poor), an XPBar that fires `LevelUp`, a rebirth button
(`RebirthDone`, level 3+), a QuestCard that fires `QuestComplete` plus a toast. Toggles: Debug
overlay (`Visuals.Debug.overlay`) and "Spam 20 taps/sec" (`DemoLogic.newTapper`); the stats box
shows tap events, steps held back by recipe throttles, live effects, particles and the
`Visuals.Stats().rejected` reasons.
APIs: `Feedback.fire`, `Objects.animate`, `UI.countTo`, `Debug.overlay`, `Visuals.Stats`,
`UrkUI.Game.XPBar`, `QuestCard`.

### 5. Animal feeding (`AnimalFeedingDemo`)
Two original blocky animals (Bramble the hopper, Puddle the waddler) bounce idly
(`Objects.animate("Bounce")`). A tray holds three foods. A throw: 0.22 s wind-up
(`DemoLogic.windUp`), a ballistic arc (`DemoLogic.arc` / `arcPoint` / `arcVelocity`), then the
`FeedAnimal` feedback (FoodTrail on the projectile, throw / hit sounds, FoodSplat, HeartBurst and a
popup, all delayed by the flight time), CrumbBurst at impact, the animal's `Interact`
squash-and-stretch followed by `HappyReaction`, hunger / happiness ProgressBars, a coin popup and
fly-to-counter; a RewardPopup when an animal is full and happy. Every fourth throw, or the "aim
wide" toggle, misses: FoodSplat and LandingDust on the ground.
APIs: `Feedback.fire`, `Visuals.Play` / `Attach`, `Objects.animate`, `Pets.play`, `UI.popup`,
`UI.flyTo`, `UI.countTo`, `UrkUI.Game.ProgressBar`, `RewardPopup`.

## The playground (`Playground/`)

Started from the launcher's last button. A window on the right with:

- **Categories**: VFX, UI animations, Objects, Camera, Pets, Rewards, Eggs, Feedback, Themes,
  Icons, Components, Demos.
- **Search** (`Visuals.Presets.search` for registry kinds, word filter otherwise) and a list from
  `Visuals.Presets.list(kind)` whose rows exist only while near the viewport.
- **Detail**: name, description, cost / minimum-quality / category chips, controls generated from
  the preset's `params` (number: Slider, boolean: Toggle, enum: Dropdown, colour: swatches from the
  current theme), Play / Replay / Stop / Reset, and the **example code** box: the exact call for
  the selection with only non-default params, keys sorted (`PlaygroundLogic.exampleCode`).
- **Settings**: theme (all `Visuals.Themes.names()`), quality Low / Medium / High / Ultra
  (`Visuals.Configure`), reduced motion, reduced flashing.
- **Metrics**: fps (sampled locally), tracks, jobs, effects, particles, lights and rejected
  reasons from `Visuals.Stats()`.
- **Preview stage** left of the window: a target ball (VFX play / attach there, camera presets aim
  at it and restore), a gift-box model (object animations), a demo pet (pet reactions and
  timelines). UI animations play on a sample button, panel, card and text in the detail panel.
- **Icons**: `Visuals.Icons.picker` (kit icons; vault pack icons appear once a pack module is
  registered, and need uploaded asset ids before they display).
- **Components**: one instance of each of the 36 UrkUI Game components with state buttons (prop
  updates or method calls such as `open`, `gain`, `reveal`, `startCooldown`).
- **Demos**: runs any demo with the playground minimised and a "back" button.

There is **no pause toggle**: the kit exposes no public time scale for `Host.clock`, and the
playground does not reach into Runtime. Closing (X) or stopping from the launcher removes
everything, restores the camera and stops all effects.

## Manual test checklist (from docs/research/visuals/design-principles.md)

Mark each line in Studio. Global, for every demo:
- [ ] Starting and stopping each demo five times leaves no instances in Workspace / PlayerGui and
  `Visuals.Stats()` returns to 0 effects and 0 tracks.
- [ ] With Reduced motion on: no camera shake, no looping motion, no positional travel.
- [ ] With Reduced flashing on: no full-screen flash anywhere, including Mythic / Secret reveals.
- [ ] No control is smaller than 44 px on a phone-sized viewport; nothing sits under the
  thumbstick or jump button.

Pet selection:
- [ ] Hovering / selecting a card responds within one frame; the selection never jumps when
  interrupted.
- [ ] Gamepad and arrow keys move the selection; Enter / A confirms; the screen closes.
- [ ] Spawn plays its burst before the pet pops in; the follower starts after it and keeps the pet
  on the ground; Release despawns and removes the model.
- [ ] Rarity is readable from the label, not only the colour.

Egg hatching:
- [ ] Common is short and pleasant, Mythic clearly longer with more layers; each tier exceeds the
  one below.
- [ ] Clicking during a hatch skips to the result and shows it; clicking again dismisses.
- [ ] After a hatch (completed, skipped or the demo stopped mid-hatch) CameraType, CFrame and
  FieldOfView equal their values from before.
- [ ] The 8-egg hatch does not clutter: only rarer pets get rarity effects, one celebration.
- [ ] Auto-hatch stops after the batch on screen when toggled off.

Reward reveal:
- [ ] Seven rarities form a clear ladder; the custom Stardust sits between Legendary and Mythic.
- [ ] Two reveals within 2 s do not both play in full (the demo refuses the second).
- [ ] Fast-forward shortens reveals but still shows the final state; the batch shows the rarest
  last.

Simulator feedback:
- [ ] Spam 20 taps/sec for 10 s: floating numbers never exceed the configured cap, the "steps
  throttled" count rises, frame time stays within budget (write down the measured value).
- [ ] The coin counter text updates at most once per frame; fly-to items stay under the cap.
- [ ] Debug overlay opens and closes cleanly; LevelUp, RebirthDone and QuestComplete each play once
  per event.
- [ ] Every sound cue in a recipe has a visual step (sounds are silent unless registered).

Animal feeding:
- [ ] The wind-up is visible before release; the food follows a smooth arc and lands where it
  aims; the trail ends at the landing.
- [ ] A hit plays splat, crumbs, hearts and the popup at the moment of impact, then the squash and
  the happy hop, then the idle bounce resumes without a jump.
- [ ] A miss lands on the ground with a splat and dust, and no reaction or reward.
- [ ] Bars animate and decay; coins fly to the counter and the total matches.

Playground:
- [ ] Every category lists entries; scrolling the 83 VFX presets keeps only ~15 row instances.
- [ ] Changing a control updates the example code; pasting that code reproduces the preview.
- [ ] Theme, quality and reduced-motion switches take effect on the next Play.
- [ ] Camera presets always restore the camera, including after Stop mid-move.
- [ ] Every Game component builds and each state button works (failures show in the status line).
