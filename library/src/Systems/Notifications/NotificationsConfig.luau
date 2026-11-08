--!strict
-- Default settings for Notifications. Every key is optional when passed to the Notifications modules.

return {
	types = {
		info = { priority = 1, duration = 4 },
		success = { priority = 2, duration = 4 },
		reward = { priority = 3, duration = 5 },
		warning = { priority = 4, duration = 6 },
		error = { priority = 5, duration = 8 },
	},
	defaultType = "info", -- used when a notification names an unknown type
	dedupeWindow = 3, -- seconds in which the same key is shown only once
	maxQueue = 20, -- notifications waiting to be shown
	maxAge = 30, -- seconds a waiting notification stays relevant
	maxTitleLength = 60, -- characters
	maxTextLength = 200, -- characters
	maxVisible = 3, -- client: shown at the same time
	remoteFolder = "UrkNotifications", -- ReplicatedStorage folder for the Notify remote
	perPlayerCapacity = 10, -- server: notifications per player in a burst
	perPlayerRefillPerSecond = 2,
}
