--!strict
local Input = require("../src/Systems/Input/InputLogic")
local t = require("./lib/t")

local DEFAULTS: any = {
	Jump = { keyboard = { "Space" }, gamepad = { "ButtonA" }, touch = { title = "Jump" } },
	Sprint = { keyboard = { "LeftShift" }, gamepad = { "ButtonL3" } },
	Interact = { keyboard = { "E", "F" }, gamepad = { "ButtonX" } },
	Reload = { keyboard = { "R" } },
}

local function hasError(errors: { string }, fragment: string): boolean
	for _, message in errors do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

return {
	["validateMap accepts the defaults and reports problems"] = function()
		t.truthy(Input.validateMap(DEFAULTS))
		local broken: any = {
			["Open Menu"] = { keyboard = { "M" } },
			Spaces = { keyboard = { "Left Shift" } },
			Twice = { keyboard = { "Q", "Q" } },
			Many = { gamepad = { "ButtonA", "ButtonB", "ButtonX", "ButtonY" } },
			Priority = { priority = "high" },
			Plain = true,
		}
		local ok, errors = Input.validateMap(broken)
		t.falsy(ok)
		t.truthy(hasError(errors, "Open Menu: action names"))
		t.truthy(hasError(errors, "bad key Left Shift"))
		t.truthy(hasError(errors, "duplicate key Q"))
		t.truthy(hasError(errors, "Many.gamepad: must be a list of at most 3 keys"))
		t.truthy(hasError(errors, "Priority: priority must be a number"))
		t.truthy(hasError(errors, "Plain: definition must be a table"))
	end,

	["reverse lookup and conflicts"] = function()
		local map = Input.cloneMap(DEFAULTS)
		map.Reload.keyboard = { "E" }
		t.deepEqual(Input.reverseLookup(map, "keyboard").E, { "Interact", "Reload" })
		local conflicts = Input.findConflicts(map, "keyboard")
		t.equal(#conflicts, 1)
		t.equal(conflicts[1].key, "E")
		t.deepEqual(conflicts[1].actions, { "Interact", "Reload" })
		t.equal(#Input.findConflicts(DEFAULTS, "keyboard"), 0)
		t.deepEqual(Input.bindingsFor(DEFAULTS, "Interact", "keyboard"), { "E", "F" })
		t.deepEqual(Input.bindingsFor(DEFAULTS, "Reload", "gamepad"), {})
	end,

	["rebind returns a new map"] = function()
		local ok, reason, map = Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "J")
		t.truthy(ok)
		t.equal(reason, nil)
		t.deepEqual(map and map.Jump.keyboard, { "J" })
		t.deepEqual(DEFAULTS.Jump.keyboard, { "Space" }, "the input map is untouched")
		local _, _, appended = Input.rebind(DEFAULTS, "Jump", "keyboard", 2, "K")
		t.deepEqual(appended and appended.Jump.keyboard, { "Space", "K" })
	end,

	["conflicts are refused, allowed or swapped"] = function()
		local ok, reason, map, other = Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "E")
		t.falsy(ok)
		t.equal(reason, "conflict")
		t.equal(map, nil)
		t.equal(other, "Interact")
		local _, _, shared = Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "E", { allowConflicts = true })
		t.deepEqual(shared and shared.Jump.keyboard, { "E" })
		t.deepEqual(shared and shared.Interact.keyboard, { "E", "F" })
		local swap = { swap = true }
		local swappedOk, _, swapped, swappedWith = Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "E", swap)
		t.truthy(swappedOk)
		t.equal(swappedWith, "Interact")
		t.deepEqual(swapped and swapped.Jump.keyboard, { "E" })
		t.deepEqual(swapped and swapped.Interact.keyboard, { "Space", "F" })
	end,

	["swapping into an empty slot takes the key away"] = function()
		local ok, _, map = Input.rebind(DEFAULTS, "Reload", "gamepad", 1, "ButtonX", { swap = true })
		t.truthy(ok)
		t.deepEqual(map and map.Reload.gamepad, { "ButtonX" })
		t.deepEqual(map and map.Interact.gamepad, {})
	end,

	["slots within one action swap"] = function()
		local _, _, map = Input.rebind(DEFAULTS, "Interact", "keyboard", 1, "F")
		t.deepEqual(map and map.Interact.keyboard, { "F", "E" })
		local _, _, same = Input.rebind(DEFAULTS, "Interact", "keyboard", 3, "E")
		t.deepEqual(same and same.Interact.keyboard, { "E", "F" }, "appending a key it already has does nothing")
	end,

	["invalid rebinds are refused"] = function()
		t.equal(select(2, Input.rebind(DEFAULTS, "Fly", "keyboard", 1, "G")), "unknown action")
		local touchReason = select(2, Input.rebind(DEFAULTS, "Jump", "touch" :: any, 1, "G"))
		t.equal(touchReason, "only keyboard and gamepad can be rebound")
		t.equal(select(2, Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "")), "invalid key")
		t.equal(select(2, Input.rebind(DEFAULTS, "Jump", "keyboard", 0, "G")), "invalid slot")
		t.equal(select(2, Input.rebind(DEFAULTS, "Jump", "keyboard", 3, "G")), "invalid slot")
		t.equal(select(2, Input.rebind(DEFAULTS, "Jump", "keyboard", 1.5, "G")), "invalid slot")
	end,

	["unbind and reset"] = function()
		local map = Input.unbind(DEFAULTS, "Interact", "keyboard", 1)
		t.deepEqual(map.Interact.keyboard, { "F" })
		local untouched = Input.unbind(DEFAULTS, "Reload", "gamepad", 1)
		t.equal(untouched.Reload.gamepad, nil)
		local reset = Input.resetAction(map, DEFAULTS, "Interact")
		t.deepEqual(reset.Interact.keyboard, { "E", "F" })
	end,

	["overrides round trip and bad saves are skipped"] = function()
		local _, _, map = Input.rebind(DEFAULTS, "Jump", "keyboard", 1, "J")
		local saved = Input.overrides(map :: any, DEFAULTS)
		t.deepEqual(saved, { Jump = { keyboard = { "J" } } })
		local restored, skipped = Input.applyOverrides(DEFAULTS, saved)
		t.equal(skipped, 0)
		t.deepEqual(restored, map)
		local bad = {
			Ghost = { keyboard = { "G" } },
			Jump = { keyboard = { "Bad Key" } },
			Sprint = { gamepad = { "ButtonY", "ButtonY" } },
			Reload = "x",
		}
		local repaired, dropped = Input.applyOverrides(DEFAULTS, bad)
		t.equal(dropped, 4)
		t.deepEqual(repaired, Input.cloneMap(DEFAULTS))
		local _, none = Input.applyOverrides(DEFAULTS, nil)
		t.equal(none, 0)
	end,

	["device detection"] = function()
		t.equal(Input.detectDevice("Keyboard"), "keyboard")
		t.equal(Input.detectDevice("MouseButton1"), "keyboard")
		t.equal(Input.detectDevice("MouseMovement"), "keyboard")
		t.equal(Input.detectDevice("Gamepad1"), "gamepad")
		t.equal(Input.detectDevice("Gamepad8"), "gamepad")
		t.equal(Input.detectDevice("Touch"), "touch")
		t.equal(Input.detectDevice("Focus"), nil)
		t.equal(Input.preferredToDevice("KeyboardAndMouse"), "keyboard")
		t.equal(Input.preferredToDevice("Gamepad"), "gamepad")
		t.equal(Input.preferredToDevice("Touch"), "touch")
		t.equal(Input.preferredToDevice("Unknown"), nil)
	end,

	["display names"] = function()
		t.equal(Input.displayName("LeftShift"), "Left Shift")
		t.equal(Input.displayName("ButtonA"), "A")
		t.equal(Input.displayName("One"), "1")
		t.equal(Input.displayName("E"), "E")
		t.equal(Input.displayName("MouseButton2"), "Right Click")
	end,
}
