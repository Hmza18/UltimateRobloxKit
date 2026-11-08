--!strict
-- Game style resolver (pure). Styles come from the generated StyleTokens module, whose source is
-- design/tokens/styles.json. Components ask this module for colours, outlines and fonts, so a new
-- theme is a JSON change, never a component change.

local StyleTokens = require("./StyleTokens")

export type Swatch = { top: string, bottom: string, text: string }
export type ButtonDef = { palette: string?, surface: string?, icon: string? }
export type BadgeDef = { palette: string, shape: string, text: string? }
export type RarityDef = { color: string, rainbow: boolean? }
export type StyleDef = { [string]: any }

local Style = {}

local defaultName = "cartoon"
local FALLBACK_PALETTE = "blue"

function Style.names(): { string }
	local names: { string } = {}
	for name in StyleTokens do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Style.setDefault(name: string)
	assert(StyleTokens[name] ~= nil, "unknown style: " .. tostring(name))
	defaultName = name
end

function Style.default(): string
	return defaultName
end

function Style.get(name: string?): StyleDef
	local key = name or defaultName
	local style = StyleTokens[key]
	assert(style ~= nil, "unknown style: " .. tostring(key))
	return style
end

function Style.palette(style: StyleDef, name: string?): Swatch
	local palette = style.palette
	local swatch = palette[name or FALLBACK_PALETTE] or palette[FALLBACK_PALETTE]
	return swatch :: Swatch
end

function Style.hasPalette(style: StyleDef, name: string): boolean
	return style.palette[name] ~= nil
end

function Style.surface(style: StyleDef, name: string?): Swatch
	local surfaces = style.surfaces
	return (surfaces[name or "window"] or surfaces.window) :: Swatch
end

function Style.button(style: StyleDef, kind: string?): ButtonDef
	local buttons = style.buttons
	return (buttons[kind or "primary"] or buttons.primary) :: ButtonDef
end

function Style.badge(style: StyleDef, kind: string?): BadgeDef
	local badges = style.badges
	return (badges[kind or "new"] or badges.new) :: BadgeDef
end

function Style.rarity(style: StyleDef, name: string?): RarityDef
	local rarity = style.rarity
	return (rarity[name or "common"] or rarity.common) :: RarityDef
end

-- Outline thickness in pixels for "thin", "regular" (default), "thick" or "heavy".
function Style.outline(style: StyleDef, weight: string?): number
	local outline = style.outline
	local value = outline[weight or "regular"]
	return if type(value) == "number" then value else outline.regular
end

function Style.outlineColor(style: StyleDef): string
	return style.outline.color
end

-- Font family names for Font.fromName (title, body, number) with a fallback for older clients.
function Style.font(style: StyleDef, role: string?): string
	local fonts = style.fonts
	return fonts[role or "body"] or fonts.fallback
end

function Style.textSize(style: StyleDef, role: string?): number
	local text = style.text
	return text[role or "label"] or text.label
end

local function clamp(x: number): number
	return math.clamp(math.floor(x + 0.5), 0, 255)
end

local function parse(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	assert(r and g and b, "colour must be #RRGGBB: " .. tostring(hex))
	return tonumber(r, 16) :: number, tonumber(g, 16) :: number, tonumber(b, 16) :: number
end

local function format(r: number, g: number, b: number): string
	return string.format("#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
end

-- Moves a colour toward black (darken) or white (lighten) by `amount` in 0..1.
function Style.darken(hex: string, amount: number): string
	local r, g, b = parse(hex)
	local k = 1 - math.clamp(amount, 0, 1)
	return format(r * k, g * k, b * k)
end

function Style.lighten(hex: string, amount: number): string
	local r, g, b = parse(hex)
	local k = math.clamp(amount, 0, 1)
	return format(r + (255 - r) * k, g + (255 - g) * k, b + (255 - b) * k)
end

function Style.rgb(hex: string): { r: number, g: number, b: number }
	local r, g, b = parse(hex)
	return { r = r, g = g, b = b }
end

return Style
