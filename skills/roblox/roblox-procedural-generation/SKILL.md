---
name: roblox-procedural-generation
description: Procedural content in Roblox - deterministic Random.new(seed), fractal math.noise heightmaps, Terrain FillBlock/FillRegion/WriteVoxels, grid and tile dungeons, a lightweight wave-function-collapse, chunked streaming generation, server vs client generation and frame budgets with task.wait. Use when generating terrain, dungeons, mazes, islands, loot placement or any seeded world content.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [procedural, seed, math.noise, perlin, heightmap, terrain generation, writevoxels, dungeon generator, wave function collapse, chunk generation]
  depends: [luau-language, roblox-performance]
---

# Roblox procedural generation

## When to use

- Seeded terrain (islands, hills, caves), dungeons and mazes, scattered props, loot tables placed in a world.
- Infinite or large worlds generated in chunks around players.

When not to use: hand-built maps; importing models (`find-resources` style workflows); loot odds and economy balance belong in `roblox-inventory-economy` and `monetization-economy-design`.

## Inputs

- Seed source (fixed per server, per player plot, or per day: `DateTime.now():ToUniversalTime()` fields).
- World size in studs, chunk size, voxel resolution (Terrain voxels are 4 studs).
- Who must see identical output (all clients: generate on server, or share the seed and generate deterministically on each client).

## Workflow

1. **Determinism first.** Use one `Random.new(seed)` per generator and pass it down. Never call `math.random` in generation code; its global state is shared. For a chunk, derive a sub-seed from the world seed and chunk coordinates so chunks are independent of generation order.
2. **Noise.** `math.noise(x, y, z)` returns roughly -1..1 (usually much closer to -0.5..0.5) and returns 0 at integer coordinates, so always scale inputs by a non-integer frequency and add a seed offset. Stack octaves for fractal detail (code below).
3. **Terrain writes.** For simple shapes, `Terrain:FillBlock(cframe, size, material)` and `FillBall`. For heightmaps use `Terrain:WriteVoxels(region, 4, materials, occupancies)` per chunk with a `Region3` aligned via `:ExpandToGrid(4)`. Keep each write region modest (for example 64 x 64 x 64 studs = 16^3 voxels); very large regions error or stall (verify the current maximum in creator docs).
4. **Tiles and dungeons.** Generate a logical grid (pure Luau tables) first, validate it (connectivity, room count), then instantiate prefab rooms from `ServerStorage`. Keep logic and instancing separate so the logic is unit-testable. See [references/dungeon-and-wfc.md](references/dungeon-and-wfc.md) for a room-and-corridor generator and a small WFC.
5. **Budget.** Yield inside long loops: check `os.clock()` and `task.wait()` once you have spent about 4-8 ms in a frame. Never generate a whole large map in one frame; the server stalls and clients disconnect.
6. **Server or client.**
   - Server: anything with collisions, gameplay, or that must be authoritative (dungeon walls, loot). Terrain written on the server replicates.
   - Client: purely decorative content (grass tufts, distant scenery), generated from a seed the server sends. Saves replication bandwidth.
7. **Chunked streaming.** Track which chunk each player stands in; generate chunks within a radius, and unload (or let StreamingEnabled stream out) those far from every player. Keep a `generated[chunkKey]` set so chunks are made once.

### Fractal heightmap into Terrain

```lua
--!strict
-- ServerScriptService/World/Heightmap.luau (ModuleScript)
local Workspace = game:GetService("Workspace")
local terrain = Workspace.Terrain

local VOXEL = 4
local CHUNK = 16 -- voxels per side horizontally (64 studs)
local HEIGHT_VOXELS = 24 -- 96 studs tall
local FRAME_BUDGET = 0.006

export type Settings = { seed: number, frequency: number, octaves: number, amplitude: number }

local Heightmap = {}

function Heightmap.fractal(x: number, z: number, s: Settings, offset: Vector2): number
	local total, amp, freq, norm = 0, 1, s.frequency, 0
	for _ = 1, s.octaves do
		total += math.noise(x * freq + offset.X, z * freq + offset.Y) * amp
		norm += amp
		amp *= 0.5
		freq *= 2
	end
	return total / norm -- roughly -1..1, usually narrower
end

function Heightmap.generateChunk(cx: number, cz: number, s: Settings)
	-- Offset from the seed, not from chunk order, so output is order-independent.
	local rng = Random.new(s.seed)
	local offset = Vector2.new(rng:NextNumber(-10000, 10000), rng:NextNumber(-10000, 10000))

	local origin = Vector3.new(cx * CHUNK * VOXEL, 0, cz * CHUNK * VOXEL)
	local region = Region3.new(origin, origin + Vector3.new(CHUNK * VOXEL, HEIGHT_VOXELS * VOXEL, CHUNK * VOXEL)):ExpandToGrid(VOXEL)

	local materials: { { { Enum.Material } } } = table.create(CHUNK)
	local occupancy: { { { number } } } = table.create(CHUNK)
	local started = os.clock()

	for ix = 1, CHUNK do
		materials[ix], occupancy[ix] = table.create(HEIGHT_VOXELS), table.create(HEIGHT_VOXELS)
		for iy = 1, HEIGHT_VOXELS do
			materials[ix][iy], occupancy[ix][iy] = table.create(CHUNK), table.create(CHUNK)
		end
		for iz = 1, CHUNK do
			local wx = origin.X + (ix - 0.5) * VOXEL
			local wz = origin.Z + (iz - 0.5) * VOXEL
			local h = (Heightmap.fractal(wx, wz, s, offset) * 0.5 + 0.5) * s.amplitude -- studs
			for iy = 1, HEIGHT_VOXELS do
				local top = iy * VOXEL
				local fill = math.clamp((h - (top - VOXEL)) / VOXEL, 0, 1) -- partial top voxel = smooth slope
				occupancy[ix][iy][iz] = fill
				materials[ix][iy][iz] = if fill <= 0 then Enum.Material.Air
					elseif h - top > 8 then Enum.Material.Rock
					else Enum.Material.Grass
			end
		end
		if os.clock() - started > FRAME_BUDGET then
			task.wait()
			started = os.clock()
		end
	end
	terrain:WriteVoxels(region, VOXEL, materials, occupancy)
end

return Heightmap
```

Driver: `for cx = -4, 3 do for cz = -4, 3 do Heightmap.generateChunk(cx, cz, settings) end end` with `settings = { seed = 12345, frequency = 1/180, octaves = 4, amplitude = 80 }`.

## Outputs

- Generator modules split into pure logic (grid, noise sampling) and instancing (Terrain writes, prefab clones).
- A seed recorded somewhere observable (server attribute `WorldSeed`) so bugs are reproducible.

## Validation

1. Determinism test: run the pure grid generator twice with the same seed under Lune and assert equal output; different seeds give different output (see `roblox-testing-debugging`).
2. Connectivity test: flood-fill the logical dungeon grid and assert every room is reachable.
3. In Studio, generate with a fixed seed, screenshot from a fixed camera, regenerate, compare.
4. MicroProfiler / Developer Console server stats during generation: no frame over ~50 ms on the server, no client disconnects.

## Pitfalls

- **Flat terrain**: inputs to `math.noise` were integers (always 0). Multiply by a fractional frequency.
- **Seams between chunks**: chunks used chunk-local noise coordinates. Always sample in world coordinates.
- **Different output per run** with the same seed: something used `math.random`, `os.time`, table iteration order of a dictionary (`pairs` order is not guaranteed), or generation order mattered. Sort keys before iterating.
- **WriteVoxels shape error**: the 3D arrays must match the region size in voxels exactly, indexed `[x][y][z]`.
- **Server freeze**: no yielding in a big loop. Add the frame-budget check.
- **Too many parts**: thousands of prefab parts per chunk kill performance; prefer Terrain, MeshParts with `CollisionFidelity = Box`, and StreamingEnabled (`roblox-performance`).

## Limitations

- `math.noise` is a gradient noise without a seed parameter; seeding works by offsetting coordinates, which is standard but not cryptographic.
- The WFC in the reference is a small, backtrack-free version; it can fail on contradictory tile sets and simply retries with a new sub-seed.
- Terrain write size limits and performance vary by engine version; verify in creator docs and measure.
