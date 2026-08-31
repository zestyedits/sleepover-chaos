--!strict
-- Signal — a tiny, self-contained event object.
--
-- Roblox's built-in BindableEvents work across the network boundary and copy their
-- arguments; for in-process game logic we want cheap, reference-preserving signals.
-- This implementation is intentionally minimal (connect / once / fire / destroy) and
-- has no external dependencies so the repo runs without a package install step.

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type ConnectionImpl = {
	Connected: boolean,
	_signal: any,
	_callback: (...any) -> (),
	Disconnect: (self: any) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.new(signal: any, callback: (...any) -> ()): ConnectionImpl
	local self = setmetatable({
		Connected = true,
		_signal = signal,
		_callback = callback,
	}, Connection)
	return (self :: any) :: ConnectionImpl
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local connections = self._signal._connections
	local index = table.find(connections, self)
	if index then
		table.remove(connections, index)
	end
end

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_connections = {},
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(callback: (...any) -> ()): any
	local connection = Connection.new(self, callback)
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(callback: (...any) -> ()): any
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Iterate a snapshot so a handler that disconnects/connects mid-fire is safe.
	local snapshot = table.clone(self._connections)
	for _, connection in snapshot do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._connections) do
		connection.Connected = false
	end
	table.clear(self._connections)
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
