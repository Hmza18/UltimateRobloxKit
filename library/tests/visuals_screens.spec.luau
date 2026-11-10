--!strict
-- Screen templates: the pure half. Responsive layout for the five reference viewports (nothing
-- overflows, touch targets stay at 44 px, sensible columns), prop validation for every
-- implemented screen, the per-screen view models, registry metadata and the list of screens
-- against the files on disk.

local fs = require("@lune/fs")
local Registry = require("../src/Visuals/Core/Registry")
local IconData = require("../src/Icons/IconData")
local Quality = require("../src/Visuals/Core/Quality")
local ScreensData = require("../src/Visuals/Screens/ScreensData")
local ScreensLogic = require("../src/Visuals/Screens/ScreensLogic")
local SettingsSchema = require("../src/UI/Core/SettingsSchema")
local UIPresets = require("../src/Visuals/UI/UIPresets")
local t = require("./lib/t")

local MIN = ScreensLogic.MIN_TOUCH

local function envs(): { ScreensLogic.Env }
	local out: { ScreensLogic.Env } = {}
	for _, viewport in ipairs(ScreensLogic.VIEWPORTS) do
		table.insert(out, ScreensLogic.env({ x = viewport.x, y = viewport.y }, nil, viewport.input))
	end
	return out
end

local function label(env: ScreensLogic.Env, what: string): string
	return string.format("%s at %dx%d", what, env.viewport.x, env.viewport.y)
end

local function windowRect(window: ScreensLogic.Window): ScreensLogic.Rect
	return { x = window.x, y = window.y, w = window.w, h = window.h }
end

-- Valid props for every implemented screen (check() must accept them as they are).
local EXAMPLES: { [string]: { [string]: any } } = {
	PetSelection = {
		pets = { { id = "ember", name = "Ember", rarity = "Rare" }, { id = "moss" }, { id = "drift", name = "Drift" } },
		selected = "moss",
	},
	EggHatching = {
		eggs = {
			{
				id = "basic",
				name = "Basic Egg",
				price = 100,
				odds = {
					{ name = "Cat", chance = 60, rarity = "common" },
					{ name = "Fox", chance = 30, rarity = "rare" },
					{ name = "Dragon", chance = 10, rarity = "legendary" },
				},
			},
			{ id = "gold", name = "Golden Egg", price = 5000, odds = { { name = "Lion", chance = 1 } } },
		},
		counts = { 1, 3 },
		balance = 250,
	},
	RewardReveal = { rewards = { { rarity = "Legendary", name = "Sun Fox" } } },
	TappingHud = {
		currencies = { { id = "coins", icon = "coin-color", value = 120 }, { id = "gems", value = 3 } },
		multiplier = 2.5,
		rebirth = { value = 40, max = 100 },
		menu = { { id = "shop", icon = "shop-color" }, { id = "pets", icon = "paw-color" } },
	},
	AnimalInteraction = {
		animal = { name = "Daisy", mood = 0.8, hunger = 0.2 },
		foods = { { id = "hay", count = 3 }, { id = "apple", count = 0 }, { id = "carrot" } },
	},
	Shop = {
		tabs = { { id = "pets", text = "PETS" }, { id = "boosts", text = "BOOSTS" } },
		products = {
			{
				id = "cat",
				tab = "pets",
				title = "CAT",
				price = { kind = "currency", amount = 100, currency = "coin-color" },
			},
		},
	},
	PremiumShop = {
		bundles = { { id = "gems", title = "GEMS", price = { kind = "robux", amount = 99, productId = 0 } } },
		featured = { title = "STARTER", price = { kind = "robux", amount = 49, productId = 0 } },
		cta = { text = "GO PREMIUM" },
	},
	DailyRewards = {
		days = { "100 Coins", { text = "Rare Egg", icon = "egg-color", premium = true }, "500 Coins" },
		today = 2,
	},
	PetInventory = {
		pets = { { id = "p1", name = "Ember", rarity = "Rare", equipped = true }, { id = "p2", name = "Moss" } },
		selected = "p2",
	},
	SpinWheel = { segments = { "10", "50", { text = "Egg", icon = "egg-color", weight = 2 }, "100" }, spins = 2 },
	QuestLog = {
		quests = {
			{ id = "hatch", tab = "daily", title = "HATCH 10", value = 4, max = 10 },
			{ id = "walk", tab = "weekly", title = "WALK", value = 5, max = 5 },
		},
	},
	Achievements = {
		achievements = {
			{ id = "collector", title = "COLLECTOR", tier = 1, value = 20, max = 50 },
			{ id = "rich", title = "RICH" },
		},
	},
	Settings = {
		schema = {
			{ key = "music", kind = "slider", label = "Music", default = 0.5, min = 0, max = 1, section = "Audio" },
			{ key = "trades", kind = "toggle", label = "Allow trades", default = true },
		},
		values = { music = 0.8 },
	},
	Leaderboard = {
		entries = { { id = 1, name = "Amy", value = 900 }, { id = 2, name = "Bob", value = 400 } },
		localId = 2,
		tabs = { { id = "coins", text = "COINS" }, { id = "pets", text = "PETS" } },
	},
	Rebirth = { current = 250, cost = 1000, multiplier = 2, keeps = { "Pets" }, loses = { "Coins" } },
	LevelUp = { level = 12, xp = { value = 20, max = 300 }, rewards = { { icon = "coin-color", amount = "x500" } } },
	Loading = { title = "PET WORLD", tips = { "Hatch eggs to find rare pets" }, progress = 0.2 },
	Welcome = {
		title = "PET WORLD",
		subtitle = "Season 2",
		news = { { id = "update", title = "NEW AREA", text = "The volcano is open" } },
	},
	Tutorial = {
		steps = {
			{ text = "Tap the big button", target = { x = 100, y = 200, w = 80, h = 80 } },
			{ title = "Done", text = "Have fun" },
		},
	},
	AreaUnlock = { area = { name = "Volcano", description = "Hot pets live here" }, cost = 5000, balance = 9000 },
	Collection = {
		entries = {
			{ id = "cat", name = "Cat", discovered = true, rarity = "common" },
			{ id = "dragon", name = "Dragon" },
		},
	},
	UpgradeShop = {
		upgrades = {
			{ id = "speed", title = "SPEED", level = 2, maxLevel = 5, cost = 300 },
			{ id = "luck", title = "LUCK", level = 5, maxLevel = 5 },
		},
		balance = 500,
	},
	Trading = {
		mine = { { id = "cat", icon = "paw-color" } },
		theirs = { { id = "gem", count = 5 } },
		partner = { name = "Amy" },
		myReady = true,
	},
	AbilityHotbar = {
		slots = {
			{ id = "dash", icon = "energy-color", keybind = "Q" },
			{ id = "heal", keybind = "E", remaining = 2, duration = 8 },
		},
	},
	CombatProgression = {
		level = 6,
		xp = { value = 40, max = 200 },
		stats = { { id = "atk", value = 12, prefix = "ATK" } },
		skills = {
			{ id = "dash", title = "DASH", level = 1, unlocked = true },
			{ id = "heal", title = "HEAL", level = 5 },
		},
	},
}

return {
	-- Environment ------------------------------------------------------------------------------

	["the five reference viewports classify as expected"] = function()
		local got: { string } = {}
		for _, env in ipairs(envs()) do
			table.insert(got, env.breakpoint)
		end
		t.deepEqual(got, { "desktop", "desktop", "tablet", "phone", "phone" })
		local list = envs()
		t.falsy(list[4].portrait, "844x390 is landscape")
		t.truthy(list[5].portrait, "390x844 is portrait")
		t.equal(ScreensLogic.env({ x = 1920, y = 1080 }, nil, "gamepad").breakpoint, "console")
		t.equal(ScreensLogic.env({ x = 1920, y = 1080 }, nil, "nonsense").input, "mouse")
	end,

	["the safe area removes the insets and text never goes below the minimum"] = function()
		local env = ScreensLogic.env({ x = 844, y = 390 }, { top = 0, left = 47, right = 47, bottom = 21 }, "touch")
		t.deepEqual(env.safe, { x = 47, y = 0, w = 750, h = 369 })
		t.equal(ScreensLogic.textSize(env, 12), ScreensLogic.MIN_TEXT)
		t.truthy(ScreensLogic.textSize(env, 32) < 32, "phones scale large text down")
		local desktop = ScreensLogic.env({ x = 1920, y = 1080 })
		t.equal(ScreensLogic.textSize(desktop, 32), 32)
		t.truthy(
			ScreensLogic.textSize(ScreensLogic.env({ x = 1920, y = 1080 }, nil, "gamepad"), 32) > 32,
			"ten-foot text grows"
		)
	end,

	-- Windows ----------------------------------------------------------------------------------

	["every window kind fits inside the safe area on every viewport"] = function()
		for _, env in ipairs(envs()) do
			for _, kind in ipairs(ScreensLogic.WINDOW_KINDS) do
				local window = ScreensLogic.window(env, kind)
				t.truthy(
					ScreensLogic.contains(env.safe, windowRect(window)),
					label(env, kind .. " inside the safe area")
				)
				t.truthy(window.header >= MIN, label(env, kind .. " header holds a 44 px close button"))
				t.truthy(window.w >= 240 and window.h >= 200, label(env, kind .. " is usable"))
			end
		end
	end,

	["windows respect notches and never exceed a tiny viewport"] = function()
		local insets = { top = 0, left = 59, right = 59, bottom = 21 }
		local env = ScreensLogic.env({ x = 844, y = 390 }, insets, "touch")
		local window = ScreensLogic.window(env, "wide")
		t.truthy(ScreensLogic.contains(env.safe, windowRect(window)), "inside the notch-safe area")
		t.truthy(window.fullscreen, "phones give windows the whole safe area")
		local tiny = ScreensLogic.env({ x = 200, y = 150 }, nil, "touch")
		local small = ScreensLogic.window(tiny, "window")
		t.truthy(small.w <= 200 and small.h <= 150, "never larger than the viewport")
	end,

	["desktop windows are centred and capped; dialogs are smaller than windows"] = function()
		local env = ScreensLogic.env({ x = 1920, y = 1080 })
		local window = ScreensLogic.window(env, "window")
		t.equal(window.w, 820)
		t.near(window.x + window.w / 2, 960, 1)
		t.near(window.y + window.h / 2, 540, 1)
		local dialog = ScreensLogic.window(env, "dialog")
		t.truthy(dialog.w < window.w and dialog.h < window.h)
		t.falsy(window.fullscreen)
	end,

	["navigation is a bottom bar, a sidebar or top tabs depending on the device"] = function()
		local list = envs()
		t.equal(ScreensLogic.navigation(list[1], 4), "top")
		t.equal(ScreensLogic.navigation(list[1], 7), "sidebar")
		t.equal(ScreensLogic.navigation(list[2], 7), "top")
		t.equal(ScreensLogic.navigation(list[3], 4), "top")
		t.equal(ScreensLogic.navigation(list[4], 4), "sidebar")
		t.equal(ScreensLogic.navigation(list[5], 4), "bottom")
		t.equal(ScreensLogic.navigation(list[5], 1), "none")
		t.equal(ScreensLogic.navigation(list[1], 0), "none")
	end,

	["navigation and content share the window without overlapping"] = function()
		for _, env in ipairs(envs()) do
			for _, kind in ipairs({ "window", "wide" }) do
				local window = ScreensLogic.window(env, kind)
				local bounds: ScreensLogic.Rect =
					{ x = 0, y = window.header, w = window.w, h = window.h - window.header }
				for _, tabs in ipairs({ 0, 2, 4, 7 }) do
					local body = ScreensLogic.body(env, window, tabs)
					local what = string.format("%s with %d tabs", kind, tabs)
					t.truthy(ScreensLogic.contains(bounds, body.content), label(env, what .. ": content inside"))
					t.truthy(body.content.w >= 150 and body.content.h >= 100, label(env, what .. ": content usable"))
					local nav = body.nav
					if tabs <= 1 then
						t.equal(nav, nil, "no navigation without tabs")
					elseif nav ~= nil then
						t.truthy(ScreensLogic.contains(bounds, nav), label(env, what .. ": nav inside"))
						t.falsy(
							ScreensLogic.intersects(nav, body.content),
							label(env, what .. ": nav clear of content")
						)
						t.truthy(body.tab.x >= MIN and body.tab.y >= MIN, label(env, what .. ": tab is a touch target"))
						if not body.navScroll then
							local along = if body.navigation == "sidebar" then nav.h else nav.w
							local size = if body.navigation == "sidebar" then body.tab.y else body.tab.x
							t.truthy(tabs * size + (tabs - 1) * 6 <= along + 0.5, label(env, what .. ": tabs fit"))
						end
					else
						error("navigation rect missing")
					end
				end
			end
		end
	end,

	-- Grids ------------------------------------------------------------------------------------

	["card grids never overflow their width and keep 44 px cells on every viewport"] = function()
		for _, env in ipairs(envs()) do
			local window = ScreensLogic.window(env, "wide")
			local body = ScreensLogic.body(env, window, 3)
			for kind in pairs(ScreensLogic.CARDS) do
				local grid = ScreensLogic.cards(kind, body.content.w, 24, body.content.h)
				local what = label(env, kind .. " grid")
				t.truthy(grid.width <= body.content.w, what .. " fits its width")
				t.equal(grid.width, grid.columns * grid.cellW + (grid.columns - 1) * grid.gap)
				t.truthy(grid.cellW >= MIN and grid.cellH >= MIN, what .. " cells are touch targets")
				t.truthy(grid.columns >= 1 and grid.columns <= 8, what .. " column count")
				t.equal(grid.rows, math.ceil(24 / grid.columns))
				t.equal(grid.scroll, grid.contentHeight > body.content.h, what .. " scrolls instead of overflowing")
			end
		end
	end,

	["pet cards get sensible columns per device"] = function()
		local columns: { number } = {}
		for _, env in ipairs(envs()) do
			local body = ScreensLogic.body(env, ScreensLogic.window(env, "wide"), 0)
			table.insert(columns, ScreensLogic.cards("pet", body.content.w, 12).columns)
		end
		t.truthy(columns[1] >= 5, "1080p shows a wide grid")
		t.truthy(columns[2] >= 4, "laptop")
		t.truthy(columns[3] >= 4, "tablet")
		t.truthy(columns[4] >= 4, "phone landscape")
		t.equal(columns[5], 2, "phone portrait shows two columns")
	end,

	["grid options: forced columns shrink until a finger fits, maxCell caps, empty grids are empty"] = function()
		local narrow = ScreensLogic.grid(150, { minColumns = 4, minCell = 44 })
		t.truthy(narrow.cellW >= MIN, "cells stay touchable")
		t.truthy(narrow.columns < 4, "columns were dropped")
		t.truthy(narrow.width <= 150)
		local capped = ScreensLogic.grid(1000, { minCell = 100, maxCell = 120, maxColumns = 4 })
		t.equal(capped.columns, 4)
		t.equal(capped.cellW, 120)
		local empty = ScreensLogic.grid(600, { count = 0 })
		t.equal(empty.rows, 0)
		t.equal(empty.contentHeight, 0)
		t.falsy(empty.scroll)
		local tall = ScreensLogic.grid(300, { minCell = 100, aspect = 0.5, count = 5, height = 200 })
		t.equal(tall.cellH, tall.cellW * 2)
		t.truthy(tall.scroll)
		local sliver = ScreensLogic.grid(30, {})
		t.equal(sliver.columns, 1)
		t.truthy(sliver.width <= 30, "a sliver never overflows")
	end,

	["rows keep the touch height and report overflow"] = function()
		local rows = ScreensLogic.rows(10, 30, 4, 200)
		t.equal(rows.rowHeight, MIN)
		t.equal(rows.contentHeight, 10 * MIN + 9 * 4)
		t.truthy(rows.scroll)
		t.falsy(ScreensLogic.rows(2, 52, 8, 400).scroll)
		t.equal(ScreensLogic.rows(0, 52).contentHeight, 0)
		t.truthy(ScreensLogic.overflows(101, 100))
		t.falsy(ScreensLogic.overflows(100, 100))
	end,

	["split puts panes side by side when both fit and stacks them otherwise"] = function()
		local wide = ScreensLogic.split({ x = 0, y = 0, w = 900, h = 500 })
		t.equal(wide.mode, "columns")
		t.equal(wide.primary.w + wide.secondary.w + 8, 900)
		t.falsy(ScreensLogic.intersects(wide.primary, wide.secondary))
		local narrow = ScreensLogic.split({ x = 0, y = 0, w = 370, h = 700 })
		t.equal(narrow.mode, "stack")
		t.equal(narrow.primary.w, 370)
		t.equal(narrow.primary.h + narrow.secondary.h + 8, 700)
		t.falsy(ScreensLogic.intersects(narrow.primary, narrow.secondary))
		for _, env in ipairs(envs()) do
			local body = ScreensLogic.body(env, ScreensLogic.window(env, "wide"), 0)
			local split = ScreensLogic.split(body.content)
			t.truthy(ScreensLogic.contains(body.content, split.primary), label(env, "primary pane inside"))
			t.truthy(ScreensLogic.contains(body.content, split.secondary), label(env, "secondary pane inside"))
		end
	end,

	-- HUD --------------------------------------------------------------------------------------

	["HUD regions stay inside the safe area and keep the centre clear"] = function()
		for _, env in ipairs(envs()) do
			local hud = ScreensLogic.hud(env)
			t.truthy(
				hud.clear.w >= env.safe.w * 0.4 and hud.clear.h >= env.safe.h * 0.45,
				label(env, "clear centre size")
			)
			for name, region in pairs(hud.regions) do
				local what = label(env, "region " .. name)
				t.truthy(ScreensLogic.contains(env.safe, region), what .. " inside the safe area")
				t.falsy(ScreensLogic.intersects(region, hud.clear), what .. " leaves the centre clear")
				t.truthy(region.w >= MIN and region.h >= MIN, what .. " can hold a touch target")
				for corner, reserved in pairs(hud.reserved) do
					t.falsy(ScreensLogic.intersects(region, reserved), what .. " avoids " .. corner)
				end
			end
		end
	end,

	["touch HUDs leave the bottom corners to the thumbstick and jump button"] = function()
		for _, env in ipairs(envs()) do
			local hud = ScreensLogic.hud(env)
			if env.input == "touch" then
				t.equal(hud.regions.bottomLeft, nil, label(env, "no bottom-left region"))
				t.equal(hud.regions.bottomRight, nil, label(env, "no bottom-right region"))
				t.truthy(hud.reserved.bottomLeft ~= nil and hud.reserved.bottomRight ~= nil)
				local bottom = hud.regions.bottom
				t.truthy(
					bottom.x >= hud.reserved.bottomLeft.x + hud.reserved.bottomLeft.w,
					"bottom starts after the thumbstick"
				)
				t.truthy(bottom.x + bottom.w <= hud.reserved.bottomRight.x, "bottom ends before the jump button")
			else
				t.truthy(hud.regions.bottomLeft ~= nil and hud.regions.bottomRight ~= nil, "mouse HUDs use the corners")
				t.equal(next(hud.reserved), nil)
			end
		end
	end,

	["HUD regions respect insets"] = function()
		local insets = { top = 36, left = 59, right = 59, bottom = 21 }
		local env = ScreensLogic.env({ x = 844, y = 390 }, insets, "touch")
		local hud = ScreensLogic.hud(env)
		for name, region in pairs(hud.regions) do
			t.truthy(ScreensLogic.contains(env.safe, region), name .. " inside the inset safe area")
		end
	end,

	["HUD buttons are between 44 and 72 px"] = function()
		t.equal(ScreensLogic.hudButton({ x = 0, y = 0, w = 220, h = 129 }, 2, true), 61)
		t.equal(ScreensLogic.hudButton({ x = 0, y = 0, w = 220, h = 129 }, 6, true), MIN)
		t.equal(ScreensLogic.hudButton({ x = 0, y = 0, w = 500, h = 500 }, 2, false), 72)
	end,

	["the tapping HUD places its parts clear of the centre and the touch controls"] = function()
		for _, env in ipairs(envs()) do
			local hud = ScreensLogic.hud(env)
			local layout = ScreensLogic.tapLayout(env, 3, 2)
			local parts: { [string]: ScreensLogic.Rect } = {
				tap = layout.tap,
				rebirth = layout.rebirth,
				counters = layout.counters,
				multiplier = layout.multiplier,
				menu = layout.menu,
			}
			for name, rect in pairs(parts) do
				local what = label(env, name)
				t.truthy(ScreensLogic.contains(env.safe, rect), what .. " inside the safe area")
				t.falsy(ScreensLogic.intersects(rect, hud.clear), what .. " leaves the centre clear")
				for corner, reserved in pairs(hud.reserved) do
					t.falsy(ScreensLogic.intersects(rect, reserved), what .. " avoids " .. corner)
				end
			end
			t.truthy(
				layout.tap.w >= MIN and layout.tap.w == layout.tap.h,
				label(env, "tap button is a square touch target")
			)
			t.truthy(layout.tap.w <= 128)
			t.falsy(
				ScreensLogic.intersects(layout.tap, layout.rebirth),
				label(env, "rebirth bar clear of the tap button")
			)
			t.falsy(
				ScreensLogic.intersects(layout.multiplier, layout.counters),
				label(env, "multiplier clear of counters")
			)
			t.truthy(layout.menuButton >= MIN, label(env, "menu buttons are touch targets"))
			t.equal(layout.menuScroll, 3 * layout.menuButton + 12 > layout.menu.h)
		end
		local portrait = ScreensLogic.tapLayout(envs()[5], 2, 3)
		t.truthy(portrait.countersVertical, "three counters stack on a portrait phone")
		t.falsy(ScreensLogic.tapLayout(envs()[1], 2, 3).countersVertical)
	end,

	["the ability hotbar fits the bottom region with touch-sized slots"] = function()
		for _, env in ipairs(envs()) do
			local hud = ScreensLogic.hud(env)
			for _, count in ipairs({ 1, 4, 6, 10 }) do
				local layout = ScreensLogic.hotbarLayout(env, count)
				local what = label(env, string.format("%d slots", count))
				t.truthy(layout.slot >= MIN and layout.slot <= 64, what .. ": slot size")
				t.truthy(
					ScreensLogic.contains(hud.regions.bottom, layout.row),
					what .. ": row inside the bottom region"
				)
				t.falsy(ScreensLogic.intersects(layout.row, hud.clear), what .. ": clear of the centre")
				for corner, reserved in pairs(hud.reserved) do
					t.falsy(ScreensLogic.intersects(layout.row, reserved), what .. ": avoids " .. corner)
				end
				local needed = count * layout.slot + (count - 1) * layout.gap
				t.equal(layout.scroll, needed > hud.regions.bottom.w, what .. ": scrolls instead of overflowing")
				if not layout.scroll then
					t.equal(layout.row.w, needed)
				end
			end
		end
		t.falsy(ScreensLogic.hotbarLayout(envs()[1], 6).scroll, "six slots fit on a desktop")
	end,

	-- Animation and focus ----------------------------------------------------------------------

	["every screen kind opens and closes with a registered Visuals UI preset"] = function()
		for _, kind in ipairs(ScreensLogic.SCREEN_KINDS) do
			local open = ScreensLogic.animation(kind, true)
			local close = ScreensLogic.animation(kind, false)
			t.truthy(UIPresets.registry:has(open), kind .. " open preset " .. open)
			t.truthy(UIPresets.registry:has(close), kind .. " close preset " .. close)
			t.truthy(open ~= close)
			t.equal(ScreensLogic.animation(kind, true, true), "FadeIn")
			t.equal(ScreensLogic.animation(kind, false, true), "FadeOut")
		end
		t.equal(ScreensLogic.animation("window", true), "ModalIn")
		t.equal(ScreensLogic.animation("dialog", false), "PopOut")
		t.equal(ScreensLogic.animation("unknown", true), "ModalIn")
		for _, screen in ipairs(ScreensData.all()) do
			t.truthy(table.find(ScreensLogic.SCREEN_KINDS, screen.kind) ~= nil, screen.id .. " has a known kind")
		end
	end,

	["focus order reads rows top to bottom and links neighbours"] = function()
		local nodes = {
			{ id = "c", x = 220, y = 12, w = 100, h = 100 },
			{ id = "a", x = 0, y = 10, w = 100, h = 100 },
			{ id = "b", x = 110, y = 8, w = 100, h = 100 },
			{ id = "confirm", x = 60, y = 300, w = 200, h = 56 },
			{ id = "d", x = 0, y = 120, w = 100, h = 100 },
		}
		local focus = ScreensLogic.focus(nodes)
		t.deepEqual(focus.order, { "a", "b", "c", "d", "confirm" })
		t.equal(focus.first, "a")
		t.equal(focus.links.a.right, "b")
		t.equal(focus.links.b.left, "a")
		t.equal(focus.links.a.down, "d")
		t.equal(focus.links.d.down, "confirm")
		t.equal(focus.links.confirm.up, "d")
		local empty = ScreensLogic.focus({})
		t.equal(empty.first, nil)
		t.equal(#empty.order, 0)
	end,

	-- Props ------------------------------------------------------------------------------------

	["every implemented screen accepts its example props and fills defaults"] = function()
		for _, name in ipairs(ScreensData.names()) do
			local example = EXAMPLES[name]
			t.truthy(example ~= nil, "the spec has example props for " .. name)
			local props, issues = ScreensLogic.check(name, example)
			t.equal(#issues, 0, name .. ": " .. table.concat(issues, "; "))
			local def = ScreensData.get(name) :: ScreensData.Screen
			for _, prop in ipairs(def.props) do
				if prop.default ~= nil and example[prop.name] == nil then
					t.equal(props[prop.name], prop.default, name .. "." .. prop.name .. " default")
				end
			end
			t.falsy(props == example, "check returns a copy")
		end
	end,

	["check reports missing, mistyped and unknown props"] = function()
		for _, name in ipairs(ScreensData.names()) do
			local def = ScreensData.get(name) :: ScreensData.Screen
			local _, issues = ScreensLogic.check(name, {})
			for _, prop in ipairs(def.props) do
				if prop.required then
					t.truthy(table.find(issues, prop.name .. " is required") ~= nil, name .. " requires " .. prop.name)
				end
			end
			local wrong = table.clone(EXAMPLES[name])
			wrong.colour = "red"
			wrong.style = 5
			local _, problems = ScreensLogic.check(name, wrong)
			t.truthy(table.find(problems, "unknown prop colour") ~= nil, name .. " rejects unknown props")
			t.truthy(table.find(problems, "style must be a string") ~= nil, name .. " checks common props")
		end
		local _, typed = ScreensLogic.check("TappingHud", { currencies = "coins", multiplier = "2" })
		t.truthy(table.find(typed, "currencies must be a list") ~= nil)
		t.truthy(table.find(typed, "multiplier must be a number") ~= nil)
		local _, emptyList = ScreensLogic.check("TappingHud", { currencies = {} })
		t.truthy(table.find(emptyList, "currencies must not be empty") ~= nil)
		local _, unknown = ScreensLogic.check("Nope", {})
		t.deepEqual(unknown, { "unknown screen Nope" })
		local _, notTable = ScreensLogic.check("TappingHud", 5)
		t.deepEqual(notTable, { "props must be a table" })
		local common, none = ScreensLogic.check("RewardReveal", {
			rewards = { { rarity = "Rare", name = "Gem" } },
			style = "scifi",
			theme = "SciFi",
			displayOrder = 3,
			startOpen = true,
			insets = { top = 0, left = 0, right = 0, bottom = 0 },
			input = "touch",
		})
		t.equal(#none, 0, "common props are accepted on every screen")
		t.equal(common.style, "scifi")
	end,

	-- View models: P0 --------------------------------------------------------------------------

	["pet selection keeps valid entries, names them and validates the selection"] = function()
		local view = ScreensLogic.petSelection(EXAMPLES.PetSelection)
		t.equal(#view.issues, 0)
		t.equal(#view.pets, 3)
		t.equal(view.pets[2].name, "moss", "a pet without a name shows its id")
		t.equal(view.selected, "moss")
		t.equal(ScreensLogic.petSelection({ pets = EXAMPLES.PetSelection.pets, selected = "ghost" }).selected, nil)
		local bad = ScreensLogic.petSelection({ pets = { { id = "a" }, { id = "a" }, { name = "x" } } })
		t.truthy(table.find(bad.issues, "duplicate pet id a") ~= nil)
		t.truthy(table.find(bad.issues, "pets[3] needs an id") ~= nil)
		t.truthy(table.find(bad.issues, "pets needs at least two entries") ~= nil)
	end,

	["egg odds are scaled to 100 %, rarest first, with readable text"] = function()
		local odds = ScreensLogic.odds({
			{ name = "Cat", chance = 120, rarity = "Common" },
			{ name = "Dragon", chance = 1, rarity = "legendary" },
			{ name = "Fox", chance = 79 },
		})
		t.equal(odds[1].name, "Dragon")
		t.equal(odds[1].text, "0.5%")
		t.equal(odds[1].rarity, "legendary")
		t.equal(odds[3].name, "Cat")
		t.equal(odds[3].text, "60%")
		t.equal(odds[3].rarity, "common")
		local total = 0
		for _, entry in ipairs(odds) do
			total += entry.chance
		end
		t.near(total, 100, 1e-6)
		t.equal(ScreensLogic.chanceText(0), "0%")
		t.equal(ScreensLogic.chanceText(0.001), "<0.01%")
		t.equal(ScreensLogic.chanceText(0.25), "0.25%")
		t.equal(ScreensLogic.chanceText(2.5), "2.5%")
		t.equal(ScreensLogic.chanceText(12.4), "12%")
		t.equal(#ScreensLogic.odds(nil), 0)
	end,

	["the egg stand selects an egg and flags the hatch sizes the balance covers"] = function()
		local view = ScreensLogic.eggHatching(EXAMPLES.EggHatching)
		t.equal(#view.issues, 0)
		t.equal(view.selected.id, "basic", "the first egg is selected by default")
		t.equal(#view.selected.odds, 3)
		t.deepEqual(view.counts, {
			{ count = 1, affordable = true, text = "HATCH" },
			{ count = 3, affordable = false, text = "HATCH x3" },
		})
		local gold = table.clone(EXAMPLES.EggHatching)
		gold.selected = "gold"
		t.equal(ScreensLogic.eggHatching(gold).selected.id, "gold")
		t.falsy(ScreensLogic.eggHatching(gold).counts[1].affordable)
		local unknown = table.clone(EXAMPLES.EggHatching)
		unknown.balance = nil
		t.truthy(ScreensLogic.eggHatching(unknown).counts[2].affordable, "without a balance every button is enabled")
		local wallets = table.clone(EXAMPLES.EggHatching)
		wallets.balance = { default = 1000 }
		t.truthy(ScreensLogic.eggHatching(wallets).counts[2].affordable, "a currency table works too")
		local bad = ScreensLogic.eggHatching({ eggs = { { name = "No id" } }, counts = { 1 } })
		t.truthy(table.find(bad.issues, "eggs[1] needs an id") ~= nil)
		t.equal(bad.selected, nil)
		t.falsy(bad.counts[1].affordable)
	end,

	["the tapping HUD normalises counters, multiplier text and rebirth progress"] = function()
		local view = ScreensLogic.tappingHud(EXAMPLES.TappingHud)
		t.equal(#view.issues, 0)
		t.equal(#view.currencies, 2)
		t.equal(view.currencies[2].value, 3)
		t.equal(view.multiplier, "x2.5")
		t.near((view.rebirth :: any).fraction, 0.4, 1e-9)
		t.falsy((view.rebirth :: any).ready)
		t.truthy((ScreensLogic.tappingHud({ currencies = {}, rebirth = { value = 9, max = 5 } }).rebirth :: any).ready)
		t.equal(ScreensLogic.tappingHud({ currencies = {} }).rebirth, nil)
		t.equal(ScreensLogic.multiplierText(1), "x1")
		t.equal(ScreensLogic.multiplierText(1.25), "x1.25")
		t.equal(ScreensLogic.multiplierText(2500), "x2.50K")
		t.equal(ScreensLogic.multiplierText(nil), "x1")
		local bad =
			ScreensLogic.tappingHud({ currencies = { { id = "a" }, { id = "a" }, {} }, menu = { { icon = "x" } } })
		t.truthy(table.find(bad.issues, "duplicate currency id a") ~= nil)
		t.truthy(table.find(bad.issues, "currencies[3] needs an id") ~= nil)
		t.truthy(table.find(bad.issues, "menu[1] needs an id") ~= nil)
	end,

	["the animal card clamps its bars and only selects food that is in stock"] = function()
		local view = ScreensLogic.animalInteraction(EXAMPLES.AnimalInteraction)
		t.equal(#view.issues, 0)
		t.equal(view.name, "Daisy")
		t.equal(view.moodText, "Happy")
		t.equal(view.hungerText, "Hungry")
		t.equal(view.selected.id, "hay")
		t.truthy(view.canThrow)
		t.falsy(view.foods[2].available, "a count of 0 is out of stock")
		t.truthy(view.foods[3].available, "no count means unlimited")
		local pick = table.clone(EXAMPLES.AnimalInteraction)
		pick.selectedFood = "apple"
		t.equal(ScreensLogic.animalInteraction(pick).selected.id, "hay", "out-of-stock food cannot be selected")
		pick.selectedFood = "carrot"
		t.equal(ScreensLogic.animalInteraction(pick).selected.id, "carrot")
		pick.canThrow = false
		t.falsy(ScreensLogic.animalInteraction(pick).canThrow)
		local wild =
			ScreensLogic.animalInteraction({ animal = { mood = 7, hunger = -2 }, foods = { { id = "x", count = 0 } } })
		t.equal(wild.mood, 1)
		t.equal(wild.hunger, 0)
		t.equal(wild.hungerText, "Starving")
		t.equal(wild.selected, nil)
		t.falsy(wild.canThrow, "nothing in stock, nothing to throw")
		for kind, reaction in pairs(ScreensLogic.REACTIONS) do
			t.truthy(UIPresets.registry:has(reaction.preset), kind .. " uses a registered preset")
		end
	end,

	-- View models: the rest --------------------------------------------------------------------

	["daily reward states: claimed before today, today until claimed, locked after"] = function()
		local days = { "a", "b", "c", "d", "e", "f", "g" }
		local function states(props: { [string]: any }): string
			local out: { string } = {}
			for _, day in ipairs(ScreensLogic.dailyRewards(props).days) do
				table.insert(out, string.sub(day.state, 1, 1))
			end
			return table.concat(out)
		end
		t.equal(states({ days = days, today = 1 }), "tllllll")
		t.equal(states({ days = days, today = 3 }), "cctllll")
		t.equal(states({ days = days, today = 3, claimed = true }), "ccclll" .. "l")
		t.equal(states({ days = days, today = 7, claimed = true }), "ccccccc")
		t.equal(states({ days = days, today = 8 }), "tllllll", "day 8 of a 7-day track is day 1 again")
		t.equal(states({ days = days }), "tllllll")
		local view = ScreensLogic.dailyRewards({ days = days, today = 3 })
		t.equal(view.today, 3)
		t.truthy(view.canClaim)
		t.equal(view.streak, 2)
		t.equal(view.days[3].reward, "c")
		local claimed = ScreensLogic.dailyRewards({ days = days, today = 3, claimed = true })
		t.falsy(claimed.canClaim)
		t.equal(claimed.streak, 3)
		t.equal(ScreensLogic.dailyRewards({ days = days, today = 3, streak = 40 }).streak, 40)
		local empty = ScreensLogic.dailyRewards({})
		t.equal(#empty.days, 0)
		t.falsy(empty.canClaim)
	end,

	["wheel segments cover the circle; weights only change the drawn width"] = function()
		local wheel = ScreensLogic.wheel({ "a", "b", "c", "d", "e", "f", "g", "h" })
		t.equal(wheel.count, 8)
		t.equal(wheel.segments[1].start, 0)
		t.equal(wheel.segments[1].sweep, 45)
		t.equal(wheel.segments[3].centre, 112.5)
		t.equal(wheel.segments[8].start + wheel.segments[8].sweep, 360)
		local weighted = ScreensLogic.wheel({ { weight = 1 }, { weight = 3 }, { weight = -5 }, {} })
		t.near(weighted.segments[2].sweep, 180, 1e-9)
		t.near(weighted.segments[3].sweep, 60, 1e-9, "a bad weight counts as 1")
		local total = 0
		for _, segment in ipairs(weighted.segments) do
			total += segment.sweep
		end
		t.near(total, 360, 1e-9)
		t.equal(ScreensLogic.wheel(nil).count, 0)
	end,

	["the wheel lands on the requested segment after the extra turns"] = function()
		local wheels = {
			ScreensLogic.wheel({ 1, 2, 3, 4, 5, 6, 7, 8 }),
			ScreensLogic.wheel({ 1, 2, 3 }),
			ScreensLogic.wheel({ { weight = 1 }, { weight = 5 }, { weight = 2 }, { weight = 0.5 } }),
			ScreensLogic.wheel({ 1 }),
		}
		for w, wheel in ipairs(wheels) do
			for index = 1, wheel.count do
				for _, from in ipairs({ 0, 37.5, 725, -90 }) do
					for _, turns in ipairs({ 0, 3, 5 }) do
						for _, offset in ipairs({ 0, -0.4, 0.4 }) do
							local options = { from = from, turns = turns, offset = offset }
							local angle = ScreensLogic.landingAngle(wheel, index, options) :: number
							local what = string.format(
								"wheel %d index %d from %g turns %d offset %g",
								w,
								index,
								from,
								turns,
								offset
							)
							t.equal(ScreensLogic.segmentAt(wheel, angle), index, what)
							t.truthy(angle >= from + turns * 360, what .. ": spins at least the extra turns")
							t.truthy(angle < from + turns * 360 + 360, what .. ": and less than one more")
						end
					end
				end
			end
		end
		t.equal(ScreensLogic.landingAngle(wheels[1], 9), nil, "an index the wheel does not have")
		t.equal(ScreensLogic.landingAngle(wheels[1], 0), nil)
		t.equal(ScreensLogic.segmentAt(ScreensLogic.wheel({}), 10), nil)
		-- Offsets beyond the limit are clamped so the pointer stays inside the segment.
		local far = ScreensLogic.landingAngle(wheels[1], 2, { offset = 5 }) :: number
		t.equal(ScreensLogic.segmentAt(wheels[1], far), 2)
	end,

	["a spin pulls back, only ever slows down, overshoots a little and settles on the target"] = function()
		local wheel = ScreensLogic.wheel({ 1, 2, 3, 4, 5, 6, 7, 8 })
		local to = ScreensLogic.landingAngle(wheel, 6, { from = 20, turns = 5 }) :: number
		local plan = ScreensLogic.spinPlan(20, to, { sweep = 45 })
		t.truthy(plan.total > 3 and plan.total < 8, "a spin takes a few seconds")
		t.near(plan.total, plan.windupTime + plan.spinTime + plan.settleTime, 1e-9)
		t.truthy(plan.overshoot <= 45 * 0.08 + 1e-9, "the overshoot stays inside the segment")
		local start, phase = ScreensLogic.spinAngle(plan, 0)
		t.equal(start, 20)
		t.equal(phase, "windup")
		-- Anticipation: the wheel turns backwards first.
		local previous = start
		local steps = 20
		for i = 1, steps do
			local angle = ScreensLogic.spinAngle(plan, plan.windupTime * i / steps)
			t.truthy(angle <= previous + 1e-9, "windup moves backwards")
			previous = angle
		end
		t.near(previous, 20 - plan.windup, 1e-6)
		-- Main spin: always forwards, and each step no faster than the one before.
		local dt = plan.spinTime / 200
		local lastAngle = ScreensLogic.spinAngle(plan, plan.windupTime)
		local lastSpeed = math.huge
		for i = 1, 200 do
			local angle, name = ScreensLogic.spinAngle(plan, plan.windupTime + dt * i - 1e-9)
			t.equal(name, "spin")
			local speed = (angle - lastAngle) / dt
			t.truthy(speed >= -1e-6, "the wheel never turns back during the spin")
			t.truthy(speed <= lastSpeed + 1e-6, "the wheel never speeds up")
			lastAngle, lastSpeed = angle, speed
		end
		t.near(lastAngle, to + plan.overshoot, 0.01, "the spin ends at the overshoot")
		t.truthy(lastSpeed < 5, "and has almost stopped by then")
		-- Settle: stays within the overshoot of the target and ends exactly on it.
		for i = 1, 50 do
			local angle, name = ScreensLogic.spinAngle(plan, plan.windupTime + plan.spinTime + plan.settleTime * i / 50)
			t.truthy(math.abs(angle - to) <= plan.overshoot + 1e-9, "settle stays near the target")
			t.equal(ScreensLogic.segmentAt(wheel, angle), 6, "the pointer never leaves the segment while settling")
			t.truthy(name == "settle" or name == "done")
		end
		local final, done = ScreensLogic.spinAngle(plan, plan.total)
		t.equal(final, to)
		t.equal(done, "done")
		t.equal(ScreensLogic.spinAngle(plan, plan.total + 10), to)
	end,

	["reduced motion and zero-distance spins jump to the result"] = function()
		local plan = ScreensLogic.spinPlan(0, 1980, { reducedMotion = true })
		t.truthy(plan.instant)
		t.equal(plan.total, 0)
		t.equal(ScreensLogic.spinAngle(plan, 0), 1980)
		t.truthy(ScreensLogic.spinPlan(90, 90).instant)
		local longer = ScreensLogic.spinPlan(0, 3600)
		local shorter = ScreensLogic.spinPlan(0, 720)
		t.truthy(longer.spinTime >= shorter.spinTime, "longer spins take at least as long")
		t.equal(ScreensLogic.spinPlan(0, 720, { duration = 2 }).spinTime, 2)
	end,

	["leaderboard rows are ordered by value with shared ranks and the local player pinned"] = function()
		local entries = {
			{ id = 5, name = "Eve", value = 50 },
			{ id = 1, name = "Zed", value = 900 },
			{ id = 2, name = "Amy", value = 900 },
			{ id = 3, name = "Bob", value = 400 },
			{ id = 4, name = "Cat", value = 400 },
			{ id = 6, name = "Dan", value = 10 },
			"not a row",
		}
		local board = ScreensLogic.leaderboard(entries, 6, 3)
		t.equal(board.total, 6)
		local names: { string } = {}
		local ranks: { number } = {}
		for _, row in ipairs(board.rows) do
			table.insert(names, row.name)
			table.insert(ranks, row.rank)
		end
		t.deepEqual(names, { "Amy", "Zed", "Bob" }, "ties are ordered by name")
		t.deepEqual(ranks, { 1, 1, 3 }, "equal values share a rank and the next rank skips")
		t.truthy(board.pinned, "the local player is below the visible rows")
		t.equal((board.localRow :: any).rank, 6)
		t.equal((board.localRow :: any).name, "Dan")
		t.truthy((board.localRow :: any).highlight)
		local top = ScreensLogic.leaderboard(entries, 2, 3)
		t.falsy(top.pinned, "a visible local player is not pinned")
		t.truthy(top.rows[1].highlight)
		t.falsy(top.rows[2].highlight)
		local stranger = ScreensLogic.leaderboard(entries, 99)
		t.equal(stranger.localRow, nil)
		t.falsy(stranger.pinned)
		t.equal(#stranger.rows, 6)
		t.equal(#ScreensLogic.leaderboard(nil, 1).rows, 0)
		local same =
			ScreensLogic.leaderboard({ { id = "b", name = "X", value = 1 }, { id = "a", name = "X", value = 1 } }, nil)
		t.equal(same.rows[1].id, "a", "equal names fall back to the id")
	end,

	["upgrade rows show pips, the next cost and whether the balance covers it"] = function()
		local rows = ScreensLogic.upgrades({
			{ id = "speed", level = 2, maxLevel = 5, cost = 300 },
			{ id = "luck", level = 5, maxLevel = 5, cost = 999 },
			{ id = "power", level = 0, maxLevel = 3, costs = { 10, 20, 30 } },
			{ id = "long", level = 10, maxLevel = 20, cost = 1 },
			{ id = "gems", level = 1, maxLevel = 2, cost = 5, currency = "gems" },
		}, { default = 250, gems = 9 })
		t.equal(rows[1].cost, 300)
		t.falsy(rows[1].affordable)
		t.deepEqual(rows[1].pips, { true, true, false, false, false })
		t.truthy(rows[2].maxed)
		t.equal(rows[2].cost, nil)
		t.falsy(rows[2].affordable, "a maxed upgrade cannot be bought")
		t.equal(rows[3].cost, 10)
		t.truthy(rows[3].affordable)
		t.equal(#rows[4].pips, 10, "long tracks show ten pips")
		t.deepEqual(rows[4].pips, { true, true, true, true, true, false, false, false, false, false })
		t.truthy(rows[5].affordable, "each upgrade reads its own currency")
		t.truthy(ScreensLogic.upgrades({ { id = "a", cost = 5 } }, 5)[1].affordable, "a plain number balance works")
		t.falsy(ScreensLogic.upgrades({ { id = "a", cost = 5 } }, nil)[1].affordable)
		t.truthy(ScreensLogic.affordable(0, nil))
	end,

	["rebirth shows progress, the multiplier change and hold-to-confirm progress"] = function()
		local view = ScreensLogic.rebirth({ current = 250, cost = 1000, multiplier = 2, nextMultiplier = 3.5 })
		t.near(view.fraction, 0.25, 1e-9)
		t.falsy(view.affordable)
		t.equal(view.multiplier, "x2")
		t.equal(view.nextMultiplier, "x3.5")
		t.equal(view.gain, 1.5)
		t.equal(view.missing, 750)
		local ready = ScreensLogic.rebirth({ current = 5000, cost = 1000 })
		t.equal(ready.fraction, 1)
		t.truthy(ready.affordable)
		t.equal(ready.nextMultiplier, "x2", "the next multiplier defaults to one more")
		t.deepEqual({ ScreensLogic.holdFraction(0.5, 2) }, { 0.25, false })
		t.deepEqual({ ScreensLogic.holdFraction(3, 2) }, { 1, true })
		t.deepEqual({ ScreensLogic.holdFraction(0, 0) }, { 1, true })
	end,

	["the Visuals settings section mirrors the current settings and maps changes to Visuals.Configure"] = function()
		local schema =
			ScreensLogic.visualsSchema({ level = "Medium", adaptive = false, reducedMotion = true, intensity = 0.5 })
		t.equal(#SettingsSchema.validate(schema), 0, table.concat(SettingsSchema.validate(schema), "; "))
		local defaults = SettingsSchema.defaults(schema :: any)
		t.deepEqual(
			defaults,
			{ uvkQuality = "Medium", uvkIntensity = 0.5, uvkReducedMotion = true, uvkReducedFlashing = false }
		)
		t.equal(ScreensLogic.visualsSchema({ level = "Ultra", adaptive = true })[1].default, "Auto")
		t.equal(ScreensLogic.visualsSchema(nil)[1].default, "High")
		t.equal(ScreensLogic.visualsSchema({ intensity = 9 })[2].default, 1.5)
		for _, entry in ipairs(schema) do
			t.equal(entry.section, "Visuals")
		end
		t.deepEqual(ScreensLogic.visualsConfig("uvkQuality", "Low"), { quality = "Low", adaptive = false })
		t.deepEqual(ScreensLogic.visualsConfig("uvkQuality", "Auto"), { adaptive = true })
		t.equal(ScreensLogic.visualsConfig("uvkQuality", "Potato"), nil)
		t.deepEqual(ScreensLogic.visualsConfig("uvkIntensity", 3), { intensity = 1.5 })
		t.deepEqual(ScreensLogic.visualsConfig("uvkReducedMotion", true), { reducedMotion = true })
		t.deepEqual(ScreensLogic.visualsConfig("uvkReducedFlashing", false), { reducedFlashing = false })
		t.equal(ScreensLogic.visualsConfig("uvkReducedMotion", "yes"), nil)
		t.equal(ScreensLogic.visualsConfig("music", 0.5), nil, "game settings are not Visuals settings")
		-- Every level the dropdown offers (except Auto) is a real quality level.
		for _, option in ipairs(ScreensLogic.QUALITY_OPTIONS) do
			if option ~= "Auto" then
				t.truthy(table.find(Quality.LEVELS, option) ~= nil, option)
			end
		end
	end,

	["screen files only name registered UI presets and existing kit icons"] = function()
		local dir: string? = nil
		for _, candidate in ipairs({ "src/Visuals/Screens", "../src/Visuals/Screens" }) do
			if fs.isDir(candidate) then
				dir = candidate
			end
		end
		if dir == nil then
			return
		end
		local icons: { [string]: boolean } = {}
		for _, entry in ipairs(IconData.icons) do
			icons[entry.name] = true
		end
		local presets, iconCount = 0, 0
		for _, fileName in ipairs(fs.readDir(dir)) do
			if string.sub(fileName, -5) == ".luau" then
				local source = fs.readFile(dir .. "/" .. fileName)
				for _, pattern in ipairs({
					'UI%.animate%([^,]+, "(%w+)"',
					'UI%.show%([^,]+, "(%w+)"',
					'UI%.hide%([^,]+, "(%w+)"',
					'UI%.stagger%([^,]+, "(%w+)"',
					'%.reveal%("(%w+)"%)',
					'preset = "(%w+)"',
					'or "(%u%l+%u%w+)", { interval',
				}) do
					for id in string.gmatch(source, pattern) do
						presets += 1
						t.truthy(UIPresets.registry:has(id), fileName .. " plays the unknown preset " .. id)
					end
				end
				for _, pattern in ipairs({
					'icon = "([%w%-]+)"',
					'or "([%l%-]+%-color)"',
					'then "([%l%-]+%-color)"',
					'"([%l%-]+%-color)", nil%)',
				}) do
					for name in string.gmatch(source, pattern) do
						iconCount += 1
						t.truthy(icons[name], fileName .. " uses the unknown icon " .. name)
					end
				end
			end
		end
		t.truthy(presets >= 20, "preset names were found")
		t.truthy(iconCount >= 8, "icon names were found")
	end,

	["quests sort claimable first, then closest to done, then claimed"] = function()
		local quests = {
			{ id = "done", tab = "daily", value = 5, max = 5, claimed = true },
			{ id = "far", tab = "daily", value = 1, max = 10 },
			{ id = "weekly", tab = "weekly", value = 3, max = 3 },
			{ id = "near", tab = "daily", value = 9, max = 10 },
			{ id = "ready", tab = "daily", value = 12, max = 10 },
			{ id = "ready2", tab = "daily", value = 0, max = 10, state = "claimable" },
			{ id = "everywhere", value = 5, max = 10 },
		}
		local ids: { string } = {}
		for _, row in ipairs(ScreensLogic.quests(quests, "daily")) do
			table.insert(ids, row.quest.id)
		end
		t.deepEqual(ids, { "ready", "ready2", "near", "everywhere", "far", "done" })
		t.equal(#ScreensLogic.quests(quests), 7, "no tab shows every quest")
		t.equal(ScreensLogic.quests(quests, "weekly")[1].quest.id, "weekly")
		t.equal(ScreensLogic.questState({ value = 1, max = 2 }), "active")
		t.equal(ScreensLogic.questState({ value = 2, max = 2 }), "claimable")
		t.equal(ScreensLogic.questState({ value = 2, max = 2, state = "claimed" }), "claimed")
		t.deepEqual(ScreensLogic.claimableByTab(quests), { daily = 2, weekly = 1 })
		local summary = ScreensLogic.achievements({
			{ tier = 1 },
			{ tier = 0 },
			{ unlocked = true },
			{ tier = 2, unlocked = false },
		})
		t.equal(summary.unlocked, 2)
		t.equal(summary.total, 4)
		t.equal(summary.percent, 50)
	end,

	["pet inventory filters by rarity and sorts equipped, then rarest, then name"] = function()
		local pets = {
			{ id = "1", name = "Zap", rarity = "Rare" },
			{ id = "2", name = "Ash", rarity = "legendary" },
			{ id = "3", name = "Bee", rarity = "common", equipped = true },
			{ id = "4", name = "Ant", rarity = "rare" },
			{ id = "5", name = "Cub" },
		}
		local view = ScreensLogic.petInventory({ pets = pets, selected = "4", equipMax = 2 })
		local ids: { string } = {}
		for _, pet in ipairs(view.pets) do
			table.insert(ids, pet.id)
		end
		t.deepEqual(ids, { "3", "2", "4", "1", "5" })
		t.deepEqual(view.filters, {
			{ id = "all", count = 5 },
			{ id = "common", count = 2 },
			{ id = "rare", count = 2 },
			{ id = "legendary", count = 1 },
		})
		t.equal(view.equipped, 1)
		t.truthy(view.canEquip)
		t.equal(view.selected.name, "Ant")
		local rare = ScreensLogic.petInventory({ pets = pets, filter = "RARE", selected = "3", equipMax = 1 })
		t.equal(rare.filter, "rare")
		t.equal(#rare.pets, 2)
		t.falsy(rare.canEquip, "an equipped pet cannot be equipped again")
		t.falsy(ScreensLogic.petInventory({ pets = pets, selected = "4", equipMax = 1 }).canEquip, "no free slot")
		t.equal(
			ScreensLogic.petInventory({ pets = pets, filter = "mythic" }).filter,
			"all",
			"an empty filter falls back"
		)
		t.equal(ScreensLogic.rarityRank("Secret"), 7)
		t.equal(ScreensLogic.rarityRank("unknown"), 0)
		local index = ScreensLogic.collection({ { discovered = true }, {}, { discovered = true } })
		t.equal(index.discovered, 2)
		t.equal(index.percent, 66, "the percentage rounds down")
		t.equal(ScreensLogic.collection({}).percent, 0)
	end,

	["shop tabs filter products and fall back to the first tab"] = function()
		local props = {
			tabs = { { id = "pets", text = "PETS" }, { id = "boosts", text = "BOOSTS" } },
			products = { { id = "a", tab = "pets" }, { id = "b", tab = "boosts" }, { id = "c" } },
		}
		local first = ScreensLogic.shop(props)
		t.equal(first.tab, "pets")
		t.equal(#first.products, 2)
		props.tab = "boosts" :: any
		t.equal(ScreensLogic.shop(props).products[1].id, "b")
		props.tab = "ghost" :: any
		t.equal(ScreensLogic.shop(props).tab, "pets")
		t.equal(#ScreensLogic.shop({ products = { { id = "a", tab = "x" } } }).products, 1, "no tabs: everything shows")
	end,

	["trade diffs list what was added and removed"] = function()
		local before = { { id = "cat" }, { id = "gem", count = 5 }, { id = "hat" } }
		local after = { { id = "cat" }, { id = "gem", count = 2 }, { id = "dog", count = 2 }, { id = "cat" } }
		local diff = ScreensLogic.tradeDiff(before, after)
		t.truthy(diff.changed)
		t.deepEqual(diff.added, { { id = "cat", count = 1 }, { id = "dog", count = 2 } })
		t.deepEqual(diff.removed, { { id = "gem", count = 3 }, { id = "hat", count = 1 } })
		t.equal(diff.summary, "+3 added, 4 removed")
		local same = ScreensLogic.tradeDiff(before, before)
		t.falsy(same.changed)
		t.equal(same.summary, "No changes")
		t.equal(ScreensLogic.tradeDiff(nil, { { id = "a" } }).summary, "+1 added")
		t.deepEqual({ ScreensLogic.tradePhase(true, false, 5) }, { "editing", 0 })
		t.deepEqual({ ScreensLogic.tradePhase(true, true, 2.2) }, { "countdown", 3 })
		t.deepEqual({ ScreensLogic.tradePhase(true, true, 0) }, { "confirm", 0 })
		t.deepEqual({ ScreensLogic.tradePhase(nil, true, 0) }, { "editing", 0 })
	end,

	["hotbar cooldown fractions run from 1 (just used) to 0 (ready)"] = function()
		local fresh = ScreensLogic.cooldown(8, 8)
		t.equal(fresh.fraction, 1)
		t.falsy(fresh.ready)
		t.equal(fresh.text, "8")
		local half = ScreensLogic.cooldown(4, 8)
		t.equal(half.fraction, 0.5)
		t.equal(half.text, "4")
		t.equal(ScreensLogic.cooldown(3.2, 8).text, "4", "whole seconds round up")
		t.equal(ScreensLogic.cooldown(0.44, 8).text, "0.4", "the last second shows tenths")
		local ready = ScreensLogic.cooldown(0, 8)
		t.deepEqual(ready, { fraction = 0, remaining = 0, ready = true, text = "" })
		t.truthy(ScreensLogic.cooldown(-3, 8).ready)
		t.truthy(ScreensLogic.cooldown(5, 0).ready, "no duration means no cooldown")
		t.equal(ScreensLogic.cooldown(20, 8).fraction, 1, "remaining is capped at the duration")
		t.truthy(ScreensLogic.cooldown(nil, nil).ready)
		local slots = {
			{ id = "dash", readyAt = 12, duration = 8 },
			{ id = "heal", readyAt = 5, duration = 10 },
			{ id = "idle" },
		}
		local at10 = ScreensLogic.hotbar(slots, 10)
		t.equal(at10.dash.fraction, 0.25)
		t.truthy(at10.heal.ready)
		t.truthy(at10.idle.ready)
		local previous = 2
		for now = 4, 12, 0.5 do
			local fraction = ScreensLogic.hotbar(slots, now).dash.fraction
			t.truthy(fraction <= previous, "the overlay only shrinks as time passes")
			previous = fraction
		end
		t.equal(previous, 0)
	end,

	["skills are listed in unlock order with their state"] = function()
		local skills = ScreensLogic.skills({
			{ id = "ult", level = 20 },
			{ id = "dash", level = 1, unlocked = true },
			{ id = "heal", level = 5 },
			{ id = "roll", level = 5, unlocked = true },
		}, 6)
		local got: { string } = {}
		for _, row in ipairs(skills) do
			table.insert(got, row.skill.id .. ":" .. row.state)
		end
		t.deepEqual(got, { "dash:unlocked", "heal:available", "roll:unlocked", "ult:locked" })
	end,

	["a tutorial cutout is four dim frames around the hole"] = function()
		local bounds = { x = 0, y = 0, w = 800, h = 400 }
		local cut = ScreensLogic.cutout(bounds, { x = 300, y = 150, w = 100, h = 50 }, 10)
		t.deepEqual(cut.hole, { x = 290, y = 140, w = 120, h = 70 })
		local area = 0
		for _, name in ipairs({ "top", "bottom", "left", "right" }) do
			local rect = (cut :: any)[name]
			t.falsy(ScreensLogic.intersects(rect, cut.hole), name .. " does not cover the hole")
			t.truthy(ScreensLogic.contains(bounds, rect), name .. " inside the screen")
			area += rect.w * rect.h
		end
		t.equal(area + cut.hole.w * cut.hole.h, 800 * 400, "the frames and the hole tile the screen exactly")
		local edge = ScreensLogic.cutout(bounds, { x = -20, y = 380, w = 60, h = 60 }, 8)
		t.truthy(ScreensLogic.contains(bounds, edge.hole), "the hole is clipped to the screen")
		t.equal(edge.left.w, 0)
		t.equal(edge.bottom.h, 0)
	end,

	["coach marks sit on the side with the most room and stay on screen"] = function()
		local bounds = { x = 0, y = 0, w = 800, h = 400 }
		local size = { x = 240, y = 100 }
		local below, side = ScreensLogic.coachMark(bounds, { x = 350, y = 20, w = 100, h = 40 }, size)
		t.equal(side, "bottom")
		t.equal(below.y, 20 + 40 + 12)
		local above, sideTop = ScreensLogic.coachMark(bounds, { x = 350, y = 340, w = 100, h = 40 }, size)
		t.equal(sideTop, "top")
		t.equal(above.y + above.h, 340 - 12)
		for _, hole in ipairs({
			{ x = 0, y = 0, w = 60, h = 60 },
			{ x = 740, y = 340, w = 60, h = 60 },
			{ x = 10, y = 150, w = 780, h = 100 },
		}) do
			local rect = ScreensLogic.coachMark(bounds, hole, size)
			t.truthy(ScreensLogic.contains(bounds, rect), "the bubble stays on screen")
		end
	end,

	-- Data and registry ------------------------------------------------------------------------

	["props and intents are parsed from their one-line definitions"] = function()
		t.deepEqual(ScreensData.parseProp("today: number = 1 | The day that can be claimed"), {
			name = "today",
			type = "number",
			required = false,
			default = 1,
			description = "The day that can be claimed",
		})
		local required = ScreensData.parseProp("pets: list* | The pets")
		t.truthy(required.required)
		t.equal(required.default, nil)
		t.equal(ScreensData.parseProp("auto: boolean = true | Show it").default, true)
		t.equal(ScreensData.parseProp("title: string = Choose your pet | Title").default, "Choose your pet")
		t.throws(function()
			ScreensData.parseProp("title: text | Unknown type")
		end)
		t.throws(function()
			ScreensData.parseProp("pets: list = 3 | Lists take no default")
		end)
		t.throws(function()
			ScreensData.parseProp("title: string")
		end)
		t.deepEqual(ScreensData.parseIntent("Selected(id) | A card was picked"), {
			name = "Selected",
			payload = "id",
			description = "A card was picked",
		})
		t.equal(ScreensData.parseIntent("Closed() | Done").payload, "")
		t.throws(function()
			ScreensData.parseIntent("selected(id) | lower case")
		end)
	end,

	["the plan lists 25 screens with unique ids, in priority order"] = function()
		local all = ScreensData.all()
		t.equal(#all, 25)
		local seen: { [string]: boolean } = {}
		for i, screen in ipairs(all) do
			t.equal(screen.priority, i)
			t.falsy(seen[screen.id], "duplicate " .. screen.id)
			seen[screen.id] = true
			t.truthy(string.match(screen.id, "^%u%w+$") ~= nil, screen.id .. " is PascalCase")
			t.truthy(#screen.description >= 10, screen.id .. " has a description")
		end
		t.equal(all[1].id, "PetSelection")
		t.equal(all[5].id, "AnimalInteraction")
		t.equal(all[25].id, "CombatProgression")
	end,

	["Screens.names() matches the screen files that exist"] = function()
		local dir: string? = nil
		for _, candidate in ipairs({ "src/Visuals/Screens", "../src/Visuals/Screens" }) do
			if fs.isDir(candidate) then
				dir = candidate
			end
		end
		if dir == nil then
			return -- a game project copy without the sources next to the tests
		end
		local support: { [string]: boolean } =
			{ Screens = true, ScreensData = true, ScreensLogic = true, ScreenKit = true }
		local files: { string } = {}
		for _, fileName in ipairs(fs.readDir(dir)) do
			local name = string.match(fileName, "^(%w+)%.luau$")
			if name ~= nil and not support[name] then
				table.insert(files, name)
			end
		end
		table.sort(files)
		local names = table.clone(ScreensData.names())
		table.sort(names)
		t.deepEqual(names, files, "implemented screens and Screens/<Name>.luau files")
		-- Screens.luau has a loader for each of them.
		local source = fs.readFile(dir .. "/Screens.luau")
		for _, name in ipairs(names) do
			t.truthy(string.find(source, 'require("./' .. name .. '")', 1, true) ~= nil, "Screens.luau loads " .. name)
		end
		for _, screen in ipairs(ScreensData.all()) do
			if not screen.implemented then
				t.equal(#screen.props, 0, screen.id .. " is not implemented and documents no props")
				t.falsy(ScreensData.registry:has(screen.id), screen.id .. " is not in the registry")
			end
		end
	end,

	["registry metadata is complete for every implemented screen"] = function()
		local registry = ScreensData.registry
		t.equal(registry.kind, "screen")
		t.equal(registry:count(), #ScreensData.names())
		for _, name in ipairs(ScreensData.names()) do
			local def = ScreensData.get(name) :: ScreensData.Screen
			local preset = registry:get(name)
			t.equal(#Registry.validate(preset), 0, name .. " is a valid preset")
			t.truthy(#preset.description >= 20, name .. " description")
			t.truthy(
				preset.usage ~= nil and string.find(preset.usage, 'Screens.create("' .. name .. '"', 1, true) ~= nil,
				name .. " usage line"
			)
			t.truthy(#def.props >= 1, name .. " documents its props")
			for _, prop in ipairs(def.props) do
				t.truthy(#prop.description >= 8, name .. "." .. prop.name .. " is described")
				t.truthy(table.find(ScreensData.PROP_TYPES, prop.type) ~= nil)
				t.falsy(
					prop.required and prop.default ~= nil,
					name .. "." .. prop.name .. " is required or has a default"
				)
				t.equal(
					ScreensLogic.COMMON_PROPS[prop.name],
					nil,
					name .. "." .. prop.name .. " does not shadow a common prop"
				)
			end
			t.truthy(#def.intents >= 1, name .. " raises intents")
			for _, intent in ipairs(def.intents) do
				t.truthy(#intent.description >= 8, name .. "." .. intent.name .. " is described")
			end
			t.deepEqual(preset.data.props, def.props)
			t.equal(#preset.data.intentNames, #def.intents)
			t.equal(preset.data.kind, def.kind)
			local described = registry:describe(name)
			t.equal(described.kind, "screen")
			for paramName, param in pairs(described.params) do
				t.equal(registry:params(name)[paramName], param.default, name .. " param " .. paramName)
			end
		end
		t.truthy(#registry:search("pet") >= 1, "screens are searchable")
	end,

	["a game can define its own screen"] = function()
		local def = ScreensData.define({
			id = "SpecCodes",
			name = "Codes",
			kind = "dialog",
			category = "system",
			implemented = true,
			description = "Redeem a code typed by the player.",
			props = { "title: string = CODES | Window title" },
			intents = { "Confirmed(code) | A code was entered" },
		})
		t.equal(def.priority, 26)
		t.truthy(table.find(ScreensData.names(), "SpecCodes") ~= nil)
		local props, issues = ScreensLogic.check("SpecCodes", {})
		t.equal(#issues, 0)
		t.equal(props.title, "CODES")
		t.equal(#Registry.validate(ScreensData.preset(def)), 0)
		-- Remove it again so the other tests see the built-in list.
		local all = ScreensData.all()
		table.remove(all, table.find(all, def) :: number)
		def.implemented = false
		t.falsy(table.find(ScreensData.names(), "SpecCodes") ~= nil)
	end,
}
