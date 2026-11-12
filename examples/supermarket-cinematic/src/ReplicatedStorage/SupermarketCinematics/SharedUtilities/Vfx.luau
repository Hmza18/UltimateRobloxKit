-- Cinematic effects: pooled particle bursts, sign glow, scanner pulse, product drop-in, money popup and
-- a temporary lighting grade. All motion runs on the cinematic Tweener (pause/skip safe); every
-- instance lives under the cinematic folder or is tracked for restore.

local Lighting = game:GetService("Lighting")

local Vfx = {}
Vfx.__index = Vfx

local function seq(colors)
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in ipairs(colors) do
		keys[i] = ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c)
	end
	return ColorSequence.new(keys)
end

function Vfx.new(folder, tweener, defs, opts)
	local self = setmetatable({}, Vfx)
	self.folder = folder
	self.tweener = tweener
	self.defs = defs
	self.budget = opts.budget or 1
	self.reducedMotion = opts.reducedMotion
	self.emitters = {}
	self.saved = nil
	self.created = {}
	-- one emitter part per effect kind, moved where needed (reused, never re-created)
	self.sparkle = self:_emitterPart("SparkleEmitter", function(e)
		local d = defs.Sparkle
		e.Color = seq(d.colors)
		e.Lifetime = d.lifetime
		e.Speed = d.speed
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(d.size[1], d.size[2])
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.LightEmission = 1
		e.Drag = 6
		e.RotSpeed = NumberRange.new(-180, 180)
		e.Rotation = NumberRange.new(0, 360)
	end)
	self.confetti = {}
	for i, c in ipairs(defs.Confetti.colors) do
		self.confetti[i] = self:_emitterPart("Confetti" .. i, function(e)
			local d = defs.Confetti
			e.Color = ColorSequence.new(c)
			e.Lifetime = d.lifetime
			e.Speed = d.speed
			e.SpreadAngle = Vector2.new(28, 28)
			e.Size = NumberSequence.new(d.size[1], d.size[2])
			e.Acceleration = d.gravity
			e.Drag = 1.6
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-360, 360)
			e.LightInfluence = 0.4
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) })
		end)
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "CinematicHighlight"
	highlight.FillColor = defs.ProductDrop.highlight
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder
	self.highlight = highlight
	return self
end

function Vfx:_emitterPart(name, setup)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Enabled = true
	setup(e)
	e.Parent = p
	p.Parent = self.folder
	self.emitters[#self.emitters + 1] = e
	return p
end

function Vfx:_emit(p, cf, count)
	p.CFrame = cf
	local n = math.max(1, math.floor(count * self.budget + 0.5))
	p:FindFirstChildOfClass("ParticleEmitter"):Emit(n)
end

function Vfx:sparkleAt(pos, count, color)
	local e = self.sparkle:FindFirstChildOfClass("ParticleEmitter")
	if color then
		e.Color = ColorSequence.new(color)
	else
		e.Color = seq(self.defs.Sparkle.colors)
	end
	self:_emit(self.sparkle, CFrame.new(pos), count or self.defs.Sparkle.count)
end

-- Celebratory burst shooting up (cf's UpVector) from cf.
function Vfx:confettiAt(cf, scale)
	if self.reducedMotion then
		scale = (scale or 1) * 0.5
	end
	for _, p in ipairs(self.confetti) do
		self:_emit(p, cf * CFrame.Angles(math.rad(-90), 0, 0), self.defs.Confetti.count * (scale or 1))
	end
end

function Vfx:setPaused(paused)
	for _, e in ipairs(self.emitters) do
		e.TimeScale = paused and 0 or 1
	end
end

-- The store sign lights up: label brightens and stops taking scene lighting, the board light ramps up.
function Vfx:signGlow(set, duration)
	local label, light = set.parts.signLabel, set.parts.signLight
	local gui = label.Parent
	local from, to = label.TextColor3, Color3.fromRGB(255, 255, 255)
	self.tweener:play({ from = 0, to = 1, duration = duration or 0.6, ease = "outCubic", set = function(u)
		label.TextColor3 = from:Lerp(to, u)
		gui.LightInfluence = 1 - u
		light.Brightness = 3 * u
	end })
	local sign = set.parts.sign
	for i = 0, 5 do
		local x = -9 + i * 3.6
		self.tweener:play({ from = 0, to = 1, duration = 0.01, delay = i * 0.06, set = function() end, done = function()
			self:sparkleAt((sign.CFrame * CFrame.new(x, 0, -0.6)).Position, 6)
		end })
	end
end

function Vfx:scannerPulse(set)
	local d = self.defs.ScanPulse
	local glass, light = set.parts.scanner, set.parts.scanLight
	local base = glass.Color
	glass.Material = Enum.Material.Neon
	self.tweener:play({ from = 1, to = 0, duration = d.duration, ease = "outQuad", set = function(u)
		glass.Color = base:Lerp(d.color, u)
		light.Brightness = d.lightBrightness * u
	end, done = function()
		glass.Material = Enum.Material.Glass
		glass.Color = base
	end })
	self:sparkleAt(glass.Position + Vector3.new(0, 0.4, 0), 8, d.color)
end

-- Product drops into its slot from just above with a soft overshoot, a flash and sparkles.
function Vfx:dropIn(primary, slotCF, delay, onLand)
	local d = self.defs.ProductDrop
	local start = slotCF * CFrame.new(0, d.height, 0) * CFrame.Angles(0, math.rad(12), math.rad(-6))
	primary.CFrame = start
	self.tweener:play({ from = start, to = slotCF, duration = d.duration, ease = "outBackSoft", delay = delay or 0, set = function(cf)
		primary.CFrame = cf
	end, done = function()
		self:flash(primary.Parent:IsA("Model") and primary.Parent or primary)
		self:sparkleAt(slotCF.Position + Vector3.new(0, 0.3, -0.3), 7)
		if onLand then
			onLand()
		end
	end })
end

-- Brief highlight on an instance (one shared Highlight; the newest flash wins).
function Vfx:flash(adornee)
	local h = self.highlight
	h.Adornee = adornee
	self.tweener:play({ from = 0, to = 1, duration = 0.45, ease = "outQuad", set = function(u)
		h.FillTransparency = 0.45 + 0.55 * u
		h.OutlineTransparency = 0.2 + 0.8 * u
	end })
end

-- Floating earnings text at a world position (illustrative cinematic UI only).
function Vfx:moneyPopup(pos, text, font)
	local d = self.defs.Money
	local anchor = Instance.new("Part")
	anchor.Name = "MoneyAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = self.folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4.5, 1.6)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 200
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = d.color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = d.stroke
	stroke.Parent = label
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 200), Color3.fromRGB(120, 255, 120))
	grad.Rotation = 90
	grad.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = label
	label.Parent = bb
	self.tweener:play({ from = 0, to = 1, duration = 0.32, ease = "outBack", set = function(u)
		scale.Scale = u
	end })
	self.tweener:play({ from = 0, to = d.rise, duration = d.duration, ease = "outCubic", set = function(y)
		bb.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
	end })
	self.tweener:play({ from = 0, to = 1, duration = 0.3, delay = d.duration - 0.3, ease = "inQuad", set = function(u)
		label.TextTransparency = u
		stroke.Transparency = u
	end, done = function()
		anchor:Destroy()
	end })
	return anchor
end

-- Temporary lighting: saves every property it touches and restores them exactly.
function Vfx:applyGrade()
	local g = self.defs.Grade
	local saved = { props = {}, atmosphere = nil }
	for _, k in ipairs({ "ClockTime", "GeographicLatitude", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }) do
		local ok, v = pcall(function()
			return Lighting[k]
		end)
		if ok then
			saved.props[k] = v
			pcall(function()
				Lighting[k] = g[k]
			end)
		end
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		saved.atmosphere = { instance = atm, values = {} }
		for k, v in pairs(g.atmosphere) do
			saved.atmosphere.values[k] = atm[k]
			atm[k] = v
		end
	else
		atm = Instance.new("Atmosphere")
		for k, v in pairs(g.atmosphere) do
			atm[k] = v
		end
		atm.Name = "SupermarketCinematicAtmosphere"
		atm.Parent = Lighting
		self.created[#self.created + 1] = atm
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SupermarketCinematicBloom"
	for k, v in pairs(g.bloom) do
		bloom[k] = v
	end
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SupermarketCinematicGrade"
	for k, v in pairs(g.color) do
		cc[k] = v
	end
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "SupermarketCinematicSunRays"
	for k, v in pairs(g.sunRays) do
		rays[k] = v
	end
	rays.Parent = Lighting
	self.created[#self.created + 1] = bloom
	self.created[#self.created + 1] = cc
	self.created[#self.created + 1] = rays
	self.bloom, self.cc = bloom, cc
	self.saved = saved
end

function Vfx:reveal()
	local r, g = self.defs.Reveal, self.defs.Grade
	local bloom, cc = self.bloom, self.cc
	if not bloom then
		return
	end
	self.tweener:play({ from = 0, to = 1, duration = r.duration, ease = "inOutSine", set = function(u)
		bloom.Intensity = g.bloom.Intensity + (r.bloom - g.bloom.Intensity) * u
		cc.Saturation = g.color.Saturation + (r.saturation - g.color.Saturation) * u
		pcall(function()
			Lighting.ExposureCompensation = g.ExposureCompensation + (r.exposure - g.ExposureCompensation) * u
		end)
	end })
end

function Vfx:restoreGrade()
	local saved = self.saved
	self.saved = nil
	if saved then
		for k, v in pairs(saved.props) do
			pcall(function()
				Lighting[k] = v
			end)
		end
		if saved.atmosphere then
			for k, v in pairs(saved.atmosphere.values) do
				pcall(function()
					saved.atmosphere.instance[k] = v
				end)
			end
		end
	end
	for _, inst in ipairs(self.created) do
		pcall(function()
			inst:Destroy()
		end)
	end
	self.created = {}
	self.bloom, self.cc = nil, nil
end

function Vfx:destroy()
	self:restoreGrade()
end

return Vfx
