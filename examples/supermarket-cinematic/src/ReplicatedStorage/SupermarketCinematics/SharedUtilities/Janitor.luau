-- Tracks everything a playback creates (instances, connections, callbacks) so one call cleans up.
local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({ _items = {}, _count = 0 }, Janitor)
end

-- Adds an item; `how` overrides the cleanup method name ("Destroy", "Disconnect" or a function).
function Janitor:Add(item, how)
	if item == nil then
		return item
	end
	self._count = self._count + 1
	self._items[self._count] = { item, how }
	return item
end

local function clean(item, how)
	if type(how) == "function" then
		how(item)
	elseif type(item) == "function" then
		item()
	elseif how then
		item[how](item)
	elseif typeof ~= nil and typeof(item) == "RBXScriptConnection" then
		item:Disconnect()
	elseif type(item) == "table" and type(item.Destroy) == "function" then
		item:Destroy()
	elseif type(item) == "table" and type(item.Disconnect) == "function" then
		item:Disconnect()
	else
		item:Destroy()
	end
end

-- Cleans newest first (children before the things they depend on). Errors are reported, never thrown,
-- so one broken item cannot leave the rest behind.
function Janitor:Cleanup()
	local items = self._items
	self._items = {}
	for i = self._count, 1, -1 do
		local entry = items[i]
		local ok, err = pcall(clean, entry[1], entry[2])
		if not ok then
			warn("[SupermarketCinematic] cleanup error: " .. tostring(err))
		end
	end
	self._count = 0
end

function Janitor:Count()
	return self._count
end

Janitor.Destroy = Janitor.Cleanup
return Janitor
