--!strict
local Placement = require("../src/Systems/Placement/PlacementLogic")
local t = require("./lib/t")

local CONFIG = Placement.resolveConfig({ gridSize = 4, rotationSteps = 4, maxItems = 5 })
local PLOT = { width = 32, depth = 32 }
local CATALOG = {
	chair = { size = { x = 4, z = 4 } },
	table = { size = { x = 8, z = 4 }, maxCount = 2 },
	bed = { size = { x = 4, z = 8 } },
}

local function request(itemId: string, x: number, z: number, rotation: number?): any
	return { itemId = itemId, x = x, z = z, rotation = rotation or 0 }
end

local function place(layout: any, itemId: string, x: number, z: number, rotation: number?): (boolean, string?, string?)
	return Placement.place(layout, request(itemId, x, z, rotation), CATALOG, PLOT, CONFIG)
end

return {
	["resolveConfig validates values"] = function()
		local config = Placement.resolveConfig({ gridSize = 0, rotationSteps = 2.5, maxItems = -1 })
		t.equal(config.gridSize, 4)
		t.equal(config.rotationSteps, 4)
		t.equal(config.maxItems, 200)
	end,

	["snapping and rotation steps"] = function()
		t.equal(Placement.snap(5.9, 4), 4)
		t.equal(Placement.snap(6.1, 4), 8)
		t.equal(Placement.snap(-1.9, 4), 0)
		t.equal(Placement.normalizeRotation(-1, 4), 3)
		t.equal(Placement.rotationDegrees(5, 4), 90)
	end,

	["rotated sizes swap and grow"] = function()
		local size = { x = 8, z = 4 }
		t.deepEqual(Placement.rotatedSize(size, 1, 4), { x = 4, z = 8 })
		t.deepEqual(Placement.rotatedSize(size, 2, 4), { x = 8, z = 4 })
		local diagonal = Placement.rotatedSize(size, 1, 8)
		t.near(diagonal.x, 12 * math.sqrt(0.5), 1e-5)
		t.near(diagonal.z, 12 * math.sqrt(0.5), 1e-5)
	end,

	["snapPosition aligns box edges to the grid"] = function()
		local x, z = Placement.snapPosition(5.1, 6.9, { x = 4, z = 4 }, 0, CONFIG)
		t.equal(x, 6)
		t.equal(z, 6)
		x, z = Placement.snapPosition(5, 5, { x = 8, z = 4 }, 0, CONFIG)
		t.equal(x, 4)
		t.equal(z, 6)
		x, z = Placement.snapPosition(5, 5, { x = 8, z = 4 }, 1, CONFIG)
		t.equal(x, 6)
		t.equal(z, 4)
	end,

	["overlap ignores touching edges"] = function()
		local a = { minX = 0, minZ = 0, maxX = 4, maxZ = 4 }
		t.falsy(Placement.overlaps(a, { minX = 4, minZ = 0, maxX = 8, maxZ = 4 }))
		t.truthy(Placement.overlaps(a, { minX = 3, minZ = 3, maxX = 5, maxZ = 5 }))
		t.falsy(Placement.overlaps(a, { minX = 0, minZ = 5, maxX = 4, maxZ = 9 }))
		t.truthy(Placement.insidePlot(a, PLOT))
		t.falsy(Placement.insidePlot({ minX = -1, minZ = 0, maxX = 3, maxZ = 4 }, PLOT))
	end,

	["validate refuses bad requests"] = function()
		local layout = Placement.newLayout()
		local ok, reason, id = place(layout, "chair", 2, 2)
		t.truthy(ok)
		t.equal(reason, nil)
		t.equal(id, "1")
		t.equal(select(2, place(layout, "chair", 2, 2)), "overlap")
		t.truthy(place(layout, "chair", 6, 2), "touching neighbours are fine")
		t.equal(select(2, place(layout, "chair", 5, 5)), "not on grid")
		t.equal(select(2, place(layout, "chair", 34, 2)), "out of bounds")
		t.equal(select(2, place(layout, "sofa", 2, 10)), "unknown item")
		t.equal(select(2, place(layout, "chair", math.sqrt(-1), 2)), "invalid request")
		t.equal(select(2, place(layout, "chair", 2, 10, 0.5)), "invalid request")
		t.equal(select(2, Placement.place(layout, nil, CATALOG, PLOT, CONFIG)), "invalid request")
		t.equal(Placement.count(layout), 2)
	end,

	["item and plot limits"] = function()
		local layout = Placement.newLayout()
		t.truthy(place(layout, "table", 4, 2))
		t.truthy(place(layout, "table", 4, 6))
		t.equal(select(2, place(layout, "table", 4, 10)), "limit reached")
		t.truthy(place(layout, "chair", 10, 2))
		t.truthy(place(layout, "chair", 14, 2))
		t.truthy(place(layout, "chair", 18, 2))
		t.equal(select(2, place(layout, "chair", 22, 2)), "limit reached")
		t.equal(Placement.count(layout, "table"), 2)
	end,

	["move validates against everything but itself"] = function()
		local layout = Placement.newLayout()
		place(layout, "chair", 2, 2)
		place(layout, "chair", 10, 2)
		place(layout, "table", 4, 10)
		place(layout, "table", 4, 14)
		t.truthy(Placement.move(layout, "1", 6, 2, 0, CATALOG, PLOT, CONFIG))
		t.equal(select(2, Placement.move(layout, "1", 10, 2, 0, CATALOG, PLOT, CONFIG)), "overlap")
		t.truthy(Placement.move(layout, "1", 6, 2, 0, CATALOG, PLOT, CONFIG), "its own old spot is free")
		t.truthy(Placement.move(layout, "2", 10, 2, 5, CATALOG, PLOT, CONFIG))
		t.equal(layout.items["2"].rotation, 1)
		t.truthy(Placement.move(layout, "3", 4, 22, 0, CATALOG, PLOT, CONFIG), "moving does not hit maxCount")
		t.equal(select(2, Placement.move(layout, "9", 2, 2, 0, CATALOG, PLOT, CONFIG)), "unknown placement")
	end,

	["rotated footprints collide correctly"] = function()
		local layout = Placement.newLayout()
		t.truthy(place(layout, "bed", 2, 4))
		t.truthy(place(layout, "bed", 8, 2, 1))
		t.deepEqual(Placement.footprint(8, 2, CATALOG.bed.size, 1, 4), { minX = 4, minZ = 0, maxX = 12, maxZ = 4 })
		t.equal(select(2, place(layout, "chair", 6, 2)), "overlap")
		t.truthy(place(layout, "chair", 6, 6))
	end,

	["remove and list"] = function()
		local layout = Placement.newLayout()
		for index = 1, 3 do
			place(layout, "chair", 2 + (index - 1) * 4, 2)
		end
		local removed = Placement.remove(layout, "2")
		t.truthy(removed)
		t.equal(Placement.remove(layout, "2"), nil)
		local ids: { string } = {}
		for _, placed in Placement.list(layout) do
			table.insert(ids, placed.id)
		end
		t.deepEqual(ids, { "1", "3" })
	end,

	["serialize and deserialize re-validate"] = function()
		local layout = Placement.newLayout()
		place(layout, "chair", 2, 2)
		place(layout, "table", 4, 6)
		place(layout, "bed", 12, 2, 1)
		local restored, dropped = Placement.deserialize(Placement.serialize(layout), CATALOG, PLOT, CONFIG)
		t.equal(dropped, 0)
		t.deepEqual(restored, layout)
		local saved = {
			items = {
				{ itemId = "chair", x = 2, z = 2, rotation = 0 },
				{ itemId = "chair", x = 2, z = 2, rotation = 0 },
				{ itemId = "sofa", x = 10, z = 10, rotation = 0 },
				"junk",
				{ itemId = "chair", x = 5, z = 5, rotation = 0 },
			},
		}
		local dirty, droppedDirty = Placement.deserialize(saved, CATALOG, PLOT, CONFIG)
		t.equal(Placement.count(dirty), 1)
		t.equal(droppedDirty, 4)
		local empty, none = Placement.deserialize("x", CATALOG, PLOT, CONFIG)
		t.equal(Placement.count(empty), 0)
		t.equal(none, 0)
	end,
}
