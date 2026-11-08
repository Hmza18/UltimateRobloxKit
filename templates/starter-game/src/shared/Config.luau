--!strict
-- Game-wide settings read by both server and client. Never put secrets here: every client can read this module.

local Config = {
	-- Changing the store name starts every player fresh. Old data stays in the old store.
	DataStoreName = "PlayerData_v1",
	AutosaveInterval = 60, -- seconds between background saves
	SessionLockTimeout = 300, -- seconds before a lock left by a crashed server counts as stale
	LockWaitAttempts = 5, -- load tries while another server still holds the lock
	LockRetryDelay = 6, -- seconds between those tries
	DataRetries = 4, -- attempts per DataStore call before giving up
	DataRetryBase = 1, -- first backoff in seconds, doubled after each failed attempt
	RebirthBaseCost = 1000,
	RebirthCostScale = 2.5,
	RebirthBonus = 0.5, -- each rebirth adds +50% to earnings
	-- Item ids the inventory accepts. The server rejects any other id.
	Items = { "Apple", "Gem", "Wood" },
}

return table.freeze(Config)
