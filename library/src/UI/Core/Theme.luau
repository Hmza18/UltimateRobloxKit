--!strict
-- Theme resolution: hex parsing, inheritance through `extends`, role lookup with state variants
-- ("primary:hover"), and validation of contrast. Pure Luau; colours are { r, g, b } in 0..1.

local Contrast = require("./Contrast")
local Tokens = require("./Tokens")

export type RGB = Contrast.RGB
export type ThemeDef = Tokens.ThemeDef

export type Resolved = { name: string, colors: { [string]: RGB }, transparency: { [string]: number } }

export type Problem = { kind: string, detail: string }

local Theme = {}

local MAX_DEPTH = 8

-- "#3D5AFE", "3D5AFE" or "#35F" -> { r, g, b }. Returns nil for anything else.
function Theme.hexToRgb(hex: string): RGB?
	if type(hex) ~= "string" then
		return nil
	end
	local digits = string.gsub(hex, "^#", "")
	if #digits == 3 then
		local r, g, b = string.sub(digits, 1, 1), string.sub(digits, 2, 2), string.sub(digits, 3, 3)
		digits = r .. r .. g .. g .. b .. b
	end
	if #digits ~= 6 or string.find(digits, "^%x+$") == nil then
		return nil
	end
	local red = tonumber(string.sub(digits, 1, 2), 16)
	local green = tonumber(string.sub(digits, 3, 4), 16)
	local blue = tonumber(string.sub(digits, 5, 6), 16)
	if red == nil or green == nil or blue == nil then
		return nil
	end
	return { r = red / 255, g = green / 255, b = blue / 255 }
end

function Theme.rgbToHex(color: RGB): string
	local function channel(value: number): number
		return math.clamp(math.floor(value * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", channel(color.r), channel(color.g), channel(color.b))
end

function Theme.mix(a: RGB, b: RGB, amount: number): RGB
	local t = math.clamp(amount, 0, 1)
	return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end

-- Interaction states derived from a base colour: lighter on dark colours, darker on light ones.
local STATE_AMOUNT: { [string]: number } = { hover = 0.12, pressed = 0.24, disabled = 0.5 }

function Theme.variant(color: RGB, state: string): RGB
	local amount = STATE_AMOUNT[state]
	if amount == nil then
		return color
	end
	local white = { r = 1, g = 1, b = 1 }
	local black = { r = 0, g = 0, b = 0 }
	if state == "disabled" then
		local grey = { r = 0.5, g = 0.5, b = 0.5 }
		return Theme.mix(color, grey, amount)
	end
	local towards = if Contrast.luminance(color) < 0.4 then white else black
	return Theme.mix(color, towards, amount)
end

-- Flattens `extends` chains into one resolved theme. Raises an error for unknown parents, cycles
-- or invalid hex values, so a typo is caught at start-up instead of producing a pink UI later.
function Theme.resolve(themes: { [string]: ThemeDef }, name: string): Resolved
	local chain: { ThemeDef } = {}
	local seen: { [string]: boolean } = {}
	local currentName: string? = name
	while currentName ~= nil do
		local key: string = currentName
		if seen[key] then
			error("theme inheritance cycle at " .. key, 2)
		end
		seen[key] = true
		local def = themes[key]
		if def == nil then
			error("unknown theme " .. key, 2)
		end
		table.insert(chain, 1, def)
		if #chain > MAX_DEPTH then
			error("theme inheritance too deep at " .. key, 2)
		end
		currentName = def.extends
	end
	local colors: { [string]: RGB } = {}
	local transparency: { [string]: number } = {}
	for _, def in chain do
		for role, hex in def.colors do
			local rgb = Theme.hexToRgb(hex)
			if rgb == nil then
				error(string.format("theme %s: role %s has invalid colour %s", def.name, role, tostring(hex)), 2)
			end
			colors[role] = rgb
		end
		if def.transparency then
			for role, value in def.transparency do
				transparency[role] = value
			end
		end
	end
	return { name = name, colors = colors, transparency = transparency }
end

-- Looks up "role" or "role:state" (state = hover, pressed, disabled). Falls back to `fallbackRole`,
-- then to "text". Returns nil only when the theme has neither.
function Theme.color(theme: Resolved, spec: string, fallbackRole: string?): RGB?
	local role, state = string.match(spec, "^([%w_]+):([%w_]+)$")
	local baseRole = role or spec
	local base = theme.colors[baseRole]
	if base == nil and fallbackRole then
		base = theme.colors[fallbackRole]
	end
	if base == nil then
		base = theme.colors.text
	end
	if base == nil then
		return nil
	end
	if state then
		return Theme.variant(base, state)
	end
	return base
end

function Theme.transparency(theme: Resolved, role: string): number
	return theme.transparency[role] or 0
end

-- Missing roles and failing contrast pairs. An empty list means the theme is usable.
-- `level` is "AA" or "AAA"; text pairs use the normal-text threshold, non-text pairs need 3:1.
function Theme.validate(theme: Resolved, level: string?): { Problem }
	local problems: { Problem } = {}
	for _, role in Tokens.ROLES do
		if theme.colors[role] == nil then
			table.insert(problems, { kind = "missing", detail = role })
		end
	end
	local required = Contrast.required(level, false)
	for _, pair in Tokens.TEXT_PAIRS do
		local foreground = theme.colors[pair[1]]
		local background = theme.colors[pair[2]]
		if foreground and background then
			local ratio = Contrast.ratio(foreground, background)
			if ratio < required then
				local detail = string.format("%s on %s is %.2f, needs %.1f", pair[1], pair[2], ratio, required)
				table.insert(problems, { kind = "contrast", detail = detail })
			end
		end
	end
	for _, pair in Tokens.NON_TEXT_PAIRS do
		local foreground = theme.colors[pair[1]]
		local background = theme.colors[pair[2]]
		if foreground and background then
			local ratio = Contrast.ratio(foreground, background)
			if ratio < Contrast.NON_TEXT then
				local detail = string.format("%s on %s is %.2f, needs 3.0", pair[1], pair[2], ratio)
				table.insert(problems, { kind = "contrast", detail = detail })
			end
		end
	end
	return problems
end

-- Merges caller themes over the built-ins without modifying either table.
function Theme.merge(base: { [string]: ThemeDef }, extra: { [string]: ThemeDef }?): { [string]: ThemeDef }
	local merged = table.clone(base)
	if extra then
		for name, def in extra do
			merged[name] = def
		end
	end
	return merged
end

-- Cycles through `order`, returning the theme after `current` (or the first one).
function Theme.nextName(order: { string }, current: string): string
	local index = table.find(order, current)
	if index == nil or index >= #order then
		return order[1]
	end
	return order[index + 1]
end

return Theme
