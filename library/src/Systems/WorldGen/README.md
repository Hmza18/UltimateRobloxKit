# WorldGen

Deterministic layouts for zone-based games. `WorldGenLogic.generate(options)` returns plain data: zone floors in a row or grid, a path and a gate between neighbours, a spawn pad, and props scattered with a minimum spacing that keeps the spawn, gates and the path clear. The same seed always gives the same layout. `WorldGenBuilder.build(layout, options)` makes a blockout in Studio.

```luau
local layout = WorldGenLogic.generate({
	seed = 42,
	zones = { "Spawn", "Forest", "Desert", "Volcano" },
	zoneSize = 160, gap = 24, columns = 4,
	props = { { kind = "Tree", weight = 3, radius = 4 }, { kind = "Rock", weight = 1, radius = 3 } },
	density = 0.6, minSpacing = 10,
})
WorldGenBuilder.build(layout, { templates = ServerStorage.Props, palette = { "#7BC96F", "#E8C872" } })
```

- Props are cloned from `templates` by kind (Model or BasePart); missing kinds become placeholder blocks.
- Gates are tagged `URK_Gate` with `ZoneFrom` and `ZoneTo` attributes and a name label, so `ProgressionServer:isWorldUnlocked` or `Systems/Zones` can lock them.
- `WorldGenLogic.rng(seed)` is a small deterministic generator you can reuse; `minDistance(zone)` is for tests.

Build once in Studio (Command Bar or a plugin), then save the place: generating at every server start is possible but makes hand edits impossible.
