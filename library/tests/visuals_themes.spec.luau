--!strict
-- The ten visual themes: data validity, style mapping, contrast, distinctness, derive / register
-- and token fallback. Pure: everything goes through ThemeData and ThemeLogic.

local Springs = require("../src/Visuals/Core/Springs")
local StyleTokens = require("../src/UI/Style/StyleTokens")
local t = require("./lib/t")
local ThemeData = require("../src/Visuals/Themes/ThemeData")
local ThemeLogic = require("../src/Visuals/Themes/ThemeLogic")
local UrkTheme = require("../src/UI/Core/Theme")

local EXPECTED_STYLES: { [string]: string } = {
	VibrantSimulator = "vibrant",
	PremiumCartoon = "premium",
	Fantasy = "fantasy",
	Anime = "anime",
	SciFi = "scifi",
	Cozy = "cozy",
	ModernMinimal = "minimal",
	Arcade = "arcade",
	Luxury = "luxury",
	Adventure = "adventure",
}

local function theme(id: string): ThemeLogic.Theme
	return ThemeData.themes[id]
end

local function springSet(id: string): string
	local parts: { string } = {}
	for _, role in ThemeData.SPRING_ROLES do
		table.insert(parts, theme(id).motion.spring[role])
	end
	return table.concat(parts, ",")
end

local function paths(problems: { ThemeLogic.Problem }): { string }
	local list: { string } = {}
	for _, problem in problems do
		table.insert(list, problem.path)
	end
	return list
end

return {
	["there are exactly ten themes with the contract ids"] = function()
		t.equal(#ThemeData.IDS, 10)
		local count = 0
		for id in ThemeData.themes do
			count += 1
			t.truthy(table.find(ThemeData.IDS, id) ~= nil, id)
			t.equal(theme(id).id, id)
		end
		t.equal(count, 10)
		t.truthy(table.find(ThemeData.IDS, ThemeData.DEFAULT) ~= nil, "default theme exists")
	end,

	["every theme validates with no problems"] = function()
		for _, id in ThemeData.IDS do
			local problems = ThemeLogic.validate(theme(id), StyleTokens)
			t.equal(#problems, 0, id .. ": " .. ThemeLogic.describe(problems))
			t.truthy(ThemeLogic.isValid(theme(id), StyleTokens), id)
		end
	end,

	["ids map to the styles of the same intent in the generated StyleTokens"] = function()
		for id, style in EXPECTED_STYLES do
			t.equal(theme(id).style, style, id)
			t.truthy(StyleTokens[style] ~= nil, style .. " exists in StyleTokens")
			t.equal(ThemeLogic.styleKey(id), style)
			t.equal(ThemeLogic.styleKey(theme(id)), style)
			t.equal(ThemeLogic.themeForStyle(style), id)
		end
		t.equal(ThemeLogic.themeForStyle("cartoon"), nil, "styles without a theme map to nil")
		t.throws(function()
			ThemeLogic.styleKey("DoesNotExist")
		end)
	end,

	["style-owned tokens are read from the style, never copied"] = function()
		for _, id in ThemeData.IDS do
			local data = theme(id)
			local style = StyleTokens[data.style]
			t.equal(data.colors.surface, style.surfaces.window.top, id .. " surface")
			t.equal(data.colors.text, style.surfaces.window.text, id .. " text")
			t.equal(data.colors.border, style.outline.color, id .. " border")
			t.equal(data.typography.fonts.title, style.fonts.title, id .. " title font")
			t.equal(data.typography.fonts.number, style.fonts.number, id .. " number font")
			t.equal(data.typography.sizes.display, style.text.display, id .. " display size")
			t.deepEqual(data.layout.spacing, style.spacing, id .. " spacing")
			t.deepEqual(data.layout.radius, style.radius, id .. " radius")
			for _, rarity in ThemeData.RARITIES do
				t.equal(data.rarity[rarity], style.rarity[string.lower(rarity)].color, id .. " " .. rarity)
			end
			t.equal(data.motion.scale.hover, style.motion.hoverScale, id .. " hover scale matches the style")
			t.equal(data.motion.scale.press, style.motion.pressScale, id .. " press scale matches the style")
			t.equal(data.motion.duration.fast, style.motion.fast, id .. " fast duration matches the style")
			t.equal(data.motion.duration.normal, style.motion.normal, id .. " normal duration matches the style")
		end
	end,

	["text is readable and accents are visible (WCAG)"] = function()
		for _, id in ThemeData.IDS do
			local c = theme(id).colors
			t.truthy(ThemeLogic.contrast(c.text, c.background) >= 4.5, id .. " text on background")
			t.truthy(ThemeLogic.contrast(c.text, c.surface) >= 4.5, id .. " text on surface")
			t.truthy(ThemeLogic.contrast(c.textMuted, c.background) >= 4.5, id .. " muted text on background")
			t.truthy(ThemeLogic.contrast(c.textMuted, c.surface) >= 4.5, id .. " muted text on surface")
			t.truthy(ThemeLogic.contrast(c.accent, c.background) >= 3, id .. " accent on background")
			t.truthy(ThemeLogic.contrast(c.primary, c.background) >= 3, id .. " primary on background")
			for _, role in { "success", "warning", "error" } do
				local ratio = ThemeLogic.contrast((c :: any)[role], c.surface)
				t.truthy(ratio >= 3, id .. " " .. role .. " on surface")
			end
		end
	end,

	["luminance and contrast follow WCAG"] = function()
		t.near(ThemeLogic.luminance("#FFFFFF"), 1, 1e-6)
		t.near(ThemeLogic.luminance("#000000"), 0, 1e-6)
		t.near(ThemeLogic.contrast("#FFFFFF", "#000000"), 21, 1e-6)
		t.near(ThemeLogic.contrast("#000000", "#FFFFFF"), 21, 1e-6, "order does not matter")
		t.near(ThemeLogic.contrast("#777777", "#FFFFFF"), 4.48, 0.01)
		t.near(ThemeLogic.contrast("#3D5AFE", "#3D5AFE"), 1, 1e-6)
		t.truthy(ThemeLogic.isHex("#aBc123"))
		t.falsy(ThemeLogic.isHex("#FFF"))
		t.falsy(ThemeLogic.isHex(12))
		t.throws(function()
			ThemeLogic.luminance("red")
		end)
	end,

	["colour helpers: mix, readableOn, ensureContrast"] = function()
		t.equal(ThemeLogic.mix("#000000", "#FFFFFF", 0.5), "#808080")
		t.equal(ThemeLogic.mix("#102030", "#FFFFFF", 0), "#102030")
		t.equal(ThemeLogic.mix("#102030", "#FFFFFF", 4), "#FFFFFF", "amount is clamped")
		t.equal(ThemeLogic.readableOn("#101010"), "#FFFFFF")
		t.equal(ThemeLogic.readableOn("#FAFAFA"), "#111111")
		t.equal(ThemeLogic.readableOn("#FAFAFA", "#EEEEEE", "#222222"), "#222222")
		local fixed = ThemeLogic.ensureContrast("#FFE866", "#FFFFFF", 4.5)
		t.truthy(ThemeLogic.contrast(fixed, "#FFFFFF") >= 4.5, "pushed until it passes")
		t.equal(ThemeLogic.ensureContrast("#000000", "#FFFFFF", 4.5), "#000000", "passing colours are unchanged")
		local onDark = ThemeLogic.ensureContrast("#202020", "#101010", 3)
		t.truthy(ThemeLogic.luminance(onDark) > ThemeLogic.luminance("#202020"), "moves toward white on dark")
	end,

	["themes are pairwise distinct in colour and motion"] = function()
		for i = 1, #ThemeData.IDS do
			for j = i + 1, #ThemeData.IDS do
				local a, b = ThemeData.IDS[i], ThemeData.IDS[j]
				local label = a .. " vs " .. b
				t.truthy(theme(a).colors.primary ~= theme(b).colors.primary, label .. " primary")
				t.truthy(theme(a).style ~= theme(b).style, label .. " style")
				t.truthy(springSet(a) ~= springSet(b), label .. " springs")
				t.truthy(theme(a).name ~= theme(b).name, label .. " name")
				local fontsA = theme(a).typography.fonts.title .. theme(a).typography.fonts.body
				local fontsB = theme(b).typography.fonts.title .. theme(b).typography.fonts.body
				t.truthy(fontsA ~= fontsB, label .. " fonts")
			end
		end
	end,

	["motion feel matches each theme's brief"] = function()
		local arcade, luxury = theme("Arcade").motion, theme("Luxury").motion
		t.equal(arcade.spring.press, "Snappy")
		t.equal(arcade.spring.popup, "Elastic")
		t.equal(luxury.spring.press, "Premium")
		t.equal(luxury.spring.reward, "Cinematic")
		t.truthy(arcade.duration.normal < luxury.duration.normal, "arcade is quicker than luxury")
		t.truthy(luxury.intensity < 1 and arcade.intensity > 1, "luxury is calm, arcade is loud")
		for _, id in ThemeData.IDS do
			t.truthy(theme("Arcade").motion.duration.fast <= theme(id).motion.duration.fast, "arcade is the fastest")
			t.truthy(theme("Luxury").motion.duration.slow >= theme(id).motion.duration.slow, "luxury is the slowest")
		end

		local cozy = theme("Cozy").motion
		for _, role in ThemeData.SPRING_ROLES do
			t.truthy(cozy.spring[role] == "Soft" or cozy.spring[role] == "Gentle", "cozy " .. role)
		end

		local anime = theme("Anime").motion
		t.equal(anime.spring.press, "Overshoot")
		t.equal(anime.spring.popup, "Overshoot")
		t.truthy(anime.duration.normal < theme("PremiumCartoon").motion.duration.normal, "anime is fast")

		local minimal = theme("ModernMinimal").motion
		t.equal(minimal.spring.press, "Snappy")
		t.truthy(minimal.scale.hover <= 1.02 and minimal.scale.press >= 0.98, "tiny scale amounts")
		for _, role in { "panel", "popup", "toast", "card", "screen" } do
			t.equal(minimal.transition[role], "fade", "minimal fades " .. role)
		end
		for _, id in ThemeData.IDS do
			t.truthy(minimal.intensity <= theme(id).motion.intensity, "minimal has the lowest intensity")
		end
	end,

	["motion tokens are usable: springs exist, durations rise, reduced motion never bounces"] = function()
		for _, id in ThemeData.IDS do
			local motion = theme(id).motion
			local last = -1
			for _, name in ThemeData.DURATIONS do
				t.truthy(motion.duration[name] >= last, id .. " " .. name)
				last = motion.duration[name]
			end
			t.equal(motion.duration.instant, 0, id .. " instant")
			for _, role in ThemeData.SPRING_ROLES do
				t.truthy(Springs.has(motion.spring[role]), id .. " spring " .. role)
			end
			t.truthy(Springs.get(motion.reduced.spring).damping >= 1, id .. " reduced spring does not overshoot")
			for _, role in ThemeData.TRANSITION_ROLES do
				t.equal(motion.reduced.transition[role], "fade", id .. " reduced " .. role)
			end
		end
	end,

	["layout: layers rise and breakpoints use the UrkUI names"] = function()
		local Breakpoints = require("../src/UI/Core/Breakpoints")
		t.deepEqual(ThemeData.BREAKPOINTS, Breakpoints.NAMES)
		for _, id in ThemeData.IDS do
			local layout = theme(id).layout
			local last = -math.huge
			for _, name in ThemeData.LAYER_NAMES do
				t.truthy(layout.layers[name] > last, id .. " layer " .. name)
				last = layout.layers[name]
			end
			for _, name in Breakpoints.NAMES do
				t.truthy(Breakpoints.isValid(name))
				t.truthy(layout.breakpoints[name].columns >= 1, id .. " columns " .. name)
				t.truthy(theme(id).typography.scale[name] > 0, id .. " text scale " .. name)
			end
			t.truthy(layout.breakpoints.phone.columns <= layout.breakpoints.desktop.columns, id .. " phone is narrower")
		end
	end,

	["effects: particle palettes, gradients and texture keys"] = function()
		local textureKeys = {
			"spark",
			"glow",
			"star",
			"ring",
			"smoke",
			"circle",
			"confetti",
			"coin",
			"gem",
			"heart",
			"leaf",
			"drop",
			"shard",
			"bubble",
			"flare",
			"streak",
		}
		for _, id in ThemeData.IDS do
			local effects = theme(id).effects
			t.truthy(#effects.particles >= 3 and #effects.particles <= 5, id .. " particle palette size")
			t.truthy(table.find(textureKeys, effects.sparkle) ~= nil, id .. " sparkle is a VFX texture key")
			t.truthy(effects.glow.strong.size > effects.glow.soft.size, id .. " glow sizes")
			t.truthy(effects.shadow.lg.offsetY >= effects.shadow.sm.offsetY, id .. " shadow sizes")
			t.equal(#effects.gradient.reward.stops, 3, id .. " reward gradient")
		end
	end,

	["validate reports missing, invalid and low-contrast tokens"] = function()
		local broken: any = ThemeLogic.derive("Cozy", { id = "Broken" })
		broken.colors.accent = nil
		broken.colors.primary = "blue"
		broken.colors.text = broken.colors.background
		broken.motion.spring.press = "Wobbly"
		broken.motion.duration.fast = 2
		broken.motion.easing = "notACurve"
		broken.motion.transition.popup = "explode"
		broken.motion.reduced.transition.panel = "pop"
		broken.motion.reduced.spring = "Bouncy"
		broken.effects.particles = { "#FFFFFF" }
		broken.layout.layers.toast = 1
		broken.style = "doesNotExist"
		local problems = ThemeLogic.validate(broken, StyleTokens)
		local found = paths(problems)
		for _, path in
			{
				"colors.accent",
				"colors.primary",
				"colors.text",
				"motion.spring.press",
				"motion.duration.normal",
				"motion.easing",
				"motion.transition.popup",
				"motion.reduced.transition.panel",
				"motion.reduced.spring",
				"effects.particles",
				"layout.layers.toast",
				"style",
			}
		do
			t.truthy(table.find(found, path) ~= nil, "reports " .. path)
		end
		local kinds: { [string]: string } = {}
		for _, problem in problems do
			kinds[problem.path] = problem.kind
		end
		t.equal(kinds["colors.accent"], "missing")
		t.equal(kinds["colors.primary"], "invalid")
		t.equal(kinds["colors.text"], "contrast")
		t.falsy(ThemeLogic.isValid(broken, StyleTokens))
		t.truthy(#ThemeLogic.describe(problems) > 0)
		t.equal(ThemeLogic.validate(nil)[1].kind, "invalid")
		t.truthy(#ThemeLogic.validate({}) >= 6, "an empty table misses every section")
	end,

	["derive copies deeply, merges overrides and leaves the base untouched"] = function()
		local before = theme("Fantasy").colors.accent
		local custom = ThemeLogic.derive("Fantasy", {
			id = "DarkFantasy",
			name = "Dark Fantasy",
			colors = { accent = "#5A3E00" },
			motion = { spring = { press = "Heavy" }, intensity = 0.5 },
			effects = { particles = { "#111111", "#222222", "#333333" } },
		})
		t.equal(custom.id, "DarkFantasy")
		t.equal(custom.name, "Dark Fantasy")
		t.equal(custom.colors.accent, "#5A3E00")
		t.equal(custom.colors.primary, theme("Fantasy").colors.primary, "other colours are kept")
		t.equal(custom.motion.spring.press, "Heavy")
		t.equal(custom.motion.spring.hover, theme("Fantasy").motion.spring.hover, "other springs are kept")
		t.equal(custom.motion.intensity, 0.5)
		t.deepEqual(custom.effects.particles, { "#111111", "#222222", "#333333" }, "arrays are replaced")
		t.equal(theme("Fantasy").colors.accent, before, "the base is untouched")
		t.truthy(custom.colors ~= theme("Fantasy").colors, "tables are copies")
		t.truthy(ThemeLogic.isValid(custom, StyleTokens))

		t.equal(ThemeLogic.derive("Arcade").id, "ArcadeCustom", "a default id is given")
		t.equal(ThemeLogic.derive(custom, { colors = { glow = "#FFFFFF" } }).id, "DarkFantasyCustom")
		t.throws(function()
			ThemeLogic.derive("DoesNotExist", {})
		end)
	end,

	["token lookup walks paths and falls back to a base theme"] = function()
		local luxury = theme("Luxury")
		t.equal(ThemeLogic.token(luxury, "motion.spring.press"), "Premium")
		t.equal(ThemeLogic.token(luxury, "motion.duration.cinematic"), 1.8)
		t.equal(ThemeLogic.token(luxury, "colors.primary"), "#C9A24B")
		t.equal(ThemeLogic.token(luxury, "effects.particles.1"), "#F0D58A")
		t.equal(ThemeLogic.token(luxury, "effects.gradient.surface.stops.2.color"), "#12100E")
		t.equal(ThemeLogic.token(luxury, "motion.spring.doesNotExist"), nil)
		t.equal(ThemeLogic.token(luxury, "motion.spring.press.deeper"), nil, "walking past a leaf is nil")

		local partial: any = { id = "Partial", motion = { spring = { press = "Elastic" } } }
		t.equal(ThemeLogic.token(partial, "motion.spring.press", luxury), "Elastic", "own token wins")
		t.equal(ThemeLogic.token(partial, "motion.spring.hover", luxury), "Premium", "missing token falls back")
		t.equal(ThemeLogic.token(partial, "colors.accent", luxury), luxury.colors.accent)
		t.equal(ThemeLogic.token(partial, "nope.nothing", luxury), nil)
	end,

	["registry: set, current, names, register and change notifications"] = function()
		local events: { string } = {}
		local registry = ThemeLogic.newRegistry(
			StyleTokens,
			function(id: string, changed: ThemeLogic.Theme, previous: string)
				table.insert(events, previous .. ">" .. id .. ":" .. changed.style)
			end
		)
		t.equal(registry.current(), ThemeData.DEFAULT)
		t.equal(registry.get().id, ThemeData.DEFAULT)
		t.equal(#registry.names(), 10)

		t.equal(registry.set("Luxury").style, "luxury")
		t.equal(registry.current(), "Luxury")
		t.equal(registry.get().id, "Luxury")
		t.equal(registry.token("motion.spring.press"), "Premium")
		t.equal(registry.token("motion.spring.press", "Arcade"), "Snappy")
		registry.set("Luxury")
		t.deepEqual(events, { "VibrantSimulator>Luxury:luxury" }, "setting the same theme does not notify")

		t.throws(function()
			registry.set("DoesNotExist")
		end)
		t.equal(registry.current(), "Luxury", "a failed set changes nothing")
		t.throws(function()
			registry.get("DoesNotExist")
		end)

		local candy = ThemeLogic.derive("VibrantSimulator", { colors = { glow = "#FF99CC" } })
		local stored = registry.register("Candy", candy)
		t.equal(stored.id, "Candy", "the registered id wins")
		t.truthy(stored ~= candy, "register stores a copy")
		t.truthy(registry.has("Candy"))
		t.equal(#registry.names(), 11)
		t.equal(registry.set("Candy").colors.glow, "#FF99CC")
		t.equal(registry.token("colors.glow"), "#FF99CC")

		t.throws(function()
			registry.register("Candy", candy)
		end, "duplicates need override")
		t.throws(function()
			registry.register("Arcade", candy)
		end, "built-ins need override")
		local replaced = ThemeLogic.derive(candy, { colors = { glow = "#00FFAA" } })
		registry.register("Candy", replaced, { override = true })
		t.equal(registry.get("Candy").colors.glow, "#00FFAA")
		t.equal(events[#events], "Candy>Candy:vibrant", "re-registering the current theme notifies")

		local bad: any = ThemeLogic.derive("Cozy", { motion = { spring = { press = "Nope" } } })
		t.throws(function()
			registry.register("Bad", bad)
		end, "invalid themes are rejected")
		t.falsy(registry.has("Bad"))

		local other = ThemeLogic.newRegistry()
		t.equal(#other.names(), 10, "registries are independent")
	end,

	["every theme converts to a valid UrkUI role theme at AA"] = function()
		for _, id in ThemeData.IDS do
			local def = ThemeLogic.urkTheme(theme(id))
			t.equal(def.name, id)
			local resolved = UrkTheme.resolve({ [id] = def :: any }, id)
			local problems = UrkTheme.validate(resolved, "AA")
			local detail = if problems[1] then problems[1].kind .. " " .. problems[1].detail else ""
			t.equal(#problems, 0, id .. ": " .. detail)
		end
	end,
}
