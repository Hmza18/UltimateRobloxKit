--!strict
-- Client adapter for InventoryServer. Holds the latest compact view sent by the server and sends
-- intents. The client never changes its own inventory: it waits for the next Sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Options = {
	remoteFolderName: string?, -- must match the server (default "URK_Inventory")
	timeout: number?, -- seconds to wait for the remote folder (default 30)
}

local InventoryClient = {}

function InventoryClient.start(options: Options?)
	local opts: Options = options or {}
	local folder = ReplicatedStorage:WaitForChild(opts.remoteFolderName or "URK_Inventory", opts.timeout or 30)
	assert(folder, "InventoryClient: remote folder not found")
	local trove = Trove.new()

	local client = {}
	client.view = nil :: any -- { v, slots = { { i, id, n } }, hotbar = { slotIndex }, sel }
	client.Changed = Signal.new() -- (view)

	local function remote(name: string): RemoteEvent
		return folder:WaitForChild(name) :: RemoteEvent
	end

	trove:Connect(remote("Sync").OnClientEvent, function(view: any)
		client.view = view
		client.Changed:Fire(view)
	end)

	-- Returns the stack in an inventory slot from the latest view, or nil.
	function client:slot(index: number): any
		local view = client.view
		if view == nil then
			return nil
		end
		for _, entry in view.slots do
			if entry.i == index then
				return entry
			end
		end
		return nil
	end

	function client:moveSlot(from: number, to: number, amount: number?)
		remote("MoveSlot"):FireServer(from, to, amount)
	end

	function client:selectHotbar(position: number?)
		remote("SelectHotbar"):FireServer(position)
	end

	function client:assignHotbar(position: number, index: number)
		remote("AssignHotbar"):FireServer(position, index)
	end

	function client:drop(index: number, amount: number?)
		remote("Drop"):FireServer(index, amount)
	end

	function client:destroy()
		trove:Clean()
		client.Changed:DisconnectAll()
	end

	remote("RequestSync"):FireServer()
	return client
end

return InventoryClient
