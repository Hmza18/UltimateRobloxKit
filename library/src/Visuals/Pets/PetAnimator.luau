--!strict
-- Pet animator: idle, reactions, hover / selected poses and object-animation layers on any Model,
-- composed into one PivotTo per update from a stored base CFrame (so nothing drifts). Rig-agnostic:
-- it moves the whole model, so no Humanoid or Motor6D is needed. Rigged models can add real
-- animations through options.animations.
--
-- Every animator, and every follower (PetFollow), is updated from ONE Host.clock job. Idle motion
-- is recomputed at the quality profile's petUpdateHz in round-robin buckets; a pet that is busy
-- (reacting, hover spring moving, being moved by a follower) updates every frame.
--
-- Used through Pets.animator; see README.md. NOT run in Studio.

local Host = require("../Runtime/Host")
local ObjectsLogic = require("../Objects/ObjectsLogic")
local PetsLogic = require("./PetsLogic")
local Props = require("../Runtime/Props")
local Springs = require("../Core/Springs")

export type AnimationSource = Animation | string | number

export type Options = {
	phase: number?, -- 0..1; default: spread automatically per pet
	radius: number?, -- bounding radius in studs; default: measured from the model
	idle: boolean?, -- play the idle loop (default true)
	breathe: boolean?, -- breathing scale (default true; always off on the Low profile)
	speed: number?, -- idle cycles per second (default 0.55)
	turntable: number?, -- degrees per second of constant turn (previews)
	everyFrame: boolean?, -- ignore the update-rate budget (previews, hero pets)
	-- Optional real animations for rigged models, played through an Animator found or created on
	-- the model: keys idle, walk, happy, curious, select, hover (or a reaction id).
	animations: { [string]: AnimationSource }?,
	onReact: ((name: string) -> ())?,
}

export type ReactOptions = {
	direction: Vector3?, -- CuriousReaction: world-space point to lean toward
	intensity: number?,
	onDone: ((completed: boolean) -> ())?,
}

export type PetAnimator = {
	model: Model,
	radius: number,
	react: (self: PetAnimator, id: string, options: ReactOptions?) -> (),
	setHover: (self: PetAnimator, hovered: boolean) -> (),
	setSelected: (self: PetAnimator, selected: boolean) -> (),
	setRarity: (self: PetAnimator, rarity: string?) -> (),
	-- Layers used by Pets.play and PetFollow:
	playObject: (self: PetAnimator, presetId: string, params: ObjectsLogic.Params?) -> (),
	clearLayers: (self: PetAnimator) -> (),
	setHidden: (self: PetAnimator, hidden: boolean) -> (),
	setBase: (self: PetAnimator, base: CFrame) -> (),
	getBase: (self: PetAnimator) -> CFrame,
	setMoving: (self: PetAnimator, moving: boolean) -> (),
	isBusy: (self: PetAnimator) -> boolean,
	isDestroyed: (self: PetAnimator) -> boolean,
	destroy: (self: PetAnimator, restore: boolean?) -> (),
}

type Record = {
	model: Model,
	animator: PetAnimator,
	base: CFrame,
	baseScale: number,
	radius: number,
	pivotHeight: number,
	phase: number,
	speed: number,
	idle: boolean,
	breathe: boolean,
	turntable: number,
	everyFrame: boolean,
	managed: boolean, -- a follower sets the base; update only when it does
	dirty: boolean,
	hidden: boolean,
	time: number,
	pending: number,
	lastScale: number,
	hoverTarget: number,
	hover: number,
	hoverVelocity: number,
	selectedTarget: number,
	selected: number,
	selectedVelocity: number,
	reaction: { id: string, t: number, options: PetsLogic.ReactionOptions, onDone: ((completed: boolean) -> ())? }?,
	object: { id: string, t: number, params: ObjectsLogic.Params?, held: ObjectsLogic.Sample? }?,
	aura: any,
	rig: Animator?,
	tracks: { [string]: AnimationTrack },
	created: { Instance },
	moving: boolean,
	onReact: ((name: string) -> ())?,
	destroyed: boolean,
}

local PetAnimator = {}

local records: { Record } = {}
local byModel: { [Model]: Record } = setmetatable({}, { __mode = "k" }) :: any
-- Scale of models an animation left hidden (Despawn), so the next animator starts from the truth.
local hiddenScale: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local steppers: { (dt: number, frame: number) -> () } = {}
local removeJob: (() -> ())? = nil
local frame = 0
local created = 0

local HOVER_SPRING: Springs.Spring = { frequency = 5, damping = 0.7 }
local TRACK_KEYS: { [string]: string } = {
	HappyReaction = "happy",
	CuriousReaction = "curious",
	SelectBounce = "select",
	HoverReaction = "hover",
}

-- VFX is another agent's module and may be absent: load it lazily and carry on without it.
local vfxModule: any = nil
local vfxTried = false
function PetAnimator.vfx(): any
	if not vfxTried then
		vfxTried = true
		local ok, module = pcall(function(): any
			return require("../VFX/VFX")
		end)
		if ok and type(module) == "table" then
			vfxModule = module
		end
	end
	return vfxModule
end

local function stopEffect(handle: any)
	if handle == nil then
		return
	end
	pcall(function()
		local vfx = PetAnimator.vfx()
		if vfx and type(vfx.stop) == "function" then
			vfx.stop(handle)
		elseif type(handle) == "table" and type(handle.stop) == "function" then
			handle.stop()
		end
	end)
end

-- Radius and feet offset of a model, from its bounding box.
function PetAnimator.measure(model: Model): (number, number)
	local ok, boxCFrame, size = pcall(function(): (CFrame, Vector3)
		return model:GetBoundingBox()
	end)
	if not ok or typeof(size) ~= "Vector3" then
		return 1, 1
	end
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local bottom = boxCFrame.Position.Y - size.Y / 2
	local pivotHeight = math.max(0, model:GetPivot().Position.Y - bottom)
	return math.max(0.05, radius), pivotHeight
end

local function finishReaction(record: Record, completed: boolean)
	local reaction = record.reaction
	record.reaction = nil
	if reaction and reaction.onDone then
		local ok, err = pcall(reaction.onDone, completed)
		if not ok then
			warn("[UVK] pet reaction onDone failed: " .. tostring(err))
		end
	end
end

local function busy(record: Record): boolean
	return record.reaction ~= nil
		or (record.object ~= nil and record.object.held == nil)
		or record.dirty
		or math.abs(record.hover - record.hoverTarget) > 1e-3
		or math.abs(record.hoverVelocity) > 1e-2
		or math.abs(record.selected - record.selectedTarget) > 1e-3
		or math.abs(record.selectedVelocity) > 1e-2
end

local function objectOffset(sample: ObjectsLogic.Sample): PetsLogic.Offset
	return {
		position = sample.position,
		rotation = sample.rotation,
		scale = sample.scale,
		done = sample.done,
	}
end

-- Advances one pet by dt and writes its pose.
local function update(record: Record, dt: number)
	local reduced = Host.settings().reducedMotion
	record.time += dt
	record.dirty = false
	local offsets: { PetsLogic.Offset } = {}

	if record.idle and not reduced then
		local breathe = record.breathe and not Host.profile().dropOptional
		table.insert(
			offsets,
			PetsLogic.idle(record.time, {
				phase = record.phase,
				radius = record.radius,
				speed = record.speed,
				breathe = if breathe then 1 else 0,
			})
		)
	end

	if reduced then
		record.hover, record.hoverVelocity = record.hoverTarget, 0
		record.selected, record.selectedVelocity = record.selectedTarget, 0
	else
		record.hover, record.hoverVelocity =
			Springs.step(record.hover, record.hoverVelocity, record.hoverTarget, dt, HOVER_SPRING)
		record.selected, record.selectedVelocity =
			Springs.step(record.selected, record.selectedVelocity, record.selectedTarget, dt, HOVER_SPRING)
	end
	if math.abs(record.hover) > 1e-4 then
		table.insert(offsets, PetsLogic.hoverPose(record.hover, record.radius))
	end
	if math.abs(record.selected) > 1e-4 then
		local k = 1 + 0.06 * record.selected
		table.insert(offsets, { position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, scale = { k, k, k }, done = false })
	end

	local reaction = record.reaction
	if reaction then
		reaction.t += dt
		local sample = if reduced
			then PetsLogic.reaction(reaction.id, math.huge)
			else PetsLogic.reaction(reaction.id, reaction.t, reaction.options)
		if sample.done then
			finishReaction(record, true)
		else
			table.insert(offsets, sample)
		end
	end

	local object = record.object
	if object then
		if object.held then
			table.insert(offsets, objectOffset(object.held))
		else
			object.t += dt
			local sample = ObjectsLogic.sample(object.id, if reduced then math.huge else object.t, object.params)
			if sample.done then
				if ObjectsLogic.isRest(sample) or sample.scale[2] == 1 then
					record.object = nil
				else
					object.held = sample -- ScaleOut and friends leave the pet in their end state
					table.insert(offsets, objectOffset(sample))
				end
			else
				table.insert(offsets, objectOffset(sample))
			end
		end
	end

	local pose = PetsLogic.combine(offsets)
	local scale = PetsLogic.uniformScale(pose.scale)
	if record.hidden then
		scale = 0
	end
	local model = record.model
	if math.abs(scale - record.lastScale) > 0.004 or (scale == 1 and record.lastScale ~= 1) then
		record.lastScale = scale
		model:ScaleTo(math.max(0.001, record.baseScale * scale))
	end
	-- Models scale around their pivot; shift so the feet stay where they were.
	local plant = (record.lastScale - 1) * record.pivotHeight
	local yaw = pose.rotation[2]
	if record.turntable ~= 0 and not reduced then
		yaw += record.turntable * record.time
	end
	local p = pose.position
	model:PivotTo(
		record.base
			* CFrame.new(p[1], p[2] + plant, p[3])
			* CFrame.fromOrientation(math.rad(pose.rotation[1]), math.rad(yaw), math.rad(pose.rotation[3]))
	)
end

local function remove(record: Record)
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
	if byModel[record.model] == record then
		byModel[record.model] = nil
	end
end

local function destroy(record: Record, restore: boolean?)
	if record.destroyed then
		return
	end
	record.destroyed = true
	remove(record)
	finishReaction(record, false)
	stopEffect(record.aura)
	record.aura = nil
	for _, track in record.tracks do
		pcall(function()
			track:Stop(0.1)
			track:Destroy()
		end)
	end
	table.clear(record.tracks)
	for _, instance in record.created do
		instance:Destroy()
	end
	table.clear(record.created)
	local model = record.model
	if model.Parent == nil then
		return
	end
	if restore == false then
		if record.lastScale < 0.5 then
			hiddenScale[model] = record.baseScale
		end
		return
	end
	if record.lastScale ~= 1 then
		model:ScaleTo(record.baseScale)
	end
	model:PivotTo(record.base)
	hiddenScale[model] = nil
end

local function step(dt: number): boolean?
	frame += 1
	for _, stepper in table.clone(steppers) do
		stepper(dt, frame)
	end
	local count = #records
	if count > 0 then
		local frameTime = Host.frameTime()
		local fps = if frameTime > 0 then 1 / frameTime else 60
		local buckets = PetsLogic.buckets(count, Host.profile().petUpdateHz, fps)
		for index, record in table.clone(records) do
			if record.destroyed then
				continue
			end
			local model = record.model
			if not Props.adapter.alive(model) then
				destroy(record, false)
				continue
			end
			if not model:IsDescendantOf(game) then
				continue -- paused while outside the DataModel
			end
			record.pending += dt
			local due: boolean
			if record.everyFrame or busy(record) then
				due = true
			elseif record.managed then
				due = false
			else
				due = PetsLogic.isDue(index, frame, buckets)
			end
			if due then
				local elapsed = record.pending
				record.pending = 0
				update(record, elapsed)
			end
		end
	end
	if #records == 0 and #steppers == 0 then
		removeJob = nil
		return false
	end
	return true
end

local function ensureJob()
	if removeJob == nil then
		removeJob = Host.clock:add(step)
	end
end

-- Runs `stepper(dt, frame)` inside the shared pet job, before the animators. Returns a remover.
function PetAnimator.addStepper(stepper: (dt: number, frame: number) -> ()): () -> ()
	table.insert(steppers, stepper)
	ensureJob()
	return function()
		local index = table.find(steppers, stepper)
		if index then
			table.remove(steppers, index)
		end
	end
end

-- The animator attached to a model, if any.
function PetAnimator.find(model: Model): PetAnimator?
	local record = byModel[model]
	return if record and not record.destroyed then record.animator else nil
end

function PetAnimator.count(): number
	return #records
end

local function rigAnimator(record: Record): Animator?
	if record.rig then
		return record.rig
	end
	local model = record.model
	local host: Instance? = model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildOfClass("AnimationController")
	if host == nil then
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		table.insert(record.created, controller)
		host = controller
	end
	local animator = (host :: Instance):FindFirstChildOfClass("Animator")
	if animator == nil then
		local made = Instance.new("Animator")
		made.Parent = host
		table.insert(record.created, made)
		animator = made
	end
	record.rig = animator
	return animator
end

local function loadTracks(record: Record, animations: { [string]: AnimationSource })
	local animator = rigAnimator(record)
	if animator == nil then
		return
	end
	for key, source in animations do
		local animation: Animation
		if typeof(source) == "Instance" then
			animation = source :: Animation
		else
			local made = Instance.new("Animation")
			made.AnimationId = if type(source) == "number"
				then "rbxassetid://" .. tostring(source)
				else tostring(source)
			table.insert(record.created, made)
			animation = made
		end
		local ok, track = pcall(function(): AnimationTrack
			return animator:LoadAnimation(animation)
		end)
		if ok then
			record.tracks[string.lower(key)] = track
		else
			warn("[UVK] pet animation " .. key .. " failed to load: " .. tostring(track))
		end
	end
	local idle = record.tracks.idle
	if idle then
		idle.Looped = true
		idle:Play()
	end
end

-- Attaches an animator to a model. A model has at most one: a second call replaces the first.
function PetAnimator.new(model: Model, options: Options?): PetAnimator
	assert(typeof(model) == "Instance" and model:IsA("Model"), "Pets.animator expects a Model")
	local opts: Options = options or {}
	local existing = byModel[model]
	if existing then
		destroy(existing, true)
	end
	local remembered = hiddenScale[model]
	if remembered then
		model:ScaleTo(remembered)
		hiddenScale[model] = nil
	end
	created += 1
	local measured, pivotHeight = PetAnimator.measure(model)
	local record: Record = {
		model = model,
		animator = nil :: any,
		base = model:GetPivot(),
		baseScale = model:GetScale(),
		radius = opts.radius or measured,
		pivotHeight = pivotHeight,
		phase = opts.phase or PetsLogic.phaseFor(created),
		speed = opts.speed or 0.55,
		idle = opts.idle ~= false,
		breathe = opts.breathe ~= false,
		turntable = opts.turntable or 0,
		everyFrame = opts.everyFrame == true,
		managed = false,
		dirty = true,
		hidden = false,
		time = 0,
		pending = 0,
		lastScale = 1,
		hoverTarget = 0,
		hover = 0,
		hoverVelocity = 0,
		selectedTarget = 0,
		selected = 0,
		selectedVelocity = 0,
		reaction = nil,
		object = nil,
		aura = nil,
		rig = nil,
		tracks = {},
		created = {},
		moving = false,
		onReact = opts.onReact,
		destroyed = false,
	}

	local function playTrack(id: string)
		local track = record.tracks[TRACK_KEYS[id] or ""] or record.tracks[string.lower(id)]
		if track then
			track:Play(0.1)
		end
	end

	local animator: PetAnimator = {
		model = model,
		radius = record.radius,
		-- Plays a reaction (HappyReaction, CuriousReaction, SelectBounce, HoverReaction). A new
		-- reaction replaces the running one.
		react = function(_self: PetAnimator, id: string, reactOptions: ReactOptions?)
			if record.destroyed then
				return
			end
			if not PetsLogic.isReaction(id) then
				error("unknown pet reaction: " .. tostring(id), 2)
			end
			local given: ReactOptions = reactOptions or {}
			finishReaction(record, false)
			local direction: { number }? = nil
			if given.direction then
				local point = record.base:PointToObjectSpace(given.direction)
				direction = { point.X, 0, point.Z }
			end
			record.reaction = {
				id = id,
				t = 0,
				options = { radius = record.radius, direction = direction, intensity = given.intensity },
				onDone = given.onDone,
			}
			record.dirty = true
			playTrack(id)
			if record.onReact then
				local ok, err = pcall(record.onReact, id)
				if not ok then
					warn("[UVK] pet onReact failed: " .. tostring(err))
				end
			end
			ensureJob()
		end,
		setHover = function(_self: PetAnimator, hovered: boolean)
			record.hoverTarget = if hovered then 1 else 0
			ensureJob()
		end,
		setSelected = function(_self: PetAnimator, selected: boolean)
			record.selectedTarget = if selected then 1 else 0
			ensureJob()
		end,
		-- Attaches the RarityAura effect for `rarity` (nil removes it). Needs the VFX module.
		setRarity = function(_self: PetAnimator, rarity: string?)
			stopEffect(record.aura)
			record.aura = nil
			local vfx = PetAnimator.vfx()
			if rarity == nil or record.destroyed or vfx == nil or type(vfx.attach) ~= "function" then
				return
			end
			local ok, handle = pcall(vfx.attach, "RarityAura", model, { rarity = rarity, owner = model })
			if ok then
				record.aura = handle
			else
				warn("[UVK] RarityAura failed: " .. tostring(handle))
			end
		end,
		playObject = function(_self: PetAnimator, presetId: string, params: ObjectsLogic.Params?)
			if record.destroyed then
				return
			end
			if not ObjectsLogic.has(presetId) or ObjectsLogic.isLoop(presetId) then
				error("pets can only layer one-shot object animations, got " .. tostring(presetId), 2)
			end
			record.object = { id = presetId, t = 0, params = params, held = nil }
			record.dirty = true
			ensureJob()
		end,
		clearLayers = function(_self: PetAnimator)
			finishReaction(record, false)
			record.object = nil
			record.hidden = false
			record.dirty = true
		end,
		setHidden = function(_self: PetAnimator, hidden: boolean)
			record.hidden = hidden
			record.dirty = true
		end,
		-- Moves the pet: every pose is composed on top of this CFrame. Used by followers.
		setBase = function(_self: PetAnimator, base: CFrame)
			record.base = base
			record.managed = true
			record.dirty = true
		end,
		getBase = function(_self: PetAnimator): CFrame
			return record.base
		end,
		setMoving = function(_self: PetAnimator, moving: boolean)
			if moving == record.moving then
				return
			end
			record.moving = moving
			local walk = record.tracks.walk
			if walk then
				if moving then
					walk.Looped = true
					walk:Play(0.15)
				else
					walk:Stop(0.2)
				end
			end
		end,
		isBusy = function(_self: PetAnimator): boolean
			return not record.destroyed and busy(record)
		end,
		isDestroyed = function(_self: PetAnimator): boolean
			return record.destroyed
		end,
		-- Stops everything and puts the model back on its base CFrame and scale. destroy(false)
		-- leaves the model as it is (used after Despawn).
		destroy = function(_self: PetAnimator, restore: boolean?)
			destroy(record, restore)
		end,
	}
	record.animator = animator
	table.insert(records, record)
	byModel[model] = record
	if opts.animations then
		loadTracks(record, opts.animations)
	end
	ensureJob()
	return animator
end

return PetAnimator
