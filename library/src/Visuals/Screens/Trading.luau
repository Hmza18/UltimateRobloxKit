--!strict
-- Trading screen: two offer panels (yours and theirs), ready states, a note when their offer
-- changes, and a countdown before the confirm button appears. Presentation only: every press
-- raises an intent, and the server owns the offers, the ready flags and the trade itself.
--
--   trade.Selected:Connect(function(itemId) RemoveFromOffer:FireServer(itemId) end)
--   trade.ReadyToggled:Connect(function(ready) SetReady:FireServer(ready) end)
--   trade.Confirmed:Connect(function() ConfirmTrade:FireServer() end)
--   OfferChanged.OnClientEvent:Connect(function(state) trade:update(state) end)
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 96
local HEAD = 34

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, kind = "wide", headerPalette = "orange", scroll = false })
	local content = window.content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy() -- the two offers are placed by ScreensLogic.split
		end
	end
	local ink = ScreenKit.ink(shell.style, "inset", "left")

	type Side = { panel: any, head: any, grid: ScreenKit.CardGrid, scroll: ScrollingFrame }
	local function side(name: string): Side
		local panel = shell:own(Game.Panel.new({
			style = shell.styleName,
			parent = content,
			name = name,
			surface = "inset",
			padding = "sm",
			shadow = false,
		}))
		local inner: Instance = panel.Content or panel.Instance
		local head = shell:text(
			inner,
			"",
			"label",
			{ color = ink.color, stroke = false, align = "left", size = UDim2.new(1, 0, 0, HEAD) }
		)
		local holder = shell:frame(inner, "Items")
		holder.Position = UDim2.fromOffset(0, HEAD)
		holder.Size = UDim2.new(1, 0, 1, -HEAD)
		local scroll = ScreenKit.scroller(holder, "Scroll", 6)
		local grid = ScreenKit.cards(scroll, "slot", 1)
		shell.trove:Add(grid.destroy)
		return { panel = panel, head = head, grid = grid, scroll = scroll }
	end
	local mine = side("Mine")
	local theirs = side("Theirs")

	local footer = window.setFooter(FOOTER)
	local status = shell:text(footer, "", "caption", {
		color = ScreenKit.ink(shell.style, "window").color,
		stroke = false,
		size = UDim2.new(1, 0, 0, 24),
	})
	local buttons = shell:frame(footer, "Buttons")
	buttons.Position = UDim2.fromOffset(0, 28)
	buttons.Size = UDim2.new(1, 0, 1, -28)
	ScreenKit.list(buttons, true, 8, "center")
	local cancel = shell:button(
		buttons,
		{ name = "Cancel", kind = "danger", text = "CANCEL", layoutOrder = 1, size = UDim2.new(0.3, 0, 1, -4) }
	)
	local ready = shell:button(
		buttons,
		{ name = "Ready", kind = "primary", text = "READY", layoutOrder = 2, size = UDim2.new(0.3, 0, 1, -4) }
	)
	local confirm = shell:button(
		buttons,
		{ name = "Confirm", kind = "buy", text = "CONFIRM", layoutOrder = 3, size = UDim2.new(0.3, 0, 1, -4) }
	)

	local lastTheirs: any = props.theirs
	local note = ""
	local deadline: number? = nil
	local stopTick: (() -> ())? = nil

	local function remaining(): number
		return if deadline ~= nil then math.max(0, deadline - Host.clock:now()) else 0
	end

	local function refreshFooter()
		local current: { [string]: any } = shell.props
		local phase, seconds = ScreensLogic.tradePhase(current.myReady, current.theirReady, remaining())
		local partner = tostring((current.partner or {}).name or "Partner")
		mine.head:update({ text = if current.myReady then "YOU  -  READY" else "YOU" })
		theirs.head:update({ text = string.upper(partner) .. (if current.theirReady then "  -  READY" else "") })
		ready:update({
			kind = if current.myReady then "neutral" else "primary",
			text = if current.myReady then "NOT READY" else "READY",
		})
		confirm:update({ enabled = phase == "confirm" })
		local text = note
		if phase == "countdown" then
			text = string.format("Check the offers: confirm in %d", seconds)
		elseif phase == "confirm" then
			text = "Both ready. Confirm to trade."
		elseif text == "" then
			text = if current.myReady then "Waiting for " .. partner else "Add items, then press READY"
		end
		status:update({ text = text })
	end

	local function stopCountdown()
		if stopTick then
			stopTick()
			stopTick = nil
		end
		deadline = nil
	end

	-- The countdown is shown from the seconds the caller passes; the server decides when a
	-- confirm is accepted.
	local function startCountdown(seconds: number)
		stopCountdown()
		if seconds <= 0 then
			return
		end
		deadline = Host.clock:now() + seconds
		local sinceText = 0
		stopTick = Host.clock:add(function(dt: number): boolean?
			sinceText += dt
			if sinceText >= 0.2 or remaining() <= 0 then
				sinceText = 0
				refreshFooter()
			end
			if remaining() <= 0 then
				stopTick = nil
				UI.animate(confirm.Instance, "Bounce")
				return false
			end
			return nil
		end)
	end

	local function fill(target: Side, items: any, pressable: boolean)
		target.grid.set(items or {}, function(item: any, index: number, size: UDim2?): any
			local slot = Game.InventorySlot.new({
				style = shell.styleName,
				parent = target.grid.holder,
				layoutOrder = index,
				name = tostring(item.id or index),
				icon = item.icon,
				image = item.image,
				count = item.count,
				rarity = if type(item.rarity) == "string" then string.lower(item.rarity) else nil,
				enabled = pressable,
				size = size,
			})
			if pressable then
				slot.Activated:Connect(function()
					shell:fire("Selected", item.id)
				end)
			end
			return slot
		end)
	end

	local function focusList(): { GuiObject }
		local objects = mine.grid.instances()
		for _, button in ipairs({ cancel, ready, confirm }) do
			table.insert(objects, button.Instance)
		end
		return objects
	end

	shell.trove:Add(cancel.Activated:Connect(function()
		shell:fire("Cancelled")
		shell:close()
	end))
	shell.trove:Add(ready.Activated:Connect(function()
		shell:fire("ReadyToggled", shell.props.myReady ~= true)
	end))
	shell.trove:Add(confirm.Activated:Connect(function()
		local phase = ScreensLogic.tradePhase(shell.props.myReady, shell.props.theirReady, remaining())
		if phase == "confirm" then
			shell:fire("Confirmed")
		end
	end))
	shell.trove:Add(stopCountdown)

	shell:onLayout(function(_env: ScreensLogic.Env)
		local size = content.AbsoluteSize
		local area = { x = 0, y = 0, w = size.X, h = size.Y }
		if area.w <= 0 then
			local body = window.body()
			area.w, area.h = body.content.w, body.content.h - FOOTER
		end
		local split = ScreensLogic.split(area, { ratio = 0.5, minPrimary = 200, minSecondary = 200 })
		ScreenKit.rect(mine.panel.Instance, split.primary)
		ScreenKit.rect(theirs.panel.Instance, split.secondary)
		mine.grid.layout(split.primary.w - 30)
		theirs.grid.layout(split.secondary.w - 30)
	end)

	fill(mine, props.mine, true)
	fill(theirs, props.theirs, false)
	startCountdown(props.countdown)
	refreshFooter()
	shell:focusables(focusList())
	shell.onClosed = stopCountdown

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.mine ~= nil then
				fill(mine, partial.mine, true)
			end
			if partial.theirs ~= nil then
				-- Say what changed on their side, and flash their panel.
				local diff = ScreensLogic.tradeDiff(lastTheirs, partial.theirs)
				lastTheirs = partial.theirs
				fill(theirs, partial.theirs, false)
				if diff.changed then
					note = "Their offer changed: " .. diff.summary
					UI.animate(theirs.panel.Instance, "Highlight")
				end
			end
			if partial.myReady ~= nil or partial.theirReady ~= nil then
				note = ""
			end
			if partial.countdown ~= nil then
				startCountdown(partial.countdown)
			elseif shell.props.myReady ~= true or shell.props.theirReady ~= true then
				stopCountdown()
			end
			shell:relayout()
			refreshFooter()
			shell:focusables(focusList())
		end,
	}
end
