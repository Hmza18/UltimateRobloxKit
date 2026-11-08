--!strict
-- Loads every ModuleScript in a folder as a service (server) or controller (client).
-- Every Init runs first, one after another, lowest Priority first and then by name.
-- Then each Start runs in its own thread, so a Start that yields does not hold up the others.

local Types = require("./Types")

type Module = Types.Module

type Entry = { name: string, module: Module }

local DEFAULT_PRIORITY = 100

local Loader = {}

local function priorityOf(entry: Entry): number
	return entry.module.Priority or DEFAULT_PRIORITY
end

local function traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

-- Returns the loaded modules by name. `label` prefixes log messages, for example "Server".
function Loader.run(folder: Instance, label: string): { [string]: Module }
	local entries: { Entry } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local module = require(child)
			if type(module) == "table" then
				table.insert(entries, { name = module.Name or child.Name, module = module })
			else
				warn(string.format("[%s] %s did not return a table, skipped", label, child:GetFullName()))
			end
		end
	end

	table.sort(entries, function(a: Entry, b: Entry): boolean
		if priorityOf(a) ~= priorityOf(b) then
			return priorityOf(a) < priorityOf(b)
		end
		return a.name < b.name
	end)

	local loaded: { [string]: Module } = {}
	local failed: { [string]: boolean } = {}
	for _, entry in entries do
		loaded[entry.name] = entry.module
		local init = entry.module.Init
		if init then
			local ok, err = xpcall(init, traceback, entry.module)
			if not ok then
				failed[entry.name] = true
				warn(string.format("[%s] %s.Init failed; Start skipped: %s", label, entry.name, tostring(err)))
			end
		end
	end

	for _, entry in entries do
		local start = entry.module.Start
		if start and not failed[entry.name] then
			task.spawn(start, entry.module)
		end
	end
	return loaded
end

return Loader
