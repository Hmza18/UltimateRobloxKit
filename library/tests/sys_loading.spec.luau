--!strict
local Loading = require("../src/Systems/Loading/LoadingLogic")
local t = require("./lib/t")

local CONFIG = Loading.resolveConfig({ minDisplayTime = 2, skipAfter = 5, maxWait = 30, allowSkip = true })

return {
	["resolveConfig validates values"] = function()
		local config = Loading.resolveConfig({ batchSize = 0, maxWait = -1, allowSkip = "yes", displaySpeed = 4 })
		t.equal(config.batchSize, 10)
		t.equal(config.maxWait, 30)
		t.equal(config.allowSkip, true)
		t.equal(config.displaySpeed, 4)
		t.equal(Loading.resolveConfig({ allowSkip = false }).allowSkip, false)
	end,

	["batches split items in order"] = function()
		local items = {}
		for index = 1, 25 do
			table.insert(items, index)
		end
		local batches = Loading.batches(items, 10)
		t.equal(#batches, 3)
		t.equal(#batches[1], 10)
		t.equal(#batches[3], 5)
		t.equal(batches[3][5], 25)
		t.equal(#Loading.batches({}, 10), 0)
		t.equal(#Loading.batches({ "a", "b" }, 0), 2, "batch size is at least one")
	end,

	["progress counts loaded and failed assets"] = function()
		local tracker = Loading.newTracker(4, 0)
		t.equal(Loading.progress(tracker), 0)
		Loading.markLoaded(tracker, 2, 1)
		t.equal(Loading.progress(tracker), 0.5)
		t.falsy(Loading.isLoaded(tracker))
		Loading.markFailed(tracker, 1, 2)
		Loading.markLoaded(tracker, 5, 3)
		t.equal(tracker.loaded, 3, "counts never exceed the total")
		t.equal(tracker.failed, 1)
		t.equal(Loading.progress(tracker), 1)
		t.equal(tracker.finishedAt, 3)
		Loading.markLoaded(tracker, 1, 9)
		t.equal(tracker.finishedAt, 3, "the finish time is kept")
	end,

	["an empty asset list is loaded at once"] = function()
		local tracker = Loading.newTracker(0, 7)
		t.truthy(Loading.isLoaded(tracker))
		t.equal(Loading.progress(tracker), 1)
		t.equal(Loading.newTracker(-3, 0).total, 0)
		local odd = Loading.newTracker(2, 0)
		Loading.markLoaded(odd, math.sqrt(-1), 1)
		t.equal(odd.loaded, 0)
	end,

	["weighted stages"] = function()
		t.near(Loading.weighted({ { weight = 1, progress = 1 }, { weight = 3, progress = 0.5 } }), 0.625)
		t.equal(Loading.weighted({}), 1)
		t.near(Loading.weighted({ { weight = 1, progress = 2 }, { weight = 0, progress = 0 } }), 1)
	end,

	["the shown bar eases forward and never back"] = function()
		t.near(Loading.displayProgress(0, 1, 0.1, 2), 0.2)
		t.equal(Loading.displayProgress(0.9, 1, 1, 2), 1)
		t.equal(Loading.displayProgress(0.6, 0.4, 1, 2), 0.6)
		t.equal(Loading.displayProgress(0.5, 3, 10, 1), 1)
	end,

	["the minimum display time holds the screen"] = function()
		local tracker = Loading.newTracker(1, 0)
		t.equal(Loading.status(tracker, 0.5, CONFIG), "loading")
		Loading.markLoaded(tracker, 1, 0.5)
		t.equal(Loading.status(tracker, 1, CONFIG), "ready")
		t.falsy(Loading.shouldDismiss(tracker, 1, CONFIG))
		t.equal(Loading.status(tracker, 2, CONFIG), "done")
		t.truthy(Loading.shouldDismiss(tracker, 2, CONFIG))
	end,

	["skip is offered after skipAfter"] = function()
		local tracker = Loading.newTracker(10, 0)
		t.falsy(Loading.canSkip(tracker, 4.9, CONFIG))
		t.falsy(Loading.skip(tracker, 4.9, CONFIG))
		t.truthy(Loading.canSkip(tracker, 5, CONFIG))
		t.truthy(Loading.skip(tracker, 5, CONFIG))
		t.falsy(Loading.skip(tracker, 6, CONFIG), "only once")
		t.equal(Loading.status(tracker, 6, CONFIG), "skipped")
		t.truthy(Loading.shouldDismiss(tracker, 6, CONFIG))
		local noSkip = Loading.resolveConfig({ allowSkip = false })
		t.falsy(Loading.canSkip(Loading.newTracker(1, 0), 100, noSkip))
	end,

	["slow loads time out"] = function()
		local tracker = Loading.newTracker(5, 0)
		t.falsy(Loading.timedOut(tracker, 29, CONFIG))
		t.equal(Loading.status(tracker, 30, CONFIG), "timeout")
		local forever = Loading.resolveConfig({ maxWait = 0 })
		t.equal(Loading.status(tracker, 1000, forever), "loading")
	end,

	["formatPercent"] = function()
		t.equal(Loading.formatPercent(0.426), "42%")
		t.equal(Loading.formatPercent(1), "100%")
		t.equal(Loading.formatPercent(-1), "0%")
		t.equal(Loading.formatPercent(math.sqrt(-1)), "0%")
	end,
}
