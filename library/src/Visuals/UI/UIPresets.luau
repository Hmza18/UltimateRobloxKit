--!strict
-- UI animation presets (pure data). Every preset is a recipe for Visuals/UI/UILogic, registered in
-- a Core/Registry of kind "ui". Recipes hold only numbers and names and are relative to the
-- object's rest state, so one preset fits any button, panel, card or label.
--
--   UIPresets.registry:get("BouncyPress").data   -- { steps = { ... } }
--   UIPresets.registry:register(myPreset, { override = true })
--
-- Timing follows the kit's hierarchy: press 60-90 ms, hover about 110 ms, release spring about
-- 230 ms, panels in 250-350 ms with overshoot, panels out 140-200 ms.

local Registry = require("../Core/Registry")
local UILogic = require("./UILogic")

type Props = UILogic.Props
type Step = UILogic.Step
type Recipe = UILogic.Recipe
type Layer = UILogic.Layer

local UIPresets = {}

local registry = Registry.new("ui")
UIPresets.registry = registry

-- Timed step.
local function to(props: Props, duration: number, easing: string?): Step
	return { props = props, duration = duration, easing = easing or "quadOut" }
end

-- Spring step.
local function spring(props: Props, name: string): Step
	return { props = props, spring = name }
end

-- A step that starts from explicit values.
local function from(start: Props, step: Step): Step
	step.from = start
	return step
end

-- A step that starts with the previous one.
local function join(step: Step): Step
	step.join = true
	return step
end

-- Fades are not motion, so they still play under reduced motion.
local function fade(value: number, duration: number, easing: string?): Step
	local step = to({ GroupFade = value }, duration, easing)
	step.essential = true
	return step
end

local function fadeIn(duration: number): Step
	return join(from({ GroupFade = 1 }, fade(0, duration)))
end

local function after(seconds: number, step: Step): Step
	step.delay = seconds
	return step
end

-- Layers are loosely typed data; this keeps mixed lists from being inferred as one exact shape.
local function overlays(list: { any }): { Layer }
	return list
end

local COSTS: { [string]: string } = {
	shine = "medium",
	border = "medium",
	ripple = "medium",
	glow = "low",
	tint = "low",
	textGlow = "low",
}

local function define(
	category: string,
	id: string,
	name: string,
	description: string,
	recipe: Recipe,
	tags: { string }?
)
	local cost = "low"
	local layers: { Layer } = recipe.layers or {}
	for _, layer in layers do
		if COSTS[layer.kind] == "medium" then
			cost = "medium"
		end
	end
	local allTags: { string } = { category }
	if recipe.loop then
		table.insert(allTags, "loop")
	end
	if recipe.out then
		table.insert(allTags, "exit")
	end
	local extra: { string } = tags or {}
	for _, tag in extra do
		table.insert(allTags, tag)
	end
	registry:register({
		id = id,
		name = name,
		category = category,
		description = description,
		params = {
			intensity = {
				type = "number",
				default = 1,
				min = 0,
				max = 2,
				description = "Scales travel, rotation and scale change",
			},
			speed = { type = "number", default = 1, min = 0.25, max = 4, description = "Playback speed multiplier" },
			delay = { type = "number", default = 0, min = 0, max = 10, description = "Seconds before it starts" },
		},
		quality = { min = "Low", cost = cost },
		preview = { loop = recipe.loop == true, duration = UILogic.duration(recipe) },
		usage = string.format('Visuals.UI.animate(gui, "%s")', id),
		tags = allTags,
		data = recipe,
	})
end

-- Buttons ---------------------------------------------------------------------------------------

define("buttons", "HoverScale", "Hover scale", "Grows a little when the pointer or gamepad selection lands on it.", {
	steps = { spring({ Scale = 1.06 }, "Snappy") },
}, { "hover", "state" })

define("buttons", "HoverReset", "Hover reset", "Returns scale, rotation and lift to rest when the pointer leaves.", {
	steps = { spring({ Scale = 1, Rotation = 0, OffsetY = 0 }, "Snappy") },
}, { "hover", "state" })

define("buttons", "PressDown", "Press down", "Quick squash on press; stays down until a release preset plays.", {
	steps = { to({ Scale = 0.92 }, 0.07, "quadOut") },
}, { "press", "state" })

define("buttons", "ReleaseSpring", "Release spring", "Springs back to rest with two visible bounces after a press.", {
	steps = { spring({ Scale = 1 }, "Bouncy") },
}, { "press" })

define("buttons", "BouncyPress", "Bouncy press", "Press and release in one: squash down, then bounce back to rest.", {
	steps = { to({ Scale = 0.92 }, 0.07, "quadOut"), spring({ Scale = 1 }, "Bouncy") },
}, { "press", "feedback" })

define("buttons", "Bounce", "Bounce", "Crouches, hops up and lands with a bounce to draw the eye once.", {
	steps = {
		to({ Scale = 0.94 }, 0.06, "quadOut"),
		to({ Scale = 1.07, OffsetY = -12 }, 0.12, "cubicOut"),
		spring({ Scale = 1, OffsetY = 0 }, "Bouncy"),
	},
}, { "attention" })

define("buttons", "Wiggle", "Wiggle", "Decaying left-right rotation, like a gift asking to be opened.", {
	steps = {
		to({ Rotation = -8 }, 0.06, "quadOut"),
		to({ Rotation = 7 }, 0.09, "sineInOut"),
		to({ Rotation = -5 }, 0.08, "sineInOut"),
		to({ Rotation = 3 }, 0.07, "sineInOut"),
		to({ Rotation = 0 }, 0.08, "quadOut"),
	},
}, { "attention" })

define("buttons", "Pulse", "Pulse", "Slow breathing scale loop for the one button the player should press next.", {
	steps = { to({ Scale = 1.06 }, 0.45, "sineInOut"), to({ Scale = 1 }, 0.45, "sineInOut") },
	loop = true,
}, { "attention" })

define("buttons", "Shine", "Shine", "A bright streak sweeps across the surface once.", {
	steps = {},
	layers = overlays({ { kind = "shine", duration = 0.6, angle = 20, width = 0.22, alpha = 0.45 } }),
	reduced = false,
}, { "premium" })

define("buttons", "Glow", "Glow", "Outline glow that breathes until stopped.", {
	steps = {},
	layers = overlays({ { kind = "glow", mode = "pulse", period = 1.2, thickness = 3, min = 0.2, max = 0.85 } }),
	loop = true,
}, { "premium", "attention" })

define("buttons", "Ripple", "Ripple", "A circle expands from the press point and fades inside the button.", {
	steps = {},
	layers = overlays({ { kind = "ripple", duration = 0.45, alpha = 0.72 } }),
	reduced = false,
}, { "press", "feedback" })

define("buttons", "Confirm", "Confirm", "Dips, overshoots and flashes a green outline: the action went through.", {
	steps = { to({ Scale = 0.94 }, 0.06, "quadOut"), spring({ Scale = 1 }, "Overshoot") },
	layers = overlays({ { kind = "glow", mode = "flash", duration = 0.45, thickness = 4, color = "#5BE37D" } }),
}, { "feedback" })

define("buttons", "Error", "Error", "Sharp horizontal shake with a red flash: the action was refused.", {
	steps = {
		to({ OffsetX = -10 }, 0.04, "quadOut"),
		to({ OffsetX = 9 }, 0.05, "sineInOut"),
		to({ OffsetX = -7 }, 0.05, "sineInOut"),
		to({ OffsetX = 5 }, 0.045, "sineInOut"),
		to({ OffsetX = -3 }, 0.04, "sineInOut"),
		to({ OffsetX = 0 }, 0.04, "quadOut"),
	},
	layers = overlays({
		{ kind = "tint", duration = 0.32, alpha = 0.5, color = "#FF3B4E" },
		{ kind = "glow", mode = "flash", duration = 0.4, thickness = 4, color = "#FF3B4E" },
	}),
}, { "feedback" })

define("buttons", "Loading", "Loading", "Dims and breathes while work is in flight; stop it when the work ends.", {
	steps = {
		to({ Scale = 0.97, GroupFade = 0.4 }, 0.5, "sineInOut"),
		to({ Scale = 1, GroupFade = 0.1 }, 0.5, "sineInOut"),
	},
	loop = true,
}, { "state" })

define("buttons", "Spinner", "Spinner", "Constant rotation for a loading icon.", {
	steps = { from({ Rotation = 0 }, to({ Rotation = 360 }, 0.9, "linear")) },
	loop = true,
}, { "state" })

define("buttons", "Selected", "Selected", "Pops up to a larger resting size and turns its outline glow on.", {
	steps = { spring({ Scale = 1.08 }, "Overshoot") },
	layers = overlays({ { kind = "glow", mode = "on", thickness = 3 } }),
}, { "state" })

define("buttons", "Deselected", "Deselected", "Returns to rest and turns the selection glow off.", {
	steps = { spring({ Scale = 1 }, "Snappy") },
	layers = overlays({ { kind = "glow", mode = "off" } }),
}, { "state" })

define("buttons", "Disabled", "Disabled", "Dims and shrinks slightly so it reads as unavailable.", {
	steps = { fade(0.5, 0.14), join(to({ Scale = 0.97 }, 0.14, "quadOut")) },
}, { "state" })

define("buttons", "Enabled", "Enabled", "Brightens and pops back to rest when it becomes available.", {
	steps = { fade(0, 0.14), join(to({ Scale = 1 }, 0.2, "backOut")) },
}, { "state" })

-- Panels ----------------------------------------------------------------------------------------

define(
	"panels",
	"PopIn",
	"Pop in",
	"Scales up past its size and settles while fading in; the default panel entrance.",
	{
		steps = { from({ Scale = 0.6 }, spring({ Scale = 1 }, "Overshoot")), fadeIn(0.12) },
		reduced = "FadeIn",
	},
	{ "enter" }
)

define("panels", "PopOut", "Pop out", "Shrinks with a small wind-up and fades; the default panel exit.", {
	steps = { to({ Scale = 0.8 }, 0.16, "backIn"), join(after(0.04, fade(1, 0.12, "quadIn"))) },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

local SLIDES: { { string } } = {
	{ "Left", "OffsetX", "-" },
	{ "Right", "OffsetX", "+" },
	{ "Up", "OffsetY", "+" },
	{ "Down", "OffsetY", "-" },
}
for _, slide in SLIDES do
	local side, axis, sign = slide[1], slide[2], slide[3]
	local distance = if sign == "-" then -48 else 48
	local origin = if axis == "OffsetX"
		then (if sign == "-" then "from the left" else "from the right")
		else (if sign == "-" then "from above, moving down" else "from below, moving up")
	define(
		"panels",
		"SlideIn" .. side,
		"Slide in " .. string.lower(side),
		"Slides in " .. origin .. " with a small overshoot while fading in.",
		{
			steps = { from({ [axis] = distance }, to({ [axis] = 0 }, 0.28, "backOut")), fadeIn(0.16) },
			reduced = "FadeIn",
		},
		{ "enter" }
	)
	-- SlideOutLeft leaves to the left, SlideOutUp leaves upward, and so on.
	local exit = if side == "Left" or side == "Up" then -48 else 48
	define(
		"panels",
		"SlideOut" .. side,
		"Slide out " .. string.lower(side),
		"Accelerates away to the " .. string.lower(side) .. " and fades out.",
		{
			steps = { to({ [axis] = exit }, 0.18, "quadIn"), join(fade(1, 0.18, "quadIn")) },
			out = true,
			reduced = "FadeOut",
		},
		{ "exit" }
	)
end

define("panels", "FadeIn", "Fade in", "Opacity only; also what motion-heavy entrances become under reduced motion.", {
	steps = { from({ GroupFade = 1 }, fade(0, 0.18)) },
}, { "enter" })

define("panels", "FadeOut", "Fade out", "Opacity only; also what motion-heavy exits become under reduced motion.", {
	steps = { fade(1, 0.14, "quadIn") },
	out = true,
}, { "exit" })

define("panels", "ScaleIn", "Scale in", "Grows from nothing with a slight overshoot.", {
	steps = { from({ Scale = 0 }, to({ Scale = 1 }, 0.24, "backOut")), fadeIn(0.1) },
	reduced = "FadeIn",
}, { "enter" })

define("panels", "ScaleOut", "Scale out", "Winds up and shrinks to nothing.", {
	steps = { to({ Scale = 0 }, 0.16, "backIn"), join(after(0.06, fade(1, 0.1, "quadIn"))) },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define("panels", "ElasticIn", "Elastic in", "Snaps open and rings like rubber; for playful, low-stakes panels.", {
	steps = { from({ Scale = 0.3 }, spring({ Scale = 1 }, "Elastic")), fadeIn(0.1) },
	reduced = "FadeIn",
}, { "enter" })

define("panels", "SpringIn", "Spring in", "Rises from below and bounces into place.", {
	steps = { from({ Scale = 0.85, OffsetY = 28 }, spring({ Scale = 1, OffsetY = 0 }, "Bouncy")), fadeIn(0.12) },
	reduced = "FadeIn",
}, { "enter" })

define("panels", "ModalIn", "Modal in", "Rises a little and scales up with a soft landing; pairs with BackdropIn.", {
	steps = { from({ Scale = 0.86, OffsetY = 18 }, spring({ Scale = 1, OffsetY = 0 }, "Premium")), fadeIn(0.14) },
	reduced = "FadeIn",
}, { "enter", "modal" })

define("panels", "ModalOut", "Modal out", "Sinks, shrinks slightly and fades; pairs with BackdropOut.", {
	steps = { to({ Scale = 0.94, OffsetY = 10 }, 0.16, "quadIn"), join(fade(1, 0.16, "quadIn")) },
	out = true,
	reduced = "FadeOut",
}, { "exit", "modal" })

define("panels", "DrawerIn", "Drawer in", "Slides up from below by its own height and decelerates.", {
	steps = { from({ OffsetYSize = 1 }, to({ OffsetYSize = 0 }, 0.3, "quintOut")) },
	reduced = "FadeIn",
}, { "enter" })

define("panels", "DrawerOut", "Drawer out", "Drops away by its own height.", {
	steps = { to({ OffsetYSize = 1 }, 0.2, "quadIn") },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define("panels", "BackdropIn", "Backdrop in", "Fades the dim layer behind a modal up to its resting opacity.", {
	steps = { from({ GroupFade = 1 }, fade(0, 0.2)) },
}, { "enter", "modal" })

define("panels", "BackdropOut", "Backdrop out", "Fades the dim layer behind a modal away.", {
	steps = { fade(1, 0.16, "quadIn") },
	out = true,
}, { "exit", "modal" })

-- Text ------------------------------------------------------------------------------------------

define("text", "TextBounce", "Text bounce", "Jumps larger and bounces back; for a value that just changed.", {
	steps = { to({ Scale = 1.25 }, 0.08, "quadOut"), spring({ Scale = 1 }, "Bouncy") },
}, { "feedback" })

define("text", "TextPulse", "Text pulse", "Gentle breathing scale loop for call-to-action text.", {
	steps = { to({ Scale = 1.08 }, 0.5, "sineInOut"), to({ Scale = 1 }, 0.5, "sineInOut") },
	loop = true,
}, { "attention" })

define("text", "TextGlow", "Text glow", "The text outline brightens and thickens in a slow loop.", {
	steps = {},
	layers = overlays({ { kind = "textGlow", mode = "pulse", period = 1.4, color = "#FFF2A8" } }),
	loop = true,
}, { "premium" })

define(
	"text",
	"RewardTextReveal",
	"Reward text reveal",
	"Slams in from oversized and tilted, squashes on impact and bounces out.",
	{
		steps = {
			from({ Scale = 1.9, Rotation = -8 }, to({ Scale = 0.9, Rotation = 0 }, 0.16, "cubicIn")),
			join(from({ GroupFade = 1 }, fade(0, 0.08))),
			spring({ Scale = 1 }, "Bouncy"),
		},
		reduced = "FadeIn",
	},
	{ "enter", "reward" }
)

define(
	"text",
	"LevelUpText",
	"Level up text",
	"Launches up oversized, hangs for a beat, then drops into place with a wobble.",
	{
		steps = {
			from({ Scale = 0.4, OffsetY = 30 }, to({ Scale = 1.3, OffsetY = -10 }, 0.22, "backOut")),
			join(from({ GroupFade = 1 }, fade(0, 0.1))),
			after(0.12, spring({ Scale = 1, OffsetY = 0 }, "Playful")),
		},
		reduced = "FadeIn",
	},
	{ "enter", "reward" }
)

-- Cards -----------------------------------------------------------------------------------------

define("cards", "HoverLift", "Hover lift", "Lifts a few pixels and grows slightly under the pointer.", {
	steps = { spring({ OffsetY = -6, Scale = 1.04 }, "Snappy") },
}, { "hover", "state" })

define("cards", "HoverDrop", "Hover drop", "Settles back down when the pointer leaves.", {
	steps = { spring({ OffsetY = 0, Scale = 1 }, "Snappy") },
}, { "hover", "state" })

define(
	"cards",
	"SelectGlow",
	"Select glow",
	"Turns the selection glow on with a small pop; the card stays slightly raised.",
	{
		steps = { spring({ Scale = 1.04 }, "Overshoot") },
		layers = overlays({ { kind = "glow", mode = "on", thickness = 4 } }),
	},
	{ "state" }
)

define("cards", "CardFlip", "Card flip", "Folds flat, fires the flip marker so the face can change, and unfolds.", {
	steps = {
		to({ Width = 0 }, 0.14, "quadIn"),
		{ props = { Width = 1 }, duration = 0.2, easing = "backOut", marker = "flip" },
	},
}, { "reveal" })

define("cards", "CardReveal", "Card reveal", "Tumbles up from below with a loose wobble and a shine once it lands.", {
	steps = {
		from(
			{ Scale = 0.5, Rotation = -10, OffsetY = 30 },
			spring({ Scale = 1, Rotation = 0, OffsetY = 0 }, "Playful")
		),
		fadeIn(0.14),
	},
	layers = overlays({ { kind = "shine", delay = 0.25, duration = 0.55, angle = 20, width = 0.22, alpha = 0.45 } }),
	reduced = "FadeIn",
}, { "enter", "reveal", "reward" })

define(
	"cards",
	"RarityBorder",
	"Rarity border",
	"A highlight travels around the outline in a loop; for high rarities.",
	{
		steps = {},
		layers = overlays({ { kind = "border", loop = true, period = 2.4 } }),
		loop = true,
	},
	{ "premium", "rarity" }
)

define(
	"cards",
	"UpgradePulse",
	"Upgrade pulse",
	"Swells, bounces back and flashes gold with a shine: the item got better.",
	{
		steps = { to({ Scale = 1.12 }, 0.1, "quadOut"), spring({ Scale = 1 }, "Bouncy") },
		layers = overlays({
			{ kind = "glow", mode = "flash", duration = 0.5, thickness = 5, color = "#FFD75A" },
			{ kind = "shine", delay = 0.08, duration = 0.5, angle = 20, width = 0.25, alpha = 0.4 },
		}),
	},
	{ "feedback", "reward" }
)

define(
	"cards",
	"InventorySelect",
	"Inventory select",
	"Quick dip, then pops to a raised resting size with the glow on.",
	{
		steps = { to({ Scale = 0.94 }, 0.05, "quadOut"), spring({ Scale = 1.05 }, "Overshoot") },
		layers = overlays({ { kind = "glow", mode = "on", thickness = 3 } }),
	},
	{ "state" }
)

define(
	"cards",
	"Highlight",
	"Highlight",
	"A white tint flashes over the surface and fades: something was just added here.",
	{
		steps = {},
		layers = overlays({ { kind = "tint", duration = 0.35, alpha = 0.55 } }),
	},
	{ "feedback" }
)

-- Navigation ------------------------------------------------------------------------------------

define(
	"navigation",
	"TabSwitch",
	"Tab switch",
	"New tab content slides in a short way and fades in; mirror it for the other direction.",
	{
		steps = { from({ OffsetX = 18 }, to({ OffsetX = 0 }, 0.2, "cubicOut")), fadeIn(0.14) },
		reduced = "FadeIn",
	},
	{ "enter" }
)

define(
	"navigation",
	"IndicatorSlide",
	"Indicator slide",
	"Springs the active indicator to options.position / options.size.",
	{
		steps = {},
		travel = { spring = "Snappy" },
	},
	{ "state" }
)

define(
	"navigation",
	"SidebarIn",
	"Sidebar in",
	"Slides in from the left edge by its own width; mirror it for a right sidebar.",
	{
		steps = { from({ OffsetXSize = -1 }, to({ OffsetXSize = 0 }, 0.28, "quintOut")) },
		reduced = "FadeIn",
	},
	{ "enter" }
)

define("navigation", "SidebarOut", "Sidebar out", "Slides out to the left edge by its own width.", {
	steps = { to({ OffsetXSize = -1 }, 0.2, "quadIn") },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define("navigation", "DropdownOpen", "Dropdown open", "Unrolls downward with a small overshoot while fading in.", {
	steps = { from({ Height = 0 }, to({ Height = 1 }, 0.18, "backOut")), fadeIn(0.1) },
	reduced = "FadeIn",
}, { "enter" })

define("navigation", "DropdownClose", "Dropdown close", "Rolls up and fades out.", {
	steps = { to({ Height = 0 }, 0.12, "quadIn"), join(fade(1, 0.12, "quadIn")) },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define(
	"navigation",
	"AccordionOpen",
	"Accordion open",
	"Grows to its full height, pushing siblings down, then fades its content in.",
	{
		steps = {
			from({ Height = 0 }, to({ Height = 1 }, 0.24, "cubicOut")),
			join(from({ GroupFade = 1 }, after(0.06, fade(0, 0.16)))),
		},
		reduced = "FadeIn",
	},
	{ "enter" }
)

define("navigation", "AccordionClose", "Accordion close", "Fades its content and collapses to zero height.", {
	steps = { fade(1, 0.1, "quadIn"), join(to({ Height = 0 }, 0.18, "cubicIn")) },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define("navigation", "PageNext", "Page next", "The next page comes in from the right by a third of its width.", {
	steps = { from({ OffsetXSize = 0.35 }, to({ OffsetXSize = 0 }, 0.26, "cubicOut")), fadeIn(0.16) },
	reduced = "FadeIn",
}, { "enter" })

define("navigation", "PagePrev", "Page previous", "The previous page comes in from the left by a third of its width.", {
	steps = { from({ OffsetXSize = -0.35 }, to({ OffsetXSize = 0 }, 0.26, "cubicOut")), fadeIn(0.16) },
	reduced = "FadeIn",
}, { "enter" })

define(
	"navigation",
	"ScrollReveal",
	"Scroll reveal",
	"Rises a short way, grows to size and fades in; made for staggered lists.",
	{
		steps = { from({ OffsetY = 24, Scale = 0.96 }, to({ OffsetY = 0, Scale = 1 }, 0.3, "cubicOut")), fadeIn(0.2) },
		reduced = "FadeIn",
	},
	{ "enter" }
)

-- Notifications ---------------------------------------------------------------------------------

define("notifications", "ToastIn", "Toast in", "Drops in from above with an overshoot while fading in.", {
	steps = { from({ OffsetY = -40, Scale = 0.9 }, spring({ OffsetY = 0, Scale = 1 }, "Overshoot")), fadeIn(0.12) },
	reduced = "FadeIn",
}, { "enter" })

define("notifications", "ToastOut", "Toast out", "Lifts away and fades.", {
	steps = { to({ OffsetY = -24, Scale = 0.96 }, 0.18, "quadIn"), join(fade(1, 0.18, "quadIn")) },
	out = true,
	reduced = "FadeOut",
}, { "exit" })

define("notifications", "BadgePop", "Badge pop", "A badge appears from nothing and bounces to size.", {
	steps = { from({ Scale = 0 }, spring({ Scale = 1 }, "Bouncy")) },
}, { "enter" })

define(
	"notifications",
	"AttentionPing",
	"Attention ping",
	"Jumps larger and rings back, then rests before the next ping.",
	{
		steps = { to({ Scale = 1.2 }, 0.12, "quadOut"), to({ Scale = 1 }, 0.4, "elasticOut") },
		loop = true,
		gap = 1.1,
	},
	{ "attention" }
)

-- Ids the kit and its components rely on. The spec checks that each one is registered.
UIPresets.REQUIRED = table.freeze({
	buttons = {
		"HoverScale",
		"PressDown",
		"ReleaseSpring",
		"BouncyPress",
		"Bounce",
		"Wiggle",
		"Pulse",
		"Shine",
		"Glow",
		"Ripple",
		"Confirm",
		"Error",
		"Loading",
		"Selected",
		"Deselected",
		"Disabled",
		"Enabled",
	},
	panels = {
		"PopIn",
		"PopOut",
		"SlideInLeft",
		"SlideInRight",
		"SlideInUp",
		"SlideInDown",
		"SlideOutLeft",
		"SlideOutRight",
		"SlideOutUp",
		"SlideOutDown",
		"FadeIn",
		"FadeOut",
		"ScaleIn",
		"ScaleOut",
		"ElasticIn",
		"SpringIn",
		"ModalIn",
		"ModalOut",
		"DrawerIn",
		"DrawerOut",
		"BackdropIn",
		"BackdropOut",
	},
	text = { "TextBounce", "TextPulse", "TextGlow", "RewardTextReveal", "LevelUpText" },
	cards = {
		"HoverLift",
		"HoverDrop",
		"SelectGlow",
		"CardFlip",
		"CardReveal",
		"RarityBorder",
		"UpgradePulse",
		"InventorySelect",
	},
	navigation = {
		"TabSwitch",
		"IndicatorSlide",
		"SidebarIn",
		"SidebarOut",
		"DropdownOpen",
		"DropdownClose",
		"AccordionOpen",
		"AccordionClose",
		"PageNext",
		"PagePrev",
		"ScrollReveal",
	},
	notifications = { "ToastIn", "ToastOut", "BadgePop", "AttentionPing" },
})

return UIPresets
