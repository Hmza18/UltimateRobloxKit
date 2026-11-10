---
name: uvk-pet-visuals
description: Pet presentation with UltimateVisualsKit's Visuals.Pets - a rig-agnostic pet animator (idle bob, breathing, sway, hover and selected states, rarity aura), reactions and timelines (HappyReaction, SelectBounce, Spawn, Equip, Evolve), followers in rows, arc, circle or orbit formations with ground alignment, ViewportFrame previews and the flagship pet selection screen with mouse, touch, keyboard and gamepad input. Use when making pets feel alive, building a starter or pet selection screen, making pets follow the player, or showing a pet in the UI.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [pet selection, pet selection screen, starter pet, pet animation, pet follow, pets follow the player, pet reaction, pet idle, pet preview, pet viewport, choose your pet, pet formation]
  depends: [uvk-visuals-kit]
---

# UVK pet visuals

Everything here is cosmetic and client-side. Which pets a player owns, and what a choice means, is the server's job (`Systems/Pets`, see `roblox-simulator-systems`).

## When to use

- Idle life, reactions and spawn, equip, evolve moments for any pet Model (no Humanoid or Motor6D needed).
- Pets trailing a character; a pet shown in a ViewportFrame; a "choose your pet" screen.

When not to use: egg odds, hatching rules, inventory and trading (`roblox-simulator-systems`); the hatch cinematic (`uvk-egg-hatching`); rigged skeletal clips (`roblox-animation`, which the animator can also play through its `animations` option).

## Inputs

- Pet Models, anchored, with a sensible pivot near the centre. Entries without a model get the kit's demo pet.
- For the selection screen: three or more `{ id, name, description?, rarity?, model?, color?, stats? }` and the server remote that receives the choice.

## Workflow

1. **Give each visible pet an animator.** One shared clock job updates all of them.

   ```lua
   local Pets = Visuals.Pets
   local animator = Pets.animator(petModel)        -- idle: bob, breathing, sway
   animator:react("HappyReaction")
   animator:setHover(true)
   animator:setSelected(true)
   animator:setRarity("Legendary")                  -- attaches the RarityAura VFX preset
   animator:destroy()                               -- restores the model
   ```

2. **Play moments by id.** Reactions: `HappyReaction`, `CuriousReaction`, `SelectBounce`, `HoverReaction`. Timelines (with their VFX): `Spawn`, `Despawn`, `Equip`, `Unequip`, `Evolve`, `Upgrade`.

   ```lua
   Pets.play("Spawn", petModel, { rarity = "Epic" })
   Pets.play("Evolve", petModel)                    -- rattle, energy build, burst, celebration
   ```

   After `Despawn` the model is scaled to nothing: destroy it or play `Spawn` again.

3. **Followers.** Run one follower per client for the pets that client shows.

   ```lua
   local follower = Pets.follow(character, { petA, petB, petC }, { mode = "arc" })
   follower:add(petD)
   follower:setMode("orbit")                        -- rows, arc, circle, orbit
   follower:destroy()
   ```

   Options: `spacing`, `distance`, `perRow`, `orbitSpeed`, `frequency`, `maxSpeed`, `teleportDistance`, `hover`, `ground`, `walkBob`, `exclude`.

4. **Previews in UI.**

   ```lua
   local preview = Pets.preview(viewportFrame, petModel, { turntable = 24 })
   preview:react("SelectBounce")
   preview:destroy()
   ```

5. **The selection screen.** It handles layout (row, compact, two-column portrait, scroller), safe areas, hover, tap, keyboard and gamepad, the select and confirm moments, and cleanup.

   ```lua
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
   		chooseStarter:FireServer(id)               -- the server validates and decides
   	end,
   })
   -- screen:select(id), screen:confirm(), screen:focus(id?), screen:selected(), screen:destroy()
   ```

   Props also include `confirmText`, `style`, `theme`, `palette`, `selected`, `onSelect`, `worldPosition` (confetti on confirm), `closeOnConfirm`, `insets`.

6. **Rigged pets.** Pass `animations = { idle = ..., walk = ..., happy = ... }` to the animator to play real AnimationTracks alongside the procedural motion.

7. **Clean up** on unequip, respawn and screen close: `animator:destroy()`, `follower:destroy()`, `preview:destroy()`, `screen:destroy()`.

## Outputs

- A client pet controller (animators and one follower) and, when asked, the selection screen wired to a server remote.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_pets`. These cover idle maths, formations, follow, ground alignment and the selection layout and navigation. In Studio (`NEEDS MANUAL REVIEW`): motion feel, ground raycasts on slopes, the selection screen on phone portrait, phone landscape, tablet, desktop and gamepad-only, and that the character does not walk while the screen is open.

## Pitfalls

- **Unanchored pets** fight physics when moved with `PivotTo`. Anchor them and disable collisions.
- **Pivot far from the centre** makes the pet swing in previews and reactions. Fix the pivot.
- **Aura missing in a preview.** ViewportFrames cannot render particles or beams.
- **Server-side followers.** Replicating per-frame pet CFrames costs bandwidth; follow on each client.
- **Trusting `onConfirm`.** It reports intent. The server checks the id and grants the pet.
- **Many previews.** A screen with many cards has that many ViewportFrames; page or virtualise long lists.

## Limitations

- `PetsLogic` and `SelectionLogic` are covered by Lune specs. `PetAnimator`, `PetFollow`, `PetPreview`, `PetSelection` and `DemoPet` create or move Instances and were not run in Studio.
- Models scale uniformly, so pet squash and stretch is a damped vertical scale with the feet planted.
- Followers do not path around walls; a pet beyond `teleportDistance` snaps back to the formation.
