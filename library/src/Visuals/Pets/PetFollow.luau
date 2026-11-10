--!strict
-- Pet followers: anchored pet Models that trail an owner in a formation (rows, arc, circle,
-- orbit) with spring smoothing, turn smoothing, a walk bob and ground alignment.
--
-- All followers share the single pet job (PetAnimator.addStepper). Each pet's follow step runs in
-- a round-robin bucket at the profile's petUpdateHz, and the ground raycast is cached per pet and
-- refreshed on a schedule or after the pet has moved, never every frame.
--
-- Client-side visual pets only. Where a pet is on the server, who owns it and how other players
-- see it (replication) is the game's job: run a follower on each client for the pets it shows.
--
-- Used through Pets.follow; see README.md. NOT run in Studio.

local Workspace = game:GetService("Workspace")

local Host = require("../Runtime/Host")
local PetAnimator = require("./PetAnimator")
local PetsLogic = require("./PetsLogic")

export type Owner = Model | BasePart | (() -> CFrame?)

export type Options = {
	mode: PetsLogic.FormationMode?, -- default "rows"
	spacing: number?,
	distance: number?,
	perRow: number?,
	orbitSpeed: number?,
	frequency: number?, -- follow spring in Hz (default 2.2)
	maxSpeed: number?,
	teleportDistance: number?,
	hover: number?, -- hover height for flying pets (default 0: walk on the ground)
	ground: boolean?, -- align to the ground with raycasts (default true)
	groundDepth: number?, -- how far down to look (default 40)
	groundInterval: number?, -- seconds between ground samples per pet (default 0.4)
	ownerHeight: number?, -- owner pivot height above its feet, used when no ground is found (default 3)
	walkBob: boolean?, -- default true
	exclude: { Instance }?, -- extra instances the ground raycast ignores
	animator: PetAnimator.Options?, -- options for animators the follower creates
}

export type Follower = {
	add: (self: Follower, pet: Model) -> (),
	remove: (self: Follower, pet: Model) -> (),
	setMode: (self: Follower, mode: PetsLogic.FormationMode) -> (),
	pets: (self: Follower) -> { Model },
	isDestroyed: (self: Follower) -> boolean,
	destroy: (self: Follower) -> (),
}

type Pet = {
	model: Model,
	animator: PetAnimator.PetAnimator,
	owned: boolean, -- the follower created the animator
	state: PetsLogic.FollowState,
	radius: number,
	pivotHeight: number,
	phase: number,
	pending: number,
	cache: PetsLogic.GroundCache?,
	groundY: number?,
	normal: { number }?,
}

type Record = {
	resolve: () -> CFrame?,
	ownerInstance: Instance?,
	options: Options,
	mode: PetsLogic.FormationMode,
	pets: { Pet },
	params: RaycastParams,
	time: number,
	destroyed: boolean,
}

local PetFollow = {}

local followers: { Record } = {}
local removeStepper: (() -> ())? = nil

local function yawOf(cframe: CFrame): number
	local _, yaw = cframe:ToOrientation()
	return math.deg(yaw)
end

local function refreshFilter(record: Record)
	local list: { Instance } = {}
	for _, pet in record.pets do
		table.insert(list, pet.model)
	end
	if record.ownerInstance then
		table.insert(list, record.ownerInstance)
	end
	local extra: { Instance } = record.options.exclude or {}
	for _, instance in extra do
		table.insert(list, instance)
	end
	record.params.FilterDescendantsInstances = list
end

local function release(pet: Pet)
	if pet.owned and not pet.animator:isDestroyed() then
		pet.animator:destroy(false)
	end
end

local function destroy(record: Record)
	if record.destroyed then
		return
	end
	record.destroyed = true
	for _, pet in record.pets do
		release(pet)
	end
	table.clear(record.pets)
	local index = table.find(followers, record)
	if index then
		table.remove(followers, index)
	end
	if #followers == 0 and removeStepper then
		removeStepper()
		removeStepper = nil
	end
end

local function stepFollower(record: Record, dt: number, frame: number)
	local ownerCFrame = record.resolve()
	if ownerCFrame == nil then
		destroy(record) -- the owner is gone
		return
	end
	local opts = record.options
	record.time += dt
	local count = #record.pets
	if count == 0 then
		return
	end
	local radius = 0.05
	for _, pet in record.pets do
		radius = math.max(radius, pet.radius)
	end
	local slots = PetsLogic.formation(record.mode, count, {
		radius = radius,
		spacing = opts.spacing,
		distance = opts.distance,
		perRow = opts.perRow,
		orbitSpeed = opts.orbitSpeed,
		time = record.time,
	})
	local ownerYaw = yawOf(ownerCFrame)
	local flat = CFrame.new(ownerCFrame.Position) * CFrame.Angles(0, math.rad(ownerYaw), 0)
	local frameTime = Host.frameTime()
	local buckets = PetsLogic.buckets(count, Host.profile().petUpdateHz, if frameTime > 0 then 1 / frameTime else 60)
	local hover = math.max(0, opts.hover or 0)
	local reduced = Host.settings().reducedMotion

	for index = count, 1, -1 do
		local pet = record.pets[index]
		if pet.model.Parent == nil or pet.animator:isDestroyed() then
			release(pet)
			table.remove(record.pets, index)
			refreshFilter(record)
			continue
		end
		pet.pending += dt
		if not PetsLogic.isDue(index, frame, buckets) then
			continue
		end
		local elapsed = pet.pending
		pet.pending = 0
		local slot = slots[index]
		if slot == nil then
			continue
		end
		local world = flat:PointToWorldSpace(Vector3.new(slot[1], 0, slot[3]))

		if
			opts.ground ~= false
			and PetsLogic.groundStale(pet.cache, world.X, world.Z, record.time, opts.groundInterval)
		then
			pet.cache = { x = world.X, z = world.Z, time = record.time }
			local depth = opts.groundDepth or 40
			local origin = Vector3.new(world.X, ownerCFrame.Position.Y + depth * 0.25, world.Z)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -depth, 0), record.params)
			if hit then
				pet.groundY = hit.Position.Y
				pet.normal = { hit.Normal.X, hit.Normal.Y, hit.Normal.Z }
			else
				pet.groundY = nil
				pet.normal = nil
			end
		end
		local ground = PetsLogic.groundAlign(pet.groundY, pet.normal, {
			pivotHeight = pet.pivotHeight,
			hover = hover,
			yaw = pet.state.yaw,
			fallbackY = ownerCFrame.Position.Y - (opts.ownerHeight or 3) + pet.pivotHeight,
		})

		pet.state = PetsLogic.followStep(pet.state, { world.X, ground.y, world.Z }, elapsed, {
			frequency = opts.frequency,
			maxSpeed = opts.maxSpeed,
			teleportDistance = opts.teleportDistance,
			faceYaw = ownerYaw,
		})
		local state = pet.state
		local speed = math.sqrt(state.velocity[1] ^ 2 + state.velocity[3] ^ 2)
		local bob = 0
		if opts.walkBob ~= false and hover == 0 and not reduced then
			bob = PetsLogic.walkBob(speed, record.time + pet.phase, pet.radius)
		end
		pet.animator:setBase(
			CFrame.new(state.position[1], state.position[2] + bob, state.position[3])
				* CFrame.fromOrientation(math.rad(ground.pitch), math.rad(state.yaw), math.rad(ground.roll))
		)
		pet.animator:setMoving(speed > 1)
	end
end

local function step(dt: number, frame: number)
	for _, record in table.clone(followers) do
		if not record.destroyed then
			stepFollower(record, dt, frame)
		end
	end
end

local function addPet(record: Record, model: Model)
	for _, pet in record.pets do
		if pet.model == model then
			return
		end
	end
	local animator = PetAnimator.find(model)
	local owned = false
	if animator == nil then
		animator = PetAnimator.new(model, record.options.animator)
		owned = true
	end
	local radius, pivotHeight = PetAnimator.measure(model)
	local pivot = model:GetPivot()
	local position = pivot.Position
	table.insert(record.pets, {
		model = model,
		animator = animator :: PetAnimator.PetAnimator,
		owned = owned,
		state = PetsLogic.newFollowState({ position.X, position.Y, position.Z }, yawOf(pivot)),
		radius = radius,
		pivotHeight = pivotHeight,
		phase = PetsLogic.phaseFor(#record.pets + 1),
		pending = 0,
		cache = nil,
		groundY = nil,
		normal = nil,
	})
	refreshFilter(record)
end

-- Makes `pets` follow `owner` (a Model, a BasePart, or a function returning a CFrame). Pets must
-- be anchored Models; they are moved with PivotTo. Returns a Follower.
function PetFollow.new(owner: Owner, pets: { Model }, options: Options?): Follower
	local opts: Options = options or {}
	local resolve: () -> CFrame?
	local ownerInstance: Instance? = nil
	if type(owner) == "function" then
		resolve = owner
	else
		local instance = owner :: Instance
		ownerInstance = instance
		resolve = function(): CFrame?
			if instance.Parent == nil then
				return nil
			end
			if instance:IsA("PVInstance") then
				return instance:GetPivot()
			end
			return nil
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local record: Record = {
		resolve = resolve,
		ownerInstance = ownerInstance,
		options = opts,
		mode = if PetsLogic.isMode(opts.mode) then opts.mode :: PetsLogic.FormationMode else "rows",
		pets = {},
		params = params,
		time = 0,
		destroyed = false,
	}
	for _, model in pets do
		addPet(record, model)
	end
	table.insert(followers, record)
	if removeStepper == nil then
		removeStepper = PetAnimator.addStepper(step)
	end
	return {
		add = function(_self: Follower, pet: Model)
			if not record.destroyed then
				addPet(record, pet)
			end
		end,
		remove = function(_self: Follower, pet: Model)
			for index, entry in record.pets do
				if entry.model == pet then
					release(entry)
					table.remove(record.pets, index)
					refreshFilter(record)
					return
				end
			end
		end,
		setMode = function(_self: Follower, mode: PetsLogic.FormationMode)
			if not PetsLogic.isMode(mode) then
				error("unknown formation mode: " .. tostring(mode), 2)
			end
			record.mode = mode
		end,
		pets = function(_self: Follower): { Model }
			local out: { Model } = {}
			for _, pet in record.pets do
				table.insert(out, pet.model)
			end
			return out
		end,
		isDestroyed = function(_self: Follower): boolean
			return record.destroyed
		end,
		-- Stops following. Pets stay where they are; animators the follower created are removed.
		destroy = function(_self: Follower)
			destroy(record)
		end,
	}
end

function PetFollow.count(): number
	return #followers
end

return PetFollow
