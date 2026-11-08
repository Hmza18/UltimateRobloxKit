--!strict
-- Chunky gradient button with outline, gloss, optional shine sweep, icon and price.
--   CartoonButton.new({ kind = "buy", text = "BUY", parent = card })
--   CartoonButton.new({ kind = "robux", price = { kind = "robux", amount = 599, productId = 123 } })
--
-- Hover, press, release and gamepad selection use MotionPresets. Disabled buttons turn gray and
-- ignore input. On activation: `action` runs through UrkUI actions when set; otherwise a price
-- fires the purchase intent (Robux: "Purchase", currency: "Buy"). Activated fires either way.

local Base = require("./Base")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Style = require("../Style/Style")

export type Props = {
	kind: string?, -- buy, robux, gift, close, primary (default), danger, neutral, price
	palette: string?,
	text: string?,
	icon: string?,
	iconSide: string?, -- "left" (default) | "right"
	price: Kit.Price?,
	enabled: boolean?,
	shine: boolean?,
	robuxImage: string?,
	radius: string?, -- radius token, default "md"
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

local CartoonButton = {}

local DEFAULT_SIZE = UDim2.fromOffset(160, 56)

-- What a button shows: the icon (name or image) and the text, from kind, price and props.
function CartoonButton.content(style: Style.StyleDef, props: { [string]: any }): (string?, string?, string)
	local def = Style.button(style, props.kind)
	local price: Kit.Price? = props.price
	local icon: string? = props.icon
	local image: string? = nil
	if price and price.kind == "robux" then
		image = Kit.robuxImage(style, props)
		return nil, image, Kit.priceText(price, image == nil)
	end
	if price and price.kind == "currency" then
		icon = icon or price.currency or def.icon
		return icon, nil, Kit.priceText(price)
	end
	if price then
		return icon, nil, Kit.priceText(price)
	end
	if icon == nil and def.icon ~= "robux" then
		icon = def.icon
	end
	return icon, image, props.text or ""
end

-- Adds a looping shine sweep to a surface body (a white streak moved by the "shine" preset).
function CartoonButton.addShine(object: any, body: Frame, radius: number)
	local streak = Instance.new("Frame")
	streak.Name = "Shine"
	streak.BackgroundColor3 = Color3.new(1, 1, 1)
	streak.BorderSizePixel = 0
	streak.Size = UDim2.fromScale(1, 1)
	streak.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = streak
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = streak
	streak.Parent = body
	object.parts:Add(Motion.play(gradient, "shine"))
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	local def = Style.button(style, props.kind)
	local enabled = props.enabled ~= false
	root.Active = enabled
	local radius = Kit.radius(style, props.radius or "md")
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or def.palette,
		surface = if props.palette then nil else def.surface,
		enabled = enabled,
		radiusPixels = radius,
		outline = "thick",
		gloss = true,
		shadow = true,
	}
	local parts = Panel.surface(object, root, surfaceProps, "blue")
	local swatch = Kit.swatch(style, surfaceProps, "blue")
	if props.shine and enabled then
		CartoonButton.addShine(object, parts.body, radius)
	end

	local content = parts.content
	local gap = Kit.spacing(style, "sm")
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, gap + 2)
	padding.PaddingRight = UDim.new(0, gap + 2)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = content

	local icon, image, text = CartoonButton.content(style, props)
	local iconShown = false
	if icon or image then
		local holder = Instance.new("ImageLabel")
		holder.Name = "Icon"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(0.8, 0.8)
		holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
		holder.LayoutOrder = if props.iconSide == "right" then 3 else 1
		holder.ImageTransparency = if enabled then 0 else 0.35
		iconShown = Kit.icon(holder, icon, image)
		holder.Parent = content
		if not iconShown then
			holder:Destroy()
		end
	end
	if text ~= "" then
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.LayoutOrder = 2
		label.Size = if iconShown then UDim2.new(1, -gap, 1, 0) else UDim2.fromScale(1, 1)
		label.TextTransparency = if enabled then 0 else 0.25
		local role = if props.price then "price" else "label"
		local options: GameText.TextOptions = { text = text, role = role, color = swatch.text, maxSize = 28 }
		GameText.decorate(label, style, options, object.parts)
		label.Parent = content
		if iconShown then
			-- Leave room for the square icon: its width equals 80% of the content height.
			local function resize()
				local iconWidth = content.AbsoluteSize.Y * 0.8 / Kit.scaleFactor(content)
				label.Size = UDim2.new(1, -math.floor(iconWidth + gap), 1, 0)
			end
			object.parts:Connect(content:GetPropertyChangedSignal("AbsoluteSize"), resize)
			resize()
		end
	end
end

local function onActivated(object: any)
	local price = object.props.price
	if price then
		Kit.purchase(price, object.props.name, object.Instance)
	end
end

function CartoonButton.new(props: Props)
	return Base.new({
		className = "TextButton",
		name = "CartoonButton",
		props = props,
		size = DEFAULT_SIZE,
		build = build,
		interactive = true,
		onActivated = onActivated,
	})
end

return CartoonButton
