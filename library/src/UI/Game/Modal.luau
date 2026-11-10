--!strict
-- Modal dialog: a dim backdrop that swallows clicks, and a window with a title, body text, an
-- optional row of buttons and a content area. Opens with "ModalIn" over "BackdropIn" and closes
-- with "ModalOut" / "BackdropOut".
--   local modal = Modal.new({ title = "REBIRTH?", text = "You keep your pets and lose your coins.",
--       buttons = { { id = "yes", text = "REBIRTH", kind = "buy" }, { id = "no", text = "CANCEL", kind = "neutral" } },
--       parent = playerGui })
--   modal.Activated:Connect(function(id) if id == "yes" then requestRebirth() end end)
--   modal:open()
--
-- It closes on the X button, a click on the backdrop (closeOnBackdrop), Escape and gamepad B, and
-- after any button unless that button sets `keepOpen`. It starts hidden unless `visible = true`.
-- A PlayerGui parent gets a ScreenGui of its own. Put custom children in modal.Content.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Base = require("./Base")
local CartoonButton = require("./CartoonButton")
local Extra = require("./Extra")
local Kit = require("./Kit")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Button = { id: string, text: string?, kind: string?, icon: string?, keepOpen: boolean? }

export type Props = {
	title: string?,
	text: string?,
	buttons: { Button }?,
	headerPalette: string?, -- default "blue"
	width: number?, -- pixels at 1x, default 440
	height: number?, -- default 280
	closable: boolean?, -- X button, Escape and gamepad B (default true)
	closeOnBackdrop: boolean?, -- default true
	dim: number?, -- backdrop transparency, default 0.45
	style: string?,
	parent: Instance?,
	name: string?,
	visible: boolean?,
	action: string?,
	[string]: any,
}

local Modal = {}

local HEADER = 56
local BUTTON_ROW = 64

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: Frame = object.Instance
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = object.opened == true

	local window = Extra.frame(root, "Window", {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(props.width or 440, props.height or 280),
		zIndex = 2,
	})
	object.parts:Add(window)
	object.Window = window
	-- The window swallows clicks so they do not reach the backdrop behind it.
	window.Active = true
	local windowProps: Panel.SurfaceProps =
		{ surface = "window", radius = "xl", outline = "heavy", gloss = false, pattern = true, shadow = true }
	Panel.surface(object, window, windowProps)

	local bar = Extra.frame(window, "Header", { size = UDim2.new(1, 0, 0, HEADER), zIndex = 4 })
	local headerProps: Panel.SurfaceProps =
		{ palette = props.headerPalette or "blue", radius = "xl", outline = "heavy", gloss = true, shadow = false }
	local header = Panel.surface(object, bar, headerProps).content
	local closable = props.closable ~= false
	Extra.label(object, header, "Title", { text = props.title or "", role = "title", maxSize = 30 }, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, if closable then -112 else -24, 0.8, 0),
	})
	if closable then
		local close = CartoonButton.new({
			kind = "close",
			text = "X",
			style = props.style,
			size = UDim2.fromOffset(48, 48),
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, 8, 0, -8),
			parent = window,
		})
		close.Instance.ZIndex = 6
		close.Activated:Connect(function()
			object:close()
			Kit.runAction(object.props.action, close.Instance)
		end)
		object.parts:Add(close)
		object.CloseButton = close
	end

	local buttons: { Button } = props.buttons or {}
	local footer = if #buttons > 0 then BUTTON_ROW else 0
	local pad = Kit.spacing(style, "lg")
	local body = Extra.frame(window, "Content", {
		position = UDim2.fromOffset(pad, HEADER + pad),
		size = UDim2.new(1, -pad * 2, 1, -(HEADER + pad * 2 + footer)),
		zIndex = 3,
	})
	body:SetAttribute("UrkInternal", nil)
	object.parts:Add(body)
	object.Content = body
	if props.text and props.text ~= "" then
		Extra.label(object, body, "Text", {
			text = props.text,
			role = "label",
			color = Style.surface(style, "window").text,
			wrap = true,
			stroke = false,
		})
	end

	object.buttons = {}
	if #buttons > 0 then
		local row = Extra.frame(window, "Buttons", {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -pad),
			size = UDim2.new(1, -pad * 2, 0, BUTTON_ROW - pad / 2),
			zIndex = 3,
		})
		object.parts:Add(row)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, Kit.spacing(style, "md"))
		layout.Parent = row
		for index, spec in buttons do
			local button = CartoonButton.new({
				kind = spec.kind or "primary",
				text = spec.text or string.upper(spec.id),
				icon = spec.icon,
				style = props.style,
				layoutOrder = index,
				size = UDim2.new(1 / #buttons, -Kit.spacing(style, "md"), 1, 0),
				parent = row,
			})
			button.Activated:Connect(function()
				object.Activated:Fire(spec.id)
				if not spec.keepOpen then
					object:close()
				end
			end)
			object.parts:Add(button)
			table.insert(object.buttons, button)
		end
	end
end

local function gamepadActive(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1 or GuiService:IsTenFootInterface()
end

function Modal.new(props: Props)
	local copy = table.clone(props)
	local screen: ScreenGui? = nil
	if copy.parent then
		local parent, created = Kit.ensureScreen(copy.parent, "Modal_" .. (copy.name or "Modal"), 40)
		copy.parent = parent
		screen = created
	end
	local startOpen = copy.visible == true
	copy.visible = nil
	local object = Base.new({
		className = "Frame",
		name = "Modal",
		props = copy,
		build = build,
		setup = function(self: any)
			self.Opened = Signal.new()
			self.Closed = Signal.new()
			self.trove:Add(function()
				if self.backdrop then
					self.backdrop.finish()
					self.backdrop = nil
				end
				if self.Window then
					Extra.UI.stop(self.Window, false)
				end
				self.Opened:DisconnectAll()
				self.Closed:DisconnectAll()
			end)
			self.trove:Connect(UserInputService.InputBegan, function(input: InputObject)
				if not self.opened or self.props.closable == false then
					return
				end
				if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
					self:close()
				end
			end)
			if screen then
				self.trove:Add(screen)
			end
		end,
	})
	object.opened = false

	function object.isOpen(self: any): boolean
		return self.opened == true
	end

	function object.open(self: any)
		if self.destroyed or self.opened then
			return
		end
		self.opened = true
		local root: Frame = self.Instance
		root.Visible = true
		if self.backdrop then
			self.backdrop.finish()
		end
		self.backdrop = Extra.UI.backdrop(root, {
			transparency = self.props.dim or 0.45,
			zIndex = 1,
			onActivated = function()
				if self.props.closeOnBackdrop ~= false then
					self:close()
				end
			end,
		})
		Extra.UI.show(self.Window, "ModalIn")
		if gamepadActive() then
			local first = self.buttons[1] or self.CloseButton
			if first then
				GuiService.SelectedObject = first.Instance
			end
		end
		self.Opened:Fire()
	end

	function object.close(self: any)
		if self.destroyed or not self.opened then
			return
		end
		self.opened = false
		local root: Frame = self.Instance
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		if self.backdrop then
			self.backdrop.stop()
			self.backdrop = nil
		end
		Extra.UI.hide(self.Window, "ModalOut", {
			onDone = function()
				if not self.opened and not self.destroyed then
					root.Visible = false
				end
			end,
		})
		self.Closed:Fire()
	end

	if startOpen then
		object:open()
	end
	return object
end

return Modal
