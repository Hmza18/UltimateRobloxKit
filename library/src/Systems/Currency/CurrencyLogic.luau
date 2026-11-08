--!strict
-- Multi-currency wallets. Pure Luau. Balances are whole numbers in [0, max] per currency.
-- Every operation returns a new wallet and records an entry in a fixed-size transaction log
-- tagged with a source (earning) or sink (spending), for analytics and support.

export type CurrencyDef = {
	max: number?, -- highest balance (default MAX_BALANCE)
	initial: number?, -- starting balance for a new wallet (default 0)
}

export type Config = {
	currencies: { [string]: CurrencyDef }, -- every allowed currency name
	logSize: number?, -- entries kept in the ring buffer (default 50, 0 disables)
	overflow: ("clamp" | "reject")?, -- what add does past max (default "clamp")
}

export type Entry = {
	currency: string, -- currency name
	delta: number, -- signed change that was applied
	balance: number, -- balance after the change
	tag: string, -- source or sink, such as "quest" or "shop:Sword"
	time: number?, -- the `now` passed by the caller, if any
}

export type Log = { entries: { Entry }, head: number, count: number, capacity: number }

export type Wallet = { balances: { [string]: number }, log: Log }

export type TxResult = {
	ok: boolean, -- whether the change was applied
	reason: string?, -- why not, when ok is false
	wallet: Wallet, -- the new wallet, or the unchanged input when ok is false
	amount: number, -- amount actually applied (can be less than asked when clamping)
}

export type TransferResult = { ok: boolean, reason: string?, from: Wallet, to: Wallet, amount: number }

export type Saved = { v: number, b: { [string]: number } }

export type Summary = { sources: { [string]: { [string]: number } }, sinks: { [string]: { [string]: number } } }

local CurrencyLogic = {}

-- Doubles stop representing every integer above 2^53, so balances stay well below it.
CurrencyLogic.MAX_BALANCE = 1e15
CurrencyLogic.DEFAULT_LOG_SIZE = 50
CurrencyLogic.SAVE_VERSION = 1

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isAmount(value: any): boolean
	return isFinite(value) and value > 0 and value % 1 == 0
end

local function maxFor(config: Config, currency: string): number
	local def = config.currencies[currency]
	if def == nil or def.max == nil then
		return CurrencyLogic.MAX_BALANCE
	end
	return math.min(def.max, CurrencyLogic.MAX_BALANCE)
end

local function newLog(capacity: number): Log
	return { entries = {}, head = 0, count = 0, capacity = capacity }
end

local function pushLog(log: Log, entry: Entry): Log
	if log.capacity <= 0 then
		return log
	end
	local entries = table.clone(log.entries)
	local head = log.head % log.capacity + 1
	entries[head] = entry
	return { entries = entries, head = head, count = math.min(log.count + 1, log.capacity), capacity = log.capacity }
end

local function withBalance(wallet: Wallet, currency: string, balance: number, entry: Entry): Wallet
	local balances = table.clone(wallet.balances)
	balances[currency] = balance
	return { balances = balances, log = pushLog(wallet.log, entry) }
end

-- Checks a config once at startup. Raises an error when it is invalid.
function CurrencyLogic.validateConfig(config: Config): Config
	assert(type(config) == "table" and type(config.currencies) == "table", "config.currencies must be a table")
	for name, def in config.currencies do
		assert(type(name) == "string" and name ~= "", "currency names must be non-empty strings")
		assert(type(def) == "table", "currency " .. name .. " must be a table")
		local max, initial = def.max, def.initial
		assert(max == nil or isFinite(max) and max >= 0, "invalid max for " .. name)
		assert(initial == nil or isFinite(initial) and initial >= 0, "invalid initial for " .. name)
	end
	local logSize = config.logSize
	assert(logSize == nil or isFinite(logSize) and logSize >= 0 and logSize % 1 == 0, "invalid logSize")
	local overflow = config.overflow
	assert(overflow == nil or overflow == "clamp" or overflow == "reject", "overflow must be clamp or reject")
	return config
end

function CurrencyLogic.isCurrency(config: Config, currency: any): boolean
	return type(currency) == "string" and config.currencies[currency] ~= nil
end

function CurrencyLogic.newWallet(config: Config): Wallet
	local balances: { [string]: number } = {}
	for name, def in config.currencies do
		local initial = math.floor(def.initial or 0)
		balances[name] = math.min(initial, maxFor(config, name))
	end
	return { balances = balances, log = newLog(config.logSize or CurrencyLogic.DEFAULT_LOG_SIZE) }
end

function CurrencyLogic.balance(wallet: Wallet, currency: string): number
	return wallet.balances[currency] or 0
end

function CurrencyLogic.canAfford(wallet: Wallet, costs: { [string]: number }): boolean
	for currency, cost in costs do
		if not isFinite(cost) or cost < 0 or CurrencyLogic.balance(wallet, currency) < cost then
			return false
		end
	end
	return true
end

-- Adds a positive whole `amount`. Past the currency's max it clamps (default) or rejects.
function CurrencyLogic.add(
	config: Config,
	wallet: Wallet,
	currency: string,
	amount: number,
	source: string?,
	now: number?
): TxResult
	if not CurrencyLogic.isCurrency(config, currency) then
		return { ok = false, reason = "unknown currency", wallet = wallet, amount = 0 }
	end
	if not isAmount(amount) then
		return { ok = false, reason = "invalid amount", wallet = wallet, amount = 0 }
	end
	local current = CurrencyLogic.balance(wallet, currency)
	local room = math.max(maxFor(config, currency) - current, 0)
	if amount > room and config.overflow == "reject" then
		return { ok = false, reason = "over max", wallet = wallet, amount = 0 }
	end
	local applied = math.min(amount, room)
	if applied == 0 then
		return { ok = false, reason = "over max", wallet = wallet, amount = 0 }
	end
	local balance = current + applied
	local tag = source or "unknown"
	local entry: Entry = { currency = currency, delta = applied, balance = balance, tag = tag, time = now }
	return { ok = true, reason = nil, wallet = withBalance(wallet, currency, balance, entry), amount = applied }
end

-- Spends a positive whole `amount`. Never goes below zero: too little balance rejects the spend.
function CurrencyLogic.spend(
	config: Config,
	wallet: Wallet,
	currency: string,
	amount: number,
	sink: string?,
	now: number?
): TxResult
	if not CurrencyLogic.isCurrency(config, currency) then
		return { ok = false, reason = "unknown currency", wallet = wallet, amount = 0 }
	end
	if not isAmount(amount) then
		return { ok = false, reason = "invalid amount", wallet = wallet, amount = 0 }
	end
	local current = CurrencyLogic.balance(wallet, currency)
	if current < amount then
		return { ok = false, reason = "insufficient funds", wallet = wallet, amount = 0 }
	end
	local balance = current - amount
	local tag = sink or "unknown"
	local entry: Entry = { currency = currency, delta = -amount, balance = balance, tag = tag, time = now }
	return { ok = true, reason = nil, wallet = withBalance(wallet, currency, balance, entry), amount = amount }
end

-- Spends several currencies at once, all or nothing. Zero costs are skipped.
function CurrencyLogic.spendMany(
	config: Config,
	wallet: Wallet,
	costs: { [string]: number },
	sink: string?,
	now: number?
): TxResult
	local names: { string } = {}
	for currency, cost in costs do
		if not CurrencyLogic.isCurrency(config, currency) then
			return { ok = false, reason = "unknown currency", wallet = wallet, amount = 0 }
		end
		if not isFinite(cost) or cost < 0 or cost % 1 ~= 0 then
			return { ok = false, reason = "invalid amount", wallet = wallet, amount = 0 }
		end
		if cost > 0 then
			table.insert(names, currency)
		end
	end
	if not CurrencyLogic.canAfford(wallet, costs) then
		return { ok = false, reason = "insufficient funds", wallet = wallet, amount = 0 }
	end
	table.sort(names)
	local current = wallet
	local total = 0
	for _, currency in names do
		local result = CurrencyLogic.spend(config, current, currency, costs[currency], sink, now)
		current = result.wallet
		total += result.amount
	end
	return { ok = true, reason = nil, wallet = current, amount = total }
end

-- Moves `amount` from one wallet to another. Fails without changes when the sender cannot pay
-- or the receiver would pass the currency's max.
function CurrencyLogic.transfer(
	config: Config,
	from: Wallet,
	to: Wallet,
	currency: string,
	amount: number,
	tag: string?,
	now: number?
): TransferResult
	local label = tag or "transfer"
	local spent = CurrencyLogic.spend(config, from, currency, amount, label, now)
	if not spent.ok then
		return { ok = false, reason = spent.reason, from = from, to = to, amount = 0 }
	end
	local room = maxFor(config, currency) - CurrencyLogic.balance(to, currency)
	if amount > room then
		return { ok = false, reason = "receiver over max", from = from, to = to, amount = 0 }
	end
	local received = CurrencyLogic.add(config, to, currency, amount, label, now)
	return { ok = true, reason = nil, from = spent.wallet, to = received.wallet, amount = amount }
end

-- Log entries, newest first. `limit` defaults to every entry kept.
function CurrencyLogic.recent(wallet: Wallet, limit: number?): { Entry }
	local log = wallet.log
	local wanted = math.min(limit or log.count, log.count)
	local result: { Entry } = {}
	local index = log.head
	for _ = 1, wanted do
		table.insert(result, log.entries[index])
		index -= 1
		if index < 1 then
			index = log.capacity
		end
	end
	return result
end

-- Totals per tag and currency, split into sources (earned) and sinks (spent).
function CurrencyLogic.summarize(entries: { Entry }): Summary
	local sources: { [string]: { [string]: number } } = {}
	local sinks: { [string]: { [string]: number } } = {}
	for _, entry in entries do
		local bucket = if entry.delta >= 0 then sources else sinks
		local perTag = bucket[entry.tag]
		if perTag == nil then
			perTag = {}
			bucket[entry.tag] = perTag
		end
		perTag[entry.currency] = (perTag[entry.currency] or 0) + math.abs(entry.delta)
	end
	return { sources = sources, sinks = sinks }
end

-- Formats 1234567 as "1.23M". Values under 1000 print as whole numbers. Rounds down.
function CurrencyLogic.abbreviate(value: number): string
	if not isFinite(value) then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local amount = math.abs(value)
	local tier = 1
	while amount >= 1000 and tier < #SUFFIXES do
		amount /= 1000
		tier += 1
	end
	if tier == 1 then
		return sign .. tostring(math.floor(amount))
	end
	local text = string.format("%.2f", math.floor(amount * 100 + 1e-9) / 100)
	local trimmed = string.gsub(text, "0+$", "")
	trimmed = string.gsub(trimmed, "%.$", "")
	return sign .. trimmed .. SUFFIXES[tier]
end

-- Formats 1234567 as "1,234,567".
function CurrencyLogic.withCommas(value: number): string
	if not isFinite(value) then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local digits = string.format("%.0f", math.floor(math.abs(value)))
	local groups: { string } = {}
	local length = #digits
	local first = length % 3
	if first > 0 then
		table.insert(groups, string.sub(digits, 1, first))
	end
	for start = first + 1, length, 3 do
		table.insert(groups, string.sub(digits, start, start + 2))
	end
	return sign .. table.concat(groups, ",")
end

-- Balances only. The log is session data and is not saved.
function CurrencyLogic.serialize(wallet: Wallet): Saved
	return { v = CurrencyLogic.SAVE_VERSION, b = table.clone(wallet.balances) }
end

-- Rebuilds a wallet from untrusted data. Unknown currencies are dropped, bad values become the
-- initial balance, and balances are floored and clamped to [0, max].
function CurrencyLogic.deserialize(config: Config, raw: any): Wallet
	local wallet = CurrencyLogic.newWallet(config)
	local saved = if type(raw) == "table" and type(raw.b) == "table" then raw.b else nil
	if saved == nil then
		return wallet
	end
	for name in config.currencies do
		local value = saved[name]
		if isFinite(value) then
			wallet.balances[name] = math.clamp(math.floor(value), 0, maxFor(config, name))
		end
	end
	return wallet
end

return CurrencyLogic
