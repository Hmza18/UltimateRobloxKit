--!strict
-- Toast / notification queue logic. Pure Luau: callers pass `now` (os.clock() on Roblox).
--
-- * At most `maxVisible` toasts show at once; the rest wait in a queue ordered by priority
--   (error > warning > success = info) and then by arrival.
-- * A toast with the same kind and text (or the same `key`) as one already showing or queued is
--   merged: its count goes up and, if visible, its timer restarts. No duplicate spam.
-- * duration 0 makes a toast sticky until dismissed.
-- Every operation returns a Change describing what the view must show, hide or refresh, so the
-- adapter never needs per-frame work: it schedules one timer for nextDeadline().

export type ToastInput = { text: string, title: string?, kind: string?, duration: number?, key: string?, icon: string? }

export type Toast = {
	id: string,
	text: string,
	title: string?,
	kind: string,
	key: string,
	icon: string?,
	duration: number,
	count: number,
	order: number,
	createdAt: number,
	shownAt: number?,
	expiresAt: number?,
}

export type Change = { shown: { Toast }, hidden: { Toast }, updated: { Toast }, dropped: { Toast } }

export type Options = { maxVisible: number?, maxQueued: number?, durations: { [string]: number }? }

export type Queue = {
	push: (self: Queue, input: ToastInput, now: number) -> (string, Change),
	dismiss: (self: Queue, id: string, now: number) -> Change,
	update: (self: Queue, now: number) -> Change,
	clear: (self: Queue) -> Change,
	visible: (self: Queue) -> { Toast },
	queued: (self: Queue) -> { Toast },
	nextDeadline: (self: Queue) -> number?,
	get: (self: Queue, id: string) -> Toast?,
}

local ToastQueue = {}

ToastQueue.KINDS = { "info", "success", "warning", "error" }

local PRIORITY: { [string]: number } = { error = 3, warning = 2, success = 1, info = 1 }
local DEFAULT_DURATIONS: { [string]: number } = { info = 4, success = 3, warning = 5, error = 6 }

function ToastQueue.normalizeKind(kind: any): string
	if type(kind) == "string" and PRIORITY[kind] ~= nil then
		return kind
	end
	return "info"
end

local function emptyChange(): Change
	return { shown = {}, hidden = {}, updated = {}, dropped = {} }
end

function ToastQueue.new(options: Options?): Queue
	local opts: Options = options or {}
	local maxVisible = math.max(1, math.floor(opts.maxVisible or 3))
	local maxQueued = math.max(0, math.floor(opts.maxQueued or 20))
	local durations = opts.durations or DEFAULT_DURATIONS
	local visibleList: { Toast } = {}
	local queuedList: { Toast } = {}
	local counter = 0

	local function sortQueue()
		table.sort(queuedList, function(a: Toast, b: Toast): boolean
			local pa = PRIORITY[a.kind]
			local pb = PRIORITY[b.kind]
			if pa ~= pb then
				return pa > pb
			end
			return a.order < b.order
		end)
	end

	local function show(toast: Toast, now: number, change: Change)
		toast.shownAt = now
		toast.expiresAt = if toast.duration > 0 then now + toast.duration else nil
		table.insert(visibleList, toast)
		table.insert(change.shown, toast)
	end

	local function promote(now: number, change: Change)
		while #visibleList < maxVisible and #queuedList > 0 do
			show(table.remove(queuedList, 1) :: Toast, now, change)
		end
	end

	local function findDuplicate(key: string): Toast?
		for _, toast in visibleList do
			if toast.key == key then
				return toast
			end
		end
		for _, toast in queuedList do
			if toast.key == key then
				return toast
			end
		end
		return nil
	end

	local function removeFrom(list: { Toast }, id: string): Toast?
		for index, toast in list do
			if toast.id == id then
				return table.remove(list, index)
			end
		end
		return nil
	end

	local queue: Queue = {
		push = function(_self: Queue, input: ToastInput, now: number): (string, Change)
			assert(type(input) == "table" and type(input.text) == "string", "toast needs text")
			local change = emptyChange()
			local kind = ToastQueue.normalizeKind(input.kind)
			local key = input.key or (kind .. "\0" .. input.text)
			local existing = findDuplicate(key)
			if existing then
				existing.count += 1
				if existing.expiresAt ~= nil then
					existing.expiresAt = now + existing.duration
				end
				table.insert(change.updated, existing)
				return existing.id, change
			end
			counter += 1
			local duration = input.duration or durations[kind] or DEFAULT_DURATIONS[kind]
			local toast: Toast = {
				id = "toast" .. tostring(counter),
				text = input.text,
				title = input.title,
				kind = kind,
				key = key,
				icon = input.icon,
				duration = math.max(0, duration),
				count = 1,
				order = counter,
				createdAt = now,
				shownAt = nil,
				expiresAt = nil,
			}
			if #visibleList < maxVisible then
				show(toast, now, change)
				return toast.id, change
			end
			table.insert(queuedList, toast)
			sortQueue()
			while #queuedList > maxQueued do
				-- Drop the least important, newest waiting toast (the end of the sorted queue).
				local dropped = table.remove(queuedList) :: Toast
				table.insert(change.dropped, dropped)
			end
			return toast.id, change
		end,

		dismiss = function(_self: Queue, id: string, now: number): Change
			local change = emptyChange()
			local hidden = removeFrom(visibleList, id)
			if hidden then
				table.insert(change.hidden, hidden)
				promote(now, change)
				return change
			end
			local dropped = removeFrom(queuedList, id)
			if dropped then
				table.insert(change.dropped, dropped)
			end
			return change
		end,

		update = function(_self: Queue, now: number): Change
			local change = emptyChange()
			for index = #visibleList, 1, -1 do
				local toast = visibleList[index]
				if toast.expiresAt ~= nil and toast.expiresAt <= now then
					table.remove(visibleList, index)
					table.insert(change.hidden, 1, toast)
				end
			end
			promote(now, change)
			return change
		end,

		clear = function(_self: Queue): Change
			local change = emptyChange()
			change.hidden = visibleList
			change.dropped = queuedList
			visibleList = {}
			queuedList = {}
			return change
		end,

		visible = function(_self: Queue): { Toast }
			return table.clone(visibleList)
		end,

		queued = function(_self: Queue): { Toast }
			return table.clone(queuedList)
		end,

		nextDeadline = function(_self: Queue): number?
			local earliest: number? = nil
			for _, toast in visibleList do
				local expiresAt = toast.expiresAt
				if expiresAt ~= nil and (earliest == nil or expiresAt < earliest) then
					earliest = expiresAt
				end
			end
			return earliest
		end,

		get = function(_self: Queue, id: string): Toast?
			for _, toast in visibleList do
				if toast.id == id then
					return toast
				end
			end
			for _, toast in queuedList do
				if toast.id == id then
					return toast
				end
			end
			return nil
		end,
	}
	return queue
end

return ToastQueue
