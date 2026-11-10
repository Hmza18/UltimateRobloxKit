# Visuals / Pets

Pet animation for any Model: idle, reactions, spawn and evolve timelines, followers in formation, viewport previews and the pet selection screen. Rig-agnostic: it moves the whole model, so no Humanoid or Motor6D is needed.

Everything here is cosmetic and client-side. Which pets a player owns, where they are on the server and how other players see them is the game's job. Run a follower on each client for the pets it shows.

| File | What |
|---|---|
| `PetsLogic.luau` | Pure maths (Lune-tested): idle, reactions, formation, follow, ground, scheduler, timelines, registry |
| `SelectionLogic.luau` | Pure layout and navigation for the selection screen (Lune-tested) |
| `PetAnimator.luau` | The animator and the one shared `Host.clock` job |
| `PetFollow.luau` | Followers |
| `PetPreview.luau` | ViewportFrame previews |
| `PetSelection.luau` | The selection screen |
| `DemoPet.luau` | An original demo pet built from Parts |
| `Pets.luau` | The public module |

## API

| Function | Does |
|---|---|
| `Pets.animator(model, options?) -> PetAnimator` | Attaches an idle loop: bob, breathing, sway |
| `Pets.find(model)` | The animator on a model, if any |
| `Pets.play(id, model, options?) -> Handle` | Plays a reaction or a timeline. Uses the model's animator, else a temporary one |
| `Pets.follow(owner, pets, options?) -> Follower` | Pets trail an owner in a formation |
| `Pets.preview(viewportFrame, model, options?) -> Preview` | A clone in a ViewportFrame with its own camera |
| `Pets.selection(props) -> SelectionScreen` | The selection screen |
| `Pets.demoPet(options?) -> Model` | Builds the demo pet (`color`, `variant` 1-3, `size`) |
| `Pets.registry` | `Core/Registry`, kind `pet` |

**PetAnimator:** `:react(id, options?)`, `:setHover(bool)`, `:setSelected(bool)`, `:setRarity(rarity?)`, `:destroy(restore?)`. Options: `phase`, `radius`, `idle`, `breathe`, `speed`, `turntable`, `everyFrame`, `animations`, `onReact(name)`.

- `:setRarity` attaches the VFX preset `RarityAura` with `owner = model`. It does nothing when the VFX module is absent.
- `animations = { idle = Animation | id, walk = ..., happy = ..., curious = ..., select = ..., hover = ... }` plays real animations on rigged models, through an Animator found or created under the model's Humanoid or AnimationController. They play alongside the procedural motion.

**Follower:** `:add(pet)`, `:remove(pet)`, `:setMode("rows" | "arc" | "circle" | "orbit")`, `:pets()`, `:destroy()`. `owner` is a Model, a BasePart or a function returning a CFrame.

| Follow option | Default |
|---|---|
| `mode` | `"rows"` |
| `spacing`, `distance`, `perRow`, `orbitSpeed` | from the largest pet's radius; 30 degrees per second |
| `frequency` (spring Hz), `maxSpeed`, `teleportDistance` | 2.2, 60, 70 |
| `hover` (flying height; flying pets do not tilt) | 0 |
| `ground`, `groundDepth`, `groundInterval` | true, 40 studs, 0.4 s |
| `ownerHeight` (used when no ground is found) | 3 |
| `walkBob` | true |
| `exclude` (extra instances the raycast ignores) | none |

**Preview:** `:react(id)`, `:setHover(bool)`, `:setSelected(bool)`, `:refit()`, `:destroy()`. Options: `turntable` (24 degrees per second), `fov` (35), `padding`, `angle`, `elevation`, `clone`, `ambient`, `lightColor`, `lightDirection`.

**SelectionScreen:** `:select(id)`, `:confirm()`, `:focus(id?)`, `:selected()`, `:layout()`, `:destroy()`.

| Selection prop | Meaning |
|---|---|
| `parent` | PlayerGui (a ScreenGui is created), a ScreenGui or a GuiObject |
| `title`, `subtitle`, `confirmText` | Text |
| `pets` | Three or more `{ id, name, description?, rarity?, model?, color?, palette?, stats? }` |
| `style`, `theme`, `palette` | UrkUI style name, Visuals theme id, backdrop palette |
| `selected` | Id selected on open |
| `onSelect(id)`, `onConfirm(id)` | Callbacks |
| `worldPosition` | Where to play `Confetti` on confirm (needs the VFX module) |
| `closeOnConfirm` | Default true |
| `insets` | Overrides the measured safe area |

`stats` is a list of `{ label, value }` or a dictionary.

## Presets

| Id | Kind | What |
|---|---|---|
| `HappyReaction` | reaction, 0.9 s | Two hops with squash and stretch and a full spin |
| `CuriousReaction` | reaction, 1.1 s | Head tilt and a lean toward a point |
| `SelectBounce` | reaction, 0.45 s | Squash, springy pop, settle |
| `HoverReaction` | reaction, 0.5 s | Lift and grow (`:setHover` holds it) |
| `Spawn` | timeline | `PetSpawn` burst, pop out with an overshoot, small bounce |
| `Despawn` | timeline | Swell, shrink to nothing, `PetDespawn` puff |
| `Equip` | timeline | `PetEquip` and a bounce |
| `Unequip` | timeline | Quick squash and `PetUnequip` |
| `Evolve` | timeline | Rattle while energy builds, `PetEvolve` burst with a stretch, celebration |
| `Upgrade` | timeline | Bounce and `PetUpgrade` |

After `Despawn` the model is left scaled to nothing: destroy it, or play `Spawn` on it again.

## Example

```lua
local Pets = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Pets.Pets)

local animator = Pets.animator(petModel)
animator:react("HappyReaction")
animator:setRarity("Legendary")

Pets.play("Spawn", petModel, { rarity = "Epic" })

local follower = Pets.follow(character, { petA, petB, petC }, { mode = "arc" })
follower:setMode("orbit")

local screen = Pets.selection({
	parent = playerGui,
	title = "Choose your starter",
	subtitle = "You can collect the others later",
	pets = {
		{ id = "ember", name = "Ember", description = "Brave and warm.", rarity = "Rare", color = "#FF8A3D" },
		{ id = "moss", name = "Moss", description = "Calm and sturdy.", color = "#58C26A" },
		{ id = "drift", name = "Drift", description = "Quick and curious.", color = "#5AB0FF" },
	},
	onConfirm = function(id)
		chooseStarter:FireServer(id) -- the server decides what the choice means
	end,
})
```

## Selection screen

- **Layout** (`SelectionLogic.layout`): one centred row on wide screens; compact cards on short landscape phones; a two-column grid in portrait; a scroller when the cards cannot fit. The safe area is measured with a second ScreenGui that Roblox insets (`CoreUISafeInsets`).
- **Pointer and touch:** hover lifts the card and the pet. A tap selects. Tapping the selected card again, or the button, confirms.
- **Keyboard:** arrow keys or A / D / W / S move the focus (wrapping). Enter or Space selects the focused card, then confirms.
- **Gamepad:** DPad or left stick move the focus; ButtonA selects, then confirms.
- Keys are bound through `ContextActionService` and sunk, so the character does not walk while the screen is open. Focus is manual; `GuiService.SelectedObject` is not used.
- **Select:** the pet plays `SelectBounce` then `HappyReaction`, the indicator slides to the card, the others dim, the confirm button pops in and pulses.
- **Confirm:** a soft flash (`UI.flash`, which honours reduced flashing), optional `Confetti`, the chosen card moves forward, the others fall away, then `onConfirm` fires and the screen closes.
- Entries without a `model` get the demo pet in their `color`.
- Components are `UI/Game` `Panel`, `GameText`, `CartoonButton`, `Badge` and `RarityFrame` with `Style` tokens, so styles and themes apply.
- `UI/UIAnimations` is used when present: `stagger` for the card entrance, `show` / `hide` for the confirm button, `flash`. Otherwise `Runtime/Motion` does the same. `UI.bind` is not used: `CartoonButton` already has hover and press states, and the cards need their own lift.

## Performance

- One `Host.clock` job updates every animator and every follower. It exists only while there is a pet.
- Idle motion is recomputed at the profile's `petUpdateHz` (Low 20, Medium 30, High every frame) in round-robin buckets. With more than 24 pets, buckets are added at any level. A pet that is reacting, or being moved by a follower, updates when it needs to.
- Ground raycasts are cached per pet and repeated every 0.4 s or after 2 studs of travel.
- One `PivotTo` per pet update, composed from the stored base CFrame. `Model:ScaleTo` is called only when the scale changes by more than 0.004, and breathing is off on Low.
- Previews update every frame. A selection screen with many cards has that many ViewportFrames.

## Limits

- Models scale uniformly, so squash and stretch on a pet shows as a damped vertical scale with the feet kept planted. It is not a true non-uniform squash.
- Followers move anchored models with `PivotTo`. Unanchored pets fight physics.
- ViewportFrames do not render particles, beams or trails, and their only lighting is `Ambient`, `LightColor` and `LightDirection`. A rarity aura does not show in a preview.
- A preview turns the pet around its pivot. A pivot far from the model's centre makes it swing.

## Not verified in Studio

`PetsLogic` and `SelectionLogic` are covered by `tests/visuals_pets.spec.luau` and `tests/visuals_pets_selection.spec.luau`. `PetAnimator`, `PetFollow`, `PetPreview`, `PetSelection`, `DemoPet` and `Pets` were NOT run in Studio. How the motion looks, raycast ground alignment, AnimationTrack playback, safe-area measurement, input binding on each device and the look of the selection screen are `NEEDS MANUAL REVIEW`.
