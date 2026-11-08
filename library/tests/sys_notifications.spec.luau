--!strict
local Notifications = require("../src/Systems/Notifications/NotificationsLogic")
local t = require("./lib/t")

local function newQueue(overrides: { [string]: any }?): any
	local config: { [string]: any } = { dedupeWindow = 3, maxQueue = 10, maxAge = 30 }
	for key, value in overrides or {} do
		config[key] = value
	end
	return Notifications.newQueue(Notifications.resolveConfig(config))
end

local function texts(queue: any, now: number): { string }
	local out: { string } = {}
	local note = Notifications.pop(queue, now)
	while note do
		table.insert(out, note.text)
		note = Notifications.pop(queue, now)
	end
	return out
end

return {
	["resolveConfig keeps valid types and fills defaults"] = function()
		local config = Notifications.resolveConfig({
			types = { alert = { priority = 9, duration = -1 }, broken = { priority = "high" } },
			defaultType = "plain",
			maxQueue = 0,
		})
		t.equal(config.types.alert.priority, 9)
		t.equal(config.types.alert.duration, 0)
		t.equal(config.types.broken, nil)
		t.truthy(config.types.plain, "the default type always exists")
		t.equal(config.maxQueue, 20)
		t.equal(Notifications.resolveConfig().types.error.priority, 5)
	end,

	["truncate respects UTF-8 and adds an ellipsis"] = function()
		t.equal(Notifications.truncate("hello", 10), "hello")
		t.equal(Notifications.truncate("hello world!", 10), "hello w...")
		t.equal(Notifications.truncate("ééééé", 4), "é...")
		t.equal(Notifications.truncate("abcdef", 2), "..")
		t.equal(Notifications.truncate("\255", 10), nil)
	end,

	["normalize validates and fills in fields"] = function()
		local config = Notifications.resolveConfig({ maxTitleLength = 5 })
		local note = Notifications.normalize({ text = "Hi", title = "Welcome!", kind = "nope", data = 7 }, config, 4, 1)
		t.truthy(note)
		if note then
			t.equal(note.kind, "info")
			t.equal(note.title, "We...")
			t.equal(note.priority, 1)
			t.equal(note.duration, 4)
			t.equal(note.data, 7)
			t.equal(note.createdAt, 4)
		end
		local override = { text = "x", kind = "error", priority = 50, duration = 1 }
		local custom = Notifications.normalize(override, config, 0, 2)
		t.equal(custom and custom.priority, 50)
		t.equal(custom and custom.duration, 1)
		t.equal(select(2, Notifications.normalize({ text = "   " }, config, 0, 1)), "text is empty or invalid")
		t.equal(select(2, Notifications.normalize({ text = 5 }, config, 0, 1)), "text must be a string")
		local badTitle = { text = "ok", title = 1 }
		t.equal(select(2, Notifications.normalize(badTitle, config, 0, 1)), "title must be a string")
		t.equal(select(2, Notifications.normalize(nil, config, 0, 1)), "text must be a string")
	end,

	["pop returns highest priority then oldest"] = function()
		local queue = newQueue()
		Notifications.push(queue, { text = "a", kind = "info" }, 0)
		Notifications.push(queue, { text = "b", kind = "error" }, 1)
		Notifications.push(queue, { text = "c", kind = "warning" }, 2)
		Notifications.push(queue, { text = "d", kind = "error" }, 3)
		t.equal(Notifications.size(queue), 4)
		t.equal(Notifications.peek(queue, 3).text, "b")
		t.deepEqual(texts(queue, 3), { "b", "d", "c", "a" })
		t.equal(Notifications.pop(queue, 3), nil)
	end,

	["duplicates inside the window are merged"] = function()
		local queue = newQueue()
		t.truthy(Notifications.push(queue, { text = "Saved" }, 0))
		local ok, reason = Notifications.push(queue, { text = "Saved" }, 1)
		t.falsy(ok)
		t.equal(reason, "duplicate")
		t.equal(queue.items[1].count, 2)
		t.truthy(Notifications.push(queue, { text = "Saved" }, 3.5), "accepted again after the window")
		t.equal(Notifications.size(queue), 2)
	end,

	["explicit keys dedupe different texts"] = function()
		local queue = newQueue()
		t.truthy(Notifications.push(queue, { text = "+5 coins", key = "coins" }, 0))
		t.equal(select(2, Notifications.push(queue, { text = "+10 coins", key = "coins" }, 1)), "duplicate")
		t.truthy(Notifications.push(queue, { text = "+5 coins", kind = "reward" }, 1), "a different key")
	end,

	["a full queue keeps the most important"] = function()
		local queue = newQueue({ maxQueue = 3 })
		Notifications.push(queue, { text = "1" }, 0)
		Notifications.push(queue, { text = "2" }, 0)
		Notifications.push(queue, { text = "3", kind = "success" }, 0)
		t.truthy(Notifications.push(queue, { text = "4", kind = "warning" }, 0))
		t.equal(select(2, Notifications.push(queue, { text = "5" }, 0)), "queue full")
		t.deepEqual(texts(queue, 0), { "4", "3", "2" })
	end,

	["old notifications expire"] = function()
		local queue = newQueue()
		Notifications.push(queue, { text = "stale" }, 0)
		Notifications.push(queue, { text = "fresh" }, 20)
		t.deepEqual(texts(queue, 31), { "fresh" })
		Notifications.prune(queue, 100)
		t.equal(queue.recent["info\0\0stale"], nil, "old dedupe keys are forgotten")
	end,

	["clear empties the queue and dedupe memory"] = function()
		local queue = newQueue()
		Notifications.push(queue, { text = "x" }, 0)
		Notifications.clear(queue)
		t.equal(Notifications.size(queue), 0)
		t.truthy(Notifications.push(queue, { text = "x" }, 1), "no longer a duplicate")
	end,

	["invalid input is refused without using an id"] = function()
		local queue = newQueue()
		t.equal(select(2, Notifications.push(queue, { text = "" }, 0)), "text is empty or invalid")
		local ok, _, note = Notifications.push(queue, { text = "real" }, 0)
		t.truthy(ok)
		t.equal(note and note.id, 1)
	end,
}
