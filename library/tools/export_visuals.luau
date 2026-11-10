--!nonstrict
-- Writes catalog/visuals.json: every UltimateVisualsKit preset as plain, sorted JSON, so tools and
-- AI agents can find an existing effect before writing a new one. Only the pure modules are
-- required, so this runs under Lune with no Roblox. (Nonstrict: it builds free-form JSON tables.)
--
-- From library/:
--   lune run tools/export_visuals            -- write ../catalog/visuals.json
--   lune run tools/export_visuals --check    -- exit 1 when the committed file is stale (CI)
--
-- The output is deterministic: object keys are sorted, lists are sorted by id (or keep the
-- module's own meaningful order, such as rarity rank), and numbers are printed with a fixed rule.

local fs = require("@lune/fs")
local process = require("@lune/process")

local AudioLogic = require("../src/Visuals/Audio/AudioLogic")
local CameraLogic = require("../src/Visuals/Camera/CameraLogic")
local Catalog = require("../src/Visuals/VFX/CatalogData")
local FeedbackLogic = require("../src/Visuals/Feedback/FeedbackLogic")
local ObjectsLogic = require("../src/Visuals/Objects/ObjectsLogic")
local PetsLogic = require("../src/Visuals/Pets/PetsLogic")
local PresetsLogic = require("../src/Visuals/Presets/PresetsLogic")
local Quality = require("../src/Visuals/Core/Quality")
local Registry = require("../src/Visuals/Core/Registry")
local RewardsLogic = require("../src/Visuals/Rewards/RewardsLogic")
local ThemeData = require("../src/Visuals/Themes/ThemeData")
local UIPresets = require("../src/Visuals/UI/UIPresets")

local ROOT = if fs.isDir("src") then ".." else "."
local LIBRARY = if fs.isDir("src") then "." else "library"
local OUT = ROOT .. "/catalog/visuals.json"

type Map = { [string]: any }

-- JSON ------------------------------------------------------------------------------------------

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function quote(text: string): string
	local escaped = string.gsub(text, '[%c"\\]', function(char: string): string
		return ESCAPES[char] or string.format("\\u%04x", string.byte(char))
	end)
	return '"' .. escaped .. '"'
end

local function number(value: number): string
	if value ~= value or value == math.huge or value == -math.huge then
		return "null"
	elseif value == math.floor(value) and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return string.format("%.6g", value)
end

local function isArray(value: any): boolean
	local count = 0
	for _ in value do
		count += 1
	end
	return count == #value
end

local function encode(value: any, indent: string, out: { string })
	local kind = type(value)
	if kind == "table" then
		local inner = indent .. " "
		if next(value) == nil then
			table.insert(out, "[]")
		elseif isArray(value) then
			table.insert(out, "[\n")
			for index, item in value do
				table.insert(out, inner)
				encode(item, inner, out)
				table.insert(out, if index < #value then ",\n" else "\n")
			end
			table.insert(out, indent .. "]")
		else
			local keys: { string } = {}
			for key in value do
				table.insert(keys, tostring(key))
			end
			table.sort(keys)
			table.insert(out, "{\n")
			for index, key in keys do
				table.insert(out, inner .. quote(key) .. ": ")
				encode(value[key], inner, out)
				table.insert(out, if index < #keys then ",\n" else "\n")
			end
			table.insert(out, indent .. "}")
		end
	elseif kind == "string" then
		table.insert(out, quote(value))
	elseif kind == "number" then
		table.insert(out, number(value))
	elseif kind == "boolean" then
		table.insert(out, if value then "true" else "false")
	else
		table.insert(out, "null")
	end
end

-- Helpers ---------------------------------------------------------------------------------------

-- An always-object value: an empty Luau table would otherwise be written as [].
local EMPTY_OBJECT = "\0object"

local function object(value: Map?): any
	if value == nil or next(value) == nil then
		return EMPTY_OBJECT
	end
	return value
end

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

local catalog = PresetsLogic.new()

-- One catalogue entry from a Core/Registry preset.
local function fromRegistry(registry: Registry.Registry, id: string): Map
	local described = catalog:describe(registry.kind, id)
	local params: Map = {}
	for name, param in described.params :: Map do
		params[name] = {
			type = param.type,
			default = param.default,
			min = param.min,
			max = param.max,
			options = param.options,
			description = param.description,
		}
	end
	return {
		id = described.id,
		name = described.name,
		category = described.category,
		description = described.description,
		params = object(params),
		quality = described.quality,
		usage = described.usage,
		tags = sorted(described.tags),
		dependencies = sorted(described.dependencies),
	}
end

local function registryKind(registry: Registry.Registry): { Map }
	catalog:add(registry)
	local out: { Map } = {}
	for _, id in registry:ids() do
		table.insert(out, fromRegistry(registry, id))
	end
	return out
end

-- Kinds -----------------------------------------------------------------------------------------

local kinds: { [string]: { Map } } = {}

kinds.vfx = registryKind(Catalog.registry())
kinds.ui = registryKind(UIPresets.registry)
kinds.object = registryKind(ObjectsLogic.registry)
kinds.camera = registryKind(CameraLogic.registry)
kinds.pet = registryKind(PetsLogic.registry)

-- Screens are optional: another module may add a pure data or logic module with a registry.
local screensDir = LIBRARY .. "/src/Visuals/Screens"
if fs.isDir(screensDir) then
	for _, fileName in sorted(fs.readDir(screensDir)) do
		local stem = string.match(fileName, "^(.+)%.luau$")
		local pure = stem ~= nil
			and (
				string.match(stem, "Logic$") ~= nil
				or string.match(stem, "Data$") ~= nil
				or string.match(stem, "Presets$") ~= nil
			)
		if stem and pure then
			local path = "../src/Visuals/Screens/" .. stem
			local ok, module = pcall(function(): any
				return (require :: any)(path)
			end)
			local registry = if ok and type(module) == "table" then module.registry else nil
			if type(registry) == "table" and type(registry.ids) == "function" and kinds[registry.kind] == nil then
				kinds[registry.kind] = registryKind(registry)
			end
		end
	end
end

-- Rarity profiles (Rewards). Kept in rank order: the order is the hierarchy.
do
	local out: { Map } = {}
	for _, id in RewardsLogic.list() do
		local profile = RewardsLogic.get(id)
		local vfx: { string } = {}
		for _, effect in profile.vfx do
			table.insert(vfx, effect.id)
		end
		local camera: { string } = {}
		if profile.camera.shake then
			table.insert(camera, "shake:" .. profile.camera.shake)
		end
		if profile.camera.cinematic then
			table.insert(camera, "cinematic:" .. profile.camera.cinematic)
		end
		if profile.camera.fov then
			table.insert(camera, "fovPunch")
		end
		table.insert(out, {
			id = id,
			name = profile.label,
			category = "rarity",
			description = string.format(
				"Rank %s rarity: %s reveal on a %s background, %s s to the settled state, %s s anticipation.",
				number(profile.rank),
				profile.revealStyle,
				profile.background,
				number(profile.duration),
				number(profile.anticipation)
			),
			params = EMPTY_OBJECT,
			quality = {
				min = "Low",
				cost = if profile.layers >= 5 then "high" elseif profile.layers >= 3 then "medium" else "low",
			},
			usage = catalog:usage("rarity", id),
			rank = profile.rank,
			color = profile.color,
			duration = profile.duration,
			anticipation = profile.anticipation,
			revealStyle = profile.revealStyle,
			background = profile.background,
			rays = profile.rayCount,
			flash = profile.flash,
			layers = profile.layers,
			vfx = vfx,
			camera = camera,
			sounds = profile.sounds,
		})
	end
	kinds.rarity = out
end

-- Feedback events. The Simulator pack is the base; other packs override or add events.
do
	local byEvent: { [string]: Map } = {}
	local function summarise(recipe: { any }): ({ string }, { string })
		local steps: { string } = {}
		local fields: { [string]: boolean } = {}
		local function scan(value: any)
			if type(value) == "string" then
				for name in string.gmatch(value, "%$([%a_][%w_]*)") do
					fields[name] = true
				end
			elseif type(value) == "table" then
				for _, inner in value do
					scan(inner)
				end
			end
		end
		for _, step in recipe do
			local label = step.kind
			local detail = step.id
				or step.preset
				or step.cue
				or step.shake
				or step.cinematic
				or step.reaction
				or step.action
			if type(detail) == "string" then
				label ..= ":" .. detail
			end
			table.insert(steps, label)
			scan(step)
		end
		local names: { string } = {}
		for name in fields do
			table.insert(names, name)
		end
		table.sort(names)
		return steps, names
	end
	for _, packName in { "Simulator", "Combat", "Minimal" } do
		local pack = FeedbackLogic.pack(packName)
		assert(pack, "missing feedback pack " .. packName)
		for event, recipe in pack do
			local steps, context = summarise(recipe :: any)
			local entry = byEvent[event]
			if entry == nil then
				entry = {
					id = event,
					name = event,
					category = packName,
					description = string.format(
						"Feedback recipe for the %s event (%d steps); defined by the %s pack.",
						event,
						#steps,
						packName
					),
					params = EMPTY_OBJECT,
					quality = { min = "Low", cost = "low" },
					usage = catalog:usage("feedback", event),
					steps = steps,
					context = context,
					overriddenBy = {},
				}
				byEvent[event] = entry
			else
				table.insert(entry.overriddenBy, packName)
			end
		end
	end
	local out: { Map } = {}
	for _, entry in byEvent do
		table.sort(entry.overriddenBy)
		table.insert(out, entry)
	end
	table.sort(out, function(a: Map, b: Map): boolean
		return a.id < b.id
	end)
	kinds.feedback = out
end

-- Audio cues. No sounds are bundled: a cue is a name a game may register a sound for.
do
	local out: { Map } = {}
	for _, cue in sorted(AudioLogic.CUES :: any) do
		local group = AudioLogic.defaultGroup(cue)
		table.insert(out, {
			id = cue,
			name = cue,
			category = group,
			description = string.format(
				"Sound cue the kit plays (group %s). Silent until the game registers a sound for it.",
				group
			),
			params = EMPTY_OBJECT,
			quality = { min = "Low", cost = "low" },
			usage = string.format('Visuals.Audio:Register("%s", soundId)', cue),
		})
	end
	kinds.audio = out
end

-- Themes.
do
	local out: { Map } = {}
	for _, id in sorted(ThemeData.IDS :: any) do
		local theme: any = ThemeData.themes[id]
		table.insert(out, {
			id = id,
			name = theme.name or id,
			category = "theme",
			description = theme.description or ("Visual theme using the " .. tostring(theme.style) .. " style."),
			params = EMPTY_OBJECT,
			quality = { min = "Low", cost = "low" },
			usage = string.format('Visuals:Configure({ theme = "%s" })', id),
			style = theme.style,
			default = id == ThemeData.DEFAULT,
			colors = theme.colors,
			intensity = theme.motion.intensity,
			springs = theme.motion.spring,
		})
	end
	kinds.theme = out
end

-- UI/Game components: names from the loader table in Game.luau, descriptions from each file's
-- header comment (the lines before the first example line).
do
	local gameDir = LIBRARY .. "/src/UI/Game"
	local source = fs.readFile(gameDir .. "/Game.luau")
	local out: { Map } = {}
	for name in string.gmatch(source, "\n\t(%u%w+) = function%(%): any\n\t\treturn require%(") do
		local path = gameDir .. "/" .. name .. ".luau"
		if fs.isFile(path) then
			local text: { string } = {}
			for _, line in string.split(fs.readFile(path), "\n") do
				if line == "--!strict" then
					continue
				end
				local comment = string.match(line, "^%-%- (.*)$")
				if comment == nil or string.match(comment, "^%s") ~= nil then
					break
				end
				table.insert(text, comment)
			end
			if #text > 0 then
				table.insert(out, {
					id = name,
					name = name,
					category = "game-component",
					description = table.concat(text, " "),
					params = EMPTY_OBJECT,
					quality = { min = "Low", cost = "low" },
					usage = string.format("Game.%s.new(props)", name),
				})
			end
		end
	end
	table.sort(out, function(a: Map, b: Map): boolean
		return a.id < b.id
	end)
	kinds.component = out
end

-- Quality profiles: the budgets every preset is scaled by.
local quality: Map = {}
for _, level in Quality.LEVELS do
	quality[level] = Quality.profile(level)
end

local counts: Map = {}
local total = 0
for kind, items in kinds do
	counts[kind] = #items
	total += #items
end

local document: Map = {
	_doc = "Generated by library/tools/export_visuals.luau from the pure Visuals modules; do not edit by hand. "
		.. "Search this file for an existing preset before writing any effect. Each entry has id, name, category, "
		.. "description, params, quality and a usage line. Kinds: vfx, ui, object, camera, pet (Core/Registry presets), "
		.. "rarity (Rewards profiles), feedback (events of the built-in packs), audio (cue names; no sounds are bundled), "
		.. "theme, component (UI/Game), and screen when the Screens module is present.",
	version = 1,
	counts = counts,
	total = total,
	quality = quality,
	kinds = kinds,
}

local buffer: { string } = {}
encode(document, "", buffer)
local text = string.gsub(table.concat(buffer), quote(EMPTY_OBJECT), "{}") .. "\n"

if table.find(process.args, "--check") then
	local current = if fs.isFile(OUT) then fs.readFile(OUT) else ""
	if current ~= text then
		print("stale: catalog/visuals.json (run `lune run tools/export_visuals` from library/)")
		process.exit(1)
	end
	print(string.format("catalog/visuals.json is current (%d entries)", total))
else
	fs.writeFile(OUT, text)
	local parts: { string } = {}
	for _, kind in
		sorted((function(): { string }
			local names: { string } = {}
			for name in kinds do
				table.insert(names, name)
			end
			return names
		end)())
	do
		table.insert(parts, string.format("%s %d", kind, counts[kind]))
	end
	print(string.format("catalog/visuals.json: %d entries (%s)", total, table.concat(parts, ", ")))
end
