-- Shot-based cinematic camera.
--
-- A shot = { name, t0, t1, ease, keys = { { u, pos, look, fov, roll }, ... }, track, shake, blend }
--   keys: positions in set-local studs ({x, y, z}), or in an actor's space with `rel = "Actor"`;
--         sampled with a Catmull-Rom spline over the shot's eased progress (smooth, no corners).
--   track: { actor, part, offset = {x,y,z}, weight = 0..1, rate = 6 } keeps a subject in frame by
--          pulling the look target toward it with frame-rate independent smoothing.
--   shake: { amp = studs, rot = degrees, freq = Hz } (disabled with reduced motion).
--   blend: seconds to blend from the previous shot (0 / nil = a cut).
-- The director only computes CFrame + FieldOfView; the cinematic writes them to the camera.

local Easing = require(script.Parent.Easing)

local CameraDirector = {}
CameraDirector.__index = CameraDirector

-- Catmull-Rom between p1 and p2 (p0/p3 neighbours), t in 0..1. Works on Vector3 or numbers.
function CameraDirector.catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return ((p1 * 2) + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Value along keys (sorted by u) at progress u, using `get(key)` for the value.
function CameraDirector.sample(keys, u, get)
	local n = #keys
	if n == 1 or u <= keys[1].u then
		return get(keys[1])
	end
	if u >= keys[n].u then
		return get(keys[n])
	end
	local i = 1
	while i < n - 1 and keys[i + 1].u <= u do
		i = i + 1
	end
	local a, b = keys[i], keys[i + 1]
	local t = (u - a.u) / math.max(b.u - a.u, 1e-6)
	local p0 = get(keys[math.max(1, i - 1)])
	local p3 = get(keys[math.min(n, i + 2)])
	return CameraDirector.catmull(p0, get(a), get(b), p3, t)
end

function CameraDirector.new(shots, ctx)
	local self = setmetatable({}, CameraDirector)
	table.sort(shots, function(a, b)
		return a.t0 < b.t0
	end)
	self.shots = shots
	self.ctx = ctx
	self.index = 0
	self.lookState = nil
	self.lastCF = nil
	self.lastFov = 50
	self.blendFrom = nil
	return self
end

function CameraDirector:_point(key, field)
	local v = key[field]
	local vec = Vector3.new(v[1], v[2], v[3])
	if key.rel then
		local actor = self.ctx.actors[key.rel]
		if actor then
			local root = actor:pivot()
			local flat = CFrame.lookAt(root.Position, root.Position + Vector3.new(root.LookVector.X, 0, root.LookVector.Z))
			return flat * vec
		end
	end
	return self.ctx.set.origin * vec
end

function CameraDirector:shotAt(t)
	local shots = self.shots
	local found, index = nil, 0
	for i, s in ipairs(shots) do
		if t >= s.t0 and t < s.t1 then
			found, index = s, i
		end
	end
	if not found and #shots > 0 and t >= shots[#shots].t1 then
		found, index = shots[#shots], #shots
	end
	return found, index
end

-- Returns camera CFrame, field of view and the active shot for cinematic time t.
function CameraDirector:evaluate(t, dt)
	local shot, index = self:shotAt(t)
	if not shot then
		return self.lastCF, self.lastFov, nil
	end
	if index ~= self.index then
		self.index = index
		self.lookState = nil
		self.blendFrom = (shot.blend and shot.blend > 0 and self.lastCF) and { cf = self.lastCF, fov = self.lastFov } or nil
	end
	local span = math.max(shot.t1 - shot.t0, 1e-3)
	local u = Easing.apply(shot.ease or "inOutSine", (t - shot.t0) / span)
	local keys = shot.keys
	local pos = CameraDirector.sample(keys, u, function(k)
		return self:_point(k, "pos")
	end)
	local look = CameraDirector.sample(keys, u, function(k)
		return self:_point(k, "look")
	end)
	local fov = CameraDirector.sample(keys, u, function(k)
		return k.fov or 50
	end)
	local roll = CameraDirector.sample(keys, u, function(k)
		return k.roll or 0
	end)
	local tr = shot.track
	if tr then
		local actor = self.ctx.actors[tr.actor]
		local target = nil
		if actor then
			local part = actor:part(tr.part or "Head")
			if part then
				local o = tr.offset or { 0, 0, 0 }
				target = part.Position + Vector3.new(o[1], o[2], o[3])
			end
		elseif tr.prop and self.ctx.props[tr.prop] then
			local p = self.ctx.props[tr.prop]
			target = (p:IsA("Model") and p:GetPivot() or p.CFrame).Position
		end
		if target then
			local want = look:Lerp(target, tr.weight or 1)
			if not self.lookState then
				self.lookState = want
			else
				self.lookState = self.lookState:Lerp(want, Easing.damp(tr.rate or 6, dt or 1 / 60))
			end
			look = self.lookState
		end
	end
	local cf = CFrame.lookAt(pos, look) * CFrame.Angles(0, 0, math.rad(roll))
	local sh = shot.shake
	if sh and not self.ctx.reducedMotion then
		local f = sh.freq or 1.2
		local nx = math.noise(t * f, 0.3, 1.7)
		local ny = math.noise(0.9, t * f, 4.1)
		local nr = math.noise(2.2, 5.3, t * f)
		cf = cf * CFrame.new(nx * (sh.amp or 0), ny * (sh.amp or 0), 0) * CFrame.Angles(0, 0, math.rad(nr * (sh.rot or 0)))
	end
	if self.blendFrom then
		local w = (t - shot.t0) / shot.blend
		if w >= 1 then
			self.blendFrom = nil
		else
			w = Easing.inOutSine(math.max(0, w))
			cf = self.blendFrom.cf:Lerp(cf, w)
			fov = self.blendFrom.fov + (fov - self.blendFrom.fov) * w
		end
	end
	fov = math.clamp(fov, 20, 80)
	self.lastCF, self.lastFov = cf, fov
	return cf, fov, shot
end

return CameraDirector
