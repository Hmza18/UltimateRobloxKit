--!strict
-- Default settings for Rounds. Every key is optional when passed to RoundsLogic or RoundsServer.

return {
	minPlayers = 2, -- players needed before the intermission timer runs
	intermissionTime = 15, -- seconds of intermission (map voting happens here)
	startingTime = 5, -- countdown before the round begins; aborts if players drop below minPlayers
	roundTime = 180, -- seconds before the round ends on time
	endingTime = 8, -- seconds to show results
	minPlayersToContinue = 1, -- the round is abandoned when fewer players remain
	-- Server adapter
	folderName = "UrkRounds", -- ReplicatedStorage folder holding state attributes and the Vote remote
	updateInterval = 0.2, -- seconds between updates
	voteCapacity = 5, -- vote requests per player in a burst
	voteRefillPerSecond = 1,
}
