--!strict
-- Client side of Notifications. Receives notifications from the server (and local ones from push),
-- queues them by priority and paces them: at most maxVisible are "shown" at once, each for its duration.
-- It draws nothing. Your UI connects to `onNotify` (show) and `onDismiss` (hide).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotificationsConfig = require("./NotificationsConfig")
local NotificationsLogic = require("./NotificationsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Client = {
	onNotify: Signal.Signal, -- (notification) when one should appear
	onDismiss: Signal.Signal, -- (notification) when it should disappear
	push: (self: Client, input: NotificationsLogic.Input) -> (boolean, string?), -- local notification
	dismiss: (self: Client, id: number) -> (),
	visible: (self: Client) -> { NotificationsLogic.Notification },
	destroy: (self: Client) -> (),
}

local NotificationsClient = {}

function NotificationsClient.new(overrides: { [string]: any }?): Client
	local settings: { [string]: any } = table.clone(NotificationsConfig)
	for key, value in pairs(overrides or {}) do
		settings[key] = value
	end
	local config = NotificationsLogic.resolveConfig(settings)
	local maxVisible = math.max(1, math.floor(settings.maxVisible))
	local queue = NotificationsLogic.newQueue(config)
	local trove = Trove.new()
	local onNotify = Signal.new()
	local onDismiss = Signal.new()
	trove:Add(function()
		onNotify:DisconnectAll()
		onDismiss:DisconnectAll()
	end)
	local shown: { NotificationsLogic.Notification } = {}
	local destroyed = false

	local client = {} :: Client
	client.onNotify = onNotify
	client.onDismiss = onDismiss

	local function pump()
		while not destroyed and #shown < maxVisible do
			local note = NotificationsLogic.pop(queue, os.clock())
			if note == nil then
				return
			end
			table.insert(shown, note)
			onNotify:Fire(note)
			local id = note.id
			task.delay(note.duration, function()
				client:dismiss(id)
			end)
		end
	end

	function client.dismiss(_self: Client, id: number)
		for index, note in shown do
			if note.id == id then
				table.remove(shown, index)
				onDismiss:Fire(note)
				break
			end
		end
		pump()
	end

	function client.push(_self: Client, input: NotificationsLogic.Input): (boolean, string?)
		local ok, reason = NotificationsLogic.push(queue, input, os.clock())
		pump()
		return ok, reason
	end

	function client.visible(_self: Client): { NotificationsLogic.Notification }
		return table.clone(shown)
	end

	local folder = ReplicatedStorage:WaitForChild(settings.remoteFolder)
	local remote = folder:WaitForChild("Notify") :: RemoteEvent
	trove:Connect(remote.OnClientEvent, function(payload: any)
		if type(payload) == "table" then
			-- Re-validated locally; the server's id is replaced by a local one.
			client:push(payload)
		end
	end)

	function client.destroy(_self: Client)
		destroyed = true
		trove:Clean()
	end

	return client
end

return NotificationsClient
