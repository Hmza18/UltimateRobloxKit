local process = require("@lune/process")
local EffectLogic = require("../src/Visuals/VFX/EffectLogic")
local Registry = require("../src/Visuals/Core/Registry")
local Quality = require("../src/Visuals/Core/Quality")
local total = 0
for _, name in process.args do
	local list = require("../src/Visuals/VFX/" .. name)
	for _, preset in list do
		total += 1
		local problems = Registry.validate(preset)
		for _, p in EffectLogic.validate(preset.data) do table.insert(problems, p) end
		local c = EffectLogic.cost(preset.data)
		local lo = EffectLogic.resolve(preset.data, Quality.profile("Low"), nil, 1)
		local hi = EffectLogic.resolve(preset.data, Quality.profile("High"), nil, 1)
		print(string.format("%-18s %-6s worst=%3d L%d  low=%3d/%d layers  high=%3d/%d  dur=%.2f linger=%.2f", preset.id, preset.quality.cost, c.particles, c.lights, lo.particles, #lo.layers, hi.particles, #hi.layers, hi.duration, hi.linger))
		for _, p in problems do print("   PROBLEM " .. p) end
	end
end
print(total, "presets")
