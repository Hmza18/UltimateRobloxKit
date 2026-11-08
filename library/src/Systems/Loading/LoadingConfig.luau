--!strict
-- Default settings for Loading. Every key is optional when passed to LoadingLogic or LoadingClient.

return {
	batchSize = 10, -- instances per ContentProvider:PreloadAsync call; smaller batches move the bar more often
	minDisplayTime = 2, -- seconds the loading screen stays up even if everything is cached
	allowSkip = true, -- offer a skip button
	skipAfter = 5, -- seconds before the skip button appears
	maxWait = 30, -- seconds before the screen closes anyway (0 = wait forever)
	displaySpeed = 1.5, -- how fast the shown bar catches up, in progress units per second
}
