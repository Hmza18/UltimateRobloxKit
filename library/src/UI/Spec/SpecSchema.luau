--!strict
-- Screen spec validation and defaults (pure Luau, no Roblox globals).
--
--   local issues = SpecSchema.validate(spec)   -- { { path = "body[3].price", message = "..." } }, empty = valid
--   local full = SpecSchema.withDefaults(spec) -- a new table with every default filled in
--
-- The rules follow docs/architecture/ui-generation.md section 4. ELEMENT_TYPES and RULES are plain
-- data so tools/ui/validate_spec.py can mirror them; both sides share the fixtures in the specs.

local Format = require("../Core/Format")
local IconData = require("../../Icons/IconData")
local Path = require("../Core/Path")
local Style = require("../Style/Style")

-- Visuals/UI/UIPresets is pure data. It is loaded guarded so the schema still works in a project
-- that installed the UI generator without the Visuals module; `motion` ids are then checked by
-- shape only.
local presetsOk, presetsModule = pcall(function(): any
	return require("../../Visuals/UI/UIPresets")
end)
local motionRegistry: any = if presetsOk and type(presetsModule) == "table" then presetsModule.registry else nil

export type Issue = { path: string, message: string }

export type ElementRule = {
	required: { string },
	optional: { string },
	anyOf: { { string } }?, -- at least one field of each group must be present
	interactive: boolean, -- fires an Intent when activated
	container: boolean, -- holds child elements in `items`
}

type Ctx = {
	issues: { Issue },
	style: { [string]: any }?,
	ids: { [string]: string },
	count: number,
	targets: { { path: string, id: string } }, -- tooltip targets, checked once every id is known
}

local SpecSchema = {}

SpecSchema.VERSION = 1

-- Fields every element may carry besides its own.
SpecSchema.COMMON_FIELDS = { "type", "id", "visible", "note", "motion" }

local function rule(
	required: { string },
	optional: { string },
	interactive: boolean,
	container: boolean,
	anyOf: { { string } }?
): ElementRule
	return { required = required, optional = optional, anyOf = anyOf, interactive = interactive, container = container }
end

local CONTROL_OPTIONAL = { "value", "min", "max", "step", "options", "bind" }
local BUTTON_ANY = { { "text", "icon" } }
local CURRENCY_ANY = { { "bind", "value" } }
local SLOT_ANY = { { "icon", "image", "keybind" } }
local ACHIEVEMENT_OPTIONAL =
	{ "description", "icon", "image", "tier", "maxTier", "value", "max", "unlocked", "palette" }
local SLOT_OPTIONAL = { "icon", "image", "count", "rarity", "selected", "equipped", "locked", "action" }
local PET_OPTIONAL = { "icon", "image", "rarity", "stats", "palette", "selected", "equipped", "action" }
local QUEST_OPTIONAL = { "description", "value", "max", "rewards", "state", "claimText", "palette" }

-- The contract table: type -> required and optional fields.
SpecSchema.ELEMENT_TYPES = {
	banner = rule({ "title", "palette", "price" }, { "subtitle", "icon", "image", "badge", "timer" }, true, false),
	product = rule(
		{ "title", "palette", "price" },
		{ "subtitle", "icon", "image", "badge", "gift", "rarity", "owned", "layout" },
		true,
		false
	),
	grid = rule({ "items" }, { "columns", "cellAspect", "gap" }, false, true),
	row = rule({ "items" }, { "gap", "align" }, false, true),
	heading = rule({ "text" }, { "size" }, false, false),
	divider = rule({}, {}, false, false),
	text = rule({ "text" }, { "size", "color" }, false, false),
	button = rule({}, { "text", "icon", "kind", "palette", "action", "price" }, true, false, BUTTON_ANY),
	iconButton = rule({ "icon" }, { "label", "palette", "action", "badge", "shape" }, true, false),
	currency = rule({ "icon" }, { "bind", "value", "format", "palette", "plus", "action" }, true, false, CURRENCY_ANY),
	level = rule({}, { "bind", "level", "value", "max" }, false, false),
	progress = rule({}, { "bind", "value", "max", "palette" }, false, false),
	timer = rule({ "seconds" }, { "format", "icon" }, false, false),
	toggle = rule({ "id", "label" }, CONTROL_OPTIONAL, true, false),
	slider = rule({ "id", "label" }, CONTROL_OPTIONAL, true, false),
	dropdown = rule({ "id", "label" }, CONTROL_OPTIONAL, true, false),
	dayCard = rule({ "day", "reward" }, { "state", "premium", "icon", "palette" }, true, false),
	listRow = rule({ "title" }, { "subtitle", "icon", "value", "progress", "button", "rank", "palette" }, true, false),
	-- The animated components of UI/Game (motion from Visuals/UI).
	premiumButton = rule(
		{},
		{ "text", "icon", "image", "palette", "action", "shine", "glow" },
		true,
		false,
		BUTTON_ANY
	),
	tabBar = rule({ "id", "tabs" }, { "value", "palette" }, true, false),
	modal = rule({ "id", "title" }, { "text", "buttons", "headerPalette", "closable" }, true, false),
	tooltip = rule({ "text", "target" }, { "side" }, false, false),
	xpBar = rule({}, { "bind", "level", "value", "max", "palette" }, false, false),
	inventorySlot = rule({}, SLOT_OPTIONAL, true, false),
	petCard = rule({ "title" }, PET_OPTIONAL, true, false),
	rarityBadge = rule({ "rarity" }, { "text" }, false, false),
	rewardPanel = rule({ "rewards" }, { "title", "columns", "claimText", "claimed", "palette" }, true, false),
	questCard = rule({ "title" }, QUEST_OPTIONAL, true, false),
	achievementCard = rule({ "title" }, ACHIEVEMENT_OPTIONAL, false, false),
	notification = rule({ "title" }, { "text", "kind", "icon", "image", "palette", "duration" }, true, false),
	leaderboardRow = rule({ "title" }, { "rank", "value", "format", "avatar", "highlight", "bind" }, false, false),
	loadingScreen = rule({}, { "title", "icon", "image", "tips", "progress", "palette" }, false, false),
	selectionCard = rule({ "title" }, { "description", "icon", "image", "palette", "selected", "action" }, true, false),
	hotbarSlot = rule({}, { "icon", "image", "keybind", "palette", "cooldown", "action" }, true, false, SLOT_ANY),
	statChip = rule(
		{},
		{ "icon", "image", "value", "format", "prefix", "suffix", "palette", "bind" },
		false,
		false,
		CURRENCY_ANY
	),
} :: { [string]: ElementRule }

local typeNames: { string } = {}
for name in pairs(SpecSchema.ELEMENT_TYPES) do
	table.insert(typeNames, name)
end
table.sort(typeNames)
SpecSchema.TYPE_NAMES = typeNames

SpecSchema.RULES = {
	kinds = { "window", "hud", "popup" },
	topFields = { "spec", "id", "kind", "style", "description", "window", "body", "rails", "popup" },
	windowFields = { "title", "headerPalette", "sizeClass", "closable", "scroll", "width", "height" },
	popupFields = {
		"variant",
		"title",
		"message",
		"icon",
		"amount",
		"palette",
		"rays",
		"confirmText",
		"cancelText",
		"price",
	},
	popupVariants = { "reward", "confirm" },
	sizeClasses = { "sm", "md", "lg", "full" },
	rails = { "left", "right", "top", "bottom", "topLeft", "topRight", "bottomLeft", "bottomRight" },
	priceKinds = { "robux", "currency", "free" },
	priceFields = { "kind", "amount", "currency", "productId", "gamePassId" },
	dayStates = { "claimed", "today", "locked" },
	layouts = { "tall", "wide" },
	aligns = { "left", "center", "right" },
	shapes = { "square", "circle" },
	timerFormats = { "clock", "short" },
	textSizes = { "display", "title", "heading", "label", "caption", "price" },
	columnKeys = { "phone", "tablet", "desktop", "console" },
	progressFields = { "value", "max", "bind", "palette" },
	badgeFields = { "kind", "text" },
	questStates = { "active", "claimable", "claimed" },
	notificationKinds = { "info", "success", "warning", "error" },
	sides = { "top", "bottom", "left", "right" },
	tabFields = { "id", "text", "icon" },
	modalButtonFields = { "id", "text", "kind" },
	chipFields = { "text", "icon", "image" },
	rewardFields = { "icon", "image", "amount", "rarity" },
	motionFields = { "preset", "delay" },
	maxTabs = 8,
	maxModalButtons = 3,
	maxChips = 3,
	maxRewards = 12,
	maxTier = 5,
	maxMotionDelay = 5,
	-- Icons of an imported pack: "pack:name", lowercase kebab-case on both sides of the colon.
	packIconPattern = "^[a-z0-9-]+:[a-z0-9-]+$",
	motionPattern = "^%u%w*$",
	minColumns = 1,
	maxColumns = 6,
	minCellAspect = 0.25,
	maxCellAspect = 4,
	maxElements = 200,
	maxDepth = 5,
	maxOptions = 20,
	maxIdLength = 48,
	maxWindowSize = 4000,
	idPattern = "^[%a_][%w_%-]*$",
	colorPattern = "^#%x%x%x%x%x%x$",
	imagePattern = "^rbx%a*://.+$",
	-- Readability limits in characters (UI rule: short titles read at phone size).
	maxLength = {
		title = 60,
		subtitle = 90,
		heading = 60,
		text = 200,
		message = 90,
		description = 200,
		buttonText = 24,
		label = 40,
		iconLabel = 16,
		badgeText = 12,
		reward = 24,
		amount = 24,
		option = 24,
		note = 200,
		keybind = 4,
		affix = 8,
	} :: { [string]: number },
}

local RULES = SpecSchema.RULES
local ELEMENT_TYPES = SpecSchema.ELEMENT_TYPES

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, item in ipairs(list) do
		set[item] = true
	end
	return set
end

local KINDS = toSet(RULES.kinds)
local TOP_FIELDS = toSet(RULES.topFields)
local WINDOW_FIELDS = toSet(RULES.windowFields)
local POPUP_FIELDS = toSet(RULES.popupFields)
local POPUP_VARIANTS = toSet(RULES.popupVariants)
local SIZE_CLASSES = toSet(RULES.sizeClasses)
local RAILS = toSet(RULES.rails)
local PRICE_KINDS = toSet(RULES.priceKinds)
local PRICE_FIELDS = toSet(RULES.priceFields)
local DAY_STATES = toSet(RULES.dayStates)
local LAYOUTS = toSet(RULES.layouts)
local ALIGNS = toSet(RULES.aligns)
local SHAPES = toSet(RULES.shapes)
local TIMER_FORMATS = toSet(RULES.timerFormats)
local TEXT_SIZES = toSet(RULES.textSizes)
local COLUMN_KEYS = toSet(RULES.columnKeys)
local PROGRESS_FIELDS = toSet(RULES.progressFields)
local BADGE_FIELDS = toSet(RULES.badgeFields)
local QUEST_STATES = toSet(RULES.questStates)
local NOTIFICATION_KINDS = toSet(RULES.notificationKinds)
local SIDES = toSet(RULES.sides)
local TAB_FIELDS = toSet(RULES.tabFields)
local MODAL_BUTTON_FIELDS = toSet(RULES.modalButtonFields)
local CHIP_FIELDS = toSet(RULES.chipFields)
local REWARD_FIELDS = toSet(RULES.rewardFields)
local MOTION_FIELDS = toSet(RULES.motionFields)
local COMMON = toSet(SpecSchema.COMMON_FIELDS)

-- The Visuals UI preset ids `motion` may name (empty when the Visuals module is not installed).
-- tools/ui/spec_rules.py mirrors this list; the parity spec keeps the two equal.
SpecSchema.MOTION_PRESETS = (if motionRegistry ~= nil then motionRegistry:ids() else {}) :: { string }

local ICON_NAMES: { [string]: boolean } = {}
for _, entry in ipairs(IconData.icons) do
	ICON_NAMES[entry.name] = true
end

-- Helpers ----------------------------------------------------------------------------------------

local function add(ctx: Ctx, path: string, message: string)
	table.insert(ctx.issues, { path = path, message = message })
end

local function join(path: string, key: string): string
	if path == "" then
		return key
	end
	return path .. "." .. key
end

local function index(path: string, i: number): string
	return path .. "[" .. tostring(i) .. "]"
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: any): boolean
	return isFiniteNumber(value) and math.floor(value) == value
end

-- True for a table whose keys are exactly 1..n (an empty table counts as an array).
local function isArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count == #value
end

local function isObject(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if next(value) == nil then
		return true
	end
	return #value == 0
end

local function sortedKeys(value: { [any]: any }): ({ string }, { any })
	local keys: { string } = {}
	local others: { any } = {}
	for key in pairs(value) do
		if type(key) == "string" then
			table.insert(keys, key)
		else
			table.insert(others, key)
		end
	end
	table.sort(keys, function(a: string, b: string): boolean
		return a < b
	end)
	return keys, others
end

local function textLength(text: string): number
	return utf8.len(text) or #text
end

-- Exposed so tools and the playground can check icon names the same way.
function SpecSchema.isIcon(name: any): boolean
	if type(name) ~= "string" or name == "" then
		return false
	end
	if ICON_NAMES[name] then
		return true
	end
	if SpecSchema.isPackIcon(name) then
		return true
	end
	local base = string.match(name, "^(.+)%-color$")
	return base ~= nil and ICON_NAMES[base] == true
end

local function isKebab(text: string): boolean
	return string.find(text, "^[a-z0-9]+[a-z0-9%-]*$") ~= nil
		and string.find(text, "--", 1, true) == nil
		and string.sub(text, -1) ~= "-"
end

-- "pack:name": an icon of an imported pack (Visuals/Icons). Only the shape is checked here; the
-- pack itself is registered at runtime, so a missing pack icon shows nothing rather than failing.
function SpecSchema.isPackIcon(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	local pack, icon = string.match(name, "^([^:]+):([^:]+)$")
	return pack ~= nil and icon ~= nil and isKebab(pack) and isKebab(icon)
end

-- A Visuals UI preset id. Without the Visuals module any PascalCase id passes.
function SpecSchema.isMotionPreset(id: any): boolean
	if type(id) ~= "string" or string.find(id, RULES.motionPattern) == nil then
		return false
	end
	if motionRegistry == nil then
		return true
	end
	return motionRegistry:has(id) == true
end

function SpecSchema.isId(value: any): boolean
	return type(value) == "string" and #value <= RULES.maxIdLength and string.find(value, RULES.idPattern) ~= nil
end

-- "OpenPanel:Shop;Fire:Buy,starter": every ;-separated part is Name or Name:args.
function SpecSchema.isAction(value: any): boolean
	if type(value) ~= "string" or #value > 200 then
		return false
	end
	local calls = 0
	for _, part in ipairs(string.split(value, ";")) do
		local text = string.match(part, "^%s*(.-)%s*$") or ""
		if text ~= "" then
			if string.find(text, "^[%w_]+$") == nil and string.find(text, "^[%w_]+%s*:") == nil then
				return false
			end
			calls += 1
		end
	end
	return calls > 0
end

function SpecSchema.isBindPath(value: any): boolean
	return type(value) == "string" and value ~= "" and Path.isValid(value)
end

-- Field checks -----------------------------------------------------------------------------------

local function checkText(ctx: Ctx, path: string, value: any, limitName: string, label: string)
	if type(value) ~= "string" then
		add(ctx, path, label .. " must be a string")
		return
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		add(ctx, path, label .. " must not be empty")
		return
	end
	local limit = RULES.maxLength[limitName]
	local length = textLength(value)
	if length > limit then
		add(ctx, path, string.format("%s is %d characters; the limit is %d", label, length, limit))
	end
end

local function checkBoolean(ctx: Ctx, path: string, value: any, label: string)
	if type(value) ~= "boolean" then
		add(ctx, path, label .. " must be true or false")
	end
end

local function checkEnum(ctx: Ctx, path: string, value: any, allowed: { [string]: boolean }, label: string)
	if type(value) ~= "string" or not allowed[value] then
		add(ctx, path, "unknown " .. label .. " " .. tostring(value))
	end
end

local function checkNumber(ctx: Ctx, path: string, value: any, label: string, min: number?, max: number?)
	if not isFiniteNumber(value) then
		add(ctx, path, label .. " must be a number")
		return
	end
	if min ~= nil and value < min then
		add(ctx, path, label .. " must be at least " .. tostring(min))
	elseif max ~= nil and value > max then
		add(ctx, path, label .. " must be at most " .. tostring(max))
	end
end

local function checkInteger(ctx: Ctx, path: string, value: any, label: string, min: number?, max: number?)
	if not isInteger(value) then
		add(ctx, path, label .. " must be a whole number")
		return
	end
	checkNumber(ctx, path, value, label, min, max)
end

local function checkPalette(ctx: Ctx, path: string, value: any)
	local style = ctx.style
	if type(value) ~= "string" then
		add(ctx, path, "palette must be a palette name")
	elseif style ~= nil and not Style.hasPalette(style, value) then
		add(ctx, path, "unknown palette " .. value)
	end
end

local function checkStyleKey(ctx: Ctx, path: string, value: any, group: string, label: string)
	if type(value) ~= "string" then
		add(ctx, path, label .. " must be a string")
		return
	end
	local style = ctx.style
	if style == nil then
		return
	end
	local entries = style[group]
	if type(entries) ~= "table" or entries[value] == nil then
		add(ctx, path, "unknown " .. label .. " " .. value)
	end
end

local function checkIcon(ctx: Ctx, path: string, value: any)
	if type(value) ~= "string" or value == "" then
		add(ctx, path, "icon must be an icon name")
	elseif not SpecSchema.isIcon(value) then
		add(ctx, path, "unknown icon " .. value)
	end
end

local function checkImage(ctx: Ctx, path: string, value: any)
	if type(value) ~= "string" or string.find(value, RULES.imagePattern) == nil then
		add(ctx, path, "image must be an asset id such as rbxassetid://123")
	end
end

local function checkBind(ctx: Ctx, path: string, value: any)
	if not SpecSchema.isBindPath(value) then
		add(ctx, path, "invalid bind path " .. tostring(value))
	end
end

local function checkAction(ctx: Ctx, path: string, value: any)
	if not SpecSchema.isAction(value) then
		add(ctx, path, "invalid action " .. tostring(value))
	end
end

local function checkUnknown(ctx: Ctx, path: string, value: any, allowed: { [string]: boolean }, owner: string)
	local keys, others = sortedKeys(value)
	for _, key in ipairs(keys) do
		if not allowed[key] then
			add(ctx, join(path, key), "unknown field " .. key .. " for " .. owner)
		end
	end
	for _, key in ipairs(others) do
		add(ctx, join(path, tostring(key)), "unknown field " .. tostring(key) .. " for " .. owner)
	end
end

local function checkPrice(ctx: Ctx, path: string, price: any)
	if not isObject(price) then
		add(ctx, path, "price must be an object")
		return
	end
	checkUnknown(ctx, path, price, PRICE_FIELDS, "price")
	local kind = price.kind
	if kind == nil then
		add(ctx, join(path, "kind"), "kind is required for price")
		return
	end
	if type(kind) ~= "string" or not PRICE_KINDS[kind] then
		add(ctx, join(path, "kind"), "unknown price kind " .. tostring(kind))
		return
	end
	local function ensureId(field: string)
		local value = price[field]
		if value ~= nil and (not isInteger(value) or value < 0) then
			add(ctx, join(path, field), field .. " must be a whole number >= 0 (0 is a placeholder)")
		end
	end
	if kind == "robux" then
		if price.amount == nil then
			add(ctx, join(path, "amount"), "robux prices need an amount")
		else
			checkInteger(ctx, join(path, "amount"), price.amount, "amount", 1)
		end
		if price.productId == nil and price.gamePassId == nil then
			add(ctx, path, "robux prices need productId or gamePassId")
		elseif price.productId ~= nil and price.gamePassId ~= nil then
			add(ctx, path, "robux prices use productId or gamePassId, not both")
		end
		ensureId("productId")
		ensureId("gamePassId")
		if price.currency ~= nil then
			add(ctx, join(path, "currency"), "currency is only used by currency prices")
		end
	elseif kind == "currency" then
		if price.amount == nil then
			add(ctx, join(path, "amount"), "currency prices need an amount")
		else
			checkInteger(ctx, join(path, "amount"), price.amount, "amount", 0)
		end
		if price.currency == nil then
			add(ctx, join(path, "currency"), "currency prices need a currency icon name")
		else
			checkIcon(ctx, join(path, "currency"), price.currency)
		end
		if price.productId ~= nil or price.gamePassId ~= nil then
			add(ctx, path, "productId and gamePassId are only used by robux prices")
		end
	else
		if price.amount ~= nil and price.amount ~= 0 then
			add(ctx, join(path, "amount"), "free prices have no amount")
		end
		if price.currency ~= nil or price.productId ~= nil or price.gamePassId ~= nil then
			add(ctx, path, "free prices take no currency or ids")
		end
	end
end

local function checkBadge(ctx: Ctx, path: string, badge: any)
	if not isObject(badge) then
		add(ctx, path, "badge must be an object")
		return
	end
	checkUnknown(ctx, path, badge, BADGE_FIELDS, "badge")
	if badge.kind == nil then
		add(ctx, join(path, "kind"), "kind is required for badge")
	else
		checkStyleKey(ctx, join(path, "kind"), badge.kind, "badges", "badge kind")
	end
	if badge.text ~= nil then
		checkText(ctx, join(path, "text"), badge.text, "badgeText", "badge text")
	end
end

local function checkColumns(ctx: Ctx, path: string, columns: any)
	local function one(p: string, value: any, label: string)
		if not isInteger(value) or value < RULES.minColumns or value > RULES.maxColumns then
			local message = "%s must be a whole number from %d to %d"
			add(ctx, p, string.format(message, label, RULES.minColumns, RULES.maxColumns))
		end
	end
	if type(columns) == "number" then
		one(path, columns, "columns")
		return
	end
	if not isObject(columns) or next(columns) == nil then
		add(ctx, path, "columns must be a number or { phone, tablet, desktop, console }")
		return
	end
	checkUnknown(ctx, path, columns, COLUMN_KEYS, "columns")
	for _, key in ipairs(RULES.columnKeys) do
		local value = columns[key]
		if value ~= nil then
			one(join(path, key), value, "columns." .. key)
		end
	end
end

-- Elements ---------------------------------------------------------------------------------------

local validateElement: (ctx: Ctx, path: string, element: any, depth: number) -> ()

local function validateList(ctx: Ctx, path: string, list: any, depth: number, label: string, allowEmpty: boolean)
	if type(list) ~= "table" or not isArray(list) then
		add(ctx, path, label .. " must be a list of elements")
		return
	end
	if #list == 0 and not allowEmpty then
		add(ctx, path, label .. " must not be empty")
		return
	end
	for i, element in ipairs(list) do
		validateElement(ctx, index(path, i), element, depth)
	end
end

local TEXT_LIMITS: { [string]: string } = {
	heading = "heading",
	text = "text",
	button = "buttonText",
	premiumButton = "buttonText",
	rarityBadge = "badgeText",
	notification = "subtitle",
}

local function checkMotion(ctx: Ctx, path: string, value: any)
	local function preset(p: string, id: any)
		if not SpecSchema.isMotionPreset(id) then
			add(ctx, p, "unknown motion preset " .. tostring(id))
		end
	end
	if type(value) == "string" then
		preset(path, value)
		return
	end
	if not isObject(value) then
		add(ctx, path, "motion must be a preset id or { preset, delay }")
		return
	end
	checkUnknown(ctx, path, value, MOTION_FIELDS, "motion")
	if value.preset == nil then
		add(ctx, join(path, "preset"), "preset is required for motion")
	else
		preset(join(path, "preset"), value.preset)
	end
	if value.delay ~= nil then
		checkNumber(ctx, join(path, "delay"), value.delay, "delay", 0, RULES.maxMotionDelay)
	end
end

-- A list of 1..limit objects; `each` checks one entry.
local function checkObjects(
	ctx: Ctx,
	path: string,
	value: any,
	label: string,
	limit: number,
	fields: { [string]: boolean },
	each: (p: string, entry: { [string]: any }) -> ()
)
	if type(value) ~= "table" or not isArray(value) or #value == 0 then
		add(ctx, path, label .. " must be a non-empty list")
		return
	end
	if #value > limit then
		add(ctx, path, label .. " has more than " .. tostring(limit) .. " entries")
		return
	end
	for i, entry in ipairs(value) do
		local here = index(path, i)
		if not isObject(entry) then
			add(ctx, here, label .. " entries must be objects")
		else
			checkUnknown(ctx, here, entry, fields, label)
			each(here, entry :: { [string]: any })
		end
	end
end

local function checkTabs(ctx: Ctx, path: string, value: any)
	local seen: { [string]: boolean } = {}
	checkObjects(ctx, path, value, "tabs", RULES.maxTabs, TAB_FIELDS, function(here: string, tab: { [string]: any })
		if tab.id == nil then
			add(ctx, join(here, "id"), "id is required for tabs")
		elseif not SpecSchema.isId(tab.id) then
			add(ctx, join(here, "id"), "id must be an identifier (letters, digits, _ or -)")
		elseif seen[tab.id] then
			add(ctx, join(here, "id"), "duplicate tab id " .. tab.id)
		else
			seen[tab.id] = true
		end
		if tab.text == nil and tab.icon == nil then
			add(ctx, here, "tabs needs text or icon")
		end
		if tab.text ~= nil then
			checkText(ctx, join(here, "text"), tab.text, "buttonText", "text")
		end
		if tab.icon ~= nil then
			checkIcon(ctx, join(here, "icon"), tab.icon)
		end
	end)
end

local function checkModalButtons(ctx: Ctx, path: string, value: any)
	local function each(here: string, button: { [string]: any })
		if button.id == nil then
			add(ctx, join(here, "id"), "id is required for buttons")
		elseif not SpecSchema.isId(button.id) then
			add(ctx, join(here, "id"), "id must be an identifier (letters, digits, _ or -)")
		end
		if button.text == nil then
			add(ctx, join(here, "text"), "text is required for buttons")
		else
			checkText(ctx, join(here, "text"), button.text, "buttonText", "text")
		end
		if button.kind ~= nil then
			checkStyleKey(ctx, join(here, "kind"), button.kind, "buttons", "button kind")
		end
	end
	checkObjects(ctx, path, value, "buttons", RULES.maxModalButtons, MODAL_BUTTON_FIELDS, each)
end

-- Stat and reward chips: { text, icon?, image? }.
local function checkChips(ctx: Ctx, path: string, value: any, label: string)
	checkObjects(ctx, path, value, label, RULES.maxChips, CHIP_FIELDS, function(here: string, chip: { [string]: any })
		if chip.text == nil then
			add(ctx, join(here, "text"), "text is required for " .. label)
		else
			checkText(ctx, join(here, "text"), chip.text, "option", "text")
		end
		if chip.icon ~= nil then
			checkIcon(ctx, join(here, "icon"), chip.icon)
		end
		if chip.image ~= nil then
			checkImage(ctx, join(here, "image"), chip.image)
		end
	end)
end

-- Reward tiles: { icon?, image?, amount?, rarity? }.
local function checkRewards(ctx: Ctx, path: string, value: any)
	local function each(here: string, reward: { [string]: any })
		if reward.icon == nil and reward.image == nil then
			add(ctx, here, "rewards needs icon or image")
		end
		if reward.icon ~= nil then
			checkIcon(ctx, join(here, "icon"), reward.icon)
		end
		if reward.image ~= nil then
			checkImage(ctx, join(here, "image"), reward.image)
		end
		if reward.amount ~= nil then
			checkText(ctx, join(here, "amount"), reward.amount, "amount", "amount")
		end
		if reward.rarity ~= nil then
			checkStyleKey(ctx, join(here, "rarity"), reward.rarity, "rarity", "rarity")
		end
	end
	checkObjects(ctx, path, value, "rewards", RULES.maxRewards, REWARD_FIELDS, each)
end

local BOOLEAN_FIELDS = toSet({
	"visible",
	"gift",
	"owned",
	"premium",
	"plus",
	"shine",
	"glow",
	"closable",
	"selected",
	"equipped",
	"locked",
	"claimed",
	"unlocked",
	"highlight",
})

local function checkField(ctx: Ctx, kind: string, key: string, path: string, value: any, depth: number)
	if key == "type" or key == "id" then
		return -- checked by validateElement
	elseif key == "note" then
		checkText(ctx, path, value, "note", key)
	elseif key == "motion" then
		checkMotion(ctx, path, value)
	elseif key == "description" then
		checkText(ctx, path, value, "subtitle", "description")
	elseif key == "claimText" then
		checkText(ctx, path, value, "buttonText", "claimText")
	elseif key == "keybind" then
		checkText(ctx, path, value, "keybind", "keybind")
	elseif key == "prefix" or key == "suffix" then
		checkText(ctx, path, value, "affix", key)
	elseif key == "tabs" then
		checkTabs(ctx, path, value)
	elseif key == "buttons" then
		checkModalButtons(ctx, path, value)
	elseif key == "stats" then
		checkChips(ctx, path, value, "stats")
	elseif key == "rewards" then
		if kind == "rewardPanel" then
			checkRewards(ctx, path, value)
		else
			checkChips(ctx, path, value, "rewards")
		end
	elseif key == "target" then
		if not SpecSchema.isId(value) then
			add(ctx, path, "target must be the id of another element")
		else
			table.insert(ctx.targets, { path = path, id = value })
		end
	elseif key == "side" then
		checkEnum(ctx, path, value, SIDES, "side")
	elseif key == "tier" or key == "maxTier" then
		checkInteger(ctx, path, value, key, 0, RULES.maxTier)
	elseif key == "tips" then
		if type(value) ~= "table" or not isArray(value) or #value == 0 then
			add(ctx, path, "tips must be a non-empty list of strings")
		elseif #value > RULES.maxOptions then
			add(ctx, path, "tips has more than " .. tostring(RULES.maxOptions) .. " entries")
		else
			for i, tip in ipairs(value) do
				checkText(ctx, index(path, i), tip, "text", "tip")
			end
		end
	elseif key == "title" then
		checkText(ctx, path, value, "title", "title")
	elseif key == "subtitle" then
		checkText(ctx, path, value, "subtitle", "subtitle")
	elseif key == "text" then
		checkText(ctx, path, value, TEXT_LIMITS[kind] or "text", "text")
	elseif key == "label" then
		checkText(ctx, path, value, if kind == "iconButton" then "iconLabel" else "label", "label")
	elseif key == "reward" then
		checkText(ctx, path, value, "reward", "reward")
	elseif key == "palette" or key == "headerPalette" then
		checkPalette(ctx, path, value)
	elseif key == "price" then
		checkPrice(ctx, path, value)
	elseif key == "icon" then
		checkIcon(ctx, path, value)
	elseif key == "image" or key == "avatar" then
		checkImage(ctx, path, value)
	elseif key == "badge" then
		checkBadge(ctx, path, value)
	elseif key == "timer" or key == "seconds" or key == "duration" or key == "cooldown" then
		checkNumber(ctx, path, value, key, 0)
	elseif BOOLEAN_FIELDS[key] then
		checkBoolean(ctx, path, value, key)
	elseif key == "rarity" then
		checkStyleKey(ctx, path, value, "rarity", "rarity")
	elseif key == "layout" then
		checkEnum(ctx, path, value, LAYOUTS, "layout")
	elseif key == "align" then
		checkEnum(ctx, path, value, ALIGNS, "align")
	elseif key == "shape" then
		checkEnum(ctx, path, value, SHAPES, "shape")
	elseif key == "state" then
		if kind == "questCard" then
			checkEnum(ctx, path, value, QUEST_STATES, "questCard state")
		else
			checkEnum(ctx, path, value, DAY_STATES, "dayCard state")
		end
	elseif key == "items" then
		validateList(ctx, path, value, depth + 1, "items", false)
	elseif key == "columns" then
		if kind == "rewardPanel" then
			checkInteger(ctx, path, value, key, RULES.minColumns, RULES.maxColumns)
		else
			checkColumns(ctx, path, value)
		end
	elseif key == "cellAspect" then
		checkNumber(ctx, path, value, key, RULES.minCellAspect, RULES.maxCellAspect)
	elseif key == "gap" then
		checkStyleKey(ctx, path, value, "spacing", "gap")
	elseif key == "size" then
		checkEnum(ctx, path, value, TEXT_SIZES, "text size")
	elseif key == "color" then
		if type(value) ~= "string" or string.find(value, RULES.colorPattern) == nil then
			add(ctx, path, "color must be #RRGGBB")
		end
	elseif key == "kind" then
		if kind == "notification" then
			checkEnum(ctx, path, value, NOTIFICATION_KINDS, "notification kind")
		else
			checkStyleKey(ctx, path, value, "buttons", "button kind")
		end
	elseif key == "action" then
		checkAction(ctx, path, value)
	elseif key == "bind" then
		checkBind(ctx, path, value)
	elseif key == "format" then
		if kind == "timer" then
			checkEnum(ctx, path, value, TIMER_FORMATS, "timer format")
		elseif type(value) ~= "string" or not Format.has((Format.parseSpec(value))) then
			add(ctx, path, "unknown format " .. tostring(value))
		end
	elseif key == "level" or key == "count" then
		checkInteger(ctx, path, value, key, 0)
	elseif key == "max" then
		if kind == "slider" then
			checkNumber(ctx, path, value, key)
		else
			checkNumber(ctx, path, value, key, 0)
			if value == 0 then
				add(ctx, path, "max must be greater than 0")
			end
		end
	elseif key == "min" then
		checkNumber(ctx, path, value, key)
	elseif key == "step" then
		checkNumber(ctx, path, value, key)
		if isFiniteNumber(value) and value <= 0 then
			add(ctx, path, "step must be greater than 0")
		end
	elseif key == "value" then
		if kind == "toggle" then
			checkBoolean(ctx, path, value, key)
		elseif kind == "dropdown" then
			checkText(ctx, path, value, "option", "value")
		elseif kind == "listRow" then
			if type(value) == "string" then
				checkText(ctx, path, value, "label", "value")
			elseif not isFiniteNumber(value) then
				add(ctx, path, "value must be a string or a number")
			end
		elseif kind == "statChip" then
			if type(value) == "string" then
				checkText(ctx, path, value, "option", "value")
			elseif not isFiniteNumber(value) then
				add(ctx, path, "value must be a string or a number")
			end
		elseif kind == "tabBar" then
			if not SpecSchema.isId(value) then
				add(ctx, path, "value must be a tab id")
			end
		elseif kind == "slider" or kind == "leaderboardRow" then
			checkNumber(ctx, path, value, key)
		else
			checkNumber(ctx, path, value, key, 0)
		end
	elseif key == "options" then
		if type(value) ~= "table" or not isArray(value) or #value == 0 then
			add(ctx, path, "options must be a non-empty list of strings")
		elseif #value > RULES.maxOptions then
			add(ctx, path, "options has more than " .. tostring(RULES.maxOptions) .. " entries")
		else
			for i, option in ipairs(value) do
				checkText(ctx, index(path, i), option, "option", "option")
			end
		end
	elseif key == "day" then
		checkInteger(ctx, path, value, key, 1, 31)
	elseif key == "rank" then
		checkInteger(ctx, path, value, key, 1)
	elseif key == "progress" then
		if kind == "loadingScreen" then
			checkNumber(ctx, path, value, key, 0, 1)
		elseif not isObject(value) then
			add(ctx, path, "progress must be an object { value, max, bind, palette }")
		else
			checkUnknown(ctx, path, value, PROGRESS_FIELDS, "progress")
			if value.value ~= nil then
				checkNumber(ctx, join(path, "value"), value.value, "value", 0)
			end
			if value.max ~= nil then
				checkNumber(ctx, join(path, "max"), value.max, "max", 0)
			end
			if value.bind ~= nil then
				checkBind(ctx, join(path, "bind"), value.bind)
			end
			if value.palette ~= nil then
				checkPalette(ctx, join(path, "palette"), value.palette)
			end
		end
	elseif key == "button" then
		if not isObject(value) then
			add(ctx, path, "button must be a button element")
		elseif value.type ~= nil and value.type ~= "button" then
			add(ctx, join(path, "type"), "a listRow button must have type button")
		else
			local copy = table.clone(value)
			copy.type = "button"
			validateElement(ctx, path, copy, depth + 1)
			ctx.count -= 1 -- part of the row, not a separate element
		end
	end
end

local function crossChecks(ctx: Ctx, kind: string, path: string, element: { [string]: any })
	if kind == "slider" then
		local min, max, value = element.min, element.max, element.value
		local lo = if isFiniteNumber(min) then min else 0
		local hi = if isFiniteNumber(max) then max else 1
		if lo >= hi then
			add(ctx, join(path, "max"), "max must be greater than min")
		elseif isFiniteNumber(value) and (value < lo or value > hi) then
			add(ctx, join(path, "value"), "value must be between min and max")
		end
	elseif kind == "dropdown" then
		local options = element.options
		if options == nil then
			add(ctx, join(path, "options"), "options is required for dropdown")
		elseif type(element.value) == "string" and type(options) == "table" and isArray(options) then
			if table.find(options, element.value) == nil then
				add(ctx, join(path, "value"), "value must be one of the options")
			end
		end
	elseif kind == "level" or kind == "progress" or kind == "xpBar" then
		local value, max = element.value, element.max
		if isFiniteNumber(value) and isFiniteNumber(max) and value > max then
			add(ctx, join(path, "value"), "value must not exceed max")
		end
	elseif kind == "tabBar" then
		local tabs, value = element.tabs, element.value
		if type(value) == "string" and type(tabs) == "table" and isArray(tabs) then
			local found = false
			for _, tab in ipairs(tabs) do
				if type(tab) == "table" and tab.id == value then
					found = true
				end
			end
			if not found then
				add(ctx, join(path, "value"), "value must be one of the tab ids")
			end
		end
	elseif kind == "achievementCard" then
		local tier, maxTier = element.tier, element.maxTier
		local limit = if isInteger(maxTier) then maxTier else 3
		if isInteger(tier) and tier > limit then
			add(ctx, join(path, "tier"), "tier must not exceed maxTier")
		end
	end
	if kind ~= "slider" and kind ~= "dropdown" and kind ~= "toggle" then
		return
	end
	-- Controls take only the fields that make sense for them.
	local unused: { [string]: { string } } = {
		toggle = { "min", "max", "step", "options" },
		slider = { "options" },
		dropdown = { "min", "max", "step" },
	}
	for _, field in ipairs(unused[kind]) do
		if element[field] ~= nil then
			add(ctx, join(path, field), field .. " is not used by " .. kind)
		end
	end
end

validateElement = function(ctx: Ctx, path: string, element: any, depth: number)
	ctx.count += 1
	if not isObject(element) then
		add(ctx, path, "element must be an object")
		return
	end
	if depth > RULES.maxDepth then
		add(ctx, path, "elements are nested too deeply (limit " .. tostring(RULES.maxDepth) .. ")")
		return
	end
	local kind = element.type
	if kind == nil then
		add(ctx, join(path, "type"), "type is required")
		return
	end
	local def = if type(kind) == "string" then ELEMENT_TYPES[kind] else nil
	if def == nil then
		add(ctx, join(path, "type"), "unknown element type " .. tostring(kind))
		return
	end
	local allowed: { [string]: boolean } = table.clone(COMMON)
	for _, field in ipairs(def.required) do
		allowed[field] = true
	end
	for _, field in ipairs(def.optional) do
		allowed[field] = true
	end
	checkUnknown(ctx, path, element, allowed, kind)
	for _, field in ipairs(def.required) do
		if element[field] == nil then
			add(ctx, join(path, field), field .. " is required for " .. kind)
		end
	end
	for _, group in ipairs(def.anyOf or {}) do
		local found = false
		for _, field in ipairs(group) do
			if element[field] ~= nil then
				found = true
			end
		end
		if not found then
			add(ctx, path, kind .. " needs " .. table.concat(group, " or "))
		end
	end
	local id = element.id
	if id ~= nil then
		if not SpecSchema.isId(id) then
			add(ctx, join(path, "id"), "id must be an identifier (letters, digits, _ or -)")
		elseif ctx.ids[id] ~= nil then
			add(ctx, join(path, "id"), "duplicate id " .. id .. " (first used at " .. ctx.ids[id] .. ")")
		else
			ctx.ids[id] = path
		end
	end
	local keys = sortedKeys(element)
	for _, key in ipairs(keys) do
		if allowed[key] then
			checkField(ctx, kind, key, join(path, key), element[key], depth)
		end
	end
	crossChecks(ctx, kind, path, element)
end

-- Screens ----------------------------------------------------------------------------------------

local function validateWindow(ctx: Ctx, window: any)
	if not isObject(window) then
		add(ctx, "window", "window must be an object")
		return
	end
	checkUnknown(ctx, "window", window, WINDOW_FIELDS, "window")
	if window.title == nil then
		add(ctx, "window.title", "title is required for window")
	else
		checkText(ctx, "window.title", window.title, "title", "title")
	end
	if window.headerPalette ~= nil then
		checkPalette(ctx, "window.headerPalette", window.headerPalette)
	end
	if window.sizeClass ~= nil then
		checkEnum(ctx, "window.sizeClass", window.sizeClass, SIZE_CLASSES, "sizeClass")
	end
	for _, field in ipairs({ "closable", "scroll" }) do
		if window[field] ~= nil then
			checkBoolean(ctx, "window." .. field, window[field], field)
		end
	end
	for _, field in ipairs({ "width", "height" }) do
		if window[field] ~= nil then
			checkNumber(ctx, "window." .. field, window[field], field, 1, RULES.maxWindowSize)
		end
	end
end

local function validateRails(ctx: Ctx, rails: any)
	if not isObject(rails) or next(rails) == nil then
		add(ctx, "rails", "rails must be an object with at least one rail")
		return
	end
	local keys, others = sortedKeys(rails)
	for _, key in ipairs(others) do
		add(ctx, "rails." .. tostring(key), "unknown rail " .. tostring(key))
	end
	for _, name in ipairs(keys) do
		if not RAILS[name] then
			add(ctx, "rails." .. name, "unknown rail " .. name)
		else
			validateList(ctx, "rails." .. name, rails[name], 1, "rail " .. name, false)
		end
	end
end

local function validatePopup(ctx: Ctx, popup: any)
	if not isObject(popup) then
		add(ctx, "popup", "popup must be an object")
		return
	end
	checkUnknown(ctx, "popup", popup, POPUP_FIELDS, "popup")
	if popup.variant == nil then
		add(ctx, "popup.variant", "variant is required for popup")
	else
		checkEnum(ctx, "popup.variant", popup.variant, POPUP_VARIANTS, "popup variant")
	end
	if popup.title == nil then
		add(ctx, "popup.title", "title is required for popup")
	else
		checkText(ctx, "popup.title", popup.title, "title", "title")
	end
	if popup.message ~= nil then
		checkText(ctx, "popup.message", popup.message, "message", "message")
	end
	if popup.icon ~= nil then
		checkIcon(ctx, "popup.icon", popup.icon)
	end
	if popup.amount ~= nil then
		checkText(ctx, "popup.amount", popup.amount, "amount", "amount")
	end
	if popup.palette ~= nil then
		checkPalette(ctx, "popup.palette", popup.palette)
	end
	if popup.rays ~= nil then
		checkBoolean(ctx, "popup.rays", popup.rays, "rays")
	end
	for _, field in ipairs({ "confirmText", "cancelText" }) do
		if popup[field] ~= nil then
			checkText(ctx, "popup." .. field, popup[field], "buttonText", field)
		end
	end
	if popup.price ~= nil then
		checkPrice(ctx, "popup.price", popup.price)
	end
	if popup.variant == "reward" then
		for _, field in ipairs({ "confirmText", "cancelText", "price" }) do
			if popup[field] ~= nil then
				add(ctx, "popup." .. field, field .. " is only used by confirm popups")
			end
		end
	end
end

-- Returns every problem as { path, message }. An empty list means the spec is valid.
function SpecSchema.validate(spec: any): { Issue }
	local ctx: Ctx = { issues = {}, ids = {}, count = 0, targets = {} }
	if not isObject(spec) then
		add(ctx, "", "spec must be an object")
		return ctx.issues
	end
	checkUnknown(ctx, "", spec, TOP_FIELDS, "spec")
	if spec.spec ~= SpecSchema.VERSION then
		add(ctx, "spec", "spec must be " .. tostring(SpecSchema.VERSION))
	end
	if spec.id == nil then
		add(ctx, "id", "id is required")
	elseif not SpecSchema.isId(spec.id) then
		add(ctx, "id", "id must be an identifier (letters, digits, _ or -)")
	end
	if spec.description ~= nil then
		checkText(ctx, "description", spec.description, "description", "description")
	end

	local styleName = spec.style
	if styleName == nil then
		styleName = Style.default()
	end
	if type(styleName) ~= "string" or table.find(Style.names(), styleName) == nil then
		add(ctx, "style", "unknown style " .. tostring(styleName))
	else
		ctx.style = Style.get(styleName)
	end

	local kind = spec.kind
	if kind == nil then
		add(ctx, "kind", "kind is required")
	elseif type(kind) ~= "string" or not KINDS[kind] then
		add(ctx, "kind", "unknown kind " .. tostring(kind))
		kind = nil
	end

	if kind == "window" then
		if spec.window == nil then
			add(ctx, "window", "window is required for window screens")
		else
			validateWindow(ctx, spec.window)
		end
		if spec.body == nil then
			add(ctx, "body", "body is required for window screens")
		else
			validateList(ctx, "body", spec.body, 1, "body", false)
		end
	elseif kind == "hud" then
		if spec.rails == nil then
			add(ctx, "rails", "rails is required for hud screens")
		else
			validateRails(ctx, spec.rails)
		end
	elseif kind == "popup" then
		if spec.popup == nil then
			add(ctx, "popup", "popup is required for popup screens")
		else
			validatePopup(ctx, spec.popup)
		end
		if spec.body ~= nil then
			validateList(ctx, "body", spec.body, 1, "body", true)
		end
	end

	if kind ~= nil then
		local owned: { [string]: { string } } = {
			window = { "window", "body" },
			hud = { "rails" },
			popup = { "popup", "body" },
		}
		for _, field in ipairs({ "window", "body", "rails", "popup" }) do
			if spec[field] ~= nil and table.find(owned[kind], field) == nil then
				add(ctx, field, field .. " is not used by " .. kind .. " screens")
			end
		end
	end

	for _, target in ipairs(ctx.targets) do
		if ctx.ids[target.id] == nil then
			add(ctx, target.path, "no element has the id " .. target.id)
		end
	end

	if ctx.count > RULES.maxElements then
		add(ctx, "", string.format("screen has %d elements; the limit is %d", ctx.count, RULES.maxElements))
	end
	return ctx.issues
end

-- Joins issues into one readable message ("body[2].price: robux prices need ...").
function SpecSchema.format(issues: { Issue }): string
	local lines: { string } = {}
	for _, issue in ipairs(issues) do
		local where = if issue.path == "" then "(spec)" else issue.path
		table.insert(lines, where .. ": " .. issue.message)
	end
	return table.concat(lines, "\n")
end

-- Defaults ---------------------------------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function fill(target: { [string]: any }, defaults: { [string]: any })
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		end
	end
end

SpecSchema.DEFAULT_COLUMNS = { phone = 2, tablet = 3, desktop = 3, console = 3 }

-- Fills all four breakpoints from a number or a partial table.
function SpecSchema.resolveColumns(columns: any): { phone: number, tablet: number, desktop: number, console: number }
	if type(columns) == "number" then
		return { phone = columns, tablet = columns, desktop = columns, console = columns }
	end
	local given: { [string]: any } = if type(columns) == "table" then columns else {}
	local desktop = given.desktop or given.tablet or SpecSchema.DEFAULT_COLUMNS.desktop
	local tablet = given.tablet or given.desktop or SpecSchema.DEFAULT_COLUMNS.tablet
	local phone = given.phone or math.min(tablet, SpecSchema.DEFAULT_COLUMNS.phone)
	local console = given.console or desktop
	return { phone = phone, tablet = tablet, desktop = desktop, console = console }
end

local ELEMENT_DEFAULTS: { [string]: { [string]: any } } = {
	product = { layout = "tall", gift = false, owned = false },
	grid = { cellAspect = 1.25, gap = "md" },
	row = { gap = "md", align = "center" },
	heading = { size = "heading" },
	text = { size = "label" },
	iconButton = { shape = "square" },
	currency = { format = "abbrev", plus = false },
	level = { level = 0, value = 0, max = 100 },
	progress = { value = 0, max = 100, palette = "green" },
	timer = { format = "clock" },
	toggle = { value = false },
	slider = { min = 0, max = 1, step = 0.1 },
	dayCard = { state = "locked", premium = false },
	tooltip = { side = "top" },
	xpBar = { level = 1, value = 0, max = 100 },
	notification = { kind = "info" },
	modal = { closable = true },
}

local function buttonKindFor(price: any): string
	if type(price) == "table" then
		if price.kind == "robux" then
			return "robux"
		elseif price.kind == "currency" then
			return "buy"
		end
	end
	return "primary"
end

type DefaultsCtx = { ids: { [string]: boolean } }

local function collectIds(value: any, ids: { [string]: boolean })
	if type(value) ~= "table" then
		return
	end
	if type(value.id) == "string" then
		ids[value.id] = true
	end
	for _, item in pairs(value) do
		if type(item) == "table" then
			collectIds(item, ids)
		end
	end
end

local function autoId(dctx: DefaultsCtx, key: string): string
	local base = "auto_" .. key
	local candidate = base
	local suffix = 1
	while dctx.ids[candidate] do
		suffix += 1
		candidate = base .. "_" .. tostring(suffix)
	end
	dctx.ids[candidate] = true
	return candidate
end

local defaultElement: (dctx: DefaultsCtx, element: any, key: string) -> ()

local function defaultList(dctx: DefaultsCtx, list: any, key: string)
	if type(list) ~= "table" then
		return
	end
	for i, element in ipairs(list) do
		defaultElement(dctx, element, key .. "_" .. tostring(i))
	end
end

defaultElement = function(dctx: DefaultsCtx, element: any, key: string)
	if type(element) ~= "table" or type(element.type) ~= "string" then
		return
	end
	local kind: string = element.type
	local defaults = ELEMENT_DEFAULTS[kind]
	if defaults then
		fill(element, defaults)
	end
	if kind == "grid" then
		element.columns = SpecSchema.resolveColumns(element.columns)
	elseif kind == "button" then
		if element.kind == nil then
			element.kind = buttonKindFor(element.price)
		end
	elseif kind == "slider" then
		if element.value == nil then
			element.value = element.min
		end
	elseif kind == "dropdown" then
		if element.value == nil and type(element.options) == "table" then
			element.value = element.options[1]
		end
	elseif kind == "tabBar" then
		local first = if type(element.tabs) == "table" then element.tabs[1] else nil
		if element.value == nil and type(first) == "table" then
			element.value = first.id
		end
	elseif kind == "listRow" then
		local button = element.button
		if type(button) == "table" then
			button.type = "button"
			defaultElement(dctx, button, key .. "_button")
		end
		local progress = element.progress
		if type(progress) == "table" then
			fill(progress, { value = 0, max = 100, palette = "green" })
		end
	end
	if element.id == nil then
		local def = ELEMENT_TYPES[kind]
		if def and def.interactive then
			element.id = autoId(dctx, key)
		end
	end
	if element.visible == nil then
		element.visible = true
	end
	if type(element.items) == "table" then
		defaultList(dctx, element.items, key)
	end
end

-- Returns a new spec with every default filled in. Never modifies the input. Tolerates invalid
-- specs (it fills what it can), but Builder always validates first.
function SpecSchema.withDefaults(spec: any): any
	local copy = deepCopy(spec)
	if type(copy) ~= "table" then
		return copy
	end
	local dctx: DefaultsCtx = { ids = {} }
	collectIds(copy, dctx.ids)
	if copy.style == nil then
		copy.style = Style.default()
	end
	if copy.kind == "window" then
		if type(copy.window) == "table" then
			fill(copy.window, { headerPalette = "red", sizeClass = "md", closable = true, scroll = true })
		end
		defaultList(dctx, copy.body, "body")
	elseif copy.kind == "hud" then
		if type(copy.rails) == "table" then
			local names, _ = sortedKeys(copy.rails)
			for _, name in ipairs(names) do
				defaultList(dctx, copy.rails[name], name)
			end
		end
	elseif copy.kind == "popup" then
		local popup = copy.popup
		if type(popup) == "table" then
			if popup.variant == "confirm" then
				fill(popup, {
					palette = "blue",
					confirmText = if popup.price ~= nil then "BUY" else "CONFIRM",
					cancelText = "CANCEL",
					rays = false,
				})
			else
				fill(popup, { palette = "gold", rays = true })
			end
		end
		if copy.body == nil then
			copy.body = {}
		end
		defaultList(dctx, copy.body, "body")
	end
	return copy
end

-- Walks every element (body, rails, items, listRow buttons) depth first: visit(element, path).
function SpecSchema.walk(spec: any, visit: (element: any, path: string) -> ())
	local function walkList(list: any, path: string)
		if type(list) ~= "table" then
			return
		end
		for i, element in ipairs(list) do
			local here = index(path, i)
			if type(element) == "table" then
				visit(element, here)
				local node = element :: any
				walkList(node.items, join(here, "items"))
				if type(node.button) == "table" then
					visit(node.button, join(here, "button"))
				end
			end
		end
	end
	if type(spec) ~= "table" then
		return
	end
	walkList(spec.body, "body")
	if type(spec.rails) == "table" then
		local names, _ = sortedKeys(spec.rails)
		for _, name in ipairs(names) do
			walkList(spec.rails[name], "rails." .. name)
		end
	end
end

table.freeze(SpecSchema.COMMON_FIELDS)
table.freeze(SpecSchema.TYPE_NAMES)

return SpecSchema
