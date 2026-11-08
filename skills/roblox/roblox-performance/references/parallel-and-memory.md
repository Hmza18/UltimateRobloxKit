# Parallel Luau and memory categories

## Actor raycast worker

Layout: `ServerScriptService/RayWorkers/Worker1` (an `Actor`) containing a `Script` with this code. Clone the Actor 2-4 times for more workers.

```lua
--!strict
-- Script inside an Actor. Answers batched line-of-sight queries in parallel.
local Workspace = game:GetService("Workspace")
local SharedTableRegistry = game:GetService("SharedTableRegistry")

local actor = script:GetActor()
assert(actor, "must run inside an Actor")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

type Query = { id: number, from: Vector3, to: Vector3 }

actor:BindToMessageParallel("CheckSight", function(queries: { Query }, registryKey: string)
	-- We are in the parallel phase here: raycasts are allowed, Instance writes are not.
	local out = {}
	for _, q in queries do
		local hit = Workspace:Raycast(q.from, q.to - q.from, params)
		out[q.id] = hit == nil
	end
	-- SharedTable may be written from the parallel phase; Instance writes would need task.synchronize().
	local shared = SharedTableRegistry:GetSharedTable(registryKey)
	for id, visible in out do
		shared[id] = visible
	end
end)
```

Requester (serial script): split queries across workers, `worker:SendMessage("CheckSight", batch, "SightResults")`, then read `SharedTableRegistry:GetSharedTable("SightResults")` on the next frame. Messages are processed in a later parallel phase, not immediately.

The requester creates the table once with `SharedTableRegistry:SetSharedTable("SightResults", SharedTable.new())`. Verify the SharedTable API (including atomic `SharedTable.update`) in creator docs for your engine version.

Use parallel workers only for work that is heavy and independent: many raycasts, spatial queries, pathfinding preparation, procedural math. Small jobs lose more to scheduling than they gain.

## Memory categories (Developer Console > Memory)

| Category | Grows when | Fix |
|---|---|---|
| `Instances` | many parts, clones never destroyed | streaming, pooling, `Destroy()` |
| `LuaHeap` | tables, closures, leaked connections | clear per-player tables, disconnect |
| `PhysicsParts` / `PhysicsCollision` | many collidable parts, precise collision | Box/Hull fidelity, anchor, CanCollide false |
| `GraphicsTexture` | many or large unique textures | fewer, smaller textures |
| `GraphicsMeshParts` | many unique meshes | reuse mesh assets |
| `GraphicsParticles` | many live particles | shorter lifetime, fewer emitters |
| `Sounds` | many loaded sounds | stream long music, unload unused |
| `Animation` | many loaded tracks per humanoid | load once and cache tracks |

Server-side numbers come from the server view of the Developer Console (needs edit permission on the experience). Scripts can read tagged memory with `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.X)` for dashboards.
