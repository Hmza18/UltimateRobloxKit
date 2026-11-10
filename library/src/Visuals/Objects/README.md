# Visuals / Objects

Preset animations for world objects and GUI objects: floating pickups, spinning coins, pop-ins, collect arcs, squash and stretch.

| File | What |
|---|---|
| `ObjectsLogic.luau` | Pure samplers (Lune-tested): for a time `t`, offsets relative to rest; the registry |
| `Objects.luau` | Applies them to a Model, BasePart, Attachment or GuiObject |

## API

| Function | Does |
|---|---|
| `Objects.animate(target, presetId, options?) -> Handle` | Plays a preset. A new animation on a target replaces the running one |
| `Objects.stop(target, restore?)` | Stops it. `restore = true` returns to rest, including an object an earlier one-shot left hidden. Default: loops restore, one-shots stay |
| `Objects.isAnimating(target)`, `Objects.count()`, `Objects.stopAll(restore?)` | State and teardown |
| `Objects.registry` | `Core/Registry`, kind `object` |

Handle: `stop(restore?)`, `cancel()`, `finish()` (one-shots jump to the end state, loops return to rest), `isActive()`.

| Option | Meaning | Default |
|---|---|---|
| `amplitude` | Studs, pixels, degrees or scale amount, depending on the preset | per preset |
| `speed` | Loops: cycles per second | per preset |
| `duration` | One-shots: seconds | per preset |
| `axis` | `"x"`, `"y"` or `"z"` | per preset |
| `phase` | Loops: 0..1 of a cycle | spread automatically |
| `intensity` | Multiplier on the amplitude | 1 |
| `target` | `Collect`, `Teleport`: end point relative to rest (Vector3 or array) | `Collect`: 3 up |
| `onDone(completed)` | Called when it ends | none |
| `restore` | One-shots: return to rest when finished | false |
| `allowUnanchored` | Animate an unanchored part anyway | false |
| `fresh` | Ignore the rest state remembered from an earlier hide | false |

## Presets

| Id | Kind | Motion | Default |
|---|---|---|---|
| `Float` | loop | Vertical bob with a lagging turn | 0.5 studs, 0.5 Hz |
| `Hover` | loop | Tight hover, figure-of-eight drift, breathing squash | 0.25 studs, 0.9 Hz |
| `Bounce` | loop | Hop with a landing squash and an air stretch | 1.2 studs, 1.2 Hz |
| `Spin` | loop | Constant rotation on one axis | 0.25 turns per second, y |
| `Pulse` | loop | Uniform scale pulse | 0.08, 0.8 Hz |
| `Sway` | loop | Rocking rotation | 8 degrees, 0.4 Hz, z |
| `Orbit` | loop | Circles the rest position | radius 2, 0.3 Hz |
| `ScaleIn` | one-shot | Grows from nothing with an overshoot | 0.4 s |
| `ScaleOut` | one-shot | Swells, shrinks to nothing, hides | 0.3 s |
| `Reveal` | one-shot | Rises, fades in, half turn, pop | 0.7 s |
| `Dissolve` | one-shot | Drifts up, swells, fades out | 0.6 s |
| `Appear` | one-shot | Fade in with a small drop | 0.35 s |
| `Disappear` | one-shot | Fade out with a slight shrink | 0.25 s |
| `Collect` | one-shot | Pop, pull back, arc to the target, shrink away | 0.55 s |
| `Teleport` | one-shot | Squash, stretch up, vanish, reappear at the target, overshoot | 0.7 s |
| `Shake` | one-shot | Decaying rattle | 0.4 s |
| `SquashStretch` | one-shot | Anticipation squash, stretch with a hop, springy settle | 0.6 s |
| `Interact` | one-shot | Quick squash and pop | 0.28 s |

Squash and stretch keeps volume: scaling y by `s` scales x and z by `1 / sqrt(s)`.

## Example

```lua
local Objects = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Objects.Objects)

local float = Objects.animate(coin, "Float")
Objects.animate(coin, "Collect", {
	target = Vector3.new(0, 4, -6),
	onDone = function()
		coin:Destroy()
	end,
})

Objects.animate(chest, "SquashStretch")
Objects.animate(shopButton, "Pulse", { amplitude = 0.05 })
```

## Targets

| Target | Position and rotation | Scale | Transparency |
|---|---|---|---|
| Model | `PivotTo` from the stored rest pivot | `ScaleTo`, uniform: the vertical component of a squash | Stored `Transparency` of every descendant part and decal |
| BasePart | `CFrame` from the stored rest CFrame | `Size`, non-uniform | The part and its descendant parts and decals |
| Attachment | Local `CFrame` | not applied | not applied |
| GuiObject | `Position` in pixels (y is up), `Rotation` | The shared `UrkScale` UIScale, uniform | `GroupFade` (see `Runtime/Props`) |

- Every frame is composed from the rest state stored when the animation started. Nothing drifts, and restore is exact.
- A new animation on a target that is already animating first returns it to rest, then starts from there.
- After a one-shot that hides the object (`ScaleOut`, `Dissolve`, `Disappear`, `Collect`), its real size and transparency are remembered. The next animation on it starts from those, at the object's current position.

**Anchored parts only.** Animating an unanchored, simulated part by CFrame fights the physics solver every frame. Such targets are skipped with one warning. Pass `allowUnanchored = true` only when the part is not simulated.

## Performance

- One `Host.clock` job updates every live animation. It exists only while something is animating.
- Loops beyond the profile's `fadeDistance` are redrawn every second frame (every third on Low) and not at all beyond `maxDistance`. Time still advances, so they stay in step.
- Loops are paused while the target is outside the DataModel and end when it is destroyed.
- `Model:ScaleTo` is called only when the scale changes by more than 0.002. A scale loop on a large model is still costly: prefer `Float`, `Spin` or `Sway` for many models.
- Reduced motion: loops do not start, one-shots jump to their end state.

## Not verified in Studio

`ObjectsLogic` is covered by `tests/visuals_objects.spec.luau`. `Objects.luau` was NOT run in Studio: how each target type is written, transparency restoration, throttling and how the presets look are `NEEDS MANUAL REVIEW`.
