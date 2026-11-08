--!strict
-- Spatial navigation graph for gamepad and keyboard focus. Given the on-screen rectangles of
-- selectable elements, picks the best neighbour in each direction. Runtime/Focus writes the
-- result into GuiObject.NextSelectionUp/Down/Left/Right. Pure Luau and deterministic.
--
-- Scoring for a move from A to B in direction d:
--   * B's centre must lie strictly in direction d from A's centre;
--   * primary = gap along d between the facing edges (0 when they overlap);
--   * secondary = gap across d between the two boxes (0 when their spans overlap);
--   * score = primary + secondary * crossWeight, plus a small centre-distance tie breaker.
-- Lowest score wins; equal scores are broken by node order, so results never depend on hashing.

export type Node = { id: string, x: number, y: number, w: number, h: number }
export type Links = { up: string?, down: string?, left: string?, right: string? }
export type Graph = { [string]: Links }

export type Options = {
	crossWeight: number?, -- how much sideways distance costs compared with forward distance (default 2)
	wrap: boolean?, -- when nothing is found, wrap to the far side on the same row or column
	maxCross: number?, -- ignore candidates further than this sideways (default unlimited)
}

local SpatialNav = {}

SpatialNav.DIRECTIONS = { "up", "down", "left", "right" }

local VECTORS: { [string]: { x: number, y: number } } = {
	up = { x = 0, y = -1 },
	down = { x = 0, y = 1 },
	left = { x = -1, y = 0 },
	right = { x = 1, y = 0 },
}

local EPSILON = 1e-6

local function centre(node: Node): (number, number)
	return node.x + node.w / 2, node.y + node.h / 2
end

-- Gap between the spans [a1, a2] and [b1, b2]; 0 when they overlap.
local function spanGap(a1: number, a2: number, b1: number, b2: number): number
	if b1 > a2 then
		return b1 - a2
	elseif a1 > b2 then
		return a1 - b2
	end
	return 0
end

local function measure(from: Node, to: Node, direction: string): (number, number)
	local primary: number
	local secondary: number
	if direction == "right" then
		primary = math.max(0, to.x - (from.x + from.w))
		secondary = spanGap(from.y, from.y + from.h, to.y, to.y + to.h)
	elseif direction == "left" then
		primary = math.max(0, from.x - (to.x + to.w))
		secondary = spanGap(from.y, from.y + from.h, to.y, to.y + to.h)
	elseif direction == "down" then
		primary = math.max(0, to.y - (from.y + from.h))
		secondary = spanGap(from.x, from.x + from.w, to.x, to.x + to.w)
	else
		primary = math.max(0, from.y - (to.y + to.h))
		secondary = spanGap(from.x, from.x + from.w, to.x, to.x + to.w)
	end
	return primary, secondary
end

local function isAhead(from: Node, to: Node, direction: string): boolean
	local vector = VECTORS[direction]
	local fx, fy = centre(from)
	local tx, ty = centre(to)
	return (tx - fx) * vector.x + (ty - fy) * vector.y > EPSILON
end

-- Best neighbour of `from` in `direction` among `nodes`, or nil.
function SpatialNav.neighbour(nodes: { Node }, from: Node, direction: string, options: Options?): string?
	assert(VECTORS[direction] ~= nil, "direction must be up, down, left or right")
	local opts: Options = options or {}
	local crossWeight = opts.crossWeight or 2
	local maxCross = opts.maxCross or math.huge
	local bestId: string? = nil
	local bestScore = math.huge
	local fx, fy = centre(from)
	for _, node in nodes do
		if node.id ~= from.id and isAhead(from, node, direction) then
			local primary, secondary = measure(from, node, direction)
			if secondary <= maxCross then
				local tx, ty = centre(node)
				local distance = math.sqrt((tx - fx) ^ 2 + (ty - fy) ^ 2)
				local score = primary + secondary * crossWeight + distance * 0.001
				if score < bestScore - EPSILON then
					bestScore = score
					bestId = node.id
				end
			end
		end
	end
	return bestId
end

-- The node furthest in the opposite direction that shares a row or column with `from`.
local function wrapTarget(nodes: { Node }, from: Node, direction: string): string?
	local vector = VECTORS[direction]
	local bestId: string? = nil
	local bestValue = math.huge
	local fx, fy = centre(from)
	for _, node in nodes do
		if node.id ~= from.id then
			local aligned: boolean
			if vector.x ~= 0 then
				aligned = spanGap(from.y, from.y + from.h, node.y, node.y + node.h) == 0
			else
				aligned = spanGap(from.x, from.x + from.w, node.x, node.x + node.w) == 0
			end
			if aligned then
				local tx, ty = centre(node)
				-- Smaller is further "behind" us along the direction of travel.
				local value = (tx - fx) * vector.x + (ty - fy) * vector.y
				if value < bestValue - EPSILON then
					bestValue = value
					bestId = node.id
				end
			end
		end
	end
	if bestValue >= 0 then
		return nil
	end
	return bestId
end

-- Builds links for every node. Duplicate ids raise an error.
function SpatialNav.build(nodes: { Node }, options: Options?): Graph
	local graph: Graph = {}
	local seen: { [string]: boolean } = {}
	for _, node in nodes do
		assert(not seen[node.id], "duplicate node id " .. node.id)
		seen[node.id] = true
	end
	local wrap = options ~= nil and options.wrap == true
	for _, node in nodes do
		local links: Links = {}
		for _, direction in SpatialNav.DIRECTIONS do
			local target = SpatialNav.neighbour(nodes, node, direction, options)
			if target == nil and wrap then
				target = wrapTarget(nodes, node, direction)
			end
			if direction == "up" then
				links.up = target
			elseif direction == "down" then
				links.down = target
			elseif direction == "left" then
				links.left = target
			else
				links.right = target
			end
		end
		graph[node.id] = links
	end
	return graph
end

function SpatialNav.move(graph: Graph, fromId: string, direction: string): string?
	local links = graph[fromId]
	if links == nil then
		return nil
	end
	if direction == "up" then
		return links.up
	elseif direction == "down" then
		return links.down
	elseif direction == "left" then
		return links.left
	elseif direction == "right" then
		return links.right
	end
	return nil
end

-- The natural first focus: the top-most node, then the left-most. nil for an empty list.
function SpatialNav.first(nodes: { Node }): string?
	local best: Node? = nil
	for _, node in nodes do
		if best == nil then
			best = node
		else
			local current: Node = best
			if node.y < current.y - EPSILON or (math.abs(node.y - current.y) <= EPSILON and node.x < current.x) then
				best = node
			end
		end
	end
	return if best then best.id else nil
end

return SpatialNav
