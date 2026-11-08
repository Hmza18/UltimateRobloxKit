--!strict
-- Dotted paths into nested tables, such as "Stats.Cash" or "Inventory.3.Count". Pure Luau.
-- Writes are copy-on-write: only the tables along the path are copied, so untouched branches keep
-- their identity. Store relies on this to detect changes by reference instead of deep comparison.

export type Segments = { string }

local Path = {}

local SEGMENT_PATTERN = "^[%w_]+$"
local CACHE_LIMIT = 512

local cache: { [string]: Segments } = {}
local cacheSize = 0

-- True for "" (the root) and for dot-separated segments of letters, digits and underscores.
function Path.isValid(path: any): boolean
	if type(path) ~= "string" then
		return false
	end
	if path == "" then
		return true
	end
	for _, segment in string.split(path, ".") do
		if not string.find(segment, SEGMENT_PATTERN) then
			return false
		end
	end
	return true
end

-- Splits a path into segments. Results are cached and frozen. Raises an error for invalid paths.
function Path.parse(path: string): Segments
	local cached = cache[path]
	if cached then
		return cached
	end
	assert(Path.isValid(path), "invalid path: " .. tostring(path))
	local parts: Segments = if path == "" then {} else string.split(path, ".")
	local segments = table.freeze(parts)
	if cacheSize >= CACHE_LIMIT then
		table.clear(cache)
		cacheSize = 0
	end
	cache[path] = segments
	cacheSize += 1
	return segments
end

function Path.join(segments: Segments): string
	return table.concat(segments, ".")
end

-- Appends a child segment, treating "" as the root.
function Path.child(path: string, key: string): string
	if path == "" then
		return key
	end
	return path .. "." .. key
end

-- A numeric segment addresses an array slot when the node already uses numeric keys.
local function keyFor(node: { [any]: any }, segment: string): any
	if node[segment] ~= nil then
		return segment
	end
	local number = tonumber(segment)
	if number ~= nil and (node[number] ~= nil or #node > 0) then
		return number
	end
	return segment
end

function Path.getSegments(tree: any, segments: Segments): any
	local node = tree
	for _, segment in segments do
		if type(node) ~= "table" then
			return nil
		end
		node = node[keyFor(node, segment)]
	end
	return node
end

function Path.get(tree: any, path: string): any
	return Path.getSegments(tree, Path.parse(path))
end

local function setAt(node: any, segments: Segments, index: number, value: any, freeze: boolean): any
	if index > #segments then
		return value
	end
	local copy: { [any]: any } = if type(node) == "table" then table.clone(node) else {}
	local key = keyFor(copy, segments[index])
	copy[key] = setAt(copy[key], segments, index + 1, value, freeze)
	if freeze then
		return table.freeze(copy)
	end
	return copy
end

-- Returns a new tree with `value` at `segments`. The input tree is never modified.
-- Setting nil removes the key. Missing or non-table nodes on the way are replaced by tables.
function Path.setSegments(tree: any, segments: Segments, value: any, freeze: boolean?): any
	return setAt(tree, segments, 1, value, freeze == true)
end

function Path.set(tree: any, path: string, value: any, freeze: boolean?): any
	return Path.setSegments(tree, Path.parse(path), value, freeze)
end

-- True when `prefix` is `full` or one of its ancestors ("Stats" is a prefix of "Stats.Cash").
function Path.isPrefix(prefix: Segments, full: Segments): boolean
	if #prefix > #full then
		return false
	end
	for index, segment in prefix do
		if full[index] ~= segment then
			return false
		end
	end
	return true
end

return Path
