--!strict
-- Region detection. Pure Luau: plain numbers instead of Vector3 and CFrame, and no clock.
-- Shapes: an oriented box (center, half-size, yaw about +Y), a sphere and a polygon prism
-- (an XZ polygon between two heights). Each update diffs which zones every tracked key
-- (usually a Player) is in and returns enter, leave and primary-zone changes.
-- Hysteresis: a key inside a zone only leaves once it is `hysteresis` studs outside it,
-- and optionally `leaveDelay` seconds after it was last inside.

export type Vec3 = { x: number, y: number, z: number }
export type Point2 = { x: number, z: number }

export type Box = { kind: "box", center: Vec3, halfSize: Vec3, yaw: number }
export type Sphere = { kind: "sphere", center: Vec3, radius: number }
export type Prism = { kind: "prism", points: { Point2 }, minY: number, maxY: number }
export type Shape = Box | Sphere | Prism

export type ZoneOptions = {
	priority: number?, -- higher wins when zones overlap (default 0)
	hysteresis: number?, -- studs outside the shape before leaving (default the state's)
	data: any?, -- anything the caller wants back, such as the source part
}

export type Zone = { id: string, shape: Shape, priority: number, hysteresis: number, data: any? }

export type Config = {
	exclusive: boolean?, -- a key is in at most one zone, the top-priority one (default false)
	hysteresis: number?, -- default hysteresis for new zones, in studs (default 0)
	leaveDelay: number?, -- seconds a key stays in a zone after it was last inside (default 0)
}

export type Settings = { exclusive: boolean, hysteresis: number, leaveDelay: number }

export type IdSet = { [string]: boolean }

export type Membership = { since: number, lastInside: number }
export type Record = { zones: { [string]: Membership }, primary: string? }

export type ChangeKind = "enter" | "leave" | "primary"

export type Change = {
	kind: ChangeKind,
	key: any,
	zoneId: string?, -- the zone entered or left, or the new primary zone (nil when none)
	previous: string?, -- for "primary": the previous primary zone
}

export type State = {
	settings: Settings,
	zones: { [string]: Zone },
	order: { Zone }, -- zones sorted by priority (high first), then id
	records: { [any]: Record },
}

local ZonesLogic = {}

local EPSILON = 1e-9

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isVec3(value: any): boolean
	return type(value) == "table" and isFinite(value.x) and isFinite(value.y) and isFinite(value.z)
end

function ZonesLogic.vec3(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

function ZonesLogic.box(center: Vec3, halfSize: Vec3, yaw: number?): Box
	assert(isVec3(center), "box center must be a finite Vec3")
	assert(isVec3(halfSize), "box halfSize must be a finite Vec3")
	assert(halfSize.x > 0 and halfSize.y > 0 and halfSize.z > 0, "box halfSize must be positive")
	local angle = yaw or 0
	assert(isFinite(angle), "box yaw must be finite")
	local shape: Box = { kind = "box", center = center, halfSize = halfSize, yaw = angle }
	return shape
end

function ZonesLogic.sphere(center: Vec3, radius: number): Sphere
	assert(isVec3(center), "sphere center must be a finite Vec3")
	assert(isFinite(radius) and radius > 0, "sphere radius must be positive")
	local shape: Sphere = { kind = "sphere", center = center, radius = radius }
	return shape
end

-- Twice the signed area of an XZ polygon (shoelace formula).
local function doubleArea(points: { Point2 }): number
	local total = 0
	local count = #points
	for index = 1, count do
		local a = points[index]
		local b = points[index % count + 1]
		total += a.x * b.z - b.x * a.z
	end
	return total
end

function ZonesLogic.prism(points: { Point2 }, minY: number, maxY: number): Prism
	assert(type(points) == "table" and #points >= 3, "a prism needs at least 3 points")
	local copy: { Point2 } = {}
	for index, point in points do
		assert(type(point) == "table" and isFinite(point.x) and isFinite(point.z), "invalid point " .. index)
		copy[index] = { x = point.x, z = point.z }
	end
	assert(#copy == #points, "prism points must be an array")
	assert(math.abs(doubleArea(copy)) > EPSILON, "prism polygon has no area")
	assert(isFinite(minY) and isFinite(maxY) and maxY > minY, "prism needs minY < maxY")
	local shape: Prism = { kind = "prism", points = copy, minY = minY, maxY = maxY }
	return shape
end

-- Even-odd ray cast in the XZ plane.
local function insidePolygon(points: { Point2 }, x: number, z: number): boolean
	local inside = false
	local count = #points
	local j = count
	for i = 1, count do
		local a = points[i]
		local b = points[j]
		local aAbove = a.z > z
		local bAbove = b.z > z
		if aAbove ~= bAbove then
			local crossX = a.x + (z - a.z) * (b.x - a.x) / (b.z - a.z)
			if x < crossX then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

local function segmentDistance(a: Point2, b: Point2, x: number, z: number): number
	local dx = b.x - a.x
	local dz = b.z - a.z
	local lengthSquared = dx * dx + dz * dz
	local t = 0
	if lengthSquared > 0 then
		t = math.clamp(((x - a.x) * dx + (z - a.z) * dz) / lengthSquared, 0, 1)
	end
	local px = a.x + t * dx - x
	local pz = a.z + t * dz - z
	return math.sqrt(px * px + pz * pz)
end

local function edgeDistance(points: { Point2 }, x: number, z: number): number
	local best = math.huge
	local count = #points
	for index = 1, count do
		local distance = segmentDistance(points[index], points[index % count + 1], x, z)
		if distance < best then
			best = distance
		end
	end
	return best
end

-- Converts a world point into the box's local frame. Yaw follows CFrame.Angles(0, yaw, 0).
function ZonesLogic.toLocal(box: Box, point: Vec3): Vec3
	local dx = point.x - box.center.x
	local dz = point.z - box.center.z
	local c = math.cos(box.yaw)
	local s = math.sin(box.yaw)
	return { x = c * dx - s * dz, y = point.y - box.center.y, z = s * dx + c * dz }
end

-- Whether `point` is inside `shape` grown by `margin` studs (a negative margin shrinks it).
function ZonesLogic.contains(shape: Shape, point: Vec3, margin: number?): boolean
	local m = margin or 0
	if shape.kind == "box" then
		local box = shape :: Box
		local h = box.halfSize
		local p = ZonesLogic.toLocal(box, point)
		return math.abs(p.x) <= h.x + m and math.abs(p.y) <= h.y + m and math.abs(p.z) <= h.z + m
	elseif shape.kind == "sphere" then
		local sphere = shape :: Sphere
		local r = sphere.radius + m
		if r < 0 then
			return false
		end
		local dx = point.x - sphere.center.x
		local dy = point.y - sphere.center.y
		local dz = point.z - sphere.center.z
		return dx * dx + dy * dy + dz * dz <= r * r
	end
	local prism = shape :: Prism
	if point.y < prism.minY - m or point.y > prism.maxY + m then
		return false
	end
	local inside = insidePolygon(prism.points, point.x, point.z)
	if m == 0 then
		return inside
	end
	local distance = edgeDistance(prism.points, point.x, point.z)
	if m > 0 then
		return inside or distance <= m
	end
	return inside and distance >= -m
end

-- World-space bounds of a shape grown by `margin`, as min and max corners.
function ZonesLogic.bounds(shape: Shape, margin: number?): (Vec3, Vec3)
	local m = margin or 0
	if shape.kind == "box" then
		local box = shape :: Box
		local h = box.halfSize
		local c = math.abs(math.cos(box.yaw))
		local s = math.abs(math.sin(box.yaw))
		local ex = c * h.x + s * h.z + m
		local ez = s * h.x + c * h.z + m
		local ey = h.y + m
		local o = box.center
		return { x = o.x - ex, y = o.y - ey, z = o.z - ez }, { x = o.x + ex, y = o.y + ey, z = o.z + ez }
	elseif shape.kind == "sphere" then
		local sphere = shape :: Sphere
		local r = sphere.radius + m
		local o = sphere.center
		return { x = o.x - r, y = o.y - r, z = o.z - r }, { x = o.x + r, y = o.y + r, z = o.z + r }
	end
	local prism = shape :: Prism
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, point in prism.points do
		minX = math.min(minX, point.x)
		maxX = math.max(maxX, point.x)
		minZ = math.min(minZ, point.z)
		maxZ = math.max(maxZ, point.z)
	end
	local low = { x = minX - m, y = prism.minY - m, z = minZ - m }
	return low, { x = maxX + m, y = prism.maxY + m, z = maxZ + m }
end

function ZonesLogic.new(config: Config?): State
	local cfg: Config = config or {}
	local hysteresis = cfg.hysteresis or 0
	local leaveDelay = cfg.leaveDelay or 0
	assert(isFinite(hysteresis) and hysteresis >= 0, "hysteresis must be a number >= 0")
	assert(isFinite(leaveDelay) and leaveDelay >= 0, "leaveDelay must be a number >= 0")
	return {
		settings = { exclusive = cfg.exclusive == true, hysteresis = hysteresis, leaveDelay = leaveDelay },
		zones = {},
		order = {},
		records = {},
	}
end

local function sortOrder(state: State)
	local order: { Zone } = {}
	for _, zone in state.zones do
		table.insert(order, zone)
	end
	table.sort(order, function(a: Zone, b: Zone): boolean
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.id < b.id
	end)
	state.order = order
end

function ZonesLogic.addZone(state: State, id: string, shape: Shape, options: ZoneOptions?): Zone
	assert(type(id) == "string" and #id > 0, "zone id must be a non-empty string")
	assert(state.zones[id] == nil, "duplicate zone id " .. id)
	assert(type(shape) == "table" and type(shape.kind) == "string", "invalid shape")
	local opts: ZoneOptions = options or {}
	local priority = opts.priority or 0
	local hysteresis = opts.hysteresis or state.settings.hysteresis
	assert(isFinite(priority), "priority must be finite")
	assert(isFinite(hysteresis) and hysteresis >= 0, "hysteresis must be a number >= 0")
	local zone: Zone = { id = id, shape = shape, priority = priority, hysteresis = hysteresis, data = opts.data }
	state.zones[id] = zone
	sortOrder(state)
	return zone
end

function ZonesLogic.getZone(state: State, id: string): Zone?
	return state.zones[id]
end

local function topOf(state: State, set: { [string]: any }): string?
	for _, zone in state.order do
		if set[zone.id] ~= nil then
			return zone.id
		end
	end
	return nil
end

local function sortedIds(set: { [string]: any }): { string }
	local ids: { string } = {}
	for id in set do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function push(out: { Change }, kind: ChangeKind, key: any, zoneId: string?, previous: string?)
	local change: Change = { kind = kind, key = key, zoneId = zoneId, previous = previous }
	table.insert(out, change)
end

-- Applies one key's new set of zones and appends the changes (leaves, enters, then primary).
local function apply(state: State, key: any, record: Record, wanted: IdSet, now: number, out: { Change })
	local left: { [string]: boolean } = {}
	for id in record.zones do
		if not wanted[id] then
			left[id] = true
		end
	end
	for _, id in sortedIds(left) do
		record.zones[id] = nil
		push(out, "leave", key, id)
	end
	for _, id in sortedIds(wanted) do
		if record.zones[id] == nil then
			record.zones[id] = { since = now, lastInside = now }
			push(out, "enter", key, id)
		end
	end
	local primary = topOf(state, record.zones)
	if primary ~= record.primary then
		push(out, "primary", key, primary, record.primary)
		record.primary = primary
	end
	if next(record.zones) == nil then
		state.records[key] = nil
	end
end

-- Core update from raw membership: `raw[key]` is the set of zone ids the key is physically in
-- this tick (with hysteresis already applied). Keys missing from `raw` count as in no zone.
function ZonesLogic.updateRaw(state: State, raw: { [any]: { [string]: boolean } }, now: number): { Change }
	assert(isFinite(now), "now must be a finite number")
	local out: { Change } = {}
	local keys: { [any]: boolean } = {}
	for key in raw do
		keys[key] = true
	end
	for key in state.records do
		keys[key] = true
	end
	local delay = state.settings.leaveDelay
	for key in keys do
		local inside = raw[key] or {}
		local existing = state.records[key]
		local record: Record
		if existing == nil then
			record = { zones = {}, primary = nil }
			state.records[key] = record
		else
			record = existing
		end
		local candidates: { [string]: boolean } = {}
		for id in inside do
			if state.zones[id] then
				candidates[id] = true
				local membership = record.zones[id]
				if membership then
					membership.lastInside = now
				end
			end
		end
		for id, membership in record.zones do
			if not candidates[id] and state.zones[id] and delay > 0 and now - membership.lastInside < delay then
				candidates[id] = true
			end
		end
		local wanted = candidates
		if state.settings.exclusive then
			local top = topOf(state, candidates)
			wanted = {}
			if top then
				wanted[top] = true
			end
		end
		apply(state, key, record, wanted, now, out)
	end
	return out
end

-- Which zones contain `point` for `key`, using the larger hysteresis shape for zones it is in.
function ZonesLogic.zonesAt(state: State, point: Vec3, key: any?): { [string]: boolean }
	local record = if key ~= nil then state.records[key] else nil
	local inside: { [string]: boolean } = {}
	for _, zone in state.order do
		local member = record ~= nil and record.zones[zone.id] ~= nil
		local margin = if member then zone.hysteresis else 0
		if ZonesLogic.contains(zone.shape, point, margin) then
			inside[zone.id] = true
		end
	end
	return inside
end

-- Point update: `positions[key]` is the key's position this tick. Keys without a position
-- (no character, or gone) leave their zones, subject to leaveDelay.
function ZonesLogic.update(state: State, positions: { [any]: Vec3 }, now: number): { Change }
	local raw: { [any]: { [string]: boolean } } = {}
	for key, position in positions do
		if isVec3(position) then
			raw[key] = ZonesLogic.zonesAt(state, position, key)
		end
	end
	return ZonesLogic.updateRaw(state, raw, now)
end

-- Removes a zone and returns the leave (and primary) changes for every key in it.
function ZonesLogic.removeZone(state: State, id: string): { Change }
	local out: { Change } = {}
	if state.zones[id] == nil then
		return out
	end
	state.zones[id] = nil
	sortOrder(state)
	for key, record in state.records do
		if record.zones[id] then
			local wanted: { [string]: boolean } = {}
			for other in record.zones do
				if other ~= id then
					wanted[other] = true
				end
			end
			apply(state, key, record, wanted, 0, out)
		end
	end
	return out
end

-- Forgets a key straight away (for example when a player leaves), returning its leave changes.
function ZonesLogic.removeKey(state: State, key: any): { Change }
	local out: { Change } = {}
	local record = state.records[key]
	if record then
		apply(state, key, record, {}, 0, out)
	end
	state.records[key] = nil
	return out
end

function ZonesLogic.zonesOf(state: State, key: any): { string }
	local record = state.records[key]
	if record == nil then
		return {}
	end
	return sortedIds(record.zones)
end

function ZonesLogic.primaryOf(state: State, key: any): string?
	local record = state.records[key]
	return if record then record.primary else nil
end

function ZonesLogic.isIn(state: State, key: any, id: string): boolean
	local record = state.records[key]
	return record ~= nil and record.zones[id] ~= nil
end

function ZonesLogic.keysIn(state: State, id: string): { any }
	local keys: { any } = {}
	for key, record in state.records do
		if record.zones[id] then
			table.insert(keys, key)
		end
	end
	return keys
end

-- The highest-priority zone containing `point`, ignoring hysteresis.
function ZonesLogic.topZoneAt(state: State, point: Vec3): string?
	for _, zone in state.order do
		if ZonesLogic.contains(zone.shape, point, 0) then
			return zone.id
		end
	end
	return nil
end

return ZonesLogic
