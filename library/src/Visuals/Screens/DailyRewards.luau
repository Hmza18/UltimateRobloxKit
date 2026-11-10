--!strict
-- DailyRewards screen: a reward track (seven days by default). Days before today show as
-- claimed, today pulses and can be claimed, later days are locked. The claim button raises
-- Claimed(day); after the server confirms, call screen:update({ claimed = true }).
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 64

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.dailyRewards(props)
	local window = shell:window({ title = props.title, headerPalette = "orange" })
	local streak = shell:text(window.content, "", "label", ScreenKit.ink(shell.style, "window", "center"))
	streak:update({ layoutOrder = 1 })
	local grid = ScreenKit.cards(window.content, "day", 2)
	shell.trove:Add(grid.destroy)
	local footer = window.setFooter(FOOTER)
	local claim = shell:button(footer, {
		premium = true,
		name = "Claim",
		text = props.claimText,
		icon = "gift-color",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(0.7, 0, 0, FOOTER - 8),
	})
	local pulse: any = nil

	local function stopPulse()
		if pulse ~= nil then
			pulse.stop(true)
			pulse = nil
		end
	end
	shell.trove:Add(stopPulse)

	-- One day: a palette panel with "DAY n", the reward icon and text, and a tick or a padlock.
	local function dayCard(day: ScreensLogic.DayView, index: number, size: UDim2?): any
		local reward: any = if type(day.reward) == "table" then day.reward else { text = tostring(day.reward) }
		local palette = reward.palette
			or (if day.state == "today" then "green" elseif reward.premium then "gold" else "blue")
		local panel = Game.Panel.new({
			style = shell.styleName,
			parent = grid.holder,
			layoutOrder = index,
			name = "Day" .. tostring(day.day),
			palette = if day.state == "locked" then "gray" else palette,
			pattern = reward.premium == true,
			gloss = true,
			size = size,
		})
		local inner: Instance = panel.Content or panel.Instance
		local parts: { any } = {}
		table.insert(
			parts,
			Game.GameText.new({
				style = shell.styleName,
				parent = inner,
				text = "DAY " .. tostring(day.day),
				role = "label",
				size = UDim2.fromScale(1, 0.24),
			})
		)
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.5, 0.42)
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = inner
		ScreenKit.icon(image, reward.icon or (if reward.image == nil then "gift-color" else nil), reward.image)
		table.insert(
			parts,
			Game.GameText.new({
				style = shell.styleName,
				parent = inner,
				text = tostring(reward.text or reward.amount or ""),
				role = "caption",
				size = UDim2.fromScale(1, 0.22),
				position = UDim2.fromScale(0, 0.76),
			})
		)
		local mark = Instance.new("ImageLabel")
		mark.Name = "Mark"
		mark.BackgroundTransparency = 1
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, 4, 0, -4)
		mark.Size = UDim2.fromOffset(26, 26)
		mark.ZIndex = 5
		mark.Visible = day.state ~= "today"
		mark.Parent = panel.Instance
		ScreenKit.icon(mark, if day.state == "claimed" then "success-color" else "lock-color", nil)
		local destroy = panel.destroy
		-- The grid resizes and destroys cards through the panel; the texts go with it.
		panel.destroy = function(self: any)
			for _, part in ipairs(parts) do
				part:destroy()
			end
			destroy(self)
		end
		panel.mark = mark
		return panel
	end

	local function build()
		stopPulse()
		view = ScreensLogic.dailyRewards(shell.props)
		grid.set(view.days, dayCard)
		streak:update({ text = string.format("Day %d streak", view.streak) })
		claim:update({
			enabled = view.canClaim,
			text = if view.canClaim then shell.props.claimText else "COME BACK TOMORROW",
		})
		local today = grid.cards[tostring(view.today)]
		if today ~= nil and view.canClaim and shell:isOpen() then
			pulse = UI.animate(today.Instance, "Pulse")
		end
		shell:relayout()
		shell:focusables({ claim.Instance })
	end

	shell.trove:Add(claim.Activated:Connect(function()
		if view.canClaim then
			shell:fire("Claimed", view.today)
		end
	end))
	shell:onLayout(function(_env: ScreensLogic.Env)
		local body = window.body()
		grid.layout(ScreenKit.innerWidth(window.content, body.content.w), body.content.h)
	end)
	build()
	shell.onOpened = function()
		grid.reveal("CardReveal")
		local today = grid.cards[tostring(view.today)]
		if today ~= nil and view.canClaim and pulse == nil then
			pulse = UI.animate(today.Instance, "Pulse", { delay = 0.5 })
		end
	end
	shell.onClosed = stopPulse

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			local wasToday = view.today
			local couldClaim = view.canClaim
			build()
			-- The claim just went through: the day's tick pops in.
			if couldClaim and not view.canClaim and view.today == wasToday then
				local card = grid.cards[tostring(wasToday)]
				if card ~= nil then
					UI.animate(card.Instance, "Confirm")
					UI.animate(card.mark, "BadgePop")
				end
			end
		end,
	}
end
