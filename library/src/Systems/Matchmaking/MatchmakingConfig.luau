--!strict
-- Default settings for Matchmaking. Every key is optional when passed to MatchmakingLogic or MatchmakingServer.

return {
	teamCount = 2, -- teams per match
	teamSize = 4, -- players per team
	baseSkillWindow = 100, -- skill difference accepted immediately
	widenPerSecond = 10, -- extra skill difference accepted per second of waiting
	maxSkillWindow = 1000, -- the window never grows past this
	fillAfter = 60, -- seconds the oldest ticket waits before a partly filled match may start
	minPlayers = 0, -- players needed for a partly filled match; 0 means full matches only
	maxWait = 300, -- seconds before a ticket is dropped from the queue
	-- Server adapter
	mapName = "UrkMatchmaking", -- MemoryStore sorted map names are derived from this
	pollInterval = 2, -- seconds between queue reads
	ticketTtl = 360, -- MemoryStore expiration for tickets, seconds
	lockTtl = 10, -- seconds the matchmaker lock lasts without renewal
	teleportRetries = 4, -- attempts for ReserveServer and TeleportAsync
	retryBaseDelay = 1, -- seconds; doubles each attempt, with jitter
	retryMaxDelay = 15,
}
