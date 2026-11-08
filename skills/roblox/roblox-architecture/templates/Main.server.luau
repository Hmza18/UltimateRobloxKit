--!strict
-- Single server entry point. Copy to src/server/Main.server.luau.
-- The client version is identical with Controllers instead of Services.

type Module = {
	Init: ((deps: any) -> ())?,
	Start: (() -> ())?,
}

local Services = script.Parent:WaitForChild("Services")

-- Explicit order: list services that others depend on first.
local ORDER = {
	"DataService",
	"PointsService",
}

local loaded: { [string]: Module } = {}
for _, name in ORDER do
	local moduleScript = Services:FindFirstChild(name)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), `missing service {name}`)
	loaded[name] = require(moduleScript) :: any
end

-- Every service gets the full registry; each service picks what it needs.
for _, name in ORDER do
	local m = loaded[name]
	if m.Init then
		local started = os.clock()
		m.Init(loaded)
		print(`[Init] {name} {math.round((os.clock() - started) * 1000)}ms`)
	end
end

for _, name in ORDER do
	local m = loaded[name]
	if m.Start then
		-- Start may yield; run each one in its own thread so one slow service does not block others.
		task.spawn(function()
			m.Start()
			print(`[Start] {name}`)
		end)
	end
end
