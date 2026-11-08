--!strict
-- Test fixture: ordinary game code that must produce no HIGH findings.
local Players = game:GetService("Players")
local Shared = require(script.Parent.Shared)
Players.PlayerAdded:Connect(function(player)
	print("hello", player.Name, Shared.VERSION)
end)
