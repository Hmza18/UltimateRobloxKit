--!strict
-- Settings panel built from a schema (see Core/SettingsSchema): toggles, sliders, dropdowns and
-- keybind displays, grouped by section. Every change is validated and coerced by the schema, then
-- emitted through onChanged(key, value, allValues). The panel stores nothing itself: the game
-- decides whether to save values, send them to the server or apply them locally.
-- Gamepad: rows are a UrkNav group; left/right on a selected slider or dropdown changes it.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local SettingsSchema = require("../Core/SettingsSchema")
local Trove = require("../../Util/Trove")

export type Props = {
	schema: SettingsSchema.Schema,
	values: SettingsSchema.Values?,
	onChanged: (key: string, value: any, values: SettingsSchema.Values) -> (),
	size: UDim2?,
	parent: Instance?,
}

local SettingsPanel = {}

local ROW_HEIGHT = 48
local CONTROL_WIDTH = 200

function SettingsPanel.new(props: Props)
	local context = Context.get()
	local problems = SettingsSchema.validate(props.schema)
	if #problems > 0 then
		error("SettingsPanel schema is invalid: " .. table.concat(problems, "; "), 2)
	end
	local values = SettingsSchema.sanitize(props.schema, props.values or SettingsSchema.defaults(props.schema))
	local trove = Trove.new()
	local refreshers: { [string]: () -> () } = {}

	local root = Create.new("ScrollingFrame", {
		Name = "Settings",
		Size = props.size or UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Tags = { "UrkNav" },
	})
	Create.list(Enum.FillDirection.Vertical, 6).Parent = root
	trove:Add(root)

	local function change(key: string, value: any)
		local nextValues, changed = SettingsSchema.applyChange(props.schema, values, key, value)
		if not changed then
			return
		end
		values = nextValues
		local refresh = refreshers[key]
		if refresh then
			refresh()
		end
		props.onChanged(key, values[key], table.clone(values))
	end

	local function label(text: string, parent: Instance, isSection: boolean?)
		local attributes = { TextRole = "text", TextSize = "body" }
		if isSection then
			attributes = { TextRole = "textMuted", TextSize = "label" }
		end
		return Create.new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = if isSection then UDim2.new(1, 0, 0, 32) else UDim2.new(1, -CONTROL_WIDTH - 16, 1, 0),
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Tags = { "UrkTheme" },
			Attributes = attributes,
			Parent = parent,
		})
	end

	local function control(className: string, parent: Instance): any
		local object = Create.new(className, {
			Name = "Control",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(CONTROL_WIDTH, ROW_HEIGHT - 12),
			BorderSizePixel = 0,
			Text = "",
			Tags = { "UrkTheme" },
			Attributes = { Role = "surfaceAlt", TextRole = "text", TextSize = "body", Radius = "md" },
		})
		if object:IsA("GuiButton") then
			object.AutoButtonColor = false
		end
		object.Parent = parent
		return object
	end

	-- Left/right on a selected control steps it (sliders and dropdowns).
	local function onStep(button: GuiObject, step: (delta: number) -> ())
		trove:Connect(UserInputService.InputBegan, function(input: InputObject)
			if GuiService.SelectedObject ~= button then
				return
			end
			if input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
				step(1)
			elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
				step(-1)
			end
		end)
	end

	local function buildToggle(entry: SettingsSchema.Entry, row: Instance)
		local button = control("TextButton", row)
		refreshers[entry.key] = function()
			local on = values[entry.key] == true
			button.Text = if on then context.localize:t("On") else context.localize:t("Off")
			button:SetAttribute("Role", if on then "primary" else "surfaceAlt")
			button:SetAttribute("TextRole", if on then "onPrimary" else "text")
		end
		trove:Connect(button.Activated, function()
			change(entry.key, not values[entry.key])
		end)
	end

	local function buildSlider(entry: SettingsSchema.Entry, row: Instance)
		local track = control("TextButton", row)
		track.Selectable = true
		local fill = Create.new("Frame", {
			Name = "Fill",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			Tags = { "UrkTheme" },
			Attributes = { Role = "primary", Radius = "md" },
			Parent = track,
		})
		local valueLabel = Create.new("TextLabel", {
			Name = "Value",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Tags = { "UrkTheme" },
			Attributes = { TextRole = "text", TextSize = "caption" },
			Parent = track,
		})
		refreshers[entry.key] = function()
			local fraction = SettingsSchema.toFraction(entry, values[entry.key])
			fill.Size = UDim2.fromScale(fraction, 1)
			valueLabel.Text = tostring(values[entry.key])
		end
		local dragging = false
		local function setFromX(x: number)
			local width = math.max(1, track.AbsoluteSize.X)
			local fraction = (x - track.AbsolutePosition.X) / width
			change(entry.key, SettingsSchema.fromFraction(entry, fraction))
		end
		trove:Connect(track.InputBegan, function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		trove:Connect(UserInputService.InputChanged, function(input: InputObject)
			local kind = input.UserInputType
			if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
				setFromX(input.Position.X)
			end
		end)
		trove:Connect(UserInputService.InputEnded, function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		local step = entry.step or ((entry.max or 1) - (entry.min or 0)) / 20
		onStep(track, function(delta: number)
			change(entry.key, values[entry.key] + step * delta)
		end)
	end

	local function buildDropdown(entry: SettingsSchema.Entry, row: Instance)
		local button = control("TextButton", row)
		refreshers[entry.key] = function()
			button.Text = context.localize:t(tostring(values[entry.key])) .. "  v"
		end
		trove:Connect(button.Activated, function()
			local items = {}
			for _, option in entry.options or {} do
				table.insert(items, {
					label = context.localize:t(option),
					callback = function()
						change(entry.key, option)
					end,
				})
			end
			context.menu:open(items, button, button)
		end)
		onStep(button, function(delta: number)
			change(entry.key, SettingsSchema.cycleOption(entry, values[entry.key], delta))
		end)
	end

	local function buildKeybind(entry: SettingsSchema.Entry, row: Instance)
		local display = control("TextLabel", row)
		refreshers[entry.key] = function()
			display.Text = tostring(values[entry.key])
		end
	end

	local builders: { [string]: (entry: SettingsSchema.Entry, row: Instance) -> () } = {
		toggle = buildToggle,
		slider = buildSlider,
		dropdown = buildDropdown,
		keybind = buildKeybind,
	}

	local order = 0
	for _, section in SettingsSchema.sections(props.schema) do
		if section.name ~= "" then
			order += 1
			local header = label(context.localize:t(section.name), root, true)
			header.LayoutOrder = order
		end
		for _, entry in section.entries do
			order += 1
			local row = Create.new("Frame", {
				Name = entry.key,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
				LayoutOrder = order,
				Parent = root,
			})
			local text = if entry.labelKey then context.localize:t(entry.labelKey) else entry.label or entry.key
			label(text, row)
			builders[entry.kind](entry, row)
			refreshers[entry.key]()
		end
	end

	if props.parent then
		root.Parent = props.parent
	end

	local handle = {}
	handle.Instance = root

	function handle.getValues(_self: any): SettingsSchema.Values
		return table.clone(values)
	end

	-- Replaces the shown values (sanitised by the schema). Does not call onChanged.
	function handle.setValues(_self: any, newValues: SettingsSchema.Values)
		values = SettingsSchema.sanitize(props.schema, newValues)
		for _, refresh in refreshers do
			refresh()
		end
	end

	function handle.Destroy(_self: any)
		trove:Destroy()
	end

	return handle
end

return SettingsPanel
