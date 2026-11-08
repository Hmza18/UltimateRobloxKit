--!strict
-- Client reader for Rounds. Reads the attributes RoundsServer publishes, fires `changed` when any of
-- them change and sends map votes. Rendering is up to your UI.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundsConfig = require("./RoundsConfig")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Snapshot = {
	phase: string?,
	phaseEndsAt: number?,
	round: number,
	waiting: boolean,
	map: string?,
	winner: string?,
	reason: string?,
	voteOptions: { string },
	voteCounts: { [string]: number },
}

export type Client = {
	changed: Signal.Signal, -- (snapshot)
	snapshot: (self: Client) -> Snapshot,
	timeLeft: (self: Client) -> number, -- seconds left in the current phase
	vote: (self: Client, option: string) -> (),
	destroy: (self: Client) -> (),
}

local RoundsClient = {}

local function decode(value: any, fallback: any): any
	if type(value) ~= "string" then
		return fallback
	end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, value)
	return if ok then result else fallback
end

function RoundsClient.new(folderName: string?): Client
	local folder = ReplicatedStorage:WaitForChild(folderName or RoundsConfig.folderName)
	local voteRemote = folder:WaitForChild("Vote") :: RemoteEvent
	local trove = Trove.new()
	local changed = Signal.new()
	trove:Add(function()
		changed:DisconnectAll()
	end)

	local function read(): Snapshot
		return {
			phase = folder:GetAttribute("Phase"),
			phaseEndsAt = folder:GetAttribute("PhaseEndsAt"),
			round = folder:GetAttribute("Round") or 0,
			waiting = folder:GetAttribute("Waiting") == true,
			map = folder:GetAttribute("Map"),
			winner = folder:GetAttribute("Winner"),
			reason = folder:GetAttribute("Reason"),
			voteOptions = decode(folder:GetAttribute("VoteOptions"), {}),
			voteCounts = decode(folder:GetAttribute("VoteCounts"), {}),
		}
	end

	local current = read()
	trove:Connect(folder.AttributeChanged, function()
		current = read()
		changed:Fire(current)
	end)

	local client = {} :: Client
	client.changed = changed

	function client.snapshot(_self: Client): Snapshot
		return current
	end

	function client.timeLeft(_self: Client): number
		local endsAt = current.phaseEndsAt
		if endsAt == nil then
			return 0
		end
		return math.max(0, endsAt - workspace:GetServerTimeNow())
	end

	function client.vote(_self: Client, option: string)
		voteRemote:FireServer(option)
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return RoundsClient
