--!strict
-- Unified input rules. Pure Luau: key and button names are strings (Enum.KeyCode or Enum.UserInputType
-- names such as "E", "LeftShift", "ButtonA", "MouseButton1"), converted to enums by the adapter.
-- An action map lists, per action, keyboard keys, gamepad buttons and an optional touch button.
-- Rebinding never mutates the map it is given and reports conflicts with other actions.

export type Device = "keyboard" | "gamepad" | "touch"
export type BindDevice = "keyboard" | "gamepad"

export type TouchSpec = {
	title: string?,
	image: string?, -- rbxassetid
	position: { x: number, y: number }?, -- scale of the screen, 0 to 1
}

export type ActionDef = {
	keyboard: { string }?,
	gamepad: { string }?,
	touch: TouchSpec?, -- nil: no on-screen button
	priority: number?, -- ContextActionService priority (higher wins)
	description: string?,
}

export type ActionMap = { [string]: ActionDef }
export type Conflict = { key: string, actions: { string } }
export type RebindOptions = { swap: boolean?, allowConflicts: boolean? }
export type Overrides = { [string]: { keyboard: { string }?, gamepad: { string }? } }

local NAME_PATTERN = "^%a[%w]*$"
local MAX_SLOTS = 3
local DEVICES: { BindDevice } = { "keyboard", "gamepad" }

local DISPLAY_NAMES: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "Left Stick",
	ButtonR3 = "Right Stick",
	ButtonStart = "Menu",
	ButtonSelect = "View",
	DPadUp = "D-Pad Up",
	DPadDown = "D-Pad Down",
	DPadLeft = "D-Pad Left",
	DPadRight = "D-Pad Right",
	MouseButton1 = "Left Click",
	MouseButton2 = "Right Click",
	MouseButton3 = "Middle Click",
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}

local Input = {}

local function keysOf(def: ActionDef, device: BindDevice): { string }?
	if device == "keyboard" then
		return def.keyboard
	end
	return def.gamepad
end

local function setKeys(def: ActionDef, device: BindDevice, keys: { string }?)
	if device == "keyboard" then
		def.keyboard = keys
	else
		def.gamepad = keys
	end
end

function Input.isKeyName(value: any): boolean
	return type(value) == "string" and #value <= 32 and string.match(value, NAME_PATTERN) ~= nil
end

local function isBindDevice(value: any): boolean
	return value == "keyboard" or value == "gamepad"
end

-- Checks an action map. Returns ok and every problem found, sorted.
function Input.validateMap(map: ActionMap): (boolean, { string })
	local errors: { string } = {}
	if type(map) ~= "table" then
		return false, { "action map must be a table" }
	end
	for action, def in map :: { [any]: any } do
		if type(action) ~= "string" or not Input.isKeyName(action) then
			table.insert(errors, tostring(action) .. ": action names must be letters and digits")
			continue
		end
		if type(def) ~= "table" then
			table.insert(errors, action .. ": definition must be a table")
			continue
		end
		for _, device in DEVICES do
			local keys = def[device]
			if keys ~= nil then
				if type(keys) ~= "table" or #keys > MAX_SLOTS then
					table.insert(errors, action .. "." .. device .. ": must be a list of at most 3 keys")
				else
					local seen: { [string]: boolean } = {}
					for _, key in keys do
						if not Input.isKeyName(key) then
							table.insert(errors, action .. "." .. device .. ": bad key " .. tostring(key))
						elseif seen[key] then
							table.insert(errors, action .. "." .. device .. ": duplicate key " .. key)
						else
							seen[key] = true
						end
					end
				end
			end
		end
		if def.priority ~= nil and type(def.priority) ~= "number" then
			table.insert(errors, action .. ": priority must be a number")
		end
	end
	table.sort(errors)
	return #errors == 0, errors
end

-- Deep copy of the binding lists; touch specs are shared because they are never changed here.
function Input.cloneMap(map: ActionMap): ActionMap
	local copy: ActionMap = {}
	for action, def in map do
		copy[action] = {
			keyboard = if def.keyboard then table.clone(def.keyboard) else nil,
			gamepad = if def.gamepad then table.clone(def.gamepad) else nil,
			touch = def.touch,
			priority = def.priority,
			description = def.description,
		}
	end
	return copy
end

function Input.bindingsFor(map: ActionMap, action: string, device: BindDevice): { string }
	local def = map[action]
	local keys = if def then keysOf(def, device) else nil
	return if keys then table.clone(keys) else {}
end

-- key -> sorted list of actions bound to it on `device`.
function Input.reverseLookup(map: ActionMap, device: BindDevice): { [string]: { string } }
	local users: { [string]: { string } } = {}
	for action, def in map do
		for _, key in ipairs(keysOf(def, device) or {}) do
			local list = users[key] or {}
			table.insert(list, action)
			users[key] = list
		end
	end
	for _, list in users do
		table.sort(list)
	end
	return users
end

-- Keys bound to more than one action on `device`, sorted by key.
function Input.findConflicts(map: ActionMap, device: BindDevice): { Conflict }
	local conflicts: { Conflict } = {}
	for key, actions in Input.reverseLookup(map, device) do
		if #actions > 1 then
			table.insert(conflicts, { key = key, actions = actions })
		end
	end
	table.sort(conflicts, function(a: Conflict, b: Conflict): boolean
		return a.key < b.key
	end)
	return conflicts
end

-- Binds `key` to slot `slot` (1 to 3; one past the end appends) of `action` on `device`.
-- When another action already uses the key: with `swap`, that action takes this slot's old key (or
-- loses the key when the slot was empty); with `allowConflicts`, both keep it; otherwise the rebind
-- is refused with reason "conflict" and the other action's name.
-- Returns ok, a reason, the new map (nil when refused) and the conflicting action.
function Input.rebind(
	map: ActionMap,
	action: string,
	device: BindDevice,
	slot: number,
	key: string,
	options: RebindOptions?
): (boolean, string?, ActionMap?, string?)
	local opts: RebindOptions = options or {}
	local def = map[action]
	if def == nil then
		return false, "unknown action", nil, nil
	end
	if not isBindDevice(device) then
		return false, "only keyboard and gamepad can be rebound", nil, nil
	end
	if not Input.isKeyName(key) then
		return false, "invalid key", nil, nil
	end
	local current = keysOf(def, device) or {}
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > math.min(#current + 1, MAX_SLOTS) then
		return false, "invalid slot", nil, nil
	end
	local result = Input.cloneMap(map)
	local own = keysOf(result[action], device) or {}
	setKeys(result[action], device, own)
	local previous = own[slot]
	local existing = table.find(own, key)
	if existing and existing ~= slot then
		-- The key is already in another slot of this action: swap the two slots.
		-- Appending a key the action already has changes nothing.
		if previous ~= nil then
			own[existing] = previous
			own[slot] = key
		end
		return true, nil, result, nil
	end
	local otherAction: string? = nil
	for name, otherDef in result do
		local otherKeys = keysOf(otherDef, device)
		if name ~= action and otherKeys and table.find(otherKeys, key) then
			otherAction = name
			break
		end
	end
	if otherAction then
		if opts.swap then
			local otherKeys = keysOf(result[otherAction], device) :: { string }
			local index = table.find(otherKeys, key) :: number
			if previous and table.find(otherKeys, previous) == nil then
				otherKeys[index] = previous
			else
				table.remove(otherKeys, index)
			end
		elseif not opts.allowConflicts then
			return false, "conflict", nil, otherAction
		end
	end
	own[slot] = key
	return true, nil, result, otherAction
end

-- Removes the key in `slot`; later slots move up.
function Input.unbind(map: ActionMap, action: string, device: BindDevice, slot: number): ActionMap
	local result = Input.cloneMap(map)
	local def = result[action]
	local keys = if def then keysOf(def, device) else nil
	if keys and keys[slot] then
		table.remove(keys, slot)
	end
	return result
end

-- Puts one action's bindings back to the defaults.
function Input.resetAction(map: ActionMap, defaults: ActionMap, action: string): ActionMap
	local result = Input.cloneMap(map)
	local default = defaults[action]
	if default and result[action] then
		result[action].keyboard = if default.keyboard then table.clone(default.keyboard) else nil
		result[action].gamepad = if default.gamepad then table.clone(default.gamepad) else nil
	end
	return result
end

local function sameList(a: { string }?, b: { string }?): boolean
	local left, right = a or {}, b or {}
	if #left ~= #right then
		return false
	end
	for index, value in left do
		if right[index] ~= value then
			return false
		end
	end
	return true
end

-- The bindings that differ from the defaults, for saving.
function Input.overrides(map: ActionMap, defaults: ActionMap): Overrides
	local result: Overrides = {}
	for action, def in map do
		local default = defaults[action]
		if default then
			local entry: { keyboard: { string }?, gamepad: { string }? } = {}
			local changed = false
			for _, device in DEVICES do
				local keys = keysOf(def, device)
				if not sameList(keys, keysOf(default, device)) then
					local copy = table.clone(keys or {})
					if device == "keyboard" then
						entry.keyboard = copy
					else
						entry.gamepad = copy
					end
					changed = true
				end
			end
			if changed then
				result[action] = entry
			end
		end
	end
	return result
end

-- Applies saved overrides on top of the defaults. Unknown actions and bad key lists are skipped.
-- Returns the map and how many entries were skipped.
function Input.applyOverrides(defaults: ActionMap, overrides: any): (ActionMap, number)
	local result = Input.cloneMap(defaults)
	local skipped = 0
	if type(overrides) ~= "table" then
		return result, 0
	end
	for action, entry in overrides do
		local def = if type(action) == "string" then result[action] else nil
		if def == nil or type(entry) ~= "table" then
			skipped += 1
			continue
		end
		for _, device in DEVICES do
			local keys = entry[device]
			if keys ~= nil then
				local valid = type(keys) == "table" and #keys <= MAX_SLOTS
				local clean: { string } = {}
				if valid then
					for _, key in keys do
						if not Input.isKeyName(key) or table.find(clean, key) then
							valid = false
							break
						end
						table.insert(clean, key)
					end
				end
				if valid then
					setKeys(def, device, clean)
				else
					skipped += 1
				end
			end
		end
	end
	return result, skipped
end

-- Maps a UserInputType name to a device, or nil for inputs that say nothing about the device
-- (for example "Focus" or "None").
function Input.detectDevice(inputTypeName: string): Device?
	if inputTypeName == "Touch" then
		return "touch"
	end
	if string.match(inputTypeName, "^Gamepad%d+$") then
		return "gamepad"
	end
	if inputTypeName == "Keyboard" or inputTypeName == "TextInput" or string.match(inputTypeName, "^Mouse") then
		return "keyboard"
	end
	return nil
end

-- Maps an Enum.PreferredInput name ("KeyboardAndMouse", "Gamepad", "Touch") to a device.
function Input.preferredToDevice(name: string): Device?
	if name == "KeyboardAndMouse" then
		return "keyboard"
	elseif name == "Gamepad" then
		return "gamepad"
	elseif name == "Touch" then
		return "touch"
	end
	return nil
end

-- A short label for prompts: "LeftShift" -> "Left Shift", "ButtonA" -> "A", "One" -> "1".
function Input.displayName(key: string): string
	local known = DISPLAY_NAMES[key]
	if known then
		return known
	end
	local spaced = string.gsub(key, "(%l)(%u)", "%1 %2")
	return spaced
end

return Input
