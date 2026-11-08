--!strict
-- Client driving adapter for Vehicles. When the local player sits in the VehicleSeat of a model tagged
-- "UrkVehicle", it reads keyboard, gamepad and the default touch/keyboard controls (VehicleSeat floats),
-- smooths them with VehiclesLogic and drives constraints inside the model:
--   * HingeConstraint (ActuatorType Motor) or CylindricalConstraint (AngularActuatorType Motor)
--     with attribute UrkMotor = true: AngularVelocity follows the throttle. Optional MotorDirection = -1.
--   * HingeConstraint (ActuatorType Servo) with attribute UrkSteer = true: TargetAngle follows the steering.
--     Optional SteerDirection = -1.
-- The driver owns the physics (VehiclesServer hands over network ownership), so changes made here simulate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local VehiclesConfig = require("./VehiclesConfig")
local VehiclesLogic = require("./VehiclesLogic")

export type Client = {
	vehicle: (self: Client) -> Model?,
	controls: (self: Client) -> VehiclesLogic.Controls,
	speed: (self: Client) -> number, -- forward speed in studs per second
	drivingChanged: Signal.Signal, -- (model?)
	destroy: (self: Client) -> (),
}

local VehiclesClient = {}

local function readGamepad(): (number, number, number)
	local rightTrigger, leftTrigger, stickX = 0, 0, 0
	if not UserInputService.GamepadEnabled then
		return rightTrigger, leftTrigger, stickX
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			rightTrigger = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			leftTrigger = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickX = input.Position.X
		end
	end
	return rightTrigger, leftTrigger, stickX
end

local function keyDown(...: Enum.KeyCode): boolean
	for _, keyCode in { ... } do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

function VehiclesClient.new(overrides: { [string]: any }?): Client
	local settings: { [string]: any } = table.clone(VehiclesConfig)
	for key, value in pairs(overrides or {}) do
		settings[key] = value
	end
	local config = VehiclesLogic.resolveConfig(settings)
	local player = Players.LocalPlayer
	local trove = Trove.new()
	local drivingChanged = Signal.new()
	trove:Add(function()
		drivingChanged:DisconnectAll()
	end)

	local driveTrove: Trove.Trove? = nil
	local currentModel: Model? = nil
	local controls: VehiclesLogic.Controls = { throttle = 0, steer = 0 }
	local forwardSpeed = 0

	local function stopDriving()
		if driveTrove then
			driveTrove:Clean()
			driveTrove = nil
		end
		if currentModel then
			currentModel = nil
			controls = { throttle = 0, steer = 0 }
			drivingChanged:Fire(nil)
		end
	end

	local function startDriving(model: Model, seat: VehicleSeat)
		stopDriving()
		local motors: { Instance } = {}
		local steering: { HingeConstraint } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:GetAttribute("UrkMotor") == true then
				if descendant:IsA("HingeConstraint") or descendant:IsA("CylindricalConstraint") then
					table.insert(motors, descendant)
				end
			elseif descendant:GetAttribute("UrkSteer") == true and descendant:IsA("HingeConstraint") then
				table.insert(steering, descendant)
			end
		end
		local localTrove = Trove.new()
		driveTrove = localTrove
		currentModel = model

		local function applyMotors(angularVelocity: number)
			for _, motor in motors do
				local direction = motor:GetAttribute("MotorDirection")
				local signed = angularVelocity * (if type(direction) == "number" then direction else 1)
				-- HingeConstraint and CylindricalConstraint share these property names.
				local joint = motor :: any
				joint.AngularVelocity = signed
				joint.MotorMaxTorque = settings.motorTorque
			end
		end

		localTrove:Add(function()
			applyMotors(0)
			for _, hinge in steering do
				hinge.TargetAngle = 0
			end
		end)

		localTrove:Connect(RunService.Heartbeat, function(dt: number)
			local keyboard = VehiclesLogic.mapKeyboard({
				forward = keyDown(Enum.KeyCode.W, Enum.KeyCode.Up),
				back = keyDown(Enum.KeyCode.S, Enum.KeyCode.Down),
				left = keyDown(Enum.KeyCode.A, Enum.KeyCode.Left),
				right = keyDown(Enum.KeyCode.D, Enum.KeyCode.Right),
			})
			local rightTrigger, leftTrigger, stickX = readGamepad()
			local gamepad = VehiclesLogic.mapGamepad(rightTrigger, leftTrigger, stickX, config.deadzone)
			-- The default control scripts fill these from the touch thumbstick as well as the keyboard.
			local seatControls = { throttle = seat.ThrottleFloat, steer = seat.SteerFloat }
			local input = VehiclesLogic.combine({ keyboard, gamepad, seatControls })
			controls = VehiclesLogic.smooth(controls, input, config, dt)

			local root = seat.AssemblyRootPart or seat
			local velocity = root.AssemblyLinearVelocity
			local forward = seat.CFrame.LookVector
			local right = seat.CFrame.RightVector
			forwardSpeed = forward:Dot(velocity)
			local lateral = right:Dot(velocity)

			local target = VehiclesLogic.targetSpeed(controls.throttle, config)
			applyMotors(VehiclesLogic.wheelAngularVelocity(target, config.wheelRadius))
			local angle = VehiclesLogic.steerAngle(controls.steer, forwardSpeed, config)
			for _, hinge in steering do
				local direction = hinge:GetAttribute("SteerDirection")
				hinge.TargetAngle = angle * (if type(direction) == "number" then direction else 1)
			end

			local handbrake = keyDown(Enum.KeyCode.Space, Enum.KeyCode.ButtonX)
			local newLateral = VehiclesLogic.applyGrip(forwardSpeed, lateral, config, dt, handbrake)
			root.AssemblyLinearVelocity = velocity + right * (newLateral - lateral)
		end)
		drivingChanged:Fire(model)
	end

	local function onSeatChanged(humanoid: Humanoid)
		local seat = humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") then
			local model = seat:FindFirstAncestorOfClass("Model")
			while model and not CollectionService:HasTag(model, settings.vehicleTag) do
				model = model:FindFirstAncestorOfClass("Model")
			end
			if model then
				startDriving(model, seat)
				return
			end
		end
		stopDriving()
	end

	local characterTrove = Trove.new()
	trove:Add(characterTrove)

	local function onCharacter(character: Model)
		stopDriving()
		characterTrove:Clean()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			characterTrove:Connect(humanoid:GetPropertyChangedSignal("SeatPart"), function()
				onSeatChanged(humanoid)
			end)
			onSeatChanged(humanoid)
		end
	end

	trove:Connect(player.CharacterAdded, onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	trove:Add(stopDriving)

	local client = {} :: Client
	client.drivingChanged = drivingChanged

	function client.vehicle(_self: Client): Model?
		return currentModel
	end

	function client.controls(_self: Client): VehiclesLogic.Controls
		return controls
	end

	function client.speed(_self: Client): number
		return forwardSpeed
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return VehiclesClient
