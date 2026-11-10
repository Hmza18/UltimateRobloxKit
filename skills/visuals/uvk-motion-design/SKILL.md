---
name: uvk-motion-design
description: Motion design with UltimateVisualsKit - the animation principles (anticipation, follow-through, secondary motion, squash and stretch, timing hierarchy), springs and easing curves, Visuals.Motion tweens and punches, Visuals.Sequence timelines with skip and cancel, and the Visuals.Objects presets for floating, spinning, bouncing and collecting world objects. Use when choosing timings or springs, sequencing several effects, animating a model or part, or when motion feels stiff, floaty or cheap.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [motion design, spring animation, easing curve, anticipation, squash and stretch, follow through, animation timing, sequence timeline, object animation, floating pickup, spinning coin, feels stiff]
  depends: [uvk-visuals-kit]
---

# UVK motion design

## When to use

- Deciding how long something takes, which spring it uses and what happens before and after it.
- Chaining effects, motion, sound and callbacks into one skippable timeline.
- Animating a Model, BasePart, Attachment or GuiObject with a ready preset.

When not to use: button states, panels and counters have presets in `uvk-ui-animation`; rigged character clips are `roblox-animation`; camera moves are `uvk-camera-effects`.

## Inputs

- What triggers the motion and how often (a tap 10 times a second gets no anticipation; a legendary reveal gets a second of it).
- The target type. Models and parts must be anchored to be animated by CFrame.

## Workflow

1. **Classify the moment** and take its timing from the hierarchy. Frequent and small is fast; rare and big is slow and layered.

   | Moment | Timing |
   |---|---|
   | Press down / release | 60-90 ms down, 180-260 ms spring back |
   | Hover | 100-140 ms |
   | Popup or panel in / out | 250-350 ms with overshoot / 140-200 ms |
   | Toast in / out | 250 ms / 180 ms |
   | Counter roll | 0.4-1.2 s, scaled by the change |
   | Reward reveal | 1.2 s (common) to about 3.5 s (top tiers) |

2. **Use a preset if one exists.** For world objects: `Float`, `Hover`, `Bounce`, `Spin`, `Pulse`, `Sway`, `Orbit` (loops) and `ScaleIn`, `ScaleOut`, `Reveal`, `Dissolve`, `Appear`, `Disappear`, `Collect`, `Teleport`, `Shake`, `SquashStretch`, `Interact` (one-shots).

   ```lua
   local Objects = Visuals.Objects
   local float = Objects.animate(coin, "Float")                 -- loop; float.stop() restores rest
   Objects.animate(chest, "SquashStretch")                       -- anticipation, stretch, springy settle
   Objects.animate(coin, "Collect", {
   	target = Vector3.new(0, 4, -6),                             -- end point relative to rest
   	onDone = function() coin:Destroy() end,
   })
   ```

   Options: `amplitude`, `speed` (loops), `duration` (one-shots), `axis`, `phase`, `intensity`, `target`, `onDone(completed)`, `restore`, `allowUnanchored`, `fresh`. `Objects.stop(target, restore?)` ends it.

3. **Otherwise animate through `Visuals.Motion`**, never TweenService loops or `task.wait` chains. The engine resolves conflicts by priority, never jumps when interrupted, drops destroyed targets and can restore.

   ```lua
   local Motion = Visuals.Motion
   Motion.tween(frame, { Position = UDim2.fromScale(0.5, 0.5) }, { duration = 0.3, easing = "backOut" })
   Motion.spring(button, { Scale = 1.08 }, "Bouncy")            -- Scale is the shared UrkScale UIScale
   Motion.punch(icon, "Scale", 0.2, "Elastic")                  -- kick and settle back
   Motion.stop(button, true)                                     -- cancel and restore
   ```

   Springs (`Core/Springs`): `Gentle`, `Soft`, `Snappy`, `Bouncy`, `Elastic`, `Overshoot`, `Heavy`, `Playful`, `Premium`, `Cinematic`. Curves (`Core/Curves`): the standard families plus `anticipate`, `anticipateOvershoot` and `swiftOut`. Virtual properties: `Scale`, `GroupFade`, `Pivot`, `PivotCFrame`, `ModelScale`.

4. **Sequence anything with more than two beats.** A sequence can be skipped (state ends correct), cancelled and paused, and its `Cleanup` functions always run once.

   ```lua
   local sequence = Visuals.Sequence()
   	:Call(function() Objects.animate(chest, "Shake") end)       -- anticipation
   	:Wait(0.4)
   	:Play("TreasureOpen", chest)                                 -- the moment
   	:Sound("success")
   	:Wait(0.15)
   	:Play("CoinBurst", chest)                                    -- follow-through
   	:Marker("opened")
   	:OnMarker(function(name) if name == "opened" then showLoot() end end)
   	:Start()
   -- sequence:Skip() jumps to the end state; sequence:Cancel() stops now
   ```

   Builder steps: `Play`, `Sound`, `Wait`, `At`, `Call`, `Animate`, `Marker`, `Parallel`, `Stagger`, `Cleanup`, `OnDone`, `OnMarker`, `Speed`; controls: `Start`, `Skip`, `Cancel`, `Pause`, `Resume`.

5. **Apply the principles on purpose.** Anticipation only before big moments. Springs instead of hard stops. One secondary element lagging 40-80 ms. Squash and stretch that keeps volume. The first visual change on the same frame as the input.

6. **Respect settings.** Reduced motion: loops do not start and one-shots jump to their end state. `Visuals:Configure({ intensity = 0.7 })` scales punches and shake for calm games; themes carry their own motion feel (`Visuals.Themes.token("motion.spring.press")`).

## Outputs

- Calls to object presets, `Motion` and `Sequence` with handles kept for cleanup.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_objects` and `visuals_sequence`. The specs prove timing, cancellation and restoration; the feel of a spring is `NEEDS MANUAL REVIEW` in Studio.

## Pitfalls

- **Unanchored parts.** Animating a simulated part by CFrame fights physics; such targets are skipped with one warning. Anchor them.
- **Offsets inside layouts.** UIListLayout and UIGridLayout own `Position`; use scale and rotation there.
- **Scale loops on large models.** `Model:ScaleTo` is costly; prefer `Float`, `Spin` or `Sway` for many models.
- **Anticipation on frequent actions.** It makes tapping feel laggy. Keep it for chests, eggs and level-ups.
- **`task.delay` for timing.** It cannot be cancelled with the effect. Use `Sequence`, `Motion.delay` or handle callbacks.
- **Everything animated at once.** Stagger by 50-80 ms so the eye has an order to follow.

## Limitations

- `ObjectsLogic`, `Engine`, `Springs`, `Curves` and `Sequence` are covered by Lune specs. `Objects.luau` and `Motion.luau` write Instances and were not run in Studio.
- Models scale uniformly, so squash and stretch on a Model is a damped vertical scale, not a true non-uniform squash.
- Timings above are design targets from the kit's research, not measurements of any game.
