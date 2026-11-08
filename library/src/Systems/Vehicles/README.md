# Vehicles

Arcade vehicle driving built on Roblox constraints. The maths is pure and tested: input smoothing, speed targets, speed-sensitive steering, wheel motor speeds, a grip and drift model, speed validation, seat ownership rules and keyboard, gamepad and touch mapping. The server owns seat rules, network ownership and speed checks; the driver's client drives the constraints.

| File | Runs on | Role |
| --- | --- | --- |
| `VehiclesLogic.luau` | anywhere (pure) | control maths, drift, speed monitor, ownership, input mapping |
| `VehiclesServer.luau` | server | seat ownership, network ownership hand-off, speed validation |
| `VehiclesClient.luau` | client | input reading, smoothing, HingeConstraint / CylindricalConstraint driving |
| `VehiclesConfig.luau` | anywhere | defaults |

## Building a vehicle

1. A Model tagged `UrkVehicle` with a `VehicleSeat` (set the model's `PrimaryPart` to the chassis).
2. Wheel joints: `HingeConstraint` with `ActuatorType = Motor` (or `CylindricalConstraint` with `AngularActuatorType = Motor` for suspension) and the attribute `UrkMotor = true`. Add `MotorDirection = -1` on wheels whose axis points the other way.
3. Steering joints: `HingeConstraint` with `ActuatorType = Servo`, attribute `UrkSteer = true` (optional `SteerDirection = -1`). Set `AngularSpeed` and `ServoMaxTorque` on the hinge to taste.
4. Optional model attributes: `OwnerUserId` (number) and `Locked` (bool). The server sets `DriverUserId`.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `VehiclesLogic.resolveConfig(overrides?)` | `Config` | |
| `approach(current, target, rate, dt)`, `smooth(controls, input, config, dt)` | | throttle eases in at `throttleRate`, brakes and reverses at `brakeRate`; steering recentres at `steerReturnRate` |
| `targetSpeed(throttle, config)`, `steerAngle(steer, speed, config)`, `wheelAngularVelocity(speed, radius)` | | |
| `slipAngle`, `isDrifting`, `applyGrip(forward, lateral, config, dt, handbrake?)` | | exponential lateral damping (`grip`, or `driftGrip` while drifting) |
| `capVelocity(v, max)`, `speedLimit`, `isSpeedValid`, `newSpeedMonitor`, `updateSpeedMonitor` | | `"ok"`, `"over"`, `"violation"` after `speedGrace` seconds |
| `canDrive({ ownerId?, locked? }, playerId)`, `networkOwner(driverId?, flagged)` | | |
| `applyDeadzone`, `mapKeyboard`, `mapGamepad(rt, lt, stickX, deadzone)`, `mapTouch(x, y, deadzone)`, `combine(list)` | `Controls` | |
| `VehiclesServer.new(overrides?)` | `Service` | `add(model)`, `remove(model)`, `driverOf(model)`, `entered`, `exited`, `flagged`, `destroy` |
| `VehiclesClient.new(overrides?)` | `Client` | `vehicle()`, `controls()`, `speed()`, `drivingChanged`, `destroy` |

## Config (`VehiclesConfig.luau`)

| Key | Default | Key | Default |
| --- | --- | --- | --- |
| `maxSpeed` | 80 | `maxReverseSpeed` | 30 |
| `throttleRate` / `brakeRate` | 2.5 / 5 | `steerRate` / `steerReturnRate` | 4 / 6 |
| `maxSteerAngle` | 30 | `highSpeedSteerFactor` | 0.4 |
| `grip` / `driftGrip` | 8 / 1.5 | `driftAngle` / `minDriftSpeed` | 15 / 20 |
| `deadzone` | 0.15 | `wheelRadius` | 1.5 |
| `motorTorque` | 20000 | `speedTolerance` / `speedGrace` | 1.25 / 0.5 |
| `vehicleTag` | `"UrkVehicle"` | | |

Use the same overrides on the server and the client so speed checks match the car's tuning.

## Example

```lua
-- Server
local vehicles = VehiclesServer.new({ maxSpeed = 100 })
vehicles.flagged:Connect(function(player, model, speed)
	warn(player.Name, "too fast in", model.Name, speed)
end)
-- Client (StarterPlayerScripts)
local driving = VehiclesClient.new({ maxSpeed = 100 })
driving.drivingChanged:Connect(function(model) speedometer.Visible = model ~= nil end)
```

## Input

| Device | Throttle | Steer | Handbrake |
| --- | --- | --- | --- |
| Keyboard | W / Up, S / Down | A / Left, D / Right | Space |
| Gamepad | R2 forward, L2 brake and reverse | left stick | X |
| Touch | default thumbstick through `VehicleSeat.ThrottleFloat` / `SteerFloat` | same | none |

## Events

`entered(player, model)`, `exited(player, model)`, `flagged(player, model, speed)` on the server; `drivingChanged(model?)` on the client.

## Persistence

None. Ownership attributes are yours to set from saved data.

## Limitations

- The drift model nudges the chassis velocity every frame; it is arcade handling, not a tyre simulation.
- A flagged car stays server-owned (and stops responding to the driver's input) until the driver gets out.
- The touch path relies on the default control scripts writing VehicleSeat floats; custom touch controls should call `VehiclesLogic.mapTouch` and be merged in your own client code.
- Speed checks catch sustained speeding only; short bursts under `speedGrace` are allowed.

## Verify in the Roblox docs / Studio

- `CylindricalConstraint` motor properties (`AngularActuatorType`, `AngularVelocity`, `MotorMaxTorque`) and `HingeConstraint` servo properties (`TargetAngle`, `AngularSpeed`, `ServoMaxTorque`).
- That `VehicleSeat.ThrottleFloat` and `SteerFloat` are fed by the mobile thumbstick in your control setup.
- Ejecting a player who may not drive by destroying the seat's `SeatWeld` (and setting `Humanoid.Jump`).

## Needs a Studio playtest

All of `VehiclesServer.luau` and `VehiclesClient.luau` (seat events, network ownership, constraints, handling feel). Lune tests cover `VehiclesLogic`.
