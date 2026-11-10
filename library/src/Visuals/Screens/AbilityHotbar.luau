--!strict
-- AbilityHotbar screen: a row of HotbarSlots at the bottom of the HUD with keybind labels,
-- cooldown sweeps and a ready pulse. A press (or the slot's key) raises Selected(id, ready); the
-- server decides whether the ability runs, and the game then starts the cooldown it reports:
--
--   bar.Selected:Connect(function(id, ready) if ready then UseAbility:FireServer(id) end end)
--   AbilityUsed.OnClientEvent:Connect(function(id, seconds) bar:startCooldown(id, seconds) end)
--
-- NOT run in Studio: see README.md.

local UserInputService = game:GetService("UserInputService")

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

return function(shell: ScreenKit.Shell, _props: { [string]: any })
	local row = ScreenKit.scroller(shell.root, "Hotbar", 6, true)
	row.ScrollBarThickness = 0
	local slots: { [string]: any } = {}
	local order: { string } = {}
	local keys: { [Enum.KeyCode]: string } = {}
	local size = 0

	local function clear()
		for _, slot in pairs(slots) do
			slot:destroy()
		end
		table.clear(slots)
		table.clear(order)
		table.clear(keys)
	end
	shell.trove:Add(clear)

	local function activate(id: string, fromKey: boolean)
		local slot = slots[id]
		if slot == nil then
			return
		end
		if fromKey then
			UI.animate(slot.Instance, "BouncyPress") -- the same feedback a click gets
		end
		shell:fire("Selected", id, slot:isReady())
	end

	local function build()
		clear()
		for i, entry in ipairs(shell.props.slots) do
			local id = tostring(entry.id or i)
			local slot = Game.HotbarSlot.new({
				style = shell.styleName,
				parent = row,
				layoutOrder = i,
				name = id,
				icon = entry.icon,
				image = entry.image,
				keybind = entry.keybind,
				palette = entry.palette,
				enabled = entry.enabled,
				size = if size > 0 then UDim2.fromOffset(size, size) else nil,
			})
			slots[id] = slot
			table.insert(order, id)
			slot.Activated:Connect(function()
				activate(id, false)
			end)
			slot.Ready:Connect(function()
				shell:fire("Ready", id)
			end)
			if typeof(entry.keyCode) == "EnumItem" then
				keys[entry.keyCode :: Enum.KeyCode] = id
			end
			if type(entry.remaining) == "number" and entry.remaining > 0 then
				slot:setCooldown(entry.remaining, entry.duration)
			end
		end
		local focus: { GuiObject } = {}
		for _, id in ipairs(order) do
			table.insert(focus, slots[id].Instance)
		end
		shell:focusables(focus)
	end

	shell.trove:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not shell:isOpen() then
			return
		end
		local id = keys[input.KeyCode]
		if id ~= nil then
			activate(id, true)
		end
	end))

	shell:onLayout(function(env: ScreensLogic.Env)
		local layout = ScreensLogic.hotbarLayout(env, #order)
		ScreenKit.rect(row, layout.row)
		if layout.slot ~= size then
			size = layout.slot
			for _, slot in pairs(slots) do
				slot:update({ size = UDim2.fromOffset(size, size) })
			end
		end
	end)
	build()

	return {
		update = function(partial: { [string]: any })
			if partial.slots ~= nil then
				build()
				shell:relayout()
			end
		end,
		methods = {
			startCooldown = function(id: any, seconds: number)
				local slot = slots[tostring(id)]
				if slot ~= nil then
					slot:startCooldown(seconds)
				end
			end,
			setCooldown = function(id: any, remaining: number, duration: number?)
				local slot = slots[tostring(id)]
				if slot ~= nil then
					slot:setCooldown(remaining, duration)
				end
			end,
			clearCooldown = function(id: any)
				local slot = slots[tostring(id)]
				if slot ~= nil then
					slot:clearCooldown()
				end
			end,
			isReady = function(id: any): boolean
				local slot = slots[tostring(id)]
				return slot ~= nil and slot:isReady()
			end,
		},
	}
end
