--!strict
-- Drag and drop for UrkDraggable / UrkDropTarget and the inventory grid.
--
-- * Pointer drag (mouse or touch): starts after the pointer moves a few pixels (so clicks still
--   work), shows a ghost copy that follows the pointer, and on release finds the drop target.
--   Input connections exist only while a press or drag is in progress.
-- * Gamepad "carry": press A on a draggable to pick it up, move the selection, press A on a
--   target to drop, or B to cancel.
-- The service only reports drops (Dropped signal and callbacks). It never moves game items:
-- the game turns a drop into a validated server request.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Create = require("./Create")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Payload = { group: string, id: string?, source: GuiObject, data: any }

export type Options = {
	threshold: number?, -- pixels before a press becomes a drag (default 6)
	ghost: boolean?, -- show a ghost copy (default true)
	-- Custom target lookup; return the target instance and its id. Defaults to UrkDropTarget tags.
	resolve: ((position: Vector2) -> (Instance?, string?))?,
	onDrop: ((target: Instance?, targetId: string?, position: Vector2) -> ())?,
	onCancel: (() -> ())?,
}

local DragService = {}

local DROP_TAG = "UrkDropTarget"
local DRAG_TAG = "UrkDraggable"

local function isPointerPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function DragService.new(context: any)
	local service = {}
	service.Dropped = Signal.new()
	service.Started = Signal.new()
	service.Cancelled = Signal.new()

	local gui = Create.screen("UrkDrag", context.theme:layer("drag"), context.playerGui)
	local session: any = nil
	local carried: Payload? = nil
	local carriedOptions: Options? = nil

	-- Default target lookup: the top-most UrkDropTarget (or ancestor of one) under the point with a
	-- matching DragGroup.
	local function findTarget(position: Vector2, group: string, source: Instance): (Instance?, string?)
		local hits = context.playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
		for _, hit in hits do
			local current: Instance? = hit
			while current ~= nil and current ~= context.playerGui do
				if current:HasTag(DROP_TAG) and current ~= source then
					local targetGroup = current:GetAttribute("DragGroup") or "default"
					if targetGroup == group then
						local id = current:GetAttribute("DropId")
						return current, if type(id) == "string" then id else nil
					end
				end
				current = current.Parent
			end
		end
		return nil, nil
	end

	local function finish(dropped: boolean, position: Vector2?)
		local active = session
		if active == nil then
			return
		end
		session = nil
		active.trove:Destroy()
		if not active.started then
			return
		end
		active.payload.source:SetAttribute("UrkDragging", nil)
		if not dropped or position == nil then
			if active.options.onCancel then
				active.options.onCancel()
			end
			service.Cancelled:Fire(active.payload)
			return
		end
		local target: Instance?, targetId: string?
		if active.options.resolve then
			target, targetId = active.options.resolve(position)
		else
			target, targetId = findTarget(position, active.payload.group, active.payload.source)
		end
		if active.options.onDrop then
			active.options.onDrop(target, targetId, position)
		end
		service.Dropped:Fire(active.payload, target, targetId)
	end

	local function startGhost(active: any, position: Vector2)
		active.started = true
		local source: GuiObject = active.payload.source
		source:SetAttribute("UrkDragging", true)
		service.Started:Fire(active.payload)
		if active.options.ghost == false then
			return
		end
		local ghost = source:Clone()
		Create.stripTags(ghost)
		for _, descendant in ghost:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then
				descendant:Destroy()
			end
		end
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Size = UDim2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
		ghost.Position = UDim2.fromOffset(position.X - gui.AbsolutePosition.X, position.Y - gui.AbsolutePosition.Y)
		ghost.Rotation = 4
		ghost.Parent = gui
		active.ghost = ghost
		active.trove:Add(ghost)
	end

	-- Starts tracking a press on `source`. Call from InputBegan with the pressing InputObject.
	function service.begin(_self: any, source: GuiObject, payload: Payload, input: InputObject, options: Options?)
		if session ~= nil or not isPointerPress(input) then
			return
		end
		local opts: Options = options or {}
		payload.source = payload.source or source
		local trove = Trove.new()
		local origin = Vector2.new(input.Position.X, input.Position.Y)
		local active = { payload = payload, options = opts, trove = trove, started = false, ghost = nil }
		session = active
		local threshold = opts.threshold or 6
		local isTouch = input.UserInputType == Enum.UserInputType.Touch

		trove:Connect(UserInputService.InputChanged, function(changed: InputObject)
			local isMouseMove = changed.UserInputType == Enum.UserInputType.MouseMovement
			local matches = if isTouch then changed == input else isMouseMove
			if not matches then
				return
			end
			local position = Vector2.new(changed.Position.X, changed.Position.Y)
			if not active.started and (position - origin).Magnitude >= threshold then
				startGhost(active, position)
			end
			if active.ghost then
				local offset = position - gui.AbsolutePosition
				active.ghost.Position = UDim2.fromOffset(offset.X, offset.Y)
			end
		end)
		trove:Connect(UserInputService.InputEnded, function(ended: InputObject)
			local matches = if isTouch then ended == input else ended.UserInputType == Enum.UserInputType.MouseButton1
			if matches then
				finish(true, Vector2.new(ended.Position.X, ended.Position.Y))
			end
		end)
	end

	function service.isDragging(_self: any): boolean
		return session ~= nil and session.started == true
	end

	function service.cancel(_self: any)
		finish(false, nil)
		if carried then
			local payload = carried
			carried = nil
			payload.source:SetAttribute("UrkCarried", nil)
			if carriedOptions and carriedOptions.onCancel then
				carriedOptions.onCancel()
			end
			carriedOptions = nil
			service.Cancelled:Fire(payload)
		end
	end

	-- Gamepad carry: picks up `payload`; the next dropOn delivers it.
	function service.pickUp(self: any, payload: Payload, options: Options?)
		self:cancel()
		carried = payload
		carriedOptions = options
		payload.source:SetAttribute("UrkCarried", true)
		service.Started:Fire(payload)
	end

	function service.carrying(_self: any): Payload?
		return carried
	end

	function service.dropOn(_self: any, target: Instance?, targetId: string?)
		local payload = carried
		if payload == nil then
			return
		end
		local options = carriedOptions
		carried = nil
		carriedOptions = nil
		payload.source:SetAttribute("UrkCarried", nil)
		local position = Vector2.new(0, 0)
		if target and target:IsA("GuiObject") then
			position = target.AbsolutePosition + target.AbsoluteSize / 2
		end
		if options and options.onDrop then
			options.onDrop(target, targetId, position)
		end
		service.Dropped:Fire(payload, target, targetId)
	end

	-- Gamepad carry for tagged elements: A picks up the selected UrkDraggable, A on a matching
	-- UrkDropTarget drops it, A on the carried element or B cancels.
	local function onGamepadInput(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			if carried then
				service:cancel()
			end
			return
		end
		if input.KeyCode ~= Enum.KeyCode.ButtonA then
			return
		end
		local selected = GuiService.SelectedObject
		if selected == nil then
			return
		end
		local current = carried
		-- Components such as the inventory grid manage their own carries; only handle tagged ones.
		if current and not current.source:HasTag(DRAG_TAG) then
			return
		end
		if current then
			if selected == current.source then
				service:cancel()
			elseif selected:HasTag(DROP_TAG) and (selected:GetAttribute("DragGroup") or "default") == current.group then
				local id = selected:GetAttribute("DropId")
				service:dropOn(selected, if type(id) == "string" then id else nil)
			end
		elseif selected:HasTag(DRAG_TAG) then
			local id = selected:GetAttribute("DragId")
			local group = selected:GetAttribute("DragGroup") or "default"
			local dragId = if type(id) == "string" then id else nil
			service:pickUp({ group = group, id = dragId, source = selected, data = nil })
		end
	end
	local gamepadConnection = UserInputService.InputBegan:Connect(onGamepadInput)

	function service.destroy(self: any)
		gamepadConnection:Disconnect()
		self:cancel()
		service.Dropped:DisconnectAll()
		service.Started:DisconnectAll()
		service.Cancelled:DisconnectAll()
		gui:Destroy()
	end

	return service
end

return DragService
