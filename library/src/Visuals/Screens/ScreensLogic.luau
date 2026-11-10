--!strict
-- Screen template maths (pure Luau, no Roblox globals). Everything a screen decides without an
-- Instance lives here so it can be tested in Lune:
--
--   * responsive layout: window rectangle, navigation placement, grids with 44 px touch targets,
--     HUD anchor regions, text scale, overflow to scrolling;
--   * prop validation against ScreensData and per-screen view models (daily reward states, spin
--     wheel angles, leaderboard order, upgrade affordability, trade diffs, quest order, hotbar
--     cooldown fractions ...);
--   * focus order for keyboard and gamepad (UI/Core/SpatialNav);
--   * which Visuals.UI preset opens and closes each kind of screen.
--
-- Sizes are pixels. Angles are degrees, clockwise, 0 at the wheel's pointer (top).
-- Nothing here decides a gameplay result: affordability, claim states and wheel results are
-- derived from numbers the caller passes in, and the server stays the authority.

local Breakpoints = require("../../UI/Core/Breakpoints")
local ScreensData = require("./ScreensData")
local SpatialNav = require("../../UI/Core/SpatialNav")

export type Size = { x: number, y: number }
export type Insets = { top: number, left: number, right: number, bottom: number }
export type Rect = { x: number, y: number, w: number, h: number }

export type Env = {
	viewport: Size,
	insets: Insets,
	safe: Rect, -- the viewport minus the insets
	input: string, -- "mouse" | "touch" | "gamepad"
	breakpoint: string, -- "phone" | "tablet" | "desktop" | "console"
	portrait: boolean,
	margin: number, -- gap kept between a screen and the safe area's edge
	textScale: number,
}

export type Window = {
	x: number, -- top-left corner in viewport pixels
	y: number,
	w: number,
	h: number,
	header: number, -- header height
	padding: number, -- content padding
	fullscreen: boolean, -- fills the safe area (phones)
}

export type Body = {
	navigation: string, -- "none" | "top" | "bottom" | "sidebar"
	nav: Rect?, -- relative to the window's top-left corner
	content: Rect, -- relative to the window's top-left corner
	tab: Size, -- size of one tab button
	navScroll: boolean, -- the tabs do not fit and scroll
}

export type GridOptions = {
	minCell: number?, -- narrowest cell, default 96 (never below the touch target)
	maxCell: number?, -- widest cell, default: no limit
	aspect: number?, -- cell width / height, default 1
	gap: number?, -- default 8
	minColumns: number?, -- default 1
	maxColumns: number?, -- default 8
	count: number?, -- number of items, for rows and content height
	height: number?, -- available height, for `scroll`
}

export type Grid = {
	columns: number,
	cellW: number,
	cellH: number,
	gap: number,
	rows: number,
	width: number, -- columns * cellW + gaps: never wider than the space given
	contentHeight: number,
	scroll: boolean,
}

local ScreensLogic = {}

-- Smallest size of anything a finger must hit.
ScreensLogic.MIN_TOUCH = 44
ScreensLogic.MIN_TEXT = 12

-- The viewports every screen is laid out for (the spec checks each).
ScreensLogic.VIEWPORTS = table.freeze({
	{ name = "1080p", x = 1920, y = 1080, input = "mouse" },
	{ name = "laptop", x = 1366, y = 768, input = "mouse" },
	{ name = "tablet", x = 1024, y = 768, input = "touch" },
	{ name = "phone landscape", x = 844, y = 390, input = "touch" },
	{ name = "phone portrait", x = 390, y = 844, input = "touch" },
})

ScreensLogic.RARITIES = table.freeze({ "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret" })

local MIN_TOUCH = ScreensLogic.MIN_TOUCH

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function number(value: any, default: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return default
end

local function list(value: any): { any }
	return if type(value) == "table" then value else {}
end

-- Environment ------------------------------------------------------------------------------------

local TEXT_SCALE: { [string]: number } = { phone = 0.85, tablet = 0.95, desktop = 1, console = 1.2 }
local MARGIN: { [string]: number } = { phone = 8, tablet = 16, desktop = 24, console = 48 }

-- Describes where a screen is shown. `input` is the kind of input in use.
function ScreensLogic.env(viewport: Size, insets: Insets?, input: string?): Env
	local kind = if input == "touch" or input == "gamepad" then input else "mouse"
	local pad: Insets = insets or { top = 0, left = 0, right = 0, bottom = 0 }
	local width = math.max(1, viewport.x)
	local height = math.max(1, viewport.y)
	local breakpoint = Breakpoints.classify(
		{ x = width, y = height },
		{ touch = kind == "touch", keyboard = kind == "mouse", gamepad = kind == "gamepad" }
	)
	local safe: Rect = {
		x = pad.left,
		y = pad.top,
		w = math.max(1, width - pad.left - pad.right),
		h = math.max(1, height - pad.top - pad.bottom),
	}
	return {
		viewport = { x = width, y = height },
		insets = pad,
		safe = safe,
		input = kind,
		breakpoint = breakpoint,
		portrait = height > width,
		margin = MARGIN[breakpoint] or 16,
		textScale = TEXT_SCALE[breakpoint] or 1,
	}
end

-- Text size for a role size at 1x: scaled for the device, never below the minimum.
function ScreensLogic.textSize(env: Env, base: number): number
	return math.max(ScreensLogic.MIN_TEXT, math.floor(base * env.textScale + 0.5))
end

-- Windows ----------------------------------------------------------------------------------------

type WindowSpec = { w: number, h: number, maxW: number, maxH: number }

local WINDOWS: { [string]: WindowSpec } = {
	dialog = { w = 0.4, h = 0.5, maxW = 480, maxH = 420 },
	window = { w = 0.56, h = 0.72, maxW = 820, maxH = 660 },
	wide = { w = 0.74, h = 0.84, maxW = 1100, maxH = 800 },
	full = { w = 1, h = 1, maxW = math.huge, maxH = math.huge },
}

ScreensLogic.WINDOW_KINDS = table.freeze({ "dialog", "window", "wide", "full" })

-- The rectangle of a window of `kind` ("dialog", "window", "wide", "full"): centred in the safe
-- area and never larger than it. Phones give every kind but "dialog" the whole safe area.
function ScreensLogic.window(env: Env, kind: string?): Window
	local spec = WINDOWS[kind or "window"] or WINDOWS.window
	local safe = env.safe
	local margin = env.margin
	local availableW = math.max(1, safe.w - margin * 2)
	local availableH = math.max(1, safe.h - margin * 2)
	local w, h = spec.w, spec.h
	local fullscreen = kind == "full"
	if env.breakpoint == "phone" then
		if kind == "dialog" then
			w, h = 0.86, 0.86
		else
			w, h = 1, 1
			fullscreen = true
		end
	elseif env.breakpoint == "tablet" then
		w = math.min(1, w + 0.18)
		h = math.min(1, h + 0.1)
	end
	local width = math.min(availableW * w, spec.maxW, availableW)
	local height = math.min(availableH * h, spec.maxH, availableH)
	width = math.floor(math.min(availableW, math.max(width, 240)))
	height = math.floor(math.min(availableH, math.max(height, 200)))
	local phone = env.breakpoint == "phone"
	return {
		x = math.floor(safe.x + (safe.w - width) / 2),
		y = math.floor(safe.y + (safe.h - height) / 2),
		w = width,
		h = height,
		header = if phone then 48 else 56,
		padding = if phone then 8 elseif env.breakpoint == "tablet" then 12 else 16,
		fullscreen = fullscreen,
	}
end

-- Where the tabs of a screen go: a bottom bar on portrait phones (thumb reach), a sidebar on
-- landscape phones (height is scarce) and for many tabs on wide screens, tabs on top otherwise.
function ScreensLogic.navigation(env: Env, tabCount: number): string
	if tabCount <= 1 then
		return "none"
	end
	if env.breakpoint == "phone" then
		return if env.portrait then "bottom" else "sidebar"
	end
	if tabCount >= 6 and env.viewport.x >= 1600 then
		return "sidebar"
	end
	return "top"
end

local NAV_BAR = 52
local NAV_GAP = 6

-- Splits a window into navigation and content. Rectangles are relative to the window.
function ScreensLogic.body(env: Env, window: Window, tabCount: number?): Body
	local count = math.max(0, math.floor(tabCount or 0))
	local navigation = ScreensLogic.navigation(env, count)
	local pad = window.padding
	local inner: Rect = {
		x = pad,
		y = window.header + pad,
		w = math.max(1, window.w - pad * 2),
		h = math.max(1, window.h - window.header - pad * 2),
	}
	if navigation == "none" then
		return { navigation = navigation, nav = nil, content = inner, tab = { x = 0, y = 0 }, navScroll = false }
	end
	if navigation == "sidebar" then
		local width = if env.breakpoint == "phone" then 64 else 200
		width = math.min(width, math.floor(inner.w * 0.4))
		local tabHeight = 48
		local needed = count * tabHeight + (count - 1) * NAV_GAP
		return {
			navigation = navigation,
			nav = { x = inner.x, y = inner.y, w = width, h = inner.h },
			content = { x = inner.x + width + pad, y = inner.y, w = math.max(1, inner.w - width - pad), h = inner.h },
			tab = { x = width, y = tabHeight },
			navScroll = needed > inner.h,
		}
	end
	local bar = math.min(NAV_BAR, math.max(MIN_TOUCH, math.floor(inner.h * 0.3)))
	local tabWidth = math.floor((inner.w - (count - 1) * NAV_GAP) / count)
	local scroll = tabWidth < MIN_TOUCH * 1.5
	if scroll then
		tabWidth = math.floor(MIN_TOUCH * 2)
	end
	local contentHeight = math.max(1, inner.h - bar - pad)
	local navY = if navigation == "top" then inner.y else inner.y + inner.h - bar
	local contentY = if navigation == "top" then inner.y + bar + pad else inner.y
	return {
		navigation = navigation,
		nav = { x = inner.x, y = navY, w = inner.w, h = bar },
		content = { x = inner.x, y = contentY, w = inner.w, h = contentHeight },
		tab = { x = tabWidth, y = bar },
		navScroll = scroll,
	}
end

-- Grids and lists --------------------------------------------------------------------------------

-- Columns and cell size for `width` pixels. Cells never go below the touch target, the grid never
-- gets wider than `width`, and `scroll` says whether `count` items overflow `height`.
function ScreensLogic.grid(width: number, options: GridOptions?): Grid
	local opts: GridOptions = options or {}
	local gap = math.max(0, opts.gap or 8)
	local space = math.max(1, math.floor(width))
	local minCell = math.max(MIN_TOUCH, opts.minCell or 96)
	local minColumns = math.max(1, math.floor(opts.minColumns or 1))
	local maxColumns = math.max(minColumns, math.floor(opts.maxColumns or 8))
	local columns = math.clamp(math.floor((space + gap) / (minCell + gap)), minColumns, maxColumns)
	local count = math.max(0, math.floor(opts.count or 0))
	local cellW = math.floor((space - gap * (columns - 1)) / columns)
	-- Forced columns (minColumns) on a narrow space: drop columns until a finger fits again.
	while columns > 1 and cellW < MIN_TOUCH do
		columns -= 1
		cellW = math.floor((space - gap * (columns - 1)) / columns)
	end
	if opts.maxCell ~= nil then
		cellW = math.min(cellW, math.max(MIN_TOUCH, math.floor(opts.maxCell)))
	end
	cellW = math.max(1, math.min(cellW, space))
	local aspect = if opts.aspect ~= nil and opts.aspect > 0 then opts.aspect else 1
	local cellH = math.max(MIN_TOUCH, math.floor(cellW / aspect))
	local rows = if count > 0 then math.ceil(count / columns) else 0
	local contentHeight = if rows > 0 then rows * cellH + (rows - 1) * gap else 0
	return {
		columns = columns,
		cellW = cellW,
		cellH = cellH,
		gap = gap,
		rows = rows,
		width = columns * cellW + (columns - 1) * gap,
		contentHeight = contentHeight,
		scroll = opts.height ~= nil and contentHeight > opts.height,
	}
end

-- Card sizes the screens share: narrowest and widest cell and width / height.
local CARDS: { [string]: GridOptions } = {
	pet = { minCell = 132, maxCell = 176, aspect = 0.75 },
	product = { minCell = 140, maxCell = 190, aspect = 0.78 },
	egg = { minCell = 150, maxCell = 220, aspect = 0.8 },
	day = { minCell = 92, maxCell = 132, aspect = 0.8 },
	slot = { minCell = 64, maxCell = 88, aspect = 1 },
	tile = { minCell = 76, maxCell = 108, aspect = 1 },
	news = { minCell = 200, maxCell = 320, aspect = 1.6 },
	bundle = { minCell = 180, maxCell = 260, aspect = 0.9 },
}

ScreensLogic.CARDS = CARDS

-- A grid of one of the shared card kinds in `width` x `height` for `count` items.
function ScreensLogic.cards(kind: string, width: number, count: number?, height: number?): Grid
	local card: GridOptions = ScreensLogic.CARDS[kind] or ScreensLogic.CARDS.tile
	local env = if width < 500 then 6 else 10
	return ScreensLogic.grid(width, {
		minCell = card.minCell,
		maxCell = card.maxCell,
		aspect = card.aspect,
		gap = env,
		count = count,
		height = height,
	})
end

-- A vertical list of rows: row height (at least the touch target), content height and overflow.
function ScreensLogic.rows(
	count: number,
	rowHeight: number,
	gap: number?,
	height: number?
): {
	rowHeight: number,
	gap: number,
	contentHeight: number,
	scroll: boolean,
}
	local space = math.max(0, gap or 8)
	local row = math.max(MIN_TOUCH, math.floor(rowHeight))
	local total = math.max(0, math.floor(count))
	local contentHeight = if total > 0 then total * row + (total - 1) * space else 0
	return {
		rowHeight = row,
		gap = space,
		contentHeight = contentHeight,
		scroll = height ~= nil and contentHeight > height,
	}
end

export type Split = { mode: string, primary: Rect, secondary: Rect }
export type SplitOptions = {
	ratio: number?, -- the primary pane's share of the width, default 0.6
	minPrimary: number?, -- default 300
	minSecondary: number?, -- default 220
	gap: number?,
	stackRatio: number?, -- the primary pane's share of the height when stacked, default 0.5
}

-- Divides an area into a primary and a secondary pane: side by side ("columns") when both get
-- their minimum width, stacked ("stack") otherwise. `ratio` is the primary pane's share.
function ScreensLogic.split(area: Rect, options: SplitOptions?): Split
	local opts: SplitOptions = options or {}
	local gap = opts.gap or 8
	local ratio = math.clamp(opts.ratio or 0.6, 0.2, 0.8)
	local primaryW = math.floor((area.w - gap) * ratio)
	local secondaryW = area.w - gap - primaryW
	if primaryW >= (opts.minPrimary or 300) and secondaryW >= (opts.minSecondary or 220) then
		return {
			mode = "columns",
			primary = { x = area.x, y = area.y, w = primaryW, h = area.h },
			secondary = { x = area.x + primaryW + gap, y = area.y, w = secondaryW, h = area.h },
		}
	end
	local stackRatio = math.clamp(opts.stackRatio or 0.5, 0.2, 0.8)
	local primaryH = math.max(1, math.floor((area.h - gap) * stackRatio))
	return {
		mode = "stack",
		primary = { x = area.x, y = area.y, w = area.w, h = primaryH },
		secondary = { x = area.x, y = area.y + primaryH + gap, w = area.w, h = math.max(1, area.h - gap - primaryH) },
	}
end

-- True when `content` pixels do not fit in `available`: the container scrolls instead of overflowing.
function ScreensLogic.overflows(content: number, available: number): boolean
	return content > available + 0.5
end

-- HUD --------------------------------------------------------------------------------------------

export type Hud = {
	regions: { [string]: Rect }, -- topLeft, top, topRight, left, right, bottom (+ bottomLeft, bottomRight off touch)
	clear: Rect, -- the centre of the screen: nothing is anchored over it
	reserved: { [string]: Rect }, -- touch only: bottomLeft (thumbstick) and bottomRight (jump button)
	margin: number,
}

function ScreensLogic.intersects(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function ScreensLogic.contains(outer: Rect, inner: Rect): boolean
	return inner.x >= outer.x - 0.5
		and inner.y >= outer.y - 0.5
		and inner.x + inner.w <= outer.x + outer.w + 0.5
		and inner.y + inner.h <= outer.y + outer.h + 0.5
end

-- Anchor regions for HUD elements. The centre stays clear of everything, and on touch devices the
-- bottom corners are left to the thumbstick and the jump button.
function ScreensLogic.hud(env: Env): Hud
	local safe = env.safe
	local m = if env.breakpoint == "phone" then 8 else 16
	local clear: Rect = {
		x = math.floor(safe.x + safe.w * 0.28),
		y = math.floor(safe.y + safe.h * 0.25),
		w = math.floor(safe.w * 0.44),
		h = math.floor(safe.h * 0.5),
	}
	local sideW = math.max(1, clear.x - safe.x - m * 2)
	local topH = math.max(1, clear.y - safe.y - m * 2)
	local bottomY = clear.y + clear.h + m
	local bottomH = math.max(1, safe.y + safe.h - m - bottomY)
	local rightX = clear.x + clear.w + m
	local regions: { [string]: Rect } = {
		topLeft = { x = safe.x + m, y = safe.y + m, w = sideW, h = topH },
		top = { x = clear.x, y = safe.y + m, w = clear.w, h = topH },
		topRight = { x = rightX, y = safe.y + m, w = sideW, h = topH },
		left = { x = safe.x + m, y = clear.y, w = sideW, h = clear.h },
		right = { x = rightX, y = clear.y, w = sideW, h = clear.h },
	}
	local reserved: { [string]: Rect } = {}
	if env.input == "touch" then
		local stickW = math.floor(math.min(safe.w * 0.28, 260))
		local stickH = math.floor(math.min(safe.h * 0.45, 220))
		local jumpW = math.floor(math.min(safe.w * 0.2, 180))
		local jumpH = math.floor(math.min(safe.h * 0.4, 180))
		local stick: Rect = { x = safe.x, y = safe.y + safe.h - stickH, w = stickW, h = stickH }
		local jump: Rect = { x = safe.x + safe.w - jumpW, y = safe.y + safe.h - jumpH, w = jumpW, h = jumpH }
		reserved.bottomLeft = stick
		reserved.bottomRight = jump
		regions.left.h = math.max(1, math.min(regions.left.h, stick.y - m - regions.left.y))
		regions.right.h = math.max(1, math.min(regions.right.h, jump.y - m - regions.right.y))
		local x = stick.x + stick.w + m
		regions.bottom = { x = x, y = bottomY, w = math.max(1, jump.x - m - x), h = bottomH }
	else
		regions.bottomLeft = { x = safe.x + m, y = bottomY, w = sideW, h = bottomH }
		regions.bottom = { x = clear.x, y = bottomY, w = clear.w, h = bottomH }
		regions.bottomRight = { x = rightX, y = bottomY, w = sideW, h = bottomH }
	end
	return { regions = regions, clear = clear, reserved = reserved, margin = m }
end

-- Size of a square HUD button that fits `count` of them along a region (never below the touch target).
function ScreensLogic.hudButton(region: Rect, count: number, vertical: boolean, gap: number?): number
	local space = gap or 6
	local n = math.max(1, count)
	local along = if vertical then region.h else region.w
	local across = if vertical then region.w else region.h
	local fit = math.floor((along - (n - 1) * space) / n)
	return math.clamp(math.min(fit, across), MIN_TOUCH, 72)
end

export type TapLayout = {
	tap: Rect, -- the tap button (square)
	rebirth: Rect, -- the rebirth progress bar
	counters: Rect, -- currency counters
	countersVertical: boolean,
	multiplier: Rect,
	menu: Rect, -- side menu buttons, stacked vertically
	menuButton: number, -- side of one menu button
	menuScroll: boolean, -- the menu buttons do not all fit and scroll
}

local CHIP_W, CHIP_H = 120, 36

-- Where the tapping HUD puts its parts: counters at the top, the tap button at the bottom
-- (between the thumbstick and the jump button on touch), the rebirth bar above it when there is
-- room, and the menu buttons down the right edge.
function ScreensLogic.tapLayout(env: Env, menuCount: number?, currencyCount: number?): TapLayout
	local hud = ScreensLogic.hud(env)
	local regions = hud.regions
	local bottom = regions.bottom
	local barH = 24
	local barInBottom = bottom.h >= 64 + 8 + barH
	local room = bottom.h - (if barInBottom then barH + 8 else 0)
	local side = math.floor(math.clamp(math.min(bottom.w, room), MIN_TOUCH, 128))
	local tap: Rect = {
		x = math.floor(bottom.x + (bottom.w - side) / 2),
		y = math.floor(bottom.y + bottom.h - side),
		w = side,
		h = side,
	}
	local rebirth: Rect
	if barInBottom then
		local width = math.min(bottom.w, 320)
		rebirth = { x = math.floor(bottom.x + (bottom.w - width) / 2), y = bottom.y, w = width, h = barH }
	else
		local corner = regions.topLeft
		rebirth = { x = corner.x, y = corner.y + corner.h - barH, w = math.min(corner.w, 320), h = barH }
	end
	local top = regions.top
	local currencies = math.max(1, math.floor(currencyCount or 1))
	local corner = regions.topRight
	local chipW = math.min(CHIP_W, corner.w)
	local right = regions.right
	local count = math.max(0, math.floor(menuCount or 0))
	local button = ScreensLogic.hudButton(right, math.max(1, count), true)
	local needed = count * button + math.max(0, count - 1) * 6
	return {
		tap = tap,
		rebirth = rebirth,
		counters = top,
		countersVertical = top.w < currencies * CHIP_W + (currencies - 1) * 6,
		multiplier = { x = corner.x + corner.w - chipW, y = corner.y, w = chipW, h = CHIP_H },
		menu = {
			x = right.x + right.w - math.min(right.w, button),
			y = right.y,
			w = math.min(right.w, button),
			h = right.h,
		},
		menuButton = button,
		menuScroll = needed > right.h,
	}
end

-- The ability hotbar: `count` square slots in a centred row at the bottom of the HUD (between the
-- touch controls on phones). Slots shrink to fit but never below the touch target; when they
-- still do not fit, the row scrolls.
function ScreensLogic.hotbarLayout(env: Env, count: number): { row: Rect, slot: number, gap: number, scroll: boolean }
	local bottom = ScreensLogic.hud(env).regions.bottom
	local n = math.max(1, math.floor(count))
	local gap = 6
	local slot = math.floor(math.clamp(math.min((bottom.w - (n - 1) * gap) / n, bottom.h), MIN_TOUCH, 64))
	local needed = n * slot + (n - 1) * gap
	local width = math.min(needed, bottom.w)
	return {
		row = {
			x = math.floor(bottom.x + (bottom.w - width) / 2),
			y = math.floor(bottom.y + bottom.h - slot),
			w = width,
			h = slot,
		},
		slot = slot,
		gap = gap,
		scroll = needed > bottom.w,
	}
end

-- How the animal card reacts: the Visuals.UI preset played on the portrait, the floating text
-- and its popup style, and the Feedback event fired when the caller passes a context.
export type Reaction = { preset: string, text: string, popup: string, event: string? }

local REACTIONS: { [string]: Reaction } = {
	eat = { preset = "Bounce", text = "Yum!", popup = "heal", event = "FeedAnimal" },
	happy = { preset = "Wiggle", text = "Happy!", popup = "heal" },
	full = { preset = "Pulse", text = "Full!", popup = "currency" },
	refuse = { preset = "Error", text = "No thanks", popup = "damage" },
}

ScreensLogic.REACTIONS = REACTIONS

-- Animation choice -------------------------------------------------------------------------------

local ANIMATIONS: { [string]: { open: string, close: string } } = {
	window = { open = "ModalIn", close = "ModalOut" },
	dialog = { open = "PopIn", close = "PopOut" },
	hud = { open = "SlideInUp", close = "SlideOutDown" },
	overlay = { open = "FadeIn", close = "FadeOut" },
	banner = { open = "SlideInDown", close = "SlideOutUp" },
	sheet = { open = "DrawerIn", close = "DrawerOut" },
	fullscreen = { open = "FadeIn", close = "FadeOut" },
}

ScreensLogic.SCREEN_KINDS = table.freeze({ "window", "dialog", "hud", "overlay", "banner", "sheet", "fullscreen" })

-- The Visuals.UI preset that opens (or closes) a screen of `kind`. Under reduced motion every
-- screen fades (Visuals.UI would turn travel into a fade anyway; this keeps the choice explicit).
function ScreensLogic.animation(kind: string, opening: boolean, reducedMotion: boolean?): string
	if reducedMotion then
		return if opening then "FadeIn" else "FadeOut"
	end
	local pair = ANIMATIONS[kind] or ANIMATIONS.window
	return if opening then pair.open else pair.close
end

-- Focus ------------------------------------------------------------------------------------------

export type Focus = { order: { string }, links: SpatialNav.Graph, first: string? }

-- Reading order (top to bottom, then left to right) and directional links for keyboard and
-- gamepad. Nodes on roughly the same line count as one row.
function ScreensLogic.focus(nodes: { SpatialNav.Node }, wrap: boolean?): Focus
	local sorted = table.clone(nodes)
	table.sort(sorted, function(a: SpatialNav.Node, b: SpatialNav.Node): boolean
		local ay = a.y + a.h / 2
		local by = b.y + b.h / 2
		local tolerance = math.min(a.h, b.h) / 2
		if math.abs(ay - by) > tolerance then
			return ay < by
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.id < b.id
	end)
	local order: { string } = {}
	for _, node in ipairs(sorted) do
		table.insert(order, node.id)
	end
	return { order = order, links = SpatialNav.build(nodes, { wrap = wrap == true }), first = order[1] }
end

-- Prop validation --------------------------------------------------------------------------------

local COMMON_PROPS: { [string]: string } = {
	parent = "any",
	style = "string",
	theme = "string",
	displayOrder = "number",
	insets = "table",
	input = "string",
	startOpen = "boolean",
}

ScreensLogic.COMMON_PROPS = COMMON_PROPS

local function typeMatches(value: any, expected: string): boolean
	if expected == "any" then
		return true
	elseif expected == "list" then
		return type(value) == "table"
	end
	return type(value) == expected
end

-- Checks `props` against the screen's entry in ScreensData and returns a copy with defaults
-- filled in, plus every problem found ("pets is required", "today must be a number").
function ScreensLogic.check(name: string, props: any): ({ [string]: any }, { string })
	local issues: { string } = {}
	local def = ScreensData.get(name)
	if def == nil then
		return {}, { "unknown screen " .. tostring(name) }
	end
	if props ~= nil and type(props) ~= "table" then
		return {}, { "props must be a table" }
	end
	local given: { [string]: any } = props or {}
	local out: { [string]: any } = table.clone(given)
	local known: { [string]: boolean } = {}
	for _, prop in ipairs(def.props) do
		known[prop.name] = true
		local value = given[prop.name]
		if value == nil then
			if prop.required then
				table.insert(issues, prop.name .. " is required")
			elseif prop.default ~= nil then
				out[prop.name] = prop.default
			end
		elseif not typeMatches(value, prop.type) then
			table.insert(issues, string.format("%s must be a %s", prop.name, prop.type))
		elseif prop.type == "list" and prop.required and #value == 0 then
			table.insert(issues, prop.name .. " must not be empty")
		end
	end
	local extra: { string } = {}
	for key, value in pairs(given) do
		if type(key) ~= "string" then
			table.insert(extra, tostring(key))
		elseif COMMON_PROPS[key] ~= nil then
			if not typeMatches(value, COMMON_PROPS[key]) then
				table.insert(issues, string.format("%s must be a %s", key, COMMON_PROPS[key]))
			end
		elseif not known[key] then
			table.insert(extra, key)
		end
	end
	table.sort(extra)
	for _, key in ipairs(extra) do
		table.insert(issues, "unknown prop " .. key)
	end
	return out, issues
end

-- Shared helpers for view models -----------------------------------------------------------------

function ScreensLogic.rarityRank(rarity: any): number
	if type(rarity) ~= "string" then
		return 0
	end
	return table.find(ScreensLogic.RARITIES, string.lower(rarity)) or 0
end

-- value / max as 0..1 (0 when max is not positive).
function ScreensLogic.fraction(value: any, max: any): number
	local top = number(max, 0)
	if top <= 0 then
		return 0
	end
	return clamp01(number(value, 0) / top)
end

-- Whether `balance` covers `cost`. `balance` is a number, or a table of currency -> amount.
function ScreensLogic.affordable(cost: any, balance: any, currency: string?): boolean
	local price = number(cost, 0)
	local have = balance
	if type(balance) == "table" then
		have = balance[currency or "default"]
	end
	return number(have, 0) >= price
end

-- Pet selection, inventory and collection --------------------------------------------------------

-- PetSelection: the entries Pets.selection takes, with ids checked and a valid selection.
function ScreensLogic.petSelection(props: { [string]: any }): { pets: { any }, selected: string?, issues: { string } }
	local issues: { string } = {}
	local pets: { any } = {}
	local seen: { [string]: boolean } = {}
	for i, pet in ipairs(list(props.pets)) do
		if type(pet) ~= "table" or type(pet.id) ~= "string" or pet.id == "" then
			table.insert(issues, string.format("pets[%d] needs an id", i))
		elseif seen[pet.id] then
			table.insert(issues, "duplicate pet id " .. pet.id)
		else
			seen[pet.id] = true
			local copy = table.clone(pet)
			copy.name = if type(pet.name) == "string" and pet.name ~= "" then pet.name else pet.id
			table.insert(pets, copy)
		end
	end
	if #pets < 2 then
		table.insert(issues, "pets needs at least two entries")
	end
	local selected: string? = nil
	if type(props.selected) == "string" and seen[props.selected] then
		selected = props.selected
	end
	return { pets = pets, selected = selected, issues = issues }
end

export type InventoryView = {
	pets: { any }, -- filtered and sorted
	filters: { { id: string, count: number } }, -- "all" then each rarity present
	filter: string,
	selected: any?,
	equipped: number,
	equipMax: number,
	canEquip: boolean, -- the selected pet could be equipped (a slot is free)
	total: number,
}

-- PetInventory: filter by rarity, sort (equipped first, then rarest, then name) and the detail state.
function ScreensLogic.petInventory(props: { [string]: any }): InventoryView
	local all = list(props.pets)
	local counts: { [string]: number } = {}
	local equipped = 0
	for _, pet in ipairs(all) do
		local rarity = if type(pet.rarity) == "string" then string.lower(pet.rarity) else "common"
		counts[rarity] = (counts[rarity] or 0) + 1
		if pet.equipped == true then
			equipped += 1
		end
	end
	local filters: { { id: string, count: number } } = { { id = "all", count = #all } }
	for _, rarity in ipairs(ScreensLogic.RARITIES) do
		if counts[rarity] ~= nil then
			table.insert(filters, { id = rarity, count = counts[rarity] })
		end
	end
	local filter = if type(props.filter) == "string" and counts[string.lower(props.filter)] ~= nil
		then string.lower(props.filter)
		else "all"
	local pets: { any } = {}
	for _, pet in ipairs(all) do
		local rarity = if type(pet.rarity) == "string" then string.lower(pet.rarity) else "common"
		if filter == "all" or rarity == filter then
			table.insert(pets, pet)
		end
	end
	table.sort(pets, function(a: any, b: any): boolean
		local ae, be = a.equipped == true, b.equipped == true
		if ae ~= be then
			return ae
		end
		local ar, br = ScreensLogic.rarityRank(a.rarity), ScreensLogic.rarityRank(b.rarity)
		if ar ~= br then
			return ar > br
		end
		local an, bn = tostring(a.name or a.id), tostring(b.name or b.id)
		if an ~= bn then
			return an < bn
		end
		return tostring(a.id) < tostring(b.id)
	end)
	local selected: any = nil
	for _, pet in ipairs(all) do
		if pet.id == props.selected then
			selected = pet
		end
	end
	local equipMax = math.max(0, math.floor(number(props.equipMax, 3)))
	return {
		pets = pets,
		filters = filters,
		filter = filter,
		selected = selected,
		equipped = equipped,
		equipMax = equipMax,
		canEquip = selected ~= nil and selected.equipped ~= true and equipped < equipMax,
		total = #all,
	}
end

-- Collection: discovered count and completion (0..1 and whole percent, rounded down so 100 %
-- only shows when everything is found).
function ScreensLogic.collection(entries: any): { discovered: number, total: number, fraction: number, percent: number }
	local total, found = 0, 0
	for _, entry in ipairs(list(entries)) do
		total += 1
		if type(entry) == "table" and entry.discovered == true then
			found += 1
		end
	end
	local fraction = if total > 0 then found / total else 0
	return { discovered = found, total = total, fraction = fraction, percent = math.floor(fraction * 100) }
end

-- Eggs -------------------------------------------------------------------------------------------

-- "0.5%", "12%", "<0.01%".
function ScreensLogic.chanceText(percent: number): string
	if percent <= 0 then
		return "0%"
	elseif percent < 0.01 then
		return "<0.01%"
	elseif percent < 1 then
		return (string.gsub(string.format("%.2f", percent), "0+$", "")) .. "%"
	elseif percent < 10 and math.floor(percent) ~= percent then
		return string.format("%.1f%%", percent)
	end
	return string.format("%d%%", math.floor(percent + 0.5))
end

-- An egg's odds list: chances scaled to 100 %, rarest first, with display text. The numbers are
-- shown as given by the caller; the server rolls the result.
function ScreensLogic.odds(
	entries: any
): { { name: string, rarity: string?, chance: number, text: string, icon: any, image: any } }
	local total = 0
	for _, entry in ipairs(list(entries)) do
		total += math.max(0, number(entry.chance, 0))
	end
	local out = {}
	for _, entry in ipairs(list(entries)) do
		local chance = math.max(0, number(entry.chance, 0))
		local percent = if total > 0 then chance / total * 100 else 0
		table.insert(out, {
			name = tostring(entry.name or entry.id or "?"),
			rarity = if type(entry.rarity) == "string" then string.lower(entry.rarity) else nil,
			chance = percent,
			text = ScreensLogic.chanceText(percent),
			icon = entry.icon,
			image = entry.image,
		})
	end
	table.sort(out, function(a: any, b: any): boolean
		if a.chance ~= b.chance then
			return a.chance < b.chance
		end
		return a.name < b.name
	end)
	return out
end

export type EggView = {
	eggs: { any },
	selected: any?,
	counts: { { count: number, affordable: boolean, text: string } },
	auto: boolean,
	issues: { string },
}

-- EggHatching: the selected egg, its odds and which hatch buttons the player can afford with
-- `balance` (a hint for the button state; the server checks again).
function ScreensLogic.eggHatching(props: { [string]: any }): EggView
	local issues: { string } = {}
	local eggs: { any } = {}
	local selected: any = nil
	for i, egg in ipairs(list(props.eggs)) do
		if type(egg) ~= "table" or type(egg.id) ~= "string" then
			table.insert(issues, string.format("eggs[%d] needs an id", i))
		else
			local copy = table.clone(egg)
			copy.name = if type(egg.name) == "string" then egg.name else egg.id
			copy.odds = ScreensLogic.odds(egg.odds)
			copy.price = math.max(0, number(egg.price, 0))
			table.insert(eggs, copy)
			if egg.id == props.selected then
				selected = copy
			end
		end
	end
	selected = selected or eggs[1]
	local counts = {}
	for _, raw in ipairs(list(props.counts)) do
		local count = math.max(1, math.floor(number(raw, 1)))
		local price = if selected ~= nil then selected.price * count else 0
		table.insert(counts, {
			count = count,
			affordable = selected ~= nil
				and (props.balance == nil or ScreensLogic.affordable(price, props.balance, selected.currency)),
			text = if count == 1 then "HATCH" else "HATCH x" .. tostring(count),
		})
	end
	return { eggs = eggs, selected = selected, counts = counts, auto = props.auto == true, issues = issues }
end

-- Tapping HUD and animals ------------------------------------------------------------------------

-- "x2", "x2.5", "x1.25K" style multiplier text.
function ScreensLogic.multiplierText(multiplier: any): string
	local value = math.max(0, number(multiplier, 1))
	if value >= 1000 then
		return string.format("x%.2fK", value / 1000)
	elseif math.floor(value) == value then
		return string.format("x%d", value)
	end
	return "x" .. (string.gsub(string.format("%.2f", value), "0+$", ""))
end

export type TapView = {
	currencies: { any },
	multiplier: string,
	rebirth: { value: number, max: number, fraction: number, ready: boolean }?,
	menu: { any },
	issues: { string },
}

function ScreensLogic.tappingHud(props: { [string]: any }): TapView
	local issues: { string } = {}
	local currencies: { any } = {}
	local seen: { [string]: boolean } = {}
	for i, currency in ipairs(list(props.currencies)) do
		if type(currency) ~= "table" or type(currency.id) ~= "string" then
			table.insert(issues, string.format("currencies[%d] needs an id", i))
		elseif seen[currency.id] then
			table.insert(issues, "duplicate currency id " .. currency.id)
		else
			seen[currency.id] = true
			local copy = table.clone(currency)
			copy.value = number(currency.value, 0)
			table.insert(currencies, copy)
		end
	end
	local menu: { any } = {}
	for i, item in ipairs(list(props.menu)) do
		if type(item) ~= "table" or type(item.id) ~= "string" then
			table.insert(issues, string.format("menu[%d] needs an id", i))
		else
			table.insert(menu, item)
		end
	end
	local rebirth = nil
	if type(props.rebirth) == "table" then
		local value = math.max(0, number(props.rebirth.value, 0))
		local max = math.max(1, number(props.rebirth.max, 1))
		rebirth = { value = value, max = max, fraction = clamp01(value / max), ready = value >= max }
	end
	return {
		currencies = currencies,
		multiplier = ScreensLogic.multiplierText(props.multiplier),
		rebirth = rebirth,
		menu = menu,
		issues = issues,
	}
end

type Word = { min: number, text: string }
local MOODS: { Word } = {
	{ min = 0.75, text = "Happy" },
	{ min = 0.5, text = "Content" },
	{ min = 0.25, text = "Grumpy" },
	{ min = 0, text = "Sad" },
}
local HUNGER: { Word } = {
	{ min = 0.75, text = "Full" },
	{ min = 0.4, text = "Peckish" },
	{ min = 0.15, text = "Hungry" },
	{ min = 0, text = "Starving" },
}

local function label(words: { Word }, value: number): string
	for _, word in ipairs(words) do
		if value >= word.min then
			return word.text
		end
	end
	return words[#words].text
end

export type AnimalView = {
	name: string,
	mood: number, -- 0..1
	moodText: string,
	hunger: number, -- 0..1, how full the animal is
	hungerText: string,
	foods: { any },
	selected: any?, -- the food that would be thrown
	canThrow: boolean,
	issues: { string },
}

-- AnimalInteraction: clamped bars, their words and which food is selected. Food with a count of
-- 0 cannot be selected or thrown.
function ScreensLogic.animalInteraction(props: { [string]: any }): AnimalView
	local issues: { string } = {}
	local animal: any = if type(props.animal) == "table" then props.animal else {}
	local mood = clamp01(number(animal.mood, 0.5))
	local hunger = clamp01(number(animal.hunger, 0.5))
	local foods: { any } = {}
	local selected: any = nil
	for i, food in ipairs(list(props.foods)) do
		if type(food) ~= "table" or type(food.id) ~= "string" then
			table.insert(issues, string.format("foods[%d] needs an id", i))
		else
			local copy = table.clone(food)
			copy.count = if food.count == nil then nil else math.max(0, math.floor(number(food.count, 0)))
			copy.available = copy.count == nil or copy.count > 0
			table.insert(foods, copy)
			if food.id == props.selectedFood and copy.available then
				selected = copy
			end
		end
	end
	if selected == nil then
		for _, food in ipairs(foods) do
			if food.available then
				selected = food
				break
			end
		end
	end
	return {
		name = tostring(animal.name or "Animal"),
		mood = mood,
		moodText = if type(animal.moodText) == "string" then animal.moodText else label(MOODS, mood),
		hunger = hunger,
		hungerText = label(HUNGER, hunger),
		foods = foods,
		selected = selected,
		canThrow = selected ~= nil and props.canThrow ~= false,
		issues = issues,
	}
end

-- Daily rewards ----------------------------------------------------------------------------------

export type DayView = { day: number, state: string, reward: any }

-- States for a reward track: days before `today` are "claimed", `today` is "today" until
-- `claimed` is true, later days are "locked". `today` wraps around the track, so day 8 of a
-- 7-day track is day 1 again.
function ScreensLogic.dailyRewards(props: { [string]: any }): {
	days: { DayView },
	today: number,
	canClaim: boolean,
	streak: number,
}
	local days: { DayView } = {}
	local rewards = list(props.days)
	local count = #rewards
	local raw = math.max(1, math.floor(number(props.today, 1)))
	local today = if count > 0 then ((raw - 1) % count) + 1 else 1
	local claimed = props.claimed == true
	for i, reward in ipairs(rewards) do
		local state = "locked"
		if i < today or (i == today and claimed) then
			state = "claimed"
		elseif i == today then
			state = "today"
		end
		table.insert(days, { day = i, state = state, reward = reward })
	end
	return {
		days = days,
		today = today,
		canClaim = count > 0 and not claimed,
		streak = math.max(0, math.floor(number(props.streak, raw - (if claimed then 0 else 1)))),
	}
end

-- Spin wheel -------------------------------------------------------------------------------------

export type Segment = { index: number, start: number, sweep: number, centre: number, weight: number, data: any }
export type Wheel = { segments: { Segment }, count: number }

-- Segment angles for a wheel. Segments are equal unless they carry a `weight`, which only changes
-- how wide a segment is drawn: it is not a probability (the server decides the result).
function ScreensLogic.wheel(segments: any): Wheel
	local entries = list(segments)
	local total = 0
	local weights: { number } = {}
	for i, entry in ipairs(entries) do
		local weight = if type(entry) == "table" then number(entry.weight, 1) else 1
		weights[i] = if weight > 0 then weight else 1
		total += weights[i]
	end
	local out: { Segment } = {}
	local start = 0
	for i, entry in ipairs(entries) do
		local sweep = weights[i] / total * 360
		table.insert(out, {
			index = i,
			start = start,
			sweep = sweep,
			centre = start + sweep / 2,
			weight = weights[i],
			data = entry,
		})
		start += sweep
	end
	return { segments = out, count = #out }
end

-- The segment under the pointer when the wheel has turned `rotation` degrees clockwise.
function ScreensLogic.segmentAt(wheel: Wheel, rotation: number): number?
	local angle = -rotation % 360
	for _, segment in ipairs(wheel.segments) do
		if angle >= segment.start and angle < segment.start + segment.sweep then
			return segment.index
		end
	end
	return if wheel.count > 0 then wheel.count else nil
end

export type LandOptions = {
	from: number?, -- current rotation, default 0
	turns: number?, -- extra full turns before stopping, default 5
	offset: number?, -- -0.4..0.4 of the segment's width away from its centre (for variety), default 0
}

-- The rotation to stop at so that segment `index` sits under the pointer: always at least
-- `turns` full turns clockwise past `from`. Returns nil for an index the wheel does not have.
function ScreensLogic.landingAngle(wheel: Wheel, index: number, options: LandOptions?): number?
	local segment = wheel.segments[index]
	if segment == nil then
		return nil
	end
	local opts: LandOptions = options or {}
	local from = number(opts.from, 0)
	local turns = math.max(0, number(opts.turns, 5))
	local offset = math.clamp(number(opts.offset, 0), -0.4, 0.4)
	local target = segment.centre + offset * segment.sweep
	local base = -target % 360
	local minimum = from + turns * 360
	local k = math.ceil((minimum - base) / 360)
	return base + 360 * k
end

export type SpinPlan = {
	from: number,
	to: number,
	windup: number, -- degrees the wheel pulls back first (anticipation)
	windupTime: number,
	spinTime: number,
	overshoot: number, -- degrees past the target before settling back
	settleTime: number,
	total: number,
	instant: boolean, -- reduced motion: jump to the result
}

export type SpinOptions = {
	windup: number?,
	windupTime: number?,
	duration: number?, -- seconds of the main spin; default grows with the distance
	overshoot: number?,
	settleTime: number?,
	sweep: number?, -- width of the target segment: the overshoot stays inside it
	reducedMotion: boolean?,
}

-- Timing for a spin from `from` to `to`: a short pull back, a spin that only ever slows down, and
-- a small overshoot that settles onto the target.
function ScreensLogic.spinPlan(from: number, to: number, options: SpinOptions?): SpinPlan
	local opts: SpinOptions = options or {}
	local distance = math.max(0, to - from)
	local overshoot = math.max(0, number(opts.overshoot, 4))
	if opts.sweep ~= nil then
		overshoot = math.min(overshoot, opts.sweep * 0.08)
	end
	local windup = math.max(0, number(opts.windup, 14))
	local windupTime = math.max(0, number(opts.windupTime, 0.28))
	local spinTime = math.max(0.1, number(opts.duration, math.clamp(2.4 + distance / 360 * 0.3, 3, 6.5)))
	local settleTime = math.max(0, number(opts.settleTime, 0.45))
	local instant = opts.reducedMotion == true or distance <= 0
	return {
		from = from,
		to = to,
		windup = windup,
		windupTime = windupTime,
		spinTime = spinTime,
		overshoot = overshoot,
		settleTime = settleTime,
		total = if instant then 0 else windupTime + spinTime + settleTime,
		instant = instant,
	}
end

-- Rotation at `t` seconds into the plan, and the phase: "windup", "spin", "settle" or "done".
function ScreensLogic.spinAngle(plan: SpinPlan, t: number): (number, string)
	if plan.instant or t >= plan.total then
		return plan.to, "done"
	end
	if t < plan.windupTime then
		local u = math.max(0, t) / plan.windupTime
		return plan.from - plan.windup * (1 - (1 - u) * (1 - u)), "windup"
	end
	local start = plan.from - plan.windup
	local peak = plan.to + plan.overshoot
	local spinT = t - plan.windupTime
	if spinT < plan.spinTime then
		local u = spinT / plan.spinTime
		local inv = 1 - u
		-- Cubic ease-out: the speed 3 (1 - u)^2 falls all the way to zero.
		return start + (peak - start) * (1 - inv * inv * inv), "spin"
	end
	local u = if plan.settleTime > 0 then (spinT - plan.spinTime) / plan.settleTime else 1
	local inv = 1 - u
	return plan.to + plan.overshoot * inv * inv * math.cos(u * math.pi), "settle"
end

-- Leaderboard ------------------------------------------------------------------------------------

export type Rank = { rank: number, id: any, name: string, value: number, highlight: boolean, entry: any }

-- Orders entries by value (highest first; ties by name, then id), gives equal values the same
-- rank, keeps the top `limit` and returns the local player's row separately so it can be pinned
-- when it is below the visible rows.
function ScreensLogic.leaderboard(
	entries: any,
	localId: any,
	limit: number?
): {
	rows: { Rank },
	localRow: Rank?,
	pinned: boolean, -- the local player is ranked but not in `rows`
	total: number,
}
	local rows: { Rank } = {}
	for _, entry in ipairs(list(entries)) do
		if type(entry) == "table" then
			table.insert(rows, {
				rank = 0,
				id = entry.id,
				name = tostring(entry.name or entry.id or "?"),
				value = number(entry.value, 0),
				highlight = localId ~= nil and entry.id == localId,
				entry = entry,
			})
		end
	end
	table.sort(rows, function(a: Rank, b: Rank): boolean
		if a.value ~= b.value then
			return a.value > b.value
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return tostring(a.id) < tostring(b.id)
	end)
	local localRow: Rank? = nil
	for i, row in ipairs(rows) do
		local previous = rows[i - 1]
		row.rank = if previous ~= nil and previous.value == row.value then previous.rank else i
		if row.highlight then
			localRow = row
		end
	end
	local max = math.max(1, math.floor(limit or 50))
	local visible: { Rank } = {}
	local localVisible = false
	for i = 1, math.min(max, #rows) do
		visible[i] = rows[i]
		if rows[i].highlight then
			localVisible = true
		end
	end
	return { rows = visible, localRow = localRow, pinned = localRow ~= nil and not localVisible, total = #rows }
end

-- Upgrades, rebirth and unlocks ------------------------------------------------------------------

export type UpgradeView = {
	id: any,
	level: number,
	maxLevel: number,
	maxed: boolean,
	cost: number?, -- nil when maxed
	affordable: boolean,
	pips: { boolean }, -- one per level, true when reached (at most 10 pips; longer tracks are scaled)
	fraction: number,
	entry: any,
}

-- Upgrade rows: level pips and whether `balance` covers the next level's cost. `cost` is a number
-- for the next level, or `costs` lists the cost of each level (costs[level + 1] is the next one).
function ScreensLogic.upgrades(upgrades: any, balance: any): { UpgradeView }
	local out: { UpgradeView } = {}
	for _, entry in ipairs(list(upgrades)) do
		if type(entry) == "table" then
			local maxLevel = math.max(1, math.floor(number(entry.maxLevel, 5)))
			local level = math.clamp(math.floor(number(entry.level, 0)), 0, maxLevel)
			local maxed = level >= maxLevel
			local cost: number? = nil
			if not maxed then
				local costs = entry.costs
				cost = if type(costs) == "table" then number(costs[level + 1], 0) else number(entry.cost, 0)
			end
			local shown = math.min(maxLevel, 10)
			local reached = math.floor(level / maxLevel * shown + 1e-6)
			local pips: { boolean } = {}
			for i = 1, shown do
				pips[i] = i <= reached
			end
			table.insert(out, {
				id = entry.id,
				level = level,
				maxLevel = maxLevel,
				maxed = maxed,
				cost = cost,
				affordable = cost ~= nil and ScreensLogic.affordable(cost, balance, entry.currency),
				pips = pips,
				fraction = level / maxLevel,
				entry = entry,
			})
		end
	end
	return out
end

-- Rebirth: progress toward the cost, the multiplier before and after, and whether the confirm
-- control is enabled. All from the caller's numbers.
function ScreensLogic.rebirth(props: { [string]: any }): {
	fraction: number,
	affordable: boolean,
	multiplier: string,
	nextMultiplier: string,
	gain: number,
	missing: number,
}
	local current = math.max(0, number(props.current, 0))
	local cost = math.max(0, number(props.cost, 0))
	local multiplier = math.max(0, number(props.multiplier, 1))
	local nextMultiplier = math.max(0, number(props.nextMultiplier, multiplier + 1))
	return {
		fraction = if cost > 0 then clamp01(current / cost) else 1,
		affordable = current >= cost,
		multiplier = ScreensLogic.multiplierText(multiplier),
		nextMultiplier = ScreensLogic.multiplierText(nextMultiplier),
		gain = nextMultiplier - multiplier,
		missing = math.max(0, cost - current),
	}
end

-- How far a hold-to-confirm has filled after `held` seconds of `required`.
function ScreensLogic.holdFraction(held: number, required: number): (number, boolean)
	if required <= 0 then
		return 1, true
	end
	local fraction = clamp01(held / required)
	return fraction, fraction >= 1
end

-- Settings ---------------------------------------------------------------------------------------

ScreensLogic.QUALITY_OPTIONS = table.freeze({ "Auto", "Low", "Medium", "High", "Ultra" })

-- The Visuals section of the settings screen as UI/Core/SettingsSchema entries, with the current
-- Visuals settings ({ level, adaptive, reducedMotion, reducedFlashing, intensity }) as defaults.
function ScreensLogic.visualsSchema(settings: { [string]: any }?): { { [string]: any } }
	local current: { [string]: any } = settings or {}
	local level = if type(current.level) == "string"
			and table.find(ScreensLogic.QUALITY_OPTIONS, current.level) ~= nil
		then current.level
		else "High"
	return {
		{
			key = "uvkQuality",
			kind = "dropdown",
			label = "Effects quality",
			section = "Visuals",
			default = if current.adaptive == true then "Auto" else level,
			options = table.clone(ScreensLogic.QUALITY_OPTIONS),
		},
		{
			key = "uvkIntensity",
			kind = "slider",
			label = "Effects intensity",
			section = "Visuals",
			default = math.clamp(number(current.intensity, 1), 0, 1.5),
			min = 0,
			max = 1.5,
			step = 0.05,
		},
		{
			key = "uvkReducedMotion",
			kind = "toggle",
			label = "Reduce motion",
			section = "Visuals",
			default = current.reducedMotion == true,
		},
		{
			key = "uvkReducedFlashing",
			kind = "toggle",
			label = "Reduce flashing",
			section = "Visuals",
			default = current.reducedFlashing == true,
		},
	}
end

-- The Visuals.Configure table for a change to one of the visualsSchema keys (nil for other keys
-- and for values of the wrong type).
function ScreensLogic.visualsConfig(key: string, value: any): { [string]: any }?
	if key == "uvkQuality" then
		if value == "Auto" then
			return { adaptive = true }
		elseif type(value) == "string" and table.find(ScreensLogic.QUALITY_OPTIONS, value) ~= nil then
			return { quality = value, adaptive = false }
		end
	elseif key == "uvkIntensity" then
		if type(value) == "number" and value == value then
			return { intensity = math.clamp(value, 0, 1.5) }
		end
	elseif key == "uvkReducedMotion" then
		if type(value) == "boolean" then
			return { reducedMotion = value }
		end
	elseif key == "uvkReducedFlashing" then
		if type(value) == "boolean" then
			return { reducedFlashing = value }
		end
	end
	return nil
end

-- Quests and achievements ------------------------------------------------------------------------

local QUEST_ORDER: { [string]: number } = { claimable = 1, active = 2, claimed = 3 }

function ScreensLogic.questState(quest: any): string
	if quest.state == "claimed" or quest.claimed == true then
		return "claimed"
	elseif quest.state == "claimable" or quest.state == "active" then
		return quest.state
	end
	local max = math.max(1, number(quest.max, 1))
	return if number(quest.value, 0) >= max then "claimable" else "active"
end

-- Quests of one tab (nil: all), ordered claimable first, then active by progress (closest to done
-- first), then claimed. Equal quests keep the order they were given in.
function ScreensLogic.quests(
	quests: any,
	tab: string?
): { { state: string, fraction: number, quest: any, order: number } }
	local out: { { state: string, fraction: number, quest: any, order: number } } = {}
	for i, quest in ipairs(list(quests)) do
		if type(quest) == "table" and (tab == nil or quest.tab == nil or quest.tab == tab) then
			table.insert(out, {
				state = ScreensLogic.questState(quest),
				fraction = ScreensLogic.fraction(quest.value, quest.max or 1),
				quest = quest,
				order = i,
			})
		end
	end
	table.sort(out, function(a: any, b: any): boolean
		local sa, sb = QUEST_ORDER[a.state], QUEST_ORDER[b.state]
		if sa ~= sb then
			return sa < sb
		end
		if a.state == "active" and a.fraction ~= b.fraction then
			return a.fraction > b.fraction
		end
		return a.order < b.order
	end)
	return out
end

-- How many quests of each tab can be claimed (for tab badges).
function ScreensLogic.claimableByTab(quests: any): { [string]: number }
	local counts: { [string]: number } = {}
	for _, quest in ipairs(list(quests)) do
		if type(quest) == "table" and ScreensLogic.questState(quest) == "claimable" then
			local tab = tostring(quest.tab or "all")
			counts[tab] = (counts[tab] or 0) + 1
		end
	end
	return counts
end

function ScreensLogic.achievements(entries: any): { unlocked: number, total: number, fraction: number, percent: number }
	local total, unlocked = 0, 0
	for _, entry in ipairs(list(entries)) do
		if type(entry) == "table" then
			total += 1
			if entry.unlocked == true or (entry.unlocked == nil and number(entry.tier, 0) > 0) then
				unlocked += 1
			end
		end
	end
	local fraction = if total > 0 then unlocked / total else 0
	return { unlocked = unlocked, total = total, fraction = fraction, percent = math.floor(fraction * 100) }
end

-- Shop -------------------------------------------------------------------------------------------

-- Products of one tab (products without a tab show in every tab) and the valid active tab.
function ScreensLogic.shop(props: { [string]: any }): { tab: string?, tabs: { any }, products: { any } }
	local tabs = list(props.tabs)
	local tab: string? = nil
	for _, entry in ipairs(tabs) do
		if type(entry) == "table" and entry.id == props.tab then
			tab = entry.id
		end
	end
	if tab == nil and type(tabs[1]) == "table" then
		tab = tabs[1].id
	end
	local products: { any } = {}
	for _, product in ipairs(list(props.products)) do
		if type(product) == "table" and (tab == nil or product.tab == nil or product.tab == tab) then
			table.insert(products, product)
		end
	end
	return { tab = tab, tabs = tabs, products = products }
end

-- Trading ----------------------------------------------------------------------------------------

local function offerMap(offer: any): { [string]: number }
	local map: { [string]: number } = {}
	for _, item in ipairs(list(offer)) do
		if type(item) == "table" and item.id ~= nil then
			local id = tostring(item.id)
			map[id] = (map[id] or 0) + math.max(1, math.floor(number(item.count, 1)))
		end
	end
	return map
end

export type TradeDiff = {
	added: { { id: string, count: number } },
	removed: { { id: string, count: number } },
	changed: boolean,
	summary: string, -- "+2 added, 1 removed" or "No changes"
}

-- What changed between two versions of one side's offer (ids and counts), so the screen can flag
-- a changed offer before the player confirms.
function ScreensLogic.tradeDiff(before: any, after: any): TradeDiff
	local old, new = offerMap(before), offerMap(after)
	local added: { { id: string, count: number } } = {}
	local removed: { { id: string, count: number } } = {}
	local addedCount, removedCount = 0, 0
	for id, count in pairs(new) do
		local delta = count - (old[id] or 0)
		if delta > 0 then
			table.insert(added, { id = id, count = delta })
			addedCount += delta
		end
	end
	for id, count in pairs(old) do
		local delta = count - (new[id] or 0)
		if delta > 0 then
			table.insert(removed, { id = id, count = delta })
			removedCount += delta
		end
	end
	local function byId(a: { id: string, count: number }, b: { id: string, count: number }): boolean
		return a.id < b.id
	end
	table.sort(added, byId)
	table.sort(removed, byId)
	local parts: { string } = {}
	if addedCount > 0 then
		table.insert(parts, string.format("+%d added", addedCount))
	end
	if removedCount > 0 then
		table.insert(parts, string.format("%d removed", removedCount))
	end
	return {
		added = added,
		removed = removed,
		changed = addedCount + removedCount > 0,
		summary = if #parts > 0 then table.concat(parts, ", ") else "No changes",
	}
end

-- The phase of a trade for the footer: "editing" until both sides are ready, "countdown" while
-- `countdown` seconds remain, then "confirm". Presentation only: the server owns the real state.
function ScreensLogic.tradePhase(myReady: any, theirReady: any, countdown: any): (string, number)
	if myReady ~= true or theirReady ~= true then
		return "editing", 0
	end
	local seconds = math.max(0, number(countdown, 0))
	if seconds > 0 then
		return "countdown", math.ceil(seconds)
	end
	return "confirm", 0
end

-- Hotbar -----------------------------------------------------------------------------------------

export type Cooldown = { fraction: number, remaining: number, ready: boolean, text: string }

-- Cooldown overlay state: `fraction` is how much of the slot is still covered (1 just used, 0 ready).
function ScreensLogic.cooldown(remaining: any, duration: any): Cooldown
	local total = math.max(0, number(duration, 0))
	local left = math.clamp(number(remaining, 0), 0, if total > 0 then total else math.huge)
	if left <= 0 or total <= 0 then
		return { fraction = 0, remaining = 0, ready = true, text = "" }
	end
	local text = if left >= 10
		then tostring(math.ceil(left))
		elseif left >= 1 then tostring(math.ceil(left))
		else string.format("%.1f", left)
	return { fraction = clamp01(left / total), remaining = left, ready = false, text = text }
end

-- Cooldowns for every slot at time `now`: a slot is { id, readyAt?, duration? } (clock seconds).
function ScreensLogic.hotbar(slots: any, now: number): { [string]: Cooldown }
	local out: { [string]: Cooldown } = {}
	for _, slot in ipairs(list(slots)) do
		if type(slot) == "table" and slot.id ~= nil then
			out[tostring(slot.id)] = ScreensLogic.cooldown(number(slot.readyAt, 0) - now, slot.duration)
		end
	end
	return out
end

-- Combat progression -----------------------------------------------------------------------------

-- Skills in unlock order with their state: "unlocked", "available" (level reached, not unlocked
-- yet) or "locked".
function ScreensLogic.skills(skills: any, level: any): { { state: string, skill: any, order: number } }
	local current = number(level, 1)
	local out: { { state: string, skill: any, order: number } } = {}
	for i, skill in ipairs(list(skills)) do
		if type(skill) == "table" then
			local state = "locked"
			if skill.unlocked == true then
				state = "unlocked"
			elseif current >= number(skill.level, 1) then
				state = "available"
			end
			table.insert(out, { state = state, skill = skill, order = i })
		end
	end
	table.sort(out, function(a: any, b: any): boolean
		local la, lb = number(a.skill.level, 1), number(b.skill.level, 1)
		if la ~= lb then
			return la < lb
		end
		return a.order < b.order
	end)
	return out
end

-- Tutorial ---------------------------------------------------------------------------------------

-- The four dim rectangles around a highlighted `target` (a cutout made of frames), clipped to
-- `bounds`, and the hole itself after `padding`.
function ScreensLogic.cutout(
	bounds: Rect,
	target: Rect,
	padding: number?
): { top: Rect, bottom: Rect, left: Rect, right: Rect, hole: Rect }
	local pad = padding or 8
	local x0 = math.clamp(target.x - pad, bounds.x, bounds.x + bounds.w)
	local y0 = math.clamp(target.y - pad, bounds.y, bounds.y + bounds.h)
	local x1 = math.clamp(target.x + target.w + pad, x0, bounds.x + bounds.w)
	local y1 = math.clamp(target.y + target.h + pad, y0, bounds.y + bounds.h)
	return {
		top = { x = bounds.x, y = bounds.y, w = bounds.w, h = y0 - bounds.y },
		bottom = { x = bounds.x, y = y1, w = bounds.w, h = bounds.y + bounds.h - y1 },
		left = { x = bounds.x, y = y0, w = x0 - bounds.x, h = y1 - y0 },
		right = { x = x1, y = y0, w = bounds.x + bounds.w - x1, h = y1 - y0 },
		hole = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 },
	}
end

-- Where a coach-mark bubble of `size` goes next to `hole`: the side with the most room, kept
-- inside `bounds`.
function ScreensLogic.coachMark(bounds: Rect, hole: Rect, size: Size, gap: number?): (Rect, string)
	local space = gap or 12
	local room: { { side: string, space: number } } = {
		{ side = "bottom", space = bounds.y + bounds.h - (hole.y + hole.h) - size.y },
		{ side = "top", space = hole.y - bounds.y - size.y },
		{ side = "right", space = bounds.x + bounds.w - (hole.x + hole.w) - size.x },
		{ side = "left", space = hole.x - bounds.x - size.x },
	}
	local side, best = "bottom", -math.huge
	for _, entry in ipairs(room) do
		if entry.space > best then
			side, best = entry.side, entry.space
		end
	end
	local x = hole.x + hole.w / 2 - size.x / 2
	local y = hole.y + hole.h / 2 - size.y / 2
	if side == "bottom" then
		y = hole.y + hole.h + space
	elseif side == "top" then
		y = hole.y - space - size.y
	elseif side == "right" then
		x = hole.x + hole.w + space
	else
		x = hole.x - space - size.x
	end
	local maxX = math.max(bounds.x, bounds.x + bounds.w - size.x)
	local maxY = math.max(bounds.y, bounds.y + bounds.h - size.y)
	return { x = math.clamp(x, bounds.x, maxX), y = math.clamp(y, bounds.y, maxY), w = size.x, h = size.y }, side
end

return ScreensLogic
