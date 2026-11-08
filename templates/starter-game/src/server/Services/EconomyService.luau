--!strict
-- EconomyService: the only place that changes coins and rebirths.
-- Balances are mirrored to player attributes ("Coins", "Rebirths") so client UI can read them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = Shared:WaitForChild("Logic")
local Config = require(Shared:WaitForChild("Config"))
local DataSchema = require(Logic:WaitForChild("DataSchema"))
local Economy = require(Logic:WaitForChild("Economy"))
local Net = require(Shared:WaitForChild("Net"))
local Validate = require(Logic:WaitForChild("Validate"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))

type PlayerData = DataSchema.PlayerData

local REBIRTH_REMOTE = "RequestRebirth"

local EconomyService = { Name = "EconomyService", Priority = 10 }

local function publish(player: Player, data: PlayerData)
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Rebirths", data.rebirths)
end

function EconomyService:GetCoins(player: Player): number
	local data = PlayerDataService:Get(player)
	return if data then data.coins else 0
end

-- Earnings multiplier from rebirths. Apply it to income, not to refunds or rewards with fixed values.
function EconomyService:GetMultiplier(player: Player): number
	local data = PlayerDataService:Get(player)
	return Economy.rebirthMultiplier(if data then data.rebirths else 0, Config.RebirthBonus)
end

-- Adds coins and returns how many were actually added (0 if data is not loaded or `amount` is invalid).
function EconomyService:AddCoins(player: Player, amount: number): number
	local added = 0
	if not Economy.isFinite(amount) or amount <= 0 then
		return 0
	end
	PlayerDataService:Update(player, function(data: PlayerData)
		local before = data.coins
		data.coins = Economy.add(before, amount)
		added = data.coins - before
	end)
	return added
end

-- Spends `cost` coins if the player can afford it. Returns true when the coins were taken.
function EconomyService:TrySpend(player: Player, cost: number): boolean
	local data = PlayerDataService:Get(player)
	if not data or not Economy.canAfford(data.coins, cost) then
		return false
	end
	return PlayerDataService:Update(player, function(current: PlayerData)
		current.coins = Economy.add(current.coins, -cost)
	end)
end

function EconomyService:GetRebirthCost(player: Player): number
	local data = PlayerDataService:Get(player)
	local rebirths = if data then data.rebirths else 0
	return Economy.rebirthCost(Config.RebirthBaseCost, Config.RebirthCostScale, rebirths)
end

-- Resets coins in exchange for a permanent earnings multiplier.
function EconomyService:Rebirth(player: Player): (boolean, string?)
	local cost = self:GetRebirthCost(player)
	local data = PlayerDataService:Get(player)
	if not data then
		return false, "data not loaded"
	end
	if not Economy.canAfford(data.coins, cost) then
		return false, "not enough coins"
	end
	PlayerDataService:Update(player, function(current: PlayerData)
		current.coins = 0
		current.rebirths += 1
	end)
	return true, nil
end

function EconomyService:Init()
	PlayerDataService.Loaded:Connect(publish)
	PlayerDataService.Changed:Connect(publish)

	local options = { validate = Validate.args({}), rateLimit = { capacity = 2, refillPerSecond = 0.5 } }
	Net.onServerEvent(REBIRTH_REMOTE, options, function(player: Player)
		self:Rebirth(player)
	end)
end

return EconomyService
