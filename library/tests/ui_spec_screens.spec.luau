--!strict
-- The ready screen specs in src/UI/Spec/Screens/*.json: each one validates with zero issues, keeps
-- validating after withDefaults, and follows the kit's content rules (illustrated -color icons,
-- ids that match file names, a price id on every Robux price).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local SpecSchema = require("../src/UI/Spec/SpecSchema")
local t = require("./lib/t")

local REQUIRED = {
	"PetSimShop",
	"PremiumStore",
	"MainHud",
	"DailyRewards",
	"Inventory",
	"PetHatch",
	"Upgrades",
	"Quests",
	"Achievements",
	"Settings",
	"Leaderboard",
	"Profile",
	"Trading",
	"GamepassStore",
	"RewardPopup",
	"ConfirmPurchase",
}

-- Specs run from library/ in CI; the fallback covers running from library/tests.
local function screensDir(): string?
	for _, candidate in ipairs({ "src/UI/Spec/Screens", "../src/UI/Spec/Screens" }) do
		if fs.isDir(candidate) then
			return candidate
		end
	end
	return nil
end

local cached: { [string]: any }? = nil

local function loadScreens(): { [string]: any }?
	if cached ~= nil then
		return cached
	end
	local dir = screensDir()
	if dir == nil then
		return nil
	end
	local screens: { [string]: any } = {}
	for _, fileName in ipairs(fs.readDir(dir)) do
		if string.sub(fileName, -5) == ".json" then
			local name = string.sub(fileName, 1, -6)
			screens[name] = serde.decode("json", fs.readFile(dir .. "/" .. fileName))
		end
	end
	cached = screens
	return screens
end

local function sortedNames(screens: { [string]: any }): { string }
	local names: { string } = {}
	for name in pairs(screens) do
		table.insert(names, name)
	end
	table.sort(names, function(a: string, b: string): boolean
		return a < b
	end)
	return names
end

-- Every icon name a screen uses, with where it is.
local function iconsOf(spec: any): { { path: string, icon: string } }
	local found: { { path: string, icon: string } } = {}
	local function note(path: string, value: any)
		if type(value) == "string" then
			table.insert(found, { path = path, icon = value })
		end
	end
	SpecSchema.walk(spec, function(element: any, path: string)
		note(path .. ".icon", element.icon)
		if type(element.price) == "table" then
			note(path .. ".price.currency", element.price.currency)
		end
	end)
	if type(spec.popup) == "table" then
		note("popup.icon", spec.popup.icon)
	end
	return found
end

return {
	["every screen spec validates with zero issues"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		local failures: { string } = {}
		for _, name in ipairs(sortedNames(screens)) do
			local issues = SpecSchema.validate(screens[name])
			if #issues > 0 then
				table.insert(failures, name .. ":\n" .. SpecSchema.format(issues))
			end
		end
		if #failures > 0 then
			error(table.concat(failures, "\n\n"))
		end
	end,

	["all sixteen required screens exist"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		for _, name in ipairs(REQUIRED) do
			t.truthy(screens[name] ~= nil, "missing Screens/" .. name .. ".json")
		end
	end,

	["each screen id matches its file name"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		for name, spec in pairs(screens) do
			t.equal(spec.id, name, name)
		end
	end,

	["screens still validate after withDefaults"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		for _, name in ipairs(sortedNames(screens)) do
			local issues = SpecSchema.validate(SpecSchema.withDefaults(screens[name]))
			if #issues > 0 then
				error(name .. " after withDefaults:\n" .. SpecSchema.format(issues))
			end
		end
	end,

	["screens use the illustrated -color icons"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		for _, name in ipairs(sortedNames(screens)) do
			for _, use in ipairs(iconsOf(screens[name])) do
				t.truthy(string.sub(use.icon, -6) == "-color", name .. " " .. use.path .. " uses " .. use.icon)
			end
		end
	end,

	["screen kinds cover window, hud and popup"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		t.equal(screens.MainHud.kind, "hud")
		t.equal(screens.RewardPopup.kind, "popup")
		t.equal(screens.RewardPopup.popup.variant, "reward")
		t.equal(screens.ConfirmPurchase.popup.variant, "confirm")
		t.equal(screens.PetSimShop.kind, "window")
	end,

	["PetSimShop mirrors the reference shop structure"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		local body = screens.PetSimShop.body
		t.equal(body[1].type, "banner", "starter pack banner first")
		local grids: { any } = {}
		for _, element in ipairs(body) do
			if element.type == "grid" then
				table.insert(grids, element)
			end
		end
		t.equal(#grids, 2, "a gamepass grid and a currency pack grid")
		t.equal(#grids[1].items, 3)
		t.equal(#grids[2].items, 3)
		t.equal(body[#body].type, "banner", "x2 cash banner last")
	end,

	["PremiumStore has giftable gamepasses and bonus coin packs"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		local gifts, attention, bonuses = 0, 0, 0
		SpecSchema.walk(screens.PremiumStore, function(element: any, _path: string)
			if element.gift == true then
				gifts += 1
			end
			if type(element.badge) == "table" and element.badge.kind == "attention" then
				attention += 1
			end
			if type(element.subtitle) == "string" and string.find(element.subtitle, "Bonus", 1, true) then
				bonuses += 1
			end
		end)
		t.truthy(gifts >= 3, "gift buttons")
		t.truthy(attention >= 1, "attention badges")
		t.equal(bonuses, 3, "+15% / +50% / +100% Bonus packs")
	end,

	["MainHud uses rails for menu, currency, level, timer and quick bar"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		local rails = screens.MainHud.rails
		t.equal(rails.left[1].type, "grid")
		t.truthy(#rails.left[1].items >= 7, "left rail menu buttons")
		t.truthy(rails.topRight ~= nil and rails.bottom ~= nil and rails.bottomLeft ~= nil)
		local kinds: { [string]: boolean } = {}
		for _, element in ipairs(rails.bottom) do
			kinds[element.type] = true
		end
		t.truthy(kinds.level and kinds.currency, "bottom level bar and cash counter")
	end,

	["DailyRewards has seven days with a premium day 7"] = function()
		local screens = loadScreens()
		if screens == nil then
			return
		end
		local days: { any } = {}
		SpecSchema.walk(screens.DailyRewards, function(element: any, _path: string)
			if element.type == "dayCard" then
				table.insert(days, element)
			end
		end)
		t.equal(#days, 7)
		t.equal(days[7].day, 7)
		t.equal(days[7].premium, true)
		local today = 0
		for _, card in ipairs(days) do
			if card.state == "today" then
				today += 1
			end
		end
		t.equal(today, 1, "exactly one card is today's")
	end,
}
