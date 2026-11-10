--!strict
-- Object animation (Visuals.Objects): plays the presets in ObjectsLogic on a Model, BasePart,
-- Attachment or GuiObject.
--
--   local float = Objects.animate(coin, "Float")              -- loops until stopped
--   Objects.animate(chest, "SquashStretch")                   -- one-shot
--   Objects.animate(orb, "Collect", { target = Vector3.new(0, 4, -6), onDone = function() ... end })
--   Objects.stop(coin, true)                                  -- stop and return to rest
--
-- How it works:
--   * Every frame is composed from the rest state stored when the animation started (pivot, size,
--     scale, transparency), never from the previous frame, so nothing drifts and restore is exact.
--   * One Host.clock job updates every live animation. It exists only while something is animating.
--   * Loops far from the camera are redrawn less often on lower quality levels, are paused while
--     the target is outside the DataModel, and end when the target is destroyed.
--   * Reduced motion: loops do not start; one-shots jump to their end state.
--
-- Anchored parts only (by default): animating an unanchored, physics-simulated part by CFrame
-- fights the physics solver every frame. Such targets are skipped with one warning; pass
-- { allowUnanchored = true } if you know the part is not simulated.
--
-- Models scale uniformly (Model:ScaleTo), so squash and stretch on a Model shows as the vertical
-- component only; parts and attachments' parents get true non-uniform squash through Size.
--
-- NOT run in Studio: see README.md.

local Workspace = game:GetService("Workspace")

local Host = require("../Runtime/Host")
local ObjectsLogic = require("./ObjectsLogic")
local Props = require("../Runtime/Props")

export type Handle = {
	stop: (restore: boolean?) -> (),
	cancel: () -> (),
	finish: () -> (),
	isActive: () -> boolean,
}

export type Options = {
	amplitude: number?,
	speed: number?,
	duration: number?,
	axis: string?,
	phase: number?,
	intensity: number?,
	target: (Vector3 | { number })?, -- Collect / Teleport: end point relative to rest
	onDone: ((completed: boolean) -> ())?,
	restore: boolean?, -- one-shots: return to rest when finished (default false)
	allowUnanchored: boolean?,
	fresh: boolean?, -- ignore the rest state remembered from an earlier hide (ScaleOut, Dissolve)
}

type Kind = string -- "model" | "part" | "attachment" | "gui"

type Rest = {
	cframe: CFrame?,
	modelScale: number?,
	size: Vector3?,
	position: UDim2?,
	rotation: number?,
	guiScale: number?,
	fade: number?,
	transparency: { [Instance]: number }?,
}

type Record = {
	target: Instance,
	kind: Kind,
	id: string,
	params: ObjectsLogic.Params,
	loop: boolean,
	fades: boolean,
	t: number,
	slot: number,
	rest: Rest,
	world: Vector3?,
	lastScale: number,
	lastFade: number,
	scaled: boolean,
	alive: boolean,
	restoreOnDone: boolean,
	onDone: ((completed: boolean) -> ())?,
}

local Objects = {}

Objects.registry = ObjectsLogic.registry

local records: { [Instance]: Record } = {}
-- Rest states of objects an animation left hidden (scaled to nothing or faded out), so the next
-- animation on them starts from the real size and transparency instead of the hidden one.
local hidden: { [Instance]: Rest } = setmetatable({}, { __mode = "k" }) :: any
local removeJob: (() -> ())? = nil
local frame = 0
local started = 0
local warnedUnanchored = false

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

local function kindOf(target: any): Kind?
	if typeof(target) ~= "Instance" then
		return nil
	elseif target:IsA("Model") then
		return "model"
	elseif target:IsA("BasePart") then
		return "part"
	elseif target:IsA("Attachment") then
		return "attachment"
	elseif target:IsA("GuiObject") then
		return "gui"
	end
	return nil
end

local function anchored(target: Instance, kind: Kind): boolean
	if kind == "part" then
		return (target :: BasePart).Anchored
	elseif kind == "model" then
		local model = target :: Model
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		return root == nil or root.Anchored
	end
	return true
end

local function fadeTargets(target: Instance): { [Instance]: number }
	local out: { [Instance]: number } = {}
	local function add(instance: Instance)
		if instance:IsA("BasePart") or instance:IsA("Decal") then
			out[instance] = (instance :: any).Transparency
		end
	end
	add(target)
	for _, descendant in target:GetDescendants() do
		add(descendant)
	end
	return out
end

local function capture(target: Instance, kind: Kind, fades: boolean, remembered: Rest?): Rest
	local rest: Rest = {}
	if kind == "model" then
		local model = target :: Model
		rest.cframe = model:GetPivot()
		rest.modelScale = if remembered and remembered.modelScale then remembered.modelScale else model:GetScale()
	elseif kind == "part" then
		local part = target :: BasePart
		rest.cframe = part.CFrame
		rest.size = if remembered and remembered.size then remembered.size else part.Size
	elseif kind == "attachment" then
		rest.cframe = (target :: Attachment).CFrame
	else
		local gui = target :: GuiObject
		rest.position = gui.Position
		rest.rotation = gui.Rotation
		local scale = gui:FindFirstChild("UrkScale")
		rest.guiScale = if remembered and remembered.guiScale
			then remembered.guiScale
			elseif scale and scale:IsA("UIScale") then scale.Scale
			else 1
		if fades then
			local fade = Props.adapter.read(gui, "GroupFade")
			rest.fade = if remembered and remembered.fade then remembered.fade elseif fade then fade[1] else 0
		end
	end
	if fades and kind ~= "gui" and kind ~= "attachment" then
		rest.transparency = if remembered and remembered.transparency
			then remembered.transparency
			else fadeTargets(target)
	end
	return rest
end

local function offsetCFrame(rest: CFrame, sample: ObjectsLogic.Sample): CFrame
	local p, r = sample.position, sample.rotation
	local moved = CFrame.new(rest.Position + Vector3.new(p[1], p[2], p[3])) * rest.Rotation
	if r[1] ~= 0 or r[2] ~= 0 or r[3] ~= 0 then
		moved *= CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	end
	return moved
end

local function applyFade(record: Record, amount: number)
	if not record.fades or amount == record.lastFade then
		return
	end
	record.lastFade = amount
	local rest = record.rest
	if record.kind == "gui" then
		local base = rest.fade or 0
		Props.adapter.write(record.target, "GroupFade", { base + (1 - base) * amount })
		return
	end
	local originals = rest.transparency
	if originals then
		for instance, original in originals do
			if instance.Parent ~= nil then
				local object: any = instance
				object.Transparency = original + (1 - original) * amount
			end
		end
	end
end

-- Writes one sample. Everything is derived from record.rest.
local function apply(record: Record, sample: ObjectsLogic.Sample)
	local rest = record.rest
	local scale = sample.scale
	if record.kind == "model" then
		local model = record.target :: Model
		local uniform = scale[2]
		if rest.modelScale and math.abs(uniform - record.lastScale) > 0.002 then
			record.lastScale = uniform
			model:ScaleTo(math.max(0.001, rest.modelScale * uniform))
		end
		if rest.cframe then
			model:PivotTo(offsetCFrame(rest.cframe, sample))
		end
	elseif record.kind == "part" then
		local part = record.target :: BasePart
		local changed = scale[1] ~= 1 or scale[2] ~= 1 or scale[3] ~= 1
		if rest.size and (changed or record.scaled) then
			record.scaled = changed
			part.Size = Vector3.new(
				math.max(0.001, rest.size.X * scale[1]),
				math.max(0.001, rest.size.Y * scale[2]),
				math.max(0.001, rest.size.Z * scale[3])
			)
		end
		if rest.cframe then
			part.CFrame = offsetCFrame(rest.cframe, sample)
		end
	elseif record.kind == "attachment" then
		local attachment = record.target :: Attachment
		if rest.cframe then
			local p, r = sample.position, sample.rotation
			attachment.CFrame = rest.cframe
				* CFrame.new(p[1], p[2], p[3])
				* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		end
	else
		local gui = record.target :: GuiObject
		local p = sample.position
		if rest.position then
			-- y is up in sample space and down on screen.
			gui.Position = rest.position + UDim2.fromOffset(p[1], -p[2])
		end
		gui.Rotation = (rest.rotation or 0) + sample.rotation[3]
		local uniform = scale[2]
		if uniform ~= 1 or record.scaled then
			record.scaled = uniform ~= 1
			Props.scaleOf(gui).Scale = math.max(0, (rest.guiScale or 1) * uniform)
		end
	end
	applyFade(record, sample.transparency)
end

local function restore(record: Record)
	if record.target.Parent == nil then
		return
	end
	-- Force every channel to be rewritten, whatever was skipped as unchanged.
	record.lastScale = -1
	record.lastFade = -1
	record.scaled = true
	apply(record, ObjectsLogic.rest())
	hidden[record.target] = nil
end

-- Ends a record. `completed` goes to onDone.
local function close(record: Record, completed: boolean)
	if not record.alive then
		return
	end
	record.alive = false
	if records[record.target] == record then
		records[record.target] = nil
	end
	if record.onDone then
		local ok, err = pcall(record.onDone, completed)
		if not ok then
			warn("[UVK] object onDone failed: " .. tostring(err))
		end
	end
end

local function complete(record: Record)
	if not record.alive then
		return
	end
	local final = ObjectsLogic.endState(record.id, record.params)
	record.lastScale = -1
	record.lastFade = -1
	record.scaled = true
	if record.restoreOnDone then
		restore(record)
	else
		apply(record, final)
		local s = final.scale
		if final.transparency ~= 0 or s[1] ~= 1 or s[2] ~= 1 or s[3] ~= 1 then
			hidden[record.target] = record.rest
		else
			hidden[record.target] = nil
		end
	end
	close(record, true)
end

local function step(dt: number): boolean?
	frame += 1
	local profile = Host.profile()
	local camera = Workspace.CurrentCamera
	local viewer = if camera then camera.CFrame.Position else nil
	for target, record in records do
		if not Props.adapter.alive(target) then
			close(record, false)
			continue
		end
		if not target:IsDescendantOf(game) then
			continue -- paused until it is in the DataModel
		end
		record.t += dt
		if record.loop and record.world and viewer then
			local every = ObjectsLogic.updateEvery(
				(record.world - viewer).Magnitude,
				profile.fadeDistance,
				profile.maxDistance,
				profile.dropOptional
			)
			if every == 0 or (every > 1 and (frame + record.slot) % every ~= 0) then
				continue
			end
		end
		local sample = ObjectsLogic.sample(record.id, record.t, record.params)
		if sample.done then
			complete(record)
		else
			apply(record, sample)
		end
	end
	if next(records) == nil then
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

local function targetVector(value: (Vector3 | { number })?): { number }?
	if typeof(value) == "Vector3" then
		local v = value :: Vector3
		return { v.X, v.Y, v.Z }
	elseif type(value) == "table" then
		return value :: { number }
	end
	return nil
end

-- Plays preset `presetId` on `target`. A new animation on a target replaces the running one and
-- inherits its rest state, so chains (ScaleIn, then Float) never drift.
function Objects.animate(target: Instance, presetId: string, options: Options?): Handle
	if not ObjectsLogic.has(presetId) then
		error("unknown object animation: " .. tostring(presetId), 2)
	end
	local opts: Options = options or {}
	local kind = kindOf(target)
	if kind == nil then
		warn("[UVK] Objects.animate: unsupported target " .. typeof(target))
		return inert()
	end
	if not opts.allowUnanchored and not anchored(target, kind) then
		if not warnedUnanchored then
			warnedUnanchored = true
			warn(
				"[UVK] Objects.animate skipped an unanchored target ("
					.. target:GetFullName()
					.. "): animating simulated parts fights physics. Anchor it or pass allowUnanchored = true."
			)
		end
		return inert()
	end

	local loop = ObjectsLogic.isLoop(presetId)
	local fades = ObjectsLogic.usesTransparency(presetId)
	local params: ObjectsLogic.Params = {
		amplitude = opts.amplitude,
		speed = opts.speed,
		duration = opts.duration,
		axis = opts.axis,
		phase = opts.phase,
		intensity = opts.intensity,
		target = targetVector(opts.target),
	}
	started += 1
	if loop and params.phase == nil then
		params.phase = ObjectsLogic.phaseFor(started)
	end

	local previous = records[target]
	local rest: Rest
	if previous then
		-- Put the object back first so the new rest state is the true one, then reuse it.
		restore(previous)
		close(previous, false)
		rest = capture(target, kind, fades, nil)
	else
		rest = capture(target, kind, fades, if opts.fresh then nil else hidden[target])
	end

	local world: Vector3? = nil
	if kind == "attachment" then
		world = (target :: Attachment).WorldPosition
	elseif rest.cframe then
		world = rest.cframe.Position
	end

	local record: Record = {
		target = target,
		kind = kind,
		id = presetId,
		params = params,
		loop = loop,
		fades = fades,
		t = 0,
		slot = started,
		rest = rest,
		world = world,
		lastScale = 1,
		lastFade = 0,
		scaled = false,
		alive = true,
		restoreOnDone = opts.restore == true,
		onDone = opts.onDone,
	}
	if hidden[target] and not opts.fresh then
		-- The object is currently hidden: make the first frame write every channel.
		record.lastScale = -1
		record.lastFade = -1
		record.scaled = true
	end

	local function stop(restoreRest: boolean?)
		if not record.alive then
			return
		end
		local back = if restoreRest == nil then loop else restoreRest
		if back then
			restore(record)
		end
		close(record, false)
	end
	local handle: Handle = {
		stop = stop,
		cancel = function()
			stop(nil)
		end,
		-- One-shots jump to their end state; loops return to rest.
		finish = function()
			if not record.alive then
				return
			end
			if loop then
				restore(record)
				close(record, true)
			else
				complete(record)
			end
		end,
		isActive = function(): boolean
			return record.alive
		end,
	}

	if Host.settings().reducedMotion then
		if loop then
			record.alive = false
			return inert()
		end
		records[target] = record
		complete(record)
		return handle
	end

	records[target] = record
	apply(record, ObjectsLogic.sample(presetId, 0, params)) -- first visual change on this frame
	ensureJob()
	return handle
end

-- Stops the animation on `target`. restore = true also returns it to its rest state, including an
-- object an earlier one-shot left hidden. Default: loops restore, one-shots stay where they are.
function Objects.stop(target: Instance, restore_: boolean?)
	local record = records[target]
	if record then
		local back = if restore_ == nil then record.loop else restore_
		if back then
			restore(record)
		end
		close(record, false)
		return
	end
	local remembered = hidden[target]
	local kind = kindOf(target)
	if restore_ and remembered and kind then
		local ghost: Record = {
			target = target,
			kind = kind,
			id = "Appear",
			params = {},
			loop = false,
			fades = true,
			t = 0,
			slot = 0,
			rest = capture(target, kind, true, remembered),
			world = nil,
			lastScale = -1,
			lastFade = -1,
			scaled = true,
			alive = false,
			restoreOnDone = false,
			onDone = nil,
		}
		restore(ghost)
	end
end

function Objects.isAnimating(target: Instance): boolean
	return records[target] ~= nil
end

-- Stops everything (restoring loops). For teardown and tests.
function Objects.stopAll(restore_: boolean?)
	local live: { Record } = {}
	for _, record in records do
		table.insert(live, record)
	end
	for _, record in live do
		Objects.stop(record.target, restore_)
	end
end

-- Number of live object animations.
function Objects.count(): number
	local n = 0
	for _ in records do
		n += 1
	end
	return n
end

return Objects
