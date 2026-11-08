--!strict
-- Notification queue rules. Pure Luau: `now` is passed in.
-- Notifications have a type (info, success, warning, ...) that sets priority and duration, a dedupe key,
-- and text that is validated and trimmed. The queue drops repeats inside the dedupe window, keeps the
-- highest priorities when full and hands out the most important, oldest notification first.

local NotificationsConfig = require("./NotificationsConfig")

export type TypeDef = { priority: number, duration: number }

export type Config = {
	types: { [string]: TypeDef },
	defaultType: string,
	dedupeWindow: number,
	maxQueue: number,
	maxAge: number,
	maxTitleLength: number,
	maxTextLength: number,
}

export type Input = {
	text: string,
	title: string?,
	kind: string?, -- a key of config.types
	key: string?, -- dedupe key; defaults to kind, title and text
	priority: number?, -- overrides the type's priority
	duration: number?, -- seconds; overrides the type's duration
	data: any?, -- passed through untouched (icon id, action, ...)
}

export type Notification = {
	id: number,
	kind: string,
	title: string?,
	text: string,
	key: string,
	priority: number,
	duration: number,
	data: any?,
	createdAt: number,
	count: number, -- how many duplicates were merged into this one
}

export type Queue = { config: Config, items: { Notification }, recent: { [string]: number }, nextId: number }

local Notifications = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Notifications.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local function numberOr(key: string, minimum: number): number
		local value = source[key]
		if isFinite(value) and value >= minimum then
			return value
		end
		return (NotificationsConfig :: any)[key]
	end
	local types: { [string]: TypeDef } = {}
	local rawTypes = if type(source.types) == "table" then source.types else NotificationsConfig.types
	for name, def in rawTypes do
		if type(name) == "string" and type(def) == "table" and isFinite(def.priority) and isFinite(def.duration) then
			types[name] = { priority = def.priority, duration = math.max(0, def.duration) }
		end
	end
	local defaultType: string = NotificationsConfig.defaultType
	if type(source.defaultType) == "string" then
		defaultType = source.defaultType
	end
	if types[defaultType] == nil then
		types[defaultType] = { priority = 1, duration = 4 }
	end
	return {
		types = types,
		defaultType = defaultType,
		dedupeWindow = numberOr("dedupeWindow", 0),
		maxQueue = math.floor(numberOr("maxQueue", 1)),
		maxAge = numberOr("maxAge", 0),
		maxTitleLength = math.floor(numberOr("maxTitleLength", 1)),
		maxTextLength = math.floor(numberOr("maxTextLength", 1)),
	}
end

-- Cuts `text` to at most `maxLength` UTF-8 characters, ending with "..." when it was cut.
-- Invalid UTF-8 returns nil.
function Notifications.truncate(text: string, maxLength: number): string?
	local length = utf8.len(text)
	if length == nil then
		return nil
	end
	if length <= maxLength then
		return text
	end
	local keep = math.max(0, maxLength - 3)
	local cut = utf8.offset(text, keep + 1)
	local head = if cut then string.sub(text, 1, cut - 1) else text
	return head .. string.sub("...", 1, maxLength - keep)
end

-- Validates and fills in a notification. Returns nil and a reason for bad input.
function Notifications.normalize(input: any, config: Config, now: number, id: number): (Notification?, string?)
	if type(input) ~= "table" or type(input.text) ~= "string" then
		return nil, "text must be a string"
	end
	local text = Notifications.truncate(input.text, config.maxTextLength)
	if text == nil or string.match(text, "%S") == nil then
		return nil, "text is empty or invalid"
	end
	local title: string? = nil
	if input.title ~= nil then
		if type(input.title) ~= "string" then
			return nil, "title must be a string"
		end
		title = Notifications.truncate(input.title, config.maxTitleLength)
		if title == nil then
			return nil, "title is invalid"
		end
	end
	local kind = if type(input.kind) == "string" and config.types[input.kind] then input.kind else config.defaultType
	local typeDef = config.types[kind]
	local priority = if isFinite(input.priority) then input.priority else typeDef.priority
	local duration = if isFinite(input.duration) and input.duration >= 0 then input.duration else typeDef.duration
	local titleText: string = if type(title) == "string" then title else ""
	local key = if type(input.key) == "string" then input.key else kind .. "\0" .. titleText .. "\0" .. text
	local note: Notification = {
		id = id,
		kind = kind,
		title = title,
		text = text,
		key = key,
		priority = priority,
		duration = duration,
		data = input.data,
		createdAt = now,
		count = 1,
	}
	return note, nil
end

function Notifications.newQueue(config: Config): Queue
	return { config = config, items = {}, recent = {}, nextId = 1 }
end

-- Adds a notification. Returns whether it was queued, a reason when not ("duplicate", "queue full" or
-- a validation reason), and the queued notification. A duplicate still waiting in the queue has its
-- count raised instead. When the queue is full, the lowest-priority (then oldest) item is dropped if
-- the new one outranks it.
function Notifications.push(queue: Queue, input: any, now: number): (boolean, string?, Notification?)
	local note, reason = Notifications.normalize(input, queue.config, now, queue.nextId)
	if note == nil then
		return false, reason, nil
	end
	local lastAt = queue.recent[note.key]
	if lastAt and now - lastAt < queue.config.dedupeWindow then
		for _, item in queue.items do
			if item.key == note.key then
				item.count += 1
				break
			end
		end
		return false, "duplicate", nil
	end
	if #queue.items >= queue.config.maxQueue then
		local lowestIndex = 1
		for index, item in queue.items do
			local lowest = queue.items[lowestIndex]
			if item.priority < lowest.priority or (item.priority == lowest.priority and item.id < lowest.id) then
				lowestIndex = index
			end
		end
		if queue.items[lowestIndex].priority >= note.priority then
			return false, "queue full", nil
		end
		table.remove(queue.items, lowestIndex)
	end
	queue.nextId += 1
	queue.recent[note.key] = now
	table.insert(queue.items, note)
	return true, nil, note
end

-- Removes notifications older than maxAge and forgets dedupe keys outside the window.
function Notifications.prune(queue: Queue, now: number)
	for index = #queue.items, 1, -1 do
		if now - queue.items[index].createdAt > queue.config.maxAge then
			table.remove(queue.items, index)
		end
	end
	for key, lastAt in queue.recent do
		if now - lastAt >= queue.config.dedupeWindow then
			queue.recent[key] = nil
		end
	end
end

local function bestIndex(queue: Queue): number?
	local best: number? = nil
	for index, item in queue.items do
		local current = if best then queue.items[best] else nil
		local higher = current == nil or item.priority > current.priority
		local olderTie = current ~= nil and item.priority == current.priority and item.id < current.id
		if higher or olderTie then
			best = index
		end
	end
	return best
end

function Notifications.peek(queue: Queue, now: number): Notification?
	Notifications.prune(queue, now)
	local index = bestIndex(queue)
	return if index then queue.items[index] else nil
end

-- Takes the next notification to show: highest priority first, then the oldest.
function Notifications.pop(queue: Queue, now: number): Notification?
	Notifications.prune(queue, now)
	local index = bestIndex(queue)
	if index == nil then
		return nil
	end
	return table.remove(queue.items, index)
end

function Notifications.size(queue: Queue): number
	return #queue.items
end

function Notifications.clear(queue: Queue)
	table.clear(queue.items)
	table.clear(queue.recent)
end

return Notifications
