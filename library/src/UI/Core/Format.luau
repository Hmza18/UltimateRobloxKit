--!strict
-- Value formatting for bound labels: thousands separators, abbreviations (1.2K), percentages,
-- clock times and durations, plus a registry for game-specific formatters. Pure Luau.
-- A format spec is a name with an optional argument, for example "abbrev", "abbrev:2" or "number:1".

export type Formatter = (value: any, argument: string?) -> string

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local INVALID = "--"
local EPSILON = 1e-7

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function trimZeros(text: string): string
	if not string.find(text, "%.") then
		return text
	end
	local trimmed = string.gsub(text, "0+$", "")
	trimmed = string.gsub(trimmed, "%.$", "")
	return trimmed
end

local function group(digits: string, separator: string): string
	local out = digits
	local count = 1
	while count > 0 do
		out, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1" .. separator .. "%2")
	end
	return out
end

local function places(argument: string?, default: number): number
	local parsed = if argument then tonumber(argument) else nil
	if parsed == nil then
		return default
	end
	return math.clamp(math.floor(parsed), 0, 6)
end

-- 1234567.891 -> "1,234,568"; with decimals 2 -> "1,234,567.89".
function Format.number(value: number, decimals: number?, separator: string?): string
	if not isFinite(value) then
		return INVALID
	end
	local digits = math.clamp(math.floor(decimals or 0), 0, 6)
	local text = string.format("%." .. tostring(digits) .. "f", math.abs(value))
	local integerPart, fraction = string.match(text, "^(%d+)(.*)$")
	if integerPart == nil then
		return text
	end
	local grouped = group(integerPart, separator or ",") .. (fraction or "")
	local isZero = string.find(text, "^[0%.]+$") ~= nil
	if value < 0 and not isZero then
		return "-" .. grouped
	end
	return grouped
end

-- Short form with a suffix. Rounds down by default so a player is never shown more than they have:
-- 1999 -> "1.9K". Pass round = true to round to nearest instead.
function Format.abbrev(value: number, decimals: number?, round: boolean?): string
	if not isFinite(value) then
		return INVALID
	end
	local digits = math.clamp(math.floor(decimals or 1), 0, 6)
	local factor = 10 ^ digits
	local magnitude = math.abs(value)
	local tier = 1
	while magnitude >= 1000 and tier < #SUFFIXES do
		magnitude /= 1000
		tier += 1
	end
	local scaled = if round then math.floor(magnitude * factor + 0.5) else math.floor(magnitude * factor + EPSILON)
	local shown = scaled / factor
	if shown >= 1000 and tier < #SUFFIXES then
		shown /= 1000
		tier += 1
	end
	local text = trimZeros(string.format("%." .. tostring(digits) .. "f", shown))
	if value < 0 and text ~= "0" then
		text = "-" .. text
	end
	return text .. SUFFIXES[tier]
end

-- 0.256 -> "26%". With fromRatio = false the value is already a percentage (25.6 -> "26%").
function Format.percent(value: number, decimals: number?, fromRatio: boolean?): string
	if not isFinite(value) then
		return INVALID
	end
	local digits = math.clamp(math.floor(decimals or 0), 0, 6)
	local percent = if fromRatio == false then value else value * 100
	return trimZeros(string.format("%." .. tostring(digits) .. "f", percent)) .. "%"
end

-- Clock style: 65 -> "1:05", 3723 -> "1:02:03". Negative values show as "0:00".
function Format.time(seconds: number): string
	if not isFinite(seconds) then
		return INVALID
	end
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

-- The two largest units: 93784 -> "1d 2h", 125 -> "2m 5s", 45 -> "45s".
function Format.duration(seconds: number): string
	if not isFinite(seconds) then
		return INVALID
	end
	local total = math.max(0, math.floor(seconds))
	local units = {
		{ size = 86400, label = "d" },
		{ size = 3600, label = "h" },
		{ size = 60, label = "m" },
		{ size = 1, label = "s" },
	}
	for index, unit in units do
		if total >= unit.size or index == #units then
			local major = total // unit.size
			local nextUnit = units[index + 1]
			if nextUnit == nil then
				return string.format("%d%s", major, unit.label)
			end
			local minor = (total % unit.size) // nextUnit.size
			if minor == 0 then
				return string.format("%d%s", major, unit.label)
			end
			return string.format("%d%s %d%s", major, unit.label, minor, nextUnit.label)
		end
	end
	return "0s"
end

local function numeric(callback: (value: number, argument: string?) -> string): Formatter
	return function(value: any, argument: string?): string
		if type(value) ~= "number" then
			return if value == nil then "" else tostring(value)
		end
		return callback(value, argument)
	end
end

local builtins: { [string]: Formatter } = {
	number = numeric(function(value: number, argument: string?): string
		return Format.number(value, places(argument, 0))
	end),
	abbrev = numeric(function(value: number, argument: string?): string
		return Format.abbrev(value, places(argument, 1))
	end),
	percent = numeric(function(value: number, argument: string?): string
		return Format.percent(value, places(argument, 0))
	end),
	time = numeric(function(value: number, _argument: string?): string
		return Format.time(value)
	end),
	duration = numeric(function(value: number, _argument: string?): string
		return Format.duration(value)
	end),
	upper = function(value: any, _argument: string?): string
		return string.upper(if value == nil then "" else tostring(value))
	end,
	lower = function(value: any, _argument: string?): string
		return string.lower(if value == nil then "" else tostring(value))
	end,
}

local custom: { [string]: Formatter } = {}

-- Registers a game formatter usable as Format="<name>" on UrkBind. Returns a function that removes it.
function Format.register(name: string, formatter: Formatter): () -> ()
	assert(type(name) == "string" and string.find(name, "^[%a][%w_]*$") ~= nil, "formatter name must be an identifier")
	assert(type(formatter) == "function", "formatter must be a function")
	custom[name] = formatter
	local function unregister()
		if custom[name] == formatter then
			custom[name] = nil
		end
	end
	return unregister
end

function Format.has(name: string): boolean
	return custom[name] ~= nil or builtins[name] ~= nil
end

-- "abbrev:2" -> ("abbrev", "2"); "time" -> ("time", nil).
function Format.parseSpec(spec: string): (string, string?)
	local name, argument = string.match(spec, "^([%w_]+):(.+)$")
	if name ~= nil then
		return name, argument
	end
	return spec, nil
end

-- Formats `value` with a spec. Unknown or empty specs fall back to tostring; nil becomes "".
-- A formatter that errors also falls back to tostring, so one bad formatter cannot break a HUD.
function Format.apply(spec: string?, value: any): string
	if spec == nil or spec == "" then
		return if value == nil then "" else tostring(value)
	end
	local name, argument = Format.parseSpec(spec)
	local formatter = custom[name] or builtins[name]
	if formatter == nil then
		return if value == nil then "" else tostring(value)
	end
	local ok, result = pcall(formatter, value, argument)
	if ok and type(result) == "string" then
		return result
	end
	return if value == nil then "" else tostring(value)
end

return Format
