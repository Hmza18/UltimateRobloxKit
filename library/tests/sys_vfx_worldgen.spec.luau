--!strict
local VFXLogic = require("../src/Systems/VFX/VFXLogic")
local WorldGenLogic = require("../src/Systems/WorldGen/WorldGenLogic")
local t = require("./lib/t")

local function layout(seed: number): WorldGenLogic.Layout
	return WorldGenLogic.generate({
		seed = seed,
		zones = { "Spawn", "Forest", "Desert", "Snow" },
		props = { { kind = "Tree", weight = 3, radius = 4 }, { kind = "Rock", weight = 1, radius = 3 } },
		minSpacing = 10,
	})
end

return {
	["quality follows graphics level, touch and frame rate"] = function()
		t.equal(VFXLogic.chooseQuality({ graphicsLevel = 2 }), "low")
		t.equal(VFXLogic.chooseQuality({ graphicsLevel = 9, touch = true }), "high")
		t.equal(VFXLogic.chooseQuality({ touch = true }), "low")
		t.equal(VFXLogic.chooseQuality({ touch = true, fps = 60 }), "medium")
		t.equal(VFXLogic.chooseQuality({ fps = 60 }), "high")
		t.equal(VFXLogic.chooseQuality({ fps = 30 }), "low")
		t.equal(VFXLogic.chooseQuality({}), "medium")
	end,

	["lower tiers emit fewer particles and drop optional layers"] = function()
		local high = VFXLogic.resolve("hatch", "high")
		local medium = VFXLogic.resolve("hatch", "medium")
		local low = VFXLogic.resolve("hatch", "low")
		t.equal(#high.layers, 2)
		t.equal(#low.layers, 1)
		t.truthy(VFXLogic.particleCount(high) > VFXLogic.particleCount(medium))
		t.truthy(VFXLogic.particleCount(medium) > VFXLogic.particleCount(low))
		t.truthy(VFXLogic.particleCount(low) >= 1)
		t.equal(VFXLogic.PRESETS.hatch.layers[1].burst, 40, "resolve never mutates the preset")
	end,

	["every built-in preset resolves at every tier"] = function()
		for _, name in VFXLogic.names() do
			for _, q in { "low", "medium", "high" } :: { VFXLogic.Quality } do
				local p = VFXLogic.resolve(name, q)
				t.truthy(#p.layers >= 1, name .. " " .. q)
			end
		end
	end,

	["register validates presets"] = function()
		t.throws(function()
			VFXLogic.register("bad", {
				layers = {
					{ name = "x", colors = {}, sizes = { 1 }, lifetime = { 1, 2 }, speed = { 1, 2 }, burst = 1 },
				},
			})
		end)
		VFXLogic.register("custom", {
			layers = {
				{
					name = "x",
					colors = { "#FFFFFF" },
					sizes = { 1 },
					lifetime = { 1, 2 },
					speed = { 1, 2 },
					rate = 5,
				},
			},
		})
		t.equal(VFXLogic.resolve("custom", "low").layers[1].rate, 1.75)
	end,

	["world layout is deterministic per seed"] = function()
		t.deepEqual(layout(42), layout(42))
		local other = layout(43)
		t.truthy(other.zones[1].props[1].position[1] ~= layout(42).zones[1].props[1].position[1])
	end,

	["zones, gates and path line up"] = function()
		local l = layout(7)
		t.equal(#l.zones, 4)
		t.equal(#l.gates, 3)
		t.equal(#l.path, 3)
		t.deepEqual(l.gates[1].between, { 1, 2 })
		t.equal(l.spawn.center[1], l.zones[1].floor.center[1])
	end,

	["props keep their spacing and stay inside their zone"] = function()
		local l = layout(99)
		for _, zone in l.zones do
			t.truthy(#zone.props > 5, zone.name .. " has props")
			t.truthy(WorldGenLogic.minDistance(zone) >= 10 - 1e-9, zone.name .. " spacing")
			for _, prop in zone.props do
				local c, s = zone.floor.center, zone.floor.size
				t.truthy(math.abs(prop.position[1] - c[1]) <= s[1] / 2, "inside x")
				t.truthy(math.abs(prop.position[3] - c[3]) <= s[3] / 2, "inside z")
				t.truthy(math.abs(prop.position[3] - c[3]) >= 7, "clear of the through path")
			end
		end
	end,

	["grid layouts keep consecutive zones next to each other"] = function()
		local l = WorldGenLogic.generate({
			seed = 1,
			zones = { "A", "B", "C", "D", "E", "F" },
			columns = 3,
			zoneSize = 100,
			gap = 20,
		})
		for i = 2, #l.zones do
			local a, b = l.zones[i - 1].floor.center, l.zones[i].floor.center
			t.equal(
				math.abs(a[1] - b[1]) + math.abs(a[3] - b[3]),
				120,
				"zone " .. i .. " is one step from zone " .. (i - 1)
			)
		end
		for _, strip in l.path do
			t.equal(math.max(strip.size[1], strip.size[3]), 120, "path strips span exactly one step")
		end
	end,

	["rng is in [0, 1)"] = function()
		local r = WorldGenLogic.rng(1)
		for _ = 1, 1000 do
			local v = r()
			t.truthy(v >= 0 and v < 1)
		end
	end,
}
