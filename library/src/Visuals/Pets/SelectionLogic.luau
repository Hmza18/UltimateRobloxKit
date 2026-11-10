--!strict
-- Layout and navigation for the pet selection screen (pure Luau). All sizes are pixels in the
-- screen's coordinate space; the safe area (notch, home indicator, top bar) is respected.
--
--   wide screens       one centred row of large cards
--   short landscape    the same row with compact cards; a horizontal scroller when they cannot fit
--   portrait phones    a two-column grid; a vertical scroller when the rows cannot fit
--
-- Also: focus navigation with wrap-around, input mapping (keyboard, gamepad, thumbstick) and the
-- tap rule (tap selects, tapping the selected card confirms).

export type Viewport = { width: number, height: number }
export type Insets = { left: number, top: number, right: number, bottom: number }
export type Rect = { x: number, y: number, width: number, height: number }

export type CardParts = {
	padding: number,
	preview: Rect, -- relative to the card
	name: Rect,
	description: Rect?,
	stats: Rect?,
}

export type Layout = {
	mode: "row" | "scroll" | "grid",
	columns: number,
	rows: number,
	scrolls: boolean,
	scrollAxis: "x" | "y" | "none",
	safe: Rect,
	margin: number,
	gap: number,
	title: Rect,
	subtitle: Rect,
	area: Rect, -- where the cards live (the scroller's frame when scrolling)
	content: { width: number, height: number }, -- size of all cards together (the scroll canvas)
	card: { width: number, height: number },
	cards: { Rect }, -- relative to the area's top-left corner (canvas space when scrolling)
	parts: CardParts,
	confirm: Rect,
	compact: boolean, -- short screens: smaller type, no description
}

export type Direction = "left" | "right" | "up" | "down"

local SelectionLogic = {}

SelectionLogic.MIN_TOUCH = 44
SelectionLogic.MIN_PETS = 3

local function inset(insets: Insets?): Insets
	local given: Insets = insets or { left = 0, top = 0, right = 0, bottom = 0 }
	return {
		left = math.max(0, given.left or 0),
		top = math.max(0, given.top or 0),
		right = math.max(0, given.right or 0),
		bottom = math.max(0, given.bottom or 0),
	}
end

local function round(value: number): number
	return math.floor(value + 0.5)
end

-- The rectangles inside one card for a given card size.
function SelectionLogic.cardParts(width: number, height: number): CardParts
	local padding = math.clamp(round(width * 0.06), 8, 18)
	local inner = width - padding * 2
	local showDescription = height >= 250
	local showStats = height >= 300
	local nameHeight = math.clamp(round(height * 0.11), 20, 40)
	local statsHeight = if showStats then math.clamp(round(height * 0.09), 24, 34) else 0
	local descriptionHeight = if showDescription then math.clamp(round(height * 0.16), 30, 64) else 0
	local gaps = padding * 0.5
	local used = nameHeight
		+ (if showDescription then descriptionHeight + gaps else 0)
		+ (if showStats then statsHeight + gaps else 0)
	local previewHeight = math.max(48, height - padding * 2 - used - gaps)
	local y = padding
	local preview: Rect = { x = padding, y = y, width = inner, height = previewHeight }
	y += previewHeight + gaps
	local name: Rect = { x = padding, y = y, width = inner, height = nameHeight }
	y += nameHeight + gaps
	local description: Rect? = nil
	if showDescription then
		description = { x = padding, y = y, width = inner, height = descriptionHeight }
		y += descriptionHeight + gaps
	end
	local stats: Rect? = nil
	if showStats then
		stats = { x = padding, y = y, width = inner, height = statsHeight }
	end
	return { padding = padding, preview = preview, name = name, description = description, stats = stats }
end

-- The whole screen for `count` pets. `hasSubtitle` reserves the subtitle line.
function SelectionLogic.layout(viewport: Viewport, insets: Insets?, count: number, hasSubtitle: boolean?): Layout
	local n = math.max(1, math.floor(count))
	local pad = inset(insets)
	local safe: Rect = {
		x = pad.left,
		y = pad.top,
		width = math.max(1, viewport.width - pad.left - pad.right),
		height = math.max(1, viewport.height - pad.top - pad.bottom),
	}
	local margin = math.clamp(round(math.min(safe.width, safe.height) * 0.04), 12, 40)
	local inner: Rect = {
		x = safe.x + margin,
		y = safe.y + margin,
		width = math.max(1, safe.width - margin * 2),
		height = math.max(1, safe.height - margin * 2),
	}
	local compact = inner.height < 420
	local gap = math.clamp(round(inner.width * 0.02), 10, 28)
	local titleHeight = math.clamp(round(inner.height * 0.11), 36, 92)
	local subtitleHeight = if hasSubtitle == false then 0 else math.clamp(round(inner.height * 0.05), 18, 34)
	local confirmHeight = math.clamp(round(inner.height * 0.1), 48, 72)
	local confirmWidth = math.min(inner.width, math.clamp(round(inner.width * 0.34), 180, 340))

	local title: Rect = { x = inner.x, y = inner.y, width = inner.width, height = titleHeight }
	local subtitle: Rect = { x = inner.x, y = inner.y + titleHeight, width = inner.width, height = subtitleHeight }
	local confirm: Rect = {
		x = round(inner.x + (inner.width - confirmWidth) / 2),
		y = inner.y + inner.height - confirmHeight,
		width = confirmWidth,
		height = confirmHeight,
	}
	local areaTop = inner.y + titleHeight + subtitleHeight + gap
	local area: Rect = {
		x = inner.x,
		y = areaTop,
		width = inner.width,
		height = math.max(SelectionLogic.MIN_TOUCH, confirm.y - gap - areaTop),
	}

	local cards: { Rect } = {}
	local portrait = safe.height > safe.width * 1.15
	local mode: "row" | "scroll" | "grid"
	local columns, rows = n, 1
	local cardWidth, cardHeight: number
	local scrolls = false
	local scrollAxis: "x" | "y" | "none" = "none"
	local contentWidth, contentHeight: number

	if portrait then
		mode = "grid"
		columns = math.min(2, n)
		rows = math.ceil(n / columns)
		cardWidth = math.max(1, math.floor((area.width - gap * (columns - 1)) / columns))
		local fit = math.floor((area.height - gap * (rows - 1)) / rows)
		cardHeight = math.max(1, math.min(round(cardWidth * 1.3), fit))
		local minimum = math.max(150, round(cardWidth * 0.95))
		if cardHeight < minimum then
			scrolls = true
			scrollAxis = "y"
			cardHeight = round(cardWidth * 1.2)
		end
		contentWidth = columns * cardWidth + (columns - 1) * gap
		contentHeight = rows * cardHeight + (rows - 1) * gap
		local top = if scrolls then 0 else math.floor((area.height - contentHeight) / 2)
		for index = 0, n - 1 do
			local row = index // columns
			local inRow = math.min(columns, n - row * columns)
			local column = index - row * columns
			local rowWidth = inRow * cardWidth + (inRow - 1) * gap
			local left = math.floor((area.width - rowWidth) / 2)
			table.insert(cards, {
				x = left + column * (cardWidth + gap),
				y = top + row * (cardHeight + gap),
				width = cardWidth,
				height = cardHeight,
			})
		end
	else
		mode = "row"
		cardHeight = math.min(area.height, 520)
		local ideal = math.min(round(cardHeight * 0.72), 340)
		cardWidth = ideal
		local needed = n * cardWidth + (n - 1) * gap
		if needed > area.width then
			-- Narrower cards first (keeping a sensible shape); a scroller once they would be
			-- too narrow to read.
			local minimum = 132
			cardWidth = math.floor((area.width - (n - 1) * gap) / n)
			if cardWidth < minimum then
				mode = "scroll"
				scrolls = true
				scrollAxis = "x"
				cardWidth = math.clamp(round(cardHeight * 0.62), minimum, 300)
				-- Leave room for the scroll bar under the cards.
				cardHeight = math.max(SelectionLogic.MIN_TOUCH, cardHeight - 10)
			else
				cardHeight = math.min(cardHeight, round(cardWidth / 0.55))
			end
		end
		cardWidth = math.max(1, cardWidth)
		contentWidth = n * cardWidth + (n - 1) * gap
		contentHeight = cardHeight
		local left = if scrolls then 0 else math.floor((area.width - contentWidth) / 2)
		local top = if scrolls then 0 else math.floor((area.height - cardHeight) / 2)
		for index = 0, n - 1 do
			table.insert(cards, {
				x = left + index * (cardWidth + gap),
				y = top,
				width = cardWidth,
				height = cardHeight,
			})
		end
	end

	return {
		mode = mode,
		columns = columns,
		rows = rows,
		scrolls = scrolls,
		scrollAxis = scrollAxis,
		safe = safe,
		margin = margin,
		gap = gap,
		title = title,
		subtitle = subtitle,
		area = area,
		content = { width = contentWidth, height = contentHeight },
		card = { width = cardWidth, height = cardHeight },
		cards = cards,
		parts = SelectionLogic.cardParts(cardWidth, cardHeight),
		confirm = confirm,
		compact = compact,
	}
end

-- The card reached from `index` by moving in `direction`. Left / right walk the reading order and
-- wrap from the last card to the first. Up / down move between rows of a grid and wrap; in a
-- single row they stay put. A short last row is skipped when the column has no card there.
function SelectionLogic.navigate(index: number, direction: Direction, count: number, columns: number): number
	local n = math.max(1, math.floor(count))
	local current = math.clamp(math.floor(index), 1, n)
	if direction == "left" then
		return (current - 2) % n + 1
	elseif direction == "right" then
		return current % n + 1
	end
	local perRow = math.clamp(math.floor(columns), 1, n)
	local rows = math.ceil(n / perRow)
	if rows <= 1 then
		return current
	end
	local column = (current - 1) % perRow
	local row = (current - 1) // perRow
	local step = if direction == "down" then 1 else -1
	for _ = 1, rows do
		row = (row + step) % rows
		local candidate = row * perRow + column + 1
		if candidate <= n then
			return candidate
		end
	end
	return current
end

-- Where focus starts when nothing is focused yet: the selected card, else the middle card.
function SelectionLogic.initialFocus(count: number, selected: number?): number
	if selected and selected >= 1 and selected <= count then
		return selected
	end
	return math.max(1, math.ceil(count / 2))
end

export type Action = Direction | "confirm"

local KEYS: { [string]: Action } = {
	Left = "left",
	A = "left",
	DPadLeft = "left",
	Right = "right",
	D = "right",
	DPadRight = "right",
	Up = "up",
	W = "up",
	DPadUp = "up",
	Down = "down",
	S = "down",
	DPadDown = "down",
	Return = "confirm",
	KeypadEnter = "confirm",
	Space = "confirm",
	ButtonA = "confirm",
}

-- The action for a KeyCode name ("Left", "D", "DPadRight", "ButtonA"), or nil.
function SelectionLogic.keyAction(keyName: string): Action?
	return KEYS[keyName]
end

-- The direction a thumbstick points in, or nil inside the dead zone. y is up, as Roblox reports it.
function SelectionLogic.stickDirection(x: number, y: number, deadzone: number?): Direction?
	local limit = deadzone or 0.55
	if math.abs(x) < limit and math.abs(y) < limit then
		return nil
	end
	if math.abs(x) >= math.abs(y) then
		return if x > 0 then "right" else "left"
	end
	return if y > 0 then "up" else "down"
end

-- Tap rule: tapping a card selects it; tapping the selected card again confirms.
function SelectionLogic.press(selected: number?, index: number): "select" | "confirm"
	return if selected == index then "confirm" else "select"
end

-- Scroll offset that brings a card fully into view (0 when it already is).
function SelectionLogic.scrollTo(card: Rect, layout: Layout, current: number): number
	if not layout.scrolls then
		return 0
	end
	local start, size, view, total: number
	if layout.scrollAxis == "x" then
		start, size, view, total = card.x, card.width, layout.area.width, layout.content.width
	else
		start, size, view, total = card.y, card.height, layout.area.height, layout.content.height
	end
	local limit = math.max(0, total - view)
	local offset = current
	if start < offset then
		offset = start
	elseif start + size > offset + view then
		offset = start + size - view
	end
	return math.clamp(offset, 0, limit)
end

return SelectionLogic
