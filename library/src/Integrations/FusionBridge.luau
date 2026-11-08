--!strict
-- Connects UrkUI's Store (UI/Core/Store) to Fusion 0.3 (Daniel P H Fox, MIT, Wally
-- "elttob/fusion@0.3.0"), so a project can build screens in Fusion while the kit's systems keep
-- writing to one Store. No Roblox globals: Fusion is passed in, so Lune can test this with a fake.
--
--   local Fusion = require(game.ReplicatedStorage.Packages.Fusion)
--   local scope = Fusion.scoped(Fusion)
--   local coins = FusionBridge.value(scope, store, "currency.Coins", 0)
--   scope:New "TextLabel" { Text = scope:Computed(function(use) return tostring(use(coins)) end) }
--
-- `value` follows the Store (one way). `twoWay` also writes Fusion changes back to the Store, for
-- settings toggles and sliders that the client owns. Never write server-owned values from the
-- client; send an intent to the server instead.

export type StoreLike = {
	get: (self: any, path: string?) -> any,
	set: (self: any, path: string, value: any) -> (),
	observe: (self: any, path: string, listener: (newValue: any, oldValue: any, path: string) -> ()) -> () -> (),
}

local FusionBridge = {}

-- Fusion 0.3 scopes are arrays of cleanup tasks; a function in the scope runs on doCleanup.
local function addCleanup(scope: any, cleanup: () -> ())
	table.insert(scope, cleanup)
end

-- A Fusion Value that mirrors `store` at `path`. `default` is used while the path is nil.
function FusionBridge.value(scope: any, store: StoreLike, path: string, default: any?): any
	local initial = store:get(path)
	local fusionValue = scope:Value(if initial == nil then default else initial)
	local unsubscribe = store:observe(path, function(newValue: any)
		fusionValue:set(if newValue == nil then default else newValue)
	end)
	addCleanup(scope, unsubscribe)
	return fusionValue
end

-- Like `value`, but Fusion-side changes are written to the Store as well. Loops are prevented by
-- comparing against the Store's current value before writing.
function FusionBridge.twoWay(scope: any, store: StoreLike, path: string, default: any?): any
	local fusionValue = FusionBridge.value(scope, store, path, default)
	local observer = scope:Observer(fusionValue)
	local disconnect = observer:onChange(function()
		local current = FusionBridge.peek(scope, fusionValue)
		if store:get(path) ~= current then
			store:set(path, current)
		end
	end)
	if type(disconnect) == "function" then
		addCleanup(scope, disconnect)
	end
	return fusionValue
end

-- Several paths at once: { coins = "currency.Coins", gems = "currency.Gems" } -> { coins = Value, ... }
function FusionBridge.values(scope: any, store: StoreLike, paths: { [string]: string }): { [string]: any }
	local result: { [string]: any } = {}
	for key, path in paths do
		result[key] = FusionBridge.value(scope, store, path)
	end
	return result
end

-- Reads a Fusion state object without tracking. Uses scope.peek when the scope inherited Fusion's
-- methods, otherwise the object's own :get() for older or fake implementations.
function FusionBridge.peek(scope: any, state: any): any
	if type(scope.peek) == "function" then
		local peek: (any) -> any = scope.peek
		return peek(state)
	end
	return state:get()
end

return FusionBridge
