--!strict
local NPC = require("../src/Systems/NPC/NPCLogic")
local t = require("./lib/t")

local v = NPC.vec

local function patrolIndices(patrol: any, steps: number): { number }
	local seen: { number } = {}
	for _ = 1, steps do
		NPC.advancePatrol(patrol)
		table.insert(seen, patrol.index)
	end
	return seen
end

return {
	["distance supports flat measurement"] = function()
		t.near(NPC.distance(v(0, 0, 0), v(3, 4, 0)), 5)
		t.near(NPC.distance(v(0, 0, 0), v(3, 10, 4), true), 5)
		t.truthy(NPC.inRange(v(0, 0, 0), v(0, 0, 5), 5))
		t.falsy(NPC.inRange(v(0, 0, 0), v(0, 0, 5.1), 5))
	end,

	["machine runs hooks and ordered transitions"] = function()
		local log: { string } = {}
		local ctx = { alert = false, calm = false }
		local definition: any = {
			initial = "idle",
			states = {
				idle = {
					enter = function()
						table.insert(log, "enter idle")
					end,
					exit = function()
						table.insert(log, "exit idle")
					end,
				},
				chase = {
					update = function(_ctx: any, _machine: any, dt: number)
						table.insert(log, "update chase " .. tostring(dt))
					end,
				},
				flee = {},
			},
			transitions = {
				{
					from = "idle",
					to = "chase",
					when = function(c: any)
						return c.alert
					end,
				},
				{
					from = "*",
					to = "flee",
					when = function(c: any)
						return c.calm
					end,
				},
			},
		}
		local machine = NPC.newMachine(definition, ctx)
		t.equal(machine.current, "idle")
		t.falsy(NPC.stepMachine(machine, ctx, 0.5))
		t.near(machine.timeInState, 0.5)
		ctx.alert = true
		t.truthy(NPC.stepMachine(machine, ctx, 0.25))
		t.equal(machine.current, "chase")
		t.equal(machine.previous, "idle")
		t.near(machine.timeInState, 0.25)
		ctx.calm = true
		t.truthy(NPC.stepMachine(machine, ctx, 1))
		t.equal(machine.current, "flee")
		t.falsy(NPC.stepMachine(machine, ctx, 1), "never transitions to itself")
		t.deepEqual(log, { "enter idle", "exit idle", "update chase 0.25" })
	end,

	["machine rejects unknown states"] = function()
		t.throws(function()
			NPC.newMachine({ initial = "nope", states = { idle = {} } })
		end)
		t.throws(function()
			NPC.newMachine({
				initial = "idle",
				states = { idle = {} },
				transitions = {
					{
						from = "idle",
						to = "ghost",
						when = function()
							return true
						end,
					},
				},
			})
		end)
		local machine = NPC.newMachine({ initial = "idle", states = { idle = {} } })
		t.falsy(NPC.setState(machine, "ghost"))
		t.equal(machine.current, "idle")
	end,

	["sequence and selector short circuit"] = function()
		local calls = 0
		local function counting(status: any)
			return NPC.action(function()
				calls += 1
				return status
			end)
		end
		local yes = NPC.condition(function()
			return true
		end)
		local no = NPC.condition(function()
			return false
		end)
		t.equal(NPC.tick(NPC.sequence({ yes, counting("success") }), {}), "success")
		t.equal(NPC.tick(NPC.sequence({ no, counting("success") }), {}), "failure")
		t.equal(calls, 1, "sequence stops at the first failure")
		t.equal(NPC.tick(NPC.selector({ no, counting("success") }), {}), "success")
		t.equal(NPC.tick(NPC.selector({ yes, counting("success") }), {}), "success")
		t.equal(calls, 2, "selector stops at the first success")
		t.equal(NPC.tick(NPC.selector({ no, no }), {}), "failure")
	end,

	["running children are resumed with memory"] = function()
		local firstCalls, secondCalls = 0, 0
		local secondStatus = "running"
		local tree = NPC.sequence({
			NPC.action(function()
				firstCalls += 1
				return "success"
			end),
			NPC.action(function()
				secondCalls += 1
				return secondStatus :: any
			end),
		})
		t.equal(NPC.tick(tree, {}), "running")
		t.equal(NPC.tick(tree, {}), "running")
		t.equal(firstCalls, 1, "the finished child is not re-run")
		t.equal(tree.running, 2)
		secondStatus = "success"
		t.equal(NPC.tick(tree, {}), "success")
		t.equal(tree.running, nil)
		t.equal(NPC.tick(tree, {}), "success", "a finished sequence starts over")
		t.equal(firstCalls, 2)
		t.equal(secondCalls, 4)
	end,

	["reactive composites re-check earlier children"] = function()
		local guardCalls = 0
		local children = {
			NPC.condition(function()
				guardCalls += 1
				return true
			end),
			NPC.action(function()
				return "running"
			end),
		}
		local tree = NPC.sequence(children, false)
		NPC.tick(tree, {})
		NPC.tick(tree, {})
		t.equal(guardCalls, 2)
		NPC.reset(tree)
		t.equal(tree.running, nil)
	end,

	["decorators and bad action results"] = function()
		local ok = NPC.condition(function()
			return true
		end)
		local fail = NPC.condition(function()
			return false
		end)
		local busy = NPC.action(function()
			return "running"
		end)
		t.equal(NPC.tick(NPC.invert(ok), {}), "failure")
		t.equal(NPC.tick(NPC.invert(fail), {}), "success")
		t.equal(NPC.tick(NPC.invert(busy), {}), "running")
		t.equal(NPC.tick(NPC.succeed(fail), {}), "success")
		local weird = NPC.action(function()
			return "maybe" :: any
		end)
		t.equal(NPC.tick(weird, {}), "failure")
		t.throws(function()
			NPC.sequence({})
		end)
	end,

	["view cone and perception"] = function()
		local origin, facing = v(0, 0, 0), v(0, 0, -1)
		t.near(NPC.angleTo(origin, facing, v(0, 0, -10)), 0, 1e-6)
		t.near(NPC.angleTo(origin, facing, v(10, 0, 0)), 90, 1e-6)
		t.near(NPC.angleTo(origin, facing, origin), 0)
		t.truthy(NPC.inViewCone(origin, facing, v(5, 0, -10), 90))
		t.falsy(NPC.inViewCone(origin, facing, v(10, 0, -5), 90))
		t.truthy(NPC.inViewCone(origin, facing, v(0, 50, -1), 90, true), "flat ignores height")
		local options = { sightRange = 20, fov = 90, hearingRange = 8 }
		t.equal(NPC.perceive(origin, facing, v(0, 0, -15), options), "seen")
		t.equal(NPC.perceive(origin, facing, v(0, 0, 6), options), "heard")
		t.equal(NPC.perceive(origin, facing, v(0, 0, 15), options), nil)
		t.equal(NPC.perceive(origin, facing, v(0, 0, -25), options), nil)
	end,

	["patrol modes"] = function()
		local points = { v(0, 0, 0), v(1, 0, 0), v(2, 0, 0) }
		t.deepEqual(patrolIndices(NPC.newPatrol(points, "loop"), 4), { 2, 3, 1, 2 })
		t.deepEqual(patrolIndices(NPC.newPatrol(points, "pingpong"), 6), { 2, 3, 2, 1, 2, 3 })
		local once = NPC.newPatrol(points, "once")
		t.equal(NPC.advancePatrol(once), points[2])
		t.equal(NPC.advancePatrol(once), points[3])
		t.equal(NPC.advancePatrol(once), nil)
		t.truthy(once.finished)
		t.equal(NPC.currentWaypoint(once), nil)
		local single = NPC.newPatrol({ v(5, 0, 5) }, "pingpong")
		t.equal(NPC.advancePatrol(single), single.points[1])
		t.throws(function()
			NPC.newPatrol({}, "loop")
		end)
		t.throws(function()
			NPC.newPatrol(points, "zigzag")
		end)
		t.truthy(NPC.reached(v(0, 3, 0), v(0.5, 0, 0), 1, true))
	end,

	["stuck detection"] = function()
		local detector = NPC.newStuckDetector(2, 1)
		t.falsy(NPC.updateStuck(detector, v(0, 0, 0), 0))
		t.falsy(NPC.updateStuck(detector, v(0.5, 0, 0), 1.5))
		t.truthy(NPC.updateStuck(detector, v(0.6, 0, 0), 2))
		t.falsy(NPC.updateStuck(detector, v(3, 0, 0), 2.5), "moving resets the window")
		t.falsy(NPC.updateStuck(detector, v(3, 0, 0), 4))
		t.truthy(NPC.updateStuck(detector, v(3, 0, 0), 4.5))
		t.throws(function()
			NPC.newStuckDetector(0, 1)
		end)
	end,

	["shouldRepath waits for movement and interval"] = function()
		t.truthy(NPC.shouldRepath(nil, v(0, 0, 0), 0, 0, 2, 1))
		t.falsy(NPC.shouldRepath(v(0, 0, 0), v(10, 0, 0), 5, 5.5, 2, 1), "too soon")
		t.truthy(NPC.shouldRepath(v(0, 0, 0), v(10, 0, 0), 5, 6, 2, 1))
		t.falsy(NPC.shouldRepath(v(0, 0, 0), v(1, 0, 0), 5, 9, 2, 1), "goal barely moved")
	end,
}
