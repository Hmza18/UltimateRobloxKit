--!strict
-- ToastQueue: visibility limits, expiry, priority, merging duplicates and sticky toasts.

local t = require("./lib/t")
local ToastQueue = require("../src/UI/Core/ToastQueue")

local function texts(list: { ToastQueue.Toast }): { string }
	local out: { string } = {}
	for _, toast in list do
		table.insert(out, toast.text)
	end
	return out
end

return {
	["shows up to maxVisible and queues the rest"] = function()
		local queue = ToastQueue.new({ maxVisible = 2 })
		local _, first = queue:push({ text = "a" }, 0)
		queue:push({ text = "b" }, 0)
		local _, third = queue:push({ text = "c" }, 0)
		t.equal(#first.shown, 1)
		t.equal(#third.shown, 0, "third waits")
		t.deepEqual(texts(queue:visible()), { "a", "b" })
		t.deepEqual(texts(queue:queued()), { "c" })
	end,

	["expired toasts hide and queued ones are promoted"] = function()
		local queue = ToastQueue.new({ maxVisible = 2 })
		queue:push({ text = "a" }, 0)
		queue:push({ text = "b" }, 0)
		queue:push({ text = "c" }, 0)
		t.equal(#queue:update(3.5).hidden, 0, "info lasts 4 seconds")
		local change = queue:update(4)
		t.deepEqual(texts(change.hidden), { "a", "b" })
		t.deepEqual(texts(change.shown), { "c" })
		t.equal(queue:nextDeadline(), 8)
	end,

	["duplicates merge and restart the timer"] = function()
		local queue = ToastQueue.new()
		local id = queue:push({ text = "Saved", kind = "success" }, 0)
		local sameId, change = queue:push({ text = "Saved", kind = "success" }, 2)
		t.equal(sameId, id)
		t.equal(#change.updated, 1)
		local toast = queue:get(id) :: ToastQueue.Toast
		t.equal(toast.count, 2)
		t.equal(toast.expiresAt, 5, "success lasts 3 seconds from the latest push")
		local otherId = queue:push({ text = "Saved", kind = "error" }, 2)
		t.truthy(otherId ~= id, "a different kind is a different toast")
	end,

	["errors jump ahead of waiting info toasts"] = function()
		local queue = ToastQueue.new({ maxVisible = 1 })
		local firstId = queue:push({ text = "first" }, 0)
		queue:push({ text = "info" }, 0)
		queue:push({ text = "warn", kind = "warning" }, 0)
		queue:push({ text = "boom", kind = "error" }, 0)
		t.deepEqual(texts(queue:queued()), { "boom", "warn", "info" })
		local change = queue:dismiss(firstId, 1)
		t.deepEqual(texts(change.hidden), { "first" })
		t.deepEqual(texts(change.shown), { "boom" })
	end,

	["sticky toasts stay until dismissed"] = function()
		local queue = ToastQueue.new()
		local id = queue:push({ text = "Connecting", duration = 0 }, 0)
		t.equal(#queue:update(1000).hidden, 0)
		t.equal(queue:nextDeadline(), nil)
		t.equal(#queue:dismiss(id, 1000).hidden, 1)
	end,

	["a full queue drops the newest least important toast"] = function()
		local queue = ToastQueue.new({ maxVisible = 1, maxQueued = 1 })
		queue:push({ text = "shown" }, 0)
		queue:push({ text = "waiting" }, 0)
		local _, change = queue:push({ text = "urgent", kind = "error" }, 0)
		t.deepEqual(texts(change.dropped), { "waiting" })
		t.deepEqual(texts(queue:queued()), { "urgent" })
	end,

	["nextDeadline is the earliest visible expiry"] = function()
		local queue = ToastQueue.new()
		queue:push({ text = "info" }, 0)
		queue:push({ text = "done", kind = "success" }, 0)
		queue:push({ text = "custom", duration = 1.5 }, 0)
		t.equal(queue:nextDeadline(), 1.5)
	end,

	["unknown kinds become info and text is required"] = function()
		local queue = ToastQueue.new()
		local id = queue:push({ text = "x", kind = "party" }, 0)
		local toast = queue:get(id) :: ToastQueue.Toast
		t.equal(toast.kind, "info")
		t.throws(function()
			queue:push({} :: any, 0)
		end)
	end,

	["dismissing a queued toast and clearing"] = function()
		local queue = ToastQueue.new({ maxVisible = 1 })
		queue:push({ text = "a" }, 0)
		local queuedId = queue:push({ text = "b" }, 0)
		t.deepEqual(texts(queue:dismiss(queuedId, 0).dropped), { "b" })
		queue:push({ text = "c" }, 0)
		local change = queue:clear()
		t.deepEqual(texts(change.hidden), { "a" })
		t.deepEqual(texts(change.dropped), { "c" })
		t.equal(#queue:visible(), 0)
	end,
}
