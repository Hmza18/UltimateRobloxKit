--!strict
-- UrkBind: writes a Store value into a property, formatted ("abbrev", "time", custom) and
-- optionally through a Template ("Cash: {value}"). With Animate, numbers count up or down on the
-- shared frame driver, which runs only while a count is in progress.
-- UrkProgress: scales a child Fill frame by Value / Max, from attributes or Store paths.

local Driver = require("../Runtime/Driver")
local Easing = require("../Core/Easing")
local Format = require("../Core/Format")
local Localizer = require("../Core/Localizer")
local Motion = require("../Runtime/Motion")
local Path = require("../Core/Path")

local Bind = {}

Bind.tags = { "UrkBind", "UrkProgress" }

local function setProperty(instance: Instance, property: string, value: any): boolean
	local target: any = instance
	local ok = pcall(function()
		target[property] = value
	end)
	return ok
end

local function bindValue(context: any, instance: Instance, trove: any, values: { [string]: any })
	local path = values.Path
	if not Path.isValid(path) then
		warn("[UrkUI] UrkBind on " .. instance:GetFullName() .. " has an invalid Path")
		return
	end
	local property: string = values.Property or "Text"
	local textual = property == "Text" or values.Format ~= nil or values.Template ~= nil
	local shown: number? = nil
	local stopCount: (() -> ())? = nil

	local function render(value: any)
		if not textual then
			if value ~= nil then
				setProperty(instance, property, value)
			end
			return
		end
		local text: string
		if value == nil then
			text = values.Fallback or ""
		else
			text = Format.apply(values.Format, value)
			if values.Template then
				text = Localizer.interpolate(values.Template, { value = text })
			end
		end
		if not setProperty(instance, property, text) then
			warn("[UrkUI] UrkBind cannot write " .. property .. " on " .. instance:GetFullName())
		end
	end

	local function animateTo(target: number)
		if stopCount then
			stopCount()
			stopCount = nil
		end
		local from = shown or target
		local seconds = Motion.duration(Easing.countUpDuration(target - from))
		if seconds <= 0 or from == target then
			shown = target
			render(target)
			return
		end
		local started = os.clock()
		stopCount = Driver.add(function(_dt: number, now: number): boolean?
			local t = Easing.progress(started, seconds, now)
			local current = Easing.countUp(from, target, t)
			shown = current
			render(current)
			if t >= 1 then
				stopCount = nil
				return false
			end
			return true
		end)
	end

	trove:Add(context.store:observe(path, function(value: any)
		if values.Animate and type(value) == "number" then
			animateTo(value)
		else
			shown = if type(value) == "number" then value else nil
			render(value)
		end
	end))
	trove:Add(function()
		if stopCount then
			stopCount()
		end
	end)
end

local function bindProgress(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local bar = instance :: GuiObject
	local fill = bar:FindFirstChild(values.Fill or "Fill")
	if fill == nil or not fill:IsA("GuiObject") then
		local created = Instance.new("Frame")
		created.Name = values.Fill or "Fill"
		created.BorderSizePixel = 0
		created:AddTag("UrkTheme")
		created:SetAttribute("Role", "primary")
		created.Parent = bar
		fill = created
	end
	local fillObject = fill :: GuiObject
	local vertical = values.Vertical == true
	if vertical then
		fillObject.AnchorPoint = Vector2.new(0, 1)
		fillObject.Position = UDim2.fromScale(0, 1)
	end

	local segments = math.floor(values.Segments or 0)
	for index = 1, segments - 1 do
		local divider = Instance.new("Frame")
		divider.Name = "UrkSegment"
		divider.BorderSizePixel = 0
		divider.BackgroundTransparency = 0.4
		divider.BackgroundColor3 = context.theme:color("background")
		divider.ZIndex = fillObject.ZIndex + 1
		local at = index / segments
		divider.Size = if vertical then UDim2.new(1, 0, 0, 2) else UDim2.new(0, 2, 1, 0)
		divider.Position = if vertical then UDim2.fromScale(0, 1 - at) else UDim2.fromScale(at, 0)
		divider.Parent = bar
		trove:Add(divider)
	end

	local current = values.Value or 0
	local maximum = values.Max or 1

	local function update()
		local ratio = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0
		local size = if vertical then UDim2.fromScale(1, ratio) else UDim2.fromScale(ratio, 1)
		if values.Animate == false then
			fillObject.Size = size
		else
			Motion.tween(fillObject, { Size = size }, "normal", Enum.EasingStyle.Quad)
		end
		bar:SetAttribute("UrkRatio", ratio)
	end

	if values.Path and Path.isValid(values.Path) then
		trove:Add(context.store:observe(values.Path, function(value: any)
			current = if type(value) == "number" then value else 0
			update()
		end))
	end
	if values.MaxPath and Path.isValid(values.MaxPath) then
		trove:Add(context.store:observe(values.MaxPath, function(value: any)
			maximum = if type(value) == "number" then value else 1
			update()
		end))
	end
	update()
end

function Bind.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkProgress" then
		bindProgress(context, instance, trove, values)
	else
		bindValue(context, instance, trove, values)
	end
end

return Bind
