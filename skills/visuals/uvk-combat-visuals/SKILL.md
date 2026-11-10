---
name: uvk-combat-visuals
description: Combat and ability visuals with UltimateVisualsKit - the Combat feedback pack (Hit, Critical, ElementHit, AbilityUsed, AbilityCharge, CooldownReady, Dash), combat VFX presets (HitConfirm, ImpactFlash, Shockwave, EnergyBurst, ElementBurst in eight elements, Aura, Transformation, DashTrail), impact camera shake, damage popups and hotbar cooldown feedback, layered for high visual impact with original effects. Use when adding hit effects, ability or skill effects, elemental attacks, auras, transformations, dash trails or anime-style impact to a fighting, RPG or anime game.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [combat visuals, hit effect, hit feedback, ability effect, skill effect, elemental effect, visual impact, impact effect, damage numbers, transformation effect, dash trail, anime effects, combat juice, attack effect]
  depends: [uvk-visuals-kit, uvk-gameplay-feedback]
---

# UVK combat visuals

Visuals never decide a hit. The server resolves damage (`roblox-physics-interactions`, `roblox-security-anti-exploit`); the client shows the result.

## When to use

- Hits, crits, abilities, charges, cooldowns, dashes, auras and transformations.
- A request for the impact level of a popular fighting or anime game. The answer is layering and timing with the kit's original presets, never copied effects, names or assets.

When not to use: hit detection and damage rules; weapon and character animation clips (`roblox-animation`); non-combat simulator feedback (`uvk-gameplay-feedback`).

## Inputs

- The server's combat events and payloads (hit position, amount, element, attacker character).
- How many hits per second the game can produce, and the lowest target device.

## Workflow

1. **Switch on the Combat pack** once at client start. It replaces `Hit`, `AbilityUsed` and `Dash` and adds `Critical`, `ElementHit`, `AbilityCharge` and `CooldownReady`.

   ```lua
   Visuals.Feedback.use("Combat")
   ```

2. **Fire events from server results.**

   ```lua
   HitRemote.OnClientEvent:Connect(function(hit)
   	local event = if hit.critical then "Critical" else "Hit"
   	Visuals.Feedback:Fire(event, { position = hit.position, amount = hit.damage })
   	if hit.element then
   		Visuals.Feedback:Fire("ElementHit", { position = hit.position, element = hit.element })
   	end
   end)

   Visuals.Feedback:Fire("AbilityUsed", { position = rootPart.Position })
   Visuals.Feedback:Fire("AbilityCharge", { character = character, duration = 1.2 })
   Visuals.Feedback:Fire("Dash", { character = character })
   Visuals.Feedback:Fire("CooldownReady", { gui = hotbarSlot.Instance, position = rootPart.Position })
   ```

   `Hit` in this pack adds a `Shockwave` when `amount` is 100 or more; change the threshold by redefining the event.

3. **Build impact in layers, in this order**, and stop adding when the hit reads:
   1. Contact: `HitConfirm` and `ImpactFlash` on the frame of the hit.
   2. Weight: a damage popup (`style = "damage"` or `"crit"`) and a shake matched to the hit (`Tap`, `SoftImpact`, `Impact`).
   3. Energy: `ElementBurst` with the element, or `EnergyBurst`.
   4. Space: `Shockwave` for heavy hits only.
   5. Aftermath: the target reacts (`Visuals.Objects.animate(target, "Shake")`).

4. **Signature moves** get a sequence with anticipation, the hit, and follow-through:

   ```lua
   local charge = Visuals:Attach("AbilityCharge", character, { owner = character, color = "#7C6BFF" })
   Visuals.Sequence()
   	:Wait(0.6)                                             -- anticipation: the charge builds
   	:Call(function() if charge then charge.stop() end end)
   	:Play("EnergyBurst", character)
   	:Call(function() Visuals.Camera.shake("HeavyImpact") end)
   	:Wait(0.08)
   	:Play("Shockwave", character)
   	:Play("ElementBurst", character, { element = "lightning", scale = 1.4 })
   	:Start()
   ```

5. **Persistent states.** `Visuals:Attach("Aura", character, { color = teamColor, owner = character })`, `Transformation` for a one-off power-up (high cost, rare), `DashTrail`, `SpeedTrail` and `MovementAura` for movement. Stop them with the state: `Visuals:StopAll(character)`.

6. **Elements.** `ElementBurst` takes `element`: fire, ice, lightning, water, earth, wind, light, dark. Each has its own motion (fire rises, ice brakes, dark implodes then bursts). Tint with `color` for a custom element instead of authoring a new preset.

7. **Cooldowns on the HUD.** `Game.HotbarSlot` shows the sweep and pulses when ready (`slot:startCooldown(seconds)`); see `uvk-simulator-screens`.

8. **Budget for fights.** Many players hitting at once is the worst case. Keep per-hit effects low cost, rely on the pack's throttles, pass `position` and `radius` to shakes so distant fights do not shake the camera, and read `uvk-visual-performance` before adding layers.

## Outputs

- A client combat-feedback script: the pack switch, one `Feedback:Fire` per server event, sequences for signature moves, attached auras stopped with their owner.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_feedback` and `visuals_vfx`. In Studio (`NEEDS MANUAL REVIEW`): a multi-client fight on a phone profile with the `Visuals.Debug` overlay open; watch live particles and rejected effects; confirm the enemy and its health bar stay readable through every effect; test reduced flashing and reduced motion.

## Pitfalls

- **Effects that hide the fight.** Nothing may cover the target, a prompt or a health bar for more than a moment. Prefer rings and sparks over opaque flashes.
- **Every hit is a heavy hit.** Without small hits, big ones have no contrast.
- **Client-side hit confirmation.** Showing `HitConfirm` before the server agrees teaches players that misses hit.
- **Shake from every player's hits.** Shake only for the local player's hits or nearby ones (`position`, `radius`).
- **Copying a known game's effect.** Ask what the effect communicates (speed, weight, element) and build that from presets.
- **Unstopped auras** after death or respawn. Tag with `owner` and stop by owner.

## Limitations

- The Combat pack and presets are covered by Lune specs for data validity and budgets only. Nothing here was run in Studio, and no claim is made that the result matches any particular game's visual quality.
- There are no mesh-based or flipbook-authored effects in the library; presets use particles, beams, rings, lights and flashes with built-in or owner-uploaded textures.
- Hit-stop (freezing the game for a few frames) is not provided outside the egg hatch.
