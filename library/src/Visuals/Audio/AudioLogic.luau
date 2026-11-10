--!strict
-- Sound cue registry (pure Luau). The kit bundles no sounds: every visual module plays cues by
-- name, and a cue is silent until the game registers an asset id for it. This module holds the
-- registry and decides, with the time passed in, whether a cue may play now (cooldown, maximum
-- concurrent copies) and at what volume and pitch.

export type Cue = {
	id: string, -- normalised content id
	volume: number, -- 0..1 (default 0.6)
	pitch: number, -- playback speed (default 1)
	pitchVariance: number, -- +/- fraction applied per play (default 0)
	cooldown: number, -- seconds between plays of this cue (default 0.03)
	maxConcurrent: number, -- copies that may sound at once (default 4)
	group: string, -- volume group (default "ui" for ui.* cues, otherwise "sfx")
}

export type Play = { cue: string, id: string, volume: number, pitch: number, group: string }

export type State = {
	cues: { [string]: Cue },
	lastPlayed: { [string]: number },
	live: { [string]: number },
	plays: { [string]: number },
	volumes: { [string]: number },
	master: number,
	muted: boolean,
}

local AudioLogic = {}

-- The cues the kit itself plays. Register any of them; the rest stay silent.
AudioLogic.CUES = table.freeze({
	"ui.hover",
	"ui.press",
	"ui.pop",
	"ui.close",
	"tap",
	"coin",
	"gem",
	"error",
	"success",
	"whoosh",
	"impact",
	"egg.land",
	"egg.wobble",
	"egg.energy",
	"egg.crack",
	"egg.reveal",
	"rarity.common",
	"rarity.uncommon",
	"rarity.rare",
	"rarity.epic",
	"rarity.legendary",
	"rarity.mythic",
	"rarity.secret",
	"reward.reveal",
	"level.up",
	"quest.complete",
	"pet.happy",
	"food.throw",
	"food.hit",
})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function AudioLogic.new(): State
	return { cues = {}, lastPlayed = {}, live = {}, plays = {}, volumes = {}, master = 1, muted = false }
end

-- Turns 123, "123", "rbxassetid://123" or an asset URL into "rbxassetid://123". Built-in
-- "rbxasset://" paths are kept. Returns nil for anything else.
function AudioLogic.normalizeId(value: any): string?
	if type(value) == "number" then
		if finite(value) and value > 0 and value == math.floor(value) then
			return string.format("rbxassetid://%d", value)
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local text = string.match(value, "^%s*(.-)%s*$") or ""
	local digits = string.match(text, "^(%d+)$")
		or string.match(text, "^rbxassetid://(%d+)$")
		or string.match(text, "^https?://[%w%.]*roblox%.com/asset/?%?id=(%d+)$")
		or string.match(text, "^https?://create%.roblox%.com/store/asset/(%d+)")
	if digits and tonumber(digits) ~= 0 then
		return "rbxassetid://" .. digits
	end
	if string.match(text, "^rbxasset://.+") then
		return text
	end
	return nil
end

function AudioLogic.defaultGroup(cue: string): string
	return if string.sub(cue, 1, 3) == "ui." then "ui" else "sfx"
end

-- Registers a cue from an id or an options table { id, volume, pitch, pitchVariance, cooldown,
-- maxConcurrent, group }. Passing nil or false removes the cue. Errors on invalid input.
function AudioLogic.register(state: State, cue: string, idOrOptions: any): Cue?
	assert(type(cue) == "string" and cue ~= "", "cue name must be a non-empty string")
	if idOrOptions == nil or idOrOptions == false then
		state.cues[cue] = nil
		return nil
	end
	local options: { [string]: any } = if type(idOrOptions) == "table" then idOrOptions else { id = idOrOptions }
	local id = AudioLogic.normalizeId(options.id)
	assert(id ~= nil, "cue " .. cue .. " needs a sound asset id")
	local function number(field: string, default: number, min: number, max: number): number
		local value = options[field]
		if value == nil then
			return default
		end
		assert(finite(value) and value >= min and value <= max, field .. " must be between " .. min .. " and " .. max)
		return value
	end
	local group = options.group
	assert(group == nil or (type(group) == "string" and group ~= ""), "group must be a non-empty string")
	local entry: Cue = {
		id = id,
		volume = number("volume", 0.6, 0, 1),
		pitch = number("pitch", 1, 0.1, 4),
		pitchVariance = number("pitchVariance", 0, 0, 0.5),
		cooldown = number("cooldown", 0.03, 0, 60),
		maxConcurrent = math.floor(number("maxConcurrent", 4, 1, 16)),
		group = group or AudioLogic.defaultGroup(cue),
	}
	state.cues[cue] = entry
	return entry
end

function AudioLogic.isRegistered(state: State, cue: any): boolean
	return type(cue) == "string" and state.cues[cue] ~= nil
end

-- Registered cue names, sorted.
function AudioLogic.registered(state: State): { string }
	local names: { string } = {}
	for name in state.cues do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- A repeatable value in [-1, 1] for the n-th play of a cue: the same cue and count always give
-- the same result, and consecutive plays differ, so rapid sounds never repeat mechanically.
function AudioLogic.variation(cue: string, n: number): number
	local hash = 2166136261
	for index = 1, #cue do
		hash = (bit32.bxor(hash, string.byte(cue, index)) * 16777619) % 4294967296
	end
	hash = (bit32.bxor(hash, math.floor(n) % 4294967296) * 2654435761) % 4294967296
	hash = bit32.bxor(hash, bit32.rshift(hash, 15))
	hash = (hash * 2246822519) % 4294967296
	hash = bit32.bxor(hash, bit32.rshift(hash, 13))
	return (hash % 20001) / 10000 - 1
end

-- Sets the volume (0..1) of a group, or the master volume when group is nil.
function AudioLogic.setVolume(state: State, group: string?, volume: number)
	assert(finite(volume), "volume must be a number")
	local clamped = math.clamp(volume, 0, 1)
	if group == nil then
		state.master = clamped
	else
		state.volumes[group] = clamped
	end
end

function AudioLogic.groupVolume(state: State, group: string?): number
	if group == nil then
		return state.master
	end
	return state.volumes[group] or 1
end

export type PlayOptions = { volume: number?, pitch: number?, pitchVariance: number?, force: boolean? }

-- Decides whether `cue` plays at time `now`. Returns the play (id, volume, pitch, group) and
-- records it, or nil and the reason: "unregistered", "muted", "cooldown" or "concurrency".
-- options.volume and options.pitch multiply the cue's own; options.force ignores the cooldown.
-- Call ended() when the sound stops so the concurrency count stays right.
function AudioLogic.decide(state: State, cue: string, now: number, options: PlayOptions?): (Play?, string?)
	local entry = state.cues[cue]
	if entry == nil then
		return nil, "unregistered"
	end
	if state.muted then
		return nil, "muted"
	end
	local opts: PlayOptions = options or {}
	local last = state.lastPlayed[cue]
	if not opts.force and last ~= nil and now - last < entry.cooldown then
		return nil, "cooldown"
	end
	if (state.live[cue] or 0) >= entry.maxConcurrent then
		return nil, "concurrency"
	end
	local count = (state.plays[cue] or 0) + 1
	state.plays[cue] = count
	state.lastPlayed[cue] = now
	state.live[cue] = (state.live[cue] or 0) + 1
	local variance = math.clamp(opts.pitchVariance or entry.pitchVariance, 0, 0.5)
	local pitch = entry.pitch * (opts.pitch or 1) * (1 + variance * AudioLogic.variation(cue, count))
	local volume = entry.volume * (opts.volume or 1) * state.master * (state.volumes[entry.group] or 1)
	return {
		cue = cue,
		id = entry.id,
		volume = math.clamp(volume, 0, 1),
		pitch = math.clamp(pitch, 0.1, 4),
		group = entry.group,
	},
		nil
end

-- Marks one copy of `cue` as finished.
function AudioLogic.ended(state: State, cue: string)
	local live = state.live[cue]
	if live == nil then
		return
	end
	if live > 1 then
		state.live[cue] = live - 1
	else
		state.live[cue] = nil
	end
end

function AudioLogic.live(state: State, cue: string): number
	return state.live[cue] or 0
end

return AudioLogic
