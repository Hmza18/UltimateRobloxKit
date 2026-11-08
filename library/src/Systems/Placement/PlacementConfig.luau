--!strict
-- Default settings for Placement. Every key is optional when passed to the Placement modules.

return {
	gridSize = 4, -- studs per grid cell
	rotationSteps = 4, -- rotations per full turn (4 = 90 degree steps)
	maxItems = 200, -- most items on one plot
	remoteFolder = "UrkPlacement", -- ReplicatedStorage folder for remotes
	requestCapacity = 10, -- placement requests per player in a burst
	requestRefillPerSecond = 4,
	ghostTransparency = 0.5, -- client preview
}
