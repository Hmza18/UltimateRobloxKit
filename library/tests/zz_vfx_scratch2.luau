local Catalog = require("../src/Visuals/VFX/CatalogData")
local EffectLogic = require("../src/Visuals/VFX/EffectLogic")
local r = Catalog.registry()
print(r:count())
local n = {low=0,medium=0,high=0}
for _, p in r:list() do n[p.quality.cost] += 1; local pr = EffectLogic.validate(p.data); for _, x in pr do print(p.id, x) end; if p.quality.cost ~= "low" then print(p.id, p.quality.cost) end end
print(n.low, n.medium, n.high)
