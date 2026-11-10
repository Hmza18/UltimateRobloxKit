--!strict
-- Deterministic frame clock for the visuals kit (pure Luau). Everything that runs over time - motion
-- tracks, sequences, effect lifetimes, cleanup timers - is a job or a timer on a Clock, and the
-- clock only moves when step(dt) is called. Runtime/Host steps one shared clock from RenderStepped;
-- specs step their own, so every lifecycle rule can be tested without Roblox.

export type Job = (dt: number, now: number) -> boolean?

export type Clock = {
	add: (self: Clock, job: Job) -> () -> (),
	after: (self: Clock, seconds: number, callback: () -> ()) -> () -> (),
	step: (self: Clock, dt: number) -> (),
	now: (self: Clock) -> number,
	count: (self: Clock) -> number,
	-- Called with true when the first job or timer is added and false when the last one ends, so a
	-- host can connect to the frame signal only while there is work.
	onActive: ((active: boolean) -> ())?,
	-- Called when a job or timer raises an error (the job is removed). Defaults to print.
	onError: (message: string) -> (),
}

type Timer = { at: number, callback: () -> () }

local Clock = {}

function Clock.new(): Clock
	local jobs: { [number]: Job } = {}
	local timers: { [number]: Timer } = {}
	local live = 0
	local nextId = 0
	local time = 0
	local self: Clock

	local function changed(delta: number)
		local before = live
		live += delta
		if self.onActive then
			if before == 0 and live > 0 then
				self.onActive(true)
			elseif before > 0 and live == 0 then
				self.onActive(false)
			end
		end
	end

	local function add(_self: Clock, job: Job): () -> ()
		nextId += 1
		local id = nextId
		jobs[id] = job
		changed(1)
		return function()
			if jobs[id] ~= nil then
				jobs[id] = nil
				changed(-1)
			end
		end
	end

	local function after(_self: Clock, seconds: number, callback: () -> ()): () -> ()
		nextId += 1
		local id = nextId
		timers[id] = { at = time + math.max(0, seconds), callback = callback }
		changed(1)
		return function()
			if timers[id] ~= nil then
				timers[id] = nil
				changed(-1)
			end
		end
	end

	local function step(_self: Clock, dt: number)
		local delta = math.max(0, dt)
		time += delta
		-- Timers first, in due order, so a cleanup scheduled for this frame runs before jobs draw.
		local due: { { id: number, at: number } } = {}
		for id, timer in timers do
			if timer.at <= time then
				table.insert(due, { id = id, at = timer.at })
			end
		end
		type Due = { id: number, at: number }
		table.sort(due, function(a: Due, b: Due): boolean
			return if a.at == b.at then a.id < b.id else a.at < b.at
		end)
		for _, entry in due do
			local timer = timers[entry.id]
			if timer then
				timers[entry.id] = nil
				changed(-1)
				local ok, err = pcall(timer.callback)
				if not ok then
					self.onError("[UVK] timer failed: " .. tostring(err))
				end
			end
		end
		local ids: { number } = {}
		for id in jobs do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local job = jobs[id]
			if job then
				local ok, result = pcall(job, delta, time)
				if not ok then
					self.onError("[UVK] job failed: " .. tostring(result))
				end
				if (not ok or result == false) and jobs[id] ~= nil then
					jobs[id] = nil
					changed(-1)
				end
			end
		end
	end

	self = {
		add = add,
		after = after,
		step = step,
		now = function(_self: Clock): number
			return time
		end,
		count = function(_self: Clock): number
			return live
		end,
		onActive = nil :: ((active: boolean) -> ())?,
		onError = function(message: string)
			print(message)
		end,
	}
	return self
end

return Clock
