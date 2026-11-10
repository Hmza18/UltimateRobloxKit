--!strict
-- Tab bar: a dark pill track with one button per tab and a gradient indicator that springs to the
-- active tab ("IndicatorSlide"). Fires Changed(id) when the player picks another tab.
--   local tabs = TabBar.new({ tabs = { { id = "pets", text = "PETS" }, { id = "eggs", text = "EGGS" } },
--       value = "pets", parent = window.Content })
--   tabs.Changed:Connect(function(id) pages:show(id) end)
--   tabs:select("eggs")           -- from code; pass true as the second argument to stay silent
--
-- Every tab is a gamepad-selectable button at least 44 px tall. `update({ value = id })` moves the
-- indicator without a rebuild.

local Base = require("./Base")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Tab = { id: string, text: string?, icon: string?, image: string? }

export type Props = {
	tabs: { Tab | string }?,
	value: string?, -- active tab id (default: the first tab)
	palette: string?, -- indicator colour, default "blue"
	enabled: boolean?,
	onChanged: ((id: string) -> ())?,
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

local TabBar = {}

local INSET = 4

-- Tabs as records: strings become { id = s, text = s }.
function TabBar.normalize(tabs: { Tab | string }?): { Tab }
	local out: { Tab } = {}
	local list: { Tab | string } = tabs or {}
	for _, tab in list do
		if type(tab) == "string" then
			table.insert(out, { id = tab, text = tab })
		else
			table.insert(out, tab)
		end
	end
	return out
end

function TabBar.indexOf(tabs: { Tab }, id: string?): number
	for index, tab in tabs do
		if tab.id == id then
			return index
		end
	end
	return 1
end

local function slot(index: number, count: number): (UDim2, UDim2)
	local share = 1 / math.max(1, count)
	return UDim2.new((index - 1) * share, INSET, 0, INSET), UDim2.new(share, -INSET * 2, 1, -INSET * 2)
end

local function paint(object: any)
	for index, label in object.labels do
		label.TextTransparency = if index == object.active then 0 else 0.35
	end
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	local tabs = TabBar.normalize(props.tabs)
	object.tabs = tabs
	object.active = TabBar.indexOf(tabs, props.value)
	object.labels = {}
	local trackProps: Panel.SurfaceProps =
		{ surface = "dark", radius = "pill", outline = "thick", gloss = false, shadow = true }
	local track = Panel.surface(object, root, trackProps).content

	local indicator = Extra.frame(track, "Indicator")
	indicator.ZIndex = 1
	indicator.Position, indicator.Size = slot(object.active, #tabs)
	local swatch = if props.enabled == false
		then Style.palette(style, "gray")
		else Style.palette(style, props.palette or "blue")
	Extra.surface(object, indicator, swatch, { radius = Kit.radius(style, "pill"), outline = "thin", shadow = false })
	object.indicator = indicator

	for index, tab in tabs do
		local button = Instance.new("TextButton")
		button.Name = "Tab_" .. tab.id
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.ZIndex = 2
		button.Position, button.Size = slot(index, #tabs)
		button.Selectable = true
		button.Active = props.enabled ~= false
		Kit.internal(button)
		local selection = Kit.selectionImage(style, Kit.radius(style, "pill"))
		selection.Parent = button
		button.SelectionImageObject = selection
		local holder = Extra.frame(button, "Holder")
		local icon = Extra.image(holder, "Icon", tab.icon, tab.image, {
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 8, 0.5, 0),
			size = UDim2.fromScale(0.6, 0.6),
		})
		if icon then
			icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		end
		local hasText = tab.text ~= nil and tab.text ~= ""
		local label = Extra.label(object, holder, "Label", { text = tab.text or "", role = "label" }, {
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -6, 0.5, 0),
			size = if icon and hasText then UDim2.new(1, -40, 0.8, 0) else UDim2.new(1, -12, 0.8, 0),
		})
		if icon and not hasText then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end
		object.labels[index] = label
		button.Parent = track
		object.parts:Add(button)
		local binding = Extra.UI.bind(button, "Snappy", {
			target = holder :: GuiObject,
			enabled = function(): boolean
				return object.props.enabled ~= false
			end,
			onActivated = function()
				object:select(tab.id)
			end,
		})
		object.parts:Add(binding.destroy)
	end
	paint(object)
end

local function move(object: any, index: number)
	object.active = index
	local position, size = slot(index, #object.tabs)
	if object.indicator then
		Extra.UI.animate(object.indicator, "IndicatorSlide", { position = position, size = size })
	end
	local label = object.labels[index]
	if label then
		Extra.UI.animate(label, "TextBounce", { intensity = 0.4 })
	end
	paint(object)
end

local function apply(object: any, partial: { [string]: any }): boolean
	for key in pairs(partial) do
		if key ~= "value" and key ~= "onChanged" then
			return false
		end
	end
	if partial.value ~= nil and object.tabs then
		local index = TabBar.indexOf(object.tabs, object.props.value)
		if index ~= object.active then
			move(object, index)
		end
	end
	return true
end

function TabBar.new(props: Props)
	local object = Base.new({
		className = "Frame",
		name = "TabBar",
		props = props,
		size = UDim2.new(1, 0, 0, 52),
		build = build,
		apply = apply,
		setup = function(self: any)
			self.Changed = Signal.new()
			self.trove:Add(function()
				self.Changed:DisconnectAll()
			end)
		end,
	})

	-- Makes `id` the active tab. Fires Changed and Activated unless `silent`.
	function object.select(self: any, id: string, silent: boolean?)
		if self.destroyed or self.props.enabled == false then
			return
		end
		local index = TabBar.indexOf(self.tabs, id)
		if self.tabs[index] == nil or self.tabs[index].id ~= id or index == self.active then
			return
		end
		self.props.value = id
		move(self, index)
		if not silent then
			self.Changed:Fire(id)
			self.Activated:Fire(id)
			if self.props.onChanged then
				self.props.onChanged(id)
			end
		end
	end

	function object.value(self: any): string?
		local tab = self.tabs[self.active]
		return if tab then tab.id else nil
	end

	return object
end

return TabBar
