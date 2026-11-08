# Cross-server matchmaking queue

Design, because `TeleportAsync` can only move players who are in the calling server:

1. Every lobby server writes a **ticket** per queued party into a MemoryStore SortedMap. The key sorts by enqueue time, so reading ascending is FIFO. Tickets expire (120 s) and are refreshed while the party waits.
2. One server at a time holds a **lock** (a SortedMap key written with `UpdateAsync` and a short expiration). The lock holder forms groups, calls `TeleportService:ReserveServer(matchPlaceId)` once per group, writes `ticketKey -> accessCode` into a HashMap, removes the tickets, and publishes a MessagingService ping.
3. Every lobby server checks the HashMap for its own tickets (on the ping, and on a slow poll as a fallback in case the message is lost) and teleports its own players with `TeleportOptions.ReservedServerAccessCode`.

Ranks, map votes and similar fields in a ticket are written by the server from validated state, never from the client.

```lua
--!strict
-- ServerScriptService/Matchmaking/Matchmaker.luau (ModuleScript, lobby place)
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local SafeTeleport = require(script.Parent.SafeTeleport)

local MATCH_PLACE_ID = 0 -- set to your match place id
local GROUP_SIZE = 4
local TICKET_TTL = 120
local ASSIGN_TTL = 120
local LOCK_TTL = 10
local LOOP_SECONDS = 3
local TOPIC = "MatchAssigned"

local tickets = MemoryStoreService:GetSortedMap("MM_Tickets")
local locks = MemoryStoreService:GetSortedMap("MM_Lock")
local assignments = MemoryStoreService:GetHashMap("MM_Assignments")

type Ticket = { jobId: string, userIds: { number }, createdAt: number }

local Matchmaker = {}
local myTickets: { [string]: { number } } = {} -- ticketKey -> userIds owned by this server

local function ticketKey(leaderId: number): string
	-- Zero-padded time first so lexical order is FIFO.
	return string.format("%012d_%d", os.time(), leaderId)
end

function Matchmaker.enqueue(party: { Player }): string?
	local ids = {}
	for _, p in party do
		table.insert(ids, p.UserId)
	end
	if #ids == 0 or #ids > GROUP_SIZE then
		return nil
	end
	local key = ticketKey(ids[1])
	local value: Ticket = { jobId = game.JobId, userIds = ids, createdAt = os.time() }
	local ok, err = pcall(tickets.SetAsync, tickets, key, value, TICKET_TTL)
	if not ok then
		warn("enqueue failed", err)
		return nil
	end
	myTickets[key] = ids
	return key
end

function Matchmaker.cancel(key: string)
	myTickets[key] = nil
	pcall(tickets.RemoveAsync, tickets, key)
end

local function tryLock(): boolean
	local ok, got = pcall(locks.UpdateAsync, locks, "lock", function(current: any)
		if current ~= nil and current ~= game.JobId then
			return nil -- someone else holds it; returning nil cancels the write
		end
		return game.JobId
	end, LOCK_TTL)
	return ok and got == game.JobId
end

-- Pure grouping step: fills groups in FIFO order without splitting parties.
function Matchmaker.formGroups(entries: { { key: string, value: Ticket } }): { { string } }
	local groups: { { string } } = {}
	local current: { string } = {}
	local count = 0
	for _, entry in entries do
		local size = #entry.value.userIds
		if count + size <= GROUP_SIZE then
			table.insert(current, entry.key)
			count += size
			if count == GROUP_SIZE then
				table.insert(groups, current)
				current, count = {}, 0
			end
		end
	end
	return groups -- a partial group waits for the next pass
end

local function runMatchmakerPass()
	if not tryLock() then
		return
	end
	local ok, entries = pcall(tickets.GetRangeAsync, tickets, Enum.SortDirection.Ascending, 100)
	if not ok then
		return
	end
	for _, group in Matchmaker.formGroups(entries) do
		local reserved, code = pcall(TeleportService.ReserveServer, TeleportService, MATCH_PLACE_ID)
		if reserved then
			for _, key in group do
				pcall(assignments.SetAsync, assignments, key, code, ASSIGN_TTL)
				pcall(tickets.RemoveAsync, tickets, key)
			end
			pcall(MessagingService.PublishAsync, MessagingService, TOPIC, group)
		end
	end
end

local function claimMyAssignments()
	for key, ids in myTickets do
		local ok, code = pcall(assignments.GetAsync, assignments, key)
		if ok and typeof(code) == "string" then
			myTickets[key] = nil
			pcall(assignments.RemoveAsync, assignments, key)
			local party = {}
			for _, id in ids do
				local p = Players:GetPlayerByUserId(id)
				if p then
					table.insert(party, p)
				end
			end
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			task.spawn(SafeTeleport.teleport, MATCH_PLACE_ID, party, options)
		end
	end
end

local function refreshMyTickets()
	for key in myTickets do
		-- UpdateAsync so a ticket the matchmaker already removed is not re-added.
		pcall(tickets.UpdateAsync, tickets, key, function(current: any)
			if current == nil then
				return nil
			end
			return current
		end, TICKET_TTL)
	end
end

function Matchmaker.start()
	pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function()
		claimMyAssignments()
	end)
	task.spawn(function()
		local passes = 0
		while true do
			runMatchmakerPass()
			claimMyAssignments() -- fallback if the message was lost
			passes += 1
			if passes % 10 == 0 then
				refreshMyTickets()
			end
			task.wait(LOOP_SECONDS)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for key, ids in myTickets do
			if table.find(ids, player.UserId) then
				Matchmaker.cancel(key)
			end
		end
	end)
end

return Matchmaker
```

Notes:

- `TeleportService:ReserveServer` returns an access code (and a private server id). It works only from a live server; mock it in Studio tests.
- `formGroups` is pure, so it can be unit-tested with Lune by passing plain tables.
- Refresh uses `UpdateAsync` and returns nil for missing keys, so a ticket the matchmaker already consumed is never resurrected.
- Verify current MemoryStore quotas and the `SortedMap:GetRangeAsync` item limit (currently up to 200 per call) in creator docs before scaling.
