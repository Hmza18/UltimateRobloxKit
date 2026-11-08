--!strict
-- Chunky slider: dark outlined track, gradient fill, white outlined knob. Drag with mouse or touch;
-- with a gamepad, select it and press D-pad left / right (bound only while it is selected).
--   local volume = Slider.new({ value = 0.5, min = 0, max = 1, step = 0.05, onChanged = setVolume })
--   volume.Changed:Connect(fn) ; volume:set(0.8)

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Base = require("./Base")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Props = {
	value: number?,
	min: number?, -- default 0
	max: number?, -- default 1
	step: number?, -- default (max - min) / 100
	onChanged: ((number) -> ())?,
	palette: string?, -- fill palette, default "blue"
	enabled: boolean?,
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

local Slider = {}

local KNOB = 30
local nextId = 0

-- Clamps to min..max and snaps to the step grid measured from min.
function Slider.snap(value: number, min: number, max: number, step: number?): number
	local low = math.min(min, max)
	local high = math.max(min, max)
	local clamped = math.clamp(value, low, high)
	if step and step > 0 then
		clamped = low + math.floor((clamped - low) / step + 0.5) * step
		clamped = math.clamp(clamped, low, high)
	end
	return clamped
end

local function bounds(props: { [string]: any }): (number, number, number)
	local min = props.min or 0
	local max = props.max or 1
	local step = props.step or (max - min) / 100
	return min, max, step
end

local function ratioOf(props: { [string]: any }): number
	local min, max = bounds(props)
	if max == min then
		return 0
	end
	return math.clamp(((props.value or min) - min) / (max - min), 0, 1)
end

local function render(object: any)
	local ratio = ratioOf(object.props)
	if object.fill then
		object.fill.Size = UDim2.fromScale(ratio, 1)
		object.fill.Visible = ratio > 0
	end
	if object.knob then
		object.knob.Position = UDim2.fromScale(ratio, 0.5)
	end
end

local function set(object: any, value: number, silent: boolean?)
	local min, max, step = bounds(object.props)
	local snapped = Slider.snap(value, min, max, step)
	if snapped == object.props.value then
		return
	end
	object.props.value = snapped
	render(object)
	if not silent then
		object.Changed:Fire(snapped)
		if object.props.onChanged then
			task.spawn(object.props.onChanged, snapped)
		end
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	root.Active = props.enabled ~= false
	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.BackgroundTransparency = 1
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = UDim2.fromScale(0.5, 0.5)
	rail.Size = UDim2.new(1, -KNOB, 0.45, 0)
	rail.Parent = root
	object.parts:Add(rail)
	object.rail = rail
	local trackProps: Panel.SurfaceProps = {
		surface = "dark",
		radius = "pill",
		outline = "regular",
		gloss = false,
		shadow = false,
	}
	local track = Panel.surface(object, rail, trackProps).content

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.ZIndex = 2
	Kit.corner(Kit.radius(style, "pill")).Parent = fill
	local swatch = if props.enabled == false then Style.palette(style, "gray") else Style.palette(style, props.palette)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
	gradient.Parent = fill
	fill.Parent = track
	object.fill = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.ZIndex = 5
	Kit.corner(KNOB).Parent = knob
	Kit.stroke(style, "thick").Parent = knob
	knob.Parent = rail
	object.knob = knob
	render(object)
end

local function setup(object: any)
	local root: TextButton = object.Instance
	local style = object.style
	object.Changed = Signal.new()
	root.Selectable = true
	local selection = Kit.selectionImage(style, Kit.radius(style, "pill"))
	object.trove:Add(selection)
	root.SelectionImageObject = selection

	local moveConnection: RBXScriptConnection? = nil
	local endConnection: RBXScriptConnection? = nil
	local function stopDrag()
		if moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
		if endConnection then
			endConnection:Disconnect()
			endConnection = nil
		end
	end
	local function setFromX(x: number)
		local rail: Frame? = object.rail
		if rail == nil or rail.AbsoluteSize.X <= 0 then
			return
		end
		local ratio = math.clamp((x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X, 0, 1)
		local min, max = bounds(object.props)
		set(object, min + (max - min) * ratio)
	end
	object.trove:Connect(root.InputBegan, function(input: InputObject)
		if object.props.enabled == false then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		stopDrag()
		setFromX(input.Position.X)
		moveConnection = UserInputService.InputChanged:Connect(function(moved: InputObject)
			local movedKind = moved.UserInputType
			if movedKind == Enum.UserInputType.MouseMovement or movedKind == Enum.UserInputType.Touch then
				setFromX(moved.Position.X)
			end
		end)
		endConnection = UserInputService.InputEnded:Connect(function(ended: InputObject)
			if ended.UserInputType == kind then
				stopDrag()
			end
		end)
	end)

	nextId += 1
	local actionName = "UrkSlider_" .. tostring(nextId)
	local bound = false
	local function nudge(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local min, max, step = bounds(object.props)
		local delta = math.max(step, (max - min) / 20)
		local direction = if input.KeyCode == Enum.KeyCode.DPadLeft then -1 else 1
		set(object, (object.props.value or min) + delta * direction)
		return Enum.ContextActionResult.Sink
	end
	local function unbind()
		if bound then
			bound = false
			ContextActionService:UnbindAction(actionName)
		end
	end
	object.trove:Connect(root.SelectionGained, function()
		if object.props.enabled == false or bound then
			return
		end
		bound = true
		local priority = Enum.ContextActionPriority.High.Value
		local left, right = Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight
		ContextActionService:BindActionAtPriority(actionName, nudge, false, priority, left, right)
	end)
	object.trove:Connect(root.SelectionLost, unbind)
	object.trove:Add(function()
		stopDrag()
		unbind()
		object.Changed:DisconnectAll()
	end)
end

function Slider.new(props: Props)
	local object = Base.new({
		className = "TextButton",
		name = "Slider",
		props = props,
		size = UDim2.fromOffset(240, 36),
		build = build,
		setup = setup,
		apply = function(self: any, partial: { [string]: any }): boolean
			for key in pairs(partial) do
				if key ~= "value" and key ~= "onChanged" then
					return false
				end
			end
			render(self)
			return true
		end,
	})
	function object.set(self: any, value: number, silent: boolean?)
		set(self, value, silent)
	end
	return object
end

return Slider
