--!strict
-- Player-to-player trading. Pure Luau: `now` is injected and nothing here moves items. The logic is a
-- small state machine that makes scams and dupes hard:
--   invite -> open -> (both accept the SAME offer version) -> countdown -> settle
-- Any change to either offer bumps the version and clears both acceptances and the countdown, so a
-- player can never accept one offer and receive another. Settlement re-checks ownership through a
-- callback right before the swap; the server adapter then applies the swap atomically.

export type Offer = { pets: { string }, currency: { [string]: number } }

export type Session = {
	id: string,
	players: { number }, -- two user ids
	offers: { [number]: Offer },
	accepted: { [number]: number? }, -- user -> version they accepted
	version: number,
	stage: "open" | "countdown" | "done" | "cancelled",
	countdownEndsAt: number?,
	createdAt: number,
	reason: string?, -- why it was cancelled
}

export type Invite = { from: number, to: number, expiresAt: number }

export type Config = {
	countdown: number?, -- seconds between both accepting and the swap (default 5)
	maxPets: number?, -- per side (default 8)
	currencies: { [string]: boolean }?, -- tradeable currencies (default none)
	maxCurrency: number?, -- per currency per side (default 1e12)
	inviteSeconds: number?, -- invite lifetime (default 30)
	sessionSeconds: number?, -- an open trade times out after this (default 300)
}

export type Result = { ok: boolean, reason: string?, session: Session }

-- Ownership check used at settlement: true when `user` still owns every pet id and can pay.
export type Verify = (user: number, offer: Offer) -> (boolean, string?)

local TradingLogic = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function emptyOffer(): Offer
	return { pets = {}, currency = {} }
end

local function copy(session: Session): Session
	local offers: { [number]: Offer } = {}
	for user, offer in session.offers do
		offers[user] = { pets = table.clone(offer.pets), currency = table.clone(offer.currency) }
	end
	return {
		id = session.id,
		players = table.clone(session.players),
		offers = offers,
		accepted = table.clone(session.accepted),
		version = session.version,
		stage = session.stage,
		countdownEndsAt = session.countdownEndsAt,
		createdAt = session.createdAt,
		reason = session.reason,
	}
end

local function isMember(session: Session, user: number): boolean
	return session.players[1] == user or session.players[2] == user
end

function TradingLogic.other(session: Session, user: number): number
	return if session.players[1] == user then session.players[2] else session.players[1]
end

function TradingLogic.invite(config: Config, from: number, to: number, now: number): (boolean, string?, Invite?)
	if from == to then
		return false, "cannot trade with yourself", nil
	end
	return true, nil, { from = from, to = to, expiresAt = now + (config.inviteSeconds or 30) }
end

function TradingLogic.start(invite: Invite, id: string, now: number): (boolean, string?, Session?)
	if now > invite.expiresAt then
		return false, "invite expired", nil
	end
	local session: Session = {
		id = id,
		players = { invite.from, invite.to },
		offers = { [invite.from] = emptyOffer(), [invite.to] = emptyOffer() },
		accepted = {},
		version = 1,
		stage = "open",
		countdownEndsAt = nil,
		createdAt = now,
		reason = nil,
	}
	return true, nil, session
end

-- Validates an offer's shape and limits. Ownership is checked by the server (and again at settle).
function TradingLogic.validateOffer(config: Config, offer: any): (boolean, string?)
	if type(offer) ~= "table" or type(offer.pets) ~= "table" or type(offer.currency) ~= "table" then
		return false, "bad offer"
	end
	if #offer.pets > (config.maxPets or 8) then
		return false, "too many pets"
	end
	local seen: { [string]: boolean } = {}
	for key, id in offer.pets do
		if type(key) ~= "number" or type(id) ~= "string" or #id > 32 or seen[id] then
			return false, "bad pet id"
		end
		seen[id] = true
	end
	local allowed = config.currencies or {}
	for currency, amount in offer.currency do
		if type(currency) ~= "string" or not allowed[currency] then
			return false, "currency not tradeable"
		end
		if not isFinite(amount) or amount < 0 or amount % 1 ~= 0 or amount > (config.maxCurrency or 1e12) then
			return false, "bad amount"
		end
	end
	return true, nil
end

local function changed(session: Session): Session
	session.version += 1
	session.accepted = {}
	session.stage = "open"
	session.countdownEndsAt = nil
	return session
end

-- Replaces a player's offer. Any change resets both acceptances.
function TradingLogic.setOffer(config: Config, session: Session, user: number, offer: Offer): Result
	if session.stage == "done" or session.stage == "cancelled" then
		return { ok = false, reason = "trade closed", session = session }
	end
	if not isMember(session, user) then
		return { ok = false, reason = "not in trade", session = session }
	end
	local valid, why = TradingLogic.validateOffer(config, offer)
	if not valid then
		return { ok = false, reason = why, session = session }
	end
	local nextSession = copy(session)
	local clean: { [string]: number } = {}
	for currency, amount in offer.currency do
		if amount > 0 then
			clean[currency] = amount
		end
	end
	nextSession.offers[user] = { pets = table.clone(offer.pets), currency = clean }
	return { ok = true, reason = nil, session = changed(nextSession) }
end

-- Accepts the offer as of `version`. When both players accepted the current version the countdown
-- starts.
function TradingLogic.accept(config: Config, session: Session, user: number, version: number, now: number): Result
	if session.stage ~= "open" then
		return { ok = false, reason = "not open", session = session }
	end
	if not isMember(session, user) then
		return { ok = false, reason = "not in trade", session = session }
	end
	if version ~= session.version then
		return { ok = false, reason = "offer changed", session = session }
	end
	local nextSession = copy(session)
	nextSession.accepted[user] = version
	local other = TradingLogic.other(session, user)
	if nextSession.accepted[other] == version then
		local a, b = nextSession.offers[user], nextSession.offers[other]
		if #a.pets == 0 and #b.pets == 0 and next(a.currency) == nil and next(b.currency) == nil then
			return { ok = false, reason = "empty trade", session = session }
		end
		nextSession.stage = "countdown"
		nextSession.countdownEndsAt = now + (config.countdown or 5)
	end
	return { ok = true, reason = nil, session = nextSession }
end

-- Withdraws acceptance (also stops a running countdown).
function TradingLogic.unaccept(session: Session, user: number): Result
	if not isMember(session, user) or (session.stage ~= "open" and session.stage ~= "countdown") then
		return { ok = false, reason = "not open", session = session }
	end
	local nextSession = copy(session)
	nextSession.accepted[user] = nil
	nextSession.stage = "open"
	nextSession.countdownEndsAt = nil
	return { ok = true, reason = nil, session = nextSession }
end

function TradingLogic.cancel(session: Session, reason: string): Session
	local nextSession = copy(session)
	if nextSession.stage ~= "done" then
		nextSession.stage = "cancelled"
		nextSession.reason = reason
	end
	return nextSession
end

-- Times out stale trades. Returns the (possibly cancelled) session.
function TradingLogic.tick(config: Config, session: Session, now: number): Session
	if session.stage == "open" and now - session.createdAt > (config.sessionSeconds or 300) then
		return TradingLogic.cancel(session, "timed out")
	end
	return session
end

function TradingLogic.isReady(session: Session, now: number): boolean
	return session.stage == "countdown" and session.countdownEndsAt ~= nil and now >= session.countdownEndsAt
end

export type Settlement = {
	ok: boolean,
	reason: string?,
	session: Session,
	-- What each user gives away (their own offer); the adapter moves it to the other user.
	gives: { [number]: Offer },
}

-- Final check right before the swap. `verify` must re-read live server data. On any failure the
-- trade is cancelled and nothing moves.
function TradingLogic.settle(session: Session, now: number, verify: Verify): Settlement
	if not TradingLogic.isReady(session, now) then
		return { ok = false, reason = "not ready", session = session, gives = {} }
	end
	for _, user in session.players do
		if session.accepted[user] ~= session.version then
			return {
				ok = false,
				reason = "not accepted",
				session = TradingLogic.cancel(session, "not accepted"),
				gives = {},
			}
		end
		local ok, why = verify(user, session.offers[user])
		if not ok then
			local reason = why or "items changed"
			return { ok = false, reason = reason, session = TradingLogic.cancel(session, reason), gives = {} }
		end
	end
	local nextSession = copy(session)
	nextSession.stage = "done"
	local gives: { [number]: Offer } = {}
	for _, user in session.players do
		gives[user] = nextSession.offers[user]
	end
	return { ok = true, reason = nil, session = nextSession, gives = gives }
end

-- Value ratio of the smaller side to the larger (1 = even), for a "this trade looks uneven" warning.
-- `valueOf(offer)` is the game's own estimate. Returns 1 when both are worth 0.
function TradingLogic.fairness(session: Session, valueOf: (offer: Offer) -> number): number
	local a = valueOf(session.offers[session.players[1]])
	local b = valueOf(session.offers[session.players[2]])
	local high = math.max(a, b)
	if high <= 0 then
		return 1
	end
	return math.min(a, b) / high
end

return TradingLogic
