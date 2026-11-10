--!strict
-- Preset registry (pure Luau). Every VFX, UI animation, object animation, camera move, reward
-- profile and screen in the kit is a preset with the same metadata, so tools, the playground and AI
-- agents can discover what exists instead of writing effects from scratch.
--
--   local registry = Registry.new("vfx")
--   registry:register({ id = "CoinBurst", name = "Coin burst", category = "rewards", ... })
--   registry:register(myVersion, { override = true })   -- replace safely; the original is kept
--   registry:search("coin")                             -- ids ranked by relevance

export type Param = {
	type: "number" | "color" | "boolean" | "string" | "enum",
	default: any,
	min: number?,
	max: number?,
	options: { string }?, -- for "enum"
	description: string?,
}

export type Preset = {
	id: string, -- unique PascalCase id, for example "CoinBurst"
	name: string,
	category: string,
	description: string,
	params: { [string]: Param }?,
	themes: { string }?, -- nil means every theme
	quality: { min: string?, cost: string? }?, -- min: lowest quality level that shows it; cost: "low" | "medium" | "high"
	dependencies: { string }?, -- other preset ids (any registry) or texture / sound keys
	preview: { [string]: any }?, -- hints for the playground (camera distance, background, loop)
	usage: string?, -- one line of example code
	tags: { string }?,
	data: any, -- the definition itself; its shape belongs to the owning module
}

export type RegisterOptions = { override: boolean? }

export type Registry = {
	kind: string,
	register: (self: Registry, preset: Preset, options: RegisterOptions?) -> Preset,
	unregister: (self: Registry, id: string) -> boolean,
	get: (self: Registry, id: string) -> Preset,
	find: (self: Registry, id: string) -> Preset?,
	has: (self: Registry, id: string) -> boolean,
	original: (self: Registry, id: string) -> Preset?,
	isOverridden: (self: Registry, id: string) -> boolean,
	reset: (self: Registry, id: string) -> boolean,
	list: (self: Registry, filter: Filter?) -> { Preset },
	ids: (self: Registry, filter: Filter?) -> { string },
	categories: (self: Registry) -> { string },
	search: (self: Registry, query: string, limit: number?) -> { string },
	params: (self: Registry, id: string, overrides: { [string]: any }?) -> { [string]: any },
	describe: (self: Registry, id: string) -> { [string]: any },
	count: (self: Registry) -> number,
}

export type Filter = { category: string?, tag: string?, theme: string?, quality: string? }

local Registry = {}

local QUALITY_RANK: { [string]: number } = { Low = 1, Medium = 2, High = 3, Ultra = 4 }
local COSTS: { [string]: boolean } = { low = true, medium = true, high = true }
local PARAM_TYPES: { [string]: boolean } = { number = true, color = true, boolean = true, string = true, enum = true }

Registry.QUALITY_RANK = QUALITY_RANK

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- Problems with a preset definition (empty when valid).
function Registry.validate(preset: Preset): { string }
	local problems: { string } = {}
	local function need(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	if type(preset) ~= "table" then
		return { "preset must be a table" }
	end
	need(
		type(preset.id) == "string" and string.match(preset.id, "^%u[%w]*$") ~= nil,
		"id must be PascalCase letters and digits"
	)
	need(type(preset.name) == "string" and preset.name ~= "", "name required")
	need(type(preset.category) == "string" and preset.category ~= "", "category required")
	need(type(preset.description) == "string" and #preset.description >= 10, "description of 10+ characters required")
	need(preset.data ~= nil, "data required")
	if preset.quality then
		local min = preset.quality.min
		need(min == nil or QUALITY_RANK[min] ~= nil, "quality.min must be Low, Medium, High or Ultra")
		local cost = preset.quality.cost
		need(cost == nil or COSTS[cost] ~= nil, "quality.cost must be low, medium or high")
	end
	local declared: { [string]: Param } = preset.params or {}
	for name, param in declared do
		local label = "param " .. tostring(name)
		if type(param) ~= "table" or not PARAM_TYPES[param.type] then
			table.insert(problems, label .. ": unknown type")
			continue
		end
		if param.type == "number" then
			need(type(param.default) == "number", label .. ": default must be a number")
			if param.min and param.max then
				need(param.min <= param.max, label .. ": min above max")
			end
		elseif param.type == "color" then
			need(isHex(param.default), label .. ": default must be #RRGGBB")
		elseif param.type == "boolean" then
			need(type(param.default) == "boolean", label .. ": default must be a boolean")
		elseif param.type == "string" then
			need(type(param.default) == "string", label .. ": default must be a string")
		else
			local options = param.options or {}
			need(
				#options > 0 and table.find(options, param.default) ~= nil,
				label .. ": default must be one of options"
			)
		end
	end
	return problems
end

local function matches(preset: Preset, filter: Filter?): boolean
	if filter == nil then
		return true
	end
	if filter.category and preset.category ~= filter.category then
		return false
	end
	if filter.tag and not (preset.tags and table.find(preset.tags, filter.tag)) then
		return false
	end
	if filter.theme and preset.themes and not table.find(preset.themes, filter.theme) then
		return false
	end
	if filter.quality then
		local have = QUALITY_RANK[filter.quality] or 4
		local min = if preset.quality and preset.quality.min then QUALITY_RANK[preset.quality.min] or 1 else 1
		if have < min then
			return false
		end
	end
	return true
end

function Registry.new(kind: string): Registry
	local presets: { [string]: Preset } = {}
	local originals: { [string]: Preset } = {}
	local self: Registry

	local function get(_self: Registry, id: string): Preset
		local preset = presets[id]
		if preset == nil then
			error(string.format("unknown %s preset: %s", kind, tostring(id)), 2)
		end
		return preset
	end

	local function list(_self: Registry, filter: Filter?): { Preset }
		local out: { Preset } = {}
		for _, preset in presets do
			if matches(preset, filter) then
				table.insert(out, preset)
			end
		end
		table.sort(out, function(a: Preset, b: Preset): boolean
			return a.id < b.id
		end)
		return out
	end

	self = {
		kind = kind,
		register = function(_self: Registry, preset: Preset, options: RegisterOptions?): Preset
			local problems = Registry.validate(preset)
			if #problems > 0 then
				error(
					string.format(
						"invalid %s preset %s: %s",
						kind,
						tostring(preset and preset.id),
						table.concat(problems, "; ")
					),
					2
				)
			end
			local existing = presets[preset.id]
			if existing ~= nil then
				if not (options and options.override) then
					error(
						string.format(
							"%s preset %s already exists; pass { override = true } to replace it",
							kind,
							preset.id
						),
						2
					)
				end
				if originals[preset.id] == nil then
					originals[preset.id] = existing
				end
			end
			presets[preset.id] = preset
			return preset
		end,
		unregister = function(_self: Registry, id: string): boolean
			if presets[id] == nil then
				return false
			end
			presets[id] = nil
			originals[id] = nil
			return true
		end,
		get = get,
		find = function(_self: Registry, id: string): Preset?
			return presets[id]
		end,
		has = function(_self: Registry, id: string): boolean
			return presets[id] ~= nil
		end,
		original = function(_self: Registry, id: string): Preset?
			return originals[id]
		end,
		isOverridden = function(_self: Registry, id: string): boolean
			return originals[id] ~= nil
		end,
		-- Puts the built-in preset back after an override.
		reset = function(_self: Registry, id: string): boolean
			local original = originals[id]
			if original == nil then
				return false
			end
			presets[id] = original
			originals[id] = nil
			return true
		end,
		list = list,
		ids = function(_self: Registry, filter: Filter?): { string }
			local out: { string } = {}
			for _, preset in list(self, filter) do
				table.insert(out, preset.id)
			end
			return out
		end,
		categories = function(_self: Registry): { string }
			local seen: { [string]: boolean } = {}
			local out: { string } = {}
			for _, preset in presets do
				if not seen[preset.category] then
					seen[preset.category] = true
					table.insert(out, preset.category)
				end
			end
			table.sort(out)
			return out
		end,
		-- Ids ranked by relevance: id match, then name, tags, category and description.
		search = function(_self: Registry, query: string, limit: number?): { string }
			local words: { string } = {}
			for word in string.gmatch(string.lower(query), "[%w]+") do
				table.insert(words, word)
			end
			local scored: { { id: string, score: number } } = {}
			for id, preset in presets do
				local score = 0
				local lowerId = string.lower(id)
				local lowerName = string.lower(preset.name)
				local lowerDescription = string.lower(preset.description)
				for _, word in words do
					if string.find(lowerId, word, 1, true) then
						score += 8
					end
					if string.find(lowerName, word, 1, true) then
						score += 5
					end
					local tags: { string } = preset.tags or {}
					for _, tag in tags do
						if string.find(string.lower(tag), word, 1, true) then
							score += 4
							break
						end
					end
					if string.find(string.lower(preset.category), word, 1, true) then
						score += 3
					end
					if string.find(lowerDescription, word, 1, true) then
						score += 1
					end
				end
				if score > 0 then
					table.insert(scored, { id = id, score = score })
				end
			end
			type Scored = { id: string, score: number }
			table.sort(scored, function(a: Scored, b: Scored): boolean
				return if a.score == b.score then a.id < b.id else a.score > b.score
			end)
			local out: { string } = {}
			for index, entry in scored do
				if limit and index > limit then
					break
				end
				table.insert(out, entry.id)
			end
			return out
		end,
		-- Parameter values for a preset: defaults merged with `overrides`. Numbers are clamped to
		-- min/max; a value of the wrong type or an unknown enum option raises an error. Unknown
		-- override keys pass through untouched so modules can accept free-form options.
		params = function(_self: Registry, id: string, overrides: { [string]: any }?): { [string]: any }
			local preset = get(self, id)
			local out: { [string]: any } = {}
			local declared: { [string]: Param } = preset.params or {}
			for name, param in declared do
				out[name] = param.default
			end
			local given: { [any]: any } = overrides or {}
			for key, value in given do
				local name = tostring(key)
				local param = declared[name]
				if param == nil then
					out[name] = value
				elseif param.type == "number" then
					if type(value) ~= "number" or value ~= value then
						error(string.format("%s.%s must be a number", id, name), 2)
					end
					out[name] = math.clamp(value, param.min or -math.huge, param.max or math.huge)
				elseif param.type == "color" then
					-- Hex strings are checked; anything else (a Color3 in Roblox) is passed through.
					if type(value) == "string" and not isHex(value) then
						error(string.format("%s.%s must be #RRGGBB", id, name), 2)
					end
					out[name] = value
				elseif param.type == "boolean" then
					if type(value) ~= "boolean" then
						error(string.format("%s.%s must be a boolean", id, name), 2)
					end
					out[name] = value
				elseif param.type == "enum" then
					if not table.find(param.options or {}, value) then
						error(
							string.format("%s.%s must be one of: %s", id, name, table.concat(param.options or {}, ", ")),
							2
						)
					end
					out[name] = value
				else
					if type(value) ~= "string" then
						error(string.format("%s.%s must be a string", id, name), 2)
					end
					out[name] = value
				end
			end
			return out
		end,
		-- Plain metadata (no `data`) for tools, the playground and AI agents.
		describe = function(_self: Registry, id: string): { [string]: any }
			local preset = get(self, id)
			return {
				kind = kind,
				id = preset.id,
				name = preset.name,
				category = preset.category,
				description = preset.description,
				params = preset.params or {},
				themes = preset.themes or { "*" },
				quality = preset.quality or { min = "Low", cost = "low" },
				dependencies = preset.dependencies or {},
				preview = preset.preview or {},
				usage = preset.usage or "",
				tags = preset.tags or {},
				overridden = originals[id] ~= nil,
			}
		end,
		count = function(_self: Registry): number
			local n = 0
			for _ in presets do
				n += 1
			end
			return n
		end,
	}
	return self
end

return Registry
