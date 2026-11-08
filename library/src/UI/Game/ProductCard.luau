--!strict
-- Colour-coded shop card: gradient panel with checker pattern and gloss, big icon, outlined title,
-- optional "+50% Bonus" subtitle, price tag, corner badge, gift button and rarity outline.
--   ProductCard.new({ palette = "purple", icon = "egg-color", title = "TRIPLE HATCH",
--       price = { kind = "robux", amount = 29, gamePassId = 123 }, badge = { kind = "attention" } })
--
-- Activation: `action` when set; otherwise the price fires the purchase intent ("Purchase" with the
-- productId or gamePassId for Robux, "Buy" with itemId = props.name for currency). Owned cards fire
-- only Activated. The gift button fires the "Gift" intent with the same ids.

local Badge = require("./Badge")
local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")
local PricePill = require("./PricePill")
local RarityFrame = require("./RarityFrame")

export type BadgeSpec = { kind: string, text: string? }

export type Props = {
	palette: string?,
	title: string?,
	subtitle: string?,
	icon: string?,
	image: string?,
	price: Kit.Price?,
	badge: BadgeSpec?,
	gift: boolean?,
	rarity: string?,
	owned: boolean?,
	layout: string?, -- "tall" (default) | "wide"
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

local ProductCard = {}

local SUBTITLE_COLOR = "#FFE45C"

type Box = { position: UDim2, size: UDim2, anchor: Vector2 }
type Layout = { icon: Box, title: Box, subtitle: Box, price: Box, align: string }

local function box(position: UDim2, size: UDim2, anchor: Vector2): Box
	return { position = position, size = size, anchor = anchor }
end

local LAYOUTS: { [string]: Layout } = {
	tall = {
		icon = box(UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.46, 0.46), Vector2.new(0.5, 0)),
		title = box(UDim2.fromScale(0.5, 0.5), UDim2.new(1, -12, 0.17, 0), Vector2.new(0.5, 0)),
		subtitle = box(UDim2.fromScale(0.5, 0.66), UDim2.new(1, -12, 0.1, 0), Vector2.new(0.5, 0)),
		price = box(UDim2.new(0.5, 0, 1, -8), UDim2.fromScale(0.8, 0.2), Vector2.new(0.5, 1)),
		align = "center",
	},
	wide = {
		icon = box(UDim2.new(0, 10, 0.5, 0), UDim2.fromScale(0.8, 0.8), Vector2.new(0, 0.5)),
		title = box(UDim2.fromScale(0.3, 0.14), UDim2.fromScale(0.42, 0.36), Vector2.zero),
		subtitle = box(UDim2.fromScale(0.3, 0.52), UDim2.fromScale(0.42, 0.22), Vector2.zero),
		price = box(UDim2.new(1, -10, 0.5, 0), UDim2.fromScale(0.26, 0.42), Vector2.new(1, 0.5)),
		align = "left",
	},
}

local function place(instance: GuiObject, box: Box)
	instance.Position = box.position
	instance.Size = box.size
	instance.AnchorPoint = box.anchor
end

local function text(object: any, parent: Instance, box: Box, value: string, options: GameText.TextOptions)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.ZIndex = 2
	place(label, box)
	options.text = value
	GameText.decorate(label, object.style, options, object.parts)
	label.Parent = parent
	return label
end

local function giftButton(object: any, root: GuiObject)
	local props = object.props
	local gift = CartoonButton.new({
		kind = "gift",
		style = props.style,
		size = UDim2.fromOffset(36, 36),
		position = UDim2.fromOffset(-4, -4),
		parent = root,
	})
	gift.Instance.ZIndex = 6
	local price = props.price or {}
	gift.Activated:Connect(function()
		local args = { itemId = props.name, productId = price.productId, gamePassId = price.gamePassId }
		Kit.intent("Gift", args, gift.Instance)
	end)
	object.parts:Add(gift)
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local wide = props.layout == "wide"
	local layout = LAYOUTS[if wide then "wide" else "tall"]
	if typeof(props.size) ~= "UDim2" then
		local card = style.sizes and style.sizes.card or { width = 150, height = 150 }
		if wide then
			root.Size = UDim2.fromOffset(card.width * 2 + 20, 110)
		else
			root.Size = UDim2.fromOffset(card.width, card.height)
		end
	end
	root.Active = props.enabled ~= false
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette,
		enabled = props.enabled,
		radius = "lg",
		outline = if props.rarity then "heavy" else "thick",
		gloss = true,
		pattern = true,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps, "blue")
	if props.rarity and parts.stroke then
		object.parts:Add(RarityFrame.attach(parts.stroke, style, props.rarity))
	end
	local content = parts.content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ZIndex = 2
	place(icon, layout.icon)
	icon.Parent = content
	if not Kit.icon(icon, props.icon, props.image) then
		icon:Destroy()
	end

	local titleBox = layout.title
	if not props.subtitle and not wide then
		titleBox = box(UDim2.fromScale(0.5, 0.54), titleBox.size, titleBox.anchor)
	end
	if props.title then
		text(object, content, titleBox, props.title, { role = "heading", align = layout.align, maxSize = 24 })
	end
	if props.subtitle then
		local options: GameText.TextOptions = { role = "caption", align = layout.align, color = SUBTITLE_COLOR }
		text(object, content, layout.subtitle, props.subtitle, options)
	end
	local pillOptions: PricePill.Options = {
		price = props.price,
		owned = props.owned,
		size = layout.price.size,
		position = layout.price.position,
		anchor = layout.price.anchor,
		robuxImage = Kit.robuxImage(style, props),
	}
	PricePill.draw(object, content, pillOptions)

	Badge.attach(object, root, props.badge)
	if props.gift then
		giftButton(object, root)
	end
end

local function onActivated(object: any)
	local props = object.props
	if props.owned or props.price == nil then
		return
	end
	Kit.purchase(props.price, props.name, object.Instance)
end

function ProductCard.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "ProductCard",
		props = props,
		build = build,
		interactive = true,
		onActivated = onActivated,
	})
end

return ProductCard
