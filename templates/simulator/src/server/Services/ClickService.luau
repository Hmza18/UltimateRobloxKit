--!strict
-- ClickService: server-validated "Collect" requests. The client only says "I clicked".
-- The server enforces the cooldown, works out the reward itself and pays it out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = Shared:WaitForChild("Logic")
local Net = require(Shared:WaitForChild("Net"))
local SimConfig = require(Shared:WaitForChild("SimConfig"))
local SimFormulas = require(Logic:WaitForChild("SimFormulas"))
local Validate = require(Logic:WaitForChild("Validate"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local EconomyService = require(Services:WaitForChild("EconomyService"))
local UpgradeService = require(Services:WaitForChild("UpgradeService"))

local COLLECT_REMOTE = "Collect"

local ClickService = { Name = "ClickService", Priority = 40 }

local lastCollect: { [Player]: number } = {}

-- Coins one click is worth for this player right now.
function ClickService:GetClickValue(player: Player): number
	return SimFormulas.clickValue({
		base = SimConfig.BaseClickValue,
		powerLevel = UpgradeService:GetLevel(player, "Power"),
		powerBonus = SimConfig.PowerBonus,
		multiplierLevel = UpgradeService:GetLevel(player, "Multiplier"),
		multiplierBonus = SimConfig.MultiplierBonus,
		rebirthMultiplier = EconomyService:GetMultiplier(player),
	})
end

-- Pays one click if the cooldown has passed. Returns the coins added (0 when rejected).
function ClickService:Collect(player: Player): number
	local now = os.clock()
	if not SimFormulas.canCollect(lastCollect[player], now, SimConfig.ClickCooldown) then
		return 0
	end
	lastCollect[player] = now
	return EconomyService:AddCoins(player, self:GetClickValue(player))
end

function ClickService:Init()
	-- The token bucket stops floods; the cooldown above caps the steady click rate.
	local options = { validate = Validate.args({}), rateLimit = { capacity = 15, refillPerSecond = 10 } }
	Net.onServerEvent(COLLECT_REMOTE, options, function(player: Player)
		self:Collect(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCollect[player] = nil
	end)
end

return ClickService
