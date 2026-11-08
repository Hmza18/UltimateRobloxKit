--!strict
-- Observable client-side state tree addressed by dotted paths ("Stats.Cash"). Pure Luau.
--
-- * Values are deep-copied and frozen on write, so readers can never mutate shared state.
-- * Writes are copy-on-write (see Path), so a subscriber fires only when the value at its own
--   path changed: ancestors and descendants of a written path are notified, siblings are not.
-- * Notifications are batched: inside store:batch(fn) every subscriber fires at most once, with
--   the final value. Pass `scheduler` (task.defer on Roblox) to also coalesce writes made outside
--   a batch until the scheduler runs; without it, notifications are synchronous.
--
-- The store is a view of game state for the UI. The server stays authoritative; feed the store
-- from attributes or replicated values (see Runtime/StoreAdapter) rather than writing results.

local Path = require("./Path")

export type Listener = (newValue: any, oldValue: any, path: string) -> ()
export type Scheduler = (callback: () -> ()) -> ()

export type Options = { scheduler: Scheduler?, onError: ((message: string) -> ())? }

export type Store = {
	get: (self: Store, path: string?) -> any,
	set: (self: Store, path: string, value: any) -> (),
	update: (self: Store, path: string, transform: (current: any) -> any) -> (),
	merge: (self: Store, path: string, values: { [string]: any }) -> (),
	subscribe: (self: Store, path: string, listener: Listener) -> () -> (),
	observe: (self: Store, path: string, listener: Listener) -> () -> (),
	batch: (self: Store, callback: () -> ()) -> (),
	flush: (self: Store) -> number,
	isPending: (self: Store) -> boolean,
	subscriberCount: (self: Store) -> number,
	destroy: (self: Store) -> (),
}

type Subscription = { path: string, segments: Path.Segments, listener: Listener, active: boolean }

local MAX_FLUSH_PASSES = 100

local Store = {}

local function freezeDeep(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	local copy: { [any]: any } = {}
	for key, item in value do
		copy[key] = freezeDeep(item)
	end
	return table.freeze(copy)
end

Store.freezeDeep = freezeDeep

function Store.new(initial: { [string]: any }?, options: Options?): Store
	local opts: Options = options or {}
	local scheduler = opts.scheduler
	local onError = opts.onError

	local root: any = freezeDeep(initial or {})
	local before: any = nil -- the root as it was before the first unflushed write
	local subscriptions: { Subscription } = {}
	local batchDepth = 0
	local flushScheduled = false
	local flushing = false
	local destroyed = false

	local function notifyOnce(snapshot: any): (number, string?)
		local notified = 0
		local firstError: string? = nil
		for _, subscription in table.clone(subscriptions) do
			if subscription.active then
				local oldValue = Path.getSegments(snapshot, subscription.segments)
				local newValue = Path.getSegments(root, subscription.segments)
				if oldValue ~= newValue then
					notified += 1
					local ok, err = pcall(subscription.listener, newValue, oldValue, subscription.path)
					if not ok then
						local message = tostring(err)
						local handler = onError
						if handler then
							handler(message)
						elseif firstError == nil then
							firstError = message
						end
					end
				end
			end
		end
		return notified, firstError
	end

	local function flushNow(): number
		if flushing then
			-- A listener wrote during a flush; the running flush picks the write up in its next pass.
			return 0
		end
		flushing = true
		local total = 0
		local firstError: string? = nil
		local passes = 0
		while before ~= nil do
			passes += 1
			if passes > MAX_FLUSH_PASSES then
				before = nil
				firstError = firstError or "Store: listeners kept writing; stopped after 100 passes"
				break
			end
			local snapshot = before
			before = nil
			local count, err = notifyOnce(snapshot)
			total += count
			if err and firstError == nil then
				firstError = err
			end
		end
		flushing = false
		if firstError then
			error(firstError, 0)
		end
		return total
	end

	local function requestFlush()
		if batchDepth > 0 or flushing then
			return
		end
		if scheduler then
			if not flushScheduled then
				flushScheduled = true
				scheduler(function()
					flushScheduled = false
					if not destroyed then
						flushNow()
					end
				end)
			end
		else
			flushNow()
		end
	end

	local function write(segments: Path.Segments, value: any)
		assert(not destroyed, "Store: used after destroy")
		if type(value) ~= "table" and Path.getSegments(root, segments) == value then
			return
		end
		if before == nil then
			before = root
		end
		if #segments == 0 then
			root = freezeDeep(if type(value) == "table" then value else {})
		else
			root = Path.setSegments(root, segments, freezeDeep(value), true)
		end
		requestFlush()
	end

	local store: Store = {
		get = function(_self: Store, path: string?): any
			if path == nil or path == "" then
				return root
			end
			return Path.get(root, path)
		end,

		set = function(_self: Store, path: string, value: any)
			write(Path.parse(path), value)
		end,

		update = function(_self: Store, path: string, transform: (current: any) -> any)
			local segments = Path.parse(path)
			write(segments, transform(Path.getSegments(root, segments)))
		end,

		merge = function(self: Store, path: string, values: { [string]: any })
			self:batch(function()
				for key, value in values do
					write(Path.parse(Path.child(path, key)), value)
				end
			end)
		end,

		subscribe = function(_self: Store, path: string, listener: Listener): () -> ()
			assert(type(listener) == "function", "Store.subscribe needs a listener function")
			local subscription: Subscription = {
				path = path,
				segments = Path.parse(path),
				listener = listener,
				active = true,
			}
			table.insert(subscriptions, subscription)
			local function unsubscribe()
				if not subscription.active then
					return
				end
				subscription.active = false
				local index = table.find(subscriptions, subscription)
				if index then
					table.remove(subscriptions, index)
				end
			end
			return unsubscribe
		end,

		-- Like subscribe, but also calls the listener straight away with the current value.
		observe = function(self: Store, path: string, listener: Listener): () -> ()
			local unsubscribe = self:subscribe(path, listener)
			listener(Path.get(root, path), nil, path)
			return unsubscribe
		end,

		batch = function(_self: Store, callback: () -> ())
			batchDepth += 1
			local ok, err = pcall(callback)
			batchDepth -= 1
			if batchDepth == 0 and before ~= nil then
				requestFlush()
			end
			if not ok then
				error(err, 0)
			end
		end,

		flush = function(_self: Store): number
			return flushNow()
		end,

		isPending = function(_self: Store): boolean
			return before ~= nil
		end,

		subscriberCount = function(_self: Store): number
			return #subscriptions
		end,

		destroy = function(_self: Store)
			destroyed = true
			for _, subscription in subscriptions do
				subscription.active = false
			end
			table.clear(subscriptions)
			before = nil
		end,
	}
	return store
end

-- Maps an attribute name to a store path. With `nest` (for example "_"), "Upgrades_Speed" becomes
-- "Upgrades.Speed". Returns nil when the result is not a valid path.
function Store.attributePath(prefix: string, attributeName: string, nest: string?): string?
	local relative = attributeName
	if nest ~= nil and nest ~= "" then
		relative = table.concat(string.split(attributeName, nest), ".")
	end
	local full = Path.child(prefix, relative)
	if not Path.isValid(full) then
		return nil
	end
	return full
end

return Store
