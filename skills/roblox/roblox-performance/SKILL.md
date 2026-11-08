---
name: roblox-performance
description: Roblox performance - StreamingEnabled and ModelStreamingMode (Atomic, Persistent), part counts, MeshPart CollisionFidelity and RenderFidelity, instancing and draw calls, texture memory, script hotspots (Heartbeat budgets, task.defer, Parallel Luau with Actors and task.desynchronize), network bandwidth, memory categories and mobile targets. Use when an experience lags, stutters, uses too much memory, loads slowly, or must run well on phones.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [lag, fps, streamingenabled, modelstreamingmode, draw calls, collisionfidelity, parallel luau, actor, memory usage, optimization, mobile performance]
  depends: [roblox-testing-debugging, roblox-architecture]
---

# Roblox performance

## When to use

- Low FPS, frame spikes, long join times, high memory, crashes on phones, server lag (high heartbeat time, delayed physics).
- Planning a large map or many NPCs before building it.

When not to use: correctness bugs (`roblox-testing-debugging`); reducing mesh triangle counts in Blender (`blender-game-optimization` if installed); VFX-specific budgets (`roblox-vfx`).

## Inputs

- Target devices and the lowest one you support (a 3-4 GB RAM phone is a realistic floor).
- A repro: place, location in the map, player count, and what is happening when it lags.
- Measurements, not guesses (see Validation).

## Rough budgets (starting points, measure on device)

| Area | Mobile target | Notes |
|---|---|---|
| Frame time | 16.6 ms (60 FPS), never above 33 ms | Client render + scripts + physics |
| Client memory | well under ~1.5 GB total on low-end phones | Developer Console > Memory |
| Server heartbeat | ~60 Hz steady | Drops mean server scripts or physics overload |
| Instances in view | a few thousand parts | Use streaming to keep it local |
| Script time per frame | 1-3 ms for gameplay | MicroProfiler `Heartbeat` / your labels |

## Workflow

1. **Measure first.** Developer Console (F9) Memory tab by category, MicroProfiler (Ctrl+Alt+F6) for frame breakdowns, Script tab / ScriptProfiler for script CPU. In Studio, **View > Stats** and the Script Performance window.
2. **Enable StreamingEnabled** on `Workspace` for any map bigger than a small arena. Tune `StreamingTargetRadius` and `StreamingMinRadius`. Client code must not assume parts exist: use `WaitForChild` with a timeout, `ChildAdded`, or CollectionService `GetInstanceAddedSignal`.
3. **Model streaming modes** (`Model.ModelStreamingMode`): `Atomic` streams a model as a whole (good for doors or vehicles whose scripts need all parts), `Persistent` keeps it always present for all clients (use sparingly: spawn, key landmarks), `PersistentPerPlayer` plus `Model:AddPersistentPlayer(player)` for per-player persistence. Use `Player:RequestStreamAroundAsync(position)` before teleporting a player across the map.
4. **Parts and geometry:**
   - Fewer, larger parts beat many small ones. Merge static decoration into MeshParts.
   - `CollisionFidelity = Box` (or `Hull`) for decorative meshes; `PreciseConvexDecomposition` only where precise collision matters. Set `CanCollide`, `CanTouch`, `CanQuery` false on decoration.
   - `RenderFidelity = Automatic` lets distant meshes use lower detail; `Precise` is always full detail.
   - Anchor everything static. Unanchored parts cost physics on the server and network ownership traffic.
5. **Draw calls and instancing:** identical MeshParts (same MeshId, same material/texture) are batched by the engine; many unique meshes and materials each cost draw calls. Reuse meshes and textures; prefer MaterialVariants and a small texture set over many unique images.
6. **Texture memory:** 1024 px is plenty for most props; reserve 2048+ for hero assets. Each unique texture stays in memory while referenced. Watch the `GraphicsTexture` memory category.
7. **Script hotspots:**
   - Do not run per-frame work for things that change rarely. Use events, attributes changed signals, or a timer at 5-10 Hz.
   - Batch per-frame work into one `RunService.Heartbeat` connection that iterates a list, with a time budget (code below).
   - `task.defer` to push non-urgent work past the current resumption; `task.spawn` for immediate concurrent threads.
   - Cache `FindFirstChild` results and services; avoid `GetDescendants` in loops.
8. **Parallel Luau:** put scripts under an `Actor`; inside, call `task.desynchronize()` for read-only parallel work (raycasts, math, pathfinding prep), then `task.synchronize()` before writing to Instances. Share data via `SharedTable` or Actor messages (`Actor:SendMessage`, `BindToMessageParallel`). Worth it only for heavy, independent work.
9. **Network:** send deltas, not full state; throttle remotes to 10-20 Hz for continuous data; use `UnreliableRemoteEvent` for cosmetic high-rate data; avoid replicating large tables through attributes every frame. Developer Console > Network shows bandwidth per remote type.
10. **Memory leaks:** disconnect connections, `Destroy()` instances you create, clear tables keyed by Player on `PlayerRemoving`. A steady rise in `LuaHeap` or `Instances` over minutes is a leak.

### Budgeted update scheduler

```lua
--!strict
-- ReplicatedStorage/Shared/Scheduler.luau
-- Runs many small jobs per frame within a time budget, round-robin, so 2,000 NPC
-- updates spread over several frames instead of spiking one.
local RunService = game:GetService("RunService")

export type Job = (dt: number) -> ()

local Scheduler = {}
local jobs: { Job } = {}
local index = 1
local BUDGET_SECONDS = 0.002 -- 2 ms per frame

function Scheduler.add(job: Job): () -> ()
	table.insert(jobs, job)
	return function()
		local i = table.find(jobs, job)
		if i then
			table.remove(jobs, i)
			if index > i then
				index -= 1
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	local count = #jobs
	if count == 0 then
		return
	end
	local deadline = os.clock() + BUDGET_SECONDS
	local processed = 0
	debug.profilebegin("Scheduler")
	while processed < count and os.clock() < deadline do
		if index > #jobs then
			index = 1
		end
		local job = jobs[index]
		index += 1
		processed += 1
		local ok, err = pcall(job, dt)
		if not ok then
			warn("Scheduler job failed:", err)
		end
	end
	debug.profileend()
end)

return Scheduler
```

Jobs receive the frame `dt`, not the time since they last ran; jobs that need elapsed time should track their own `os.clock()`.

Parallel Luau example (Actor raycast worker) and a memory-category cheat sheet: [references/parallel-and-memory.md](references/parallel-and-memory.md).

## Outputs

- Streaming settings, fixed collision and render fidelity on heavy meshes, scheduler-based updates, a before/after measurement table.

## Validation

1. Record before numbers: FPS on the target device, Memory by category, MicroProfiler capture of the worst frame, server heartbeat with N players.
2. Apply one change at a time; re-measure in the same spot with the same player count.
3. Studio device emulation does not emulate phone CPU/GPU; test on a real low-end phone for final numbers.
4. Long session test (20+ minutes): memory flat or bounded.

## Pitfalls

- **Streaming breaks scripts**: client code indexing `workspace.Map.Door` errors when the door is not streamed in. Use tags and `GetInstanceAddedSignal`, or mark that model `Atomic`/`Persistent`.
- **Everything Persistent**: defeats streaming. Keep the persistent set small.
- **`while true do task.wait() end` loops** per object: thousands of threads. Use one scheduler.
- **Parallel Luau writes in a desynchronized phase** error. Synchronize first.
- **Precise collisions on every mesh**: heavy physics and memory. Default to Box/Hull.
- **Optimizing without a profile**: time lost on things that were not the bottleneck.

## Limitations

- Budgets here are practical guidance, not Roblox-published guarantees; device performance varies widely.
- The engine's internal batching and streaming heuristics change between releases; verify property behavior in creator docs.
- This skill cannot profile a device it has no access to; real-device numbers must come from the user.
