--!strict
-- Turns resolved effect layers (VFX/EffectLogic) into real Roblox objects: ParticleEmitters, Beams,
-- Trails, lights, Highlights, ring and flash parts, BillboardGuis and post-processing pulses.
-- Everything a build creates is tracked, so destroy() removes all of it, cancels its timers and
-- stops its envelopes; soften() lets a looping effect fade out instead of vanishing.
--
-- NOT run in Studio: this file is checked by StyLua, Selene and luau-lsp against the Roblox type
-- definitions only. See README.md for what needs a playtest.

local Workspace = game:GetService("Workspace")

local EffectLogic = require("./EffectLogic")
local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local Pool = require("../Core/Pool")

type Layer = EffectLogic.Layer

export type Origin = {
	part: BasePart, -- attachments are parented here
	base: CFrame, -- the effect origin in `part` space
	adornee: Instance?, -- what a highlight outlines (nil for a bare position)
	moving: BasePart?, -- the caller's part when the effect follows one
	pooled: boolean, -- `part` is a pooled holder to give back
}

export type Options = {
	lights: number, -- dynamic lights this build may still create
	maxDistance: number,
	shake: ((preset: string, amount: number, position: Vector3) -> ())?,
	sound: ((cue: string, volume: number?, at: Instance) -> ())?,
}

export type Control = {
	destroy: () -> (),
	-- Stops emitting and fades envelopes. Returns the seconds the fade needs.
	soften: () -> number,
	-- A timer that is cancelled when the effect is destroyed.
	after: (seconds: number, callback: () -> ()) -> (),
	-- Something to clean up with the effect (a connection, an instance, a function).
	own: (item: any) -> (),
}

local Builders = {}

-- Roblox renders a limited number of Highlights at once; effects never hold more than this.
Builders.MAX_HIGHLIGHTS = 8

local FOLDER_NAME = "UvkEffects"
local RING_CURVE = 4 / 3 -- cubic Bezier handle length for a half circle of radius 1

local textures: { [string]: string } = {}
local highlights = 0
local postfx: { [string]: boolean } = {}

function Builders.setTextures(map: { [string]: string })
	for key, id in map do
		if type(key) == "string" and type(id) == "string" then
			textures[key] = id
		end
	end
end

function Builders.textures(): { [string]: string }
	return table.clone(textures)
end

function Builders.highlightCount(): number
	return highlights
end

local function folder(): Instance
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	return created
end

local function invisiblePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
	part.Size = Vector3.one
	return part
end

-- Holder parts for effects played at a bare position are reused instead of created per effect.
local holders = Pool.new({
	create = function(): Part
		return invisiblePart("UvkHolder")
	end,
	reset = function(part: Part)
		part:ClearAllChildren()
		part.Parent = nil
	end,
	destroy = function(part: Part)
		part:Destroy()
	end,
	max = 24,
})

function Builders.poolStats(): Pool.Stats
	return holders:stats()
end

local function firstPart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	local found = model:FindFirstChildWhichIsA("BasePart", true)
	return found
end

-- World position of anything play() accepts, or nil when it cannot be placed.
function Builders.position(at: any): Vector3?
	local kind = typeof(at)
	if kind == "Vector3" then
		return at
	elseif kind == "CFrame" then
		return at.Position
	elseif kind == "Instance" then
		if at:IsA("Attachment") then
			return at.WorldPosition
		elseif at:IsA("BasePart") then
			return at.Position
		elseif at:IsA("Model") then
			local part = firstPart(at)
			return if part then part.Position else nil
		end
	end
	return nil
end

-- Where an effect lives. A position or CFrame gets a pooled invisible holder part; a part, an
-- attachment on a part or a model (PrimaryPart, else its first BasePart) is used directly.
function Builders.origin(at: any, parent: Instance?): Origin?
	local kind = typeof(at)
	if kind == "Instance" then
		if at:IsA("BasePart") then
			return { part = at, base = CFrame.identity, adornee = at, moving = at, pooled = false }
		elseif at:IsA("Model") then
			local part = firstPart(at)
			if part == nil then
				return nil
			end
			return { part = part, base = CFrame.identity, adornee = at, moving = part, pooled = false }
		elseif at:IsA("Attachment") then
			local owner = at.Parent
			if owner and owner:IsA("BasePart") then
				return { part = owner, base = at.CFrame, adornee = owner, moving = owner, pooled = false }
			end
			at = at.WorldCFrame
			kind = "CFrame"
		else
			return nil
		end
	end
	local cframe: CFrame
	if kind == "Vector3" then
		cframe = CFrame.new(at)
	elseif kind == "CFrame" then
		cframe = at
	else
		return nil
	end
	local holder = holders:acquire()
	holder.CFrame = cframe
	holder.Parent = parent or folder()
	local origin: Origin = { part = holder, base = CFrame.identity, adornee = nil, moving = nil, pooled = true }
	return origin
end

-- Sequences ---------------------------------------------------------------------------------------

local function numberSequence(stops: { number }): NumberSequence
	local keys: { NumberSequenceKeypoint } = {}
	for _, point in EffectLogic.keypoints(stops) do
		table.insert(keys, NumberSequenceKeypoint.new(point.time, point.value))
	end
	return NumberSequence.new(keys)
end

local function colorSequence(stops: { string }): ColorSequence
	local keys: { ColorSequenceKeypoint } = {}
	for _, point in EffectLogic.keypoints(stops) do
		table.insert(keys, ColorSequenceKeypoint.new(point.time, Color3.fromHex(point.value)))
	end
	return ColorSequence.new(keys)
end

Builders.numberSequence = numberSequence
Builders.colorSequence = colorSequence

local function range(values: { number }?, low: number, high: number): NumberRange
	if values == nil then
		return NumberRange.new(low, high)
	end
	return NumberRange.new(math.min(values[1], values[2]), math.max(values[1], values[2]))
end

local function vector(values: { number }?): Vector3
	if values == nil then
		return Vector3.zero
	end
	return Vector3.new(values[1], values[2], values[3])
end

local function firstColor(layer: Layer): Color3
	local colors = layer.colors
	return Color3.fromHex(if colors and colors[1] then colors[1] else "#FFFFFF")
end

local function lastColor(layer: Layer): Color3
	local colors = layer.colors
	return Color3.fromHex(if colors and #colors > 0 then colors[#colors] else "#FFFFFF")
end

-- The layer's own frame relative to the effect origin: offset, then orient (degrees).
local function layerFrame(layer: Layer): CFrame
	local frame = CFrame.new(vector(layer.offset))
	local orient = layer.orient
	if orient then
		frame *= CFrame.Angles(math.rad(orient[1]), math.rad(orient[2]), math.rad(orient[3]))
	end
	return frame
end

local function enumItem(enum: any, name: string?): any
	if name == nil then
		return nil
	end
	local ok, item = pcall(function(): any
		return enum[name]
	end)
	return if ok then item else nil
end

-- Build ---------------------------------------------------------------------------------------

type Context = {
	origin: Origin,
	options: Options,
	looping: boolean,
	lightsLeft: number,
	made: { Instance },
	owned: { any },
	timers: { () -> () },
	states: { any },
	emitters: { ParticleEmitter },
	trails: { Trail },
	releases: { () -> number },
	destroyed: boolean,
}

local function after(ctx: Context, seconds: number, callback: () -> ())
	if ctx.destroyed then
		return
	end
	if seconds <= 0 then
		callback()
		return
	end
	table.insert(
		ctx.timers,
		Host.clock:after(seconds, function()
			if not ctx.destroyed then
				callback()
			end
		end)
	)
end

local function track<T>(ctx: Context, instance: T): T
	table.insert(ctx.made, instance :: any)
	return instance
end

local function attachment(ctx: Context, layer: Layer, extra: CFrame?): Attachment
	local point = Instance.new("Attachment")
	point.Name = "Uvk_" .. (layer.name or layer.kind)
	local frame = ctx.origin.base * layerFrame(layer)
	point.CFrame = if extra then frame * extra else frame
	point.Parent = ctx.origin.part
	return track(ctx, point)
end

local function worldFrame(ctx: Context, layer: Layer): CFrame
	return ctx.origin.part.CFrame * ctx.origin.base * layerFrame(layer)
end

-- Drives `apply(level)` through attack / hold / release on the shared engine. A looping effect
-- holds until it is softened. Returns nothing; the release is registered on the context.
local function envelope(ctx: Context, layer: Layer, apply: (level: number) -> ())
	local fadeIn = layer.fadeIn or 0.05
	local hold = layer.hold or 0
	local fadeOut = layer.fadeOut or 0.3
	local state = { level = 0 }
	table.insert(ctx.states, state)
	apply(0)
	local function go(target: number, duration: number, easing: string)
		Motion.tween(state, { level = target }, {
			duration = duration,
			easing = easing,
			essential = true,
			onStep = function()
				apply(state.level)
			end,
		})
	end
	after(ctx, layer.delay or 0, function()
		go(1, fadeIn, "quadOut")
		if not ctx.looping then
			after(ctx, fadeIn + hold, function()
				go(0, fadeOut, "quadIn")
			end)
		end
	end)
	table.insert(ctx.releases, function(): number
		go(0, fadeOut, "quadIn")
		return fadeOut
	end)
end

-- Runs `apply(alpha)` once from 0 to 1 over `seconds` after the layer's delay.
local function oneShot(ctx: Context, layer: Layer, seconds: number, easing: string, apply: (alpha: number) -> ())
	local state = { t = 0 }
	table.insert(ctx.states, state)
	after(ctx, layer.delay or 0, function()
		apply(0)
		Motion.tween(state, { t = 1 }, {
			duration = seconds,
			easing = easing,
			essential = true,
			onStep = function(alpha: number)
				apply(alpha)
			end,
		})
	end)
end

local function buildParticles(ctx: Context, layer: Layer)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = layer.name or "Particles"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Texture = EffectLogic.texture(layer.texture, textures)
	emitter.Color = colorSequence(layer.colors or { "#FFFFFF" })
	emitter.Size = numberSequence(layer.sizes or { 0.4, 0 })
	emitter.Transparency = numberSequence(layer.transparency or { 0, 1 })
	emitter.Lifetime = range(layer.lifetime, 0.5, 1)
	emitter.Speed = range(layer.speed, 4, 8)
	local spread = layer.spread
	emitter.SpreadAngle = if spread then Vector2.new(spread[1], spread[2]) else Vector2.new(180, 180)
	emitter.Acceleration = vector(layer.acceleration)
	emitter.Drag = layer.drag or 0
	if layer.rotation then
		emitter.Rotation = range(layer.rotation, 0, 0)
	end
	if layer.rotSpeed then
		emitter.RotSpeed = range(layer.rotSpeed, 0, 0)
	end
	local emission = layer.lightEmission or 0
	emitter.LightEmission = emission
	-- Glowing particles ignore scene lighting so they still read in dark places.
	emitter.LightInfluence = layer.lightInfluence or (if emission >= 0.5 then 0 else 1)
	emitter.Brightness = layer.brightness or 1
	if layer.squash then
		emitter.Squash = numberSequence(layer.squash)
	end
	local shape = enumItem(Enum.ParticleEmitterShape, layer.shape)
	if shape then
		emitter.Shape = shape
	end
	local shapeStyle = enumItem(Enum.ParticleEmitterShapeStyle, layer.shapeStyle)
	if shapeStyle then
		emitter.ShapeStyle = shapeStyle
	end
	local shapeInOut = enumItem(Enum.ParticleEmitterShapeInOut, layer.shapeInOut)
	if shapeInOut then
		emitter.ShapeInOut = shapeInOut
	end
	local direction = enumItem(Enum.NormalId, layer.emissionDirection)
	if direction then
		emitter.EmissionDirection = direction
	end
	local orientation = enumItem(Enum.ParticleOrientation, layer.orientation)
	if orientation then
		emitter.Orientation = orientation
	end
	emitter.ZOffset = layer.zOffset or 0
	emitter.LockedToPart = layer.lockedToPart == true
	if layer.timeScale then
		emitter.TimeScale = layer.timeScale
	end

	-- A sized emit volume needs its own part; a point emitter sits on an attachment.
	local volume = layer.shapeSize
	if volume then
		local part = invisiblePart("UvkVolume")
		part.Size = Vector3.new(volume[1], volume[2], volume[3])
		part.CFrame = worldFrame(ctx, layer)
		local target = ctx.origin.moving
		if target then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = target
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = folder()
		track(ctx, part)
		emitter.Parent = part
	else
		emitter.Parent = attachment(ctx, layer)
	end
	track(ctx, emitter)
	table.insert(ctx.emitters, emitter)

	local burst = layer.burst
	local rate = layer.rate
	after(ctx, layer.delay or 0, function()
		if burst then
			emitter:Emit(burst)
		elseif rate then
			emitter.Rate = rate
			emitter.Enabled = true
			local emitFor = layer.emitFor
			if not ctx.looping and emitFor then
				after(ctx, emitFor, function()
					emitter.Enabled = false
				end)
			end
		end
	end)
end

local function buildBeam(ctx: Context, layer: Layer)
	local direction = vector(layer.direction or { 0, 1, 0 })
	if direction.Magnitude < 1e-3 then
		direction = Vector3.yAxis
	end
	local a0 = attachment(ctx, layer)
	local a1 = attachment(ctx, layer, CFrame.new(direction.Unit * (layer.length or 10)))
	local beam = Instance.new("Beam")
	beam.Name = layer.name or "Beam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = colorSequence(layer.colors or { "#FFFFFF" })
	beam.Transparency = numberSequence(layer.transparency or { 0.2, 1 })
	beam.Segments = layer.segments or 8
	local curve = layer.curve
	if curve then
		beam.CurveSize0 = curve[1]
		beam.CurveSize1 = curve[2]
	end
	if layer.texture then
		beam.Texture = EffectLogic.texture(layer.texture, textures)
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureSpeed = layer.textureSpeed or 1
		beam.TextureLength = layer.textureLength or 4
	end
	beam.LightEmission = layer.lightEmission or 1
	beam.LightInfluence = layer.lightInfluence or 0
	beam.Brightness = layer.brightness or 1
	beam.FaceCamera = layer.faceCamera ~= false
	beam.ZOffset = layer.zOffset or 0
	local width = layer.width or { 1, 1 }
	beam.Width0 = 0
	beam.Width1 = 0
	beam.Parent = a0
	track(ctx, beam)
	envelope(ctx, layer, function(level: number)
		beam.Width0 = width[1] * level
		beam.Width1 = width[2] * level
	end)
end

local function buildTrail(ctx: Context, layer: Layer)
	-- A trail is drawn by movement, so it only makes sense on a part the caller moves.
	if ctx.origin.moving == nil then
		return
	end
	local half = (if layer.width then layer.width[1] else 1) / 2
	local a0 = attachment(ctx, layer, CFrame.new(0, half, 0))
	local a1 = attachment(ctx, layer, CFrame.new(0, -half, 0))
	local trail = Instance.new("Trail")
	trail.Name = layer.name or "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = colorSequence(layer.colors or { "#FFFFFF" })
	trail.Transparency = numberSequence(layer.transparency or { 0, 1 })
	trail.Lifetime = layer.time or 0.3
	if layer.widthScale then
		trail.WidthScale = numberSequence(layer.widthScale)
	end
	trail.MinLength = layer.minLength or 0.1
	if layer.maxLength then
		trail.MaxLength = layer.maxLength
	end
	if layer.texture then
		trail.Texture = EffectLogic.texture(layer.texture, textures)
		trail.TextureMode = Enum.TextureMode.Stretch
	end
	trail.LightEmission = layer.lightEmission or 1
	trail.LightInfluence = layer.lightInfluence or 0
	trail.Brightness = layer.brightness or 1
	trail.FaceCamera = layer.faceCamera ~= false
	trail.Enabled = true
	trail.Parent = ctx.origin.part
	track(ctx, trail)
	table.insert(ctx.trails, trail)
end

local function buildLight(ctx: Context, layer: Layer)
	if ctx.lightsLeft <= 0 then
		return
	end
	ctx.lightsLeft -= 1
	local kind = layer.light or "point"
	local light: Light
	if kind == "spot" then
		local spot = Instance.new("SpotLight")
		spot.Range = layer.range or 12
		spot.Angle = layer.angle or 60
		spot.Face = enumItem(Enum.NormalId, layer.face) or Enum.NormalId.Top
		light = spot
	elseif kind == "surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Range = layer.range or 12
		surface.Angle = layer.angle or 90
		surface.Face = enumItem(Enum.NormalId, layer.face) or Enum.NormalId.Top
		light = surface
	else
		local point = Instance.new("PointLight")
		point.Range = layer.range or 12
		light = point
	end
	light.Name = layer.name or "Light"
	light.Color = firstColor(layer)
	light.Shadows = false
	light.Brightness = 0
	light.Parent = attachment(ctx, layer)
	track(ctx, light)

	local brightness = layer.brightness or 1
	local pulse = { value = 1 }
	local level = 0
	local function write()
		light.Brightness = brightness * level * pulse.value
	end
	envelope(ctx, layer, function(value: number)
		level = value
		write()
	end)
	local wave = layer.pulse
	if wave and ctx.looping then
		table.insert(ctx.states, pulse)
		-- A looping tween: the engine does not start it under reduced motion.
		Motion.tween(pulse, { value = 1 - wave[2] }, {
			duration = wave[1] / 2,
			easing = "sineInOut",
			repeatCount = -1,
			reverses = true,
			onStep = write,
		})
	end
end

local function buildHighlight(ctx: Context, layer: Layer)
	local adornee = ctx.origin.adornee
	if adornee == nil or highlights >= Builders.MAX_HIGHLIGHTS then
		return
	end
	highlights += 1
	local highlight = Instance.new("Highlight")
	highlight.Name = "UvkHighlight"
	highlight.Adornee = adornee
	highlight.FillColor = firstColor(layer)
	highlight.OutlineColor = Color3.fromHex(layer.outline or "#FFFFFF")
	highlight.DepthMode = enumItem(Enum.HighlightDepthMode, layer.depthMode) or Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = folder()
	track(ctx, highlight)
	table.insert(ctx.owned, function()
		highlights = math.max(0, highlights - 1)
	end)
	local fill = layer.fillTransparency or 0.5
	local outline = layer.outlineTransparency or 0
	envelope(ctx, layer, function(level: number)
		highlight.FillTransparency = 1 - (1 - fill) * level
		highlight.OutlineTransparency = 1 - (1 - outline) * level
	end)
end

local function buildRing(ctx: Context, layer: Layer)
	local radius = layer.radius or { 0.5, 5 }
	local fade = layer.transparency or { 0.05, 1 }
	local thickness = layer.thickness or 0.3
	local from = firstColor(layer)
	local to = lastColor(layer)
	local seconds = layer.time or 0.45
	local easing = layer.easing or "quartOut"

	if layer.style == "disc" then
		-- A thin cylinder lying flat. Its axis is the part's X axis, so it is turned upright.
		local disc = invisiblePart("UvkRing")
		disc.Shape = Enum.PartType.Cylinder
		disc.Material = Enum.Material.Neon
		disc.Color = from
		disc.Transparency = 1
		disc.CFrame = worldFrame(ctx, layer) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Size = Vector3.new(thickness, radius[1] * 2, radius[1] * 2)
		disc.Parent = folder()
		track(ctx, disc)
		oneShot(ctx, layer, seconds, easing, function(alpha: number)
			local r = radius[1] + (radius[2] - radius[1]) * alpha
			disc.Size = Vector3.new(thickness, math.max(0.05, r * 2), math.max(0.05, r * 2))
			disc.Transparency = math.clamp(fade[1] + (fade[2] - fade[1]) * alpha, 0, 1)
			disc.Color = from:Lerp(to, alpha)
		end)
		return
	end

	-- A true ring outline: two curved beams, each a half circle between the same two attachments.
	-- The attachments' X axes point along the ring's tangent plane so CurveSize bends the beams
	-- into arcs; FaceCamera keeps the line readable from any angle.
	local frame = ctx.origin.base * layerFrame(layer)
	local function place(point: Attachment, x: number)
		point.CFrame = frame * CFrame.fromMatrix(Vector3.new(x, 0, 0), Vector3.zAxis, Vector3.yAxis)
	end
	local a0 = attachment(ctx, layer)
	local a1 = attachment(ctx, layer)
	local beams: { Beam } = {}
	for side = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Name = "UvkRing"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Segments = 16
		beam.FaceCamera = true
		beam.LightEmission = layer.lightEmission or 1
		beam.LightInfluence = 0
		beam.Brightness = layer.brightness or 1
		beam.Width0 = thickness
		beam.Width1 = thickness
		beam.Transparency = NumberSequence.new(1)
		beam.Color = ColorSequence.new(from)
		beam.Parent = a0
		track(ctx, beam)
		beams[side] = beam
	end
	oneShot(ctx, layer, seconds, easing, function(alpha: number)
		local r = math.max(0.01, radius[1] + (radius[2] - radius[1]) * alpha)
		place(a0, -r)
		place(a1, r)
		local transparency = NumberSequence.new(math.clamp(fade[1] + (fade[2] - fade[1]) * alpha, 0, 1))
		local color = ColorSequence.new(from:Lerp(to, alpha))
		for side, beam in beams do
			local sign = if side == 1 then 1 else -1
			beam.CurveSize0 = sign * RING_CURVE * r
			beam.CurveSize1 = -sign * RING_CURVE * r
			beam.Transparency = transparency
			beam.Color = color
		end
	end)
end

local function buildFlash(ctx: Context, layer: Layer)
	local seconds = layer.time or 0.16
	if layer.style == "light" then
		if ctx.lightsLeft <= 0 then
			return
		end
		ctx.lightsLeft -= 1
		local light = Instance.new("PointLight")
		light.Name = "UvkFlash"
		light.Color = firstColor(layer)
		light.Range = layer.range or 16
		light.Shadows = false
		light.Brightness = 0
		light.Parent = attachment(ctx, layer)
		track(ctx, light)
		local peak = layer.brightness or 4
		oneShot(ctx, layer, seconds, "quadOut", function(alpha: number)
			light.Brightness = peak * (1 - alpha)
		end)
		return
	end
	local sizes = layer.sizes or { 0.8, 4 }
	local fade = layer.transparency or { 0.25, 1 }
	local orb = invisiblePart("UvkFlash")
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = firstColor(layer)
	orb.CFrame = worldFrame(ctx, layer)
	orb.Size = Vector3.one * math.max(0.05, sizes[1])
	orb.Parent = folder()
	track(ctx, orb)
	oneShot(ctx, layer, seconds, layer.easing or "quadOut", function(alpha: number)
		local size = math.max(0.05, sizes[1] + (sizes[2] - sizes[1]) * alpha)
		orb.Size = Vector3.one * size
		orb.Transparency = math.clamp(fade[1] + (fade[2] - fade[1]) * alpha, 0, 1)
	end)
end

local function buildBillboard(ctx: Context, layer: Layer)
	local sizes = layer.sizes or { 0, 2, 1.5 }
	local fade = layer.transparency or { 0, 1 }
	local rise = layer.rise or 0
	local color = firstColor(layer)
	local point = attachment(ctx, layer)
	local gui = Instance.new("BillboardGui")
	gui.Name = "UvkBillboard"
	gui.Adornee = point
	gui.AlwaysOnTop = layer.alwaysOnTop == true
	gui.LightInfluence = 0
	gui.MaxDistance = ctx.options.maxDistance
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromScale(math.max(0.01, sizes[1]), math.max(0.01, sizes[1]))

	-- An image when the key has an asset id, else the text, else a plain round glow dot (the
	-- built-in particle textures are not usable as GUI images).
	local image: string? = nil
	local key = layer.image
	if key then
		if string.sub(key, 1, 3) == "rbx" then
			image = key
		elseif textures[key] then
			image = textures[key]
		end
	end
	local setFade: (value: number) -> ()
	if image then
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Image = image
		label.ImageColor3 = color
		label.Parent = gui
		setFade = function(value: number)
			label.ImageTransparency = value
		end
	elseif layer.text then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = layer.text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.6
		label.Parent = gui
		setFade = function(value: number)
			label.TextTransparency = value
			label.TextStrokeTransparency = 0.6 + 0.4 * value
		end
	else
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromScale(0.7, 0.7)
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2
		stroke.Parent = dot
		dot.Parent = gui
		setFade = function(value: number)
			dot.BackgroundTransparency = value
			stroke.Transparency = value
		end
	end
	setFade(1)
	gui.Parent = ctx.origin.part
	track(ctx, gui)

	-- Pop to the peak in the first third (with the layer's easing), settle, and fade in the last 40%.
	local pop = Motion.Curves.get(layer.easing or "backOut")
	oneShot(ctx, layer, layer.time or 0.6, "linear", function(alpha: number)
		local size: number
		if alpha < 0.35 then
			size = sizes[1] + (sizes[2] - sizes[1]) * pop(alpha / 0.35)
		else
			size = sizes[2] + (sizes[3] - sizes[2]) * ((alpha - 0.35) / 0.65)
		end
		size = math.max(0.01, size)
		gui.Size = UDim2.fromScale(size, size)
		gui.StudsOffsetWorldSpace = Vector3.new(0, rise * alpha, 0)
		local fading = math.clamp((alpha - 0.6) / 0.4, 0, 1)
		setFade(math.clamp(fade[1] + (fade[2] - fade[1]) * fading, 0, 1))
	end)
end

local function buildPostfx(ctx: Context, layer: Layer)
	local camera = Workspace.CurrentCamera
	local kind = layer.effect or "bloom"
	-- One pulse per kind at a time: stacked pulses would compound into a white screen.
	if camera == nil or postfx[kind] then
		return
	end
	local amount = layer.amount or 0.5
	local apply: (level: number) -> ()
	local effect: PostEffect
	if kind == "blur" then
		local blur = Instance.new("BlurEffect")
		blur.Size = 0
		effect = blur
		apply = function(level: number)
			blur.Size = 12 * amount * level
		end
	elseif kind == "color" then
		local correction = Instance.new("ColorCorrectionEffect")
		local tint = if layer.colors then firstColor(layer) else Color3.new(1, 1, 1)
		effect = correction
		apply = function(level: number)
			correction.Brightness = 0.25 * amount * level
			correction.Contrast = 0.1 * amount * level
			correction.Saturation = 0.2 * amount * level
			correction.TintColor = Color3.new(1, 1, 1):Lerp(tint, 0.3 * level)
		end
	else
		local bloom = Instance.new("BloomEffect")
		bloom.Size = 24 + 16 * amount
		bloom.Threshold = 0.8
		bloom.Intensity = 0
		effect = bloom
		apply = function(level: number)
			bloom.Intensity = amount * level
		end
	end
	postfx[kind] = true
	effect.Name = "UvkPostfx"
	effect.Parent = camera
	track(ctx, effect)
	table.insert(ctx.owned, function()
		postfx[kind] = nil
	end)
	envelope(ctx, layer, apply)
end

local function buildShake(ctx: Context, layer: Layer)
	local shake = ctx.options.shake
	local preset = layer.preset
	if shake == nil or preset == nil then
		return
	end
	after(ctx, layer.delay or 0, function()
		shake(preset, layer.amount or 1, worldFrame(ctx, layer).Position)
	end)
end

local function buildSound(ctx: Context, layer: Layer)
	local sound = ctx.options.sound
	local cue = layer.cue
	if sound == nil or cue == nil then
		return
	end
	after(ctx, layer.delay or 0, function()
		sound(cue, layer.volume, ctx.origin.part)
	end)
end

local BUILDERS: { [string]: (ctx: Context, layer: Layer) -> () } = {
	particles = buildParticles,
	beam = buildBeam,
	trail = buildTrail,
	light = buildLight,
	highlight = buildHighlight,
	ring = buildRing,
	flash = buildFlash,
	billboard = buildBillboard,
	postfx = buildPostfx,
	shake = buildShake,
	sound = buildSound,
}

-- Creates every layer of a resolved effect at `origin`. The returned control destroys it all.
function Builders.build(resolved: EffectLogic.Resolved, origin: Origin, options: Options): Control
	local ctx: Context = {
		origin = origin,
		options = options,
		looping = resolved.looping,
		lightsLeft = options.lights,
		made = {},
		owned = {},
		timers = {},
		states = {},
		emitters = {},
		trails = {},
		releases = {},
		destroyed = false,
	}

	local function destroy()
		if ctx.destroyed then
			return
		end
		ctx.destroyed = true
		for _, cancel in ctx.timers do
			cancel()
		end
		for _, state in ctx.states do
			Motion.stop(state)
		end
		for _, item in ctx.owned do
			local kind = typeof(item)
			if kind == "function" then
				pcall(item)
			elseif kind == "RBXScriptConnection" then
				item:Disconnect()
			elseif kind == "Instance" then
				item:Destroy()
			end
		end
		for index = #ctx.made, 1, -1 do
			ctx.made[index]:Destroy()
		end
		table.clear(ctx.made)
		if origin.pooled then
			holders:release(origin.part :: any)
		end
	end

	for _, layer in resolved.layers do
		local builder = BUILDERS[layer.kind]
		if builder then
			local ok, err = pcall(builder, ctx, layer)
			if not ok then
				-- One bad layer must not leak the others.
				destroy()
				error(err, 0)
			end
		end
	end

	return {
		destroy = destroy,
		soften = function(): number
			if ctx.destroyed then
				return 0
			end
			-- Pending bursts and emit windows are dropped; nothing new may start.
			for _, cancel in ctx.timers do
				cancel()
			end
			table.clear(ctx.timers)
			for _, emitter in ctx.emitters do
				emitter.Enabled = false
			end
			for _, trail in ctx.trails do
				trail.Enabled = false
			end
			local fade = 0
			for _, release in ctx.releases do
				fade = math.max(fade, release())
			end
			return fade
		end,
		after = function(seconds: number, callback: () -> ())
			after(ctx, math.max(seconds, 1e-3), callback)
		end,
		own = function(item: any)
			if ctx.destroyed then
				if typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				end
				return
			end
			table.insert(ctx.owned, item)
		end,
	}
end

return Builders
