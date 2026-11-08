--!strict
-- Grid building rules. Pure Luau, in plot-local 2D coordinates: x and z run from 0 to the plot's
-- width and depth. Items are rectangles (catalog size in studs) rotated in steps; collisions use the
-- axis-aligned box around the rotated rectangle, and touching edges do not count as overlapping.

local PlacementConfig = require("./PlacementConfig")

export type Size = { x: number, z: number }
export type CatalogEntry = { size: Size, maxCount: number? }
export type Catalog = { [string]: CatalogEntry }
export type Plot = { width: number, depth: number }
export type Config = { gridSize: number, rotationSteps: number, maxItems: number }
export type Box = { minX: number, minZ: number, maxX: number, maxZ: number }
export type Placed = { id: string, itemId: string, x: number, z: number, rotation: number }
export type Request = { itemId: string, x: number, z: number, rotation: number }
export type Layout = { items: { [string]: Placed }, nextId: number }

local EPSILON = 1e-6
local SAVE_VERSION = 1

local Placement = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Placement.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local grid = source.gridSize
	local steps = source.rotationSteps
	local maxItems = source.maxItems
	local validSteps = isFinite(steps) and steps >= 1 and steps % 1 == 0
	return {
		gridSize = if isFinite(grid) and grid > 0 then grid else PlacementConfig.gridSize,
		rotationSteps = if validSteps then steps else PlacementConfig.rotationSteps,
		maxItems = if isFinite(maxItems) and maxItems >= 0 then math.floor(maxItems) else PlacementConfig.maxItems,
	}
end

function Placement.newLayout(): Layout
	return { items = {}, nextId = 1 }
end

function Placement.snap(value: number, grid: number): number
	return math.floor(value / grid + 0.5) * grid
end

function Placement.normalizeRotation(step: number, steps: number): number
	return step % steps
end

function Placement.rotationDegrees(step: number, steps: number): number
	return Placement.normalizeRotation(step, steps) * 360 / steps
end

-- Size of the axis-aligned box around a rectangle rotated by `step`.
function Placement.rotatedSize(size: Size, step: number, steps: number): Size
	local radians = math.rad(Placement.rotationDegrees(step, steps))
	local cos, sin = math.abs(math.cos(radians)), math.abs(math.sin(radians))
	-- Round away floating-point noise so 90 degree turns swap sizes exactly.
	local x = math.floor((size.x * cos + size.z * sin) * 1e6 + 0.5) / 1e6
	local z = math.floor((size.x * sin + size.z * cos) * 1e6 + 0.5) / 1e6
	return { x = x, z = z }
end

-- Snaps a centre so the item's box edges land on grid lines.
function Placement.snapPosition(x: number, z: number, size: Size, step: number, config: Config): (number, number)
	local box = Placement.rotatedSize(size, step, config.rotationSteps)
	local grid = config.gridSize
	local snappedX = Placement.snap(x - box.x / 2, grid) + box.x / 2
	local snappedZ = Placement.snap(z - box.z / 2, grid) + box.z / 2
	return snappedX, snappedZ
end

function Placement.footprint(x: number, z: number, size: Size, step: number, steps: number): Box
	local box = Placement.rotatedSize(size, step, steps)
	return { minX = x - box.x / 2, minZ = z - box.z / 2, maxX = x + box.x / 2, maxZ = z + box.z / 2 }
end

-- True when the boxes share area. Boxes that only touch along an edge do not overlap.
function Placement.overlaps(a: Box, b: Box): boolean
	local acrossX = a.minX < b.maxX - EPSILON and b.minX < a.maxX - EPSILON
	local acrossZ = a.minZ < b.maxZ - EPSILON and b.minZ < a.maxZ - EPSILON
	return acrossX and acrossZ
end

function Placement.insidePlot(box: Box, plot: Plot): boolean
	local insideX = box.minX >= -EPSILON and box.maxX <= plot.width + EPSILON
	local insideZ = box.minZ >= -EPSILON and box.maxZ <= plot.depth + EPSILON
	return insideX and insideZ
end

local function countOf(layout: Layout, itemId: string?, ignoreId: string?): number
	local count = 0
	for id, placed in layout.items do
		if id ~= ignoreId and (itemId == nil or placed.itemId == itemId) then
			count += 1
		end
	end
	return count
end

function Placement.count(layout: Layout, itemId: string?): number
	return countOf(layout, itemId, nil)
end

-- Checks an untrusted placement request. `ignoreId` skips one placed item (the one being moved).
-- Reasons: "invalid request", "unknown item", "not on grid", "out of bounds", "overlap", "limit reached".
function Placement.validate(
	layout: Layout,
	request: any,
	catalog: Catalog,
	plot: Plot,
	config: Config,
	ignoreId: string?
): (boolean, string?)
	if type(request) ~= "table" or type(request.itemId) ~= "string" then
		return false, "invalid request"
	end
	if not isFinite(request.x) or not isFinite(request.z) or not isFinite(request.rotation) then
		return false, "invalid request"
	end
	if request.rotation % 1 ~= 0 then
		return false, "invalid request"
	end
	local entry = catalog[request.itemId]
	if entry == nil then
		return false, "unknown item"
	end
	local snappedX, snappedZ = Placement.snapPosition(request.x, request.z, entry.size, request.rotation, config)
	if math.abs(snappedX - request.x) > EPSILON or math.abs(snappedZ - request.z) > EPSILON then
		return false, "not on grid"
	end
	local box = Placement.footprint(request.x, request.z, entry.size, request.rotation, config.rotationSteps)
	if not Placement.insidePlot(box, plot) then
		return false, "out of bounds"
	end
	for id, placed in layout.items do
		local other = catalog[placed.itemId]
		if id ~= ignoreId and other then
			local otherBox = Placement.footprint(placed.x, placed.z, other.size, placed.rotation, config.rotationSteps)
			if Placement.overlaps(box, otherBox) then
				return false, "overlap"
			end
		end
	end
	local moving = if ignoreId then layout.items[ignoreId] else nil
	local sameItem = moving ~= nil and moving.itemId == request.itemId
	if not sameItem then
		if countOf(layout, nil, ignoreId) >= config.maxItems then
			return false, "limit reached"
		end
		local maxCount = entry.maxCount
		if maxCount and countOf(layout, request.itemId, ignoreId) >= maxCount then
			return false, "limit reached"
		end
	end
	return true, nil
end

-- Validates and places an item. Returns ok, a reason when refused, and the new item's id.
function Placement.place(
	layout: Layout,
	request: any,
	catalog: Catalog,
	plot: Plot,
	config: Config
): (boolean, string?, string?)
	local ok, reason = Placement.validate(layout, request, catalog, plot, config, nil)
	if not ok then
		return false, reason, nil
	end
	local id = tostring(layout.nextId)
	layout.nextId += 1
	layout.items[id] = {
		id = id,
		itemId = request.itemId,
		x = request.x,
		z = request.z,
		rotation = Placement.normalizeRotation(request.rotation, config.rotationSteps),
	}
	return true, nil, id
end

-- Moves or rotates a placed item. The item keeps its id.
function Placement.move(
	layout: Layout,
	id: string,
	x: number,
	z: number,
	rotation: number,
	catalog: Catalog,
	plot: Plot,
	config: Config
): (boolean, string?)
	local placed = layout.items[id]
	if placed == nil then
		return false, "unknown placement"
	end
	local request = { itemId = placed.itemId, x = x, z = z, rotation = rotation }
	local ok, reason = Placement.validate(layout, request, catalog, plot, config, id)
	if not ok then
		return false, reason
	end
	placed.x = x
	placed.z = z
	placed.rotation = Placement.normalizeRotation(rotation, config.rotationSteps)
	return true, nil
end

function Placement.remove(layout: Layout, id: string): Placed?
	local placed = layout.items[id]
	layout.items[id] = nil
	return placed
end

-- Placed items sorted by numeric id, which is placement order.
function Placement.list(layout: Layout): { Placed }
	local list: { Placed } = {}
	for _, placed in layout.items do
		table.insert(list, placed)
	end
	table.sort(list, function(a: Placed, b: Placed): boolean
		local na, nb = tonumber(a.id), tonumber(b.id)
		if na and nb and na ~= nb then
			return na < nb
		end
		return a.id < b.id
	end)
	return list
end

-- Shape: { version = 1, items = { { itemId, x, z, rotation } } } in placement order.
function Placement.serialize(layout: Layout): { [string]: any }
	local items: { any } = {}
	for _, placed in Placement.list(layout) do
		table.insert(items, { itemId = placed.itemId, x = placed.x, z = placed.z, rotation = placed.rotation })
	end
	return { version = SAVE_VERSION, items = items }
end

-- Rebuilds a layout from untrusted data, re-validating every item against the current catalog and plot.
-- Returns the layout and how many saved items were dropped.
function Placement.deserialize(data: any, catalog: Catalog, plot: Plot, config: Config): (Layout, number)
	local layout = Placement.newLayout()
	local dropped = 0
	if type(data) ~= "table" or type(data.items) ~= "table" then
		return layout, 0
	end
	for _, raw in data.items do
		local request: any = nil
		if type(raw) == "table" then
			request = { itemId = raw.itemId, x = raw.x, z = raw.z, rotation = raw.rotation }
		end
		if not Placement.place(layout, request, catalog, plot, config) then
			dropped += 1
		end
	end
	return layout, dropped
end

return Placement
