--!strict
-- Gamepad focus groups (UrkNav). Collects the visible, Selectable GuiObjects inside a group,
-- builds a spatial graph with Core/SpatialNav and writes NextSelectionUp/Down/Left/Right, so
-- D-pad and thumbstick movement goes to the nearest element instead of Roblox's default guess.
-- Groups are rewired (at most once per frame) when their contents or layout change.
-- When a panel opens with a gamepad in use, focus moves into it; when it closes, focus returns.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local SpatialNav = require("../Core/SpatialNav")

export type GroupOptions = { wrap: boolean?, autoSelect: boolean?, remember: boolean? }

type Group = { container: GuiObject, options: GroupOptions, last: GuiObject?, scheduled: boolean }

local Focus = {}

local GAMEPAD_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

local function isShown(object: GuiObject, stopAt: Instance): boolean
	local current: Instance? = object
	while current ~= nil and current ~= stopAt do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

-- Visible, Selectable GuiObjects inside `container`, in a stable order.
function Focus.selectables(container: Instance): { GuiObject }
	local list: { GuiObject } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiObject") and descendant.Selectable and isShown(descendant, container) then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Builds the spatial graph for `objects` and writes their NextSelection* properties.
function Focus.wire(objects: { GuiObject }, wrap: boolean?)
	local nodes: { SpatialNav.Node } = {}
	local byId: { [string]: GuiObject } = {}
	for index, object in objects do
		local id = tostring(index)
		byId[id] = object
		local position = object.AbsolutePosition
		local size = object.AbsoluteSize
		table.insert(nodes, { id = id, x = position.X, y = position.Y, w = size.X, h = size.Y })
	end
	local graph = SpatialNav.build(nodes, { wrap = wrap })
	for id, links in graph do
		local object = byId[id]
		object.NextSelectionUp = if links.up then byId[links.up] else nil
		object.NextSelectionDown = if links.down then byId[links.down] else nil
		object.NextSelectionLeft = if links.left then byId[links.left] else nil
		object.NextSelectionRight = if links.right then byId[links.right] else nil
	end
	return nodes
end

function Focus.new(_context: any)
	local focus = {}
	local groups: { [GuiObject]: Group } = {}
	local returnTo: { [Instance]: GuiObject } = {}
	local connections: { RBXScriptConnection } = {}

	function focus.isGamepad(_self: any): boolean
		return GAMEPAD_INPUTS[UserInputService:GetLastInputType()] == true
	end

	local function firstIn(container: Instance): GuiObject?
		local objects = Focus.selectables(container)
		if #objects == 0 then
			return nil
		end
		local nodes = Focus.wire(objects, false)
		local id = SpatialNav.first(nodes)
		return if id then objects[tonumber(id) :: number] else nil
	end

	local function rewire(group: Group)
		group.scheduled = false
		if group.container.Parent == nil then
			return
		end
		Focus.wire(Focus.selectables(group.container), group.options.wrap)
	end

	local function schedule(group: Group)
		if group.scheduled then
			return
		end
		group.scheduled = true
		task.defer(rewire, group)
	end

	local function selectIn(group: Group)
		if group.options.autoSelect == false or not focus:isGamepad() then
			return
		end
		local current = GuiService.SelectedObject
		if current and current:IsDescendantOf(group.container) then
			return
		end
		local remembered = group.last
		if group.options.remember ~= false and remembered and remembered:IsDescendantOf(group.container) then
			GuiService.SelectedObject = remembered
			return
		end
		GuiService.SelectedObject = firstIn(group.container)
	end

	-- Called by the UrkNav behaviour. Everything connected here is owned by `trove`.
	function focus.attachGroup(_self: any, container: GuiObject, options: GroupOptions, trove: any)
		local group: Group = { container = container, options = options, last = nil, scheduled = false }
		groups[container] = group
		local function queue()
			schedule(group)
		end
		trove:Connect(container.DescendantAdded, queue)
		trove:Connect(container.DescendantRemoving, queue)
		trove:Connect(container:GetPropertyChangedSignal("AbsoluteSize"), queue)
		trove:Connect(container:GetPropertyChangedSignal("AbsolutePosition"), queue)
		trove:Connect(container:GetPropertyChangedSignal("Visible"), function()
			schedule(group)
			if container.Visible then
				task.defer(selectIn, group)
			end
		end)
		trove:Add(function()
			groups[container] = nil
		end)
		schedule(group)
		if container.Visible then
			task.defer(selectIn, group)
		end
	end

	function focus.refresh(_self: any, container: GuiObject?)
		for key, group in groups do
			if container == nil or key == container then
				schedule(group)
			end
		end
	end

	function focus.panelOpened(_self: any, panel: Instance)
		if not focus:isGamepad() then
			return
		end
		local current = GuiService.SelectedObject
		if current and not current:IsDescendantOf(panel) then
			returnTo[panel] = current
		end
		-- Let the open transition and layout settle before choosing a target.
		task.defer(function()
			local target = firstIn(panel)
			if target then
				GuiService.SelectedObject = target
			end
		end)
	end

	function focus.panelClosed(_self: any, panel: Instance)
		local current = GuiService.SelectedObject
		local previous = returnTo[panel]
		returnTo[panel] = nil
		if current == nil or not current:IsDescendantOf(panel) then
			return
		end
		if previous and previous.Parent ~= nil and previous.Visible then
			GuiService.SelectedObject = previous
		else
			GuiService.SelectedObject = nil
		end
	end

	-- Remember the last selected object per group.
	local function onSelectionChanged()
		local selected = GuiService.SelectedObject
		if selected == nil then
			return
		end
		for container, group in groups do
			if selected:IsDescendantOf(container) then
				group.last = selected
			end
		end
	end
	table.insert(connections, GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged))

	function focus.destroy(_self: any)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		table.clear(groups)
		table.clear(returnTo)
	end

	return focus
end

return Focus
