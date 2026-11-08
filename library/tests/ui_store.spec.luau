--!strict
-- Path and Store: dotted paths, copy-on-write, subscriptions and batching.

local t = require("./lib/t")
local Path = require("../src/UI/Core/Path")
local Store = require("../src/UI/Core/Store")

return {
	["Path.parse splits and validates"] = function()
		t.deepEqual(Path.parse("Stats.Cash"), { "Stats", "Cash" })
		t.deepEqual(Path.parse(""), {})
		t.falsy(Path.isValid("Stats..Cash"), "empty segment")
		t.falsy(Path.isValid("Stats.Ca$h"), "bad character")
		t.falsy(Path.isValid(42), "not a string")
		t.throws(function()
			Path.parse("a..b")
		end)
	end,

	["Path.get reads nested values and array slots"] = function()
		local tree = { Stats = { Cash = 10 }, Inventory = { { Name = "Sword" }, { Name = "Shield" } } }
		t.equal(Path.get(tree, "Stats.Cash"), 10)
		t.equal(Path.get(tree, "Inventory.2.Name"), "Shield")
		t.equal(Path.get(tree, "Stats.Missing.Deep"), nil)
		t.equal(Path.get(tree, "Stats.Cash.More"), nil, "cannot index a number")
	end,

	["Path.set copies only the written branch"] = function()
		local tree = { Stats = { Cash = 1 }, Settings = { Music = true } }
		local nextTree = Path.set(tree, "Stats.Cash", 5)
		t.equal(tree.Stats.Cash, 1, "input untouched")
		t.equal(Path.get(nextTree, "Stats.Cash"), 5)
		t.truthy(nextTree.Settings == tree.Settings, "sibling branch keeps its identity")
		t.truthy(nextTree.Stats ~= tree.Stats, "written branch is a copy")
	end,

	["Path.isPrefix compares segments"] = function()
		t.truthy(Path.isPrefix(Path.parse("Stats"), Path.parse("Stats.Cash")))
		t.truthy(Path.isPrefix(Path.parse(""), Path.parse("Stats")))
		t.falsy(Path.isPrefix(Path.parse("Stats.Cash"), Path.parse("Stats")))
		t.falsy(Path.isPrefix(Path.parse("Stat"), Path.parse("Stats.Cash")))
	end,

	["Store get and set by path"] = function()
		local store = Store.new({ Stats = { Cash = 0 } })
		store:set("Stats.Cash", 250)
		store:set("Stats.Gems", 3)
		t.equal(store:get("Stats.Cash"), 250)
		t.equal(store:get("Stats.Gems"), 3)
		t.equal(store:get().Stats.Cash, 250)
	end,

	["Store values are frozen copies"] = function()
		local source = { Name = "Sword", Tags = { "rare" } }
		local store = Store.new()
		store:set("Item", source)
		source.Name = "Changed"
		t.equal(store:get("Item.Name"), "Sword", "later edits to the source do not leak in")
		t.throws(function()
			local item = store:get("Item")
			item.Name = "Hacked"
		end)
	end,

	["Store notifies exact, ancestor and descendant subscribers but not siblings"] = function()
		local store = Store.new({ Stats = { Cash = 1, Gems = 1 } })
		local calls: { [string]: number } = { cash = 0, stats = 0, gems = 0, root = 0 }
		store:subscribe("Stats.Cash", function()
			calls.cash += 1
		end)
		store:subscribe("Stats", function()
			calls.stats += 1
		end)
		store:subscribe("Stats.Gems", function()
			calls.gems += 1
		end)
		store:subscribe("", function()
			calls.root += 1
		end)
		store:set("Stats.Cash", 2)
		t.deepEqual(calls, { cash = 1, stats = 1, gems = 0, root = 1 })
		store:set("Stats", { Cash = 2, Gems = 9 })
		t.equal(calls.gems, 1, "replacing the parent notifies the changed child")
		t.equal(calls.cash, 1, "unchanged child value is not notified")
	end,

	["Store passes new and old values"] = function()
		local store = Store.new({ Stats = { Cash = 5 } })
		local seenNew: any, seenOld: any, seenPath: any = nil, nil, nil
		store:subscribe("Stats.Cash", function(newValue, oldValue, path)
			seenNew, seenOld, seenPath = newValue, oldValue, path
		end)
		store:set("Stats.Cash", 8)
		t.equal(seenNew, 8)
		t.equal(seenOld, 5)
		t.equal(seenPath, "Stats.Cash")
	end,

	["Store skips writes that do not change a primitive"] = function()
		local store = Store.new({ Level = 3 })
		local count = 0
		store:subscribe("Level", function()
			count += 1
		end)
		store:set("Level", 3)
		t.equal(count, 0)
		t.falsy(store:isPending())
	end,

	["Store batch notifies once with the final value"] = function()
		local store = Store.new({ Cash = 0 })
		local values: { number } = {}
		store:subscribe("Cash", function(value)
			table.insert(values, value)
		end)
		store:batch(function()
			store:set("Cash", 1)
			store:set("Cash", 2)
			store:set("Cash", 3)
		end)
		t.deepEqual(values, { 3 })
	end,

	["Store batch that ends where it began notifies nobody"] = function()
		local store = Store.new({ Cash = 7 })
		local count = 0
		store:subscribe("Cash", function()
			count += 1
		end)
		store:batch(function()
			store:set("Cash", 8)
			store:set("Cash", 7)
		end)
		t.equal(count, 0)
	end,

	["Store with a scheduler defers until flush"] = function()
		local queued: { () -> () } = {}
		local store = Store.new({ Cash = 0 }, {
			scheduler = function(callback: () -> ())
				table.insert(queued, callback)
			end,
		})
		local count = 0
		store:subscribe("Cash", function()
			count += 1
		end)
		store:set("Cash", 1)
		store:set("Cash", 2)
		t.equal(count, 0, "nothing before the scheduler runs")
		t.equal(#queued, 1, "one scheduled flush for many writes")
		queued[1]()
		t.equal(count, 1)
	end,

	["Store unsubscribe and observe"] = function()
		local store = Store.new({ Cash = 1 })
		local seen: { any } = {}
		local stop = store:observe("Cash", function(value)
			table.insert(seen, value)
		end)
		t.deepEqual(seen, { 1 }, "observe calls straight away")
		store:set("Cash", 2)
		stop()
		stop()
		store:set("Cash", 3)
		t.deepEqual(seen, { 1, 2 })
		t.equal(store:subscriberCount(), 0)
	end,

	["Store listener errors do not stop other listeners"] = function()
		local errors: { string } = {}
		local store = Store.new({ Cash = 0 }, {
			onError = function(message: string)
				table.insert(errors, message)
			end,
		})
		local reached = false
		store:subscribe("Cash", function()
			error("boom")
		end)
		store:subscribe("Cash", function()
			reached = true
		end)
		store:set("Cash", 1)
		t.truthy(reached)
		t.equal(#errors, 1)
	end,

	["Store listener writes are flushed in a later pass"] = function()
		local store = Store.new({ Cash = 0, Doubled = 0 })
		store:subscribe("Cash", function(value)
			store:set("Doubled", value * 2)
		end)
		local doubled: any = nil
		store:subscribe("Doubled", function(value)
			doubled = value
		end)
		store:set("Cash", 21)
		t.equal(doubled, 42)
	end,

	["Store merge writes several keys in one batch"] = function()
		local store = Store.new()
		local count = 0
		store:subscribe("Stats", function()
			count += 1
		end)
		store:merge("Stats", { Cash = 5, Gems = 2 })
		t.equal(store:get("Stats.Gems"), 2)
		t.equal(count, 1)
	end,

	["Store.attributePath maps attribute names"] = function()
		t.equal(Store.attributePath("Stats", "Cash"), "Stats.Cash")
		t.equal(Store.attributePath("Stats", "Upgrades_Speed", "_"), "Stats.Upgrades.Speed")
		t.equal(Store.attributePath("", "Cash"), "Cash")
		t.equal(Store.attributePath("Stats", "Bad__Name", "_"), nil, "empty segment")
	end,
}
