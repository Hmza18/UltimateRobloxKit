--!strict
-- Premium call-to-action button: gradient surface with gloss, a shine that sweeps across every few
-- seconds, a breathing outline glow, and the "Premium" press feel (smooth spring, shine on hover).
--   PremiumButton.new({ text = "CLAIM REWARD", icon = "gift-color", palette = "gold", parent = panel })
--
-- Use it for the one action a screen is about. The shine and glow stop when the button is
-- disabled, under reduced motion, and on the Low quality profile (profile.uiShine).

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Style = require("../Style/Style")

export type Props = {
	text: string?,
	icon: string?,
	image: string?,
	palette: string?, -- default "gold"
	enabled: boolean?,
	shine: boolean?, -- looping shine sweep, default true
	glow: boolean?, -- breathing outline glow, default true
	shineInterval: number?, -- seconds between sweeps, default 2.6
	radius: string?, -- radius token, default "lg"
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	action: string?,
	[string]: any,
}

local PremiumButton = {}

local DEFAULT_SIZE = UDim2.fromOffset(220, 64)

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local enabled = props.enabled ~= false
	root.Active = enabled
	local radius = Kit.radius(style, props.radius or "lg")
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "gold",
		enabled = enabled,
		radiusPixels = radius,
		outline = "heavy",
		gloss = true,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps)
	local swatch = Kit.swatch(style, surfaceProps)
	local content = parts.content
	local gap = Kit.spacing(style, "sm")
	local icon = Extra.image(content, "Icon", props.icon, props.image, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, gap + 4, 0.5, -1),
		size = UDim2.fromScale(0.62, 0.62),
	})
	local inset = gap + 4
	if icon then
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.ImageTransparency = if enabled then 0 else 0.35
		inset = math.floor(root.Size.Y.Offset * 0.62) + gap * 2 + 4
	end
	local label = Extra.label(object, content, "Label", {
		text = props.text or "",
		role = "heading",
		color = swatch.text,
		maxSize = 30,
	}, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, inset, 0.5, -1),
		size = UDim2.new(1, -(inset + gap + 4), 0.8, 0),
	})
	label.TextTransparency = if enabled then 0 else 0.25

	if enabled and props.shine ~= false then
		Extra.own(object, Extra.UI.shine(root, { loop = true, interval = props.shineInterval or 2.6, delay = 0.6 }))
	end
	if enabled and props.glow ~= false then
		local color = Style.lighten(Style.palette(style, props.palette or "gold").top, 0.35)
		Extra.own(object, Extra.UI.animate(root, "Glow", { color = color }))
	end
end

function PremiumButton.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "PremiumButton",
		props = props,
		size = DEFAULT_SIZE,
		build = build,
		setup = function(self: any)
			Extra.wire(self, { style = "Premium", radius = Kit.radius(self.style, self.props.radius or "lg") })
		end,
	})
end

return PremiumButton
