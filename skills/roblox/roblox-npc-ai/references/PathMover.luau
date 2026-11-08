--!strict
-- PathMover.luau: walks a Humanoid NPC to a goal with PathfindingService,
-- handles Jump waypoints, Blocked events, stuck detection and recompute.

local PathfindingService = game:GetService("PathfindingService")

export type PathMover = {
	moveTo: (self: PathMover, goal: Vector3) -> (),
	stop: (self: PathMover) -> (),
	destroy: (self: PathMover) -> (),
	isMoving: (self: PathMover) -> boolean,
}

local RECOMPUTE_DISTANCE = 4   -- studs the goal may move before we repath
local STUCK_SECONDS = 2

local PathMover = {}

function PathMover.new(humanoid: Humanoid, root: BasePart, agentParams: { [string]: any }?): PathMover
	local path = PathfindingService:CreatePath(agentParams or {
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
		Costs = { Water = 20 },   -- material or PathfindingModifier label -> cost
	})

	local waypoints: { PathWaypoint } = {}
	local index = 0
	local goal: Vector3? = nil
	local generation = 0          -- invalidates stale computations
	local blockedConn: RBXScriptConnection? = nil
	local reachedConn: RBXScriptConnection? = nil
	local lastProgress = os.clock()

	local self = {} :: PathMover

	local function step()
		index += 1
		local wp = waypoints[index]
		if not wp then
			goal = nil
			return
		end
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(wp.Position)
		lastProgress = os.clock()
	end

	local function compute(target: Vector3)
		generation += 1
		local myGen = generation
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if myGen ~= generation then
			return -- a newer request replaced this one while we yielded
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			waypoints = {}
			index = 0
			humanoid:MoveTo(root.Position) -- stand still; caller may retry
			return
		end
		waypoints = path:GetWaypoints()
		index = 1 -- waypoint 1 is the start position
		step()
	end

	blockedConn = path.Blocked:Connect(function(blockedIndex: number)
		if goal and blockedIndex >= index then
			task.spawn(compute, goal)
		end
	end)

	reachedConn = humanoid.MoveToFinished:Connect(function(reached: boolean)
		if not goal then
			return
		end
		if reached then
			step()
		else
			-- MoveTo times out after about 8 seconds without reaching; repath
			task.spawn(compute, goal)
		end
	end)

	function self.moveTo(_, target: Vector3)
		if goal and (goal - target).Magnitude < RECOMPUTE_DISTANCE and index > 0 then
			-- same goal; only repath if stuck
			if os.clock() - lastProgress > STUCK_SECONDS and root.AssemblyLinearVelocity.Magnitude < 0.5 then
				goal = target
				task.spawn(compute, target)
			end
			return
		end
		goal = target
		task.spawn(compute, target)
	end

	function self.stop(_)
		generation += 1
		goal = nil
		waypoints = {}
		index = 0
		humanoid:MoveTo(root.Position)
	end

	function self.isMoving(_): boolean
		return goal ~= nil
	end

	function self.destroy(s: PathMover)
		s:stop()
		if blockedConn then blockedConn:Disconnect() end
		if reachedConn then reachedConn:Disconnect() end
		path:Destroy()
	end

	return self
end

return PathMover
