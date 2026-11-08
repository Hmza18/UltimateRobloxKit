--!strict
-- Easing curves, springs and count-up maths for animations. Pure Luau: time is passed in, never read.
-- Every curve maps t in 0..1 to a progress value with f(0) = 0 and f(1) = 1 (back and elastic
-- curves overshoot in between).

export type EasingFn = (t: number) -> number
export type SpringState = { position: number, velocity: number }
export type SpringOptions = {
	frequency: number?, -- oscillations per second (default 4)
	damping: number?, -- 1 = critically damped, < 1 bounces, > 1 is sluggish (default 1)
}

local Easing = {}

local BACK = 1.70158
local SPRING_STEP = 1 / 240

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function bounceOut(t: number): number
	local n1 = 7.5625
	local d1 = 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		local u = t - 1.5 / d1
		return n1 * u * u + 0.75
	elseif t < 2.5 / d1 then
		local u = t - 2.25 / d1
		return n1 * u * u + 0.9375
	end
	local u = t - 2.625 / d1
	return n1 * u * u + 0.984375
end

local curves: { [string]: EasingFn } = {
	linear = function(t: number): number
		return t
	end,
	quadIn = function(t: number): number
		return t * t
	end,
	quadOut = function(t: number): number
		return 1 - (1 - t) * (1 - t)
	end,
	quadInOut = function(t: number): number
		return if t < 0.5 then 2 * t * t else 1 - ((-2 * t + 2) ^ 2) / 2
	end,
	cubicIn = function(t: number): number
		return t * t * t
	end,
	cubicOut = function(t: number): number
		return 1 - (1 - t) ^ 3
	end,
	cubicInOut = function(t: number): number
		return if t < 0.5 then 4 * t * t * t else 1 - ((-2 * t + 2) ^ 3) / 2
	end,
	sineInOut = function(t: number): number
		return -(math.cos(math.pi * t) - 1) / 2
	end,
	backOut = function(t: number): number
		local c3 = BACK + 1
		return 1 + c3 * (t - 1) ^ 3 + BACK * (t - 1) ^ 2
	end,
	elasticOut = function(t: number): number
		if t == 0 or t == 1 then
			return t
		end
		return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
	end,
	bounceOut = bounceOut,
}

Easing.NAMES = {
	"linear",
	"quadIn",
	"quadOut",
	"quadInOut",
	"cubicIn",
	"cubicOut",
	"cubicInOut",
	"sineInOut",
	"backOut",
	"elasticOut",
	"bounceOut",
}

-- The curve called `name`, or linear when unknown.
function Easing.get(name: string?): EasingFn
	if name == nil then
		return curves.linear
	end
	return curves[name] or curves.linear
end

function Easing.has(name: string): boolean
	return curves[name] ~= nil
end

-- Evaluates a curve with t clamped to 0..1.
function Easing.ease(name: string?, t: number): number
	return Easing.get(name)(clamp01(t))
end

function Easing.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Progress of a timed animation that started at `startedAt` and lasts `duration` seconds.
-- A zero or negative duration is complete immediately.
function Easing.progress(startedAt: number, duration: number, now: number): number
	if duration <= 0 then
		return 1
	end
	return clamp01((now - startedAt) / duration)
end

-- Seconds to use for an animation: 0 when the player asked for reduced motion.
function Easing.duration(base: number, reducedMotion: boolean?): number
	if reducedMotion then
		return 0
	end
	return math.max(0, base)
end

-- Value of a count-up from `from` to `to` at progress t, eased and rounded to whole numbers when
-- both ends are whole numbers (so a coin counter never shows 12.37 coins).
function Easing.countUp(from: number, to: number, t: number, curve: string?): number
	local value = Easing.lerp(from, to, Easing.ease(curve or "cubicOut", t))
	if from % 1 == 0 and to % 1 == 0 then
		if to >= from then
			return math.min(to, math.floor(value + 1e-9))
		end
		return math.max(to, math.ceil(value - 1e-9))
	end
	return value
end

-- Count-up duration that grows with the size of the change but stays between min and max seconds.
function Easing.countUpDuration(delta: number, minSeconds: number?, maxSeconds: number?): number
	local low = minSeconds or 0.25
	local high = maxSeconds or 1.2
	local magnitude = math.abs(delta)
	if magnitude == 0 then
		return 0
	end
	return math.clamp(low + math.log10(magnitude + 1) * 0.15, low, high)
end

-- Advances a damped spring towards `target` by `dt` seconds. Uses fixed sub-steps of 1/240 s with
-- semi-implicit Euler, which is stable for any frame rate. Returns a new state.
function Easing.springStep(state: SpringState, target: number, dt: number, options: SpringOptions?): SpringState
	local opts: SpringOptions = options or {}
	local omega = 2 * math.pi * math.max(0.01, opts.frequency or 4)
	local zeta = math.max(0, opts.damping or 1)
	local position = state.position
	local velocity = state.velocity
	local remaining = math.max(0, dt)
	while remaining > 0 do
		local step = math.min(SPRING_STEP, remaining)
		local acceleration = -2 * zeta * omega * velocity - omega * omega * (position - target)
		velocity += acceleration * step
		position += velocity * step
		remaining -= step
	end
	return { position = position, velocity = velocity }
end

function Easing.springSettled(state: SpringState, target: number, epsilon: number?): boolean
	local limit = epsilon or 1e-3
	return math.abs(state.position - target) < limit and math.abs(state.velocity) < limit
end

return Easing
