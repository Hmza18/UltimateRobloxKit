--!strict
-- Rewards: rarity-driven reward reveals (Visuals.Rewards).
--
--   local handle = Rewards.reveal("Legendary", { name = "Dragon", amount = 1, icon = "pet" })
--   handle.Completed:Connect(function(dismissed) ... end)
--
-- A reveal is an overlay: a dim backdrop, a ray burst, the reward tile, the rarity label, the
-- name and a counting amount. RewardsLogic plans the timeline from the rarity's profile and this
-- module runs it as a Sequence, so a reveal can always be skipped (first press: jump to the
-- settled state; second press: dismiss) or cancelled without leaving anything behind.
--
-- Everything is UI unless options.position is given; then the profile's VFX also play in the
-- world there. Reveals are cosmetic: call them after the server has granted the reward.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local RewardView = require("./RewardView")
local RewardsLogic = require("./RewardsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Reward = RewardView.Reward

export type Options = {
	parent: Instance?, -- a PlayerGui or GUI container (default: the local player's PlayerGui)
	position: (Vector3 | CFrame | Instance)?, -- play the profile's VFX in the world here
	speed: number?,
	skipAnticipation: boolean?,
	compact: boolean?,
	skippable: boolean?, -- default true
	autoDismiss: boolean?, -- default true: dismiss after the profile's hold
	displayOrder: number?, -- default 900
	hint: string?, -- default "Tap to continue"
	reducedMotion: boolean?, -- default: Host settings
	reducedFlashing: boolean?,
	fastForward: (boolean | number)?,
	threshold: string?, -- batch: rarities at or above this get a full reveal (default "Epic")
	onDismiss: (() -> ())?,
}

export type Handle = {
	skip: () -> (), -- jump to the settled state; when already settled, dismiss
	finish: () -> (), -- alias of skip
	dismiss: () -> (), -- play the exit and complete
	cancel: () -> (), -- remove everything now
	stop: () -> (), -- alias of cancel
	isRunning: () -> boolean,
	Completed: Signal.Signal, -- (dismissed: boolean) true after a normal dismiss, false when cancelled
}

local Rewards = {}

Rewards.Logic = RewardsLogic

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

-- Calls a function of an optional module. A missing module, a missing function or an error all
-- give nil, so a reveal never breaks because another module is absent or skipped an effect.
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
		local stop = handle.stop or handle.cancel
		if type(stop) == "function" then
			pcall(stop)
		end
	end
end

local function planOptions(options: Options): RewardsLogic.Options
	local settings = Host.settings()
	return {
		speed = options.speed,
		skipAnticipation = options.skipAnticipation,
		compact = options.compact,
		reducedMotion = if options.reducedMotion ~= nil then options.reducedMotion else settings.reducedMotion,
		reducedFlashing = if options.reducedFlashing ~= nil then options.reducedFlashing else settings.reducedFlashing,
		quality = settings.level,
		fastForward = options.fastForward,
		threshold = options.threshold,
	}
end

local function isSkipInput(input: InputObject): boolean
	if input.UserInputType == Enum.UserInputType.Gamepad1 or input.UserInputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		return key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA
	end
	return false
end

type View = {
	gui: ScreenGui,
	backdrop: TextButton,
	stage: Frame,
	rays: Frame?,
	glow: Frame,
	tile: Frame,
	flash: Frame,
	label: TextLabel,
	name: TextLabel,
	amount: TextLabel?,
	subtitle: TextLabel?,
	hint: TextLabel,
}

-- The labels a view has (amount and subtitle are optional), with or without the hint.
local function texts(view: View, withHint: boolean): { TextLabel }
	local list: { TextLabel } = { view.label, view.name }
	if view.amount then
		table.insert(list, view.amount)
	end
	if view.subtitle then
		table.insert(list, view.subtitle)
	end
	if withHint then
		table.insert(list, view.hint)
	end
	return list
end

local BACKDROP: { [string]: number } = { none = 1, dim = 0.45, rays = 0.4, wash = 0.35, starfield = 0.2 }

local function buildView(
	gui: ScreenGui,
	reward: Reward,
	plan: RewardsLogic.Plan,
	options: Options,
	trove: Trove.Trove
): View
	local profile = plan.profile
	local open = plan.steps[1].payload

	-- The backdrop is a button so presses never reach the game's UI underneath.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = if open.background == "wash"
		then RewardView.color(profile.secondary):Lerp(Color3.new(0, 0, 0), 0.55)
		else Color3.fromRGB(8, 10, 20)
	backdrop.BackgroundTransparency = 1
	backdrop.ZIndex = 0
	backdrop.Parent = gui

	if open.background == "starfield" then
		-- A fixed scatter of small dots; cheap, and it reads as "somewhere else".
		for index = 1, 26 do
			local star = Instance.new("Frame")
			star.Name = "Star"
			star.BorderSizePixel = 0
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Position = UDim2.fromScale((index * 0.618034) % 1, (index * 0.381966 + 0.07 * (index % 5)) % 1)
			local size = 2 + (index % 3)
			star.Size = UDim2.fromOffset(size, size)
			star.BackgroundColor3 = Color3.new(1, 1, 1)
			star.BackgroundTransparency = 1
			star.ZIndex = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = star
			star.Parent = backdrop
			Motion.tween(star, { BackgroundTransparency = 0.15 + 0.5 * ((index * 3) % 4) / 3 }, {
				duration = 0.5,
				delay = 0.02 * index,
			})
		end
	end

	local safe = RewardView.safeArea(gui)
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.45)
	stage.Size = UDim2.fromScale(0.44, 0.44)
	stage.SizeConstraint = Enum.SizeConstraint.RelativeYY
	stage.ZIndex = 2
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, 360)
	limit.MinSize = Vector2.new(140, 140)
	limit.Parent = stage
	stage.Parent = safe

	local rays: Frame? = nil
	if open.rayCount > 0 then
		local burst = RewardView.rays(stage, open.rayCount, profile.glow)
		RewardView.setScale(burst, 0)
		rays = burst
	end
	local glow = RewardView.glow(stage, profile.glow)
	local tile, cleanupTile = RewardView.tile(reward, profile, stage)
	trove:Add(cleanupTile)
	RewardView.setScale(tile, 0)

	local textSize = 26 + 4 * profile.text.sizeStep
	local label = RewardView.text({
		name = "Rarity",
		text = profile.label,
		parent = stage,
		color = if profile.rank >= 7 then profile.secondary else profile.color,
		maxSize = textSize + 8,
		stroke = profile.text.stroke,
		position = UDim2.fromScale(0.5, -0.02),
		size = UDim2.new(1.8, 0, 0, textSize + 14),
		anchor = Vector2.new(0.5, 1),
	})
	local name = RewardView.text({
		name = "Name",
		text = reward.name or "",
		parent = stage,
		maxSize = textSize,
		position = UDim2.fromScale(0.5, 0.86),
		size = UDim2.new(1.8, 0, 0, textSize + 8),
		anchor = Vector2.new(0.5, 0),
	})
	local nextY = 0.86
	local amount: TextLabel? = nil
	if type(reward.amount) == "number" then
		nextY += 0.17
		amount = RewardView.text({
			name = "Amount",
			text = "x0",
			parent = stage,
			color = profile.glow,
			maxSize = textSize - 2,
			position = UDim2.fromScale(0.5, nextY),
			size = UDim2.new(1.8, 0, 0, textSize + 4),
			anchor = Vector2.new(0.5, 0),
		})
	end
	local subtitle: TextLabel? = nil
	if reward.subtitle and reward.subtitle ~= "" then
		nextY += 0.16
		subtitle = RewardView.text({
			name = "Subtitle",
			text = reward.subtitle,
			parent = stage,
			color = "#D6DCEB",
			maxSize = 18,
			stroke = 1,
			position = UDim2.fromScale(0.5, nextY),
			size = UDim2.new(2, 0, 0, 24),
			anchor = Vector2.new(0.5, 0),
		})
	end
	local hint = RewardView.text({
		name = "Hint",
		text = options.hint or "Tap to continue",
		parent = safe,
		color = "#FFFFFF",
		maxSize = 18,
		stroke = 1,
		position = UDim2.fromScale(0.5, 0.94),
		size = UDim2.new(0.8, 0, 0, 24),
	})

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20
	flash.Active = false
	flash.Parent = gui

	local view: View = {
		gui = gui,
		backdrop = backdrop,
		stage = stage,
		rays = rays,
		glow = glow,
		tile = tile,
		flash = flash,
		label = label,
		name = name,
		amount = amount,
		subtitle = subtitle,
		hint = hint,
	}
	for _, text in texts(view, true) do
		RewardView.setTextAlpha(text, 1)
	end
	return view
end

-- How each reveal style brings the tile in. All of them end at Scale 1, Rotation 0, centred.
local function playStyle(view: View, payload: { [string]: any }, duration: number)
	local tile = view.tile
	local style: string = payload.style
	local spring: string = payload.spring
	local peak = 1 + (payload.punch or 0)
	local centre = UDim2.fromScale(0.5, 0.5)
	local function settle()
		Motion.spring(tile, { Scale = 1 }, spring, { essential = true })
	end
	local function punchIn(from: number, rise: number)
		Motion.tween(tile, { Scale = peak }, {
			duration = rise,
			easing = "cubicOut",
			from = { Scale = from },
			essential = true,
			onDone = function(completed: boolean)
				if completed then
					settle()
				end
			end,
		})
	end
	if style == "bounce" then
		tile.Position = UDim2.fromScale(0.5, 0.1)
		Motion.spring(tile, { Position = centre }, "Bouncy")
		punchIn(0.4, 0.12)
	elseif style == "flip" then
		tile.Rotation = -180
		Motion.tween(tile, { Rotation = 0 }, { duration = math.min(0.4, duration), easing = "backOut" })
		punchIn(0.1, 0.18)
	elseif style == "burst" then
		-- Slams in from oversized: the reverse of a pop.
		Motion.tween(tile, { Scale = 1 }, {
			duration = 0.16,
			easing = "quartOut",
			from = { Scale = 1.9 + (payload.punch or 0) },
			essential = true,
			onDone = function(completed: boolean)
				if completed then
					Motion.punch(tile, "Scale", -(payload.punch or 0) * 0.6, spring)
				end
			end,
		})
	elseif style == "beam" then
		local beam = Instance.new("Frame")
		beam.Name = "Beam"
		beam.BorderSizePixel = 0
		beam.AnchorPoint = Vector2.new(0.5, 1)
		beam.Position = UDim2.fromScale(0.5, 0.6)
		beam.Size = UDim2.fromScale(0.02, 4)
		beam.BackgroundColor3 = view.glow.BackgroundColor3
		beam.BackgroundTransparency = 0.15
		beam.ZIndex = 3
		beam.Parent = view.stage
		Motion.tween(beam, { Size = UDim2.fromScale(0.75, 4), BackgroundTransparency = 1 }, {
			duration = math.min(0.5, duration + 0.1),
			easing = "quartOut",
			onDone = function()
				beam:Destroy()
			end,
		})
		tile.Position = UDim2.fromScale(0.5, 0.62)
		Motion.spring(tile, { Position = centre }, "Soft")
		punchIn(0, 0.16)
	elseif style == "shatter" then
		tile.Rotation = 14
		Motion.spring(tile, { Rotation = 0 }, "Elastic")
		punchIn(0.25, 0.1)
		RewardView.burst(view.stage, view.glow.BackgroundColor3, 10, 1.1)
	elseif style == "eclipse" then
		-- A dark disc covers the tile and shrinks away while the tile grows behind it.
		local disc = Instance.new("Frame")
		disc.Name = "Eclipse"
		disc.BorderSizePixel = 0
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = centre
		disc.Size = UDim2.fromScale(1.1, 1.1)
		disc.BackgroundColor3 = Color3.new(0, 0, 0)
		disc.ZIndex = 7
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		disc.Parent = view.stage
		Motion.tween(disc, { Size = UDim2.fromScale(0, 0) }, {
			duration = math.min(0.45, duration + 0.1),
			easing = "cubicInOut",
			onDone = function()
				disc:Destroy()
			end,
		})
		punchIn(0.6, 0.3)
	elseif style == "spiral" then
		tile.Rotation = -360
		Motion.tween(tile, { Rotation = 0 }, { duration = math.min(0.45, duration), easing = "quartOut" })
		punchIn(0, 0.2)
	else
		punchIn(0, 0.14)
	end
end

-- Reveals one reward with the presentation of `rarity`. Unknown rarities use Common.
function Rewards.reveal(rarity: string, reward: Reward?, options: Options?): Handle
	local opts: Options = options or {}
	local data: Reward = reward or {}
	local plan = RewardsLogic.plan(rarity, data, planOptions(opts))
	local profile = plan.profile
	local completed = Signal.new()
	local trove = Trove.new()
	local state: string = "revealing" -- revealing | settled | dismissing | done
	local sequence: any = nil
	local dismissing = false
	local handle: Handle

	local function finishWith(dismissed: boolean)
		if state == "done" then
			return
		end
		state = "done"
		if sequence then
			sequence:Cancel()
		end
		trove:Clean()
		if dismissed and opts.onDismiss then
			task.spawn(opts.onDismiss)
		end
		completed:Fire(dismissed)
	end

	local gui = RewardView.screen(opts.parent, "UVKReward", opts.displayOrder or 900)
	if gui == nil then
		-- Nowhere to draw (no PlayerGui): complete at once so callers waiting on it continue.
		state = "done"
		local noop = function() end
		handle = {
			skip = noop,
			finish = noop,
			dismiss = noop,
			cancel = noop,
			stop = noop,
			isRunning = function(): boolean
				return false
			end,
			Completed = completed,
		}
		Host.clock:after(0, function()
			completed:Fire(false)
		end)
		return handle
	end
	trove:Add(gui)
	local view = buildView(gui, data, plan, opts, trove)
	local position = opts.position
	local amountFinal = if type(data.amount) == "number" then data.amount else 0

	-- Camera effects restore themselves when stopped; keep every handle so cancel stops them.
	local function track(effect: any): any
		if effect ~= nil then
			trove:Add(function()
				endHandle(effect)
			end)
		end
		return effect
	end

	local function setAmount(value: number)
		if view.amount then
			view.amount.Text = "x" .. RewardView.format(value)
		end
	end

	-- The final state, written directly. Used when the reveal is skipped.
	local function settleNow()
		for _, object in { view.tile, view.glow, view.backdrop, view.label, view.name } :: { Instance } do
			Motion.stop(object)
		end
		local open = plan.steps[1].payload
		view.backdrop.BackgroundTransparency = BACKDROP[open.background] or 1
		view.tile.Position = UDim2.fromScale(0.5, 0.5)
		view.tile.Rotation = 0
		RewardView.setScale(view.tile, 1)
		view.glow.BackgroundTransparency = 0.35
		RewardView.setScale(view.glow, 1)
		if view.rays then
			RewardView.setScale(view.rays, 1)
		end
		for _, text in texts(view, false) do
			Motion.stop(text)
			local stroke = text:FindFirstChildOfClass("UIStroke")
			if stroke then
				Motion.stop(stroke)
			end
			RewardView.setTextAlpha(text, 0)
		end
		setAmount(amountFinal)
		view.flash.BackgroundTransparency = 1
		for _, child in view.stage:GetChildren() do
			if child.Name == "Beam" or child.Name == "Eclipse" or child.Name == "Spark" then
				child:Destroy()
			end
		end
	end

	local function dismiss()
		if state ~= "settled" then
			return
		end
		state = "dismissing"
		dismissing = true
		try(audioModule(), "play", "ui.close")
		Motion.tween(view.tile, { Scale = 0 }, { duration = plan.dismissDuration, easing = "backIn", essential = true })
		Motion.tween(view.backdrop, { BackgroundTransparency = 1 }, { duration = plan.dismissDuration })
		Motion.tween(view.glow, { BackgroundTransparency = 1 }, { duration = plan.dismissDuration })
		if view.rays then
			Motion.tween(view.rays, { Scale = 0 }, { duration = plan.dismissDuration, essential = true })
		end
		for _, text in texts(view, true) do
			RewardView.fadeText(text, 1, plan.dismissDuration * 0.8)
		end
		trove:Add(Host.clock:after(plan.dismissDuration, function()
			finishWith(true)
		end))
	end

	local function settled(skipped: boolean)
		if state ~= "revealing" then
			return
		end
		state = "settled"
		local untilHint = if skipped then 0.25 else plan.hintAt - plan.settledAt
		trove:Add(Host.clock:after(untilHint, function()
			if handle.isRunning() and not dismissing then
				RewardView.fadeText(view.hint, 0.2, 0.25)
			end
		end))
		if opts.autoDismiss ~= false then
			trove:Add(Host.clock:after(plan.dismissAt - plan.settledAt, dismiss))
		end
	end

	local handlers: { [string]: (step: RewardsLogic.Step, ctx: any) -> any } = {}

	function handlers.open(step: RewardsLogic.Step): any
		local target = BACKDROP[step.payload.background] or 1
		if target < 1 then
			Motion.tween(view.backdrop, { BackgroundTransparency = target }, { duration = step.duration or 0.15 })
		end
		local rays = view.rays
		if rays and step.payload.raySpeed > 0 then
			Motion.tween(rays, { Rotation = 360 }, {
				duration = 360 / step.payload.raySpeed,
				easing = "linear",
				repeatCount = -1,
				from = { Rotation = 0 },
			})
		end
		return nil
	end

	function handlers.anticipate(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		-- The glow swells and the hidden tile shows as a small trembling silhouette.
		local duration = step.duration or 0.3
		Motion.tween(view.glow, { BackgroundTransparency = 0.25, Scale = 1.15 }, {
			duration = duration,
			easing = "quadIn",
			from = { Scale = 0.3 },
		})
		Motion.tween(
			view.tile,
			{ Scale = 0.22 },
			{ duration = duration, easing = "anticipate", from = { Scale = 0.05 } }
		)
		return nil
	end

	function handlers.shake(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		return track(try(cameraModule(), "shake", step.payload.preset))
	end

	function handlers.camera(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		local camera = cameraModule()
		if step.payload.cinematic and position ~= nil then
			return track(
				try(camera, "cinematic", step.payload.cinematic, position, { duration = plan.settledAt - step.time })
			)
		end
		local current = Workspace.CurrentCamera
		if step.payload.fov and current then
			-- A short push-in that ends by itself; the Camera module blends the field of view back.
			return track(try(camera, "fov", current.FieldOfView - step.payload.fov, {
				duration = 0.3,
				blendIn = 0.15,
				blendOut = 0.35,
			}))
		end
		return nil
	end

	function handlers.flash(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped or Host.settings().reducedFlashing then
			return nil
		end
		view.flash.BackgroundColor3 = RewardView.color(step.payload.color)
		Motion.tween(view.flash, { BackgroundTransparency = 1 }, {
			duration = step.payload.duration,
			easing = "quadOut",
			from = { BackgroundTransparency = 1 - step.payload.strength },
		})
		return nil
	end

	function handlers.reveal(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		Motion.tween(view.glow, { BackgroundTransparency = 0.35, Scale = 1 }, { duration = 0.3 })
		if view.rays then
			Motion.spring(view.rays, { Scale = 1 }, "Soft", { from = { Scale = 0.2 } })
		end
		playStyle(view, step.payload, step.duration or 0.3)
		return nil
	end

	function handlers.label(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		RewardView.fadeText(view.label, 0, 0.16)
		Motion.spring(view.label, { Scale = 1 }, "Bouncy", { from = { Scale = 1.5 } })
		RewardView.fadeText(view.name, 0, 0.22)
		if view.amount then
			RewardView.fadeText(view.amount, 0, 0.22)
		end
		if view.subtitle then
			RewardView.fadeText(view.subtitle, 0, 0.3)
		end
		if step.payload.shimmer then
			-- A slow breathing scale on the label: a shimmer without any flashing.
			trove:Add(Host.clock:after(0.5, function()
				Motion.tween(view.label, { Scale = 1.06 }, {
					duration = 0.7,
					easing = "sineInOut",
					repeatCount = -1,
					reverses = true,
				})
			end))
		end
		return nil
	end

	function handlers.count(step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			return nil
		end
		local counter = { value = 0 }
		return Motion.tween(counter, { value = amountFinal }, {
			duration = step.duration or 0.4,
			easing = "cubicOut",
			essential = true,
			onStep = function()
				setAmount(counter.value)
			end,
			onDone = function()
				setAmount(amountFinal)
			end,
		})
	end

	function handlers.settle(_step: RewardsLogic.Step, ctx: any): any
		if ctx.skipped then
			settleNow()
		end
		return nil
	end

	local built = Motion.sequence({
		play = function(id: string, params: any): any
			if position ~= nil then
				return try(vfxModule(), "play", id, position, params)
			end
			-- No world position: a UI burst sized by the profile stands in for the particles.
			if id == "RewardGlow" or id == "GoldenShine" or id == "RarityBeam" then
				Motion.punch(view.glow, "Scale", 0.25, "Soft")
			else
				RewardView.burst(view.stage, profile.color, 8 + 8 * profile.particles)
			end
			return nil
		end,
		sound = function(cue: string, soundOptions: any?): any
			return try(audioModule(), "play", cue, soundOptions)
		end,
	})
	for _, step in plan.steps do
		built:At(step.time)
		if step.kind == "vfx" then
			built:Play(step.payload.id, step.payload.params)
		elseif step.kind == "sound" then
			built:Sound(step.payload.cue)
		else
			local handler = handlers[step.kind]
			if handler then
				built:Call(function(ctx: any): any
					return handler(step, ctx)
				end)
			end
		end
	end
	built:OnDone(function(finished: boolean, skipped: boolean)
		if finished then
			settled(skipped)
		end
	end)
	sequence = built

	local function press()
		if opts.skippable == false then
			return
		end
		if state == "revealing" then
			built:Skip()
		elseif state == "settled" then
			dismiss()
		end
	end
	trove:Connect(view.backdrop.Activated, press)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if isSkipInput(input) and UserInputService:GetFocusedTextBox() == nil then
			press()
		end
	end)
	-- If the overlay is destroyed from outside (its parent went away), end cleanly.
	trove:Connect(gui.AncestryChanged, function()
		if gui.Parent == nil then
			finishWith(false)
		end
	end)

	handle = {
		skip = function()
			if state == "revealing" then
				built:Skip()
			elseif state == "settled" then
				dismiss()
			end
		end,
		finish = function()
			if state == "revealing" then
				built:Skip()
			end
		end,
		dismiss = function()
			if state == "revealing" then
				built:Skip()
			end
			dismiss()
		end,
		cancel = function()
			finishWith(false)
		end,
		stop = function()
			finishWith(false)
		end,
		isRunning = function(): boolean
			return state ~= "done"
		end,
		Completed = completed,
	}
	built:Start()
	return handle
end

-- Shows one group of low-rarity rewards as a grid of tiles that pop in one after another.
local function revealGrid(group: RewardsLogic.Group, options: Options): Handle
	local profile = RewardsLogic.get(group.rarity)
	local completed = Signal.new()
	local trove = Trove.new()
	local state: string = "revealing"
	local sequence: any = nil

	local function finishWith(dismissed: boolean)
		if state == "done" then
			return
		end
		state = "done"
		if sequence then
			sequence:Cancel()
		end
		trove:Clean()
		completed:Fire(dismissed)
	end

	local gui = RewardView.screen(options.parent, "UVKRewardGrid", options.displayOrder or 900)
	if gui == nil then
		state = "done"
		Host.clock:after(0, function()
			completed:Fire(false)
		end)
		local noop = function() end
		return {
			skip = noop,
			finish = noop,
			dismiss = noop,
			cancel = noop,
			stop = noop,
			isRunning = function(): boolean
				return false
			end,
			Completed = completed,
		}
	end
	trove:Add(gui)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = gui
	Motion.tween(backdrop, { BackgroundTransparency = 0.45 }, { duration = 0.15 })
	local safe = RewardView.safeArea(gui)
	local title = RewardView.text({
		name = "Title",
		text = profile.label .. " x" .. tostring(#group.items),
		parent = safe,
		color = profile.color,
		maxSize = 30,
		position = UDim2.fromScale(0.5, 0.14),
		size = UDim2.new(0.9, 0, 0, 40),
	})
	local holder = Instance.new("Frame")
	holder.Name = "Grid"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.55)
	holder.Size = UDim2.fromScale(0.86, 0.62)
	holder.Parent = safe
	local layout = Instance.new("UIGridLayout")
	local cell = math.min(1 / group.columns, 1 / group.rows)
	layout.CellSize = UDim2.fromScale(cell * 0.92, cell * 0.92)
	layout.CellPadding = UDim2.fromScale(cell * 0.08, cell * 0.08)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = group.columns
	layout.Parent = holder
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = group.columns / group.rows
	square.Parent = holder

	local tiles: { Frame } = {}
	for index, item in group.items do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. tostring(index)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = index
		slot.Parent = holder
		local reward: Reward = if type(item.reward) == "table" then item.reward else {}
		local tile, cleanupTile = RewardView.tile(reward, profile, slot)
		trove:Add(cleanupTile)
		tile.Size = UDim2.fromScale(0.86, 0.86)
		RewardView.setScale(tile, 0)
		if type(reward.amount) == "number" then
			RewardView.text({
				name = "Amount",
				text = "x" .. RewardView.format(reward.amount),
				parent = tile,
				maxSize = 18,
				position = UDim2.fromScale(0.5, 0.86),
				size = UDim2.fromScale(0.9, 0.26),
				zIndex = 6,
			})
		end
		table.insert(tiles, tile)
	end

	local function dismiss()
		if state ~= "settled" then
			return
		end
		state = "dismissing"
		for _, tile in tiles do
			Motion.tween(tile, { Scale = 0 }, { duration = 0.16, easing = "backIn", essential = true })
		end
		RewardView.fadeText(title, 1, 0.14)
		Motion.tween(backdrop, { BackgroundTransparency = 1 }, { duration = 0.16 })
		trove:Add(Host.clock:after(0.17, function()
			finishWith(true)
		end))
	end

	local built = Motion.sequence({
		sound = function(cue: string, soundOptions: any?): any
			return try(audioModule(), "play", cue, soundOptions)
		end,
	})
	built:Stagger(#tiles, group.stagger, function(branch: any, index: number)
		branch:Sound("ui.pop", { pitch = 1 + 0.02 * math.min(index, 12) })
		branch:Call(function(ctx: any): any
			local tile = tiles[index]
			if ctx.skipped then
				Motion.stop(tile)
				RewardView.setScale(tile, 1)
			else
				Motion.spring(tile, { Scale = 1 }, "Bouncy", { from = { Scale = 0 }, essential = true })
			end
			return nil
		end)
	end)
	built:Wait(0.3)
	built:OnDone(function(finished: boolean, skipped: boolean)
		if not finished or state ~= "revealing" then
			return
		end
		state = "settled"
		local remaining = group.duration - built:Duration()
		trove:Add(Host.clock:after(if skipped then 0.35 else math.max(0.1, remaining), dismiss))
	end)
	sequence = built

	local function press()
		if options.skippable == false then
			return
		end
		if state == "revealing" then
			built:Skip()
		elseif state == "settled" then
			dismiss()
		end
	end
	trove:Connect(backdrop.Activated, press)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if isSkipInput(input) and UserInputService:GetFocusedTextBox() == nil then
			press()
		end
	end)
	built:Start()
	return {
		skip = press,
		finish = function()
			if state == "revealing" then
				built:Skip()
			end
		end,
		dismiss = function()
			if state == "revealing" then
				built:Skip()
			end
			dismiss()
		end,
		cancel = function()
			finishWith(false)
		end,
		stop = function()
			finishWith(false)
		end,
		isRunning = function(): boolean
			return state ~= "done"
		end,
		Completed = completed,
	}
end

-- Reveals several rewards. Each entry is { rarity = ..., reward = { ... } } or a reward table
-- with a `rarity` field. The rarest comes last; low rarities share a quick grid per rarity and
-- rarities at or above options.threshold (default "Epic") get a full reveal each.
-- handle.skip() skips the current step; handle.cancel() removes everything.
function Rewards.batch(rewards: { any }, options: Options?): Handle
	local opts: Options = options or {}
	local batch = RewardsLogic.planBatch(rewards, planOptions(opts))
	local completed = Signal.new()
	local current: Handle? = nil
	local done = false
	local index = 0

	local function finishWith(dismissed: boolean)
		if done then
			return
		end
		done = true
		local active = current
		current = nil
		if active then
			active.cancel()
		end
		if dismissed and opts.onDismiss then
			task.spawn(opts.onDismiss)
		end
		completed:Fire(dismissed)
	end

	local function advance()
		if done then
			return
		end
		index += 1
		local group = batch.groups[index]
		if group == nil then
			finishWith(true)
			return
		end
		local stepOptions: Options = table.clone(opts)
		stepOptions.onDismiss = nil
		stepOptions.autoDismiss = true
		local started: Handle
		if group.kind == "full" then
			stepOptions.compact = opts.compact
			started = Rewards.reveal(group.rarity, group.items[1].reward, stepOptions)
		else
			started = revealGrid(group, stepOptions)
		end
		current = started
		started.Completed:Once(function(dismissed: boolean)
			if current ~= started then
				return
			end
			current = nil
			if dismissed then
				advance()
			else
				finishWith(false)
			end
		end)
	end

	local handle: Handle = {
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
		dismiss = function()
			if current then
				current.dismiss()
			end
		end,
		cancel = function()
			finishWith(false)
		end,
		stop = function()
			finishWith(false)
		end,
		isRunning = function(): boolean
			return not done
		end,
		Completed = completed,
	}
	advance()
	return handle
end

-- Registers a custom rarity; see RewardsLogic.register. `profile.extends` names a base rarity.
function Rewards.registerRarity(id: string, profile: { [string]: any }): RewardsLogic.Profile
	return RewardsLogic.register(id, profile)
end

-- The profile of a rarity (Common's for an unknown id).
function Rewards.rarity(id: string): RewardsLogic.Profile
	return RewardsLogic.get(id)
end

-- Every rarity id, lowest rank first.
function Rewards.rarities(): { string }
	return RewardsLogic.list()
end

-- The plan a reveal would run, for tools and previews.
function Rewards.plan(rarity: string, reward: Reward?, options: Options?): RewardsLogic.Plan
	return RewardsLogic.plan(rarity, reward or {}, planOptions(options or {}))
end

return Rewards
