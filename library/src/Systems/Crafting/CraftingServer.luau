--!strict
-- Server adapter for CraftingLogic. Crafts against an inventory owned by another system (for
-- example InventoryServer) through `getInventory`/`setInventory`, keeps a timed queue per player,
-- delivers finished jobs automatically and validates every client intent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingLogic = require("./CraftingLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = { load: (userId: number) -> any?, save: (userId: number, data: any) -> boolean }

export type Config = {
	book: CraftingLogic.Book, -- from CraftingLogic.newBook
	ops: CraftingLogic.InventoryOps, -- usually CraftingLogic.inventoryOps(registry)
	getInventory: (player: Player) -> any?, -- current inventory value
	setInventory: (player: Player, inventory: any) -> (), -- commit a new inventory value
	getStations: ((player: Player) -> { [string]: boolean })?, -- stations in reach (default none)
	maxJobs: number?, -- queue length per player (default 10)
	store: Store?, -- persists queues
	clock: (() -> number)?, -- default os.time, so queued jobs keep running across sessions
	collectInterval: number?, -- seconds between automatic deliveries (default 1)
	remoteFolderName: string?, -- default "URK_Crafting"
	rateLimit: RateLimiter.Options?, -- default 6 burst, 3 per second
}

local CraftingServer = {}

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

function CraftingServer.new(config: Config)
	local book, ops = config.book, config.ops
	local clock = config.clock or os.time
	local store = config.store
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 6, refillPerSecond = 3 })
	local trove = Trove.new()
	local queues: { [Player]: CraftingLogic.Queue } = {}
	local loadFailed: { [Player]: boolean } = {}

	local folder = getFolder(config.remoteFolderName or "URK_Crafting")
	trove:Add(folder)
	local craftRemote = makeRemote(folder, "Craft")
	local enqueueRemote = makeRemote(folder, "Enqueue")
	local cancelRemote = makeRemote(folder, "Cancel")
	local syncRemote = makeRemote(folder, "Sync")

	local server = {}
	server.Crafted = Signal.new() -- (player, recipeId, times)
	server.JobStarted = Signal.new() -- (player, job)
	server.JobCompleted = Signal.new() -- (player, job)

	local function context(player: Player): CraftingLogic.Context
		return { stations = if config.getStations then config.getStations(player) else nil }
	end

	local function sync(player: Player)
		local queue = queues[player]
		if queue then
			syncRemote:FireClient(player, CraftingLogic.serializeQueue(queue))
		end
	end

	function server:craft(player: Player, recipeId: string, times: number?): (boolean, string?)
		local inventory = config.getInventory(player)
		if inventory == nil then
			return false, "not loaded"
		end
		local result = CraftingLogic.craft(book, recipeId, inventory, ops, context(player), times)
		if not result.ok then
			return false, result.reason
		end
		config.setInventory(player, result.inventory)
		server.Crafted:Fire(player, recipeId, times or 1)
		return true, nil
	end

	function server:enqueue(player: Player, recipeId: string): (boolean, string?)
		local inventory = config.getInventory(player)
		local queue = queues[player]
		if inventory == nil or queue == nil then
			return false, "not loaded"
		end
		local result = CraftingLogic.enqueue(book, queue, recipeId, inventory, ops, context(player), clock())
		if not result.ok then
			return false, result.reason
		end
		queues[player] = result.queue
		config.setInventory(player, result.inventory)
		server.JobStarted:Fire(player, result.job)
		sync(player)
		return true, nil
	end

	function server:cancel(player: Player, jobId: number): (boolean, string?)
		local inventory = config.getInventory(player)
		local queue = queues[player]
		if inventory == nil or queue == nil then
			return false, "not loaded"
		end
		local result = CraftingLogic.cancel(book, queue, jobId, inventory, ops, clock())
		if not result.ok then
			return false, result.reason
		end
		queues[player] = result.queue
		config.setInventory(player, result.inventory)
		sync(player)
		return true, nil
	end

	-- Delivers finished jobs for one player. Returns how many were delivered.
	function server:collect(player: Player): number
		local inventory = config.getInventory(player)
		local queue = queues[player]
		if inventory == nil or queue == nil then
			return 0
		end
		local result = CraftingLogic.collect(book, queue, inventory, ops, clock())
		if #result.completed == 0 then
			return 0
		end
		queues[player] = result.queue
		config.setInventory(player, result.inventory)
		for _, job in result.completed do
			server.JobCompleted:Fire(player, job)
		end
		sync(player)
		return #result.completed
	end

	function server:getQueue(player: Player): CraftingLogic.Queue?
		return queues[player]
	end

	function server:loadPlayer(player: Player)
		local queue = CraftingLogic.newQueue(config.maxJobs)
		if store then
			local ok, raw = pcall(store.load, player.UserId)
			if ok then
				queue = CraftingLogic.deserializeQueue(book, raw, config.maxJobs)
			else
				loadFailed[player] = true
				warn("[CraftingServer] load failed for", player.UserId, raw)
			end
		end
		if player.Parent ~= nil then
			queues[player] = queue
			sync(player)
		end
	end

	function server:savePlayer(player: Player): boolean
		local queue = queues[player]
		if store == nil or queue == nil or loadFailed[player] then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, CraftingLogic.serializeQueue(queue))
		return ok and saved == true
	end

	function server:unloadPlayer(player: Player)
		server:savePlayer(player)
		queues[player] = nil
		loadFailed[player] = nil
		limiter:forget(tostring(player.UserId))
	end

	local recipeCheck = Validate.string({ minLength = 1, maxLength = 100 })
	local checkCraft = Validate.args({ recipeCheck, Validate.optional(Validate.integer(1, CraftingLogic.MAX_TIMES)) })
	local checkEnqueue = Validate.args({ recipeCheck })
	local checkCancel = Validate.args({ Validate.integer(1, 1e9) })

	local function allowed(player: Player): boolean
		return limiter:allow(tostring(player.UserId), os.clock())
	end

	trove:Connect(craftRemote.OnServerEvent, function(player: Player, ...: any)
		if allowed(player) and checkCraft(...) then
			local recipeId, times = ...
			server:craft(player, recipeId, times)
		end
	end)
	trove:Connect(enqueueRemote.OnServerEvent, function(player: Player, ...: any)
		if allowed(player) and checkEnqueue(...) then
			local recipeId = ...
			server:enqueue(player, recipeId)
		end
	end)
	trove:Connect(cancelRemote.OnServerEvent, function(player: Player, ...: any)
		if allowed(player) and checkCancel(...) then
			local jobId = ...
			server:cancel(player, jobId)
		end
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
			for player in queues do
				server:savePlayer(player)
			end
		end)
	end

	local running = true
	trove:Add(function()
		running = false
	end)
	task.spawn(function()
		local interval = config.collectInterval or 1
		while running do
			task.wait(interval)
			for player in queues do
				server:collect(player)
			end
		end
	end)

	function server:destroy()
		trove:Clean()
		server.Crafted:DisconnectAll()
		server.JobStarted:DisconnectAll()
		server.JobCompleted:DisconnectAll()
		table.clear(queues)
	end

	return server
end

return CraftingServer
