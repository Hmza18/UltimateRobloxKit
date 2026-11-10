--!strict
-- Visual themes at runtime. One theme is current; every visuals module reads motion and effect
-- tokens from here, and UrkUI game components follow it because `set` also switches the default
-- style (UI/Style/Style.setDefault).
--
--   Themes.set("Luxury")
--   Themes.token("motion.spring.press")  --> "Premium"
--   Themes.color("accent")               --> Color3
--
-- Components built before `set` keep the style they were built with: set the theme before
-- building UI, or rebuild on Themes.Changed. When UrkUI is running and was started with
-- `themes = Themes.urkThemes()`, `set` also switches its ThemeService, which re-skins base UrkUI
-- components live.
--
-- NOT run in Studio. Registry, validation and lookup are covered by Lune specs through
-- ThemeLogic; the Style / ThemeService / Color3 glue below is not.

local Context = require("../../UI/Runtime/Context")
local Signal = require("../../Util/Signal")
local Style = require("../../UI/Style/Style")
local StyleTokens = require("../../UI/Style/StyleTokens")
local ThemeData = require("./ThemeData")
local ThemeLogic = require("./ThemeLogic")

export type Theme = ThemeData.Theme

local Themes = {}

-- Fires (id, theme, previousId) after the current theme changes or is re-registered.
Themes.Changed = Signal.new()

Themes.IDS = ThemeData.IDS
Themes.DEFAULT = ThemeData.DEFAULT

local colorCache: { [string]: Color3 } = {}

local function toColor3(hex: string): Color3
	local cached = colorCache[hex]
	if cached then
		return cached
	end
	local r, g, b = ThemeLogic.rgb(hex)
	local color = Color3.new(r, g, b)
	colorCache[hex] = color
	return color
end

-- Switches the running UrkUI ThemeService when it knows a role theme with this id.
local function syncUrkUI(id: string)
	local context = Context.peek()
	local service = if context then context.theme else nil
	if service == nil then
		return
	end
	local ok, err = pcall(function()
		if service.name ~= id and table.find(service:names(), id) ~= nil then
			service:setTheme(id)
		end
	end)
	if not ok then
		warn("[Visuals] could not switch the UrkUI theme: " .. tostring(err))
	end
end

local registry = ThemeLogic.newRegistry(StyleTokens, function(id: string, theme: Theme, previous: string)
	Style.setDefault(theme.style)
	syncUrkUI(id)
	Themes.Changed:Fire(id, theme, previous)
end)

-- Makes `id` the current theme. Errors on an unknown id. Setting the current theme again only
-- re-applies the style default (cheap, and it repairs a default changed elsewhere).
function Themes.set(id: string): Theme
	local theme = registry.set(id)
	if Style.default() ~= theme.style then
		Style.setDefault(theme.style)
	end
	return theme
end

-- The theme table for `id`, or the current theme. Read-only: use Themes.derive for changes.
function Themes.get(id: string?): Theme
	return registry.get(id)
end

function Themes.current(): string
	return registry.current()
end

function Themes.has(id: string): boolean
	return registry.has(id)
end

-- Every registered theme id, sorted (the ten built-ins plus custom themes).
function Themes.names(): { string }
	return registry.names()
end

-- Registers a custom theme (validated; errors list every problem). Built-in ids and existing
-- custom ids need { override = true }. Returns the stored copy.
function Themes.register(id: string, theme: Theme, options: { override: boolean? }?): Theme
	return registry.register(id, theme, options)
end

-- A copy of a theme (id or table) with overrides merged in, ready for Themes.register:
--   Themes.register("Candy", Themes.derive("VibrantSimulator", { colors = { accent = "#C2185B" } }))
function Themes.derive(base: string | Theme, overrides: { [string]: any }?): Theme
	local source: Theme = if type(base) == "string" then registry.get(base) else base
	return ThemeLogic.derive(source, overrides)
end

-- A token by path from the current theme (or `id`), e.g. "motion.spring.press",
-- "motion.duration.fast", "effects.glow.soft.size". Tokens a custom theme lacks come from the
-- default theme; an unknown path returns nil.
function Themes.token(path: string, id: string?): any
	return registry.token(path, id)
end

-- A colour role ("accent"), rarity ("Legendary") or any "#RRGGBB" as a Color3.
function Themes.color(name: string, id: string?): Color3
	if ThemeLogic.isHex(name) then
		return toColor3(name)
	end
	local theme = registry.get(id)
	local hex = (theme.colors :: any)[name] or theme.rarity[name]
	if hex == nil then
		error("unknown theme colour: " .. tostring(name), 2)
	end
	return toColor3(hex)
end

-- The particle palette of the current theme (or `id`) as Color3s, for tinting VFX.
function Themes.particleColors(id: string?): { Color3 }
	local colors: { Color3 } = {}
	for _, hex in registry.get(id).effects.particles do
		table.insert(colors, toColor3(hex))
	end
	return colors
end

-- The styles.json key the current theme (or `id`) uses.
function Themes.style(id: string?): string
	return registry.get(id).style
end

-- Role themes for UrkUI.start({ themes = Themes.urkThemes(), theme = Themes.current() }), one
-- per registered theme, so base UrkUI components share the palette.
function Themes.urkThemes(): { [string]: any }
	local themes: { [string]: any } = {}
	for _, id in registry.names() do
		themes[id] = ThemeLogic.urkTheme(registry.get(id))
	end
	return themes
end

-- Problems in a theme table ({ path, kind, message }); empty when valid.
function Themes.validate(theme: Theme): { ThemeLogic.Problem }
	return ThemeLogic.validate(theme, StyleTokens)
end

return Themes
