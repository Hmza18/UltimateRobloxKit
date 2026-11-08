--!strict
-- Default settings for Quests. Pass overrides to QuestsServer.new({ config = { ... } }); every key is optional.

return {
	dayLength = 86400, -- seconds in one quest day, used by daily quests
	dayOffset = 0, -- seconds after 00:00 UTC when the quest day starts (3600 = 01:00 UTC)
	maxActive = 20, -- most quests one player can have active at once
	remoteFolder = "UrkQuests", -- folder created in ReplicatedStorage for this system's remotes
	requestCapacity = 10, -- client requests allowed in a burst
	requestRefillPerSecond = 2, -- client requests refilled each second
}
