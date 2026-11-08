--!strict
-- Toast notifications driven by Core/ToastQueue. Frames are pooled and reused; expiry uses one
-- task.delay for the earliest deadline instead of a per-frame check. Toasts go into the latest
-- UrkToastHost frame if there is one, otherwise into a top-right host created on first use.

local Create = require("./Create")
local IconBridge = require("./IconBridge")
local Motion = require("./Motion")
local ToastQueue = require("../Core/ToastQueue")

export type ToastInput = ToastQueue.ToastInput

local ToastService = {}

local WIDTH = 320
local KIND_ROLES: { [string]: string } = { info = "info", success = "success", warning = "warning", error = "danger" }

type View = {
	frame: Frame,
	accent: Frame,
	icon: ImageLabel,
	title: TextLabel,
	body: TextLabel,
	badge: TextLabel,
	close: TextButton,
	toastId: string?,
}

function ToastService.new(context: any)
	local service = {}
	local theme = context.theme
	local queue = ToastQueue.new({ maxVisible = context.config.maxToasts or 3 })
	local pool: { View } = {}
	local active: { [string]: View } = {}
	local hosts: { GuiObject } = {}
	local defaultHost: GuiObject? = nil
	local defaultGui: ScreenGui? = nil
	local timer: thread? = nil

	local function host(): GuiObject
		for index = #hosts, 1, -1 do
			local candidate = hosts[index]
			if candidate.Parent ~= nil then
				return candidate
			end
			table.remove(hosts, index)
		end
		if defaultHost == nil or defaultHost.Parent == nil then
			local gui = Create.screen("UrkToasts", theme:layer("toast"), context.playerGui)
			gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
			local frame = Create.new("Frame", {
				Name = "Host",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 16),
				Size = UDim2.new(0, WIDTH, 1, -32),
				BackgroundTransparency = 1,
				Parent = gui,
			})
			local layout = Create.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
			layout.Parent = frame
			defaultGui = gui
			defaultHost = frame
			return frame
		end
		return defaultHost :: GuiObject
	end

	local function skin(view: View, kind: string)
		local role = KIND_ROLES[kind] or "info"
		view.frame.BackgroundColor3 = theme:color("surface")
		view.accent.BackgroundColor3 = theme:color(role)
		view.icon.ImageColor3 = theme:color(role)
		view.title.TextColor3 = theme:color("text")
		view.body.TextColor3 = theme:color("textMuted")
		view.badge.BackgroundColor3 = theme:color(role)
		view.badge.TextColor3 = theme:color("on" .. string.upper(string.sub(role, 1, 1)) .. string.sub(role, 2))
		view.close.TextColor3 = theme:color("textMuted")
		local stroke = view.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = theme:color("border")
		end
	end

	local function makeView(): View
		local frame = Create.new("Frame", {
			Name = "Toast",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,
			Visible = false,
		})
		Create.corner(theme:radius("md")).Parent = frame
		Create.stroke(theme:color("border"), 1).Parent = frame
		Create.padding(10, 14).Parent = frame
		local accent = Create.new("Frame", {
			Name = "Accent",
			Size = UDim2.new(0, 4, 1, 0),
			Position = UDim2.fromOffset(-14, 0),
			BorderSizePixel = 0,
			Parent = frame,
		})
		local icon = Create.new("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Parent = frame,
		})
		local title = Create.new("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -60, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			FontFace = theme:font("label"),
			TextSize = theme:textSize("body"),
			Parent = frame,
		})
		local body = Create.new("TextLabel", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -60, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			FontFace = theme:font("body"),
			TextSize = theme:textSize("caption"),
			Parent = frame,
		})
		local badge = Create.new("TextLabel", {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -24, 0, 0),
			Size = UDim2.fromOffset(28, 20),
			BorderSizePixel = 0,
			FontFace = theme:font("title"),
			TextSize = theme:textSize("caption"),
			Visible = false,
			Parent = frame,
		})
		Create.corner(theme:radius("pill")).Parent = badge
		local close = Create.new("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Text = "X",
			FontFace = theme:font("title"),
			TextSize = theme:textSize("caption"),
			Parent = frame,
		})
		local view: View = {
			frame = frame,
			accent = accent,
			icon = icon,
			title = title,
			body = body,
			badge = badge,
			close = close,
			toastId = nil,
		}
		close.Activated:Connect(function()
			if view.toastId then
				service:dismiss(view.toastId)
			end
		end)
		return view
	end

	local function acquire(): View
		local view = table.remove(pool)
		if view then
			return view
		end
		return makeView()
	end

	local function release(view: View)
		view.toastId = nil
		view.frame.Visible = false
		view.frame.Parent = nil
		table.insert(pool, view)
	end

	local function fill(view: View, toast: ToastQueue.Toast)
		local hasTitle = toast.title ~= nil and toast.title ~= ""
		view.title.Text = if hasTitle then toast.title :: string else toast.text
		view.title.Visible = true
		view.body.Text = if hasTitle then toast.text else ""
		view.body.Visible = hasTitle
		view.body.Position = UDim2.fromOffset(30, if hasTitle then view.title.TextSize + 6 else 0)
		view.badge.Visible = toast.count > 1
		view.badge.Text = "x" .. tostring(toast.count)
		view.icon.Visible = IconBridge.apply(view.icon, toast.icon or toast.kind)
		view.frame.LayoutOrder = toast.order
		skin(view, toast.kind)
	end

	local schedule: () -> ()

	local function applyChange(change: ToastQueue.Change)
		for _, toast in change.shown do
			local view = acquire()
			view.toastId = toast.id
			active[toast.id] = view
			fill(view, toast)
			view.frame.Parent = host()
			Motion.show(view.frame, "slideLeft")
		end
		for _, toast in change.updated do
			local view = active[toast.id]
			if view then
				fill(view, toast)
				Motion.pop(view.frame, 0.06)
			end
		end
		for _, toast in change.hidden do
			local view = active[toast.id]
			if view then
				active[toast.id] = nil
				view.toastId = nil
				Motion.hide(view.frame, "slideLeft", function()
					if view.toastId == nil then
						release(view)
					end
				end)
			end
		end
		schedule()
	end

	schedule = function()
		if timer then
			pcall(task.cancel, timer)
			timer = nil
		end
		local deadline = queue:nextDeadline()
		if deadline == nil then
			return
		end
		timer = task.delay(math.max(0, deadline - os.clock()), function()
			timer = nil
			applyChange(queue:update(os.clock()))
		end)
	end

	-- Shows a toast; returns its id. Duplicates of a visible toast bump its counter instead.
	function service.show(_self: any, input: ToastInput | string): string
		local toastInput: ToastInput = if type(input) == "string" then { text = input } else input
		local id, change = queue:push(toastInput, os.clock())
		applyChange(change)
		return id
	end

	function service.dismiss(_self: any, id: string)
		applyChange(queue:dismiss(id, os.clock()))
	end

	function service.clear(_self: any)
		applyChange(queue:clear())
	end

	-- Called by the UrkToastHost behaviour.
	function service.addHost(_self: any, frame: GuiObject): () -> ()
		table.insert(hosts, frame)
		local function remove()
			local index = table.find(hosts, frame)
			if index then
				table.remove(hosts, index)
			end
		end
		return remove
	end

	function service.destroy(_self: any)
		if timer then
			pcall(task.cancel, timer)
			timer = nil
		end
		for _, view in active do
			view.frame:Destroy()
		end
		for _, view in pool do
			view.frame:Destroy()
		end
		table.clear(active)
		table.clear(pool)
		if defaultGui then
			defaultGui:Destroy()
			defaultGui = nil
		end
	end

	return service
end

return ToastService
