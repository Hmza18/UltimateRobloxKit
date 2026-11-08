--!strict
-- Client side of VFXLogic: builds ParticleEmitters from resolved presets, plays one-shot bursts at a
-- position or part, attaches looping auras, and keeps the number of live emitters under the quality
-- budget. Quality is chosen once from the device and can be changed by a settings menu.
--
--   local vfx = VFXClient.new()            -- picks quality from the device
--   vfx:play("hatch", eggModel.PrimaryPart.Position)
--   local stop = vfx:attach("rareAura", petModel.PrimaryPart)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local VFXLogic = require("./VFXLogic")

local VFXClient = {}

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

local function colorSequence(stops: { string }): ColorSequence
	if #stops == 1 then
		return ColorSequence.new(color(stops[1]))
	end
	local keys = {}
	for i, hex in stops do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#stops - 1), color(hex)))
	end
	return ColorSequence.new(keys)
end

local function numberSequence(stops: { number }): NumberSequence
	if #stops == 1 then
		return NumberSequence.new(stops[1])
	end
	local keys = {}
	for i, v in stops do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#stops - 1), v))
	end
	return NumberSequence.new(keys)
end

local function emitter(layer: VFXLogic.Layer): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = layer.name
	if layer.texture then
		e.Texture = layer.texture
	end
	e.Color = colorSequence(layer.colors)
	e.Size = numberSequence(layer.sizes)
	e.Transparency = numberSequence(layer.transparency or { 0, 1 })
	e.Lifetime = NumberRange.new(layer.lifetime[1], layer.lifetime[2])
	e.Speed = NumberRange.new(layer.speed[1], layer.speed[2])
	local spread = layer.spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = Vector3.new(0, layer.gravity or 0, 0)
	e.LightEmission = layer.lightEmission or 0
	if layer.rotSpeed then
		e.RotSpeed = NumberRange.new(layer.rotSpeed[1], layer.rotSpeed[2])
	end
	e.Rate = layer.rate or 0
	e.Enabled = layer.rate ~= nil
	return e
end

function VFXClient.new(options: { quality: VFXLogic.Quality? }?)
	local self = {}
	local live = 0
	local quality: VFXLogic.Quality = (options and options.quality)
		or VFXLogic.chooseQuality({
			touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
			gamepad = UserInputService.GamepadEnabled,
			fps = nil,
		})

	-- Measure frame rate for a few seconds and step down if the device struggles.
	task.spawn(function()
		local frames, started = 0, os.clock()
		local connection = RunService.RenderStepped:Connect(function()
			frames += 1
		end)
		task.wait(5)
		connection:Disconnect()
		local fps = frames / (os.clock() - started)
		if options == nil or options.quality == nil then
			quality = VFXLogic.chooseQuality({ touch = UserInputService.TouchEnabled, fps = fps })
		end
	end)

	function self.quality(): VFXLogic.Quality
		return quality
	end

	function self.setQuality(value: VFXLogic.Quality)
		quality = value
	end

	-- One-shot effect at a position (or on a part). Returns false when over budget.
	function self.play(_: any, name: string, at: Vector3 | BasePart): boolean
		local preset = VFXLogic.resolve(name, quality)
		if live + #preset.layers > VFXLogic.BUDGET[quality] then
			return false
		end
		local holder: BasePart
		if typeof(at) == "Vector3" then
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.Transparency = 1
			part.Size = Vector3.one
			part.Position = at
			part.Parent = Workspace
			holder = part
		else
			holder = at :: BasePart
		end
		local made = {}
		for _, layer in preset.layers do
			local e = emitter(layer)
			e.Parent = holder
			e:Emit(layer.burst or 0)
			table.insert(made, e)
		end
		live += #made
		task.delay((preset.duration or 1) + 2, function()
			live -= #made
			for _, e in made do
				e:Destroy()
			end
			if typeof(at) == "Vector3" then
				holder:Destroy()
			end
		end)
		return true
	end

	-- Looping effect on a part. Returns a function that stops it.
	function self.attach(_: any, name: string, part: BasePart): () -> ()
		local preset = VFXLogic.resolve(name, quality)
		local made = {}
		if live + #preset.layers <= VFXLogic.BUDGET[quality] then
			for _, layer in preset.layers do
				local e = emitter(layer)
				e.Parent = part
				table.insert(made, e)
			end
			live += #made
		end
		local stopped = false
		return function()
			if stopped then
				return
			end
			stopped = true
			live -= #made
			for _, e in made do
				e:Destroy()
			end
		end
	end

	return self
end

return VFXClient
