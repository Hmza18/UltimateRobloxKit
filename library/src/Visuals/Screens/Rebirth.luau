--!strict
-- Rebirth screen: progress toward the rebirth cost, the multiplier before and after, what the
-- player keeps and loses, and a confirm that cannot be hit by accident: hold the button
-- (`confirm = "hold"`) or press it twice (`confirm = "double"`). Confirmed is only a request; the
-- server performs the rebirth, and the game then calls screen:celebrate().
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 64
local DOUBLE_WINDOW = 3 -- seconds the second press stays armed

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.rebirth(props)
	local window = shell:window({ title = props.title, kind = "dialog", headerPalette = "purple" })
	local ink = ScreenKit.ink(shell.style, "window", "center")

	local row = shell:frame(window.content, "Multiplier")
	row.LayoutOrder = 1
	row.Size = UDim2.new(1, -10, 0, 44)
	ScreenKit.list(row, true, 10, "center")
	local before = shell:own(Game.StatChip.new({
		style = shell.styleName,
		parent = row,
		layoutOrder = 1,
		icon = "star-color",
		value = view.multiplier,
	}))
	local arrow = shell:text(row, ">", "heading", { layoutOrder = 2, color = ink.color, stroke = false })
	arrow:update({ size = UDim2.fromOffset(28, 36) })
	local after = shell:own(Game.StatChip.new({
		style = shell.styleName,
		parent = row,
		layoutOrder = 3,
		icon = "star-color",
		value = view.nextMultiplier,
		palette = "gold",
	}))
	local bar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = window.content,
		layoutOrder = 2,
		name = "Cost",
		palette = "purple",
		value = math.min(props.current, props.cost),
		max = math.max(1, props.cost),
		showText = true,
		size = UDim2.new(1, -10, 0, 28),
	}))
	local keeps =
		shell:text(window.content, "", "caption", { layoutOrder = 3, color = ink.color, stroke = false, wrap = true })
	local loses =
		shell:text(window.content, "", "caption", { layoutOrder = 4, color = ink.color, stroke = false, wrap = true })
	local hint = shell:text(window.content, "", "caption", { layoutOrder = 5, color = ink.color, stroke = false })

	-- Confirm control: a palette panel with a fill that grows while held, and a button on top.
	local footer = window.setFooter(FOOTER)
	local panel = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = footer,
		name = "Confirm",
		palette = "green",
		gloss = true,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(0.8, 0, 0, FOOTER - 8),
	}))
	local fill = Instance.new("Frame")
	fill.Name = "Hold"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0.55
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	fill.Parent = panel.Body or panel.Instance
	local label = shell:text(panel.Content or panel.Instance, "", "heading", { size = UDim2.fromScale(1, 1) })
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	hit.Parent = panel.Instance

	local stopHold: (() -> ())? = nil
	local disarm: (() -> ())? = nil
	local armed = false
	local busy = false -- a confirm was sent; wait for update() or celebrate()

	local function mode(): string
		return if shell.props.confirm == "double" then "double" else "hold"
	end

	local function refresh()
		view = ScreensLogic.rebirth(shell.props)
		local current: { [string]: any } = shell.props
		before:update({ value = view.multiplier })
		after:update({ value = view.nextMultiplier })
		bar:update({ value = math.min(current.current, current.cost), max = math.max(1, current.cost) })
		local keepList: { string } = current.keeps or {}
		local loseList: { string } = current.loses or {}
		keeps:update({ text = "You keep: " .. table.concat(keepList, ", "), visible = #keepList > 0 })
		loses:update({ text = "You lose: " .. table.concat(loseList, ", "), visible = #loseList > 0 })
		local enabled = view.affordable and not busy
		panel:update({ palette = if not enabled then "gray" elseif armed then "red" else "green" })
		local text = current.confirmText
		if not view.affordable then
			text = "NEED " .. ScreenKit.amount(view.missing) .. " MORE"
		elseif armed then
			text = "PRESS AGAIN"
		end
		label:update({ text = text })
		hint:update({
			text = if mode() == "hold" then "Hold the button to rebirth" else "Press twice to rebirth",
			visible = view.affordable,
		})
	end

	local function confirm()
		busy = true
		armed = false
		fill.Size = UDim2.fromScale(0, 1)
		refresh()
		UI.animate(panel.Instance, "Confirm")
		shell:fire("Confirmed")
	end

	local function cancelHold()
		if stopHold then
			stopHold()
			stopHold = nil
		end
		fill.Size = UDim2.fromScale(0, 1)
	end

	local function press()
		if not view.affordable or busy then
			UI.animate(panel.Instance, "Error")
			return
		end
		UI.animate(panel.Instance, "PressDown")
		if mode() == "double" then
			if armed then
				if disarm then
					disarm()
					disarm = nil
				end
				confirm()
			else
				armed = true
				refresh()
				disarm = Host.clock:after(DOUBLE_WINDOW, function()
					disarm = nil
					armed = false
					refresh()
				end)
			end
			return
		end
		cancelHold()
		local held = 0
		stopHold = Host.clock:add(function(dt: number): boolean?
			held += dt
			local fraction, done = ScreensLogic.holdFraction(held, shell.props.holdSeconds)
			fill.Size = UDim2.fromScale(fraction, 1)
			if done then
				stopHold = nil
				confirm()
				return false
			end
			return nil
		end)
	end

	local function release()
		if mode() == "hold" and stopHold ~= nil then
			cancelHold()
		end
		UI.animate(panel.Instance, "ReleaseSpring")
	end

	local function isPress(input: InputObject): boolean
		local kind = input.UserInputType
		return kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.Return
	end
	shell.trove:Add(hit.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			press()
		end
	end))
	shell.trove:Add(hit.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			release()
		end
	end))
	shell.trove:Add(function()
		cancelHold()
		if disarm then
			disarm()
		end
	end)

	refresh()
	shell:focusables({ hit })
	shell.onClosed = function()
		cancelHold()
		armed = false
		busy = false
		refresh()
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			-- New numbers from the server end the wait after a confirm.
			if partial.current ~= nil or partial.cost ~= nil or partial.multiplier ~= nil then
				busy = false
			end
			refresh()
		end,
		methods = {
			-- Call after the server performed the rebirth: the new multiplier pulses and, with a
			-- `context` ({ position = ... }), the RebirthDone feedback plays in the world.
			celebrate = function(context: { [string]: any }?)
				busy = false
				refresh()
				UI.animate(after.Instance, "UpgradePulse")
				UI.flash(nil, { duration = 0.35 })
				if context ~= nil then
					local ok, Feedback = pcall(function(): any
						return require("../Feedback/Feedback")
					end)
					if ok and type(Feedback) == "table" then
						Feedback.fire("RebirthDone", context)
					end
				end
				shell:fire("Celebrated")
			end,
		},
	}
end
