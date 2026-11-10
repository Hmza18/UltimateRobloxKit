--!strict
-- Theme rules (pure): validation, WCAG contrast, token lookup with fallback, deriving custom
-- themes, and the registry Themes.luau wraps. No Roblox globals, so all of it runs under Lune.

local Curves = require("../Core/Curves")
local Springs = require("../Core/Springs")
local ThemeData = require("./ThemeData")

export type Theme = ThemeData.Theme
export type Problem = { path: string, kind: "missing" | "invalid" | "contrast", message: string }

export type Registry = {
	register: (id: string, theme: Theme, options: { override: boolean? }?) -> Theme,
	get: (id: string?) -> Theme,
	has: (id: string) -> boolean,
	names: () -> { string },
	set: (id: string) -> Theme,
	current: () -> string,
	token: (path: string, id: string?) -> any,
}

local ThemeLogic = {}

-- Minimum WCAG ratios: body text on its surfaces, and non-text accents against the background.
ThemeLogic.TEXT_CONTRAST = 4.5
ThemeLogic.ACCENT_CONTRAST = 3

local HEX = "^#%x%x%x%x%x%x$"

function ThemeLogic.isHex(value: any): boolean
	return type(value) == "string" and string.find(value, HEX) ~= nil
end

-- Channels of "#RRGGBB" in 0..1.
function ThemeLogic.rgb(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	if not (r and g and b) then
		error("colour must be #RRGGBB: " .. tostring(hex), 2)
	end
	return (tonumber(r, 16) :: number) / 255, (tonumber(g, 16) :: number) / 255, (tonumber(b, 16) :: number) / 255
end

local function linear(channel: number): number
	return if channel <= 0.03928 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
end

-- WCAG 2 relative luminance, 0 (black) to 1 (white).
function ThemeLogic.luminance(hex: string): number
	local r, g, b = ThemeLogic.rgb(hex)
	return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

-- WCAG 2 contrast ratio, 1 to 21. Order does not matter.
function ThemeLogic.contrast(a: string, b: string): number
	local la, lb = ThemeLogic.luminance(a), ThemeLogic.luminance(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

-- Blend of two colours; k = 0 returns a, k = 1 returns b.
function ThemeLogic.mix(a: string, b: string, k: number): string
	local ar, ag, ab = ThemeLogic.rgb(a)
	local br, bg, bb = ThemeLogic.rgb(b)
	local t = math.clamp(k, 0, 1)
	local function channel(x: number, y: number): number
		return math.clamp(math.floor((x + (y - x) * t) * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", channel(ar, br), channel(ag, bg), channel(ab, bb))
end

-- Whichever of `light` / `dark` (default white / near-black) reads better on `background`.
function ThemeLogic.readableOn(background: string, light: string?, dark: string?): string
	local lightColor = light or "#FFFFFF"
	local darkColor = dark or "#111111"
	if ThemeLogic.contrast(lightColor, background) >= ThemeLogic.contrast(darkColor, background) then
		return lightColor
	end
	return darkColor
end

-- Moves `color` away from `background` (toward black or white) in small steps until the pair
-- reaches `ratio`. Returns the adjusted colour; the input when it already passes.
function ThemeLogic.ensureContrast(color: string, background: string, ratio: number?): string
	local need = ratio or ThemeLogic.TEXT_CONTRAST
	local target = if ThemeLogic.luminance(background) < 0.4 then "#FFFFFF" else "#000000"
	local result = color
	local k = 0
	while ThemeLogic.contrast(result, background) < need and k < 1 do
		k += 0.02
		result = ThemeLogic.mix(color, target, k)
	end
	return result
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepClone(item)
	end
	return copy
end

local function isArray(value: { [any]: any }): boolean
	return #value > 0
end

-- Tables merge key by key; arrays and scalars in `extra` replace what is there.
local function deepMerge(base: any, extra: any): any
	local out = deepClone(base)
	for key, value in extra do
		if type(value) == "table" and type(out[key]) == "table" and not isArray(value) and not isArray(out[key]) then
			out[key] = deepMerge(out[key], value)
		else
			out[key] = deepClone(value)
		end
	end
	return out
end

ThemeLogic.clone = deepClone :: (theme: Theme) -> Theme

-- Reads "motion.spring.press" style paths. Numeric segments index arrays ("effects.particles.1").
-- A missing token falls back to `base` (another theme) and then to nil.
function ThemeLogic.token(theme: Theme, path: string, base: Theme?): any
	local function walk(root: any): any
		local node = root
		for segment in string.gmatch(path, "[^%.]+") do
			if type(node) ~= "table" then
				return nil
			end
			local index = tonumber(segment)
			node = if index ~= nil and node[index] ~= nil then node[index] else node[segment]
		end
		return node
	end
	local value = walk(theme)
	if value == nil and base ~= nil then
		value = walk(base)
	end
	return value
end

-- The built-in theme for an id, or nil.
function ThemeLogic.builtin(id: string): Theme?
	return ThemeData.themes[id]
end

-- The styles.json key a theme (or theme id) skins UrkUI components with.
function ThemeLogic.styleKey(theme: string | Theme): string
	if type(theme) == "string" then
		local found = ThemeData.themes[theme]
		if found == nil then
			error("unknown theme: " .. theme, 2)
		end
		return found.style
	end
	return theme.style
end

-- The built-in theme id for a styles.json key ("vibrant" -> "VibrantSimulator"), or nil.
function ThemeLogic.themeForStyle(style: string): string?
	return ThemeData.byStyle[style]
end

-- A new theme: a deep copy of `base` (a built-in id or a theme table) with `overrides` merged in.
-- overrides.id names it; without one the id is "<base id>Custom". The result is not validated:
-- call ThemeLogic.validate, or Themes.register, which does.
function ThemeLogic.derive(base: string | Theme, overrides: { [string]: any }?): Theme
	local source: Theme
	if type(base) == "string" then
		local found = ThemeData.themes[base]
		if found == nil then
			error("unknown base theme: " .. base, 2)
		end
		source = found
	else
		source = base
	end
	local theme: Theme = deepMerge(source, overrides or {})
	if overrides == nil or overrides.id == nil then
		theme.id = source.id .. "Custom"
	end
	return theme
end

-- The theme as a UrkUI role theme (UI/Core/Tokens.ThemeDef), so base UrkUI components (buttons,
-- inputs, tooltips) match the game components. Pass the result of Themes.urkThemes() to
-- UrkUI.start({ themes = ... }). "on" colours and the focus ring are pushed until they meet AA.
function ThemeLogic.urkTheme(
	theme: Theme
): { name: string, colors: { [string]: string }, transparency: { [string]: number } }
	local c = theme.colors
	local function on(background: string): string
		return ThemeLogic.readableOn(background, "#FFFFFF", "#000000")
	end
	local surfaceAlt = ThemeLogic.mix(c.surface, c.text, 0.07)
	if
		ThemeLogic.contrast(c.text, surfaceAlt) < ThemeLogic.TEXT_CONTRAST
		or ThemeLogic.contrast(c.textMuted, surfaceAlt) < ThemeLogic.TEXT_CONTRAST
	then
		surfaceAlt = c.surface
	end
	local border = ThemeLogic.ensureContrast(c.border, c.surface, ThemeLogic.ACCENT_CONTRAST)
	local focus = ThemeLogic.ensureContrast(c.accent, c.background, ThemeLogic.ACCENT_CONTRAST)
	focus = ThemeLogic.ensureContrast(focus, c.surface, ThemeLogic.ACCENT_CONTRAST)
	return {
		name = theme.id,
		colors = {
			background = c.background,
			surface = c.surface,
			surfaceAlt = surfaceAlt,
			border = border,
			text = c.text,
			textMuted = c.textMuted,
			primary = c.primary,
			onPrimary = on(c.primary),
			secondary = c.secondary,
			onSecondary = on(c.secondary),
			danger = c.error,
			onDanger = on(c.error),
			success = c.success,
			onSuccess = on(c.success),
			warning = c.warning,
			onWarning = on(c.warning),
			info = c.secondary,
			onInfo = on(c.secondary),
			focus = focus,
			overlay = "#000000",
		},
		transparency = { overlay = 0.45, surface = 0, ghost = 1 },
	}
end

local function push(problems: { Problem }, path: string, kind: "missing" | "invalid" | "contrast", message: string)
	table.insert(problems, { path = path, kind = kind, message = message })
end

-- Every problem in a theme, sorted by path; an empty list means valid. `styles` is the set of
-- known style keys (pass the StyleTokens module) and is optional.
function ThemeLogic.validate(theme: any, styles: { [string]: any }?): { Problem }
	local problems: { Problem } = {}
	if type(theme) ~= "table" then
		push(problems, "", "invalid", "theme must be a table")
		return problems
	end

	local function section(name: string): { [string]: any }?
		local value = theme[name]
		if type(value) ~= "table" then
			push(problems, name, "missing", "section is required")
			return nil
		end
		return value
	end
	local function hex(path: string, value: any)
		if value == nil then
			push(problems, path, "missing", "colour is required")
		elseif not ThemeLogic.isHex(value) then
			push(problems, path, "invalid", "colour must be #RRGGBB, got " .. tostring(value))
		end
	end
	local function number(path: string, value: any, min: number?, max: number?)
		if value == nil then
			push(problems, path, "missing", "number is required")
		elseif type(value) ~= "number" or value ~= value then
			push(problems, path, "invalid", "must be a number, got " .. tostring(value))
		elseif (min ~= nil and value < min) or (max ~= nil and value > max) then
			push(
				problems,
				path,
				"invalid",
				string.format("%s is outside %s..%s", tostring(value), tostring(min), tostring(max))
			)
		end
	end
	local function text(path: string, value: any)
		if value == nil then
			push(problems, path, "missing", "text is required")
		elseif type(value) ~= "string" or value == "" then
			push(problems, path, "invalid", "must be a non-empty string")
		end
	end
	local function group(path: string, value: any): { [string]: any }
		if type(value) ~= "table" then
			push(problems, path, "missing", "table is required")
			return {}
		end
		return value
	end

	local function list(path: string, value: any): { any }
		if type(value) ~= "table" then
			push(problems, path, "missing", "list is required")
			return {}
		end
		return value
	end

	for _, key in { "id", "style", "name", "description" } do
		text(key, theme[key])
	end
	if styles ~= nil and type(theme.style) == "string" and styles[theme.style] == nil then
		push(problems, "style", "invalid", "unknown style key: " .. theme.style)
	end

	local colors = section("colors")
	if colors then
		for _, role in ThemeData.COLOR_ROLES do
			hex("colors." .. role, colors[role])
		end
		local function pair(a: string, b: string, need: number)
			if ThemeLogic.isHex(colors[a]) and ThemeLogic.isHex(colors[b]) then
				local ratio = ThemeLogic.contrast(colors[a], colors[b])
				if ratio < need then
					local message = string.format("%s on %s is %.2f:1, needs %.1f:1", a, b, ratio, need)
					push(problems, "colors." .. a, "contrast", message)
				end
			end
		end
		pair("text", "background", ThemeLogic.TEXT_CONTRAST)
		pair("text", "surface", ThemeLogic.TEXT_CONTRAST)
		pair("textMuted", "background", ThemeLogic.TEXT_CONTRAST)
		pair("textMuted", "surface", ThemeLogic.TEXT_CONTRAST)
		pair("accent", "background", ThemeLogic.ACCENT_CONTRAST)
		pair("primary", "background", ThemeLogic.ACCENT_CONTRAST)
	end

	local rarity = section("rarity")
	if rarity then
		for _, name in ThemeData.RARITIES do
			hex("rarity." .. name, rarity[name])
		end
	end

	local typography = section("typography")
	if typography then
		local fonts = group("typography.fonts", typography.fonts)
		local weights = group("typography.weights", typography.weights)
		local sizes = group("typography.sizes", typography.sizes)
		for _, role in ThemeData.TEXT_ROLES do
			text("typography.fonts." .. role, fonts[role])
			text("typography.weights." .. role, weights[role])
			number("typography.sizes." .. role, sizes[role], 8, 200)
		end
		text("typography.fallback", typography.fallback)
		local strokes = group("typography.stroke", typography.stroke)
		for _, name in { "title", "body", "number" } do
			local stroke = group("typography.stroke." .. name, strokes[name])
			hex("typography.stroke." .. name .. ".color", stroke.color)
			number("typography.stroke." .. name .. ".thickness", stroke.thickness, 0, 16)
			number("typography.stroke." .. name .. ".transparency", stroke.transparency, 0, 1)
		end
		local shadows = group("typography.shadow", typography.shadow)
		for _, name in { "soft", "hard" } do
			local shadow = group("typography.shadow." .. name, shadows[name])
			hex("typography.shadow." .. name .. ".color", shadow.color)
			number("typography.shadow." .. name .. ".offsetY", shadow.offsetY)
			number("typography.shadow." .. name .. ".transparency", shadow.transparency, 0, 1)
		end
		local scale = group("typography.scale", typography.scale)
		for _, name in ThemeData.BREAKPOINTS do
			number("typography.scale." .. name, scale[name], 0.5, 2)
		end
		local numbers = group("typography.numbers", typography.numbers)
		text("typography.numbers.style", numbers.style)
		number("typography.numbers.decimals", numbers.decimals, 0, 3)
	end

	local layout = section("layout")
	if layout then
		local spacing = group("layout.spacing", layout.spacing)
		for _, name in { "xs", "sm", "md", "lg", "xl", "xxl" } do
			number("layout.spacing." .. name, spacing[name], 0)
		end
		local radius = group("layout.radius", layout.radius)
		for _, name in { "sm", "md", "lg", "xl", "pill" } do
			number("layout.radius." .. name, radius[name], 0)
		end
		local padding = group("layout.padding", layout.padding)
		for _, name in { "screen", "panel", "card", "button", "chip" } do
			number("layout.padding." .. name, padding[name], 0)
		end
		local margin = group("layout.margin", layout.margin)
		for _, name in { "screen", "section", "item" } do
			number("layout.margin." .. name, margin[name], 0)
		end
		local safeArea = group("layout.safeArea", layout.safeArea)
		text("layout.safeArea.policy", safeArea.policy)
		number("layout.safeArea.minInset", safeArea.minInset, 0)
		local breakpoints = group("layout.breakpoints", layout.breakpoints)
		for _, name in ThemeData.BREAKPOINTS do
			local entry = group("layout.breakpoints." .. name, breakpoints[name])
			number("layout.breakpoints." .. name .. ".columns", entry.columns, 1)
			number("layout.breakpoints." .. name .. ".hudScale", entry.hudScale, 0.5, 2)
		end
		local layers = group("layout.layers", layout.layers)
		local previous = -math.huge
		for _, name in ThemeData.LAYER_NAMES do
			number("layout.layers." .. name, layers[name])
			if type(layers[name]) == "number" then
				if layers[name] <= previous then
					push(
						problems,
						"layout.layers." .. name,
						"invalid",
						"layers must rise: hud < panel < modal < toast < reveal < debug"
					)
				end
				previous = layers[name]
			end
		end
	end

	local motion = section("motion")
	if motion then
		local duration = group("motion.duration", motion.duration)
		local last = -1
		for _, name in ThemeData.DURATIONS do
			number("motion.duration." .. name, duration[name], 0, 10)
			if type(duration[name]) == "number" then
				if duration[name] < last then
					push(
						problems,
						"motion.duration." .. name,
						"invalid",
						"durations must not shrink: instant <= fast <= normal <= slow <= cinematic"
					)
				end
				last = duration[name]
			end
		end
		if motion.easing == nil then
			push(problems, "motion.easing", "missing", "easing is required")
		elseif type(motion.easing) ~= "string" or not Curves.has(motion.easing) then
			push(problems, "motion.easing", "invalid", "unknown curve: " .. tostring(motion.easing))
		end
		local springs = group("motion.spring", motion.spring)
		for _, role in ThemeData.SPRING_ROLES do
			local name = springs[role]
			if name == nil then
				push(problems, "motion.spring." .. role, "missing", "spring is required")
			elseif type(name) ~= "string" or not Springs.has(name) then
				push(problems, "motion.spring." .. role, "invalid", "unknown spring preset: " .. tostring(name))
			end
		end
		number("motion.intensity", motion.intensity, 0, 3)
		number("motion.stagger", motion.stagger, 0, 1)
		local scale = group("motion.scale", motion.scale)
		number("motion.scale.hover", scale.hover, 1, 2)
		number("motion.scale.press", scale.press, 0.5, 1)
		number("motion.scale.pop", scale.pop, 1, 2)
		local transition = group("motion.transition", motion.transition)
		local reduced = group("motion.reduced", motion.reduced)
		local reducedTransition = group("motion.reduced.transition", reduced.transition)
		local transitionSources: { [string]: { [string]: any } } = {
			["motion.transition."] = transition,
			["motion.reduced.transition."] = reducedTransition,
		}
		for _, role in ThemeData.TRANSITION_ROLES do
			for prefix, source in transitionSources do
				local style = source[role]
				if style == nil then
					push(problems, prefix .. role, "missing", "transition is required")
				elseif table.find(ThemeData.TRANSITIONS, style) == nil then
					push(problems, prefix .. role, "invalid", "unknown transition: " .. tostring(style))
				end
			end
			-- Reduced motion never travels or overshoots.
			local substitute = reducedTransition[role]
			if substitute ~= nil and substitute ~= "fade" and substitute ~= "none" then
				push(
					problems,
					"motion.reduced.transition." .. role,
					"invalid",
					"reduced motion allows only fade or none"
				)
			end
		end
		if reduced.spring == nil then
			push(problems, "motion.reduced.spring", "missing", "spring is required")
		elseif type(reduced.spring) ~= "string" or not Springs.has(reduced.spring) then
			push(problems, "motion.reduced.spring", "invalid", "unknown spring preset: " .. tostring(reduced.spring))
		elseif Springs.get(reduced.spring).damping < 1 then
			push(problems, "motion.reduced.spring", "invalid", "reduced motion needs a spring that does not overshoot")
		end
		if type(reduced.easing) ~= "string" or not Curves.has(reduced.easing) then
			push(problems, "motion.reduced.easing", "invalid", "unknown curve: " .. tostring(reduced.easing))
		end
		number("motion.reduced.durationScale", reduced.durationScale, 0, 1)
	end

	local effects = section("effects")
	if effects then
		local shadows = group("effects.shadow", effects.shadow)
		for _, name in { "sm", "md", "lg" } do
			local shadow = group("effects.shadow." .. name, shadows[name])
			hex("effects.shadow." .. name .. ".color", shadow.color)
			number("effects.shadow." .. name .. ".offsetY", shadow.offsetY)
			number("effects.shadow." .. name .. ".transparency", shadow.transparency, 0, 1)
		end
		local glows = group("effects.glow", effects.glow)
		for _, name in { "soft", "strong", "reward" } do
			local glow = group("effects.glow." .. name, glows[name])
			hex("effects.glow." .. name .. ".color", glow.color)
			number("effects.glow." .. name .. ".size", glow.size, 0)
			number("effects.glow." .. name .. ".transparency", glow.transparency, 0, 1)
		end
		local gradients = group("effects.gradient", effects.gradient)
		for _, name in { "primary", "accent", "surface", "reward" } do
			local gradient = group("effects.gradient." .. name, gradients[name])
			number("effects.gradient." .. name .. ".rotation", gradient.rotation, -360, 360)
			local stops = list("effects.gradient." .. name .. ".stops", gradient.stops)
			if #stops < 2 then
				push(
					problems,
					"effects.gradient." .. name .. ".stops",
					"invalid",
					"a gradient needs at least two stops"
				)
			end
			local at = -1
			for index, stop in stops do
				local path = string.format("effects.gradient.%s.stops.%d", name, index)
				if type(stop) ~= "table" then
					push(problems, path, "invalid", "stop must be { at, color }")
					continue
				end
				hex(path .. ".color", stop.color)
				number(path .. ".at", stop.at, 0, 1)
				if type(stop.at) == "number" then
					if stop.at <= at then
						push(problems, path .. ".at", "invalid", "stops must be in rising order")
					end
					at = stop.at
				end
			end
		end
		local outlines = group("effects.outline", effects.outline)
		for _, name in { "thin", "regular", "bold" } do
			local outline = group("effects.outline." .. name, outlines[name])
			hex("effects.outline." .. name .. ".color", outline.color)
			number("effects.outline." .. name .. ".thickness", outline.thickness, 0, 32)
		end
		local highlights = group("effects.highlight", effects.highlight)
		for _, name in { "select", "hover", "reward" } do
			local highlight = group("effects.highlight." .. name, highlights[name])
			hex("effects.highlight." .. name .. ".fill", highlight.fill)
			hex("effects.highlight." .. name .. ".outline", highlight.outline)
			number("effects.highlight." .. name .. ".fillTransparency", highlight.fillTransparency, 0, 1)
			number("effects.highlight." .. name .. ".outlineTransparency", highlight.outlineTransparency, 0, 1)
		end
		local shines = group("effects.shine", effects.shine)
		for _, name in { "subtle", "sweep", "reward" } do
			local shine = group("effects.shine." .. name, shines[name])
			hex("effects.shine." .. name .. ".color", shine.color)
			number("effects.shine." .. name .. ".angle", shine.angle, -360, 360)
			number("effects.shine." .. name .. ".width", shine.width, 0, 1)
			number("effects.shine." .. name .. ".speed", shine.speed, 0)
			number("effects.shine." .. name .. ".transparency", shine.transparency, 0, 1)
		end
		local particles = list("effects.particles", effects.particles)
		if #particles < 3 or #particles > 5 then
			push(problems, "effects.particles", "invalid", "the particle palette needs 3 to 5 colours")
		end
		for index, color in particles do
			hex("effects.particles." .. tostring(index), color)
		end
		text("effects.sparkle", effects.sparkle)
	end

	table.sort(problems, function(a: Problem, b: Problem): boolean
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.message < b.message
	end)
	return problems
end

function ThemeLogic.isValid(theme: any, styles: { [string]: any }?): boolean
	return #ThemeLogic.validate(theme, styles) == 0
end

-- One line per problem, for error messages.
function ThemeLogic.describe(problems: { Problem }): string
	local lines: { string } = {}
	for _, problem in problems do
		table.insert(
			lines,
			string.format("%s: %s", if problem.path == "" then "theme" else problem.path, problem.message)
		)
	end
	return table.concat(lines, "; ")
end

-- The theme registry behind Themes.luau: the ten built-ins plus registered customs, one current
-- theme, and token lookup that falls back to the default theme. `styles` (the StyleTokens
-- module) lets register reject themes that name an unknown style; `onChange` fires after set.
function ThemeLogic.newRegistry(
	styles: { [string]: any }?,
	onChange: ((id: string, theme: Theme, previous: string) -> ())?
): Registry
	local themes: { [string]: Theme } = {}
	for id, theme in ThemeData.themes do
		themes[id] = theme
	end
	local current = ThemeData.DEFAULT

	local function get(id: string?): Theme
		local key = id or current
		local theme = themes[key]
		if theme == nil then
			error("unknown theme: " .. tostring(key), 2)
		end
		return theme
	end

	local function register(id: string, theme: Theme, options: { override: boolean? }?): Theme
		if type(id) ~= "string" or id == "" then
			error("theme id required", 2)
		end
		if themes[id] ~= nil and not (options and options.override) then
			error("theme already registered: " .. id .. " (pass { override = true } to replace it)", 2)
		end
		local copy = deepClone(theme)
		copy.id = id
		local problems = ThemeLogic.validate(copy, styles)
		if #problems > 0 then
			error("invalid theme " .. id .. ": " .. ThemeLogic.describe(problems), 2)
		end
		themes[id] = copy
		if id == current and onChange then
			onChange(id, copy, id)
		end
		return copy
	end

	local function names(): { string }
		local list: { string } = {}
		for id in themes do
			table.insert(list, id)
		end
		table.sort(list)
		return list
	end

	local function set(id: string): Theme
		local theme = themes[id]
		if theme == nil then
			error("unknown theme: " .. tostring(id), 2)
		end
		local previous = current
		current = id
		if previous ~= id and onChange then
			onChange(id, theme, previous)
		end
		return theme
	end

	return {
		register = register,
		get = get,
		has = function(id: string): boolean
			return themes[id] ~= nil
		end,
		names = names,
		set = set,
		current = function(): string
			return current
		end,
		token = function(path: string, id: string?): any
			return ThemeLogic.token(get(id), path, ThemeData.themes[ThemeData.DEFAULT])
		end,
	}
end

return ThemeLogic
