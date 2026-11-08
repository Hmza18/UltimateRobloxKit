--!strict
-- HUD currency counter: outlined pill with a big currency icon overlapping its left end, the
-- amount, and an optional green "+" button that runs `action` (for example "OpenPanel:Shop").
-- Value changes count up with the "count" preset (duration and easing) on the shared ticker and
-- pop the icon; under reduced motion the number changes at once.
--   local cash = CurrencyCounter.new({ icon = "coin-color", value = 1250, plus = true, action = "OpenPanel:Shop" })
--   cash:update({ value = 2400 })

local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local Easing = require("../Core/Easing")
local Format = require("../Core/Format")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local MotionPresets = require("../Core/MotionPresets")
local Panel = require("./Panel")
local Ticker = require("./Ticker")

export type Props = {
	icon: string?,
	image: string?,
	value: number?,
	format: string?, -- Core/Format spec, default "abbrev"
	palette: string?, -- default: the dark surface
	plus: boolean?,
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

local CurrencyCounter = {}

function CurrencyCounter.text(value: number, format: string?): string
	return Format.apply(format or "abbrev", value)
end

local function render(object: any)
	if object.label then
		object.label.Text = CurrencyCounter.text(object.shown or 0, object.props.format)
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette,
		surface = if props.palette then nil else "dark",
		radius = "pill",
		outline = "thick",
		gloss = true,
		shadow = true,
	}
	local content = Panel.surface(object, root, surfaceProps).content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Size = UDim2.fromScale(1.3, 1.3)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.ZIndex = 5
	icon.Parent = root
	object.parts:Add(icon)
	object.icon = if Kit.icon(icon, props.icon, props.image) then icon else nil

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0.24, 0.5)
	label.Size = UDim2.fromScale(if props.plus then 0.52 else 0.7, 0.8)
	local text = CurrencyCounter.text(object.shown or props.value or 0, props.format)
	local options: GameText.TextOptions = { text = text, role = "price", maxSize = 28 }
	GameText.decorate(label, style, options, object.parts)
	label.Parent = content
	object.label = label

	if props.plus then
		local plus = CartoonButton.new({
			kind = "buy",
			text = "+",
			style = props.style,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -4, 0.5, 0),
			size = UDim2.fromScale(0.82, 0.82),
			parent = root,
		})
		plus.Instance.SizeConstraint = Enum.SizeConstraint.RelativeYY
		plus.Instance.ZIndex = 5
		plus.Activated:Connect(function()
			object.Activated:Fire(object.props.name)
			Kit.runAction(object.props.action, plus.Instance)
		end)
		object.parts:Add(plus)
	end
end

-- Counts from the shown value to props.value.
local function countTo(object: any, target: number)
	if object.stopCount then
		object.stopCount()
		object.stopCount = nil
	end
	local from = object.shown or 0
	local preset = MotionPresets.get("count")
	local seconds = Motion.duration(preset.duration)
	if target > from and object.icon then
		Motion.play(object.icon, "count")
	end
	if seconds <= 0 or from == target then
		object.shown = target
		render(object)
		return
	end
	local started = os.clock()
	object.stopCount = Ticker.frame(function(now: number): boolean?
		if object.destroyed then
			return false
		end
		local t = Easing.progress(started, seconds, now)
		object.shown = Easing.countUp(from, target, t, preset.easing)
		render(object)
		if t >= 1 then
			object.stopCount = nil
			return false
		end
		return true
	end)
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" and key ~= "format" then
			return false
		end
	end
	countTo(object, object.props.value or 0)
	return true
end

function CurrencyCounter.new(props: Props)
	return Base.new({
		className = "Frame",
		name = "CurrencyCounter",
		props = props,
		size = UDim2.fromOffset(200, 48),
		build = build,
		apply = apply,
		setup = function(self: any)
			self.shown = self.props.value or 0
			self.trove:Add(function()
				if self.stopCount then
					self.stopCount()
					self.stopCount = nil
				end
			end)
		end,
	})
end

return CurrencyCounter
