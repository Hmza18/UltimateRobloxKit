# Map plan template

Copy to `docs/map-plan.md` and fill in every section before blockout.

## Summary

- Map name:
- Genre and core loop in one sentence:
- Target devices (mobile share expected):
- Max players per server:
- Total footprint (studs, X by Z):
- Grid: base module ___ studs, building module ___ studs, storey height ___ studs

## Zones

| Zone | Purpose (what the player does) | Size (studs) | Unlock condition | Landmark | Biome/material set | Streaming mode |
|---|---|---|---|---|---|---|
| Spawn hub | Orient, first task | 200x200 | none | | | default |
| | | | | | | |

## Critical path

Ordered list from spawn to the first reward, then to the first zone unlock. Give walk time at 16 studs/s.

1. Spawn -> ___ (__ s)
2. ___ -> first reward (__ s)
3. ___ -> zone 2 gate (__ s)

## Sightlines and guidance

- From spawn the player sees: ___
- Each gate is visible from: ___
- Guidance tools used (light, colour, path wear, NPC, signage icon): ___

## Spawn areas

- Locations and facing:
- Spacing and count:
- Safe radius (no hazards/PvP within ___ studs):

## Navigation

- NPC agent sizes (radius, height):
- PathfindingModifier labels and costs:
- PathfindingLinks (jumps, ladders, teleports):

## Collision and bounds

- Map edge treatment (water, cliffs, fog, fences):
- Invisible walls (location and reason):
- Collision groups:

## Streaming plan

- StreamingTargetRadius / StreamingMinRadius:
- Atomic models:
- Persistent models (keep under ~5):
- Areas players teleport to (need RequestStreamAroundAsync):

## Budgets

- Parts per zone target:
- Unique meshes / textures per zone:
- Shadow-casting lights in any view:

## Storytelling beats

| Zone | What happened here | Staged props |
|---|---|---|
| | | |

## Scatter seeds

| Zone | Seed | Templates | Count | Date |
|---|---|---|---|---|
| | | | | |
