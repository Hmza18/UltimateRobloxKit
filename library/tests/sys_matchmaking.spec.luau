--!strict
local Matchmaking = require("../src/Systems/Matchmaking/MatchmakingLogic")
local t = require("./lib/t")

local BASE = { teamCount = 2, teamSize = 2, baseSkillWindow = 100, widenPerSecond = 10, maxSkillWindow = 500 }

local function queueWith(overrides: { [string]: any }?): any
	local config: { [string]: any } = table.clone(BASE)
	for key, value in overrides or {} do
		config[key] = value
	end
	return Matchmaking.newQueue(config)
end

local function solo(id: string, skill: number, bucket: string?): any
	return { id = id, players = { id }, skill = skill, bucket = bucket }
end

return {
	["resolveConfig fills defaults and rejects bad values"] = function()
		local config = Matchmaking.resolveConfig({ teamSize = 3, teamCount = 1.5, widenPerSecond = -1, maxWait = 0 })
		t.equal(config.teamSize, 3)
		t.equal(config.teamCount, 2, "non-integer team count falls back")
		t.equal(config.widenPerSecond, 10, "negative values fall back")
		t.equal(config.maxWait, 300, "maxWait must be positive")
		t.equal(Matchmaking.matchSize(config), 6)
	end,

	["skill window widens with waiting and caps"] = function()
		local config = Matchmaking.resolveConfig(BASE)
		t.equal(Matchmaking.skillWindow(config, 0), 100)
		t.equal(Matchmaking.skillWindow(config, 10), 200)
		t.equal(Matchmaking.skillWindow(config, 1000), 500)
		t.equal(Matchmaking.skillWindow(config, -5), 100)
	end,

	["enqueue validates tickets"] = function()
		local queue = queueWith()
		t.truthy(Matchmaking.enqueue(queue, { id = "p", players = { "u1", "u2" }, skill = 1000 }, 0))
		t.equal(select(2, Matchmaking.enqueue(queue, solo("p", 1000), 0)), "duplicate ticket")
		local again = { id = "q", players = { "u2" }, skill = 1 }
		t.equal(select(2, Matchmaking.enqueue(queue, again, 0)), "player already queued")
		local big = { id = "big", players = { "a", "b", "c" }, skill = 1 }
		t.equal(select(2, Matchmaking.enqueue(queue, big, 0)), "party is larger than a team")
		local twice = { id = "twice", players = { "x", "x" }, skill = 1 }
		t.equal(select(2, Matchmaking.enqueue(queue, twice, 0)), "player listed twice")
		t.equal(select(2, Matchmaking.enqueue(queue, solo("nan", math.sqrt(-1)), 0)), "skill must be a finite number")
		t.equal(select(2, Matchmaking.enqueue(queue, { id = "e", players = {}, skill = 1 }, 0)), "ticket needs players")
		t.equal(select(2, Matchmaking.enqueue(queue, nil :: any, 0)), "ticket needs an id")
		t.equal(Matchmaking.size(queue), 1)
	end,

	["four solos make a full two versus two"] = function()
		local queue = queueWith()
		for index, id in { "a", "b", "c", "d" } do
			Matchmaking.enqueue(queue, solo(id, 1000 + index * 10), 0)
		end
		local matches = Matchmaking.assemble(queue, 0)
		t.equal(#matches, 1)
		local match = matches[1]
		t.truthy(match.full)
		t.deepEqual(match.teams, { { "a", "c" }, { "b", "d" } })
		t.deepEqual(match.players, { "a", "b", "c", "d" })
		t.near(match.averageSkill, 1025)
		t.equal(match.bucket, "default")
		t.equal(Matchmaking.size(queue), 0)
	end,

	["skill gaps close as the window widens"] = function()
		local queue = queueWith({ teamSize = 1 })
		Matchmaking.enqueue(queue, solo("low", 1000), 0)
		Matchmaking.enqueue(queue, solo("high", 1300), 0)
		t.equal(#Matchmaking.assemble(queue, 0), 0)
		t.equal(#Matchmaking.assemble(queue, 19), 0)
		t.equal(#Matchmaking.assemble(queue, 20), 1)
	end,

	["buckets never mix"] = function()
		local queue = queueWith({ teamSize = 1 })
		Matchmaking.enqueue(queue, solo("a", 1000, "duo"), 0)
		Matchmaking.enqueue(queue, solo("b", 1000), 0)
		t.equal(#Matchmaking.assemble(queue, 0), 0)
		Matchmaking.enqueue(queue, solo("c", 1000, "duo"), 1)
		local matches = Matchmaking.assemble(queue, 1)
		t.equal(#matches, 1)
		t.deepEqual(matches[1].ticketIds, { "a", "c" })
		t.equal(matches[1].bucket, "duo")
	end,

	["parties stay together"] = function()
		local queue = queueWith()
		Matchmaking.enqueue(queue, { id = "p1", players = { "u1", "u2" }, skill = 1000 }, 0)
		Matchmaking.enqueue(queue, solo("s1", 1000), 1)
		Matchmaking.enqueue(queue, solo("s2", 1000), 2)
		Matchmaking.enqueue(queue, { id = "p2", players = { "u5", "u6" }, skill = 1000 }, 3)
		local matches = Matchmaking.assemble(queue, 3)
		t.equal(#matches, 1)
		t.deepEqual(matches[1].teams, { { "u1", "u2" }, { "u5", "u6" } })
		t.equal(Matchmaking.size(queue), 2, "the solos wait for the next match")
	end,

	["partial matches only after fillAfter with minPlayers"] = function()
		local queue = queueWith({ minPlayers = 2, fillAfter = 30 })
		Matchmaking.enqueue(queue, solo("a", 1000), 0)
		Matchmaking.enqueue(queue, solo("b", 1000), 0)
		t.equal(#Matchmaking.assemble(queue, 10), 0)
		local matches = Matchmaking.assemble(queue, 30)
		t.equal(#matches, 1)
		t.falsy(matches[1].full)
		local strict = queueWith()
		Matchmaking.enqueue(strict, solo("a", 1000), 0)
		Matchmaking.enqueue(strict, solo("b", 1000), 0)
		t.equal(#Matchmaking.assemble(strict, 1000), 0, "minPlayers 0 means full matches only")
	end,

	["several matches form in one pass"] = function()
		local queue = queueWith({ teamSize = 1 })
		local skills = { a = 0, b = 10, c = 1000, d = 1010, e = 5000, f = 5010 }
		for id, skill in skills do
			Matchmaking.enqueue(queue, solo(id, skill), 0)
		end
		local matches = Matchmaking.assemble(queue, 0)
		t.equal(#matches, 3)
		t.deepEqual(matches[1].ticketIds, { "a", "b" })
		t.deepEqual(matches[2].ticketIds, { "c", "d" })
		t.deepEqual(matches[3].ticketIds, { "e", "f" })
	end,

	["leaving removes the whole party"] = function()
		local queue = queueWith()
		Matchmaking.enqueue(queue, { id = "p", players = { "u1", "u2" }, skill = 1000 }, 0)
		t.equal(Matchmaking.dequeuePlayer(queue, "u2"), "p")
		t.equal(Matchmaking.size(queue), 0)
		t.equal(queue.byPlayer.u1, nil)
		t.equal(Matchmaking.dequeuePlayer(queue, "nobody"), nil)
		t.falsy(Matchmaking.dequeue(queue, "p"))
	end,

	["expire drops old tickets"] = function()
		local queue = queueWith({ maxWait = 60 })
		Matchmaking.enqueue(queue, solo("old", 1000), 0)
		Matchmaking.enqueue(queue, solo("new", 1000), 50)
		t.deepEqual(Matchmaking.expire(queue, 61), { "old" })
		t.equal(Matchmaking.size(queue), 1)
	end,

	["tickets encode and decode safely"] = function()
		local queue = queueWith()
		Matchmaking.enqueue(queue, { id = "p", players = { "u1" }, skill = 7, bucket = "ranked" }, 12)
		local ticket = queue.tickets.p
		local decoded = Matchmaking.decodeTicket(Matchmaking.encodeTicket(ticket))
		t.deepEqual(decoded, ticket)
		t.equal(Matchmaking.decodeTicket({ id = "x", bucket = "b", skill = 1, enqueuedAt = 0, players = { 5 } }), nil)
		t.equal(Matchmaking.decodeTicket({ id = "x", skill = 1, enqueuedAt = 0, players = { "a" } }), nil)
		t.equal(Matchmaking.decodeTicket({ id = "x", bucket = "b", skill = 1, enqueuedAt = 0, players = {} }), nil)
		t.equal(Matchmaking.decodeTicket("x"), nil)
		local other = queueWith()
		t.truthy(Matchmaking.restore(other, ticket))
		t.equal(other.tickets.p.enqueuedAt, 12)
	end,

	["backoff doubles with jitter and caps"] = function()
		local function zero(): number
			return 0
		end
		local function one(): number
			return 1
		end
		t.near(Matchmaking.backoff(1, 1, 15, zero), 0.5)
		t.near(Matchmaking.backoff(3, 1, 15, zero), 2)
		t.near(Matchmaking.backoff(3, 1, 15, one), 4)
		t.near(Matchmaking.backoff(10, 1, 15, one), 15)
	end,
}
