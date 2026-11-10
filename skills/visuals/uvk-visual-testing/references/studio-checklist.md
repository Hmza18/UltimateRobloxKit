# Manual Studio checklist for UVK visuals

None of this can be proven outside Roblox Studio. Work through the sections that apply, in a local test place, and record each line as done, failed or not run. Open the stats overlay first:

```lua
local close = Visuals.Debug.overlay()
```

Test matrix: Studio device emulator at a small phone (portrait and landscape), a tablet and desktop; mouse, touch and gamepad-only; quality Low and High; `reducedMotion` and `reducedFlashing` each on (`Visuals:Configure({ reducedMotion = true })`).

## Every effect and animation

- [ ] It appears where expected, at the expected size, on Low and on High.
- [ ] It ends by itself or when stopped; stopping twice raises nothing.
- [ ] Destroying the target mid-effect raises no error.
- [ ] After `Visuals:StopAll()` and a second of waiting, `Visuals:Stats()` shows zero effects and zero jobs.
- [ ] No stray `Uvk*` instances remain (pools under `Workspace.UvkEffects` and the `UvkOverlay` ScreenGui are expected).
- [ ] With reduced motion: no loops, no shake, no travel. With reduced flashing: no full-screen flash.

## World VFX

- [ ] The preset reads with Roblox's built-in textures (no uploaded ids configured).
- [ ] Rings, beams and emit volumes face the right way on a rotated target.
- [ ] Looping effects fade on `stop()` and vanish on `stop(true)`.
- [ ] Effects beyond the profile's distance do not play; effects behind the camera are skipped.

## UI animation

- [ ] Bound buttons respond on the input frame with mouse, touch and gamepad; touch release returns to rest.
- [ ] `show` during a `hide` leaves the object visible.
- [ ] Popups and fly-to-counter land in the right place at several resolutions and with the top-bar inset.
- [ ] Counters end on the exact target value.
- [ ] Animated components (PremiumButton, TabBar, Modal, XPBar and the rest) lay out and fit text at phone size.

## Camera

- [ ] After a shake, move or cinematic ends, is cancelled, or the character respawns: CameraType, CFrame and FieldOfView are back.
- [ ] Works with the game's own camera script enabled.

## Pets, eggs and rewards

- [ ] Pet idle and reactions look right on the game's real pet models (check pivots).
- [ ] Followers keep formation, stay on the ground on slopes and catch up after a teleport.
- [ ] Selection screen: layout on every device class, keyboard and gamepad navigation, the character does not move while it is open.
- [ ] Hatch: stage placement, skip at every beat, cancel mid-hatch, 1, 3 and 10 eggs, each rarity.
- [ ] Reveal: each rarity, a batch, skip and dismiss, two reveals in quick succession.
- [ ] The HUD is hidden or dimmed during a hatch or reveal and restored afterwards.

## Performance

- [ ] 15 taps a second for 10 s: popups stay under the cap; frame time stays in budget on the phone profile (write the number down).
- [ ] The heaviest moment in the game (largest hatch, busiest fight) with the overlay open: note live particles, rejected and evicted counts.
- [ ] A real phone, if one is available. If not, say so.

## Sound

- [ ] Registered cues play once per event, at a sensible volume, and stop with their effect.
- [ ] Unregistered cues stay silent with no warnings.
