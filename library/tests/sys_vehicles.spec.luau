--!strict
local Vehicles = require("../src/Systems/Vehicles/VehiclesLogic")
local t = require("./lib/t")

local CONFIG = Vehicles.resolveConfig()

return {
	["resolveConfig fills defaults and rejects bad values"] = function()
		local config = Vehicles.resolveConfig({ maxSpeed = 120, grip = -2, deadzone = 3, wheelRadius = 0 })
		t.equal(config.maxSpeed, 120)
		t.equal(config.grip, 8)
		t.equal(config.deadzone, 0.95, "deadzone is capped")
		t.equal(config.wheelRadius, 1.5)
		t.equal(CONFIG.maxReverseSpeed, 30)
	end,

	["approach never overshoots"] = function()
		t.near(Vehicles.approach(0, 1, 2, 0.1), 0.2)
		t.equal(Vehicles.approach(0.9, 1, 2, 0.1), 1)
		t.near(Vehicles.approach(1, -1, 5, 0.1), 0.5)
		t.equal(Vehicles.approach(0.5, 0, 5, -1), 0.5, "negative dt does nothing")
	end,

	["smooth eases in and brakes faster"] = function()
		local first = Vehicles.smooth({ throttle = 0, steer = 0 }, { throttle = 1, steer = 1 }, CONFIG, 0.1)
		t.near(first.throttle, 0.25)
		t.near(first.steer, 0.4)
		local released = Vehicles.smooth({ throttle = 0.5, steer = 0.4 }, { throttle = 0, steer = 0 }, CONFIG, 0.1)
		t.near(released.throttle, 0)
		t.near(released.steer, 0)
		local reversing = Vehicles.smooth({ throttle = 0.5, steer = 0 }, { throttle = -1, steer = 0 }, CONFIG, 0.05)
		t.near(reversing.throttle, 0.25, 1e-9, "reversing uses the brake rate")
		local wild = { throttle = 9, steer = math.sqrt(-1) }
		local clamped = Vehicles.smooth({ throttle = 0, steer = 0 }, wild, CONFIG, 10)
		t.equal(clamped.throttle, 1)
		t.equal(clamped.steer, 0)
	end,

	["target speed covers forward and reverse"] = function()
		t.equal(Vehicles.targetSpeed(1, CONFIG), 80)
		t.equal(Vehicles.targetSpeed(0.5, CONFIG), 40)
		t.equal(Vehicles.targetSpeed(-1, CONFIG), -30)
		t.equal(Vehicles.targetSpeed(3, CONFIG), 80)
	end,

	["steering narrows with speed"] = function()
		t.near(Vehicles.steerAngle(1, 0, CONFIG), 30)
		t.near(Vehicles.steerAngle(1, 40, CONFIG), 21)
		t.near(Vehicles.steerAngle(1, 80, CONFIG), 12)
		t.near(Vehicles.steerAngle(-1, 200, CONFIG), -12)
		t.near(Vehicles.steerAngle(2, 0, CONFIG), 30)
	end,

	["wheel angular velocity"] = function()
		t.near(Vehicles.wheelAngularVelocity(30, 1.5), 20)
		t.equal(Vehicles.wheelAngularVelocity(30, 0), 0)
	end,

	["drift detection and grip"] = function()
		t.near(Vehicles.slipAngle(10, 10), 45)
		t.equal(Vehicles.slipAngle(0, 0), 0)
		t.truthy(Vehicles.isDrifting(30, 10, CONFIG))
		t.falsy(Vehicles.isDrifting(10, 10, CONFIG), "too slow")
		t.falsy(Vehicles.isDrifting(50, 5, CONFIG), "slip angle too small")
		t.near(Vehicles.applyGrip(50, 5, CONFIG, 0.1), 5 * math.exp(-0.8), 1e-9)
		t.near(Vehicles.applyGrip(30, 10, CONFIG, 0.1), 10 * math.exp(-0.15), 1e-9)
		t.near(Vehicles.applyGrip(50, 5, CONFIG, 0.1, true), 5 * math.exp(-0.15), 1e-9)
	end,

	["capVelocity keeps direction"] = function()
		t.deepEqual(Vehicles.capVelocity({ x = 3, y = 4, z = 0 }, 10), { x = 3, y = 4, z = 0 })
		local capped = Vehicles.capVelocity({ x = 30, y = 40, z = 0 }, 10)
		t.near(capped.x, 6)
		t.near(capped.y, 8)
		t.deepEqual(Vehicles.capVelocity({ x = 0, y = 0, z = 0 }, 0), { x = 0, y = 0, z = 0 })
	end,

	["speed monitor flags sustained speeding"] = function()
		local monitor = Vehicles.newSpeedMonitor()
		t.equal(Vehicles.speedLimit(CONFIG), 100)
		t.equal(Vehicles.updateSpeedMonitor(monitor, 50, CONFIG, 0.1), "ok")
		t.equal(Vehicles.updateSpeedMonitor(monitor, 120, CONFIG, 0.3), "over")
		t.equal(Vehicles.updateSpeedMonitor(monitor, 120, CONFIG, 0.3), "violation")
		t.equal(monitor.violations, 1)
		t.equal(monitor.overFor, 0)
		t.equal(Vehicles.updateSpeedMonitor(monitor, 120, CONFIG, 0.3), "over")
		t.equal(Vehicles.updateSpeedMonitor(monitor, 90, CONFIG, 0.1), "ok")
		t.equal(monitor.overFor, 0, "dropping under the limit resets the timer")
		t.falsy(Vehicles.isSpeedValid(math.sqrt(-1), CONFIG))
	end,

	["seat ownership and network owner"] = function()
		t.falsy(Vehicles.canDrive({ ownerId = "1", locked = true }, "2"))
		t.truthy(Vehicles.canDrive({ ownerId = "1", locked = true }, "1"))
		t.truthy(Vehicles.canDrive({ ownerId = "1", locked = false }, "2"))
		t.truthy(Vehicles.canDrive({ locked = true }, "2"))
		t.equal(Vehicles.networkOwner("1", false), "1")
		t.equal(Vehicles.networkOwner("1", true), nil)
		t.equal(Vehicles.networkOwner(nil, false), nil)
	end,

	["input mapping for every device"] = function()
		t.equal(Vehicles.applyDeadzone(0.1, 0.15), 0)
		t.near(Vehicles.applyDeadzone(1, 0.15), 1)
		t.near(Vehicles.applyDeadzone(-0.575, 0.15), -0.5)
		t.near(Vehicles.applyDeadzone(5, 0.15), 1)
		t.deepEqual(Vehicles.mapKeyboard({ forward = true, left = true }), { throttle = 1, steer = -1 })
		t.deepEqual(Vehicles.mapKeyboard({ forward = true, back = true }), { throttle = 0, steer = 0 })
		local pad = Vehicles.mapGamepad(1, 0.25, 0.1, 0.15)
		t.near(pad.throttle, 0.75)
		t.equal(pad.steer, 0)
		t.deepEqual(Vehicles.mapGamepad(0, 1, -1, 0.15), { throttle = -1, steer = -1 })
		local touch = Vehicles.mapTouch(0.5, 1, 0.15)
		t.near(touch.throttle, 1)
		t.near(touch.steer, 0.35 / 0.85)
		local merged = Vehicles.combine({
			{ throttle = 0.5, steer = 0 },
			{ throttle = -0.8, steer = 0.2 },
			{ throttle = 0.1, steer = -0.3 },
		})
		t.deepEqual(merged, { throttle = -0.8, steer = -0.3 })
	end,
}
