--!strict
-- Trove — collects things that need cleaning up and disposes them all at once.
--
-- Every activity/event run gets its own Trove; when the run ends the framework calls
-- `trove:Clean()` and every connection, instance, thread, and teardown callback added
-- to it is released. This is what guarantees the GDD's "cleanup/reset" lifecycle step
-- actually reverts the world, even if an activity errors partway through.
--
-- Accepts: Instances (Destroy), RBXScriptConnections / Signal.Connection (Disconnect),
-- threads (task.cancel), functions (called), and tables with a Destroy/Disconnect method.

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _objects: { any }, _cleaned: boolean }, Trove))

local cleanupObject -- forward declaration; defined below, used by both Add and Clean.

function Trove.new(): Trove
	return setmetatable({
		_objects = {},
		_cleaned = false,
	}, Trove)
end

-- Track an object for later cleanup and return it (so you can inline `local x = trove:Add(...)`).
--
-- Adding to an already-cleaned trove disposes the object IMMEDIATELY instead of storing it.
-- This is deliberate: a run's trove is cleaned exactly once when the run ends, so anything that
-- arrives afterwards belongs to a run that no longer exists. Without this, a `task.delay` that
-- fires past the activity timer would happily hand the trove a Tool it never destroys, and that
-- Tool would follow the player into the next activity (the Hide & Seek "Tag!" bug).
function Trove:Add<T>(object: T): T
	if self._cleaned then
		cleanupObject(object)
		return object
	end
	table.insert(self._objects, object)
	return object
end

-- Convenience: construct `class.new(...)`, track it, return it.
function Trove:Construct(class: { new: (...any) -> any }, ...: any): any
	local object = class.new(...)
	return self:Add(object)
end

-- Connect to a signal (Roblox or custom) and track the connection.
function Trove:Connect(signal: any, callback: (...any) -> ()): any
	return self:Add(signal:Connect(callback))
end

-- Track a plain teardown function.
function Trove:AddCleanup(callback: () -> ()): () -> ()
	return self:Add(callback)
end

-- Assigns the forward-declared local above (Lua resolves the name lexically), so `Add` can
-- dispose late arrivals with the exact same logic `Clean` uses.
function cleanupObject(object: any)
	local objType = typeof(object)
	if objType == "Instance" then
		object:Destroy()
	elseif objType == "RBXScriptConnection" then
		object:Disconnect()
	elseif objType == "function" then
		object()
	elseif objType == "thread" then
		pcall(task.cancel, object)
	elseif objType == "table" then
		if typeof(object.Destroy) == "function" then
			object:Destroy()
		elseif typeof(object.Disconnect) == "function" then
			object:Disconnect()
		end
	end
end

-- Clean up everything, most-recent first (reverse order mirrors construction order).
function Trove:Clean()
	self._cleaned = true
	local objects = self._objects
	for i = #objects, 1, -1 do
		cleanupObject(objects[i])
		objects[i] = nil
	end
end

-- Alias used in some call sites.
function Trove:Destroy()
	self:Clean()
end

return Trove
