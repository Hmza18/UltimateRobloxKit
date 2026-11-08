---
name: roblox-networking
description: Client/server communication in Roblox - RemoteEvent, RemoteFunction and UnreliableRemoteEvent, a typed Net wrapper, payload validation, per-player rate limiting, replication through attributes and value objects, buffer-packed payloads and optional Blink/Zap IDL code generators. Use when adding any remote, syncing state to clients, designing multiplayer features or reviewing remote security.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [remoteevent, remotefunction, unreliableremoteevent, fireserver, onserverevent, replication, rate limit, payload validation, blink, zap]
  depends: [luau-language, roblox-architecture, roblox-security-anti-exploit]
---

# Roblox networking

## When to use

- Adding a client action the server must react to (buy, attack, interact, chat command).
- Pushing state to clients (round timer, health of a boss, inventory snapshot).
- Sending high-frequency, loss-tolerant data (aim direction, cosmetic effects).
- Reviewing remotes for exploits: missing validation, client-trusted values, spam.

When not to use: cross-server messaging (MessagingService/MemoryStore, see `roblox-teleport-matchmaking`), anti-cheat design beyond remote validation (see `roblox-security-anti-exploit`).

## Inputs

- The list of messages: direction (client to server, server to client), frequency, payload shape, whether a reply is needed, and whether loss is acceptable.
- The project's architecture (services/controllers). See `roblox-architecture`.

## Workflow

1. **Pick the transport** for each message:

   | Need | Use |
   | --- | --- |
   | Server state every client can see, changes rarely | Attributes or ValueObjects on a replicated Instance |
   | One-off event, must arrive in order | `RemoteEvent` |
   | Frequent, latest-value-wins, may drop | `UnreliableRemoteEvent` (small payloads; check creator docs for the current size cap) |
   | Client asks server and needs an answer | `RemoteFunction` with `InvokeServer` |
   | Server asks client for something | Do not. Use a RemoteEvent pair with a timeout instead; `InvokeClient` can hang forever or error if the client leaves |

2. **Create remotes on the server only**, in `ReplicatedStorage.Remotes`. Clients `WaitForChild`. Copy [templates/Net.luau](templates/Net.luau) to `src/shared/Net.luau`.
3. **Define each remote with a rate limit and a validator.** The server treats every argument as hostile: wrong type, NaN, huge strings, other players' Instances, negative quantities.
4. **Send intent, not results.** The client says "I want to buy item `sword_01`", never "set my coins to 50" or "I dealt 90 damage".
5. **Recompute on the server** using server data: prices from server config, distance from the server's character position, cooldowns from server timestamps.
6. **Replicate results** with attributes (`player:SetAttribute("Coins", n)`) or a targeted `FireClient`.

### Example: a validated purchase request

```luau
--!strict
-- Server: src/server/Services/ShopService.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Items = require(ReplicatedStorage.Shared.Config.Items) -- { [string]: { price: number } }

local V = Net.V
local buyRequest = Net.request("BuyItem")

local ShopService = {}

function ShopService.Start()
	buyRequest.handle(
		{ perSecond = 2, burst = 4 },
		function(itemId: any, quantity: any): boolean
			return type(itemId) == "string" and Items[itemId] ~= nil and V.integer(quantity, 1, 99)
		end,
		function(player: Player, itemId: string, quantity: number)
			local price = Items[itemId].price * quantity        -- server price, never the client's
			local coins = player:GetAttribute("Coins")
			if type(coins) ~= "number" or coins < price then
				return false, "not enough coins"
			end
			player:SetAttribute("Coins", coins - price)          -- real code: go through the data service
			return true, itemId
		end
	)
end

return ShopService
```

```luau
--!strict
-- Client: src/client/Controllers/ShopController.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local buyRequest = Net.request("BuyItem")

local function onBuyClicked(itemId: string)
	local ok, result = buyRequest.invoke(itemId, 1)
	if not ok then
		warn("Purchase failed:", result)
	end
end

return { onBuyClicked = onBuyClicked }
```

### Replication without remotes

- **Attributes**: `instance:SetAttribute("RoundTime", 90)` on the server; clients use `GetAttributeChangedSignal("RoundTime")`. Supported types include numbers, strings, booleans, Vector3, Color3, CFrame and others; tables are not supported.
- **ValueObjects** (`IntValue`, `ObjectValue`) when you need an Instance reference that replicates.
- **Per-player data**: attributes on the `Player` replicate to every client. For private data, `FireClient` only to that player or parent a folder under the player's `PlayerGui` (replicated only to them).
- **StreamingEnabled**: parts far from a player may not exist on their client. Never assume a server-side Instance is present on the client; check for nil and listen for `ChildAdded`.

### Compressing hot payloads with buffer

For many small updates per second, pack values into a `buffer` (supported by remotes) instead of tables. A Vector3 as three `f32` is 12 bytes; a quantized angle can be one `u16`. See the codec pattern in `luau-language` (references/idioms.md in that skill). On the server, check `buffer.len` before reading.

### Optional: IDL code generators

Blink and Zap generate typed, buffer-serialized networking code from a schema file, with validation of types built in. They suit projects with many high-frequency messages. They are third-party command-line tools (install via Rokit) and still require game-logic validation (ranges, ownership, cooldowns) in your handlers. Check each tool's docs for its current schema syntax.

## Outputs

- `src/shared/Net.luau` plus one remote definition per message, each with a rate limit and validator.
- A message table in the project docs: name, direction, payload, limit, reliable or not.

## Validation

1. Play with 2+ players in Studio (Test > Clients and Servers). Every remote action works from each client.
2. In the client command bar (client context), fire remotes with bad payloads: `nil`, `0/0`, `-1`, a 100 KB string, another player's character. The server neither errors nor changes state.
3. Spam a remote in a loop from the client; the server ignores calls past the limit and the server's heartbeat stays steady (Developer Console > Network, Server Stats).
4. `grep -rn "InvokeClient" src` returns nothing.

## Pitfalls

- **Trusting client values** (damage, price, position for a teleport). Recompute on the server.
- **NaN fails every comparison**, so a guard written as `if x < 0 then reject end` lets NaN through and corrupts saved data. Test `x == x`, and prefer positive range checks.
- **Instance arguments** can reference any replicated Instance. Check `IsDescendantOf` and ownership.
- **Firing every frame on a reliable RemoteEvent** queues data and adds latency. Throttle, or use UnreliableRemoteEvent.
- **Tables lose metatables and mixed keys** across the network; send plain arrays or string-keyed dictionaries.
- **Remotes created on the client** do not replicate to the server.
- **Yielding in `OnServerInvoke`** for long work holds the client's thread; keep it short or reply via an event.

## Limitations

- Size limits and throughput for UnreliableRemoteEvent and remote payloads change; verify current numbers in creator docs.
- The Net wrapper does not encrypt or hide traffic; exploiters can see and fire every remote.
- Rate limits use per-server memory only; they do not follow a player across servers.
