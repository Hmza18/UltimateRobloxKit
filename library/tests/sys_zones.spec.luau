--!strict
local ZonesLogic = require("../src/Systems/Zones/ZonesLogic")
local t = require("./lib/t")

local v = ZonesLogic.vec3

local function kinds(changes: { ZonesLogic.Change }): string
	local parts: { string } = {}
	for _, change in changes do
		table.insert(parts, change.kind .. ":" .. tostring(change.zoneId))
	end
	return table.concat(parts, ",")
end

local function forKey(changes: { ZonesLogic.Change }, key: any): { ZonesLogic.Change }
	local out: { ZonesLogic.Change } = {}
	for _, change in changes do
		if change.key == key then
			table.insert(out, change)
		end
	end
	return out
end

-- An L shape: the square 0..4 with the corner 1..4 x 1..4 cut out.
local L_SHAPE: { ZonesLogic.Point2 } = {
	{ x = 0, z = 0 },
	{ x = 4, z = 0 },
	{ x = 4, z = 1 },
	{ x = 1, z = 1 },
	{ x = 1, z = 4 },
	{ x = 0, z = 4 },
}

return {
	["a box contains its center and edges but not points outside"] = function()
		local box = ZonesLogic.box(v(10, 0, 10), v(2, 1, 3))
		t.truthy(ZonesLogic.contains(box, v(10, 0, 10)))
		t.truthy(ZonesLogic.contains(box, v(12, 1, 13)), "corners count as inside")
		t.falsy(ZonesLogic.contains(box, v(12.01, 0, 10)))
		t.falsy(ZonesLogic.contains(box, v(10, 1.5, 10)), "height is checked")
		t.falsy(ZonesLogic.contains(box, v(10, 0, 6.9)))
	end,

	["a box yaw follows CFrame.Angles(0, yaw, 0)"] = function()
		-- Local +X maps to world -Z after a quarter turn, so the long side runs along Z.
		local box = ZonesLogic.box(v(0, 0, 0), v(4, 1, 1), math.pi / 2)
		t.truthy(ZonesLogic.contains(box, v(0, 0, 3.5)))
		t.truthy(ZonesLogic.contains(box, v(0, 0, -3.5)))
		t.falsy(ZonesLogic.contains(box, v(3.5, 0, 0)))
		local p = ZonesLogic.toLocal(box, v(0, 0, -2))
		t.near(p.x, 2, 1e-9, "world -Z is local +X")
		t.near(p.z, 0, 1e-9)
	end,

	["a 45 degree box reaches further along its diagonal"] = function()
		local box = ZonesLogic.box(v(0, 0, 0), v(1, 1, 1), math.pi / 4)
		t.truthy(ZonesLogic.contains(box, v(1.3, 0, 0)))
		t.falsy(ZonesLogic.contains(ZonesLogic.box(v(0, 0, 0), v(1, 1, 1)), v(1.3, 0, 0)))
		t.falsy(ZonesLogic.contains(box, v(1.0, 0, 1.0)), "the old corner is now outside")
	end,

	["box margins grow and shrink the box"] = function()
		local box = ZonesLogic.box(v(0, 0, 0), v(2, 2, 2))
		t.truthy(ZonesLogic.contains(box, v(2.5, 0, 0), 1))
		t.falsy(ZonesLogic.contains(box, v(2.5, 0, 0), 0))
		t.falsy(ZonesLogic.contains(box, v(1.5, 0, 0), -1))
		t.truthy(ZonesLogic.contains(box, v(0.5, 0, 0), -1))
	end,

	["a sphere checks distance with margins"] = function()
		local sphere = ZonesLogic.sphere(v(0, 5, 0), 3)
		t.truthy(ZonesLogic.contains(sphere, v(0, 8, 0)), "on the surface")
		t.falsy(ZonesLogic.contains(sphere, v(2.2, 7.2, 0)))
		t.truthy(ZonesLogic.contains(sphere, v(2.2, 7.2, 0), 1))
		t.falsy(ZonesLogic.contains(sphere, v(0, 5, 0), -4), "a margin below -radius contains nothing")
	end,

	["a prism handles concave outlines and height"] = function()
		local prism = ZonesLogic.prism(L_SHAPE, 0, 10)
		t.truthy(ZonesLogic.contains(prism, v(0.5, 5, 0.5)))
		t.truthy(ZonesLogic.contains(prism, v(0.5, 5, 3)))
		t.truthy(ZonesLogic.contains(prism, v(3, 5, 0.5)))
		t.falsy(ZonesLogic.contains(prism, v(3, 5, 3)), "inside the cut-out corner")
		t.falsy(ZonesLogic.contains(prism, v(0.5, 11, 0.5)), "above the prism")
		t.falsy(ZonesLogic.contains(prism, v(0.5, -0.1, 0.5)), "below the prism")
	end,

	["prism margins use the distance to the nearest edge"] = function()
		local prism = ZonesLogic.prism(L_SHAPE, 0, 10)
		t.truthy(ZonesLogic.contains(prism, v(4.5, 5, 0.5), 1))
		t.falsy(ZonesLogic.contains(prism, v(4.5, 5, 0.5), 0.4))
		t.truthy(ZonesLogic.contains(prism, v(0.5, 5, 0.5), -0.4))
		t.falsy(ZonesLogic.contains(prism, v(0.5, 5, 0.5), -0.6))
		t.truthy(ZonesLogic.contains(prism, v(0.5, 10.5, 0.5), 1), "the margin also grows the height")
	end,

	["prism winding order does not matter"] = function()
		local reversed: { ZonesLogic.Point2 } = {}
		for index = #L_SHAPE, 1, -1 do
			table.insert(reversed, L_SHAPE[index])
		end
		local prism = ZonesLogic.prism(reversed, 0, 1)
		t.truthy(ZonesLogic.contains(prism, v(0.5, 0.5, 3)))
		t.falsy(ZonesLogic.contains(prism, v(3, 0.5, 3)))
	end,

	["shape constructors reject invalid input"] = function()
		t.throws(function()
			ZonesLogic.box(v(0, 0, 0), v(0, 1, 1))
		end)
		t.throws(function()
			ZonesLogic.box(v(0 / 0, 0, 0), v(1, 1, 1))
		end)
		t.throws(function()
			ZonesLogic.box(v(0, 0, 0), v(1, 1, 1), math.huge)
		end)
		t.throws(function()
			ZonesLogic.sphere(v(0, 0, 0), 0)
		end)
		t.throws(function()
			ZonesLogic.prism({ { x = 0, z = 0 }, { x = 1, z = 0 } }, 0, 1)
		end)
		t.throws(function()
			ZonesLogic.prism({ { x = 0, z = 0 }, { x = 1, z = 1 }, { x = 2, z = 2 } }, 0, 1)
		end, "collinear points have no area")
		t.throws(function()
			ZonesLogic.prism(L_SHAPE, 5, 5)
		end)
	end,

	["prism copies its points"] = function()
		local points = { { x = 0, z = 0 }, { x = 2, z = 0 }, { x = 0, z = 2 } }
		local prism = ZonesLogic.prism(points, 0, 1)
		points[2].x = 100
		t.falsy(ZonesLogic.contains(prism, v(50, 0.5, 0.1)))
	end,

	["bounds cover rotated boxes, spheres and prisms"] = function()
		local low, high = ZonesLogic.bounds(ZonesLogic.box(v(0, 0, 0), v(2, 1, 1), math.pi / 2))
		t.near(high.x, 1, 1e-9)
		t.near(high.z, 2, 1e-9)
		t.near(low.y, -1, 1e-9)
		local sLow, sHigh = ZonesLogic.bounds(ZonesLogic.sphere(v(1, 1, 1), 2), 1)
		t.equal(sLow.x, -2)
		t.equal(sHigh.y, 4)
		local pLow, pHigh = ZonesLogic.bounds(ZonesLogic.prism(L_SHAPE, 0, 3))
		t.deepEqual(pLow, { x = 0, y = 0, z = 0 })
		t.deepEqual(pHigh, { x = 4, y = 3, z = 4 })
	end,

	["new and addZone validate settings"] = function()
		t.throws(function()
			ZonesLogic.new({ hysteresis = -1 })
		end)
		t.throws(function()
			ZonesLogic.new({ leaveDelay = 0 / 0 })
		end)
		local state = ZonesLogic.new()
		local shape = ZonesLogic.sphere(v(0, 0, 0), 1)
		ZonesLogic.addZone(state, "A", shape)
		t.throws(function()
			ZonesLogic.addZone(state, "A", shape)
		end, "duplicate id")
		t.throws(function()
			ZonesLogic.addZone(state, "", shape)
		end)
		t.throws(function()
			ZonesLogic.addZone(state, "B", shape, { priority = 0 / 0 })
		end)
		t.throws(function()
			ZonesLogic.addZone(state, "C", shape, { hysteresis = -2 })
		end)
		t.equal((ZonesLogic.getZone(state, "A") :: ZonesLogic.Zone).hysteresis, 0)
	end,

	["update reports enter, primary and leave"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "Shop", ZonesLogic.box(v(0, 0, 0), v(5, 5, 5)))
		local entered = ZonesLogic.update(state, { p1 = v(0, 0, 0) }, 1)
		t.equal(kinds(entered), "enter:Shop,primary:Shop")
		t.equal(entered[1].key, "p1")
		t.equal(#ZonesLogic.update(state, { p1 = v(1, 0, 1) }, 2), 0, "moving inside changes nothing")
		local left = ZonesLogic.update(state, { p1 = v(20, 0, 0) }, 3)
		t.equal(kinds(left), "leave:Shop,primary:nil")
		t.equal(left[2].previous, "Shop")
		t.equal(state.records["p1"], nil, "keys in no zone are not kept")
	end,

	["hysteresis keeps a key inside until it is clearly out"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "Ring", ZonesLogic.sphere(v(0, 0, 0), 5), { hysteresis = 1 })
		t.equal(kinds(ZonesLogic.update(state, { k = v(4.5, 0, 0) }, 0)), "enter:Ring,primary:Ring")
		t.equal(#ZonesLogic.update(state, { k = v(5.5, 0, 0) }, 1), 0, "inside the hysteresis band")
		t.equal(kinds(ZonesLogic.update(state, { k = v(6.5, 0, 0) }, 2)), "leave:Ring,primary:nil")
		t.equal(#ZonesLogic.update(state, { k = v(5.5, 0, 0) }, 3), 0, "the band does not count for entering")
	end,

	["the state hysteresis is the default for new zones"] = function()
		local state = ZonesLogic.new({ hysteresis = 2 })
		local zone = ZonesLogic.addZone(state, "A", ZonesLogic.sphere(v(0, 0, 0), 1))
		t.equal(zone.hysteresis, 2)
		local custom = ZonesLogic.addZone(state, "B", ZonesLogic.sphere(v(0, 0, 0), 1), { hysteresis = 0 })
		t.equal(custom.hysteresis, 0)
	end,

	["leaveDelay keeps membership for a while after leaving"] = function()
		local state = ZonesLogic.new({ leaveDelay = 2 })
		ZonesLogic.addZone(state, "Door", ZonesLogic.box(v(0, 0, 0), v(1, 1, 1)))
		ZonesLogic.update(state, { k = v(0, 0, 0) }, 10)
		t.equal(#ZonesLogic.update(state, { k = v(5, 0, 0) }, 11), 0)
		t.equal(#ZonesLogic.update(state, { k = v(0, 0, 0) }, 11.5), 0, "coming back refreshes the timer")
		t.equal(#ZonesLogic.update(state, { k = v(5, 0, 0) }, 13), 0)
		t.equal(kinds(ZonesLogic.update(state, { k = v(5, 0, 0) }, 13.5)), "leave:Door,primary:nil")
	end,

	["overlapping zones are all entered and the top priority is primary"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "Town", ZonesLogic.sphere(v(0, 0, 0), 50), { priority = 1 })
		ZonesLogic.addZone(state, "Tavern", ZonesLogic.box(v(0, 0, 0), v(5, 5, 5)), { priority = 10 })
		local changes = ZonesLogic.update(state, { k = v(0, 0, 0) }, 0)
		t.equal(kinds(changes), "enter:Tavern,enter:Town,primary:Tavern")
		t.equal(ZonesLogic.primaryOf(state, "k"), "Tavern")
		local out = ZonesLogic.update(state, { k = v(20, 0, 0) }, 1)
		t.equal(kinds(out), "leave:Tavern,primary:Town")
		t.equal(out[2].previous, "Tavern")
	end,

	["priority ties are broken by zone id"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "Beta", ZonesLogic.sphere(v(0, 0, 0), 5))
		ZonesLogic.addZone(state, "Alpha", ZonesLogic.sphere(v(0, 0, 0), 5))
		ZonesLogic.update(state, { k = v(0, 0, 0) }, 0)
		t.equal(ZonesLogic.primaryOf(state, "k"), "Alpha")
		t.equal(ZonesLogic.topZoneAt(state, v(0, 0, 0)), "Alpha")
	end,

	["exclusive mode keeps a key in the top zone only"] = function()
		local state = ZonesLogic.new({ exclusive = true })
		ZonesLogic.addZone(state, "Field", ZonesLogic.sphere(v(0, 0, 0), 50), { priority = 1 })
		ZonesLogic.addZone(state, "Arena", ZonesLogic.box(v(0, 0, 0), v(5, 5, 5)), { priority = 5 })
		t.equal(kinds(ZonesLogic.update(state, { k = v(30, 0, 0) }, 0)), "enter:Field,primary:Field")
		local inArena = ZonesLogic.update(state, { k = v(0, 0, 0) }, 1)
		t.equal(kinds(inArena), "leave:Field,enter:Arena,primary:Arena")
		t.deepEqual(ZonesLogic.zonesOf(state, "k"), { "Arena" })
		local back = ZonesLogic.update(state, { k = v(30, 0, 0) }, 2)
		t.equal(kinds(back), "leave:Arena,enter:Field,primary:Field")
	end,

	["keys are tracked independently"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.box(v(0, 0, 0), v(2, 2, 2)))
		local changes = ZonesLogic.update(state, { one = v(0, 0, 0), two = v(9, 0, 0) }, 0)
		t.equal(kinds(forKey(changes, "one")), "enter:A,primary:A")
		t.equal(#forKey(changes, "two"), 0)
		t.deepEqual(ZonesLogic.keysIn(state, "A"), { "one" })
		t.truthy(ZonesLogic.isIn(state, "one", "A"))
		t.falsy(ZonesLogic.isIn(state, "two", "A"))
	end,

	["keys missing from an update leave their zones"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.box(v(0, 0, 0), v(2, 2, 2)))
		ZonesLogic.update(state, { one = v(0, 0, 0), two = v(1, 0, 0) }, 0)
		local changes = ZonesLogic.update(state, { two = v(1, 0, 0) }, 1)
		t.equal(kinds(forKey(changes, "one")), "leave:A,primary:nil")
		t.equal(#forKey(changes, "two"), 0)
	end,

	["invalid positions count as missing"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.box(v(0, 0, 0), v(2, 2, 2)))
		ZonesLogic.update(state, { k = v(0, 0, 0) }, 0)
		local bad: any = { k = { x = 0 / 0, y = 0, z = 0 } }
		t.equal(kinds(ZonesLogic.update(state, bad, 1)), "leave:A,primary:nil")
		t.throws(function()
			ZonesLogic.update(state, {}, 0 / 0)
		end)
	end,

	["removeKey returns leave changes and forgets the key"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.box(v(0, 0, 0), v(2, 2, 2)))
		ZonesLogic.addZone(state, "B", ZonesLogic.sphere(v(0, 0, 0), 3))
		ZonesLogic.update(state, { k = v(0, 0, 0) }, 0)
		t.equal(kinds(ZonesLogic.removeKey(state, "k")), "leave:A,leave:B,primary:nil")
		t.deepEqual(ZonesLogic.zonesOf(state, "k"), {})
		t.equal(#ZonesLogic.removeKey(state, "nobody"), 0)
	end,

	["removeZone evicts its members and recomputes the primary"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "Top", ZonesLogic.sphere(v(0, 0, 0), 3), { priority = 2 })
		ZonesLogic.addZone(state, "Base", ZonesLogic.sphere(v(0, 0, 0), 30))
		ZonesLogic.update(state, { a = v(0, 0, 0), b = v(10, 0, 0) }, 0)
		local changes = ZonesLogic.removeZone(state, "Top")
		t.equal(kinds(forKey(changes, "a")), "leave:Top,primary:Base")
		t.equal(#forKey(changes, "b"), 0)
		t.equal(ZonesLogic.getZone(state, "Top"), nil)
		t.equal(#ZonesLogic.removeZone(state, "Top"), 0, "removing twice is harmless")
		t.equal(#ZonesLogic.update(state, { a = v(0, 0, 0), b = v(10, 0, 0) }, 1), 0)
	end,

	["updateRaw ignores unknown zone ids"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.sphere(v(0, 0, 0), 1))
		local changes = ZonesLogic.updateRaw(state, { k = { A = true, Ghost = true } }, 0)
		t.equal(kinds(changes), "enter:A,primary:A")
	end,

	["zonesAt applies hysteresis only for zones the key is in"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.sphere(v(0, 0, 0), 5), { hysteresis = 2 })
		t.deepEqual(ZonesLogic.zonesAt(state, v(6, 0, 0), "k"), {})
		ZonesLogic.update(state, { k = v(0, 0, 0) }, 0)
		t.deepEqual(ZonesLogic.zonesAt(state, v(6, 0, 0), "k"), { A = true })
		t.deepEqual(ZonesLogic.zonesAt(state, v(6, 0, 0)), {}, "no key means no hysteresis")
	end,

	["topZoneAt returns nil outside every zone"] = function()
		local state = ZonesLogic.new()
		ZonesLogic.addZone(state, "A", ZonesLogic.sphere(v(0, 0, 0), 1))
		t.equal(ZonesLogic.topZoneAt(state, v(5, 5, 5)), nil)
	end,
}
