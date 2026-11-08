--!strict
-- The price tag drawn on cards and banners (not a button: the card is). Internal to UI/Game.
--   robux     green pill "R$ 599" (or the robuxImage plus "599")
--   currency  dark pill with the currency icon and an abbreviated amount
--   free      green pill "FREE"
--   owned     gray pill "OWNED"

local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")

export type Options = {
	price: Kit.Price?,
	owned: boolean?,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	robuxImage: string?,
	zIndex: number?,
}

local PricePill = {}

function PricePill.draw(object: any, parent: Instance, options: Options): Frame
	local style = object.style
	local price = options.price
	local holder = Instance.new("Frame")
	holder.Name = "Price"
	holder.BackgroundTransparency = 1
	holder.Size = options.size
	holder.Position = options.position
	holder.AnchorPoint = options.anchor
	holder.ZIndex = options.zIndex or 4
	local kind = if options.owned then "owned" elseif price then price.kind else "free"
	local surfaceProps: Panel.SurfaceProps = {
		palette = if kind == "owned" then "gray" else "green",
		surface = if kind == "currency" then "dark" else nil,
		radius = "pill",
		outline = "regular",
		gloss = kind ~= "currency",
		shadow = false,
	}
	local parts = Panel.surface(object, holder, surfaceProps)
	local content = parts.content

	local image = if kind == "robux" then options.robuxImage else nil
	local iconName = if kind == "currency" and price then price.currency else nil
	local text = if kind == "owned" then "OWNED" else Kit.priceText(price, image == nil)
	local hasIcon = false
	if image or iconName then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.16, 0.5)
		icon.Size = UDim2.fromScale(1.1, 1.1)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.ZIndex = 2
		hasIcon = Kit.icon(icon, iconName, image)
		icon.Parent = content
		if not hasIcon then
			icon:Destroy()
		end
	end
	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0.5)
	label.Position = UDim2.new(1, -6, 0.5, 0)
	label.Size = if hasIcon then UDim2.new(0.68, -6, 0.9, 0) else UDim2.new(1, -12, 0.9, 0)
	local textOptions: GameText.TextOptions = { text = text, role = "price", maxSize = 24 }
	GameText.decorate(label, style, textOptions, object.parts)
	label.Parent = content
	holder.Parent = parent
	object.parts:Add(holder)
	return holder
end

return PricePill
