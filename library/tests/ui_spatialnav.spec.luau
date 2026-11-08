--!strict
-- SpatialNav: nearest-neighbour focus graph for gamepad navigation.

local t = require("./lib/t")
local SpatialNav = require("../src/UI/Core/SpatialNav")

-- A 3 x 3 grid of 100 x 50 buttons with 20 px gaps, ids r<row>c<column>.
local function grid(): { SpatialNav.Node }
	local nodes: { SpatialNav.Node } = {}
	for row = 1, 3 do
		for column = 1, 3 do
			table.insert(nodes, {
				id = string.format("r%dc%d", row, column),
				x = (column - 1) * 120,
				y = (row - 1) * 70,
				w = 100,
				h = 50,
			})
		end
	end
	return nodes
end

return {
	["centre of a grid links to its four neighbours"] = function()
		local graph = SpatialNav.build(grid())
		t.deepEqual(graph.r2c2, { up = "r1c2", down = "r3c2", left = "r2c1", right = "r2c3" })
	end,

	["corners have no links off the edge"] = function()
		local graph = SpatialNav.build(grid())
		t.equal(graph.r1c1.up, nil)
		t.equal(graph.r1c1.left, nil)
		t.equal(graph.r1c1.right, "r1c2")
		t.equal(graph.r1c1.down, "r2c1")
		t.equal(graph.r3c3.down, nil)
		t.equal(graph.r3c3.right, nil)
	end,

	["wrap links to the far side of the same row or column"] = function()
		local graph = SpatialNav.build(grid(), { wrap = true })
		t.equal(graph.r1c3.right, "r1c1")
		t.equal(graph.r1c1.up, "r3c1")
		t.equal(graph.r2c1.left, "r2c3")
	end,

	["aligned targets beat closer diagonal ones"] = function()
		local nodes: { SpatialNav.Node } = {
			{ id = "a", x = 0, y = 0, w = 100, h = 50 },
			{ id = "far", x = 300, y = 0, w = 100, h = 50 },
			{ id = "diagonal", x = 120, y = 200, w = 100, h = 50 },
		}
		t.equal(SpatialNav.neighbour(nodes, nodes[1], "right"), "far")
		t.equal(SpatialNav.neighbour(nodes, nodes[1], "down"), "diagonal")
	end,

	["maxCross ignores targets too far sideways"] = function()
		local nodes: { SpatialNav.Node } = {
			{ id = "a", x = 0, y = 0, w = 100, h = 50 },
			{ id = "offset", x = 0, y = 400, w = 100, h = 50 },
			{ id = "side", x = 500, y = 120, w = 100, h = 50 },
		}
		t.equal(SpatialNav.neighbour(nodes, nodes[1], "right"), "side")
		t.equal(SpatialNav.neighbour(nodes, nodes[1], "right", { maxCross = 50 }), nil)
	end,

	["move, first and invalid input"] = function()
		local nodes = grid()
		local graph = SpatialNav.build(nodes)
		t.equal(SpatialNav.move(graph, "r2c2", "up"), "r1c2")
		t.equal(SpatialNav.move(graph, "missing", "up"), nil)
		t.equal(SpatialNav.move(graph, "r2c2", "sideways"), nil)
		t.equal(SpatialNav.first(nodes), "r1c1")
		t.equal(SpatialNav.first({}), nil)
		t.throws(function()
			SpatialNav.neighbour(nodes, nodes[1], "diagonal")
		end)
		t.throws(function()
			SpatialNav.build({ nodes[1], nodes[1] })
		end, "duplicate ids")
	end,

	["results do not depend on input order"] = function()
		local nodes = grid()
		local reversed: { SpatialNav.Node } = {}
		for index = #nodes, 1, -1 do
			table.insert(reversed, nodes[index])
		end
		t.deepEqual(SpatialNav.build(reversed), SpatialNav.build(nodes))
	end,
}
