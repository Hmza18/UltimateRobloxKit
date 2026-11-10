--!strict
-- Object animation presets (pure Luau). Each preset is data plus a sampler: for a time t it gives
-- offsets relative to the object's rest state, which Objects/Objects.luau applies to a Model,
-- BasePart, Attachment or GuiObject:
--
--   position      { x, y, z } added to the rest position (studs in the world, pixels on a GUI;
--                 y is up in both)
--   rotation      { x, y, z } degrees added to the rest rotation
--   scale         { x, y, z } multipliers; squash and stretch keeps volume (y up means x, z down)
--   transparency  0 (as at rest) .. 1 (invisible)
--
-- Loops (Float, Hover, Bounce, Spin, Pulse, Sway, Orbit) repeat forever and take a `phase` so a
-- row of objects does not move in unison. One-shots end exactly on their end state.

local Curves = require("../Core/Curves")
local Registry = require("../Core/Registry")

export type Vec3 = { number }

export type Sample = {
	position: Vec3,
	rotation: Vec3,
	scale: Vec3,
	transparency: number,
	done: boolean,
}

export type Params = {
	amplitude: number?, -- studs, pixels, degrees or scale amount, depending on the preset
	speed: number?, -- loops: cycles per second
	duration: number?, -- one-shots: seconds
	axis: string?, -- "x" | "y" | "z"
	phase: number?, -- loops: 0..1 of a cycle
	intensity: number?, -- multiplier on the amplitude (default 1)
	target: Vec3?, -- Collect / Teleport: where to end up, relative to rest
}

type Resolved = {
	amplitude: number,
	speed: number,
	duration: number,
	axis: number, -- 1, 2 or 3
	phase: number,
	intensity: number,
	target: Vec3,
}

type Def = {
	name: string,
	description: string,
	loop: boolean,
	amplitude: number,
	unit: string, -- what amplitude means, for the docs
	speed: number?,
	duration: number?,
	axis: string?,
	target: Vec3?,
	transparency: boolean, -- true when the preset changes transparency
	sample: (t: number, p: Resolved) -> Sample,
}

local ObjectsLogic = {}

local TAU = 2 * math.pi
local AXES: { [string]: number } = { x = 1, y = 2, z = 3 }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function ease(name: string, t: number): number
	return Curves.ease(name, math.clamp(t, 0, 1))
end

local function rest(): Sample
	return { position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, scale = { 1, 1, 1 }, transparency = 0, done = false }
end

-- Volume-preserving squash and stretch: scaling y by `stretch` scales x and z by 1 / sqrt(stretch).
function ObjectsLogic.squash(stretch: number): Vec3
	local y = math.max(0.05, stretch)
	local side = 1 / math.sqrt(y)
	return { side, y, side }
end

local squash = ObjectsLogic.squash

-- A phase 0..1 for the index-th object of a group (golden-ratio spacing: neighbours never match).
function ObjectsLogic.phaseFor(index: number): number
	local value = index * 0.61803398875
	return value - math.floor(value)
end

local DEFS: { [string]: Def } = {
	-- Loops ----------------------------------------------------------------------------------
	Float = {
		name = "Float",
		description = "Slow vertical bob with a lagging turn, for pickups and floating props.",
		loop = true,
		amplitude = 0.5,
		unit = "studs",
		speed = 0.5,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local angle = TAU * (t * p.speed + p.phase)
			s.position[2] = p.amplitude * math.sin(angle)
			-- Secondary motion: a small turn a quarter cycle behind the bob.
			s.rotation[2] = 4 * p.intensity * math.sin(angle - math.pi / 2)
			return s
		end,
	},
	Hover = {
		name = "Hover",
		description = "Quicker, tighter hover with a figure-of-eight drift and a breathing squash.",
		loop = true,
		amplitude = 0.25,
		unit = "studs",
		speed = 0.9,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local angle = TAU * (t * p.speed + p.phase)
			s.position[2] = p.amplitude * math.sin(angle)
			s.position[1] = p.amplitude * 0.4 * math.sin(angle * 2)
			s.scale = squash(1 + 0.03 * p.intensity * math.sin(angle + math.pi / 2))
			return s
		end,
	},
	Bounce = {
		name = "Bounce",
		description = "Repeated hop from the rest position with a squash on landing and a stretch in the air.",
		loop = true,
		amplitude = 1.2,
		unit = "studs",
		speed = 1.2,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local cycle = t * p.speed + p.phase
			local u = cycle - math.floor(cycle)
			s.position[2] = p.amplitude * 4 * u * (1 - u)
			local edge = math.min(u, 1 - u)
			local stretch: number
			if edge < 0.1 then
				stretch = 1 - 0.18 * p.intensity * (1 - edge / 0.1)
			else
				stretch = 1 + 0.08 * p.intensity * math.sin(math.pi * (edge - 0.1) / 0.4)
			end
			s.scale = squash(stretch)
			return s
		end,
	},
	Spin = {
		name = "Spin",
		description = "Constant rotation around one axis; a negative speed spins the other way.",
		loop = true,
		amplitude = 1,
		unit = "unused",
		speed = 0.25,
		axis = "y",
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			s.rotation[p.axis] = (360 * (t * p.speed + p.phase)) % 360
			return s
		end,
	},
	Pulse = {
		name = "Pulse",
		description = "Gentle uniform scale pulse around the rest size.",
		loop = true,
		amplitude = 0.08,
		unit = "scale",
		speed = 0.8,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local k = math.max(0.01, 1 + p.amplitude * math.sin(TAU * (t * p.speed + p.phase)))
			s.scale = { k, k, k }
			return s
		end,
	},
	Sway = {
		name = "Sway",
		description = "Rocking rotation around one axis, like a sign in the wind.",
		loop = true,
		amplitude = 8,
		unit = "degrees",
		speed = 0.4,
		axis = "z",
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			s.rotation[p.axis] = p.amplitude * math.sin(TAU * (t * p.speed + p.phase))
			return s
		end,
	},
	Orbit = {
		name = "Orbit",
		description = "Circles the rest position in the plane across the axis; amplitude is the radius.",
		loop = true,
		amplitude = 2,
		unit = "studs",
		speed = 0.3,
		axis = "y",
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local angle = TAU * (t * p.speed + p.phase)
			local a = p.axis % 3 + 1
			local b = a % 3 + 1
			s.position[b] = p.amplitude * math.cos(angle)
			s.position[a] = p.amplitude * math.sin(angle)
			return s
		end,
	},
	-- One-shots ------------------------------------------------------------------------------
	ScaleIn = {
		name = "Scale in",
		description = "Grows from nothing with an overshoot and settles at full size.",
		loop = false,
		amplitude = 1,
		unit = "overshoot",
		duration = 0.4,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local k = math.max(0, lerp(ease("quintOut", u), ease("backOut", u), math.clamp(p.amplitude, 0, 1)))
			if u <= 0 then
				k = 0
			end
			s.scale = { k, k, k }
			return s
		end,
	},
	ScaleOut = {
		name = "Scale out",
		description = "Swells briefly in anticipation, then shrinks to nothing and hides.",
		loop = false,
		amplitude = 1,
		unit = "anticipation",
		duration = 0.3,
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local k = math.max(0, 1 - lerp(ease("quadIn", u), ease("backIn", u), math.clamp(p.amplitude, 0, 1)))
			s.scale = { k, k, k }
			if u >= 1 then
				s.scale = { 0, 0, 0 }
				s.transparency = 1
			end
			return s
		end,
	},
	Reveal = {
		name = "Reveal",
		description = "Rises into place while fading in, turning half a turn and popping to full size.",
		loop = false,
		amplitude = 1.5,
		unit = "studs",
		duration = 0.7,
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local travel = ease("quintOut", u)
			s.position[2] = -p.amplitude * (1 - travel)
			s.rotation[2] = 180 * (1 - travel)
			local k = 0.6 + 0.4 * ease("backOut", u)
			s.scale = { k, k, k }
			s.transparency = 1 - math.clamp(u / 0.4, 0, 1)
			return s
		end,
	},
	Dissolve = {
		name = "Dissolve",
		description = "Drifts upward and swells slightly while fading out completely.",
		loop = false,
		amplitude = 0.6,
		unit = "studs",
		duration = 0.6,
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			s.position[2] = p.amplitude * ease("quadOut", u)
			local k = 1 + 0.15 * math.clamp(u, 0, 1)
			s.scale = { k, k, k }
			s.transparency = ease("sineInOut", u)
			return s
		end,
	},
	Appear = {
		name = "Appear",
		description = "Quick fade in with a small drop and a settle to full size.",
		loop = false,
		amplitude = 0.4,
		unit = "studs",
		duration = 0.35,
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local travel = ease("quintOut", u)
			s.position[2] = p.amplitude * (1 - travel)
			local k = 0.92 + 0.08 * travel
			s.scale = { k, k, k }
			s.transparency = 1 - ease("quadOut", u)
			return s
		end,
	},
	Disappear = {
		name = "Disappear",
		description = "Quick fade out with a slight shrink.",
		loop = false,
		amplitude = 0.08,
		unit = "scale",
		duration = 0.25,
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = ease("quadIn", t / p.duration)
			local k = 1 - p.amplitude * u
			s.scale = { k, k, k }
			s.transparency = u
			return s
		end,
	},
	Collect = {
		name = "Collect",
		description = "Pops, pulls back, then arcs to a target point and shrinks away as it arrives.",
		loop = false,
		amplitude = 1.5,
		unit = "studs",
		duration = 0.55,
		target = { 0, 3, 0 },
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local target = p.target
			if u < 0.18 then
				-- Anticipation: a pop and a small pull away from where it is about to go.
				local v = math.sin(math.pi * u / 0.18)
				local k = 1 + 0.15 * p.intensity * v
				s.scale = { k, k, k }
				for i = 1, 3 do
					s.position[i] = -0.08 * target[i] * v
				end
				return s
			end
			local w = math.clamp((u - 0.18) / 0.82, 0, 1)
			local travel = ease("cubicIn", w)
			for i = 1, 3 do
				s.position[i] = target[i] * travel
			end
			s.position[2] += p.amplitude * math.sin(math.pi * w) * (1 - w)
			local k = 1 - ease("quadIn", (w - 0.5) / 0.5)
			s.scale = { k, k, k }
			if w >= 1 then
				s.position = { target[1], target[2], target[3] }
				s.scale = { 0, 0, 0 }
				s.transparency = 1
			end
			return s
		end,
	},
	Teleport = {
		name = "Teleport",
		description = "Squashes, stretches up and vanishes, then reappears at the target with an overshoot.",
		loop = false,
		amplitude = 1.5,
		unit = "studs",
		duration = 0.7,
		target = { 0, 0, 0 },
		transparency = true,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local target = p.target
			local wide = 1 / math.sqrt(0.35)
			if u < 0.22 then
				s.scale = squash(lerp(1, 0.35, ease("quadOut", u / 0.22)))
			elseif u < 0.4 then
				local v = ease("quadIn", (u - 0.22) / 0.18)
				local side = lerp(wide, 0.05, v)
				s.scale = { side, lerp(0.35, 2.4, v), side }
				s.position[2] = p.amplitude * v
				s.transparency = v
			elseif u < 0.5 then
				s.scale = { 0.05, 2.4, 0.05 }
				s.position = { target[1], target[2] + p.amplitude, target[3] }
				s.transparency = 1
			elseif u < 0.68 then
				local v = ease("quintOut", (u - 0.5) / 0.18)
				local side = lerp(0.05, 1, v)
				s.scale = { side, lerp(2.4, 1, v), side }
				s.position = { target[1], target[2] + p.amplitude * (1 - v), target[3] }
				s.transparency = 1 - v
			else
				-- Landing: squash on contact, rebound past rest, settle.
				local v = math.clamp((u - 0.68) / 0.32, 0, 1)
				local wobble = math.exp(-4 * v) * math.sin(v * math.pi * 3) * (1 - v)
				s.scale = squash(1 - 0.16 * p.intensity * wobble)
				s.position = { target[1], target[2], target[3] }
			end
			return s
		end,
	},
	Shake = {
		name = "Shake",
		description = "Fast decaying rattle around the rest position, for locked or damaged objects.",
		loop = false,
		amplitude = 0.25,
		unit = "studs",
		duration = 0.4,
		speed = 22,
		axis = "x",
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = math.clamp(t / p.duration, 0, 1)
			local envelope = (1 - u) ^ 2
			local angle = TAU * (p.speed * t + p.phase)
			local other = p.axis % 3 + 1
			s.position[p.axis] = p.amplitude * envelope * math.sin(angle)
			s.position[other] = p.amplitude * 0.45 * envelope * math.sin(angle * 1.31 + 1.7)
			s.rotation[3] = 6 * p.intensity * envelope * math.sin(angle * 0.83 + 0.6)
			return s
		end,
	},
	SquashStretch = {
		name = "Squash and stretch",
		description = "Anticipation squash, a stretch with a small hop, then a springy settle; keeps volume.",
		loop = false,
		amplitude = 0.25,
		unit = "scale",
		duration = 0.6,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local a = math.min(p.amplitude, 0.8)
			local stretch: number
			if u < 0.2 then
				stretch = 1 - a * ease("quadOut", u / 0.2)
			elseif u < 0.45 then
				stretch = lerp(1 - a, 1 + a, ease("sineInOut", (u - 0.2) / 0.25))
			else
				local v = math.clamp((u - 0.45) / 0.55, 0, 1)
				stretch = 1 + a * math.exp(-5 * v) * math.cos(v * math.pi * 2.5) * (1 - v)
			end
			s.scale = squash(stretch)
			if u > 0.2 and u < 0.7 then
				s.position[2] = a * 1.2 * math.sin(math.pi * (u - 0.2) / 0.5)
			end
			return s
		end,
	},
	Interact = {
		name = "Interact",
		description = "Quick squash and pop to confirm a click, touch or proximity prompt.",
		loop = false,
		amplitude = 0.12,
		unit = "scale",
		duration = 0.28,
		transparency = false,
		sample = function(t: number, p: Resolved): Sample
			local s = rest()
			local u = t / p.duration
			local a = math.min(p.amplitude, 0.6)
			local stretch: number
			if u < 0.22 then
				stretch = 1 - a * ease("quadOut", u / 0.22)
			else
				local v = math.clamp((u - 0.22) / 0.78, 0, 1)
				stretch = 1 - a * math.exp(-3.5 * v) * math.cos(v * math.pi * 2.2) * (1 - v)
			end
			s.scale = squash(stretch)
			return s
		end,
	},
}

ObjectsLogic.LOOPS = table.freeze({ "Float", "Hover", "Bounce", "Spin", "Pulse", "Sway", "Orbit" })
ObjectsLogic.ONE_SHOTS = table.freeze({
	"ScaleIn",
	"ScaleOut",
	"Reveal",
	"Dissolve",
	"Appear",
	"Disappear",
	"Collect",
	"Teleport",
	"Shake",
	"SquashStretch",
	"Interact",
})

local function def(id: string): Def
	local found = DEFS[id]
	if found == nil then
		error("unknown object animation: " .. tostring(id), 3)
	end
	return found
end

function ObjectsLogic.has(id: string): boolean
	return DEFS[id] ~= nil
end

function ObjectsLogic.isLoop(id: string): boolean
	return def(id).loop
end

-- True when the preset changes transparency (the runtime then stores the originals).
function ObjectsLogic.usesTransparency(id: string): boolean
	return def(id).transparency
end

local function number(value: any, default: number): number
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return default
end

local function resolve(d: Def, params: Params?): Resolved
	local given: Params = params or {}
	local intensity = math.max(0, number(given.intensity, 1))
	local target = given.target or d.target or { 0, 0, 0 }
	return {
		amplitude = number(given.amplitude, d.amplitude) * intensity,
		speed = number(given.speed, d.speed or 1),
		duration = math.max(0.01, number(given.duration, d.duration or 1)),
		axis = AXES[given.axis or d.axis or "y"] or 2,
		phase = number(given.phase, 0),
		intensity = intensity,
		target = { number(target[1], 0), number(target[2], 0), number(target[3], 0) },
	}
end

-- Seconds a one-shot lasts with these params (math.huge for loops).
function ObjectsLogic.duration(id: string, params: Params?): number
	local d = def(id)
	if d.loop then
		return math.huge
	end
	return resolve(d, params).duration
end

-- Seconds after which a loop repeats exactly.
function ObjectsLogic.period(id: string, params: Params?): number
	local d = def(id)
	if not d.loop then
		error(id .. " is not a loop", 2)
	end
	local speed = math.abs(resolve(d, params).speed)
	return if speed > 0 then 1 / speed else math.huge
end

-- The offsets of preset `id` at time t (seconds since it started). One-shots clamp to their end
-- state and set done = true once t reaches the duration.
function ObjectsLogic.sample(id: string, t: number, params: Params?): Sample
	local d = def(id)
	local p = resolve(d, params)
	if d.loop then
		return d.sample(math.max(0, t), p)
	end
	local time = math.clamp(t, 0, p.duration)
	local done = t >= p.duration
	local s = d.sample(if done then p.duration else time, p)
	s.done = done
	if done then
		-- Rounding must not leave a finished object a hair off its end state.
		if s.transparency < 1e-9 then
			s.transparency = 0
		elseif s.transparency > 1 - 1e-9 then
			s.transparency = 1
		end
		for i = 1, 3 do
			if math.abs(s.position[i] - p.target[i]) < 1e-9 and d.target ~= nil then
				s.position[i] = p.target[i]
			elseif math.abs(s.position[i]) < 1e-9 then
				s.position[i] = 0
			end
			if math.abs(s.rotation[i]) < 1e-9 then
				s.rotation[i] = 0
			end
			if math.abs(s.scale[i] - 1) < 1e-9 then
				s.scale[i] = 1
			end
		end
	end
	return s
end

-- The state a one-shot leaves the object in (rest for loops).
function ObjectsLogic.endState(id: string, params: Params?): Sample
	local d = def(id)
	if d.loop then
		return rest()
	end
	return ObjectsLogic.sample(id, resolve(d, params).duration, params)
end

function ObjectsLogic.rest(): Sample
	return rest()
end

-- True when the sample leaves the object exactly as it was.
function ObjectsLogic.isRest(s: Sample): boolean
	for i = 1, 3 do
		if s.position[i] ~= 0 or s.rotation[i] ~= 0 or s.scale[i] ~= 1 then
			return false
		end
	end
	return s.transparency == 0
end

-- How often a looping object far from the camera is redrawn: 1 = every frame, 2 = every second
-- frame, and so on; 0 = not at all (beyond the profile's maximum distance). Time still advances,
-- so a throttled loop stays in step.
function ObjectsLogic.updateEvery(
	distance: number?,
	fadeDistance: number,
	maxDistance: number,
	dropOptional: boolean
): number
	if distance == nil or distance <= fadeDistance then
		return 1
	end
	if distance > maxDistance then
		return 0
	end
	return if dropOptional then 3 else 2
end

-- Registry ------------------------------------------------------------------------------------

local registry = Registry.new("object")
ObjectsLogic.registry = registry

local function register(id: string)
	local d = DEFS[id]
	local params: { [string]: Registry.Param } = {
		amplitude = {
			type = "number",
			default = d.amplitude,
			min = 0,
			max = 1000,
			description = "Amount in " .. d.unit,
		},
		intensity = { type = "number", default = 1, min = 0, max = 3, description = "Multiplier on the amplitude" },
	}
	if d.loop then
		params.speed =
			{ type = "number", default = d.speed or 1, min = -20, max = 20, description = "Cycles per second" }
		params.phase = { type = "number", default = 0, min = 0, max = 1, description = "Start offset, 0..1 of a cycle" }
	else
		params.duration = { type = "number", default = d.duration or 1, min = 0.01, max = 30, description = "Seconds" }
	end
	if d.axis then
		params.axis = { type = "enum", default = d.axis, options = { "x", "y", "z" }, description = "Axis" }
	end
	registry:register({
		id = id,
		name = d.name,
		category = if d.loop then "loop" else "oneshot",
		description = d.description,
		params = params,
		quality = { min = "Low", cost = "low" },
		usage = string.format('Visuals.Objects.animate(target, "%s")', id),
		tags = { if d.loop then "loop" else "oneshot", if d.transparency then "fade" else "motion" },
		preview = { loop = d.loop, duration = d.duration },
		data = { loop = d.loop, transparency = d.transparency, target = d.target },
	})
end

for _, id in ObjectsLogic.LOOPS do
	register(id)
end
for _, id in ObjectsLogic.ONE_SHOTS do
	register(id)
end

return ObjectsLogic
