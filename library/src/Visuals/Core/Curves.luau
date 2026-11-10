--!strict
-- Easing curves for the visuals kit (pure Luau). Extends UI/Core/Easing - every curve there works
-- here by the same name - with the rest of the standard set, cubic Bezier curves, stepped curves
-- and custom registration. A curve maps t in 0..1 to progress with f(0) = 0 and f(1) = 1.

local Easing = require("../../UI/Core/Easing")

export type Curve = (t: number) -> number

local Curves = {}

local BACK = 1.70158
local BACK_IN_OUT = BACK * 1.525

local function bounceOut(t: number): number
	return Easing.get("bounceOut")(t)
end

local function elasticOut(t: number): number
	return Easing.get("elasticOut")(t)
end

local own: { [string]: Curve } = {
	sineIn = function(t: number): number
		return 1 - math.cos(t * math.pi / 2)
	end,
	sineOut = function(t: number): number
		return math.sin(t * math.pi / 2)
	end,
	quartIn = function(t: number): number
		return t ^ 4
	end,
	quartOut = function(t: number): number
		return 1 - (1 - t) ^ 4
	end,
	quartInOut = function(t: number): number
		return if t < 0.5 then 8 * t ^ 4 else 1 - ((-2 * t + 2) ^ 4) / 2
	end,
	quintIn = function(t: number): number
		return t ^ 5
	end,
	quintOut = function(t: number): number
		return 1 - (1 - t) ^ 5
	end,
	quintInOut = function(t: number): number
		return if t < 0.5 then 16 * t ^ 5 else 1 - ((-2 * t + 2) ^ 5) / 2
	end,
	expoIn = function(t: number): number
		return if t == 0 then 0 else 2 ^ (10 * t - 10)
	end,
	expoOut = function(t: number): number
		return if t == 1 then 1 else 1 - 2 ^ (-10 * t)
	end,
	expoInOut = function(t: number): number
		if t == 0 or t == 1 then
			return t
		end
		return if t < 0.5 then 2 ^ (20 * t - 10) / 2 else (2 - 2 ^ (-20 * t + 10)) / 2
	end,
	circIn = function(t: number): number
		return 1 - math.sqrt(1 - t * t)
	end,
	circOut = function(t: number): number
		return math.sqrt(1 - (t - 1) ^ 2)
	end,
	backIn = function(t: number): number
		return (BACK + 1) * t ^ 3 - BACK * t ^ 2
	end,
	backInOut = function(t: number): number
		if t < 0.5 then
			return ((2 * t) ^ 2 * ((BACK_IN_OUT + 1) * 2 * t - BACK_IN_OUT)) / 2
		end
		return ((2 * t - 2) ^ 2 * ((BACK_IN_OUT + 1) * (t * 2 - 2) + BACK_IN_OUT) + 2) / 2
	end,
	elasticIn = function(t: number): number
		return 1 - elasticOut(1 - t)
	end,
	bounceIn = function(t: number): number
		return 1 - bounceOut(1 - t)
	end,
	bounceInOut = function(t: number): number
		return if t < 0.5 then (1 - bounceOut(1 - 2 * t)) / 2 else (1 + bounceOut(2 * t - 1)) / 2
	end,
	-- Pulls back about 10% before moving: anticipation for throws, hatches and big reveals.
	anticipate = function(t: number): number
		local s = 2.4
		return t * t * ((s + 1) * t - s)
	end,
	-- Anticipation, then overshoot and settle: the full cartoon move in one curve.
	anticipateOvershoot = function(t: number): number
		local s = 2.2 * 1.5
		if t < 0.5 then
			return 0.5 * ((2 * t) ^ 2 * ((s + 1) * 2 * t - s))
		end
		local u = 2 * t - 2
		return 0.5 * (u * u * ((s + 1) * u + s) + 2)
	end,
	-- Fast start with a long soft tail; good for currency flying to a counter.
	swiftOut = function(t: number): number
		return 1 - (1 - t) ^ 2.6
	end,
}

-- The curve called `name`. Unknown names fall back to linear (same rule as UI/Core/Easing).
function Curves.get(name: string?): Curve
	if name ~= nil and own[name] ~= nil then
		return own[name]
	end
	return Easing.get(name)
end

function Curves.has(name: string): boolean
	return own[name] ~= nil or Easing.has(name)
end

function Curves.names(): { string }
	local names: { string } = table.clone(Easing.NAMES)
	for name in own do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Evaluates a curve (by name or function) with t clamped to 0..1.
function Curves.ease(curve: (string | Curve)?, t: number): number
	local clamped = math.clamp(t, 0, 1)
	if type(curve) == "function" then
		return curve(clamped)
	end
	return Curves.get(curve)(clamped)
end

-- Adds or replaces a named curve.
function Curves.register(name: string, curve: Curve)
	assert(type(name) == "string" and name ~= "", "curve name required")
	assert(type(curve) == "function", "curve must be a function")
	own[name] = curve
end

-- A CSS-style cubic Bezier timing curve through (0,0), (x1,y1), (x2,y2), (1,1).
function Curves.bezier(x1: number, y1: number, x2: number, y2: number): Curve
	local ax, bx, cx = 3 * x1 - 3 * x2 + 1, 3 * x2 - 6 * x1, 3 * x1
	local ay, by, cy = 3 * y1 - 3 * y2 + 1, 3 * y2 - 6 * y1, 3 * y1
	return function(t: number): number
		if t <= 0 or t >= 1 then
			return math.clamp(t, 0, 1)
		end
		-- Solve x(u) = t with Newton steps, then bisection if the slope is too flat.
		local u = t
		for _ = 1, 6 do
			local x = ((ax * u + bx) * u + cx) * u - t
			local slope = (3 * ax * u + 2 * bx) * u + cx
			if math.abs(x) < 1e-6 then
				break
			end
			if math.abs(slope) < 1e-6 then
				break
			end
			u -= x / slope
		end
		local low, high = 0, 1
		u = math.clamp(u, 0, 1)
		for _ = 1, 12 do
			local x = ((ax * u + bx) * u + cx) * u
			if math.abs(x - t) < 1e-6 then
				break
			end
			if x < t then
				low = u
			else
				high = u
			end
			u = (low + high) / 2
		end
		return ((ay * u + by) * u + cy) * u
	end
end

-- A stepped curve with `count` equal jumps (sprite-like motion, number tickers).
function Curves.steps(count: number): Curve
	local n = math.max(1, math.floor(count))
	return function(t: number): number
		return if t >= 1 then 1 else math.floor(t * n) / n
	end
end

-- Plays `curve` forwards then backwards within one 0..1 span (there and back).
function Curves.yoyo(curve: (string | Curve)?): Curve
	return function(t: number): number
		local u = if t < 0.5 then t * 2 else (1 - t) * 2
		return Curves.ease(curve, u)
	end
end

-- Blends two curves: weight 0 is `a`, 1 is `b`.
function Curves.blend(a: (string | Curve)?, b: (string | Curve)?, weight: number): Curve
	local k = math.clamp(weight, 0, 1)
	return function(t: number): number
		return Curves.ease(a, t) * (1 - k) + Curves.ease(b, t) * k
	end
end

return Curves
