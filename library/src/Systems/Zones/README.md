# Zones

Region detection: shops, safe zones, music areas and capture points. `ZonesLogic` is pure maths. It handles oriented boxes (center, half-size and yaw, with no CFrame), spheres and polygon prisms, enter and leave diffing for each key on each tick, hysteresis, a leave delay and priority between overlapping zones. `Zones` builds zones from parts tagged `UrkZone` and polls character positions on Heartbeat, on the server (all players) or on a client (the local player).

## ZonesLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `vec3(x, y, z)` | `Vec3` | plain `{ x, y, z }` |
| `box(center, halfSize, yaw?)` | `Box` | yaw in radians about +Y, the same as `CFrame.Angles(0, yaw, 0)` |
| `sphere(center, radius)` | `Sphere` | |
| `prism(points, minY, maxY)` | `Prism` | points `{ { x, z } }`, at least 3 and with non-zero area; concave outlines work; the points are copied |
| `contains(shape, point, margin?)` | `boolean` | a positive margin grows the shape, a negative one shrinks it |
| `toLocal(box, point)` | `Vec3` | world point to box space |
| `bounds(shape, margin?)` | `(min, max)` | world-space bounding box |
| `new(config?)` | `State` | |
| `addZone(state, id, shape, options?)` | `Zone` | options `{ priority = 0, hysteresis = state default, data? }`; errors on a duplicate id |
| `removeZone(state, id)` | `{ Change }` | leave changes for members |
| `update(state, positions, now)` | `{ Change }` | `positions[key] = Vec3`; keys that are missing or invalid count as in no zone |
| `updateRaw(state, raw, now)` | `{ Change }` | `raw[key] = { [zoneId] = true }`, for other detectors |
| `zonesAt(state, point, key?)` | `{ [id]: true }` | uses the hysteresis margin for zones `key` is already in |
| `removeKey(state, key)` | `{ Change }` | for a player who leaves |
| `zonesOf(state, key)` / `primaryOf(state, key)` / `isIn(state, key, id)` / `keysIn(state, id)` / `topZoneAt(state, point)` | | queries |

`Change = { kind = "enter" | "leave" | "primary", key, zoneId?, previous? }`. For each key the changes come in this order: leaves (sorted by id), enters (sorted by id), then one `primary` change when the top zone changed. A `primary` change with `zoneId = nil` means the key is in no zone.

## Rules

- **Hysteresis**: a key enters when it is inside the shape and leaves only when it is more than `hysteresis` studs outside it. This stops flicker on the border.
- **leaveDelay**: a key also stays a member until `leaveDelay` seconds after it was last inside (the time comes from the injected `now`).
- **Priority**: the primary zone is the highest priority, with ties broken by id in alphabetical order. In the default mode a key is in every overlapping zone. With `exclusive = true` it is in the top zone only, and moving out of an inner zone re-enters the outer one.

## Config

`ZonesLogic.Config`: `exclusive = false`, `hysteresis = 0` (the default for new zones), `leaveDelay = 0`.

`Zones.new(config?)`:

| Key | Default | Meaning |
| --- | --- | --- |
| `tag` | `"UrkZone"` | CollectionService tag on zone parts |
| `mode` | `"server"` on the server, `"client"` on a client | which players are tracked |
| `rate` | 10 | updates per second |
| `detection` | `"root"` | `"root"` checks the root part position. `"bounds"` counts a player in a box or sphere zone when any character part overlaps it, using `workspace:GetPartBoundsInBox` and `GetPartBoundsInRadius`; prism zones still use the root position |
| `hysteresis` | 1 | studs, used when a part has no `Hysteresis` attribute |
| `logic` | `{}` | `exclusive`, `leaveDelay` |
| `rootName` | `"HumanoidRootPart"` | |
| `workspaceOnly` | true | ignore tagged parts outside Workspace |

Part attributes: `Shape` (`"Box"`, the default, or `"Sphere"` or `"Prism"`), `ZoneId` (default the part name, with `#2` and so on added for duplicates), `Priority` and `Hysteresis`. A sphere uses half the smallest size axis. A prism takes its outline from the part's `Attachment` children, sorted by name, and its height from the part's Y size. A box uses the part's yaw only, and warns about any pitch or roll.

## Adapter API and events

`addZone(id, shape, options?)` (a zone from code), `removeZone(id)`, `refresh()` (re-reads part shapes after you move or resize them), `update()` (polls now), `getZones(player)`, `getPrimary(player)`, `isIn(player, id)`, `getPlayers(id)` and `destroy()`. `zones.state` is the `ZonesLogic` state.

Events: `PlayerEntered(player, zoneId, part?)`, `PlayerLeft(player, zoneId, part?)` and `PrimaryChanged(player, zoneId?, previousZoneId?)`.

## Example

```luau
local Zones = require(Kit.Systems.Zones.Zones)
local zones = Zones.new({ rate = 8, logic = { leaveDelay = 0.5 } })
zones.PlayerEntered:Connect(function(player, zoneId)
	if zoneId == "SafeZone" then
		player:SetAttribute("Safe", true)
	end
end)
zones.PlayerLeft:Connect(function(player, zoneId)
	if zoneId == "SafeZone" then
		player:SetAttribute("Safe", nil)
	end
end)
-- A zone from code: a 20 x 10 x 6 stud box turned 30 degrees.
local ZonesLogic = require(Kit.Systems.Zones.ZonesLogic)
zones:addZone("Stage", ZonesLogic.box(ZonesLogic.vec3(0, 5, 40), ZonesLogic.vec3(10, 5, 3), math.rad(30)))
```

Make zone parts `Anchored`, `CanCollide = false`, `CanQuery = false` (they are never queried themselves), `CanTouch = false` and `Transparency = 1`.

## Limitations

- Boxes support yaw only. Tilted boxes are treated as upright.
- Moving or resizing zone parts is not tracked automatically, so call `refresh()`. A refresh fires leave and then enter again for members.
- A prism outline that crosses itself uses the even-odd rule.
- `"bounds"` detection uses part bounding boxes, so it is coarser than the shape for rotated character parts, and it costs two spatial queries per zone per tick.
- Client mode is for presentation (music, UI). Anything that gives rewards or protection must run on the server.
- Positions are polled, so a fast player can pass through a thin zone between ticks. Raise `rate` or make the zone thicker.

## Needs a Studio playtest

Lune covers `ZonesLogic` in `tests/sys_zones.spec.luau`. Not verified: reading zones from tagged parts (attributes, Attachments, `ToEulerAnglesYXZ` yaw), the Heartbeat polling rate, `"bounds"` detection with `OverlapParams`, client mode, and the events when characters respawn or players leave.
