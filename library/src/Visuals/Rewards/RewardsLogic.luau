--!strict
-- Rarity profiles and reveal plans (pure Luau). A profile is data describing how a rarity is
-- presented; plan() turns a profile into an ordered list of timed steps that Rewards.luau (and
-- the egg hatch) execute. Nothing here touches an Instance, so every timing rule is spec'd.
--
-- Hierarchy rules the built-in profiles follow and register() keeps readable:
--   * duration, particle intensity and layer count never decrease with rank
--   * Common to Rare never flash the screen; Epic and above use at most one soft flash, which
--     reducedFlashing removes
--   * camera shakes are short and soft (Tap, SoftImpact, Impact only)

export type Vfx = { id: string, at: number?, params: { [string]: any }?, optional: boolean? }

export type Camera = { shake: string?, cinematic: string?, fov: number? }

export type Text = { sizeStep: number, stroke: number, shimmer: boolean }

export type Profile = {
	id: string,
	rank: number,
	label: string,
	color: string, -- hex
	secondary: string, -- hex, gradient partner
	glow: string, -- hex, rays and glow
	duration: number, -- seconds from the start to the settled state (anticipation included)
	anticipation: number, -- seconds before the reveal
	revealStyle: string, -- one of STYLES
	scalePunch: number, -- overshoot of the reveal, as a fraction of the final scale
	spring: string, -- Core/Springs preset used for the reveal
	background: string, -- one of BACKGROUNDS
	rayCount: number,
	raySpeed: number, -- degrees per second
	particles: number, -- intensity multiplier passed to VFX
	layers: number, -- how many visual layers the reveal stacks (for the hierarchy check)
	vfx: { Vfx }, -- `at` is seconds after the reveal
	camera: Camera,
	sounds: { string }, -- cue names played at the reveal
	text: Text,
	hold: number, -- seconds between settled and auto-dismiss
	flash: string, -- "none" | "soft"
}

export type Options = {
	speed: number?,
	skipAnticipation: boolean?,
	compact: boolean?,
	reducedMotion: boolean?,
	reducedFlashing: boolean?,
	quality: string?, -- "Low" | "Medium" | "High" | "Ultra"
	fastForward: (boolean | number)?,
	threshold: string?, -- planBatch: rarities at or above this get the full reveal (default "Epic")
	columns: number?, -- planBatch: grid columns (default: chosen from the group size)
}

export type Step = {
	time: number,
	kind: string,
	duration: number?,
	cosmetic: boolean, -- cosmetic steps are dropped when skipping or fast-forwarding
	payload: { [string]: any },
}

export type Plan = {
	rarity: string,
	profile: Profile,
	steps: { Step },
	revealAt: number,
	settledAt: number, -- also the length of the timed part of the plan
	hintAt: number, -- when the "tap to continue" hint appears (after settledAt)
	dismissAt: number, -- auto-dismiss time
	dismissDuration: number,
	duration: number, -- dismissAt + dismissDuration
	flashes: number,
}

export type BatchItem = { index: number, rarity: string, reward: any, rank: number }

export type Group = {
	kind: string, -- "grid" | "full"
	rarity: string,
	startAt: number,
	duration: number,
	items: { BatchItem },
	stagger: number, -- grid: seconds between tiles
	columns: number, -- grid
	rows: number, -- grid
	plan: Plan?, -- full
}

export type Batch = {
	items: { BatchItem }, -- sorted, rarest last
	groups: { Group },
	duration: number,
	fastForward: number, -- time compression factor (1 = none)
}

local RewardsLogic = {}

RewardsLogic.ORDER = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" })

RewardsLogic.STYLES = table.freeze({ "pop", "bounce", "flip", "burst", "beam", "shatter", "eclipse", "spiral" })

RewardsLogic.BACKGROUNDS = table.freeze({ "none", "dim", "rays", "wash", "starfield" })

-- Shakes a profile may use. Anything stronger would break the "short and soft" rule.
RewardsLogic.SOFT_SHAKES = table.freeze({ "Tap", "SoftImpact", "Impact" })

RewardsLogic.CINEMATICS = table.freeze({ "RewardReveal", "PetReveal" })

RewardsLogic.DEFAULT_FAST_FORWARD = 3

local function builtins(): { [string]: Profile }
	return {
		Common = {
			id = "Common",
			rank = 1,
			label = "COMMON",
			color = "#B8C4D0",
			secondary = "#8E9BAA",
			glow = "#FFFFFF",
			duration = 1.2,
			anticipation = 0,
			revealStyle = "pop",
			scalePunch = 0.12,
			spring = "Snappy",
			background = "none",
			rayCount = 0,
			raySpeed = 0,
			particles = 0.35,
			layers = 1,
			vfx = { { id = "SparkleBurst", at = 0 } },
			camera = {},
			sounds = { "reward.reveal", "rarity.common" },
			text = { sizeStep = 0, stroke = 2, shimmer = false },
			hold = 1.2,
			flash = "none",
		},
		Uncommon = {
			id = "Uncommon",
			rank = 2,
			label = "UNCOMMON",
			color = "#5FD35F",
			secondary = "#2FA84A",
			glow = "#C8FFC0",
			duration = 1.5,
			anticipation = 0.15,
			revealStyle = "bounce",
			scalePunch = 0.18,
			spring = "Bouncy",
			background = "dim",
			rayCount = 0,
			raySpeed = 0,
			particles = 0.5,
			layers = 2,
			vfx = { { id = "SparkleBurst", at = 0 }, { id = "RewardGlow", at = 0.05, optional = true } },
			camera = {},
			sounds = { "reward.reveal", "rarity.uncommon" },
			text = { sizeStep = 0, stroke = 2, shimmer = false },
			hold = 1.3,
			flash = "none",
		},
		Rare = {
			id = "Rare",
			rank = 3,
			label = "RARE",
			color = "#3FA7FF",
			secondary = "#1F6FE0",
			glow = "#BFE4FF",
			duration = 1.9,
			anticipation = 0.3,
			revealStyle = "flip",
			scalePunch = 0.22,
			spring = "Bouncy",
			background = "dim",
			rayCount = 6,
			raySpeed = 18,
			particles = 0.7,
			layers = 3,
			vfx = {
				{ id = "RarityBurst", at = 0, params = { rarity = "Rare" } },
				{ id = "RewardGlow", at = 0.05 },
				{ id = "SparkleBurst", at = 0.2, optional = true },
			},
			camera = {},
			sounds = { "reward.reveal", "rarity.rare" },
			text = { sizeStep = 1, stroke = 2, shimmer = false },
			hold = 1.5,
			flash = "none",
		},
		Epic = {
			id = "Epic",
			rank = 4,
			label = "EPIC",
			color = "#B45CFF",
			secondary = "#7A2FE0",
			glow = "#E6C8FF",
			duration = 2.4,
			anticipation = 0.5,
			revealStyle = "burst",
			scalePunch = 0.28,
			spring = "Overshoot",
			background = "rays",
			rayCount = 8,
			raySpeed = 28,
			particles = 0.9,
			layers = 4,
			vfx = {
				{ id = "RarityBurst", at = 0, params = { rarity = "Epic" } },
				{ id = "RewardGlow", at = 0.05 },
				{ id = "SparkleBurst", at = 0.25, optional = true },
			},
			camera = { shake = "Tap" },
			sounds = { "reward.reveal", "rarity.epic" },
			text = { sizeStep = 1, stroke = 3, shimmer = false },
			hold = 1.8,
			flash = "soft",
		},
		Legendary = {
			id = "Legendary",
			rank = 5,
			label = "LEGENDARY",
			color = "#FFC02E",
			secondary = "#FF8A1F",
			glow = "#FFF2B0",
			duration = 2.9,
			anticipation = 0.75,
			revealStyle = "beam",
			scalePunch = 0.34,
			spring = "Overshoot",
			background = "rays",
			rayCount = 12,
			raySpeed = 36,
			particles = 1.15,
			layers = 5,
			vfx = {
				{ id = "RarityBeam", at = 0, params = { rarity = "Legendary" } },
				{ id = "RarityBurst", at = 0.05, params = { rarity = "Legendary" } },
				{ id = "GoldenShine", at = 0.2 },
				{ id = "Confetti", at = 0.35, optional = true },
			},
			camera = { shake = "SoftImpact" },
			sounds = { "reward.reveal", "rarity.legendary" },
			text = { sizeStep = 2, stroke = 3, shimmer = true },
			hold = 2.2,
			flash = "soft",
		},
		Mythic = {
			id = "Mythic",
			rank = 6,
			label = "MYTHIC",
			color = "#FF4D8D",
			secondary = "#C01F6B",
			glow = "#FFC2DC",
			duration = 3.5,
			anticipation = 1,
			revealStyle = "shatter",
			scalePunch = 0.4,
			spring = "Elastic",
			background = "wash",
			rayCount = 14,
			raySpeed = 44,
			particles = 1.35,
			layers = 6,
			vfx = {
				{ id = "RarityBeam", at = 0, params = { rarity = "Mythic" } },
				{ id = "RarityBurst", at = 0.05, params = { rarity = "Mythic" } },
				{ id = "GoldenShine", at = 0.2 },
				{ id = "Fireworks", at = 0.4 },
				{ id = "Confetti", at = 0.6, optional = true },
			},
			camera = { shake = "Impact", fov = 6 },
			sounds = { "reward.reveal", "rarity.mythic" },
			text = { sizeStep = 2, stroke = 4, shimmer = true },
			hold = 2.6,
			flash = "soft",
		},
		Secret = {
			id = "Secret",
			rank = 7,
			label = "SECRET",
			color = "#1B1B2F",
			secondary = "#6C3BFF",
			glow = "#FFFFFF",
			duration = 3.8,
			anticipation = 1.2,
			revealStyle = "eclipse",
			scalePunch = 0.45,
			spring = "Elastic",
			background = "starfield",
			rayCount = 16,
			raySpeed = 52,
			particles = 1.5,
			layers = 7,
			vfx = {
				{ id = "RarityBeam", at = 0, params = { rarity = "Secret" } },
				{ id = "RarityBurst", at = 0.05, params = { rarity = "Secret" } },
				{ id = "RewardGlow", at = 0.1 },
				{ id = "GoldenShine", at = 0.25 },
				{ id = "Fireworks", at = 0.45 },
				{ id = "Confetti", at = 0.7, optional = true },
			},
			camera = { shake = "SoftImpact", cinematic = "RewardReveal", fov = 8 },
			sounds = { "reward.reveal", "rarity.secret" },
			text = { sizeStep = 3, stroke = 4, shimmer = true },
			hold = 3,
			flash = "soft",
		},
	}
end

local profiles: { [string]: Profile } = builtins()
local customOrder: { string } = {}

local function contains(list: { string }, value: any): boolean
	return table.find(list, value) ~= nil
end

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- Checks a complete profile. Returns false and a message naming the first problem.
function RewardsLogic.validate(profile: any): (boolean, string?)
	if type(profile) ~= "table" then
		return false, "profile must be a table"
	end
	if type(profile.id) ~= "string" or profile.id == "" then
		return false, "id must be a non-empty string"
	end
	if not finite(profile.rank) or profile.rank < 0 then
		return false, "rank must be a number >= 0"
	end
	if type(profile.label) ~= "string" then
		return false, "label must be a string"
	end
	for _, field in { "color", "secondary", "glow" } do
		if not isHex(profile[field]) then
			return false, field .. " must be a hex colour like #FFC02E"
		end
	end
	if not finite(profile.duration) or profile.duration <= 0 or profile.duration > 10 then
		return false, "duration must be in (0, 10]"
	end
	if not finite(profile.anticipation) or profile.anticipation < 0 or profile.anticipation >= profile.duration then
		return false, "anticipation must be >= 0 and shorter than duration"
	end
	if not contains(RewardsLogic.STYLES, profile.revealStyle) then
		return false, "unknown revealStyle " .. tostring(profile.revealStyle)
	end
	if not contains(RewardsLogic.BACKGROUNDS, profile.background) then
		return false, "unknown background " .. tostring(profile.background)
	end
	for _, field in { "scalePunch", "rayCount", "raySpeed", "particles", "layers", "hold" } do
		if not finite(profile[field]) or profile[field] < 0 then
			return false, field .. " must be a number >= 0"
		end
	end
	if profile.scalePunch > 1 then
		return false, "scalePunch must be <= 1"
	end
	if type(profile.spring) ~= "string" then
		return false, "spring must be a spring preset name"
	end
	if profile.flash ~= "none" and profile.flash ~= "soft" then
		return false, 'flash must be "none" or "soft"'
	end
	if type(profile.vfx) ~= "table" then
		return false, "vfx must be a list"
	end
	for index, entry in profile.vfx do
		if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" then
			return false, "vfx[" .. tostring(index) .. "] needs an id"
		end
		if entry.at ~= nil and (not finite(entry.at) or entry.at < 0) then
			return false, "vfx[" .. tostring(index) .. "].at must be >= 0"
		end
	end
	if type(profile.camera) ~= "table" then
		return false, "camera must be a table"
	end
	if profile.camera.shake ~= nil and not contains(RewardsLogic.SOFT_SHAKES, profile.camera.shake) then
		return false, "camera.shake must be one of Tap, SoftImpact, Impact"
	end
	if profile.camera.cinematic ~= nil and type(profile.camera.cinematic) ~= "string" then
		return false, "camera.cinematic must be a cinematic name"
	end
	if profile.camera.fov ~= nil and (not finite(profile.camera.fov) or math.abs(profile.camera.fov) > 20) then
		return false, "camera.fov must be within -20..20 degrees"
	end
	if type(profile.sounds) ~= "table" then
		return false, "sounds must be a list of cue names"
	end
	for _, cue in profile.sounds do
		if type(cue) ~= "string" then
			return false, "sounds must be a list of cue names"
		end
	end
	local text = profile.text
	if type(text) ~= "table" or not finite(text.sizeStep) or not finite(text.stroke) then
		return false, "text needs sizeStep and stroke numbers"
	end
	if type(text.shimmer) ~= "boolean" then
		return false, "text.shimmer must be a boolean"
	end
	return true, nil
end

-- Registers a custom rarity. `profile` may be partial when it names a base to copy from with
-- `extends = "Epic"` (default "Common"); fields given replace the base's. Errors on invalid data
-- and on a built-in id unless profile.override is true.
function RewardsLogic.register(id: string, profile: { [string]: any }): Profile
	assert(type(id) == "string" and id ~= "", "rarity id must be a non-empty string")
	assert(type(profile) == "table", "profile must be a table")
	local builtIn = contains(RewardsLogic.ORDER, id)
	assert(not builtIn or profile.override == true, "rarity " .. id .. " is built in; pass override = true")
	local baseId = profile.extends
	local base: Profile? = nil
	if baseId ~= nil then
		base = profiles[baseId]
		assert(base ~= nil, "unknown base rarity " .. tostring(baseId))
	elseif profiles[id] ~= nil then
		base = profiles[id]
	else
		base = profiles.Common
	end
	local merged: { [string]: any } = deepCopy(base)
	for key, value in profile do
		if key ~= "extends" and key ~= "override" then
			merged[key] = deepCopy(value)
		end
	end
	merged.id = id
	if profile.label == nil and base ~= nil and base.id ~= id then
		merged.label = string.upper(id)
	end
	local ok, message = RewardsLogic.validate(merged)
	assert(ok, "invalid rarity " .. id .. ": " .. tostring(message))
	if profiles[id] == nil then
		table.insert(customOrder, id)
	end
	local stored: Profile = merged :: any
	profiles[id] = stored
	return deepCopy(stored)
end

-- Removes every custom rarity and restores the built-in profiles.
function RewardsLogic.reset()
	profiles = builtins()
	customOrder = {}
end

function RewardsLogic.has(id: any): boolean
	return type(id) == "string" and profiles[id] ~= nil
end

-- The profile for `id`. Unknown rarities fall back to Common, so a reveal never fails on data.
function RewardsLogic.get(id: any): Profile
	local found = if type(id) == "string" then profiles[id] else nil
	return deepCopy(found or profiles.Common)
end

function RewardsLogic.rank(id: any): number
	local found = if type(id) == "string" then profiles[id] else nil
	return if found then found.rank else profiles.Common.rank
end

-- Every registered rarity, lowest rank first (ties keep registration order).
function RewardsLogic.list(): { string }
	local ids: { string } = table.clone(RewardsLogic.ORDER)
	for _, id in customOrder do
		table.insert(ids, id)
	end
	local position: { [string]: number } = {}
	for index, id in ids do
		position[id] = index
	end
	table.sort(ids, function(a: string, b: string): boolean
		local ra, rb = profiles[a].rank, profiles[b].rank
		if ra == rb then
			return position[a] < position[b]
		end
		return ra < rb
	end)
	return ids
end

-- Negative when a ranks below b, 0 when equal, positive when above.
function RewardsLogic.compare(a: any, b: any): number
	return RewardsLogic.rank(a) - RewardsLogic.rank(b)
end

function RewardsLogic.atLeast(id: any, minimum: any): boolean
	return RewardsLogic.rank(id) >= RewardsLogic.rank(minimum)
end

-- Hex colour for a rarity (Common's for unknown ids).
function RewardsLogic.color(id: any): string
	return RewardsLogic.get(id).color
end

function RewardsLogic.label(id: any): string
	return RewardsLogic.get(id).label
end

-- Returns a new list sorted so the rarest comes last. Entries are rarity ids or tables with a
-- `rarity` field; the sort is stable.
function RewardsLogic.sort<T>(entries: { T }): { T }
	local keyed: { { entry: T, rank: number, index: number } } = {}
	for index, entry in entries do
		local value: any = entry
		local rarity = if type(value) == "table" then value.rarity else value
		table.insert(keyed, { entry = entry, rank = RewardsLogic.rank(rarity), index = index })
	end
	type Keyed = { entry: T, rank: number, index: number }
	table.sort(keyed, function(a: Keyed, b: Keyed): boolean
		if a.rank == b.rank then
			return a.index < b.index
		end
		return a.rank < b.rank
	end)
	local sorted: { T } = {}
	for _, item in keyed do
		table.insert(sorted, item.entry)
	end
	return sorted
end

local function speedOf(options: Options?): number
	local speed = if options and options.speed then options.speed else 1
	if not finite(speed) or speed <= 0 then
		return 1
	end
	return math.clamp(speed, 0.1, 10)
end

local function fastFactor(options: Options?): number
	local value = if options then options.fastForward else nil
	if value == true then
		return RewardsLogic.DEFAULT_FAST_FORWARD
	elseif type(value) == "number" and finite(value) and value > 1 then
		return math.min(value, 10)
	end
	return 1
end

-- Seconds a number counter should roll for a given amount: 0.4 s for small amounts up to 1.2 s.
function RewardsLogic.countDuration(amount: any): number
	if not finite(amount) or amount <= 1 then
		return 0
	end
	return math.clamp(0.4 + 0.2 * math.log10(amount), 0.4, 1.2)
end

-- Builds the timed steps for one reveal. Step kinds, in the order they can appear:
--   open        backdrop and background treatment appear        payload: background, rayCount, raySpeed
--   anticipate  item hidden, glow builds over `duration`        payload: intensity
--   shake       camera shake                                    payload: preset
--   sound       audio cue                                       payload: cue
--   camera      cinematic and/or FOV punch                      payload: cinematic?, fov?
--   flash       one soft full-screen flash                      payload: color, strength
--   reveal      the item appears with a scale punch             payload: style, punch, spring
--   vfx         VFX preset                                      payload: id, params
--   label       rarity label and name appear                    payload: text, sizeStep, stroke, shimmer
--   count       amount counts up over `duration`                payload: amount
--   settle      everything is in its final state                (never cosmetic)
function RewardsLogic.plan(rarity: any, reward: any, options: Options?): Plan
	local profile = RewardsLogic.get(rarity)
	local opts: Options = options or {}
	local speed = speedOf(opts) * fastFactor(opts)
	local fast = fastFactor(opts) > 1
	local compact = opts.compact == true or fast
	local reducedMotion = opts.reducedMotion == true
	local low = opts.quality == "Low"

	local anticipation = profile.anticipation
	if opts.skipAnticipation or compact then
		anticipation = 0
	elseif reducedMotion then
		anticipation *= 0.5
	end
	local settle = profile.duration - profile.anticipation
	if compact then
		settle *= 0.5
	elseif reducedMotion then
		settle *= 0.7
	end
	local hold = profile.hold
	if compact then
		hold *= 0.5
	end

	local steps: { Step } = {}
	local order: { [Step]: number } = {}
	local flashes = 0
	local function add(time: number, kind: string, cosmetic: boolean, payload: { [string]: any }, duration: number?)
		local step: Step = {
			time = time / speed,
			kind = kind,
			cosmetic = cosmetic,
			payload = payload,
			duration = if duration then duration / speed else nil,
		}
		table.insert(steps, step)
		order[step] = #steps
	end

	local background = if compact and profile.background ~= "none" then "dim" else profile.background
	local rayCount = if compact then 0 else profile.rayCount
	if low then
		rayCount = math.floor(rayCount / 2)
	end
	add(0, "open", false, {
		background = background,
		rayCount = rayCount,
		raySpeed = if reducedMotion then 0 else profile.raySpeed,
		color = profile.color,
		glow = profile.glow,
	}, 0.15)

	if anticipation > 0 then
		add(0, "anticipate", true, { intensity = profile.particles, color = profile.glow }, anticipation)
		add(0, "sound", true, { cue = "whoosh" })
		if profile.rank >= 4 and not reducedMotion then
			add(anticipation * 0.55, "shake", true, { preset = "Tap", phase = "anticipation" })
		end
	end

	local revealAt = anticipation
	if profile.flash ~= "none" and not opts.reducedFlashing and not fast then
		flashes += 1
		add(revealAt, "flash", true, { color = profile.glow, strength = 0.55, duration = 0.35 })
	end
	add(revealAt, "reveal", false, {
		style = if reducedMotion then "pop" else profile.revealStyle,
		punch = if reducedMotion then 0 else profile.scalePunch,
		spring = profile.spring,
	}, math.min(0.45, settle))
	for _, cue in profile.sounds do
		add(revealAt, "sound", true, { cue = cue })
	end
	if not reducedMotion and not compact then
		if profile.camera.shake then
			add(revealAt, "shake", true, { preset = profile.camera.shake, phase = "reveal" })
		end
		if profile.camera.cinematic or profile.camera.fov then
			add(revealAt, "camera", true, { cinematic = profile.camera.cinematic, fov = profile.camera.fov })
		end
	end
	if not fast then
		local kept = 0
		for _, entry in profile.vfx do
			local dropped = entry.optional == true and (low or compact)
			if not dropped and not (compact and kept >= 2) then
				kept += 1
				local params: { [string]: any } = deepCopy(entry.params or {})
				params.color = params.color or profile.color
				params.intensity = profile.particles
				local at = math.min(entry.at or 0, settle * 0.8)
				add(revealAt + at, "vfx", true, { id = entry.id, params = params })
			end
		end
	end
	add(revealAt + math.min(0.08, settle * 0.2), "label", false, {
		text = profile.label,
		color = profile.color,
		sizeStep = profile.text.sizeStep,
		stroke = profile.text.stroke,
		shimmer = profile.text.shimmer and not reducedMotion and not compact,
	})
	local amount = if type(reward) == "table" then reward.amount else nil
	local countFor = RewardsLogic.countDuration(amount)
	if countFor > 0 then
		local start = math.min(0.2, settle * 0.3)
		add(revealAt + start, "count", false, { amount = amount }, math.min(countFor, settle - start))
	end
	local settledAt = revealAt + settle
	add(settledAt, "settle", false, {})

	table.sort(steps, function(a: Step, b: Step): boolean
		if a.time == b.time then
			return order[a] < order[b]
		end
		return a.time < b.time
	end)

	local dismissDuration = 0.18 / speed
	local settled = settledAt / speed
	local dismissAt = settled + hold / speed
	return {
		rarity = profile.id,
		profile = profile,
		steps = steps,
		revealAt = revealAt / speed,
		settledAt = settled,
		hintAt = settled + (hold * 0.5) / speed,
		dismissAt = dismissAt,
		dismissDuration = dismissDuration,
		duration = dismissAt + dismissDuration,
		flashes = flashes,
	}
end

-- Seconds until the reveal is settled, and until it has dismissed itself.
function RewardsLogic.durations(rarity: any, reward: any, options: Options?): (number, number)
	local plan = RewardsLogic.plan(rarity, reward, options)
	return plan.settledAt, plan.duration
end

-- Only the steps that must still happen when a reveal is skipped.
function RewardsLogic.essential(plan: Plan): { Step }
	local kept: { Step } = {}
	for _, step in plan.steps do
		if not step.cosmetic then
			table.insert(kept, step)
		end
	end
	return kept
end

-- Columns for a grid of `count` tiles: near-square, at most 6 wide.
function RewardsLogic.gridColumns(count: number): number
	return math.clamp(math.ceil(math.sqrt(math.max(1, count))), 1, 6)
end

-- Plans a batch of rewards. Each entry is { rarity = ..., reward = ... } or a reward table with a
-- `rarity` field. Rewards are sorted so the rarest is last. Rarities below the threshold are
-- grouped per rarity and shown as a quickly staggered grid; the others get a full reveal each.
-- options.fastForward (true or a factor > 1) compresses time and drops cosmetic steps.
function RewardsLogic.planBatch(rewards: { any }, options: Options?): Batch
	assert(type(rewards) == "table", "rewards must be a list")
	local opts: Options = options or {}
	local speed = speedOf(opts)
	local fast = fastFactor(opts)
	local threshold = RewardsLogic.rank(opts.threshold or "Epic")

	local items: { BatchItem } = {}
	for index, entry in rewards do
		assert(type(entry) == "table", "rewards[" .. tostring(index) .. "] must be a table")
		local rarity = if type(entry.rarity) == "string" and profiles[entry.rarity] then entry.rarity else "Common"
		local reward = if entry.reward ~= nil then entry.reward else entry
		table.insert(items, { index = index, rarity = rarity, reward = reward, rank = profiles[rarity].rank })
	end
	table.sort(items, function(a: BatchItem, b: BatchItem): boolean
		if a.rank == b.rank then
			return a.index < b.index
		end
		return a.rank < b.rank
	end)

	local groups: { Group } = {}
	local cursor = 0
	local current: Group? = nil
	for _, item in items do
		if item.rank < threshold then
			local grid: Group
			if current ~= nil and current.rarity == item.rarity then
				grid = current
			else
				grid = {
					kind = "grid",
					rarity = item.rarity,
					startAt = 0,
					duration = 0,
					items = {} :: { BatchItem },
					stagger = 0,
					columns = 1,
					rows = 1,
					plan = nil :: Plan?,
				}
				table.insert(groups, grid)
				current = grid
			end
			table.insert(grid.items, item)
		else
			current = nil
			local planOptions: Options = table.clone(opts)
			planOptions.speed = speed
			local plan = RewardsLogic.plan(item.rarity, item.reward, planOptions)
			local full: Group = {
				kind = "full",
				rarity = item.rarity,
				startAt = 0,
				duration = plan.settledAt + (plan.dismissAt - plan.settledAt) * 0.5,
				items = { item },
				stagger = 0,
				columns = 1,
				rows = 1,
				plan = plan,
			}
			table.insert(groups, full)
		end
	end

	local scale = speed * fast
	for _, group in groups do
		group.startAt = cursor
		if group.kind == "grid" then
			local count = #group.items
			-- Many tiles reveal faster each, so a big batch never drags: at most ~0.9 s of stagger.
			local stagger = math.clamp(0.9 / count, 0.03, 0.08) / scale
			local columns = if opts.columns and opts.columns >= 1
				then math.floor(opts.columns)
				else RewardsLogic.gridColumns(count)
			group.stagger = stagger
			group.columns = columns
			group.rows = math.ceil(count / columns)
			group.duration = (count - 1) * stagger + (0.3 + 0.5) / scale
		end
		cursor += group.duration
	end

	return { items = items, groups = groups, duration = cursor, fastForward = fast }
end

return RewardsLogic
