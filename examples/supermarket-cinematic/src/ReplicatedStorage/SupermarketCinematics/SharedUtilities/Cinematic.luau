-- Plays the supermarket intro for the local player and guarantees a clean return to gameplay.
--
--   local cinematic = Cinematic.new()
--   cinematic:play()            -- false if already playing
--   cinematic:pause(true/false) -- freezes clock, tweens, clips, particles and sounds
--   cinematic:skip()            -- fades out and restores at once
--   cinematic.Finished.Event    -- fires (skipped: boolean) after everything is restored
--
-- Everything created during playback is registered with one Janitor; restore (camera, lighting,
-- other GUIs, CoreGui, controls) is registered the moment it is changed, so any exit path - normal
-- end, skip, an error, the script being destroyed - undoes exactly what was done.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = script.Parent.Parent
local Configuration = require(Root.Configuration)
local TimelineDefinitions = require(Root.TimelineDefinitions)
local EffectDefinitions = require(Root.EffectDefinitions)
local AnimationDefinitions = require(Root.AnimationDefinitions)
local U = script.Parent
local Janitor = require(U.Janitor)
local Timeline = require(U.Timeline)
local Tweener = require(U.Tweener)
local Actor = require(U.Actor)
local Rig = require(U.Rig)
local StoreSet = require(U.StoreSet)
local Products = require(U.Products)
local Vfx = require(U.Vfx)
local Audio = require(U.Audio)
local CinematicUi = require(U.CinematicUi)
local CameraDirector = require(U.CameraDirector)

local Cinematic = {}
Cinematic.__index = Cinematic

local LOG = "[SupermarketCinematic] "

local function qualityLevel()
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if ok and level and level > 0 then
		return level
	end
	return 10 -- "Automatic"
end

function Cinematic.new(overrides)
	local self = setmetatable({}, Cinematic)
	self.config = overrides and overrides.config or Configuration
	self.timeline = overrides and overrides.timeline or TimelineDefinitions
	self.state = "idle"
	self.time = 0
	self.paused = false
	self.Finished = Instance.new("BindableEvent")
	self.SceneChanged = Instance.new("BindableEvent")
	self.lastStats = nil
	return self
end

function Cinematic:isPlaying()
	return self.state ~= "idle"
end

-- ---------------------------------------------------------------------------------------------------
-- ctx: the helpers timeline cues use. Built per playback.

local function buildCtx(self, set, actors, j, tweener, vfx, ui, audio, propsFolder)
	local config = self.config
	local ctx = {
		config = config,
		set = set,
		actors = actors,
		vfx = vfx,
		ui = ui,
		audio = audio,
		tweener = tweener,
		contacts = AnimationDefinitions.Contacts,
		props = {},
		state = {},
		reducedMotion = self.reducedMotion,
		lowQuality = self.lowQuality,
		total = 0,
	}
	ctx.props.ProductBox = set.parts.productBox

	function ctx:mark(name)
		return set.marks[name]
	end
	function ctx:point(x, z)
		return set.origin * Vector3.new(x, 0, z)
	end
	function ctx:dir(x, z)
		return set.origin:VectorToWorldSpace(Vector3.new(x, 0, z))
	end
	function ctx:after(delay, fn)
		self._timers = self._timers or {}
		table.insert(self._timers, { t = delay, fn = fn })
	end

	-- products ------------------------------------------------------------------------------------
	function ctx:product(key, id)
		local prop, primary, height, kind = Products.make(key, config, true)
		prop.Parent = propsFolder
		ctx.props[id or key] = prop
		self.stats.products = self.stats.products + 1
		if kind == "real" then
			self.stats.realProducts = self.stats.realProducts + 1
		end
		return prop, primary, height
	end
	function ctx:moveTo(primary, toCF, duration, ease, done)
		local from = primary.CFrame
		return tweener:play({ from = from, to = toCF, duration = duration, ease = ease or "outCubic", set = function(cf)
			primary.CFrame = cf
		end, done = done })
	end
	-- arcs a prop to `toCF` (lift `height` studs at the midpoint)
	function ctx:arc(primary, toCF, duration, height, done)
		local from = primary.CFrame
		return tweener:play({ from = 0, to = 1, duration = duration, ease = "inOutSine", set = function(u)
			local cf = from:Lerp(toCF, u)
			primary.CFrame = cf + Vector3.new(0, 4 * height * u * (1 - u), 0)
		end, done = done })
	end
	-- upright placement at the fingertips of a hand, facing the way the actor faces
	function ctx:tip(actor, handName)
		local hand = actor:part(handName)
		local look = actor:pivot().LookVector
		local pos = (hand.CFrame * CFrame.new(0, -0.42, 0)).Position
		return CFrame.lookAt(pos, pos - Vector3.new(look.X, 0, look.Z))
	end
	function ctx:grab(actor, prop, primary, handName, duration)
		ctx:unweld(prop)
		primary.Anchored = true
		local target = ctx:tip(actor, handName)
		-- weld where it is, then slide the weld offset to the fingertips: the prop follows the hand the
		-- whole time (moving a welded part's CFrame would drag the anchored rig with it)
		actor:hold(prop, handName, nil, true)
		local weld = actor.held[prop]
		if weld then
			local hand = actor:part(handName)
			local final = hand.CFrame:ToObjectSpace(target)
			local start = weld.C0
			tweener:play({ from = start, to = final, duration = duration or 0.1, ease = "outQuad", set = function(c0)
				if weld.Parent then
					weld.C0 = c0
				end
			end })
		end
		ctx.audio:play("BoxHandle")
	end
	function ctx:place(actor, prop, primary, slotCF, duration)
		actor:release(prop)
		ctx:moveTo(primary, slotCF, duration or 0.22, "outBackSoft", function()
			vfx:flash(prop)
			vfx:sparkleAt(slotCF.Position + Vector3.new(0, 0.2, 0), 8)
			ctx.audio:play("ProductPlace", { at = slotCF.Position })
		end)
	end
	function ctx:slotFor(stockerCF, wristLocal, height)
		return StoreSet.slotFor(set, stockerCF, wristLocal, height)
	end
	-- root CFrame for an actor facing `facing` whose wrist target `wristLocal` lands on `targetCF`
	function ctx:standFor(targetCF, wristLocal, facing)
		local grabPoint = targetCF.Position + Vector3.new(0, 0, 0) - facing.Unit * 0.25
		local rot = CFrame.lookAt(Vector3.zero, Vector3.new(facing.X, 0, facing.Z))
		local root = grabPoint - rot:VectorToWorldSpace(Vector3.new(wristLocal.X, 0, wristLocal.Z))
		root = Vector3.new(root.X, set.origin.Position.Y + Rig.HIP_HEIGHT, root.Z)
		return CFrame.lookAt(root, root + Vector3.new(facing.X, 0, facing.Z))
	end
	function ctx:unweld(prop)
		local primary = prop:IsA("Model") and prop.PrimaryPart or prop
		for _, d in ipairs(primary:GetChildren()) do
			if d:IsA("WeldConstraint") and d.Name == "CinematicAttach" then
				d:Destroy()
			end
		end
	end
	function ctx:weldTo(prop, primary, target)
		local w = Instance.new("WeldConstraint")
		w.Name = "CinematicAttach"
		w.Part0 = target
		w.Part1 = primary
		w.Parent = primary
		primary.Anchored = false
	end
	function ctx:intoBasket(actor, prop, primary, offset)
		local basket = actor.basket
		if not basket then
			return
		end
		actor:release(prop)
		local dest = basket.CFrame * CFrame.new(offset) * CFrame.Angles(0, math.rad(8), 0)
		ctx:moveTo(primary, dest, 0.18, "outQuad", function()
			ctx:weldTo(prop, primary, basket)
			vfx:sparkleAt(dest.Position + Vector3.new(0, 0.3, 0), 5)
		end)
	end
	-- moves an item from the actor's basket onto the counter's waiting spot; returns the item
	function ctx:toCounter(actor, which, duration)
		local item = which == "picked" and self.state.picked or actor.basketItem
		if not item then
			return nil
		end
		ctx:unweld(item.prop)
		item.primary.Anchored = true
		local cashier = ctx:mark("Cashier")
		local wait = AnimationDefinitions.Contacts.ScanWait
		local dest = cashier * CFrame.new(wait.X, AnimationDefinitions.Contacts.CounterTop + item.height / 2, wait.Z) * CFrame.Angles(0, math.rad(180), 0)
		ctx:arc(item.primary, dest, duration or 0.45, 1.2, function()
			vfx:sparkleAt(dest.Position, 5)
			ctx.audio:play("ProductPlace", { at = dest.Position })
		end)
		return item
	end
	function ctx:intoBag(actor, prop, primary)
		actor:release(prop)
		local bag = set.bagSpot
		ctx:moveTo(primary, bag * CFrame.new(0, 0.6, 0), 0.12, "outQuad", function()
			ctx:moveTo(primary, bag * CFrame.new(0, -0.35, 0), 0.18, "inQuad")
		end)
	end
	function ctx:addToTotal(text)
		local n = tonumber((text:gsub("[^%d%.]", ""))) or 0
		local from = ctx.total
		ctx.total = ctx.total + n
		local label = set.parts.registerTotal
		tweener:play({ from = from, to = ctx.total, duration = 0.5, ease = "outCubic", set = function(v)
			label.Text = ("$%d"):format(math.floor(v + 0.5))
		end })
	end
	function ctx:openDoors(duration)
		local d = set.parts
		ctx:moveTo(d.doorL, set.doorOpen.L, duration, "inOutCubic")
		ctx:moveTo(d.doorR, set.doorOpen.R, duration, "inOutCubic")
	end
	-- the rest of shelf A fills itself: products drop into the empty slots one after another
	function ctx:cascadeShelf(stagger)
		local sa = StoreSet.SHELF_A
		local taken = {}
		for _, s in pairs(self.state.handSlots or {}) do
			taken[#taken + 1] = set.origin:PointToObjectSpace(s.cf.Position)
		end
		local order = { "SalsSlicedBread", "Pasta", "BasmatyRice", "OrangeJuice", "Milk", "CookingOil", "TamsCereal", "BlueFlour" }
		local topKeys = { "SUSUsSugar", "InstantNoodles" }
		local slots = {}
		local step = self.lowQuality and 1.6 or 1.2
		for _, row in ipairs({ { y = sa.boards[2], keys = order }, { y = sa.boards[3], keys = topKeys, sparse = true } }) do
			local x = sa.x0 + 0.75
			local k = 0
			while x < sa.x1 - 0.5 do
				local free = true
				for _, t in ipairs(taken) do
					if math.abs(t.X - x) < 0.95 and math.abs(t.Y - row.y) < 1.2 then
						free = false
					end
				end
				-- the top row starts half full (pre-stocked), only its gaps are filled
				if row.sparse and math.floor((x - sa.x0) / step + 0.5) % 2 == 0 then
					free = false
				end
				if free then
					k = k + 1
					slots[#slots + 1] = { x = x, y = row.y, key = row.keys[(k - 1) % #row.keys + 1] }
				end
				x = x + step
			end
		end
		-- closest to the camera first so the cascade sweeps across the frame
		table.sort(slots, function(a, b)
			return a.x > b.x
		end)
		for i, s in ipairs(slots) do
			local prop, primary, height = ctx:product(s.key, "Cascade" .. i)
			primary.CFrame = set.origin * CFrame.new(s.x, -50, sa.front + 0.55) -- hidden until it drops
			local slotCF = set.origin * CFrame.new(s.x, s.y + height / 2, sa.front + 0.55)
			vfx:dropIn(primary, slotCF, (i - 1) * stagger, i % 3 == 1 and function()
				ctx.audio:play("ProductPlace", { at = slotCF.Position, volume = 0.35 })
			end or nil)
		end
	end
	return ctx
end

-- Pre-stocks the half-full top row of shelf A (hand-placed + cascade fill the rest).
local function prestock(set, propsFolder, config, lowQuality)
	local sa = StoreSet.SHELF_A
	local step = lowQuality and 1.6 or 1.2
	local x, k = sa.x0 + 0.75, 0
	local keys = { "SUSUsSugar", "InstantNoodles" }
	while x < sa.x1 - 0.5 do
		if math.floor((x - sa.x0) / step + 0.5) % 2 == 0 then
			k = k + 1
			local p = Products.filler(keys[(k - 1) % 2 + 1], config.ProductScale)
			p.CFrame = set.origin * CFrame.new(x, sa.boards[3] + p.Size.Y / 2, sa.front + 0.55)
			p.Parent = propsFolder
		end
		x = x + step
	end
	-- bottom row: full, bulk items
	x, k = sa.x0 + 0.6, 0
	local bulk = { "BasmatyRice", "BlueFlour", "SalsSlicedBread", "Pasta" }
	while x < sa.x1 - 0.4 do
		k = k + 1
		local p = Products.filler(bulk[(k - 1) % #bulk + 1], config.ProductScale)
		p.CFrame = set.origin * CFrame.new(x, sa.boards[1] + p.Size.Y / 2, sa.front + 0.55)
		p.Parent = propsFolder
		x = x + 0.95
	end
end

-- A shopping basket that hangs from the left hand; returns the basket's primary part.
local function giveBasket(actor, propsFolder)
	local model = Instance.new("Model")
	model.Name = actor.name .. "Basket"
	local color = Color3.fromRGB(60, 150, 240)
	local function piece(name, size, offset, primary)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = primary or false
		p.CFrame = offset
		p.Parent = model
		return p
	end
	local hand = actor:part("LeftHand")
	local look = actor:pivot().LookVector
	local top = (hand.CFrame * CFrame.new(0, -0.25, 0)).Position
	local base = CFrame.lookAt(top, top + Vector3.new(look.X, 0, look.Z)) * CFrame.new(0, -1.05, 0)
	local bottom = piece("Bottom", Vector3.new(1.0, 0.1, 1.4), base, true)
	model.PrimaryPart = bottom
	local walls = {
		{ Vector3.new(1.0, 0.65, 0.08), CFrame.new(0, 0.33, 0.66) },
		{ Vector3.new(1.0, 0.65, 0.08), CFrame.new(0, 0.33, -0.66) },
		{ Vector3.new(0.08, 0.65, 1.4), CFrame.new(0.46, 0.33, 0) },
		{ Vector3.new(0.08, 0.65, 1.4), CFrame.new(-0.46, 0.33, 0) },
		{ Vector3.new(0.08, 0.5, 0.08), CFrame.new(0, 0.85, 0.6) },
		{ Vector3.new(0.08, 0.5, 0.08), CFrame.new(0, 0.85, -0.6) },
		{ Vector3.new(0.1, 0.08, 1.28), CFrame.new(0, 1.08, 0) },
	}
	for i, w in ipairs(walls) do
		local p = piece("Wall" .. i, w[1], base * w[2], false)
		local wc = Instance.new("WeldConstraint")
		wc.Part0, wc.Part1 = bottom, p
		wc.Parent = p
	end
	model.Parent = propsFolder
	actor:hold(model, "LeftHand", nil, true)
	actor.basket = bottom
	return bottom
end

-- ---------------------------------------------------------------------------------------------------

function Cinematic:play()
	if self.state ~= "idle" then
		return false
	end
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	self.state = "playing"
	self.time = 0
	self.paused = false
	self.finishing = false
	local ok, err = pcall(self._start, self, player)
	if not ok then
		warn(LOG .. "could not start: " .. tostring(err))
		self:_cleanup(true)
		return false
	end
	return true
end

function Cinematic:_start(player)
	local config = self.config
	local j = Janitor.new()
	self.janitor = j
	local level = qualityLevel()
	self.lowQuality = level <= config.LowQualityLevel
	self.reducedMotion = false
	pcall(function()
		self.reducedMotion = GuiService.ReducedMotionEnabled
	end)
	local stats = { products = 0, realProducts = 0, cast = {}, errors = 0 }
	self.stats = stats
	player:SetAttribute("SupermarketCinematicPlaying", true)
	j:Add(function()
		player:SetAttribute("SupermarketCinematicPlaying", nil)
	end)

	-- world ---------------------------------------------------------------------------------------
	local folder = Instance.new("Folder")
	folder.Name = "SupermarketCinematicAssets"
	j:Add(folder)
	local chars = Instance.new("Folder")
	chars.Name = "Characters"
	chars.Parent = folder
	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	effectsFolder.Parent = folder
	local set = StoreSet.build(folder, config.SetOrigin, { lowQuality = self.lowQuality, storeName = config.StoreName })
	local propsFolder = set.propsFolder
	prestock(set, propsFolder, config, self.lowQuality)
	folder.Parent = workspace

	local tweener = Tweener.new()
	self.tweener = tweener
	local templates = ReplicatedStorage:FindFirstChild("SupermarketCinematics")
	templates = templates and templates:FindFirstChild("CastTemplates")

	-- cast ------------------------------------------------------------------------------------------
	local actors = {}
	local audio = Audio.new(config)
	j:Add(function()
		audio:destroy()
	end)
	local events = {
		onMarker = function(actor, marker)
			if marker == "Step" then
				audio:footstep(actor.root.Position - Vector3.new(0, 2.8, 0))
			end
		end,
	}
	for _, c in ipairs(self.timeline.Cast) do
		if not (c.optional and self.lowQuality) then
			local model, kind = Rig.make(c.look, templates)
			model.Name = c.name
			model:PivotTo(set.marks[c.mark])
			model.Parent = chars
			local actor = Actor.new(c.name, model, AnimationDefinitions, config, events)
			actor:place(set.marks[c.mark])
			actor:play(c.clip, { fade = 0 })
			actor:update(0)
			actors[c.name] = actor
			stats.cast[c.name] = kind
		end
	end
	self.actors = actors

	-- baskets (and the item already in the first customer's basket)
	for _, name in ipairs({ "Customer", "ShopperA", "ShopperB" }) do
		local a = actors[name]
		if a then
			giveBasket(a, propsFolder)
		end
	end

	local vfx = Vfx.new(effectsFolder, tweener, EffectDefinitions, { budget = config.ParticleBudget * (self.lowQuality and 0.5 or 1), reducedMotion = self.reducedMotion })
	j:Add(function()
		vfx:destroy()
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local ui = CinematicUi.new(playerGui, tweener, config)
	j:Add(function()
		ui:destroy()
	end)
	self.ui = ui
	local ctx = buildCtx(self, set, actors, j, tweener, vfx, ui, audio, propsFolder)
	ctx.stats = stats
	self.ctx = ctx
	if actors.Customer then
		local prop, primary, height = ctx:product("Milk", "BasketMilk")
		primary.CFrame = actors.Customer.basket.CFrame * CFrame.new(-0.2, 0.05 + height / 2, 0.2)
		ctx:weldTo(prop, primary, actors.Customer.basket)
		actors.Customer.basketItem = { prop = prop, primary = primary, height = height }
	end

	-- take over presentation (each change registers its own restore) -------------------------------
	local camera = workspace.CurrentCamera
	local saved = { type = camera.CameraType, subject = camera.CameraSubject, fov = camera.FieldOfView, cf = camera.CFrame }
	camera.CameraType = Enum.CameraType.Scriptable
	j:Add(function()
		local cam = workspace.CurrentCamera
		cam.FieldOfView = saved.fov
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		cam.CameraSubject = humanoid or saved.subject
		cam.CameraType = (saved.type == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or saved.type
	end)
	vfx:applyGrade()

	if config.HideOtherGuis then
		local hidden = {}
		for _, g in ipairs(playerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g ~= ui.gui and not g.Name:find("SupermarketCinematic") then
				g.Enabled = false
				hidden[#hidden + 1] = g
			end
		end
		j:Add(function()
			for _, g in ipairs(hidden) do
				if g.Parent then
					g.Enabled = true
				end
			end
		end)
		local core = {}
		for _, t in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			if t ~= Enum.CoreGuiType.All then
				local okGet, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
				if okGet then
					core[t] = enabled
				end
			end
		end
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
		j:Add(function()
			for t, enabled in pairs(core) do
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, enabled)
			end
		end)
	end
	local controls = nil
	pcall(function()
		local module = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
		if module then
			controls = require(module):GetControls()
			controls:Disable()
		end
	end)
	j:Add(function()
		if controls then
			pcall(function()
				controls:Enable()
			end)
		end
	end)

	-- skip input ---------------------------------------------------------------------------------
	if config.AllowSkip then
		if ui.skip then
			j:Add(ui.skip.Activated:Connect(function()
				self:skip()
			end))
		end
		ContextActionService:BindAction("SupermarketCinematicSkip", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self:skip()
			end
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(config.SkipKeys))
		j:Add(function()
			ContextActionService:UnbindAction("SupermarketCinematicSkip")
		end)
	end

	-- timeline + camera --------------------------------------------------------------------------
	self.director = CameraDirector.new(self.timeline.Shots, ctx)
	self.cueList = Timeline.new(self.timeline.cues(ctx), function(name, e)
		stats.errors = stats.errors + 1
		warn(LOG .. "cue '" .. name .. "' failed: " .. tostring(e))
	end)
	self.duration = self.timeline.Duration
	self.sceneIndex = 0

	j:Add(RunService.PreSimulation:Connect(function(dt)
		local okStep, e = pcall(self._step, self, dt)
		if not okStep then
			stats.errors = stats.errors + 1
			warn(LOG .. "playback error, returning to gameplay: " .. tostring(e))
			self:skip()
		end
	end))
	RunService:BindToRenderStep("SupermarketCinematicCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cf, fov = self.director:evaluate(self.time, dt)
		if cf then
			camera.CFrame = cf
			camera.FieldOfView = fov
		end
	end)
	j:Add(function()
		RunService:UnbindFromRenderStep("SupermarketCinematicCamera")
	end)
	self.cueList:update(0)
end

function Cinematic:_step(dt)
	if self.state ~= "playing" then
		if self.state == "ending" and self.tweener then
			self.tweener:update(dt)
		end
		return
	end
	if self.paused then
		return
	end
	dt = math.min(dt, self.config.MaxStep)
	self.time = self.time + dt
	local ctx = self.ctx
	if ctx._timers then
		local keep = {}
		for _, timer in ipairs(ctx._timers) do
			timer.t = timer.t - dt
			if timer.t <= 0 then
				local okTimer, e = pcall(timer.fn)
				if not okTimer then
					warn(LOG .. "timer failed: " .. tostring(e))
				end
			else
				keep[#keep + 1] = timer
			end
		end
		ctx._timers = keep
	end
	self.cueList:update(self.time)
	self.tweener:update(dt)
	for _, actor in pairs(self.actors) do
		actor:update(dt)
	end
	local scenes = self.timeline.Scenes
	for i, s in ipairs(scenes) do
		if self.time >= s.t0 and self.time < s.t1 and i ~= self.sceneIndex then
			self.sceneIndex = i
			self.SceneChanged:Fire(i, s.name)
		end
	end
	if self.time >= self.duration and self.cueList:done() then
		self:_finish(false)
	end
end

function Cinematic:pause(on)
	if self.state ~= "playing" then
		return
	end
	self.paused = on and true or false
	if self.ctx then
		self.ctx.vfx:setPaused(self.paused)
		self.ctx.audio:setPaused(self.paused)
	end
end

function Cinematic:skip()
	if self.state ~= "playing" then
		return
	end
	self:_finish(true)
end

-- Ends playback: brief fade to white, then restore everything and fade back into gameplay.
function Cinematic:_finish(skipped)
	if self.finishing then
		return
	end
	self.finishing = true
	self.state = "ending"
	self.paused = false
	local ui = self.ui
	local fadeTime = skipped and 0.25 or 0.05
	if ui then
		ui:fadeTo(0, fadeTime, Color3.new(1, 1, 1), function()
			self:_cleanup(skipped)
		end)
	else
		self:_cleanup(skipped)
	end
	-- guard: restore even if the fade tween never completes
	task.delay(fadeTime + 1, function()
		if self.state == "ending" then
			self:_cleanup(skipped)
		end
	end)
end

function Cinematic:_cleanup(skipped)
	if self.state == "idle" and not self.janitor then
		return
	end
	local player = Players.LocalPlayer
	-- an independent white frame that fades out over the restored game view
	local playerGui = player and player:FindFirstChild("PlayerGui")
	if playerGui and self.ui then
		local outro = Instance.new("ScreenGui")
		outro.Name = "SupermarketCinematicOutro"
		outro.IgnoreGuiInset = true
		outro.DisplayOrder = 1002
		outro.ResetOnSpawn = false
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.Parent = outro
		outro.Parent = playerGui
		local tween = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			outro:Destroy()
		end)
		tween:Play()
	end
	local stats = self.stats
	if self.ctx and self.ctx.audio then
		stats = stats or {}
		stats.missingAudio = self.ctx.audio:missingCues()
	end
	if self.actors then
		for _, actor in pairs(self.actors) do
			pcall(function()
				actor.player:destroy()
			end)
		end
	end
	if self.tweener then
		self.tweener:cancelAll()
	end
	if self.janitor then
		self.janitor:Cleanup()
		self.janitor = nil
	end
	self.actors, self.ctx, self.ui, self.director, self.cueList, self.tweener = nil, nil, nil, nil, nil, nil
	self.lastStats = stats
	self.state = "idle"
	self.Finished:Fire(skipped and true or false, stats)
end

function Cinematic:destroy()
	if self.state ~= "idle" then
		self:_cleanup(true)
	end
	self.Finished:Destroy()
	self.SceneChanged:Destroy()
end

return Cinematic
