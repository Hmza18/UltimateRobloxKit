--!strict
-- Pure registry for imported icon packs (no Roblox globals, Lune-tested). The data comes from the
-- Luau module written by `tools/icons/vault.py registry <pack>`: names, categories, tags, sizes
-- and Roblox asset ids. No image bytes live here; the originals stay in the private vault.
--
--   IconVaultLogic.register("mypack", require(path.to.MypackIcons))
--   IconVaultLogic.get("mypack:sword")        -- qualified
--   IconVaultLogic.get("sword")               -- default pack first, then the other packs
--   IconVaultLogic.search("coin", 20)         -- { "mypack:coin", "mypack:coin-stack", ... }
--
-- Every list this module returns holds qualified ids ("pack:name"), which are unambiguous and can
-- be passed straight back to get / assetId / image and to IconVault.apply.

export type Rect = { x: number, y: number, w: number, h: number }

export type Entry = {
	id: string, -- "pack:name"
	pack: string,
	name: string,
	category: string,
	tags: { string },
	width: number, -- original pixel size, 0 when unknown
	height: number,
	assetId: number?, -- the icon's own image asset
	sheet: number?, -- sprite sheet index when the icon was packed with `vault.py derive --sheets`
	rect: Rect?,
}

export type Sheet = { width: number, height: number, assetId: number? }

export type Image = { image: string, rect: Rect?, width: number, height: number }

export type Filter = { pack: string?, category: string?, tag: string?, mapped: boolean? }

export type RegisterOptions = { override: boolean?, default: boolean? }

export type PackInfo = { name: string, count: number, mapped: number, categories: { string }, sheets: number }

export type GridLayout = { columns: number, rows: number, cell: number, gap: number, height: number, count: number }

type PackState = {
	name: string,
	entries: { Entry },
	byName: { [string]: Entry },
	sheets: { Sheet },
}

local IconVaultLogic = {}

local packs: { [string]: PackState } = {}
local order: { string } = {}
local explicitDefault: string? = nil

local PACK_PATTERN = "^%l[%l%d%-]*$"
local NAME_PATTERN = "^[%l%d][%l%d%-]*$"

-- "Arrow Left", "arrow_left" and "arrowLeft" all mean "arrow-left" (same rule as Icons/IconCatalog).
function IconVaultLogic.normalize(name: string): string
	local spaced = string.gsub(name, "(%l)(%u)", "%1-%2")
	local lowered = string.lower(spaced)
	local dashed = string.gsub(lowered, "[%s_]+", "-")
	return dashed
end

-- Splits "pack:name" into its parts; an unqualified name returns nil for the pack.
function IconVaultLogic.split(name: string): (string?, string)
	local pack, rest = string.match(name, "^([^:]*):(.*)$")
	if pack ~= nil and rest ~= nil then
		return string.lower(pack :: string), IconVaultLogic.normalize(rest :: string)
	end
	return nil, IconVaultLogic.normalize(name)
end

-- Accepts 123, "123", "rbxassetid://123" and 0 / "" / nil for "none". Returns nil for none and
-- raises on anything else, so a typo never becomes a silent blank icon.
function IconVaultLogic.parseAssetId(value: any): number?
	if value == nil or value == 0 or value == "" then
		return nil
	end
	local id: number? = nil
	if type(value) == "number" then
		id = value
	elseif type(value) == "string" then
		local digits = string.match(value, "^rbxassetid://(%d+)$") or string.match(value, "^(%d+)$")
		id = if digits then tonumber(digits) else nil
	end
	if id == nil or id <= 0 or id % 1 ~= 0 then
		error("not a Roblox asset id: " .. tostring(value), 0)
	end
	return id
end

local function fail(packName: string, message: string): never
	error(string.format("IconVault.register(%s): %s", packName, message), 0)
end

local function build(packName: string, data: any): PackState
	if type(data) ~= "table" then
		fail(packName, "data must be the table returned by the generated icons module")
	end
	if data.pack ~= nil and data.pack ~= packName then
		fail(packName, "this data is for pack " .. tostring(data.pack))
	end
	if type(data.icons) ~= "table" then
		fail(packName, "data.icons must be a list")
	end
	local sheets: { Sheet } = {}
	if data.sheets ~= nil then
		if type(data.sheets) ~= "table" then
			fail(packName, "data.sheets must be a list")
		end
		for index, raw in ipairs(data.sheets :: { any }) do
			if type(raw) ~= "table" or type(raw.width) ~= "number" or type(raw.height) ~= "number" then
				fail(packName, string.format("sheet %d needs width and height", index))
			end
			local ok, id = pcall(IconVaultLogic.parseAssetId, raw.assetId)
			if not ok then
				fail(packName, string.format("sheet %d: %s", index, tostring(id)))
			end
			table.insert(sheets, { width = raw.width, height = raw.height, assetId = id })
		end
	end
	local state: PackState = { name = packName, entries = {}, byName = {}, sheets = sheets }
	for index, raw in ipairs(data.icons :: { any }) do
		local where = string.format("icon %d", index)
		if type(raw) ~= "table" then
			fail(packName, where .. " must be a table")
		end
		local name = raw.name
		if type(name) ~= "string" or string.match(name, NAME_PATTERN) == nil then
			fail(packName, where .. " needs a kebab-case name, got " .. tostring(name))
		end
		where = "icon " .. name
		if state.byName[name] ~= nil then
			fail(packName, where .. " is listed twice")
		end
		if type(raw.category) ~= "string" or raw.category == "" then
			fail(packName, where .. " needs a category")
		end
		local tags: { string } = {}
		if raw.tags ~= nil then
			if type(raw.tags) ~= "table" then
				fail(packName, where .. ": tags must be a list of strings")
			end
			for _, tag in ipairs(raw.tags :: { any }) do
				if type(tag) ~= "string" then
					fail(packName, where .. ": tags must be a list of strings")
				end
				table.insert(tags, string.lower(tag))
			end
		end
		local width, height = raw.width, raw.height
		if (width ~= nil and type(width) ~= "number") or (height ~= nil and type(height) ~= "number") then
			fail(packName, where .. ": width and height must be numbers")
		end
		local ok, id = pcall(IconVaultLogic.parseAssetId, raw.assetId)
		if not ok then
			fail(packName, where .. ": " .. tostring(id))
		end
		local entry: Entry = {
			id = packName .. ":" .. name,
			pack = packName,
			name = name,
			category = raw.category,
			tags = tags,
			width = math.max(0, width or 0),
			height = math.max(0, height or 0),
			assetId = id,
		}
		local sheet = raw.sheet
		if sheet ~= nil and sheet ~= 0 then
			if type(sheet) ~= "number" or sheets[sheet] == nil then
				fail(packName, where .. ": sheet " .. tostring(sheet) .. " is not in data.sheets")
			end
			local x, y, w, h = raw.x, raw.y, raw.w, raw.h
			local numbers = type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number"
			if not numbers or w <= 0 or h <= 0 or x < 0 or y < 0 then
				fail(packName, where .. ": a sheet icon needs x, y, w and h")
			end
			entry.sheet = sheet
			entry.rect = { x = x, y = y, w = w, h = h }
		end
		state.byName[name] = entry
		table.insert(state.entries, entry)
	end
	table.sort(state.entries, function(a: Entry, b: Entry): boolean
		return a.name < b.name
	end)
	return state
end

-- Registers a pack. `data` is the table returned by the generated module. Nothing is registered
-- when validation fails. Returns the number of icons. Registering a pack again raises unless
-- options.override is true; options.default makes it the default pack for unqualified names.
function IconVaultLogic.register(packName: string, data: any, options: RegisterOptions?): number
	if type(packName) ~= "string" or string.match(packName, PACK_PATTERN) == nil then
		error("IconVault.register: pack names are lowercase letters, digits and '-', got " .. tostring(packName), 0)
	end
	local replacing = packs[packName] ~= nil
	if replacing and not (options and options.override) then
		fail(packName, "pack already registered (pass { override = true } to replace it)")
	end
	local state = build(packName, data)
	packs[packName] = state
	if not replacing then
		table.insert(order, packName)
	end
	if options and options.default then
		explicitDefault = packName
	end
	return #state.entries
end

function IconVaultLogic.unregister(packName: string): boolean
	if packs[packName] == nil then
		return false
	end
	packs[packName] = nil
	local index = table.find(order, packName)
	if index then
		table.remove(order, index)
	end
	if explicitDefault == packName then
		explicitDefault = nil
	end
	return true
end

-- Forgets every pack (tests, and tools that reload data).
function IconVaultLogic.reset()
	packs = {}
	order = {}
	explicitDefault = nil
end

-- The pack unqualified names resolve in first: the one set here, else the first registered.
function IconVaultLogic.setDefaultPack(packName: string?)
	if packName ~= nil and packs[packName] == nil then
		error("IconVault.setDefaultPack: unknown pack " .. tostring(packName), 0)
	end
	explicitDefault = packName
end

function IconVaultLogic.defaultPack(): string?
	return explicitDefault or order[1]
end

-- Pack names in resolution order: the default pack, then the rest in registration order.
function IconVaultLogic.packs(): { string }
	local names: { string } = {}
	local first = IconVaultLogic.defaultPack()
	if first then
		table.insert(names, first)
	end
	for _, name in order do
		if name ~= first then
			table.insert(names, name)
		end
	end
	return names
end

function IconVaultLogic.count(packName: string?): number
	if packName ~= nil then
		local state = packs[packName]
		return if state then #state.entries else 0
	end
	local total = 0
	for _, state in packs do
		total += #state.entries
	end
	return total
end

-- The entry for "pack:name" or "name", or nil. Treat the returned table as read-only.
function IconVaultLogic.get(name: string): Entry?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local packName, key = IconVaultLogic.split(name)
	if packName ~= nil then
		local state = packs[packName]
		return if state then state.byName[key] else nil
	end
	for _, candidate in IconVaultLogic.packs() do
		local entry = packs[candidate].byName[key]
		if entry then
			return entry
		end
	end
	return nil
end

function IconVaultLogic.has(name: string): boolean
	return IconVaultLogic.get(name) ~= nil
end

-- "rbxassetid://123" for the icon's own image, or nil when it has not been uploaded and mapped.
function IconVaultLogic.assetId(name: string): string?
	local entry = IconVaultLogic.get(name)
	if entry and entry.assetId then
		return "rbxassetid://" .. tostring(entry.assetId)
	end
	return nil
end

-- What to show for an icon: its own image when it has an asset id, else its sprite sheet and rect
-- when that sheet has one, else nil (not uploaded yet).
function IconVaultLogic.image(name: string): Image?
	local entry = IconVaultLogic.get(name)
	if entry == nil then
		return nil
	end
	if entry.assetId then
		local own: Image = {
			image = "rbxassetid://" .. tostring(entry.assetId),
			width = entry.width,
			height = entry.height,
		}
		return own
	end
	local rect = entry.rect
	if entry.sheet and rect then
		local sheet = packs[entry.pack].sheets[entry.sheet]
		if sheet and sheet.assetId then
			return {
				image = "rbxassetid://" .. tostring(sheet.assetId),
				rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
				width = rect.w,
				height = rect.h,
			}
		end
	end
	return nil
end

-- Merges asset ids after upload: { ["sword"] = 123, ["coin"] = "rbxassetid://456" }. Returns how
-- many were applied and the names the pack does not have. Invalid ids raise before anything changes.
function IconVaultLogic.setAssetIds(packName: string, ids: { [string]: any }): (number, { string })
	local state = packs[packName]
	if state == nil then
		error("IconVault.setAssetIds: unknown pack " .. tostring(packName), 0)
	end
	local parsed: { [string]: number } = {}
	local unknown: { string } = {}
	for name, value in ids do
		local _, key = IconVaultLogic.split(name)
		if state.byName[key] == nil then
			table.insert(unknown, name)
		else
			local id = IconVaultLogic.parseAssetId(value)
			if id then
				parsed[key] = id
			end
		end
	end
	local applied = 0
	for key, id in parsed do
		state.byName[key].assetId = id
		applied += 1
	end
	table.sort(unknown)
	return applied, unknown
end

-- Sets the asset ids of the pack's sprite sheets, in sheet order.
function IconVaultLogic.setSheetIds(packName: string, ids: { any })
	local state = packs[packName]
	if state == nil then
		error("IconVault.setSheetIds: unknown pack " .. tostring(packName), 0)
	end
	local parsed: { [number]: number } = {}
	for index, value in ids do
		if state.sheets[index] == nil then
			error(string.format("IconVault.setSheetIds: pack %s has no sheet %s", packName, tostring(index)), 0)
		end
		local id = IconVaultLogic.parseAssetId(value)
		if id then
			parsed[index] = id
		end
	end
	for index, id in parsed do
		state.sheets[index].assetId = id
	end
end

local function showable(state: PackState, entry: Entry): boolean
	if entry.assetId then
		return true
	end
	local sheet = if entry.sheet then state.sheets[entry.sheet] else nil
	return sheet ~= nil and sheet.assetId ~= nil
end

-- Names (unqualified, sorted) of the icons that cannot be shown yet: no asset id of their own and
-- no uploaded sheet. With no pack given, qualified ids across every pack.
function IconVaultLogic.missingAssetIds(packName: string?): { string }
	local missing: { string } = {}
	if packName ~= nil then
		local state = packs[packName]
		if state == nil then
			return missing
		end
		for _, entry in state.entries do
			if not showable(state, entry) then
				table.insert(missing, entry.name)
			end
		end
		return missing
	end
	for _, name in IconVaultLogic.packs() do
		local state = packs[name]
		for _, entry in state.entries do
			if not showable(state, entry) then
				table.insert(missing, entry.id)
			end
		end
	end
	return missing
end

function IconVaultLogic.info(packName: string): PackInfo?
	local state = packs[packName]
	if state == nil then
		return nil
	end
	local mapped = 0
	for _, entry in state.entries do
		if showable(state, entry) then
			mapped += 1
		end
	end
	return {
		name = packName,
		count = #state.entries,
		mapped = mapped,
		categories = IconVaultLogic.categories(packName),
		sheets = #state.sheets,
	}
end

-- Sorted category names of one pack, or of every pack.
function IconVaultLogic.categories(packName: string?): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for name, state in packs do
		if packName == nil or packName == name then
			for _, entry in state.entries do
				if not seen[entry.category] then
					seen[entry.category] = true
					table.insert(names, entry.category)
				end
			end
		end
	end
	table.sort(names)
	return names
end

-- Qualified ids matching the filter: pack, category, tag, and mapped (true: can be shown now,
-- false: still needs an asset id). Ordered by pack (resolution order), then name.
function IconVaultLogic.list(filter: Filter?): { string }
	local options: Filter = filter or {}
	local tag = if options.tag then string.lower(options.tag) else nil
	local ids: { string } = {}
	for _, name in IconVaultLogic.packs() do
		if options.pack == nil or options.pack == name then
			local state = packs[name]
			for _, entry in state.entries do
				local matches = options.category == nil or entry.category == options.category
				if matches and tag ~= nil then
					matches = table.find(entry.tags, tag) ~= nil
				end
				if matches and options.mapped ~= nil then
					matches = showable(state, entry) == options.mapped
				end
				if matches then
					table.insert(ids, entry.id)
				end
			end
		end
	end
	return ids
end

local function score(entry: Entry, query: string): number
	local name = entry.name
	if name == query then
		return 100
	end
	if string.sub(name, 1, #query) == query then
		return 60
	end
	for token in string.gmatch(name, "[^%-]+") do
		if token == query then
			return 50
		end
	end
	if string.find(name, query, 1, true) then
		return 40
	end
	local best = 0
	for _, tag in entry.tags do
		if tag == query then
			best = math.max(best, 30)
		elseif string.sub(tag, 1, #query) == query then
			best = math.max(best, 20)
		end
	end
	if best == 0 and string.find(entry.category, query, 1, true) then
		best = 10
	end
	return best
end

-- Ranked search: exact name, name prefix, whole word in the name, substring, tag, tag prefix,
-- category. "pack:query" searches one pack. Ties go to the default pack, then alphabetically.
function IconVaultLogic.search(query: string, limit: number?): { string }
	if type(query) ~= "string" then
		return {}
	end
	local packName, wanted = IconVaultLogic.split(query)
	wanted = string.gsub(wanted, "^%-+", "")
	wanted = string.gsub(wanted, "%-+$", "")
	if wanted == "" then
		return {}
	end
	type Scored = { id: string, score: number, rank: number }
	local scored: { Scored } = {}
	for rank, name in IconVaultLogic.packs() do
		if packName == nil or packName == name then
			for _, entry in packs[name].entries do
				local value = score(entry, wanted)
				if value > 0 then
					table.insert(scored, { id = entry.id, score = value, rank = rank })
				end
			end
		end
	end
	table.sort(scored, function(a: Scored, b: Scored): boolean
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.id < b.id
	end)
	local results: { string } = {}
	for index, item in scored do
		if limit and index > limit then
			break
		end
		table.insert(results, item.id)
	end
	return results
end

-- Qualified ids whose name starts with the prefix ("sw", or "mypack:sw" for one pack), for editor
-- and tool completion. An empty prefix lists from the start. Default limit 20.
function IconVaultLogic.autocomplete(prefix: string, limit: number?): { string }
	local packName, wanted = IconVaultLogic.split(if type(prefix) == "string" then prefix else "")
	local max = limit or 20
	local results: { string } = {}
	for _, name in IconVaultLogic.packs() do
		if packName == nil or packName == name then
			for _, entry in packs[name].entries do
				if string.sub(entry.name, 1, #wanted) == wanted then
					if #results >= max then
						return results
					end
					table.insert(results, entry.id)
				end
			end
		end
	end
	return results
end

-- Grid maths for the icon picker (virtualised: only visible cells exist) ---------------------------

-- Columns and total height for `count` square cells of `cell` pixels in `width` pixels.
function IconVaultLogic.gridLayout(count: number, width: number, cell: number, gap: number?): GridLayout
	local size = math.max(1, cell)
	local space = math.max(0, gap or 0)
	local columns = math.max(1, math.floor((math.max(0, width) + space) / (size + space)))
	local total = math.max(0, math.floor(count))
	local rows = math.ceil(total / columns)
	local height = if rows > 0 then rows * size + (rows - 1) * space else 0
	return { columns = columns, rows = rows, cell = size, gap = space, height = height, count = total }
end

-- First and last item index (1-based, inclusive) to keep alive for a scroll offset and viewport
-- height, with `overscan` extra rows on each side. Returns 1, 0 when nothing is visible.
function IconVaultLogic.visibleRange(
	layout: GridLayout,
	scroll: number,
	viewHeight: number,
	overscan: number?
): (number, number)
	if layout.count == 0 or viewHeight <= 0 then
		return 1, 0
	end
	local pitch = layout.cell + layout.gap
	local extra = math.max(0, overscan or 1)
	local firstRow = math.max(0, math.floor(math.max(0, scroll) / pitch) - extra)
	local lastRow = math.min(layout.rows - 1, math.floor((math.max(0, scroll) + viewHeight) / pitch) + extra)
	if firstRow > lastRow then
		return 1, 0
	end
	return firstRow * layout.columns + 1, math.min(layout.count, (lastRow + 1) * layout.columns)
end

-- Top-left pixel offset of item `index` (1-based) inside the grid.
function IconVaultLogic.cellPosition(layout: GridLayout, index: number): (number, number)
	local zero = math.max(0, index - 1)
	local column = zero % layout.columns
	local row = math.floor(zero / layout.columns)
	local pitch = layout.cell + layout.gap
	return column * pitch, row * pitch
end

return IconVaultLogic
