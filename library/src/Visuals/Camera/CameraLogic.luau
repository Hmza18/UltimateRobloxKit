--!strict
-- Camera maths for the visuals kit (pure Luau; no Roblox globals, so everything here runs under
-- Lune). Positions are number arrays { x, y, z }; angles are degrees.
--
--   Shake      trauma-based camera shake: amplitude = trauma^2, smooth pseudo-noise from summed
--              sines (deterministic for a given time and seed), separate positional and rotational
--              amplitude, presets, and a clamped sum of several shakes
--   Framing    focus / orbit / pan / zoom poses and the distance needed to fit a bounding sphere
--   Stack      priority stack of camera moves with blend in / out; it folds the live entries over
--              the game's own camera pose and remembers what was changed so restore is exact
--   Cinematics recipes as keyframed data (PetReveal, RewardReveal, AreaUnlock, Teleport)
--
-- Camera/Camera.luau applies the results to workspace.CurrentCamera.

local Curves = require("../Core/Curves")
local Registry = require("../Core/Registry")

export type Vec3 = { number }

-- A camera pose. `position` and `lookAt` are nil for FOV-only moves: they inherit whatever is
-- underneath (the game's own camera).
export type Pose = { position: Vec3?, lookAt: Vec3?, fov: number? }

export type Offset = { x: number, y: number, z: number, pitch: number, yaw: number, roll: number }

export type ShakeShape = "decay" | "sustain" | "build"

export type ShakeDef = {
	amplitude: number, -- positional amplitude in studs at trauma 1
	rotation: number, -- rotational amplitude in degrees at trauma 1
	frequency: number, -- base noise frequency in Hz
	duration: number, -- seconds
	fadeIn: number, -- seconds
	fadeOut: number, -- seconds
	shape: ShakeShape, -- decay: impact that dies away; sustain: steady rumble; build: grows to a peak
	decay: number?, -- decay shape only: e-folds over the duration (default 3)
	bias: Vec3?, -- per-axis positional weight { x, y, z } (default 1, 1, 0.4)
	rotationBias: Vec3?, -- per-axis rotational weight { pitch, yaw, roll } (default 1, 1, 0.6)
}

export type Shake = {
	def: ShakeDef,
	seed: number,
	intensity: number, -- multiplier on both amplitudes (settings, distance, caller)
}

export type ShakeOptions = {
	intensity: number?,
	seed: number?,
	duration: number?,
	amplitude: number?,
	rotation: number?,
	frequency: number?,
	fadeIn: number?,
	fadeOut: number?,
}

local CameraLogic = {}

local TAU = 2 * math.pi

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerp3(a: Vec3, b: Vec3, t: number): Vec3
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

local function distance3(a: Vec3, b: Vec3): number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

CameraLogic.lerp3 = lerp3
CameraLogic.distance = distance3

-- Shake ---------------------------------------------------------------------------------------

local SHAKES: { [string]: ShakeDef } = {
	-- A light knock: coin pickups, small hits.
	SoftImpact = {
		amplitude = 0.18,
		rotation = 0.5,
		frequency = 14,
		duration = 0.28,
		fadeIn = 0,
		fadeOut = 0.1,
		shape = "decay",
	},
	-- The default hit.
	Impact = {
		amplitude = 0.4,
		rotation = 1.1,
		frequency = 16,
		duration = 0.4,
		fadeIn = 0,
		fadeOut = 0.14,
		shape = "decay",
	},
	-- Big, slower and longer: boss slams, chest drops.
	HeavyImpact = {
		amplitude = 0.85,
		rotation = 2.2,
		frequency = 11,
		duration = 0.7,
		fadeIn = 0,
		fadeOut = 0.25,
		shape = "decay",
		decay = 2.4,
	},
	-- Sustained low rumble; stop it through its handle or let the duration run out.
	Rumble = {
		amplitude = 0.12,
		rotation = 0.35,
		frequency = 9,
		duration = 2.5,
		fadeIn = 0.3,
		fadeOut = 0.45,
		shape = "sustain",
	},
	-- Barely there: UI confirmations that want a physical tick.
	Tap = {
		amplitude = 0.06,
		rotation = 0.18,
		frequency = 20,
		duration = 0.14,
		fadeIn = 0,
		fadeOut = 0.06,
		shape = "decay",
	},
	-- Builds to a peak for an egg about to hatch, then cuts quickly.
	Hatch = {
		amplitude = 0.3,
		rotation = 0.9,
		frequency = 15,
		duration = 1.4,
		fadeIn = 0.1,
		fadeOut = 0.12,
		shape = "build",
	},
	-- Mostly vertical: landing from a jump.
	Landing = {
		amplitude = 0.35,
		rotation = 0.8,
		frequency = 10,
		duration = 0.32,
		fadeIn = 0,
		fadeOut = 0.14,
		shape = "decay",
		bias = { 0.15, 1, 0.1 },
		rotationBias = { 1, 0.15, 0.2 },
	},
	-- Violent start with a long tail.
	Explosion = {
		amplitude = 1.1,
		rotation = 3,
		frequency = 18,
		duration = 0.9,
		fadeIn = 0,
		fadeOut = 0.4,
		shape = "decay",
		decay = 3.6,
	},
}

CameraLogic.SHAKE_NAMES = table.freeze({
	"SoftImpact",
	"Impact",
	"HeavyImpact",
	"Rumble",
	"Tap",
	"Hatch",
	"Landing",
	"Explosion",
})

-- Limits for the sum of all running shakes: studs per axis and degrees per axis.
CameraLogic.MAX_SHAKE_OFFSET = 2.5
CameraLogic.MAX_SHAKE_ROTATION = 8

function CameraLogic.shakeDef(name: string): ShakeDef?
	return SHAKES[name]
end

-- Problems with a shake definition (empty when valid).
function CameraLogic.validateShake(def: ShakeDef): { string }
	local problems: { string } = {}
	local function need(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	if type(def) ~= "table" then
		return { "shake must be a table" }
	end
	need(finite(def.amplitude) and def.amplitude >= 0, "amplitude must be 0 or more")
	need(finite(def.rotation) and def.rotation >= 0, "rotation must be 0 or more")
	need(finite(def.frequency) and def.frequency > 0, "frequency must be positive")
	need(finite(def.duration) and def.duration > 0, "duration must be positive")
	need(finite(def.fadeIn) and def.fadeIn >= 0, "fadeIn must be 0 or more")
	need(finite(def.fadeOut) and def.fadeOut >= 0, "fadeOut must be 0 or more")
	if finite(def.duration) and finite(def.fadeIn) and finite(def.fadeOut) then
		need(def.fadeIn + def.fadeOut <= def.duration + 1e-9, "fades must fit inside the duration")
	end
	need(def.shape == "decay" or def.shape == "sustain" or def.shape == "build", "unknown shape")
	return problems
end

-- Builds a shake from a preset name or a definition. `juice` is Host.juice("shake"): 0 under
-- reduced motion, which makes every sample zero.
function CameraLogic.makeShake(preset: string | ShakeDef, options: ShakeOptions?, juice: number?): Shake
	local base: ShakeDef
	if type(preset) == "string" then
		local found = SHAKES[preset]
		if found == nil then
			error("unknown camera shake: " .. tostring(preset), 2)
		end
		base = found
	else
		base = preset
	end
	local opts: ShakeOptions = options or {}
	local duration = math.max(0.01, opts.duration or base.duration)
	local fadeIn = math.max(0, opts.fadeIn or base.fadeIn)
	local fadeOut = math.max(0, opts.fadeOut or base.fadeOut)
	-- A shortened shake keeps its fades in proportion instead of overlapping them.
	local fades = fadeIn + fadeOut
	if fades > duration then
		fadeIn, fadeOut = fadeIn * duration / fades, fadeOut * duration / fades
	end
	local def: ShakeDef = {
		amplitude = math.max(0, opts.amplitude or base.amplitude),
		rotation = math.max(0, opts.rotation or base.rotation),
		frequency = math.max(0.1, opts.frequency or base.frequency),
		duration = duration,
		fadeIn = fadeIn,
		fadeOut = fadeOut,
		shape = base.shape,
		decay = base.decay,
		bias = base.bias,
		rotationBias = base.rotationBias,
	}
	local problems = CameraLogic.validateShake(def)
	if #problems > 0 then
		error("invalid camera shake: " .. table.concat(problems, "; "), 2)
	end
	local intensity = math.max(0, opts.intensity or 1) * math.max(0, juice or 1)
	return { def = def, seed = opts.seed or 0, intensity = intensity }
end

-- Trauma 0..1 at time t: the shake's energy before squaring.
function CameraLogic.trauma(shake: Shake, t: number): number
	local def = shake.def
	if t < 0 or t >= def.duration then
		return 0
	end
	local value = 1
	if def.shape == "decay" then
		value = math.exp(-(def.decay or 3) * t / def.duration)
	elseif def.shape == "build" then
		local rise = math.max(1e-6, def.duration - def.fadeOut)
		value = math.clamp(t / rise, 0, 1) ^ 1.5
	end
	if def.fadeIn > 0 then
		value *= math.clamp(t / def.fadeIn, 0, 1)
	end
	if def.fadeOut > 0 then
		value *= math.clamp((def.duration - t) / def.fadeOut, 0, 1)
	end
	return math.clamp(value, 0, 1)
end

-- Phase 0..TAU for one sine of one axis, hashed from the seed (no Random, so it is repeatable).
local function phase(seed: number, axis: number, octave: number): number
	local value = math.sin(seed * 12.9898 + axis * 78.233 + octave * 37.719) * 43758.5453
	return (value - math.floor(value)) * TAU
end

-- Smooth noise in -1..1: three sines at unrelated frequencies with per-axis phases.
function CameraLogic.noise(t: number, frequency: number, seed: number, axis: number): number
	local w = TAU * frequency * t
	return 0.5 * math.sin(w + phase(seed, axis, 1))
		+ 0.3 * math.sin(w * 2.17 + phase(seed, axis, 2))
		+ 0.2 * math.sin(w * 3.71 + phase(seed, axis, 3))
end

function CameraLogic.zeroOffset(): Offset
	return { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0 }
end

-- The camera offset of one shake at time t (seconds since it started).
function CameraLogic.sample(shake: Shake, t: number): Offset
	local trauma = CameraLogic.trauma(shake, t)
	local power = trauma * trauma * shake.intensity
	if power <= 0 then
		return CameraLogic.zeroOffset()
	end
	local def = shake.def
	local bias: Vec3 = def.bias or { 1, 1, 0.4 }
	local rotationBias: Vec3 = def.rotationBias or { 1, 1, 0.6 }
	local move = def.amplitude * power
	local turn = def.rotation * power
	local f, seed = def.frequency, shake.seed
	return {
		x = CameraLogic.noise(t, f, seed, 1) * move * bias[1],
		y = CameraLogic.noise(t, f, seed, 2) * move * bias[2],
		z = CameraLogic.noise(t, f, seed, 3) * move * bias[3],
		pitch = CameraLogic.noise(t, f, seed, 4) * turn * rotationBias[1],
		yaw = CameraLogic.noise(t, f, seed, 5) * turn * rotationBias[2],
		roll = CameraLogic.noise(t, f, seed, 6) * turn * rotationBias[3],
	}
end

-- Sums offsets and clamps each axis, so stacked explosions cannot throw the camera across the map.
function CameraLogic.combine(offsets: { Offset }, maxOffset: number?, maxRotation: number?): Offset
	local total = CameraLogic.zeroOffset()
	for _, offset in offsets do
		total.x += offset.x
		total.y += offset.y
		total.z += offset.z
		total.pitch += offset.pitch
		total.yaw += offset.yaw
		total.roll += offset.roll
	end
	local move = maxOffset or CameraLogic.MAX_SHAKE_OFFSET
	local turn = maxRotation or CameraLogic.MAX_SHAKE_ROTATION
	total.x = math.clamp(total.x, -move, move)
	total.y = math.clamp(total.y, -move, move)
	total.z = math.clamp(total.z, -move, move)
	total.pitch = math.clamp(total.pitch, -turn, turn)
	total.yaw = math.clamp(total.yaw, -turn, turn)
	total.roll = math.clamp(total.roll, -turn, turn)
	return total
end

function CameraLogic.isZero(offset: Offset): boolean
	return offset.x == 0
		and offset.y == 0
		and offset.z == 0
		and offset.pitch == 0
		and offset.yaw == 0
		and offset.roll == 0
end

-- Framing -------------------------------------------------------------------------------------

export type FocusOptions = {
	distance: number?, -- studs from the look-at point (default 12)
	angle: number?, -- yaw in degrees around the target; 0 is +Z, 90 is +X (default 0)
	elevation: number?, -- degrees above the horizon (default 15)
	height: number?, -- studs added to the target's y for the look-at point (default 0)
	fov: number?,
}

-- Places the camera `distance` studs from the target at the given yaw and elevation, looking at it.
function CameraLogic.focusPose(target: Vec3, options: FocusOptions?): Pose
	local opts: FocusOptions = options or {}
	local distance = math.max(0.1, opts.distance or 12)
	local yaw = math.rad(opts.angle or 0)
	local elevation = math.rad(math.clamp(opts.elevation or 15, -89, 89))
	local lookAt: Vec3 = { target[1], target[2] + (opts.height or 0), target[3] }
	local flat = math.cos(elevation) * distance
	local position: Vec3 = {
		lookAt[1] + math.sin(yaw) * flat,
		lookAt[2] + math.sin(elevation) * distance,
		lookAt[3] + math.cos(yaw) * flat,
	}
	return { position = position, lookAt = lookAt, fov = opts.fov }
end

export type OrbitOptions = FocusOptions & {
	speed: number?, -- degrees per second (default 20); negative orbits the other way
}

-- The yaw of an orbit after t seconds.
function CameraLogic.orbitAngle(options: OrbitOptions?, t: number): number
	local opts: OrbitOptions = options or {}
	return (opts.angle or 0) + (opts.speed or 20) * t
end

function CameraLogic.orbitPose(target: Vec3, options: OrbitOptions?, t: number): Pose
	local opts: OrbitOptions = options or {}
	local focus: FocusOptions = {
		distance = opts.distance,
		angle = CameraLogic.orbitAngle(opts, t),
		elevation = opts.elevation,
		height = opts.height,
		fov = opts.fov,
	}
	return CameraLogic.focusPose(target, focus)
end

-- Blends two poses. Missing fields inherit from the other pose, so a FOV-only pose over a full
-- pose changes only the FOV.
function CameraLogic.blendPose(under: Pose, over: Pose, weight: number): Pose
	local w = math.clamp(weight, 0, 1)
	local position = under.position
	if over.position then
		position = if under.position then lerp3(under.position, over.position, w) else over.position
	end
	local lookAt = under.lookAt
	if over.lookAt then
		lookAt = if under.lookAt then lerp3(under.lookAt, over.lookAt, w) else over.lookAt
	end
	local fov = under.fov
	if over.fov then
		fov = if under.fov then lerp(under.fov, over.fov, w) else over.fov
	end
	return { position = position, lookAt = lookAt, fov = fov }
end

-- Pose `alpha` of the way from one pose to another with an easing curve.
function CameraLogic.panPose(from: Pose, to: Pose, alpha: number, easing: (string | Curves.Curve)?): Pose
	local eased = Curves.ease(easing or "sineInOut", math.clamp(alpha, 0, 1))
	return CameraLogic.blendPose(from, to, eased)
end

-- Moves the camera along its view line: factor 2 halves the distance to the look-at point.
function CameraLogic.zoomPose(pose: Pose, factor: number): Pose
	local position, lookAt = pose.position, pose.lookAt
	if position == nil or lookAt == nil then
		return pose
	end
	local k = 1 / math.max(0.01, factor)
	return { position = lerp3(lookAt, position, k), lookAt = lookAt, fov = pose.fov }
end

-- The field of view that magnifies the picture by `factor` (2 = twice as large), clamped to the
-- range Roblox accepts.
function CameraLogic.zoomFov(fov: number, factor: number): number
	local half = math.rad(math.clamp(fov, 1, 120)) / 2
	local zoomed = 2 * math.atan(math.tan(half) / math.max(0.01, factor))
	return math.clamp(math.deg(zoomed), 1, 120)
end

-- Distance at which a sphere of `radius` fits the view: `fov` is the vertical field of view in
-- degrees, `aspect` is width / height, `padding` (default 1.1) leaves a margin.
function CameraLogic.fitDistance(radius: number, fov: number, aspect: number?, padding: number?): number
	local vertical = math.rad(math.clamp(fov, 1, 120)) / 2
	local ratio = math.max(0.05, aspect or 1)
	local horizontal = math.atan(math.tan(vertical) * ratio)
	local half = math.min(vertical, horizontal)
	return math.max(0, radius) * (padding or 1.1) / math.sin(half)
end

-- Stack ---------------------------------------------------------------------------------------

-- A fixed pose, or a function of the entry's age and the pose beneath it (for relative moves).
export type PoseSource = Pose | (age: number, under: Pose) -> Pose

export type EntrySpec = {
	priority: number?, -- higher wins (default 0)
	blendIn: number?, -- seconds (default 0.4)
	blendOut: number?, -- seconds (default 0.4)
	duration: number?, -- seconds before it ends on its own; nil holds until removed
	takeover: boolean?, -- true when the move positions the camera (false for FOV-only moves)
	easing: (string | Curves.Curve)?, -- blend curve (default sineInOut)
	pose: PoseSource,
}

type Entry = {
	id: number,
	order: number,
	priority: number,
	blendIn: number,
	blendOut: number,
	duration: number?,
	takeover: boolean,
	easing: string | Curves.Curve,
	pose: PoseSource,
	age: number,
	weight: number,
	ending: boolean,
	replacedBy: number?,
}

export type StackResult = {
	pose: Pose,
	active: boolean, -- any entry alive
	takeover: boolean, -- any living entry positions the camera
	finished: { number }, -- ids that ended during this step
}

export type Stack = {
	push: (self: Stack, spec: EntrySpec) -> number,
	remove: (self: Stack, id: number, immediate: boolean?) -> boolean,
	finish: (self: Stack, id: number) -> boolean,
	has: (self: Stack, id: number) -> boolean,
	isEnding: (self: Stack, id: number) -> boolean,
	top: (self: Stack) -> number?,
	count: (self: Stack) -> number,
	hasTakeover: (self: Stack) -> boolean,
	clear: (self: Stack) -> { number },
	step: (self: Stack, dt: number, base: Pose) -> StackResult,
	-- Restoration: remember the first value seen for a key, hand everything back once.
	save: (self: Stack, key: string, value: any) -> (),
	saved: (self: Stack, key: string) -> any,
	release: (self: Stack, keys: { string }?) -> { [string]: any },
}

local function resolvePose(source: PoseSource, age: number, under: Pose): Pose
	if type(source) == "function" then
		return source(age, under)
	end
	return source
end

function CameraLogic.newStack(): Stack
	local entries: { Entry } = {}
	local nextId = 0
	local stored: { [string]: any } = {}
	local self: Stack

	local function find(id: number): (Entry?, number?)
		for index, entry in entries do
			if entry.id == id then
				return entry, index
			end
		end
		return nil, nil
	end

	local function sort()
		table.sort(entries, function(a: Entry, b: Entry): boolean
			return if a.priority == b.priority then a.order < b.order else a.priority < b.priority
		end)
	end

	local function push(_self: Stack, spec: EntrySpec): number
		nextId += 1
		local entry: Entry = {
			id = nextId,
			order = nextId,
			priority = spec.priority or 0,
			blendIn = math.max(0, spec.blendIn or 0.4),
			blendOut = math.max(0, spec.blendOut or 0.4),
			duration = spec.duration,
			takeover = spec.takeover ~= false,
			easing = spec.easing or "sineInOut",
			pose = spec.pose,
			age = 0,
			weight = 0,
			ending = false,
			replacedBy = nil,
		}
		-- Equal priority replaces: the old move stays underneath at full weight while the new one
		-- blends in over it (no jump), then it is dropped.
		for _, other in entries do
			if other.priority == entry.priority and other.replacedBy == nil and other.takeover == entry.takeover then
				other.replacedBy = entry.id
			end
		end
		table.insert(entries, entry)
		sort()
		return entry.id
	end

	local function remove(_self: Stack, id: number, immediate: boolean?): boolean
		local entry, index = find(id)
		if entry == nil or index == nil then
			return false
		end
		if immediate or entry.blendOut <= 0 or entry.weight <= 0 then
			table.remove(entries, index)
		else
			entry.ending = true
		end
		return true
	end

	local function step(_self: Stack, dt: number, base: Pose): StackResult
		local delta = math.max(0, dt)
		local finished: { number } = {}
		-- Advance ages and weights.
		for _, entry in entries do
			entry.age += delta
			if entry.duration and entry.age >= entry.duration and not entry.ending then
				entry.ending = true
				if entry.blendOut <= 0 then
					entry.weight = 0
				end
			end
			if entry.ending then
				entry.weight = if entry.blendOut > 0 then math.max(0, entry.weight - delta / entry.blendOut) else 0
			else
				entry.weight = if entry.blendIn > 0 then math.min(1, entry.weight + delta / entry.blendIn) else 1
			end
		end
		-- Drop entries that faded out, and replaced entries once their replacement covers them.
		for index = #entries, 1, -1 do
			local entry = entries[index]
			local gone = entry.ending and entry.weight <= 0
			if not gone and entry.replacedBy then
				local replacement = find(entry.replacedBy)
				gone = replacement == nil or (replacement.weight >= 1 and not replacement.ending)
				-- A replacement that was removed again hands the camera back to this entry's
				-- level, which then fades out normally.
				if replacement == nil and entry.weight > 0 then
					gone = false
					entry.replacedBy = nil
					entry.ending = true
				end
			end
			if gone then
				table.insert(finished, entry.id)
				table.remove(entries, index)
			end
		end
		-- Fold: lowest priority first, each entry blended over what is beneath it.
		local pose: Pose = { position = base.position, lookAt = base.lookAt, fov = base.fov }
		local takeover = false
		for _, entry in entries do
			local weight = Curves.ease(entry.easing, entry.weight)
			pose = CameraLogic.blendPose(pose, resolvePose(entry.pose, entry.age, pose), weight)
			takeover = takeover or entry.takeover
		end
		return { pose = pose, active = #entries > 0, takeover = takeover, finished = finished }
	end

	self = {
		push = push,
		remove = remove,
		-- Ends a timed entry now: it starts blending out as if its duration had run out.
		finish = function(_self: Stack, id: number): boolean
			local entry = find(id)
			if entry == nil then
				return false
			end
			if entry.duration then
				entry.age = math.max(entry.age, entry.duration)
			end
			entry.ending = true
			return true
		end,
		has = function(_self: Stack, id: number): boolean
			return find(id) ~= nil
		end,
		isEnding = function(_self: Stack, id: number): boolean
			local entry = find(id)
			return entry ~= nil and entry.ending
		end,
		top = function(_self: Stack): number?
			local last = entries[#entries]
			return if last then last.id else nil
		end,
		count = function(_self: Stack): number
			return #entries
		end,
		hasTakeover = function(_self: Stack): boolean
			for _, entry in entries do
				if entry.takeover then
					return true
				end
			end
			return false
		end,
		clear = function(_self: Stack): { number }
			local ids: { number } = {}
			for _, entry in entries do
				table.insert(ids, entry.id)
			end
			table.clear(entries)
			return ids
		end,
		step = step,
		save = function(_self: Stack, key: string, value: any)
			if stored[key] == nil then
				stored[key] = { value = value }
			end
		end,
		saved = function(_self: Stack, key: string): any
			local slot = stored[key]
			return if slot then slot.value else nil
		end,
		release = function(_self: Stack, keys: { string }?): { [string]: any }
			local out: { [string]: any } = {}
			if keys then
				for _, key in keys do
					local slot = stored[key]
					if slot then
						out[key] = slot.value
						stored[key] = nil
					end
				end
				return out
			end
			for key, slot in stored do
				out[key] = slot.value
			end
			table.clear(stored)
			return out
		end,
	}
	return self
end

-- FOV punch: a quick kick that springs back. Returns the FOV delta at time t.
function CameraLogic.punchFov(amount: number, t: number, duration: number): number
	if t <= 0 or t >= duration then
		return 0
	end
	local alpha = t / duration
	-- Fast attack over the first 18%, then a damped return with one small counter-swing.
	if alpha < 0.18 then
		return amount * Curves.ease("quadOut", alpha / 0.18)
	end
	local rest = (alpha - 0.18) / 0.82
	return amount * math.exp(-4.2 * rest) * math.cos(rest * math.pi * 1.5) * (1 - rest)
end

-- Cinematics ----------------------------------------------------------------------------------

export type Key = {
	time: number, -- seconds from the start
	distance: number?, -- multiplier on the base distance (default: previous key)
	angle: number?, -- degrees added to the base yaw
	elevation: number?, -- degrees added to the base elevation
	fov: number?, -- multiplier on the base field of view
	easing: string?, -- curve used to arrive at this key (default sineInOut)
}

export type Cinematic = {
	duration: number, -- seconds, including the hold after the last key
	takeover: boolean, -- false: FOV only, the game camera keeps control
	blendIn: number,
	blendOut: number,
	base: FocusOptions, -- framing the keys are relative to
	keys: { Key },
	markers: { [string]: number }?, -- named moments (seconds), for example "reveal"
	settle: number?, -- index of the key shown under reduced motion (default: the last key)
}

local CINEMATICS: { [string]: Cinematic } = {
	-- Push in on a pet with a slight orbit and a tightening lens; "reveal" is the beat to pop VFX.
	PetReveal = {
		duration = 2.6,
		takeover = true,
		blendIn = 0.55,
		blendOut = 0.6,
		base = { distance = 11, angle = 0, elevation = 12, height = 0.4 },
		keys = {
			{ time = 0, distance = 1.35, angle = -14, elevation = 6, fov = 1 },
			{ time = 1.15, distance = 0.95, angle = -3, elevation = 0, fov = 0.93, easing = "quintOut" },
			{ time = 1.45, distance = 0.78, angle = 2, elevation = -2, fov = 0.84, easing = "cubicIn" },
			{ time = 2.3, distance = 0.82, angle = 9, elevation = -2, fov = 0.88, easing = "quintOut" },
		},
		markers = { reveal = 1.45 },
		settle = 4,
	},
	-- Gentle dolly toward a reward with an FOV punch on the reveal.
	RewardReveal = {
		duration = 2.1,
		takeover = true,
		blendIn = 0.45,
		blendOut = 0.5,
		base = { distance = 10, angle = 0, elevation = 10, height = 0 },
		keys = {
			{ time = 0, distance = 1.2, angle = 0, elevation = 2, fov = 1 },
			{ time = 0.9, distance = 1, angle = 0, elevation = 0, fov = 0.96, easing = "sineInOut" },
			{ time = 1.02, distance = 0.97, angle = 0, elevation = 0, fov = 1.1, easing = "quadOut" },
			{ time = 1.75, distance = 0.92, angle = 0, elevation = 0, fov = 0.94, easing = "quintOut" },
		},
		markers = { reveal = 0.9 },
		settle = 4,
	},
	-- Rise above the player, sweep toward the new area, hold, then hand the camera back.
	AreaUnlock = {
		duration = 4.2,
		takeover = true,
		blendIn = 0.9,
		blendOut = 0.9,
		base = { distance = 46, angle = 0, elevation = 24, height = 2 },
		keys = {
			{ time = 0, distance = 1.7, angle = -28, elevation = 22, fov = 1 },
			{ time = 1.5, distance = 1.25, angle = -10, elevation = 10, fov = 0.97, easing = "sineInOut" },
			{ time = 3, distance = 1, angle = 6, elevation = 0, fov = 0.92, easing = "quintOut" },
			{ time = 3.7, distance = 0.98, angle = 9, elevation = 0, fov = 0.92, easing = "sineInOut" },
		},
		markers = { arrive = 3 },
		settle = 3,
	},
	-- FOV only: stretch out, snap in at the jump, settle. The game camera keeps control, so it
	-- follows the character to the destination.
	Teleport = {
		duration = 0.95,
		takeover = false,
		blendIn = 0,
		blendOut = 0.2,
		base = {},
		keys = {
			{ time = 0, fov = 1 },
			{ time = 0.32, fov = 1.28, easing = "quadIn" },
			{ time = 0.4, fov = 0.82, easing = "quintOut" },
			{ time = 0.85, fov = 1, easing = "backOut" },
		},
		markers = { jump = 0.32 },
		settle = 1,
	},
}

CameraLogic.CINEMATIC_NAMES = table.freeze({ "PetReveal", "RewardReveal", "AreaUnlock", "Teleport" })

function CameraLogic.cinematic(name: string): Cinematic?
	return CINEMATICS[name]
end

-- Problems with a cinematic recipe (empty when valid).
function CameraLogic.validateCinematic(recipe: Cinematic): { string }
	local problems: { string } = {}
	local function need(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	if type(recipe) ~= "table" or type(recipe.keys) ~= "table" then
		return { "cinematic must be a table with keys" }
	end
	need(finite(recipe.duration) and recipe.duration > 0, "duration must be positive")
	need(finite(recipe.blendIn) and recipe.blendIn >= 0, "blendIn must be 0 or more")
	need(finite(recipe.blendOut) and recipe.blendOut >= 0, "blendOut must be 0 or more")
	need(#recipe.keys >= 2, "at least two keys")
	local previous = -1
	for index, key in recipe.keys do
		local label = "key " .. tostring(index)
		if not finite(key.time) then
			table.insert(problems, label .. ": time required")
			continue
		end
		need(key.time > previous, label .. ": times must increase")
		need(key.time <= recipe.duration + 1e-9, label .. ": after the end")
		need(key.easing == nil or Curves.has(key.easing), label .. ": unknown easing")
		need(key.distance == nil or (finite(key.distance) and key.distance > 0), label .. ": distance must be positive")
		need(
			key.fov == nil or (finite(key.fov) and key.fov > 0.2 and key.fov < 3),
			label .. ": fov multiplier out of range"
		)
		if not recipe.takeover then
			need(
				key.distance == nil and key.angle == nil and key.elevation == nil,
				label .. ": FOV-only recipes may only key fov"
			)
		end
		previous = key.time
	end
	if recipe.keys[1] and finite(recipe.keys[1].time) then
		need(recipe.keys[1].time == 0, "first key must be at time 0")
	end
	if recipe.settle then
		need(recipe.keys[recipe.settle] ~= nil, "settle must index a key")
	end
	local markers: { [string]: number } = recipe.markers or {}
	for name, at in markers do
		need(finite(at) and at >= 0 and at <= recipe.duration, "marker " .. tostring(name) .. " outside the duration")
	end
	return problems
end

export type KeyState = { distance: number, angle: number, elevation: number, fov: number }

local function keyState(recipe: Cinematic, index: number): KeyState
	-- A field a key leaves out carries over from the nearest earlier key that set it.
	local state: KeyState = { distance = 1, angle = 0, elevation = 0, fov = 1 }
	for i = 1, index do
		local key = recipe.keys[i]
		state.distance = key.distance or state.distance
		state.angle = key.angle or state.angle
		state.elevation = key.elevation or state.elevation
		state.fov = key.fov or state.fov
	end
	return state
end

-- The interpolated key values at time t. Under `reduced` it is the settle key throughout, so the
-- camera cuts to the final framing instead of travelling.
function CameraLogic.cinematicState(recipe: Cinematic, t: number, reduced: boolean?): KeyState
	local keys = recipe.keys
	if reduced then
		local state = keyState(recipe, recipe.settle or #keys)
		if not recipe.takeover then
			state.fov = 1
		end
		return state
	end
	if t <= keys[1].time then
		return keyState(recipe, 1)
	end
	for index = 2, #keys do
		local key = keys[index]
		if t < key.time then
			local before = keyState(recipe, index - 1)
			local after = keyState(recipe, index)
			local span = key.time - keys[index - 1].time
			local alpha = Curves.ease(key.easing or "sineInOut", (t - keys[index - 1].time) / span)
			return {
				distance = lerp(before.distance, after.distance, alpha),
				angle = lerp(before.angle, after.angle, alpha),
				elevation = lerp(before.elevation, after.elevation, alpha),
				fov = lerp(before.fov, after.fov, alpha),
			}
		end
	end
	return keyState(recipe, #keys)
end

export type CinematicFraming = {
	distance: number?, -- base distance override (for example from fitDistance)
	angle: number?, -- base yaw: usually the direction the player is looking from
	elevation: number?,
	height: number?,
	fov: number, -- the camera's field of view when the cinematic started
}

-- The pose of a cinematic at time t around `target`.
function CameraLogic.cinematicPose(
	recipe: Cinematic,
	target: Vec3,
	framing: CinematicFraming,
	t: number,
	reduced: boolean?
): Pose
	local state = CameraLogic.cinematicState(recipe, t, reduced)
	local fov = math.clamp(framing.fov * state.fov, 1, 120)
	if not recipe.takeover then
		return { fov = fov }
	end
	local base = recipe.base
	local focus: FocusOptions = {
		distance = (framing.distance or base.distance or 12) * state.distance,
		angle = (framing.angle or base.angle or 0) + state.angle,
		elevation = (framing.elevation or base.elevation or 15) + state.elevation,
		height = framing.height or base.height or 0,
		fov = fov,
	}
	return CameraLogic.focusPose(target, focus)
end

-- Blend and travel times under reduced motion: quick crossfades instead of long moves.
function CameraLogic.reducedBlend(seconds: number): number
	return math.min(seconds, 0.12)
end

-- Registry ------------------------------------------------------------------------------------

local registry = Registry.new("camera")
CameraLogic.registry = registry

local SHAKE_PARAMS: { [string]: Registry.Param } = {
	intensity = { type = "number", default = 1, min = 0, max = 3, description = "Multiplier on both amplitudes" },
	duration = { type = "number", default = 0, min = 0, max = 30, description = "Seconds; 0 keeps the preset's" },
	seed = { type = "number", default = 0, description = "Changes the noise pattern" },
}

local SHAKE_TEXT: { [string]: { string } } = {
	SoftImpact = { "Soft impact", "A light knock for pickups and small hits." },
	Impact = { "Impact", "The default hit shake: sharp start, quick decay." },
	HeavyImpact = { "Heavy impact", "Slow, large shake for slams and heavy drops." },
	Rumble = { "Rumble", "Sustained low rumble that fades in and out; stop it through its handle." },
	Tap = { "Tap", "A tiny tick for confirmations that should feel physical." },
	Hatch = { "Hatch", "Builds to a peak and cuts, for an egg about to hatch." },
	Landing = { "Landing", "Mostly vertical jolt for landing from a jump." },
	Explosion = { "Explosion", "Violent start with a long tail." },
}

for _, name in CameraLogic.SHAKE_NAMES do
	local def = SHAKES[name]
	local text = SHAKE_TEXT[name]
	registry:register({
		id = name,
		name = text[1],
		category = "shake",
		description = text[2],
		params = SHAKE_PARAMS,
		quality = { min = "Low", cost = "low" },
		usage = string.format('Visuals.Camera.shake("%s")', name),
		tags = { "shake", def.shape },
		preview = { duration = def.duration },
		data = { kind = "shake", shake = def },
	})
end

local CINEMATIC_PARAMS: { [string]: Registry.Param } = {
	distance = { type = "number", default = 0, min = 0, max = 500, description = "Base distance; 0 fits the target" },
	angle = { type = "number", default = 0, min = -360, max = 360, description = "Base yaw in degrees" },
	priority = { type = "number", default = 10, description = "Stack priority" },
}

local CINEMATIC_TEXT: { [string]: { string } } = {
	PetReveal = { "Pet reveal", "Push in on a pet with a slight orbit and a tightening lens." },
	RewardReveal = { "Reward reveal", "Gentle dolly toward a reward with an FOV punch on the reveal." },
	AreaUnlock = { "Area unlock", "Rise, sweep toward a newly unlocked area, hold, then return the camera." },
	Teleport = { "Teleport", "FOV stretch, snap and settle around a teleport; the game camera keeps control." },
}

for _, name in CameraLogic.CINEMATIC_NAMES do
	local recipe = CINEMATICS[name]
	local text = CINEMATIC_TEXT[name]
	registry:register({
		id = name,
		name = text[1],
		category = "cinematic",
		description = text[2],
		params = CINEMATIC_PARAMS,
		quality = { min = "Low", cost = "low" },
		usage = string.format('Visuals.Camera.cinematic("%s", target)', name),
		tags = { "cinematic", if recipe.takeover then "takeover" else "fov" },
		preview = { duration = recipe.duration },
		data = { kind = "cinematic", cinematic = recipe },
	})
end

local MOVES: { { string } } = {
	{
		"Focus",
		"Focus",
		"Hold the camera at a distance, yaw and elevation from a target, looking at it.",
		"focus(target)",
	},
	{ "Orbit", "Orbit", "Circle a target at a steady speed until stopped.", "orbit(target, { speed = 20 })" },
	{ "Pan", "Pan", "Travel from one camera CFrame to another with easing.", "pan(fromCFrame, toCFrame)" },
	{
		"Zoom",
		"Zoom",
		"Magnify the view by a factor through the field of view; the game camera keeps control.",
		"zoom(1.5)",
	},
	{ "Fov", "Field of view", "Ease the field of view to a value until stopped.", "fov(50)" },
	{
		"PunchFov",
		"FOV punch",
		"A quick field-of-view kick that springs back; skipped under reduced motion.",
		"punchFov(6)",
	},
}

for _, move in MOVES do
	registry:register({
		id = move[1],
		name = move[2],
		category = "move",
		description = move[3],
		quality = { min = "Low", cost = "low" },
		usage = "Visuals.Camera." .. move[4],
		tags = { "move" },
		data = { kind = "move" },
	})
end

return CameraLogic
