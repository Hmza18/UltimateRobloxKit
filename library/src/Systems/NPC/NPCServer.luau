--!strict
-- Server adapter for NPCs: PathfindingService movement with waypoint following, re-pathing when the
-- path is blocked or the goal moves, stuck detection (jump, then re-path), and an optional "brain"
-- (behaviour tree or state machine from NPCLogic) ticked at a fixed rate.

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local NPCLogic = require("./NPCLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type MoveStatus = "idle" | "computing" | "moving" | "arrived" | "failed"

export type Options = {
	agent: { [string]: any }?, -- CreatePath parameters, for example { AgentRadius = 2, AgentCanJump = true }
	arriveTolerance: number?, -- studs, default 3
	repathDistance: number?, -- re-path when the goal moves further than this, default 4
	repathInterval: number?, -- seconds between goal-driven re-paths, default 0.5
	stuckWindow: number?, -- seconds without progress before counting as stuck, default 1.5
	stuckDistance: number?, -- studs of progress that reset the stuck timer, default 1
	maxStuckRetries: number?, -- re-paths after getting stuck before failing, default 3
	thinkRate: number?, -- brain ticks per second, default 5
	sightRange: number?, -- default 60
	fov: number?, -- degrees, default 120
	hearingRange: number?, -- default 15
}

export type Brain = { tree: NPCLogic.BTNode?, machine: NPCLogic.Machine?, blackboard: { [string]: any } }

export type Agent = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	goTo: (self: Agent, position: Vector3) -> NPCLogic.Status, -- call every tick from a behaviour tree action
	moveTo: (self: Agent, position: Vector3) -> (),
	stop: (self: Agent) -> (),
	status: (self: Agent) -> MoveStatus,
	canSee: (self: Agent, target: BasePart) -> boolean,
	perceive: (self: Agent, target: BasePart) -> string?,
	setBrain: (self: Agent, brain: Brain?) -> (),
	statusChanged: Signal.Signal, -- (status)
	destroy: (self: Agent) -> (),
}

local NPCServer = {}

local function toVec(position: Vector3): NPCLogic.Vec3
	return NPCLogic.vec(position.X, position.Y, position.Z)
end

function NPCServer.new(model: Model, options: Options?): Agent
	local opts: Options = options or {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	assert(humanoid, "NPCServer: model needs a Humanoid")
	assert(root and root:IsA("BasePart"), "NPCServer: model needs a PrimaryPart or HumanoidRootPart")
	local rootPart = root :: BasePart

	local arriveTolerance = opts.arriveTolerance or 3
	local repathDistance = opts.repathDistance or 4
	local repathInterval = opts.repathInterval or 0.5
	local maxStuckRetries = opts.maxStuckRetries or 3
	local thinkInterval = 1 / (opts.thinkRate or 5)
	local perception: NPCLogic.PerceptionOptions = {
		sightRange = opts.sightRange or 60,
		fov = opts.fov or 120,
		hearingRange = opts.hearingRange or 15,
	}

	local trove = Trove.new()
	local statusChanged = Signal.new()
	trove:Add(function()
		statusChanged:DisconnectAll()
	end)
	local path = PathfindingService:CreatePath(opts.agent or {})
	local stuck = NPCLogic.newStuckDetector(opts.stuckWindow or 1.5, opts.stuckDistance or 1)

	local moveStatus: MoveStatus = "idle"
	local goal: Vector3? = nil
	local lastPathGoal: NPCLogic.Vec3? = nil
	local lastPathTime = -math.huge
	local waypoints: { PathWaypoint } = {}
	local waypointIndex = 0
	local computeToken = 0
	local stuckRetries = 0
	local brain: Brain? = nil

	-- Server-owned physics keeps NPC movement authoritative and avoids hand-offs to nearby players.
	if rootPart:CanSetNetworkOwnership() then
		rootPart:SetNetworkOwner(nil)
	end

	local function setStatus(nextStatus: MoveStatus)
		if moveStatus ~= nextStatus then
			moveStatus = nextStatus
			statusChanged:Fire(nextStatus)
		end
	end

	local function moveToWaypoint()
		local waypoint = waypoints[waypointIndex]
		if waypoint == nil then
			waypoints = {}
			setStatus("arrived")
			return
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
	end

	local function computePath()
		local target = goal
		if target == nil then
			return
		end
		computeToken += 1
		local token = computeToken
		lastPathGoal = toVec(target)
		lastPathTime = os.clock()
		setStatus("computing")
		task.spawn(function()
			local ok = pcall(function()
				path:ComputeAsync(rootPart.Position, target)
			end)
			if token ~= computeToken then
				return -- a newer request replaced this one
			end
			if not ok or path.Status ~= Enum.PathStatus.Success then
				waypoints = {}
				setStatus("failed")
				return
			end
			waypoints = path:GetWaypoints()
			-- The first waypoint is the start position.
			waypointIndex = math.min(2, #waypoints)
			NPCLogic.resetStuck(stuck, toVec(rootPart.Position), os.clock())
			setStatus("moving")
			moveToWaypoint()
		end)
	end

	trove:Connect(humanoid.MoveToFinished, function(reached: boolean)
		if moveStatus ~= "moving" then
			return
		end
		if reached then
			waypointIndex += 1
			moveToWaypoint()
		else
			computePath() -- Humanoid:MoveTo gives up after about 8 seconds
		end
	end)

	trove:Connect(path.Blocked, function(blockedIndex: number)
		if moveStatus == "moving" and blockedIndex >= waypointIndex then
			computePath()
		end
	end)

	local agent = {} :: Agent
	agent.model = model
	agent.humanoid = humanoid
	agent.root = rootPart
	agent.statusChanged = statusChanged

	function agent.moveTo(_self: Agent, position: Vector3)
		goal = position
		stuckRetries = 0
		computePath()
	end

	function agent.goTo(self: Agent, position: Vector3): NPCLogic.Status
		local goalVec = toVec(position)
		if NPCLogic.reached(toVec(rootPart.Position), goalVec, arriveTolerance) then
			if moveStatus == "moving" or moveStatus == "computing" then
				self:stop()
			end
			return "success"
		end
		if moveStatus == "failed" and goal and (goal - position).Magnitude < repathDistance then
			return "failure"
		end
		local idle = moveStatus == "idle" or moveStatus == "arrived"
		local now = os.clock()
		local moved = NPCLogic.shouldRepath(lastPathGoal, goalVec, lastPathTime, now, repathDistance, repathInterval)
		if idle or moved then
			self:moveTo(position)
		end
		return "running"
	end

	function agent.stop(_self: Agent)
		computeToken += 1
		goal = nil
		waypoints = {}
		humanoid:MoveTo(rootPart.Position)
		setStatus("idle")
	end

	function agent.status(_self: Agent): MoveStatus
		return moveStatus
	end

	function agent.perceive(_self: Agent, target: BasePart): string?
		local look = rootPart.CFrame.LookVector
		return NPCLogic.perceive(toVec(rootPart.Position), toVec(look), toVec(target.Position), perception)
	end

	-- Sight test plus a raycast, so walls block vision.
	function agent.canSee(self: Agent, target: BasePart): boolean
		if self:perceive(target) ~= "seen" then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local direction = target.Position - rootPart.Position
		local hit = workspace:Raycast(rootPart.Position, direction, params)
		return hit == nil or hit.Instance:IsDescendantOf(target.Parent or target)
	end

	function agent.setBrain(_self: Agent, nextBrain: Brain?)
		brain = nextBrain
	end

	local thinkAccumulator = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		if moveStatus == "moving" then
			if NPCLogic.updateStuck(stuck, toVec(rootPart.Position), os.clock()) then
				stuckRetries += 1
				if stuckRetries > maxStuckRetries then
					waypoints = {}
					setStatus("failed")
				else
					humanoid.Jump = true
					computePath()
				end
			end
		end
		thinkAccumulator += dt
		if brain == nil or thinkAccumulator < thinkInterval then
			return
		end
		local elapsed = thinkAccumulator
		thinkAccumulator = 0
		local current = brain
		local ctx = { agent = agent, blackboard = current.blackboard, dt = elapsed, now = os.clock() }
		if current.machine then
			NPCLogic.stepMachine(current.machine, ctx, elapsed)
		end
		if current.tree then
			NPCLogic.tick(current.tree, ctx)
		end
	end)

	trove:Connect(model.AncestryChanged, function()
		if not model:IsDescendantOf(workspace) then
			agent:destroy()
		end
	end)

	function agent.destroy(_self: Agent)
		computeToken += 1
		brain = nil
		trove:Clean()
	end

	return agent
end

return NPCServer
