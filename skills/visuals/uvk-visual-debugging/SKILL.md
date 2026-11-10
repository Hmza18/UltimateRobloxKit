---
name: uvk-visual-debugging
description: Debugging UltimateVisualsKit visuals - the Visuals.Debug stats overlay, the effect profiler, Debug.dump of every preset id, Visuals:Stats and per-module stats, and a symptom table for effects that do not appear, play twice, never stop, leave the camera or UI stuck, or leak instances and clock jobs. Use when an effect or animation is missing, wrong, doubled, stuck or leaking, or to inspect what UVK is running right now.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [visual debugging, effect not showing, effect is not showing, effect not playing, animation stuck, debug overlay, visuals stats, effect leak, camera stuck after, ui stuck scaled, preset not found, debug vfx]
  depends: [uvk-visuals-kit]
---

# UVK visual debugging

## When to use

- An effect, animation, reveal or camera move does not appear, appears twice, never ends, or leaves something changed.
- You need live numbers: tracks, clock jobs, effects, particles, rejections.

When not to use: Luau errors and stack traces in general (`luau-debugging`); frame-time work once the cause is known to be load (`uvk-visual-performance`).

## Inputs

- The exact call (module, preset id, target, params) and what was expected.
- The settings in force: quality level, reduced motion, reduced flashing, intensity.

## Workflow

1. **Turn on the overlay.** It shows the level, fps and 99th percentile frame time, engine tracks, clock jobs, live effects, estimated particles, lights, spawned and evicted counts, and skips by reason. It connects to RenderStepped only while open.

   ```lua
   local close = Visuals.Debug.overlay()     -- under PlayerGui; pass a parent to place it elsewhere
   -- close() removes it
   ```

2. **Read the numbers in code.**

   ```lua
   print(Visuals:Stats())          -- level, tracks, jobs, effects, particles, lights, spawned, evicted, rejected, frameTime, running
   print(Visuals:Settings())       -- level, adaptive, reducedMotion, reducedFlashing, intensity
   print(Visuals.VFX.stats())      -- live, effects, particles, lights, rejected, highlights, holders, presets
   print(Visuals.UI.stats())       -- chains, popups, flyers
   print(Visuals.Camera.stats(), Visuals.Camera.isActive())
   ```

3. **Check the id exists.** `Visuals.Debug.dump()` prints every preset id by kind. `Visuals.Presets.search("coin")` and `Visuals.Presets.describe("vfx", "CoinBurst")` answer "what is it called" and "what params does it take". Offline, grep `catalog/visuals.json`.

4. **Match the symptom.**

   | Symptom | Likely cause | Check or fix |
   |---|---|---|
   | `Visuals:Play` returns nil | skipped by budget, distance, offscreen or throttle | `Visuals:Stats().rejected`; move closer; raise `priority` for rare effects |
   | Nothing on Low quality | trails, lights, highlights, post-processing and optional layers are off by design | test at High; do not rely on those layers to read |
   | A loop never starts | reduced motion is on (loops do not start) | `Visuals:Settings().reducedMotion` |
   | Effect plays twice | fired from two scripts, or both server broadcast and local input | fire from one place; keep one `Feedback` recipe |
   | Looping effect never ends | handle dropped | store it, or tag with `owner` and call `Visuals:StopAll(owner)` |
   | Trail missing | trails need a part target, and are off on Low | attach to a BasePart |
   | Aura missing in a pet preview | ViewportFrames do not render particles | expected |
   | No fade on a panel | not a CanvasGroup | wrap in a CanvasGroup |
   | UI stays scaled or offset | you changed scale or rotation yourself after first use | `Visuals.UI.rest(gui)`; or `Visuals.UI.stop(gui, true)` |
   | Preset does nothing in a list | offsets inside a UIListLayout | use scale presets |
   | Camera stuck or wrong FOV | a takeover handle never stopped, or a camera script fights it | `Visuals.Camera.restore()`; find the unstopped handle |
   | No sound | cue not registered (none are bundled) | `Visuals.Audio.isRegistered(cue)`; register your sound id |
   | Feedback step missing | context field absent, so the step was dropped | inspect `Visuals.Feedback:Fire(...).dropped` |
   | Object animation ignored | unanchored part | anchor it (one warning is printed) |
   | Unknown preset error | wrong id or wrong kind | `Visuals.Debug.dump()` |
   | Pack icon not found | pack not registered or `bridge()` not called | see `uvk-icon-pack` |

5. **Test for leaks.** Trigger the moment, wait for it to end, stop everything, and compare:

   ```lua
   Visuals:StopAll()
   task.wait(1)
   local stats = Visuals:Stats()
   assert(stats.effects == 0 and stats.jobs == 0, "something is still running")
   ```

   Also look for leftover instances named `Uvk*` (`UvkOverlay` and the pooled holders under `Workspace.UvkEffects` are expected to persist; stray `UvkShine`, `UvkGlow`, `UvkRipple`, `UvkTint` are not). Destroy a target mid-animation and confirm no error and no job remains.

6. **Isolate.** Play the single preset on a bare part or frame in an empty place with default settings. If it works there, the problem is the call site (timing, parent, target), not the preset.

7. **Measure a suspect effect** with `Visuals.Debug.profile(seconds, start, done)`; see `uvk-visual-performance`.

## Outputs

- The cause, stated with the number or setting that shows it, and a fix at the call site (or a preset override when the preset is at fault).

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_`. A fix is confirmed when the overlay shows the effect spawning, `rejected` no longer grows for it, and stats return to zero afterwards. Visual confirmation is `NEEDS MANUAL REVIEW` in Studio.

## Pitfalls

- **Treating a skip as a bug** and retrying until the effect plays. That defeats the budget.
- **Debugging with reduced motion on** (the game passed `reducedMotion = true` to `Visuals:Configure`) and concluding loops are broken.
- **Leaving the overlay in a release build.** Gate it behind a developer check.
- **Destroying UVK's instances by hand.** Stop the handle; the module cleans up and keeps its pools consistent.
- **Editing the library copy** in the project to "fix" a preset. Override it through the registry so upgrades keep working.

## Limitations

- The overlay and profiler create Instances and connect to RenderStepped; `DebugLogic` (sampling, percentiles, verdicts) is covered by a Lune spec, the Roblox side was not run in Studio.
- Particle numbers are estimates from preset data, not engine counters. Use the MicroProfiler for render cost.
- The symptom table reflects how the modules are written; several rows have not been observed in Studio.
