--!strict
-- Frame-time statistics and profiling maths for Visuals.Debug (pure Luau).

export type Sampler = {
	push: (self: Sampler, frameTime: number) -> (),
	average: (self: Sampler) -> number,
	fps: (self: Sampler) -> number,
	worst: (self: Sampler) -> number,
	percentile: (self: Sampler, p: number) -> number,
	hitches: (self: Sampler, threshold: number?) -> number,
	count: (self: Sampler) -> number,
	reset: (self: Sampler) -> (),
}

local DebugLogic = {}

-- A ring buffer of the last `capacity` frame times (default 240, about 4 s at 60 fps).
function DebugLogic.sampler(capacity: number?): Sampler
	local size = math.max(1, math.floor(capacity or 240))
	local values: { number } = {}
	for i = 1, size do
		values[i] = 0
	end
	local filled, index = 0, 0

	local function snapshot(): { number }
		local out: { number } = {}
		for i = 1, filled do
			out[i] = values[i]
		end
		return out
	end

	local self: Sampler
	self = {
		push = function(_self: Sampler, frameTime: number)
			if frameTime ~= frameTime or frameTime <= 0 or frameTime == math.huge then
				return
			end
			index = index % size + 1
			values[index] = frameTime
			filled = math.min(size, filled + 1)
		end,
		average = function(_self: Sampler): number
			if filled == 0 then
				return 0
			end
			local sum = 0
			for i = 1, filled do
				sum += values[i]
			end
			return sum / filled
		end,
		fps = function(_self: Sampler): number
			local average = self:average()
			return if average > 0 then 1 / average else 0
		end,
		worst = function(_self: Sampler): number
			local high = 0
			for i = 1, filled do
				high = math.max(high, values[i])
			end
			return high
		end,
		-- Frame time at percentile p (0..100); p = 99 is the usual "1% low" measure.
		percentile = function(_self: Sampler, p: number): number
			if filled == 0 then
				return 0
			end
			local sorted = snapshot()
			table.sort(sorted)
			local rank = math.clamp(math.ceil(math.clamp(p, 0, 100) / 100 * filled), 1, filled)
			return sorted[rank]
		end,
		-- Frames slower than `threshold` seconds (default 1/30).
		hitches = function(_self: Sampler, threshold: number?): number
			local limit = threshold or 1 / 30
			local n = 0
			for i = 1, filled do
				if values[i] > limit then
					n += 1
				end
			end
			return n
		end,
		count = function(_self: Sampler): number
			return filled
		end,
		reset = function(_self: Sampler)
			filled, index = 0, 0
		end,
	}
	return self
end

-- Difference between two measurements: how much an effect cost. Positive ms means slower.
function DebugLogic.compare(
	before: { average: number, p99: number },
	after: { average: number, p99: number }
): { averageMs: number, p99Ms: number, verdict: string }
	local averageMs = (after.average - before.average) * 1000
	local p99Ms = (after.p99 - before.p99) * 1000
	local verdict = "ok"
	if averageMs > 2 or p99Ms > 6 then
		verdict = "expensive"
	elseif averageMs > 0.5 or p99Ms > 2 then
		verdict = "noticeable"
	end
	return { averageMs = averageMs, p99Ms = p99Ms, verdict = verdict }
end

-- One line per stat for the overlay.
function DebugLogic.format(stats: { [string]: any }, sampler: Sampler): { string }
	local lines = {
		string.format(
			"UVK  %s  %.0f fps  (p99 %.1f ms)",
			tostring(stats.level),
			sampler:fps(),
			sampler:percentile(99) * 1000
		),
		string.format("tracks %d   jobs %d", stats.tracks or 0, stats.jobs or 0),
		string.format(
			"effects %d   particles ~%d   lights %d",
			stats.effects or 0,
			stats.particles or 0,
			stats.lights or 0
		),
		string.format("spawned %d   evicted %d", stats.spawned or 0, stats.evicted or 0),
	}
	local rejected: { string } = {}
	local skipped: { [any]: any } = stats.rejected or {}
	for reason, count in skipped do
		table.insert(rejected, string.format("%s %d", tostring(reason), tonumber(count) or 0))
	end
	table.sort(rejected)
	if #rejected > 0 then
		table.insert(lines, "skipped: " .. table.concat(rejected, ", "))
	end
	return lines
end

return DebugLogic
