# VFX

Cosmetic particle effects with quality tiers. `VFXLogic` is pure: built-in presets (`hatch`, `levelUp`, `coinPickup`, `rareAura`, `purchase`) are plain data, and `resolve(name, quality)` scales them. `VFXClient` builds ParticleEmitters, plays one-shot bursts, attaches looping auras and keeps live emitters under a per-tier budget.

| Quality | Particles | Optional layers | Emitter budget | Picked when |
|---|---|---|---|---|
| `low` | 35% | dropped | 12 | saved graphics level 1-3, touch device, or under 40 fps |
| `medium` | 70% | kept | 30 | default; touch device at a steady 58+ fps |
| `high` | 100% | kept | 60 | graphics level 8+, or a non-touch device at 55+ fps |

```luau
local vfx = VFXClient.new() -- measures frame rate for 5 s, then settles the tier
vfx:play("hatch", egg:GetPivot().Position)
local stop = vfx:attach("rareAura", pet.PrimaryPart)
vfx.setQuality("low") -- from a settings menu
```

`VFXLogic.register(name, preset)` adds game presets (validated: 1-3 colours and sizes, `{ min, max }` lifetime and speed, a `burst` or a `rate`). `chooseQuality(device)`, `particleCount(preset)` and `names()` help menus and tests.

Effects are client-only and never decide gameplay.
