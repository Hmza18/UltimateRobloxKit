--!strict
-- Shop item card: icon, name, description, price and a buy button whose state follows
-- owned / affordable. Pressing buy calls onBuy, which should send a purchase request to the
-- server; the card never grants anything. Call card:setState after the server answers.

local Button = require("./Button")
local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local Format = require("../Core/Format")
local IconBridge = require("../Runtime/IconBridge")
local Motion = require("../Runtime/Motion")

export type State = { owned: boolean?, affordable: boolean?, price: number? }

export type Props = {
	name: string,
	price: number,
	icon: string?,
	currencyIcon: string?,
	description: string?,
	owned: boolean?,
	affordable: boolean?,
	buyText: string?,
	ownedText: string?,
	onBuy: () -> (),
	parent: Instance?,
	layoutOrder: number?,
}

local ShopCard = {}

function ShopCard.new(props: Props)
	local context = Context.get()
	local theme = context.theme
	local card = Create.new("Frame", {
		Name = props.name,
		Size = UDim2.fromOffset(180, 240),
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Tags = { "UrkTheme" },
		Attributes = { Role = "surface", StrokeRole = "border", Radius = "lg" },
	})
	Create.stroke(theme:color("border"), 1).Parent = card
	Create.padding(12).Parent = card
	Create.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = card
	local icon = Create.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(84, 84),
		LayoutOrder = 1,
		Parent = card,
	})
	IconBridge.apply(icon, props.icon)
	Create.new("TextLabel", {
		Name = "ItemName",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Text = props.name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Tags = { "UrkTheme" },
		Attributes = { TextRole = "text", TextSize = "label" },
		Parent = card,
	})
	if props.description then
		Create.new("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			Text = props.description,
			TextWrapped = true,
			LayoutOrder = 3,
			Tags = { "UrkTheme" },
			Attributes = { TextRole = "textMuted", TextSize = "caption" },
			Parent = card,
		})
	end
	local priceRow = Create.new("Frame", {
		Name = "Price",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 4,
		Parent = card,
	})
	local priceLayout = Create.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center)
	priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	priceLayout.Parent = priceRow
	if props.currencyIcon then
		local currency = Create.new("ImageLabel", {
			Name = "CurrencyIcon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(20, 20),
			Parent = priceRow,
		})
		IconBridge.apply(currency, props.currencyIcon)
	end
	local priceLabel = Create.new("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = 2,
		Tags = { "UrkTheme" },
		Attributes = { TextRole = "text", TextSize = "label" },
		Parent = priceRow,
	})

	local state: State = { owned = props.owned, affordable = props.affordable ~= false, price = props.price }
	local buy = Button.new({
		text = props.buyText or "Buy",
		variant = "primary",
		size = "md",
		width = 140,
		layoutOrder = 5,
		parent = card,
		onClick = function()
			if state.owned then
				return
			end
			if not state.affordable then
				Motion.shake(card, 6, 0.3)
				return
			end
			props.onBuy()
		end,
	})

	local handle = {}
	handle.Instance = card

	function handle.setState(_self: any, newState: State)
		local mutable: any = state
		for key, value in newState do
			mutable[key] = value
		end
		priceLabel.Text = Format.abbrev(state.price or props.price)
		if state.owned then
			buy:setText(props.ownedText or "Owned")
			buy:setEnabled(false)
		else
			buy:setText(props.buyText or "Buy")
			buy:setEnabled(state.affordable ~= false)
		end
	end

	function handle.Destroy(_self: any)
		card:Destroy()
	end

	handle:setState(state)
	if props.parent then
		card.Parent = props.parent
	end
	return handle
end

return ShopCard
