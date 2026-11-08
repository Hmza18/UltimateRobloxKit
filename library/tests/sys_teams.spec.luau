--!strict
local Teams = require("../src/Systems/Teams/TeamsLogic")
local t = require("./lib/t")

return {
	["new validates team names"] = function()
		local state = Teams.new({ "Red", { name = "Blue", maxSize = 2 } })
		t.deepEqual(state.order, { "Red", "Blue" })
		t.equal(state.maxSize.Blue, 2)
		t.equal(state.maxSize.Red, math.huge)
		t.throws(function()
			Teams.new({})
		end)
		t.throws(function()
			Teams.new({ "Red", "Red" })
		end)
		t.throws(function()
			Teams.new({ 5 })
		end)
	end,

	["assign fills the smallest team in order"] = function()
		local state = Teams.new({ "Red", "Blue" })
		t.equal(Teams.assign(state, "1"), "Red")
		t.equal(Teams.assign(state, "2"), "Blue")
		t.equal(Teams.assign(state, "3"), "Red")
		t.equal(Teams.assign(state, "1"), "Red", "already assigned players keep their team")
		t.equal(Teams.size(state, "Red"), 2)
		t.deepEqual(Teams.membersOf(state, "Red"), { "1", "3" })
	end,

	["assign breaks size ties by total skill"] = function()
		local state = Teams.new({ "Red", "Blue" })
		Teams.assign(state, "pro", 2000, true)
		Teams.assign(state, "mid", 1000, true)
		t.equal(Teams.teamOf(state, "pro"), "Red")
		t.equal(Teams.teamOf(state, "mid"), "Blue")
		t.equal(Teams.assign(state, "new", 500, true), "Blue", "Blue has the lower total")
		t.equal(Teams.totalSkill(state, "Blue"), 1500)
	end,

	["full teams are skipped"] = function()
		local state = Teams.new({ { name = "Solo", maxSize = 1 }, { name = "Duo", maxSize = 2 } })
		t.equal(Teams.assign(state, "a"), "Solo")
		t.equal(Teams.assign(state, "b"), "Duo")
		t.equal(Teams.assign(state, "c"), "Duo")
		t.equal(Teams.assign(state, "d"), nil)
		t.equal(Teams.pickTeam(state), nil)
	end,

	["join enforces size and balance rules"] = function()
		local state = Teams.new({ "Red", "Blue", { name = "Gold", maxSize = 1 } })
		Teams.assign(state, "1", 10)
		Teams.assign(state, "2")
		Teams.assign(state, "3")
		t.equal(select(2, Teams.join(state, "1", "Green")), "unknown team")
		t.equal(select(2, Teams.join(state, "1", "Red")), "already on that team")
		t.equal(select(2, Teams.join(state, "2", "Gold")), "team is full")
		Teams.assign(state, "4")
		t.equal(Teams.teamOf(state, "4"), "Red")
		t.equal(select(2, Teams.join(state, "2", "Red")), "teams would be unbalanced")
		t.truthy(Teams.join(state, "2", "Red", nil, 3))
		t.equal(Teams.teamOf(state, "2"), "Red")
		t.truthy(Teams.join(state, "1", "Blue"))
		t.equal(state.members.Blue["1"], 10, "skill moves with the player")
	end,

	["remove takes the player off their team"] = function()
		local state = Teams.new({ "Red", "Blue" })
		Teams.assign(state, "1")
		t.equal(Teams.remove(state, "1"), "Red")
		t.equal(Teams.remove(state, "1"), nil)
		t.equal(Teams.size(state, "Red"), 0)
	end,

	["balance uses a snake draft by skill"] = function()
		local players = {
			{ id = "a", skill = 100 },
			{ id = "b", skill = 90 },
			{ id = "c", skill = 80 },
			{ id = "d", skill = 70 },
			{ id = "e", skill = 60 },
		}
		local result = Teams.balance(players, { "Red", "Blue" }, true)
		t.deepEqual(result, { a = "Red", b = "Blue", c = "Blue", d = "Red", e = "Red" })
	end,

	["balance without skill deals round robin by id"] = function()
		local players = { { id = "c" }, { id = "a" }, { id = "b" } }
		local result = Teams.balance(players, { "Red", "Blue", "Green" })
		t.deepEqual(result, { a = "Red", b = "Blue", c = "Green" })
	end,

	["rebalance moves players from the largest team"] = function()
		local state = Teams.new({ "Red", "Blue" })
		for index, skill in { 50, 10, 30, 40 } do
			state.members.Red[tostring(index)] = skill
			state.teamOf[tostring(index)] = "Red"
		end
		local moves = Teams.rebalance(state, 1)
		t.equal(#moves, 2)
		t.equal(moves[1].from, "Red")
		t.equal(moves[1].to, "Blue")
		t.equal(moves[1].playerId, "1", "moving the 50 leaves totals 80 against 50")
		t.equal(moves[2].playerId, "2", "then the 10 leaves 70 against 60")
		t.equal(Teams.size(state, "Red"), 2)
		t.equal(#Teams.rebalance(state, 1), 0)
	end,

	["friendly fire and self damage rules"] = function()
		local rules = { friendlyFire = false, selfDamage = false }
		t.truthy(Teams.canDamage(rules, "1", "2", "Red", "Blue"))
		t.falsy(Teams.canDamage(rules, "1", "2", "Red", "Red"))
		t.falsy(Teams.canDamage(rules, "1", "1", "Red", "Red"))
		t.truthy(Teams.canDamage(rules, "1", "2", nil, "Red"), "neutral players can fight")
		t.truthy(Teams.canDamage({ friendlyFire = true }, "1", "2", "Red", "Red"))
		t.truthy(Teams.canDamage({ selfDamage = true }, "1", "1", "Red", "Red"))
	end,

	["scores, standings and leader"] = function()
		local state = Teams.new({ "Red", "Blue", "Green" })
		t.equal(Teams.leader(state), nil, "all tied at zero")
		t.equal(Teams.addScore(state, "Blue", 5), 5)
		t.equal(Teams.addScore(state, "Red", 3), 3)
		t.equal(Teams.addScore(state, "Nope", 1), nil)
		t.equal(Teams.addScore(state, "Red", math.huge), nil)
		t.equal(Teams.leader(state), "Blue")
		local standings = Teams.standings(state)
		t.equal(standings[1].team, "Blue")
		t.equal(standings[2].team, "Red")
		t.equal(standings[3].team, "Green")
		Teams.addScore(state, "Red", 2)
		t.equal(Teams.leader(state), nil, "Red and Blue share the top score")
		Teams.resetScores(state)
		t.equal(state.scores.Blue, 0)
	end,
}
