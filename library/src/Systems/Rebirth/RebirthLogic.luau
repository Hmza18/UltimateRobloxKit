--!strict
-- Rebirths (prestige). Pure Luau. A rebirth costs a growing amount of a currency, raises a
-- permanent multiplier, and tells the server which data to reset. Supports buying several
-- rebirths at once and a "rebirth tokens" reward per rebirth.

export type Curve = {
	kind: "linear" | "exponential" | "table",
	base: number?, -- cost of the first rebirth (linear, exponential)
	step: number?, -- linear: added per rebirth
	growth: number?, -- exponential: multiplied per rebirth (default 1.5)
	values: { number }?, -- table: cost of rebirth N is values[N]; past the end the last value repeats
}

export type Config = {
	currency: string, -- currency spent
	cost: Curve,
	multiplierPerRebirth: number?, -- added to the multiplier per rebirth (default 0.5)
	maxRebirths: number?, -- default unlimited (1e6)
	reset: { string }?, -- data keys the server resets, e.g. { "Coins", "upgrades" }
	tokensPerRebirth: number?, -- reward currency amount per rebirth (default 0)
	tokenCurrency: string?, -- where tokens go
}

export type State = { rebirths: number }

export type Plan = {
	ok: boolean,
	reason: string?,
	count: number, -- rebirths bought
	cost: number, -- total currency to spend
	tokens: number, -- tokens to grant
	state: State, -- the state after the rebirths (unchanged on failure)
	reset: { string },
}

local RebirthLogic = {}

RebirthLogic.MAX_PER_PURCHASE = 1000

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Cost of a leveled curve at level `n` (1-based). Shared with Upgrades.
function RebirthLogic.curveCost(curve: Curve, n: number): number
	if curve.kind == "linear" then
		return math.floor((curve.base or 0) + (curve.step or 0) * (n - 1))
	elseif curve.kind == "exponential" then
		return math.floor((curve.base or 0) * (curve.growth or 1.5) ^ (n - 1))
	end
	local values = curve.values or {}
	if #values == 0 then
		return 0
	end
	return values[math.min(n, #values)]
end

function RebirthLogic.validateCurve(curve: Curve, label: string)
	assert(type(curve) == "table", label .. " curve must be a table")
	local kind = curve.kind
	assert(
		kind == "linear" or kind == "exponential" or kind == "table",
		label .. " curve kind must be linear, exponential or table"
	)
	if kind == "table" then
		assert(type(curve.values) == "table" and #(curve.values :: any) > 0, label .. " table curve needs values")
		for _, v in curve.values :: { number } do
			assert(isFinite(v) and v >= 0, label .. " curve values must be >= 0")
		end
	else
		assert(isFinite(curve.base) and (curve.base :: number) >= 0, label .. " curve base must be >= 0")
		assert(curve.step == nil or isFinite(curve.step), label .. " curve step must be finite")
		assert(
			curve.growth == nil or isFinite(curve.growth) and (curve.growth :: number) >= 1,
			label .. " growth must be >= 1"
		)
	end
end

function RebirthLogic.validateConfig(config: Config): Config
	assert(type(config) == "table", "config must be a table")
	assert(type(config.currency) == "string" and config.currency ~= "", "currency required")
	RebirthLogic.validateCurve(config.cost, "rebirth")
	local m = config.multiplierPerRebirth
	assert(m == nil or isFinite(m) and m >= 0, "multiplierPerRebirth must be >= 0")
	local max = config.maxRebirths
	assert(max == nil or isFinite(max) and max >= 0, "maxRebirths must be >= 0")
	local tokens = config.tokensPerRebirth
	assert(tokens == nil or isFinite(tokens) and tokens >= 0, "tokensPerRebirth must be >= 0")
	assert(tokens == nil or tokens == 0 or type(config.tokenCurrency) == "string", "tokenCurrency required with tokens")
	return config
end

function RebirthLogic.newState(): State
	return { rebirths = 0 }
end

function RebirthLogic.costOf(config: Config, state: State): number
	return RebirthLogic.curveCost(config.cost, state.rebirths + 1)
end

function RebirthLogic.multiplier(config: Config, state: State): number
	return 1 + state.rebirths * (config.multiplierPerRebirth or 0.5)
end

-- Plans `count` rebirths (default 1) against a balance. With `count = "max"` it buys as many as the
-- balance allows (up to MAX_PER_PURCHASE). The server spends `plan.cost`, resets `plan.reset`,
-- grants `plan.tokens` and stores `plan.state`.
function RebirthLogic.plan(config: Config, state: State, balance: number, count: (number | "max")?): Plan
	local fail = function(reason: string): Plan
		return { ok = false, reason = reason, count = 0, cost = 0, tokens = 0, state = state, reset = {} }
	end
	local wanted = count or 1
	local maxCount = if wanted == "max" then RebirthLogic.MAX_PER_PURCHASE else wanted :: number
	if not isFinite(maxCount) or maxCount < 1 or maxCount % 1 ~= 0 or maxCount > RebirthLogic.MAX_PER_PURCHASE then
		return fail("invalid count")
	end
	local limit = config.maxRebirths or 1e6
	local bought, total = 0, 0
	while bought < maxCount and state.rebirths + bought < limit do
		local nextCost = RebirthLogic.curveCost(config.cost, state.rebirths + bought + 1)
		if total + nextCost > balance then
			break
		end
		total += nextCost
		bought += 1
	end
	if state.rebirths >= limit then
		return fail("max rebirths")
	end
	if bought == 0 or (wanted ~= "max" and bought < maxCount) then
		return fail("not enough " .. config.currency)
	end
	return {
		ok = true,
		reason = nil,
		count = bought,
		cost = total,
		tokens = bought * (config.tokensPerRebirth or 0),
		state = { rebirths = state.rebirths + bought },
		reset = table.clone(config.reset or {}),
	}
end

function RebirthLogic.serialize(state: State): { [string]: any }
	return { v = 1, r = state.rebirths }
end

function RebirthLogic.deserialize(config: Config, raw: any): State
	local value = if type(raw) == "table" then raw.r else nil
	if not isFinite(value) or value < 0 then
		return RebirthLogic.newState()
	end
	return { rebirths = math.min(math.floor(value), config.maxRebirths or 1e6) }
end

return RebirthLogic
