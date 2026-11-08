--!strict
-- One server adapter for the simulator progression loop: Rebirth, Upgrades, Worlds and Boosts share
-- one saved record per player and one currency system. Clients send intents (Rebirth, BuyUpgrade,
-- UnlockWorld); boosts are granted only by server code (products, codes, rewards).
--
--   local progression = ProgressionServer.new({ currency = currencyServer, rebirth = ..., upgrades = ...,
--       worlds = ..., boosts = ..., store = adapter.section("progression") })
--   local mult = progression:multiplier(player, "coins") -- rebirths x world x boosts

local BoostsLogic = require("../Boosts/BoostsLogic")
local PlayerState = require("../../Util/PlayerState")
local RateLimiter = require("../../Util/RateLimiter")
local RebirthLogic = require("../Rebirth/RebirthLogic")
local Signal = require("../../Util/Signal")
local UpgradesLogic = require("../Upgrades/UpgradesLogic")
local Validate = require("../../Util/Validate")
local WorldsLogic = require("../Worlds/WorldsLogic")

-- CurrencyServer satisfies this.
export type CurrencyLike = {
	balance: (self: any, player: Player, currency: string) -> number,
	spendMany: (self: any, player: Player, costs: { [string]: number }, sink: string?) -> boolean,
	add: (self: any, player: Player, currency: string, amount: number, source: string?) -> any,
	getWallet: (self: any, player: Player) -> any,
	setWallet: (self: any, player: Player, wallet: any) -> (),
}

export type Config = {
	currency: CurrencyLike,
	rebirth: RebirthLogic.Config?,
	upgrades: UpgradesLogic.Config?,
	worlds: WorldsLogic.Config?,
	boosts: BoostsLogic.Config?,
	store: PlayerState.Store?,
	-- Called after a rebirth with plan.reset (e.g. reset currencies, inventories). Required for
	-- resetting anything outside this module.
	onRebirthReset: ((player: Player, keys: { string }) -> ())?,
	getStats: ((player: Player) -> { [string]: number })?, -- for world stat requirements
	remoteFolderName: string?, -- default "URK_Progression"
	rateLimit: RateLimiter.Options?,
}

export type State = {
	rebirth: RebirthLogic.State,
	upgrades: UpgradesLogic.State,
	worlds: WorldsLogic.State?,
	boosts: BoostsLogic.State,
}

local ProgressionServer = {}

function ProgressionServer.new(config: Config)
	local rebirthCfg = if config.rebirth then RebirthLogic.validateConfig(config.rebirth) else nil
	local upgradesCfg = if config.upgrades then UpgradesLogic.validateConfig(config.upgrades) else nil
	local worldsCfg = if config.worlds then WorldsLogic.validateConfig(config.worlds) else nil
	local boostsCfg = if config.boosts then BoostsLogic.validateConfig(config.boosts) else nil
	local currency = config.currency
	local limiter = RateLimiter.new(config.rateLimit or { capacity = 6, refillPerSecond = 3 })
	local _, remotes = PlayerState.remotes(
		config.remoteFolderName or "URK_Progression",
		{ "Rebirth", "BuyUpgrade", "UnlockWorld", "Sync" }
	)

	local server = {}
	server.Rebirthed = Signal.new() -- (player, count)
	server.Upgraded = Signal.new() -- (player, name, level)
	server.WorldUnlocked = Signal.new() -- (player, world)

	local function fresh(): State
		return {
			rebirth = RebirthLogic.newState(),
			upgrades = UpgradesLogic.newState(),
			worlds = if worldsCfg then WorldsLogic.newState(worldsCfg) else nil,
			boosts = BoostsLogic.newState(),
		}
	end

	local function encode(state: State): any
		return {
			r = RebirthLogic.serialize(state.rebirth),
			u = UpgradesLogic.serialize(state.upgrades),
			w = if worldsCfg and state.worlds then WorldsLogic.serialize(worldsCfg, state.worlds) else nil,
			b = if boostsCfg then BoostsLogic.serialize(boostsCfg, state.boosts, os.time()) else nil,
		}
	end

	local function decode(raw: any): State
		local state = fresh()
		if type(raw) ~= "table" then
			return state
		end
		if rebirthCfg then
			state.rebirth = RebirthLogic.deserialize(rebirthCfg, raw.r)
		end
		if upgradesCfg then
			state.upgrades = UpgradesLogic.deserialize(upgradesCfg, raw.u)
		end
		if worldsCfg then
			state.worlds = WorldsLogic.deserialize(worldsCfg, raw.w)
		end
		if boostsCfg then
			state.boosts = BoostsLogic.deserialize(boostsCfg, raw.b, os.time())
		end
		return state
	end

	local function publish(player: Player, state: State)
		player:SetAttribute("Rebirths", state.rebirth.rebirths)
		remotes.Sync:FireClient(player, encode(state))
	end

	local states = PlayerState.new({
		name = "ProgressionServer",
		store = config.store,
		new = fresh,
		decode = decode,
		encode = encode,
		onLoaded = publish,
	})

	local function commit(player: Player, state: State)
		states:set(player, state)
		publish(player, state)
	end

	function server:getState(player: Player): State?
		return states:get(player)
	end

	-- Combined multiplier for a stat: rebirth x best unlocked world x active boosts.
	function server:multiplier(player: Player, stat: string): number
		local state = states:get(player)
		if state == nil then
			return 1
		end
		local total = 1
		if rebirthCfg then
			total *= RebirthLogic.multiplier(rebirthCfg, state.rebirth)
		end
		if worldsCfg and state.worlds then
			total *= WorldsLogic.multiplier(worldsCfg, state.worlds)
		end
		if boostsCfg then
			total *= BoostsLogic.multiplier(boostsCfg, state.boosts, stat, os.time())
		end
		return total
	end

	function server:upgradeValue(player: Player, name: string): number?
		local state = states:get(player)
		if state == nil or upgradesCfg == nil then
			return nil
		end
		return UpgradesLogic.value(upgradesCfg, state.upgrades, name)
	end

	function server:rebirth(player: Player, count: (number | "max")?): (boolean, string?)
		local state = states:get(player)
		if state == nil or rebirthCfg == nil then
			return false, "rebirth disabled"
		end
		local cfg = rebirthCfg :: RebirthLogic.Config
		local plan = RebirthLogic.plan(cfg, state.rebirth, currency:balance(player, cfg.currency), count)
		if not plan.ok then
			return false, plan.reason
		end
		if not currency:spendMany(player, { [cfg.currency] = plan.cost }, "rebirth") then
			return false, "cannot afford"
		end
		local nextState = table.clone(state)
		nextState.rebirth = plan.state
		if upgradesCfg and table.find(plan.reset, "upgrades") then
			nextState.upgrades = UpgradesLogic.afterRebirth(upgradesCfg, state.upgrades)
		end
		commit(player, nextState)
		if config.onRebirthReset then
			config.onRebirthReset(player, plan.reset)
		end
		if plan.tokens > 0 and cfg.tokenCurrency then
			currency:add(player, cfg.tokenCurrency, plan.tokens, "rebirth")
		end
		server.Rebirthed:Fire(player, plan.count)
		return true, nil
	end

	function server:buyUpgrade(player: Player, name: string, count: (number | "max")?): (boolean, string?)
		local state = states:get(player)
		if state == nil or upgradesCfg == nil then
			return false, "upgrades disabled"
		end
		local def = (upgradesCfg :: UpgradesLogic.Config).upgrades[name]
		if def == nil then
			return false, "unknown upgrade"
		end
		local balance = currency:balance(player, def.currency)
		local plan = UpgradesLogic.buy(upgradesCfg :: UpgradesLogic.Config, state.upgrades, name, balance, count)
		if not plan.ok then
			return false, plan.reason
		end
		if plan.cost > 0 and not currency:spendMany(player, { [def.currency] = plan.cost }, "upgrade:" .. name) then
			return false, "cannot afford"
		end
		local nextState = table.clone(state)
		nextState.upgrades = plan.state
		commit(player, nextState)
		server.Upgraded:Fire(player, name, UpgradesLogic.level(plan.state, name))
		return true, nil
	end

	function server:unlockWorld(player: Player, world: string): (boolean, string?)
		local state = states:get(player)
		if state == nil or worldsCfg == nil or state.worlds == nil then
			return false, "worlds disabled"
		end
		local wallet = currency:getWallet(player)
		local context: WorldsLogic.Context = {
			balances = if wallet then wallet.balances else {},
			rebirths = state.rebirth.rebirths,
			stats = if config.getStats then config.getStats(player) else nil,
		}
		local check, nextWorlds =
			WorldsLogic.unlock(worldsCfg :: WorldsLogic.Config, state.worlds :: WorldsLogic.State, world, context)
		if not check.ok then
			return false, check.reason
		end
		if next(check.cost) ~= nil and not currency:spendMany(player, check.cost, "world:" .. world) then
			return false, "cannot afford"
		end
		local nextState = table.clone(state)
		nextState.worlds = nextWorlds
		commit(player, nextState)
		server.WorldUnlocked:Fire(player, world)
		return true, nil
	end

	function server:isWorldUnlocked(player: Player, world: string): boolean
		local state = states:get(player)
		if state == nil or worldsCfg == nil or state.worlds == nil then
			return false
		end
		return WorldsLogic.isUnlocked(worldsCfg :: WorldsLogic.Config, state.worlds :: WorldsLogic.State, world)
	end

	-- Server-only: grant a boost (after a purchase, a code, a reward).
	function server:grantBoost(player: Player, kind: string, count: number?): (boolean, string?)
		local state = states:get(player)
		if state == nil or boostsCfg == nil then
			return false, "boosts disabled"
		end
		local result = BoostsLogic.activate(boostsCfg :: BoostsLogic.Config, state.boosts, kind, os.time(), count)
		if not result.ok then
			return false, result.reason
		end
		local nextState = table.clone(state)
		nextState.boosts = result.state
		commit(player, nextState)
		return true, nil
	end

	local nameCheck = Validate.string({ minLength = 1, maxLength = 64 })
	local countCheck = Validate.optional(function(value: any): (boolean, string?)
		if value == "max" then
			return true, nil
		end
		return Validate.integer(1, 1000)(value)
	end)
	local checks = {
		Rebirth = Validate.args({ countCheck }),
		BuyUpgrade = Validate.args({ nameCheck, countCheck }),
		UnlockWorld = Validate.args({ nameCheck }),
	}
	local handlers: { [string]: (player: Player, ...any) -> () } = {
		Rebirth = function(player: Player, count: any)
			server:rebirth(player, count)
		end,
		BuyUpgrade = function(player: Player, name: string, count: any)
			server:buyUpgrade(player, name, count)
		end,
		UnlockWorld = function(player: Player, world: string)
			server:unlockWorld(player, world)
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
		server.Rebirthed:DisconnectAll()
		server.Upgraded:DisconnectAll()
		server.WorldUnlocked:DisconnectAll()
	end

	return server
end

return ProgressionServer
