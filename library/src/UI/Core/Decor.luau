--!strict
-- Values of the decorative UrkAnimate effects at time t (seconds). Pure Luau, so the shared frame
-- driver only applies numbers. With reduced motion every effect returns its resting value.
--
--   Spin    -> rotation in degrees               (Speed = degrees per second, default 90)
--   Bob     -> vertical offset in pixels         (Amplitude px, default 4; Speed = cycles per second)
--   Pulse   -> scale multiplier around 1          (Amplitude = fraction, default 0.06)
--   Shine   -> gradient offset from -1 to 1      (Speed = sweeps per second, Pause = rest seconds)
--   Rainbow -> colour { r, g, b }                (Speed = hue cycles per second, default 0.2)

export type RGB = { r: number, g: number, b: number }
export type Params = { speed: number?, amplitude: number?, phase: number?, pause: number? }

local Decor = {}

Decor.EFFECTS = { "Spin", "Bob", "Pulse", "Shine", "Rainbow" }

local TAU = 2 * math.pi

function Decor.isEffect(name: any): boolean
	return type(name) == "string" and table.find(Decor.EFFECTS, name) ~= nil
end

function Decor.spin(t: number, params: Params?, reduced: boolean?): number
	if reduced then
		return 0
	end
	local p: Params = params or {}
	return ((p.speed or 90) * t + (p.phase or 0)) % 360
end

function Decor.bob(t: number, params: Params?, reduced: boolean?): number
	if reduced then
		return 0
	end
	local p: Params = params or {}
	return math.sin((t * (p.speed or 0.8) + (p.phase or 0)) * TAU) * (p.amplitude or 4)
end

function Decor.pulse(t: number, params: Params?, reduced: boolean?): number
	if reduced then
		return 1
	end
	local p: Params = params or {}
	local wave = (math.sin((t * (p.speed or 1) + (p.phase or 0)) * TAU) + 1) / 2
	return 1 + wave * (p.amplitude or 0.06)
end

-- A sweep from -1 to 1 lasting 1/speed seconds, followed by `pause` seconds resting at -1.
function Decor.shine(t: number, params: Params?, reduced: boolean?): number
	if reduced then
		return -1
	end
	local p: Params = params or {}
	local sweep = 1 / math.max(0.01, p.speed or 0.8)
	local period = sweep + math.max(0, p.pause or 1.5)
	local elapsed = (t + (p.phase or 0)) % period
	if elapsed >= sweep then
		return -1
	end
	return -1 + 2 * (elapsed / sweep)
end

-- HSV (all 0..1) to RGB (0..1).
function Decor.hsvToRgb(h: number, s: number, v: number): RGB
	local hue = (h % 1) * 6
	local sector = math.floor(hue)
	local f = hue - sector
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local u = v * (1 - s * (1 - f))
	if sector == 0 then
		return { r = v, g = u, b = p }
	elseif sector == 1 then
		return { r = q, g = v, b = p }
	elseif sector == 2 then
		return { r = p, g = v, b = u }
	elseif sector == 3 then
		return { r = p, g = q, b = v }
	elseif sector == 4 then
		return { r = u, g = p, b = v }
	end
	return { r = v, g = p, b = q }
end

function Decor.rainbow(t: number, params: Params?, reduced: boolean?): RGB
	local p: Params = params or {}
	if reduced then
		return Decor.hsvToRgb(p.phase or 0, 0.75, 1)
	end
	return Decor.hsvToRgb((t * (p.speed or 0.2) + (p.phase or 0)) % 1, 0.75, 1)
end

return Decor
