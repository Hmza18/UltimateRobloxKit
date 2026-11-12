-- A cast member: rig + clip player + root travel + held props.
--
-- Travel moves the HumanoidRootPart along waypoints at exactly the ground speed the walk clips were
-- authored for (Configuration.WalkSpeed), ramping speed and clip rate together so the planted foot
-- never skates, and turning smoothly toward each next waypoint.

local ClipPlayer = require(script.Parent.ClipPlayer)
local Easing = require(script.Parent.Easing)

local Actor = {}
Actor.__index = Actor

local ACCEL = 0.3 -- seconds to reach full speed / to stop
local TURN_RATE = 8 -- yaw smoothing (1/s)

function Actor.new(name, model, definitions, config, events)
	local self = setmetatable({}, Actor)
	self.name = name
	self.model = model
	self.root = model:FindFirstChild("HumanoidRootPart")
	self.player = ClipPlayer.new(model, definitions, config)
	self.config = config
	self.events = events -- { onMarker = fn(actor, marker) }
	self.held = {}
	self.move = nil
	return self
end

function Actor:pivot()
	return self.root.CFrame
end

function Actor:place(cf)
	self.root.CFrame = cf
	self.move = nil
end

function Actor:play(clip, opts)
	opts = opts or {}
	local userMarker = opts.onMarker
	opts.onMarker = function(marker)
		if self.events and self.events.onMarker then
			self.events.onMarker(self, marker)
		end
		if userMarker then
			userMarker(marker)
		end
	end
	return self.player:play(clip, opts)
end

-- Walk through waypoints (Vector3, floor height ignored: the root keeps its height).
-- opts: { clip = "SM_Walk", arrive = "SM_Idle", face = Vector3 direction at the end, done = fn }
function Actor:walk(points, opts)
	opts = opts or {}
	local y = self.root.Position.Y
	local path = {}
	for i, p in ipairs(points) do
		path[i] = Vector3.new(p.X, y, p.Z)
	end
	local total = 0
	local from = self.root.Position
	for _, p in ipairs(path) do
		total = total + (p - from).Magnitude
		from = p
	end
	-- arriveBy: scale ground speed (and the clip rate with it, so feet stay matched) to hit a time
	local scale = 1
	if opts.arriveBy then
		local cruise = math.max(opts.arriveBy - ACCEL * 0.75, 0.3)
		scale = math.clamp(total / cruise / self.config.WalkSpeed, 0.7, 1.7)
	end
	self.move = {
		scale = scale,
		path = path,
		index = 1,
		travelled = 0,
		total = total,
		speed = 0,
		clip = opts.clip or "SM_Walk",
		arrive = opts.arrive,
		face = opts.face,
		done = opts.done,
	}
	self:play(self.move.clip, { fade = 0.25, speed = 0 })
	return total / (self.config.WalkSpeed * scale) + ACCEL -- approximate duration (seconds)
end

-- Turn in place to face a direction over `duration` seconds.
function Actor:turnTo(direction, duration)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	self.turn = { from = self.root.CFrame, to = CFrame.lookAt(self.root.Position, self.root.Position + flat.Unit), t = 0, d = duration or 0.4 }
end

function Actor:_updateMove(dt)
	local m = self.move
	local base = self.config.WalkSpeed
	local full = base * (m.scale or 1)
	local left = m.total - m.travelled
	-- ease in at the start, ease out over the last ACCEL * full / 2 studs
	local stopDist = full * ACCEL * 0.5
	local target = full
	if left < stopDist then
		target = full * math.max(0.15, left / stopDist)
	end
	m.speed = m.speed + (target - m.speed) * math.min(1, dt / (ACCEL * 0.5))
	self.player:setSpeed(m.speed / base)
	local step = m.speed * dt
	local pos = self.root.Position
	while step > 0 and m.index <= #m.path do
		local goal = m.path[m.index]
		local d = (goal - pos).Magnitude
		if d <= step then
			pos = goal
			step = step - d
			m.travelled = m.travelled + d
			m.index = m.index + 1
		else
			pos = pos + (goal - pos).Unit * step
			m.travelled = m.travelled + step
			step = 0
		end
	end
	local look = self.root.CFrame.LookVector
	local goal = m.path[math.min(m.index, #m.path)]
	local dir = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	if dir.Magnitude > 0.05 then
		look = look:Lerp(dir.Unit, Easing.damp(TURN_RATE, dt))
	end
	if look.Magnitude < 1e-3 then
		look = self.root.CFrame.LookVector
	end
	self.root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
	if m.index > #m.path then
		self.move = nil
		self.player:setSpeed(1)
		if m.face then
			self:turnTo(m.face, 0.45)
		end
		if m.arrive then
			self:play(m.arrive, { fade = 0.3 })
		end
		if m.done then
			task.defer(m.done)
		end
	end
end

function Actor:update(dt)
	if self.move then
		self:_updateMove(dt)
	end
	if self.turn then
		local t = self.turn
		t.t = t.t + dt
		local u = Easing.apply("inOutSine", t.t / t.d)
		self.root.CFrame = t.from:Lerp(t.to, u)
		if t.t >= t.d then
			self.turn = nil
		end
	end
	self.player:update(dt)
end

-- Holds a prop in a hand (or any part): the prop is welded with `offset` (part space). With
-- keepWorld = true the current world placement is kept instead (grabbing a box where it is).
function Actor:hold(prop, partName, offset, keepWorld)
	local part = self.model:FindFirstChild(partName)
	if not part or not prop then
		return nil
	end
	self:release(prop)
	local primary = prop:IsA("Model") and prop.PrimaryPart or prop
	if keepWorld then
		offset = part.CFrame:ToObjectSpace(primary.CFrame)
	end
	for _, d in ipairs(prop:IsA("Model") and prop:GetDescendants() or { prop }) do
		if d:IsA("BasePart") then
			d.Anchored = false -- every part is welded to the primary (Products.prepare)
			d.Massless = true
			d.CanCollide = false
		end
	end
	primary.Anchored = false
	local weld = Instance.new("Weld")
	weld.Name = "CinematicHold"
	weld.Part0 = part
	weld.Part1 = primary
	weld.C0 = offset
	weld.Parent = primary
	self.held[prop] = weld
	return weld
end

-- Lets go: the prop stays where it is (anchored) and is returned for the caller to tween.
function Actor:release(prop)
	local weld = self.held[prop]
	if weld then
		local primary = prop:IsA("Model") and prop.PrimaryPart or prop
		local cf = primary.CFrame
		weld:Destroy()
		primary.Anchored = true
		primary.CFrame = cf
		self.held[prop] = nil
	end
	return prop
end

function Actor:part(name)
	return self.model:FindFirstChild(name)
end

function Actor:destroy()
	self.player:destroy()
	for prop in pairs(self.held) do
		self:release(prop)
	end
	self.model:Destroy()
end

return Actor
