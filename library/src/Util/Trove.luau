--!strict
-- Collects things that need cleaning up and cleans them all at once.
-- Accepts Instances, RBXScriptConnections, functions, threads and tables with Destroy or Disconnect.

export type Trove = {
	Add: (self: Trove, item: any) -> any,
	Connect: (self: Trove, signal: any, handler: (...any) -> ()) -> any,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

local Trove = {}

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		-- Cancelling the running thread errors, so ignore that case.
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.new(): Trove
	local items: { any } = {}
	local cleaning = false

	local function add(_self: Trove, item: any): any
		if cleaning then
			-- Added during Clean: clean it straight away instead of leaking it.
			cleanup(item)
		else
			table.insert(items, item)
		end
		return item
	end

	local function connect(self: Trove, signal: any, handler: (...any) -> ()): any
		return self:Add(signal:Connect(handler))
	end

	local function clean(_self: Trove)
		if cleaning then
			return
		end
		cleaning = true
		-- Clean in reverse order of adding, like a stack.
		for index = #items, 1, -1 do
			local item = items[index]
			items[index] = nil
			cleanup(item)
		end
		cleaning = false
	end

	return { Add = add, Connect = connect, Clean = clean, Destroy = clean }
end

return Trove
