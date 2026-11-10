--!strict
-- AreaUnlock screen: a banner for a new area with its cost and an unlock button. The button
-- raises Confirmed; the server checks the cost and unlocks. The game then calls
-- screen:celebrate({ position = gate.Position }), which plays the UnlockArea feedback (with the
-- NewArea effect) and closes the banner.
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local HEIGHT = 136

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local root = shell.root
	local banner = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = root,
		name = "Banner",
		palette = props.palette,
		pattern = true,
		gloss = true,
		padding = "sm",
		anchor = Vector2.new(0.5, 0),
	}))
	shell.animated = banner.Instance
	local inner: Instance = banner.Content or banner.Instance
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.new(0, HEIGHT - 40, 1, 0)
	icon.Parent = inner
	local textLeft = HEIGHT - 32
	local title = shell:text(inner, "", "title", {
		align = "left",
		position = UDim2.fromOffset(textLeft, 0),
		size = UDim2.new(1, -textLeft - 52, 0, 40),
	})
	local description = shell:text(inner, "", "caption", {
		align = "left",
		position = UDim2.fromOffset(textLeft, 40),
		size = UDim2.new(1, -textLeft, 0, 22),
	})
	local unlock = shell:button(inner, {
		name = "Unlock",
		kind = "buy",
		text = props.unlockText,
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, textLeft, 1, 0),
		size = UDim2.new(1, -textLeft, 0, 48),
	})
	local close = shell:button(banner.Instance, {
		name = "Close",
		kind = "close",
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -4, 0, 4),
		size = UDim2.fromOffset(ScreensLogic.MIN_TOUCH, ScreensLogic.MIN_TOUCH),
	})
	close.Instance.ZIndex = 6
	local unlocked = false
	local cancelClose: (() -> ())? = nil

	local function refresh()
		local current: { [string]: any } = shell.props
		local area: any = current.area
		ScreenKit.icon(icon, area.icon or (if area.image == nil then "map-color" else nil), area.image)
		title:update({ text = string.upper(tostring(area.name or "New area")) })
		description:update({ text = tostring(area.description or "") })
		local affordable = current.balance == nil
			or ScreensLogic.affordable(current.cost, current.balance, current.currency)
		local text = if unlocked
			then "UNLOCKED!"
			elseif current.cost > 0 then string.format(
				"%s  %s",
				current.unlockText,
				ScreenKit.amount(current.cost)
			)
			else current.unlockText
		unlock:update({
			text = text,
			enabled = affordable and not unlocked,
			icon = if unlocked then nil else current.currencyIcon,
		})
	end

	shell.trove:Add(unlock.Activated:Connect(function()
		if not unlocked then
			shell:fire("Confirmed")
		end
	end))
	shell.trove:Add(close.Activated:Connect(function()
		shell:close()
	end))
	shell.trove:Add(function()
		if cancelClose then
			cancelClose()
		end
	end)

	shell:onLayout(function(env: ScreensLogic.Env)
		local width = math.floor(math.min(env.safe.w - env.margin * 2, 560))
		banner.Instance.Size = UDim2.fromOffset(width, HEIGHT)
		banner.Instance.Position = UDim2.new(0.5, 0, 0, env.margin)
	end)
	refresh()
	shell:focusables({ unlock.Instance, close.Instance })

	return {
		update = function(_partial: { [string]: any })
			refresh()
		end,
		methods = {
			-- Call once the server unlocked the area. `context` goes to the UnlockArea feedback
			-- ({ position = ... } plays the NewArea effect there). The banner closes after a moment.
			celebrate = function(context: { [string]: any }?)
				unlocked = true
				refresh()
				UI.animate(banner.Instance, "Confirm")
				local ok, Feedback = pcall(function(): any
					return require("../Feedback/Feedback")
				end)
				if ok and type(Feedback) == "table" then
					Feedback.fire("UnlockArea", context or {})
				end
				if cancelClose == nil then
					cancelClose = Host.clock:after(1.4, function()
						cancelClose = nil
						shell:close()
					end)
				end
			end,
		},
	}
end
