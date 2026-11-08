--!strict
-- VFX presets with quality tiers. Pure Luau: presets are plain data (numbers and hex colours), and this
-- module picks a quality for the device and scales each preset to it. VFXClient turns the result into
-- ParticleEmitters. Effects are cosmetic, so they always run on the client.
--
-- Quality: "low" (phones, low frame rate), "medium" (default), "high" (desktop and console with
-- headroom). Lower tiers cut particle counts and rates, shorten lifetimes and drop optional layers.

export type Quality = "low" | "medium" | "high"

export type Layer = {
	name: string,
	texture: string?, -- rbxassetid; nil uses Roblox's default sparkle
	colors: { string }, -- 1-3 hex stops over the lifetime
	sizes: { number }, -- 1-3 size stops in studs
	transparency: { number }?, -- 1-3 stops, default { 0, 1 }
	lifetime: { number }, -- { min, max } seconds
	speed: { number }, -- { min, max } studs per second
	spread: number?, -- degrees (default 180 = sphere)
	rate: number?, -- particles per second for looping layers
	burst: number?, -- particles emitted at once for one-shot layers
	gravity: number?, -- Y acceleration (negative falls)
	lightEmission: number?, -- 0..1
	rotSpeed: { number }?, -- { min, max } degrees per second
	optional: boolean?, -- dropped on "low"
}

export type Preset = { layers: { Layer }, duration: number?, looping: boolean? }

export type Device = {
	touch: boolean?, -- phone or tablet
	gamepad: boolean?, -- console or controller
	fps: number?, -- recent average frame rate
	graphicsLevel: number?, -- UserSettings().GameSettings.SavedQualityLevel (1-10)
}

local VFXLogic = {}

export type Scale = { count: number, rate: number, lifetime: number, size: number }

local SCALE: { [string]: Scale } = {
	low = { count = 0.35, rate = 0.35, lifetime = 0.75, size = 1.1 },
	medium = { count = 0.7, rate = 0.7, lifetime = 0.9, size = 1 },
	high = { count = 1, rate = 1, lifetime = 1, size = 1 },
}
VFXLogic.SCALE = SCALE

-- Concurrent emitters allowed per tier; VFXClient skips new effects past this.
VFXLogic.BUDGET = { low = 12, medium = 30, high = 60 }

VFXLogic.PRESETS = {
	hatch = {
		duration = 1.2,
		layers = {
			{
				name = "burst",
				colors = { "#FFF6B0", "#FFC93C" },
				sizes = { 0.6, 0 },
				lifetime = { 0.5, 0.9 },
				speed = { 10, 18 },
				burst = 40,
				lightEmission = 1,
			},
			{
				name = "sparkle",
				colors = { "#FFFFFF", "#8FD3FF" },
				sizes = { 0.25, 0 },
				lifetime = { 0.8, 1.2 },
				speed = { 2, 5 },
				burst = 25,
				lightEmission = 1,
				rotSpeed = { -180, 180 },
				optional = true,
			},
		},
	},
	levelUp = {
		duration = 1.5,
		layers = {
			{
				name = "ring",
				colors = { "#7CFF6B", "#2ECC71" },
				sizes = { 0.4, 1.2, 0 },
				lifetime = { 0.6, 0.8 },
				speed = { 6, 8 },
				spread = 15,
				burst = 30,
				gravity = 4,
				lightEmission = 0.8,
			},
			{
				name = "stars",
				colors = { "#FFFFFF", "#FFE45C" },
				sizes = { 0.3, 0 },
				lifetime = { 1, 1.4 },
				speed = { 3, 6 },
				burst = 18,
				gravity = 2,
				optional = true,
			},
		},
	},
	coinPickup = {
		duration = 0.6,
		layers = {
			{
				name = "glint",
				colors = { "#FFE45C", "#F7C21B" },
				sizes = { 0.35, 0 },
				lifetime = { 0.3, 0.5 },
				speed = { 4, 8 },
				burst = 12,
				lightEmission = 1,
			},
		},
	},
	rareAura = {
		looping = true,
		layers = {
			{
				name = "aura",
				colors = { "#B36BFF", "#5A2BFF" },
				sizes = { 0.5, 0.2 },
				transparency = { 0.2, 1 },
				lifetime = { 1, 1.6 },
				speed = { 0.5, 1.5 },
				rate = 18,
				gravity = 1.5,
				lightEmission = 0.7,
			},
			{
				name = "motes",
				colors = { "#FFFFFF" },
				sizes = { 0.15, 0 },
				lifetime = { 1.5, 2 },
				speed = { 0.3, 0.8 },
				rate = 8,
				optional = true,
			},
		},
	},
	purchase = {
		duration = 1,
		layers = {
			{
				name = "confetti",
				colors = { "#FF5A5A", "#FFE45C", "#4FC3FF" },
				sizes = { 0.3, 0.3 },
				lifetime = { 1, 1.5 },
				speed = { 12, 20 },
				spread = 40,
				burst = 50,
				gravity = -25,
				rotSpeed = { -360, 360 },
			},
		},
	},
} :: { [string]: Preset }

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Picks a quality tier. A saved graphics level (1-10) wins when given; otherwise touch devices and low
-- frame rates get "low", and devices with steady 55+ fps that are not touch get "high".
function VFXLogic.chooseQuality(device: Device): Quality
	local level = device.graphicsLevel
	if isFinite(level) and (level :: number) >= 1 then
		if (level :: number) <= 3 then
			return "low"
		elseif (level :: number) >= 8 then
			return "high"
		end
		return "medium"
	end
	local fps = device.fps
	if isFinite(fps) and (fps :: number) < 40 then
		return "low"
	end
	if device.touch then
		return if isFinite(fps) and (fps :: number) >= 58 then "medium" else "low"
	end
	if isFinite(fps) and (fps :: number) >= 55 then
		return "high"
	end
	return "medium"
end

local function scaleRange(range: { number }, k: number): { number }
	local out = {}
	for i, v in range do
		out[i] = v * k
	end
	return out
end

-- The preset adjusted for a quality tier. Optional layers are dropped on "low"; counts never drop below 1.
function VFXLogic.resolve(name: string, quality: Quality): Preset
	local preset = VFXLogic.PRESETS[name]
	assert(preset ~= nil, "unknown VFX preset " .. tostring(name))
	local k: Scale? = SCALE[quality]
	assert(k ~= nil, "unknown quality " .. tostring(quality))
	local scale: Scale = k
	local layers: { Layer } = {}
	for _, layer in preset.layers do
		if quality == "low" and layer.optional then
			continue
		end
		local copy = table.clone(layer)
		copy.lifetime = scaleRange(layer.lifetime, scale.lifetime)
		copy.sizes = scaleRange(layer.sizes, scale.size)
		if layer.burst then
			copy.burst = math.max(1, math.floor(layer.burst * scale.count + 0.5))
		end
		if layer.rate then
			copy.rate = math.max(1, layer.rate * scale.rate)
		end
		table.insert(layers, copy)
	end
	return { layers = layers, duration = preset.duration, looping = preset.looping }
end

-- Total particles a one-shot preset emits at a quality, for budgeting and tests.
function VFXLogic.particleCount(preset: Preset): number
	local total = 0
	for _, layer in preset.layers do
		total += layer.burst or 0
	end
	return total
end

function VFXLogic.names(): { string }
	local names: { string } = {}
	for name in VFXLogic.PRESETS do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Registers a game-specific preset (same shape as the built-ins). Errors on bad data.
function VFXLogic.register(name: string, preset: Preset)
	assert(type(name) == "string" and name ~= "", "preset name required")
	assert(type(preset.layers) == "table" and #preset.layers > 0, "preset needs layers")
	for _, layer in preset.layers do
		assert(#layer.colors >= 1 and #layer.colors <= 3, name .. ": 1-3 colours")
		assert(#layer.sizes >= 1 and #layer.sizes <= 3, name .. ": 1-3 sizes")
		assert(#layer.lifetime == 2 and #layer.speed == 2, name .. ": lifetime and speed are { min, max }")
		assert(layer.burst ~= nil or layer.rate ~= nil, name .. ": a layer needs burst or rate")
	end
	VFXLogic.PRESETS[name] = preset
end

return VFXLogic
