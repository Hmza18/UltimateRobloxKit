--!strict
-- The ten visual themes (pure data). A theme names a style in design/tokens/styles.json (read here
-- through the generated StyleTokens module) and adds what a style does not carry: colour roles,
-- type roles and weights, layout scales, motion feel and effect presets.
--
-- Values a style already owns (surface, text and border colours, rarity colours, font families,
-- text sizes, text stroke, spacing, radius, shadow) are read from the style, so a theme can never
-- drift from the components it skins. Everything else is written per theme below.
--
-- Use Themes.luau at runtime and ThemeLogic.luau for validation, contrast and lookup.

local StyleTokens = require("../../UI/Style/StyleTokens")

export type Stroke = { color: string, thickness: number, transparency: number }
export type Shadow = { color: string, offsetX: number, offsetY: number, transparency: number, spread: number }
export type Glow = { color: string, size: number, transparency: number }
export type GradientStop = { at: number, color: string }
export type Gradient = { rotation: number, stops: { GradientStop } }
export type Highlight = { fill: string, outline: string, fillTransparency: number, outlineTransparency: number }
export type Shine = { color: string, angle: number, width: number, speed: number, transparency: number }
export type BreakpointLayout = { columns: number, gutter: number, hudScale: number, density: number }

export type Colors = {
	primary: string,
	secondary: string,
	accent: string,
	success: string,
	warning: string,
	error: string,
	background: string,
	surface: string,
	text: string,
	textMuted: string,
	border: string,
	glow: string,
}

export type Typography = {
	fonts: { [string]: string }, -- role -> family (Enum.Font name, also valid for Font.fromName)
	fallback: string,
	weights: { [string]: string }, -- role -> Enum.FontWeight name
	sizes: { [string]: number }, -- role -> pixels at 1x
	stroke: { [string]: Stroke }, -- title, body, number
	shadow: { [string]: Shadow }, -- soft, hard
	scale: { [string]: number }, -- UI/Core/Breakpoints name -> text scale factor
	numbers: { style: string, decimals: number, separator: string, suffixCase: string, tabular: boolean },
}

export type Layout = {
	spacing: { [string]: number },
	radius: { [string]: number },
	padding: { [string]: number }, -- screen, panel, card, button, chip
	margin: { [string]: number }, -- screen, section, item
	safeArea: { policy: string, hud: string, modal: string, backdrop: string, minInset: number },
	breakpoints: { [string]: BreakpointLayout },
	layers: { [string]: number },
}

export type Motion = {
	duration: { [string]: number }, -- instant, fast, normal, slow, cinematic (seconds)
	easing: string, -- a Core/Curves name
	spring: { [string]: string }, -- role -> Core/Springs name
	intensity: number, -- multiplier for travel, scale and shake amounts
	scale: { hover: number, press: number, pop: number },
	transition: { [string]: string }, -- role -> pop | slide | fade | scale | rise | wipe | blink | none
	stagger: number, -- seconds between list items
	reduced: { spring: string, easing: string, durationScale: number, transition: { [string]: string } },
}

export type Effects = {
	shadow: { [string]: Shadow }, -- sm, md, lg
	glow: { [string]: Glow }, -- soft, strong, reward
	gradient: { [string]: Gradient }, -- primary, accent, surface, reward
	outline: { [string]: Stroke }, -- thin, regular, bold
	highlight: { [string]: Highlight }, -- select, hover, reward
	shine: { [string]: Shine }, -- subtle, sweep, reward
	particles: { string }, -- 3 to 5 colours VFX may tint with
	sparkle: string, -- default VFX texture key
}

export type Theme = {
	id: string,
	style: string,
	name: string,
	description: string,
	colors: Colors,
	rarity: { [string]: string },
	typography: Typography,
	layout: Layout,
	motion: Motion,
	effects: Effects,
}

-- What each theme writes by hand; `build` completes it from the style.
type Spec = {
	style: string,
	name: string,
	description: string,
	colors: { [string]: string },
	weights: { [string]: string },
	labelFont: string?,
	textScale: { [string]: number },
	numbers: { style: string, decimals: number, separator: string, suffixCase: string, tabular: boolean },
	textShadow: { offsetX: number, offsetY: number, soft: number, hard: number },
	padding: { [string]: number },
	margin: { [string]: number },
	minInset: number,
	columns: { [string]: number },
	density: { [string]: number },
	motion: Motion,
	glow: { size: number, transparency: number },
	gradientRotation: number,
	highlight: { fill: number, outline: number },
	shine: { angle: number, width: number, speed: number, transparency: number },
	particles: { string },
	sparkle: string,
}

local ThemeData = {}

ThemeData.IDS = table.freeze({
	"VibrantSimulator",
	"PremiumCartoon",
	"Fantasy",
	"Anime",
	"SciFi",
	"Cozy",
	"ModernMinimal",
	"Arcade",
	"Luxury",
	"Adventure",
})

ThemeData.DEFAULT = "VibrantSimulator"

ThemeData.RARITIES = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" })
ThemeData.COLOR_ROLES = table.freeze({
	"primary",
	"secondary",
	"accent",
	"success",
	"warning",
	"error",
	"background",
	"surface",
	"text",
	"textMuted",
	"border",
	"glow",
})
ThemeData.TEXT_ROLES = table.freeze({ "display", "title", "heading", "body", "label", "caption", "number" })
ThemeData.DURATIONS = table.freeze({ "instant", "fast", "normal", "slow", "cinematic" })
ThemeData.SPRING_ROLES = table.freeze({ "press", "hover", "panel", "popup", "card", "reward", "camera" })
ThemeData.TRANSITION_ROLES = table.freeze({ "panel", "popup", "toast", "card", "reward", "screen" })
ThemeData.TRANSITIONS = table.freeze({ "pop", "slide", "fade", "scale", "rise", "wipe", "blink", "none" })
ThemeData.BREAKPOINTS = table.freeze({ "phone", "tablet", "desktop", "console" }) -- UI/Core/Breakpoints.NAMES
ThemeData.LAYER_NAMES = table.freeze({ "hud", "panel", "modal", "toast", "reveal", "debug" })

-- DisplayOrder bands for ScreenGuis (and ZIndex bands inside one). They sit around UrkUI's own
-- bands (hud 0, panel 10, modal 50, toast 80): reward reveals cover toasts, debug covers everything.
local LAYERS: { [string]: number } = { hud = 0, panel = 10, modal = 50, toast = 80, reveal = 120, debug = 1000 }

-- With reduced motion every transition becomes a short fade and springs stop overshooting.
local function reduced(
	durationScale: number
): { spring: string, easing: string, durationScale: number, transition: { [string]: string } }
	return {
		spring = "Gentle",
		easing = "quadOut",
		durationScale = durationScale,
		transition = {
			panel = "fade",
			popup = "fade",
			toast = "fade",
			card = "fade",
			reward = "fade",
			screen = "fade",
		},
	}
end

local function channels(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	assert(r and g and b, "colour must be #RRGGBB: " .. tostring(hex))
	return tonumber(r, 16) :: number, tonumber(g, 16) :: number, tonumber(b, 16) :: number
end

-- Linear blend of two hex colours; k = 0 returns a, k = 1 returns b.
local function mix(a: string, b: string, k: number): string
	local ar, ag, ab = channels(a)
	local br, bg, bb = channels(b)
	local function lerp(x: number, y: number): number
		return math.clamp(math.floor(x + (y - x) * k + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", lerp(ar, br), lerp(ag, bg), lerp(ab, bb))
end

local function build(id: string, spec: Spec): Theme
	local style = StyleTokens[spec.style]
	assert(style ~= nil, "theme " .. id .. " names an unknown style: " .. spec.style)
	local window = style.surfaces.window
	local stroke = style.textStroke
	local shadow = style.shadow

	local colors: Colors = {
		primary = spec.colors.primary,
		secondary = spec.colors.secondary,
		accent = spec.colors.accent,
		success = spec.colors.success,
		warning = spec.colors.warning,
		error = spec.colors.error,
		background = spec.colors.background,
		surface = window.top,
		text = window.text,
		textMuted = spec.colors.textMuted,
		border = style.outline.color,
		glow = spec.colors.glow,
	}

	local rarity: { [string]: string } = {}
	for _, name in ThemeData.RARITIES do
		rarity[name] = style.rarity[string.lower(name)].color
	end

	local fonts = style.fonts
	local sizes = style.text
	local typography: Typography = {
		fonts = {
			display = fonts.title,
			title = fonts.title,
			heading = fonts.title,
			body = fonts.body,
			label = spec.labelFont or fonts.body,
			caption = fonts.body,
			number = fonts.number,
		},
		fallback = fonts.fallback,
		weights = spec.weights,
		sizes = {
			display = sizes.display,
			title = sizes.title,
			heading = sizes.heading,
			body = math.max(sizes.minimum, sizes.label - 2),
			label = sizes.label,
			caption = sizes.caption,
			number = sizes.price,
		},
		stroke = {
			title = { color = stroke.color, thickness = stroke.thickness, transparency = 0 },
			body = { color = stroke.color, thickness = stroke.smallThickness, transparency = 0 },
			number = { color = stroke.color, thickness = stroke.thickness, transparency = 0 },
		},
		shadow = {
			soft = {
				color = shadow.color,
				offsetX = 0,
				offsetY = math.max(1, spec.textShadow.offsetY - 1),
				transparency = spec.textShadow.soft,
				spread = 0,
			},
			hard = {
				color = shadow.color,
				offsetX = spec.textShadow.offsetX,
				offsetY = spec.textShadow.offsetY,
				transparency = spec.textShadow.hard,
				spread = 0,
			},
		},
		scale = spec.textScale,
		numbers = spec.numbers,
	}

	local spacing = table.clone(style.spacing)
	local breakpoints: { [string]: BreakpointLayout } = {}
	for _, name in ThemeData.BREAKPOINTS do
		breakpoints[name] = {
			columns = spec.columns[name],
			gutter = if name == "phone" then spacing.sm else spacing.md,
			hudScale = spec.textScale[name],
			density = spec.density[name],
		}
	end
	local layout: Layout = {
		spacing = spacing,
		radius = table.clone(style.radius),
		padding = spec.padding,
		margin = spec.margin,
		-- HUD and modals stay inside the device safe area; full-screen backdrops bleed under it.
		safeArea = { policy = "inset", hud = "inset", modal = "inset", backdrop = "bleed", minInset = spec.minInset },
		breakpoints = breakpoints,
		layers = table.clone(LAYERS),
	}

	local outline = style.outline
	local offset = shadow.offsetY
	local glow = spec.glow
	local effects: Effects = {
		shadow = {
			sm = {
				color = shadow.color,
				offsetX = 0,
				offsetY = math.max(1, math.floor(offset / 2 + 0.5)),
				transparency = math.min(0.95, shadow.transparency + 0.12),
				spread = 0,
			},
			md = { color = shadow.color, offsetX = 0, offsetY = offset, transparency = shadow.transparency, spread = 1 },
			lg = {
				color = shadow.color,
				offsetX = 0,
				offsetY = offset * 2 + 2,
				transparency = math.min(0.95, shadow.transparency + 0.06),
				spread = 3,
			},
		},
		glow = {
			soft = { color = colors.glow, size = glow.size, transparency = math.min(0.95, glow.transparency + 0.2) },
			strong = { color = colors.glow, size = glow.size * 2, transparency = glow.transparency },
			reward = {
				color = mix(colors.glow, "#FFFFFF", 0.35),
				size = glow.size * 3,
				transparency = math.max(0, glow.transparency - 0.1),
			},
		},
		gradient = {
			primary = {
				rotation = spec.gradientRotation,
				stops = {
					{ at = 0, color = mix(colors.primary, "#FFFFFF", 0.22) },
					{ at = 1, color = mix(colors.primary, "#000000", 0.12) },
				},
			},
			accent = {
				rotation = spec.gradientRotation,
				stops = {
					{ at = 0, color = mix(colors.accent, "#FFFFFF", 0.22) },
					{ at = 1, color = mix(colors.accent, "#000000", 0.12) },
				},
			},
			surface = {
				rotation = 90,
				stops = { { at = 0, color = window.top }, { at = 1, color = window.bottom } },
			},
			reward = {
				rotation = spec.gradientRotation,
				stops = {
					{ at = 0, color = mix(colors.glow, "#FFFFFF", 0.5) },
					{ at = 0.5, color = colors.accent },
					{ at = 1, color = colors.primary },
				},
			},
		},
		outline = {
			thin = { color = outline.color, thickness = outline.thin, transparency = 0 },
			regular = { color = outline.color, thickness = outline.regular, transparency = 0 },
			bold = { color = outline.color, thickness = outline.heavy, transparency = 0 },
		},
		highlight = {
			select = {
				fill = colors.accent,
				outline = colors.accent,
				fillTransparency = spec.highlight.fill,
				outlineTransparency = spec.highlight.outline,
			},
			hover = {
				fill = colors.glow,
				outline = colors.glow,
				fillTransparency = math.min(1, spec.highlight.fill + 0.1),
				outlineTransparency = math.min(1, spec.highlight.outline + 0.3),
			},
			reward = {
				fill = colors.glow,
				outline = mix(colors.glow, "#FFFFFF", 0.5),
				fillTransparency = math.max(0, spec.highlight.fill - 0.15),
				outlineTransparency = 0,
			},
		},
		shine = {
			subtle = {
				color = "#FFFFFF",
				angle = spec.shine.angle,
				width = spec.shine.width * 0.6,
				speed = spec.shine.speed * 0.6,
				transparency = math.min(0.95, spec.shine.transparency + 0.2),
			},
			sweep = {
				color = "#FFFFFF",
				angle = spec.shine.angle,
				width = spec.shine.width,
				speed = spec.shine.speed,
				transparency = spec.shine.transparency,
			},
			reward = {
				color = mix(colors.glow, "#FFFFFF", 0.6),
				angle = spec.shine.angle,
				width = spec.shine.width * 1.5,
				speed = spec.shine.speed * 1.25,
				transparency = math.max(0, spec.shine.transparency - 0.15),
			},
		},
		particles = spec.particles,
		sparkle = spec.sparkle,
	}

	return {
		id = id,
		style = spec.style,
		name = spec.name,
		description = spec.description,
		colors = colors,
		rarity = rarity,
		typography = typography,
		layout = layout,
		motion = spec.motion,
		effects = effects,
	}
end

local SPECS: { [string]: Spec } = {
	-- Loud, bouncy and saturated: everything pops and overshoots.
	VibrantSimulator = {
		style = "vibrant",
		name = "Vibrant Simulator",
		description = "Saturated candy colours, very chunky outlines and bouncy pops. For tap-heavy simulators.",
		colors = {
			primary = "#0A81FA",
			secondary = "#8A2BFF",
			accent = "#F21DA0",
			success = "#16961F",
			warning = "#D16400",
			error = "#FC1F4A",
			background = "#CFE8FF",
			textMuted = "#4A4580",
			glow = "#FFE866",
		},
		weights = {
			display = "Heavy",
			title = "ExtraBold",
			heading = "Bold",
			body = "Bold",
			label = "Bold",
			caption = "SemiBold",
			number = "Heavy",
		},
		textScale = { phone = 0.9, tablet = 1, desktop = 1, console = 1.2 },
		numbers = { style = "abbreviated", decimals = 1, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 0, offsetY = 3, soft = 0.6, hard = 0.25 },
		padding = { screen = 16, panel = 18, card = 12, button = 14, chip = 8 },
		margin = { screen = 12, section = 26, item = 12 },
		minInset = 8,
		columns = { phone = 3, tablet = 4, desktop = 5, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.15 },
		motion = {
			duration = { instant = 0, fast = 0.09, normal = 0.16, slow = 0.3, cinematic = 0.9 },
			easing = "backOut",
			spring = {
				press = "Bouncy",
				hover = "Snappy",
				panel = "Soft",
				popup = "Bouncy",
				card = "Playful",
				reward = "Bouncy",
				camera = "Soft",
			},
			intensity = 1.15,
			scale = { hover = 1.08, press = 0.9, pop = 1.16 },
			transition = {
				panel = "pop",
				popup = "pop",
				toast = "slide",
				card = "pop",
				reward = "pop",
				screen = "slide",
			},
			stagger = 0.04,
			reduced = reduced(0.5),
		},
		glow = { size = 24, transparency = 0.35 },
		gradientRotation = 90,
		highlight = { fill = 0.7, outline = 0 },
		shine = { angle = 25, width = 0.28, speed = 1.6, transparency = 0.45 },
		particles = { "#FFE866", "#FF6BD6", "#4DC3FF", "#8CFF4D", "#FFFFFF" },
		sparkle = "star",
	},

	-- Polished storefront: clean overshoot on entrances, soft landings elsewhere.
	PremiumCartoon = {
		style = "premium",
		name = "Premium Cartoon",
		description = "Warm cream panels, navy outlines and rich gradients with soft, polished motion.",
		colors = {
			primary = "#3B7DDB",
			secondary = "#7C5BD9",
			accent = "#AC7E1A",
			success = "#299950",
			warning = "#CC6C24",
			error = "#D93A4A",
			background = "#F3E9D6",
			textMuted = "#5A6280",
			glow = "#FFDE85",
		},
		weights = {
			display = "ExtraBold",
			title = "Bold",
			heading = "Bold",
			body = "SemiBold",
			label = "Bold",
			caption = "Medium",
			number = "Bold",
		},
		textScale = { phone = 0.9, tablet = 1, desktop = 1, console = 1.15 },
		numbers = { style = "abbreviated", decimals = 2, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 0, offsetY = 2, soft = 0.7, hard = 0.45 },
		padding = { screen = 18, panel = 18, card = 14, button = 14, chip = 8 },
		margin = { screen = 14, section = 24, item = 14 },
		minInset = 10,
		columns = { phone = 3, tablet = 4, desktop = 5, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.1 },
		motion = {
			duration = { instant = 0, fast = 0.11, normal = 0.2, slow = 0.34, cinematic = 1 },
			easing = "cubicOut",
			spring = {
				press = "Snappy",
				hover = "Soft",
				panel = "Premium",
				popup = "Overshoot",
				card = "Soft",
				reward = "Bouncy",
				camera = "Gentle",
			},
			intensity = 1,
			scale = { hover = 1.05, press = 0.94, pop = 1.1 },
			transition = {
				panel = "scale",
				popup = "pop",
				toast = "slide",
				card = "rise",
				reward = "pop",
				screen = "fade",
			},
			stagger = 0.05,
			reduced = reduced(0.5),
		},
		glow = { size = 20, transparency = 0.45 },
		gradientRotation = 90,
		highlight = { fill = 0.78, outline = 0 },
		shine = { angle = 20, width = 0.22, speed = 1.1, transparency = 0.55 },
		particles = { "#FFDE85", "#FF8FC4", "#6CB6FF", "#FFFFFF" },
		sparkle = "spark",
	},

	-- Weighty and ceremonial: slow settles, rising reveals, long cinematic beats.
	Fantasy = {
		style = "fantasy",
		name = "Fantasy",
		description = "Parchment, dark oak and jewel tones with weighty, ceremonial motion and warm glows.",
		colors = {
			primary = "#7D50C1",
			secondary = "#3F6FBF",
			accent = "#93701F",
			success = "#458432",
			warning = "#AD641C",
			error = "#BB3A34",
			background = "#E5D0A3",
			textMuted = "#6B4A30",
			glow = "#F2D377",
		},
		weights = {
			display = "Bold",
			title = "Bold",
			heading = "SemiBold",
			body = "Regular",
			label = "Medium",
			caption = "Regular",
			number = "Bold",
		},
		textScale = { phone = 0.92, tablet = 1, desktop = 1, console = 1.15 },
		numbers = { style = "grouped", decimals = 0, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 1, offsetY = 2, soft = 0.65, hard = 0.4 },
		padding = { screen = 16, panel = 18, card = 12, button = 12, chip = 8 },
		margin = { screen = 12, section = 24, item = 12 },
		minInset = 8,
		columns = { phone = 3, tablet = 4, desktop = 5, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.1 },
		motion = {
			duration = { instant = 0, fast = 0.12, normal = 0.22, slow = 0.4, cinematic = 1.4 },
			easing = "cubicInOut",
			spring = {
				press = "Soft",
				hover = "Gentle",
				panel = "Heavy",
				popup = "Soft",
				card = "Soft",
				reward = "Premium",
				camera = "Cinematic",
			},
			intensity = 0.9,
			scale = { hover = 1.04, press = 0.95, pop = 1.08 },
			transition = {
				panel = "rise",
				popup = "scale",
				toast = "fade",
				card = "rise",
				reward = "rise",
				screen = "fade",
			},
			stagger = 0.07,
			reduced = reduced(0.5),
		},
		glow = { size = 28, transparency = 0.4 },
		gradientRotation = 90,
		highlight = { fill = 0.75, outline = 0.1 },
		shine = { angle = 35, width = 0.18, speed = 0.8, transparency = 0.6 },
		particles = { "#F2D377", "#A77BE0", "#5FC2B0", "#FFF3D1" },
		sparkle = "glow",
	},

	-- Fast and sharp: everything overshoots hard and snaps into place.
	Anime = {
		style = "anime",
		name = "Anime",
		description = "Ink outlines on white, hot pink and cyan, hard shadows and very fast overshooting motion.",
		colors = {
			primary = "#FF1493",
			secondary = "#0099A9",
			accent = "#1466FF",
			success = "#00A243",
			warning = "#E86000",
			error = "#F0143C",
			background = "#F0F2FA",
			textMuted = "#4A4D63",
			glow = "#4DF0F0",
		},
		weights = {
			display = "Heavy",
			title = "ExtraBold",
			heading = "Bold",
			body = "Bold",
			label = "ExtraBold",
			caption = "SemiBold",
			number = "Heavy",
		},
		textScale = { phone = 0.9, tablet = 1, desktop = 1, console = 1.2 },
		numbers = { style = "abbreviated", decimals = 1, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 3, offsetY = 3, soft = 0.5, hard = 0 },
		padding = { screen = 14, panel = 16, card = 10, button = 12, chip = 6 },
		margin = { screen = 10, section = 24, item = 10 },
		minInset = 8,
		columns = { phone = 3, tablet = 4, desktop = 6, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.15 },
		motion = {
			duration = { instant = 0, fast = 0.07, normal = 0.13, slow = 0.24, cinematic = 0.75 },
			easing = "expoOut",
			spring = {
				press = "Overshoot",
				hover = "Snappy",
				panel = "Overshoot",
				popup = "Overshoot",
				card = "Snappy",
				reward = "Elastic",
				camera = "Snappy",
			},
			intensity = 1.3,
			scale = { hover = 1.07, press = 0.9, pop = 1.2 },
			transition = {
				panel = "slide",
				popup = "pop",
				toast = "slide",
				card = "slide",
				reward = "wipe",
				screen = "wipe",
			},
			stagger = 0.03,
			reduced = reduced(0.5),
		},
		glow = { size = 18, transparency = 0.3 },
		gradientRotation = 60,
		highlight = { fill = 0.65, outline = 0 },
		shine = { angle = 45, width = 0.14, speed = 2.4, transparency = 0.35 },
		particles = { "#FF5CB8", "#4DF0F0", "#FFF066", "#FFFFFF" },
		sparkle = "flare",
	},

	-- Precise and technical: tight snaps, wipes and scans, restrained scale.
	SciFi = {
		style = "scifi",
		name = "Sci-Fi",
		description = "Navy glass with glowing cyan edges; tight, precise snaps and scan-line wipes.",
		colors = {
			primary = "#00B8D4",
			secondary = "#7851E4",
			accent = "#3DFFA2",
			success = "#00C26E",
			warning = "#E6B800",
			error = "#FF4D6A",
			background = "#0B1524",
			textMuted = "#8FB4CC",
			glow = "#5CE1FF",
		},
		weights = {
			display = "Bold",
			title = "Bold",
			heading = "SemiBold",
			body = "Regular",
			label = "SemiBold",
			caption = "Regular",
			number = "Bold",
		},
		textScale = { phone = 0.92, tablet = 1, desktop = 1, console = 1.15 },
		numbers = { style = "grouped", decimals = 0, separator = " ", suffixCase = "upper", tabular = true },
		textShadow = { offsetX = 0, offsetY = 1, soft = 0.7, hard = 0.5 },
		padding = { screen = 16, panel = 16, card = 12, button = 12, chip = 8 },
		margin = { screen = 12, section = 20, item = 12 },
		minInset = 8,
		columns = { phone = 3, tablet = 5, desktop = 6, console = 6 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.1 },
		motion = {
			duration = { instant = 0, fast = 0.08, normal = 0.16, slow = 0.3, cinematic = 0.9 },
			easing = "quartOut",
			spring = {
				press = "Snappy",
				hover = "Snappy",
				panel = "Snappy",
				popup = "Snappy",
				card = "Gentle",
				reward = "Overshoot",
				camera = "Gentle",
			},
			intensity = 0.85,
			scale = { hover = 1.03, press = 0.96, pop = 1.05 },
			transition = {
				panel = "wipe",
				popup = "scale",
				toast = "slide",
				card = "fade",
				reward = "wipe",
				screen = "wipe",
			},
			stagger = 0.025,
			reduced = reduced(0.5),
		},
		glow = { size = 22, transparency = 0.25 },
		gradientRotation = 0,
		highlight = { fill = 0.85, outline = 0 },
		shine = { angle = 0, width = 0.08, speed = 2, transparency = 0.4 },
		particles = { "#5CE1FF", "#3DFFA2", "#9B6BFF", "#E6F7FF" },
		sparkle = "ring",
	},

	-- Slow and soft: nothing snaps, nothing shakes, small amounts everywhere.
	Cozy = {
		style = "cozy",
		name = "Cozy",
		description = "Cream paper, cocoa outlines and garden colours with slow, soft motion and little overshoot.",
		colors = {
			primary = "#709058",
			secondary = "#B37A46",
			accent = "#C76D57",
			success = "#5E8C4A",
			warning = "#9C8445",
			error = "#B8503F",
			background = "#F7E9D2",
			textMuted = "#7A6250",
			glow = "#F9E3A0",
		},
		weights = {
			display = "Bold",
			title = "Bold",
			heading = "SemiBold",
			body = "SemiBold",
			label = "SemiBold",
			caption = "Medium",
			number = "Bold",
		},
		textScale = { phone = 0.95, tablet = 1, desktop = 1, console = 1.2 },
		numbers = { style = "grouped", decimals = 0, separator = ",", suffixCase = "lower", tabular = false },
		textShadow = { offsetX = 0, offsetY = 2, soft = 0.8, hard = 0.6 },
		padding = { screen = 20, panel = 20, card = 14, button = 14, chip = 10 },
		margin = { screen = 14, section = 28, item = 14 },
		minInset = 12,
		columns = { phone = 2, tablet = 4, desktop = 5, console = 4 },
		density = { phone = 0.95, tablet = 1, desktop = 1, console = 1.15 },
		motion = {
			duration = { instant = 0, fast = 0.14, normal = 0.26, slow = 0.44, cinematic = 1.3 },
			easing = "sineOut",
			spring = {
				press = "Soft",
				hover = "Gentle",
				panel = "Gentle",
				popup = "Soft",
				card = "Gentle",
				reward = "Soft",
				camera = "Gentle",
			},
			intensity = 0.7,
			scale = { hover = 1.04, press = 0.95, pop = 1.06 },
			transition = {
				panel = "rise",
				popup = "scale",
				toast = "rise",
				card = "fade",
				reward = "scale",
				screen = "fade",
			},
			stagger = 0.08,
			reduced = reduced(0.6),
		},
		glow = { size = 26, transparency = 0.55 },
		gradientRotation = 90,
		highlight = { fill = 0.82, outline = 0.2 },
		shine = { angle = 15, width = 0.3, speed = 0.6, transparency = 0.7 },
		particles = { "#F9E3A0", "#F5B8CC", "#BBD8A0", "#FFF9EE" },
		sparkle = "heart",
	},

	-- Quiet: fades instead of pops, tiny scale amounts, no decoration.
	ModernMinimal = {
		style = "minimal",
		name = "Modern Minimal",
		description = "Flat white, hairline borders and one accent; quick fades and barely-there scale changes.",
		colors = {
			primary = "#2563EB",
			secondary = "#111827",
			accent = "#7C3AED",
			success = "#218358",
			warning = "#D2460F",
			error = "#D83A40",
			background = "#FAFBFC",
			textMuted = "#5B6472",
			glow = "#3472D8",
		},
		weights = {
			display = "Bold",
			title = "SemiBold",
			heading = "SemiBold",
			body = "Regular",
			label = "Medium",
			caption = "Regular",
			number = "Medium",
		},
		textScale = { phone = 0.95, tablet = 1, desktop = 1, console = 1.15 },
		numbers = { style = "grouped", decimals = 0, separator = ",", suffixCase = "upper", tabular = true },
		textShadow = { offsetX = 0, offsetY = 1, soft = 0.9, hard = 0.8 },
		padding = { screen = 20, panel = 20, card = 16, button = 12, chip = 8 },
		margin = { screen = 16, section = 32, item = 12 },
		minInset = 12,
		columns = { phone = 2, tablet = 4, desktop = 6, console = 5 },
		density = { phone = 0.95, tablet = 1, desktop = 1, console = 1.1 },
		motion = {
			duration = { instant = 0, fast = 0.08, normal = 0.15, slow = 0.25, cinematic = 0.7 },
			easing = "cubicOut",
			spring = {
				press = "Snappy",
				hover = "Snappy",
				panel = "Snappy",
				popup = "Snappy",
				card = "Snappy",
				reward = "Soft",
				camera = "Gentle",
			},
			intensity = 0.5,
			scale = { hover = 1.02, press = 0.98, pop = 1.02 },
			transition = {
				panel = "fade",
				popup = "fade",
				toast = "fade",
				card = "fade",
				reward = "scale",
				screen = "fade",
			},
			stagger = 0.02,
			reduced = reduced(0.5),
		},
		glow = { size = 10, transparency = 0.7 },
		gradientRotation = 90,
		highlight = { fill = 0.9, outline = 0 },
		shine = { angle = 20, width = 0.12, speed = 1, transparency = 0.8 },
		particles = { "#3472D8", "#8558EC", "#9CA3AF" },
		sparkle = "circle",
	},

	-- Twitchy: the shortest durations in the kit, elastic pops, blinking toasts.
	Arcade = {
		style = "arcade",
		name = "Arcade",
		description = "Cabinet-black panels, pixel type and neon blocks with very short, snappy and elastic motion.",
		colors = {
			primary = "#F200A6",
			secondary = "#00D9C4",
			accent = "#FFF21A",
			success = "#39FF14",
			warning = "#FF8C1A",
			error = "#FF3355",
			background = "#170D3A",
			textMuted = "#B5ABE0",
			glow = "#1AFFE8",
		},
		weights = {
			display = "Regular",
			title = "Regular",
			heading = "Regular",
			body = "Medium",
			label = "Bold",
			caption = "Regular",
			number = "Regular",
		},
		textScale = { phone = 0.9, tablet = 1, desktop = 1, console = 1.2 },
		numbers = { style = "padded", decimals = 0, separator = "", suffixCase = "upper", tabular = true },
		textShadow = { offsetX = 3, offsetY = 3, soft = 0.4, hard = 0 },
		padding = { screen = 16, panel = 16, card = 12, button = 12, chip = 8 },
		margin = { screen = 12, section = 24, item = 12 },
		minInset = 8,
		columns = { phone = 3, tablet = 4, desktop = 5, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.15 },
		motion = {
			duration = { instant = 0, fast = 0.05, normal = 0.1, slow = 0.18, cinematic = 0.6 },
			easing = "backOut",
			spring = {
				press = "Snappy",
				hover = "Snappy",
				panel = "Snappy",
				popup = "Elastic",
				card = "Snappy",
				reward = "Elastic",
				camera = "Snappy",
			},
			intensity = 1.4,
			scale = { hover = 1.1, press = 0.86, pop = 1.22 },
			transition = {
				panel = "pop",
				popup = "pop",
				toast = "blink",
				card = "pop",
				reward = "blink",
				screen = "wipe",
			},
			stagger = 0.02,
			reduced = reduced(0.5),
		},
		glow = { size = 16, transparency = 0.2 },
		gradientRotation = 90,
		highlight = { fill = 0.6, outline = 0 },
		shine = { angle = 0, width = 0.1, speed = 3, transparency = 0.3 },
		particles = { "#FF1ACC", "#1AFFE8", "#FFF21A", "#39FF14", "#FFFFFF" },
		sparkle = "confetti",
	},

	-- Unhurried: the longest durations, no bounce, low intensity, cinematic reveals.
	Luxury = {
		style = "luxury",
		name = "Luxury",
		description = "Black lacquer and fine gold rules; slow, smooth, low-intensity motion with cinematic reveals.",
		colors = {
			primary = "#C9A24B",
			secondary = "#795AA0",
			accent = "#F0D58A",
			success = "#2F9E6E",
			warning = "#D4B24C",
			error = "#C93452",
			background = "#12100E",
			textMuted = "#B5A88C",
			glow = "#F0D58A",
		},
		weights = {
			display = "Regular",
			title = "Regular",
			heading = "Medium",
			body = "Regular",
			label = "SemiBold",
			caption = "Regular",
			number = "Regular",
		},
		textScale = { phone = 0.92, tablet = 1, desktop = 1, console = 1.15 },
		numbers = { style = "grouped", decimals = 0, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 0, offsetY = 2, soft = 0.6, hard = 0.4 },
		padding = { screen = 24, panel = 26, card = 18, button = 16, chip = 10 },
		margin = { screen = 18, section = 40, item = 18 },
		minInset = 14,
		columns = { phone = 2, tablet = 3, desktop = 4, console = 4 },
		density = { phone = 0.92, tablet = 1, desktop = 1, console = 1.1 },
		motion = {
			duration = { instant = 0, fast = 0.16, normal = 0.3, slow = 0.55, cinematic = 1.8 },
			easing = "quintOut",
			spring = {
				press = "Premium",
				hover = "Premium",
				panel = "Premium",
				popup = "Premium",
				card = "Premium",
				reward = "Cinematic",
				camera = "Cinematic",
			},
			intensity = 0.6,
			scale = { hover = 1.025, press = 0.97, pop = 1.03 },
			transition = {
				panel = "fade",
				popup = "scale",
				toast = "fade",
				card = "fade",
				reward = "rise",
				screen = "fade",
			},
			stagger = 0.09,
			reduced = reduced(0.6),
		},
		glow = { size = 30, transparency = 0.5 },
		gradientRotation = 100,
		highlight = { fill = 0.88, outline = 0 },
		shine = { angle = 30, width = 0.1, speed = 0.5, transparency = 0.6 },
		particles = { "#F0D58A", "#C9A24B", "#F6EBD2" },
		sparkle = "glow",
	},

	-- Sturdy: heavy panels that slide in like gear, bouncy rewards, a weighty camera.
	Adventure = {
		style = "adventure",
		name = "Adventure",
		description = "Forest canvas and leather with sunset accents; sturdy slides, heavy panels and bouncy rewards.",
		colors = {
			primary = "#E97C25",
			secondary = "#579FDB",
			accent = "#FFD95C",
			success = "#8FD94A",
			warning = "#F0B41F",
			error = "#F2735E",
			background = "#1A372D",
			textMuted = "#C5CDB0",
			glow = "#FFD470",
		},
		weights = {
			display = "Bold",
			title = "Bold",
			heading = "SemiBold",
			body = "Medium",
			label = "Bold",
			caption = "Regular",
			number = "Bold",
		},
		textScale = { phone = 0.9, tablet = 1, desktop = 1, console = 1.2 },
		numbers = { style = "abbreviated", decimals = 1, separator = ",", suffixCase = "upper", tabular = false },
		textShadow = { offsetX = 0, offsetY = 2, soft = 0.55, hard = 0.3 },
		padding = { screen = 16, panel = 16, card = 12, button = 12, chip = 8 },
		margin = { screen = 12, section = 24, item = 12 },
		minInset = 8,
		columns = { phone = 3, tablet = 4, desktop = 5, console = 5 },
		density = { phone = 0.9, tablet = 1, desktop = 1, console = 1.15 },
		motion = {
			duration = { instant = 0, fast = 0.1, normal = 0.2, slow = 0.36, cinematic = 1.1 },
			easing = "cubicOut",
			spring = {
				press = "Snappy",
				hover = "Soft",
				panel = "Heavy",
				popup = "Overshoot",
				card = "Soft",
				reward = "Bouncy",
				camera = "Heavy",
			},
			intensity = 1,
			scale = { hover = 1.05, press = 0.93, pop = 1.1 },
			transition = {
				panel = "slide",
				popup = "pop",
				toast = "slide",
				card = "rise",
				reward = "pop",
				screen = "slide",
			},
			stagger = 0.05,
			reduced = reduced(0.5),
		},
		glow = { size = 22, transparency = 0.4 },
		gradientRotation = 90,
		highlight = { fill = 0.72, outline = 0 },
		shine = { angle = 25, width = 0.2, speed = 1.2, transparency = 0.5 },
		particles = { "#FFD470", "#8FD94A", "#58B4F0", "#FF9D3D" },
		sparkle = "leaf",
	},
}

local themes: { [string]: Theme } = {}
for _, id in ThemeData.IDS do
	themes[id] = build(id, SPECS[id])
end

-- Built-in themes by id. Treat them as read-only: derive a copy with ThemeLogic.derive instead.
ThemeData.themes = themes

-- Style key (styles.json) -> theme id, for games that already picked a style.
local byStyle: { [string]: string } = {}
for _, id in ThemeData.IDS do
	byStyle[themes[id].style] = id
end
ThemeData.byStyle = byStyle

return ThemeData
