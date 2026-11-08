--!strict
-- Server adapter for LeaderboardsLogic: a global leaderboard on an OrderedDataStore (throttled
-- writes that respect the request budget, paged top-N reads, cached display names), an in-server
-- ranking and a helper that builds the leaderstats folder for the player list.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardsLogic = require("./LeaderboardsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type StatSpec = { name: string, kind: string?, value: any? }

export type Config = {
	storeName: string, -- OrderedDataStore name
	scope: string?, -- OrderedDataStore scope
	getScore: (player: Player) -> number?, -- current score, nil to skip
	keyPrefix: string?, -- key = prefix .. userId (default "")
	decimals: number?, -- digits kept by integer encoding (default 0)
	useLog: boolean?, -- store log-encoded scores for huge numbers (default false)
	ascending: boolean?, -- lowest first, for best times (default false)
	topN: number?, -- entries read, 1..100 (default 50)
	writeInterval: number?, -- seconds between writes for one player (default 60)
	flushInterval: number?, -- seconds between write batches (default 30)
	refreshInterval: number?, -- seconds between top-N reads (default 120)
	budgetReserve: number?, -- requests left for other systems (default 5)
	remoteFolderName: string?, -- default "URK_Leaderboard_" .. storeName
}

local LeaderboardsServer = {}

-- Creates (or reuses) the player's leaderstats folder with one value per spec.
-- kind is "IntValue" (default), "NumberValue" or "StringValue".
function LeaderboardsServer.leaderstats(player: Player, specs: { StatSpec }): Instance
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "leaderstats"
		created.Parent = player
		folder = created
	end
	for _, spec in specs do
		local existing = folder:FindFirstChild(spec.name)
		if existing == nil then
			local value: any = Instance.new(spec.kind or "IntValue")
			value.Name = spec.name
			if spec.value ~= nil then
				value.Value = spec.value
			end
			value.Parent = folder
		end
	end
	return folder
end

-- Sets a leaderstats value if it exists. Returns whether it did.
function LeaderboardsServer.setStat(player: Player, name: string, value: any): boolean
	local folder = player:FindFirstChild("leaderstats")
	local stat: any = folder and folder:FindFirstChild(name)
	if stat == nil then
		return false
	end
	stat.Value = value
	return true
end

function LeaderboardsServer.new(config: Config)
	local store = DataStoreService:GetOrderedDataStore(config.storeName, config.scope)
	local prefix = config.keyPrefix or ""
	local decimals = config.decimals or 0
	local useLog = config.useLog == true
	local topN = math.clamp(config.topN or 50, 1, 100)
	local reserve = config.budgetReserve or 5
	local queue = LeaderboardsLogic.newQueue(config.writeInterval or 60)
	local trove = Trove.new()
	local names: { [number]: string } = {}
	local top: { any } = {}

	local folder = Instance.new("Folder")
	folder.Name = config.remoteFolderName or "URK_Leaderboard_" .. config.storeName
	folder.Parent = ReplicatedStorage
	trove:Add(folder)
	local updatedRemote = Instance.new("RemoteEvent")
	updatedRemote.Name = "Updated"
	updatedRemote.Parent = folder
	local getRemote = Instance.new("RemoteFunction")
	getRemote.Name = "GetTop"
	getRemote.Parent = folder

	local server = {}
	server.Updated = Signal.new() -- (top)

	local function encode(score: number): number
		if useLog then
			return LeaderboardsLogic.encodeLog(score)
		end
		return LeaderboardsLogic.encode(score, decimals)
	end

	local function decode(stored: number): number
		if useLog then
			return LeaderboardsLogic.decodeLog(stored)
		end
		return LeaderboardsLogic.decode(stored, decimals)
	end

	local function nameFor(userId: number): string
		local cached = names[userId]
		if cached then
			return cached
		end
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		local resolved = if ok and type(name) == "string" then name else "#" .. tostring(userId)
		names[userId] = resolved
		return resolved
	end

	local function queuePlayer(player: Player)
		local ok, score = pcall(config.getScore, player)
		if ok and type(score) == "number" then
			LeaderboardsLogic.queueScore(queue, prefix .. tostring(player.UserId), score)
		end
	end

	-- Writes due scores, within the request budget. Returns how many were written.
	function server:flush(): number
		local requestType = Enum.DataStoreRequestType.SetIncrementSortedAsync
		local available = DataStoreService:GetRequestBudgetForRequestType(requestType)
		local writes = LeaderboardsLogic.takeBatch(queue, os.clock(), available - reserve)
		local written = 0
		for _, write in writes do
			local ok, err = pcall(function()
				store:SetAsync(write.key, encode(write.score))
			end)
			if ok then
				written += 1
			else
				LeaderboardsLogic.requeue(queue, write)
				warn("[LeaderboardsServer] write failed", err)
			end
		end
		return written
	end

	-- Reads the top N entries. Returns false when the read failed (the old list is kept).
	function server:refresh(): boolean
		local ok, page = pcall(function()
			local pages = store:GetSortedAsync(config.ascending == true, topN)
			return pages:GetCurrentPage()
		end)
		if not ok or type(page) ~= "table" then
			warn("[LeaderboardsServer] read failed", page)
			return false
		end
		local raw = LeaderboardsLogic.fromPage(page, prefix, 0)
		for _, entry in raw do
			entry.score = decode(entry.score)
			local userId = tonumber(entry.key)
			entry.name = if userId then nameFor(userId) else entry.key
		end
		top = LeaderboardsLogic.rank(raw, { descending = config.ascending ~= true })
		server.Updated:Fire(top)
		updatedRemote:FireAllClients(top)
		return true
	end

	function server:getTop(): { any }
		return top
	end

	-- Ranks the players in this server by their current score.
	function server:serverRanking(): { LeaderboardsLogic.RankedEntry }
		local entries: { LeaderboardsLogic.Entry } = {}
		for _, player in Players:GetPlayers() do
			local ok, score = pcall(config.getScore, player)
			if ok and type(score) == "number" then
				table.insert(entries, { key = tostring(player.UserId), score = score, name = player.DisplayName })
			end
		end
		return LeaderboardsLogic.rank(entries, { descending = config.ascending ~= true })
	end

	getRemote.OnServerInvoke = function()
		return top
	end

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		queuePlayer(player)
	end)

	local running = true
	trove:Add(function()
		running = false
	end)
	task.spawn(function()
		local flushEvery = config.flushInterval or 30
		local refreshEvery = config.refreshInterval or 120
		local sinceRefresh = refreshEvery
		while running do
			for _, player in Players:GetPlayers() do
				queuePlayer(player)
			end
			server:flush()
			if sinceRefresh >= refreshEvery then
				server:refresh()
				sinceRefresh = 0
			end
			task.wait(flushEvery)
			sinceRefresh += flushEvery
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			queuePlayer(player)
		end
		server:flush()
	end)

	function server:destroy()
		trove:Clean()
		server.Updated:DisconnectAll()
		getRemote.OnServerInvoke = nil
	end

	return server
end

return LeaderboardsServer
