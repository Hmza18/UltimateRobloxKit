--!strict
-- ClickController: a click or tap anywhere in the world asks the server to collect.
-- E buys a Power level and Q buys a Multiplier level. The server checks everything again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SimConfig = require(Shared:WaitForChild("SimConfig"))

local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Controllers = PlayerScripts:WaitForChild("Client"):WaitForChild("Controllers")
local InputController = require(Controllers:WaitForChild("InputController"))

local ClickController = { Name = "ClickController", Priority = 30 }

local lastClick = 0

local function collect()
	-- Match the server cooldown so the client does not send requests it knows will be dropped.
	local now = os.clock()
	if now - lastClick < SimConfig.ClickCooldown then
		return
	end
	lastClick = now
	Net.fireServer("Collect")
end

function ClickController:Init()
	InputController:Bind(Enum.KeyCode.E, "BuyPower")
	InputController:Bind(Enum.KeyCode.Q, "BuyMultiplier")
	InputController.ActionTriggered:Connect(function(action: string)
		if action == "BuyPower" then
			Net.fireServer("BuyUpgrade", "Power")
		elseif action == "BuyMultiplier" then
			Net.fireServer("BuyUpgrade", "Multiplier")
		end
	end)
end

function ClickController:Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
		if isClick or input.UserInputType == Enum.UserInputType.Touch then
			collect()
		end
	end)
end

return ClickController
