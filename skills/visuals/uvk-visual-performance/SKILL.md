---
name: uvk-visual-performance
description: Performance for UltimateVisualsKit visuals - the four quality levels (Low, Medium, High, Ultra) and their particle, effect, light and distance budgets, adaptive quality, preset cost labels, throttling and eviction, pooling, reduced motion and intensity settings, and measuring an effect's frame cost with the Visuals.Debug profiler. Use when particles or effects cause lag, when choosing budgets for phones, when a new preset must fit the particle budget, or when effects are being skipped and you need to know why.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [particle budget, particle lag, effects lag, vfx performance, too many particles, particle optimization, quality level, quality settings, effect budget, effects skipped, visual performance, low end phones]
  depends: [uvk-visuals-kit, uvk-visual-debugging]
---

# UVK visual performance

## When to use

- Effects, UI animation or pets cost frame time, especially on phones.
- Authoring or overriding a preset that must stay inside the budgets.
- Effects are not appearing and the cause may be a budget or throttle.

When not to use: general game performance, streaming, meshes and server load (`roblox-performance`); static UI instance counts and redraw cost (`roblox-ui-performance`).

## Inputs

- The lowest device the game targets and the frame budget (16.7 ms at 60 fps).
- A reproducible heavy moment (a 10-egg hatch, a crowded fight, 15 taps a second).

## Workflow

1. **Measure before changing anything.** Open the overlay and reproduce the moment (details in `uvk-visual-debugging`):

   ```lua
   local close = Visuals.Debug.overlay()
   print(Visuals:Stats())   -- level, tracks, jobs, effects, particles, lights, spawned, evicted, rejected, frameTime
   ```

2. **Know the budgets.** Every effect goes through one manager that applies them.

   | Level | Live particles | Effects | Lights | Max distance | Particle scale | Off at this level |
   |---|---|---|---|---|---|---|
   | Low | 250 | 10 | 0 | 90 studs | 0.3 | trails, lights, highlights, post-processing, UI shine, optional layers |
   | Medium | 700 | 24 | 2 | 160 | 0.6 | post-processing |
   | High | 1600 | 48 | 6 | 260 | 1 | - |
   | Ultra | 3200 | 80 | 12 | 400 | 1.35 | - |

   Also per level: pet idle updates (Low 20 Hz, Medium 30 Hz, High and Ultra every frame), floating popups alive at once (8, 16, 28, 40) and camera shake scale (0.6, 0.85, 1, 1). The live numbers are in `catalog/visuals.json` under `quality`.

3. **Let the kit choose, or set it.** The level is picked from the device and, with `adaptive` on (default), stepped down under load and back up.

   ```lua
   Visuals:Configure({ quality = "Medium", adaptive = true })
   Visuals.Changed:Connect(function() print(Visuals:Settings().level) end)
   ```

   Offer the player a setting: quality, reduced motion, reduced flashing and an intensity slider (`intensity` 0 to 1.5 scales shake, punches and particle counts).

4. **Read why effects are skipped.** `Visuals:Stats().rejected` counts skips by reason (budget, distance, offscreen, throttle). `evicted` counts older low-priority effects removed to make room. A nil from `Visuals:Play` is this system working.

5. **Fix the cause, in this order.**
   1. Fewer starts: throttle in the feedback recipe (`throttle = { max, window }`), coalesce amounts, use `when = { every = N }`.
   2. Cheaper presets: check the cost label in `catalog/visuals.json`; replace a `high` preset used frequently with a `low` one, or lower `intensity` and `scale` in params.
   3. Priority: give rare, important effects `priority = 10` or more so they evict filler instead of being refused.
   4. Scope: attach ambient effects to the character with the default `size`; stop loops with their owner (`Visuals:StopAll(owner)`).
   5. Calmer pack: `Visuals.Feedback.use("Minimal")` on low-end devices.

6. **Cost a new preset before registering it.**

   ```lua
   local cost = Visuals.VFX.EffectLogic.cost(preset.data)   -- estimated live particles and lights
   ```

   Targets the built-ins meet: one-shots resolve to at most 62 particles on Low and under 400 on High; no emitter rate above 100 per second; rapid-input presets carry a `minInterval`; layers that are decoration are marked `optional` so Low drops them.

7. **Profile the change.** `Visuals.Debug.profile` measures frame time before and with the effect and gives a verdict (`ok`, `noticeable`, `expensive`):

   ```lua
   Visuals.Debug.profile(2, function()
   	return Visuals:Attach("Rain", rootPart)
   end, function(result)
   	print(result.verdict, result.averageMs, result.p99Ms)
   end)
   ```

8. **Report numbers**: before and after, the device or emulator profile, and what still needs a real phone.

## Outputs

- A quality and accessibility settings hook, throttled recipes, cheaper or re-prioritised presets, and a before and after measurement.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_core` and `visuals_vfx` (budgets, eviction, throttle, distance scaling, every preset inside its limits). After a heavy moment `Visuals:Stats()` must return to zero live effects and zero jobs. Frame time on a real phone is `NEEDS MANUAL REVIEW`.

## Pitfalls

- **Raising budgets to make effects appear.** The skip is the protection; lower the demand instead.
- **Optimising without a measurement.** The overlay and profiler take a minute.
- **Per-frame emitter writes** in custom code. Presets never write emitter properties each frame; neither should overrides.
- **Many ViewportFrames** (pet grids) cost more than particles. Page them.
- **`Model:ScaleTo` loops** on many large models. Prefer position and rotation loops.
- **Testing only on desktop.** The Low profile behaves differently by design: trails, lights and highlights are off.

## Limitations

- Budgets count estimated live particles from preset data, not what the engine renders; fill rate from large overlapping particles is not modelled.
- The profiler compares average and 99th percentile frame time over a short window in a live game; it is an indicator, not a benchmark.
- No part of this was measured on a device. The budget numbers are design choices, covered by specs for consistency, not proven frame-time guarantees.
