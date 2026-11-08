--!strict
-- WCAG 2 contrast maths for picking readable text colours. Pure Luau: colours are { r, g, b } in 0..1.

export type RGB = { r: number, g: number, b: number }

local ColorContrast = {}

-- WCAG minimum ratios. Large text is at least 24 px, or 18.5 px bold.
ColorContrast.AA = 4.5
ColorContrast.AA_LARGE = 3
ColorContrast.AAA = 7
ColorContrast.AAA_LARGE = 4.5

local function linear(channel: number): number
	local value = math.clamp(channel, 0, 1)
	if value <= 0.04045 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

-- Relative luminance: 0 for black, 1 for white.
function ColorContrast.luminance(color: RGB): number
	return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
end

-- Contrast ratio from 1 (identical colours) to 21 (black on white). The argument order does not matter.
function ColorContrast.ratio(a: RGB, b: RGB): number
	local first, second = ColorContrast.luminance(a), ColorContrast.luminance(b)
	return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
end

-- True when the pair meets AA (or AAA when `strict` is true), using the large-text threshold if `large`.
function ColorContrast.meets(a: RGB, b: RGB, large: boolean?, strict: boolean?): boolean
	local required: number
	if strict then
		required = if large then ColorContrast.AAA_LARGE else ColorContrast.AAA
	else
		required = if large then ColorContrast.AA_LARGE else ColorContrast.AA
	end
	return ColorContrast.ratio(a, b) >= required
end

-- The candidate with the highest contrast against `background`. `candidates` must not be empty.
function ColorContrast.best(background: RGB, candidates: { RGB }): RGB
	assert(#candidates > 0, "ColorContrast.best needs at least one candidate")
	local bestColor, bestRatio = candidates[1], -1
	for _, candidate in candidates do
		local value = ColorContrast.ratio(candidate, background)
		if value > bestRatio then
			bestColor, bestRatio = candidate, value
		end
	end
	return bestColor
end

return ColorContrast
