--!strict
-- DataStore adapter and per-player session manager for SaveDataLogic.
--
-- SaveDataServer.dataStoreStore(options) returns a store `{ load, save, release }` that uses
-- UpdateAsync with a session lock, retries with exponential backoff and waits for request budget.
-- SaveDataServer.new(options) loads players on join, autosaves, releases on leave and flushes on
-- BindToClose. Any object with the same `load`/`save`/`release` shape (for example a ProfileStore
-- wrapper, see README) can replace the DataStore store.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local SaveDataLogic = require("./SaveDataLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Store = {
	load: (userId: number) -> any?, -- raises an error when the data cannot be read
	save: (userId: number, data: any) -> boolean, -- true once written
	release: ((userId: number, data: any) -> boolean)?, -- final save that ends the session
}

export type DataStoreOptions = {
	name: string, -- DataStore name
	scope: string?, -- DataStore scope
	schema: SaveDataLogic.Schema, -- from SaveDataLogic.newSchema
	keyPrefix: string?, -- key = prefix .. userId (default "Player_")
	lockTimeout: number?, -- seconds before another server's lock counts as abandoned (default 1800)
	lockRetries: number?, -- tries to take a held lock before giving up (default 5, 6 s apart)
	attempts: number?, -- retries per DataStore call (default 5)
	sleep: ((seconds: number) -> ())?, -- default task.wait
	jobId: string?, -- default game.JobId (Studio uses "studio" when empty)
}

export type ManagerOptions = {
	store: Store, -- usually from dataStoreStore
	schema: SaveDataLogic.Schema, -- used for defaults when the store returns nil
	autosaveSeconds: number?, -- default 120; also refreshes the session heartbeat
	kickOnLoadFailure: boolean?, -- default true, so a player never plays on unsaved data
}

local SaveDataServer = {}

local function budget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

function SaveDataServer.dataStoreStore(options: DataStoreOptions): Store
	local dataStore = DataStoreService:GetDataStore(options.name, options.scope)
	local schema = options.schema
	local prefix = options.keyPrefix or "Player_"
	local sleep = options.sleep or function(seconds: number)
		task.wait(seconds)
	end
	local jobId = options.jobId
	if jobId == nil then
		jobId = if game.JobId ~= "" then game.JobId else "studio"
	end
	local random = Random.new()
	local retryOptions: SaveDataLogic.RetryOptions = {
		attempts = options.attempts or 5,
		base = 1,
		max = 16,
		sleep = sleep,
		rng = function()
			return random:NextNumber()
		end,
	}

	local function updateBudget(): number
		return budget(Enum.DataStoreRequestType.UpdateAsync)
	end

	local function update(key: string, transform: (any) -> any): any
		SaveDataLogic.waitForBudget(updateBudget, 1, sleep, 30)
		local function call(): any
			return dataStore:UpdateAsync(key, transform)
		end
		local ok, result = SaveDataLogic.retry(call, retryOptions)
		if not ok then
			error(result, 0)
		end
		return result
	end

	local store = {}

	function store.load(userId: number): any?
		local key = prefix .. tostring(userId)
		local lockTries = options.lockRetries or 5
		local lastReason = "unknown"
		for attempt = 1, lockTries do
			local plan: SaveDataLogic.LoadPlan? = nil
			update(key, function(old: any)
				plan = SaveDataLogic.planLoad(schema, old, jobId, os.time(), options.lockTimeout)
				local current = plan
				return if current and current.ok then current.record else nil
			end)
			local finished = plan
			if finished and finished.ok then
				return finished.data
			end
			lastReason = if finished then finished.reason or lastReason else lastReason
			if attempt < lockTries then
				sleep(6)
			end
		end
		error("SaveData load failed: " .. lastReason, 0)
	end

	local function write(userId: number, data: any, release: boolean): boolean
		local key = prefix .. tostring(userId)
		local plan: SaveDataLogic.SavePlan? = nil
		local ok = pcall(update, key, function(old: any)
			plan = SaveDataLogic.planSave(schema, old, jobId, data, os.time(), release)
			local current = plan
			return if current and current.ok then current.record else nil
		end)
		local finished = plan
		return ok and finished ~= nil and finished.ok
	end

	function store.save(userId: number, data: any): boolean
		return write(userId, data, false)
	end

	function store.release(userId: number, data: any): boolean
		return write(userId, data, true)
	end

	return store
end

function SaveDataServer.new(options: ManagerOptions)
	local store = options.store
	local schema = options.schema
	local trove = Trove.new()
	local sessions: { [Player]: { data: any, dirty: boolean } } = {}
	local closing = false

	local manager = {}
	manager.Loaded = Signal.new() -- (player, data)
	manager.LoadFailed = Signal.new() -- (player, reason)
	manager.Saved = Signal.new() -- (player, ok)

	function manager:get(player: Player): any
		local session = sessions[player]
		return if session then session.data else nil
	end

	-- Changes a player's data. `transform` gets the current data and returns the new data
	-- (or nothing to keep the same table after editing it in place).
	function manager:update(player: Player, transform: (any) -> any?): boolean
		local session = sessions[player]
		if session == nil then
			return false
		end
		local result = transform(session.data)
		if result ~= nil then
			session.data = result
		end
		session.dirty = true
		return true
	end

	function manager:save(player: Player): boolean
		local session = sessions[player]
		if session == nil then
			return false
		end
		local ok, saved = pcall(store.save, player.UserId, session.data)
		local success = ok and saved == true
		if success then
			session.dirty = false
		end
		manager.Saved:Fire(player, success)
		return success
	end

	local function release(player: Player)
		local session = sessions[player]
		if session == nil then
			return
		end
		sessions[player] = nil
		local finalSave = store.release or store.save
		local ok, saved = pcall(finalSave, player.UserId, session.data)
		manager.Saved:Fire(player, ok and saved == true)
	end

	local function load(player: Player)
		local ok, raw = pcall(store.load, player.UserId)
		if not ok then
			manager.LoadFailed:Fire(player, raw)
			if options.kickOnLoadFailure ~= false then
				player:Kick("Your data could not be loaded. Please rejoin in a minute.")
			end
			return
		end
		local data = if raw == nil then SaveDataLogic.defaults(schema) else raw
		if player.Parent == nil or closing then
			-- The player left while loading: give the session back straight away.
			local finalSave = store.release or store.save
			pcall(finalSave, player.UserId, data)
			return
		end
		sessions[player] = { data = data, dirty = false }
		manager.Loaded:Fire(player, data)
	end

	trove:Connect(Players.PlayerAdded, load)
	trove:Connect(Players.PlayerRemoving, release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	local running = true
	trove:Add(function()
		running = false
	end)
	task.spawn(function()
		local interval = options.autosaveSeconds or 120
		while running do
			task.wait(interval)
			for player in sessions do
				if running then
					-- Saving clean data too keeps the session heartbeat fresh.
					task.spawn(manager.save, manager, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		closing = true
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	function manager:destroy()
		trove:Clean()
		manager.Loaded:DisconnectAll()
		manager.LoadFailed:DisconnectAll()
		manager.Saved:DisconnectAll()
	end

	return manager
end

return SaveDataServer
