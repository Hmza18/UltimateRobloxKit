--!strict
-- WCAG 2.x contrast maths. Pure Luau: colours are { r, g, b } with channels in 0..1.

export type RGB = { r: number, g: number, b: number }

local Contrast = {}

-- WCAG minimum ratios. Large text is at least 24 px, or 18.5 px bold. Non-text UI parts need 3.
Contrast.AA = 4.5
Contrast.AA_LARGE = 3
Contrast.AAA = 7
Contrast.AAA_LARGE = 4.5
Contrast.NON_TEXT = 3

local function linear(channel: number): number
	local value = math.clamp(channel, 0, 1)
	if value <= 0.04045 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

-- Relative luminance: 0 for black, 1 for white.
function Contrast.luminance(color: RGB): number
	return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
end

-- Contrast ratio from 1 (identical colours) to 21 (black on white). Argument order does not matter.
function Contrast.ratio(a: RGB, b: RGB): number
	local first = Contrast.luminance(a)
	local second = Contrast.luminance(b)
	return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
end

-- The ratio a pair must reach. level is "AA" (default) or "AAA".
function Contrast.required(level: string?, large: boolean?): number
	if level == "AAA" then
		return if large then Contrast.AAA_LARGE else Contrast.AAA
	end
	return if large then Contrast.AA_LARGE else Contrast.AA
end

function Contrast.meets(a: RGB, b: RGB, level: string?, large: boolean?): boolean
	return Contrast.ratio(a, b) >= Contrast.required(level, large)
end

-- The candidate with the highest contrast against `background`. `candidates` must not be empty.
function Contrast.best(background: RGB, candidates: { RGB }): RGB
	assert(#candidates > 0, "Contrast.best needs at least one candidate")
	local bestColor = candidates[1]
	local bestRatio = -1
	for _, candidate in candidates do
		local value = Contrast.ratio(candidate, background)
		if value > bestRatio then
			bestColor = candidate
			bestRatio = value
		end
	end
	return bestColor
end

local function mix(a: RGB, b: RGB, amount: number): RGB
	return { r = a.r + (b.r - a.r) * amount, g = a.g + (b.g - a.g) * amount, b = a.b + (b.b - a.b) * amount }
end

-- Moves `foreground` towards black or white (whichever helps) until it reaches `target` against
-- `background`. Returns the adjusted colour and whether the target was reached.
function Contrast.adjust(foreground: RGB, background: RGB, target: number): (RGB, boolean)
	if Contrast.ratio(foreground, background) >= target then
		return foreground, true
	end
	local white = { r = 1, g = 1, b = 1 }
	local black = { r = 0, g = 0, b = 0 }
	local towards = if Contrast.ratio(white, background) >= Contrast.ratio(black, background) then white else black
	for step = 1, 20 do
		local candidate = mix(foreground, towards, step / 20)
		if Contrast.ratio(candidate, background) >= target then
			return candidate, true
		end
	end
	return towards, Contrast.ratio(towards, background) >= target
end

return Contrast
