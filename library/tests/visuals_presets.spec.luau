--!strict
local DebugLogic = require("../src/Visuals/Debug/DebugLogic")
local PresetsLogic = require("../src/Visuals/Presets/PresetsLogic")
local Registry = require("../src/Visuals/Core/Registry")
local t = require("./lib/t")

local function preset(id: string, category: string, extra: { [string]: any }?): Registry.Preset
	local base: any = {
		id = id,
		name = id,
		category = category,
		description = "A preset used by the catalogue spec.",
		data = {},
	}
	for key, value in extra or {} do
		base[key] = value
	end
	return base
end

local function catalog()
	local vfx = Registry.new("vfx")
	vfx:register(preset("CoinBurst", "rewards", { tags = { "currency" } }))
	vfx:register(preset("Rain", "environment"))
	local ui = Registry.new("ui")
	ui:register(preset("BouncyPress", "buttons", { usage = 'Visuals.UI:Animate(button, "BouncyPress")' }))
	ui:register(preset("CoinCount", "text"))
	local all = PresetsLogic.new()
	all:add(vfx)
	all:add(ui)
	return all, vfx
end

return {
	["catalog: kinds, counts and listing"] = function()
		local all = catalog()
		t.deepEqual(all:kinds(), { "ui", "vfx" })
		t.equal(all:count(), 4)
		t.equal(#all:list(), 4)
		t.deepEqual(all:list("vfx", { category = "rewards" }), { { kind = "vfx", id = "CoinBurst" } })
		t.equal(all:registry("nope"), nil)
	end,
	["catalog: search spans kinds and is stable"] = function()
		local all = catalog()
		local found = all:search("coin")
		t.equal(#found, 2)
		t.equal(found[1].kind .. ":" .. found[1].id, "ui:CoinCount")
		t.equal(found[2].kind .. ":" .. found[2].id, "vfx:CoinBurst")
		t.equal(#all:search("coin", 1), 1)
		t.equal(#all:search("nothing-here"), 0)
	end,
	["catalog: usage lines default per kind and export is plain data"] = function()
		local all, vfx = catalog()
		t.equal(all:usage("vfx", "CoinBurst"), 'Visuals:Play("CoinBurst", position)')
		t.equal(all:usage("ui", "BouncyPress"), 'Visuals.UI:Animate(button, "BouncyPress")')
		t.equal(all:describe("vfx", "Rain").usage, 'Visuals:Play("Rain", position)')
		local exported = all:export()
		t.equal(exported.total, 4)
		t.equal(#exported.kinds.vfx, 2)
		t.equal(exported.kinds.vfx[1].data, nil)
		vfx:register(preset("CoinBurst", "rewards", { name = "Mine" }), { override = true })
		t.truthy(all:describe("vfx", "CoinBurst").overridden)
		t.throws(function()
			all:describe("nope", "X")
		end)
	end,
	["debug: sampler statistics"] = function()
		local sampler = DebugLogic.sampler(4)
		t.equal(sampler:fps(), 0)
		for _, value in { 0.01, 0.02, 0.03, 0.04, 0.05 } do
			sampler:push(value)
		end
		sampler:push(0 / 0)
		sampler:push(-1)
		t.equal(sampler:count(), 4, "ring buffer keeps the last four")
		t.near(sampler:average(), 0.035, 1e-9)
		t.near(sampler:worst(), 0.05, 1e-9)
		t.near(sampler:percentile(50), 0.03, 1e-9)
		t.near(sampler:percentile(100), 0.05, 1e-9)
		t.equal(sampler:hitches(), 2)
		sampler:reset()
		t.equal(sampler:count(), 0)
	end,
	["debug: compare and format"] = function()
		local same = DebugLogic.compare({ average = 0.016, p99 = 0.02 }, { average = 0.016, p99 = 0.02 })
		t.equal(same.verdict, "ok")
		t.equal(
			DebugLogic.compare({ average = 0.016, p99 = 0.02 }, { average = 0.017, p99 = 0.02 }).verdict,
			"noticeable"
		)
		t.equal(
			DebugLogic.compare({ average = 0.016, p99 = 0.02 }, { average = 0.02, p99 = 0.03 }).verdict,
			"expensive"
		)
		local sampler = DebugLogic.sampler()
		sampler:push(1 / 60)
		local lines = DebugLogic.format(
			{ level = "High", tracks = 2, effects = 3, particles = 120, rejected = { throttled = 4 } },
			sampler
		)
		t.truthy(string.find(lines[1], "High", 1, true))
		t.truthy(string.find(lines[1], "60 fps", 1, true))
		t.equal(lines[#lines], "skipped: throttled 4")
	end,
}
