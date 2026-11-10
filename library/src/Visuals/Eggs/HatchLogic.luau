--!strict
-- Egg hatch timeline (pure Luau). plan() turns a list of eggs into the eleven beats of a hatch,
-- the timed steps Eggs.luau executes, a layout slot per egg and a wobble curve per egg.
--
-- Beats:  1 enter      egg drops in and squashes on landing
--         2 settle
--         3 anticipation  small wobbles begin
--         4 wobble     shakes ramp in amplitude and frequency; each has a sound cue and dust
--         5 energy     glow and energy build, the camera pushes in, a rising sound
--         6 crack      shell cracks, the egg pops and vanishes
--         7 transition bloom; a 60-100 ms hit-stop for Epic and above
--         8 appear     the pet scales in with overshoot and a spin
--         9 rarity     rays, label, aura, shake, fireworks (from the Rewards profile)
--        10 result     name, rarity badge, NEW tag, continue
--        11 finish     everything fades and is destroyed, the camera is restored
--
-- Times in a Plan are seconds from the start, already divided by options.speed.

local RewardsLogic = require("../Rewards/RewardsLogic")

export type Options = {
	mode: string?, -- "single" | "triple" | "multi" | "auto" (default: from the egg count)
	speed: number?,
	aspect: number?, -- viewport width / height (default 16 / 9)
	reducedMotion: boolean?,
	reducedFlashing: boolean?,
	quality: string?,
	hold: number?, -- seconds the result stays before it continues by itself
	camera: boolean?, -- default true
}

export type Slot = { x: number, y: number, size: number }

export type Layout = { kind: string, columns: number, rows: number, cell: number, slots: { Slot } }

export type Beat = { index: number, name: string, start: number, duration: number }

export type Step = {
	time: number,
	kind: string,
	beat: number,
	egg: number?, -- index into the eggs given to plan()
	essential: boolean, -- still applied when the hatch is skipped
	duration: number?,
	payload: { [string]: any },
}

export type EggPlan = {
	index: number, -- position in the eggs given to plan()
	order: number, -- 1 = revealed first
	rarity: string,
	rank: number,
	slot: Slot,
	wobbleStart: number,
	crackAt: number,
	appearAt: number,
	hitStop: number,
	shakes: { number }, -- times of the shakes
	amplitude: number, -- degrees of the strongest shake
	timeScale: number, -- the plan's speed, for the wobble sampler
}

export type Plan = {
	mode: string,
	count: number,
	top: string, -- the rarest rarity in the batch
	speed: number,
	beats: { Beat },
	steps: { Step },
	eggs: { EggPlan }, -- same order as the input
	order: { number }, -- input indices in reveal order (rarest last)
	layout: Layout,
	stagger: number, -- seconds between reveals
	resultAt: number,
	hold: number,
	finishAt: number,
	finishDuration: number,
	duration: number,
}

local HatchLogic = {}

HatchLogic.BEATS = table.freeze({
	"enter",
	"settle",
	"anticipation",
	"wobble",
	"energy",
	"crack",
	"transition",
	"appear",
	"rarity",
	"result",
	"finish",
})

-- Seconds from the start to the result for a single egg, by rarity rank 1..7.
local TOTALS = { 2.2, 2.7, 3.3, 4.0, 4.7, 5.5, 5.7 }

local AUTO = {
	enter = 0.12,
	settle = 0.04,
	anticipation = 0.08,
	wobble = 0.2,
	energy = 0.1,
	crack = 0.08,
	transition = 0.03,
	appear = 0.2,
	rarity = 0.1,
	finish = 0.1,
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Seconds a single hatch of this rank takes to reach its result (before speed and mode).
function HatchLogic.total(rank: number): number
	local r = math.clamp(rank, 1, #TOTALS)
	local low = math.floor(r)
	local high = math.min(#TOTALS, low + 1)
	return TOTALS[low] + (TOTALS[high] - TOTALS[low]) * (r - low)
end

-- Hit-stop after the crack: none below Epic, then 60, 80 and 100 ms.
function HatchLogic.hitStop(rank: number): number
	if rank < 4 then
		return 0
	end
	return math.clamp(0.06 + 0.02 * (math.floor(rank) - 4), 0.06, 0.1)
end

function HatchLogic.mode(count: number, requested: string?): string
	if requested == "auto" then
		return "auto"
	end
	if count <= 1 then
		return "single"
	elseif count <= 3 then
		return "triple"
	end
	return "multi"
end

-- Lays `count` eggs out in a frame `aspect` wide and 1 tall, centred on (0, 0) with y up. A row
-- for one or two eggs, a shallow arc for a single row of three or more, otherwise a grid whose
-- last row is centred. Slots never overlap and always fit the frame.
function HatchLogic.layout(count: number, aspect: number?): Layout
	local n = math.max(1, math.floor(count))
	local ratio = if aspect and finite(aspect) and aspect > 0 then math.clamp(aspect, 0.3, 4) else 16 / 9
	local width = ratio * 0.9
	local height = 0.62
	local bestColumns, bestCell = 1, 0
	for columns = 1, n do
		local rows = math.ceil(n / columns)
		local cell = math.min(width / columns, height / rows)
		if cell > bestCell + 1e-9 then
			bestColumns, bestCell = columns, cell
		end
	end
	local columns = bestColumns
	local rows = math.ceil(n / columns)
	local kind = if rows > 1 then "grid" elseif n >= 3 then "arc" else "row"
	local cell = math.min(bestCell, 0.5)
	if kind == "arc" then
		cell = math.min(cell, height * 0.8)
	end
	local size = cell * 0.82
	local centerY = 0.04
	local slots: { Slot } = {}
	for index = 1, n do
		local row = math.floor((index - 1) / columns)
		local column = (index - 1) % columns
		local inRow = if row == rows - 1 then n - row * columns else columns
		local x = (column - (inRow - 1) / 2) * cell
		local y = centerY + ((rows - 1) / 2 - row) * cell
		if kind == "arc" then
			-- The middle of the arc sits a little further back (higher), the ends lower.
			local u = if inRow > 1 then (column / (inRow - 1)) * 2 - 1 else 0
			y += cell * 0.1 * (0.5 - u * u)
		end
		table.insert(slots, { x = x, y = y, size = size })
	end
	return { kind = kind, columns = columns, rows = rows, cell = cell, slots = slots }
end

-- Rotation of an egg in degrees at time `t` (plan time). Zero before the anticipation, then a
-- small sway that grows, plus one damped oscillation per shake, each stronger and faster than
-- the one before. It eases to exactly zero at the crack.
function HatchLogic.wobble(egg: EggPlan, t: number): number
	if t <= egg.wobbleStart or t >= egg.crackAt then
		return 0
	end
	local scale = egg.timeScale
	local span = egg.crackAt - egg.wobbleStart
	local progress = (t - egg.wobbleStart) / span
	local angle = egg.amplitude * 0.12 * progress * math.sin((t - egg.wobbleStart) * scale * math.pi * 2 * 2.2)
	local count = #egg.shakes
	for index, at in egg.shakes do
		if t >= at then
			local since = (t - at) * scale
			local strength = egg.amplitude * (0.35 + 0.65 * index / count)
			local hertz = 5 + 4 * (index - 1) / math.max(1, count - 1)
			angle += strength * math.exp(-7 * since) * math.sin(since * math.pi * 2 * hertz)
		end
	end
	local taper = math.clamp((egg.crackAt - t) * scale / 0.06, 0, 1)
	return angle * taper
end

export type IdleOptions = {
	period: number?, -- seconds per sway (default 2.4)
	angle: number?, -- degrees (default 4)
	hopEvery: number?, -- seconds between hops (default 3.2); 0 disables hops
	hopTime: number?, -- seconds a hop lasts (default 0.45)
	hopHeight: number?, -- as a fraction of the egg's height (default 0.08)
	phase: number?, -- seconds of offset, so eggs on a shelf do not move in unison
}

export type IdlePose = { angle: number, offset: number, squash: number }

-- Pose of an egg on display at time `t`: a gentle sway, and every few seconds a small hop with a
-- crouch before it and a squash on landing. `squash` is the vertical scale (1 = rest).
function HatchLogic.idle(t: number, options: IdleOptions?): IdlePose
	local opts: IdleOptions = options or {}
	local time = t + (opts.phase or 0)
	local period = math.max(0.2, opts.period or 2.4)
	local angle = (opts.angle or 4) * math.sin(time * math.pi * 2 / period)
	local hopEvery = opts.hopEvery or 3.2
	local offset, squash = 0, 1
	if hopEvery > 0 then
		local hopTime = math.clamp(opts.hopTime or 0.45, 0.1, hopEvery)
		local crouch = 0.12
		local land = 0.14
		local cycle = time % (hopEvery + crouch + land)
		if cycle < crouch then
			squash = 1 - 0.06 * math.sin(math.pi * cycle / crouch)
		elseif cycle < crouch + hopTime then
			local u = (cycle - crouch) / hopTime
			offset = (opts.hopHeight or 0.08) * math.sin(math.pi * u)
			squash = 1 + 0.05 * math.sin(math.pi * u)
		elseif cycle < crouch + hopTime + land then
			squash = 1 - 0.08 * math.sin(math.pi * (cycle - crouch - hopTime) / land)
		end
	end
	return { angle = angle, offset = offset, squash = squash }
end

-- VFX presets (HatchBurst, RarityBurst, RarityBeam, RarityAura) only accept the seven built-in
-- rarity names for their `rarity` param. A custom rarity uses the built-in tier nearest its rank;
-- its own colour is still passed alongside.
local function vfxRarity(rarity: string, rank: number): string
	if table.find(RewardsLogic.ORDER, rarity) ~= nil then
		return rarity
	end
	return RewardsLogic.ORDER[math.clamp(math.floor(rank + 0.5), 1, #RewardsLogic.ORDER)]
end

-- Builds the hatch plan for `eggs` (each a table with a `rarity`; unknown rarities are Common).
function HatchLogic.plan(eggs: { any }, options: Options?): Plan
	assert(type(eggs) == "table" and #eggs >= 1, "eggs must be a list with at least one egg")
	local opts: Options = options or {}
	local count = #eggs
	local mode = HatchLogic.mode(count, opts.mode)
	local auto = mode == "auto"
	local speed = if opts.speed and finite(opts.speed) and opts.speed > 0 then math.clamp(opts.speed, 0.1, 10) else 1
	local reducedMotion = opts.reducedMotion == true
	local low = opts.quality == "Low"
	local compact = mode == "multi" or auto
	local useCamera = opts.camera ~= false and not reducedMotion and not auto

	-- Reveal order: rarest last, input order within a rarity.
	type Entry = { index: number, rarity: string, rank: number }
	local entries: { Entry } = {}
	for index, egg in eggs do
		assert(type(egg) == "table", "eggs[" .. tostring(index) .. "] must be a table")
		local rarity = if RewardsLogic.has(egg.rarity) then egg.rarity else "Common"
		table.insert(entries, { index = index, rarity = rarity, rank = RewardsLogic.rank(rarity) })
	end
	local sorted = table.clone(entries)
	table.sort(sorted, function(a: Entry, b: Entry): boolean
		if a.rank == b.rank then
			return a.index < b.index
		end
		return a.rank < b.rank
	end)
	local top = sorted[count]

	-- Beat durations (before speed).
	local enter, settle, anticipation, wobble, energy, crack, transition, appear, rarityTime, finishTime
	local stagger = 0
	if auto then
		enter, settle, anticipation, wobble, energy =
			AUTO.enter, AUTO.settle, AUTO.anticipation, AUTO.wobble, AUTO.energy
		crack, transition, appear, rarityTime, finishTime =
			AUTO.crack, AUTO.transition, AUTO.appear, AUTO.rarity, AUTO.finish
		if count > 1 then
			stagger = math.min(0.03, 0.15 / (count - 1))
		end
	else
		local factor = if mode == "single" then 1 elseif mode == "triple" then 0.85 else 0.7
		if mode == "multi" and low then
			factor *= 0.85
		end
		if reducedMotion then
			factor *= 0.75
		end
		enter, settle, crack, appear, finishTime = 0.35, 0.12, 0.14, 0.4, 0.3
		transition = 0.05 + HatchLogic.hitStop(top.rank)
		local fixed = enter + settle + crack + transition + appear * 0.6
		local rest = math.max(0.5, HatchLogic.total(top.rank) * factor - fixed)
		anticipation, wobble, energy, rarityTime = rest * 0.18, rest * 0.42, rest * 0.22, rest * 0.18
		if count > 1 then
			stagger = math.clamp(1.6 / count, 0.12, 0.2)
		end
	end

	local tSettle = enter
	local tAnticipation = tSettle + settle
	local tWobble = tAnticipation + anticipation
	local tEnergy = tWobble + wobble
	local tCrack = tEnergy + energy

	local layout = HatchLogic.layout(count, opts.aspect)
	local steps: { Step } = {}
	local added: { [Step]: number } = {}
	local function add(
		time: number,
		kind: string,
		beat: number,
		egg: number?,
		essential: boolean,
		payload: { [string]: any },
		duration: number?
	)
		local step: Step = {
			time = time / speed,
			kind = kind,
			beat = beat,
			egg = egg,
			essential = essential,
			payload = payload,
			duration = if duration then duration / speed else nil,
		}
		table.insert(steps, step)
		added[step] = #steps
	end

	local plans: { EggPlan } = {}
	local order: { number } = {}
	local wobbleOffset = if count > 1 then math.min(0.05, 0.4 / (count - 1)) else 0
	local enterOffset = if count > 1 then math.min(0.04, 0.2 / (count - 1)) else 0
	local lastAppear = 0

	for position, entry in sorted do
		local k = position - 1
		local profile = RewardsLogic.get(entry.rarity)
		local hitStop = if auto then 0 else HatchLogic.hitStop(entry.rank)
		local crackAt = tCrack + k * stagger
		local appearAt = crackAt + crack + (if auto then transition else 0.05 + hitStop)
		lastAppear = appearAt
		local isLast = position == count

		local shakeCount = if auto
			then 2
			elseif compact then math.min(4, 2 + math.floor(entry.rank))
			else 2 + math.floor(entry.rank)
		local shakeStart = tWobble + k * wobbleOffset
		local shakeSpan = math.max(0.05, crackAt - 0.08 - shakeStart)
		local shakes: { number } = {}
		for j = 0, shakeCount - 1 do
			-- Shakes come closer together towards the crack.
			local at = shakeStart + shakeSpan * (1 - (1 - j / shakeCount) ^ 1.6)
			table.insert(shakes, at / speed)
			add(at, "shake", if at < tEnergy then 4 else 5, entry.index, false, {
				shake = j + 1,
				count = shakeCount,
				cue = "egg.wobble",
				pitch = 1 + 0.5 * j / shakeCount,
				vfx = if (compact or low) and j < shakeCount - 1 then nil else "EggShakeDust",
			})
		end

		local eggPlan: EggPlan = {
			index = entry.index,
			order = position,
			rarity = entry.rarity,
			rank = entry.rank,
			slot = layout.slots[entry.index],
			wobbleStart = (tAnticipation + k * wobbleOffset) / speed,
			crackAt = crackAt / speed,
			appearAt = appearAt / speed,
			hitStop = hitStop / speed,
			shakes = shakes,
			amplitude = (8 + 2 * math.min(entry.rank, 7)) * (if reducedMotion then 0.3 else 1),
			timeScale = speed,
		}
		plans[entry.index] = eggPlan
		table.insert(order, entry.index)

		add(k * enterOffset, "enter", 1, entry.index, false, { slot = eggPlan.slot }, enter * 0.8)
		add(k * enterOffset + enter * 0.8, "land", 1, entry.index, false, {
			cue = if k == 0 or not compact then "egg.land" else nil,
			vfx = if compact or low then nil else "EggShakeDust",
			squash = 0.22,
		}, enter * 0.2 + settle)

		add(crackAt, "crack", 6, entry.index, false, {
			vfx = "EggCrack",
			flash = "EggFlash",
			cue = "egg.crack",
			color = profile.color,
		}, crack)
		if not auto then
			if not opts.reducedFlashing and (isLast or not compact) then
				add(crackAt + crack, "bloom", 7, entry.index, false, {
					color = if entry.rank >= 4 then profile.glow else "#FFFFFF",
					strength = math.clamp(0.25 + 0.05 * entry.rank, 0.25, 0.6),
				}, 0.05 + hitStop + 0.2)
			end
			if hitStop > 0 then
				add(crackAt + crack + 0.05, "hitStop", 7, entry.index, false, {}, hitStop)
			end
		end
		add(appearAt, "appear", 8, entry.index, true, {
			spring = if entry.rank >= 4 then "Elastic" else "Overshoot",
			spin = if reducedMotion then 0 elseif entry.rank >= 5 then 720 else 360,
			vfx = "HatchBurst",
			params = {
				rarity = vfxRarity(entry.rarity, entry.rank),
				color = profile.color,
				intensity = profile.particles,
			},
			cue = "egg.reveal",
			rarityCue = if isLast or not compact then "rarity." .. string.lower(entry.rarity) else nil,
		}, appear)
		add(appearAt, "revealed", 8, entry.index, true, { rarity = entry.rarity })
		if not auto then
			add(appearAt + appear * 0.6, "react", 8, entry.index, false, { reaction = "HappyReaction" })
		end

		-- Rarity effects come from the Rewards profile. In a compact hatch only the rarer pets
		-- get them, and only the last one celebrates, so many eggs never clutter the screen.
		local wantsRarity = if auto then entry.rank >= 5 and isLast elseif compact then entry.rank >= 3 else true
		if wantsRarity then
			local celebrate: { string } = {}
			if entry.rank >= 5 and isLast and not low then
				celebrate = { "Fireworks", "Confetti" }
			elseif entry.rank >= 5 and isLast then
				celebrate = { "Confetti" }
			end
			add(appearAt + appear * 0.6, "rarity", 9, entry.index, false, {
				rarity = entry.rarity,
				vfxRarity = vfxRarity(entry.rarity, entry.rank),
				label = profile.label,
				color = profile.color,
				rays = if entry.rank >= 4 and not compact then profile.rayCount else 0,
				aura = if entry.rank >= 3 and not (compact and low) then "RarityAura" else nil,
				shake = if useCamera and isLast then profile.camera.shake else nil,
				celebrate = celebrate,
			}, rarityTime)
		end
	end

	add(tAnticipation, "anticipate", 3, nil, false, {}, tCrack - tAnticipation)
	if not auto then
		add(tEnergy, "energy", 5, nil, false, {
			vfx = if compact and low then nil else "EggEnergy",
			light = not low,
			intensity = math.clamp(0.4 + 0.12 * top.rank, 0.4, 1.3),
			cue = "egg.energy",
		}, tCrack - tEnergy)
		if useCamera then
			add(0, "cameraLand", 1, nil, false, { shake = "Landing", at = enter * 0.8 })
			add(tEnergy, "cameraPush", 5, nil, false, { cinematic = "PetReveal" }, tCrack - tEnergy)
		end
	end

	local rarityStart = lastAppear + appear * 0.6
	local resultAt = rarityStart + rarityTime
	local hold = if auto then 0 elseif opts.hold and finite(opts.hold) then math.max(0, opts.hold) else 2.5
	local finishAt = resultAt + hold
	add(resultAt, "result", 10, nil, true, { hold = hold, auto = auto })
	add(finishAt, "finish", 11, nil, true, {}, finishTime)

	table.sort(steps, function(a: Step, b: Step): boolean
		if a.time == b.time then
			return added[a] < added[b]
		end
		return a.time < b.time
	end)

	local firstAppear = tCrack + crack + (if auto then transition else 0.05 + HatchLogic.hitStop(sorted[1].rank))
	local starts = {
		0,
		tSettle,
		tAnticipation,
		tWobble,
		tEnergy,
		tCrack,
		tCrack + crack,
		firstAppear,
		rarityStart,
		resultAt,
		finishAt,
	}
	local durations = {
		enter,
		settle,
		anticipation,
		wobble,
		energy,
		crack + (count - 1) * stagger,
		lastAppear - (tCrack + crack),
		lastAppear + appear - firstAppear,
		rarityTime,
		hold,
		finishTime,
	}
	local beats: { Beat } = {}
	for index, name in HatchLogic.BEATS do
		table.insert(
			beats,
			{ index = index, name = name, start = starts[index] / speed, duration = durations[index] / speed }
		)
	end

	return {
		mode = mode,
		count = count,
		top = top.rarity,
		speed = speed,
		beats = beats,
		steps = steps,
		eggs = plans,
		order = order,
		layout = layout,
		stagger = stagger / speed,
		resultAt = resultAt / speed,
		hold = hold / speed,
		finishAt = finishAt / speed,
		finishDuration = finishTime / speed,
		duration = (finishAt + finishTime) / speed,
	}
end

-- The steps that are still applied when a hatch is skipped: every pet appears in its final
-- state and is announced, then the result is shown. Finishing stays a separate, later step.
function HatchLogic.skipSteps(plan: Plan): { Step }
	local kept: { Step } = {}
	for _, step in plan.steps do
		if step.essential and step.kind ~= "finish" then
			table.insert(kept, step)
		end
	end
	return kept
end

return HatchLogic
