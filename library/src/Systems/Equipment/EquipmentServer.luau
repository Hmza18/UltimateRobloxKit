--!strict
-- Server adapter for EquipmentLogic. Keeps a loadout per player, validates Equip and Unequip
-- intents, checks ownership through a callback and applies results through callbacks: by
-- default final stats become player attributes, and `EquipmentServer.toolEquipper` clones Tools.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentLogic = require("./EquipmentLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Config = {
	catalog: EquipmentLogic.Catalog, -- from EquipmentLogic.newCatalog
	getContext: ((player: Player) -> EquipmentLogic.Context)?, -- level and tags (default: none)
	hasItem: ((player: Player, itemId: string) -> boolean)?, -- ownership check (default: allow)
	baseStats: ((player: Player) -> { [string]: number })?, -- stats before equipment (default {})
	onEquip: ((player: Player, slot: string, itemId: string) -> ())?, -- apply visuals or tools
	onUnequip: ((player: Player, slot: string, itemId: string) -> ())?, -- undo onEquip
	onStats: ((player: Player, stats: { [string]: number }) -> ())?, -- default: Stat_<name> attributes
	store: Store?, -- optional persistence
	remoteFolderName: string?, -- default "URK_Equipment"
	rateLimit: RateLimiter.Options?, -- default 6 burst, 3 per second
}

local EquipmentServer = {}

local function getFolder(name: string): Instance
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ReplicatedStorage
	return folder
end

local function makeRemote(folder: Instance, name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function setStatAttributes(player: Player, stats: { [string]: number })
	for name, value in stats do
		player:SetAttribute("Stat_" .. name, value)
	end
end

-- Builds onEquip/onUnequip callbacks that clone a Tool from `toolsFolder` (named like the item)
-- into the player's Backpack, and remove it again on unequip.
function EquipmentServer.toolEquipper(toolsFolder: Instance)
	local equipper = {}
	function equipper.onEquip(player: Player, _slot: string, itemId: string)
		local template = toolsFolder:FindFirstChild(itemId)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if template and template:IsA("Tool") and backpack then
			local tool = template:Clone()
			tool:SetAttribute("EquipmentItem", itemId)
			tool.Parent = backpack
		end
	end
	function equipper.onUnequip(player: Player, _slot: string, itemId: string)
		local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
		for _, container in containers do
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("EquipmentItem") == itemId then
					child:Destroy()
				end
			end
		end
	end
	return equipper
end

function EquipmentServer.new(config: Config)
	local catalog = config.catalog
	local store = config.store
	local onStats = config.onStats or setStatAttributes
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 6, refillPerSecond = 3 })
	local trove = Trove.new()
	local loadouts: { [Player]: EquipmentLogic.Loadout } = {}
	local loadFailed: { [Player]: boolean } = {}

	local folder = getFolder(config.remoteFolderName or "URK_Equipment")
	trove:Add(folder)
	local equipRemote = makeRemote(folder, "Equip")
	local unequipRemote = makeRemote(folder, "Unequip")
	local syncRemote = makeRemote(folder, "Sync")

	local server = {}
	server.Equipped = Signal.new() -- (player, slot, itemId, replacedItemId)
	server.Unequipped = Signal.new() -- (player, slot, itemId)
	server.StatsChanged = Signal.new() -- (player, stats)

	local function context(player: Player): EquipmentLogic.Context
		return if config.getContext then config.getContext(player) else {}
	end

	function server:stats(player: Player): { [string]: number }
		local loadout = loadouts[player] or EquipmentLogic.new()
		local base = if config.baseStats then config.baseStats(player) else {}
		return EquipmentLogic.aggregate(catalog, loadout, base)
	end

	local function refresh(player: Player)
		local loadout = loadouts[player]
		if loadout == nil then
			return
		end
		local stats = server:stats(player)
		onStats(player, stats)
		server.StatsChanged:Fire(player, stats)
		syncRemote:FireClient(player, loadout.equipped, stats)
	end

	function server:get(player: Player): EquipmentLogic.Loadout?
		return loadouts[player]
	end

	function server:equip(player: Player, itemId: string, slot: string?): (boolean, string?)
		local loadout = loadouts[player]
		if loadout == nil then
			return false, "not loaded"
		end
		if config.hasItem and not config.hasItem(player, itemId) then
			return false, "not owned"
		end
		-- On success the second value is the slot used; on failure it is the reason.
		local nextLoadout, usedSlot, replaced = EquipmentLogic.equip(catalog, loadout, itemId, context(player), slot)
		if nextLoadout == nil or usedSlot == nil then
			return false, usedSlot or "cannot equip"
		end
		loadouts[player] = nextLoadout
		if replaced and config.onUnequip then
			config.onUnequip(player, usedSlot, replaced)
		end
		if config.onEquip then
			config.onEquip(player, usedSlot, itemId)
		end
		server.Equipped:Fire(player, usedSlot, itemId, replaced)
		refresh(player)
		return true, nil
	end

	function server:unequip(player: Player, slot: string): boolean
		local loadout = loadouts[player]
		if loadout == nil then
			return false
		end
		local nextLoadout, removed = EquipmentLogic.unequip(loadout, slot)
		if removed == nil then
			return false
		end
		loadouts[player] = nextLoadout
		if config.onUnequip then
			config.onUnequip(player, slot, removed)
		end
		server.Unequipped:Fire(player, slot, removed)
		refresh(player)
		return true
	end

	-- Re-checks requirements (call after a level or tag change) and unequips what no longer qualifies.
	function server:revalidate(player: Player)
		local loadout = loadouts[player]
		if loadout == nil then
			return
		end
		for _, slot in EquipmentLogic.invalidSlots(catalog, loadout, context(player)) do
			server:unequip(player, slot)
		end
	end

	function server:loadPlayer(player: Player)
		local loadout = EquipmentLogic.new()
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				loadout = EquipmentLogic.deserialize(catalog, raw)
			else
				loadFailed[player] = true
				warn("[EquipmentServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent == nil then
			return
		end
		loadouts[player] = EquipmentLogic.new()
		-- Re-equip through the normal path so ownership, requirements and callbacks all apply.
		for _, slot in catalog.slots do
			local itemId = loadout.equipped[slot]
			if itemId then
				server:equip(player, itemId, slot)
			end
		end
		refresh(player)
	end

	function server:savePlayer(player: Player): boolean
		local loadout = loadouts[player]
		if store == nil or loadout == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, EquipmentLogic.serialize(loadout))
		return ok and saved == true
	end

	function server:unloadPlayer(player: Player)
		server:savePlayer(player)
		loadouts[player] = nil
		loadFailed[player] = nil
		limiter:forget(tostring(player.UserId))
	end

	local nameCheck = Validate.string({ minLength = 1, maxLength = 100 })
	local checkEquip = Validate.args({ nameCheck, Validate.optional(Validate.oneOf(catalog.slots)) })
	local checkUnequip = Validate.args({ Validate.oneOf(catalog.slots) })

	trove:Connect(equipRemote.OnServerEvent, function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) or not checkEquip(...) then
			return
		end
		local itemId, slot = ...
		server:equip(player, itemId, slot)
	end)

	trove:Connect(unequipRemote.OnServerEvent, function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) or not checkUnequip(...) then
			return
		end
		local slot = ...
		server:unequip(player, slot)
	end)

	trove:Connect(Players.PlayerAdded, function(player: Player)
		server:loadPlayer(player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		server:unloadPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(server.loadPlayer, server, player)
	end
	if store then
		game:BindToClose(function()
			for player in loadouts do
				server:savePlayer(player)
			end
		end)
	end

	function server:destroy()
		trove:Clean()
		server.Equipped:DisconnectAll()
		server.Unequipped:DisconnectAll()
		server.StatsChanged:DisconnectAll()
		table.clear(loadouts)
	end

	return server
end

return EquipmentServer
