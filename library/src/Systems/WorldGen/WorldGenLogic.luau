--!strict
-- Deterministic world layout for zone-based games (simulators, tycoon plots, obby stages). Pure Luau:
-- the same seed always gives the same layout, so servers agree and tests can check it. The output is
-- plain data (boxes, points, gates); WorldGenBuilder turns it into Parts, or a map agent can turn it into
-- Blender props.
--
-- Layout: zones in a row (or a grid) along +X with a path between them, a gate at every border, a
-- spawn pad in the first zone, and props scattered inside each zone with a minimum spacing that keeps
-- the path and gate areas clear.

export type Box = { center: { number }, size: { number } } -- { x, y, z }

export type Zone = {
	index: number,
	name: string,
	floor: Box,
	props: { { kind: string, position: { number }, rotation: number, scale: number } },
}

export type Gate = { between: { number }, box: Box }

export type Layout = { seed: number, zones: { Zone }, gates: { Gate }, path: { Box }, spawn: Box }

export type Options = {
	seed: number,
	zones: { string }, -- zone names in order
	zoneSize: number?, -- square zone side in studs (default 160)
	gap: number?, -- space between zones (default 24)
	columns: number?, -- zones per row (default all in one row)
	pathWidth: number?, -- default 14
	props: { { kind: string, weight: number, radius: number? } }?, -- what to scatter
	density: number?, -- props per 1000 studs^2 (default 0.6)
	minSpacing: number?, -- default 10
	maxPropsPerZone: number?, -- default 120
}

local WorldGenLogic = {}

-- Small deterministic generator (mulberry32-style, kept inside 32 bits).
function WorldGenLogic.rng(seed: number): () -> number
	local state = math.floor(seed) % 4294967296
	return function(): number
		state = (state + 0x6D2B79F5) % 4294967296
		local t = state
		t = bit32.bxor(t, bit32.rshift(t, 15))
		t = (t * bit32.bor(t, 1)) % 4294967296
		t = bit32.bxor(t, t + (bit32.bxor(t, bit32.rshift(t, 7)) * bit32.bor(t, 61)) % 4294967296)
		t = bit32.bxor(t, bit32.rshift(t, 14))
		return (t % 4294967296) / 4294967296
	end
end

local function box(x: number, y: number, z: number, sx: number, sy: number, sz: number): Box
	return { center = { x, y, z }, size = { sx, sy, sz } }
end

local function inside(b: Box, x: number, z: number, margin: number): boolean
	return math.abs(x - b.center[1]) <= b.size[1] / 2 - margin and math.abs(z - b.center[3]) <= b.size[3] / 2 - margin
end

local function pickKind(props: { { kind: string, weight: number, radius: number? } }, roll: number): (string, number)
	local total = 0
	for _, p in props do
		total += p.weight
	end
	local target = roll * total
	for _, p in props do
		target -= p.weight
		if target < 0 then
			return p.kind, p.radius or 3
		end
	end
	local last = props[#props]
	return last.kind, last.radius or 3
end

function WorldGenLogic.generate(options: Options): Layout
	assert(type(options.zones) == "table" and #options.zones > 0, "zones required")
	local size = options.zoneSize or 160
	local gap = options.gap or 24
	local columns = options.columns or #options.zones
	local pathWidth = options.pathWidth or 14
	local spacing = options.minSpacing or 10
	local rand = WorldGenLogic.rng(options.seed)
	local zones: { Zone } = {}
	local gates: { Gate } = {}
	local path: { Box } = {}
	for i, name in options.zones do
		local col = (i - 1) % columns
		local row = (i - 1) // columns
		local x = col * (size + gap)
		local z = row * (size + gap)
		local zone: Zone = { index = i, name = name, floor = box(x, -1, z, size, 2, size), props = {} }
		table.insert(zones, zone)
	end
	for i = 2, #zones do
		local a, b = zones[i - 1].floor.center, zones[i].floor.center
		local mx, mz = (a[1] + b[1]) / 2, (a[3] + b[3]) / 2
		local horizontal = a[3] == b[3]
		local length = if horizontal then math.abs(b[1] - a[1]) else math.abs(b[3] - a[3])
		local gateBox = if horizontal
			then box(mx, 6, mz, 4, 12, pathWidth + 6)
			else box(mx, 6, mz, pathWidth + 6, 12, 4)
		table.insert(gates, { between = { i - 1, i }, box = gateBox })
		table.insert(
			path,
			if horizontal then box(mx, -0.9, mz, length, 1, pathWidth) else box(mx, -0.9, mz, pathWidth, 1, length)
		)
	end
	local first = zones[1].floor
	local spawn = box(first.center[1], 0.5, first.center[3], 16, 1, 16)
	local props = options.props or {}
	if #props > 0 then
		local density = options.density or 0.6
		local cap = options.maxPropsPerZone or 120
		for _, zone in zones do
			local wanted = math.min(cap, math.floor(size * size / 1000 * density))
			local placed: { { number } } = {}
			local attempts = 0
			while #zone.props < wanted and attempts < wanted * 30 do
				attempts += 1
				local x = zone.floor.center[1] + (rand() - 0.5) * size
				local z = zone.floor.center[3] + (rand() - 0.5) * size
				local kind, radius = pickKind(props, rand())
				local ok = inside(zone.floor, x, z, radius + 2)
				-- Keep spawn, path strips and gates clear.
				if ok and zone.index == 1 and inside(box(spawn.center[1], 0, spawn.center[3], 40, 1, 40), x, z, 0) then
					ok = false
				end
				for _, strip in path do
					if
						ok
						and inside(
							box(
								strip.center[1],
								0,
								strip.center[3],
								strip.size[1] + 2 * radius,
								1,
								strip.size[3] + 2 * radius
							),
							x,
							z,
							0
						)
					then
						ok = false
					end
				end
				local through = zone.floor.center
				if ok and math.abs(z - through[3]) < pathWidth / 2 + radius then
					ok = false -- the path continues through the middle of each zone
				end
				for _, other in placed do
					if ok and (other[1] - x) ^ 2 + (other[2] - z) ^ 2 < (math.max(spacing, other[3] + radius)) ^ 2 then
						ok = false
					end
				end
				if ok then
					table.insert(placed, { x, z, radius })
					table.insert(zone.props, {
						kind = kind,
						position = { x, 0, z },
						rotation = math.floor(rand() * 360),
						scale = 0.85 + rand() * 0.3,
					})
				end
			end
		end
	end
	return { seed = options.seed, zones = zones, gates = gates, path = path, spawn = spawn }
end

-- Smallest distance between any two props in a zone (math.huge with fewer than two), for tests.
function WorldGenLogic.minDistance(zone: Zone): number
	local best = math.huge
	for i = 1, #zone.props do
		for j = i + 1, #zone.props do
			local a, b = zone.props[i].position, zone.props[j].position
			best = math.min(best, math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2))
		end
	end
	return best
end

return WorldGenLogic
