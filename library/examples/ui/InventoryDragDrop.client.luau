--!strict
-- Example 2: inventory grid with drag-and-drop, tooltips and gamepad support, in a window that
-- toggles with I (keyboard) or Y (gamepad).
--
-- The grid never moves items. It turns a drop into an intent and this script sends that intent
-- to the server through the "InventoryIntent" RemoteEvent. The server checks the request with
-- the same rules (UrkUI.Core.SlotLogic.resolveDrop on its own copy of the inventory), applies it,
-- and fires the authoritative slots back. Without that remote the example previews locally.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
local UrkUI = require(Kit:WaitForChild("UI"):WaitForChild("UrkUI"))
local SlotLogic = UrkUI.Core.SlotLogic

UrkUI.start()

local slots: { any } = {
	{ itemId = "sword", count = 1, category = "Weapon", icon = "sword", name = "Iron Sword" },
	{ itemId = "apple", count = 5, category = "Food", maxStack = 10, icon = "apple", name = "Apple" },
	{ itemId = "apple", count = 8, category = "Food", maxStack = 10, icon = "apple", name = "Apple" },
	{},
	{ accepts = { "Weapon" }, name = "Weapon slot" },
	{ itemId = "key", count = 1, category = "Quest", locked = true, icon = "key", name = "Old Key (quest)" },
}
for _ = #slots + 1, 20 do
	table.insert(slots, {})
end

local window = UrkUI.Components.Window.new({ id = "Inventory", title = "Backpack", size = Vector2.new(440, 420) })
local remote = ReplicatedStorage:FindFirstChild("InventoryIntent")

local grid: any -- assigned below; the callbacks run later, after the grid exists
grid = UrkUI.Components.InventoryGrid.new({
	slots = slots,
	columns = 5,
	cellSize = 72,
	parent = window.Content,
	tooltip = function(slot: any): string?
		local count = slot.count or 1
		return if count > 1 then string.format("%s x%d", slot.name, count) else slot.name
	end,
	onIntent = function(intent: any)
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(intent.kind, intent.from, intent.to, intent.amount)
		else
			-- Local preview only. A real game must let the server decide.
			slots = SlotLogic.applyIntent(slots, intent)
			grid:setSlots(slots)
		end
	end,
	onReject = function(intent: any)
		UrkUI.toast({ text = "Can't move that: " .. tostring(intent.reason), kind = "warning" })
	end,
})

if remote and remote:IsA("RemoteEvent") then
	remote.OnClientEvent:Connect(function(authoritativeSlots: { any })
		slots = authoritativeSlots
		grid:setSlots(slots)
	end)
end

local function toggleInventory(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		UrkUI.toggle("Inventory")
	end
	return Enum.ContextActionResult.Pass
end
ContextActionService:BindAction("ToggleInventory", toggleInventory, false, Enum.KeyCode.I, Enum.KeyCode.ButtonY)
