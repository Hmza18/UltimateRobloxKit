--!strict
-- Settings schema validation and value coercion. Pure Luau. Components/SettingsPanel builds rows
-- from a schema and calls applyChange; the game decides what to do with the emitted values
-- (save them, send them to the server, apply them locally).
--
-- Entry kinds:
--   toggle   { key, kind = "toggle", label, default: boolean }
--   slider   { key, kind = "slider", label, default, min, max, step? }
--   dropdown { key, kind = "dropdown", label, default, options = { "Low", "High" } }
--   keybind  { key, kind = "keybind", label, default = "E" }  (display only: a KeyCode name)
-- Optional on every entry: section (string), description (string), labelKey (localisation key).

export type Entry = {
	key: string,
	kind: string,
	label: string?,
	labelKey: string?,
	description: string?,
	section: string?,
	default: any,
	min: number?,
	max: number?,
	step: number?,
	options: { string }?,
}

export type Schema = { Entry }
export type Values = { [string]: any }

local SettingsSchema = {}

SettingsSchema.KINDS = { "toggle", "slider", "dropdown", "keybind" }

local KEY_PATTERN = "^[%a][%w_]*$"
local KEYCODE_PATTERN = "^[%a][%w]*$"

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Coerces `value` for `entry`. Sliders clamp and snap to step; dropdowns must name an option;
-- toggles need a boolean; keybinds need a KeyCode-like name. Returns (true, value) or (false, reason).
function SettingsSchema.coerce(entry: Entry, value: any): (boolean, any)
	local kind = entry.kind
	if kind == "toggle" then
		if type(value) ~= "boolean" then
			return false, "expected a boolean"
		end
		return true, value
	elseif kind == "slider" then
		if not isFinite(value) then
			return false, "expected a finite number"
		end
		local min = entry.min or 0
		local max = math.max(entry.max or 1, min)
		local clamped = math.clamp(value, min, max)
		local step = entry.step
		if step and step > 0 then
			clamped = min + math.floor((clamped - min) / step + 0.5) * step
			clamped = math.clamp(clamped, min, max)
			-- Remove floating point noise such as 0.30000000000000004.
			clamped = math.floor(clamped * 1e6 + 0.5) / 1e6
		end
		return true, clamped
	elseif kind == "dropdown" then
		local options = entry.options or {}
		if type(value) ~= "string" or table.find(options, value) == nil then
			return false, "not one of the options"
		end
		return true, value
	elseif kind == "keybind" then
		if type(value) ~= "string" or string.find(value, KEYCODE_PATTERN) == nil or #value > 32 then
			return false, "expected a KeyCode name"
		end
		return true, value
	end
	return false, "unknown kind " .. tostring(kind)
end

-- Every problem with a schema as "<key>: <reason>". An empty list means it is valid.
function SettingsSchema.validate(schema: any): { string }
	local errors: { string } = {}
	if type(schema) ~= "table" then
		return { "schema must be an array of entries" }
	end
	local seen: { [string]: boolean } = {}
	for index, entry in schema do
		local label = "entry " .. tostring(index)
		if type(entry) ~= "table" then
			table.insert(errors, label .. ": must be a table")
			continue
		end
		if type(entry.key) ~= "string" or string.find(entry.key, KEY_PATTERN) == nil then
			table.insert(errors, label .. ": key must be an identifier")
			continue
		end
		label = entry.key
		if seen[entry.key] then
			table.insert(errors, label .. ": duplicate key")
		end
		seen[entry.key] = true
		if table.find(SettingsSchema.KINDS, entry.kind) == nil then
			table.insert(errors, label .. ": unknown kind " .. tostring(entry.kind))
			continue
		end
		if entry.kind == "slider" then
			if not isFinite(entry.min) or not isFinite(entry.max) or entry.min >= entry.max then
				table.insert(errors, label .. ": slider needs finite min < max")
				continue
			end
			if entry.step ~= nil and (not isFinite(entry.step) or entry.step <= 0) then
				table.insert(errors, label .. ": step must be a positive number")
			end
		elseif entry.kind == "dropdown" then
			if type(entry.options) ~= "table" or #entry.options == 0 then
				table.insert(errors, label .. ": dropdown needs options")
				continue
			end
			for _, option in entry.options do
				if type(option) ~= "string" then
					table.insert(errors, label .. ": options must be strings")
					break
				end
			end
		end
		local ok, reason = SettingsSchema.coerce(entry, entry.default)
		if not ok then
			table.insert(errors, label .. ": default " .. tostring(reason))
		end
	end
	return errors
end

function SettingsSchema.defaults(schema: Schema): Values
	local values: Values = {}
	for _, entry in schema do
		values[entry.key] = entry.default
	end
	return values
end

function SettingsSchema.find(schema: Schema, key: string): Entry?
	for _, entry in schema do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

-- Loaded or remote values with every missing or invalid value replaced by its default and
-- unknown keys removed. Never trust saved settings blindly.
function SettingsSchema.sanitize(schema: Schema, values: any): Values
	local source: { [any]: any } = if type(values) == "table" then values else {}
	local clean: Values = {}
	for _, entry in schema do
		local ok, coerced = SettingsSchema.coerce(entry, source[entry.key])
		clean[entry.key] = if ok then coerced else entry.default
	end
	return clean
end

-- Applies one change. Returns the new values table (the input is not modified), whether the value
-- actually changed, and an error message when the change was rejected.
function SettingsSchema.applyChange(schema: Schema, values: Values, key: string, value: any): (Values, boolean, string?)
	local entry = SettingsSchema.find(schema, key)
	if entry == nil then
		return values, false, "unknown setting " .. tostring(key)
	end
	local ok, coerced = SettingsSchema.coerce(entry, value)
	if not ok then
		return values, false, tostring(coerced)
	end
	if values[key] == coerced then
		return values, false, nil
	end
	local nextValues = table.clone(values)
	nextValues[key] = coerced
	return nextValues, true, nil
end

-- Sections in first-appearance order, each with its entries. Entries without a section go to "".
function SettingsSchema.sections(schema: Schema): { { name: string, entries: { Entry } } }
	local order: { { name: string, entries: { Entry } } } = {}
	local byName: { [string]: { name: string, entries: { Entry } } } = {}
	for _, entry in schema do
		local name = entry.section or ""
		local section = byName[name]
		if section == nil then
			section = { name = name, entries = {} }
			byName[name] = section
			table.insert(order, section)
		end
		table.insert(section.entries, entry)
	end
	return order
end

-- Slider value as a fraction 0..1 of its range, and back.
function SettingsSchema.toFraction(entry: Entry, value: number): number
	local min = entry.min or 0
	local max = entry.max or 1
	if max <= min then
		return 0
	end
	return math.clamp((value - min) / (max - min), 0, 1)
end

function SettingsSchema.fromFraction(entry: Entry, fraction: number): number
	local min = entry.min or 0
	local max = entry.max or 1
	local _, value = SettingsSchema.coerce(entry, min + (max - min) * math.clamp(fraction, 0, 1))
	return value
end

-- Next or previous dropdown option, wrapping around.
function SettingsSchema.cycleOption(entry: Entry, current: string, delta: number): string
	local options = entry.options or {}
	if #options == 0 then
		return current
	end
	local index = table.find(options, current) or 1
	local nextIndex = ((index - 1 + delta) % #options) + 1
	return options[nextIndex]
end

return SettingsSchema
