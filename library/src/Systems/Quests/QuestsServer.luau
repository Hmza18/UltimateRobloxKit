--!strict
-- Server adapter for Quests. Owns every player's quest state, turns game events into progress,
-- grants rewards through a callback and saves through an injected store.
-- Clients can only ask to start or abandon a quest; progress comes from server code calling recordEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestsLogic = require("./QuestsLogic")
local QuestsConfig = require("./QuestsConfig")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Store = {
	load: (player: Player) -> any?, -- may yield; returns saved data or nil
	save: (player: Player, data: any) -> (), -- may yield
}

export type Options = {
	definitions: { QuestsLogic.QuestDef },
	grantReward: (player: Player, questId: string, rewards: any) -> (),
	store: Store?,
	config: { [string]: any }?,
	autoStart: { string }?, -- quests started for every player after their data loads
	clock: (() -> number)?, -- wall clock in seconds, default os.time (daily quests need a real date)
}

export type Service = {
	recordEvent: (self: Service, player: Player, event: QuestsLogic.Event) -> QuestsLogic.EventResult,
	start: (self: Service, player: Player, questId: string) -> (boolean, string?),
	abandon: (self: Service, player: Player, questId: string) -> boolean,
	getState: (self: Service, player: Player) -> QuestsLogic.PlayerState?,
	completed: Signal.Signal, -- (player, questId)
	progressed: Signal.Signal, -- (player, questId)
	destroy: (self: Service) -> (),
}

local QuestsServer = {}

local function getRemote(folder: Instance, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function QuestsServer.new(options: Options): Service
	assert(type(options.grantReward) == "function", "QuestsServer needs options.grantReward")
	local settings: { [string]: any } = table.clone(QuestsConfig)
	for key, value in pairs(options.config or {}) do
		settings[key] = value
	end
	local catalog = QuestsLogic.newCatalog(options.definitions)
	local config = QuestsLogic.resolveConfig(settings)
	local clock = options.clock or os.time
	local trove = Trove.new()
	local states: { [Player]: QuestsLogic.PlayerState } = {}
	local completedSignal = Signal.new()
	local progressedSignal = Signal.new()
	trove:Add(function()
		completedSignal:DisconnectAll()
		progressedSignal:DisconnectAll()
	end)
	local limiter = RateLimiter.new({
		capacity = settings.requestCapacity,
		refillPerSecond = settings.requestRefillPerSecond,
	})

	local folder = ReplicatedStorage:FindFirstChild(settings.remoteFolder)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = settings.remoteFolder
		created.Parent = ReplicatedStorage
		folder = created
	end
	local stateRemote = getRemote(folder :: Instance, "State")
	local requestRemote = getRemote(folder :: Instance, "Request")
	local checkRequest = Validate.args({
		Validate.oneOf({ "start", "abandon" }),
		Validate.string({ minLength = 1, maxLength = 64 }),
	})

	local function sync(player: Player)
		local state = states[player]
		if state then
			stateRemote:FireClient(player, QuestsLogic.serialize(state), QuestsLogic.available(catalog, state, clock()))
		end
	end

	local function grant(player: Player, questIds: { string })
		for _, questId in questIds do
			local definition = catalog.byId[questId]
			local ok, err = pcall(options.grantReward, player, questId, definition and definition.rewards)
			if not ok then
				warn("QuestsServer: grantReward failed for " .. questId .. ": " .. tostring(err))
			end
			completedSignal:Fire(player, questId)
		end
	end

	local service = {} :: Service

	function service.recordEvent(_self: Service, player: Player, event: QuestsLogic.Event): QuestsLogic.EventResult
		local state = states[player]
		if not state then
			return { updated = {}, completed = {}, started = {} }
		end
		local result = QuestsLogic.handleEvent(catalog, state, event, clock(), config)
		for _, questId in result.updated do
			progressedSignal:Fire(player, questId)
		end
		grant(player, result.completed)
		if #result.updated > 0 or #result.started > 0 then
			sync(player)
		end
		return result
	end

	function service.start(_self: Service, player: Player, questId: string): (boolean, string?)
		local state = states[player]
		if not state then
			return false, "not loaded"
		end
		local ok, reason = QuestsLogic.start(catalog, state, questId, clock(), config)
		if ok then
			sync(player)
		end
		return ok, reason
	end

	function service.abandon(_self: Service, player: Player, questId: string): boolean
		local state = states[player]
		local removed = state ~= nil and QuestsLogic.abandon(state, questId)
		if removed then
			sync(player)
		end
		return removed
	end

	function service.getState(_self: Service, player: Player): QuestsLogic.PlayerState?
		return states[player]
	end

	service.completed = completedSignal
	service.progressed = progressedSignal

	local function onPlayerAdded(player: Player)
		local saved = nil
		if options.store then
			local store = options.store
			local ok, data = pcall(store.load, player)
			if ok then
				saved = data
			else
				warn("QuestsServer: load failed for " .. player.Name .. ": " .. tostring(data))
			end
		end
		if player.Parent ~= Players then
			return
		end
		local state = QuestsLogic.deserialize(saved, catalog)
		states[player] = state
		for _, questId in ipairs(options.autoStart or {}) do
			QuestsLogic.start(catalog, state, questId, clock(), config)
		end
		sync(player)
	end

	local function save(player: Player)
		local state = states[player]
		if state and options.store then
			local ok, err = pcall(options.store.save, player, QuestsLogic.serialize(state))
			if not ok then
				warn("QuestsServer: save failed for " .. player.Name .. ": " .. tostring(err))
			end
		end
	end

	trove:Connect(requestRemote.OnServerEvent, function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			return
		end
		if not checkRequest(...) then
			return
		end
		local action, questId = ...
		if action == "start" then
			service:start(player, questId)
		else
			service:abandon(player, questId)
		end
	end)
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		save(player)
		states[player] = nil
		limiter:forget(tostring(player.UserId))
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	function service.destroy(_self: Service)
		for player in states do
			save(player)
		end
		table.clear(states)
		trove:Clean()
	end

	return service
end

return QuestsServer
