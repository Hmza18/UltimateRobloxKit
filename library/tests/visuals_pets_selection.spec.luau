--!strict
local SelectionLogic = require("../src/Visuals/Pets/SelectionLogic")
local t = require("./lib/t")

type Rect = SelectionLogic.Rect
type Insets = SelectionLogic.Insets

type Case = { name: string, width: number, height: number, insets: Insets, mode: string, columns: number }

-- Representative screens with the insets such devices report (notch, home indicator, top bar).
local CASES: { Case } = {
	{
		name = "1920x1080 desktop",
		width = 1920,
		height = 1080,
		insets = { left = 0, top = 0, right = 0, bottom = 0 },
		mode = "row",
		columns = 3,
	},
	{
		name = "1366x768 laptop",
		width = 1366,
		height = 768,
		insets = { left = 0, top = 0, right = 0, bottom = 0 },
		mode = "row",
		columns = 3,
	},
	{
		name = "1024x768 tablet",
		width = 1024,
		height = 768,
		insets = { left = 0, top = 24, right = 0, bottom = 20 },
		mode = "row",
		columns = 3,
	},
	{
		name = "844x390 phone landscape",
		width = 844,
		height = 390,
		insets = { left = 47, top = 0, right = 47, bottom = 21 },
		mode = "row",
		columns = 3,
	},
	{
		name = "390x844 phone portrait",
		width = 390,
		height = 844,
		insets = { left = 0, top = 47, right = 0, bottom = 34 },
		mode = "grid",
		columns = 2,
	},
}

local function inside(inner: Rect, outer: Rect): boolean
	return inner.x >= outer.x - 1e-6
		and inner.y >= outer.y - 1e-6
		and inner.x + inner.width <= outer.x + outer.width + 1e-6
		and inner.y + inner.height <= outer.y + outer.height + 1e-6
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

-- A card's rectangle on screen (cards are stored relative to the area).
local function onScreen(layout: SelectionLogic.Layout, card: Rect): Rect
	return { x = layout.area.x + card.x, y = layout.area.y + card.y, width = card.width, height = card.height }
end

local function checkParts(parts: SelectionLogic.CardParts, width: number, height: number, label: string)
	local box: Rect = { x = 0, y = 0, width = width, height = height }
	local list: { Rect } = { parts.preview, parts.name }
	if parts.description then
		table.insert(list, parts.description)
	end
	if parts.stats then
		table.insert(list, parts.stats)
	end
	for i, rect in list do
		t.truthy(inside(rect, box), label .. " part inside the card")
		t.truthy(rect.width > 0 and rect.height > 0, label .. " part has a size")
		for j = i + 1, #list do
			t.falsy(overlaps(rect, list[j]), label .. " parts do not overlap")
		end
	end
	t.truthy(parts.preview.height >= 48, label .. " preview is visible")
	t.truthy(parts.name.height >= 20, label .. " name is readable")
end

return {
	["layout: three starters fit the safe area on every representative screen"] = function()
		for _, case in CASES do
			local layout = SelectionLogic.layout({ width = case.width, height = case.height }, case.insets, 3, true)
			local label = case.name
			t.equal(layout.mode, case.mode, label .. " mode")
			t.equal(layout.columns, case.columns, label .. " columns")
			t.falsy(layout.scrolls, label .. " needs no scrolling")
			t.equal(#layout.cards, 3, label)

			local safe = layout.safe
			t.equal(safe.x, case.insets.left, label)
			t.equal(safe.y, case.insets.top, label)
			t.equal(safe.width, case.width - case.insets.left - case.insets.right, label)
			t.equal(safe.height, case.height - case.insets.top - case.insets.bottom, label)

			t.truthy(inside(layout.title, safe), label .. " title in the safe area")
			t.truthy(inside(layout.subtitle, safe), label .. " subtitle in the safe area")
			t.truthy(inside(layout.confirm, safe), label .. " confirm in the safe area")
			t.truthy(inside(layout.area, safe), label .. " cards area in the safe area")
			t.falsy(overlaps(layout.title, layout.area), label)
			t.falsy(overlaps(layout.subtitle, layout.area), label)
			t.falsy(overlaps(layout.confirm, layout.area), label)
			t.falsy(overlaps(layout.title, layout.subtitle), label)

			-- Touch targets.
			t.truthy(layout.confirm.height >= SelectionLogic.MIN_TOUCH, label .. " confirm height")
			t.truthy(layout.confirm.width >= 180, label .. " confirm width")
			t.truthy(layout.title.height >= 36, label .. " title height")

			for index, card in layout.cards do
				local rect = onScreen(layout, card)
				t.truthy(inside(rect, safe), label .. " card " .. index .. " in the safe area")
				t.truthy(inside(rect, layout.area), label .. " card " .. index .. " in its area")
				t.truthy(card.width >= SelectionLogic.MIN_TOUCH and card.height >= SelectionLogic.MIN_TOUCH, label)
				t.truthy(card.width >= 120, label .. " card is wide enough to read")
				t.equal(card.width, layout.card.width, label)
				t.equal(card.height, layout.card.height, label)
				for other = index + 1, #layout.cards do
					t.falsy(overlaps(card, layout.cards[other]), label .. " cards do not overlap")
				end
			end
			checkParts(layout.parts, layout.card.width, layout.card.height, label)
		end
	end,
	["layout: big screens get big cards, short screens get compact ones"] = function()
		local desktop = SelectionLogic.layout({ width = 1920, height = 1080 }, nil, 3, true)
		t.truthy(desktop.card.height >= 480)
		t.truthy(desktop.card.width >= 300)
		t.falsy(desktop.compact)
		t.truthy(desktop.parts.description ~= nil)
		t.truthy(desktop.parts.stats ~= nil)
		-- The row is centred.
		local first, last = desktop.cards[1], desktop.cards[3]
		t.near(first.x, desktop.area.width - (last.x + last.width), 1)

		local phone = SelectionLogic.layout({ width = 844, height = 390 }, nil, 3, true)
		t.truthy(phone.compact)
		t.equal(phone.parts.description, nil)
		t.equal(phone.parts.stats, nil)
		t.truthy(phone.card.height < desktop.card.height)
		t.truthy(phone.parts.preview.height >= phone.card.height * 0.5, "the pet stays the hero")

		-- Without a subtitle the cards get the space.
		local without = SelectionLogic.layout({ width = 844, height = 390 }, nil, 3, false)
		t.equal(without.subtitle.height, 0)
		t.truthy(without.area.height > phone.area.height)
	end,
	["layout: portrait uses a two-column grid with a centred last row"] = function()
		local layout = SelectionLogic.layout({ width = 390, height = 844 }, nil, 3, true)
		t.equal(layout.rows, 2)
		t.equal(layout.cards[1].y, layout.cards[2].y)
		t.truthy(layout.cards[3].y > layout.cards[1].y)
		-- The lone third card sits in the middle.
		t.near(layout.cards[3].x + layout.cards[3].width / 2, layout.area.width / 2, 1)
		local four = SelectionLogic.layout({ width = 390, height = 844 }, nil, 4, true)
		t.equal(four.cards[3].x, four.cards[1].x)
		t.equal(four.cards[4].x, four.cards[2].x)
	end,
	["layout: many pets scroll instead of shrinking past readable"] = function()
		local wide = SelectionLogic.layout({ width = 844, height = 390 }, nil, 9, true)
		t.equal(wide.mode, "scroll")
		t.truthy(wide.scrolls)
		t.equal(wide.scrollAxis, "x")
		t.truthy(wide.content.width > wide.area.width)
		t.truthy(wide.card.width >= 132)
		t.truthy(wide.card.height <= wide.area.height)
		for index, card in wide.cards do
			t.truthy(card.y >= 0 and card.y + card.height <= wide.area.height)
			t.truthy(card.x + card.width <= wide.content.width + 1e-6)
			if index > 1 then
				t.truthy(card.x >= wide.cards[index - 1].x + wide.cards[index - 1].width)
			end
		end

		local tall = SelectionLogic.layout({ width = 390, height = 844 }, nil, 10, true)
		t.equal(tall.mode, "grid")
		t.truthy(tall.scrolls)
		t.equal(tall.scrollAxis, "y")
		t.equal(tall.columns, 2)
		t.equal(tall.rows, 5)
		t.truthy(tall.content.height > tall.area.height)
		t.truthy(tall.card.height >= 150)
		for _, card in tall.cards do
			t.truthy(card.x >= 0 and card.x + card.width <= tall.area.width + 1e-6)
		end

		-- Five pets still fit a desktop row without scrolling.
		local five = SelectionLogic.layout({ width = 1920, height = 1080 }, nil, 5, true)
		t.equal(five.mode, "row")
		t.falsy(five.scrolls)
		-- Six on a laptop shrink a little but stay in one row.
		local six = SelectionLogic.layout({ width = 1366, height = 768 }, nil, 6, true)
		t.equal(six.mode, "row")
		t.truthy(six.card.width < five.card.width)
		t.truthy(six.cards[6].x + six.cards[6].width <= six.area.width + 1e-6)
	end,
	["layout: degenerate input does not produce negative sizes"] = function()
		for _, size in { { 1, 1 }, { 200, 100 }, { 100, 200 }, { 320, 480 } } do
			local layout = SelectionLogic.layout(
				{ width = size[1], height = size[2] },
				{ left = 500, top = 0, right = 0, bottom = 0 },
				3
			)
			t.truthy(layout.card.width > 0 and layout.card.height > 0)
			t.truthy(layout.area.height > 0 and layout.confirm.height >= SelectionLogic.MIN_TOUCH)
			t.equal(#layout.cards, 3)
		end
		t.equal(#SelectionLogic.layout({ width = 800, height = 600 }, nil, 0).cards, 1)
	end,
	["navigation: left and right wrap through the reading order"] = function()
		t.equal(SelectionLogic.navigate(1, "right", 3, 3), 2)
		t.equal(SelectionLogic.navigate(3, "right", 3, 3), 1)
		t.equal(SelectionLogic.navigate(1, "left", 3, 3), 3)
		t.equal(SelectionLogic.navigate(2, "left", 3, 3), 1)
		-- A full lap in each direction visits every card once and returns.
		for _, count in { 1, 3, 4, 7 } do
			for _, columns in { 1, 2, count } do
				local seen: { [number]: boolean } = {}
				local index = 1
				for _ = 1, count do
					seen[index] = true
					index = SelectionLogic.navigate(index, "right", count, columns)
				end
				t.equal(index, 1)
				for i = 1, count do
					t.truthy(seen[i])
				end
				index = 1
				for _ = 1, count do
					index = SelectionLogic.navigate(index, "left", count, columns)
				end
				t.equal(index, 1)
			end
		end
	end,
	["navigation: up and down move between grid rows and wrap, a single row stays put"] = function()
		t.equal(SelectionLogic.navigate(2, "down", 3, 3), 2)
		t.equal(SelectionLogic.navigate(2, "up", 3, 3), 2)
		-- 2 columns, 4 cards:  1 2 / 3 4
		t.equal(SelectionLogic.navigate(1, "down", 4, 2), 3)
		t.equal(SelectionLogic.navigate(3, "down", 4, 2), 1)
		t.equal(SelectionLogic.navigate(2, "up", 4, 2), 4)
		t.equal(SelectionLogic.navigate(4, "up", 4, 2), 2)
		-- 2 columns, 3 cards:  1 2 / 3 .   Column 2 has no second row, so it wraps to itself.
		t.equal(SelectionLogic.navigate(1, "down", 3, 2), 3)
		t.equal(SelectionLogic.navigate(3, "up", 3, 2), 1)
		t.equal(SelectionLogic.navigate(2, "down", 3, 2), 2)
		t.equal(SelectionLogic.navigate(2, "up", 3, 2), 2)
		-- 2 columns, 5 cards:  1 2 / 3 4 / 5 .
		t.equal(SelectionLogic.navigate(4, "down", 5, 2), 2)
		t.equal(SelectionLogic.navigate(2, "up", 5, 2), 4)
		t.equal(SelectionLogic.navigate(5, "down", 5, 2), 1)
		-- Out-of-range input is clamped rather than raising.
		t.equal(SelectionLogic.navigate(99, "right", 3, 3), 1)
		t.equal(SelectionLogic.navigate(-4, "left", 3, 3), 3)
		t.equal(SelectionLogic.initialFocus(3), 2)
		t.equal(SelectionLogic.initialFocus(4), 2)
		t.equal(SelectionLogic.initialFocus(3, 3), 3)
		t.equal(SelectionLogic.initialFocus(3, 9), 2)
	end,
	["input: keys, gamepad buttons, thumbstick and the tap rule"] = function()
		t.equal(SelectionLogic.keyAction("Left"), "left")
		t.equal(SelectionLogic.keyAction("A"), "left")
		t.equal(SelectionLogic.keyAction("D"), "right")
		t.equal(SelectionLogic.keyAction("DPadRight"), "right")
		t.equal(SelectionLogic.keyAction("DPadUp"), "up")
		t.equal(SelectionLogic.keyAction("S"), "down")
		t.equal(SelectionLogic.keyAction("Return"), "confirm")
		t.equal(SelectionLogic.keyAction("Space"), "confirm")
		t.equal(SelectionLogic.keyAction("ButtonA"), "confirm")
		t.equal(SelectionLogic.keyAction("Q"), nil)

		t.equal(SelectionLogic.stickDirection(0.2, 0.1), nil)
		t.equal(SelectionLogic.stickDirection(0.9, 0.1), "right")
		t.equal(SelectionLogic.stickDirection(-0.9, 0.3), "left")
		t.equal(SelectionLogic.stickDirection(0.1, 0.8), "up")
		t.equal(SelectionLogic.stickDirection(0.1, -0.8), "down")
		t.equal(SelectionLogic.stickDirection(0.3, 0, 0.2), "right")

		t.equal(SelectionLogic.press(nil, 2), "select")
		t.equal(SelectionLogic.press(1, 2), "select")
		t.equal(SelectionLogic.press(2, 2), "confirm")
	end,
	["scrolling: the focused card is brought fully into view"] = function()
		local layout = SelectionLogic.layout({ width = 844, height = 390 }, nil, 9, true)
		local limit = layout.content.width - layout.area.width
		t.equal(SelectionLogic.scrollTo(layout.cards[1], layout, 0), 0)
		local last = SelectionLogic.scrollTo(layout.cards[9], layout, 0)
		t.near(last, limit, 1e-6)
		-- Coming back to the first card scrolls to the start.
		t.equal(SelectionLogic.scrollTo(layout.cards[1], layout, last), 0)
		-- A card already in view does not move the scroller.
		t.equal(SelectionLogic.scrollTo(layout.cards[2], layout, 0), 0)
		local middle = SelectionLogic.scrollTo(layout.cards[6], layout, 0)
		t.truthy(middle > 0 and middle <= limit)
		t.truthy(layout.cards[6].x + layout.cards[6].width <= middle + layout.area.width + 1e-6)
		local still = SelectionLogic.layout({ width = 1920, height = 1080 }, nil, 3, true)
		t.equal(SelectionLogic.scrollTo(still.cards[3], still, 40), 0)
	end,
}
