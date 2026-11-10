--!strict
-- Camera effects (Visuals.Camera): shake, FOV moves, focus, orbit, pan and cinematics on
-- workspace.CurrentCamera. The maths is in CameraLogic; this file applies it.
--
--   Camera.shake("Impact")
--   local focus = Camera.focus(petModel, { distance = 10, angle = 30 })
--   focus.stop()                                  -- blends back and restores the game's camera
--   Camera.cinematic("PetReveal", petModel, { onMarker = function(name) ... end })
--
-- Rules this module keeps:
--   * Shakes are additive. The offset is applied after the game's camera update each frame and
--     taken off again before the next one, so any camera controller keeps working underneath.
--   * Takeover moves (focus, orbit, pan, most cinematics) save CameraType, CameraSubject, CFrame
--     and FieldOfView, switch to Scriptable only while active, and always put everything back:
--     on stop, finish, cancel, when the character respawns and when the player leaves.
--   * FOV-only moves (fov, zoom, punchFov, the Teleport cinematic) never change CameraType.
--   * Reduced motion: no shake, no FOV punch, moves crossfade quickly instead of travelling.
--
-- This is the one module in the kit that uses RunService:BindToRenderStep instead of Host.clock:
-- the offset has to be written after the camera scripts run and removed before they run again,
-- which only render-step priorities can order. It is bound only while a shake or move is active.
--
-- NOT run in Studio: see README.md.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraLogic = require("./CameraLogic")
local Host = require("../Runtime/Host")

export type Handle = {
	stop: (blend: boolean?) -> (),
	cancel: () -> (),
	finish: () -> (),
	isActive: () -> boolean,
}

export type ShakeOptions = CameraLogic.ShakeOptions & {
	position: Vector3?, -- world position of the source; with `radius` the shake fades by distance
	radius: number?,
}

export type MoveOptions = {
	priority: number?,
	blendIn: number?,
	blendOut: number?,
	duration: number?, -- seconds before the move ends on its own (nil: until stopped)
	easing: string?,
	fov: number?,
	onDone: ((completed: boolean) -> ())?,
}

export type FocusOptions = MoveOptions & {
	distance: number?,
	angle: number?, -- yaw in degrees; default: the side the camera is already on
	elevation: number?,
	height: number?,
}

export type OrbitOptions = FocusOptions & { speed: number? }

export type CinematicOptions = FocusOptions & { onMarker: ((name: string) -> ())? }

type Target = Vector3 | CFrame | Instance

type ShakeRecord = {
	shake: CameraLogic.Shake,
	age: number,
	stoppedAt: number?,
	alive: boolean,
}

type MoveRecord = {
	id: number,
	age: number,
	onDone: ((completed: boolean) -> ())?,
	onMarker: ((name: string) -> ())?,
	markers: { { name: string, at: number } }?,
	fired: number,
	cancelled: boolean,
}

local Camera = {}

Camera.registry = CameraLogic.registry

local PRE_STEP = "UvkCameraRelease"
local POST_STEP = "UvkCameraApply"
local STOP_FADE = 0.15

local stack = CameraLogic.newStack()
local shakes: { ShakeRecord } = {}
local moves: { [number]: MoveRecord } = {}
local bound = false
local guards: { RBXScriptConnection } = {}
local seedCounter = 0

-- The shake offset written last frame: the camera it went to, the CFrame before and after.
local applied: { camera: Camera, base: CFrame, written: CFrame }? = nil
-- The camera the saved values in the stack belong to.
local savedCamera: Camera? = nil

local function reduced(): boolean
	return Host.settings().reducedMotion
end

local function inert(): Handle
	local function none() end
	return {
		stop = none,
		cancel = none,
		finish = none,
		isActive = function(): boolean
			return false
		end,
	}
end

local function vec(v: Vector3): CameraLogic.Vec3
	return { v.X, v.Y, v.Z }
end

local function vector(v: CameraLogic.Vec3): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function poseOf(cframe: CFrame, focusDistance: number, fov: number?): CameraLogic.Pose
	local position = cframe.Position
	return {
		position = vec(position),
		lookAt = vec(position + cframe.LookVector * focusDistance),
		fov = fov,
	}
end

local function focusDistance(camera: Camera): number
	local distance = (camera.Focus.Position - camera.CFrame.Position).Magnitude
	if distance ~= distance or distance < 1 then
		return 10
	end
	return math.min(distance, 500)
end

-- Removes last frame's shake offset, but only if nothing else has written the camera since.
local function releaseOffset()
	local last = applied
	applied = nil
	if last and last.camera.Parent ~= nil and last.camera.CFrame == last.written then
		last.camera.CFrame = last.base
	end
end

-- Puts back whatever is no longer needed: the takeover state once no takeover move is alive, the
-- field of view once the stack is empty.
local function settle()
	local camera = savedCamera
	if camera == nil then
		return
	end
	if not stack:hasTakeover() and stack:saved("cameraType") ~= nil then
		local saved = stack:release({ "cameraType", "cframe", "subject", "focusDistance" })
		if camera.Parent ~= nil then
			camera.CameraType = saved.cameraType
			if saved.subject ~= nil then
				camera.CameraSubject = saved.subject
			end
			camera.CFrame = saved.cframe
		end
	end
	if stack:count() == 0 then
		local saved = stack:release()
		if saved.fov ~= nil and camera.Parent ~= nil then
			camera.FieldOfView = saved.fov
		end
		savedCamera = nil
	end
end

local function finishMove(id: number, completed: boolean)
	local record = moves[id]
	if record == nil then
		return
	end
	moves[id] = nil
	if record.onDone then
		local ok, err = pcall(record.onDone, completed and not record.cancelled)
		if not ok then
			warn("[UVK] camera onDone failed: " .. tostring(err))
		end
	end
end

local unbind: () -> ()

local function before()
	releaseOffset()
end

local function after(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	if savedCamera and savedCamera ~= camera then
		-- The camera was replaced (Roblox does this on some respawns). The saved values belong to
		-- an instance that is gone, so drop them and take the new camera's own state as the base.
		local hadTakeover = stack:saved("cameraType") ~= nil
		stack:release()
		savedCamera = camera
		stack:save("fov", camera.FieldOfView)
		if hadTakeover and stack:hasTakeover() then
			stack:save("cameraType", camera.CameraType)
			stack:save("subject", camera.CameraSubject)
			stack:save("cframe", camera.CFrame)
			stack:save("focusDistance", focusDistance(camera))
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end

	if stack:count() > 0 then
		for _, record in moves do
			record.age += dt
			local markers = record.markers
			if markers and record.onMarker then
				while record.fired < #markers and markers[record.fired + 1].at <= record.age do
					record.fired += 1
					local ok, err = pcall(record.onMarker, markers[record.fired].name)
					if not ok then
						warn("[UVK] camera onMarker failed: " .. tostring(err))
					end
				end
			end
		end
		local base: CameraLogic.Pose = { fov = stack:saved("fov") or camera.FieldOfView }
		local savedCFrame = stack:saved("cframe")
		if savedCFrame then
			base = poseOf(savedCFrame, stack:saved("focusDistance") or 10, base.fov)
		end
		local result = stack:step(dt, base)
		for _, id in result.finished do
			finishMove(id, true)
		end
		local pose = result.pose
		if result.takeover and pose.position and pose.lookAt then
			local from, to = vector(pose.position), vector(pose.lookAt)
			if (to - from).Magnitude > 1e-3 then
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Scriptable
				end
				camera.CFrame = CFrame.lookAt(from, to)
			end
		end
		if result.active and pose.fov then
			camera.FieldOfView = math.clamp(pose.fov, 1, 120)
		end
		settle()
	end

	if #shakes > 0 then
		local offsets: { CameraLogic.Offset } = {}
		for index = #shakes, 1, -1 do
			local record = shakes[index]
			record.age += dt
			local fade = 1
			if record.stoppedAt then
				fade = 1 - (record.age - record.stoppedAt) / STOP_FADE
			end
			if not record.alive or fade <= 0 or record.age >= record.shake.def.duration then
				record.alive = false
				table.remove(shakes, index)
				continue
			end
			local offset = CameraLogic.sample(record.shake, record.age)
			if fade < 1 then
				offset.x *= fade
				offset.y *= fade
				offset.z *= fade
				offset.pitch *= fade
				offset.yaw *= fade
				offset.roll *= fade
			end
			table.insert(offsets, offset)
		end
		local total = CameraLogic.combine(offsets)
		if not CameraLogic.isZero(total) then
			local baseCFrame = camera.CFrame
			local written = baseCFrame
				* CFrame.new(total.x, total.y, total.z)
				* CFrame.Angles(math.rad(total.pitch), math.rad(total.yaw), math.rad(total.roll))
			camera.CFrame = written
			applied = { camera = camera, base = baseCFrame, written = written }
		end
	end

	if #shakes == 0 and stack:count() == 0 then
		unbind()
	end
end

local function bind()
	if bound then
		return
	end
	bound = true
	local priority = Enum.RenderPriority.Camera.Value
	RunService:BindToRenderStep(PRE_STEP, priority - 1, before)
	RunService:BindToRenderStep(POST_STEP, priority + 1, after)
	local player = Players.LocalPlayer
	if player then
		-- A respawn or the player leaving must never leave the camera overridden.
		table.insert(
			guards,
			player.CharacterAdded:Connect(function()
				Camera.restore({ shakes = false })
			end)
		)
		table.insert(
			guards,
			Players.PlayerRemoving:Connect(function(leaving: Player)
				if leaving == player then
					Camera.restore()
				end
			end)
		)
	end
end

unbind = function()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep(PRE_STEP)
	RunService:UnbindFromRenderStep(POST_STEP)
	for _, connection in guards do
		connection:Disconnect()
	end
	table.clear(guards)
	releaseOffset()
	settle()
end

local function canRun(): boolean
	return RunService:IsClient() and Workspace.CurrentCamera ~= nil
end

-- Shake ---------------------------------------------------------------------------------------

-- Adds a camera shake: a preset name or a CameraLogic.ShakeDef. Returns a handle; stop() fades it
-- out over 0.15 s, cancel() removes it at once. Under reduced motion nothing happens.
function Camera.shake(presetOrOptions: string | CameraLogic.ShakeDef, options: ShakeOptions?): Handle
	local opts: ShakeOptions = options or {}
	local juice = Host.juice("shake")
	local camera = Workspace.CurrentCamera
	if not canRun() or camera == nil or juice <= 0 then
		return inert()
	end
	if opts.position and opts.radius and opts.radius > 0 then
		local distance = (camera.CFrame.Position - opts.position).Magnitude
		juice *= math.clamp(1 - distance / opts.radius, 0, 1)
		if juice <= 0 then
			return inert()
		end
	end
	seedCounter += 1
	local settings: CameraLogic.ShakeOptions = table.clone(opts) :: any
	settings.seed = opts.seed or seedCounter
	local record: ShakeRecord = {
		shake = CameraLogic.makeShake(presetOrOptions, settings, juice),
		age = 0,
		stoppedAt = nil,
		alive = true,
	}
	table.insert(shakes, record)
	bind()
	local function cancel()
		record.alive = false
	end
	return {
		stop = function(blend: boolean?)
			if blend == false then
				cancel()
			elseif record.stoppedAt == nil then
				record.stoppedAt = record.age
			end
		end,
		cancel = cancel,
		finish = cancel,
		isActive = function(): boolean
			return record.alive and record.age < record.shake.def.duration
		end,
	}
end

-- Moves ---------------------------------------------------------------------------------------

local function blendTime(value: number?, default: number): number
	local seconds = math.max(0, value or default)
	return if reduced() then CameraLogic.reducedBlend(seconds) else seconds
end

-- Saves what a move is about to change (first save wins, so nested moves restore to the state
-- before any of them started).
local function prepare(camera: Camera, takeover: boolean)
	if savedCamera ~= camera then
		stack:release()
		savedCamera = camera
	end
	stack:save("fov", camera.FieldOfView)
	if takeover and stack:saved("cameraType") == nil then
		stack:save("cameraType", camera.CameraType)
		stack:save("subject", camera.CameraSubject)
		stack:save("cframe", camera.CFrame)
		stack:save("focusDistance", focusDistance(camera))
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

local function push(
	takeover: boolean,
	options: MoveOptions,
	defaults: { priority: number, blendIn: number, blendOut: number },
	pose: CameraLogic.PoseSource,
	extra: { onMarker: ((name: string) -> ())?, markers: { [string]: number }? }?
): Handle
	local camera = Workspace.CurrentCamera
	if not canRun() or camera == nil then
		return inert()
	end
	prepare(camera, takeover)
	local id = stack:push({
		priority = options.priority or defaults.priority,
		blendIn = blendTime(options.blendIn, defaults.blendIn),
		blendOut = blendTime(options.blendOut, defaults.blendOut),
		duration = options.duration,
		takeover = takeover,
		easing = options.easing,
		pose = pose,
	})
	local markers: { { name: string, at: number } }? = nil
	if extra and extra.markers then
		local list: { { name: string, at: number } } = {}
		for name, at in extra.markers do
			table.insert(list, { name = name, at = at })
		end
		type Marker = { name: string, at: number }
		table.sort(list, function(a: Marker, b: Marker): boolean
			return if a.at == b.at then a.name < b.name else a.at < b.at
		end)
		markers = list
	end
	local record: MoveRecord = {
		id = id,
		age = 0,
		onDone = options.onDone,
		onMarker = extra and extra.onMarker,
		markers = markers,
		fired = 0,
		cancelled = false,
	}
	moves[id] = record
	bind()
	local function cancel()
		if stack:remove(id, true) then
			record.cancelled = true
			finishMove(id, false)
			settle()
		end
	end
	return {
		-- Blends back to the camera underneath and restores it. stop(false) cuts back at once.
		stop = function(blend: boolean?)
			if blend == false then
				cancel()
			elseif stack:has(id) and not stack:isEnding(id) then
				record.cancelled = true
				stack:remove(id)
			end
		end,
		cancel = cancel,
		-- Ends the move as if its time had run out (onDone receives true).
		finish = function()
			stack:finish(id)
		end,
		isActive = function(): boolean
			return stack:has(id)
		end,
	}
end

-- A function returning the target's current position, so moves follow a moving Instance.
local function tracker(target: Target): () -> CameraLogic.Vec3
	local kind = typeof(target)
	if kind == "Vector3" then
		local fixed = vec(target :: Vector3)
		return function(): CameraLogic.Vec3
			return fixed
		end
	elseif kind == "CFrame" then
		local fixed = vec((target :: CFrame).Position)
		return function(): CameraLogic.Vec3
			return fixed
		end
	end
	local instance = target :: Instance
	local last: CameraLogic.Vec3 = { 0, 0, 0 }
	return function(): CameraLogic.Vec3
		if instance.Parent ~= nil then
			if instance:IsA("PVInstance") then
				last = vec(instance:GetPivot().Position)
			elseif instance:IsA("Attachment") then
				last = vec(instance.WorldPosition)
			end
		end
		return last
	end
end

local function radiusOf(target: Target): number?
	if typeof(target) ~= "Instance" then
		return nil
	end
	local instance = target :: Instance
	if instance:IsA("Model") then
		return instance:GetExtentsSize().Magnitude / 2
	elseif instance:IsA("BasePart") then
		return instance.Size.Magnitude / 2
	end
	return nil
end

-- The yaw from which the camera currently sees `point`, so a move starts on the side it is on.
local function currentAngle(camera: Camera, point: CameraLogic.Vec3): number
	local position = camera.CFrame.Position
	return math.deg(math.atan2(position.X - point[1], position.Z - point[3]))
end

local function aspectOf(camera: Camera): number
	local size = camera.ViewportSize
	return if size.Y > 0 then size.X / size.Y else 16 / 9
end

-- Eases the field of view to `target` degrees and holds it until the handle is stopped (or for
-- options.duration seconds). The game camera keeps control.
function Camera.fov(target: number, options: MoveOptions?): Handle
	local opts: MoveOptions = options or {}
	local pose: CameraLogic.Pose = { fov = math.clamp(target, 1, 120) }
	return push(false, opts, { priority = 0, blendIn = 0.35, blendOut = 0.3 }, pose)
end

-- Magnifies the view by `factor` (1.5 = 50% closer) through the field of view. With
-- options.mode = "distance" the camera dollies toward its focus instead (a takeover move).
function Camera.zoom(factor: number, options: (MoveOptions & { mode: ("fov" | "distance")? })?): Handle
	local opts: MoveOptions & { mode: ("fov" | "distance")? } = options or {}
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return inert()
	end
	if opts.mode == "distance" then
		local start = poseOf(camera.CFrame, focusDistance(camera), nil)
		return push(true, opts, { priority = 0, blendIn = 0.4, blendOut = 0.4 }, CameraLogic.zoomPose(start, factor))
	end
	local function pose(_age: number, under: CameraLogic.Pose): CameraLogic.Pose
		return { fov = CameraLogic.zoomFov(under.fov or 70, factor) }
	end
	return push(false, opts, { priority = 0, blendIn = 0.35, blendOut = 0.3 }, pose)
end

-- A quick field-of-view kick of `amount` degrees that springs back. Skipped under reduced motion.
function Camera.punchFov(amount: number, options: MoveOptions?): Handle
	local opts: MoveOptions = table.clone(options or {}) :: any
	local scaled = amount * Host.juice("scale")
	if reduced() or scaled == 0 then
		return inert()
	end
	local duration = math.max(0.05, opts.duration or 0.4)
	opts.duration = duration
	opts.blendIn = 0
	opts.blendOut = 0
	local function pose(age: number, under: CameraLogic.Pose): CameraLogic.Pose
		return { fov = (under.fov or 70) + CameraLogic.punchFov(scaled, age, duration) }
	end
	return push(false, opts, { priority = 5, blendIn = 0, blendOut = 0 }, pose)
end

-- Holds the camera at a distance, yaw and elevation from a target, looking at it. The target may
-- move. Restores the game's camera when stopped.
function Camera.focus(target: Target, options: FocusOptions?): Handle
	local opts: FocusOptions = options or {}
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return inert()
	end
	local track = tracker(target)
	local radius = radiusOf(target)
	local framing: CameraLogic.FocusOptions = {
		distance = opts.distance or (if radius
			then CameraLogic.fitDistance(radius, opts.fov or camera.FieldOfView, aspectOf(camera), 1.6)
			else 12),
		angle = opts.angle or currentAngle(camera, track()),
		elevation = opts.elevation,
		height = opts.height,
		fov = opts.fov,
	}
	local function pose(): CameraLogic.Pose
		return CameraLogic.focusPose(track(), framing)
	end
	return push(true, opts, { priority = 10, blendIn = 0.6, blendOut = 0.6 }, pose)
end

-- Circles a target at options.speed degrees per second until stopped. Under reduced motion the
-- camera holds the starting angle instead of circling.
function Camera.orbit(target: Target, options: OrbitOptions?): Handle
	local opts: OrbitOptions = options or {}
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return inert()
	end
	local track = tracker(target)
	local radius = radiusOf(target)
	local still = reduced()
	local framing: CameraLogic.OrbitOptions = {
		distance = opts.distance or (if radius
			then CameraLogic.fitDistance(radius, opts.fov or camera.FieldOfView, aspectOf(camera), 1.8)
			else 14),
		angle = opts.angle or currentAngle(camera, track()),
		elevation = opts.elevation,
		height = opts.height,
		fov = opts.fov,
		speed = if still then 0 else opts.speed,
	}
	local function pose(age: number): CameraLogic.Pose
		return CameraLogic.orbitPose(track(), framing, age)
	end
	return push(true, opts, { priority = 10, blendIn = 0.7, blendOut = 0.6 }, pose)
end

-- Travels from one camera CFrame to another over options.travel seconds (default 1.5), then holds
-- until stopped or until options.duration runs out. Under reduced motion it cuts to the end.
function Camera.pan(from: CFrame, to: CFrame, options: (MoveOptions & { travel: number? })?): Handle
	local opts: MoveOptions & { travel: number? } = options or {}
	local travel = if reduced() then 0 else math.max(0, opts.travel or 1.5)
	local reach = 10
	local start = poseOf(from, reach, opts.fov)
	local finish = poseOf(to, reach, opts.fov)
	local easing = opts.easing or "sineInOut"
	local function pose(age: number): CameraLogic.Pose
		local alpha = if travel > 0 then math.clamp(age / travel, 0, 1) else 1
		return CameraLogic.panPose(start, finish, alpha, easing)
	end
	local moveOptions: MoveOptions = table.clone(opts) :: any
	moveOptions.easing = nil -- `easing` shapes the travel; the stack blend keeps its default
	return push(true, moveOptions, { priority = 10, blendIn = 0.3, blendOut = 0.5 }, pose)
end

-- Plays a cinematic recipe around a target: PetReveal, RewardReveal, AreaUnlock, Teleport, or any
-- "cinematic" preset registered in Camera.registry. options.onMarker(name) fires at the recipe's
-- named beats (for example "reveal"); options.onDone(completed) when the camera is handed back.
function Camera.cinematic(name: string, target: Target?, options: CinematicOptions?): Handle
	local opts: CinematicOptions = options or {}
	local preset = CameraLogic.registry:get(name)
	local recipe: CameraLogic.Cinematic? = preset.data and preset.data.cinematic
	if recipe == nil then
		error("camera preset " .. name .. " is not a cinematic", 2)
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return inert()
	end
	if recipe.takeover and target == nil then
		error("cinematic " .. name .. " needs a target", 2)
	end
	local still = reduced()
	local track = tracker(if target ~= nil then target else Vector3.zero)
	local radius = if target ~= nil then radiusOf(target) else nil
	local fov = opts.fov or camera.FieldOfView
	local distance = opts.distance
	if distance == nil and radius and name ~= "AreaUnlock" then
		distance = math.max(4, CameraLogic.fitDistance(radius, fov, aspectOf(camera), 1.7))
	end
	local framing: CameraLogic.CinematicFraming = {
		distance = distance,
		angle = opts.angle or (if recipe.takeover then currentAngle(camera, track()) else nil),
		elevation = opts.elevation,
		height = opts.height,
		fov = fov,
	}
	local function pose(age: number, under: CameraLogic.Pose): CameraLogic.Pose
		if not recipe.takeover then
			local relative: CameraLogic.CinematicFraming = { fov = under.fov or fov }
			return CameraLogic.cinematicPose(recipe, track(), relative, age, still)
		end
		return CameraLogic.cinematicPose(recipe, track(), framing, age, still)
	end
	local moveOptions: MoveOptions = table.clone(opts) :: any
	moveOptions.duration = opts.duration or recipe.duration
	moveOptions.fov = nil
	return push(
		recipe.takeover,
		moveOptions,
		{ priority = 10, blendIn = recipe.blendIn, blendOut = recipe.blendOut },
		pose,
		{ onMarker = opts.onMarker, markers = recipe.markers }
	)
end

-- Force-releases everything: removes every move, removes the shake offset and puts CameraType,
-- CameraSubject, CFrame and FieldOfView back. Pass { shakes = false } to keep shakes running.
function Camera.restore(options: { shakes: boolean? }?)
	local ids = stack:clear()
	for _, id in ids do
		local record = moves[id]
		if record then
			record.cancelled = true
		end
		finishMove(id, false)
	end
	table.clear(moves)
	releaseOffset()
	settle()
	if not (options and options.shakes == false) then
		for _, record in shakes do
			record.alive = false
		end
		table.clear(shakes)
	end
	if #shakes == 0 then
		unbind()
	end
end

-- True while any shake or move is running.
function Camera.isActive(): boolean
	return bound and (#shakes > 0 or stack:count() > 0)
end

-- Numbers for the debug overlay.
function Camera.stats(): { shakes: number, moves: number, bound: boolean }
	return { shakes = #shakes, moves = stack:count(), bound = bound }
end

return Camera
