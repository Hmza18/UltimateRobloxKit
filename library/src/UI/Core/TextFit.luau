--!strict
-- Picks a text size for a box from approximate font metrics (pure Luau). Components use the
-- result as the UITextSizeConstraint maximum with TextScaled, so the engine does the exact fit;
-- when even the minimum does not fit, they switch to the minimum size with TextTruncate instead.
--
-- Metrics are approximations: `charWidth` is the average glyph advance as a fraction of the text
-- size (chunky rounded fonts such as Fredoka One are about 0.58, all caps about 0.68), and
-- `lineHeight` is the line spacing as a fraction of the size. The size never goes below `floor`
-- (the style's minimum text size).

export type Request = {
	width: number, -- box width in pixels at 1x scale
	height: number, -- box height in pixels at 1x scale
	text: string?, -- the text, or give `length`
	length: number?, -- number of characters when the text is not known
	min: number?, -- smallest size wanted (default floor)
	max: number?, -- largest size wanted (default 32)
	floor: number?, -- hard minimum, the style's minimum text size (default 12)
	wrap: boolean?, -- allow several lines (default false)
	charWidth: number?, -- average glyph width / size (default 0.58, or 0.68 for all caps)
	lineHeight: number?, -- line spacing / size (default 1.15)
	padding: number?, -- pixels lost on each side, for example to the text stroke (default 0)
}

export type Result = {
	size: number, -- chosen text size
	lines: number, -- lines used at that size
	truncate: boolean, -- true when the text does not fit even at the minimum
	maxChars: number, -- characters that fit at the chosen size
}

local TextFit = {}

TextFit.DEFAULT_FLOOR = 12
TextFit.DEFAULT_MAX = 32
TextFit.CHAR_WIDTH = 0.58
TextFit.CAPS_WIDTH = 0.68
TextFit.LINE_HEIGHT = 1.15
-- Wrapping breaks between words, so wrapped text needs a little more room than its raw length.
TextFit.WRAP_SLACK = 1.15

-- Number of characters in `text` (UTF-8 aware, falls back to bytes for invalid UTF-8).
function TextFit.length(text: string): number
	local count = utf8.len(text)
	return if count then count else #text
end

-- True when the text has letters and none of them are lower case.
function TextFit.isCaps(text: string): boolean
	return string.find(text, "%a") ~= nil and string.find(text, "%l") == nil
end

local function charWidthFor(request: Request): number
	local custom = request.charWidth
	if custom then
		return custom
	end
	local text = request.text
	if text and TextFit.isCaps(text) then
		return TextFit.CAPS_WIDTH
	end
	return TextFit.CHAR_WIDTH
end

local function lengthOf(request: Request): number
	local length = request.length
	if length then
		return math.max(0, math.floor(length))
	end
	local text = request.text
	if text then
		return TextFit.length(text)
	end
	return 0
end

-- Size bounds after applying the floor: low >= floor and high >= low.
function TextFit.bounds(min: number?, max: number?, floor: number?): (number, number)
	local hard = math.max(1, math.floor(floor or TextFit.DEFAULT_FLOOR))
	local low = math.max(hard, math.floor(min or hard))
	local high = math.max(low, math.floor(max or TextFit.DEFAULT_MAX))
	return low, high
end

type Fit = { fits: boolean, lines: number, maxChars: number }

local function tryFit(size: number, length: number, width: number, height: number, request: Request): Fit
	local perLine = math.floor(width / (size * charWidthFor(request)))
	local lineStep = size * (request.lineHeight or TextFit.LINE_HEIGHT)
	local maxLines = 0
	if height >= size then
		maxLines = if request.wrap then 1 + math.floor((height - size) / lineStep) else 1
	end
	local maxChars = math.max(0, perLine * maxLines)
	if perLine < 1 or maxLines < 1 then
		return { fits = length == 0, lines = 0, maxChars = 0 }
	end
	if length <= perLine then
		return { fits = true, lines = 1, maxChars = maxChars }
	end
	local needed = math.ceil(length * TextFit.WRAP_SLACK / perLine)
	local fits = request.wrap == true and needed <= maxLines
	return { fits = fits, lines = math.min(needed, maxLines), maxChars = maxChars }
end

-- The largest whole size between the bounds at which the text fits the box.
function TextFit.fit(request: Request): Result
	local low, high = TextFit.bounds(request.min, request.max, request.floor)
	local padding = math.max(0, request.padding or 0)
	local width = math.max(0, request.width - padding * 2)
	local height = math.max(0, request.height - padding * 2)
	local length = lengthOf(request)
	for size = high, low, -1 do
		local attempt = tryFit(size, length, width, height, request)
		if attempt.fits then
			return { size = size, lines = attempt.lines, truncate = false, maxChars = attempt.maxChars }
		end
	end
	local smallest = tryFit(low, length, width, height, request)
	return { size = low, lines = smallest.lines, truncate = length > 0, maxChars = smallest.maxChars }
end

-- Cuts `text` to at most `maxChars` characters, ending with "..." when it was cut.
function TextFit.ellipsize(text: string, maxChars: number): string
	local limit = math.max(0, math.floor(maxChars))
	if TextFit.length(text) <= limit then
		return text
	end
	if limit <= 3 then
		return string.rep(".", limit)
	end
	local cut = utf8.offset(text, limit - 2)
	local head = if cut then string.sub(text, 1, cut - 1) else string.sub(text, 1, limit - 3)
	return head .. "..."
end

return TextFit
