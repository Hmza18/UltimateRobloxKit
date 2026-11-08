--!strict
-- The wide "STARTER PACK" offer: patterned gradient banner, big icon on the left, outlined title,
-- subtitle, optional countdown, price tag on the right and a corner badge.
--   PromoBanner.new({ palette = "teal", icon = "star-color", title = "STARTER PACK",
--       subtitle = "A great offer you can't refuse!", timer = 3600,
--       price = { kind = "robux", amount = 29, productId = 123 }, parent = window.Content })
--
-- Activation works like ProductCard: `action` when set, otherwise the price's purchase intent.

local Badge = require("./Badge")
local Base = require("./Base")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")
local PricePill = require("./PricePill")
local Timer = require("./Timer")

export type BadgeSpec = { kind: string, text: string? }

export type Props = {
	palette: string?,
	title: string?,
	subtitle: string?,
	icon: string?,
	image: string?,
	price: Kit.Price?,
	badge: BadgeSpec?,
	timer: number?, -- seconds left on the offer
	owned: boolean?,
	robuxImage: string?,
	enabled: boolean?,
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

local PromoBanner = {}

local TEXT_LEFT = 0.25

local function label(object: any, parent: Instance, position: UDim2, size: UDim2, options: GameText.TextOptions)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = position
	text.Size = size
	text.ZIndex = 2
	GameText.decorate(text, object.style, options, object.parts)
	text.Parent = parent
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	if typeof(props.size) ~= "UDim2" then
		local height = style.sizes and style.sizes.banner and style.sizes.banner.height or 110
		root.Size = UDim2.new(1, 0, 0, height)
	end
	root.Active = props.enabled ~= false
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "teal",
		enabled = props.enabled,
		radius = "xl",
		outline = "thick",
		gloss = true,
		pattern = true,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Size = UDim2.fromScale(1.05, 1.05)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ZIndex = 2
	icon.Parent = content
	if not Kit.icon(icon, props.icon, props.image) then
		icon:Destroy()
	end

	local hasSubtitle = props.subtitle ~= nil and props.subtitle ~= ""
	local titleTop = if hasSubtitle or props.timer then 0.08 else 0.25
	local titleOptions: GameText.TextOptions = { text = props.title, role = "display", align = "left", maxSize = 40 }
	label(object, content, UDim2.fromScale(TEXT_LEFT, titleTop), UDim2.fromScale(0.47, 0.44), titleOptions)
	if hasSubtitle then
		local options: GameText.TextOptions = { text = props.subtitle, role = "label", align = "left" }
		label(object, content, UDim2.fromScale(TEXT_LEFT, 0.52), UDim2.fromScale(0.47, 0.2), options)
	end
	if props.timer then
		local timer = Timer.new({
			seconds = props.timer,
			icon = "clock",
			prefix = "Ends in ",
			style = props.style,
			position = UDim2.fromScale(TEXT_LEFT, 0.74),
			size = UDim2.fromScale(0.3, 0.2),
			parent = content,
		})
		object.parts:Add(timer)
	end

	local pillOptions: PricePill.Options = {
		price = props.price,
		owned = props.owned,
		size = UDim2.fromScale(0.23, 0.44),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		robuxImage = Kit.robuxImage(style, props),
	}
	PricePill.draw(object, content, pillOptions)

	Badge.attach(object, root, props.badge)
end

local function onActivated(object: any)
	local props = object.props
	if props.owned or props.price == nil then
		return
	end
	Kit.purchase(props.price, props.name, object.Instance)
end

function PromoBanner.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "PromoBanner",
		props = props,
		build = build,
		interactive = true,
		onActivated = onActivated,
	})
end

return PromoBanner
