--!strict
local Dialogue = require("../src/Systems/Dialogue/DialogueLogic")
local t = require("./lib/t")

local function guardGraph(): any
	return {
		start = "hello",
		nodes = {
			hello = {
				speaker = "Guard",
				text = "Halt!",
				actions = { { kind = "add", key = "visits", value = 1 } },
				choices = {
					{ text = "Who are you?", next = "who" },
					{ text = "Let me in", next = "gate", conditions = { { key = "vip", value = true } } },
					{
						text = "Bribe",
						next = "gate",
						conditions = { { key = "gold", op = ">=", value = 10 } },
						actions = {
							{ kind = "add", key = "gold", value = -10 },
							{ kind = "emit", event = "Bribed", args = 10 },
						},
					},
					{ text = "Bye" },
				},
			},
			who = { speaker = "Guard", text = "The guard.", next = "hello" },
			gate = {
				text = "The gate opens.",
				actions = { { kind = "set", key = "gateOpen", value = true }, { kind = "emit", event = "OpenGate" } },
			},
		},
	}
end

local function hasError(errors: { string }, fragment: string): boolean
	for _, message in errors do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

return {
	["validate accepts a well formed graph"] = function()
		local ok, errors, unreachable = Dialogue.validate(guardGraph())
		t.truthy(ok, table.concat(errors, "; "))
		t.equal(#unreachable, 0)
	end,

	["validate reports a missing start and dangling links"] = function()
		local graph = guardGraph()
		graph.start = "nowhere"
		graph.nodes.who.next = "ghost"
		graph.nodes.hello.choices[1].next = "void"
		local ok, errors = Dialogue.validate(graph)
		t.falsy(ok)
		t.truthy(hasError(errors, "start node nowhere does not exist"))
		t.truthy(hasError(errors, "missing node ghost"))
		t.truthy(hasError(errors, "missing node void"))
	end,

	["validate reports unreachable nodes"] = function()
		local graph = guardGraph()
		graph.nodes.secret = { text = "Nobody gets here." }
		graph.nodes.island = { text = "Nor here.", next = "secret" }
		local ok, errors, unreachable = Dialogue.validate(graph)
		t.falsy(ok)
		t.deepEqual(unreachable, { "island", "secret" })
		t.truthy(hasError(errors, "node secret: unreachable from start"))
	end,

	["validate reports malformed nodes, conditions and actions"] = function()
		local graph = guardGraph()
		graph.nodes.who.choices = {}
		graph.nodes.gate.actions = { { kind = "explode" }, { kind = "add", key = "gold", value = "lots" } }
		graph.nodes.hello.choices[2].conditions = { { key = "vip", op = "is" }, { check = "hasPass" } }
		graph.nodes.hello.text = nil
		local ok, errors = Dialogue.validate(graph, {})
		t.falsy(ok)
		t.truthy(hasError(errors, "node hello: needs text"))
		t.truthy(hasError(errors, "choices must be a non-empty array"))
		t.truthy(hasError(errors, "unknown action"))
		t.truthy(hasError(errors, "add needs a number value"))
		t.truthy(hasError(errors, "unknown operator is"))
		t.truthy(hasError(errors, "unknown predicate hasPass"))
		local bad = Dialogue.validate(nil :: any)
		t.falsy(bad)
	end,

	["validate rejects nodes with both choices and next"] = function()
		local graph = guardGraph()
		graph.nodes.hello.next = "who"
		local ok, errors = Dialogue.validate(graph)
		t.falsy(ok)
		t.truthy(hasError(errors, "has both choices and next"))
	end,

	["evaluate supports every operator"] = function()
		local vars = { gold = 5, name = "Ana", flag = false }
		t.truthy(Dialogue.evaluate({ key = "gold", op = ">", value = 4 }, vars))
		t.truthy(Dialogue.evaluate({ key = "gold", op = ">=", value = 5 }, vars))
		t.truthy(Dialogue.evaluate({ key = "gold", op = "<", value = 6 }, vars))
		t.truthy(Dialogue.evaluate({ key = "gold", op = "<=", value = 5 }, vars))
		t.truthy(Dialogue.evaluate({ key = "name", value = "Ana" }, vars))
		t.truthy(Dialogue.evaluate({ key = "name", op = "~=", value = "Bo" }, vars))
		t.truthy(Dialogue.evaluate({ key = "flag", op = "falsy" }, vars))
		t.truthy(Dialogue.evaluate({ key = "missing", op = "falsy" }, vars))
		t.truthy(Dialogue.evaluate({ key = "gold" }, vars), "default is truthy")
		t.falsy(Dialogue.evaluate({ key = "name", op = ">", value = 1 }, vars), "non numbers never compare")
		t.falsy(Dialogue.evaluate({ key = "gold", op = "is", value = 5 }, vars))
		t.falsy(Dialogue.evaluate({}, vars))
	end,

	["predicates decide check conditions"] = function()
		local predicates = {
			hasItem = function(vars: { [string]: any }, args: any): boolean
				return vars.items ~= nil and vars.items[args] == true
			end,
		}
		local vars = { items = { Key = true } }
		t.truthy(Dialogue.evaluate({ check = "hasItem", args = "Key" }, vars, predicates))
		t.falsy(Dialogue.evaluate({ check = "hasItem", args = "Map" }, vars, predicates))
		t.falsy(Dialogue.evaluate({ check = "unknown" }, vars, predicates))
		t.falsy(Dialogue.evaluate({ check = "hasItem", args = "Key" }, vars))
	end,

	["start enters the first node and runs its actions"] = function()
		local runner = Dialogue.start(guardGraph(), { visits = 2 })
		t.equal(runner.vars.visits, 3)
		local view = Dialogue.view(runner)
		t.truthy(view)
		if view then
			t.equal(view.id, "hello")
			t.equal(view.speaker, "Guard")
			t.equal(view.text, "Halt!")
			t.equal(#view.choices, 2, "only unconditional choices are visible")
			t.equal(view.choices[1].index, 1)
			t.equal(view.choices[2].index, 4)
			t.falsy(view.canContinue)
		end
	end,

	["hidden choices are refused"] = function()
		local runner = Dialogue.start(guardGraph(), { gold = 3 })
		local ok, reason = Dialogue.choose(runner, 3)
		t.falsy(ok)
		t.equal(reason, "choice not available")
		t.equal(select(2, Dialogue.choose(runner, 9)), "no such choice")
		t.equal(select(2, Dialogue.choose(runner, "1" :: any)), "no such choice")
		t.equal(runner.nodeId, "hello")
	end,

	["choices run actions and collect effects"] = function()
		local runner = Dialogue.start(guardGraph(), { gold = 12 })
		local ok, _, effects = Dialogue.choose(runner, 3)
		t.truthy(ok)
		t.equal(runner.nodeId, "gate")
		t.equal(runner.vars.gold, 2)
		t.equal(runner.vars.gateOpen, true)
		t.equal(#effects, 2)
		t.equal(effects[1].event, "Bribed")
		t.equal(effects[1].args, 10)
		t.equal(effects[2].event, "OpenGate")
		t.deepEqual(runner.history, { "hello", "gate" })
	end,

	["advance follows next and finishes at the end"] = function()
		local runner = Dialogue.start(guardGraph(), {})
		Dialogue.choose(runner, 1)
		t.equal(runner.nodeId, "who")
		local blocked = Dialogue.advance(Dialogue.start(guardGraph(), {}))
		t.falsy(blocked, "a node with visible choices needs a choice")
		t.truthy(Dialogue.advance(runner))
		t.equal(runner.nodeId, "hello")
		t.equal(runner.vars.visits, 2)
		Dialogue.choose(runner, 4)
		t.truthy(runner.finished)
		t.equal(Dialogue.view(runner), nil)
		t.equal(select(2, Dialogue.advance(runner)), "dialogue finished")
		t.equal(select(2, Dialogue.choose(runner, 1)), "dialogue finished")
	end,

	["a node whose choices are all hidden can be continued"] = function()
		local graph = {
			start = "a",
			nodes = {
				a = { text = "Members only", choices = { { text = "Enter", conditions = { { key = "member" } } } } },
			},
		}
		local runner = Dialogue.start(graph :: any, {})
		local view = Dialogue.view(runner)
		t.truthy(view and view.canContinue)
		t.truthy(Dialogue.advance(runner))
		t.truthy(runner.finished)
	end,

	["stop ends the dialogue"] = function()
		local runner = Dialogue.start(guardGraph())
		Dialogue.stop(runner)
		t.truthy(runner.finished)
		t.equal(Dialogue.currentNode(runner), nil)
		t.equal(#Dialogue.visibleChoices(runner), 0)
	end,
}
