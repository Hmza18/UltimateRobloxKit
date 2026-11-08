--!strict
local LeaderboardsLogic = require("../src/Systems/Leaderboards/LeaderboardsLogic")
local t = require("./lib/t")

local function entries(): { LeaderboardsLogic.Entry }
	return {
		{ key = "c", score = 50 },
		{ key = "a", score = 100 },
		{ key = "d", score = 30 },
		{ key = "b", score = 50 },
	}
end

local function ranks(ranked: { LeaderboardsLogic.RankedEntry }): { number }
	local result: { number } = {}
	for _, entry in ranked do
		table.insert(result, entry.rank)
	end
	return result
end

local function keys(ranked: { LeaderboardsLogic.RankedEntry }): { string }
	local result: { string } = {}
	for _, entry in ranked do
		table.insert(result, entry.key)
	end
	return result
end

return {
	["rank sorts descending and breaks ties by key"] = function()
		local ranked = LeaderboardsLogic.rank(entries())
		t.deepEqual(keys(ranked), { "a", "b", "c", "d" })
		t.deepEqual(ranks(ranked), { 1, 2, 2, 4 })
	end,

	["dense and ordinal tie modes"] = function()
		t.deepEqual(ranks(LeaderboardsLogic.rank(entries(), { ties = "dense" })), { 1, 2, 2, 3 })
		t.deepEqual(ranks(LeaderboardsLogic.rank(entries(), { ties = "ordinal" })), { 1, 2, 3, 4 })
	end,

	["ascending order for times"] = function()
		local ranked = LeaderboardsLogic.rank(entries(), { descending = false })
		t.deepEqual(keys(ranked), { "d", "b", "c", "a" })
		t.deepEqual(ranks(ranked), { 1, 2, 2, 4 })
	end,

	["rank drops invalid entries and does not modify the input"] = function()
		local input: { any } = {
			{ key = "ok", score = 1 },
			{ key = "nan", score = math.sqrt(-1) },
			{ key = "inf", score = math.huge },
			{ key = 5, score = 2 },
			"junk",
		}
		local ranked = LeaderboardsLogic.rank(input)
		t.equal(#ranked, 1)
		t.equal(ranked[1].key, "ok")
		t.equal(input[1].rank, nil)
		t.deepEqual(LeaderboardsLogic.rank({}), {})
	end,

	["all equal scores share rank one"] = function()
		local same = { { key = "x", score = 7 }, { key = "y", score = 7 }, { key = "z", score = 7 } }
		t.deepEqual(ranks(LeaderboardsLogic.rank(same)), { 1, 1, 1 })
		t.deepEqual(ranks(LeaderboardsLogic.rank(same, { ties = "dense" })), { 1, 1, 1 })
	end,

	["top returns at most n entries"] = function()
		t.equal(#LeaderboardsLogic.top(entries(), 2), 2)
		t.equal(#LeaderboardsLogic.top(entries(), 10), 4)
		t.equal(#LeaderboardsLogic.top(entries(), 0), 0)
		t.equal(#LeaderboardsLogic.top(entries(), -3), 0)
		t.equal(LeaderboardsLogic.top(entries(), 1)[1].key, "a")
	end,

	["find locates an entry"] = function()
		local ranked = LeaderboardsLogic.rank(entries())
		local found = LeaderboardsLogic.find(ranked, "c")
		assert(found, "missing entry")
		t.equal(found.rank, 2)
		t.equal(LeaderboardsLogic.find(ranked, "zz"), nil)
	end,

	["the write queue throttles per key"] = function()
		local queue = LeaderboardsLogic.newQueue(60)
		t.truthy(LeaderboardsLogic.queueScore(queue, "1", 10))
		t.deepEqual(LeaderboardsLogic.takeBatch(queue, 0, 10), { { key = "1", score = 10 } })
		LeaderboardsLogic.queueScore(queue, "1", 20)
		t.deepEqual(LeaderboardsLogic.takeBatch(queue, 30, 10), {})
		t.equal(queue.pending["1"], 20)
		t.deepEqual(LeaderboardsLogic.takeBatch(queue, 60, 10), { { key = "1", score = 20 } })
	end,

	["unchanged scores are dropped without a write"] = function()
		local queue = LeaderboardsLogic.newQueue(0)
		LeaderboardsLogic.queueScore(queue, "1", 5)
		LeaderboardsLogic.takeBatch(queue, 0, 10)
		LeaderboardsLogic.queueScore(queue, "1", 5)
		t.deepEqual(LeaderboardsLogic.takeBatch(queue, 100, 10), {})
		t.equal(queue.pending["1"], nil)
	end,

	["batches respect the request budget"] = function()
		local queue = LeaderboardsLogic.newQueue(0)
		for index = 1, 5 do
			LeaderboardsLogic.queueScore(queue, tostring(index), index)
		end
		local first = LeaderboardsLogic.takeBatch(queue, 0, 2)
		t.deepEqual(first, { { key = "1", score = 1 }, { key = "2", score = 2 } })
		t.equal(#LeaderboardsLogic.takeBatch(queue, 0, -4), 0)
		t.equal(#LeaderboardsLogic.takeBatch(queue, 0, 10), 3)
	end,

	["failed writes are requeued unless a newer score arrived"] = function()
		local queue = LeaderboardsLogic.newQueue(0)
		LeaderboardsLogic.queueScore(queue, "1", 5)
		local batch = LeaderboardsLogic.takeBatch(queue, 0, 1)
		LeaderboardsLogic.requeue(queue, batch[1])
		t.equal(queue.pending["1"], 5)
		t.deepEqual(LeaderboardsLogic.takeBatch(queue, 1, 1), { { key = "1", score = 5 } })
		LeaderboardsLogic.queueScore(queue, "1", 9)
		LeaderboardsLogic.requeue(queue, { key = "1", score = 5 })
		t.equal(queue.pending["1"], 9)
		LeaderboardsLogic.forget(queue, "1")
		t.equal(queue.pending["1"], nil)
		t.falsy(LeaderboardsLogic.queueScore(queue, "1", math.huge))
		t.throws(function()
			LeaderboardsLogic.newQueue(-1)
		end)
	end,

	["integer encoding keeps decimals and clamps"] = function()
		t.equal(LeaderboardsLogic.encode(12.345, 2), 1234)
		t.equal(LeaderboardsLogic.decode(1234, 2), 12.34)
		t.equal(LeaderboardsLogic.encode(7.9), 7)
		t.equal(LeaderboardsLogic.encode(1e300), 2 ^ 53)
		t.equal(LeaderboardsLogic.encode(math.sqrt(-1)), 0)
		t.equal(LeaderboardsLogic.decode(math.huge), 0)
	end,

	["log encoding preserves order and is close"] = function()
		local small = LeaderboardsLogic.encodeLog(1e6)
		local big = LeaderboardsLogic.encodeLog(1e30)
		t.truthy(big > small)
		t.equal(big % 1, 0)
		local decoded = LeaderboardsLogic.decodeLog(big)
		t.truthy(math.abs(decoded - 1e30) / 1e30 < 0.001)
		t.equal(LeaderboardsLogic.encodeLog(0), 0)
		t.equal(LeaderboardsLogic.encodeLog(-5), 0)
		t.equal(LeaderboardsLogic.decodeLog(0), 0)
	end,

	["fromPage strips prefixes and skips bad items"] = function()
		local page: { any } = {
			{ key = "Player_1", value = 300 },
			{ key = "Player_2", value = 150 },
			{ key = "Other", value = 10 },
			{ key = "Player_3", value = "x" },
			{ key = 4, value = 1 },
		}
		local result = LeaderboardsLogic.fromPage(page, "Player_", 1)
		t.equal(#result, 3)
		t.equal(result[1].key, "1")
		t.equal(result[1].score, 30)
		t.equal(result[3].key, "Other")
		t.equal(#LeaderboardsLogic.fromPage({}), 0)
	end,
}
