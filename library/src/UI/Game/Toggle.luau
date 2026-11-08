--!strict
-- Pill switch: green track when on, gray when off, white outlined knob that slides across.
-- Mouse, touch and gamepad (A) toggle it.
--   local music = Toggle.new({ value = true, onChanged = function(on) setMusic(on) end })
--   music.Changed:Connect(fn) ; music:set(false)

local Base = require("./Base")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")
local Surface = require("./Surface")

export type Props = {
	value: boolean?,
	onChanged: ((boolean) -> ())?,
	onPalette: string?, -- default "green"
	enabled: boolean?,
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	action: string?,
	[string]: any,
}

local Toggle = {}

local INSET = 4

-- The knob keeps AnchorPoint (0, 0.5), so moving it never jumps; "on" needs its width in 1x pixels.
local function knobPosition(knob: Frame, on: boolean): UDim2
	if not on then
		return UDim2.new(0, INSET, 0.5, 0)
	end
	local width = knob.AbsoluteSize.X / Kit.scaleFactor(knob)
	if width <= 0 then
		width = 32
	end
	return UDim2.new(1, -(width + INSET), 0.5, 0)
end

local function paint(object: any, animate: boolean)
	local props = object.props
	local on = props.value == true
	local palette = if on then props.onPalette or "green" else "gray"
	if props.enabled == false then
		palette = "gray"
	end
	if object.surface then
		Surface.paint(object.surface, Style.palette(object.style, palette))
	end
	local knob: Frame? = object.knob
	if knob then
		local target = knobPosition(knob, on)
		if animate then
			Motion.tween(knob, { Position = target }, "fast", Enum.EasingStyle.Back)
		else
			knob.Position = target
		end
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: TextButton = object.Instance
	root.Active = props.enabled ~= false
	local surfaceProps: Panel.SurfaceProps = {
		palette = "gray",
		radius = "pill",
		outline = "thick",
		gloss = true,
		shadow = false,
	}
	object.surface = Panel.surface(object, root, surfaceProps)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BorderSizePixel = 0
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2)
	knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
	knob.ZIndex = 5
	Kit.corner(Kit.radius(style, "pill")).Parent = knob
	Kit.stroke(style, "regular").Parent = knob
	knob.Parent = root
	object.parts:Add(knob)
	object.knob = knob
	paint(object, false)
	-- Re-place the "on" knob once its real width is known (and after resizes).
	local lastWidth = -1
	object.parts:Connect(knob:GetPropertyChangedSignal("AbsoluteSize"), function()
		local width = math.floor(knob.AbsoluteSize.X / Kit.scaleFactor(knob) + 0.5)
		if width ~= lastWidth then
			lastWidth = width
			Motion.cancel(knob)
			knob.Position = knobPosition(knob, object.props.value == true)
		end
	end)
end

-- Sets the value. Fires Changed and onChanged only when it changes and `silent` is not true.
local function set(object: any, value: boolean, silent: boolean?)
	if object.props.value == value then
		return
	end
	object.props.value = value
	paint(object, true)
	if not silent then
		object.Changed:Fire(value)
		if object.props.onChanged then
			task.spawn(object.props.onChanged, value)
		end
	end
end

function Toggle.new(props: Props)
	local object = Base.new({
		className = "TextButton",
		name = "Toggle",
		props = props,
		size = UDim2.fromOffset(76, 40),
		build = build,
		interactive = true,
		apply = function(self: any, partial: { [string]: any }): boolean
			for key in pairs(partial) do
				if key ~= "value" and key ~= "onChanged" then
					return false
				end
			end
			paint(self, true)
			return true
		end,
		setup = function(self: any)
			self.Changed = Signal.new()
			self.trove:Add(function()
				self.Changed:DisconnectAll()
			end)
		end,
		onPress = function(self: any)
			set(self, self.props.value ~= true)
		end,
	})
	function object.set(self: any, value: boolean, silent: boolean?)
		set(self, value, silent)
	end
	return object
end

return Toggle
