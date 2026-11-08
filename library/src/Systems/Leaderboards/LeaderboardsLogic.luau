--!strict
-- Leaderboard rules. Pure Luau: sorting and ranks with tie modes, top-N, a write queue that
-- throttles OrderedDataStore updates per key and per request budget, integer score encoding
-- (OrderedDataStore stores whole numbers) and parsing of OrderedDataStore pages.

export type Entry = { key: string, score: number, name: string? }

export type RankedEntry = { key: string, score: number, name: string?, rank: number }

-- competition: 1, 2, 2, 4. dense: 1, 2, 2, 3. ordinal: 1, 2, 3, 4 (ties broken by key).
export type TieMode = "competition" | "dense" | "ordinal"

export type RankOptions = { descending: boolean?, ties: TieMode? }

export type WriteQueue = {
	minInterval: number, -- seconds between writes for one key
	pending: { [string]: number }, -- key -> newest score not written yet
	lastWrite: { [string]: number }, -- key -> time of the last write
	lastValue: { [string]: number }, -- key -> last written score
}

export type Write = { key: string, score: number }

export type PageItem = { key: string, value: number }

local LeaderboardsLogic = {}

-- Largest integer a double represents exactly.
LeaderboardsLogic.MAX_SAFE = 2 ^ 53

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Sorts entries and assigns ranks. Entries with a non-finite score or a non-string key are
-- dropped. Equal scores are ordered by key so the result is deterministic.
function LeaderboardsLogic.rank(entries: { Entry }, options: RankOptions?): { RankedEntry }
	local opts: RankOptions = options or {}
	local descending = opts.descending ~= false
	local ties: TieMode = opts.ties or "competition"
	local ranked: { RankedEntry } = {}
	for _, entry in entries do
		if type(entry) == "table" and type(entry.key) == "string" and isFinite(entry.score) then
			table.insert(ranked, { key = entry.key, score = entry.score, name = entry.name, rank = 0 })
		end
	end
	table.sort(ranked, function(a: RankedEntry, b: RankedEntry): boolean
		if a.score ~= b.score then
			if descending then
				return a.score > b.score
			end
			return a.score < b.score
		end
		return a.key < b.key
	end)
	local previousScore: number? = nil
	local previousRank = 0
	for index, entry in ranked do
		if ties == "ordinal" then
			entry.rank = index
		elseif previousScore ~= nil and entry.score == previousScore then
			entry.rank = previousRank
		elseif ties == "dense" then
			entry.rank = previousRank + 1
		else
			entry.rank = index
		end
		previousScore = entry.score
		previousRank = entry.rank
	end
	return ranked
end

-- The first `count` ranked entries (all of them when there are fewer).
function LeaderboardsLogic.top(entries: { Entry }, count: number, options: RankOptions?): { RankedEntry }
	local ranked = LeaderboardsLogic.rank(entries, options)
	local result: { RankedEntry } = {}
	for index = 1, math.min(math.max(math.floor(count), 0), #ranked) do
		table.insert(result, ranked[index])
	end
	return result
end

function LeaderboardsLogic.find(ranked: { RankedEntry }, key: string): RankedEntry?
	for _, entry in ranked do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

-- Write queue ------------------------------------------------------------------------------

function LeaderboardsLogic.newQueue(minInterval: number): WriteQueue
	assert(isFinite(minInterval) and minInterval >= 0, "minInterval must be >= 0")
	return { minInterval = minInterval, pending = {}, lastWrite = {}, lastValue = {} }
end

-- Remembers the newest score for `key`. Modifies `queue`. Non-finite scores are ignored.
function LeaderboardsLogic.queueScore(queue: WriteQueue, key: string, score: number): boolean
	if type(key) ~= "string" or not isFinite(score) then
		return false
	end
	queue.pending[key] = score
	return true
end

-- Takes up to `budget` writes that are due: the key's interval has passed and the score changed.
-- Unchanged scores leave the queue without a write. Modifies `queue`; returns writes sorted by key.
function LeaderboardsLogic.takeBatch(queue: WriteQueue, now: number, budget: number): { Write }
	local keys: { string } = {}
	for key in queue.pending do
		table.insert(keys, key)
	end
	table.sort(keys)
	local writes: { Write } = {}
	local limit = math.max(math.floor(budget), 0)
	for _, key in keys do
		local score = queue.pending[key]
		if queue.lastValue[key] == score then
			queue.pending[key] = nil
		else
			local last = queue.lastWrite[key]
			local due = last == nil or now - last >= queue.minInterval
			if due and #writes < limit then
				table.insert(writes, { key = key, score = score })
				queue.pending[key] = nil
				queue.lastWrite[key] = now
				queue.lastValue[key] = score
			end
		end
	end
	return writes
end

-- Puts a failed write back so the next batch retries it (unless a newer score arrived).
function LeaderboardsLogic.requeue(queue: WriteQueue, write: Write)
	if queue.pending[write.key] == nil then
		queue.pending[write.key] = write.score
	end
	queue.lastValue[write.key] = nil
end

function LeaderboardsLogic.forget(queue: WriteQueue, key: string)
	queue.pending[key] = nil
	queue.lastWrite[key] = nil
	queue.lastValue[key] = nil
end

-- Score encoding ---------------------------------------------------------------------------

-- Whole number for OrderedDataStore: score * 10^decimals rounded down, clamped to +/- 2^53.
function LeaderboardsLogic.encode(score: number, decimals: number?): number
	if not isFinite(score) then
		return 0
	end
	local scaled = math.floor(score * 10 ^ (decimals or 0))
	return math.clamp(scaled, -LeaderboardsLogic.MAX_SAFE, LeaderboardsLogic.MAX_SAFE)
end

function LeaderboardsLogic.decode(stored: number, decimals: number?): number
	if not isFinite(stored) then
		return 0
	end
	return stored / 10 ^ (decimals or 0)
end

-- Order-preserving log encoding for scores too large for integers (idle games). Approximate:
-- decodeLog(encodeLog(x)) is within about 0.03% of x with the default precision.
function LeaderboardsLogic.encodeLog(score: number, precision: number?): number
	if not isFinite(score) or score <= 0 then
		return 0
	end
	return math.floor(math.log10(score + 1) * (precision or 10000) + 0.5)
end

function LeaderboardsLogic.decodeLog(stored: number, precision: number?): number
	if not isFinite(stored) or stored <= 0 then
		return 0
	end
	return 10 ^ (stored / (precision or 10000)) - 1
end

-- Turns OrderedDataStore page items ({ key, value }) into entries, stripping `keyPrefix`.
-- Items with a non-string key or a non-number value are skipped.
function LeaderboardsLogic.fromPage(items: { PageItem }, keyPrefix: string?, decimals: number?): { Entry }
	local prefix = keyPrefix or ""
	local entries: { Entry } = {}
	for _, item in items do
		if type(item) == "table" and type(item.key) == "string" and isFinite(item.value) then
			local key = item.key
			if prefix ~= "" and string.sub(key, 1, #prefix) == prefix then
				key = string.sub(key, #prefix + 1)
			end
			table.insert(entries, { key = key, score = LeaderboardsLogic.decode(item.value, decimals), name = nil })
		end
	end
	return entries
end

return LeaderboardsLogic
