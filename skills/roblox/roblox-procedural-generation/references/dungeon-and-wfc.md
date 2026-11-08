# Dungeon generation and a small WFC

Both modules are pure Luau (no Roblox services), so they run under Lune for tests and in Roblox unchanged.

## Room-and-corridor grid

```lua
--!strict
-- ReplicatedStorage/Shared/Dungeon.luau
export type Cell = "wall" | "room" | "corridor"
export type Room = { x: number, y: number, w: number, h: number }
export type Dungeon = { width: number, height: number, cells: { { Cell } }, rooms: { Room } }

local Dungeon = {}

local function overlaps(a: Room, b: Room, pad: number): boolean
	return a.x - pad < b.x + b.w and a.x + a.w + pad > b.x and a.y - pad < b.y + b.h and a.y + a.h + pad > b.y
end

local function carve(d: Dungeon, x: number, y: number, kind: Cell)
	if d.cells[y][x] == "wall" then
		d.cells[y][x] = kind
	end
end

function Dungeon.generate(seed: number, width: number, height: number, attempts: number): Dungeon
	local rng = Random.new(seed)
	local cells: { { Cell } } = {}
	for y = 1, height do
		cells[y] = table.create(width, "wall" :: Cell)
	end
	local d: Dungeon = { width = width, height = height, cells = cells, rooms = {} }

	for _ = 1, attempts do
		local w, h = rng:NextInteger(3, 7), rng:NextInteger(3, 7)
		local room: Room = { x = rng:NextInteger(2, width - w - 1), y = rng:NextInteger(2, height - h - 1), w = w, h = h }
		local ok = true
		for _, other in d.rooms do
			if overlaps(room, other, 1) then
				ok = false
				break
			end
		end
		if ok then
			for yy = room.y, room.y + h - 1 do
				for xx = room.x, room.x + w - 1 do
					d.cells[yy][xx] = "room"
				end
			end
			-- Connect to the previous room with an L-shaped corridor: guarantees connectivity.
			local prev = d.rooms[#d.rooms]
			if prev then
				local ax, ay = prev.x + prev.w // 2, prev.y + prev.h // 2
				local bx, by = room.x + room.w // 2, room.y + room.h // 2
				local horizontalFirst = rng:NextNumber() < 0.5
				local cornerX, cornerY = if horizontalFirst then bx else ax, if horizontalFirst then ay else by
				for xx = math.min(ax, bx), math.max(ax, bx) do
					carve(d, xx, cornerY, "corridor")
				end
				for yy = math.min(ay, by), math.max(ay, by) do
					carve(d, cornerX, yy, "corridor")
				end
			end
			table.insert(d.rooms, room)
		end
	end
	return d
end

-- Flood fill from the first room; true when every open cell is reachable.
function Dungeon.isConnected(d: Dungeon): boolean
	local start = d.rooms[1]
	if not start then
		return false
	end
	local seen: { [number]: boolean } = {}
	local stack = { { start.x, start.y } }
	local reached = 0
	while #stack > 0 do
		local p = table.remove(stack) :: { number }
		local x, y = p[1], p[2]
		local key = y * d.width + x
		if x >= 1 and y >= 1 and x <= d.width and y <= d.height and not seen[key] and d.cells[y][x] ~= "wall" then
			seen[key] = true
			reached += 1
			table.insert(stack, { x + 1, y })
			table.insert(stack, { x - 1, y })
			table.insert(stack, { x, y + 1 })
			table.insert(stack, { x, y - 1 })
		end
	end
	local open = 0
	for y = 1, d.height do
		for x = 1, d.width do
			if d.cells[y][x] ~= "wall" then
				open += 1
			end
		end
	end
	return reached == open
end

return Dungeon
```

Instancing (server only): for each `room` or `corridor` cell, clone a floor tile prefab from `ServerStorage.DungeonTiles` at `Vector3.new(x * TILE, 0, y * TILE)`; for walls adjacent to open cells, clone a wall prefab. Yield with a frame budget every few hundred clones.

## Wave-function-collapse lite

Tiles declare which neighbours they accept on each side. The grid starts with every tile possible everywhere; repeatedly collapse the cell with the fewest options (ties broken by the seeded RNG), then propagate constraints. On contradiction, restart with `seed + 1` up to a few times. No backtracking.

```lua
--!strict
-- ReplicatedStorage/Shared/Wfc.luau
export type Rules = { [string]: { n: { string }, e: { string }, s: { string }, w: { string } } }

local Wfc = {}
local DIRS = { { 0, -1, "n", "s" }, { 1, 0, "e", "w" }, { 0, 1, "s", "n" }, { -1, 0, "w", "e" } }

local function allows(rules: Rules, a: string, side: string, b: string): boolean
	local list = (rules[a] :: any)[side] :: { string }
	return table.find(list, b) ~= nil
end

local function attempt(rules: Rules, names: { string }, w: number, h: number, rng: Random): { { string } }?
	local options: { { { string } } } = {}
	for y = 1, h do
		options[y] = {}
		for x = 1, w do
			options[y][x] = table.clone(names)
		end
	end
	for _ = 1, w * h do
		-- Find the lowest-entropy uncollapsed cell.
		local best, bx, by = math.huge, 0, 0
		for y = 1, h do
			for x = 1, w do
				local n = #options[y][x]
				if n == 0 then
					return nil
				end
				if n > 1 and n < best then
					best, bx, by = n, x, y
				end
			end
		end
		if bx == 0 then
			break -- everything collapsed
		end
		local cell = options[by][bx]
		options[by][bx] = { cell[rng:NextInteger(1, #cell)] }
		-- Propagate.
		local queue = { { bx, by } }
		while #queue > 0 do
			local p = table.remove(queue, 1) :: { number }
			for _, d in DIRS do
				local nx, ny = p[1] + (d[1] :: number), p[2] + (d[2] :: number)
				if nx >= 1 and ny >= 1 and nx <= w and ny <= h then
					local kept = {}
					for _, candidate in options[ny][nx] do
						for _, source in options[p[2]][p[1]] do
							if allows(rules, source, d[3] :: string, candidate) and allows(rules, candidate, d[4] :: string, source) then
								table.insert(kept, candidate)
								break
							end
						end
					end
					if #kept < #options[ny][nx] then
						options[ny][nx] = kept
						table.insert(queue, { nx, ny })
					end
				end
			end
		end
	end
	local out: { { string } } = {}
	for y = 1, h do
		out[y] = {}
		for x = 1, w do
			out[y][x] = options[y][x][1]
		end
	end
	return out
end

function Wfc.solve(rules: Rules, w: number, h: number, seed: number, retries: number): { { string } }?
	local names = {}
	for name in rules do
		table.insert(names, name)
	end
	table.sort(names) -- dictionary order is not stable; sort for determinism
	for i = 0, retries do
		local result = attempt(rules, names, w, h, Random.new(seed + i))
		if result then
			return result
		end
	end
	return nil
end

return Wfc
```

Keep grids small (for example 12 x 12) per call: the propagation is O(cells x tiles^2) per step. For larger maps, solve chunk by chunk with the shared border fixed.
