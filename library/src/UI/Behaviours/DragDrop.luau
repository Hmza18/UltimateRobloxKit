--!strict
-- UrkDraggable and UrkDropTarget. Pointer drags go through Runtime/DragService; drops fire
-- UrkUI.Dropped(payload, target, targetId). Gamepad carry (A to pick up, A on a target to drop)
-- is handled centrally by the DragService. A target highlights while a drag of its group hovers it.

local DragDrop = {}

DragDrop.tags = { "UrkDraggable", "UrkDropTarget" }

local function bindDraggable(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local object = instance :: GuiObject
	object.Active = true
	trove:Connect(object.InputBegan, function(input: InputObject)
		local payload = { group = values.DragGroup or "default", id = values.DragId, source = object, data = nil }
		context.drag:begin(object, payload, input)
	end)
end

local function bindDropTarget(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local object = instance :: GuiObject
	local group = values.DragGroup or "default"
	local function highlight(on: boolean)
		object:SetAttribute("UrkDropHover", if on then true else nil)
		local stroke = object:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = context.theme:color(if on then "focus" else "border")
		end
	end
	trove:Connect(object.MouseEnter, function()
		if context.drag:isDragging() then
			highlight(true)
		end
	end)
	trove:Connect(object.MouseLeave, function()
		highlight(false)
	end)
	trove:Connect(context.drag.Dropped, function(payload: any)
		if payload.group == group then
			highlight(false)
		end
	end)
end

function DragDrop.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkDraggable" then
		bindDraggable(context, instance, trove, values)
	else
		bindDropTarget(context, instance, trove, values)
	end
end

return DragDrop
