# NPC

Behaviour for non-player characters: a finite-state machine, a small behaviour tree, perception tests, patrol routes and stuck detection, all pure and tested. The server adapter moves a Humanoid with PathfindingService, follows waypoints, re-paths when the path is blocked or the goal moves, and recovers when the NPC gets stuck.

| File | Runs on | Role |
| --- | --- | --- |
| `NPCLogic.luau` | anywhere (pure) | FSM, behaviour tree, perception, patrol, stuck detection, re-path rule |
| `NPCServer.luau` | server | pathfinding movement, brain ticking, sight raycasts |

## API (NPCLogic)

| Function | Returns | Notes |
| --- | --- | --- |
| `vec(x, y, z)`, `distance(a, b, flat?)` | | vectors are `{ x, y, z }` tables |
| `newMachine({ initial, states, transitions }, ctx?)` | `Machine` | runs the initial `enter(ctx, machine)` |
| `stepMachine(machine, ctx, dt)` | changed | first matching transition wins; `from = "*"` matches any state; then `update(ctx, machine, dt)` |
| `setState(machine, name, ctx?)` | ok | runs `exit` then `enter` |
| `sequence(children, memory?)`, `selector(children, memory?)` | `BTNode` | `memory` (default true) resumes the running child next tick |
| `condition(fn)`, `action(fn)`, `invert(child)`, `succeed(child)` | `BTNode` | actions return `"success"`, `"failure"` or `"running"` |
| `tick(node, ctx)`, `reset(node)` | `Status` | |
| `angleTo`, `inViewCone(origin, facing, target, fov, flat?)`, `inRange` | | `fov` is the full cone width in degrees |
| `perceive(origin, facing, target, { sightRange, fov, hearingRange?, flat? })` | `"seen"`, `"heard"` or nil | no wall checks; the adapter raycasts |
| `newPatrol(points, "loop" \| "pingpong" \| "once")`, `advancePatrol`, `currentWaypoint`, `reached` | | |
| `newStuckDetector(window, minDistance)`, `updateStuck(d, pos, now)`, `resetStuck` | stuck | |
| `shouldRepath(lastGoal, goal, lastPathTime, now, threshold, minInterval)` | boolean | |

## API (NPCServer)

`NPCServer.new(model, options?)` returns an agent:

| Member | Notes |
| --- | --- |
| `agent:goTo(position)` | returns `"running"` until arrival (`"success"`) or failure; safe to call every tick from a behaviour tree action |
| `agent:moveTo(position)` / `agent:stop()` / `agent:status()` | status: idle, computing, moving, arrived, failed |
| `agent:perceive(part)` / `agent:canSee(part)` | `canSee` adds a raycast so walls block sight |
| `agent:setBrain({ tree = node?, machine = machine?, blackboard = {} })` | ticked at `thinkRate` with `ctx = { agent, blackboard, dt, now }` |
| `agent.statusChanged` | Signal `(status)` |
| `agent:destroy()` | also runs when the model leaves the workspace |

## Config (options, all optional)

| Key | Default | Meaning |
| --- | --- | --- |
| `agent` | `{}` | `PathfindingService:CreatePath` parameters |
| `arriveTolerance` | 3 | studs |
| `repathDistance` / `repathInterval` | 4 / 0.5 | goal-moved re-path rule |
| `stuckWindow` / `stuckDistance` / `maxStuckRetries` | 1.5 / 1 / 3 | stuck handling: jump and re-path, then fail |
| `thinkRate` | 5 | brain ticks per second |
| `sightRange` / `fov` / `hearingRange` | 60 / 120 / 15 | perception |

## Example

```lua
local NPCLogic = require(Systems.NPC.NPCLogic)
local agent = NPCServer.new(workspace.Guard)
local patrol = NPCLogic.newPatrol({ NPCLogic.vec(0, 0, 0), NPCLogic.vec(40, 0, 0) }, "pingpong")
local function asVector(p) return Vector3.new(p.x, p.y, p.z) end

agent:setBrain({
	blackboard = {},
	tree = NPCLogic.selector({
		NPCLogic.sequence({
			NPCLogic.condition(function(ctx)
				ctx.blackboard.target = findVisiblePlayer(ctx.agent) -- uses agent:canSee
				return ctx.blackboard.target ~= nil
			end),
			NPCLogic.action(function(ctx) return ctx.agent:goTo(ctx.blackboard.target.Position) end),
		}, false), -- reactive: re-check the target every tick
		NPCLogic.action(function(ctx)
			local status = ctx.agent:goTo(asVector(NPCLogic.currentWaypoint(patrol)))
			if status == "success" then NPCLogic.advancePatrol(patrol) end
			return "running"
		end),
	}),
})
```

## Events

`agent.statusChanged(status)`. Brains communicate through the `blackboard` table.

## Persistence

None. NPC state is runtime only.

## Limitations

- Pathfinding runs on the server for every agent; for crowds, lower `thinkRate` and reuse goals.
- `goTo` treats a goal within `repathDistance` of a failed goal as unreachable until you call `moveTo` or `stop`.
- No avoidance between NPCs beyond what Roblox pathfinding costs provide.
- Perception has no memory; store "last seen" in the blackboard.

## Needs a Studio playtest

Path computation, `Blocked` re-paths, `MoveToFinished` timing, jump waypoints, network ownership and raycasts are unverified outside Studio. Lune tests cover `NPCLogic`.
