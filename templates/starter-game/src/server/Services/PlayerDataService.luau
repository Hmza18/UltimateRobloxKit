--!strict
-- PlayerDataService: loads, autosaves and releases player data in one DataStore.
--
-- How it protects data:
--   * Session lock. Every write goes through UpdateAsync and stamps { jobId, time } on the record.
--     A server that finds a fresh lock from another server waits and retries instead of loading,
--     so two servers never edit the same player at once. Locks left by crashed servers expire
--     after Config.SessionLockTimeout seconds because autosave keeps refreshing live locks.
--   * Retries with exponential backoff and jitter for every DataStore call.
--   * Schema version and migrations (Logic/DataSchema), and every loaded field is sanitised.
--   * game:BindToClose saves and releases every session before the server shuts down.
--
-- PRODUCTION NOTE: this is a compact, readable reference. For a live game, ProfileStore
-- (by loleris, see wally.toml) is recommended: it is battle-tested and also handles
-- MessagingService lock hand-off, DataStore budget throttling and more edge cases.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DataSchema = require(Shared:WaitForChild("Logic"):WaitForChild("DataSchema"))
local Signal = require(Shared:WaitForChild("Signal"))

type PlayerData = DataSchema.PlayerData

type Session = {
	data: PlayerData,
	active: boolean, -- false once another server took the lock
	saving: boolean, -- a write is in flight
	releasing: boolean, -- the final save has started; no more edits are accepted
}

local PlayerDataService = {
	Name = "PlayerDataService",
	Priority = 0,
	-- Fires (player, data) once a player's data has loaded.
	Loaded = Signal.new(),
	-- Fires (player, data) after Update changes a player's data.
	Changed = Signal.new(),
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local store: DataStore? = nil
local random = Random.new()

local function keyFor(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

-- Calls `attempt` until it succeeds or Config.DataRetries is reached, backing off between tries.
local function withRetries(label: string, attempt: () -> any): (boolean, any)
	local lastError: any = nil
	for tryNumber = 1, Config.DataRetries do
		local ok, result = pcall(attempt)
		if ok then
			return true, result
		end
		lastError = result
		if tryNumber < Config.DataRetries then
			local backoff = math.min(Config.DataRetryBase * 2 ^ (tryNumber - 1), 30)
			task.wait(backoff + random:NextNumber(0, 0.5))
		end
	end
	warn(string.format("[PlayerDataService] %s failed: %s", label, tostring(lastError)))
	return false, lastError
end

local function lockOf(record: any): any
	return if type(record) == "table" then record.lock else nil
end

-- Loads and locks the player's record. Returns nil and a kick message on failure.
local function loadProfile(player: Player): (PlayerData?, string?)
	local dataStore = store
	if not dataStore then
		-- Memory-only mode (for example Studio without API access): nothing is saved.
		return DataSchema.default(), nil
	end
	local key = keyFor(player)
	for _ = 1, Config.LockWaitAttempts do
		local blocked = false
		local loaded: PlayerData? = nil
		local failure: string? = nil
		local ok = withRetries("load " .. key, function()
			return dataStore:UpdateAsync(key, function(old: any): any
				-- UpdateAsync may call this more than once, so reset the results each time.
				blocked, loaded, failure = false, nil, nil
				local now = os.time()
				if DataSchema.lockState(lockOf(old), game.JobId, now, Config.SessionLockTimeout) == "held" then
					blocked = true
					return nil -- returning nil cancels the write
				end
				local data, reason = DataSchema.migrate(old)
				if not data then
					failure = reason
					return nil
				end
				loaded = data
				return DataSchema.newRecord(data, game.JobId, now, false)
			end)
		end)
		if not ok then
			return nil, "Roblox data servers are not responding. Please rejoin in a minute."
		end
		if failure then
			return nil, failure
		end
		if loaded then
			return loaded, nil
		end
		if blocked then
			task.wait(Config.LockRetryDelay)
		end
	end
	return nil, "Your data is still open in another server. Please rejoin in a minute."
end

-- Writes the session to the DataStore. `release` also clears the lock (used when the player leaves).
local function saveProfile(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session or not session.active then
		return false
	end
	local dataStore = store
	if not dataStore then
		return true
	end
	if session.saving then
		if not release then
			return false -- an autosave is already running
		end
		while session.saving do
			task.wait(0.1)
		end
		if not session.active then
			return false -- the save we waited for found that another server owns the lock
		end
	end
	session.saving = true
	local key = keyFor(player)
	local snapshot = DataSchema.copy(session.data)
	local lostLock = false
	local ok = withRetries("save " .. key, function()
		return dataStore:UpdateAsync(key, function(old: any): any
			local now = os.time()
			lostLock = DataSchema.lockState(lockOf(old), game.JobId, now, Config.SessionLockTimeout) == "held"
			if lostLock then
				return nil
			end
			return DataSchema.newRecord(snapshot, game.JobId, now, release)
		end)
	end)
	session.saving = false
	if lostLock then
		session.active = false
		warn("[PlayerDataService] another server took the lock for " .. key .. "; this session stops saving")
		if player.Parent == Players then
			player:Kick("Your data was opened in another server.")
		end
		return false
	end
	return ok
end

local function releaseProfile(player: Player)
	local session = sessions[player]
	if not session or session.releasing then
		return
	end
	session.releasing = true
	saveProfile(player, true)
	sessions[player] = nil
end

local function onPlayerAdded(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	local data, reason = loadProfile(player)
	loading[player] = nil
	if not data then
		player:Kick(reason or "Your data could not be loaded. Please rejoin.")
		return
	end
	sessions[player] = { data = data, active = true, saving = false, releasing = false }
	if player.Parent ~= Players then
		-- The player left while loading: give the lock back straight away.
		releaseProfile(player)
		return
	end
	PlayerDataService.Loaded:Fire(player, data)
end

local function onClose()
	for player in sessions do
		task.spawn(releaseProfile, player)
	end
	-- Roblox allows about 30 seconds after BindToClose fires.
	local deadline = os.clock() + 25
	while next(sessions) ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function autosaveLoop()
	while true do
		task.wait(Config.AutosaveInterval)
		for player, session in sessions do
			if session.active and not session.releasing then
				task.spawn(saveProfile, player, false)
			end
		end
	end
end

-- Returns the player's data, or nil if it has not loaded (or the session was lost).
-- Treat the result as read-only and change data through Update.
function PlayerDataService:Get(player: Player): PlayerData?
	local session = sessions[player]
	if session and session.active and not session.releasing then
		return session.data
	end
	return nil
end

-- Waits up to `timeout` seconds (default 30) for the player's data to load.
function PlayerDataService:WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = self:Get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return self:Get(player)
end

-- Changes the player's data in place through `mutator`, then fires Changed.
-- Returns false when the data is not loaded. `mutator` must not yield.
function PlayerDataService:Update(player: Player, mutator: (data: PlayerData) -> ()): boolean
	local data = self:Get(player)
	if not data then
		return false
	end
	mutator(data)
	self.Changed:Fire(player, data)
	return true
end

function PlayerDataService:Init()
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerDataService] DataStore unavailable, data will not save: " .. tostring(result))
	end
end

function PlayerDataService:Start()
	local dataStore = store
	if dataStore and RunService:IsStudio() then
		-- Studio blocks DataStores unless "Enable Studio Access to API Services" is on.
		local ok = pcall(function()
			return dataStore:GetAsync("StudioAccessProbe")
		end)
		if not ok then
			store = nil
			warn("[PlayerDataService] Studio has no DataStore access. Running in memory-only mode.")
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releaseProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosaveLoop)
end

return PlayerDataService
