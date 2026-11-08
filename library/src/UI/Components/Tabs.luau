--!strict
-- Tabs component built on the UrkTabs / UrkTab tags.
--   local tabs = Tabs.new({ tabs = { { id = "Items", label = "Items" }, { id = "Pets", label = "Pets" } } })
--   tabs.Pages.Items -- a Frame for the Items page

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")

export type Tab = { id: string, label: string?, labelKey: string? }

export type Props = {
	tabs: { Tab },
	selected: string?,
	onChanged: ((id: string) -> ())?,
	size: UDim2?,
	parent: Instance?,
}

local Tabs = {}

local BAR_HEIGHT = 40

function Tabs.new(props: Props)
	local context = Context.get()
	assert(#props.tabs > 0, "Tabs.new needs at least one tab")
	local selected = props.selected or props.tabs[1].id
	local root = Create.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = props.size or UDim2.fromScale(1, 1),
		Tags = { "UrkTabs" },
		Attributes = { Selected = selected },
	})
	local bar = Create.new("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		Tags = { "UrkNav" },
		Parent = root,
	})
	Create.list(Enum.FillDirection.Horizontal, 6).Parent = bar
	local pagesFrame = Create.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, BAR_HEIGHT + 8),
		Size = UDim2.new(1, 0, 1, -(BAR_HEIGHT + 8)),
		Parent = root,
	})
	local pages: { [string]: Frame } = {}
	for index, tab in props.tabs do
		local tags = { "UrkTab" }
		local attributes: { [string]: any } = { Tab = tab.id, Radius = "md" }
		if tab.labelKey then
			table.insert(tags, "UrkLocalize")
			attributes.Key = tab.labelKey
		end
		local tabButton = Create.new("TextButton", {
			Name = tab.id,
			Text = tab.label or tab.id,
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, BAR_HEIGHT),
			BorderSizePixel = 0,
			LayoutOrder = index,
			FontFace = context.theme:font("label"),
			TextSize = context.theme:textSize("body"),
			Tags = tags,
			Attributes = attributes,
		})
		Create.padding(0, 16).Parent = tabButton
		Create.corner(context.theme:radius("md")).Parent = tabButton
		tabButton.Parent = bar
		pages[tab.id] = Create.new("Frame", {
			Name = tab.id,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = tab.id == selected,
			Attributes = { TabPage = tab.id },
			Parent = pagesFrame,
		})
	end
	if props.parent then
		root.Parent = props.parent
	end

	local connection = context.TabChanged:Connect(function(container: Instance, id: string?)
		if container == root and id and props.onChanged then
			props.onChanged(id)
		end
	end)
	root.Destroying:Connect(function()
		connection:Disconnect()
	end)

	local handle = {}
	handle.Instance = root
	handle.Pages = pages

	function handle.select(_self: any, id: string)
		root:SetAttribute("Selected", id)
	end

	function handle.selected(_self: any): string
		return root:GetAttribute("Selected") or selected
	end

	function handle.Destroy(_self: any)
		root:Destroy()
	end

	return handle
end

return Tabs
