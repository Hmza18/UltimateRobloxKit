--!strict
-- Holds the running UrkUI context so components created with code can reach the theme, router,
-- toasts and other services without passing them around. Set by UrkUI.start, cleared by stop.

local Context = {}

local current: any = nil

function Context.set(context: any)
	current = context
end

-- The running context. Raises a clear error when UrkUI.start() has not been called yet.
function Context.get(): any
	assert(current ~= nil, "UrkUI is not running: call UrkUI.start() on the client first")
	return current
end

-- The running context or nil.
function Context.peek(): any
	return current
end

return Context
