--!strict
local Rounds = require("../src/Systems/Rounds/RoundsLogic")
local t = require("./lib/t")

local CONFIG = Rounds.resolveConfig({
	minPlayers = 2,
	intermissionTime = 10,
	startingTime = 3,
	roundTime = 60,
	endingTime = 5,
	minPlayersToContinue = 1,
})

local function step(state: any, now: number, players: number, winner: any?): any
	local input = {
		now = now,
		playerCount = players,
		checkWinner = function()
			return winner
		end,
	}
	return Rounds.update(state, CONFIG, input)
end

-- Runs a fresh state into InProgress at time 13 with 2 players.
local function inProgress(): any
	local state = Rounds.new(CONFIG, 0)
	step(state, 10, 2)
	step(state, 13, 2)
	return state
end

return {
	["resolveConfig keeps valid values and fills the rest"] = function()
		local config = Rounds.resolveConfig({ minPlayers = 4, roundTime = -1, endingTime = "x" })
		t.equal(config.minPlayers, 4)
		t.equal(config.roundTime, 180)
		t.equal(config.endingTime, 8)
		t.equal(config.intermissionTime, 15)
	end,

	["intermission holds until enough players"] = function()
		local state = Rounds.new(CONFIG, 0)
		t.equal(state.phase, "Intermission")
		t.equal(step(state, 20, 1), nil)
		t.truthy(state.waiting)
		t.equal(state.phaseEndsAt, 30, "the timer restarts while waiting")
		t.equal(step(state, 25, 2), nil)
		t.falsy(state.waiting)
		local change = step(state, 30, 2)
		t.truthy(change)
		t.equal(change.from, "Intermission")
		t.equal(change.to, "Starting")
		t.equal(state.phaseEndsAt, 33)
	end,

	["a full cycle counts rounds"] = function()
		local state = Rounds.new(CONFIG, 0)
		t.equal(step(state, 10, 2).to, "Starting")
		t.equal(step(state, 12, 2), nil)
		local started = step(state, 13, 2)
		t.equal(started.to, "InProgress")
		t.equal(started.round, 1)
		t.equal(state.round, 1)
		local ended = step(state, 73, 2)
		t.equal(ended.to, "Ending")
		t.equal(ended.result.reason, "timeout")
		t.equal(step(state, 77, 2), nil)
		t.equal(step(state, 78, 2).to, "Intermission")
		step(state, 88, 2)
		step(state, 91, 2)
		t.equal(state.round, 2)
	end,

	["starting aborts when players leave"] = function()
		local state = Rounds.new(CONFIG, 0)
		step(state, 10, 2)
		local change = step(state, 11, 1)
		t.equal(change.from, "Starting")
		t.equal(change.to, "Intermission")
		t.equal(state.round, 0)
	end,

	["a winner ends the round"] = function()
		local state = inProgress()
		t.equal(step(state, 20, 2), nil)
		local change = step(state, 21, 2, "Red")
		t.equal(change.to, "Ending")
		t.equal(change.result.winner, "Red")
		t.equal(change.result.reason, "win")
		t.equal(state.result.winner, "Red")
	end,

	["the winner check only runs in progress"] = function()
		local calls = 0
		local state = Rounds.new(CONFIG, 0)
		local input = {
			now = 1,
			playerCount = 2,
			checkWinner = function()
				calls += 1
				return "Blue"
			end,
		}
		Rounds.update(state, CONFIG, input)
		t.equal(calls, 0)
		t.equal(state.phase, "Intermission")
	end,

	["the round is abandoned when players run out"] = function()
		local state = inProgress()
		local change = step(state, 20, 0)
		t.equal(change.result.reason, "abandoned")
		t.equal(change.result.winner, nil)
	end,

	["forceEnd only works during a round"] = function()
		local state = Rounds.new(CONFIG, 0)
		t.equal(Rounds.forceEnd(state, CONFIG, 1, "Admin"), nil)
		local running = inProgress()
		local change = Rounds.forceEnd(running, CONFIG, 14, "Admin")
		t.truthy(change)
		t.equal(running.phase, "Ending")
		t.equal(running.result.reason, "forced")
		t.equal(running.phaseEndsAt, 19)
	end,

	["votes are validated and replaceable"] = function()
		local state = Rounds.new(CONFIG, 0)
		t.equal(select(2, Rounds.castVote(state, "1", "Desert")), "no vote open")
		local vote = Rounds.openVote(state, { "Desert", "Forest", "Desert", 5 :: any })
		t.deepEqual(vote.options, { "Desert", "Forest" })
		t.truthy(Rounds.castVote(state, "1", "Desert"))
		t.truthy(Rounds.castVote(state, "2", "Desert"))
		t.truthy(Rounds.castVote(state, "2", "Forest"))
		t.equal(select(2, Rounds.castVote(state, "3", "Moon")), "unknown option")
		t.deepEqual(Rounds.counts(vote), { Desert = 1, Forest = 1 })
		Rounds.removeVoter(state, "1")
		t.deepEqual(Rounds.counts(vote), { Desert = 0, Forest = 1 })
		local started = inProgress()
		Rounds.openVote(started, { "Desert" })
		t.equal(select(2, Rounds.castVote(started, "1", "Desert")), "no vote open")
	end,

	["tally breaks ties with the random source"] = function()
		local vote = { options = { "A", "B", "C" }, ballots = { p1 = "A", p2 = "B", p3 = "C", p4 = "B", p5 = "C" } }
		local function high(): number
			return 0.99
		end
		local function middle(): number
			return 0.5
		end
		t.equal(Rounds.tally(vote :: any), "B", "without rng the first tied option wins")
		t.equal(Rounds.tally(vote :: any, high), "C")
		local empty = { options = { "A", "B" }, ballots = {} }
		t.equal(Rounds.tally(empty :: any, middle), "B")
		t.equal(Rounds.tally({ options = {}, ballots = {} } :: any), nil)
	end,

	["the winning map is chosen when the round starts"] = function()
		local state = Rounds.new(CONFIG, 0)
		Rounds.openVote(state, { "Desert", "Forest" })
		Rounds.castVote(state, "1", "Forest")
		local change = step(state, 10, 2)
		t.equal(change.map, "Forest")
		t.equal(state.map, "Forest")
		t.equal(state.vote, nil)
		t.equal(step(state, 13, 2).map, "Forest")
		step(state, 14, 2, "Red")
		step(state, 19, 2)
		t.equal(state.phase, "Intermission")
		t.equal(state.map, nil)
	end,

	["timeLeft never goes negative"] = function()
		local state = Rounds.new(CONFIG, 0)
		t.equal(Rounds.timeLeft(state, 4), 6)
		t.equal(Rounds.timeLeft(state, 40), 0)
	end,
}
