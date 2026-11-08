--!strict
-- The single source of truth for UrkUI's CollectionService tags and their attributes, plus pure
-- helpers that read attributes with defaults and parse Action and menu strings.
-- README.md mirrors this table; ui_tagspec.spec.luau checks the two stay consistent in shape.

export type AttributeSpec = {
	kind: string, -- "string" | "number" | "boolean" | "Color3" | "any"
	default: any,
	required: boolean?,
	description: string,
}

export type TagDef = {
	description: string,
	attributes: { [string]: AttributeSpec },
	dynamic: string?, -- documents attribute families such as "Arg_<name>"
}

export type ActionCall = { name: string, args: { string }, raw: string }
export type MenuItem = { label: string, action: string?, separator: boolean }

local TagSpec = {}

local function attr(kind: string, default: any, description: string, required: boolean?): AttributeSpec
	return { kind = kind, default = default, description = description, required = required }
end

local PANEL_ATTRIBUTES: { [string]: AttributeSpec } = {
	PanelId = attr("string", nil, "Router id used by OpenPanel/ClosePanel/TogglePanel", true),
	Group = attr("string", nil, "Exclusive group: opening one panel closes the others in the group"),
	Exclusive = attr("boolean", true, "Set false to let panels of the same group stack"),
	Modal = attr("boolean", false, "Draw above normal panels with a backdrop"),
	Dismissible = attr("boolean", true, "false blocks Back (gamepad B / Escape) and backdrop clicks"),
	AdoptPriority = attr("number", 0, "When two instances share a PanelId, the highest priority is used"),
	StartOpen = attr("boolean", false, "Open as soon as the panel is bound"),
	Transition = attr("string", "pop", "none | fade | pop | slideUp | slideDown | slideLeft | slideRight"),
	CloseOnBackdrop = attr("boolean", true, "Clicking the modal backdrop closes the panel"),
}

TagSpec.tags = {
	UrkPanel = { description = "A GuiObject or ScreenGui managed by the panel router", attributes = PANEL_ATTRIBUTES },
	UrkModal = { description = "Same as UrkPanel with Modal = true", attributes = PANEL_ATTRIBUTES },
	UrkButton = {
		description = "GuiButton with hover/press feedback, sounds, tooltip and an Action",
		attributes = {
			Action = attr("string", nil, "Action spec, e.g. TogglePanel:Shop or OpenPanel:Shop;PlaySound"),
			Target = attr("string", nil, "Default argument for the action when the spec has none"),
			Variant = attr("string", nil, "primary | secondary | ghost | danger: themed colours and states"),
			Tooltip = attr("string", nil, "Tooltip text"),
			TooltipKey = attr("string", nil, "Localisation key for the tooltip"),
			HoverScale = attr("number", 1.05, "Scale while hovered or gamepad-selected"),
			PressScale = attr("number", 0.95, "Scale while pressed"),
			HoverSound = attr("string", nil, "Sound asset id played on hover"),
			ClickSound = attr("string", nil, "Sound asset id played on activation"),
			Cooldown = attr("number", 0, "Seconds between activations"),
		},
	},
	UrkBind = {
		description = "Writes a Store value into a property (Text by default)",
		attributes = {
			Path = attr("string", nil, "Store path such as Stats.Cash", true),
			Format = attr("string", nil, "number | abbrev | percent | time | duration | <custom>[:arg]"),
			Property = attr("string", "Text", "Property to write"),
			Template = attr("string", nil, "Text template with {value}, e.g. Cash: {value}"),
			Animate = attr("boolean", false, "Count up/down to new numeric values"),
			Fallback = attr("string", "", "Shown while the value is nil"),
		},
	},
	UrkProgress = {
		description = "Progress bar: scales a child Fill frame by Value / Max",
		attributes = {
			Path = attr("string", nil, "Store path of the current value"),
			Value = attr("number", 0, "Static value when Path is not set"),
			Max = attr("number", 1, "Maximum value"),
			MaxPath = attr("string", nil, "Store path of the maximum"),
			Fill = attr("string", "Fill", "Name of the child frame that is scaled"),
			Segments = attr("number", 0, "Draw this many segment dividers"),
			Animate = attr("boolean", true, "Tween the fill"),
			Vertical = attr("boolean", false, "Fill bottom-to-top instead of left-to-right"),
		},
	},
	UrkTabs = {
		description = "Tab container: descendants tagged UrkTab switch descendants with a TabPage attribute",
		attributes = { Selected = attr("string", nil, "The selected tab; defaults to the first tab") },
	},
	UrkTab = {
		description = "A GuiButton inside UrkTabs that selects a page",
		attributes = { Tab = attr("string", nil, "Name of the page (TabPage attribute) it shows", true) },
	},
	UrkTooltip = {
		description = "Shows the shared tooltip on hover and gamepad selection",
		attributes = {
			Text = attr("string", nil, "Tooltip text"),
			Key = attr("string", nil, "Localisation key, used instead of Text"),
			Delay = attr("number", 0.35, "Seconds before showing"),
			Placement = attr("string", "below", "below | above | left | right"),
		},
	},
	UrkToastHost = {
		description = "A frame toasts are placed in; without one UrkUI creates its own top-right host",
		attributes = {},
	},
	UrkDraggable = {
		description = "Can be dragged onto UrkDropTarget elements; fires UrkUI.Dropped",
		attributes = {
			DragId = attr("string", nil, "Payload id sent with the drop"),
			DragGroup = attr("string", "default", "Only targets of the same group accept it"),
		},
	},
	UrkDropTarget = {
		description = "Accepts UrkDraggable drops of the same DragGroup",
		attributes = {
			DropId = attr("string", nil, "Id sent with the drop"),
			DragGroup = attr("string", "default", "Group of draggables accepted"),
		},
	},
	UrkIcon = {
		description = "ImageLabel/ImageButton filled from the Icons catalogue",
		attributes = {
			Icon = attr("string", nil, "Icon name", true),
			IconColor = attr("Color3", nil, "Tint"),
			IconSize = attr("number", nil, "Square size in pixels"),
		},
	},
	UrkAnimate = {
		description = "Decorative effect driven by the shared frame driver",
		attributes = {
			Effect = attr("string", nil, "Spin | Bob | Pulse | Shine | Rainbow", true),
			Speed = attr("number", nil, "Effect speed (see Decor)"),
			Amplitude = attr("number", nil, "Effect size (see Decor)"),
			Phase = attr("number", 0, "Offset so neighbours do not move in sync"),
			Pause = attr("number", nil, "Shine: rest between sweeps in seconds"),
		},
	},
	UrkTheme = {
		description = "Re-skinned from the active theme",
		attributes = {
			Role = attr("string", nil, "Background role, e.g. surface or primary:hover"),
			TextRole = attr("string", nil, "TextColor3 role"),
			StrokeRole = attr("string", nil, "Role for a child UIStroke"),
			ImageRole = attr("string", nil, "ImageColor3 role"),
			PlaceholderRole = attr("string", nil, "TextBox PlaceholderColor3 role"),
			TransparencyRole = attr("string", nil, "BackgroundTransparency from the theme, e.g. overlay"),
			TextSize = attr("string", nil, "Text token, e.g. body or title (minimum text size applies)"),
			Radius = attr("string", nil, "Radius token for a UICorner, e.g. md or pill"),
		},
	},
	UrkLocalize = {
		description = "Text from the Localizer, re-applied when the locale changes",
		attributes = {
			Key = attr("string", nil, "Localisation key", true),
			Property = attr("string", "Text", "Property to write"),
		},
		dynamic = "Arg_<name> gives a literal placeholder value; ArgPath_<name> binds one to a Store path",
	},
	UrkContextMenu = {
		description = "Opens a context menu on right-click, long-press or gamepad X",
		attributes = { Items = attr("string", nil, "Label=Action pairs separated by ;  use - for a separator", true) },
	},
	UrkNav = {
		description = "Gamepad focus group: wires NextSelection* from a spatial graph",
		attributes = {
			Wrap = attr("boolean", false, "Wrap around at the edges"),
			AutoSelect = attr("boolean", true, "Select the first element when the group appears"),
			Remember = attr("boolean", true, "Return to the last selected element"),
		},
	},
	UrkResponsive = {
		description = "Applies per-breakpoint attribute overrides and optional UIScale",
		attributes = { AutoScale = attr("boolean", false, "Add a UIScale driven by the breakpoint maths") },
		dynamic = "Phone_<Property>, Tablet_<Property>, Desktop_<Property>, Console_<Property>",
	},
} :: { [string]: TagDef }

-- Tag names in a stable order, for docs and binding.
function TagSpec.names(): { string }
	local names: { string } = {}
	for name in TagSpec.tags do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function kindOf(value: any, typeOf: (any) -> string): string
	return typeOf(value)
end

-- Reads every declared attribute of `tag` through `getAttribute`, applying defaults and checking
-- kinds. Pass Roblox's `typeof` as typeOf so Color3 attributes are recognised; plain `type` is the
-- default (Lune). Returns the values and human-readable warnings.
export type Getter = (name: string) -> any

function TagSpec.read(tag: string, getAttribute: Getter, typeOf: ((any) -> string)?): ({ [string]: any }, { string })
	local def = TagSpec.tags[tag]
	assert(def ~= nil, "unknown tag " .. tostring(tag))
	local check: (any) -> string = typeOf or type
	local values: { [string]: any } = {}
	local warnings: { string } = {}
	for name, spec in def.attributes do
		local value = getAttribute(name)
		if value == nil then
			if spec.required then
				table.insert(warnings, string.format("%s needs the %s attribute", tag, name))
			end
			values[name] = spec.default
		elseif spec.kind ~= "any" and kindOf(value, check) ~= spec.kind then
			local message = "%s.%s should be a %s, got %s"
			table.insert(warnings, string.format(message, tag, name, spec.kind, kindOf(value, check)))
			values[name] = spec.default
		else
			values[name] = value
		end
	end
	return values, warnings
end

local function trim(text: string): string
	local trimmed = string.match(text, "^%s*(.-)%s*$")
	return trimmed or text
end

-- "OpenPanel:Shop; ShowToast:Saved, success" gives two calls:
--   { name = "OpenPanel", args = { "Shop" }, raw = "Shop" }
--   { name = "ShowToast", args = { "Saved", "success" }, raw = "Saved, success" }
function TagSpec.parseAction(spec: string?): { ActionCall }
	local calls: { ActionCall } = {}
	if spec == nil then
		return calls
	end
	for _, part in string.split(spec, ";") do
		local text = trim(part)
		if text ~= "" then
			local name, raw = string.match(text, "^([%w_]+)%s*:%s*(.*)$")
			if name == nil then
				name = string.match(text, "^([%w_]+)$")
				raw = ""
			end
			if name ~= nil then
				local args: { string } = {}
				if raw ~= nil and raw ~= "" then
					for _, piece in string.split(raw, ",") do
						table.insert(args, trim(piece))
					end
				end
				table.insert(calls, { name = name, args = args, raw = raw or "" })
			end
		end
	end
	return calls
end

-- "Equip=EquipItem; -; Drop=DropItem:all" -> items with labels and action specs; "-" is a separator.
function TagSpec.parseMenuItems(spec: string?): { MenuItem }
	local items: { MenuItem } = {}
	if spec == nil then
		return items
	end
	for _, part in string.split(spec, ";") do
		local text = trim(part)
		if text == "-" then
			table.insert(items, { label = "", action = nil, separator = true })
		elseif text ~= "" then
			local label, action = string.match(text, "^(.-)%s*=%s*(.+)$")
			if label ~= nil and label ~= "" then
				table.insert(items, { label = label, action = action, separator = false })
			else
				table.insert(items, { label = text, action = nil, separator = false })
			end
		end
	end
	return items
end

-- Collects "Arg_<name>" attributes into a table: { Arg_count = 3 } -> { count = 3 }.
function TagSpec.prefixed(attributes: { [string]: any }, prefix: string): { [string]: any }
	local found: { [string]: any } = {}
	local length = #prefix
	for name, value in attributes do
		if string.sub(name, 1, length) == prefix and #name > length then
			found[string.sub(name, length + 1)] = value
		end
	end
	return found
end

return TagSpec
