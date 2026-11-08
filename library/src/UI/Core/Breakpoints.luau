--!strict
-- Breakpoint maths: classify a viewport and input mix as phone, tablet, desktop or console, pick a
-- UIScale, and choose per-breakpoint attribute overrides such as "Phone_Size". Pure Luau:
-- sizes are { x, y } tables in pixels. Runtime/Responsive feeds it the live camera and input state.

export type Size = { x: number, y: number }

export type InputState = {
	touch: boolean?, -- a touch screen is available
	gamepad: boolean?, -- a gamepad is the last used input
	keyboard: boolean?, -- a keyboard is available
	tenFoot: boolean?, -- GuiService:IsTenFootInterface() (console or TV)
}

export type Thresholds = {
	phoneShortSide: number, -- below this short side (px) the layout is "phone"
	tabletShortSide: number, -- touch devices below this short side are "tablet"
	desktopMinWidth: number, -- non-touch windows narrower than this use "tablet"
}

export type ScaleOptions = {
	reference: { [string]: Size }?, -- design resolution per breakpoint
	min: number?,
	max: number?,
	userScale: number?, -- accessibility multiplier from settings, default 1
}

local Breakpoints = {}

Breakpoints.NAMES = { "phone", "tablet", "desktop", "console" }

Breakpoints.defaultThresholds = { phoneShortSide = 500, tabletShortSide = 900, desktopMinWidth = 1000 } :: Thresholds

Breakpoints.defaultReference = {
	phone = { x = 844, y = 390 },
	tablet = { x = 1180, y = 820 },
	desktop = { x = 1920, y = 1080 },
	console = { x = 1920, y = 1080 },
} :: { [string]: Size }

-- Attribute prefixes for each breakpoint, in lookup order. Console layouts fall back to desktop ones.
local PREFIXES: { [string]: { string } } = {
	phone = { "Phone" },
	tablet = { "Tablet" },
	desktop = { "Desktop" },
	console = { "Console", "Desktop" },
}

local KNOWN_PREFIX: { [string]: boolean } = { Phone = true, Tablet = true, Desktop = true, Console = true }

function Breakpoints.classify(viewport: Size, input: InputState?, thresholds: Thresholds?): string
	local limits = thresholds or Breakpoints.defaultThresholds
	local state: InputState = input or {}
	if state.tenFoot then
		return "console"
	end
	local shortSide = math.min(viewport.x, viewport.y)
	if shortSide <= 0 then
		return "desktop"
	end
	if shortSide < limits.phoneShortSide then
		return "phone"
	end
	if state.touch and not state.keyboard then
		if shortSide < limits.tabletShortSide then
			return "tablet"
		end
		return "desktop"
	end
	if state.gamepad and not state.keyboard and not state.touch then
		return "console"
	end
	if viewport.x < limits.desktopMinWidth then
		return "tablet"
	end
	return "desktop"
end

function Breakpoints.isValid(name: any): boolean
	return type(name) == "string" and PREFIXES[name] ~= nil
end

-- UIScale that fits the breakpoint's reference resolution into the viewport, clamped to min..max
-- and multiplied by the user's accessibility scale.
function Breakpoints.scale(viewport: Size, breakpoint: string, options: ScaleOptions?): number
	local opts: ScaleOptions = options or {}
	local references = opts.reference or Breakpoints.defaultReference
	local reference = references[breakpoint] or Breakpoints.defaultReference.desktop
	if viewport.x <= 0 or viewport.y <= 0 or reference.x <= 0 or reference.y <= 0 then
		return 1
	end
	local fit = math.min(viewport.x / reference.x, viewport.y / reference.y)
	local clamped = math.clamp(fit, opts.min or 0.6, opts.max or 1.5)
	return clamped * (opts.userScale or 1)
end

-- "Size" + "phone" -> "Phone_Size".
function Breakpoints.attributeName(property: string, breakpoint: string): string
	local prefixes = PREFIXES[breakpoint]
	local prefix = if prefixes then prefixes[1] else "Desktop"
	return prefix .. "_" .. property
end

-- Picks the value for `property` from an attribute table: the breakpoint override if present
-- (console also tries Desktop_), else `base`. Returns the value and the attribute name used.
function Breakpoints.pick(values: { [string]: any }, property: string, breakpoint: string, base: any): (any, string?)
	local prefixes = PREFIXES[breakpoint] or {}
	for _, prefix in prefixes do
		local name = prefix .. "_" .. property
		local value = values[name]
		if value ~= nil then
			return value, name
		end
	end
	return base, nil
end

-- Every responsive property mentioned in an attribute table ("Phone_Size" -> "Size"), sorted.
function Breakpoints.properties(attributes: { [string]: any }): { string }
	local found: { [string]: boolean } = {}
	for name in attributes do
		local prefix, property = string.match(name, "^(%a+)_(.+)$")
		if prefix and property and KNOWN_PREFIX[prefix] then
			found[property] = true
		end
	end
	local list: { string } = {}
	for property in found do
		table.insert(list, property)
	end
	table.sort(list)
	return list
end

return Breakpoints
