-- Plays the cast's keyframe clips on an R15 rig.
--
-- Two backends, same clips:
--   * "track": the clip has an uploaded asset ID in Configuration.AnimationIds -> a real AnimationTrack
--     on the rig's Animator (markers via GetMarkerReachedSignal).
--   * "pose" (default, works unpublished): the exported keyframes are sampled every frame and written
--     to each joint's Transform (Motor6D or AnimationConstraint - both expose Transform), exactly as the
--     Animator would apply a Linear-eased KeyframeSequence.
-- Switching clips cross-fades from a snapshot of the current pose, so nothing ever pops.

local ClipPlayer = {}
ClipPlayer.__index = ClipPlayer

local cache = {}

-- Pure helper: index i and alpha so the value at time t lies between key i and i + 1.
function ClipPlayer.locate(times, t)
	local n = #times
	if n == 0 then
		return 0, 0
	end
	if t <= times[1] then
		return 1, 0
	end
	if t >= times[n] then
		return n, 0
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = times[hi] - times[lo]
	if span <= 0 then
		return lo, 0
	end
	return lo, (t - times[lo]) / span
end

-- Pure helper: marker names crossed moving the playhead from a to b in a clip of `length`
-- (handles one loop wrap). Markers exactly at `a` were already fired last frame.
function ClipPlayer.crossed(markers, a, b, length, looped)
	local out = {}
	if looped then
		-- the end of this pass first, then the start of the next: time order
		for _, m in ipairs(markers) do
			if m.t > a and m.t <= length then
				out[#out + 1] = m.name
			end
		end
		for _, m in ipairs(markers) do
			if m.t >= 0 and m.t <= b then
				out[#out + 1] = m.name
			end
		end
		return out
	end
	for _, m in ipairs(markers) do
		if m.t > a and m.t <= b then
			out[#out + 1] = m.name
		end
	end
	if a == 0 and not looped then
		for _, m in ipairs(markers) do
			if m.t == 0 then
				table.insert(out, 1, m.name)
			end
		end
	end
	return out
end

-- Builds (once) CFrame arrays from a clip data module.
function ClipPlayer.load(definitions, name)
	if cache[name] then
		return cache[name]
	end
	local data = definitions.Clips[name]
	assert(data, "unknown clip " .. tostring(name))
	local joints = {}
	for joint, track in pairs(data.tracks) do
		local cfs, q, p = {}, track.q, track.p
		for i = 1, #track.t do
			local k = (i - 1) * 4
			local x, y, z = 0, 0, 0
			if p then
				local j = (i - 1) * 3
				x, y, z = p[j + 1], p[j + 2], p[j + 3]
			end
			cfs[i] = CFrame.new(x, y, z, q[k + 1], q[k + 2], q[k + 3], q[k + 4])
		end
		joints[joint] = { times = track.t, cfs = cfs }
	end
	local clip = { name = name, length = data.length, loop = data.loop, markers = data.markers, joints = joints }
	cache[name] = clip
	return clip
end

local function findJoints(model)
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 then
			joints[d.Part1.Name] = d
		elseif d:IsA("AnimationConstraint") and d.Attachment1 and d.Attachment1.Parent then
			joints[d.Attachment1.Parent.Name] = d
		end
	end
	return joints
end

function ClipPlayer.new(model, definitions, config)
	local self = setmetatable({}, ClipPlayer)
	self.model = model
	self.definitions = definitions
	self.config = config
	self.joints = findJoints(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	self.animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	self.current = nil
	self.time = 0
	self.speed = 1
	self.fade = 0
	self.fadeTime = 0
	self.snapshot = {}
	self.tracks = {}
	self.connections = {}
	return self
end

function ClipPlayer:_assetId(name)
	local ids = self.config and self.config.AnimationIds
	local id = ids and ids[name]
	if id and id ~= "" and self.animator then
		return id
	end
	return nil
end

-- opts: { fade = 0.2, speed = 1, start = 0, onMarker = fn(name), onEnd = fn() }
function ClipPlayer:play(name, opts)
	opts = opts or {}
	local clip = ClipPlayer.load(self.definitions, name)
	-- snapshot the pose we are leaving, for the cross-fade
	for jointName, joint in pairs(self.joints) do
		self.snapshot[jointName] = joint.Transform
	end
	self:_stopTrack(opts.fade or 0.2)
	self.current = clip
	self.time = opts.start or 0
	self.speed = opts.speed or 1
	self.fadeTime = opts.fade or 0.2
	self.fade = self.fadeTime > 0 and 0 or 1
	self.onMarker = opts.onMarker
	self.onEnd = opts.onEnd
	self.ended = false
	self.backend = "pose"
	local id = self:_assetId(name)
	if id then
		local ok, track = pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			return self.animator:LoadAnimation(anim)
		end)
		if ok and track then
			self.backend = "track"
			self.track = track
			track.Looped = clip.loop
			for _, m in ipairs(clip.markers) do
				if not self.connections[m.name] then
					self.connections[m.name] = track:GetMarkerReachedSignal(m.name):Connect(function()
						if self.track == track and self.onMarker then
							self.onMarker(m.name)
						end
					end)
				end
			end
			track:Play(self.fadeTime, 1, self.speed)
		else
			warn("[SupermarketCinematic] could not load AnimationId for " .. name .. ": using the pose player")
		end
	end
	if self.backend == "pose" and self.time == 0 and self.onMarker then
		for _, m in ipairs(ClipPlayer.crossed(clip.markers, 0, 0, clip.length, false)) do
			self.onMarker(m)
		end
	end
	return clip
end

function ClipPlayer:_stopTrack(fade)
	if self.track then
		pcall(function()
			self.track:Stop(fade)
		end)
		self.track = nil
	end
	for key, c in pairs(self.connections) do
		c:Disconnect()
		self.connections[key] = nil
	end
end

function ClipPlayer:setSpeed(speed)
	self.speed = speed
	if self.track then
		self.track:AdjustSpeed(speed)
	end
end

function ClipPlayer:isPlaying(name)
	return self.current ~= nil and self.current.name == name and not self.ended
end

-- Seconds left in a one-shot clip (0 for loops or nothing playing).
function ClipPlayer:remaining()
	local c = self.current
	if not c or c.loop then
		return 0
	end
	return math.max(0, (c.length - self.time) / math.max(self.speed, 1e-3))
end

function ClipPlayer:update(dt)
	local clip = self.current
	if not clip then
		return
	end
	local before = self.time
	local after = before + dt * self.speed
	local looped = false
	if clip.loop then
		if after >= clip.length then
			after = after % clip.length
			looped = true
		end
	elseif after >= clip.length then
		after = clip.length
	end
	self.time = after
	if self.backend == "pose" and self.onMarker and after ~= before then
		for _, name in ipairs(ClipPlayer.crossed(clip.markers, before, after, clip.length, looped)) do
			self.onMarker(name)
		end
	end
	if not clip.loop and after >= clip.length and not self.ended then
		self.ended = true
		local onEnd = self.onEnd
		if onEnd then
			task.defer(function()
				-- only if nothing else started meanwhile and the player was not destroyed
				if self.current == clip and self.onEnd == onEnd then
					onEnd()
				end
			end)
		end
	end
	if self.backend ~= "pose" then
		return
	end
	if self.fade < 1 then
		self.fade = math.min(1, self.fade + dt / math.max(self.fadeTime, 1e-3))
	end
	local w = self.fade
	w = w * w * (3 - 2 * w)
	for jointName, joint in pairs(self.joints) do
		local track = clip.joints[jointName]
		if track then
			local i, a = ClipPlayer.locate(track.times, after)
			local cf = track.cfs[i]
			if a > 0 then
				cf = cf:Lerp(track.cfs[i + 1], a)
			end
			if w < 1 then
				cf = (self.snapshot[jointName] or CFrame.identity):Lerp(cf, w)
			end
			joint.Transform = cf
		end
	end
end

function ClipPlayer:destroy()
	self:_stopTrack(0)
	self.current = nil
	self.onEnd = nil
	self.onMarker = nil
end

return ClipPlayer
