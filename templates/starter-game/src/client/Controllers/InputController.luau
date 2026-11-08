--!strict
-- InputController: maps keys to named actions and fires ActionTriggered(actionName).
-- Other controllers bind keys with InputController:Bind and listen for their action names.
-- Input already handled by Roblox UI (typing in a TextBox, pressing a button) is ignored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))

local InputController = {
	Name = "InputController",
	Priority = 0,
	-- Fires (actionName) when a bound key is pressed.
	ActionTriggered = Signal.new(),
}

local bindings: { [Enum.KeyCode]: string } = {}

function InputController:Bind(keyCode: Enum.KeyCode, action: string)
	bindings[keyCode] = action
end

function InputController:Unbind(keyCode: Enum.KeyCode)
	bindings[keyCode] = nil
end

function InputController:Init()
	self:Bind(Enum.KeyCode.R, "Rebirth")
	self.ActionTriggered:Connect(function(action: string)
		if action == "Rebirth" then
			Net.fireServer("RequestRebirth")
		end
	end)
end

function InputController:Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local action = bindings[input.KeyCode]
		if action then
			self.ActionTriggered:Fire(action)
		end
	end)
end

return InputController
