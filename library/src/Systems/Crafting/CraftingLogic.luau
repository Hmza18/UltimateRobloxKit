--!strict
-- Crafting recipes, atomic craft transactions and a timed job queue. Pure Luau and immutable.
-- The inventory is reached through `InventoryOps`, so the same rules work with InventoryLogic
-- (`CraftingLogic.inventoryOps(registry)`) or a plain { [itemId]: count } bag (`bagOps`).
-- Ops must not modify their input: a failed craft simply discards the partial result.

local InventoryLogic = require("../Inventory/InventoryLogic")

export type ItemCount = { id: string, count: number }

export type RecipeInput = {
	id: string, -- unique recipe id
	inputs: { ItemCount }, -- consumed items
	outputs: { ItemCount }, -- produced items
	time: number?, -- seconds a queued job takes (default 0)
	station: string?, -- station tag the crafter must be at, such as "Anvil" (default none)
}

export type Recipe = {
	id: string, -- unique recipe id
	inputs: { ItemCount }, -- consumed items
	outputs: { ItemCount }, -- produced items
	time: number, -- seconds per job
	station: string?, -- required station tag
}

export type Book = { recipes: { [string]: Recipe }, order: { string } }

export type InventoryOps = {
	count: (inventory: any, id: string) -> number, -- items of `id` held
	remove: (inventory: any, id: string, count: number) -> (any?, string?), -- all or nothing
	add: (inventory: any, id: string, count: number) -> (any, number), -- new inventory, leftover
}

export type Context = { stations: { [string]: boolean }? }

export type Job = { id: number, recipeId: string, startAt: number, finishAt: number, duration: number }

export type Queue = { jobs: { Job }, maxJobs: number, nextId: number }

export type CraftResult = { ok: boolean, reason: string?, inventory: any }

export type QueueResult = { ok: boolean, reason: string?, queue: Queue, inventory: any, job: Job? }

export type CollectResult = { queue: Queue, inventory: any, completed: { Job }, blocked: boolean }

export type SavedJob = { id: number, r: string, s: number, f: number }

export type SavedQueue = { v: number, n: number, jobs: { SavedJob } }

local CraftingLogic = {}

CraftingLogic.MAX_TIMES = 1000
CraftingLogic.DEFAULT_MAX_JOBS = 10
CraftingLogic.SAVE_VERSION = 1

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

local function copyCounts(list: { ItemCount }, label: string): { ItemCount }
	assert(type(list) == "table", label .. " must be an array")
	local result: { ItemCount } = {}
	for _, entry in list do
		assert(type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "", label .. " needs item ids")
		assert(isCount(entry.count), label .. " counts must be positive integers")
		table.insert(result, { id = entry.id, count = entry.count })
	end
	return result
end

local function copyQueue(queue: Queue): Queue
	local jobs: { Job } = {}
	for index, job in queue.jobs do
		jobs[index] = table.clone(job)
	end
	return { jobs = jobs, maxJobs = queue.maxJobs, nextId = queue.nextId }
end

function CraftingLogic.newBook(recipes: { RecipeInput }): Book
	assert(type(recipes) == "table", "recipes must be an array")
	local book: Book = { recipes = {}, order = {} }
	for _, input in recipes do
		local id = input.id
		assert(type(id) == "string" and id ~= "", "recipe id must be a non-empty string")
		assert(book.recipes[id] == nil, "duplicate recipe id " .. id)
		local time = input.time or 0
		assert(isFinite(time) and time >= 0, "time must be >= 0 for " .. id)
		local station = input.station
		assert(station == nil or type(station) == "string", "station must be a string for " .. id)
		local outputs = copyCounts(input.outputs, "outputs of " .. id)
		assert(#outputs > 0, "recipe " .. id .. " needs at least one output")
		book.recipes[id] = {
			id = id,
			inputs = copyCounts(input.inputs, "inputs of " .. id),
			outputs = outputs,
			time = time,
			station = station,
		}
		table.insert(book.order, id)
	end
	return book
end

function CraftingLogic.getRecipe(book: Book, recipeId: string): Recipe?
	return book.recipes[recipeId]
end

-- Ops for a plain { [itemId]: count } table with unlimited space.
CraftingLogic.bagOps = {
	count = function(bag: any, id: string): number
		return bag[id] or 0
	end,
	remove = function(bag: any, id: string, count: number): (any?, string?)
		local held = bag[id] or 0
		if held < count then
			return nil, "not enough items"
		end
		local result = table.clone(bag)
		result[id] = if held == count then nil else held - count
		return result, nil
	end,
	add = function(bag: any, id: string, count: number): (any, number)
		local result = table.clone(bag)
		result[id] = (bag[id] or 0) + count
		return result, 0
	end,
} :: InventoryOps

-- Ops backed by InventoryLogic and its registry.
function CraftingLogic.inventoryOps(registry: InventoryLogic.Registry): InventoryOps
	return {
		count = function(inventory: any, id: string): number
			return InventoryLogic.count(inventory, id)
		end,
		remove = function(inventory: any, id: string, count: number): (any?, string?)
			return InventoryLogic.remove(inventory, id, count)
		end,
		add = function(inventory: any, id: string, count: number): (any, number)
			return InventoryLogic.add(inventory, registry, id, count)
		end,
	}
end

-- Inputs still missing for `times` crafts. Empty when everything is there.
function CraftingLogic.missing(recipe: Recipe, inventory: any, ops: InventoryOps, times: number?): { ItemCount }
	local multiplier = times or 1
	local needed: { [string]: number } = {}
	local order: { string } = {}
	for _, input in recipe.inputs do
		if needed[input.id] == nil then
			table.insert(order, input.id)
			needed[input.id] = 0
		end
		needed[input.id] += input.count * multiplier
	end
	local result: { ItemCount } = {}
	for _, id in order do
		local short = needed[id] - ops.count(inventory, id)
		if short > 0 then
			table.insert(result, { id = id, count = short })
		end
	end
	return result
end

local function check(
	book: Book,
	recipeId: string,
	inventory: any,
	ops: InventoryOps,
	context: Context?,
	times: number
): (Recipe?, string?)
	local recipe = book.recipes[recipeId]
	if recipe == nil then
		return nil, "unknown recipe"
	end
	if not isCount(times) or times > CraftingLogic.MAX_TIMES then
		return nil, "invalid times"
	end
	local station = recipe.station
	if station ~= nil then
		local stations = if context then context.stations else nil
		if stations == nil or stations[station] ~= true then
			return nil, "station required"
		end
	end
	if #CraftingLogic.missing(recipe, inventory, ops, times) > 0 then
		return nil, "missing items"
	end
	return recipe, nil
end

local function consume(recipe: Recipe, inventory: any, ops: InventoryOps, times: number): (any?, string?)
	local current = inventory
	for _, input in recipe.inputs do
		local nextInventory, reason = ops.remove(current, input.id, input.count * times)
		if nextInventory == nil then
			return nil, reason or "missing items"
		end
		current = nextInventory
	end
	return current, nil
end

local function produce(recipe: Recipe, inventory: any, ops: InventoryOps, times: number): (any?, string?)
	local current = inventory
	for _, output in recipe.outputs do
		local nextInventory, leftover = ops.add(current, output.id, output.count * times)
		if leftover > 0 then
			return nil, "no space"
		end
		current = nextInventory
	end
	return current, nil
end

function CraftingLogic.canCraft(
	book: Book,
	recipeId: string,
	inventory: any,
	ops: InventoryOps,
	context: Context?,
	times: number?
): (boolean, string?)
	local recipe, reason = check(book, recipeId, inventory, ops, context, times or 1)
	return recipe ~= nil, reason
end

-- Crafts instantly, ignoring `time`: consumes inputs and adds outputs, all or nothing.
-- Fails with "no space" when the outputs do not fit after the inputs are removed.
function CraftingLogic.craft(
	book: Book,
	recipeId: string,
	inventory: any,
	ops: InventoryOps,
	context: Context?,
	times: number?
): CraftResult
	local count = times or 1
	local recipe, reason = check(book, recipeId, inventory, ops, context, count)
	if recipe == nil then
		return { ok = false, reason = reason, inventory = inventory }
	end
	local consumed, consumeReason = consume(recipe, inventory, ops, count)
	if consumed == nil then
		return { ok = false, reason = consumeReason, inventory = inventory }
	end
	local produced, produceReason = produce(recipe, consumed, ops, count)
	if produced == nil then
		return { ok = false, reason = produceReason, inventory = inventory }
	end
	return { ok = true, reason = nil, inventory = produced }
end

function CraftingLogic.newQueue(maxJobs: number?): Queue
	local size = maxJobs or CraftingLogic.DEFAULT_MAX_JOBS
	assert(isCount(size), "maxJobs must be a positive integer")
	return { jobs = {}, maxJobs = size, nextId = 1 }
end

-- Starts a timed job. Inputs are taken now; outputs arrive through `collect` once the job is done.
-- Jobs run one after another, so a new job starts when the previous one finishes.
function CraftingLogic.enqueue(
	book: Book,
	queue: Queue,
	recipeId: string,
	inventory: any,
	ops: InventoryOps,
	context: Context?,
	now: number
): QueueResult
	if not isFinite(now) then
		return { ok = false, reason = "invalid time", queue = queue, inventory = inventory, job = nil }
	end
	if #queue.jobs >= queue.maxJobs then
		return { ok = false, reason = "queue full", queue = queue, inventory = inventory, job = nil }
	end
	local recipe, reason = check(book, recipeId, inventory, ops, context, 1)
	if recipe == nil then
		return { ok = false, reason = reason, queue = queue, inventory = inventory, job = nil }
	end
	local consumed, consumeReason = consume(recipe, inventory, ops, 1)
	if consumed == nil then
		return { ok = false, reason = consumeReason, queue = queue, inventory = inventory, job = nil }
	end
	local result = copyQueue(queue)
	local last = result.jobs[#result.jobs]
	local startAt = if last then math.max(now, last.finishAt) else now
	local job: Job = {
		id = result.nextId,
		recipeId = recipe.id,
		startAt = startAt,
		finishAt = startAt + recipe.time,
		duration = recipe.time,
	}
	result.nextId += 1
	table.insert(result.jobs, job)
	return { ok = true, reason = nil, queue = result, inventory = consumed, job = table.clone(job) }
end

-- 0 before the job starts, 1 when it is done.
function CraftingLogic.progress(job: Job, now: number): number
	if job.duration <= 0 then
		return if now >= job.startAt then 1 else 0
	end
	return math.clamp((now - job.startAt) / job.duration, 0, 1)
end

-- Delivers the outputs of every finished job, in order. Stops at the first job whose outputs
-- do not fit (`blocked = true`); that job stays queued and can be collected later.
function CraftingLogic.collect(book: Book, queue: Queue, inventory: any, ops: InventoryOps, now: number): CollectResult
	local result = copyQueue(queue)
	local current = inventory
	local completed: { Job } = {}
	local blocked = false
	while #result.jobs > 0 do
		local job = result.jobs[1]
		if job.finishAt > now then
			break
		end
		local recipe = book.recipes[job.recipeId]
		if recipe ~= nil then
			local produced = produce(recipe, current, ops, 1)
			if produced == nil then
				blocked = true
				break
			end
			current = produced
		end
		table.remove(result.jobs, 1)
		table.insert(completed, job)
	end
	return { queue = result, inventory = current, completed = completed, blocked = blocked }
end

-- Cancels a job and refunds its inputs. Later jobs that have not started move up.
function CraftingLogic.cancel(
	book: Book,
	queue: Queue,
	jobId: number,
	inventory: any,
	ops: InventoryOps,
	now: number
): QueueResult
	local result = copyQueue(queue)
	local position: number? = nil
	for index, job in result.jobs do
		if job.id == jobId then
			position = index
			break
		end
	end
	if position == nil then
		return { ok = false, reason = "no such job", queue = queue, inventory = inventory, job = nil }
	end
	local job = table.remove(result.jobs, position)
	local current = inventory
	local recipe = if job then book.recipes[job.recipeId] else nil
	if recipe ~= nil then
		for _, input in recipe.inputs do
			local refunded, leftover = ops.add(current, input.id, input.count)
			if leftover > 0 then
				return { ok = false, reason = "no space for refund", queue = queue, inventory = inventory, job = nil }
			end
			current = refunded
		end
	end
	local previousFinish: number? = nil
	for _, other in result.jobs do
		if other.startAt > now then
			local startAt = math.max(now, previousFinish or now)
			other.startAt = startAt
			other.finishAt = startAt + other.duration
		end
		previousFinish = other.finishAt
	end
	return { ok = true, reason = nil, queue = result, inventory = current, job = job }
end

function CraftingLogic.serializeQueue(queue: Queue): SavedQueue
	local jobs: { SavedJob } = {}
	for _, job in queue.jobs do
		table.insert(jobs, { id = job.id, r = job.recipeId, s = job.startAt, f = job.finishAt })
	end
	return { v = CraftingLogic.SAVE_VERSION, n = queue.nextId, jobs = jobs }
end

-- Rebuilds a queue from untrusted data. Drops jobs for unknown recipes or with bad times and
-- keeps at most `maxJobs`, ordered by start time.
function CraftingLogic.deserializeQueue(book: Book, raw: any, maxJobs: number?): Queue
	local queue = CraftingLogic.newQueue(maxJobs)
	if type(raw) ~= "table" or type(raw.jobs) ~= "table" then
		return queue
	end
	local highest = 0
	for _, entry in raw.jobs do
		local valid = type(entry) == "table" and isCount(entry.id) and isFinite(entry.s) and isFinite(entry.f)
		local recipe = if valid and type(entry.r) == "string" then book.recipes[entry.r] else nil
		if recipe ~= nil and entry.f >= entry.s and #queue.jobs < queue.maxJobs then
			table.insert(queue.jobs, {
				id = entry.id,
				recipeId = recipe.id,
				startAt = entry.s,
				finishAt = entry.f,
				duration = entry.f - entry.s,
			})
			highest = math.max(highest, entry.id)
		end
	end
	table.sort(queue.jobs, function(a: Job, b: Job): boolean
		return a.startAt < b.startAt
	end)
	local savedNext = if isCount(raw.n) then raw.n else 1
	queue.nextId = math.max(savedNext, highest + 1)
	return queue
end

return CraftingLogic
