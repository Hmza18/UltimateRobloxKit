--!strict
-- Pet animation maths (pure Luau; no Roblox globals). Positions are { x, y, z } arrays, angles
-- are degrees. Pets/Pets.luau turns the results into one PivotTo per pet update.
--
--   idle         float bob + breathing squash + gentle sway, phased per pet, scaled by pet size
--   reactions    HappyReaction, CuriousReaction, SelectBounce, HoverReaction samplers
--   formation    slots behind / around an owner: rows, arc, circle, orbit
--   follow       critically damped spring toward a slot, speed limit, teleport when too far,
--                turn smoothing, walk bob
--   ground       y offset and tilt from a ground height and normal, hover height for flying pets
--   scheduler    round-robin buckets so many pets do not all update on the same frame
--   plans        Spawn / Despawn / Equip / Unequip / Evolve / Upgrade timelines (which VFX, which
--                animation, when)
--
-- Local space for offsets: x is the pet's (or owner's) right, y is up, z is behind (Roblox looks
-- down -z). Rotation is { pitch, yaw, roll }.

local Curves = require("../Core/Curves")
local ObjectsLogic = require("../Objects/ObjectsLogic")
local Registry = require("../Core/Registry")
local Springs = require("../Core/Springs")

export type Vec3 = { number }

export type Offset = {
	position: Vec3,
	rotation: Vec3, -- pitch, yaw, roll in degrees
	scale: Vec3, -- multipliers; squash and stretch keeps volume
	done: boolean,
}

local PetsLogic = {}

local TAU = 2 * math.pi

local function rest(): Offset
	return { position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, scale = { 1, 1, 1 }, done = false }
end

PetsLogic.rest = rest

local function ease(name: string, t: number): number
	return Curves.ease(name, math.clamp(t, 0, 1))
end

local function number(value: any, default: number): number
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return default
end

-- A phase 0..1 for the index-th pet, spread by the golden ratio so neighbours never move together.
function PetsLogic.phaseFor(index: number): number
	local value = index * 0.61803398875
	return value - math.floor(value)
end

-- Idle ----------------------------------------------------------------------------------------

export type IdleOptions = {
	phase: number?, -- 0..1
	radius: number?, -- the pet's bounding radius in studs (default 1)
	speed: number?, -- bob cycles per second (default 0.55)
	bob: number?, -- multiplier on the bob height (default 1)
	breathe: number?, -- multiplier on the breathing squash (default 1; 0 turns it off)
	sway: number?, -- multiplier on the yaw / roll sway (default 1)
}

-- Bob height in studs for a pet of this size: bigger pets move more, within limits.
function PetsLogic.bobHeight(radius: number?): number
	return math.clamp(number(radius, 1) * 0.12, 0.04, 0.6)
end

-- Seconds after which the idle repeats exactly.
function PetsLogic.idlePeriod(options: IdleOptions?): number
	local speed = math.max(0.01, number(options and options.speed, 0.55))
	return 2 / speed
end

-- The idle offset at time t: centred on rest, periodic, different for every phase.
function PetsLogic.idle(t: number, options: IdleOptions?): Offset
	local opts: IdleOptions = options or {}
	local speed = math.max(0.01, number(opts.speed, 0.55))
	local phase = number(opts.phase, 0)
	local angle = TAU * (t * speed + phase)
	local sway = number(opts.sway, 1)
	local out = rest()
	out.position[2] = PetsLogic.bobHeight(opts.radius) * number(opts.bob, 1) * math.sin(angle)
	-- Breathing leads the bob by a quarter cycle: the pet swells as it starts to rise.
	out.scale = ObjectsLogic.squash(1 + 0.025 * number(opts.breathe, 1) * math.sin(angle + math.pi / 2))
	-- Sway at half the bob rate, so the two never line up into a mechanical loop.
	out.rotation[2] = 6 * sway * math.sin(angle / 2 + phase * TAU)
	out.rotation[3] = 1.5 * sway * math.sin(angle)
	return out
end

-- Reactions -----------------------------------------------------------------------------------

export type ReactionOptions = {
	radius: number?, -- the pet's bounding radius (default 1)
	direction: Vec3?, -- CuriousReaction: local direction to lean toward (default forward)
	intensity: number?, -- multiplier on heights, tilts and squash (default 1)
}

type Resolved = { radius: number, direction: Vec3, intensity: number }

type ReactionDef = {
	name: string,
	description: string,
	duration: number,
	sample: (u: number, p: Resolved) -> Offset,
}

-- Smooth interpolation through { u, value } keys.
local function track(keys: { { number } }, u: number): number
	if u <= keys[1][1] then
		return keys[1][2]
	end
	for index = 2, #keys do
		local key = keys[index]
		if u < key[1] then
			local before = keys[index - 1]
			local alpha = (u - before[1]) / (key[1] - before[1])
			local smooth = alpha * alpha * (3 - 2 * alpha)
			return before[2] + (key[2] - before[2]) * smooth
		end
	end
	return keys[#keys][2]
end

-- 0 outside from..to, a parabola peaking at 1 between.
local function hop(u: number, from: number, to: number): number
	if u <= from or u >= to then
		return 0
	end
	local v = (u - from) / (to - from)
	return 4 * v * (1 - v)
end

local HAPPY_STRETCH = {
	{ 0, 1 },
	{ 0.1, 0.8 }, -- anticipation squash
	{ 0.17, 1.18 }, -- stretch on take-off
	{ 0.29, 1 },
	{ 0.42, 1.1 },
	{ 0.49, 0.84 }, -- landing
	{ 0.56, 1.14 }, -- second take-off
	{ 0.65, 1 },
	{ 0.75, 1.07 },
	{ 0.81, 0.88 }, -- landing
	{ 0.9, 1.04 }, -- follow-through
	{ 1, 1 },
}

local SELECT_STRETCH = { { 0, 1 }, { 0.18, 0.82 }, { 0.4, 1.18 }, { 0.62, 0.95 }, { 0.8, 1.03 }, { 1, 1 } }

local function strength(curve: number, intensity: number): number
	return 1 + (curve - 1) * intensity
end

local REACTIONS: { [string]: ReactionDef } = {
	HappyReaction = {
		name = "Happy reaction",
		description = "Two quick hops with squash and stretch and a full spin; the pet lands where it started.",
		duration = 0.9,
		sample = function(u: number, p: Resolved): Offset
			local out = rest()
			out.position[2] = p.radius * p.intensity * (0.9 * hop(u, 0.12, 0.48) + 0.55 * hop(u, 0.5, 0.8))
			out.scale = ObjectsLogic.squash(strength(track(HAPPY_STRETCH, u), p.intensity))
			if p.intensity > 0 then
				out.rotation[2] = 360 * ease("sineInOut", (u - 0.12) / 0.68)
			end
			return out
		end,
	},
	CuriousReaction = {
		name = "Curious reaction",
		description = "Tilts its head and leans toward a point, holds, then eases back.",
		duration = 1.1,
		sample = function(u: number, p: Resolved): Offset
			local out = rest()
			local weight: number
			if u <= 0 then
				weight = 0
			elseif u < 0.25 then
				weight = ease("backOut", u / 0.25)
			elseif u < 0.7 then
				-- A slow breath while it looks, so the hold is not frozen.
				weight = 1 + 0.04 * math.sin((u - 0.25) / 0.45 * math.pi)
			else
				weight = 1 - ease("sineInOut", (u - 0.7) / 0.3)
			end
			local amount = weight * p.intensity
			local lean = p.radius * 0.3 * amount
			out.position[1] = p.direction[1] * lean
			out.position[2] = p.radius * 0.08 * amount
			out.position[3] = p.direction[3] * lean
			out.rotation[1] = -8 * amount
			out.rotation[3] = 14 * amount
			return out
		end,
	},
	SelectBounce = {
		name = "Select bounce",
		description = "A squash, a springy pop upward and a settle: the answer to being picked.",
		duration = 0.45,
		sample = function(u: number, p: Resolved): Offset
			local out = rest()
			out.position[2] = p.radius * 0.35 * p.intensity * hop(u, 0.18, 0.68)
			out.scale = ObjectsLogic.squash(strength(track(SELECT_STRETCH, u), p.intensity))
			return out
		end,
	},
	HoverReaction = {
		name = "Hover reaction",
		description = "Lifts and grows a little while the pointer or focus is on it, then comes back down.",
		duration = 0.5,
		sample = function(u: number, p: Resolved): Offset
			local out = rest()
			local weight = math.sin(math.pi * math.clamp(u, 0, 1)) * p.intensity
			out.position[2] = p.radius * 0.25 * weight
			local k = 1 + 0.08 * weight
			out.scale = { k, k, k }
			return out
		end,
	},
}

PetsLogic.REACTIONS = table.freeze({ "HappyReaction", "CuriousReaction", "SelectBounce", "HoverReaction" })

function PetsLogic.isReaction(id: string): boolean
	return REACTIONS[id] ~= nil
end

function PetsLogic.reactionDuration(id: string): number
	local def = REACTIONS[id]
	if def == nil then
		error("unknown pet reaction: " .. tostring(id), 2)
	end
	return def.duration
end

-- The offset of reaction `id` at time t. At and after its duration it is exactly rest, done = true.
function PetsLogic.reaction(id: string, t: number, options: ReactionOptions?): Offset
	local def = REACTIONS[id]
	if def == nil then
		error("unknown pet reaction: " .. tostring(id), 2)
	end
	if t >= def.duration then
		local out = rest()
		out.done = true
		return out
	end
	local opts: ReactionOptions = options or {}
	local direction = opts.direction or { 0, 0, -1 }
	local dx, dz = number(direction[1], 0), number(direction[3], -1)
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		dx, dz, length = 0, -1, 1
	end
	local resolved: Resolved = {
		radius = math.max(0.05, number(opts.radius, 1)),
		direction = { dx / length, 0, dz / length },
		intensity = math.max(0, number(opts.intensity, 1)),
	}
	return def.sample(math.max(0, t) / def.duration, resolved)
end

-- The held hover pose for a weight 0..1 (spring the weight toward 1 while hovered).
function PetsLogic.hoverPose(weight: number, radius: number?): Offset
	local out = rest()
	out.position[2] = number(radius, 1) * 0.25 * weight
	local k = 1 + 0.08 * weight
	out.scale = { k, k, k }
	return out
end

-- Adds offsets: positions and rotations sum, scales multiply.
function PetsLogic.combine(offsets: { Offset }): Offset
	local out = rest()
	for _, offset in offsets do
		for i = 1, 3 do
			out.position[i] += offset.position[i]
			out.rotation[i] += offset.rotation[i]
			out.scale[i] *= offset.scale[i]
		end
	end
	return out
end

-- Models can only scale uniformly. A uniform scale passes through; a squash becomes a damped
-- vertical scale, which the runtime pairs with a shift that keeps the feet planted.
function PetsLogic.uniformScale(scale: Vec3): number
	if math.abs(scale[1] - scale[2]) < 1e-6 and math.abs(scale[3] - scale[2]) < 1e-6 then
		return scale[2]
	end
	return 1 + (scale[2] - 1) * 0.6
end

-- Formation -----------------------------------------------------------------------------------

export type FormationMode = "rows" | "arc" | "circle" | "orbit"

export type FormationOptions = {
	radius: number?, -- pet bounding radius (default 1)
	spacing: number?, -- centre-to-centre distance (default radius * 2.6)
	distance: number?, -- how far behind the owner the first slot is (default max(3, radius + 2.5))
	perRow: number?, -- rows mode: pets per row (default grows with the count, up to 5)
	time: number?, -- orbit mode: seconds
	orbitSpeed: number?, -- orbit mode: degrees per second (default 30)
}

PetsLogic.MODES = table.freeze({ "rows", "arc", "circle", "orbit" })

function PetsLogic.isMode(mode: any): boolean
	return mode == "rows" or mode == "arc" or mode == "circle" or mode == "orbit"
end

function PetsLogic.spacing(options: FormationOptions?): number
	local opts: FormationOptions = options or {}
	return math.max(0.5, number(opts.spacing, math.max(0.05, number(opts.radius, 1)) * 2.6))
end

local ARC_SPAN = math.rad(150)

-- Slots for `count` pets in owner-local space ({ x, 0, z }, z positive behind the owner). Slot i
-- always belongs to pet i, so pets keep their place when the count or the frame changes.
function PetsLogic.formation(mode: FormationMode, count: number, options: FormationOptions?): { Vec3 }
	local opts: FormationOptions = options or {}
	local n = math.max(0, math.floor(count))
	local radius = math.max(0.05, number(opts.radius, 1))
	local spacing = PetsLogic.spacing(opts)
	local distance = math.max(0, number(opts.distance, math.max(3, radius + 2.5)))
	local slots: { Vec3 } = {}
	if n == 0 then
		return slots
	end
	if mode == "rows" then
		local perRow = math.floor(number(opts.perRow, math.clamp(math.ceil(math.sqrt(n * 1.5)), 1, 5)))
		perRow = math.max(1, perRow)
		for index = 0, n - 1 do
			local row = index // perRow
			local inRow = math.min(perRow, n - row * perRow)
			local column = index - row * perRow
			table.insert(slots, { (column - (inRow - 1) / 2) * spacing, 0, distance + row * spacing })
		end
		return slots
	elseif mode == "arc" then
		local remaining = n
		local ring = 0
		while remaining > 0 do
			local ringRadius = math.max(distance, spacing * 0.75) + ring * spacing
			local step = 2 * math.asin(math.min(1, spacing / (2 * ringRadius)))
			local capacity = math.max(1, math.floor(ARC_SPAN / step) + 1)
			local here = math.min(remaining, capacity)
			for index = 0, here - 1 do
				local angle = (index - (here - 1) / 2) * step
				table.insert(slots, { math.sin(angle) * ringRadius, 0, math.cos(angle) * ringRadius })
			end
			remaining -= here
			ring += 1
		end
		return slots
	end
	-- circle and orbit: evenly around the owner, on a ring wide enough that neighbours do not touch.
	local ringRadius = distance
	if n >= 2 then
		ringRadius = math.max(distance, spacing / (2 * math.sin(math.pi / n)))
	end
	local turn = 0
	if mode == "orbit" then
		turn = math.rad(number(opts.orbitSpeed, 30) * number(opts.time, 0))
	end
	for index = 0, n - 1 do
		local angle = turn + TAU * index / n
		table.insert(slots, { math.sin(angle) * ringRadius, 0, math.cos(angle) * ringRadius })
	end
	return slots
end

-- Follow --------------------------------------------------------------------------------------

export type FollowState = {
	position: Vec3,
	velocity: Vec3,
	yaw: number, -- degrees; 0 looks down -z
}

export type FollowOptions = {
	frequency: number?, -- spring frequency in Hz (default 2.2); higher follows tighter
	maxSpeed: number?, -- studs per second (default 60)
	teleportDistance: number?, -- beyond this the pet snaps to its slot (default 70)
	turnRate: number?, -- how fast it turns to face its travel direction, per second (default 10)
	moveThreshold: number?, -- speed above which it faces where it is going (default 0.75)
	faceYaw: number?, -- yaw to settle on when standing still (usually the owner's)
}

-- Shortest signed difference from angle a to angle b, in degrees (-180..180).
function PetsLogic.angleDelta(a: number, b: number): number
	return (b - a + 180) % 360 - 180
end

function PetsLogic.newFollowState(position: Vec3, yaw: number?): FollowState
	return { position = { position[1], position[2], position[3] }, velocity = { 0, 0, 0 }, yaw = yaw or 0 }
end

-- Advances a pet toward `target` by dt seconds. A critically damped spring never overshoots from
-- rest; the speed limit only ever shortens a step. Returns the new state and whether it teleported.
function PetsLogic.followStep(
	state: FollowState,
	target: Vec3,
	dt: number,
	options: FollowOptions?
): (FollowState, boolean)
	local opts: FollowOptions = options or {}
	local position, velocity = state.position, state.velocity
	local dx, dy, dz = target[1] - position[1], target[2] - position[2], target[3] - position[3]
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	local faceYaw = opts.faceYaw
	if distance > number(opts.teleportDistance, 70) then
		return {
			position = { target[1], target[2], target[3] },
			velocity = { 0, 0, 0 },
			yaw = if faceYaw then faceYaw else state.yaw,
		},
			true
	end
	if dt <= 0 then
		return state, false
	end
	local spring: Springs.Spring = { frequency = math.max(0.05, number(opts.frequency, 2.2)), damping = 1 }
	local nextPosition: Vec3 = { 0, 0, 0 }
	local nextVelocity: Vec3 = { 0, 0, 0 }
	for i = 1, 3 do
		nextPosition[i], nextVelocity[i] = Springs.step(position[i], velocity[i], target[i], dt, spring)
	end
	local sx, sy, sz = nextPosition[1] - position[1], nextPosition[2] - position[2], nextPosition[3] - position[3]
	local stepLength = math.sqrt(sx * sx + sy * sy + sz * sz)
	local limit = math.max(0, number(opts.maxSpeed, 60)) * dt
	if stepLength > limit and stepLength > 0 then
		local k = limit / stepLength
		nextPosition = { position[1] + sx * k, position[2] + sy * k, position[3] + sz * k }
		nextVelocity = { sx * k / dt, sy * k / dt, sz * k / dt }
	end
	local yaw = state.yaw
	local flat = math.sqrt(nextVelocity[1] ^ 2 + nextVelocity[3] ^ 2)
	local desired: number? = faceYaw
	if flat > number(opts.moveThreshold, 0.75) then
		desired = math.deg(math.atan2(-nextVelocity[1], -nextVelocity[3]))
	end
	if desired then
		local blend = 1 - math.exp(-math.max(0, number(opts.turnRate, 10)) * dt)
		yaw += PetsLogic.angleDelta(yaw, desired) * blend
	end
	return { position = nextPosition, velocity = nextVelocity, yaw = yaw }, false
end

-- Extra height for a walking pet: small hops in proportion to its speed, none when standing.
function PetsLogic.walkBob(speed: number, t: number, radius: number?, fullSpeed: number?): number
	local amount = math.clamp(speed / math.max(0.1, number(fullSpeed, 8)), 0, 1)
	if amount <= 0 then
		return 0
	end
	return math.abs(math.sin(TAU * 1.6 * t)) * number(radius, 1) * 0.22 * amount
end

-- Ground --------------------------------------------------------------------------------------

export type GroundOptions = {
	pivotHeight: number?, -- distance from the model's pivot down to its feet (default 1)
	hover: number?, -- extra height for flying pets (default 0); flying pets do not tilt
	yaw: number?, -- the pet's facing in degrees, to turn the normal into pitch and roll
	maxTilt: number?, -- degrees (default 25)
	fallbackY: number?, -- used when no ground was found (default 0)
}

export type Ground = { y: number, pitch: number, roll: number, grounded: boolean }

-- Where a pet stands: its pivot height and its tilt, from a ground sample (height and normal).
function PetsLogic.groundAlign(groundY: number?, normal: Vec3?, options: GroundOptions?): Ground
	local opts: GroundOptions = options or {}
	local hover = math.max(0, number(opts.hover, 0))
	if groundY == nil then
		return { y = number(opts.fallbackY, 0) + hover, pitch = 0, roll = 0, grounded = false }
	end
	local y = groundY + math.max(0, number(opts.pivotHeight, 1)) + hover
	if normal == nil or hover > 0 then
		return { y = y, pitch = 0, roll = 0, grounded = true }
	end
	local yaw = math.rad(number(opts.yaw, 0))
	-- Forward and right of the pet on the ground plane.
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local up = math.max(1e-3, normal[2])
	local alongForward = normal[1] * fx + normal[3] * fz
	local alongRight = normal[1] * rx + normal[3] * rz
	local limit = math.max(0, number(opts.maxTilt, 25))
	-- Ground rising ahead leans its normal back toward the pet: nose up. Same idea sideways.
	local pitch = math.clamp(math.deg(math.atan2(-alongForward, up)), -limit, limit)
	local roll = math.clamp(math.deg(math.atan2(-alongRight, up)), -limit, limit)
	return { y = y, pitch = pitch, roll = roll, grounded = true }
end

export type GroundCache = { x: number, z: number, time: number }

-- True when a pet's ground sample should be taken again: it is older than `interval` seconds or
-- the pet has moved more than `distance` studs since. Keeps raycasts off the per-frame path.
function PetsLogic.groundStale(
	cache: GroundCache?,
	x: number,
	z: number,
	now: number,
	interval: number?,
	distance: number?
): boolean
	if cache == nil then
		return true
	end
	if now - cache.time >= (interval or 0.4) then
		return true
	end
	local dx, dz = x - cache.x, z - cache.z
	local limit = distance or 2
	return dx * dx + dz * dz > limit * limit
end

-- Scheduler -----------------------------------------------------------------------------------

-- Number of round-robin buckets: with `hz` updates per second wanted at `fps` frames per second,
-- each pet updates every (fps / hz) frames; hz 0 means every frame. `maxPerFrame` (default 24)
-- adds buckets when there are very many pets, whatever the quality level.
function PetsLogic.buckets(count: number, hz: number, fps: number?, maxPerFrame: number?): number
	local n = math.max(0, math.floor(count))
	if n <= 1 then
		return 1
	end
	local byRate = 1
	if hz > 0 then
		byRate = math.max(1, math.floor(math.max(1, number(fps, 60)) / hz + 0.5))
	end
	local byCount = math.ceil(n / math.max(1, number(maxPerFrame, 24)))
	return math.clamp(math.max(byRate, byCount), 1, n)
end

function PetsLogic.bucketOf(index: number, buckets: number): number
	return (index - 1) % math.max(1, buckets)
end

-- True when pet `index` (1-based) updates on frame `frame`.
function PetsLogic.isDue(index: number, frame: number, buckets: number): boolean
	local count = math.max(1, buckets)
	return (index - 1) % count == frame % count
end

-- Plans ---------------------------------------------------------------------------------------

export type Step = {
	at: number, -- seconds from the start
	kind: "vfx" | "object" | "reaction" | "show" | "hide",
	id: string?, -- VFX preset id, ObjectsLogic preset id or reaction id
}

export type Plan = {
	name: string,
	description: string,
	duration: number,
	steps: { Step },
}

local PLANS: { [string]: Plan } = {
	Spawn = {
		name = "Spawn",
		description = "The burst lands first, the pet pops out of it with an overshoot and gives a small bounce.",
		duration = 0.95,
		steps = {
			{ at = 0, kind = "hide" },
			{ at = 0, kind = "vfx", id = "PetSpawn" },
			{ at = 0.08, kind = "show" },
			{ at = 0.08, kind = "object", id = "ScaleIn" },
			{ at = 0.5, kind = "reaction", id = "SelectBounce" },
		},
	},
	Despawn = {
		name = "Despawn",
		description = "The pet swells, shrinks to nothing and leaves a puff behind.",
		duration = 0.5,
		steps = {
			{ at = 0, kind = "object", id = "ScaleOut" },
			{ at = 0.22, kind = "vfx", id = "PetDespawn" },
			{ at = 0.3, kind = "hide" },
		},
	},
	Equip = {
		name = "Equip",
		description = "A ring of energy and a proud bounce as the pet joins the team.",
		duration = 0.5,
		steps = {
			{ at = 0, kind = "vfx", id = "PetEquip" },
			{ at = 0, kind = "reaction", id = "SelectBounce" },
		},
	},
	Unequip = {
		name = "Unequip",
		description = "A quick squash and a soft puff as the pet steps down.",
		duration = 0.35,
		steps = {
			{ at = 0, kind = "object", id = "Interact" },
			{ at = 0.05, kind = "vfx", id = "PetUnequip" },
		},
	},
	Evolve = {
		name = "Evolve",
		description = "The pet rattles as energy builds, bursts into its new form with a stretch, then celebrates.",
		duration = 2.3,
		steps = {
			{ at = 0, kind = "object", id = "Shake" },
			{ at = 0.45, kind = "object", id = "Shake" },
			{ at = 0.9, kind = "vfx", id = "PetEvolve" },
			{ at = 0.9, kind = "object", id = "SquashStretch" },
			{ at = 1.4, kind = "reaction", id = "HappyReaction" },
		},
	},
	Upgrade = {
		name = "Upgrade",
		description = "A bounce with a rising sparkle to mark a level or stat upgrade.",
		duration = 0.6,
		steps = {
			{ at = 0, kind = "reaction", id = "SelectBounce" },
			{ at = 0.1, kind = "vfx", id = "PetUpgrade" },
		},
	},
}

PetsLogic.PLANS = table.freeze({ "Spawn", "Despawn", "Equip", "Unequip", "Evolve", "Upgrade" })

function PetsLogic.plan(id: string): Plan?
	return PLANS[id]
end

-- Problems with a plan (empty when valid).
function PetsLogic.validatePlan(plan: Plan): { string }
	local problems: { string } = {}
	if type(plan) ~= "table" or type(plan.steps) ~= "table" then
		return { "plan must be a table with steps" }
	end
	if not (number(plan.duration, -1) > 0) then
		table.insert(problems, "duration must be positive")
	end
	local previous = 0
	for index, step in plan.steps do
		local label = "step " .. tostring(index)
		if type(step.at) ~= "number" or step.at < previous then
			table.insert(problems, label .. ": times must not go backwards")
		else
			previous = step.at
		end
		if type(step.at) == "number" and step.at > number(plan.duration, 0) then
			table.insert(problems, label .. ": after the end")
		end
		if step.kind == "vfx" then
			if type(step.id) ~= "string" or step.id == "" then
				table.insert(problems, label .. ": vfx id required")
			end
		elseif step.kind == "object" then
			if type(step.id) ~= "string" or not ObjectsLogic.has(step.id) or ObjectsLogic.isLoop(step.id) then
				table.insert(problems, label .. ": object step needs a one-shot object preset")
			end
		elseif step.kind == "reaction" then
			if type(step.id) ~= "string" or REACTIONS[step.id] == nil then
				table.insert(problems, label .. ": unknown reaction")
			end
		elseif step.kind ~= "show" and step.kind ~= "hide" then
			table.insert(problems, label .. ": unknown kind")
		end
	end
	return problems
end

-- Registry ------------------------------------------------------------------------------------

local registry = Registry.new("pet")
PetsLogic.registry = registry

for _, id in PetsLogic.REACTIONS do
	local def = REACTIONS[id]
	registry:register({
		id = id,
		name = def.name,
		category = "reaction",
		description = def.description,
		params = {
			intensity = { type = "number", default = 1, min = 0, max = 2, description = "Multiplier on the motion" },
		},
		quality = { min = "Low", cost = "low" },
		usage = string.format('Visuals.Pets.play("%s", petModel)', id),
		tags = { "pet", "reaction" },
		preview = { duration = def.duration },
		data = { kind = "reaction", duration = def.duration },
	})
end

for _, id in PetsLogic.PLANS do
	local plan = PLANS[id]
	local dependencies: { string } = {}
	for _, step in plan.steps do
		if step.kind == "vfx" and step.id then
			table.insert(dependencies, step.id)
		end
	end
	registry:register({
		id = id,
		name = plan.name,
		category = "timeline",
		description = plan.description,
		quality = { min = "Low", cost = "medium" },
		dependencies = dependencies,
		usage = string.format('Visuals.Pets.play("%s", petModel)', id),
		tags = { "pet", "timeline" },
		preview = { duration = plan.duration },
		data = { kind = "timeline", plan = plan },
	})
end

return PetsLogic
