--!strict
-- RewardReveal screen: wraps Rewards.reveal (one reward) and Rewards.batch (several). open()
-- starts the reveal, close() dismisses it, and Claimed fires when the player has seen it through.
-- The reveal shows rewards the server has already granted; nothing is granted here.
--
-- NOT run in Studio: see README.md.

local Rewards = require("../Rewards/Rewards")
local ScreenKit = require("./ScreenKit")

return function(shell: ScreenKit.Shell, _props: { [string]: any })
	local handle: any = nil
	local connection: any = nil

	local function clear()
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		handle = nil
	end

	local function open()
		if handle ~= nil and handle.isRunning() then
			return
		end
		local props = shell.props
		local rewards: { any } = props.rewards
		-- Rewards makes its own overlay ScreenGui; give it the player's GUI, not this screen's root.
		local parent = if shell.gui then shell.gui.Parent else shell.root
		local options: any = {
			parent = parent,
			position = props.position,
			compact = props.compact,
			skippable = props.skippable,
			autoDismiss = props.autoDismiss,
			threshold = props.threshold,
			hint = props.hint,
			displayOrder = props.displayOrder,
		}
		local started: any
		if #rewards == 1 then
			local reward = rewards[1]
			started = Rewards.reveal(reward.rarity or "Common", reward.reward or reward, options)
		else
			started = Rewards.batch(rewards, options)
		end
		handle = started
		connection = started.Completed:Connect(function(dismissed: boolean)
			clear()
			if dismissed then
				shell:fire("Claimed", rewards)
			end
			shell:fire("Closed")
		end)
	end

	shell.trove:Add(function()
		local running = handle
		clear()
		if running ~= nil then
			running.cancel()
		end
	end)

	return {
		open = open,
		close = function()
			if handle ~= nil then
				handle.dismiss()
			end
		end,
		isOpen = function(): boolean
			return handle ~= nil and handle.isRunning()
		end,
		methods = {
			skip = function()
				if handle ~= nil then
					handle.skip()
				end
			end,
		},
	}
end
