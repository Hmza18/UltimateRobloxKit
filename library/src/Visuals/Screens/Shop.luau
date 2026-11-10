--!strict
-- Shop screen: tabs and a grid of ProductCards. Pressing a card raises Purchased(id, price):
-- a request, not a sale. Robux prices also go through the kit's PurchaseBridge (the ProductCard
-- raises the Purchase intent itself); currency prices are for the server to check and charge.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.shop(props)
	local grid: ScreenKit.CardGrid
	local window: ScreenKit.Window

	local function build(animate: boolean)
		view = ScreensLogic.shop(shell.props)
		grid.set(view.products, function(product: any, index: number, size: UDim2?): any
			local card = Game.ProductCard.new({
				style = shell.styleName,
				parent = grid.holder,
				layoutOrder = index,
				name = tostring(product.id),
				palette = product.palette,
				title = product.title,
				subtitle = product.subtitle,
				icon = product.icon,
				image = product.image,
				price = product.price,
				badge = product.badge,
				rarity = product.rarity,
				owned = product.owned,
				size = size,
			})
			card.Activated:Connect(function()
				if product.owned == true then
					shell:fire("Selected", product.id)
				else
					shell:fire("Purchased", product.id, product.price)
				end
			end)
			return card
		end)
		shell:relayout()
		shell:focusables(grid.instances())
		if animate and shell:isOpen() then
			grid.reveal("CardReveal")
		end
	end

	window = shell:window({
		title = props.title,
		kind = "wide",
		headerPalette = "red",
		tabs = view.tabs,
		tab = view.tab,
		onTab = function(id: string)
			shell.props.tab = id
			build(true)
			shell:fire("TabChanged", id)
		end,
	})
	grid = ScreenKit.cards(window.content, "product", 1)
	shell.trove:Add(grid.destroy)
	shell:onLayout(function(_env: ScreensLogic.Env)
		local body = window.body()
		grid.layout(ScreenKit.innerWidth(window.content, body.content.w), body.content.h)
	end)
	build(false)
	shell.onOpened = function()
		grid.reveal("CardReveal")
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.tab ~= nil then
				window.setTab(ScreensLogic.shop(shell.props).tab or partial.tab)
			end
			if partial.products ~= nil or partial.tab ~= nil then
				build(false)
			end
		end,
	}
end
