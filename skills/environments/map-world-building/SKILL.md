---
name: map-world-building
description: Plans and builds Roblox maps and worlds - zones, landmarks, sightlines, critical path, spawn areas, navigation and PathfindingModifiers, Terrain API and MaterialService materials, modular buildings and streets on a stud grid, interiors and exteriors, biomes, seeded prop scatter with raycast ground snapping, collision setup, StreamingEnabled-aware layout, mobile budgets and environmental storytelling. Use when designing a level or map, laying out a town, city, island or dungeon, generating terrain, scattering props or fixing navigation and collision in a world.
license: MIT
metadata:
  category: environments
  version: 1.0.0
  triggers: [map, level design, terrain, world building, biome, prop scatter, landmark, spawn area, streamingenabled, pathfindingmodifier, modular kit, invisible wall]
  depends: [roblox-performance, lighting-atmosphere, modular-buildings-props]
---

# Map and world building

## When to use

- Planning a new map or zone, from a one-page layout to a blockout.
- Terrain work: generating, painting, custom materials.
- Building towns, streets and interiors from modular pieces.
- Scattering props, fixing collision, navigation or streaming pop-in.

When not to use: making individual building or prop meshes (use `modular-buildings-props`), mood and lighting (use `lighting-atmosphere`), fully procedural or infinite worlds (use `roblox-procedural-generation`), deep frame-time profiling (use `roblox-performance`).

## Inputs

- The core loop and what the player does in each area (from `game-design-core`).
- Target devices and player count per server (mobile-first unless told otherwise).
- Art direction: stylized or realistic, palette, scale of the avatar (R15 is about 5 studs tall).
- Existing place file or Rojo project layout.

## Workflow

1. **Write the map plan first.** Fill in [references/map-plan-template.md](references/map-plan-template.md): zones, their purpose, the critical path from spawn to first reward, landmarks, and the streaming plan. Get it agreed before building.
2. **Block out in grey.** Use plain parts on a grid. Settle distances by walking them: a default Humanoid walks 16 studs/s, so a 160 stud street takes 10 s. Target the first reward within 30-60 s of spawn.
3. **Pick a grid and stick to it.** Use a 4 stud base module with 8 or 16 stud building modules (walls 1 stud thick, storeys 12-16 studs, doors about 4x8, corridors at least 6-8 studs wide for crowds and cameras). Set Studio Move snap to 1 or 4 and Rotate to 15 or 90.
4. **Shape the space with landmarks and sightlines.** Each zone gets one tall, uniquely coloured or lit landmark visible from its entrance. Frame the next goal through openings; block views of what is not yet reachable. Use light, colour and paths (wider, brighter, worn ground) to pull players along the critical path.
5. **Spawn areas.** Put `SpawnLocation`s in a calm, uncluttered spot facing the first objective, away from hazards and PvP. Give 2+ spawns spaced so a full server does not stack. Use `SpawnLocation.Neutral`/`TeamColor` for teams, and a short `Duration` forcefield in combat games.
6. **Terrain.** Generate base shapes in code, then hand-polish:

   ```lua
   --!strict
   local terrain = workspace.Terrain
   terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(1024, 16, 1024), Enum.Material.Grass)
   terrain:FillBall(Vector3.new(120, 10, -80), 40, Enum.Material.Rock)
   terrain:FillCylinder(CFrame.new(-60, -2, 40), 4, 30, Enum.Material.Water)
   -- Remove terrain to carve a path: fill with Air
   terrain:FillBlock(CFrame.new(0, 1, 0), Vector3.new(12, 4, 300), Enum.Material.Air)
   ```

   Use `Terrain:ReadVoxels`/`WriteVoxels` on 4-stud voxels for heightmaps (aligned `Region3:ExpandToGrid(4)`). Set `Terrain.Decoration` only where grass is wanted, it costs on mobile.
7. **Custom materials.** Add `MaterialVariant`s under `MaterialService` and set `MaterialService.<Material>Name` overrides, or set `BasePart.MaterialVariant` per part. Keep one palette of 6-10 materials for the whole map; more reads as noise.
8. **Modular buildings and streets.** Snap kit pieces to the grid, pivots at a corner or bottom-centre (pick one and document it). Group each building as a `Model`. Exteriors and interiors share the wall grid so doors line up; interiors that are not visible from outside can live in a separate streaming model.
9. **Biomes.** Give each biome its own ground material, 3-5 prop types, a colour accent and an atmosphere tweak; blend edges with a 20-40 stud transition band of mixed props.
10. **Scatter props** with the seeded script below. Place hero props by hand; scatter only fillers (rocks, grass, debris).
11. **Collision.** See the collision rules below. Add invisible walls only where a real-looking barrier is impossible.
12. **Navigation.** Add `PathfindingModifier` with a `Label` (e.g. `"Water"`, `"Door"`) and use agent `Costs` in `PathfindingService:CreatePath`; set `PassThrough = true` on modifiers for decorative parts NPCs may walk through. Use `PathfindingLink` for jumps and ladders. Check with Studio's navigation mesh visualisation (File > Studio Settings > Visualization > Show Navigation Mesh; verify location in your Studio version).
13. **Streaming.** Enable `Workspace.StreamingEnabled`. Group anything scripts need as a whole in a `Model` with `ModelStreamingMode = Atomic`; global landmarks that must always be visible as `Persistent` (sparingly). Distant scenery can use `Model.LevelOfDetail = StreamingMesh` for imposters. Client scripts must use `WaitForChild` or `ChildAdded` and tolerate parts streaming out. Call `Player:RequestStreamAroundAsync(position)` on the server before teleporting a player far.
14. **Environmental storytelling.** Each zone should answer "what happened here?" with 2-3 staged props (abandoned cart, scorched wall, footprints toward the next goal). Keep it readable at a glance, no text walls.

### Prop scatter (seeded, ground snapped)

```lua
--!strict
-- ServerScriptService/Tools/PropScatter.lua (run from the command bar or an edit-time plugin)
local Workspace = game:GetService("Workspace")

export type ScatterConfig = {
	seed: number,
	minCorner: Vector3, -- X/Z footprint; Y = ray end (bottom)
	maxCorner: Vector3, -- Y = ray start (top)
	count: number,
	minSpacing: number,
	maxSlopeDeg: number,
	templates: { Model }, -- pivots at the base, PrimaryPart set
	parent: Instance,
	allowedMaterials: { [Enum.Material]: boolean }?,
	exclude: { Instance }?,
	scaleMin: number?,
	scaleMax: number?,
}

local PropScatter = {}

function PropScatter.scatter(cfg: ScatterConfig): { Model }
	assert(#cfg.templates > 0, "PropScatter: no templates")
	local rng = Random.new(cfg.seed)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = table.clone(cfg.exclude or {})
	table.insert(excluded, cfg.parent)
	params.FilterDescendantsInstances = excluded

	local cosMax = math.cos(math.rad(cfg.maxSlopeDeg))
	local drop = Vector3.new(0, cfg.minCorner.Y - cfg.maxCorner.Y, 0)
	local allowed = cfg.allowedMaterials
	local placed: { Model } = {}
	local points: { Vector3 } = {}
	local attempts = 0

	while #placed < cfg.count and attempts < cfg.count * 20 do
		attempts += 1
		-- Draw every random value each attempt, in a fixed order, so a seed always gives the same layout.
		local x = rng:NextNumber(cfg.minCorner.X, cfg.maxCorner.X)
		local z = rng:NextNumber(cfg.minCorner.Z, cfg.maxCorner.Z)
		local index = rng:NextInteger(1, #cfg.templates)
		local yaw = rng:NextNumber(0, 2 * math.pi)
		local scaleT = rng:NextNumber()

		local hit = Workspace:Raycast(Vector3.new(x, cfg.maxCorner.Y, z), drop, params)
		if not hit or hit.Normal.Y < cosMax or hit.Material == Enum.Material.Water then
			continue
		end
		if allowed and not allowed[hit.Material] then
			continue
		end
		local p = hit.Position
		local free = true
		for _, q in points do
			local dx, dz = p.X - q.X, p.Z - q.Z
			if dx * dx + dz * dz < cfg.minSpacing * cfg.minSpacing then
				free = false
				break
			end
		end
		if not free then
			continue
		end

		local prop = cfg.templates[index]:Clone()
		local lo, hi = cfg.scaleMin or 1, cfg.scaleMax or 1
		if hi ~= 1 or lo ~= 1 then
			prop:ScaleTo(lo + (hi - lo) * scaleT)
		end
		-- Align up with a softened normal so props sit on slopes without leaning hard.
		local up = Vector3.yAxis:Lerp(hit.Normal, 0.5).Unit
		local forward = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local right = forward:Cross(up).Unit
		prop:PivotTo(CFrame.fromMatrix(p, right, up))
		prop:SetAttribute("ScatterSeed", cfg.seed)
		prop.Parent = cfg.parent
		table.insert(points, p)
		table.insert(placed, prop)
	end
	return placed
end

return PropScatter
```

Usage: run in edit mode, inspect, then keep the result as static geometry (scatter at runtime only if the map must vary). Re-running with the same seed on the same ground reproduces the layout. Spacing is O(n^2): above a few thousand props, switch to a grid hash.

### Collision rules

| Part kind | CanCollide | CanQuery | CanTouch | Notes |
|---|---|---|---|---|
| Walkable ground, walls | true | true | false | `CanTouch` off unless a script needs `.Touched` |
| Small decoration (grass, cups, signs) | false | false | false | Cheapest; also set `CastShadow = false` on tiny parts |
| Trigger zones | false | true | true | `Transparency = 1`, `Anchored = true` |
| Invisible wall | true | (true) | false | Name `InvisibleWall`, put in a collision group, prefer visible fences |
| Mesh props | true | true | false | `CollisionFidelity = Box` or `Hull`; `PreciseConvexDecomposition` only when needed |

`CanQuery = false` only takes effect when `CanCollide` is also false; a colliding part is always queryable, so use a `RaycastParams` filter or collision group to make rays skip an invisible wall. Register groups with `PhysicsService:RegisterCollisionGroup` and set `BasePart.CollisionGroup`.

## Outputs

- `docs/map-plan.md` (from the template) with zone list and critical path.
- Map geometry in the place or Rojo model files, organised as `Workspace/Map/<Zone>/<Building|Props|Terrain>`.
- Scatter tooling module and the seeds used, recorded in the map plan.

## Validation

1. Walk the critical path with a stopwatch on a phone-size test device (Studio Device Emulator, then a real phone). First reward under 60 s, no dead ends without a reason.
2. Play Test with 8+ players (Test > Clients and Servers) to check spawn crowding.
3. With StreamingEnabled on, teleport around and confirm no client errors in Output and no missing critical parts (`Atomic` models arrive whole).
4. Pathfinding: compute paths between every pair of zone entrances in a test script; every `Path.Status` should be `Success`.
5. Count with the MicroProfiler and `Stats` (Ctrl+Shift+F5 in clients): parts and draw calls per zone; compare against `roblox-performance` budgets.
6. Raycast down across the map in a grid to find holes (rays that hit nothing over the play area).

## Pitfalls

- Building off-grid early makes modular pieces never line up; fix the grid before decoration.
- Thousands of tiny unanchored or colliding parts: anchor everything static, disable collision on decoration.
- Huge single meshes defeat streaming; split by zone.
- `Persistent` on many models removes streaming benefits; reserve it for a few landmarks.
- Scattering at runtime on the client gives each client a different world unless all use the same seed and ground.
- Invisible walls with no visual cue feel unfair; add rocks, fences, water or a soft fog edge.
- Over-dense terrain decoration and many `Water` areas cost heavily on low-end phones.

## Limitations

- Cannot judge fun or readability without playtests; the plan is a starting point.
- Navigation mesh visualisation and streaming behaviour must be checked in Studio; this skill cannot run Studio.
- Exact Studio menu locations and some streaming properties change between releases; verify in creator docs.
