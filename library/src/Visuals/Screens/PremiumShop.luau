--!strict
-- PremiumShop screen: a featured banner, a grid of bundles and a premium call-to-action button.
-- Presses raise Purchased(id, price); Robux prices also reach the kit's PurchaseBridge through
-- the components' own Purchase intent. Nothing is granted here.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 64

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, kind = "wide", headerPalette = "gold" })
	local banner: any = nil
	local grid = ScreenKit.cards(window.content, "bundle", 2)
	shell.trove:Add(grid.destroy)
	local cta: any = nil

	local function buildBanner()
		if banner ~= nil then
			banner:destroy()
			banner = nil
		end
		local featured: any = shell.props.featured
		if type(featured) ~= "table" then
			return
		end
		banner = Game.PromoBanner.new({
			style = shell.styleName,
			parent = window.content,
			layoutOrder = 1,
			name = tostring(featured.id or "featured"),
			palette = featured.palette or "purple",
			title = featured.title,
			subtitle = featured.subtitle,
			icon = featured.icon,
			image = featured.image,
			price = featured.price,
			badge = featured.badge,
			timer = featured.timer,
			size = UDim2.new(1, -10, 0, 110),
		})
		banner.Activated:Connect(function()
			shell:fire("Purchased", featured.id or "featured", featured.price)
		end)
	end

	local function focusList(): { GuiObject }
		local objects = grid.instances()
		if banner ~= nil then
			table.insert(objects, 1, banner.Instance)
		end
		if cta ~= nil then
			table.insert(objects, cta.Instance)
		end
		return objects
	end

	local function buildBundles()
		grid.set(shell.props.bundles or {}, function(bundle: any, index: number, size: UDim2?): any
			local card = Game.ProductCard.new({
				style = shell.styleName,
				parent = grid.holder,
				layoutOrder = index,
				name = tostring(bundle.id),
				palette = bundle.palette or "blue",
				title = bundle.title,
				subtitle = bundle.subtitle,
				icon = bundle.icon,
				image = bundle.image,
				price = bundle.price,
				badge = bundle.badge,
				owned = bundle.owned,
				gift = bundle.gift,
				size = size,
			})
			card.Activated:Connect(function()
				if bundle.owned ~= true then
					shell:fire("Purchased", bundle.id, bundle.price)
				end
			end)
			return card
		end)
	end

	local function buildCta()
		if cta ~= nil then
			cta:destroy()
			cta = nil
		end
		local action: any = shell.props.cta
		if type(action) ~= "table" then
			window.footer.Visible = false
			return
		end
		local footer = window.setFooter(FOOTER)
		cta = Game.PremiumButton.new({
			style = shell.styleName,
			parent = footer,
			name = tostring(action.id or "premium"),
			text = action.text,
			icon = action.icon,
			palette = action.palette,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.new(0.7, 0, 0, FOOTER - 8),
		})
		cta.Activated:Connect(function()
			shell:fire("Confirmed", action.id or "premium")
		end)
	end

	shell.trove:Add(function()
		if banner ~= nil then
			banner:destroy()
		end
		if cta ~= nil then
			cta:destroy()
		end
	end)
	shell:onLayout(function(_env: ScreensLogic.Env)
		local body = window.body()
		grid.layout(ScreenKit.innerWidth(window.content, body.content.w), body.content.h)
	end)

	buildBanner()
	buildBundles()
	buildCta()
	shell:focusables(focusList())
	shell.onOpened = function()
		if banner ~= nil then
			UI.animate(banner.Instance, "SlideInDown")
		end
		grid.reveal("CardReveal")
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.featured ~= nil then
				buildBanner()
			end
			if partial.bundles ~= nil then
				buildBundles()
			end
			if partial.cta ~= nil then
				buildCta()
			end
			shell:relayout()
			shell:focusables(focusList())
		end,
	}
end
