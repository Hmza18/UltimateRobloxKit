--!strict
-- Eggs: the hatch cinematic (Visuals.Eggs).
--
--   local hatch = Eggs.hatch({
--       eggs = { { rarity = "Legendary", name = "Dragon", pet = dragonModel, isNew = true } },
--   })
--   hatch.Completed:Connect(function(results, skipped) ... end)
--
-- HatchLogic plans the eleven beats; this module builds a small client-side stage in front of
-- the camera (anchored, in one Folder), runs the plan as a Sequence and tears everything down.
-- Pressing tap / click / Enter / ButtonA jumps to the result; pressing again dismisses it.
-- cancel() removes everything at once and restores the camera.
--
-- A hatch is presentation only: decide what the eggs contain on the server first.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local HatchLogic = require("./HatchLogic")
local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local RewardView = require("../Rewards/RewardView")
local RewardsLogic = require("../Rewards/RewardsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Entry = {
	rarity: string?,
	pet: (Model | () -> Model?)?, -- cloned when a Model; called when a function
	egg: Model?, -- cloned; default: a demo egg tinted by rarity
	name: string?,
	isNew: boolean?,
	color: any?, -- demo egg / pet colour (default: the rarity colour)
	[string]: any,
}

export type Config = {
	eggs: { Entry },
	mode: string?, -- "auto" for auto-hatch; otherwise chosen from the egg count
	origin: CFrame?, -- centre of the stage, looking at the viewer (default: in front of the camera)
	distance: number?, -- studs in front of the camera for the default origin (default 14)
	speed: number?,
	camera: boolean?, -- default true
	ui: boolean?, -- default true
	skippable: boolean?, -- default true
	autoContinue: boolean?, -- default true: the result dismisses itself after `hold`
	hold: number?, -- seconds the result stays (default 2.5)
	parent: Instance?, -- where the stage Folder goes (default Workspace)
	guiParent: Instance?, -- where the overlay ScreenGui goes (default the local PlayerGui)
	sounds: { [string]: any }?, -- cue -> asset id, registered with Audio before the hatch
	onReveal: ((index: number, entry: Entry) -> ())?,
	next: (() -> { Entry }?)?, -- auto mode: returns the next batch, or nil to stop
}

export type Result = { index: number, rarity: string, name: string?, isNew: boolean, entry: Entry }

export type Hatch = {
	skip: () -> (), -- jump to the result; when already there, dismiss
	finish: () -> (), -- jump to the result
	cancel: () -> (), -- remove everything now
	stop: () -> (), -- auto mode: stop after removing the current batch; otherwise cancel
	isRunning: (self: Hatch) -> boolean,
	Revealed: Signal.Signal, -- (index, entry)
	Completed: Signal.Signal, -- (results, skipped)
	BatchCompleted: Signal.Signal, -- auto mode: (results) after each batch
}

local Eggs = {}

Eggs.Logic = HatchLogic

local modules: { [string]: any } = {}
local function optional(name: string, load: () -> any): any
	local cached = modules[name]
	if cached == nil then
		local ok, module = pcall(load)
		cached = if ok and module ~= nil then module else false
		modules[name] = cached
	end
	return if cached == false then nil else cached
end

local function vfxModule(): any
	return optional("VFX", function(): any
		return require("../VFX/VFX")
	end)
end

local function cameraModule(): any
	return optional("Camera", function(): any
		return require("../Camera/Camera")
	end)
end

local function audioModule(): any
	return optional("Audio", function(): any
		return require("../Audio/Audio")
	end)
end

local function petsModule(): any
	return optional("Pets", function(): any
		return require("../Pets/Pets")
	end)
end

-- Calls a function of an optional module; nil when the module or function is missing or the
-- call fails. Effects are often skipped by budgets, so nil is normal and never an error here.
local function try(module: any, name: string, ...: any): any
	if module == nil or type(module[name]) ~= "function" then
		return nil
	end
	local ok, result = pcall(module[name], ...)
	return if ok then result else nil
end

local function endHandle(handle: any)
	if type(handle) == "function" then
		pcall(handle)
	elseif type(handle) == "table" then
		local stop = handle.stop or handle.cancel or handle.destroy
		if type(stop) == "function" then
			pcall(stop)
		end
	end
end

local function prepare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	prepare(part)
	part.Parent = parent
	return part
end

local function sphereMesh(part: BasePart): SpecialMesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return mesh
end

-- An original demo egg: one ellipsoid body with a few darker spots, 2 x 2.6 x 2 studs, pivot at
-- its base so it rocks on the ground. `color` is a hex string or Color3.
function Eggs.demoEgg(color: any?): Model
	local tint = RewardView.color(color, Color3.fromRGB(240, 236, 224))
	local model = Instance.new("Model")
	model.Name = "DemoEgg"
	model:SetAttribute("UvkDemoEgg", true)
	local width, height = 2, 2.6
	local body = newPart("Body", Vector3.new(width, height, width), tint, model)
	sphereMesh(body)
	body.PivotOffset = CFrame.new(0, -height / 2, 0)
	model.PrimaryPart = body
	local dark = tint:Lerp(Color3.new(0, 0, 0), 0.28)
	-- Spots sit on the surface of the ellipsoid, flattened along its normal.
	local spots = { { 0.5, 0.9, 0.7 }, { 2.3, -0.2, 0.55 }, { 4.1, 0.5, 0.6 }, { 5.4, -0.6, 0.45 }, { 3.2, 1.25, 0.4 } }
	for index, spot in spots do
		local yaw, lift, size = spot[1], spot[2], spot[3]
		local ring = math.sqrt(math.max(0, 1 - (lift / (height / 2)) ^ 2))
		local position = Vector3.new(math.cos(yaw) * ring * width / 2, lift, math.sin(yaw) * ring * width / 2)
		local normal =
			Vector3.new(position.X / (width / 2) ^ 2, position.Y / (height / 2) ^ 2, position.Z / (width / 2) ^ 2)
		local patch = newPart("Spot" .. tostring(index), Vector3.new(size, size, 0.12), dark, model)
		sphereMesh(patch)
		patch.CFrame = CFrame.lookAt(position * 0.99, position + normal)
	end
	return model
end

-- An original demo pet: a round little creature made of a few parts, about 2.4 studs tall.
function Eggs.demoPet(color: any?): Model
	local tint = RewardView.color(color, Color3.fromRGB(120, 200, 255))
	local model = Instance.new("Model")
	model.Name = "DemoPet"
	local function ball(name: string, diameter: number, shade: Color3, at: Vector3): Part
		local part = newPart(name, Vector3.new(diameter, diameter, diameter), shade, model)
		part.Shape = Enum.PartType.Ball
		part.CFrame = CFrame.new(at)
		return part
	end
	local body = ball("Body", 2, tint, Vector3.zero)
	model.PrimaryPart = body
	local light = tint:Lerp(Color3.new(1, 1, 1), 0.55)
	local dark = Color3.fromRGB(28, 30, 44)
	ball("Belly", 1.3, light, Vector3.new(0, -0.25, -0.5))
	ball("EarLeft", 0.7, tint, Vector3.new(-0.65, 0.95, 0))
	ball("EarRight", 0.7, tint, Vector3.new(0.65, 0.95, 0))
	ball("EyeLeft", 0.3, dark, Vector3.new(-0.38, 0.3, -0.88))
	ball("EyeRight", 0.3, dark, Vector3.new(0.38, 0.3, -0.88))
	ball("FootLeft", 0.6, light, Vector3.new(-0.5, -0.95, -0.15))
	ball("FootRight", 0.6, light, Vector3.new(0.5, -0.95, -0.15))
	ball("Tail", 0.5, light, Vector3.new(0, -0.3, 1))
	return model
end

local function anchorModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			prepare(descendant)
		end
	end
end

local function maxExtent(model: Model): number
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Y, size.Z, 0.01)
end

type EggRig = {
	index: number,
	model: Model,
	base: CFrame, -- rest pivot (bottom centre of the slot)
	rest: number, -- model scale at rest
	height: number,
	state: { y: number, squash: number, scale: number },
	plan: HatchLogic.EggPlan,
	body: SpecialMesh?, -- demo eggs squash through their mesh
	last: string,
	alive: boolean,
}

type PetRig = {
	index: number,
	model: Model,
	base: CFrame,
	rest: number,
	state: { scale: number, spin: number },
	last: string,
	billboard: BillboardGui?,
}

local function resolvePet(entry: Entry, color: string): Model
	local source: any = entry.pet
	local model: Model? = nil
	if type(source) == "function" then
		local ok, result = pcall(source)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			model = result
		end
	elseif typeof(source) == "Instance" and source:IsA("Model") then
		model = source:Clone()
	end
	return model or Eggs.demoPet(entry.color or color)
end

type Batch = {
	skip: () -> (),
	finish: () -> (),
	cancel: () -> (),
	isRunning: () -> boolean,
}

-- Runs one batch of eggs. `done(results, skipped, cancelled)` is called exactly once.
local function runBatch(
	config: Config,
	entries: { Entry },
	mode: string?,
	revealed: Signal.Signal,
	done: (results: { Result }, skipped: boolean, cancelled: boolean) -> ()
): Batch
	local settings = Host.settings()
	local profile = Host.profile()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(16, 9)
	local aspect: number = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local planOptions: HatchLogic.Options = {
		mode = mode,
		speed = config.speed,
		aspect = aspect,
		reducedMotion = settings.reducedMotion,
		reducedFlashing = settings.reducedFlashing,
		quality = settings.level :: string,
		hold = config.hold,
		camera = config.camera,
	}
	local plan = HatchLogic.plan(entries, planOptions)
	local auto = plan.mode == "auto"

	-- The stage: its centre looks at the viewer, so +X of `origin` is the viewer's left.
	local distance = config.distance or 14
	local origin: CFrame
	if config.origin then
		origin = config.origin
		if camera then
			distance = math.max(4, (camera.CFrame.Position - origin.Position).Magnitude)
		end
	elseif camera then
		local eye = camera.CFrame
		origin = CFrame.lookAt(eye.Position + eye.LookVector * distance, eye.Position, eye.UpVector)
	else
		origin = CFrame.new(0, 10, 0)
	end
	local fov = if camera then camera.FieldOfView else 70
	local frameHeight = 2 * distance * math.tan(math.rad(fov) / 2)

	local trove = Trove.new()
	local effects: { any } = {} -- VFX, camera and light handles that must not outlive the hatch
	local state: string = "playing" -- playing | result | finishing | done
	local wasSkipped = false
	local sequence: any = nil
	local eggs: { [number]: EggRig } = {}
	local pets: { [number]: PetRig } = {}
	local announced: { [number]: boolean } = {}
	local results: { Result } = {}

	local folder = Instance.new("Folder")
	folder.Name = "UVKHatch"
	folder.Parent = config.parent or Workspace
	trove:Add(folder)

	local gui = RewardView.screen(config.guiParent, "UVKHatch", 880)
	local flash: Frame? = nil
	local hint: TextLabel? = nil
	if gui then
		trove:Add(gui)
		local overlay = Instance.new("Frame")
		overlay.Name = "Flash"
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(1, 1, 1)
		overlay.BackgroundTransparency = 1
		overlay.Parent = gui
		flash = overlay
		if config.ui ~= false and not auto then
			local label = RewardView.text({
				name = "Hint",
				text = "Tap to continue",
				parent = RewardView.safeArea(gui),
				maxSize = 18,
				stroke = 1,
				position = UDim2.fromScale(0.5, 0.94),
				size = UDim2.new(0.8, 0, 0, 24),
			})
			RewardView.setTextAlpha(label, 1)
			hint = label
		end
	end

	local function keep(effect: any): any
		if effect ~= nil then
			table.insert(effects, effect)
		end
		return effect
	end

	local function stopEffects()
		local list = effects
		effects = {}
		for _, effect in list do
			endHandle(effect)
		end
	end

	local function slotCFrame(slot: HatchLogic.Slot): CFrame
		return origin * CFrame.new(-slot.x * frameHeight, slot.y * frameHeight, 0)
	end

	local function eggHeight(slot: HatchLogic.Slot): number
		return slot.size * frameHeight * 0.55
	end

	local function destroyEgg(index: number)
		local rig = eggs[index]
		if rig then
			eggs[index] = nil
			rig.alive = false
			Motion.stop(rig.state)
			rig.model:Destroy()
		end
	end

	local function poseEgg(rig: EggRig, angle: number)
		local s = rig.state
		local key = string.format("%.3f|%.3f|%.3f|%.2f", s.y, s.squash, s.scale, angle)
		if key == rig.last or not rig.alive then
			return
		end
		rig.last = key
		local squash = math.clamp(s.squash, 0.5, 1.5)
		local scale = math.max(0.01, s.scale)
		local mesh = rig.body
		if mesh then
			-- Volume-preserving squash on the mesh; the model itself keeps one uniform scale.
			local wide = 1 / math.sqrt(squash)
			mesh.Scale = Vector3.new(wide, squash, wide)
			mesh.Offset = Vector3.new(0, -rig.height * (1 - squash) / 2 / rig.model:GetScale(), 0)
			rig.model:ScaleTo(rig.rest * scale)
		else
			rig.model:ScaleTo(rig.rest * scale * (0.5 + 0.5 * squash))
		end
		rig.model:PivotTo(rig.base * CFrame.new(0, s.y, 0) * CFrame.Angles(0, 0, math.rad(angle)))
	end

	local function posePet(rig: PetRig)
		local s = rig.state
		local key = string.format("%.3f|%.1f", s.scale, s.spin)
		if key == rig.last or rig.model.Parent == nil then
			return
		end
		rig.last = key
		rig.model:ScaleTo(rig.rest * math.max(0.01, s.scale))
		rig.model:PivotTo(rig.base * CFrame.Angles(0, math.rad(s.spin), 0))
	end

	-- One job poses every egg and pet; it does nothing for rigs whose values did not change.
	trove:Add(Host.clock:add(function(): boolean?
		local now = if sequence then sequence:Elapsed() else 0
		for _, rig in eggs do
			poseEgg(rig, HatchLogic.wobble(rig.plan, now))
		end
		for _, rig in pets do
			posePet(rig)
		end
		return true
	end))

	local function showPet(index: number, animate: boolean, payload: { [string]: any })
		if pets[index] then
			return
		end
		local entry = entries[index]
		local eggPlan = plan.eggs[index]
		local rarity = RewardsLogic.get(eggPlan.rarity)
		local model = resolvePet(entry, rarity.color)
		anchorModel(model)
		local target = eggHeight(eggPlan.slot) * 0.9
		local rest = model:GetScale() * target / maxExtent(model)
		local rig: PetRig = {
			index = index,
			model = model,
			base = slotCFrame(eggPlan.slot),
			rest = rest,
			state = { scale = if animate then 0.05 else 1, spin = if animate then payload.spin or 0 else 0 },
			last = "",
			billboard = nil,
		}
		pets[index] = rig
		model.Parent = folder
		posePet(rig)
		if animate then
			Motion.spring(rig.state, { scale = 1 }, payload.spring or "Overshoot", { essential = true })
			if rig.state.spin ~= 0 then
				Motion.tween(rig.state, { spin = 0 }, { duration = 0.4 / plan.speed, easing = "quartOut" })
			end
		end
	end

	local function announce(index: number)
		if announced[index] then
			return
		end
		announced[index] = true
		local entry = entries[index]
		table.insert(results, {
			index = index,
			rarity = plan.eggs[index].rarity,
			name = entry.name,
			isNew = entry.isNew == true,
			entry = entry,
		})
		revealed:Fire(index, entry)
		if config.onReveal then
			task.spawn(config.onReveal, index, entry)
		end
	end

	-- Name, rarity and NEW tag under each pet. A BillboardGui sized in studs follows the pet and
	-- scales with distance, so one layout works for 1 egg and for 25.
	local function showResult()
		if config.ui == false then
			return
		end
		local compact = plan.count > 3
		for index, rig in pets do
			if rig.billboard or rig.model.PrimaryPart == nil then
				continue
			end
			local entry = entries[index]
			local rarity = RewardsLogic.get(plan.eggs[index].rarity)
			local height = eggHeight(plan.eggs[index].slot)
			local board = Instance.new("BillboardGui")
			board.Name = "Result"
			board.Adornee = rig.model.PrimaryPart
			board.AlwaysOnTop = true
			board.LightInfluence = 0
			board.Size = UDim2.fromScale(height * 2.2, height * 0.7)
			board.StudsOffsetWorldSpace = Vector3.new(0, -height * 0.85, 0)
			board.Parent = folder
			rig.billboard = board
			local label = RewardView.text({
				name = "Rarity",
				text = rarity.label,
				parent = board,
				color = if rarity.rank >= 7 then rarity.secondary else rarity.color,
				maxSize = 60,
				stroke = 3,
				position = UDim2.fromScale(0.5, if entry.name and not compact then 0.72 else 0.5),
				size = UDim2.fromScale(1, 0.46),
			})
			RewardView.setScale(label, 0)
			Motion.spring(label, { Scale = 1 }, "Bouncy", { essential = true })
			if entry.name and not compact then
				RewardView.text({
					name = "Name",
					text = entry.name,
					parent = board,
					maxSize = 72,
					stroke = 3,
					position = UDim2.fromScale(0.5, 0.25),
					size = UDim2.fromScale(1, 0.5),
				})
			end
			if entry.isNew then
				local tag = RewardView.text({
					name = "New",
					text = "NEW!",
					parent = board,
					color = "#FFE14D",
					maxSize = 48,
					stroke = 3,
					position = UDim2.fromScale(0.88, 0.05),
					size = UDim2.fromScale(0.34, 0.34),
				})
				tag.Rotation = 12
				RewardView.setScale(tag, 0)
				Motion.spring(tag, { Scale = 1 }, "Elastic", { delay = 0.12, essential = true })
			end
		end
		if hint then
			RewardView.fadeText(hint, 0.2, 0.25)
		end
	end

	local function teardown(cancelled: boolean)
		if state == "done" then
			return
		end
		state = "done"
		if sequence then
			sequence:Cancel()
		end
		stopEffects()
		for _, rig in eggs do
			Motion.stop(rig.state)
		end
		for _, rig in pets do
			Motion.stop(rig.state)
		end
		trove:Clean()
		table.sort(results, function(a: Result, b: Result): boolean
			return a.index < b.index
		end)
		done(results, wasSkipped, cancelled)
	end

	local function finish()
		if state ~= "result" then
			return
		end
		state = "finishing"
		stopEffects()
		try(audioModule(), "play", "ui.close")
		for _, rig in pets do
			Motion.tween(rig.state, { scale = 0.02 }, {
				duration = plan.finishDuration,
				easing = "backIn",
				essential = true,
			})
			if rig.billboard then
				rig.billboard:Destroy()
				rig.billboard = nil
			end
		end
		if hint then
			RewardView.fadeText(hint, 1, plan.finishDuration * 0.6)
		end
		trove:Add(Host.clock:after(plan.finishDuration, function()
			teardown(false)
		end))
	end

	local function toResult(skipped: boolean)
		if state ~= "playing" then
			return
		end
		state = "result"
		if skipped then
			-- Anything still running belongs to beats that were skipped.
			stopEffects()
			for index in table.clone(eggs) do
				destroyEgg(index)
			end
			if flash then
				Motion.stop(flash)
				flash.BackgroundTransparency = 1
			end
		end
		if auto then
			finish()
		elseif config.autoContinue ~= false then
			trove:Add(Host.clock:after(plan.hold, finish))
		end
	end

	local handlers: { [string]: (step: HatchLogic.Step, ctx: any) -> any } = {}

	function handlers.enter(step: HatchLogic.Step, ctx: any): any
		local index = step.egg :: number
		if ctx.skipped or eggs[index] then
			return nil
		end
		local entry = entries[index]
		local eggPlan = plan.eggs[index]
		local rarity = RewardsLogic.get(eggPlan.rarity)
		local model: Model = if entry.egg then entry.egg:Clone() else Eggs.demoEgg(entry.color or rarity.color)
		anchorModel(model)
		local height = eggHeight(eggPlan.slot)
		local rest = model:GetScale() * height / math.max(0.01, model:GetExtentsSize().Y)
		local body: SpecialMesh? = nil
		if model:GetAttribute("UvkDemoEgg") and model.PrimaryPart then
			body = model.PrimaryPart:FindFirstChildOfClass("SpecialMesh")
		end
		local drop = frameHeight * 0.75
		local rig: EggRig = {
			index = index,
			model = model,
			base = slotCFrame(eggPlan.slot) * CFrame.new(0, -height / 2, 0),
			rest = rest,
			height = height,
			state = { y = drop, squash = 1.12, scale = 1 },
			plan = eggPlan,
			body = body,
			last = "",
			alive = true,
		}
		eggs[index] = rig
		poseEgg(rig, 0)
		model.Parent = folder
		-- Falls with a slight stretch; the landing step squashes it.
		Motion.tween(rig.state, { y = 0 }, { duration = step.duration or 0.28, easing = "quadIn", essential = true })
		return nil
	end

	function handlers.land(step: HatchLogic.Step, ctx: any): any
		local rig = eggs[step.egg :: number]
		if ctx.skipped or rig == nil then
			return nil
		end
		rig.state.y = 0
		Motion.spring(rig.state, { squash = 1 }, "Bouncy", { from = { squash = 1 - step.payload.squash } })
		if step.payload.cue then
			try(audioModule(), "play", step.payload.cue)
		end
		if step.payload.vfx then
			return try(vfxModule(), "play", step.payload.vfx, rig.base.Position, { scale = rig.height / 2.6 })
		end
		return nil
	end

	function handlers.cameraLand(step: HatchLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		return Host.clock:after(step.payload.at / plan.speed, function()
			if state == "playing" then
				keep(try(cameraModule(), "shake", step.payload.shake))
			end
		end)
	end

	function handlers.shake(step: HatchLogic.Step, ctx: any): any
		local rig = eggs[step.egg :: number]
		if ctx.skipped or rig == nil then
			return nil
		end
		-- The wobble curve rotates the egg; a small squash kick sells each shake.
		Motion.punch(rig.state, "squash", -0.05 - 0.05 * step.payload.shake / step.payload.count, "Snappy")
		try(audioModule(), "play", step.payload.cue, { pitch = step.payload.pitch })
		if step.payload.vfx then
			return try(vfxModule(), "play", step.payload.vfx, rig.base.Position, { scale = rig.height / 2.6 })
		end
		return nil
	end

	function handlers.energy(step: HatchLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		try(audioModule(), "play", step.payload.cue)
		local duration = step.duration or 0.5
		for _, rig in eggs do
			local rarity = RewardsLogic.get(rig.plan.rarity)
			local glow = RewardView.color(rarity.glow)
			if step.payload.vfx then
				keep(try(vfxModule(), "attach", step.payload.vfx, rig.model, {
					color = glow,
					intensity = step.payload.intensity,
					scale = rig.height / 2.6,
					owner = folder,
				}))
			end
			local part = rig.model.PrimaryPart
			if step.payload.light and profile.lights and part and plan.count <= 3 then
				local light = Instance.new("PointLight")
				light.Color = glow
				light.Range = rig.height * 4
				light.Brightness = 0
				light.Shadows = false
				light.Parent = part
				Motion.tween(
					light,
					{ Brightness = 1 + 2 * step.payload.intensity },
					{ duration = duration, easing = "quadIn" }
				)
			end
			-- The egg swells a little as the energy builds: anticipation for the pop.
			Motion.tween(rig.state, { scale = 1.08 }, { duration = duration, easing = "quadIn" })
		end
		return nil
	end

	function handlers.cameraPush(step: HatchLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		return keep(try(cameraModule(), "cinematic", step.payload.cinematic, origin.Position, {
			distance = distance * 0.72,
			blendIn = step.duration,
		}))
	end

	function handlers.crack(step: HatchLogic.Step, ctx: any): any
		local index = step.egg :: number
		local rig = eggs[index]
		if ctx.skipped or rig == nil then
			return nil
		end
		local centre = (rig.base * CFrame.new(0, rig.height / 2, 0)).Position
		local params = { color = step.payload.color, scale = rig.height / 2.6 }
		try(audioModule(), "play", step.payload.cue)
		try(vfxModule(), "play", step.payload.vfx, centre, params)
		try(vfxModule(), "play", step.payload.flash, centre, params)
		-- Stretch up, then collapse: the shell is gone before the pet appears.
		local duration = step.duration or 0.14
		Motion.stop(rig.state)
		rig.state.squash = 1.18
		Motion.tween(rig.state, { scale = 1.3 }, {
			duration = duration * 0.45,
			easing = "quadOut",
			essential = true,
			onDone = function(completed: boolean)
				if completed and rig.alive then
					Motion.tween(rig.state, { scale = 0.02, squash = 0.7 }, {
						duration = duration * 0.5,
						easing = "quadIn",
						essential = true,
					})
				end
			end,
		})
		return Host.clock:after(duration, function()
			destroyEgg(index)
		end)
	end

	function handlers.bloom(step: HatchLogic.Step, ctx: any): any
		if ctx.skipped or flash == nil or Host.settings().reducedFlashing then
			return nil
		end
		flash.BackgroundColor3 = RewardView.color(step.payload.color)
		return Motion.tween(flash, { BackgroundTransparency = 1 }, {
			duration = step.duration or 0.3,
			easing = "quadOut",
			from = { BackgroundTransparency = 1 - step.payload.strength },
		})
	end

	function handlers.appear(step: HatchLogic.Step, ctx: any): any
		local index = step.egg :: number
		destroyEgg(index)
		showPet(index, not ctx.skipped, step.payload)
		if ctx.skipped then
			return nil
		end
		local rig = pets[index]
		try(audioModule(), "play", step.payload.cue)
		if step.payload.rarityCue then
			try(audioModule(), "play", step.payload.rarityCue)
		end
		return try(vfxModule(), "play", step.payload.vfx, rig.base.Position, step.payload.params)
	end

	function handlers.revealed(step: HatchLogic.Step): any
		announce(step.egg :: number)
		return nil
	end

	function handlers.react(step: HatchLogic.Step, ctx: any): any
		local rig = pets[step.egg :: number]
		if ctx.skipped or rig == nil then
			return nil
		end
		-- The reaction moves the model itself, so the stage job must stop writing its pose.
		Motion.stop(rig.state)
		rig.state.scale = 1
		rig.state.spin = 0
		posePet(rig)
		return keep(try(petsModule(), "play", step.payload.reaction, rig.model))
	end

	function handlers.rarity(step: HatchLogic.Step, ctx: any): any
		local rig = pets[step.egg :: number]
		if ctx.skipped or rig == nil then
			return nil
		end
		local payload = step.payload
		local vfx = vfxModule()
		local at = rig.base.Position
		-- The VFX `rarity` param is an enum of the built-in tiers; custom rarities map to one.
		local tier = payload.vfxRarity or payload.rarity
		if payload.aura then
			keep(try(vfx, "attach", payload.aura, rig.model, { rarity = tier, color = payload.color, owner = folder }))
		end
		if payload.rays > 0 then
			keep(try(vfx, "play", "RarityBurst", at, { rarity = tier, color = payload.color }))
			if payload.rays >= 12 then
				keep(try(vfx, "play", "RarityBeam", at, { rarity = tier, color = payload.color }))
			end
		end
		if payload.shake then
			keep(try(cameraModule(), "shake", payload.shake))
		end
		for offset, id in payload.celebrate do
			trove:Add(Host.clock:after((offset - 1) * 0.2, function()
				if state ~= "done" then
					keep(try(vfx, "play", id, origin.Position, { color = payload.color }))
				end
			end))
		end
		return nil
	end

	function handlers.result(): any
		-- Pets that never got their appear step (a skip) are already placed by `appear`.
		showResult()
		return nil
	end

	local built = Motion.sequence({
		sound = function(cue: string, soundOptions: any?): any
			return try(audioModule(), "play", cue, soundOptions)
		end,
	})
	for _, step in plan.steps do
		local handler = handlers[step.kind]
		if handler and step.kind ~= "finish" then
			built:At(step.time)
			built:Call(function(ctx: any): any
				return handler(step, ctx)
			end)
		end
	end
	built:At(plan.resultAt)
	built:OnDone(function(completed: boolean, skipped: boolean)
		if completed then
			wasSkipped = skipped
			toResult(skipped)
		end
	end)
	sequence = built

	local function press()
		if state == "playing" then
			built:Skip()
		elseif state == "result" then
			finish()
		end
	end

	if config.skippable ~= false and not auto then
		trove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
			if processed or UserInputService:GetFocusedTextBox() ~= nil then
				return
			end
			local kind = input.UserInputType
			local key = input.KeyCode
			if
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.Touch
				or key == Enum.KeyCode.Return
				or key == Enum.KeyCode.KeypadEnter
				or key == Enum.KeyCode.ButtonA
			then
				press()
			end
		end)
	end
	-- If the stage is destroyed from outside, end cleanly instead of animating nothing.
	trove:Connect(folder.AncestryChanged, function()
		if folder.Parent == nil then
			teardown(true)
		end
	end)

	built:Start()
	return {
		skip = press,
		finish = function()
			if state == "playing" then
				built:Skip()
			end
		end,
		cancel = function()
			teardown(true)
		end,
		isRunning = function(): boolean
			return state ~= "done"
		end,
	}
end

-- Starts a hatch. See the Config type for every option. With mode = "auto" the hatch repeats:
-- after each batch `config.next()` is called for the next list of eggs until it returns nil or
-- stop() is called; auto mode takes no input and never moves the camera.
function Eggs.hatch(config: Config): Hatch
	assert(type(config) == "table", "Eggs.hatch needs a config table")
	assert(type(config.eggs) == "table" and #config.eggs >= 1, "Eggs.hatch needs config.eggs with at least one egg")
	if config.sounds then
		try(audioModule(), "registerMany", config.sounds)
	end
	local revealed = Signal.new()
	local completed = Signal.new()
	local batchCompleted = Signal.new()
	local auto = config.mode == "auto"
	local current: Batch? = nil
	local running = true
	local stopping = false
	local all: { Result } = {}

	local function complete(skipped: boolean)
		if not running then
			return
		end
		running = false
		current = nil
		completed:Fire(all, skipped)
	end

	local function start(entries: { Entry })
		current = runBatch(
			config,
			entries,
			config.mode,
			revealed,
			function(results: { Result }, skipped: boolean, cancelled: boolean)
				current = nil
				if not running then
					return
				end
				if not auto then
					all = results
					complete(skipped or cancelled)
					return
				end
				for _, result in results do
					table.insert(all, result)
				end
				batchCompleted:Fire(results)
				local nextEggs: { Entry }? = nil
				if not stopping and not cancelled and config.next then
					local ok, value = pcall(config.next)
					if ok and type(value) == "table" and #value >= 1 then
						nextEggs = value
					end
				end
				if nextEggs then
					start(nextEggs)
				else
					complete(stopping or cancelled)
				end
			end
		)
	end

	local hatch: Hatch = {
		skip = function()
			if current then
				current.skip()
			end
		end,
		finish = function()
			if current then
				current.finish()
			end
		end,
		cancel = function()
			stopping = true
			local active = current
			if active then
				active.cancel()
			else
				complete(true)
			end
		end,
		stop = function()
			stopping = true
			local active = current
			if active then
				active.cancel()
			else
				complete(true)
			end
		end,
		isRunning = function(_self: Hatch): boolean
			return running
		end,
		Revealed = revealed,
		Completed = completed,
		BatchCompleted = batchCompleted,
	}
	start(config.eggs)
	return hatch
end

export type IdleOptions = HatchLogic.IdleOptions

export type IdleHandle = { stop: () -> (), cancel: () -> (), isRunning: () -> boolean }

-- Gentle idle motion for an egg on display: a sway and an occasional hop, around the model's
-- pivot. The egg returns to where it was when the handle stops or the model is destroyed.
-- Under reduced motion the egg stays still. Anchor the egg's parts; this moves it with PivotTo.
function Eggs.idle(eggModel: Model, options: IdleOptions?): IdleHandle
	local base = eggModel:GetPivot()
	local height = math.max(0.1, eggModel:GetExtentsSize().Y)
	local elapsed = 0
	local running = true
	local remove: (() -> ())? = nil
	local hz = Host.profile().petUpdateHz
	local interval = if hz > 0 then 1 / hz else 0
	local sinceWrite = interval

	local function stop()
		if not running then
			return
		end
		running = false
		if remove then
			remove()
		end
		if eggModel.Parent ~= nil then
			eggModel:PivotTo(base)
		end
	end

	if Host.settings().reducedMotion then
		running = false
	else
		remove = Host.clock:add(function(dt: number): boolean?
			if eggModel.Parent == nil then
				running = false
				return false
			end
			elapsed += dt
			sinceWrite += dt
			if sinceWrite < interval then
				return true
			end
			sinceWrite = 0
			local pose = HatchLogic.idle(elapsed, options)
			-- A model cannot squash without resizing its parts, so the squash becomes a dip.
			local dip = (pose.squash - 1) * height * 0.5
			eggModel:PivotTo(
				base
					* CFrame.new(0, pose.offset * height + math.min(0, dip), 0)
					* CFrame.Angles(0, 0, math.rad(pose.angle))
			)
			return true
		end)
	end
	return {
		stop = stop,
		cancel = stop,
		isRunning = function(): boolean
			return running
		end,
	}
end

return Eggs
