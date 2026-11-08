--!strict
-- Player settings rules. Pure Luau.
-- A schema describes each setting (bool, number range with step, enum, keybind) with a default.
-- Values from clients or saves are validated and clamped against it, saves are versioned and migrated,
-- and only values that differ from the defaults are stored.

export type Def = {
	type: string, -- "bool" | "number" | "enum" | "keybind"
	default: any,
	min: number?, -- number
	max: number?, -- number
	step: number?, -- number: values snap to min + n * step
	options: { string }?, -- enum
	allowed: { string }?, -- keybind: optional allow list of key names
	group: string?, -- for settings menus
	hook: string?, -- how SettingsClient applies it, see SettingsConfig
}

export type Schema = { [string]: Def }
export type Values = { [string]: any }
export type Migration = (values: { [string]: any }) -> { [string]: any }
export type Saved = { version: number, values: { [string]: any } }

local KEY_PATTERN = "^%a[%w]*$"
local MAX_KEY_LENGTH = 32

local Settings = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function roundNoise(value: number): number
	return math.floor(value * 1e6 + 0.5) / 1e6
end

-- Checks a value against one definition. Returns ok and the cleaned value (clamped and snapped
-- for numbers), or false and a reason.
function Settings.coerce(def: Def, value: any): (boolean, any)
	local kind = def.type
	if kind == "bool" then
		if type(value) ~= "boolean" then
			return false, "expected a boolean"
		end
		return true, value
	elseif kind == "number" then
		if not isFinite(value) then
			return false, "expected a finite number"
		end
		local low = def.min or -math.huge
		local high = def.max or math.huge
		if low > high then
			return false, "invalid range"
		end
		local result = math.clamp(value, low, high)
		local step = def.step
		if step and step > 0 then
			local base = def.min or 0
			result = base + math.floor((result - base) / step + 0.5) * step
			result = math.clamp(roundNoise(result), low, high)
		end
		return true, result
	elseif kind == "enum" then
		local options = def.options
		if type(value) ~= "string" or options == nil or table.find(options, value) == nil then
			return false, "not one of the options"
		end
		return true, value
	elseif kind == "keybind" then
		if type(value) ~= "string" or #value > MAX_KEY_LENGTH or string.match(value, KEY_PATTERN) == nil then
			return false, "not a key name"
		end
		local allowed = def.allowed
		if allowed and table.find(allowed, value) == nil then
			return false, "key not allowed"
		end
		return true, value
	end
	return false, "unknown setting type"
end

-- Checks a schema. Returns ok and every problem found.
function Settings.validateSchema(schema: Schema): (boolean, { string })
	local errors: { string } = {}
	if type(schema) ~= "table" then
		return false, { "schema must be a table" }
	end
	for key, def in schema do
		if type(key) ~= "string" or type(def) ~= "table" then
			table.insert(errors, tostring(key) .. ": must be a named table")
			continue
		end
		local low, high = def.min, def.max
		if def.type == "number" and low and high and low > high then
			table.insert(errors, key .. ": min is greater than max")
		end
		if def.type == "enum" and (type(def.options) ~= "table" or #def.options == 0) then
			table.insert(errors, key .. ": enum needs options")
		end
		local ok, cleaned = Settings.coerce(def, def.default)
		if not ok then
			table.insert(errors, key .. ": bad default (" .. tostring(cleaned) .. ")")
		elseif cleaned ~= def.default then
			table.insert(errors, key .. ": default is off the range or step")
		end
	end
	table.sort(errors)
	return #errors == 0, errors
end

function Settings.defaults(schema: Schema): Values
	local values: Values = {}
	for key, def in schema do
		values[key] = def.default
	end
	return values
end

-- Applies changes to a copy of `values`. Unknown keys and invalid values are listed in `rejected`
-- (key -> reason) and leave the old value in place.
function Settings.apply(schema: Schema, values: Values, changes: { [any]: any }): (Values, { [string]: string })
	local result = table.clone(values)
	local rejected: { [string]: string } = {}
	for key, value in changes do
		local name = tostring(key)
		local def = if type(key) == "string" then schema[key] else nil
		if def == nil then
			rejected[name] = "unknown setting"
		else
			local ok, cleaned = Settings.coerce(def, value)
			if ok then
				result[key] = cleaned
			else
				rejected[name] = cleaned
			end
		end
	end
	return result, rejected
end

-- Runs migrations from the saved version up to `currentVersion`. migrations[n] turns version n
-- values into version n + 1. Data without a version counts as version 1. Missing steps are skipped.
function Settings.migrate(data: any, migrations: { [number]: Migration }?, currentVersion: number): (Values, number)
	local values: Values = {}
	local version = 1
	if type(data) == "table" then
		if type(data.values) == "table" then
			values = table.clone(data.values)
		end
		if isFinite(data.version) and data.version >= 1 then
			version = math.floor(data.version)
		end
	end
	while version < currentVersion do
		local step = if migrations then migrations[version] else nil
		if step then
			local ok, migrated = pcall(step, table.clone(values))
			if ok and type(migrated) == "table" then
				values = migrated
			end
		end
		version += 1
	end
	return values, version
end

-- Stores only values that differ from the defaults, so changing a default later reaches everyone
-- who never touched that setting.
function Settings.serialize(schema: Schema, values: Values, version: number): Saved
	local stored: { [string]: any } = {}
	for key, def in schema do
		local value = values[key]
		if value ~= nil and value ~= def.default then
			stored[key] = value
		end
	end
	return { version = version, values = stored }
end

-- Rebuilds values from untrusted saved data: migrates, keeps valid values, uses defaults for the rest
-- and drops keys the schema no longer has.
function Settings.deserialize(
	schema: Schema,
	data: any,
	currentVersion: number,
	migrations: { [number]: Migration }?
): Values
	local saved = Settings.migrate(data, migrations, currentVersion)
	local values = Settings.defaults(schema)
	for key, def in schema do
		local raw = saved[key]
		if raw ~= nil then
			local ok, cleaned = Settings.coerce(def, raw)
			if ok then
				values[key] = cleaned
			end
		end
	end
	return values
end

-- Keys whose values differ between `a` and `b`, sorted.
function Settings.diff(a: Values, b: Values): { string }
	local keys: { string } = {}
	local seen: { [string]: boolean } = {}
	for key, value in a do
		if b[key] ~= value then
			seen[key] = true
		end
	end
	for key, value in b do
		if a[key] ~= value then
			seen[key] = true
		end
	end
	for key in seen do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Keybind settings that share a key: key name -> sorted setting names (only keys used twice or more).
function Settings.keybindConflicts(schema: Schema, values: Values): { [string]: { string } }
	local users: { [string]: { string } } = {}
	for key, def in schema do
		local value = values[key]
		if def.type == "keybind" and type(value) == "string" then
			local list = users[value] or {}
			table.insert(list, key)
			users[value] = list
		end
	end
	local conflicts: { [string]: { string } } = {}
	for keyName, list in users do
		if #list > 1 then
			table.sort(list)
			conflicts[keyName] = list
		end
	end
	return conflicts
end

-- Setting names per group (ungrouped settings go under "General"), each list sorted.
function Settings.groups(schema: Schema): { [string]: { string } }
	local groups: { [string]: { string } } = {}
	for key, def in schema do
		local group = def.group or "General"
		local list = groups[group] or {}
		table.insert(list, key)
		groups[group] = list
	end
	for _, list in groups do
		table.sort(list)
	end
	return groups
end

return Settings
