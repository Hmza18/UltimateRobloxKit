--!strict
-- Feedback recipes (pure Luau). A recipe is a list of steps; each step names one thing another
-- visuals module does (a VFX, a UI animation, a popup, a camera shake, a sound cue ...). Values
-- that start with "$" are read from the context the game passes to Feedback.fire:
--
--   { kind = "vfx", id = "CoinBurst", at = "$position" }
--   { kind = "popup", text = "+$amount", at = "$position", throttle = { max = 8, coalesce = "amount" } }
--   { kind = "camera", shake = "Tap", when = { every = 5 } }
--
-- resolve() substitutes the references, drops steps whose `when` fails or whose context is
-- missing, and reports what it dropped. Throttling is a pure state machine with time passed in.
-- Nothing here decides gameplay: recipes only describe presentation.

local RewardsLogic = require("../Rewards/RewardsLogic")

export type Step = { [string]: any }
export type Recipe = { Step }
export type Context = { [string]: any }
export type Meta = { count: number? } -- count: how many times the event has fired, this one included
export type Dropped = { index: number, kind: string, reason: string }

export type ThrottleRule = { max: number, window: number?, coalesce: string? }
type Bucket = { times: { number }, pending: number, pendingCount: number }
export type ThrottleState = { [string]: Bucket }

local FeedbackLogic = {}

FeedbackLogic.KINDS = table.freeze({
	"vfx",
	"ui",
	"popup",
	"flyTo",
	"camera",
	"sound",
	"object",
	"pet",
	"reward",
	"hatch",
	"call",
})

FeedbackLogic.UI_ACTIONS = table.freeze({ "animate", "countTo", "shine", "flash", "show", "hide" })

-- Fields that configure a step rather than being passed on.
local CONTROL: { [string]: boolean } = { kind = true, when = true, throttle = true, optional = true }

local REQUIRED: { [string]: { string } } = {
	vfx = { "id", "at" },
	popup = { "text", "at" },
	flyTo = { "from", "to" },
	sound = { "cue" },
	object = { "preset", "target" },
	pet = { "reaction", "target" },
	reward = { "rarity", "reward" },
	hatch = { "eggs" },
	call = { "fn" },
}

local UI_REQUIRED: { [string]: { string } } = {
	animate = { "preset", "target" },
	countTo = { "target", "to" },
	shine = { "target" },
	flash = {},
	show = { "target" },
	hide = { "target" },
}

local CAMERA_MOVES = { "shake", "cinematic", "fov", "zoom", "focus" }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function trim(text: string): string
	local trimmed = string.gsub(text, "%.0$", "")
	return trimmed
end

-- Formats a number for a popup: 950, 1,250, 12.5K, 3M, 1.2B. Non-numbers become tostring(value).
function FeedbackLogic.format(value: any): string
	if not finite(value) then
		return tostring(value)
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n >= 10000 then
		local suffixes = { "K", "M", "B", "T", "Qa", "Qi" }
		local tier = math.min(#suffixes, math.floor(math.log10(n) / 3 + 1e-9))
		local scaled = n / 1000 ^ tier
		-- Truncate, never round up: a popup must not promise more than was earned.
		local shown = math.floor(scaled * 10) / 10
		return sign .. trim(string.format("%.1f", shown)) .. suffixes[tier]
	end
	local whole = math.floor(n)
	local fraction = n - whole
	local digits = tostring(whole)
	if whole >= 1000 then
		digits = string.sub(digits, 1, -4) .. "," .. string.sub(digits, -3)
	end
	if fraction >= 0.05 and whole < 1000 then
		return sign .. trim(string.format("%.1f", math.floor(n * 10) / 10))
	end
	return sign .. digits
end

-- Reads "a.b.c" from the context. Returns nil when any part is missing.
function FeedbackLogic.lookup(context: Context, path: string): any
	local current: any = context
	for part in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[part]
	end
	return current
end

local REFERENCE = "%$([%a_][%w_]*%.?[%w_%.]*)"

local function cleanPath(path: string): (string, string)
	-- "$amount." ends a sentence: the dot is text, not part of the path.
	local name = string.gsub(path, "%.+$", "")
	return name, string.sub(path, #name + 1)
end

local function resolveValue(value: any, context: Context, missing: { string }): any
	if type(value) == "string" then
		if string.find(value, "$", 1, true) == nil then
			return value
		end
		local whole = string.match(value, "^" .. REFERENCE .. "$")
		if whole ~= nil then
			local name = cleanPath(whole)
			if name == whole then
				local found = FeedbackLogic.lookup(context, name)
				if found == nil then
					table.insert(missing, name)
				end
				return found
			end
		end
		local text = string.gsub(value, REFERENCE, function(path: string): string
			local name, rest = cleanPath(path)
			local found = FeedbackLogic.lookup(context, name)
			if found == nil then
				table.insert(missing, name)
				return ""
			end
			local shown = if type(found) == "number" then FeedbackLogic.format(found) else tostring(found)
			return shown .. rest
		end)
		return text
	elseif type(value) == "table" then
		local copy: { [any]: any } = {}
		local inner: { string } = {}
		for key, item in value do
			-- References inside option tables are optional: a missing one is simply nil.
			copy[key] = resolveValue(item, context, inner)
		end
		return copy
	end
	return value
end

local function passes(condition: any, context: Context, meta: Meta?): boolean
	if type(condition) ~= "table" then
		return true
	end
	if condition[1] ~= nil then
		for _, item in condition do
			if not passes(item, context, meta) then
				return false
			end
		end
		return true
	end
	if condition.every ~= nil then
		local count = if meta and meta.count then meta.count else 1
		if count % math.max(1, condition.every) ~= 0 then
			return false
		end
	end
	if condition.field == nil then
		return true
	end
	local value = FeedbackLogic.lookup(context, condition.field)
	if condition.exists ~= nil and (value ~= nil) ~= condition.exists then
		return false
	end
	if condition.equals ~= nil and value ~= condition.equals then
		return false
	end
	if condition.min ~= nil and not (type(value) == "number" and value >= condition.min) then
		return false
	end
	if condition.max ~= nil and not (type(value) == "number" and value <= condition.max) then
		return false
	end
	if condition.atLeast ~= nil then
		if not RewardsLogic.has(value) or not RewardsLogic.atLeast(value, condition.atLeast) then
			return false
		end
	end
	return true
end

-- True when a step's `when` holds: { field = "amount", min = 100 }, { field = "rarity", atLeast =
-- "Epic" }, { field = "pet", exists = true }, { field = "mode", equals = "boss" }, { every = 5 }
-- (every fifth fire), or a list of such conditions that must all hold.
function FeedbackLogic.check(when: any, context: Context?, meta: Meta?): boolean
	return passes(when, context or {}, meta)
end

-- Substitutes context references in every step. Returns the steps to run and the steps that were
-- dropped, each with a reason ("when" or "missing <field>"). A step is dropped when a reference
-- in one of its own fields is missing, unless the field is listed in step.optional.
function FeedbackLogic.resolve(recipe: Recipe, context: Context?, meta: Meta?): ({ Step }, { Dropped })
	local ctx: Context = context or {}
	local steps: { Step } = {}
	local dropped: { Dropped } = {}
	for index, step in recipe do
		if not passes(step.when, ctx, meta) then
			table.insert(dropped, { index = index, kind = step.kind, reason = "when" })
			continue
		end
		local resolved: Step = { kind = step.kind, throttle = step.throttle, index = index }
		local reason: string? = nil
		local keys: { string } = {}
		for key in step do
			if not CONTROL[key] then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		for _, key in keys do
			local missing: { string } = {}
			resolved[key] = resolveValue(step[key], ctx, missing)
			if #missing > 0 then
				local optional = type(step.optional) == "table" and table.find(step.optional, key) ~= nil
				if optional then
					resolved[key] = nil
				elseif reason == nil then
					reason = "missing " .. missing[1]
				end
			end
		end
		if reason then
			table.insert(dropped, { index = index, kind = step.kind, reason = reason })
		else
			if not finite(resolved.delay) or resolved.delay < 0 then
				resolved.delay = 0
			end
			table.insert(steps, resolved)
		end
	end
	return steps, dropped
end

-- Checks a recipe's shape. Returns false and a message naming the first problem.
function FeedbackLogic.validate(recipe: any): (boolean, string?)
	if type(recipe) ~= "table" then
		return false, "a recipe is a list of steps"
	end
	local count = 0
	for _ in recipe do
		count += 1
	end
	if count ~= #recipe then
		return false, "a recipe is a list of steps"
	end
	for index, step in recipe do
		local where = "step " .. tostring(index)
		if type(step) ~= "table" then
			return false, where .. " must be a table"
		end
		local kind = step.kind
		if type(kind) ~= "string" or table.find(FeedbackLogic.KINDS, kind) == nil then
			return false, where .. " has unknown kind " .. tostring(kind)
		end
		local required = REQUIRED[kind]
		if kind == "ui" then
			local action = step.action or "animate"
			required = UI_REQUIRED[action]
			if required == nil then
				return false, where .. " has unknown ui action " .. tostring(action)
			end
		elseif kind == "camera" then
			local moves = 0
			for _, move in CAMERA_MOVES do
				if step[move] ~= nil then
					moves += 1
				end
			end
			if moves ~= 1 then
				return false, where .. " needs exactly one of shake, cinematic, fov, zoom, focus"
			end
			if step.cinematic ~= nil and step.target == nil then
				return false, where .. " needs target for a cinematic"
			end
		end
		for _, field in required or {} do
			if step[field] == nil then
				return false, where .. " (" .. kind .. ") needs " .. field
			end
		end
		if kind == "call" and type(step.fn) ~= "function" and type(step.fn) ~= "string" then
			return false, where .. " fn must be a function or a context reference"
		end
		if step.delay ~= nil and type(step.delay) ~= "string" and (not finite(step.delay) or step.delay < 0) then
			return false, where .. " delay must be a number >= 0"
		end
		if step.when ~= nil and type(step.when) ~= "table" then
			return false, where .. " when must be a table"
		end
		if step.optional ~= nil and type(step.optional) ~= "table" then
			return false, where .. " optional must be a list of field names"
		end
		local throttle = step.throttle
		if throttle ~= nil then
			if type(throttle) ~= "table" or not finite(throttle.max) or throttle.max < 1 then
				return false, where .. " throttle needs max >= 1"
			end
			if throttle.window ~= nil and (not finite(throttle.window) or throttle.window <= 0) then
				return false, where .. " throttle window must be > 0"
			end
			if throttle.coalesce ~= nil and type(throttle.coalesce) ~= "string" then
				return false, where .. " throttle coalesce must be a context field name"
			end
		end
	end
	return true, nil
end

-- Throttling. One bucket per key (Feedback uses "<event>#<step index>").
function FeedbackLogic.newThrottle(): ThrottleState
	return {}
end

local function bucketOf(state: ThrottleState, key: string, rule: ThrottleRule, now: number): Bucket
	local bucket = state[key]
	if bucket == nil then
		bucket = { times = {}, pending = 0, pendingCount = 0 }
		state[key] = bucket
	end
	local window = rule.window or 1
	while #bucket.times > 0 and bucket.times[1] <= now - window do
		table.remove(bucket.times, 1)
	end
	return bucket
end

-- Asks to run a throttled step now. Returns true and the amount to show (this amount plus any
-- that was held back) when there is room, or false when over the limit; with rule.coalesce the
-- amount is then kept for the next admitted step or for flush().
function FeedbackLogic.admit(
	state: ThrottleState,
	key: string,
	rule: ThrottleRule,
	now: number,
	amount: number?
): (boolean, number?)
	local bucket = bucketOf(state, key, rule, now)
	if #bucket.times < math.max(1, math.floor(rule.max)) then
		table.insert(bucket.times, now)
		local total: number? = amount
		if bucket.pendingCount > 0 then
			total = (amount or 0) + bucket.pending
			bucket.pending = 0
			bucket.pendingCount = 0
		end
		return true, total
	end
	if rule.coalesce ~= nil then
		bucket.pending += amount or 0
		bucket.pendingCount += 1
	end
	return false, nil
end

-- Amount and number of events currently held back for `key`.
function FeedbackLogic.pending(state: ThrottleState, key: string): (number, number)
	local bucket = state[key]
	if bucket == nil then
		return 0, 0
	end
	return bucket.pending, bucket.pendingCount
end

-- The earliest time a throttled step can run again (`now` when there is room already).
function FeedbackLogic.nextFree(state: ThrottleState, key: string, rule: ThrottleRule, now: number): number
	local bucket = bucketOf(state, key, rule, now)
	if #bucket.times < math.max(1, math.floor(rule.max)) then
		return now
	end
	return bucket.times[1] + (rule.window or 1)
end

-- Emits what was held back, if anything is pending and there is room. Returns the merged amount.
function FeedbackLogic.flush(state: ThrottleState, key: string, rule: ThrottleRule, now: number): number?
	local bucket = bucketOf(state, key, rule, now)
	if bucket.pendingCount == 0 or #bucket.times >= math.max(1, math.floor(rule.max)) then
		return nil
	end
	table.insert(bucket.times, now)
	local amount = bucket.pending
	bucket.pending = 0
	bucket.pendingCount = 0
	return amount
end

-- UI animation preset ids the built-in packs ask Visuals.UI for. Unknown ids are skipped at
-- runtime, so a game can register its own under these names.
FeedbackLogic.UI_PRESETS = table.freeze({
	"BouncyPress",
	"SelectionPulse",
	"Pulse",
	"UpgradePulse",
	"Confirm",
	"Error",
	"ToastIn",
})

local function simulator(): { [string]: Recipe }
	return {
		Tap = {
			{ kind = "ui", preset = "BouncyPress", target = "$gui" },
			{
				kind = "popup",
				text = "+$amount",
				at = "$position",
				options = { style = "tap" },
				throttle = { max = 8, window = 1, coalesce = "amount" },
			},
			{ kind = "vfx", id = "TapPop", at = "$position", throttle = { max = 12, window = 1 } },
			{ kind = "camera", shake = "Tap", when = { every = 5 } },
			{ kind = "sound", cue = "tap", options = { pitchVariance = 0.12 }, throttle = { max = 15, window = 1 } },
		},
		CollectCoin = {
			{ kind = "vfx", id = "CoinBurst", at = "$position", throttle = { max = 10, window = 1 } },
			{ kind = "flyTo", from = "$position", to = "$counter", options = { icon = "coin", count = 5 } },
			{ kind = "ui", action = "countTo", target = "$counter", to = "$total", delay = 0.45 },
			{ kind = "sound", cue = "coin", options = { pitchVariance = 0.08 }, throttle = { max = 12, window = 1 } },
		},
		CollectGem = {
			{ kind = "vfx", id = "GemBurst", at = "$position", throttle = { max = 10, window = 1 } },
			{ kind = "flyTo", from = "$position", to = "$counter", options = { icon = "gem", count = 3 } },
			{ kind = "ui", action = "countTo", target = "$counter", to = "$total", delay = 0.45 },
			{ kind = "sound", cue = "gem", options = { pitchVariance = 0.06 }, throttle = { max = 12, window = 1 } },
		},
		EquipPet = {
			{ kind = "ui", preset = "SelectionPulse", target = "$gui" },
			{ kind = "pet", reaction = "Equip", target = "$pet" },
			{ kind = "vfx", id = "PetEquip", at = "$pet" },
			{ kind = "sound", cue = "pet.happy" },
		},
		UnequipPet = {
			{ kind = "pet", reaction = "Unequip", target = "$pet" },
			{ kind = "vfx", id = "PetUnequip", at = "$pet" },
			{ kind = "sound", cue = "ui.close" },
		},
		HatchEgg = {
			{ kind = "hatch", eggs = "$eggs", config = { origin = "$origin", speed = "$speed", mode = "$mode" } },
		},
		QuestComplete = {
			{ kind = "ui", preset = "ToastIn", target = "$gui" },
			{ kind = "vfx", id = "QuestComplete", at = "$position" },
			{ kind = "sound", cue = "quest.complete" },
		},
		LevelUp = {
			{ kind = "vfx", id = "LevelUp", at = "$position" },
			{ kind = "popup", text = "LEVEL UP!", at = "$position", options = { style = "LevelUpText" } },
			{ kind = "ui", preset = "Pulse", target = "$bar" },
			{ kind = "camera", shake = "SoftImpact" },
			{ kind = "sound", cue = "level.up" },
		},
		UnlockArea = {
			{ kind = "vfx", id = "AreaUnlock", at = "$position" },
			{ kind = "camera", cinematic = "AreaUnlock", target = "$position" },
			{ kind = "vfx", id = "NewArea", at = "$position", delay = 0.6 },
			{ kind = "sound", cue = "success" },
		},
		UpgradeItem = {
			{ kind = "ui", preset = "UpgradePulse", target = "$gui" },
			{ kind = "ui", action = "shine", target = "$gui", delay = 0.1 },
			{ kind = "ui", action = "countTo", target = "$counter", to = "$total" },
			{ kind = "vfx", id = "SparkleBurst", at = "$position" },
			{ kind = "sound", cue = "success" },
		},
		FeedAnimal = {
			{ kind = "vfx", id = "FoodTrail", at = "$projectile", attach = true },
			{ kind = "sound", cue = "food.throw" },
			{ kind = "vfx", id = "FoodSplat", at = "$position", delay = "$travel", optional = { "delay" } },
			{ kind = "object", preset = "Interact", target = "$animal", delay = "$travel", optional = { "delay" } },
			{ kind = "pet", reaction = "HappyReaction", target = "$pet", delay = "$travel", optional = { "delay" } },
			{ kind = "vfx", id = "HeartBurst", at = "$position", delay = "$travel", optional = { "delay" } },
			{ kind = "popup", text = "+$amount", at = "$position", delay = "$travel", optional = { "delay" } },
			{ kind = "sound", cue = "food.hit", delay = "$travel", optional = { "delay" } },
		},
		Purchase = {
			{ kind = "ui", preset = "Confirm", target = "$gui" },
			{ kind = "vfx", id = "Confetti", at = "$position" },
			{ kind = "sound", cue = "success" },
		},
		Error = {
			{ kind = "ui", preset = "Error", target = "$gui" },
			{ kind = "sound", cue = "error", throttle = { max = 4, window = 1 } },
		},
		RebirthDone = {
			{ kind = "vfx", id = "Rebirth", at = "$position" },
			{ kind = "camera", shake = "Impact" },
			{ kind = "ui", action = "flash", color = "#FFFFFF", options = { duration = 0.4 } },
			{ kind = "sound", cue = "level.up" },
		},
		DailyReward = {
			{ kind = "vfx", id = "DailyReward", at = "$position" },
			{ kind = "reward", rarity = "$rarity", reward = "$reward" },
			{ kind = "sound", cue = "success" },
		},
		Achievement = {
			{ kind = "ui", preset = "ToastIn", target = "$gui" },
			{ kind = "vfx", id = "Achievement", at = "$position" },
			{ kind = "sound", cue = "success" },
		},
		RankUp = {
			{ kind = "vfx", id = "RankUp", at = "$position" },
			{ kind = "popup", text = "RANK UP!", at = "$position", options = { style = "LevelUpText" } },
			{ kind = "camera", shake = "SoftImpact" },
			{ kind = "sound", cue = "level.up" },
		},
		AbilityUsed = {
			{ kind = "vfx", id = "AbilityActivate", at = "$position" },
			{ kind = "camera", shake = "Tap" },
			{ kind = "sound", cue = "whoosh" },
		},
		Hit = {
			{ kind = "vfx", id = "HitConfirm", at = "$position", throttle = { max = 12, window = 1 } },
			{ kind = "vfx", id = "ImpactFlash", at = "$position", throttle = { max = 6, window = 1 } },
			{
				kind = "popup",
				text = "-$amount",
				at = "$position",
				options = { style = "damage" },
				throttle = { max = 10, window = 1, coalesce = "amount" },
			},
			{ kind = "camera", shake = "Tap", throttle = { max = 4, window = 1 } },
			{ kind = "sound", cue = "impact", options = { pitchVariance = 0.1 }, throttle = { max = 10, window = 1 } },
		},
		Dash = {
			{ kind = "vfx", id = "DashTrail", at = "$character", attach = true, options = { duration = 0.35 } },
			{ kind = "sound", cue = "whoosh", options = { pitchVariance = 0.1 } },
		},
	}
end

-- Fewer steps and no camera movement: for calm games and low-end devices.
local function minimal(): { [string]: Recipe }
	return {
		Tap = {
			{ kind = "ui", preset = "BouncyPress", target = "$gui" },
			{ kind = "sound", cue = "tap", throttle = { max = 10, window = 1 } },
		},
		CollectCoin = {
			{ kind = "flyTo", from = "$position", to = "$counter", options = { icon = "coin", count = 2 } },
			{ kind = "ui", action = "countTo", target = "$counter", to = "$total", delay = 0.45 },
			{ kind = "sound", cue = "coin", throttle = { max = 8, window = 1 } },
		},
		CollectGem = {
			{ kind = "flyTo", from = "$position", to = "$counter", options = { icon = "gem", count = 2 } },
			{ kind = "ui", action = "countTo", target = "$counter", to = "$total", delay = 0.45 },
			{ kind = "sound", cue = "gem", throttle = { max = 8, window = 1 } },
		},
		LevelUp = {
			{ kind = "vfx", id = "LevelUp", at = "$position" },
			{ kind = "sound", cue = "level.up" },
		},
		RebirthDone = {
			{ kind = "vfx", id = "Rebirth", at = "$position" },
			{ kind = "sound", cue = "level.up" },
		},
		RankUp = {
			{ kind = "vfx", id = "RankUp", at = "$position" },
			{ kind = "sound", cue = "level.up" },
		},
		AbilityUsed = {
			{ kind = "vfx", id = "AbilityActivate", at = "$position" },
		},
		Hit = {
			{ kind = "vfx", id = "HitConfirm", at = "$position", throttle = { max = 8, window = 1 } },
			{
				kind = "popup",
				text = "-$amount",
				at = "$position",
				options = { style = "damage" },
				throttle = { max = 6, window = 1, coalesce = "amount" },
			},
		},
	}
end

-- Heavier hits and a few combat-only events.
local function combat(): { [string]: Recipe }
	return {
		Hit = {
			{ kind = "vfx", id = "HitConfirm", at = "$position", throttle = { max = 14, window = 1 } },
			{ kind = "vfx", id = "ImpactFlash", at = "$position", throttle = { max = 8, window = 1 } },
			{
				kind = "vfx",
				id = "Shockwave",
				at = "$position",
				when = { field = "amount", min = 100 },
				throttle = { max = 3, window = 1 },
			},
			{
				kind = "popup",
				text = "-$amount",
				at = "$position",
				options = { style = "damage" },
				throttle = { max = 12, window = 1, coalesce = "amount" },
			},
			{
				kind = "camera",
				shake = "Tap",
				when = { field = "amount", max = 99 },
				throttle = { max = 5, window = 1 },
			},
			{
				kind = "camera",
				shake = "SoftImpact",
				when = { field = "amount", min = 100 },
				throttle = { max = 2, window = 1 },
			},
			{ kind = "sound", cue = "impact", options = { pitchVariance = 0.12 }, throttle = { max = 12, window = 1 } },
		},
		Critical = {
			{ kind = "vfx", id = "HitConfirm", at = "$position" },
			{ kind = "vfx", id = "Shockwave", at = "$position" },
			{ kind = "popup", text = "CRIT -$amount", at = "$position", options = { style = "critical" } },
			{ kind = "camera", shake = "Impact", throttle = { max = 2, window = 1 } },
			{ kind = "sound", cue = "impact", options = { pitch = 0.85 } },
		},
		ElementHit = {
			{ kind = "vfx", id = "ElementBurst", at = "$position", params = { element = "$element" } },
			{ kind = "sound", cue = "impact", options = { pitchVariance = 0.1 } },
		},
		AbilityUsed = {
			{ kind = "vfx", id = "AbilityActivate", at = "$position" },
			{ kind = "vfx", id = "EnergyBurst", at = "$position", delay = 0.08 },
			{ kind = "camera", shake = "SoftImpact" },
			{ kind = "sound", cue = "whoosh" },
		},
		AbilityCharge = {
			{
				kind = "vfx",
				id = "AbilityCharge",
				at = "$character",
				attach = true,
				options = { duration = "$duration" },
			},
		},
		CooldownReady = {
			{ kind = "vfx", id = "CooldownReady", at = "$position" },
			{ kind = "ui", preset = "Pulse", target = "$gui" },
			{ kind = "sound", cue = "ui.pop" },
		},
		Dash = {
			{ kind = "vfx", id = "DashTrail", at = "$character", attach = true, options = { duration = 0.35 } },
			{ kind = "vfx", id = "SpeedTrail", at = "$character", attach = true, options = { duration = 0.5 } },
			{ kind = "sound", cue = "whoosh", options = { pitchVariance = 0.1 } },
		},
	}
end

local PACKS: { [string]: () -> { [string]: Recipe } } = {
	Simulator = simulator,
	Minimal = minimal,
	Combat = combat,
}

-- Names of the built-in packs. "Simulator" is the base; the others override some of its events.
function FeedbackLogic.packs(): { string }
	return { "Combat", "Minimal", "Simulator" }
end

-- A fresh copy of a built-in pack (event -> recipe), or nil for an unknown name.
function FeedbackLogic.pack(name: string): { [string]: Recipe }?
	local build = PACKS[name]
	return if build then build() else nil
end

-- Returns `recipes` with the pack's events replaced. Events the pack does not define are kept.
-- Errors when a recipe in the pack is invalid.
function FeedbackLogic.apply(recipes: { [string]: Recipe }, pack: { [string]: Recipe }): { [string]: Recipe }
	assert(type(pack) == "table", "a pack is a table of event -> recipe")
	local merged = table.clone(recipes)
	for event, recipe in pack do
		assert(type(event) == "string" and event ~= "", "event names must be non-empty strings")
		local ok, message = FeedbackLogic.validate(recipe)
		assert(ok, "invalid recipe for " .. event .. ": " .. tostring(message))
		merged[event] = recipe
	end
	return merged
end

return FeedbackLogic
