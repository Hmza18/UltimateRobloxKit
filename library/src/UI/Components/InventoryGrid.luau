--!strict
-- Inventory grid: slot views, selection, tooltips and drag-and-drop between slots.
--
-- The grid never changes the inventory. A drop is resolved by Core/SlotLogic into an intent
-- ({ kind = "move" | "swap" | "merge", from, to, amount }) and handed to onIntent; the game sends
-- it to the server, and when the authoritative inventory changes it calls grid:setSlots(slots).
-- Rejected drops (locked slot, wrong category, full stack) shake the target and call onReject.
--
-- Mouse/touch: drag a slot onto another. Gamepad: A picks up the selected slot, A on another slot
-- drops it there, A on the same slot or B cancels. The grid is a UrkNav focus group.

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local IconBridge = require("../Runtime/IconBridge")
local Motion = require("../Runtime/Motion")
local SlotLogic = require("../Core/SlotLogic")
local Trove = require("../../Util/Trove")

export type Props = {
	slots: { any }, -- SlotLogic.Slot plus optional display fields: icon, name, rarity
	columns: number?, -- default 5
	cellSize: number?, -- pixels, default 72
	gap: number?, -- pixels, default 6
	group: string?, -- drag group, default "inventory"
	dropOptions: SlotLogic.DropOptions?,
	onIntent: (intent: SlotLogic.Intent) -> (),
	onReject: ((intent: SlotLogic.Intent) -> ())?,
	onSelect: ((index: number, slot: any) -> ())?,
	tooltip: ((slot: any, index: number) -> string?)?,
	renderSlot: ((button: TextButton, slot: any, index: number) -> ())?,
	size: UDim2?,
	parent: Instance?,
}

local InventoryGrid = {}

function InventoryGrid.new(props: Props)
	local context = Context.get()
	local theme = context.theme
	assert(type(props.onIntent) == "function", "InventoryGrid needs onIntent")
	local columns = math.max(1, math.floor(props.columns or 5))
	local cell = props.cellSize or 72
	local gap = props.gap or 6
	local group = props.group or "inventory"
	local slots: { any } = props.slots or {}
	local selectedIndex: number? = nil

	local width = columns * cell + (columns - 1) * gap
	local root = Create.new("ScrollingFrame", {
		Name = "InventoryGrid",
		Size = props.size or UDim2.new(0, width + 12, 0, cell * 4 + gap * 3),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Tags = { "UrkNav" },
	})
	Create.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell, cell),
		CellPadding = UDim2.fromOffset(gap, gap),
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	local buttons: { TextButton } = {}
	local troves: { any } = {}

	local function paintSelection()
		for index, button in buttons do
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				local isSelected = index == selectedIndex
				local carried = context.drag:carrying()
				local isCarried = carried ~= nil and carried.source == button
				stroke.Color = theme:color(if isSelected or isCarried then "focus" else "border")
				stroke.Thickness = if isSelected or isCarried then 3 else 1
			end
		end
	end

	local function render(index: number)
		local button = buttons[index]
		local slot = slots[index] or {}
		local icon = button:FindFirstChild("Icon") :: ImageLabel
		local count = button:FindFirstChild("Count") :: TextLabel
		local hasItem = slot.itemId ~= nil and (slot.count or 1) > 0
		icon.Visible = hasItem and IconBridge.apply(icon, slot.icon or slot.itemId)
		count.Visible = hasItem and (slot.count or 1) > 1
		count.Text = tostring(slot.count or "")
		button.BackgroundColor3 = theme:color(if slot.locked then "background" else "surfaceAlt")
		button.BackgroundTransparency = if slot.locked then 0.5 else 0
		if props.renderSlot then
			props.renderSlot(button, slot, index)
		end
	end

	local function selectSlot(index: number?)
		selectedIndex = index
		paintSelection()
		if index and props.onSelect then
			props.onSelect(index, slots[index])
		end
	end

	local function resolve(from: number, to: number)
		local intent = SlotLogic.resolveDrop(slots, from, to, props.dropOptions)
		if intent.kind == "reject" then
			local target = buttons[to]
			if target then
				Motion.shake(target, 5, 0.25)
			end
			if props.onReject then
				props.onReject(intent)
			end
			return
		end
		props.onIntent(intent)
	end

	local function slotAt(position: Vector2): (Instance?, string?)
		local rects = {}
		for index, button in buttons do
			local at = button.AbsolutePosition
			local size = button.AbsoluteSize
			rects[index] = { x = at.X, y = at.Y, w = size.X, h = size.Y }
		end
		local index = SlotLogic.hitTest({ x = position.X, y = position.Y }, rects)
		if index == nil then
			return nil, nil
		end
		return buttons[index], tostring(index)
	end

	local function payloadFor(index: number): any
		return { group = group, id = tostring(index), source = buttons[index], data = index }
	end

	local function dropHandler(from: number)
		return function(_target: Instance?, targetId: string?)
			paintSelection()
			local to = if targetId then tonumber(targetId) else nil
			if to then
				resolve(from, to)
			end
		end
	end

	local function makeButton(index: number): TextButton
		local button = Create.new("TextButton", {
			Name = "Slot" .. index,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Selectable = true,
		})
		button:SetAttribute("SlotIndex", index)
		Create.corner(theme:radius("md")).Parent = button
		Create.stroke(theme:color("border"), 1).Parent = button
		Create.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Visible = false,
			Parent = button,
		})
		Create.new("TextLabel", {
			Name = "Count",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.fromOffset(40, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = theme:color("text"),
			TextStrokeTransparency = 0.4,
			FontFace = theme:font("title"),
			TextSize = theme:textSize("caption"),
			Visible = false,
			Parent = button,
		})

		local trove = Trove.new()
		trove:Connect(button.InputBegan, function(input: InputObject)
			local slot = slots[index]
			if slot == nil or slot.itemId == nil or slot.locked then
				return
			end
			context.drag:begin(button, payloadFor(index), input, { resolve = slotAt, onDrop = dropHandler(index) })
		end)
		trove:Connect(button.Activated, function()
			if not context.focus:isGamepad() then
				selectSlot(index)
				return
			end
			local carried = context.drag:carrying()
			if carried and carried.group == group then
				if carried.source == button then
					context.drag:cancel()
				else
					context.drag:dropOn(button, tostring(index))
				end
				paintSelection()
				return
			end
			local slot = slots[index]
			if slot and slot.itemId and not slot.locked then
				context.drag:pickUp(payloadFor(index), { onDrop = dropHandler(index), onCancel = paintSelection })
				paintSelection()
			end
		end)
		trove:Connect(button.SelectionGained, function()
			selectSlot(index)
		end)
		if props.tooltip then
			local tooltip = props.tooltip
			local function getText(): string?
				local slot = slots[index]
				if slot == nil or slot.itemId == nil then
					return nil
				end
				return tooltip(slot, index)
			end
			context.tooltip:attach(button, getText, nil, trove)
		end
		trove:Add(button)
		troves[index] = trove
		button.Parent = root
		return button
	end

	local function sync()
		for index = 1, #slots do
			if buttons[index] == nil then
				buttons[index] = makeButton(index)
			end
			render(index)
		end
		for index = #buttons, #slots + 1, -1 do
			troves[index]:Destroy()
			troves[index] = nil
			buttons[index] = nil
		end
		if selectedIndex and selectedIndex > #slots then
			selectedIndex = nil
		end
		paintSelection()
	end

	local stopWatching = theme:watch(function()
		for index in buttons do
			render(index)
		end
		paintSelection()
	end)
	sync()
	if props.parent then
		root.Parent = props.parent
	end

	local handle = {}
	handle.Instance = root

	-- Replaces the displayed slots with the authoritative inventory.
	function handle.setSlots(_self: any, newSlots: { any })
		slots = newSlots
		sync()
	end

	function handle.select(_self: any, index: number?)
		selectSlot(index)
	end

	function handle.selected(_self: any): number?
		return selectedIndex
	end

	-- Moves the selection with SlotLogic grid maths (for custom key bindings).
	function handle.move(_self: any, direction: string)
		local nextIndex = SlotLogic.moveSelection(selectedIndex or 1, direction, columns, #slots)
		selectSlot(nextIndex)
	end

	function handle.Destroy(_self: any)
		stopWatching()
		for _, trove in troves do
			trove:Destroy()
		end
		root:Destroy()
	end

	return handle
end

return InventoryGrid
