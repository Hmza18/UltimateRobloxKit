--!strict
-- UrkTooltip (shared tooltip on hover / selection), UrkToastHost (where toasts go) and
-- UrkContextMenu (right-click, long-press or gamepad X opens a menu from the Items attribute).

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local TagSpec = require("../Core/TagSpec")

local Overlay = {}

Overlay.tags = { "UrkTooltip", "UrkToastHost", "UrkContextMenu" }

local function bindTooltip(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local function getText(): string?
		if values.Key then
			return context.localize:t(values.Key)
		end
		return values.Text
	end
	local options = { placement = values.Placement, delay = values.Delay }
	context.tooltip:attach(instance :: GuiObject, getText, options, trove)
end

local function bindToastHost(context: any, instance: Instance, trove: any, _values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	if instance:FindFirstChildOfClass("UIListLayout") == nil then
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = instance
		trove:Add(layout)
	end
	trove:Add(context.toasts:addHost(instance :: GuiObject))
end

local function bindContextMenu(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local object = instance :: GuiObject
	local function items(): { any }
		local list = {}
		for _, item in TagSpec.parseMenuItems(values.Items) do
			table.insert(list, {
				label = context.localize:t(item.label),
				action = item.action,
				separator = item.separator,
				disabled = item.action == nil and not item.separator,
			})
		end
		return list
	end
	local function openAt(position: Vector2?)
		if position then
			context.menu:open(items(), position, object)
		else
			context.menu:open(items(), object, object)
		end
	end
	trove:Connect(object.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			openAt(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	trove:Connect(object.TouchLongPress, function(positions: { Vector2 }, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			openAt(positions[1])
		end
	end)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonX and GuiService.SelectedObject == object then
			openAt(nil)
		end
	end)
end

function Overlay.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkTooltip" then
		bindTooltip(context, instance, trove, values)
	elseif tag == "UrkToastHost" then
		bindToastHost(context, instance, trove, values)
	else
		bindContextMenu(context, instance, trove, values)
	end
end

return Overlay
