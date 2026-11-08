--!strict
-- InventoryService: server-owned inventories built on the pure Logic/Inventory module.
-- Clients can only ask to drop items, through a validated and rate-limited remote.
-- The server sends the full inventory to its owner after every change ("InventoryChanged").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = Shared:WaitForChild("Logic")
local Config = require(Shared:WaitForChild("Config"))
local DataSchema = require(Logic:WaitForChild("DataSchema"))
local Inventory = require(Logic:WaitForChild("Inventory"))
local Net = require(Shared:WaitForChild("Net"))
local Validate = require(Logic:WaitForChild("Validate"))

local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))

type PlayerData = DataSchema.PlayerData

local CHANGED_REMOTE = "InventoryChanged"
local DROP_REMOTE = "DropItem"

local isItemId = Validate.oneOf(Config.Items)
local dropArgs = Validate.args({ isItemId, Validate.integer(1, DataSchema.MAX_STACK) })

local InventoryService = { Name = "InventoryService", Priority = 20 }

local function sendInventory(player: Player, data: PlayerData)
	Net.fireClient(CHANGED_REMOTE, player, data.inventory)
end

function InventoryService:Count(player: Player, itemId: string): number
	local data = PlayerDataService:Get(player)
	return if data then Inventory.count(data.inventory, itemId) else 0
end

-- Gives up to `amount` items and returns how many did not fit.
function InventoryService:Give(player: Player, itemId: string, amount: number): number
	assert(isItemId(itemId), "unknown item id " .. itemId)
	local leftover = amount
	local changed = PlayerDataService:Update(player, function(data: PlayerData)
		data.inventory, leftover = Inventory.add(data.inventory, itemId, amount)
	end)
	if changed then
		local data = PlayerDataService:Get(player)
		if data then
			sendInventory(player, data)
		end
	end
	return leftover
end

-- Removes exactly `amount` items. Returns false and a reason when the player has too few.
function InventoryService:Remove(player: Player, itemId: string, amount: number): (boolean, string?)
	local data = PlayerDataService:Get(player)
	if not data then
		return false, "data not loaded"
	end
	local nextInventory, reason = Inventory.remove(data.inventory, itemId, amount)
	if not nextInventory then
		return false, reason
	end
	PlayerDataService:Update(player, function(current: PlayerData)
		current.inventory = nextInventory
	end)
	sendInventory(player, data)
	return true, nil
end

function InventoryService:Init()
	Net.remote(CHANGED_REMOTE)
	PlayerDataService.Loaded:Connect(sendInventory)

	local options = { validate = dropArgs, rateLimit = { capacity = 5, refillPerSecond = 2 } }
	Net.onServerEvent(DROP_REMOTE, options, function(player: Player, itemId: string, amount: number)
		self:Remove(player, itemId, amount)
	end)
end

return InventoryService
