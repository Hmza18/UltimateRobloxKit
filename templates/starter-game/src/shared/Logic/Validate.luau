--!strict
-- Composable checkers for untrusted values such as RemoteEvent payloads. Pure Luau.
-- A check returns true, or false and a short reason. Number checks reject NaN and infinities.

export type Check = (value: any) -> (boolean, string?)
export type ArgsCheck = (...any) -> (boolean, string?)

export type NumberOptions = { min: number?, max: number?, integer: boolean? }
export type StringOptions = { minLength: number?, maxLength: number?, pattern: string? }

local DEFAULT_MAX_STRING = 200
local DEFAULT_MAX_ARRAY = 100

local Validate = {}

function Validate.isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.number(options: NumberOptions?): Check
	local opts: NumberOptions = options or {}
	local min, max, integer = opts.min, opts.max, opts.integer
	return function(value: any): (boolean, string?)
		if not Validate.isFinite(value) then
			return false, "expected a finite number"
		end
		if integer and value % 1 ~= 0 then
			return false, "expected an integer"
		end
		if min and value < min then
			return false, "below minimum"
		end
		if max and value > max then
			return false, "above maximum"
		end
		return true, nil
	end
end

function Validate.integer(min: number?, max: number?): Check
	return Validate.number({ min = min, max = max, integer = true })
end

-- Length is counted in UTF-8 characters. Invalid UTF-8 is rejected.
function Validate.string(options: StringOptions?): Check
	local opts: StringOptions = options or {}
	local minLength = opts.minLength or 0
	local maxLength = opts.maxLength or DEFAULT_MAX_STRING
	local pattern = opts.pattern
	return function(value: any): (boolean, string?)
		if type(value) ~= "string" then
			return false, "expected a string"
		end
		-- Cheap byte check first so huge strings never reach utf8.len.
		if #value > maxLength * 4 then
			return false, "string too long"
		end
		local length = utf8.len(value)
		if length == nil then
			return false, "invalid UTF-8"
		end
		if length < minLength or length > maxLength then
			return false, "string length out of range"
		end
		if pattern and not string.find(value, pattern) then
			return false, "string does not match the pattern"
		end
		return true, nil
	end
end

function Validate.boolean(): Check
	return function(value: any): (boolean, string?)
		if type(value) ~= "boolean" then
			return false, "expected a boolean"
		end
		return true, nil
	end
end

-- Accepts only values that appear in `allowed`, compared with ==.
function Validate.oneOf(allowed: { any }): Check
	local set: { [any]: boolean } = {}
	for _, item in allowed do
		set[item] = true
	end
	return function(value: any): (boolean, string?)
		if value == nil or not set[value] then
			return false, "value is not allowed"
		end
		return true, nil
	end
end

function Validate.optional(check: Check): Check
	return function(value: any): (boolean, string?)
		if value == nil then
			return true, nil
		end
		return check(value)
	end
end

-- A dense array (keys 1..n, no holes) of at most `maxLength` items that all pass `check`.
function Validate.array(check: Check, maxLength: number?): Check
	local limit = maxLength or DEFAULT_MAX_ARRAY
	return function(value: any): (boolean, string?)
		if type(value) ~= "table" then
			return false, "expected an array"
		end
		local count = 0
		for key in value do
			count += 1
			if count > limit then
				return false, "array too long"
			end
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false, "expected an array"
			end
		end
		if count ~= #value then
			return false, "array has holes"
		end
		for index = 1, count do
			local ok, reason = check(value[index])
			if not ok then
				return false, string.format("[%d] %s", index, reason or "invalid")
			end
		end
		return true, nil
	end
end

-- A table with exactly the keys in `shape`. Unknown keys are rejected; use Validate.optional for optional keys.
function Validate.struct(shape: { [string]: Check }): Check
	return function(value: any): (boolean, string?)
		if type(value) ~= "table" then
			return false, "expected a table"
		end
		for key in value do
			if type(key) ~= "string" or shape[key] == nil then
				return false, "unexpected key " .. tostring(key)
			end
		end
		for key, check in shape do
			local ok, reason = check(value[key])
			if not ok then
				return false, key .. ": " .. (reason or "invalid")
			end
		end
		return true, nil
	end
end

-- Checks a whole argument list, as received by OnServerEvent after the player.
-- Extra arguments are rejected, and missing ones are checked as nil.
function Validate.args(checks: { Check }): ArgsCheck
	return function(...: any): (boolean, string?)
		if select("#", ...) > #checks then
			return false, "too many arguments"
		end
		local values = table.pack(...)
		for index, check in checks do
			local ok, reason = check(values[index])
			if not ok then
				return false, string.format("argument %d: %s", index, reason or "invalid")
			end
		end
		return true, nil
	end
end

return Validate
