---
name: roblox-teleport-matchmaking
description: Moving players between places and servers - TeleportService:TeleportAsync with TeleportOptions, reserved servers, untrusted teleport data, retries on TeleportInitFailed, MemoryStoreService (Queue, SortedMap, HashMap) matchmaking queues, MessagingService cross-server signals, parties, and lobby/match place architecture. Use when building a lobby, round-based matches, party teleports, server browsers or any cross-server feature.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [teleport, teleportservice, teleportasync, reserved server, matchmaking, memorystore, messagingservice, lobby, party, cross-server, queue]
  depends: [roblox-architecture, roblox-data-persistence, roblox-security-anti-exploit]
---

# Roblox teleport and matchmaking

## When to use

- A lobby place that sends groups into match places.
- Reserved (private, code-only) servers for matches, parties that move together.
- Cross-server queues, server lists, global announcements.

When not to use: saving player data between places is `roblox-data-persistence` (use DataStores, not teleport data, for anything that matters); in-server team assignment is `roblox-architecture`.

## Inputs

- Universe layout: lobby place id, match place id(s). All places must be in the same experience for `TeleportAsync` to a reserved server.
- Match size, region/skill rules, max wait time.
- Whether third-party teleports are needed (experience Security settings; off by default).

## Architecture

```
Lobby place (public servers)
  - players join queue -> MemoryStore Queue / SortedMap
  - one elected "matchmaker" loop per lobby server pulls batches
  - TeleportAsync(matchPlaceId, players, options{ShouldReserveServer=true})
Match place (reserved servers)
  - reads player:GetJoinData().TeleportData (untrusted hints only)
  - plays the round, saves results to DataStore
  - teleports everyone back to the lobby place
```

## Workflow

1. **Enable APIs**: in Studio, Game Settings > Security > enable Studio access to API services for MemoryStore testing. Teleports do not work in Studio playtests; plan to test in a published place.
2. **Queue**: on a validated `JoinQueue` remote, add the player (or party leader) to a MemoryStore queue with an expiration (for example 120 s) so stale entries disappear.
3. **Match loop**: each lobby server runs a loop that `ReadAsync`s a batch, checks those users are still in *this* server (others are handled by their own servers; see the reference module), teleports, then `RemoveAsync`s the read id. Unremoved items reappear after the invisibility timeout, which is your crash safety.
4. **Teleport with retries**: wrap `TeleportAsync` in `pcall`, retry with backoff, and also listen to `TeleportService.TeleportInitFailed`, which fires asynchronously for failures after the call returned.
5. **Teleport data is untrusted**: the client can read and influence it. Use it for hints (selected map, party id). Re-verify everything that matters on arrival against server-side state (DataStore or MemoryStore).
6. **Parties**: store `partyId -> {leader, members}` in a MemoryStore HashMap with expiry; teleport the whole member list in one `TeleportAsync` call so they land together.
7. **Cross-server signals**: `MessagingService:PublishAsync(topic, data)` and `SubscribeAsync(topic, callback)` for announcements and "party invite" pings. Delivery is best-effort; never use it as the source of truth.
8. **Return trip**: match servers teleport players back to the lobby place id (public server) when the round ends, and on `game:BindToClose` as a last resort.

### Teleport with retry

```lua
--!strict
-- ServerScriptService/Teleport/SafeTeleport.luau (ModuleScript)
local TeleportService = game:GetService("TeleportService")

local MAX_ATTEMPTS = 4
local BASE_DELAY = 2

local SafeTeleport = {}

function SafeTeleport.teleport(placeId: number, players: { Player }, options: TeleportOptions?): (boolean, string?)
	local lastError: string? = nil
	for attempt = 1, MAX_ATTEMPTS do
		-- Drop anyone who left while we were retrying.
		local present = {}
		for _, p in players do
			if p.Parent ~= nil then
				table.insert(present, p)
			end
		end
		if #present == 0 then
			return false, "no players left"
		end
		local ok, result = pcall(TeleportService.TeleportAsync, TeleportService, placeId, present, options)
		if ok then
			return true, nil
		end
		lastError = tostring(result)
		warn(("Teleport attempt %d failed: %s"):format(attempt, lastError))
		task.wait(BASE_DELAY * attempt)
	end
	return false, lastError
end

local RETRYABLE: { [Enum.TeleportResult]: boolean } = {
	[Enum.TeleportResult.Flooded] = true,
	[Enum.TeleportResult.Failure] = true,
}

TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string, placeId: number, options: TeleportOptions)
	warn(("TeleportInitFailed %s %s %s"):format(player.Name, result.Name, message))
	if RETRYABLE[result] and player.Parent then
		task.delay(BASE_DELAY, function()
			SafeTeleport.teleport(placeId, { player }, options)
		end)
	end
end)

function SafeTeleport.reservedOptions(data: { [string]: any }): TeleportOptions
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData(data) -- hints only; the client can see and alter this
	return options
end

return SafeTeleport
```

A full MemoryStore queue matchmaker with party support and a lock so only one server teleports a given batch: [references/matchmaking-queue.md](references/matchmaking-queue.md).

## Outputs

- `SafeTeleport` module, a matchmaker module in the lobby place, an arrival handler in the match place.
- Documented place ids in a shared config module.

## Validation

1. Unit-test the batching logic (pure function: list of tickets -> groups) with Lune; see `roblox-testing-debugging`.
2. In Studio, MemoryStore calls work with API access enabled (Studio uses a separate data scope from live; verify in creator docs). Mock `TeleportAsync` there, because it errors in Studio.
3. Publish to a test experience (not the live one), open 2+ clients from different accounts or a team test, queue, and confirm all land in the same reserved server (`game.PrivateServerId ~= ""` and `game.JobId` match in the match place).
4. Watch Creator Hub > MemoryStore observability dashboard for quota and throttling (verify location in creator docs).

## Pitfalls

- **Trusting teleport data** for rewards, rank or currency: an exploiter can forge it. Look it up server-side.
- **Teleporting one by one**: party members land in different servers. Pass the whole array once.
- **No expiry on queue items**: ghosts of disconnected players get matched. Always set expiration and re-check `Players:GetPlayerByUserId`.
- **Every lobby server reading the same items**: Queue `ReadAsync` hides items from other readers for the invisibility timeout; remove after success, or let them reappear on failure.
- **MemoryStore quota**: limits scale with concurrent users; batch reads (`ReadAsync(count)`) and avoid per-frame polling. Loop every 2-5 s.
- **MessagingService limits**: message size and per-server publish rate are capped (about 1 KB per message; verify current numbers in creator docs).
- **BindToClose**: servers get about 30 s to shut down; teleport players out early, not at the last second.
- **`TeleportService:Teleport` / `TeleportToPrivateServer`** are older APIs; prefer `TeleportAsync` with `TeleportOptions`.

## Limitations

- Teleports cannot be validated in Studio; this skill can only verify logic locally and requires a published test place for the real flow.
- Skill-based matchmaking quality depends on your rating model; this skill gives the plumbing, not the rating system.
- Roblox also offers a built-in matchmaking configuration for server selection; its scope and API are evolving, so verify in creator docs before choosing between it and a custom queue.
