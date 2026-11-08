--!strict
-- Countdown pill ("1:59:30" or "1h 59m") with an optional clock icon. All timers share one ticker
-- (Game/Ticker) that runs about four times a second only while a timer is counting.
--   local timer = Timer.new({ seconds = 3600, format = "clock", icon = "clock", onDone = refresh })
--   timer:update({ seconds = 120 })  -- restart from 2 minutes
--   timer.Done:Connect(fn)

local Base = require("./Base")
local Format = require("../Core/Format")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Ticker = require("./Ticker")

export type Props = {
	seconds: number?,
	format: string?, -- "clock" (default) | "short"
	icon: string?,
	prefix: string?, -- text before the time, for example "Ends in "
	onDone: (() -> ())?,
	surface: string?, -- default "dark"
	palette: string?,
	background: boolean?, -- false draws only the text (default true)
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

local Timer = {}

-- Display text for `seconds` left in a format.
function Timer.text(seconds: number, format: string?, prefix: string?): string
	local left = math.max(0, math.ceil(seconds))
	local body = if format == "short" then Format.duration(left) else Format.time(left)
	return (prefix or "") .. body
end

local function remaining(object: any): number
	if object.deadline == nil then
		return math.max(0, object.props.seconds or 0)
	end
	return math.max(0, object.deadline - os.clock())
end

local CHEAP: { [string]: boolean } = { seconds = true, onDone = true }

local function render(object: any)
	local label = object.label
	if label then
		label.Text = Timer.text(remaining(object), object.props.format, object.props.prefix)
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local container: Instance = root
	if props.background ~= false then
		local surfaceProps: Panel.SurfaceProps = {
			surface = if props.palette then nil else props.surface or "dark",
			palette = props.palette,
			radius = "pill",
			outline = "regular",
			gloss = false,
			shadow = false,
		}
		container = Panel.surface(object, root, surfaceProps).content
	end
	local hasIcon = false
	if props.icon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 4, 0.5, 0)
		icon.Size = UDim2.fromScale(0.8, 0.8)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		hasIcon = Kit.icon(icon, props.icon)
		icon.Parent = container
		object.parts:Add(icon)
	end
	local label = Instance.new("TextLabel")
	label.Name = "Time"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0.5)
	label.Position = UDim2.new(1, -6, 0.5, 0)
	label.Size = if hasIcon then UDim2.new(0.72, -6, 0.86, 0) else UDim2.new(1, -12, 0.86, 0)
	local text = Timer.text(remaining(object), props.format, props.prefix)
	local options: GameText.TextOptions = { text = text, role = "price", maxSize = 22 }
	GameText.decorate(label, style, options, object.parts)
	label.Parent = container
	object.parts:Add(label)
	object.label = label
end

local function start(object: any)
	if object.stopTicker then
		object.stopTicker()
		object.stopTicker = nil
	end
	object.finished = false
	object.deadline = os.clock() + math.max(0, object.props.seconds or 0)
	render(object)
	object.stopTicker = Ticker.slow(function(): boolean?
		if object.destroyed then
			return false
		end
		render(object)
		if remaining(object) <= 0 and not object.finished then
			object.finished = true
			object.stopTicker = nil
			object.Done:Fire()
			if object.props.onDone then
				task.spawn(object.props.onDone)
			end
			return false
		end
		return true
	end)
end

function Timer.new(props: Props)
	local object = Base.new({
		className = "Frame",
		name = "Timer",
		props = props,
		size = UDim2.fromOffset(120, 34),
		build = build,
		apply = function(self: any, partial: { [string]: any }): boolean
			if partial.seconds ~= nil then
				start(self)
			end
			for key in pairs(partial) do
				if not CHEAP[key] then
					return false
				end
			end
			return true
		end,
		setup = function(self: any)
			self.Done = Signal.new()
			self.trove:Add(function()
				if self.stopTicker then
					self.stopTicker()
					self.stopTicker = nil
				end
				self.Done:DisconnectAll()
			end)
			start(self)
		end,
	})
	-- Seconds left on the countdown.
	function object.remaining(self: any): number
		return remaining(self)
	end
	return object
end

return Timer
