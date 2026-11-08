-- Deliberately insecure fixture for tests/test_v4_tools.py (audit rules). Never copy this.
local remote = game.ReplicatedStorage.Buy
remote.OnServerEvent:Connect(function(player, itemId, price)
	player.leaderstats.Coins.Value -= price
end)
local f = loadstring("print(1)")
local m = require(1234567)
