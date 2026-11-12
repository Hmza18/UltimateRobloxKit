-- Easing curves (u in 0..1 -> 0..1, back/elastic overshoot). Pure functions: unit-tested offline.
local Easing = {}
local pi, sin, cos = math.pi, math.sin, math.cos

function Easing.linear(u) return u end
function Easing.inQuad(u) return u * u end
function Easing.outQuad(u) return 1 - (1 - u) * (1 - u) end
function Easing.inOutQuad(u)
	if u < 0.5 then return 2 * u * u end
	return 1 - (-2 * u + 2) ^ 2 / 2
end
function Easing.inCubic(u) return u * u * u end
function Easing.outCubic(u) return 1 - (1 - u) ^ 3 end
function Easing.inOutCubic(u)
	if u < 0.5 then return 4 * u * u * u end
	return 1 - (-2 * u + 2) ^ 3 / 2
end
function Easing.outQuint(u) return 1 - (1 - u) ^ 5 end
function Easing.inOutSine(u) return -(cos(pi * u) - 1) / 2 end
function Easing.outSine(u) return sin(u * pi / 2) end
function Easing.inExpo(u)
	if u <= 0 then return 0 end
	return 2 ^ (10 * u - 10)
end
function Easing.outExpo(u)
	if u >= 1 then return 1 end
	return 1 - 2 ^ (-10 * u)
end
function Easing.outBack(u)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end
function Easing.outBackSoft(u)
	local c1 = 0.9
	local c3 = c1 + 1
	return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end
function Easing.outElastic(u)
	if u <= 0 then return 0 end
	if u >= 1 then return 1 end
	return 2 ^ (-10 * u) * sin((u * 10 - 0.75) * (2 * pi) / 3) + 1
end
function Easing.outBounce(u)
	local n1, d1 = 7.5625, 2.75
	if u < 1 / d1 then
		return n1 * u * u
	elseif u < 2 / d1 then
		u = u - 1.5 / d1
		return n1 * u * u + 0.75
	elseif u < 2.5 / d1 then
		u = u - 2.25 / d1
		return n1 * u * u + 0.9375
	end
	u = u - 2.625 / d1
	return n1 * u * u + 0.984375
end

-- Easing.get("outBack")(u) with clamping; unknown names fall back to inOutSine.
function Easing.get(name)
	local f = Easing[name or "inOutSine"]
	if type(f) ~= "function" or name == "get" or name == "apply" then
		f = Easing.inOutSine
	end
	return f
end

function Easing.apply(name, u)
	if u <= 0 then return 0 end
	if u >= 1 then return 1 end
	return Easing.get(name)(u)
end

-- Exponential smoothing factor that is frame-rate independent: lerp(a, b, Easing.damp(rate, dt)).
function Easing.damp(rate, dt)
	return 1 - math.exp(-rate * dt)
end

return Easing
