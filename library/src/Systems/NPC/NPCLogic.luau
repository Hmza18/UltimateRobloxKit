--!strict
-- NPC behaviour building blocks. Pure Luau: vectors are plain { x, y, z } tables and time is passed in.
--   * Finite-state machine with enter/exit/update hooks and ordered transitions.
--   * Behaviour tree: sequence, selector, condition, action, invert, succeed; "running" is remembered.
--   * Perception: distance, view cone and hearing tests.
--   * Patrol routes (loop, ping-pong, once), arrival checks and stuck detection.

export type Vec3 = { x: number, y: number, z: number }
export type Status = "success" | "failure" | "running"

export type StateDef = {
	enter: ((ctx: any, machine: Machine) -> ())?,
	exit: ((ctx: any, machine: Machine) -> ())?,
	update: ((ctx: any, machine: Machine, dt: number) -> ())?,
}

export type Transition = { from: string, to: string, when: (ctx: any, machine: Machine) -> boolean }

export type MachineDef = { initial: string, states: { [string]: StateDef }, transitions: { Transition }? }

export type Machine = {
	current: string,
	previous: string?,
	timeInState: number,
	states: { [string]: StateDef },
	transitions: { Transition },
}

export type BTNode = {
	kind: string, -- "sequence" | "selector" | "condition" | "action" | "invert" | "succeed"
	children: { BTNode }?,
	child: BTNode?,
	fn: ((ctx: any) -> any)?,
	memory: boolean, -- composites resume a running child instead of starting over
	running: number?, -- index of the child that returned "running" last tick
}

export type Patrol = { points: { Vec3 }, index: number, direction: number, mode: string, finished: boolean }

export type StuckDetector = { window: number, minDistance: number, anchor: Vec3?, anchorTime: number }

export type PerceptionOptions = { sightRange: number, fov: number, hearingRange: number?, flat: boolean? }

local NPC = {}

-- Vectors ------------------------------------------------------------------------------------------

function NPC.vec(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function sub(a: Vec3, b: Vec3, flat: boolean?): Vec3
	return { x = a.x - b.x, y = if flat then 0 else a.y - b.y, z = a.z - b.z }
end

local function length(v: Vec3): number
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

function NPC.distance(a: Vec3, b: Vec3, flat: boolean?): number
	return length(sub(a, b, flat))
end

-- Finite-state machine -----------------------------------------------------------------------------

-- Creates a machine in `def.initial` and runs that state's enter hook.
function NPC.newMachine(def: MachineDef, ctx: any?): Machine
	assert(type(def) == "table" and type(def.states) == "table", "machine needs states")
	assert(def.states[def.initial] ~= nil, "initial state must exist")
	for _, transition in def.transitions or {} do
		assert(transition.from == "*" or def.states[transition.from] ~= nil, "unknown state " .. transition.from)
		assert(def.states[transition.to] ~= nil, "unknown state " .. tostring(transition.to))
	end
	local machine: Machine = {
		current = def.initial,
		previous = nil,
		timeInState = 0,
		states = def.states,
		transitions = def.transitions or {},
	}
	local enter = def.states[def.initial].enter
	if enter then
		enter(ctx, machine)
	end
	return machine
end

-- Changes state immediately, running exit and enter hooks. Returns false for unknown states.
function NPC.setState(machine: Machine, name: string, ctx: any?): boolean
	local target = machine.states[name]
	if target == nil then
		return false
	end
	local exit = machine.states[machine.current].exit
	if exit then
		exit(ctx, machine)
	end
	machine.previous = machine.current
	machine.current = name
	machine.timeInState = 0
	if target.enter then
		target.enter(ctx, machine)
	end
	return true
end

-- Takes the first transition (in order) whose `from` matches and whose `when` passes,
-- then runs the current state's update. Returns whether the state changed.
function NPC.stepMachine(machine: Machine, ctx: any, dt: number): boolean
	local changed = false
	for _, transition in machine.transitions do
		local matches = transition.from == machine.current or transition.from == "*"
		if matches and transition.to ~= machine.current and transition.when(ctx, machine) then
			NPC.setState(machine, transition.to, ctx)
			changed = true
			break
		end
	end
	machine.timeInState += dt
	local update = machine.states[machine.current].update
	if update then
		update(ctx, machine, dt)
	end
	return changed
end

-- Behaviour tree -----------------------------------------------------------------------------------

local function composite(kind: string, children: { BTNode }, memory: boolean?): BTNode
	assert(type(children) == "table" and #children > 0, kind .. " needs children")
	return { kind = kind, children = children, memory = memory ~= false, running = nil }
end

-- Runs children in order until one fails. Pass memory = false to re-check earlier children every tick.
function NPC.sequence(children: { BTNode }, memory: boolean?): BTNode
	return composite("sequence", children, memory)
end

-- Runs children in order until one succeeds.
function NPC.selector(children: { BTNode }, memory: boolean?): BTNode
	return composite("selector", children, memory)
end

-- Succeeds when `fn(ctx)` returns true.
function NPC.condition(fn: (ctx: any) -> boolean): BTNode
	return { kind = "condition", fn = fn, memory = false }
end

-- `fn(ctx)` returns "success", "failure" or "running". Anything else counts as failure.
function NPC.action(fn: (ctx: any) -> Status): BTNode
	return { kind = "action", fn = fn, memory = false }
end

function NPC.invert(child: BTNode): BTNode
	return { kind = "invert", child = child, memory = false }
end

-- Turns failure into success; running stays running.
function NPC.succeed(child: BTNode): BTNode
	return { kind = "succeed", child = child, memory = false }
end

-- Clears remembered running children in the whole tree.
function NPC.reset(node: BTNode)
	node.running = nil
	if node.children then
		for _, child in node.children do
			NPC.reset(child)
		end
	end
	if node.child then
		NPC.reset(node.child)
	end
end

local function asStatus(value: any): Status
	if value == "success" or value == "running" then
		return value
	end
	return "failure"
end

function NPC.tick(node: BTNode, ctx: any): Status
	local kind = node.kind
	if kind == "condition" or kind == "action" then
		local fn = node.fn
		if fn == nil then
			return "failure"
		end
		local result = fn(ctx)
		if kind ~= "condition" then
			return asStatus(result)
		elseif result == true then
			return "success"
		end
		return "failure"
	elseif kind == "invert" or kind == "succeed" then
		local child = node.child
		if child == nil then
			return "failure"
		end
		local status = NPC.tick(child, ctx)
		if status == "running" then
			return "running"
		elseif kind == "succeed" or status == "failure" then
			return "success"
		end
		return "failure"
	end
	local children = node.children or {}
	-- In a sequence, "failure" stops the run; in a selector, "success" does.
	local stopOn: Status = "success"
	if kind == "sequence" then
		stopOn = "failure"
	end
	local running = node.running
	local start = if node.memory and running then running else 1
	for index = start, #children do
		local status = NPC.tick(children[index], ctx)
		if status == "running" then
			node.running = index
			return "running"
		end
		if status == stopOn then
			node.running = nil
			return stopOn
		end
	end
	node.running = nil
	if kind == "sequence" then
		return "success"
	end
	return "failure"
end

-- Perception ---------------------------------------------------------------------------------------

function NPC.inRange(origin: Vec3, target: Vec3, range: number, flat: boolean?): boolean
	return NPC.distance(origin, target, flat) <= range
end

-- Angle in degrees between `facing` and the direction to `target`. 0 when the target is at the origin.
function NPC.angleTo(origin: Vec3, facing: Vec3, target: Vec3, flat: boolean?): number
	local toTarget = sub(target, origin, flat)
	local direction: Vec3 = if flat then { x = facing.x, y = 0, z = facing.z } else facing
	local a, b = length(direction), length(toTarget)
	if a == 0 or b == 0 then
		return 0
	end
	local dot = (direction.x * toTarget.x + direction.y * toTarget.y + direction.z * toTarget.z) / (a * b)
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

-- True when `target` is inside a cone of `fov` degrees (total width) around `facing`.
function NPC.inViewCone(origin: Vec3, facing: Vec3, target: Vec3, fov: number, flat: boolean?): boolean
	return NPC.angleTo(origin, facing, target, flat) <= fov / 2
end

-- "seen" when in sight range and view cone, "heard" when only inside hearing range, otherwise nil.
-- Line of sight (walls) is not checked here; the server adapter raycasts for that.
function NPC.perceive(origin: Vec3, facing: Vec3, target: Vec3, options: PerceptionOptions): string?
	local distance = NPC.distance(origin, target, options.flat)
	if distance <= options.sightRange and NPC.inViewCone(origin, facing, target, options.fov, options.flat) then
		return "seen"
	end
	local hearing = options.hearingRange
	if hearing and distance <= hearing then
		return "heard"
	end
	return nil
end

-- Patrol routes ------------------------------------------------------------------------------------

-- `mode` is "loop" (1, 2, 3, 1, ...), "pingpong" (1, 2, 3, 2, 1, ...) or "once" (stops at the end).
function NPC.newPatrol(points: { Vec3 }, mode: string?): Patrol
	assert(type(points) == "table" and #points > 0, "patrol needs at least one point")
	local chosen = mode or "loop"
	assert(chosen == "loop" or chosen == "pingpong" or chosen == "once", "unknown patrol mode")
	return { points = points, index = 1, direction = 1, mode = chosen, finished = false }
end

function NPC.currentWaypoint(patrol: Patrol): Vec3?
	if patrol.finished then
		return nil
	end
	return patrol.points[patrol.index]
end

-- Moves to the next point and returns it, or nil when a "once" patrol has finished.
function NPC.advancePatrol(patrol: Patrol): Vec3?
	local count = #patrol.points
	if patrol.finished then
		return nil
	end
	if count == 1 then
		if patrol.mode == "once" then
			patrol.finished = true
			return nil
		end
		return patrol.points[1]
	end
	if patrol.mode == "loop" then
		patrol.index = patrol.index % count + 1
	elseif patrol.mode == "once" then
		if patrol.index >= count then
			patrol.finished = true
			return nil
		end
		patrol.index += 1
	else
		local nextIndex = patrol.index + patrol.direction
		if nextIndex > count or nextIndex < 1 then
			patrol.direction = -patrol.direction
			nextIndex = patrol.index + patrol.direction
		end
		patrol.index = nextIndex
	end
	return patrol.points[patrol.index]
end

function NPC.reached(position: Vec3, target: Vec3, tolerance: number, flat: boolean?): boolean
	return NPC.distance(position, target, flat) <= tolerance
end

-- Stuck detection ----------------------------------------------------------------------------------

-- Reports "stuck" when the position stays within `minDistance` of where it was for `window` seconds.
function NPC.newStuckDetector(window: number, minDistance: number): StuckDetector
	assert(window > 0 and minDistance > 0, "window and minDistance must be positive")
	return { window = window, minDistance = minDistance, anchor = nil, anchorTime = 0 }
end

function NPC.resetStuck(detector: StuckDetector, position: Vec3?, now: number)
	detector.anchor = position
	detector.anchorTime = now
end

function NPC.updateStuck(detector: StuckDetector, position: Vec3, now: number): boolean
	local anchor = detector.anchor
	if anchor == nil or NPC.distance(anchor, position) >= detector.minDistance then
		NPC.resetStuck(detector, position, now)
		return false
	end
	return now - detector.anchorTime >= detector.window
end

-- Re-path when the goal moved more than `threshold` since the last path, at most every `minInterval` seconds.
function NPC.shouldRepath(
	lastGoal: Vec3?,
	goal: Vec3,
	lastPathTime: number,
	now: number,
	threshold: number,
	minInterval: number
): boolean
	if lastGoal == nil then
		return true
	end
	if now - lastPathTime < minInterval then
		return false
	end
	return NPC.distance(lastGoal, goal) > threshold
end

return NPC
