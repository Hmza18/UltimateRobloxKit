--!strict
-- Vehicle control maths. Pure Luau: dt and inputs are passed in, vectors are { x, y, z } tables.
-- Covers input smoothing, speed targets, speed-sensitive steering, wheel motor speeds, an arcade
-- grip/drift model, server speed checks, seat ownership rules and keyboard/gamepad/touch mapping.

local VehiclesConfig = require("./VehiclesConfig")

export type Config = {
	maxSpeed: number,
	maxReverseSpeed: number,
	throttleRate: number,
	brakeRate: number,
	steerRate: number,
	steerReturnRate: number,
	maxSteerAngle: number,
	highSpeedSteerFactor: number,
	grip: number,
	driftGrip: number,
	driftAngle: number,
	minDriftSpeed: number,
	deadzone: number,
	wheelRadius: number,
	speedTolerance: number,
	speedGrace: number,
}

export type Controls = { throttle: number, steer: number } -- both in [-1, 1]
export type Vec3 = { x: number, y: number, z: number }
export type Keys = { forward: boolean?, back: boolean?, left: boolean?, right: boolean? }
export type SpeedMonitor = { overFor: number, violations: number }
export type Ownership = { ownerId: string?, locked: boolean? }

local NUMBER_KEYS = {
	"maxSpeed",
	"maxReverseSpeed",
	"throttleRate",
	"brakeRate",
	"steerRate",
	"steerReturnRate",
	"maxSteerAngle",
	"highSpeedSteerFactor",
	"grip",
	"driftGrip",
	"driftAngle",
	"minDriftSpeed",
	"deadzone",
	"wheelRadius",
	"speedTolerance",
	"speedGrace",
}

local Vehicles = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clampUnit(value: number): number
	if not isFinite(value) then
		return 0
	end
	return math.clamp(value, -1, 1)
end

function Vehicles.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local result: { [string]: any } = {}
	for _, key in NUMBER_KEYS do
		local value = source[key]
		result[key] = if isFinite(value) and value >= 0 then value else (VehiclesConfig :: any)[key]
	end
	if result.wheelRadius <= 0 then
		result.wheelRadius = VehiclesConfig.wheelRadius
	end
	result.deadzone = math.min(result.deadzone, 0.95)
	return result :: any
end

-- Moves `current` toward `target` by at most `rate * dt`.
function Vehicles.approach(current: number, target: number, rate: number, dt: number): number
	local step = rate * math.max(0, dt)
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

-- Smooths raw controls. Throttle eases in at throttleRate and drops or reverses at brakeRate;
-- steering eases in at steerRate and recentres at steerReturnRate.
function Vehicles.smooth(current: Controls, input: Controls, config: Config, dt: number): Controls
	local throttleTarget = clampUnit(input.throttle)
	local steerTarget = clampUnit(input.steer)
	local sameDirection = throttleTarget * current.throttle >= 0
	local easingIn = sameDirection and math.abs(throttleTarget) > math.abs(current.throttle)
	local throttleRate = if easingIn then config.throttleRate else config.brakeRate
	local steerRate = if steerTarget == 0 then config.steerReturnRate else config.steerRate
	return {
		throttle = Vehicles.approach(current.throttle, throttleTarget, throttleRate, dt),
		steer = Vehicles.approach(current.steer, steerTarget, steerRate, dt),
	}
end

function Vehicles.targetSpeed(throttle: number, config: Config): number
	local value = clampUnit(throttle)
	if value >= 0 then
		return value * config.maxSpeed
	end
	return value * config.maxReverseSpeed
end

-- Steering angle in degrees. It shrinks linearly to highSpeedSteerFactor of the maximum at maxSpeed.
function Vehicles.steerAngle(steer: number, speed: number, config: Config): number
	local fraction = if config.maxSpeed > 0 then math.clamp(math.abs(speed) / config.maxSpeed, 0, 1) else 0
	local scale = 1 + (config.highSpeedSteerFactor - 1) * fraction
	return clampUnit(steer) * config.maxSteerAngle * scale
end

-- Motor angular velocity (radians per second) that rolls a wheel of `radius` at `speed`.
function Vehicles.wheelAngularVelocity(speed: number, radius: number): number
	if radius <= 0 then
		return 0
	end
	return speed / radius
end

-- Slip angle in degrees between the car's heading and its travel direction.
function Vehicles.slipAngle(forwardSpeed: number, lateralSpeed: number): number
	local forward, lateral = math.abs(forwardSpeed), math.abs(lateralSpeed)
	if lateral == 0 then
		return 0
	elseif forward == 0 then
		return 90
	end
	return math.deg(math.atan(lateral / forward))
end

function Vehicles.isDrifting(forwardSpeed: number, lateralSpeed: number, config: Config): boolean
	local speed = math.sqrt(forwardSpeed * forwardSpeed + lateralSpeed * lateralSpeed)
	return speed >= config.minDriftSpeed and Vehicles.slipAngle(forwardSpeed, lateralSpeed) >= config.driftAngle
end

-- Damps sideways speed: grip while gripping, driftGrip while drifting (or when `handbrake` is held).
function Vehicles.applyGrip(
	forwardSpeed: number,
	lateralSpeed: number,
	config: Config,
	dt: number,
	handbrake: boolean?
): number
	local drifting = handbrake == true or Vehicles.isDrifting(forwardSpeed, lateralSpeed, config)
	local grip = if drifting then config.driftGrip else config.grip
	return lateralSpeed * math.exp(-grip * math.max(0, dt))
end

-- Scales a velocity down to `maxSpeed` if it is faster. Direction is kept.
function Vehicles.capVelocity(velocity: Vec3, maxSpeed: number): Vec3
	local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
	if speed <= maxSpeed or speed == 0 then
		return { x = velocity.x, y = velocity.y, z = velocity.z }
	end
	local scale = maxSpeed / speed
	return { x = velocity.x * scale, y = velocity.y * scale, z = velocity.z * scale }
end

function Vehicles.speedLimit(config: Config): number
	return math.max(config.maxSpeed, config.maxReverseSpeed) * config.speedTolerance
end

function Vehicles.isSpeedValid(speed: number, config: Config): boolean
	return isFinite(speed) and speed <= Vehicles.speedLimit(config)
end

function Vehicles.newSpeedMonitor(): SpeedMonitor
	return { overFor = 0, violations = 0 }
end

-- Tracks how long a vehicle has been over the speed limit. Returns "ok", "over" (within the grace time)
-- or "violation" (over for at least speedGrace seconds; the timer then restarts).
function Vehicles.updateSpeedMonitor(monitor: SpeedMonitor, speed: number, config: Config, dt: number): string
	if Vehicles.isSpeedValid(speed, config) then
		monitor.overFor = 0
		return "ok"
	end
	monitor.overFor += math.max(0, dt)
	if monitor.overFor >= config.speedGrace then
		monitor.overFor = 0
		monitor.violations += 1
		return "violation"
	end
	return "over"
end

-- Seat ownership: anyone may drive an unowned or unlocked vehicle; a locked one only by its owner.
function Vehicles.canDrive(vehicle: Ownership, playerId: string): boolean
	if not vehicle.locked or vehicle.ownerId == nil then
		return true
	end
	return vehicle.ownerId == playerId
end

-- Who should simulate the vehicle: the driver for responsive controls, or the server (nil) when there is
-- no driver or the driver has been flagged for speed violations.
function Vehicles.networkOwner(driverId: string?, flagged: boolean): string?
	if driverId == nil or flagged then
		return nil
	end
	return driverId
end

-- Input mapping -------------------------------------------------------------------------------------

-- Removes the stick deadzone and rescales the rest to the full range.
function Vehicles.applyDeadzone(value: number, deadzone: number): number
	local v = clampUnit(value)
	local magnitude = math.abs(v)
	if magnitude <= deadzone then
		return 0
	end
	return math.sign(v) * (magnitude - deadzone) / (1 - deadzone)
end

function Vehicles.mapKeyboard(keys: Keys): Controls
	local throttle = (if keys.forward then 1 else 0) - (if keys.back then 1 else 0)
	local steer = (if keys.right then 1 else 0) - (if keys.left then 1 else 0)
	return { throttle = throttle, steer = steer }
end

-- Right trigger accelerates, left trigger brakes and reverses, the left stick steers.
function Vehicles.mapGamepad(rightTrigger: number, leftTrigger: number, stickX: number, deadzone: number): Controls
	local throttle = math.clamp(rightTrigger, 0, 1) - math.clamp(leftTrigger, 0, 1)
	return { throttle = clampUnit(throttle), steer = Vehicles.applyDeadzone(stickX, deadzone) }
end

-- A touch thumbstick: x is right, y is forward (both -1 to 1).
function Vehicles.mapTouch(x: number, y: number, deadzone: number): Controls
	return { throttle = Vehicles.applyDeadzone(y, deadzone), steer = Vehicles.applyDeadzone(x, deadzone) }
end

-- Merges several devices: on each axis the input with the largest magnitude wins.
function Vehicles.combine(inputs: { Controls }): Controls
	local result: Controls = { throttle = 0, steer = 0 }
	for _, input in inputs do
		if math.abs(input.throttle) > math.abs(result.throttle) then
			result.throttle = input.throttle
		end
		if math.abs(input.steer) > math.abs(result.steer) then
			result.steer = input.steer
		end
	end
	return result
end

return Vehicles
