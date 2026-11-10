--!strict
-- Spec rules for the animated Game components, the per-element `motion` field, "pack:name" icons
-- and the ten Visuals styles.

local SpecSchema = require("../src/UI/Spec/SpecSchema")
local Style = require("../src/UI/Style/Style")
local UIPresets = require("../src/Visuals/UI/UIPresets")
local t = require("./lib/t")

local function window(body: { any }, style: string?): any
	return { spec = 1, id = "Test", kind = "window", style = style, window = { title = "TEST" }, body = body }
end

local function describe(issues: { SpecSchema.Issue }): string
	return SpecSchema.format(issues)
end

local function expectValid(spec: any)
	local issues = SpecSchema.validate(spec)
	t.equal(#issues, 0, describe(issues))
end

local function expectIssue(spec: any, path: string, fragment: string)
	local issues = SpecSchema.validate(spec)
	for _, issue in ipairs(issues) do
		if issue.path == path and string.find(issue.message, fragment, 1, true) ~= nil then
			return
		end
	end
	error(string.format("expected %q at %q, got:\n%s", fragment, path, describe(issues)), 2)
end

local VISUALS_STYLES =
	{ "vibrant", "premium", "fantasy", "anime", "scifi", "cozy", "minimal", "arcade", "luxury", "adventure" }

return {
	["every animated component validates with typical props"] = function()
		expectValid(window({
			{
				type = "premiumButton",
				text = "CLAIM",
				icon = "gift-color",
				palette = "gold",
				shine = true,
				glow = false,
			},
			{ type = "tabBar", id = "tabs", tabs = { { id = "a", text = "A" }, { id = "b", icon = "star-color" } } },
			{ type = "xpBar", level = 2, value = 10, max = 50, bind = "player.xp" },
			{ type = "inventorySlot", icon = "coin-color", count = 3, rarity = "rare", locked = true },
			{ type = "petCard", title = "Fox", rarity = "epic", stats = { { text = "x2" } }, equipped = true },
			{ type = "rarityBadge", rarity = "mythic", text = "MYTHIC" },
			{ type = "rewardPanel", rewards = { { icon = "coin-color", amount = "x5" } }, columns = 2 },
			{ type = "questCard", title = "Quest", description = "Do it", value = 1, max = 3, state = "active" },
			{ type = "achievementCard", title = "Badge", tier = 2, maxTier = 3, value = 5, max = 10 },
			{ type = "notification", title = "Saved", text = "All good", kind = "success", duration = 3 },
			{ type = "leaderboardRow", title = "Player", rank = 1, value = 1200, highlight = true },
			{ type = "loadingScreen", title = "GAME", tips = { "Tip one" }, progress = 0.4, visible = false },
			{ type = "selectionCard", title = "Mage", description = "Casts spells", selected = false },
			{ type = "hotbarSlot", icon = "energy-color", keybind = "Q", cooldown = 6 },
			{ type = "statChip", icon = "star-color", value = 120, suffix = "%" },
			{ type = "statChip", value = "x2.5", prefix = "LUCK" },
			{ type = "modal", id = "ask", title = "SURE?", text = "Really?", buttons = { { id = "ok", text = "OK" } } },
			{ type = "tooltip", text = "Opens the shop", target = "tabs", side = "left" },
		}))
	end,

	["interactive animated components get an id from withDefaults"] = function()
		local full = SpecSchema.withDefaults(window({
			{ type = "premiumButton", text = "GO" },
			{ type = "petCard", title = "Fox" },
			{ type = "statChip", value = 1 },
			{ type = "tabBar", id = "tabs", tabs = { { id = "first", text = "A" }, { id = "second", text = "B" } } },
			{ type = "xpBar" },
		}))
		t.truthy(type(full.body[1].id) == "string", "premiumButton id")
		t.truthy(type(full.body[2].id) == "string", "petCard id")
		t.equal(full.body[3].id, nil, "statChip is not interactive")
		t.equal(full.body[4].value, "first", "tabBar selects its first tab")
		t.equal(full.body[5].max, 100)
		t.equal(#SpecSchema.validate(full), 0, "still valid after defaults")
	end,

	["component field rules are enforced"] = function()
		expectIssue(window({ { type = "premiumButton" } }), "body[1]", "needs text or icon")
		expectIssue(window({ { type = "hotbarSlot" } }), "body[1]", "needs icon or image or keybind")
		expectIssue(window({ { type = "statChip" } }), "body[1]", "needs bind or value")
		expectIssue(
			window({ { type = "questCard", title = "Q", state = "locked" } }),
			"body[1].state",
			"questCard state"
		)
		expectIssue(
			window({ { type = "notification", title = "N", kind = "buy" } }),
			"body[1].kind",
			"notification kind"
		)
		expectIssue(window({ { type = "achievementCard", title = "A", tier = 6 } }), "body[1].tier", "at most 5")
		expectIssue(
			window({ { type = "achievementCard", title = "A", tier = 3, maxTier = 2 } }),
			"body[1].tier",
			"maxTier"
		)
		expectIssue(window({ { type = "loadingScreen", progress = 2 } }), "body[1].progress", "at most 1")
		expectIssue(window({ { type = "hotbarSlot", keybind = "SHIFT" } }), "body[1].keybind", "limit is 4")
		expectIssue(window({ { type = "rewardPanel", rewards = {} } }), "body[1].rewards", "non-empty")
		expectIssue(
			window({ { type = "rewardPanel", rewards = { { amount = "x1" } } } }),
			"body[1].rewards[1]",
			"icon or image"
		)
		expectIssue(
			window({
				{
					type = "petCard",
					title = "P",
					stats = { { text = "a" }, { text = "b" }, { text = "c" }, { text = "d" } },
				},
			}),
			"body[1].stats",
			"more than 3"
		)
		expectIssue(window({ { type = "xpBar", value = 5, max = 2 } }), "body[1].value", "exceed max")
		expectIssue(
			window({ { type = "leaderboardRow", title = "P", avatar = "http://x" } }),
			"body[1].avatar",
			"asset id"
		)
	end,

	["tab bars need unique tab ids and a value that names a tab"] = function()
		local tabs = { { id = "a", text = "A" }, { id = "a", text = "B" } }
		expectIssue(window({ { type = "tabBar", id = "t", tabs = tabs } }), "body[1].tabs[2].id", "duplicate tab id")
		expectIssue(
			window({ { type = "tabBar", id = "t", tabs = { { id = "a", text = "A" } }, value = "b" } }),
			"body[1].value",
			"one of the tab ids"
		)
		expectIssue(
			window({ { type = "tabBar", id = "t", tabs = { { id = "a" } } } }),
			"body[1].tabs[1]",
			"text or icon"
		)
		expectIssue(window({ { type = "tabBar", tabs = { { id = "a", text = "A" } } } }), "body[1].id", "required")
	end,

	["a tooltip must target an element that exists, in any order"] = function()
		expectIssue(
			window({ { type = "tooltip", text = "Hi", target = "ghost" } }),
			"body[1].target",
			"no element has the id"
		)
		expectValid(window({
			{ type = "tooltip", text = "Hi", target = "later" },
			{ type = "button", id = "later", text = "GO" },
		}))
	end,

	["modal buttons need an id and text"] = function()
		local modal = { type = "modal", id = "m", title = "T", buttons = { { text = "OK" }, { id = "no" } } }
		expectIssue(window({ modal }), "body[1].buttons[1].id", "required")
		expectIssue(window({ modal }), "body[1].buttons[2].text", "required")
	end,

	["motion takes a registered Visuals UI preset id or { preset, delay }"] = function()
		expectValid(window({
			{ type = "divider", motion = "PopIn" },
			{ type = "button", text = "GO", motion = { preset = "BouncyPress", delay = 0.2 } },
		}))
		expectIssue(window({ { type = "divider", motion = "popIn" } }), "body[1].motion", "unknown motion preset")
		expectIssue(window({ { type = "divider", motion = "Nope" } }), "body[1].motion", "unknown motion preset")
		expectIssue(window({ { type = "divider", motion = 3 } }), "body[1].motion", "preset id or")
		expectIssue(window({ { type = "divider", motion = { delay = 1 } } }), "body[1].motion.preset", "required")
		expectIssue(
			window({ { type = "divider", motion = { preset = "PopIn", delay = -1 } } }),
			"body[1].motion.delay",
			"at least 0"
		)
		expectIssue(
			window({ { type = "divider", motion = { preset = "PopIn", loop = true } } }),
			"body[1].motion.loop",
			"unknown field"
		)
	end,

	["every required Visuals UI preset is a valid motion id"] = function()
		local seen = 0
		for _, ids in pairs(UIPresets.REQUIRED) do
			for _, id in ipairs(ids) do
				seen += 1
				t.truthy(SpecSchema.isMotionPreset(id), id)
				t.truthy(table.find(SpecSchema.MOTION_PRESETS, id) ~= nil, id .. " listed")
			end
		end
		t.truthy(seen >= 60, "required ids checked")
	end,

	["a preset a game registers later is accepted as motion"] = function()
		t.falsy(SpecSchema.isMotionPreset("SpecTestWobble"))
		UIPresets.registry:register({
			id = "SpecTestWobble",
			name = "Spec test wobble",
			category = "buttons",
			description = "Registered by the spec.",
			data = { steps = { { props = { Scale = 1.05 }, duration = 0.1 } } },
		})
		t.truthy(SpecSchema.isMotionPreset("SpecTestWobble"))
		UIPresets.registry:unregister("SpecTestWobble")
		t.falsy(SpecSchema.isMotionPreset("SpecTestWobble"))
	end,

	["pack icons are lowercase kebab-case on both sides of one colon"] = function()
		for _, name in ipairs({ "mypack:sword", "ui-pack-2:iron-sword", "a:b", "pack9:gem-3" }) do
			t.truthy(SpecSchema.isPackIcon(name), name)
			t.truthy(SpecSchema.isIcon(name), name)
		end
		local bad = {
			"MyPack:sword",
			"mypack:Sword",
			"mypack:",
			":sword",
			"my pack:sword",
			"a:b:c",
			"a--b:c",
			"a:b-",
			"-a:b",
			"sword",
		}
		for _, name in ipairs(bad) do
			t.falsy(SpecSchema.isPackIcon(name), name)
		end
		expectValid(window({ { type = "iconButton", icon = "mypack:iron-sword" } }))
		expectValid(window({
			{ type = "button", text = "BUY", price = { kind = "currency", amount = 5, currency = "mypack:gold-coin" } },
		}))
		expectIssue(window({ { type = "iconButton", icon = "MyPack:Sword" } }), "body[1].icon", "unknown icon")
	end,

	["specs may select each of the ten Visuals styles"] = function()
		local names = Style.names()
		for _, style in ipairs(VISUALS_STYLES) do
			t.truthy(table.find(names, style) ~= nil, style .. " is a style")
			expectValid(window({
				{ type = "button", text = "GO", kind = "buy", palette = "gold" },
				{ type = "rarityBadge", rarity = "legendary" },
				{ type = "row", gap = "lg", items = { { type = "statChip", value = 1, palette = "teal" } } },
			}, style))
		end
	end,
}
