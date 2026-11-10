--!strict
-- Pure logic for the UltimateVisuals Playground: the category list, generated parameter controls,
-- the "example code" text for the current selection, list filtering, the lazy row window and the
-- metrics text. No Roblox types, so library/tests/visuals_demos_playground.spec.luau covers it.

export type Param = {
	type: string, -- "number" | "color" | "boolean" | "string" | "enum"
	default: any,
	min: number?,
	max: number?,
	options: { string }?,
	description: string?,
}

export type Params = { [string]: Param }

export type Category = {
	id: string,
	label: string,
	kind: string?, -- the Visuals.Presets kind, for categories backed by a registry
}

export type Selection = {
	category: string,
	id: string,
	params: Params?, -- metadata of the selected preset
	values: { [string]: any }?, -- current control values
	looping: boolean?, -- vfx: attach instead of play
	group: string?, -- camera: the preset's registry category ("shake" | "cinematic" | "move")
	context: { string }?, -- feedback: the context fields the recipe reads
	props: { [string]: any }?, -- components: the sample props
	module: string?, -- demos: the ModuleScript name
}

export type Control = {
	name: string,
	kind: string, -- "slider" | "toggle" | "dropdown" | "swatches" | "text"
	param: Param,
	min: number?,
	max: number?,
	step: number?,
}

local PlaygroundLogic = {}

local CATEGORIES: { Category } = {
	{ id = "vfx", label = "VFX", kind = "vfx" },
	{ id = "ui", label = "UI animations", kind = "ui" },
	{ id = "object", label = "Objects", kind = "object" },
	{ id = "camera", label = "Camera", kind = "camera" },
	{ id = "pet", label = "Pets", kind = "pet" },
	{ id = "rewards", label = "Rewards" },
	{ id = "eggs", label = "Eggs" },
	{ id = "feedback", label = "Feedback" },
	{ id = "themes", label = "Themes" },
	{ id = "icons", label = "Icons" },
	{ id = "components", label = "Components" },
	{ id = "demos", label = "Demos" },
}

function PlaygroundLogic.categories(): { Category }
	return table.clone(CATEGORIES)
end

function PlaygroundLogic.category(id: string): Category?
	for _, category in CATEGORIES do
		if category.id == id then
			return category
		end
	end
	return nil
end

PlaygroundLogic.QUALITY = table.freeze({ "Low", "Medium", "High", "Ultra" })

PlaygroundLogic.EGG_MODES = table.freeze({ "Single", "Triple", "Multi", "Auto" })

-- Eggs per mode ("Auto" hatches batches of three).
function PlaygroundLogic.eggCount(mode: string): number
	if mode == "Triple" or mode == "Auto" then
		return 3
	elseif mode == "Multi" then
		return 8
	end
	return 1
end

-- Parameter metadata for the categories that are not registry presets.
function PlaygroundLogic.rewardParams(): Params
	return {
		fastForward = { type = "boolean", default = false, description = "Compress the reveal" },
		compact = { type = "boolean", default = false, description = "Short form used inside batches" },
		skipAnticipation = { type = "boolean", default = false, description = "Start at the reveal" },
		speed = { type = "number", default = 1, min = 0.5, max = 3, description = "Playback speed" },
	}
end

function PlaygroundLogic.eggParams(rarities: { string }): Params
	return {
		rarity = {
			type = "enum",
			default = "Rare",
			options = table.clone(rarities),
			description = "Rarity of every egg",
		},
		speed = { type = "number", default = 1, min = 0.5, max = 3, description = "Playback speed" },
		camera = { type = "boolean", default = true, description = "Camera push and shakes" },
	}
end

function PlaygroundLogic.feedbackParams(rarities: { string }): Params
	return {
		amount = { type = "number", default = 5, min = 1, max = 1000, description = "context.amount" },
		rarity = { type = "enum", default = "Rare", options = table.clone(rarities), description = "context.rarity" },
	}
end

-- Values -----------------------------------------------------------------------------------------

function PlaygroundLogic.defaults(params: Params?): { [string]: any }
	local values: { [string]: any } = {}
	local declared: Params = params or {}
	for name, param in declared do
		values[name] = param.default
	end
	return values
end

local function same(param: Param, a: any, b: any): boolean
	if param.type == "number" and type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) < 1e-6
	elseif param.type == "color" and type(a) == "string" and type(b) == "string" then
		return string.upper(a) == string.upper(b)
	end
	return a == b
end

-- Only the values that differ from the preset's defaults: what the example code and the call need.
-- Values for names the preset does not declare are dropped.
function PlaygroundLogic.changed(params: Params?, values: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	local given: { [string]: any } = values or {}
	local declared: Params = params or {}
	for name, param in declared do
		local value = given[name]
		if value ~= nil and not same(param, value, param.default) then
			out[name] = value
		end
	end
	return out
end

-- Rounds a slider value to its step and keeps it inside the parameter's range.
function PlaygroundLogic.clamp(param: Param, value: number): number
	local low = param.min or -math.huge
	local high = param.max or math.huge
	return math.clamp(value, low, high)
end

-- The control each parameter gets, in name order so the panel never reshuffles.
function PlaygroundLogic.controls(params: Params?): { Control }
	local names: { string } = {}
	local declared: Params = params or {}
	for name in declared do
		table.insert(names, name)
	end
	table.sort(names)
	local controls: { Control } = {}
	for _, name in names do
		local param = declared[name]
		if param.type == "number" then
			local default = if type(param.default) == "number" then param.default else 0
			-- A parameter without a range gets one around its default.
			local low = param.min or math.min(0, default)
			local high = param.max or math.max(1, default * 2, low + 1)
			table.insert(controls, {
				name = name,
				kind = "slider",
				param = param,
				min = low,
				max = high,
				step = if high - low >= 20 then 1 else (high - low) / 100,
			})
		elseif param.type == "boolean" then
			table.insert(controls, { name = name, kind = "toggle", param = param })
		elseif param.type == "enum" then
			table.insert(controls, { name = name, kind = "dropdown", param = param })
		elseif param.type == "color" then
			table.insert(controls, { name = name, kind = "swatches", param = param })
		else
			table.insert(controls, { name = name, kind = "text", param = param })
		end
	end
	return controls
end

-- Swatch colours for a colour parameter: the default first, then the theme's colours without
-- repeats (case-insensitive), at most `limit`.
function PlaygroundLogic.swatches(default: any, themeColors: { string }, limit: number?): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(hex: any)
		if type(hex) ~= "string" or string.match(hex, "^#%x%x%x%x%x%x$") == nil then
			return
		end
		local key = string.upper(hex)
		if not seen[key] and #out < (limit or 8) then
			seen[key] = true
			table.insert(out, key)
		end
	end
	add(default)
	for _, hex in themeColors do
		add(hex)
	end
	return out
end

-- Example code ----------------------------------------------------------------------------------

local function isIdentifier(text: string): boolean
	return string.match(text, "^[%a_][%w_]*$") ~= nil
end

local function isArray(value: { [any]: any }): boolean
	local count = 0
	for _ in value do
		count += 1
	end
	return count > 0 and count == #value
end

-- A Luau literal for a value: numbers without float noise, quoted strings, sorted table keys.
function PlaygroundLogic.literal(value: any): string
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		local text = string.format("%.3f", value)
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
		return text
	elseif kind == "string" then
		local escaped = string.gsub(value, '[\\"\n]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n" })
		return '"' .. escaped .. '"'
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		return PlaygroundLogic.tableLiteral(value)
	end
	return "nil"
end

-- "{ a = 1, b = "x" }" with keys sorted; arrays keep their order; an empty table is "{}".
function PlaygroundLogic.tableLiteral(values: { [any]: any }): string
	if next(values) == nil then
		return "{}"
	end
	local parts: { string } = {}
	if isArray(values) then
		for _, item in values do
			table.insert(parts, PlaygroundLogic.literal(item))
		end
	else
		local keys: { string } = {}
		for key in values do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		for _, key in keys do
			local name = if isIdentifier(key) then key else "[" .. PlaygroundLogic.literal(key) .. "]"
			table.insert(parts, name .. " = " .. PlaygroundLogic.literal(values[key]))
		end
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ", { ... }" for a trailing options argument, or "" when there is nothing to pass.
local function trailing(values: { [string]: any }): string
	if next(values) == nil then
		return ""
	end
	return ", " .. PlaygroundLogic.tableLiteral(values)
end

local CAMERA_MOVES: { [string]: string } = {
	Focus = "local handle = Visuals.Camera.focus(target, { duration = 2.5 })",
	Fov = "local handle = Visuals.Camera.fov(45, { duration = 1.5 })",
	Zoom = "local handle = Visuals.Camera.zoom(1.6, { duration = 1.5 })",
	Orbit = "local handle = Visuals.Camera.orbit(target, { duration = 4 })",
	Pan = "local handle = Visuals.Camera.pan(fromCFrame, toCFrame, { duration = 2 })",
	PunchFov = "Visuals.Camera.punchFov(8)",
}

-- The fields a feedback recipe reads from its context ("$position", "+$amount", "$pet.name"),
-- sorted, top-level names only.
function PlaygroundLogic.contextFields(recipe: any): { string }
	local seen: { [string]: boolean } = {}
	local function visit(value: any, depth: number)
		if type(value) == "string" then
			for name in string.gmatch(value, "%$([%a_][%w_]*)") do
				seen[name] = true
			end
		elseif type(value) == "table" and depth < 6 then
			for _, item in value do
				visit(item, depth + 1)
			end
		end
	end
	visit(recipe, 0)
	local names: { string } = {}
	for name in seen do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- The exact Luau call for the current selection. Only parameters that differ from the preset's
-- defaults are written, in name order, so the same selection always gives the same text.
function PlaygroundLogic.exampleCode(selection: Selection): string
	local id = PlaygroundLogic.literal(selection.id)
	local values = PlaygroundLogic.changed(selection.params, selection.values)
	local category = selection.category
	if category == "vfx" then
		if selection.looping then
			return string.format(
				"local handle = Visuals.VFX.attach(%s, target%s)\n-- later: handle.stop()",
				id,
				trailing(values)
			)
		end
		return string.format("Visuals.VFX.play(%s, target.Position%s)", id, trailing(values))
	elseif category == "ui" then
		return string.format("Visuals.UI.animate(gui, %s%s)", id, trailing(values))
	elseif category == "object" then
		return string.format("local handle = Visuals.Objects.animate(model, %s%s)", id, trailing(values))
	elseif category == "camera" then
		if selection.group == "shake" then
			return string.format("Visuals.Camera.shake(%s%s)", id, trailing(values))
		elseif selection.group == "cinematic" then
			return string.format("local handle = Visuals.Camera.cinematic(%s, target%s)", id, trailing(values))
		end
		return CAMERA_MOVES[selection.id] or string.format("-- %s is used through Visuals.Camera", selection.id)
	elseif category == "pet" then
		return string.format("Visuals.Pets.play(%s, petModel%s)", id, trailing(values))
	elseif category == "rewards" then
		return string.format(
			'local handle = Visuals.Rewards.reveal(%s, { name = "Demo reward", amount = 250 }%s)',
			id,
			trailing(values)
		)
	elseif category == "eggs" then
		local given: { [string]: any } = selection.values or {}
		local rarity = PlaygroundLogic.literal(given.rarity or "Rare")
		local count = PlaygroundLogic.eggCount(selection.id)
		local lines = { "local hatch = Visuals.Eggs.hatch({" }
		if count == 1 then
			table.insert(lines, string.format('\teggs = { { rarity = %s, name = "Demo pet" } },', rarity))
		else
			table.insert(
				lines,
				string.format('\teggs = eggs, -- %d entries like { rarity = %s, name = "Demo pet" }', count, rarity)
			)
		end
		if selection.id == "Auto" then
			table.insert(lines, '\tmode = "auto",')
			table.insert(lines, "\tnext = nextBatch, -- returns the next list of eggs, or nil to stop")
		end
		-- The rarity is part of each egg; the other changed values are hatch options.
		local names: { string } = {}
		for name in values do
			if name ~= "rarity" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in names do
			table.insert(lines, string.format("\t%s = %s,", name, PlaygroundLogic.literal(values[name])))
		end
		table.insert(lines, "})")
		return table.concat(lines, "\n")
	elseif category == "feedback" then
		local fields: { string } = {}
		local context: { string } = selection.context or {}
		for _, name in context do
			table.insert(fields, name .. " = " .. name)
		end
		if #fields == 0 then
			return string.format("Visuals.Feedback.fire(%s)", id)
		end
		return string.format("Visuals.Feedback.fire(%s, { %s })", id, table.concat(fields, ", "))
	elseif category == "themes" then
		return string.format("Visuals.Themes.set(%s)", id)
	elseif category == "icons" then
		return string.format("local icon = Visuals.Icons.create(%s, { size = 48 })\nicon.Parent = parent", id)
	elseif category == "components" then
		local props: { [string]: any } = table.clone(selection.props or {})
		local overrides: { [string]: any } = selection.values or {}
		for name, value in overrides do
			props[name] = value
		end
		local text = PlaygroundLogic.tableLiteral(props)
		local body = if text == "{}" then "{ parent = parent }" else "{ parent = parent, " .. string.sub(text, 3)
		return string.format("local component = UrkUI.Game.%s.new(%s)", selection.id, body)
	elseif category == "demos" then
		return string.format(
			"local stop = require(script.Parent.%s).start(playerGui)\n-- later: stop()",
			selection.module or selection.id
		)
	end
	return "-- nothing to show for " .. category
end

-- Lists ------------------------------------------------------------------------------------------

-- Ids that contain every word of the query (case-insensitive), in their original order.
function PlaygroundLogic.filter(ids: { string }, query: string?): { string }
	local words: { string } = {}
	for word in string.gmatch(string.lower(query or ""), "%S+") do
		table.insert(words, word)
	end
	if #words == 0 then
		return table.clone(ids)
	end
	local out: { string } = {}
	for _, id in ids do
		local lower = string.lower(id)
		local matches = true
		for _, word in words do
			if string.find(lower, word, 1, true) == nil then
				matches = false
				break
			end
		end
		if matches then
			table.insert(out, id)
		end
	end
	return out
end

-- Keeps the ids of one kind from Visuals.Presets.search results, in ranked order.
function PlaygroundLogic.ofKind(entries: { { kind: string, id: string } }, kind: string): { string }
	local out: { string } = {}
	for _, entry in entries do
		if entry.kind == kind then
			table.insert(out, entry.id)
		end
	end
	return out
end

-- The rows a scrolling list needs to exist: first and last index (1-based, inclusive) for a
-- scroll offset, with `overscan` rows either side. Returns 1, 0 for an empty list.
function PlaygroundLogic.visibleRows(
	scroll: number,
	viewport: number,
	rowHeight: number,
	total: number,
	overscan: number?
): (number, number)
	if total <= 0 or rowHeight <= 0 then
		return 1, 0
	end
	local extra = math.max(0, overscan or 2)
	local first = math.floor(math.max(0, scroll) / rowHeight) + 1 - extra
	local last = math.ceil((math.max(0, scroll) + math.max(0, viewport)) / rowHeight) + extra
	first = math.clamp(first, 1, total)
	last = math.clamp(last, first, total)
	return first, last
end

-- Metrics ----------------------------------------------------------------------------------------

export type FpsSampler = { times: { number }, size: number, index: number, count: number }

function PlaygroundLogic.newSampler(size: number?): FpsSampler
	return { times = {}, size = math.max(1, math.floor(size or 60)), index = 0, count = 0 }
end

function PlaygroundLogic.sample(sampler: FpsSampler, dt: number)
	if dt ~= dt or dt <= 0 then
		return
	end
	sampler.index = sampler.index % sampler.size + 1
	sampler.times[sampler.index] = dt
	sampler.count = math.min(sampler.count + 1, sampler.size)
end

-- Average frames per second over the sampled frames (0 before the first frame).
function PlaygroundLogic.fps(sampler: FpsSampler): number
	if sampler.count == 0 then
		return 0
	end
	local total = 0
	for index = 1, sampler.count do
		total += sampler.times[index]
	end
	return sampler.count / total
end

-- The live metrics block: fps, tracks, effects, particles and why effects were rejected.
function PlaygroundLogic.metrics(stats: { [string]: any }, fps: number): { string }
	local reasons: { string } = {}
	local rejected: { [any]: any } = if type(stats.rejected) == "table" then stats.rejected :: any else {}
	for reason, count in rejected do
		table.insert(reasons, string.format("%s %d", tostring(reason), tonumber(count) or 0))
	end
	table.sort(reasons)
	return {
		string.format("%.0f fps   quality %s", fps, tostring(stats.level or "?")),
		string.format("tracks %d   jobs %d", tonumber(stats.tracks) or 0, tonumber(stats.jobs) or 0),
		string.format(
			"effects %d   particles ~%d   lights %d",
			tonumber(stats.effects) or 0,
			tonumber(stats.particles) or 0,
			tonumber(stats.lights) or 0
		),
		"rejected: " .. (if #reasons > 0 then table.concat(reasons, ", ") else "none"),
	}
end

return PlaygroundLogic
