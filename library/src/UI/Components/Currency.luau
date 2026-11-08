--!strict
-- Currency display: icon plus an animated, abbreviated count. Bind it to a Store path (it then
-- uses UrkBind with Animate) or drive it with :set(value).
--   Currency.new({ icon = "coin", path = "Stats.Cash", parent = hud:rail("topRight") })

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local Driver = require("../Runtime/Driver")
local Easing = require("../Core/Easing")
local Format = require("../Core/Format")
local IconBridge = require("../Runtime/IconBridge")
local Motion = require("../Runtime/Motion")

export type Props = {
	icon: string?,
	path: string?, -- Store path; when set the label follows the store
	value: number?,
	format: string?, -- default "abbrev"
	role: string?, -- background role, default "surface"
	parent: Instance?,
	layoutOrder: number?,
}

local Currency = {}

function Currency.new(props: Props)
	local context = Context.get()
	local theme = context.theme
	local spec = props.format or "abbrev"
	local frame = Create.new("Frame", {
		Name = "Currency",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Tags = { "UrkTheme" },
		Attributes = { Role = props.role or "surface", Radius = "pill", TransparencyRole = "surface" },
	})
	Create.padding(6, 14).Parent = frame
	Create.list(Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center).Parent = frame
	if props.icon then
		local icon = Create.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(26, 26),
			LayoutOrder = 1,
			Parent = frame,
		})
		IconBridge.apply(icon, props.icon)
	end
	local labelAttributes: { [string]: any } = { TextRole = "text", TextSize = "label" }
	local labelTags = { "UrkTheme" }
	if props.path then
		labelAttributes.Path = props.path
		labelAttributes.Format = spec
		labelAttributes.Animate = true
		table.insert(labelTags, "UrkBind")
	end
	local label = Create.new("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		Text = Format.apply(spec, props.value or 0),
		FontFace = theme:font("title"),
		LayoutOrder = 2,
		Tags = labelTags,
		Attributes = labelAttributes,
		Parent = frame,
	})
	if props.parent then
		frame.Parent = props.parent
	end

	local shown = props.value or 0
	local stopJob: (() -> ())? = nil
	local handle = {}
	handle.Instance = frame

	-- Counts from the shown value to `value`. Ignored when the display is bound to a Store path.
	function handle.set(_self: any, value: number)
		if props.path then
			return
		end
		if stopJob then
			stopJob()
			stopJob = nil
		end
		local from = shown
		local seconds = Motion.duration(Easing.countUpDuration(value - from))
		if value > from then
			Motion.pop(frame, 0.08)
		end
		if seconds <= 0 then
			shown = value
			label.Text = Format.apply(spec, value)
			return
		end
		local started = os.clock()
		stopJob = Driver.add(function(_dt: number, now: number): boolean?
			local t = Easing.progress(started, seconds, now)
			shown = Easing.countUp(from, value, t)
			label.Text = Format.apply(spec, shown)
			if t >= 1 then
				stopJob = nil
				return false
			end
			return true
		end)
	end

	function handle.Destroy(_self: any)
		if stopJob then
			stopJob()
		end
		frame:Destroy()
	end

	return handle
end

return Currency
