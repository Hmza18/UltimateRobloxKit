--!strict
-- Minimal typed signal. Handlers run in new threads so one erroring or yielding
-- handler does not break the others.

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	wait: (self: Signal<T...>) -> T...,
	destroy: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { [Connection]: (T...) -> () } = {}
	local self = {} :: Signal<T...>

	function self.connect(_, fn: (T...) -> ()): Connection
		local conn = { connected = true } :: Connection
		function conn.disconnect(c: Connection)
			c.connected = false
			handlers[c] = nil
		end
		handlers[conn] = fn
		return conn
	end

	function self.once(s: Signal<T...>, fn: (T...) -> ()): Connection
		local conn: Connection
		conn = s:connect(function(...: T...)
			conn:disconnect()
			fn(...)
		end)
		return conn
	end

	function self.fire(_, ...: T...)
		for conn, fn in table.clone(handlers) do
			if conn.connected then
				task.spawn(fn, ...)
			end
		end
	end

	function self.wait(s: Signal<T...>): T...
		local thread = coroutine.running()
		s:once(function(...: T...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.destroy(_)
		for conn in handlers do
			conn.connected = false
		end
		table.clear(handlers)
	end

	return self
end

return Signal
