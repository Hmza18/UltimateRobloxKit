--!strict
-- Server adapter for Rounds. Runs the RoundsLogic loop on a timer and publishes the state as attributes
-- on ReplicatedStorage.<folderName> so any client UI can read it without a remote:
--   Phase (string), PhaseEndsAt (server time, compare with workspace:GetServerTimeNow()), Round (number),
--   Waiting (bool), Map (string), Winner (string), Reason (string), VoteOptions and VoteCounts (JSON strings).
-- Players vote with the Vote RemoteEvent in the same folder.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require("../../Util/RateLimiter")
local RoundsConfig = require("./RoundsConfig")
local RoundsLogic = require("./RoundsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local Validate = require("../../Util/Validate")

export type Options = {
	config: { [string]: any }?,
	maps: { string }?, -- map names offered in each intermission vote
	mapsPerVote: number?, -- how many random maps to offer, default all
	countPlayers: (() -> number)?, -- default: #Players:GetPlayers()
	checkWinner: ((state: RoundsLogic.State) -> any?)?, -- return a winner (team name, player, ...) to end the round
}

export type Service = {
	state: (self: Service) -> RoundsLogic.State,
	forceEnd: (self: Service, winner: any?) -> (),
	phaseChanged: Signal.Signal, -- (change: RoundsLogic.Change, state)
	destroy: (self: Service) -> (),
}

local RoundsServer = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Picks up to `count` options in random order without repeats.
local function sample(options: { string }, count: number, random: Random): { string }
	local pool = table.clone(options)
	local picked: { string } = {}
	while #picked < count and #pool > 0 do
		table.insert(picked, table.remove(pool, random:NextInteger(1, #pool)) :: string)
	end
	return picked
end

function RoundsServer.new(options: Options?): Service
	local opts: Options = options or {}
	local settings: { [string]: any } = table.clone(RoundsConfig)
	for key, value in opts.config or {} do
		settings[key] = value
	end
	local config = RoundsLogic.resolveConfig(settings)
	local random = Random.new()
	local function rng(): number
		return random:NextNumber()
	end
	local state = RoundsLogic.new(config, now())
	local trove = Trove.new()
	local phaseChanged = Signal.new()
	trove:Add(function()
		phaseChanged:DisconnectAll()
	end)

	local folder = ReplicatedStorage:FindFirstChild(settings.folderName)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = settings.folderName
		created.Parent = ReplicatedStorage
		folder = created
	end
	local stateFolder = folder :: Instance
	local voteRemote = stateFolder:FindFirstChild("Vote")
	if not voteRemote then
		local created = Instance.new("RemoteEvent")
		created.Name = "Vote"
		created.Parent = stateFolder
		voteRemote = created
	end
	local limiter = RateLimiter.new({
		capacity = settings.voteCapacity,
		refillPerSecond = settings.voteRefillPerSecond,
	})
	local checkVote = Validate.args({ Validate.string({ minLength = 1, maxLength = 50 }) })

	local function publish()
		stateFolder:SetAttribute("Phase", state.phase)
		stateFolder:SetAttribute("PhaseEndsAt", state.phaseEndsAt)
		stateFolder:SetAttribute("Round", state.round)
		stateFolder:SetAttribute("Waiting", state.waiting)
		stateFolder:SetAttribute("Map", state.map)
		local result = state.result
		stateFolder:SetAttribute("Winner", if result and result.winner ~= nil then tostring(result.winner) else nil)
		stateFolder:SetAttribute("Reason", if result then result.reason else nil)
		local vote = state.vote
		if vote then
			stateFolder:SetAttribute("VoteOptions", HttpService:JSONEncode(vote.options))
			stateFolder:SetAttribute("VoteCounts", HttpService:JSONEncode(RoundsLogic.counts(vote)))
		else
			stateFolder:SetAttribute("VoteOptions", nil)
			stateFolder:SetAttribute("VoteCounts", nil)
		end
	end

	local function openVote()
		local maps = opts.maps
		if maps and #maps > 0 then
			RoundsLogic.openVote(state, sample(maps, opts.mapsPerVote or #maps, random))
		end
	end

	local function countPlayers(): number
		if opts.countPlayers then
			return opts.countPlayers()
		end
		return #Players:GetPlayers()
	end

	local function handle(change: RoundsLogic.Change?)
		if change == nil then
			return
		end
		if change.to == "Intermission" then
			openVote()
		end
		publish()
		phaseChanged:Fire(change, state)
	end

	local input: RoundsLogic.Input = {
		now = 0,
		playerCount = 0,
		checkWinner = function(): any?
			if opts.checkWinner then
				return opts.checkWinner(state)
			end
			return nil
		end,
		rng = rng,
	}

	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed < settings.updateInterval then
			return
		end
		elapsed = 0
		local wasWaiting = state.waiting
		input.now = now()
		input.playerCount = countPlayers()
		local change = RoundsLogic.update(state, config, input)
		if change then
			handle(change)
		elseif state.waiting or wasWaiting then
			publish() -- PhaseEndsAt moves while waiting for players
		end
	end)

	trove:Connect((voteRemote :: RemoteEvent).OnServerEvent, function(player: Player, ...: any)
		local key = tostring(player.UserId)
		if not limiter:allow(key, os.clock()) or not checkVote(...) then
			return
		end
		local option = ...
		if RoundsLogic.castVote(state, key, option) then
			publish()
		end
	end)

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		local key = tostring(player.UserId)
		RoundsLogic.removeVoter(state, key)
		limiter:forget(key)
	end)

	openVote()
	publish()

	local service = {} :: Service
	service.phaseChanged = phaseChanged

	function service.state(_self: Service): RoundsLogic.State
		return state
	end

	function service.forceEnd(_self: Service, winner: any?)
		handle(RoundsLogic.forceEnd(state, config, now(), winner))
	end

	function service.destroy(_self: Service)
		trove:Clean()
	end

	return service
end

return RoundsServer
