# Placement

Grid building for tycoons, sandboxes and housing: snapping, rotation steps, footprint collision, plot bounds, per-item and per-plot limits, save and load. The server validates every placement; the client shows a ghost preview coloured by the same rules.

| File | Runs on | Role |
| --- | --- | --- |
| `PlacementLogic.luau` | anywhere (pure) | snapping, rotated footprints, AABB overlap, validation, layout, persistence |
| `PlacementServer.luau` | server | remotes, validation, model spawning on the player's plot, store |
| `PlacementClient.luau` | client | ghost preview, rotate, confirm, move, remove |
| `PlacementConfig.luau` | anywhere | defaults |

## Coordinates

Everything in the logic is plot-local 2D: `x` runs from 0 to the plot part's `Size.X`, `z` from 0 to `Size.Z`. An item's `x, z` is the centre of its footprint. The server places models on the plot part's top face with `PlacementServer.toWorld(plot, x, z, degrees)`. Template models need their pivot at the bottom centre.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `PlacementLogic.resolveConfig(overrides?)` | `Config` | `gridSize`, `rotationSteps`, `maxItems` |
| `snap(value, grid)`, `normalizeRotation(step, steps)`, `rotationDegrees(step, steps)` | | |
| `rotatedSize(size, step, steps)` | `Size` | box around the rotated rectangle |
| `snapPosition(x, z, size, step, config)` | `x, z` | box edges land on grid lines |
| `footprint(x, z, size, step, steps)`, `overlaps(a, b)`, `insidePlot(box, plot)` | | touching edges do not overlap |
| `validate(layout, request, catalog, plot, config, ignoreId?)` | `ok, reason` | invalid request, unknown item, not on grid, out of bounds, overlap, limit reached |
| `place(layout, request, catalog, plot, config)` | `ok, reason, id` | |
| `move(layout, id, x, z, rotation, catalog, plot, config)`, `remove(layout, id)`, `list(layout)`, `count(layout, itemId?)` | | |
| `serialize(layout)` / `deserialize(data, catalog, plot, config)` | data / `layout, dropped` | load re-validates every item |
| `PlacementServer.new(options)` | `Service` | `layoutOf`, `clear`, `reload`, `placed`, `removed`, `destroy` |
| `PlacementClient.new(options)` | `Client` | `start(itemId)`, `rotate(steps?)`, `confirm()`, `cancel()`, `move`, `remove`, `isValid`, `layout`, `layoutChanged`, `rejected` |

Catalog: `{ [itemId] = { size = { x = 8, z = 4 }, maxCount = 2? } }`.

## Config (`PlacementConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `gridSize` | 4 | studs per cell |
| `rotationSteps` | 4 | 90 degree steps |
| `maxItems` | 200 | per plot |
| `remoteFolder` | `"UrkPlacement"` | ReplicatedStorage folder |
| `requestCapacity` / `requestRefillPerSecond` | 10 / 4 | per-player rate limit |
| `ghostTransparency` | 0.5 | preview |

## Example

```lua
-- Server
local placement = PlacementServer.new({
	catalog = Catalog, -- shared module with item sizes
	templates = ReplicatedStorage.Furniture,
	getPlot = function(player) return Plots.of(player) end,
	canPlace = function(player, itemId) return Inventory.has(player, itemId) end,
	store = { load = function(p) return data[p].plot end, save = function(p, d) data[p].plot = d end },
})
Plots.assigned:Connect(function(player) placement:reload(player) end)

-- Client
local builder = PlacementClient.new({
	catalog = Catalog,
	templates = ReplicatedStorage.Furniture,
	getPlot = function() return Plots.mine() end,
})
builder:start("Table")
-- R rotates, click confirms (wire these to your input or Input system)
builder:rotate()
builder:confirm()
```

## Events and remotes

- Server signals: `placed(player, placed)`, `removed(player, placed)`.
- Remotes in `ReplicatedStorage.UrkPlacement`: `Place (itemId, x, z, rotation)`, `Move (id, x, z, rotation)`, `Remove (id)` from the client; `Layout ({ Placed })` and `Rejected (reason)` from the server. All client arguments are type- and range-checked and rate limited.

## Persistence shape

`{ version = 1, items = { { itemId, x, z, rotation } } }` in placement order. On load, items that no longer fit the catalog or plot are dropped and counted. If the player's plot does not exist yet when they join, the saved data is kept as is until `reload(player)` (or their first request) finds the plot.

## Limitations

- Footprints are 2D boxes on one level; stacking and walls need a height dimension you add yourself.
- Non-90-degree rotation steps use the box around the rotated rectangle, which is conservative.
- The preview raycasts from the mouse or last touch position; on touch, call `confirm()` from a button.

## Needs a Studio playtest

Model spawning and pivots, plot CFrames, the ghost raycast and Highlight tint, and the remotes are unverified outside Studio. Lune tests cover `PlacementLogic`.
