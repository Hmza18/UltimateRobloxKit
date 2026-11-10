--!strict
-- Generic object pool (pure Luau). Effects reuse emitters, popup labels and holder parts instead of
-- creating and destroying instances for every tap.
--
--   local pool = Pool.new({ create = makeLabel, reset = hideLabel, destroy = destroyLabel, max = 32 })
--   local label = pool:acquire()
--   pool:release(label)

export type Options<T> = {
	create: () -> T,
	reset: ((item: T) -> ())?, -- called on release, before the item is stored
	destroy: ((item: T) -> ())?, -- called for items that do not fit and on clear
	max: number?, -- idle items kept (default 32)
}

export type Stats = { idle: number, live: number, created: number, reused: number, discarded: number }

export type Pool<T> = {
	acquire: (self: Pool<T>) -> T,
	release: (self: Pool<T>, item: T) -> (),
	prewarm: (self: Pool<T>, count: number) -> (),
	clear: (self: Pool<T>) -> (),
	stats: (self: Pool<T>) -> Stats,
}

local Pool = {}

function Pool.new<T>(options: Options<T>): Pool<T>
	local idle: { T } = {}
	local live: { [any]: boolean } = {}
	local liveCount = 0
	local created, reused, discarded = 0, 0, 0
	local max = math.max(0, options.max or 32)

	local function discard(item: T)
		discarded += 1
		if options.destroy then
			options.destroy(item)
		end
	end

	return {
		acquire = function(_self: Pool<T>): T
			local item = table.remove(idle)
			if item == nil then
				item = options.create()
				created += 1
			else
				reused += 1
			end
			live[item] = true
			liveCount += 1
			return item :: T
		end,
		-- Releasing an item twice, or one the pool never handed out, is ignored.
		release = function(_self: Pool<T>, item: T)
			if not live[item] then
				return
			end
			live[item] = nil
			liveCount -= 1
			if options.reset then
				options.reset(item)
			end
			if #idle < max then
				table.insert(idle, item)
			else
				discard(item)
			end
		end,
		prewarm = function(_self: Pool<T>, count: number)
			for _ = 1, math.min(count, max) - #idle do
				created += 1
				table.insert(idle, options.create())
			end
		end,
		clear = function(_self: Pool<T>)
			for _, item in idle do
				discard(item)
			end
			table.clear(idle)
		end,
		stats = function(_self: Pool<T>): Stats
			return { idle = #idle, live = liveCount, created = created, reused = reused, discarded = discarded }
		end,
	}
end

return Pool
