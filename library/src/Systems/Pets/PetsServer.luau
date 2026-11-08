--!strict
-- Server adapter for PetsLogic. Clients send intents only (Hatch, Equip, Unequip, EquipBest, Lock,
-- Delete, Fuse); the server validates shapes, rate-limits, charges egg costs through an injected
-- currency system, rolls with its own Random, and syncs the pet list back.
--
--   local pets = PetsServer.new({ pets = petsConfig, currency = currencyServer, store = adapter.section("pets"),
--       getLuck = function(player) return boosts:multiplier(player, "luck") end })

local PetsLogic = require("./PetsLogic")
local PlayerState = require("../../Util/PlayerState")
local RateLimiter = require("../../Util/RateLimiter")
local Signal = require("../../Util/Signal")
local Validate = require("../../Util/Validate")

-- CurrencyServer satisfies this (its spendMany is all or nothing).
export type CurrencyLike = {
	spendMany: (self: any, player: Player, costs: { [string]: number }, sink: string?) -> boolean,
}

export type Config = {
	pets: PetsLogic.Config,
	store: PlayerState.Store?,
	currency: CurrencyLike?, -- required when eggs have costs
	getLuck: ((player: Player) -> number)?, -- luck multiplier per hatch (default 1)
	canUseEgg: ((player: Player, egg: string) -> boolean)?, -- world/zone checks (default true)
	remoteFolderName: string?, -- default "URK_Pets"
	rateLimit: RateLimiter.Options?, -- default 8 burst, 4 per second
	random: Random?, -- default Random.new()
}

local PetsServer = {}

function PetsServer.new(config: Config)
	local petsConfig = PetsLogic.validateConfig(config.pets)
	local random = config.random or Random.new()
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 8, refillPerSecond = 4 })
	local _, remotes = PlayerState.remotes(
		config.remoteFolderName or "URK_Pets",
		{ "Hatch", "Equip", "Unequip", "EquipBest", "Lock", "Delete", "Fuse", "Sync", "Hatched" }
	)

	local server = {}
	server.Hatched = Signal.new() -- (player, egg, pets)
	server.Changed = Signal.new() -- (player, state)

	local states = PlayerState.new({
		name = "PetsServer",
		store = config.store,
		new = PetsLogic.newState,
		decode = function(raw: any): PetsLogic.State
			return PetsLogic.deserialize(petsConfig, raw)
		end,
		encode = PetsLogic.serialize,
		onLoaded = function(player: Player, state: PetsLogic.State)
			remotes.Sync:FireClient(player, PetsLogic.serialize(state))
		end,
	})

	local function commit(player: Player, state: PetsLogic.State)
		states:set(player, state)
		remotes.Sync:FireClient(player, PetsLogic.serialize(state))
		server.Changed:Fire(player, state)
	end

	function server:getState(player: Player): PetsLogic.State?
		return states:get(player)
	end

	function server:setState(player: Player, state: PetsLogic.State)
		commit(player, state)
	end

	function server:multiplier(player: Player): number
		local state = states:get(player)
		return if state then PetsLogic.totalMultiplier(petsConfig, state) else 1
	end

	function server:hatch(player: Player, egg: string, amount: number): (boolean, string?)
		local state = states:get(player)
		local def = petsConfig.eggs[egg]
		if state == nil or def == nil then
			return false, "unknown egg"
		end
		if config.canUseEgg and not config.canUseEgg(player, egg) then
			return false, "egg locked"
		end
		if PetsLogic.count(state) + amount > (petsConfig.capacity or 100) then
			return false, "inventory full"
		end
		local luck = if config.getLuck then config.getLuck(player) else 1
		local rng = function(): number
			return random:NextNumber()
		end
		-- Roll first (pure, no side effects), charge second, commit last: a failed charge changes nothing.
		local result = PetsLogic.hatch(petsConfig, state, egg, amount, rng, luck)
		if not result.ok then
			return false, result.reason
		end
		if def.cost and next(def.cost) ~= nil then
			assert(config.currency ~= nil, "PetsServer: eggs with costs need config.currency")
			local costs: { [string]: number } = {}
			for currency, price in def.cost do
				costs[currency] = price * amount
			end
			if not (config.currency :: CurrencyLike):spendMany(player, costs, "egg:" .. egg) then
				return false, "cannot afford"
			end
		end
		commit(player, result.state)
		remotes.Hatched:FireClient(player, egg, result.pets)
		server.Hatched:Fire(player, egg, result.pets)
		return true, nil
	end

	local function apply(player: Player, step: (state: PetsLogic.State) -> any)
		local state = states:get(player)
		if state == nil then
			return
		end
		local result = step(state)
		if result.ok then
			commit(player, result.state)
		end
	end

	local idCheck = Validate.string({ minLength = 1, maxLength = 16, pattern = "^%d+$" })
	local idList = Validate.array(idCheck, 50)
	local checks = {
		Hatch = Validate.args({
			Validate.string({ minLength = 1, maxLength = 64 }),
			Validate.integer(1, PetsLogic.MAX_HATCH),
		}),
		Equip = Validate.args({ idCheck }),
		Unequip = Validate.args({ idCheck }),
		EquipBest = Validate.args({}),
		Lock = Validate.args({ idCheck, Validate.boolean() }),
		Delete = Validate.args({ idList }),
		Fuse = Validate.args({ idList }),
	}

	local handlers: { [string]: (player: Player, ...any) -> () } = {
		Hatch = function(player: Player, egg: string, amount: number)
			server:hatch(player, egg, amount)
		end,
		Equip = function(player: Player, id: string)
			apply(player, function(s)
				return PetsLogic.equip(petsConfig, s, id)
			end)
		end,
		Unequip = function(player: Player, id: string)
			apply(player, function(s)
				return PetsLogic.unequip(s, id)
			end)
		end,
		EquipBest = function(player: Player)
			apply(player, function(s)
				return PetsLogic.equipBest(petsConfig, s)
			end)
		end,
		Lock = function(player: Player, id: string, locked: boolean)
			apply(player, function(s)
				return PetsLogic.setLocked(s, id, locked)
			end)
		end,
		Delete = function(player: Player, ids: { string })
			apply(player, function(s)
				return PetsLogic.delete(s, ids)
			end)
		end,
		Fuse = function(player: Player, ids: { string })
			apply(player, function(s)
				return PetsLogic.fuse(petsConfig, s, ids)
			end)
		end,
	}

	local connections: { RBXScriptConnection } = {}
	for name, handler in handlers do
		local check = checks[name]
		table.insert(
			connections,
			remotes[name].OnServerEvent:Connect(function(player: Player, ...: any)
				if limiter:allow(tostring(player.UserId), os.clock()) and check(...) then
					handler(player, ...)
				end
			end)
		)
	end

	function server:destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
		states:destroy()
		server.Hatched:DisconnectAll()
		server.Changed:DisconnectAll()
	end

	return server
end

return PetsServer
