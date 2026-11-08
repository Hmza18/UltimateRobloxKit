--!strict
-- Tiny assertion helpers for Lune tests. Each helper raises an error when the check fails.

local t = {}

local function describe(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function fail(label: string?, message: string)
	error(if label then label .. ": " .. message else message, 3)
end

function t.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		fail(label, "expected " .. describe(expected) .. ", got " .. describe(actual))
	end
end

function t.near(actual: number, expected: number, epsilon: number?, label: string?)
	local tolerance = epsilon or 1e-9
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		fail(label, "expected " .. describe(expected) .. " +/- " .. tostring(tolerance) .. ", got " .. describe(actual))
	end
end

function t.truthy(value: any, label: string?)
	if not value then
		fail(label, "expected a truthy value, got " .. describe(value))
	end
end

function t.falsy(value: any, label: string?)
	if value then
		fail(label, "expected a falsy value, got " .. describe(value))
	end
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function t.deepEqual(actual: any, expected: any, label: string?)
	if not deepEqual(actual, expected) then
		fail(label, "tables differ")
	end
end

function t.throws(callback: () -> (), label: string?)
	local ok = pcall(callback)
	if ok then
		fail(label, "expected an error")
	end
end

return t
