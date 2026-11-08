--!strict
-- Server adapter for Vehicles. For every model tagged "UrkVehicle" (or registered with :add):
--   * Seat ownership: the model's "OwnerUserId" and "Locked" attributes decide who may drive;
--     anyone else is ejected from the VehicleSeat.
--   * Network ownership goes to the driver for responsive physics and back to the server on exit.
--   * Speed validation: sustained speeds above maxSpeed * speedTolerance are clamped, ownership is
--     taken back by the server and `flagged` fires.
-- Driving itself (motor and steering constraints) is done by VehiclesClient on the driver's machine.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")
local VehiclesConfig = require("./VehiclesConfig")
local VehiclesLogic = require("./VehiclesLogic")

export type Service = {
	add: (self: Service, model: Model) -> (),
	remove: (self: Service, model: Model) -> (),
	driverOf: (self: Service, model: Model) -> Player?,
	flagged: Signal.Signal, -- (player, model, speed)
	entered: Signal.Signal, -- (player, model)
	exited: Signal.Signal, -- (player, model)
	destroy: (self: Service) -> (),
}

type Entry = {
	trove: Trove.Trove,
	seat: VehicleSeat,
	root: BasePart,
	driver: Player?,
	monitor: VehiclesLogic.SpeedMonitor,
	flaggedDriver: boolean,
}

local VehiclesServer = {}

local function setOwner(root: BasePart, player: Player?)
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(player)
	end
end

function VehiclesServer.new(overrides: { [string]: any }?): Service
	local settings: { [string]: any } = table.clone(VehiclesConfig)
	for key, value in overrides or {} do
		settings[key] = value
	end
	local config = VehiclesLogic.resolveConfig(settings)
	local trove = Trove.new()
	local flagged = Signal.new()
	local entered = Signal.new()
	local exited = Signal.new()
	trove:Add(function()
		flagged:DisconnectAll()
		entered:DisconnectAll()
		exited:DisconnectAll()
	end)
	local entries: { [Model]: Entry } = {}

	local function onOccupantChanged(model: Model, entry: Entry)
		local humanoid = entry.seat.Occupant
		local player = if humanoid and humanoid.Parent then Players:GetPlayerFromCharacter(humanoid.Parent) else nil
		local previous = entry.driver
		if player == previous then
			return
		end
		if player then
			local ownerId = model:GetAttribute("OwnerUserId")
			local ownership = {
				ownerId = if ownerId ~= nil then tostring(ownerId) else nil,
				locked = model:GetAttribute("Locked") == true,
			}
			if not VehiclesLogic.canDrive(ownership, tostring(player.UserId)) then
				local weld = entry.seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy() -- eject the player who may not drive
				end
				if humanoid then
					humanoid.Jump = true
				end
				return
			end
		end
		entry.driver = player
		entry.flaggedDriver = false
		entry.monitor = VehiclesLogic.newSpeedMonitor()
		local owner = VehiclesLogic.networkOwner(if player then tostring(player.UserId) else nil, false)
		setOwner(entry.root, if owner then player else nil)
		model:SetAttribute("DriverUserId", if player then player.UserId else nil)
		if previous then
			exited:Fire(previous, model)
		end
		if player then
			entered:Fire(player, model)
		end
	end

	local service = {} :: Service
	service.flagged = flagged
	service.entered = entered
	service.exited = exited

	function service.add(_self: Service, model: Model)
		if entries[model] then
			return
		end
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		local root = model.PrimaryPart or seat
		if seat == nil or root == nil then
			warn("VehiclesServer: " .. model:GetFullName() .. " needs a VehicleSeat")
			return
		end
		local entry: Entry = {
			trove = Trove.new(),
			seat = seat,
			root = root,
			driver = nil,
			monitor = VehiclesLogic.newSpeedMonitor(),
			flaggedDriver = false,
		}
		entries[model] = entry
		setOwner(root, nil)
		entry.trove:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
			onOccupantChanged(model, entry)
		end)
		entry.trove:Connect(model.AncestryChanged, function()
			if not model:IsDescendantOf(workspace) then
				service:remove(model)
			end
		end)
	end

	function service.remove(_self: Service, model: Model)
		local entry = entries[model]
		if entry then
			entries[model] = nil
			entry.trove:Clean()
		end
	end

	function service.driverOf(_self: Service, model: Model): Player?
		local entry = entries[model]
		return if entry then entry.driver else nil
	end

	trove:Connect(RunService.Heartbeat, function(dt: number)
		for model, entry in entries do
			local driver = entry.driver
			if driver == nil or entry.flaggedDriver then
				continue -- a flagged car stays server-owned until the driver gets out
			end
			local velocity = entry.root.AssemblyLinearVelocity
			local speed = velocity.Magnitude
			if VehiclesLogic.updateSpeedMonitor(entry.monitor, speed, config, dt) == "violation" then
				-- Take physics back from the client and slow the car to the limit.
				entry.flaggedDriver = true
				setOwner(entry.root, nil)
				local limit = VehiclesLogic.speedLimit(config) / settings.speedTolerance
				entry.root.AssemblyLinearVelocity = velocity.Unit * limit
				flagged:Fire(driver, model, speed)
			end
		end
	end)

	local tag = settings.vehicleTag
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("Model") then
			service:add(instance)
		end
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(tag), function(instance: Instance)
		if instance:IsA("Model") then
			service:add(instance)
		end
	end)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(tag), function(instance: Instance)
		if instance:IsA("Model") then
			service:remove(instance)
		end
	end)

	function service.destroy(_self: Service)
		for model in table.clone(entries) do
			service:remove(model)
		end
		trove:Clean()
	end

	return service
end

return VehiclesServer
