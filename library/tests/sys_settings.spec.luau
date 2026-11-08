--!strict
local Settings = require("../src/Systems/Settings/SettingsLogic")
local SettingsConfig = require("../src/Systems/Settings/SettingsConfig")
local t = require("./lib/t")

local SCHEMA: any = {
	Volume = { type = "number", default = 0.5, min = 0, max = 1, step = 0.1, group = "Audio" },
	Fov = { type = "number", default = 70, min = 50, max = 110, group = "Camera" },
	Quality = { type = "enum", default = "Auto", options = { "Auto", "Low", "High" } },
	Motion = { type = "bool", default = true },
	Jump = { type = "keybind", default = "Space", group = "Controls" },
	Sprint = {
		type = "keybind",
		default = "LeftShift",
		allowed = { "LeftShift", "RightShift", "Q" },
		group = "Controls",
	},
}

return {
	["the default and test schemas are valid"] = function()
		local ok, errors = Settings.validateSchema(SettingsConfig.schema :: any)
		t.truthy(ok, table.concat(errors, "; "))
		t.truthy(Settings.validateSchema(SCHEMA))
	end,

	["validateSchema reports problems"] = function()
		local broken: any = {
			Range = { type = "number", default = 5, min = 10, max = 1 },
			Empty = { type = "enum", default = "A", options = {} },
			Wrong = { type = "bool", default = "yes" },
			Offstep = { type = "number", default = 0.33, min = 0, max = 1, step = 0.25 },
			Mystery = { type = "colour", default = 1 },
		}
		local ok, errors = Settings.validateSchema(broken)
		t.falsy(ok)
		local joined = table.concat(errors, "\n")
		t.truthy(string.find(joined, "Range: min is greater than max", 1, true))
		t.truthy(string.find(joined, "Empty: enum needs options", 1, true))
		t.truthy(string.find(joined, "Wrong: bad default", 1, true))
		t.truthy(string.find(joined, "Offstep: default is off the range or step", 1, true))
		t.truthy(string.find(joined, "Mystery: bad default (unknown setting type)", 1, true))
	end,

	["numbers are clamped and snapped to the step"] = function()
		local function coerce(key: string, value: any): any
			local ok, cleaned = Settings.coerce(SCHEMA[key], value)
			return if ok then cleaned else nil
		end
		t.equal(coerce("Volume", 0.37), 0.4)
		t.equal(coerce("Volume", 5), 1)
		t.equal(coerce("Volume", -1), 0)
		t.equal(coerce("Fov", 120), 110)
		t.equal(coerce("Fov", 75.5), 75.5)
		t.equal(coerce("Volume", math.sqrt(-1)), nil)
		t.equal(coerce("Volume", "1"), nil)
		t.equal(coerce("Volume", math.huge), nil)
	end,

	["enums, booleans and keybinds"] = function()
		t.equal(select(2, Settings.coerce(SCHEMA.Quality, "Ultra")), "not one of the options")
		t.truthy(Settings.coerce(SCHEMA.Quality, "Low"))
		t.equal(select(2, Settings.coerce(SCHEMA.Motion, "true")), "expected a boolean")
		t.truthy(Settings.coerce(SCHEMA.Motion, false))
		t.truthy(Settings.coerce(SCHEMA.Jump, "Q"))
		t.equal(select(2, Settings.coerce(SCHEMA.Jump, "Left Shift")), "not a key name")
		t.equal(select(2, Settings.coerce(SCHEMA.Jump, "1abc")), "not a key name")
		t.equal(select(2, Settings.coerce(SCHEMA.Jump, string.rep("A", 40))), "not a key name")
		t.equal(select(2, Settings.coerce(SCHEMA.Sprint, "E")), "key not allowed")
		t.truthy(Settings.coerce(SCHEMA.Sprint, "Q"))
	end,

	["defaults come from the schema"] = function()
		local values = Settings.defaults(SCHEMA)
		t.equal(values.Volume, 0.5)
		t.equal(values.Quality, "Auto")
		t.equal(values.Motion, true)
		t.equal(values.Sprint, "LeftShift")
	end,

	["apply validates changes without mutating"] = function()
		local values = Settings.defaults(SCHEMA)
		local changes = { Volume = 0.72, Quality = "Ultra", Cheat = 1, Fov = 90 }
		local changed, rejected = Settings.apply(SCHEMA, values, changes)
		t.equal(values.Volume, 0.5, "the input is untouched")
		t.equal(changed.Volume, 0.7)
		t.equal(changed.Fov, 90)
		t.equal(changed.Quality, "Auto")
		t.equal(rejected.Quality, "not one of the options")
		t.equal(rejected.Cheat, "unknown setting")
		t.equal(rejected.Volume, nil)
	end,

	["migrations run in order and failures are skipped"] = function()
		local migrations = {
			[1] = function(values: { [string]: any }): { [string]: any }
				values.Volume = values.OldVolume
				values.OldVolume = nil
				return values
			end,
			[2] = function(_values: { [string]: any }): { [string]: any }
				error("broken migration")
			end,
		}
		local values, version = Settings.migrate({ version = 1, values = { OldVolume = 0.3 } }, migrations, 3)
		t.equal(version, 3)
		t.deepEqual(values, { Volume = 0.3 })
		local empty, emptyVersion = Settings.migrate(nil, migrations, 1)
		t.deepEqual(empty, {})
		t.equal(emptyVersion, 1)
		local future, futureVersion = Settings.migrate({ version = 9, values = { Volume = 1 } }, migrations, 3)
		t.equal(futureVersion, 9, "newer saves are not migrated backwards")
		t.equal(future.Volume, 1)
	end,

	["serialize keeps only changed values"] = function()
		local values = Settings.defaults(SCHEMA)
		values.Volume = 0.9
		values.Jump = "F"
		local saved = Settings.serialize(SCHEMA, values, 2)
		t.equal(saved.version, 2)
		t.deepEqual(saved.values, { Volume = 0.9, Jump = "F" })
		t.deepEqual(Settings.deserialize(SCHEMA, saved, 2), values)
	end,

	["deserialize repairs untrusted data"] = function()
		local data = { version = 2, values = { Volume = 7, Quality = "Ultra", Removed = true, Motion = false } }
		local values = Settings.deserialize(SCHEMA, data, 2)
		t.equal(values.Volume, 1, "clamped")
		t.equal(values.Quality, "Auto", "invalid values fall back to the default")
		t.equal(values.Motion, false)
		t.equal(values.Removed, nil, "unknown keys are dropped")
		t.deepEqual(Settings.deserialize(SCHEMA, "garbage", 2), Settings.defaults(SCHEMA))
	end,

	["diff, keybind conflicts and groups"] = function()
		local a = Settings.defaults(SCHEMA)
		local b = table.clone(a)
		b.Fov = 90
		b.Jump = "LeftShift"
		t.deepEqual(Settings.diff(a, b), { "Fov", "Jump" })
		t.deepEqual(Settings.keybindConflicts(SCHEMA, b), { LeftShift = { "Jump", "Sprint" } })
		t.deepEqual(Settings.keybindConflicts(SCHEMA, a), {})
		local groups = Settings.groups(SCHEMA)
		t.deepEqual(groups.Controls, { "Jump", "Sprint" })
		t.deepEqual(groups.General, { "Motion", "Quality" })
	end,
}
