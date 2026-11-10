--!strict
-- Spring presets and an exact damped-spring integrator (pure Luau). The step uses the closed-form
-- solution of the damped harmonic oscillator, so it is stable at any frame rate and two devices
-- with different frame times draw the same curve.
--
-- frequency: oscillations per second. damping: 1 is critically damped (no overshoot), below 1
-- bounces, above 1 is sluggish.

export type Spring = { frequency: number, damping: number }

local Springs = {}

local PRESETS: { [string]: Spring } = {
	Gentle = { frequency = 2, damping = 1 }, -- settles without overshoot; panels, large surfaces
	Soft = { frequency = 2.6, damping = 0.82 }, -- a hint of overshoot; cards, tooltips
	Snappy = { frequency = 6.5, damping = 0.9 }, -- fast and tight; hover, toggles, tabs
	Bouncy = { frequency = 4.6, damping = 0.45 }, -- two visible bounces; buttons, rewards
	Elastic = { frequency = 5.2, damping = 0.24 }, -- long ringing; attention and error wobble
	Overshoot = { frequency = 5, damping = 0.6 }, -- one clear overshoot; pop-ins
	Heavy = { frequency = 1.7, damping = 1.25 }, -- slow, weighty; big chests, boss UI
	Playful = { frequency = 3.8, damping = 0.36 }, -- loose cartoon wobble; pets, eggs
	Premium = { frequency = 3.2, damping = 0.78 }, -- smooth with a soft landing; shop and luxury UI
	Cinematic = { frequency = 1.15, damping = 1 }, -- slow ease for cameras and reveals
}
for _, preset in PRESETS do
	table.freeze(preset)
end

Springs.NAMES = table.freeze({
	"Gentle",
	"Soft",
	"Snappy",
	"Bouncy",
	"Elastic",
	"Overshoot",
	"Heavy",
	"Playful",
	"Premium",
	"Cinematic",
})

function Springs.has(name: string): boolean
	return PRESETS[name] ~= nil
end

-- A preset by name, or the table itself when a custom { frequency, damping } is passed.
function Springs.get(spring: (string | Spring)?): Spring
	if type(spring) == "table" then
		return {
			frequency = math.max(0.01, spring.frequency or 4),
			damping = math.max(0, spring.damping or 1),
		}
	end
	local preset = PRESETS[spring or "Soft"]
	if preset == nil then
		error("unknown spring preset: " .. tostring(spring), 2)
	end
	return preset
end

-- Registers or replaces a named preset (for a game's own feel).
function Springs.register(name: string, spring: Spring)
	assert(type(name) == "string" and name ~= "", "spring name required")
	assert(type(spring.frequency) == "number" and spring.frequency > 0, "frequency must be positive")
	assert(type(spring.damping) == "number" and spring.damping >= 0, "damping must be 0 or more")
	local preset: Spring = { frequency = spring.frequency, damping = spring.damping }
	PRESETS[name] = table.freeze(preset) :: any
end

-- Advances one value by dt seconds. Returns the new position and velocity.
function Springs.step(position: number, velocity: number, target: number, dt: number, spring: Spring): (number, number)
	if dt <= 0 then
		return position, velocity
	end
	local omega = 2 * math.pi * spring.frequency
	local zeta = spring.damping
	local offset = position - target
	if zeta < 1 then
		local damped = omega * math.sqrt(1 - zeta * zeta)
		local decay = math.exp(-zeta * omega * dt)
		local cos, sin = math.cos(damped * dt), math.sin(damped * dt)
		local b = (velocity + zeta * omega * offset) / damped
		local newPosition = target + decay * (offset * cos + b * sin)
		local newVelocity = decay
			* ((b * damped - zeta * omega * offset) * cos - (offset * damped + zeta * omega * b) * sin)
		return newPosition, newVelocity
	elseif zeta == 1 then
		local decay = math.exp(-omega * dt)
		local b = velocity + omega * offset
		return target + decay * (offset + b * dt), decay * (velocity - omega * b * dt)
	end
	local root = math.sqrt(zeta * zeta - 1)
	local r1 = -omega * (zeta - root)
	local r2 = -omega * (zeta + root)
	local c2 = (velocity - r1 * offset) / (r2 - r1)
	local c1 = offset - c2
	local e1, e2 = math.exp(r1 * dt), math.exp(r2 * dt)
	return target + c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2
end

function Springs.settled(position: number, velocity: number, target: number, epsilon: number?): boolean
	local limit = epsilon or 1e-3
	return math.abs(position - target) < limit and math.abs(velocity) < limit * 10
end

-- Seconds until the spring stays within `epsilon` of its target after a unit displacement (an
-- estimate from the decay envelope; used for sequence timing and tests).
function Springs.settleTime(spring: (string | Spring)?, epsilon: number?): number
	local resolved = Springs.get(spring)
	local limit = epsilon or 1e-3
	local omega = 2 * math.pi * resolved.frequency
	local zeta = resolved.damping
	local rate = if zeta <= 1 then zeta * omega else omega * (zeta - math.sqrt(zeta * zeta - 1))
	if rate <= 0 then
		return math.huge
	end
	return -math.log(limit) / rate
end

return Springs
