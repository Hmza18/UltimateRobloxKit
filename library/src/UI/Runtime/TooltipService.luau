--!strict
-- One shared, pooled tooltip for the whole UI. Shows after a short delay on mouse hover or gamepad
-- selection, follows the cursor while hovering, and is clamped inside the screen with
-- Core/Layout.place (flipping above or beside the anchor near edges). Mouse tracking is connected
-- only while the tooltip is visible.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Create = require("./Create")
local Layout = require("../Core/Layout")

export type Options = {
	placement: string?, -- "below" (default), "above", "left", "right"
	delay: number?, -- seconds before showing (default 0.35)
	followCursor: boolean?, -- default true for mouse hover
}

local TooltipService = {}

local MAX_WIDTH = 280

function TooltipService.new(context: any)
	local service = {}
	local theme = context.theme
	local gui = Create.screen("UrkTooltip", theme:layer("tooltip"), context.playerGui)
	local frame = Create.new("Frame", {
		Name = "Tooltip",
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BorderSizePixel = 0,
		Parent = gui,
	})
	local corner = Create.corner(theme:radius("sm"))
	corner.Parent = frame
	local stroke = Create.stroke(theme:color("border"), 1)
	stroke.Parent = frame
	local padding = Create.padding(6, 10)
	padding.Parent = frame
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	constraint.Parent = frame
	local label = Create.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local labelConstraint = Instance.new("UISizeConstraint")
	labelConstraint.MaxSize = Vector2.new(MAX_WIDTH - 20, math.huge)
	labelConstraint.Parent = label

	local stopWatching = theme:watch(function(current: any)
		frame.BackgroundColor3 = current:color("surfaceAlt")
		stroke.Color = current:color("border")
		label.TextColor3 = current:color("text")
		label.TextSize = current:textSize("caption")
		label.FontFace = current:font("body")
	end)

	local currentAnchor: GuiObject? = nil
	local currentOptions: Options = {}
	local pending: thread? = nil
	local mouseConnection: RBXScriptConnection? = nil
	local cursor: Vector2? = nil

	local function reposition()
		local anchor = currentAnchor
		if anchor == nil then
			return
		end
		local origin = gui.AbsolutePosition
		local bounds = { x = 0, y = 0, w = gui.AbsoluteSize.X, h = gui.AbsoluteSize.Y }
		local rect: Layout.Rect
		local gap = 8
		if cursor ~= nil then
			local point = cursor :: Vector2
			rect = { x = point.X - origin.X, y = point.Y - origin.Y, w = 0, h = 0 }
			gap = 18
		else
			local position = anchor.AbsolutePosition - origin
			rect = { x = position.X, y = position.Y, w = anchor.AbsoluteSize.X, h = anchor.AbsoluteSize.Y }
		end
		local size = { x = frame.AbsoluteSize.X, y = frame.AbsoluteSize.Y }
		local placed = Layout.place(rect, size, bounds, { gap = gap, prefer = currentOptions.placement })
		frame.Position = UDim2.fromOffset(placed.x, placed.y)
	end

	local function stopMouse()
		if mouseConnection then
			mouseConnection:Disconnect()
			mouseConnection = nil
		end
	end

	-- Hides the tooltip; with `anchor`, only if it currently belongs to that anchor.
	function service.hide(_self: any, anchor: GuiObject?)
		if anchor ~= nil and anchor ~= currentAnchor then
			return
		end
		if pending then
			pcall(task.cancel, pending)
			pending = nil
		end
		stopMouse()
		currentAnchor = nil
		cursor = nil
		frame.Visible = false
	end

	-- Shows `text` next to `anchor` after the delay. `byMouse` enables cursor following.
	function service.show(self: any, anchor: GuiObject, text: string, options: Options?, byMouse: boolean?)
		self:hide()
		if text == "" then
			return
		end
		currentAnchor = anchor
		currentOptions = options or {}
		local delaySeconds = currentOptions.delay or 0.35
		pending = task.delay(delaySeconds, function()
			pending = nil
			if currentAnchor ~= anchor or anchor.Parent == nil then
				return
			end
			label.Text = text
			if byMouse and currentOptions.followCursor ~= false then
				-- GetMouseLocation includes the top bar inset; GUI AbsolutePosition and
				-- InputObject.Position do not, so convert once here.
				local inset = GuiService:GetGuiInset()
				cursor = UserInputService:GetMouseLocation() - inset
				mouseConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseMovement then
						cursor = Vector2.new(input.Position.X, input.Position.Y)
						reposition()
					end
				end)
			end
			-- Position after the automatic size has been computed for the new text.
			task.defer(function()
				if currentAnchor == anchor then
					reposition()
					frame.Visible = true
				end
			end)
		end)
	end

	-- Wires hover and gamepad selection on `object`. `getText` is read each time it shows, so
	-- localised or changing text stays current. Connections are owned by `trove`.
	function service.attach(self: any, object: GuiObject, getText: () -> string?, options: Options?, trove: any)
		local function open(byMouse: boolean)
			local text = getText()
			if text and text ~= "" then
				self:show(object, text, options, byMouse)
			end
		end
		trove:Connect(object.MouseEnter, function()
			open(true)
		end)
		trove:Connect(object.MouseLeave, function()
			self:hide(object)
		end)
		trove:Connect(object.SelectionGained, function()
			open(false)
		end)
		trove:Connect(object.SelectionLost, function()
			self:hide(object)
		end)
		trove:Add(function()
			self:hide(object)
		end)
	end

	function service.isVisible(_self: any): boolean
		return frame.Visible
	end

	function service.destroy(self: any)
		self:hide()
		stopWatching()
		gui:Destroy()
	end

	return service
end

return TooltipService
