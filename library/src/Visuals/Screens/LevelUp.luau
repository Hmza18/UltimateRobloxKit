--!strict
-- LevelUp screen: an overlay for a level the server just granted. The title launches in
-- (LevelUpText), the XP bar fills across the level boundary, and the rewards (already granted)
-- pop in with a claim button that closes the overlay. Without rewards it closes by itself.
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

return function(shell: ScreenKit.Shell, props: { [string]: any })
	shell.backdrop = true
	local root = shell.root
	local column = shell:frame(root, "Column")
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromScale(0.5, 0.5)
	local layout = ScreenKit.list(column, false, 10, "center")
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local title = shell:text(column, props.title, "display", { layoutOrder = 1 })
	local levelText = shell:text(column, "", "title", { layoutOrder = 2 })
	local bar = shell:own(Game.XPBar.new({
		style = shell.styleName,
		parent = column,
		layoutOrder = 3,
		level = props.fromLevel or math.max(1, props.level - 1),
		value = 0,
		max = 1,
	}))
	local panel: any = nil
	local cancelClose: (() -> ())? = nil

	local function clearPanel()
		if panel ~= nil then
			panel:destroy()
			panel = nil
		end
	end
	local function clearTimer()
		if cancelClose then
			cancelClose()
			cancelClose = nil
		end
	end
	shell.trove:Add(function()
		clearPanel()
		clearTimer()
	end)

	local function buildPanel()
		clearPanel()
		local rewards: { any }? = shell.props.rewards
		if rewards == nil or #rewards == 0 then
			return
		end
		panel = Game.RewardPanel.new({
			style = shell.styleName,
			parent = column,
			layoutOrder = 4,
			title = "REWARDS",
			rewards = rewards,
			claimText = shell.props.claimText,
			revealed = false,
		})
		panel.Claimed:Connect(function()
			shell:fire("Claimed", shell.props.level)
			shell:close()
		end)
		shell:focusables({ panel.Instance })
	end

	shell:onLayout(function(env: ScreensLogic.Env)
		local width = math.min(env.safe.w - env.margin * 2, 460)
		column.Size = UDim2.fromOffset(width, math.min(env.safe.h - env.margin * 2, 520))
		bar:update({ size = UDim2.fromOffset(math.min(width, 340), 44) })
	end)

	buildPanel()
	shell.onOpened = function()
		local current: { [string]: any } = shell.props
		levelText:update({ text = "LEVEL " .. tostring(current.level) })
		UI.animate(title.Instance, "LevelUpText")
		UI.animate(levelText.Instance, "RewardTextReveal", { delay = 0.25 })
		-- Fill from where the player was to where the server says they are now.
		local xp: any = current.xp or {}
		local fromLevel = current.fromLevel or math.max(1, current.level - 1)
		bar:update({ level = fromLevel, value = xp.from or 0, max = xp.fromMax or xp.max or 1 })
		clearTimer()
		cancelClose = Host.clock:after(0.45, function()
			cancelClose = nil
			bar:update({ level = current.level, value = xp.value or 0, max = xp.max or 1 })
			UI.animate(bar.Instance, "UpgradePulse")
			if panel ~= nil then
				panel:reveal()
			elseif current.duration > 0 then
				cancelClose = Host.clock:after(current.duration, function()
					cancelClose = nil
					shell:close()
				end)
			end
		end)
	end
	shell.onClosed = clearTimer

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				title:update({ text = partial.title })
			end
			if partial.rewards ~= nil or partial.claimText ~= nil then
				buildPanel()
			end
			if partial.level ~= nil then
				levelText:update({ text = "LEVEL " .. tostring(partial.level) })
			end
		end,
	}
end
