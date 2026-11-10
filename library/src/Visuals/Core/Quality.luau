--!strict
-- Quality levels, budgets and adaptive quality (pure Luau). Four levels - Low, Medium, High,
-- Ultra - each with a profile that every visuals module reads: how many particles and effects may
-- be alive, how far away effects still play, and which optional layers are dropped.
--
-- Settings also carry the accessibility switches: reducedMotion (no loops, no camera shake, jumps
-- instead of travel), reducedFlashing (screen flashes become soft fades) and intensity (a global
-- 0..1.5 multiplier on shake, scale punches and particle counts).

export type Level = "Low" | "Medium" | "High" | "Ultra"

export type Profile = {
	level: Level,
	particleScale: number, -- multiplier on burst counts
	rateScale: number, -- multiplier on looping emission rates
	lifetimeScale: number,
	maxParticles: number, -- estimated live particles across all effects
	maxEffects: number, -- concurrent effects
	maxLights: number, -- dynamic lights created by effects
	maxDistance: number, -- studs; beyond this effects do not play
	fadeDistance: number, -- studs; from here to maxDistance counts scale down to 25%
	dropOptional: boolean, -- drop layers marked optional
	trails: boolean,
	beams: boolean,
	lights: boolean,
	highlights: boolean,
	postProcessing: boolean, -- bloom / colour-correction / blur pulses
	shakeScale: number, -- camera shake multiplier
	petUpdateHz: number, -- how often idle pet motion is recomputed (0 = every frame)
	uiShine: boolean, -- looping shine / shimmer on UI
	maxPopups: number, -- floating number popups alive at once
}

export type Device = {
	touch: boolean?,
	gamepad: boolean?,
	fps: number?,
	graphicsLevel: number?, -- saved Roblox quality level 1-10
	memoryMb: number?,
}

export type Settings = {
	level: Level,
	adaptive: boolean,
	reducedMotion: boolean,
	reducedFlashing: boolean,
	intensity: number,
}

local Quality = {}

Quality.LEVELS = table.freeze({ "Low", "Medium", "High", "Ultra" })

local PROFILES: { [string]: Profile } = {
	Low = {
		level = "Low",
		particleScale = 0.3,
		rateScale = 0.3,
		lifetimeScale = 0.75,
		maxParticles = 250,
		maxEffects = 10,
		maxLights = 0,
		maxDistance = 90,
		fadeDistance = 50,
		dropOptional = true,
		trails = false,
		beams = true,
		lights = false,
		highlights = false,
		postProcessing = false,
		shakeScale = 0.6,
		petUpdateHz = 20,
		uiShine = false,
		maxPopups = 8,
	},
	Medium = {
		level = "Medium",
		particleScale = 0.6,
		rateScale = 0.6,
		lifetimeScale = 0.9,
		maxParticles = 700,
		maxEffects = 24,
		maxLights = 2,
		maxDistance = 160,
		fadeDistance = 90,
		dropOptional = false,
		trails = true,
		beams = true,
		lights = true,
		highlights = true,
		postProcessing = false,
		shakeScale = 0.85,
		petUpdateHz = 30,
		uiShine = true,
		maxPopups = 16,
	},
	High = {
		level = "High",
		particleScale = 1,
		rateScale = 1,
		lifetimeScale = 1,
		maxParticles = 1600,
		maxEffects = 48,
		maxLights = 6,
		maxDistance = 260,
		fadeDistance = 150,
		dropOptional = false,
		trails = true,
		beams = true,
		lights = true,
		highlights = true,
		postProcessing = true,
		shakeScale = 1,
		petUpdateHz = 0,
		uiShine = true,
		maxPopups = 28,
	},
	Ultra = {
		level = "Ultra",
		particleScale = 1.35,
		rateScale = 1.25,
		lifetimeScale = 1.1,
		maxParticles = 3200,
		maxEffects = 80,
		maxLights = 12,
		maxDistance = 400,
		fadeDistance = 240,
		dropOptional = false,
		trails = true,
		beams = true,
		lights = true,
		highlights = true,
		postProcessing = true,
		shakeScale = 1,
		petUpdateHz = 0,
		uiShine = true,
		maxPopups = 40,
	},
}
for _, profile in PROFILES do
	table.freeze(profile)
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function Quality.isLevel(value: any): boolean
	return type(value) == "string" and PROFILES[value] ~= nil
end

function Quality.profile(level: string): Profile
	local profile = PROFILES[level]
	if profile == nil then
		error("unknown quality level: " .. tostring(level), 2)
	end
	return profile
end

function Quality.rank(level: string): number
	return table.find(Quality.LEVELS, level) or 0
end

-- True when `level` is at least `minimum` (nil minimum always passes).
function Quality.atLeast(level: string, minimum: string?): boolean
	return minimum == nil or Quality.rank(level) >= Quality.rank(minimum)
end

-- Maps Systems/VFX's three tiers ("low" | "medium" | "high") onto the four levels and back.
function Quality.fromLegacy(tier: string): Level
	if tier == "low" then
		return "Low"
	elseif tier == "high" then
		return "High"
	end
	return "Medium"
end

function Quality.toLegacy(level: string): string
	if level == "Low" then
		return "low"
	elseif level == "Medium" then
		return "medium"
	end
	return "high"
end

-- Picks a starting level for a device. A saved graphics level wins; phones start Low unless they
-- hold 58+ fps; desktops and consoles start High, and Ultra only at the top graphics levels.
function Quality.choose(device: Device): Level
	local memory = device.memoryMb
	if finite(memory) and (memory :: number) > 0 and (memory :: number) < 1500 then
		return "Low"
	end
	local level = device.graphicsLevel
	if finite(level) and (level :: number) >= 1 then
		local l = level :: number
		if l <= 3 then
			return "Low"
		elseif l <= 6 then
			return "Medium"
		elseif l <= 8 then
			return "High"
		end
		return if device.touch then "High" else "Ultra"
	end
	local fps = device.fps
	if finite(fps) and (fps :: number) < 40 then
		return "Low"
	end
	if device.touch then
		return if finite(fps) and (fps :: number) >= 58 then "Medium" else "Low"
	end
	if finite(fps) and (fps :: number) < 55 then
		return "Medium"
	end
	return "High"
end

function Quality.defaults(): Settings
	return { level = "Medium", adaptive = true, reducedMotion = false, reducedFlashing = false, intensity = 1 }
end

-- A clean copy of `partial` over `base`, with invalid values replaced by the base value.
function Quality.merge(base: Settings, partial: { [string]: any }?): Settings
	local out = table.clone(base)
	if partial == nil then
		return out
	end
	if Quality.isLevel(partial.level) then
		out.level = partial.level
	end
	if type(partial.adaptive) == "boolean" then
		out.adaptive = partial.adaptive
	end
	if type(partial.reducedMotion) == "boolean" then
		out.reducedMotion = partial.reducedMotion
	end
	if type(partial.reducedFlashing) == "boolean" then
		out.reducedFlashing = partial.reducedFlashing
	end
	if finite(partial.intensity) then
		out.intensity = math.clamp(partial.intensity, 0, 1.5)
	end
	return out
end

-- Multiplier for shake, punch scale and other "juice" amounts. Reduced motion removes camera
-- shake entirely and halves the rest.
function Quality.juice(settings: Settings, kind: ("shake" | "scale" | "particles")?): number
	local k = settings.intensity
	if settings.reducedMotion then
		if kind == "shake" then
			return 0
		end
		k *= 0.5
	end
	if kind == "shake" then
		k *= Quality.profile(settings.level).shakeScale
	end
	return k
end

-- Scales a one-shot particle count for a profile and distance; never below 1 for a visible effect.
function Quality.scaleCount(count: number, profile: Profile, distance: number?, intensity: number?): number
	local k = profile.particleScale * (intensity or 1) * Quality.distanceScale(profile, distance)
	if k <= 0 then
		return 0
	end
	return math.max(1, math.floor(count * k + 0.5))
end

-- 1 inside fadeDistance, falling to 0.25 at maxDistance, 0 beyond it.
function Quality.distanceScale(profile: Profile, distance: number?): number
	if distance == nil or distance <= profile.fadeDistance then
		return 1
	end
	if distance > profile.maxDistance then
		return 0
	end
	local span = math.max(1e-6, profile.maxDistance - profile.fadeDistance)
	return 1 - 0.75 * (distance - profile.fadeDistance) / span
end

-- Adaptive quality ----------------------------------------------------------------------------
-- Feed frame times in; the controller steps the level down quickly when frames are slow and back
-- up slowly when there is headroom, never above the ceiling it started with.

export type Adaptive = {
	level: Level,
	ceiling: Level,
	average: number, -- smoothed frame time in seconds
	slowFor: number,
	fastFor: number,
	cooldown: number,
}

export type AdaptiveOptions = {
	slowFrame: number?, -- seconds; above this is slow (default 1/42)
	fastFrame: number?, -- seconds; below this is fast (default 1/57)
	downAfter: number?, -- seconds of slow frames before stepping down (default 2)
	upAfter: number?, -- seconds of fast frames before stepping up (default 12)
	cooldown: number?, -- seconds to wait after any change (default 4)
}

function Quality.adaptive(level: Level, ceiling: Level?): Adaptive
	return { level = level, ceiling = ceiling or level, average = 1 / 60, slowFor = 0, fastFor = 0, cooldown = 0 }
end

-- Advances the controller by one frame. Returns the new level when it changed, else nil.
function Quality.adapt(state: Adaptive, frameTime: number, options: AdaptiveOptions?): Level?
	if not finite(frameTime) or frameTime <= 0 then
		return nil
	end
	local opts: AdaptiveOptions = options or {}
	local dt = math.min(frameTime, 0.25)
	-- Exponential smoothing with a ~0.5 s time constant, so one hitch does not change quality.
	local blend = 1 - math.exp(-dt / 0.5)
	state.average += (dt - state.average) * blend
	if state.cooldown > 0 then
		state.cooldown = math.max(0, state.cooldown - dt)
		state.slowFor, state.fastFor = 0, 0
		return nil
	end
	if state.average > (opts.slowFrame or 1 / 42) then
		state.slowFor += dt
		state.fastFor = 0
	elseif state.average < (opts.fastFrame or 1 / 57) then
		state.fastFor += dt
		state.slowFor = 0
	else
		state.slowFor, state.fastFor = 0, 0
	end
	local rank = Quality.rank(state.level)
	if state.slowFor >= (opts.downAfter or 2) and rank > 1 then
		state.level = Quality.LEVELS[rank - 1] :: Level
		state.slowFor, state.cooldown = 0, opts.cooldown or 4
		return state.level
	end
	if state.fastFor >= (opts.upAfter or 12) and rank < Quality.rank(state.ceiling) then
		state.level = Quality.LEVELS[rank + 1] :: Level
		state.fastFor, state.cooldown = 0, opts.cooldown or 4
		return state.level
	end
	return nil
end

return Quality
