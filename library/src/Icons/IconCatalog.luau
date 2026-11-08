--!strict
-- Pure icon catalog: lookup, search and sprite-sheet rects. No Roblox globals, so Lune can test it.
-- Icons.luau turns these plain results into Roblox properties.

local IconData = require("./IconData")

export type Rect = { image: string?, pack: string, sheet: number, x: number, y: number, w: number, h: number }
export type Entry = IconData.IconEntry
-- Packs made by tools/icons/import_pack.py have the same shape as IconData plus a `pack` id.
export type Pack = { pack: string?, cell: number, padding: number, icons: { Entry } }

local IconCatalog = {}

local byName: { [string]: Entry } = {}
local packOf: { [string]: string } = {}
local paddingOf: { [string]: number } = { urk = IconData.padding }
local aliases: { [string]: string } = {}
local sheetIds: { [string]: { [number]: string } } = { urk = {} }
local allEntries: { Entry } = {}

for _, entry in IconData.icons do
	byName[entry.name] = entry
	packOf[entry.name] = "urk"
	table.insert(allEntries, entry)
end

-- Accept "arrow_left", "Arrow Left" or "arrowLeft" for "arrow-left".
function IconCatalog.normalize(name: string): string
	local spaced = string.gsub(name, "(%l)(%u)", "%1-%2")
	local lowered = string.lower(spaced)
	local dashed = string.gsub(lowered, "[%s_]+", "-")
	return dashed
end

function IconCatalog.resolve(name: string): Entry?
	local key = IconCatalog.normalize(name)
	local direct = byName[key]
	if direct then
		return direct
	end
	local target = aliases[key]
	if target then
		return byName[target]
	end
	return nil
end

function IconCatalog.has(name: string): boolean
	return IconCatalog.resolve(name) ~= nil
end

-- Add an imported pack. Its names must not clash with icons already registered.
function IconCatalog.register(pack: Pack)
	local id = pack.pack or "custom"
	assert(sheetIds[id] == nil, "pack already registered: " .. id)
	sheetIds[id] = {}
	paddingOf[id] = pack.padding
	for _, entry in pack.icons do
		assert(byName[entry.name] == nil, "icon name already used: " .. entry.name)
		byName[entry.name] = entry
		packOf[entry.name] = id
		table.insert(allEntries, entry)
	end
end

-- Upload sheet-1.png, sheet-2.png ... once and pass their ids in order (`pack` defaults to "urk").
-- Optional aliases map game-specific names onto catalog icons, e.g. { cash = "coins" }.
function IconCatalog.configure(options: { pack: string?, sheets: { string }?, aliases: { [string]: string }? })
	if options.sheets then
		local ids = sheetIds[options.pack or "urk"]
		assert(ids ~= nil, "unknown pack: " .. tostring(options.pack))
		for index, id in options.sheets do
			local valid = type(id) == "string" and string.find(id, "^rbxassetid://%d+$") ~= nil
			assert(valid, "sheet ids look like rbxassetid://123")
			ids[index] = id
		end
	end
	if options.aliases then
		for alias, target in options.aliases do
			assert(byName[IconCatalog.normalize(target)] ~= nil, "alias target is not an icon: " .. target)
			aliases[IconCatalog.normalize(alias)] = IconCatalog.normalize(target)
		end
	end
end

function IconCatalog.sheetId(sheet: number, pack: string?): string?
	local ids = sheetIds[pack or "urk"]
	return if ids then ids[sheet] else nil
end

-- Cell rect inside the sheet, shrunk by the transparent padding so filtering never bleeds.
function IconCatalog.rect(name: string): Rect?
	local entry = IconCatalog.resolve(name)
	if not entry then
		return nil
	end
	local pack = packOf[entry.name]
	local pad = paddingOf[pack]
	return {
		image = sheetIds[pack][entry.sheet],
		pack = pack,
		sheet = entry.sheet,
		x = entry.x + pad,
		y = entry.y + pad,
		w = entry.w - 2 * pad,
		h = entry.h - 2 * pad,
	}
end

function IconCatalog.list(category: string?): { string }
	local names: { string } = {}
	for _, entry in allEntries do
		if category == nil or entry.category == category then
			table.insert(names, entry.name)
		end
	end
	table.sort(names)
	return names
end

function IconCatalog.categories(): { string }
	return table.clone(IconData.categories)
end

-- Ranked search over names and tags: exact name, name prefix, name substring, then tag match.
function IconCatalog.search(query: string, limit: number?): { string }
	local q = IconCatalog.normalize(query)
	if q == "" then
		return {}
	end
	local scored: { { name: string, score: number } } = {}
	for _, entry in allEntries do
		local score = 0
		if entry.name == q then
			score = 100
		elseif string.sub(entry.name, 1, #q) == q then
			score = 60
		elseif string.find(entry.name, q, 1, true) then
			score = 40
		else
			for _, tag in entry.tags do
				if tag == q then
					score = math.max(score, 30)
				elseif string.sub(tag, 1, #q) == q then
					score = math.max(score, 20)
				end
			end
		end
		if score > 0 then
			table.insert(scored, { name = entry.name, score = score })
		end
	end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.name < b.name
	end)
	local results: { string } = {}
	for index, item in scored do
		if limit and index > limit then
			break
		end
		table.insert(results, item.name)
	end
	return results
end

return IconCatalog
