--!strict
-- TappingHud screen: the clicker HUD. A big tap button (BouncyPress), currency counters that
-- roll and receive flying currency, a multiplier chip, a rebirth progress bar and side menu
-- buttons. Placement comes from ScreensLogic.tapLayout: the centre of the screen stays clear and,
-- on touch, so do the thumbstick and jump button corners.
--
--   hud.Tapped:Connect(function(position) TapRemote:FireServer() end)
--   TapResult.OnClientEvent:Connect(function(gain) hud:reward(gain, "coins") end)
--
-- Rapid taps stay cheap: the press animation is one binding on the engine, popups are pooled by
-- Visuals.UI, and counter updates from many rewards are folded into one roll.
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

-- Rewards arriving within this window roll the counter once.
local FOLD_SECONDS = 0.08

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.tappingHud(props)
	if #view.issues > 0 then
		error("TappingHud: " .. table.concat(view.issues, "; "), 0)
	end
	local root = shell.root
	local trove = shell.trove

	-- Tap button: a palette panel with a transparent button on top. The button takes the input,
	-- the panel takes the BouncyPress motion.
	local tapPanel = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = root,
		name = "Tap",
		palette = props.tapPalette,
		radius = "xl",
		outline = "heavy",
		gloss = true,
		pattern = true,
	}))
	local tapInner: Instance = tapPanel.Content or tapPanel.Instance
	local tapIcon: ImageLabel? = nil
	if props.tapIcon ~= nil then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.42)
		image.Size = UDim2.fromScale(0.5, 0.5)
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = tapInner
		ScreenKit.icon(image, props.tapIcon, nil)
		tapIcon = image
	end
	local tapLabel = shell:text(tapInner, props.tapText, "title", {
		size = if tapIcon then UDim2.fromScale(1, 0.3) else UDim2.fromScale(1, 1),
		position = if tapIcon then UDim2.fromScale(0, 0.68) else UDim2.fromScale(0, 0),
	})
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	hit.Parent = tapPanel.Instance
	local lastPress: Vector2? = nil
	trove:Add(hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			lastPress = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	local function tapPosition(): Vector2
		if lastPress ~= nil then
			return lastPress
		end
		return hit.AbsolutePosition + hit.AbsoluteSize / 2
	end
	trove:Add(UI.bind(hit, "BouncyPress", {
		target = tapPanel.Instance,
		onActivated = function()
			shell:fire("Tapped", tapPosition())
			lastPress = nil
		end,
	}))

	-- Counters.
	local countersHolder = shell:frame(root, "Counters")
	local countersLayout = ScreenKit.list(countersHolder, true, 6, "center")
	local chips: { [string]: any } = {}
	local values: { [string]: number } = {}
	local pending: { [string]: boolean } = {}
	local cancelFold: (() -> ())? = nil

	local function buildCounters()
		for _, chip in pairs(chips) do
			chip:destroy()
		end
		table.clear(chips)
		for i, currency in ipairs(view.currencies) do
			values[currency.id] = currency.value
			chips[currency.id] = Game.StatChip.new({
				style = shell.styleName,
				parent = countersHolder,
				layoutOrder = i,
				name = currency.id,
				icon = currency.icon,
				image = currency.image,
				value = currency.value,
				format = currency.format,
				palette = currency.palette,
			})
		end
	end
	trove:Add(function()
		if cancelFold then
			cancelFold()
		end
		for _, chip in pairs(chips) do
			chip:destroy()
		end
	end)

	local function flush()
		cancelFold = nil
		for id in pairs(pending) do
			local chip = chips[id]
			if chip ~= nil then
				chip:update({ value = values[id] })
			end
		end
		table.clear(pending)
	end

	local function setValue(id: string, value: number)
		values[id] = value
		pending[id] = true
		if cancelFold == nil then
			cancelFold = Host.clock:after(FOLD_SECONDS, flush)
		end
	end

	-- Multiplier chip and rebirth bar.
	local multiplier = shell:own(Game.StatChip.new({
		style = shell.styleName,
		parent = root,
		name = "Multiplier",
		icon = "star-color",
		value = view.multiplier,
		palette = "purple",
	}))
	local rebirthBar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = root,
		name = "Rebirth",
		palette = "purple",
		value = if view.rebirth then view.rebirth.value else 0,
		max = if view.rebirth then view.rebirth.max else 1,
		showText = true,
		visible = view.rebirth ~= nil,
	}))
	local rebirthHit = Instance.new("TextButton")
	rebirthHit.Name = "RebirthHit"
	rebirthHit.Text = ""
	rebirthHit.BackgroundTransparency = 1
	rebirthHit.ZIndex = 10
	rebirthHit.Visible = false
	rebirthHit.Parent = root
	trove:Add(rebirthHit)
	local rebirthPulse: any = nil
	trove:Add(UI.bind(rebirthHit, "Soft", {
		target = rebirthBar.Instance,
		onActivated = function()
			shell:fire("RebirthRequested")
		end,
	}))
	-- A full bar breathes and becomes a button: the press only raises the intent.
	local function refreshRebirth()
		local ready = view.rebirth ~= nil and view.rebirth.ready
		rebirthHit.Visible = ready
		if ready and rebirthPulse == nil then
			rebirthPulse = UI.animate(rebirthBar.Instance, "Pulse")
		elseif not ready and rebirthPulse ~= nil then
			rebirthPulse.stop(true)
			rebirthPulse = nil
		end
	end
	trove:Add(function()
		if rebirthPulse ~= nil then
			rebirthPulse.stop(false)
		end
	end)

	-- Side menu.
	local menuScroll = ScreenKit.scroller(root, "Menu", 6)
	menuScroll.ScrollBarThickness = 0
	local menuButtons: { any } = {}
	local menuSize = 0

	local function buildMenu()
		for _, button in ipairs(menuButtons) do
			button:destroy()
		end
		table.clear(menuButtons)
		for i, item in ipairs(view.menu) do
			local button = Game.IconButton.new({
				style = shell.styleName,
				parent = menuScroll,
				layoutOrder = i,
				name = item.id,
				icon = item.icon,
				image = item.image,
				palette = item.palette,
				badge = item.badge,
				size = if menuSize > 0 then UDim2.fromOffset(menuSize, menuSize) else nil,
			})
			table.insert(menuButtons, button)
			button.Activated:Connect(function()
				shell:fire("Selected", item.id)
			end)
		end
	end
	trove:Add(function()
		for _, button in ipairs(menuButtons) do
			button:destroy()
		end
	end)

	local function focusList(): { GuiObject }
		local objects: { GuiObject } = { hit }
		for _, button in ipairs(menuButtons) do
			table.insert(objects, button.Instance)
		end
		return objects
	end

	shell:onLayout(function(env: ScreensLogic.Env)
		local layout = ScreensLogic.tapLayout(env, #view.menu, #view.currencies)
		-- The root already sits inside the safe area, so rectangles are relative to it.
		ScreenKit.rect(tapPanel.Instance, layout.tap)
		ScreenKit.rect(countersHolder, layout.counters)
		countersLayout.FillDirection = if layout.countersVertical
			then Enum.FillDirection.Vertical
			else Enum.FillDirection.Horizontal
		countersLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		ScreenKit.rect(multiplier.Instance, layout.multiplier)
		ScreenKit.rect(rebirthBar.Instance, layout.rebirth)
		ScreenKit.rect(rebirthHit, {
			x = layout.rebirth.x,
			y = layout.rebirth.y - 10,
			w = layout.rebirth.w,
			h = math.max(ScreensLogic.MIN_TOUCH, layout.rebirth.h + 20),
		})
		ScreenKit.rect(menuScroll, layout.menu)
		if layout.menuButton ~= menuSize then
			menuSize = layout.menuButton
			for _, button in ipairs(menuButtons) do
				button:update({ size = UDim2.fromOffset(menuSize, menuSize) })
			end
		end
	end)

	buildCounters()
	buildMenu()
	refreshRebirth()
	shell:focusables(focusList())

	return {
		update = function(partial: { [string]: any })
			local previous = view
			view = ScreensLogic.tappingHud(shell.props)
			if #view.issues > 0 then
				view = previous
				error("TappingHud: " .. table.concat(view.issues, "; "), 0)
			end
			if partial.currencies ~= nil then
				local same = #previous.currencies == #view.currencies
				for i, currency in ipairs(view.currencies) do
					same = same and previous.currencies[i] ~= nil and previous.currencies[i].id == currency.id
				end
				if same then
					for _, currency in ipairs(view.currencies) do
						setValue(currency.id, currency.value)
					end
				else
					buildCounters()
				end
			end
			if partial.multiplier ~= nil then
				multiplier:update({ value = view.multiplier })
				UI.animate(multiplier.Instance, "UpgradePulse")
			end
			if partial.rebirth ~= nil then
				local rebirth = view.rebirth
				rebirthBar:update({
					visible = rebirth ~= nil,
					value = if rebirth then rebirth.value else 0,
					max = if rebirth then rebirth.max else 1,
				})
				refreshRebirth()
			end
			if partial.tapText ~= nil then
				tapLabel:update({ text = partial.tapText })
			end
			if partial.menu ~= nil then
				buildMenu()
				shell:relayout()
				shell:focusables(focusList())
			end
		end,
		methods = {
			-- Shows a gain the server confirmed: a floating number at `from` (default: where the
			-- player tapped) and the counter rolling up. Pass `from` (a GuiObject, screen pixels or
			-- a world position) to also fly currency from there to the counter.
			reward = function(amount: number, currencyId: string?, from: any)
				local first = view.currencies[1]
				local id = currencyId or (if first then first.id else nil)
				if id == nil or chips[id] == nil or type(amount) ~= "number" then
					return
				end
				if shell.props.popups ~= false then
					UI.popup(amount, from or tapPosition(), { style = "currency" })
				end
				if from ~= nil then
					UI.flyTo(from, chips[id].Instance, { count = 4 })
				end
				setValue(id, (values[id] or 0) + amount)
			end,
			-- The counter's GuiObject, as a target for the game's own UI.flyTo calls.
			counter = function(currencyId: string): GuiObject?
				local chip = chips[currencyId]
				return if chip then chip.Instance else nil
			end,
		},
	}
end
