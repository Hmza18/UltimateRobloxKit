--!strict
-- FusionBridge against the real UrkUI Store and a minimal fake of Fusion 0.3's scope API.
local FusionBridge = require("../src/Integrations/FusionBridge")
local Store = require("../src/UI/Core/Store")
local t = require("./lib/t")

local function fakeScope(): any
	local scope: any = {}
	function scope.Value(_self: any, initial: any)
		local state: any = { value = initial, listeners = {} }
		function state.get(self: any)
			return self.value
		end
		function state.set(self: any, v: any)
			self.value = v
			for _, l in self.listeners do
				l()
			end
		end
		return state
	end
	function scope.Observer(_self: any, state: any)
		return {
			onChange = function(_: any, fn: () -> ())
				table.insert(state.listeners, fn)
				return function()
					local i = table.find(state.listeners, fn)
					if i then
						table.remove(state.listeners, i)
					end
				end
			end,
		}
	end
	return scope
end

local function syncStore(): any
	return Store.new({ currency = { Coins = 5 } }, {
		scheduler = function(callback: () -> ())
			callback()
		end,
	})
end

return {
	["value mirrors the store and cleans up"] = function()
		local store = syncStore()
		local scope = fakeScope()
		local coins = FusionBridge.value(scope, store, "currency.Coins", 0)
		t.equal(coins:get(), 5)
		store:set("currency.Coins", 9)
		store:flush()
		t.equal(coins:get(), 9)
		local gems = FusionBridge.value(scope, store, "currency.Gems", 0)
		t.equal(gems:get(), 0, "default while nil")
		t.equal(#scope, 2, "one cleanup per bridged value")
		for _, cleanup in scope do
			cleanup()
		end
		store:set("currency.Coins", 1)
		store:flush()
		t.equal(coins:get(), 9, "no updates after cleanup")
	end,

	["twoWay writes Fusion changes back"] = function()
		local store = syncStore()
		local scope = fakeScope()
		local music = FusionBridge.twoWay(scope, store, "settings.music", true)
		music:set(false)
		store:flush()
		t.equal(store:get("settings.music"), false)
		store:set("settings.music", true)
		store:flush()
		t.equal(music:get(), true)
	end,
}
