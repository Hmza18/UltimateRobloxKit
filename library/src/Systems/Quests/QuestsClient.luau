--!strict
-- Client adapter for Quests. Mirrors the server's snapshot and sends start/abandon requests.
-- It renders nothing: connect `changed` to your own UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestsConfig = require("./QuestsConfig")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Client = {
	changed: Signal.Signal, -- (snapshot, availableIds) after every server update
	snapshot: (self: Client) -> any?, -- last QuestsLogic.serialize() shape received
	available: (self: Client) -> { string },
	start: (self: Client, questId: string) -> (),
	abandon: (self: Client, questId: string) -> (),
	destroy: (self: Client) -> (),
}

local QuestsClient = {}

function QuestsClient.new(remoteFolder: string?): Client
	local folder = ReplicatedStorage:WaitForChild(remoteFolder or QuestsConfig.remoteFolder)
	local stateRemote = folder:WaitForChild("State") :: RemoteEvent
	local requestRemote = folder:WaitForChild("Request") :: RemoteEvent
	local trove = Trove.new()
	local changed = Signal.new()
	trove:Add(function()
		changed:DisconnectAll()
	end)
	local latest: any = nil
	local availableIds: { string } = {}

	trove:Connect(stateRemote.OnClientEvent, function(snapshot: any, ids: any)
		latest = snapshot
		availableIds = if type(ids) == "table" then ids else {}
		changed:Fire(latest, availableIds)
	end)

	local client = {} :: Client
	client.changed = changed

	function client.snapshot(_self: Client): any?
		return latest
	end

	function client.available(_self: Client): { string }
		return availableIds
	end

	function client.start(_self: Client, questId: string)
		requestRemote:FireServer("start", questId)
	end

	function client.abandon(_self: Client, questId: string)
		requestRemote:FireServer("abandon", questId)
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return QuestsClient
