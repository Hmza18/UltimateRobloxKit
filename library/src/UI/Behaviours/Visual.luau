--!strict
-- UrkIcon (icons from the Icons catalogue), UrkTheme (role-based skinning that follows theme
-- switches) and UrkAnimate (decorative Spin / Bob / Pulse / Shine / Rainbow on the shared frame
-- driver, paused while hidden and disabled by reduced motion).

local Decor = require("../Core/Decor")
local Driver = require("../Runtime/Driver")
local IconBridge = require("../Runtime/IconBridge")
local Motion = require("../Runtime/Motion")

local Visual = {}

Visual.tags = { "UrkIcon", "UrkTheme", "UrkAnimate" }

local function bindIcon(context: any, instance: Instance, _trove: any, values: { [string]: any })
	if not (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
		warn("[UrkUI] UrkIcon must be on an ImageLabel or ImageButton: " .. instance:GetFullName())
		return
	end
	local options = { color = values.IconColor, size = values.IconSize }
	local applied = IconBridge.apply(instance :: ImageLabel, values.Icon, options)
	if not applied and context.config.debug then
		warn("[UrkUI] unknown icon " .. tostring(values.Icon) .. " on " .. instance:GetFullName())
	end
end

local function bindTheme(context: any, instance: Instance, trove: any, values: { [string]: any })
	local skin = {
		Role = values.Role,
		TextRole = values.TextRole,
		StrokeRole = values.StrokeRole,
		ImageRole = values.ImageRole,
		PlaceholderRole = values.PlaceholderRole,
		TransparencyRole = values.TransparencyRole,
		TextSize = values.TextSize,
		Radius = values.Radius,
	}
	trove:Add(context.theme:watch(function(theme: any)
		theme:apply(instance, skin)
	end))
end

-- True when the object and every GuiObject ancestor are visible and its ScreenGui is enabled.
local function isRendered(object: GuiObject): boolean
	local current: Instance? = object
	while current ~= nil do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

local function bindAnimate(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local object = instance :: GuiObject
	local effect = values.Effect
	if not Decor.isEffect(effect) then
		warn("[UrkUI] UrkAnimate Effect must be one of Spin, Bob, Pulse, Shine, Rainbow on " .. object:GetFullName())
		return
	end
	local params = { speed = values.Speed, amplitude = values.Amplitude, phase = values.Phase, pause = values.Pause }
	local baseRotation = object.Rotation
	local basePosition = object.Position
	local scale: UIScale? = if effect == "Pulse" then Motion.scaleOf(object) else nil
	local gradient: UIGradient? = nil
	if effect == "Shine" then
		local existing = object:FindFirstChildOfClass("UIGradient")
		if existing then
			gradient = existing
		else
			local created = Instance.new("UIGradient")
			created.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.45, 0),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(0.55, 0),
				NumberSequenceKeypoint.new(1, 0),
			})
			created.Rotation = 20
			created.Parent = object
			trove:Add(created)
			gradient = created
		end
	end
	local colorProperty = "BackgroundColor3"
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		colorProperty = "ImageColor3"
	elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		colorProperty = "TextColor3"
	end
	local target: any = object
	local baseColor = target[colorProperty]
	local stopJob: (() -> ())? = nil

	local function restore()
		object.Rotation = baseRotation
		object.Position = basePosition
		if scale then
			scale.Scale = 1
		end
		if gradient then
			gradient.Offset = Vector2.new(-1, 0)
		end
		if effect == "Rainbow" then
			target[colorProperty] = baseColor
		end
	end

	local function step(_dt: number, now: number): boolean?
		if not isRendered(object) then
			return true
		end
		if effect == "Spin" then
			object.Rotation = baseRotation + Decor.spin(now, params)
		elseif effect == "Bob" then
			object.Position = basePosition + UDim2.fromOffset(0, Decor.bob(now, params))
		elseif effect == "Pulse" and scale then
			scale.Scale = Decor.pulse(now, params)
		elseif effect == "Shine" and gradient then
			gradient.Offset = Vector2.new(Decor.shine(now, params), 0)
		elseif effect == "Rainbow" then
			local rgb = Decor.rainbow(now, params)
			target[colorProperty] = Color3.new(rgb.r, rgb.g, rgb.b)
		end
		return true
	end

	local function update()
		local wanted = not Motion.isReduced()
		if wanted and stopJob == nil then
			stopJob = Driver.add(step)
		elseif not wanted and stopJob then
			stopJob()
			stopJob = nil
			restore()
		end
	end

	trove:Connect(context.ReducedMotionChanged, update)
	trove:Add(function()
		if stopJob then
			stopJob()
			stopJob = nil
		end
		restore()
	end)
	update()
end

function Visual.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkIcon" then
		bindIcon(context, instance, trove, values)
	elseif tag == "UrkTheme" then
		bindTheme(context, instance, trove, values)
	else
		bindAnimate(context, instance, trove, values)
	end
end

return Visual
