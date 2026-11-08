---
name: roblox-architecture
description: Code architecture for Roblox experiences - framework-free services and controllers, Rojo src/server, src/client and src/shared layout, one bootstrap script per side with ordered Init/Start, dependency injection, a typed Signal, a cleanup maid (Trove/Janitor style) and deciding where state lives. Use when starting a project, adding a new system, untangling require cycles or reviewing how modules are wired.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [architecture, service, controller, bootstrap, rojo layout, signal, maid, trove, janitor, knit, require cycle, dependency injection]
  depends: [luau-language]
---

# Roblox architecture

## When to use

- New project, or a project with dozens of loose `Script`s that need structure.
- Adding a system (combat, shops, quests) and deciding whether it is a service, a controller or a shared module.
- Fixing require cycles, double initialization, or memory leaks from connections that are never disconnected.

When not to use: remote design (use `roblox-networking`), saving data (use `roblox-data-persistence`), installing Rojo/Wally (use `roblox-toolchain-doctor`).

## Inputs

- A Rojo project (`default.project.json`) or willingness to create one from [templates/default.project.json](templates/default.project.json).
- The list of systems the experience needs, split into server-authoritative logic and client presentation.

## Workflow

1. **Lay out folders.** Copy [templates/default.project.json](templates/default.project.json). It maps:

   | Folder | Roblox location | Contents |
   | --- | --- | --- |
   | `src/server` | `ServerScriptService.Server` | `Main.server.luau`, `Services/` |
   | `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | `Main.client.luau`, `Controllers/` |
   | `src/shared` | `ReplicatedStorage.Shared` | config, types, pure logic, `Signal`, `Trove` |
   | `Packages` | `ReplicatedStorage.Packages` | Wally packages |

   Server-only secrets and modules never go in `ReplicatedStorage`; clients can read everything there.

2. **One entry point per side.** Exactly one `Script` (server) and one `LocalScript` (client) require every service or controller, call `Init` on all of them, then `Start` on all of them. See [templates/Main.server.luau](templates/Main.server.luau).
   - `Init(deps)`: sync setup only. Store references, create remotes, register tables. Must not yield and must not call other services' methods.
   - `Start()`: may yield and may call other services. Runs after every `Init` finished, so cross-service calls are safe.
3. **Write a service** as a table with typed methods. Pass dependencies in through `Init` instead of requiring siblings directly; this kills require cycles and makes services testable with fakes.
4. **Use Signals for events between modules** instead of BindableEvents. Copy [templates/Signal.luau](templates/Signal.luau) into `src/shared`.
5. **Clean up everything you connect.** Each player session, round or spawned object owns a Trove; destroy it when the thing ends. Copy [templates/Trove.luau](templates/Trove.luau).
6. **Decide where state lives** (table below) before writing code that reads it.

### Example service

```luau
--!strict
-- src/server/Services/PointsService.luau
local Players = game:GetService("Players")
local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local Trove = require(game:GetService("ReplicatedStorage").Shared.Trove)

type Deps = {
	DataService: { getProfileData: (Player) -> { points: number }? },
}

local PointsService = {}
PointsService.Changed = Signal.new() :: Signal.Signal<Player, number>

local deps: Deps
local sessions: { [Player]: Trove.Trove } = {}

function PointsService.Init(injected: Deps)
	deps = injected
end

function PointsService.Start()
	local function onPlayer(player: Player)
		local trove = Trove.new()
		sessions[player] = trove
		trove:add(player:GetAttributeChangedSignal("Team"):Connect(function()
			-- per-player connections die with the trove
		end))
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local trove = sessions[player]
		if trove then
			trove:destroy()
			sessions[player] = nil
		end
	end)
end

function PointsService.add(player: Player, amount: number)
	assert(amount > 0, "amount must be positive")
	local data = deps.DataService.getProfileData(player)
	if not data then
		return
	end
	data.points += amount
	player:SetAttribute("Points", data.points)   -- replicate a read-only copy
	PointsService.Changed:fire(player, data.points)
end

return PointsService
```

### Where state lives

| State | Owner | Replication |
| --- | --- | --- |
| Saved player data (coins, inventory) | Server data service (profile table) | Attributes or a remote snapshot to that player |
| Round / match state | Server round service | Attributes on a `ReplicatedStorage` folder |
| World objects (doors, NPCs) | Server, as Instances in `Workspace` | Automatic Instance replication |
| UI state (open menu, selected tab) | Client controller | None |
| Settings (volume, camera sens) | Client, saved through a validated remote | None |
| Config (prices, item stats) | Shared frozen module | Read by both; server is still the authority |

The client copy of any value is a display cache. The server never reads game-relevant values from the client.

### Optional: Knit and other frameworks

Knit (Sleitnick) provides the same service/controller pattern with built-in remotes, but its author has stopped active development (check the repository status before adopting it). New projects can stay framework-free with this skill's templates; existing Knit projects can keep it. Avoid mixing two frameworks in one place.

## Outputs

- `default.project.json`, `src/server/Main.server.luau`, `src/client/Main.client.luau`, `src/shared/Signal.luau`, `src/shared/Trove.luau`, and one module per service or controller.

## Validation

1. `rojo build default.project.json -o build.rbxl` succeeds.
2. Play in Studio: Output shows every service's Init then Start in order with no "Requested module experienced an error while loading" or "Infinite yield possible".
3. Search for stray entry points: `find src -name "*.server.luau" -o -name "*.client.luau"` lists only the two `Main` files (plus any intentional extras).
4. Join and leave in a test server several times; the Developer Console memory (LuaHeap) does not climb each cycle.

## Pitfalls

- **Require cycles** ("Recursive require detected"): two services require each other. Inject one into the other through `Init`, or move shared code to `src/shared`.
- **Yielding in Init** stalls every later service. Move `WaitForChild`, DataStore and HTTP calls to `Start`.
- **Missed PlayerAdded**: players who joined before `Start` ran never get set up. Always loop `Players:GetPlayers()` after connecting.
- **Leaked connections** on characters and players. Give each a Trove and destroy it on `PlayerRemoving` or `Humanoid.Died`.
- **Server modules in ReplicatedStorage** expose logic to exploiters. Keep them under `ServerScriptService` or `ServerStorage`.
- **Client-side `require` of a server-only module** errors silently in the client. Keep the shared boundary explicit.

## Limitations

- This skill gives a pattern, not a framework; teams must enforce Init/Start rules by review.
- It cannot detect architecture problems automatically; validation relies on Studio playtests and the build.
