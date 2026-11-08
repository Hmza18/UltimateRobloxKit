--!strict
-- Confirm / alert dialogs on the modal layer. The result arrives through a callback, through the
-- handle's Result signal, or by calling handle:wait() (yields until answered; returns at once if
-- it already was). Back (gamepad B / Escape) or the backdrop count as cancel.
--   local handle = Dialog.confirm({ title = "Sell sword?", message = "You get 40 coins." })
--   if handle:wait() then ... end

local Button = require("./Button")
local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local Signal = require("../../Util/Signal")

export type Props = {
	title: string,
	message: string?,
	confirmText: string?,
	cancelText: string?, -- nil with alert = true hides the cancel button
	danger: boolean?, -- red confirm button
	alert: boolean?, -- only one button
	onResult: ((confirmed: boolean) -> ())?,
}

local Dialog = {}

local counter = 0

function Dialog.confirm(props: Props)
	local context = Context.get()
	local theme = context.theme
	counter += 1
	local id = "UrkDialog" .. tostring(counter)
	local gui = Create.screen(id, theme:layer("modal") + 5, context.playerGui)
	local frame = Create.new("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Visible = false,
		Tags = { "UrkTheme" },
		Attributes = { Role = "surface", Radius = "lg", StrokeRole = "border" },
	})
	Create.stroke(theme:color("border"), 1).Parent = frame
	Create.padding(20).Parent = frame
	Create.list(Enum.FillDirection.Vertical, 12).Parent = frame
	Create.new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = props.title,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Tags = { "UrkTheme" },
		Attributes = { TextRole = "text", TextSize = "title" },
		Parent = frame,
	})
	if props.message then
		Create.new("TextLabel", {
			Name = "Message",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = props.message,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			Tags = { "UrkTheme" },
			Attributes = { TextRole = "textMuted", TextSize = "body" },
			Parent = frame,
		})
	end
	local row = Create.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 3,
		Parent = frame,
	})
	Create.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right).Parent = row

	local handle = {}
	handle.Result = Signal.new()
	handle.Instance = frame
	local answered = false
	local result = false

	local function finish(confirmed: boolean)
		if answered then
			return
		end
		answered = true
		result = confirmed
		context.panels:close(id)
		if props.onResult then
			task.spawn(props.onResult, confirmed)
		end
		handle.Result:Fire(confirmed)
		-- Leave time for the close transition, then clean up.
		task.delay(0.5, function()
			gui:Destroy()
		end)
	end

	if not props.alert then
		Button.new({
			text = props.cancelText or context.localize:t("Cancel"),
			variant = "secondary",
			layoutOrder = 1,
			parent = row,
			onClick = function()
				finish(false)
			end,
		})
	end
	Button.new({
		text = props.confirmText or context.localize:t("OK"),
		variant = if props.danger then "danger" else "primary",
		layoutOrder = 2,
		parent = row,
		onClick = function()
			finish(true)
		end,
	})

	frame.Parent = gui
	local def = { modal = true, dismissible = true }
	local unregister = context.panels:registerInstance(id, frame, def, { transition = "pop" })
	local closedConnection = context.panels.Closed:Connect(function(closedId: string)
		if closedId == id then
			finish(false)
		end
	end)
	gui.Destroying:Connect(function()
		closedConnection:Disconnect()
		unregister()
		handle.Result:DisconnectAll()
	end)
	context.panels:open(id)

	-- Yields until answered. Safe to call after the answer: returns the stored result.
	function handle.wait(_self: any): boolean
		if answered then
			return result
		end
		local confirmed = handle.Result:Wait()
		return confirmed == true
	end

	function handle.close(_self: any, confirmed: boolean?)
		finish(confirmed == true)
	end

	function handle.isAnswered(_self: any): boolean
		return answered
	end

	return handle
end

-- A one-button notice. Same handle as confirm.
function Dialog.alert(props: Props)
	local copy = table.clone(props)
	copy.alert = true
	return Dialog.confirm(copy)
end

return Dialog
