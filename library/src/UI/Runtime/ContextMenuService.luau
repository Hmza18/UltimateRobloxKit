--!strict
-- One shared context menu. Items are { label, action = "ActionSpec"?, callback = fn?, disabled?,
-- separator? }. Opens at a screen point or next to an anchor, clamps inside the screen, closes on
-- an outside click, Back (gamepad B / Escape, handled by Panels) or after an item runs.
-- Item buttons are pooled.

local GuiService = game:GetService("GuiService")

local Create = require("./Create")
local Layout = require("../Core/Layout")

export type Item = { label: string, action: string?, callback: (() -> ())?, disabled: boolean?, separator: boolean? }

local ContextMenuService = {}

local ITEM_HEIGHT = 36
local WIDTH = 200

function ContextMenuService.new(context: any)
	local service = {}
	local theme = context.theme
	local gui = Create.screen("UrkContextMenu", theme:layer("menu"), context.playerGui)
	gui.Enabled = false
	local catcher = Create.new("TextButton", {
		Name = "OutsideClick",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local frame = Create.new("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	Create.corner(theme:radius("md")).Parent = frame
	local stroke = Create.stroke(theme:color("border"), 1)
	stroke.Parent = frame
	Create.padding(4).Parent = frame
	Create.list(Enum.FillDirection.Vertical, 2).Parent = frame

	local pool: { TextButton } = {}
	local used: { GuiObject } = {}
	local itemConnections: { RBXScriptConnection } = {}
	local source: Instance? = nil
	local open = false

	local function skinButton(button: TextButton, disabled: boolean?)
		button.BackgroundColor3 = theme:color("surfaceAlt")
		button.TextColor3 = theme:color(if disabled then "textMuted" else "text")
		button.FontFace = theme:font("label")
		button.TextSize = theme:textSize("body")
	end

	local stopWatching = theme:watch(function(current: any)
		frame.BackgroundColor3 = current:color("surface")
		stroke.Color = current:color("border")
		for _, item in used do
			if item:IsA("TextButton") then
				skinButton(item, item:GetAttribute("Disabled") == true)
			end
		end
	end)

	local function clearItems()
		for _, connection in itemConnections do
			connection:Disconnect()
		end
		table.clear(itemConnections)
		for _, item in used do
			if item:IsA("TextButton") then
				item.Visible = false
				item.Parent = nil
				table.insert(pool, item)
			else
				item:Destroy()
			end
		end
		table.clear(used)
	end

	function service.isOpen(_self: any): boolean
		return open
	end

	function service.close(_self: any)
		if not open then
			return
		end
		open = false
		gui.Enabled = false
		clearItems()
		local previous = source
		source = nil
		if previous and previous:IsA("GuiObject") and context.focus and context.focus:isGamepad() then
			GuiService.SelectedObject = previous
		end
	end

	local function makeButton(): TextButton
		local button = table.remove(pool)
		if button then
			return button
		end
		local created = Create.new("TextButton", {
			Size = UDim2.new(1, 0, 0, ITEM_HEIGHT),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
		Create.corner(theme:radius("sm")).Parent = created
		Create.padding(0, 12).Parent = created
		return created
	end

	-- Opens the menu. `at` is a point in GUI space or an anchor object to open beside.
	function service.open(self: any, items: { Item }, at: Vector2 | GuiObject, from: Instance?)
		self:close()
		source = from
		local firstButton: TextButton? = nil
		for index, item in items do
			if item.separator then
				local line = Create.new("Frame", {
					Name = "Separator",
					Size = UDim2.new(1, 0, 0, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = theme:color("border"),
					LayoutOrder = index,
					ZIndex = 3,
					Parent = frame,
				})
				table.insert(used, line)
			else
				local button = makeButton()
				button.Name = "Item" .. index
				button.Text = item.label
				button.LayoutOrder = index
				button.Visible = true
				button.Active = not item.disabled
				button.Selectable = not item.disabled
				button:SetAttribute("Disabled", item.disabled == true)
				skinButton(button, item.disabled)
				local connection = button.Activated:Connect(function()
					if item.disabled then
						return
					end
					local origin = source
					self:close()
					if item.callback then
						task.spawn(item.callback)
					elseif item.action then
						context.actions:run(item.action, origin)
					end
				end)
				table.insert(itemConnections, connection)
				button.Parent = frame
				table.insert(used, button)
				if firstButton == nil and not item.disabled then
					firstButton = button
				end
			end
		end
		open = true
		gui.Enabled = true
		task.defer(function()
			if not open then
				return
			end
			local origin = gui.AbsolutePosition
			local bounds = { x = 0, y = 0, w = gui.AbsoluteSize.X, h = gui.AbsoluteSize.Y }
			local rect: Layout.Rect
			if typeof(at) == "Vector2" then
				local point = at :: Vector2
				rect = { x = point.X - origin.X, y = point.Y - origin.Y, w = 0, h = 0 }
			else
				local anchor = at :: GuiObject
				local position = anchor.AbsolutePosition - origin
				rect = { x = position.X, y = position.Y, w = anchor.AbsoluteSize.X, h = anchor.AbsoluteSize.Y }
			end
			local size = { x = frame.AbsoluteSize.X, y = frame.AbsoluteSize.Y }
			local placed = Layout.place(rect, size, bounds, { gap = 4, prefer = "right" })
			frame.Position = UDim2.fromOffset(placed.x, placed.y)
			if firstButton and context.focus and context.focus:isGamepad() then
				GuiService.SelectedObject = firstButton
			end
		end)
	end

	catcher.Activated:Connect(function()
		service:close()
	end)

	function service.destroy(self: any)
		self:close()
		stopWatching()
		gui:Destroy()
	end

	return service
end

return ContextMenuService
