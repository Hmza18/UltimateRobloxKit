--!strict
local AnalyticsLogic = require("../src/Systems/Analytics/AnalyticsLogic")
local t = require("./lib/t")

local function newState(config: AnalyticsLogic.Config?): AnalyticsLogic.State
	return AnalyticsLogic.new(config, 0)
end

local function economy(overrides: { [string]: any }?): { [string]: any }
	local event: { [string]: any } = {
		kind = "economy",
		userId = 1,
		flow = "Source",
		currency = "Coins",
		amount = 10,
		balance = 110,
		transaction = "Gameplay",
	}
	for key, value in overrides or {} do
		event[key] = value
	end
	return event
end

local function funnel(userId: number, step: number, sessionId: string?): { [string]: any }
	return { kind = "funnel", userId = userId, funnel = "Shop", step = step, sessionId = sessionId }
end

local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[index] or 0
	end
end

return {
	["validateConfig applies defaults"] = function()
		local settings = AnalyticsLogic.validateConfig(nil)
		t.equal(settings.maxSteps, 100)
		t.equal(settings.maxCustomNames, 100)
		t.equal(settings.maxFunnels, 10)
		t.equal(settings.maxCurrencies, 10)
		t.equal(settings.batchSize, 20)
		t.equal(settings.dedupeWindow, 1)
		t.equal(settings.rejectLongNumbers, true)
		t.equal(settings.coalesceCustom, false)
		t.equal(settings.sessionPrefix, "s")
	end,

	["validateConfig rejects bad values"] = function()
		t.throws(function()
			AnalyticsLogic.validateConfig({ batchSize = 0 })
		end)
		t.throws(function()
			AnalyticsLogic.validateConfig({ sampleRates = { custom = 1.5 } })
		end)
		t.throws(function()
			AnalyticsLogic.validateConfig({ sampleRates = { unknown = 0.5 } })
		end)
		t.throws(function()
			AnalyticsLogic.validateConfig({ rate = { capacity = 0, refillPerSecond = 1 } })
		end)
		t.throws(function()
			AnalyticsLogic.validateConfig({ dedupeWindow = -1 })
		end)
	end,

	["a valid economy event is queued and flushed to the sink"] = function()
		local state = newState()
		local ok, reason = AnalyticsLogic.track(state, economy(), 1)
		t.truthy(ok, reason)
		t.equal(#state.queue, 1)
		local sink = AnalyticsLogic.memorySink()
		local sent = AnalyticsLogic.flush(state, sink, 2)
		t.equal(sent, 1)
		t.equal(#state.queue, 0)
		t.equal(sink.batches, 1)
		local event = sink.events[1]
		t.equal(event.kind, "economy")
		t.equal(event.flow, "Source")
		t.equal(event.amount, 10)
		t.equal(event.balance, 110)
		t.equal(event.time, 1)
	end,

	["economy events check flow, amount and balance"] = function()
		local state = newState({ dedupeWindow = 0 })
		local _, flowReason = AnalyticsLogic.track(state, economy({ flow = "Both" }), 1)
		t.equal(flowReason, "invalid flow")
		local _, zero = AnalyticsLogic.track(state, economy({ amount = 0 }), 1)
		t.equal(zero, "invalid amount")
		local _, negative = AnalyticsLogic.track(state, economy({ amount = -5 }), 1)
		t.equal(negative, "invalid amount")
		local _, nan = AnalyticsLogic.track(state, economy({ amount = 0 / 0 }), 1)
		t.equal(nan, "invalid amount")
		local _, huge = AnalyticsLogic.track(state, economy({ amount = math.huge }), 1)
		t.equal(huge, "invalid amount")
		local _, balance = AnalyticsLogic.track(state, economy({ balance = -1 }), 1)
		t.equal(balance, "invalid balance")
		local _, tooBig = AnalyticsLogic.track(state, economy({ amount = 1e13 }), 1)
		t.equal(tooBig, "invalid amount")
		t.equal(#state.queue, 0)
	end,

	["names must be short, plain text"] = function()
		local state = newState({ dedupeWindow = 0 })
		local _, empty = AnalyticsLogic.track(state, economy({ currency = "" }), 1)
		t.equal(empty, "invalid currency")
		local _, long = AnalyticsLogic.track(state, economy({ currency = string.rep("a", 51) }), 1)
		t.equal(long, "invalid currency")
		local _, symbol = AnalyticsLogic.track(state, economy({ transaction = "Shop<script>" }), 1)
		t.equal(symbol, "invalid transaction")
		local _, email = AnalyticsLogic.track(state, economy({ sku = "me@example.com" }), 1)
		t.equal(email, "invalid sku")
		local _, trailing = AnalyticsLogic.track(state, economy({ currency = "Coins " }), 1)
		t.equal(trailing, "invalid currency")
		local okPlain = AnalyticsLogic.track(state, economy({ sku = "Sword: Iron-2" }), 1)
		t.truthy(okPlain)
	end,

	["long digit runs are rejected as possible personal data"] = function()
		local state = newState()
		local _, reason = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "Call5551234567" }, 1)
		t.equal(reason, "possible personal data")
		local withId = { kind = "custom", userId = 1, name = "Join", fields = { "user 123456789" } }
		local _, fieldReason = AnalyticsLogic.track(state, withId, 1)
		t.equal(fieldReason, "possible personal data")
		local relaxed = newState({ rejectLongNumbers = false })
		t.truthy(AnalyticsLogic.track(relaxed, { kind = "custom", userId = 1, name = "Score1234567" }, 1))
	end,

	["invalid events, kinds and users are rejected"] = function()
		local state = newState()
		local _, notTable = AnalyticsLogic.track(state, "economy", 1)
		t.equal(notTable, "invalid event")
		local _, kind = AnalyticsLogic.track(state, { kind = "purchase", userId = 1 }, 1)
		t.equal(kind, "invalid kind")
		local _, user = AnalyticsLogic.track(state, economy({ userId = 1.5 }), 1)
		t.equal(user, "invalid user")
		local _, zeroUser = AnalyticsLogic.track(state, economy({ userId = 0 }), 1)
		t.equal(zeroUser, "invalid user")
		t.truthy(AnalyticsLogic.track(state, economy({ userId = -1 }), 1), "Studio test players have negative ids")
	end,

	["track errors on a non-finite now"] = function()
		local state = newState()
		t.throws(function()
			AnalyticsLogic.track(state, economy(), 0 / 0)
		end)
	end,

	["custom fields accept arrays or keyed tables and convert values"] = function()
		local settings = AnalyticsLogic.validateConfig(nil)
		local fields = AnalyticsLogic.normalizeFields(settings, { "Warrior", 10, true })
		t.deepEqual(fields, { CustomField01 = "Warrior", CustomField02 = "10", CustomField03 = "true" })
		local keyed = AnalyticsLogic.normalizeFields(settings, { CustomField02 = "Mage" })
		t.deepEqual(keyed, { CustomField02 = "Mage" })
		local none, noReason = AnalyticsLogic.normalizeFields(settings, {})
		t.equal(none, nil)
		t.equal(noReason, nil)
	end,

	["custom fields reject unknown keys, a fourth field and bad values"] = function()
		local settings = AnalyticsLogic.validateConfig(nil)
		local _, unknown = AnalyticsLogic.normalizeFields(settings, { Class = "Mage" })
		t.equal(unknown, "invalid fields")
		local _, fourth = AnalyticsLogic.normalizeFields(settings, { "a", "b", "c", "d" })
		t.equal(fourth, "invalid fields")
		local _, both = AnalyticsLogic.normalizeFields(settings, { "a", CustomField01 = "b" })
		t.equal(both, "invalid fields")
		local _, nested = AnalyticsLogic.normalizeFields(settings, { { "x" } })
		t.equal(nested, "invalid fields")
		local _, long = AnalyticsLogic.normalizeFields(settings, { string.rep("x", 51) })
		t.equal(long, "invalid fields")
		local _, notTable = AnalyticsLogic.normalizeFields(settings, "Mage")
		t.equal(notTable, "invalid fields")
	end,

	["custom events default their value to 1 and check range"] = function()
		local state = newState({ dedupeWindow = 0 })
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "MonsterDefeated" }, 1))
		t.equal(state.queue[1].value, 1)
		local _, reason = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "X", value = 1e13 }, 1)
		t.equal(reason, "invalid value")
		local _, nanReason = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "X", value = 0 / 0 }, 1)
		t.equal(nanReason, "invalid value")
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "Ratio", value = -2.5 }, 1))
	end,

	["progression events check status and level"] = function()
		local state = newState({ dedupeWindow = 0 })
		local start = { kind = "progression", userId = 1, path = "World1", status = "Start", level = 1 }
		t.truthy(AnalyticsLogic.track(state, start, 1))
		local badStatus = { kind = "progression", userId = 1, path = "World1", status = "Skip", level = 1 }
		local _, statusReason = AnalyticsLogic.track(state, badStatus, 1)
		t.equal(statusReason, "invalid status")
		local badLevel = { kind = "progression", userId = 1, path = "World1", status = "Fail", level = 0 }
		local _, levelReason = AnalyticsLogic.track(state, badLevel, 1)
		t.equal(levelReason, "invalid level")
		local fraction = { kind = "progression", userId = 1, path = "World1", status = "Fail", level = 1.5 }
		local _, fractionReason = AnalyticsLogic.track(state, fraction, 1)
		t.equal(fractionReason, "invalid level")
	end,

	["funnel steps must start at 1 and go up one at a time"] = function()
		local state = newState()
		local _, notStarted = AnalyticsLogic.track(state, funnel(1, 2), 1)
		t.equal(notStarted, "funnel not started")
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 1))
		local _, skipped = AnalyticsLogic.track(state, funnel(1, 3), 2)
		t.equal(skipped, "skipped step")
		t.truthy(AnalyticsLogic.track(state, funnel(1, 2), 3))
		local _, duplicate = AnalyticsLogic.track(state, funnel(1, 2), 10)
		t.equal(duplicate, "duplicate step")
		local _, backwards = AnalyticsLogic.track(state, funnel(1, 1), 10)
		t.equal(backwards, nil, "step 1 after step 2 restarts the funnel")
		t.equal(#state.queue, 3)
	end,

	["funnel steps are tracked per player"] = function()
		local state = newState()
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 1))
		local _, other = AnalyticsLogic.track(state, funnel(2, 2), 1)
		t.equal(other, "funnel not started")
		t.truthy(AnalyticsLogic.track(state, funnel(2, 1), 1))
		t.truthy(AnalyticsLogic.track(state, funnel(2, 2), 2))
		t.equal((AnalyticsLogic.funnelProgress(state, 1, "Shop") :: AnalyticsLogic.Progress).step, 1)
		t.equal((AnalyticsLogic.funnelProgress(state, 2, "Shop") :: AnalyticsLogic.Progress).step, 2)
	end,

	["funnel sessions get generated ids that carry to later steps"] = function()
		local state = newState()
		t.truthy(AnalyticsLogic.track(state, funnel(7, 1), 1))
		t.truthy(AnalyticsLogic.track(state, funnel(7, 2), 2))
		local first = state.queue[1].sessionId
		t.equal(first, "s1")
		t.equal(state.queue[2].sessionId, first)
		t.truthy(AnalyticsLogic.track(state, funnel(7, 1), 3))
		t.equal(state.queue[3].sessionId, "s2", "a restart starts a new session")
	end,

	["generated session ids use the configured prefix, not the user id"] = function()
		local state = newState({ sessionPrefix = "srv7-" })
		t.truthy(AnalyticsLogic.track(state, funnel(123456789, 1), 1))
		t.equal(state.queue[1].sessionId, "srv7-1")
	end,

	["explicit funnel session ids are checked"] = function()
		local state = newState()
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1, "s1"), 1))
		local _, wrong = AnalyticsLogic.track(state, funnel(1, 2, "s2"), 2)
		t.equal(wrong, "wrong session")
		local _, same = AnalyticsLogic.track(state, funnel(1, 1, "s1"), 3)
		t.equal(same, "duplicate step")
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1, "s2"), 4), "a new session id restarts at step 1")
		t.truthy(AnalyticsLogic.track(state, funnel(1, 2), 5))
		t.equal(state.queue[3].sessionId, "s2")
	end,

	["endFunnel lets step 1 start fresh"] = function()
		local state = newState()
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 1))
		local _, again = AnalyticsLogic.track(state, funnel(1, 1), 5)
		t.equal(again, "duplicate step")
		AnalyticsLogic.endFunnel(state, 1, "Shop")
		t.equal(AnalyticsLogic.funnelProgress(state, 1, "Shop"), nil)
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 6))
	end,

	["onboarding steps run once, in order"] = function()
		local state = newState()
		local function step(n: number): (boolean, string?)
			return AnalyticsLogic.track(state, { kind = "onboarding", userId = 3, step = n, stepName = "Step" .. n }, n)
		end
		t.truthy(step(1))
		t.truthy(step(2))
		local _, skip = step(4)
		t.equal(skip, "skipped step")
		local _, restart = step(1)
		t.equal(restart, "duplicate step", "onboarding cannot restart")
		t.truthy(step(3))
		t.equal((AnalyticsLogic.funnelProgress(state, 3) :: AnalyticsLogic.Progress).step, 3)
	end,

	["funnel steps above the documented 100 are rejected"] = function()
		local state = newState()
		local _, reason = AnalyticsLogic.track(state, funnel(1, 101), 1)
		t.equal(reason, "invalid step")
	end,

	["distinct name caps follow the documented limits"] = function()
		local state = newState({ maxCurrencies = 2, dedupeWindow = 0 })
		t.truthy(AnalyticsLogic.track(state, economy({ currency = "Coins" }), 1))
		t.truthy(AnalyticsLogic.track(state, economy({ currency = "Gems" }), 1))
		local _, reason = AnalyticsLogic.track(state, economy({ currency = "Tokens" }), 1)
		t.equal(reason, "too many names")
		t.truthy(AnalyticsLogic.track(state, economy({ currency = "Coins", amount = 5 }), 1), "known names still pass")
	end,

	["the funnel name cap counts funnels, not steps"] = function()
		local state = newState({ maxFunnels = 1 })
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 1))
		t.truthy(AnalyticsLogic.track(state, funnel(1, 2), 2))
		local other = { kind = "funnel", userId = 1, funnel = "Quest", step = 1 }
		local _, reason = AnalyticsLogic.track(state, other, 3)
		t.equal(reason, "too many names")
	end,

	["identical events inside the dedupe window are dropped"] = function()
		local state = newState({ dedupeWindow = 2 })
		t.truthy(AnalyticsLogic.track(state, economy(), 1))
		local _, reason = AnalyticsLogic.track(state, economy(), 2)
		t.equal(reason, "duplicate")
		t.truthy(AnalyticsLogic.track(state, economy({ balance = 120 }), 2), "a different balance is a new event")
		t.truthy(AnalyticsLogic.track(state, economy(), 3), "the window has passed")
		t.equal(state.stats.dropped.duplicate, 1)
	end,

	["prune forgets old dedupe entries"] = function()
		local state = newState({ dedupeWindow = 1 })
		AnalyticsLogic.track(state, economy(), 1)
		AnalyticsLogic.track(state, economy({ balance = 5 }), 1.5)
		AnalyticsLogic.prune(state, 2.2)
		local count = 0
		for _ in state.recent do
			count += 1
		end
		t.equal(count, 1)
	end,

	["each player has a rate limit bucket"] = function()
		local state = newState({ rate = { capacity = 2, refillPerSecond = 1 }, dedupeWindow = 0 })
		local custom = { kind = "custom", userId = 1, name = "Click" }
		t.truthy(AnalyticsLogic.track(state, custom, 0))
		t.truthy(AnalyticsLogic.track(state, custom, 0))
		local _, reason = AnalyticsLogic.track(state, custom, 0)
		t.equal(reason, "rate limited")
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 2, name = "Click" }, 0), "other players")
		t.truthy(AnalyticsLogic.track(state, custom, 1), "a token refilled after one second")
		t.equal(state.stats.dropped["rate limited"], 1)
	end,

	["a rate limited funnel step still advances the funnel"] = function()
		local state = newState({ rate = { capacity = 1, refillPerSecond = 0 } })
		t.truthy(AnalyticsLogic.track(state, funnel(1, 1), 0))
		local _, reason = AnalyticsLogic.track(state, funnel(1, 2), 1)
		t.equal(reason, "rate limited")
		t.equal((AnalyticsLogic.funnelProgress(state, 1, "Shop") :: AnalyticsLogic.Progress).step, 2)
		local _, third = AnalyticsLogic.track(state, funnel(1, 3), 2)
		t.equal(third, "rate limited", "step 3 is in order, only the budget is gone")
	end,

	["the queue has a cap"] = function()
		local state = newState({ maxQueue = 2, dedupeWindow = 0 })
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 0))
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 2, name = "A" }, 0))
		local _, reason = AnalyticsLogic.track(state, { kind = "custom", userId = 3, name = "A" }, 0)
		t.equal(reason, "queue full")
	end,

	["shouldFlush triggers on batch size or interval"] = function()
		local state = newState({ batchSize = 2, flushInterval = 5, dedupeWindow = 0 })
		t.falsy(AnalyticsLogic.shouldFlush(state, 100), "empty queues never flush")
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 1)
		t.falsy(AnalyticsLogic.shouldFlush(state, 1))
		t.truthy(AnalyticsLogic.shouldFlush(state, 5), "five seconds since the last flush")
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "B" }, 1)
		t.truthy(AnalyticsLogic.shouldFlush(state, 1), "batch is full")
	end,

	["tick flushes only when due"] = function()
		local state = newState({ batchSize = 3, flushInterval = 10, dedupeWindow = 0 })
		local sink = AnalyticsLogic.memorySink()
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 1)
		t.equal(AnalyticsLogic.tick(state, sink, 2), 0)
		t.equal(AnalyticsLogic.tick(state, sink, 10), 1)
		t.equal(sink.batches, 1)
		t.equal(AnalyticsLogic.tick(state, sink, 30), 0, "nothing queued")
	end,

	["a sink that errors does not keep the batch"] = function()
		local state = newState()
		AnalyticsLogic.track(state, economy(), 1)
		local broken: AnalyticsLogic.Sink = {
			write = function(_events: { AnalyticsLogic.Event })
				error("network down")
			end,
		}
		local sent, err = AnalyticsLogic.flush(state, broken, 2)
		t.equal(sent, 1)
		t.truthy(err and string.find(err, "network down"))
		t.equal(#state.queue, 0)
		t.equal(state.stats.sinkErrors, 1)
	end,

	["coalescing sums identical custom events in one batch"] = function()
		local state = newState({ coalesceCustom = true, dedupeWindow = 0 })
		local kill = { kind = "custom", userId = 1, name = "Kill", fields = { "Sword" } }
		AnalyticsLogic.track(state, kill, 0)
		AnalyticsLogic.track(state, kill, 0)
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "Kill", value = 3, fields = { "Sword" } }, 0)
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "Kill", fields = { "Bow" } }, 0)
		t.equal(#state.queue, 2)
		t.equal(state.queue[1].value, 5)
		t.equal(state.stats.coalesced, 2)
		local sink = AnalyticsLogic.memorySink()
		AnalyticsLogic.flush(state, sink, 1)
		AnalyticsLogic.track(state, kill, 2)
		t.equal(#state.queue, 1, "a new batch starts a new sum")
	end,

	["sampling is decided once per player and kind"] = function()
		local state = newState({ sampleRates = { custom = 0.5 }, dedupeWindow = 0 })
		local rng = sequence({ 0.9, 0.1 })
		local _, reason = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 0, rng)
		t.equal(reason, "sampled out")
		local _, again = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "B" }, 0, rng)
		t.equal(again, "sampled out", "the decision sticks")
		t.truthy(AnalyticsLogic.track(state, { kind = "custom", userId = 2, name = "A" }, 0, rng))
		t.truthy(AnalyticsLogic.track(state, economy(), 0, rng), "other kinds are not sampled")
	end,

	["sample rates of 0 and 1 never call the rng"] = function()
		local state = newState({ sampleRates = { custom = 0, economy = 1 } })
		local _, reason = AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 0)
		t.equal(reason, "sampled out")
		t.truthy(AnalyticsLogic.track(state, economy(), 0))
		local partial = newState({ sampleRates = { custom = 0.5 } })
		t.throws(function()
			AnalyticsLogic.track(partial, { kind = "custom", userId = 1, name = "A" }, 0)
		end)
	end,

	["forgetPlayer clears funnels and sampling for that player only"] = function()
		local state = newState({ sampleRates = { custom = 0.5 } })
		AnalyticsLogic.track(state, funnel(1, 1), 0)
		AnalyticsLogic.track(state, funnel(12, 1), 0)
		AnalyticsLogic.track(state, { kind = "custom", userId = 1, name = "A" }, 0, sequence({ 0.9 }))
		AnalyticsLogic.forgetPlayer(state, 1)
		t.equal(AnalyticsLogic.funnelProgress(state, 1, "Shop"), nil)
		t.truthy(AnalyticsLogic.funnelProgress(state, 12, "Shop"), "user 12 shares a prefix but is kept")
		local decided = 0
		for _ in state.sampled do
			decided += 1
		end
		t.equal(decided, 0)
	end,

	["serverBudgetPerMinute matches the documented formula"] = function()
		t.equal(AnalyticsLogic.serverBudgetPerMinute(0), 120)
		t.equal(AnalyticsLogic.serverBudgetPerMinute(10), 320)
		t.throws(function()
			AnalyticsLogic.serverBudgetPerMinute(-1)
		end)
	end,

	["validate returns a clean copy without extra keys"] = function()
		local settings = AnalyticsLogic.validateConfig(nil)
		local input = economy({ extra = "ignored", fields = { "Shop" } })
		local event = AnalyticsLogic.validate(settings, input, 4) :: AnalyticsLogic.Event
		t.equal((event :: any).extra, nil)
		t.deepEqual(event.fields, { CustomField01 = "Shop" })
		t.equal(event.time, 4)
		t.falsy(rawequal(event, input))
	end,
}
