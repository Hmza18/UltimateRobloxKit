--!strict
-- Animation presets as data (pure Luau). Runtime/Motion.play applies them to instances through the
-- shared frame driver; tests and the HTML previewer call MotionPresets.sample directly.
--
-- A preset is { duration, easing, keys, loop? }. Keys are sorted by t (0..1) and may set any of
-- scale, rotation (degrees), offsetY (pixels) and transparency. Each property interpolates between
-- the previous and the next key that sets it, eased with the preset's Easing curve, and holds its
-- last value after the final key. A property no key sets stays at its rest value.
--
-- Special case: "shine" uses offsetY as a normalized sweep position from -1 to 1. Motion.play
-- applies it to a UIGradient's Offset.X instead of a position.

local Easing = require("./Easing")

export type Key = { t: number, scale: number?, rotation: number?, offsetY: number?, transparency: number? }
export type Preset = { duration: number, easing: string, keys: { Key }, loop: boolean? }
export type Sample = { scale: number, rotation: number, offsetY: number, transparency: number }

local MotionPresets = {}

MotionPresets.PROPERTIES = table.freeze({ "scale", "rotation", "offsetY", "transparency" })

local REST: Sample = { scale = 1, rotation = 0, offsetY = 0, transparency = 0 }
table.freeze(REST)
MotionPresets.REST = REST

local PRESETS: { [string]: Preset } = {
	-- Pointer and gamepad states. Components play these with fromCurrent so they blend.
	hover = { duration = 0.12, easing = "quadOut", keys = { { t = 0, scale = 1 }, { t = 1, scale = 1.06 } } },
	unhover = { duration = 0.12, easing = "quadOut", keys = { { t = 0, scale = 1.06 }, { t = 1, scale = 1 } } },
	press = { duration = 0.08, easing = "quadOut", keys = { { t = 0, scale = 1 }, { t = 1, scale = 0.92 } } },
	release = { duration = 0.22, easing = "backOut", keys = { { t = 0, scale = 0.92 }, { t = 1, scale = 1 } } },
	select = { duration = 0.2, easing = "backOut", keys = { { t = 0, scale = 1 }, { t = 1, scale = 1.08 } } },

	-- Windows and popups.
	open = {
		duration = 0.32,
		easing = "backOut",
		keys = {
			{ t = 0, scale = 0.6, offsetY = 24, transparency = 1 },
			{ t = 0.5, transparency = 0 },
			{ t = 1, scale = 1, offsetY = 0, transparency = 0 },
		},
	},
	close = {
		duration = 0.18,
		easing = "quadIn",
		keys = { { t = 0, scale = 1, transparency = 0 }, { t = 1, scale = 0.85, transparency = 1 } },
	},
	popIn = {
		duration = 0.35,
		easing = "backOut",
		keys = {
			{ t = 0, scale = 0, transparency = 1 },
			{ t = 0.4, transparency = 0 },
			{ t = 1, scale = 1, transparency = 0 },
		},
	},
	bounce = { duration = 0.5, easing = "bounceOut", keys = { { t = 0, offsetY = -24 }, { t = 1, offsetY = 0 } } },
	reveal = {
		duration = 0.9,
		easing = "backOut",
		keys = {
			{ t = 0, scale = 0, rotation = -12, transparency = 1 },
			{ t = 0.5, scale = 1.15, rotation = 4, transparency = 0 },
			{ t = 1, scale = 1, rotation = 0, transparency = 0 },
		},
	},

	-- Feedback.
	count = {
		duration = 0.6,
		easing = "cubicOut",
		keys = { { t = 0, scale = 1 }, { t = 0.25, scale = 1.12 }, { t = 1, scale = 1 } },
	},
	acquire = {
		duration = 0.45,
		easing = "backOut",
		keys = {
			{ t = 0, scale = 1, offsetY = 0 },
			{ t = 0.3, scale = 1.25, offsetY = -10 },
			{ t = 1, scale = 1, offsetY = 0 },
		},
	},
	purchase = {
		duration = 0.4,
		easing = "quadOut",
		keys = { { t = 0, scale = 1 }, { t = 0.25, scale = 0.9 }, { t = 0.6, scale = 1.12 }, { t = 1, scale = 1 } },
	},
	progress = {
		duration = 0.35,
		easing = "cubicOut",
		keys = { { t = 0, scale = 1 }, { t = 0.5, scale = 1.04 }, { t = 1, scale = 1 } },
	},
	tabSwitch = {
		duration = 0.2,
		easing = "quadOut",
		keys = { { t = 0, offsetY = 8, transparency = 1 }, { t = 1, offsetY = 0, transparency = 0 } },
	},
	toastIn = {
		duration = 0.3,
		easing = "backOut",
		keys = {
			{ t = 0, scale = 0.9, offsetY = -30, transparency = 1 },
			{ t = 1, scale = 1, offsetY = 0, transparency = 0 },
		},
	},
	toastOut = {
		duration = 0.2,
		easing = "quadIn",
		keys = { { t = 0, offsetY = 0, transparency = 0 }, { t = 1, offsetY = -20, transparency = 1 } },
	},

	-- Looping attention effects (skipped entirely under reduced motion).
	attention = {
		duration = 1.2,
		easing = "sineInOut",
		loop = true,
		keys = { { t = 0, scale = 1 }, { t = 0.5, scale = 1.15 }, { t = 1, scale = 1 } },
	},
	wiggle = {
		duration = 1.6,
		easing = "sineInOut",
		loop = true,
		keys = {
			{ t = 0, rotation = 0 },
			{ t = 0.1, rotation = -10 },
			{ t = 0.2, rotation = 10 },
			{ t = 0.3, rotation = -6 },
			{ t = 0.4, rotation = 6 },
			{ t = 0.5, rotation = 0 },
			{ t = 1, rotation = 0 },
		},
	},
	shine = {
		duration = 2.2,
		easing = "quadInOut",
		loop = true,
		keys = { { t = 0, offsetY = -1 }, { t = 0.45, offsetY = 1 }, { t = 1, offsetY = 1 } },
	},
}

for _, preset in PRESETS do
	for _, key in preset.keys do
		table.freeze(key)
	end
	table.freeze(preset.keys)
	table.freeze(preset)
end
table.freeze(PRESETS)

local function read(key: Key, property: string): number?
	if property == "scale" then
		return key.scale
	elseif property == "rotation" then
		return key.rotation
	elseif property == "offsetY" then
		return key.offsetY
	end
	return key.transparency
end

local function restValue(property: string): number
	return if property == "scale" then 1 else 0
end

-- Value of one property at normalized time t (0..1).
local function valueAt(preset: Preset, property: string, t: number): number
	local fromT = 0
	local fromV = restValue(property)
	for _, key in preset.keys do
		local value = read(key, property)
		if value ~= nil then
			if key.t <= t then
				fromT = key.t
				fromV = value
			else
				local span = key.t - fromT
				local u = if span > 0 then (t - fromT) / span else 1
				return Easing.lerp(fromV, value, Easing.ease(preset.easing, u))
			end
		end
	end
	return fromV
end

function MotionPresets.has(name: string): boolean
	return PRESETS[name] ~= nil
end

-- The preset called `name` (frozen). Unknown names raise an error.
function MotionPresets.get(name: string): Preset
	local preset = PRESETS[name]
	if preset == nil then
		error("unknown motion preset: " .. tostring(name), 2)
	end
	return preset
end

-- Every preset name, sorted.
function MotionPresets.names(): { string }
	local names: { string } = {}
	for name in PRESETS do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- True when any key of the preset sets `property`.
function MotionPresets.uses(preset: Preset, property: string): boolean
	for _, key in preset.keys do
		if read(key, property) ~= nil then
			return true
		end
	end
	return false
end

-- Values at normalized time t. Looping presets wrap t past 1; others clamp to 0..1.
function MotionPresets.sample(preset: Preset | string, t: number): Sample
	local resolved: Preset = if type(preset) == "string" then MotionPresets.get(preset) else preset
	local time = t
	if resolved.loop and time > 1 then
		time = time % 1
	end
	time = math.clamp(time, 0, 1)
	return {
		scale = math.max(0, valueAt(resolved, "scale", time)),
		rotation = valueAt(resolved, "rotation", time),
		offsetY = valueAt(resolved, "offsetY", time),
		transparency = math.clamp(valueAt(resolved, "transparency", time), 0, 1),
	}
end

-- The resting values a preset ends on (what reduced motion jumps to).
function MotionPresets.final(preset: Preset | string): Sample
	return MotionPresets.sample(preset, 1)
end

-- A copy of `preset` whose first key starts from `current` for the properties the preset uses.
-- Used for state transitions (hover after press) so an interrupted animation never jumps.
function MotionPresets.from(preset: Preset, current: Sample): Preset
	local keys: { Key } = {}
	for _, key in preset.keys do
		table.insert(keys, table.clone(key))
	end
	if #keys == 0 or keys[1].t > 0 then
		table.insert(keys, 1, { t = 0 })
	end
	local first = keys[1]
	if MotionPresets.uses(preset, "scale") then
		first.scale = current.scale
	end
	if MotionPresets.uses(preset, "rotation") then
		first.rotation = current.rotation
	end
	if MotionPresets.uses(preset, "offsetY") then
		first.offsetY = current.offsetY
	end
	if MotionPresets.uses(preset, "transparency") then
		first.transparency = current.transparency
	end
	return { duration = preset.duration, easing = preset.easing, keys = keys, loop = preset.loop }
end

-- Problems with a preset definition (empty when valid): keys sorted, t within 0..1, first key at
-- 0, last key at 1, a known easing and a positive duration.
function MotionPresets.validate(preset: Preset): { string }
	local problems: { string } = {}
	if type(preset.duration) ~= "number" or preset.duration <= 0 then
		table.insert(problems, "duration must be a positive number")
	end
	if type(preset.easing) ~= "string" or not Easing.has(preset.easing) then
		table.insert(problems, "unknown easing " .. tostring(preset.easing))
	end
	local keys = preset.keys
	if #keys < 2 then
		table.insert(problems, "needs at least two keys")
		return problems
	end
	if keys[1].t ~= 0 then
		table.insert(problems, "first key must be at t = 0")
	end
	if keys[#keys].t ~= 1 then
		table.insert(problems, "last key must be at t = 1")
	end
	for index, key in keys do
		if key.t < 0 or key.t > 1 then
			table.insert(problems, string.format("key %d: t out of range", index))
		end
		if index > 1 and key.t <= keys[index - 1].t then
			table.insert(problems, string.format("key %d: t not increasing", index))
		end
	end
	return problems
end

-- Seconds a preset lasts, or 0 under reduced motion.
function MotionPresets.duration(name: string, reducedMotion: boolean?): number
	return Easing.duration(MotionPresets.get(name).duration, reducedMotion)
end

return MotionPresets
