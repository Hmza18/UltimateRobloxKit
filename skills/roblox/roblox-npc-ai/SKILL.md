---
name: roblox-npc-ai
description: NPC behaviour in Roblox - Humanoid NPC setup, PathfindingService agent parameters, waypoints, Blocked events and recompute, finite state machines and behavior trees in Luau, perception with raycast line of sight and spatial queries, server network ownership and scaling to many NPCs with one scheduler. Use when building enemies, shopkeepers, pets, followers or crowds, or when NPCs get stuck, jitter or cost too much frame time.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [npc, pathfinding, pathfindingservice, enemy ai, state machine, behavior tree, line of sight, waypoint, aggro, mob]
  depends: [luau-language, roblox-physics-interactions, roblox-animation]
---

# Roblox NPC AI

## When to use

- Enemies that patrol, chase and attack; shopkeepers; pets and followers; ambient crowds.
- NPCs that get stuck on corners, walk through walls, jitter or teleport.
- Many NPCs making the server slow.

When not to use: NPC animation playback (use `roblox-animation`), combat hit validation (use `roblox-physics-interactions`), dialogue UI (use `roblox-ui-systems`).

## Inputs

- An NPC model: a `Model` with `Humanoid`, `HumanoidRootPart` set as `PrimaryPart`, and an `Animator` under the Humanoid. R15 or R6 rigs from the Avatar tab's Rig Builder work.
- The map, with walkable areas, doors, water and jump gaps marked (`PathfindingModifier`, `PathfindingLink`).

## Workflow

1. **Set up the rig on the server.** Parent the NPC to a `Workspace.NPCs` folder, then `npc.HumanoidRootPart:SetNetworkOwner(nil)` so the server simulates it (otherwise a nearby player's client owns it and can teleport it).
2. **Choose agent parameters** matching the rig: `AgentRadius`, `AgentHeight`, `AgentCanJump`, `AgentCanClimb`, `WaypointSpacing`, `Costs` (by material name or modifier label; `math.huge` forbids).
3. **Move with a path mover** that handles jumps, `Blocked`, `MoveToFinished` timeouts and stuck detection. Copy [references/PathMover.luau](references/PathMover.luau).
4. **Drive decisions with a state machine** (few states) or a behavior tree (many conditions). A small BT library is in [references/BehaviorTree.luau](references/BehaviorTree.luau).
5. **Perceive cheaply**: distance check first, then a cone check, then one raycast for line of sight. Use `workspace:GetPartBoundsInRadius` with `OverlapParams` to find candidates near the NPC when targets are not just players.
6. **Tick all NPCs from one scheduler** at a fixed rate (5 to 10 Hz for decisions), spreading NPCs across frames. Pathfinding runs in its own threads.
7. **Despawn or freeze far NPCs**: no players within range means no thinking.

### State machine with perception

```luau
--!strict
local Players = game:GetService("Players")

type State = "Idle" | "Patrol" | "Chase" | "Attack" | "Return"

export type Brain = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: State,
	target: Player?,
	home: Vector3,
	lastAttack: number,
	mover: any,                    -- PathMover from references/PathMover.luau
}

local SIGHT_RANGE = 60
local SIGHT_FOV_COS = math.cos(math.rad(70))  -- 140 degree cone
local ATTACK_RANGE = 5
local LEASH = 120

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function canSee(brain: Brain, targetRoot: BasePart): boolean
	local origin = brain.root.Position + Vector3.new(0, 1.5, 0)
	local offset = targetRoot.Position - origin
	local dist = offset.Magnitude
	if dist > SIGHT_RANGE then
		return false                                    -- cheapest test first
	end
	if brain.root.CFrame.LookVector:Dot(offset.Unit) < SIGHT_FOV_COS and dist > 10 then
		return false                                    -- behind us (but always notice close players)
	end
	rayParams.FilterDescendantsInstances = { brain.model }
	local hit = workspace:Raycast(origin, offset, rayParams)
	return hit ~= nil and hit.Instance:IsDescendantOf(targetRoot.Parent :: Instance)
end

local function findTarget(brain: Brain): Player?
	local best: Player? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - brain.root.Position).Magnitude
			if d < bestDist and canSee(brain, hrp) then
				best, bestDist = player, d
			end
		end
	end
	return best
end

local function targetRoot(brain: Brain): BasePart?
	local char = brain.target and brain.target.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Called by the scheduler about 5 times per second per NPC.
local function think(brain: Brain)
	if brain.humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if brain.state == "Idle" or brain.state == "Patrol" then
		brain.target = findTarget(brain)
		if brain.target then
			brain.state = "Chase"
		end
	elseif brain.state == "Chase" then
		local tr = targetRoot(brain)
		if not tr or (brain.root.Position - brain.home).Magnitude > LEASH then
			brain.state, brain.target = "Return", nil
			return
		end
		if (tr.Position - brain.root.Position).Magnitude <= ATTACK_RANGE then
			brain.state = "Attack"
			brain.mover:stop()
		else
			brain.mover:moveTo(tr.Position)
		end
	elseif brain.state == "Attack" then
		local tr = targetRoot(brain)
		if not tr or (tr.Position - brain.root.Position).Magnitude > ATTACK_RANGE + 1 then
			brain.state = "Chase"
		elseif now - brain.lastAttack > 1.2 then
			brain.lastAttack = now
			local hum = (tr.Parent :: Model):FindFirstChildOfClass("Humanoid")
			if hum then
				hum:TakeDamage(10)                     -- server applies damage
			end
		end
	elseif brain.state == "Return" then
		brain.mover:moveTo(brain.home)
		if (brain.root.Position - brain.home).Magnitude < 4 then
			brain.state = "Idle"
		end
	end
end

-- One scheduler for every NPC; spreads work across frames.
local brains: { Brain } = {}
local THINK_INTERVAL = 0.2
local cursor = 1
local accumulator = 0

game:GetService("RunService").Heartbeat:Connect(function(dt)
	accumulator += dt
	local count = #brains
	if count == 0 then
		return
	end
	local budget = math.ceil(count * math.min(accumulator / THINK_INTERVAL, 1))
	accumulator = 0
	for _ = 1, budget do
		if cursor > count then
			cursor = 1
		end
		task.spawn(think, brains[cursor])            -- isolate errors per NPC
		cursor += 1
	end
end)

return { brains = brains, think = think }
```

### Pathfinding details

- `path:ComputeAsync(start, goal)` yields; never call it every frame. Repath when the goal moved more than a few studs, on `Blocked`, or when stuck.
- Check `path.Status == Enum.PathStatus.Success` before `GetWaypoints()`. `NoPath` means unreachable; fall back to direct `MoveTo` or give up.
- `Humanoid:MoveTo` gives up after about 8 seconds and fires `MoveToFinished(false)`; the mover repaths then.
- Mark doors and ladders with `PathfindingLink`, no-go zones with `PathfindingModifier` (label + `Costs`), and set `PassThrough` on modifiers for decorative parts.
- For straight-line chasing in open arenas, skip pathfinding and `MoveTo` the target directly when a raycast shows a clear line.

### Scaling to many NPCs

- Decisions at 5 Hz, movement by the Humanoid, animation on the client if needed (see `roblox-animation`).
- Disable unused humanoid states (`Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)`, and others) to cut physics cost.
- Past roughly 50 to 100 humanoid NPCs, consider non-Humanoid NPCs (anchored or AnimationController rigs moved by CFrame on the server, or rendered by clients from replicated positions). Measure with the MicroProfiler (see `roblox-performance`).
- Use `StreamingEnabled` and model streaming modes so distant NPCs do not reach clients.

## Outputs

- NPC templates in `ServerStorage.NPCs`, a spawner service, `PathMover`, the brain/scheduler module.

## Validation

1. Play solo: the NPC patrols, sees you only when in front and unobstructed, chases around obstacles, attacks, and returns home when you outrun the leash.
2. Drop a part on its path mid-walk; it repaths (Blocked) instead of walking into it.
3. Enable Studio's Navigation Mesh view (Studio settings > Visualization) to confirm walkable areas and links.
4. Spawn the target count of NPCs; MicroProfiler shows the AI scheduler under its frame budget on the server (Developer Console > Server Jobs / Scripts).
5. Confirm `part:GetNetworkOwner()` returns nil for each NPC root on the server.

## Pitfalls

- **NPC owned by a client**: unanchored parts near a player go to that player's client; call `SetNetworkOwner(nil)` after parenting.
- **ComputeAsync in a tight loop** throttles and lags the server.
- **Raycast hits the NPC's own parts**: exclude the NPC model.
- **NPC stuck on its spawn**: spawn it slightly above the floor and make sure the HumanoidRootPart is not anchored.
- **One `while true do` loop per NPC** with `task.wait` piles up threads and drifts; use one scheduler.
- **Hip height wrong** on custom rigs makes NPCs float or sink; set `Humanoid.HipHeight` to match leg length.

## Limitations

- Pathfinding results depend on the navmesh, which Roblox generates; very large or dynamic maps may give partial paths. Verify modifier and link behaviour in creator docs.
- Numbers for how many NPCs a server can run depend on the game; only profiling proves them.
- This skill does not cover client-rendered NPC replication in depth.
