--!strict
-- Cleanup container (maid). Add connections, instances, threads, functions or
-- anything with a destroy/Destroy method; destroy() releases them in reverse order.

type Cleanable = RBXScriptConnection | Instance | thread | () -> () | { destroy: (any) -> () } | { Destroy: (any) -> () }

export type Trove = {
	add: <T>(self: Trove, item: T) -> T,
	extend: (self: Trove) -> Trove,
	destroy: (self: Trove) -> (),
}

local Trove = {}

local function clean(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "function" then
		item()
	elseif type(item) == "table" then
		if type(item.destroy) == "function" then
			item:destroy()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		end
	end
end

function Trove.new(): Trove
	local items: { any } = {}
	local destroyed = false
	local self = {} :: Trove

	function self.add<T>(_, item: T): T
		if destroyed then
			clean(item)   -- adding to a dead trove cleans immediately
		else
			table.insert(items, item)
		end
		return item
	end

	function self.extend(s: Trove): Trove
		return s:add(Trove.new())
	end

	function self.destroy(_)
		if destroyed then
			return
		end
		destroyed = true
		for i = #items, 1, -1 do
			clean(items[i])
			items[i] = nil
		end
	end

	return self
end

return Trove
