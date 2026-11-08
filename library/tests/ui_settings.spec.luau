--!strict
-- SettingsSchema: schema validation, coercion, sanitising saved values and applying changes.

local t = require("./lib/t")
local SettingsSchema = require("../src/UI/Core/SettingsSchema")

local SCHEMA: SettingsSchema.Schema = {
	{ key = "Music", kind = "toggle", label = "Music", default = true, section = "Audio" },
	{
		key = "Volume",
		kind = "slider",
		label = "Volume",
		default = 0.8,
		min = 0,
		max = 1,
		step = 0.1,
		section = "Audio",
	},
	{ key = "Quality", kind = "dropdown", label = "Quality", default = "High", options = { "Low", "Medium", "High" } },
	{ key = "Sprint", kind = "keybind", label = "Sprint", default = "LeftShift", section = "Controls" },
}

return {
	["a valid schema has no errors"] = function()
		t.deepEqual(SettingsSchema.validate(SCHEMA), {})
	end,

	["validate reports each broken entry"] = function()
		local errors = SettingsSchema.validate({
			{ key = "A", kind = "toggle", default = "yes" },
			{ key = "B", kind = "slider", default = 1, min = 5, max = 1 },
			{ key = "C", kind = "dropdown", default = "x", options = {} },
			{ key = "A", kind = "toggle", default = false },
			{ key = "bad key", kind = "toggle", default = true },
			{ key = "D", kind = "colour", default = 1 },
		})
		t.equal(#errors, 6)
		t.truthy(string.find(errors[1], "^A: default") ~= nil, errors[1])
		t.truthy(string.find(errors[4], "duplicate") ~= nil, errors[4])
		t.deepEqual(SettingsSchema.validate("nope"), { "schema must be an array of entries" })
	end,

	["sliders clamp and snap to step"] = function()
		local entry = SCHEMA[2]
		local ok, value = SettingsSchema.coerce(entry, 0.34)
		t.truthy(ok)
		t.equal(value, 0.3)
		t.equal(select(2, SettingsSchema.coerce(entry, 7)), 1)
		t.equal(select(2, SettingsSchema.coerce(entry, -2)), 0)
		t.falsy(SettingsSchema.coerce(entry, 0 / 0), "NaN is rejected")
		t.falsy(SettingsSchema.coerce(entry, "0.5"), "strings are rejected")
	end,

	["dropdowns, toggles and keybinds"] = function()
		t.truthy(SettingsSchema.coerce(SCHEMA[3], "Low"))
		t.falsy(SettingsSchema.coerce(SCHEMA[3], "Ultra"))
		t.falsy(SettingsSchema.coerce(SCHEMA[1], 1))
		t.truthy(SettingsSchema.coerce(SCHEMA[4], "ButtonX"))
		t.falsy(SettingsSchema.coerce(SCHEMA[4], "Left Shift"))
	end,

	["defaults and sanitize"] = function()
		local defaults = SettingsSchema.defaults(SCHEMA)
		t.deepEqual(defaults, { Music = true, Volume = 0.8, Quality = "High", Sprint = "LeftShift" })
		local clean = SettingsSchema.sanitize(SCHEMA, { Music = "yes", Volume = 5, Quality = "Low", Hacked = true })
		t.deepEqual(clean, { Music = true, Volume = 1, Quality = "Low", Sprint = "LeftShift" })
		t.deepEqual(SettingsSchema.sanitize(SCHEMA, nil), defaults)
	end,

	["applyChange returns new values and never mutates"] = function()
		local values = SettingsSchema.defaults(SCHEMA)
		local nextValues, changed, err = SettingsSchema.applyChange(SCHEMA, values, "Volume", 0.55)
		t.truthy(changed)
		t.equal(err, nil)
		t.equal(nextValues.Volume, 0.6)
		t.equal(values.Volume, 0.8, "input untouched")
		local same, sameChanged = SettingsSchema.applyChange(SCHEMA, nextValues, "Volume", 0.6)
		t.falsy(sameChanged)
		t.truthy(same == nextValues)
		local _, rejected, reason = SettingsSchema.applyChange(SCHEMA, values, "Quality", "Ultra")
		t.falsy(rejected)
		t.truthy(reason ~= nil)
		local _, unknown, unknownReason = SettingsSchema.applyChange(SCHEMA, values, "Nope", 1)
		t.falsy(unknown)
		t.truthy(string.find(unknownReason or "", "unknown") ~= nil)
	end,

	["sections keep first-appearance order"] = function()
		local sections = SettingsSchema.sections(SCHEMA)
		t.equal(#sections, 3)
		t.equal(sections[1].name, "Audio")
		t.equal(#sections[1].entries, 2)
		t.equal(sections[2].name, "")
		t.equal(sections[3].name, "Controls")
	end,

	["fractions and option cycling"] = function()
		local slider = SCHEMA[2]
		t.near(SettingsSchema.toFraction(slider, 0.25), 0.25)
		t.equal(SettingsSchema.fromFraction(slider, 0.47), 0.5)
		t.equal(SettingsSchema.cycleOption(SCHEMA[3], "High", 1), "Low")
		t.equal(SettingsSchema.cycleOption(SCHEMA[3], "Low", -1), "High")
		t.equal(SettingsSchema.cycleOption(SCHEMA[3], "Missing", 1), "Medium")
	end,
}
