--!strict
-- Server side of Notifications: send notifications to one player, a list of players or everyone.
-- Each player has a rate limit and a dedupe window, so a loop that spams the same message cannot flood
-- the client. Payloads are validated and trimmed by NotificationsLogic before they are sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotificationsConfig = require("./NotificationsConfig")
local NotificationsLogic = require("./NotificationsLogic")
local RateLimiter = require("../../Util/RateLimiter")
local Trove = require("../../Util/Trove")

export type Service = {
	notify: (self: Service, player: Player, input: NotificationsLogic.Input) -> (boolean, string?),
	notifyMany: (self: Service, players: { Player }, input: NotificationsLogic.Input) -> (),
	notifyAll: (self: Service, input: NotificationsLogic.Input) -> (),
	destroy: (self: Service) -> (),
}

local NotificationsServer = {}

function NotificationsServer.new(overrides: { [string]: any }?): Service
	local settings: { [string]: any } = table.clone(NotificationsConfig)
	for key, value in overrides or {} do
		settings[key] = value
	end
	local config = NotificationsLogic.resolveConfig(settings)
	local trove = Trove.new()
	local queues: { [Player]: NotificationsLogic.Queue } = {}
	local limiter = RateLimiter.new({
		capacity = settings.perPlayerCapacity,
		refillPerSecond = settings.perPlayerRefillPerSecond,
	})

	local folder = ReplicatedStorage:FindFirstChild(settings.remoteFolder)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = settings.remoteFolder
		created.Parent = ReplicatedStorage
		folder = created
	end
	local remote = (folder :: Instance):FindFirstChild("Notify")
	if not remote then
		local created = Instance.new("RemoteEvent")
		created.Name = "Notify"
		created.Parent = folder
		remote = created
	end
	local notifyRemote = remote :: RemoteEvent

	local service = {} :: Service

	function service.notify(_self: Service, player: Player, input: NotificationsLogic.Input): (boolean, string?)
		if player.Parent ~= Players then
			return false, "player left"
		end
		local queue = queues[player]
		if queue == nil then
			queue = NotificationsLogic.newQueue(config)
			queues[player] = queue
		end
		local now = os.clock()
		-- The server queue only validates and dedupes; display order is the client's job.
		NotificationsLogic.prune(queue, now)
		local ok, reason, note = NotificationsLogic.push(queue, input, now)
		table.clear(queue.items)
		if not ok or note == nil then
			return false, reason
		end
		if not limiter:allow(tostring(player.UserId), now) then
			return false, "rate limited"
		end
		local payload = {
			id = note.id,
			kind = note.kind,
			title = note.title,
			text = note.text,
			key = note.key,
			priority = note.priority,
			duration = note.duration,
			data = note.data,
		}
		notifyRemote:FireClient(player, payload)
		return true, nil
	end

	function service.notifyMany(self: Service, players: { Player }, input: NotificationsLogic.Input)
		for _, player in players do
			self:notify(player, input)
		end
	end

	function service.notifyAll(self: Service, input: NotificationsLogic.Input)
		self:notifyMany(Players:GetPlayers(), input)
	end

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		queues[player] = nil
		limiter:forget(tostring(player.UserId))
	end)

	function service.destroy(_self: Service)
		table.clear(queues)
		trove:Clean()
	end

	return service
end

return NotificationsServer
