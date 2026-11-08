--!strict
-- UpgradeService: buys upgrade levels with coins. Levels are saved in data.progress["upgrade:<Id>"]
-- and mirrored to player attributes ("Upgrade_<Id>") for the client UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = Shared:WaitForChild("Logic")
local DataSchema = require(Logic:WaitForChild("DataSchema"))
local Net = require(Shared:WaitForChild("Net"))
local SimConfig = require(Shared:WaitForChild("SimConfig"))
local SimFormulas = require(Logic:WaitForChild("SimFormulas"))
local Validate = require(Logic:WaitForChild("Validate"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local EconomyService = require(Services:WaitForChild("EconomyService"))
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))

type PlayerData = DataSchema.PlayerData

local BUY_REMOTE = "BuyUpgrade"

local UpgradeService = { Name = "UpgradeService", Priority = 30 }

local upgradeIds: { string } = {}
for id in SimConfig.Upgrades do
	table.insert(upgradeIds, id)
end
table.sort(upgradeIds)

local buyArgs = Validate.args({ Validate.oneOf(upgradeIds) })

local function progressKey(upgradeId: string): string
	return "upgrade:" .. upgradeId
end

local function publish(player: Player, data: PlayerData)
	for _, id in upgradeIds do
		player:SetAttribute("Upgrade_" .. id, data.progress[progressKey(id)] or 0)
	end
end

function UpgradeService:GetLevel(player: Player, upgradeId: string): number
	local data = PlayerDataService:Get(player)
	return if data then data.progress[progressKey(upgradeId)] or 0 else 0
end

function UpgradeService:GetCost(player: Player, upgradeId: string): number?
	local upgrade = SimConfig.Upgrades[upgradeId]
	if not upgrade then
		return nil
	end
	return SimFormulas.upgradeCost(upgrade.BaseCost, upgrade.Growth, self:GetLevel(player, upgradeId))
end

-- Buys one level. Returns false and a reason when the upgrade is unknown, maxed or unaffordable.
function UpgradeService:Buy(player: Player, upgradeId: string): (boolean, string?)
	local upgrade = SimConfig.Upgrades[upgradeId]
	if not upgrade then
		return false, "unknown upgrade"
	end
	local level = self:GetLevel(player, upgradeId)
	if level >= upgrade.MaxLevel then
		return false, "already at max level"
	end
	local cost = SimFormulas.upgradeCost(upgrade.BaseCost, upgrade.Growth, level)
	-- TrySpend and Update run without yielding in between, so nothing can interleave.
	if not EconomyService:TrySpend(player, cost) then
		return false, "not enough coins"
	end
	PlayerDataService:Update(player, function(data: PlayerData)
		data.progress[progressKey(upgradeId)] = level + 1
	end)
	return true, nil
end

function UpgradeService:Init()
	PlayerDataService.Loaded:Connect(publish)
	PlayerDataService.Changed:Connect(publish)

	local options = { validate = buyArgs, rateLimit = { capacity = 5, refillPerSecond = 4 } }
	Net.onServerEvent(BUY_REMOTE, options, function(player: Player, upgradeId: string)
		self:Buy(player, upgradeId)
	end)
end

return UpgradeService
