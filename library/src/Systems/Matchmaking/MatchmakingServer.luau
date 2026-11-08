--!strict
-- Cross-server matchmaking adapter.
--   * Each server writes its players' tickets to a MemoryStore sorted map.
--   * One server at a time (holding a short MemoryStore lock) reads the queue, assembles matches with
--     MatchmakingLogic, reserves a server for each match and writes an assignment per ticket.
--   * Every server polls assignments for its own tickets and teleports those players, with retries.
-- Verify in the Roblox docs before shipping: MemoryStore quotas and size limits, GetRangeAsync page size,
-- TeleportService:ReserveServer / TeleportAsync behaviour, and that teleports do not work in Studio.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local MatchmakingConfig = require("./MatchmakingConfig")
local MatchmakingLogic = require("./MatchmakingLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Options = {
	placeId: number, -- the place matches are sent to
	config: { [string]: any }?, -- overrides for MatchmakingConfig
	skillOf: ((player: Player) -> number)?, -- default 1000 for everyone
	teleportData: ((match: MatchmakingLogic.Match) -> any)?, -- read in the match server with GetJoinData
}

export type Service = {
	queue: (self: Service, players: { Player }, bucket: string?) -> (boolean, string?),
	cancel: (self: Service, player: Player) -> boolean,
	isQueued: (self: Service, player: Player) -> boolean,
	matched: Signal.Signal, -- (players, assignment) when this server is about to teleport a ticket
	failed: Signal.Signal, -- (player, reason) when a teleport gives up
	destroy: (self: Service) -> (),
}

type LocalTicket = { id: string, players: { Player } }
type Retry = { attempts: number, options: TeleportOptions }

local MatchmakingServer = {}

local function withRetries(attempts: number, settings: { [string]: any }, fn: () -> any): (boolean, any)
	local lastError: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(MatchmakingLogic.backoff(attempt, settings.retryBaseDelay, settings.retryMaxDelay, math.random))
		end
	end
	return false, tostring(lastError)
end

function MatchmakingServer.new(options: Options): Service
	assert(type(options.placeId) == "number", "MatchmakingServer needs options.placeId")
	local settings: { [string]: any } = table.clone(MatchmakingConfig)
	for key, value in pairs(options.config or {}) do
		settings[key] = value
	end
	local serverId = if game.JobId ~= "" then game.JobId else "studio"
	local ticketsMap = MemoryStoreService:GetSortedMap(settings.mapName .. "Tickets")
	local assignmentsMap = MemoryStoreService:GetSortedMap(settings.mapName .. "Assignments")
	local lockMap = MemoryStoreService:GetSortedMap(settings.mapName .. "Lock")

	local trove = Trove.new()
	local matched = Signal.new()
	local failed = Signal.new()
	trove:Add(function()
		matched:DisconnectAll()
		failed:DisconnectAll()
	end)
	local running = true
	local counter = 0
	local localTickets: { [string]: LocalTicket } = {}
	local localQueue = MatchmakingLogic.newQueue(settings) -- guards against queueing a player twice
	local retries: { [Player]: Retry } = {}

	local function skillOf(player: Player): number
		local getter = options.skillOf
		if getter == nil then
			return 1000
		end
		local ok, value = pcall(getter, player)
		return if ok and type(value) == "number" then value else 1000
	end

	local service = {} :: Service
	service.matched = matched
	service.failed = failed

	function service.queue(_self: Service, group: { Player }, bucket: string?): (boolean, string?)
		counter += 1
		local ids: { string } = {}
		local total = 0
		for _, player in group do
			table.insert(ids, tostring(player.UserId))
			total += skillOf(player)
		end
		local ticketId = string.format("%s:%d", serverId, counter)
		local input = { id = ticketId, players = ids, skill = total / math.max(1, #group), bucket = bucket }
		local ok, reason = MatchmakingLogic.enqueue(localQueue, input, os.time())
		if not ok then
			return false, reason
		end
		local stored = localQueue.tickets[ticketId]
		local saved, err = pcall(function()
			ticketsMap:SetAsync(ticketId, MatchmakingLogic.encodeTicket(stored), settings.ticketTtl)
		end)
		if not saved then
			MatchmakingLogic.dequeue(localQueue, ticketId)
			return false, "queue unavailable: " .. tostring(err)
		end
		localTickets[ticketId] = { id = ticketId, players = table.clone(group) }
		return true, nil
	end

	local function removeTicket(ticketId: string)
		localTickets[ticketId] = nil
		MatchmakingLogic.dequeue(localQueue, ticketId)
		task.spawn(pcall, function()
			ticketsMap:RemoveAsync(ticketId)
		end)
	end

	function service.cancel(_self: Service, player: Player): boolean
		local ticketId = localQueue.byPlayer[tostring(player.UserId)]
		if ticketId == nil then
			return false
		end
		removeTicket(ticketId)
		return true
	end

	function service.isQueued(_self: Service, player: Player): boolean
		return localQueue.byPlayer[tostring(player.UserId)] ~= nil
	end

	-- Holds the matchmaker role while the lock is ours or free.
	local function claim(old: any): any
		local now = os.time()
		if old == nil or old.owner == serverId or old.expires < now then
			return { owner = serverId, expires = now + settings.lockTtl }
		end
		return nil -- someone else holds a live lock: leave it unchanged
	end

	local function tryLock(): boolean
		local ok, value = pcall(function()
			return lockMap:UpdateAsync("matchmaker", claim, settings.lockTtl)
		end)
		return ok and type(value) == "table" and value.owner == serverId
	end

	local function runMatchmaker()
		local ok, entries = pcall(function()
			return ticketsMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
		end)
		if not ok then
			return
		end
		local queue = MatchmakingLogic.newQueue(settings)
		for _, entry in entries do
			local ticket = MatchmakingLogic.decodeTicket(entry.value)
			if ticket then
				MatchmakingLogic.restore(queue, ticket)
			end
		end
		local now = os.time()
		for _, ticketId in MatchmakingLogic.expire(queue, now) do
			pcall(function()
				ticketsMap:RemoveAsync(ticketId)
			end)
		end
		for _, match in MatchmakingLogic.assemble(queue, now) do
			local reserved, code = withRetries(settings.teleportRetries, settings, function()
				local accessCode = TeleportService:ReserveServer(options.placeId)
				return accessCode
			end)
			if not reserved then
				warn("MatchmakingServer: ReserveServer failed: " .. tostring(code))
				continue -- the tickets stay queued and are tried again next poll
			end
			local data = if options.teleportData then options.teleportData(match) else nil
			local assignment = { placeId = options.placeId, accessCode = code, teams = match.teams, data = data }
			for _, ticketId in match.ticketIds do
				pcall(function()
					assignmentsMap:SetAsync(ticketId, assignment, 120)
					ticketsMap:RemoveAsync(ticketId)
				end)
			end
		end
	end

	local function teleport(group: { Player }, teleportOptions: TeleportOptions)
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(options.placeId, group, teleportOptions)
		end)
		if not ok then
			for _, player in group do
				failed:Fire(player, tostring(err))
			end
		end
	end

	local function deliverAssignments()
		for ticketId, ticket in table.clone(localTickets) do
			local ok, assignment = pcall(function()
				return assignmentsMap:GetAsync(ticketId)
			end)
			if ok and type(assignment) == "table" and type(assignment.accessCode) == "string" then
				removeTicket(ticketId)
				pcall(function()
					assignmentsMap:RemoveAsync(ticketId)
				end)
				local present: { Player } = {}
				for _, player in ticket.players do
					if player.Parent == Players then
						table.insert(present, player)
					end
				end
				if #present > 0 then
					local teleportOptions = Instance.new("TeleportOptions")
					teleportOptions.ReservedServerAccessCode = assignment.accessCode
					teleportOptions:SetTeleportData(assignment.data)
					for _, player in present do
						retries[player] = { attempts = 1, options = teleportOptions }
					end
					matched:Fire(present, assignment)
					teleport(present, teleportOptions)
				end
			end
		end
	end

	-- TeleportAsync can fail after it returns (full server, flood limits); retry with backoff.
	trove:Connect(TeleportService.TeleportInitFailed, function(player: Player, _result: any, message: string)
		local retry = retries[player]
		if retry == nil then
			return
		end
		if retry.attempts >= settings.teleportRetries then
			retries[player] = nil
			failed:Fire(player, message)
			return
		end
		retry.attempts += 1
		local base, cap = settings.retryBaseDelay, settings.retryMaxDelay
		local retryDelay = MatchmakingLogic.backoff(retry.attempts, base, cap, math.random)
		task.delay(retryDelay, function()
			if player.Parent == Players then
				teleport({ player }, retry.options)
			end
		end)
	end)

	-- A party is cancelled when any member leaves, so it is never matched incomplete.
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		retries[player] = nil
		service:cancel(player)
	end)

	trove:Add(task.spawn(function()
		while running do
			if tryLock() then
				runMatchmaker()
			end
			deliverAssignments()
			task.wait(settings.pollInterval)
		end
	end))

	function service.destroy(_self: Service)
		running = false
		for ticketId in table.clone(localTickets) do
			removeTicket(ticketId)
		end
		trove:Clean()
	end

	return service
end

return MatchmakingServer
