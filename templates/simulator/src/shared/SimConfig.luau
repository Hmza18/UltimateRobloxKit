--!strict
-- Simulator tuning. Clients can read this module, so keep secrets out of it.

export type Upgrade = {
	DisplayName: string,
	BaseCost: number, -- price of level 1
	Growth: number, -- each level costs this many times the previous one
	MaxLevel: number,
}

local Upgrades: { [string]: Upgrade } = {
	-- +PowerBonus coins per click per level.
	Power = { DisplayName = "Power", BaseCost = 25, Growth = 1.15, MaxLevel = 200 },
	-- +MultiplierBonus (as a fraction) to every click per level.
	Multiplier = { DisplayName = "Multiplier", BaseCost = 250, Growth = 1.35, MaxLevel = 50 },
}

local SimConfig = {
	BaseClickValue = 1,
	PowerBonus = 1,
	MultiplierBonus = 0.1,
	-- Seconds the server waits between accepted clicks. The client throttles to the same value.
	ClickCooldown = 0.15,
	Upgrades = Upgrades,
}

return table.freeze(SimConfig)
