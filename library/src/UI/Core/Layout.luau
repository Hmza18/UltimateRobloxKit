--!strict
-- Layout maths for HUD rails, safe areas and popup placement (tooltips, context menus).
-- Pure Luau: rectangles are { x, y, w, h } in pixels, anchors and positions are { x, y } in 0..1.

export type Rect = { x: number, y: number, w: number, h: number }
export type Point = { x: number, y: number }
export type Insets = { top: number, left: number, right: number, bottom: number }

export type RailSpec = {
	anchor: Point, -- AnchorPoint of the rail frame
	position: Point, -- Position scale inside the safe area
	direction: string, -- "horizontal" or "vertical" UIListLayout fill direction
	horizontal: string, -- "left" | "center" | "right" alignment of children
	vertical: string, -- "top" | "center" | "bottom" alignment of children
}

export type PlaceOptions = {
	gap: number?, -- distance between the anchor and the popup
	margin: number?, -- distance kept from the viewport edges
	prefer: string?, -- "below" (default), "above", "right" or "left"
}

local Layout = {}

local function railSpec(ax: number, ay: number, direction: string, horizontal: string, vertical: string): RailSpec
	return {
		anchor = { x = ax, y = ay },
		position = { x = ax, y = ay },
		direction = direction,
		horizontal = horizontal,
		vertical = vertical,
	}
end

local RAILS: { [string]: RailSpec } = {
	topLeft = railSpec(0, 0, "vertical", "left", "top"),
	topCenter = railSpec(0.5, 0, "horizontal", "center", "top"),
	topRight = railSpec(1, 0, "vertical", "right", "top"),
	left = railSpec(0, 0.5, "vertical", "left", "center"),
	center = railSpec(0.5, 0.5, "vertical", "center", "center"),
	right = railSpec(1, 0.5, "vertical", "right", "center"),
	bottomLeft = railSpec(0, 1, "vertical", "left", "bottom"),
	bottomCenter = railSpec(0.5, 1, "horizontal", "center", "bottom"),
	bottomRight = railSpec(1, 1, "vertical", "right", "bottom"),
}

Layout.RAIL_NAMES = {
	"topLeft",
	"topCenter",
	"topRight",
	"left",
	"center",
	"right",
	"bottomLeft",
	"bottomCenter",
	"bottomRight",
}

-- Anchor, position and list alignment for a named HUD rail. Returns nil for unknown names.
function Layout.rail(name: string): RailSpec?
	return RAILS[name]
end

-- The viewport minus device/core UI insets and an extra padding on every side.
function Layout.safeRect(viewport: Point, insets: Insets?, padding: number?): Rect
	local inset: Insets = insets or { top = 0, left = 0, right = 0, bottom = 0 }
	local pad = padding or 0
	local x = inset.left + pad
	local y = inset.top + pad
	local w = math.max(0, viewport.x - inset.left - inset.right - pad * 2)
	local h = math.max(0, viewport.y - inset.top - inset.bottom - pad * 2)
	return { x = x, y = y, w = w, h = h }
end

-- Pixel position of a child of `size` placed on `rail` inside `area` (its top-left corner).
function Layout.railPosition(name: string, area: Rect, size: Point): Point?
	local spec = RAILS[name]
	if spec == nil then
		return nil
	end
	local x = area.x + area.w * spec.position.x - size.x * spec.anchor.x
	local y = area.y + area.h * spec.position.y - size.y * spec.anchor.y
	return { x = x, y = y }
end

-- Keeps a box of `size` at `position` fully inside `bounds` (shrinking the margin if needed).
function Layout.clamp(position: Point, size: Point, bounds: Rect, margin: number?): Point
	local pad = margin or 0
	local minX = bounds.x + pad
	local minY = bounds.y + pad
	local maxX = math.max(minX, bounds.x + bounds.w - size.x - pad)
	local maxY = math.max(minY, bounds.y + bounds.h - size.y - pad)
	return { x = math.clamp(position.x, minX, maxX), y = math.clamp(position.y, minY, maxY) }
end

local function candidate(side: string, anchor: Rect, size: Point, gap: number): Point
	if side == "above" then
		return { x = anchor.x + (anchor.w - size.x) / 2, y = anchor.y - gap - size.y }
	elseif side == "right" then
		return { x = anchor.x + anchor.w + gap, y = anchor.y + (anchor.h - size.y) / 2 }
	elseif side == "left" then
		return { x = anchor.x - gap - size.x, y = anchor.y + (anchor.h - size.y) / 2 }
	end
	return { x = anchor.x + (anchor.w - size.x) / 2, y = anchor.y + anchor.h + gap }
end

local function fits(position: Point, size: Point, bounds: Rect, margin: number): boolean
	local insideX = position.x >= bounds.x + margin and position.x + size.x <= bounds.x + bounds.w - margin
	local insideY = position.y >= bounds.y + margin and position.y + size.y <= bounds.y + bounds.h - margin
	return insideX and insideY
end

local OPPOSITE: { [string]: string } = { below = "above", above = "below", left = "right", right = "left" }

-- Places a popup of `size` next to `anchor` (a rect, or a 0x0 rect at the cursor). Tries the
-- preferred side, then the opposite side, then clamps into `bounds`. Returns the top-left corner
-- and the side that was used.
function Layout.place(anchor: Rect, size: Point, bounds: Rect, options: PlaceOptions?): (Point, string)
	local opts: PlaceOptions = options or {}
	local gap = opts.gap or 8
	local margin = opts.margin or 4
	local prefer = opts.prefer or "below"
	if OPPOSITE[prefer] == nil then
		prefer = "below"
	end
	local order = { prefer, OPPOSITE[prefer], "below", "above", "right", "left" }
	for _, side in order do
		local position = candidate(side, anchor, size, gap)
		if fits(position, size, bounds, margin) then
			return Layout.clamp(position, size, bounds, margin), side
		end
	end
	local fallback = candidate(prefer, anchor, size, gap)
	return Layout.clamp(fallback, size, bounds, margin), prefer
end

-- Grid cell size that fits `count` columns into `width` with `gap` pixels between cells.
function Layout.gridCell(width: number, columns: number, gap: number, aspect: number?): Point
	local cols = math.max(1, math.floor(columns))
	local cell = math.max(0, (width - gap * (cols - 1)) / cols)
	return { x = cell, y = cell * (aspect or 1) }
end

return Layout
