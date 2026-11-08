--!strict
-- UrkTabs container and UrkTab buttons. Pages are descendants of the container with a TabPage
-- attribute; a tab shows the page whose TabPage equals its Tab attribute. The selection is the
-- container's Selected attribute, so code, actions and Studio edits can all switch tabs.

local Tabs = {}

Tabs.tags = { "UrkTabs", "UrkTab" }

local function owningTabs(instance: Instance): Instance?
	local current = instance.Parent
	while current ~= nil do
		if current:HasTag("UrkTabs") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function collect(container: Instance): ({ GuiObject }, { GuiObject })
	local tabs: { GuiObject } = {}
	local pages: { GuiObject } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiObject") then
			if descendant:HasTag("UrkTab") and owningTabs(descendant) == container then
				table.insert(tabs, descendant)
			end
			if descendant:GetAttribute("TabPage") ~= nil and owningTabs(descendant) == container then
				table.insert(pages, descendant)
			end
		end
	end
	table.sort(tabs, function(a: GuiObject, b: GuiObject): boolean
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.AbsolutePosition.X + a.AbsolutePosition.Y < b.AbsolutePosition.X + b.AbsolutePosition.Y
	end)
	return tabs, pages
end

local function bindContainer(context: any, container: Instance, trove: any, values: { [string]: any })
	local scheduled = false

	local function apply()
		scheduled = false
		local tabs, pages = collect(container)
		local selected = values.Selected
		if selected == nil and tabs[1] then
			selected = tabs[1]:GetAttribute("Tab")
		end
		for _, page in pages do
			page.Visible = page:GetAttribute("TabPage") == selected
		end
		local theme = context.theme
		for _, tab in tabs do
			local isSelected = tab:GetAttribute("Tab") == selected
			tab:SetAttribute("Selected", isSelected)
			if tab:GetAttribute("Variant") == nil and not tab:HasTag("UrkTheme") then
				tab.BackgroundColor3 = theme:color(if isSelected then "primary" else "surfaceAlt")
				if tab:IsA("TextButton") then
					tab.TextColor3 = theme:color(if isSelected then "onPrimary" else "text")
				end
			end
		end
		context.TabChanged:Fire(container, selected)
	end

	local function queue()
		if not scheduled then
			scheduled = true
			task.defer(apply)
		end
	end

	trove:Connect(container.DescendantAdded, queue)
	trove:Connect(context.theme.Changed, queue)
	apply()
end

local function bindTab(_context: any, tab: Instance, trove: any, values: { [string]: any })
	if not tab:IsA("GuiButton") then
		return
	end
	trove:Connect((tab :: GuiButton).Activated, function()
		local container = owningTabs(tab)
		if container and values.Tab then
			container:SetAttribute("Selected", values.Tab)
		end
	end)
end

function Tabs.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkTabs" then
		bindContainer(context, instance, trove, values)
	else
		bindTab(context, instance, trove, values)
	end
end

-- Selects a tab from code.
function Tabs.select(container: Instance, tab: string)
	container:SetAttribute("Selected", tab)
end

return Tabs
