--!strict
-- Feeds a Store from replicated game state, so the server stays the source of truth:
--   fromAttributes(instance, prefix) mirrors attributes (for example on the Player) into the store.
--   fromFolder(folder, prefix) mirrors ValueBase children (IntValue, StringValue, ...) recursively,
--   with nested Folders becoming nested paths.
-- Both return the store and a stop function; stop disconnects everything.

local Store = require("../Core/Store")
local Trove = require("../../Util/Trove")

export type Options = {
	store: Store.Store?, -- write into this store instead of a new one
	nest: string?, -- attribute name separator for nesting, for example "_"
}

local StoreAdapter = {}

-- Scheduler for Store.new on Roblox: coalesces writes until the next resumption point.
function StoreAdapter.deferred(callback: () -> ())
	task.defer(callback)
end

local function newStore(options: Options?): Store.Store
	if options and options.store then
		return options.store
	end
	return Store.new(nil, { scheduler = StoreAdapter.deferred })
end

function StoreAdapter.fromAttributes(instance: Instance, prefix: string?, options: Options?): (Store.Store, () -> ())
	local store = newStore(options)
	local base = prefix or ""
	local nest = if options then options.nest else nil
	local trove = Trove.new()

	local function write(name: string, value: any)
		local path = Store.attributePath(base, name, nest)
		if path then
			store:set(path, value)
		end
	end

	store:batch(function()
		for name, value in instance:GetAttributes() do
			write(name, value)
		end
	end)
	trove:Connect(instance.AttributeChanged, function(name: string)
		write(name, instance:GetAttribute(name))
	end)

	local function stop()
		trove:Clean()
	end
	return store, stop
end

local function mirrorFolder(store: Store.Store, folder: Instance, path: string, trove: any)
	local function track(child: Instance)
		local childPath = Store.attributePath(path, child.Name)
		if childPath == nil then
			return
		end
		if child:IsA("ValueBase") then
			local valueObject: any = child
			store:set(childPath, valueObject.Value)
			trove:Connect(valueObject.Changed, function(value: any)
				store:set(childPath, value)
			end)
		elseif child:IsA("Folder") or child:IsA("Configuration") then
			mirrorFolder(store, child, childPath, trove)
		end
	end
	for _, child in folder:GetChildren() do
		track(child)
	end
	trove:Connect(folder.ChildAdded, track)
	trove:Connect(folder.ChildRemoved, function(child: Instance)
		local childPath = Store.attributePath(path, child.Name)
		if childPath then
			store:set(childPath, nil)
		end
	end)
end

-- Mirrors a folder of Value objects (for example the classic leaderstats folder).
-- A renamed child keeps its old path until it is re-added; rename values only before replicating.
function StoreAdapter.fromFolder(folder: Instance, prefix: string?, options: Options?): (Store.Store, () -> ())
	local store = newStore(options)
	local trove = Trove.new()
	store:batch(function()
		mirrorFolder(store, folder, prefix or "", trove)
	end)
	local function stop()
		trove:Clean()
	end
	return store, stop
end

return StoreAdapter
