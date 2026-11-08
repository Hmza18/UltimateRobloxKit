--!strict
-- Dialogue graphs and a runner state machine. Pure Luau.
-- A graph is data: nodes with text, optional choices, conditions on variables and actions.
-- The runner walks the graph; "set" and "add" actions change `runner.vars`, and "emit" actions
-- are returned as effects for the server to carry out (give an item, start a quest, open a shop).

export type Condition = {
	key: string?, -- variable to compare
	op: string?, -- "==", "~=", ">", ">=", "<", "<=", "truthy", "falsy" (default "==" with a value, else "truthy")
	value: any?,
	check: string?, -- name of a predicate passed to the runner instead of key/op/value
	args: any?, -- passed to the predicate
}

export type Action = {
	kind: string, -- "set" | "add" | "emit"
	key: string?, -- variable for "set" and "add"
	value: any?, -- value for "set", number for "add"
	event: string?, -- effect name for "emit"
	args: any?, -- effect payload for "emit"
}

export type Choice = { text: string, next: string?, conditions: { Condition }?, actions: { Action }? }

export type Node = {
	speaker: string?,
	text: string,
	choices: { Choice }?, -- the player picks one of the visible choices
	next: string?, -- without choices: where "continue" goes; nil ends the dialogue
	actions: { Action }?, -- run when the node is entered
}

export type Graph = { start: string, nodes: { [string]: Node } }
export type Predicate = (vars: { [string]: any }, args: any) -> boolean
export type Predicates = { [string]: Predicate }
export type Effect = { event: string, args: any }

export type Runner = {
	graph: Graph,
	nodeId: string?,
	vars: { [string]: any },
	predicates: Predicates,
	finished: boolean,
	history: { string },
}

export type ChoiceView = { index: number, text: string }
export type View = { id: string, speaker: string?, text: string, choices: { ChoiceView }, canContinue: boolean }

local OPS: { [string]: boolean } = {
	["=="] = true,
	["~="] = true,
	[">"] = true,
	[">="] = true,
	["<"] = true,
	["<="] = true,
	truthy = true,
	falsy = true,
}
local ACTIONS: { [string]: boolean } = { set = true, add = true, emit = true }
local MAX_HISTORY = 200

local Dialogue = {}

local function isName(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function validateConditions(label: string, raw: any, predicates: Predicates?, errors: { string })
	if raw == nil then
		return
	end
	if type(raw) ~= "table" then
		table.insert(errors, label .. ": conditions must be an array")
		return
	end
	for _, condition in raw do
		if type(condition) ~= "table" then
			table.insert(errors, label .. ": condition must be a table")
		elseif condition.check ~= nil then
			if not isName(condition.check) then
				table.insert(errors, label .. ": check must be a name")
			elseif predicates and predicates[condition.check] == nil then
				table.insert(errors, label .. ": unknown predicate " .. condition.check)
			end
		elseif not isName(condition.key) then
			table.insert(errors, label .. ": condition needs a key or a check")
		elseif condition.op ~= nil and not OPS[condition.op] then
			table.insert(errors, label .. ": unknown operator " .. tostring(condition.op))
		end
	end
end

local function validateActions(label: string, raw: any, errors: { string })
	if raw == nil then
		return
	end
	if type(raw) ~= "table" then
		table.insert(errors, label .. ": actions must be an array")
		return
	end
	for _, action in raw do
		if type(action) ~= "table" or not ACTIONS[action.kind] then
			table.insert(errors, label .. ": unknown action")
		elseif action.kind == "emit" and not isName(action.event) then
			table.insert(errors, label .. ": emit needs an event")
		elseif action.kind ~= "emit" and not isName(action.key) then
			table.insert(errors, label .. ": " .. action.kind .. " needs a key")
		elseif action.kind == "add" and type(action.value) ~= "number" then
			table.insert(errors, label .. ": add needs a number value")
		end
	end
end

-- Checks a graph for missing nodes, dangling links, malformed data and unreachable nodes.
-- Returns ok, the sorted list of errors and the sorted list of unreachable node ids.
-- Unreachable nodes count as errors. Pass `predicates` to also check predicate names.
function Dialogue.validate(graph: Graph, predicates: Predicates?): (boolean, { string }, { string })
	local errors: { string } = {}
	local unreachable: { string } = {}
	if type(graph) ~= "table" or type(graph.nodes) ~= "table" then
		return false, { "graph needs a nodes table" }, unreachable
	end
	local nodes: { [any]: any } = graph.nodes :: any
	if not isName(graph.start) or nodes[graph.start] == nil then
		table.insert(errors, "start node " .. tostring(graph.start) .. " does not exist")
	end
	for id, node in nodes do
		local label = "node " .. tostring(id)
		if not isName(id) or type(node) ~= "table" then
			table.insert(errors, label .. ": must be a table with a string id")
			continue
		end
		if type(node.text) ~= "string" then
			table.insert(errors, label .. ": needs text")
		end
		if node.next ~= nil and nodes[node.next] == nil then
			table.insert(errors, label .. ": next points to missing node " .. tostring(node.next))
		end
		validateActions(label, node.actions, errors)
		if node.choices ~= nil then
			if type(node.choices) ~= "table" or #node.choices == 0 then
				table.insert(errors, label .. ": choices must be a non-empty array")
			else
				if node.next ~= nil then
					table.insert(errors, label .. ": has both choices and next")
				end
				for index, choice in node.choices do
					local choiceLabel = label .. " choice " .. tostring(index)
					if type(choice) ~= "table" or type(choice.text) ~= "string" then
						table.insert(errors, choiceLabel .. ": needs text")
						continue
					end
					if choice.next ~= nil and nodes[choice.next] == nil then
						table.insert(errors, choiceLabel .. ": next points to missing node " .. tostring(choice.next))
					end
					validateConditions(choiceLabel, choice.conditions, predicates, errors)
					validateActions(choiceLabel, choice.actions, errors)
				end
			end
		end
	end
	-- Breadth-first walk from the start to find nodes no path reaches.
	local reached: { [any]: boolean } = {}
	if isName(graph.start) and nodes[graph.start] ~= nil then
		local queue: { any } = { graph.start }
		reached[graph.start] = true
		local head = 1
		while head <= #queue do
			local node = nodes[queue[head]]
			head += 1
			local targets: { any } = {}
			if type(node) == "table" then
				if node.next ~= nil then
					table.insert(targets, node.next)
				end
				if type(node.choices) == "table" then
					for _, choice in node.choices do
						if type(choice) == "table" and choice.next ~= nil then
							table.insert(targets, choice.next)
						end
					end
				end
			end
			for _, target in targets do
				if nodes[target] ~= nil and not reached[target] then
					reached[target] = true
					table.insert(queue, target)
				end
			end
		end
	end
	for id in nodes do
		if not reached[id] then
			table.insert(unreachable, tostring(id))
			table.insert(errors, "node " .. tostring(id) .. ": unreachable from start")
		end
	end
	table.sort(errors)
	table.sort(unreachable)
	return #errors == 0, errors, unreachable
end

-- Evaluates one condition against the variables. Unknown operators and predicates are false.
function Dialogue.evaluate(condition: Condition, vars: { [string]: any }, predicates: Predicates?): boolean
	local check = condition.check
	if check ~= nil then
		local predicate = if predicates then predicates[check] else nil
		return predicate ~= nil and predicate(vars, condition.args) == true
	end
	local key = condition.key
	if key == nil then
		return false
	end
	local actual = vars[key]
	local expected = condition.value
	local op = condition.op
	if op == nil then
		op = if expected == nil then "truthy" else "=="
	end
	if op == "truthy" then
		return actual ~= nil and actual ~= false
	elseif op == "falsy" then
		return actual == nil or actual == false
	elseif op == "==" then
		return actual == expected
	elseif op == "~=" then
		return actual ~= expected
	end
	if type(actual) ~= "number" or type(expected) ~= "number" then
		return false
	end
	if op == ">" then
		return actual > expected
	elseif op == ">=" then
		return actual >= expected
	elseif op == "<" then
		return actual < expected
	elseif op == "<=" then
		return actual <= expected
	end
	return false
end

function Dialogue.allPass(conditions: { Condition }?, vars: { [string]: any }, predicates: Predicates?): boolean
	if conditions == nil then
		return true
	end
	for _, condition in conditions do
		if not Dialogue.evaluate(condition, vars, predicates) then
			return false
		end
	end
	return true
end

-- Runs actions in order, changing `vars` and appending "emit" effects to `effects`.
function Dialogue.applyActions(actions: { Action }?, vars: { [string]: any }, effects: { Effect })
	if actions == nil then
		return
	end
	for _, action in actions do
		local key = action.key
		if action.kind == "set" and key then
			vars[key] = action.value
		elseif action.kind == "add" and key and type(action.value) == "number" then
			local current = vars[key]
			local base = if type(current) == "number" then current else 0
			vars[key] = base + action.value
		elseif action.kind == "emit" and action.event then
			table.insert(effects, { event = action.event, args = action.args })
		end
	end
end

local function enter(runner: Runner, nodeId: string?, effects: { Effect })
	if nodeId == nil then
		runner.nodeId = nil
		runner.finished = true
		return
	end
	local node = runner.graph.nodes[nodeId]
	if node == nil then
		runner.nodeId = nil
		runner.finished = true
		return
	end
	runner.nodeId = nodeId
	table.insert(runner.history, nodeId)
	if #runner.history > MAX_HISTORY then
		table.remove(runner.history, 1)
	end
	Dialogue.applyActions(node.actions, runner.vars, effects)
end

-- Starts a dialogue at the graph's start node. `vars` is used (and changed) in place.
function Dialogue.start(graph: Graph, vars: { [string]: any }?, predicates: Predicates?): (Runner, { Effect })
	local runner: Runner = {
		graph = graph,
		nodeId = nil,
		vars = vars or {},
		predicates = predicates or {},
		finished = false,
		history = {},
	}
	local effects: { Effect } = {}
	enter(runner, graph.start, effects)
	return runner, effects
end

function Dialogue.currentNode(runner: Runner): Node?
	local nodeId = runner.nodeId
	if runner.finished or nodeId == nil then
		return nil
	end
	return runner.graph.nodes[nodeId]
end

-- Choices whose conditions pass, with their index in the node's full choice list.
function Dialogue.visibleChoices(runner: Runner): { ChoiceView }
	local visible: { ChoiceView } = {}
	local node = Dialogue.currentNode(runner)
	if node == nil or node.choices == nil then
		return visible
	end
	for index, choice in node.choices do
		if Dialogue.allPass(choice.conditions, runner.vars, runner.predicates) then
			table.insert(visible, { index = index, text = choice.text })
		end
	end
	return visible
end

-- What a UI needs to draw the current node, or nil when the dialogue has finished.
function Dialogue.view(runner: Runner): View?
	local node = Dialogue.currentNode(runner)
	local nodeId = runner.nodeId
	if node == nil or nodeId == nil then
		return nil
	end
	local choices = Dialogue.visibleChoices(runner)
	return { id = nodeId, speaker = node.speaker, text = node.text, choices = choices, canContinue = #choices == 0 }
end

-- Picks a choice by its index in the node's full choice list. The choice must currently be visible.
function Dialogue.choose(runner: Runner, choiceIndex: number): (boolean, string?, { Effect })
	local effects: { Effect } = {}
	local node = Dialogue.currentNode(runner)
	if node == nil then
		return false, "dialogue finished", effects
	end
	local choices = node.choices
	local choice = if choices and type(choiceIndex) == "number" then choices[choiceIndex] else nil
	if choice == nil then
		return false, "no such choice", effects
	end
	if not Dialogue.allPass(choice.conditions, runner.vars, runner.predicates) then
		return false, "choice not available", effects
	end
	Dialogue.applyActions(choice.actions, runner.vars, effects)
	enter(runner, choice.next, effects)
	return true, nil, effects
end

-- Moves on from a node that shows no choices: to `next`, or to the end.
function Dialogue.advance(runner: Runner): (boolean, string?, { Effect })
	local effects: { Effect } = {}
	local node = Dialogue.currentNode(runner)
	if node == nil then
		return false, "dialogue finished", effects
	end
	if #Dialogue.visibleChoices(runner) > 0 then
		return false, "a choice is required", effects
	end
	enter(runner, node.next, effects)
	return true, nil, effects
end

-- Ends the dialogue early, for example when the player walks away.
function Dialogue.stop(runner: Runner)
	runner.nodeId = nil
	runner.finished = true
end

return Dialogue
