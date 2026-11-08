--!strict
-- Design tokens and the built-in themes. Pure data: colours are hex strings, sizes are pixels,
-- durations are seconds. Runtime/ThemeService converts them to Color3, UDim and Font.
-- Override any of these through UrkUI.start({ tokens = ..., themes = ... }) instead of editing this file.

export type ThemeDef = {
	name: string,
	extends: string?,
	colors: { [string]: string },
	transparency: { [string]: number }?,
}

export type TokenSet = {
	spacing: { [string]: number },
	radius: { [string]: number },
	stroke: { [string]: number },
	text: { [string]: number },
	fonts: { [string]: string },
	motion: { [string]: number },
	layers: { [string]: number },
	sizes: { [string]: { height: number, padding: number, text: number } },
}

local Tokens = {}

-- Every theme must define these roles (Theme.validate checks it).
Tokens.ROLES = {
	"background",
	"surface",
	"surfaceAlt",
	"border",
	"text",
	"textMuted",
	"primary",
	"onPrimary",
	"secondary",
	"onSecondary",
	"danger",
	"onDanger",
	"success",
	"onSuccess",
	"warning",
	"onWarning",
	"info",
	"onInfo",
	"focus",
	"overlay",
}

-- Text/background pairs that must stay readable, and non-text pairs that need 3:1.
Tokens.TEXT_PAIRS = {
	{ "text", "background" },
	{ "text", "surface" },
	{ "text", "surfaceAlt" },
	{ "textMuted", "surface" },
	{ "textMuted", "background" },
	{ "onPrimary", "primary" },
	{ "onSecondary", "secondary" },
	{ "onDanger", "danger" },
	{ "onSuccess", "success" },
	{ "onWarning", "warning" },
	{ "onInfo", "info" },
}

Tokens.NON_TEXT_PAIRS = { { "focus", "background" }, { "focus", "surface" }, { "border", "surface" } }

Tokens.defaults = {
	spacing = { none = 0, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 },
	radius = { none = 0, sm = 4, md = 8, lg = 12, xl = 16, pill = 999 },
	stroke = { thin = 1, regular = 2, thick = 3 },
	-- Text sizes in pixels before UIScale. `minimum` is the floor the accessibility setting enforces.
	text = { caption = 14, body = 16, label = 18, title = 22, heading = 28, display = 40, minimum = 12 },
	-- Font families for Font.fromName; weights come from the text role (see Runtime/ThemeService).
	fonts = { family = "BuilderSans", fallback = "GothamSSm" },
	-- Seconds. Reduced motion turns every duration into 0.
	motion = { instant = 0, fast = 0.12, normal = 0.2, slow = 0.35, toast = 0.25 },
	-- DisplayOrder bands for ScreenGuis and ZIndex bands inside them.
	layers = { hud = 0, panel = 10, modal = 50, toast = 80, tooltip = 90, menu = 95, drag = 100 },
	sizes = {
		sm = { height = 32, padding = 10, text = 14 },
		md = { height = 44, padding = 16, text = 18 },
		lg = { height = 56, padding = 22, text = 22 },
	},
} :: TokenSet

Tokens.themes = {
	dark = {
		name = "dark",
		colors = {
			background = "#0F1220",
			surface = "#1A1F33",
			surfaceAlt = "#252B45",
			border = "#7A84AD",
			text = "#F4F6FF",
			textMuted = "#B4BCE0",
			primary = "#3D5AFE",
			onPrimary = "#FFFFFF",
			secondary = "#2E3550",
			onSecondary = "#F4F6FF",
			danger = "#D32F2F",
			onDanger = "#FFFFFF",
			success = "#1A7F3B",
			onSuccess = "#FFFFFF",
			warning = "#FFC23D",
			onWarning = "#1A1300",
			info = "#1565C0",
			onInfo = "#FFFFFF",
			focus = "#FFD24D",
			overlay = "#000000",
		},
		transparency = { overlay = 0.45, surface = 0.05, ghost = 1 },
	},
	light = {
		name = "light",
		colors = {
			background = "#F5F7FB",
			surface = "#FFFFFF",
			surfaceAlt = "#EEF1F7",
			border = "#6B7593",
			text = "#12172B",
			textMuted = "#4A5375",
			primary = "#2F55D4",
			onPrimary = "#FFFFFF",
			secondary = "#E3E8F5",
			onSecondary = "#12172B",
			danger = "#C62828",
			onDanger = "#FFFFFF",
			success = "#1E7D34",
			onSuccess = "#FFFFFF",
			warning = "#F2B705",
			onWarning = "#1A1300",
			info = "#0B6FB8",
			onInfo = "#FFFFFF",
			focus = "#2F55D4",
			overlay = "#0B0E1A",
		},
		transparency = { overlay = 0.55, surface = 0, ghost = 1 },
	},
	highContrast = {
		name = "highContrast",
		colors = {
			background = "#000000",
			surface = "#000000",
			surfaceAlt = "#1A1A1A",
			border = "#FFFFFF",
			text = "#FFFFFF",
			textMuted = "#E6E6E6",
			primary = "#FFD60A",
			onPrimary = "#000000",
			secondary = "#FFFFFF",
			onSecondary = "#000000",
			danger = "#FF8A80",
			onDanger = "#000000",
			success = "#69F0AE",
			onSuccess = "#000000",
			warning = "#FFD60A",
			onWarning = "#000000",
			info = "#80D8FF",
			onInfo = "#000000",
			focus = "#FFD60A",
			overlay = "#000000",
		},
		transparency = { overlay = 0.2, surface = 0, ghost = 1 },
	},
} :: { [string]: ThemeDef }

-- The WCAG level each built-in theme promises. Custom themes default to "AA".
Tokens.levels = { dark = "AA", light = "AA", highContrast = "AAA" } :: { [string]: string }

return Tokens
