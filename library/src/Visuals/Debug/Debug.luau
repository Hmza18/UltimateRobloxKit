--!strict
-- Visuals.Debug: a stats overlay and a profiler for effects.
--
--   local close = Visuals.Debug.overlay()            -- live numbers in the corner; call close() to remove
--   Visuals.Debug.profile(2, function()              -- measure 2 s before and 2 s with the effect
--       return Visuals:Attach("Rain", part)
--   end, function(result) print(result.verdict, result.averageMs) end)
--
-- The overlay and the profiler connect to RenderStepped only while they are open.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DebugLogic = require("./DebugLogic")
local Host = require("../Runtime/Host")

local Debug = {}

local function stats(): { [string]: any }
	local effects = Host.effects:stats()
	return {
		level = Host.settings().level,
		tracks = Host.engine:count(),
		jobs = Host.clock:count(),
		effects = effects.live,
		particles = effects.particles,
		lights = effects.lights,
		spawned = effects.spawned,
		evicted = effects.evicted,
		rejected = effects.rejected,
	}
end

Debug.stats = stats

-- Shows the overlay under `parent` (default: the local player's PlayerGui). Returns a close function.
function Debug.overlay(parent: Instance?): () -> ()
	local target = parent
	if target == nil then
		local player = Players.LocalPlayer
		target = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	end
	if target == nil then
		return function() end
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "UvkDebug"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10000
	screen.IgnoreGuiInset = false

	local label = Instance.new("TextLabel")
	label.Name = "Stats"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 8, 1, -8)
	label.Size = UDim2.fromOffset(300, 92)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Active = false
	label.Parent = screen

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	screen.Parent = target

	local sampler = DebugLogic.sampler(240)
	local sinceRefresh = 1
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		sampler:push(dt)
		sinceRefresh += dt
		if sinceRefresh >= 0.25 then
			sinceRefresh = 0
			label.Text = table.concat(DebugLogic.format(stats(), sampler), "\n")
		end
	end)

	local closed = false
	return function()
		if closed then
			return
		end
		closed = true
		connection:Disconnect()
		screen:Destroy()
	end
end

export type ProfileResult = {
	averageMs: number,
	p99Ms: number,
	verdict: string,
	before: { average: number, p99: number },
	after: { average: number, p99: number },
}

-- Measures frame time for `seconds`, runs `start`, measures again, then stops what `start`
-- returned (a handle with stop, or a function) and calls `done` with the difference.
-- Returns a cancel function.
function Debug.profile(seconds: number, start: () -> any, done: (result: ProfileResult) -> ()): () -> ()
	local window = math.max(0.5, seconds)
	local sampler = DebugLogic.sampler(math.ceil(window * 240))
	local elapsed = 0
	local phase = "before"
	local before = { average = 0, p99 = 0 }
	local started: any = nil
	local connection: RBXScriptConnection? = nil

	local function stopStarted()
		if type(started) == "function" then
			started()
		elseif type(started) == "table" and type(started.stop) == "function" then
			started.stop()
		end
		started = nil
	end

	local function cancel()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		stopStarted()
	end

	connection = RunService.RenderStepped:Connect(function(dt: number)
		sampler:push(dt)
		elapsed += dt
		if elapsed < window then
			return
		end
		if phase == "before" then
			before = { average = sampler:average(), p99 = sampler:percentile(99) }
			sampler:reset()
			elapsed = 0
			phase = "after"
			local ok, result = pcall(start)
			if ok then
				started = result
			else
				warn("[UVK] profile start failed: " .. tostring(result))
			end
			return
		end
		local after = { average = sampler:average(), p99 = sampler:percentile(99) }
		cancel()
		local compared = DebugLogic.compare(before, after)
		done({
			averageMs = compared.averageMs,
			p99Ms = compared.p99Ms,
			verdict = compared.verdict,
			before = before,
			after = after,
		})
	end)
	return cancel
end

-- Prints every preset id by kind (requires the Presets module).
function Debug.dump()
	local ok, presets = pcall(function(): any
		return require("../Presets/Presets")
	end)
	if not ok then
		return
	end
	for _, kind in presets.kinds() do
		local ids: { string } = {}
		for _, entry in presets.list(kind) do
			table.insert(ids, entry.id)
		end
		print(string.format("[UVK] %s (%d): %s", kind, #ids, table.concat(ids, ", ")))
	end
end

return Debug
