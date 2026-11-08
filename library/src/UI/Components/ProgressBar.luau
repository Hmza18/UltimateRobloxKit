--!strict
-- Progress / status bar with an animated fill, optional segments and an optional label.
--   local xp = ProgressBar.new({ value = 30, max = 100, segments = 5, label = "{value} / {max}" })
--   xp:set(45)

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local Format = require("../Core/Format")
local Localizer = require("../Core/Localizer")
local Motion = require("../Runtime/Motion")

export type Props = {
	value: number?,
	max: number?,
	segments: number?,
	role: string?, -- fill colour role, default "primary"
	size: UDim2?,
	label: string?, -- template with {value}, {max} and {percent}
	format: string?, -- format spec for {value} and {max}, default "number"
	parent: Instance?,
	layoutOrder: number?,
}

local ProgressBar = {}

function ProgressBar.new(props: Props)
	local context = Context.get()
	local theme = context.theme
	local bar = Create.new("Frame", {
		Name = "ProgressBar",
		Size = props.size or UDim2.new(1, 0, 0, 18),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Tags = { "UrkTheme" },
		Attributes = { Role = "surfaceAlt", Radius = "pill" },
	})
	local fill = Create.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Tags = { "UrkTheme" },
		Attributes = { Role = props.role or "primary", Radius = "pill" },
		Parent = bar,
	})
	local segments = math.floor(props.segments or 0)
	for index = 1, segments - 1 do
		Create.new("Frame", {
			Name = "Segment",
			Size = UDim2.new(0, 2, 1, 0),
			Position = UDim2.fromScale(index / segments, 0),
			BorderSizePixel = 0,
			BackgroundTransparency = 0.4,
			ZIndex = 2,
			Tags = { "UrkTheme" },
			Attributes = { Role = "background" },
			Parent = bar,
		})
	end
	local label: TextLabel? = nil
	if props.label then
		label = Create.new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			TextSize = theme:textSize("caption"),
			FontFace = theme:font("label"),
			Tags = { "UrkTheme" },
			Attributes = { TextRole = "text" },
			Parent = bar,
		})
	end
	if props.parent then
		bar.Parent = props.parent
	end

	local value = props.value or 0
	local maximum = props.max or 1
	local handle = {}
	handle.Instance = bar

	function handle.set(_self: any, newValue: number, newMax: number?)
		value = newValue
		if newMax then
			maximum = newMax
		end
		local ratio = if maximum > 0 then math.clamp(value / maximum, 0, 1) else 0
		Motion.tween(fill, { Size = UDim2.fromScale(ratio, 1) }, "normal", Enum.EasingStyle.Quad)
		if label and props.label then
			local spec = props.format or "number"
			local args = {
				value = Format.apply(spec, value),
				max = Format.apply(spec, maximum),
				percent = Format.percent(ratio),
			}
			label.Text = Localizer.interpolate(props.label, args)
		end
	end

	function handle.get(_self: any): (number, number)
		return value, maximum
	end

	function handle.Destroy(_self: any)
		bar:Destroy()
	end

	handle:set(value, maximum)
	return handle
end

return ProgressBar
