# Dialogue

Branching conversations as data: nodes with text, choices that show only when their conditions pass, and actions that change variables or emit effects. The graph is validated up front (dangling links, unreachable nodes, malformed conditions). The server runs the conversation, so a client cannot pick a hidden choice or trigger a consequence it was not offered.

| File | Runs on | Role |
| --- | --- | --- |
| `DialogueLogic.luau` | anywhere (pure) | graph validation, condition evaluation, runner state machine |
| `DialogueServer.luau` | server | one session per player, validated input, effects callback |
| `DialogueClient.luau` | client | UI-agnostic: `onNode` / `onEnd` callbacks and signals |

## Graph format

```lua
local guard = {
	start = "hello",
	nodes = {
		hello = {
			speaker = "Guard", text = "Halt!",
			actions = { { kind = "add", key = "visits", value = 1 } },
			choices = {
				{ text = "Who are you?", next = "who" },
				{ text = "I have a pass", next = "gate", conditions = { { check = "hasItem", args = "Pass" } } },
				{ text = "Bribe (10 gold)", next = "gate",
					conditions = { { key = "gold", op = ">=", value = 10 } },
					actions = { { kind = "add", key = "gold", value = -10 }, { kind = "emit", event = "Paid", args = 10 } } },
				{ text = "Bye" }, -- no next: ends the dialogue
			},
		},
		who = { speaker = "Guard", text = "I guard the gate.", next = "hello" },
		gate = { text = "The gate opens.", actions = { { kind = "emit", event = "OpenGate" } } },
	},
}
```

- Conditions: `{ key, op, value }` with `op` one of `==`, `~=`, `>`, `>=`, `<`, `<=`, `truthy`, `falsy` (default `==` when `value` is set, else `truthy`), or `{ check = "predicateName", args = ... }`.
- Actions: `set` (key, value), `add` (key, number), `emit` (event, args). `emit` becomes an effect for the server.
- A node has either `choices` or `next`, never both. A node with neither ends the dialogue when continued.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `DialogueLogic.validate(graph, predicates?)` | `ok, errors, unreachable` | errors and unreachable ids are sorted |
| `DialogueLogic.start(graph, vars?, predicates?)` | `runner, effects` | runs the start node's actions |
| `DialogueLogic.view(runner)` | `View?` | `{ id, speaker, text, choices = { { index, text } }, canContinue }` |
| `DialogueLogic.choose(runner, index)` | `ok, reason, effects` | `index` is the position in the node's full choice list |
| `DialogueLogic.advance(runner)` | `ok, reason, effects` | for nodes with no visible choices |
| `DialogueLogic.evaluate(condition, vars, predicates?)`, `allPass`, `applyActions`, `visibleChoices`, `currentNode`, `stop` | | building blocks |
| `DialogueServer.new(options)` | `Service` | `service:open(player, graphId)`, `close`, `isTalking`, `destroy` |
| `DialogueClient.new({ onNode, onEnd })` | `Client` | `client:choose(index)`, `client:advance()`, `client:close()`, `nodeChanged`, `ended` |

Server options: `graphs` (required), `getVars(player, graphId)` (the table conditions read and actions change, for example the player's saved dialogue flags), `onEffect(player, effect, graphId)`, `onEnd(player, graphId, vars)`, `predicates`, `canTalk(player, graphId)` (checked on open and on every input; use it for a distance check), `remoteFolder` (default `"UrkDialogue"`).

## Example

```lua
local dialogue = DialogueServer.new({
	graphs = { Guard = guard },
	getVars = function(player) return PlayerData.get(player).dialogueFlags end,
	predicates = { hasItem = function(_vars, itemId) return false end }, -- wire to your inventory per player
	onEffect = function(player, effect)
		if effect.event == "OpenGate" then Gate.open(player) end
	end,
	canTalk = function(player) return distanceToGuard(player) < 12 end,
})
prompt.Triggered:Connect(function(player) dialogue:open(player, "Guard") end)
```

Predicates receive only `(vars, args)`. To check per-player data from a predicate, have `getVars` return a table that includes what the predicate needs (for example `vars.inventory`).

## Events and remotes

- `ReplicatedStorage.UrkDialogue.Node` (server to client): a `View`, or `nil` when the dialogue ends.
- `ReplicatedStorage.UrkDialogue.Input` (client to server): `("choose", index)`, `("advance")` or `("close")`, validated and rate limited (8 burst, 4 per second).

## Persistence

Dialogue sessions are not saved. Variables live in the table returned by `getVars`, so save that table with the rest of the player's data.

## Limitations

- One active dialogue per player; opening another closes the first.
- `history` keeps the last 200 visited nodes.
- Graph loops are allowed (a node can link back), so a dialogue can run until the player picks an ending choice or walks away.

## Needs a Studio playtest

Remote flow, `canTalk` checks and client callbacks are unverified outside Studio. Lune tests cover `DialogueLogic`.
