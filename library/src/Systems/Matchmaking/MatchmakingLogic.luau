--!strict
-- Matchmaking queue rules. Pure Luau: `now` and a random source are passed in.
-- Tickets are parties (one or more players) with a skill rating and a bucket (mode, region, ...).
-- The skill window widens the longer a ticket waits, parties are never split across teams,
-- and a ticket only matches others in its bucket.

local MatchmakingConfig = require("./MatchmakingConfig")

export type TicketInput = { id: string, players: { string }, skill: number, bucket: string? }
export type Ticket = { id: string, players: { string }, skill: number, bucket: string, enqueuedAt: number }

export type Config = {
	teamCount: number,
	teamSize: number,
	baseSkillWindow: number,
	widenPerSecond: number,
	maxSkillWindow: number,
	fillAfter: number,
	minPlayers: number,
	maxWait: number,
}

export type Queue = { config: Config, tickets: { [string]: Ticket }, byPlayer: { [string]: string } }

export type Match = {
	bucket: string,
	teams: { { string } }, -- player ids per team
	ticketIds: { string },
	players: { string },
	averageSkill: number,
	full: boolean,
	createdAt: number,
}

type Team = { players: { string }, count: number }

local Matchmaking = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isCount(value: any): boolean
	return isFinite(value) and value >= 1 and value % 1 == 0
end

-- Fills missing or invalid keys from MatchmakingConfig.
function Matchmaking.resolveConfig(overrides: { [string]: any }?): Config
	local source: { [string]: any } = overrides or {}
	local function pick(key: string, positive: boolean): number
		local value = source[key]
		if isFinite(value) and value >= 0 and (not positive or value > 0) then
			return value
		end
		return (MatchmakingConfig :: any)[key]
	end
	local teamCount = source.teamCount
	local teamSize = source.teamSize
	return {
		teamCount = if isCount(teamCount) then teamCount else MatchmakingConfig.teamCount,
		teamSize = if isCount(teamSize) then teamSize else MatchmakingConfig.teamSize,
		baseSkillWindow = pick("baseSkillWindow", false),
		widenPerSecond = pick("widenPerSecond", false),
		maxSkillWindow = pick("maxSkillWindow", false),
		fillAfter = pick("fillAfter", false),
		minPlayers = pick("minPlayers", false),
		maxWait = pick("maxWait", true),
	}
end

function Matchmaking.newQueue(config: { [string]: any }?): Queue
	return { config = Matchmaking.resolveConfig(config), tickets = {}, byPlayer = {} }
end

function Matchmaking.matchSize(config: Config): number
	return config.teamCount * config.teamSize
end

-- Skill difference a ticket accepts after waiting `waited` seconds.
function Matchmaking.skillWindow(config: Config, waited: number): number
	local window = config.baseSkillWindow + math.max(0, waited) * config.widenPerSecond
	return math.min(window, config.maxSkillWindow)
end

-- Checks an untrusted ticket against the queue. Returns false and a reason when it cannot join.
function Matchmaking.validateTicket(queue: Queue, ticket: any): (boolean, string?)
	if type(ticket) ~= "table" or type(ticket.id) ~= "string" or ticket.id == "" then
		return false, "ticket needs an id"
	end
	if queue.tickets[ticket.id] then
		return false, "duplicate ticket"
	end
	if not isFinite(ticket.skill) then
		return false, "skill must be a finite number"
	end
	if ticket.bucket ~= nil and type(ticket.bucket) ~= "string" then
		return false, "bucket must be a string"
	end
	local players = ticket.players
	if type(players) ~= "table" or #players == 0 then
		return false, "ticket needs players"
	end
	if #players > queue.config.teamSize then
		return false, "party is larger than a team"
	end
	local seen: { [string]: boolean } = {}
	for _, playerId in players do
		if type(playerId) ~= "string" or playerId == "" then
			return false, "player ids must be strings"
		end
		if seen[playerId] then
			return false, "player listed twice"
		end
		if queue.byPlayer[playerId] then
			return false, "player already queued"
		end
		seen[playerId] = true
	end
	return true, nil
end

function Matchmaking.enqueue(queue: Queue, ticket: TicketInput, now: number): (boolean, string?)
	local ok, reason = Matchmaking.validateTicket(queue, ticket)
	if not ok then
		return false, reason
	end
	local stored: Ticket = {
		id = ticket.id,
		players = table.clone(ticket.players),
		skill = ticket.skill,
		bucket = ticket.bucket or "default",
		enqueuedAt = now,
	}
	queue.tickets[stored.id] = stored
	for _, playerId in stored.players do
		queue.byPlayer[playerId] = stored.id
	end
	return true, nil
end

-- Restores a ticket that already has an enqueuedAt, for example one read back from a MemoryStore.
function Matchmaking.restore(queue: Queue, ticket: Ticket): (boolean, string?)
	if not isFinite(ticket.enqueuedAt) then
		return false, "enqueuedAt must be a number"
	end
	local ok, reason = Matchmaking.enqueue(queue, ticket, ticket.enqueuedAt)
	return ok, reason
end

function Matchmaking.dequeue(queue: Queue, ticketId: string): boolean
	local ticket = queue.tickets[ticketId]
	if ticket == nil then
		return false
	end
	queue.tickets[ticketId] = nil
	for _, playerId in ticket.players do
		queue.byPlayer[playerId] = nil
	end
	return true
end

-- Removes the whole party of `playerId`, so a party is never matched without one of its members.
function Matchmaking.dequeuePlayer(queue: Queue, playerId: string): string?
	local ticketId = queue.byPlayer[playerId]
	if ticketId then
		Matchmaking.dequeue(queue, ticketId)
	end
	return ticketId
end

function Matchmaking.size(queue: Queue): number
	local count = 0
	for _ in queue.tickets do
		count += 1
	end
	return count
end

-- Tickets oldest first; ties broken by id so results never depend on table order.
function Matchmaking.ordered(queue: Queue): { Ticket }
	local list: { Ticket } = {}
	for _, ticket in queue.tickets do
		table.insert(list, ticket)
	end
	table.sort(list, function(a: Ticket, b: Ticket): boolean
		if a.enqueuedAt ~= b.enqueuedAt then
			return a.enqueuedAt < b.enqueuedAt
		end
		return a.id < b.id
	end)
	return list
end

-- Two tickets can share a match when they are in the same bucket and either one's window covers the gap.
function Matchmaking.compatible(config: Config, a: Ticket, b: Ticket, now: number): boolean
	if a.bucket ~= b.bucket then
		return false
	end
	local windowA = Matchmaking.skillWindow(config, now - a.enqueuedAt)
	local windowB = Matchmaking.skillWindow(config, now - b.enqueuedAt)
	return math.abs(a.skill - b.skill) <= math.max(windowA, windowB)
end

-- Places parties into teams without splitting them. The anchor goes first, then larger parties,
-- then older tickets. Returns the teams, the tickets used and the player total.
local function fillTeams(config: Config, anchor: Ticket, others: { Ticket }): ({ Team }, { Ticket }, number)
	local teams: { Team } = {}
	for _ = 1, config.teamCount do
		table.insert(teams, { players = {}, count = 0 })
	end
	local sorted = table.clone(others)
	table.sort(sorted, function(a: Ticket, b: Ticket): boolean
		if #a.players ~= #b.players then
			return #a.players > #b.players
		end
		if a.enqueuedAt ~= b.enqueuedAt then
			return a.enqueuedAt < b.enqueuedAt
		end
		return a.id < b.id
	end)
	table.insert(sorted, 1, anchor)
	local used: { Ticket } = {}
	local total = 0
	local capacity = Matchmaking.matchSize(config)
	for _, ticket in sorted do
		if total >= capacity then
			break
		end
		local size = #ticket.players
		local best: Team? = nil
		for _, team in teams do
			if team.count + size <= config.teamSize and (best == nil or team.count < best.count) then
				best = team
			end
		end
		if best then
			for _, playerId in ticket.players do
				table.insert(best.players, playerId)
			end
			best.count += size
			total += size
			table.insert(used, ticket)
		end
	end
	return teams, used, total
end

-- Forms as many matches as possible and removes their tickets from the queue.
-- A match is full when every team is full. A partly filled match is allowed once the oldest ticket
-- has waited `fillAfter` seconds and at least `minPlayers` (> 0) players are available.
function Matchmaking.assemble(queue: Queue, now: number): { Match }
	local config = queue.config
	local matches: { Match } = {}
	local taken: { [string]: boolean } = {}
	local capacity = Matchmaking.matchSize(config)
	for _, anchor in Matchmaking.ordered(queue) do
		if taken[anchor.id] then
			continue
		end
		local others: { Ticket } = {}
		for _, ticket in Matchmaking.ordered(queue) do
			local free = ticket.id ~= anchor.id and not taken[ticket.id]
			if free and Matchmaking.compatible(config, anchor, ticket, now) then
				table.insert(others, ticket)
			end
		end
		local teams, used, total = fillTeams(config, anchor, others)
		local full = total == capacity
		local waited = now - anchor.enqueuedAt
		local partialOk = config.minPlayers > 0 and total >= config.minPlayers and waited >= config.fillAfter
		if full or partialOk then
			local teamPlayers: { { string } } = {}
			for _, team in teams do
				table.insert(teamPlayers, team.players)
			end
			local ticketIds: { string } = {}
			local players: { string } = {}
			local skillSum = 0
			for _, ticket in used do
				taken[ticket.id] = true
				table.insert(ticketIds, ticket.id)
				skillSum += ticket.skill * #ticket.players
				for _, playerId in ticket.players do
					table.insert(players, playerId)
				end
			end
			table.insert(matches, {
				bucket = anchor.bucket,
				teams = teamPlayers,
				ticketIds = ticketIds,
				players = players,
				averageSkill = skillSum / total,
				full = full,
				createdAt = now,
			})
		end
	end
	for ticketId in taken do
		Matchmaking.dequeue(queue, ticketId)
	end
	return matches
end

-- Drops tickets that waited longer than config.maxWait and returns their ids.
function Matchmaking.expire(queue: Queue, now: number): { string }
	local removed: { string } = {}
	for _, ticket in Matchmaking.ordered(queue) do
		if now - ticket.enqueuedAt > queue.config.maxWait then
			Matchmaking.dequeue(queue, ticket.id)
			table.insert(removed, ticket.id)
		end
	end
	return removed
end

-- Plain table for storage (MemoryStore values must be JSON-compatible).
function Matchmaking.encodeTicket(ticket: Ticket): { [string]: any }
	return {
		id = ticket.id,
		players = table.clone(ticket.players),
		skill = ticket.skill,
		bucket = ticket.bucket,
		enqueuedAt = ticket.enqueuedAt,
	}
end

-- Reads a stored ticket back, or nil when it is malformed.
function Matchmaking.decodeTicket(raw: any): Ticket?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or type(raw.bucket) ~= "string" then
		return nil
	end
	if not isFinite(raw.skill) or not isFinite(raw.enqueuedAt) or type(raw.players) ~= "table" then
		return nil
	end
	local players: { string } = {}
	for _, playerId in raw.players do
		if type(playerId) ~= "string" then
			return nil
		end
		table.insert(players, playerId)
	end
	if #players == 0 then
		return nil
	end
	return { id = raw.id, players = players, skill = raw.skill, bucket = raw.bucket, enqueuedAt = raw.enqueuedAt }
end

-- Exponential backoff with jitter for retries. `random` returns a number in [0, 1).
-- Attempt 1 waits about `base` seconds, attempt 2 about twice that, and so on, never more than `maxDelay`.
function Matchmaking.backoff(attempt: number, base: number, maxDelay: number, random: () -> number): number
	local raw = math.min(maxDelay, base * 2 ^ math.max(0, attempt - 1))
	return raw * (0.5 + 0.5 * math.clamp(random(), 0, 1))
end

return Matchmaking
