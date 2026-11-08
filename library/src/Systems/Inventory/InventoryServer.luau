--!strict
-- Server adapter for InventoryLogic. Keeps one inventory per player, accepts validated and
-- rate-limited intents (MoveSlot, SelectHotbar, AssignHotbar, Drop), fires change signals,
-- replicates a compact view to the owner only and persists through an injected store.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryLogic = require("./InventoryLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Config = {
	registry: InventoryLogic.Registry, -- from InventoryLogic.newRegistry
	capacity: number?, -- slots per player (default 30)
	hotbarSize: number?, -- hotbar positions (default 9)
	store: Store?, -- optional persistence; without it inventories live for the session only
	remoteFolderName: string?, -- folder created in ReplicatedStorage (default "URK_Inventory")
	allowDrop: boolean?, -- accept Drop intents (default true)
	onDrop: ((player: Player, stack: InventoryLogic.Stack) -> ())?, -- spawn a world item, for example
	rateLimit: RateLimiter.Options?, -- per player (default 10 burst, 5 per second)
	autoLoad: boolean?, -- load on PlayerAdded and save on PlayerRemoving (default true)
}

local DEFAULTS = {
	capacity = 30,
	hotbarSize = 9,
	remoteFolderName = "URK_Inventory",
	rateLimit = { capacity = 10, refillPerSecond = 5 },
}

local InventoryServer = {}

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

function InventoryServer.new(config: Config)
	assert(type(config) == "table" and config.registry ~= nil, "InventoryServer.new needs a registry")
	local registry = config.registry
	local capacity = config.capacity or DEFAULTS.capacity
	local hotbarSize = config.hotbarSize or DEFAULTS.hotbarSize
	local store = config.store
	local allowDrop = config.allowDrop ~= false
	local limiter = RateLimiter.new(config.rateLimit or DEFAULTS.rateLimit)
	local trove = Trove.new()

	local inventories: { [Player]: InventoryLogic.Inventory } = {}
	local loadFailed: { [Player]: boolean } = {}

	local folder = getFolder(config.remoteFolderName or DEFAULTS.remoteFolderName)
	trove:Add(folder)
	local moveRemote = makeRemote(folder, "MoveSlot")
	local selectRemote = makeRemote(folder, "SelectHotbar")
	local assignRemote = makeRemote(folder, "AssignHotbar")
	local dropRemote = makeRemote(folder, "Drop")
	local syncRemote = makeRemote(folder, "Sync")
	local requestSyncRemote = makeRemote(folder, "RequestSync")

	local server = {}
	server.Changed = Signal.new() -- (player, inventory)
	server.Dropped = Signal.new() -- (player, stack)
	server.Loaded = Signal.new() -- (player, inventory)

	local function replicate(player: Player)
		local inventory = inventories[player]
		if inventory then
			syncRemote:FireClient(player, InventoryLogic.view(inventory))
		end
	end

	function server:get(player: Player): InventoryLogic.Inventory?
		return inventories[player]
	end

	-- Commits a new inventory value, fires Changed and replicates it to the owner.
	function server:set(player: Player, inventory: InventoryLogic.Inventory)
		if inventories[player] == nil then
			return
		end
		inventories[player] = inventory
		server.Changed:Fire(player, inventory)
		replicate(player)
	end

	-- Applies `transform` to the player's inventory and commits the result when it returns one.
	function server:update(player: Player, transform: (InventoryLogic.Inventory) -> InventoryLogic.Inventory?): boolean
		local current = inventories[player]
		if current == nil then
			return false
		end
		local nextInventory = transform(current)
		if nextInventory == nil then
			return false
		end
		server:set(player, nextInventory)
		return true
	end

	-- Gives items and returns how many did not fit. Matches the `give` callback Pickup expects.
	function server:give(player: Player, itemId: string, count: number): number
		local current = inventories[player]
		if current == nil then
			return count
		end
		local nextInventory, leftover = InventoryLogic.add(current, registry, itemId, count)
		if leftover < count then
			server:set(player, nextInventory)
		end
		return leftover
	end

	-- Removes exactly `count` items. All or nothing.
	function server:take(player: Player, itemId: string, count: number): boolean
		local current = inventories[player]
		if current == nil then
			return false
		end
		local nextInventory = InventoryLogic.remove(current, itemId, count)
		if nextInventory == nil then
			return false
		end
		server:set(player, nextInventory)
		return true
	end

	function server:loadPlayer(player: Player)
		local inventory = InventoryLogic.new(capacity, hotbarSize)
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				inventory = InventoryLogic.deserialize(raw, registry, capacity, hotbarSize)
			else
				-- Never overwrite saved data we could not read.
				loadFailed[player] = true
				warn("[InventoryServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent == nil then
			return
		end
		inventories[player] = inventory
		server.Loaded:Fire(player, inventory)
		replicate(player)
	end

	function server:savePlayer(player: Player): boolean
		local inventory = inventories[player]
		if store == nil or inventory == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, InventoryLogic.serialize(inventory))
		if not ok then
			warn("[InventoryServer] save failed for", player.UserId, saved)
			return false
		end
		return saved == true
	end

	function server:unloadPlayer(player: Player)
		server:savePlayer(player)
		inventories[player] = nil
		loadFailed[player] = nil
		limiter:forget(tostring(player.UserId))
	end

	local function allowed(player: Player): boolean
		return inventories[player] ~= nil and limiter:allow(tostring(player.UserId), os.clock())
	end

	local slotCheck = Validate.integer(1, capacity)
	local amountCheck = Validate.optional(Validate.integer(1, 1e6))
	local hotbarCheck = Validate.integer(1, math.max(hotbarSize, 1))
	local checkMove = Validate.args({ slotCheck, slotCheck, amountCheck })
	local checkSelect = Validate.args({ Validate.optional(hotbarCheck) })
	local checkAssign = Validate.args({ hotbarCheck, slotCheck })
	local checkDrop = Validate.args({ slotCheck, amountCheck })

	trove:Connect(moveRemote.OnServerEvent, function(player: Player, ...: any)
		if not allowed(player) or not checkMove(...) then
			return
		end
		local from, to, amount = ...
		server:update(player, function(inventory)
			return (InventoryLogic.move(inventory, registry, from, to, amount))
		end)
	end)

	trove:Connect(selectRemote.OnServerEvent, function(player: Player, ...: any)
		if not allowed(player) or not checkSelect(...) then
			return
		end
		local position = ...
		server:update(player, function(inventory)
			return (InventoryLogic.selectHotbar(inventory, position))
		end)
	end)

	trove:Connect(assignRemote.OnServerEvent, function(player: Player, ...: any)
		if not allowed(player) or not checkAssign(...) then
			return
		end
		local position, index = ...
		server:update(player, function(inventory)
			return (InventoryLogic.assignHotbar(inventory, position, index))
		end)
	end)

	trove:Connect(dropRemote.OnServerEvent, function(player: Player, ...: any)
		if not allowDrop or not allowed(player) or not checkDrop(...) then
			return
		end
		local index, amount = ...
		local current = inventories[player]
		if current == nil then
			return
		end
		local nextInventory, stack = InventoryLogic.removeAt(current, index, amount)
		if nextInventory == nil or stack == nil then
			return
		end
		server:set(player, nextInventory)
		server.Dropped:Fire(player, stack)
		if config.onDrop then
			config.onDrop(player, stack)
		end
	end)

	trove:Connect(requestSyncRemote.OnServerEvent, function(player: Player)
		if allowed(player) then
			replicate(player)
		end
	end)

	if config.autoLoad ~= false then
		trove:Connect(Players.PlayerAdded, function(player: Player)
			server:loadPlayer(player)
		end)
		trove:Connect(Players.PlayerRemoving, function(player: Player)
			server:unloadPlayer(player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(server.loadPlayer, server, player)
		end
		game:BindToClose(function()
			local pending = 0
			for player in inventories do
				pending += 1
				task.spawn(function()
					server:savePlayer(player)
					pending -= 1
				end)
			end
			local deadline = os.clock() + 25
			while pending > 0 and os.clock() < deadline do
				task.wait(0.1)
			end
		end)
	end

	-- Disconnects remotes and signals and removes the remote folder. Does not save.
	function server:destroy()
		trove:Clean()
		server.Changed:DisconnectAll()
		server.Dropped:DisconnectAll()
		server.Loaded:DisconnectAll()
		table.clear(inventories)
	end

	return server
end

return InventoryServer
