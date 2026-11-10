# Eggs

The hatch cinematic. `HatchLogic` plans the eleven beats, the per-egg layout and the wobble curve; `Eggs` builds a client-side stage in front of the camera and runs the plan as a `Core/Sequence`. A hatch is presentation only: the server decides what the eggs contain first.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

local hatch = Visuals.Eggs:Hatch({
	eggs = {
		{ rarity = "Legendary", name = "Dragon", pet = dragonModel, isNew = true },
		{ rarity = "Common", name = "Kitten", pet = kittenModel },
		{ rarity = "Rare", name = "Fox" }, -- no model: a demo pet is built
	},
})
hatch.Revealed:Connect(function(index, entry) end)
hatch.Completed:Connect(function(results, skipped) end)

-- Auto-hatch: about a second per batch, no camera, no input, until next() returns nil.
local auto = Visuals.Eggs:Hatch({ mode = "auto", eggs = firstBatch, next = function() return nextBatch() end })
auto.stop()

local idle = Visuals.Eggs:Idle(shopEggModel)
```

## API

| Function | Result |
|---|---|
| `Eggs.hatch(config)` | `Hatch`: `skip()`, `finish()`, `cancel()`, `stop()`, `isRunning()`, `Revealed(index, entry)`, `Completed(results, skipped)`, `BatchCompleted(results)` (auto mode) |
| `Eggs.idle(eggModel, options?)` | Handle with `stop()` / `cancel()`; sway and occasional hop, restored on stop |
| `Eggs.demoEgg(color?)` / `Eggs.demoPet(color?)` | The original placeholder models used when no model is given |
| `Eggs.Logic` | `HatchLogic`: `plan`, `layout`, `wobble`, `idle`, `skipSteps`, `total`, `hitStop` |

Config: `eggs` (`{ rarity, pet = Model or function, egg = Model?, name?, isNew?, color? }`), `mode` (`"auto"`, otherwise from the count: single, triple, multi), `origin` (CFrame at the stage centre looking at the viewer; default 14 studs in front of the camera), `distance`, `speed`, `camera` (true), `ui` (true), `skippable` (true), `autoContinue` (true), `hold` (2.5 s), `parent`, `guiParent`, `sounds` (cue to asset id), `onReveal(index, entry)`, `next` (auto mode).

Skipping (tap, click, Enter, gamepad A) jumps to the result: every pet at its final scale, result labels shown, running effects and the camera move stopped. A second press dismisses. `cancel()` removes everything at once. The result has no buttons: it continues after `hold` or on a press.

## Beats and timing

| # | Beat | What happens |
|---|---|---|
| 1 | enter | the egg drops in with a stretch and squashes on landing (`egg.land`, `EggShakeDust`, `Landing` shake) |
| 2 | settle | |
| 3 | anticipation | a small sway begins |
| 4 | wobble | damped shakes, each stronger and faster, each with `egg.wobble` and `EggShakeDust`; 3 shakes for Common up to 9 for Secret |
| 5 | energy | `EggEnergy`, a light, the egg swells, `PetReveal` camera push, `egg.energy` |
| 6 | crack | `EggCrack` and `EggFlash`, the egg stretches and collapses, `egg.crack` |
| 7 | transition | bloom (white, or the rarity glow from Epic); hit-stop of 60, 80, 100 ms for Epic, Legendary, Mythic and Secret |
| 8 | appear | the pet springs from zero with a spin, `HatchBurst`, `egg.reveal`, `rarity.<name>`, Pets `HappyReaction` |
| 9 | rarity | from the Rewards profile: `RarityAura`, `RarityBurst` / `RarityBeam`, the profile's shake, Fireworks and Confetti for Legendary and above |
| 10 | result | name, rarity label and NEW tag under each pet |
| 11 | finish | pets shrink away, everything is destroyed, the camera is restored |

Time to the result for one egg: Common 2.2 s, Uncommon 2.7, Rare 3.3, Epic 4.0, Legendary 4.7, Mythic 5.5, Secret 5.7, divided by `speed`. Triple runs at 85 %, multi at 70 % with at most four shakes per egg; reveals are 0.12 to 0.2 s apart with the rarest last. Auto mode is about one second per batch.

Layout: a row for one or two eggs, a shallow arc for a single row of three or more, otherwise a grid whose last row is centred. It is computed from the count and the viewport aspect ratio and never overlaps.

Reduced motion: no camera, no spin, a wobble at 30 % and a shorter timeline. Reduced flashing: no bloom. Quality `Low`: no lights; a multi hatch also drops `EggEnergy`, per-shake dust and auras and is shorter.

## Performance

One clock job poses every egg and pet and skips rigs whose values did not change. Lights are created only for up to three eggs and only when the quality profile allows lights. Particle counts come from the VFX module's quality scaling. Everything lives in one Folder and one ScreenGui, both destroyed at the end.

## Not verified in Studio

`HatchLogic` is covered by `tests/visuals_eggs.spec.luau` (17 tests). `Eggs.luau` creates Instances and was NOT run in Studio; all of it is `NEEDS MANUAL REVIEW`, in particular: stage placement and scale, the demo egg's mesh squash (the spots do not follow the squash for the fraction of a second it lasts; `SpecialMesh.Offset` under `ScaleTo` is unchecked), custom egg and pet models with unusual pivots, BillboardGui sizing, the hand-over between the stage job and the Pets reaction, and the camera cinematic options. It passes StyLua, Selene and `luau-lsp` with Roblox types.
