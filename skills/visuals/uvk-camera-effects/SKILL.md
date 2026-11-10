---
name: uvk-camera-effects
description: Camera effects with UltimateVisualsKit's Visuals.Camera - additive trauma-based shake presets (Tap, SoftImpact, Impact, HeavyImpact, Landing, Explosion, Hatch, Rumble), FOV moves and punches, zoom, focus, orbit, pan and cinematic recipes (PetReveal, RewardReveal, AreaUnlock, Teleport) on a priority stack that always restores CameraType, CFrame and FieldOfView. Use when adding camera shake, screen shake, impact kicks, zoom or FOV effects, a reveal or area-unlock cinematic, or when a camera effect leaves the camera stuck.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [camera shake, screen shake, camera effect, fov punch, fov effect, camera zoom, camera focus, camera orbit, cinematic camera, reveal cinematic, camera stuck, impact shake]
  depends: [uvk-visuals-kit]
---

# UVK camera effects

## When to use

- Shake on hits, landings, explosions and taps; a FOV kick on a dash or reward.
- Temporary takeovers: focus on a pet, orbit a prize, pan to a new area, a named cinematic.

When not to use: the player's camera controller, shift lock, first person or input (`roblox-camera-input`); camera work inside a hatch or reveal (those modules call the camera themselves).

## Inputs

- The trigger and its strength, and whether it is frequent (use `Tap`) or rare (`Impact` and above).
- For takeovers: the target (Vector3, CFrame or Instance) and when control must return.

## Workflow

1. **Shake by preset.** Shakes are additive offsets applied after the game's camera update, so they work with any camera controller.

   ```lua
   local Camera = Visuals.Camera
   Camera.shake("SoftImpact")
   Camera.shake("Impact", { intensity = 0.7, position = hitPosition, radius = 60 })  -- fades with distance
   local rumble = Camera.shake("Rumble", { duration = 6 })
   rumble.stop()                               -- fades out over 0.15 s
   ```

   | Preset | Use |
   |---|---|
   | `Tap` | frequent small feedback |
   | `SoftImpact`, `Impact`, `HeavyImpact` | hits by weight |
   | `Landing` | vertical, for falls |
   | `Explosion` | big, rare |
   | `Hatch` | builds up |
   | `Rumble` | sustained |

   Options: `intensity`, `duration`, `amplitude`, `rotation`, `frequency`, `seed`, `position` + `radius`.

2. **Field of view.** These never change `CameraType`.

   ```lua
   Camera.punchFov(6)                          -- quick kick that springs back
   local speed = Camera.fov(80, { duration = 0.3 })   -- eases and holds until stopped
   speed.stop()
   Camera.zoom(1.5)                            -- magnify through FOV; mode = "distance" dollies instead
   ```

3. **Takeover moves** save the camera state, set `Scriptable` only while active and restore on stop, finish, cancel, respawn and when the player leaves.

   ```lua
   local focus = Camera.focus(petModel, { distance = 10, elevation = 15 })
   local orbit = Camera.orbit(prize, { speed = 20 })
   Camera.pan(fromCFrame, toCFrame, { travel = 1.2 })
   focus.stop()                                -- blends back; stop(false) cuts back
   ```

   Move options: `priority`, `blendIn`, `blendOut`, `duration`, `easing`, `fov`, `onDone(completed)`.

4. **Cinematics** are recipes with named beats.

   ```lua
   Camera.cinematic("PetReveal", petModel, {
   	onMarker = function(name)
   		if name == "reveal" then
   			Visuals:Play("PetSpawn", petModel)
   		end
   	end,
   	onDone = function(completed) end,
   })
   ```

   `PetReveal` and `RewardReveal` fire `reveal`; `AreaUnlock` fires `arrive`; `Teleport` fires `jump` and is FOV only.

5. **Handles.** `stop(blend?)`, `cancel()` (immediate), `finish()`, `isActive()`. `Camera.restore()` force-releases everything; `Camera.restore({ shakes = false })` keeps shakes.

6. **Throttle frequent shakes** in the recipe instead of in the handler: in `Visuals.Feedback` use `throttle = { max = 4, window = 1 }` or `when = { every = 5 }`.

7. **Accessibility is automatic.** Under reduced motion there is no shake and no FOV punch, blends shorten, orbits hold still, pans cut and cinematics hold their settled framing. Shake is also scaled by the quality profile and `intensity`.

## Outputs

- Shake and move calls with handles stored where a takeover must end on a game event.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_camera` (trauma maths, the priority stack, cinematic recipes, restoration accounting). In Studio (`NEEDS MANUAL REVIEW`): after every cinematic ends, is cancelled, or the character respawns, check that `CameraType`, `CFrame` and `FieldOfView` are back; test with the game's own camera script; test with reduced motion.

## Pitfalls

- **Shake on every tap.** It becomes noise and can cause discomfort. Use `Tap`, throttled, or none.
- **Big shake for small events.** Keep `HeavyImpact` and `Explosion` for a few moments per session.
- **A custom camera script that sets `CameraType` every frame** fights takeover moves. Pause it during the move.
- **Writing `Camera.CFrame` yourself during a move.** The stack owns the camera until the handle stops.
- **Setting FOV during an FOV move.** The move restores the FOV saved when it began.
- **Forgetting the handle of a looping `Rumble` or `orbit`.** Store it and stop it.

## Limitations

- `CameraLogic` is covered by a Lune spec. `Camera.luau` was not run in Studio: render-step ordering, restoration on respawn and behaviour with custom camera scripts are unverified.
- `Camera.luau` binds two render steps while a shake or move is active. This is the kit's one exception to the "all timing through `Host.clock`" rule.
- While a takeover blends out it returns to the pose saved when it began; if the character moved far, the game camera snaps to its own position when control returns.
