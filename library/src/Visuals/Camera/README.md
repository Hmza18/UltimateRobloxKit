# Visuals / Camera

Camera shake, field-of-view moves, focus, orbit, pan and cinematics on `workspace.CurrentCamera`. The camera is never left overridden: every move restores what it changed.

| File | What |
|---|---|
| `CameraLogic.luau` | Pure maths (Lune-tested): trauma shake, framing, the priority stack, cinematic recipes, the registry |
| `Camera.luau` | Applies it to the camera |

## API

| Function | Does |
|---|---|
| `Camera.shake(presetOrDef, options?)` | Additive shake. Options: `intensity`, `duration`, `amplitude`, `rotation`, `frequency`, `seed`, `position` + `radius` (fade by distance) |
| `Camera.fov(degrees, options?)` | Eases the field of view and holds it until stopped. FOV only |
| `Camera.zoom(factor, options?)` | Magnifies through the field of view. `mode = "distance"` dollies instead (takeover) |
| `Camera.punchFov(amount, options?)` | Quick FOV kick that springs back. FOV only. Skipped under reduced motion |
| `Camera.focus(target, options?)` | Holds the camera at `distance`, `angle`, `elevation`, `height` from a target; follows a moving Instance |
| `Camera.orbit(target, options?)` | Circles a target at `speed` degrees per second |
| `Camera.pan(fromCFrame, toCFrame, options?)` | Travels between two CFrames over `travel` seconds, then holds |
| `Camera.cinematic(name, target, options?)` | Plays a recipe; `onMarker(name)` fires at its named beats |
| `Camera.restore(options?)` | Force-releases everything. `{ shakes = false }` keeps shakes |
| `Camera.isActive()`, `Camera.stats()` | State for tools |
| `Camera.registry` | `Core/Registry`, kind `camera` |

Move options: `priority`, `blendIn`, `blendOut`, `duration`, `easing`, `fov`, `onDone(completed)`.

Every function returns a handle:

| Method | Does |
|---|---|
| `stop(blend?)` | Blends back and restores. `stop(false)` cuts back at once. For a shake, fades it out over 0.15 s |
| `cancel()` | Removes it immediately and restores |
| `finish()` | Ends a timed move as if its time had run out |
| `isActive()` | True while it is alive |

The contract lists `stop(restore?)`. A camera move always restores, so the argument chooses between blending back and cutting back.

## Presets

| Category | Ids |
|---|---|
| shake | `SoftImpact`, `Impact`, `HeavyImpact`, `Rumble` (sustained), `Tap`, `Hatch` (builds up), `Landing` (vertical), `Explosion` |
| cinematic | `PetReveal` (push-in, slight orbit, FOV ease; marker `reveal`), `RewardReveal` (dolly and FOV punch; marker `reveal`), `AreaUnlock` (rise and sweep, then return; marker `arrive`), `Teleport` (FOV stretch, snap, settle; marker `jump`; FOV only) |
| move | `Focus`, `Orbit`, `Pan`, `Zoom`, `Fov`, `PunchFov` (metadata only) |

## Example

```lua
local Camera = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Camera.Camera)

Camera.shake("Impact")
local rumble = Camera.shake("Rumble", { duration = 6 })
rumble.stop()

Camera.cinematic("PetReveal", petModel, {
	onMarker = function(name)
		if name == "reveal" then
			Visuals:Play("PetSpawn", petModel)
		end
	end,
	onDone = function(completed) end,
})
```

## How it works

- **Shake** uses trauma: amplitude is trauma squared, so it eases out. Noise is three summed sines with a phase per axis, hashed from a seed. It is smooth and repeatable, and uses no `Random`. Several shakes add up and the sum is clamped to 2.5 studs and 8 degrees per axis.
- **Shakes are additive.** The offset is written after the game's camera update each frame and removed before the next one. It is removed only if nothing else wrote the camera in between.
- **The stack** folds live moves over the game's camera pose, lowest priority first. The highest priority wins. An equal priority replaces without a jump: the old move stays underneath until the new one covers it. When the top move ends, the camera blends to the next move or back to the game.
- **Takeover moves** save `CameraType`, `CameraSubject`, `CFrame` and `FieldOfView`, and set `CameraType` to `Scriptable` only while active. They restore on stop, finish, cancel, character respawn and when the local player leaves.
- **FOV-only moves** never change `CameraType`.
- **Settings.** Shake is scaled by `Host.juice("shake")`. Under reduced motion there is no shake and no FOV punch, blends shorten to 0.12 s, orbits hold still, pans cut and cinematics hold their settled framing.

`Camera.luau` uses `RunService:BindToRenderStep`, not `Host.clock`. This is the one permitted exception in the kit: the offset must run after the camera scripts and be removed before them, which only render-step priorities can order. Two steps are bound (`Camera - 1` to remove, `Camera + 1` to apply), only while a shake or move is active.

## Performance

- Nothing is bound while idle.
- A shake costs 18 sine calls per frame. A move costs one pose and one blend.

## Limits

- While a takeover move blends out, it blends to the camera pose saved when the takeover began. If the character moved far meanwhile, the game camera snaps to its own position when control returns.
- FOV moves restore the FOV saved when the first move began. A game script that changes FOV during a move is overwritten until the move ends.
- A custom camera script that sets `CameraType` every frame fights takeover moves.

## Not verified in Studio

`CameraLogic` is covered by `tests/visuals_camera.spec.luau`. `Camera.luau` was NOT run in Studio: render-step ordering, restoration on respawn, behaviour with custom camera scripts and how the presets feel are `NEEDS MANUAL REVIEW`.
