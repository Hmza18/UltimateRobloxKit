--!strict
-- Minimal signal for events between modules on the same machine. Use Net for client-server events.
-- Handlers run in their own threads, so one handler that errors or yields never blocks the others.

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

type Listener = { connection: Connection, handler: (...any) -> () }

local Signal = {}

function Signal.new(): Signal
	local listeners: { Listener } = {}

	local function connectHandler(_self: Signal, handler: (...any) -> ()): Connection
		local connection: Connection = {
			Connected = true,
			Disconnect = function(self: Connection)
				if not self.Connected then
					return
				end
				self.Connected = false
				for index, listener in listeners do
					if listener.connection == self then
						table.remove(listeners, index)
						break
					end
				end
			end,
		}
		table.insert(listeners, { connection = connection, handler = handler })
		return connection
	end

	local function onceHandler(self: Signal, handler: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...: any)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	local function fireAll(_self: Signal, ...: any)
		-- Iterate a copy so handlers can connect or disconnect while firing.
		for _, listener in table.clone(listeners) do
			if listener.connection.Connected then
				task.spawn(listener.handler, ...)
			end
		end
	end

	local function waitForFire(self: Signal): ...any
		local thread = coroutine.running()
		self:Once(function(...: any)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	local function disconnectAllListeners(_self: Signal)
		for _, listener in table.clone(listeners) do
			listener.connection:Disconnect()
		end
	end

	return {
		Connect = connectHandler,
		Once = onceHandler,
		Fire = fireAll,
		Wait = waitForFire,
		DisconnectAll = disconnectAllListeners,
	}
end

return Signal
