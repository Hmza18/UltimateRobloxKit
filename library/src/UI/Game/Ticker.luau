--!strict
-- One shared ticker for the game components: Timer countdowns, CurrencyCounter count-ups and the
-- secret-rarity rainbow. It is a single job on Runtime/Driver, which runs only while at least one
-- callback is registered, so an idle UI does no per-frame work.
--
--   Ticker.frame(fn)  -> fn(now, dt) every frame; return false to stop
--   Ticker.slow(fn)   -> fn(now) about 4 times per second (countdowns); return false to stop
-- Both return a function that removes the callback.

local Driver = require("../Runtime/Driver")

export type FrameFn = (now: number, dt: number) -> boolean?
export type SlowFn = (now: number) -> boolean?

local Ticker = {}

local SLOW_INTERVAL = 0.25

local frameJobs: { [number]: FrameFn } = {}
local slowJobs: { [number]: SlowFn } = {}
local count = 0
local nextId = 0
local lastSlow = -math.huge
local removeDriverJob: (() -> ())? = nil

local function removeId(id: number)
	if frameJobs[id] ~= nil or slowJobs[id] ~= nil then
		frameJobs[id] = nil
		slowJobs[id] = nil
		count -= 1
	end
end

local function step(dt: number, now: number): boolean?
	for id, job in table.clone(frameJobs) do
		if frameJobs[id] == job then
			local ok, keep = pcall(job, now, dt)
			if not ok then
				warn("[UrkUI.Game] ticker job failed: " .. tostring(keep))
				removeId(id)
			elseif keep == false then
				removeId(id)
			end
		end
	end
	if now - lastSlow >= SLOW_INTERVAL then
		lastSlow = now
		for id, job in table.clone(slowJobs) do
			if slowJobs[id] == job then
				local ok, keep = pcall(job, now)
				if not ok then
					warn("[UrkUI.Game] ticker job failed: " .. tostring(keep))
					removeId(id)
				elseif keep == false then
					removeId(id)
				end
			end
		end
	end
	if count <= 0 then
		removeDriverJob = nil
		return false
	end
	return true
end

local function ensureRunning()
	if removeDriverJob == nil then
		lastSlow = -math.huge
		removeDriverJob = Driver.add(step)
	end
end

local function register(): (number, () -> ())
	nextId += 1
	count += 1
	local id = nextId
	local function remove()
		removeId(id)
	end
	return id, remove
end

function Ticker.frame(fn: FrameFn): () -> ()
	local id, remove = register()
	frameJobs[id] = fn
	ensureRunning()
	return remove
end

function Ticker.slow(fn: SlowFn): () -> ()
	local id, remove = register()
	slowJobs[id] = fn
	ensureRunning()
	return remove
end

-- Number of registered callbacks (0 means the ticker is not running).
function Ticker.count(): number
	return count
end

return Ticker
