--!strict
-- Team assignment, balancing, friendly-fire rules and team scores. Pure Luau.
-- Players are identified by string ids (use tostring(player.UserId)). Skill is optional; when used,
-- ties in team size go to the team with the lower total skill and shuffles use a snake draft.

export type TeamDef = { name: string, maxSize: number? }

export type State = {
	order: { string },
	maxSize: { [string]: number },
	members: { [string]: { [string]: number } }, -- team -> playerId -> skill
	teamOf: { [string]: string },
	scores: { [string]: number },
}

export type DamageRules = { friendlyFire: boolean?, selfDamage: boolean? }
export type Move = { playerId: string, from: string, to: string }
export type PlayerSkill = { id: string, skill: number? }
export type Standing = { team: string, score: number }

local Teams = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- `teams` is a list of names or { name, maxSize } tables. Names must be unique.
function Teams.new(teams: { any }): State
	assert(type(teams) == "table" and #teams > 0, "Teams.new needs at least one team")
	local state: State = { order = {}, maxSize = {}, members = {}, teamOf = {}, scores = {} }
	for _, entry in teams do
		local name = if type(entry) == "table" then entry.name else entry
		assert(type(name) == "string" and name ~= "", "team names must be strings")
		assert(state.members[name] == nil, "duplicate team " .. name)
		table.insert(state.order, name)
		state.members[name] = {}
		state.scores[name] = 0
		local limit = if type(entry) == "table" then entry.maxSize else nil
		state.maxSize[name] = if isFinite(limit) and limit >= 1 then math.floor(limit) else math.huge
	end
	return state
end

function Teams.size(state: State, team: string): number
	local count = 0
	for _ in pairs(state.members[team] or {}) do
		count += 1
	end
	return count
end

function Teams.totalSkill(state: State, team: string): number
	local total = 0
	for _, skill in pairs(state.members[team] or {}) do
		total += skill
	end
	return total
end

function Teams.teamOf(state: State, playerId: string): string?
	return state.teamOf[playerId]
end

-- Sorted member ids of a team.
function Teams.membersOf(state: State, team: string): { string }
	local ids: { string } = {}
	for playerId in pairs(state.members[team] or {}) do
		table.insert(ids, playerId)
	end
	table.sort(ids)
	return ids
end

-- The team a new player should join: the smallest team with room. Ties go to the lower total skill
-- when `useSkill` is set, otherwise to the earlier team in the list. Nil when every team is full.
function Teams.pickTeam(state: State, useSkill: boolean?): string?
	local best: string? = nil
	local bestSize = math.huge
	local bestSkill = math.huge
	for _, team in state.order do
		local size = Teams.size(state, team)
		if size < state.maxSize[team] then
			local skill = if useSkill then Teams.totalSkill(state, team) else 0
			if size < bestSize or (size == bestSize and skill < bestSkill) then
				best = team
				bestSize = size
				bestSkill = skill
			end
		end
	end
	return best
end

local function place(state: State, playerId: string, team: string, skill: number?)
	local previous = state.teamOf[playerId]
	if previous then
		state.members[previous][playerId] = nil
	end
	state.members[team][playerId] = if isFinite(skill) then skill :: number else 0
	state.teamOf[playerId] = team
end

-- Puts a player on the best team (see pickTeam). Returns the existing team if already assigned.
function Teams.assign(state: State, playerId: string, skill: number?, useSkill: boolean?): string?
	local existing = state.teamOf[playerId]
	if existing then
		return existing
	end
	local team = Teams.pickTeam(state, useSkill)
	if team then
		place(state, playerId, team, skill)
	end
	return team
end

-- A player asks for a specific team. Refused when the team is full or the move would make it more than
-- `maxImbalance` players larger than the smallest other team.
function Teams.join(
	state: State,
	playerId: string,
	team: string,
	skill: number?,
	maxImbalance: number?
): (boolean, string?)
	if state.members[team] == nil then
		return false, "unknown team"
	end
	local current = state.teamOf[playerId]
	if current == team then
		return false, "already on that team"
	end
	local size = Teams.size(state, team)
	if size >= state.maxSize[team] then
		return false, "team is full"
	end
	local limit = maxImbalance or 1
	for _, other in state.order do
		if other ~= team then
			local otherSize = Teams.size(state, other) - (if other == current then 1 else 0)
			if size + 1 - otherSize > limit then
				return false, "teams would be unbalanced"
			end
		end
	end
	local keptSkill = if current then state.members[current][playerId] else skill
	place(state, playerId, team, keptSkill)
	return true, nil
end

function Teams.remove(state: State, playerId: string): string?
	local team = state.teamOf[playerId]
	if team then
		state.members[team][playerId] = nil
		state.teamOf[playerId] = nil
	end
	return team
end

-- Splits players across teams from scratch. With `useSkill`, players are sorted by skill and dealt
-- in snake order (1, 2, 2, 1, 1, 2, ...); without it they are dealt round-robin in id order.
-- Returns playerId -> team. Team size limits are not applied here.
function Teams.balance(players: { PlayerSkill }, teamNames: { string }, useSkill: boolean?): { [string]: string }
	assert(#teamNames > 0, "balance needs at least one team")
	local sorted = table.clone(players)
	table.sort(sorted, function(a: PlayerSkill, b: PlayerSkill): boolean
		local skillA, skillB = a.skill or 0, b.skill or 0
		if useSkill and skillA ~= skillB then
			return skillA > skillB
		end
		return a.id < b.id
	end)
	local result: { [string]: string } = {}
	local count = #teamNames
	for index, player in sorted do
		local slot = (index - 1) % count
		local roundNumber = math.floor((index - 1) / count)
		if useSkill and roundNumber % 2 == 1 then
			slot = count - 1 - slot
		end
		result[player.id] = teamNames[slot + 1]
	end
	return result
end

-- Moves players from the largest to the smallest team until sizes differ by at most `maxImbalance`.
-- Picks the player whose move leaves the two teams' total skill closest. Returns the moves made.
function Teams.rebalance(state: State, maxImbalance: number?): { Move }
	local limit = math.max(1, maxImbalance or 1)
	local moves: { Move } = {}
	for _ = 1, 1000 do
		local largest, smallest = state.order[1], state.order[1]
		for _, team in state.order do
			if Teams.size(state, team) > Teams.size(state, largest) then
				largest = team
			end
			if Teams.size(state, team) < Teams.size(state, smallest) then
				smallest = team
			end
		end
		local gap = Teams.size(state, largest) - Teams.size(state, smallest)
		if gap <= limit or Teams.size(state, smallest) >= state.maxSize[smallest] then
			break
		end
		local sumLarge, sumSmall = Teams.totalSkill(state, largest), Teams.totalSkill(state, smallest)
		local bestId: string? = nil
		local bestScore = math.huge
		for _, playerId in Teams.membersOf(state, largest) do
			local skill = state.members[largest][playerId]
			local score = math.abs(sumLarge - skill - (sumSmall + skill))
			if score < bestScore then
				bestId = playerId
				bestScore = score
			end
		end
		if bestId == nil then
			break
		end
		place(state, bestId, smallest, state.members[largest][bestId])
		table.insert(moves, { playerId = bestId, from = largest, to = smallest })
	end
	return moves
end

-- Whether an attack should deal damage. Players without a team (nil) can always be damaged by others.
function Teams.canDamage(
	rules: DamageRules,
	attackerId: string,
	victimId: string,
	attackerTeam: string?,
	victimTeam: string?
): boolean
	if attackerId == victimId then
		return rules.selfDamage == true
	end
	if attackerTeam == nil or victimTeam == nil or attackerTeam ~= victimTeam then
		return true
	end
	return rules.friendlyFire == true
end

-- Adds to a team's score (negative amounts are allowed). Returns the new score, or nil for unknown teams.
function Teams.addScore(state: State, team: string, amount: number): number?
	local current = state.scores[team]
	if current == nil or not isFinite(amount) then
		return nil
	end
	local score = current + amount
	state.scores[team] = score
	return score
end

function Teams.resetScores(state: State)
	for _, team in state.order do
		state.scores[team] = 0
	end
end

-- Teams sorted by score, highest first; ties keep the team order.
function Teams.standings(state: State): { Standing }
	local rows: { Standing } = {}
	for _, team in state.order do
		table.insert(rows, { team = team, score = state.scores[team] })
	end
	local position: { [string]: number } = {}
	for index, team in state.order do
		position[team] = index
	end
	table.sort(rows, function(a: Standing, b: Standing): boolean
		if a.score ~= b.score then
			return a.score > b.score
		end
		return position[a.team] < position[b.team]
	end)
	return rows
end

-- The team with the highest score, or nil when the top score is shared.
function Teams.leader(state: State): string?
	local rows = Teams.standings(state)
	local first, second = rows[1], rows[2]
	if first == nil then
		return nil
	end
	if second and second.score == first.score then
		return nil
	end
	return first.team
end

return Teams
