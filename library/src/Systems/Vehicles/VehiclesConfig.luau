--!strict
-- Default settings for Vehicles. Every key is optional when passed to VehiclesLogic, VehiclesServer or VehiclesClient.

return {
	maxSpeed = 80, -- studs per second forwards
	maxReverseSpeed = 30, -- studs per second backwards
	throttleRate = 2.5, -- how fast throttle moves toward the input, per second
	brakeRate = 5, -- how fast throttle returns to zero or reverses, per second
	steerRate = 4, -- how fast steering moves toward the input, per second
	steerReturnRate = 6, -- how fast steering recentres when released, per second
	maxSteerAngle = 30, -- degrees at low speed
	highSpeedSteerFactor = 0.4, -- fraction of maxSteerAngle left at maxSpeed
	grip = 8, -- lateral velocity damping per second while gripping
	driftGrip = 1.5, -- lateral damping per second while drifting
	driftAngle = 15, -- slip angle in degrees that counts as drifting
	minDriftSpeed = 20, -- studs per second needed to drift
	deadzone = 0.15, -- gamepad and touch stick deadzone
	wheelRadius = 1.5, -- studs, for motor angular velocity
	motorTorque = 20000, -- MotorMaxTorque for wheel motors
	speedTolerance = 1.25, -- server allows maxSpeed * tolerance
	speedGrace = 0.5, -- seconds over the limit before a violation
	vehicleTag = "UrkVehicle", -- CollectionService tag on vehicle models
}
