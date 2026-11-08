--!strict
-- Button component. Builds a TextButton tagged UrkButton + UrkTheme, so it gets the same hover,
-- press, sound, tooltip and theming behaviour as a button tagged in Studio.
--   local buy = Button.new({ text = "Buy", variant = "primary", size = "md", onClick = fn, parent = frame })

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local IconBridge = require("../Runtime/IconBridge")

export type Props = {
	text: string?,
	variant: string?, -- "primary" (default) | "secondary" | "ghost" | "danger"
	size: string?, -- "sm" | "md" (default) | "lg"
	icon: string?,
	action: string?, -- Action spec run on activation, e.g. "OpenPanel:Shop"
	tooltip: string?,
	width: number?, -- pixels; default sizes to the text
	onClick: (() -> ())?,
	layoutOrder: number?,
	parent: Instance?,
}

local Button = {}

function Button.new(props: Props)
	local context = Context.get()
	local theme = context.theme
	local size = theme.tokens.sizes[props.size or "md"] or theme.tokens.sizes.md
	local attributes: { [string]: any } = { Variant = props.variant or "primary", Radius = "md", TextSize = "label" }
	if props.action then
		attributes.Action = props.action
	end
	if props.tooltip then
		attributes.Tooltip = props.tooltip
	end
	local button = Create.new("TextButton", {
		Name = "Button",
		Text = props.text or "",
		AutoButtonColor = false,
		AutomaticSize = if props.width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(props.width or 0, size.height),
		BorderSizePixel = 0,
		TextSize = size.text,
		FontFace = theme:font("label"),
		LayoutOrder = props.layoutOrder or 0,
		Tags = { "UrkButton", "UrkTheme" },
		Attributes = attributes,
	})
	Create.stroke(theme:color("border"), 1).Parent = button
	Create.padding(0, size.padding + (if props.icon then size.height * 0.6 else 0)).Parent = button
	if props.icon then
		local icon = Create.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -6, 0.5, 0),
			Size = UDim2.fromOffset(size.text + 4, size.text + 4),
			Parent = button,
		})
		IconBridge.apply(icon, props.icon)
	end
	local connection: RBXScriptConnection? = nil
	if props.onClick then
		local onClick = props.onClick
		connection = button.Activated:Connect(function()
			onClick()
		end)
	end
	if props.parent then
		button.Parent = props.parent
	end

	local handle = {}
	handle.Instance = button
	handle.Activated = button.Activated

	function handle.setText(_self: any, text: string)
		button.Text = text
	end

	function handle.setEnabled(_self: any, enabled: boolean)
		button.Active = enabled
		button.AutoButtonColor = false
		button:SetAttribute("Variant", if enabled then props.variant or "primary" else "secondary")
		button.TextTransparency = if enabled then 0 else 0.4
	end

	function handle.Destroy(_self: any)
		if connection then
			connection:Disconnect()
		end
		button:Destroy()
	end

	return handle
end

return Button
